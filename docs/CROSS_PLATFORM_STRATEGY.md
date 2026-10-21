# Moria8 Cross-Platform Strategy

This document outlines the architectural strategy and necessary steps to
transition the Moria8 codebase from a Commodore-specific project to a
multi-platform engine, establishing parallel tracks for 8-bit architectures.

## 1. The Repository Structure

A true multi-platform project requires strict separation between game rules and
hardware execution. The various 8-bit versions exist as parallel tracks to
ensure native performance and idiomatic hardware utilization.

**Current and Proposed Structure:**

```text
/
├── core/                  # Platform-agnostic 6502 game logic
│                          # No hardware registers allowed here.
├── core_z80/              # Z80 native rewrite of game logic (Parallel Core)
├── platforms/
│   ├── shared/            # Cross-architecture helper logic
│   ├── commodore/         # Legacy MOS-era machines
│   │   ├── c64/           # VIC-II, SID, D64 Serial Bus
│   │   ├── c128/          # VDC, MMU, 2MHz mode
│   │   ├── plus4/         # TED chip, 64KB RAM
│   │   └── common/        # Shared KERNAL/VIC-II/SID/TED logic
│   ├── z80/               # Zilog Z80 machines
│   │   ├── cpm/           # CP/M 2.2 (ANSI/VT100 Terminal)
│   │   ├── zxspectrum/    # ZX Spectrum (48K/128K bitmapped)
│   │   └── msx/           # MSX/MSX2 (VDP)
│   ├── cx16/              # Commander X16 (65C02, VERA, FAT32/SD)
│   ├── apple2/            # Apple IIe/IIc (6502, 128K, Soft-switches, ProDOS)
│   ├── apple2gs/          # Apple IIgs (65C816, Super Hi-Res, GS/OS)
│   ├── atari8/            # Atari 8-bit (6502C, ANTIC, POKEY, 64KB XL/XE)
│   ├── acorn/             # Acorn/BBC Micro machines
│   │   └── bbcmaster/     # BBC Master 128 (65C02, Sideways RAM, Mode 7/0)
│   └── nes/               # PPU, APU, Mappers
├── data/                  # Shared game assets, strings, levels
├── tools/                 # Build tools (Python scripts, Asset Converters)
└── docs/                  # Architectural documentation
```

## 2. The Assembler & ISA (Instruction Set Architecture)

* **The 6502 Track:** All active 6502/65C02 ports (C64, C128, Plus/4, Apple IIe,
  Commander X16) retain Kick Assembler per in-tree precedent; the earlier `ca65`
  migration note is superseded. Platform-specific configurations and segmenting
  are handled with Kick Assembler segment directives. The `core/` game logic
  targets the standard 6502/65C02.
* **The Z80 Track:** A native rewrite of the game logic specifically for the
  Zilog Z80. Using `z88dk` (`z80asm`) or `sjasmplus`, this track establishes a
  parallel `core_z80/` for native efficiency on CP/M, ZX Spectrum, and MSX.

## 3. The Hardware Abstraction Layer (HAL)

The HAL must provide zero-overhead interfaces for Video, Audio, and I/O.

### Video Paradigms

* **8-bit Character Mapping:** Character-mapped or indirect character-mapped
  paradigms for Commodore and Atari.
* **CP/M Terminal:** ANSI/VT100 serial terminal escape codes for text rendering
  on business machines.
* **Z80 VDP/Bitmap:** Bitmapped rendering for ZX Spectrum and
  hardware-accelerated tile rendering for MSX.

### Storage & OS

* **8-bit OS:** KERNAL, ProDOS, Acorn MOS, and TOS.
* **CP/M OS:** Standard CP/M 2.2 BDOS calls for disk I/O.

## 4. Memory Management & Overlays

Moria8 uses architectural tiers based on available address space and memory speed.

### The "Disk-Bound" 64KB Targets (C64, Plus/4, Atari XL/XE, & CP/M)

* **6502 Overlays:** Loaded on-demand from disk (SIO/IEC) into a small
  execution window.
* **CP/M Overlays:** Leverages the 50-54KB Transient Program Area (TPA) for a
  similar disk-swapping strategy to accommodate the dungeon and monster data on
  64KB business machines.

### The "Resident Overlay" Advantage

* **128K+ 8-bit (Apple IIe, IIgs, CX16, BBC Master 128):** Overlays and tier
  data use a partial cache in extended/paged memory with disk-on-demand loads
  for cold classes; full preloading of all overlays is not required. The
  Apple IIe port implements this as an aux-resident overlay cache with
  disk-backed cold classes.

## 5. Plus/4 Release Track

The Plus/4 port was implemented pragmatically during the Commodore HAL work and
now lives in the current `core/`/`platforms/` layout.

* Source lives under `platforms/commodore/plus4/` and reuses `core/` plus
  `platforms/commodore/common/` and the C64 40-column gameplay layout.
* The release target is stock 64K Plus/4 using standard Commodore DOS disk I/O
  with a 1541-compatible 35-track D64 artifact. The port must not require a
  1551-specific path.
* TED owns screen, color/attribute, sound, and ROM/RAM switching. C64 VIC-II,
  SID, CIA, REU, and `$01` banking assumptions must not leak into Plus/4 code.
* Plus/4 uses disk-loaded overlays like C64, but its low memory screen/attribute
  ownership moves the main-map window upward for this target.

## 6. Apple IIe Release Track

The Apple IIe port lives in the current `core/`/`platforms/` layout and is
the second 128K-class target after the C128.

