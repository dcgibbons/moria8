# Release Notes for Moria8 v1.0.0
This is the first public release of Moria8 for the Commodore 64 and Commodore 128.

It runs on original hardware, the [FPGA-based C64 Ultimate](https://commodore.net/computer/), and emulators such as [VICE](https://vice-emu.sourceforge.io/).

## Using the Disk Images
C64: `.d64` disk image (1541 compatible)
C128: `.d71` disk image (1571 compatible)
You can use these images directly in VICE, with an SD2IEC, or via the storage options on the C64 Ultimate / 1541 Ultimate II+.

### Real floppy users
If you want the game on an actual 5.25" floppy:

- With an SD2IEC, C64 Ultimate, or 1541 Ultimate II+: mount the `.d64`/`.d71` image and use your favorite disk copy program, such as DraCopy, Maverick, or CBM Command to copy it to your 1541/1571 drive.

- With a real 1541 or 1571 drive attached to a PC: the fastest method is OpenCBM + ZoomFloppy (or XUM1541 adapter). See the [OpenCBM guide](https://github.com/OpenCBM/OpenCBM) or search “write d64 ZoomFloppy”.

## Restrictions

1. The game disk must be in drive 8.
2. Save disks can be in drive 8 or 9 (future versions will support any device number; the C128 port supports different device numbers but this has not yet been tested). 
3. The game disk cannot be used as a save disk (the game will block it). This keeps your saves safe and makes upgrading to new versions easy.

## Recommendations

1. C64: Use an REU (Ram Expansion Unit) if possible to reduce disk use. Both VICE and the C64 Ultimate emulate one easily. The C128 has enough built-in RAM, so no RAM expansion is needed.
4. Use a fast loader ([Epyx FastLoad](https://www.tfw8b.com/product/epyx-fastload-reloaded-disk-sd2iec-turbo-loader-cartridge-c64/), [JiffyDOS](https://www.jiffydos.com), or the built-in fast loaders on modern devices) — it makes a noticeable difference even in emulation.

## Running the Game

### C64
Insert the game disk into drive 8, then type:
`LOAD "*",8`
`RUN`

### C128
Insert the game disk into drive 8 and reset the computer. The game boots automatically in 80-column mode.
(Use C64 mode if you prefer the 40-column version — let me know if you’d like a dedicated 40-col C128 build!)

## How to Play
See the [Player Guide](https://github.com/dcgibbons/moria8/blob/main/docs/PLAYER_GUIDE.md) for quick-start tips and the [Manual](https://github.com/dcgibbons/moria8/blob/main/docs/MANUAL.md) for controls and additional details.

## Reporting Issues
If you hit any bugs, crashes, or compatibility problems, please open an issue in the [Issues tab](https://github.com/dcgibbons/moria8/issues).

**To help me fix it faster, please include:**

Game version and which disk image you used (.d64 or .d71)
Hardware: real C64/C128 or emulator? (VICE, etc.)
Drive: 1541 / 1571 / SD2IEC / C64 Ultimate / other
Fast loader used (stock, JiffyDOS, Epyx FastLoad, etc.)
PAL or NTSC machine
Exact steps to reproduce + any error messages or screenshots
(Quick tip: search existing issues first — your bug may already be listed!)
