#!/usr/bin/env python3
"""Check a C128 Save V2 file for the secondary-weapon fixture.

The save-write smokes save with slot 33 (EQUIP_SECONDARY) holding a
Dagger (+3,+4) (Defender): fields id, qty, p1, to_hit, to_dam, to_ac,
flags, ego = 2, 1, 0, 3, 4, 0, IF_IDENTIFIED, 6. The 34-slot inventory
section stores the 8 arrays back to back, so those 8 bytes sit 34 bytes
apart, each one directly after slot 32 (EQUIP_CLOAK: id $FF, fields 0).

usage: check_save_secondary128.py <save-file> <expected-version-byte>
"""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "tools"))
from item_ids import FI_EMPTY, ITEM_PAGE_DAGGER, ITEM_SLOT_DAGGER  # noqa: E402

SLOTS = 34
EGO_DEFENDER = 6
SECONDARY = [ITEM_SLOT_DAGGER, 1, 0, 3, 4, 0, 2, ITEM_PAGE_DAGGER | EGO_DEFENDER]
CLOAK = [FI_EMPTY, 0, 0, 0, 0, 0, 0, 0]


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    data = Path(sys.argv[1]).read_bytes()
    version = int(sys.argv[2], 0)
    if len(data) < 8 or data[7] != version:
        print(f"FAIL: save version byte {data[7] if len(data) > 7 else None!r}, expected {version:#04x}")
        return 1
    hits = [
        i for i in range(1, len(data) - 7 * SLOTS)
        if all(data[i + k * SLOTS] == SECONDARY[k] for k in range(8))
        and all(data[i - 1 + k * SLOTS] == CLOAK[k] for k in range(8))
    ]
    if len(hits) != 1:
        print(f"FAIL: secondary-weapon pattern found {len(hits)} times (expected once)")
        return 1
    print(f"PASS: slot 33 at offset {hits[0]} (inventory section from {hits[0] - 33})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