* Source lives under `platforms/apple2/` and reuses `core/` with the shared
  Commodore HAL interfaces where they fit; platform code owns soft-switches,
  80-column text, ProDOS MLI storage, and the aux-memory mechanics.
* The release target is a stock 128K Apple IIe (extended 80-column card)
  running ProDOS 8 from a 140 KB `.po` disk image. Fixed machine identity:
  no IIc/IIgs variants, no RAM cards beyond the standard 64K aux bank.
* Memory model (authority: `docs/APPLE2_MEMORY_POLICY.md`): the 198x66
  dungeon map, the auxdata payload (Huffman data, item names, lookup
  tables), and the hot overlay cache live in aux RAM; resident code and the
  load-once play payload fill main RAM to `$9FFF`; 11 overlay classes share
  one `$A400-$B9FF` window. Cold classes (start, death, help, storage,
  title) stay on disk — the aux cache is a partial manifest, not a full
  preload.
* Boot is a ProDOS `.SYSTEM` file that streams a single-open container
  (`MORIA8.PAK`: resident + auxdata + six hot overlays) with an on-screen
  `n/8` progress line. The single sequential container replaces per-file
  open/read/close cycles, which seek-thrashed the directory and could lose
  the head under ProDOS 2.4.3 — the pattern to copy on any future target
  with a fragile DOS driver.
* The port's #1 correctness hazard is the RAMRD instruction-fetch trap:
  with aux reads switched in, instruction fetches from `$0200-$BFFF` come
  from aux, so all aux-read thunks execute from zero page. Any future
  banked target needs its thunk site chosen with the same care.
* The 80STORE main/aux text interleave drives renderer design: row staging
  in main RAM, then burst writes with two soft-switch toggles per row —
  never per-cell toggling.
* Testing is headless MAME (apple2ee) with a Lua harness asserting RAM
  contracts (never pixels) across 14 permanent scenarios. Two harness
  lessons are portable: entropy-from-input-timing makes dungeons
  timing-sensitive, so strict scenarios must pin the RNG; and
  heuristic screen sniffing (e.g. "in town") must tolerate legitimate
  dungeon features.

## 7. Commander X16 Release Track

The Commander X16 port lives under `platforms/cx16/` and is the third
128K+-class target (512 KB banked RAM + 38.6 KB unbanked low RAM) after the
C128 and Apple IIe.

* Source lives under `platforms/cx16/` and links the shared `core/` and
  `platforms/shared/` modules through semantic HAL policy contracts (`hal/layout.s`,
  `hal/lifecycle_policy.s`, `hal/storage_policy.s`, `hal/memory_bank_consts.s`,
  `hal/entropy_consts.s`, `screen_vera.s`, `input.s`) and a 12-overlay +
  banked-data layout (`Cx16AuxData`, `Cx16HuffData`).
* The release target is a stock 512 KB Commander X16 (65C02, VERA video,
  CX16 KERNAL R47/R48) running from a host/SD filesystem directory or
  shipping `.zip` bundle (`build/moria8-cx16.zip`).
* Memory model (authority: `docs/CX16_MEMORY_CONTRACT.md`):
  * Unbanked low RAM (`$0801-$9AFF`) holds the unified Resident + Play image;
    `$9B00-$9EFF` holds the active monster tier name pool (`1,024` B);
    `$0400-$07FF` holds `FLOOR_ITEM_BASE`, `CREATURE_BASE`, Huffman/door-scan
    scratch, and VERA row / file I/O staging; `$9F00-$9FFF` is the VERA/VIA
    hardware I/O hole.
  * Banked RAM (`$A000-$BFFF`, 8 KB × 64 banks via ZP `$00`) holds:
    * Bank 0: reserved for CX16 KERNAL (`KVARSB0`)
    * Banks 1–2: live 198×66 dungeon map (virtual `$2000-$530B`)
    * Bank 3: `Cx16AuxData` (`CX16.AUXDATA`, virtual `$6000-$7FFF`)
    * Bank 4: `Cx16HuffData` (`CX16.HUFFDATA`, virtual `$8000-$9FFF`)
    * Banks 5–8: preloaded monster tiers 1–4 (`MONSTER.DB.1..4`)
    * Banks 9–20: preloaded 12 code overlays (`OVL.START`..`OVL.TITLE`),
      executing directly in-place at `$A000-$BFFF` via `$00` bank selection
    * Bank 21: preloaded title screen artwork (`TITLE`).
* Unlike the Apple IIe, switching ZP `$00` on CX16 banks *only* `$A000-$BFFF`
  and never affects `$0000-$9EFF`, so resident map/aux/huffman accessors in
  fixed low RAM switch `$00`, perform the access in `$A000-$BFFF`, and restore
  `$00` directly without zero-page execution thunks.
* Display is 80×24 text in VERA VRAM (`$1B000`, 256-byte row stride,
  interleaved screen code + attribute bytes) streamed via `VERA_DATA0`
  auto-increment (`VERA_INC_1`).
* Testing is headless `x16emu -testbench` driven by `platforms/cx16/harness_smoke.py`
  across 20 permanent runtime scenarios.

## 8. Current Codebase Assessment & Next Steps

Moria8 is currently well-positioned because the 8-bit logic is increasingly platform-agnostic.

**Strategic Phasing:**

1. **Decoupling:** Keep shared 8-bit logic in the top-level `core/` directory.
2. **Parallel Cores:** Establish `core_z80/` to begin the native Z80 rewrite.
3. **Active Parallel Development:** Implement basic renderers (HAL) for both
   6502 and Z80 targets to validate hardware paradigms side-by-side.
