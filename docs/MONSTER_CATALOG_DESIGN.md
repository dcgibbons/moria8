# Monster Catalog Design: the Whole Catalog, Picked as VMS Picks

Status: implemented on the Commander X16 and C128 (2026-11-02), the C64
and Plus/4 (2026-11-05) and the Apple IIe, BBC Master and Atari 8-bit
(2026-11-05): every port. It replaces the depth-tier monster model. The maintainer's decisions
are at the end.

## Why

Moria8 loads monsters in four depth tiers (DL1-8, 5-15, 11-25, 20-100), each a
fixed roster of its own band, and picks uniformly among the loaded roster's
creatures at or below the depth. That was an early memory-model choice made
before any playtesting. It makes each tier change a step up in difficulty:
when a tier loads, every low-level creature drops out of the pool, and those
are most of what VMS players meet. Descending into DL16 the average creature
is level 13.4 (VMS: 7.6); into DL30 it is 25.2 (VMS: 12.5), with 32% casters
(VMS: 20%). Experience per kill runs 10-15 times VMS's deep down. The AI
playtest dies about eight times as often per step from DL16 on, at every
character level. Moria8 also has 150 of the 279 creatures, two attacks each,
and no VMS win-creature placement.

The fix is not better tiers. It is to stop loading monsters by depth band.

## Principles

1. **VMS semantics by construction.** The pick, the out-of-depth pick, win
   creatures and summons follow VMS Moria 4.8 exactly, because the data and
   the algorithm are VMS's, not an approximation tuned to match it.
2. **The whole catalog, at full fidelity.** All 279 creatures, all four
   attacks, the full movement, defence and spell words. Generated from the
   VMS source (Umoria 5.7.15 as the cross-check), never hand-maintained.
3. **Load what a level holds, not what a depth band might hold.** A level has
   at most `MAX_MONSTERS` (32) monsters, so at most 32 species; only those
   need to be resident.
4. **One design for every port**, with the storage path behind the HAL.

## The VMS rules to reproduce

| Rule | VMS Moria 4.8 | Value |
| --- | --- | --- |
| Catalog order | `c_list` sorted by level. `init_m_level` (`misc.inc` 184-201) counts creatures per level, then makes levels 1-40 cumulative from level 2, so `m_level[0]` is the town count and `m_level[L]` counts levels 1 to L, town excluded | 279 creatures (`max_creatures`) |
| Normal pick | `randint(m_level[dun_level]) + m_level[0]`: uniform over creatures of level 1 to the depth (`misc.inc` 593-605) | |
| Depth cap | Deeper than `max_mons_level`, pick as at that level | 40 |
| Out-of-depth | 1 in `mon_nasty`: target level `dun_level + abs(randnor(0,4)) + 1` (capped at 40), then `randint(count at that level) + m_level[T-1]` (`misc.inc` 597-602). The `+ m_level[0]` is missing, so for targets of 2 and up the pick lands 8 entries (the town count) early, usually on a creature a level or two shallower. **Replicated exactly** (maintainer, 2026-11-02). Umoria fixes it (`monster_manager.cpp` 129-159) | 50 |
| Win creatures | The last `win_mon_tot` creatures never come from the normal pick (`init_m_level` stops before them). From `win_mon_appear`, every new level gets one unless the player has already won (`total_winner`), placed beyond `max_sight` of the player, chosen by `randint(2)` (`place_win_monster`, `misc.inc` 540-570; `generate.inc` 867) | 2 (Evil Iggy, the Balrog); DL50 |
| Level population | `randint(8) + min_malloc_level + alloc_level`, `alloc_level = dun_level / 3` clamped to 2-10 (`generate.inc` 854-861): 17-32 on a 198x66 map | 14 |
| New monsters | 1 in `max_malloc_chance` each turn, awake, placed beyond `max_sight` (`moria.inc` ~3635) | 160 |
| Summons | Picked at `dun_level + mon$summon_adj` (`misc.inc` 620). Vault monsters are summoned this way, asleep (`generate.inc` 181-188) | 2 |
| Summon undead | Scans `c_list` from a random start for an undead creature (`cdefense` `0x0008`), up to 20 entries, at any level (`misc.inc` ~650-690) | |
| Polymorph | A new creature uniform over levels 1-40, whatever the depth (`spells.inc` 1136, 1414) | |
| Breeders | A clone is the parent's species (`moria.inc` 2236-2244) | |
| Town | `randint(m_level[0])` (`misc.inc` 594); 4 creatures by day, 8 by night (`constants.inc` 116-117; `generate.inc` 950, 960) | |

**Population on Moria8's maps** (maintainer, 2026-11-02). Moria8 today places
`2 + rng(4) + dlvl / 3` monsters, capped at 14 (`core/monster.s`
`monster_spawn_level`), on every port: half VMS's count or less on the
198x66 maps (C128, Apple IIe, BBC Master, CX16), and denser than VMS deep
down on the 80x48 maps (C64, Plus/4, Atari 8-bit). The catalog uses VMS's
count scaled by map area (`cols x rows / 13,068`): VMS's own numbers on the
198x66 maps, 5-9 on 80x48. `MAX_MONSTERS` stays 32 and generation stops at
26, so 6 slots stay free for summons, breeders, new arrivals and pits; only
the 198x66 maps reach the cap, from about DL25. Raising `MAX_MONSTERS` (about
200 resident bytes for 48) is revisited after the CX16 prototype.

Moria8 calls the pick from `core/chest_summons.s`, `core/special_rooms.s`
(pits and nests, which VMS does not have), `core/player_magic_execute_overlay.s`
and `core/monster_magic.s`; each moves to the index.

## Architecture

### Layer 1: the level index (resident, about 100 bytes)

The catalog is stored in VMS order, sorted by level, so a creature's catalog
id (0-278) is its position. The index is the per-level counts, levels 0-40
(41 bytes; at most 15 creatures share a level), or their running totals (82
bytes, two bytes each) to save the summing.

