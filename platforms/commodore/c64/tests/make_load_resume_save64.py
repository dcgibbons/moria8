#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

SAVE_VERSION = 0x11
SPLIT_SAVE_VERSION = 0x16

PL_STRUCT_SIZE = 111
ITEM_TYPE_COUNT = 96
ITEM_ID_CAPACITY = 160
STORE_TOTAL_SLOTS = 96
MAX_ROOMS = 8
MAX_TRAPS = 16
MAX_MONSTERS = 32
MONSTER_ENTRY_SIZE = 12
MAX_FLOOR_ITEMS = 42
RECALL_DATA_SIZE = 260
MAP_SIZE = 3840
TOTAL_INV_SLOTS = 31

PL_LEVEL = 19
PL_DLEVEL = 20
PL_MAP_X = 10
PL_MAP_Y = 11
PL_LIGHT_RAD = 55
PL_MAX_DLVL = 56


def block(size: int, value: int = 0) -> bytearray:
    return bytearray([value] * size)


def make_fields(version: int, *, split: bool) -> tuple[bytearray, bytearray]:
    player = block(PL_STRUCT_SIZE)
    player[PL_LEVEL] = 1
    player[PL_DLEVEL] = 0
    player[PL_MAP_X] = 10
    player[PL_MAP_Y] = 10
    player[PL_LIGHT_RAD] = 1
    player[PL_MAX_DLVL] = 1

    payload = bytearray(b"MORIA01" + bytes([version]))
    payload.extend(player)
    payload.extend(block(160))  # player_background
    payload.extend(block(32))   # zp $40-$5f
    payload.extend(block(1))    # eff_fear_timer
    payload.extend(block(4))    # rng
    for _ in range(8):
        payload.extend(block(TOTAL_INV_SLOTS))
    payload.extend(block((ITEM_ID_CAPACITY + 7) // 8 if split else 96))
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
    if split:
        payload.extend(block(1))  # door_state_count
        payload.extend(block(3 * 16))  # door state x/y/value arrays
    for _ in range(11):
        payload.extend(block(MAX_FLOOR_ITEMS))
    payload.extend(block(RECALL_DATA_SIZE))
    dungeon_map = block(MAP_SIZE)
    dungeon_map[-1] = 0x10  # Far-corner wall probes the final staged-copy page.
    return payload, dungeon_map


def apply_variant(data: bytearray, variant: str, *, header: bool) -> bytearray | None:
    if variant == "missing":
        return None
    result = bytearray(data)
    if variant == "corrupt":
        result[-1] ^= 0x01
    elif variant == "wrong-header":
        if not header:
            raise ValueError("wrong-header requires a PRG fixture")
        result[0] ^= 0x01
    elif variant == "short":
        result.pop()
    elif variant == "oversized":
        result.append(0)
    return result


def write_legacy(out_path: Path) -> None:
    payload, dungeon_map = make_fields(SAVE_VERSION, split=False)
    payload.extend(dungeon_map)
    checksum = sum(payload) & 0xFFFF
    payload.extend(bytes((checksum & 0xFF, checksum >> 8)))
    out_path.write_bytes(payload)


def write_split(
    state_path: Path,
    map_path: Path,
    state_variant: str,
    map_variant: str,
) -> None:
    state_data, dungeon_map = make_fields(SPLIT_SAVE_VERSION, split=True)
    map_checksum = sum(dungeon_map) & 0xFFFF
    state_checksum = sum(state_data) & 0xFFFF
    state = bytearray((0x00, 0xC0))
    state.extend(state_data)
    state.extend((map_checksum & 0xFF, map_checksum >> 8))
    state.extend((state_checksum & 0xFF, state_checksum >> 8))
    map_file = bytearray((0x00, 0xC0))
    map_file.extend(dungeon_map)

    if len(state) != 2560 or len(map_file) != 3842:
        raise ValueError(f"split fixture shape mismatch: state={len(state)} map={len(map_file)}")

    state_result = apply_variant(state, state_variant, header=True)
    map_result = apply_variant(map_file, map_variant, header=True)
    if state_result is not None:
        state_path.write_bytes(state_result)
    if map_result is not None:
        map_path.write_bytes(map_result)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("save_output", nargs="?", type=Path)
    parser.add_argument("legacy_marker_output", nargs="?", type=Path)
    parser.add_argument("--split-v16", nargs=2, metavar=("STATE_OUTPUT", "MAP_OUTPUT"), type=Path)
    variants = ("valid", "missing", "corrupt", "wrong-header", "short", "oversized")
    parser.add_argument("--state-variant", choices=variants, default="valid")
    parser.add_argument("--map-variant", choices=variants, default="valid")
    parser.add_argument("--marker-output", type=Path)
    args = parser.parse_args()

    if args.split_v16:
        if args.save_output or args.legacy_marker_output:
            parser.error("positional outputs cannot be combined with --split-v16")
        write_split(*args.split_v16, args.state_variant, args.map_variant)
        marker_path = args.marker_output
    else:
        if args.save_output is None:
            parser.error("save-output is required unless --split-v16 is used")
        if args.state_variant != "valid" or args.map_variant != "valid":
            parser.error("fixture variants require --split-v16")
        write_legacy(args.save_output)
        marker_path = args.marker_output or args.legacy_marker_output

    if marker_path is not None:
        marker_path.write_bytes(b"M8SAVE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
