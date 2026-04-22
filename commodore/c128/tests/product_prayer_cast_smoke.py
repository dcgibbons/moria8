#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from vice_connector import VICEConnector, parse_vs_symbols


MSG_HIST_COUNT = 8
MSG_HIST_LEN = 80
MSG_HIST_BYTES = MSG_HIST_COUNT * MSG_HIST_LEN

PL_CLASS = 18
PL_LEVEL = 19
PL_WIS_BASE = 23
PL_WIS_CUR = 29
PL_HP_LO = 33
PL_MHP_LO = 35
PL_MANA = 37
PL_MAX_MANA = 38
PL_SPELL_TYPE = 60
PL_SPELLS_LEARNT_0 = 61
PL_SPELLS_WORKED_0 = 65
PL_SPELLS_FORGOTTEN_0 = 69
PL_NEW_SPELLS = 73
PL_SPELL_ORDER = 74

CLASS_PRIEST = 2
SPELL_PRIEST = 2
FI_EMPTY = 0xFF
PRIEST_BOOK_ITEM_ID = 48

MEM_LINE_RE = re.compile(r"^[^:]+:([0-9A-Fa-f]{4})\s+((?:[0-9A-Fa-f]{2}\s+)+)")


def parse_required_symbols(vs_path: Path, names: dict[str, str]) -> dict[str, int]:
    symbols = parse_vs_symbols(vs_path)
    resolved: dict[str, int] = {}
    for key, name in names.items():
        raw = symbols.get(name)
        if not raw:
            raise ValueError(f"missing {name} in {vs_path}")
        resolved[key] = int(raw, 16)
    return resolved


def run_direct_effect_probe(
    *,
    vice: str,
    snapshot_path: Path,
    connect_timeout: float,
    socket_timeout: float,
    tramp_spell_execute_selected: int,
    pm_spell_type: int,
    pm_spell_idx: int,
    player_data: int,
    msg_history: int,
    zp_player_hp_lo: int,
    zp_player_mhp_lo: int,
    zp_eff_bless: int,
    prayer: str,
) -> str:
    process = subprocess.Popen(
        build_vice_command(
            vice=vice,
        ),
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    connector = VICEConnector(timeout=socket_timeout)
    stub_addr = 0x1A00
    stop_addr = stub_addr + 3
    try:
        connector.connect(
            retries=max(1, int(connect_timeout / 0.1)),
            retry_delay=0.1,
        )
        connector.send_command(
            f'undump "{snapshot_path.resolve()}"',
            expect_prompt=False,
        )
        time.sleep(0.2)
        connector.close()
        connector.connect(
            retries=max(1, int(connect_timeout / 0.1)),
            retry_delay=0.1,
        )

        connector.fill_memory(msg_history, msg_history + MSG_HIST_BYTES - 1, 0x20)
        connector.poke(pm_spell_type, SPELL_PRIEST)

        if prayer == "bless":
            connector.poke(pm_spell_idx, 0x02)
            connector.poke(zp_eff_bless, 0x00)
        elif prayer == "cure_light_wounds":
            connector.poke(pm_spell_idx, 0x01)
            write_bytes(connector, player_data + PL_HP_LO, [0x06, 0x00])
            write_bytes(connector, player_data + PL_MHP_LO, [0x09, 0x00])
            write_bytes(connector, zp_player_hp_lo, [0x06, 0x00])
            write_bytes(connector, zp_player_mhp_lo, [0x09, 0x00])
        else:
            return f"FAIL: unsupported direct prayer probe {prayer}"

        write_bytes(
            connector,
            stub_addr,
            [
                0x20,
                tramp_spell_execute_selected & 0xFF,
                (tramp_spell_execute_selected >> 8) & 0xFF,
                0x00,
            ],
        )

        connector.clear_breakpoints()
        connector.break_at(stop_addr)
        connector.go(stub_addr)
        result = connector.wait_for_stop(pass_addr=stop_addr, timeout=12.0)
        if not result.passed:
            return f"FAIL: direct priest effect probe stopped early: {result.reason}"

        if prayer == "bless":
            bless_timer = extract_dump(
                connector.send_command(f"m {zp_eff_bless:04X} {zp_eff_bless:04X}"),
                zp_eff_bless,
                1,
            )
            if not bless_timer or bless_timer[0] == 0:
                return "FAIL: direct priest bless probe left zp_eff_bless at zero"
            return "PASS: direct priest bless probe set zp_eff_bless"

        hp_now = extract_dump(
            connector.send_command(f"m {zp_player_hp_lo:04X} {zp_player_hp_lo + 1:04X}"),
            zp_player_hp_lo,
            2,
        )
        if len(hp_now) < 2:
            return "FAIL: direct priest cure probe could not read zp_player_hp_lo"
        if hp_now[0] <= 0x06 and hp_now[1] == 0x00:
            return "FAIL: direct priest cure probe did not increase HP"
        return "PASS: direct priest cure probe increased HP"
    finally:
        connector.close()
        terminate_vice(process)


def extract_dump(log_text: str, start_addr: int, length: int) -> list[int]:
    lines = log_text.splitlines()
    wanted = f"{start_addr & 0xFFFF:04X}"
    for idx in range(len(lines) - 1, -1, -1):
        match = MEM_LINE_RE.match(lines[idx].strip())
        if not match or match.group(1).upper() != wanted:
            continue
        data: list[int] = []
        expected = start_addr & 0xFFFF
        cursor = idx
        while cursor < len(lines) and len(data) < length:
            current = MEM_LINE_RE.match(lines[cursor].strip())
            if not current:
                break
            addr = int(current.group(1), 16)
            if addr != expected:
                break
            hex_bytes = current.group(2).split()
            data.extend(int(value, 16) for value in hex_bytes)
            expected = (expected + len(hex_bytes)) & 0xFFFF
            cursor += 1
        return data[:length]
    return []


def history_contains(log_text: str, msg_history: int, needle: bytes) -> bool:
    haystack = bytes(extract_dump(log_text, msg_history, MSG_HIST_BYTES))
    return needle in haystack


def terminate_vice(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=2.0)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2.0)


