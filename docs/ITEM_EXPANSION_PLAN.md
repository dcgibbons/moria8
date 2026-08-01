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
| `MAX_EQUIP_SLOTS` | 9 | Stored equipment slots |
| `VISIBLE_EQUIP_SLOTS` | 8 | Currently displayed equipment slots |
| `TOTAL_INV_SLOTS` | 31 | Inventory + equipment slots |
| `FI_EMPTY` | `$ff` | Empty item slot sentinel |

Current linked headroom (measured from the 2026-07-31 build symbols;
see the Space Recovery Analysis section for the full inventory and funding
options):

| Target | Resident/catalog area free | Largest other item-relevant space |
|---|---:|---|
| C64 | 1 byte (`program_end=$BFFF`, boundary `$C000`); banked 0 bytes | gen overlay 495 B; ~7.6 KB total overlay slack; ~1,240 B hidden tier-name pool tail |
| C128 | `128.item` ~7 bytes; main 4 bytes; play 10 bytes; banked 17 bytes | Bank 1 DB window 2,251 B; town overlay 144 B |
| Plus/4 | 85 bytes; banked 72 bytes | gen overlay 495 B; items overlay 952 B; ~7 KB total overlay slack |
| Apple IIe | resident 5 bytes; play 19 bytes; auxdata ~130 bytes | gen overlay slot-safe 116 B; UI aux slot ~803 B; HELP class ~3,402 B cold window |

All four ports are effectively full in resident/banked space. Catalog growth
is fundable only through the recovery options in the Space Recovery Analysis
section below.

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

> **STALE — superseded by later slices.** Measured 2026-07-31: `128.names`
> occupies `$7400-$7734` and the Bank 1 DB window has **2,251 bytes free**
> (`$7735-$7FFF`); `128.item` occupies `$8CA0-$A7F9` (**~7 bytes free**, not
> 773 — the Phase 1B runway was consumed by later slices and a resident
> title-draw routine); the main program ends at `$5FFC` (**4 bytes free**,
> not 97). The table below is the historical Phase 1B record.

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

> **SUPERSEDED by the Space Recovery Analysis (2026-07-31).** Chest state can
> ride existing per-slot fields (`fi_p1`/`inv_p1`, `fi_to_hit`/`inv_to_hit`,
> `fi_to_dam`/`inv_to_dam`, `fi_meta` bit 7) gated on `ICAT_CHEST`, at **zero
> new RAM and zero new save bytes** because those fields are already
> serialized. The 126-byte sidecar plan below is retained as the fallback.

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
- `it_unknown_idx` stores the per-row class-local unknown-description index as
  two types per byte; the class itself is derived from `it_category`
  (potion/scroll/ring/wand/staff are the randomized classes). The table asserts
  to `(ITEM_TYPE_COUNT + 1) >> 1`.
- Unknown name and floor-color routing now switch on `it_category` and fetch
  the class-local index via `iuk_index_for_type`. Fixed-name rows forced to
  unknown fall back to real item name/color rather than indexing a shuffled
  table out of bounds.
- Legacy save migration now derives appended known-state defaults from
  `it_category`: fixed rows default known, randomized rows default unknown,
  and future capacity bytes are cleared.
- When adding IDs `66-95`, extend `it_unknown_idx` in lockstep with
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

Target appended rows (approved 2026-08-01, deep-play-optimized list; the
older committed table and the 2026-07-31 chat draft are superseded):

