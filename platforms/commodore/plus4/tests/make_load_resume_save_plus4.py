#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

# The Plus/4 product build writes Save Format V2 ($22; older saves refused):
# 34 inventory slots, 47-byte known-item bitset, 174-byte flavour shuffles,
# 8 store arrays, door-state + species tables, 11 floor-item arrays, and 279
# creature rows of recall (1,116 B, hal/storage_policy.s, platforms/shared/save.s).
SAVE_VERSION = 0x22
ID_KNOWN_BYTES = 47
MAX_DOOR_STATES = 16
CATALOG_SLOTS = 32

PL_STRUCT_SIZE = 114
STORE_TOTAL_SLOTS = 128
MAX_ROOMS = 8
MAX_TRAPS = 16
MAX_MONSTERS = 32
MONSTER_ENTRY_SIZE = 12
MAX_FLOOR_ITEMS = 42
RECALL_DATA_SIZE = 1116   # 279 creature rows x 4 (core/6502/recall_defs.s)
# Current Plus/4 product load gate consumes this many map bytes before reading
# the checksum. Keep this explicit until the storage HAL owns per-platform
# record layout instead of inheriting the C64 save shape implicitly.
LOAD_SAVE_MAP_SIZE = 3840
TOTAL_INV_SLOTS = 34

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
    item_ids = block(TOTAL_INV_SLOTS)
    item_ids[32] = item_ids[33] = 0xFF   # cloak and secondary: empty
    payload.extend(item_ids)
    for _ in range(7):
        payload.extend(block(TOTAL_INV_SLOTS))
    payload.extend(block(ID_KNOWN_BYTES))
    payload.extend(block(46))  # potion_shuffle
    payload.extend(block(49))  # scroll_shuffle
    payload.extend(block(30))  # ring_shuffle
    payload.extend(block(24))  # wand_shuffle
    payload.extend(block(25))  # staff_shuffle
    for _ in range(8):
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
    payload.extend(block(1 + MAX_DOOR_STATES * 3))   # door-state table
    payload.extend(block(CATALOG_SLOTS))              # species ids lo
    payload.extend(block(CATALOG_SLOTS, 0xFF))        # species ids hi: all empty
    for _ in range(11):
        payload.extend(block(MAX_FLOOR_ITEMS))
    payload.extend(block(RECALL_DATA_SIZE))
    payload.extend(block(LOAD_SAVE_MAP_SIZE))

    checksum = sum(payload) & 0xFFFF
    payload.extend(bytes((checksum & 0xFF, checksum >> 8)))

    out_path.write_bytes(payload)
    if marker_path is not None:
        marker_path.write_bytes(b"M8SAVE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
