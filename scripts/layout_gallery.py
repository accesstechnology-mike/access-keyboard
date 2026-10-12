#!/usr/bin/env python3
"""Alternative layout gallery for access: keyboard.

This machine has no Xcode and no iOS Simulator, so these PNGs are not device
captures. Key rows, colours, and frames are taken from AccessKeyboardCore
(LayoutFactory, KeyboardGeometry, LayoutMetrics, KeyboardAppearance,
AccessColouring, BethColorMap, PredictionBarGeometry, PredictionColumnGeometry).
SF Symbols and the San Francisco font are drawn with stand-in shapes and
DejaVu; letters use the bundled Andika font.

The script refuses to run if the Swift sources no longer contain the literals
it parses. It does not change keyboard behaviour.
"""

from __future__ import annotations

import argparse
import math
import os
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "Packages/AccessKeyboardCore/Sources/AccessKeyboardCore"
FONT_ANDIKA = CORE / "Resources/Fonts/Andika-Regular.ttf"
WORD_LIST = CORE / "Resources/google-10000-english-usa.txt"
FONT_UI = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
FONT_UI_BOLD = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")

# UIColor.systemBlue cannot be resolved without UIKit. These are Apple's
# documented sRGB values for the light and dark dynamic colours.
SYSTEM_BLUE_LIGHT = (0, 122, 255, 255)
SYSTEM_BLUE_DARK = (10, 132, 255, 255)

THEMES = (
    "system-light",
    "beth",
    "vowels",
    "system-dark",
    "hc-white",
    "hc-yellow",
)
LAYOUT_ORDER = ("qwerty", "abc", "hifreq")
SUB_ORDER = (
    "letters",
    "letters-shift",
    "letters-caps",
    "letters-autoshift",
    "numbers",
    "symbols",
)
SHIFT_FOR_SUB = {
    "letters": "off",
    "letters-shift": "shifted",
    "letters-caps": "capsLock",
    "letters-autoshift": "autoShifted",
    "numbers": "off",
    "symbols": "off",
}
MODE_FOR_SUB = {
    "letters": "alphabetic",
    "letters-shift": "alphabetic",
    "letters-caps": "alphabetic",
    "letters-autoshift": "alphabetic",
    "numbers": "numeric",
    "symbols": "symbols",
}


def swift_rounded(value: float) -> float:
    """Swift FloatingPoint.rounded() for positive numbers: half away from zero."""
    return math.floor(value + 0.5)


def read(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"missing source file: {path}")
    return path.read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def case_block(text: str, label: str, end_marker: str) -> str:
    token = f"case .{label}:"
    start = text.find(token)
    require(start >= 0, f"Swift source is missing `{token}`")
    end = text.find(end_marker, start + len(token))
    require(end > start, f"Swift source is missing `{end_marker}` after `{token}`")
    return text[start:end]


def parse_float_field(block: str, name: str) -> float:
    token = f"{name}:"
    index = block.find(token)
    require(index >= 0, f"metrics block missing {name}")
    rest = block[index + len(token):].lstrip()
    number = []
    for char in rest:
        if char.isdigit() or char == ".":
            number.append(char)
        else:
            break
    require(bool(number), f"metrics block missing a number for {name}")
    return float("".join(number))


def parse_max_floor(block: str, name: str) -> float:
    token = f"{name}: max("
    index = block.find(token)
    require(index >= 0, f"metrics block missing {name}: max(")
    rest = block[index + len(token):]
    number = []
    for char in rest:
        if char.isdigit() or char == ".":
            number.append(char)
        else:
            break
    require(bool(number), f"metrics block missing a floor for {name}")
    return float("".join(number))


def parse_landscape_pair(block: str, name: str) -> tuple[float, float]:
    token = f"{name}: landscape ?"
    index = block.find(token)
    require(index >= 0, f"metrics block missing landscape pair for {name}")
    rest = block[index + len(token):]
    parts = rest.split(":", 1)
    require(len(parts) == 2, f"could not parse landscape pair for {name}")
    landscape = float(parts[0].strip())
    portrait_token = parts[1].lstrip()
    number = []
    for char in portrait_token:
        if char.isdigit() or char == ".":
            number.append(char)
        else:
            break
    require(bool(number), f"could not parse portrait value for {name}")
    return landscape, float("".join(number))


@dataclass
class MetricsSpec:
    side_inset: float
    top_inset: float
    bottom_floor: float
    key_spacing: float
    row_spacing: float
    key_height_landscape: float
    key_height_portrait: float
    prediction_bar_height: float
    corner_radius: float
    letter_font_size: float
    modifier_font_size: float
    symbol_point_size: float
    row_count: int


def parse_metrics_block(block: str, landscape_pair: bool) -> MetricsSpec:
    if landscape_pair:
        key_landscape, key_portrait = parse_landscape_pair(block, "keyHeight")
    else:
        key_landscape = key_portrait = parse_float_field(block, "keyHeight")
    return MetricsSpec(
        side_inset=parse_float_field(block, "sideInset"),
        top_inset=parse_float_field(block, "topInset"),
        bottom_floor=parse_max_floor(block, "bottomInset"),
        key_spacing=parse_float_field(block, "keySpacing"),
        row_spacing=parse_float_field(block, "rowSpacing"),
        key_height_landscape=key_landscape,
        key_height_portrait=key_portrait,
        prediction_bar_height=parse_float_field(block, "predictionBarHeight"),
        corner_radius=parse_float_field(block, "cornerRadius"),
        letter_font_size=parse_float_field(block, "letterFontSize"),
        modifier_font_size=parse_float_field(block, "modifierFontSize"),
        symbol_point_size=parse_float_field(block, "symbolPointSize"),
        row_count=int(parse_float_field(block, "rowCount")),
    )


def parse_layout_metrics(text: str) -> dict[str, MetricsSpec]:
    compact = case_block(text, "compact", "case .iPad:")
    ipad = case_block(text, "iPad", "case .iPadPro:")
    pro = case_block(text, "iPadPro", "if let rowCount")
    return {
        "compact": parse_metrics_block(compact, False),
        "iPad": parse_metrics_block(ipad, True),
        "iPadPro": parse_metrics_block(pro, True),
    }


def parse_thresholds(text: str) -> tuple[float, float]:
    narrow = "if size.width < "
    wide = "if size.width >= "
    n = text.find(narrow)
    w = text.find(wide)
    require(n >= 0 and w >= 0, "LayoutClassResolver thresholds missing")

    def number_at(index: int, token: str) -> float:
        rest = text[index + len(token):]
        digits = []
        for char in rest:
            if char.isdigit() or char == ".":
                digits.append(char)
            else:
                break
        require(bool(digits), f"missing number after {token}")
        return float("".join(digits))

    return number_at(n, narrow), number_at(w, wide)


def parse_letter_maps(text: str) -> dict[str, tuple[str, str, str]]:
    maps = {}
    for name in ("qwerty", "abc"):
        token = f'case .{name}:\n            return ("'
        index = text.find(token)
        require(index >= 0, f"LetterMaps missing {name}")
        rest = text[index + len(token):]
        parts = rest.split('")', 1)[0].split('", "')
        require(len(parts) == 3, f"LetterMaps {name} is not a 3-tuple")
        maps[name] = (parts[0], parts[1], parts[2])
    return maps


def parse_frequency_rows(text: str) -> list[str]:
    token = "public static func frequencyLetterRows()"
    index = text.find(token)
    require(index >= 0, "frequencyLetterRows() missing")
    window = text[index:index + 400]
    rows = []
    cursor = 0
    while True:
        start = window.find('"', cursor)
        if start < 0:
            break
        end = window.find('"', start + 1)
        require(end > start, "unterminated frequency row string")
        rows.append(window[start + 1:end])
        cursor = end + 1
        if len(rows) == 4:
            break
    require(len(rows) == 4, f"expected 4 frequency rows, found {rows}")
    return rows


def swift_strings(body: str) -> list[str]:
    values = []
    index = 0
    while index < len(body):
        if body[index] != '"':
            index += 1
            continue
        index += 1
        chars: list[str] = []
        while index < len(body):
            if body[index] == "\\" and index + 1 < len(body):
                chars.append(body[index + 1])
                index += 2
                continue
            if body[index] == '"':
                index += 1
                break
            chars.append(body[index])
            index += 1
        values.append("".join(chars))
    return values


def parse_string_array(text: str, anchor: str) -> list[str]:
    index = text.find(anchor)
    require(index >= 0, f"missing {anchor}")
    window = text[index:index + 500]
    bracket = window.find("[")
    end = window.find("]", bracket)
    require(bracket >= 0 and end > bracket, f"could not parse array {anchor}")
    values = swift_strings(window[bracket + 1:end])
    require(values, f"empty array {anchor}")
    return values


def parse_frame_references(text: str) -> dict[str, tuple[float, int]]:
    fn = text.find("static func frameReference")
    require(fn >= 0, "frameReference missing")
    window = text[fn:fn + 600]
    refs = {}
    for label in ("compact", "iPad", "iPadPro"):
        token = f"case .{label}: return ("
        index = window.find(token)
        require(index >= 0, f"frame reference missing {label}")
        rest = window[index + len(token):]
        body = rest.split(")", 1)[0]
        weight, count = body.split(",")
        refs[label] = (float(weight.strip()), int(count.strip()))
    return refs


def parse_frequency_columns(text: str) -> dict[str, int]:
    fn = text.find("func frequencyRightColumnCount")
    require(fn >= 0, "frequencyRightColumnCount missing")
    window = text[fn:fn + 400]
    columns = {}
    for label in ("compact", "iPad", "iPadPro"):
        token = f"case .{label}: return "
        index = window.find(token)
        require(index >= 0, f"frequency columns missing {label}")
        rest = window[index + len(token):]
        digits = []
        for char in rest:
            if char.isdigit():
                digits.append(char)
            elif digits:
                break
        require(digits, f"frequency column count missing for {label}")
        columns[label] = int("".join(digits))
    return columns


