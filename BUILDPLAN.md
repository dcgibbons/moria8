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
| Program code | $0801–$9FFF | ~38 KB | Code + resident data |
| RAM under BASIC ROM | $A000–$BFFF | 8 KB | Banked data (creature tiers) |
| Free RAM (no banking) | $C000–$CFFF | 4 KB | Dungeon map (3,840 bytes at $C000–$CEFF) + floor item table (256 bytes at $CF00–$CFFF) — always accessible |
| RAM under KERNAL ROM | $E000–$FFFF | 8 KB | Banked data (item tiers 4,000 bytes, monster recall 1,200 bytes, spell tables ~1 KB, ~1.8 KB free) |
| Screen RAM | $0400–$07E7 | 1 KB | Display |
| Color RAM | $D800–$DBE7 | 1 KB | Display colors |
| **Total usable** | | **~58 KB** | With banking (code + all banked regions) |

On the C128, the full 128 KB is available through bank switching, which gives us
much more room. The design should target C64 as the constrained baseline.

**Zero page KERNAL conflicts:** Although $02–$8F is nominally free from BASIC,
some locations are clobbered by KERNAL routines. In particular, $22–$25 are used
by KERNAL LOAD/SAVE, $14–$15 by KERNAL OPEN, and several others by KERNAL I/O.
The `zeropage.s` module must document which ZP locations are safe to use freely
vs. which must be saved/restored around KERNAL calls (especially data_loader.s
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

**Tiered loading:** Group creatures into depth tiers:
- Tier 0 (town): creatures 0–19 (~20 types)
- Tier 1 (levels 1–5): creatures 20–69 (~50 types)
- Tier 2 (levels 6–10): creatures 70–129 (~60 types)
- Tier 3 (levels 11–20): creatures 130–209 (~80 types)
- Tier 4 (levels 21–50): creatures 210–279 (~70 types)

Only 2 adjacent tiers are in memory at once. Compressed to ~24 bytes per creature
(2-byte tokenized name index into string dictionary, pack flags into 2 bytes,
pack attacks into 8 bytes, remaining fields in 12 bytes). Do NOT truncate names
to 8 characters — use the PETSCII token compression system (see Text and Names
below) to preserve full creature names while storing only a 2-byte dictionary
index per creature:
- Largest pair: Tier 3 + Tier 4 = 150 types x 24 bytes = 3,600 bytes

Stored in RAM under BASIC ROM ($A000–$BFFF). This region is dedicated to creature
data only. Item data is stored separately in RAM under KERNAL ROM ($E000–$FFFF)
to avoid overflowing the 8 KB BASIC ROM region (creature + item data combined
would be 7,600 bytes — too tight for a single 8 KB region with no margin).

### Item/Treasure Data

Original: 420 items x ~35 bytes = ~14.7 KB.

**Same tiered approach:** Items grouped by minimum dungeon level, loaded alongside
creature tiers. Compressed to ~20 bytes per item (tokenized names, packed fields):
- ~200 items in any 2-tier window x 20 bytes = 4,000 bytes

Item tier data is stored in RAM under KERNAL ROM ($E000–$FFFF), separate from
creature tier data ($A000–$BFFF). Item lookups are less frequent than creature
lookups (AI runs every turn; item lookups happen on player action), so the
SEI/bank overhead for KERNAL RAM access is acceptable here.

### Text and Names

Monster names, item names, class titles, spell names, store dialogue — the
original has several KB of strings.

**PETSCII token compression:** Build a dictionary of common fragments (e.g.,
"potion of ", "scroll of ", " resistance", "sword", "dagger"). Names are stored
as sequences of token indices + literal bytes. Expect 40-60% compression.

**String dictionary location:** The compressed dictionary (`strings.bin`, estimated
~2–3 KB) must be **always resident in the main code region** ($0801–$9FFF).
Creature and item names are displayed during combat, LOS reveal, inventory, and
store screens — too frequently to tolerate banking overhead. Creature/item records
store a 2-byte index into this dictionary. The decompression routine expands
tokens to screen codes on the fly during display.

### Monster Recall

Original: 351 creatures x ~16 bytes = 5.6 KB.

**On disk:** Only the current tier pair's recall data is in memory (~150 x 8
bytes = 1,200 bytes, reduced fields). Recall is stored in the $E000 banked
region alongside item data.

