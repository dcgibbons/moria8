#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONNECTOR_DIR = ROOT / "commodore" / "c128" / "tests"
if str(CONNECTOR_DIR) not in sys.path:
    sys.path.insert(0, str(CONNECTOR_DIR))

from vice_connector import VICEConnector, parse_vs_symbols


KEYBUF = "NA\rCA\rB LPAA........................I"


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
    args = parser.parse_args()

    symbols = parse_vs_symbols(args.vs)
    detect_addr = symbols[".eff_detect_evil"]
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

        detect_status = connector.run_until(detect_addr, timeout=args.stage_timeout)
        if not reached_addr(detect_status, detect_addr):
            print("FAIL: detect stage (did not reach eff_detect_evil)")
            if detect_status:
                print(detect_status.strip())
            return 2

        inventory_status = connector.run_until(inventory_addr, timeout=args.stage_timeout)
        if reached_addr(inventory_status, inventory_addr):
            print("PASS: product_detect_evil_smoke")
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
