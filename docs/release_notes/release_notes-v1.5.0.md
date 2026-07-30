# Release Notes for Moria8 v1.5.0

Moria8 v1.5.0 adds the Apple II as the fourth supported platform, alongside
the Commodore 64, Plus/4, and Commodore 128, and improves scrolling and
redraw performance across all platforms.

It runs on supported original hardware, the
[FPGA-based C64 Ultimate](https://commodore.net/computer/), and emulators
such as [VICE](https://vice-emu.sourceforge.io/) (Commodore) and Apple II
emulators such as [MAME](https://www.mamedev.org) and 
[Virtual \]\[](https://www.virtualii.com).

## What's New in v1.5.0

- Added the Apple II port as a ProDOS `.po` disk image, with 80-column
  display, sound effects, four save slots, and a boot progress display.
- Faster dungeon scrolling and screen redraws on all platforms; monster
  movement and combat turns are noticeably snappier on the Apple II and C128.
- Faster C128 scrolling in both directions.
- Fixed truncated combat and equipment messages on 80-column displays.

## What's New in v1.4.2

- Dungeon generation more closely matches the original Moria, including
  door and stair placement fixes.
- Improved monster sleep, wake, and aggravation behavior.

## What's New in v1.4.1

- Improved monster visibility and line-of-sight rules.

## What's New in v1.4.0

- Save disks now hold four independent save slots.
- Fixed several disk handling issues and improved save/load reliability.

## Using the Disk Images

C64: `.d64` disk image, 1541 compatible.

Plus/4: `.d64` disk image, 1541 compatible.

C128: `.d64` disk image, 1541 compatible.

Apple II: `.po` ProDOS disk image, 140 KB 5.25" format.

You can use the Commodore images directly in VICE, with an SD2IEC, or through
the storage options on the C64 Ultimate / 1541 Ultimate II+. The Apple II
image works in Apple II emulators and can be written to a real floppy or used
with common Apple II disk-image hardware.

For C64 Ultimate users, the C64 `.zip` distribution can also be copied to a
SoftwareIEC directory. This improves load performance significantly and is
the recommended way to play on the C64 Ultimate.

### Apple II Requirements

- Apple IIe with 128K memory (extended 80-column text card), Apple IIc, or
  Apple IIgs and one disk drive. Two drives are supported, but a single drive
  works with disk swapping.

### Real Floppy Users

If you want the game on an actual 5.25" floppy:

- With an SD2IEC, C64 Ultimate, or 1541 Ultimate II+: mount the `.d64` image
  and use your favorite disk copy program, such as DraCopy, Maverick, or CBM
  Command, to copy it to your 1541/1571 drive.

- With a real 1541 or 1571 drive attached to a Mac or PC: the fastest method
  is OpenCBM + ZoomFloppy or an XUM1541 adapter. See the
  [OpenCBM guide](https://github.com/OpenCBM/OpenCBM) or search for "write
  d64 ZoomFloppy".

- For the Apple II: transfer the `.po` image with your preferred disk image
  tool (for example ADTPro) to a 140 KB 5.25" disk.
- Alternatively, write a floppy image on another system using a 
  [Greaseweazel](https://github.com/keirf/greaseweazle).

#### Interested in Buying a Floppy Distribution?

If you'd like to support this effort, or would just like to have a real
floppy made for you, we're gathering interest right now. Visit this
[Google Form](https://forms.gle/aVDEXfVxjjsaLFNm6) and let us know your
interest.

## Restrictions and Save Media

1. The program can be started from any supported device number (8-11 on
   Commodore).
2. Save drives may be selected in the 8-11 range where supported on
   Commodore.
3. The program media cannot be used as save media and the game will block
   it. This keeps your saves safe and makes upgrading to new versions
   easier. On the Apple II, use `D)isk Setup` on the title screen to prepare
   a save disk (any ProDOS volume); each save disk holds four save slots.
4. Some unusual storage failures may still display compact diagnostic
   messages, such as a disk code or internal status value. Please include
   the exact text if you report one.

## What's New in Earlier Releases

See the
[v1.3.0 release notes](release_notes-v1.3.0.md)
for the initial Commodore feature set, including the C64, Plus/4, and C128
ports, expanded weapons and armor, and the Balrog end-game.
