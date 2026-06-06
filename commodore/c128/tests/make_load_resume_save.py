#!/usr/bin/env python3

from pathlib import Path
import sys

SAVE_VERSION = 0x12

PL_STRUCT_SIZE = 111
ITEM_TYPE_COUNT = 82
ITEM_ID_CAPACITY = 96
STORE_TOTAL_SLOTS = 96
MAX_ROOMS = 8
MAX_TRAPS = 16
MAX_MONSTERS = 32
MONSTER_ENTRY_SIZE = 12
MAX_FLOOR_ITEMS = 42
RECALL_DATA_SIZE = 260
MAP_SIZE = 13068
TOTAL_INV_SLOTS = 31

PL_LEVEL = 19
PL_DLEVEL = 20
PL_MAP_X = 49
PL_MAP_Y = 50
PL_LIGHT_RAD = 55
PL_MAX_DLVL = 56


def block(size: int, value: int = 0) -> bytearray:
    return bytearray([value] * size)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: make_load_resume_save.py <output>", file=sys.stderr)
        return 1

    out_path = Path(sys.argv[1])

    player = block(PL_STRUCT_SIZE)
    player[PL_LEVEL] = 1
    player[PL_DLEVEL] = 0
    player[PL_MAP_X] = 10
    player[PL_MAP_Y] = 10
    player[PL_LIGHT_RAD] = 1
    player[PL_MAX_DLVL] = 1

    payload = bytearray()
    payload.extend(b"MORIA01" + bytes([SAVE_VERSION]))
    payload.extend(player)
    payload.extend(block(160))  # player_background
    payload.extend(block(32))   # zp $40-$5f
    payload.extend(block(1))    # eff_fear_timer
    payload.extend(block(4))    # rng
    for _ in range(8):
        payload.extend(block(TOTAL_INV_SLOTS))
    payload.extend(block(ITEM_ID_CAPACITY))
    payload.extend(block(12))
    payload.extend(block(12))
    payload.extend(block(4))
    payload.extend(block(5))
    payload.extend(block(5))
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
    payload.extend(block(MAP_SIZE))

    checksum = sum(payload) & 0xFFFF
    payload.extend(bytes((checksum & 0xFF, checksum >> 8)))

    out_path.write_bytes(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
