#!/usr/bin/env python3
"""Exercise production-overlay MON-044 Gain Stat potions in VICE (C64, C128, Plus/4).

Boots unmodified shipping disk images into town, seeds worn stat gear and a
Potion of Gain Strength in pack slot 0, drives 'Q' + 'A' through the real
hal_input_get_key / input_get_key_fast boundary, and asserts PL_STR_BASE,
PL_STR_CUR, zp_player_str, and player_stat_res[0] after return to main_loop.
Covers C64 TitleOverlay, Plus/4 ItemActionsOverlay, and C128 StorageOverlay ->
C128ResidentPlay (PLAYER_GAIN_STAT_HELPERS_EXTERNAL).
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from catalog_disk import consts  # noqa: E402
from item_ids import (  # noqa: E402
    FI_EMPTY,
    ITEM_PAGE_RING_OF_STRENGTH,
    ITEM_PAGE_RING_OF_WEAKNESS,
    ITEM_SLOT_POTION_OF_GAIN_STRENGTH,
    ITEM_SLOT_RING_OF_STRENGTH,
    ITEM_SLOT_RING_OF_WEAKNESS,
)
from vice_config import vice_config  # noqa: E402
from vice_connector import VICEConnector, allocate_free_port  # noqa: E402


def de_statt(val: int) -> int:
    """One negative VMS de_statt step (matching core/6502/player.s)."""
    if val >= 28:
        return val - 10
    if val >= 19:
        return 18
    return max(3, val - 1)


def run_port(args: argparse.Namespace, output: Path) -> None:
    port = args.port
    output.mkdir(parents=True, exist_ok=True)
    sym = {
        name: int(value, 16)
        for name, value in re.findall(
            r"\.label (\w+)=\$([0-9a-fA-F]+)",
            args.symbols.read_text(),
        )
    }
    pl = consts(ROOT / "core/6502/player.s")
    idefs = consts(ROOT / "core/6502/item_defs.s")
    PL_STR_BASE = pl["PL_STR_BASE"]
    PL_STR_CUR = pl["PL_STR_CUR"]
    EQUIP_WEAPON = idefs["EQUIP_WEAPON"]
    EQUIP_RING = idefs["EQUIP_RING"]
    EQUIP_CLOAK = idefs["EQUIP_CLOAK"]
    PACK_SLOTS = idefs["EQUIP_WEAPON"]

    endpoint = allocate_free_port()
    mon = VICEConnector(port=endpoint, timeout=0.2)
    deadline = time.monotonic() + 30
    command = [
        args.vice, "-config", vice_config(args.vice), "-default", "+saveres",
        "+autostart-delay-random", "-console", "-nativemonitor", "-warp",
        "+sound", "-sounddev", "dummy", "+confirmonexit",
        "-8", str(args.disk_image), "-remotemonitor",
        "-remotemonitoraddress", f"127.0.0.1:{endpoint}",
    ]
    if port == "c128":
        command += ["-80col", "-VDC16KB"]
    elif port == "c64":
        command += ["-autostartprgmode", "1"]

    with (output / "vice.log").open("wb", buffering=0) as log:
        proc = subprocess.Popen(
            command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
            env=dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy"),
        )
        timer = threading.Timer(max(0, deadline - time.monotonic()), proc.kill)
        timer.start()

        def cmd(text: str) -> str:
            with (output / "monitor.log").open("a") as trace:
                trace.write(text + "\n")
                resp = mon.send_command(text, deadline=deadline)
                trace.write(resp + "\n")
            assert not re.search(
                r"(?im)^\s*(ERROR|Unknown command|Unknown bank name|Syntax error)\b",
                resp,
            ), resp
            return resp

        def guard_for(addr: int) -> str:
            if port == "c64" and addr >= 0xE000:
                return " if (@cpu:$0001 & $02) == $00"
            if port == "c64" and 0xA000 <= addr < 0xC000:
                return " if (@cpu:$0001 & $03) != $03"
            if port == "c128" and addr >= 0xC000:
                return " if @cpu:$ff00 == $3e"
            return ""

        def until(label: str) -> None:
            addr = sym[label]
            if re.search(rf"(?im)^\s*\.;{addr:04x}\s", cmd("r")):
                return
            cmd("del")
            cmd(f"break ${addr:04x}{guard_for(addr)}")
            resp = cmd("g")
            assert re.search(rf"(?:C:|PC:|PC=)\$?{addr:04x}", resp, re.I), resp

        def read_ram(addr: int, count: int, switch_bank: bool = True) -> bytes:
            target = output / "memory.bin"
            target.unlink(missing_ok=True)
            if switch_bank:
                cmd("bank ram")
            cmd(f'bsave "{target}" 0 ${addr:04x} ${addr + count - 1:04x}')
            if switch_bank:
                cmd("bank cpu")
            data = target.read_bytes()
            assert len(data) == count
            return data

        def write_ram(addr: int, values: list[int], switch_bank: bool = True) -> None:
            if switch_bank:
                cmd("bank ram")
            cmd(f"> {addr:04x} " + " ".join(f"{b & 0xFF:02x}" for b in values))
            if switch_bank:
                cmd("bank cpu")

        def wait_key_entry() -> str:
            if port == "c128":
                labels = ("hal_input_get_key", "input_get_key_fast")
                regs = cmd("r")
                if not any(re.search(rf"(?im)^\s*\.;{sym[lbl]:04x}\s", regs) for lbl in labels):
                    cmd("del")
                    for lbl in labels:
                        cmd(f"break ${sym[lbl]:04x}")
                    cmd("g")
                    return cmd("r")
                return regs
            until("hal_input_get_key")
            return cmd("r")

        def return_key(ch: str, regs: str) -> None:
            row = next(ln for ln in regs.splitlines() if ln.strip().startswith(".;"))
            sp = int(row.split()[4], 16)
            if sp <= 0xFD:
                lo, hi = read_ram(0x100 + sp + 1, 2)
            else:
                cmd("bank ram")
                lo = read_ram(0x100 + ((sp + 1) & 0xFF), 1, switch_bank=False)[0]
                hi = read_ram(0x100 + ((sp + 2) & 0xFF), 1, switch_bank=False)[0]
                cmd("bank cpu")
            ret = (((hi << 8) | lo) + 1) & 0xFFFF
            cmd(f"r a={ord(ch):02x}")
            cmd(f"r sp={(sp + 2) & 0xFF:02x}")
            cmd(f"r pc={ret:04x}")

        def key(ch: str) -> None:
            return_key(ch, wait_key_entry())

        def quaff_slot0_and_wait_main_loop() -> None:
            key("Q")
            key("A")
            ml = sym["main_loop"]
            guard = guard_for(ml)
            key_labels = ("hal_input_get_key", "input_get_key_fast") if port == "c128" else ("hal_input_get_key",)
            for _ in range(6):
                cmd("del")
                cmd(f"break ${ml:04x}{guard}")
                for lbl in key_labels:
                    cmd(f"break ${sym[lbl]:04x}")
                resp = cmd("g")
                if re.search(rf"(?:C:|PC:|PC=)\$?{ml:04x}", resp, re.I):
                    return
                return_key(" ", cmd("r"))
            raise AssertionError(f"{port}: did not return to main_loop after quaff")

        def reset_pack_and_gear(slot_id: int, ego: int, p1: int,
                                base_str: int, cur_str: int, res_str: int = 0) -> None:
            cmd(f"f {sym['inv_item_id']:04x} {sym['inv_item_id'] + EQUIP_CLOAK:04x} {FI_EMPTY:02x}")
            for arr in ("inv_qty", "inv_ego", "inv_p1"):
                cmd(f"f {sym[arr]:04x} {sym[arr] + EQUIP_CLOAK:04x} 00")
            # Slot 0: Potion of Gain Strength
            assert PACK_SLOTS <= EQUIP_RING <= EQUIP_CLOAK and EQUIP_WEAPON == PACK_SLOTS
            cmd("bank ram")
            write_ram(sym["inv_item_id"], [ITEM_SLOT_POTION_OF_GAIN_STRENGTH], switch_bank=False)
            write_ram(sym["inv_qty"], [1], switch_bank=False)
            write_ram(sym["inv_ego"], [0], switch_bank=False)
            write_ram(sym["inv_p1"], [0], switch_bank=False)
            write_ram(sym["inv_item_id"] + EQUIP_RING, [slot_id], switch_bank=False)
            write_ram(sym["inv_qty"] + EQUIP_RING, [1], switch_bank=False)
            write_ram(sym["inv_ego"] + EQUIP_RING, [ego], switch_bank=False)
            write_ram(sym["inv_p1"] + EQUIP_RING, [p1 & 0xFF], switch_bank=False)
            write_ram(sym["player_data"] + PL_STR_BASE, [base_str], switch_bank=False)
            write_ram(sym["player_data"] + PL_STR_CUR, [cur_str], switch_bank=False)
            write_ram(sym["zp_player_str"], [cur_str], switch_bank=False)
            write_ram(sym["player_stat_res"], [res_str & 0xFF], switch_bank=False)
            cmd("bank cpu")

        def read_str_state() -> tuple[int, int, int, int, int]:
            cmd("bank ram")
            stats = read_ram(sym["player_data"] + PL_STR_BASE, PL_STR_CUR - PL_STR_BASE + 1, switch_bank=False)
            b = stats[0]
            c = stats[PL_STR_CUR - PL_STR_BASE]
            z = read_ram(sym["zp_player_str"], 1, switch_bank=False)[0]
            r = read_ram(sym["player_stat_res"], 1, switch_bank=False)[0]
            s0 = read_ram(sym["inv_item_id"], 1, switch_bank=False)[0]
            cmd("bank cpu")
            return b, c, z, r, s0

        try:
            mon.connect()
            cmd("del")
            initial = sym["title_menu_loop"] if port == "c128" else sym["entry"]
            cmd(f"break ${initial:04x}")
            program = args.program if port == "c64" and args.program is not None else args.disk_image
            cmd(f'autostart "{program}"')
            if port == "c64" and args.program is not None:
                until("entry")
                cmd("> ba 08")
            until("title_menu_loop")

            for ch in ("N", "A", "\r", "A", "G", "\r", "A", " "):
                key(ch)
            until("main_loop")

            # Case 1: +3 Ring of Strength at base 17 -> base 18, cur 38 -> 48 (+10 threshold step)
            reset_pack_and_gear(ITEM_SLOT_RING_OF_STRENGTH, ITEM_PAGE_RING_OF_STRENGTH, 3, 17, 38)
            quaff_slot0_and_wait_main_loop()
            b, c, z, r, s0 = read_str_state()
            assert (b, c, z, r, s0) == (18, 48, 48, 0, FI_EMPTY), f"{port} case1 got {(b, c, z, r, s0)}"

            # Case 2: -2 Ring of Weakness at base 18 -> healthy de_statt(de_statt(new_base))
            reset_pack_and_gear(ITEM_SLOT_RING_OF_WEAKNESS, ITEM_PAGE_RING_OF_WEAKNESS, -2, 18, 16)
            quaff_slot0_and_wait_main_loop()
            b, c, z, r, s0 = read_str_state()
            want = de_statt(de_statt(b))
            assert 19 <= b <= 43 and (c, z, r, s0) == (want, want, 0, FI_EMPTY), (
                f"{port} case2 base={b} want={want} got {(c, z, r, s0)}"
            )

            # Case 3: +17 Ring of Strength saturated cap + drained cur=90, base=100 -> full new_base-100 delta
            reset_pack_and_gear(ITEM_SLOT_RING_OF_STRENGTH, ITEM_PAGE_RING_OF_STRENGTH, 17, 100, 90)
            quaff_slot0_and_wait_main_loop()
            b, c, z, r, s0 = read_str_state()
            want = 90 + (b - 100)
            assert 101 <= b <= 110 and (c, z, r, s0) == (want, want, 0, FI_EMPTY), (
                f"{port} case3 base={b} want={want} got {(c, z, r, s0)}"
            )

            print(f"PASS {port}: production Gain Stat (+3 cross-18, -2 de_statt, +17 drained)", flush=True)
        finally:
            timer.cancel()
            mon.close()
            if proc.poll() is None:
                proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=1)
            (output / "exit.txt").write_text(f"{proc.returncode}\n")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", choices=("c64", "c128", "plus4"))
    parser.add_argument("--symbols", type=Path, required=True)
    parser.add_argument("--disk-image", type=Path, required=True)
    parser.add_argument("--program", type=Path, help="C64 product PRG to inject")
    parser.add_argument("--vice", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    if args.port == "c64" and args.program is None:
        parser.error("--program is required for c64")
    for name in ("symbols", "disk_image", "program"):
        path = getattr(args, name)
        if path is not None:
            path = path.resolve()
            if not path.is_file():
                parser.error(f"{name}: file not found: {path}")
            setattr(args, name, path)
    tool = shutil.which(args.vice)
    if tool is None:
        parser.error(f"vice: executable not found: {args.vice}")
    args.vice = str(Path(tool).resolve())
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="run-", dir=args.output))
    print(f"Evidence: {output}", flush=True)
    run_port(args, output)


if __name__ == "__main__":
    main()
