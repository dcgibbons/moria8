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

Current Moria8 has 96 item type IDs.

Relevant current constants:

| Constant | Value | Meaning |
|---|---:|---|
| `ITEM_TYPE_COUNT` | 96 | Current item catalog size |
| `MAX_FLOOR_ITEMS` | 42 | Max live floor item slots |
| `MAX_INV_SLOTS` | 22 | Carried inventory slots |
| `MAX_EQUIP_SLOTS` | 9 | Equipment slots |
| `TOTAL_INV_SLOTS` | 31 | Inventory + equipment slots |
| `FI_EMPTY` | `$ff` | Empty item slot sentinel |

Current linked headroom after the 88-item slice:

| Target | Most relevant free space | Verdict |
|---|---:|---|
| C64 | must be remeasured after each batch | Tight; overlay-only growth |
| C128 | must be remeasured after each batch | Item storage has runway, but UI/death/world/play remain tight |
| Plus/4 | must be remeasured after each batch | Workable but still tight |

The C128 is the limiting platform.

## Measured C128 Resident Item Ledger

Before Phase 1A, the C128 problem was not theoretical. `128.item.prg` occupied
7,051 bytes at `$8C70-$A7FA`, leaving only 5 bytes before the resident selector
at `$A800`.

Original measured chunks from `commodore/c128/main.sym` before the Bank 1
name-stream relocation:

| Chunk | Address range | Bytes | Notes |
|---|---:|---:|---|
| C128 resident item prefix | `$8C70-$8C90` | 33 | C128-only strings/scratch before common item import |
| fixed SoA tables `category..min_level` | `$8C91-$9000` | 880 | 10 resident bytes per item |
| compact missile table | `$9001-$9015` | 21 | Bounded ranged-only table |
| known-name pointer tables | `$9016-$90C5` | 176 | 2 resident bytes per item |
| name-token pointer tables | `$90C6-$90FB` | 54 | 27 token pointers |
| name-token strings | `$90FC-$91CC` | 209 | Shared name fragments |
| known item-name streams | `$91CD-$94BD` | 753 | Fixed/tokenized item names |
| inventory/equipment arrays | `$94BE-$95B5` | 248 | Live item slots |
| floor stat sidecars | `$95B6-$9633` | 126 | Split floor hit/dam/AC sidecars |
| glyph arrays | `$9634-$963F` | 12 | Glyph-of-warding state |
| item add/generation scratch | `$9640-$964B` | 12 | Floor-add scratch |
| core item code before spawn | `$964C-$990D` | 706 | Add/remove/find helpers |
| spawn/pickup/description/drop code | `$990E-$9DF1` | 1,252 | Live gameplay item logic |
| enchantment scratch/code | `$9DF2-$9F5F` | 366 | Generation-time equipment magic |
| `id_known` save runway | `$9F60-$9FBF` | 96 | Already fixed at `ITEM_ID_CAPACITY = 96` |
| unknown-description metadata | `$9FC0-$A017` | 88 | 1 byte per implemented item |
| shuffle RAM tables | `$A018-$A03D` | 38 | Potion/scroll/ring/wand/staff shuffles |
| unknown-name strings | `$A03E-$A106` | 201 | Randomized class names |
| unknown-name pointers/colors | `$A107-$A1B6` | 176 | Randomized class pointer/color tables |
| identification code/decode buffer | `$A1B7-$A7FA` | 1,604 | Init, lookup, decode, and buffer |

Raw growth from 88 to 96 is not eight bytes. It is at least:

| Data | 8-item growth |
|---|---:|
| fixed SoA tables | 80 bytes |
| known-name pointers | 16 bytes |
| unknown-description metadata | 8 bytes |
| item-name streams | usually 50-120 bytes |
| generation bucket table | 8 bytes, but already in the dungeon-generation overlay |
| `id_known` | 0 bytes until capacity exceeds 96 |

That meant the next 8 rows needed roughly 150-230 bytes of `128.item` relief
before behavior/effect code. Reaching 128 with the current byte-per-row model
would still need roughly 900-1,200 resident bytes plus effect code.

