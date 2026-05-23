# Moria8 Resident Memory-Saving Analysis

This note reviews practical opportunities to reclaim resident RAM and tight
overlay space across the C64, C128, and Plus/4 builds.

The original analysis correctly identified useful pressure points, but several
byte totals were overstated. In particular, the resident monster tables are
active runtime buffers, and the current Huffman string bank is not an unlimited
or free destination for additional names.

## Current Pressure Points

Approximate current slack from the latest build symbols:

| Area | End | Limit | Slack |
| :--- | :--- | :--- | ---: |
| C64 resident before `MAP_BASE` | `$bdae` | `$c000` | 594 bytes |
| Plus/4 resident before `CREATURE_BASE` | `$c564` | `$c800` | 668 bytes |
| C128 default segment | `$5fc2` | `$6000` | 62 bytes |
| C128 resident world segment | `$8b2b` | `$8d00` | 469 bytes |
| C128 resident items segment | `$a723` | `$a800` | 221 bytes |
| C64/Plus4 `TownOverlay` | `$eff3` | `$f000` | 13 bytes |
| C64/Plus4 `UiOverlay` | `$ef90` | `$f000` | 112 bytes |
| C128 `UiOverlay` | `$efe7` | `$f000` | 25 bytes |

Any proposed saving should be evaluated by segment, not only by total bytes.
Moving data out of one tight area can overflow another.

## 1. Store Names and Owners

Store display strings are a clean relocation candidate.

Implemented state:

- Store names and owners now live at the tail of product `TownOverlay` via
  `commodore/common/store.s`.
- Unit tests still get fixture strings from `commodore/common/store_data.s`
  when product overlay defines are not active.
- Resident `store_name_lo/hi` and `store_owner_lo/hi` tables still live in
  `store_data.s` and point at the product overlay labels.
- Persistent store inventory arrays, category masks, door checks, and helpers
  must stay resident.

Measured cost:

- Store and owner raw strings: 207 bytes.
- `store_name_lo/hi` and `store_owner_lo/hi`: 32 bytes.
- Implemented resident saving: 207 bytes. The pointer tables were deliberately
  kept resident to avoid adding overlay glue.

Constraint:

- `TownOverlay` now has about 13 bytes free. This is acceptable but tight.
- The strings must remain after existing store code/scratch labels in
  `store.s`. `store_restock_overlay.s` runs from `ItemActionsOverlay` while
  sharing those scratch label addresses; moving text ahead of them corrupts the
  restock path.

Follow-up recommendation:

Leave this implementation in place, but treat `TownOverlay` as full. Future
town/store work should first recover overlay bytes or move additional cold text
to a different representation.

Required verification:

- `make build` on all platforms.
- C64 product new-game/save smoke, because store restock runs during new game.
- Store UI smoke: enter each store and home, verify store title and owner rows.
- Leave and re-enter stores after other overlays load.
- Static check that only store UI code references store name/owner labels.

## 2. Embedded Dungeon Monster Roster

The easy resident-monster savings are much smaller than the original estimate.

Current state:

- `commodore/common/monster.s` defines 57 dungeon creature slots and 8 town
  creature slots.
- Those SoA arrays are live active buffers. Tier loading copies tier creature
  data into those arrays.
- Therefore the 57 dungeon slots, `cr_name_lo/hi`, and most SoA table capacity
  cannot be removed without a deeper memory-layout redesign.

Corrected accounting:

- Replacing initialized 0-25 dungeon entries with `.fill 0` does not save RAM.
  The bytes are still emitted because the arrays must remain writable active
  buffers.
- The realistic low-risk saving is primarily the embedded dungeon name strings
  `crn_0` through `crn_25`.
- Current raw embedded dungeon name strings are about 392 bytes.
- Town creature names must remain resident for town gameplay.

Risk:

- The embedded dungeon roster currently provides a fallback if tier data is not
  loaded yet or if a test spawns creatures by index without loading a tier.
- Before production can start with `active_dungeon_count = 0`, dungeon tier-load
  failure must be handled as fatal/retry-safe before monster spawning. Otherwise
  the game can spawn zeroed type-0 creatures.

Recommendation:

- Do not remove or shrink active SoA buffers.
- If this path is pursued, use a narrow flag such as
  `COMPILE_EMBEDDED_DUNGEON_TEST_ROSTER`.
- Gate only embedded test fixture data and raw dungeon names, while preserving
  full active buffer capacity and all town entries.
- Apply the omission only on memory-constrained platforms where the recovered
  bytes are needed. The current implementation keeps the fixture on Plus/4.
- Prefer teaching tests to load/copy a test tier over relying indefinitely on a
  production/test conditional in `monster.s`.

Required verification:

- Tier transition tests prove tier 1-4 still load into active buffers.
- Product smoke from town into dungeon verifies valid non-town monsters spawn.
- Forced tier-load failure test verifies the game does not spawn zeroed
  monsters.
- Static asserts keep `MAX_DUNGEON_CREATURES`, `TOWN_CREATURE_BASE`, and
  `MAX_CREATURES` unchanged.

