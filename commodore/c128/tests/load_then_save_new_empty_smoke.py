#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
import time
import re
from pathlib import Path

from vice_connector import MonitorTestResult, VICEConnector, normalize_addr, parse_vs_symbols

BYTE_DUMP_RE = re.compile(r"C:([0-9A-Fa-f]{4})\s+([0-9A-Fa-f]{2})")


def build_vice_command(args: argparse.Namespace) -> list[str]:
    return [
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
        "-80col",
        "-drive8truedrive",
        "-drive8type",
        str(args.drive8_type),
        "-attach8rw",
        "-8",
        str(args.boot_d64),
        "+busdevice9",
        "-drive9type",
        "0",
        "-autostart",
        str(args.boot_d64),
    ]


def attach_drive8(connector: VICEConnector, disk_path: Path, delay: float, reset: bool = False) -> None:
    response = connector.send_command("detach 8")
    if "Cannot" in response or "Error" in response or "Failed" in response:
        raise RuntimeError(f"failed to detach drive 8 before image swap: {response.strip()}")
    response = connector.send_command('resourceset "AttachDevice8d0Readonly" "0"')
    if "Cannot" in response or "Error" in response or "Failed" in response:
        raise RuntimeError(f"failed to mark drive 8 attachment writable: {response.strip()}")
    response = connector.send_command(f'attach "{disk_path.resolve()}" 8')
    if "Cannot" in response or "Error" in response or "Failed" in response:
        raise RuntimeError(f"failed to attach drive 8 image {disk_path}: {response.strip()}")
    if reset:
        response = connector.send_command("reset 8")
        if "Cannot" in response or "Error" in response or "Failed" in response:
            raise RuntimeError(f"failed to reset drive 8 after image swap: {response.strip()}")
    time.sleep(delay)


def wait_for_break(
    connector: VICEConnector,
    *,
    pass_addr: str,
    fail_addr: str | None,
    timeout: float,
) -> MonitorTestResult:
    result = connector.wait_for_stop(pass_addr=pass_addr, fail_addr=fail_addr, timeout=timeout)
    if result.passed:
        return result
    if fail_addr and f".C:{normalize_addr(fail_addr)}" in result.last_status.upper():
        return result
    return result


def status_has_pc(status: str, addr: str) -> bool:
    norm = normalize_addr(addr)
    upper = status.upper()
    return any(marker in upper for marker in (
        f"C:${norm}",
        f"C:{norm}",
        f".C:{norm}",
    ))


def run_until_symbol(connector: VICEConnector, addr: str, timeout: float) -> MonitorTestResult:
    try:
        status = connector.run_until(addr, timeout=timeout)
    except TimeoutError:
        return MonitorTestResult(False, f"timeout after {timeout}s", "")
    except ConnectionError as exc:
        return MonitorTestResult(False, str(exc), "")
    if status_has_pc(status, addr):
        return MonitorTestResult(True, "", status)
    if "JAM" in status.upper() or "INVALID OPCODE" in status.upper():
        return MonitorTestResult(False, "CPU JAM", status)
    return MonitorTestResult(False, "stopped without reaching target", status)


def wait_for_gate(connector: VICEConnector, addr: str, timeout: float) -> MonitorTestResult:
    result = connector.wait_for_stop(pass_addr=addr, timeout=timeout)
    if result.passed:
        return result
    try:
        status = connector.send_command("r") + connector.send_command("bt")
    except Exception:
        return result
    if status_has_pc(status, addr):
        return MonitorTestResult(True, "PC reached gate loop", status)
    if "JAM" in status.upper() or "INVALID OPCODE" in status.upper():
        return MonitorTestResult(False, "CPU JAM", status)
    return MonitorTestResult(False, result.reason, status)


def read_monitor_byte(connector: VICEConnector, addr: int | str) -> int | None:
    response = connector.send_command(f"m {normalize_addr(addr)} {normalize_addr(addr)}")
    for line in response.splitlines():
        if "C:" not in line:
            continue
        match = BYTE_DUMP_RE.search(line)
        if match:
            return int(match.group(2), 16)
    return None


def read_symbol_byte(connector: VICEConnector, symbols: dict[str, str], name: str) -> int | None:
    addr = symbols.get(name)
    if addr is None:
        return None
    return read_monitor_byte(connector, int(addr, 16))