| ID | Item | Class | Cost | Min level | Notes |
|---:|---|---|---:|---:|---|
| 96 | Potion of Healing | potion | 200 | 12 | heal 200 HP; p1-driven heal machinery |
| 97 | Potion of Restoration | potion | 300 | 30 | restore all drained stats; new small handler |
| 98 | Potion of Resist Heat | potion | 30 | 1 | temp fire resist; existing resist machinery |
| 99 | Potion of Resist Cold | potion | 30 | 1 | temp cold resist; existing resist machinery |
| 100 | Potion of Cure Critical Wounds | potion | 100 | 5 | big heal; existing heal machinery |
| 101 | Scroll of Teleport Level | scroll | 50 | 20 | new small handler on stairs level-change path |
| 102 | Scroll of Magic Mapping | scroll | 40 | 5 | full-level map; wizard-reveal path product entry |
| 103 | Scroll of Object Detection | scroll | 15 | 1 | floor-item detection; new moderate handler |
| 104 | Scroll of Recharging | scroll | 200 | 40 | existing recharge_item dispatch |
| 105 | Scroll of Rune of Protection | scroll | 500 | 50 | existing glyph_of_warding dispatch |
| 106 | Scroll of Genocide | scroll | 750 | 35 | existing genocide dispatch |
| 107 | Scroll of Mass Genocide | scroll | 1000 | 50 | all monsters in line of sight; new LOS-filtered genocide |
| 108 | Scroll of *Destruction* | scroll | 750 | 40 | existing word_of_destruction dispatch |
| 109 | Ring of Resist Fire | ring | 250 | 14 | new persistent resist bit + damage hook |
| 110 | Ring of Resist Cold | ring | 250 | 14 | new persistent resist bit + damage hook |
| 111 | Ring of Speed | ring | 3000 | 50 | new persistent speed bit (turn/energy) |
| 112 | Ring of See Invisible | ring | 500 | 40 | new persistent see-invis bit (monster visibility) |
| 113 | Ring of Slaying | ring | 1000 | 50 | no new code; p1 to-hit/to-dam fields apply |
| 114 | Wand of Slow Monster | wand | 500 | 2 | existing slow_monster dispatch |
| 115 | Wand of Stone-to-Mud | wand | 300 | 12 | existing turn_stone_to_mud dispatch |
| 116 | Wand of Teleport Away | wand | 350 | 20 | existing teleport_other dispatch |
| 117 | Wand of Fire Balls | wand | 1800 | 50 | existing fire_ball dispatch |
| 118 | Wand of Cold Balls | wand | 1500 | 40 | existing frost_ball dispatch |
| 119 | Staff of Dispel Evil | staff | 1200 | 49 | existing dispel_evil dispatch |
| 120 | Staff of Destruction | staff | 2500 | 50 | existing word_of_destruction dispatch |
| 121 | Staff of Speed | staff | 1000 | 40 | existing haste_self dispatch |
| 122 | Mithril Chain Mail | armor | 600 | 14 | AC 11, weight 200; moria8-scale armor (not upstream) |
| 123 | Mithril Plate Mail | armor | 1200 | 24 | AC 14, weight 320; fits 4-bit AC nibble |
| 124 | Amulet of Wisdom | amulet | 300 | 20 | +WIS via p1; requires amulet slot machinery |
| 125 | Amulet of the Magi | amulet | 5000 | 50 | +INT via p1 + see-invisible |
| 126 | Potion of Neutralize Poison | potion | 75 | 5 | eff_cure_poison dispatch |
| 127 | Staff of Remove Curse | staff | 500 | 30 | eff_remove_curse dispatch |

Resolved decisions (2026-08-01): deep-play row list approved; unknown-name
pools wrap class-local indexes modulo pool size (cosmetic duplicate
appearances, 0 B, no save change); resist rings are two rows (fire, cold);
Mass Genocide removes all monsters in line of sight; two amulet rows;
chests follow after the 32 rows. Fill rows chosen by the agent: Cure
Critical Wounds, Neutralize Poison, Amulet of Wisdom, Staff of Remove
Curse; Ring of Searching dropped in favor of Ring of See Invisible.

Pool wrap assignment: potions +6 -> indexes 10,11,0,1,2,3 (pool 12);
scrolls +8 -> 10,11,0,1,2,3,4,5 (pool 12); rings +5 -> 2,3,0,1,2 (pool 4);
wands +5 -> 4,0,1,2,3 (pool 5); staves +4 -> 4,0,1,2 (pool 5).

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
- The amulet slot is save-reserved but intentionally hidden from the equipment
  UI and prompt-time take-off selector until actual amulet item types exist.
  User-visible equipment stops at `VISIBLE_EQUIP_END`/`VISIBLE_EQUIP_SLOTS`;
  storage and migration continue to use `EQUIP_END`/`TOTAL_INV_SLOTS`.
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

## Space Recovery Analysis (2026-07-31)

Deep per-port recovery survey funding 32 new rows (IDs 96-127), ~3-6 KB of
item effect/dispatch code, and chest gameplay (~1.5-2.5 KB code + live state).
Evidence base: `build/*/main.vs` symbol dumps and PRG payload sizes from the
2026-07-30/31 build. This section supersedes all earlier headroom claims in
this document (see the stale-table note under Current C128 product layout).

### Lever 1: Chest State At Zero Cost