def write_bytes(connector: VICEConnector, start_addr: int, values: list[int]) -> None:
    payload = " ".join(f"{value & 0xFF:02X}" for value in values)
    connector.send_command(f"> {start_addr & 0xFFFF:04X} {payload}")


def build_priest_patch_commands(
    *,
    player_data: int,
    inv_item_id: int,
    inv_qty: int,
    inv_p1: int,
    inv_flags: int,
    msg_history: int,
    zp_player_lvl: int,
    zp_player_wis: int,
    zp_player_hp_lo: int,
    zp_player_mhp_lo: int,
    zp_player_mp: int,
    zp_player_mmp: int,
    zp_eff_bless: int,
    zp_msg_flags: int,
    snapshot_path: Path,
) -> list[str]:
    commands = [
        f"f {msg_history:04X} {msg_history + MSG_HIST_BYTES - 1:04X} 20",
        f"> {zp_msg_flags:04X} 00",
        f"> {zp_eff_bless:04X} 00",
        f"> {player_data + PL_CLASS:04X} {CLASS_PRIEST:02X}",
        f"> {player_data + PL_LEVEL:04X} 32",
        f"> {player_data + PL_WIS_BASE:04X} 12",
        f"> {player_data + PL_WIS_CUR:04X} 12",
        f"> {player_data + PL_SPELL_TYPE:04X} {SPELL_PRIEST:02X}",
        f"> {player_data + PL_HP_LO:04X} 09 00",
        f"> {player_data + PL_MHP_LO:04X} 09 00",
        f"> {player_data + PL_MANA:04X} 14",
        f"> {player_data + PL_MAX_MANA:04X} 14",
        f"> {player_data + PL_SPELLS_LEARNT_0:04X} 07 00 00 00",
        f"> {player_data + PL_SPELLS_WORKED_0:04X} 00 00 00 00",
        f"> {player_data + PL_SPELLS_FORGOTTEN_0:04X} 00 00 00 00",
        f"> {player_data + PL_NEW_SPELLS:04X} 00",
        f"f {player_data + PL_SPELL_ORDER:04X} {player_data + PL_SPELL_ORDER + 31:04X} 63",
        f"> {player_data + PL_SPELL_ORDER:04X} 00 01 02",
        f"> {zp_player_lvl:04X} 32",
        f"> {zp_player_wis:04X} 12",
        f"> {zp_player_hp_lo:04X} 09 00",
        f"> {zp_player_mhp_lo:04X} 09 00",
        f"> {zp_player_mp:04X} 14",
        f"> {zp_player_mmp:04X} 14",
        f"> {inv_item_id + 0:04X} {FI_EMPTY:02X}",
        f"> {inv_qty + 0:04X} 00",
        f"> {inv_p1 + 0:04X} 00",
        f"> {inv_flags + 0:04X} 00",
        f"> {inv_item_id + 1:04X} {PRIEST_BOOK_ITEM_ID:02X}",
        f"> {inv_qty + 1:04X} 01",
        f"> {inv_p1 + 1:04X} 00",
        f"> {inv_flags + 1:04X} 00",
        f'dump "{snapshot_path.resolve()}"',
        "quit",
    ]
    return commands


