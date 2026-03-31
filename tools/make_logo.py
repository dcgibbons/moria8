#!/usr/bin/env python3
"""Generate a simple shared fallback MORIA8 boot-art PPM.

The output is deliberately geometric and high-contrast so it survives both the
C64 multicolor bitmap reduction and the C128 custom-charset poster pipeline.
"""

from __future__ import annotations

import sys
from pathlib import Path

BLACK = (0x00, 0x00, 0x00)
GOLD = (0xD7, 0xE8, 0x6C)
DARK_GOLD = (0xB8, 0x5B, 0x13)
IVORY = (0xFF, 0xFF, 0xFF)
SLATE = (0x1E, 0x1C, 0x16)

BASE_W = 640
BASE_H = 200

GLYPHS = {
    "M": (
        "110000000011",
        "111000000111",
        "111100001111",
        "111110011111",
        "111111111111",
        "111011110111",
        "111001100111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111000000111",
    ),
    "O": (
        "001111111100",
        "011111111110",
        "111100001111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111100001111",
        "011111111110",
        "001111111100",
    ),
    "R": (
        "111111111000",
        "111111111110",
        "111000001111",
        "111000001111",
        "111000001111",
        "111111111110",
        "111111111000",
        "111001100000",
        "111000111000",
        "111000011100",
        "111000001110",
        "111000000111",
        "111000000111",
        "111000000111",
    ),
    "I": (
        "111111111111",
        "001111111100",
        "000011110000",
        "000011110000",
        "000011110000",
        "000011110000",
        "000011110000",
        "000011110000",
        "000011110000",
        "000011110000",
        "000011110000",
        "000011110000",
        "001111111100",
        "111111111111",
    ),
    "A": (
        "000111111000",
        "001111111100",
        "011110011110",
        "111100001111",
        "111000000111",
        "111000000111",
        "111111111111",
        "111111111111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111000000111",
        "111000000111",
    ),
    "8": (
        "001111111100",
        "011111111110",
        "111100001111",
        "111000000111",
        "111100001111",
        "011111111110",
        "001111111100",
        "011111111110",
        "111100001111",
        "111000000111",
        "111000000111",
        "111100001111",
        "011111111110",
        "001111111100",
    ),
}


def sx(x: int, width: int) -> int:
    return x * width // BASE_W


def sy(y: int, height: int) -> int:
    return y * height // BASE_H


def make_canvas(width: int, height: int, color: tuple[int, int, int]) -> bytearray:
    return bytearray(color * (width * height))


def fill_rect(
    canvas: bytearray,
    width: int,
    height: int,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    color: tuple[int, int, int],
) -> None:
    x0 = max(0, min(width, x0))
    x1 = max(0, min(width, x1))
    y0 = max(0, min(height, y0))
    y1 = max(0, min(height, y1))
    if x0 >= x1 or y0 >= y1:
        return
    row_bytes = width * 3
    pixel = bytes(color)
    span = pixel * (x1 - x0)
    for y in range(y0, y1):
        start = y * row_bytes + x0 * 3
        canvas[start : start + len(span)] = span


def rect_outline(
    canvas: bytearray,
    width: int,
    height: int,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    thickness: int,
    color: tuple[int, int, int],
) -> None:
    fill_rect(canvas, width, height, x0, y0, x1, y0 + thickness, color)
    fill_rect(canvas, width, height, x0, y1 - thickness, x1, y1, color)
    fill_rect(canvas, width, height, x0, y0, x0 + thickness, y1, color)
    fill_rect(canvas, width, height, x1 - thickness, y0, x1, y1, color)


