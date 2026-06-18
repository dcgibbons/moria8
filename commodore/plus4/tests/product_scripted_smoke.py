#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent.parent
C128_TESTS_DIR = REPO_ROOT / "commodore" / "c128" / "tests"
if str(C128_TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(C128_TESTS_DIR))

from vice_connector import MonitorTestResult, VICEConnector, normalize_addr, parse_vs_symbols

BYTE_DUMP_RE = re.compile(r"C:([0-9A-Fa-f]{4})\s+([0-9A-Fa-f]{2})")
SCREEN_EXPECT_RE = re.compile(r"^([^:]+):([0-9]+):([0-9]+)$")
BYTE_EXPECT_RE = re.compile(r"^([^=]+)=([0-9A-Fa-fx]+)$")
HEX_BYTE_RE = re.compile(r"^[0-9A-Fa-f]{2}$")
REGISTER_PC_RE = re.compile(r"(?:\.;|\.C:)([0-9A-Fa-f]{4})")


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
    ]
    if not args.autostart_only_drive8:
        command.extend([
            "-drive8truedrive",
            "-drive8type",
            str(args.drive8_type),
            "-attach8rw",
            "-8",
            str(args.boot_d64),
        ])
    if Path(args.vice).name == "x128":
        command.append("-80col")
    if args.save_d64:
        command.extend([
            "-drive9truedrive",
            "-drive9type",
            str(args.drive9_type),
        ])
        if args.enable_drive9_bus:
            command.append("-busdevice9")
        command.extend([
            "-attach9rw",
            "-9",
            str(args.save_d64),
        ])
    else:
        command.extend([
            "+busdevice9",
            "-drive9type",
            "0",
        ])
    if args.save10_d64:
        command.extend([
            "-drive10truedrive",
            "-drive10type",
            str(args.drive10_type),
            "-busdevice10",
            "-attach10rw",
            "-10",
            str(args.save10_d64),
        ])
    else:
        command.extend([
            "+busdevice10",
            "-drive10type",
            "0",
        ])
    command.extend([
        "-autostart",
        str(args.boot_d64),
    ])
    if args.limitcycles > 0:
        command.extend(["-limitcycles", str(args.limitcycles)])
    if args.native_start_moncommands:
        command.extend([
            "-moncommands",
            str(args.native_start_moncommands),
            "-monlog",
            "-monlogname",
            str(args.native_start_log),
        ])
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
    time.sleep(1.0)

def read_monitor_byte(connector: VICEConnector, addr: int | str) -> int | None:
    response = connector.send_command(f"m {normalize_addr(addr)} {normalize_addr(addr)}")
    for line in response.splitlines():
        if not line.startswith(">C:"):
            continue
        match = BYTE_DUMP_RE.search(line)
        if match:
            return int(match.group(2), 16)
    return None


def read_monitor_bytes(connector: VICEConnector, start: int, end: int) -> list[int]:
    response = connector.send_command(f"m {normalize_addr(start)} {normalize_addr(end)}")
    values: list[int] = []
    for line in response.splitlines():
        if not line.startswith(">C:"):
            continue
        for token in line.split()[1:]:
            if not HEX_BYTE_RE.match(token):
                break
            values.append(int(token, 16))
    return values


def read_monitor_string(connector: VICEConnector, addr: int, max_len: int = 80) -> list[int]:
    result: list[int] = []
    for value in read_monitor_bytes(connector, addr, addr + max_len - 1):
        if value == 0:
            return result
        result.append(value)
    return result


def check_screen_expectations(connector: VICEConnector, args: argparse.Namespace) -> str | None:
    for symbol, row, col in args.expect_screen:
        source_addr = int(args.symbols[symbol], 16)
        expected = read_monitor_string(connector, source_addr)
        screen_addr = args.screen_base + row * args.screen_cols + col
        actual = read_monitor_bytes(connector, screen_addr, screen_addr + len(expected) - 1)
        if actual != expected:
            return (
                f"screen mismatch for {symbol} at row {row}, col {col}: "
                f"expected {bytes(expected).hex(' ')}, got {bytes(actual).hex(' ')}"
            )
    return None


def check_byte_expectations(connector: VICEConnector, args: argparse.Namespace) -> str | None:
    for symbol, expected in args.expect_bytes:
        actual = read_monitor_byte(connector, int(args.symbols[symbol], 16))
        if actual != expected:
            actual_text = "unreadable" if actual is None else f"${actual:02x}"
            return f"byte mismatch for {symbol}: expected ${expected:02x}, got {actual_text}"
    return None