Chests never fight, so the combat sidecars every floor/inventory slot already
carries are free for chest use, gated on `ICAT_CHEST`:

| Existing field | Chest meaning |
|---|---|
| `fi_p1` / `inv_p1` | chest flags low (trap id, locked) |
| `fi_to_hit` / `inv_to_hit` | chest source level |
| `fi_to_dam` / `inv_to_dam` | content flags / flags high |
| `fi_to_ac` / `inv_to_ac` | disarm progress/state |
| `fi_meta` bit 7 (free; bits 0-6 used, `core/item.s:53-55`) | opened |

These fields are already serialized in both floor and inventory save blocks
(`platforms/shared/save.s:395-403`, `:319-328`), so chest state costs **0 new
RAM, 0 new save bytes, and no save migration**. Spawn/store/wizard paths
already zero the fields (`core/item.s:103-112`,
`core/store_restock_overlay.s:207-216`). This supersedes the 126-byte sidecar
proposal and removes the C64/Plus4 "no home for live state" blocker. Sparse
precedent: glyph-of-warding state (`core/item.s:75-77`).

### Lever 2: Effect Dispatch Reuse (Mandatory)

Item use runs from `OVL.ITEMS` on all four ports (read/aim/use via
`core/item_actions_overlay.s`; quaff is resident on C64/Plus4, banked on
C128, overlay on Apple IIe). The deep-play effects wanted for new items
already exist as spell effects:

- Overlay `eff_*` (`core/player_magic_execute_overlay.s`): genocide (157 B),
  destroy_area (17), glyph_of_warding (35), haste_self (11), teleport_other
  (107), slow_monster_dir (24), polymorph_other (40), sleep_all (57),
  dispel_flagged (66), recharge_item (88), resist_heat_cold (11),
  remove_curse_all (26).
- Resident `eff_*` (`core/spell_effects.s`): cure_poison, phase_door,
  wall_to_mud, remove_curse, detect_evil_only, heal — these need no dispatch
  at all.

Copying the ~10 wanted overlay effects into `OVL.ITEMS` would cost ~500-650
B/port and does not fit (items-overlay free: C64 236 B, C128 118 B, Plus/4
952 B, **Apple IIe 0 B**). Dispatch is the only option that fits everywhere.

Mechanism: the item front-end finishes selection/charges/`id_known`, sets
`pm_spell_type`/`pm_spell_idx` to a virtual spell index, and tail-calls
`tramp_spell_execute_selected`. Production precedent: the C128 reverse-bounce
(`tramp_eff_earthquake`, `platforms/commodore/c128/main.s:1444-1461`) already
calls an effect across overlay boundaries and restores the previous overlay.

Constraints and costs:

- C128 executes spells from the death overlay, which has only 28 B free, so
  new code must use virtual indices with no wrapper jump table; fixed item
  power spoofs `zp_player_lvl` (2 stores) instead of level-scaled wrappers.
- New resident cost: ~20 B dispatch trampoline (C64/Plus4/Apple IIe; C128
  already has the mechanism) + ~5 B per item call site.
- Runtime cost: one overlay swap per exotic item use (see performance table).
- Shared `.const` names for virtual indices with table asserts are required
  so item tables and spell tables cannot drift.

### Lever 3: Resident Representation Packing

Measured packing options, all ports (savings multiply x4 through shared
core). At 128 rows (estimated); measured results at 96 rows below.

| Change | Resident/port | Access sites | Risk | Status |
|---|---:|---|---|---|
| `id_known` byte-per-item -> 16-byte bitset | -112 B | 15 product sites in 7 files (+~114 test fixture refs) | medium: save V4 required | done |
| `it_unknown_desc` -> nibble index; class derived from `it_category` (verified 1:1 for all 96 rows) | -64 B | 14 sites in 2 files | low | done (-48 B measured) |
| dice count+sides -> 1 byte (count <=3, sides <=9) | -128 B | 3 files, always read together | low | done (-93 B measured) |
| color+base AC -> 1 byte (4+4 bits) | -128 B | 4 files | low | done (-86 B measured; AC reads via `item_get_base_ac` helper) |
| `it_display` -> derived from `it_category` (verified consistent; exception range for bows/ammo) | -80 B | 8 render files | medium-low | done (-41 B measured; `item_get_display_char` + 16-byte category table + exceptions for ranged/ammo/flask) |
| `it_min_level` -> nibble | -64 B (gen overlay on C64/Plus4/A2; resident on C128) | 1 file | low | done (via `iml_get_for_type`) |

