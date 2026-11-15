#!/usr/bin/env python3
"""Rewrite item.idx's sector table in place on a C128 .d64, .d71, or .d81 image.

Supports:
  - 1541 .d64 (35 tracks, 683 sectors = 174,848 B, directory at 18/1)
  - 1571 .d71 (70 tracks across both sides, 1,366 sectors = 349,696 B, directory at 18/1)
  - 1581 .d81 (80 tracks x 40 sectors, 3,200 sectors = 819,200 B, directory at 40/3)
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
import catalog_disk  # noqa: E402

D64_SPT = [0, *([21] * 17), *([19] * 7), *([18] * 6), *([17] * 5)]
D71_SPT = [0, *D64_SPT[1:], *D64_SPT[1:]]
D81_SPT = [0, *([40] * 80)]

GEOMETRIES: dict[int, tuple[list[int], int, int]] = {
    683 * 256: (D64_SPT, 18, 1),
    683 * 257: (D64_SPT, 18, 1),
    1366 * 256: (D71_SPT, 18, 1),
    1366 * 257: (D71_SPT, 18, 1),
    3200 * 256: (D81_SPT, 40, 3),
    3200 * 257: (D81_SPT, 40, 3),
}


def image_geometry(size: int) -> tuple[list[int], int, int]:
    if size not in GEOMETRIES:
        raise SystemExit(f"unsupported CBM disk image size: {size} bytes")
    return GEOMETRIES[size]


def sector_offset(spt: list[int], track: int, sector: int) -> int:
    assert 1 <= track < len(spt), f"track {track} out of range 1..{len(spt) - 1}"
    assert 0 <= sector < spt[track], f"sector {sector} out of range 0..{spt[track] - 1} on track {track}"
    return (sum(spt[1:track]) + sector) * 256


def chain(image: bytes, spt: list[int], track: int, sector: int) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    while track:
        out.append((track, sector))
        assert len(out) <= 3200, "sector chain loops"
        off = sector_offset(spt, track, sector)
        track, sector = image[off], image[off + 1]
    return out


def directory(image: bytes, spt: list[int], dir_track: int, dir_sector: int) -> dict[str, tuple[int, int]]:
    out: dict[str, tuple[int, int]] = {}
    for track, sector in chain(image, spt, dir_track, dir_sector):
        off = sector_offset(spt, track, sector)
        for e in range(8):
            entry = image[off + e * 32: off + e * 32 + 32]
            if entry[2] & 0x07:
                name = bytes(entry[5:21]).rstrip(b"\xa0").decode("latin-1").lower()
                out[name] = (entry[3], entry[4])
    return out


def fix_image(path: Path) -> bool:
    image = bytearray(path.read_bytes())
    spt, dir_track, dir_sector = image_geometry(len(image))
    dirs = directory(bytes(image), spt, dir_track, dir_sector)
    if catalog_disk.ITEM_INDEX_FILE not in dirs or catalog_disk.ITEM_FILE not in dirs:
        return False

    blob = catalog_disk.item_catalog_bytes()
    expected_sectors = -(-(len(blob) + 2) // 254)
    cat_sectors = chain(bytes(image), spt, *dirs[catalog_disk.ITEM_FILE])
    assert len(cat_sectors) == expected_sectors, (len(cat_sectors), expected_sectors)

    cat0_off = sector_offset(spt, *cat_sectors[0]) + 4
    assert bytes(image[cat0_off:cat0_off + 4]) == b"ITM2", f"{path}: item.cat missing 'ITM2' header"

    idx_blocks = chain(bytes(image), spt, *dirs[catalog_disk.ITEM_INDEX_FILE])
    assert len(idx_blocks) == 1, f"{catalog_disk.ITEM_INDEX_FILE} spans {len(idx_blocks)} blocks"
    idx_off = sector_offset(spt, *idx_blocks[0])
    load_lo, load_hi = image[idx_off + 2], image[idx_off + 3]
    header = [load_lo, load_hi, len(blob) & 0xFF, len(blob) >> 8, expected_sectors]
    data = bytes(header + [t for t, _ in cat_sectors] + [s for _, s in cat_sectors])
    assert image[idx_off] == 0 and image[idx_off + 1] == len(data) + 1, (
        f"{path}: item.idx sector link {(image[idx_off], image[idx_off + 1])} != (0, {len(data) + 1})"
    )
    image[idx_off + 2: idx_off + 2 + len(data)] = data
    path.write_bytes(bytes(image))
    return True


def selftest() -> None:
    assert sum(D64_SPT) == 683
    assert sum(D71_SPT) == 1366
    assert sum(D81_SPT) == 3200
    assert sector_offset(D81_SPT, 40, 3) == ((39 * 40) + 3) * 256
    assert sector_offset(D71_SPT, 36, 0) == 683 * 256
    print("fix_c128_item_idx selftest PASSED")


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        selftest()
        return 0
    if len(sys.argv) < 2:
        print("usage: fix_c128_item_idx.py <image.d64|image.d71|image.d81> ...", file=sys.stderr)
        return 2
    for arg in sys.argv[1:]:
        fix_image(Path(arg))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
