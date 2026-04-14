# Moria8 Cross-Platform Strategy

This document outlines the architectural strategy and necessary steps to transition the Moria8 codebase from a Commodore-specific project to a multi-platform engine, establishing parallel tracks for 8-bit (6502), 16-bit (Motorola 68000), and x86 (Intel Real Mode) architectures.

## 1. The Repository Structure
A true multi-platform project requires strict separation between game rules and hardware execution. The non-6502 versions exist as parallel tracks with zero code sharing to ensure native performance and idiomatic hardware utilization.

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
│   ├── atarist/           # Atari ST/STfm (Interleaved video, GEMDOS)
│   ├── megadrive/         # Sega Genesis / Mega Drive (Tile-based VDP, ROM-exec)
│   └── mac68k/            # Classic Macintosh (System 6+, Toolbox, QuickDraw)
├── x86/                   # Intel 8088/8086 Real Mode native rewrites (LOWEST PRIORITY)
│   └── msdos/             # IBM PC XT (256KB RAM, CGA/MDA Text Mode, INT 21h)
├── data/                  # Game assets, strings, levels (Shared across ALL platforms)
├── tools/                 # Build tools (Python scripts, Asset Converters)
└── docs/                  # Architectural documentation
```

## 2. The Assembler & ISA (Instruction Set Architecture)
*   **The 8-bit Track (6502):** Migration from KickAssembler to `ca65` supports platform-specific configurations (`.cfg`) and segmenting. The `core/` game logic targets the standard 6502/65C02.
*   **The 16-bit Track (68000):** The Amiga, Atari ST, Sega Genesis, and Macintosh versions are **complete rewrites** natively for the Motorola 68000. They share game design and data assets with the 6502 version but utilize native 32-bit registers and flat memory.
*   **The x86 Track (8088/8086):** A native rewrite for the IBM PC XT ecosystem. By avoiding a standard uMoria C compile (which is notoriously sluggish on 4.77MHz hardware), this custom engine utilizes the Small/Medium memory model and 16-bit registers to provide a premium, fast experience on original 1980s PC hardware.

## 3. The Hardware Abstraction Layer (HAL)
The HAL must provide zero-overhead interfaces for Video, Audio, and I/O.

### Video Paradigms
*   **8-bit Character Mapping:** Character-mapped or indirect character-mapped (VDC/VERA) paradigms.
*   **16-bit Bitmapped Rendering:** Planar (Amiga), Interleaved (ST), or Linear (Mac) bitmaps.
*   **16-bit Tile-Based Rendering:** Hardware VDP with 8x8 tiles (Genesis).
*   **x86 Text Mode:** Direct memory writes to `0xB800` (CGA Color) or `0xB000` (MDA Mono). Utilizes Code Page 437 box-drawing symbols for high-performance dungeon rendering without custom charsets.

### Storage & OS
*   **8-bit OS:** KERNAL, ProDOS, Acorn MOS, and TOS.
*   **16-bit OS:** AmigaDOS, GEMDOS, ROM-reads, and Mac OS Toolbox (System 6.0.8).
*   **x86 OS:** Standard MS-DOS Interrupts (`INT 21h`).

## 4. Memory Management & Overlays
Moria8 uses architectural tiers based on available address space and memory speed.

### The "Disk-Bound" 64KB Targets (C64, Plus/4, & Atari XL/XE)
*   Overlays are loaded on-demand from disk (SIO/IEC) into a small execution window.

### The "Resident Overlay" Advantage
*   **128K+ 8-bit (Apple IIe, IIgs, CX16, BBC Master 128):** All game overlays and tier data are pre-loaded into extended/paged memory.
*   **256KB+ x86 (IBM PC XT):** 256KB is the historical baseline for the XT era. This provides sufficient space to keep the entire engine, monster tables, and the dungeon map **resident in memory**, eliminating intra-level disk access.
*   **512KB+ 16-bit (Amiga, Atari ST, Macintosh):** The "Overlay Window" paradigm is eliminated. All game logic, data, and levels reside in memory simultaneously.

### ROM-Based Execution (Sega Genesis)
*   Executes logic and reads static data directly from the ROM cartridge, dedicating its 64KB Work RAM strictly to dynamic game state.

## 5. Current Codebase Assessment & Next Steps
Moria8 is currently well-positioned because the 8-bit logic is increasingly platform-agnostic.

**Strategic Phasing:**
1.  **Decoupling:** Move 8-bit logic to the top-level `core/` directory.
2.  **68k & x86 Initialization:** Establish parallel branches for native rewrites.
3.  **Cross-Platform Prototypes:** Implement basic renderers across all tracks to validate hardware paradigms.
