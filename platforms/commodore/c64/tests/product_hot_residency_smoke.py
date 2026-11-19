#!/usr/bin/env python3
"""Verify zero disk/ITEM.CAT/overlay reads across C64 hot gameplay paths (no REU).

Exercises normal movement, Shift+direction corridor running (run_initialize +
multi-turn run_step), plain/stuck/locked doors ('o'/'c' + door_pick_roll),
stepping onto a hidden floor trap (trap_trigger), picking up a real pre-warmed
non-gold floor item ('g' via HAL_PLATFORM_ITEM_PICKUP_CACHE in $DD2A-$DEFF),
and dropping a carried item ('d') on a stock non-REU C64 1541 disk build.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
CONNECTOR_DIR = ROOT / "platforms" / "commodore" / "c128" / "tests"
if str(CONNECTOR_DIR) not in sys.path:
    sys.path.insert(0, str(CONNECTOR_DIR))

from vice_connector import VICEConnector, allocate_free_port, monitor_status_has_pc, parse_vs_symbols

sys.path.insert(0, str(ROOT / "tools"))
from item_ids import (  # noqa: E402
    ID_BY_SLUG,
    ITEM_LARGE_IRON_CHEST,
    ITEM_LARGE_STEEL_CHEST,
    ITEM_LARGE_WOODEN_CHEST,
    ITEM_PAGE_BIT,
    ITEM_PAGE_SPELLBOOK_BEGINNERS_MAGICK,
    ITEM_RUINED_CHEST,
    ITEM_SLOT_SPELLBOOK_BEGINNERS_MAGICK,
    ITEM_SMALL_IRON_CHEST,
    ITEM_SMALL_STEEL_CHEST,
    ITEM_SMALL_WOODEN_CHEST,
    item_page,
    item_slot,
)
from vice_config import vice_config  # noqa: E402

GOLD_PAGED_IDS = {
    (item_page(lid), item_slot(lid))
    for slug, lid in ID_BY_SLUG.items()
    if slug.startswith("GOLD_")
}
CHEST_PAGED_IDS = {
    (item_page(lid), item_slot(lid))
    for lid in (
        ITEM_SMALL_WOODEN_CHEST,
        ITEM_LARGE_WOODEN_CHEST,
        ITEM_SMALL_IRON_CHEST,
        ITEM_LARGE_IRON_CHEST,
        ITEM_SMALL_STEEL_CHEST,
        ITEM_LARGE_STEEL_CHEST,
        ITEM_RUINED_CHEST,
    )
}

# N (New), A (Human), CR (accept stats), A (Warrior), A + CR (name),
# B (Female), SPACE (begin), L (step onto '>' in town), '>' (descend to DL1).
BOOT_KEYS = [0x4E, 0x41, 0x0D, 0x41, 0x41, 0x0D, 0x42, 0x20, 0x4C, 0x3E]

MAP_BASE = 0xC000
MAP_COLS = 80
TILE_FLOOR = 0x00
TILE_WALL_H = 0x10
TILE_DOOR_OPEN = 0x70
TILE_DOOR_CLOSED = 0x80
TILE_TRAP = 0xE0
TILE_TYPE_MASK = 0xF0

FLAG_OCCUPIED = 0x01
FLAG_HAS_ITEM = 0x02
FLAG_VISITED = 0x04
FLAG_LIT = 0x08
VISIBLE_LIT = FLAG_VISITED | FLAG_LIT

MAX_MONSTERS = 32
MONSTER_ENTRY_SIZE = 12
MX_X = 0
MX_Y = 1
MX_TYPE = 2
EMPTY_SLOT = 0xFF

MAX_FLOOR_ITEMS = 42
MAX_INV_SLOTS = 22
TRAP_ARROW = 1

PL_CLASS = 18
PL_LEVEL = 19
PL_INT_CUR = 28
PL_DEX_CUR = 30
PL_HP_LO = 33
PL_HP_HI = 34
PL_MHP_LO = 35
PL_MHP_HI = 36
PL_MANA = 37
PL_MAX_MANA = 38
PL_XP_0 = 46
PL_MAP_X = 49
PL_MAP_Y = 50
PL_SPELL_TYPE = 60
PL_SPELLS_LEARNT_0 = 61
CLASS_ROGUE = 3
SPELL_MAGE = 1
OVL_UI = 6
OVL_SPELL = 8

KBDBUF_ADDR = 0x0277
KBDBUF_COUNT_ADDR = 0x00C6

PETSCII_H = 0x48       # west
PETSCII_J = 0x4A       # south
PETSCII_K = 0x4B       # north
PETSCII_L = 0x4C       # east
PETSCII_SHIFT_L = 0xCC # Shift+L: run east
PETSCII_O = 0x4F       # open
PETSCII_C = 0x43       # close
PETSCII_G = 0x47       # get / pickup
PETSCII_D = 0x44       # drop
PETSCII_A = 0x41       # inventory slot 'a'

HEX_BYTE_RE = re.compile(r"^[0-9A-Fa-f]{2}$")


def terminate(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=2.0)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2.0)


def read_bytes(connector: VICEConnector, start: int, count: int) -> list[int]:
    end = (start + count - 1) & 0xFFFF
    response = connector.send_command(f"m {start:04x} {end:04x}")
    values: list[int] = []
    for line in response.splitlines():
        if not line.startswith(">C:"):
            continue
        for token in line.split()[1:]:
            if not HEX_BYTE_RE.match(token):
                break
            values.append(int(token, 16))
            if len(values) >= count:
                return values
    if len(values) != count:
        raise RuntimeError(f"short monitor read at ${start:04X}: wanted {count}, got {len(values)}")
    return values


def write_bytes(connector: VICEConnector, start: int, values: list[int]) -> None:
    chunk_size = 24
    for offset in range(0, len(values), chunk_size):
        chunk = values[offset : offset + chunk_size]
        hex_bytes = " ".join(f"{b & 0xFF:02x}" for b in chunk)
        connector.send_command(f"> {(start + offset) & 0xFFFF:04x} {hex_bytes}")


def tile_addr(x: int, y: int) -> int:
    return MAP_BASE + y * MAP_COLS + x


def step_keys(
    connector: VICEConnector,
    keys: list[int],
    input_get_key_addr: str,
    label: str,
    timeout: float,
) -> None:
    for idx, key_code in enumerate(keys):
        connector.poke(KBDBUF_ADDR, key_code)
        connector.poke(KBDBUF_COUNT_ADDR, 1)
        connector.go()
        res = connector.wait_for_stop(pass_addr=input_get_key_addr, timeout=timeout)
        if not res.passed:
            raise RuntimeError(
                f"{label} (key #{idx}): stopped before next input_get_key "
                f"(unexpected disk/catalog/overlay call or hang):\n"
                f"{res.reason}\n{res.last_status.strip()}"
            )


def count_carried_items(connector: VICEConnector, inv_addr: int) -> int:
    ids = read_bytes(connector, inv_addr, MAX_INV_SLOTS)
    return sum(1 for item_id in ids if item_id != EMPTY_SLOT)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vice", default="x64sc")
    parser.add_argument("--boot-d64", default=str(ROOT / "build" / "moria8-c64.d64"))
    parser.add_argument("--vs", default=str(ROOT / "build" / "c64" / "main.vs"))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--connect-timeout", type=float, default=10.0)
    parser.add_argument("--socket-timeout", type=float, default=2.0)
    parser.add_argument("--boot-timeout", type=float, default=25.0)
    parser.add_argument("--step-timeout", type=float, default=10.0)
    args = parser.parse_args()

    port = args.port or allocate_free_port(args.host)
    symbols = parse_vs_symbols(args.vs)

    main_loop_addr = symbols[".main_loop"]
    input_get_key_addr = symbols[".input_get_key"]
    reu_present_addr = int(symbols[".reu_present"], 16)
    ipc_end_lo_addr = int(symbols[".ipc_end_lo"], 16)
    ipc_end_hi_addr = int(symbols[".ipc_end_hi"], 16)

    zp_player_x = int(symbols[".zp_player_x"], 16)
    zp_player_y = int(symbols[".zp_player_y"], 16)
    zp_player_dlvl = int(symbols[".zp_player_dlvl"], 16)
    zp_player_hp_lo = int(symbols[".zp_player_hp_lo"], 16)
    zp_player_hp_hi = int(symbols[".zp_player_hp_hi"], 16)
    zp_player_mhp_lo = int(symbols[".zp_player_mhp_lo"], 16)
    zp_player_mhp_hi = int(symbols[".zp_player_mhp_hi"], 16)
    zp_player_lvl = int(symbols[".zp_player_lvl"], 16)
    zp_player_int = int(symbols[".zp_player_int"], 16)
    zp_player_dex = int(symbols[".zp_player_dex"], 16)
    zp_mon_count = int(symbols[".zp_mon_count"], 16)
    zp_run_dir = int(symbols[".zp_run_dir"], 16)
    zp_eff_blind = int(symbols[".zp_eff_blind"], 16)

    player_data = int(symbols[".player_data"], 16)
    monster_table = int(symbols[".monster_table"], 16)
    door_state_count = int(symbols[".door_state_count"], 16)
    door_state_x = int(symbols[".door_state_x"], 16)
    door_state_y = int(symbols[".door_state_y"], 16)
    door_state_val = int(symbols[".door_state_val"], 16)
    trap_count = int(symbols[".trap_count"], 16)
    trap_x = int(symbols[".trap_x"], 16)
    trap_y = int(symbols[".trap_y"], 16)
    trap_type = int(symbols[".trap_type"], 16)

    fi_item_id = int(symbols[".fi_item_id"], 16)
    fi_x = int(symbols[".fi_x"], 16)
    fi_y = int(symbols[".fi_y"], 16)
    fi_meta_hi = int(symbols[".fi_meta_hi"], 16)
    inv_item_id = int(symbols[".inv_item_id"], 16)
    inv_qty = int(symbols[".inv_qty"], 16)
    inv_ego = int(symbols[".inv_ego"], 16)
    zp_player_mp = int(symbols[".zp_player_mp"], 16)
    zp_player_mmp = int(symbols[".zp_player_mmp"], 16)
    current_overlay_addr = int(symbols[".current_overlay"], 16)

    disk_watch_syms = (
        ".c64_disk_open",
        ".c64_disk_load",
        ".kernal_load_safe",
        ".overlay_load_disk",
        ".hal_item_cat_read_byte",
        ".catalog_fetch_record",
    )
    disk_watch_addrs = [symbols[name] for name in disk_watch_syms]

    command = [
        args.vice,
        "-config",
        vice_config(args.vice),
        "-default",
        "+saveres",
        "+autostart-delay-random",
        "+reu",
        "-console",
        "-warp",
        "+sound",
        "-sounddev",
        "dummy",
        "-remotemonitor",
        "-remotemonitoraddress",
        f"{args.host}:{port}",
        "-autostart",
        str(Path(args.boot_d64).resolve()),
        "-limitcycles",
        "900000000",
    ]

    vice = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    connector = VICEConnector(host=args.host, port=port, timeout=args.socket_timeout)
    try:
        connector.connect(
            retries=max(1, int(args.connect_timeout / 0.1)),
            retry_delay=0.1,
        )

        # Feed each chargen + town-stairs key deterministically at input_get_key
        # (never racing 1541 disk boot or input_modal_prepare buffer drains).
        connector.clear_breakpoints()
        connector.send_command(f"break ${input_get_key_addr}")
        for idx, key_code in enumerate(BOOT_KEYS):
            connector.go()
            key_res = connector.wait_for_stop(pass_addr=input_get_key_addr, timeout=args.boot_timeout)
            if not key_res.passed:
                print(f"FAIL: did not reach input_get_key for boot key #{idx}: {key_res.reason}")
                if key_res.last_status:
                    print(key_res.last_status.strip())
                return 2
            connector.poke(KBDBUF_ADDR, key_code)
            connector.poke(KBDBUF_COUNT_ADDR, 1)

        connector.clear_breakpoints()
        connector.send_command(
            f"break ${main_loop_addr} if (@cpu:$0001 & $01) == $00 && @cpu:${zp_player_dlvl:04x} == $01"
        )
        connector.go()
        boot_res = connector.wait_for_stop(pass_addr=main_loop_addr, timeout=args.boot_timeout)
        if not boot_res.passed or not monitor_status_has_pc(boot_res.last_status.upper(), main_loop_addr):
            print(f"FAIL: did not reach Dungeon Level 1 main_loop: {boot_res.reason}")
            if boot_res.last_status:
                print(boot_res.last_status.strip())
            return 2

        reu_val = read_bytes(connector, reu_present_addr, 1)[0]
        dlvl_val = read_bytes(connector, zp_player_dlvl, 1)[0]
        ipc_end = read_bytes(connector, ipc_end_lo_addr, 1)[0] | (
            read_bytes(connector, ipc_end_hi_addr, 1)[0] << 8
        )
        if reu_val != 0:
            print(f"FAIL: expected reu_present == 0 (stock non-REU C64), got {reu_val}")
            return 2
        if dlvl_val != 1:
            print(f"FAIL: expected zp_player_dlvl == 1, got {dlvl_val}")
            return 2
        if ipc_end <= 0xDD2A or ipc_end > 0xDF00:
            print(f"FAIL: item_pickup_cache_prewarm cursor out of bounds: ${ipc_end:04X}")
            return 2

        # Clear monsters so random AI actions cannot interfere with corridor steps.
        mon_bytes = read_bytes(connector, monster_table, MAX_MONSTERS * MONSTER_ENTRY_SIZE)
        for slot in range(MAX_MONSTERS):
            base = slot * MONSTER_ENTRY_SIZE
            if mon_bytes[base + MX_TYPE] != EMPTY_SLOT:
                mx, my = mon_bytes[base + MX_X], mon_bytes[base + MX_Y]
                if mx < MAP_COLS and my < 48:
                    cur_t = read_bytes(connector, tile_addr(mx, my), 1)[0]
                    connector.poke(tile_addr(mx, my), cur_t & ~FLAG_OCCUPIED)
                connector.poke(monster_table + base + MX_TYPE, EMPTY_SLOT)
        connector.poke(zp_mon_count, 0)

        # Clear old player occupancy before carving the controlled test corridor.
        old_px = read_bytes(connector, zp_player_x, 1)[0]
        old_py = read_bytes(connector, zp_player_y, 1)[0]
        if old_px < MAP_COLS and old_py < 48:
            cur_t = read_bytes(connector, tile_addr(old_px, old_py), 1)[0]
            connector.poke(tile_addr(old_px, old_py), cur_t & ~FLAG_OCCUPIED)

        # Pick a REAL non-gold, non-chest floor item already spawned & pre-warmed on DL1.
        f_ids = read_bytes(connector, fi_item_id, MAX_FLOOR_ITEMS)
        f_xs = read_bytes(connector, fi_x, MAX_FLOOR_ITEMS)
        f_ys = read_bytes(connector, fi_y, MAX_FLOOR_ITEMS)
        f_meta = read_bytes(connector, fi_meta_hi, MAX_FLOOR_ITEMS)
        chosen_slot = None
        for idx in range(MAX_FLOOR_ITEMS):
            iid = f_ids[idx]
            if iid == EMPTY_SLOT:
                continue
            page = f_meta[idx] & ITEM_PAGE_BIT
            if f_xs[idx] < MAP_COLS and f_ys[idx] < 48:
                cur_t = read_bytes(connector, tile_addr(f_xs[idx], f_ys[idx]), 1)[0]
                connector.poke(tile_addr(f_xs[idx], f_ys[idx]), cur_t & ~FLAG_HAS_ITEM)
            is_gold = (page, iid) in GOLD_PAGED_IDS
            is_chest = (page, iid) in CHEST_PAGED_IDS
            if chosen_slot is None and not is_gold and not is_chest:
                chosen_slot = idx
            else:
                connector.poke(fi_item_id + idx, EMPTY_SLOT)

        if chosen_slot is None:
            print("FAIL: no non-gold floor item spawned on Dungeon Level 1")
            return 2

        # Carve sealed 1-tile-wide corridor at y=10, x=20..25 inside granite walls (18..27, 8..12).
        wall_row = [TILE_WALL_H | VISIBLE_LIT] * 10
        for y in range(8, 13):
            write_bytes(connector, tile_addr(18, y), wall_row)
        write_bytes(connector, tile_addr(20, 10), [TILE_FLOOR | VISIBLE_LIT] * 6)

        # Plain closed door at (19,10), locked closed door at (20,9), stuck closed door at (20,11).
        connector.poke(tile_addr(19, 10), TILE_DOOR_CLOSED | VISIBLE_LIT)
        connector.poke(tile_addr(20, 9), TILE_DOOR_CLOSED | VISIBLE_LIT)
        connector.poke(tile_addr(20, 11), TILE_DOOR_CLOSED | VISIBLE_LIT)
        connector.poke(door_state_count, 2)
        write_bytes(connector, door_state_x, [20, 20])
        write_bytes(connector, door_state_y, [9, 11])
        write_bytes(connector, door_state_val, [11, 0xFF])  # 11 = locked, -1 ($FF) = stuck

        # Hidden arrow trap at (21,10); relocate real pre-warmed floor item to (22,10).
        connector.poke(trap_count, 1)
        connector.poke(trap_x, 21)
        connector.poke(trap_y, 10)
        connector.poke(trap_type, TRAP_ARROW)

        connector.poke(fi_x + chosen_slot, 22)
        connector.poke(fi_y + chosen_slot, 10)
        connector.poke(tile_addr(22, 10), TILE_FLOOR | FLAG_HAS_ITEM | VISIBLE_LIT)

        # Place player at (20,10) with high HP and saturated disarm skill (127 > lock 11 + 100).
        connector.poke(zp_player_x, 20)
        connector.poke(zp_player_y, 10)
        connector.poke(player_data + PL_MAP_X, 20)
        connector.poke(player_data + PL_MAP_Y, 10)
        connector.poke(tile_addr(20, 10), TILE_FLOOR | FLAG_OCCUPIED | VISIBLE_LIT)

        connector.poke(zp_player_hp_lo, 200)
        connector.poke(zp_player_hp_hi, 0)
        connector.poke(zp_player_mhp_lo, 200)
        connector.poke(zp_player_mhp_hi, 0)
        connector.poke(player_data + PL_HP_LO, 200)
        connector.poke(player_data + PL_HP_HI, 0)
        connector.poke(player_data + PL_MHP_LO, 200)
        connector.poke(player_data + PL_MHP_HI, 0)
        connector.poke(zp_player_lvl, 40)
        connector.poke(player_data + PL_LEVEL, 40)
        connector.poke(zp_player_dex, 118)
        connector.poke(player_data + PL_DEX_CUR, 118)
        connector.poke(zp_player_int, 118)
        connector.poke(player_data + PL_INT_CUR, 118)
        write_bytes(connector, player_data + PL_XP_0, [0, 0, 0])
        write_bytes(connector, zp_eff_blind, [0, 0, 0])  # blind, confuse, paralyze = 0

        # Advance from DL1 main_loop to its idle input_get_key prompt, then arm
        # zero-disk / zero-ITEM.CAT / zero-catalog / zero-overlay-load traps.
        connector.clear_breakpoints()
        connector.send_command(f"break ${input_get_key_addr}")
        connector.go()
        idle_res = connector.wait_for_stop(pass_addr=input_get_key_addr, timeout=args.step_timeout)
        if not idle_res.passed:
            print(f"FAIL: did not reach DL1 idle input_get_key: {idle_res.reason}")
            return 2

        for addr in disk_watch_addrs:
            if int(addr, 16) < 0xA000:
                connector.send_command(f"break ${addr}")
            else:
                connector.send_command(f"break ${addr} if (@cpu:$0001 & $01) == $00")
        connector.send_command("break $ffc0 if (@cpu:$0001 & $02) != $00")
        connector.send_command("break $ffd5 if (@cpu:$0001 & $02) != $00")

        # 1. Plain door open ('o' west) + close ('c' west).
        step_keys(connector, [PETSCII_O, PETSCII_H], input_get_key_addr, "open plain door", args.step_timeout)
        if (read_bytes(connector, tile_addr(19, 10), 1)[0] & TILE_TYPE_MASK) != TILE_DOOR_OPEN:
            print("FAIL: plain door at (19,10) did not open")
            return 2

        step_keys(connector, [PETSCII_C, PETSCII_H], input_get_key_addr, "close plain door", args.step_timeout)
        if (read_bytes(connector, tile_addr(19, 10), 1)[0] & TILE_TYPE_MASK) != TILE_DOOR_CLOSED:
            print("FAIL: plain door at (19,10) did not close")
            return 2

        # 2. Stuck door ('o' south) stays closed in resident RAM.
        step_keys(connector, [PETSCII_O, PETSCII_J], input_get_key_addr, "open stuck door", args.step_timeout)
        if (read_bytes(connector, tile_addr(20, 11), 1)[0] & TILE_TYPE_MASK) != TILE_DOOR_CLOSED:
            print("FAIL: stuck door at (20,11) unexpectedly opened")
            return 2

        # 3. Locked door ('o' north + SPACE for -MORE-) runs banked door_pick_roll, unlocks, and opens.
        step_keys(connector, [PETSCII_O, PETSCII_K, 0x20], input_get_key_addr, "pick locked door", args.step_timeout)
        if (read_bytes(connector, tile_addr(20, 9), 1)[0] & TILE_TYPE_MASK) != TILE_DOOR_OPEN:
            print("FAIL: locked door at (20,9) did not unlock and open")
            return 2
        if read_bytes(connector, door_state_count, 1)[0] != 1:
            print("FAIL: locked door entry was not cleared from door_state table")
            return 2

        # 4. Step east onto hidden arrow trap at (21,10) -> trap_trigger reveals TILE_TRAP and deals 1d8.
        step_keys(connector, [PETSCII_L], input_get_key_addr, "step onto floor trap", args.step_timeout)
        if read_bytes(connector, zp_player_x, 1)[0] != 21:
            print("FAIL: player did not move onto trap tile (21,10)")
            return 2
        if (read_bytes(connector, tile_addr(21, 10), 1)[0] & TILE_TYPE_MASK) != TILE_TRAP:
            print("FAIL: floor trap at (21,10) was not revealed by trap_trigger")
            return 2
        if read_bytes(connector, zp_player_hp_lo, 1)[0] >= 200:
            print("FAIL: arrow trap at (21,10) did not apply damage")
            return 2

        # 5. Step east onto pre-warmed non-gold floor item at (22,10) and pick it up ('g').
        inv_before = count_carried_items(connector, inv_item_id)
        step_keys(connector, [PETSCII_L], input_get_key_addr, "step onto floor item", args.step_timeout)
        if read_bytes(connector, zp_player_x, 1)[0] != 22:
            print("FAIL: player did not reach floor item tile (22,10)")
            return 2

        step_keys(connector, [PETSCII_G], input_get_key_addr, "pickup non-gold floor item", args.step_timeout)
        if read_bytes(connector, fi_item_id + chosen_slot, 1)[0] != EMPTY_SLOT:
            print("FAIL: floor item slot was not cleared on 'g' pickup")
            return 2
        inv_after_get = count_carried_items(connector, inv_item_id)
        if inv_after_get < inv_before:
            print("FAIL: carried inventory shrank after 'g' pickup")
            return 2

        # 6. Shift+L corridor run from (22,10) -> (25,10) (run_initialize + 3 run_step turns).
        step_keys(connector, [PETSCII_SHIFT_L], input_get_key_addr, "Shift+L corridor run", args.step_timeout)
        final_x = read_bytes(connector, zp_player_x, 1)[0]
        if final_x != 25:
            print(f"FAIL: Shift+L corridor run stopped at x={final_x}, expected x=25")
            return 2

        # 7. Drop carried item 'a' ('d' + 'a') at (25,10) with zero disk access.
        step_keys(connector, [PETSCII_D, PETSCII_A], input_get_key_addr, "drop carried item", args.step_timeout)
        if (read_bytes(connector, tile_addr(25, 10), 1)[0] & FLAG_HAS_ITEM) == 0:
            print("FAIL: 'd' drop did not place item on floor at (25,10)")
            return 2

        # 8. Seed [Beginners-Magick] in free carried slot 10 and grant Light
        # (spell 3: 0% fail at Rogue L23 / INT 118, 3 MP cost), warm OVL_SPELL
        # once, then verify 0 disk/overlay reads on cancel + repeat cast, and
        # cached OVL_UI across Book-'?' -> Spell-'?'.
        connector.clear_breakpoints()
        connector.send_command(f"break ${input_get_key_addr}")
        connector.poke(inv_item_id + 10, ITEM_SLOT_SPELLBOOK_BEGINNERS_MAGICK)
        connector.poke(inv_qty + 10, 1)
        connector.poke(inv_ego + 10, ITEM_PAGE_SPELLBOOK_BEGINNERS_MAGICK)
        connector.poke(player_data + PL_CLASS, CLASS_ROGUE)
        connector.poke(player_data + PL_LEVEL, 23)
        connector.poke(zp_player_lvl, 23)
        connector.poke(player_data + PL_SPELL_TYPE, SPELL_MAGE)
        connector.poke(player_data + PL_MANA, 50)
        connector.poke(player_data + PL_MAX_MANA, 40)
        connector.poke(zp_player_mp, 50)
        connector.poke(zp_player_mmp, 40)
        connector.poke(player_data + PL_SPELLS_LEARNT_0, 0x08)

        # Warm-up cast ('m', 'a', 'a') loads OVL_SPELL once (50 -> 47 MP).
        step_keys(connector, [0x4D, PETSCII_A, PETSCII_A], input_get_key_addr, "warmup cast", args.boot_timeout)
        if read_bytes(connector, zp_player_mp, 1)[0] != 47 or read_bytes(connector, current_overlay_addr, 1)[0] != OVL_SPELL:
            print("FAIL: warmup cast did not leave mp=47 and current_overlay=OVL_SPELL")
            return 2

        # Re-arm all zero-disk / zero-overlay-load traps for cancel + repeat cast.
        for addr in disk_watch_addrs:
            if int(addr, 16) < 0xA000:
                connector.send_command(f"break ${addr}")
            else:
                connector.send_command(f"break ${addr} if (@cpu:$0001 & $01) == $00")
        connector.send_command("break $ffc0 if (@cpu:$0001 & $02) != $00")
        connector.send_command("break $ffd5 if (@cpu:$0001 & $02) != $00")

        step_keys(connector, [0x4D, 0x20], input_get_key_addr, "cast cancel", args.step_timeout)
        step_keys(connector, [0x4D, PETSCII_A, PETSCII_A], input_get_key_addr, "repeat cast", args.step_timeout)
        if read_bytes(connector, zp_player_mp, 1)[0] != 44 or read_bytes(connector, current_overlay_addr, 1)[0] != OVL_SPELL:
            print("FAIL: repeat cast did not spend 3 MP (47->44) in warm OVL_SPELL")
            return 2

        # Book-'?' loads OVL_UI once; Spell-'?' must hit cached OVL_UI with 0 reloads.
        connector.clear_breakpoints()
        connector.send_command(f"break ${input_get_key_addr}")
        step_keys(connector, [0x4D, 0x3F, PETSCII_A], input_get_key_addr, "book '?' list", args.boot_timeout)
        if read_bytes(connector, current_overlay_addr, 1)[0] != OVL_UI:
            print("FAIL: book '?' did not keep OVL_UI cached")
            return 2
        ovl_disk_addr = symbols[".overlay_load_disk"]
        if int(ovl_disk_addr, 16) < 0xA000:
            connector.send_command(f"break ${ovl_disk_addr}")
        else:
            connector.send_command(f"break ${ovl_disk_addr} if (@cpu:$0001 & $01) == $00")
        step_keys(connector, [0x3F, 0x20], input_get_key_addr, "spell '?' cached OVL_UI", args.step_timeout)

        print(
            f"PASS: product_hot_residency_smoke (reu=0, cache=${ipc_end:04X}, "
            f"item_id={f_ids[chosen_slot]}, 0 disk/ITEM.CAT/overlay reads incl. repeat cast & '?' cache)"
        )
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL: {exc}")
        return 2
    finally:
        connector.close()
        terminate(vice)


if __name__ == "__main__":
    raise SystemExit(main())