Phase 1A recovered resident space by replacing full base-cost high bytes with
sparse high-byte exceptions and removing the product known-name high-byte table.
An attempted C128 move of `it_cost_lo` to `TownOverlay` was rejected after
runtime testing because town entry could CPU JAM when the executable overlay
started with data. C64 and Plus/4 still place the low cost table in
`TownOverlay`; C128 keeps it in `128.item`.

| Change | C128 `128.item` impact | Tradeoff |
|---|---:|---|
| Keep `it_cost_lo` resident on C128 | 0 resident bytes | Correctness fix: town overlay entry remains code-owned. |
| Replace `it_cost_hi` with sparse high-byte exceptions | -79 resident bytes net | Store pricing scans 9 high-byte exceptions. |
| Remove product `it_name_hi` and derive high bytes from `it_name_lo` page crossings | about -62 resident bytes net | Name lookup spends a small loop instead of a resident high-byte table. |

After the corrected Phase 1A, `128.item.prg` occupied `$8C70-$A780`, leaving
127 bytes before `128.select` at `$A800`.

Phase 1B then moved only the known item-name token streams into a new C128
Bank 1 resident data payload, `128.names.prg`, loaded at `$7400`. The token
dictionary and all unknown/randomized-name tables remain in `128.item`; only
known-name source bytes are read through the existing C128 Bank 1 DB helpers.
Current C128 product layout:

| Payload | Current range | Free/notes |
|---|---:|---|
| `128.names` | `$7400-$76F0` | Lives inside Bank 1 DB/data `$7400-$7FFF`; 2,319 bytes remain in that DB window. |
| `128.item` | `$8C70-$A4FA` | 773 bytes free before `128.select` at `$A800`. |
| Main program | `$1C0E-$5F9E` | 97 bytes free before `128.world` at `$6000`; loader growth is now tight. |

The C128 runtime loader now has an explicit Bank 1 load path for this payload:
`128.names` uses logical file 14, the save/media marker remains logical file 13,
and the command channel remains 15. The preload sequence loads world, item
resident data, Bank 1 item names, then selector data before gameplay can decode
known item names.

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
| 66 | Rapier | weapon |
| 67 | Broad Sword | weapon |
| 68 | Bastard Sword | weapon |
| 69 | Two-Handed Sword | weapon |
| 70 | Scimitar | weapon |
| 71 | Battle Axe | weapon |
| 72 | War Hammer | weapon |
| 73 | Morningstar | weapon |
| 74 | Spear | weapon |
| 75 | Pike | weapon |
| 76 | Halberd | weapon |
| 77 | Quarterstaff | weapon |

This exposed several important contracts:

| Area | What went wrong | Required rule |
|---|---|---|
| Wizard/debug UI | Prompt still advertised `ITEM 0-63` | Every range-bearing user/debug string must be updated with the catalog count. |
| Item names | Appended equipment could be treated as unknown staff-like data | Unknown-name logic must be category-safe and migration defaults must keep mundane always-known items known. |
| Save migration | V1 saves contained only 64 known-item bytes | Legacy loads must initialize every byte beyond `LEGACY_ITEM_TYPE_COUNT` deterministically. |
| Ranged metadata | Melee IDs above the missile table could read adjacent code as missile metadata | Narrow per-class tables need explicit lower and upper bounds before IDs from other classes can live above them. |
| Resident memory | The second melee slice crossed both the C64 runtime `$C000` boundary and the C128 resident-items `$A800` boundary | Every slice must be treated as memory work, not only catalog data work; recover bytes or shrink the slice before testing. |
| C128 layout | Small data growth still stressed resident/banked placement | Any catalog growth can require C128 layout work and full C128 verification. |
| Generation pool | IDs can exist in wizard/tests but still be absent from random dungeon loot or stores | `pit_sorted`/`pit_level_bounds` and store sampling must grow with the catalog, with asserts or constants instead of old literal ceilings. |
| Tests | Isolated table tests missed product wizard-to-inventory corruption, and explicit expected-name fixtures stopped at the old high ID | Product-path smoke tests are required for appended IDs, and every explicit catalog fixture must grow with `ITEM_TYPE_COUNT`. |

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
- Bound class-specific compact tables on both ends; do not let a high item ID
  index through adjacent data or code.
