#!/usr/bin/env python3
"""Render + verify the iPhone (compact) keyboard boards on a Linux box.

The app has no iOS renderer here, so this reproduces the *actual* geometry the
extension runs on iPhone — the `.compact` metrics from `LayoutMetrics.metrics`
and the width math from `KeyboardGeometry.unitWidth` / `framesForRow` — for the
QWERTY, ABC and Frequency (Grid) boards. It does two jobs:

  1. `verify()` lays every compact board out across the real iPhone widths
     (portrait 320-430pt and a few landscape widths) and asserts no key spills
     past the side inset and none collapses to zero width. This mirrors
     `LayoutStabilityTests.testCompactBoardsFitIPhoneWidths`, which cannot run
     on Linux because the Core package imports UIKit.
  2. It renders QWERTY + Frequency at iPhone portrait width so a reviewer can
     see the boards fit on a phone.

The row specs and formulas below mirror LayoutFactory (compact branch) and
KeyboardGeometry exactly; if either changes, update this too.
"""
import os
import sys

# --- LayoutMetrics.metrics(for: .compact) -------------------------------------
SIDE_INSET = 3
TOP_INSET = 8
KEY_SPACING = 7
ROW_SPACING = 12
KEY_HEIGHT = 52
PRED_BAR = 46
CORNER = 6

# LayoutFactory.frameReference(for: .compact)
COMPACT_REF_WEIGHT = 10.0
COMPACT_REF_COUNT = 10

FREQ_SYMBOLS = [".", ",", "?", "!", "'", '"', "-", "@", ":", ";", "&", "/", "(", ")"]


def L(ch):
    return {"t": ch, "w": 1.0, "s": "letter"}


def P(ch):
    return {"t": ch, "w": 1.0, "s": "punct"}


def M(label, w=1.0):
    return {"t": label, "w": w, "s": "mod"}


def SPACE(label="", w="flex"):
    return {"t": label, "w": w, "s": "space"}


def letters(seq):
    return [L(c) for c in seq]


def chars(seq):
    return [L(c) for c in seq]


# --- LayoutFactory compact rows (needsGlobe = True) ---------------------------
FRAME_ROWS = {
    "qwerty": ("qwertyuiop", "asdfghjkl", "zxcvbnm"),
    "abc": ("abcdefghij", "klmnopqrs", "tuvwxyz"),
}
FREQ_LETTER_ROWS = ["earduw", "toilfyj", "nsmpbxk", "hcgvqz"]


def compact_toolbar(mode):
    keys = [M("123", 1.5)] if mode == "alphabetic" else [M("ABC", 1.5)]
    keys.append(M("globe", 1.2))          # needsGlobe = True
    keys.append(SPACE())
    keys.append(M("return", 2.2))
    return keys


def compact_bottom_letter_row(bottom):
    return [M("shift", 1.4)] + letters(bottom) + [M("delete", 1.4)]


def frequency_right_cells(row_count=4, columns=3):
    functions = [M("delete"), M("return"), M("123"), M("globe")]  # compact, no hide
    total = row_count * columns
    grid = [None] * total
    first = min(len(functions), row_count)
    for row in range(first):
        grid[row * columns] = functions[row]
    tail = total - 1
    for i in range(row_count, len(functions)):
        grid[tail] = functions[i]
        tail -= 1
    sym = 0
    for cell in range(total):
        if grid[cell] is None:
            grid[cell] = P(FREQ_SYMBOLS[sym % len(FREQ_SYMBOLS)])
            sym += 1
    return [[c for c in grid[r * columns:(r + 1) * columns] if c is not None] for r in range(row_count)]


def compact_board(mode, letter_layout):
    """Returns (rows, left_docked, reference) mirroring LayoutFactory.compactLayout + stamped()."""
    if mode == "alphabetic" and letter_layout == "frequency":
        right = frequency_right_cells()
        rows = []
        for i, lr in enumerate(FREQ_LETTER_ROWS):
            keys = []
            if i == 0:
                keys.append(SPACE("Space", 1.0))
            keys += letters(lr)
            if i == len(FREQ_LETTER_ROWS) - 1:
                keys.append(M("shift", 1.0))
            keys += right[i]
            rows.append(keys)
        return rows, True, None
    if mode == "alphabetic":
        top, home, bottom = FRAME_ROWS[letter_layout]
        rows = [
            letters(top),
            letters(home),
            compact_bottom_letter_row(bottom),
            compact_toolbar("alphabetic"),
        ]
        return rows, False, (COMPACT_REF_WEIGHT, COMPACT_REF_COUNT)
    if mode == "numeric":
        rows = [
            chars("1234567890"),
            chars("-/:;()$&@\""),
            [M("#+=", 1.4)] + chars(".,?!'") + [M("delete", 1.4)],
            compact_toolbar("numeric"),
        ]
        return rows, False, (COMPACT_REF_WEIGHT, COMPACT_REF_COUNT)
    # symbols
    rows = [
        chars("[]{}#%^*+="),
        chars("_\\|~<>\u20ac\u00a3\u00a5\u00b7"),
        [M("123", 1.4)] + chars(".,?!'") + [M("delete", 1.4)],
        compact_toolbar("symbols"),
    ]
    return rows, False, (COMPACT_REF_WEIGHT, COMPACT_REF_COUNT)


