#!/usr/bin/env python3
"""Render before/after mockups of the frequency (Grid) keyboard layout.

This reproduces the *actual* layout math the app runs — the left-docked branch
of `KeyboardView.unitWidth` / `framesForRow` and the `rowCount` scaling in
`LayoutMetrics.metrics` — so the pictures reflect the real geometry the iPad
produces, not a hand-drawn guess. It exists only to give reviewers a before/
after image on a Linux box with no iOS renderer.

BEFORE  = the shipped board: a 7-wide left-docked letter block with the whole
          right-hand side empty and a separate function row underneath.
AFTER   = the redesign: function keys and symbols fill the space to the right of
          the letters, so the board is one dense grid (and one row shorter).

The key sequences below mirror LayoutFactory.frequencyRows /
frequencyRightCells exactly for the iPad size class (needsGlobe = true).
"""
import os
from PIL import Image, ImageDraw, ImageFont

# iPad portrait reference size the app lays out against.
BOARD_W = 834

# --- LayoutMetrics.metrics(for: .iPad, portrait) ------------------------------
SIDE_INSET = 8
TOP_INSET = 10
BOTTOM_INSET = 10
KEY_SPACING = 9
PRED_BAR = 52
BASE_ROWS = 4
BASE_KEY_H = 80          # iPad portrait
BASE_ROW_SPACING = 10


def metrics_for(row_count):
    # Mirrors the rowCount rescale in LayoutMetrics.metrics.
    scale = BASE_ROWS / max(row_count, 1)
    key_h = max(50, round(BASE_KEY_H * min(1.0, scale * 1.08)))
    row_spacing = max(8, round(BASE_ROW_SPACING * min(1.0, scale)))
    return key_h, row_spacing


def weight(w):
    return 4.5 if w == "flex" else w


def unit_width_left_docked(rows, usable, key_h):
    # KeyboardView.unitWidth, leftDocked branch: square keys sized by row height,
    # but never wider than a fill would allow.
    max_weight = max(sum(weight(k["w"]) for k in row) for row in rows)
    max_count = max(len(row) for row in rows)
    gaps = max(max_count - 1, 0) * KEY_SPACING
    fill_unit = (usable - gaps) / max(max_weight, 1)
    return min(key_h, fill_unit)


def frames_row_left_docked(row, y, unit, key_h):
    # KeyboardView.framesForRow, leftDocked branch: flush left.
    cursor = SIDE_INSET
    out = []
    for k in row:
        kw = unit * weight(k["w"])
        out.append((cursor, y, kw, key_h, k))
        cursor += kw + KEY_SPACING
    return out


def L(ch):
    return {"t": ch, "w": 1, "s": "letter"}


def P(ch):
    return {"t": ch, "w": 1, "s": "punct"}


def M(label, w=1):
    return {"t": label, "w": w, "s": "mod"}


def SPACE():
    return {"t": "Space", "w": 1, "s": "space"}


def letters(seq):
    return [L(c) for c in seq]


# --- BEFORE: the shipped board (LayoutFactory before this change) -------------
# 4 letter rows (Space + block, Shift closing the block) + one function toolbar
# row, all left-docked, leaving the whole right-hand side empty.
BEFORE = [
    [SPACE()] + letters("earduw"),
    letters("toilfyj"),
    letters("nsmpbxk"),
    letters("hcgvqz") + [M("shift")],
    [M("123"), M("globe"), M("delete"), M("return", 1.4), M("hide", 1.2)],
]

# --- AFTER: the redesign (LayoutFactory.frequencyRightCells, iPad, 3 cols) ----
# functions = [delete, return, 123, globe, hide]; first column = delete/return/
# 123/globe, hide overflows to the bottom-right corner, punctuation fills rest.
AFTER = [
    [SPACE()] + letters("earduw") + [M("delete"), P("."), P(",")],
    letters("toilfyj") + [M("return"), P("?"), P("!")],
    letters("nsmpbxk") + [M("123"), P("'"), P('"')],
    letters("hcgvqz") + [M("shift"), M("globe"), P("-"), M("hide")],
]

