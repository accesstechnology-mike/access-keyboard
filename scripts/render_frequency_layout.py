#!/usr/bin/env python3
"""Render before/after mockups of the frequency keyboard layout.

This reproduces the *actual* layout math from KeyboardView.swift
(`unitWidth` / `framesForRow`) and LayoutMetrics.swift so the pictures reflect
the real geometry the app produces, not a hand-drawn guess. It exists only to
give reviewers a before/after image on a Linux box with no iOS renderer.
"""
from PIL import Image, ImageDraw, ImageFont

# iPad portrait reference size the app lays out against.
BOARD_W = 834

# --- LayoutMetrics.metrics(for: .iPad, portrait) with rowCount scaling --------
SIDE_INSET = 8
TOP_INSET = 10
BOTTOM_INSET = 10
KEY_SPACING = 9
PRED_BAR = 52
BASE_ROWS = 4
BASE_KEY_H = 80          # portrait
BASE_ROW_SPACING = 10


def metrics_for(row_count):
    scale = BASE_ROWS / max(row_count, 1)
    key_h = max(50, round(BASE_KEY_H * min(1.0, scale * 1.08)))
    row_spacing = max(8, round(BASE_ROW_SPACING * min(1.0, scale)))
    return key_h, row_spacing


def weight(w):
    return 4.5 if w == "flex" else w


def unit_width(rows, usable):
    def fixed(row):
        return sum(weight(k["w"]) for k in row)
    ref = max(rows, key=fixed)
    gaps = max(len(ref) - 1, 0) * KEY_SPACING
    return (usable - gaps) / max(fixed(ref), 1)


def frames_row(row, y, usable, unit, key_h):
    gaps = max(len(row) - 1, 0) * KEY_SPACING
    flex_count = sum(1 for k in row if k["w"] == "flex")
    fixed = sum(weight(k["w"]) for k in row if k["w"] != "flex")
    leftover = usable - fixed * unit - gaps
    if flex_count > 0:
        flex_w = max(unit, leftover / flex_count)
        leading = SIDE_INSET
    else:
        flex_w = 0
        row_w = fixed * unit + gaps
        leading = SIDE_INSET + max(0, (usable - row_w) / 2)
    cursor = leading
    out = []
    for k in row:
        kw = flex_w if k["w"] == "flex" else unit * weight(k["w"])
        out.append((cursor, y, kw, key_h, k))
        cursor += kw + KEY_SPACING
    return out


def L(ch):      # letter
    return {"t": ch, "w": 1, "s": "letter"}


def P(ch):      # punctuation (style .letter in code, flagged for the period)
    return {"t": ch, "w": 1, "s": "punct"}


def M(label, w):  # modifier
    return {"t": label, "w": w, "s": "mod"}


def SP():
    return {"t": "space", "w": "flex", "s": "space"}


def letters(seq):
    return [L(c) for c in seq]


# --- BEFORE: original iPad frequency board ------------------------------------
BEFORE = [
    letters("eardu") + [M("delete", 1.5)],
    letters("toilgv") + [M("return", 1.6)],
    [M("shift", 1.4)] + letters("nsfyx") + [P(".")],
    letters("hcpkj") + [P(",")],
    letters("mbwqz") + [P("?")],
    [M(".?123", 1.5), M("globe", 1.1), SP(), P("."), M(".?123", 1.4), M("hide", 1.2)],
]

# --- AFTER: redesigned aligned grid -------------------------------------------
AFTER = [
    [M("tab", 1.4)] + letters("earduto"),
    [M("caps lock", 1.4)] + letters("ilgvnsf"),
    [M("shift", 1.4)] + letters("yxhcpkj"),
    [M("123", 1.4)] + letters("mbwqz") + [P("."), P(",")],
    [M("delete", 1.6), M("globe", 1.1), SP(), M("return", 1.8), M("hide", 1.2)],
]

