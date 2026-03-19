#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
TESTS_DIR = SCRIPT_DIR / "tests"
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))

from harness128 import (
    build_arg_parser,
    build_connector,
    build_vice_command,
    create_ready_snapshot,
    run_test_via_moncommands,
    symbols_need_moncommands,
    terminate_vice,
)
from vice_connector import extract_test_symbols, run_test_case

REPO_ROOT = SCRIPT_DIR.parent.parent
KICKASS_JAR = REPO_ROOT / "tools" / "kickass" / "KickAss.jar"
IMPORT_RE = re.compile(r'^\s*#import\s+"([^"]+)"')


@dataclass(frozen=True)
class TestCase:
    name: str
    source: Path
    timeout: float
    limitcycles: int | None = None
    force_moncommands: bool = False
    break_on_fail: bool = True
    cold_ready: bool = True
    snapshot_ready: bool = True


BATCH_TESTS: dict[str, TestCase] = {
    "minimal128": TestCase("minimal128", SCRIPT_DIR / "tests" / "test_minimal128.s", 5.0),
    "config128": TestCase("config128", SCRIPT_DIR / "tests" / "test_config128.s", 5.0),
    "memory128": TestCase("memory128", SCRIPT_DIR / "tests" / "test_memory128.s", 5.0, 20000000, True, False, True, True),
    "input128": TestCase("input128", SCRIPT_DIR / "tests" / "test_input128.s", 5.0, 20000000, True),
    "db128": TestCase("db128", SCRIPT_DIR / "tests" / "test_db128.s", 5.0, 20000000, True),
    "msg_prompt128": TestCase("msg_prompt128", SCRIPT_DIR / "tests" / "test_msg_prompt128.s", 5.0, 120000000, True, False, True, True),
    "main_loop128": TestCase("main_loop128", SCRIPT_DIR / "tests" / "test_main_loop128.s", 5.0),
    "status_coherence128": TestCase("status_coherence128", SCRIPT_DIR / "tests" / "test_status_coherence128.s", 5.0),
    "tier128": TestCase("tier128", SCRIPT_DIR / "tests" / "test_tier128.s", 5.0, 20000000, True, False, True, True),
    "dungeon128": TestCase("dungeon128", SCRIPT_DIR / "tests" / "test_dungeon128.s", 5.0),
    "vdc_attr128": TestCase("vdc_attr128", SCRIPT_DIR / "tests" / "test_vdc_attr128.s", 5.0),
    "monster128": TestCase("monster128", SCRIPT_DIR / "tests" / "test_monster128.s", 5.0, 20000000, True),
    "soak128": TestCase("soak128", SCRIPT_DIR / "tests" / "test_soak128.s", 5.0, 300000000, True),
}

DEFAULT_BATCH_TESTS = [
    "minimal128",
    "config128",
    "memory128",
    "input128",
    "db128",
    "status_coherence128",
    "vdc_attr128",
    "msg_prompt128",
    "tier128",
    "dungeon128",
    "main_loop128",
    "monster128",
    "soak128",
]


def assemble_if_stale(test_case: TestCase, verbose: bool = False) -> tuple[Path, Path]:
    source = test_case.source
    prg_path = source.with_suffix(".prg")
    vs_path = source.with_suffix(".vs")
    source_stamp = compute_source_stamp(source)
    if (
        prg_path.exists()
        and vs_path.exists()
        and prg_path.stat().st_mtime >= source_stamp
        and vs_path.stat().st_mtime >= source_stamp
    ):
        return prg_path, vs_path

    command = [
        "java",
        "-jar",
        str(KICKASS_JAR),
        str(source),
        "-libdir",
        str(REPO_ROOT / "commodore" / "c64"),
        "-define",
        "C128",
        "-define",
        'OVL_OUT="out"',
        "-vicesymbols",
        "-o",
        str(prg_path),
    ]
    result = subprocess.run(command, cwd=SCRIPT_DIR, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"assembly failed for {test_case.name}:\n{result.stderr or result.stdout}")
    if verbose and result.stdout.strip():
        print(result.stdout.strip())
    return prg_path, vs_path


def compute_source_stamp(source: Path, seen: set[Path] | None = None) -> float:
    if seen is None:
        seen = set()
    source = source.resolve()
    if source in seen:
        return 0.0
    seen.add(source)

    stamp = source.stat().st_mtime
    for line in source.read_text(encoding="utf-8").splitlines():
        match = IMPORT_RE.match(line)
        if not match:
            continue
        imported_path = (source.parent / match.group(1)).resolve()
        if imported_path.exists():
            stamp = max(stamp, compute_source_stamp(imported_path, seen))
    return stamp


def run_one_test(
    connector,
    base_args: argparse.Namespace,
    *,
    force_moncommands: bool,
    break_on_fail: bool,
    limitcycles: int | None,
    test_name: str,
    prg_path: Path,
    vs_path: Path,
    timeout: float,
    snapshot_path: Path | None,
    verbose: bool,
) -> tuple[bool, str, float]:
    symbols = extract_test_symbols(vs_path)
    start_time = time.perf_counter()
    if force_moncommands or symbols_need_moncommands(symbols):
        mon_args = argparse.Namespace(**vars(base_args))
        mon_args.name = test_name
        mon_args.timeout = timeout
        exit_code = run_test_via_moncommands(
            mon_args,
            prg_path=prg_path,
            symbols=symbols,
            snapshot_path=snapshot_path,
            break_on_fail=break_on_fail,
            limitcycles=limitcycles,
        )
        duration = time.perf_counter() - start_time
        return exit_code == 0, "" if exit_code == 0 else "moncommands execution failed", duration
    if snapshot_path is not None and connector is not None:
        connector.undump_snapshot(snapshot_path, debug=verbose)
    result = run_test_case(
        connector,
        prg_path=prg_path,
        start_addr=symbols.start_addr,
        pass_addr=symbols.pass_addr,
        fail_addr=symbols.fail_addr,
        timeout=timeout,
        reset_environment=(snapshot_path is None),
        debug=verbose,
    )
    duration = time.perf_counter() - start_time
    return result.passed, result.reason, duration


