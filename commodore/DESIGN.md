# Moria C64/C128 — Design Reference

> Architectural reference and design decisions for the Moria C64/C128 port.
> Extracted from BUILDPLAN.md on 2026-02-18.
> See [BUILDPLAN.md](BUILDPLAN.md) for active plans, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## The Problem

Umoria's data footprint (~90-110 KB of game tables, map, and text) far exceeds the
C64's ~38 KB of usable RAM. The original runs on an 80x24 terminal; the C64 has 40x25.
Every design decision flows from these two constraints.

---

## Memory Budget (C64)

| Region | Address | Size | Use |
|---|---|---|---|
| Zero page (BASIC area) | $02–$8F | ~140 bytes | Hot variables, pointers (see ZP notes below) |
| Program code | $0801–$BFFF | ~46 KB | Code + resident data (BASIC ROM banked out at startup) |
| *(of which $A000–$BFFF)* | | *(8 KB)* | *(RAM under BASIC ROM — usable because ROM is banked out)* |
| Free RAM (no banking) | $C000–$CFFF | 4 KB | Dungeon map (3,840 bytes at $C000–$CEFF) + floor item table (256 bytes at $CF00–$CFFF) — always accessible |
| RAM under KERNAL ROM | $E000–$FFFF | 8 KB | Banked data: `$E000`–`$EFFF` = phase overlays (creature tiers in dungeon, store code in town — see OPT-2); `$F000`–`$FFFA` = permanent banked code (special rooms, ego items, UI screens) |
| Screen RAM | $0400–$07E7 | 1 KB | Display |
| Color RAM | $D800–$DBE7 | 1 KB | Display colors |
| **Total usable** | | **~58 KB** | With banking (code + all banked regions) |

On the C128, the full 128 KB is available through bank switching, which gives us
much more room. The design should target C64 as the constrained baseline.

**C128 high-memory ownership rule:** The C128 port must keep the live overlay
window and the reloadable banked payload physically separate in Bank 0 RAM.
`$E000-$EFFF` is the overlay execution window; `$F000-$FFFA` is the reloadable
banked payload window. Persistent overlay metadata/state must live in resident
Bank 0 RAM, not adjacent to overlay code. No startup-overlay routine may trigger
`init_copy_banked` while startup overlay execution is active.

**C128 runtime-loaded code rule:** For any copied or disk-loaded runtime code,
the linked address, PRG load header, load destination bank, visible execution
bank, and recopy source span must all agree. A callable symbol is not enough.
This exact class of mismatch caused:
- post-chargen `JSR $1000` crashes when low-RAM VDC code loaded into the wrong bank
- help/inventory blank screens when a recopy source overlapped `$E000-$EFFF`
- dungeon-descent `JAM`s when ego-item code drifted into `$D000-$DFFF`

**C128 low/high RAM caveats:**
- `$1000-$3FFF` is not common RAM in the shipping C128 runtime model
- `$D000-$DFFF` is the I/O hole and cannot be treated as ordinary executable RAM with I/O visible

**Zero page KERNAL conflicts:** Although $02–$8F is nominally free from BASIC,
some locations are clobbered by KERNAL routines. In particular, $22–$25 are used
by KERNAL LOAD/SAVE, $14–$15 by KERNAL OPEN, and several others by KERNAL I/O.
The `zeropage.s` module must document which ZP locations are safe to use freely
vs. which must be saved/restored around KERNAL calls (especially tier_manager.s
and save.s). Divide ZP into "permanent" variables (never touched by KERNAL) and
"volatile" variables (caller-save around KERNAL calls).

**Banking note — $E000–$FFFF:** When KERNAL ROM is banked out, hardware IRQ/NMI
vectors at $FFFE/$FFFF read from RAM. All access to this region must be wrapped
in SEI/bank-out/access/bank-in/CLI sequences. Because this overhead is expensive,
**the dungeon map must NOT live here** — it goes in the always-accessible $C000
region instead. Reserve $E000–$FFFF for infrequent bulk access (tier data loading,
save/load).

**Carried inventory contract:** The carried pack is a dense prefix, not a sparse
absolute-slot array. Whole-item removals shift later carried items left, so pack
letters always follow the current packed order (`A..` current count). Equipment
remains fixed-slot and does not compact. Filtered selectors should keep mapping
through their visible-slot cache; direct all-items carried prompts may still do
`A -> slot` math only because the dense-pack invariant now makes visible order
and carried-slot order the same thing.

**Timed-effect contract:** Transient buffs must behave as timers, not as sticky
boolean latches hidden inside timer space. If an effect extends over turns, the
effect owner must:
- add duration on application
- participate in `turn_tick_effects` decay unless there is an explicit separate
  expiration owner
- keep its player-facing cast feedback in the live gameplay path instead of
  relying on one-shot first-set assumptions that can be invalidated by saved or
  already-active runtime state

**Death-screen layout contract:** `score.s` remains the single owner of the
death/high-score screen on both targets. The composition is still a 40-column
block, but it must be expressed relative to `SCREEN_COLS` instead of raw
absolute columns so:
- C64 keeps the historical 40-column layout unchanged
- C128 centers that same block cleanly in 80-column mode
- the high-score row start, value column, pad threshold, and footer all move
  together instead of drifting into a partial left-anchored layout

---

## Data Compression Strategy

The raw umoria data must be reduced to fit. Here is the approach for each major
data set:

### Dungeon Map

Original: 66 rows x 198 columns x 4 bytes = ~52 KB. **This cannot fit.**

**Redesigned map:** 40 columns x 24 rows per screen, with a dungeon of 80 x 48
tiles total (4 screens, 2x2 grid) = 3,840 tiles.

Each tile is encoded in a single byte:
- Bits 7–4: tile type (wall, floor, door, stairs, rubble, magma, quartz — 16 types)
- Bit 3: lit flag
- Bit 2: visited/known flag
- Bit 1: treasure present flag (index into separate small treasure-on-floor table)
- Bit 0: creature present flag (index into active creature table)

Map cost: 3,840 bytes (~3.75 KB) at $C000–$CEFF.

**Sparse lookup tables:** Tile bits 0 and 1 are boolean flags only — they indicate
presence, not identity. To find WHICH creature or item is at a given tile,
scan the corresponding runtime table for a position match:

