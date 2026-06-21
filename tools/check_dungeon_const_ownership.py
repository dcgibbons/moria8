#!/usr/bin/env python3
"""Guard shared dungeon-domain constants against platform-local copies."""

from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
OWNER = ROOT / "core" / "dungeon_consts.s"
CONST_RE = re.compile(r"^\s*\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=")
COMMENT_RE = re.compile(r"//.*$")

CHECK_PATHS = (
    ROOT / "core" / "dungeon_data.s",
    ROOT / "core" / "dungeon_feature_gen.s",
)


def strip_comment(line: str) -> str:
    return COMMENT_RE.sub("", line)


def read_owned_names() -> set[str]:
    names: set[str] = set()
    for raw_line in OWNER.read_text(encoding="utf-8", errors="replace").splitlines():
        match = CONST_RE.match(strip_comment(raw_line))
        if match:
            names.add(match.group(1))
    if not names:
        raise SystemExit(f"No shared dungeon constants found in {OWNER.relative_to(ROOT)}")
    return names


def scan_sources() -> list[Path]:
    sources = list(CHECK_PATHS)
    sources.extend(sorted((ROOT / "platforms" / "cx16").rglob("*.s")))
    return [source for source in sources if source != OWNER]


def main() -> int:
    owned_names = read_owned_names()
    errors: list[str] = []

    for source in scan_sources():
        text = source.read_text(encoding="utf-8", errors="replace")
        for line_number, raw_line in enumerate(text.splitlines(), start=1):
            match = CONST_RE.match(strip_comment(raw_line))
            if match and match.group(1) in owned_names:
                errors.append(
                    f"{source.relative_to(ROOT)}:{line_number}: "
                    f"redefines shared dungeon constant {match.group(1)}"
                )

    if errors:
        print("Dungeon constant ownership check failed:")
        for error in errors:
            print(f"  {error}")
        print(f"Move these definitions to, or import them from, {OWNER.relative_to(ROOT)}.")
        return 1

    print(f"Dungeon constant ownership check passed ({len(owned_names)} owned constants).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
