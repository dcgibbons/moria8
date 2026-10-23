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
│   ├── bbcmaster/         # Acorn BBC Master 128 (65C12, Sideways RAM, Mode 0 LYNNE)
│   └── nes/               # PPU, APU, Mappers
├── data/                  # Shared game assets, strings, levels
├── tools/                 # Build tools (Python scripts, Asset Converters)
└── docs/                  # Architectural documentation
```

## 2. The Assembler & ISA (Instruction Set Architecture)

* **The 6502 Track:** All active 6502/65C02 ports (C64, C128, Plus/4, Apple IIe,
  Commander X16, Atari 8-bit) retain Kick Assembler per in-tree precedent; the
  earlier `ca65` migration note is superseded. Platform-specific configurations
  and segmenting are handled with Kick Assembler segment directives. The `core/`
  game logic targets the standard 6502/65C02.
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

## 8. Atari 8-Bit Release Track

The Atari 8-bit port lives under `platforms/atari8/` (design & execution plan:
`docs/ATARI8_PORT_PLAN.md`; memory authority: `docs/ATARI8_MEMORY_CONTRACT.md`).

* Source lives under `platforms/atari8/` and links the unmodified `core/` and
  `platforms/shared/` modules through the semantic HAL policy contracts with
  40×25 gameplay geometry (`80×48` map = `3,840` B, identical to C64 and Plus/4).
* The release target is a stock **64 KB Atari 800XL / 65XE** baseline (PIA
  `PORTB` `$D301` banking RAM under OS ROM at `$C000-$CFFF` and `$D800-$FFFF`)
  with automatic runtime detection of **128 KB Atari 130XE** extended RAM (`4 ×
  16 KB` banks at `$4000-$7FFF`, preloading hot overlays, Tier 1, and title art
  at boot and write-allocating cold overlays/tiers on first load across 15 of
  the 16 available 4 KB slots).
* Memory model (authority: `docs/ATARI8_MEMORY_CONTRACT.md`):
  * `$D000-$D7FF` (`GTIA`, `POKEY`, `PIA`, `ANTIC`) is an immovable 2 KB hardware
    I/O hole, and `$0200-$031A` is preserved untouched for Atari OS vectors,
    Page 2 display/timer shadows, and the `SIOV` DCB.
  * Because `PORTB` bit 0 controls OS ROM visibility for both the CPU and ANTIC,
    and because the Atari XL/XE MMU disables RAM `CAS` (dropping CPU writes to
    `$C000-$CFFF` and `$D800-$FFFF`) while OS ROM is enabled, all ANTIC display
    structures (`ATARI_DISPLAY_LIST` at `$0380`, 1 KB C64-screen-code-ordered RAM
    font `ATARI_CHARSET_BASE` at `$0400`, and `SCREEN_RAM` at `$0800-$0BE7`) plus
    `EnterSio`/`ExitSio`, `hal_asset_load_prg_header`, the `SIOV` 128-byte sector
    bounce buffer (using named platform ZP labels in `$0092-$00AF`, with `$0090`
    reserved for `zp_kernal_status`), interrupt/exit handlers, and 130XE
    bank-copy helpers (executed with `SEI`, `NMIEN = $00`, and `STA NMIRES`
    before restoring `NMIEN = $C0`) reside in fixed low RAM below `$4000`.
  * Resident code/data fills `$0C00-$C0FF` (entered at `entry_main` in `< $4000`
    from `boot.s` at `$0800`); `MAP_BASE` (`$C100-$CFFF`, `15` pages = `3,840` B,
    zero linked code) sits immediately below the `$D000` I/O hole; high
    RAM under OS ROM (`$D800-$FFFF`) holds `PLATFORM_TIER_NAME_POOL_BASE`
    (`$D800-$DBFF`), `FLOOR_ITEM_BASE` (`$DC00-$DCFF`),
    `PLATFORM_HD_DECODE_BUF_BASE` (`$DD00-$DD3F`), `zp_save_buf`
    (`$DD40-$DDCD`), `msg_history` (`$DDCE-$DF0D`), the shared `$E000-$EFFF`
    overlay/tier window, `RuntimeBanked` (`$F000-$FFF9`), and RAM CPU vectors
    (`$FFFA-$FFFF`).
* Display uses a custom 40×25 ANTIC Mode 2 Display List (`200` scanlines),
  zero-translation screen-code rendering via the C64-ordered 1 KB RAM font at
  `$0400`, classic monochrome LOS differentiation (`.` for lit floor vs ` ` for
  remembered out-of-LOS floor), hardware bit-7 inverse video for player/cursor/
  status highlights, and a self-healing VBI->DLI horizontal color chain
  (disabled via `NMIEN = $40` during `SIOV` calls to prevent 19,200-baud serial
  overruns).
* Shipping media is a self-contained **130 KB Enhanced Density (`1,040 × 128 B`
  sectors) Atari DOS 2.5 compatible `.atr`** (`build/moria8-atari8.atr`) built
  by `tools/make_atr.py`, booted without resident `DOS.SYS` using ROM `SIOV`
  (`$E459`) 10-bit sector-link reads (`$7D` byte count, `$7E` `(file_index << 2) | link_hi`,
  `$7F` `link_lo`) and contiguous pre-allocated 56-sector (`7,000` B) save slots
  (`SAVE0.SAV`..`SAVE3.SAV`), `MORIA8.ID`, `HISCORE.DAT`, `LICENSE.TXT`, and
  `SRCOFFER.TXT` on `D1:`.
* Testing uses headless MAME (`a800xl` 15-scenario behavioral suite + `a130xe`
  3-scenario cache/SIO suite) driven by `platforms/atari8/harness_smoke.py`.

## 9. Acorn BBC Master 128 Release Track

The Acorn BBC Master 128 port lives under `platforms/bbcmaster/` (design &
execution plan: `docs/BBCMASTER_PORT_PLAN.md`; memory authority:
`docs/BBCMASTER_MEMORY_CONTRACT.md`).

* Source lives under `platforms/bbcmaster/` and links the unmodified `core/`
  and `platforms/shared/` modules with `80×24` gameplay geometry (`198×66` map =
  `13,068` B, identical to C128, Apple IIe, and Commander X16).
* The release target is a stock **128 KB Acorn BBC Master 128** (2 MHz 65C12,
  MOS 3.20, DFS 2.24, 32 KB Main RAM, 20 KB Shadow Screen RAM `LYNNE`, 4 KB
  Private RAM `ANDY`, 8 KB Filing/System RAM `HAZEL`, and 64 KB Sideways RAM in
  slots 4–7).
* Memory model (authority: `docs/BBCMASTER_MEMORY_CONTRACT.md`):
  * Unbanked Main RAM (`$0E00-$7FFF`, `29,184` B) holds the Always-Resident
    image (`MORIA8.RES`), with all `ACCCON`/`ROMSEL` switching helpers,
    Mode 0 glyph blitter, and MOS storage wrappers linked strictly below `$3000`
    (`$0E00-$2FFF`), `WRCHV` (`$020E`) redirected to `rts`, and `VDU 23,1,0;0;0;0;`
    disabling the MOS 100 Hz software cursor timer; `$0400-$07FF` (Language
    Workspace) holds `FLOOR_ITEM_BASE`, `CREATURE_BASE`, Huffman/door scratch,
    MOS `OSFILE`/`OSGBPB`/`OSWORD` parameter blocks, and the 256-byte save/bounce
    buffer (`beeb_ss_buf`).
  * 20 KB Shadow Screen RAM `LYNNE` (`$3000-$7FFF`, `ACCCON` bit `D = 1` for
    CRTC display and bit `X = 1` for row-bracketed CPU access from `< $3000`)
    hosts `beeb_font_table` (`$3000-$33FF`, 1 KB C64-ordered font),
    `DUNGEON_GEN_SCAN_SCRATCH_BASE` (`$3400-$37FF`), `beeb_char_shadow`
    (`$3800-$3F7F`, `80×24` C64 screen-code shadow buffer for dirty-cell skipping
    and MAME Lua harness inspection), and the active `80×24` Mode 0 bitmap
    (`$4400-$7FFF`, `15,360` B, CRTC `R12=$08, R13=$80`).
  * 4 KB Private RAM `ANDY` (`$8000-$8FFF`, `ROMSEL` bit 7 = `1`) hosts
    `BeebHuffData` linked directly at physical `$8000-$8D93` and decoded under
    `HAL_HUFFMAN_LOCK_IRQ_DURING_DECODE = 1` (`ROMSEL = $84`) with zero per-byte
    bank-switch thunks.
  * 64 KB Sideways RAM (`$8000-$BFFF`, `ROMSEL = 4..7`) hosts:
    * Bank 4 (`$04`): Active execution bank (`BeebPlaySlot` `$8000-$A3FF`,
      `PLATFORM_TIER_NAME_POOL_BASE` `$A400-$A7FF`, and the active Overlay/Tier
      window `$A800-$BFFF`).
    * Bank 5 (`$05`): Live 198×66 Dungeon Map (`$8000-$B30B`) plus cached
      `OVL.UI` (`$B400-$BDFF`, with `512` B free slack at `$BE00-$BFFF`).
    * Bank 6 (`$06`): `BeebAuxData` (`$8000-$96FF`, `5,888` B budget = `718` B
      slack, virtual `$6000-$76FF`) plus cached `OVL.TOWN`, `OVL.MODAL`, and
      `MONSTER.DB1` (`512` B free slack at `$BE00-$BFFF`).
    * Bank 7 (`$07`): Cached `OVL.SPELL`, `OVL.ITEMS`, and `OVL.GEN` (`512` B
      free slack at `$BE00-$BFFF`), with cold modal overlays (`OVL.START`,
      `OVL.DEATH`, `OVL.HELP`, `OVL.CHEST`, `OVL.STORAGE`, `OVL.TITLE`),
      `MONSTER.DB.2..4`, and `TITLE` loaded on demand via MOS `OSFILE`.
* Shipping media is a self-contained **200 KB 80-track single-sided Acorn DFS
  `.ssd` Program Disk** (`build/moria8-bbcmaster.ssd`, `*OPT 4, 3`) built by
  `tools/make_ssd.py`, booted via `!BOOT` -> `MORIA8` (`boot.s`) streaming
  `MORIA8P`, plus `LICENSE` and `SRCOFFR` (Rule 7). Saves are never written to
  the Program Disk; Disk Setup (`disk_setup_beeb.s`) supports 1-drive swap (`:0`)
  and 2-drive (`:0`..`:3`) modes, rejects the Program Disk (`TITLE` check), and
  initializes a separate Save Disk with `MORIAID` (`"M8SAVE"`), `HISCORE`, and 4
  pre-allocated contiguous 64-sector (`16,384` B) save slots (`SAVE0`..`SAVE3`)
  updated in place via `OSFIND A=$C0`.
* Testing uses headless MAME (`bbcm`) driven by
  `platforms/bbcmaster/harness_smoke.py` (gated by `BBCMROMS`).

## 10. Current Codebase Assessment & Next Steps

Moria8 is currently well-positioned because the 8-bit logic is increasingly platform-agnostic.

**Strategic Phasing:**

1. **Decoupling:** Keep shared 8-bit logic in the top-level `core/` directory.
2. **Parallel Cores:** Establish `core_z80/` to begin the native Z80 rewrite.
3. **Active Parallel Development:** Implement basic renderers (HAL) for both
   6502 and Z80 targets to validate hardware paradigms side-by-side.
