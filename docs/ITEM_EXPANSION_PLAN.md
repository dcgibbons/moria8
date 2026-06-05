# Moria8 Item Catalog Expansion Notes

## Bottom Line

The current Moria8 item system cannot support the full Umoria catalog by simply
raising `ITEM_TYPE_COUNT` and appending table rows.

Confidence: high.

The first post-64 expansion proved the main risk: catalog growth is a schema,
memory-layout, and product-path compatibility change. It is not just a table
append. The failure mode was an appended mundane equipment item entering an
old randomized unknown-name path, indexing past the staff shuffle table, and
rendering unrelated memory as inventory text. Future item batches must treat
identification defaults, wizard/debug paths, save migration, and per-platform
layout as first-class work.

The full catalog is possible only with a different implementation: split live
item instance state from catalog definition data, keep a compact resident
catalog, and move names/full metadata/generation tables into banked or
disk-loaded data.

An abbreviated catalog is much more practical. A 96-128 item catalog is
plausible with layout work. A literal 420-row Umoria-style catalog is an
architecture project.

## Current Moria8 Constraints

Current Moria8 has 66 item type IDs.

Relevant current constants:

| Constant | Value | Meaning |
|---|---:|---|
| `ITEM_TYPE_COUNT` | 66 | Current item catalog size |
| `MAX_FLOOR_ITEMS` | 42 | Max live floor item slots |
| `MAX_INV_SLOTS` | 22 | Carried inventory slots |
| `MAX_EQUIP_SLOTS` | 9 | Equipment slots |
| `TOTAL_INV_SLOTS` | 31 | Inventory + equipment slots |
| `FI_EMPTY` | `$ff` | Empty item slot sentinel |

Current linked headroom:

| Target | Main/free | Items overlay/free | Banked/free | Verdict |
|---|---:|---:|---:|---|
| C64 | 1156 bytes below `$C000` | 972 bytes | 7 bytes below `$FFFA` | Tight; overlay-only growth |
| C128 | 60 bytes below current limit | 157 bytes | about 367 bytes below `$FFFA` | Blocked without layout work |
| Plus/4 | 1610 bytes below `$C800` | 972 bytes | 502 bytes below `$FF00` | Workable but not free |

The C128 is the limiting platform.

## Current Resident Item Model

The current item system is built around one-byte item IDs and resident
immutable item tables.

Each item type has resident table fields roughly like:

| Field | Cost |
|---|---:|
| category | 1 byte |
| display glyph | 1 byte |
| color | 1 byte |
| weight | 1 byte |
| damage dice count | 1 byte |
| damage dice sides | 1 byte |
| base AC | 1 byte |
| cost low | 1 byte |
| cost high | 1 byte |
| min level | 1 byte |
| name pointer low | 1 byte |
| name pointer high | 1 byte |

Minimum table cost is about 12 bytes per item, before name text,
identification data, generation tables, behavior code, and special-case logic.

Each new item also usually costs:

| Area | Typical cost |
|---|---:|
| `id_known` RAM/save state | 1 byte per item |
| name text/token stream | 6-30 bytes per item |
| behavior/action code | highly variable |
| generation table changes | variable |
| save/load compatibility | variable |

The hidden cost is old range assumptions. Code that was correct for a 64-row
catalog may still contain literal prompts, table bounds, unknown-name category
rules, or save/load block sizes that assume item IDs `0-63`.

## Lessons From The First Expansion

The first expansion from 64 to 66 IDs added:

| ID | Item | Category |
|---:|---|---|
| 64 | Main Gauche | weapon |
| 65 | Studded Leather Armor | armor |

This exposed several important contracts:

| Area | What went wrong | Required rule |
|---|---|---|
| Wizard/debug UI | Prompt still advertised `ITEM 0-63` | Every range-bearing user/debug string must be updated with the catalog count. |
| Item names | Appended equipment could be treated as unknown staff-like data | Unknown-name logic must be category-safe and migration defaults must keep mundane always-known items known. |
| Save migration | V1 saves contained only 64 known-item bytes | Legacy loads must initialize every byte beyond `LEGACY_ITEM_TYPE_COUNT` deterministically. |
| C128 layout | Small data growth still stressed resident/banked placement | Any catalog growth can require C128 layout work and full C128 verification. |
| Tests | Isolated table tests missed product wizard-to-inventory corruption | Product-path smoke tests are required for appended IDs, not only direct descriptor tests. |

