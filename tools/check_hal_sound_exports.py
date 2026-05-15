#!/usr/bin/env python3
"""Verify platform sound constants and common SID sound boundary."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_CONSTANTS = ("hal_sound_sid_base",)
REQUIRED_SERVICES = (
    "hal_sound_init",
    "hal_sound_play",
    "hal_sound_stop",
    "hal_sound_update",
)

SID_PLATFORM_FILES = {
    "c64": ROOT / "commodore/c64/hal/sound_consts.s",
    "c128": ROOT / "commodore/c128/hal/sound_consts.s",
}
SOUND_IMPL_FILES = {
    "sid": ROOT / "commodore/common/sound.s",
    "plus4": ROOT / "commodore/plus4/sound.s",
}

COMMON_SOUND = ROOT / "commodore/common/sound.s"
COMMON_SOURCE_ROOT = ROOT / "commodore/common"
FORBIDDEN_COMMON_TOKENS = ("$d400",)
FORBIDDEN_COMMON_CALLS = (
    "jsr sound_init",
    "jmp sound_init",
    "jsr sound_play",
    "jmp sound_play",
)


def exported_constants(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    return {
        match.group(1)
        for match in re.finditer(r"(?m)^\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text)
    }


def exported_symbols(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    symbols: set[str] = set()
    for match in re.finditer(r"(?m)^([A-Za-z_][A-Za-z0-9_]*):", text):
        symbols.add(match.group(1))
    for match in re.finditer(r"(?m)^\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text):
        symbols.add(match.group(1))
    return symbols


def main() -> int:
    errors: list[str] = []
    for platform, path in SID_PLATFORM_FILES.items():
        constants = exported_constants(path)
        for constant in REQUIRED_CONSTANTS:
            if constant not in constants:
                errors.append(f"{platform}: missing {constant} in {path.relative_to(ROOT)}")

    for implementation, path in SOUND_IMPL_FILES.items():
        symbols = exported_symbols(path)
        for service in REQUIRED_SERVICES:
            if service not in symbols:
                errors.append(f"{implementation}: missing {service} in {path.relative_to(ROOT)}")

    common_text = COMMON_SOUND.read_text(encoding="utf-8", errors="replace")
    common_lower = common_text.lower()
    for token in FORBIDDEN_COMMON_TOKENS:
        if token in common_lower:
            errors.append(f"sound.s: common sound still contains {token}")
    for constant in REQUIRED_CONSTANTS:
        if constant not in common_text:
            errors.append(f"sound.s: common sound does not consume {constant}")
    for path in sorted(COMMON_SOURCE_ROOT.glob("*.s")):
        if path == COMMON_SOUND:
            continue
        text = path.read_text(encoding="utf-8", errors="replace").lower()
        for token in FORBIDDEN_COMMON_CALLS:
            if token in text:
                errors.append(
                    f"{path.relative_to(ROOT)}: common gameplay still calls {token}"
                )

    if errors:
        print("HAL sound export check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print(
        "HAL sound export check passed "
        f"({len(REQUIRED_CONSTANTS)} constant x {len(SID_PLATFORM_FILES)} SID platforms, "
        f"{len(REQUIRED_SERVICES)} services x {len(SOUND_IMPL_FILES)} implementations)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