def scripted_input_exhausted(connector: VICEConnector, args: argparse.Namespace) -> bool:
    key_index_addr = getattr(args, "key_index_addr", None)
    key_script_addr = getattr(args, "key_script_addr", None)
    if key_index_addr is None:
        return False
    wait_loop_addr = (int(key_index_addr, 16) - 3) & 0xFFFF
    pc_match = REGISTER_PC_RE.search(connector.send_command("bt"))
    if pc_match and int(pc_match.group(1), 16) == wait_loop_addr:
        return True
    if key_script_addr is not None:
        key_index = read_monitor_byte(connector, key_index_addr)
        if key_index is not None:
            script_byte = read_monitor_byte(connector, int(key_script_addr, 16) + key_index)
            if script_byte == 0:
                return True
    register_response = connector.send_command("r")
    match = REGISTER_PC_RE.search(register_response)
    if not match:
        match = REGISTER_PC_RE.search(connector.send_command("bt"))
    if not match:
        return False
    return int(match.group(1), 16) == wait_loop_addr


def dumps_show_script_exhausted(args: argparse.Namespace, dumps: list[str]) -> bool:
    key_index_addr = getattr(args, "key_index_addr", None)
    if key_index_addr is None:
        return False
    wait_loop_addr = (int(key_index_addr, 16) - 3) & 0xFFFF
    return any(monitor_text_has_pc(dump, wait_loop_addr) for dump in dumps)


def monitor_text_has_pc(text: str, addr: int | str) -> bool:
    norm = normalize_addr(addr)
    upper = text.upper()
    return any(marker in upper for marker in (
        f"C:${norm}",
        f"C:{norm}",
        f".C:{norm}",
    ))


def attach_drive8(connector: VICEConnector, disk_path: Path, delay: float = 0.5, reset: bool = False) -> None:
    detach_response = connector.send_command("detach 8")
    if "Cannot" in detach_response or "Error" in detach_response or "Failed" in detach_response:
        raise RuntimeError(f"failed to detach drive 8 before image swap: {detach_response.strip()}")
    resource_response = connector.send_command('resourceset "AttachDevice8d0Readonly" "0"')
    if "Cannot" in resource_response or "Error" in resource_response or "Failed" in resource_response:
        raise RuntimeError(f"failed to mark drive 8 runtime attachments writable: {resource_response.strip()}")
    response = connector.send_command(f'attach "{disk_path.resolve()}" 8')
    if "Cannot" in response or "Error" in response or "Failed" in response:
        raise RuntimeError(f"failed to attach drive 8 image {disk_path}: {response.strip()}")
    if reset:
        reset_response = connector.send_command("reset 8")
        if "Cannot" in reset_response or "Error" in reset_response or "Failed" in reset_response:
            raise RuntimeError(f"failed to reset drive 8 after image swap: {reset_response.strip()}")
    time.sleep(delay)


def wait_for_native_start(args: argparse.Namespace) -> MonitorTestResult:
    deadline = time.monotonic() + args.timeout
    needle = f"C:${args.start_addr}"
    while time.monotonic() < deadline:
        try:
            log_text = args.native_start_log.read_text(errors="ignore").upper()
        except FileNotFoundError:
            log_text = ""
        if "JAM" in log_text or "INVALID OPCODE" in log_text:
            return MonitorTestResult(False, "native start wait saw crash", log_text[-1000:])
        for line in log_text.splitlines():
            if line.startswith("UNTIL:") and needle in line:
                return MonitorTestResult(True, "native monitor reached start symbol", line)
        time.sleep(0.1)
    return MonitorTestResult(False, f"timeout after {args.timeout:.1f}s", log_text[-1000:] if "log_text" in locals() else "")


def run_until_pass(connector: VICEConnector, pass_addr: str, timeout: float) -> MonitorTestResult:
    try:
        status = connector.run_until(pass_addr, timeout=timeout)
    except TimeoutError:
        try:
            status = connector.send_command("bt")
        except Exception:
            return MonitorTestResult(False, f"timeout after {timeout}s", "")
        if monitor_text_has_pc(status, pass_addr):
            return MonitorTestResult(True, "", status)
        return MonitorTestResult(False, f"timeout after {timeout}s", "")
    except ConnectionError as exc:
        return MonitorTestResult(False, str(exc), "")
    if monitor_text_has_pc(status, pass_addr):
        return MonitorTestResult(True, "", status)
    if "JAM" in status.upper() or "INVALID OPCODE" in status.upper():
        return MonitorTestResult(False, "CPU JAM", status)
    return MonitorTestResult(False, "stopped without reaching pass breakpoint", status)