The root failure was not that item ID 64 is special. The root failure was that
unknown-name lookup had ID-range assumptions from the old randomized
identification model. An appended equipment ID with `id_known = 0` was routed
through a staff-description shuffle table that did not contain that ID. The
inventory renderer then printed unrelated memory.

The fix was to make catalog growth explicit:

- Append IDs without renumbering legacy `0-63`.
- Keep a stable `ITEM_ID_CAPACITY` larger than `ITEM_TYPE_COUNT`.
- Migrate V1 known-state by reading the 64 legacy bytes, clearing future bytes,
  and marking appended mundane always-known items as known.
- Add direct item-description tests for appended IDs.
- Smoke the real wizard grant plus inventory display path on C64, C128, and
  Plus/4.
- Verify save/load with appended items in inventory.

## Expansion Gate Checklist

Before accepting any future item batch, all of these must be true:

| Gate | Required proof |
|---|---|
| Catalog constants | `ITEM_TYPE_COUNT`, `LEGACY_ITEM_TYPE_COUNT`, and `ITEM_ID_CAPACITY` have the intended relationship. |
| Table completeness | Every per-item table has one row for each implemented ID. |
| Name safety | Known and unknown name paths are valid for every appended ID category. |
| Identification defaults | New mundane equipment is known by default; randomized/identified item classes use intentional defaults. |
| Generation | Level pools or rarity buckets include only valid item IDs. |
| Wizard/debug | Prompts and input bounds match the implemented ID range. |
| Save migration | Old saves initialize all new known-state and live-state fields deterministically. |
| Product path | Wizard grant -> inventory display works for first and last appended ID. |
| Save/load path | Save and reload preserves appended IDs and renders their names correctly. |
| Platform layout | C64, C128, and Plus/4 memory assertions still pass. |
| Docs | `docs/WIZARD.md`, this plan, and save migration notes reflect the new catalog. |

For broad C128 banking, loader, layout, or runtime-loaded changes, `make
test128` is the acceptance gate. Narrow direct harnesses are diagnostics only.

## Catalog Size Reality

Current catalog sizes:

| Catalog | Raw item rows |
|---|---:|
| Moria8 | 64 |
| Umoria full table | 420 |
| VMS Moria parsed table | about 500 raw rows, including templates/duplicates |

Missing vs Umoria full table:

| Comparison | Missing rows |
|---|---:|
| Raw Umoria rows vs Moria8 | 356 |
| Dungeon/catalog rows excluding many fixtures | about 280 |
| Loot-ish rows including gold variants, excluding most fixtures | about 323 |

Chests specifically:

| Source | Chest rows |
|---|---:|
| Umoria | 7: six real chests plus ruined chest |
| VMS Moria | 6: six real chests |
| Moria8 | 0 |

## Naive Expansion Cost

If Moria8 simply appended source-style rows to the resident catalog:

| Scope | Added rows | Data/table growth | Runtime RAM/save growth | Likely code/text growth |
|---|---:|---:|---:|---:|
| Chests only | 7 | ~150-250 bytes | ~126 bytes for chest sidecars | ~1.5-2.5 KB |
| Abbreviated 96 total | +32 | ~700-1200 bytes | +32 bytes | ~1-3 KB |
| Rich abbreviated 128 total | +64 | ~1.4-2.5 KB | +64 bytes | ~3-6 KB |
| Full Umoria-ish | +280 to +356 | ~6-12 KB | +280-356 bytes | ~10-25 KB+ |

Conclusion: full resident expansion does not fit. C128 fails first. C64
banked space is already effectively full.

## Viable Architecture

The right design is to split runtime item instances from catalog definition
data.

| Layer | Keep resident | Move out of resident RAM |
|---|---|---|
| Item instance | item id, qty, p1, flags, ego, bonuses | none |
| Fast gameplay fields | category, glyph/color, equip slot, compact flags | maybe compressed |
| Full catalog fields | minimal resident index only | names, costs, weights, dice, AC, rarity, long metadata |
| Behavior | compact effect/profile dispatch | large text and rare lookup data |
| Generation | compact bucket selectors | full source-like rarity tables |

Recommended conceptual structure:

| Data | Resident? | Notes |
|---|---|---|
| `item_id` | yes | still one byte for abbreviated catalog |
| `category` | yes | needed constantly |
| `display glyph/color` | yes | needed for floor rendering |
| `behavior_profile` | yes | dispatches use/eat/quaff/read/aim/apply |
| `equip_profile` | yes | weapon, armor, light, ring, book, etc. |
| `effect_id` | yes or compact banked | potion/scroll/wand/staff/ring effect |
| `name_token_id` | resident index | points into banked/disk string data |
| full name text | banked/disk | loaded or decoded on demand |
| cost/weight/dice/ac | compressed resident or banked | depends on UI needs |
| generation rarity | banked or compact buckets | not needed every turn |

## Item ID Strategy

Item IDs `0-63` are the shipped v1.1.0 Save Format V1 catalog contract. They
are append-only after v1.1.0. Full catalog work must preserve those IDs and use
the migration rules in `docs/SAVE_FILE_MIGRATION.md`.

| Approach | Max catalog | Runtime cost | Implementation risk | Verdict |
|---|---:|---:|---:|---|
| Keep 1-byte item IDs | 255 | low | moderate | best for abbreviated catalog |
| Add 2-byte item IDs | 420+ | higher | high | required for literal full row catalog |
| Use `tval/sval` | very large | higher | high | source-faithful but invasive |
| Base item + variant profiles | large apparent catalog | moderate | moderate | best value |

Recommendation: keep one-byte IDs for now and target 128 or 192 items. Do not
move to 16-bit item IDs unless the product requirement is literally every
Umoria row distinct.

## 16-Bit Item ID Cost

For full 420-row catalog, one-byte IDs are insufficient.

Adding item ID high bytes affects at least:

| Area | Added RAM/save cost |
|---|---:|
| Floor item id high byte | 42 bytes |
| Inventory/equipment id high byte | 30 bytes |
| Store stock id high bytes | depends on store stock table |
| Save/load format | same live-state growth |
| Code size | widespread comparison/index changes |

The RAM cost is manageable. The code churn is the problem. Every item lookup,
pickup/drop, store operation, inventory display, save/load path, item action,
and generation routine must become 16-bit-aware or `tval/sval`-aware.

## Recommended Product Path

### Phase 1: Curated Abbreviated Catalog

Target: 96 or 128 item IDs.

Rules:

- Preserve one-byte item IDs.
- Add high-value missing item families first.
- Prefer rows that reuse existing behavior.
- Avoid one-off effects until architecture is stable.
- Do not add full source row granularity for every armor/weapon variant unless
  the gameplay distinction matters.

Best additions:

| Family | Add? | Reason |
|---|---|---|
| Chests | yes | new gameplay, source-faithful feature |
| More weapons | yes | low behavior cost |
| More armor | yes | low behavior cost |
| More potions | selective | medium behavior cost |
| More scrolls | selective | medium/high behavior cost |
| More rings | selective | persistent effect complexity |
| More wands/staves | selective | charges/effects complexity |
| Amulets | later | new equipment slot or rule decision |
| Junk/skeletons | no/low priority | flavor, low gameplay value |
| Full trap objects | no | map feature, not item catalog priority |
| Store-door/stair/door fixtures | no | not inventory items |

### Phase 2: Split Catalog

Introduce a compact resident item descriptor and move full catalog data out.

Resident fields:

| Field | Size |
|---|---:|
| category | 1 |
| display glyph | 1 |
| color | 1 |
| behavior profile | 1 |
| equip profile / flags | 1 |
| name token/index | 1 |
| min level / rarity bucket | 1 |
| packed combat/stat profile | 1-2 |

Goal: roughly 8-10 resident bytes per item, with less custom table duplication.

Banked/disk fields:

| Field |
|---|
| full name token stream |
| verbose description if any |
| source cost |
| source weight |
| exact dice |
| exact AC |
| generation rarity |
| store availability |

### Phase 3: Optional 16-Bit or `tval/sval`

Only do this if the explicit product requirement becomes full source catalog
fidelity.

A source-faithful design would use:

| Field | Meaning |
|---|---|
| `tval` | broad item type/category |
| `sval` | subtype |
| `p1` | charges, bonuses, timeout, or special payload |
| flags | curse, identify, sensed, known, chest flags, etc. |
| effect/profile | Moria8 compact behavior mapping |

This is cleaner long-term but larger and invasive.

## Current Moria8 Item Table