## 3. Item Name Compression

Compressing item names is plausible, but it needs an API design first.

Current state:

- 64 base item names live as raw null-terminated screen-code strings in
  `commodore/common/item_tables.s`.
- Raw item strings are about 825 bytes.
- `it_name_lo/hi` pointer tables cost 128 bytes.
- Total current item-name footprint is about 953 bytes in the segment where
  item tables live.

Important constraints:

- The existing Huffman bank has `HUFF_STR_COUNT = 201`.
- The decoder uses an 8-bit string ID in `X`, so the current ABI has only 55
  remaining IDs before reaching 256.
- Adding all 64 item names to the existing Huffman namespace does not fit
  unless there is significant deduplication or the ABI changes.
- Huffman data is resident today. Moving item names into it trades raw strings
  for compressed bytes, 2-byte Huffman index entries, ID tables, and code.
- Item naming already uses `hd_decode_buf` for composed known names such as
  known potions, scrolls, books, wands, and staves. Decoding a base name into
  the same buffer can clobber composed names unless the API changes.

Recommendation:

- Do not start by mechanically replacing `it_name_lo/hi` with Huffman IDs.
- First design explicit name operations:
  - `item_print_name`
  - `item_append_name`
  - possibly `item_decode_base_name_to_secondary_buffer`
- Alternatively create a separate name bank / name-string namespace instead of
  expanding the general message Huffman namespace.
- Add an assert or generator check for any 8-bit ID namespace limit.

Expected savings:

- Likely useful, but the original `~832 bytes reclaimed` estimate is too high.
- Real savings depend on whether the compressed data shares an existing bank,
  whether a second index table is required, and how much formatter glue is
  needed.

Required verification:

- Item description tests for unknown and known potions, scrolls, rings, books,
  wands, staves, weapons, armor, and stackable ammunition.
- Product UI smoke for pickup, drop, inventory, equipment, identify, read,
  quaff, aim, and use paths.
- C64/C128/Plus4 build memory deltas by segment.

## 4. Spell and Prayer Name Compression

Spell/prayer names are a UI-overlay pressure problem, not automatically a
resident-memory saving.

Current state:

- Spell/prayer names live in `commodore/common/spell_names.s`, imported into
  `UiOverlay`.
- There are 59 raw `.text` definitions because some names already share labels
  with item names.
- Raw spell/prayer strings are about 792 bytes.
- Pointer tables cost 124 bytes.

Benefit:

- Compressing or relocating spell/prayer names can free meaningful `UiOverlay`
  space, especially on C128 where `UiOverlay` currently has about 25 bytes free.

Constraint:

- If these names are moved into the current resident Huffman bank, they increase
  resident/default pressure.
- The current Huffman ID namespace cannot absorb item names plus spell/prayer
  names as-is.
- Spell UI currently expects pointer tables, so the selector rendering path must
  change to decode/print by ID.

Recommendation:

- Defer until item-name/name-bank design is settled.
- Treat this as a UI overlay space project, not as main-bank reclamation.

Required verification:

- Spell and prayer selector tests on C64 and C128.
- Book learning UI tests.
- C128 `UiOverlay` memory assert.

## 5. Other Resident Strings

The original list of miscellaneous resident string candidates is stale.

Many messages cited as compression candidates have already been moved to
Huffman strings, including save messages, dungeon feature messages, item command
messages, monster magic messages, ranged/throw/tunnel messages, and several
effect timer messages.

Recommendation:

- Do not implement from the stale table.
- Re-scan for raw `.text` strings in resident segments before choosing targets.
- Prefer converting one small subsystem at a time and measuring actual segment
  deltas.

## Recommended Order

1. **Correct `TownOverlay` headroom, then move store names/owners.**
   This is the cleanest near-term resident saving and helps C128 item-segment
   pressure.
2. **Narrow embedded dungeon monster fixture cleanup.**
   Save raw embedded dungeon names/test fixture data only; keep active buffers.
   Do not do this until tier-load failure behavior is safe.
3. **Item name system redesign.**
   Introduce print/append APIs or a separate name bank before migrating base
   item names.
4. **Spell/prayer name compression or relocation.**
   Do this after the name-bank design exists, mainly to relieve `UiOverlay`.
5. **Fresh scan of remaining resident raw strings.**
   Recompute against current source before implementing any one-off conversion.

## Summary

| Opportunity | Corrected View | Suggested Priority |
| :--- | :--- | :--- |
| Store names/owners | About 239 resident bytes, but direct move needs `TownOverlay` headroom | First |
| Embedded dungeon monster names/test fixture | Hundreds of bytes, not ~900; active buffers must remain | Second |
| Base item names | Promising but needs name API/bank redesign; current HSTR namespace is too full | Third |
| Spell/prayer names | Frees UI overlay but may increase resident/default pressure | Fourth |
| Misc resident strings | Original list stale; re-scan before action | Opportunistic |

The safest immediate cleanup is to make the analysis itself accurate, then
attack the store-string relocation once `TownOverlay` has enough room.