def parse_hex_colors(text: str) -> dict[str, tuple[int, int, int, int]]:
    colors = {}
    cursor = 0
    while True:
        let = text.find("public static let ", cursor)
        if let < 0:
            break
        rgb = text.find("rgb(0x", let)
        newline = text.find("\n", let)
        if rgb < 0 or (newline >= 0 and rgb > newline + 80):
            cursor = let + 1
            continue
        name = text[let + len("public static let "):text.find(" ", let + len("public static let "))]
        if name.endswith(":"):
            cursor = rgb + 1
            continue
        body = text[rgb + len("rgb("):text.find(")", rgb)]
        parts = [int(part.strip(), 16) for part in body.split(",")]
        require(len(parts) == 3, f"bad rgb for {name}")
        colors[name] = (parts[0], parts[1], parts[2], 255)
        cursor = rgb + 1
    return colors


def parse_beth_fills(text: str) -> dict[str, tuple[int, int, int, int]]:
    fills = {}
    for line in text.splitlines():
        line = line.strip().rstrip(",")
        if not line.startswith('"') or "rgb(0x" not in line:
            continue
        letter = line[1]
        body = line[line.find("rgb(") + 4:line.find(")")]
        parts = [int(part.strip(), 16) for part in body.split(",")]
        require(len(parts) == 3, f"bad Beth colour for {letter}")
        fills[letter] = (parts[0], parts[1], parts[2], 255)
    require(len(fills) == 26, f"BethColorMap parsed {len(fills)} letters, expected 26")
    return fills


def parse_max_suggestions(text: str) -> int:
    token = "static let maxSuggestions = "
    index = text.find(token)
    require(index >= 0, "maxSuggestions missing")
    rest = text[index + len(token):]
    digits = []
    for char in rest:
        if char.isdigit():
            digits.append(char)
        else:
            break
    require(digits, "maxSuggestions has no number")
    return int("".join(digits))


def parse_column_fraction(text: str) -> float:
    token = "static let standardWidthFraction: CGFloat = "
    index = text.find(token)
    require(index >= 0, "standardWidthFraction missing")
    rest = text[index + len(token):]
    number = []
    for char in rest:
        if char.isdigit() or char == ".":
            number.append(char)
        else:
            break
    require(number, "standardWidthFraction has no number")
    return float("".join(number))


def u8(component: float) -> int:
    return max(0, min(255, int(round(component * 255))))


def parse_unit_color(expr: str) -> tuple[int, int, int, int]:
    expr = expr.strip().rstrip(",")
    if expr in (".white", "UIColor.white"):
        return (255, 255, 255, 255)
    if expr in (".black", "UIColor.black"):
        return (0, 0, 0, 255)
    if expr == "UIColor.systemBlue":
        return SYSTEM_BLUE_LIGHT
    if expr.startswith("UIColor(white:"):
        white = float(expr.split("white:")[1].split(",")[0].strip())
        return (u8(white), u8(white), u8(white), 255)
    if expr.startswith("UIColor(red:"):
        body = expr[expr.find("red:") + 4:expr.rfind(")")]
        red_s, rest = body.split("green:")
        green_s, blue_s = rest.split("blue:")
        blue_s = blue_s.split("alpha:")[0]
        return (
            u8(float(red_s.strip().rstrip(","))),
            u8(float(green_s.strip().rstrip(","))),
            u8(float(blue_s.strip().rstrip(","))),
            255,
        )
    if ".withAlphaComponent(" in expr:
        base = expr.split(".withAlphaComponent(")[0].strip()
        alpha = float(expr.split(".withAlphaComponent(")[1].split(")")[0])
        color = parse_unit_color(base)
        return (color[0], color[1], color[2], u8(alpha))
    raise SystemExit(f"unparsed colour expression: {expr}")


def parse_appearance_call(block: str) -> dict[str, tuple[int, int, int, int]]:
    names = [
        "backgroundColor",
        "letterFill",
        "modifierFill",
        "primaryFill",
        "letterPressedFill",
        "modifierPressedFill",
        "textColor",
        "modifierTextColor",
        "primaryTextColor",
        "secondaryTextColor",
        "shadowColor",
        "calloutFill",
    ]
    found = {}
    for name in names:
        token = f"{name}:"
        index = block.find(token)
        require(index >= 0, f"appearance missing {name}")
        rest = block[index + len(token):].lstrip()
        if rest.startswith("UIColor.black.withAlphaComponent"):
            expr = rest.split(")")[0] + ")"
        elif rest.startswith("UIColor("):
            expr = rest[:rest.find(")") + 1]
        elif rest.startswith("UIColor.") or rest.startswith("."):
            expr = rest.split(",")[0].split("\n")[0].strip()
        else:
            raise SystemExit(f"bad appearance value for {name}: {rest[:80]!r}")
        found[name] = parse_unit_color(expr)
    return found


def parse_system_appearances(text: str) -> dict[str, dict[str, tuple[int, int, int, int]]]:
    fn = text.find("public static func system(for style: UIUserInterfaceStyle)")
    require(fn >= 0, "KeyboardAppearance.system missing")
    window = text[fn:text.find("public func fill(", fn)]
    dark = window.find("case .dark:")
    default = window.find("default:")
    require(dark >= 0 and default > dark, "system appearance cases missing")
    dark_colors = parse_appearance_call(window[dark:default])
    light_colors = parse_appearance_call(window[default:])
    # primaryFill is UIColor.systemBlue in both branches. The parser assigns
    # the light sRGB value; replace the dark one explicitly.
    require(dark_colors["primaryFill"] == SYSTEM_BLUE_LIGHT, "expected systemBlue primary on dark")
    dark_colors["primaryFill"] = SYSTEM_BLUE_DARK
    return {"light": light_colors, "dark": dark_colors}


def parse_high_contrast_calls(text: str) -> dict[str, dict[str, str]]:
    """Return the raw argument expressions for the two high-contrast call sites."""
    calls = {}
    for label, token in (
        ("hc-white", "case .highContrastWhite:"),
        ("hc-yellow", "case .highContrastYellow:"),
    ):
        index = text.find(token)
        require(index >= 0, f"missing {token}")
        window = text[index:text.find("appearance.colour", index)]
        args = {}
        for name in ("background", "keyFill", "modifierFill", "text", "primaryFill", "primaryText"):
            key = f"{name}:"
            at = window.find(key)
            require(at >= 0, f"{label} missing {name}")
            rest = window[at + len(key):].lstrip()
            if rest.startswith("UIColor("):
                expr = rest[:rest.find(")") + 1]
            elif rest.startswith("AccessColouring."):
                expr = rest.split(",")[0].split("\n")[0].strip()
            else:
                expr = rest.split(",")[0].split("\n")[0].strip()
            args[name] = expr
        calls[label] = args
    return calls


@dataclass
class Sources:
    metrics: dict[str, MetricsSpec]
    narrow_width: float
    wide_width: float
    letter_maps: dict[str, tuple[str, str, str]]
    frequency_rows: list[str]
    frequency_symbols: list[str]
    frame_reference: dict[str, tuple[float, int]]
    frequency_columns: dict[str, int]
    colouring: dict[str, tuple[int, int, int, int]]
    beth: dict[str, tuple[int, int, int, int]]
    system: dict[str, dict[str, tuple[int, int, int, int]]]
    high_contrast_args: dict[str, dict[str, str]]
    max_suggestions: int
    column_fraction: float


def load_sources() -> Sources:
    metrics_text = read(CORE / "LayoutMetrics.swift")
    resolver_text = read(CORE / "LayoutClass.swift")
    options_text = read(CORE / "AccessOptions.swift")
    factory_text = read(CORE / "LayoutFactory.swift")
    colouring_text = read(CORE / "AccessColouring.swift")
    beth_text = read(CORE / "BethColorMap.swift")
    appearance_text = read(CORE / "KeyboardAppearance.swift")
    provider_text = read(CORE / "PredictionProvider.swift")
    column_text = read(CORE / "PredictionColumnGeometry.swift")
    return Sources(
        metrics=parse_layout_metrics(metrics_text),
        narrow_width=parse_thresholds(resolver_text)[0],
        wide_width=parse_thresholds(resolver_text)[1],
        letter_maps=parse_letter_maps(options_text),
        frequency_rows=parse_frequency_rows(options_text),
        frequency_symbols=parse_string_array(factory_text, "private static let frequencySymbols"),
        frame_reference=parse_frame_references(factory_text),
        frequency_columns=parse_frequency_columns(factory_text),
        colouring=parse_hex_colors(colouring_text),
        beth=parse_beth_fills(beth_text),
        system=parse_system_appearances(appearance_text),
        high_contrast_args=parse_high_contrast_calls(appearance_text),
        max_suggestions=parse_max_suggestions(provider_text),
        column_fraction=parse_column_fraction(column_text),
    )


@dataclass
class Key:
    action: str
    display_kind: str
    display: str
    width: float | None
    style: str
    secondary: str | None = None
    shifted_display: str | None = None
    character: str | None = None


@dataclass
class Board:
    rows: list[list[Key]]
    left_docked: bool
    reference: tuple[float, int] | None
    layout_class: str


def letter_key(text: str) -> Key:
    return Key("character", "text", text, 1.0, "letter", character=text)


def punct_key(value: str, shifted: str | None = None, width: float = 1.0) -> Key:
    return Key(
        "character",
        "text",
        value,
        width,
        "letter",
        shifted_display=shifted,
        character=value,
    )


def modifier(action: str, kind: str, display: str, width: float, style: str = "modifier") -> Key:
    return Key(action, kind, display, width, style)


def flex_space() -> Key:
    return Key("space", "blank", "", None, "space")


def space_cell() -> Key:
    return Key("space", "text", "Space", 1.0, "space")


def letters(sequence: str, shift: str) -> list[Key]:
    upper = shift != "off"
    return [letter_key(ch.upper() if upper else ch) for ch in sequence]


def chars(sequence: str) -> list[Key]:
    return [letter_key(ch) for ch in sequence]


def shift_key(compact: bool, shift: str, width: float = 1.4) -> Key:
    if shift == "capsLock":
        symbol = "capslock.fill"
    elif shift in ("shifted", "autoShifted"):
        symbol = "shift.fill"
    else:
        symbol = "shift"
    if compact:
        return modifier("shift", "symbol", symbol, width)
    return modifier("shift", "text", "shift", width)


def caps_key(width: float = 1.5) -> Key:
    return modifier("capsLock", "text", "caps lock", width)


def backspace(compact: bool, width: float = 1.4) -> Key:
    if compact:
        return modifier("backspace", "symbol", "delete.left", width)
    return modifier("backspace", "text", "delete", width)


def tab_key() -> Key:
    return modifier("tab", "text", "tab", 1.2)


