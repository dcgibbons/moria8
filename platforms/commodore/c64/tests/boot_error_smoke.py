#!/usr/bin/env python3
"""Verify C64 bootloader (boot.s) MORIA64 load-error path in headless VICE.

Tests:
  1. drive8_missing_moria64:
     Boot from a D64 on drive 8 missing MORIA64, clobber boot_device in $080E+
     at chain_entry ($0340) to simulate a partial MORIA64 overwrite, and verify
     that !err: prints "?LOAD ERROR: MORIA64 (DEV 8)", "CHECK BOOT DISK ON DRIVE 8.",
     restores VIC text mode/colors, and reaches BASIC READY. cleanly.
  2. drive9_only_missing_moria64_after_bootart:
     Boot from a D64 attached only on drive 9 containing MORIA8 + dummy
     BOOTART64 (so display_boot_art enters VIC Bank 3 multicolor bitmap mode
     and overwrites Color RAM) without MORIA64; verify chain_boot_device == 9,
     full VIC Bank 0 text/color restoration, "?LOAD ERROR: MORIA64 (DEV 9)",
     "CHECK BOOT DISK ON DRIVE 9.", and BASIC READY.
  3. drive8_empty_disk_only_in_drive9:
     Autostart boot.prg (default device 8) with an empty disk on drive 8 and a
     boot disk only on drive 9; verify "?LOAD ERROR: MORIA64 (DEV 8)",
     "CHECK BOOT DISK ON DRIVE 8.", and BASIC READY.
  4. drive8_absent_disk_only_in_drive9:
     Autostart boot.prg (default device 8) with drive 8 disabled (DEVICE NOT
     PRESENT) and a disk attached only on drive 9; verify
     "?LOAD ERROR: MORIA64 (DEV 8)", "CHECK BOOT DISK ON DRIVE 8.", and
     BASIC READY.
  5. drive10_two_digit_device:
     Boot from a D64 attached only on drive 10 missing MORIA64; verify two-digit
     decimal formatting "?LOAD ERROR: MORIA64 (DEV 10)",
     "CHECK BOOT DISK ON DRIVE 10.", and BASIC READY.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
CONNECTOR_DIR = ROOT / "platforms" / "commodore" / "c128" / "tests"
if str(CONNECTOR_DIR) not in sys.path:
    sys.path.insert(0, str(CONNECTOR_DIR))

from vice_connector import parse_vs_symbols  # noqa: E402

sys.path.insert(0, str(ROOT / "tools"))
from vice_config import vice_config  # noqa: E402

BASIC_MAIN_LOOP_ADDR = 0xA483  # BASIC immediate-mode loop after READY.
KERNAL_CUR_DEV_ADDR = 0x00BA

SCREEN_BASE = 0x0400
COLOR_BASE = 0xD800
SCREEN_ROWS = 25
SCREEN_COLS = 40
SCREEN_BYTES = SCREEN_ROWS * SCREEN_COLS

MEM_LINE_RE = re.compile(r"^>C:([0-9A-Fa-f]{4})\s+(.*)$")
STOP_HIT_RE = re.compile(r"^#\d+\s+\(Stop on\s+exec\s+([0-9A-Fa-f]{4})\)")
HEX_BYTE_RE = re.compile(r"^[0-9A-Fa-f]{2}$")


def run_tool(command: list[str], label: str, timeout: float = 30.0) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"{label} failed (rc={completed.returncode}):\n{completed.stdout[-2000:]}")
    return completed


def assemble_boot(kickass: Path, work_dir: Path) -> tuple[Path, Path]:
    resolved_dir = work_dir.resolve()
    boot_src = (ROOT / "platforms" / "commodore" / "c64" / "boot.s").resolve()
    boot_prg = (resolved_dir / "boot.prg").resolve()
    boot_vs = (resolved_dir / "boot.vs").resolve()
    run_tool(
        [
            str(ROOT / "tools" / "kickass_java.sh"),
            "-jar",
            str(kickass.resolve()),
            str(boot_src),
            "-showmem",
            "-vicesymbols",
            "-symbolfiledir",
            str(resolved_dir),
            "-o",
            str(boot_prg),
        ],
        "assemble platforms/commodore/c64/boot.s",
    )
    if not boot_prg.is_file() or not boot_vs.is_file():
        raise RuntimeError(f"assembler did not emit expected outputs in {resolved_dir}")
    return boot_prg, boot_vs


def make_d64(c1541: str, disk_path: Path, label: str, files: list[tuple[Path, str]]) -> None:
    disk_path.unlink(missing_ok=True)
    cmd = [c1541, "-format", label, "d64", str(disk_path)]
    if files:
        cmd.extend(["-attach", str(disk_path)])
        for src_path, cbm_name in files:
            cmd.extend(["-write", str(src_path), cbm_name])
    run_tool(cmd, f"c1541 build {disk_path.name}")


def decode_c64_screencode(code: int) -> str:
    code &= 0x7F
    if code == 0x00:
        return "@"
    if 0x01 <= code <= 0x1A:
        return chr(ord("A") + code - 1)
    if code == 0x1B:
        return "["
    if code == 0x1C:
        return "\\"
    if code == 0x1D:
        return "]"
    if code == 0x1E:
        return "^"
    if code == 0x1F:
        return "<"
    if 0x20 <= code <= 0x3F:
        return chr(code)
    return "?"


def parse_memory_dumps(log_text: str) -> list[tuple[int, dict[int, int]]]:
    """Split monitor log on each breakpoint hit '#N (Stop on  exec XXXX)'."""
    stops: list[tuple[int, dict[int, int]]] = []
    for raw_line in log_text.splitlines():
        stripped = raw_line.strip()
        stop_match = STOP_HIT_RE.match(stripped)
        if stop_match:
            stops.append((int(stop_match.group(1), 16), {}))
            continue
        if not stops:
            continue
        match = MEM_LINE_RE.match(stripped)
        if not match:
            continue
        addr = int(match.group(1), 16)
        mem = stops[-1][1]
        for token in match.group(2).split():
            if not HEX_BYTE_RE.match(token):
                break
            mem[addr] = int(token, 16)
            addr = (addr + 1) & 0xFFFF
    return stops


def extract_range(
    mem: dict[int, int],
    start: int,
    count: int,
    case_name: str,
    label: str,
    log_text: str = "",
) -> list[int]:
    result: list[int] = []
    for offset in range(count):
        addr = (start + offset) & 0xFFFF
        if addr not in mem:
            tail = f"\n{log_text[-2000:]}" if log_text else ""
            raise RuntimeError(f"{case_name}: missing {label} byte at ${addr:04X} in monitor log{tail}")
        result.append(mem[addr])
    return result


def build_vice_command(
    args: argparse.Namespace,
    moncommands: Path,
    monlog: Path,
    extra_args: list[str],
) -> list[str]:
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
        "+remotemonitor",
        "+binarymonitor",
        "-moncommands",
        str(moncommands),
        "-monlogname",
        str(monlog),
        "-monlog",
        "-limitcycles",
        "40000000",
    ]
    command.extend(extra_args)
    return command


def run_case(
    args: argparse.Namespace,
    run_dir: Path,
    case_name: str,
    vice_extra_args: list[str],
    symbols: dict[str, int],
    *,
    expected_dev: int,
    manual_load_dev: int | None = None,
    expect_bitmap_before_err: bool = False,
    clobber_boot_device: bool = False,
) -> None:
    chain_entry = symbols[".chain_entry"]
    chain_boot_device = symbols[".chain_boot_device"]
    boot_device = symbols[".boot_device"]

    mon_path = run_dir / f"{case_name}.mon"
    log_path = run_dir / f"{case_name}.log"
    mon_lines: list[str] = []

    if manual_load_dev is not None:
        mon_lines.extend(
            [
                f"break exec ${BASIC_MAIN_LOOP_ADDR:04x}",
                "g",
                "del",
                f'keybuf load"moria8",{manual_load_dev},1\\n',
                f"break exec ${BASIC_MAIN_LOOP_ADDR:04x}",
                "g",
                f"m {KERNAL_CUR_DEV_ADDR:04x} {KERNAL_CUR_DEV_ADDR:04x}",
                "del",
                f"break exec ${chain_entry:04x}",
                "keybuf run\\n",
                "g",
            ]
        )
    else:
        mon_lines.extend(
            [
                f"break exec ${chain_entry:04x}",
                "g",
            ]
        )

    # At chain_entry ($0340): inspect chain_boot_device and pre-error VIC state.
    mon_lines.append(f"m {chain_boot_device:04x} {chain_boot_device:04x}")
    if expect_bitmap_before_err:
        mon_lines.append("m dd00 dd00")
        mon_lines.append("m d011 d011")
    if clobber_boot_device:
        # Simulate a partial MORIA64 load overwriting $080E+ before failing.
        mon_lines.append(f"> {boot_device:04x} 00")

    # Continue until BASIC immediate-mode loop ($A483) right after READY. prints.
    mon_lines.extend(
        [
            "del",
            f"break exec ${BASIC_MAIN_LOOP_ADDR:04x}",
            "g",
            "m 0001 0001",
            "m dd00 dd00",
            "m d011 d021",
            "m 0286 0286",
            f"m {SCREEN_BASE:04x} {SCREEN_BASE + SCREEN_BYTES - 1:04x}",
            f"m {COLOR_BASE:04x} {COLOR_BASE + SCREEN_BYTES - 1:04x}",
            "quit",
        ]
    )
    mon_path.write_text("\n".join(mon_lines) + "\n", encoding="ascii")

    command = build_vice_command(args, mon_path, log_path, list(vice_extra_args))

    completed = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=args.timeout,
    )
    log_text = log_path.read_text(encoding="latin-1", errors="replace") if log_path.is_file() else ""
    upper_log = log_text.upper()
    vice_out = completed.stdout or ""

    if "JAM" in upper_log or "INVALID OPCODE" in upper_log or "JAM" in vice_out.upper():
        raise RuntimeError(f"{case_name}: CPU JAM / invalid opcode (rc={completed.returncode})\n{log_text[-2000:]}\n{vice_out[-1000:]}")
    if "CYCLE LIMIT REACHED" in upper_log or "CYCLE LIMIT REACHED" in vice_out.upper():
        raise RuntimeError(f"{case_name}: VICE cycle limit reached\n{log_text[-2000:]}\n{vice_out[-1000:]}")

    stops = parse_memory_dumps(log_text)
    expected_pcs = (
        [BASIC_MAIN_LOOP_ADDR, chain_entry, BASIC_MAIN_LOOP_ADDR]
        if manual_load_dev is not None
        else [chain_entry, BASIC_MAIN_LOOP_ADDR]
    )
    # VICE logs its own initial entry stop (e.g. $FCE2 reset or -initbreak ready)
    # before our breakpoints fire; match our breakpoints at the tail of the trace.
    tail_stops = stops[-len(expected_pcs) :] if len(stops) >= len(expected_pcs) else []
    if [pc for pc, _ in tail_stops] != expected_pcs:
        got_pcs = [f"${pc:04X}" for pc, _ in stops]
        want_pcs = [f"${pc:04X}" for pc in expected_pcs]
        extra_screen = ""
        for idx, (pc, mem) in enumerate(stops):
            if 0x0400 in mem:
                rows = [
                    "".join(decode_c64_screencode(mem.get(0x0400 + r * 40 + c, 0x20)) for c in range(40)).rstrip()
                    for r in range(8)
                ]
                extra_screen += f"\n  screen@stop[{idx}] (${pc:04X}):\n" + "\n".join(
                    f"    {r:02d}: {t}" for r, t in enumerate(rows) if t
                )
        raise RuntimeError(
            f"{case_name}: expected stop sequence {want_pcs}, saw {got_pcs} "
            f"(rc={completed.returncode}){extra_screen}\n{log_text[-1200:]}"
        )

    if manual_load_dev is not None:
        load_mem = tail_stops[0][1]
        entry_mem = tail_stops[1][1]
        final_mem = tail_stops[2][1]
        ba = extract_range(load_mem, KERNAL_CUR_DEV_ADDR, 1, case_name, "$BA", log_text)[0]
        if ba != manual_load_dev:
            raise RuntimeError(f"{case_name}: expected $BA={manual_load_dev} after LOAD, got {ba}")
    else:
        entry_mem = tail_stops[0][1]
        final_mem = tail_stops[1][1]

    got_dev = extract_range(entry_mem, chain_boot_device, 1, case_name, "chain_boot_device", log_text)[0]
    if got_dev != expected_dev:
        raise RuntimeError(
            f"{case_name}: chain_boot_device=${got_dev:02X} ({got_dev}), expected {expected_dev}"
        )

    if expect_bitmap_before_err:
        dd00_pre = extract_range(entry_mem, 0xDD00, 1, case_name, "pre $DD00", log_text)[0]
        d011_pre = extract_range(entry_mem, 0xD011, 1, case_name, "pre $D011", log_text)[0]
        if (dd00_pre & 0x03) != 0x00 or (d011_pre & 0x7F) != 0x3B:
            raise RuntimeError(
                f"{case_name}: expected bootart bitmap mode before error "
                f"($DD00=${dd00_pre:02X}, $D011=${d011_pre:02X})"
            )

    cpu_port = extract_range(final_mem, 0x0001, 1, case_name, "$01", log_text)[0]
    dd00 = extract_range(final_mem, 0xDD00, 1, case_name, "$DD00", log_text)[0]
    d011 = extract_range(final_mem, 0xD011, 1, case_name, "$D011", log_text)[0]
    d016 = extract_range(final_mem, 0xD016, 1, case_name, "$D016", log_text)[0]
    d018 = extract_range(final_mem, 0xD018, 1, case_name, "$D018", log_text)[0]
    d020 = extract_range(final_mem, 0xD020, 1, case_name, "$D020", log_text)[0] & 0x0F
    d021 = extract_range(final_mem, 0xD021, 1, case_name, "$D021", log_text)[0] & 0x0F
    cursor_col = extract_range(final_mem, 0x0286, 1, case_name, "$0286", log_text)[0] & 0x0F

    if cpu_port != 0x37:
        raise RuntimeError(f"{case_name}: expected $01=$37, got ${cpu_port:02X}")
    if (dd00 & 0x03) != 0x03:
        raise RuntimeError(f"{case_name}: VIC not restored to bank 0 ($DD00=${dd00:02X})")
    # VIC-II unused/status readback bits: $D018 bit 0=1, $D016 bits 7..6=11, $D011 bit 7=raster MSB.
    if (d018 & 0xFE) != 0x14 or (d016 & 0x3F) != 0x08 or (d011 & 0x7F) != 0x1B:
        raise RuntimeError(
            f"{case_name}: VIC text mode not restored "
            f"($D018=${d018:02X}, $D016=${d016:02X}, $D011=${d011:02X})"
        )
    if d020 != 0x0E or d021 != 0x06 or cursor_col != 0x0E:
        raise RuntimeError(
            f"{case_name}: colors not restored "
            f"($D020=${d020:02X}, $D021=${d021:02X}, $0286=${cursor_col:02X})"
        )

    screen_raw = extract_range(final_mem, SCREEN_BASE, SCREEN_BYTES, case_name, "screen RAM")
    color_raw = extract_range(final_mem, COLOR_BASE, SCREEN_BYTES, case_name, "color RAM")
    lines = [
        "".join(
            decode_c64_screencode(b)
            for b in screen_raw[row * SCREEN_COLS : (row + 1) * SCREEN_COLS]
        ).rstrip()
        for row in range(SCREEN_ROWS)
    ]

    expected_line1 = f"?LOAD ERROR: MORIA64 (DEV {expected_dev})"
    expected_line2 = f"CHECK BOOT DISK ON DRIVE {expected_dev}."
    idx1 = next((i for i, line in enumerate(lines) if expected_line1 in line), None)
    idx2 = next((i for i, line in enumerate(lines) if expected_line2 in line), None)
    idx_ready = next((i for i, line in enumerate(lines) if line.strip() == "READY."), None)

    if idx1 is None or idx2 is None or idx_ready is None or not (idx1 < idx2 < idx_ready):
        rendered = "\n".join(f"  {row:02d}: {text}" for row, text in enumerate(lines) if text)
        raise RuntimeError(
            f"{case_name}: screen text mismatch\n"
            f"  expected: {expected_line1!r} -> {expected_line2!r} -> 'READY.'\n"
            f"  screen:\n{rendered}"
        )

    color_row1 = [b & 0x0F for b in color_raw[idx1 * SCREEN_COLS : idx1 * SCREEN_COLS + len(expected_line1)]]
    color_row2 = [b & 0x0F for b in color_raw[idx2 * SCREEN_COLS : idx2 * SCREEN_COLS + len(expected_line2)]]
    if any(c != 0x0E for c in color_row1) or any(c != 0x0E for c in color_row2):
        raise RuntimeError(
            f"{case_name}: error text color RAM not restored to $0E "
            f"(row1={color_row1[:8]}..., row2={color_row2[:8]}...)"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="C64 bootloader MORIA64 error-path VICE smoke test")
    parser.add_argument("--vice", default="x64sc")
    parser.add_argument("--c1541", default="c1541")
    parser.add_argument("--kickass", type=Path, default=ROOT / "tools" / "kickass" / "KickAss.jar")
    parser.add_argument("--boot-prg", type=Path, help="Optional prebuilt boot.prg (requires --boot-vs)")
    parser.add_argument("--boot-vs", type=Path, help="Optional VICE symbol file for --boot-prg")
    parser.add_argument("--work-dir", type=Path, default=ROOT / "build" / "test" / "c64" / "boot_err_work")
    parser.add_argument("--timeout", type=float, default=25.0)
    args = parser.parse_args()

    run_dir = (args.work_dir.resolve() / f"run-{os.getpid()}").resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    try:
        if args.boot_prg is not None:
            boot_prg = args.boot_prg.resolve()
            boot_vs = (args.boot_vs or boot_prg.with_suffix(".vs")).resolve()
        else:
            boot_prg, boot_vs = assemble_boot(args.kickass.resolve(), run_dir)

        raw_syms = parse_vs_symbols(boot_vs)
        required_syms = (
            ".chain_entry",
            ".chain_boot_device",
            ".chain_err_msg",
            ".chain_stub",
            ".chain_stub_end",
            ".boot_device",
        )
        symbols: dict[str, int] = {}
        for name in required_syms:
            if name not in raw_syms:
                raise RuntimeError(f"missing required symbol {name} in {boot_vs}")
            symbols[name] = int(raw_syms[name], 16)

        stub_size = symbols[".chain_stub_end"] - symbols[".chain_stub"]
        if symbols[".chain_entry"] != 0x0340:
            raise RuntimeError(f"chain_entry=${symbols['.chain_entry']:04X}, expected $0340")
        if not (0 < stub_size <= 0xC0):
            raise RuntimeError(f"chain_stub size {stub_size} B exceeds 192 B ($C0) cassette buffer")
        for sym_name in (".chain_boot_device", ".chain_err_msg"):
            addr = symbols[sym_name]
            if not (0x0340 <= addr < 0x0400):
                raise RuntimeError(f"{sym_name}=${addr:04X} lies outside $0340-$03FF")

        # Dummy BOOTART64 PRG loading at $A000 (triggers display_boot_art -> VIC Bank 3).
        dummy_art = run_dir / "bootart64.prg"
        dummy_art.write_bytes(b"\x00\xa0" + bytes(16))

        empty8_d64 = run_dir / "empty8.d64"
        boot8_d64 = run_dir / "boot8.d64"
        boot9_art_d64 = run_dir / "boot9_art.d64"
        boot10_d64 = run_dir / "boot10.d64"

        make_d64(args.c1541, empty8_d64, "empty8,m8", [])
        make_d64(args.c1541, boot8_d64, "boot8,m8", [(boot_prg, "moria8")])
        make_d64(
            args.c1541,
            boot9_art_d64,
            "boot9,m8",
            [(boot_prg, "moria8"), (dummy_art, "bootart64")],
        )
        make_d64(args.c1541, boot10_d64, "boot10,m8", [(boot_prg, "moria8")])

        # Case 1: Disk on drive 8 missing MORIA64, with simulated $080E+ clobber.
        run_case(
            args,
            run_dir,
            "drive8_missing_moria64",
            [
                "-drive8truedrive",
                "-drive8type",
                "1541",
                "+busdevice9",
                "-drive9type",
                "0",
                "-8",
                str(boot8_d64),
                "-autostart",
                str(boot8_d64),
            ],
            symbols,
            expected_dev=8,
            clobber_boot_device=True,
        )

        # Case 2: Disk attached only on drive 9 (with BOOTART64, missing MORIA64).
        run_case(
            args,
            run_dir,
            "drive9_only_missing_moria64_after_bootart",
            [
                "+busdevice8",
                "-drive8type",
                "0",
                "-drive9truedrive",
                "-drive9type",
                "1541",
                "-9",
                str(boot9_art_d64),
            ],
            symbols,
            expected_dev=9,
            manual_load_dev=9,
            expect_bitmap_before_err=True,
            clobber_boot_device=True,
        )

        # Case 3: Autostart boot.prg (default dev 8) with empty drive 8 and disk only in drive 9.
        run_case(
            args,
            run_dir,
            "drive8_empty_disk_only_in_drive9",
            [
                "-drive8truedrive",
                "-drive8type",
                "1541",
                "-8",
                str(empty8_d64),
                "-drive9truedrive",
                "-drive9type",
                "1541",
                "-busdevice9",
                "-9",
                str(boot9_art_d64),
                "-autostartprgmode",
                "1",
                "-autostart",
                str(boot_prg),
            ],
            symbols,
            expected_dev=8,
        )

        # Case 4: Autostart boot.prg (default dev 8) with drive 8 absent and disk only in drive 9.
        run_case(
            args,
            run_dir,
            "drive8_absent_disk_only_in_drive9",
            [
                "+busdevice8",
                "-drive8type",
                "0",
                "-drive9truedrive",
                "-drive9type",
                "1541",
                "-9",
                str(boot9_art_d64),
                "-autostartprgmode",
                "1",
                "-autostart",
                str(boot_prg),
            ],
            symbols,
            expected_dev=8,
        )

        # Case 5: Two-digit device number (drive 10) missing MORIA64.
        run_case(
            args,
            run_dir,
            "drive10_two_digit_device",
            [
                "+busdevice8",
                "-drive8type",
                "0",
                "+busdevice9",
                "-drive9type",
                "0",
                "-drive10truedrive",
                "-drive10type",
                "1541",
                "-10",
                str(boot10_d64),
            ],
            symbols,
            expected_dev=10,
            manual_load_dev=10,
        )

        print(f"PASS: boot_error_smoke (5/5 cases, chain_stub={stub_size}/192 B)")
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL: {exc}")
        return 2
    finally:
        shutil.rmtree(run_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