A pick is the VMS pick: the running total at `min(depth, 40)` excluding the
win creatures, a 16-bit roll below it, and the id. The out-of-depth, summon,
polymorph and win-creature rules are a few lines each over the same index.
Moria8 has no 16-bit `rng_range` yet (totals reach 277). Summon undead needs
the creatures' undead flag without fetching records: a resident undead bitmap
(35 bytes) beside the availability one.

### Availability: every creature has its place

Every creature keeps its catalog position, so ids, saves, recall, the attack
table and the name block never shift. Which creatures spawn (maintainer,
2026-11-02):

- A creature **plays** unless most of its abilities are not implemented yet.
  Its abilities are what it does itself: each attack type, each spell, its way
  of moving and each other movement behaviour (invisible, passing walls,
  picking up objects, eating weaker creatures). Its reactions to the player's
  elemental and sleep attacks are a player-side feature and do not count.
- A creature that plays has its missing abilities **degraded** (as today's
  roster does), and every missing ability is high-priority backlog work
  (`docs/BACKLOG.md`, "High priority: the monster abilities Moria8 lacks").
- A creature with most abilities missing is **asked about** if it is in
  today's roster, and **left out** if it is not, until its abilities land.

`tools/build_catalog.py` applies the rule and reports each group
(`catalog.json`). On the VMS catalog (2026-11-02):

| Creature levels | Plays |
| --- | --- |
| 0 (town) | 8 of 8 |
| 1-5 | 63 of 65 |
| 6-10 | 40 of 40 |
| 11-20 | 61 of 65 |
| 21-30 | 48 of 49 |
| 31-40 | 47 of 50 |
| 41-100 | 2 of 2 (Evil Iggy, the Balrog) |
| **All** | **269 of 279** (113 with degraded abilities; 2026-11-08, after every breath element and Hold Person; the White Dragon Bat, Giant Black Dragon Fly and Blue Dragon Bat joined) |

Kept, degraded (in today's game with most abilities missing; maintainer,
2026-11-02: "keep all"): Blubbering Icky-Thing, Poltergeist, Radiation Eye,
Bloodshot Eye, Lost Soul, Disenchanter Mold, Giant White Dragon Fly,
Quylthulg, Banshee, Ghost, Lich, King Lich, Emperor Lich, Evil Iggy and the
Balrog (`KEPT` in the generator; a creature added to the roster later is
asked about). Left out (not in today's game): Green Glutton Ghost,
Disenchanter Eye, Grape Jelly, Moaning Spirit, White and Blue Dragon Bats,
Grey Ooze, Disenchanter Ooze, Giant Black Dragon Fly, Giant White and Red Ant
Lions, Crystal Ooze and the Rotting Quylthulg.

The index carries a resident availability bitmap (279 bits, 35 bytes) and
counts only playable creatures per level. A pick rolls among them at or below
the depth and walks the bitmap to the chosen id. Win creatures are placed
only when playable.

### Layer 2: the catalog (far memory or disk, about 11.8 KB)

One fixed-length record per creature, in catalog order:

The field widths come from the VMS data (`tools/build_catalog.py` asserts
them): VMS writes the largest creatures with many small dice (the Balrog is
375d8, Evil Iggy 300d8), and its sleep values reach 25,000.

| Field | Bytes | Today |
| --- | --- | --- |
| Glyph, colour, level | 3 | same |
| Hit dice: number (2), sides (1); armour class (1) | 4 | 3 |
| Sleep (2), awareness radius (1), speed (1) | 4 | 3 |
| Experience | 2 | same |
| Movement and behaviour flags (VMS `cmove`, all 32 bits) | 4 | 1 (`cr_mflags`) |
| Spell frequency and spell flags (VMS `spells`, all 32 bits) | 4 | 2 |
| Defence flags (VMS `cdefense`, all 16 bits) | 2 | partly in `cr_mflags` and `cr_speed` |
| Attacks: four indices into the shared attack table | 4 | two attacks inline (6) |
| Name: offset into the name block | 2 | name pointers |
| **Record** | **29** | 22 |

Shared with the records: the attack table (215 distinct VMS attacks, each
type, verb, dice and sides: 864 bytes with the empty entry 0) and the name
block, Huffman-coded with the game's coder under its own tree (2,707 bytes
plus a 110-byte tree).

Total: **11,772 bytes** (8,091 of records, 864 of attacks, 2,817 of names),
against about 6.9 KB of tier data today (185 rows, many duplicated across
tiers). The resident index is 76 bytes (41 level counts, a 35-byte bitmap).

`tools/build_catalog.py` reads VMS's `c_list` (`values.inc`) through
`VMS_SRC` and, given `UMORIA_SRC`, cross-checks Umoria: the same 279
creatures in the same order, with 553 field differences (mostly flag bits,
awareness radii and a few names). Moria8's current monster data came from
Umoria, so taking VMS as the source of truth changes data, not only labels.

### Layer 3: the level's species table (resident)

The resident `cr_*` arrays become a table of the species on the current
level: one slot per species, 32 dungeon slots plus the town creatures, each
holding the decoded record (the fields the game reads during play, about 24
bytes) and its catalog id. Names go to today's 1 KB name pool. Live monsters
point at species slots (`MX_TYPE` stays one byte).

Resident memory does not go down. Today's 23 SoA arrays of 65 slots are 1,495
bytes. Combat reads each attack's type, dice and sides on every blow, so a
species slot holds its four attacks (12 bytes) or the 864-byte attack table
stays resident: about 34 bytes a slot, 40 slots about 1.36 KB, roughly even
with today. Recall grows from 260 bytes (65 slots x 4) to 1,116 (279 x 4),
more with VMS's 19 spell bits (today's `recall_spells` has 8). On the banked
ports recall moves to far memory with the catalog; on the disk ports, which
have 101-158 bytes of resident headroom, it has to move to disk or shrink.

### Level generation

1. Roll every initial monster's species from the index (the area-scaled
   count, at most 26), plus the win creature from DL50.
2. Deduplicate the ids, sort them by catalog order, and fetch each record
   (and its name) into a species slot: one pass over the catalog in id order.
   Deep on a 198x66 map that is about 25 fetches, nearly all distinct species.
3. Place the monsters as today.

### During play