def patch_priest_runtime_state(
    connector: VICEConnector,
    *,
    player_data: int,
    inv_item_id: int,
    inv_qty: int,
    inv_p1: int,
    inv_flags: int,
    msg_history: int,
    zp_player_lvl: int,
    zp_player_wis: int,
    zp_player_hp_lo: int,
    zp_player_mhp_lo: int,
    zp_player_mp: int,
    zp_player_mmp: int,
    zp_eff_bless: int,
    zp_msg_flags: int,
) -> None:
    connector.fill_memory(msg_history, msg_history + MSG_HIST_BYTES - 1, 0x20)
    connector.poke(zp_msg_flags, 0x00)
    connector.poke(zp_eff_bless, 0x00)
    connector.poke(player_data + PL_CLASS, CLASS_PRIEST)
    connector.poke(player_data + PL_LEVEL, 0x32)
    connector.poke(player_data + PL_WIS_BASE, 0x12)
    connector.poke(player_data + PL_WIS_CUR, 0x12)
    connector.poke(player_data + PL_SPELL_TYPE, SPELL_PRIEST)
    write_bytes(connector, player_data + PL_HP_LO, [0x09, 0x00])
    write_bytes(connector, player_data + PL_MHP_LO, [0x09, 0x00])
    connector.poke(player_data + PL_MANA, 0x14)
    connector.poke(player_data + PL_MAX_MANA, 0x14)
    write_bytes(connector, player_data + PL_SPELLS_LEARNT_0, [0x07, 0x00, 0x00, 0x00])
    write_bytes(connector, player_data + PL_SPELLS_WORKED_0, [0x00, 0x00, 0x00, 0x00])
    write_bytes(connector, player_data + PL_SPELLS_FORGOTTEN_0, [0x00, 0x00, 0x00, 0x00])
    connector.poke(player_data + PL_NEW_SPELLS, 0x00)
    connector.fill_memory(player_data + PL_SPELL_ORDER, player_data + PL_SPELL_ORDER + 31, 0x63)
    write_bytes(connector, player_data + PL_SPELL_ORDER, [0x00, 0x01, 0x02])
    connector.poke(zp_player_lvl, 0x32)
    connector.poke(zp_player_wis, 0x12)
    write_bytes(connector, zp_player_hp_lo, [0x09, 0x00])
    write_bytes(connector, zp_player_mhp_lo, [0x09, 0x00])
    connector.poke(zp_player_mp, 0x14)
    connector.poke(zp_player_mmp, 0x14)
    connector.poke(inv_item_id + 0, FI_EMPTY)
    connector.poke(inv_qty + 0, 0x00)
    connector.poke(inv_p1 + 0, 0x00)
    connector.poke(inv_flags + 0, 0x00)
    connector.poke(inv_item_id + 1, PRIEST_BOOK_ITEM_ID)
    connector.poke(inv_qty + 1, 0x01)
    connector.poke(inv_p1 + 1, 0x00)
    connector.poke(inv_flags + 1, 0x00)


