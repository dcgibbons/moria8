#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

from vice_connector import VICEConnector, normalize_addr, parse_vs_symbols


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


def stopped_at(status: str, addr: str) -> bool:
    return f"C:${addr}" in status.upper()


def run_to_break_or_fail(
    connector: VICEConnector,
    *,
    addr: str,
    timeout: float,
    fallback_addr: str,
    fail_addr: str,
    description: str,
) -> tuple[bool, str]:
    try:
        connector.clear_breakpoints()
        connector.break_at(fallback_addr)
        connector.break_at(fail_addr)
        connector.break_at(addr)
        connector.go()
        status = connector.read_until_prompt(deadline=time.monotonic() + timeout)
    except TimeoutError:
        return False, f"{description}: timeout waiting for ${addr}"

    upper = status.upper()
    if stopped_at(upper, addr):
        return True, status
    if stopped_at(upper, fallback_addr):
        return False, f"{description}: reached title_fallback_render at ${fallback_addr}"
    if stopped_at(upper, fail_addr):
        return False, f"{description}: reached c128_test_title_art_fail_sym at ${fail_addr}"
    if "JAM" in upper or "INVALID OPCODE" in upper:
        return False, f"{description}: CPU JAM"
    return False, f"{description}: stopped unexpectedly\n{status}"


def build_vice_command(args: argparse.Namespace) -> list[str]:
    return [
        args.vice,
        "-console",
        "-nativemonitor",
        "-warp",
        "-80col",
        "+sound",
        "-sounddev",
        "dummy",
        "-remotemonitor",
        "-binarymonitor",
        "-autostart",
        str(args.boot_d64),
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="C128 mounted-save-disk missing-savefile smoke")
    parser.add_argument("--vice", required=True)
    parser.add_argument("--boot-d64", required=True, type=Path)
    parser.add_argument("--save-d64", required=True, type=Path)
    parser.add_argument("--main-vs", required=True, type=Path)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6510)
    parser.add_argument("--timeout", type=float, default=40.0)
    parser.add_argument("--connect-timeout", type=float, default=12.0)
    parser.add_argument("--connect-retry-delay", type=float, default=0.1)
    parser.add_argument("--socket-timeout", type=float, default=0.5)
    parser.add_argument("--keybuf", default="LN1      ")
    parser.add_argument("--keybuf-delay", type=int, default=8)
    parser.add_argument("--attach-only", action="store_true")
    parser.add_argument("--skip-initial-stop", action="store_true")
    args = parser.parse_args()

    symbols = parse_vs_symbols(args.main_vs)
    required = {
        "title_menu_ready": ".title_menu_ready",
        "title_art_pass": ".c128_test_title_art_pass_sym",
        "title_art_fail": ".c128_test_title_art_fail_sym",
        "title_fallback_render": ".title_fallback_render",
    }
    resolved: dict[str, str] = {}
    for key, symbol in required.items():
        addr = symbols.get(symbol)
        if not addr:
            print(f"FAIL: missing symbol {symbol} in {args.main_vs}")
            return 2
        resolved[key] = normalize_addr(addr)

    vice_process: subprocess.Popen[bytes] | None = None
    connector = VICEConnector(host=args.host, port=args.port, timeout=args.socket_timeout)
    try:
        if not args.attach_only:
            vice_process = subprocess.Popen(
                build_vice_command(args),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        connector.connect(
            retries=max(1, int(args.connect_timeout / args.connect_retry_delay)),
            retry_delay=args.connect_retry_delay,
        )
        if not args.skip_initial_stop:
            ok, status = run_to_break_or_fail(
                connector,
                addr=resolved["title_menu_ready"],
                timeout=args.timeout,
                fallback_addr=resolved["title_fallback_render"],
                fail_addr=resolved["title_art_fail"],
                description="initial title menu",
            )
            if not ok:
                print(f"FAIL: {status}")
                return 2

        connector.send_command(f'attach "{args.save_d64.resolve()}" 8')
        connector.send_command(f"keybuf {args.keybuf}")

        ok, status = run_to_break_or_fail(
            connector,
            addr=resolved["title_art_pass"],
            timeout=args.timeout,
            fallback_addr=resolved["title_fallback_render"],
            fail_addr=resolved["title_art_fail"],
            description="mounted-save-disk load miss return",
        )
        if not ok:
            print(f"FAIL: {status}")
            return 2

        print("PASS: boot_title_load_missing_savefile_smoke")
        return 0
    finally:
        connector.close()
        terminate_vice(vice_process)


if __name__ == "__main__":
    sys.exit(main())