# --- KeyboardGeometry (compact) -----------------------------------------------
def weight(k):
    return 4.5 if k["w"] == "flex" else k["w"]


def fixed_weight(row):
    return sum(weight(k) for k in row if k["w"] != "flex")


def unit_width(rows, left_docked, reference, usable):
    if left_docked:
        max_weight = max(sum(weight(k) for k in row) for row in rows)
        max_count = max(len(row) for row in rows)
        gaps = max(max_count - 1, 0) * KEY_SPACING
        return min(KEY_HEIGHT, (usable - gaps) / max(max_weight, 1))
    if reference is not None:
        ref_weight, ref_count = reference
        gaps = max(ref_count - 1, 0) * KEY_SPACING
        return (usable - gaps) / max(ref_weight, 1)
    ref = max(rows, key=fixed_weight)
    gaps = max(len(ref) - 1, 0) * KEY_SPACING
    return (usable - gaps) / max(fixed_weight(ref), 1)


def frames_for_row(row, y, usable, unit, left_docked):
    gaps = max(len(row) - 1, 0) * KEY_SPACING
    flex_count = sum(1 for k in row if k["w"] == "flex")
    fixed = sum(weight(k) for k in row if k["w"] != "flex")
    if flex_count > 0:
        flex_w = max(unit, (usable - fixed * unit - gaps) / flex_count)
        leading = SIDE_INSET
    else:
        flex_w = 0
        row_w = fixed * unit + gaps
        leading = SIDE_INSET if left_docked else SIDE_INSET + max(0, (usable - row_w) / 2)
    cursor = leading
    out = []
    for k in row:
        kw = flex_w if k["w"] == "flex" else unit * weight(k)
        out.append((cursor, y, kw, KEY_HEIGHT, k))
        cursor += kw + KEY_SPACING
    return out


def board_frames(rows, left_docked, reference, board_width):
    usable = board_width - 2 * SIDE_INSET
    unit = unit_width(rows, left_docked, reference, usable)
    y = TOP_INSET + PRED_BAR
    out = []
    for row in rows:
        out.append(frames_for_row(row, y, usable, unit, left_docked))
        y += KEY_HEIGHT + ROW_SPACING
    return out


# --- verification -------------------------------------------------------------
IPHONE_WIDTHS = [320, 360, 375, 390, 393, 402, 414, 428, 430, 667, 736, 844, 932]
MODES = ["alphabetic", "numeric", "symbols"]
LETTER_LAYOUTS = ["qwerty", "abc", "frequency"]


def verify():
    failures = []
    checked = 0
    for width in IPHONE_WIDTHS:
        right_limit = width - SIDE_INSET
        for mode in MODES:
            for letter_layout in LETTER_LAYOUTS:
                rows, left_docked, reference = compact_board(mode, letter_layout)
                frames = board_frames(rows, left_docked, reference, width)
                for r, row in enumerate(frames):
                    for (x, y, w, h, k) in row:
                        checked += 1
                        ctx = f"w={width} mode={mode} letters={letter_layout} row={r} key={k['t']!r}"
                        if w <= 0:
                            failures.append(f"zero/negative width: {ctx}")
                        if x < SIDE_INSET - 0.5:
                            failures.append(f"starts left of inset (x={x:.2f}): {ctx}")
                        if x + w > right_limit + 0.5:
                            failures.append(f"overflows right (maxX={x + w:.2f} > {right_limit}): {ctx}")
    print(f"verify: checked {checked} key frames across {len(IPHONE_WIDTHS)} widths x {len(MODES)} modes x {len(LETTER_LAYOUTS)} layouts")
    if failures:
        print(f"FAIL ({len(failures)}):")
        for f in failures[:40]:
            print("  -", f)
        return False
    print("PASS: every compact board fits inside the usable width on all iPhone sizes")
    return True


