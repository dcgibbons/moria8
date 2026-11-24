# Release Notes for Moria8 v2.0.0

Moria8 v2.0.0 expands support to seven 8-bit platforms — adding **Commander
X16**, **Atari 8-bit**, and **Acorn BBC Master 128** alongside the **Commodore
64**, **Commodore 128**, **Commodore Plus/4**, and **Apple II** — introduces ROM
cartridge editions on five systems, and completes full VMS Moria 4.8 item,
monster, trap, magic, and store parity.

It runs on supported original hardware, modern flash/cartridge adapters, the
[FPGA-based C64 Ultimate](https://commodore.net/computer/), and emulators such
as [VICE](https://vice-emu.sourceforge.io/) (Commodore),
[MAME](https://www.mamedev.org) (Apple IIe, Atari 8-bit, BBC Master 128),
[Virtual \]\[](https://www.virtualii.com) (Apple II), and
[x16emu](https://www.commanderx16.com/) (Commander X16).

## What's New in v2.0.0

### Three New Platforms

- **Commander X16 (`moria8-cx16-v2.0.0.crt`, `moria8-cx16-v2.0.0.zip`):**
  80-column VERA display with 65C02 banked-RAM caching (`512 KB`), cartridge
  boot or HostFS/SD archive, and KERNAL/HostFS save support.
- **Atari 8-bit (`moria8-atari8-v2.0.0.car`, `moria8-atari8-v2.0.0.atr`):**
  40-column build supporting stock 64 KB XL/XE systems (Atari 800XL / 65XE) as
  well as auto-detected 128 KB Atari 130XE extended-RAM caching, plus a 128 KB
  cartridge image.
- **Acorn BBC Master 128 (`moria8-bbcmaster-v2.0.0.ssd`):** 80-column Mode 0
  display using Shadow RAM (`LYNNE`), Private RAM (`ANDY`), and Sideways RAM
  banks for cached overlays and monster catalog data, packaged as an
  auto-booting DFS `.ssd` floppy image.

### Five ROM Cartridge Editions

Instant-boot cartridge builds are now available on five platforms alongside
their disk images, with full disk save interchange between disk and cartridge
editions:

- **Commodore 64 (`moria8-c64-v2.0.0.crt`):** Recommended default for C64
  Ultimate and cartridge adapters (1 MB CRT with disk-free gameplay and
  floppy/1541 save support).
- **Commodore 128 (`moria8-c128-v2.0.0.crt`):** ROM cartridge booting straight
  to the 80-column VDC title screen.
- **Commodore Plus/4 (`moria8-plus4-v2.0.0.crt`):** ROM cartridge image.
- **Commander X16 (`moria8-cx16-v2.0.0.crt`):** 512 KB ROM cartridge image.
- **Atari 8-bit (`moria8-atari8-v2.0.0.car`):** 128 KB cartridge image.

### Gameplay, Item, Monster & Save Parity

- **Full VMS Moria 4.8 Monster Roster:** Expanded to the 279-creature catalog
  with elemental breaths, theft and stat-drain attacks, wandering monster
  spawning, summon depth/count rules, and polymorph resistance.
- **Full VMS Item & Ego Catalog:** 361 item definitions and 55 ego types,
  including Cloak equipment, secondary weapon swap (`x`), second ring hand,
  18 dungeon traps, VMS weight limits, and 16-item town stores.
- **Magic, Combat & Status:** Cross-port auto-rest disturbance model, expanded
  wand/scroll/potion/spell/prayer effects (including *Resist Heat/Cold*,
  *Hold Person*, *Free Action*, and poisoned indicator parity), and full
  24-bit gold and XP display.
- **Save Format v2:** Four independent save slots per save disk with checksums
  and version validation. Note: v2.0.0 save disks are not compatible with v1.x
  save disks.

### Performance, Reliability & Built-in Legal/Info Viewers

- **Zero-Disk Hot Gameplay:** Core turn loops, spell/prayer selection, and
  REU/banked caches stay resident across turns without hitting disk.
- **Apple IIe & C128 Improvements:** LZ4-compressed Apple IIe boot/overlays
  and stock 16 KB VDC support on Commodore 128 (with dual-direction fast
  scrolling and debounced `-more-` prompts).
- **Storage Hardening:** Hardened Commodore IEC / DOS status retry and error
  handling, fallback reads, and dedicated **About (`A`)**, **Help License
  (`L`)**, and **System Info (`Shift+V`)** viewers across all 7 disk and
  cartridge editions.

## Using the Cartridges and Disk Images

| Platform | Cartridges | Disks / Archives | Notes |
| -------- | ---------- | ---------------- | ----- |
| **Commodore 64** | `moria8-c64-v2.0.0.crt` | `moria8-c64-v2.0.0.d64` | 1541-compatible D64; CRT recommended on C64 Ultimate & cart adapters |
| **Commodore 128** | `moria8-c128-v2.0.0.crt` | `moria8-c128-v2.0.0.d64`, `moria8-c128-v2.0.0.d71`, `moria8-c128-v2.0.0.d81` | 80-column VDC; choose 1541, 1571, 1581, or CRT cartridge |
| **Commodore Plus/4** | `moria8-plus4-v2.0.0.crt` | `moria8-plus4-v2.0.0.d64` | 1541 D64 or CRT cartridge |
| **Apple II** | — | `moria8-apple2-v2.0.0.po` | ProDOS 140 KB 5.25" image (Apple IIe 128K, IIc, IIgs) |
| **Commander X16** | `moria8-cx16-v2.0.0.crt` | `moria8-cx16-v2.0.0.zip` | Extract ZIP to SD card / HostFS or attach CRT in `x16emu` |
| **Atari 8-bit** | `moria8-atari8-v2.0.0.car` | `moria8-atari8-v2.0.0.atr` | 128 KB cartridge image or DOS 2.5 ATR (64 KB XL/XE + 128 KB 130XE) |
| **Acorn BBC Master 128** | — | `moria8-bbcmaster-v2.0.0.ssd` | Auto-booting DFS `.ssd` (`*EXEC !BOOT` / Shift+Break) |

For cartridge mounting, drive setup, and emulator launch details, see the
[Player Manual](../MANUAL.md) and [Troubleshooting Guide](../TROUBLESHOOTING.md).

### System Requirements Summary

- **Commodore 64 / 128 / Plus/4:** Stock RAM supported; optional 17xx/REU RAM
  expansion used on C64 when present; real 1541/1571/1581, SD2IEC, C64
  Ultimate / 1541 Ultimate II+, or VICE 3.10+.
- **Apple II:** Apple IIe with 128K (extended 80-column text card), Apple IIc,
  or Apple IIgs and one or two ProDOS disk drives.
- **Commander X16:** Commander X16 with 512 KB banked RAM and SD card or HostFS
  (or `x16emu`).
- **Atari 8-bit:** Atari 800XL / 65XE (64 KB) or 130XE (128 KB) with disk
  drive / SIO2SD / FujiNet or 128 KB cartridge support.
- **Acorn BBC Master 128:** BBC Master 128 with Shadow/Sideways RAM enabled
  and DFS floppy / MMFS / GoTek / MAME.

### Real Floppy Users

If you want the game on actual 5.25" or 3.5" floppy media:

- **Commodore (1541 / 1571 / 1581):** Mount the disk image on SD2IEC / C64
  Ultimate / 1541 Ultimate II+ and copy with DraCopy, Maverick, or CBM Command,
  or write directly from Mac/PC with OpenCBM + ZoomFloppy/XUM1541, or via
  [Greaseweazel](https://github.com/keirf/greaseweazle).
- **Apple II / Atari 8-bit / BBC Master 128:** Transfer `.po` with ADTPro,
  mount/write `.atr` via RespeQt/AtariSIO/FujiNet, or write `.ssd`/floppies
  with tools such as [Greaseweazel](https://github.com/keirf/greaseweazle).

#### Interested in Buying a Floppy Distribution?

If you'd like to support this effort, or would just like to have a real
floppy made for you, visit this
[Google Form](https://forms.gle/aVDEXfVxjjsaLFNm6) to indicate interest.

## Restrictions and Save Media

1. Program media cannot be used as save media and the game blocks it. Always
   prepare or mount a separate save disk so upgrading versions never overwrites
   your characters.
2. On disk and cartridge editions alike, use `D)isk Setup` (title menu) or
   `Shift+S` (in game) to select and initialize save media (`4` save slots per
   save disk/volume).
3. On Commodore systems, program and save drives may use device numbers `8-11`.
   Cartridge editions interchange save disks directly with the matching
   platform's disk edition.
4. Unusual I/O failures display compact status codes (for example IEC status
   or DOS error details); include the exact text if reporting an issue.

## What's New in Earlier Releases

See the [v1.5.0 release notes](release_notes-v1.5.0.md) for the Apple II
introduction and earlier release history.
