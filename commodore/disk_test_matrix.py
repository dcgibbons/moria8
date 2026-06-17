#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


PLATFORMS = ("c64", "c128", "plus4")


@dataclass(frozen=True)
class PlatformCoverage:
    tests: tuple[str, ...]
    strict: bool = False
    note: str = ""

    def filter_names(self, scenario_id: str) -> tuple[str, ...]:
        if self.strict:
            return (scenario_id,)
        return self.tests


@dataclass(frozen=True)
class ScenarioContract:
    media: str
    start: str
    ordered_events: tuple[str, ...]
    event_counts: tuple[str, ...]
    forbidden_events: tuple[str, ...]
    screen_assertions: tuple[str, ...]
    final_proof: tuple[str, ...]


@dataclass(frozen=True)
class Scenario:
    scenario_id: str
    coverage: dict[str, PlatformCoverage]
    contract: ScenarioContract | None = None

    def platform_coverage(self, platform: str) -> PlatformCoverage | None:
        return self.coverage.get(platform)


def legacy(*tests: str, note: str = "") -> PlatformCoverage:
    return PlatformCoverage(tests, strict=False, note=note)


def strict(*tests: str, note: str = "") -> PlatformCoverage:
    return PlatformCoverage(tests, strict=True, note=note)


SCENARIOS: tuple[Scenario, ...] = (
    Scenario(
        "media_drive8_attach_read_write",
        {
            "c64": legacy("disk_swap"),
            "c128": legacy("disk_swap128", "marker_init_d64_smoke"),
            "plus4": legacy("disk_setup_product_plus4"),
        },
    ),
    Scenario(
        "media_drive9_attach_read_write",
        {
            "c64": legacy("disk_setup_product_smoke", "save_write_product_smoke"),
            "c128": legacy("marker_init_d64_smoke", "boot_title_save_write_product_smoke"),
            "plus4": legacy("disk_setup_product_plus4", "save_write_product_plus4"),
        },
    ),
    Scenario(
        "media_drive10_11_device_probe",
        {
            "c64": legacy("disk_swap"),
            "c128": legacy("disk_swap128"),
            "plus4": legacy("disk_setup_product_plus4"),
        },
    ),
    Scenario(
        "wrong_media_detection_selected_devices",
        {
            "c64": legacy("load_missing_savefile_product_smoke", "save_media_fail_product_smoke"),
            "c128": legacy("boot_title_load_missing_savefile_smoke", "boot_title_save_media_fail_product_smoke"),
            "plus4": legacy("load_wrong_media_product_plus4", "load_missing_savefile_product_plus4"),
        },
    ),
    Scenario(
        "single_drive_save_program_disk_rejected",
        {
            "c64": strict("single_drive_save_wrong_media_product_smoke"),
            "c128": strict("boot_title_single_drive_save_wrong_media_smoke"),
            "plus4": strict("single_drive_save_wrong_media_plus4"),
        },
        ScenarioContract(
            media="drive 8 contains program disk; save device is also drive 8",
            start="title/new game reaches town save path with one-drive disk setup",
            ordered_events=("save_disk_prompt", "program_disk_rejected_for_save", "save_disk_prompt"),
            event_counts=("program_disk_rejected_for_save=1",),
            forbidden_events=("save_success", "gameplay_resume_after_save"),
            screen_assertions=("program disk cannot be used as save media", "press any key"),
            final_proof=("returns to save-disk prompt without writing THE.GAME",),
        ),
    ),
    Scenario(
        "single_drive_load_program_disk_rejected",
        {
            "c64": strict("single_drive_load_wrong_media_product_smoke"),
            "c128": strict("boot_title_single_drive_load_wrong_media_smoke"),
            "plus4": strict("single_drive_load_wrong_media_plus4"),
        },
        ScenarioContract(
            media="drive 8 contains program disk; save device is also drive 8",
            start="title load command in one-drive disk setup",
            ordered_events=("save_disk_prompt", "program_disk_rejected_for_save", "save_disk_prompt"),
            event_counts=("program_disk_rejected_for_save=1",),
            forbidden_events=("wrong_save_disk", "load_success"),
            screen_assertions=("program disk cannot be used as save media", "press any key"),
            final_proof=("remains in save-disk recovery path",),
        ),
    ),
    Scenario(
        "title_disk_setup_single_drive_returns_program_prompt",
        {
            "c64": strict("disk_setup_single_drive_return_product_smoke"),
            "c128": strict("boot_title_disk_setup_single_drive_return_smoke"),
            "plus4": strict("disk_setup_single_drive_return_plus4"),
        },
        ScenarioContract(
            media="drive 8 starts as program disk, title Disk Setup validates a save disk on drive 8, then program disk is reattached only at the program-media prompt",
            start="title D)isk Setup command in one-drive mode with save device 8",
            ordered_events=("disk_setup_save_media_valid", "program_disk_prompt", "title_menu_ready"),
            event_counts=("program_disk_prompt=1",),
            forbidden_events=("title_load_from_save_disk", "garbled_title_return"),
            screen_assertions=("Insert program disk", "title menu text"),
            final_proof=("title menu redraws only after verified program media",),
        ),
    ),
    Scenario(
        "new_save_empty_no_init_returns_setup",
        {
            "c64": legacy("load_missing_savefile_product_smoke"),
            "c128": legacy("boot_title_load_missing_savefile_smoke"),
            "plus4": legacy("disk_setup_missing_save_plus4"),
        },
    ),
    Scenario(
        "new_save_empty_init_writes",
        {
            "c64": strict("single_drive_fresh_save_product_smoke"),
            "c128": strict("boot_title_single_drive_fresh_save_smoke"),
            "plus4": strict("single_drive_fresh_save_plus4"),
        },
        ScenarioContract(
            media="drive 8 starts as program disk, then an empty save disk is attached to drive 8 for the save path",
            start="new game reaches town save path in one-drive disk setup",
            ordered_events=("save_disk_prompt", "initialize_prompt", "save_success", "program_disk_prompt", "gameplay_resume_after_save"),
            event_counts=("initialize_prompt=1", "save_success=1", "program_disk_prompt=1"),
            forbidden_events=("overwrite_prompt", "program_disk_rejected_for_save", "garbled_title_return"),
            screen_assertions=("initialize prompt", "Saving game", "Game Saved", "Insert program disk"),
            final_proof=("save disk contains MORIA8.ID and THE.GAME", "gameplay resumes after program media is restored"),
        ),
    ),
    Scenario(
        "load_initialized_save",
        {
            "c64": strict("load_resume_product_smoke"),
            "c128": strict("boot_title_load_resume_smoke"),
            "plus4": strict("load_resume_product_plus4"),
        },
        ScenarioContract(
            media="program disk remains mounted while initialized save media is available on the selected save device",
            start="title load command with a valid initialized save disk",
            ordered_events=("load_success", "gameplay_resume_after_load"),
            event_counts=("load_success=1",),
            forbidden_events=("save_disk_prompt", "wrong_save_disk", "corrupt_save_error", "program_disk_prompt_after_load"),
            screen_assertions=("title load flow", "gameplay screen after load"),
            final_proof=("load reaches the gameplay resume path from THE.GAME",),
        ),
    ),
    Scenario(
        "prompt_sequence_no_repeat",
        {
            "c64": legacy("load_resume_product_smoke", "single_drive_load_return_product_smoke", "single_drive_fresh_save_product_smoke"),
            "c128": legacy("boot_title_load_mounted_save_smoke", "boot_title_single_drive_fresh_save_smoke"),
            "plus4": legacy("single_drive_load_return_plus4", "single_drive_save_return_plus4", "single_drive_fresh_save_plus4"),
        },
    ),
    Scenario(
        "save_existing_overwrite",
        {
            "c64": strict("save_write_product_smoke"),
            "c128": strict("boot_title_save_write_product_smoke"),
            "plus4": strict("save_write_product_plus4"),
        },
        ScenarioContract(
            media="drive 8 contains program disk; selected save device contains an existing initialized save",
            start="gameplay save command with an existing THE.GAME on the save disk",
            ordered_events=("overwrite_prompt", "save_success", "gameplay_resume_after_save"),
            event_counts=("overwrite_prompt=1", "save_success=1"),
            forbidden_events=("initialize_prompt", "program_disk_prompt_after_save", "program_media_error_after_save"),
            screen_assertions=("overwrite prompt", "Saving game", "Game Saved"),
            final_proof=("save disk still contains MORIA8.ID and THE.GAME after overwrite",),
        ),
    ),
    Scenario(
        "load_then_save_new_empty_disk",
        {
            "c64": legacy("single_drive_load_return_product_smoke", "save_write_product_smoke"),
            "c128": legacy("boot_title_load_mounted_save_smoke", "boot_title_save_write_product_smoke"),
            "plus4": legacy("single_drive_load_return_plus4"),
        },
    ),
    Scenario(
        "dual_drive_load_then_save_no_program_prompt",
        {
            "c64": strict("save_write_product_smoke"),
            "c128": strict("boot_title_save_write_product_smoke"),
            "plus4": strict("save_write_product_plus4"),
        },
        ScenarioContract(
            media="drive 8 contains program disk; drive 9 contains existing save disk",
            start="load existing save, then save back to selected save device",
            ordered_events=("load_success", "overwrite_prompt", "save_success"),
            event_counts=("program_disk_prompt_after_save=0", "save_success=1"),
            forbidden_events=("program_disk_prompt_after_save", "program_media_error_after_save"),
            screen_assertions=("overwrite prompt", "Saving game", "Game Saved"),
            final_proof=("save completes on drive 9 without requiring program media from drive 9",),
        ),
    ),
    Scenario(
        "change_save_drive_after_save",
        {
            "c64": legacy("disk_swap", "save_write_product_smoke"),
            "c128": legacy("disk_swap128", "boot_title_save_write_product_smoke"),
            "plus4": legacy("single_drive_save_return_plus4", "save_write_product_plus4"),
        },
    ),
    Scenario(
        "wrong_media_recovery",
        {
            "c64": legacy("load_missing_savefile_product_smoke", "save_media_fail_product_smoke"),
            "c128": legacy("boot_title_load_missing_savefile_smoke", "boot_title_save_media_fail_product_smoke"),
            "plus4": legacy("load_wrong_media_product_plus4", "load_missing_savefile_product_plus4"),
        },
    ),
    Scenario(
        "missing_device_or_no_disk",
        {
            "c64": legacy("load_missing_savefile_product_smoke"),
            "c128": legacy("boot_title_load_missing_savefile_smoke"),
            "plus4": legacy("disk_setup_missing_save_plus4"),
        },
    ),
    Scenario(
        "cancel_supported_prompts",
        {
            "c64": legacy("load_missing_savefile_product_smoke"),
            "c128": legacy("boot_title_load_missing_savefile_smoke"),
            "plus4": legacy("disk_setup_missing_save_plus4"),
        },
    ),
    Scenario(
        "alternate_drive10_11_save_load_smoke",
        {
            "c64": legacy("disk_swap"),
            "c128": legacy("disk_swap128"),
            "plus4": legacy("disk_setup_product_plus4"),
        },
    ),
    Scenario(
        "alternate_drive_change_smoke",
        {
            "c64": legacy("disk_swap"),
            "c128": legacy("disk_swap128"),
            "plus4": legacy("single_drive_save_return_plus4"),
        },
    ),
    Scenario(
        "alternate_drive_prompt_no_repeat",
        {
            "c64": legacy("disk_swap", "single_drive_load_return_product_smoke"),
            "c128": legacy("disk_swap128"),
            "plus4": legacy("single_drive_load_return_plus4"),
        },
    ),
    Scenario(
        "corrupt_save_file",
        {
            "c64": legacy("load_missing_savefile_product_smoke", note="missing dedicated corrupt-save fixture"),
            "c128": legacy("boot_title_load_missing_savefile_smoke", note="missing dedicated corrupt-save fixture"),
            "plus4": legacy("load_missing_savefile_product_plus4"),
        },
    ),
    Scenario(
        "single_drive_corrupt_save_recovery_requires_program_disk",
        {
            "c64": strict("single_drive_load_corrupt_product_smoke"),
            "c128": strict("boot_title_single_drive_load_corrupt_smoke"),
            "plus4": strict("single_drive_load_corrupt_plus4"),
        },
        ScenarioContract(
            media="drive 8 starts with wrong-platform save disk; program disk is reattached only after program-media prompt",
            start="title load command in one-drive disk setup",
            ordered_events=("corrupt_save_error", "program_disk_prompt", "title_menu_ready"),
            event_counts=("corrupt_save_error=1", "program_disk_prompt=1"),
            forbidden_events=("main_loop", "garbled_title_return"),
            screen_assertions=("Save file corrupt", "Insert program disk", "title menu text"),
            final_proof=("title menu redraws after verified program media",),
        ),
    ),
    Scenario(
        "write_protected_or_forced_write_error",
        {
            "c64": legacy("save_media_fail_product_smoke"),
            "c128": legacy("boot_title_save_media_fail_product_smoke"),
            "plus4": legacy("load_wrong_media_product_plus4"),
        },
    ),
)


