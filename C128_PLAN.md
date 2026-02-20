# C128 Separation and Expansion Plan

## 1. Executive Summary

The goal is to create a distinct, premier version of Moria for the Commodore 128 that utilizes the machine's full capabilities (128KB RAM, 80-column VDC, 2MHz CPU) to restore 100% of the features cut from the C64 version.

**Strategy:** **Separate Binaries**
Instead of a single compromised binary, we will build two dedicated versions sharing a common core:
-   **`moria64.prg`**: Optimized for C64 (40-col, tiered loading, smaller maps).
-   **`moria128.prg`**: Optimized for C128 (80-col, full memory resident, large maps).

## 2. Architecture & File Structure

The `commodore/` directory will be restructured to maximize code sharing while allowing platform-specific overrides.

### New Directory Layout

```
commodore/
├── common/             # SHARED CODE (Logic, Data, Math, RNG)
│   ├── game_params.inc # Assembler constants (MAP_W, MAX_MONSTERS)
│   ├── math.s
│   ├── rng.s
│   ├── tables.s
│   ├── dungeon_gen.s   # (Refactored to be screen-size agnostic)
│   ├── monster_ai.s
│   ├── combat.s
│   ├── item.s
│   └── ...
├── c64/                # C64 SPECIFIC (I/O, Screen, Memory)
│   ├── main.s          # Entry point
│   ├── screen.s        # VIC-II 40-col driver
│   ├── input.s         # Keyboard driver
│   ├── memory.s        # 64KB Banking logic
│   └── boot.s
├── c128/               # C128 SPECIFIC (I/O, VDC, Memory)
│   ├── main.s          # Entry point (Go64/Fast mode setup)
│   ├── screen_vdc.s    # VDC 80-col driver
│   ├── input_c128.s    # C128 Keyboard driver (extended keys)
│   ├── memory_128.s    # 128KB Banking logic (MMU)
│   └── boot.s
└── include/            # Shared Headers
    └── zeropage.s
```

> **REVIEW NOTE — "Great Split" is premature.** See Section 8 (Audit) for
> recommended alternative: build C128 via `#import "../c64/..."` first,
> extract to `common/` only after both platforms build and you can verify
> what's actually shared. Several files assumed to be "common" contain
> platform-specific code (see Section 8.3).

### Component Analysis

| Component | Status | Action |
| :--- | :--- | :--- |
| **Math / RNG** | Shared | Move to `common/` |
| **Game Logic** | Shared | Move to `common/` (Combat, Move, Turns) |
| **Dungeon Gen** | Shared* | Refactor to use soft-coded dimensions from `game_params.inc` |
| **Screen Output** | Specific | `c64/screen.s` (VIC) vs `c128/screen_vdc.s` (VDC) |
| **Input** | Specific | `c64/input.s` vs `c128/input.s` (Keypad support) |
| **Memory** | Specific | `c64` uses overlays; `c128` uses MMU banks |
| **Data Tables** | Split | Core tables in `common/`; Size definitions in `game_params.inc` |

## 3. C128 Technical Implementation

### A. 80-Column Display (VDC)
The C128 uses the MOS 8563 VDC for 80-column text. Unlike the VIC-II, it is not memory-mapped but accessed via two registers ($D600/$D601).

-   **Driver**: `c128/screen_vdc.s` will implement the same abstract interface as `c64/screen.s`:
    -   `screen_clear`
    -   `screen_put_char`
    -   `screen_put_string`
-   **Attributes**: The VDC supports attributes (Color, Blink, Underline, Reverse) separate from character data. We will use this for the "Enhanced Display" requirement (e.g., color-coded monsters).
-   **Performance**: VDC access is slow. We must use the **2MHz CPU mode** during rendering.

> **REVIEW NOTE — VDC write protocol.** Each byte written to VRAM requires:
> (1) write register number to $D600, (2) poll bit 7 of $D600 until ready,
> (3) write data to $D601. That's ~15-20 cycles per byte vs ~6 for direct
> `sta (ptr),y` on VIC-II. A 78x19 viewport with separate character +
> attribute bytes = ~3,000 VDC writes per full redraw. At 2MHz with I/O
> throttled to 1MHz (see Section 3.D), this is ~45,000-60,000 cycles per
> redraw (~30-40ms). **Dirty-tile tracking is essential** to avoid full
> redraws. This must be prototyped early — see Section 8.5.