def build_vice_command(
    *,
    vice: str,
    boot_d64: Path | None = None,
    keybuf: str | None = None,
    keybuf_delay: int = 8,
) -> list[str]:
    command = [
        vice,
        "-console",
        "-nativemonitor",
        "-warp",
        "-80col",
        "+sound",
        "-sounddev",
        "dummy",
        "-remotemonitor",
        "-binarymonitor",
    ]
    if boot_d64 is not None:
        command.extend(["-autostart", str(boot_d64)])
    if keybuf is not None:
        command.extend(["-keybuf", keybuf, "-keybuf-delay", str(keybuf_delay)])
    return command


def write_stage1_moncommands(mon_path: Path, *, main_loop: int) -> None:
    mon_path.write_text(f"until ${main_loop:04X}\n", encoding="ascii")


def run_to_stage(
    connector: VICEConnector,
    *,
    addr: int,
    timeout: float,
    description: str,
) -> tuple[bool, str]:
    connector.clear_breakpoints()
    connector.break_at(addr)
    connector.go()
    result = connector.wait_for_stop(pass_addr=addr, timeout=timeout)
    if result.passed:
        return True, result.last_status
    if result.reason == "CPU JAM":
        return False, f"{description}: CPU JAM"
    return False, f"{description}: {result.reason}"