Measured C64 resident recovery at 96 rows: program_end `$bc63` -> `$bb57`
(268 B), with `it_min_level` savings landing in the gen overlay on
C64/Plus4/Apple IIe and resident on C128.
| `it_min_level` -> nibble | -64 B (gen overlay on C64/Plus4/A2; resident on C128) | 1 file | low |

Gross recovery ~380-450 B/port at 128 rows, against ~200 B of packed table
growth for the 32 new rows plus ~350-420 B of new name streams (resident only
on C64/Plus4; banked on C128/Apple IIe). Save-format impact: the `id_known`
bitset is the documented `id_known_bits[16]` design in
`docs/SAVE_FILE_MIGRATION.md` and requires the save V4 layout bump.

Constraint: the `it_unknown_desc` index nibble caps at 15 appearances per
class; the Phase 3 list pushes potions past 15. Either grow the unknown-name
pools (~250 B/port plus save-block size changes) or wrap class-local indexes
(cosmetic duplicate appearances, 0 B, no save change). **Product decision
pending.**

### Per-Port Recovery Inventory

**C64 — Tier-0 (zero performance loss) ~2,545 B resident:**

| Option | Bytes | Evidence |
|---|---:|---|
| Wizard UI -> ModalMiscOverlay (overlay-hosted wizard already ships on C128 via `core/ui_wizard.s`) | 1,169 | `core/wizard.s:182-677` resident block `$A88E-$ACC9` |
| Boot-only code -> init-only tail past `program_end` (`reu_detect`, `reu_load_all_tiers`, `reu_stash_overlays`, `reu_show_file`, `tier_init`, `detect_machine`, service installs) | ~854 | established tail pattern `platforms/commodore/c64/main.s:1972-1977` |
| `roll_enchantment` -> DungeonGenOverlay (resident wrapper, `pick_item_type` pattern) | ~300 | `core/item.s:1512`, callers `:691,:825`, wizard `:89` |
| `item_init_identification` -> ItemActionsOverlay (call from `store_init_all` body) | 127 | `core/game_loop.s:610-616`; Apple StartupOverlay precedent |
| Dead code (`c64u_turbo_force_normal`, unused memory helpers) | ~95 | `c64/main.s:1029-1041`, `c64/memory.s:148-206` |

Additional C64 assets: ~1,240 B permanently free in the $D000 tier-name pool
tail (assert `core/tier_manager.s:527`) — fits the 821 B known-name streams
that C128/Apple IIe already bank; ~7.6 KB total overlay slack (spell 1,497,
death 2,491, modal 2,600, gen 495, help 339, items 236); a new overlay class
costs ~20 B resident + one disk-image line, with REU stash/pickup automatic.

**Plus/4 — Tier-0 ~2,624 B resident:**

| Option | Bytes | Evidence |
|---|---:|---|
| Wizard UI -> ModalMiscOverlay | 1,169 | same as C64 |
| Disarm subsystem -> ItemActionsOverlay (C64 already ships this exact layout) | ~700 | `plus4/main.s:359` vs `c64/main.s:412-416,2405-2406` |
| `roll_enchantment` -> DungeonGenOverlay | ~300 | same as C64 |
| `item_init_identification` -> ItemActionsOverlay | 127 | same as C64 |
| Dead `game_restart` (zero callers) + `winner_apply_retirement_bonus` -> ModalMisc + unused memory helpers | ~181 | `plus4/main.s:1902-1943`, `:1858-1888`, `plus4/memory.s:130-170` |
| Boot-only code -> init tail | ~147 | entry-main-only subset; `restart_entry` is re-entered on Plus/4 |

Plus/4 overlay slack ~7 KB (items 952, modal 2,656, death 1,957, spell 704,
gen 495). Caveat: `HAL_PLATFORM_OVERLAY_FORCE_RELOAD` makes every overlay
load a disk hit — already the Plus/4 norm for read/aim/use/bash/throw.

**C128 — Bank 1 plus dead code:**