def diamond(
    canvas: bytearray,
    width: int,
    height: int,
    cx: int,
    cy: int,
    rx: int,
    ry: int,
    fill: tuple[int, int, int],
    outline: tuple[int, int, int] | None = None,
) -> None:
    for y in range(cy - ry, cy + ry + 1):
        if y < 0 or y >= height:
            continue
        dy = abs(y - cy)
        if ry == 0:
            continue
        span = rx * (ry - dy) // ry
        fill_rect(canvas, width, height, cx - span, y, cx + span + 1, y + 1, fill)
    if outline is not None:
        for inset in range(1, 3):
            for y in range(cy - ry, cy + ry + 1):
                if y < 0 or y >= height:
                    continue
                dy = abs(y - cy)
                if ry == 0:
                    continue
                span = max(0, rx * (ry - dy) // ry - inset)
                if span == 0:
                    continue
                fill_rect(canvas, width, height, cx - span, y, cx - span + 1, y + 1, outline)
                fill_rect(canvas, width, height, cx + span, y, cx + span + 1, y + 1, outline)


def stepped_wing(
    canvas: bytearray,
    width: int,
    height: int,
    x0: int,
    y0: int,
    steps: int,
    step_w: int,
    step_h: int,
    color: tuple[int, int, int],
    mirror: bool,
) -> None:
    for step in range(steps):
        w = step_w * (steps - step)
        h = max(1, step_h - step // 2)
        y = y0 + step * step_h
        if mirror:
            fill_rect(canvas, width, height, x0 - w, y, x0, y + h, color)
        else:
            fill_rect(canvas, width, height, x0, y, x0 + w, y + h, color)


def render_glyph(
    canvas: bytearray,
    width: int,
    height: int,
    x: int,
    y: int,
    scale: int,
    glyph_rows: tuple[str, ...],
    color: tuple[int, int, int],
) -> None:
    for row_idx, row in enumerate(glyph_rows):
        for col_idx, cell in enumerate(row):
            if cell != "1":
                continue
            fill_rect(
                canvas,
                width,
                height,
                x + col_idx * scale,
                y + row_idx * scale,
                x + (col_idx + 1) * scale,
                y + (row_idx + 1) * scale,
                color,
            )


def draw_logo(canvas: bytearray, width: int, height: int) -> None:
    outer = sx(22, width)
    top = sy(12, height)
    right = width - outer
    bottom = height - top
    thick = max(1, sx(4, width))
    inner_gap = max(2, sx(7, width))

    rect_outline(canvas, width, height, outer, top, right, bottom, thick, DARK_GOLD)
    rect_outline(
        canvas,
        width,
        height,
        outer + inner_gap,
        top + inner_gap,
        right - inner_gap,
        bottom - inner_gap,
        max(1, thick // 2),
        GOLD,
    )

    cx = width // 2
    cy = height // 2
    diamond(
        canvas,
        width,
        height,
        cx,
        sy(18, height),
        sx(12, width),
        sy(8, height),
        GOLD,
        outline=IVORY,
    )
    diamond(
        canvas,
        width,
        height,
        cx,
        height - sy(18, height),
        sx(12, width),
        sy(8, height),
        GOLD,
        outline=IVORY,
    )

    stepped_wing(canvas, width, height, sx(102, width), sy(42, height), 4, sx(16, width), sy(7, height), GOLD, True)
    stepped_wing(canvas, width, height, width - sx(102, width), sy(42, height), 4, sx(16, width), sy(7, height), GOLD, False)
    stepped_wing(canvas, width, height, sx(102, width), height - sy(54, height), 3, sx(14, width), sy(6, height), DARK_GOLD, True)
    stepped_wing(canvas, width, height, width - sx(102, width), height - sy(54, height), 3, sx(14, width), sy(6, height), DARK_GOLD, False)

    word = "MORIA8"
    glyphs = GLYPHS
    scale = 1 if width <= 200 else max(1, width // 160)
    letter_w = len(glyphs["M"][0]) * scale
    gap = max(2, scale + 1)
    total_w = len(word) * letter_w + (len(word) - 1) * gap
    start_x = width // 2 - total_w // 2
    text_h = len(glyphs["M"]) * scale
    start_y = cy - text_h // 2

    top_rule_y = start_y - sy(18, height)
    bottom_rule_y = start_y + text_h + sy(10, height)
    top_rule_half = total_w // 2 + sx(32, width)
    bottom_rule_half = total_w // 2 + sx(40, width)
    fill_rect(canvas, width, height, width // 2 - top_rule_half, top_rule_y, width // 2 + top_rule_half, top_rule_y + max(1, sy(4, height)), GOLD)
    fill_rect(canvas, width, height, width // 2 - bottom_rule_half, bottom_rule_y, width // 2 + bottom_rule_half, bottom_rule_y + max(1, sy(4, height)), DARK_GOLD)

    x = start_x
    for ch in word:
        render_glyph(canvas, width, height, x, start_y, scale, glyphs[ch], IVORY)
        x += letter_w + gap


def write_ppm(path: Path, width: int, height: int, pixels: bytes) -> None:
    header = f"P6\n{width} {height}\n255\n".encode("ascii")
    path.write_bytes(header + pixels)


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print("usage: make_logo.py <width> <height> <output.ppm>", file=sys.stderr)
        return 2

    width = int(argv[1])
    height = int(argv[2])
    out_path = Path(argv[3])

    canvas = make_canvas(width, height, BLACK)
    draw_logo(canvas, width, height)
    write_ppm(out_path, width, height, bytes(canvas))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
