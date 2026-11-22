# Troubleshooting

## Save Format Compatibility

Current builds use **Save Format V2** (`SAVE_VERSION = $22`) across all seven
platforms.

- **`Unsupported save.`:** Older saves from prior releases (`< $22`, including
  Save Format V1) and saves from newer/incompatible builds (`> $22`) are
  rejected cleanly without modifying your current session or disk. Start a new
  character on a fresh or reinitialized save slot.
- **`Save file corrupt!`:** The save stream failed its checksum or structural
  bounds check (for example, an interrupted write, truncated disk image, or a
  cross-geometry save disk mismatch — see below).
- **Cross-geometry saves (`80x48` vs. `198x66`) are NOT compatible:** Save Format
  V2 (`$22`) writes the full active map (`80x48` = `3,840` bytes on **C64,
  Plus/4, and Atari 8-bit** [`7,858` bytes total]; `198x66` = `13,068` bytes on
  **C128, Apple IIe, Commander X16, and BBC Master 128** [`17,164` bytes
  total]). **Never share save disks between 40-column (`80x48`) and 80-column
  (`198x66`) machines:**
  - C64 (`80x48`) and C128 (`198x66`) share the `"MORIA01"` V2 header and
    Commodore filenames (`MORIA8.ID`, `THE.GAME`–`THE.GAME4`). Loading a C64 save
    in C128 (or a C128 save in C64) passes the version check and fails
    mid-stream with **`Save file corrupt!`** — use separate save disks for C64
    and C128.
  - Plus/4 uses its own `"MORIA+4"` header and rejects saves from any other
    platform immediately with **`Unsupported save.`**.
  - Saves *are* bidirectionally compatible between each platform's own disk and
    cartridge editions (e.g. C64 `.d64` ↔ `.crt`, C128 `.d71`/`.d81`/`.d64` ↔
    `.crt`, Plus/4 `.d64` ↔ `.crt`, Commander X16 `.zip`/HostFS ↔ `.crt`, and
    Atari 8-bit `.atr` ↔ `.car`).

## Cartridge Media & Saves

The five cartridge releases (`moria8-c64.crt`, `moria8-c128.crt`,
`moria8-plus4.crt`, `moria8-cx16.crt`, `moria8-atari8.car`) load resident code,
overlays, and monster/item catalogs directly from read-only cartridge ROM, so
no program disk swaps are needed during play. However, saves and high scores
still require writable storage configured in **`D)isk Setup`** on the title
screen:

- **C64 / C128 / Plus/4 cartridges:** Attach a separate writable `.d64`/`.d71`/
  `.d81` disk (devices 8–11) and initialize it with `D)isk Setup`.
- **Atari 8-bit AtariMax `.car`:** `D)isk Setup` shows `Program: Cartridge`
  and `1) Use D1: for saves` (or `2) Pick save drive` for `D1:`–`D4:`). Attach
  a writable DOS 2.5 `.atr` save disk (do not leave a Program Disk containing
  `TITLE.DAT` in the save drive).
- **Commander X16 `.crt`:** Attach an SD card or pass `-fsroot <dir>` in
  `x16emu` for writable save storage on device 8–11.

## Apple IIe Storage Errors

The Apple IIe port reports ProDOS MLI errors through its storage status
mapping (`platforms/apple2/storage_mli.s`): write-protected media, disk
full, and wrong-media verdicts are shown as friendly status text, and the
boot loader halts with the MLI error code in the top-left screen cell if
`MORIA8.PAK` cannot be opened or read. Save-media rejection alternates
with the insert-save prompt and cancels back to the menu with `Q` or ESC.

## Commander X16 Storage

The Commander X16 port uses KERNAL storage (`program_device` and `save_device`
default to device `8`; `D)isk Setup` supports selecting devices `8`–`11`).
Overlays, catalogs, and auxiliary data preload into banked HiRAM at boot, so
runtime disk reads occur only for save/load and high scores.

- **`Drive not found.`:** `D)isk Setup` only accepts IEC/HostFS device numbers
  `8`–`11`.
- When launching `build/moria8-cx16.zip` in `x16emu`, extract the archive and
  pass `-fsroot <extracted_dir>` so `MORIA8.PRG` can preload all companion files.

## Atari 8-bit (`800XL` / `130XE`) Storage Errors

The Atari 8-bit disk port uses direct OS `SIOV` sector I/O (`D1:`–`D4:`) on
Enhanced Density DOS 2.5 `.atr` images. The `130XE` automatically caches
overlays, monster tiers, and title art in extended RAM (`PORTB`), while a
`64 KB` `800XL`/`65XE` streams overlays and tiers from `D1:` on demand.