**Recall lifecycle on tier change:** When the player crosses a tier boundary,
the outgoing tier pair's accumulated recall must be written to disk before
loading the incoming tier's recall. On tier change: (1) save current recall
to a per-tier file on disk (e.g., `recall_t1.bin`), (2) load new tier's
creature + item data, (3) load new tier's recall from disk (if file exists;
otherwise initialize to zero). On game save, the current tier's recall is
saved in the save file as before — the per-tier recall files on disk handle
the other tiers. This preserves accumulated recall across the full game,
matching original Moria behavior where recall is cumulative and permanent.
The extra disk I/O for recall save/load adds ~4 seconds stock (~1 second
with fastloader) per tier change — acceptable given tier changes already
require disk access.

---

## Architecture Overview

```
main.s                    Entry point, BASIC stub, initialization
├── config.s              System detection (C64/C128), column mode selection
├── memory.s              Bank switching routines, memory map management
├── zeropage.s            Zero page variable declarations (with KERNAL-safe zones)
├── turn.s                Game turn sequencer (player → monsters → effects → regen)
│
├── screen.s              Screen output routines (40-col and 80-col)
├── input.s               Keyboard input, command parsing
├── ui_status.s           Status bar rendering
├── ui_messages.s         Message line management (top of screen)
├── ui_inventory.s        Inventory display screens
├── ui_character.s        Character info screens
├── color.s               Color palette definitions and color RAM management
│
├── rng.s                 Random number generator (32-bit LFSR)
├── math.s                16-bit multiply/divide, dice rolling
├── tables.s              Lookup tables (stats, XP thresholds, etc.)
├── sound.s               Minimal SID sound effects (hit, miss, bump, death)
│
├── player.s              Player struct, stat calculations
├── player_create.s       Character creation (race, class, stats)
├── player_move.s         Movement, running, searching
├── player_combat.s       Melee attacks, blow count calculation
├── player_magic.s        Spell/prayer casting, mana management
├── player_items.s        Item use (eat, quaff, read, zap)
├── player_effects.s      Status effect timers, regeneration
│
├── dungeon_gen.s         Dungeon generation (rooms, corridors, doors)
├── dungeon_render.s      Viewport scrolling, tile-to-screen-code mapping
├── dungeon_los.s         Line of sight, lighting
├── dungeon_features.s    Traps, stairs, doors
│
├── monster.s             Monster data structures, spawning
├── monster_ai.s          Monster movement, pathfinding
├── monster_attack.s      Monster attack execution, special effects
├── monster_magic.s       Monster spellcasting
│
├── inventory.s           Item data structures, stacking, identification
├── store.s               Store system, buying/selling, haggling
│
├── save.s                Save/load game state to disk
├── data_loader.s         Tiered data loading from disk
├── fastload.s            Fast IEC serial loader (required for tier transitions)
│
└── data/
    ├── creatures_t0.bin  Creature data tier 0 (town)
    ├── creatures_t1.bin  Creature data tier 1
    ├── creatures_t2.bin  ...through t4
    ├── items_t0.bin      Item data tier 0
    ├── items_t1.bin      ...through t4
    ├── strings.bin       Compressed string dictionary (resident in main code area)
    ├── spells.bin        Spell/prayer tables (loaded to $E000 region)
    └── (runtime)
        └── recall_t0.bin ...through t4 — per-tier recall saves (created at runtime)
```

36 source files, plus binary data files generated at build time.

---

## Phase Plan

### Phase 1 — Skeleton and Infrastructure

**Goal:** A program that boots on C64/C128, displays text, accepts input, and
can be tested.

