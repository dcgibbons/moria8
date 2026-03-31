#!/usr/bin/env python3
"""Convert a padded 160x200 RGB PPM image into a C64 multicolor boot-art PRG.

The emitted PRG stages at $A000 and contains:
- 8000 bytes of bitmap data
- 1000 bytes of screen RAM
- 1000 bytes of color RAM

The runtime bootloader copies those three planes into their final VIC-visible
locations before loading the main game.
"""

from __future__ import annotations

import sys
from pathlib import Path

LOAD_ADDR = 0xA000
WIDTH = 160
HEIGHT = 200
CELL_WIDTH = 4
CELL_HEIGHT = 8

C64_PALETTE = {
    0x0: (0x00, 0x00, 0x00),  # black
    0x1: (0xFF, 0xFF, 0xFF),  # white
    0x7: (0xD7, 0xE8, 0x6C),  # yellow
    0x8: (0xB8, 0x5B, 0x13),  # orange
    0x9: (0x6F, 0x4F, 0x25),  # brown
    0xB: (0x44, 0x44, 0x44),  # dark grey
    0xC: (0x6C, 0x6C, 0x6C),  # grey
    0xF: (0x95, 0x95, 0x95),  # light grey
}
DEFAULT_CELL_COLORS = (0x7, 0x8, 0xF)


def read_tokens(blob: bytes, count: int) -> tuple[list[bytes], int]:
    tokens: list[bytes] = []
    i = 0
    n = len(blob)
    while i < n and len(tokens) < count:
        while i < n and blob[i] in b" \t\r\n":
            i += 1
        if i < n and blob[i] == ord("#"):
            while i < n and blob[i] not in b"\r\n":
                i += 1
            continue
        if i >= n:
            break
        start = i
        while i < n and blob[i] not in b" \t\r\n":
            i += 1
        tokens.append(blob[start:i])
    if len(tokens) != count:
        raise ValueError("invalid PPM header")
    while i < n and blob[i] in b" \t\r\n":
        i += 1
    return tokens, i


def color_distance(rgb: tuple[int, int, int], pal: tuple[int, int, int]) -> int:
    r, g, b = rgb
    pr, pg, pb = pal
    dr = r - pr
    dg = g - pg
    db = b - pb
    return dr * dr + dg * dg + db * db


def luminance(color_idx: int) -> int:
    r, g, b = C64_PALETTE[color_idx]
    return r * 3 + g * 6 + b


def nearest_c64_color(rgb: tuple[int, int, int]) -> int:
    best_idx = 0
    best_dist = 1 << 62
    for idx, pal in C64_PALETTE.items():
        dist = color_distance(rgb, pal)
        if dist < best_dist:
            best_idx = idx
            best_dist = dist
    return best_idx


def choose_cell_colors(pixel_colors: list[int]) -> tuple[int, int, int]:
    counts: dict[int, int] = {}
    for color_idx in pixel_colors:
        if color_idx == 0:
            continue
        counts[color_idx] = counts.get(color_idx, 0) + 1

    ranked = sorted(
        counts,
        key=lambda idx: (-counts[idx], -luminance(idx), idx),
    )
    chosen = ranked[:3]
    for fallback in DEFAULT_CELL_COLORS:
        if len(chosen) >= 3:
            break
        if fallback not in chosen:
            chosen.append(fallback)
    while len(chosen) < 3:
        chosen.append(DEFAULT_CELL_COLORS[len(chosen)])
    return chosen[0], chosen[1], chosen[2]


def convert_ppm_to_prg(src: Path, dst: Path) -> None:
    blob = src.read_bytes()
    (magic, width_s, height_s, maxval_s), pixel_start = read_tokens(blob, 4)
    if magic != b"P6":
        raise ValueError(f"unsupported PPM magic: {magic!r}")
    width = int(width_s)
    height = int(height_s)
    maxval = int(maxval_s)
    if width != WIDTH or height != HEIGHT:
        raise ValueError(f"expected {WIDTH}x{HEIGHT} PPM, got {width}x{height}")
    if maxval != 255:
        raise ValueError(f"expected 8-bit RGB PPM, got maxval={maxval}")

    pixels = blob[pixel_start:]
    expected = WIDTH * HEIGHT * 3
    if len(pixels) != expected:
        raise ValueError(f"expected {expected} RGB bytes, got {len(pixels)}")

    quantized: list[int] = []
    for offset in range(0, len(pixels), 3):
        rgb = (pixels[offset], pixels[offset + 1], pixels[offset + 2])
        quantized.append(nearest_c64_color(rgb))

    bitmap = bytearray()
    screen = bytearray()
    color = bytearray()
    for cell_y in range(25):
        for cell_x in range(40):
            cell_pixels: list[int] = []
            for row in range(CELL_HEIGHT):
                y = cell_y * CELL_HEIGHT + row
                for pix in range(CELL_WIDTH):
                    x = cell_x * CELL_WIDTH + pix
                    cell_pixels.append(quantized[y * WIDTH + x])

            mc1, mc2, cell_color = choose_cell_colors(cell_pixels)
            palette_choices = (
                C64_PALETTE[0x0],
                C64_PALETTE[mc1],
                C64_PALETTE[mc2],
                C64_PALETTE[cell_color],
            )

            for row in range(8):
                y = cell_y * CELL_HEIGHT + row
                value = 0
                for pix in range(CELL_WIDTH):
                    x = cell_x * CELL_WIDTH + pix
                    offset = (y * WIDTH + x) * 3
                    rgb = (pixels[offset], pixels[offset + 1], pixels[offset + 2])
                    best_slot = 0
                    best_dist = 1 << 62
                    for slot, pal in enumerate(palette_choices):
                        dist = color_distance(rgb, pal)
                        if dist < best_dist:
                            best_slot = slot
                            best_dist = dist
                    value = (value << 2) | best_slot
                bitmap.append(value)
            screen.append((mc1 << 4) | mc2)
            color.append(cell_color)

    if len(bitmap) != 8000:
        raise AssertionError(f"expected 8000 bitmap bytes, got {len(bitmap)}")
    if len(screen) != 1000:
        raise AssertionError(f"expected 1000 screen bytes, got {len(screen)}")
    if len(color) != 1000:
        raise AssertionError(f"expected 1000 color bytes, got {len(color)}")

    dst.write_bytes(LOAD_ADDR.to_bytes(2, "little") + bytes(bitmap) + bytes(screen) + bytes(color))


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: ppm_to_c64_bootart.py <input.ppm> <output.prg>", file=sys.stderr)
        return 2
    try:
        convert_ppm_to_prg(Path(argv[1]), Path(argv[2]))
    except Exception as exc:  # pragma: no cover - CLI error path
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