### B. Memory Map (128KB)
We will use the C128's MMU to access Bank 1.

-   **Bank 0 (Main)**: Program Code, Zero Page, Stack, I/O.
-   **Bank 1 (Data)**: Full Monster Database, Full Item Database, Full Maps.
    -   *Constraint Removal*: No more "Tiered Loading". All 279 monsters and item templates will reside in Bank 1 RAM.
    -   *Implementation*: A helper `bank_read` / `bank_write` routine in `memory_128.s` will handle fetching data from Bank 1.

> **REVIEW NOTE — MMU implementation details.**
> - Must use **`$FF00`** for MMU configuration writes, not `$D500`.
>   `$D500` is only accessible when I/O is banked in; `$FF00` is always
>   available regardless of configuration.
> - MMU configuration register layout: bits 7-6 = RAM bank (00=Bank 0,
>   01=Bank 1), bits 5-4 = high ROM ($C000-$FFFF), bits 3-2 = mid ROM
>   ($8000-$BFFF), bit 1 = low ROM, bit 0 = I/O visibility.
> - **Common RAM is required.** The `bank_read`/`bank_write` routines must
>   reside in MMU "common RAM" — a configurable shared region (1K/4K/8K/16K
>   at bottom and/or top of address space) visible in both banks. Without
>   this, the switching code disappears from under its own feet mid-switch.
> - Zero page and stack should be configured as common RAM (bottom 1K shared).

### C. Feasibility Study: Memory Budget (Bank 1)

Can the full dataset fit in the 64KB of Bank 1?
-   **Monsters**: ~16 KB (Template data + Strings for 279 creatures)
-   **Items**: ~12 KB (Template data + Strings for <256 types)
-   **Recall Data**: ~5.5 KB (Monster memory)
-   **TOTAL**: **~33.5 KB**
-   **Free Space**: **~30.5 KB**

Note: Map data (13 KB) lives in Bank 0 at $4000-$730B (see Section 8.6),
not in Bank 1. This leaves substantial Bank 1 headroom for string banks,
attribute maps, or other future data.

**Conclusion**: Yes. The stock 128KB C128 is more than sufficient. A 256KB
REU/Expansion is **not required**.

> **REVIEW NOTE — Map memory placement: RESOLVED.** The map will live at
> $4000-$730B in Bank 0 (BASIC ROM banked out via MMU). No I/O conflict,
> no bank-switch overhead, 5 cycles per tile read. Map data removed from
> Bank 1 budget — revised Bank 1 total: ~33.5 KB used, ~30.5 KB free.
> See Section 8.6 for full analysis.

### D. 2MHz Mode
The C128's 8502 can run at 2MHz.
-   **Activation**: `lda $d030 : ora #$01 : sta $d030` (set bit 0 to enable fast mode; preserves bit 1).
-   **Usage**: Enabled during Dungeon Generation, Turn Processing, and VDC Rendering.
-   **Restriction**: VIC-II cannot display graphics in 2MHz mode (screen goes black or garbage). Since we use VDC for the main display, **we can run at 2MHz for all computation** (leaving the VIC screen blank/black).

> **REVIEW NOTE — I/O throttling.** All I/O access at $D000-$DFFF is
> **automatically throttled to 1MHz by hardware**, even when the CPU is in
> 2MHz mode. This means every VDC register write, SID access, and CIA access
> incurs 1MHz cycle penalties. The effective speed during I/O-heavy operations
> (VDC rendering, disk access) is significantly less than 2MHz. The 2x
> speedup applies fully only to pure computation (dungeon gen, AI, combat
> math). Do not characterize this as "2MHz 100% of the time."

## 4. Feature Restoration Requirements

The C128 version will restore features cut from `moria8` to match `umoria`.