- **Active monster table:** Up to 32 entries x 12 bytes (position, creature type
  index, current HP, status flags, speed counter) = 384 bytes. Stored in main
  RAM ($0801–$9FFF). Linear scan of 32 entries per tile lookup is fast.
- **Floor item table:** Up to 32 entries x 8 bytes (position, item template index,
  enchantment, quantity) = 256 bytes. Stored at $CF00–$CFFF (remainder of the
  $C000 region after the map). 32 floor items per level is sufficient given
  the 80x48 map size — items beyond this limit are not spawned.

### Creature Data

Original: 351 creatures x ~45 bytes = ~15.8 KB.

**Tiered loading (as implemented in R3.5):** 120 creatures across 5 tiers:
- Tier 0 (town): 8 creatures — always resident in program code (indices 57-62)
- Tier 1 (DL 1–8): 24 creatures — loaded from disk/REU
- Tier 2 (DL 5–15): 32 creatures — loaded from disk/REU
- Tier 3 (DL 11–25): 39 creatures — loaded from disk/REU
- Tier 4 (DL 20–100): 57 creatures — loaded from disk/REU

One dungeon tier active at a time. SoA layout: 22 arrays × up to 65 entries
(57 dungeon + 8 town = MAX_CREATURES). ~20 bytes per creature + ~15 bytes
for name string. Tier PRGs load to $E000 (RAM under KERNAL ROM), then
`load_tier_to_buffer` copies SoA data to active creature buffers in program RAM.
Name strings remain at $E000+ (read via `creature_get_name` with KERNAL banking).

REU path: all 4 tiers + 3 overlays preloaded at startup → DMA fetch on transition
(instant). Loading screen shows "LOADING INTO REU:" header with per-file progress
(`X/YYYKB` used/total). Display routine lives in banked $F000 region
(`reu_loading_banked.s`), called via self-modifying dispatch patched at startup.
Disk path: KERNAL LOAD tier PRG on each transition.
Tier overlap ranges prevent thrashing: T1=[1,8], T2=[5,15], T3=[11,25], T4=[20,100].

### Item/Treasure Data

Original: 420 items x ~35 bytes = ~14.7 KB.

**Simplified approach (as implemented):** 55 item types stored entirely in program
code as SoA arrays (no tiered loading). Items include 16 equipment types, 10
potions, 10 scrolls, 4 wands, 4 staves, 4 rings, and 7 ranged weapons/ammo.
~12 bytes per item type in SoA arrays + name strings. Total ~1.5 KB.

Item tiered loading was planned but not implemented — the reduced item count
(55 vs 420) fits comfortably in program RAM without banking. Future item
expansion (ego items, artifacts) may eventually require tiered loading.

### Text and Names

Monster names, item names, class titles, spell names, store dialogue — the
original has several KB of strings.

**Inline strings (current):** Names are stored as null-terminated strings
in program code using `.encoding "screencode_upper"` and `.text` directives.
No compression — the reduced roster (120 creatures, 55 items) keeps total
string data manageable (~3 KB). Creature name strings for tier data are stored
at $E000+ in the tier PRG files and accessed via `creature_get_name` with
KERNAL banking (SEI/$35 for reads).

**Planned: Huffman compression + string banks (R7).** Two-tier approach:
**Tier 1** — Huffman-compress strings into the ~3.7 KB free in main code area
($B196-$C020). At ~55% compression, this yields ~6-7 KB of effective text
capacity with no disk I/O or hardware requirements. Sufficient for shopkeeper
insults, haggling dialog, and moderate content additions. **Tier 2** — when
Tier 1 space is exhausted, store additional Huffman-compressed string banks on
disk as loadable PRG files in the $E000 overlay region. REU caches all banks at
startup for instant access when available; disk fallback for unexpanded C64s.
See R7.1-R7.7 in the R-series enhancement tracker for full plan.

### Monster Recall

Original: 351 creatures x ~16 bytes = 5.6 KB.

**Not implemented.** Monster recall (accumulated knowledge about creature
abilities) was planned but deferred. The per-tier recall files on disk
(`recall_t0.bin` through `recall_t4.bin`) described in the original plan
were never created. This is a missing feature, not a bug — the game plays
fine without it, but players don't accumulate creature knowledge across
encounters.

---

## Architecture Overview

```
main.s                    Entry point, BASIC stub, initialization
game_loop.s               Shared main loop orchestration, movement/running core, death/exit flow
├── game_loop_helpers.s   Shared UI-only command flows, result-policy helpers, post-turn tails
├── input_ui_helpers.s    Shared modal/follow-up input policy helpers, including platform escape-equivalent classification for read-only dismiss flows
├── config.s              System detection (C64/C128), column mode selection
├── memory.s              Bank switching routines, memory map management
├── zeropage.s            Zero page variable declarations (with KERNAL-safe zones)
├── turn.s                Turn post-action (effects → hunger → regen → AI → turn counter), sets shared scene-dirty state for redraw policy
│
├── screen.s              Screen output routines (40-col)
├── input.s               Keyboard input, command parsing
├── ui_status.s           Status bar rendering (3-line umoria-style)
├── ui_messages.s         Message line management (top of screen, "—more—" prompt)
├── ui_inventory.s        Inventory and equipment display screens
├── ui_character.s        Character info and spell list screens
├── ui_store.s            Store buy/sell UI screens
├── ui_help.s             Help screen rendering code (banked $F000, color-coded with box borders)
├── ui_help_data.s        Help screen string data (main RAM, inline color toggle markers)
├── color.s               Color palette definitions and color RAM management
│
├── rng.s                 Random number generator (32-bit LFSR)
├── math.s                16-bit multiply/divide, dice rolling, 24-bit math
├── tables.s              Lookup tables (stats, XP thresholds, price adjustments, etc.)
├── sound.s               Minimal SID sound effects (hit, miss, bump, spell, death)
│
├── player.s              Player struct, stat calculations, increment/decrement_stat
├── player_create.s       Character creation (race, stats, class, name)
├── player_move.s         Movement, running, searching, bump-to-attack
├── combat.s              Player melee combat (to-hit, damage, blows, XP, level-up)
├── player_magic.s        Spell/prayer casting, mana management, spell learning
├── player_items.s        Item use (eat, quaff, read, aim, use, equip, drop)
│
├── dungeon_gen.s         Dungeon generation (rooms, corridors, doors, streamers, stairs)
├── dungeon_render.s      Viewport scrolling, tile-to-screen-code mapping, dirty render
├── dungeon_los.s         Line of sight, lighting, torch radius, room reveal
├── dungeon_features.s    Traps, stairs, doors, secret doors, searching
│
├── monster.s             Monster data structures (SoA), spawning, creature tier buffers
├── monster_ai.s          Monster movement, wake/sleep, speed model, confused wandering
├── monster_attack.s      Monster melee attacks (8 types, poison, confuse, paralyze)
├── monster_magic.s       Monster spellcasting (bolts, breath, summon, blind, heal)
│
├── item.s                Item SoA tables (55 types), floor items, identification, stacking
├── store.s               Store system (8 stores/buildings), pricing, restocking, category masks
├── spell_data.s          Spell/prayer data tables (32 spells, names, costs, levels)
├── spell_effects.s       Shared effect subroutines (bolt, heal, teleport, detect, etc.)
├── ranged_fire.s         Ranged combat (bow/crossbow/sling fire command, ammo matching)
│
├── save.s                Save/load game state to disk (RLE map compression, checksum, overwrite confirm, saves kept after load/death)
├── score.s               Death screen, high score table, 24-bit score calculation
├── reu.s                 REU detection, DMA stash/fetch for tier data
├── reu_loading_banked.s  REU loading progress display (banked at $F000)
├── tier_manager.s        Creature tier loading (disk KERNAL LOAD or REU DMA)
│
└── data/
    ├── cr_tier1.s        Creature tier 1 data (DL 1-8, 24 creatures) → CR T1 on disk
    ├── cr_tier2.s        Creature tier 2 data (DL 5-15, 32 creatures) → CR T2 on disk
    ├── cr_tier3.s        Creature tier 3 data (DL 11-25, 39 creatures) → CR T3 on disk
    ├── cr_tier4.s        Creature tier 4 data (DL 20-100, 57 creatures) → CR T4 on disk
    └── parse_creatures.py  Python script to generate tier .s files from umoria data
```

