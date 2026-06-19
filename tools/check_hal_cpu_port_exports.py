#!/usr/bin/env python3
"""Verify C64-family CPU-port constants and common disk setup use."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_CONSTANTS = ("hal_memory_cpu_port",)
RAW_CPU_PORT_RE = re.compile(r"\b(?:inc|dec|lda|sta)\s+\$0*01\b", re.IGNORECASE)

PLATFORM_FILES = {
    "c64": ROOT / "platforms/commodore/c64/hal/memory_bank_consts.s",
    "c128": ROOT / "platforms/commodore/c128/hal/memory_bank_consts.s",
}

COMMON_CPU_PORT_USERS = {
    "disk_swap.s": ROOT / "platforms/commodore/common/disk_swap.s",
    "disk_setup_banked.s": ROOT / "platforms/commodore/common/disk_setup_banked.s",
    "item_actions_overlay.s": ROOT / "core/item_actions_overlay.s",
    "monster.s": ROOT / "core/monster.s",
    "overlay.s": ROOT / "platforms/commodore/common/overlay.s",
    "player_items.s": ROOT / "core/player_items.s",
    "reu.s": ROOT / "platforms/commodore/common/reu.s",
    "save.s": ROOT / "platforms/commodore/common/save.s",
    "tier_manager.s": ROOT / "core/tier_manager.s",
}


def exported_constants(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    return {
        match.group(1)
        for match in re.finditer(r"(?m)^\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text)
    }


def main() -> int:
    errors: list[str] = []
    for platform, path in PLATFORM_FILES.items():
        constants = exported_constants(path)
        for constant in REQUIRED_CONSTANTS:
            if constant not in constants:
                errors.append(f"{platform}: missing {constant} in {path.relative_to(ROOT)}")

    for name, path in COMMON_CPU_PORT_USERS.items():
        common_text = path.read_text(encoding="utf-8", errors="replace")
        for match in RAW_CPU_PORT_RE.finditer(common_text):
            errors.append(f"{name}: common CPU-port user still contains {match.group(0)}")
        if "hal_memory_cpu_port" not in common_text:
            errors.append(f"{name}: common CPU-port user does not consume hal_memory_cpu_port")

    if errors:
        print("HAL CPU-port export check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print("HAL CPU-port export check passed (1 constant x 2 platforms).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