| # | File | What it does | Tests |
|---|---|---|---|
| 1.1 | `main.s` | BASIC stub ($0801), SYS entry, save BASIC ZP state ($02–$8F) to buffer, disable BASIC ROM, call init, main loop. IRQ: keep the default KERNAL IRQ handler active (required for keyboard scanning used by GETIN in `input.s`). If a custom raster IRQ is needed later (e.g., for split-screen effects), chain it to the KERNAL handler via the saved vector. Clean exit: restore ZP state, re-enable BASIC ROM, RTS to BASIC warm start. Select unshifted character set mode (uppercase + graphics) at startup. | Boots in VICE, exits cleanly, BASIC works after exit, keyboard responsive |
| 1.2 | `config.s` | Detect C64 vs C128, detect 40/80 column mode, store machine type in ZP | Returns correct machine ID |
| 1.3 | `zeropage.s` | Define ZP variable locations for all modules using BASIC's freed space ($02–$8F). Document two zones: "safe" (never touched by KERNAL) and "volatile" (clobbered by KERNAL LOAD/SAVE/OPEN — $14–$15, $22–$25, etc.). Volatile ZP must be caller-saved around KERNAL calls in data_loader.s and save.s. | Symbols resolve, no overlap, KERNAL-safe zones documented |
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

### Phase 2 — Player and Character Creation

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

### Phase 3 — The Town Level

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

### Phase 4 — Dungeon Generation and Navigation

**Goal:** Generate dungeon levels and navigate between them.

| # | File | What it does | Tests |
|---|---|---|---|
| 4.1 | `dungeon_gen.s` (full) | Room-and-corridor generation for dungeon levels. 80x48 map. Place N rooms (4–8 for simplicity), connect with tunnels, add doors, place stairs (2 down, 1 up), add mineral streamers. Room types: basic rectangle + overlapping. | Rooms connected, stairs present |
| 4.2 | `dungeon_features.s` | Door open/close/lock/jam logic, trap placement (6 types: pit, arrow, gas, teleport, dart, rockfall), staircase level transitions, secret door detection | Traps trigger correctly |
| 4.3 | `data_loader.s` + `fastload.s` | Load creature/item tier data from disk to banked RAM on level change using fast IEC loader. Track current tier pair — only reload on tier boundary crossing, and skip the load entirely if the same tier pair is re-requested (prevents repeated disk I/O when player yo-yos between adjacent tier-boundary levels like 5↔6). **Banking note:** On the 6502, CPU writes always go to RAM regardless of ROM banking state — only reads are affected. This means KERNAL LOAD (or the fastloader) can write directly to $A000 or $E000 without banking out ROM first. However, **bank out BASIC ROM before loading to $A000** so the data can be read back immediately after load (reads from $A000 with BASIC ROM banked in return ROM contents, not the loaded data). For $E000, the same principle applies: writes land in RAM automatically, but KERNAL ROM must be banked out (with SEI/CLI) to read the data back. **File organization:** Creature data, item data, and recall data are separate files per tier (`creatures_tN.bin`, `items_tN.bin`, `recall_tN.bin`). Recall files are created at runtime as the player accumulates knowledge. **Tier change sequence:** (1) save current recall to disk, (2) load new creature tier to $A000, (3) load new item tier to $E000, (4) load new recall from disk if it exists (else zero-init). See Monster Recall section and Design Decision #11. | Correct data after load, tier caching works, recall persists across tier changes, load time <3s with fastloader |
| 4.4 | `dungeon_render.s` (viewport) | Viewport scrolling for 80x48 map on 38x20 screen. Panel movement when player nears edge. Draw only changed tiles (dirty tile tracking). | Viewport scrolls correctly |
| 4.5 | `dungeon_los.s` (full) | Hybrid LOS matching original Moria behavior: lit rooms reveal fully when player enters (check room membership, not per-tile rays). Dark corridors reveal only adjacent tiles. Bresenham ray casting reserved for specific checks (ranged attacks, bolt spells in Phase 7) — not used for general visibility, as per-tile ray casting is too expensive at 1 MHz for every player move. Torch/lamp extends corridor visibility to light-radius adjacent tiles. | LOS matches expected pattern |
| 4.6 | Player movement updates | Walking into darkness, falling in pits, hitting traps, going up/down stairs transitions. Searching reveals secret doors (1-in-6 base). Running: auto-move in a direction until interrupted by wall, intersection, visible monster, or item on floor. Running is essential QoL for traversing explored corridors. | Transitions work, running stops at obstacles |

**Deliverable:** Multi-level dungeon with rooms, corridors, doors, traps, and
lighting. Player can descend and ascend.

---

### Phase 5 — Monsters

**Goal:** Monsters appear, move, and can be fought.