~42 source files. Creature tier data assembled separately and loaded at runtime.

---

## Implementation Priorities and Dependencies

```
Phase 1 (Skeleton)
  │
  ├──► Phase 2 (Player/Character)
  │       │
  │       ├──► Phase 3 (Town) ──────────────────────┐
  │       │       │                                  │
  │       │       └──► Phase 4 (Dungeon) ──┬──► Phase 5 (Monsters) ──┐
  │       │                                │                         │
  │       │                                ├──► Phase 6 (Items) ─────┼──► Phase 7 (Magic)
  │       │                                │         │               │
  │       │                                │         └──► Phase 8 (Stores) ◄── Phase 3
  │       │                                │
  │       └────────────────────────────────┴──► Phase 9 (Save/Load, Polish)
  │
  └──► Phase 10 (C128 — independent, can start after Phase 1)
```

**Key parallelism:** Phases 5 (Monsters) and 6 (Items) are **independent peers**
after Phase 4 and can be developed in parallel. Items do not depend on monsters.
Phase 7 (Magic) depends on **both** Phase 5 (Monsters) for `monster_magic.s`
(breath weapons, monster spellcasting) **and** Phase 6 (Items) for scroll/potion/wand
infrastructure — both must be complete before Phase 7 begins.
Phase 8 (Stores) needs Phase 3 (Town) for the store locations and Phase 6 (Items)
for the item system. Phase 9 can begin once enough game state exists to be worth
saving (after Phase 4 at earliest).

---

## Key Design Decisions

### 1. Reduced Dungeon Size (80x48 vs 66x198)

The original 13,068-tile map is replaced with 3,840 tiles. This is still large
enough for interesting exploration (4 screen-sized rooms connected by corridors)
and fits in ~4 KB. Deeper levels can use the same 80x48 but with denser room
placement.

### 2. Reduced Monster/Item Counts

Active monsters capped at 32 (vs 125). Item templates reduced to 55 (vs 420).
Inventory slots reduced to 22+8 (vs 34+11). These keep memory under control while
preserving the core Moria experience.

### 3. Tiered Data Loading

Creature and item data is divided into depth tiers loaded from disk. Only 2
adjacent tiers are resident at once. Loading happens only on tier boundary
crossings (every 5–10 dungeon levels), not on every level change. Most level
transitions require zero disk I/O.

**Disk speed reality:** Standard 1541 KERNAL LOAD runs at ~300 bytes/sec. A
creature tier file (~2 KB) takes ~7 seconds stock. With JiffyDOS or equivalent
fastloader (~3–5 KB/sec), tier changes take ~1 second — acceptable given they
only happen at tier boundaries. The REU path eliminates disk I/O entirely after
the initial preload.

**As implemented:** Tier loading uses `tier_manager.s` with standard KERNAL
LOAD (no custom fastloader). The REU path (`reu.s`) preloads all 4 tiers at
startup, making subsequent transitions near-instant via DMA. Without REU,
JiffyDOS is recommended for acceptable load times. A custom fastloader was
planned but deferred — JiffyDOS compatibility covers most real-hardware users.

### 4. Simplified Haggling

The multi-round bidding system is replaced with a simple accept/decline at a
calculated price. This avoids the heavy text UI of the original and fits the
C64's tighter display constraints.

### 5. Reduced Spell Count

31 mage spells + 31 priest prayers → 16 + 16 = 32 total. Focus on the most
impactful and iconic spells. Cuts code size and spell table data in half.

### 6. 40-Column Layout

```
+--------------------------------------+
|Message line 1                        | Row 0
|Message line 2                        | Row 1
+--------------------------------------+
|                                      | Row 2
|                                      |
|          Game viewport               | Rows 2-20
|          (38 x 19 tiles)             | (38 cols visible)
|                                      |
|                                      | Row 20
+--------------------------------------+
|Moria  Dlvl:3  HP:45/45  MP:12/15    | Row 21
|STR:16  AC:5  Exp:1200   Full        | Row 22
+--------------------------------------+
|[Space] for more                      | Row 23 (input prompt)
+--------------------------------------+
| Border column 0 and 39 reserved      |
+--------------------------------------+
```

### 7. Unshifted Character Set (Uppercase + Graphics)

