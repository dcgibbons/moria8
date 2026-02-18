# Moria C64/C128 — Build Plan

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

REU path: all 4 tiers preloaded at startup → DMA fetch on transition (instant).
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
main.s                    Entry point, BASIC stub, initialization, command dispatch
├── config.s              System detection (C64/C128), column mode selection
├── memory.s              Bank switching routines, memory map management
├── zeropage.s            Zero page variable declarations (with KERNAL-safe zones)
├── turn.s                Turn post-action (effects → hunger → regen → AI → turn counter)
│
├── screen.s              Screen output routines (40-col)
├── input.s               Keyboard input, command parsing
├── ui_status.s           Status bar rendering (3-line umoria-style)
├── ui_messages.s         Message line management (top of screen, "—more—" prompt)
├── ui_inventory.s        Inventory and equipment display screens
├── ui_character.s        Character info and spell list screens
├── ui_store.s            Store buy/sell UI screens
├── ui_help.s             Help screen overlay (22 lines of key bindings)
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
├── store.s               Store system (6 stores), pricing, restocking, category masks
├── spell_data.s          Spell/prayer data tables (32 spells, names, costs, levels)
├── spell_effects.s       Shared effect subroutines (bolt, heal, teleport, detect, etc.)
├── ranged_fire.s         Ranged combat (bow/crossbow/sling fire command, ammo matching)
│
├── save.s                Save/load game state to disk (RLE map compression, checksum)
├── score.s               Death screen, high score table, 24-bit score calculation
├── reu.s                 REU detection, DMA stash/fetch for tier data
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

## Phase Plan

### Phase 1 — Skeleton and Infrastructure ✅ COMPLETE

**Goal:** A program that boots on C64/C128, displays text, accepts input, and
can be tested.

| # | File | What it does | Tests |
|---|---|---|---|
| 1.1 | `main.s` | BASIC stub ($0801), SYS entry, save BASIC ZP state ($02–$8F) to buffer, disable BASIC ROM, call init, main loop. IRQ: keep the default KERNAL IRQ handler active (required for keyboard scanning used by GETIN in `input.s`). If a custom raster IRQ is needed later (e.g., for split-screen effects), chain it to the KERNAL handler via the saved vector. Clean exit: restore ZP state, re-enable BASIC ROM, RTS to BASIC warm start. Select unshifted character set mode (uppercase + graphics) at startup. | Boots in VICE, exits cleanly, BASIC works after exit, keyboard responsive |
| 1.2 | `config.s` | Detect C64 vs C128, detect 40/80 column mode, store machine type in ZP | Returns correct machine ID |
| 1.3 | `zeropage.s` | Define ZP variable locations for all modules using BASIC's freed space ($02–$8F). Document two zones: "safe" (never touched by KERNAL) and "volatile" (clobbered by KERNAL LOAD/SAVE/OPEN — $14–$15, $22–$25, etc.). Volatile ZP must be caller-saved around KERNAL calls in tier_manager.s and save.s. | Symbols resolve, no overlap, KERNAL-safe zones documented |
| 1.4 | `memory.s` | Bank switching macros: bank out BASIC ROM, bank out KERNAL ROM (with SEI/CLI protection), copy routines for banked RAM | Read/write behind ROM works |
| 1.5 | `screen.s` | Clear screen, print string at (row,col), print char, set colors, scroll message area. Uses direct screen memory writes (not KERNAL CHROUT) for performance. All output goes through a vector table (`put_char`, `put_string`, `clear_screen`, `set_color`) so the VDC 80-column backend can be swapped in for Phase 10 without changing callers. Overhead is ~6 cycles per indirect JMP — negligible. | Text appears correctly |
| 1.6 | `input.s` | Wait for keypress (KERNAL GETIN), key-to-command mapping table, handle direction keys. Numeric prefix for repeats deferred to Phase 6+. | Correct key codes returned |
| 1.7 | `rng.s` | 32-bit Galois LFSR seeded from CIA timer, `randByte` and `randRange` routines. A 16-bit LCG only has 65,536 states and produces noticeable repetition in dungeon generation; 32-bit LFSR has 4 billion states at ~20 cycles per call. | Statistical distribution test, no short-period repetition |
| 1.8 | `math.s` | 8x8→16 multiply, 16/8→8 divide, dice roll (NdS+B) | Boundary value tests |
| 1.9 | `turn.s` | Turn processing routines: `turn_post_action` (called by main loop after player actions) runs effect timers → hunger tick → increment turn counter → mark status dirty. Monster AI and regeneration added in Phase 5. Main loop in `main.s` handles command dispatch and rendering. | Turn post-action runs correctly |
| 1.10 | `sound.s` | Minimal SID sound effects: bump (wall collision), hit (combat), miss (combat), pickup (item), death (game over). Simple waveform + ADSR envelope per effect, no music. | Sounds play without disrupting gameplay timing |

**Deliverable:** Program boots, shows "MORIA" title, waits for a keypress, exits
to BASIC. All infrastructure routines have passing unit tests.

---

### Phase 2 — Player and Character Creation ✅ COMPLETE

**Goal:** Create a character with race, class, stats, and display the character
sheet.

| # | File | What it does | Tests |
|---|---|---|---|
| 2.1 | `tables.s` | Race stat modifiers (8 races x 6 stats), class data (6 classes), XP level thresholds (40 levels), stat bonus tables | Data integrity checks |
| 2.2 | `player.s` | Player struct in memory (~200 bytes), accessors for stats/HP/mana/gold/level, stat bonus lookups | Get/set round-trip |
| 2.3 | `player_create.s` | Race selection, stat rolling (umoria algorithm: 18 dice cycling d3/d4/d5, constrained total 43–54, each stat = 5 + 3 consecutive dice, race modifiers via incrementStat/decrementStat — see Stat Generation Deep Dive in Audit Review), class selection (filtered by race), name entry (max 16 chars, uppercase only — matches unshifted character set), initialize starting HP/mana/inventory. Order: race → stats → class → name (stat roll shows race-adjusted previews before class is chosen). | Full creation flow in VICE |
| 2.4 | `ui_character.s` | Character sheet display (name, race, class, stats, level, HP, mana, AC, gold), stat detail view | Screen output matches data |
| 2.5 | `ui_status.s` | Bottom status line: HP, mana, dungeon level, player level. Update on change only (dirty flag). | Status reflects player state |
| 2.6 | `ui_messages.s` | Top message line: display message, "—more—" prompt for overflow, message history buffer (last 8 messages) | Messages display, more works |

**Deliverable:** Player can roll a character, see their stats, and the status bar
and message system work.

---

### Phase 3 — The Town Level ✅ COMPLETE

**Goal:** Generate and display the town, move the player around it.

| # | File | What it does | Tests |
|---|---|---|---|
| 3.1 | `dungeon_gen.s` (town portion) | Generate town level: outer boundary walls, 6 store buildings (10x5 each with door), staircase to dungeon, open areas. Fixed layout (no RNG needed). | Town structure matches spec |
| 3.2 | `dungeon_render.s` | Tile-to-screen-code mapping table (see Screen Code table below), render visible portion of map to screen, handle 40-col viewport (38x20 game area with border), cursor positioning for player `@` symbol | Map renders correctly |
| 3.3 | `player_move.s` | 8-direction movement via HJKLYUBN (vi-keys) and cursor keys. Numpad keys 1–9 deferred to Phase 10 (C128 enhancements). Collision with walls, enter store door (triggers store screen), step on stairs. Running (auto-move in a direction until interrupted by obstacle, monster, or intersection) deferred to Phase 4.6 — requires dungeon corridors. | Movement works, walls block |
| 3.4 | `dungeon_los.s` | Simple town LOS: everything in town is lit and visible. Player position tracking, map reveal. (Full LOS in Phase 4.5.) | Visibility correct |

**Tile Mapping (40-column) — Screen Codes for Direct Memory Writes:**

These are **screen codes** (values poked directly into screen RAM at $0400+),
NOT PETSCII codes (which are different and used with KERNAL CHROUT). All
rendering uses direct screen memory writes for performance.

**Tile types (bits 7–4) — 16 codes, all used:**

| Type Code | Tile | Glyph | Screen Code | Color |
|---|---|---|---|---|
| 0 | Floor | `.` (period) | $2E | Dark grey ($0B) |
| 1 | Wall (horizontal) | `─` (horiz line) | $40 | Light grey ($0F) |
| 2 | Wall (vertical) | `│` (vert line) | $5D | Light grey ($0F) |
| 3 | Wall (corner TL) | `┌` | $70 | Light grey ($0F) |
| 4 | Wall (corner TR) | `┐` | $6E | Light grey ($0F) |
| 5 | Wall (corner BL) | `└` | $6D | Light grey ($0F) |
| 6 | Wall (corner BR) | `┘` | $7D | Light grey ($0F) |
| 7 | Door (open) | `'` | $27 | Brown ($09) |
| 8 | Door (closed) | `+` | $2B | Brown ($09) |
| 9 | Stairs down | `>` | $3E | White ($01) |
| 10 | Stairs up | `<` | $3C | White ($01) |
| 11 | Rubble | `:` | $3A | Grey ($0C) |
| 12 | Magma stream | `#` | $23 | Red ($02) |
| 13 | Quartz vein | `%` | $25 | White ($01) |
| 14 | Trap (visible) | `^` (up arrow) | $1E | Red ($02) |
| 15 | Secret door | (wall glyph) | (same as adjacent wall) | (same as wall, until found) |

**Rendering states (not tile types — derived from flags or context):**

| State | Glyph | Screen Code | Color | How determined |
|---|---|---|---|---|
| Player | `@` | $00 | White ($01) | Player position (always drawn on top) |
| Store (number) | `1`–`6` | $31–$36 | Yellow ($07) | Town gen marks floor tiles; renderer checks store table |
| Gold / floor item | `$` | $24 | Yellow ($07) | Bit 1 (treasure flag) set; renderer checks floor item table |
| Unknown/unseen | (not drawn) | — | Black (background) | Bit 2 (visited flag) = 0; tile type stored but not rendered |
| Monster | letter | varies | threat-coded | Bit 0 (creature flag) set; renderer checks active monster table |

**Screen code conversion note:** PETSCII and screen codes are different encodings.
For ASCII-range characters ($20–$3F), values are identical. For graphic characters:
PETSCII $A0–$BF → screen code = PETSCII − $40; PETSCII $C0–$DF → screen code =
PETSCII − $80. The values above are verified screen codes for the unshifted
character set. Do NOT use PETSCII values (e.g., $C0 for `─`) in direct screen
writes — $C0 as a screen code renders as reverse-video horizontal bar.

**Character set mode:** The game uses **unshifted mode** (uppercase + graphics
characters). This provides the box-drawing characters needed for walls but means
all text is uppercase only. This matches the retro feel and is standard for C64
games. The character set is selected at startup in `main.s` via the $D018
register. No custom character set is loaded.

**Color palette:** Colors are written to color RAM ($D800+) alongside screen
codes. The palette above improves readability by distinguishing structural
elements (grey walls), interactive elements (brown doors, yellow stores), and
the player (white). Monster colors are defined in Phase 5 — threat-coded by
depth relative to player level.

**Deliverable:** Town level renders, player walks around with `@`, bumps into
walls, store numbers visible, stairs visible.

---

### Phase 4 — Dungeon Generation and Navigation ✅ COMPLETE

**Goal:** Generate dungeon levels and navigate between them.

| # | File | What it does | Tests |
|---|---|---|---|
| 4.1 | `dungeon_gen.s` (full) | Room-and-corridor generation for dungeon levels. 80x48 map. Place N rooms (4–8 for simplicity), connect with tunnels, add doors, place stairs (2 down, 1 up), add mineral streamers. Room types: basic rectangle + overlapping. | Rooms connected, stairs present |
| 4.2 | `dungeon_features.s` | Door open/close/lock/jam logic, trap placement (6 types: pit, arrow, gas, teleport, dart, rockfall), staircase level transitions, secret door detection | Traps trigger correctly |
| 4.3 | `tier_manager.s` + `reu.s` | ✅ **COMPLETE** (implemented as R3.5). Creature tier data loaded from disk via KERNAL LOAD or REU DMA on tier boundary crossings. `tier_check_transition` detects boundary; hysteresis via overlapping tier ranges prevents thrashing. REU path: all tiers preloaded at startup, DMA fetch on transition (near-instant). Disk path: KERNAL LOAD on each transition. Graceful fallback to embedded creatures if no d64. | 10 automated tests in test_tier.s |
| 4.4 | `dungeon_render.s` (viewport) | Viewport scrolling for 80x48 map on 38x20 screen. Panel movement when player nears edge. Draw only changed tiles (dirty tile tracking). | Viewport scrolls correctly |
| 4.5 | `dungeon_los.s` (full) | Hybrid LOS matching original Moria behavior: lit rooms reveal fully when player enters (check room membership, not per-tile rays). Dark corridors reveal only adjacent tiles. Bresenham ray casting reserved for specific checks (ranged attacks, bolt spells in Phase 7) — not used for general visibility, as per-tile ray casting is too expensive at 1 MHz for every player move. Torch/lamp extends corridor visibility to light-radius adjacent tiles. | LOS matches expected pattern |
| 4.6 | Player movement updates | Walking into darkness, falling in pits, hitting traps, going up/down stairs transitions. Searching reveals secret doors (1-in-6 base). Running: auto-move in a direction until interrupted by wall, intersection, visible monster, or item on floor. Running is essential QoL for traversing explored corridors. | Transitions work, running stops at obstacles |

**Deliverable:** Multi-level dungeon with rooms, corridors, doors, traps, and
lighting. Player can descend and ascend.

---

### Phase 5 — Monsters ✅ COMPLETE

**Goal:** Monsters appear, move, and can be fought.

| # | File | What it does | Tests |
|---|---|---|---|
| 5.1 | `monster.s` | Active monster table (up to 32 simultaneous — reduced from 125 for C64 RAM). Spawn routine: pick creature type appropriate to depth, place in valid empty tile. Monster display characters. | Monsters spawn at correct depth |
| 5.2 | `monster_ai.s` | Monster movement: awake/sleep check (noise radius), greedy step toward player, confused wandering, wall-phasing for ghosts. Variable speed: each creature type has a speed value (1 = normal, 2 = fast/moves twice per player turn, 0 = slow/moves every other turn). The turn sequencer (`turn.s`) checks speed counters and calls AI accordingly. Speed is a core tactical mechanic — fast hounds are dangerous because they outrun you, slow molds are manageable because you can kite them. | Monsters approach player, fast monsters move twice per turn |
| 5.3 | `combat.s` | Melee attack: blow count from table (dex x weight ratio), to-hit roll (d20 + bonuses vs AC), damage roll (weapon dice + str bonus). Kill awards XP, check level-up. | Damage/kill/XP correct |
| 5.4 | `monster_attack.s` | Monster melee: up to 4 attacks per creature, damage types (normal, poison, stat drain, gold theft, item theft). Attack messages. Player death check. | Attacks deal correct damage |
| 5.5 | `turn.s` (effects) | Status effect application and timers: poison tick, blindness (hide map), confusion (random movement), paralysis (skip turns), regeneration (HP/mana per turn based on CON). | Timers decrement, effects apply |
| 5.6 | `dungeon_render.s` (monsters) | Show monster characters on map. Monster visibility (only in LOS and lit). Monsters blink or highlight on attack. | Monsters visible when expected |

**Deliverable:** Monsters wander the dungeon, attack the player, the player can
fight back. Status effects work. Combat is functional.

---

### Phase 6 — Items and Inventory ✅ COMPLETE

**Goal:** Items can be found, carried, equipped, used, and dropped.

| # | File | What it does | Tests |
|---|---|---|---|
| 6.1 | `item.s` | Item SoA tables (55 types) + inventory data structure: 22 carried slots + 8 equipment slots. Floor item table (32 slots at $CF00). Add/remove/stack operations. | Add/remove/stack correct |
| 6.2 | `ui_inventory.s` | Display inventory list (letter-indexed a–v), equipment list, item detail view. 40-column formatting with scrolling for overflow. | Display matches contents |
| 6.3 | `player_items.s` | Equip/remove/drop/pick-up commands. Wear/wield calculates AC and to-hit changes. Cursed items cannot be removed. Eat food (hunger system: full → hungry → weak → fainting → dead). | Equip changes stats |
| 6.4 | Item generation | Floor item spawning during dungeon gen. Gold pile generation. Treasure rooms. Chest contents. Item enchantment rolling (+1 to +N based on depth). | Items spawn at correct depth |
| 6.5 | Item identification | Unidentified items show generic name ("a blue potion"). Identify scroll/spell reveals true name. "Tried" status after first use. Scroll/potion/wand color randomization per game. | ID progression works |

**Deliverable:** Full item lifecycle — find, pick up, identify, equip, use, drop.
Hunger system functional.

---

### Phase 7 — Magic System ✅ COMPLETE

**Goal:** Mages cast spells, priests pray, scrolls/potions/wands work.

| # | File | What it does | Tests |
|---|---|---|---|
| 7.1 | `player_magic.s` | Spell/prayer book display, learn new spells on level-up, cast spell (mana cost, failure chance based on level+INT/WIS), spell cooldown. 16 mage spells + 16 priest prayers (reduced from 31 each). | Cast succeeds/fails correctly |
| 7.2 | Spell effects | Implement each spell: magic missile, light area, detect monsters, phase door, fireball, teleport self, identify, cure poison, cure wounds, bless, remove curse, etc. | Each effect works |
| 7.3 | Scrolls/potions | Use item → apply effect → consume item. 20 scroll types, 20 potion types (reduced). Effects overlap spell system where possible (share subroutines). | Items consumed, effects apply |
| 7.4 | Wands/staves | Directional targeting for wands (aim in 8 directions). Staves affect area. Charge tracking. | Charges decrement |
| 7.5 | `monster_magic.s` | Monster spellcasting: breath weapons (damage = current HP fraction), bolt spells, summoning, teleport player, blindness, confusion. Check range, check LOS. | Monsters cast when in range |

**Deliverable:** Full magic system for both player and monsters.

---

### Phase 8 — Stores ✅ COMPLETE

**Goal:** Town stores buy and sell items.

| # | File | What it does | Tests |
|---|---|---|---|
| 8.1 | `store.s` | 6 stores with inventory (12 items each — reduced from 24). Store owner data (name only — race and max gold deferred, see RP14-2/RP14-5). Inventory restocking on town re-entry. (Design deviation: original Moria restocks based on game turns elapsed, not on re-entry. Simplified for implementation; acceptable because the net effect is similar — stores refresh between dungeon visits.) | Stores stock correct items |
| 8.2 | `ui_store.s` | Store screen: list items with prices, buy/sell interface. Simplified haggling (accept/decline at offered price, no multi-round bidding — optional enhancement later). Store entry detected via `check_player_on_store_door` at `!post_move:` in main loop. Sell flow uses sub-screen to show full 22-slot player inventory. | Buy/sell transactions work |
| 8.3 | Price calculation | Base price × charisma modifier only (race modifier deferred, see RP14-2). Buy: `base_price × chr_price_adj[CHR-3] / 100` (100-130%). Sell: `base_price × chr_sell_adj[CHR-3] / 100` (25-50%). Uses `math_mul_16x8` (16×8→24-bit multiply, added to `math.s`) and existing `math_div_16x8`. | Prices match formula (17 tests) |

**Implementation details:**
- **New files:** `store.s` (474 lines — data, restock, pricing, gold ops), `ui_store.s` (~500 lines — entry detection, screen rendering, buy/sell flows), `tests/test_store.s` (17 runtime tests)
- **Modified files:** `main.s` (imports + 3 hooks: init, restock on ascend, door check at post_move), `math.s` (added `math_mul_16x8`), `tables.s` (added `chr_sell_adj` 16-byte table), `run_tests.sh` (added store suite)
- **Store inventory:** SoA layout — `si_item_id`, `si_qty`, `si_p1`, `si_flags` (72 slots = 6 stores × 12). Category matching via 16-bit bitmasks (`store_cat_mask_lo/hi`).
- **Restocking:** `store_init_all` at game start; `store_restock_all` on stair ascent to town. Each empty slot has 50% chance to stock. Item selection via rejection sampling (`rng_range(45)+2`, check category, max 30 retries, fallback table).
- **Branch distance issues:** Several routines required `bcc/jmp` patterns and subroutine extraction to stay within 6502's ±128 byte relative branch limit.
- **math_multiply clobbers X:** `math_mul_16x8` saves X in `mul_saved_x` before first `math_multiply` call.
- **Test framework note:** Data bytes after `brk` shift segment end address, breaking `run_tests.sh` VICE breakpoint detection. All scratch data must be placed before `brk`. (See RP14-6.)
- **Verification:** `make build` → 57 asserts, 0 failed. `make test` → 13/13 suites pass (186 total tests, store 17/17).

**Deliverable:** Player can buy equipment and sell loot in town.

---

### Phase 9 — Save/Load and Game Polish ✅ COMPLETE

**Goal:** Game state persists across sessions. Death and scoring work.

| # | File | What it does | Tests |
|---|---|---|---|
| 9.1 | `save.s` ✅ | Save game: write player struct, current dungeon map, active monsters, floor item table, inventory, current tier recall data, game flags to sequential file on disk. Compress map (RLE on tile bytes). Estimated save size: ~3–5 KB. | Save and reload match, all floor items and monsters persist |
| 9.2 | Load game ✅ | Load from disk, validate file integrity (checksum), **delete savefile immediately after successful load** (before resuming play — this enforces permadeath and prevents save-scumming via machine reset), restore all state, resume play. | Game resumes correctly, savefile gone |
| 9.3 | Death and scores ✅ | Death screen with killer info. High score table (top 10, stored on disk). Score = XP + gold + depth bonus. | Scores persist |
| 9.4 | Game polish ✅ | PETSCII title screen (disk-loaded art), HP calculation bug fix (race HD), starting equipment (dagger, leather armor, spellbook), RP15 store fixes. | Title displays, HP correct, equipment works |

**9.1/9.2 Implementation details:**
- **New files:** `save.s` (~1,120 lines — KERNAL I/O, RLE compress/decompress, save/load orchestration, checksum, recount routines), `tests/test_save.s` (10 runtime tests: RLE round-trips, checksum, recount_monsters, recount_floor_items)
- **Modified files:** `main.s` (bootstrap trampoline, exit trampoline, CMD_SAVE dispatch, title screen New/Load menu, load_resume_game, death handler delete, program_end assert), `input.s` (SHIFT+S → CMD_SAVE), `ui_help.s` (SHIFT+S SAVE in help screen), `memory.s` (CREATURE_BASE $A100→$AB00), `dungeon_gen.s` (BFS_QUEUE_MAX 3840→2650), `player.s` (light_radius in sync_from_zp), `run_tests.sh` (added save suite)
- **Save file format:** Binary sequential file "MORIA.SAV" on device 8. ~4,100 bytes: magic header, player struct, ZP game state, RNG state, inventory, id_known, shuffle tables, store inventory, stairs, rooms, traps, monster table, floor items, RLE-compressed map, 16-bit additive checksum.
- **RLE compression:** Literal packets (header < $80, len = header+1) and repeat packets (header >= $80, len = header−$7D). Workspace at CREATURE_BASE ($AB00). Output bounds check prevents corrupt data from overwriting FLOOR_ITEM_BASE.
- **Memory safety:** Bootstrap trampoline at $080E banks out BASIC ROM before entry. Exit trampoline in low RAM banks BASIC ROM back in safely. CREATURE_BASE must be past program_end (compile-time assert). check_savefile_exists uses separate file number (3) to avoid KERNAL file table conflict with load_game (file 2).
- **Test framework fix:** Tests with BRK above $A000 can false-trigger during BASIC ROM execution in VICE autostart. test_save.s splits into "Test Code" (bootstrap + finish with BRK at $0824) and "Test Body" (imports + logic) segments.
- **Verification:** `make build` → 61 asserts, 0 failed. `make test` → 14/14 suites pass (save: 10/10). See Review Pass 16 for post-implementation fixes.

**9.3 Implementation details:**
- **New files:** `score.s` (~988 lines — 24-bit math, score calculation, death screen, high score table insert/display, disk I/O for MORIA.HI), `tests/test_score.s` (10 runtime tests: math_add_24, math_cmp_24, score_calculate, hiscore_insert empty/ordering/overflow, screen_put_decimal_24)
- **Modified files:** `zeropage.s` (renamed `zp_eff_spare` → `zp_death_source`), `config.s` (death source constants DEATH_ALIVE/CURSED/POISON/STARVE), `monster_attack.s` (+2 lines: set death source from `mat_type2`), `monster_magic.s` (+4 lines: set death source from `zp_mon_type` for bolt/breath), `turn.s` (+4 lines: set death source for poison/starvation), `player_items.s` (+2 lines: set death source for poison potion), `main.s` (import score.s, replaced death handler with score flow), `memory.s` (CREATURE_BASE $AC00→$B200), `dungeon_gen.s` (BFS_QUEUE_MAX 2560→1792), `run_tests.sh` (added score suite)
- **Death source tracking:** `zp_death_source` ($5F, in ZP save range) encodes killer identity: $00=alive, $01–$FC=monster creature type index (→ cr_name_lo/hi for name), $FD=cursed item, $FE=poison, $FF=starvation. Set at each death source before `player_death_check`.
- **Score formula:** `score = XP(24-bit) + gold(24-bit) + max_depth × 50`. Uses `math_multiply` (8×8→16) for depth bonus, then 24-bit addition.
- **Death screen:** 40×25 layout: title, player name/race/class/level, dungeon depth, death source ("KILLED BY A KOBOLD" / "POISON" / "STARVATION" / "A CURSED ITEM"), XP/gold/depth bonus/total score breakdown, high score table with new entry highlighted, "PRESS ANY KEY".
- **High score table:** 10 entries × 23 bytes (16-byte name, 3-byte score LE, level, depth, race, class). File format: 4-byte header ("MH" + version $01 + count) + entries. Sequential file "MORIA.HI" on device 8. Scratch-and-rewrite on save.
- **Memory optimization:** `hiscore_table` (230 bytes) placed at CREATURE_BASE instead of in program image — safe because BFS/RLE (gameplay) and hiscore (game over) never overlap temporally. This kept program_end ($B191) within the raised CREATURE_BASE ($B200).
- **Verification:** `make build` → 62 asserts, 0 failed. `make test` → 15/15 suites pass (score: 10/10).

**Deliverable:** Complete, playable game loop from title screen through death
and high scores.

---

### Phase 10 — C128 Enhancements

**Goal:** Take advantage of C128 hardware when available.

| # | What | Details |
|---|---|---|
| 10.1 | 80-column mode | VDC-based rendering for 80x25 display. Larger viewport (78x20). Full-width status bar. **Note:** The VDC has its own 16 KB RAM accessed only through register ports ($D600/$D601) — screen memory is NOT directly addressable. Every character write requires a multi-step register sequence (set address high, set address low, write data). This is architecturally different from VIC-II direct screen pokes and effectively requires a **second rendering backend**, not just wider output. Design screen.s with an abstract interface from Phase 1 so the VDC renderer can be swapped in. |
| 10.2 | Extended memory | Use C128's 128 KB to hold all creature/item tiers simultaneously — no disk loading between levels. |
| 10.3 | Larger dungeon | With more RAM, expand dungeon to 120x80 or larger. More rooms, more monsters (up to 64 active). |
| 10.4 | Enhanced display | Use VDC attributes for color-coded monsters (red = dangerous, green = easy). Reverse video for walls. |

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
- Doors: brown — interactive, stands out from walls
- Stairs: white — high importance navigation
- Player `@`: white — always visible
- Gold/stores: yellow — items of interest
- Monsters: color-coded by threat (green = low, yellow = moderate, red = high,
  relative to player level)
- Unlit/unknown tiles: black (not rendered)

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

## Audit Review — Phases 1–3 Implementation

Code review performed against this plan after Phases 1–3 were implemented.
Findings are categorized as bugs, plan deviations, and minor issues.

### Bugs

