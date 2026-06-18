#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from disk_test_catalog import ADAPTER_MODES, PLATFORMS, SCENARIOS, SCENARIO_ID_RE, Scenario


RESULT_RE = re.compile(r"=== Results: \d+ passed, \d+ failed \(of (\d+) suites\) ===")
PLUS4_RESULT_RE = re.compile(r"=== Plus/4 runtime summary: \d+ passed, \d+ failed, (\d+) total ===")


@dataclass(frozen=True)
class PlatformAdapter:
    workdir: str
    script: str
    filter_var: str
    vice_env: str
    vice_arg: str
    summary_re: re.Pattern[str]


PLATFORM_ADAPTERS = {
    "c64": PlatformAdapter("c64", "./run_tests.sh", "TEST_FILTER", "VICE", "vice64", RESULT_RE),
    "c128": PlatformAdapter("c128", "./run_tests128.sh", "TEST_FILTER", "VICE", "vice128", RESULT_RE),
    "plus4": PlatformAdapter("plus4", "./run_testsplus4.sh", "TEST_FILTER", "VICEPLUS4", "viceplus4", PLUS4_RESULT_RE),
}


def selected_scenarios(
    pattern: str | None,
    strict_only: bool,
    legacy_only: bool,
    adapter_modes: tuple[str, ...],
    excluded_adapter_modes: tuple[str, ...],
) -> tuple[Scenario, ...]:
    scenarios = SCENARIOS
    wanted = {part.strip() for part in pattern.split(",") if part.strip()} if pattern else set()
    if wanted:
        scenarios = tuple(scenario for scenario in scenarios if scenario.scenario_id in wanted)
    if strict_only:
        scenarios = tuple(scenario for scenario in scenarios if scenario.contract)
    if legacy_only:
        scenarios = tuple(scenario for scenario in scenarios if not scenario.contract)
    if adapter_modes:
        wanted_modes = set(adapter_modes)
        scenarios = tuple(
            scenario
            for scenario in scenarios
            if any(coverage.mode in wanted_modes for coverage in scenario.coverage.values())
        )
    if excluded_adapter_modes:
        blocked_modes = set(excluded_adapter_modes)
        scenarios = tuple(
            scenario
            for scenario in scenarios
            if not any(coverage.mode in blocked_modes for coverage in scenario.coverage.values())
        )
    return scenarios


def unknown_scenarios(pattern: str | None) -> tuple[str, ...]:
    if not pattern:
        return ()
    known = {scenario.scenario_id for scenario in SCENARIOS}
    wanted = {part.strip() for part in pattern.split(",") if part.strip()}
    return tuple(sorted(wanted - known))


def declared_filter_names(root: Path, platform: str) -> tuple[str, ...]:
    adapter = PLATFORM_ADAPTERS[platform]
    script_path = root / adapter.workdir / adapter.script.removeprefix("./")
    text = script_path.read_text()
    names: set[str] = set()
    if platform == "c64":
        for line in text.splitlines():
            if "run_suite_function" in line or "run_test" in line:
                names.update(re.findall(r'"([a-z0-9_]+)"', line))
    elif platform == "c128":
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith("run_named_suite"):
                tokens = shlex.split(stripped)
                names.add(tokens[1])
                for index, token in enumerate(tokens[:-1]):
                    if token == "--alias":
                        names.add(tokens[index + 1])
            for quoted in re.findall(r'"([a-z0-9_]+ [^"]+)"', line):
                names.add(quoted.split()[0])
    elif platform == "plus4":
        for line in text.splitlines():
            match = re.search(r'local name="([a-z0-9_]+)"', line)
            if match:
                names.add(match.group(1))
            if "suite_selected" in line:
                for name in re.findall(r'"([a-z0-9_]+)"', line):
                    names.add(name)
    return tuple(sorted(names))