PLATFORM_COMMANDS = {
    "c64": ("c64", "./run_tests.sh", "TEST_FILTER"),
    "c128": ("c128", "./run_tests128.sh", "TEST_FILTER"),
    "plus4": ("plus4", "./run_testsplus4.sh", "TEST_FILTER"),
}


RESULT_RE = re.compile(r"=== Results: \d+ passed, \d+ failed \(of (\d+) suites\) ===")
PLUS4_RESULT_RE = re.compile(r"=== Plus/4 runtime summary: \d+ passed, \d+ failed, (\d+) total ===")


def selected_scenarios(pattern: str | None) -> tuple[Scenario, ...]:
    if not pattern:
        return SCENARIOS
    wanted = {part.strip() for part in pattern.split(",") if part.strip()}
    return tuple(scenario for scenario in SCENARIOS if scenario.scenario_id in wanted)


def unknown_scenarios(pattern: str | None) -> tuple[str, ...]:
    if not pattern:
        return ()
    known = {scenario.scenario_id for scenario in SCENARIOS}
    wanted = {part.strip() for part in pattern.split(",") if part.strip()}
    return tuple(sorted(wanted - known))


def validate_matrix(scenarios: tuple[Scenario, ...], require_strict_contracts: bool) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    for scenario in scenarios:
        if scenario.scenario_id in seen:
            errors.append(f"duplicate scenario id {scenario.scenario_id}")
        seen.add(scenario.scenario_id)
        has_strict_adapter = any(coverage.strict for coverage in scenario.coverage.values())
        if has_strict_adapter and scenario.contract is None:
            errors.append(f"{scenario.scenario_id}: strict adapter requires a scenario contract")
        if require_strict_contracts and not scenario.contract:
            errors.append(f"{scenario.scenario_id}: missing strict scenario contract")
        for platform in PLATFORMS:
            coverage = scenario.platform_coverage(platform)
            if not coverage:
                errors.append(f"{scenario.scenario_id}: missing {platform} adapter")
                continue
            if not coverage.tests:
                errors.append(f"{scenario.scenario_id}: empty {platform} test filter")
            if scenario.contract and not coverage.strict:
                errors.append(f"{scenario.scenario_id}: {platform} adapter is legacy, not strict")
    return errors


