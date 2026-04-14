# Moria8 Cross-Platform Strategy

This document outlines the architectural strategy and necessary steps to transition the Moria8 codebase from a Commodore-specific project to a multi-platform 6502 engine capable of targeting the Commodore 64/128, Commander X16, Apple II, and NES.

## 1. The Repository Structure
A true multi-platform project requires strict separation between game rules and hardware execution. The Commander X16 (CX16), despite its Commodore-adjacent heritage, is a distinct 65C02-based machine and must not be grouped under Commodore-specific directories.

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
│   ├── apple2/            # Soft-switches, Mockingboard, ProDOS
│   └── nes/               # PPU, APU, Mappers
├── data/                  # Game assets, strings, levels
├── tools/                 # Build tools (Python scripts, Asset Converters)
└── docs/                  # Architectural documentation
```

## 2. The Assembler & ISA (Instruction Set Architecture)
*   **The Assembler:** Migration from KickAssembler to `ca65` is necessary to support platform-specific memory configurations (`.cfg`) and segmenting.
*   **The CPU Split:** 
    *   **MOS 6502/8502 (C64/C128):** Standard instruction set.
    *   **WDC 65C02 (CX16/Apple IIe):** Enhanced set (`STZ`, `PHX/PHY`, `BRA`).
*   **Strategy:** Utilize assembly-time macros to leverage 65C02 optimizations where available, while maintaining a standard 6502 fallback for legacy Commodore hardware.

## 3. The Hardware Abstraction Layer (HAL)
The HAL must provide zero-overhead interfaces for Video, Audio, and I/O.

### Video: VERA vs. VIC-II/VDC
The CX16's **VERA** (Video Embedded Retro Adapter) provides a massive architectural leap over the C64/C128:
*   **VRAM Access:** Similar to the C128's VDC (indirect registers), but significantly faster and without wait-state requirements.
*   **Layering:** Unlike the C64/C128 which require complex software "dirty-rect" logic or raster interrupts for UI/Viewport separation, VERA supports multiple layers. We can dedicate Layer 0 to the Map/Tile Viewport and Layer 1 to the UI/Text overlay.

### Storage: FAT32 vs. Commodore Serial
*   **CX16:** Native FAT32/SD card support via KERNAL.
*   **Commodore:** Slow serial bus (IEC) and sector-level disk swapping.
*   **Abstraction:** Filesystem access must be moved to an `io_service` layer that hides the difference between a D64 sector read and an SD card `fopen`.

## 4. Memory Management & Overlays
Moria8 uses a **Resource Window** paradigm, typically at `$E000-$EFFF` (4KB).

### The "Resident Overlay" Advantage (CX16)
While the C128 must swap overlays from disk into Bank 0 RAM (or REU), the CX16 has 512KB–2MB of High RAM.
1.  **Bootloader:** On CX16, the bootloader pre-loads all `ovl.*` files into High RAM banks (Banks 1–64).
2.  **Execution:** `invoke_resource(RES_ID)` on CX16 becomes a zero-latency bank switch (`sta $00`) instead of a disk load.
3.  **Portability:** The core game logic remains unaware if the overlay was loaded from a 1541 disk or simply banked in from High RAM.

## 5. Current Codebase Assessment & Next Steps
Moria8 is currently well-positioned because:
*   **Pure Logic (~60%):** Most gameplay code is in `commodore/common/` but is actually platform-agnostic.
*   **C128 Precedent:** The C128 port already implements VRAM-indirect rendering and memory banking, which are the two primary requirements for a CX16 port.

**Strategic Phasing:**
1.  **Decoupling:** Move `monster_ai.s`, `math.s`, and `dungeon_gen.s` from `commodore/common/` to a new top-level `core/` directory.
2.  **HAL Definition:** Formalize the `platform_services_api.s` to include VRAM and Banking primitives.
3.  **CX16 Prototype:** Implement a basic VERA text-mode renderer in `platforms/cx16/` to validate the display abstraction.