#!/usr/bin/env python3
"""
tools/check_overlay_fallthrough.py
Module ownership: platform-tooling static check for code that runs off the end
of a segment.

Flags a ``:Macro()`` expansion that is the last code before a ``.segment``
switch or an ``*_end:`` label (the end of an overlay or other code region)
when the macro's body does not end in ``rts``/``rti``/``jmp``/``bra``: the CPU
runs on into whatever bytes follow the region. 2026-11-15: 708f3df moved
InvAddCarriedBody's ``rts`` out to its callers, the BBC and Apple IIe overlay
copies got none, and every store buy ran past OVL.TOWN's end and panicked.

``--selftest`` runs synthetic fixtures.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
SKIP_PARTS = {"build", "var", "tools", "tests", ".git"}

MACRO_START = re.compile(r"\s*\.macro\s+(\w+)\s*\(")
EXPANSION = re.compile(r"\s*:(\w+)\(")
TERMINATOR = re.compile(r"^(rts|rti|jmp|bra|brl)\b", re.IGNORECASE)
REGION_END = re.compile(r"^(\.segment\b|\w*_end:)")


def code_line(line: str) -> str:
    return re.sub(r"//.*", "", line).strip()


def macro_last_instructions(sources: Iterable[Tuple[str, List[str]]]) -> Dict[str, str]:
    """Each code macro's last instruction ('' for one holding none: a
    segment switch or data macro, never flagged)."""
    last: Dict[str, str] = {}
    for _, lines in sources:
        i = 0
        while i < len(lines):
            match = MACRO_START.match(lines[i])
            if not match:
                i += 1
                continue
            depth = lines[i].count("{") - lines[i].count("}")
            body: List[str] = []
            i += 1
            while i < len(lines) and depth > 0:
                depth += lines[i].count("{") - lines[i].count("}")
                body.append(lines[i])
                i += 1
            instructions = [c for c in map(code_line, body)
                            if c and c != "}" and not c.endswith(":") and not c.startswith(("#", "."))]
            last[match.group(1)] = instructions[-1] if instructions else ""
    return last


def findings(sources: List[Tuple[str, List[str]]]) -> List[str]:
    last = macro_last_instructions(sources)
    found: List[str] = []
    for name, lines in sources:
        for n, line in enumerate(lines):
            match = EXPANSION.match(line)
            if not match or not last.get(match.group(1)) or TERMINATOR.match(last[match.group(1)]):
                continue
            following = next((c for c in map(code_line, lines[n + 1:]) if c), "")
            if REGION_END.match(following):
                found.append(f"{name}:{n + 1}: :{match.group(1)}() ends in '{last[match.group(1)]}', "
                             f"then '{following}': the CPU runs past the region's end")
    return found


def repo_sources() -> List[Tuple[str, List[str]]]:
    paths = sorted(p for p in REPO_ROOT.rglob("*.s") if not SKIP_PARTS & set(p.relative_to(REPO_ROOT).parts))
    return [(str(p.relative_to(REPO_ROOT)), p.read_text(encoding="utf-8", errors="replace").splitlines())
            for p in paths]


def selftest() -> int:
    body = ".macro Body() {\n    jsr work\n    bcs !done+\n    clc\n!done:\n%s}\n"
    cases = [
        ("runs off an overlay's end", body % "", "x:\n    :Body()\novl_town_end:\n", 1),
        ("runs into a segment switch", body % "", "x:\n    :Body()\n.segment Default\n", 1),
        ("returns itself", body % "    rts\n", "x:\n    :Body()\novl_town_end:\n", 0),
        ("its caller returns", body % "", "x:\n    :Body()\n    rts\novl_town_end:\n", 0),
        ("a jump ends it", body % "    jmp elsewhere\n", "x:\n    :Body()\n.segment Default\n", 0),
        ("a data macro", ".macro Table() {\n    .byte 1, 2\n}\n", "    :Table()\n.segment Default\n", 0),
    ]
    failed = 0
    for what, macro, use, want in cases:
        got = len(findings([("m.s", macro.splitlines()), ("u.s", use.splitlines())]))
        status = "PASS" if got == want else "FAIL"
        failed += got != want
        print(f"{status} {what}: {got} finding(s), want {want}")
    return 1 if failed else 0


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    found = findings(repo_sources())
    for line in found:
        print(line)
    print(f"check_overlay_fallthrough: {len(found)} finding(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