| # | File | What it does | Tests |
|---|---|---|---|
| 5.1 | `monster.s` | Active monster table (up to 32 simultaneous — reduced from 125 for C64 RAM). Spawn routine: pick creature type appropriate to depth, place in valid empty tile. Monster display characters. | Monsters spawn at correct depth |
| 5.2 | `monster_ai.s` | Monster movement: awake/sleep check (noise radius), greedy step toward player, confused wandering, wall-phasing for ghosts. Variable speed: each creature type has a speed value (1 = normal, 2 = fast/moves twice per player turn, 0 = slow/moves every other turn). The turn sequencer (`turn.s`) checks speed counters and calls AI accordingly. Speed is a core tactical mechanic — fast hounds are dangerous because they outrun you, slow molds are manageable because you can kite them. | Monsters approach player, fast monsters move twice per turn |
| 5.3 | `player_combat.s` | Melee attack: blow count from table (dex x weight ratio), to-hit roll (d20 + bonuses vs AC), damage roll (weapon dice + str bonus). Kill awards XP, check level-up. | Damage/kill/XP correct |
| 5.4 | `monster_attack.s` | Monster melee: up to 4 attacks per creature, damage types (normal, poison, stat drain, gold theft, item theft). Attack messages. Player death check. | Attacks deal correct damage |
| 5.5 | `player_effects.s` | Status effect application and timers: poison tick, blindness (hide map), confusion (random movement), paralysis (skip turns), regeneration (HP/mana per turn based on CON). | Timers decrement, effects apply |
| 5.6 | `dungeon_render.s` (monsters) | Show monster characters on map. Monster visibility (only in LOS and lit). Monsters blink or highlight on attack. | Monsters visible when expected |

**Deliverable:** Monsters wander the dungeon, attack the player, the player can
fight back. Status effects work. Combat is functional.

---

### Phase 6 — Items and Inventory

**Goal:** Items can be found, carried, equipped, used, and dropped.

| # | File | What it does | Tests |
|---|---|---|---|
| 6.1 | `inventory.s` | Inventory data structure: 22 carried slots + 8 equipment slots (reduced from umoria). Item struct (~16 bytes: type, subtype, flags, plus/damage/AC, quantity, id-status). Add/remove/stack operations. | Add/remove/stack correct |
| 6.2 | `ui_inventory.s` | Display inventory list (letter-indexed a–v), equipment list, item detail view. 40-column formatting with scrolling for overflow. | Display matches contents |
| 6.3 | `player_items.s` | Equip/remove/drop/pick-up commands. Wear/wield calculates AC and to-hit changes. Cursed items cannot be removed. Eat food (hunger system: full → hungry → weak → fainting → dead). | Equip changes stats |
| 6.4 | Item generation | Floor item spawning during dungeon gen. Gold pile generation. Treasure rooms. Chest contents. Item enchantment rolling (+1 to +N based on depth). | Items spawn at correct depth |
| 6.5 | Item identification | Unidentified items show generic name ("a blue potion"). Identify scroll/spell reveals true name. "Tried" status after first use. Scroll/potion/wand color randomization per game. | ID progression works |

**Deliverable:** Full item lifecycle — find, pick up, identify, equip, use, drop.
Hunger system functional.

---

### Phase 7 — Magic System

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

### Phase 8 — Stores

**Goal:** Town stores buy and sell items.

| # | File | What it does | Tests |
|---|---|---|---|
| 8.1 | `store.s` | 6 stores with inventory (12 items each — reduced from 24). Store owner data (name, race, max gold). Inventory restocking on town re-entry. (Design deviation: original Moria restocks based on game turns elapsed, not on re-entry. Simplified for implementation; acceptable because the net effect is similar — stores refresh between dungeon visits.) | Stores stock correct items |
| 8.2 | Store UI | Store screen: list items with prices, buy/sell interface. Simplified haggling (accept/decline at offered price, no multi-round bidding — optional enhancement later). | Buy/sell transactions work |
| 8.3 | Price calculation | Base price x charisma modifier x race modifier. Buy markup, sell markdown. | Prices match formula |

**Deliverable:** Player can buy equipment and sell loot in town.

---

### Phase 9 — Save/Load and Game Polish

**Goal:** Game state persists across sessions. Death and scoring work.

