#!/usr/bin/env python3
"""Verify platform REU register constants and common REU ownership."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_CONSTANTS = (
    "hal_memory_reu_status",
    "hal_memory_reu_command",
    "hal_memory_reu_c64lo",
    "hal_memory_reu_c64hi",
    "hal_memory_reu_reulo",
    "hal_memory_reu_reuhi",
    "hal_memory_reu_bank",
    "hal_memory_reu_lenlo",
    "hal_memory_reu_lenhi",
    "hal_memory_reu_irqmask",
    "hal_memory_reu_control",
)

PLATFORM_FILES = {
    "c64": ROOT / "commodore/c64/hal/memory_bank_consts.s",
    "c128": ROOT / "commodore/c128/hal/memory_bank_consts.s",
}

COMMON_REU = ROOT / "commodore/common/reu.s"
FORBIDDEN_COMMON_TOKENS = (
    "$df00",
    "$df01",
    "$df02",
    "$df03",
    "$df04",
    "$df05",
    "$df06",
    "$df07",
    "$df08",
    "$df09",
    "$df0a",
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

    common_text = COMMON_REU.read_text(encoding="utf-8", errors="replace")
    common_lower = common_text.lower()
    for token in FORBIDDEN_COMMON_TOKENS:
        if token in common_lower:
            errors.append(f"reu.s: common REU still contains {token}")
    for constant in REQUIRED_CONSTANTS:
        if constant not in common_text:
            errors.append(f"reu.s: common REU does not consume {constant}")

    if errors:
        print("HAL REU export check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print(
        "HAL REU export check passed "
        f"({len(REQUIRED_CONSTANTS)} constants x {len(PLATFORM_FILES)} platforms)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
