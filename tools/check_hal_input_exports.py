#!/usr/bin/env python3
"""Verify every Commodore platform exports the input HAL contract."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMMON_DIR = ROOT / "commodore/common"

PLATFORM_FILES = {
    "c64": ROOT / "commodore/c64/input.s",
    "c128": ROOT / "commodore/c128/input128.s",
    "plus4": ROOT / "commodore/plus4/input.s",
}

REQUIRED_LABELS = (
    "hal_input_get_key",
    "hal_input_get_command",
    "hal_input_get_text_char",
    "hal_input_wait_release",
    "hal_input_any_key_held",
    "hal_input_run_cancel_check",
    "hal_input_followup_prepare",
    "hal_input_modal_prepare",
    "hal_input_modal_finish",
)

REQUIRED_CONSTANTS = (
    "hal_input_kbdbuf_count",
    "hal_input_modal_dismiss_uses_fast_key",
    "hal_input_modal_escape_primary",
    "hal_input_modal_escape_secondary",
    "hal_input_flush_run_cancel_buffer",
    "hal_input_help_footer_uses_esc_stop",
    "hal_input_inventory_letter_normalize_shifted",
)

HELPER_POLICY_CONSTANTS = (
    "hal_input_kbdbuf_count",
    "hal_input_modal_dismiss_uses_fast_key",
    "hal_input_modal_escape_primary",
    "hal_input_modal_escape_secondary",
    "hal_input_flush_run_cancel_buffer",
    "hal_input_inventory_letter_normalize_shifted",
)

FORBIDDEN_COMMON_CALLS = (
    "input_get_key",
    "input_get_command",
    "input_wait_release",
    "input_run_key_held",
    "input_run_cancel_check",
)

COMMON_HELPER_FILE = COMMON_DIR / "input_ui_helpers.s"


def exported_symbols(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    symbols: set[str] = set(re.findall(r"(?m)^([A-Za-z_][A-Za-z0-9_]*):", text))
    symbols.update(re.findall(r"(?m)^\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text))
    symbols.update(re.findall(r"(?m)^\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text))
    return symbols


def common_call_violations() -> list[str]:
    violations: list[str] = []
    names = "|".join(re.escape(name) for name in FORBIDDEN_COMMON_CALLS)
    call_pattern = re.compile(rf"\b(?:jsr|jmp)\s+({names})\b")
    for path in sorted(COMMON_DIR.glob("*.s")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_number, line in enumerate(text.splitlines(), start=1):
            match = call_pattern.search(line)
            if match:
                violations.append(
                    f"{path.relative_to(ROOT)}:{line_number} calls {match.group(1)}"
                )
    return violations


def helper_policy_violations() -> list[str]:
    text = COMMON_HELPER_FILE.read_text(encoding="utf-8", errors="replace")
    errors: list[str] = []
    target_if = re.compile(r"(?m)^\s*#(?:if|elif|ifdef)\b.*\b(?:C64|C128|PLUS4)\b")
    for match in target_if.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        errors.append(
            f"{COMMON_HELPER_FILE.relative_to(ROOT)}:{line} uses target conditional in input helper"
        )
    for const in HELPER_POLICY_CONSTANTS:
        if const not in text:
            errors.append(
                f"{COMMON_HELPER_FILE.relative_to(ROOT)} does not consume {const}"
            )
    if "hal_input_followup_prepare" not in text:
        errors.append(
            f"{COMMON_HELPER_FILE.relative_to(ROOT)} does not consume hal_input_followup_prepare"
        )
    help_text = (COMMON_DIR / "ui_help.s").read_text(encoding="utf-8", errors="replace")
    if "hal_input_help_footer_uses_esc_stop" not in help_text:
        errors.append(
            "commodore/common/ui_help.s does not consume hal_input_help_footer_uses_esc_stop"
        )
    return errors


def main() -> int:
    errors: list[str] = []
    for platform, path in PLATFORM_FILES.items():
        symbols = exported_symbols(path)
        for label in REQUIRED_LABELS:
            if label not in symbols:
                errors.append(f"{platform}: missing {label} in {path.relative_to(ROOT)}")
        for const in REQUIRED_CONSTANTS:
            if const not in symbols:
                errors.append(f"{platform}: missing {const} in {path.relative_to(ROOT)}")

    errors.extend(common_call_violations())
    errors.extend(helper_policy_violations())

    if errors:
        print("HAL input export check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print(
        "HAL input export check passed "
        f"({len(REQUIRED_LABELS)} labels and {len(REQUIRED_CONSTANTS)} constants "
        f"x {len(PLATFORM_FILES)} platforms, "
        "common input call-site audit)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