def validate_contract(scenario: Scenario) -> list[str]:
    if not scenario.contract:
        return []
    errors: list[str] = []
    contract = scenario.contract
    if not contract.media:
        errors.append(f"{scenario.scenario_id}: empty contract media")
    if not contract.start:
        errors.append(f"{scenario.scenario_id}: empty contract start")
    tuple_fields = (
        ("ordered_events", contract.ordered_events, True),
        ("event_counts", contract.event_counts, False),
        ("forbidden_events", contract.forbidden_events, False),
        ("screen_assertions", contract.screen_assertions, False),
        ("final_proof", contract.final_proof, False),
    )
    for field_name, values, allow_repeats in tuple_fields:
        if not values:
            errors.append(f"{scenario.scenario_id}: empty contract {field_name}")
        if not allow_repeats and len(set(values)) != len(values):
            errors.append(f"{scenario.scenario_id}: duplicate contract {field_name}")
    for event_count in contract.event_counts:
        if not re.fullmatch(r"[a-z0-9_]+=\d+", event_count):
            errors.append(f"{scenario.scenario_id}: invalid event count {event_count}")
    return errors


def validate_matrix(
    root: Path,
    scenarios: tuple[Scenario, ...],
    require_strict_contracts: bool,
    fail_on_adapter_modes: tuple[str, ...],
) -> list[str]:
    errors: list[str] = []
    blocked_modes = set(fail_on_adapter_modes)
    missing_adapters = sorted(set(PLATFORMS) - set(PLATFORM_ADAPTERS))
    extra_adapters = sorted(set(PLATFORM_ADAPTERS) - set(PLATFORMS))
    for platform in missing_adapters:
        errors.append(f"missing platform runner adapter for {platform}")
    for platform in extra_adapters:
        errors.append(f"unknown platform runner adapter {platform}")
    declared_filters: dict[str, tuple[str, ...]] = {}
    for platform in PLATFORMS:
        if platform in PLATFORM_ADAPTERS:
            declared_filters[platform] = declared_filter_names(root, platform)
    seen: set[str] = set()
    for scenario in scenarios:
        if not SCENARIO_ID_RE.fullmatch(scenario.scenario_id):
            errors.append(f"{scenario.scenario_id}: scenario id must be lowercase snake_case")
        if scenario.scenario_id in seen:
            errors.append(f"duplicate scenario id {scenario.scenario_id}")
        seen.add(scenario.scenario_id)
        extra_platforms = sorted(set(scenario.coverage) - set(PLATFORMS))
        for platform in extra_platforms:
            errors.append(f"{scenario.scenario_id}: unknown platform adapter {platform}")
        has_strict_adapter = any(coverage.strict for coverage in scenario.coverage.values())
        if has_strict_adapter and scenario.contract is None:
            errors.append(f"{scenario.scenario_id}: strict adapter requires a scenario contract")
        if require_strict_contracts and not scenario.contract:
            errors.append(f"{scenario.scenario_id}: missing strict scenario contract")
        errors.extend(validate_contract(scenario))
        for platform in PLATFORMS:
            coverage = scenario.platform_coverage(platform)
            if not coverage:
                errors.append(f"{scenario.scenario_id}: missing {platform} adapter")
                continue
            if not coverage.tests:
                errors.append(f"{scenario.scenario_id}: empty {platform} test filter")
            if coverage.mode not in ADAPTER_MODES:
                errors.append(f"{scenario.scenario_id}: invalid {platform} adapter mode {coverage.mode}")
            if coverage.mode != "strict" and not coverage.note:
                errors.append(f"{scenario.scenario_id}: non-strict {platform} adapter requires a debt note")
            if coverage.mode in blocked_modes:
                errors.append(f"{scenario.scenario_id}: {platform} adapter mode {coverage.mode} is blocked")
            for test_filter in coverage.filter_names(scenario.scenario_id):
                if test_filter not in declared_filters.get(platform, ()):
                    errors.append(f"{scenario.scenario_id}: {platform} filter {test_filter} is not declared by the harness")
            if len(set(coverage.tests)) != len(coverage.tests):
                errors.append(f"{scenario.scenario_id}: duplicate {platform} adapter filter")
            if scenario.contract and not coverage.strict:
                errors.append(f"{scenario.scenario_id}: {platform} adapter is legacy, not strict")
            if scenario.contract and coverage.mode in ("real", "proxy"):
                errors.append(f"{scenario.scenario_id}: {platform} adapter mode {coverage.mode} is not valid for a contract scenario")
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


def platform_suite_count(adapter: PlatformAdapter, output: str) -> int | None:
    match = adapter.summary_re.search(output)
    if not match:
        return None
    return int(match.group(1))


