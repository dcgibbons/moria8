# Chest Design

Classic Moria chest gameplay for Moria8. This document is the settled design
record for the "Add classic Moria chests" backlog item
(`docs/BACKLOG.md`). It supersedes the chest-state proposals in
`docs/ITEM_EXPANSION_PLAN.md` (Lever 1's `fi_meta` bit-7 plan is invalid;
see State Layout) and records the maintainer-approved product decisions that
upstream sources do not settle.

Authority: pinned VMS Moria is the default gameplay oracle; pinned Umoria is
secondary where VMS is unclear. Both oracles were traced for this design
(2026-08-13). Reviewed by three independent design reviews (correctness,
affordability, 6502 performance) on 2026-08-13; their accepted corrections
are incorporated and marked.

## Settled Maintainer Decisions

| Question | Decision | Date |
| --- | --- | --- |
| Catalog rows | Seven rows: IDs 128-133 (six real chests) plus 134 (Ruined Chest) | 2026-08-13 |
| Portability | Chests are portable: pickup, inventory, drop, throw, Home, save/load | 2026-08-13 |
| Trap initialization oracle | VMS Moria `randint(depth)+4` | 2026-08-13 |
| Compressed generation depths | 2, 4, 7, 9, 11, 12 (for source levels 7, 15, 25, 35, 45, 50) | 2026-08-13 |
| Full floor table on open | Place rewards that fit; discard the rest; no reopening or rerolling | 2026-08-13 |
| Weight overflow | Small wooden/ruined 250; all others saturate at 255 (small iron is 300 upstream) | 2026-08-13 |
| Overlay strategy | Chest-only cold overlay + resident chest-at-tile pre-dispatch; Bash/Disarm do not move | 2026-08-13 (review) |
| A2 overlay divergences | A2 shares `OVL_CHEST` ID 10 (STORAGE/TITLE shift to 11/12); A2 chest overlay also hosts store init/restock (see step-6 as-built notes) | 2026-08-14 |
| Loot flags oracle | VMS Moria catalog flags (no small-object filtering) | 2026-08-13 (review) |
| Loot handoff | GEN-overlay fulfillment ships in v1, with explosion suppression | 2026-08-13 (review) |
| Known-item capacity | `ITEM_ID_CAPACITY = 160` (20-byte bitset) so the next catalog expansion pays no save bump | 2026-08-13 (review) |

## Catalog Rows

| ID | Name | Compressed level | Source level | Weight | Cost | Dice |
|---:|---|---:|---:|---:|---:|---|
| 128 | Small Wooden Chest | 2 | 7 | 250 | 20 | 2d3 |
| 129 | Large Wooden Chest | 4 | 15 | 255 | 60 | 2d5 |
| 130 | Small Iron Chest | 7 | 25 | 255 | 100 | 2d4 |
| 131 | Large Iron Chest | 9 | 35 | 255 | 150 | 2d6 |
| 132 | Small Steel Chest | 11 | 45 | 255 | 200 | 2d4 |
| 133 | Large Steel Chest | 12 | 50 | 255 | 250 | 2d6 |
| 134 | Ruined Chest | 0 (excluded from picker) | 0 | 250 | 0 | 0d0 |

Notes:

- Costs are the VMS catalog values; `it_cost_lo` only (no high-byte costs).
- Weights: VMS uses 250/300/500/1000 in tenths; Moria8's `it_weight` is one
  byte, so chests above 250 saturate at 255 per the maintainer decision.
- Dice: VMS `damage` column; used for thrown damage. `it_dmg_packed` nibbles
  encode count 0-15 and sides 0-15, so $23/$25/$24/$26 fit directly; no
  encoding extension needed (review 2026-08-13).
- Ruined Chest exists so a bashed chest keeps a stable, portable identity.
  It never generates randomly.
- All chest rows use `ICAT_CHEST` (17) and the `&` glyph; the category lookup
  in `it_display_by_cat` gains one entry.
- Chest names are fixed-known items (no randomized identification); the
  legacy-save migration default for IDs 128-134 is "known".

## State Layout

All persistent chest state rides existing serialized per-instance fields.
The `fi_meta` bit-7 "opened" proposal in `ITEM_EXPANSION_PLAN.md` is invalid:
`floor_item_get_flags_x` masks `fi_meta` with `$78`, so bit 7 is dropped by
both save/load and pickup. The selected layout needs zero new RAM and no new
save blocks:

| Field | Meaning |
| --- | --- |
| `p1` bit 0 | locked |
| `p1` bit 1 | lose-STR trap |
| `p1` bit 2 | poison trap |
| `p1` bit 3 | paralysis trap |
| `p1` bit 4 | explosion trap |
| `p1` bit 5 | summoning trap |
| `p1` bit 6 | trap found (known to the player) |
| `p1` bit 7 | opened/empty |
| `to_hit` | classic source level (7/15/25/35/45/50): lock difficulty, disarm difficulty, XP award, trap-init roll bound |
| `to_dam`, `to_ac` | zero; reserved |

- Armed = any of bits 1-5 set. Found = bit 6. `D <Dir>` on an unfound
  trapped chest reports "I don't see a trap..." per upstream.