| # | File | What it does | Tests |
|---|---|---|---|
| 9.1 | `save.s` | Save game: write player struct, current dungeon map, active monsters, floor item table, inventory, current tier recall data, game flags to sequential file on disk. Compress map (RLE on tile bytes). Estimated save size: ~3–5 KB. | Save and reload match, all floor items and monsters persist |
| 9.2 | Load game | Load from disk, validate file integrity (checksum), **delete savefile immediately after successful load** (before resuming play — this enforces permadeath and prevents save-scumming via machine reset), restore all state, resume play. | Game resumes correctly, savefile gone |
| 9.3 | Death and scores | Death screen with killer info. High score table (top 10, stored on disk). Score = XP + gold + depth bonus. | Scores persist |
| 9.4 | Game polish | Title screen with ASCII art (PETSCII). Help screen (command reference). Difficulty tuning pass. | Screens display |

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

Active monsters capped at 32 (vs 125). Item templates reduced to ~250 (vs 420).
Inventory slots reduced to 22+8 (vs 34+11). These keep memory under control while
preserving the core Moria experience.

### 3. Tiered Data Loading

Creature and item data is divided into depth tiers loaded from disk. Only 2
adjacent tiers are resident at once. Loading happens only on tier boundary
crossings (every 5–10 dungeon levels), not on every level change. Most level
transitions require zero disk I/O.

**Disk speed reality:** Standard 1541 KERNAL LOAD runs at ~300 bytes/sec. A
full tier change (creature tier ~3,600 bytes + item tier ~4,000 bytes + recall
save ~1,200 bytes + recall load ~1,200 bytes) totals ~10 KB, which would take
~33 seconds stock. This is unacceptable. **A fastloader is required
infrastructure, not optional.** With a fastloader (~3–5 KB/sec), a full tier
change takes ~2–3 seconds — acceptable given it only happens at tier boundaries.
Tier change sequence: (1) save current recall to `recall_tN.bin`, (2) load
new creature tier, (3) load new item tier, (4) load new recall from
`recall_tN.bin` (if exists; else zero-init). See Design Decision #11.

The fastloader (`fastload.s`) should be implemented in Phase 4 alongside
`data_loader.s`. A host-side-only optimization of the standard Commodore
serial protocol is sufficient for ~2x speedup (tighter CIA bit timing,
optimized handshake loops). For ~3–5x, a minimal custom protocol with a
small drive-side routine uploaded to the 1541's RAM on startup is needed.
Start with host-side-only; upgrade to drive-side if 2x is not fast enough.
Note: custom drive code may not work with all drive types (SD2IEC, Pi1541);
test compatibility or provide a KERNAL LOAD fallback.

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
|Message line                          | Row 0
+--------------------------------------+
|                                      | Row 1
|                                      |
|          Game viewport               | Rows 1-20
|          (38 x 20 tiles)             | (38 cols visible)
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

### 11. Cumulative Monster Recall

Monster recall accumulates permanently across the entire game, matching
original Moria behavior. Because only the current tier pair's recall fits in
memory (1,200 bytes), recall for other tiers is persisted to individual disk
files (`recall_t0.bin` through `recall_t4.bin`) on tier change. This adds a
small amount of disk I/O to tier transitions (~1,200 bytes written + ~1,200
bytes read = ~1 second with fastloader) but preserves a key game feature:
knowledge gained about monsters is never lost. On a new game, these files do
not exist and recall initializes to zero. On game save, the current tier's
recall is included in the save file; on game load, it is restored to memory.
The per-tier recall files are separate from the save file and persist
independently (they are NOT deleted on death — this is intentional, as a
quality-of-life concession: recall knowledge carries across characters, same
as original Moria).

---

## Build System

**Kick Assembler** is invoked from the command line:

```bash
# Assemble
java -jar KickAss.jar main.s -o moria.prg

# Run tests (assemble test file, run in VICE headless with monitor script)
java -jar KickAss.jar tests/test_rng.s -o tests/test_rng.prg
x64sc -console -nativemonitor -autostartprgmode 1 \
  -autostart tests/test_rng.prg \
  -moncommands tests/test_rng.mon \
  -limitcycles 10000000 2>&1 | grep "^>C:"

# Run in VICE
x64sc moria.prg
```

