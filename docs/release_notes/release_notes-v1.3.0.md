# Release Notes for Moria8 v1.3.0

Moria8 v1.3.0 is the fourth release for the Commodore 64, Plus/4, and 128 systems.

It runs on supported original Commodore hardware, the [FPGA-based C64 Ultimate](https://commodore.net/computer/), and emulators such as [VICE](https://vice-emu.sourceforge.io/).

## What's New in v1.3.0

- Added many more weapons and pieces of armor, including new swords, axes, polearms, shields, helms, gloves, and boots.
- Older save files from recent releases should still load normally.
- The C128 release now uses a 1541-compatible `.d64` image instead of requiring a `.d71` image.
- Improved save/load behavior on single-drive systems where the program disk and save disk share drive 8.
- Fixed C128 spellbook selection when studying spells from the inventory.

## What's New in v1.2.0

- Added winning condition for killing the Balrog and end-game retirement screen and flow.

## What's New in v1.1.0

- Added support for the Commodore Plus/4 platform as a `.d64` disk image.
- Improved C64 Ultimate support, including better REU-oriented play and targeted runtime acceleration for expensive map and magic operations.
- Added Disk Setup and save-media improvements for one-drive and two-drive play, including clearer program-disk versus save-disk separation.
- Added support for running from configurable Commodore device numbers, with save drives selectable in the 8-11 range where supported.
- Added a direct visible-trap disarm command.
- Kept discovered floor traps armed until the player handles them.
- Improved combat balance and bonuses to closer match umoria.
- Added visual indicator of multi-attack hits.
- Fixed several item, store, spellbook, and save-result display issues.

## Using the Disk Images

C64: `.d64` disk image, 1541 compatible.

Plus/4: `.d64` disk image, 1541 compatible.

C128: `.d64` disk image, 1541 compatible.

You can use these images directly in VICE, with an SD2IEC, or through the storage options on the C64 Ultimate / 1541 Ultimate II+.

For C64 Ultimate users, the C64 `.zip` distribution can also be copied to a SoftwareIEC directory. This improves load performance significantly and is the recommended way to play on the C64 Ultimate.

### Real Floppy Users

If you want the game on an actual 5.25" floppy:

- With an SD2IEC, C64 Ultimate, or 1541 Ultimate II+: mount the `.d64` image and use your favorite disk copy program, such as DraCopy, Maverick, or CBM Command, to copy it to your 1541/1571 drive.

- With a real 1541 or 1571 drive attached to a Mac or PC: the fastest method is OpenCBM + ZoomFloppy or an XUM1541 adapter. See the [OpenCBM guide](https://github.com/OpenCBM/OpenCBM) or search for "write d64 ZoomFloppy".

#### Interested in Buying a Floppy Distribution?

If you'd like to support this effort, or would just like to have a real floppy made for you, we're gathering interest right now. Visit this [Google Form](https://forms.gle/aVDEXfVxjjsaLFNm6) and let us know your interest.

## Restrictions and Save Media

1. The program can be started from any supported device number (8-11).
2. Save drives may be selected in the 8-11 range where supported.
3. The program media cannot be used as save media and the game will block it. This keeps your saves safe and makes upgrading to new versions easier.
4. Some unusual storage failures may still display compact diagnostic messages, such as a disk code, KERNAL status, or internal phase value. Please include the exact text if you report one.

## Recommendations

1. C64: use an REU if possible to reduce disk use. VICE and the C64 Ultimate both emulate one easily.
2. Plus/4: use a reliable 1541-compatible disk path in VICE or on hardware.
3. C128: no RAM expansion is needed.
4. Use a fast loader where compatible, such as [Epyx FastLoad](https://www.tfw8b.com/product/epyx-fastload-reloaded-disk-sd2iec-turbo-loader-cartridge-c64/), [JiffyDOS](https://www.jiffydos.com), or the built-in fast loaders on modern devices. It makes a noticeable difference even in emulation.

## C64 Ultimate Notes

The C64 Ultimate is the preferred C64-family target for v1.3.0 if you want the best C64 experience.

### Enable REU

Enable the RAM Expansion Unit in the Ultimate configuration menu before starting the game. The exact menu wording depends on firmware, but it is under the C64/cartridge configuration area. Any REU size will do, as Moria8 will use less than 64KB of the REU.

Moria8 detects the REU on startup. When present, the C64 build uses it to cache runtime data that would otherwise be loaded from disk.

### Use the SoftwareIEC Distribution

For best C64 Ultimate performance, use the C64 `.zip` distribution instead of mounting the `.d64` image:

1. Unzip the C64 distribution on your computer.
2. Copy the extracted Moria8 directory to storage used by the C64 Ultimate (USB, SD Card, or the internal Flash memory will work).
3. Enable SoftwareIEC and note its device number. Device 10 or 11 is common, but use the number configured on your system.
4. From C64 BASIC, change SoftwareIEC to the Moria8 directory, then load and run the boot file.

Example, using SoftwareIEC as device 10 and the game directory at `/Usb0/MORIA8-C64`:

```text
OPEN 15,10,15,"CD:/USB0/MORIA8-C64":CLOSE 15
LOAD "MORIA8",10
RUN
```

If your SoftwareIEC device or directory path is different, substitute those values.

### C64 Ultimate-Specific Acceleration

Moria8 v1.3.0 includes C64 Ultimate-specific support for:

- REU-assisted runtime data caching.
- C64 Ultimate detection on the title/system information path.
- Turbo mode during expensive in-game operations such as dungeon generation, map effects, and selected magic effects.

These optimizations are automatic when the required C64 Ultimate features are enabled. The game returns to normal speed after the accelerated operation.

## Running the Game

### C64

Insert or mount the C64 game media, then load from the device you are using. For the usual device 8 setup, type:

```text
LOAD "MORIA8",8
RUN
```

### Plus/4

Insert or mount the Plus/4 game media, then load from the device you are using. For the usual device 8 setup, type:

```text
LOAD "MORIA8",8
RUN
```

### C128

Insert or mount the C128 game media and reset the computer. In the usual device 8 setup, the game boots automatically in 80-column mode.

Use C64 mode and the C64 disk if you prefer the 40-column version.

## How to Play

See the [Player Guide](https://github.com/dcgibbons/moria8/blob/main/docs/PLAYER_GUIDE.md) for quick-start tips and the [Manual](https://github.com/dcgibbons/moria8/blob/main/docs/MANUAL.md) for controls and additional details.

## Known Limits

Moria8 is not a exact feature-for-feature Umoria or VMS Moria reproduction. It is a lineage-faithful Commodore adaptation with platform-specific memory, display, storage, and runtime tradeoffs.

Known limits:

- The monster roster and item list are still selected for this Commodore version rather than copied in full from upstream Umoria.
- Chests are not implemented yet.
- Monster recall display exists, but recall persistence is not complete.
- Some upstream monster special attacks and content effects are not implemented yet.
- C64, C128, and Plus/4 support racial/timed infravision for warm monsters in darkness.
- Combat follows VMS Moria and Umoria mechanics closely where implemented, but exact message timing, feedback granularity, and every edge-case probability are not guaranteed.
- Unlike VMS Moria and Umoria, Moria8 does not enforce permadeath by deleting or invalidating your save file after death. Your save game remains intact.
- Some UI text, message timing, and screen behavior differ from upstream VMS Moria and Umoria.
- Some disk/storage failures still use compact diagnostic text.
- Future versions may need a save-file migration if the item list grows again.

## Reporting Issues

If you hit any bugs, crashes, or compatibility problems, please open an issue in the [Issues tab](https://github.com/dcgibbons/moria8/issues).

To help fix it faster, please include:

- Game version and which disk image you used.
- Platform: C64, C128, or Plus/4.
- Hardware or emulator: real machine, VICE, C64 Ultimate, or other.
- Drive or storage device: 1541, 1571, SD2IEC, C64 Ultimate, 1541 Ultimate II+, or other.
- Fast loader used, if any: stock, JiffyDOS, Epyx FastLoad, etc.
- PAL or NTSC machine.
- Exact steps to reproduce.
- Any error messages or screenshots.

Quick tip: search existing issues first. Your bug may already be listed.

## Community

Join our [Discord Server](https://discord.gg/b5rFSDZ8Yk) to get help, chat with community, and discuss new features!
