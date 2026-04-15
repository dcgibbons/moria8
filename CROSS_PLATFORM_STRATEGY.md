# Moria8 Cross-Platform Strategy

This document outlines the architectural strategy and necessary steps to transition the Moria8 codebase from a Commodore-specific project to a multi-platform engine, establishing parallel tracks for 8-bit (6502) architectures.

## 1. The Repository Structure
A true multi-platform project requires strict separation between game rules and hardware execution. The various 8-bit versions exist as parallel tracks to ensure native performance and idiomatic hardware utilization.

**Proposed Structure:**
```text
/
├── core/                  # 8-bit platform-agnostic 6502 game logic (math, AI, RNG, Map Gen)
│                          # No hardware registers allowed here.
├── core_z80/              # Z80 native rewrite of game logic (Parallel Core)
├── platforms/
│   ├── shared/            # Logic shared by 8-bit architecture (e.g., 6502 vs 65C02 macros)
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
├── data/                  # Game assets, strings, levels (Shared across ALL platforms)
├── tools/                 # Build tools (Python scripts, Asset Converters)
└── docs/                  # Architectural documentation
```

## 2. The Assembler & ISA (Instruction Set Architecture)
*   **The 6502 Track:** Migration from KickAssembler to `ca65` supports platform-specific configurations (`.cfg`) and segmenting. The `core/` game logic targets the standard 6502/65C02.
*   **The Z80 Track:** A native rewrite of the game logic specifically for the Zilog Z80. Utilizing `z88dk` (using `z80asm`) or `sjasmplus`. This track establishes a parallel `core_z80/` to ensure native efficiency on the CP/M, ZX Spectrum, and MSX platforms.

## 3. The Hardware Abstraction Layer (HAL)
The HAL must provide zero-overhead interfaces for Video, Audio, and I/O.

### Video Paradigms
*   **8-bit Character Mapping:** Character-mapped or indirect character-mapped (VDC/VERA) paradigms for Commodore and Atari.
*   **CP/M Terminal:** ANSI/VT100 serial terminal escape codes for text-based rendering on business machines.
*   **Z80 VDP/Bitmap:** Bitmapped rendering for ZX Spectrum and hardware-accelerated tile-based rendering for MSX.

### Storage & OS
*   **8-bit OS:** KERNAL, ProDOS, Acorn MOS, and TOS.
*   **CP/M OS:** Standard CP/M 2.2 BDOS calls for disk I/O.

## 4. Memory Management & Overlays
Moria8 uses architectural tiers based on available address space and memory speed.

### The "Disk-Bound" 64KB Targets (C64, Plus/4, Atari XL/XE, & CP/M)
*   **6502 Overlays:** Loaded on-demand from disk (SIO/IEC) into a small execution window.
*   **CP/M Overlays:** Leverages the 50-54KB Transient Program Area (TPA) for a similar disk-swapping strategy to accommodate the dungeon and monster data on 64KB business machines.

### The "Resident Overlay" Advantage
*   **128K+ 8-bit (Apple IIe, IIgs, CX16, BBC Master 128):** All game overlays and tier data are pre-loaded into extended/paged memory.

## 5. Current Codebase Assessment & Next Steps
Moria8 is currently well-positioned because the 8-bit logic is increasingly platform-agnostic.

**Strategic Phasing:**
1.  **Decoupling:** Move 8-bit logic to the top-level `core/` directory.
2.  **Parallel Cores:** Establish `core_z80/` to begin the native Z80 rewrite.
3.  **Active Parallel Development:** Implement basic renderers (HAL) for both 6502 and Z80 (CP/M, ZX Spectrum, MSX) to validate hardware paradigms side-by-side.