| Option | Bytes | Evidence |
|---|---:|---|
| Remove dead REU cluster from the main image (`reu_present` forced to 0; stub precedent `plus4/reu_stub.s`) | ~850-900 | `c128/main.s:1740-1744`, `core/tier_manager.s:181-207`; keep `reu_show_file` |
| New item name streams land in `128.names` Bank 1 window (2,251 B free) — zero resident cost | funds 300-500 | `core/item_tables.s:666-772`, `item_identification.s:537-588` |
| Unknown-name cluster + `it_unknown_desc` -> Bank 1 (write helpers exist: `mmu_safe_db_write_ptr0/1`, `config128.s:108-115`) | ~511 resident | `item_identification.s:45-145,276-360,604-678` |
| Token dictionary -> Bank 1 | ~229 resident | `item_tables.s:615-658` |
| `it_cost_lo` + `it_cost_hi_extra` -> TownOverlay, placed after store code | 116 resident | sole reader `core/store.s:59-83` is town-local; 144 B free |
| `it_min_level` -> Bank 1 (sole reader is gen-overlay picker) | 96 resident | `item_tables.s:465-490`, `core/item.s:1426` |
| New <=2 KB cached overlay class in the DB window (DISARM is the precedent) | funds 2-3 KB code | `memory128.s:124-166,574-579`, `overlay.s:384-580` |

Notes: the historical `it_cost_lo` town-entry JAM is documented by symptom
only; current C128 overlays provably start with data (`ovl.gen` begins with
`pit_sorted`), and the failed attempt's segment restore targeted `Default`
rather than `C128ResidentItems` (`item_tables.s:436-438`). Mitigation: place
the table after the entry code and fix the restore segment. Bank 1 cannot
execute code — data only. Title-cache slack ~1,176 B and a 640 B candidate
low-common-RAM block at `$0800-$0A7F` exist but the latter has undocumented
KERNAL/boot ownership — validate before use, and it is not needed.

**Apple IIe — table conversions, cache repack, overlay homes:**

| Option | Bytes | Evidence |
|---|---:|---|
| `it_name_hi` -> derived page-crossing (shipped on the other three ports) | +74 resident | `item_tables.s:552-577`, `item_identification.s:449-476` |
| `it_cost_hi` -> sparse exceptions (shipped elsewhere) | +59 town overlay | `item_tables.s:425,439-463`, reader `store.s:59-83` |
| UI aux cache slot 13 -> 10 pages (payload 2,525 B; slots single-sourced from `cache_layout.s`) | +768 aux | `platforms/apple2/cache_layout.s:5-11` |
| Chest state fits auxdata today (~130 B free) if Lever 1 is not taken | 126 aux | auxdata ends `$567E`, limit `$56FF` |
| `store_restock_overlay` -> GEN slot (transition-only, certified in its header) | +715 items overlay | `store_restock_overlay.s:1-6`; page math 21+10+20+12+20+22=105 |
| Chest UI -> HELP class (cold; inventory/equipment UI already lives there) | ~3,402 cold window | `ovl_help_end=$ACB6`, window 5,632 |
| New cold overlay class | +5,632 window | `overlay_storage.s:36-38` zero-entry pattern |
| Overlay window tail `$B9FF->$BAFF` | +256/class | reservation-only; tier payloads end `$AC0E` |

Correction to earlier window-based figures: the aux cache copy is a fixed
$1600-byte AUXMOVE from the slot base, so slot-safe headroom is smaller than
window headroom (town 14 B, spell 95 B, modal 94 B, gen 116 B, items 0 B;
UI 803 B is the only whole-page slack). Cache-hit overlay swap ~60 ms; cold
load = ProDOS read (fine for chest-open flows, not for per-round effects).

### Performance Cost Summary

| Path | Cost |
|---|---|
| Hot effects (cure, phase door, stone-to-mud, remove curse, detect evil) | zero — resident today |
| Exotic item effects (genocide, destruction, glyph, etc.) | one overlay swap per use: C64 = disk hit (REU: DMA), Plus/4 = disk hit (status quo), C128 = ~35-50 ms Bank 1 cache copy, Apple IIe = ~60 ms auxmove |
| Chest open/disarm | rare per level; cold-load disk hit acceptable on C64/Plus4, cached elsewhere |
| Packed-table reads | ~8-12 extra cycles per combat blow / render lookup — invisible |
| Bank 1 / aux data reads (C128/Apple IIe) | already the shipped name-stream pattern |

### Risks And Open Product Decisions

1. C128 town-entry JAM mechanism is unknown; mitigations above, runtime proof
   required before relying on the town move.
