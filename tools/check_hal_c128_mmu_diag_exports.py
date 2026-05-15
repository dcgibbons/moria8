#!/usr/bin/env python3
"""Verify C128 MMU diagnostic constants used by common REU preload traps."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_CONSTANTS = (
    "hal_memory_mmu_config_register",
    "hal_memory_mmu_preconfig_a",
)

C128_MEMORY_CONSTS = ROOT / "commodore/c128/hal/memory_bank_consts.s"
COMMON_REU = ROOT / "commodore/common/reu.s"
FORBIDDEN_COMMON_TOKENS = ("$ff00", "$d501")


def exported_constants(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    return {
        match.group(1)
        for match in re.finditer(r"(?m)^\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text)
    }


def main() -> int:
    errors: list[str] = []
    constants = exported_constants(C128_MEMORY_CONSTS)
    for constant in REQUIRED_CONSTANTS:
        if constant not in constants:
            errors.append(f"c128: missing {constant} in {C128_MEMORY_CONSTS.relative_to(ROOT)}")

    common_text = COMMON_REU.read_text(encoding="utf-8", errors="replace")
    common_lower = common_text.lower()
    for token in FORBIDDEN_COMMON_TOKENS:
        if token in common_lower:
            errors.append(f"reu.s: common REU still contains {token}")
    for constant in REQUIRED_CONSTANTS:
        if constant not in common_text:
            errors.append(f"reu.s: common REU does not consume {constant}")

    if errors:
        print("HAL C128 MMU diagnostic export check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print(
        "HAL C128 MMU diagnostic export check passed "
        f"({len(REQUIRED_CONSTANTS)} constants x 1 platform)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
