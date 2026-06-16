#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


PLATFORMS = ("c64", "c128", "plus4")


@dataclass(frozen=True)
class Scenario:
    scenario_id: str
    coverage: dict[str, tuple[str, ...]]


SCENARIOS: tuple[Scenario, ...] = (
    Scenario(
        "media_drive8_attach_read_write",
        {
            "c64": ("disk_swap",),
            "c128": ("disk_swap128", "marker_init_d64_smoke"),
            "plus4": ("disk_setup_product_plus4",),
        },
    ),
    Scenario(
        "media_drive9_attach_read_write",
        {
            "c64": ("disk_setup_product_smoke", "save_write_product_smoke"),
            "c128": ("marker_init_d64_smoke", "boot_title_save_write_product_smoke"),
            "plus4": ("disk_setup_product_plus4", "save_write_product_plus4"),
        },
    ),
    Scenario(
        "media_drive10_11_device_probe",
        {
            "c64": ("disk_swap",),
            "c128": ("disk_swap128",),
            "plus4": ("disk_setup_product_plus4",),
        },
    ),
    Scenario(
        "wrong_media_detection_selected_devices",
        {
            "c64": ("load_missing_savefile_product_smoke", "save_media_fail_product_smoke"),
            "c128": ("boot_title_load_missing_savefile_smoke", "boot_title_save_media_fail_product_smoke"),
            "plus4": ("load_wrong_media_product_plus4", "load_missing_savefile_product_plus4"),
        },
    ),
    Scenario(
        "single_drive_save_program_disk_rejected",
        {
            "c64": ("single_drive_save_wrong_media_product_smoke",),
            "c128": ("boot_title_single_drive_save_wrong_media_smoke",),
            "plus4": ("single_drive_save_wrong_media_plus4",),
        },
    ),
    Scenario(
        "new_save_empty_no_init_returns_setup",
        {
            "c64": ("load_missing_savefile_product_smoke",),
            "c128": ("boot_title_load_missing_savefile_smoke",),
            "plus4": ("disk_setup_missing_save_plus4",),
        },
    ),
    Scenario(
        "new_save_empty_init_writes",
        {
            "c64": ("disk_setup_product_smoke", "single_drive_fresh_save_product_smoke"),
            "c128": ("marker_init_d64_smoke", "boot_title_single_drive_fresh_save_smoke"),
            "plus4": ("disk_setup_product_plus4", "single_drive_fresh_save_plus4"),
        },
    ),
    Scenario(
        "load_initialized_save",
        {
            "c64": ("load_resume_product_smoke",),
            "c128": ("boot_title_load_resume_smoke", "boot_title_load_mounted_save_smoke"),
            "plus4": ("load_resume_product_plus4",),
        },
    ),
    Scenario(
        "prompt_sequence_no_repeat",
        {
            "c64": ("load_resume_product_smoke", "single_drive_load_return_product_smoke", "single_drive_fresh_save_product_smoke"),
            "c128": ("boot_title_load_mounted_save_smoke", "boot_title_single_drive_fresh_save_smoke"),
            "plus4": ("single_drive_load_return_plus4", "single_drive_save_return_plus4", "single_drive_fresh_save_plus4"),
        },
    ),
    Scenario(
        "save_existing_overwrite",
        {
            "c64": ("save_write_product_smoke",),
            "c128": ("boot_title_save_write_product_smoke",),
            "plus4": ("save_write_product_plus4",),
        },
    ),
    Scenario(
        "load_then_save_new_empty_disk",
        {
            "c64": ("single_drive_load_return_product_smoke", "save_write_product_smoke"),
            "c128": ("boot_title_load_mounted_save_smoke", "boot_title_save_write_product_smoke"),
            "plus4": ("single_drive_load_return_plus4",),
        },
    ),
    Scenario(
        "change_save_drive_after_save",
        {
            "c64": ("disk_swap", "save_write_product_smoke"),
            "c128": ("disk_swap128", "boot_title_save_write_product_smoke"),
            "plus4": ("single_drive_save_return_plus4", "save_write_product_plus4"),
        },
    ),
    Scenario(
        "wrong_media_recovery",
        {
            "c64": ("load_missing_savefile_product_smoke", "save_media_fail_product_smoke"),
            "c128": ("boot_title_load_missing_savefile_smoke", "boot_title_save_media_fail_product_smoke"),
            "plus4": ("load_wrong_media_product_plus4", "load_missing_savefile_product_plus4"),
        },
    ),
    Scenario(
        "missing_device_or_no_disk",
        {
            "c64": ("load_missing_savefile_product_smoke",),
            "c128": ("boot_title_load_missing_savefile_smoke",),
            "plus4": ("disk_setup_missing_save_plus4",),
        },
    ),
    Scenario(
        "cancel_supported_prompts",
        {
            "c64": ("load_missing_savefile_product_smoke",),
            "c128": ("boot_title_load_missing_savefile_smoke",),
            "plus4": ("disk_setup_missing_save_plus4",),
        },
    ),
    Scenario(
        "alternate_drive10_11_save_load_smoke",
        {
            "c64": ("disk_swap",),
            "c128": ("disk_swap128",),
            "plus4": ("disk_setup_product_plus4",),
        },
    ),
    Scenario(
        "alternate_drive_change_smoke",
        {
            "c64": ("disk_swap",),
            "c128": ("disk_swap128",),
            "plus4": ("single_drive_save_return_plus4",),
        },
    ),
    Scenario(
        "alternate_drive_prompt_no_repeat",
        {
            "c64": ("disk_swap", "single_drive_load_return_product_smoke"),
            "c128": ("disk_swap128",),
            "plus4": ("single_drive_load_return_plus4",),
        },
    ),
    Scenario(
        "corrupt_save_file",
        {
            "c64": ("load_missing_savefile_product_smoke",),
            "c128": ("boot_title_load_missing_savefile_smoke",),
            "plus4": ("load_missing_savefile_product_plus4",),
        },
    ),
    Scenario(
        "write_protected_or_forced_write_error",
        {
            "c64": ("save_media_fail_product_smoke",),
            "c128": ("boot_title_save_media_fail_product_smoke",),
            "plus4": ("load_wrong_media_product_plus4",),
        },
    ),
)


