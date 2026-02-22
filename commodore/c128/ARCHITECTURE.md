# Moria8 C128 Port — Architecture Plan

> Phase 10 architecture for the C128 80-column VDC port.
> Covers: BOOT.PRG platform detection (10.0), VDC rendering backend (10.1),
> and the build system changes needed to produce both MORIA64 and MORIA128.

---

## Overview

The C128 port adds an 80-column VDC rendering backend to the existing Moria8 game.
The game logic (combat, monsters, items, spells, dungeon generation, save/load) is
**100% shared** between C64 and C128. Only the display layer differs:

| | C64 (MORIA64) | C128 (MORIA128) |
|---|---|---|
| **Display chip** | VIC-II | VDC (8563/8568) |
| **Screen width** | 40 columns | 80 columns |
| **Screen access** | Direct memory writes ($0400+, $D800+) | Indirect register access ($D600/$D601) |
| **Screen RAM** | 1 KB at $0400 in system RAM | 2 KB at VDC $0000 in VDC's own 16 KB RAM |
| **Color/attribute** | Color RAM at $D800 (4-bit foreground only) | Attribute RAM at VDC $0800 (4-bit color + blink/reverse/underline) |
| **Character encoding** | VIC-II screen codes | ASCII-like VDC codes (different mapping!) |
| **Banking** | PLA register at $01 | MMU at $FF00 / $D500 |

**Key constraint:** VDC RAM is entirely separate from system RAM. You cannot use
6502 indirect addressing (`sta (ptr),y`) to write to the VDC screen — every byte
must go through the VDC's register interface. This is the fundamental difference
that drives the entire rendering architecture.

---

## 10.0 — BOOT.PRG: Platform Detection and Chain-Loading

### Current State

`boot.s` is a standalone bootloader that:
1. Displays "LOADING MORIA8..."
2. Chain-loads "MORIA64" from disk via KERNAL LOAD
3. Uses a stub copied to $0340 (cassette buffer) to survive LOAD overwriting $0801+

### Design

The new BOOT.PRG extends this with C64/C128 detection:

```
BOOT.PRG starts
    │
    ├─ Probe VDC at $D600 (same technique as config.s)
    │   ├─ No VDC → C64 (or C128 in GO64 mode)
    │   │   └─ Load "MORIA64"
    │   │
    │   └─ VDC detected → C128 native mode
    │       ├─ Check $D7 (40/80 column flag)
    │       │   ├─ $D7 = 0 → 40-column mode → Load "MORIA64"
    │       │   └─ $D7 ≠ 0 → 80-column mode → Load "MORIA128"
    │       │
    │       └─ Chain-load selected binary
    │
    └─ JMP $080E (game entry point)
```

**Why check $D7 (40/80 flag)?** On C128, the user selects 40-col or 80-col mode
before running the game (via the 40/80 DISPLAY key). If they chose 40-col, they're
looking at the VIC-II output and should get the C64 rendering path. If 80-col,
they're looking at VDC output and should get the VDC rendering path.

**Detection method (VDC probe):** Same as `config.s:detect_machine`:
```asm
    lda #18             // VDC register 18 (safe to select)
    sta $d600           // Write register index
    nop ; nop           // Settle time
    lda $d600           // Read status
    ora $d600
    ora $d600           // OR multiple reads
    bpl not_c128        // Bit 7 clear → no VDC
```
On C64: $D600 is a SID mirror, reads ~$00 (bit 7 clear).
On C128 native: VDC status register, bit 7 (ready) is usually high.
On C128 in GO64: $D600 is SID mirror (VDC not accessible), reads ~$00.

### File Changes

| File | Change |
|------|--------|
| `commodore/c64/boot.s` | Add VDC probe + $D7 check. Select filename "MORIA64" or "MORIA128". Display "LOADING MORIA8 (C64)..." or "LOADING MORIA8 (C128)...". |
| `commodore/c64/Makefile` | Add `MORIA128_PRG` target. Add to `disk` target. |
| Disk image | Add "MORIA128" file alongside "MORIA64". |

### Boot Display

