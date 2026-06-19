#!/usr/bin/env python3
"""Verify platform memory-bank constants and common compatibility boundary."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_CONSTANTS = (
    "hal_memory_has_cpu_port",
    "hal_memory_bank_all_ram",
    "hal_memory_bank_all_rom",
    "hal_memory_bank_no_basic",
    "hal_memory_bank_no_kernal",
    "hal_memory_bank_no_roms",
    "hal_huffman_lock_irq_during_decode",
    "hal_huffman_print_uses_cached_msg",
    "hal_memory_map_row_helper_enabled",
)
COMMON_ALIAS_CONSTANTS = tuple(
    constant
    for constant in REQUIRED_CONSTANTS
    if constant
    not in (
        "hal_memory_has_cpu_port",
        "hal_huffman_lock_irq_during_decode",
        "hal_huffman_print_uses_cached_msg",
        "hal_memory_map_row_helper_enabled",
    )
)

PLATFORM_FILES = {
    "c64": ROOT / "platforms/commodore/c64/hal/memory_bank_consts.s",
    "c128": ROOT / "platforms/commodore/c128/hal/memory_bank_consts.s",
    "plus4": ROOT / "platforms/commodore/plus4/hal/memory_bank_consts.s",
}

COMMON_ALIAS_FILE = ROOT / "platforms/commodore/common/bank_port_consts.s"
COMMON_HUFFMAN_FILE = ROOT / "core/huffman.s"
FORBIDDEN_COMMON_TOKENS = (
    "#if",
    "$30",
    "$37",
    "$36",
    "$35",
    "$34",
    "$01",
    "$00",
)


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

    common_text = COMMON_ALIAS_FILE.read_text(encoding="utf-8", errors="replace")
    common_lower = common_text.lower()
    for token in FORBIDDEN_COMMON_TOKENS:
        if token.lower() in common_lower:
            errors.append(f"bank_port_consts.s: common alias file still contains {token}")
    for constant in COMMON_ALIAS_CONSTANTS:
        if constant not in common_text:
            errors.append(f"bank_port_consts.s: common alias file does not consume {constant}")

    huffman_text = COMMON_HUFFMAN_FILE.read_text(encoding="utf-8", errors="replace")
    if re.search(r"(?m)^\s*#if[^\n]*\bC128\b", huffman_text):
        errors.append("huffman.s: common decoder still branches directly on C128")
    if "hal_huffman_lock_irq_during_decode" not in huffman_text:
        errors.append("huffman.s: common decoder does not consume hal_huffman_lock_irq_during_decode")
    if "hal_huffman_print_uses_cached_msg" not in huffman_text:
        errors.append("huffman.s: common decoder does not consume hal_huffman_print_uses_cached_msg")

    dungeon_los_text = (ROOT / "core/dungeon_los.s").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(r"(?m)^\s*#if[^\n]*\bC128\b", dungeon_los_text):
        errors.append("dungeon_los.s: common visibility code still branches directly on C128")
    if "hal_memory_map_row_helper_enabled" not in dungeon_los_text:
        errors.append("dungeon_los.s: common visibility code does not consume hal_memory_map_row_helper_enabled")

    if errors:
        print("HAL memory bank export check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print(
        "HAL memory bank export check passed "
        f"({len(REQUIRED_CONSTANTS)} constants x {len(PLATFORM_FILES)} platforms)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
