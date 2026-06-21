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

* **The 6502 Track:** Migration from KickAssembler to `ca65` supports
  platform-specific configurations (`.cfg`) and segmenting. The `core/` game
  logic targets the standard 6502/65C02.
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

* **128K+ 8-bit (Apple IIe, IIgs, CX16, BBC Master 128):** All game overlays and
  tier data are pre-loaded into extended/paged memory.

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

## 6. Commander X16 Bring-Up Track

The Commander X16 port is a first-class 65C02 platform under `platforms/cx16/`,
not a Commodore subtarget. The initial milestone is deliberately narrow:
boot a PRG under `x16emu`, initialize text output, render the Moria8
title/menu, enter a CX16-owned fixed-memory town bootstrap, and acknowledge
basic movement input there.

Current assumptions:

* Build remains Kick Assembler for the first slice.
* Baseline RAM is 512 KB, using fixed RAM below `$9F00` plus 64 banks exposed
  through the `$A000-$BFFF` banked-RAM window. The enforced policy lives in
  `docs/CX16_MEMORY_POLICY.md`, `platforms/cx16/memory.s`, and
  `platforms/cx16/check_memory_contract.py`.
* The normal product PRG loads at `$0801`; machine code starts at `$0810` and
  must end before the fixed live-map base at `$6800`. Title art loads as a
  bank-window PRG at `$A000` into RAM bank 11 as a title-art source bank, so it
  does not pin resident code below an old fixed-RAM staging address.
* Display target is VERA 80x30 text. The first title screen centers the
  existing 40-column title composition inside the wider display.
* The current new-game path renders a deterministic 66x22 town through
  `core/town_map_basic.s`, using the shared town/map constants and
  store-position tables, backed by fixed RAM at `MAP_BASE` (`$6800`) with the shared
  198-byte row stride. This is still a bootstrap renderer, not the full shared
  game loop.
* The live shared map is deliberately fixed RAM, not banked RAM. The 198x66
  map is 13,068 bytes, larger than one 8 KiB CX16 banked-RAM window, so moving
  it behind `$A000-$BFFF` would require explicit split-window map accessors.
* CX16 bootstrap town rendering uses the shared tile byte to screen-code/color
  mapping in `core/tile_display.s`; the VERA text backend remains
  platform-owned.
* CX16 bootstrap town interactions use the dependency-light store-door and
  stairs probes in `core/town_interactions_basic.s`; full store UI remains
  deferred. Stairs-down now enters a visible dungeon bootstrap milestone: it
  loads `MONSTER.DB.1` into CX16 RAM bank 4, loads and probes the executable
  `DUNGEON.GEN` module in CX16 RAM bank 8 at `$A000`, records depth/tier state,
  runs the shared `core/dungeon_gen.s` generator into fixed RAM, and renders a
  78x22 VERA text viewport from the shared tile byte to screen-code/color
  mapping. Shared dungeon tile, flag, room, trap, generation-helper, and
  town constants live in `core/dungeon_consts.s` so CX16 wrappers and core
  generator probes do not duplicate game-domain byte values. The
  `check-dungeon-const-ownership` guard fails if CX16 or the core generator
  probe reintroduces local copies of those constants. CX16 VERA cell rendering
  and viewport redraw policy live in `platforms/cx16/map_render.s`; `main.s`
  owns state transitions and command dispatch. The banked dungeon generator
  ABI lives in `platforms/cx16/dungeon_module_contract.s`; the module is
  emitted from the normal CX16 assembly context as a separate `$A000` PRG, so
  it shares resident map row tables, player state, stairs, trap tables, and
  generation scratch instead of copying state through a CX16-specific output
  block.
  Store doors render as numbered entrances from the shared store-door metadata.
  Help, version, and character-info commands render CX16 bootstrap status text.
  Other mapped but not-yet-implemented town commands acknowledge by category
  (activity, item/feature, magic/recall, storage, info/map, wizard) instead of
  being silently ignored.
* CX16 bootstrap movement uses the shared player-position and tile-walkability
  contracts through `core/player_move_basic.s`. Full `player_try_move` remains
  outside the normal CX16 PRG because it still pulls in combat, monsters, traps,
  sound, search, and broader runtime state.
* Save/load and CMDR-DOS/FAT32 storage are deferred until after boot-to-title.
* `x16emu` is expected on `PATH` by default; `X16EMU=/path/to/x16emu` and
  `X16_ROM=/path/to/rom.bin` may override local tool and ROM locations.

Current shared-gameplay status:

* `make testcx16` is the current CX16 gate. It runs setup smoke, x16emu
  runtime smoke, and the guarded shared-gameplay link probe.
