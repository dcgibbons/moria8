# Save File Migration Plan

## Bottom Line

With the current save format, adding items can break old saves. The main
problem is not item IDs by themselves, but that the save stream serializes
`id_known` as `ITEM_TYPE_COUNT` bytes:

```asm
:save_block_desc(id_known, ITEM_TYPE_COUNT)
```

If `ITEM_TYPE_COUNT` changes from 64 to 96, a new loader expects 32 more bytes
in the middle of the save. An old save does not contain those bytes, so every
later block is read at the wrong offset.

Confidence: high.

## Shipping Save Contract

Moria8 v1.1.0 ships Save Format V1.

V1 means:

| Contract | Value |
|---|---|
| Item catalog size | `ITEM_TYPE_COUNT = 64` |
| Permanent item ID range | `0-63` |
| Known-item save shape | fixed 64-byte `id_known` block |
| Chest state | none |
| Extended catalog state | none |

Item IDs `0-63` are the shipped catalog ABI. They must not be renumbered,
reused for different items, or reinterpreted in later releases. Existing IDs
may be deprecated, hidden, or made unobtainable, but their saved meaning must
remain stable.

Future item expansion must either load V1 saves through an explicit migration
path or reject them with a clear incompatible-save message. It must not change
`ITEM_TYPE_COUNT` and rely on the current fixed block loader to read old saves.

## Compatibility Risks

| Change | Breaks old saves today? | Why |
|---|---:|---|
| Add new item IDs and increase `ITEM_TYPE_COUNT` | yes | `id_known` block size changes |
| Renumber existing item IDs | yes | old inventory/floor/store IDs point to wrong items |
| Add new fields to item instances | yes unless versioned | floor/inventory/store block layout changes |
| Add new items using currently unused IDs under same count | no, but no unused IDs exist | current table is exactly 64 |
| Add behavior to existing items without changing IDs/layout | usually no | save shape unchanged |
| Add banked catalog data only, no live/save layout change | usually no | old saves still reference same IDs |

## Hard Rule: Never Renumber Existing Item IDs

IDs `0-63` should be treated as a permanent save ABI.

Bad:

```text
17 was Cure Light Wounds
17 becomes Potion of Healing
```

Good:

```text
17 stays Cure Light Wounds
64 becomes Potion of Healing
```

Any item catalog expansion must be append-only unless an explicit migration
maps old IDs to new IDs.

## Reserve Future Item Capacity

Before expanding the item catalog beyond the legacy ABI range, define a stable
save capacity separate from the number of currently implemented item rows:

```asm
.const LEGACY_ITEM_TYPE_COUNT = 64
.const ITEM_TYPE_COUNT = 96
.const ITEM_ID_CAPACITY = 96
```

The save format should serialize the stable capacity, not the current
implemented count.

Byte-per-item identification at 128 capacity costs:

```text
+64 bytes RAM compared with current 64-byte id_known
+64 bytes per save file
```

Byte-per-item identification at 256 capacity costs:

```text
+192 bytes RAM compared with current 64-byte id_known
+192 bytes per save file
```

Given current memory pressure, 128 is the sane near-term planning target. A
256-item capacity is more future-proof but expensive on C128.

## Prefer Identification Bitsets

Current `id_known` uses one byte per item. That is simple but wasteful.

| Capacity | Byte table | Bitset |
|---|---:|---:|
| 64 item IDs | 64 bytes | 8 bytes |
| 128 item IDs | 128 bytes | 16 bytes |
| 256 item IDs | 256 bytes | 32 bytes |

Recommended design:

```text
id_known_bits[16] for 128 item IDs
```

or, if planning for maximum one-byte item IDs:

```text
id_known_bits[32] for 256 item IDs
```

This requires bit access helpers, but it reduces RAM/save growth and makes item
catalog expansion much less painful.

## Add Explicit Save Layout Versions

The save header already has a version byte, but future compatibility should
treat the save layout as a schema with migration paths.

Suggested layout milestones:

| Layout | Meaning |
|---|---|
| `SAVE_LAYOUT_V1` | 64-byte `id_known`, 30 inventory/equipment slots |
| `SAVE_LAYOUT_V2` | 96-byte fixed-capacity `id_known`, 30 inventory/equipment slots |
| `SAVE_LAYOUT_V3` | 96-byte fixed-capacity `id_known`, 31 inventory/equipment slots with `EQUIP_AMULET` |
| future layout | chest sidecars or split catalog / extended item state |