PLATFORM_COMMANDS = {
    "c64": ("c64", "./run_tests.sh", "TEST_FILTER"),
    "c128": ("c128", "./run_tests128.sh", "TEST_FILTER"),
    "plus4": ("plus4", "./run_testsplus4.sh", "TEST_FILTER"),
}


def selected_scenarios(pattern: str | None) -> tuple[Scenario, ...]:
    if not pattern:
        return SCENARIOS
    wanted = {part.strip() for part in pattern.split(",") if part.strip()}
    return tuple(scenario for scenario in SCENARIOS if scenario.scenario_id in wanted)


def validate_matrix(scenarios: tuple[Scenario, ...]) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    for scenario in scenarios:
        if scenario.scenario_id in seen:
            errors.append(f"duplicate scenario id {scenario.scenario_id}")
        seen.add(scenario.scenario_id)
        for platform in PLATFORMS:
            if not scenario.coverage.get(platform):
                errors.append(f"{scenario.scenario_id}: missing {platform} adapter")
    return errors


def filters_by_platform(scenarios: tuple[Scenario, ...]) -> dict[str, str]:
    result: dict[str, str] = {}
    for platform in PLATFORMS:
        names: list[str] = []
        for scenario in scenarios:
            for name in scenario.coverage[platform]:
                if name not in names:
                    names.append(name)
        result[platform] = "|".join(names)
    return result


def print_plan(scenarios: tuple[Scenario, ...], filters: dict[str, str]) -> None:
    print("=== Cross-platform disk scenario matrix ===")
    for scenario in scenarios:
        print(f"  {scenario.scenario_id}")
        for platform in PLATFORMS:
            print(f"    {platform}: {', '.join(scenario.coverage[platform])}")
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
    return subprocess.run(command, cwd=root / workdir_name, env=env).returncode


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
    args = parser.parse_args()

    root = Path(__file__).resolve().parent
    repo_root = root.parent
    if not args.kickass.is_absolute():
        args.kickass = repo_root / args.kickass

    scenarios = selected_scenarios(args.scenario)
    if not scenarios:
        print("FAIL: no disk scenarios selected")
        return 2

    errors = validate_matrix(scenarios)
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