- Keep normal-game acquisition paths in sync: random floor generation and store
  restocking must include intended appended IDs, not only wizard item grant.
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
| Store stock | Store restocking samples through `ITEM_TYPE_COUNT` and filters by explicit store category. |
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

## Architecture Strategy Overview

### Strategy A: Curated Abbreviated Catalog

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

### Strategy B: Split Catalog

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

### Strategy C: Optional 16-Bit or `tval/sval`

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
| 66 | Rapier | Weapon |
| 67 | Broad Sword | Weapon |
| 68 | Bastard Sword | Weapon |
| 69 | Two-Handed Sword | Weapon |
| 70 | Scimitar | Weapon |
| 71 | Battle Axe | Weapon |
| 72 | War Hammer | Weapon |
| 73 | Morningstar | Weapon |
| 74 | Spear | Weapon |
| 75 | Pike | Weapon |
| 76 | Halberd | Weapon |
| 77 | Quarterstaff | Weapon |
| 78 | Large Shield | Shield |
| 79 | Hard Leather Armor | Armor |
| 80 | Scale Mail | Armor |
| 81 | Plate Mail | Armor |
| 82 | Cloak | Armor |
| 83 | Steel Helm | Helm |
| 84 | Gauntlets | Gloves |
| 85 | Soft Leather Boots | Boots |
| 86 | Hard Leather Boots | Boots |
| 87 | Metal Cap | Helm |
| 88 | Sabre | Weapon |
| 89 | Cutlass | Weapon |
| 90 | Tulwar | Weapon |
| 91 | Katana | Weapon |
| 92 | Flail | Weapon |
| 93 | Lucerne Hammer | Weapon |
| 94 | Broad Axe | Weapon |
| 95 | Awl-Pike | Weapon |

## Source Catalog Comparison

| Item class | Umoria | VMS Moria | Moria8 |
|---|---:|---:|---:|
| Food / mushrooms | 34 | 33 | 2 |
| Swords / daggers | 24 | 29 | 15 selected |
| Hafted weapons / axes | 9 | 16 | 7 selected |
| Polearms | 13 | 13 | 5 selected |
| Bows | 6 | 10 raw, 6 meaningful | 3 |
| Ammo | 6 raw, 4 meaningful | 7 raw, 4 meaningful | 3 |
| Spikes | 1 | 2 raw, 1 meaningful | 0 |
| Light / oil | 6 raw, 3 meaningful | 5 raw, 3 meaningful | 3 |
| Digging | 6 | 6 | 2 |
| Boots | 3 | 5 raw, 3 meaningful | 3 selected |
| Gloves | 2 | 4 raw, 2 meaningful | 2 selected |
| Cloaks | 1 | 2 raw, 1 meaningful | 1 |
| Helms / crowns | 8 | 11 raw, 8 meaningful | 3 selected |
| Shields | 6 | 9 raw, 6 meaningful | 2 selected |
| Hard armor | 12 | 16 raw, 12 meaningful | 3 selected |
| Soft armor | 10 | 15 raw, 10 meaningful | 3 selected |
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

## Phased Product Plan

The catalog plan has two near-term milestones:

| Milestone | Target | Meaning |
|---|---:|---|
| 96 items | IDs `0-95` | Controlled append within the existing `ITEM_ID_CAPACITY = 96` save runway |
| 128 items | IDs `0-127` | Requires catalog representation cleanup before broad row growth |

The 96 milestone should be treated as a hardening milestone. The 128 milestone
should be treated as an architecture milestone.

### Phase 0: Expansion Hardening

Goal: make the next item batch boring before adding many rows.

Required work:

0. Recover C64 resident bytes before adding any new resident catalog-routing
   code. Current clean C64 product build ends at `$C166`, and the boundary
   assert has effectively no usable slack. During Phase 0 implementation, a
   66-byte packed unknown-description table failed C64 layout, and even a
   7-byte `item_get_name_ptr` guard moved the image to `$C16D` and failed the
   product boundary assert. This means the design is sound but cannot be landed
   as resident code until bytes are recovered or the routing metadata moves out
   of the hot C64 image.