- Trap fire sets bit 6 (upstream identifies the trap when it triggers:
  VMS `known2`, Umoria `spellItemIdentifyAndRemoveRandomInscription`).
- The four flag bits do not fit floor `fi_meta` (bits 3-6 pack the four
  `IF_*` flags); "found" therefore lives in `p1` bit 6, not in the
  instance-flags byte.
- Pickup, drop, throw, Home, floor save, inventory save all copy `p1` and
  `to_hit` today, so chest state survives every transfer with no schema
  change beyond the known-item bitset growth below.
- Upstream zeroes the per-instance cost on open. Moria8 has no per-instance
  cost field (cost is catalog-static), so this is N/A; stores reject chests
  regardless (see Blockers).

## Trap Initialization

VMS Moria (`misc.inc:1380-1417`): at generation, roll `randint(depth)+4`
where depth is the current dungeon level. VMS `randint` is 1-based and
`rng_range` is 0-based, so the Moria8 form is **`rng_range(dlvl)+5`**
(producing 5..dlvl+4):

| Roll | Outcome | p1 bits |
|---:|---|---|
| 1 | Empty, unlocked | none |
| 2 | Locked only | 0 |
| 3-4 | Lose STR + locked | 0, 1 |
| 5-6 | Poison + locked | 0, 2 |
| 7-9 | Paralysis + locked | 0, 3 |
| 10-11 | Explosion + locked | 0, 4 |
| 12-14 | Summoning + locked | 0, 5 |
| 15-17 | Lose STR + poison + paralysis + locked | 0, 1, 2, 3 |
| 18+ | Summoning + explosion + locked | 0, 4, 5 |

Rolls 1-4 never occur because the minimum roll is 5; Umoria's
`randomNumber(level+4)` (which can produce them) is explicitly not adopted
per the maintainer decision.

The trap-init write must run **after** `roll_enchantment` in the spawn flow,
because `roll_enchantment` zeroes p1/to_hit for non-equipment categories
(`core/item.s:1499-1541`).

## Gameplay Rules

### Search and Find Traps

- `search_scan_adjacent_silent` gains a chest branch, gated on the tile's
  `FLAG_HAS_ITEM` bit before any floor-table scan (review: keeps the
  per-move passive-search cost at ~80 cycles instead of ~6 ms).
- An adjacent armed chest rolls the normal per-tile search chance; success
  sets p1 bit 6 and prints "You have discovered a trap on the chest!"
- Searching an already-found trapped chest prints "The chest is trapped!"
  (upstream repeat message).
- `eff_find_traps` marks p1 bit 6 on every armed floor chest in its scan
  (upstream Find Traps reveals chest traps as well as floor traps).

### Open (`o <Dir>`)

- Resident dispatch: if the target tile's floor item is a chest, route to
  the chest overlay; otherwise the existing door path runs unchanged.
- If locked: confused players get "You are too confused to pick the lock."
  Otherwise success iff `skill - 2*source_level > rng roll`, using the
  existing effective disarm skill (`player_disarm_get_effective_chance`)
  converted with the 0-based threshold convention (see Blockers: the
  existing threshold helper is table-indexed and needs a value-based
  variant).
- Success clears bit 0 and grants `source_level` XP; failure consumes the
  turn with "You failed to pick the lock."
- Once unlocked: trigger all armed trap effects (VMS order below), clear the
  trap bits, set bit 7, then generate contents unless the chest was
  destroyed by its own explosion (upstream suppresses contents when the
  chest is deleted: VMS `if tptr > 0`, Umoria `if treasure_id != 0`).
- A chest whose trap was disarmed but whose lock is intact still requires
  lock picking.
- Re-opening an already-opened chest consumes a turn (upstream behavior).

### Disarm (`D <Dir>`)

- Resident dispatch: chest at the target tile routes to the chest overlay;
  visible floor traps keep the existing path.
- Unfound trap (bit 6 clear) but armed: "I don't see a trap..." — no turn.
- Disarmed/never-trapped chest: "The chest was not trapped." — no turn.
- Armed and found: success iff `skill - source_level` passes (value-based
  threshold helper). Success clears bits 1-5 (lock preserved), grants
  `source_level` XP.
- Ordinary failure: state unchanged.
- Bad failure (existing `disarm_roll_bad_fail` policy): fires the trap;
  surviving trap state stays armed (upstream does not clear flags after a
  bad-fail trigger), and bit 6 is set by the trigger.

### Bash (`B <Dir>`)

- Resident dispatch: chest at the target tile routes to the chest overlay;
  monsters/doors/tunnel keep the existing paths.
- 1-in-10 destroys the chest — identity becomes Ruined Chest (ID 134),
  p1/to_hit zeroed, contents never generated. This applies even to opened
  chests (upstream behavior; recorded as the selected rule).
