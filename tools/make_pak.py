#!/usr/bin/env python3
"""make_pak.py — build MORIA8.PAK, the Apple IIe boot payload container.

Layout (see platforms/apple2/boot.s):
  byte 0      entry count (<= 42; lengths + 24-bit offsets fit in 256-byte prefix)
  byte 1      reserved (0)
  bytes 2..   count little-endian 16-bit entry lengths
  bytes 128.. count little-endian 24-bit byte offsets from start of MORIA8.PAK
  pad to 512
  entry payloads concatenated in the same order

Usage: make_pak.py OUT.PAK ENTRY [ENTRY ...]
Boot entries 0..7 must match platforms/apple2/boot.s file_table:
MORIA8.RES, A2.AUXDATA, A2.CATALOG, OVL.UI, OVL.ITEMS, OVL.SPELL, OVL.MODAL,
A2.HUFFDATA. Additional cold entries (8+) are read via MLI_SET_MARK ($CE).
"""

import sys
from pathlib import Path

HEADER_SIZE = 512
OFFSET_TABLE_BASE = 128
MAX_ENTRIES = (256 - OFFSET_TABLE_BASE) // 3


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    out = Path(sys.argv[1])
    payloads = []
    for name in sys.argv[2:]:
        data = Path(name).read_bytes()
        if len(data) > 0xFFFF:
            print(f"{name}: entry too large ({len(data)} bytes)")
            return 1
        payloads.append((name, data))
    if len(payloads) > MAX_ENTRIES:
        print(f"too many entries ({len(payloads)} > {MAX_ENTRIES})")
        return 1

    header = bytearray(HEADER_SIZE)
    header[0] = len(payloads)
    offset = HEADER_SIZE
    for i, (_, data) in enumerate(payloads):
        header[2 + i * 2] = len(data) & 0xFF
        header[3 + i * 2] = (len(data) >> 8) & 0xFF
        off_pos = OFFSET_TABLE_BASE + i * 3
        header[off_pos] = offset & 0xFF
        header[off_pos + 1] = (offset >> 8) & 0xFF
        header[off_pos + 2] = (offset >> 16) & 0xFF
        offset += len(data)

    with out.open("wb") as f:
        f.write(header)
        for name, data in payloads:
            f.write(data)
    total = HEADER_SIZE + sum(len(d) for _, d in payloads)
    print(f"{out}: {len(payloads)} entries, {total} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