| ID | Item | Category |
|---:|---|---|
| 0 | Gold (small) | Gold |
| 1 | Gold (large) | Gold |
| 2 | Dagger | Weapon |
| 3 | Short Sword | Weapon |
| 4 | Long Sword | Weapon |
| 5 | Mace | Weapon |
| 6 | Robe | Armor |
| 7 | Leather Armor | Armor |
| 8 | Chain Mail | Armor |
| 9 | Small Shield | Shield |
| 10 | Iron Helm | Helm |
| 11 | Leather Gloves | Gloves |
| 12 | Leather Boots | Boots |
| 13 | Wooden Torch | Light |
| 14 | Brass Lantern | Light |
| 15 | Ration of Food | Food |
| 16 | Slime Mold | Food |
| 17 | Cure Light Wounds | Potion |
| 18 | Speed | Potion |
| 19 | Poison | Potion |
| 20 | Light | Scroll |
| 21 | Identify | Scroll |
| 22 | Teleportation | Scroll |
| 23 | Protection | Ring |
| 24 | Strength | Ring |
| 25 | Cure Serious Wounds | Potion |
| 26 | Restore Mana | Potion |
| 27 | Heroism | Potion |
| 28 | Blindness | Potion |
| 29 | Confusion | Potion |
| 30 | Detect Monsters | Potion |
| 31 | Infravision | Potion |
| 32 | Word of Recall | Scroll |
| 33 | Remove Curse | Scroll |
| 34 | Enchant Weapon | Scroll |
| 35 | Enchant Armor | Scroll |
| 36 | Monster Confusion | Scroll |
| 37 | Aggravate | Scroll |
| 38 | Protect from Evil | Scroll |
| 39 | Wand of Light | Wand |
| 40 | Wand of Lightning | Wand |
| 41 | Wand of Frost | Wand |
| 42 | Wand of Stinking Cloud | Wand |
| 43 | Staff of Light | Staff |
| 44 | Staff of Detect Monsters | Staff |
| 45 | Staff of Teleportation | Staff |
| 46 | Staff of Cure Light Wounds | Staff |
| 47 | Beginners-Magick | Book |
| 48 | Beginners Handbook | Book |
| 49 | Short Bow | Weapon |
| 50 | Light Crossbow | Weapon |
| 51 | Sling | Weapon |
| 52 | Arrow | Weapon/ammo |
| 53 | Bolt | Weapon/ammo |
| 54 | Rock | Weapon/ammo |
| 55 | Magick I | Book |
| 56 | Magick II | Book |
| 57 | The Mages Guide to Power | Book |
| 58 | Words of Wisdom | Book |
| 59 | Chants and Blessings | Book |
| 60 | Exorcism and Dispelling | Book |
| 61 | Flask of Oil | Light/throwable |
| 62 | Shovel | Digging |
| 63 | Pick | Digging |
| 64 | Main Gauche | Weapon |
| 65 | Studded Leather Armor | Armor |

## Source Catalog Comparison

| Item class | Umoria | VMS Moria | Moria8 |
|---|---:|---:|---:|
| Food / mushrooms | 34 | 33 | 2 |
| Swords / daggers | 24 | 29 | 3 collapsed |
| Hafted weapons / axes | 9 | 16 | 1 collapsed |
| Polearms | 13 | 13 | 0 |
| Bows | 6 | 10 raw, 6 meaningful | 3 |
| Ammo | 6 raw, 4 meaningful | 7 raw, 4 meaningful | 3 |
| Spikes | 1 | 2 raw, 1 meaningful | 0 |
| Light / oil | 6 raw, 3 meaningful | 5 raw, 3 meaningful | 3 |
| Digging | 6 | 6 | 2 |
| Boots | 3 | 5 raw, 3 meaningful | 1 collapsed |
| Gloves | 2 | 4 raw, 2 meaningful | 1 |
| Cloaks | 1 | 2 raw, 1 meaningful | 0 |
| Helms / crowns | 8 | 11 raw, 8 meaningful | 1 |
| Shields | 6 | 9 raw, 6 meaningful | 1 collapsed |
| Hard armor | 12 | 16 raw, 12 meaningful | 1 collapsed |
| Soft armor | 10 | 15 raw, 10 meaningful | 2 collapsed |
| Amulets | 9 | 13 raw, 9 meaningful | 0 |
| Rings | 30 | 35 raw, 30 meaningful | 2 |
| Staffs | 25 raw, 23 meaningful | 29 raw, 23 meaningful | 4 |
| Wands | 24 | 31 raw, 24 meaningful | 4 |
| Scrolls | 58 raw, 40 meaningful | 62 raw, 40 meaningful | 10 |
| Potions | 50 raw, 43 meaningful | 61 raw, similar meaningful set | 10 |
| Magic books | 4 | 8 raw, 4 meaningful | 4 |
| Prayer books | 4 | 8 raw, 4 meaningful | 4 |
| Chests | 7 | 6 | 0 |
| Junk / skeletons | 11 | 10 | 0 |
| Gold / gems | 18 raw | 17 raw | 2 collapsed |
| Traps | 19 raw | 35 raw | map feature, not item catalog |
| Rubble | 1 | 0 parsed | map feature |
| Doors | 3 | 1 | map feature |
| Stairs | 2 | 0 parsed | map feature |
| Store doors | 6 | 5 parsed | town/map feature |
| Nothing / sentinel | 2 | 0 parsed | 0 |

