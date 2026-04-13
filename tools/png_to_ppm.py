#!/usr/bin/env python3
"""Convert a PNG source asset into an exact-size RGB PPM intermediate."""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path


def _parse_int(value: str, label: str) -> int:
    try:
        return int(value)
    except ValueError as exc:
        raise ValueError(f"invalid {label}: {value!r}") from exc


def _convert_with_pillow(src: Path, width: int, height: int, dst: Path) -> bool:
    try:
        from PIL import Image
    except ModuleNotFoundError:
        return False

    with Image.open(src) as image:
        if image.size != (width, height):
            raise ValueError(
                f"expected {width}x{height} PNG, got {image.size[0]}x{image.size[1]}"
            )

        if "A" in image.getbands():
            alpha = image.getchannel("A")
            lo, hi = alpha.getextrema()
            if (lo, hi) != (255, 255):
                raise ValueError("PNG alpha is not fully opaque; refusing to flatten art")

        image.convert("RGB").save(dst, format="PPM")
    return True


def _read_sips_property(src: Path, prop: str) -> str:
    proc = subprocess.run(
        ["/usr/bin/sips", "-g", prop, str(src)],
        capture_output=True,
        check=True,
        text=True,
    )
    for line in proc.stdout.splitlines():
        if line.strip().startswith(f"{prop}:"):
            return line.split(":", 1)[1].strip()
    raise ValueError(f"unable to read {prop} via sips")


def _png_uses_visible_transparency(src: Path) -> bool:
    data = src.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return False

    offset = 8
    idat = bytearray()
    trns: bytes | None = None
    width = height = bit_depth = color_type = None
    while offset < len(data):
        chunk_len = int.from_bytes(data[offset : offset + 4], "big")
        offset += 4
        chunk_type = data[offset : offset + 4]
        offset += 4
        chunk_data = data[offset : offset + chunk_len]
        offset += chunk_len + 4

        if chunk_type == b"IHDR":
            width = int.from_bytes(chunk_data[0:4], "big")
            height = int.from_bytes(chunk_data[4:8], "big")
            bit_depth = chunk_data[8]
            color_type = chunk_data[9]
        elif chunk_type == b"tRNS":
            trns = chunk_data
        elif chunk_type == b"IDAT":
            idat.extend(chunk_data)
        elif chunk_type == b"IEND":
            break

    if trns is None:
        return False
    if color_type != 3 or bit_depth != 8 or width is None or height is None:
        return True

    raw = zlib.decompress(bytes(idat))
    stride = width + 1
    prev = bytearray(width)
    used_indices: set[int] = set()
    for row_idx in range(height):
        row = bytearray(raw[row_idx * stride : (row_idx + 1) * stride])
        filter_type = row[0]
        pixels = row[1:]
        if filter_type == 1:
            for i in range(width):
                pixels[i] = (pixels[i] + (pixels[i - 1] if i else 0)) & 0xFF
        elif filter_type == 2:
            for i in range(width):
                pixels[i] = (pixels[i] + prev[i]) & 0xFF
        elif filter_type == 3:
            for i in range(width):
                pixels[i] = (pixels[i] + ((prev[i] + (pixels[i - 1] if i else 0)) >> 1)) & 0xFF
        elif filter_type == 4:
            for i in range(width):
                a = pixels[i - 1] if i else 0
                b = prev[i]
                c = prev[i - 1] if i else 0
                p = a + b - c
                pa = abs(p - a)
                pb = abs(p - b)
                pc = abs(p - c)
                predictor = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                pixels[i] = (pixels[i] + predictor) & 0xFF
        elif filter_type != 0:
            raise ValueError(f"unsupported PNG filter type: {filter_type}")

        used_indices.update(pixels)
        prev = pixels

    for idx in used_indices:
        alpha = trns[idx] if idx < len(trns) else 255
        if alpha != 255:
            return True
    return False


def _write_ppm(dst: Path, width: int, height: int, pixels: bytes) -> None:
    dst.write_bytes(f"P6\n{width} {height}\n255\n".encode("ascii") + pixels)


