# Moria8 C128 Port — Architecture Specification

> Phase 10 architecture for the C128 80-column VDC port.
> This document is the authoritative technical reference for the C128-specific 
> subsystems (VDC, MMU, Memory Mapping, and Input).

---

## Overview

The C128 port adds an 80-column VDC rendering backend to the existing Moria8 game.
The game logic (combat, monsters, items, spells, dungeon generation, save/load) is
**100% shared** between C64 and C128. Only the hardware abstraction layer differs.

| Component | C64 (MORIA64) | C128 (MORIA128) |
| :--- | :--- | :--- |
| **Display Chip** | VIC-II (320x200) | VDC 8563/8568 (640x200) |
| **Resolution** | 40 x 25 Columns | 80 x 25 Columns |
| **Video RAM** | 1 KB at $0400 (System) | 16 KB Dedicated VDC RAM |
| **Banking** | PLA Register at $01 | MMU at $FF00 + PLA at $01 |
| **Input** | KERNAL SCNKEY/GETIN | Direct CIA1 Keyboard Scan |
| **CPU Speed** | 1.02 MHz | 2.04 MHz (during non-VDC logic) |

---

## 1. System Memory Architecture (Bank 0)

To ensure stability and prevent "Ghost Crashes," the C128 port uses a contiguous 
memory layout in Bank 0. Code and data are strictly separated.

### 1.1 Physical Layout Map

| Range | Content | Owner |
| :--- | :--- | :--- |
| $0000–$03FF | ZP, Stack, Vectors | System (Shared) |
| $0400–$07FF | Loader / ZP Save | Game (Temporary) |
| $0800–$09FF | KERNAL Workspace | System |
| $0A00–$0AFF | Screen Editor Workspace | **SYSTEM (RESERVED)** |
| **$0B00–$19FF** | **Dungeon Map (MAP_BASE)** | **Game (Data)** |
| $1A00–$1C00 | Buffer / Padding | - |
| **$1C01–$BFFF** | **Game Engine + Imports** | **Game (Code)** |
| $C000–$CFFF | Screen Editor ROM | System (Hidden in All-RAM) |
| $D000–$DFFF | I/O Registers | System |
| $E000–$FFFF | KERNAL ROM | System (Hidden in All-RAM) |

### 1.2 Implementation Mandates
*   **Link Address**: The main game binary is linked at **$1C0E**.
*   **Dungeon Map**: `MAP_BASE` is set to **$0B00** (different from C64's $C000).
*   **Bank 1 Usage**: Used for staging Creature Tier data ($C000) and UI help data ($E000). Accessed via the `read_banked_byte` hook.

---

## 2. MMU Configuration & Banking

The C128 uses the MMU Configuration Register at **$FF00** to control RAM/ROM 
visibility and bank selection.

### 2.1 MMU Bit Layout (Corrected)
*   **Bits 7–6**: RAM Bank Select (00=Bank 0, 01=Bank 1)
*   **Bits 5–4**: $C000–$FFFF ROMs (00=System ROMs, 11=RAM)
*   **Bits 3–2**: $8000–$BFFF ROMs (00=BASIC High, 11=RAM)
*   **Bit 1**: $4000–$7FFF ROM (0=BASIC Low, 1=RAM)
*   **Bit 0**: $D000 I/O Select (0=I/O visible, 1=RAM/CharROM)

### 2.2 Standard Constants

| Constant | Value | Description |
| :--- | :--- | :--- |
| `MMU_NORMAL` | **$0E** | Bank 0, KERNAL/ScreenEd ROMs visible, BASIC out, I/O in. |
| `MMU_ALL_RAM` | **$3E** | Bank 0, All RAM, I/O in. **Operational Mode.** |
| `MMU_RAM_BANK1` | **$7E** | Bank 1, All RAM, I/O in. Used for data staging. |

### 2.3 Banking Strategy (Safe KERNAL Wrappers)
The game runs primarily in `MMU_ALL_RAM` mode ($3E). To call KERNAL routines 
(LOAD/SAVE), the game uses **JMP Stubs** installed in Bank 0 RAM at the KERNAL 
vector locations ($FFB7–$FFD5).

1.  Stub saves current $FF00.
2.  Switch to `MMU_NORMAL` ($0E) to expose KERNAL ROM.
3.  Execute `JSR` to real KERNAL routine.
4.  Restore $FF00 and return.

---

## 3. VDC 80-Column Rendering

### 3.1 Hardware Interface
*   **Registers**: Indirect access via `$D600` (Address) and `$D601` (Data).
*   **VDC RAM**: 16 KB (independent of system RAM).
    *   $0000–$07CF: Screen RAM (80x25)
    *   $0800–$0FCF: Attribute RAM (Color/Effects)
*   **Attributes**: 4-bit RGBI color + Blink, Reverse, Underline.

### 3.2 Performance Optimization
To minimize the overhead of indirect register access:
1.  **Row Batching**: Uses the VDC auto-increment register (31) to stream an 
    entire row of screen codes, then an entire row of attributes.
2.  **Dirty Rendering**: Only redrawing the 7x7 area around the player for 
    movement, rather than the full 80x25 screen.

---

## 4. Input & Hardware Interaction

### 4.1 Keyboard Scanning
The C128 port **bypasses the KERNAL SCNKEY** entirely to avoid banking conflicts 
and Screen Editor re-initialization crashes.
*   **Mechanism**: Direct CIA1 matrix scan ($DC00/$DC01).
*   **Scan Table**: Custom mapping from hardware scan codes to PETSCII.
*   **Critical Address**: Keyboard buffer count is at **$D0** (not C64's $C6).

### 4.2 Interrupts
*   **IRQ**: Handled by `direct_irq_handler` in Bank 0 RAM.
*   **NMI**: Uses a safe stub to allow disk I/O and RESTORE key handling.
*   **Vector Mirroring**: IRQ/NMI vectors must be initialized in the RAM of 
    the operational bank ($3E/Bank 0).

---

## 5. Build & Boot Process

### 5.1 BOOT.PRG
A universal loader that detects the platform:
1.  Probe VDC at $D600.
2.  If VDC found and 40/80 key is 80-col ($D7 != 0): Load **MORIA128**.
3.  Otherwise: Load **MORIA64**.

### 5.2 boot128.s (The Native Loader)
1.  Moves itself to **$0400** to survive memory overwrites.
2.  Loads the main game into Bank 1.
3.  Copies from Bank 1 to Bank 0 (safe copy).
4.  Jumps to entry at **$080E**.

---

## 6. Known Issues & Technical Debt
*   **Key Gaps**: Scan table requires mapping for RETURN, SPACE, DEL, and STOP.
*   **VDC Blanking**: VIC-II blanking ($D011) is ineffective; needs VDC-specific 
    blanking during dungeon generation.
*   **Key Repeat**: Currently lacks hardware/software key repeat for movement.
*   **VDC Color Table**: Grey ($0C) and Light Grey ($0F) collapse to the same 
    VDC RGBI value. Mapping adjustment needed.