def dump_context(connector: VICEConnector, args: argparse.Namespace) -> str:
    chunks: list[str] = []
    for command in (
        "bt",
        f"m {normalize_addr(args.screen_base)} {normalize_addr(args.screen_base + args.screen_cols * 25 - 1)}",
    ):
        try:
            chunks.append(connector.send_command(command))
        except Exception as exc:
            chunks.append(f"{command}: {exc}")
    symbols = getattr(args, "symbols", {})
    state_names = (
        ".disk_mode",
        ".disk_setup_done",
        ".program_device",
        ".save_device",
        ".disk_status",
        ".disk_ui_result",
        ".disk_ui_action",
        ".c128_media_state",
        ".c128_modal_slot_state",
        ".load_result",
        ".c128_test_load_then_save_new_empty_stage",
        ".c128_test_input_idx",
        ".disk_diag_phase",
        ".disk_diag_readst",
        ".disk_diag_cmd_status0",
        ".disk_diag_cmd_status1",
    )
    for name in state_names:
        addr = symbols.get(name)
        if not addr:
            continue
        try:
            chunks.append(f"{name}:\n{connector.send_command(f'm {normalize_addr(addr)} {normalize_addr(addr)}')}")
        except Exception as exc:
            chunks.append(f"{name}: {exc}")
    return "\n".join(chunks)


def phase_failure(
    connector: VICEConnector,
    args: argparse.Namespace,
    phase: str,
    result: MonitorTestResult,
) -> MonitorTestResult:
    reason = result.reason or "stopped unexpectedly"
    return MonitorTestResult(False, f"{phase}: {reason}", result.last_status + dump_context(connector, args))


def require_symbols(symbols: dict[str, str], names: tuple[str, ...], vs_path: Path) -> dict[str, str]:
    resolved: dict[str, str] = {}
    missing: list[str] = []
    for name in names:
        addr = symbols.get(name)
        if addr is None:
            missing.append(name)
        else:
            resolved[name] = normalize_addr(addr)
    if missing:
        raise ValueError(f"missing symbols in {vs_path}: {', '.join(missing)}")
    return resolved