1. Add an explicit unknown-identification class per item row.
   Suggested classes: fixed, potion, scroll, ring, wand, staff, and future
   amulet. Unknown-name and unknown-color logic must switch on this class, not
   numeric ID ranges.
2. Add an explicit migration known-default per item row or per appended range.
   Mundane equipment, food, books, and fixed-name tools default to known.
   Randomized identification classes default to unknown only when their
   shuffled unknown-name/color tables cover the ID.
3. Replace remaining `0-63` assumptions in generation, stores, wizard/debug UI,
   and tests with `ITEM_TYPE_COUNT`, explicit item lists, or documented legacy
   constants.
4. Add product-path smoke coverage for the first and last appended ID in each
   batch: wizard grant, inventory display, floor display/color, save/load, and
   resume.
5. Recover or relocate resident bytes before adding the full 96-row batch.

Acceptance gate:

| Gate | Required proof |
|---|---|
| Resident space | C64 has enough reclaimed bytes to add metadata/routing without crossing the product boundary. |
| Name routing | No unknown item can fall through into the wrong shuffled table. |
| Save defaults | Legacy saves initialize every appended ID deterministically. |
| Table coverage | Every `it_*` table and new class/default table asserts to `ITEM_TYPE_COUNT`. |
| Product smoke | C64, C128, and Plus/4 can grant, display, save, and reload appended IDs. |
| Dungeon transition smoke | C64 and Plus/4 can descend into a generated dungeon, accept the immediate up-stairs command, and enter the town-return path after item spawning. |
| Memory | C64/C128/Plus4 layout asserts pass without weakening boundaries. |

Phase 0 implementation status:

- C64 resident bytes were recovered by removing the hidden C64U `V` timing
  diagnostic. Actual C64U detection and fast/normal wrappers remain in place.
- The C64 build log's default-segment end includes an init-only startup tail
  that runs before the dungeon map owns `MAP_BASE`. The runtime `program_end`
  after metadata hardening was below `$C000`, but the emitted PRG still reports
  addresses above `$C000`. Treat this as tight and easy to misread, not
  spacious.
- The first Phase 1 melee slice raised `ITEM_TYPE_COUNT` to 70 by adding
  `Rapier`, `Broad Sword`, `Bastard Sword`, and `Two-Handed Sword`.
- The second Phase 1 melee slice raised `ITEM_TYPE_COUNT` to 74 by adding
  `Scimitar`, `Battle Axe`, `War Hammer`, and `Morningstar`.
- The third Phase 1 melee slice raised `ITEM_TYPE_COUNT` to 78 by adding
  `Spear`, `Pike`, `Halberd`, and `Quarterstaff`.
- The first defensive-equipment slice raised `ITEM_TYPE_COUNT` to 80 by adding
  `Large Shield` and `Hard Leather Armor`. A four-row defensive slice crossed
  the C64 resident boundary, so the accepted slice stayed at two rows and
  recovered bytes by returning picker/depth ownership to the generation
  overlay.
- The second defensive-equipment slice raised `ITEM_TYPE_COUNT` to 82 by
  adding `Scale Mail` and `Plate Mail`. This continued the fixed-known body
  armor path without adding randomized unknown descriptors or new item
  behavior. It initially overflowed the C128 resident-items segment by 14
  bytes; suffix-tokenizing repeated item-name fragments (`Armor`, ` Mail`, and
  ` Shield`) preserved player-facing names and brought the segment back to the
  `$A7FF` boundary.
- The third defensive-equipment slice raised `ITEM_TYPE_COUNT` to 88 by adding
  `Cloak`, `Steel Helm`, `Gauntlets`, `Soft Leather Boots`, `Hard Leather
  Boots`, and `Metal Cap`. These remain fixed-known equipment rows within the
  current simplified slot model; `Cloak` uses the existing armor/body slot
  rather than introducing a new cloak slot.
