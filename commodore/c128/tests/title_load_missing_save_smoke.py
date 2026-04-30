#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from vice_connector import normalize_addr, parse_vs_symbols


def run_vice(args: argparse.Namespace, moncommands: Path, monlog: Path) -> int:
    command = [
        args.vice,
        "-console",
        "-nativemonitor",
        "-warp",
        "-80col",
        "-autostart",
        str(args.boot_d64),
        "-keybuf",
        args.keybuf,
        "-keybuf-delay",
        str(args.keybuf_delay),
        "-moncommands",
        str(moncommands),
        "-monlog",
        "-monlogname",
        str(monlog),
        "-limitcycles",
        str(args.limitcycles),
        "+sound",
        "-sounddev",
        "dummy",
        "+remotemonitor",
        "+binarymonitor",
    ]
    return subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode


def log_reached(log_text: str, addr: str) -> bool:
    return f"C:${addr}" in log_text.upper()


def main() -> int:
    parser = argparse.ArgumentParser(description="C128 drive-9 missing-save title-load smoke")
    parser.add_argument("--vice", required=True)
    parser.add_argument("--boot-d64", required=True, type=Path)
    parser.add_argument("--save-d64", required=True, type=Path)
    parser.add_argument("--main-vs", required=True, type=Path)
    parser.add_argument("--keybuf", default="LY ")
    parser.add_argument("--keybuf-delay", type=int, default=8)
    parser.add_argument("--limitcycles", type=int, default=260000000)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6510)
    parser.add_argument("--timeout", type=float, default=40.0)
    parser.add_argument("--connect-timeout", type=float, default=12.0)
    parser.add_argument("--connect-retry-delay", type=float, default=0.1)
    parser.add_argument("--socket-timeout", type=float, default=0.5)
    parser.add_argument("--startup-delay", type=float, default=2.0)
    parser.add_argument("--attach-only", action="store_true")
    parser.add_argument("--skip-initial-stop", action="store_true")
    args = parser.parse_args()

    symbols = parse_vs_symbols(args.main_vs)
    required = {
        "missing_save_dismiss": ".input_get_modal_dismiss_key",
        "runtime_load_failed": ".runtime_load_failed",
        "title_fallback_render": ".title_fallback_render",
    }
    resolved: dict[str, str] = {}
    for key, symbol in required.items():
        addr = symbols.get(symbol)
        if not addr:
            print(f"FAIL: missing symbol {symbol} in {args.main_vs}")
            return 2
        resolved[key] = normalize_addr(addr)

    moncommands_path: Path | None = None
    monlog_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".mon") as mon_file:
            mon_file.write(f'attach "{args.save_d64.resolve()}" 9\n')
            mon_file.write(f"until ${resolved['missing_save_dismiss']}\n")
            mon_file.write("g\n")
            moncommands_path = Path(mon_file.name)

        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".log") as log_file:
            monlog_path = Path(log_file.name)

        vice_rc = run_vice(args, moncommands_path, monlog_path)
        log_text = monlog_path.read_text(errors="replace")
        if log_reached(log_text, resolved["missing_save_dismiss"]):
            print("PASS: boot_title_load_missing_savefile_smoke")
            return 0

        if log_reached(log_text, resolved["runtime_load_failed"]):
            print(f"FAIL: reached runtime_load_failed at ${resolved['runtime_load_failed']}")
            return 2
        if log_reached(log_text, resolved["title_fallback_render"]):
            print(f"FAIL: reached title_fallback_render at ${resolved['title_fallback_render']}")
            return 2

        print(f"FAIL: missing-save title load did not reach dismiss prompt (VICE rc={vice_rc})")
        print(log_text[-2000:])
        return 2
    finally:
        for path in (moncommands_path, monlog_path):
            if path is None:
                continue
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


if __name__ == "__main__":
    sys.exit(main())