def filters_by_platform(scenarios: tuple[Scenario, ...]) -> dict[str, str]:
    result: dict[str, str] = {}
    for platform in PLATFORMS:
        names: list[str] = []
        for scenario in scenarios:
            coverage = scenario.coverage[platform]
            for name in coverage.filter_names(scenario.scenario_id):
                if name not in names:
                    names.append(name)
        result[platform] = "|".join(names)
    return result


def platform_suite_count(platform: str, output: str) -> int | None:
    if platform == "plus4":
        match = PLUS4_RESULT_RE.search(output)
    else:
        match = RESULT_RE.search(output)
    if not match:
        return None
    return int(match.group(1))


def print_plan(scenarios: tuple[Scenario, ...], filters: dict[str, str]) -> None:
    print("=== Cross-platform disk scenario matrix ===")
    for scenario in scenarios:
        contract_label = "contract" if scenario.contract else "legacy"
        print(f"  {scenario.scenario_id} [{contract_label}]")
        if scenario.contract:
            print(f"    media: {scenario.contract.media}")
            print(f"    start: {scenario.contract.start}")
            print(f"    events: {', '.join(scenario.contract.ordered_events)}")
            print(f"    counts: {', '.join(scenario.contract.event_counts)}")
            print(f"    no: {', '.join(scenario.contract.forbidden_events)}")
            print(f"    screens: {', '.join(scenario.contract.screen_assertions)}")
            print(f"    proof: {', '.join(scenario.contract.final_proof)}")
        for platform in PLATFORMS:
            coverage = scenario.coverage[platform]
            strict_label = "strict" if coverage.strict else "legacy"
            filters_label = ", ".join(coverage.filter_names(scenario.scenario_id))
            note = f" ({coverage.note})" if coverage.note else ""
            print(f"    {platform}: {strict_label}: {filters_label}; adapter: {', '.join(coverage.tests)}{note}")
    print("")
    print("=== Platform filters ===")
    for platform in PLATFORMS:
        print(f"  {platform}: {filters[platform]}")
    print("")