| # | Severity | File | Issue |
|---|---|---|---|
| A1 | High | `screen.s:91-96` | **`screen_clear` writes 24 bytes past screen RAM.** The second fill loop (`SCREEN_RAM + $300 + x` starting at `x=$E8`) writes to $07E8–$07FF, which is past the end of screen RAM ($07E7). The first loop already covers all 1000 bytes via the `$2E8` offset. The second loop is both redundant and out-of-bounds. Same issue exists for the color RAM fill. Fix: delete the second loop entirely. |
| A2 | High | `dungeon_gen.s:45-46` | **Flag bit assignment swapped vs. plan.** Code defines `FLAG_HAS_ITEM=$01` (bit 0) and `FLAG_OCCUPIED=$02` (bit 1). Plan specifies bit 0 = creature, bit 1 = treasure. No runtime impact in Phase 3 (flags not checked yet), but Phase 5 (monsters) and Phase 6 (items) will read the wrong bits. Fix: either swap the constants in code or update this plan to match the code. |
| A3 | Medium | `input.s:85-96` | **Numeric prefix parsing is broken.** `input_get_command` detects `CMD_REPEAT` but discards the digit value and loops back to `!get_key` without accumulating anything. Comment says "TODO: implement in Phase 3" but Phase 3 is complete. Plan 1.6 lists this as a Phase 1 deliverable. Fix: implement digit accumulation or remove the feature from Phase 1 scope and defer explicitly. |
| A4 | Low | `player_create.s:706` | **"CHOOSE (A-" prompt is incomplete.** The string `create_choose_str` ends with `A-` and a null terminator — the closing range letter and `)` are never appended. Displays as `CHOOSE (A-` for both race and class selection. Fix: dynamically append the final letter and closing paren after the string, or use separate prompt strings per screen. |
| A5 | Medium | `player.s` (player_calc_stats) | **Stat modifiers may be clamped prematurely between race and class additions.** If the intermediate result after adding the race modifier is clamped to 3–18 before the class modifier is added, edge cases produce wrong results. Example: base=17, race=+3, class=-3 → sequential clamping gives 15 (17→20→18→15) instead of correct 17 (17+3-3=17). Current tests use base=10 and don't hit this case. Fix: sum all modifiers first, then clamp once. |
| A6 | High | `dungeon_render.s` / `main.s` | **Full viewport redraw on every move causes visible input lag.** `render_viewport` redraws all 760 tiles (38x20) on every movement keypress, even though typically only 2 tiles changed (old and new player position). Per-tile cost is ~80-120 cycles (map read, flag check, 4x LSR, two table lookups, player position check, `check_store_door` JSR with 6-entry linear scan, screen+color RAM writes), totaling 60,000-90,000 cycles (~3-5 frames). Fix: implement dirty tile rendering — only update changed tiles on move; reserve full redraw for viewport scroll and screen transitions. |
| A7 | High | `input.s` / `main.s` | **Keyboard buffer not flushed before input poll causes key stacking.** While `render_viewport` runs for 3-5 frames, the KERNAL IRQ continues scanning the keyboard and queuing keypresses into the buffer at `$0277` (count at `$C6`). When `input_get_command` calls GETIN, it immediately dequeues stale buffered keys, triggering another full redraw, which buffers more keys — a snowball effect. Fix: flush the keyboard buffer (`lda #0 / sta $c6`) before polling for input. |

### Plan Deviations

| # | Area | Plan Says | Code Does | Resolution Needed |
|---|---|---|---|---|
| D1 | Character creation order (2.3) | Race → class → stats → name | Race → stats → class → name | Decide: update plan or reorder code. Current order means stat rolling screen shows race-adjusted stats but not class-adjusted stats. |
| D2 | Movement keys (3.3) | Vi-keys + number keys 1–9 (numpad) | Vi-keys + cursor keys only | Add numpad mapping to `key_map_petscii`/`key_map_cmd` tables, or defer numpad to Phase 10 (C128 enhancements) and update plan. |
| D3 | Store building size (3.1) | 6 stores, 4x3 each | 6 stores, 10x5 each (`STORE_W=10, STORE_H=5`) | The 10x5 stores are more proportional on the 80x48 map. Update plan to match code if intentional. |
| D4 | Turn sequencer usage (1.9) | `turn.s` drives the game loop | `main.s` dispatches commands directly, calls `turn_post_action` | `turn_execute` and its phase structure are dead code. Either refactor main loop to use the sequencer or simplify `turn.s` to match actual usage. |
| D5 | Food timer | Not specified in plan | Starting food = 200, hungry at 150 = only 50 turns before hunger warning | Original Moria food lasts thousands of turns. 50 turns is extremely aggressive. Either increase starting food significantly (e.g., 2000+) or adjust thresholds. |

### Minor Issues

| # | File | Issue |
|---|---|---|
| M1 | `player_create.s:653-656` | Dead code: `create_init_character` sets player position to (20,12), but `town_generate` (called after in `main.s`) overwrites it to (39,24). Remove the dead assignment. |
| M2 | `tests/*.s` | No `.mon` monitor scripts exist. The testing strategy section of this plan says each test `.s` file has a corresponding `.mon` script for VICE headless execution. The 4 test files cannot run as specified without these scripts. |
| M3 | `tests/test_memory.s` | Does not track overall pass/fail in `$02` like the other test files do. Convention requires `$02 = $01` for all-pass, `$02 = $00` for any-fail. |
| M4 | `screen.s:83-89` | The first fill loop in `screen_clear` has a 24-byte overlap: `SCREEN_RAM+$200` writes $0600–$06FF, and `SCREEN_RAM+$2E8` writes $06E8–$07E7, overlapping at $06E8–$06FF. Harmless but wasteful. Could restructure as 3 full pages + a partial 232-byte fill. |

### Status

- **Phases 1–3 implemented and audited:** 21 source files, 4 test files

**Bug fixes applied:**

| # | Status | Resolution |
|---|---|---|
| A1 | **Fixed** | `screen_clear` rewritten: 3 full pages + 232-byte partial fill. No overlap, no OOB write. |
| A2 | **Fixed** | Flag bits swapped to match plan: `FLAG_OCCUPIED=$01` (bit 0), `FLAG_HAS_ITEM=$02` (bit 1). Header comment in `dungeon_gen.s:16-17` also updated to match. |
| A3 | **Fixed** | Broken `CMD_REPEAT` handling removed. Numeric prefix explicitly deferred to Phase 6+. `input_get_command` now skips unknown keys cleanly. Dead `CMD_REPEAT` constant and stale header comment cleaned up. |
| A4 | **Fixed** | Added `put_choose_suffix` helper. Race prompt now shows "CHOOSE (A-H)", class prompt shows "CHOOSE (A-X)" with correct final letter. |
| A5 | **Not a bug** | Code already sums both modifiers before clamping — no intermediate clamp exists. Added clarifying comment documenting the valid range (sum -8 to 28, no 8-bit wrap). |
| A6 | **Fixed** | Implemented dirty tile rendering: on player move without viewport scroll, only old and new player tiles are redrawn. Full viewport redraw reserved for scroll, screen transitions, and initial render. |
| A7 | **Fixed** | Keyboard buffer flushed (`sta $c6`) before input polling in `input_get_command`. |

**Plan deviation resolutions:**

| # | Status | Resolution |
|---|---|---|
| D1 | **Plan updated** | Creation order is race → stats → class → name. This lets the stat roll screen show race-adjusted previews, and the class screen filters by race. Intentional. |
| D2 | **Deferred** | Numpad mapping deferred to Phase 10 (C128 enhancements). Cursor keys + vi-keys sufficient for C64. |
| D3 | **Plan updated** | Stores are 10x5 tiles, intentional for 80x48 map proportions. Plan section 3.1 should read "10x5 each". |
| D4 | **Fixed** | Removed dead `turn_execute` and phase constants from `turn.s`. Module now provides `turn_post_action` (called by main loop) plus tick subroutines. Dead ZP allocations `zp_turn_phase` ($42) and `zp_turn_state` ($4F) reclaimed as spare slots in `zeropage.s`. |
| D5 | **Fixed** | Starting food increased from 200 to 2000 turns. Hunger thresholds unchanged (hungry at 150, weak at 50, faint at 10). |

**Minor issue resolutions:**

| # | Status | Resolution |
|---|---|---|
| M1 | **Fixed** | Removed dead position assignment (20,12) from `create_init_character`. Position set by `town_generate`. |
| M2 | **Deferred** | `.mon` scripts for VICE headless tests deferred — manual VICE testing used for now. |
| M3 | **Deferred** | `test_memory.s` pass/fail convention fix deferred to test infrastructure pass. |
| M4 | **Fixed** | Addressed with A1 — `screen_clear` no longer has overlap or OOB writes. |

### Stat Generation Deep Dive (QA Review)

Investigation into why character rolling never produces stats above 16, even for
races with large positive modifiers (e.g., Half-Troll STR +4, Elf INT +2).

**Finding S1 — Wrong dice algorithm (HIGH)**

| Aspect | Umoria (correct) | Before fix | After fix |
|--------|------------------|------------|-----------|
| Dice pool | 18 dice cycling d3, d4, d5 | 6 independent `math_dice(3,6,0)` calls | d3+d4+d5 per stat |
| Per-stat formula | 5 + three consecutive dice (one d3 + one d4 + one d5) | 3d6 | 5 + d3 + d4 + d5 (range 8–17) |
| Raw stat range | 8–17 | 3–18 | 8–17 |
| Total constraint | Re-roll all 18 dice if sum < 43 or sum > 54 | None | Re-roll if total not in 73–84 |
| Distribution shape | Tight, correlated across stats (total constrained) | Independent, wide variance per stat | Constrained, tight distribution |

**Status: FIXED.** Dice algorithm rewritten in `player_create.s`.

**Finding S2 — Wrong race/class modifier application (CRITICAL)**

This is the root cause of the user-reported defect.

Umoria does NOT use simple addition for modifiers. Each +1 or −1 is applied as a
separate call to `incrementStat()` / `decrementStat()`:

```
incrementStat(stat):
    if stat < 18:       stat += 1
    if stat 18–87:      stat += randomNumber(15) + 5   // adds 6–20
    if stat 88–107:     stat += randomNumber(6) + 2    // adds 3–8
    if stat > 107:      stat += 1

decrementStat(stat):
    if stat > 108:      stat -= 1
    if stat 88–108:     stat -= randomNumber(6) + 2
    if stat 19–88:      stat -= randomNumber(15) + 5
    if stat > 18:       stat = 18
    if stat > 3:        stat -= 1
```

Internal encoding: values 3–18 stored as-is; 19–118 = 18/01 through 18/100.

**Example**: Half-Troll STR modifier +4, base STR 16:
- Umoria: 16 → 17 → 18 → 18/(06–20) → 18/(12–40). Easily reaches 18/30+.
- Old code: `min(16 + 4, 18) = 18`. Could never reach 18/xx.

**Example**: Elf INT modifier +2, base INT 17:
- Umoria: 17 → 18 → 18/(06–20). Reaches 18/06–18/20.
- Old code: `min(17 + 2, 18) = 18`.

**Status: FIXED.** `increment_stat`/`decrement_stat` implemented in `player.s` with
umoria's exact randomized step logic. `apply_modifier` loops through each ±1.
`player_calc_stats` and `create_calc_modified_stat` both use the new system.

**Finding S3 — 18/xx support too limited (HIGH)**

`tables.s` line 7 says: *"For C64 simplicity, we cap stats at 18 (no 18/xx
percentile stats)."* This conflicts with faithful umoria behavior:

| Aspect | Umoria | Before fix | After fix |
|--------|--------|------------|-----------|
| Stats that support 18/xx | All six (STR, INT, WIS, DEX, CON, CHR) | STR only (via `PL_STR_EXTRA`) | All six stats |
| How 18/xx is reached | Race/class modifiers via incrementStat | Only if base die roll is exactly 18 | Via increment_stat during modifier application |
| Player struct fields | Single uint8_t per stat (3–118 encoding) | Separate base + extra byte (STR only) | Single byte per stat (3–118 encoding) |
| Display support | All stats show 18/xx | Only STR shows 18/xx (`ui_character.s`) | All stats via `put_stat_val` |

**Status: FIXED.** `PL_STR_EXTRA` removed (now `PL_SPARE_63`). Single-byte encoding
(3–118) for all stats. `put_stat_val` simplified to take A only (no Y param).
`ui_character.s` updated. `stat_bonus_index` caps at index 15 for 18/xx stats.

**Finding S4 — PRNG algorithm is acceptable (OK)**

The 32-bit Galois LFSR (polynomial $ED, period 2^32−1) with rejection sampling
in `rng_range` is adequate for game use. CIA timer seeding provides reasonable
initial entropy. No changes needed.

**Required code changes (all resolved):**

| # | Change | Status |
|---|--------|--------|
| 1 | Replace 3d6 with umoria's constrained multi-die system | **Fixed** — `player_create.s` rolls d3+d4+d5 per stat (+5), total constrained 73–84 |
| 2 | Implement `increment_stat` / `decrement_stat` | **Fixed** — Added to `player.s` with umoria's randomized step logic |
| 3 | Extend 18/xx support to all six stats | **Fixed** — Single-byte encoding (3–118), `PL_STR_EXTRA` removed, `ui_character.s` + `put_stat_val` updated |
| 4 | Remove "cap at 18" constraint from `tables.s` | **Fixed** — Header comment updated |
| 5 | Update plan Phase 2.3 | **Fixed** — Phase 2.3 now describes correct umoria algorithm |

### Dungeon Generation Deep Dive (QA Review)

Investigation of persistent dungeon generation bugs including rooms with no exits,
incorrect algorithm vs. umoria, build breakage, and zero test coverage. Compared
against actual umoria source (`src/dungeon_generate.cpp`, `src/dungeon_tile.h`,
`src/config.cpp`).

#### Finding DG1 — Build is broken (BLOCKER)

`dungeon_gen.s` references three undefined symbols:
- `trap_count` (lines 99, 404) — not allocated anywhere
- `place_traps` (line 418) — subroutine doesn't exist
- `place_secrets` (line 419) — subroutine doesn't exist

These are forward references to Phase 4.2 features. The code cannot assemble.
Must be stubbed out to restore a buildable state.

#### Finding DG2 — Connectivity algorithm is fundamentally wrong (CRITICAL)

**The reported bug** (rooms with no exits) traces directly to the corridor
connection algorithm. The current code connects consecutive rooms (room 0→1,
1→2, 2→3, etc.) in the order they were placed. This is a **linear chain**
that does NOT guarantee all rooms are reachable if any corridor fails to connect.

**Umoria's approach:**
1. Place rooms into a 6x6 grid (typically 24-28 rooms)
2. **Randomly shuffle** the room location list
3. Connect room[0]→room[1]→...→room[N]→room[0] as a **circular chain**
   (Hamiltonian cycle), guaranteeing every room has at least 2 connections
4. The tunnel algorithm uses a biased random walk toward the destination with
   up to 2000 iterations, ensuring it reaches the target even through winding
   paths