The `main.s` file uses `#import` directives to include all module files.
Data files (`.bin`) are included with `.import binary` directives and can be
generated by helper scripts or assembled separately.

---

## Testing Strategy

Testing uses two complementary approaches:

**1. Assembly-time `.assert` directives** — Kick Assembler's built-in assertions
validate constants, table sizes, macros, and compile-time expressions during
assembly. These run as part of the normal build with zero overhead.

```asm
.assert "tile type count", TILE_TYPE_COUNT, 16
.assert "map size", MAP_COLS * MAP_ROWS, 3840
```

**2. Runtime tests via VICE headless** — Test programs are assembled to `.prg`,
run in VICE with `-console -nativemonitor`, and results are verified by dumping
memory at a known address after a BRK breakpoint triggers. Each test file has a
corresponding `.mon` monitor script that sets breakpoints and dumps results.

```
tests/
├── test_rng.s          RNG distribution, range bounds
├── test_rng.mon        VICE monitor script for test_rng
├── test_math.s         Multiply, divide, dice roll edge cases
├── test_math.mon
├── test_memory.s       Bank switching read/write verification
├── test_player.s       Stat get/set, bonus lookups, level-up
├── test_dungeon.s      Room placement, connectivity, door placement
├── test_combat.s       Hit/miss, damage ranges, XP awards
├── test_inventory.s    Add/remove/stack, capacity limits
├── test_los.s          Visibility calculations
└── ...
```

Runtime test convention: tests write a result byte to `$02` ($01 = all pass,
$00 = fail) and individual pass/fail flags to `$0400`+ (screen RAM), then
execute BRK. The `.mon` script sets a breakpoint at the BRK address, dumps
`$02` and the result area, and quits. A shell script parses the output for
pass/fail.

---

## Risk Register

| Risk | Impact | Mitigation |
|---|---|---|
| Dungeon generation too slow on 6502 | Player waits >5s on level change | Pre-compute room positions in table, minimize random calls, generate during stairs transition animation |
| Memory overrun | Crashes, corruption | Track allocation in spreadsheet, test with VICE memory monitor, enforce byte-level budgets for banked regions |
| Disk loading too slow on 1541 | Frustrating delays (33 sec stock for full tier change) | Fastloader is **required** (see Design Decision #3). With fastloader (~3–5 KB/sec), tier changes take 2–3 sec. Minimize tier transitions via tier pair caching. Provide KERNAL LOAD fallback for drive compatibility (slower but functional). |
| Game too hard without full spell set | Poor balance | Playtesting pass in Phase 9, adjust creature stats |
| PETSCII map unreadable | Poor UX | Iterate on tile characters, test on real hardware or accurate emulator, use color coding to differentiate elements |
| Runtime test flakiness | VICE cycle count too low/high for reliable BRK trigger | Tune `-limitcycles` per test, add fallback timeout. Use `.assert` for anything testable at assembly time. |
| Stack overflow from deep call nesting | Crash, corruption | 6502 stack is 256 bytes ($0100–$01FF). Deep chains (main→input→move→combat→effects→message→scroll) consume 3-6 bytes per level. Use flat state machine for monster AI loop (32 monsters per turn). Profile stack high-water mark in VICE. Target max 20 nesting levels. |
| ZP clobbered by KERNAL calls | Corrupted game state | Document KERNAL-volatile ZP locations in zeropage.s. Caller-save volatile ZP before KERNAL LOAD/SAVE/OPEN calls in data_loader.s and save.s. |
| Save file write speed on 1541 | 10+ second save delay at stock speed | Expect 3–5 KB save file. Stock 1541 writes at ~300 bytes/sec (10–17 sec). With fastloader write support, 2–4 sec. RLE compress map data. Warn player before save ("SAVING..."). Acceptable delay for infrequent operation. |

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

---

## What's Next

Phases 1–3 are complete. All audit and QA findings resolved. Phase 4 (Dungeon
Generation and Navigation) is next. Key prerequisites: `dungeon_gen.s`
room-and-corridor generation, `data_loader.s` + `fastload.s` for tiered data
loading, full LOS in `dungeon_los.s`, and player movement updates (traps,
searching, running).
