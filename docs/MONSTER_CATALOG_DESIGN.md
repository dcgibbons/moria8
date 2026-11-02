# Monster Catalog Design: the Whole Catalog, Picked as VMS Picks

Status: design (2026-11-02), not implemented. It replaces the depth-tier
monster model. The maintainer's decisions are at the end.

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
| Catalog order | `c_list` sorted by level; `m_level[L]` counts creatures per level (`misc.inc` 185-195) | 279 creatures (`max_creatures`) |
| Normal pick | `randint(m_level[dun_level]) + m_level[0]`: uniform over creatures of level 1 to the depth (`misc.inc` 593-605) | |
| Depth cap | Deeper than `max_mons_level`, pick as at that level | 40 |
| Out-of-depth | 1 in `mon_nasty`: level `dun_level + abs(randnor(0,4)) + 1`, uniform within that level | 50 |
| Win creatures | The last `win_mon_tot` creatures never come from the normal pick; from `win_mon_appear`, every new level gets one, out of sight (`place_win_monster`, `misc.inc` 540; `generate.inc` 867) | 2 (Evil Iggy, the Balrog); DL50 |
| Level population | `randint(8) + min_malloc_level + alloc_level` monsters at generation, `alloc_level = dun_level / 3` (at least 2) (`generate.inc` 854-861) | 14 |
| New monsters | 1 in `max_malloc_chance` each turn | 160 |
| Summons | Picked at `dun_level + mon$summon_adj` (`misc.inc` 620) | 2 |
| Town | Level-0 creatures (`m_level[0]`) only, in the town | 8 in Moria8 |

Moria8 caps live monsters at 32 (VMS: 100), so a generated level is the VMS
count clamped to the slots available, as today.

## Architecture

### Layer 1: the level index (resident, about 100 bytes)

The catalog is stored in VMS order, sorted by level, so a creature's catalog
id (0-278) is its position. The index is the per-level counts, levels 0-40
(41 bytes; at most 15 creatures share a level), or their running totals (82
bytes, two bytes each) to save the summing.

A pick is the VMS pick: the running total at `min(depth, 40)` excluding the
win creatures, a 16-bit roll below it, and the id. The out-of-depth, summon
and win-creature rules are a few lines each over the same index. The roll
needs a 16-bit `rng_range` (totals reach 277).

### Availability: every creature has its place, some wait for features

Every creature keeps its catalog position whether or not the game can play
it yet, so ids, saves, recall, the attack table and the name block never
shift. A creature is **available** when every one of its attacks, spells and
flags is implemented exactly (not degraded); otherwise it is **unavailable**
and never spawns. The generator decides availability from one list of the
abilities the engine implements, so implementing an ability makes every
creature waiting only on it available at the next build, with no format
change.

The index carries a resident availability bitmap (279 bits, 35 bytes) and
counts only available creatures per level. A pick rolls among the available
creatures at or below the depth and walks the bitmap to the chosen id: VMS's
uniform pick, over the creatures the game can play. Win creatures are placed
only when available.

Available with today's abilities (attack types 1, 3, 4, 6, 9, 11, 14 and 20;
light and serious wounds, blindness, confusion, fear, both summons,
teleport-to and fire breath; movement and defence flags still to be checked
in the survey):

| Creature levels | Available |
| --- | --- |
| 1-5 | 46 of 65 |
| 6-10 | 23 of 40 |
| 11-20 | 42 of 65 |
| 21-30 | 20 of 49 |
| 31-40 | 14 of 50 |
| 41-100 | 0 of 2 (Evil Iggy, the Balrog) |
| **All** | **145 of 271** |

The abilities that unlock the most creatures, which order the feature work:

| Ability (VMS spell bit or attack type) | Creatures waiting on it |
| --- | --- |
| Hold person (spell `0x200`) | 24 |
| Drain mana (spell `0x10000`) | 19 |
| Blink (spell `0x10`) | 18 |
| Frost breath (spell `0x400000`) | 17 |
| Lose experience (attack 19) | 17 |
| Acid breath (spell `0x200000`) | 16 |
| Teleport (spell `0x20`) | 14 |
| Lightning breath (spell `0x80000`) | 13 |
| Fire touch (attack 5) | 11 |
| Cold touch (attack 7), slow (spell `0x8000`) | 10 each |

The Balrog needs fire touch, eat charges (attack 24) and its spells
(teleport, slow, drain mana among them); Evil Iggy needs lose strength
(attack 2), steal object (attack 13) and its spells. Their abilities are the
features M8 depends on.

### Layer 2: the catalog (far memory or disk, about 10 KB)

One fixed-length record per creature, in catalog order:

| Field | Bytes | Today |
| --- | --- | --- |
| Glyph, colour, level | 3 | same |
| Hit dice (number, sides), armour class | 3 | same |
| Sleep, awareness radius, speed (with random-move bits) | 3 | same |
| Experience | 2 | same |
| Movement and behaviour flags (upstream `cmove`: attack-only, random move, breeds, opens and bashes doors, passes walls, picks up objects, invisible, carries gold and objects) | 3 | 1 (`cr_mflags`) |
| Defence flags (upstream `cdefense`: evil, undead, dragon, animal, maximum HP, infravision, hurt by light and rock, immunities, no sleep) | 2 | partly in `cr_mflags` and `cr_speed` |
| Spell chance and spell flags (upstream `spells`) | 4 | 2 |
| Attacks: four indices into the shared attack table | 4 | two attacks inline (6) |
| Name: offset into the name block | 2 | name pointers |
| **Record** | **26** | 22 |

Shared with the records: the attack table (212 entries used, each type,
dice and sides, 3 bytes: about 640 bytes) and the name block (4,027 bytes of
text raw), Huffman-coded with the game's existing coder (about 2.4 KB).

Total: 279 x 26 = 7,254 bytes of records, plus 640 of attacks, plus about
2.4 KB of names: **about 10.3 KB**, against about 6.9 KB of tier data today
(185 rows, many duplicated across tiers).

### Layer 3: the level's species table (resident)

The resident `cr_*` arrays become a table of the species on the current
level: one slot per species, 32 dungeon slots plus the town creatures, each
holding the decoded record (the fields the game reads during play, about 24
bytes) and its catalog id. Names go to today's 1 KB name pool. Live monsters
point at species slots (`MX_TYPE` stays one byte).

This is smaller than today's 65 resident slots (about 1,430 bytes): 40 slots
of about 24 bytes plus a catalog id each is about 1,000 bytes, so resident
memory goes **down** by about 400 bytes on every port.

### Level generation

1. Roll every initial monster's species from the index (VMS counts, clamped
   to 32), plus the win creature from DL50.
2. Deduplicate the ids, sort them by catalog order, and fetch each record
   (and its name) into a species slot: one pass over the catalog in id order.
3. Place the monsters as today.

### During play

A new monster (1 in 160 turns) or a summon rolls an id from the index. A
species already loaded is used directly; a new one is fetched into a free
slot. A slot frees when no live monster uses it (a scan of the 32 monster
records, or a use count). With no free slot, the roll is repeated among the
loaded species at or below the depth (rare: it needs 32 distinct live
species).

## Storage and fetch, per port

