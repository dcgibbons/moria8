# gifcapture

Records genuine non-wizard gameplay in VICE, `x16emu`, and MAME and cuts it into
the animated GIFs used on the website (`docs/assets/moria8-<platform>-gameplay-<n>.gif`).

```
tools/isolated.sh python3 tools/gifcapture/record.py c64        # boot art + chargen (clip 1), Balrog Gnome Warrior DL7-9 (clips 2-4)
tools/isolated.sh python3 tools/gifcapture/record.py plus4      # Balrog Half-Troll Warrior DL9-11 (clips 1-4)
tools/isolated.sh python3 tools/gifcapture/record.py c128       # Balrog Half-Elf Mage DL26, 80-col VDC (clips 1-4)
tools/isolated.sh python3 tools/gifcapture/record.py cx16       # Balrog Halfling Rogue DL12-13 (clips 1-4)
tools/isolated.sh python3 tools/gifcapture/record.py apple2     # Balrog Dwarf Priest DL26-27 (clips 1-4)
tools/isolated.sh python3 tools/gifcapture/record.py atari8     # Balrog Human Ranger DL23-24 (clips 1-4)
tools/isolated.sh python3 tools/gifcapture/record.py bbcmaster  # Balrog Elf Rogue DL38 (clips 1-4)
```

Run from the repository root inside `tools/isolated.sh` with unsandboxed emulator
permissions (`VICE`, `x16emu`, and `MAME` harnesses use localhost sockets).

## Requirements

- Built disk images in `build/` (`make disk`) and Balrog Town checkpoints in
  `var/moria8/balrog/` (never modified in place)
- `ffmpeg`, Python 3 with Pillow (`PIL`)
- VICE (`x64sc`, `x128`, `xplus4`) for Commodore 64, Plus/4, and C128
- `x16emu` and `X16ROM` for Commander X16
- MAME (`apple2ee`, `a130xe`, `bbcm`) with `A2ROMS`, `ATARI8ROMS`, and `BBCMROMS`

Frame dumps and emulator scratch files go to `build/gifcapture/`
(override with `GIFCAP_WORK`). Final GIFs are encoded with
`tools/make_gameplay_gif.sh`.

## How it works

- **Non-wizard Balrog saves (`balrog_save.py`)**: extracts real non-wizard
  Save Format V2 (`$22`) `THE.GAME` Town checkpoints (`7,858 B` 80x48 for
  `c64`, `plus4`, `atari8`; spliced onto native `198x66` `17,164 B` Town
  geometry for `c128`, `apple2`, `cx16`, `bbcmaster` with updated magic and
  16-bit additive checksum). Each clip loads its save off-camera, uses a real
  `Scroll of Word of Recall` in Town to reach its earned `max_dl`, and lets
  `playtest/moria_playtest/brain.py` play naturally with torchlight fog-of-war
  and zero wizard mode (`Ctrl+W` is never sent).
- **Commodore (`record_cbm.py`)**:
  - **C64 Clip 1**: uses `rec.py` (`Game` + VIC binary monitor) to capture boot
    artwork, title screen, character creation, and Town arrival (`384x288`).
  - **C64 / Plus/4 / C128 Action Clips**: driven through `playtest`'s `Worker`
    and `Brain` (with `brain.town_trip` disabled so characters explore and
    fight continuously). Frames are rendered pixel-exact from live VIC/TED/VDC
    RAM and palette registers (`384x288` for C64/Plus/4, `656x492` for C128).
  - **C128 keyboard hook (`rec.py`)**: dynamically resolves `cia_scan_petscii`
    from `build/c128/main.sym` rather than hardcoding an address.
- **Commander X16 (`record_cx16.py`)**: drives `x16emu -testbench` over
  host-FS and captures 80-column `640x480` VERA frames from live registers/VRAM.
- **MAME (`record_mame.py` + `mame_snap_bridge.lua`)**: drives `apple2ee`,
  `a130xe`, and `bbcm` via headless `-video soft` + Lua command/screenshot IPC
  and scales to crisp 4:3 canvases (`560x420`, `384x288`, `640x480`).

## Files

| File | Role |
| --- | --- |
| `record.py` | unified CLI dispatcher across all 7 platforms |
| `balrog_save.py` | Balrog Save V2 (`$22`) extractor, 80x48/198x66 splicer, disk packager |
| `record_cbm.py` | non-wizard C64, Plus/4, and C128 capture pipeline |
| `record_cx16.py` | non-wizard Commander X16 capture pipeline (`x16emu -testbench`) |
| `record_mame.py`, `mame_snap_bridge.lua` | non-wizard Apple IIe, Atari 8-bit, and BBC Master capture pipeline |
| `rec.py`, `vcap.py` | VICE monitor wrapper (with dynamic `cia_scan_petscii`) and GIF encoder |
| `paths.py` | shared repo/build/asset path definitions |
