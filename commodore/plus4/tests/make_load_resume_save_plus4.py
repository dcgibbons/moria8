#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

SAVE_VERSION = 0x01

PL_STRUCT_SIZE = 111
ITEM_TYPE_COUNT = 64
STORE_TOTAL_SLOTS = 96
MAX_ROOMS = 8
MAX_TRAPS = 16
MAX_MONSTERS = 32
MONSTER_ENTRY_SIZE = 12
MAX_FLOOR_ITEMS = 42
RECALL_DATA_SIZE = 260
# Current Plus/4 product load gate consumes this many map bytes before reading
# the checksum. Keep this explicit until the storage HAL owns per-platform
# record layout instead of inheriting the C64 save shape implicitly.
LOAD_SAVE_MAP_SIZE = 3676
TOTAL_INV_SLOTS = 30

PL_LEVEL = 19
PL_DLEVEL = 20
PL_MAP_X = 49
PL_MAP_Y = 50
PL_LIGHT_RAD = 55
PL_MAX_DLVL = 56


def block(size: int, value: int = 0) -> bytearray:
    return bytearray([value] * size)


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print("usage: make_load_resume_save_plus4.py <save-output> [marker-output]", file=sys.stderr)
        return 1

    out_path = Path(sys.argv[1])
    marker_path = Path(sys.argv[2]) if len(sys.argv) == 3 else None

    player = block(PL_STRUCT_SIZE)
    player[PL_LEVEL] = 1
    player[PL_DLEVEL] = 0
    player[PL_MAP_X] = 10
    player[PL_MAP_Y] = 10
    player[PL_LIGHT_RAD] = 1
    player[PL_MAX_DLVL] = 1

    payload = bytearray()
    payload.extend(b"MORIA+4" + bytes([SAVE_VERSION]))
    payload.extend(player)
    payload.extend(block(160))  # player_background
    payload.extend(block(32))   # zp $40-$5f
    payload.extend(block(1))    # eff_fear_timer
    payload.extend(block(4))    # rng
    for _ in range(8):
        payload.extend(block(TOTAL_INV_SLOTS))
    payload.extend(block(ITEM_TYPE_COUNT))
    payload.extend(block(12))  # potion_shuffle
    payload.extend(block(12))  # scroll_shuffle
    payload.extend(block(4))   # ring_shuffle
    payload.extend(block(5))   # wand_shuffle
    payload.extend(block(5))   # staff_shuffle
    for _ in range(7):
        payload.extend(block(STORE_TOTAL_SLOTS))
    payload.extend(block(6))  # stairs
    payload.extend(block(1))  # level_entry_dir
    payload.extend(block(1))  # room_count
    for _ in range(6):
        payload.extend(block(MAX_ROOMS))
    payload.extend(block(1))  # trap_count
    for _ in range(3):
        payload.extend(block(MAX_TRAPS))
    payload.extend(block(MAX_MONSTERS * MONSTER_ENTRY_SIZE))
    for _ in range(11):
        payload.extend(block(MAX_FLOOR_ITEMS))
    payload.extend(block(RECALL_DATA_SIZE))
    payload.extend(block(LOAD_SAVE_MAP_SIZE))

    checksum = sum(payload) & 0xFFFF
    payload.extend(bytes((checksum & 0xFF, checksum >> 8)))

    out_path.write_bytes(payload)
    if marker_path is not None:
        marker_path.write_bytes(b"M8P4SV")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