- That slice also corrected normal acquisition coverage for appended melee:
  `pit_sorted` now includes IDs `66-81`, `pit_level_bounds` has compile-time
  size assertions, and store restocking samples through `ITEM_TYPE_COUNT`
  before applying store-category filters.
- The item-type picker and its depth tables moved into the dungeon-generation
  overlay for product builds on C64, C128, and Plus/4. The public
  `pick_item_type` label remains a resident wrapper, because callers cannot
  assume the generation overlay is still visible after other product
  trampolines run. This recovered resident bytes without moving item names,
  item instances, or wizard enchantment logic.
- The initial overlay ownership attempt was wrong: putting `item_spawn_level`
  itself inside the generation trampoline assumed the generation overlay would
  stay visible for every nested call. Item spawning can call special-room and
  ego trampolines that restore normal banking before returning, so the next
  `pick_item_type` call jumped into non-overlay memory and produced a C64 CPU
  JAM on stairs-up generation. The corrected rule is narrower: keep
  `item_spawn_level` resident, keep `pick_item_type` as a resident entry point,
  and put only the picker implementation plus `pit_sorted`/`pit_level_bounds`
  in the dungeon-generation overlay.
- Plus/4 needs a platform-specific `pick_item_type` wrapper. During dungeon
  generation it must not call the prompt-capable generic `overlay_load`, and it
  must leave Plus/4 RAM visible before calling the `$E000` overlay
  implementation. The accepted path checks `current_overlay`, calls
  `overlay_load_disk` only when the generation overlay is absent, sets
  `current_overlay`, banks RAM visible with `plus4_bank_ram`, and falls back to
  item ID `2` if the program disk load fails.
- C64 and Plus/4 now have product dungeon-ascent smokes for this failure class.
  They script a new game, move onto the town stairs, descend, and immediately
  press `<`. Passing requires reaching `tramp_store_restock_all`, which proves
  that item spawning completed, input resumed, the player remained on the
  generated up-stairs, and the town-return transition began without a JAM or
  hidden media prompt.
- The second slice initially failed memory assertions. The accepted layout
  recovered shared resident bytes by tokenizing repeated unknown-name articles
  and shrinking the dedicated item-name decode buffer to the current catalog's
  maximum needs. It recovered C128 resident-items space by moving C128
  game-loop low data from `C128ResidentItems` to `C128ResidentPlay`, where the
  game-loop code already lives.
- That slice also hardened `item_get_missile` with an upper bound, because
  melee IDs above the compact ranged table must return non-ranged rather than
  reading the following code bytes.
- `it_unknown_desc` is now the explicit per-row unknown-description descriptor.
  It asserts to `ITEM_TYPE_COUNT`.
- Unknown name and floor-color routing now use descriptor class/index instead
  of numeric ID ranges. Fixed-name rows forced to unknown fall back to real
  item name/color rather than indexing a shuffled table out of bounds.
- Legacy save migration now derives appended known-state defaults from
  `it_unknown_desc`: fixed rows default known, randomized rows default unknown,
  and future capacity bytes are cleared.
- When adding IDs `66-95`, extend `it_unknown_desc` in lockstep with
  `ITEM_TYPE_COUNT`. Do not add randomized appended IDs unless their shuffled
  unknown-name/color pools cover the class-local descriptor indexes.

### Phase 1: Reach 96 Items

Goal: fill the existing 96-ID runway with high-value ordinary loot and a small
number of low-risk consumable/magic rows.

Current status: IDs `0-95` are implemented. Phase 1A/1B catalog-storage relief
is complete: C128 known-name streams live in the boot-loaded Bank 1
`128.names` payload, and the 96-ID save runway is now filled.

Rules:

- Preserve one-byte item IDs.
- Preserve IDs `0-63`.
- Keep `ITEM_ID_CAPACITY = 96`.
- Grow `ITEM_TYPE_COUNT` only as implemented rows are added.
- Prefer fixed-known equipment before randomized classes.
- Do not add chest sidecar state in this milestone.
- For the release parking point, IDs `88-95` intentionally use fixed-known
  ordinary weapons instead of the earlier randomized consumable/magic proposal.
  This keeps the 96-item milestone data-only and avoids adding potion, scroll,
  ring, wand, or staff behavior during release stabilization.

