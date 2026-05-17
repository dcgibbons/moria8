#!/usr/bin/env python3
"""Verify every Commodore platform exports the screen HAL contract."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMMON_DIR = ROOT / "commodore/common"

PLATFORM_FILES = {
    "c64": ROOT / "commodore/c64/screen.s",
    "c128": ROOT / "commodore/c128/screen_vdc.s",
    "plus4": ROOT / "commodore/plus4/screen.s",
}

REQUIRED_LABELS = (
    "hal_screen_init",
    "hal_screen_clear",
    "hal_screen_clear_row",
    "hal_screen_put_char",
    "hal_screen_put_string",
    "hal_screen_put_char_at",
    "hal_screen_set_cursor",
    "hal_screen_set_color",
    "hal_screen_blank",
    "hal_screen_unblank",
    "hal_screen_begin_bulk",
    "hal_screen_end_bulk",
)

REQUIRED_CONSTANTS = (
    "hal_screen_full_clear_uses_bulk",
    "hal_screen_box_vertical_char",
    "hal_screen_help_line_uses_api",
    "hal_screen_help_line_uses_color_map",
    "hal_screen_spell_bolt_flash_sets_color",
)

FORBIDDEN_COMMON_CALLS = (
    "screen_clear",
    "screen_clear_row",
    "screen_put_char",
    "screen_put_string",
    "screen_put_char_at",
    "screen_set_cursor",
    "screen_set_color",
    "screen_blank",
    "screen_unblank",
)

COMMON_HELP_CLEAR_FILE = COMMON_DIR / "ui_help_clear.s"
COMMON_HELP_FILE = COMMON_DIR / "ui_help.s"
COMMON_SPELL_EFFECTS_FILE = COMMON_DIR / "spell_effects.s"


def exported_symbols(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    symbols: set[str] = set(re.findall(r"(?m)^([A-Za-z_][A-Za-z0-9_]*):", text))
    symbols.update(re.findall(r"(?m)^\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text))
    symbols.update(re.findall(r"(?m)^\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text))
    return symbols


def common_call_violations() -> list[str]:
    violations: list[str] = []
    call_pattern = re.compile(
        rf"\b(?:jsr|jmp)\s+({'|'.join(re.escape(name) for name in FORBIDDEN_COMMON_CALLS)})\b"
    )
    for path in sorted(COMMON_DIR.glob("*.s")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_number, line in enumerate(text.splitlines(), start=1):
            match = call_pattern.search(line)
            if match:
                violations.append(
                    f"{path.relative_to(ROOT)}:{line_number} calls {match.group(1)}"
                )
    return violations


def common_policy_violations() -> list[str]:
    text = COMMON_HELP_CLEAR_FILE.read_text(encoding="utf-8", errors="replace")
    help_text = COMMON_HELP_FILE.read_text(encoding="utf-8", errors="replace")
    spell_effects_text = COMMON_SPELL_EFFECTS_FILE.read_text(
        encoding="utf-8", errors="replace"
    )
    errors: list[str] = []
    target_if = re.compile(r"(?m)^\s*#(?:if|elif|ifdef)\b.*\b(?:C64|C128|PLUS4)\b")
    for match in target_if.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        errors.append(
            f"{COMMON_HELP_CLEAR_FILE.relative_to(ROOT)}:{line} uses target conditional in screen helper"
        )
    for match in target_if.finditer(help_text):
        line = help_text.count("\n", 0, match.start()) + 1
        errors.append(
            f"{COMMON_HELP_FILE.relative_to(ROOT)}:{line} uses target conditional in screen helper"
        )
    if "hal_screen_full_clear_uses_bulk" not in text:
        errors.append(
            f"{COMMON_HELP_CLEAR_FILE.relative_to(ROOT)} does not consume hal_screen_full_clear_uses_bulk"
        )
    if "hal_screen_box_vertical_char" not in help_text:
        errors.append("commodore/common/ui_help.s does not consume hal_screen_box_vertical_char")
    if "HAL_SCREEN_HELP_LINE_USES_API" not in help_text:
        errors.append("commodore/common/ui_help.s does not consume HAL_SCREEN_HELP_LINE_USES_API")
    if "HAL_SCREEN_HELP_LINE_USES_COLOR_MAP" not in help_text:
        errors.append(
            "commodore/common/ui_help.s does not consume HAL_SCREEN_HELP_LINE_USES_COLOR_MAP"
        )
    if "hal_screen_spell_bolt_flash_sets_color" not in spell_effects_text:
        errors.append(
            "commodore/common/spell_effects.s does not consume hal_screen_spell_bolt_flash_sets_color"
        )
    flash_policy = re.compile(
        r"(?s)#if\s+hal_screen_spell_bolt_flash_sets_color.*?"
        r"jsr\s+screen_flash_set_color.*?"
        r"jsr\s+screen_flash_at.*?"
        r"#if\s+hal_screen_spell_bolt_flash_sets_color.*?"
        r"jsr\s+screen_flash_reset_color"
    )
    if not flash_policy.search(spell_effects_text):
        errors.append(
            "commodore/common/spell_effects.s does not gate bolt flash color with "
            "hal_screen_spell_bolt_flash_sets_color"
        )
    c128_flash_policy = re.compile(
        r"(?s)#if\s+\(?\s*C128\s*\)?.{0,120}?"
        r"jsr\s+screen_flash_(?:set_color|reset_color)"
    )
    match = c128_flash_policy.search(spell_effects_text)
    if match:
        line = spell_effects_text.count("\n", 0, match.start()) + 1
        errors.append(
            f"{COMMON_SPELL_EFFECTS_FILE.relative_to(ROOT)}:{line} uses target conditional "
            "for bolt flash color"
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
    errors.extend(common_policy_violations())

    if errors:
        print("HAL screen export check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print(
        "HAL screen export check passed "
        f"({len(REQUIRED_LABELS)} labels and {len(REQUIRED_CONSTANTS)} constants "
        f"x {len(PLATFORM_FILES)} platforms, "
        "common text/clear/color call-site audit)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
