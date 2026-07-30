#!/usr/bin/env python3
"""make_pak.py — build MORIA8.PAK, the Apple IIe boot payload container.

Layout (see platforms/apple2/boot.s):
  byte 0      entry count
  byte 1      reserved (0)
  bytes 2..   count little-endian 16-bit entry lengths
  pad to 512
  entry payloads concatenated in the same order

Usage: make_pak.py OUT.PAK ENTRY [ENTRY ...]
Entry order must match boot.s file_table: RES, AUXDATA, TOWN, UI, ITEMS,
SPELL, MODAL, GEN.
"""

import sys
from pathlib import Path

HEADER_SIZE = 512


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
    if len(payloads) > 255:
        print("too many entries")
        return 1

    header = bytearray(HEADER_SIZE)
    header[0] = len(payloads)
    for i, (_, data) in enumerate(payloads):
        header[2 + i * 2] = len(data) & 0xFF
        header[3 + i * 2] = (len(data) >> 8) & 0xFF

    with out.open("wb") as f:
        f.write(header)
        for name, data in payloads:
            f.write(data)
    total = HEADER_SIZE + sum(len(d) for _, d in payloads)
    print(f"{out}: {len(payloads)} entries, {total} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