def globe(width: float) -> Key:
    return modifier("nextKeyboard", "symbol", "globe", width)


def dismiss(width: float = 1.2) -> Key:
    return modifier("dismissKeyboard", "symbol", "keyboard.chevron.compact.down", width)


def undo_key() -> Key:
    return modifier("undo", "symbol", "arrow.uturn.backward", 1.1)


def redo_key() -> Key:
    return modifier("redo", "symbol", "arrow.uturn.forward", 1.1)


def mode_key(title: str, mode: str, width: float) -> Key:
    return modifier("setMode", "text", title, width)


def return_key(width: float) -> Key:
    return modifier("returnKey", "text", "return", width)


def number_row(shift: str) -> list[Key]:
    pairs = [
        ("1", "!"), ("2", "@"), ("3", "#"), ("4", "$"), ("5", "%"),
        ("6", "^"), ("7", "&"), ("8", "*"), ("9", "("), ("0", ")"),
        ("-", "_"), ("=", "+"),
    ]
    show_symbol = shift in ("shifted", "capsLock")
    keys = []
    for number, symbol in pairs:
        shown = symbol if show_symbol else number
        other = number if show_symbol else symbol
        keys.append(Key("character", "text", shown, 1.0, "letter", secondary=other, character=shown))
    return keys


def compact_toolbar(mode: str) -> list[Key]:
    title, target = ("123", "numeric") if mode == "alphabetic" else ("ABC", "alphabetic")
    return [mode_key(title, target, 1.5), globe(1.2), flex_space(), return_key(2.2)]


def ipad_toolbar(mode: str, pro: bool) -> list[Key]:
    if mode == "alphabetic":
        keys = [mode_key(".?123", "numeric", 1.4 if pro else 1.5)]
    else:
        keys = [mode_key("ABC", "alphabetic", 1.4 if pro else 1.5)]
    keys.append(globe(1.1))
    if pro:
        keys.append(undo_key())
    keys.append(flex_space())
    if mode == "alphabetic":
        keys.append(mode_key(".?123", "numeric", 1.4))
    else:
        keys.append(mode_key("ABC", "alphabetic", 1.4))
    keys.append(dismiss())
    return keys


def frequency_right(sources: Sources, layout_class: str, compact: bool) -> list[list[Key]]:
    columns = sources.frequency_columns[layout_class]
    row_count = len(sources.frequency_rows)
    functions = [backspace(compact, 1.0), return_key(1.0), mode_key("123", "numeric", 1.0)]
    functions.append(globe(1.0))
    if not compact:
        functions.append(dismiss(1.0))
    total = row_count * columns
    grid: list[Key | None] = [None] * total
    first = min(len(functions), row_count)
    for row in range(first):
        grid[row * columns] = functions[row]
    if len(functions) > row_count:
        tail = total - 1
        for index in range(row_count, len(functions)):
            grid[tail] = functions[index]
            tail -= 1
    symbol_index = 0
    symbols = sources.frequency_symbols
    for cell in range(total):
        if grid[cell] is None:
            grid[cell] = punct_key(symbols[symbol_index % len(symbols)])
            symbol_index += 1
    rows = []
    for row in range(row_count):
        rows.append([grid[row * columns + col] for col in range(columns)])
    return rows


def build_board(sources: Sources, mode: str, shift: str, layout_class: str, letter: str) -> Board:
    compact = layout_class == "compact"
    if mode == "alphabetic" and letter == "hifreq":
        right = frequency_right(sources, layout_class, compact)
        rows = []
        for index, sequence in enumerate(sources.frequency_rows):
            keys: list[Key] = []
            if index == 0:
                keys.append(space_cell())
            keys.extend(letters(sequence, shift))
            if index == len(sources.frequency_rows) - 1:
                keys.append(shift_key(compact, shift, 1.0))
            keys.extend(right[index])
            rows.append(keys)
        return Board(rows, True, None, layout_class)

    reference = sources.frame_reference[layout_class]
    if mode == "alphabetic":
        top, home, bottom = sources.letter_maps[letter]
        if layout_class == "compact":
            rows = [
                letters(top, shift),
                letters(home, shift),
                [shift_key(True, shift)] + letters(bottom, shift) + [backspace(True)],
                compact_toolbar("alphabetic"),
            ]
        elif layout_class == "iPad":
            rows = [
                letters(top, shift) + [backspace(False, 1.5)],
                letters(home, shift) + [punct_key(";", ":"), punct_key("'", '"'), return_key(1.6)],
                [shift_key(False, shift, 1.4), punct_key("`", "~")]
                + letters(bottom, shift)
                + [punct_key(",", "<"), punct_key(".", ">"), punct_key("/", "?"), shift_key(False, shift, 1.4)],
                ipad_toolbar("alphabetic", False),
            ]
        else:
            rows = [
                number_row(shift) + [backspace(False, 1.8)],
                [tab_key()] + letters(top, shift) + [punct_key("[", "{"), punct_key("]", "}"), punct_key("\\", "|")],
                [caps_key()] + letters(home, shift) + [punct_key(";", ":"), punct_key("'", '"'), return_key(1.7)],
                [shift_key(False, shift, 1.5), punct_key("`", "~")]
                + letters(bottom, shift)
                + [punct_key(",", "<"), punct_key(".", ">"), punct_key("/", "?"), shift_key(False, shift, 1.8)],
                ipad_toolbar("alphabetic", True),
            ]
        return Board(rows, False, reference, layout_class)

    if layout_class == "compact":
        if mode == "numeric":
            rows = [
                chars("1234567890"),
                chars('-/:;()$&@"'),
                [mode_key("#+=", "symbols", 1.4)] + chars(".,?!'") + [backspace(True)],
                compact_toolbar("numeric"),
            ]
        else:
            rows = [
                chars("[]{}#%^*+="),
                chars("_\\|~<>€£¥·"),
                [mode_key("123", "numeric", 1.4)] + chars(".,?!'") + [backspace(True)],
                compact_toolbar("symbols"),
            ]
    elif layout_class == "iPad":
        if mode == "numeric":
            rows = [
                chars("1234567890") + [backspace(False, 1.5)],
                chars('-/:;()$&@"') + [return_key(1.6)],
                [mode_key("#+=", "symbols", 1.6)] + chars(".,?!'") + [mode_key("#+=", "symbols", 1.6)],
                ipad_toolbar("numeric", False),
            ]
        else:
            rows = [
                chars("[]{}#%^*+=") + [backspace(False, 1.5)],
                chars("_\\|~<>€£¥·") + [return_key(1.6)],
                [mode_key("123", "numeric", 1.6)] + chars(".,?!'") + [mode_key("123", "numeric", 1.6)],
                ipad_toolbar("symbols", False),
            ]
    else:
        if mode == "numeric":
            rows = [
                chars("1234567890-=") + [backspace(False, 1.8)],
                [undo_key()] + chars('-/:;()$&@"') + [return_key(1.7)],
                [redo_key(), mode_key("#+=", "symbols", 1.4)] + chars(".,?!'_|~") + [mode_key("#+=", "symbols", 1.8)],
                [mode_key("ABC", "alphabetic", 1.5)] + chars("€£¥%…") + [mode_key("ABC", "alphabetic", 1.8)],
                ipad_toolbar("numeric", True),
            ]
        else:
            rows = [
                chars("[]{}#%^*+=•") + [backspace(False, 1.8)],
                [undo_key()] + chars("_\\|~<>€£¥·") + [return_key(1.7)],
                [redo_key(), mode_key("123", "numeric", 1.4)] + chars(".§¡¿–—«»") + [mode_key("123", "numeric", 1.8)],
                [mode_key("ABC", "alphabetic", 1.5)] + chars("°†‡※∞") + [mode_key("ABC", "alphabetic", 1.8)],
                ipad_toolbar("symbols", True),
            ]
    return Board(rows, False, reference, layout_class)


def shown_text(key: Key, shift: str) -> str:
    if shift in ("shifted", "capsLock") and key.shifted_display:
        return key.shifted_display
    return key.display


def highlighted(key: Key, shift: str) -> bool:
    if key.action == "shift":
        return shift != "off"
    if key.action == "capsLock":
        return shift == "capsLock"
    return False


def visual_signature(board: Board, shift: str) -> tuple:
    parts = []
    for row in board.rows:
        row_parts = []
        for key in row:
            row_parts.append((
                shown_text(key, shift),
                key.display_kind,
                key.style,
                key.secondary,
                key.character,
                key.width,
                highlighted(key, shift),
            ))
        parts.append(tuple(row_parts))
    return tuple(parts)


def labels(board: Board, shift: str) -> list[list[str]]:
    return [[shown_text(key, shift) if key.display_kind != "blank" else "" for key in row] for row in board.rows]


@dataclass
class ResolvedMetrics:
    side_inset: float
    top_inset: float
    bottom_inset: float
    key_spacing: float
    row_spacing: float
    key_height: float
    prediction_bar_height: float
    corner_radius: float
    letter_font_size: float
    modifier_font_size: float
    symbol_point_size: float
    row_count: int

    @property
    def preferred_height(self) -> float:
        return (
            self.prediction_bar_height
            + self.top_inset
            + self.row_count * self.key_height
            + max(self.row_count - 1, 0) * self.row_spacing
            + self.bottom_inset
        )


def resolve_class(sources: Sources, width: float, idiom: str) -> str:
    if idiom != "pad":
        return "compact"
    if width < sources.narrow_width:
        return "compact"
    if width >= sources.wide_width:
        return "iPadPro"
    return "iPad"


def resolve_metrics(sources: Sources, layout_class: str, width: float, height: float, safe_bottom: float, row_count: int) -> ResolvedMetrics:
    spec = sources.metrics[layout_class]
    landscape = width > height
    key_height = spec.key_height_landscape if landscape else spec.key_height_portrait
    metrics = ResolvedMetrics(
        side_inset=spec.side_inset,
        top_inset=spec.top_inset,
        bottom_inset=max(spec.bottom_floor, safe_bottom),
        key_spacing=spec.key_spacing,
        row_spacing=spec.row_spacing,
        key_height=key_height,
        prediction_bar_height=spec.prediction_bar_height,
        corner_radius=spec.corner_radius,
        letter_font_size=spec.letter_font_size,
        modifier_font_size=spec.modifier_font_size,
        symbol_point_size=spec.symbol_point_size,
        row_count=spec.row_count,
    )
    if row_count != metrics.row_count:
        scale = metrics.row_count / max(row_count, 1)
        factor = min(1.0, scale * 1.08)
        metrics.key_height = max(50.0, swift_rounded(metrics.key_height * factor))
        metrics.row_spacing = max(8.0, swift_rounded(metrics.row_spacing * min(1.0, scale)))
        metrics.row_count = row_count
    return metrics