def run(args: argparse.Namespace) -> MonitorTestResult:
    symbols = require_symbols(
        parse_vs_symbols(args.main_vs),
        (
            ".c128_test_single_drive_load_return_wait_for_harness",
            ".c128_test_single_drive_load_return_before_load",
            ".c128_test_single_drive_load_return_loaded",
            ".c128_program_media_error_prompt",
            ".c128_test_load_then_save_new_empty_save",
            ".c128_test_load_then_save_new_empty_save_media_ready",
            ".c128_test_load_then_save_new_empty_after_save_wait",
            ".c128_test_load_then_save_new_empty_restore_program",
            ".c128_test_load_then_save_new_empty_stage",
            ".c128_test_load_then_save_new_empty_fail",
            ".c128_test_load_then_save_new_empty_done",
            ".disk_prompt_game",
        ),
        args.main_vs,
    )
    args.symbols = parse_vs_symbols(args.main_vs)

    process: subprocess.Popen[bytes] | None = None
    connector = VICEConnector(host=args.host, port=args.port, timeout=args.socket_timeout)
    try:
        process = subprocess.Popen(
            build_vice_command(args),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(args.startup_delay)
        connector.connect(
            retries=max(1, int(args.connect_timeout / args.connect_retry_delay)),
            retry_delay=args.connect_retry_delay,
        )

        connector.clear_breakpoints()
        connector.break_at(symbols[".c128_test_single_drive_load_return_wait_for_harness"])
        connector.go()
        result = wait_for_gate(connector, symbols[".c128_test_single_drive_load_return_wait_for_harness"], args.timeout)
        if not result.passed:
            return phase_failure(connector, args, "boot wait", result)

        attach_drive8(connector, args.load_save_d64, args.attach_delay, reset=True)

        connector.clear_breakpoints()
        connector.break_at(symbols[".c128_program_media_error_prompt"])
        connector.break_at(symbols[".c128_test_load_then_save_new_empty_fail"])
        connector.go(symbols[".c128_test_single_drive_load_return_before_load"])
        result = wait_for_break(
            connector,
            pass_addr=symbols[".c128_program_media_error_prompt"],
            fail_addr=symbols[".c128_test_load_then_save_new_empty_fail"],
            timeout=args.timeout,
        )
        if not result.passed:
            return phase_failure(connector, args, "load existing save", result)
        load_result = read_symbol_byte(connector, args.symbols, ".load_result")
        if load_result != 0:
            reason = "unreadable" if load_result is None else f"${load_result:02x}"
            return MonitorTestResult(False, f"load existing save failed: load_result={reason}", dump_context(connector, args))

        attach_drive8(connector, args.program_d64, args.attach_delay, reset=True)

        connector.clear_breakpoints()
        connector.break_at(symbols[".c128_test_load_then_save_new_empty_save_media_ready"])
        connector.break_at(symbols[".c128_test_load_then_save_new_empty_fail"])
        connector.go(symbols[".c128_test_load_then_save_new_empty_save"])
        result = wait_for_break(
            connector,
            pass_addr=symbols[".c128_test_load_then_save_new_empty_save_media_ready"],
            fail_addr=symbols[".c128_test_load_then_save_new_empty_fail"],
            timeout=args.timeout,
        )
        if not result.passed:
            return phase_failure(connector, args, "restore program media before fresh save", result)

        attach_drive8(connector, args.new_save_d64, args.attach_delay, reset=True)

        connector.clear_breakpoints()
        connector.break_at(symbols[".c128_test_load_then_save_new_empty_after_save_wait"])
        connector.break_at(symbols[".c128_test_load_then_save_new_empty_fail"])
        connector.go()
        result = wait_for_break(
            connector,
            pass_addr=symbols[".c128_test_load_then_save_new_empty_after_save_wait"],
            fail_addr=symbols[".c128_test_load_then_save_new_empty_fail"],
            timeout=args.timeout,
        )
        if not result.passed:
            return phase_failure(connector, args, "initialize and save to fresh save disk", result)
        stage = read_symbol_byte(connector, args.symbols, ".c128_test_load_then_save_new_empty_stage")
        if stage != 2:
            reason = "unreadable" if stage is None else f"${stage:02x}"
            return MonitorTestResult(False, f"save did not reach expected stage: stage={reason}", dump_context(connector, args))
        reset_response = connector.send_command("reset 8")
        if "Cannot" in reset_response or "Error" in reset_response or "Failed" in reset_response:
            raise RuntimeError(f"failed to reset drive 8 after save: {reset_response.strip()}")
        time.sleep(args.attach_delay)

        connector.clear_breakpoints()
        connector.break_at(symbols[".c128_test_load_then_save_new_empty_done"])
        connector.break_at(symbols[".c128_test_load_then_save_new_empty_fail"])
        connector.go(symbols[".c128_test_load_then_save_new_empty_restore_program"])
        result = wait_for_break(
            connector,
            pass_addr=symbols[".c128_test_load_then_save_new_empty_done"],
            fail_addr=symbols[".c128_test_load_then_save_new_empty_fail"],
            timeout=args.timeout,
        )
        if not result.passed:
            return phase_failure(connector, args, "done", result)
        return result
    finally:
        connector.close()
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2.0)


def main() -> int:
    parser = argparse.ArgumentParser(description="C128 load existing save, then save to a new empty disk smoke")
    parser.add_argument("--vice", required=True)
    parser.add_argument("--boot-d64", required=True, type=Path)
    parser.add_argument("--load-save-d64", required=True, type=Path)
    parser.add_argument("--new-save-d64", required=True, type=Path)
    parser.add_argument("--program-d64", required=True, type=Path)
    parser.add_argument("--main-vs", required=True, type=Path)
    parser.add_argument("--drive8-type", default="1541")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6510)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--socket-timeout", type=float, default=0.5)
    parser.add_argument("--connect-timeout", type=float, default=12.0)
    parser.add_argument("--connect-retry-delay", type=float, default=0.1)
    parser.add_argument("--startup-delay", type=float, default=0.0)
    parser.add_argument("--attach-delay", type=float, default=5.0)
    parser.add_argument("--screen-base", type=lambda value: int(value, 0), default=0x0400)
    parser.add_argument("--screen-cols", type=int, default=40)
    args = parser.parse_args()

    try:
        result = run(args)
    except Exception as exc:
        print(f"FAIL: {exc}")
        return 2

    if result.passed:
        print("PASS: load_then_save_new_empty_c128")
        return 0
    print(f"FAIL: {result.reason}")
    if result.last_status:
        print(result.last_status)
    return 2


if __name__ == "__main__":
    sys.exit(main())
