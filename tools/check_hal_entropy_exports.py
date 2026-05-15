#!/usr/bin/env python3
"""Verify platform entropy HAL constants and common RNG boundary."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_CONSTANTS = (
    "hal_entropy_timer0_lo",
    "hal_entropy_timer0_hi",
    "hal_entropy_timer1_lo",
    "hal_entropy_timer1_hi",
)

PLATFORM_FILES = {
    "c64": ROOT / "commodore/c64/hal/entropy_consts.s",
    "c128": ROOT / "commodore/c128/hal/entropy_consts.s",
    "plus4": ROOT / "commodore/plus4/hal/entropy_consts.s",
}

RNG_COMMON = ROOT / "commodore/common/rng.s"
FORBIDDEN_RNG_TOKENS = (
    "$dc04",
    "$dc05",
    "$dd04",
    "$dd05",
    "$ff02",
    "$ff03",
    "$ff04",
    "$ff05",
    "#if PLUS4",
)


def exported_labels(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    labels: set[str] = set()
    for match in re.finditer(r"(?m)^\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text):
        labels.add(match.group(1))
    for match in re.finditer(r"(?m)^\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text):
        labels.add(match.group(1))
    return labels


def main() -> int:
    errors: list[str] = []
    for platform, path in PLATFORM_FILES.items():
        labels = exported_labels(path)
        for constant in REQUIRED_CONSTANTS:
            if constant not in labels:
                errors.append(f"{platform}: missing {constant} in {path.relative_to(ROOT)}")

    rng_text = RNG_COMMON.read_text(encoding="utf-8", errors="replace").lower()
    for token in FORBIDDEN_RNG_TOKENS:
        if token.lower() in rng_text:
            errors.append(f"rng.s: common RNG still contains {token}")
    for constant in REQUIRED_CONSTANTS:
        if constant not in rng_text:
            errors.append(f"rng.s: common RNG does not consume {constant}")

    if errors:
        print("HAL entropy export check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print(
        "HAL entropy export check passed "
        f"({len(REQUIRED_CONSTANTS)} constants x {len(PLATFORM_FILES)} platforms)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