def weight_of(key: Key) -> float:
    return 4.5 if key.width is None else key.width


def unit_width(board: Board, usable: float, metrics: ResolvedMetrics) -> float:
    if board.left_docked:
        max_weight = max(sum(weight_of(key) for key in row) for row in board.rows)
        max_count = max(len(row) for row in board.rows)
        gaps = max(max_count - 1, 0) * metrics.key_spacing
        fill = (usable - gaps) / max(max_weight, 1)
        return min(metrics.key_height, fill)
    if board.reference is not None:
        ref_weight, ref_count = board.reference
        gaps = max(ref_count - 1, 0) * metrics.key_spacing
        return (usable - gaps) / max(ref_weight, 1)
    reference = max(board.rows, key=lambda row: sum(weight_of(key) for key in row))
    gaps = max(len(reference) - 1, 0) * metrics.key_spacing
    fixed = sum(weight_of(key) for key in reference)
    return (usable - gaps) / max(fixed, 1)


def frames_for_row(row: list[Key], y: float, usable: float, unit: float, metrics: ResolvedMetrics, content_leading: float, left_docked: bool) -> list[tuple[float, float, float, float]]:
    gap = metrics.key_spacing
    gaps = max(len(row) - 1, 0) * gap
    flexible = sum(1 for key in row if key.width is None)
    fixed = sum(weight_of(key) for key in row if key.width is not None)
    leftover = usable - fixed * unit - gaps
    if flexible:
        flex_width = max(unit, leftover / flexible)
        leading = content_leading
    else:
        flex_width = 0.0
        row_width = fixed * unit + gaps
        if left_docked:
            leading = content_leading
        else:
            leading = content_leading + max(0.0, (usable - row_width) / 2)
    cursor = leading
    frames = []
    for key in row:
        key_width = flex_width if key.width is None else unit * weight_of(key)
        frames.append((cursor, y, key_width, metrics.key_height))
        cursor += key_width + gap
    return frames


def board_frames(board: Board, metrics: ResolvedMetrics, bounds_width: float, reserved_leading: float, reserved_top: float) -> list[list[tuple[float, float, float, float]]]:
    content_leading = metrics.side_inset + max(0.0, reserved_leading)
    usable = bounds_width - content_leading - metrics.side_inset
    unit = unit_width(board, usable, metrics)
    y = metrics.top_inset + max(0.0, reserved_top)
    rows = []
    for row in board.rows:
        rows.append(frames_for_row(row, y, usable, unit, metrics, content_leading, board.left_docked))
        y += metrics.key_height + metrics.row_spacing
    return rows


@dataclass
class Device:
    slug: str
    title: str
    aliases: str
    idiom: str
    portrait: tuple[int, int]
    safe_portrait: float
    safe_landscape: float

    def orientations(self) -> list[tuple[str, int, int, float]]:
        pw, ph = self.portrait
        return [
            ("portrait", pw, ph, self.safe_portrait),
            ("landscape", ph, pw, self.safe_landscape),
        ]


def supported_devices() -> list[Device]:
    """Logical points for devices that run iOS/iPadOS 18.

    Sizes are the public logical resolutions (iosref.com/res, checked
    2026-10-12). A12-and-later devices only: iOS 18 dropped A11 and earlier,
    so iPhone SE (1st), iPhone 8/X, iPad Pro 10.5-inch, iPad mini 4, and
    iPad (6th) are not included. Devices that share a point size are one row;
    aliases name the rest.
    """
    return [
        Device("iphone-se", "iPhone SE (2nd/3rd)", "iPhone SE (2020), iPhone SE (2022)", "phone", (375, 667), 0, 0),
        Device("iphone-13-mini", "iPhone 13 mini", "iPhone 12 mini, iPhone XS, iPhone 11 Pro", "phone", (375, 812), 34, 21),
        Device("iphone-14", "iPhone 14", "iPhone 12, 12 Pro, 13, 13 Pro, 16e, 17e", "phone", (390, 844), 34, 21),
        Device("iphone-16", "iPhone 16", "iPhone 14 Pro, 15, 15 Pro", "phone", (393, 852), 34, 21),
        Device("iphone-17", "iPhone 17", "iPhone 16 Pro, iPhone 17 Pro", "phone", (402, 874), 34, 21),
        Device("iphone-air", "iPhone Air", "", "phone", (420, 912), 34, 21),
        Device("iphone-11", "iPhone 11", "iPhone XR, XS Max, 11 Pro Max", "phone", (414, 896), 34, 21),
        Device("iphone-14-plus", "iPhone 14 Plus", "iPhone 12 Pro Max, 13 Pro Max", "phone", (428, 926), 34, 21),
        Device("iphone-16-plus", "iPhone 16 Plus", "iPhone 14 Pro Max, 15 Plus, 15 Pro Max", "phone", (430, 932), 34, 21),
        Device("iphone-16-pro-max", "iPhone 16 Pro Max", "iPhone 17 Pro Max", "phone", (440, 956), 34, 21),
        Device("ipad-mini-5", "iPad mini (5th)", "home-button mini", "pad", (768, 1024), 0, 0),
        Device("ipad-mini", "iPad mini (6th)", "iPad mini (A17 Pro)", "pad", (744, 1133), 20, 20),
        Device("ipad-9", "iPad (9th)", "iPad (7th), iPad (8th)", "pad", (810, 1080), 0, 0),
        Device("ipad-air-3", "iPad Air (3rd)", "home button, 10.5-inch", "pad", (834, 1112), 0, 0),
        Device("ipad-10", "iPad (10th)", "iPad (A16), iPad Air (4th/5th), iPad Air 11-inch", "pad", (820, 1180), 20, 20),
        Device("ipad-pro-11", "iPad Pro 11-inch (1st–4th)", "", "pad", (834, 1194), 20, 20),
        Device("ipad-pro-11-m4", "iPad Pro 11-inch (M4/M5)", "", "pad", (834, 1210), 20, 20),
        Device("ipad-pro-12-9", "iPad Pro 12.9-inch", "iPad Air 13-inch", "pad", (1024, 1366), 20, 20),
        Device("ipad-pro-13", "iPad Pro 13-inch (M4/M5)", "", "pad", (1032, 1376), 20, 20),
    ]


def theme_for(layout: str, subscreen: str) -> str:
    index = LAYOUT_ORDER.index(layout) * 2 + SUB_ORDER.index(subscreen)
    return THEMES[index % len(THEMES)]


def empty_field_predictions(sources: Sources) -> list[str]:
    words = []
    require(WORD_LIST.is_file(), f"missing word list {WORD_LIST}")
    for line in WORD_LIST.read_text(encoding="utf-8").splitlines():
        word = line.strip().lower()
        if not word:
            continue
        # PredictionProvider.capitalizationHint returns "A" for an empty field,
        # and matchingCase capitalises the first letter.
        words.append(word[:1].upper() + word[1:])
        if len(words) == sources.max_suggestions:
            break
    require(len(words) == sources.max_suggestions, "word list is shorter than maxSuggestions")
    return words


def base_letter(character: str) -> str | None:
    if not character:
        return None
    folded = unicodedata.normalize("NFD", character)
    folded = "".join(ch for ch in folded if unicodedata.category(ch) != "Mn").lower()
    if not folded:
        return None
    letter = folded[0]
    if "a" <= letter <= "z":
        return letter
    return None


def glyph_class(character: str) -> str:
    if not character:
        return "other"
    if character.isdigit() or (len(character) == 1 and unicodedata.category(character) == "Nd"):
        return "number"
    letter = base_letter(character)
    if letter:
        return "vowel" if letter in "aeiou" else "consonant"
    category = unicodedata.category(character[0])
    if category.startswith("P") or category.startswith("S"):
        return "punctuation"
    return "other"


def linearize(component: float) -> float:
    return component / 12.92 if component <= 0.04045 else ((component + 0.055) / 1.055) ** 2.4


def luminance(color: tuple[int, int, int, int]) -> float:
    red, green, blue = [channel / 255 for channel in color[:3]]
    return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)


