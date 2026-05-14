#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
C128_TESTS_DIR = REPO_ROOT / "commodore" / "c128" / "tests"
if str(C128_TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(C128_TESTS_DIR))

from vice_connector import VICEConnector, extract_test_symbols, parse_vs_symbols, run_test_case


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


def write_bytes(connector: VICEConnector, start_addr: int, data: list[int], *, debug: bool = False) -> None:
    for offset, value in enumerate(data):
        connector.poke(start_addr + offset, value, debug=debug)


def run_marker_init_smoke(args: argparse.Namespace) -> int:
    symbols = parse_vs_symbols(args.main_vs)
    required = [
        ".title_menu_loop",
        ".plus4_install_ram_irq_vectors",
        ".plus4_bank_ram",
        ".save_device",
        ".disk_marker_init",
        ".disk_marker_present",
    ]
    missing = [name for name in required if name not in symbols]
    if missing:
        print(f"FAIL: {args.name} (missing symbols: {', '.join(missing)})")
        return 2

    stub_addr = args.stub_addr
    fail_addr = stub_addr + 0x19
    pass_addr = stub_addr + 0x1C

    def lo(name: str) -> int:
        return int(symbols[name], 16) & 0xFF

    def hi(name: str) -> int:
        return (int(symbols[name], 16) >> 8) & 0xFF

    stub = [
        0x78,                                           # sei
        0x20, lo(".plus4_bank_ram"), hi(".plus4_bank_ram"),
        0xA9, args.save_device,                         # lda #save_device
        0x8D, lo(".save_device"), hi(".save_device"),   # sta save_device
        0x20, lo(".plus4_install_ram_irq_vectors"), hi(".plus4_install_ram_irq_vectors"),
        0x20, lo(".disk_marker_init"), hi(".disk_marker_init"),
        0xB0, 0x08,                                     # bcs fail
        0x20, lo(".disk_marker_present"), hi(".disk_marker_present"),
        0xB0, 0x03,                                     # bcs fail
        0x4C, pass_addr & 0xFF, pass_addr >> 8,         # jmp pass
        0x4C, fail_addr & 0xFF, fail_addr >> 8,         # fail: jmp fail
        0x4C, pass_addr & 0xFF, pass_addr >> 8,         # pass: jmp pass
    ]

    command = build_vice_command(args)
    command.extend([
        "-8",
        str(Path(args.boot_d64).resolve()),
        "-9",
        str(Path(args.save_d64).resolve()),
        "-autostart",
        str(Path(args.boot_d64).resolve()),
    ])

    vice_process = subprocess.Popen(
        command,
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
        try:
            connector.run_until(symbols[".title_menu_loop"], timeout=args.timeout, debug=args.verbose)
        except TimeoutError:
            print(f"FAIL: {args.name} (timeout before title menu)")
            return 2

        write_bytes(connector, stub_addr, stub, debug=args.verbose)
        connector.clear_breakpoints(debug=args.verbose)
        connector.break_at(pass_addr, debug=args.verbose)
        connector.break_at(fail_addr, debug=args.verbose)
        connector.set_register("pc", stub_addr, debug=args.verbose)
        connector.go()
        result = connector.wait_for_stop(pass_addr=pass_addr, fail_addr=fail_addr, timeout=args.timeout)
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


def run_storage_record_smoke(args: argparse.Namespace) -> int:
    symbols = parse_vs_symbols(args.main_vs)
    required = [
        ".title_menu_loop",
        ".plus4_install_ram_irq_vectors",
        ".plus4_bank_ram",
        ".save_device",
        ".disk_mode",
        ".disk_setup_done",
        ".save_game",
        ".load_game",
        ".disk_marker_init",
        ".load_resume_game",
        ".main_loop",
        ".input_get_key",
    ]
    missing = [name for name in required if name not in symbols]
    if missing:
        print(f"FAIL: {args.name} (missing symbols: {', '.join(missing)})")
        return 2

    stub_addr = args.stub_addr
    fail_addr = stub_addr + 0x40
    pass_addr = stub_addr + 0x43

    def lo(name: str) -> int:
        return int(symbols[name], 16) & 0xFF

    def hi(name: str) -> int:
        return (int(symbols[name], 16) >> 8) & 0xFF

    def jmp(addr: int) -> list[int]:
        return [0x4C, addr & 0xFF, addr >> 8]

    prefix = [
        0x78,                                           # sei
        0x20, lo(".plus4_bank_ram"), hi(".plus4_bank_ram"),
        0xA9, args.save_device,                         # lda #save_device
        0x8D, lo(".save_device"), hi(".save_device"),   # sta save_device
        0xA9, 0x02,                                     # lda #2 (separate save drive)
        0x8D, lo(".disk_mode"), hi(".disk_mode"),       # sta disk_mode
        0xA9, 0x01,                                     # lda #1
        0x8D, lo(".disk_setup_done"), hi(".disk_setup_done"),
        0x20, lo(".plus4_install_ram_irq_vectors"), hi(".plus4_install_ram_irq_vectors"),
        0x20, lo(".disk_marker_init"), hi(".disk_marker_init"),
        0x90, 0x03,                                     # bcc marker ok
        *jmp(fail_addr),
    ]
    if args.storage_op == "save":
        body = [
            0x20, lo(".load_game"), hi(".load_game"),
            0x90, 0x08,                                 # bcc fail
            0x20, lo(".save_game"), hi(".save_game"),
            0x90, 0x03,                                 # bcc fail
            *jmp(pass_addr),
            *jmp(fail_addr),
        ]
        pass_break = pass_addr
        fail_break = fail_addr
    else:
        body = [
            0x20, lo(".load_game"), hi(".load_game"),
            0x90, 0x03,                                 # bcc fail
            *jmp(int(symbols[".load_resume_game"], 16)),
            *jmp(fail_addr),
        ]
        pass_break = int(symbols[".main_loop"], 16)
        fail_break = fail_addr

    stub = prefix + body
    if len(stub) > fail_addr - stub_addr:
        print(f"FAIL: {args.name} (storage stub too large)")
        return 2
    stub.extend([0xEA] * ((fail_addr - stub_addr) - len(stub)))
    stub.extend(jmp(fail_addr))
    stub.extend(jmp(pass_addr))

    command = build_vice_command(args)
    command.extend([
        "-8",
        str(Path(args.boot_d64).resolve()),
        "-9",
        str(Path(args.save_d64).resolve()),
        "-autostart",
        str(Path(args.boot_d64).resolve()),
    ])

    vice_process = subprocess.Popen(
        command,
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
        try:
            connector.run_until(symbols[".title_menu_loop"], timeout=args.timeout, debug=args.verbose)
        except TimeoutError:
            print(f"FAIL: {args.name} (timeout before title menu)")
            return 2

        write_bytes(connector, stub_addr, stub, debug=args.verbose)
        connector.clear_breakpoints(debug=args.verbose)
        connector.break_at(pass_break, debug=args.verbose)
        connector.break_at(fail_break, debug=args.verbose)
        connector.set_register("pc", stub_addr, debug=args.verbose)
        connector.go()
        result = connector.wait_for_stop(pass_addr=pass_break, fail_addr=fail_break, timeout=args.timeout)
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


def run_monitor_test(args: argparse.Namespace) -> int:
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
        result = run_test_case(
            connector,
            prg_path=prg_path,
            start_addr=symbols.start_addr,
            pass_addr=symbols.pass_addr,
            fail_addr=symbols.fail_addr,
            timeout=args.timeout,
            reset_environment=False,
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
    parser = argparse.ArgumentParser(description="Plus/4 Python monitor harness")
    parser.add_argument("--mode", choices=("prg", "marker-init-smoke", "storage-record-smoke"), default="prg")
    parser.add_argument("--name", required=True)
    parser.add_argument("--prg")
    parser.add_argument("--vs", help="Path to the companion .vs file; defaults to <prg>.vs")
    parser.add_argument("--main-vs", help="Product main.vs for disk smoke modes")
    parser.add_argument("--boot-d64", help="Product boot disk image for disk smoke modes")
    parser.add_argument("--save-d64", help="Save disk fixture for disk smoke modes")
    parser.add_argument("--save-device", type=int, default=9)
    parser.add_argument("--storage-op", choices=("save", "load-resume"), default="save")
    parser.add_argument("--stub-addr", type=lambda value: int(value, 0), default=0x0800)
    parser.add_argument("--vice", default="xplus4")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6510)
    parser.add_argument("--monitor-address", help="Optional raw VICE -remotemonitoraddress value")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--socket-timeout", type=float, default=0.5)
    parser.add_argument("--connect-timeout", type=float, default=5.0)
    parser.add_argument("--connect-retry-delay", type=float, default=0.1)
    parser.add_argument("--attach-only", action="store_true")
    parser.add_argument("--vice-arg", action="append", default=[])
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser


def main() -> int:
    args = build_arg_parser().parse_args()
    if args.mode == "marker-init-smoke":
        if not args.main_vs or not args.boot_d64 or not args.save_d64:
            raise SystemExit("--main-vs, --boot-d64, and --save-d64 are required for marker-init-smoke")
        return run_marker_init_smoke(args)
    if args.mode == "storage-record-smoke":
        if not args.main_vs or not args.boot_d64 or not args.save_d64:
            raise SystemExit("--main-vs, --boot-d64, and --save-d64 are required for storage-record-smoke")
        return run_storage_record_smoke(args)
    if not args.prg:
        raise SystemExit("--prg is required for prg mode")
    return run_monitor_test(args)


if __name__ == "__main__":
    raise SystemExit(main())