* `make testcx16-shared-link` is a link-only probe for the guarded shared
  gameplay import path. It verifies that CX16 imports, constants, and
  trampolines still satisfy the shared code's assembly-time contracts.
  The probe is intentionally asserted as non-runtime-safe while its linked
  image crosses the fixed live-map base and VERA I/O hole.
  `platforms/cx16/check_memory_contract.py` also checks the generated product
  and shared-probe PRG load spans against their symbol files so this distinction
  is mechanically enforced by `make testcx16-memory-contract` and reported as
  concrete product/probe memory spans, product fixed-code headroom, and
  shared-probe overrun across the live-map, VERA I/O, and bank-window regions.
  The same gate validates the generated CX16 `MONSTER.DB.1` through
  `MONSTER.DB.4` tier payloads as `$A000` bank-window PRGs that fit inside one
  8 KiB RAM bank. It also validates the generated `DUNGEON.GEN` module as a
  `$A000` bank-window PRG that fits inside one 8 KiB RAM bank. The
  memory-contract self-test covers the checker's positive and negative contract
  cases without assembling the retired basic-generator probe as part of CX16
  validation.
  `make testcx16-memory-contract-selftest` covers the checker's positive and
  negative contract cases, including stale PRG/symbol mismatches.
* `make testcx16-runtime` runs an x16emu `-testbench` smoke check against the
  normal CX16 PRG. It verifies RAM-visible bootstrap contracts: town generation,
  player position, store-door detection, stairs detection, title asset loading,
  VERA text output, command feedback messages, exported memory-contract
  symbols, `$A000-$BFFF` RAM-bank isolation, and the scoped bank-window copy
  helpers used to move fixed-RAM data into and back out of selected CX16 RAM
  banks without leaving the caller on the wrong bank. It also loads
  `MONSTER.DB.1` through the product tier loader into RAM bank 4, verifies the
  resulting banked payload byte-for-byte against the generated PRG, loads
  `DUNGEON.GEN` through the product dungeon-module loader into RAM bank 8,
  verifies the module payload byte-for-byte against the generated PRG, checks
  the `$A000` entry ABI tuple, confirms an unowned guard bank remains untouched, validates the
  generated shared-map tile bytes for rooms, connectors, doors, rubble, quartz,
  trap, and stairs, and checks the visible stairs-down dungeon bootstrap map,
  viewport rendering, movement, blocked-wall behavior, and upstairs return to
  town.
* The probe is not a runtime-safe memory placement. The linked image currently
  crosses the fixed-RAM map/scratch plan and the CX16 `$A000-$BFFF` banked-RAM
  window.
* Runtime enablement must keep the live map in fixed RAM with resident code
  below it. Banked resident databases or cached payloads must use the CX16
  bank-window helpers rather than direct, unscoped writes to `$00`/`$A000`.
  Bank 0 is the default/system bank; banks 1-3 are transient scratch; banks
  4-7 hold `MONSTER.DB.1` through `MONSTER.DB.4`; bank 8 holds
  `DUNGEON.GEN`; banks 9-10 are the item-catalog family; bank 11 is the
  title-art source bank; banks 12-21 hold preloaded CX16 overlay sidecar PRGs
  `X16.START`, `X16.TOWN`, `X16.DEATH`, `X16.ROYAL`, `X16.GEN`, `X16.HELP`,
  `X16.UI`, `X16.ITEMS`, `X16.SPELL`, and `X16.DISARM` as marker payloads
  until the real shared overlay code is migrated; banks 22-31, 32-47, and
  48-63 are defined unallocated classes for overlay expansion, immutable
  data/string caches, and transient work respectively. The CX16 wrapper calls the common
  `core/dungeon_gen.s` generator after seeding the shared RNG. Future dungeon
  work must preserve that load address, entry point, caller-bank restoration,
  fixed-RAM map ownership, and one-bank fit instead of adding CX16-specific map
  rules.
  Do not enable the guarded shared loop in the normal CX16 PRG until the code,
  map, floor-item table, creature scratch, generation queue, and bank-window
  database ownership are all asserted in one runtime-safe placement.

## 7. Current Codebase Assessment & Next Steps

Moria8 is currently well-positioned because the 8-bit logic is increasingly platform-agnostic.

**Strategic Phasing:**

1. **Decoupling:** Keep shared 8-bit logic in the top-level `core/` directory.
2. **Parallel Cores:** Establish `core_z80/` to begin the native Z80 rewrite.
3. **Active Parallel Development:** Implement basic renderers (HAL) for both
   6502 and Z80 targets to validate hardware paradigms side-by-side.
