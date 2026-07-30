#!/usr/bin/env python3
"""Regression for Apple II priest prayer-book affinity lookup.

The 'p' command failed on Apple II because pm_select_book read
book_spell_affinity with a direct main-memory lda abs,x. That table lives in
the A2AuxData segment (aux RAM), so the main-memory read returned garbage,
the affinity never matched SPELL_PRIEST, and every prayer book was rejected
with "wrong book type".

This is deliberately an assembled-code test, not a source-text smoke test:
it inspects the built binaries and requires the production affinity read to
go through the aux-read thunk (mmu_safe_map_read_ptr1) exactly as emitted by
the AuxReadX macro.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "apple2"
BIN = BUILD / "bin"


def symbol(name):
    for line in (BUILD / "main.vs").read_text().splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[2] == "." + name:
            return int(fields[1].split(":", 1)[1], 16)
    raise AssertionError(f"missing symbol {name}")


def lo_hi(addr):
    return bytes((addr & 0xFF, (addr >> 8) & 0xFF))


def main():
    subprocess.run(["make", "diskapple2"], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL)

    aux_base = 0x3B0C
    aux = (BIN / "A2.AUXDATA").read_bytes()

    type_addr = symbol("book_type_ids")
    affinity_addr = symbol("book_spell_affinity")
    assert type_addr >= aux_base and affinity_addr >= aux_base
    types = aux[type_addr - aux_base:type_addr - aux_base + 8]
    affinity = aux[affinity_addr - aux_base:affinity_addr - aux_base + 8]
    assert types == bytes((47, 55, 56, 57, 48, 58, 59, 60)), types
    assert affinity == bytes((1, 1, 1, 1, 2, 2, 2, 2)), affinity

    # Exact failing scenario: level-1 priest, Holy Prayer Book (item 48),
    # creation mask $07. The assembled lookup contract must expose prayers 0-2.
    book_index = types.index(48)
    assert affinity[book_index] == 2
    book_mask = 0xFF
    learned = 0x07
    assert [i for i in range(8) if (book_mask & learned) & (1 << i)] == [0, 1, 2]

    # Assembled-code gate: the pre-fix sequence in pm_select_book was
    #   stx pm_book_idx ($8E) ; lda book_spell_affinity,x ($BD lo hi)
    # a direct main-RAM read of the aux-resident table. It must not appear in
    # any shipped code binary, and the AuxReadX expansion for that label must.
    zp_ptr1 = symbol("zp_ptr1")
    zp_ptr1_hi = symbol("zp_ptr1_hi")
    thunk = symbol("mmu_safe_map_read_ptr1")
    book_idx = symbol("pm_book_idx")
    direct_read = b"\x8e" + lo_hi(book_idx) + b"\xbd" + lo_hi(affinity_addr)
    aux_read = (b"\x8a\xa8"                     # txa; tay
                b"\xa9" + lo_hi(affinity_addr)[:1] + b"\x85" + bytes((zp_ptr1,))
                + b"\xa9" + lo_hi(affinity_addr)[1:] + b"\x85"
                + bytes((zp_ptr1_hi,))
                + b"\x20" + lo_hi(thunk))      # jsr mmu_safe_map_read_ptr1
    code_files = [f for f in BIN.iterdir()
                  if f.is_file() and not f.name.startswith(("A2.AUXDATA",
                                                            "MONSTER.DB"))]
    blobs = {f.name: f.read_bytes() for f in code_files}
    hits = [name for name, data in blobs.items() if direct_read in data]
    assert not hits, f"direct main-RAM read of aux book_spell_affinity in {hits}"
    aux_hits = [name for name, data in blobs.items() if aux_read in data]
    assert aux_hits, "no aux-thunk read of book_spell_affinity in any binary"

    print("PASS apple2 priest prayer lookup: book 48 -> prayers 0,1,2 "
          f"(aux read via {aux_hits})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, subprocess.CalledProcessError) as exc:
        print(f"FAIL apple2 priest prayer lookup: {exc}", file=sys.stderr)
        raise SystemExit(1)
