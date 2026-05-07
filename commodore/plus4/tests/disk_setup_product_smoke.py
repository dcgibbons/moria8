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
        return
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2.0)


def run_vice(args: argparse.Namespace, resolved: dict[str, str]) -> MonitorTestResult:
    process: subprocess.Popen[bytes] | None = None
    connector = VICEConnector(host=args.host, port=args.port, timeout=args.socket_timeout)
    result = MonitorTestResult(False, "not run", "")
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
        connector.clear_breakpoints()
        connector.break_at(resolved["commit_initialized"])
        connector.break_at(resolved["init_fail"])
        connector.go()
        result = connector.wait_for_stop(
            pass_addr=resolved["commit_initialized"],
            fail_addr=resolved["init_fail"],
            timeout=args.timeout,
        )
        return result
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
    parser.add_argument("--save-d64", required=True, type=Path)
    parser.add_argument("--main-vs", required=True, type=Path)
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
    resolved: dict[str, str] = {}
    for key, symbol in required.items():
        addr = symbols.get(symbol)
        if not addr:
            print(f"FAIL: missing symbol {symbol} in {args.main_vs}")
            return 2
        resolved[key] = normalize_addr(addr)

    result = run_vice(args, resolved)
    if result.passed:
        print("PASS: disk_setup_product_plus4")
        return 0

    if result.reason == f"reached test_fail label at ${resolved['init_fail']}":
        print(f"FAIL: Disk Setup reached init failure at ${resolved['init_fail']}")
    else:
        print(f"FAIL: Disk Setup smoke did not reach initialized commit ({result.reason})")
    if result.last_status:
        print(result.last_status[-2000:])
    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
