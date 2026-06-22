#!/usr/bin/env python3
"""Generate Kick Assembler include data from version.json."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def load_versions(path: Path) -> tuple[str, str, str]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError("version.json must be a JSON object")
    values: list[str] = []
    for platform in ("c64", "c128", "plus4"):
        value = raw.get(platform)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"version.json missing string version for {platform}")
        version = value.strip()
        if not version.lower().startswith("v"):
            version = f"v{version}"
        values.append(version)
    return values[0], values[1], values[2]


def screen_bytes(text: str) -> str:
    values: list[str] = []
    for ch in text.upper():
        code = ord(ch)
        if 65 <= code <= 90:
            code -= 64
        values.append(str(code))
    return ", ".join(values)


def cx16_screen_bytes(text: str) -> str:
    values: list[str] = []
    for ch in text:
        code = ord(ch)
        if 97 <= code <= 122:
            code -= 96
        values.append(str(code))
    return ", ".join(values)


def emit_include(dst: Path, c64_version: str, c128_version: str, plus4_version: str) -> None:
    cx16_version = c128_version.upper()
    text = f"""// Auto-generated from version.json. Do not edit by hand.
#if CX16
.const TITLE_VERSION_LEN = {len(cx16_version)}
.const TITLE_VERSION_SCREEN_LEN = {len(cx16_version)}
.macro EmitTitleVersion() {{
    .text "{cx16_version}"
}}
.macro EmitTitleVersionScreen() {{
    .byte {cx16_screen_bytes(cx16_version)}
}}
#elif C128
.const TITLE_VERSION_LEN = {len(c128_version)}
.const TITLE_VERSION_SCREEN_LEN = {len(c128_version)}
.macro EmitTitleVersion() {{
    .text "{c128_version}"
}}
.macro EmitTitleVersionScreen() {{
    .byte {screen_bytes(c128_version)}
}}
#elif PLUS4
.const TITLE_VERSION_LEN = {len(plus4_version)}
.const TITLE_VERSION_SCREEN_LEN = {len(plus4_version)}
.macro EmitTitleVersion() {{
    .text "{plus4_version}"
}}
.macro EmitTitleVersionScreen() {{
    .byte {screen_bytes(plus4_version)}
}}
#else
.const TITLE_VERSION_LEN = {len(c64_version)}
.const TITLE_VERSION_SCREEN_LEN = {len(c64_version)}
.macro EmitTitleVersion() {{
    .text "{c64_version}"
}}
.macro EmitTitleVersionScreen() {{
    .byte {screen_bytes(c64_version)}
}}
#endif
"""
    dst.write_text(text, encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <version.json> <out.inc>")
        return 1
    version_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    c64_version, c128_version, plus4_version = load_versions(version_path)
    emit_include(out_path, c64_version, c128_version, plus4_version)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