BG = (209, 212, 219)
LETTER_FILL = (255, 255, 255)
SPACE_FILL = (238, 240, 244)
MOD_FILL = (173, 179, 189)
PUNCT_FILL = (214, 226, 255)
PUNCT_BORDER = (54, 108, 214)
WASTE_FILL = (250, 224, 224)
WASTE_BORDER = (206, 41, 41)
TEXT = (20, 20, 20)
MOD_TEXT = (30, 30, 30)


def font(size):
    for name in ("DejaVuSans.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def render(rows, title, subtitle, path, mark_waste, scale=2):
    key_h, row_spacing = metrics_for(len(rows))
    usable = BOARD_W - 2 * SIDE_INSET
    unit = unit_width_left_docked(rows, usable, key_h)
    title_h = 64
    board_h = TOP_INSET + PRED_BAR + len(rows) * key_h + (len(rows) - 1) * row_spacing + BOTTOM_INSET
    W, H = BOARD_W, title_h + board_h
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

    text_center(0, 6, W, 28, title, font(24), (24, 24, 24))
    text_center(0, 36, W, 22, subtitle, font(16), (110, 114, 122))

    top = title_h
    rr(0, top, W, board_h, 0, BG)
    rr(SIDE_INSET, top + 6, usable, PRED_BAR - 12, 8, (232, 234, 238))
    text_center(SIDE_INSET, top + 6, usable, PRED_BAR - 12, "predictions", font(18), (120, 124, 132))

    key_font = font(26)
    mod_font = font(17)
    y = top + TOP_INSET + PRED_BAR
    board_right = SIDE_INSET + usable
    for row in rows:
        frames = frames_row_left_docked(row, y, unit, key_h)
        # Highlight the empty area to the right of the row (the wasted space).
        if mark_waste and frames:
            last_x = frames[-1][0] + frames[-1][2]
            waste_x = last_x + KEY_SPACING
            if board_right - waste_x > 24:
                rr(waste_x, y, board_right - waste_x, key_h, 9, WASTE_FILL,
                   outline=WASTE_BORDER, width=1)
        for (x, ky, kw, kh, k) in frames:
            style = k["s"]
            if style == "mod":
                rr(x, ky, kw, kh, 9, MOD_FILL)
            elif style == "space":
                rr(x, ky, kw, kh, 9, SPACE_FILL)
            elif style == "punct":
                rr(x, ky, kw, kh, 9, PUNCT_FILL, outline=PUNCT_BORDER, width=2)
            else:
                rr(x, ky, kw, kh, 9, LETTER_FILL)
            label = k["t"]
            if style == "letter":
                text_center(x, ky, kw, kh, label, key_font, TEXT)
            elif style == "punct":
                text_center(x, ky, kw, kh, label, key_font, PUNCT_BORDER)
            else:
                text_center(x, ky, kw, kh, label, mod_font, MOD_TEXT)
        y += key_h + row_spacing

    img.save(path)
    print("wrote", path, img.size)
    return img


if __name__ == "__main__":
    out = "/opt/cursor/artifacts"
    os.makedirs(out, exist_ok=True)
    a = render(
        BEFORE,
        "BEFORE  —  Frequency (Grid), iPad portrait",
        "7-wide letter block docked left; the whole right side is empty + a separate function row",
        f"{out}/freq_before.png",
        mark_waste=True,
    )
    b = render(
        AFTER,
        "AFTER  —  Frequency (Grid), iPad portrait",
        "letters stay left; function keys + symbols fill the right; one dense grid, one row shorter",
        f"{out}/freq_after.png",
        mark_waste=False,
    )

    W = max(a.width, b.width)
    gap = 28
    combo = Image.new("RGB", (W, a.height + gap + b.height), (255, 255, 255))
    combo.paste(a, ((W - a.width) // 2, 0))
    combo.paste(b, ((W - b.width) // 2, a.height + gap))
    combo.save(f"{out}/freq_before_after.png")
    print("wrote", f"{out}/freq_before_after.png", combo.size)