| Port | Tier storage today | Catalog home | Fetch |
| --- | --- | --- | --- |
| C128 | All four tiers cached in Bank 1 (`$7A60-$9567`, 6,920 B) | Bank 1: the tier cache plus about 3.5-5 KB more. Its neighbours are the names payload below and the title cache and modal overlays above, so Bank 1 needs re-planning, or the names stay on disk | Bank-1 copy: instant |
| CX16 | Tiers preloaded in RAM banks 5-8 (32 KB) | Two of those banks; the other two free up | Bank switch: instant |
| Atari 130XE | Tiers preloaded in extended banks (4 x 4 KB) | The same 16 KB | Bank copy: instant |
| Apple IIe | Tiers from ProDOS on demand into `$A400-$BAFF` | Aux RAM if the overlay cache (`$5A00-$BFFF`) can give 10-12 KB; otherwise disk | Aux copy, or ProDOS random access |
| BBC Master | Tiers from DFS on demand into the `$A800` window | Sideways RAM has 1.5 KB free (Bank 6), so disk | DFS random access (`OSGBPB` with a pointer) |
| C64 | Tiers from disk (REU cache when present) into the `$E000` window | The REU when present; otherwise disk | REU copy, or a CBM relative file |
| Plus/4 | Tiers from disk into the `$E000` window | Disk | CBM relative file |
| Atari 800XL | Tiers from disk into the `$E000` window | Disk | DOS 2.5 `NOTE`/`POINT` |

**Disk fetches are by record, not by file.** Every disk format here can read
a record at an offset: CBM relative files (fixed records up to 254 bytes,
addressed by number), ProDOS `SET_MARK`, DFS file pointers, DOS 2.5
`POINT`. A level's 10-20 species are 10-20 record reads, in catalog order.
On a stock 1541 a relative-file record read is a few tenths of a second, so a
level costs a few seconds of loading; the existing fast-loader work and the
REU shorten it. A mid-level fetch (new monster, summon) is one record read.
Measuring this on real hardware timings (VICE true drive emulation) is the
first prototype task.

The Huffman-coded name block follows the records' path: far memory where the
records live there, otherwise each species' name is read with its record and
decoded into the name pool.

## Saves and recall

- **Monsters in a save** store their catalog id (0-278: two bytes, or one
  byte plus a high bit), not a tier slot. Loading rebuilds the species table
  by fetching the saved ids. The save version rises on every port.
- **Upgrade path for old saves.** A tier-format save names each monster by
  tier slot within the tier active when it was saved. The loader for the old
  version maps (tier, slot) to a catalog id through a table the generator
  emits from the last tier rosters (185 entries), then continues as a new
  save. The table lives with the other old-format loader code, not in
  resident memory.
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

## Costs and risks

- **Unavailable creatures.** 126 of the 271 dungeon creatures wait on
  abilities Moria8 does not implement yet (Availability, above), most of
  them deep: until those land, the deep levels have fewer species than VMS,
  and the Balrog and Evil Iggy do not appear.
- **Disk-only load time** per level, until measured.
- **Scope.** Level generation, spawning, summons, saves, recall, the
  generator, every port's storage HAL and memory contract. A project in
  milestones, not one change.
- **Bank 1 on the C128** needs a re-plan for the larger catalog.

## Plan

1. **Survey:** per port, the catalog home and its bytes; per disk path, the
   time of a 15-record fetch on true drive emulation.
2. **Generator:** the catalog file, attack table, name block and index from
   the VMS source, with checks against Umoria.
3. **Prototype on CX16 first** (maintainer, 2026-11-02: the fastest port to
   test; banked, fast, roomy): the index, the species table,
   level generation and spawning; AI playtest comparison against the current
   build (character level reached, deaths by depth).
4. **Saves and recall** on the new ids.
5. **Ports**, banked ones first (C128, Atari 130XE, Apple IIe), then the disk
   paths (C64, Plus/4, Atari 800XL, BBC Master).
6. **Abilities:** the unsupported attacks and spells, or their documented
   degradations.

## Decisions (maintainer, 2026-11-02)

1. **Source of truth:** VMS Moria 4.8, with Umoria 5.7.15 as the cross-check.
2. **The whole catalog:** all 279 creatures, each in its place. A creature
   whose abilities are not all implemented is marked unavailable and never
   spawns until they are; abilities are not degraded to make a creature
   available.
3. **Names:** Huffman-coded.
4. **Old saves:** an upgrade path (the tier-slot to catalog-id table above).
5. **Disk-only ports:** the survey decides between per-level record loads
   and a compressed resident catalog.