def contrast(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    lighter = max(luminance(a), luminance(b))
    darker = min(luminance(a), luminance(b))
    return (lighter + 0.05) / (darker + 0.05)


def foreground_on(fill: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    white = (255, 255, 255, 255)
    black = (0, 0, 0, 255)
    return white if contrast(fill, white) >= contrast(fill, black) else black


@dataclass
class Appearance:
    background: tuple[int, int, int, int]
    letter_fill: tuple[int, int, int, int]
    modifier_fill: tuple[int, int, int, int]
    primary_fill: tuple[int, int, int, int]
    text: tuple[int, int, int, int]
    modifier_text: tuple[int, int, int, int]
    primary_text: tuple[int, int, int, int]
    secondary_text: tuple[int, int, int, int]
    shadow: tuple[int, int, int, int]
    colour: str
    beth: dict[str, tuple[int, int, int, int]]
    colouring: dict[str, tuple[int, int, int, int]]

    def decorative(self, key: Key) -> tuple[int, int, int, int] | None:
        if key.style != "letter" or not key.character:
            return None
        if self.colour in ("system", "hc-white", "hc-yellow"):
            return None
        if self.colour == "beth":
            letter = base_letter(key.character)
            return self.beth.get(letter) if letter else None
        if self.colour == "vowels":
            kind = glyph_class(key.character)
            mapping = {
                "vowel": "vowelFill",
                "consonant": "consonantFill",
                "number": "numberFill",
                "punctuation": "punctuationFill",
            }
            name = mapping.get(kind)
            return self.colouring.get(name) if name else None
        return None

    def fill(self, key: Key, shift: str) -> tuple[int, int, int, int]:
        if highlighted(key, shift) and key.style in ("modifier", "primary"):
            return self.letter_fill
        overlay = self.decorative(key)
        if overlay:
            return overlay
        if key.style in ("letter", "space"):
            return self.letter_fill
        if key.style == "primary":
            return self.primary_fill
        return self.modifier_fill

    def foreground(self, key: Key, shift: str) -> tuple[int, int, int, int]:
        overlay = self.decorative(key)
        if overlay and not (highlighted(key, shift) and key.style in ("modifier", "primary")):
            return foreground_on(overlay)
        if key.style == "primary":
            return self.primary_text
        if key.style == "modifier":
            return self.modifier_text
        return self.text


def appearance_for(sources: Sources, theme: str) -> Appearance:
    if theme == "system-dark":
        colors = sources.system["dark"]
        colour = "system"
    elif theme == "system-light":
        colors = sources.system["light"]
        colour = "system"
    elif theme in ("vowels", "beth"):
        colors = sources.system["light"]
        colour = theme
    elif theme == "hc-white":
        args = sources.high_contrast_args["hc-white"]
        colors = _high_contrast_colors(sources, args)
        colour = "hc-white"
    elif theme == "hc-yellow":
        args = sources.high_contrast_args["hc-yellow"]
        colors = _high_contrast_colors(sources, args)
        colour = "hc-yellow"
    else:
        raise SystemExit(f"unknown theme {theme}")
    return Appearance(
        background=colors["backgroundColor"],
        letter_fill=colors["letterFill"],
        modifier_fill=colors["modifierFill"],
        primary_fill=colors["primaryFill"],
        text=colors["textColor"],
        modifier_text=colors["modifierTextColor"],
        primary_text=colors["primaryTextColor"],
        secondary_text=colors["secondaryTextColor"],
        shadow=colors["shadowColor"],
        colour=colour,
        beth=sources.beth,
        colouring=sources.colouring,
    )


def _high_contrast_colors(sources: Sources, args: dict[str, str]) -> dict[str, tuple[int, int, int, int]]:
    def color_of(expr: str) -> tuple[int, int, int, int]:
        if expr.startswith("AccessColouring."):
            name = expr.split(".", 1)[1]
            require(name in sources.colouring, f"missing {expr}")
            return sources.colouring[name]
        return parse_unit_color(expr)

    background = color_of(args["background"])
    key = color_of(args["keyFill"])
    modifier = color_of(args["modifierFill"])
    text = color_of(args["text"])
    primary = color_of(args["primaryFill"])
    primary_text = color_of(args["primaryText"])
    return {
        "backgroundColor": background,
        "letterFill": key,
        "modifierFill": modifier,
        "primaryFill": primary,
        "textColor": text,
        "modifierTextColor": text,
        "primaryTextColor": primary_text,
        "secondaryTextColor": (text[0], text[1], text[2], u8(0.75)),
        "shadowColor": (0, 0, 0, u8(0.45)),
    }


FONT_CACHE: dict[tuple[str, int], ImageFont.FreeTypeFont] = {}


def font_at(path: Path, size: float) -> ImageFont.FreeTypeFont:
    px = max(1, int(round(size)))
    key = (str(path), px)
    cached = FONT_CACHE.get(key)
    if cached is None:
        cached = ImageFont.truetype(str(path), px)
        FONT_CACHE[key] = cached
    return cached


def text_width(text: str, font: ImageFont.FreeTypeFont) -> float:
    return font.getlength(text)


def uniform_letter_size(intended: float, available: float) -> float:
    if available <= 1 or intended <= 1:
        return max(intended, 1)
    if max(text_width(ch, font_at(FONT_ANDIKA, intended)) for ch in ("W", "w", "M", "m")) <= available:
        return intended
    low, high, best = 1.0, intended, 1.0
    for _ in range(14):
        mid = (low + high) / 2
        widest = max(text_width(ch, font_at(FONT_ANDIKA, mid)) for ch in ("W", "w", "M", "m"))
        if widest <= available:
            best = mid
            low = mid
        else:
            high = mid
    return best


def fit_ui_font(text: str, max_width: float, size: float, bold: bool = False, minimum_scale: float = 0.6) -> ImageFont.FreeTypeFont:
    path = FONT_UI_BOLD if bold else FONT_UI
    current = size
    floor = max(1.0, size * minimum_scale)
    while current > floor:
        font = font_at(path, current)
        if text_width(text, font) <= max_width:
            return font
        current -= 0.5
    return font_at(path, floor)


@dataclass
class ColumnPlan:
    column: tuple[float, float, float, float]
    cells: list[tuple[float, float, float, float]]
    fonts: list[float]
    texts: list[str]
    fix: tuple[float, float, float, float]
    reserved_leading: float


def column_plan(sources: Sources, texts: list[str], keyboard: tuple[float, float], metrics: ResolvedMetrics, board: Board, shows: bool) -> ColumnPlan:
    if not shows or keyboard[0] <= 1 or keyboard[1] <= 1:
        return ColumnPlan((0, 0, 0, 0), [], [], [], (0, 0, 0, 0), 0)
    count = board.reference[1] if board.reference else max(len(row) for row in board.rows)
    weight = board.reference[0] if board.reference else max(sum(weight_of(key) for key in row) for row in board.rows)
    per_key = keyboard[0] / max(count, 1)
    floor = min(metrics.key_height * 0.42, max(16, per_key * 0.55))
    gaps = max(count - 1, 0) * metrics.key_spacing
    min_keys = floor * max(weight, 1) + gaps
    chrome = metrics.side_inset * 2 + metrics.key_spacing
    cap = keyboard[0] - chrome - min_keys
    maximum = max(0.0, min(keyboard[0] * 0.34, cap))
    proposed = swift_rounded(keyboard[0] * sources.column_fraction)
    if keyboard[0] < 360:
        minimum = 58
    elif keyboard[0] < 700:
        minimum = 74
    else:
        minimum = swift_rounded(700 * sources.column_fraction)
    width = min(maximum, max(minimum, proposed))
    x = metrics.side_inset
    y = metrics.top_inset
    height = max(0.0, keyboard[1] - metrics.top_inset - metrics.bottom_inset)
    fix_h = min(metrics.key_height, max(height, 0))
    column = (x, y, width, height)
    fix = (x, y + height - fix_h, width, fix_h)
    list_gap = metrics.row_spacing if texts else 0
    list_height = max(0.0, fix[1] - list_gap - y)
    readable = max(13, swift_rounded(metrics.letter_font_size * 0.5))
    preferred = max(readable, swift_rounded(metrics.letter_font_size * 0.72))
    visible, fonts, cell_frames = layout_column_rows(
        texts[:sources.max_suggestions], width, list_height, y, preferred, readable, metrics
    )
    reserved = width + metrics.key_spacing if width > 0 else 0
    return ColumnPlan(column, cell_frames, fonts, visible, fix, reserved)


def layout_column_rows(texts, width, list_height, origin_y, preferred, readable, metrics):
    if not texts or list_height <= 8 or width <= 8:
        return [], [], []
    insets = (4, 6, 4, 6)

    def line_width(text: str, size: float) -> float:
        return text_width(text, font_at(FONT_ANDIKA, size))

    def fitting(text: str) -> float:
        inner = max(1, width - insets[1] - insets[3])
        size = preferred
        lower = min(readable, preferred)
        while size > lower + 0.01:
            if line_width(text, size) <= inner + 0.5:
                return size
            size -= 0.5
        return lower

    def line_height(size: float) -> float:
        font = font_at(FONT_ANDIKA, size)
        return math.ceil(font.getmetrics()[0] + font.getmetrics()[1]) + insets[0] + insets[2] + 2

    for count in range(len(texts), 0, -1):
        slice_ = texts[:count]
        fonts = [fitting(text) for text in slice_]
        heights = [line_height(size) for size in fonts]
        if sum(heights) <= list_height + 0.5:
            extra = (list_height - sum(heights)) / count
            frames = []
            cursor = origin_y
            for height in heights:
                frames.append((metrics_x := 0, cursor, width, height + extra))
                cursor += height + extra
            # x is filled by the caller; placeholder replaced below
            frames = [(0, frame[1], width, frame[3]) for frame in frames]
            return slice_, fonts, frames
    return [texts[0]], [fitting(texts[0])], [(0, origin_y, width, list_height)]


def bar_plan(texts: list[str], bar_width: float, bar_height: float, preferred: float, readable: float, limit: int):
    fix_width = min(92.0, max(72.0, bar_width * 0.14))
    fix = (0.0, 2.0, fix_width, max(0.0, bar_height - 4))
    available = max(0.0, bar_width - fix_width)
    candidates = texts[:limit]
    if not candidates or available <= 1 or bar_height <= 1:
        return fix, [], [], preferred

    def place(slice_: list[str], size: float):
        content = [text_width(text, font_at(FONT_ANDIKA, size)) + 10 * 2 + 2 for text in slice_]
        total = sum(content)
        if total > available + 0.5:
            return None
        raised = [max(item, 36.0) for item in content]
        if sum(raised) <= available + 0.5:
            extra = (available - sum(raised)) / len(slice_)
            widths = [item + extra for item in raised]
        else:
            extra = (available - total) / len(slice_)
            widths = [item + extra for item in content]
        frames = []
        cursor = fix_width
        for item in widths:
            frames.append((cursor, 0.0, item, bar_height))
            cursor += item
        return frames

    for count in range(len(candidates), 0, -1):
        slice_ = candidates[:count]
        floor = min(8, readable) if count == 1 else readable
        size = preferred
        while size >= floor - 0.01:
            frames = place(slice_, size)
            if frames:
                return fix, frames, slice_, size
            size -= 1
    return fix, [(fix_width, 0.0, available, bar_height)], [candidates[0]], preferred


def keyboard_box(sources: Sources, device_width: float, safe_bottom: float, idiom: str, mode: str, shift: str, letter: str) -> tuple[str, Board, ResolvedMetrics, float]:
    height = 1.0
    layout_class = resolve_class(sources, device_width, idiom)
    board = build_board(sources, mode, shift, layout_class, letter)
    metrics = resolve_metrics(sources, layout_class, device_width, height, safe_bottom, len(board.rows))
    for _ in range(3):
        height = metrics.preferred_height
        layout_class = resolve_class(sources, device_width, idiom)
        board = build_board(sources, mode, shift, layout_class, letter)
        metrics = resolve_metrics(sources, layout_class, device_width, height, safe_bottom, len(board.rows))
    return layout_class, board, metrics, height


def distinct_subscreens(sources: Sources, layout_class: str, letter: str) -> tuple[list[str], list[str]]:
    emitted = []
    skipped = []
    seen = []
    for subscreen in ("letters", "letters-shift", "letters-caps", "letters-autoshift"):
        shift = SHIFT_FOR_SUB[subscreen]
        board = build_board(sources, "alphabetic", shift, layout_class, letter)
        signature = visual_signature(board, shift)
        if any(signature == previous for previous, _name in seen):
            match = next(name for previous, name in seen if previous == signature)
            skipped.append(
                f"{letter} {subscreen} on {layout_class} matches {match} "
                "(same labels, highlights, and key widths)"
            )
            continue
        seen.append((signature, subscreen))
        emitted.append(subscreen)
    for subscreen in ("numbers", "symbols"):
        off = build_board(sources, MODE_FOR_SUB[subscreen], "off", layout_class, letter)
        for shift in ("shifted", "capsLock", "autoShifted"):
            other = build_board(sources, MODE_FOR_SUB[subscreen], shift, layout_class, letter)
            if visual_signature(other, shift) != visual_signature(off, "off"):
                raise SystemExit(f"{subscreen} changed under {shift} on {layout_class}/{letter}")
        emitted.append(subscreen)
    return emitted, skipped


def assert_no_overflow(frames, width: float, metrics: ResolvedMetrics, context: str) -> list[str]:
    """Return sub-point inset misses. Fail only on a real overflow.

    A row with more inter-key gaps than `frameReference`'s column count can
    extend a fraction of a point past the side inset. That is the same math
    `KeyboardGeometry` runs; it is recorded, not hidden.
    """
    notes = []
    right = width - metrics.side_inset
    for row in frames:
        for x, _y, w, _h in row:
            require(w > 0, f"zero-width key: {context}")
            over = x + w - right
            require(over <= 8.0, f"key overflows ({x + w:.2f} > {right:.2f}): {context}")
            if over > 0.5:
                notes.append(f"{context}: key ends {over:.2f}pt past the side inset")
    return notes


def run_checks(sources: Sources) -> None:
    require(sources.letter_maps["qwerty"] == ("qwertyuiop", "asdfghjkl", "zxcvbnm"), "qwerty map drifted")
    require(sources.letter_maps["abc"] == ("abcdefghij", "klmnopqrs", "tuvwxyz"), "abc map drifted")
    require(sources.frequency_rows == ["earduw", "toilfyj", "nsmpbxk", "hcgvqz"], "frequency rows drifted")
    require(sources.frame_reference["compact"] == (10, 10), "compact frame reference drifted")
    require(sources.frequency_columns == {"compact": 3, "iPad": 3, "iPadPro": 4}, "frequency columns drifted")
    require(set("aeiou") <= set(sources.beth), "Beth map missing a vowel")
    for name in ("vowelFill", "consonantFill", "numberFill", "punctuationFill", "highContrastYellow"):
        require(name in sources.colouring, f"AccessColouring missing {name}")

    def expect(layout_class: str, letter: str, mode: str, shift: str, rows: list[list[str]]) -> None:
        board = build_board(sources, mode, shift, layout_class, letter)
        got = labels(board, shift)
        require(got == rows, f"label mismatch {layout_class} {letter} {mode} {shift}\n got {got}\n want {rows}")

    expect("compact", "qwerty", "alphabetic", "off", [
        list("qwertyuiop"),
        list("asdfghjkl"),
        ["shift", *list("zxcvbnm"), "delete.left"],
        ["123", "globe", "", "return"],
    ])
    expect("compact", "qwerty", "alphabetic", "shifted", [
        list("QWERTYUIOP"),
        list("ASDFGHJKL"),
        ["shift.fill", *list("ZXCVBNM"), "delete.left"],
        ["123", "globe", "", "return"],
    ])
    expect("compact", "qwerty", "alphabetic", "capsLock", [
        list("QWERTYUIOP"),
        list("ASDFGHJKL"),
        ["capslock.fill", *list("ZXCVBNM"), "delete.left"],
        ["123", "globe", "", "return"],
    ])
    expect("compact", "abc", "alphabetic", "off", [
        list("abcdefghij"),
        list("klmnopqrs"),
        ["shift", *list("tuvwxyz"), "delete.left"],
        ["123", "globe", "", "return"],
    ])
    expect("compact", "hifreq", "alphabetic", "off", [
        ["Space", *list("earduw"), "delete.left", ".", ","],
        [*list("toilfyj"), "return", "?", "!"],
        [*list("nsmpbxk"), "123", "'", '"'],
        [*list("hcgvqz"), "shift", "globe", "-", "@"],
    ])
    expect("iPad", "qwerty", "alphabetic", "off", [
        [*list("qwertyuiop"), "delete"],
        [*list("asdfghjkl"), ";", "'", "return"],
        ["shift", "`", *list("zxcvbnm"), ",", ".", "/", "shift"],
        [".?123", "globe", "", ".?123", "keyboard.chevron.compact.down"],
    ])
    expect("iPad", "qwerty", "alphabetic", "shifted", [
        [*list("QWERTYUIOP"), "delete"],
        [*list("ASDFGHJKL"), ":", '"', "return"],
        ["shift", "~", *list("ZXCVBNM"), "<", ">", "?", "shift"],
        [".?123", "globe", "", ".?123", "keyboard.chevron.compact.down"],
    ])
    expect("iPad", "abc", "alphabetic", "autoShifted", [
        [*list("ABCDEFGHIJ"), "delete"],
        [*list("KLMNOPQRS"), ";", "'", "return"],
        ["shift", "`", *list("TUVWXYZ"), ",", ".", "/", "shift"],
        [".?123", "globe", "", ".?123", "keyboard.chevron.compact.down"],
    ])
    pro_top = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
    expect("iPadPro", "qwerty", "alphabetic", "off", [
        pro_top + ["delete"],
        ["tab", *list("qwertyuiop"), "[", "]", "\\"],
        ["caps lock", *list("asdfghjkl"), ";", "'", "return"],
        ["shift", "`", *list("zxcvbnm"), ",", ".", "/", "shift"],
        [".?123", "globe", "arrow.uturn.backward", "", ".?123", "keyboard.chevron.compact.down"],
    ])
    expect("iPadPro", "qwerty", "alphabetic", "shifted", [
        ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+", "delete"],
        ["tab", *list("QWERTYUIOP"), "{", "}", "|"],
        ["caps lock", *list("ASDFGHJKL"), ":", '"', "return"],
        ["shift", "~", *list("ZXCVBNM"), "<", ">", "?", "shift"],
        [".?123", "globe", "arrow.uturn.backward", "", ".?123", "keyboard.chevron.compact.down"],
    ])
    expect("iPadPro", "qwerty", "alphabetic", "autoShifted", [
        pro_top + ["delete"],
        ["tab", *list("QWERTYUIOP"), "[", "]", "\\"],
        ["caps lock", *list("ASDFGHJKL"), ";", "'", "return"],
        ["shift", "`", *list("ZXCVBNM"), ",", ".", "/", "shift"],
        [".?123", "globe", "arrow.uturn.backward", "", ".?123", "keyboard.chevron.compact.down"],
    ])
    expect("iPad", "qwerty", "numeric", "off", [
        [*list("1234567890"), "delete"],
        [*list('-/:;()$&@"'), "return"],
        ["#+=", *list(".,?!'"), "#+="],
        ["ABC", "globe", "", "ABC", "keyboard.chevron.compact.down"],
    ])
    expect("iPadPro", "abc", "symbols", "off", [
        [*list("[]{}#%^*+=•"), "delete"],
        ["arrow.uturn.backward", *list("_\\|~<>€£¥·"), "return"],
        ["arrow.uturn.forward", "123", *list(".§¡¿–—«»"), "123"],
        ["ABC", *list("°†‡※∞"), "ABC"],
        ["ABC", "globe", "arrow.uturn.backward", "", "ABC", "keyboard.chevron.compact.down"],
    ])
    freq_ipad = build_board(sources, "alphabetic", "off", "iPad", "hifreq")
    require(labels(freq_ipad, "off")[3][-1] == "keyboard.chevron.compact.down", "iPad frequency should tuck hide into the corner")
    freq_pro = build_board(sources, "alphabetic", "off", "iPadPro", "hifreq")
    require(len(freq_pro.rows[0]) == 1 + 6 + 4, "iPad Pro frequency row width drifted")

    # Geometry: compact QWERTY at 390pt spans the usable width.
    layout_class, board, metrics, _height = keyboard_box(sources, 390, 0, "phone", "alphabetic", "off", "qwerty")
    frames = board_frames(board, metrics, 390, 0, metrics.prediction_bar_height)
    require(layout_class == "compact", "390pt phone should be compact")
    require(abs(frames[0][0][0] - 3) < 0.01, "QWERTY should start at the side inset")
    require(abs((frames[0][-1][0] + frames[0][-1][2]) - 387) < 0.01, "QWERTY top row should meet the right inset")
    assert_no_overflow(frames, 390, metrics, "qwerty 390")

    # iPad portrait uses the 4-row board; landscape of an 11-inch Pro uses iPad Pro.
    portrait_class = resolve_class(sources, 834, "pad")
    landscape_class = resolve_class(sources, 1210, "pad")
    require(portrait_class == "iPad", "834pt iPad should be the iPad board")
    require(landscape_class == "iPadPro", "1210pt iPad should be the iPad Pro board")
    print("checks passed")


def draw_round(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float], radius: float, fill, scale: int) -> None:
    x, y, w, h = box
    draw.rounded_rectangle(
        [x * scale, y * scale, (x + w) * scale, (y + h) * scale],
        radius=max(0, radius * scale),
        fill=fill,
    )


def draw_symbol(draw: ImageDraw.ImageDraw, name: str, box: tuple[float, float, float, float], color, scale: int) -> None:
    x, y, w, h = [value * scale for value in box]
    pad = min(w, h) * 0.22
    left, top, right, bottom = x + pad, y + pad, x + w - pad, y + h - pad
    cx, cy = (left + right) / 2, (top + bottom) / 2
    stroke = max(2, int(min(w, h) * 0.08))

    def line(a, b):
        draw.line([a, b], fill=color, width=stroke)

    if name in ("shift", "shift.fill", "capslock", "capslock.fill"):
        tip = (cx, top)
        left_pt = (left, cy)
        right_pt = (right, cy)
        if name.endswith(".fill"):
            draw.polygon([tip, right_pt, left_pt], fill=color)
        else:
            draw.line([left_pt, tip, right_pt], fill=color, width=stroke)
        if name.startswith("capslock"):
            line((left, bottom), (right, bottom))
        else:
            stem_top = cy
            draw.rectangle([cx - stroke, stem_top, cx + stroke, bottom], fill=color)
    elif name == "delete.left":
        body_left = left + (right - left) * 0.28
        draw.polygon([(left, cy), (body_left, top), (right, top), (right, bottom), (body_left, bottom)], outline=color)
        line((body_left + stroke * 2, top + stroke * 2), (right - stroke * 2, bottom - stroke * 2))
        line((right - stroke * 2, top + stroke * 2), (body_left + stroke * 2, bottom - stroke * 2))
    elif name == "globe":
        draw.ellipse([left, top, right, bottom], outline=color, width=stroke)
        draw.ellipse([cx - (right - left) * 0.22, top, cx + (right - left) * 0.22, bottom], outline=color, width=max(1, stroke - 1))
        line((left, cy), (right, cy))
    elif name == "keyboard.chevron.compact.down":
        draw.rounded_rectangle([left, top, right, cy], radius=stroke, outline=color, width=stroke)
        line((cx - (right - left) * 0.22, cy + stroke), (cx, bottom))
        line((cx, bottom), (cx + (right - left) * 0.22, cy + stroke))
    elif name in ("arrow.uturn.backward", "arrow.uturn.forward"):
        forward = name.endswith("forward")
        mid_y = top + (bottom - top) * 0.45
        if forward:
            line((left, bottom), (left, mid_y))
            line((left, mid_y), (right - stroke * 2, mid_y))
            draw.polygon([(right, mid_y), (right - stroke * 4, mid_y - stroke * 3), (right - stroke * 4, mid_y + stroke * 3)], fill=color)
        else:
            line((right, bottom), (right, mid_y))
            line((right, mid_y), (left + stroke * 2, mid_y))
            draw.polygon([(left, mid_y), (left + stroke * 4, mid_y - stroke * 3), (left + stroke * 4, mid_y + stroke * 3)], fill=color)
    else:
        draw.text((cx, cy), "?", fill=color, anchor="mm", font=font_at(FONT_UI, max(8, (bottom - top) * 0.8 / scale) * scale))


def draw_keyboard(sources: Sources, appearance: Appearance, device: Device, orientation: str, width: int, safe_bottom: float, layout: str, subscreen: str, predictions: list[str], scale: int, notes: list[str] | None = None) -> Image.Image:
    mode = MODE_FOR_SUB[subscreen]
    shift = SHIFT_FOR_SUB[subscreen]
    layout_class, board, metrics, height = keyboard_box(sources, width, safe_bottom, device.idiom, mode, shift, layout)
    shows_column = layout_class != "compact"
    prediction_texts = predictions if mode == "alphabetic" else []
    column = column_plan(
        sources,
        prediction_texts,
        (width, height),
        metrics,
        board,
        shows_column,
    )
    reserved_top = 0 if shows_column else metrics.prediction_bar_height
    frames = board_frames(board, metrics, width, column.reserved_leading, reserved_top)
    for note in assert_no_overflow(frames, width, metrics, f"{layout} {subscreen} {device.slug} {orientation}"):
        if notes is not None and note not in notes:
            notes.append(note)

    banner = 46
    image = Image.new("RGBA", (int(width * scale), int((banner + height) * scale)), (28, 28, 30, 255))
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, banner * scale, image.width, image.height], fill=appearance.background)
    title = "NOT an iOS Simulator render"
    detail = f"{layout_title(layout)} · {subscreen} · {device.slug} · {orientation} · {theme_for(layout, subscreen)} · {layout_class} · {width:.0f}pt"
    draw.text((12 * scale, 8 * scale), title, fill=(255, 255, 255, 255), font=font_at(FONT_UI_BOLD, 13 * scale))
    detail_font = fit_ui_font(detail, width - 16, 11 * scale, False, 0.6)
    draw.text((12 * scale, 26 * scale), detail, fill=(210, 210, 214, 255), font=detail_font)

    origin = banner
    if not shows_column:
        bar = (
            metrics.side_inset,
            4,
            max(0, width - metrics.side_inset * 2),
            max(0, metrics.prediction_bar_height - 8),
        )
        preferred = metrics.modifier_font_size + 2
        readable = max(13, swift_rounded(metrics.letter_font_size * 0.5))
        fix, cells, texts, size = bar_plan(prediction_texts, bar[2], bar[3], preferred, readable, sources.max_suggestions)
        fix_box = (bar[0] + fix[0], origin + bar[1] + fix[1], fix[2], fix[3])
        draw_round(draw, fix_box, min(8, max(0, fix[3]) / 4), appearance.primary_fill, scale)
        fix_font = font_at(FONT_UI_BOLD, size * scale)
        draw.text(
            ((fix_box[0] + fix_box[2] / 2) * scale, (fix_box[1] + fix_box[3] / 2) * scale),
            "Fix",
            fill=appearance.primary_text,
            anchor="mm",
            font=fix_font,
        )
        line = (*appearance.secondary_text[:3], u8(0.45))
        for index, (text, cell) in enumerate(zip(texts, cells)):
            cell_box = (bar[0] + cell[0], origin + bar[1] + cell[1], cell[2], cell[3])
            label_font = font_at(FONT_ANDIKA, size * scale)
            draw.text(
                ((cell_box[0] + cell_box[2] / 2) * scale, (cell_box[1] + cell_box[3] / 2) * scale),
                text,
                fill=appearance.text,
                anchor="mm",
                font=label_font,
            )
            sep_x = bar[0] + (fix[2] if index == 0 else cells[index - 1][0] + cells[index - 1][2])
            sep_y = origin + bar[1] + bar[3] * 0.22
            draw.rectangle(
                [sep_x * scale, sep_y * scale, sep_x * scale + max(1, scale / 2), (sep_y + bar[3] * 0.56) * scale],
                fill=line,
            )
    elif column.column[2] > 0:
        for text, cell, font_size in zip(column.texts, column.cells, column.fonts):
            cell_box = (column.column[0], origin + cell[1], column.column[2], cell[3])
            inner_left = cell_box[0] + 6
            draw.text(
                (inner_left * scale, (cell_box[1] + cell_box[3] / 2) * scale),
                text,
                fill=appearance.text,
                anchor="lm",
                font=font_at(FONT_ANDIKA, font_size * scale),
            )
        fix_box = column.fix
        draw_round(draw, (fix_box[0], origin + fix_box[1], fix_box[2], fix_box[3]), metrics.corner_radius, appearance.primary_fill, scale)
        draw.text(
            ((fix_box[0] + fix_box[2] / 2) * scale, (origin + fix_box[1] + fix_box[3] / 2) * scale),
            "Fix",
            fill=appearance.primary_text,
            anchor="mm",
            font=font_at(FONT_UI_BOLD, metrics.modifier_font_size * scale),
        )

    for row_keys, row_frames in zip(board.rows, frames):
        for key, frame in zip(row_keys, row_frames):
            box = (frame[0], origin + frame[1], frame[2], frame[3])
            shadow = (box[0], box[1] + 1, box[2], box[3])
            draw_round(draw, shadow, metrics.corner_radius, appearance.shadow, scale)
            draw_round(draw, box, metrics.corner_radius, appearance.fill(key, shift), scale)
            color = appearance.foreground(key, shift)
            label = shown_text(key, shift)
            if key.display_kind == "symbol":
                draw_symbol(draw, label, (box[0] + 6, box[1] + 6, box[2] - 12, box[3] - 12), color, scale)
            elif key.display_kind == "text" and label:
                if key.secondary:
                    sec_font = font_at(FONT_UI, 10 * scale)
                    draw.text(
                        ((box[0] + box[2] - 4) * scale, (box[1] + 2) * scale),
                        key.secondary,
                        fill=appearance.secondary_text,
                        anchor="rt",
                        font=sec_font,
                    )
                    label_top = 15
                    label_box_h = max(8, box[3] - label_top - 2)
                    available = box[2] - 4
                    if key.style == "letter" and len(label) == 1:
                        size = uniform_letter_size(metrics.letter_font_size, available)
                        label_font = font_at(FONT_ANDIKA, size * scale)
                    else:
                        label_font = fit_ui_font(label, available * scale, metrics.modifier_font_size * scale)
                    draw.text(
                        ((box[0] + box[2] / 2) * scale, (box[1] + label_top + label_box_h / 2) * scale),
                        label,
                        fill=color,
                        anchor="mm",
                        font=label_font,
                    )
                else:
                    available = box[2] - 8
                    if key.style == "letter" and len(label) == 1:
                        size = uniform_letter_size(metrics.letter_font_size, available)
                        label_font = font_at(FONT_ANDIKA, size * scale)
                    elif key.style == "space":
                        label_font = fit_ui_font(label, available * scale, metrics.letter_font_size * scale, False, 0.6)
                    else:
                        label_font = fit_ui_font(label, available * scale, metrics.modifier_font_size * scale)
                    draw.text(
                        ((box[0] + box[2] / 2) * scale, (box[1] + box[3] / 2) * scale),
                        label,
                        fill=color,
                        anchor="mm",
                        font=label_font,
                    )
    return image


