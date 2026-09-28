#!/usr/bin/env python3
"""Krill's Loader filename-hash collision check.

Krill's drive-side code identifies files by a 16-bit rolling hash of the
filename (FILENAMEHASHLO/HI; see loader/src/drives/drivecode-common.inc,
FNAMEHASH / gethashval). A collision makes the loader pick either file
silently. c1541 cannot detect this, so we reimplement the hash here and
fail the disk build if any two names that may share a disk collide.

Hash loop semantics (1541 path, FILENAME_MAXLENGTH = 16):
    entry: A = Y = n (name length), carry set
    loop over x = n .. 1:
        TEMP = A
        A = Y + name[x-1] + carry   ; carry = carry-out
        Y = A
        A = A + TEMP + carry        ; carry = carry-out
    result = (A, Y)

Only the Krill-loaded payload names strictly need checking, but save-slot
files can share a disk with the program files in one-drive mode, and dir-art
entries exist on the shipping image, so the full shipping set is checked.
"""

from __future__ import annotations

import argparse
import sys

# Names as stored in the CBM directory (game sends PETSCII uppercase).
C64_DISK_NAMES = [
    # Krill-loaded at runtime
    "64.START", "64.TOWN", "64.DEATH", "64.MODAL", "64.GEN",
    "64.HELP", "64.UI", "64.ITEMS", "64.SPELL", "64.CHEST", "64.SAVE",
    "MONSTER.DB.1", "MONSTER.DB.2", "MONSTER.DB.3", "MONSTER.DB.4",
    "T64",
    # KERNAL-loaded boot/program files (share the directory)
    "MORIA8", "BOOT64", "BOOTART64", "KINST64", "KRES64", "KINST41",
    "MORIA64", "64.INIT", "64.BANK",
    # Release-compliance SEQ files
    "LICENSE", "SOURCE-OFFER",
    # Dir-art placeholder files
    "ART1", "ART2", "ART3", "ART4", "ART5",
    # Runtime save-disk files (one-drive mode shares media with the above)
    "THE.GAME", "THE.GAME2", "THE.GAME3", "THE.GAME4",
    "THE.SAVE", "THE.SAVE2", "THE.SAVE3", "THE.SAVE4",
    "THE.MAP", "THE.MAP2", "THE.MAP3", "THE.MAP4",
    "HALL.OF.FAME", "MORIA8.ID",
]


def krill_hash(name: str) -> tuple[int, int]:
    """16-bit drive-side filename hash; returns (hash_a, hash_y)."""
    data = [ord(ch) for ch in name[:16]]  # names are ASCII==PETSCII-uppercase here
    n = len(data)
    a = n
    y = n
    carry = 1
    for x in range(n, 0, -1):
        temp = a
        v = y + data[x - 1] + carry
        carry = 1 if v > 0xFF else 0
        y = v & 0xFF
        v = y + temp + carry
        carry = 1 if v > 0xFF else 0
        a = v & 0xFF
    return a, y


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()

    seen: dict[tuple[int, int], str] = {}
    failed = False
    for name in C64_DISK_NAMES:
        h = krill_hash(name)
        other = seen.get(h)
        if other is not None and other != name:
            print(
                f"ERROR: Krill filename hash collision: {name!r} and {other!r} "
                f"both hash to ${h[0]:02x}${h[1]:02x}"
            )
            failed = True
        seen[h] = name
    if failed:
        return 1
    print(f"Krill filename hash check: {len(C64_DISK_NAMES)} names, no collisions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
