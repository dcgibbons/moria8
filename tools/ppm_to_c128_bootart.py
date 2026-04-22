#!/usr/bin/env python3
"""Convert a 640x200 RGB PPM into a C128 VDC custom-charset boot-art asset set.

Outputs:
- <prefix>_charset.bin : 8192 bytes (512 glyph slots x 16 bytes)
- <prefix>_screen.bin  : 2000-byte 80x25 screen map
- <prefix>_attr.bin    : 2000-byte 80x25 VDC attribute map
- <prefix>_preview.ppm : reconstructed 640x200 preview of the quantized poster
- <prefix>.inc         : Kick Assembler constants for the generated asset
"""

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

WIDTH = 640
HEIGHT = 200
CELL_W = 8
CELL_H = 8
COLS = 80
ROWS = 25
POSTER_COLS = 80
POSTER_X_OFFSET = (COLS - POSTER_COLS) // 2
BLANK_CODE = 0x20
CODE_ORDER = tuple(code for code in range(512) if code != BLANK_CODE)
MAX_CUSTOM_TILES = len(CODE_ORDER)
ATTR_ALT_MODE = 0x00
REGION_FRAME = "frame"
REGION_INTERIOR = "interior"
FRAME_TILE_BUDGET = 48
SAFE_MARGIN_COLS = 3
SAFE_MARGIN_PX = SAFE_MARGIN_COLS * CELL_W
FRAME_SOURCE_COLS = 7
FRAME_SOURCE_PX = FRAME_SOURCE_COLS * CELL_W
FRAME_DEST_COLS = FRAME_SOURCE_COLS - SAFE_MARGIN_COLS
FRAME_DEST_PX = FRAME_DEST_COLS * CELL_W
INTERIOR_START_X = FRAME_SOURCE_PX
INTERIOR_END_X = WIDTH - FRAME_SOURCE_PX
SAFE_WINDOW_LEFT = SAFE_MARGIN_PX
SAFE_WINDOW_RIGHT = WIDTH - SAFE_MARGIN_PX - 1
BAYER4 = (
    (0, 8, 2, 10),
    (12, 4, 14, 6),
    (3, 11, 1, 9),
    (15, 7, 13, 5),
)

VDC_PALETTE = {
    0x0: (0x00, 0x00, 0x00),  # black
    0x1: (0x00, 0x00, 0xAA),  # blue
    0x2: (0x00, 0xAA, 0x00),  # green
    0x3: (0x00, 0xAA, 0xAA),  # cyan
    0x4: (0xAA, 0x00, 0x00),  # red
    0x5: (0xAA, 0x00, 0xAA),  # magenta
    0x6: (0xAA, 0x55, 0x00),  # brown/orange
    0x7: (0xAA, 0xAA, 0xAA),  # light grey
    0x8: (0x55, 0x55, 0x55),  # dark grey
    0x9: (0x55, 0x55, 0xFF),  # light blue
    0xA: (0x55, 0xFF, 0x55),  # light green
    0xB: (0x55, 0xFF, 0xFF),  # light cyan
    0xC: (0xFF, 0x55, 0x55),  # light red
    0xD: (0xFF, 0x55, 0xFF),  # light magenta
    0xE: (0xFF, 0xFF, 0x55),  # yellow
    0xF: (0xFF, 0xFF, 0xFF),  # white
}

FRAME_PALETTE = (0x6, 0xE, 0x7, 0xF)
INTERIOR_PALETTE = tuple(idx for idx in VDC_PALETTE if idx != 0)


def vdc_encode_rgbi(nibble: int) -> int:
    return ((nibble & 0x07) << 1) | ((nibble & 0x08) >> 3)


ENCODED_ATTRS = {
    idx: (vdc_encode_rgbi(idx) | ATTR_ALT_MODE) if idx else ATTR_ALT_MODE
    for idx in VDC_PALETTE
}


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


def color_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> int:
    dr = a[0] - b[0]
    dg = a[1] - b[1]
    db = a[2] - b[2]
    return dr * dr + dg * dg + db * db


def luminance(rgb: tuple[int, int, int]) -> int:
    return rgb[0] * 30 + rgb[1] * 59 + rgb[2] * 11