2. Unknown-name pools: resolved 2026-08-01 — wrap class-local indexes
   modulo pool size (cosmetic duplicate appearances, 0 B, no save change).
3. REU 1700 (64 KB) capacity for tiers plus a 10th overlay on C64 is
   untraced.
4. Test-suite coupling: `id_known` bitset touches ~114 test fixture refs;
   deleting C64/Plus4 memory helpers touches one test file. Mechanical but
   real; infrastructure fixes are a separate ask per verification rules.
5. Apple IIe storage-overlay free space is unmeasured; save-migration code
   growth lands there.
6. Chest sequencing: resolved 2026-08-01 — chests follow the 32 rows.
7. Row list: resolved 2026-08-01 — the deep-play-optimized list is approved
   and is the Phase 3 table above; the older committed table is superseded.

### Suggested Sequencing

1. **Phase R (recovery, no catalog change):** dead-code removal (C128 REU,
   C64/Plus4 dead helpers), wizard->modal on C64/Plus4, disarm->items overlay
   on Plus/4, Apple IIe table conversions (`it_name_hi`, `it_cost_hi`),
   chest-state-on-existing-fields decision. Lands headroom with zero gameplay
   change; each port's suite gates it.
2. **Phase 2 (representation):** Lever 3 packing + save V4 (bitset, capacity
   128).
3. **Phase 3 (rows):** the 32-row list; effects mostly dispatched (Lever 2);
   names banked on C128/Apple IIe, funded by packing + hidden pool on
   C64/Plus4.
4. **Chests:** code into overlay headroom (modal/death/help slack or a new
   class), state at 0 B via Lever 1.

### Phase R Implementation Status (2026-07-31)

Complete and verified. Resident free space after Phase R:

| Port | Before | After | Recovered |
|---|---:|---:|---:|
| C64 resident | 1 B | 1,042 B (`program_end=$BBEE`) | +1,041 B |
| C128 main | 4 B | 893 B (`program_end=$5C83`) | +889 B |
| Plus/4 resident | 85 B | 1,984 B (`program_end=$C040`) | +1,899 B |
| Apple IIe resident | 5 B | 81 B (`program_end=$7BAF`) | +76 B (+60 B town) |

After the spell_effects.s indirect-JMP fix (below), the C64 memory helpers
were also deleted (+69 B) and `fea_jmp_smc` removed the `adj_callback` word
(−2 B); the `testapple2` gate now generates its own `main.sym`/`boot.sym`.

Landed slices:

| Slice | Change | Result |
|---|---|---|
| R5 | Apple IIe `it_name_hi` -> derived page-crossing (3-port precedent) | +76 B resident |
| R6 | Apple IIe `it_cost_hi` -> sparse exceptions | +60 B town overlay |
| R2 | C64: removed dead `c64u_turbo_force_normal` (+26 B). Plus/4: removed dead `game_restart`, moved `winner_apply_retirement_bonus` to ModalMisc, removed unused memory helpers (+181 B) | verified |
| R1 | C128: removed dead REU cluster; new `preload128.s` (C128 preload LOAD, moved out of `common/reu.s`) and `reu_stub128.s` (Plus/4 stub pattern, keeps live `reu_show_file`); removed `reu_loading_banked.s`, `tramp_reu_show_status`, and the boot patch | +889 B main |
| R4 | Plus/4 disarm subsystem -> ItemActionsOverlay (C64 pattern; `PLATFORM_DISARM_COMMAND_INLINE` removed) | +703 B resident |

R4 follow-up fix (same day): the initial R4 edit wrapped the
`dungeon_features.s` import in `DISARM_COMMAND_EXTERNAL` but not the
`game_loop.s` import, so `cmd_disarm` assembled a resident
`jsr disarm_command` straight into the `$E000` overlay window. Pressing
SHIFT+D executed whatever overlay/tier bytes were resident there and CPU
JAMmed (reproduced deterministically: JAM at `$2F03` in a scripted flow;
user-reported JAM at `$0115`). C64, C128, and Apple IIe all wrap both
imports; Plus/4 now does too (plus4/main.s:435-437). Verified in the PRG:
`cmd_disarm` now calls `tramp_disarm_command`. Regression coverage:
`disarm_command_external_import_contract` static check in
run_testsplus4.sh (the defect is static; the crash itself is
timing/RNG-dependent and cannot be caught deterministically through gameplay
scripting) plus a `disarm_plus4` scripted runtime smoke for the happy path.
| R3 | C64/Plus4 wizard UI -> ModalMiscOverlay (`HAL_PLATFORM_WIZARD_ENTRY_OVERLAY`; `ui_wizard.s` 40-col menu already existed) | +1,015 B resident each |

