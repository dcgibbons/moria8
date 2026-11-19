#!/usr/bin/env python3
"""The C64 scripted Detect Evil smoke's detection checks, from VICE dumps.

The product image holds no checking code (2026-11-13: it had taken the image
past MAP_BASE). The runner breaks at c64_test_detect_check_point (just after
the first successful prayer) and at c64_test_spell_pass_sym (after the
scripted rests), dumps the monster table and cr_mflags at each, and this
script reads those dumps out of the monitor log: at the check point an evil
monster must carry MF_DETECTED; at the pass none may (the marks expire).

Usage: c64_detect_evil_check.py <main.vs> <tty.log>
Exit 0 on pass; otherwise prints the failure and exits 1.
"""
import re
import sys

STOP = re.compile(r"\(Stop on +exec ([0-9a-fA-F]{4})\)")
DUMP = re.compile(r"^>C:([0-9a-fA-F]{4})((?:\s+[0-9a-fA-F]{2})+)")


def symbols(path: str) -> dict[str, int]:
    out = {}
    for line in open(path):
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "al":
            out[parts[2].lstrip(".")] = int(parts[1].split(":")[1], 16)
    return out


def dumps(log: str) -> dict[int, dict[int, int]]:
    """Memory read at each stop: stop address -> {address: byte}."""
    by_stop: dict[int, dict[int, int]] = {}
    stop = None
    for raw in open(log, errors="replace"):
        line = raw.strip()
        hit = STOP.search(line)
        if hit:
            stop = int(hit.group(1), 16)
            continue
        dump = DUMP.match(line)
        if dump and stop is not None:
            # A dump line is 16 bytes, then its PETSCII column; split the
            # hex pairs off the front only.
            values = re.findall(r"\b([0-9a-fA-F]{2})\b", dump.group(2))[:16]
            base = int(dump.group(1), 16)
            mem = by_stop.setdefault(stop, {})
            for i, value in enumerate(values):
                mem[base + i] = int(value, 16)
    return by_stop


def detected(mem: dict[int, int], sym: dict[str, int]) -> bool | None:
    """An evil monster marked detected; None when the dump is incomplete."""
    table, mflags = sym["monster_table"], sym["cr_mflags"]
    size, count = sym["c64_test_k_monster_entry_size"], sym["c64_test_k_max_monsters"]
    for slot in range(count):
        base = table + slot * size
        kind = mem.get(base + sym["c64_test_k_mx_type"])
        flags = mem.get(base + sym["c64_test_k_mx_flags"])
        if kind is None or flags is None:
            return None
        if kind == sym["c64_test_k_empty_slot"]:
            continue
        evil = mem.get(mflags + kind)
        if evil is None:
            return None
        if evil & sym["c64_test_k_cf_evil"] and flags & sym["c64_test_k_mf_detected"]:
            return True
    return False


def main() -> int:
    sym = symbols(sys.argv[1])
    seen = dumps(sys.argv[2])
    check, done = sym["c64_test_detect_check_point"], sym["c64_test_spell_pass_sym"]
    after_prayer = detected(seen.get(check, {}), sym)
    if after_prayer is not True:
        print("no evil monster detected after the prayer" if after_prayer is False
              else "no monster-table dump at the detection check point")
        return 1
    at_pass = detected(seen.get(done, {}), sym)
    if at_pass is not False:
        print("detection marks not cleared by the pass" if at_pass
              else "no monster-table dump at the pass trap")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
