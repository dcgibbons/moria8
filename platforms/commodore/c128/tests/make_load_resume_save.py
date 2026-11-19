#!/usr/bin/env python3

from pathlib import Path
import sys

# The C128 product build writes Save Format V2 ($22) with the 361-item Base-255
# paged catalog, 34 inventory slots (including EQUIP_CLOAK = 32 and
# EQUIP_SECONDARY = 33), 47-byte known-item bitset, 174-byte flavour shuffles,
# 8 store arrays (including si_meta_hi), 11 floor-item blocks (including
# fi_meta_hi), and 279 creature rows of persistent recall (1,116 B).
SAVE_VERSION = 0x22
ID_KNOWN_BYTES = 47
FLAVOUR_COUNT = 174
MAX_DOOR_STATES = 16
CATALOG_SLOTS = 32

PL_STRUCT_SIZE = 114
STORE_TOTAL_SLOTS = 128
MAX_ROOMS = 21
MAX_TRAPS = 16
MAX_MONSTERS = 32
MONSTER_ENTRY_SIZE = 12
MAX_FLOOR_ITEMS = 42
RECALL_DATA_SIZE = 1116          # 279 creature rows x 4 (core/recall_defs.s)
MAP_SIZE = 13068
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
    payload.extend(block(TOTAL_INV_SLOTS, 0xFF))
    for _ in range(7):
        payload.extend(block(TOTAL_INV_SLOTS))
    payload.extend(block(ID_KNOWN_BYTES))
    payload.extend(block(FLAVOUR_COUNT))
    payload.extend(block(STORE_TOTAL_SLOTS, 0xFF))  # si_item_id: all empty
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
    payload.extend(block(1 + MAX_DOOR_STATES * 3))   # door-state table
    payload.extend(block(CATALOG_SLOTS))              # species ids lo
    payload.extend(block(CATALOG_SLOTS, 0xFF))        # species ids hi: all empty
    payload.extend(block(MAX_FLOOR_ITEMS, 0xFF))
    for _ in range(10):
        payload.extend(block(MAX_FLOOR_ITEMS))
    payload.extend(block(RECALL_DATA_SIZE))
    payload.extend(block(MAP_SIZE))

    checksum = sum(payload) & 0xFFFF
    payload.extend(bytes((checksum & 0xFF, checksum >> 8)))

    out_path.write_bytes(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
