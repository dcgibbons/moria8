#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent.parent
C128_TESTS_DIR = REPO_ROOT / "commodore" / "c128" / "tests"
if str(C128_TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(C128_TESTS_DIR))

from vice_connector import MonitorTestResult, VICEConnector, normalize_addr, parse_vs_symbols


def build_vice_command(args: argparse.Namespace) -> list[str]:
    command = [
        args.vice,
        "-console",
        "-nativemonitor",
        "-warp",
        "+sound",
        "-sounddev",
        "dummy",
        "-remotemonitor",
        "-binarymonitor",
        "-drive8truedrive",
        "-drive8type",
        str(args.drive8_type),
        "-drive9truedrive",
        "-drive9type",
        str(args.drive9_type),
        "-attach8rw",
        "-8",
        str(args.boot_d64),
        "-attach9rw",
        "-9",
        str(args.save_d64),
        "-autostart",
        str(args.boot_d64),
    ]
    if args.limitcycles > 0:
        command.extend(["-limitcycles", str(args.limitcycles)])
    return command


def terminate_vice(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=2.0)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2.0)


def run_vice(args: argparse.Namespace, pass_addr: str, fail_addr: str | None, dump_addrs: list[str]) -> tuple[MonitorTestResult, list[str]]:
    process: subprocess.Popen[bytes] | None = None
    connector = VICEConnector(host=args.host, port=args.port, timeout=args.socket_timeout)
    dumps: list[str] = []
    try:
        process = subprocess.Popen(
            build_vice_command(args),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        connector.connect(
            retries=max(1, int(args.connect_timeout / args.connect_retry_delay)),
            retry_delay=args.connect_retry_delay,
        )
        if args.start_symbol:
            connector.run_until(args.start_addr, timeout=args.timeout)
        connector.clear_breakpoints()
        connector.break_at(pass_addr)
        if fail_addr:
            connector.break_at(fail_addr)
        connector.go()
        result = connector.wait_for_stop(
            pass_addr=pass_addr,
            fail_addr=fail_addr,
            timeout=args.timeout,
        )
        if not result.passed:
            for addr in dump_addrs:
                try:
                    dumps.append(connector.send_command(f"m {addr} {addr}"))
                except Exception as exc:
                    dumps.append(f"{addr}: {exc}")
        return result, dumps
    finally:
        connector.close()
        terminate_vice(process)


def main() -> int:
    parser = argparse.ArgumentParser(description="Plus/4 scripted product smoke")
    parser.add_argument("--name", required=True)
    parser.add_argument("--vice", required=True)
    parser.add_argument("--boot-d64", required=True, type=Path)
    parser.add_argument("--save-d64", required=True, type=Path)
    parser.add_argument("--main-vs", required=True, type=Path)
    parser.add_argument("--pass-symbol", required=True)
    parser.add_argument("--fail-symbol")
    parser.add_argument("--start-symbol")
    parser.add_argument("--limitcycles", type=int, default=0)
    parser.add_argument("--drive8-type", default="1541")
    parser.add_argument("--drive9-type", default="1541")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6510)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--connect-timeout", type=float, default=12.0)
    parser.add_argument("--connect-retry-delay", type=float, default=0.1)
    parser.add_argument("--socket-timeout", type=float, default=0.5)
    args = parser.parse_args()

    symbols = parse_vs_symbols(args.main_vs)
    pass_addr = symbols.get(args.pass_symbol)
    if not pass_addr:
        print(f"FAIL: missing symbol {args.pass_symbol} in {args.main_vs}")
        return 2
    fail_addr = None
    if args.fail_symbol:
        fail_addr = symbols.get(args.fail_symbol)
        if not fail_addr:
            print(f"FAIL: missing symbol {args.fail_symbol} in {args.main_vs}")
            return 2
    args.start_addr = None
    if args.start_symbol:
        args.start_addr = symbols.get(args.start_symbol)
        if not args.start_addr:
            print(f"FAIL: missing symbol {args.start_symbol} in {args.main_vs}")
            return 2
        args.start_addr = normalize_addr(args.start_addr)

    dump_addrs: list[str] = []
    dump_symbols = (".load_result", ".save_io_error", ".save_magic_buf", ".load_save_version", ".disk_error_phase", ".disk_error_readst", ".disk_error_dos0", ".disk_error_dos1")
    for symbol in dump_symbols:
        addr = symbols.get(symbol)
        if addr:
            dump_addrs.append(normalize_addr(addr))

    result, dumps = run_vice(args, normalize_addr(pass_addr), normalize_addr(fail_addr) if fail_addr else None, dump_addrs)
    if result.passed:
        print(f"PASS: {args.name}")
        return 0

    print(f"FAIL: {args.name} ({result.reason})")
    for dump in dumps:
        print(dump.strip())
    if result.last_status:
        print(result.last_status[-2000:])
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
