#!/usr/bin/env python3
"""Patch a single 256-byte sector in a D64 image from a PRG payload."""

import sys
from pathlib import Path

SECTORS_PER_TRACK = [
    0,
    *([21] * 17),
    *([19] * 7),
    *([18] * 6),
    *([17] * 5),
]


def sector_offset(track: int, sector: int) -> int:
    if track < 1 or track >= len(SECTORS_PER_TRACK):
        raise ValueError(f"invalid track: {track}")
    max_sector = SECTORS_PER_TRACK[track]
    if sector < 0 or sector >= max_sector:
        raise ValueError(f"invalid sector {sector} for track {track}")
    absolute_sector = sum(SECTORS_PER_TRACK[1:track]) + sector
    return absolute_sector * 256


def main() -> int:
    if len(sys.argv) != 6:
        print(
            "usage: patch_d64_sector.py <d64> <track> <sector> <prg> <expected-load-addr-hex>",
            file=sys.stderr,
        )
        return 1

    d64_path = Path(sys.argv[1])
    track = int(sys.argv[2], 10)
    sector = int(sys.argv[3], 10)
    prg_path = Path(sys.argv[4])
    expected_load = int(sys.argv[5], 16)

    prg = prg_path.read_bytes()
    if len(prg) < 2:
        raise ValueError(f"{prg_path} is too short to be a PRG")
    load_addr = prg[0] | (prg[1] << 8)
    if load_addr != expected_load:
        raise ValueError(
            f"{prg_path} load address {load_addr:#06x} != expected {expected_load:#06x}"
        )

    payload = prg[2:]
    if len(payload) > 256:
        raise ValueError(f"{prg_path} payload is {len(payload)} bytes; sector limit is 256")
    payload = payload + bytes(256 - len(payload))

    image = bytearray(d64_path.read_bytes())
    offset = sector_offset(track, sector)
    if offset + 256 > len(image):
        raise ValueError(f"{d64_path} is too small for track {track} sector {sector}")
    image[offset : offset + 256] = payload
    d64_path.write_bytes(image)
    print(
        f"Patched {d64_path} track {track} sector {sector} "
        f"from {prg_path} payload ({len(prg[2:])} bytes, load {load_addr:#06x})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
