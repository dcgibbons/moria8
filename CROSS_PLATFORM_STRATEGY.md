# Moria8 Cross-Platform Strategy

This document outlines the architectural strategy and necessary steps to transition the Moria8 codebase from a Commodore-specific project to a multi-platform 6502 engine capable of targeting the Commodore 64/128, Commander X16, Apple II (8-bit), Apple IIgs (16-bit), and NES.

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
│   │   └── common/        # Shared KERNAL/VIC-II/SID logic
│   ├── cx16/              # Commander X16 (65C02, VERA, FAT32/SD)
│   ├── apple2/            # Apple IIe/IIc (6502, 128K, Soft-switches, ProDOS)
│   ├── apple2gs/          # Apple IIgs (65C816, Super Hi-Res, GS/OS)
│   └── nes/               # PPU, APU, Mappers
├── data/                  # Game assets, strings, levels
├── tools/                 # Build tools (Python scripts, Asset Converters)
└── docs/                  # Architectural documentation
```

## 2. The Assembler & ISA (Instruction Set Architecture)
*   **The Assembler:** Migration from KickAssembler to `ca65` is necessary to support platform-specific memory configurations (`.cfg`), segmenting, and the 65C816 instruction set.
*   **The CPU Split:** 
    *   **MOS 6502/8502 (C64/C128, Apple IIe):** Standard instruction set.
    *   **WDC 65C02 (CX16, Apple IIc/Enhanced IIe):** Enhanced set (`STZ`, `PHX/PHY`, `BRA`).
    *   **WDC 65C816 (Apple IIgs):** 16-bit registers, 24-bit addressing.
*   **Strategy:** The `core/` game logic will be written targeting the standard 6502/65C02 (8-bit) to ensure maximum compatibility. The Apple IIgs will execute the `core/` in 8-bit mode (or native mode with 8-bit registers), while its `platforms/apple2gs/` HAL leverages 16-bit instructions for OS and hardware interfacing.

## 3. The Hardware Abstraction Layer (HAL)
The HAL must provide zero-overhead interfaces for Video, Audio, and I/O.

### Video Paradigms
*   **C128 / CX16 / Apple II (80-col):** These share a text-based, indirect or character-mapped paradigm. The `apple2` port can map directly to the 80-column text screen, avoiding the notorious complexity of Double Hi-Res (DHGR).
*   **Apple IIgs (SHR):** Super Hi-Res offers a linear 320x200 4-bit framebuffer. The HAL here will translate the text-based UI/Viewport calls from `core/` into bitmap tile drawing, functioning more like a modern 2D engine.

### Storage & OS
*   **Commodore:** Slow serial bus (IEC) and sector-level disk swapping.
*   **Apple II (ProDOS 8):** Fast block device access with a real hierarchical filesystem.
*   **CX16 / Apple IIgs:** Modern FAT32/SD or GS/OS filesystems.
*   **Abstraction:** Filesystem access must be moved to an `io_service` layer that abstracts the difference between a D64 sector read and a ProDOS/GSOS file `read()` call.

## 4. Memory Management & Overlays
Moria8 uses a **Resource Window** paradigm, typically at `$E000-$EFFF` (4KB).

### The Apple II Ecosystem Divergence
**Apple IIe/IIc (128K): Soft-Switch Banking**
*   The Apple II 128K uses "Auxiliary RAM" switched via hardware registers at `$C000`.
*   Overlays can be loaded from ProDOS into Aux RAM.
*   When `invoke_resource(RES_ID)` is called, the HAL toggles the soft-switch to map Aux RAM into the Main RAM execution window, executing the overlay, and switching back upon completion.

**Apple IIgs & CX16: The "Resident Overlay" Advantage**
*   Both the IIgs (1MB+ flat RAM) and CX16 (512KB+ banked High RAM) have enough memory to hold the entire game simultaneously.
*   On these platforms, the bootloader pre-loads all `ovl.*` files into memory.
*   `invoke_resource(RES_ID)` becomes a zero-latency bank switch (CX16) or a simple long `JSL` subroutine call (IIgs).

## 5. Current Codebase Assessment & Next Steps
Moria8 is currently well-positioned because:
*   **Pure Logic (~60%):** Most gameplay code is in `commodore/common/` but is actually platform-agnostic.
*   **C128 Precedent:** The C128 port already implements VRAM-indirect rendering and memory banking.

**Strategic Phasing:**
1.  **Decoupling:** Move `monster_ai.s`, `math.s`, and `dungeon_gen.s` from `commodore/common/` to a new top-level `core/` directory.
2.  **HAL Formalization:** Define `platform_services_api.inc` that all targets must implement.
3.  **CX16 / Apple II Prototypes:** Implement basic text-mode renderers in `platforms/cx16/` and `platforms/apple2/` to validate the display and banking abstractions before attempting the more complex IIgs SHR graphics layer.