BG = (209, 212, 219)
LETTER_FILL = (255, 255, 255)
MOD_FILL = (173, 179, 189)
PERIOD_FILL = (255, 214, 214)
PERIOD_BORDER = (206, 41, 41)
TEXT = (20, 20, 20)
MOD_TEXT = (30, 30, 30)


def font(size):
    for name in ("DejaVuSans.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def render(rows, title, path, scale=2):
    key_h, row_spacing = metrics_for(len(rows))
    usable = BOARD_W - 2 * SIDE_INSET
    unit = unit_width(rows, usable)
    title_h = 46
    board_h = TOP_INSET + PRED_BAR + len(rows) * key_h + (len(rows) - 1) * row_spacing + BOTTOM_INSET
    W, H = BOARD_W, title_h + board_h
    img = Image.new("RGB", (W * scale, H * scale), (245, 246, 248))
    d = ImageDraw.Draw(img)

    def rr(x, y, w, h, radius, fill, outline=None, width=1):
        d.rounded_rectangle(
            [x * scale, y * scale, (x + w) * scale, (y + h) * scale],
            radius=radius * scale, fill=fill, outline=outline, width=width * scale)

    def text_center(x, y, w, h, s, fnt, color):
        bbox = d.textbbox((0, 0), s, font=fnt)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        d.text(((x + w / 2) * scale - tw / 2, (y + h / 2) * scale - th / 2 - bbox[1]),
               s, font=fnt, fill=color)

    # title
    text_center(0, 6, W, 30, title, font(26), (30, 30, 30))
    # board
    top = title_h
    rr(0, top, W, board_h, 0, BG)
    # prediction bar placeholder
    rr(SIDE_INSET, top + 6, usable, PRED_BAR - 12, 8, (232, 234, 238))
    text_center(SIDE_INSET, top + 6, usable, PRED_BAR - 12, "predictions", font(18), (120, 124, 132))

    key_font = font(26)
    mod_font = font(18)
    y = top + TOP_INSET + PRED_BAR
    for row in rows:
        for (x, ky, kw, kh, k) in frames_row(row, y, usable, unit, key_h):
            style = k["s"]
            is_period = style == "punct" and k["t"] == "."
            fill = LETTER_FILL
            if style == "mod":
                fill = MOD_FILL
            elif style == "space":
                fill = LETTER_FILL
            if is_period:
                rr(x, ky, kw, kh, 9, PERIOD_FILL, outline=PERIOD_BORDER, width=2)
            else:
                rr(x, ky, kw, kh, 9, fill)
            label = k["t"]
            if style == "letter":
                text_center(x, ky, kw, kh, label, key_font, TEXT)
            elif is_period:
                text_center(x, ky, kw, kh, ".", key_font, PERIOD_BORDER)
            else:
                text_center(x, ky, kw, kh, label, mod_font, MOD_TEXT if style == "mod" else TEXT)
        y += key_h + row_spacing

    img.save(path)
    print("wrote", path, img.size)


if __name__ == "__main__":
    import os
    out = "/opt/cursor/artifacts"
    os.makedirs(out, exist_ok=True)
    render(BEFORE, "BEFORE  -  ragged rows, misaligned columns, 2x period (red)",
           f"{out}/freq_before.png")
    render(AFTER, "AFTER  -  aligned grid, one leading modifier column, single period (red)",
           f"{out}/freq_after.png")

    a = Image.open(f"{out}/freq_before.png")
    b = Image.open(f"{out}/freq_after.png")
    W = max(a.width, b.width)
    gap = 24
    combo = Image.new("RGB", (W, a.height + gap + b.height), (255, 255, 255))
    combo.paste(a, ((W - a.width) // 2, 0))
    combo.paste(b, ((W - b.width) // 2, a.height + gap))
    combo.save(f"{out}/freq_before_after.png")
    print("wrote", f"{out}/freq_before_after.png", combo.size)