def _convert_bmp_to_ppm(src: Path, width: int, height: int, dst: Path) -> None:
    data = src.read_bytes()
    if len(data) < 54 or data[:2] != b"BM":
        raise ValueError("sips fallback produced an invalid BMP")

    pixel_offset = int.from_bytes(data[10:14], "little")
    dib_size = int.from_bytes(data[14:18], "little")
    bmp_width = int.from_bytes(data[18:22], "little", signed=True)
    bmp_height = int.from_bytes(data[22:26], "little", signed=True)
    planes = int.from_bytes(data[26:28], "little")
    bits_per_pixel = int.from_bytes(data[28:30], "little")
    compression = int.from_bytes(data[30:34], "little")

    if dib_size < 40 or planes != 1:
        raise ValueError("sips fallback produced an unsupported BMP layout")
    if abs(bmp_width) != width or abs(bmp_height) != height:
        raise ValueError(
            f"sips fallback changed image size to {abs(bmp_width)}x{abs(bmp_height)}"
        )

    if bits_per_pixel == 24 and compression == 0:
        bytes_per_pixel = 3
        row_stride = ((width * bytes_per_pixel) + 3) & ~3
        masks = None
    elif bits_per_pixel == 32 and compression == 3 and dib_size >= 56:
        bytes_per_pixel = 4
        row_stride = width * bytes_per_pixel
        masks = (
            int.from_bytes(data[54:58], "little"),
            int.from_bytes(data[58:62], "little"),
            int.from_bytes(data[62:66], "little"),
        )
        if masks != (0x00FF0000, 0x0000FF00, 0x000000FF):
            raise ValueError("sips fallback produced unsupported 32-bit BMP masks")
    else:
        raise ValueError("sips fallback produced an unsupported BMP layout")

    rows: list[bytes] = []
    for row_idx in range(height):
        src_row = row_idx if bmp_height < 0 else (height - 1 - row_idx)
        row_start = pixel_offset + (src_row * row_stride)
        row_end = row_start + (width * bytes_per_pixel)
        if row_end > len(data):
            raise ValueError("BMP pixel data is truncated")
        row = data[row_start:row_end]
        rgb_row = bytearray(width * 3)
        for pixel_idx in range(width):
            bmp_offset = pixel_idx * bytes_per_pixel
            rgb_offset = pixel_idx * 3
            if bytes_per_pixel == 3:
                blue = row[bmp_offset]
                green = row[bmp_offset + 1]
                red = row[bmp_offset + 2]
            else:
                pixel = int.from_bytes(row[bmp_offset : bmp_offset + 4], "little")
                red = (pixel & 0x00FF0000) >> 16
                green = (pixel & 0x0000FF00) >> 8
                blue = pixel & 0x000000FF
            rgb_row[rgb_offset : rgb_offset + 3] = bytes((red, green, blue))
        rows.append(bytes(rgb_row))

    _write_ppm(dst, width, height, b"".join(rows))


def _convert_with_sips(src: Path, width: int, height: int, dst: Path) -> bool:
    sips = shutil.which("sips")
    if not sips:
        return False

    actual_width = _parse_int(_read_sips_property(src, "pixelWidth"), "pixelWidth")
    actual_height = _parse_int(_read_sips_property(src, "pixelHeight"), "pixelHeight")
    if (actual_width, actual_height) != (width, height):
        raise ValueError(f"expected {width}x{height} PNG, got {actual_width}x{actual_height}")

    has_alpha = _read_sips_property(src, "hasAlpha").lower()
    if has_alpha == "yes" and _png_uses_visible_transparency(src):
        raise ValueError("PNG has alpha; refusing to flatten art during conversion")

    with tempfile.TemporaryDirectory() as tmpdir:
        bmp_path = Path(tmpdir) / "bootart.bmp"
        subprocess.run(
            [sips, "-s", "format", "bmp", str(src), "--out", str(bmp_path)],
            check=True,
            capture_output=True,
            text=True,
        )
        _convert_bmp_to_ppm(bmp_path, width, height, dst)
    return True


def convert_png_to_ppm(src: Path, width: int, height: int, dst: Path) -> None:
    if not src.is_file():
        raise FileNotFoundError(f"missing source art: {src}")

    dst.parent.mkdir(parents=True, exist_ok=True)

    if _convert_with_pillow(src, width, height, dst):
        return
    if _convert_with_sips(src, width, height, dst):
        return

    raise RuntimeError("need Pillow (`pip install pillow`) or macOS `sips` to decode PNG")


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print("usage: png_to_ppm.py <input.png> <width> <height> <output.ppm>", file=sys.stderr)
        return 2

    src = Path(argv[1])
    width = _parse_int(argv[2], "width")
    height = _parse_int(argv[3], "height")
    dst = Path(argv[4])

    try:
        convert_png_to_ppm(src, width, height, dst)
    except Exception as exc:  # pragma: no cover - CLI error path
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