Target appended rows:

| ID | Item | Class | Notes |
|---:|---|---|---|
| 66 | Rapier | weapon | Fixed-known melee progression |
| 67 | Broad Sword | weapon | Fixed-known melee progression |
| 68 | Bastard Sword | weapon | Fixed-known melee progression |
| 69 | Two-Handed Sword | weapon | Fixed-known heavy melee |
| 70 | Scimitar | weapon | Fixed-known melee variety |
| 71 | Battle Axe | weapon | Fixed-known hafted/axe role |
| 72 | War Hammer | weapon | Fixed-known hafted role |
| 73 | Morningstar | weapon | Fixed-known hafted role |
| 74 | Spear | weapon | Fixed-known polearm role |
| 75 | Pike | weapon | Fixed-known polearm role |
| 76 | Halberd | weapon | Fixed-known polearm role |
| 77 | Quarterstaff | weapon | Fixed-known light blunt role |
| 78 | Large Shield | shield | Fixed-known defensive progression |
| 79 | Hard Leather Armor | armor | Fixed-known soft armor tier |
| 80 | Scale Mail | armor | Fixed-known hard armor tier |
| 81 | Plate Mail | armor | Fixed-known hard armor tier |
| 82 | Cloak | armor | Fixed-known missing slot family |
| 83 | Steel Helm | helm | Fixed-known head progression |
| 84 | Gauntlets | gloves | Fixed-known hand progression |
| 85 | Soft Leather Boots | boots | Fixed-known foot progression |
| 86 | Hard Leather Boots | boots | Fixed-known foot progression |
| 87 | Metal Cap | helm | Fixed-known low head tier |
| 88 | Sabre | weapon | Fixed-known blade progression |
| 89 | Cutlass | weapon | Fixed-known blade progression |
| 90 | Tulwar | weapon | Fixed-known blade progression |
| 91 | Katana | weapon | Fixed-known premium blade |
| 92 | Flail | weapon | Fixed-known hafted role |
| 93 | Lucerne Hammer | weapon | Fixed-known hafted role |
| 94 | Broad Axe | weapon | Fixed-known axe role |
| 95 | Awl-Pike | weapon | Fixed-known polearm role |

Why this shape:

- 22 of 30 new rows are fixed-known equipment, which minimizes identification
  and behavior risk.
- The batch restores missing melee, polearm, armor, shield, helm, glove, and
  boot variety before adding lower-priority systems.
- The final eight rows intentionally avoid randomized identification and
  effect-code growth so 96 can serve as a release parking point.

Implementation slices:

1. Complete Phase 1A/1B C128 catalog-storage relief. Done.
2. Add IDs `88-95` as fixed-known ordinary equipment.
3. Defer randomized potion/scroll/ring/wand/staff rows to the post-96 design.
4. Update wizard docs and item catalog docs after each accepted slice.

#### Phase 1A/1B: C128 Catalog-Storage Relief

Goal: create enough `128.item` space for IDs `88-95` without weakening memory
asserts, shortening player-facing strings, or moving the `$A800` selector
boundary.

Preferred order:

1. Move known-name pointer tables and known-name streams behind a C128-safe
   name lookup boundary, or otherwise remove their per-row resident growth from
   `128.item`. Current resident cost is 929 bytes for known-name pointers plus
   known name streams, before token tables.
2. If name relocation is too broad for the first pass, introduce compact
   numeric/stat profiles for fixed equipment fields. Current fixed SoA tables
   cost 880 bytes and grow by 10 bytes per row.
3. Keep `pit_sorted` and `pit_level_bounds` in the dungeon-generation overlay;
   they are already relocated for product builds and are not the next
   meaningful resident target.
4. Avoid moving `C128ResidentSelect`, `C128ResidentDiskIo`, or the `$AF00`
   play/persist boundary unless the catalog-local options fail. Those are
   broader C128 layout changes.

Phase 1A/1B acceptance gate:

