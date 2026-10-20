# gifcapture

Records gameplay in an emulator and cuts it into the animated GIFs used on the
website (`docs/assets/moria8-<platform>-gameplay-<n>.gif`).

```
tools/gifcapture/record.py c64      # loading art + character creation (clip 1),
                                    #   level 8 Warrior on DL8 (clips 2-4)
tools/gifcapture/record.py plus4    # level 10 Rogue on DL10, 4 clips
tools/gifcapture/record.py c128     # level 5 Mage on DL4, 4 clips
tools/gifcapture/record.py apple2   # level 30 Priest on DL35, 4 clips
```

Run from the repository root on a normal desktop session (VICE and MAME are
driven over localhost sockets and files, so sandboxed runs fail).

## Requirements

- Built disk images in `build/` (`make disk`)
- `ffmpeg`, Python 3 with Pillow and numpy
- VICE (`x64sc`, `x128`, `xplus4`) for the Commodore targets
- MAME `apple2ee` for the Apple II, with `A2ROMS` set to the directory holding
  `apple2ee.zip` (the ROMs are not redistributable)

Frame dumps and emulator scratch files go to `build/gifcapture/`
(override with `GIFCAP_WORK`). Final GIFs are encoded with
`tools/make_gameplay_gif.sh`.

## How it works

- **VICE** is driven through its binary monitor: keys are fed to the keyboard
  buffer, screen text is read straight from screen RAM, and frames are grabbed
  as images. Emulation speed is raised while disks load and between screens,
  and frames are only captured while the clip is meant to be "playing".
- **C128**: the game scans the CIA keyboard matrix directly, so the keyboard
  routine (`cia_scan_petscii`) is patched in RAM to read a byte the monitor
  controls. The patch lives only in the running emulator; no repo files change.
  The C128 screen is read from VDC RAM (monitor bank 10).
- **Apple II**: MAME runs a Lua script (`rpc.lua`) that polls a command file for
  key presses, text-page reads and screenshots.
- **Action clips** skip character creation in the clip: a character is made
  off-camera, then wizard mode (`Ctrl+W`) raises its level, jumps to the target
  dungeon level, heals and reveals the map. During the clip the character
  travels between items and far-off spots and fights, while wizard commands
  summon monsters and heal (also off-camera).
- The player's real map position is read from zero page (`$2B`/`$2C`, the same
  on every platform) so goals are tracked in map coordinates. Screen
  coordinates are useless because the view scrolls.

## Files

| File | Role |
| --- | --- |
| `record.py` | entry point and per-platform configuration |
| `gamerec.py` | boot, character creation and the C64 creation clip |
| `action.py` | wizard setup, fighting loop, off-camera healing/summoning |
| `explore.py` | movement: committed goals, fighting, anti-dithering |
| `rec.py` | emulator wrapper (frames, keys, screen text) and GIF encoding |
| `vcap.py` | VICE binary-monitor client |
| `mamegame.py`, `rpc.lua` | MAME wrapper and its Lua command loop |
| `split.py` | cuts a frame dump into numbered clips |
| `lvl.py`, `paths.py` | level-generation waits, shared paths |

## Gotchas

- Characters die now and then; `record.py` detects it and retries (up to 5
  times), so a run can take several attempts.
- MAME only loads the Lua script reliably when run for 299 emulated seconds or
  less, so the Apple II session is kept inside that budget and the script
  stops emulation while it waits for commands.
- The first frames of each action clip are trimmed because they still show the
  wizard's `OK` message.
