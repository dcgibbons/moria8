#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from vice_connector import VICEConnector, parse_vs_symbols


def resolve_symbol_addr(vs_path: Path, symbol_name: str) -> str:
    symbols = parse_vs_symbols(vs_path)
    addr = symbols.get(symbol_name)
    if not addr:
        raise ValueError(f"missing {symbol_name} in {vs_path}")
    return addr


def build_vice_command(
    *,
    vice: str,
    boot_d64: Path,
    keybuf: str,
    keybuf_delay: int,
) -> list[str]:
    return [
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
        "-autostart",
        str(boot_d64),
        "-keybuf",
        keybuf,
        "-keybuf-delay",
        str(keybuf_delay),
    ]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify the shipping C128 cast flow reaches spell success and does not stop at $D026"
    )
    parser.add_argument("--vice", required=True)
    parser.add_argument("--boot-d64", required=True, type=Path)
    parser.add_argument("--vs", default="build/c128/main.vs", type=Path)
    parser.add_argument("--crash-addr", default="D026")
    parser.add_argument("--success-symbol", default=".pm_mark_worked")
    parser.add_argument("--keybuf", default="NAB\rA\rBMAAL")
    parser.add_argument("--keybuf-delay", type=int, default=8)
    parser.add_argument("--connect-timeout", type=float, default=12.0)
    parser.add_argument("--socket-timeout", type=float, default=1.0)
    parser.add_argument("--success-timeout", type=float, default=20.0)
    parser.add_argument("--post-timeout", type=float, default=10.0)
    args = parser.parse_args()

    if not args.boot_d64.exists():
        print(f"FAIL: missing boot image {args.boot_d64}")
        return 2
    if not args.vs.exists():
        print(f"FAIL: missing symbol file {args.vs}")
        return 2

    try:
        success_addr = resolve_symbol_addr(args.vs, args.success_symbol)
    except ValueError as exc:
        print(f"FAIL: {exc}")
        return 2

    vice_process = subprocess.Popen(
        build_vice_command(
            vice=args.vice,
            boot_d64=args.boot_d64,
            keybuf=args.keybuf,
            keybuf_delay=args.keybuf_delay,
        ),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    connector = VICEConnector(timeout=args.socket_timeout)
    try:
        connector.connect(
            retries=max(1, int(args.connect_timeout / 0.1)),
            retry_delay=0.1,
            debug=False,
        )

        connector.clear_breakpoints()
        connector.break_at(args.crash_addr)
        connector.break_at(success_addr)
        connector.go()

        first_stop = connector.wait_for_stop(
            pass_addr=success_addr,
            fail_addr=args.crash_addr,
            timeout=args.success_timeout,
        )
        if not first_stop.passed:
            if first_stop.reason.startswith("reached test_fail"):
                print(f"FAIL: reproduced shipping spell-cast crash at ${args.crash_addr.strip().upper()}")
            elif first_stop.reason.startswith("timeout"):
                print(f"FAIL: cast flow did not reach {args.success_symbol}")
            else:
                print(f"FAIL: cast flow stopped unexpectedly ({first_stop.reason})")
            return 2

        connector.clear_breakpoints()
        connector.break_at(args.crash_addr)
        connector.go()

        post_stop = connector.wait_for_stop(
            pass_addr=args.crash_addr,
            timeout=args.post_timeout,
        )
        if post_stop.passed:
            print(f"FAIL: reproduced shipping spell-cast crash at ${args.crash_addr.strip().upper()}")
            return 2
        if not post_stop.reason.startswith("timeout"):
            print(f"FAIL: post-cast flow stopped unexpectedly ({post_stop.reason})")
            return 2

        print(f"PASS: cast reached {args.success_symbol} and no crash stop at ${args.crash_addr.strip().upper()}")
        return 0
    finally:
        connector.close()
        vice_process.terminate()
        try:
            vice_process.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            vice_process.kill()
            vice_process.wait(timeout=2.0)


if __name__ == "__main__":
    sys.exit(main())