**Current code issues:**
- Only 4-8 rooms (vs. umoria's ~24-28) — fewer rooms means longer corridors
  between non-adjacent rooms, increasing failure risk
- Rooms are connected in placement order, not shuffled — rooms placed far apart
  in the grid may have extremely long tunnel distances
- No circular chain — room 0 has only 1 connection (to room 1), making it
  vulnerable to disconnection
- L-shaped corridors (fixed 2-segment paths) can fail if the path crosses
  multiple rooms — the corridor carver stops at the first perpendicular wall
  it hits and places a door, but the corridor segment terminates without
  reaching the target room's interior
- The current algorithm has NO concept of reaching the destination — it just
  carves to the target coordinate. If another room's wall is in the way, the
  corridor dead-ends at a door in that room's wall, leaving the intended
  destination room disconnected

**Root cause of the screenshot bug:** When connecting rooms A and B with an
L-shaped corridor, if room C sits between them, the horizontal segment hits
C's vertical wall and places a door there. The corridor segment ends at room B's
x-coordinate but that coordinate is inside room C, not room B. Room B gets
no connecting corridor.

#### Finding DG3 — Room placement algorithm differs from umoria (HIGH)

| Aspect | Umoria | Current code |
|--------|--------|-------------|
| Grid system | 6x6 grid of slots, ~32 attempts → ~24-28 rooms | No grid; random placement with overlap rejection |
| Room count | Mean 32 attempts into 36 slots | 4-8 rooms (rng(5)+4) |
| Room sizing | Width: 2-22 interior, Height: 2-7 interior | Width: 4-11, Height: 3-7 |
| Room types | Normal, overlapping rectangles, inner rooms, cross-shaped | Basic rectangle only |
| Unusual rooms | Level/300 chance per room | None |
| Level dimensions | 66x198 | 80x48 |

The 80x48 map with 4-8 rooms is a reasonable C64 simplification, but the room
count is too low and the placement algorithm creates pathological layouts where
rooms cluster or spread too far apart.

#### Finding DG4 — Tunnel algorithm differs from umoria (HIGH)

| Aspect | Umoria | Current code |
|--------|--------|-------------|
| Path finding | Biased random walk toward target, 2000 iteration limit | Fixed L-shaped (2-segment) path |
| Direction changes | 70% chance to redirect toward target, 1/9 random | None — always horizontal then vertical or vice versa |
| Wall penetration | Marks adjacent granite as TMP2_WALL to prevent clustered entries | No tracking — can place multiple doors in adjacent wall tiles |
| Room wall handling | Records wall crossings for later door placement | Inline door placement during carving |
| Robustness | 2000-iteration walk guarantees reaching target even through complex geometry | Can dead-end when another room blocks the L-path |

#### Finding DG5 — Door placement differs from umoria (MEDIUM)

| Aspect | Umoria | Current code |
|--------|--------|-------------|
| Room entry doors | 25% chance at tunnel-granite intersection; rest become corridor floor | Always places closed door on perpendicular room wall |
| Corridor intersection doors | Placed at tunnel-corridor crossings (15% chance) after all tunnels | Not implemented |
| Door types | 1/3 open (3/4 normal, 1/4 broken), 1/3 closed (plain/stuck/locked), 1/3 secret | Always closed |
| Wall detection | Uses FLAG_LIT to distinguish room walls from rock | Same — correct |

#### Finding DG6 — Streamer generation order is wrong (MEDIUM)

Current code comment says: *"Streamers BEFORE corridors ensures corridors
always overwrite mineral veins they cross."* The actual call order is:

```
place_streamers     // line 413 — BEFORE connect_rooms
connect_rooms       // line 415 — after streamers
```

But umoria does it the opposite way:
1. Build tunnels (corridors)
2. Fill empty space with TILE_GRANITE_WALL
3. **Then** place streamers

Umoria places streamers AFTER tunnels and granite fill, which means streamers
can overwrite corridor floor tiles (creating obstacles). The current code places
streamers before tunnels, so corridor carving will overwrite streamer tiles —
meaning streamers never create obstacles in corridors. This is actually more
player-friendly but differs from umoria.

Additionally, umoria places 3 magma + 2 quartz streamers (5 total). Current
code places 1 + 50% chance of a second (1-2 total).

#### Finding DG7 — Stairs placement differences (MEDIUM)

| Aspect | Umoria | Current code |
|--------|--------|-------------|
| Down stairs count | 3-4 (randomNumber(2)+2) | 2 |
| Up stairs count | 1-2 (randomNumber(2)) | 1 |
| Placement criteria | Random floor tile with >= 3 adjacent walls (degrades) | Random floor tile in specified room |
| Wall adjacency check | Yes — prefers corner-like positions | No — any interior floor tile |

#### Finding DG8 — fill_map_rock uses wrong fill tile (LOW)

`fill_map_rock` fills with `TILE_WALL_H` ($10, "horizontal wall"). Umoria
fills with `TILE_NULL_WALL` (0), then converts to `TILE_GRANITE_WALL` (12) after
tunnels are carved. The current code uses a concrete wall type for uncarved rock,
which means:

1. The corridor carver's LIT-flag check (`and #FLAG_LIT / beq = rock`) works
   correctly because unlit TILE_WALL_H distinguishes rock from room walls
2. But all 6 wall types ($10-$60) share the same "is this a wall?" semantic,
   which is fragile — the code relies on the LIT bit rather than tile type
   to distinguish rock from structure

Umoria uses the type value itself (>= MIN_CAVE_WALL=12) to identify walls vs.
open space. A dedicated "rock" tile type would be cleaner but the current
approach works.

#### Finding DG9 — DUNGEON_FLAGS marks all rooms as lit+visited (LOW) — RESOLVED

Originally `DUNGEON_FLAGS = FLAG_LIT | FLAG_VISITED` ($0C), baking full
visibility into every tile at generation time. **Fixed in Phase 4.5:**

- `DUNGEON_FLAGS = FLAG_LIT` ($08) — rooms start lit but NOT visited
- Corridors start with NO flags (invisible until the player's torch reveals them)
- `dungeon_los.s` implements three-state visibility: unseen → visible → remembered
- `darken_rooms` strips FLAG_LIT from dark rooms (umoria formula: lit if dlvl <= rng(25)+1)
- `update_visibility` sets FLAG_VISITED via torch radius (Phase A) and room reveal (Phase B)
- Rendering dims remembered tiles (FLAG_VISITED but outside torch and not FLAG_LIT) to dark grey

#### Finding DG10 — Zero test coverage for dungeon generation (HIGH)

No `test_dungeon.s` exists. Dungeon generation is the most algorithmically
complex part of the codebase and has the most edge cases. The following tests
are needed:

**Room placement tests:**
- `check_room_overlap` returns correct results for overlapping and non-overlapping rooms
- `check_room_overlap` handles ROOM_GAP correctly
- Rooms never placed outside map boundary (x >= 4, y >= 4, x+w <= 76, y+h <= 44)
- `draw_dungeon_room` writes correct wall/floor tiles and flags
- Room count never drops below 2 after retry exhaustion

**Corridor tests:**
- `carve_h_corridor` carves floor from cx1 to cx2 (both directions)
- `carve_v_corridor` carves floor from cy1 to cy2 (both directions)
- Corridor through room wall places door (not floor)
- Corridor through rock places floor (not door)
- Single-tile corridor (cx1 == cx2) handled correctly
- L-shaped corridor reaches both endpoints

**Connectivity tests:**
- Every room has at least one floor tile adjacent to a corridor or door
- Player start position is on a walkable tile
- All stairs are on walkable tiles
- Pathfinding from player start to each staircase succeeds (BFS/flood-fill)

**Streamer tests:**
- Streamers don't overwrite room floor tiles
- Streamers don't overwrite doors or stairs
- Streamer bounds checking works (doesn't write outside map)

**Stairs tests:**
- `verify_stairs` re-places overwritten stairs
- Stairs placed inside room interiors (not on walls)
- Up-stairs and down-stairs in different rooms

**Integration test:**
- Generate 100+ dungeons, verify all pass connectivity flood-fill
- No room is fully enclosed (every room reachable from player start)

#### Summary of required changes

| # | Priority | Change | Status |
|---|----------|--------|--------|
| 1 | BLOCKER | Stub out `trap_count`, `place_traps`, `place_secrets` to restore buildability | **Fixed** — `dungeon_features.s` implements traps and secrets |
| 2 | CRITICAL | Rewrite connectivity algorithm: shuffle rooms, connect as circular chain | **Fixed** — Fisher-Yates shuffle + circular chain in `connect_rooms` |
| 3 | HIGH | Add flood-fill connectivity verification after generation; re-generate if unreachable | **Fixed** — BFS `verify_connectivity` with max 10 retries |
| 4 | HIGH | Create `test_dungeon.s` with room placement, corridor, and connectivity tests | **Fixed** — 23 runtime tests covering rooms, corridors, connectivity, doors, visibility, dark rooms |
| 5 | MEDIUM | Add door type variety (open/closed/secret per umoria probabilities) | **Fixed** — 50/50 open/closed at junctions; `place_secrets` enabled in Phase 4.6 (1-3 secret doors per level) |
| 6 | MEDIUM | Increase streamer count to match umoria (3 magma + 2 quartz) | **Fixed** — 5 streamers (3 magma + 2 quartz) |
| 7 | MEDIUM | Add wall-adjacency check for stairs placement | **Fixed** — `random_wall_adj_floor` with degrading threshold (>=3, >=2, >=1, any) |
| 8 | LOW | Consider increasing room count range (e.g., 6-12) for better dungeon density | Deferred |
| 9 | LOW | Add dark room support (defer LIT flag to Phase 4.5 LOS implementation) | **Fixed** — `room_lit[]` array, `darken_rooms` post-processing, umoria formula |

**Additional fixes applied during QA:**

| # | Issue | Resolution |
|---|-------|------------|
| DG-A | Corridors adjacent to rooms without doors | **Fixed** — `add_corridor_doors` iterates per-room-wall (max 1 door per wall side) |
| DG-B | Secret doors at corridor junctions block passage | **Fixed** — `random_door_type` produces only open/closed for door placement; `place_secrets` converts 1-3 closed doors to TILE_SECRET per level (Phase 4.6) |
| DG-C | Room overlap detection off-by-one | **Fixed** — `check_room_overlap` uses ROOM_GAP correctly |

---

## Known Bugs

Playtesting bugs BUG-1 through BUG-18 have been fixed (see Review Pass 15). BUG-19 through BUG-29 fixed individually.

| # | Description | Status |
|---|-------------|--------|
| BUG-1 | 18 stat inflating to 18/99 | ✅ Fixed — exceptional strength gated to STR only |
| BUG-2 | Status bar layout mismatch | ✅ Fixed — rewritten to 3-line umoria-style |
| BUG-3 | No townspeople | ✅ Fixed — 6 town creature types added |
| BUG-4 | Town render speed / store doors | ✅ Fixed — render_store_doors post-pass |
| BUG-5 | Direction/diagonal key mapping | ✅ Fixed |
| BUG-6 | Store exit requires ESC | ✅ Fixed — Q key added |
| BUG-7 | Doors auto-open | ✅ Fixed — closed doors block movement |
| BUG-8 | Sound effects broken | ✅ Fixed — sound_init added to main.s |
| BUG-9 | Player '@' drawn as blank | ✅ Fixed — missing jmp (fall-through bug) |
| BUG-10 | Look command | ✅ Fixed — direction scanning implemented |
| BUG-11 | Town creature provocation | ✅ Fixed — MF_PROVOKED flag |
| BUG-12 | Spell books | ✅ Fixed (side-effect bugs RP15-1/2 also resolved) |
| BUG-13 | (folded into BUG-12) | ✅ Fixed |
| BUG-14 | KERNAL GETIN clobbers X in name entry | ✅ Fixed — cen_count byte |
| BUG-15 | Debug hardcoded name | ✅ Fixed — removed |
| BUG-16 | Store screen clearing | ✅ Fixed — ui_help_clear_all |
| BUG-17 | Look command distance | ✅ Fixed — multi-tile scan |
| BUG-18 | Inventory popup in selection dialogs | ✅ Fixed — '?' key added |
| BUG-19 | Garbage characters flash on screen when descending to dungeon level 1 | **Fixed** — resolved by VIC-II bank restore (`$DD00 ora #3`) after KERNAL serial I/O in OPT-2 display bug fixes (223bb1e). KERNAL LOAD corrupted $DD00 bits 0-1, causing VIC-II to read wrong memory bank. |
| BUG-20 | Dead strings `mat_acid_str` and `mat_dead_str` in monster_attack.s (42 bytes wasted) | ✅ Fixed — inline strings eliminated by R7.6 Huffman migration; acid message now lives in Huffman dictionary, `mat_dead_str` was never referenced and is gone. |
| BUG-21 | Acid attack effect (`mon_atk_effect_acid`) is a no-op with no message | ✅ Fixed — prints "SPITS ACID ON YOU" via mon_atk_build_effect_msg (pre-R7.6), now Huffman-compressed. |
| BUG-22 | `mat_the_str` duplicates `cmb_the_str + 1` (5 bytes wasted) | ✅ Fixed — OPT-1.7 eliminated the duplicate; R7.6 Huffman migration removed all remaining inline strings from monster_attack.s. |
| BUG-23 | Magic Missile spell does not work — no animation and no damage to monsters | **Fixed** — `eff_bolt` damage math was correct but had zero user feedback: no messages, no animation, no monster wake-up, no sound. Added: bolt `*` animation along trace path with save/restore, hit/kill/fizzle messages using combat_msg_buf, `MF_AWAKE` on non-lethal hit, `SFX_HIT` on hit. |
| BUG-29 | Secret doors on vertical walls render as '─' instead of '│' | ✅ Fixed — old heuristic checked tiles above/below for wall types, failed when neighbors were doors or carved floor. Replaced with left/right floor check: vertical wall doors have floor on both sides (room + corridor), horizontal wall doors have wall tiles beside them. Also saves ~40 bytes. |

---

## Current State (2026-02-16)

**All core phases complete.** The game is fully playable from title screen through dungeon exploration, combat, magic, stores, save/load, death, and high scores. Ranged combat (R1.1) added. OPT-1 code size optimizations applied (excluding OPT-1.1).

### Phase Completion Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Skeleton and Infrastructure | ✅ Complete |
| 2 | Player and Character Creation | ✅ Complete |
| 3 | The Town Level | ✅ Complete |
| 4 | Dungeon Generation and Navigation | ✅ Complete |
| 5 | Monsters | ✅ Complete |
| 6 | Items and Inventory | ✅ Complete |
| 7 | Magic System | ✅ Complete (steps 7.0-7.10) |
| 8 | Stores | ✅ Complete |
| 9 | Save/Load and Game Polish | ✅ Complete (9.1-9.4, BUG-1 through BUG-18 fixed) |
| R3.5 | Creature Tier System + REU | ✅ Complete (R3.5.1-R3.5.12, 120 creatures across 5 tiers) |
| R1.1 | Ranged Combat | ✅ Complete — bows, crossbows, slings, 3 ammo types, fire command, ammo stacking |
| R3.4 | Monster Fleeing | ✅ Complete — flee threshold (HP/4) at spawn, reversed greedy movement |
| R2.1 | Special Rooms | ✅ Complete — pits, vaults, nests with $F000 banking |
| R4.1 | Ego Items | ✅ Complete — 7 enchanted weapon types with slay/elemental/AC bonuses |
| OPT-1 | Code Size Optimization | ✅ Complete — 182 bytes reclaimed (OPT-1.1 resolved by R7.6) |
| R7 | String Compression (Tier 1) | ✅ Complete — R7.1-R7.3, R7.6 done. 155 strings Huffman-compressed, 888 bytes saved. Tier 2 (R7.4-R7.5) deferred. |
| 10 | C128 Enhancements | Not started |

### Build Stats

- **Test suites:** 21 (263 runtime tests)
- **Compile-time asserts:** 67
- **Source files:** ~42 .s files
- **Program size:** $B4E8 (program_end), CREATURE_BASE at $C020 — **2,872 bytes headroom**
- **PRG file:** 44,266 bytes (43 KB on disk)

### Known Remaining Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| MC4.1 | LOW | No player critical hit system | **Fixed** — `combat_critical_blow` in combat.s implements umoria `playerWeaponCriticalBlow` (2-5x damage based on weapon weight/tohit/class/level) |
| RP15-4 | LOW | BUG-18 re-entry after inventory popup skips state re-validation | **Resolved** — documented in show_inv_and_restore comment; overlay is read-only |
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |
| MC2.3 | LOW | Only uses cr_xp_lo (8-bit XP); will need 16-bit for high-tier creatures | **Fixed** — combat_award_xp now uses 16×8→24-bit multiply with cr_xp_hi:cr_xp_lo; generalized ccl_div_24x8 shared with levelup |
| BUG-19b | **HIGH** | XP awards too generous — player levels up too quickly on low dungeon levels | **Fixed** — experience factor (race_xp% + class_xp%) was never applied to thresholds; now computed at character creation (PL_EXPFACT) and used in combat_check_levelup via 16×8→24-bit multiply + div-by-100 |
| BUG-23 | **HIGH** | Players still level up too fast despite BUG-19b fix — XP economy not matching umoria | **Fixed** — root cause: missing XP halving on multi-level gain. Umoria halves excess XP above each new threshold on level-up; we preserved full XP, allowing cascading (e.g., 150 XP: 1→7 without halving vs 1→4 with). Audit confirmed cr_xp values and xp_level thresholds match umoria exactly. |
| BUG-20 | LOW | ~~Dead string `mat_dead_str` wastes 21 bytes~~ | ✅ Fixed — eliminated by R7.6 Huffman migration |
| BUG-21 | LOW | Acid attack effect is a no-op (no player message) | **Fixed** — prints "SPITS ACID ON YOU" via mon_atk_build_effect_msg |
| BUG-22 | LOW | ~~`mat_the_str` duplicates `cmb_the_str + 1`~~ | ✅ Fixed — OPT-1.7 |
| BUG-24 | **HIGH** | Huffman decoder 8-bit overflow for string IDs >= 128 | **Fixed** — `huff_decode_string` used `txa; asl; tax` for word index, but `asl` overflows for IDs >= 128 (e.g., 154 → offset $34 instead of $134). 27 strings (128-154) decoded wrong text. Fixed with carry-based page branching. |
| BUG-25 | MED | Inventory commands (Wear, Cast, etc.) show all items instead of filtering to applicable ones | **Fixed** — Added `uinv_filter` variable to `ui_inventory.s`. `show_inv_and_restore` accepts filter in A: `$FF`=all (drop, throw, 'I'), `$FE`=wearable (wear), or exact `ICAT_*` match (quaff=potion, read=scroll, aim=wand, use=staff, study=book). Takeoff uses new `show_equip_and_restore` to show equipment instead. ~66 bytes. |
| BUG-26 | MED | -MORE- prompt placement and frequency feels unnatural on 40-column display | **Fixed** — Expanded message area from 1 row to 2 rows (rows 0-1). Messages fill row 0 then row 1; -MORE- only triggers when a 3rd message arrives while both rows are occupied, roughly halving -MORE- frequency. -MORE- positioned at end of row 1 message. Viewport shrunk from 20 to 19 rows (VIEWPORT_Y=2, VIEWPORT_H=19). |
| BUG-27 | MED | Spell casting animation/combat happens while spell list overlay is still displayed | **Fixed** — After player selects a spell letter in `pm_do_cast`, the dungeon screen is restored (`ui_help_clear_all` + viewport + render + status) before any mana/level checks or spell effect dispatch. Bolt animations, damage messages, and error messages now appear on the dungeon screen. Cancel (ESC/space) still handled by main.s `screen_clear`. ~16 bytes. |
| BUG-28 | MED | XP still too generous at low levels — single kills can cause 1-2 level jumps | **Fixed** — Capped `combat_check_levelup` at 1 level-up per kill by replacing the recursive `jmp combat_check_levelup` with `rts`. Excess XP is still halved and retained, so the player levels again on the next kill if still above threshold. Root cause: spawn window [dlvl-2, dlvl+3] allows cr_level 3-4 creatures at DL 1, and XP formula `(cr_xp * cr_level) / player_level` amplifies rewards when cr_level >> player_level. Saves 2 bytes. |
| OPT-1 | MED | ~~Code size optimization~~ — 182 bytes reclaimed (OPT-1.2–1.7), OPT-1.1 resolved by R7.6 | ✅ Done |
| OPT-2 | MED | ~~Phase overlay code banking~~ — `$E000` overlays + `$F000` UI screens, ~6.8KB freed. Display bugs from incorrect banking ($34→$35) fixed. | ✅ Done |

### What's Next

Priority order based on AUDIT review (see Audit Response below):

| Priority | # | What | Effort |
|----------|---|------|--------|
| ~~1~~ | A1 | ~~File naming cleanup~~ — ✅ THE.GAME, HALL.OF.FAME, MONSTER.DB.1-4 | Done |
| ~~2~~ | A2 | ~~Directory art~~ — ✅ PETSCII title card in d64 directory listing | Done |
| ~~3~~ | A5 | ~~Stack depth audit (trace deep call chains)~~ — ✅ Max 27 bytes (11%), safe | Done |
| ~~4~~ | A3 | ~~Character disk strategy (separate game/save disks)~~ — ✅ Dual-disk mode with swap prompts | Done |
| ~~5~~ | R3.4 | ~~Monster fleeing at low HP~~ — ✅ Flee threshold (HP/4) at spawn, reversed greedy movement | Done |
| ~~6~~ | R2.1 | ~~Special rooms (vaults, pits, nests)~~ — ✅ Pits, vaults, nests with $F000 banking | Done |
| ~~7~~ | R4.1 | ~~Ego items~~ — ✅ 7 enchanted weapon types with slay/elemental/AC bonuses | Done |
| ~~8~~ | OPT-1 | ~~Code size optimization~~ — ✅ 182 bytes reclaimed ($BFF7→$BF41), 20/20 tests pass | Done |
| ~~9~~ | OPT-2 | ~~Code banking~~ — ✅ Phase overlays at `$E000` + permanent `$F000` expansion. ~6.8KB freed. Display bugs fixed (color RAM, input banking, filesystem naming). | Done |
| ~~10~~ | R5.1/R5.2 | ~~Spell expansion~~ — ✅ All 32 effects implemented. 8 spellbooks (4/class), book-gated learning, books not consumed. +101 bytes. | Done |
| ~~11~~ | R6.1 | ~~Store haggling~~ — ✅ Multi-round buy/sell haggling with insult/kick system. CHR affects markup. Items ≤10 GP use simple Y/N. Number input, 4-round negotiation, gap/step convergence. +1479 bytes in town overlay ($E000-$EF47). | Done |
| ~~12~~ | R7.1-R7.2 | ~~Huffman codec + resident compressed strings (Tier 1)~~ — ✅ 155 strings, 888 bytes saved (program_end $B196→$AE1E) | Done |
| ~~13~~ | R7.3 | ~~Store dialog strings~~ — ✅ 15 shopkeeper insults compressed via Huffman | Done |
| ~~14~~ | R7.6 | ~~Combat/UI string migration~~ — ✅ 155 strings from 11 source files, 3 migration patterns | Done |
| **15** | R7.4-R7.5 | Overlay string banks + REU cache (Tier 2 — when Tier 1 space exhausted) | Medium |
| **16** | A4 | Separate binaries (BOOT.PRG + MORIA64 + MORIA128) | Major (Phase 10) |

**Lower priority content** (tracked but not scheduled):
~~R1.2 Throwing~~ ✅, ~~R3.2 Group tactics~~ ✅, ~~R3.3 Breeders~~ ✅, ~~R4.4 Pseudo-ID~~ ✅, ~~R6.2 Black Market~~ ✅, ~~R6.3 Player Home~~ ✅

**Phase 10 — C128 Enhancements** (not started):

| # | What | Summary |
|---|------|---------|
| 10.1 | 80-column VDC mode | Second rendering backend for VDC 80x25 display |
| 10.2 | Extended memory | C128 128KB MMU bank-switch path (no disk tier loading) |
| 10.3 | Larger dungeon | Expand map to 120x80+, more rooms, up to 64 active monsters |
| 10.4 | Enhanced display | VDC color attributes for threat-coded monsters |

---

## Audit Response (2026-02-14)

Full review of AUDIT.md findings. Each item is categorized as **done**, **action item**, **tracked TODO**, or **deferred**.

### AUDIT §1 — Feature Comparison

| Finding | Disposition |
|---------|------------|
| Map size (48x80 vs 66x198) | **Deferred** — intentional C64 constraint. Phase 10.3 expands for C128. |
| Monster count (120 vs 351) | **Done** — R3.5 expanded to 120 across 5 tiers. Further expansion possible with more tier data. |
| Item count (55 vs 400+) | **Tracked** — R4.1 (ego items) addresses this. 55 base types is adequate for C64 memory. |
| Active monsters cap (32) | **Deferred** — RAM constraint. Phase 10.3 raises to 64 on C128. |
| Haggling simplified | **Done** — R6.1 implemented multi-round haggling with insult/kick system. |
| ~~Missing stores (Black Market, Player Home)~~ | **Done** — R6.2 Black Market + R6.3 Player Home implemented. |
| Character history | **Deferred** — nice-to-have, not gameplay-critical. |
| Save scumming prevention | **Done** — save file deleted on load, enforcing permadeath. |

### AUDIT §2 — Bugs in Implemented Features

| Finding | Disposition |
|---------|------------|
| Input lag (viewport redraw) | **Done** — fixed with dirty render (render_local_area). Verify in playtesting. |
| Key stacking (keyboard buffer) | **Done** — fixed. |
| Monster AI stack depth | ✅ **Done (A5)** — Audited. Deepest chain: monster_ai_tick → monster_attack_player → mon_atk_effect_confuse → msg_print → screen_put_string (14 JSR levels, 27 bytes = 11% of stack). 224 bytes free. No canary needed. |
| screen_clear memory safety | **Done** — fixed (ui_help_clear_all pattern). |
| Item generation distribution | **Action item A7** — review spawn curves vs umoria. Low priority, informational. |

### AUDIT §3 — Code Quality

| Finding | Disposition |
|---------|------------|
| Numeric prefix parsing | **Deferred** — not needed for core gameplay. |
| Phase 10 TODOs | **Tracked** — Phase 10 plan exists. |
| ~~Missing stores~~ | ~~**Tracked** — R6.2, R6.3.~~ **Done** — R6.2 Black Market + R6.3 Player Home implemented. |
| Spellbook expansion | **Tracked** — R5.2. |
| Room placement grid logic | **Deferred** — random placement works; grid would need significant rework. |
| Large files (dungeon_gen.s, item.s) | **Action item A6** — split opportunistically when touching these files. Low priority. |
| Magic numbers / hardcoded values | **Deferred** — adding symbolic constants everywhere would be nice but is low-impact on a stable codebase. Address incrementally. |

### AUDIT §4 — Product Quality / Playability

| Finding | Disposition |
|---------|------------|
| 40-column display | **Deferred** — fundamental hardware limit. Phase 10.1 adds 80-col on C128. |
| Message truncation | **Deferred** — "—more—" prompt handles overflow. Monitor for intrusiveness. |
| Disk I/O performance | **Done** — JiffyDOS fastloader required and documented. REU path eliminates tier load pauses entirely. |
| Turn speed at 1 MHz | **Deferred** — monitor in playtesting. AI loop processes max 32 monsters; should be fast enough. |
| Balance (fewer monsters/items) | **Deferred** — tuning pass after all content features are in place. |
| Spell variety | **Tracked** — R5.1/R5.2. |
| Lack of artifacts | **N/A** — not present in umoria. Ego items (R4.1) cover umoria's "special" item system. |

### AUDIT §5 — Architecture & Physical Build

| Finding | Disposition |
|---------|------------|
| Single binary tax (~2-4KB C128 dead code) | **Action item A4** — separate binaries (BOOT.PRG + MORIA64 + MORIA128). Aligned with Phase 10. Major effort, deferred until C128 work begins. |
| REU support | **Done** — keep as-is. ~400 bytes for massive playability gain. |

### AUDIT §6 — UX & Polish

| Finding | Disposition |
|---------|------------|
| Directory art | **Action item A2** — add PETSCII art filenames to d64 image. Small effort, high first-impression impact. |

### AUDIT §7 — File Naming

| Finding | Disposition |
|---------|------------|
| MORIA.SAV → THE.GAME | ✅ **Done** (save.s) |
| MORIA.HI → HALL.OF.FAME | ✅ **Done** (score.s) |
| CR T1-T4 → MONSTER.DB.1-4 | ✅ **Done** (tier_manager.s, Makefile) |

### AUDIT §8 — Release Strategy

| Finding | Disposition |
|---------|------------|
| Character Disk (separate game/save disks) | **Action item A3** — medium effort. Requires disk-swap prompts, save disk ID validation, and code changes to save.s/score.s. Improves update experience. |

### Action Items Summary

| # | Description | Effort | Files |
|---|-------------|--------|-------|
| A1 | ~~File naming: MORIA.SAV→THE.GAME, MORIA.HI→HALL.OF.FAME, CR T1-T4→MONSTER.DB.1-4~~ | ✅ Done | save.s, score.s, tier_manager.s, Makefile, memory.s |
| A2 | ~~Directory art: PETSCII art in d64 listing~~ | ✅ Done | Makefile, tools/diskart.py |
| A3 | Character disk: separate game/save disks with swap prompts | Medium | save.s, score.s, new disk_swap.s |
| A4 | ~~Separate binaries: BOOT.PRG + MORIA64~~ | ✅ Done | boot.s, main.s, Makefile |
| A5 | ~~Stack depth audit: trace deep call chains, document max nesting~~ | ✅ Done | Max 27 bytes (14 JSR levels), 87% margin — no canary needed |
| A6 | Large file split: dungeon_gen.s, item.s into sub-modules | Low | Opportunistic refactoring |
| A7 | Item generation distribution review vs umoria curves | Small | Documentation / item.s tuning |

---

### Review Pass 5 — Post-Phase 4.5 Full Codebase Review (2026-02-10)

Reviewed all 32 files (~12,400 lines). All tests pass (6/6 suites, 52/52 tests).
No blocking bugs found.

#### Test coverage gaps

| Module | Gap | Severity | Status |
|--------|-----|----------|--------|
| math.s | `math_dice` is completely untested — no tests for bonus handling, negative bonuses, or edge cases | Medium | **Fixed** — Tests 13-16: basic 1d6+0, positive bonus 1d6+10, negative bonus 1d6-1, multi-dice 10d8+0 (20 iterations each) |
| test_dungeon.s Test 14 | Streamer scan only checks 3 of 15 map pages ($C000, $C400, $C800) — streamers in unscanned pages would be missed | Low | **Fixed** — Pointer-based full map scan ($C000-$CEFF, 15 pages) |
| test_memory.s | ZP save/restore only validates 4 of 142 bytes ($02–$05) | Low | **Fixed** — Loop-based test covers all 142 ZP bytes ($02-$8F) using X^$A5 pattern |
| test_rng.s | `rng_range` boundary cases (N=1, N=255) not tested | Low | **Fixed** — Tests 5-6: rng_range(1) always 0, rng_range(255) always <255 (100 iterations each) |

#### Code quality notes (non-blocking)

| File | Issue | Severity |
|------|-------|----------|
| dungeon_render.s | `render_single_tile` (lines 289–452) duplicates ~150 lines from `render_viewport` — extract shared subroutine when code next changes | Low |
| dungeon_features.s:196 | `find_random_floor` returns last (possibly non-floor) coordinates if 200 attempts exhausted — trap could land on wall tile (extremely rare) | Low |
| dungeon_gen.s:2062 | BFS queue has no overflow guard — safe in practice (max ~2000 passable tiles vs 4000 queue capacity on 80x48 map) | Low |

#### False positives investigated and cleared

Three findings were flagged by automated review and manually verified as correct:

1. **Room lit/dark logic (dungeon_gen.s:621–624):** `ldx`/`lda` between `cmp` and `bcc` do NOT affect the carry flag. Logic correctly implements "lit if dlvl <= threshold".
2. **math_dice negative bonus (math.s:103–110):** Sign-extension via `adc #$ff` on the high byte is the standard 6502 pattern for 16-bit addition of a sign-extended 8-bit negative value. Verified with worked examples.
3. **Corridor swap infinite loop (dungeon_gen.s:1031–1043):** All coordinates are valid map positions (0–79), so the Y register always reaches the target. No wrap-around possible.

---

### Review Pass 6 — Monster/Combat Deep Review vs. umoria (2026-02-11)

Reviewed all Phase 5 implementation (monster.s, combat.s, monster_attack.s, monster_ai.s, turn.s)
against umoria source (data_creatures.cpp, monster.h, monster.cpp, player.cpp).
All 10 test suites pass. Attack types verified by manually decoding umoria's monster_attacks[] array.

#### MC1: Creature stat data — RESOLVED

**Status: FIXED.** All 20 creature types now match umoria. The 5 invented creatures (Fruit bat,
Soldier ant, Green naga hatchling, Cave spider, Wild cat) have been replaced with real umoria
creatures (White Harpy, Green Worm mass, Poltergeist, Huge Brown Bat, Creeping Copper Coins).

All stats verified correct against umoria `data_creatures.cpp`:
- **XP values**: 20/20 match (kill_exp_value)
- **AC values**: 20/20 match
- **HP dice**: 20/20 match (hd_num, hd_sides)
- **Creature levels**: 20/20 match
- **Sleep values**: 20/20 match
- **Awareness radii**: 20/20 match
- **Attack types**: 20/20 match (slot 0 and slot 1)
- **Attack dice**: 20/20 match

**Naming note:** C64 "Grey Mold" = umoria "Grey Mushroom patch" (same stats, display 'm'/M).
C64 "Giant Frog" = umoria "Giant Green Frog" (same stats).

**Multi-attack limitation:** White Harpy has 3 attacks in umoria (claw 1d1, claw 1d1, bite 1d2)
but C64 only supports 2 slots (claw 1d1, claw 1d1). Third attack lost. Low impact (1d2 normal).

#### MC2: XP system bugs — PARTIALLY RESOLVED

1. ~~**Min-1 XP floor not in umoria.**~~ **FIXED** — `combat_award_xp` (combat.s:473) no longer
   forces minimum 1 XP. Weak creatures correctly award 0 XP when player level >> creature level.

2. **No fractional XP accumulation (known simplification).** umoria uses 16-bit fixed-point
   fractions (`exp_fraction`) to preserve partial XP. The C64 uses integer division only.
   This means small XP amounts from weak creatures are lost entirely (0 instead of accumulating
   fractions). Documented in code comment at combat.s:475. Impact is minor for early game
   since creature XP values are high enough relative to player level.

3. **Only uses cr_xp_lo, ignores cr_xp_hi** (combat.s:459). Safe for current creatures
   (max XP=9) but will break when higher-tier creatures are added.

#### MC3: Combat formula bugs — PARTIALLY RESOLVED

1. ~~**Monster to-hit off-by-one.**~~ **FIXED** — `mon_atk_roll_tohit` (monster_attack.s:249-250)
   now uses `cmp zp_player_ac; bcs !mart_hit+` correctly (`>=` check). No extra `beq`.

2. ~~**Player to-hit missing race BTH.**~~ **FIXED** — `combat_calc_tohit` (combat.s:172-197)
   now adds race BTH from `race_properties` offset 7, with signed handling and clamping.

3. **Confusion damage handling still wrong (see RP7-3).** The original finding was inverted:
   the code does NOT apply AC reduction + physical damage. Instead it applies NO damage at all
   (`lda #0; sta zp_combat_dmg`). In umoria, confusion deals FULL dice damage (no AC reduction)
   plus 50% chance of confusion effect. See Review Pass 7 for details.

#### MC4: Missing features — MEDIUM

1. **No critical hit system.** umoria's `playerWeaponCriticalBlow` (chance based on weapon
   weight + to-hit + class_adj × level, damage multiplier 2-5×) is not implemented. All player
   hits do flat damage. Critical chance formula: `(weapon_weight + 5*plus_to_hit +
   class_level_adj[class][BTH]*level) / 5000`. Tiers: 2× (+5), 3× (+10), 4× (+15), 5× (+20).

2. ~~**No HP/MP regeneration.**~~ **HP + MP REGEN IMPLEMENTED** — `turn_tick_regen` (turn.s)
   implements CON-based regen counter (8-50 turns per 1 HP depending on CON). Poison suppresses
   regen. `zp_eff_regen` doubles tick rate. Simplified vs umoria's 16-bit fixed-point fractional
   accumulation — C64 uses integer counter per CON. Starvation damage (1 HP/turn at food=0)
   also implemented. Mana regen implemented in Step 7.9 (turn.s: INT-based, non-warriors only).

3. ~~**Missing effect-specific messages.**~~ **VERIFIED CORRECT** — Effect handlers DO print
   messages: `mon_atk_effect_poison` calls `mon_atk_build_effect_msg` (monster_attack.s:408-417),
   `mon_atk_effect_confuse` prints at lines 442-452, `mon_atk_effect_paralyze` prints at
   lines 514-524. Player sees both "THE X HITS YOU." and "THE X POISONS YOU." etc.
   Effect expiration messages also print: "YOU FEEL BETTER." (poison), "YOU CAN SEE AGAIN."
   (blind), "YOU FEEL LESS CONFUSED." (confuse), "YOU CAN MOVE AGAIN." (paralyze).

4. ~~**Monster confusion/stun timers never decremented.**~~ **FIXED** — `monster_process_one`
   now checks `MX_STUN` and `MX_CONFUSE` timers directly at `!mpo_awake:`. Stun > 0: decrement
   and skip turn. Confuse > 0: decrement and random-move (no spellcast). Old `MF_CONFUSED` flag
   check removed — timer IS the confusion state. Timers count down 1 per turn; at 0, normal AI
   resumes. All timer-setting call sites (combat.s, player_magic.s, player_items.s, spell_effects.s)
   already write `MX_CONFUSE`/`MX_STUN` correctly. 21 monster_ai tests pass.

#### MC5: Design simplifications — LOW (speed issues mostly resolved)

1. ~~**Speed model oversimplified.**~~ **MOSTLY FIXED** — Speed model now uses 0=slow (every other
   turn), 1=normal, 2=fast (double move). CF_ATTACK_ONLY flag separates "can't move" from "slow".
   Three slow creatures correctly at speed=0. Remaining issue: Poltergeist speed=1 should be 2
   (see RP8-1). Huge Brown Bat correctly at speed=2. Very fast creatures (umoria speed=13) capped
   at 2 moves instead of 3 — acceptable simplification for C64.

2. **Blows table simplified.** C64 uses 5×4 (5 weight classes, 4 DEX brackets). umoria uses
   7×6 (7 weight classes, 6 DEX brackets including 18/xx ranges). Fine for now since weapons
   and 18/xx DEX aren't in play yet.

3. ~~**Stale header comment in monster_ai.s:8.**~~ **FIXED** — Header now correctly documents
   CF_ATTACK_ONLY behavior and updated speed model.

#### Verified correct

1. **Attack type constants** (ATK_NORMAL=1, ATK_CONFUSE=3, ATK_ACID=6, ATK_PARALYZE=11,
   ATK_POISON=14, ATK_AGGRAVATE=20) match umoria's numbering.
2. **Base to-hit values per attack type** in `mon_atk_base_tohit` table match umoria's
   `playerTestAttackHits` switch statement.
3. **Monster to-hit formula** (`base_tohit + creature_level × 3`) correctly derives from
   umoria's `playerTestBeingHit(base, level, 0, AC, CLASS_MISC_HIT)` with CLASS_MISC_HIT=3.
4. **AC damage reduction formula** (`damage -= (AC × damage) / 200`) matches umoria exactly.
5. **Player to-hit roll** (combat.s:332-360) correctly compensates for rng_range's [0,N-1]
   range vs umoria's [1,N] by using `>=` instead of `>`.
6. **Monster to-hit roll** (monster_attack.s:229-257) also correctly uses `>=` check.
7. **Paralysis saving throw** logic (monster_attack.s:447-504) correctly implements
   class_save_base + player_level with rng_range(100) check. (Simplified vs umoria's
   full formula that includes WIS adjustment — acceptable simplification.)
8. **Monster rendering** is implemented in dungeon_render.s (checks FLAG_OCCUPIED, looks up
   cr_display/cr_color).
9. **Player to-hit formula** (combat.s:161-250) now correctly includes class BTH + race BTH +
   PL_TOHIT × 3 + player_level × class_bth_per_level, matching umoria's full calculation.
10. **All 20 creature stats** match umoria source (XP, AC, HP dice, levels, sleep, aaf, attack
    types, attack dice). Verified against `data_creatures.cpp` and `monster_attacks[]` array.
11. **Effect messages** are printed: poison, confusion, and paralysis handlers all call
    `mon_atk_build_effect_msg` with the appropriate strings.
12. **XP award formula** (`cr_xp * cr_level / player_level`) correctly matches umoria.
    Min-1 floor removed. Integer-only is a documented simplification.

---

### Review Pass 7 — Verification of Review Pass 6 Findings (2026-02-11)

Cross-referenced Review Pass 6 findings against current code and umoria source (`data_creatures.cpp`,
`monster.cpp`, `player.cpp`, `game_run.cpp`). Found that MC1-MC3 have been substantially fixed in
code but the BUILDPLAN was not updated to reflect this. Additionally found 8 new bugs not identified
in Review Pass 6, mostly in `mon_atk_effect_dispatch` (attack type routing) and the speed model.

All 10 test suites still pass.

#### RP7-1: Speed=0 creatures cannot attack — CRITICAL

Four creatures have `cr_speed` = 0: Shrieker Mushroom (#6), Floating Eye (#8), Grey Mold (#16),
Yellow Mold (#18). In `monster_ai_tick` (monster_ai.s:60-61), speed=0 causes the monster to be
**completely skipped** — no wake check, no attack processing, nothing. These creatures are
decorative scenery that can be killed without any resistance.

In umoria, these creatures have speed=11 (normal) with `CM_ATTACK_ONLY` movement flag — they cannot
move but DO attack when the player is adjacent. The distinction between "can't move" and "can't act"
is missing from the C64's speed model.

**Impact:** Floating Eye never paralyzes (its entire purpose). Shrieker Mushroom never aggravates.
Grey Mold never confuses. Yellow Mold never attacks. These are 4/20 creatures rendered harmless.

**Fix options:**
1. Add `MF_ATTACK_ONLY` flag. In `monster_ai_tick`, process speed=0 monsters with a simplified
   path: wake check → if awake and player adjacent → attack. Skip movement entirely.
2. Set speed=1 and add a `CM_NO_MOVE` flag checked in `monster_move_toward`/`monster_move_random`.
   Simpler: monster wakes, tries to move, flag prevents actual movement, but adjacency check
   in `monster_try_step` still triggers `monster_attack_player`.

Option 2 is simpler to implement — just check a flag before moving and skip movement but still
process the monster normally otherwise.

#### RP7-2: Poison attacks wrongly apply AC reduction — MEDIUM

`mon_atk_effect_dispatch` routes poison (ATK_POISON) through `mon_atk_ac_reduce` before applying
the poison effect (monster_attack.s:341-344):
```
!maed_poison:
    jsr mon_atk_ac_reduce       // WRONG — poison has no AC reduction in umoria
    jsr mon_atk_effect_poison
```

In umoria (monster.cpp:1665-1668), poison attacks call `playerTakesHit(damage, ...)` with the full
dice damage — NO AC reduction. Only attack type 1 (Normal) gets AC reduction.

**Fix:** Remove `jsr mon_atk_ac_reduce` from the poison handler.

#### RP7-3: Confusion attacks deal no damage — MEDIUM

`mon_atk_effect_dispatch` sets confusion damage to 0 (monster_attack.s:346-347):
```
!maed_confuse:
    lda #0
    sta zp_combat_dmg           // Confusion: no physical damage
```

In umoria (monster.cpp:1563-1576), confusion attacks deal **full dice damage** (no AC reduction)
AND have a 50% chance (`randomNumber(2) == 1`) of applying confusion. The C64 applies 0 damage
and always applies confusion.

**Fix:** Remove the `lda #0; sta zp_combat_dmg` lines. Add 50% roll before applying confusion
(see RP7-4).

#### RP7-4: Confusion missing 50% chance — MEDIUM

In umoria, confusion only applies 50% of the time:
```cpp
if (randomNumber(2) == 1) {
    // apply confusion
}
```

The C64 `mon_atk_effect_confuse` always applies confusion when the attack hits (no random check).
This makes confusion effects twice as frequent as umoria intends.

**Fix:** Add `lda #2; jsr rng_range; cmp #0; bne !mec_done+` before applying confusion effect.

#### RP7-5: Confusion doesn't stack — LOW

In umoria, confusion stacks: `py.flags.confused += 3` always runs (even if already confused),
and if not previously confused, also adds `randomNumber(creature_level)`. The C64 returns
immediately if already confused (`bne !mec_done+` at monster_attack.s:413).

**Fix:** Remove the early return. If already confused, add 3 turns. If not, add
`rng_range(creature_level) + 3`.

#### RP7-6: Poison doesn't stack — LOW

In umoria (monster.cpp:1668): `py.flags.poisoned += randomNumber(creature_level) + 5` — poison
always adds to the existing counter. The C64 returns immediately if already poisoned
(`bne !mep_done+` at monster_attack.s:378).

**Fix:** Remove the early return. Always add `rng_range(cr_level) + 5` to poison timer.

#### RP7-7: Three slow creatures run at normal speed — MEDIUM

White Worm Mass (#2), Green Worm Mass (#10), and Creeping Copper Coins (#15) have umoria speed=10
(half speed — acts every other player turn). The C64 has them at speed=1 (normal — acts every turn).
This makes them move twice as often as umoria intends.

In umoria, speed < 11 means the creature acts less frequently (speed 10 = every other turn).
The C64 has no "slow" category — only 0 (broken, see RP7-1), 1 (normal), 2 (fast).

**Fix options:**
1. Add speed=0 handling (see RP7-1) that includes "slow" via a fractional counter.
2. Simpler: keep the 0/1/2 model but make 0 = "slow" (acts every other turn), 1 = normal,
   2 = fast. Rename from "immobile" to "slow". Attack-only creatures (RP7-1) need a separate
   flag regardless.

#### RP7-8: Fear attack wrongly applies AC reduction — LOW

`mon_atk_effect_dispatch` routes fear (ATK_FEAR) through `mon_atk_ac_reduce` (monster_attack.s:367):
```
!maed_fear:
    jsr mon_atk_ac_reduce
```

In umoria (monster.cpp:1577-1588), fear attacks call `playerTakesHit(damage, ...)` with full dice
damage — no AC reduction. Only currently impacts Poltergeist (#13, 1d1 fear attack) so low impact.

**Fix:** Remove `jsr mon_atk_ac_reduce` from the fear handler.

#### RP7-9: Poison tick ignores CON — LOW

C64 (turn.s:30-32) deals flat 1 HP/turn poison damage. In umoria (`playerUpdatePoisonedState` in
game_run.cpp:550), poison damage per turn varies by CON adjustment: 0-4 HP/turn. High CON
characters take damage every 2-4 turns, low CON characters take 2-4 HP/turn.

Low priority — the flat 1 HP/turn is a reasonable simplification that averages out over time.

#### Summary of Review Pass 7 findings

| # | Severity | Issue | Fix complexity |
|---|----------|-------|----------------|
| RP7-1 | **CRITICAL** | Speed=0 creatures can't attack (4 of 20 broken) | Medium — add flag + special processing |
| RP7-2 | **MEDIUM** | Poison AC reduction wrong | Trivial — remove 1 JSR |
| RP7-3 | **MEDIUM** | Confusion deals no damage | Trivial — remove 2 lines |
| RP7-4 | **MEDIUM** | Confusion missing 50% chance | Easy — add rng check |
| RP7-5 | LOW | Confusion doesn't stack | Easy — restructure handler |
| RP7-6 | LOW | Poison doesn't stack | Easy — remove early return |
| RP7-7 | **MEDIUM** | 3 slow creatures at normal speed | Medium — requires speed model change |
| RP7-8 | LOW | Fear AC reduction wrong | Trivial — remove 1 JSR |
| RP7-9 | LOW | Poison tick ignores CON | Low priority simplification |

---

### Review Pass 8 — Post-RP7-Fix Verification (2026-02-11)

Verified all RP7 fixes (commit `37552c0`) against umoria source. All 8 actionable RP7 bugs
confirmed fixed correctly. Also verified new Phase 5 additions (HP regen, starvation, light
tracking, effect expiration messages). Found 3 remaining issues.

#### RP7 fix verification results

| # | Finding | Status |
|---|---------|--------|
| RP7-1 | Speed=0 creatures can't attack | **FIXED** — CF_ATTACK_ONLY flag added to `cr_mflags`. Attack-only creatures set to speed=1. `monster_try_step` checks CF_ATTACK_ONLY to block movement while still allowing adjacency attacks. |
| RP7-2 | Poison AC reduction wrong | **FIXED** — `mon_atk_effect_dispatch` routes poison directly to `mon_atk_effect_poison`, no AC reduction. |
| RP7-3 | Confusion deals no damage | **FIXED** — Confusion handler no longer zeroes `zp_combat_dmg`. Full dice damage passes through. |
| RP7-4 | Confusion missing 50% chance | **FIXED** — `rng_range(2)` check added: 0 = apply confusion, 1 = skip. |
| RP7-5 | Confusion doesn't stack | **FIXED** — Already confused: `+= 3`. New confusion: `rng_range(cr_level) + 3`. |
| RP7-6 | Poison doesn't stack | **FIXED** — Always adds `rng_range(cr_level) + 5` to existing timer. Message only on first poisoning. |
| RP7-7 | 3 slow creatures at normal speed | **FIXED** — White Worm (#2), Green Worm (#10), Copper Coins (#15) now speed=0. `monster_ai_tick` skips speed=0 on odd turns (acts every other turn). Verified against umoria speed=10 (half speed). |
| RP7-8 | Fear AC reduction wrong | **FIXED** — Fear handler passes through full dice damage, no AC reduction. |
| RP7-9 | Poison tick ignores CON | **Accepted simplification** — flat 1 HP/turn. |

#### New additions verified correct

1. **HP regeneration** (`turn_tick_regen`, turn.s:210-281) — CON-based counter (8-50 turns per
   1 HP heal). Poison suppresses regen. `zp_eff_regen` active doubles tick rate. Caps at max HP
   with 16-bit comparison. Resets counter from `regen_rate` table indexed by CON-3.

2. **Starvation damage** (`turn_tick_hunger`, turn.s:187-204) — When food counter reaches 0,
   deals 1 HP/turn and calls `player_death_check`. Correct behavior.

3. **Effect expiration messages** (turn.s:20-144) — Poison ("YOU FEEL BETTER."), blindness
   ("YOU CAN SEE AGAIN." + viewport redraw), confusion ("YOU FEEL LESS CONFUSED."), paralysis
   ("YOU CAN MOVE AGAIN.") all print correctly when their timers reach 0.

4. **Light source tracking** (`turn_tick_light`, turn.s) — Uses x30 tick multiplier
   (`LIGHT_TICKS_PER_CHARGE = 30`) so each charge = 30 turns. Torches ~4,020 turns,
   lanterns ~7,500 turns (matching umoria). Warns at 2 charges (~60 turns remaining:
   "YOUR LIGHT IS GROWING DIM."), expires at 0 ("YOUR LIGHT HAS GONE OUT." +
   sets `zp_light_radius` to 0 + unequips light).

#### RP8-1: Poltergeist speed wrong — MEDIUM

Poltergeist (#13) has `cr_speed` = 1 (normal) in monster.s:97. In umoria (`data_creatures.cpp`),
Poltergeist has speed = 13, meaning +3 over normal (very fast). The C64's maximum speed is 2
(double move), so the correct mapping is speed=2.

Huge Brown Bat (#14) is already correctly at speed=2 (umoria speed=12, double speed).

**Fix:** Change `cr_speed` index 13 from 1 to 2. One byte change.

#### RP8-2: Paralysis zeroes damage — LOW

`mon_atk_effect_dispatch` (monster_attack.s:356-357) zeroes `zp_combat_dmg` for paralysis:
```
!maed_paralyze:
    lda #0
    sta zp_combat_dmg
```

In umoria (monster.cpp:1620-1634), paralysis calls `playerTakesHit(damage, death_description)`
FIRST (applying full dice damage), then checks saving throw and applies paralysis effect.
Damage should not be zeroed.

**Practical impact: NONE currently.** The only paralysis creature (Floating Eye, #8) has 0d0
attack dice, so damage is already 0 before zeroing. However, the pattern is wrong for
correctness — future paralysis creatures with non-zero dice would be affected.

**Fix:** Remove `lda #0; sta zp_combat_dmg` from `!maed_paralyze`. Let dice damage pass through.

#### RP8-3: Paralysis timer offset wrong — LOW

C64 `mon_atk_effect_paralyze` uses `rng_range(cr_level) + 1`, giving a range of [1, level].
For the level-1 special case, it hardcodes 2.

umoria uses `randomNumber(creature_level) + 3`, giving a range of [4, level+3].

For Floating Eye (level 1): C64 = 2 turns, umoria = 4 turns.
For a hypothetical level 3 creature: C64 = [1, 3], umoria = [4, 6].

Paralysis is consistently ~2-3 turns shorter than umoria intends. This makes paralysis less
threatening than it should be.

**Fix:** Change `adc #1` to `adc #4` (equivalent to umoria's randomNumber offset after accounting
for rng_range's [0,N-1] vs randomNumber's [1,N]). Update level-1 special case from 2 to 5.

#### Summary of Review Pass 8 findings

| # | Severity | Issue | Fix complexity |
|---|----------|-------|----------------|
| RP8-1 | **MEDIUM** | Poltergeist speed=1, should be 2 | Trivial — 1 byte |
| RP8-2 | LOW | Paralysis zeroes damage (no practical impact) | Trivial — remove 2 lines |
| RP8-3 | LOW | Paralysis timer +1 should be +4 | Trivial — change 2 constants |

### Review Pass 9 — Post-RP8-Fix + Phase 6.5 Review (2026-02-11)

Verified RP8 fixes (commit `d63dc07`) and reviewed Phase 6.5 item identification system
(commit `d1788f4`). RP8 fixes confirmed correct with one residual off-by-one. Phase 6.5
identification system (Fisher-Yates shuffle, name/color resolution, quaff, read scroll,
inventory/render integration) is well-structured and correct. Found 3 issues.

#### RP8 fix verification results

| # | Finding | Status |
|---|---------|--------|
| RP8-1 | Poltergeist speed wrong | **FIXED** — `cr_speed[13]` changed from 1 to 2 (monster.s:97). Correct. |
| RP8-2 | Paralysis zeroes damage | **FIXED** — `lda #0; sta zp_combat_dmg` removed from `!maed_paralyze` (monster_attack.s:355). Full dice damage passes through. |
| RP8-3 | Paralysis timer offset wrong | **PARTIALLY FIXED** — General formula changed from `+1` to `+4`. Correct for level >= 2. However, **level-1 special case hardcodes 5 instead of 4** — see RP9-1. |

#### Phase 6.5 items verified correct

1. **Fisher-Yates shuffle** (item.s:1283-1370) — Correct implementation. Loop from i=N-1 down
   to 1, pick j in [0, i] via `rng_range(i+1)`, swap. X saved/restored around `rng_range` call.
   5 potion descriptors, 5 scroll descriptors, 4 ring descriptors — more descriptors than item
   types ensures unique assignments.

2. **`item_get_name_ptr`** (item.s:1382-1445) — Correctly maps type → id_known check → local
   index (subtract category base) → shuffle table → name pointer. Returns real name for known
   types, randomized description for unknown.

3. **`item_get_floor_color`** (item.s:1453-1500) — Same pattern as name resolution. Clobbers X
   (documented), verified safe in both render_viewport (dungeon_render.s:250-252) and
   render_single_tile (dungeon_render.s:519-521) — X not needed after color stored.

4. **Flag preservation on pickup** (item.s:886-887, 451) — `fi_flags,x → fi_add_flags →
   inv_flags,x` chain correctly preserves IF_CURSED through pickup. Test 30 validates.

5. **Quaff effects** (player_items.s) — Cure Light Wounds HP cap (16-bit comparison handles all
   cases), Speed timer stacking with 255 cap, Poison damage+death+timer stacking all correct.

6. **Scroll effects** (player_items.s) — Light room bounds check correct, Identify scroll
   consumes before second prompt (matches classic Moria), Teleport clears/sets FLAG_OCCUPIED.

7. **Inventory/render integration** — `ui_inv_display`, `ui_equip_display`, `item_append_name`,
   and both render functions all correctly delegate to `item_get_name_ptr`/`item_get_floor_color`.

#### RP9-1: Paralysis timer off-by-one for level 1 — LOW

Residual from RP8-3 fix. The general formula `rng_range(level) + 4` gives [4, level+3], correctly
matching umoria's `randomNumber(level) + 3` = [4, level+3]. But the level-1 special case
(monster_attack.s:504) hardcodes 5:

```
lda #5                      // Level 1: 0 + 4 + 1 = 5
```

The comment's arithmetic "0 + 4 + 1 = 5" is wrong — there's no "+1" in the formula. For level 1,
`rng_range(1)` always returns 0, so the result should be `0 + 4 = 4`. umoria confirms:
`randomNumber(1) + 3 = 1 + 3 = 4`.

The special case is also unnecessary — `rng_range(1)` safely returns 0, so the general path
would give the correct result for level 1.

**Practical impact:** Floating Eye paralysis lasts 5 turns instead of 4. Minor balance difference.

**Fix:** Remove the level-1 special case entirely, or change `lda #5` to `lda #4`.

#### RP9-2: `item_drop` doesn't preserve flags — MEDIUM

`item_drop` (item.s:982-994) copies `inv_item_id`, `inv_qty`, and `inv_p1` to `fi_add_*`
variables before calling `floor_item_add`, but does NOT copy `inv_flags` to `fi_add_flags`.
Since `floor_item_add` always writes 0 to `fi_flags,x` (item.s:311), a drop+pickup round-trip
loses IF_CURSED (and IF_IDENTIFIED).

This means a player could uncurse an item by dropping and picking it back up.

**Fix:** Add `lda inv_flags,x` / `sta fi_add_flags` in `item_drop` before the `floor_item_add`
call, then post-hoc set `fi_flags,x` from `fi_add_flags` after `floor_item_add` succeeds
(same pattern used in `item_spawn_level` at item.s:664-667).

#### RP9-3: `floor_item_add` ignores `fi_add_flags` — LOW (design debt)

Root cause of RP9-2. `floor_item_add` (item.s:311) unconditionally writes `lda #0; sta fi_flags,x`
instead of copying `fi_add_flags`. Every caller must remember to post-hoc patch `fi_flags,x`
after the call — currently `item_spawn_level` does this (item.s:664-667 and 766-768) but
`item_drop` does not.

**Fix (optional cleanup):** Change `floor_item_add` to copy `fi_add_flags` instead of hardcoding
0. This would eliminate the need for post-hoc patching in callers, making the API less error-prone.
If done, also update the function's input comment to document `fi_add_flags`.

#### Summary of Review Pass 9 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP9-1 | LOW | Paralysis timer level-1 special case: 5 should be 4 | Trivial — remove special case | **FIXED** — removed level-1 special case; general formula handles it |
| RP9-2 | **MEDIUM** | `item_drop` loses IF_CURSED/IF_IDENTIFIED flags | Easy — add `inv_flags→fi_add_flags` copy | **FIXED** — added flags copy in `item_drop` before `floor_item_add` |
| RP9-3 | LOW | `floor_item_add` ignores `fi_add_flags` (design debt) | Easy — copy `fi_add_flags` instead of hardcoding 0 | **FIXED** — `floor_item_add` now copies `fi_add_flags`; removed post-hoc patches; added init to gold path + all tests |

### Review Pass 10 — Phase 7 Steps 7.0–7.5 Implementation Review (2026-02-12)

Reviewed all three new Phase 7 files (`spell_effects.s` ~1014 lines, `spell_data.s` ~137 lines,
`player_magic.s` ~1258 lines) plus integration points in `main.s`, `combat.s`, and `player_create.s`.
Cross-referenced against BUILDPLAN steps 7.0–7.5, calling conventions of all referenced functions
(`math_dice`, `monster_find_at`, `monster_get_ptr`, `monster_remove`, `rng_range`, `get_direction_target`,
`stat_bonus_index`, `combat_append_str`, `combat_award_xp`, `combat_check_levelup`, `find_random_floor`),
zero-page allocations (`zp_math_tmp0/1` at $20/$21 confirmed separate from `zp_temp0-2` at $02-$04),
and encoding (`.encoding "screencode_upper"` confirmed set globally in `main.s` line 20).

**Files reviewed:** `spell_effects.s`, `spell_data.s`, `player_magic.s`, `main.s` (dispatch),
`combat.s` (level-up hooks), `player_create.s` (starting spells), `monster.s` (CF_UNDEAD),
`dungeon_features.s` (find_random_floor, trap_check_at_player), `dungeon_render.s` (monster
rendering), `math.s` (math_dice/math_multiply), `player.s` (stat_bonus_index), `tables.s`
(spell_stat_bonus), `screen.s` (screen_put_string), `zeropage.s`.

#### Findings

**RP10-1 (BUG): Monster HP=0 treated as alive in spell effect damage**

In `spell_effects.s`, the death check after 16-bit HP subtraction uses only `bpl` (branch if
HP_HI >= 0), meaning a monster at exactly 0 HP survives. This is INCONSISTENT with `combat.s`
`combat_apply_damage` (lines 412–449), which checks BOTH `bmi` (HP < 0) AND `ora` for exact
zero (HP == 0), treating HP <= 0 as dead.

Affected locations:
- `eff_bolt` line 702: `bpl !eb_fizzle+`
- `eff_damage_adjacent` line 765: `bpl !eda_next+`
- `eff_dispel_undead` line 1002: `bpl !edu_next+`
- ~~`mage_effect_dispatch` effect 0 (Magic Missile)~~ — **Fixed**: now uses `eff_bolt` (shared death check)

**Fix:** After each `bpl !alive+`, add an explicit zero check:
```
    bmi !dead+
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    ldy #MX_HP_HI
    ora (zp_ptr0),y
    bne !alive+
!dead:
```
Or extract a shared `eff_check_monster_dead` subroutine since this pattern repeats 4 times.
Alternatively, match the `combat_apply_damage` pattern: `bmi` then `beq` on the OR of both bytes.

**RP10-2 (BUG): `eff_destroy_traps_doors` does not remove traps from trap table**

`eff_destroy_traps_doors` (spell_effects.s lines 804–869) changes adjacent TILE_TRAP map tiles
to TILE_FLOOR, but does NOT modify or remove the corresponding entries in `trap_x`/`trap_y`/
`trap_type` arrays. The comment at line 865 acknowledges this: "simplified: clear the whole trap
table since most are revealed" — but the code doesn't actually do it.

`trap_check_at_player` (dungeon_features.s line 330) triggers traps by scanning the
`trap_x`/`trap_y` table, NOT by checking map tile types. Therefore, a trap that was "destroyed"
on the map (tile changed to TILE_FLOOR) will STILL TRIGGER when the player steps on it.

**Fix:** After the direction loop, scan `trap_x`/`trap_y` for entries matching each of the 8
adjacent positions and remove them (swap with last entry + decrement `trap_count`):
```
    // Remove matching traps from trap table
    ldx #0
!scan:
    cpx trap_count
    bcs !scan_done
    // For each of 8 directions, check if trap_x[x],trap_y[x] matches
    // If match: swap with last entry, dec trap_count, don't inc x
    ...
```

**RP10-3 (BUG): `find_random_floor` does not check FLAG_OCCUPIED**

`find_random_floor` (dungeon_features.s lines 165–200) selects a random floor tile by checking
only `TILE_TYPE_MASK == TILE_FLOOR`. It does NOT check that `FLAG_OCCUPIED` is clear. This means
`eff_teleport_self` and `eff_phase_door` can teleport the player onto a tile already occupied by
a monster, resulting in both entities sharing a tile.

Compare with `find_monster_floor` (monster.s lines 285–338) which correctly checks
`TILE_TYPE_MASK | FLAG_OCCUPIED` before accepting a tile.

**Fix:** In `find_random_floor`, change the tile check from:
```
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
```
to:
```
    sta zp_temp0
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !frf_next+
    lda zp_temp0
    and #FLAG_OCCUPIED
    bne !frf_next+
```

**RP10-4 (MEDIUM): BUILDPLAN test expectation for `magic_recalc_mana` is wrong**

Step 7.3 test says: "Verify `magic_recalc_mana` with INT=12, level=5 → expected max_mana
= (5*12)/8 + bonus[12-3] = 7 + 1 = 8." (Corrected: bonus[9]=1 per `spell_stat_bonus` table.)

The `spell_stat_bonus` table in `tables.s` (lines 196–198) has:
```
    .byte  0,  0,  0,  0,  0,  1,  1,  1  // indices 0-7 (stats 3-10)
    .byte  1,  1,  1,  2,  2,  3,  3,  3  // indices 8-15 (stats 11-18)
```
Index 9 (stat 12) = **1**, not 2. Correct expected value: (5×12)/8 + 1 = 7 + 1 = **8**.

**RP10-5 (MEDIUM): `eff_phase_door` duplicates teleport code instead of calling `eff_teleport_self`**

`eff_phase_door` (spell_effects.s lines 376–404) contains a full copy of the FLAG_OCCUPIED
clear/move/set logic from `eff_teleport_self`. After the distance-check loop selects a target
(stored in `df_target_x`/`df_target_y`), it should simply `jsr eff_teleport_self` which does
the exact same thing. The duplicated code is 28 bytes of wasted space and a maintenance hazard
(a bug fix in one copy won't automatically apply to the other).

**Fix:** Replace lines 376–404 with `jsr eff_teleport_self; rts` (or `jmp eff_teleport_self`).

**RP10-6 (MEDIUM): `eff_heal` API diverges from BUILDPLAN — 8-bit only**

The BUILDPLAN (Step 7.0) describes `eff_heal(A=dice, X=sides, Y=bonus)` with integrated dice
rolling. The implementation takes a pre-rolled 8-bit heal amount in A. This means all callers
must call `math_dice` separately, then pass `zp_math_a` to `eff_heal`. The 16-bit high byte
(`zp_math_b`) is silently discarded.

Current max heal is 5d8+5 = 45, well within 8 bits. However, the function signature mismatch
between plan and code should be documented. The current approach is arguably better (simpler
function, separation of concerns), but the BUILDPLAN should be updated to match reality.

**RP10-7 (LOW): `eff_detect_monsters` makes monster tiles permanently FLAG_VISITED**

After `eff_detect_monsters` sets FLAG_VISITED on each monster's tile, those tiles remain
permanently marked as visited. When the monster moves away, the old tile still shows as visited
floor. This is not harmful (the renderer checks FLAG_OCCUPIED before drawing a monster glyph,
so no phantom monsters appear), but it does reveal map layout in areas the player hasn't
explored — a minor information leak.

In umoria, Detect Monster is a temporary effect with a duration. Consider adding a timer
(`zp_eff_detect`, already in the ZP effect block) and only showing monsters while the timer
is active, rather than permanently marking tiles.

**RP10-8 (LOW): CMP/BEQ dispatch chains for 16 spell effects**

Both `mage_effect_dispatch` and `priest_effect_dispatch` use a linear CMP/BEQ chain (16
comparisons worst case for spell index 15). A jump table would be O(1):
```
    asl                   // index * 2
    tax
    lda mage_jmp_tbl+1,x
    pha
    lda mage_jmp_tbl,x
    pha
    rts                   // jump via RTS trick
```
This saves ~48 bytes and is faster for higher-index spells. Not critical at 16 entries but
worth considering since the same pattern will be used for potions, scrolls, wands, and staves
in steps 7.6–7.7, potentially expanding to 40+ dispatch entries total.

**RP10-9 (LOW): `stat_bonus_index` has no lower-bounds check**

`stat_bonus_index` (player.s lines 392–401) computes `stat - 3` without checking if stat < 3.
If a stat ever reaches 2 or below, the subtraction underflows to 253+ and indexes far past the
16-byte `spell_stat_bonus` table (buffer over-read).

Current stat drain code (dungeon_features.s line 500) guards with `cmp #4; bcc !no_drain+`,
preventing stats from dropping below 3. But this is an implicit contract — `stat_bonus_index`
itself is fragile.

**Fix:** Add a defensive clamp:
```
    cmp #3
    bcs !ok+
    lda #3
!ok:
```

**RP10-10 (LOW): `eff_bolt` tile passability check is too narrow**

`eff_bolt` (spell_effects.s lines 664–671) only allows bolts through `TILE_FLOOR` and
`TILE_DOOR_OPEN`. If any other passable tile types exist or are added later (e.g., stairs,
rubble), bolts would stop on them. The check should probably use a "not wall" test instead:
```
    cmp #TILE_WALL_H
    beq !eb_wall+
    cmp #TILE_WALL_V
    beq !eb_wall+
    cmp #TILE_DOOR_CLOSED
    beq !eb_wall+
    jmp !eb_check_mon+
!eb_wall:
    jmp !eb_fizzle+
```
Or better, use a tile-passability helper. For now, TILE_FLOOR covers corridors (they use the
same tile type), so this works for the current map generator. Flag for future review.

**RP10-11 (LOW): `eff_kill_monster` clears FLAG_OCCUPIED redundantly**

`eff_kill_monster` manually clears FLAG_OCCUPIED (lines 924–940), then calls `monster_remove`
(line 944) which also clears FLAG_OCCUPIED (monster.s lines 619–625). The first clear is
redundant. Removing the manual clear saves ~17 bytes.

**RP10-12 (LOW): No `eff_aggravate` implementation**

Step 7.0 lists `eff_aggravate` (wake all monsters, set MF_AWAKE) as a shared subroutine to
create. It's not used in steps 7.4/7.5, but step 7.6 needs it for Scroll of Aggravation.
It should be implemented now to keep step 7.0 complete. Implementation is trivial:
```
eff_aggravate:
    ldx #0
!loop:
    cpx #MAX_MONSTERS
    bcs !done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !next+
    ldy #MX_SLEEP_CUR
    lda #0
    sta (zp_ptr0),y       // Clear sleep
!next:
    inx
    jmp !loop-
!done:
    rts
```

#### Suggested Additional Tests

The existing test suites (`test_effects.s`, `test_combat.s`) do not cover the spell casting flow
or individual spell effects. The following runtime tests should be added:

1. **Spell dispatch correctness:** Cast each mage spell 0–15 in a controlled setup; verify the
   expected side effect occurred (e.g., Magic Missile: monster HP decreased; Light: room_lit set;
   Teleport: player position changed).
2. **Mana deduction on failure:** Set player to Mage, mana=10, force spell failure (set fail_base
   to 100), verify mana decreased but no effect applied.
3. **HP=0 kill check:** Place monster with exactly N HP, deal exactly N damage via bolt/Fire Ball,
   verify monster is removed (once RP10-1 is fixed).
4. **Phase door distance:** Set player at (40, 24), call eff_phase_door, verify new position is
   within Chebyshev distance 10 (or verify fallback behavior after 20 failed attempts).
5. **Occupied tile teleport:** Place monster on every floor tile except one, call
   eff_teleport_self, verify player lands on the unoccupied tile (once RP10-3 is fixed).
6. **Spell known bitmask boundary:** Set PL_SPELLS_KNOWN = $00/$00, player_level = 9. Call
   magic_check_new_spells. Verify spells 0–7 (lo byte) AND spells 8–9 (hi byte) are all learned
   correctly (tests the 8-bit boundary crossing).
7. **Bless/Chant timer ranges:** Cast Bless 100 times, verify all values in [12, 23]. Cast Chant
   100 times, verify all values in [24, 47].
8. **Slow Poison edge cases:** Test with poison=1 → stays 1. Test with poison=0 → stays 0
   (guard check). Test with poison=255 → becomes 128 (127 | 1).
9. **Remove Curse coverage:** Equip cursed weapon + cursed armor + non-cursed ring. Cast
   Remove Curse. Verify cursed flags cleared on weapon and armor, ring unchanged.
10. **Bolt wall stop:** Fire Lightning Bolt toward wall 2 tiles away with monster behind wall.
    Verify bolt stops at wall, monster takes no damage.
11. **Trap/Door Destroy + trigger:** Destroy adjacent trap via spell, then step on that tile.
    Verify trap does NOT trigger (once RP10-2 is fixed).
12. **Failure rate clamp:** Test with very high level (level 40, spell level 1): verify failure
    rate is clamped to 5%, not negative. Test with very low stat (stat 3): verify no underflow.

#### Summary of Review Pass 10 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP10-1 | **HIGH** | Monster HP=0 treated as alive in spell damage (inconsistent with combat.s) | Easy — add zero check after `bpl` in 4 locations, or extract helper | **Fixed** — all 3 locations already use `bmi`+`ora` zero-check; Magic Missile now uses shared `eff_bolt` |
| RP10-2 | **HIGH** | `eff_destroy_traps_doors` doesn't remove traps from trap table; traps still trigger | Medium — add trap table scan after direction loop | **Fixed** — trap table entries scanned and removed via swap-with-last logic (spell_effects.s:854-906) |
| RP10-3 | **HIGH** | `find_random_floor` doesn't check FLAG_OCCUPIED; teleport can land on monsters | Easy — add FLAG_OCCUPIED check in find_random_floor | **Fixed** — FLAG_OCCUPIED check added (dungeon_features.s:197-198) |
| RP10-4 | **MEDIUM** | BUILDPLAN test expectation wrong: spell_stat_bonus[9]=1, not 2; expected mana=8, not 9 | Trivial — fix test expectation text | **Fixed** — corrected both test spec (line 3147) and RP description (line 1856) |
| RP10-5 | **MEDIUM** | `eff_phase_door` duplicates 28 bytes of teleport code; should call `eff_teleport_self` | Trivial — replace with JSR/JMP | **Fixed** — now calls find_random_floor (spell_effects.s:342) |
| RP10-6 | **MEDIUM** | `eff_heal` API takes pre-rolled A (8-bit) not dice params as BUILDPLAN describes | Documentation — update BUILDPLAN to match implementation | **Fixed** — BUILDPLAN step 7.1 updated to match actual 8-bit API |
| RP10-7 | LOW | `eff_detect_monsters` permanently marks tiles FLAG_VISITED (minor map info leak) | Medium — add timer-based detect effect | **Fixed** — timer-based: `eff_detect_timer` counts down 20 turns, renderer shows detected monsters on unvisited tiles |
| RP10-8 | LOW | CMP/BEQ dispatch chains are O(n); jump table would be O(1) and smaller | Medium — rewrite as jump table | **Fixed** — RTS-trick jump tables replace 32 CMP/BNE entries; shared `heal_dice` helper; saves ~136 bytes |
| RP10-9 | LOW | `stat_bonus_index` has no lower-bounds check (stat < 3 causes buffer over-read) | Trivial — add `cmp #3; bcs` guard | **Fixed** — guard already present (player.s:407-409) |
| RP10-10 | LOW | `eff_bolt` only passes through TILE_FLOOR and TILE_DOOR_OPEN | Easy — invert check to block walls instead | **Fixed** — already uses `walkable_table` (allows floor, doors, rubble, stairs, traps) |
| RP10-11 | LOW | `eff_kill_monster` clears FLAG_OCCUPIED redundantly (also done by monster_remove) | Trivial — remove manual clear | **Fixed** — redundant clear removed |
| RP10-12 | LOW | `eff_aggravate` not implemented despite being listed in Step 7.0 | Easy — ~20 bytes | Resolved (see RP11-6) |

---

### Review Pass 11 — Step 7.6 (Expanded Potions and Scrolls)

**Scope:** `item.s`, `player_items.s`, `combat.s`, `zeropage.s`, `tests/test_item.s`, `run_tests.sh`
**Reviewer:** Claude (automated)
**Date:** 2025-02-12

#### RP11-1 (HIGH): CSW heal computes [5,40] instead of intended [10,45]

**Location:** `player_items.s:836-856`

The comment says "heal 5d8 (5× rng(8)) + 5" and BUILDPLAN line 2408 says "Heal 5d8+5".
The code rolls 5×rng(8) = 5×[0,7] = [0,35], then adds 5, giving **[5,40]**.
The +5 only compensates for `rng_range(8)` returning [0,7] instead of [1,8] — the actual
+5 bonus from the design is lost.

Intended range: 5d8+5 = [10, 45]. Actual range: [5, 40]. Off by 5 at both ends.

**Test impact:** Test 33 checks HP in [60,95] (expects 50 + [10,45] heal). With the actual
[5,40] range, heal values 5-9 produce HP 55-59 which fails the `cmp #60; bcc` lower bound
check. The test will fail intermittently (~14% of runs).

**Fix:** Replace the manual loop with `math_dice(5, 8, 5)`:
```
lda #5           ; N=5 dice
ldx #8           ; S=8 sides
ldy #5           ; bonus=5
jsr math_dice
lda zp_math_a    ; low byte (max 45, fits in 8 bits)
jsr eff_heal
```
This also saves ~14 bytes versus the manual loop.

#### RP11-2 (HIGH): Enchant Weapon/Armor broken on cursed items

**Location:** `player_items.s:1184-1198` (weapon), `player_items.s:1228-1242` (armor)

The cap check uses unsigned comparison: `lda inv_p1,x; cmp #5; bcc`. Cursed items store
negative p1 as two's complement (e.g., -3 = $FD). Unsigned $FD = 253 ≥ 5, so BCC does not
branch. The handler falls through to "already at cap" and does nothing.

In umoria, enchanting a cursed weapon/armor should: (1) clear IF_CURSED flag, (2) set p1=0,
(3) recalculate equipment, (4) display glow message.

**Fix:** Before the unsigned cap check, add a cursed-item branch:
```
!irs_ew_has:
    ldx #EQUIP_WEAPON
    lda inv_flags,x
    and #IF_CURSED
    beq !irs_ew_not_cursed+
    // Cursed → remove curse + reset to 0
    lda inv_flags,x
    and #~IF_CURSED & $ff
    sta inv_flags,x
    lda #0
    sta inv_p1,x
    jsr player_recalc_equipment
    jmp !irs_ew_msg+         ; print glow message
!irs_ew_not_cursed:
    lda inv_p1,x
    cmp #5
    bcc !irs_ew_inc+
    ...
```
Same pattern needed for Enchant Armor with EQUIP_BODY.

#### RP11-3 (MEDIUM): No test coverage for enchant on cursed items

Test 35 (Enchant Weapon) only tests with positive p1=2. No test exists for:
- Enchant weapon with negative p1 ($FD = -3) and IF_CURSED flag set → should remove curse, set p1=0
- Enchant armor with IF_CURSED flag → same behavior
- Enchant at exact cap (p1=5) → should print "nothing happens", p1 unchanged

#### RP11-4 (MEDIUM): Heroism, Infravision, Protect from Evil timers have no game effect

`zp_eff_hero`, `zp_eff_infra`, and `zp_eff_protect` are set by their respective
potions/scrolls and decremented each turn by `turn.s`, but **no code checks these timers
to apply gameplay effects:**
- Heroism: should grant +1 to-hit and +10 max HP while active (per umoria)
- Infravision: should reveal monsters within range while active
- Protect from Evil: should reduce damage from evil monsters while active

The timers are pure stubs — using these items currently has no gameplay effect. Either the
consumption code should be added (likely a Phase 8+ concern) or the BUILDPLAN should
explicitly note these as infrastructure-only stubs awaiting integration.

#### RP11-5 (LOW): Word of Recall overwrites timer (correct but undocumented)

`zp_eff_word_recall` is stored directly (`sta`), not added to existing value. Reading a
second Word of Recall scroll overwrites the timer rather than extending it. This matches
umoria behavior but differs from other timer effects (Heroism, Blindness, etc.) which
stack via `clc; adc`. Should be documented as intentional.

#### RP11-6 (LOW): RP10-12 resolved — eff_aggravate IS implemented

RP10-12 stated eff_aggravate was not implemented. It exists at `spell_effects.s:1046` and
is successfully called by the Aggravate scroll handler at `player_items.s:1270`. RP10-12
status should be updated to Resolved.

#### Suggested tests for Step 7.6

1. **CSW heal range [10,45]:** After fixing RP11-1, verify heal from HP=50 gives HP in
   [60,95]. Run multiple iterations to catch edge cases.
2. **Enchant Weapon on cursed item:** Set EQUIP_WEAPON p1=$FD (-3), inv_flags=IF_CURSED.
   Read Enchant Weapon scroll. Verify p1=0, IF_CURSED cleared.
3. **Enchant Armor on cursed item:** Same test for EQUIP_BODY slot.
4. **Enchant at exact cap:** Set p1=5, read Enchant scroll → verify p1 stays 5.
5. **Heroism timer stacking:** Drink two Heroism potions → verify timer in [50,98] range
   (not overflow beyond 98).
6. **Protect from Evil timer range:** Verify timer in [25,49] after reading scroll.

#### Summary of Review Pass 11 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP11-1 | **HIGH** | CSW heal [5,40] instead of [10,45]; Test 33 fails intermittently | Easy — use math_dice(5,8,5) or change adc #5 → adc #10 | **Fixed** — replaced manual loop with `math_dice(5,8,5)` giving correct [10,45] range |
| RP11-2 | **HIGH** | Enchant Weapon/Armor broken on cursed items (unsigned cmp treats -N as >5) | Medium — add IF_CURSED branch before cap check in both handlers | **Fixed** — added IF_CURSED check before cap comparison; cursed items get curse cleared + p1 set to 0 |
| RP11-3 | **MEDIUM** | No test for enchant on cursed items | Easy — add test with negative p1 + IF_CURSED | **Fixed** — added test 39 (enchant cursed weapon: p1→0, flag cleared) and test 40 (enchant at cap: p1 stays 5) |
| RP11-4 | **MEDIUM** | Heroism/Infravision/Protect timers are stubs — no code checks them for gameplay effects | Design — document as stubs or implement consumption | **Documented** — added NOTE comments to all three handlers marking timers as infrastructure-only until effect consumption phase |
| RP11-5 | LOW | Word of Recall overwrites (not stacks) timer — correct but undocumented | Trivial — add comment | **Fixed** — added comment documenting overwrite-not-stack behavior matches umoria |
| RP11-6 | LOW | RP10-12 wrong: eff_aggravate IS implemented at spell_effects.s:1046 | Trivial — update RP10-12 status | **Resolved** — RP10-12 already marked as resolved in prior pass |

---

### Review Pass 12 — RP11 Fix Verification

**Scope:** `player_items.s`, `tests/test_item.s`, `run_tests.sh`, `BUILDPLAN.md`
**Reviewer:** Claude (automated)
**Date:** 2025-02-12
**Commit reviewed:** `b94e59e Fix Review Pass 11 findings for Step 7.6 potions/scrolls`

All six RP11 fixes verified correct. No bugs found.

- **RP11-1 fix (CSW heal):** `math_dice(5, 8, 5)` produces correct [10,45] range.
  `zp_math_a` low byte (max 45) fits 8 bits. Test 33's [60,95] check now consistent.
- **RP11-2 fix (Enchant on cursed items):** Both weapon and armor handlers check
  `IF_CURSED` before the unsigned cap comparison. Cursed path correctly clears flag
  via `and #~IF_CURSED & $ff`, sets p1=0, calls `player_recalc_equipment`, jumps to
  shared `!irs_ew_msg` / `!irs_ea_msg` glow message label. Normal-increment path
  unchanged.
- **RP11-3 fix (New tests 39-40):** Test 39 sets p1=$FD with IF_CURSED, verifies
  p1=0 and flag cleared. Test 40 sets p1=5, verifies no increment past cap. Copy
  loop `ldx #39` (40 bytes) and run_tests.sh `"0400 0427" 40` both correct.
- **RP11-4/5/6 (Comments and status updates):** Infrastructure NOTE comments and
  WoR overwrite comment all correctly placed.

#### RP12-1 (LOW): Armor enchant cursed/cap paths lack dedicated tests

Tests 39-40 only cover the **weapon** enchant path. The armor handlers
(`!irs_ea_has` cursed branch and cap check) are structurally identical but untested.
Adding tests 41-42 mirroring tests 39-40 for EQUIP_BODY would complete coverage.

#### Summary of Review Pass 12 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP12-1 | LOW | Armor enchant cursed/cap paths untested (weapon-only coverage) | Easy — mirror tests 39-40 for EQUIP_BODY | **Fixed** — tests 41-42 added (cursed armor + cap check) |

---

### Review Pass 13 — Steps 7.9 and 7.10 (Mana Regen, WoR, Integration, Polish)

**Scope:** `turn.s`, `player_magic.s`, `player_items.s`, `sound.s`, `ui_character.s`,
`ui_help.s`, `monster_magic.s`, `tests/test_effects.s`, `run_tests.sh`
**Reviewer:** Claude (automated)
**Date:** 2026-02-12

#### RP13-1 (HIGH): Confused casting blocked by known-spell and level checks

**Location:** `player_magic.s:160-236`

When confused, a random spell index (0-15) is selected at line 166-168, replacing the
player's choice. However, the code falls through to the known-spell check (line 164-191)
and the minimum level check (line 218-236). If the random spell isn't known (the common
case for most players), the handler prints "YOU DON'T KNOW THAT SPELL" and returns CLC
(no turn consumed, no mana deducted). If the spell is too high level, same result.

**In umoria**, confused casting:
- Bypasses both known and level requirements
- Deducts mana for the random spell (checked normally)
- Rolls for failure normally
- Executes the random spell's effect on success

**Current behavior:** Confusion during casting is effectively harmless — most random spells
will be unknown, so the player just gets an error message and no turn is consumed. This
defeats the entire purpose of the confusion mechanic during spellcasting.

**Fix:** Two changes needed:
1. In the confused branch, add `jmp !pm_known+` to skip the known-spell check:
```
    lda zp_eff_confuse
    beq !pm_not_confused+
    lda #16
    jsr rng_range
    sta pm_spell_idx
    jmp !pm_known+             ; Skip known check when confused
!pm_not_confused:
```
2. Before the level check at `!pm_mana_ok`, add a confusion bypass:
```
!pm_mana_ok:
    lda zp_eff_confuse
    bne !pm_lvl_ok+            ; Skip level check when confused
    // Normal level check follows...
```

#### RP13-2 (MEDIUM): BUILDPLAN mana regen rate contradicts implementation

**Location:** BUILDPLAN line ~2864 vs `turn.s` implementation

BUILDPLAN prose says "recover 1 mana per 3 turns" with regen making it "1 per 2 turns".
BUILDPLAN code block says "Every 2 turns (basic rate)" with `and #$01`.
Implementation matches the code block: normal = 1 per 2 turns, with regen = 1 per turn.

The prose and code block within the BUILDPLAN contradict each other. The code block and
implementation agree. Fix: update the prose from "per 3 turns" to "per 2 turns" and
regen from "per 2 turns" to "every turn".

#### RP13-3 (MEDIUM): PL_MAX_DLVL offset differs from BUILDPLAN

BUILDPLAN step 7.9 line ~2910 says "Use `PL_SPARE_63` (player struct offset 63)".
Implementation uses `PL_MAX_DLVL = 56` (offset 56). `PL_SPARE_63` remains unused at
offset 63. Not a code bug — the architect chose a different offset — but the BUILDPLAN
should be updated to match.

#### RP13-4 (LOW): No test for confused casting

The confusion-during-casting interaction (Step 7.10 checklist item 2) has no dedicated
test. A test should:
1. Set zp_eff_confuse > 0, put all 16 spells known, sufficient mana
2. Call pm_do_cast with keyboard input for spell 'A'
3. Verify a spell was actually cast (mana decreased, turn consumed)
4. This would also expose the RP13-1 bug if spells were NOT all known

#### RP13-5 (LOW): No test for extra regen on odd turn

Tests 11-12 cover normal regen (even turn) and warrior no-regen. Missing:
- Set zp_eff_regen > 0, zp_turn_lo = 1 (odd turn), verify MP still increases
  (extra regen bypasses the even-turn check)

#### RP13-6 (LOW): No test for Word of Recall fizzle

When recalling from town (dlvl=0) with PL_MAX_DLVL=0 (player has never entered the
dungeon), the recall should fizzle (jump to `!no_recall`). No test covers this path.

#### RP13-7 (LOW): Intermediate fix commit (e427147) notes

The fix commit between RP12 and Step 7.9 correctly:
- Replaced `mm_check_death` with `player_death_check` in `monster_magic.s` bolt and
  breath handlers (carries through from `mon_atk_apply_damage`)
- Hit sound no longer plays on player death (correct — death has its own SFX)
- Added missing `monster_magic.s` import to `test_item.s`
- Updated stale test bounds

No issues found in this commit.

#### Verified correct in Steps 7.9/7.10

- **Word of Recall teleportation:** Clears FLAG_OCCUPIED at old position, sets
  level_entry_dir correctly (1=ascending for dungeon→town, 0=descending for
  town→dungeon), calls full level regeneration chain, stops running, redraws UI.
- **Mana regen logic:** Warriors excluded (PL_SPELL_TYPE=0), max cap check correct,
  extra regen skips turn parity check, syncs to player_data.
- **Blindness blocks scroll reading:** Returns CLC immediately (no turn consumed).
- **Hunger penalty:** +20 to failure rate at HUNGER_FAINT or worse, capped at 95.
  Applied after the base [5,95] clamp, so max effective failure with hunger is 95%.
- **Sound effects:** SFX_SPELL and SFX_SPELL_FAIL correctly added to sfx_table at
  indices 6-7. Triangle wave for spell, noise buzz for fizzle. Both use voice 3.
- **Help screen:** New line "M CAST SPELL     P PRAY", HELP_LINE_COUNT=22, pointer
  tables extended correctly in both lo and hi arrays.
- **Character sheet:** Spells Known (N/16) displayed for spell-casters only (row 11).
  count_spells_known correctly iterates all 16 bits via spell_bit_mask. "Press any key"
  moved to row 16 to accommodate.
- **Max depth tracking:** Already present in main.s (lines 338-341), updates on
  stairs-down. PL_MAX_DLVL initialized to 0 at player creation (line 165).
- **Tests 11-18:** All structurally correct — mana regen, warrior no-regen, recall
  both directions, hunger penalty, no-hunger baseline, count_spells_known, blindness
  blocks scrolls.

#### Suggested tests for Steps 7.9/7.10

1. **Confused cast (all spells known):** Set 16 spells known, confuse > 0, cast →
   verify mana decreased and turn consumed (currently fails due to RP13-1).
2. **Confused cast (few spells known):** Set 3 spells known, confuse > 0, cast →
   should still cast random spell (currently blocked by known check).
3. **Extra regen on odd turn:** zp_eff_regen=5, zp_turn_lo=1, mage MP=5/20 →
   verify MP becomes 6 (bypass even-turn check).
4. **Recall fizzle:** dlvl=0, PL_MAX_DLVL=0, recall timer=1 → verify dlvl stays 0.
5. **Mana regen stops at max:** MP=19, MMP=20, tick even turn → MP=20. Tick again →
   MP stays 20.

#### Summary of Review Pass 13 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP13-1 | **HIGH** | Confused casting blocked by known-spell and level checks (confusion is harmless) | Easy — add `jmp !pm_known+` in confused branch + confusion bypass at level check | **Fixed** |
| RP13-2 | **MEDIUM** | BUILDPLAN says "1 per 3 turns" but code/implementation do 1 per 2 turns | Trivial — fix BUILDPLAN prose | **Fixed** |
| RP13-3 | **MEDIUM** | PL_MAX_DLVL at offset 56, BUILDPLAN says offset 63 (PL_SPARE_63) | Trivial — update BUILDPLAN | **Fixed** |
| RP13-4 | LOW | No test for confused casting interaction | Easy — add test with confusion + known spells | **Fixed** (test 19) |
| RP13-5 | LOW | No test for extra regen on odd turn | Trivial — same as test 11 with regen=5 and odd turn | **Fixed** (test 20) |
| RP13-6 | LOW | No test for Word of Recall fizzle (town, never visited dungeon) | Trivial — set PL_MAX_DLVL=0, verify dlvl unchanged | **Fixed** (test 21) |

### Review Pass 14 — Phase 8 (Stores) Implementation Review (2026-02-12)

Full review of Phase 8 store implementation: `store.s`, `ui_store.s`, `math.s` (math_mul_16x8),
`tables.s` (chr_price_adj/chr_sell_adj), main.s integration, and test files. Cross-referenced
against umoria source (`store.cpp`, `store_inventory.cpp`, `data_store_owners.cpp`,
`data_stores.cpp`, `player_stats.cpp`) for pricing formulas, store categories, restocking,
and haggling behavior.

**Files reviewed:**
- `store.s` — 6 stores, SoA inventory (72 slots), category bitmasks, restocking, pricing, gold ops
- `ui_store.s` — Store UI loop, buy/sell flows, door detection, screen drawing
- `math.s` — math_mul_16x8 (16×8→24-bit multiply)
- `tables.s` — chr_price_adj (100-130%), chr_sell_adj (25-50%)
- `item.s` — it_cost_lo/hi (47 entries), it_category, ICAT constants
- `main.s` — store_init_all at startup, store door check in main loop, restock on stair ascent
- `turn.s` — Word of Recall code path (missing restock)
- `player_items.s` — inv_add_item, inv_remove_item, inv_count_items
- `dungeon_gen.s` — STORE_COUNT, store_door_x/y, store positions
- `zeropage.s` — zp_store_idx ($8C), zp_store_slot ($8D)
- `tests/test_store.s` — 17 tests (all pass; VICE detection issue only)
- `tests/test_store_debug.s` — 13 deterministic tests (pass)
- `tests/test_store_iso.s` — 9 isolation tests (pass)

**Verification approach:** Built test_store.s, confirmed segment layout ($0810-$90D0),
checked symbol addresses (tc_results=$8E25, test_start=$8E39, BRK=$90CF, tc_count=$90D0),
ran all tests in VICE with correct breakpoint — all 17 pass in 3.1M cycles. Verified
store door positions match building geometry. Verified price arithmetic for boundary cases
(max cost 300 × max adj 130 = 39,000 fits 16-bit intermediate).

**Documented design deviations (acceptable):**
- 12 items per store vs 24 in umoria (noted in BUILDPLAN)
- No haggling (accept/decline at offered price, noted in BUILDPLAN)
- Restock on town re-entry vs umoria's turn-based (every 1000 turns, noted in BUILDPLAN)
- No item identification affecting prices (C64 scope limitation)
- No item stacking in store slots (each item takes one slot)

#### Findings

**RP14-1 (HIGH — Word of Recall to town skips store restock)**

`turn.s:157-163`: When Word of Recall teleports the player from dungeon to town, the code
sets `zp_player_dlvl=0`, sets `level_entry_dir=1`, and jumps to `recall_generate` which
calls `level_generate`, `monster_spawn_level`, `item_spawn_level`, etc. — but does NOT
call `store_restock_all`. In contrast, `main.s:405-407` correctly calls `store_restock_all`
when ascending stairs to town (dlvl becomes 0).

The BUILDPLAN Step 8.1 says "Inventory restocking on town re-entry." Word of Recall is a
form of town re-entry. The fix is to add `jsr store_restock_all` in the WoR-to-town path,
after setting dlvl=0 and before `jmp !recall_generate+`.

**RP14-2 (MEDIUM — BUILDPLAN says "race modifier" but implementation omits it)**

BUILDPLAN Step 8.3: "Base price x charisma modifier x **race modifier**." The implementation
uses ONLY charisma adjustment (`chr_price_adj` for buying, `chr_sell_adj` for selling).
No race-based price modifier exists.

In umoria, a `race_gold_adjustments[8][8]` table adjusts prices by ±5-35% based on
owner_race × player_race. The C64 store owners have names but no race data. This is a
reasonable simplification for the C64 scope, but the BUILDPLAN should be updated to remove
the "race modifier" reference to match the implementation, or a race modifier should be added.

**RP14-3 (MEDIUM — Enchantment and charges ignored in pricing)**

`calc_buy_price` and `calc_sell_price` use only the base item type cost (`it_cost_lo/hi`).
Enchantment level (`si_p1` / `inv_p1`) and item flags are completely ignored.

Impact: A +3 enchanted sword and a +0 sword of the same type cost the same to buy and sell.
A wand with 8 charges and a wand with 0 charges cost the same. In umoria, enchanted
weapons/armor get `(to_hit + to_damage + to_ac) × 100` added to base value, and
wands/staves get `(cost/20) × charges` added.

This is a design simplification but notable — players get no extra gold for selling superior
items, and store-stocked enchanted items are underpriced. Consider adding at least
`p1 × enchant_bonus_per_category` to the price calculation.

**RP14-4 (MEDIUM — Cursed items sellable at full base price)**

`calc_sell_price` does not check the `IF_CURSED` flag. A cursed item sells for the same
price as a normal item of the same type. In umoria, `storeItemValue()` returns 0 for
cursed items (identified as `ID_DAMD`), preventing sale.

The fix is to check `IF_CURSED` at the start of the sell flow (in `store_sell` at
`!ssell_cat_ok`) and either refuse the sale or set the price to 0. Additionally, when
a cursed item is sold to a store, it pollutes the store inventory — another player could
buy it back.

**RP14-5 (LOW — Store owner max gold not implemented)**

BUILDPLAN Step 8.1 mentions "Store owner data (name, race, max gold)." The implementation
has owner names (displayed in UI) but no race or max gold. Stores will buy items of
unlimited value. In umoria, each owner has `max_cost` (250-32,000 gold) which limits
both what items appear in auto-generated stock and the maximum price the owner will pay.

Update the BUILDPLAN to remove "race, max gold" from the owner data description if these
features are intentionally deferred.

**RP14-6 (LOW — test_store.s VICE breakpoint detection failure)**

All 17 tests in `test_store.s` pass correctly (verified by running in VICE with breakpoint
at BRK address $90CF). The apparent "hang" is caused by `tc_count: .byte 0` being defined
AFTER the `brk` instruction (line 478). This pushes the "Test Code" segment end address
to $90D0 (tc_count) instead of $90CF (brk). The `run_tests.sh` script extracts the segment
end address and sets a VICE breakpoint there — but $90D0 is data that's never executed, so
the breakpoint never fires. VICE hits the cycle limit and exits without processing monitor
commands (no memory dump occurs).

Fix: Move `tc_count` before `brk` (e.g., next to `tc_results`), so `brk` is the last byte
in the segment and the breakpoint fires correctly. Alternatively, eliminate tc_results and
write directly to $0400 (no store functions call msg_print, so screen RAM is safe).

**RP14-7 (LOW — inv_count_items clobbers fi_add_p1)**

`player_items.s`: `inv_count_items` reuses `fi_add_p1` as a scratch counter. This is
currently safe because `store_buy` re-sets `fi_add_p1` from the store slot data after
calling `inv_count_items` and before calling `inv_add_item`. However, this coupling is
fragile — any future caller that sets `fi_add_p1`, calls `inv_count_items`, then calls
`inv_add_item` without re-setting `fi_add_p1` would get corrupted data. Consider using
a dedicated scratch variable or a ZP temp instead.

#### Summary of Review Pass 14 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP14-1 | **HIGH** | Word of Recall to town skips store_restock_all | Trivial — add `jsr store_restock_all` in WoR-to-town path | **RESOLVED** — added `jsr store_restock_all` in turn.s WoR-to-town path |
| RP14-2 | **MEDIUM** | BUILDPLAN says "race modifier" for prices; implementation has charisma only | Trivial — update BUILDPLAN prose to match implementation | **RESOLVED** — Phase 8 table updated to say "charisma modifier only (race modifier deferred)" |
| RP14-3 | **MEDIUM** | Enchantment/charges ignored in pricing — all items of same type priced identically | Medium — add p1-based price bonus per category | **RESOLVED** — added `price_add_p1_bonus` in store.s: equipment +100 GP/enchant, wand/staff +10 GP/charge. New tests 18-19 verify. |
| RP14-4 | **MEDIUM** | Cursed items sellable at full base price (umoria: value 0) | Easy — check IF_CURSED in sell flow, refuse or set price 0 | **RESOLVED** — added IF_CURSED check in store_sell, displays "THAT ITEM IS CURSED." |
| RP14-5 | LOW | Store owner "max gold" mentioned in BUILDPLAN but not implemented | Trivial — update BUILDPLAN if intentionally deferred | **RESOLVED** — Phase 8 table updated to say "name only — race and max gold deferred" |
| RP14-6 | LOW | test_store.s VICE breakpoint fails — tc_count after brk shifts segment end | Trivial — move tc_count before brk | **RESOLVED** — tc_count moved before brk |
| RP14-7 | LOW | inv_count_items clobbers fi_add_p1 scratch (currently safe, fragile) | Easy — use dedicated scratch variable | **RESOLVED** — added `ici_count` dedicated scratch in item.s |

---

### Review Pass 15 — Staff Engineer Review of 18 Bug Fixes (2026-02-12)

Reviewed commit range `62e8480..a7b0712` (23 files changed, 1128 additions, 274 deletions).
Each bug fix was verified for 6502 assembly correctness, semantic correctness against umoria
behavior, and potential regressions. Also reviewed the RP14 fix commit (`ecdb78b`) and the
`store_pick_item` fix (`d21e376`).

**BUG-1 (18 stats inflating) — CORRECT.** Exceptional strength logic was being applied to
all stats, not just STR. Fix correctly gates the exceptional check on stat index == 0.

**BUG-2 (status bar redesign) — CORRECT.** Complete rewrite to 3-line umoria-style status
bar. 273 lines changed. Layout matches umoria conventions.

**BUG-3 (no townspeople) — CORRECT.** Added 6 town creature types (indices 20-25) and
`TOWN_CREATURE_BASE = 20` threshold for spawning. Town creatures use `MF_PROVOKED` flag
for aggression.

**BUG-4 (store door rendering) — CORRECT.** Per-tile store door check replaced with a
`render_store_doors` post-pass. More efficient and avoids disrupting dirty-tile rendering.

**BUG-5 (direction/diagonal key mapping) — CORRECT.** Directional keys now consistent.

**BUG-6 (no Q-to-quit in stores) — CORRECT.** Added `PETSCII_Q` ($51) as exit key in
store UI menu. Menu string updated to "Q)UIT".

**BUG-7 (auto-open door removes interactivity) — CORRECT.** Removed 10 lines of
auto-open door code; closed doors now block movement via `walkable_table[8]=0`.

**BUG-8 (sound_init not called) — CORRECT.** Added `jsr sound_init` in main.s init
sequence.

**BUG-9 (player '@' drawn as blank) — CORRECT.** Classic 6502 fall-through bug: missing
`jmp !rst_write+` after setting player tile caused execution to fall into blank-tile code.

**BUG-10 (look command) — CORRECT.** Direction scanning, monster/item/tile identification
all implemented. No assembly issues.

**BUG-11 (town creature provocation) — CORRECT, minor fragility note.** `MF_PROVOKED`
flag mechanism is correct. However, `TOWN_CREATURE_BASE = 20` is a magic number that
must stay synchronized with the creature table layout — any creature table reordering
will silently break the town/dungeon threshold. Consider a comment or `.assert`.

**BUG-12 (spell books) — CORRECT implementation, but introduced TWO side-effect bugs:**

> **RP15-1 (MEDIUM — Armory stocks spell books):** `ICAT_CLOAK` was renamed to `ICAT_BOOK`
> (value 13), but the Armory's category mask in `store_cat_mask_lo/hi` was not updated.
> Store 1 (Armory) has mask `$20F8` which has bit 13 set — this was intentional for cloaks,
> but now means the Armory unintentionally stocks spell books. Fix: change Armory mask from
> `$20F8` to `$00F8` (store.s line 35-37).

> **RP15-2 (MEDIUM — books get equipment pricing):** In `price_add_p1_bonus` (store.s
> line 436-437), `cmp #ICAT_BOOK / beq !pap_equip+` routes books to the equipment pricing
> handler that adds `p1 × 100` GP as an enchantment bonus. But book `p1` is a spell index
> (0-15), not an enchantment level — this creates up to 1500 GP of incorrect price inflation
> based on which spell the book teaches. Fix: remove the `ICAT_BOOK` branch from the
> equipment handler, or add a separate book pricing branch (e.g., flat 100 GP or base cost
> only, since spell books don't have enchantment).

**BUG-13 (folded into BUG-12 commit) — CORRECT.** No separate issues.

**BUG-14 (KERNAL GETIN clobbers X during name entry) — CORRECT.** Fix uses `cen_count`
byte to preserve character count across `input_get_key` calls. Clean solution that avoids
relying on X register surviving KERNAL calls.

**BUG-15 (debug hardcoded name) — CORRECT.** Removed test/debug name.

**BUG-16 (store screen clearing) — CORRECT.** Replaced `screen_clear` with
`ui_help_clear_all` for full 25-row clearing.

**BUG-17 (look command distance) — CORRECT.** Extended look to scan multiple tiles along
direction, not just adjacent tile. Turn-consuming actions reordered so AI runs before render.

**BUG-18 (inventory popup in selection dialogs) — CORRECT, minor note.** Added `'?'`
($3F) key check in 8 item selection dialogs to show inventory via `show_inv_and_restore`.
After the popup, the dialog re-prompts without re-validating state — this is safe because
inventory display can't modify game state, but worth noting as an assumption.

**store_pick_item fix (d21e376) — CORRECT.** `pha`/`pla` properly preserves item type
across `check_store_category` (which clobbers X). Previously returned store index (0-5)
instead of the item type.

**RP14 fixes (ecdb78b) — CORRECT.** All 7 RP14 findings addressed: WoR restock, plan
prose updates, enchantment pricing, cursed item check, tc_count position, and
`ici_count` dedicated scratch.

#### Summary of Review Pass 15 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP15-1 | **MEDIUM** | Armory mask $20F8 has bit 13 (ICAT_BOOK) — stocks spell books | Trivial — change to $00F8 in store_cat_mask_lo/hi | **Fixed** (Step 9.4) — mask data was already $00F8; fixed stale comment + test |
| RP15-2 | **MEDIUM** | price_add_p1_bonus routes ICAT_BOOK to equipment handler (p1×100 GP) | Easy — remove ICAT_BOOK from equipment branch or add flat book pricing | **Resolved** — ICAT_BOOK not in equipment branch; books fall through to no-bonus |
| RP15-3 | LOW | TOWN_CREATURE_BASE=20 is a magic number synced to creature table layout | Trivial — add .assert or comment | **Resolved** — already protected by .assert at monster.s:16 |
| RP15-4 | LOW | BUG-18 re-entry after inventory popup skips state re-validation (currently safe) | N/A — document assumption only | **Resolved** — comment added to show_inv_and_restore (player_items.s:65) |

**Overall verdict:** All 18 bug fixes are correct at the 6502 assembly level. No register
clobbering, branch range, or logic errors found. Two semantic bugs (RP15-1, RP15-2)
were introduced as side effects of the BUG-12 (spell books) implementation, both in
store.s. These are both straightforward fixes.

---

### Review Pass 16 — Save/Load System Review (Phase 9.1) (2026-02-13)

Reviewed save.s (1118 lines), main.s integration (title screen, load_resume_game),
and supporting files (memory.s, zeropage.s, player.s, dungeon_gen.s, dungeon_render.s).
Commits: `24b2df8` (initial save/load), `3cfa751` (crash fixes).

**Context:** User reports loading a save game crashes. The crash fix commit `3cfa751`
already addressed several issues: entry point under BASIC ROM, CREATURE_BASE overlap
with program code ($A100 → $AA00), file number conflict in check_savefile_exists, and
delete_savefile closing when OPEN failed. This review looks for remaining issues.

---

**RP16-1 (HIGH — player_sync_from_zp doesn't save light_radius; load overwrites it)**

In `save_game` (save.s:164), `player_sync_from_zp` is called before saving. But
`player_sync_from_zp` (player.s:153-183) does NOT copy `zp_light_radius` ($4B) back
to `player_data + PL_LIGHT_RAD`. It saves X, Y, HP, MHP, MP, level, dlvl, AC, and
food — but not light_radius, STR/INT/WIS/DEX/CON/CHR, race, or class.

The ZP state block ($40-$5F) IS saved, which includes $4B (correct light_radius value).
But during `load_game`, the load order is:
1. Step 3: load ZP $40-$5F from file → $4B gets correct saved value
2. Step s (save.s:499): `player_sync_to_zp` → overwrites $4B with
   `player_data + PL_LIGHT_RAD` (stale struct value)

Since PL_LIGHT_RAD is only set during player creation (via `player_sync_to_zp` copying
it from the struct), and the main.s new-game code sets `zp_light_radius = 1` directly
in ZP (main.s:224) without updating the struct, PL_LIGHT_RAD in the struct is likely 0.

**Result:** After loading, `zp_light_radius = 0`. `update_visibility` creates a 0-tile
visibility radius — the player can only see their own tile. The screen appears almost
entirely blank. While this doesn't cause a CPU crash, it makes the game unplayable and
likely appears as a "crash" to the user.

**Fix (two options):**
- **(A)** Add `lda zp_light_radius / sta player_data + PL_LIGHT_RAD` to
  `player_sync_from_zp`, so the struct always has the current value.
- **(B)** In `load_game`, move `player_sync_to_zp` BEFORE loading ZP $40-$5F, so the
  ZP state block has final authority. But this breaks other fields — option A is better.
- Also add the same line to `main.s` new-game init (after `lda #1 / sta zp_light_radius`,
  add `sta player_data + PL_LIGHT_RAD`).

---

**RP16-2 (HIGH — save filename is "MORIA SAV", should be "moria.sav")**

All four filename strings in save.s use the PETSCII sequence for "MORIA SAV" (with
space, no dot). The user requires the filename to be "moria.sav". On the 1541, filenames
can contain dots and lowercase letters. PETSCII lowercase letters are $41-$5A (same
codes as uppercase in PETSCII — the 1541 stores them as-is).

Affected strings (save.s lines 77-99):
- `save_filename`: `@0:MORIA SAV,S,W` → `@0:MORIA.SAV,S,W`
- `load_filename`: `0:MORIA SAV,S,R` → `0:MORIA.SAV,S,R`
- `scratch_cmd`: `S0:MORIA SAV` → `S0:MORIA.SAV`
- `check_filename`: `0:MORIA SAV,S,R` → `0:MORIA.SAV,S,R`

Fix: Replace `$20` (space) with `$2E` (PETSCII dot) in all four strings. Lengths
remain the same.

---

**RP16-3 (MEDIUM — READST EOF bit not checked during load)**

`load_read_block` (save.s:651-654) and `load_read_byte` (save.s:688-691) check
READST with `and #$03` (timeout/error bits only). They do not check bit 6 ($40)
which indicates EOF. If the save file is truncated, CHRIN will return $0D or
unpredictable values after EOF without flagging an error.

The checksum verification (save.s:484-493) provides a secondary defense — truncated
data will almost certainly fail the checksum. However, defense-in-depth requires
detecting the I/O error at the source.

Fix: Change mask from `$03` to `$43` to include EOF detection. This affects 4 locations:
save.s lines 567, 605, 653, 689 (write-side $03 checks can stay as-is since writes
don't encounter EOF).

---

**RP16-4 (MEDIUM — no RLE decompression output bounds check)**

`rle_decompress_map` (save.s:1021-1094) writes decompressed data to `MAP_BASE`
($C000) using `zp_ptr1` without checking that output doesn't exceed `MAP_SIZE` (3840
bytes). If the compressed data is corrupt (despite passing checksum), the output could
write past `MAP_END` ($CEFF) into `FLOOR_ITEM_BASE` ($CF00), corrupting floor item
data loaded moments earlier.

The checksum should catch most corruption, but this is a defense-in-depth issue.

Fix: Add a decompressed-byte counter. After decompression, assert the counter equals
MAP_SIZE. Or add bounds checking on `zp_ptr1_hi` during the write loop.

---

**RP16-5 (MEDIUM — player_sync_from_zp / player_sync_to_zp asymmetry)**

`player_sync_to_zp` (player.s:106-151) copies 20 fields from struct to ZP:
map X/Y, HP, MHP, MP, MMP, level, dlvl, AC, STR/INT/WIS/DEX/CON/CHR, race, class,
food, and light_radius.

`player_sync_from_zp` (player.s:153-183) copies only 13 fields back:
map X/Y, HP, MHP, MP, MMP, level, dlvl, AC, food.

Missing from sync_from_zp: STR/INT/WIS/DEX/CON/CHR (recalculated — OK), race/class
(immutable — OK), **light_radius** (mutable — BUG, see RP16-1).

The asymmetry means any future mutable field added to sync_to_zp but not sync_from_zp
will silently break save/load. Consider adding a comment documenting which fields are
intentionally excluded and why, or making the functions fully symmetric.

---

**RP16-6 (LOW — ZP $60-$8F not saved, mostly OK but fragile)**

The save system saves ZP $40-$5F (game state + effect timers) and the player struct
($2B-$3F via sync). But ZP $60-$8F (viewport, sound, monster AI, combat, inventory
scratch) is not saved. This is currently safe because:
- Viewport ($60-$63): recalculated by `viewport_update`
- Sound ($6C-$6F): reinitialized by `sound_init`
- Monster/combat/inv scratch ($70-$8F): transient, recalculated on use
- Dirty tiles ($69-$6B): `render_viewport` does full redraw, not dirty update

But `zp_ui_dirty` ($19) and `zp_msg_flags` ($18) are in the safe zone ($13-$19) which
is NOT covered by either the ZP save block ($40-$5F) or player sync ($2B-$3F). After
load, `msg_init` resets $18, and `zp_ui_dirty` should be 0 (no pending updates). This
is currently safe but the gap should be documented.

---

**RP16-7 (LOW — rle_flush_literals page-crossing handler tests X not Y)**

In `rle_flush_literals` (save.s:978-988), the page-crossing code:
```
    sta (zp_ptr1),y
    iny
    inx
    bne !rfl_copy-          // Tests INX result, not INY
    inc zp_ptr1_hi
```

The `bne` tests the Z flag from `inx`, not `iny`. The comment says "Handle page
crossing in dest" but the actual page crossing (Y wrapping from $FF to $00) is not
detected. This is currently harmless because the maximum literal length is 128, so Y
ranges from 1 to 129 ($81) and never wraps. But the logic is misleading and would
break if RLE_LITERAL_MAX were ever increased above 254.

---

#### Summary of Review Pass 16 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP16-1 | **HIGH** | player_sync_from_zp doesn't save light_radius — load reverts to 0, screen blank | Easy — add light_radius to sync_from_zp + init struct in main.s | **Fixed** |
| RP16-2 | **HIGH** | Filename "MORIA SAV" should be "moria.sav" per user requirement | Trivial — change $20 to $2E in 4 filename strings | **Fixed** |
| RP16-3 | **MEDIUM** | READST EOF bit ($40) not checked — truncated files not detected at I/O level | Easy — change mask from $03 to $43 in load_read_block/byte | **Fixed** |
| RP16-4 | **MEDIUM** | No RLE decompression output bounds check — corrupt data writes past MAP_END | Medium — add decompressed-byte counter or ptr bounds check | **Fixed** |
| RP16-5 | **MEDIUM** | sync_from_zp / sync_to_zp asymmetry — light_radius (and future fields) lost | Easy — document intentional exclusions, fix light_radius | **Fixed** |
| RP16-6 | LOW | ZP $60-$8F and $13-$19 not saved — currently safe, gaps undocumented | Trivial — add comments documenting the gap | **Fixed** |
| RP16-7 | LOW | rle_flush_literals page-crossing tests X not Y — dead code, misleading | Trivial — fix or add comment noting it's intentionally dead | **Fixed** |

**Likely crash cause:** RP16-1. After loading, `zp_light_radius` reverts to 0 (struct
value), making the screen appear almost completely blank. The player sees only their own
tile — this effectively looks like a crash or freeze. The root cause is that
`player_sync_from_zp` doesn't save light_radius to the struct, so when
`player_sync_to_zp` runs during load and copies the stale struct value (0) to ZP, it
overwrites the correct value that was loaded from the ZP state block.

---

### Audit: Light Source Duration vs. Umoria (2026-02-17)

Compared torch and brass lantern charge values against umoria source (`data_treasure.cpp`, `game_run.cpp`, `treasure.cpp`).

#### Umoria Reference Values

| Item | Full Charge | Store-Bought | Dungeon Find | Warning Threshold |
|------|------------|-------------|--------------|-------------------|
| **Wooden Torch** | **4,000 turns** | 4,000 | `randomNumber(4000)` = 1–4,000 | < 40 turns remaining (1-in-5 chance per turn) |
| **Brass Lantern** | **7,500 turns** | 7,500 | `randomNumber(7500)` = 1–7,500 | < 40 turns remaining (1-in-5 chance per turn) |

Umoria uses 16-bit `misc_use` field (int16_t). Decrements by 1 per turn. Store torches sold in stacks of 5.

#### C64 Port Current Values

| Item | Charge Range | Starting Torch | Warning |
|------|-------------|----------------|---------|
| **Wooden Torch** (type 13) | `20 + rng(30)` = **20–49 turns** | 40 (fixed) | Exactly 10 turns remaining |
| **Brass Lantern** (type 14) | `50 + rng(50)` = **50–99 turns** | — | Exactly 10 turns remaining |

Charges stored in `inv_p1` (8-bit, max 255). Decrements by 1 per turn in `turn_tick_light`.

#### Problem

C64 values are **~100x too low**. Torches should last thousands of turns, not dozens. The root cause is the 8-bit `inv_p1` field — umoria's values (4,000 and 7,500) don't fit in a byte.

With current values, a torch lasts ~35 turns on average — barely enough to explore a single room and corridor. In umoria, a store-bought torch lasts 4,000 turns (~100 dungeon levels of casual exploration). Light management is a background resource concern in umoria, not a constant crisis.

#### RP17-1 ~~(HIGH)~~ DONE: Light source duration ~100x too short

**Fixed** using Option B (x30 multiplier). `LIGHT_TICKS_PER_CHARGE = 30` with `light_tick_counter` in `turn_tick_light`. Each charge = 30 turns.

| Item | Charges (store) | Charges (dungeon) | Effective turns |
|------|----------------|-------------------|-----------------|
| Torch | 134 | 67 + rng(67) | ~4,020 (store) |
| Lantern | 250 | 125 + rng(125) | ~7,500 (store) |
| Starting torch | 134 | — | 4,020 |
| Warning threshold | 2 charges | — | ~60 turns remaining |

Files changed: `turn.s`, `item.s`, `main.s`, `tests/test_item.s`.

**Status:** Open

---

## Phase 7 — Magic System: Detailed Implementation Plan

### Current State Summary

**What exists:**
- Player struct has mana fields (`PL_MANA`=$31, `PL_MAX_MANA`=$32), spell type
  (`PL_SPELL_TYPE`=60), and `PL_SPELLS_KNOWN` 16-bit bitmask (offsets 61-62).
  16 spare bytes in player struct (offsets 63-79).
- Mana initialized in `player_create.s` (spell_stat/2, min 1). Displayed in
  `ui_status.s` and `ui_character.s`. Synced to/from ZP by `player_sync_*`.
- Command IDs defined: `CMD_CAST=$1A`, `CMD_PRAY=$1B`, `CMD_AIM=$18`,
  `CMD_USE=$19`. Key mappings exist in `input.s` but **not dispatched** in `main.s`.
- 14 status effect timers at ZP $50-$5E already ticked by `turn_tick_effects`
  in `turn.s`. Spells only need to SET timers — decrement/expiry is done.
- 3 potions (Cure Light, Speed, Poison) and 3 scrolls (Light, Identify,
  Teleportation) working with full identification system (Fisher-Yates shuffle).
- `get_direction_target` provides directional prompt (8 directions) + target
  tile calculation. `dir_dx`/`dir_dy` tables in `input.s`.
- `find_random_floor` finds an unoccupied floor tile (used by teleport scroll).
- LOS scratch at ZP $84-$87 reserved but Bresenham line trace **not implemented**.
- 20 creature types (levels 1-5). No spell/breath data in creature tables.
  Active monster entry has 2 reserved bytes (10-11).
- ~13.8 KB code space remaining ($6A00-$9FFF). 8 KB under KERNAL ROM available
  for spell tables if needed (but tables are small enough for main area).
- 5 spare ZP bytes ($4F, $5F, $6F, $8E, $8F) + scratch reuse.

**What's missing:**
- No cast/pray command dispatch. No spell list UI.
- No spell data tables (costs, levels, failure rates, effects).
- No learn-spells-on-level-up logic. No mana recalculation on level-up.
- No mana regeneration in turn processing.
- No Bresenham line trace for bolt/breath targeting.
- No wand/staff item categories or charge mechanics.
- No monster spell/breath data or ranged attack logic.
- Word of Recall timer ticks but the teleport TODO is unimplemented.

### Memory Budget

| Component | Estimated bytes |
|-----------|-----------------|
| Spell data tables (32 spells × 5 bytes + 32 name ptrs) | ~230 |
| Spell name strings (32 × avg 15 chars) | ~500 |
| `player_magic.s` (cast/pray, spell list UI, learn, failure roll) | ~1,500 |
| Shared effect subroutines (extracted + new) | ~800 |
| 16 mage spell effect handlers | ~1,200 |
| 16 priest prayer effect handlers | ~800 (many share w/ mage) |
| Expanded potions (7 new types, effect code) | ~600 |
| Expanded scrolls (7 new types, effect code) | ~700 |
| Wand/staff items + aim/use handlers + Bresenham | ~1,200 |
| Monster magic (spell data, ranged AI, breath) | ~1,500 |
| New item type SoA entries (~22 types × 8 arrays) | ~180 |
| Identification shuffle tables for new types | ~100 |
| Integration (mana regen, level-up, Word of Recall) | ~300 |
| **Total estimate** | **~9,600** |
| **Available** | **~14,100** |
| **Margin** | **~4,500 (32%)** |

### Spell Lists

#### Mage Spells (16) — indexed 0-15, requires `PL_SPELL_TYPE == SPELL_MAGE`

| # | Name | Mana | Min Lvl | Fail% | Effect |
|---|------|------|---------|-------|--------|
| 0 | Magic Missile | 1 | 1 | 22 | 1d4+level/2 bolt (traces path up to 20 tiles) |
| 1 | Detect Monsters | 1 | 1 | 23 | Reveal all monsters on map for 1 turn |
| 2 | Phase Door | 2 | 1 | 24 | Teleport to random floor within 10 tiles |
| 3 | Light Area | 2 | 1 | 26 | Light current room (share with scroll) |
| 4 | Cure Light Wounds | 3 | 3 | 25 | Heal 1d8+1 (share with potion) |
| 5 | Find Traps/Doors | 3 | 3 | 28 | Reveal traps + secret doors in radius |
| 6 | Stinking Cloud | 3 | 5 | 30 | Confuse all adjacent monsters |
| 7 | Confusion | 4 | 5 | 32 | Confuse target monster (directional) |
| 8 | Lightning Bolt | 5 | 7 | 34 | Bolt: 3d8 damage along line |
| 9 | Trap/Door Destruction | 5 | 7 | 36 | Destroy traps+doors in radius |
| 10 | Sleep I | 6 | 9 | 38 | Sleep all adjacent monsters |
| 11 | Cure Poison | 6 | 9 | 40 | Set zp_eff_poison = 0 |
| 12 | Teleport Self | 7 | 11 | 42 | Random teleport (share with scroll) |
| 13 | Frost Bolt | 8 | 13 | 44 | Bolt: 5d8 damage along line |
| 14 | Wall to Mud | 10 | 15 | 46 | Destroy one wall tile (directional) |
| 15 | Fire Ball | 12 | 17 | 50 | 7d8 damage to all adjacent monsters |

#### Priest Prayers (16) — indexed 0-15, requires `PL_SPELL_TYPE == SPELL_PRIEST`

| # | Name | Mana | Min Lvl | Fail% | Effect |
|---|------|------|---------|-------|--------|
| 0 | Detect Evil | 1 | 1 | 10 | Reveal monsters (same as mage Detect) |
| 1 | Cure Light Wounds | 1 | 1 | 15 | Heal 1d8+1 (shared subroutine) |
| 2 | Bless | 2 | 1 | 20 | Set zp_eff_bless = 12+1d12 |
| 3 | Remove Fear | 2 | 3 | 24 | (Future: clear fear status) |
| 4 | Call Light | 2 | 3 | 25 | Light room (shared subroutine) |
| 5 | Find Traps | 3 | 5 | 27 | Reveal traps in radius |
| 6 | Detect Doors/Stairs | 3 | 5 | 30 | Reveal doors + stairs in radius |
| 7 | Slow Poison | 4 | 7 | 32 | Halve zp_eff_poison (round up) |
| 8 | Blind Creature | 5 | 7 | 36 | Blind target monster (directional) |
| 9 | Portal | 5 | 9 | 38 | Short teleport (share Phase Door) |
| 10 | Cure Medium Wounds | 6 | 9 | 38 | Heal 3d8+3 |
| 11 | Chant | 6 | 11 | 42 | Set zp_eff_bless = 24+1d24 (stronger) |
| 12 | Sanctuary | 7 | 11 | 44 | Sleep all adjacent monsters |
| 13 | Remove Curse | 8 | 13 | 46 | Clear IF_CURSED on all equipped items |
| 14 | Cure Serious Wounds | 10 | 15 | 48 | Heal 5d8+5 |
| 15 | Dispel Undead | 12 | 17 | 52 | Damage all undead monsters in room |

#### Expanded Item Types (22 new, IDs 25-46)

**New Potions (IDs 25-31) — 7 new + 3 existing = 10 total:**

| ID | Name | Effect |
|----|------|--------|
| 25 | Cure Serious Wounds | Heal 5d8+5 |
| 26 | Restore Strength | Restore STR to base value |
| 27 | Heroism | Set zp_eff_hero = 10+1d10 |
| 28 | Restore Mana | Restore mana to max |
| 29 | Resist Heat/Cold | Set zp_eff_resist = 20+1d20 |
| 30 | See Invisible | Set zp_eff_see_inv = 20+1d20 |
| 31 | Blindness | Set zp_eff_blind = 10+1d10 (harmful) |

**New Scrolls (IDs 32-38) — 7 new + 3 existing = 10 total:**

| ID | Name | Effect |
|----|------|--------|
| 32 | Word of Recall | Set zp_eff_word_recall = 15+1d10 |
| 33 | Remove Curse | Clear IF_CURSED on equipped items |
| 34 | Enchant Weapon | +1 to equipped weapon p1 |
| 35 | Enchant Armor | +1 to equipped armor p1 |
| 36 | Monster Confusion | Next melee hit confuses monster |
| 37 | Aggravate Monsters | Wake all monsters on level |
| 38 | Protect from Evil | Set zp_eff_protect = 20+1d20 |

**Wands (IDs 39-42) — `ICAT_WAND = 14`:**

| ID | Name | Charges | Effect |
|----|------|---------|--------|
| 39 | Light | 10-15 | Light room (directional not needed) |
| 40 | Lightning | 5-8 | Bolt: 3d8 along line |
| 41 | Frost | 5-8 | Bolt: 4d8 along line |
| 42 | Stinking Cloud | 5-8 | Confuse target monster |

**Staves (IDs 43-46) — `ICAT_STAFF = 15`:**

| ID | Name | Charges | Effect |
|----|------|---------|--------|
| 43 | Light | 10-15 | Light room |
| 44 | Detect Monsters | 5-8 | Reveal monsters |
| 45 | Teleportation | 3-5 | Teleport self |
| 46 | Cure Light Wounds | 5-8 | Heal 1d8+1 |

### Implementation Steps

---

#### Step 7.0 — Extract Shared Effect Subroutines

**Goal:** Refactor existing potion/scroll effect code into reusable subroutines
callable from spells, potions, scrolls, wands, and staves. This is the foundation
that prevents code duplication across all of Phase 7.

**File:** `spell_effects.s` (new)

**Subroutines to extract/create:**

| Subroutine | Source | What it does |
|------------|--------|--------------|
| `eff_heal(A=amount)` | `player_items.s` quaff cure | Add pre-rolled 8-bit amount to HP, cap at max HP (16-bit). Callers roll dice separately via `math_dice`. (RP10-6: simplified from plan's dice-param API.) |
| `eff_light_room` | `player_items.s` scroll of light | Light current room tiles |
| `eff_teleport_self` | `player_items.s` scroll of teleport | find_random_floor, move player, update occupied flags |
| `eff_phase_door` | New | find_random_floor within 10 tiles of player |
| `eff_identify_prompt` | `player_items.s` scroll of identify | Prompt for slot, set id_known + IF_IDENTIFIED |
| `eff_cure_poison` | New (trivial) | `lda #0; sta zp_eff_poison` |
| `eff_detect_monsters` | New | Scan active monster table, mark positions FLAG_VISITED |
| `eff_confuse_adjacent` | New | Scan adjacent tiles, set MX_CONFUSE on monsters found |
| `eff_sleep_adjacent` | New | Scan adjacent tiles, clear MF_AWAKE + set MX_SLEEP_CUR |
| `eff_find_traps` | New | Scan visible radius, reveal hidden traps |
| `eff_find_doors` | New | Scan visible radius, reveal secret doors |
| `eff_bolt(dir, dice, sides)` | New | Bresenham line trace, damage first monster hit |
| `eff_remove_curse` | New | Scan equipment slots, clear IF_CURSED flags |
| `eff_aggravate` | New | Wake all monsters on level (set MF_AWAKE) |

**Steps:**
1. Create `spell_effects.s`. Add `#import` to `main.s`.
2. Extract `eff_heal` from `player_items.s:712-762` (the Cure Light Wounds HP
   addition + 16-bit cap logic). Parameterize: A=dice count, X=sides, Y=bonus.
   Replace original quaff code with `lda #1; ldx #8; ldy #1; jsr eff_heal`.
3. Extract `eff_light_room` from `player_items.s:910-960` (the Light scroll
   room-lighting loop). Replace original scroll code with `jsr eff_light_room`.
4. Extract `eff_teleport_self` from `player_items.s:1050-1100` (find_random_floor,
   clear old FLAG_OCCUPIED, move player, set new FLAG_OCCUPIED). Replace original
   with `jsr eff_teleport_self`.
5. Extract `eff_identify_prompt` from `player_items.s:980-1040` (prompt for
   inventory slot, set id_known, set IF_IDENTIFIED). Replace with call.
6. Write new subroutines: `eff_cure_poison`, `eff_detect_monsters`,
   `eff_confuse_adjacent`, `eff_sleep_adjacent`, `eff_find_traps`, `eff_find_doors`,
   `eff_remove_curse`, `eff_aggravate`. Each is ~30-60 bytes.
7. Write `eff_phase_door` — like `eff_teleport_self` but with distance check:
   call find_random_floor in a loop, accept first result within Chebyshev
   distance 10 of player (max 20 attempts, fall back to any floor).

**Tests:**
- Existing potion/scroll tests must still pass (verify refactor didn't break).
- New compile-time asserts for each new subroutine.
- Runtime test: `eff_heal` with known dice → verify HP change.
- Runtime test: `eff_detect_monsters` → verify monster tile gets FLAG_VISITED.

---

#### Step 7.1 — Spell Data Tables

**Goal:** Define the 32 spell/prayer data tables and name strings.

**File:** `spell_data.s` (new)

**Data structures:**

```
// Per-spell table (one array per field, 16 entries each for mage + priest)
mage_spell_mana:    .byte 1, 1, 2, 2, 3, 3, 3, 4, 5, 5, 6, 6, 7, 8, 10, 12
mage_spell_level:   .byte 1, 1, 1, 1, 3, 3, 5, 5, 7, 7, 9, 9, 11, 13, 15, 17
mage_spell_fail:    .byte 22, 23, 24, 26, 25, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 50
priest_spell_mana:  .byte 1, 1, 2, 2, 2, 3, 3, 4, 5, 5, 6, 6, 7, 8, 10, 12
priest_spell_level: .byte 1, 1, 1, 3, 3, 5, 5, 7, 7, 9, 9, 11, 11, 13, 15, 17
priest_spell_fail:  .byte 10, 15, 20, 24, 25, 27, 30, 32, 36, 38, 38, 42, 44, 46, 48, 52

// Name pointer tables (lo/hi, 16 entries each)
mage_spell_name_lo:  .byte <msn_0, <msn_1, ...
mage_spell_name_hi:  .byte >msn_0, >msn_1, ...
priest_spell_name_lo: .byte <psn_0, <psn_1, ...
priest_spell_name_hi: .byte >psn_0, >psn_1, ...

// Name strings (null-terminated PETSCII)
msn_0: .text "MAGIC MISSILE" ; .byte 0
msn_1: .text "DETECT MONSTERS" ; .byte 0
... (16 mage + 16 priest)
```

**Steps:**
1. Create `spell_data.s` with all tables above.
2. Add `#import` to `main.s`.
3. Compile-time asserts: table sizes match (16 entries each), mana values > 0,
   levels monotonically non-decreasing.

**Tests:**
- `.assert` for table element counts.
- `.assert` spot-checks: `mage_spell_mana[0] == 1`, `priest_spell_fail[15] == 52`.

---

#### Step 7.2 — Cast/Pray Commands (`player_magic.s`)

**Goal:** Implement the `m` (cast) and `p` (pray) commands. Player sees spell
list, selects a spell, failure/success is rolled, mana is deducted.

**File:** `player_magic.s` (new)

**Entry points:**
- `player_cast_spell` — called from main.s CMD_CAST dispatch
- `player_pray` — called from main.s CMD_PRAY dispatch
  (Both share most logic; only the table pointers and spell_type check differ.)

**Detailed logic for `player_cast_spell`:**
```
1. Check PL_SPELL_TYPE != SPELL_MAGE → print "YOU CANNOT CAST SPELLS." → clc, rts
2. Call spell_list_display (mage tables) — show known spells with mana costs
3. Prompt: "CAST WHICH SPELL? (A-P, ESC)" → input_get_key
4. ESC/space → cancel, clc, rts
5. Convert letter to spell index (A=0, B=1, ...)
6. Check bit in PL_SPELLS_KNOWN → if not known, "YOU DON'T KNOW THAT SPELL.", clc, rts
7. Check mana cost <= zp_player_mp → if insufficient, "NOT ENOUGH MANA.", clc, rts
8. Check spell min_level <= zp_player_lvl → if too low, "YOU'RE NOT EXPERIENCED ENOUGH.", clc, rts
9. Deduct mana: zp_player_mp -= cost; sync to player_data + PL_MANA
10. Roll failure: adjusted_fail = fail_base - 3*(level - spell_level) - spell_stat_bonus
    Clamp to [5, 95]. Roll rng_range(100): if roll < adjusted_fail → "YOUR SPELL FAILS.", sec, rts
11. Dispatch spell effect: jsr mage_effect_dispatch (CMP/BEQ chain on spell index)
12. Print effect-specific message. sec, rts (turn consumed)
```

**`spell_list_display` subroutine:**
```
1. screen_clear (or use message area — could use full-screen overlay like inventory)
2. Print header: "  SPELLS  MANA  LVL"
3. For each spell 0-15:
   a. Check if bit set in PL_SPELLS_KNOWN → if not, skip (or show "???" for unknown)
   b. Print letter (A-P), spell name, mana cost, min level
   c. If mana cost > zp_player_mp, show in dim color
4. Wait for keypress (the selection key, handled by caller)
```

**`player_pray` — identical structure but:**
- Check `PL_SPELL_TYPE == SPELL_PRIEST`
- Use `priest_spell_*` tables
- Use `priest_effect_dispatch`
- Messages say "PRAY" instead of "CAST"

**main.s dispatch additions** (insert before "Unknown command" at line ~659):
```
    // Cast spell?
    cmp #CMD_CAST
    bne !not_cast+
    jsr msg_clear
    jsr player_cast_spell
    bcc !cast_no_turn+
    jsr update_visibility     // Some spells change visibility
    jsr viewport_update
    jsr render_viewport
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr status_draw
    jmp !main_loop-
!cast_no_turn:
    jmp !main_loop-
!not_cast:

    // Pray?
    cmp #CMD_PRAY
    bne !not_pray+
    (same pattern, calling player_pray)
!not_pray:
```

**Steps:**
1. Create `player_magic.s`. Add `#import` to `main.s`.
2. Implement `spell_list_display` — full-screen overlay showing spell list.
   Use inventory display pattern from `ui_inventory.s` as template.
3. Implement `player_cast_spell` with the 12-step logic above.
4. Implement `player_pray` (thin wrapper changing table pointers + spell type).
5. Add `CMD_CAST` and `CMD_PRAY` dispatch blocks in `main.s` (before line 659).
6. Implement `calc_spell_failure` — the failure adjustment formula:
   `adjusted = fail_base - 3*(player_level - spell_level) - spell_stat_bonus[stat-3]`
   Clamped to [5, 95]. Uses `spell_stat_bonus` table already in `tables.s`.

**Tests:**
- Compile-time: assert mana deduction arithmetic.
- Runtime test: Set player as Mage, give all spells known (PL_SPELLS_KNOWN=$FFFF),
  set mana=10, cast spell 0 (Magic Missile, cost 1). Verify mana becomes 9.
- Runtime test: Set mana=0, attempt cast → verify "NOT ENOUGH MANA", carry clear.
- Runtime test: Warrior (SPELL_NONE) attempts cast → verify rejection message.
- Runtime test: Cast unknown spell (bit not set) → verify rejection.

---

#### Step 7.3 — Learn Spells on Level-Up + Mana Recalc

**Goal:** When the player levels up, check if new spells become available.
Recalculate max mana based on level + spell stat.

**File:** `player_magic.s` (append)

**Learn-spells logic (`magic_check_new_spells`):**
```
1. Get player's spell_type. If SPELL_NONE, rts.
2. Select table pointer (mage_spell_level or priest_spell_level).
3. For each spell index 0-15:
   a. If already known (bit set in PL_SPELLS_KNOWN), skip.
   b. If spell_level[i] <= zp_player_lvl:
      - Set bit in PL_SPELLS_KNOWN (use ORA with bit mask)
      - Print "YOU HAVE LEARNED <spell name>!"
4. Sync PL_SPELLS_KNOWN to player_data.
```

**Mana recalculation (`magic_recalc_mana`):**
```
1. Get spell_type. If SPELL_NONE → max_mana = 0, rts.
2. Get spell stat (INT for mage, WIS for priest): stat = zp_player_int or zp_player_wis
3. max_mana = (level * stat) / 8 + spell_stat_bonus[stat-3]
   (Simplified from umoria; gives reasonable progression)
4. Clamp max_mana to [1, 255]
5. Store to PL_MAX_MANA and zp_player_mmp
6. If PL_MANA > max_mana, set PL_MANA = max_mana (stat drain case)
```

**Bit mask helper table:**
```
spell_bit_mask:
    .byte $01, $02, $04, $08, $10, $20, $40, $80  // Bits 0-7 (lo byte)
spell_bit_hi_mask:
    .byte $01, $02, $04, $08, $10, $20, $40, $80  // Bits 8-15 (hi byte)
```
Spells 0-7 use lo byte with `spell_bit_mask`, spells 8-15 use hi byte with
`spell_bit_hi_mask`.

**Integration into level-up** (`combat.s:519-558`):
After `jsr player_calc_combat` (line 543), add:
```
    jsr magic_recalc_mana
    jsr magic_check_new_spells
```

**Starting spells** (`player_create.s`):
After mana initialization (~line 624), add:
```
    jsr magic_check_new_spells  // Learn level-1 spells at character creation
```

**Steps:**
1. Add `spell_bit_mask` table to `spell_data.s`.
2. Implement `magic_check_new_spells` in `player_magic.s`.
3. Implement `magic_recalc_mana` in `player_magic.s`.
4. Hook `magic_recalc_mana` + `magic_check_new_spells` into `combat_check_levelup`.
5. Hook `magic_check_new_spells` into `player_create.s` after mana init.

**Tests:**
- Runtime: Create Mage at level 1 → verify spells 0-3 known (all have min_level 1).
- Runtime: Set Mage to level 3, call `magic_check_new_spells` → verify spells 4-5
  now known.
- Runtime: Verify `magic_recalc_mana` with INT=12, level=5 → expected max_mana
  = (5*12)/8 + bonus[12-3] = 7 + 1 = 8. (RP10-4: bonus[9]=1 per `spell_stat_bonus` table.)

---

#### Step 7.4 — Mage Spell Effect Dispatch

**Goal:** Implement the 16 mage spell effects.

**File:** `player_magic.s` (effect dispatch) + `spell_effects.s` (shared code)

**Dispatch table** (called after successful cast):
```
mage_effect_dispatch:
    cmp #0
    beq !mage_eff_0+    // Magic Missile
    cmp #1
    beq !mage_eff_1+    // Detect Monsters
    ... (CMP/BEQ chain)
    rts                  // Unknown — no effect (safety)
```

**Effect implementations:**

| Spell | Implementation | Shared? |
|-------|---------------|---------|
| 0 Magic Missile | `eff_bolt(1,4,level/2)` — traces path, damages first monster hit | Shared bolt |
| 1 Detect Monsters | `jsr eff_detect_monsters` | Shared |
| 2 Phase Door | `jsr eff_phase_door` | Shared |
| 3 Light Area | `jsr eff_light_room` | Shared |
| 4 Cure Light Wounds | `lda #1; ldx #8; ldy #1; jsr eff_heal` | Shared |
| 5 Find Traps/Doors | `jsr eff_find_traps; jsr eff_find_doors` | Shared |
| 6 Stinking Cloud | `jsr eff_confuse_adjacent` | Shared |
| 7 Confusion | `get_direction_target` → find monster → set MX_CONFUSE | Partly new |
| 8 Lightning Bolt | `get_direction_target` → `lda #3; ldx #8; jsr eff_bolt` | Shared bolt |
| 9 Trap/Door Destroy | Scan radius, destroy traps + jam doors open | New |
| 10 Sleep I | `jsr eff_sleep_adjacent` | Shared |
| 11 Cure Poison | `jsr eff_cure_poison` | Shared |
| 12 Teleport Self | `jsr eff_teleport_self` | Shared |
| 13 Frost Bolt | `get_direction_target` → `lda #5; ldx #8; jsr eff_bolt` | Shared bolt |
| 14 Wall to Mud | `get_direction_target` → if wall tile, replace with floor | New |
| 15 Fire Ball | `lda #7; ldx #8; jsr eff_damage_adjacent` | New area dmg |

**New subroutines needed for this step:**
- `eff_bolt(A=dice, X=sides)` — Bresenham line trace from player in chosen
  direction. Step through tiles; stop at wall. If monster found, roll damage,
  apply to monster HP, check kill. Uses ZP $84-$87 for line state.
- `eff_damage_adjacent(A=dice, X=sides)` — Scan 8 adjacent tiles for monsters,
  roll damage for each, apply, check kills.
- `eff_directional_monster` — `get_direction_target`, find monster at target
  tile. Returns monster index in X or carry clear if no monster.

**Bresenham bolt algorithm (`eff_bolt`):**
```
1. Get direction from get_direction_target. Extract dx, dy from dir_dx/dir_dy.
2. Start at player position (px, py). Step: x += dx, y += dy each iteration.
3. For each step (max 20 iterations — longest dungeon dimension):
   a. Check bounds (0 < x < MAP_W-1, 0 < y < MAP_H-1).
   b. Read map tile. If wall → stop (bolt hits wall, no damage).
   c. Check for monster at (x, y) via monster_find_at.
   d. If monster found → roll damage, apply, check kill. Stop.
4. If bolt exits map or reaches max range → fizzle.
```
Note: This is a simplified "straight-line" bolt, not a full Bresenham with
fractional error — movement is exactly along the 8 cardinal/diagonal directions,
one tile per step. This matches how `dir_dx`/`dir_dy` work and is sufficient
for the dungeon's grid-based geometry.

**Steps:**
1. Implement `eff_bolt` in `spell_effects.s`.
2. Implement `eff_damage_adjacent` in `spell_effects.s`.
3. Implement `eff_directional_monster` in `spell_effects.s`.
4. Implement `mage_effect_dispatch` in `player_magic.s` with all 16 effects.
5. Hook up to `player_cast_spell` (JSR to dispatch after successful cast).

**Tests:**
- Runtime test: Cast Magic Missile with monster adjacent → verify damage applied.
- Runtime test: Cast Light Area → verify room tiles get FLAG_LIT.
- Runtime test: Cast Teleport Self → verify player moved.
- Runtime test: Cast Lightning Bolt toward monster 3 tiles away → verify damage.
- Runtime test: Cast Lightning Bolt toward wall → verify no damage, bolt stops.
- Runtime test: Cast Cure Light Wounds → verify HP increases.

---

#### Step 7.5 — Priest Prayer Effect Dispatch

**Goal:** Implement the 16 priest prayer effects. Many share code with mage spells.

**File:** `player_magic.s` (append)

**Dispatch + implementations:**

| Prayer | Implementation | Shared with |
|--------|---------------|-------------|
| 0 Detect Evil | `jsr eff_detect_monsters` | Mage #1 |
| 1 Cure Light Wounds | `lda #1; ldx #8; ldy #1; jsr eff_heal` | Mage #4 |
| 2 Bless | `lda #12; jsr rng_range; clc; adc #12; sta zp_eff_bless` | New (tiny) |
| 3 Remove Fear | (Placeholder — clear future fear timer) | New (tiny) |
| 4 Call Light | `jsr eff_light_room` | Mage #3 |
| 5 Find Traps | `jsr eff_find_traps` | Mage #5 (half) |
| 6 Detect Doors/Stairs | `jsr eff_find_doors` (incl stairs) | Mage #5 (half) |
| 7 Slow Poison | `lda zp_eff_poison; lsr; ora #1; sta zp_eff_poison` | New (tiny) |
| 8 Blind Creature | `jsr eff_directional_monster` → set stun on monster | New |
| 9 Portal | `jsr eff_phase_door` | Mage #2 |
| 10 Cure Medium Wounds | `lda #3; ldx #8; ldy #3; jsr eff_heal` | Shared heal |
| 11 Chant | `lda #24; jsr rng_range; clc; adc #24; sta zp_eff_bless` | Like Bless |
| 12 Sanctuary | `jsr eff_sleep_adjacent` | Mage #10 |
| 13 Remove Curse | `jsr eff_remove_curse` | Shared |
| 14 Cure Serious Wounds | `lda #5; ldx #8; ldy #5; jsr eff_heal` | Shared heal |
| 15 Dispel Undead | Scan visible monsters, if undead → 1d3*level damage | New |

**New monster flag needed:** `CF_UNDEAD = $02` in `cr_mflags`. No current tier-0
monsters are undead, but the flag is needed for future tiers. Dispel Undead will
check `cr_mflags[type] & CF_UNDEAD` before applying damage. For now, this spell
effectively does nothing (no undead in levels 1-5), which is correct — priests
learn it at level 17 and should be in deeper tiers by then.

**Steps:**
1. Add `CF_UNDEAD` constant to `monster.s`.
2. Implement `priest_effect_dispatch` in `player_magic.s`.
3. Each shared effect is a JSR to the corresponding subroutine.
4. Implement Bless/Chant (set `zp_eff_bless` timer with different durations).
5. Implement Blind Creature (directional monster + set MX_STUN timer).
6. Implement Dispel Undead (scan active monsters, check CF_UNDEAD, damage).

**Tests:**
- Runtime: Priest casts Bless → verify zp_eff_bless > 0.
- Runtime: Priest casts Cure Medium Wounds → verify HP gain is in [6, 27] range.
- Runtime: Priest casts Remove Curse with cursed equipped item → verify IF_CURSED
  cleared.
- Runtime: Priest casts Slow Poison with poison timer 10 → verify timer becomes 5.

---

#### Step 7.6 — Expanded Potions and Scrolls ✅ COMPLETE

**Goal:** Add 7 new potions and 7 new scrolls. Expand item type tables and
identification system. ITEM_TYPE_COUNT goes from 25 → 39.

**Files modified:** `item.s`, `player_items.s`, `zeropage.s`, `combat.s`,
`tests/test_item.s`, `run_tests.sh`

**New item types (14 total, IDs 25-38):**

| ID | Category | Name | Effect |
|----|----------|------|--------|
| 25 | Potion | Cure Serious Wounds | Heal 5d8+5 via eff_heal |
| 26 | Potion | Restore Mana | Set zp_player_mp = zp_player_mmp |
| 27 | Potion | Heroism | Set zp_eff_hero timer (rng(25)+25) |
| 28 | Potion | Blindness | Set zp_eff_blind timer (rng(100)+100) — harmful |
| 29 | Potion | Confusion | Set zp_eff_confuse timer (rng(15)+10) — harmful |
| 30 | Potion | Detect Monsters | jsr eff_detect_monsters |
| 31 | Potion | Infravision | Set zp_eff_infra timer (rng(50)+50) |
| 32 | Scroll | Word of Recall | Set zp_eff_word_recall (rng(15)+15) |
| 33 | Scroll | Remove Curse | jsr eff_remove_curse |
| 34 | Scroll | Enchant Weapon | Find EQUIP_WEAPON, inc inv_p1 (cap +5) |
| 35 | Scroll | Enchant Armor | Find EQUIP_BODY, inc inv_p1 (cap +5) |
| 36 | Scroll | Monster Confusion | Set zp_confuse_melee = 1 |
| 37 | Scroll | Aggravate | jsr eff_aggravate |
| 38 | Scroll | Protect from Evil | Set zp_eff_protect timer (rng(25)+25) |

**What was implemented:**

1. **`zeropage.s`** — Renamed `zp_spare_4f` → `zp_confuse_melee` ($4f): flag for
   Monster Confusion scroll's one-time confuse-on-melee-hit effect.

2. **`item.s` — SoA table extensions (14 new entries):**
   - Extended all 10 SoA arrays (`it_category`, `it_display`, `it_color`,
     `it_weight`, `it_dmg_dice`, `it_dmg_sides`, `it_base_ac`, `it_cost_lo/hi`,
     `it_min_level`) from 25 → 39 entries.
   - Added 14 name strings (`itn_25`..`itn_38`), extended `it_name_lo/hi`.
   - Extended `id_known` with 14× 0 (unknown at start).

3. **`item.s` — Lookup tables for non-contiguous type IDs:**
   - Potion types at IDs 17-19 and 25-31 are non-contiguous; scrolls at 20-22
     and 32-38. The old `sbc #17` / `sbc #20` approach breaks.
   - Added two 39-byte lookup tables: `potion_local_idx` and `scroll_local_idx`.
     Indexed by type ID → local category index (0-9), or $FF if not that category.
   - Rewrote `item_get_name_ptr` and `item_get_floor_color` potion/scroll branches
     to use lookup tables instead of subtraction.

4. **`item.s` — Expanded identification system:**
   - Expanded shuffle tables from 5 to 12 entries each (10 types, 12 descriptors).
   - Added 7 new potion descriptors: "AZURE", "SMOKY", "BROWN", "SILVER", "PINK",
     "CLOUDY", "GOLDEN".
   - Added 7 new scroll descriptors: "LUMEN", "VERITAS", "DURA", "LIBERA",
     "ACUTA", "FEROX", "TUTELA" (Latin-themed).
   - Expanded `potion_name_lo/hi`, `scroll_name_lo/hi` from 5 to 12 entries.
   - Expanded `potion_colors`, `scroll_colors` from 5 to 12 entries.
   - Updated `item_init_identification`: shuffle init `ldx #4` → `ldx #11`,
     Fisher-Yates loops `ldx #4` → `ldx #11`.

5. **`item.s` — Updated `pick_item_type`:**
   - Changed range from `rng_range(23) + 2` → `rng_range(37) + 2` (giving [2,38]).

6. **`item.s` — Updated compile-time asserts:**
   - `ITEM_TYPE_COUNT` assert from 25 to 39.

7. **`player_items.s` — 7 new potion handlers in `item_quaff`:**
   - CSW: Roll 5d8 via loop, add 5, jsr eff_heal. Msg: "YOU FEEL MUCH BETTER."
   - Restore Mana: Set MP=max MP. Msg: "YOUR MIND FEELS CLEAR."
   - Heroism: Timer → zp_eff_hero. Msg: "YOU FEEL HEROIC!"
   - Blindness: Timer → zp_eff_blind. Msg: "YOU CAN'T SEE!"
   - Confusion: Timer → zp_eff_confuse. Msg: "YOU FEEL DIZZY."
   - Detect Monsters: jsr eff_detect_monsters. Msg: "YOU SENSE NEARBY CREATURES."
   - Infravision: Timer → zp_eff_infra. Msg: "YOUR EYES TINGLE."
   - Dispatch uses JMP trampolines for branch distance.

8. **`player_items.s` — 7 new scroll handlers in `item_read_scroll`:**
   - Word of Recall: Timer → zp_eff_word_recall. Msg: "THE AIR CRACKLES AROUND YOU."
   - Remove Curse: jsr eff_remove_curse. Msg: "YOU FEEL CLEANSED."
   - Enchant Weapon: Inc inv_p1 at EQUIP_WEAPON (cap +5). Msg: "YOUR WEAPON GLOWS BRIEFLY."
   - Enchant Armor: Inc inv_p1 at EQUIP_BODY (cap +5). Msg: "YOUR ARMOR GLOWS BRIEFLY."
   - Monster Confusion: Set zp_confuse_melee=1. Msg: "YOUR HANDS BEGIN TO GLOW."
   - Aggravate: jsr eff_aggravate. Msg: "YOU HEAR A HIGH-PITCHED HUMMING."
   - Protect from Evil: Timer → zp_eff_protect. Msg: "YOU FEEL PROTECTED."
   - No weapon/armor → "YOU FEEL A STRANGE VIBRATION." (enchant scrolls).
   - 17 new message strings added.

9. **`combat.s` — Confuse-on-hit check:**
   - After `sta cmb_any_hit` (first hit scored), checks `zp_confuse_melee`.
   - If set: clears flag (one-time use), sets monster MX_CONFUSE timer to 20.
   - zp_ptr0 still points to monster entry (set by `monster_get_ptr` earlier).

10. **`tests/test_item.s` — 6 new runtime tests (tests 33-38):**
    - Test 33: CSW potion heals HP in [60, 95] (from 50, heal 10-45).
    - Test 34: Restore Mana sets MP = max MP (5 → 30).
    - Test 35: Enchant Weapon scroll increments p1 (2 → 3).
    - Test 36: Word of Recall sets zp_eff_word_recall in [15, 29].
    - Test 37: Blindness potion sets zp_eff_blind in [100, 199].
    - Test 38: pick_item_type returns new types (>= 25) at deep dungeon levels.
    - Updated test 21 range check from `cmp #25` → `cmp #39`.
    - Expanded tc_results buffer from 30 → 40, copy loop from 31 → 37.

11. **`run_tests.sh`** — Updated item test expected count from 32 → 38,
    result range from `0400 041f` → `0400 0425`.

**Shared subroutines reused from `spell_effects.s`:**
- `eff_heal` (line 28) — add pre-rolled amount to player HP
- `eff_detect_monsters` (line 264) — reveal monsters on map
- `eff_remove_curse` (line 313) — clear IF_CURSED on equipment
- `eff_aggravate` (line 1046) — wake all monsters

**Verification:**
- `make build` → 56 asserts, 0 failed ✅
- `make test` → 12/12 suites pass (item: 38/38 tests) ✅

---

#### Step 7.7 — Wands and Staves ✅ COMPLETE

**Goal:** Implement wand aiming and staff usage with charge tracking.

**Files modified:** `player_items.s`, `main.s`, `item.s`, `tests/test_wands_staves.s`, `run_tests.sh`

**What was implemented:**

1. **`item.s` — Wands and Staves data:**
   - Added SoA entries for item IDs 39-46 (4 wands, 4 staves).
   - Added descriptor tables and shuffling logic (wands: metal/wood types; staves: wood types).
   - Updated `pick_item_type` to include the new range [39, 46].
   - Updated `roll_enchantment` to initialize charges (p1).

2. **`player_items.s` — Logic:**
   - Implemented `item_aim_wand`: prompts for direction, checks charges, consumes charge, fires effect.
   - Implemented `item_use_staff`: checks charges, consumes charge, fires effect.
   - Effects wired: Light, Lightning, Frost, Stinking Cloud (Wands); Light, Detect Monsters, Teleport, Cure Light Wounds (Staves).

3. **`main.s` — Dispatch:**
   - Added `CMD_AIM` ('a') key dispatch.
   - Added `CMD_USE` ('Z') key dispatch.

**Verification:**
- Created `tests/test_wands_staves.s` runtime test suite.
- Verified generation of wands/staves with charges.
- Verified consumption of charges and effect triggering.
- Fixed test bugs (Step 9.4): `rts`→`brk` terminator; keyboard buffer needs 2 keys (slot + -more-).
- `make test` pass (17/17 suites).

---

#### Step 7.8 — Monster Magic (`monster_magic.s`) ✅ COMPLETE

**Goal:** Monsters with spellcasting ability can use ranged spells and breath
weapons instead of (or in addition to) melee attacks.

**What was done:**

The `monster_magic.s` framework (monster_can_cast, monster_pick_spell, 7 spell
handlers, AI hook) was already fully implemented. This step activated it by:

1. **Added 6 spellcasting dungeon creatures** (IDs 20-25) to `monster.s`:
   - Kobold Shaman (L3): 30% spell, bolt + heal
   - Giant White Ant Lion (L4): no spells, pure melee 2d4
   - Novice Mage (L4): 40% spell, bolt + confuse + blind
   - Novice Priest (L4): 35% spell, heal + summon
   - Giant Salamander (L5): 25% spell, breath
   - Orc Shaman (L5): 35% spell, bolt + confuse + heal

2. **Updated constants:** DUNGEON_CREATURES=26, TOWN_CREATURE_BASE=26,
   CREATURE_COUNT=32. Town creatures shifted to IDs 26-31.

3. **Fixed bug:** `monster_cast_summon` used CREATURE_COUNT (included town
   creatures); changed to DUNGEON_CREATURES.

4. **Moved MSF_* spell flag constants** from `monster_magic.s` to `monster.s`
   (needed by cr_spell_flags data arrays at assembly time).

5. **Bumped CREATURE_BASE** from $B200 to $B300 in `memory.s` to accommodate
   larger program. Reduced BFS_QUEUE_MAX from 1792 to 1664 (still far exceeds
   typical dungeon floor tile counts of ~400).

**Tests:** `tests/test_monster_magic.s` — 8 runtime tests:
1. monster_can_cast returns clear for spell_chance=0
2. monster_can_cast returns set for 100% chance + clear LOS
3. monster_can_cast fails when out of range (>8 tiles)
4. monster_can_cast fails with wall blocking LOS
5. Bolt damage in expected range [5, 19] (2d8+3)
6. Breath damage = HP/3 (30 HP → 10 damage)
7. Blind sets timer in [11, 20] (1d10+10)
8. Heal increases monster HP, capped at max

---

#### Step 7.9 — Mana Regeneration + Word of Recall ✅ COMPLETE

**Goal:** Mana regenerates over time. Word of Recall timer, when expired,
teleports the player between town and dungeon.

**Files modified:** `turn.s`, `main.s`, `tests/test_effects.s`

**What was implemented:**

1. **`turn.s` — Mana regeneration (lines 196-218):**
   - Spell-casting classes (PL_SPELL_TYPE != 0) regen 1 MP every 2 turns.
   - If `zp_eff_regen` active, regen rate doubles to 1 MP per turn.
   - Warriors skip mana regen entirely.
   - MP capped at max MP (`zp_player_mmp`).

2. **`turn.s` — Word of Recall (lines 138-194):**
   - Timer countdown in `turn_tick_effects`: when `zp_eff_word_recall` reaches 0,
     teleport triggers.
   - In dungeon (dlvl > 0) → teleport to town (dlvl = 0).
   - In town (dlvl = 0) → teleport to deepest level reached (`PL_MAX_DLVL`).
   - Fizzle if `PL_MAX_DLVL = 0` (player has never entered the dungeon).
   - Full level regeneration: `level_generate` + `monster_spawn_level` +
     `item_spawn_level` + visibility + viewport.
   - Messages: "YOU FEEL YOURSELF YANKED AWAY!" on teleport,
     "THE SPELL FIZZLES." on fizzle.

3. **`main.s` — Max depth tracking (lines 470-474):**
   - Stairs-down handler updates `PL_MAX_DLVL` when `zp_player_dlvl` exceeds it.

4. **`tests/test_effects.s` — Tests 11-14, 20-21:**
   - Test 11: Mage mana regen — MP increases after 2 turns.
   - Test 12: Warrior no mana regen — MP unchanged.
   - Test 13: Word of Recall dungeon→town — dlvl becomes 0.
   - Test 14: Word of Recall town→dungeon — dlvl becomes PL_MAX_DLVL.
   - Test 20: Recall fizzle — PL_MAX_DLVL=0 prevents teleport.
   - Test 21: Extra regen — MP increases every turn with zp_eff_regen active.

**Verification:**
- `make build` → all asserts pass ✅
- `make test` → all suites pass ✅

---

#### Step 7.10 — Integration, Polish, and Full Test Pass ✅ COMPLETE

**Goal:** Wire everything together, verify all commands work end-to-end,
fix edge cases.

**Files modified:** `player_magic.s`, `player_items.s`, `sound.s`, `ui_help.s`,
`ui_character.s`, `ui_status.s`

**What was implemented:**

1. **Confusion + casting (`player_magic.s:163-170`):**
   - When `zp_eff_confuse > 0`, casting randomly selects a spell via
     `rng_range(spell_count)` instead of using player's choice.

2. **Blindness + scrolls (`player_items.s:1030-1040`):**
   - `item_read_scroll` checks `zp_eff_blind` at entry; if nonzero, prints
     "YOU CAN'T SEE TO READ!" and aborts (no turn consumed).

3. **Hunger + spell failure (`player_magic.s:653-665`):**
   - When `zp_hunger_state >= HUNGER_FAINT`, adds +20 to spell failure roll,
     making spells much more likely to fail while fainting.

4. **Sound effects (`sound.s:46-47`):**
   - `SFX_SPELL` ($06): short mystical tone on successful cast.
   - `SFX_SPELL_FAIL` ($07): low buzz on failed cast.

5. **Help screen (`ui_help.s:136-138`):**
   - Added M=cast spell, P=pray, A=aim wand, Z=use staff to key listing.

6. **Character sheet (`ui_character.s:239-263`):**
   - Displays "SPELLS: N/16" showing number of spells known.

7. **Status bar mana (`ui_status.s:221-243`):**
   - Displays "MP:nn/nn" for spell-casting classes, updates after casting.

**Verification:**
- All 4 commands (M, P, A, Z) work end-to-end with success/failure messages.
- Cancellation works cleanly at every prompt.
- `make build` → all asserts pass ✅
- `make test` → all suites pass ✅

---

### Implementation Order and Dependencies

```
Step 7.0 (Shared Effects) ──────────┐
                                     │
Step 7.1 (Spell Tables) ───────┐    │
                                │    │
Step 7.2 (Cast/Pray Commands) ─┤    │
         depends on 7.0, 7.1   │    │
                                │    │
Step 7.3 (Learn/Mana Recalc) ──┤    │
         depends on 7.1        │    │
                                ▼    ▼
Step 7.4 (Mage Effects) ───────────────┐
         depends on 7.0, 7.2           │
                                        │
Step 7.5 (Priest Effects) ─────────────┤
         depends on 7.0, 7.2           │
                                        │
Step 7.6 (Potions/Scrolls) ───────────┤
         depends on 7.0                │
                                        │
Step 7.7 (Wands/Staves) ──────────────┤
         depends on 7.0, bolt from 7.4 │
                                        │
Step 7.8 (Monster Magic) ─────────────┤
         depends on bolt from 7.4      │
                                        │
Step 7.9 (Mana Regen/Recall) ─────────┤
         depends on 7.3                │
                                        ▼
Step 7.10 (Integration/Polish) ─── all steps complete
```

**Recommended implementation sequence:**
1. **7.0** → 2. **7.1** → 3. **7.2** + **7.3** → 4. **7.4** → 5. **7.5** →
6. **7.6** → 7. **7.7** → 8. **7.8** → 9. **7.9** → 10. **7.10**

Each step is independently testable and committable. Steps 7.4 and 7.5 can
potentially be done in one pass since they share the dispatch pattern. Steps
7.6 and 7.7 are largely independent of the spell system (they're item-based)
and could be parallelized.

---

## Review Pass — Missing Features & Known Gaps

Findings from code review against full umoria feature set. Organized by system.
Items marked **(deferred)** are intentional simplifications documented in the
design; items marked **(TODO)** need implementation.

### 1. Combat System

**Missing features:**

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R1.1 | Ranged combat (bows, crossbows, slings) | ✅ **DONE** | `ranged_fire.s` — 3 launchers (bow, crossbow, sling), 3 ammo types (arrow, bolt, rock), SHIFT+F fire command, ammo stacking on pickup, melee unarmed fallback for ranged weapons. 6 new item types (IDs 49-54), `it_missile[]` SoA array. |
| R1.2 | Throwing items | ✅ **DONE** | `throw.s` — SHIFT+T throws any inventory item. BOW-based to-hit at 75%, STR-based range calc, projectile trace reuses ranged_fire pattern. Potions shatter on impact, other items land on floor. 6 tests in `test_throw.s`. |
| R1.3 | Monster attacks | ✅ **DONE** | `monster_attack.s` fully implemented (Phase 5.4). 8 attack types, 2 slots per creature, all effects (poison, confuse, paralyze, acid, aggravate). |
| R1.4 | Monster spells | ✅ **DONE** | `monster_magic.s` fully implemented (Phase 7.8). Breath weapons, bolts, summoning, blindness, confusion. Creature tier data has spell entries. |

**Issues:**

| # | Issue | Status | Notes |
|---|-------|--------|-------|
| R1.5 | Blows calculation simplified | **(deferred)** | Currently a 4×5 table (weight class × DEX). Original uses STR, weapon weight, and character level. Consider upgrading if combat feels flat. |
| R1.6 | AC calculation simplified | **(deferred)** | Review whether current AC formula produces adequate difficulty curve. |

### 2. Dungeon Generation

**Missing features:**

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R2.1 | Special rooms (vaults, pits, nests) | ✅ **DONE** | Monster pits (dlvl>=5, 4-8 same type), treasure vaults (dlvl>=8, secret door entrance, enhanced loot), nests (dlvl>=3, 3-6 mixed weak monsters + gold). At most 1 per level. Code at $F000 (RAM under KERNAL ROM) with trampolines. |
| R2.2 | Magma/quartz streamers with treasure | ✅ **DONE** | 5 streamers per level (3 magma + 2 quartz), placed during dungeon generation. Treasure in veins not yet implemented. |
| R2.3 | Level persistence on stair transitions | **(deferred)** | Levels regenerate on each visit. True persistence would require per-level disk save — too much I/O for 1541. Acceptable simplification. |
| R2.4 | Secret door generation | ✅ **DONE** | `place_secrets` enabled (Phase 4.6). 1-3 closed doors converted to TILE_SECRET per level. Context-aware rendering. `do_search` reveals with 1-in-6 chance. |

### 3. Monsters & AI

**Missing features:**

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R3.1 | Pathfinding | **(deferred)** | Greedy movement (try diagonal, then cardinal). No A*/flow maps. Monsters can get stuck on corners. A* is expensive at 1 MHz; greedy + unstick heuristic may be sufficient. |
| R3.2 | Group/pack tactics | **(TODO)** | No pack instinct, escort behavior, or group spawning beyond random clusters. |
| R3.3 | Explosive breeders | **(TODO)** | No breeding logic (lice, mice, etc.). Need spawn-on-turn mechanic with population cap. |
| R3.4 | Monster fleeing | ✅ **DONE** | Monsters flee when HP < 25% of max. Flee threshold computed at spawn (HP/4). Reversed greedy movement (monster_move_away). Fleeing suppresses attack. CF_ATTACK_ONLY creatures can't flee (can't move). Confusion overrides flee. |
| R3.5 | Limited creature roster | ✅ **DONE** | Expanded to 120 creatures across 5 tiers (T0 town + T1-T4 dungeon). REU + disk loading paths implemented. All 12 steps complete (R3.5.1-R3.5.12). See **R3.5 Detailed Plan** below. |

### 4. Items & Inventory

**Missing features:**

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R4.1 | Ego items | **(TODO)** | No "Holy Avenger", "Defender", "Slay Evil", etc. Need ego flag + modifier table + name generation. |
| R4.4 | Pseudo-ID | **(TODO)** | No "feeling" about items (excellent, terrible, etc.). Need carry-time counter + quality hint based on hidden enchantment. |
| R4.5 | Thorough identification | **(TODO)** | `eff_identify_prompt` sets identified flag but doesn't reveal hidden powers (since ego items don't exist yet). Depends on R4.1. |
| R4.6 | Flasks of Oil | **(TODO)** | Consumable item to refuel Brass Lanterns. In umoria: `TV_FLASK` type, sold at General Store for 7,500 turns of fuel per flask. Player uses flask ('F'uel or 'r'efill command) on equipped lantern, adding charges up to lantern max (250 charges × 30 = 7,500 turns). Does NOT work on torches (torches are disposable). Need: new item type entry in `item.s` SoA tables, General Store inventory category update, refuel command in `player_items.s`, charge addition capped at lantern max. RP17-1 light duration fix is done. |

### 5. Magic System

**Missing features:**

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R5.1 | Advanced spells | **Done** ✅ | All 32 spell/prayer effects implemented (16 mage + 16 priest). Ball spells, enchantments, detection, healing all functional. |
| R5.2 | Full spellbook set | **Done** ✅ | 8 books total (4 mage + 4 priest). Each covers 4 spells. Book-gated learning on level-up + manual study ('G'). Books not consumed. |

### 6. Town & Stores

**Missing features:**

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R6.1 | Haggling | **Done** | Multi-round buy/sell haggling. 4 rounds max, gap/4 convergence, insult/kick system (3 insults = kicked). Items ≤10 GP use simple Y/N. Number input with 5-digit limit, DELETE support. |
| R6.2 | Black Market (Store 7) | **Done** | Store index 6. All item categories ($FFFF mask). Buy=base×3, sell=base/10, no CHR adjustment. No haggling (Y/N only). Building at (37,3), door (42,7). Owner: "THE FENCE". |
| R6.3 | Player Home (Store 8) | **Done** | Store index 7. Free deposit/retrieve, no pricing. Separate UI at $F000 (D/R/Q menu). No restocking — items persist. Saved with game state (SAVE_VERSION $05). Building at (42,20), door (47,24). |
| R6.4 | Advanced restocking | **(deferred)** | Currently 50% chance per slot on town re-entry. Original restocks based on turn count and dungeon depth. Current approach is acceptable simplification. |

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

### Priority Triage (updated 2026-02-17)

**Completed since original triage:**
- ~~R1.1 Ranged combat~~ — ✅ ranged_fire.s (bows, crossbows, slings, ammo stacking)
- ~~R1.3 Monster attacks~~ — ✅ Phase 5.4
- ~~R1.4 Monster spells~~ — ✅ Phase 7.8 (monster_magic.s)
- ~~R2.2 Mineral streamers~~ — ✅ 5 streamers per level (3 magma + 2 quartz)
- ~~R2.4 Secret doors~~ — ✅ Phase 4.6 (place_secrets + do_search)
- ~~R3.5 Creature roster~~ — ✅ R3.5.1-R3.5.12 (120 creatures, 5 tiers, REU + disk)
- ~~A1 File naming~~ — ✅ THE.GAME, HALL.OF.FAME, MONSTER.DB.1-4
- ~~A2 Directory art~~ — ✅ PETSCII title card via tools/diskart.py

**High priority (from AUDIT — polish & release readiness):**
- ~~A5 Stack depth audit~~ — ✅ max 27 bytes (11%), safe, no canary needed
- ~~A3 Character disk strategy~~ — ✅ dual-disk mode with swap prompts

**Medium priority (significant missing content):**
- ~~R3.4 Monster fleeing~~ — ✅ Done
- ~~R2.1 Special rooms~~ — ✅ Done (pits, vaults, nests with $F000 banking)
- ~~R4.1 Ego items~~ — ✅ Done
- ~~R5.1/R5.2 Spell expansion~~ — ✅ Done (8 spellbooks, book-gated learning)
- ~~R6.1 Store haggling~~ ✅

**Medium priority (infrastructure for more content):**
- ~~R7.1-R7.2 Huffman codec + resident compressed strings~~ ✅
- ~~R7.3 Store dialog strings~~ ✅
- R7.4-R7.5 Overlay string banks + REU cache — Tier 2, when resident space is exhausted

**Low priority (polish/completeness):**
- ~~R1.2 Throwing~~ ✅
- R3.2 Group tactics — nice-to-have
- R3.3 Breeders — nice-to-have (lice, mice spawn-on-turn)
- R4.4 Pseudo-ID — QoL feature
- R4.6 Flasks of Oil — lantern refueling (RP17-1 light duration fix done)
- ~~R7.6 Combat/UI string migration~~ ✅
- R7.7 Monster recall text — depends on R3.6 (monster recall feature)
- ~~R6.2 Black Market~~ ✅
- ~~R6.3 Player Home~~ ✅
- A4 Separate binaries — Phase 10 scope (BOOT.PRG + MORIA64 + MORIA128)
- A6 Large file split — opportunistic refactoring (dungeon_gen.s, item.s)
- A7 Item generation distribution review vs umoria curves

---

## R3.5 Detailed Plan — Creature Roster Expansion + REU Support

### Problem

Only 32 creature types (26 dungeon levels 1–5, 6 town). Umoria has 247 covering
levels 0–100. The dungeon becomes stale quickly once the player outlevelscreatures.
All creature data is currently embedded in program code (~1,097 bytes).

### Data Budget

Per-creature cost: 20 bytes (SoA arrays) + ~15 bytes (name string avg) = ~35 bytes.

| Roster size | SoA bytes | Name bytes | Total |
|-------------|-----------|------------|-------|
| 32 (current) | 640 | 457 | ~1.1 KB |
| 120 (target) | 2,400 | ~1,800 | ~4.2 KB |
| 247 (full umoria) | 4,940 | ~3,700 | ~8.5 KB |

Any REU (128 KB minimum) can trivially hold the full 8.5 KB roster plus item
tiers, recall data, etc. The C128's native 128 KB can also hold everything.

### Architecture: Two Paths

**Path A — REU detected (or C128 expanded memory):**
- At startup, load ALL creature data from disk into REU in one batch (~8.5 KB,
  ~3 sec with fastloader, one-time cost).
- On dungeon level change, DMA the needed creature data from REU → working RAM
  buffer. DMA transfer is near-instant (~1 cycle/byte, <10ms for a tier).
- No disk I/O after startup. Seamless tier transitions.
- Full 247-creature roster available.

**Path B — Unexpanded C64 (no REU):**
- Creature data split into overlapping tier files on disk:
  - `cr_tier0.dat`: Town creatures (level 0) — always resident in program code
  - `cr_tier1.dat`: Levels 1–8 (~30 creatures, ~1 KB)
  - `cr_tier2.dat`: Levels 5–15 (~35 creatures, ~1.2 KB)
  - `cr_tier3.dat`: Levels 11–25 (~35 creatures, ~1.2 KB)
  - `cr_tier4.dat`: Levels 20–40 (~30 creatures, ~1 KB)
- Tiers overlap by ~4 levels so the spawn window (`dlvl-2` to `dlvl+3`) never
  falls outside loaded data.
- Two adjacent tiers loaded simultaneously into $A000 bank (~2.2 KB).
- Tier change triggered on staircase transition when new dlvl crosses a tier
  boundary. Show "DESCENDING..." during the 1–3 sec disk load.
- Reduced roster (~120 creatures) to keep tier files small for stock 1541 speed.

### REU Interface

REU registers at $DF00–$DF0A (memory-mapped I/O):
- $DF00: Status register (read-only)
- $DF01: Command register (transfer type + execute/trigger mode)
- $DF02–$DF03: C64 base address (16-bit)
- $DF04–$DF06: REU base address (24-bit: lo, hi, bank)
- $DF07–$DF08: Transfer length (16-bit)

DMA transfer types: 00 = C64→REU (stash), 01 = REU→C64 (fetch), 10 = swap.

REU detection: write test pattern to $DF02/$DF03, read back, verify. If match,
REU is present. Size detection: attempt writes at bank boundaries ($DF06) to
determine 128 KB / 256 KB / 512 KB.

### Title Screen Display

When REU is detected, show on the title screen (e.g., row 12 or below the
"COMMODORE 64 EDITION" line):

```
REU DETECTED: 256KB
```

If no REU, show nothing (or optionally "UNEXPANDED C64"). This tells the player
whether they'll get the full creature roster or the tiered subset.

### Implementation Steps

| Step | Description |
|------|-------------|
| R3.5.1 | ✅ **Define creature roster.** Select ~120 creatures from umoria covering levels 0–40. Map each creature's SoA fields (display, color, speed, flags, level, HP dice, AC, sleep, aaf, XP, attacks, spells). Assign to tier groups with overlapping level ranges. |
| R3.5.2 | ✅ **Creature data file format.** Design binary format for tier files: header (count, level range, SoA block offsets) + SoA data blocks + name string table. Write assembler tool or standalone .s files that produce tier .dat files. |
| R3.5.3 | ✅ **REU detection + size probe.** New `reu.s` module: `reu_detect` (sets `reu_present` flag + `reu_size_kb`), `reu_stash` (C64→REU), `reu_fetch` (REU→C64). Call `reu_detect` at startup before title screen. |
| R3.5.4 | ✅ **Title screen REU display.** If `reu_present`, render "REU: xxxKB DETECTED" on the title screen below "COMMODORE 64 EDITION". |
| R3.5.5 | ✅ **Active creature buffer.** Expanded SoA arrays from 32→65 entries (57 dungeon + 8 town). `active_dungeon_count` variable, `load_tier_to_buffer` copies 22 SoA arrays from source to active buffer. All existing `lda cr_xxx,x` code works unchanged. |
| R3.5.6 | ✅ **REU loading path.** `reu_load_all_tiers` at startup loads 4 tier PRGs from disk → $E000 → REU DMA stash. `reu_fetch_tier` DMAs tier from REU → $E000 on transition. |
| R3.5.7 | ✅ **Disk loading path.** `tier_load_disk` uses KERNAL LOAD to load tier PRG from disk to $E000 (RAM under KERNAL ROM). Graceful fallback on failure. |
| R3.5.8 | ✅ **Tier transition logic.** `tier_check_transition` in stair handlers detects tier boundary crossings. Hysteresis via overlapping tier ranges prevents thrashing. `creature_get_name` handles KERNAL banking for name strings at $E000+. |
| R3.5.9 | ✅ **Town creatures always resident.** 6 town creatures embedded at indices 57-62 in program code (never loaded from disk). |
| R3.5.10 | ✅ **Full roster data entry.** Transcribe all ~120–247 creatures from umoria source into tier data files. Verify stats against umoria. **(Done — 120 creatures via parse_creatures.py)** |
| R3.5.11 | ✅ **Testing + bug fixes.** Fixed REU preload bug (`current_tier` not set before `tier_load_disk`), fixed post-loop `current_tier=4` stale state, added `reu_tiers_loaded` fallback counter, fixed Word of Recall skipping tier transition. 10 automated tests in `test_tier.s`. Tested both REU and non-REU paths in VICE. |
| R3.5.12 | ✅ **Fix `monster_init_table` cpx #384 truncation.** 6502 `cpx #imm` is 8-bit — `cpx #384` silently became `cpx #128`, only clearing 128 of 384 bytes. Fixed with two-pass loop. Added compile-time assert. |

### R3.5 Review Findings (2026-02-14)

**Architecture verified correct.** Comprehensive code review of monster.s, reu.s, tier_manager.s, memory.s, dungeon_gen.s, monster_magic.s, and all 5 tier data files.

**Confirmed working:**
- All 22 SoA arrays consistent across 5 tiers; compile-time assertions verify array sizes = MAX_CREATURES (65)
- `active_dungeon_count` variable correctly replaces old `DUNGEON_CREATURES` constant in `pick_creature_type` and `monster_cast_summon`
- `load_tier_to_buffer` copies all 22 arrays from $E000 source to active buffers
- `creature_get_name` properly handles KERNAL banking (SEI/$35) for name strings at $E000+
- REU detection: 3-stage bank probing (0-7, 8-15, 16-31), stash/fetch DMA verified
- `reu_load_all_tiers`: loads tiers 1-4 from disk → $E000 → REU bank 0 with sequential offsets
- `tier_load_disk`: KERNAL LOAD with PETSCII filenames "CR T1"-"CR T4"
- Tier transition hysteresis: T1=[1,8], T2=[5,15], T3=[11,25], T4=[20,100] — overlaps prevent thrashing
- Town creatures at indices 57-62 always resident (never loaded from disk)
- BFS queue now at screen RAM $0400-$07FF (512 entries × 2 bytes = 1024 bytes), moved from CREATURE_BASE to free up program space. SEI/CLI wraps prevent KERNAL IRQ cursor blink from corrupting queue.
- 19 test suites (17 at time of R3.5 review + test_tier + test_ranged); 13+ import reu.s + tier_manager.s; test_tier has 500M cycle limit

**Minor observations (non-blocking):**
- **Tight memory margin:** Program ends at $BF3F, CREATURE_BASE at $BFD0 — 145 bytes of headroom (after A3 dual-disk + streaming RLE fix). The compile-time assertion `program_end < CREATURE_BASE` catches overflow, but future code additions should be mindful of this margin.
- ~~**`monster_init_table` cpx #384:**~~ **Fixed in R3.5.12** — 6502 `cpx #imm` is 8-bit, so `cpx #384` silently became `cpx #128`, only clearing 128 of 384 bytes. Fixed with two-pass loop + compile-time assert.

**Issue found (2026-02-14): `test_dungeon.s` timeout.**
- R3.5 imports (`reu.s`, `tier_manager.s`) pushed `test_start` to $A032 — inside BASIC ROM ($A000-$BFFF). `BasicUpstart2(test_start)` generates `SYS 40994`, which jumps into BASIC ROM instead of the test code, causing an infinite hang until the cycle limit.
- **Fix:** Apply the bootstrap trampoline pattern from `test_item.s` — small stub at $080E banks out BASIC ROM, then `jmp test_start`. Any test with `test_start` >= $A000 needs this.

**No other critical issues found.**

### Future: C128 Native Memory (Phase 10.2)

The C128 has 128 KB natively (two 64 KB banks). With MMU bank switching,
the second bank can hold all creature + item data without REU or disk tier
loading — same benefit as the REU path but using built-in hardware. If the
C128 has an REU as well, even more data can be resident (larger item roster,
full monster recall, etc.).

**TODO (Phase 10.2):** Add C128 MMU bank-switch path alongside REU path.
Detect C128 mode at startup (check $D030 or MMU register at $FF00).
Load creature data into bank 1 via MMU configuration. Fetch via bank
switch instead of REU DMA. Same zero-disk-I/O benefit as REU path.

---

## Code Size Audit (2026-02-15)

**Context:** Program ended at ~$BFF7, CREATURE_BASE at $C020 — approximately **45 bytes free**. This audit identified ~188 bytes of verified, low-risk savings across 7 optimizations plus 3 bugs.

**Result:** OPT-1.2–1.7 implemented on 2026-02-15. Actual savings: **182 bytes** ($BFF7→$BF41). OPT-1.1 (dead string deletion) deferred. All 20 test suites pass. See Memory Usage Overview below for full post-optimization memory map.

### Bugs Found

| # | File | Description | Bytes |
|---|------|-------------|-------|
| BUG-20 | ~~monster_attack.s~~ | ✅ Fixed — inline strings eliminated by R7.6 Huffman migration. `mat_acid_str` now in Huffman dictionary, `mat_dead_str` removed (never referenced). | ~~42~~ |
| BUG-21 | ~~monster_attack.s~~ | ✅ Fixed — acid effect prints "SPITS ACID ON YOU" via mon_atk_build_effect_msg, now Huffman-compressed. | N/A |
| BUG-22 | ~~monster_attack.s~~ | ✅ Fixed — OPT-1.7 eliminated duplicate; R7.6 removed all remaining inline strings. | ~~5~~ |

### Additional Issues Noted

| Issue | File | Description |
|-------|------|-------------|
| ~~`rng_range_word` not implemented~~ | rng.s | **RESOLVED:** 16-bit rejection sampling implemented; gold drops now use `fi_qty_hi` + `rng_range_word` + `combat_append_decimal_16`. |
| ~~`mon_atk_effect_fear` is a no-op~~ | monster_attack.s | **RESOLVED:** Fear sets `eff_fear_timer` (static RAM byte in turn.s). Timer = `rng_range(cr_level) + 3`. Blocks melee attacks in `player_move.s`. Ticks down in `turn_tick_effects`. Saved/loaded in save.s. |
| `mon_atk_effect_corrode` is a no-op | monster_attack.s:360-362 | Corrode attacks deal damage but don't damage equipment. Marked "deferred". |

### Optimization Plan (OPT-1)

Seven optimizations totaling ~188 bytes. All preserve existing behavior and are independently testable.

| # | What | Where | Est. | Status |
|---|------|-------|------|--------|
| OPT-1.1 | ~~**Delete dead strings** `mat_acid_str` + `mat_dead_str`~~ | monster_attack.s | **42** | ✅ Done (eliminated by R7.6 Huffman migration) |
| OPT-1.2 | **Parameterize cast/pray table setup** — table-driven copy loop | player_magic.s | **~55** | ✅ Done |
| OPT-1.3 | **Deduplicate "CURE LIGHT WOUNDS"** — `.label` alias to `itn_17` | spell_data.s | **36** | ✅ Done |
| OPT-1.4 | **Unify `mon_atk_build_hit/miss_msg`** into `mon_atk_build_effect_msg` | monster_attack.s | **~20** | ✅ Done |
| OPT-1.5 | **Deduplicate "DETECT MONSTERS"** — `.label` alias to `itn_30` | spell_data.s | **16** | ✅ Done |
| OPT-1.6 | **Self-printing `mon_atk_build_effect_msg`** — `jmp cmb_term_and_print` | monster_attack.s | **~14** | ✅ Done |
| OPT-1.7 | **Eliminate `mat_the_str`** — use `cmb_the_str + 1` | monster_attack.s, monster_magic.s | **5** | ✅ Done |
| | **Estimated total (1.2–1.7)** | | **~146** | |
| | **Actual savings** | $BFF7 → $BF41 | **182** | ✅ Verified |

**Net effect:** Headroom increased from ~45 bytes to **223 bytes**. All 20 test suites pass (259 tests).

### OPT-1.2 Detail: Cast/Pray Table Parameterization

Lines 51-81 (`player_cast_spell`) and 102-132 (`player_pray`) are near-identical 58-byte blocks that initialize 10 consecutive pointer bytes (`pm_mana_tbl_lo` through `pm_name_hi_hi`) for mage vs priest spell tables. Replace with:

```asm
// Table of source addresses (10 per spell type, mage then priest)
pm_tables:                              // 20 bytes
    .byte <mage_spell_mana, >mage_spell_mana
    .byte <mage_spell_level, >mage_spell_level
    .byte <mage_spell_fail, >mage_spell_fail
    .byte <mage_spell_name_lo, >mage_spell_name_lo
    .byte <mage_spell_name_hi, >mage_spell_name_hi
    .byte <priest_spell_mana, >priest_spell_mana
    .byte <priest_spell_level, >priest_spell_level
    .byte <priest_spell_fail, >priest_spell_fail
    .byte <priest_spell_name_lo, >priest_spell_name_lo
    .byte <priest_spell_name_hi, >priest_spell_name_hi

// Copy 10 bytes from pm_tables+X into pm_mana_tbl_lo..pm_name_hi_hi
pm_setup:                               // 15 bytes
    ldy #0
!loop:
    lda pm_tables,x
    sta pm_mana_tbl_lo,y
    inx
    iny
    cpy #10
    bne !loop-
    rts

// Callers become:                      // 13 bytes each
player_cast_spell:
    ...
    lda #SPELL_MAGE
    sta pm_spell_type
    ldx #0                  // Offset 0 = mage tables
    jsr pm_setup
    jmp pm_do_cast

player_pray:
    ...
    lda #SPELL_PRIEST
    sta pm_spell_type
    ldx #10                 // Offset 10 = priest tables
    jsr pm_setup
    jmp pm_do_cast
```

New total: 20 (table) + 15 (helper) + 13 + 13 (callers) = **61 bytes** vs current **116 bytes**. Savings: **~55 bytes**.

### OPT-1.4 Detail: Unify Hit/Miss Message Builders

`mon_atk_build_hit_msg` and `mon_atk_build_miss_msg` (monster_attack.s:562-600) are structurally identical to `mon_atk_build_effect_msg`, just with hardcoded suffix strings. Replace:

```asm
// Before (2 × 18-byte routines + 2 × 3-byte call sites = 42 bytes):
    jsr mon_atk_build_hit_msg
    jsr cmb_print_buf

// After (2 × 11-byte inline setups = 22 bytes):
    lda #<mat_hits_str
    sta zp_ptr2
    lda #>mat_hits_str
    sta zp_ptr2_hi
    jsr mon_atk_build_effect_msg    // (self-printing per OPT-1.6)
```

Delete `mon_atk_build_hit_msg` and `mon_atk_build_miss_msg` entirely. **~20 bytes saved.**

### Non-Issues Verified

Items investigated that turned out to be correct:
- **`cpx #41` in `combat_append_str`:** Buffer is 42 bytes (indices 0-41). After writing at index 40, x=41 triggers bcs exit. Null terminator at 41 via `cmb_term_and_print` is within bounds. **Correct.**
- **Zero-page clobbering:** Known hazards in MEMORY.md are accurate. No new zp conflicts found.
- **Stack balance:** All JSR/RTS and PHA/PLA pairs are balanced across all audited paths.
- **Screen code vs PETSCII:** Properly separated — `.text` with inherited encoding for screen RAM, raw bytes for KERNAL I/O.
- **`mon_atk_base_tohit` sparse table** (21 bytes, mostly zeros): Direct-index access pattern makes this already optimal; a compact search table would cost more than 21 bytes.

### Lower-Priority Savings (Not in OPT-1 Scope)

These were identified but deferred due to complexity or diminishing returns:

| Category | Technique | Est. Savings | Why Deferred |
|----------|-----------|-------------|--------------|
| Shared " YOU." suffix | Build monster attack messages from fragments | 25-35 | Adds runtime complexity, small payoff |
| Compute XP tables at init | Replace 80-byte `xp_level_lo/hi` with init-time computation | ~20 net | 80 bytes table - ~60 bytes init code = small net win |
| Stat bonus table formulas | Replace 16-byte lookup tables with computed values | 30-50 | Risky — umoria fidelity requirement |
| String pool / dictionary | Central string deduplication system | 50-100 | Major refactor, error-prone |
| Creature name prefix extraction | Share "GIANT ", "SKELETON " prefixes | 40-60 | Only applies to tier data files (loaded from disk, not in main PRG) |

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

**Region 2: Permanent banked at `$F000` — always callable (via trampoline)**

Currently: special rooms (435 lines), ego items (214 lines), title sysinfo (84 lines). Total 1,101 bytes, 2,989 bytes free.

Expand with **gameplay UI screens** that are called during play but only on user keypress:

| Module | Lines | Est. bytes | Entry points |
|--------|-------|-----------|-------------|
| `ui_help.s` | 153 | ~400 | `ui_help_display` |
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