On C128 in 80-col mode, the bootloader runs in BASIC which uses the VDC for text
output (KERNAL CHROUT goes to VDC in 80-col mode). So "LOADING MORIA8 (C128)..."
will appear on the 80-column screen naturally. The chain-loaded MORIA128 takes over
VDC rendering from there.

---

## 10.1 — VDC 80-Column Rendering Backend

### VDC Hardware Summary

The VDC (MOS 8563 on C128, 8568 on C128DCR) has:
- **Its own 16 KB RAM** (64 KB on some models), completely separate from system RAM
- **37 internal registers** accessed indirectly via two I/O ports:
  - `$D600` — Address/Status register (write: register number; read: bit 7 = ready)
  - `$D601` — Data register (read/write selected register's value)
- **Auto-incrementing address pointer** (registers 18-19) for streaming data

**Default VDC RAM layout:**
| VDC Address | Size | Contents |
|-------------|------|----------|
| $0000–$07CF | 2,000 | Screen character codes (80 × 25) |
| $0800–$0FCF | 2,000 | Attribute bytes (80 × 25) |
| $1000–$1FFF | 4,096 | Character generator ROM copy |
| $2000–$3FFF | 8,192 | Free (unused in 16 KB configuration) |

**VDC register access pattern:**
```asm
// Write value A to VDC register X
vdc_write:
    stx $d600           // Select register
!wait:
    bit $d600           // Poll status
    bpl !wait-          // Wait for bit 7 (ready)
    sta $d601           // Write data
    rts

// Read VDC register X → A
vdc_read:
    stx $d600
!wait:
    bit $d600
    bpl !wait-
    lda $d601
    rts
```

**Streaming writes (auto-increment):** After setting the update address (registers
18-19), each write to register 31 writes one byte to VDC RAM and auto-increments
the address. This allows efficient bulk writes without re-setting the address for
each byte.

**VDC attribute byte format:**
| Bit | Function |
|-----|----------|
| 7 | Alternate character set |
| 6 | Reverse video |
| 5 | Underline |
| 4 | Blink |
| 3–0 | Foreground color (RGBI) |

Background color is global: VDC register 26, bits 7–4. Set to black ($00) for
the game.

### Character Code Translation

The VDC uses ASCII-like character codes, NOT VIC-II screen codes. A translation
is required for all text output:

| Character | VIC-II Screen Code | VDC Code | Conversion |
|-----------|-------------------|----------|------------|
| A–Z (upper) | $01–$1A | $41–$5A | add $40 |
| a–z (lower) | $41–$5A | $61–$7A | add $20 |
| @ | $00 | $40 | add $40 |
| Space | $20 | $20 | unchanged |
| 0–9 | $30–$39 | $30–$39 | unchanged |
| Punctuation ($20–$3F) | $20–$3F | $20–$3F | unchanged |

**Conversion logic** (handles the common range used by the game):
```asm
// screen_code_to_vdc — Convert VIC-II screen code → VDC character code
// Input: A = screen code
// Output: A = VDC code
screen_code_to_vdc:
    cmp #$20
    bcs !above_1f+
    // $00–$1F → $40–$5F (add $40)
    clc
    adc #$40
    rts
!above_1f:
    cmp #$40
    bcc !done+          // $20–$3F → unchanged
    // $40–$5F → $60–$7F (add $20)
    clc
    adc #$20
!done:
    rts
```

Alternatively, a 128-byte lookup table could handle all cases including special
characters. The arithmetic approach is ~15 bytes of code vs 128 bytes for a table;
prefer arithmetic for the common case with a small table for the few special
graphics characters (if any).

### VDC Color Translation

VDC colors use 4-bit RGBI encoding, different from VIC-II's palette:

| VIC-II Color | VIC-II # | VDC RGBI | VDC # | Notes |
|-------------|----------|----------|-------|-------|
| Black | 0 | 0000 | 0 | Exact |
| White | 1 | 1111 | 15 | Exact |
| Red | 2 | 0100 | 4 | Dark red |
| Cyan | 3 | 1011 | 11 | Light cyan |
| Purple | 4 | 0101 | 5 | Dark magenta |
| Green | 5 | 0010 | 2 | Dark green |
| Blue | 6 | 0001 | 1 | Dark blue |
| Yellow | 7 | 1110 | 14 | Yellow |
| Orange | 8 | 1100 | 12 | Light red (closest) |
| Brown | 9 | 0110 | 6 | Brown |
| Light Red | 10 | 1100 | 12 | Light red |
| Dark Grey | 11 | 1000 | 8 | Dark grey |
| Grey | 12 | 0111 | 7 | Light grey |
| Light Green | 13 | 1010 | 10 | Light green |
| Light Blue | 14 | 1001 | 9 | Light blue |
| Light Grey | 15 | 0111 | 7 | Light grey (same as grey) |

**16-byte lookup table:**
```asm
vic_to_vdc_color:
    .byte 0, 15, 4, 11, 5, 2, 1, 14
    .byte 12, 6, 12, 8, 7, 10, 9, 7
```

All color values passed through `zp_text_color` and `tile_colors[]` are VIC-II
palette indices. The VDC rendering routines translate via this table before writing
VDC attributes. The game logic and color.s are unchanged.

### 80-Column Screen Layout

```
+------------------------------------------------------------------------------+
|Message line 1 (80 chars)                                                     | Row 0
|Message line 2 (80 chars)                                                     | Row 1
+------------------------------------------------------------------------------+
|                                                                              | Row 2
|                                                                              |
|                    Game viewport (78 x 21 tiles)                             | Rows 2–22
|                    Full map width visible (80 tiles fit in 78+scroll)        |
|                                                                              |
|                                                                              | Row 22
+------------------------------------------------------------------------------+
|Name  Human  LV:12  DL:25  HP:145/145  MP:32/40  AC:15  AU:12345  Full       | Row 23
|ST:18 IN:14 WI:16 DX:17 CO:15 CH:12  EXP:125000                             | Row 24
+------------------------------------------------------------------------------+
```

**Key differences from 40-column layout:**

| Parameter | 40-col (C64) | 80-col (C128) | Notes |
|-----------|-------------|--------------|-------|
| SCREEN_COLS | 40 | 80 | |
| VIEWPORT_X | 1 | 1 | Left border column |
| VIEWPORT_W | 38 | 78 | Almost full map width |
| VIEWPORT_Y | 2 | 2 | Below 2-line message area |
| VIEWPORT_H | 19 | 21 | 2 extra rows (save 1 status row) |
| MSG_ROW | 0 | 0 | Same |
| STATUS_ROW | 21 | 23 | Moved down (more viewport room) |
| Status lines | 3 | 2 | 80 chars wide — all info fits in 2 rows |
| INPUT_ROW | 24 | N/A | Merged into status area or removed |

**Status bar consolidation:** With 80 columns, the 3-line status bar compresses
to 2 lines. Row 23 holds the primary stats (name, race, level, HP, MP, AC, gold,
hunger) and row 24 holds the six ability scores plus experience. No need for a
separate input prompt row — prompts can appear on the message lines.

### Rendering Architecture

**Strategy: Direct VDC register writes (no shadow buffer).**

A shadow buffer approach (write to system RAM, then sync to VDC) was considered
but rejected for the first implementation:
- Requires 4 KB extra RAM (2000 screen + 2000 attributes)
- Adds sync overhead after every render
- The direct register approach is fast enough for the game's rendering pattern

The VDC auto-increment feature makes row-by-row rendering efficient:
- Set VDC address to start of row → stream 78 screen codes via register 31
- Set VDC address to attribute row → stream 78 attribute bytes
- Each register access: ~8–12 µs (including ready-bit polling)
- Full viewport (78 × 21): ~4400 register accesses × ~10 µs = ~44 ms (~2.5 frames)

This is slightly slower than VIC-II direct writes but acceptable for a turn-based
game. Dirty rendering (render_local_area) limits most updates to a small region,
making the typical per-turn update much faster.

### New Files

#### `commodore/c128/screen_vdc.s` — VDC Screen Output

Provides the same API as `commodore/c64/screen.s` but targets the VDC:

```
Routine                  Description
─────────────────────────────────────────────────────────────────
vdc_write_reg            Write A to VDC register X (polls ready)
vdc_read_reg             Read VDC register X → A (polls ready)
vdc_set_update_addr      Set VDC update address (regs 18/19)
vdc_write_data           Write A to VDC data register 31 (auto-increments)

screen_clear             Fill VDC screen RAM with spaces, attributes with color
screen_put_char          Convert screen code → VDC code, write to VDC at cursor
screen_put_string        Stream converted string to VDC at cursor position
screen_set_color         Set zp_text_color (same as C64 — translation at write time)
screen_clear_row         Clear one row in VDC screen + attribute RAM
screen_set_cursor        Compute VDC address from (row, col) — no zp_screen_lo/hi
screen_put_char_at       Write one char at (row, col) without moving cursor
screen_put_decimal       Write 8-bit decimal (calls screen_put_char)
screen_put_decimal_16    Write 16-bit decimal
screen_put_hex           Write 2-digit hex
screen_put_decimal_rj2   Right-justified 2-char decimal
screen_put_decimal_lz2   Leading-zero 2-char decimal

screen_code_to_vdc       Convert VIC-II screen code → VDC character code
vic_to_vdc_color         16-byte lookup table for color translation
```

**Row address tables:** Instead of `screen_row_lo/hi` pointing to system RAM,
the VDC version uses `vdc_row_addr_lo/hi` containing VDC RAM offsets:
```asm
vdc_screen_row_lo:   .fill 25, <(i * 80)         // Screen chars at VDC $0000
vdc_screen_row_hi:   .fill 25, >(i * 80)
vdc_attrib_row_lo:   .fill 25, <($0800 + i * 80) // Attributes at VDC $0800
vdc_attrib_row_hi:   .fill 25, >($0800 + i * 80)
```

**screen_put_char implementation sketch:**
```asm
screen_put_char:        // A = screen code
    pha
    jsr screen_set_cursor_vdc   // Sets VDC address for (row, col)
    pla
    jsr screen_code_to_vdc      // Convert to VDC character code
    ldx #31
    jsr vdc_write_reg           // Write character

    // Write attribute at same position + $0800
    // VDC address auto-incremented, but attribute is at +$0800 offset
    // Must set new address for attribute
    jsr screen_set_attrib_addr  // VDC address = screen addr + $0800
    lda zp_text_color
    tax
    lda vic_to_vdc_color,x      // Translate VIC-II color → VDC RGBI
    ldx #31
    jsr vdc_write_reg           // Write attribute

    inc zp_cursor_col
    rts
```

#### `commodore/c128/dungeon_render_vdc.s` — VDC Viewport Rendering

Same logic as `commodore/c64/dungeon_render.s` but writes to VDC instead of
system RAM. The tile decoding (map byte → screen code + color) is identical.

**Key difference from dungeon_render.s:** Instead of:
```asm
    // C64: direct memory writes
    lda zp_temp0            // screen code
    sta (zp_screen_lo),y
    lda zp_temp1            // color
    sta (zp_color_lo),y
```

The VDC version uses:
```asm
    // C128 VDC: register-indirect writes
    lda zp_temp0
    jsr screen_code_to_vdc
    ldx #31
    jsr vdc_write_reg       // Write screen code to VDC

    // Attribute write deferred — batch per row for efficiency
    lda zp_temp1            // VIC-II color
    sta row_attr_buf,x      // Buffer attribute for batch write
```

**Row-batch optimization:** Instead of writing screen code + attribute for each
tile (2 VDC address sets per tile = slow), the VDC renderer:
1. Sets VDC address to screen row start
2. Streams all 78 screen codes via register 31 (auto-increment)
3. Sets VDC address to attribute row start ($0800 offset)
4. Streams all 78 attribute bytes via register 31

This halves the address-setup overhead. A small 80-byte `row_attr_buf` buffers
the attribute bytes for step 4. Total cost per row: 2 address sets + 156 data
writes = ~160 register accesses.

**render_viewport flow:**
```
for each viewport row (0 to VIEWPORT_H-1):
    map_row = view_y + row
    vdc_screen_addr = vdc_screen_row[row + VIEWPORT_Y] + VIEWPORT_X
    Set VDC update address to vdc_screen_addr

    for each column (0 to VIEWPORT_W-1):
        decode tile → (screen_code, vic_color)
        convert screen_code → vdc_char
        write vdc_char to register 31 (auto-increments)
        save translated color to row_attr_buf[col]

    vdc_attrib_addr = vdc_attrib_row[row + VIEWPORT_Y] + VIEWPORT_X
    Set VDC update address to vdc_attrib_addr

    for each column (0 to VIEWPORT_W-1):
        write row_attr_buf[col] to register 31

next row
```

**render_single_tile** and **render_local_area** work similarly but set VDC
addresses per-tile (no row batching — these handle sparse updates).

#### `commodore/c128/config128.s` — C128 Configuration

Replaces the `detect_machine` routine (unnecessary — we know we're on C128 in
80-col mode because the bootloader selected MORIA128):

```asm
detect_machine:
    lda #MACHINE_C128
    sta zp_machine_type
    lda #COLUMNS_80
    sta zp_column_mode
    rts
```

Also defines C128-specific constants (VDC registers, MMU addresses).

#### `commodore/c128/memory128.s` — C128 Memory Banking

C128 uses the MMU Configuration Register at $FF00 (hardware mirror of $D500)
instead of the C64 PLA register at $01. The banking patterns are:

| Purpose | C64 ($01) | C128 ($FF00) | What it does |
|---------|-----------|-------------|--------------|
| Normal game mode | $36 | MMU: I/O + KERNAL + RAM at $4000–$BFFF | Standard gameplay |
| Overlay access | $35 | MMU: I/O + RAM at $E000 (KERNAL out) | Read $E000 overlays |
| Compute-only banked | $34 | MMU: RAM everywhere + I/O | Access $E000 + $F000 |

The `BANK_NO_BASIC`, `BANK_NO_KERNAL`, `BANK_NO_ROMS` constants and the
`BankOutBasic()` / `BankOutKernal()` macros in `memory.s` are redefined for C128
MMU register values. All trampoline code in `main.s` works unchanged because it
uses these named constants.

**C128 MMU key registers:**

| Register | Address | Purpose |
|----------|---------|---------|
| Configuration | $FF00 | Memory map control (ROM/RAM/I/O visibility) |
| Pre-configuration A | $FF01 | Stored config, loaded by `STA $FF00` |
| Pre-configuration B | $FF02 | Alternative stored config |
| Mode | $FF04 | 8502/Z80 selection (always 8502 for us) |
| RAM bank | $FF04 | Select bank 0 or bank 1 |

The exact bit patterns for $FF00 will be determined during implementation with
reference to the C128 Programmer's Reference Guide. The architecture is the same
as C64 — we bank out KERNAL ROM to access $E000 overlay RAM, wrapping in SEI/CLI.

#### `commodore/c128/main128.s` — C128 Entry Point

Structured identically to `commodore/c64/main.s` but imports C128-specific modules:

```asm
// main128.s — Entry point for Moria8 C128 (80-column VDC)

// Same BASIC stub, overlay segments, entry point structure as main.s
.pc = $0801 "BASIC Stub"
:BasicUpstart2(entry)

.pc = $080e "Program"
entry:
    lda #$36            // Bank out BASIC ROM (C128 MMU equivalent)
    sta $01             // NOTE: Use MMU register for C128
    jmp entry_main

// Import shared modules from c64/
#import "../c64/zeropage.s"
#import "memory128.s"              // C128 MMU banking (replaces memory.s)
#import "../c64/reu.s"
#import "screen_vdc.s"             // VDC rendering (replaces screen.s)
#import "../c64/color.s"
#import "config128.s"              // C128 config (replaces config.s)
#import "../c64/input.s"
#import "../c64/rng.s"
#import "../c64/math.s"
#import "../c64/tables.s"
// ... all shared game logic modules from ../c64/ ...
#import "dungeon_render_vdc.s"     // VDC viewport (replaces dungeon_render.s)
// ... remaining shared modules ...
```

**Four modules replaced, everything else shared:**

| C64 Module | C128 Replacement | Reason |
|------------|-----------------|--------|
| `screen.s` | `screen_vdc.s` | VDC register access instead of direct memory |
| `dungeon_render.s` | `dungeon_render_vdc.s` | VDC-specific viewport rendering |
| `config.s` | `config128.s` | Hardcoded C128/80-col detection |
| `memory.s` | `memory128.s` | MMU banking instead of PLA $01 |

All other ~47 source files are imported directly from `../c64/` unchanged.

### Modules That Work Unchanged

These modules call `screen_put_char`, `screen_put_string`, `screen_clear_row`,
etc. — the screen.s API. Since `screen_vdc.s` provides the same API, they work
without modification:

- `ui_status.s` — Status bar rendering (column positions will use new constants)
- `ui_messages.s` — Message line management
- `ui_help.s` — Help screen (banked at $F000)
- `ui_character.s` — Character info display
- `ui_inventory.s` — Inventory/equipment display
- `ui_store.s` — Store buy/sell UI
- `ui_recall.s` — Monster recall display
- `title_screen.s` — Title screen (loads art, renders via screen_put_string)
- `player_create.s` — Character creation UI
- `score.s` — Death screen / high scores
- `stat_display.s` — Stat value formatting
- `combat.s`, `monster_attack.s`, `monster_magic.s` — Game logic (no screen calls in hot paths)
- All other game logic modules

### Column Position Adjustment

The 80-col layout has different column positions for the status bar. Two approaches:

**Option A: Re-use constants with conditional values.**
Define `STATUS_COL_*` constants differently for 40-col vs 80-col. Modules like
`ui_status.s` use these constants for column positions.

**Option B: Create `ui_status_vdc.s` with 80-col layout.**
A separate status bar module optimized for 80 columns. More work but gives full
control over the wider layout.

**Recommendation: Option A** for the first implementation. Most column positions
in `ui_status.s` are hardcoded literals (`lda #28` / `sta zp_cursor_col`). These
can be replaced with named constants defined differently per platform:

```asm
// 40-col (screen.s)
.const STATUS_COL_LV = 28
.const STATUS_COL_DL = 34

// 80-col (screen_vdc.s)
.const STATUS_COL_LV = 48
.const STATUS_COL_DL = 56
```

The `ui_status.s` source uses these constants → no code changes needed, just
different constant definitions depending on which screen module is imported.

**However**, this requires modifying `ui_status.s` to use constants instead of
literals. This is a pre-requisite refactor (small, mechanical) that also benefits
the C64 code by removing magic numbers.

---

## Build System Changes

### Directory Structure

```
commodore/
├── c64/                    (existing — unchanged)
│   ├── main.s
│   ├── screen.s
│   ├── dungeon_render.s
│   ├── config.s
│   ├── memory.s
│   ├── Makefile            (updated: add MORIA128 target)
│   └── ... (all other .s files)
│
├── c128/
│   ├── ARCHITECTURE.md     (this file)
│   ├── screen_vdc.s        (NEW: VDC rendering backend)
│   ├── dungeon_render_vdc.s (NEW: VDC viewport rendering)
│   ├── config128.s         (NEW: C128 configuration)
│   ├── memory128.s         (NEW: C128 MMU banking)
│   ├── main128.s           (NEW: C128 entry point, imports ../c64/ modules)
│   └── layout.s            (NEW: 80-col layout constants)
│
└── DESIGN.md               (updated: add C128 section)
```

### Makefile Changes

The `commodore/c64/Makefile` gains a `MORIA128` target:

```makefile
# C128 sources (in c128/ directory)
C128_DIR    = ../c128
MAIN128_SRC = $(C128_DIR)/main128.s
MAIN128_PRG = $(OUT)/moria128.prg
VICE128     ?= x128

# C128 binary — uses shared sources from c64/ via #import "../c64/..."
$(MAIN128_PRG): $(SOURCES) $(wildcard $(C128_DIR)/*.s) $(KICKASS) | $(OUT)
	$(JAVA) -jar $(KICKASS) $(MAIN128_SRC) $(KA_FLAGS) -o $(MAIN128_PRG)

# Build both binaries
build128: $(MAIN128_PRG)

# Launch C128 binary in x128 emulator
run128: $(MAIN128_PRG) $(TITLE_PRG) $(TIER_PRGS)
	$(VICE128) -80col -autostartprgmode 1 -autostart $(MAIN128_PRG)

# Disk image includes both binaries
disk: ... $(MAIN128_PRG) ...
	$(C1541) ... -write $(MAIN128_PRG) "moria128" ...
```

### Test Infrastructure

C128 tests run in VICE x128 instead of x64sc:

```makefile
test128: $(MAIN128_PRG)
	VICE=x128 ./run_tests.sh --c128
```

The `run_tests.sh` script is parameterized to use x128 when `--c128` is passed.
C128-specific tests go in `commodore/c128/tests/` and test VDC output by reading
VDC RAM through the register interface (rather than checking screen RAM at $0400).

---

## Implementation Plan

### Milestone 1: VDC Hello World (Standalone Demo)

A standalone `vdc_demo.s` that proves the VDC rendering pipeline works:

1. **Initialize VDC** — set background color, clear screen
2. **Display text** — "MORIA8 C128 80-COL" at row 12
3. **Color test** — show all 16 VDC colors
4. **Dungeon mock** — render a small hardcoded dungeon viewport with walls,
   floor, doors, player '@', and a few monster letters
5. **Status bar** — render a mock status bar in 80-col layout

This demo does NOT import any game logic — it's a self-contained VDC exercise.
Build and test with: `make run128_demo` → launches in VICE x128 80-col mode.

**Files:** `commodore/c128/vdc_demo.s` (standalone), `commodore/c128/screen_vdc.s`

### Milestone 2: Full screen_vdc.s API

Implement all screen.s API functions in screen_vdc.s:
- `screen_clear`, `screen_put_char`, `screen_put_string`
- `screen_set_color`, `screen_clear_row`, `screen_set_cursor`
- `screen_put_char_at`, `screen_put_hex`
- `screen_put_decimal`, `screen_put_decimal_16`
- `screen_put_decimal_rj2`, `screen_put_decimal_lz2`

Test by running simple UI tests that call these functions and verify VDC RAM
contents.

### Milestone 3: dungeon_render_vdc.s

Port the viewport rendering:
- `viewport_update` — same logic, different VIEWPORT_W/H constants
- `render_viewport` — row-batch VDC writes
- `render_single_tile` — per-tile VDC writes
- `render_local_area` — bounding-box dirty rendering

Test with a hardcoded map and verify rendered output.

### Milestone 4: main128.s Integration

Assemble the full MORIA128 binary:
- `main128.s` imports all shared modules from `../c64/`
- `memory128.s` provides C128 MMU banking
- `config128.s` hardcodes C128/80-col
- Run the full game in VICE x128

### Milestone 5: BOOT.PRG Update

Update `boot.s` with platform detection. Test:
- On x64sc: boots MORIA64 (C64 path)
- On x128 40-col: boots MORIA64
- On x128 80-col: boots MORIA128

### Milestone 6: Status Bar and Layout Polish

- Refactor `ui_status.s` to use named column constants
- Define 80-col layout constants in `layout.s`
- Adjust -MORE- prompt positioning for 80-col
- Test all UI screens (help, character, inventory, stores) at 80 columns

---

## VDC Performance Considerations

### Worst Case: Full Viewport Redraw

| Operation | Count | Time per op | Total |
|-----------|-------|------------|-------|
| Set row address (screen) | 21 | ~20 µs | 0.4 ms |
| Stream screen codes | 21 × 78 = 1638 | ~10 µs | 16.4 ms |
| Set row address (attrib) | 21 | ~20 µs | 0.4 ms |
| Stream attribute bytes | 21 × 78 = 1638 | ~10 µs | 16.4 ms |
| **Total** | | | **~33.6 ms** |

~33 ms per full redraw = ~2 video frames at 60 Hz. Acceptable for a turn-based
game (redraws happen on player movement, not continuously).

### Typical Case: Dirty Rendering

Most turns, only the area around the player (light radius + 1) changes. With
light radius 2, that's a ~7×7 area = 49 tiles. Each tile requires 2 VDC address
sets + 2 data writes = ~4 register accesses × 10 µs = ~40 µs per tile.
49 tiles × 40 µs = ~2 ms. Imperceptible.

### Optimization: Deferred Attribute Write

If the color doesn't change often (many tiles share the same color), we can skip
attribute writes for tiles whose color matches the existing VDC attribute. This
requires reading the VDC attribute first (slower per-tile) but saves time when
most tiles don't change color. Deferred to future optimization pass.

---

## C128 Banking Strategy

The C128 overlay system works identically to C64 — overlays at $E000 loaded
from disk or REU, banked in/out via the MMU instead of PLA $01. The trampoline
pattern is the same:

```asm
tramp_level_generate:
    sei
    lda #C128_BANK_NO_ROMS      // MMU equivalent of $34
    sta C128_MMU_CONFIG          // $FF00 instead of $01
    jsr level_generate
    lda #C128_BANK_NO_BASIC     // MMU equivalent of $36
    sta C128_MMU_CONFIG
    cli
    rts
```

The `BANK_NO_BASIC`, `BANK_NO_KERNAL`, `BANK_NO_ROMS` constants are redefined
in `memory128.s` with C128 MMU values. `C128_MMU_CONFIG` = `$FF00`.

For `input_get_key`, the same approach works: save/restore MMU config, set to
normal mode (KERNAL visible) for keyboard scanning, then restore.

---

## Future Phases (10.2–10.4, not designed here)

### 10.2 — Extended Memory (C128 128 KB)

The C128 has two 64 KB RAM banks. Bank 1 could store:
- All creature tier data (eliminate disk loading entirely)
- All overlays pre-loaded at startup
- String bank data

Access via MMU bank switching instead of REU DMA. This gives stock C128 users
the same "instant tier loading" experience as C64+REU users.

### 10.3 — Larger Dungeon

With 80-col display and more RAM, the map could expand to 120×80 or larger.
The 78-wide viewport means the player sees almost the full horizontal extent
without scrolling. Larger maps need more RAM for the map array
(120×80 = 9,600 bytes — fits easily in C128 with bank switching).

### 10.4 — Enhanced VDC Display

VDC attributes enable visual effects not possible on VIC-II:
- **Blink** (bit 4): blinking effect on certain tiles (stairs, traps)
- **Reverse** (bit 6): highlight player, selected menu items
- **Underline** (bit 5): underline active status effects
- Potentially load a custom character set into VDC RAM for better dungeon graphics

---

## Risk Register (C128-specific)

| Risk | Impact | Mitigation |
|------|--------|-----------|
| VDC register access too slow for viewport rendering | Sluggish movement, visible redraw | Row-batch streaming minimizes address sets. Dirty rendering limits updates. Benchmark in VICE. |
| Screen code ↔ VDC code translation bugs | Garbled text | Build translation test: render all game characters, compare. Keep arithmetic conversion simple. |
| VDC color mapping looks wrong on RGBI monitors | Poor aesthetics | Test with VICE 80-col output. Tune vic_to_vdc_color table. Accept that RGBI palette is inherently different from VIC-II. |
| C128 MMU banking differs more than expected from PLA | Banking bugs, crashes | Study C128 PRG carefully during implementation. Use VICE x128 monitor to verify bank states. Keep banking constants in one file (memory128.s). |
| KERNAL GETIN behavior differs on C128 | Keyboard input fails | C128 KERNAL is compatible. input_get_key already handles banking correctly. Test early. |
| Kick Assembler cross-directory #import issues | Build failures | Test `#import "../c64/module.s"` syntax early. May need `-libdir` flag. |
| Title screen art format assumes 40-col | Title art garbled at 80-col | Create 80-col title art file, or center 40-col art with padding. Title render data format (row/col/color/string) works at any width. |
| C128 disk access slower or different | Load failures | C128 KERNAL LOAD is compatible with C64. 1571 drive is faster than 1541. Test with both drive types in VICE. |
