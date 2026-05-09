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
    "hal_storage_require_program_media",
    "hal_storage_require_save_media",
    "hal_storage_marker_present",
    "hal_storage_marker_init",
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
    "hal_storage_save_record",
    "hal_storage_load_record",
    "hal_storage_save_probe_name",
    "hal_storage_save_probe_name_len",
    "hal_storage_save_read_name",
    "hal_storage_save_read_name_len",
    "hal_storage_save_write_name",
    "hal_storage_save_write_name_len",
    "hal_storage_init_command",
    "hal_storage_marker_magic",
    "hal_storage_marker_magic_len",
    "hal_storage_marker_read_name",
    "hal_storage_marker_read_name_len",
    "hal_storage_marker_write_name",
    "hal_storage_marker_write_name_len",
    "hal_storage_marker_scratch_name",
    "hal_storage_marker_scratch_name_len",
)

PLATFORM_FILES = {
    "c64": ROOT / "commodore/c64/hal/storage.s",
    "c128": ROOT / "commodore/c128/hal/storage.s",
    "plus4": ROOT / "commodore/plus4/hal/storage.s",
}


def exported_labels(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    labels: set[str] = set()
    for match in re.finditer(r"(?m)^([A-Za-z_][A-Za-z0-9_]*):", text):
        labels.add(match.group(1))
    for match in re.finditer(r"(?m)^\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text):
        labels.add(match.group(1))
    return labels


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

    if failed:
        return 1

    print(f"Storage HAL export check passed ({len(REQUIRED_LABELS)} labels x {len(PLATFORM_FILES)} platforms).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
