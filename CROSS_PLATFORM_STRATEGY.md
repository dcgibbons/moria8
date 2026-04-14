# Moria8 Cross-Platform Strategy

This document outlines the architectural strategy and necessary steps to transition the Moria8 codebase from a Commodore-specific project to a multi-platform 6502 engine, while establishing a parallel track for 16-bit Motorola 68000 targets (Amiga and Atari ST).

## 1. The Repository Structure
A true multi-platform project requires strict separation between game rules and hardware execution. The 16-bit versions will exist as a parallel track with zero code sharing.

**Proposed Structure:**
```text
/
├── core/                  # 8-bit platform-agnostic game logic (math, AI, RNG, Map Gen)
│                          # No hardware registers allowed here.
├── platforms/
│   ├── shared/            # Logic shared by 8-bit architecture (e.g., 6502 vs 65C02 macros)
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
├── m68k/                  # 16-bit Motorola 68000 native rewrites
│   ├── amiga/             # Amiga OCS/ECS (Blitter, Copper, AmigaDOS)
│   └── atarist/           # Atari ST/STfm (Interleaved video, GEMDOS)
├── data/                  # Game assets, strings, levels (Shared across ALL platforms)
├── tools/                 # Build tools (Python scripts, Asset Converters)
└── docs/                  # Architectural documentation
```

## 2. The Assembler & ISA (Instruction Set Architecture)
*   **The 8-bit Track (6502):** Migration from KickAssembler to `ca65` supports platform-specific configurations (`.cfg`) and segmenting. The `core/` game logic targets the standard 6502/65C02.
*   **The 16-bit Track (68000):** The Amiga and Atari ST versions will be **complete rewrites** natively for the Motorola 68000. They will share game design, algorithms, and data assets with the 6502 version, but will not share source code. This ensures they can utilize 32-bit registers and flat memory without being constrained by 8-bit legacy logic.

## 3. The Hardware Abstraction Layer (HAL)
The HAL must provide zero-overhead interfaces for Video, Audio, and I/O.

### Video Paradigms
*   **8-bit Character Mapping:** Commodore, Atari 8-bit, and Apple II use various character-mapped or indirect character-mapped (VDC/VERA) paradigms.
*   **16-bit Bitmapped Rendering:**
    *   **Amiga:** Uses 4-5 planar bitplanes. The engine utilizes the **Blitter** for tile drawing and the **Copper** for hardware-accelerated Viewport/Status UI splits (changing palettes or pointers at the status boundary).
    *   **Atari ST:** Uses interleaved bitplanes (4 words per 16 pixels). Rendering is primarily software-driven, requiring an optimized `draw_tile` primitive for bit-shuffling.
*   **Apple IIgs (SHR):** Super Hi-Res offers a linear 320x200 4-bit framebuffer. 

### Storage & OS
*   **8-bit OS:** Abstraction across KERNAL, ProDOS, Acorn MOS, and TOS.
*   **16-bit OS:** Native file I/O via **AmigaDOS** (Amiga) and **GEMDOS** (Atari ST) for block-level access.
*   **Abstraction:** The `io_service` layer abstracts the difference between serial sector reads and high-speed block-level file I/O.

## 4. Memory Management & Overlays
Moria8 uses a **Resource Window** paradigm for machines with limited address space.

### The "Disk-Bound" 64KB Targets (C64, Plus/4, & Atari XL/XE)
*   Overlays are loaded on-demand from disk (SIO/IEC) into the execution window.

### The "Resident Overlay" Advantage
*   **128K+ 8-bit (Apple IIe, IIgs, CX16, BBC Master 128):** All game overlays and tier data are pre-loaded into extended/paged memory, turning resource invocation into zero-latency bank switches.
*   **16-bit 68000 (Amiga & Atari ST):** With 512KB+ of RAM, the "Overlay Window" paradigm is eliminated. All game logic, data, and levels reside in memory simultaneously.
    *   **Amiga Memory Tiers:** The engine must manage **Chip RAM** (for bitplanes, audio, and Copper lists) versus **Fast RAM** (for game logic and dungeon data) to ensure maximum CPU performance.

## 5. Current Codebase Assessment & Next Steps
Moria8 is currently well-positioned because the 8-bit logic is increasingly platform-agnostic.

**Strategic Phasing:**
1.  **Decoupling:** Move 8-bit logic to the top-level `core/` directory.
2.  **68k Initialization:** Establish the parallel `m68k/` branch for the native rewrites.
3.  **Cross-Platform Prototypes:** Implement basic renderers in the `platforms/` (8-bit) and `m68k/` (16-bit) branches to validate the diverse hardware paradigms.