The C64 has two character sets: unshifted (uppercase + box-drawing graphics) and
shifted (lowercase + uppercase, fewer graphics). These are mutually exclusive —
you cannot display lowercase letters and box-drawing wall characters at the same
time. The game uses **unshifted mode** to get box-drawing characters for walls.
All text (messages, names, menus) is uppercase only. This matches the retro
aesthetic and is standard for C64 games. No custom character set is loaded.

### 8. Color Palette

The C64's 16 colors are used to improve map readability via color RAM ($D800+).
The palette is defined in `color.s`:
- Walls: light grey — structural, background
- Floor: dark grey — recedes visually
- C128 VDC note: the hardware only provides two practical grey luminance steps. The shared palette still keeps `COL_DGREY` / `COL_GREY` / `COL_LGREY`, but the C128 VDC translation intentionally falls canonical `COL_GREY` back to dark grey while preserving `COL_LGREY` as the brighter wall/UI grey.
- Doors: brown — interactive, stands out from walls
- Stairs: white — high importance navigation
- Player `@`: white — always visible
- Gold/stores: yellow — items of interest
- Monsters: color-coded by threat (green = low, yellow = moderate, red = high,
  relative to player level)
- Unlit/unknown tiles: black (not rendered)
- C128 VDC renderer invariant: `render_viewport` and `render_single_tile` must
  apply the same overlay precedence for items, monsters, glyphs, and player.
  Full redraws triggered by room reveal or modal restore are common enough that
  any drift between those paths becomes a live disappearing-entity bug.

### 9. Variable Monster Speed

Monster speed is preserved from the original — it is a core tactical mechanic.
Each creature type has a speed value: 0 = slow (moves every other player turn),
1 = normal (1:1 with player), 2 = fast (moves twice per player turn). The turn
sequencer (`turn.s`) manages speed counters. This adds minimal memory (1 byte
per creature template, 1 byte per active monster for the counter) but preserves
the important distinction between dangerous fast creatures and manageable slow
ones.

### 10. Sound Effects

Minimal SID sound effects provide gameplay feedback without music:
- Wall bump, melee hit, melee miss, item pickup, level-up, player death
- Simple waveform + ADSR envelope per effect, stateless (fire and forget)
- No background music — preserves the quiet tension of dungeon crawling

### 11. Monster Recall (Not Implemented)

Monster recall was planned to accumulate permanently across the entire game,
matching original Moria behavior. Per-tier recall files on disk would persist
knowledge across tier transitions. **This feature was deferred** — the
infrastructure for per-tier disk files and recall data structures was not
built. This is a missing feature tracked for future implementation.

---

## Build System

**Kick Assembler** via Makefile:

```bash
make            # Build main.s → out/moria.prg (+ tier PRGs)
make run        # Build and launch in VICE (x64sc)
make test       # Assemble + run all 19 test suites in VICE headless
make disk       # Create .d64 disk image with all files
make clean      # Remove build artifacts in out/
```

Override tool paths: `make KICKASS=/path/to/KickAss.jar VICE=/path/to/x64sc`

The `main.s` file uses `#import` directives to include all module files.
Creature tier data files are assembled separately as standalone PRGs
(`cr_tier1.s` through `cr_tier4.s`) and loaded at runtime.

Testing uses `run_tests.sh` which assembles each test, runs in VICE headless
with `-limitcycles`, and checks screen RAM at $0400+ for pass/fail bytes.

---

## Testing Strategy

Testing uses two complementary approaches:

**1. Assembly-time `.assert` directives** (62 asserts) — Kick Assembler's built-in
assertions validate constants, table sizes, memory layout, and compile-time
expressions during assembly. Run as part of every build with zero overhead.

```asm
.assert "tile type count", TILE_TYPE_COUNT, 16
.assert "map size", MAP_COLS * MAP_ROWS, 3840
.assert "program fits", program_end < CREATURE_BASE, true
```

**2. Runtime tests via VICE headless** (19 suites, 241+ tests) — Test programs
are assembled to `.prg`, run in VICE with `-limitcycles`, and `run_tests.sh`
verifies results by reading screen RAM at $0400+ for pass/fail bytes ($01=pass,
$00=fail) after BRK triggers.

```
tests/
├── test_rng.s              RNG distribution, range bounds (6 tests)
├── test_math.s             Multiply, divide, dice roll edge cases (16 tests)
├── test_memory.s           Bank switching read/write verification
├── test_player.s           Stat get/set, bonus lookups, level-up
├── test_dungeon.s          Room placement, connectivity, door placement (23 tests)
├── test_combat.s           Hit/miss, damage ranges, XP awards
├── test_monster.s          Monster spawning, creature types
├── test_monster_ai.s       AI movement, wake/sleep, speed
├── test_monster_attack.s   Monster melee, effect application
├── test_monster_magic.s    Monster spellcasting, bolt/breath
├── test_effects.s          Status effects, regen, Word of Recall (21 tests)
├── test_item.s             Item lifecycle, identification, enchant (40 tests)
├── test_wands_staves.s     Wand/staff charge tracking
├── test_store.s            Store buy/sell, pricing (17 tests)
├── test_save.s             Save/load RLE compression, checksum (10 tests)
├── test_score.s            Score calculation, high score table (10 tests)
├── test_tier.s             Creature tier loading, REU/disk paths (10 tests)
├── test_ranged.s           Ranged combat, ammo matching (8 tests)
└── test_los.s              Visibility calculations
```

**Bootstrap trampoline requirement:** Tests whose assembled code crosses $A000
must use a bootstrap trampoline (small stub at $080E that banks out BASIC ROM
before jumping to test_start). See `test_item.s` for the reference pattern.
`run_tests.sh` extracts the breakpoint address from the "Test Code" segment.

---

## Risk Register