def run_platform(root: Path, platform: str, test_filter: str, args: argparse.Namespace) -> int:
    workdir_name, script_name, filter_var = PLATFORM_COMMANDS[platform]
    env = os.environ.copy()
    env[filter_var] = test_filter
    env["KICKASS"] = str(args.kickass)
    env.setdefault("C1541", args.c1541)
    if platform == "c64":
        env["VICE"] = args.vice64
    elif platform == "c128":
        env["VICE"] = args.vice128
    else:
        env["VICEPLUS4"] = args.viceplus4

    command = [script_name]
    print(f"=== {platform}: {filter_var}={test_filter} ===", flush=True)
    if args.dry_run:
        return 0
    process = subprocess.Popen(
        command,
        cwd=root / workdir_name,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    output_parts: list[str] = []
    assert process.stdout is not None
    for line in process.stdout:
        output_parts.append(line)
        print(line, end="", flush=True)
    rc = process.wait()
    if rc != 0:
        return rc
    output = "".join(output_parts)
    suite_count = platform_suite_count(platform, output)
    if suite_count is None:
        print(f"FAIL: {platform} did not print a suite summary")
        return 1
    if suite_count == 0:
        print(f"FAIL: {platform} ran zero suites for {filter_var}={test_filter}")
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the shared cross-platform disk test matrix")
    parser.add_argument("--platform", action="append", choices=PLATFORMS)
    parser.add_argument("--scenario", help="comma-separated scenario IDs to run")
    parser.add_argument("--kickass", default="tools/kickass/KickAss.jar", type=Path)
    parser.add_argument("--c1541", default="c1541")
    parser.add_argument("--vice64", default="x64sc")
    parser.add_argument("--vice128", default="x128")
    parser.add_argument("--viceplus4", default="xplus4")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--require-strict-contracts",
        action="store_true",
        help="fail if a selected contract scenario still uses any legacy platform adapter",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parent
    repo_root = root.parent
    if not args.kickass.is_absolute():
        args.kickass = repo_root / args.kickass

    scenarios = selected_scenarios(args.scenario)
    unknown = unknown_scenarios(args.scenario)
    if unknown:
        print(f"FAIL: unknown disk scenario(s): {', '.join(unknown)}")
        return 2
    if not scenarios:
        print("FAIL: no disk scenarios selected")
        return 2

    errors = validate_matrix(scenarios, args.require_strict_contracts)
    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        return 2

    filters = filters_by_platform(scenarios)
    print_plan(scenarios, filters)

    platforms = tuple(args.platform) if args.platform else PLATFORMS
    failed: list[str] = []
    for platform in platforms:
        rc = run_platform(root, platform, filters[platform], args)
        if rc != 0:
            failed.append(platform)
            if not args.dry_run:
                break

    if failed:
        print(f"FAIL: disk matrix failed on {', '.join(failed)}")
        return 1
    print("PASS: cross-platform disk matrix")
    return 0


if __name__ == "__main__":
    sys.exit(main())