def layout_title(layout: str) -> str:
    return {"qwerty": "QWERTY", "abc": "ABC", "hifreq": "Hi-Frequency"}[layout]


def render_gallery(out_dir: Path, scale: int) -> None:
    sources = load_sources()
    run_checks(sources)
    predictions = empty_field_predictions(sources)
    out_dir.mkdir(parents=True, exist_ok=True)
    appearances = {theme: appearance_for(sources, theme) for theme in THEMES}
    records = []
    skipped = []
    seen_skip = set()
    overflow_notes: list[str] = []
    devices = supported_devices()
    for letter in LAYOUT_ORDER:
        # Sub-screens depend on layout class, so compute them per class once.
        class_screens: dict[str, list[str]] = {}
        for layout_class in ("compact", "iPad", "iPadPro"):
            screens, skips = distinct_subscreens(sources, layout_class, letter)
            class_screens[layout_class] = screens
            for item in skips:
                if item not in seen_skip:
                    seen_skip.add(item)
                    skipped.append(item)
        for device in devices:
            for orientation, width, _height, safe in device.orientations():
                layout_class = resolve_class(sources, width, device.idiom)
                for subscreen in class_screens[layout_class]:
                    theme = theme_for(letter, subscreen)
                    image = draw_keyboard(
                        sources,
                        appearances[theme],
                        device,
                        orientation,
                        width,
                        safe,
                        letter,
                        subscreen,
                        predictions,
                        scale,
                        overflow_notes,
                    )
                    filename = f"{letter}_{subscreen}_{device.slug}_{orientation}_{theme}.png"
                    image.save(out_dir / filename)
                    records.append({
                        "file": filename,
                        "layout": letter,
                        "subscreen": subscreen,
                        "device": device.slug,
                        "device_title": device.title,
                        "aliases": device.aliases,
                        "orientation": orientation,
                        "theme": theme,
                        "width": width,
                        "safe": safe,
                        "idiom": device.idiom,
                        "layout_class": layout_class,
                    })
                    if len(records) % 40 == 0:
                        print(f"rendered {len(records)}")
    write_contact_sheet(out_dir, records)
    write_readme(out_dir, records, skipped, predictions, sources, overflow_notes)
    print(f"wrote {len(records)} screenshots to {out_dir}")


