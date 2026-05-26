#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent.parent
C128_TESTS_DIR = REPO_ROOT / "commodore" / "c128" / "tests"
if str(C128_TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(C128_TESTS_DIR))

from vice_connector import MonitorTestResult, VICEConnector, normalize_addr, parse_vs_symbols

MEM_DUMP_RE = re.compile(r">\S+:\S+\s+([0-9a-fA-F]{2})")


def build_vice_command(args: argparse.Namespace) -> list[str]:
    command = [
        args.vice,
        "-console",
        "-nativemonitor",
        "-warp",
        "+saveres",
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
    ]
    if args.save_d64:
        command.extend([
            "-attach9rw",
            "-9",
            str(args.save_d64),
        ])
    command.extend([
        "-autostart",
        str(args.boot_d64),
    ])
    if args.limitcycles > 0:
        command.extend(["-limitcycles", str(args.limitcycles)])
    return command


def terminate_vice(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=2.0)
        return
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2.0)


def read_byte(connector: VICEConnector, addr: str) -> int:
    dump = connector.send_command(f"m {addr} {addr}")
    match = MEM_DUMP_RE.search(dump)
    if not match:
        raise ValueError(f"could not parse memory dump for ${addr}: {dump!r}")
    return int(match.group(1), 16)


def run_vice(args: argparse.Namespace, resolved: dict[str, str]) -> tuple[MonitorTestResult, dict[str, int]]:
    process: subprocess.Popen[bytes] | None = None
    connector = VICEConnector(host=args.host, port=args.port, timeout=args.socket_timeout)
    result = MonitorTestResult(False, "not run", "")
    diagnostics: dict[str, int] = {}
    try:
        process = subprocess.Popen(
            build_vice_command(args),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            connector.connect(
                retries=max(1, int(args.connect_timeout / args.connect_retry_delay)),
                retry_delay=args.connect_retry_delay,
            )
            connector.clear_breakpoints()
            connector.break_at(resolved["commit_initialized"])
            connector.break_at(resolved["init_fail"])
            connector.go()
            pass_addr = resolved["commit_initialized"]
            fail_addr = resolved["init_fail"]
            if args.expect == "init-fail":
                pass_addr = resolved["init_fail"]
                fail_addr = resolved["commit_initialized"]
            result = connector.wait_for_stop(
                pass_addr=pass_addr,
                fail_addr=fail_addr,
                timeout=args.timeout,
            )
        except ConnectionError as exc:
            result = MonitorTestResult(False, str(exc), "")
        if result.passed:
            for key in ("disk_error_phase", "disk_error_readst", "disk_error_dos0", "disk_error_dos1", "disk_status"):
                addr = resolved.get(key)
                if addr:
                    diagnostics[key] = read_byte(connector, addr)
        return result, diagnostics
    finally:
        if process is not None and process.poll() is None:
            try:
                connector.send_command("quit", expect_prompt=False)
                process.wait(timeout=2.0)
            except Exception:
                terminate_vice(process)
        connector.close()
        terminate_vice(process)


def main() -> int:
    parser = argparse.ArgumentParser(description="Plus/4 product Disk Setup smoke")
    parser.add_argument("--vice", required=True)
    parser.add_argument("--boot-d64", required=True, type=Path)
    parser.add_argument("--save-d64", type=Path)
    parser.add_argument("--main-vs", required=True, type=Path)
    parser.add_argument("--expect", choices=("initialized", "init-fail"), default="initialized")
    parser.add_argument("--expect-dos-code")
    parser.add_argument("--expect-phase")
    parser.add_argument("--expect-disk-status")
    parser.add_argument("--print-diagnostics", action="store_true")
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
    required = {
        "commit_initialized": ".disk_setup_commit_initialized",
        "init_fail": ".uds_show_init_fail",
    }
    optional = {
        "disk_error_phase": ".disk_error_phase",
        "disk_error_readst": ".disk_error_readst",
        "disk_error_dos0": ".disk_error_dos0",
        "disk_error_dos1": ".disk_error_dos1",
        "disk_status": ".disk_status",
    }
    resolved: dict[str, str] = {}
    for key, symbol in required.items():
        addr = symbols.get(symbol)
        if not addr:
            print(f"FAIL: missing symbol {symbol} in {args.main_vs}")
            return 2
        resolved[key] = normalize_addr(addr)
    for key, symbol in optional.items():
        addr = symbols.get(symbol)
        if addr:
            resolved[key] = normalize_addr(addr)

    result, diagnostics = run_vice(args, resolved)
    if result.passed:
        if args.print_diagnostics:
            print(f"diagnostics: {diagnostics}")
        if args.expect_dos_code:
            if len(args.expect_dos_code) != 2 or "disk_error_dos0" not in diagnostics or "disk_error_dos1" not in diagnostics:
                print("FAIL: --expect-dos-code requires two digits and disk error symbols")
                return 2
            actual = f"{diagnostics['disk_error_dos0'] - 0x30}{diagnostics['disk_error_dos1'] - 0x30}"
            if actual != args.expect_dos_code:
                print(f"FAIL: expected DOS code {args.expect_dos_code}, got {actual} ({diagnostics})")
                return 2
        if args.expect_phase:
            actual_phase = diagnostics.get("disk_error_phase")
            expected_phase = int(args.expect_phase, 0)
            if actual_phase != expected_phase:
                print(f"FAIL: expected phase ${expected_phase:02x}, got ${actual_phase or 0:02x} ({diagnostics})")
                return 2
        if args.expect_disk_status:
            actual_status = diagnostics.get("disk_status")
            expected_status = int(args.expect_disk_status, 0)
            if actual_status != expected_status:
                print(f"FAIL: expected disk status ${expected_status:02x}, got ${actual_status or 0:02x} ({diagnostics})")
                return 2
        if args.expect == "init-fail":
            print("PASS: disk_setup_missing_save_plus4")
        else:
            print("PASS: disk_setup_product_plus4")
        return 0

    if args.expect == "initialized" and result.reason == f"reached test_fail label at ${resolved['init_fail']}":
        print(f"FAIL: Disk Setup reached init failure at ${resolved['init_fail']}")
    elif args.expect == "init-fail" and result.reason == f"reached test_fail label at ${resolved['commit_initialized']}":
        print(f"FAIL: Disk Setup unexpectedly initialized at ${resolved['commit_initialized']}")
    else:
        print(f"FAIL: Disk Setup smoke did not reach expected {args.expect} path ({result.reason})")
    if result.last_status:
        print(result.last_status[-2000:])
    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
