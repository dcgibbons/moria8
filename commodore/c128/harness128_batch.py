#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
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
    "item_desc128": TestCase("item_desc128", SCRIPT_DIR / "tests" / "test_item_desc128.s", 5.0),
    "vdc_scroll_delta128": TestCase("vdc_scroll_delta128", SCRIPT_DIR / "tests" / "test_vdc_scroll_delta128.s", 5.0, 30000000, True),
    "monster128": TestCase("monster128", SCRIPT_DIR / "tests" / "test_monster128.s", 5.0, 20000000, True),
    "detect_monsters128": TestCase("detect_monsters128", SCRIPT_DIR / "tests" / "test_detect_monsters128.s", 5.0, 20000000, True),
    "detect_evil128": TestCase("detect_evil128", SCRIPT_DIR / "tests" / "test_detect_evil128.s", 5.0, 20000000, True),
    "cure_light_wounds128": TestCase("cure_light_wounds128", SCRIPT_DIR / "tests" / "test_cure_light_wounds128.s", 5.0, 20000000, True),
    "cure_poison128": TestCase("cure_poison128", SCRIPT_DIR / "tests" / "test_cure_poison128.s", 5.0, 20000000, True),
    "cure_light_wounds_prayer128": TestCase("cure_light_wounds_prayer128", SCRIPT_DIR / "tests" / "test_cure_light_wounds_prayer128.s", 5.0, 20000000, True),
    "bless_prayer128": TestCase("bless_prayer128", SCRIPT_DIR / "tests" / "test_bless_prayer128.s", 5.0, 20000000, True),
    "remove_fear_prayer128": TestCase("remove_fear_prayer128", SCRIPT_DIR / "tests" / "test_remove_fear_prayer128.s", 5.0, 20000000, True),
    "call_light_prayer128": TestCase("call_light_prayer128", SCRIPT_DIR / "tests" / "test_call_light_prayer128.s", 5.0, 20000000, True),
    "find_traps_prayer128": TestCase("find_traps_prayer128", SCRIPT_DIR / "tests" / "test_find_traps_prayer128.s", 5.0, 20000000, True),
    "detect_doors_stairs_prayer128": TestCase("detect_doors_stairs_prayer128", SCRIPT_DIR / "tests" / "test_detect_doors_stairs_prayer128.s", 5.0, 20000000, True),
    "slow_poison_prayer128": TestCase("slow_poison_prayer128", SCRIPT_DIR / "tests" / "test_slow_poison_prayer128.s", 5.0, 20000000, True),
    "blind_creature_prayer128": TestCase("blind_creature_prayer128", SCRIPT_DIR / "tests" / "test_blind_creature_prayer128.s", 5.0, 20000000, True),
    "portal_prayer128": TestCase("portal_prayer128", SCRIPT_DIR / "tests" / "test_portal_prayer128.s", 5.0, 20000000, True),
    "cure_medium_wounds_prayer128": TestCase("cure_medium_wounds_prayer128", SCRIPT_DIR / "tests" / "test_cure_medium_wounds_prayer128.s", 5.0, 20000000, True),
    "cure_serious_wounds_prayer128": TestCase("cure_serious_wounds_prayer128", SCRIPT_DIR / "tests" / "test_cure_serious_wounds_prayer128.s", 5.0, 20000000, True),
    "sense_invisible_prayer128": TestCase("sense_invisible_prayer128", SCRIPT_DIR / "tests" / "test_sense_invisible_prayer128.s", 5.0, 20000000, True),
    "protection_from_evil_prayer128": TestCase("protection_from_evil_prayer128", SCRIPT_DIR / "tests" / "test_protection_from_evil_prayer128.s", 5.0, 20000000, True),
    "earthquake_prayer128": TestCase("earthquake_prayer128", SCRIPT_DIR / "tests" / "test_earthquake_prayer128.s", 5.0, 20000000, True),
    "sense_surroundings_prayer128": TestCase("sense_surroundings_prayer128", SCRIPT_DIR / "tests" / "test_sense_surroundings_prayer128.s", 5.0, 20000000, True),
    "cure_critical_wounds_prayer128": TestCase("cure_critical_wounds_prayer128", SCRIPT_DIR / "tests" / "test_cure_critical_wounds_prayer128.s", 5.0, 20000000, True),
    "turn_undead_prayer128": TestCase("turn_undead_prayer128", SCRIPT_DIR / "tests" / "test_turn_undead_prayer128.s", 5.0, 20000000, True),
    "prayer_prayer128": TestCase("prayer_prayer128", SCRIPT_DIR / "tests" / "test_prayer_prayer128.s", 5.0, 20000000, True),
    "dispel_undead_prayer128": TestCase("dispel_undead_prayer128", SCRIPT_DIR / "tests" / "test_dispel_undead_prayer128.s", 5.0, 20000000, True),
    "dispel_evil_prayer128": TestCase("dispel_evil_prayer128", SCRIPT_DIR / "tests" / "test_dispel_evil_prayer128.s", 5.0, 20000000, True),
    "glyph_of_warding_prayer128": TestCase("glyph_of_warding_prayer128", SCRIPT_DIR / "tests" / "test_glyph_of_warding_prayer128.s", 5.0, 20000000, True),
    "holy_word_prayer128": TestCase("holy_word_prayer128", SCRIPT_DIR / "tests" / "test_holy_word_prayer128.s", 5.0, 20000000, True),
    "heal_prayer128": TestCase("heal_prayer128", SCRIPT_DIR / "tests" / "test_heal_prayer128.s", 5.0, 20000000, True),
    "chant_prayer128": TestCase("chant_prayer128", SCRIPT_DIR / "tests" / "test_chant_prayer128.s", 5.0, 20000000, True),
    "sanctuary_prayer128": TestCase("sanctuary_prayer128", SCRIPT_DIR / "tests" / "test_sanctuary_prayer128.s", 5.0, 20000000, True),
    "neutralize_poison_prayer128": TestCase("neutralize_poison_prayer128", SCRIPT_DIR / "tests" / "test_neutralize_poison_prayer128.s", 5.0, 20000000, True),
    "create_food_prayer128": TestCase("create_food_prayer128", SCRIPT_DIR / "tests" / "test_create_food_prayer128.s", 5.0, 20000000, True),
    "remove_curse_prayer128": TestCase("remove_curse_prayer128", SCRIPT_DIR / "tests" / "test_remove_curse_prayer128.s", 5.0, 20000000, True),
    "resist_heat_cold_prayer128": TestCase("resist_heat_cold_prayer128", SCRIPT_DIR / "tests" / "test_resist_heat_cold_prayer128.s", 5.0, 20000000, True),
    "orb_of_draining_prayer128": TestCase("orb_of_draining_prayer128", SCRIPT_DIR / "tests" / "test_orb_of_draining_prayer128.s", 5.0, 20000000, True),
    "find_hidden_traps_doors128": TestCase("find_hidden_traps_doors128", SCRIPT_DIR / "tests" / "test_find_hidden_traps_doors128.s", 5.0, 20000000, True),
    "stinking_cloud128": TestCase("stinking_cloud128", SCRIPT_DIR / "tests" / "test_stinking_cloud128.s", 5.0, 20000000, True),
    "frost_ball128": TestCase("frost_ball128", SCRIPT_DIR / "tests" / "test_frost_ball128.s", 5.0, 20000000, True),
    "teleport_other128": TestCase("teleport_other128", SCRIPT_DIR / "tests" / "test_teleport_other128.s", 5.0, 20000000, True),
    "haste_self128": TestCase("haste_self128", SCRIPT_DIR / "tests" / "test_haste_self128.s", 5.0, 20000000, True),
    "fire_ball128": TestCase("fire_ball128", SCRIPT_DIR / "tests" / "test_fire_ball128.s", 5.0, 20000000, True),
    "word_of_destruction128": TestCase("word_of_destruction128", SCRIPT_DIR / "tests" / "test_word_of_destruction128.s", 5.0, 20000000, True),
    "genocide128": TestCase("genocide128", SCRIPT_DIR / "tests" / "test_genocide128.s", 5.0, 20000000, True),
    "confusion128": TestCase("confusion128", SCRIPT_DIR / "tests" / "test_confusion128.s", 5.0, 20000000, True),
    "lightning_bolt128": TestCase("lightning_bolt128", SCRIPT_DIR / "tests" / "test_lightning_bolt128.s", 5.0, 20000000, True),
    "frost_bolt128": TestCase("frost_bolt128", SCRIPT_DIR / "tests" / "test_frost_bolt128.s", 5.0, 20000000, True),
    "turn_stone_to_mud128": TestCase("turn_stone_to_mud128", SCRIPT_DIR / "tests" / "test_turn_stone_to_mud128.s", 5.0, 20000000, True),
    "create_food128": TestCase("create_food128", SCRIPT_DIR / "tests" / "test_create_food128.s", 5.0, 20000000, True),
    "recharge_item_i128": TestCase("recharge_item_i128", SCRIPT_DIR / "tests" / "test_recharge_item_i128.s", 5.0, 20000000, True),
    "recharge_item_ii128": TestCase("recharge_item_ii128", SCRIPT_DIR / "tests" / "test_recharge_item_ii128.s", 5.0, 20000000, True),
    "trap_door_destruction128": TestCase("trap_door_destruction128", SCRIPT_DIR / "tests" / "test_trap_door_destruction128.s", 5.0, 20000000, True),
    "sleep_i128": TestCase("sleep_i128", SCRIPT_DIR / "tests" / "test_sleep_i128.s", 5.0, 20000000, True),
    "sleep_ii128": TestCase("sleep_ii128", SCRIPT_DIR / "tests" / "test_sleep_ii128.s", 5.0, 20000000, True),
    "sleep_iii128": TestCase("sleep_iii128", SCRIPT_DIR / "tests" / "test_sleep_iii128.s", 5.0, 20000000, True),
    "fire_bolt128": TestCase("fire_bolt128", SCRIPT_DIR / "tests" / "test_fire_bolt128.s", 5.0, 20000000, True),
    "slow_monster128": TestCase("slow_monster128", SCRIPT_DIR / "tests" / "test_slow_monster128.s", 5.0, 20000000, True),
    "polymorph_other128": TestCase("polymorph_other128", SCRIPT_DIR / "tests" / "test_polymorph_other128.s", 5.0, 20000000, True),
    "identify128": TestCase("identify128", SCRIPT_DIR / "tests" / "test_identify128.s", 5.0, 20000000, True),
    "teleport_self128": TestCase("teleport_self128", SCRIPT_DIR / "tests" / "test_teleport_self128.s", 5.0, 20000000, True),
    "remove_curse128": TestCase("remove_curse128", SCRIPT_DIR / "tests" / "test_remove_curse128.s", 5.0, 20000000, True),
    "phase_door128": TestCase("phase_door128", SCRIPT_DIR / "tests" / "test_phase_door128.s", 5.0, 20000000, True),
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
    "item_desc128",
    "vdc_scroll_delta128",
    "msg_prompt128",
    "tier128",
    "dungeon128",
    "main_loop128",
    "monster128",
    "detect_monsters128",
    "detect_evil128",
    "cure_light_wounds128",
    "cure_poison128",
    "cure_light_wounds_prayer128",
    "bless_prayer128",
    "remove_fear_prayer128",
    "call_light_prayer128",
    "find_traps_prayer128",
    "detect_doors_stairs_prayer128",
    "slow_poison_prayer128",
    "blind_creature_prayer128",
    "portal_prayer128",
    "cure_medium_wounds_prayer128",
    "cure_serious_wounds_prayer128",
    "sense_invisible_prayer128",
    "protection_from_evil_prayer128",
    "earthquake_prayer128",
    "sense_surroundings_prayer128",
    "cure_critical_wounds_prayer128",
    "turn_undead_prayer128",
    "prayer_prayer128",
    "dispel_undead_prayer128",
    "dispel_evil_prayer128",
    "glyph_of_warding_prayer128",
    "holy_word_prayer128",
    "heal_prayer128",
    "chant_prayer128",
    "sanctuary_prayer128",
    "neutralize_poison_prayer128",
    "create_food_prayer128",
    "remove_curse_prayer128",
    "resist_heat_cold_prayer128",
    "orb_of_draining_prayer128",
    "find_hidden_traps_doors128",
    "stinking_cloud128",
    "frost_ball128",
    "teleport_other128",
    "haste_self128",
    "fire_ball128",
    "word_of_destruction128",
    "genocide128",
    "confusion128",
    "lightning_bolt128",
    "frost_bolt128",
    "turn_stone_to_mud128",
    "create_food128",
    "recharge_item_i128",
    "recharge_item_ii128",
    "trap_door_destruction128",
    "sleep_i128",
    "sleep_ii128",
    "sleep_iii128",
    "fire_bolt128",
    "slow_monster128",
    "polymorph_other128",
    "identify128",
    "teleport_self128",
    "remove_curse128",
    "phase_door128",
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
    reset_environment: bool | None = None,
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
        reset_environment=(snapshot_path is None) if reset_environment is None else reset_environment,
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

    results: list[tuple[str, bool, str, float]] = []
    for test_case in tests:
        if not test_case.snapshot_ready:
            results.append((test_case.name, False, "not snapshot-ready", 0.0))
            continue

        prg_path, vs_path = assemble_if_stale(test_case, verbose=base_args.verbose)
        symbols = extract_test_symbols(vs_path)
        if test_case.force_moncommands or symbols_need_moncommands(symbols):
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
                snapshot_path=snapshot_path,
                reset_environment=False,
                verbose=base_args.verbose,
            )
            results.append((test_case.name, passed, reason, duration))
            continue

        with tempfile.TemporaryDirectory(prefix="harness128_snapshot_") as temp_dir:
            mon_file = Path(temp_dir) / "restore.mon"
            mon_file.write_text(f'undump "{snapshot_path.resolve()}"\n', encoding="utf-8")
            vice_command = build_vice_command(base_args)
            vice_command.extend(["-moncommands", str(mon_file)])
            vice_process = subprocess.Popen(
                vice_command,
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
                # Startup `undump` via -moncommands can still be settling when the
                # remote monitor first accepts a socket connection, but some VICE
                # runs go straight to command-ready without a second prompt burst.
                try:
                    connector.read_until_prompt(deadline=time.monotonic() + base_args.connect_timeout)
                except TimeoutError:
                    pass
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
                    reset_environment=True,
                    verbose=base_args.verbose,
                )
            finally:
                connector.close()
                terminate_vice(vice_process)
        results.append((test_case.name, passed, reason, duration))
    return results


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