A new monster (1 in 160 turns), a summon or a polymorph rolls an id from the
index; a breeder's clone takes its parent's slot. A species already loaded
is used directly; a new one is fetched into a free slot. A slot frees when no
live monster uses it (a scan of the 32 monster records, or a use count).
Live species never exceed live monsters, so a free slot always exists. Deep,
nearly every new monster or summon is a new species: on the disk ports a
fetch in the middle of play.

## Storage and fetch, per port

Survey (2026-11-02; resident headroom from each port's `program_end`
against its limit):

| Port | Tier storage today | Catalog home | Record fetch | Resident headroom | Verdict |
| --- | --- | --- | --- | --- | --- |
| CX16 | Banks 5-8, one tier each | Two banks (22-23, later 5-6) | Bank select, instant | 417 B | Banked: feasible |
| Atari 130XE | Extended banks, 4 x 4 KB slots, preloaded | Banks 2-3 (8 KB contiguous each); records must not straddle a `PORTB` bank edge | Existing `xe_cache_fetch`, instant | 143 B (`Default`), 194 B (high resident) | Banked: feasible |
| C128 | All four tiers in Bank 1 (`$7A60-$9567`, 6,920 B, 47 spare) | Needs about 4.9 KB more; Bank 1's slack is about 0.9 KB, scattered | Bank 1 copy through the MMU thunks, instant | 464 B (`Default`), 43 B (resident world) | Re-plan: give up an overlay cache slot, or keep names on disk |
| Apple IIe | ProDOS on demand into `$A400-$BAFF` | Aux overlay cache (`$5A00-$BFFF`) has 354 B free: evict about two overlays to disk | Aux copy; or ProDOS, which needs `SET_MARK` (not implemented) | 369 B | Re-plan, or disk records |
| BBC Master | DFS on demand into the `$A800` window | About 2.9 KB of scattered sideways slack: not enough | DFS, which needs pointer reads (`OSGBPB` 3 or `OSARGS`; only sequential `OSGBPB` 4 is used) | 265 B (unverified) | Disk records |
| C64 | Disk or the REU into the `$E000` window | The REU when present; otherwise disk | `KERNAL_LOAD` only: relative-file reads are new code | 158 B | Disk records (and an REU path) |
| Plus/4 | Disk into the `$E000` window | Disk | `KERNAL_LOAD` only: relative-file reads are new code | 101 B | Disk records |
| Atari 800XL | Disk into the `$E000` window | Disk | A custom SIOV sector loader with no CIO, so no `NOTE`/`POINT`: walk the sector chain or use a build-time sector table | 143 B | Disk records |

**CX16 survey (2026-11-02).** Banks 0-21 are assigned (map, aux data,
Huffman corpus, tiers in banks 5-8, overlays in 9-20, title art in 21); the
machine has at least 64, so 42 or more are free. The catalog takes two banks:
22-23 while the tiers still exist, then 5-6 when they go (freeing 7-8). The
unified resident image ends at `$995E` against the `$9B00` name pool: 418
bytes free for the 76-byte index and the fetch code, and the species table
nets a saving. A record fetch is a bank select (`$00`) and a 29-byte copy;
names decode from the catalog bank into the existing name pool
(`$9B00-$9EFF`), with the game's Huffman decoder given the names' tree, data
and bank (it already reads its corpus from bank 4). Verdict: fits, no memory
re-plan, instant fetches.

**Disk fetches are by record, not by file**, and no port has record-level
reads today: every disk path above needs new seek code. A deep level is
about 25 record reads; how long that takes on a stock 1541 is unmeasured and
is the first task before any disk port. The resident species table, index and
recall growth must also fit 101-158 bytes of headroom on the disk ports, which
likely means compressing resident data or moving recall out.

The Huffman-coded name block follows the records' path: far memory where the
records live there, otherwise each species' name is read with its record and
decoded into the name pool.

## Saves and recall

- **Monsters in a save** store their catalog id (0-278: two bytes, or one
  byte plus a high bit), not a tier slot. The monster table is saved as a
  raw block today, so every stream writer and reader (and the banked
  variants) transforms slot to id. Loading rebuilds the species table by
  fetching the saved ids, whether or not a species is currently playable. The
  save version rises on every port.
- **No upgrade path for old saves** (maintainer, 2026-11-02). The catalog
  release raises the save version on every port and makes it
  `OLDEST_SAVE_VERSION`, so an older save gets the existing "Unsupported
  save." refusal (`save_version_supported`, `platforms/shared/save.s`). The
  legacy loaders (32-slot floor items, the older known-item bitsets, 30- and
  31-slot inventories) and their tests then compile out, as the Atari port
  already does. A tier-format save could not be mapped reliably anyway: the
  active tier is not saved and the tiers overlap.
- **Recall** (per-creature kills and deaths, and what the player has seen)
  becomes per catalog id: 279 entries a statistic. It lives with the catalog
  where far memory holds it, and is saved; on disk-only ports it is the main
  new resident or save-file cost.

## What goes away

`core/tier_manager.s`, the four tier files and their loaders, tier
transitions on stairs, Word of Recall and level jumps, the tier name-pool
handoff, `CREATURE_BALROG` as the last tier-4 row, the tier hysteresis (the
same depth harder going down than coming up), and the hand-kept tier
membership in `tools/parse_creatures.py`.

## What changes for players

- Every depth has the VMS creature mix: the tier steps at DL9, DL16 and DL26
  disappear.
- All 279 creatures appear, with all their attacks.
- Experience per kill falls to VMS levels deep down, against a much less
  dangerous pool.
- The Balrog and Evil Iggy appear from DL50, one per level, as in VMS (today
  the Balrog is a 1-in-57 normal pick from DL100).
- About twice today's monsters on the 198x66 maps (VMS's count); on 80x48,
  more shallow and fewer deep.

## Costs and risks

- **Degraded and left-out creatures.** 130 creatures play with degraded
  abilities and 13 are left out until their abilities land (Availability).
- **Random sequences change.** Availability and the new pick shift every
  fixed-seed game, so playtest baselines restart with the catalog.
- **An empty level.** An out-of-depth target level can have no playable
  creature; the pick then falls back to the nearest shallower level that has
  one.