def nearest_vdc_attr(rgb: tuple[int, int, int]) -> int:
    return nearest_vdc_attr_from_palette(rgb, INTERIOR_PALETTE)


def nearest_vdc_attr_from_palette(rgb: tuple[int, int, int], allowed: tuple[int, ...]) -> int:
    best_idx = 0xE
    best_dist = 1 << 62
    for idx in allowed:
        pal = VDC_PALETTE[idx]
        dist = color_distance(rgb, pal)
        if dist < best_dist:
            best_idx = idx
            best_dist = dist
    return ENCODED_ATTRS[best_idx]


def tile_rows_to_key(rows: list[int]) -> int:
    key = 0
    for row in rows:
        key = (key << 8) | row
    return key


def key_to_tile_rows(key: int) -> list[int]:
    rows = [0] * CELL_H
    for idx in range(CELL_H - 1, -1, -1):
        rows[idx] = key & 0xFF
        key >>= 8
    return rows


def classify_cell(cell_x: int, cell_y: int) -> str:
    if cell_x < 7 or cell_x >= 73 or cell_y < 3 or cell_y >= 22:
        return REGION_FRAME
    return REGION_INTERIOR


def region_threshold(region: str) -> int:
    if region == REGION_FRAME:
        return 3050
    return 3400


def region_palette(region: str) -> tuple[int, ...]:
    if region == REGION_FRAME:
        return FRAME_PALETTE
    return INTERIOR_PALETTE


def smooth_rows(rows: list[int], region: str) -> list[int]:
    return rows


def make_region_cell_mask(
    cell_pixels: list[tuple[int, int, int]],
    region: str,
    phase_x: int,
    phase_y: int,
) -> tuple[int, tuple[int, int, int] | None]:
    lumas = [luminance(rgb) for rgb in cell_pixels]
    min_l = min(lumas)
    max_l = max(lumas)
    avg_l = sum(lumas) // len(lumas)
    if max_l < 2100 or ((max_l - min_l) < 700 and avg_l < 3400):
        return 0, None

    threshold = region_threshold(region)
    rows: list[int] = []
    on_pixels: list[tuple[int, int, int]] = []
    for row in range(CELL_H):
        byte = 0
        row_base = row * CELL_W
        for col in range(CELL_W):
            rgb = cell_pixels[row_base + col]
            luma = luminance(rgb)
            dither = (BAYER4[(phase_y * CELL_H + row) & 3][(phase_x * CELL_W + col) & 3] - 7) * 90
            on = luma + dither >= threshold and luma >= 1600
            byte = (byte << 1) | int(on)
            if on:
                on_pixels.append(rgb)
        rows.append(byte)

    rows = smooth_rows(rows, region)
    key = tile_rows_to_key(rows)
    if key == 0 or not on_pixels:
        return 0, None

    dominant_rgb = Counter(on_pixels).most_common(1)[0][0]
    return key, dominant_rgb


def make_cell_mask(
    cell_pixels: list[tuple[int, int, int]],
    cell_x: int,
    cell_y: int,
) -> tuple[int, tuple[int, int, int] | None, str]:
    region = classify_cell(cell_x, cell_y)
    key, avg_rgb = make_region_cell_mask(cell_pixels, region, cell_x, cell_y)
    return key, avg_rgb, region


def write_preview(
    dst: Path,
    charset_rows: list[list[int]],
    screen: bytes,
    attrs: bytes,
) -> None:
    attr_to_rgb = {val & 0x7F: VDC_PALETTE[(val & 0x0F) >> 1 | ((val & 0x01) << 3)] for val in ENCODED_ATTRS.values()}
    pixels = bytearray()
    for cell_y in range(ROWS):
        for row in range(CELL_H):
            for cell_x in range(COLS):
                code = screen[cell_y * COLS + cell_x]
                attr = attrs[cell_y * COLS + cell_x]
                if code == BLANK_CODE:
                    tile_row = 0
                    fg = VDC_PALETTE[0]
                else:
                    full_code = code | (256 if attr & 0x80 else 0)
                    tile_row = charset_rows[full_code][row]
                    fg = attr_to_rgb.get(attr & 0x7F, VDC_PALETTE[7])
                for bit in range(7, -1, -1):
                    if tile_row & (1 << bit):
                        pixels.extend(fg)
                    else:
                        pixels.extend(VDC_PALETTE[0])
    header = f"P6\n{WIDTH} {HEIGHT}\n255\n".encode("ascii")
    dst.write_bytes(header + pixels)


