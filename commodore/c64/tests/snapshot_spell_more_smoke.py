#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONNECTOR_DIR = ROOT / "commodore" / "c128" / "tests"
if str(CONNECTOR_DIR) not in sys.path:
    sys.path.insert(0, str(CONNECTOR_DIR))

from vice_connector import VICEConnector, normalize_addr, parse_vs_symbols


def terminate(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=2.0)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2.0)


def stopped_at(status: str, addr: str) -> bool:
    return f"C:${addr}" in status.upper()


def run_to_break_or_fail(
    connector: VICEConnector,
    *,
    addr: str,
    timeout: float,
    basic_addr: str,
    exit_addr: str,
    description: str,
) -> tuple[bool, str]:
    try:
        connector.clear_breakpoints()
        connector.break_at(basic_addr)
        connector.break_at(exit_addr)
        connector.break_at(addr)
        connector.go()
        status = connector.read_until_prompt(deadline=time.monotonic() + timeout)
    except TimeoutError:
        try:
            connector.send_command("stop")
            status = connector.read_until_prompt(deadline=time.monotonic() + 2.0)
            regs = connector.send_command("r")
            return False, f"{description}: timeout waiting for ${addr}\n{status}\n{regs}"
        except Exception:
            return False, f"{description}: timeout waiting for ${addr}"

    upper = status.upper()
    if stopped_at(upper, addr):
        return True, status
    if stopped_at(upper, basic_addr):
        return False, f"{description}: reached BASIC warm start at ${basic_addr}"
    if stopped_at(upper, exit_addr):
        return False, f"{description}: reached exit_trampoline at ${exit_addr}"
    if "JAM" in upper or "INVALID OPCODE" in upper:
        return False, f"{description}: CPU JAM"
    return False, f"{description}: stopped unexpectedly\n{status}"


def run_to_break_or_jam(
    connector: VICEConnector,
    *,
    addr: str,
    timeout: float,
    description: str,
) -> tuple[bool, str]:
    try:
        connector.clear_breakpoints()
        connector.break_at(addr)
        connector.go()
        status = connector.read_until_prompt(deadline=time.monotonic() + timeout)
    except TimeoutError:
        try:
            connector.send_command("stop")
            status = connector.read_until_prompt(deadline=time.monotonic() + 2.0)
            regs = connector.send_command("r")
            return False, f"{description}: timeout waiting for ${addr}\n{status}\n{regs}"
        except Exception:
            return False, f"{description}: timeout waiting for ${addr}"

    upper = status.upper()
    if stopped_at(upper, addr):
        return True, status
    if "JAM" in upper or "INVALID OPCODE" in upper:
        return False, f"{description}: CPU JAM"
    return False, f"{description}: stopped unexpectedly\n{status}"


def main() -> int:
    parser = argparse.ArgumentParser(description="C64 snapshot spell -more- crash smoke")
    parser.add_argument("--vice", default="x64sc")
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--main-vs", type=Path, default=ROOT / "commodore" / "out" / "c64" / "main.vs")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6510)
    parser.add_argument("--timeout", type=float, default=25.0)
    parser.add_argument("--connect-timeout", type=float, default=12.0)
    parser.add_argument("--connect-retry-delay", type=float, default=0.1)
    parser.add_argument("--socket-timeout", type=float, default=0.5)
    parser.add_argument("--startup-delay", type=float, default=1.0)
    parser.add_argument("--keybuf", default="ma ")
    parser.add_argument("--after-entry-keybuf", default="")
    parser.add_argument("--entry-symbol", default=".player_cast_spell")
    parser.add_argument("--return-symbol", default=".main_loop")
    args = parser.parse_args()

    symbols = parse_vs_symbols(args.main_vs)
    required = {
        "entry": args.entry_symbol,
        "return": args.return_symbol,
        "exit_trampoline": ".exit_trampoline",
    }
    resolved: dict[str, str] = {}
    for key, symbol in required.items():
        addr = symbols.get(symbol)
        if not addr:
            print(f"FAIL: missing symbol {symbol} in {args.main_vs}")
            return 2
        resolved[key] = normalize_addr(addr)
    resolved["basic_warm_start"] = "A002"

    moncommands_path: Path | None = None
    mon_file = tempfile.NamedTemporaryFile("w", delete=False, suffix=".mon")
    mon_file.write(f'undump "{args.snapshot.resolve()}"\n')
    mon_file.close()
    moncommands_path = Path(mon_file.name)

    vice = subprocess.Popen(
        [
            args.vice,
            "-console",
            "-nativemonitor",
            "-warp",
            "+sound",
            "-sounddev",
            "dummy",
            "-remotemonitor",
            "-binarymonitor",
            "-moncommands",
            str(moncommands_path),
            "-limitcycles",
            "900000000",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    connector = VICEConnector(host=args.host, port=args.port, timeout=args.socket_timeout)
    try:
        time.sleep(args.startup_delay)
        connector.connect(
            retries=max(1, int(args.connect_timeout / args.connect_retry_delay)),
            retry_delay=args.connect_retry_delay,
        )
        time.sleep(0.2)
        connector.send_command(f"keybuf {args.keybuf}")

        ok, status = run_to_break_or_jam(
            connector,
            addr=resolved["entry"],
            timeout=args.timeout,
            description=f"snapshot entry {args.entry_symbol}",
        )
        if not ok:
            print(f"FAIL: {status}")
            return 2

        if args.after_entry_keybuf:
            connector.send_command(f"keybuf {args.after_entry_keybuf}")

        ok, status = run_to_break_or_fail(
            connector,
            addr=resolved["return"],
            timeout=args.timeout,
            basic_addr=resolved["basic_warm_start"],
            exit_addr=resolved["exit_trampoline"],
            description=f"snapshot return {args.return_symbol}",
        )
        if ok:
            print("PASS: snapshot_spell_more_smoke")
            return 0
        print(f"FAIL: {status}")
        return 2
    finally:
        connector.close()
        terminate(vice)
        if moncommands_path is not None:
            try:
                os.unlink(moncommands_path)
            except FileNotFoundError:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