| Risk | Impact | Mitigation |
|---|---|---|
| Dungeon generation too slow on 6502 | Player waits >5s on level change | Pre-compute room positions in table, minimize random calls, generate during stairs transition animation |
| Memory overrun | Crashes, corruption | Track allocation in spreadsheet, test with VICE memory monitor, enforce byte-level budgets for banked regions |
| Disk loading too slow on 1541 | Frustrating delays (33 sec stock for full tier change) | JiffyDOS or equivalent fastloader is **recommended** (see Design Decision #3). With JiffyDOS (~3–5 KB/sec), tier changes take 2–3 sec. REU path eliminates disk I/O entirely after startup. Minimize tier transitions via overlapping tier ranges. Standard KERNAL LOAD used as fallback for drives without JiffyDOS (slower but functional). |
| Game too hard without full spell set | Poor balance | Playtesting pass in Phase 9, adjust creature stats |
| PETSCII map unreadable | Poor UX | Iterate on tile characters, test on real hardware or accurate emulator, use color coding to differentiate elements |
| Runtime test flakiness | VICE cycle count too low/high for reliable BRK trigger | Tune `-limitcycles` per test, add fallback timeout. Use `.assert` for anything testable at assembly time. |
| Stack overflow from deep call nesting | Crash, corruption | 6502 stack is 256 bytes ($0100–$01FF). Deep chains (main→input→move→combat→effects→message→scroll) consume 3-6 bytes per level. Use flat state machine for monster AI loop (32 monsters per turn). Profile stack high-water mark in VICE. Target max 20 nesting levels. |
| ZP clobbered by KERNAL calls | Corrupted game state | Document KERNAL-volatile ZP locations in zeropage.s. Caller-save volatile ZP before KERNAL LOAD/SAVE/OPEN calls in tier_manager.s and save.s. |
| Save file write speed on 1541 | 10+ second save delay at stock speed | Expect 3–5 KB save file. Stock 1541 writes at ~300 bytes/sec (10–17 sec). With JiffyDOS write support, 2–4 sec. RLE compress map data. Warn player before save ("SAVING..."). Acceptable delay for infrequent operation. |

---

## Memory Usage Overview (Post-OPT-1, 2026-02-15)

After OPT-1.2–1.7 optimizations. `program_end` = $BF41. PRG file = 48,060 bytes.

### Code + Data Size

| Region | Address Range | Size | Notes |
|--------|--------------|------|-------|
| Main code+data | `$0801`–`$BF41` | 46,912 | Program image (code, tables, strings, static RAM) |
| Banked at `$F000` | `$F000`–`$F44C` | 1,101 | Special rooms, ego items, title sysinfo (under KERNAL ROM) |
| **Total code+data** | | **48,013** | |

### Runtime RAM Map

| Address Range | Size | Contents |
|--------------|------|----------|
| `$00`–`$01` | 2 | 6510 CPU port (hardware) |
| `$02`–`$8F` | 142 | Zero page: game state, pointers, scratch |
| `$90`–`$FF` | 112 | KERNAL zero page (volatile, caller-save) |
| `$0100`–`$01FF` | 256 | 6502 stack |
| `$0200`–`$03FF` | 512 | KERNAL buffers (input, file tables) |
| `$0400`–`$07FF` | 1,024 | Screen RAM (shared: display + BFS queue during dungeon gen) |
| `$0801`–`$BF41` | 46,912 | Main code + data |
| `$BF42`–`$C01F` | 223 | **Free** (headroom before CREATURE_BASE) |
| `$C000`–`$CEFF` | 3,840 | Dungeon map (64×60 tiles, always RAM) |
| `$CF00`–`$CFFF` | 256 | Floor item table (32 slots × 8 arrays) |
| `$D000`–`$DFFF` | 4,096 | I/O region (VIC-II, SID, CIA, color RAM) |
| `$E000`–`$EFFF` | — | KERNAL ROM (banked in by default) |
| `$F000`–`$F44C` | 1,101 | Banked code (copied here at startup, under KERNAL ROM) |
| `$F44D`–`$FFFA` | 2,989 | **Free** (banked region, available for expansion) |
| `$FFFB`–`$FFFF` | 5 | CPU vectors (NMI, RESET, IRQ) |

### Summary

| Metric | Value |
|--------|-------|
| Total code + data | 48,013 bytes (46.9 KB) |
| PRG file on disk | 48,060 bytes (47.0 KB) |
| Main region free | 223 bytes (`$BF42`–`$C01F`) |
| Banked region free | 2,989 bytes (`$F44D`–`$FFFA`) |
| Total free (expandable) | 3,212 bytes |
| RAM used (code+map+items+ZP+screen) | ~53 KB |
| Test suites | 20 (261 tests, all passing) |

---

## Code Banking Architecture — OPT-2 (2026-02-15)

**Context:** With 223 bytes of main region headroom and ~3KB free at `$F000`, the project cannot add significant new features without first moving infrequently-used code out of the main region. This section designs a phase-based overlay system that reclaims ~6.8KB from `$0801`–`$BFFF`.

### Key Insight: Game Phases

The game has four distinct phases where different code modules are active. Modules that only run in one phase are dead weight in every other phase.

| Phase | When | Active code | Dead weight |
|-------|------|-------------|-------------|
| **Startup** | Once | Title screen, char creation | Everything else |
| **Town** | Between dungeon trips | Stores, restocking | Creature tier data (tier 0 is embedded in `monster.s`!) |
| **Dungeon** | 95% of play | Combat, AI, spells, movement | Stores, char creation, title, score |
| **Death** | Once | Score, high scores, disk I/O | Everything else |

**Critical observation:** Town creatures (tier 0, indices 57-64) are always resident in `monster.s`. The `$E000`–`$EFFF` region used for creature tier data is **completely idle during town time**. This makes it available for store code overlays at zero cost.

### Three-Region Architecture

**Region 1: Main RAM (`$0801`–`$BF41`) — always resident**

Core gameplay that must be callable at all times: combat, monster AI, spells, spell effects, movement, dungeon gen/render, LOS, item logic, player state, math, screen routines, RNG, input, messages, turn management. No changes.

For spell and prayer book selection, prompt-time ownership is narrower than generic
inventory category ownership. The live selector must filter by exact book class before
showing letters or drawing the `?` overlay: mage flows may expose only mage books and
prayer flows may expose only prayer books. Late rejection after a broad `ICAT_BOOK`
prompt is not acceptable because it mislabels the visible selection range.

**Region 2: Permanent banked at `$F000` — always callable (via trampoline)**

Currently: special rooms (435 lines), ego items (214 lines), title sysinfo (84 lines). Total 1,101 bytes, 2,989 bytes free.

Expand with **gameplay UI screens** that are called during play but only on user keypress:

| Module | Lines | Est. bytes | Entry points |
|--------|-------|-----------|-------------|
| `ui_help.s` | 229 | ~280 | `ui_help_display` (string data in `ui_help_data.s`, main RAM) |
| `ui_character.s` | 395 | ~700 | `ui_char_display` |
| `ui_inventory.s` | 269 | ~500 | `ui_inv_display`, `ui_equip_display` |
| **Total** | 817 | ~1,600 | 4 trampolines |

These fit comfortably in the 2,989 free bytes. They can't be phase-overlayed because they're callable during both town and dungeon gameplay.

**Note:** `ui_help_clear_all` is used by multiple modules (help, character, inventory, store). It must either stay in main RAM or be duplicated. At ~20 bytes, keeping it in main RAM is simpler.

**Region 3: Phase overlays at `$E000`–`$EFFF` — swapped per game phase**

Four overlays share the same 4KB window, loaded at phase transitions:

| Overlay | Phase | Modules | Est. bytes | Entry points |
|---------|-------|---------|-----------|-------------|
| **Startup** | Game start | `title_screen.s` + `player_create.s` | ~1,600 | 2 (`title_load_and_draw`, `player_create`) |
| **Town** | In town | `store.s` + `ui_store.s` | ~2,300 | 4 (`store_init_all`, `store_restock_all`, `check_player_on_store_door`, `store_enter`) |
| **Dungeon** | In dungeon | Creature tier data (tiers 1-4) | ~2,500 | Existing `load_tier_to_buffer` path |
| **Death** | Game over | `score.s` | ~1,600 | 5 (`score_calculate`, `hiscore_load`, `hiscore_insert`, `hiscore_save`, `score_death_screen`) |

All overlays fit well within the 4KB window.

### Overlay Loading Mechanism

**REU path (expanded C64):** All overlays are stashed in REU at startup alongside creature tiers. Phase transitions use `reu_fetch` DMA — microseconds for a few KB, effectively instant.

**Disk path (stock C64):** Overlay PRGs loaded from disk via KERNAL LOAD on phase transition. Acceptable because:
- Startup overlay: loaded once before gameplay begins
- Town overlay: loaded when ascending to town (already a "loading moment" if coming from dungeon)
- Dungeon overlay: existing tier loading behavior (unchanged)
- Death overlay: loaded once at game over

**REU memory map (128KB minimum):**

| REU offset | Size | Contents |
|-----------|------|----------|
| `$00000`–`$009FF` | ~2.5KB | Creature tier 1 |
| `$00A00`–`$013FF` | ~2.5KB | Creature tier 2 |
| `$01400`–`$01DFF` | ~2.5KB | Creature tier 3 |
| `$01E00`–`$027FF` | ~2.5KB | Creature tier 4 |
| `$02800`–`$02DFF` | ~1.6KB | Startup overlay (title + char create) |
| `$02E00`–`$036FF` | ~2.3KB | Town overlay (stores) |
| `$03700`–`$03CFF` | ~1.6KB | Death overlay (score) |
| `$03D00`+ | ~113KB+ | Free (future: save state, undo, monster recall) |

### Trampoline Pattern for `$E000` Overlays

Same pattern as existing `$F000` trampolines. **Critical:** use the correct banking mode based on whether the banked code writes to screen/color RAM.

#### C64 PLA Banking Modes — `$01` Register Truth Table

| `$01` | Constant | `$A000` | `$D000` | `$E000` | Use case |
|-------|----------|---------|---------|---------|----------|
| `$34` | `BANK_NO_ROMS` | RAM | **RAM** (I/O hidden!) | RAM | Compute-only banked code (no screen writes) |
| `$35` | `BANK_NO_KERNAL` | RAM | **I/O** (color RAM!) | RAM | Screen-writing banked code (the sweet spot) |
| `$36` | `BANK_NO_BASIC` | RAM | I/O | KERNAL ROM | Normal game mode (KERNAL callable) |
| `$37` | `BANK_ALL_ROM` | **BASIC ROM** | I/O | KERNAL ROM | Dangerous — maps ROM over program code! |

**Key rule:** Color RAM at `$D800`–`$DBFF` is separate static SRAM on the VIC-II, only accessible when I/O is banked in at `$D000`–`$DFFF`. This requires `(HIRAM=1 OR LORAM=1)` — satisfied by `$35`/`$36`/`$37` but NOT `$34`. With `$34`, writes to `$D800` go to underlying DRAM, not VIC-II color SRAM. Title screen colors (or whatever was last in color RAM) persist.

**Two trampoline variants:**

```asm
// Screen-writing trampoline — uses $35 (I/O visible for color RAM)
tramp_ui_char_display:
    sei
    lda #BANK_NO_KERNAL         // $35 — RAM everywhere + I/O at $D000
    sta $01
    jsr ui_char_display         // at $F000+, writes to screen + color RAM
    jmp tramp_sr_epilogue       // restores $36, CLI, RTS

// Compute-only trampoline — uses $34 (slightly faster, no I/O needed)
tramp_score_calculate:
    sei
    lda #BANK_NO_ROMS           // $34 — all RAM (I/O not needed)
    sta $01
    jsr score_calculate         // at $E000+, no screen writes
    jmp tramp_sr_epilogue
```

**When to use which:**
- `$35` — any trampoline where the banked code writes to screen RAM (`$0400+`) or color RAM (`$D800+`), either directly or through screen.s helpers
- `$34` — compute-only trampolines (score calculation, ego roll/damage math, hiscore insert)

#### `input_get_key` Banking Safety

`input_get_key` is called from many banking contexts. It must use an explicit `lda #BANK_NO_BASIC` ($36), NOT `ora #%00000010` on the current `$01` value:
- Called from `$35` context: `ora #2` on `$35` = `$37` (BANK_ALL_ROM) — maps BASIC ROM at `$A000` over program code!
- Called from `$34` context: `ora #2` on `$34` = `$36` — happens to work, but fragile.
- Explicit `$36` is correct and safe from any context. It saves/restores original `$01` via PHA/PLA.

**KERNAL access from banked code:** Banked code cannot directly call KERNAL routines (ROM is banked out). Two solutions:

1. **`input_get_key` handles its own banking** — already saves/restores `$01`, sets `$36` internally, uses PHP/PLP to save I flag. Safe to call from any banked context.

2. **Existing main-RAM routines** — `screen_put_string`, `screen_put_char`, `rng_range`, `math_dice` etc. are custom code in main RAM, not KERNAL. These work without wrapping.

3. **Disk I/O** (score.s hiscore save/load) needs KERNAL. The death overlay trampoline restores `$36` before disk ops.

#### `$DD00` VIC-II Bank Restore After KERNAL I/O

KERNAL serial I/O uses CIA2 (`$DD00`) bits 3-5 for the serial bus, which can corrupt bits 0-1 that select the VIC-II 16KB bank. After any KERNAL LOAD operation, restore with:
```asm
    lda $dd00
    ora #%00000011              // Bits 0-1 = %11 → bank 0 ($0000-$3FFF)
    sta $dd00
```
This is done in `overlay.s`, `tier_manager.s`, and `title_screen.s` after KERNAL LOAD calls.

### Why Stores ARE Bankable

Store code is deeply integrated with gameplay systems but only through **function calls to main RAM**, not through shared state that must be simultaneously accessible:

- `screen_put_string`, `screen_put_char` — custom code in main RAM, always callable
- `inv_item_id[]`, `it_cost_lo[]` arrays — in main RAM, always readable
- `math_multiply`, `rng_range` — in main RAM
- `player_recalc_equipment` — in main RAM

The store code itself is orchestration logic and UI rendering. All data and utility routines it depends on stay in main RAM. The only KERNAL need is keyboard input (`input_get_key`), solved with one 15-byte wrapper.

Store entry is naturally gated by `zp_player_dlvl == 0` (town only), and `store_init_all` / `store_restock_all` are called at transition points where loading an overlay is expected.

### Freed Space Estimate

| What | Freed from main | Trampoline + wrapper cost | Net gain |
|------|----------------|--------------------------|----------|
| `player_create.s` → `$E000` overlay | ~1,200 | ~20 | ~1,180 |
| `title_screen.s` → `$E000` overlay | ~400 | ~20 | ~380 |
| `store.s` + `ui_store.s` → `$E000` overlay | ~2,300 | ~80 | ~2,220 |
| `score.s` → `$E000` overlay | ~1,600 | ~100 | ~1,500 |
| `ui_help.s` + `ui_character.s` + `ui_inventory.s` → `$F000` permanent | ~1,600 | ~60 | ~1,540 |
| **Total** | **~7,100** | **~280** | **~6,820** |

**Result:** Main region headroom goes from **223 bytes** to approximately **7KB free** — enough for significant new feature development (spells, haggling, throwing, group AI, artifacts, etc.).

### Modules NOT Recommended for Banking

| Module | Why it must stay resident |
|--------|-------------------------|
| `combat.s` | Core dungeon gameplay, called every turn |
| `monster_ai.s` / `monster_magic.s` / `monster_attack.s` | Core dungeon gameplay |
| `player_move.s` / `player_items.s` / `player_magic.s` | Core dungeon gameplay |
| `dungeon_gen.s` / `dungeon_render.s` / `dungeon_los.s` | Core dungeon gameplay |
| `spell_effects.s` | Called during dungeon combat |
| `item.s` | SoA tables read by many modules |
| `save.s` | Used in both town (save) and dungeon (save before quit). Could overlay, but touches ALL game state — high complexity, moderate payoff. Defer. |
| `turn.s` | Core game loop |

### Implementation Steps (OPT-2)

| Step | Description | Depends on |
|------|-------------|-----------|
| OPT-2.1 | **Overlay infrastructure.** Add `overlay_load` routine: REU DMA or disk LOAD to `$E000` based on `reu_present`. Track current overlay ID to skip redundant loads. Add KERNAL wrapper routines (`banked_get_key`, `banked_disk_io_*`) in main RAM. | — |
| OPT-2.2 | **REU overlay stash.** At startup, load all overlay PRGs (startup, town, death) and stash to REU alongside creature tiers. Define REU offset table. Non-REU path: overlay PRGs loaded from disk on demand. | OPT-2.1 |
| OPT-2.3 | **Move `ui_help.s` + `ui_character.s` + `ui_inventory.s` to `$F000`.** Add trampolines for 4 entry points. Keep `ui_help_clear_all` in main RAM. Update all call sites. | — |
| OPT-2.4 | **Move `player_create.s` to startup overlay at `$E000`.** Load overlay before `player_create` call. Add 1 trampoline. Title screen code can share this overlay. | OPT-2.1 |
| OPT-2.5 | **Move `store.s` + `ui_store.s` to town overlay at `$E000`.** Load overlay on ascent to town / game start. Add trampolines for 4 entry points. Gate `store_enter` trampoline on overlay-loaded check. | OPT-2.1 |
| OPT-2.6 | **Move `score.s` to death overlay at `$E000`.** Load overlay at death. Add trampolines for 5 entry points. Score disk I/O needs KERNAL wrappers. | OPT-2.1 |
| OPT-2.7 | **Disk image update.** Add overlay PRG files to .d64: `OVL.START`, `OVL.TOWN`, `OVL.DEATH`. Update Makefile to build overlays as separate PRGs. | OPT-2.4–2.6 |
| OPT-2.8 | **Testing.** Verify all overlay transitions: startup→town, town→dungeon, dungeon→town, death. Test both REU and non-REU paths. Add overlay-specific tests. | OPT-2.7 |

### Interaction with Existing Systems

- **Creature tier loading (unchanged in dungeon):** The dungeon phase uses `$E000` exactly as today — `tier_load` fetches tier data from REU/disk. No overlay infrastructure needed for this path; it's the existing behavior.
- **Town → dungeon transition:** Store overlay at `$E000` gets overwritten by `tier_load` when player descends. Natural and safe — store code isn't needed in dungeon.
- **Dungeon → town transition:** `tier_load` is skipped for dlvl=0 (tier 0 embedded). Load town overlay to `$E000` instead.
- **Word of Recall:** If recalling to town from deep dungeon, load town overlay. If recalling from town to dungeon, load appropriate tier.
- **`$F000` permanent code:** No interaction — `$F000` contents are independent of `$E000` overlays. Both regions can be banked simultaneously with `$01=$34` (compute-only) or `$01=$35` (screen-writing). Use `$35` whenever the banked code writes to screen/color RAM.

---

### 7. String Compression & String Banks

**Problem:** The game is nearly out of space for new text. The town overlay has 1 byte free,
main code area has ~3,722 bytes free ($B196-$C020), and the $F000 banked region has only
~292 bytes free ($FED6-$FFFA). Adding flavor text (shopkeeper insults, item descriptions,
monster recall, lore) requires a string infrastructure that can hold far more text than
currently fits in any single RAM region.

**Two-tier approach:**

**Tier 1 — Huffman compression in resident RAM (no disk I/O, no hardware requirements).**
Huffman-encode all game strings. The ~40-character uppercase alphabet compresses at ~50-60%,
effectively doubling the capacity of the ~3.7 KB free in main code. This alone provides
~6-7 KB of effective string capacity — enough for shopkeeper insults, haggling flavor,
additional combat messages, and moderate item descriptions. No disk loads, no REU, works on
every C64. This is the first thing to implement.

**Tier 2 — $E000 overlay string banks (when Tier 1 space is exhausted).**
For large-scale text expansion beyond what fits in resident RAM (monster recall, extensive
lore, full umoria dialog), store Huffman-compressed string banks on disk as loadable PRG
files. Two fetch paths: **REU** — all string banks preloaded to REU at startup alongside
creature tiers, DMA fetch on demand (~instant, no disk I/O). **Disk** — KERNAL LOAD from
d64 on demand (~1-2 sec per bank on 1541). Banks share the $E000 overlay region, so they
must coordinate with creature tier overlays.

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R7.1 | Huffman codec | **DONE** | `tools/huff_encoder.py` (offline encoder): reads text file, builds Huffman tree, emits Kick Assembler `.s` with tree tables + compressed bitstreams. `huffman.s` (6502 decoder): `huff_decode_string(X=id)` walks tree, outputs to `hd_decode_buf`. 55.6% compression ratio. Decoder ~80 bytes + 286 bytes data = ~438 bytes in main code area. |
| R7.2 | Resident compressed strings | **DONE** | `huffman_data.s` (generated) contains tree tables + compressed data in main code area. `huff_str_index` (16-bit offsets) + `huff_str_data` (byte-aligned bitstreams). First consumer: 15 store insult strings (367→204 bytes compressed). Infrastructure ready for additional string corpora. |
| R7.3 | Migrate store dialog strings | **DONE** | 15 umoria-sourced shopkeeper insult strings (`data/insult_strings.txt`) compressed via Huffman. Both buy-side and sell-side insult handlers in `ui_store.s` now call `rng_range` + `huff_decode_string` for random insults. Deleted `hg_insult_str`, freed 14 bytes in town overlay. |
| R7.4 | String bank format | **(TODO — Tier 2)** | Each bank is a loadable PRG file: header (string count, compressed data offset) + string index (16-bit offsets) + compressed bitstream. Banks sized to fit $E000-$EFFF (4 KB max compressed data per bank). Bank IDs assigned by content category: combat/UI, item descriptions, monster recall, etc. |
| R7.5 | String bank loader | **(TODO — Tier 2)** | `str_bank_load(bank_id)` — loads a string bank into $E000 overlay region. **REU path:** all string banks preloaded to REU at startup (alongside creature tiers), DMA fetch on demand (~instant). **Disk path:** KERNAL LOAD from d64 on demand. `str_current_bank` tracks loaded bank to avoid redundant loads. Must coordinate with creature tier overlay (both share $E000). |
| R7.6 | Migrate combat/UI strings | **DONE** | Migrated ~155 strings from 11 source files into Huffman-compressed storage. Net savings: 888 bytes in main code area (program_end $B196→$AE1E). Three migration patterns: A (zp_ptr0→msg_print), B (zp_ptr2→mon_atk_build_effect_msg), C (combat_append_str). New helpers: huff_decode_to_ptr2, huff_append_combat. |
| R7.6a | Follow-up resident ownership migrations | **DONE** | Later follow-up repairs moved additional live spell/save status text into the shared Huffman dictionary when raw literals started colliding with C128 overlay and staged-source ownership. Glyph-of-warding feedback and save/load status copy now use `HSTR_*` IDs instead of fragile resident `.text` blocks. |
| R7.6b | Prompt ownership discipline | **DONE** | Shared Huffman prompt helpers are for genuinely shared prompt contracts only. Narrow UX differences such as sparse all-item absolute-slot ranges stay caller-owned (`drop`), so prompt fixes do not bloat the shared resident/common path or destabilize the C128 staged-source ceiling. |
| R7.7 | Monster recall text | **(TODO — future, Tier 2)** | If monster recall is ever implemented, store descriptive text in a string bank. Each creature's recall text 30-80 bytes uncompressed, ~15-40 bytes compressed. 120 creatures × ~25 bytes avg = ~3 KB compressed — fits in one bank. |

**Space budget — Tier 1 (resident compressed strings):**

| Component | Location | Size |
|-----------|----------|------|
| Huffman decoder routine | Main code ($0801-$BFFF) | ~150-200 bytes |
| Huffman tree table | Main code | ~80-120 bytes (40-char alphabet) |
| `str_decode_buf` | Main code | ~80 bytes (max decoded string length) |
| **Infrastructure subtotal** | | **~310-400 bytes** |
| Compressed string data + index | Main code (remaining ~3.3 KB) | ~3,300 bytes |
| **Effective text capacity** | | **~6-7 KB uncompressed** |

**Space budget — Tier 2 (overlay string banks, when Tier 1 exhausted):**

| Component | Location | Size |
|-----------|----------|------|
| Bank loader + fetch API | Main code | ~100-150 bytes additional |
| Per string bank (disk/REU) | $E000 overlay | Up to 4 KB compressed per bank |
| Effective capacity per bank | | ~7-8 KB uncompressed text (at 55% ratio) |

**REU string cache layout** (when REU available, Tier 2):

| REU offset | Size | Content |
|------------|------|---------|
| $00000-$03FFF | 16 KB | Creature tiers 1-4 (existing) |
| $04000-$04FFF | 4 KB | String bank 0 (combat/UI) |
| $05000-$05FFF | 4 KB | String bank 1 (store dialog) |
| $06000-$06FFF | 4 KB | String bank 2 (item descriptions) |
| $07000-$07FFF | 4 KB | String bank 3 (monster recall) |

Minimum REU requirement: 32 KB (tiers + string banks). Any 1700/1750/1764 REU has at
least 128 KB — no constraint in practice.