def build_platform_env(adapter: PlatformAdapter, test_filter: str, args: argparse.Namespace) -> dict[str, str]:
    env = os.environ.copy()
    env[adapter.filter_var] = test_filter
    env["KICKASS"] = str(args.kickass)
    env.setdefault("C1541", args.c1541)
    env[adapter.vice_env] = getattr(args, adapter.vice_arg)
    return env


def scenario_status(scenario: Scenario) -> str:
    if scenario.contract:
        return "strict"
    modes = {coverage.mode for coverage in scenario.coverage.values()}
    if "deferred" in modes:
        return "deferred"
    if "proxy" in modes or "real" in modes:
        return "proxy"
    return "legacy"


def adapter_mode_counts(scenarios: tuple[Scenario, ...]) -> dict[str, int]:
    return {
        mode: sum(1 for scenario in scenarios for coverage in scenario.coverage.values() if coverage.mode == mode)
        for mode in ADAPTER_MODES
    }


def scenario_ids_with_mode(scenarios: tuple[Scenario, ...], mode: str) -> tuple[str, ...]:
    return tuple(
        scenario.scenario_id
        for scenario in scenarios
        if any(coverage.mode == mode for coverage in scenario.coverage.values())
    )


def print_summary(scenarios: tuple[Scenario, ...]) -> None:
    strict_count = sum(1 for scenario in scenarios if scenario.contract)
    status_counts = {
        status: sum(1 for scenario in scenarios if scenario_status(scenario) == status)
        for status in ("strict", "proxy", "deferred", "legacy")
    }
    debt = tuple(scenario for scenario in scenarios if scenario_has_debt(scenario))
    mode_counts = adapter_mode_counts(scenarios)
    real_ids = scenario_ids_with_mode(scenarios, "real")
    proxy_ids = scenario_ids_with_mode(scenarios, "proxy")
    deferred_ids = scenario_ids_with_mode(scenarios, "deferred")
    print("=== Matrix summary ===")
    print(f"  scenarios: {len(scenarios)}")
    print(f"  strict contracts: {strict_count}")
    print(
        "  scenario status: "
        + ", ".join(f"{status}={status_counts[status]}" for status in ("strict", "proxy", "deferred", "legacy"))
    )
    print("  adapter modes: " + ", ".join(f"{mode}={mode_counts[mode]}" for mode in ADAPTER_MODES))
    if real_ids:
        print(f"  real adapter ids: {', '.join(real_ids)}")
    if proxy_ids:
        print(f"  proxy adapter ids: {', '.join(proxy_ids)}")
    if deferred_ids:
        print(f"  deferred adapter ids: {', '.join(deferred_ids)}")
    if debt:
        print(f"  debt ids: {', '.join(scenario.scenario_id for scenario in debt)}")
    print("")


def print_list(scenarios: tuple[Scenario, ...], include_platform_modes: bool = False) -> None:
    for scenario in scenarios:
        if include_platform_modes:
            modes = "\t".join(f"{platform}={scenario.coverage[platform].mode}" for platform in PLATFORMS)
            print(f"{scenario.scenario_id}\t{scenario_status(scenario)}\t{modes}")
        else:
            print(f"{scenario.scenario_id}\t{scenario_status(scenario)}")


def scenario_has_debt(scenario: Scenario) -> bool:
    return scenario.contract is None or any(not coverage.strict for coverage in scenario.coverage.values())


def print_debt(scenarios: tuple[Scenario, ...]) -> None:
    debt = tuple(scenario for scenario in scenarios if scenario_has_debt(scenario))
    if not debt:
        print("No disk matrix debt in selected scenarios")
        return
    for scenario in debt:
        print(f"{scenario.scenario_id}\t{scenario_status(scenario)}")
        for platform in PLATFORMS:
            coverage = scenario.coverage[platform]
            note = f"\t{coverage.note}" if coverage.note else ""
            print(f"  {platform}\t{coverage.mode}\t{', '.join(coverage.tests)}{note}")


