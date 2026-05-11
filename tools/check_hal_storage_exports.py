#!/usr/bin/env python3
"""Verify every Commodore platform exports the storage HAL adapter labels."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_LABELS = (
    "hal_storage_enter_os",
    "hal_storage_exit_os",
    "hal_storage_probe_media",
    "hal_storage_init_selected_drive",
    "hal_storage_require_program_media",
    "hal_storage_require_save_media",
    "hal_storage_marker_present",
    "hal_storage_marker_init",
    "hal_storage_save_media_status",
    "hal_storage_setup_status",
    "hal_storage_setnam",
    "hal_storage_setlfs",
    "hal_storage_open",
    "hal_storage_close",
    "hal_storage_chkin",
    "hal_storage_chkout",
    "hal_storage_chrin",
    "hal_storage_chrout",
    "hal_storage_clrchn",
    "hal_storage_readst",
    "hal_storage_load",
    "hal_storage_read_command_status",
    "hal_storage_save_record",
    "hal_storage_load_record",
    "hal_storage_save_file_num",
    "hal_storage_check_file_num",
    "hal_storage_save_sec_write",
    "hal_storage_save_sec_read",
    "hal_storage_check_sec_read",
    "hal_storage_cmd_channel",
    "hal_storage_marker_file_num",
    "hal_storage_marker_sec_read",
    "hal_storage_marker_sec_write",
    "hal_storage_program_file_num",
    "hal_storage_save_probe_name",
    "hal_storage_save_probe_name_len",
    "hal_storage_save_read_name",
    "hal_storage_save_read_name_len",
    "hal_storage_save_write_name",
    "hal_storage_save_write_name_len",
    "hal_storage_score_read_name",
    "hal_storage_score_read_name_len",
    "hal_storage_score_write_name",
    "hal_storage_score_write_name_len",
    "hal_storage_score_scratch_name",
    "hal_storage_score_scratch_name_len",
    "hal_storage_init_command",
    "hal_storage_marker_magic",
    "hal_storage_marker_magic_len",
    "hal_storage_marker_read_name",
    "hal_storage_marker_read_name_len",
    "hal_storage_marker_write_name",
    "hal_storage_marker_write_name_len",
    "hal_storage_marker_scratch_name",
    "hal_storage_marker_scratch_name_len",
    "hal_storage_title_name",
    "hal_storage_title_name_len",
    "hal_storage_tier_name_lo",
    "hal_storage_tier_name_hi",
    "hal_storage_tier_name_len",
    "hal_storage_tier_1_name",
    "hal_storage_tier_1_name_len",
    "hal_storage_tier_2_name",
    "hal_storage_tier_2_name_len",
    "hal_storage_tier_3_name",
    "hal_storage_tier_3_name_len",
    "hal_storage_tier_4_name",
    "hal_storage_tier_4_name_len",
    "hal_storage_overlay_name_lo",
    "hal_storage_overlay_name_hi",
    "hal_storage_overlay_name_len",
    "hal_storage_overlay_start_name",
    "hal_storage_overlay_start_name_len",
    "hal_storage_overlay_town_name",
    "hal_storage_overlay_town_name_len",
    "hal_storage_overlay_death_name",
    "hal_storage_overlay_death_name_len",
    "hal_storage_overlay_gen_name",
    "hal_storage_overlay_gen_name_len",
    "hal_storage_overlay_help_name",
    "hal_storage_overlay_help_name_len",
    "hal_storage_overlay_ui_name",
    "hal_storage_overlay_ui_name_len",
    "hal_storage_overlay_items_name",
    "hal_storage_overlay_items_name_len",
)

PLATFORM_FILES = {
    "c64": ROOT / "commodore/c64/hal/storage.s",
    "c128": ROOT / "commodore/c128/hal/storage.s",
    "plus4": ROOT / "commodore/plus4/hal/storage.s",
}

OVERLAY_NAMES = {
    "c64": ("start", "town", "death", "gen", "help", "ui", "items", "spell"),
    "c128": ("start", "town", "death", "gen", "help", "ui", "items"),
    "plus4": ("start", "town", "death", "gen", "help", "ui", "items", "spell"),
}

TIER_NAMES = ("1", "2", "3", "4")


def expanded_source(path: Path) -> str:
    text = path.read_text(encoding="utf-8", errors="replace")
    chunks = [text]
    for match in re.finditer(r'(?m)^#import\s+"([^"]+)"', text):
        imported = path.parent / match.group(1)
        if imported.exists():
            chunks.append(expanded_source(imported))
    return "\n".join(chunks)


def exported_labels(path: Path) -> set[str]:
    text = expanded_source(path)
    labels: set[str] = set()
    for match in re.finditer(r"(?m)^([A-Za-z_][A-Za-z0-9_]*):", text):
        labels.add(match.group(1))
    for match in re.finditer(r"(?m)^\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text):
        labels.add(match.group(1))
    for match in re.finditer(r"(?m)^\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text):
        labels.add(match.group(1))
    return labels


def missing_length_terminators(path: Path, prefix: str, names: tuple[str, ...], table_label: str) -> list[str]:
    text = expanded_source(path)
    missing: list[str] = []
    for name in names:
        label = f"{prefix}_{name}_name"
        pattern = (
            rf"(?ms)^{label}:\s*"
            rf".*?^\.label\s+{label}_len\s*=\s*\*\s*-\s*{label}\s*"
            rf"(?P<after>.*?)(?=^{prefix}_[A-Za-z0-9_]+_name:|^{table_label}:)"
        )
        match = re.search(pattern, text)
        if not match:
            missing.append(f"{label}: missing length block")
            continue
        after = match.group("after")
        if not re.search(r"(?m)^\s*\.byte\s+0\s*(?://.*)?$", after):
            missing.append(f"{label}: missing display terminator after length label")
    return missing


def main() -> int:
    failed = False
    for platform, path in PLATFORM_FILES.items():
        if not path.exists():
            print(f"{platform}: missing {path.relative_to(ROOT)}")
            failed = True
            continue
        labels = exported_labels(path)
        missing = [label for label in REQUIRED_LABELS if label not in labels]
        if missing:
            print(f"{platform}: missing storage HAL exports in {path.relative_to(ROOT)}")
            for label in missing:
                print(f"  {label}")
            failed = True
        terminator_missing = missing_length_terminators(
            path,
            "hal_storage_tier",
            TIER_NAMES,
            "hal_storage_tier_name_lo",
        )
        if terminator_missing:
            print(f"{platform}: tier filename display terminator errors in {path.relative_to(ROOT)}")
            for item in terminator_missing:
                print(f"  {item}")
            failed = True
        terminator_missing = missing_length_terminators(
            path,
            "hal_storage_overlay",
            OVERLAY_NAMES[platform],
            "hal_storage_overlay_name_lo",
        )
        if terminator_missing:
            print(f"{platform}: overlay filename display terminator errors in {path.relative_to(ROOT)}")
            for item in terminator_missing:
                print(f"  {item}")
            failed = True

    if failed:
        return 1

    print(f"Storage HAL export check passed ({len(REQUIRED_LABELS)} labels x {len(PLATFORM_FILES)} platforms).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
