#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from vice_connector import VICEConnector, extract_test_symbols, run_test_case


MARKER_BYTES = b"M8SAVE"


def run(command: list[str], timeout: float = 10.0) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )


def format_save_disk(args: argparse.Namespace) -> tuple[bool, str]:
    args.save_d64.unlink(missing_ok=True)
    completed = run(
        [
            args.c1541,
            "-format",
            "moria128 save,m8",
            "d64",
            str(args.save_d64),
        ]
    )
    return completed.returncode == 0, completed.stdout


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


def run_vice(args: argparse.Namespace) -> int:
    symbols = extract_test_symbols(args.vs)
    command = [
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
        "-drive9type",
        str(args.drive9_type),
        "-attach9rw",
        "-9",
        str(args.save_d64),
    ]
    vice_process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    connector = VICEConnector(timeout=args.socket_timeout)
    try:
        connector.connect(
            retries=max(1, int(args.connect_timeout / args.connect_retry_delay)),
            retry_delay=args.connect_retry_delay,
        )
        result = run_test_case(
            connector,
            prg_path=args.prg,
            start_addr=symbols.start_addr,
            pass_addr=symbols.pass_addr,
            fail_addr=symbols.fail_addr,
            timeout=args.timeout,
            reset_environment=False,
        )
        if not result.passed:
            print(f"FAIL: C128 marker-init payload {result.reason}")
            if result.last_status:
                print(result.last_status[-1000:])
            return 2
        return 0
    finally:
        connector.close()
        terminate_vice(vice_process)


def read_marker(args: argparse.Namespace) -> tuple[bytes | None, str]:
    with tempfile.TemporaryDirectory() as tmp_dir:
        marker_path = Path(tmp_dir) / "MORIA8.ID"
        completed: subprocess.CompletedProcess[str] | None = None
        for marker_name in ("moria8.id,s", "MORIA8.ID,S"):
            completed = run(
                [
                    args.c1541,
                    "-attach",
                    str(args.save_d64),
                    "-read",
                    marker_name,
                    str(marker_path),
                ]
            )
            if completed.returncode == 0 and marker_path.exists():
                break
        if completed.returncode != 0 or not marker_path.exists():
            return None, completed.stdout
        return marker_path.read_bytes(), completed.stdout


def disk_listing(args: argparse.Namespace) -> str:
    completed = run([args.c1541, "-attach", str(args.save_d64), "-list"])
    return completed.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description="C128 real-D64 marker-init smoke")
    parser.add_argument("--vice", required=True)
    parser.add_argument("--c1541", default="c1541")
    parser.add_argument("--prg", required=True, type=Path)
    parser.add_argument("--vs", required=True, type=Path)
    parser.add_argument("--save-d64", required=True, type=Path)
    parser.add_argument("--drive9-type", default="1571")
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--socket-timeout", type=float, default=5.0)
    parser.add_argument("--connect-timeout", type=float, default=12.0)
    parser.add_argument("--connect-retry-delay", type=float, default=0.1)
    args = parser.parse_args()

    ok, output = format_save_disk(args)
    if not ok:
        print("FAIL: could not format C128 marker-init save disk")
        print(output[-2000:])
        return 2

    try:
        vice_rc = run_vice(args)
    except subprocess.TimeoutExpired:
        print(f"FAIL: C128 marker-init smoke timed out after {args.timeout:.1f}s")
        return 2
    if vice_rc != 0:
        return vice_rc

    marker, read_output = read_marker(args)
    if marker != MARKER_BYTES:
        print(f"FAIL: C128 marker-init smoke did not create valid MORIA8.ID (VICE rc={vice_rc})")
        print(disk_listing(args)[-2000:])
        print(read_output[-2000:])
        if marker is not None:
            print(f"Read marker bytes: {marker!r}")
        return 2

    print("PASS: marker_init_d64_128")
    return 0


if __name__ == "__main__":
    sys.exit(main())