def print_plan(scenarios: tuple[Scenario, ...], filters: dict[str, str]) -> None:
    print_summary(scenarios)
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
            filters_label = ", ".join(coverage.filter_names(scenario.scenario_id))
            note = f" ({coverage.note})" if coverage.note else ""
            print(f"    {platform}: {coverage.mode}: {filters_label}; adapter: {', '.join(coverage.tests)}{note}")
    print("")
    print("=== Platform filters ===")
    for platform in PLATFORMS:
        print(f"  {platform}: {filters[platform]}")
    print("")


def run_platform(root: Path, platform: str, test_filter: str, args: argparse.Namespace) -> int:
    adapter = PLATFORM_ADAPTERS[platform]
    env = build_platform_env(adapter, test_filter, args)

    command = [adapter.script]
    print(f"=== {platform}: {adapter.filter_var}={test_filter} ===", flush=True)
    if args.dry_run:
        return 0
    process = subprocess.Popen(
        command,
        cwd=root / adapter.workdir,
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
    suite_count = platform_suite_count(adapter, output)
    if suite_count is None:
        print(f"FAIL: {platform} did not print a suite summary")
        return 1
    if suite_count == 0:
        print(f"FAIL: {platform} ran zero suites for {adapter.filter_var}={test_filter}")
        return 1
    return 0


def selected_platforms(args: argparse.Namespace) -> tuple[str, ...]:
    return tuple(args.platform) if args.platform else PLATFORMS


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the shared cross-platform disk test matrix")
    parser.add_argument("--platform", action="append", choices=PLATFORMS)
    parser.add_argument("--scenario", help="comma-separated scenario IDs to run")
    parser.add_argument("--strict-only", action="store_true", help="select only strict contract scenarios")
    parser.add_argument("--legacy-only", action="store_true", help="select only scenarios without strict contracts")
    parser.add_argument(
        "--adapter-mode",
        action="append",
        choices=ADAPTER_MODES,
        help="select scenarios with at least one platform adapter in this mode",
    )
    parser.add_argument(
        "--exclude-adapter-mode",
        action="append",
        choices=ADAPTER_MODES,
        help="exclude scenarios with any platform adapter in this mode",
    )
    parser.add_argument(
        "--fail-on-adapter-mode",
        action="append",
        choices=ADAPTER_MODES,
        help="fail if any selected platform adapter uses this mode",
    )
    parser.add_argument("--list-scenarios", action="store_true", help="list selected scenario IDs and exit")
    parser.add_argument("--list-platform-modes", action="store_true", help="include per-platform adapter modes when listing")
    parser.add_argument("--list-debt", action="store_true", help="list selected scenarios that are not fully strict contracts")
    parser.add_argument("--kickass", default="tools/kickass/KickAss.jar", type=Path)
    parser.add_argument("--c1541", default="c1541")
    parser.add_argument("--vice64", default="x64sc")
    parser.add_argument("--vice128", default="x128")
    parser.add_argument("--viceplus4", default="xplus4")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--check-only", action="store_true", help="validate selected scenarios and exit without printing the run plan")
    parser.add_argument(
        "--require-strict-contracts",
        action="store_true",
        help="fail unless every selected scenario has a strict contract and strict platform adapters",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parent
    repo_root = root.parent
    if not args.kickass.is_absolute():
        args.kickass = repo_root / args.kickass

    if args.strict_only and args.legacy_only:
        print("FAIL: --strict-only and --legacy-only are mutually exclusive")
        return 2

    scenarios = selected_scenarios(
        args.scenario,
        args.strict_only,
        args.legacy_only,
        tuple(args.adapter_mode or ()),
        tuple(args.exclude_adapter_mode or ()),
    )
    unknown = unknown_scenarios(args.scenario)
    if unknown:
        print(f"FAIL: unknown disk scenario(s): {', '.join(unknown)}")
        return 2
    if not scenarios:
        print("FAIL: no disk scenarios selected")
        return 2

    errors = validate_matrix(root, scenarios, args.require_strict_contracts, tuple(args.fail_on_adapter_mode or ()))
    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        return 2
    if args.check_only:
        print("PASS: disk matrix validation")
        return 0

    if args.list_scenarios:
        print_list(scenarios, args.list_platform_modes)
        return 0
    if args.list_debt:
        print_debt(scenarios)
        return 0

    filters = filters_by_platform(scenarios)
    print_plan(scenarios, filters)

    failed: list[str] = []
    for platform in selected_platforms(args):
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