# --- rendering ----------------------------------------------------------------
BG = (209, 212, 219)
LETTER_FILL = (255, 255, 255)
SPACE_FILL = (238, 240, 244)
MOD_FILL = (173, 179, 189)
PUNCT_FILL = (214, 226, 255)
PUNCT_BORDER = (54, 108, 214)
TEXT = (20, 20, 20)
MOD_TEXT = (30, 30, 30)


def _font(size):
    from PIL import ImageFont
    for name in ("DejaVuSans.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def render(mode, letter_layout, title, subtitle, path, board_width=390, scale=3):
    from PIL import Image, ImageDraw
    rows, left_docked, reference = compact_board(mode, letter_layout)
    frames = board_frames(rows, left_docked, reference, board_width)
    title_h = 74
    board_h = TOP_INSET + PRED_BAR + len(rows) * KEY_HEIGHT + (len(rows) - 1) * ROW_SPACING + 10
    W, H = board_width, title_h + board_h
    img = Image.new("RGB", (W * scale, H * scale), (245, 246, 248))
    d = ImageDraw.Draw(img)

    def rr(x, y, w, h, radius, fill, outline=None, width=1):
        d.rounded_rectangle(
            [x * scale, y * scale, (x + w) * scale, (y + h) * scale],
            radius=radius * scale, fill=fill, outline=outline, width=max(1, width * scale))

    def text_center(x, y, w, h, s, fnt, color):
        bbox = d.textbbox((0, 0), s, font=fnt)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        d.text(((x + w / 2) * scale - tw / 2, (y + h / 2) * scale - th / 2 - bbox[1]),
               s, font=fnt, fill=color)

    text_center(0, 8, W, 28, title, _font(22), (24, 24, 24))
    text_center(0, 40, W, 22, subtitle, _font(14), (110, 114, 122))

    top = title_h
    rr(0, top, W, board_h, 0, BG)
    rr(SIDE_INSET, top + 4, W - 2 * SIDE_INSET, PRED_BAR - 10, 6, (232, 234, 238))
    text_center(SIDE_INSET, top + 4, W - 2 * SIDE_INSET, PRED_BAR - 10, "predictions", _font(16), (120, 124, 132))

    key_font = _font(22)
    mod_font = _font(14)
    for row in frames:
        for (x, y, w, h, k) in row:
            yy = top + y
            style = k["s"]
            if style == "mod":
                rr(x, yy, w, h, CORNER, MOD_FILL)
            elif style == "space":
                rr(x, yy, w, h, CORNER, SPACE_FILL)
            elif style == "punct":
                rr(x, yy, w, h, CORNER, PUNCT_FILL, outline=PUNCT_BORDER, width=1)
            else:
                rr(x, yy, w, h, CORNER, LETTER_FILL)
            label = k["t"]
            if not label:
                continue
            if style == "letter":
                text_center(x, yy, w, h, label, key_font, TEXT)
            elif style == "punct":
                text_center(x, yy, w, h, label, key_font, PUNCT_BORDER)
            else:
                text_center(x, yy, w, h, label, mod_font, MOD_TEXT)

    img.save(path)
    print("wrote", path, img.size)
    return img


def render_all():
    from PIL import Image
    out = "/opt/cursor/artifacts"
    os.makedirs(out, exist_ok=True)
    q = render(
        "alphabetic", "qwerty",
        "iPhone  —  QWERTY  (compact, 390pt portrait)",
        "10-column letter row spans edge to edge; toolbar space bar flexes to fill",
        f"{out}/iphone_qwerty.png",
    )
    f = render(
        "alphabetic", "frequency",
        "iPhone  —  Frequency / Grid  (compact, 390pt portrait)",
        "left-docked Smartbox block + function keys/symbols to the right, one dense grid",
        f"{out}/iphone_frequency.png",
    )
    W = max(q.width, f.width)
    gap = 30
    combo = Image.new("RGB", (W, q.height + gap + f.height), (255, 255, 255))
    combo.paste(q, ((W - q.width) // 2, 0))
    combo.paste(f, ((W - f.width) // 2, q.height + gap))
    combo.save(f"{out}/iphone_qwerty_frequency.png")
    print("wrote", f"{out}/iphone_qwerty_frequency.png", combo.size)


if __name__ == "__main__":
    ok = verify()
    if "--no-render" not in sys.argv:
        try:
            render_all()
        except Exception as exc:  # PIL may be unavailable; verification is the gate
            print("render skipped:", exc)
    sys.exit(0 if ok else 1)