Example migration:

```text
load V1:
  read 64-byte id_known
  convert to 128-bit id_known_bits
  initialize new item IDs as unknown/known by default
  read old floor/inventory/store layouts
  initialize future known-item bytes and the amulet slot to empty/zero
```

## Append New Save Blocks Where Possible

For additive features, append new blocks near the end of the save stream
instead of inserting them into existing block tables.

Bad:

```text
player
inventory
NEW_BLOCK
map
monsters
```

Better:

```text
player
inventory
map
monsters
extensions
```

Then versioned loading can use default initialization for old saves:

```text
if version >= chest_version:
  read chest sidecars
else:
  clear chest sidecars
```

## Migration Defaults

Every new field needs a deterministic old-save default.

| New field | Old-save default |
|---|---|
| New item IDs in known table | unknown, except mundane always-known items |
| Chest flags | 0 |
| Chest content flags | 0 |
| Chest source level | 0, or current dungeon level if needed |
| Item ID high byte | 0 |
| New inventory flags | 0 |
| New store stock fields | 0 |
| Catalog generation version | current default |

Do not treat `id_known = 0` as a harmless universal default. Unknown-name
rendering is category-sensitive: potions, scrolls, staves, wands, and similar
randomized identification classes may use shuffled description tables, while
ordinary equipment should normally render its real name. If an appended mundane
item is left unknown during legacy-save migration, it can be routed through the
wrong randomized-name table and read outside that table. That produces garbage
inventory text and can corrupt the running product.

For every appended item range, migration must explicitly choose one of:

| Item class | Migration default |
|---|---|
| Mundane equipment, food, books, fixed-name tools | known |
| Randomized potions, scrolls, wands, staves, rings, amulets | unknown only if the category-specific unknown-name table covers the new ID |
| New special behavior items | explicit default documented with the item batch |

## Keep Save Identity Stable

Old saves should store stable item identity, not derived names or table order.

Good:

```text
item_id = 17
p1 = charges/quantity/special payload
flags = cursed/identified/etc.
ego = ego id
```

Bad:

```text
catalog row offset
generated table index
store display index
```

If catalog data later moves into banks or disk-loaded tables, old saves should
continue to work because saved item IDs remain stable.

## Recommended Migration Project

Use the current 96-ID runway before introducing another save capacity.

For the 96-item milestone:

1. Freeze IDs `0-63`.
2. Keep `ITEM_ID_CAPACITY = 96`.
3. Grow `ITEM_TYPE_COUNT` only as rows are implemented.
4. Add explicit migration defaults for every appended item or appended range.
5. Keep old 64-byte known-state loading deterministic: read legacy bytes,
   initialize appended bytes from documented defaults, and clear future
   capacity bytes.
6. Document append-only item IDs as a hard rule.

Implementation status: C64 resident bytes were recovered by removing the hidden
C64U timing diagnostic, and the 96-ID migration runway now uses explicit
per-row metadata. `it_unknown_desc` drives both unknown-name/color routing and
legacy appended known-state defaults:

- Fixed-name rows default known.
- Randomized identification rows default unknown.
- Future capacity bytes from `ITEM_TYPE_COUNT` through `ITEM_ID_CAPACITY - 1`
  are cleared.

When adding more rows, extend `it_unknown_desc` in lockstep with
`ITEM_TYPE_COUNT`; do not add randomized appended rows unless their
unknown-name/color pools cover the descriptor's class-local index.

Before the 128-item milestone:

1. Introduce `ITEM_ID_CAPACITY = 128`.
2. Convert `id_known` from byte-per-item to a bitset, or save/load it through a
   compact compatibility wrapper.
3. Add version-aware save loading for 64-byte, 96-byte, and 128-capacity known
   state.
4. Add explicit migration defaults for future item ranges.
5. Verify old saves containing IDs `64-95` before adding IDs `96-127`.

After that, future catalog expansion to 128 items does not need to break saves.

For full 420-row support, a later breaking or migrating format would still be
needed because one-byte item IDs cap out at 255. Planning around 128 now gives
Moria8 a clean runway for an abbreviated catalog without burning save
compatibility every time items are added.