def write_contact_sheet(out_dir: Path, records: list[dict]) -> None:
    thumbs = []
    thumb_w = 220
    for record in records:
        with Image.open(out_dir / record["file"]) as image:
            ratio = thumb_w / image.width
            thumb = image.convert("RGB").resize((thumb_w, max(1, int(image.height * ratio))), Image.Resampling.LANCZOS)
        thumbs.append(thumb)
    label_h = 28
    cols = 6
    rows = math.ceil(len(thumbs) / cols)
    cell_h = max(thumb.height for thumb in thumbs) + label_h
    sheet = Image.new("RGB", (cols * thumb_w, rows * cell_h + 36), (245, 245, 247))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 8), "NOT an iOS Simulator render — contact sheet", fill=(20, 20, 20), font=font_at(FONT_UI_BOLD, 16))
    for index, (thumb, record) in enumerate(zip(thumbs, records)):
        col = index % cols
        row = index // cols
        x = col * thumb_w
        y = 36 + row * cell_h
        sheet.paste(thumb, (x, y))
        caption = f"{record['layout']} {record['subscreen']}"
        caption2 = f"{record['device']} {record['orientation']}"
        draw.text((x + 4, y + thumb.height + 1), caption, fill=(20, 20, 20), font=font_at(FONT_UI, 9))
        draw.text((x + 4, y + thumb.height + 13), caption2, fill=(70, 70, 74), font=font_at(FONT_UI, 9))
    path = out_dir / "contact-sheet.png"
    sheet.save(path)
    print("wrote", path, sheet.size)