def rgb_at(pixels: bytes | bytearray, x: int, y: int) -> tuple[int, int, int]:
    offset = (y * WIDTH + x) * 3
    return pixels[offset], pixels[offset + 1], pixels[offset + 2]


def set_rgb(row: bytearray, x: int, rgb: tuple[int, int, int]) -> None:
    offset = x * 3
    row[offset] = rgb[0]
    row[offset + 1] = rgb[1]
    row[offset + 2] = rgb[2]


def content_bounds(pixels: bytes | bytearray) -> tuple[int, int, int, int] | None:
    left = WIDTH
    right = -1
    top = HEIGHT
    bottom = -1
    for y in range(HEIGHT):
        row_offset = y * WIDTH * 3
        for x in range(WIDTH):
            offset = row_offset + x * 3
            if pixels[offset] or pixels[offset + 1] or pixels[offset + 2]:
                if x < left:
                    left = x
                if x > right:
                    right = x
                if y < top:
                    top = y
                if y > bottom:
                    bottom = y
    if right < 0:
        return None
    return left, top, right, bottom


def format_center(left: int, right: int) -> str:
    total = left + right
    if total & 1:
        return f"{total // 2}.5"
    return str(total // 2)


def print_framing_report(label: str, pixels: bytes | bytearray) -> None:
    bounds = content_bounds(pixels)
    if bounds is None:
        print(f"{label}: no non-black pixels")
        return
    left, top, right, bottom = bounds
    print(
        f"{label}: bounds=({left},{top})-({right},{bottom}) "
        f"center_x={format_center(left, right)} "
        f"safe_margins=({left - SAFE_WINDOW_LEFT},{SAFE_WINDOW_RIGHT - right})"
    )


def needs_title_safe_framing(pixels: bytes | bytearray) -> bool:
    bounds = content_bounds(pixels)
    if bounds is None:
        return False
    left, _top, right, _bottom = bounds
    return left < SAFE_WINDOW_LEFT or right > SAFE_WINDOW_RIGHT


def resample_x_nearest(
    pixels: bytes | bytearray,
    row_y: int,
    src_start: int,
    src_width: int,
    dest_width: int,
) -> list[tuple[int, int, int]]:
    row: list[tuple[int, int, int]] = []
    for dest_x in range(dest_width):
        src_x = src_start + (dest_x * src_width) // dest_width
        row.append(rgb_at(pixels, src_x, row_y))
    return row


def apply_title_safe_framing(pixels: bytes | bytearray) -> bytearray:
    framed = bytearray(WIDTH * HEIGHT * 3)
    for y in range(HEIGHT):
        row = bytearray(WIDTH * 3)

        left_frame = resample_x_nearest(pixels, y, 0, FRAME_SOURCE_PX, FRAME_DEST_PX)
        for x, rgb in enumerate(left_frame):
            set_rgb(row, SAFE_MARGIN_PX + x, rgb)

        interior_width = INTERIOR_END_X - INTERIOR_START_X
        for x in range(interior_width):
            set_rgb(row, INTERIOR_START_X + x, rgb_at(pixels, INTERIOR_START_X + x, y))

        right_frame = resample_x_nearest(
            pixels,
            y,
            INTERIOR_END_X,
            FRAME_SOURCE_PX,
            FRAME_DEST_PX,
        )
        right_dest_start = WIDTH - SAFE_MARGIN_PX - FRAME_DEST_PX
        for x, rgb in enumerate(right_frame):
            set_rgb(row, right_dest_start + x, rgb)

        row_offset = y * WIDTH * 3
        framed[row_offset:row_offset + WIDTH * 3] = row
    return framed


def convert_ppm(src: Path, out_prefix: Path) -> None:
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
        raise ValueError(f"expected 8-bit PPM, got maxval={maxval}")

    pixels = bytearray(blob[pixel_start:])
    expected = WIDTH * HEIGHT * 3
    if len(pixels) != expected:
        raise ValueError(f"expected {expected} RGB bytes, got {len(pixels)}")

    print_framing_report("source", pixels)
    if needs_title_safe_framing(pixels):
        pixels = apply_title_safe_framing(pixels)
        print_framing_report("framed", pixels)
    else:
        print("framed: skipped (source already inside title-safe window)")

    cells: list[tuple[int, tuple[int, int, int] | None, str]] = []

    for cell_y in range(ROWS):
        for cell_x in range(POSTER_COLS):
            cell_pixels: list[tuple[int, int, int]] = []
            src_x0 = cell_x * CELL_W
            for row in range(CELL_H):
                y = cell_y * CELL_H + row
                row_offset = y * WIDTH * 3
                for col in range(CELL_W):
                    x = src_x0 + col
                    offset = row_offset + x * 3
                    cell_pixels.append((pixels[offset], pixels[offset + 1], pixels[offset + 2]))

            key, avg_rgb, region = make_cell_mask(cell_pixels, cell_x, cell_y)
            cells.append((key, avg_rgb, region))

    counts: Counter[int] = Counter()
    frame_counts: Counter[int] = Counter()
    for key, _avg_rgb, region in cells:
        if not key:
            continue
        counts[key] += 1
        if region == REGION_FRAME:
            frame_counts[key] += 1

    prototypes: list[int] = []
    seen: set[int] = set()

    for key, _count in frame_counts.most_common(FRAME_TILE_BUDGET):
        if key not in seen:
            prototypes.append(key)
            seen.add(key)
    for key, _count in counts.most_common(MAX_CUSTOM_TILES):
        if key in seen:
            continue
        prototypes.append(key)
        seen.add(key)
        if len(prototypes) >= MAX_CUSTOM_TILES:
            break

    if not prototypes:
        raise ValueError("no nonblank tiles found")

    charset_rows = [[0] * CELL_H for _ in range(512)]
    code_map = {}
    for idx, key in enumerate(prototypes):
        code = CODE_ORDER[idx]
        charset_rows[code] = key_to_tile_rows(key)
        code_map[key] = code

    screen = bytearray([BLANK_CODE] * (COLS * ROWS))
    attrs = bytearray([ENCODED_ATTRS[0]] * (COLS * ROWS))
    for idx, (key, avg_rgb, region) in enumerate(cells):
        row = idx // POSTER_COLS
        col = idx % POSTER_COLS
        dst = row * COLS + POSTER_X_OFFSET + col
        if key == 0:
            continue

        code = code_map.get(key)
        if code is None:
            best_code = CODE_ORDER[0]
            best_dist = 1 << 62
            for idx, proto_key in enumerate(prototypes):
                dist = bin(key ^ proto_key).count('1')
                if dist < best_dist:
                    best_dist = dist
                    best_code = CODE_ORDER[idx]
            code = best_code
        screen[dst] = code & 0xFF
        base_attr = nearest_vdc_attr_from_palette(
            avg_rgb or (255, 255, 255),
            region_palette(region),
        )
        if code >= 256:
            attrs[dst] = base_attr | 0x80
        else:
            attrs[dst] = base_attr & 0x7F

    charset = bytearray()
    for rows in charset_rows:
        charset.extend(rows)
        charset.extend(b"\x00" * 8)

    charset_bin = out_prefix.with_name(out_prefix.name + "_charset.bin")
    screen_bin = out_prefix.with_name(out_prefix.name + "_screen.bin")
    attr_bin = out_prefix.with_name(out_prefix.name + "_attr.bin")
    preview_ppm = out_prefix.with_name(out_prefix.name + "_preview.ppm")
    include_file = out_prefix.with_suffix(".inc")

    charset_bin.write_bytes(bytes(charset))
    screen_bin.write_bytes(bytes(screen))
    attr_bin.write_bytes(bytes(attrs))
    write_preview(preview_ppm, charset_rows, bytes(screen), bytes(attrs))
    include_file.write_text(
        "// generated by tools/ppm_to_c128_bootart.py\n"
        f".const BOOTART_TILE_COUNT = {len(prototypes)}\n"
        f".const BOOTART_CHARSET_BYTES = {len(charset)}\n",
        encoding="ascii",
    )


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: ppm_to_c128_bootart.py <input.ppm> <output_prefix>", file=sys.stderr)
        return 2
    try:
        convert_ppm(Path(argv[1]), Path(argv[2]))
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
