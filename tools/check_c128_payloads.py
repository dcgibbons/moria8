#!/usr/bin/env python3
"""Check the C128's built payloads against each other and Bank 1's owners.

Reads every ``.segmentdef`` in platforms/commodore/c128/main.s that writes a
PRG, and that PRG's real load address and length from the build directory:

- each payload loads at its segment's start and ends at or below its max;
- the resident Bank 0 payloads' segment windows, and their actual bytes, are
  pairwise disjoint (the $E000 overlays, and the persist/play pair at $AF00,
  replace one another by design and are only checked against the rest);
- the Bank 1 item-names payload lies inside BANK1_DB_BASE..BANK1_DB_END and
  ends before BANK1_TIER_CACHE_BASE (memory128.s).

The bytes a payload emits, not a label beside them: on 2026-10-26 the names
payload ran into the tier cache and 128.item over 128.select while asserts on
end labels passed (docs/C128_MEMORY_CONTRACT.md).

Usage: check_c128_payloads.py [--both | build/c128]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "platforms" / "commodore" / "c128" / "main.s"
MEMORY = ROOT / "platforms" / "commodore" / "c128" / "memory128.s"

SEGMENTDEF = re.compile(r'^\.segmentdef\s+(\w+)\s+\[outPrg=OVL_OUT \+ "/([\w.]+)",\s*start=\$([0-9a-fA-F]+),'
                        r'\s*min=\$[0-9a-fA-F]+,\s*max=\$([0-9a-fA-F]+)\]')
CONST = re.compile(r"^\.const\s+(\w+)\s*=\s*\$([0-9a-fA-F]+)\b")

BANK1 = {"C128ResidentItemNames", "C128Bank1Huffman", "C128Bank1HuffmanVector", "C128Bank1Catalog",
         "C128Bank1CatalogNames"}
ALTERNATES = [{"C128ResidentPersist", "C128ResidentPlay"}]   # one or the other at $AF00
OVERLAY_START = 0xE000                                        # every overlay shares $E000-$EFFF


def segments(main: Path = MAIN) -> dict[str, tuple[str, int, int]]:
    """Segment name -> (PRG file, start, max). A PRG-writing .segmentdef the
    pattern cannot read is an error, not a segment silently left out."""
    out = {}
    for line in main.read_text().splitlines():
        line = line.strip()
        if not (line.startswith(".segmentdef") and "outPrg=" in line):
            continue
        match = SEGMENTDEF.match(line)
        if not match:
            raise ValueError(f"cannot read {line!r}: check_c128_payloads.SEGMENTDEF needs updating")
        out[match.group(1)] = (match.group(2), int(match.group(3), 16), int(match.group(4), 16))
    return out


def consts(memory: Path = MEMORY) -> dict[str, int]:
    return {m.group(1): int(m.group(2), 16)
            for m in map(CONST.match, memory.read_text().splitlines()) if m}


def prg_span(path: Path) -> tuple[int, int]:
    """(load address, last byte's address) of a PRG."""
    data = path.read_bytes()
    load = data[0] | data[1] << 8
    return load, load + len(data) - 3


def overlaps(a: tuple[int, int], b: tuple[int, int]) -> bool:
    return a[0] <= b[1] and b[0] <= a[1]


def check(build: Path, segs: dict[str, tuple[str, int, int]], mem: dict[str, int]) -> list[str]:
    errors = []
    spans = {}
    for name, (prg, start, end_max) in segs.items():
        path = build / prg
        if not path.exists():
            errors.append(f"{name}: {path} not built")
            continue
        load, last = prg_span(path)
        spans[name] = (load, last)
        if load != start:
            errors.append(f"{name}: {prg} loads at ${load:04X}, its segment starts at ${start:04X}")
        if last > end_max:
            errors.append(f"{name}: {prg} ends at ${last:04X}, past its segment max ${end_max:04X}")
    resident = sorted(n for n in segs if n not in BANK1 and segs[n][1] != OVERLAY_START)
    for i, a in enumerate(resident):
        for b in resident[i + 1:]:
            if any({a, b} <= group for group in ALTERNATES):
                continue
            windows = (segs[a][1], segs[a][2]), (segs[b][1], segs[b][2])
            if overlaps(*windows):
                errors.append(f"{a} ${windows[0][0]:04X}-${windows[0][1]:04X} and {b} "
                              f"${windows[1][0]:04X}-${windows[1][1]:04X}: segment windows overlap")
            if a in spans and b in spans and overlaps(spans[a], spans[b]):
                errors.append(f"{a} ${spans[a][0]:04X}-${spans[a][1]:04X} and {b} "
                              f"${spans[b][0]:04X}-${spans[b][1]:04X}: payloads overlap")
    main_prg = build / "moria128.prg"
    if main_prg.exists():
        main_span = prg_span(main_prg)
        if main_span[0] != 0x1C01:
            errors.append(f"Default: moria128.prg loads at ${main_span[0]:04X}, expected $1C01")
        if main_span[1] > 0xAEFF:
            errors.append(f"Default: moria128.prg ends at ${main_span[1]:04X}, past Bank 0 resident max $AEFF")
        for other in resident:
            if other != "RuntimeLowData" and overlaps((0x1C01, 0xAEFF), (segs[other][1], segs[other][2])):
                errors.append(f"Default $1C01-$AEFF and {other} "
                              f"${segs[other][1]:04X}-${segs[other][2]:04X}: segment windows overlap")
            if other in spans and overlaps(main_span, spans[other]):
                errors.append(f"Default ${main_span[0]:04X}-${main_span[1]:04X} and {other} "
                              f"${spans[other][0]:04X}-${spans[other][1]:04X}: payloads overlap")
    names = spans.get("C128ResidentItemNames")
    if names:
        if names[0] < mem["BANK1_DB_BASE"] or names[1] > mem["BANK1_DB_END"]:
            errors.append(f"128.names ${names[0]:04X}-${names[1]:04X} leaves the Bank 1 DB region "
                          f"${mem['BANK1_DB_BASE']:04X}-${mem['BANK1_DB_END']:04X}")
        if names[1] >= mem["BANK1_TIER_CACHE_BASE"]:
            errors.append(f"128.names ends at ${names[1]:04X}, inside the tier cache "
                          f"(${mem['BANK1_TIER_CACHE_BASE']:04X})")
    return errors


def check_one(build: Path, segs: dict[str, tuple[str, int, int]], mem: dict[str, int]) -> bool:
    errors = check(build, segs, mem)
    for error in errors:
        print(f"check_c128_payloads ({build.name}): {error}")
    print(f"check_c128_payloads ({build.name}):", "FAIL" if errors else f"PASS ({len(segs)} payloads)")
    return not errors


def main(argv: list[str]) -> int:
    segs = segments()
    mem = consts()
    if len(argv) == 2 and argv[1] == "--both":
        targets = [ROOT / "build" / "c128", ROOT / "build" / "c128-cart"]
        ok = all([check_one(target, segs, mem) for target in targets])
        return 0 if ok else 1
    build = Path(argv[1]) if len(argv) > 1 else ROOT / "build" / "c128"
    return 0 if check_one(build, segs, mem) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