def write_readme(out_dir: Path, records: list[dict], skipped: list[str], predictions: list[str], sources: Sources, overflow_notes: list[str]) -> None:
    by_layout: dict[str, int] = {}
    by_device: dict[str, int] = {}
    themes = set()
    classes = set()
    for record in records:
        by_layout[record["layout"]] = by_layout.get(record["layout"], 0) + 1
        by_device[record["device"]] = by_device.get(record["device"], 0) + 1
        themes.add(record["theme"])
        classes.add(record["layout_class"])
    lines = [
        "# access: keyboard layout gallery",
        "",
        "These PNGs are **not** iOS Simulator or device captures. This environment has no Xcode and no iOS Simulator. Each image is drawn by `scripts/layout_gallery.py` from the Swift layout sources:",
        "",
        "- `LayoutFactory.swift` — key rows for QWERTY, ABC, and Hi-Frequency (Frequency / Grid), including numbers and symbols",
        "- `KeyboardGeometry.swift` and `LayoutMetrics.swift` — key frames, insets, and row heights",
        "- `LayoutClass.swift` — compact below "
        f"{sources.narrow_width:.0f}pt on iPad, iPad Pro at {sources.wide_width:.0f}pt and wider; iPhone is always compact",
        "- `KeyboardAppearance.swift`, `AccessColouring.swift`, `BethColorMap.swift` — colours",
        "- `PredictionBarGeometry.swift` and `PredictionColumnGeometry.swift` — the prediction bar (iPhone) and prediction column (iPad)",
        "- `Resources/google-10000-english-usa.txt` — empty-field predictions",
        "- `Resources/Fonts/Andika-Regular.ttf` — letter glyphs",
        "",
        "A banner on every PNG repeats that disclaimer.",
        "",
        "## How to read a filename",
        "",
        "`layout_subscreen_device_orientation_theme.png`",
        "",
        f"Total files: **{len(records)}** screenshots, plus `contact-sheet.png` and this README.",
        "",
        "Counts by layout:",
        "",
    ]
    for layout in LAYOUT_ORDER:
        lines.append(f"- {layout_title(layout)} (`{layout}`): {by_layout.get(layout, 0)}")
    lines += ["", "Counts by device:", ""]
    for device in supported_devices():
        lines.append(f"- `{device.slug}` — {device.title}" + (f" ({device.aliases})" if device.aliases else "") + f": {by_device.get(device.slug, 0)}")
    lines += [
        "",
        "## Matrix",
        "",
        "Layouts: QWERTY, ABC, Hi-Frequency (`LetterLayout.frequency`, titled Frequency (Grid) in the app).",
        "",
        "Sub-screens, when they look different:",
        "",
        "- `letters` — alphabetic, shift off",
        "- `letters-shift` — manual shift (capitals; symbol alternates on the iPad boards that have them; filled shift)",
        "- `letters-caps` — caps lock, only where the glyph or the caps-lock key differs from manual shift",
        "- `letters-autoshift` — autocapitalisation, only where it differs from manual shift (letters upper, symbol keys unchanged)",
        "- `numbers` — the 123 page",
        "- `symbols` — the #+= page",
        "",
        "Both orientations of every iOS 18 / iPadOS 18 point size below. Full-width keyboard only (not a floating or split keyboard).",
        "",
        "Mode: the only keyboard the sources implement. There is no general-use toggle and no hideable sidebar. `showsPredictions` defaults to true, so the iPhone prediction bar and the iPad prediction column are shown. The column is what a reviewer might call a sidebar; hiding it would change key widths, so these shots keep it.",
        "",
        f"Empty-field predictions, from the word list, first {sources.max_suggestions} words capitalised the way `PredictionProvider` capitalises an empty field: {', '.join(predictions)}.",
        "",
        "Colour themes are a mix, not a full cross product. A given layout and sub-screen uses one theme on every device, so device sizes can be compared. Themes used: "
        + ", ".join(sorted(themes))
        + ".",
        "",
        "Layout classes actually produced: " + ", ".join(sorted(classes)) + ".",
        "",
        "Globe key is included (`needsInputModeSwitchKey = true`). Return key is the default label `return`.",
        "",
        "## Files",
        "",
        "| File | Layout | Sub-screen | Device | Orientation | Theme | Class | Width pt | Safe bottom |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for record in records:
        lines.append(
            f"| `{record['file']}` | {record['layout']} | {record['subscreen']} | {record['device']} | {record['orientation']} | {record['theme']} | {record['layout_class']} | {record['width']} | {record['safe']:.0f} |"
        )
    lines += [
        "",
        "## Combinations not produced",
        "",
        "Shift states that are visually the same as another state of the same board were not given a second file:",
        "",
    ]
    for item in skipped:
        lines.append(f"- {item}")
    lines += [
        "",
        "Also not produced, and why:",
        "",
        "- Real device or Simulator pixels. `xcodebuild` and `simctl` are not installed; the host is Linux.",
        "- San Francisco and SF Symbols. Modifier words use DejaVu Sans. Symbol keys (shift, delete, globe, hide, undo, redo) are geometric stand-ins for the SF Symbol names in `LayoutFactory`, not the Apple glyphs.",
        "- `UIColor.systemBlue` sampled on a device. The Fix key uses Apple's published sRGB system blue: #007AFF in light mode and #0A84FF in dark mode.",
        "- Prediction-cell widths measured with Core Text. The same fitting rules run against Andika via Pillow, so a suggestion's cell can differ by a point from an iPhone.",
        "- A full colour-theme cross product. Vowels and Beth are drawn on the light system chrome. High-contrast themes do not follow the interface style, matching `KeyboardAppearance.resolved`.",
        "- Floating and Split keyboards, and iPad widths under "
        f"{sources.narrow_width:.0f}pt (those resolve to the compact board). Only full-screen widths are included.",
        "- Accent popovers, the pressed-key state, and Fix-in-progress. Those are transient overlays, not layout pages.",
        "- Devices that cannot install an iOS 18 / iPadOS 18 binary: iPhone SE (1st generation), iPhone 8 and earlier, iPhone X, iPad Pro 10.5-inch, iPad mini (4th) and earlier, iPad (6th) and earlier.",
        "- Numeric and symbol pages do not depend on the letter layout (`LayoutFactory` builds one 123 board and one #+= board per size class). They are still rendered under each layout name because the requested filename includes the layout. Key geometry matches across QWERTY, ABC, and Hi-Frequency for those two pages; the theme can differ.",
        "",
        "Safe-area bottoms: 34pt portrait and 21pt landscape on Face ID iPhones (the home-indicator insets the extension assigns to `extraBottomInset`); 0 on home-button devices; 20pt on home-indicator iPads, the value `LayoutStabilityTests` uses for an iPad.",
        "",
        "Rows that end a fraction of a point past the side inset, using the same `KeyboardGeometry` formula (a row with more gaps than the stamped frame reference):",
        "",
    ]
    if overflow_notes:
        # The same miss repeats for every theme and layout that shares the geometry.
        # Keep one line per layout/sub-screen/device/orientation.
        for note in overflow_notes:
            lines.append(f"- {note}")
    else:
        lines.append("- None.")
    lines.append("")
    (out_dir / "README.md").write_text("\n".join(lines), encoding="utf-8")
    print("wrote", out_dir / "README.md")


def main() -> None:
    parser = argparse.ArgumentParser(description="Render the access: keyboard layout gallery")
    parser.add_argument("--out", default="/opt/cursor/artifacts/keyboard-screens")
    parser.add_argument("--scale", type=int, default=2)
    parser.add_argument("--check", action="store_true", help="parse sources and assert layouts, then exit")
    args = parser.parse_args()
    if args.check:
        run_checks(load_sources())
        return
    render_gallery(Path(args.out), args.scale)


if __name__ == "__main__":
    main()