## Chests as Deferred Expansion Candidate

Chests are useful, but they are not the next catalog priority. The breadth-first
catalog expansion should add missing melee, armor, potions, scrolls, wands,
staves, rings, and lights before spending resident/item-state budget on chests.

Source-faithful chest rows:

| Chest | Umoria | VMS Moria | Moria8 current |
|---|---:|---:|---:|
| Small Wooden Chest | yes | yes | no |
| Large Wooden Chest | yes | yes | no |
| Small Iron Chest | yes | yes | no |
| Large Iron Chest | yes | yes | no |
| Small Steel Chest | yes | yes | no |
| Large Steel Chest | yes | yes | no |
| Ruined Chest | yes | no parsed row | no |

Required live chest state:

| Field | Size |
|---|---:|
| chest flags low | 42 bytes if per floor slot |
| chest flags high / content flags | 42 bytes |
| chest source level | 42 bytes |

Total proposed chest sidecar RAM: 126 bytes.

This should stay outside the fixed 256-byte floor item page.

## Product Recommendation

Recommended plan:

1. Expand missing ordinary catalog families toward the 96-slot runway.
2. Move names and full catalog metadata to banked/disk-loaded data before
   attempting broad row batches.
3. Introduce behavior profiles/effect IDs while expanding.
4. Defer chests until the ordinary catalog has better melee/armor/consumable
   coverage.
5. Defer 16-bit item IDs until a full-source-fidelity requirement is confirmed.

Implementation checkpoints:

- Save runway is in place for 96 known-item bytes: old 64-byte saves load with
  future known-item bytes cleared, and new saves write the fixed 96-byte block.
- Equipment loops now use `EQUIP_END` instead of hard-coded `EQUIP_RING + 1`;
  this prepares for adding an amulet slot without hunting every current ring-end
  loop again.
- Inventory capacity has moved to 31 total slots with `EQUIP_AMULET = 30`;
  `LEGACY_TOTAL_INV_SLOTS` records the prior 30-slot save/layout value for
  loading older saves.
- The first catalog breadth slice added two append-only equipment rows:
  `Main Gauche` and `Studded Leather Armor`. A four-row resident slice
  (`Main Gauche`, `Rapier`, `Studded Leather Armor`, `Large Shield`) crossed the
  C64 main-segment fit assert, so additional rows need byte recovery or catalog
  data relocation first.
- C128 resident selector layout is extremely tight: `128.select.prg` currently
  ends at `$AAFE`, one byte before the `$AB00` disk-I/O payload. Future selector
  work must recover bytes or move code before adding behavior there.
- Verification checkpoint: `make build`, `make test64`, and `make test128-fast`
  pass after the first catalog breadth slice.

Good 128-item target mix:

| Family | Current | Suggested target |
|---|---:|---:|
| Gold | 2 | 4-6 |
| Weapons/ammo | 14 | 25-32 |
| Armor/shields/helms/etc. | 9 | 20-28 |
| Food/light/digging | 7 | 10-14 |
| Potions | 10 | 18-24 |
| Scrolls | 10 | 18-24 |
| Rings | 2 | 8-12 |
| Wands | 4 | 8-12 |
| Staffs | 4 | 8-12 |
| Books | 8 | 8 |
| Chests | 0 | 7 |
| Amulets | 0 | optional 4-8 |

This gets most of the gameplay feel without forcing a full source-catalog port.