def run_cold_mode(base_args: argparse.Namespace, tests: list[TestCase]) -> list[tuple[str, bool, str, float]]:
    results: list[tuple[str, bool, str, float]] = []
    for test_case in tests:
        if not test_case.cold_ready:
            results.append((test_case.name, False, "not cold-batch-ready", 0.0))
            continue
        prg_path, vs_path = assemble_if_stale(test_case, verbose=base_args.verbose)
        symbols = extract_test_symbols(vs_path)
        if symbols_need_moncommands(symbols):
                passed, reason, duration = run_one_test(
                    None,
                    base_args,
                    force_moncommands=test_case.force_moncommands,
                    break_on_fail=test_case.break_on_fail,
                    limitcycles=test_case.limitcycles,
                    test_name=test_case.name,
                    prg_path=prg_path,
                    vs_path=vs_path,
                    timeout=test_case.timeout,
                    snapshot_path=None,
                    verbose=base_args.verbose,
                )
        else:
            vice_process = subprocess.Popen(
                build_vice_command(base_args),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            connector = build_connector(base_args)
            try:
                connector.connect(
                    retries=max(1, int(base_args.connect_timeout / base_args.connect_retry_delay)),
                    retry_delay=base_args.connect_retry_delay,
                    debug=base_args.verbose,
                )
                passed, reason, duration = run_one_test(
                    connector,
                    base_args,
                    force_moncommands=test_case.force_moncommands,
                    break_on_fail=test_case.break_on_fail,
                    limitcycles=test_case.limitcycles,
                    test_name=test_case.name,
                    prg_path=prg_path,
                    vs_path=vs_path,
                    timeout=test_case.timeout,
                    snapshot_path=None,
                    verbose=base_args.verbose,
                )
            finally:
                connector.close()
                terminate_vice(vice_process)
        results.append((test_case.name, passed, reason, duration))
    return results


def run_snapshot_mode(base_args: argparse.Namespace, tests: list[TestCase], snapshot_path: Path) -> list[tuple[str, bool, str, float]]:
    if not snapshot_path.exists():
        create_ready_snapshot(base_args, snapshot_path)

    vice_process = subprocess.Popen(
        build_vice_command(base_args),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    connector = build_connector(base_args)
    try:
        connector.connect(
            retries=max(1, int(base_args.connect_timeout / base_args.connect_retry_delay)),
            retry_delay=base_args.connect_retry_delay,
            debug=base_args.verbose,
        )
        results: list[tuple[str, bool, str, float]] = []
        for test_case in tests:
            if not test_case.snapshot_ready:
                results.append((test_case.name, False, "not snapshot-ready", 0.0))
                continue
            prg_path, vs_path = assemble_if_stale(test_case, verbose=base_args.verbose)
            passed, reason, duration = run_one_test(
                connector,
                base_args,
                force_moncommands=test_case.force_moncommands,
                break_on_fail=test_case.break_on_fail,
                limitcycles=test_case.limitcycles,
                test_name=test_case.name,
                prg_path=prg_path,
                vs_path=vs_path,
                timeout=test_case.timeout,
                snapshot_path=snapshot_path,
                verbose=base_args.verbose,
            )
            results.append((test_case.name, passed, reason, duration))
        return results
    finally:
        connector.close()
        terminate_vice(vice_process)


def print_results(mode: str, results: list[tuple[str, bool, str, float]]) -> int:
    failures = 0
    total = 0.0
    print(f"== {mode} ==")
    for name, passed, reason, duration in results:
        total += duration
        if passed:
            print(f"{name}\tPASS\t{duration:.3f}s")
        else:
            failures += 1
            print(f"{name}\tFAIL\t{duration:.3f}s\t{reason}")
    print(f"TOTAL\t{total:.3f}s")
    return failures


def build_batch_parser() -> argparse.ArgumentParser:
    parser = build_arg_parser()
    parser.description = "C128 Python batch harness (Gate C.4 slice)"
    parser.add_argument("--mode", choices=["cold", "snapshot", "compare"], default="compare")
    parser.add_argument("--snapshot-path", default=str(SCRIPT_DIR / "out" / "ready.vsf"))
    parser.add_argument(
        "--tests",
        default=",".join(DEFAULT_BATCH_TESTS),
        help="Comma-separated test ids; defaults to the stable snapshot-friendly Gate C.4 batch set",
    )
    return parser


def main() -> int:
    parser = build_batch_parser()
    args = parser.parse_args()
    selected_tests: list[TestCase] = []
    for test_name in [item.strip() for item in args.tests.split(",") if item.strip()]:
        if test_name not in BATCH_TESTS:
            parser.error(f"unknown test id: {test_name}")
        selected_tests.append(BATCH_TESTS[test_name])

    snapshot_path = Path(args.snapshot_path).resolve()
    failures = 0

    if args.mode in {"cold", "compare"}:
        failures += print_results("cold", run_cold_mode(args, selected_tests))
    if args.mode in {"snapshot", "compare"}:
        failures += print_results("snapshot", run_snapshot_mode(args, selected_tests, snapshot_path))

    return 0 if failures == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
