#!/usr/bin/env python3
"""Convert a 160x200 RGB PPM into a Plus/4 text boot-art PRG.

The emitted PRG loads at $0800 and contains TED attribute RAM followed by
padding up to $0C00, then screen codes. Loading it directly displays a
40x25 text-mode title while the bootloader chains the main program.
"""

from __future__ import annotations

import sys
from pathlib import Path

LOAD_ADDR = 0x0800
WIDTH = 160
HEIGHT = 200
COLS = 40
ROWS = 25

RAMP = [0x20, 0x2e, 0x3a, 0x2a, 0x6d, 0x23, 0x01]


def read_tokens(blob: bytes, count: int) -> tuple[list[bytes], int]:
    tokens: list[bytes] = []
    i = 0
    while i < len(blob) and len(tokens) < count:
        while i < len(blob) and blob[i] in b" \t\r\n":
            i += 1
        if i < len(blob) and blob[i] == ord("#"):
            while i < len(blob) and blob[i] not in b"\r\n":
                i += 1
            continue
        start = i
        while i < len(blob) and blob[i] not in b" \t\r\n":
            i += 1
        tokens.append(blob[start:i])
    while i < len(blob) and blob[i] in b" \t\r\n":
        i += 1
    return tokens, i


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: ppm_to_plus4_bootart.py <input.ppm> <output.prg>", file=sys.stderr)
        return 2
    src = Path(argv[1])
    dst = Path(argv[2])
    blob = src.read_bytes()
    (magic, width_s, height_s, maxval_s), start = read_tokens(blob, 4)
    if magic != b"P6" or int(width_s) != WIDTH or int(height_s) != HEIGHT or int(maxval_s) != 255:
        raise SystemExit(f"expected P6 {WIDTH}x{HEIGHT} maxval 255")
    pixels = blob[start:]
    if len(pixels) != WIDTH * HEIGHT * 3:
        raise SystemExit("invalid PPM payload size")

    attrs = bytearray([0x71] * 1024)
    screen = bytearray([0x20] * 1024)
    for row in range(ROWS):
        for col in range(COLS):
            total = 0
            samples = 0
            for y in range(row * 8, row * 8 + 8):
                for x in range(col * 4, col * 4 + 4):
                    off = (y * WIDTH + x) * 3
                    r, g, b = pixels[off], pixels[off + 1], pixels[off + 2]
                    total += r * 3 + g * 6 + b
                    samples += 10
            level = total // (samples * 32)
            if level >= len(RAMP):
                level = len(RAMP) - 1
            idx = row * COLS + col
            screen[idx] = RAMP[level]
            attrs[idx] = 0x70 | 0x01

    payload = bytes(attrs) + bytes(screen)
    dst.write_bytes(LOAD_ADDR.to_bytes(2, "little") + payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