## Meaningful-Only Catalog Cut

The original ports contain many rows that add flavor, price spread, or
stat-gradation without changing player decisions much. For Moria8 product
planning, "meaningful" should mean a new verb, effect, risk, equipment role,
tactical answer, build choice, or save-relevant state.

| Bucket | Approx Umoria rows | Product value |
|---|---:|---|
| Meaningful inventory/loot items | ~110-140 | worth considering |
| Color/stat variants | ~170-220 | mostly compressible |
| Fixtures/sentinels/traps/store doors | ~40-70 | not item catalog work |
| Duplicate/store/template/source rows | variable | do not port literally |

Rows that should usually be collapsed or skipped:

| Source family | Product read |
|---|---|
| 24 sword/dagger rows | collapse to 4-6 weapon roles |
| 22+ hafted/polearm rows | collapse to 4-6 roles |
| 20+ armor rows | collapse by slot/weight/AC tier |
| 18 gold/gem rows | collapse to 3-5 value tiers |
| Junk/skeletons | mostly flavor, skip unless room exists |
| Store doors, stairs, doors, rubble | map features, not item catalog |
| Many mushrooms | duplicate potion effects, optional flavor |
| Full trap rows | map/trap system, not item catalog |

Meaningful-only target shape:

| Family | Current | Meaningful target | Why |
|---|---:|---:|---|
| Gold/value | 2 | 4-5 | economy variety, low code cost |
| Melee weapons | 4 | 8-10 | damage/weight/progression choices |
| Ranged/ammo | 6 | 6-8 | already mostly covered |
| Armor slots | 7 | 14-18 | equipment progression |
| Light/food/digging | 7 | 10-12 | utility/survival |
| Potions | 10 | 18-22 | major tactical effects |
| Scrolls | 10 | 18-22 | utility/mobility/detection |
| Rings | 2 | 10-12 | persistent build decisions |
| Amulets | 0 | 6-8 | meaningful if an amulet slot is added |
| Wands | 4 | 10-12 | tactical targeted effects |
| Staves | 4 | 10-12 | area/utility effects |
| Books | 8 | 8 | already complete enough |
| Chests | 0 | 7 | source-faithful new gameplay |

Recommended meaningful additions:

| Family | Candidate additions |
|---|---|
| Chests | Small/Large Wooden, Iron, and Steel Chests; Ruined Chest |
| Rings | Resist Fire, Resist Cold, See Invisible, Feather Falling, Slow Digestion, Teleportation, Damage, To-Hit, Slaying, Sustain Stat |
| Amulets | Wisdom, Charisma, Searching, Slow Digestion, Resist Acid, the Magi, DOOM |
| Potions | Cure Critical Wounds, Healing, Restore Life Levels, Gain Experience, Neutralize Poison, Resist Heat, Resist Cold, Invulnerability, selected stat gain/restore effects |
| Scrolls | Phase Door, Teleport Level, Magic Mapping, Treasure/Object/Trap Detection, Door/Stair Location, Recharging, Genocide, Mass Genocide, Rune of Protection, Trap/Door Destruction, Destruction |
| Wands | Magic Missile, Stone-to-Mud, Polymorph, Teleport Away, Disarming, Trap/Door Destruction, Drain Life, Fire/Cold/Lightning Balls |
| Staves | Object Location, Trap Location, Door/Stair Location, Speed, Slow Monsters, Sleep Monsters, Detect Evil, Curing, Earthquakes, Destruction |
| Equipment | Cloak, Gauntlets, Hard Boots, heavy armor, plate armor, better shield, soft/hard cap, Steel Helm |
| Weapons | Heavy sword, axe, spear/polearm, war hammer/flail, heavy bow/crossbow |

Product recommendation: port roles, not every source row. Keep source names
where they add flavor, but collapse rows that only change dice, AC, cost, or
weight unless they create a real equipment choice. A meaningful-only catalog of
about 128 item IDs is the best near-term target.

## Final Judgment

- Full catalog using current resident table model: no.
- Full catalog using split/banked catalog architecture: yes, possible.
- Abbreviated catalog using one-byte IDs and split data: yes, recommended.
- Literal Umoria 420-row catalog: possible only with 16-bit IDs or `tval/sval`,
  plus major save/UI/store/generation/action work.

Confidence: high on the memory conclusion, moderate-high on the recommended
architecture.
