#!/usr/bin/env python3
"""Draw the 1024 App Store icon using the live access: technology colours."""

from __future__ import annotations

import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw

CANVAS = 1024

# Colours from https://www.accesstechnology.co.uk
FIELD = (0x1A, 0x2C, 0x41)
SURFACE = (0xF5, 0xF7, 0xFA)
SHIFT = (0x24, 0x76, 0xED)
ACCENT = (0x33, 0xDE, 0xCF)

KEYBOARD = (168, 297, 688, 430)
KEY_SIZE = 48
GAP = 12
ROWS = (10, 9, 7)


def flip_rect(x: float, y: float, w: float, h: float) -> tuple[float, float, float, float]:
    return (x, CANVAS - y - h, w, h)


def rounded(draw: ImageDraw.ImageDraw, rect: tuple[float, float, float, float], radius: float, fill: tuple[int, int, int]) -> None:
    x, y, w, h = flip_rect(*rect)
    draw.rounded_rectangle((x, y, x + w, y + h), radius=radius, fill=fill)


def write_rgb_png(image: Image.Image, path: Path) -> None:
    rgb = image.convert("RGB")
    rgb.save(path, format="PNG")
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a PNG")
    offset = 8
    while offset + 8 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk = data[offset + 8 : offset + 8 + length]
        if chunk_type == b"IHDR":
            width, height, _bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
            if (width, height, color_type) != (CANVAS, CANVAS, 2):
                raise SystemExit(f"{path} is {width}x{height} color {color_type}, need {CANVAS} RGB")
            return
        offset += 8 + length + 4
    raise SystemExit(f"{path} has no IHDR")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} <output.png>")

    image = Image.new("RGB", (CANVAS, CANVAS), FIELD)
    draw = ImageDraw.Draw(image)
    kx, ky, kw, kh = KEYBOARD
    rounded(draw, KEYBOARD, 48, SURFACE)

    row_y = ky + kh - 86
    mid_x = kx + kw / 2
    for row_index, count in enumerate(ROWS):
        row_width = count * KEY_SIZE + (count - 1) * GAP
        x = mid_x - row_width / 2
        if row_index == 2:
            rounded(draw, (x - 72, row_y, 60, KEY_SIZE), 10, SHIFT)
        for _ in range(count):
            rounded(draw, (x, row_y, KEY_SIZE, KEY_SIZE), 10, FIELD)
            x += KEY_SIZE + GAP
        row_y -= KEY_SIZE + 18

    rounded(draw, (mid_x - 160, ky + 36, 320, 44), 10, ACCENT)

    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    write_rgb_png(image, output)
    print(f"Wrote {output}")


if __name__ == "__main__":
    main()