- **Disk-only ports:** new seek code everywhere, unmeasured load times, and
  101-158 bytes of resident headroom.
- **C128 and Apple IIe** need a memory re-plan for the catalog.
- **Scope.** Level generation, spawning, summons, saves, recall, the
  generator, every port's storage HAL and memory contract. A project in
  milestones, not one change.

## Plan

1. **Survey:** catalog homes and resident headroom per port are done
   (2026-11-02, Storage and fetch); the time of a 25-record fetch on each
   disk path, on true drive emulation, is still to measure.
2. **Generator:** `tools/build_catalog.py` (2026-11-02) builds the records,
   attack table, Huffman name block, level index and availability bitmap
   from VMS and reports the Umoria differences; still to add are the undead
   bitmap and the per-port packaging.
3. **Prototype on CX16 first** (maintainer, 2026-11-02: the fastest port to
   test; banked, fast, roomy): the index, the species table,
   level generation and spawning; AI playtest comparison against the current
   build (character level reached, deaths by depth).
4. **Saves and recall** on the new ids.
5. **Ports**, banked ones first (C128, Atari 130XE, Apple IIe), then the disk
   paths (C64, Plus/4, Atari 800XL, BBC Master).
6. **Abilities:** the unsupported attacks and spells, or their documented
   degradations.

## CX16 prototype (2026-11-02)

Plan step 3 runs on the Commander X16 behind `HAL_PLATFORM_MONSTER_CATALOG`
(`platforms/cx16/hal/lifecycle_policy.s`). Every other port builds
byte-identical to the tier build and keeps the tiers.

- **Data:** `tools/build_catalog.py --engine-out platforms/shared/catalog`
  writes three files each port places: `catalog_fields.s`, the 21 engine
  fields of the tier rows, 279 bytes each (5,859 B); `catalog_index.s`, the
  raw and playable counts per level 0-40 and the availability bitmap
  (117 B); `catalog_names.s`, the names Huffman-coded with their own tree in
  the game decoder's format, with pointer tables (3,380 B; plain they were
  4,869 B). The X16 puts fields and index in Bank 22 (`MONSTER.CAT`) and the
  names in Bank 4 after the corpus. VMS values go through
  `parse_creatures.py`'s tier encoding: speed + 10,
  sleep / 10, attacks through the tier attack map, and hit dice over 255
  as fewer, larger dice with the same maximum (Balrog 375d8 is 75d40).
- **Species table:** `core/monster_catalog.s`. Dungeon rows 0-31 of the
  resident `cr_*` arrays hold this level's species, and `cat_slot_id_lo/hi`
  holds their catalog ids. A pick of a species that is not loaded fetches it
  into an empty slot, or one no live monster uses. Its name is decoded, with
  the names' tree swapped into the game's decoder (`hd_tree_left_ptr`), into
  the pool at slot × 32 (the X16's `$9B00`), and the slot's recall counters
  are cleared.
  `monster_spawn_level` empties the table.
- **Picks:** as in "The VMS rules to reproduce": 1 in 50 out of depth with
  VMS's base; the normal pick is uniform over the playable creatures of
  levels 1..min(dlvl, 40). `randnor(0,4)` is approximated by the sum of four
  rolls of 0-6, less 12 (mean 0, standard deviation 4).
- **Population:** `randint(8) + 14 + alloc_level`; generation stops at 26
  live monsters. The X16 map is VMS's 198×66, so no area scale applies (an
  assert holds the map size). From DL50, until the game is won, an awake
  Evil Iggy or Balrog lands more than 20 squares away. Only the Balrog wins.
- **Tiers:** `tier_check_transition` returns at once, and `current_tier`
  stays 0, so `creature_get_name` takes the `cr_name` pointers. The tier
  loader, tier tables and the X16 tier bank preload compile out. Banks 5-8
  are free; the tier rules stay in the Makefile for builds without the flag.
- **Saves:** the species table (64 B) rides in the door-state block, and
  load refetches each occupied slot. The X16 save version is `$17`, and the
  oldest it loads; the legacy feature versions are pinned to it.
- **Resident:** the image ends at `$9AD4` (43 B free). The catalog code is
  about 870 B, paid for by the tier code it replaces.
- **Tests:** `make testcx16`, 23 scenarios. The new scenario,
  `monster_catalog`, jumps to DL16 and checks for at least 15 monsters, the
  live species loaded, their levels and decoded names against the catalog,
  and a creature below level 8; then DL50 for one awake win creature.
  `balrog_victory` now marks a catalog slot as the
  Balrog. `scroll_delta` clears the monsters before measuring, because more
  monsters put breeding worms in view.

Deviation from these decisions, for now:

- **Recall** is per species slot and lives for one level, until recall moves
  to catalog ids ("Saves and recall").

## C128 (2026-11-02)

The second port (maintainer: "let's not cache the start overlay. and then
huffman-code the names, but avoid #2 unless we need to"; #2 was names on
disk). `platforms/commodore/c128/main.s` defines the flag for the product
build; the unit tests do not import `main.s` and keep the tier roster.

- **Bank 1** (`memory128.s`, C128M-007): the tier cache window holds the
  name pool (`$7A60-$7E5F`) and `128.cat`, the fields (`$7E60-$9542`, 37 B
  spare); the STARTUP overlay slot holds `128.cnm`, the names (`$A000-$AD33`).
  Both files load at boot through the Bank 1 loader
  (`c128_load_core_residents`). STARTUP is no longer cached: New Game loads
  it from disk. The progress count is 23 files (13 startup, the two catalog
  files and 8 overlays).
- **Resident:** the index sits in `128.world` with the catalog code, which
  ends at `$8BC9` (134 B free; 43 before, the tier code compiled out). The
  catalog loaders live there too: the main image ends at `$5E48`.
- **Fetch:** fields through `mmu_safe_db_read_ptr0`, names through the
  Huffman Bank 1 reads, the decoded name into the Bank 1 pool through
  `mmu_safe_db_write_ptr1`; `creature_get_name` copies a slot's name back
  from Bank 1. The stale-tier name reload compiles out.
- **Saves:** version `$19`, the oldest it loads; the room8 migration
  compiles out. The test fixture (`tests/make_load_resume_save.py`) writes
  the `$19` layout.
