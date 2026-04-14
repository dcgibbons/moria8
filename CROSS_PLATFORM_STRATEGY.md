# Moria8 Cross-Platform Strategy

This document outlines the architectural strategy and necessary steps to transition the Moria8 codebase from a Commodore-specific project to a multi-platform 6502 engine capable of targeting the Commodore 64/128, Commodore Plus/4, Commander X16, Apple II (8-bit), Apple IIgs (16-bit), Atari 8-bit (64KB XL/XE), BBC Master 128, and NES.

## 1. The Repository Structure
A true multi-platform project requires strict separation between game rules and hardware execution.

**Proposed Structure:**
```text
/
├── core/                  # Platform-agnostic game logic (math, AI, RNG, Map Gen)
│                          # No hardware registers allowed here.
├── platforms/
│   ├── shared/            # Logic shared by architecture (e.g., 6502 vs 65C02 macros)
│   ├── commodore/         # Legacy MOS-era machines
│   │   ├── c64/           # VIC-II, SID, D64 Serial Bus
│   │   ├── c128/          # VDC, MMU, 2MHz mode
│   │   ├── plus4/         # TED chip, 64KB RAM
│   │   └── common/        # Shared KERNAL/VIC-II/SID/TED logic
│   ├── cx16/              # Commander X16 (65C02, VERA, FAT32/SD)
│   ├── apple2/            # Apple IIe/IIc (6502, 128K, Soft-switches, ProDOS)
│   ├── apple2gs/          # Apple IIgs (65C816, Super Hi-Res, GS/OS)
│   ├── atari8/            # Atari 8-bit (6502C, ANTIC, POKEY, 64KB XL/XE)
│   ├── acorn/             # Acorn/BBC Micro machines
│   │   └── bbcmaster/     # BBC Master 128 (65C02, Sideways RAM, Mode 7/0)
│   └── nes/               # PPU, APU, Mappers
├── data/                  # Game assets, strings, levels
├── tools/                 # Build tools (Python scripts, Asset Converters)
└── docs/                  # Architectural documentation
```

## 2. The Assembler & ISA (Instruction Set Architecture)
*   **The Assembler:** Migration from KickAssembler to `ca65` is necessary to support platform-specific memory configurations (`.cfg`), segmenting, and the 65C816 instruction set.
*   **The CPU Split:** 
    *   **MOS 6502/8502/6502C (C64/C128, Plus/4, Apple IIe, Atari 8-bit):** Standard instruction set. The Atari's "SALLY" CPU is standard 6502 with a HALT pin for DMA.
    *   **WDC 65C02 (CX16, Apple IIc/Enhanced IIe, BBC Master 128):** Enhanced set (`STZ`, `PHX/PHY`, `BRA`).
    *   **WDC 65C816 (Apple IIgs):** 16-bit registers, 24-bit addressing.
*   **Strategy:** The `core/` game logic will be written targeting the standard 6502/65C02 (8-bit) to ensure maximum compatibility.

## 3. The Hardware Abstraction Layer (HAL)
The HAL must provide zero-overhead interfaces for Video, Audio, and I/O.

### Video Paradigms
*   **C128 / CX16 / Apple II (80-col):** These share a text-based, indirect or character-mapped paradigm.
*   **C64 / Plus/4:** 40-column character-mapped video with custom charset support. The Plus/4 utilizes the TED chip, offering a 121-color palette but following the same fundamental rendering logic as the C64.
*   **BBC Master 128:** A strategic hybrid. The HAL will target **Mode 7** (Teletext) for low-memory, high-speed, 8-color character rendering (matching the C64 layout). For 80-column or custom charset requirements, it will utilize **Shadow RAM** to host Mode 0 or Mode 1 displays without encroaching on core game RAM.
*   **Apple IIgs (SHR):** Super Hi-Res offers a linear 320x200 4-bit framebuffer. 
*   **Atari 8-bit (ANTIC):** The Atari uses a video coprocessor (ANTIC) driven by a "Display List" in RAM. We will configure ANTIC Mode 2 (40x24 text) to match the C64 layout. The HAL will construct a display list to handle the Viewport/Status UI split without requiring raster interrupts.

### Storage & OS
*   **Commodore & Atari 8-bit:** Both utilize a slow serial bus (IEC vs. SIO). Disk I/O will require sector-level swapping or standard OS calls.
*   **Apple II / CX16 / Apple IIgs / BBC Master 128:** Fast block device access (ProDOS, FAT32, GS/OS, ADFS/DFS).
*   **Abstraction:** Filesystem access must be moved to an `io_service` layer that abstracts the difference between serial sector reads and block-level file I/O (e.g., Acorn MOS `OSFILE` vs. Commodore `LOAD`).

## 4. Memory Management & Overlays
Moria8 uses a **Resource Window** paradigm, typically at `$E000-$EFFF` (4KB).

### The "Disk-Bound" 64KB Targets (C64, Plus/4, & Atari XL/XE)
*   **Baseline:** The C64, Plus/4, and Atari XL/XE provide a full 64KB by allowing the OS ROM to be banked out.
*   **48KB Exclusion:** Older 48KB machines (Atari 400/800) and 32KB PET models are not supported due to the memory constraints of the shared engine.
*   **Strategy:** Overlays will be loaded on-demand from disk (SIO/IEC), identical to the C64 strategy.
*   **Future Optimization:** 128KB Atari models (130XE) and those with PORTB banking expansions will be considered later as a "Resident Overlay" target to eliminate load times.

### The "Resident Overlay" Advantage (Apple IIe, IIgs, CX16, BBC Master 128)
*   **Apple IIe/IIc (128K):** Soft-switch banking swaps Aux RAM into the execution window.
*   **Apple IIgs & CX16:** Large memory (1MB+ / 512KB+) allows all overlays to be pre-loaded, turning resource invocation into zero-latency bank switches or long calls.
*   **BBC Master 128:** Utilizes **Sideways RAM** (16KB banks paged at `$8000-$BFFF`). All game overlays and tier data are cached in Sideways banks 4-15, effectively eliminating disk access after the initial bootstrap.

## 5. Current Codebase Assessment & Next Steps
Moria8 is currently well-positioned because:
*   **Pure Logic (~60%):** Most gameplay code is in `commodore/common/` but is actually platform-agnostic.
*   **C128 Precedent:** The C128 port already implements VRAM-indirect rendering and memory banking.

**Strategic Phasing:**
1.  **Decoupling:** Move `monster_ai.s`, `math.s`, and `dungeon_gen.s` from `commodore/common/` to a new top-level `core/` directory.
2.  **HAL Formalization:** Define `platform_services_api.inc` that all targets must implement.
3.  **Cross-Platform Prototypes:** Implement basic text-mode renderers in `platforms/cx16/`, `platforms/apple2/`, `platforms/atari8/`, `platforms/commodore/plus4/`, and `platforms/acorn/bbcmaster/` to validate the display and banking abstractions.
