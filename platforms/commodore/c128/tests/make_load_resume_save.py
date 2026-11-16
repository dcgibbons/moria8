#!/usr/bin/env python3

from pathlib import Path
import os
import sys

# The C128 product build writes Save Format V2 ($20) with the 370-item Base-255
# paged catalog, 34 inventory slots (including EQUIP_CLOAK = 32 and
# EQUIP_SECONDARY = 33), 47-byte known-item bitset, 174-byte flavour shuffles,
# 8 store arrays (including si_meta_hi), 11 floor-item blocks (including
# fi_meta_hi), and 279 creature rows of persistent recall (1,116 B).
SAVE_VERSION = 0x21
LEGACY_ROOM8_SAVE_VERSION = 0x12
LEGACY_TOTAL_INV_SLOTS = 31
ID_KNOWN_BYTES = 47
FLAVOUR_COUNT = 174
LEGACY_FLAVOUR_COUNT = 38
MAX_DOOR_STATES = 16
CATALOG_SLOTS = 32

PL_STRUCT_SIZE = 111
ITEM_ID_CAPACITY = 96
STORE_TOTAL_SLOTS = 128
MAX_ROOMS = 21
LEGACY_MAX_ROOMS = 8
MAX_TRAPS = 16
MAX_MONSTERS = 32
MONSTER_ENTRY_SIZE = 12
MAX_FLOOR_ITEMS = 42
RECALL_DATA_SIZE = 1116          # 279 creature rows x 4 (core/recall_defs.s)
LEGACY_RECALL_DATA_SIZE = 160
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
    if len(sys.argv) not in (2, 3):
        print("usage: make_load_resume_save.py <output> [--legacy-room8]", file=sys.stderr)
        return 1

    out_path = Path(sys.argv[1])
    legacy_room8 = (len(sys.argv) == 3 and sys.argv[2] == "--legacy-room8") or os.environ.get("C128_LEGACY_ROOM8") == "1"
    if len(sys.argv) == 3 and not legacy_room8:
        print("unknown option", file=sys.stderr)
        return 1
    save_version = LEGACY_ROOM8_SAVE_VERSION if legacy_room8 else SAVE_VERSION
    max_rooms = LEGACY_MAX_ROOMS if legacy_room8 else MAX_ROOMS
    inv_slots = LEGACY_TOTAL_INV_SLOTS if legacy_room8 else TOTAL_INV_SLOTS
    known_bytes = ITEM_ID_CAPACITY if legacy_room8 else ID_KNOWN_BYTES
    flavour_bytes = LEGACY_FLAVOUR_COUNT if legacy_room8 else FLAVOUR_COUNT
    store_arrays = 7 if legacy_room8 else 8
    recall_bytes = LEGACY_RECALL_DATA_SIZE if legacy_room8 else RECALL_DATA_SIZE

    player = block(PL_STRUCT_SIZE)
    player[PL_LEVEL] = 1
    player[PL_DLEVEL] = 0
    player[PL_MAP_X] = 10
    player[PL_MAP_Y] = 10
    player[PL_LIGHT_RAD] = 1
    player[PL_MAX_DLVL] = 1

    payload = bytearray()
    payload.extend(b"MORIA01" + bytes([save_version]))
    payload.extend(player)
    payload.extend(block(160))  # player_background
    payload.extend(block(32))   # zp $40-$5f
    payload.extend(block(1))    # eff_fear_timer
    payload.extend(block(4))    # rng
    item_ids = block(inv_slots, 0 if legacy_room8 else 0xFF)
    payload.extend(item_ids)
    for _ in range(7):
        payload.extend(block(inv_slots))
    payload.extend(block(known_bytes))
    payload.extend(block(flavour_bytes))
    if legacy_room8:
        for _ in range(store_arrays):
            payload.extend(block(STORE_TOTAL_SLOTS))
    else:
        payload.extend(block(STORE_TOTAL_SLOTS, 0xFF))  # si_item_id: all empty
        for _ in range(store_arrays - 1):
            payload.extend(block(STORE_TOTAL_SLOTS))
    payload.extend(block(6))  # stairs
    payload.extend(block(1))  # level_entry_dir
    payload.extend(block(1))  # room_count
    for _ in range(6):
        payload.extend(block(max_rooms))
    payload.extend(block(1))  # trap_count
    for _ in range(3):
        payload.extend(block(MAX_TRAPS))
    payload.extend(block(MAX_MONSTERS * MONSTER_ENTRY_SIZE))
    if not legacy_room8:
        payload.extend(block(1 + MAX_DOOR_STATES * 3))   # door-state table
        payload.extend(block(CATALOG_SLOTS))              # species ids lo
        payload.extend(block(CATALOG_SLOTS, 0xFF))        # species ids hi: all empty
    payload.extend(block(MAX_FLOOR_ITEMS, 0 if legacy_room8 else 0xFF))
    for _ in range(10):
        payload.extend(block(MAX_FLOOR_ITEMS))
    payload.extend(block(recall_bytes))
    payload.extend(block(MAP_SIZE))

    checksum = sum(payload) & 0xFFFF
    payload.extend(bytes((checksum & 0xFF, checksum >> 8)))

    out_path.write_bytes(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
