# Release Notes for Moria8 v1.1.0

Moria8 v1.1.0 is the second public Commodore release and the first release to
include Commodore Plus/4 support alongside the Commodore 64 and Commodore 128.

It runs on supported original Commodore hardware targets, the
[FPGA-based C64 Ultimate](https://commodore.net/computer/), and emulators such
as [VICE](https://vice-emu.sourceforge.io/).

## What's New in v1.1.0

- Added the Commodore Plus/4 release as a standard `.d64` disk image.
- Improved C64 Ultimate support, including better REU-oriented play and targeted
  runtime acceleration for expensive map and magic operations.
- Added Disk Setup and save-media improvements for one-drive and two-drive
  play, including clearer program-disk versus save-disk separation.
- Added support for running from configurable Commodore device numbers, with
  save drives selectable in the 8-11 range where supported.
- Added a direct visible-trap disarm command.
- Hardened Plus/4 boot, storage, save/load, display, input, sound, and overlay
  behavior.
- Fixed C128 input and Home redraw behavior.
- Fixed SID gate-off lifecycle behavior.
- Fixed several item, store, spellbook, and save-result display issues.
- Kept discovered floor traps armed until the player handles them.

## Using the Disk Images

C64: `.d64` disk image, 1541 compatible.

C128: `.d71` disk image, 1571 compatible.

Plus/4: `.d64` disk image, 1541 compatible.

You can use these images directly in VICE, with an SD2IEC, or through the
storage options on the C64 Ultimate / 1541 Ultimate II+.

For C64 Ultimate users, the C64 loose-file `.zip` distribution can also be
copied to a Software IEC directory. This avoids disk-image mounting and can
improve load performance significantly.

### Real Floppy Users

If you want the game on an actual 5.25" floppy:

- With an SD2IEC, C64 Ultimate, or 1541 Ultimate II+: mount the `.d64` or
  `.d71` image and use your favorite disk copy program, such as DraCopy,
  Maverick, or CBM Command, to copy it to your 1541/1571 drive.

- With a real 1541 or 1571 drive attached to a PC: the fastest method is
  OpenCBM + ZoomFloppy or an XUM1541 adapter. See the
  [OpenCBM guide](https://github.com/OpenCBM/OpenCBM) or search for
  "write d64 ZoomFloppy".

## Restrictions and Save Media

1. The examples below use device 8, but the program media no longer has to be
   drive 8 only. Use the device number where you mounted or copied the game.
2. Save disks are configured through Disk Setup. Save drives may be selected in
   the 8-11 range where supported.
3. The program media cannot be used as save media. The game will block it. This
   keeps your saves safe and makes upgrading to new versions easier.
4. Some unusual storage failures may still display compact diagnostic messages,
   such as a disk code, KERNAL status, or internal phase value. Please include
   the exact text if you report one.

## Recommendations

1. C64: use an REU if possible to reduce disk use. VICE and the C64 Ultimate
   both emulate one easily.
2. C128: no RAM expansion is needed.
3. Plus/4: use a reliable 1541-compatible disk path in VICE or on hardware.
4. Use a fast loader where compatible, such as
   [Epyx FastLoad](https://www.tfw8b.com/product/epyx-fastload-reloaded-disk-sd2iec-turbo-loader-cartridge-c64/),
   [JiffyDOS](https://www.jiffydos.com), or the built-in fast loaders on modern
   devices. It makes a noticeable difference even in emulation.

## C64 Ultimate Notes

The C64 Ultimate is the preferred C64-family target for v1.1.0 if you want the
fastest C64 experience.

### Enable REU

Enable the RAM Expansion Unit in the Ultimate configuration menu before
starting the game. The exact menu wording depends on firmware, but it is under
the C64/cartridge configuration area. A 512 KB REU setting is a safe
compatibility choice, and larger REU sizes are also supported by the Ultimate
hardware.

Moria8 detects the REU on startup. When present, the C64 build uses it to cache
runtime data that would otherwise be loaded from disk.

### Use the Software IEC Distribution

For best C64 Ultimate performance, use the C64 loose-file `.zip` distribution
instead of only mounting the `.d64` image:

1. Unzip the C64 distribution on your computer.
2. Copy the extracted Moria8 directory to the USB storage used by the C64
   Ultimate.
3. Enable Software IEC and note its device number. Device 10 or 11 is common,
   but use the number configured on your system.
4. From C64 BASIC, change Software IEC to the Moria8 directory, then load and
   run the boot file.

Example, using Software IEC as device 10 and the game directory at
`/Usb0/MORIA8-C64`:

```text
OPEN 15,10,15,"CD:/Usb0/MORIA8-C64":CLOSE 15
LOAD "MORIA8",10
RUN
```

If your Software IEC device or directory path is different, substitute those
values. The current game loader uses normal KERNAL-style file loading from that
directory; it does not rely on the experimental UCI `LOAD_SU`/`LOAD_EX` path.

### C64 Ultimate-Specific Acceleration

Moria8 v1.1.0 includes C64 Ultimate-specific support for:

- REU-assisted runtime data caching.
- C64 Ultimate detection on the title/system information path.
- Turbo mode during expensive in-game operations such as dungeon generation,
  map effects, and selected magic effects.

These optimizations are automatic when the required C64 Ultimate features are
enabled. The game returns to normal speed after the accelerated operation.

## Running the Game

### C64

Insert or mount the C64 game media, then load from the device you are using.
For the usual device 8 setup, type:

```text
LOAD "*",8
RUN
```

### C128

Insert or mount the C128 game media and reset the computer. In the usual device
8 setup, the game boots automatically in 80-column mode.

Use C64 mode if you prefer the 40-column version.

### Plus/4

Insert or mount the Plus/4 game media, then load from the device you are using.
For the usual device 8 setup, type:

```text
LOAD "*",8
RUN
```

The Plus/4 version uses a simple loading display rather than C64/C128-style
boot art.

## How to Play

See the
[Player Guide](https://github.com/dcgibbons/moria8/blob/main/docs/PLAYER_GUIDE.md)
for quick-start tips and the
[Manual](https://github.com/dcgibbons/moria8/blob/main/docs/MANUAL.md) for
controls and additional details.

## Known Limits

Moria8 is not a byte-for-byte Umoria or VMS Moria reproduction. It is a
lineage-faithful Commodore adaptation with platform-specific memory, display,
storage, and runtime tradeoffs.

Known limits:

- Monster and item catalogs are curated and reduced from the full upstream
  catalogs.
- Monster recall display exists, but recall persistence is not complete.
- Some UI text, message timing, and terminal behavior differ from upstream
  Moria and Umoria.
- Some disk/storage failures still use compact diagnostic text.
- v1.1.0 ships Save Format V1. Future item/catalog expansion must either load
  v1.1.0 saves through an explicit migration path or reject them with a clear
  incompatible-save message.

## Reporting Issues

If you hit any bugs, crashes, or compatibility problems, please open an issue in
the [Issues tab](https://github.com/dcgibbons/moria8/issues).

To help fix it faster, please include:

- Game version and which disk image you used: `.d64` or `.d71`.
- Platform: C64, C128, or Plus/4.
- Hardware or emulator: real machine, VICE, C64 Ultimate, or other.
- Drive or storage device: 1541, 1571, SD2IEC, C64 Ultimate, 1541 Ultimate II+,
  or other.
- Fast loader used, if any: stock, JiffyDOS, Epyx FastLoad, etc.
- PAL or NTSC machine.
- Exact steps to reproduce.
- Any error messages or screenshots.

Quick tip: search existing issues first. Your bug may already be listed.