- **`Program disk cannot hold saves.`:** Moria8 refuses to write saves or
  markers onto any disk containing `TITLE.DAT`. Use a separate `.atr` save disk
  in `D2:`–`D4:` (or swap disks in `D1:` in 1-drive mode).
- **`No Save Disk marker found.` / `Initialize this disk? (Y/N)`:** The
  selected save disk lacks the `MORIA8.ID` (`M8SAVE`) DOS 2.5 marker; press `Y`
  to initialize it with `MORIA8.ID`, `HISCORE.DAT`, and `SAVE0..3.SAV`.
- **`Disk error.`:** `SIOV` reported a drive timeout, write-protect tab, or I/O
  error on the target drive. Check that the `.atr` save disk is writable and
  attached to the selected drive.

## Acorn BBC Master 128 Storage & Boot Errors

The BBC Master 128 port uses Acorn DFS (`:0`–`:3`) via `OSFILE`/`OSGBPB`
protected by `BRKV`.

- **`!` at boot:** `MORIA8` (`!BOOT` / `*RUN MORIA8`) prints `!` and halts if
  `MORIA8.PAK` (`MORIA8P` on DFS) cannot be opened or read during initial RAM
  preloading. Confirm `moria8-bbcmaster.ssd` is mounted in `:0` and booted with
  `*EXEC !BOOT` (or `SHIFT+BREAK`).
- **`Program disk cannot hold saves.`:** Moria8 refuses to write onto any DFS
  disk containing `TITLE`. Use a separate `.ssd` save disk in `:1`–`:3` (or
  swap in `:0` in 1-drive mode).
- **`No Save Disk marker found.` / `Initialize this disk? (Y/N)`:** The
  selected save disk lacks the `MORIAID` (`M8SAVE`) marker; press `Y` to
  initialize it.
- **`Disk error.`:** Acorn DFS raised a `BRK` disk fault (drive not ready,
  write-protected, or disk full) during save, load, or disk initialization.

## Commodore I/O Errors

Moria8 storage failures can come from two places:

- The Commodore DOS status returned by the drive command channel.
- The KERNAL status byte (`$ST`) plus a Moria8 phase byte that identifies which
  storage step failed.

The current compact messages preserve diagnostic data. They are not the final
friendly text design.

### Current Display Forms

| Message form | Meaning |
| --- | --- |
| `Disk error! 74` | The drive returned Commodore DOS status code `74`. |
| `Disk code $00 phase $83` | The drive did not report a DOS error, but Moria8 failed during phase `$83`. |
| `Disk ST $xx phase $yy` | KERNAL `$ST` was nonzero during phase `$yy`. |
| `Wrong Save Disk.` | The disk responded, but the Moria8 save marker was missing or did not match. |
| `Need Save Disk.` | Disk Setup has not selected or validated save media for this session. |

### Commodore DOS Codes

These are the high-value drive status codes currently worth mapping to friendlier
text first.

| Code | Meaning | Useful player text |
| --- | --- | --- |
| `00` | OK | Not a drive failure by itself. Check the Moria8 phase. |
| `26` | Write protect on | Disk is write-protected. Use a writable disk. |
| `62` | File not found | Save file or marker was not found. Check the save disk. |
| `72` | Disk full | Disk is full. Use another save disk. |
| `74` | Drive not ready | Drive is not ready. Insert/attach a disk and check the drive. |

### Moria8 Storage Phases

Phase bytes are Moria8 diagnostics, not Commodore DOS status codes.

| Phase | Context |
| --- | --- |
| `$81` | Save marker open/check start failed. |
| `$82` | Save marker input channel setup failed. |
| `$83` | Save marker read/compare failed. |
| `$92` | Save marker create/open failed. |
| `$93` | Save marker output channel setup failed. |
| `$94` | Save marker write failed. |
| `$95` | Save marker close failed. |
| `$96` | Save marker DOS status check failed. |
| `$97` | Save marker scratch/delete failed. |
| `$a1` | Save file open failed. |
| `$a2` | Save file output channel setup failed. |
| `$a3` | Save file write failed. |
| `$b1` | Save file load/open failed. |
| `$b2` | Save file input channel setup failed. |
| `$b3` | Save file read failed. |
| `$c1` | High-score load failed. |
| `$c2` | High-score save failed. |

### Backlog

The next UI improvement is to classify common DOS codes and phase groups into
short friendly text while keeping the raw code/phase fallback for unmapped
failures.