- **Tests** (`run_tests128.sh`): the new `catalog_spawn_smoke` descends to
  DL1 and checks the population, the species, their levels and their Bank 1
  pool names against the catalog (`tests/check_catalog128.py`).
  `cache_survival_smoke` probes the catalog's Bank 1 data where it probed the
  tier cache and the STARTUP slot, and expects no tier bits and no STARTUP
  bit. `preload_partial_failure_smoke` is retired: it proved a skipped tier
  preload fell back to disk, and there are no tiers; the catalog files are
  required at boot like the other residents.

Change record (`docs/BEHAVIOR_CHANGE_PROTOCOL.md`):

```text
Problem and success criteria: X16 and C128 monsters follow VMS 4.8's
  catalog, pick and population; make testcx16 and make test128 pass; other
  ports unchanged (byte-identical).
State being changed: cr_* dungeon rows 0-31, name pool, active_dungeon_count,
  cat_slot_id_lo/hi, monster population per level, X16 save format.
Search scope and terms: pick_creature_type, tier_check_transition, tier_load,
  current_tier, active_dungeon_count, CREATURE_BALROG, CREATE_BALROG,
  MAX_DUNGEON_CREATURES, recall_*, save block tables (core/, platforms/cx16/,
  platforms/shared/save.s).
Relevant readers/writers found and known exclusions: pickers (spawn level,
  summons, chest summons, special rooms, spell summons, wizard summon), the
  combat win check, creature_get_name; C64 test-only scripted paths in
  game_loop.s are not built for X16.
Initialization, reset and persistence points: cat_slot_id_hi = $FF at load;
  catalog_reset_slots at each monster_spawn_level; saved in the door-state
  block and refetched on load.
Affected production sequence through the changed transition: level generate
  -> monster_spawn_level -> catalog_population -> pick_creature_type ->
  catalog fetch -> monster_spawn_one; mid-level summons pick the same way.
Contract decision or selected upstream oracle with source locations: VMS
  misc.inc alloc_monster (597-602), place_win_monster (540-575),
  init_m_level (184-200); generate.inc 855-867; constants.inc 110-119;
  values.inc c_list.
Intentional Moria8 deviations: generation cap 26 of 32; picks skip creatures
  this port leaves out; randnor approximation; names and recall as above.
Input/intermediate widths, signedness, carry, range and overflow policy: ids
  are 9-bit (<= 278), sums of level counts 16-bit; the out-of-depth level is
  signed 8-bit before abs, at most 40.
RNG reduction and bias, if applicable: rng_range and rng_range_word reject,
  so the picks are unbiased.
Affected platforms, overlays, banks and owners: Commander X16 (Bank 22 new,
  names in Bank 4, Banks 5-8 freed) and C128 (Bank 1 tier window and STARTUP
  slot, C128M-007); the pick runs from resident code under any overlay.
Required production-path tests: X16 monster_catalog, balrog_victory,
  save_load, save_reboot_load, wizard_summon_town (harness_smoke.py); C128
  catalog_spawn_smoke, cache_survival_smoke, the save and load smokes
  (run_tests128.sh).
Known behavior explicitly out of scope: other ports, MAX_MONSTERS, recall
  by catalog id.
Unresolved uncertainty and risk: the population and level mix change game
  balance; the X16 cycle (one success of 31) has no tier baseline to compare.
```

## C64 and Plus/4 (2026-11-05)

