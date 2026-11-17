#!/usr/bin/env python3
"""Plus/4 runtime smoke proving 0 disk / overlay accesses on hot DL1 gameplay paths.

Boots the real Plus/4 disk build (.d64), enters DL1 through normal Town stairs
so level generation and item_pickup_cache_prewarm run naturally, stages a
deterministic corridor fixture on DL1, arms VICE CPU execution breakpoints on:
  - .plus4_kernal_open
  - .plus4_kernal_load
  - .overlay_load_disk
  - .hal_item_cat_read_byte
  - .catalog_fetch_record
and runs the live main_loop command sequence:
  1) Normal directional moves ('L', 'H')
  2) Shift+dir corridor run ('SHIFT+L' -> run_initialize + multi-step run_step)
  3) Plain door open ('O'), close ('C'), and re-open ('O') + step through
  4) Locked door open ('O' -> door_pick_roll + player_disarm_get_effective_chance)
  5) Stepping onto a floor trap (TRAP_ARROW -> resident $F000 trap_trigger)
  6) Stepping onto and picking up ('G') a non-gold floor item (item_pickup +
     $0600-$07FF ITEM_PICKUP_CACHE)
Fails immediately if any disk/KERNAL/overlay/catalog routine executes even once,
and verifies every gameplay state transition in RAM at completion.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[3]
sys.path.insert(0, str(REPO_ROOT / "tools"))
sys.path.insert(0, str(SCRIPT_DIR))

from vice_config import vice_config  # noqa: E402
from vice_connector import (  # noqa: E402
    VICEConnector,
    allocate_free_port,
    monitor_status_has_pc,
    normalize_addr,
    parse_vs_symbols,
)
from product_scripted_smoke import (  # noqa: E402
    REGISTER_PC_RE,
    read_monitor_byte,
    read_monitor_bytes,
    terminate_vice,
)

MAP_BASE = 0xC800
MAP_COLS = 80
MAX_FLOOR_ITEMS = 42
MAX_INV_SLOTS = 22
ITEM_PAGE_BIT = 0x40
FI_EMPTY = 0xFF

TILE_FLOOR = 0x00
TILE_WALL_H = 0x10
TILE_DOOR_OPEN = 0x70
TILE_DOOR_CLOSED = 0x80
TILE_TRAP = 0xE0
TILE_TYPE_MASK = 0xF0
FLAG_HAS_ITEM = 0x02
FLAG_VISITED = 0x04
FLAG_LIT = 0x08
VIS_LIT = FLAG_VISITED | FLAG_LIT

TRAP_ARROW = 1

PL_CLASS = 18
PL_LEVEL = 19
PL_INT_CUR = 28
PL_DEX_CUR = 30
PL_HP_LO = 33
PL_HP_HI = 34
PL_MHP_LO = 35
PL_MHP_HI = 36
PL_MAP_X = 49
PL_MAP_Y = 50
CLASS_ROGUE = 3


def sym_int(symbols: dict[str, str], name: str) -> int:
    if name not in symbols:
        raise KeyError(f"missing symbol {name} in main.vs")
    return int(symbols[name], 16)


def wait_for_pc(connector: VICEConnector, target_pc: int, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        reg_text = connector.send_command("r")
        match = REGISTER_PC_RE.search(reg_text)
        if match and int(match.group(1), 16) == target_pc:
            return True
        connector.send_command("g", expect_prompt=False)
        time.sleep(0.15)
        # Sending an empty newline interrupts VICE remote monitor back to prompt.
        connector.send_command("")
    reg_text = connector.send_command("r")
    match = REGISTER_PC_RE.search(reg_text)
    return bool(match and int(match.group(1), 16) == target_pc)


def stage_dl1_fixture(connector: VICEConnector, symbols: dict[str, str]) -> tuple[int, int]:
    """Install deterministic corridor at row 10, cols 10..24 on live DL1 map.

    Returns (picked_floor_slot, inv_non_empty_before).
    """
    dlvl = read_monitor_byte(connector, sym_int(symbols, ".zp_player_dlvl"))
    if dlvl != 1:
        raise RuntimeError(f"expected player on DL1 at harness stop, got dlvl={dlvl}")

    # Clear live monsters so monster AI cannot block corridor or emit extra messages.
    mon_table = sym_int(symbols, ".monster_table")
    connector.fill_memory(mon_table, mon_table + 383, 0xFF)
    connector.poke(sym_int(symbols, ".zp_mon_count"), 0)
    connector.poke(sym_int(symbols, ".zp_msg_flags"), 0)

    # Locate a real DL1-spawned non-gold floor item (already prewarmed in $0600-$07FF).
    fi_id_base = sym_int(symbols, ".fi_item_id")
    fi_x_base = sym_int(symbols, ".fi_x")
    fi_y_base = sym_int(symbols, ".fi_y")
    fi_qty_base = sym_int(symbols, ".fi_qty")
    fi_meta_hi_base = sym_int(symbols, ".fi_meta_hi")
    inv_id_base = sym_int(symbols, ".inv_item_id")
    inv_ego_base = sym_int(symbols, ".inv_ego")

    fi_ids = read_monitor_bytes(connector, fi_id_base, fi_id_base + MAX_FLOOR_ITEMS - 1)
    fi_xs = read_monitor_bytes(connector, fi_x_base, fi_x_base + MAX_FLOOR_ITEMS - 1)
    fi_ys = read_monitor_bytes(connector, fi_y_base, fi_y_base + MAX_FLOOR_ITEMS - 1)
    fi_meta_his = read_monitor_bytes(connector, fi_meta_hi_base, fi_meta_hi_base + MAX_FLOOR_ITEMS - 1)

    target_slot: int | None = None
    for idx in range(MAX_FLOOR_ITEMS):
        item_id = fi_ids[idx]
        if item_id == FI_EMPTY:
            continue
        is_page1 = (fi_meta_his[idx] & ITEM_PAGE_BIT) != 0
        if is_page1 or item_id >= 2:
            target_slot = idx
            break

    # Move any other floor items out of our corridor box (cols 10..24, rows 9..11).
    for idx in range(MAX_FLOOR_ITEMS):
        if fi_ids[idx] == FI_EMPTY or idx == target_slot:
            continue
        if 10 <= fi_xs[idx] <= 24 and 9 <= fi_ys[idx] <= 11:
            connector.poke(fi_x_base + idx, 1)
            connector.poke(fi_y_base + idx, 1)

    # Fallback if DL1 happened to roll 0 non-gold floor items: clone carried slot 0
    # (prewarmed by Pass 3 of item_pickup_cache_prewarm).
    if target_slot is None:
        target_slot = 0
        carried_id = read_monitor_byte(connector, inv_id_base)
        carried_ego = read_monitor_byte(connector, inv_ego_base)
        if carried_id is None or carried_id == FI_EMPTY:
            raise RuntimeError("neither DL1 floor nor carried slot 0 had a non-gold item")
        connector.poke(fi_id_base + target_slot, carried_id)
        connector.poke(fi_qty_base + target_slot, 1)
        connector.poke(fi_meta_hi_base + target_slot, carried_ego or 0)

    connector.poke(fi_x_base + target_slot, 21)
    connector.poke(fi_y_base + target_slot, 10)

    # Build 1-tile horizontal corridor on row 10, bounded by walls on rows 9 & 11.
    for row in (9, 11):
        row_start = MAP_BASE + row * MAP_COLS + 10
        connector.fill_memory(row_start, row_start + 14, TILE_WALL_H | VIS_LIT)

    row10 = MAP_BASE + 10 * MAP_COLS
    connector.fill_memory(row10 + 11, row10 + 23, TILE_FLOOR | VIS_LIT)
    connector.poke(row10 + 10, TILE_WALL_H | VIS_LIT)
    connector.poke(row10 + 24, TILE_WALL_H | VIS_LIT)
    connector.poke(row10 + 16, TILE_DOOR_CLOSED | VIS_LIT)  # plain door
    connector.poke(row10 + 18, TILE_DOOR_CLOSED | VIS_LIT)  # locked door
    connector.poke(row10 + 21, TILE_FLOOR | FLAG_HAS_ITEM | VIS_LIT)

    # Door state: single locked door (val = 11) at (18, 10); (16, 10) is plain.
    connector.poke(sym_int(symbols, ".door_state_count"), 1)
    connector.poke(sym_int(symbols, ".door_state_x"), 18)
    connector.poke(sym_int(symbols, ".door_state_y"), 10)
    connector.poke(sym_int(symbols, ".door_state_val"), 11)

    # Trap table: single hidden arrow trap at (20, 10).
    connector.poke(sym_int(symbols, ".trap_count"), 1)
    connector.poke(sym_int(symbols, ".trap_x"), 20)
    connector.poke(sym_int(symbols, ".trap_y"), 10)
    connector.poke(sym_int(symbols, ".trap_type"), TRAP_ARROW)

    # Player position (11, 10), high HP (200), high Rogue disarm skill so
    # door_pick_roll succeeds deterministically on the first attempt.
    pdata = sym_int(symbols, ".player_data")
    connector.poke(sym_int(symbols, ".zp_player_x"), 11)
    connector.poke(sym_int(symbols, ".zp_player_y"), 10)
    connector.poke(pdata + PL_MAP_X, 11)
    connector.poke(pdata + PL_MAP_Y, 10)

    connector.poke(sym_int(symbols, ".zp_player_hp_lo"), 200)
    connector.poke(sym_int(symbols, ".zp_player_hp_hi"), 0)
    connector.poke(sym_int(symbols, ".zp_player_mhp_lo"), 200)
    connector.poke(sym_int(symbols, ".zp_player_mhp_hi"), 0)
    connector.poke(pdata + PL_HP_LO, 200)
    connector.poke(pdata + PL_HP_HI, 0)
    connector.poke(pdata + PL_MHP_LO, 200)
    connector.poke(pdata + PL_MHP_HI, 0)

    connector.poke(pdata + PL_CLASS, CLASS_ROGUE)
    connector.poke(pdata + PL_LEVEL, 50)
    connector.poke(sym_int(symbols, ".zp_player_lvl"), 50)
    connector.poke(pdata + PL_DEX_CUR, 118)
    connector.poke(pdata + PL_INT_CUR, 118)

    inv_ids = read_monitor_bytes(connector, inv_id_base, inv_id_base + MAX_INV_SLOTS - 1)
    inv_count_before = sum(1 for v in inv_ids if v != FI_EMPTY)
    return target_slot, inv_count_before


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", default="hot_gameplay_zero_disk_product_plus4")
    parser.add_argument("--main-vs", type=Path, required=True)
    parser.add_argument("--boot-d64", type=Path, required=True)
    parser.add_argument("--vice", required=True)
    parser.add_argument("--timeout", type=float, default=20.0)
    args = parser.parse_args()

    symbols = parse_vs_symbols(args.main_vs)
    wait_addr = sym_int(symbols, ".plus4_test_hot_res_wait_for_harness")
    cont_addr = sym_int(symbols, ".plus4_test_hot_res_continue")
    done_addr = sym_int(symbols, ".plus4_test_script_exhausted_wait")

    forbidden = {
        ".plus4_kernal_open": sym_int(symbols, ".plus4_kernal_open"),
        ".plus4_kernal_load": sym_int(symbols, ".plus4_kernal_load"),
        ".overlay_load_disk": sym_int(symbols, ".overlay_load_disk"),
        ".hal_item_cat_read_byte": sym_int(symbols, ".hal_item_cat_read_byte"),
        ".catalog_fetch_record": sym_int(symbols, ".catalog_fetch_record"),
    }

    port = allocate_free_port()
    command = [
        args.vice,
        "-config",
        vice_config(args.vice),
        "-default",
        "+saveres",
        "+autostart-delay-random",
        "-console",
        "-nativemonitor",
        "-warp",
        "+sound",
        "-sounddev",
        "dummy",
        "-remotemonitor",
        "-binarymonitor",
        "-remotemonitoraddress",
        f"127.0.0.1:{port}",
        "-drive8truedrive",
        "-drive8type",
        "1541",
        "-attach8rw",
        "-8",
        str(args.boot_d64),
        "+busdevice9",
        "-drive9type",
        "0",
        "-autostart",
        str(args.boot_d64),
    ]

    process: subprocess.Popen[bytes] | None = None
    connector = VICEConnector(port=port, timeout=5.0)
    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        connector.connect(retries=80, retry_delay=0.1)

        if not wait_for_pc(connector, wait_addr, timeout=args.timeout):
            reg = connector.send_command("r")
            print(f"FAIL: {args.name} (did not reach DL1 harness wait ${wait_addr:04X}: {reg.strip()})")
            return 1

        target_slot, inv_before = stage_dl1_fixture(connector, symbols)

        # Arm forbidden disk/overlay/catalog breakpoints + final pass breakpoint.
        connector.clear_breakpoints()
        for addr in forbidden.values():
            connector.break_at(addr)
        connector.break_at(done_addr)

        connector.set_register("pc", cont_addr)
        connector.go()
        stop = connector.wait_for_stop(pass_addr=done_addr, timeout=args.timeout)
        if not stop.passed:
            upper = stop.last_status.upper()
            hit_names = [
                label for label, addr in forbidden.items()
                if monitor_status_has_pc(upper, normalize_addr(addr))
            ]
            if hit_names:
                print(
                    f"FAIL: {args.name} (forbidden disk/overlay routine hit during hot gameplay: "
                    f"{', '.join(hit_names)}; monitor={stop.last_status.strip()})"
                )
            else:
                print(f"FAIL: {args.name} ({stop.reason}: {stop.last_status.strip()})")
            return 1

        # Verify every gameplay state transition in RAM.
        px = read_monitor_byte(connector, sym_int(symbols, ".zp_player_x"))
        py = read_monitor_byte(connector, sym_int(symbols, ".zp_player_y"))
        hp = read_monitor_byte(connector, sym_int(symbols, ".zp_player_hp_lo"))
        row10 = MAP_BASE + 10 * MAP_COLS
        plain_door_tile = read_monitor_byte(connector, row10 + 16)
        locked_door_tile = read_monitor_byte(connector, row10 + 18)
        trap_tile = read_monitor_byte(connector, row10 + 20)
        door_cnt = read_monitor_byte(connector, sym_int(symbols, ".door_state_count"))
        picked_fi_id = read_monitor_byte(connector, sym_int(symbols, ".fi_item_id") + target_slot)
        inv_id_base = sym_int(symbols, ".inv_item_id")
        inv_ids_after = read_monitor_bytes(connector, inv_id_base, inv_id_base + MAX_INV_SLOTS - 1)
        inv_after = sum(1 for v in inv_ids_after if v != FI_EMPTY)

        errors: list[str] = []
        if (px, py) != (21, 10):
            errors.append(f"player pos=({px},{py}), expected (21,10)")
        if plain_door_tile is None or (plain_door_tile & TILE_TYPE_MASK) != TILE_DOOR_OPEN:
            errors.append(f"plain door tile=${plain_door_tile or 0:02x}, expected TILE_DOOR_OPEN")
        if locked_door_tile is None or (locked_door_tile & TILE_TYPE_MASK) != TILE_DOOR_OPEN:
            errors.append(f"locked door tile=${locked_door_tile or 0:02x}, expected TILE_DOOR_OPEN")
        if door_cnt != 0:
            errors.append(f"door_state_count={door_cnt}, expected 0 after picking lock")
        if trap_tile is None or (trap_tile & TILE_TYPE_MASK) != TILE_TRAP:
            errors.append(f"trap tile=${trap_tile or 0:02x}, expected revealed TILE_TRAP")
        if hp is None or not (192 <= hp <= 199):
            errors.append(f"hp={hp}, expected 192..199 after 1d8 arrow trap from 200")
        if picked_fi_id != FI_EMPTY:
            errors.append(f"floor slot {target_slot} id=${picked_fi_id or 0:02x}, expected FI_EMPTY after pickup")
        if inv_after <= inv_before and sum(
            read_monitor_bytes(
                connector,
                sym_int(symbols, ".inv_qty"),
                sym_int(symbols, ".inv_qty") + MAX_INV_SLOTS - 1,
            )
        ) <= inv_before:
            errors.append(f"inventory did not gain picked-up item (slots {inv_before}->{inv_after})")

        if errors:
            print(f"FAIL: {args.name} ({'; '.join(errors)})")
            return 1

        print(
            f"PASS: {args.name} (0 disk/overlay/catalog hits; pos=({px},{py}), "
            f"hp=200->{hp}, doors=OPEN, inv={inv_before}->{inv_after})"
        )
        return 0
    finally:
        connector.close()
        terminate_vice(process)


if __name__ == "__main__":
    raise SystemExit(main())
