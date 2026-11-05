#!/usr/bin/env python3
"""Check a C128 level's monsters against the monster catalog.

Reads a VICE monitor log holding, in order, memory dumps of: the monster
table, cat_slot_id_lo/hi, cr_level, cr_name_lo, cr_name_hi (Bank 0), then the
Bank 1 name pool. Checks that the level holds VMS's population (randint(8)
+ 14 + alloc_level, at least 15 placed on DL1), that every live monster's
species slot is loaded, that each slot's level is the catalog's, and that
its name in the Bank 1 pool, decoded at fetch from the Huffman-coded names,
is the catalog's (platforms/shared/catalog; docs/MONSTER_CATALOG_DESIGN.md).

usage: check_catalog128.py <monitor-log> <pool-base-hex> [min-monsters]

The C64 and Plus/4 catalog smokes use it too, with the population VMS's
count scales to on their 80x48 maps (5-7 on DL1) and the hidden name pool.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[4] / "platforms" / "shared" / "catalog"
SLOTS = 32
ENTRY = 12
LINE = re.compile(r"^>C:([0-9a-f]{4})  ", re.I)


def memory(log: str) -> list[dict[int, int]]:
    """One {address: byte} map per 'm' dump, split where addresses jump back."""
    dumps: list[dict[int, int]] = []
    last = None
    for line in log.splitlines():
        match = LINE.match(line)
        if not match:
            continue
        addr = int(match.group(1), 16)
        # The hex column is fixed (16 bytes, a gap every 4); the ASCII column
        # after it holds raw bytes, newlines included.
        values = [int(v, 16) for v in line[9:60].split()]
        if last is None or addr != last:
            dumps.append({})
        for k, value in enumerate(values):
            dumps[-1][addr + k] = value
        last = addr + len(values)
    return dumps


def catalog_levels() -> list[int]:
    text = (CATALOG / "catalog_fields.s").read_text()
    body = re.search(r"^cat_cr_level:\n((?:\s*\.byte[^\n]*\n)+)", text, re.M).group(1)
    return [int(v, 16) for v in re.findall(r"\$([0-9a-fA-F]{2})", body)]


def catalog_names() -> dict[int, list[int]]:
    out = {}
    for m in re.finditer(r"^catn_(\d+):.*// (.+?)\s*$", (CATALOG / "catalog_names.s").read_text(), re.M):
        out[int(m.group(1))] = [ord(c) - 0x60 if "a" <= c <= "z" else ord(c) for c in m.group(2)]
    return out


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 2
    min_live = int(sys.argv[3]) if len(sys.argv) == 4 else 15
    dumps = memory(Path(sys.argv[1]).read_text(errors="replace"))
    if len(dumps) < 6:
        print(f"FAIL: {len(dumps)} memory dumps in the log, 6 expected")
        return 1
    table, ids, levels, name_lo, name_hi, pool = (sorted(d.items()) for d in
                                                   dumps[:6])
    table, ids, levels = [v for _, v in table], [v for _, v in ids], [v for _, v in levels]
    name_lo, name_hi, pool_bytes = [v for _, v in name_lo], [v for _, v in name_hi], dict(pool)
    want_levels, want_names = catalog_levels(), catalog_names()
    live = [table[i * ENTRY + 2] for i in range(SLOTS) if table[i * ENTRY + 2] != 0xFF]
    errors = []
    if len(live) < min_live:
        errors.append(f"{len(live)} monsters, at least {min_live} expected on DL1")
    for kind in sorted(set(live)):
        if kind >= SLOTS or ids[SLOTS + kind] == 0xFF:
            errors.append(f"monster of type {kind}: no catalog species loaded")
            continue
        cid = ids[kind] | ids[SLOTS + kind] << 8
        if levels[kind] != want_levels[cid]:
            errors.append(f"slot {kind} id {cid}: level {levels[kind]}, catalog {want_levels[cid]}")
        ptr = name_lo[kind] | name_hi[kind] << 8
        got = [pool_bytes.get(ptr + k, -1) for k in range(len(want_names[cid]) + 1)]
        if got != want_names[cid] + [0]:
            errors.append(f"slot {kind} id {cid}: pool name {got} at ${ptr:04X}, catalog {want_names[cid]}")
    if errors:
        print("FAIL: " + "; ".join(errors))
        return 1
    print(f"PASS: {len(live)} monsters, {len(set(live))} catalog species, names and levels match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
