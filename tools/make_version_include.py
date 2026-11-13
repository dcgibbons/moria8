#!/usr/bin/env python3
"""Generate Kick Assembler include data from version.json."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def load_versions(path: Path) -> dict[str, str]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError("version.json must be a JSON object")
    versions: dict[str, str] = {}
    for platform in ("c64", "c128", "plus4", "apple2", "cx16", "atari8", "bbcmaster"):
        value = raw.get(platform)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"version.json missing string version for {platform}")
        version = value.strip()
        if not version.lower().startswith("v"):
            version = f"v{version}"
        versions[platform] = version
    return versions


def emit_include(dst: Path, versions: dict[str, str]) -> None:
    text = f"""// Auto-generated from version.json. Do not edit by hand.
#if C128
.const TITLE_VERSION_LEN = {len(versions["c128"])}
.macro EmitTitleVersion() {{
    .text "{versions["c128"]}"
}}
#elif PLUS4
.const TITLE_VERSION_LEN = {len(versions["plus4"])}
.macro EmitTitleVersion() {{
    .text "{versions["plus4"]}"
}}
#elif APPLE2
.const TITLE_VERSION_LEN = {len(versions["apple2"])}
.macro EmitTitleVersion() {{
    .text "{versions["apple2"]}"
}}
#elif CX16
.const TITLE_VERSION_LEN = {len(versions["cx16"])}
.macro EmitTitleVersion() {{
    .text "{versions["cx16"]}"
}}
#elif ATARI8
.const TITLE_VERSION_LEN = {len(versions["atari8"])}
.macro EmitTitleVersion() {{
    .text "{versions["atari8"]}"
}}
#elif BBCMASTER
.const TITLE_VERSION_LEN = {len(versions["bbcmaster"])}
.macro EmitTitleVersion() {{
    .text "{versions["bbcmaster"]}"
}}
#else
.const TITLE_VERSION_LEN = {len(versions["c64"])}
.macro EmitTitleVersion() {{
    .text "{versions["c64"]}"
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
    versions = load_versions(version_path)
    emit_include(out_path, versions)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