| Gate | Required proof |
|---|---|
| Memory | `128.item` has at least 230 bytes free before `$A800`; more is better. Current Phase 1B leaves 773 bytes. |
| No disk churn | Inventory/store/name display does not require per-item disk loads. |
| Name correctness | All implemented item names still pass item-description tests on C64 and C128. |
| Product paths | Wizard grant, inventory display, store display, dungeon pickup, and save/load still work. |
| C128 layout | `make test128` passes if the implementation changes C128 loading, banking, copied code, or runtime segment starts. |

Phase 1A/1B implementation status:

- Partially complete. C64 and Plus/4 move `it_cost_lo` to `TownOverlay`, but
  C128 keeps `it_cost_lo` resident after runtime testing exposed a town-entry
  CPU JAM when the executable town overlay started with cost data.
- Complete. Product builds replaced the full resident `it_cost_hi` table with
  sparse high-byte exceptions used by store pricing.
- Complete. Product builds no longer emit the resident `it_name_hi` table.
  Known-name lookup derives the stream high byte by counting low-byte page
  crossings in the existing `it_name_lo` table. Names remain resident; this is
  not a disk-backed name path.
- Complete. C128 known-name streams now live in `128.names.prg`, loaded once at
  startup into Bank 1 `$7400-$76F0`. The token dictionary remains in
  `128.item`; known-name decoding reads only stream source bytes through
  `mmu_safe_db_read_ptr0`.
- C128 `128.item` now ends at `$A4FA`, leaving 773 bytes before `$A800`.
  C128 town overlay now ends at `$EF78`, leaving 136 bytes; C64 and Plus/4
  town overlays still end at `$EFE1`, leaving 30 bytes.
- Validation: focused C128 `memory128|item_desc128|boot_title|town|load_resume|main_loop128`
  passed 15/15, full `make test128` passed 118/118, and `make disk128` builds
  the product disk with `128.names`.

Phase 1 acceptance gate:

| Gate | Required proof |
|---|---|
| Build | `make build` passes. |
| C64 | `make test64` passes and product smoke covers IDs 66 and 95. |
| C128 | `make test128` passes after any C128 layout/banking/runtime-loaded change. |
| Plus/4 | `make testplus4` or relevant product smoke passes for appended IDs. |
| Save/load | Old 64-ID saves, current 66-ID saves, and new 96-ID saves load deterministically. |
| Manual smoke | Wizard grant of IDs 66 and 95 renders correct inventory text after save/load. |

### Phase 2: Prepare 128-Capable Catalog

Goal: reduce resident cost and save-state cost before growing beyond 96.

Required work before setting `ITEM_ID_CAPACITY = 128`:

1. Convert `id_known` to a bitset, or hide it behind accessors with a compact
   save/load representation.
2. Move cold item names and name-token streams out of scarce resident catalog
   space where practical.
3. Pack or profile duplicate combat/stat fields:
   - damage dice count/sides
   - base AC
   - weight
   - cost
   - equip slot/profile
4. Replace generation and store selection range logic with explicit eligible
   lists or bucket tables.
5. Decide the amulet category/store-mask model before adding amulet rows.
6. Update save layout documentation and migration code for the 128-capacity
   known-state representation.

Resident target:

| Data | Target |
|---|---|
| Hot item row | about 7-9 resident bytes |
| Known state | 16 bytes for 128 IDs if bitset |
| Names | banked/cold where possible |
| Generation/store rarity | explicit lists or banked/cold tables |

Phase 2 acceptance gate:

| Gate | Required proof |
|---|---|
| Compatibility | Saves from V1, 66-item V2/V3, and 96-item saves migrate correctly. |
| Accessors | All known-state reads/writes go through the new representation. |
| Memory | C128 has real headroom, not byte-level luck. |
| Product paths | Unknown randomized display, fixed-known display, store display, and save/load work under product smoke. |

### Phase 3: Reach 128 Items

Goal: add high-value consumables, rings, wands, staves, and first amulets after
the 128-capable representation exists.

Target appended rows:

| ID | Item | Class | Notes |
|---:|---|---|---|
| 96 | Potion of Restore Strength | potion | Randomized stat restoration |
| 97 | Potion of Restore Intelligence | potion | Randomized stat restoration |
| 98 | Potion of Restore Wisdom | potion | Randomized stat restoration |
| 99 | Potion of Restore Dexterity | potion | Randomized stat restoration |
| 100 | Potion of Restore Constitution | potion | Randomized stat restoration |
| 101 | Potion of Resist Heat | potion | Randomized resistance |
| 102 | Potion of Resist Cold | potion | Randomized resistance |
| 103 | Potion of Cure Poison | potion | Randomized utility |
| 104 | Scroll of Phase Door | scroll | Randomized mobility |
| 105 | Scroll of Treasure Detection | scroll | Randomized detection |
| 106 | Scroll of Object Detection | scroll | Randomized detection |
| 107 | Scroll of Detect Curse | scroll | Randomized identification support |
| 108 | Scroll of Rune of Protection | scroll | Randomized tactical utility |
| 109 | Scroll of Create Monster | scroll | Randomized risk item |
| 110 | Scroll of Sleep Monster | scroll | Randomized control |
| 111 | Scroll of Genocide | scroll | Randomized high-value effect |
| 112 | Ring of Dexterity | ring | Persistent stat choice |
| 113 | Ring of Constitution | ring | Persistent stat choice |
| 114 | Ring of Searching | ring | Persistent utility |
| 115 | Ring of See Invisible | ring | Persistent utility |
| 116 | Ring of Speed | ring | Persistent speed |
| 117 | Ring of Sustain Strength | ring | Persistent sustain effect |
| 118 | Wand of Slow Monster | wand | Charged control |
| 119 | Wand of Polymorph | wand | Charged transformation |
| 120 | Wand of Sleep Monster | wand | Charged control |
| 121 | Wand of Stone-to-Mud | wand | Charged utility |
| 122 | Staff of Detect Evil | staff | Charged detection |
| 123 | Staff of Cure Serious Wounds | staff | Charged healing |
| 124 | Staff of Remove Curse | staff | Charged utility |
| 125 | Staff of Dispel Evil | staff | Charged damage/control |
| 126 | Amulet of Wisdom | amulet | Requires amulet slot/category decision |
| 127 | Amulet of Charisma | amulet | Requires amulet slot/category decision |

Phase 3 acceptance gate:

| Gate | Required proof |
|---|---|
| Full build/test | `make build`, `make test64`, `make test128`, and Plus/4 product smoke pass. |
| Boundary IDs | Wizard grant/display/save/load works for IDs 96 and 127. |
| Randomized classes | Unknown-name/color tables cover every randomized class-local index. |
| Store/generation | New eligible-list/bucket generation produces only valid implemented IDs. |
| Amulets | Equip, remove, save/load, and display work through `EQUIP_AMULET`. |

### Deferred: Chests And Full Source Fidelity

Chests remain deferred until after 128 unless product priorities change. They
are not just rows; they require live sidecar state for trap/content/source-level
data.

Full 420-row source fidelity remains a separate architecture project requiring
16-bit IDs or a `tval/sval` identity model.

## Product Recommendation

Recommended plan:

1. Complete Phase 0 before adding more than tiny fixed-known equipment slices.
2. Reach 96 with ordinary catalog breadth and limited randomized rows.
3. Complete the 128-capable representation before raising capacity beyond 96.
4. Reach 128 with high-value consumables, rings, wands, staves, and first
   amulets.
5. Defer chests and 16-bit item IDs until the ordinary catalog is balanced.

Implementation checkpoints already completed:

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
- C128 resident items and selector layout is extremely tight: `128.item.prg`
  currently occupies `$8C70-$A7FA`, leaving 5 bytes before the `$A800`
  selector payload, and `128.select.prg` currently ends at `$AAE0`, 31 bytes
  before the `$AB00` disk-I/O payload. Future item work must recover catalog
  bytes before adding IDs `88-95`.
- Verification checkpoint: `make build`, focused C64 item/store/save tests,
  `make test128-fast`, and focused Plus/4 runtime smoke passed after the
  88-item slice.

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