def continue_from(connector: VICEConnector, addr: str | None) -> None:
    if addr:
        connector.set_register("pc", addr)
    connector.go()


def run_vice(args: argparse.Namespace, pass_addr: str, fail_addr: str | None, dump_ranges: list[tuple[str, str]]) -> tuple[MonitorTestResult, list[str]]:
    process: subprocess.Popen[bytes] | None = None
    connector = VICEConnector(host=args.host, port=args.port, timeout=args.socket_timeout)
    dumps: list[str] = []
    native_tmp_dir: tempfile.TemporaryDirectory[str] | None = None
    try:
        if args.native_start:
            native_tmp_dir = tempfile.TemporaryDirectory(prefix="moria-product-smoke-")
            args.native_start_moncommands = Path(native_tmp_dir.name) / "native-start.mon"
            args.native_start_log = Path(native_tmp_dir.name) / "native-start.log"
            args.native_start_moncommands.write_text(f"until ${args.start_addr}\n")
        else:
            args.native_start_moncommands = None
            args.native_start_log = None
        process = subprocess.Popen(
            build_vice_command(args),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            if args.startup_delay > 0:
                time.sleep(args.startup_delay)
            if args.native_start:
                start_result = wait_for_native_start(args)
                if not start_result.passed:
                    return start_result, dumps
                connector.connect(
                    retries=max(1, int(args.connect_timeout / args.connect_retry_delay)),
                    retry_delay=args.connect_retry_delay,
                )
                if args.attach8_at_start_d64:
                    attach_drive8(connector, args.attach8_at_start_d64, args.attach_delay, args.reset8_after_attach)
            else:
                connector.connect(
                    retries=max(1, int(args.connect_timeout / args.connect_retry_delay)),
                    retry_delay=args.connect_retry_delay,
                )
            if args.start_symbol and not args.native_start:
                connector.clear_breakpoints()
                connector.break_at(args.start_addr)
                connector.go()
                start_result = connector.wait_for_stop(
                    pass_addr=args.start_addr,
                    timeout=args.timeout,
                )
                if not start_result.passed:
                    try:
                        dumps.append(connector.send_command("bt"))
                    except Exception as exc:
                        dumps.append(f"bt: {exc}")
                    try:
                        screen_start = args.screen_base
                        screen_end = args.screen_base + args.screen_cols * 25 - 1
                        dumps.append(connector.send_command(f"m {normalize_addr(screen_start)} {normalize_addr(screen_end)}"))
                    except Exception as exc:
                        dumps.append(f"screen: {exc}")
                    for start, end in dump_ranges:
                        try:
                            dumps.append(connector.send_command(f"m {start} {end}"))
                        except Exception as exc:
                            dumps.append(f"{start}: {exc}")
                    return start_result, dumps
                if args.attach8_at_start_d64:
                    attach_drive8(connector, args.attach8_at_start_d64, args.attach_delay, args.reset8_after_attach)
            connector.clear_breakpoints()
            if args.swap_addr:
                connector.break_at(args.swap_addr)
                connector.break_at(pass_addr)
                if fail_addr:
                    connector.break_at(fail_addr)
                swap_hits = 0
                resume_addr = args.resume_addr
                while True:
                    continue_from(connector, resume_addr)
                    resume_addr = None
                    result = connector.wait_for_stop(
                        pass_addr=args.swap_addr,
                        fail_addr=fail_addr,
                        timeout=args.timeout,
                    )
                    if result.passed:
                        swap_hits += 1
                        if swap_hits >= args.swap_attach_after_hits:
                            attach_drive8(connector, args.swap_attach8_d64, args.attach_delay, args.reset8_after_attach)
                            if args.swap2_addr:
                                connector.clear_breakpoints()
                                connector.break_at(args.swap2_addr)
                                if fail_addr:
                                    connector.break_at(fail_addr)
                                connector.go()
                                result = connector.wait_for_stop(
                                    pass_addr=args.swap2_addr,
                                    fail_addr=fail_addr,
                                    timeout=args.timeout,
                                )
                                if not result.passed:
                                    try:
                                        dumps.append(connector.send_command("bt"))
                                    except Exception as exc:
                                        dumps.append(f"bt: {exc}")
                                attach_drive8(connector, args.swap2_attach8_d64, args.attach_delay, args.reset8_after_attach)
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
                            break
                        continue
                    if pass_addr in result.last_status.upper().replace("$", ""):
                        result = MonitorTestResult(False, f"reached pass before swap symbol ${args.swap_addr}", result.last_status)
                    if not result.passed:
                        try:
                            dumps.append(connector.send_command("bt"))
                        except Exception as exc:
                            dumps.append(f"bt: {exc}")
                        try:
                            screen_start = args.screen_base
                            screen_end = args.screen_base + args.screen_cols * 25 - 1
                            dumps.append(connector.send_command(f"m {normalize_addr(screen_start)} {normalize_addr(screen_end)}"))
                        except Exception as exc:
                            dumps.append(f"screen: {exc}")
                        for start, end in dump_ranges:
                            try:
                                dumps.append(connector.send_command(f"m {start} {end}"))
                            except Exception as exc:
                                dumps.append(f"{start}: {exc}")
                    break
            else:
                if not args.until_pass:
                    connector.break_at(pass_addr)
                if fail_addr and not args.until_pass:
                    connector.break_at(fail_addr)
                if args.require_hit_addr:
                    connector.break_at(args.require_hit_addr)
                    continue_from(connector, args.resume_addr)
                    required_result = connector.wait_for_stop(
                        pass_addr=args.require_hit_addr,
                        fail_addr=fail_addr,
                        timeout=args.timeout,
                    )
                    if not required_result.passed:
                        try:
                            dumps.append(connector.send_command("bt"))
                        except Exception as exc:
                            dumps.append(f"bt: {exc}")
                        for start, end in dump_ranges:
                            try:
                                dumps.append(connector.send_command(f"m {start} {end}"))
                            except Exception as exc:
                                dumps.append(f"{start}: {exc}")
                        return required_result, dumps
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
                else:
                    if args.until_pass:
                        result = run_until_pass(connector, pass_addr, args.timeout)
                    else:
                        continue_from(connector, args.resume_addr)
                        result = connector.wait_for_stop(
                            pass_addr=pass_addr,
                            fail_addr=fail_addr,
                            timeout=args.timeout,
                        )
            if (
                args.pass_on_script_exhausted
                and not result.passed
                and result.reason.startswith("timeout")
                and scripted_input_exhausted(connector, args)
            ):
                result = MonitorTestResult(True, "script exhausted at next input wait", result.last_status)
            if result.passed:
                byte_error = check_byte_expectations(connector, args)
                if byte_error:
                    result = MonitorTestResult(False, byte_error, result.last_status)
                screen_error = check_screen_expectations(connector, args)
                if screen_error and result.passed:
                    result = MonitorTestResult(False, screen_error, result.last_status)
                    start = args.screen_base
                    end = args.screen_base + args.screen_cols * 25 - 1
                    dumps.append(connector.send_command(f"m {normalize_addr(start)} {normalize_addr(end)}"))
        except ConnectionError as exc:
            result = MonitorTestResult(False, str(exc), "")
        if not result.passed:
            try:
                dumps.append(connector.send_command("bt"))
            except Exception as exc:
                dumps.append(f"bt: {exc}")
            try:
                screen_start = args.screen_base
                screen_end = args.screen_base + args.screen_cols * 25 - 1
                dumps.append(connector.send_command(f"m {normalize_addr(screen_start)} {normalize_addr(screen_end)}"))
            except Exception as exc:
                dumps.append(f"screen: {exc}")
            for start, end in dump_ranges:
                try:
                    dumps.append(connector.send_command(f"m {start} {end}"))
                except Exception as exc:
                    dumps.append(f"{start}: {exc}")
            if args.until_pass:
                if any(monitor_text_has_pc(dump, pass_addr) for dump in dumps):
                    result = MonitorTestResult(True, "target PC reached after timeout", result.last_status)
            if (
                not result.passed
                and args.pass_on_script_exhausted
                and result.reason.startswith("timeout")
                and dumps_show_script_exhausted(args, dumps)
            ):
                result = MonitorTestResult(True, "script exhausted at next input wait", result.last_status)
        return result, dumps
    finally:
        if process is not None and process.poll() is None:
            try:
                connector.send_command("quit", expect_prompt=False)
                process.wait(timeout=2.0)
            except Exception:
                terminate_vice(process)
        connector.close()
        terminate_vice(process)
        if native_tmp_dir is not None:
            native_tmp_dir.cleanup()
        time.sleep(1.0)


def main() -> int:
    parser = argparse.ArgumentParser(description="Plus/4 scripted product smoke")
    parser.add_argument("--name", required=True)
    parser.add_argument("--vice", required=True)
    parser.add_argument("--boot-d64", required=True, type=Path)
    parser.add_argument("--save-d64", type=Path)
    parser.add_argument("--save10-d64", type=Path)
    parser.add_argument("--main-vs", required=True, type=Path)
    parser.add_argument("--pass-symbol", required=True)
    parser.add_argument("--fail-symbol")
    parser.add_argument("--start-symbol")
    parser.add_argument("--native-start", action="store_true")
    parser.add_argument("--resume-symbol")
    parser.add_argument("--limitcycles", type=int, default=0)
    parser.add_argument("--drive8-type", default="1541")
    parser.add_argument("--autostart-only-drive8", action="store_true")
    parser.add_argument("--drive9-type", default="1541")
    parser.add_argument("--drive10-type", default="1541")
    parser.add_argument("--enable-drive9-bus", action="store_true")
    parser.add_argument("--attach8-at-start-d64", type=Path)
    parser.add_argument("--attach-delay", type=float, default=0.5)
    parser.add_argument("--reset8-after-attach", action="store_true")
    parser.add_argument("--swap-symbol")
    parser.add_argument("--swap-attach8-d64", type=Path)
    parser.add_argument("--swap-attach-after-hits", type=int, default=1)
    parser.add_argument("--swap2-symbol")
    parser.add_argument("--swap2-attach8-d64", type=Path)
    parser.add_argument("--fail-on-extra-swap", action="store_true")
    parser.add_argument("--require-hit-symbol")
    parser.add_argument("--until-pass", action="store_true")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6510)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--retry-timeouts", type=int, default=2)
    parser.add_argument("--connect-timeout", type=float, default=12.0)
    parser.add_argument("--connect-retry-delay", type=float, default=0.1)
    parser.add_argument("--startup-delay", type=float, default=0.0)
    parser.add_argument("--socket-timeout", type=float, default=0.5)
    parser.add_argument("--pass-on-script-exhausted", action="store_true")
    parser.add_argument("--screen-base", type=lambda value: int(value, 0), default=0x0c00)
    parser.add_argument("--screen-cols", type=int, default=40)
    parser.add_argument("--expect-screen-symbol", action="append", default=[])
    parser.add_argument("--expect-byte-symbol", action="append", default=[])
    args = parser.parse_args()

    symbols = parse_vs_symbols(args.main_vs)
    args.symbols = symbols
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
    args.resume_addr = None
    if args.resume_symbol:
        args.resume_addr = symbols.get(args.resume_symbol)
        if not args.resume_addr:
            print(f"FAIL: missing symbol {args.resume_symbol} in {args.main_vs}")
            return 2
        args.resume_addr = normalize_addr(args.resume_addr)
    args.key_index_addr = (
        symbols.get(".plus4_test_key_index")
        or symbols.get(".c64_test_input_idx")
        or symbols.get(".c128_test_input_idx")
    )
    args.key_script_addr = (
        symbols.get(".plus4_test_key_script")
        or symbols.get(".c64_test_input_script")
        or symbols.get(".c128_test_input_script")
    )
    args.expect_screen = []
    for value in args.expect_screen_symbol:
        match = SCREEN_EXPECT_RE.match(value)
        if not match:
            print(f"FAIL: invalid --expect-screen-symbol {value!r}; expected SYMBOL:ROW:COL")
            return 2
        symbol, row, col = match.groups()
        if symbol not in symbols:
            print(f"FAIL: missing symbol {symbol} in {args.main_vs}")
            return 2
        args.expect_screen.append((symbol, int(row), int(col)))
    args.expect_bytes = []
    for value in args.expect_byte_symbol:
        match = BYTE_EXPECT_RE.match(value)
        if not match:
            print(f"FAIL: invalid --expect-byte-symbol {value!r}; expected SYMBOL=VALUE")
            return 2
        symbol, expected_text = match.groups()
        if symbol not in symbols:
            print(f"FAIL: missing symbol {symbol} in {args.main_vs}")
            return 2
        args.expect_bytes.append((symbol, int(expected_text, 0)))
    args.swap_addr = None
    if args.swap_symbol:
        args.swap_addr = symbols.get(args.swap_symbol)
        if not args.swap_addr:
            print(f"FAIL: missing symbol {args.swap_symbol} in {args.main_vs}")
            return 2
        if not args.swap_attach8_d64:
            print("FAIL: --swap-symbol requires --swap-attach8-d64")
            return 2
        args.swap_addr = normalize_addr(args.swap_addr)
    args.swap2_addr = None
    if args.swap2_symbol:
        args.swap2_addr = symbols.get(args.swap2_symbol)
        if not args.swap2_addr:
            print(f"FAIL: missing symbol {args.swap2_symbol} in {args.main_vs}")
            return 2
        if not args.swap2_attach8_d64:
            print("FAIL: --swap2-symbol requires --swap2-attach8-d64")
            return 2
        args.swap2_addr = normalize_addr(args.swap2_addr)
    args.require_hit_addr = None
    if args.require_hit_symbol:
        args.require_hit_addr = symbols.get(args.require_hit_symbol)
        if not args.require_hit_addr:
            print(f"FAIL: missing symbol {args.require_hit_symbol} in {args.main_vs}")
            return 2
        args.require_hit_addr = normalize_addr(args.require_hit_addr)

    dump_ranges: list[tuple[str, str]] = []
    dump_symbols = (
        ".load_result",
        ".save_io_error",
        ".save_magic_buf",
        ".load_save_version",
        ".save_device",
        ".save_cksum_lo",
        ".save_cksum_hi",
        ".zp_temp0",
        ".zp_temp1",
        ".plus4_test_file_cksum_lo",
        ".plus4_test_file_cksum_hi",
        ".plus4_test_read_count_lo",
        ".plus4_test_read_count_hi",
        ".disk_error_phase",
        ".disk_error_readst",
        ".disk_error_dos0",
        ".disk_error_dos1",
        ".disk_error_actual",
        ".disk_error_expect",
        ".disk_error_index",
        ".disk_diag_phase",
        ".disk_diag_readst",
        ".disk_diag_cmd_status0",
        ".disk_diag_cmd_status1",
        ".disk_diag_carry",
        ".disk_diag_index",
        ".disk_diag_byte",
        ".disk_status",
        ".disk_setup_done",
        ".disk_ui_result",
        ".plus4_test_key_index",
        ".plus4_test_key_script",
        ".c64_test_input_idx",
        ".c64_test_input_script",
        ".c128_test_input_idx",
        ".c128_test_input_script",
        ".plus4_test_single_drive_stage",
        ".c128_media_state",
        ".c128_modal_slot_state",
        ".c128_runtime_load_stage",
        ".c128_runtime_load_bank",
        ".c128_runtime_load_result_a",
        ".c128_runtime_load_readst",
        ".program_device",
        ".save_device",
        ".disk_prompt_device",
    )
    for symbol in dump_symbols:
        addr = symbols.get(symbol)
        if addr:
            start = int(normalize_addr(addr), 16)
            length = 8 if symbol == ".save_magic_buf" else 1
            dump_ranges.append((normalize_addr(start), normalize_addr(start + length - 1)))

    result, dumps = run_vice(args, normalize_addr(pass_addr), normalize_addr(fail_addr) if fail_addr else None, dump_ranges)
    if not result.passed and (
        monitor_text_has_pc(result.last_status, pass_addr)
        or any(monitor_text_has_pc(dump, pass_addr) for dump in dumps)
    ):
        result = MonitorTestResult(True, "target PC reached", result.last_status)
    retries_left = args.retry_timeouts
    while retries_left > 0 and not result.passed and result.reason.startswith("timeout"):
        result, dumps = run_vice(args, normalize_addr(pass_addr), normalize_addr(fail_addr) if fail_addr else None, dump_ranges)
        if not result.passed and (
            monitor_text_has_pc(result.last_status, pass_addr)
            or any(monitor_text_has_pc(dump, pass_addr) for dump in dumps)
        ):
            result = MonitorTestResult(True, "target PC reached", result.last_status)
        retries_left -= 1
    if not result.passed and result.reason.startswith("timeout"):
        if any(monitor_text_has_pc(dump, pass_addr) for dump in dumps):
            result = MonitorTestResult(True, "target PC reached after timeout", result.last_status)
        elif args.pass_on_script_exhausted and dumps_show_script_exhausted(args, dumps):
            result = MonitorTestResult(True, "script exhausted at next input wait", result.last_status)
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