The disk ports (maintainer, 2026-11-05: "do most of the loading at dungeon
generation time, but i do not want to limit the surprise monsters. so if we
need to ad-hoc load a couple of monsters during the gameplay on non-REU
systems, I think that is OK"). `main.s` defines the flag and
`HAL_PLATFORM_CATALOG_RECORDS` for the product build; the unit tests keep the
tier roster.

- **Records** (`platforms/commodore/common/catalog_records.s`,
  `tools/catalog_disk.py`): 49 bytes each, the catalog id, the 21 engine
  fields and the name as plain screen codes (maintainer: "plain names in the
  records"; Huffman names stay on the C128 and X16), five to a 254-byte
  sector so none crosses one: 56 sectors in `MONSTER.CAT1-4` (16, 16, 16 and
  8 blocks), each a PRG loading at `$E000`.
- **Index and sector table** (maintainer: "the spare half of the name pool"):
  `MONSTER.IDX` holds the level index and the track and sector of each record
  sector, written by the disk build from where the records landed (the test
  runners' images through `catalog_disk.py fix`). At boot (`tier_init`,
  `catalog_boot_load` in the init-only tail) it loads into the map's last
  page (`CATALOG_IDX_LOAD`; the `$E000` window holds the title's overlay, and
  a game loaded from a save disk left in the drive must not need the program
  disk) and is copied into hidden RAM:
  the C64's `$D400-$D4E4` under I/O, the Plus/4's `$DC00-$DCE4`; the name
  pool is `$D000-$D3FF` / `$D800-$DBFF` (`memory.s`, with asserts). The picker
  reads the index there: the C64 maps all RAM with interrupts off
  (`c64_catalog_map`), the Plus/4 runs with that RAM visible.
- **Fetch** (`common/catalog_fetch.s` `catalog_fetch_record`): the KERNAL and
  I/O in for the transfer (a pick can come from the C64's `$F000` code, which
  runs with every ROM and I/O out), then:
  - with an REU (C64): the four files were stashed at REU `$0000-$3FFF` at
    boot (`catalog_reu_preload`), and a record is one 49-byte DMA;
  - else the drive: `U1` reads the record's sector into a buffer channel and
    `B-P` points at the record. A record that names another creature (files
    copied one by one, an SD drive without block commands, a read error) is
    read again from `MONSTER.CATn` by name, skipping to it; only when that
    fails too does the game ask for the program disk and read again (the
    screen is redrawn at the next render).
  Timings on a true-drive 1541 (stock / JiffyDOS, measured 2026-11-05): a
  direct read about 0.42 / 0.24 s (0.7 / 0.46 s after an overlay load), a
  DL1's 5-9 species 2-4 s / 1-2 s; the REU is instant.
- **Population**: VMS's count scaled by map area (`CAT_AREA_SCALE`,
  75/256 on 80x48): 5-9.
- **Resident room**: the tier code, the tier file names and 25 unused
  creature rows paid for the catalog; the C64's win-creature placement runs
  from its `$F000` runtime (`tramp_catalog_place_win`). C64 `program_end`
  `$BF5F` (161 B free), Plus/4 `$C797` (104 B free).
- **Saves**: C64 `$17`, Plus/4 `$09`, the oldest each loads; the test
  fixtures write that layout. Loading a game re-reads its species.
- **Tests**: C64 `catalog_spawn_product_smoke` (the drive) and
  `catalog_spawn_product_reu_smoke` (the REU), Plus/4 `catalog_spawn_plus4`:
  a scripted new game to DL1, then the monster table, species table, levels
  and the hidden pool's names checked against the catalog
  (`c128/tests/check_catalog128.py`, at least 5 monsters).

**40 creature rows on every catalog port** (maintainer, 2026-11-05: "let's
not be wasteful if it isn't being fucking used. let's go with 40
everywhere"): a level holds at most `MAX_MONSTERS` live monsters, so at most
that many species, and the tier-era 57 dungeon rows left rows 32-56 unused on
the C128 and X16. `MAX_DUNGEON_CREATURES` is `CATALOG_DUNGEON_CREATURES` (32)
with the catalog; the recall block is 160 bytes, so the C128 saves are `$1A`
and the X16's `$18`, each the oldest it loads. Raising `MAX_MONSTERS` on the
large-map ports, never above VMS's 100, is backlog work.

Change record (`docs/BEHAVIOR_CHANGE_PROTOCOL.md`):

```text
Problem and success criteria: C64 and Plus/4 monsters follow the VMS catalog
  as the C128 and X16 do, read from disk (or the C64's REU) a species at a
  time; make test passes on every port.
State being changed: cr_* rows 0-31 and the hidden name pool on the C64 and
  Plus/4; creature row count 65 -> 40 on every catalog port; save versions.
Search scope and terms: pick_creature_type, catalog_*, tier_*, MAX_CREATURES,
  MAX_DUNGEON_CREATURES, TOWN_CREATURE_BASE, RECALL_DATA_SIZE, monster.db,
  PLATFORM_TIER_NAME_POOL, hal_storage_tier_*, reu_fetch_tier (core/,
  platforms/commodore/, platforms/cx16/, playtest/, tools/).
Relevant readers/writers found and known exclusions: as the C128 record;
  creature_get_name reads the hidden pool through its existing path; the
  playtest bot reads 32 or 57 dungeon rows by port (knowledge.uses_catalog).
Initialization, reset and persistence points: MONSTER.IDX at boot;
  catalog_reset_slots each level; the species table saved and re-read.
Affected production sequence through the changed transition: level generate
  -> monster_spawn_level -> catalog_population -> pick_creature_type ->
  cat_fetch -> catalog_fetch_record (REU or drive) -> monster_spawn_one;
  mid-level arrivals and summons the same way.
Contract decision or selected upstream oracle with source locations: as the
  C128 record (VMS misc.inc, generate.inc).
Intentional Moria8 deviations: population scaled by map area; plain names on
  disk; a copied disk reads by name, slower.
Input/intermediate widths, signedness, carry, range and overflow policy: ids
  9-bit; sector = id / 5 (<= 55), offset 2 + (id % 5) * 49 (<= 198); REU
  address (sector / 16) * $1000 + (sector % 16) * 254 + (offset - 2), 16-bit.
RNG reduction and bias, if applicable: unchanged pick; the scale is a
  rounded multiply, no RNG.
Affected platforms, overlays, banks and owners: C64 (hidden $D000-$D7FF,
  REU $0000-$3FFF, $F000 runtime), Plus/4 (hidden $D800-$DFFF), C128 and X16
  (row count, save version).
Required production-path tests: catalog_spawn_product_smoke,
  catalog_spawn_product_reu_smoke, catalog_spawn_plus4, the save and load
  smokes, make test.
Known behavior explicitly out of scope: Apple IIe, Atari 8-bit, BBC Master;
  recall by catalog id; raising MAX_MONSTERS.
Unresolved uncertainty and risk: real-hardware drive timing beyond VICE's
  deterministic rotation; a mid-play read is a visible pause on a stock 1541.
```

## Apple IIe (2026-11-05)

The catalog lives in aux RAM, as the C128's lives in Bank 1: no disk reads
during play, no record format. `main.s` defines the flag; the Apple IIe has
no tier build left (its tests are the MAME product scenarios).

- **Fields** (`A2.CATALOG`, 5,859 B): a boot-pack entry copied to aux
  `$5000-$66E2`, read a byte at a time through the zero-page aux-read thunk
  (`mmu_safe_map_read_ptr0`; `monster_catalog_a2.s`).
- **Names** (3,380 B Huffman): appended to the Huffman corpus in
  `A2.HUFFDATA`, now at aux `$8D00` (corpus and names end `$A829`, 470 B
  before ITEMS), decoded through the corpus's aux reads, as the X16 keeps
  them after its corpus in Bank 4.
- **Room** (maintainer: "only the town overlay, but we can come back to
  look/recall later"): OVL.TOWN left the aux cache and loads from disk on
  each town visit; aux data is capped at `$4FFF` (130 B to grow; the 40-row
  recall block freed 256 B); the cache is UI `$6700`, SPELL `$6D00`, MODAL
  `$8100`, the corpus and names `$8D00`, ITEMS `$AA00` (`cache_layout.s`,
  manifest v8). The auxiliary language card (16 KB of aux `$D000-$FFFF`) is
  the room if this margin runs out: a later experiment.
- **Index** resident; the species' names go to the old tier name pool at
  main `$A000-$A3FF`, read by `creature_get_name`'s existing path.
- **Resident image** ends `$7A0A` (502 B free, from 389); the play slot has
  141 B. Save version `$17`, the oldest it loads.
- **Test:** the MAME scenario `catalog_spawn` (DL1's population, species,
  levels and names against the catalog; one awake win creature on DL50);
  `wizard_summon_town` expects the town rows 32-39 and `balrog_victory`
  marks a species slot as the Balrog by catalog id, as the X16's do.

```text
Problem and success criteria: the Apple IIe draws its monsters from the VMS
  catalog as the other catalog ports do; testapple2-runtime and make test pass.
State being changed: aux RAM layout above the map (aux data cap, catalog
  fields, cache slots, corpus base); cr_* rows 0-31 and the $A000 name pool;
  the creature row count 65 -> 40; the Apple save version $16 -> $17.
Search scope and terms: A2_AUX_CACHE_*, A2_HUFFDATA_BASE, file_table,
  a2_ovl_cache_*, hal_storage_tier_*, monster.db, creature_data, PAK
  (platforms/apple2, playtest/, tools/).
Relevant readers/writers found and known exclusions: boot.s copies the pack
  to the cache manifest; a2_overlay_try_cache reads it (TOWN now cold);
  creature_get_name reads the pool; the bot reads 32 dungeon rows
  (knowledge.CATALOG_PORTS).
Initialization, reset and persistence points: the boot pack at startup;
  catalog_reset_slots each level; the species table saved and re-read.
Affected production sequence through the changed transition: level generate
  -> monster_spawn_level -> catalog_population -> pick_creature_type ->
  cat_fetch (aux field reads, Huffman name decode) -> monster_spawn_one.
Contract decision or selected upstream oracle with source locations: as the
  C128 record (VMS misc.inc, generate.inc).
Intentional Moria8 deviations: none beyond the shared catalog's; the town
  overlay is a disk load.
Input/intermediate widths, signedness, carry, range and overflow policy:
  unchanged shared code; field addresses 16-bit below $C000.
RNG reduction and bias, if applicable: unchanged.
Affected platforms, overlays, banks and owners: Apple IIe aux $3B0C-$BFFF,
  main $A000-$A3FF; OVL.TOWN cold.
Required production-path tests: catalog_spawn, the full testapple2-runtime
  suite (town, summon, Balrog, saves), make test.
Known behavior explicitly out of scope: Atari 8-bit, BBC Master; caching
  OVL.TOWN again (the language card).
Unresolved uncertainty and risk: aux data has 130 B to grow; real-drive
  timing of the town overlay load.
```

## BBC Master 128 (2026-11-05)

The catalog lives in sideways RAM Bank 6, as on the C128: no disk reads during
play. `main.s` defines the flag; like the Apple IIe, the BBC has no tier build
left (its tests are the MAME product scenarios).

- **Fields and names** (`BEEB.CATALOG`, 9,239 B: the fields, then the
  Huffman names) load into Bank 6 at `$9500-$B916` with the boot pack
  (`monster_catalog_beeb.s`). The Huffman readers (`memory_bank.s`
  `mmu_safe_huff_read_ptr0/1`, below `$3000`) select Bank 6 for a pointer at
  `$9000` and up and ANDY below it, so the names decode like the corpus and
  the fields read through the same helper; interrupts stay masked and
  `ROMSEL` returns to Bank 4, as the contract requires.
- **Room** (maintainer: the town overlay only): OVL.TOWN loads from DFS
  (`OVLTWN`); OVL.MODAL moved to Bank 5 after the map (`$B400-$BFFF`, 93 B
  spare), OVL.UI to Bank 6's tail (`$BA00`), and the aux-data reservation
  shrank from 23 to 21 pages (`$6000-$74FF` virtual, 418 B to grow)
  (`cache_layout.s`).
- **Index** resident; names go to the Bank 4 pool at `$A400-$A7FF`.
- **Resident image** ends `$7E93` (365 B free); the low helpers end `$23D3`.
  Save version `$17`.
- **Checker:** `check_memory_contract.py` checks the catalog's span and the
  bank sums, and lets the catalog's Bank 6 labels sit at addresses that
  Bank 4's pool and window also use.
- **Test:** the MAME scenario `catalog_spawn` (DL1's population, species,
  levels and names; one awake win creature on DL50); `dungeon_descend`
  checks DL1's species came from the catalog, and `balrog_victory` marks a
  species slot as the Balrog by catalog id.

```text
Problem and success criteria: the BBC Master draws its monsters from the VMS
  catalog; testbbcmaster-runtime and make test pass.
State being changed: Bank 5 and 6 layout (MODAL, aux data, catalog, UI);
  the Huffman readers' bank choice; cr_* rows 0-31 and the $A400 pool; the
  creature row count 65 -> 40; the BBC save version $16 -> $17.
Search scope and terms: BEEB_CACHE_*, BEEB_SWR_*, file_bank_table,
  beeb_ovl_cache_*, mmu_safe_huff_read_*, hal_storage_tier_*, MONDB,
  creature_data (platforms/bbcmaster, playtest/, tools/).
Relevant readers/writers found and known exclusions: every Huffman read
  (corpus in ANDY, catalog in Bank 6) goes through the two readers; the map
  and aux data readers are unchanged.
Initialization, reset and persistence points: the boot pack; per-level slot
  reset; the species table in saves.
Affected production sequence through the changed transition: as the Apple
  IIe record, with Bank 6 reads.
Contract decision or selected upstream oracle with source locations: as the
  C128 record.
Intentional Moria8 deviations: none beyond the shared catalog's; the town
  overlay is a disk load.
Input/intermediate widths, signedness, carry, range and overflow policy: the
  readers keep X, Y and the caller's flags (php/plp).
RNG reduction and bias, if applicable: unchanged.
Affected platforms, overlays, banks and owners: BBC Banks 5 and 6, ANDY
  readers, main pool $A400-$A7FF; OVL.TOWN cold.
Required production-path tests: catalog_spawn, testbbcmaster-runtime, make
  test.
Known behavior explicitly out of scope: the Atari 8-bit; caching OVL.TOWN
  again.
Unresolved uncertainty and risk: MODAL has 93 B to grow in Bank 5.
```

## Atari 8-bit (2026-11-05)

Disk records, as on the C64 (maintainer: one contiguous `MONSTER.CAT`, its
start sector found at boot, each record's id checked, the sector chain walked
if not, then the disk prompt; the 130XE preloads every record; the 800XL's
mid-play reads may turn the screen monochrome for a moment). `main.s` defines
the flag and `HAL_PLATFORM_CATALOG_RECORDS`; the Atari has no tier build left.

- **File** (`tools/catalog_disk.py atari`): the C64's 49-byte records
  (`common/catalog_records.s`), two to each DOS 2.5 sector's 125 data bytes,
  no load header: 140 sectors, written contiguous by `tools/make_atr.py`.
  Record n is in file sector n / 2 at byte (n % 2) * 49.
- **Fetch** (`monster_catalog_a8.s`, in the low helpers below `$4000`):
  `catalog_boot_load` finds the file's first sector in the directory at each
  title; a record is one SIOV read of start + n / 2 into `sio_sector_buf`. A
  record that names another creature (a copy written by DOS, not contiguous)
  is read down the sector chain from the start; then the disk prompt, and the
  file is looked up again.
- **130XE**: at boot `a8_catalog_xe_preload` reads every record sector, 32 at
  a 128-byte stride through the `$E000` window, and stashes each 4 KB into
  the tiers' old slots 10-13 and the spare slot 15 (the slot tables now cover
  slots 0-15); a record is a 49-byte copy from the bank with interrupts and
  NMIs off, falling back to the disk if its id is wrong.
- **Index** in the `$F000` runtime (`ATARI.BNK`): Default had no room; the
  name pool is the old tier pool at `$D800`. Default ends `$C09E` (98 B
  free), the runtime `$FF4F` (170 B).
- **Save version** `$17`, the oldest it loads; the version asserts now state
  the catalog's chain.
- **Test:** `catalog_spawn` (800XL, sector reads) and `catalog_spawn_130xe`
  (the preloaded copy): DL1's population (5-7 on 80x48), species, levels and
  names against the catalog, one awake win creature on DL50;
  `xe_cache_verify` expects all 16 slots filled; `balrog_victory` marks a
  species slot by catalog id. With disk fetches broken on purpose the 130XE
  scenario still passed and the 800XL's failed: the 130XE reads its copy.

```text
Problem and success criteria: the Atari draws its monsters from the VMS
  catalog; testatari8 (both machines) and make test pass.
State being changed: the tiers' 130XE slots (now the catalog's, plus slot
  15); cr_* rows 0-31 and the $D800 pool; creature rows 65 -> 40; the Atari
  save version $16 -> $17; the disk's files.
Search scope and terms: MONSTER.DB, tier_load_disk, current_tier,
  xe_slot_*, hal_storage_tier_*, TIER_FILES (platforms/atari8, tools/,
  playtest/).
Relevant readers/writers found and known exclusions: atari_match_cache_slot
  still maps MONSTER.DBn names (none are loaded now); EnterSio/ExitSio keep
  the SIOV contract; the bot reads 32 dungeon rows (knowledge.CATALOG_PORTS).
Initialization, reset and persistence points: the 130XE preload at boot, the
  directory lookup at each title, after a disk prompt; species table in saves.
Affected production sequence through the changed transition: level generate
  -> monster_spawn_level -> catalog_population -> pick_creature_type ->
  cat_fetch -> catalog_fetch_record (130XE copy, sector, chain, prompt).
Contract decision or selected upstream oracle with source locations: as the
  C128 record.
Intentional Moria8 deviations: population scaled by map area; plain names on
  disk.
Input/intermediate widths, signedness, carry, range and overflow policy: id
  9-bit, id / 2 <= 139 fits a byte; sector = start + id / 2, 16-bit; the XE
  offset (sector % 32) * 128 + (id % 2) * 49 within a 4 KB slot.
RNG reduction and bias, if applicable: unchanged.
Affected platforms, overlays, banks and owners: Atari low helpers (< $4000),
  $F000 runtime, $D800 pool, $E000 window at boot, 130XE slots 10-13, 15.
Required production-path tests: catalog_spawn, catalog_spawn_130xe,
  xe_cache_verify, testatari8, make test.
Known behavior explicitly out of scope: a mid-play read's pause on real
  drives (MAME times SIO, not a real 1050's seeks).
Unresolved uncertainty and risk: real-drive timing; the chain walk is slow
  (up to 139 reads) and only for a non-contiguous copy.
```

## Decisions (maintainer, 2026-11-02)

1. **Source of truth:** VMS Moria 4.8, with Umoria 5.7.15 as the cross-check.
2. **The whole catalog:** all 279 creatures, each in its place. A creature
   plays unless most of its abilities are missing (degraded until built,
   high-priority backlog); one with most missing is asked about if it is in
   today's game, left out if not.
3. **Names:** Huffman-coded.
4. **Old saves:** no upgrade path; refused as unsupported (Saves and recall).
5. **Disk-only ports:** the survey decides between per-level record loads
   and a compressed resident catalog.
6. **Abilities that count:** attacks, spells and movement behaviour; the
   reactions to the player's elemental and sleep attacks are one
   player-side feature.
7. **Out-of-depth picks:** VMS exactly, its off-by-8 quirk included.
8. **Population:** VMS's count scaled by map area, generation capped at 26 of
   the 32 slots; `MAX_MONSTERS` revisited after the CX16 prototype.

Decisions (maintainer, 2026-11-05):

9. **Disk ports:** most species read while a level is generated; a new
   arrival or summon may read during play on machines without an REU (the
   C64 uses its REU when present).
10. **C64 and Plus/4 storage:** plain names in the records; the index and
    sector table in the spare half of the hidden name pool; the sector table
    written when the disk is built.
11. **Creature rows:** 40 on every catalog port; raising `MAX_MONSTERS` on
    the large-map ports, never above VMS's 100, is backlog.
12. **Apple IIe, BBC Master and Atari** (2026-11-05): the Apple IIe in aux RAM
    with only OVL.TOWN out of the cache (look/recall stays cached; the
    auxiliary language card is a later experiment); the BBC in sideways RAM;
    the Atari as disk records in one contiguous `MONSTER.CAT`, its start
    sector found at boot, each record's id checked, the sector chain walked
    if not, then the disk prompt; the 130XE preloads every record at boot;
    the 800XL's mid-play reads may flash the screen; save versions `$17`.
