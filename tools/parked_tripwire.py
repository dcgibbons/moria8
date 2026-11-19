#!/usr/bin/env python3
"""Breakpoints that catch a C64 unit test running code it parked out of reach.

Tight unit tests link modules they do not exercise into segments that are
never executable: the $D000 I/O hole, or above MAP_BASE ($C000) past the end
of the loaded PRG (RAM under the KERNAL that holds nothing at run time). A
call into such a module runs I/O or KERNAL ROM bytes instead, and the test
fails somewhere else, or not at all: test_monster_magic's spell messages ran
KERNAL bytes for weeks, until a layout shift turned them into a crash
(2026-11-13).

Prints one ``$ADDR label`` line per parked entry point: a parked label that
the loaded program calls or jumps to (JSR, JMP or JMP indirect operands in
the PRG). Data labels are left out, since only execution is the bug, and a
parked variable can share its address with KERNAL code that runs every IRQ.

Usage: parked_tripwire.py <test.prg> <test.vs>
"""
import sys

IO_HOLE = range(0xD000, 0xE000)
MAP_BASE = 0xC000
CALL_OPCODES = (0x20, 0x4C, 0x6C)   # JSR abs, JMP abs, JMP (ind)


def main() -> int:
    prg_path, vs_path = sys.argv[1], sys.argv[2]
    data = open(prg_path, "rb").read()
    load = data[0] | data[1] << 8
    body = data[2:]
    end = load + len(body)
    labels: dict[int, str] = {}
    for line in open(vs_path):
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "al":
            addr = int(parts[1].split(":")[1], 16)
            parked = addr in IO_HOLE or (addr >= MAP_BASE and addr >= end)
            if parked:
                labels.setdefault(addr, parts[2].lstrip("."))
    targets = set()
    for i in range(len(body) - 2):
        if body[i] in CALL_OPCODES:
            target = body[i + 1] | body[i + 2] << 8
            if target in labels:
                targets.add(target)
    for addr in sorted(targets):
        print(f"${addr:04X} {labels[addr]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