| Feature | C64 Implementation | C128 Implementation |
| :--- | :--- | :--- |
| **Dungeon Size** | 80 x 48 (4 screens) | **198 x 66** (Original size) |
| **Monsters** | 120 (5 Tiers, disk/REU loaded) | **279** (Full umoria roster, all resident in Bank 1) |
| **Active Monsters** | 32 limit | **64+ limit** (2MHz CPU allows it) |
| **Items** | 62 Templates | **Up to 255 Templates** (8-bit index ceiling; see note) |
| **Stores** | 8 Stores | **8 Stores** (already matches umoria's 6 + Black Market & Home enhancements) |
| **Display** | 40-col scrolling | **80-col** (Full view / less scrolling) |

> **REVIEW NOTE — Corrected counts from umoria source:**
> - Monsters: `MON_MAX_CREATURES = 279` in `umoria/src/monster.h`. Previous
>   claim of "350+" was overstated by ~25%.
> - Items: `MAX_OBJECTS_IN_GAME = 420` in `umoria/src/game.h`, but this
>   includes doors, traps, rubble, stairs, and other non-collectible dungeon
>   features. Actual collectible item templates are well under 255.
> - Stores: umoria has **6 stores** (`MAX_STORES = 6` in `umoria/src/store.h`).
>   Black Market and Player Home are **Angband features**, not umoria.
>   Moria8 already implements 8 stores on C64 as an enhancement — this is
>   not a "restoration" but is already done.
>
> **Item type hard limit:** The entire item system uses 8-bit X-indexed SoA
> access (`lda it_category,x`). Going past 255 item types requires either
> a tier/paging system, 16-bit pointer-based access (major rewrite, much
> slower on 6502), or staying under 256 and using ego/enchantment for
> variation (which moria8 already does). See Open Question Q4.

## 5. Plan of Attack

### Phase 1: Refactoring (The "Great Split")
1.  Create `commodore/common/` and `commodore/c128/`.
2.  Move strictly logic-only files (Math, RNG, Combat) to `common/`.
3.  Update `c64/main.s` to import from `../common/`.
4.  Update `Makefile` to continue building `moria64` successfully.
5.  **Verify**: C64 build must pass all current tests.

> **REVIEW NOTE — Recommended revision:** Do NOT move files until the C128
> build exists. Build C128 by importing from `../c64/` initially. Only
> extract to `common/` after both platforms build and you can empirically
> verify what's shared. See Section 8.2.

### Phase 2: Abstraction & Parameters
1.  Create `game_params.inc`. Define `MAP_WIDTH`, `MAP_HEIGHT`, `MAX_MONSTERS`.
    -   C64: `MAP_WIDTH=80`, `MAX_MONSTERS=32`.
    -   C128: `MAP_WIDTH=198`, `MAX_MONSTERS=64`.
2.  Refactor `dungeon_gen.s` to use these constants instead of hardcoded values.
3.  Refactor `screen.s` calls to use a standardized jump table (already mostly done per architectural review).

### Phase 3: C128 Bootstrap
1.  Create `c128/main.s`.
2.  Implement `c128/boot.s`:
    -   Detect C128 mode.
    -   Switch to 2MHz.
    -   Initialize VDC 80-col mode.
3.  Implement `c128/screen_vdc.s` (Basic text output).
4.  **Verify**: `make moria128` boots, clears screen, and prints "Moria C128" in 80 columns.

> **REVIEW NOTE — VDC rendering must be prototyped here**, not deferred to
> Phase 6. Implement a test that draws a mock dungeon viewport (78x19 tiles
> with character + attribute writes) and measure the cycle count. If full
> redraw exceeds ~100ms, dirty-tile tracking is mandatory. If even dirty-tile
> rendering is too slow, the entire plan needs rethinking. **This is the
> critical path — the plan's feasibility depends on this result.**

### Phase 4: Core Game Port
1.  Connect `c128/main.s` to `common/` game loop.
2.  Implement `c128/input.s` (Standard decoding + Keypad).
3.  Implement `c128/memory_128.s` (Bank 1 access).
4.  **Verify**: Player can walk around the Town level in 80-column mode.

### Phase 5: Content Expansion (The "Un-Cut")
1.  Import complete `umoria` monster/item tables into `data/full_db/`.
2.  Configure C128 build to compile `data/full_db/` into Bank 1.
3.  Update `common/monster.s` and `common/item.s` to fetch from Bank 1 if `UnifiedBuild` flag is set (or similar compile-time switch).
4.  Verify: Full monster roster spawns.

### Phase 6: Polish
1.  Implement VDC Attributes (Color).
2.  Optimize VDC drawing routines (use hardware block copy if possible, or unrolled loops).
3.  Switchable 40/80 column Logic?
    -   *Decision*: **Drop 40-col support for C128 binary.** The C128 user wants 80 columns. Supporting variable width at runtime complicates the renderer significantly. If they want 40 columns, they can run `moria64.prg`.
    -   *Correction*: User requested "Switchable".
    -   *Revised Plan*: If 40-col is active, use `c128/screen_vic.s` (wrapper around VIC). This requires dual rendering backends. We will prioritize 80-col first.

## 6. Build System Updates

New Makefile targets:
```makefile
moria64:
    $(KICKASS) c64/main.s -o out/moria64.prg

moria128:
    $(KICKASS) c128/main.s -o out/moria128.prg
```

## 7. Risks & Mitigation

1.  **Code Maintenance**: Shared code might accidentally break one platform.
    -   *Mitigation*: Automated build script compiles BOTH versions on every commit.
2.  **VDC Speed**: 80-col text can be slow.
    -   *Mitigation*: 2MHz mode is mandatory. Use "burst" writing techniques for VDC. Dirty-tile tracking to minimize redraws.
3.  **Memory Management**: 128KB banking is complex.
    -   *Mitigation*: Keep Bank 1 strictly for *data* (tables). Keep Code in Bank 0. This avoids complex code-execution-across-banks issues. Bank-switch helpers must reside in MMU common RAM.

---

## 8. Architecture Review (2026-02-17)

Findings from senior principal engineering review against the moria8 codebase
and umoria source. Items are organized by severity.

### 8.1 Factual Corrections

| Original Claim | Correction | Source |
|---|---|---|
| "351+ monsters" | **279** (`MON_MAX_CREATURES`) | `umoria/src/monster.h` |
| "400+ item templates" | **420 total object defs**, but includes doors, traps, rubble, stairs. Collectible item templates < 255. | `umoria/src/game.h` |
| "8 Stores (Adding Black Market & Home)" | umoria has **6 stores**. Black Market & Home are Angband features. Moria8 already has 8 stores on C64. | `umoria/src/store.h` |
| "350+ Full Roster" in feature table | **279** — overstated by 25% | `umoria/src/monster.h` |
| "`lda #1 : sta $d030`" for 2MHz | Should use `ora #$01` to preserve bit 1 of $D030 (VIC-IIe test bit) | C128 PRG |
| "2MHz 100% of the time" | I/O at $D000-$DFFF is hardware-throttled to 1MHz; effective speed during VDC rendering is < 2MHz | C128 hardware docs |
| C64 has "160 (Tiered)" monsters | C64 currently has **120 creatures** across 5 tiers (T0 town + T1-T4 dungeon) | moria8 `creature_data/` |
| C64 has "55 Templates" items | C64 currently has **62 item types** (`ITEM_TYPE_COUNT`) | moria8 `item.s` |
| C64 has "6 Stores" | C64 already has **8 stores** (6 standard + Black Market + Player Home) | moria8 `store.s`, `ui_home.s` |

### 8.2 The "Great Split" Should Be Deferred

Phase 1 proposes moving ~40 files into `common/` before any C128 code exists.
This is premature and risky:

- Creates a massive diff that harms `git blame` and risks breaking the only
  working product (C64).
- You cannot know which files are truly "common" until the C128 version
  actually builds and runs.
- Several files assumed to be portable contain platform-specific code
  (see 8.3 below).

**Recommended approach:** Build the C128 version by `#import`ing directly from
`../c64/`. Extract to `common/` only after both platforms build successfully
and shared code is empirically verified. "Make it work, then make it clean."

### 8.3 Hidden Platform Dependencies in "Common" Files

Files the plan assumes are shared but contain VIC-II or C64-specific code:

| File | Issue |
|---|---|
| `spell_effects.s` (line 649) | Converts screen RAM ptr to color RAM by adding `$d4` to high byte — VIC-II specific `$0400`→`$D800` trick. Breaks on VDC. |
| `dungeon_render.s` | Writes directly via `sta (zp_screen_lo),y` / `sta (zp_color_lo),y` for performance. Fundamentally incompatible with VDC register-port I/O. |
| `dungeon_gen.s` (line 1988-1991) | Uses screen RAM at `$0400` as scratch BFS queue during map generation. |
| `overlay.s` (line 110-112) | Restores `$DD00` (CIA2 VIC bank) after disk I/O. No VIC bank concept on VDC. |
| `tier_manager.s` | Same `$DD00` restoration as `overlay.s`. |
| `ui_messages.s` (line 17, 187) | `MSG_HIST_LEN = 40` tied to 40-column width; multiply-by-40 routine uses `x32 + x8` shift pattern. |
| `title_data.s` | Title art hardcoded for 40-column layout with explicit row/column coordinates. |
| `ui_help.s` (line 6) | Layout explicitly designed for "40 columns, 25 rows". |
| `ui_status.s` (line 248, 264) | Status bar column positions hardcoded (`lda #19` for AC, `lda #25` for AU). |
| `main.s` (line 170, 195) | Text centering hardcoded: `(40-23)/2`, `(40-11)/2`. |
| `disk_swap.s` (line 55, 62) | Centering hardcoded: `(40-16)/2`, `(40-13)/2`. |

### 8.4 What the Codebase Already Provides

The C64 code was designed with C128 in mind — the plan should leverage this:

- **`screen.s` jump table** (lines 6-7, 52): `screen_vectors` with 5 entry
  points (`screen_clear`, `screen_put_char`, `screen_put_string`,
  `screen_set_color`, `screen_clear_row`). Comments explicitly state:
  "Vector table allows the 80-column VDC backend to be swapped in for C128
  support (Phase 10) without changing any callers."
- **`zp_view_w` / `zp_view_h`** (zeropage.s lines 159-160): Runtime viewport
  dimensions already stored in zero page. Comment says "38 for 40-col,"
  implying it was designed to be variable.
- **`config.s`**: Already has `$D600` (VDC) and `$D7` (C128 mode flag)
  detection code.
- **Named constants**: `SCREEN_COLS`, `SCREEN_ROWS`, `VIEWPORT_W`,
  `VIEWPORT_H`, `MAP_COLS`, `MAP_ROWS` are defined symbolically. ~80% of
  dimension usage references these constants and would auto-adapt if changed.
- **Row lookup tables**: Generated at compile time with `.fill` — auto-adapt
  to constant changes.

### 8.5 VDC Rendering Is the Critical Path

The plan defers VDC rendering optimization to Phase 6 (Polish). This is the
single hardest engineering challenge and must be validated in Phase 3.

**The problem:** `dungeon_render.s` currently writes tiles via direct store
instructions (`sta (zp_screen_lo),y`) — 6 cycles per tile. On VDC, each VRAM
byte requires register write + poll + data write through $D600/$D601, all
throttled to 1MHz. That's ~15-20 cycles per byte, plus separate attribute
writes.

**Performance estimate for full viewport redraw (78x19 = 1,482 tiles):**
- Character writes: 1,482 × ~18 cycles = ~26,676 cycles
- Attribute writes: 1,482 × ~18 cycles = ~26,676 cycles
- Total: ~53,352 cycles at 1MHz effective = ~53ms per full redraw

This is borderline acceptable (~19 FPS) but assumes no other overhead. Real
rendering includes map lookups, tile-to-character conversion, color lookups,
and viewport clipping.

**Required Phase 3 deliverable:** A benchmark that draws a mock viewport on
VDC and reports cycle count. If full redraw > ~100ms, implement dirty-tile
tracking. If even dirty-tile rendering is too slow, the plan needs fundamental
rethinking.

### 8.6 Map Memory Placement — RESOLVED

**Decision: Use full 198x66 map at $4000-$730B in Bank 0.**

198x66 = 13,068 bytes (12.8 KB). This is the original umoria dungeon size and
should be used on C128. Keeping 80x48 would be strictly worse — an 80-column
display with a 78-wide viewport shows 97.5% of the map width, destroying
horizontal exploration. The smaller map also limits rooms to 4-8 (vs umoria's
25-40), caps active monsters at 32 (vs 125), and floor items at 32 (vs 175).

**Placement:** Bank out BASIC ROM via MMU (`ora #$02 : sta $FF00`), exposing
$4000-$7FFF as 16 KB of free RAM. The map fits with room to spare:

```
$4000-$730B  Dungeon map (198x66 = 13,068 bytes)
$730C-$740B  Floor item table (256 bytes)
$740C-$7FFF  Scratch buffers (3,060 bytes free)
```

**Why this works:**
- Zero bank-switching overhead — direct `lda (ptr),y` at 5 cycles per tile
- No I/O conflict — $4000-$730B is far from $D000
- KERNAL and I/O remain available (only BASIC ROM is banked out)
- BASIC ROM is already unused (CLAUDE.md: "Do NOT use BASIC routines")
- Only requires changing `MAP_BASE` constant; no structural code changes

**Program code space with map at $4000 (C128 Bank 0):**

```
$1300-$3FFF  Program code                    11.5 KB
$8000-$BFFF  Program code (ROM banked out)   16.0 KB
$C000-$CFFF  Program code / data              4.0 KB
$E000-$FFFF  Program code (KERNAL out)        8.0 KB
                                     Total: ~39.5 KB
```

This is comparable to the current C64 layout. Bank 1 (64 KB) holds all bulk
data: creature tables, item tables, string banks, recall data.

**Rejected alternatives:**

| Option | Why rejected |
|---|---|
| Map at $C000 (current C64 location) | 13 KB extends to $D31B, colliding with I/O at $D000 |
| Map in Bank 1 | Every map read requires bank switch (13 cycles vs 5). Viable but unnecessary when $4000 is available |
| Keep 80x48 | 78-col viewport shows nearly full width; rooms, monsters, and items all severely constrained; defeats the purpose of the C128 port |

### 8.7 Item Type 255 Ceiling

The entire item system uses 8-bit X-indexed SoA access:
```
lda it_category,x    ; X = item type ID (0-255)
lda it_display,x
lda it_color,x
```

Going past 255 types is not possible without one of:
- A tier/paging system for items (analogous to creature tiers)
- 16-bit pointer-based access (major architectural rewrite, very slow on 6502)
- Staying under 256 types and using ego/enchantment for variation (already done)

Since umoria's collectible item count is well under 255 when door/trap/rubble
object definitions are excluded, **staying under 256 with ego items is the
correct approach**. The plan should acknowledge this limit explicitly rather
than promising "400+ templates."

---

## 9. Open Questions

These must be answered before implementation begins:

**Q1. VDC rendering performance.** Can the VDC render a 78x19 dungeon viewport
at acceptable speed (~10+ FPS with dirty-tile tracking)? This determines
whether the entire plan is feasible. **Must be answered by prototype in
Phase 3 before any refactoring work begins.**

**Q2. Phase ordering.** Should Phase 1 (refactoring) happen before or after
Phase 3 (C128 bootstrap)? The review recommends bootstrap first, refactor
after — but this affects the entire schedule.

**Q3. Map size and placement.** ~~RESOLVED~~ — Use full 198x66 at $4000-$730B
in Bank 0 (BASIC ROM banked out). See Section 8.6 for details.

**Q4. Item type count strategy.** Stay under 255 types with ego/enchantment
variation (simple, already works) or implement item tier paging (complex,
mirrors creature tier system)? umoria's collectible items fit under 255, so
paging may be unnecessary engineering.

**Q5. MMU common RAM size.** How much common RAM (shared between Bank 0 and
Bank 1) is needed? Bank-switch helpers, zero page, and stack need to be in
common RAM. The MMU supports 1K, 4K, 8K, or 16K at bottom and/or top of
address space. What's the minimum required?

**Q6. VDC dirty-tile tracking design.** If full redraws are too slow (likely),
how is the dirty-tile bitmap structured? One bit per tile = 78x19 = 186 bytes.
Where does this live? How does it interact with LOS updates, monster movement,
and scroll events?

**Q7. 40/80 column switching.** The plan contradicts itself (drop 40-col, then
revised to support it). Is runtime 40/80 switching a real requirement? If so,
it means maintaining two complete rendering backends in the C128 binary, which
is significant complexity. If the answer is "just run moria64.prg for 40-col,"
that simplifies the C128 build substantially.

**Q8. C128 overlay system.** With 128KB native RAM, does the C128 version still
need the overlay system (STARTUP/TOWN/DEATH sharing $E000)? If all data fits
in Bank 1, overlays could be eliminated entirely, simplifying the architecture.

**Q9. Keyboard input.** The C128 numeric keypad is electrically separate and
can be distinguished from main keyboard keys via location $D4. Should the C128
version support roguelike numpad movement (1-9 for 8 directions + wait)?
This is a significant gameplay improvement but requires a different input
driver architecture.
