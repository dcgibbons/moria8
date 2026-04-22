#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONNECTOR_DIR = ROOT / "commodore" / "c128" / "tests"
if str(CONNECTOR_DIR) not in sys.path:
    sys.path.insert(0, str(CONNECTOR_DIR))

from vice_connector import VICEConnector, parse_vs_symbols


KEYBUF = "NA\rBA\rB L>MAALI"
MAP_BASE = 0xC000
MAP_COLS = 80
FLAG_OCCUPIED = 0x01
TILE_FLOOR = 0x00
EMPTY_SLOT = 0xFF
MONSTER_ENTRY_SIZE = 12
MAX_MONSTERS = 32
MX_X = 0
MX_Y = 1
MX_TYPE = 2
MX_HP_LO = 3
MX_HP_HI = 4
MX_FLAGS = 5
MX_SPEED_CNT = 6
MX_SLEEP_CUR = 7
MX_STUN = 8
MX_CONFUSE = 9
MX_FLEE_LO = 10
MX_FLEE_HI = 11
ZP_PLAYER_X = 0x002B
ZP_PLAYER_Y = 0x002C
ZP_MON_COUNT = 0x004D


def read_bytes(connector: VICEConnector, start: int, count: int) -> list[int]:
    response = connector.send_command(f"m {start:04x} {(start + count - 1) & 0xFFFF:04x}")
    return [int(token, 16) for token in re.findall(r"\b[0-9A-Fa-f]{2}\b", response)[:count]]


def poke_bytes(connector: VICEConnector, start: int, values: list[int]) -> None:
    for offset, value in enumerate(values):
        connector.poke(start + offset, value)


def inject_adjacent_monster(connector: VICEConnector, symbols: dict[str, str]) -> None:
    player_x = read_bytes(connector, ZP_PLAYER_X, 1)[0]
    player_y = read_bytes(connector, ZP_PLAYER_Y, 1)[0]
    target_x = (player_x + 1) & 0xFF
    target_y = player_y

    tile_addr = MAP_BASE + target_y * MAP_COLS + target_x
    connector.poke(tile_addr, TILE_FLOOR)

    monster_table = int(symbols[".monster_table"], 16)
    existing_slot = None
    free_slot = None
    for slot in range(MAX_MONSTERS):
        slot_addr = monster_table + slot * MONSTER_ENTRY_SIZE
        slot_bytes = read_bytes(connector, slot_addr, MONSTER_ENTRY_SIZE)
        slot_type = slot_bytes[MX_TYPE]
        if slot_type == EMPTY_SLOT and free_slot is None:
            free_slot = slot_addr
            continue
        if slot_type != EMPTY_SLOT and slot_bytes[MX_X] == target_x and slot_bytes[MX_Y] == target_y:
            existing_slot = slot_addr
            break

    slot_addr = existing_slot if existing_slot is not None else free_slot
    if slot_addr is None:
        raise RuntimeError("no free monster slot available for product smoke injection")

    poke_bytes(
        connector,
        slot_addr,
        [
            target_x,
            target_y,
            0,
            1,
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            0,
        ],
    )

    connector.poke(tile_addr, TILE_FLOOR | FLAG_OCCUPIED)
    if existing_slot is None:
        mon_count = read_bytes(connector, ZP_MON_COUNT, 1)[0]
        connector.poke(ZP_MON_COUNT, (mon_count + 1) & 0xFF)


def terminate(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=2.0)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2.0)


def reached_addr(response: str, addr: str) -> bool:
    return f"C:${addr.upper()}" in response.upper()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vice", default="x64sc")
    parser.add_argument("--boot-d64", default=str(ROOT / "commodore" / "out" / "moria8-c64.d64"))
    parser.add_argument("--vs", default=str(ROOT / "commodore" / "out" / "c64" / "main.vs"))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6510)
    parser.add_argument("--connect-timeout", type=float, default=12.0)
    parser.add_argument("--socket-timeout", type=float, default=2.0)
    parser.add_argument("--stage-timeout", type=float, default=45.0)
    parser.add_argument("--reu-size", default="512")
    args = parser.parse_args()

    symbols = parse_vs_symbols(args.vs)
    cast_addr = symbols[".player_cast_spell"]
    inventory_addr = symbols[".cmd_show_inventory_view"]

    command = [
        args.vice,
        "-console",
        "-warp",
        "+sound",
        "-sounddev",
        "dummy",
        "-remotemonitor",
        "-binarymonitor",
        "-reu",
        "-reusize",
        args.reu_size,
        "-autostart",
        str(Path(args.boot_d64).resolve()),
        "-autostart-delay",
        "8",
        "-keybuf",
        KEYBUF,
        "-keybuf-delay",
        "1",
        "-limitcycles",
        "900000000",
    ]

    vice = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    connector = VICEConnector(host=args.host, port=args.port, timeout=args.socket_timeout)
    try:
        connector.connect(
            retries=max(1, int(args.connect_timeout / 0.1)),
            retry_delay=0.1,
        )

        cast_status = connector.run_until(cast_addr, timeout=args.stage_timeout)
        if not reached_addr(cast_status, cast_addr):
            print("FAIL: cast stage (did not reach player_cast_spell)")
            if cast_status:
                print(cast_status.strip())
            return 2

        inject_adjacent_monster(connector, symbols)

        inventory_status = connector.run_until(inventory_addr, timeout=args.stage_timeout)
        if reached_addr(inventory_status, inventory_addr):
            print("PASS: product_magic_missile_smoke")
            return 0

        print("FAIL: inventory stage (did not reach cmd_show_inventory_view)")
        if inventory_status:
            print(inventory_status.strip())
        return 2
    finally:
        connector.close()
        terminate(vice)


if __name__ == "__main__":
    raise SystemExit(main())