def run_snapshot_probe(
    *,
    vice: str,
    snapshot_path: Path,
    keybuf: str,
    connect_timeout: float,
    socket_timeout: float,
    stage_addr: int,
    stage_timeout: float,
    description: str,
    dump_addrs: list[tuple[int, int]] | None = None,
) -> tuple[bool, str, list[str]]:
    process = subprocess.Popen(
        build_vice_command(
            vice=vice,
            keybuf=keybuf,
        ),
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    connector = VICEConnector(timeout=socket_timeout)
    try:
        connector.connect(
            retries=max(1, int(connect_timeout / 0.1)),
            retry_delay=0.1,
        )
        connector.send_command(
            f'undump "{snapshot_path.resolve()}"',
            expect_prompt=False,
        )
        time.sleep(0.2)
        connector.close()
        connector.connect(
            retries=max(1, int(connect_timeout / 0.1)),
            retry_delay=0.1,
        )
        ok, detail = run_to_stage(
            connector,
            addr=stage_addr,
            timeout=stage_timeout,
            description=description,
        )
        if not ok:
            return False, detail, []
        dumps: list[str] = []
        for start_addr, end_addr in dump_addrs or []:
            dumps.append(connector.send_command(f"m {start_addr:04X} {end_addr:04X}"))
        return True, "", dumps
    finally:
        connector.close()
        terminate_vice(process)


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify the shipping C128 prayer flow on the product image")
    parser.add_argument("--vice", required=True)
    parser.add_argument("--boot-d64", type=Path)
    parser.add_argument("--snapshot", type=Path)
    parser.add_argument("--vs", default=Path("commodore/out/c128/main.vs"), type=Path)
    parser.add_argument("--prayer", choices=("bless", "cure_light_wounds"), default="bless")
    parser.add_argument("--direct-exec", action="store_true")
    parser.add_argument("--keybuf", default="PAC")
    parser.add_argument("--connect-timeout", type=float, default=12.0)
    parser.add_argument("--socket-timeout", type=float, default=1.0)
    parser.add_argument("--boot-timeout", type=float, default=40.0)
    parser.add_argument("--stage-timeout", type=float, default=12.0)
    args = parser.parse_args()

    if (args.boot_d64 is None) == (args.snapshot is None):
        print("FAIL: provide exactly one of --boot-d64 or --snapshot")
        return 2
    if args.boot_d64 is not None and not args.boot_d64.exists():
        print(f"FAIL: missing boot image {args.boot_d64}")
        return 2
    if args.snapshot is not None and not args.snapshot.exists():
        print(f"FAIL: missing snapshot {args.snapshot}")
        return 2
    if not args.vs.exists():
        print(f"FAIL: missing symbol file {args.vs}")
        return 2

    try:
        resolved = parse_required_symbols(
            args.vs,
            {
                "title_menu_ready": ".title_menu_ready",
                "main_loop": ".main_loop",
                "tramp_player_pray": ".tramp_player_pray",
                "player_pray": ".player_pray",
                "prompt_choice": ".pm_prompt_visible_spell_choice",
                "validate_selected": ".pm_validate_selected_spell",
                "tramp_spell_execute_selected": ".tramp_spell_execute_selected",
                "spell_execute_selected": ".spell_execute_selected",
                "pm_spell_idx": ".pm_spell_idx",
                "pm_spell_type": ".pm_spell_type",
                "player_data": ".player_data",
                "inv_item_id": ".inv_item_id",
                "inv_qty": ".inv_qty",
                "inv_p1": ".inv_p1",
                "inv_flags": ".inv_flags",
                "msg_history": ".msg_history",
                "zp_player_lvl": ".zp_player_lvl",
                "zp_player_wis": ".zp_player_wis",
                "zp_player_hp_lo": ".zp_player_hp_lo",
                "zp_player_mhp_lo": ".zp_player_mhp_lo",
                "zp_player_mp": ".zp_player_mp",
                "zp_player_mmp": ".zp_player_mmp",
                "zp_eff_bless": ".zp_eff_bless",
                "zp_msg_flags": ".zp_msg_flags",
                "bless_msg": ".pmx_msg_bless_on",
            },
        )
    except ValueError as exc:
        print(f"FAIL: {exc}")
        return 2

    if args.direct_exec:
        result = run_direct_effect_probe(
            vice=args.vice,
            snapshot_path=args.snapshot,
            connect_timeout=args.connect_timeout,
            socket_timeout=args.socket_timeout,
            tramp_spell_execute_selected=resolved["tramp_spell_execute_selected"],
            pm_spell_type=resolved["pm_spell_type"],
            pm_spell_idx=resolved["pm_spell_idx"],
            player_data=resolved["player_data"],
            msg_history=resolved["msg_history"],
            zp_player_hp_lo=resolved["zp_player_hp_lo"],
            zp_player_mhp_lo=resolved["zp_player_mhp_lo"],
            zp_eff_bless=resolved["zp_eff_bless"],
            prayer=args.prayer,
        )
        print(result)
        return 0 if result.startswith("PASS:") else 2

    if args.snapshot is not None:
        snapshot_path = args.snapshot
    else:
        with tempfile.TemporaryDirectory(prefix="c128_prayer_smoke_") as temp_dir:
            snapshot_path = Path(temp_dir) / "priest_ready.vsf"
            stage1_mon_path = Path(temp_dir) / "stage1.mon"
            write_stage1_moncommands(
                stage1_mon_path,
                main_loop=resolved["main_loop"],
            )
            stage1_process = subprocess.Popen(
                build_vice_command(
                    vice=args.vice,
                    boot_d64=args.boot_d64,
                    keybuf="NAA\rA\rA",
                )
                + [
                    "-moncommands",
                    str(stage1_mon_path),
                ],
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            patch_commands = build_priest_patch_commands(
                player_data=resolved["player_data"],
                inv_item_id=resolved["inv_item_id"],
                inv_qty=resolved["inv_qty"],
                inv_p1=resolved["inv_p1"],
                inv_flags=resolved["inv_flags"],
                msg_history=resolved["msg_history"],
                zp_player_lvl=resolved["zp_player_lvl"],
                zp_player_wis=resolved["zp_player_wis"],
                zp_player_hp_lo=resolved["zp_player_hp_lo"],
                zp_player_mhp_lo=resolved["zp_player_mhp_lo"],
                zp_player_mp=resolved["zp_player_mp"],
                zp_player_mmp=resolved["zp_player_mmp"],
                zp_eff_bless=resolved["zp_eff_bless"],
                zp_msg_flags=resolved["zp_msg_flags"],
                snapshot_path=snapshot_path,
            )
            if stage1_process.stdin is None:
                print("FAIL: stage1 monitor stdin unavailable for snapshot handoff")
                return 2
            stage1_process.stdin.write(("\n".join(patch_commands) + "\n").encode("ascii"))
            stage1_process.stdin.flush()
            try:
                stage1_process.wait(timeout=args.boot_timeout)
            except subprocess.TimeoutExpired:
                terminate_vice(stage1_process)
                print("FAIL: newgame flow did not reach gameplay")
                return 2
            finally:
                terminate_vice(stage1_process)
            if stage1_process.returncode not in (0, None):
                print("FAIL: stage1 prayer repro exited unexpectedly before snapshot handoff")
                return 2
            if not snapshot_path.exists() or snapshot_path.stat().st_size <= 0:
                print("FAIL: stage1 did not produce a gameplay snapshot for prayer repro")
                return 2

            result = run_from_snapshot(args, resolved, snapshot_path)
            print(result)
            return 0 if result.startswith("PASS:") else 2

    result = run_from_snapshot(args, resolved, snapshot_path)
    print(result)
    return 0 if result.startswith("PASS:") else 2


def run_from_snapshot(args: argparse.Namespace, resolved: dict[str, int], snapshot_path: Path) -> str:
    for addr, message in [
        (resolved["tramp_player_pray"], "prayer command did not reach tramp_player_pray"),
        (resolved["player_pray"], "prayer command did not reach player_pray"),
        (resolved["prompt_choice"], "book choice did not reach prayer prompt"),
        (resolved["validate_selected"], "prayer letter did not reach pm_validate_selected_spell"),
        (resolved["tramp_spell_execute_selected"], "prayer path did not reach tramp_spell_execute_selected"),
        (resolved["spell_execute_selected"], "prayer path did not reach spell_execute_selected"),
    ]:
        ok, detail, _ = run_snapshot_probe(
            vice=args.vice,
            snapshot_path=snapshot_path,
            keybuf=args.keybuf,
            connect_timeout=args.connect_timeout,
            socket_timeout=args.socket_timeout,
            stage_addr=addr,
            stage_timeout=args.stage_timeout,
            description=message,
        )
        if not ok:
            return f"FAIL: {detail}"

    ok, detail, dumps = run_snapshot_probe(
        vice=args.vice,
        snapshot_path=snapshot_path,
        keybuf=args.keybuf,
        connect_timeout=args.connect_timeout,
        socket_timeout=args.socket_timeout,
        stage_addr=resolved["main_loop"],
        stage_timeout=args.stage_timeout,
        description="prayer path never returned to gameplay after spell_execute_selected",
        dump_addrs=[
            (resolved["zp_eff_bless"], resolved["zp_eff_bless"]),
            (resolved["msg_history"], resolved["msg_history"] + MSG_HIST_BYTES - 1),
            (resolved["bless_msg"], resolved["bless_msg"] + len("You feel righteous!")),
        ],
    )
    if not ok:
        return f"FAIL: {detail}"
    bless_timer_dump, msg_history_dump, bless_msg_dump_text = dumps

    if args.prayer == "bless":
        bless_timer = extract_dump(bless_timer_dump, resolved["zp_eff_bless"], 1)
        if not bless_timer or bless_timer[0] == 0:
            return "FAIL: bless prayer reached spell_execute_selected but zp_eff_bless is still zero"
        bless_msg_dump = bytes(extract_dump(bless_msg_dump_text, resolved["bless_msg"], len("You feel righteous!") + 1))
        bless_msg = bless_msg_dump.split(b"\x00", 1)[0]
        if not bless_msg or not history_contains(msg_history_dump, resolved["msg_history"], bless_msg):
            return "FAIL: bless prayer ran but the bless message was not recorded in msg_history"
    return "PASS: shipping C128 bless prayer reached live execution, set bless, and recorded the bless message"

if __name__ == "__main__":
    sys.exit(main())
