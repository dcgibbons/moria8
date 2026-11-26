#!/usr/bin/env python3
"""Generate Kick Assembler include data from version.json."""

from __future__ import annotations

import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))
import version_info  # noqa: E402


def load_versions(path: Path) -> dict[str, str]:
    resolved = version_info.resolve_versions(
        path,
        ports=("c64", "c128", "plus4", "apple2", "cx16", "atari8", "bbcmaster"),
    )
    return {p: pv.display for p, pv in resolved.ports.items()}


def emit_include(dst: Path, versions: dict[str, str]) -> None:
    text = f"""#importonce
// Auto-generated from version.json. Do not edit by hand.
#if !VERSION_STRINGS_INCLUDED
#define VERSION_STRINGS_INCLUDED
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
#endif
"""
    version_info.atomic_write_if_changed(dst, text)


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
