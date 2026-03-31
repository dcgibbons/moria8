#!/usr/bin/env python3
"""Reserve a CBM disk sector in the BAM so c1541 will not allocate it."""

from __future__ import annotations

import sys
from pathlib import Path


SECTORS_1541 = [0] + [21] * 17 + [19] * 7 + [18] * 6 + [17] * 5
SECTORS_1571 = SECTORS_1541 + SECTORS_1541[1:]


def sector_offset(track: int, sector: int, sectors_per_track: list[int]) -> int:
    max_sector = sectors_per_track[track]
    if sector < 0 or sector >= max_sector:
        raise ValueError(f"invalid sector {sector} for track {track}")
    return sum(sectors_per_track[1:track]) * 256 + sector * 256


def detect_geometry(image_size: int) -> tuple[str, list[int]]:
    if image_size == 174848:
        return ("d64", SECTORS_1541)
    if image_size == 349696:
        return ("d71", SECTORS_1571)
    raise ValueError(f"unsupported disk image size {image_size}")


def bam_entry_offset(track: int, image_kind: str) -> tuple[int, int]:
    if image_kind == "d64" or track <= 35:
        bam_track = 18
        bam_slot = track
    else:
        bam_track = 53
        bam_slot = track - 35
    bam_sector = 0
    bam_base = sector_offset(bam_track, bam_sector, SECTORS_1571 if image_kind == "d71" else SECTORS_1541)
    return bam_base + 4 * bam_slot, bam_track


def main() -> int:
    if len(sys.argv) != 4:
        print(f"usage: {sys.argv[0]} <disk-image> <track> <sector>", file=sys.stderr)
        return 1

    image_path = Path(sys.argv[1])
    track = int(sys.argv[2], 10)
    sector = int(sys.argv[3], 10)

    image = bytearray(image_path.read_bytes())
    image_kind, sectors_per_track = detect_geometry(len(image))
    if track < 1 or track >= len(sectors_per_track):
        raise ValueError(f"invalid track {track} for {image_kind}")

    entry_offset, _ = bam_entry_offset(track, image_kind)
    bitmap_index = sector // 8
    bit_mask = 1 << (sector % 8)

    if image[entry_offset + 1 + bitmap_index] & bit_mask:
        image[entry_offset] -= 1
        image[entry_offset + 1 + bitmap_index] &= (~bit_mask) & 0xFF

    image_path.write_bytes(image)
    print(f"Reserved sector {track}/{sector} in {image_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
