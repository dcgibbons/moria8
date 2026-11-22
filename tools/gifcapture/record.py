#!/usr/bin/env python3
"""Record non-wizard gameplay GIFs across all 7 Moria8 platforms.

  tools/gifcapture/record.py c64        boot art + chargen (clip 1), Balrog Gnome Warrior DL7-9 (clips 2-4)
  tools/gifcapture/record.py plus4      Balrog Half-Troll Warrior DL9-11 (clips 1-4)
  tools/gifcapture/record.py c128       Balrog Half-Elf Mage DL26 on 80-col VDC (clips 1-4)
  tools/gifcapture/record.py apple2     Balrog Dwarf Priest DL26-27 on Apple IIe (clips 1-4)
  tools/gifcapture/record.py cx16       Balrog Halfling Rogue DL12-13 on CX16 (clips 1-4)
  tools/gifcapture/record.py atari8     Balrog Human Ranger DL23-24 on Atari 130XE (clips 1-4)
  tools/gifcapture/record.py bbcmaster  Balrog Elf Rogue DL38 on BBC Master 128 (clips 1-4)
  tools/gifcapture/record.py all        all 7 platforms

Output: docs/assets/moria8-<platform>-gameplay-<n>.gif. Frame dumps and emulator
scratch files go under build/gifcapture/ (override with GIFCAP_WORK).

Requires built disk images in build/ (make disk), ffmpeg, Python 3 + Pillow,
VICE (x64sc/x128/xplus4) for Commodore targets, x16emu + X16ROM for CX16, and
MAME + A2ROMS / ATARI8ROMS / BBCMROMS for Apple IIe / Atari 8-bit / BBC Master.
Launch inside tools/isolated.sh so emulator monitor ports never collide.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

CBM_PLATFORMS = ("c64", "plus4", "c128")
MAME_PLATFORMS = ("apple2", "atari8", "bbcmaster")
ALL_PLATFORMS = CBM_PLATFORMS + ("cx16",) + MAME_PLATFORMS


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else list(argv)
    if len(args) != 1 or args[0] not in (*ALL_PLATFORMS, "all"):
        sys.stderr.write(__doc__ or "")
        return 2

    target = args[0]
    targets = ALL_PLATFORMS if target == "all" else (target,)
    for plat in targets:
        if plat in CBM_PLATFORMS:
            import record_cbm

            rc = record_cbm.main([plat])
        elif plat in MAME_PLATFORMS:
            import record_mame

            rc = record_mame.main(["--platform", plat])
        elif plat == "cx16":
            import record_cx16

            rc = record_cx16.main([])
        else:
            raise AssertionError(plat)
        if rc != 0:
            return rc
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