- Otherwise, if locked, a separate 1-in-10 breaks the lock ("The lock breaks
  open!"); else "The chest holds firm." Bash never disarms a trap and never
  opens the chest.
- Upstream chest bash has no off-balance roll (that is monster-bash-only);
  no off-balance on chest bash.

### Trap effects (VMS order)

1. Lose STR: decrement STR (existing `decrement_stat` path), 1d4 damage,
   "You feel weakened!" (no sustain-STR item exists in Moria8; no immunity
   branch).
2. Poison: 1d6 damage, poison timer `+= 10 + rng(20)` (saturating add,
   Umoria stacking semantics).
3. Paralysis: `zp_eff_paralyze = 10 + rng(20)`; `PLF_FREE_ACT` suppresses.
4. Explosion: chest removed from the floor, then 5d8 damage, death cause
   "an exploding chest." (new `DEATH_*` source + Huffman string via the
   `df_death_source`/`trap_resolve_death_name` pattern). A destroyed chest
   suppresses contents (see Open).
5. Summoning: deferred to the resident handoff — three depth-appropriate
   monster spawn attempts at random adjacent free tiles (existing
   `pick_creature_type`/`monster_spawn_one` pattern). Summons must not run
   from inside the chest overlay: `monster_spawn_one` reads the tier buffer
   that aliases the `$E000` window, and `tier_check_transition`/`tier_load`
   can overwrite the executing overlay. The chest overlay records a pending
   summon count; the resident trampoline performs the spawns. Deferred
   summons still run when the chest exploded (VMS order), and still run when
   the explosion is lethal (death is deferred through `zp_death_source`;
   upstream runs the summons but not the loot in that case).

### Contents

Contents are generated lazily at open time from the static VMS per-type
flags (maintainer decision: VMS oracle), never pre-generated or stored. VMS
flag decode (bits 24 = carry object, 25 = carry gold, 26 = 60% drop,
27 = 90% drop, 28 = 1d2 drops, 29 = 2d2 drops; each mixed drop is 50/50
object/gold via `summon_object` typ 3):

| Chest | VMS flags | Reward profile |
| --- | --- | --- |
| Small Wooden | $0F000000 | 60% one drop + 90% one drop; each 50/50 object/gold |
| Large Wooden | $15000000 | objects only: 60% one drop + randint(2) drops |
| Small Iron | $0F000000 | as Small Wooden |
| Large Iron | $1F000000 | 60% + 90% + randint(2) drops; each 50/50 object/gold |
| Small Steel | $0F000000 | as Small Wooden |
| Large Steel | $23000000 | 2d2 drops; each 50/50 object/gold |

Notes:

- VMS has no small-object filtering for chest contents (that is Umoria-only
  `itemBiggerThanChest` behavior); contents may be any object, including
  another chest.
- Content depth = current dungeon level (matching `pick_item_type`'s
  existing dlvl convention; upstream `dun_level`).
- Placement: bounded 10 attempts per drop, candidate tiles within a 5x5 box
  around the chest, walkable and unoccupied; failure discards that drop.
  Upstream additionally requires LOS from the chest and allows 21 tries;
  the LOS check is omitted because loot fulfillment runs from the GEN
  overlay where the LOS routine is not linked (accepted approximation,
  recorded here).
- Floor-table-full policy: place what fits, discard the rest, no reopening
  or rerolling (maintainer decision).
- Rewards are generated at open time from live RNG. A save before opening
  and after opening legitimately diverge in loot; only chest state is
  persisted.

## Architecture

### Overlay placement (reviewed 2026-08-13)

Chest interactions are rare (a handful per level), so chest code is cold;
Bash and Disarm are warm verbs and **do not move** (the original wholesale
move was rejected on review: it would have converted 4-200 ms cached loads
into 1-11 s disk loads per invocation and caused ITEMS<->CHEST thrash).

A small resident pre-dispatch (`floor_item_find_at` + category check, both
already resident) routes only chest-targeted Open/Bash/Disarm to the chest
overlay — the same pattern Open already uses for doors. All non-chest paths
are byte-for-byte unchanged.

| Platform | Overlay | Loading |
| --- | --- | --- |
| C64 | New `OVL_CHEST` (ID 10), window `$E000` | REU-stashed (verified headroom: 9 overlays + tiers = 42,232 B; +4,096 = 46,328 B of the 64 KB bank); cold disk fallback for non-REU machines |
| Plus/4 | New `OVL_CHEST` (ID 10), window `$E000` | Cold disk load (status quo; no REU/cache machinery) |
| C128 | New `OVL_CHEST` (ID 10), window `$E000` | Cold disk load: excluded from boot preload and the Bank 1 cache slot tables (no free slot exists); the existing cached Disarm overlay (ID 8) is untouched |
| Apple IIe | New `OVL_CHEST` (ID 12, after STORAGE/TITLE), window `$A400` | Cold MLI load, like DEATH/HELP/STORAGE |

Size budget: chest command handlers + trap effects + state helpers, est.
1.3-1.7 KB — fits the 4 KB Commodore window and the Apple window with wide
margin. `.assert` guards at every platform's overlay end.

Accepted worst-case latencies for a chest open (chest overlay + GEN overlay
fulfillment): stock 1541 C64 ~ up to 20 s; C64+REU ~ 8 ms; C128 ~ 2-3 s +
200 ms cache fetch; Apple IIe ~ 1-1.5 s + 70 ms aux fetch. Bash/Disarm on
non-chest targets are unaffected.

### Loot fulfillment handoff

Chest contents need the generation picker (`pick_item_type` overlay +
`pit_sorted` data), which lives in the GEN overlay and cannot be called from
the chest overlay (mutually exclusive windows; returning into an overwritten
overlay is fatal; C128 `overlay_load` has no skip-if-current).

Flow: the chest overlay completes all state changes and non-summon trap
effects, stores the pending profile (chest position, VMS flags byte, source
level, pending summon count, chest-destroyed flag) in resident scratch, and
returns through the resident trampoline. The trampoline then:

1. Performs deferred summon spawns (if any) — resident tier machinery.
2. If the chest was not destroyed, loads the GEN overlay and fulfills loot:
   roll drops, pick items, `roll_enchantment`, bounded placement,
   `floor_item_add`, dirty marking.
3. Clears the pending latch. Overlay-load failure clears the latch and
   discards that chest's contents (consistent with the floor-full policy).
   Death, new game, and load transitions also clear the latch.

### Save format

`ITEM_TYPE_COUNT = 135`; `ITEM_ID_CAPACITY = 160`; `ID_KNOWN_BYTES` becomes
20 (maintainer decision: absorb the next catalog expansion without another
4-platform save bump). Bits 135-159 are unused capacity and stay clear.

Existing saves write/read a 16-byte bitset, so a new version threshold is
required:

- Bump `hal_storage_save_version` on all four platforms (+1) and add
  `hal_storage_save_known_bits20_version` equal to the new current version.
- `load_read_known_items` gains another arm: versions below the new
  threshold but at/above `SAVE_KNOWN_BITS_VERSION` read exactly 16 bytes,
  clear bytes 17-20, then run the category-default initializer over IDs
  128-134 (fixed-known -> known).
- Older version paths (V1/V2/V3 byte-per-item) are unchanged; their existing
  default loop now covers 128-134 through `it_category`.
- Invalid IDs (`>= ITEM_TYPE_COUNT`, not `$FF`) loaded from corrupt or newer
  saves are cleared to empty during inventory/floor/store load as a
  hardening measure (protects all future catalog growth, not just chests).

## Blockers Found During Design (must fix with the catalog growth)

1. Wand/staff effect dispatch routes every ID `>= 114` (wand) / `>= 119`
   (staff) into the Phase 3 router, whose default entry is Destruction
   (`core/item_actions_overlay.s:346-360, 410-425`;
   `core/scroll_effects_p3.s:126-162` C128 table `$ff`->`eff_destroy_area`,
   and 188-193 non-C128 fallthrough). Fix: explicit per-ID dispatch with a
   harmless fallback. This is a live latent bug independent of chests; land
   it first as its own change.
2. Apple IIe amulet stat application selects WIS/INT by item-ID parity
   (`platforms/apple2/main.s:929-946`). **Re-scoped 2026-08-13:** not a chest
   pre-fix. Chests are `ICAT_CHEST` and can never occupy the amulet slot, and
   the only amulets are IDs 124/125, so the parity shortcut is unreachable by
   this feature. The A2 play slot is hard-full (2 B free; any explicit-compare
   guard overflows it), so the parity-to-explicit fix is deferred until a new
   amulet row is added, at which point it must land with play-slot byte
   recovery.
3. `check_store_category` (`core/store_data.s:78-102`) maps categories > 8
   with `sbc #8` into an 8-byte mask table; `ICAT_CHEST` (17) reads out of
   bounds (review 2026-08-13). Add an explicit reject guard for ICAT_CHEST
   before the table indexing.
4. The fixed-known default loops in `core/item_identification.s:182-195` and
   `platforms/shared/save.s:1526-1540` mark known only categories `<
   ICAT_POTION`, `ICAT_BOOK`, `ICAT_AMULET`; `ICAT_CHEST` must be added or
   chests default to unknown on new games and legacy migrations.
5. `disarm_calc_success_threshold` takes X = trap-type *index* into the
   6-entry `trap_difficulty` table, not a difficulty value (review
   2026-08-13). Chest lock/disarm formulas need difficulty = source level;
   split the helper into a value-based variant (difficulty in a register or
   scratch) and keep the indexed wrapper for floor traps.
6. `test_store.s` picker predicates pass with duplicates; add a
   completeness/uniqueness check over IDs 2-133 plus the ruined exclusion.
7. Wizard "ITEM 0-127" prompt strings and `run_tests.sh` static contract
   need `0-134` updates. Wizard decimal parser wraps modulo 256 for inputs
   above 255 (pre-existing; exposed by three-digit IDs).
8. Chest state in `p1`/`to_hit` must not flow into store sale pricing as
   "enchantment"; stores reject ICAT_CHEST purchases, but Home metadata
   paths must preserve `p1`.
9. Known-item bitset growth (16->20 bytes) requires the save-version arm
   above; the plan's "0 new save bytes, no migration" claim was false.
10. Explosion death cause needs a new `DEATH_*` constant and Huffman string
    plumbed through `df_death_source`/`trap_resolve_death_name`
    (`core/dungeon_features.s:614-668`).

## Implementation Sequence

1. Durable records: this file; update `BACKLOG.md` chest section,
   `ITEM_EXPANSION_PLAN.md` (mark Lever 1 superseded), generation contract
   ledger if picker RNG order changes, save-migration doc. (No C128 memory
   ledger row needed: the C128 disarm cache is untouched; the chest overlay
   is a new cold class.)
2. Pre-fixes (standalone, independently shippable): wand/staff explicit
   dispatch with harmless router default (done: router-level fix; per-site
   upper bounds rejected — Apple ITEMS has 3 B free); store-category
   ICAT_CHEST guard (lands with step 3's constant).
3. Catalog: `ICAT_CHEST`, rows 128-134, glyph, names, costs, weights,
   compressed levels, dice, identification defaults; assert updates.
4. Save: `ITEM_ID_CAPACITY = 160`, 20-byte known bitset, version bumps,
   migration arm, invalid-ID hardening; round-trip and migration tests.
5. Picker: insert 128-133 into `pit_sorted` buckets 2/4/7/9/11/12, update
   bounds, completeness test, ruined exclusion. Generation RNG draw order
   changes; refresh generation fixtures in the same change.
6. Chest overlay shell + resident pre-dispatch: `OVL_CHEST` on all four
   platforms, chest-at-tile routing for Open/Bash/Disarm, stub handlers.
   Machinery verified by existing bash/disarm/open suites before any chest
   gameplay lands.
7. Chest spawn initialization (trap roll) after `roll_enchantment`;
   fixed-known description.
8. Search/Find Traps reveal (FLAG_HAS_ITEM-gated).
9. Open: lock pick, XP, trap-on-open, opened state, explosion suppression.
10. Disarm chest branch (value-based threshold helper).
11. Bash chest branch, ruin to ID 134.
12. Trap effects in VMS order, including explosion removal, death cause,
    found-on-fire; summon count staged in the pending latch.
13. Loot fulfillment handoff through the GEN overlay + deferred summons;
    latch lifecycle (overlay failure, death, new game, load).
14. (Optional, deferrable) Look/inspection chest state suffixes
    (locked/trapped/disarmed/empty).

## Implementation Notes (as-built, 2026-08-13)

Catalog + save representation landed with these measured memory levers:

- C64: `item_init_identification` moved to the ITEMS overlay (one-shot
  new-game init; resident trampoline `tramp_item_init_identification`),
  freeing ~180 B resident. Chest names are tokenized (`Small /Large /
  Wooden /Iron /Steel / Chest` tokens) since C64/Plus4 name streams are
  resident.
- Plus4: fits resident as-is (751 B free); tokenized streams shared with C64.
- C128: `it_min_level` + `iml_get_for_type` moved to the DungeonGenOverlay
  (sole reader is the gen-overlay picker), freeing ~88 B in
  C128ResidentItems; name streams already Bank 1 and spell chest names
  literally (no token strings resident).
- Apple IIe: `it_unknown_idx` moved to aux (`A2AuxData`, read via AuxReadY
  thunk in `iuk_index_for_type`); name streams already aux and literal.
- Save: `hal_storage_save_known160_version` = new current version per port
  (C64 $14, C128 $16, Plus4 $06, Apple $14); 16-byte bitset saves migrate
  through the new arm (`save.s` `load_read_known_items`).

Unit-test layout: catalog growth pushed several heavyweight C64 tests past
MAP_BASE (`$C000`). Fixes applied: opt-in `C64_TEST_NAME_STREAMS_A000`
parks name streams in BASIC-shadow RAM (`$A000`) for the ball/bash tests;
`test_scroll_p3.s` map-writing tests (t6/t7) moved to the end of the test
body so their row-8-12 writes only stomp already-executed code (this was a
latent test-layout hazard exposed by growth, not a product bug).

## Implementation Notes — Step 6 overlay shell (as-built, 2026-08-14)

Step 6 (chest overlay + resident pre-dispatch + stub handlers) landed with
these as-built details. The two A2 divergences from the Overlay placement
table were ratified by the maintainer on 2026-08-14 (see below).

Routing shape (all platforms):

- Open: `cmd_open` calls resident `chest_open_route` (core/game_loop.s),
  which checks `chest_find_at_df_target` (core/item.s) and tail-jumps to
  `tramp_chest_open` on a chest, else to `door_try_open`. The door path is
  byte-for-byte unchanged. `chest_open_route` is placed through the new
  per-platform `ChestRouteSegment`/`ChestRouteRestoreSegment` macros so
  tight ports can park it outside full payloads.
- Bash/Disarm: detection is inside `bash_command`/`disarm_command` (after
  direction resolution and, for bash, after confusion redirection, matching
  upstream target semantics). On a chest they stage the handler address in
  A/Y and tail-jump to the resident `chest_dispatch`; the evicted overlay is
  never returned into — the outer verb trampoline owns the continuation and
  epilogue. Non-chest paths are observably unchanged (one floor-table scan
  per targeted bash/disarm, no prompts or RNG added).
- Multi-item tiles (selected rule, 2026-08-14): `floor_item_find_at` scans
  slots high-to-low and `floor_item_add` allocates low-to-high, so the
  pre-dispatch sees the item pickup would take first ("top of pile"). A
  chest shadowed by later-dropped items is not routed until the covering
  items are picked up — consistent with Moria8's pile semantics (upstream
  allows only one object per tile, so there is no oracle to match).

Platform placement and levers (all measured):

- C64: `tramp_chest_open` (epilogue-owning) + `chest_dispatch` (plain-rts)
  in Default. Lever: one-shot `platform_services_install64` moved to the
  init-only tail past `program_end` (same pattern as `init_load_banked`),
  freeing 44 B resident. REU stash auto-tracks the name table (10 overlays,
  ~46 KB of REU bank 0); the boot progress total is now computed
  (`4 + REU_OVERLAY_COUNT`).
- Plus4: same shape as C64; `ovl_reu_start_*` stubs extended to 10 entries.
- C128 (`OVL_CHEST` = 10, cold): boot preload skips it
  (`c128_preload_all_overlays`), ready-mask bits for ID 10 stay zero so the
  cache probe misses to disk, and no Bank 1 slot exists (C128M-003
  untouched). `chest_dispatch`, `tramp_chest_open`, `chest_find_at_df_target`
  (via item.s) and `chest_open_route` (via `ChestRouteSegment`) all ride the
  resident items payload; `c128_resident_items_end` moved past the
  game_loop import to keep the end labels covering the macro-placed route.
  The C128 dispatcher mirrors the production `tramp_p3_dispatch_items`
  overlay-to-overlay pattern (KERNAL RAM stubs preserve operational
  MMU/$01 banking). Dead 8-entry `ovl_reu_start_*` stub tables removed from
  the world overlay-state area (REU path is compiled out on C128).
  `io_contracts.s` audits the chest symbols (`C128AuditChestOverlay` macro +
  runner regex).
- Apple IIe (`OVL_CHEST` = 10 shared constant; STORAGE/TITLE shift to
  11/12 — all references symbolic): `chest_dispatch` in Default. Two levers
  were required because the play slot (2 B free), the resident image
  (~15 B free), the ITEMS window (4 B free), and every aux cache slot are
  all hard-full:
  1. `store_restock_overlay.s` (store_init_all + store_restock_all, ~450 B)
     moved from the ITEMS overlay into the chest overlay; its file header
     already documents it as transition-only code safe in a non-town
     overlay, and its only entries are the resident trampolines
     (`tramp_store_init_all`/`tramp_store_restock_all`, retargeted to
     `chest_dispatch`). Restock runs inside new-game/recall generation
     flows, so the cold MLI load rides an already-cold transition.
  2. `winner_apply_retirement_bonus` moved from resident to the DEATH
     overlay (`winner_apply_retirement_bonus_overlay`), with the A2 royal
     flow loading DEATH before MODAL — the C64/Plus4 structure of applying
     the bonus inside the overlay flow. game_loop.s gates its plain-name
     call off for APPLE2 so the bonus still applies exactly once. This
     keeps the modal overlay inside its aux cache slot.

**Ratified 2026-08-14 (maintainer)** — A2 divergences from the Overlay
placement table: (a) A2 uses the shared `OVL_CHEST` ID 10 (STORAGE/TITLE
shift to 11/12; all references are symbolic) instead of appending a new
ID 12; (b) the A2 chest overlay also hosts store init/restock rather than
being strictly chest-only, because the A2 ITEMS window and every aux cache
slot are hard-full. Restock latency is unaffected in practice: it runs only
inside new-game and recall/stairs generation flows, which are already cold
disk transitions.

Shipping media: `64.chest`, `4.chest`, `128.chest` (d64/d71/d81), and
`OVL.CHEST` (ProDOS) are on the shipping images; the 25+26+2 test-harness
d64 build sites carry the new overlay as well.

Verification (step 6 gates): `make build` all ports; `make test64`
182/182; `make testplus4` 37/38 (`disarm_plus4` known flake — passes
isolated, same signature as pre-change); `make test128` 136/136;
`make testapple2` 22/22; `make disk` all images. New unit coverage:
`test_item.s` tests 53-55 pin `chest_find_at_df_target` (chest hit returns
carry+slot, non-chest item and empty tile return clear). Stub handlers
consume no turn; gameplay steps 7-13 replace them and add the behavioral
suites that exercise these routes end-to-end.

## Implementation Notes — step 4 completion (as-built, 2026-08-14)

The invalid-ID hardening from step 4 landed after review found it missing:
`save_sanitize_id_table` (platforms/shared/save.s) wipes any loaded item ID
that is neither `FI_EMPTY` nor `< ITEM_TYPE_COUNT` to empty at the end of
inventory load (`load_read_inventory_state`), floor load
(`load_read_floor_items`), and store load (`save_sanitize_store_ids` after
the post-known block; aux-thunk loop on Apple IIe where `si_item_id` is aux).
C64 resident funding: one-shot `generation_busy_install` moved to the
init-only tail via `GENERATION_BUSY_INSTALL_EXTERNAL` (same pattern as
`platform_services_install64`). Coverage: `test_save.s` tests 27-29
(inventory/floor production-path streams with ID 200 wiped, chest IDs kept;
store helper direct). Routing coverage: `test_main_loop.s` tests 41-42
(`cmd_open` on a chest dispatches to `tramp_chest_open` and never the door
handler; a plain tile stays on the door path).

## Implementation Notes — step 9 Open (as-built, 2026-08-15)

`chest_open_command` (core/chest.s, chest overlay) implements the Open rules:
chest-at-tile resident pre-dispatch (`chest_open_route`); locked chests require
a pick with success iff `rng_range(100) < clamp(skill + 99 - 2*source_level, 0,
100)` (the value-based `chest_threshold_value`); a pick clears `CHEST_P1_LOCKED`
and grants `source_level` XP via the 24-bit `chest_award_xp`; confused players
are blocked with the too-confused message and no skill roll. Once unlocked the
armed traps fire in VMS order (`chest_trigger_traps`), the trap bits are
cleared, and `CHEST_P1_OPENED` is set — unless an explosion destroyed the chest
(`floor_item_remove`), which suppresses the opened state and (later) contents.
Re-opening an opened chest consumes a turn with no effect.

Bug found by the new behavioral suite and fixed in the same step: the lock-pick
threshold call dropped the skill. `chest_disarm_skill` returns the effective
skill in A (stored to `chest_skill`), but `lda fi_to_hit,x / asl` then
overwrote A with the difficulty before `jsr chest_threshold_value`, so the
threshold was computed from difficulty alone (~99 always, independent of skill
or source level). Fix: reload `lda chest_skill` into A before the threshold
call so `X = difficulty`, `A = skill` as the helper expects.

Coverage: `test_chest_open.s` tests 0-7 exercise the production
`chest_open_command` directly (chest overlay imported into the unit assembly;
`huff_print_msg`, `trap_apply_damage`, `rng_range`, and `chest_disarm_skill`
patched to spies/controlled stubs for determinism): untrapped open sets OPENED
and consumes the turn; successful pick clears the lock and awards source_level
XP; failed pick (threshold 0) keeps the lock and awards nothing; confused lock
prints the message and consumes no skill roll; lose-STR trap fires once,
decrements STR, sets found and clears the trap bit; explosion empties the floor
slot and suppresses OPENED; summoning stages `chest_pending_summons = 3` with
no direct damage; re-open consumes a turn with no trap. The pick-success test
(T1) failed before the threshold fix and passes after.

Gates: `make build` all four ports (0 failed asserts); focused
`TEST_FILTER='chest_open|main_loop|find_hidden_traps_doors|item' make test64`
17/17 (incl. `chest_open` 8/8, `main_loop` 42/42 routing, `item` 57/57
catalog). Per the verification plan the slow serial platform suites are not run
per gameplay step; they run at the next architectural step and at feature end.



Step 8 landed as two resident helpers in `core/chest_search.s`
(`chest_search_reveal`, `chest_mark_found_all`), placed per platform through
`ChestSearchSegment`/`ChestSearchRestoreSegment` macros. Call sites are
guarded by `CHEST_ROUTING_ENABLED` (defined by the four product mains and
`test_find_hidden_traps_doors.s`) so unit assemblies without `item.s`
(table deps) compile the branch out:

- `search_scan_adjacent_silent` (core/dungeon_features.s) gates on
  `FLAG_HAS_ITEM` before any floor-table scan, then calls
  `chest_search_reveal`: unfound armed chests roll the per-tile chance and
  set `CHEST_P1_TRAP_FOUND` with the discovery message; already-found
  trapped chests print the upstream repeat message. The passive per-move
  cost stays off the floor table when no item is present.
- `eff_find_traps` calls `chest_mark_found_all` (marks every armed floor
  chest found). `eff_find_traps` and `eff_destroy_traps_doors` moved from
  `spell_effects.s` into the new `core/spell_effects_overlay.s` so
  Apple IIe can place them outside the resident image; on A2 they land in
  Default anyway (the A2 SPELL aux-cache slot is exactly full, so the
  spell-overlay placement was reverted).

Huffman: `@CHEST_FOUND_TRAP` and `@CHEST_TRAPPED` appended to the corpus
(re-encoded, 198 strings); the `test_subsystems.s` bank fixture was
re-encoded against the new tree (same maintenance as phase 3).

Measured memory levers for step 8:

- C64: one-shot `reu_load_all_tiers` moved to the init-only tail via
  `REU_LOAD_ALL_TIERS_EXTERNAL`.
- C128 (the large one): the search branch + find-traps helpers ride the
  resident items payload; `it_unknown_idx` and `it_name_lo` moved to the
  Bank 1 item-names payload with `mmu_safe_db_read_ptr1` reads in
  `iuk_index_for_type` / `item_load_known_name_ptr`; `eff_find_doors`
  relocated to the items payload (`EFF_FIND_DOORS_EXTERNAL`). Caught by the
  retirement/corrupt-load smokes: the overlay filename strings must stay in
  Bank 0 (the loader reads them with direct CPU pointers; the item-names
  payload is Bank 1) — an earlier placement of them in the names payload
  was reverted and is now documented in `hal/storage_overlay_names.s`.
- Apple IIe: `place_secrets` moved from `dungeon_features.s` to
  `dungeon_gen.s` (GEN overlay) via `PLACE_SECRETS_EXTERNAL` — its only
  caller is the generator.

Coverage: `test_find_hidden_traps_doors.s` tests 4-8 (discovery at 100%
chance sets found + prints, repeat message on re-search, zero-chance
no-discovery, unarmed-chest silence, `eff_find_traps` marks armed chests
and spares unarmed). Gates: `make build`, `make test64` 182/182,
`make testplus4` 38/38, `make test128` 136/136 (incl. retirement-royal and
corrupt-load smokes), `make testapple2` 22/22.

## Implementation Notes — step 7 spawn init (as-built, 2026-08-14)

Chest spawn initialization landed inside `roll_enchantment` (core/item.s),
which owns the non-equipment p1/to_hit zeroing the design's ordering rule
requires: a new `ICAT_CHEST` branch writes `fi_add_to_hit` from
`chest_source_level` (7/15/25/35/45/50/0) and returns p1 = trap bits from
the VMS `randint(depth)+4` band table. As-built form: the raw
`rng_range(dlvl)` result IS the band index (roll = rng+5, band = roll-5),
clamped to the 18+ band, looked up in the 14-entry `chest_trap_band` table
and OR-ed with `CHEST_P1_LOCKED`. Wizard-created chests take the same path
(harmless; useful for interactive verification). Stores never stock chests
(step 2's guard), so restock cannot create untrapped-state chests.

Measured memory levers for step 7:

- C64: one-shot `reu_stash_overlays` moved to the init-only tail via
  `REU_STASH_OVERLAYS_EXTERNAL` (same pattern as `platform_services_install64`
  and `generation_busy_install`).
- C128: one-shot `item_init_identification` moved from the resident items
  payload to the TOWN overlay (`ItemInitIdentSegment`; cached, unlike the
  full items overlay/payload and gen overlay), called through the new
  `tramp_item_init_identification`; game_loop.s's trampoline gate now
  includes C128. `io_contracts.s` audits it.
- Apple IIe: `disk_prompt_save`/`disk_prompt_game` bodies moved to the
  STORAGE overlay (`*_impl`) behind same-name resident trampolines; every
  call flow (title load, in-game save, post-save swap-back) has OVL.STORAGE
  loaded already, so the trampolines are always skip-if-current with zero
  latency change. Band chain flattened to the lookup table above.

Test-layout: step 7's item.s growth pushed `test_stinking_cloud.s` and
`test_orb_of_draining_prayer.s` Main regions past MAP_BASE (same latent
map-stomp hazard as the ball/bash tests). Both opted into
`C64_TEST_NAME_STREAMS_A000` and gained `test_body_end <= MAP_BASE` asserts
so future growth fails at assembly time instead of hanging.

Coverage: `test_item.s` tests 56-57 — deterministic fixtures for all six
trap bands (raw rng 0/2/5/7/10/13 -> expected p1 bits, to_hit=7) and the
per-ID source-level table (128-134 -> 7/15/25/35/45/50/0). Gates:
`make build`, `make test64` 182/182, `make testplus4` 38/38,
`make test128` 136/136, `make testapple2` 22/22.

## Verification Plan

Budget note (review 2026-08-13): gameplay logic is proven in the fast C64
unit harness; slow serial platform suites run once per architectural step
and once at the end, not per gameplay step.

- Catalog/table size asserts and picker completeness (C64 unit).
- Save: current-format round trip with chests in floor/inventory/Home;
  16-byte legacy bitset migration defaults; invalid-ID rejection.
- Spawn: deterministic RNG fixtures for each trap-roll band; excluded at
  town; ruined never generated.
- Search reveal found/unfound/already-found; Find Traps marks found.
- Open: locked success/fail/confused, XP award, trap-on-open, opened state,
  re-open turn cost, explosion suppresses loot, floor-full truncation.
- Disarm: unfound rejection, success (lock preserved), ordinary fail, bad
  fail triggers trap and sets found, no-turn cases.
- Bash: destroy-to-ruined (identity swap, state zeroed, including opened
  chests), lock break, holds firm, trap still armed after bash, no
  off-balance.
- Traps: each effect, multi-effect VMS order, explosion removal before
  damage, lethal explosion still summons but does not loot, death-cause
  string.
- Loot: VMS profile decode per type, drop counts, placement bounds,
  floor-full policy, pending-latch clearing on overlay failure/death/load.
- Portability: pickup/drop/throw/Home/save round trip preserves p1/to_hit.
- High-ID safety: IDs 128/134 through wizard grant, render, look, pickup,
  save on every platform.

Gates: `make build`, `make test64`, `make testplus4`, `make test128`
(overlay tables change), `make testapple2`, full `make test`, `make disk`.
Interactive verification: generate, search, disarm, bash, open, loot, carry,
save, reload a chest.