R3 follow-up fix (same day): the wizard reveal command (`A`) corrupted state
or ejected the player to town. `ui_wizard_cmd_reveal` executes in the
ModalMisc `$E000` window; its call chain reaches `tramp_reveal_floorplan`,
which loads OVL.SPELL into the same window, evicting the menu code, and the
return then landed in spell-overlay bytes. Fixed with resident
`wizard_reveal_level_from_overlay` (core/wizard.s), which restores
OVL_MODAL_MISC after the reveal before returning; gated to
`HAL_PLATFORM_WIZARD_REVEAL_TRAMPOLINE` (C64/Plus4) since C128/Apple IIe use
the inline resident reveal path and never evict. Regression coverage:
`wizard_reveal_product_smoke` in `platforms/commodore/c64/run_tests.sh`
scripts new game -> descend -> CTRL+W -> Y -> CTRL+W -> A and asserts the
flow unwinds to input exhaustion with `zp_player_dlvl == 1` and
`current_overlay == OVL_MODAL_MISC`; it fails on the pre-fix build with the
reported symptom. Audit of the other overlay-hosted wizard commands found no
other mid-call overlay loads (level-jump is resident-by-design and never
returns to the overlay).

Reverted slice: the C64 memory-helper deletion (`read_banked_byte_a000/e000`,
`copy_to_e000`, 69 B) was reverted after it deterministically flipped
`test_directional_effects` into a wild-execution failure (BRK storm into the
KERNAL/BASIC input loop). Diagnosis proved the deletion is not the cause:
restoring only a 69-byte NOP pad at the same address also passes, so the test
has a latent layout/address-sensitive defect that any future byte shift can
re-expose. The helpers stay until that defect is root-caused; Plus/4's
equivalent removal (56 B) landed cleanly.

Root cause found and fixed (2026-07-31): `for_each_adjacent` in
core/spell_effects.s dispatched its callback with `jmp (adj_callback)`. The
6502 indirect-JMP page-crossing bug reads the pointer high byte from `$9200`
instead of `$9300` when the pointer sits at `$92FF` — exactly where the −69
byte layout placed `adj_callback`. Every `eff_sleep_adjacent` call then
jumped to a garbage address, cascading into stack corruption and BRK storms.
The original layout placed it at `$9342` (safe), so the bug only appeared
when spell_effects.s moved by a multiple of 256-page alignment into a `$xxFF`
boundary. Fixed by replacing the indirect dispatch with a self-modified
absolute JMP (`fea_jmp_smc`), eliminating the bug class and the `adj_callback`
storage word. The same exposure in Apple IIe `tramp_items_target` was
converted identically. With the fix, the C64 helper deletion landed: the
suite passes with the 69 B reclaimed.

Still available from the Tier-0 inventory (not yet done): C64 init-tail
relocation (~854 B), `roll_enchantment` -> gen overlay (~300 B, both
Commodore 40-col ports), `item_init_identification` -> items overlay (127 B),
Plus/4 init tail (~147 B), C64 hidden tier-name-pool name streams
(~820-1,030 B, higher risk).

Verification: `make build` all four ports; `make test128-fast` 290 PASS;
`make testplus4` 36/36; `make test64` 178/179 with one save-flow smoke
flaking under full-suite load (passes in isolation on both clean and modified
trees); Apple IIe memory-contract gate 21/21 and MAME `wizard_flow` 7/7.

Infrastructure defect found and fixed: `make testapple2` used to fail from a
clean tree because the build never generated `platforms/apple2/main.sym`/
`boot.sym`, which `check_memory_contract.py` requires. The build now generates
both via `-symbolfile` and `make clean` removes them; the gate passes from a
clean tree (21/21).


## Final Judgment

- Full catalog using current resident table model: no.
- Full catalog using split/banked catalog architecture: yes, possible.
- Abbreviated catalog using one-byte IDs and split data: yes, recommended.
- Literal Umoria 420-row catalog: possible only with 16-bit IDs or `tval/sval`,
  plus major save/UI/store/generation/action work.

Confidence: high on the memory conclusion, moderate-high on the recommended
architecture.
