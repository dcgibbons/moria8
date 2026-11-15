#!/usr/bin/env python3
"""Verify the 34-slot Save V2 inventory payload in a Plus/4 THE.GAME SEQ save."""

import sys
from pathlib import Path

SLOTS = 34
# Header (8) + player_data (111) + player_background (160) + ZP_STATE (32) + eff_fear_timer (1) + ZP_RNG (4)
INV_OFFSET = 8 + 111 + 160 + 32 + 1 + 4
EXPECTED_CLOAK = [0xFF, 0, 0, 0, 0, 0, 0, 0]
EXPECTED_SECONDARY = [2, 1, 0, 3, 4, 0, 2, 6]


def main() -> int:
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        print(f"Usage: {sys.argv[0]} <save.seq> [version]", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    version = int(sys.argv[2], 0) if len(sys.argv) == 3 else 0x20
    data = path.read_bytes()
    if len(data) < INV_OFFSET + 8 * SLOTS:
        print(f"FAIL: save too short ({len(data)} bytes)", file=sys.stderr)
        return 1
    if data[:7] != b"MORIA+4" or data[7] != version:
        print(f"FAIL: bad header {data[:8]!r}, expected MORIA+4 version {version:#x}", file=sys.stderr)
        return 1
    inv = data[INV_OFFSET : INV_OFFSET + 8 * SLOTS]
    cloak = [inv[i * SLOTS + 32] for i in range(8)]
    if cloak != EXPECTED_CLOAK:
        print(f"FAIL: cloak slot 32={cloak!r}, expected {EXPECTED_CLOAK!r}", file=sys.stderr)
        return 1
    secondary = [inv[i * SLOTS + 33] for i in range(8)]
    if secondary != EXPECTED_SECONDARY:
        print(f"FAIL: secondary slot 33={secondary!r}, expected {EXPECTED_SECONDARY!r}", file=sys.stderr)
        return 1
    print(f"PASS: Save V2 header={data[:8]!r}, cloak={cloak}, secondary={secondary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
