#!/usr/bin/env python3
"""Verify platform sound constants and common SID sound boundary."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_CONSTANTS = ("hal_sound_sid_base",)

PLATFORM_FILES = {
    "c64": ROOT / "commodore/c64/hal/sound_consts.s",
    "c128": ROOT / "commodore/c128/hal/sound_consts.s",
}

COMMON_SOUND = ROOT / "commodore/common/sound.s"
FORBIDDEN_COMMON_TOKENS = ("$d400",)


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

    common_text = COMMON_SOUND.read_text(encoding="utf-8", errors="replace")
    common_lower = common_text.lower()
    for token in FORBIDDEN_COMMON_TOKENS:
        if token in common_lower:
            errors.append(f"sound.s: common sound still contains {token}")
    for constant in REQUIRED_CONSTANTS:
        if constant not in common_text:
            errors.append(f"sound.s: common sound does not consume {constant}")

    if errors:
        print("HAL sound export check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print(
        "HAL sound export check passed "
        f"({len(REQUIRED_CONSTANTS)} constant x {len(PLATFORM_FILES)} SID platforms)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
