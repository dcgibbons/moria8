#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
TESTS_DIR = SCRIPT_DIR / "tests"
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))

from vice_connector import VICEConnector, extract_test_symbols, run_test_case


def build_vice_command(args: argparse.Namespace) -> list[str]:
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
    ]
    if args.monitor_address:
        command.extend(["-remotemonitoraddress", args.monitor_address])
    for extra_arg in args.vice_arg:
        command.append(extra_arg)
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


def create_ready_snapshot(args: argparse.Namespace, snapshot_path: Path) -> None:
    snapshot_path.parent.mkdir(parents=True, exist_ok=True)
    if snapshot_path.exists():
        snapshot_path.unlink()

    vice_process = subprocess.Popen(
        build_vice_command(args),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    connector = VICEConnector(host=args.host, port=args.port, timeout=args.socket_timeout)
    try:
        connector.connect(
            retries=max(1, int(args.connect_timeout / args.connect_retry_delay)),
            retry_delay=args.connect_retry_delay,
            debug=args.verbose,
        )
        connector.poke("FF00", "3E", debug=args.verbose)
        connector.poke("D506", "07", debug=args.verbose)
        connector.poke("D011", "00", debug=args.verbose)
        connector.dump_snapshot(snapshot_path, debug=args.verbose)
    finally:
        connector.close()
        terminate_vice(vice_process)

    if not snapshot_path.exists() or snapshot_path.stat().st_size <= 0:
        raise RuntimeError(f"failed to create snapshot at {snapshot_path}")


def build_connector(args: argparse.Namespace) -> VICEConnector:
    return VICEConnector(host=args.host, port=args.port, timeout=args.socket_timeout)


def run_monitor_test(args: argparse.Namespace) -> int:
    snapshot_path = Path(args.snapshot).resolve() if args.snapshot else None
    if snapshot_path is not None and args.ensure_snapshot and not snapshot_path.exists():
        create_ready_snapshot(args, snapshot_path)

    prg_path = Path(args.prg).resolve()
    vs_path = Path(args.vs).resolve() if args.vs else prg_path.with_suffix(".vs")
    symbols = extract_test_symbols(vs_path)

    vice_process: subprocess.Popen[bytes] | None = None
    if not args.attach_only:
        vice_process = subprocess.Popen(
            build_vice_command(args),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    connector = VICEConnector(host=args.host, port=args.port, timeout=args.socket_timeout)
    try:
        connector.connect(
            retries=max(1, int(args.connect_timeout / args.connect_retry_delay)),
            retry_delay=args.connect_retry_delay,
            debug=args.verbose,
        )
        if snapshot_path is not None:
            connector.undump_snapshot(snapshot_path, debug=args.verbose)
        result = run_test_case(
            connector,
            prg_path=prg_path,
            start_addr=symbols.start_addr,
            pass_addr=symbols.pass_addr,
            fail_addr=symbols.fail_addr,
            timeout=args.timeout,
            reset_environment=not args.no_reset_environment,
            debug=args.verbose,
        )
    finally:
        connector.close()
        terminate_vice(vice_process)

    if result.passed:
        print(f"PASS: {args.name}")
        return 0

    if args.verbose and result.last_status:
        print(result.last_status)
    print(f"FAIL: {args.name} ({result.reason})")
    return result.exit_code


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="C128 Python monitor harness (Gate C.1/C.2 slice)")
    parser.add_argument("--name")
    parser.add_argument("--prg")
    parser.add_argument("--vs", help="Path to the companion .vs file; defaults to <prg>.vs")
    parser.add_argument("--snapshot", help="Restore the given prepared .vsf snapshot via monitor-side `undump` before running the test")
    parser.add_argument("--ensure-snapshot", action="store_true", help="Create --snapshot first if it does not exist")
    parser.add_argument("--prepare-snapshot", help="Create a prepared .vsf snapshot and exit")
    parser.add_argument("--vice", default="x128")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6510)
    parser.add_argument("--monitor-address", help="Optional raw VICE -remotemonitoraddress value")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--socket-timeout", type=float, default=0.5)
    parser.add_argument("--connect-timeout", type=float, default=5.0)
    parser.add_argument("--connect-retry-delay", type=float, default=0.1)
    parser.add_argument("--attach-only", action="store_true")
    parser.add_argument("--no-reset-environment", action="store_true")
    parser.add_argument("--vice-arg", action="append", default=[])
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser


def main() -> int:
    parser = build_arg_parser()
    args = parser.parse_args()

    if args.prepare_snapshot:
        create_ready_snapshot(args, Path(args.prepare_snapshot).resolve())
        print(f"READY SNAPSHOT: {Path(args.prepare_snapshot).resolve()}")
        return 0

    if not args.name or not args.prg:
        parser.error("--name and --prg are required unless --prepare-snapshot is used")

    return run_monitor_test(args)


if __name__ == "__main__":
    raise SystemExit(main())
