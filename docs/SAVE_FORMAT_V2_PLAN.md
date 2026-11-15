# Save Format V2 Plan

**Status:** Implemented (`2026-11-15`, Phase 4 atomic Save Format V2 cutover; part of `docs/MEMORY_REDESIGN_PLAN.md`). Supersedes the incremental V1..V19 compatibility regime documented in `docs/SAVE_FILE_MIGRATION.md`.

---

## 1. Single Save Format V2 Bump Policy

All seven Moria8 ports switch in **one atomic Phase 4 bump** to Save Format V2:

1. **Single Version Window (`OLDEST_SAVE_VERSION = SAVE_VERSION`)**:
   - Bump `hal_storage_save_version` across every port's `hal/storage_policy.s` to a unified V2 version (recommended: `$20`, cleanly above the highest current V1 version, C128 `$1B`), and pin `hal_storage_save_v1_version = hal_storage_save_version`.
   - Keep the existing 8-byte magic prefix (`"MORIA01" + SAVE_VERSION`, or `"MORIA+4" + SAVE_VERSION` under `HAL_STORAGE_SAVE_MAGIC_ALT_SIGNATURE` on Plus/4).
   - Set `OLDEST_SAVE_VERSION = SAVE_VERSION` in `platforms/shared/save.s`.
2. **Zero V1 Backward Migration; Clean Rejection**:
   - `save_version_supported` (`platforms/shared/save.s`) accepts **only** `version == SAVE_VERSION`.
   - Any pre-V2 save file (`< $20`) or future version (`> $20`) is rejected immediately after reading the 8-byte magic header with `LOAD_RESULT_UNSUPPORTED` (`4`) and zero writes to player, inventory, store, map, or recall RAM.
   - All V1..V19 migration paths (`SAVE_KNOWN96_VERSION`, `SAVE_KNOWN_BITS_VERSION`, `SAVE_KNOWN160_VERSION`, `SAVE_INV31_VERSION`, `SAVE_INV33_VERSION`, `SAVE_STATS_BAKED_VERSION`, `SAVE_DOOR_STATE_VERSION`, `SAVE_FLOOR42_VERSION`, `HAL_STORAGE_LEGACY_ROOM8_MIGRATION`, `HAL_STORAGE_LEGACY_STORE12_MIGRATION`) are deleted.
3. **Playtest Queue Reset to DL1**:
   - `playtest/moria_playtest/queue.py` (`save_versions()` and `start_loads()`, lines `393-427`) parses `hal_storage_save_v1_version` and `hal_storage_save_version` from each build's `hal/storage_policy.s` and resumes a saved run only when `loads[0] <= saved[1] <= loads[1]`.
   - Because Phase 4 sets `loads[0] == loads[1] == V2`, every active pre-V2 Balrog-queue checkpoint automatically fails `start_loads()` and restarts cleanly from DL1 without manual queue edits.

---

## 2. Exact V2 Stream Layout and Byte Counts

All seven shipping ports run with `HAL_PLATFORM_MONSTER_CATALOG = 1`. Unless noted, all blocks are fixed-size and unconditionally written in stream order by `save_game` (`platforms/shared/save.s`), summed into the 16-bit additive checksum (`save_cksum_lo`, `save_cksum_hi`).

### 2.1 Stream Comparison (`V1` vs. `V2`)

| # | Stream Block | V1 (`80x48`) | V1 (`198x66`) | V2 (`80x48`) | V2 (`198x66`) | Delta (`V2 - V1`) & Encoding Details |
|---:|---|---:|---:|---:|---:|---|
| 1 | `save_magic` | `8` | `8` | `8` | `8` | `0`: `"MORIA01" + SAVE_VERSION` (Plus/4 `"MORIA+4" + SAVE_VERSION`, `SAVE_VERSION = $20`) |
| 2a | `player_data` (`PL_STRUCT_SIZE`) | `111` | `111` | `111` | `111` | `0`: player struct (`core/player.s`) with stats pre-baked |
| 2b | `player_background` | `160` | `160` | `160` | `160` | `0`: 4×40 character background lines |
| 2c | `ZP_STATE_START` (`$40-$5F`) | `32` | `32` | `32` | `32` | `0`: turn counter, timed effects, game flags |
| 2d | `eff_fear_timer` | `1` | `1` | `1` | `1` | `0` |
| 2e | `ZP_RNG_START` (`$1A-$1D`) | `4` | `4` | `4` | `4` | `0`: 32-bit PRNG state |
| 2f | `inv_item_id..inv_ego` (`8 × TOTAL_INV_SLOTS`) | `264` | `264` | **`272`** | **`272`** | **`+8`**: `TOTAL_INV_SLOTS` `33 -> 34` (adds `EQUIP_CLOAK = 32`, `EQUIP_SECONDARY = 33`; `7 * 34 = 238 < 256` preserves 8-bit stride invariant). `55` egos (`0` = none, `1..55`) use `inv_ego` bits `0..5` (`EGO_ID_MASK = $3F`); **bit 6 (`ITEM_PAGE_BIT = $40`) of `inv_ego`** encodes the Base-255 page bit (`0..254` vs `255..369`) with **zero 9th inventory array**. |
| 3 | `id_known_bits` | `20` | `20` | **`47`** | **`47`** | **`+27`**: `ceil(370 / 8) = 47 B` (`ID_KNOWN_BYTES`, `376`-bit capacity covering linear IDs `0..369`; fixed categories refreshed post-load via `item_refresh_fixed_known`) |
| 4a | Flavor shuffles (`potion_shuffle`, `FLAVOUR_COUNT`) | `38` | `38` | **`174`** | **`174`** | **`+136`**: single contiguous `FLAVOUR_COUNT` block covering all randomized VMS pools (`46` potions + `49` scrolls + `30` rings + `24` wands + `25` staves = `174 B`) |
| 4b | Stores (`si_item_id..si_meta_hi`, `8 × STORE_TOTAL_SLOTS`) | `896` | `896` | **`1,024`** | **`1,024`** | **`+128`**: `8 × 16 = 128` store slots (`7 × 128 = 896 B`) plus contiguous **`128 B` sidecar** (`si_meta_hi[128]`: bits `0..5` = 6-bit ego `0..55`, bit `6` = `ITEM_PAGE_BIT`; `si_meta` keeps unshifted `IF_*` bits `0..3`). |
| 4c | Stairs & entry (`stairs_up_x..level_entry_dir`) | `7` | `7` | `7` | `7` | `0`: 6 stair bytes + 1 direction byte |
| 4d | Rooms (`room_count` + `6 × MAX_ROOMS`) | `49` | `127` | `49` | `127` | `0`: `1 + 6×8 = 49 B` (`80x48`), `1 + 6×21 = 127 B` (`198x66`) |
| 4e | Traps (`trap_count` + `3 × MAX_TRAPS`) | `49` | `49` | `49` | `49` | `0`: `18` trap types (`TRAP_TYPE_COUNT = 18`) still fit 1 byte/slot in `trap_type` (`1 + 16×3 = 49 B`, `MAX_TRAPS = 16`) |
| 4f | Active monsters (`monster_table`) | `384` | `384` | `384` | `384` | `0`: `32 × 12 = 384 B` (`MX_TYPE` holds species slot `0..31`) |
| 4g | Doors (`door_state_count` + `3 × MAX_DOOR_STATES`) | `49` | `49` | `49` | `49` | `0`: `1 + 16×3 = 49 B`; unconditional in V2 |
| 4h | Monster species slots (`cat_slot_id_lo/hi`) | `64` | `64` | `64` | `64` | `0`: `2 × 32 = 64 B` 16-bit creature IDs (accommodates all `279` VMS species) |
| 5 | Floor items (`42` slots, `fi_meta_hi` outside `FLOOR_ITEM_BASE`) | `462` | `462` | **`462`** | **`462`** | **`0`**: `11 × 42 = 462 B` (`fi_item_id, fi_x, fi_y, fi_qty, fi_meta_hi, qty_hi, p1, raw fi_meta, fi_to_hit, fi_to_dam, fi_to_ac`). `fi_meta_hi[42]` lives after `fi_to_ac` outside `252 B` `FLOOR_ITEM_BASE` and carries `ITEM_PAGE_BIT` (`$40`) + 6-bit ego (`0..55`), loaded in `HEAD` before `qty_hi`/`p1` gold checks and replacing the redundant `FI_META_EGO_MASK`-truncated `ego` loop; `fi_meta[42]` stores raw unshifted `IF_*` bits `0..3`. |
| 6a | Monster recall (`recall[279]`) | `160` | `160` | **`1,116`** | **`1,116`** | **`+956`**: `4 × 279 = 1,116 B` (`RECALL_DATA_SIZE` interleaved across all `279` VMS species; up from `4 × 40 = 160 B`). Supports `#if HAL_STORAGE_RECALL_CUSTOM` byte streaming via `recall_off_lo/hi` + `hal_recall_read_byte`/`hal_recall_write_byte` for ports keeping recall under C64 `$D700` I/O or BBC `LYNNE` `$3F80`. |
| 6b | Dungeon map (`MAP_BASE`, raw `MAP_SIZE`) | `3,840` | `13,068` | `3,840` | `13,068` | `0`: raw `80×48` (`3,840 B`) or `198×66` (`13,068 B`) |
| 7 | Checksum (`save_cksum_lo/hi`) | `2` | `2` | `2` | `2` | `0`: not accumulated into checksum |
| | **Total Serialized Stream Size (Final V2)** | **`6,600 B`** | **`15,906 B`** | **`7,855 B`** | **`17,161 B`** | **`+1,255 B`** (`+19.0%` on `80x48`; `+7.9%` on `198x66`) |

### 2.2 Critical Data-Encoding Invariants for Phase 4

1. **Base-255 9-bit Paging (`FI_EMPTY = $FF` vs. Item ID `#255`)**:
   - Logical template IDs `0..254` encode with `page_bit = 0`, `slot_lo = id`; logical template IDs `255..369` encode with `page_bit = $40` (`ITEM_PAGE_BIT`), `slot_lo = id - 255` (`0..114`), so `logical_id = slot_lo + (255 if (meta_hi & $40) else 0)`.
   - `FI_EMPTY` (`$FF`) is never valid on either page (`255 - 255 = 0` for Page 1 slot `#255`), eliminating the `$FF` collision completely. `save_sanitize_id_table` / `save_sanitize_store_ids` validate `(slot_lo, meta_hi)` pairs on load (Page 0: `FI_EMPTY` or `< ITEM_PAGE_SIZE`; Page 1: `< ITEM_TYPE_COUNT - ITEM_PAGE_SIZE`, otherwise clearing both `slot_lo = FI_EMPTY` and `meta_hi = 0`).
2. **`FLOOR_ITEM_BASE` Page Ceiling**:
   - `FLOOR_ITEM_BASE` (`6 × 42 = 252 B`: `fi_item_id`, `fi_x`, `fi_y`, `fi_qty`, `fi_p1`, `fi_meta`) fits inside one 256-byte page across all 7 ports. `fi_meta_hi[42]` lives outside `FLOOR_ITEM_BASE` immediately after `fi_to_ac`.
3. **`platforms/shared/save.s` Floor Ego & Flags Fix**:
   - `fi_meta` is stored/loaded raw (`IF_*` bits `0..3`, no `asl; asl; asl`) and `fi_meta_hi` is stored/loaded raw in `HEAD` (no `and #FI_META_EGO_MASK` 3-bit truncation), before `qty_hi` and `p1` check `(fi_meta_hi,x & ITEM_PAGE_BIT) == 0 && fi_item_id,x < 2`.

---

## 3. Per-Port Fixed Save-Slot Budget Table

All 4-slot budgets below include `THE.GAME`..`THE.GAME4` (or `SAVE0`..`SAVE3`) plus `MORIA8.ID` (`1` block/sector) and `HALL.OF.FAME` / `HISCORE.DAT` (`1–2` blocks/sectors) at the exact V2 stream sizes (`7,855 B` for `80x48`; `17,161 B` for `198x66`):

| Port | Map | Save Media & Unit Size | V1 Slot Size | V2 Slot Size | 4 Slots + ID + HiScore | Media Capacity & Free Margin | Verdict & Required Constant Changes |
|---|---|---|---:|---:|---:|---|---|
| **Atari 8-bit** (`800XL` / `130XE` / `.car`) | `80x48` | Separate DOS 2.5 ED `.atr` Save Disk (`1,040` total / `1,020` non-boot / `1,011` file-allocatable sectors `<= 1023`, `125 B` data/sec) | `6,600 B` (`53` used / `56` pre-alloc = `7,000 B`) | **`7,855 B`** (`63` sec used) | **`275 / 1,011`** data sectors (at `68` sec/slot) | `736` data sectors free (`92.0 KB`); Program `.atr` never accepts saves (`145` free sec) | **EXCEEDS current `56`-sector (`7,000 B`) cap!** Bump `ATARI_SAVE_SLOT_SECTORS` in `platforms/atari8/memory.s` from `56` to **`68`** (`8,500 B`, leaving headroom over `7,855 B`), and bump `ATARI_SAVE_SERIALIZED_MAX` (`6616 -> 7855+`). Update `disk_setup_atari.s` and `tools/make_atr.py` to match. |
| **C64** (Disk / EasyFlash) | `80x48` | `.d64` SEQ `THE.GAME..4` (`254 B` user data/block) | `6,600 B` (`26` blks) | **`7,855 B`** (`31` blks) | **`126` blks** | Save `.d64`: `664` blks (`~538` free). Program `.d64`: ~`194 / 664` free before Phase 3/4 asset changes | **Fits Save `.d64` easily.** Single-disk Program `.d64` fits 4 slots *only* if remaining free blocks allow; otherwise use separate Save Disk. |
| **Plus/4** (Disk / `.crt`) | `80x48` | `.d64` SEQ `THE.GAME..4` (`254 B` user data/block) | `6,600 B` (`26` blks) | **`7,855 B`** (`31` blks) | **`126` blks** | Save `.d64`: `664` blks (`~538` free). Program `.d64`: ~`242 / 664` free (`~116` blks margin) | **Fits both Save `.d64` and Program `.d64`** (`+5` blocks/slot). Fix stale `LOAD_SAVE_MAP_SIZE = 3676` in `make_load_resume_save_plus4.py` to `3840`. |
| **C128** (Disk / MD128 `.crt`) | `198x66` | `.d71` (`1,328` data blks) / `.d81` (`3,160` data blks) / `.d64` (`664` blks), `254 B`/blk | `15,906 B` (`63` blks) | **`17,161 B`** (`68` blks) | **`274` blks** | Save `.d64`: `390` free. Single-disk `.d71`: `839` free -> `565` left; `.d81`: `2,671` free -> `2,397` left. | **Fits Save `.d64`, single/save `.d71`, and single/save `.d81` easily** (`+5` blks/slot). Single-disk `.d64` remains 2-slot max / Save-Disk recommended as in V1. |
| **Apple IIe** | `198x66` | Separate ProDOS save `.po` (`140 KB` `280` blks or **`800 KB` `1,600` blks**, `512 B`/blk + `1` sapling index blk/file) | `15,906 B` (`32+1 = 33` blks) | **`17,161 B`** (`34+1 = 35` blks) | **`142` user blks** (`+ 7` FS = `149`) | `140 KB` Save `.po`: `131 / 280` blks free. **`800 KB` Save `.po`: `1,451 / 1,600` blks free.** Program `.po` (`14/280` free) forbids saves | **Fits both `140 KB` and `800 KB` Save `.po` volumes cleanly** (`+2` blocks/slot; `17,161 B` = `34` data blocks + `1` index block). |
| **Commander X16** | `198x66` | HostFS / FAT32 SD card flat files (`THE.GAME..4`) | `15,906 B` | **`17,161 B`** | **`~68.7 KB`** total | Host filesystem / SD card (no fixed slot cap) | **Zero space constraint.** Stream grows `+1,255 B` per file. |
| **Acorn BBC Master 128** | `198x66` | Separate 80-track Acorn DFS `.ssd` (`800` sectors × `256 B`, `798` usable, `31`-file DFS limit) | `15,906 B` (`63` sec) | **`17,161 B`** (`68` sec) | **`275 / 798`** sectors (`6 / 31` files) | Save `.ssd`: `~523` sectors (`~130.8 KB`) free. Program `.ssd` (`387/800` free) strictly forbids saves | **Fits separate Save `.ssd` easily** (`+5` sectors/slot; `68` sectors holds up to `17,408 B`). |

---

## 4. Audit of `platforms/shared/save.s` Legacy V1..V19 Migration Branches

Measured directly from C64 `build/c64/main.sym` (`$a068..$a935`) and `platforms/shared/save.s` source lines. Setting `OLDEST_SAVE_VERSION = SAVE_VERSION` in Phase 4 removes the following legacy code and buffers:

| Legacy Symbol / Guard | `platforms/shared/save.s` Span | Active Ports Today | Purpose Today | Reclaimed Bytes (Measured `C64` / Port) | Notes |
|---|---|---|---|---:|---|
| `SAVE_KNOWN96_VERSION`, `SAVE_KNOWN_BITS_VERSION`, `SAVE_KNOWN160_VERSION` | `L21-L27`, `L1615-L1709` | All 7 *(most compiled-out logic still linked)* | Legacy 64-byte / 96-byte known staging + 16-byte bitset clear/pack (`idk_clear_bits`, `idk_pack_stage`, `idk_legacy_stage` `.fill 96, 0`) | **`~244 B`** | Measured `C64`: `load_read_known_items` (`169 B`) + `idk_clear_bits` (`11 B`) + `idk_pack_stage` (`16 B`) + `idk_legacy_stage` (`96 B`) = `292 B`; keeping defensive fixed-category refresh (`~36 B`) + `:load_block(id_known_bits, 47)` (`~12 B`) leaves `~48 B`, freeing **`~244 B`** in `Default` (or `StorageOverlay` on A2/BBC). |
| `SAVE_INV31_VERSION`, `SAVE_INV33_VERSION` | `L28-L31`, `L1510-L1548` | All 7 (`INV31` `.if` false on all catalog builds; `INV33` live) | `load_inv_slots` (`1 B`) + `load_read_inventory_state` (`64 B`, `$a50b..$a54a`) per-array 8-pass loader for 30/31/33 slots | **`~15–52 B`** | Dropping version checks only saves **`~15 B`**; folding the fixed `8 * TOTAL_INV_SLOTS` read directly into `save_block_table_pre_inventory` (`65 B` gross minus `~13–20 B` retained `item_init_inventory` + `save_sanitize_id_table` setup) reclaims **`~45–52 B`** net. |
| `SAVE_STATS_BAKED_VERSION` | `L34`, `L1105-L1112` | All 7 *(never taken when pinned to `SAVE_VERSION`)* | One-time deterministic race/class stat baking for pre-baked saves (`stat_bake_mode = 0`, `jsr player_bake_stat_modifiers`) | **`~17 B`** | `17 B` in `platforms/shared/save.s`. Optional `core/player.s` follow-up (`stat_bake_mode == 0` path in `player_bake_apply_one`) saves another `~15 B` if no test exercises mode `0` (`player_bake_creation_stats` stays). |
| `SAVE_DOOR_STATE_VERSION` | `L37`, `L442`, `L1715-L1745` | All 7 *(pinned `== OLDEST_SAVE_VERSION`)* | Guards `door_state_count` + `cat_slot_id` block on old saves (`cmp #SAVE_DOOR_STATE_VERSION / bcc`) | **`~7 B`** | Version branch is already dead against `.assert L442`; folding into `save_block_table_post_known` (keeping `door_state_count` range check + `catalog_refetch_slots`) can reclaim another `~20 B` wrapper overhead. |
| `SAVE_FLOOR42_VERSION` / `save_version_uses_legacy_floor_layout` | `L20`, `L2120-L2129`, `L2235-L2242`, `L1294` (`load_read_floor_block_table` `$a44d`) | All 7 | Switches `load_floor_item_count` between 32 and 42 floor slots and duplicates `load_read_block_table` with dynamic slot count | **`~66 B`** | Reclaims `load_floor_item_count` (`1 B`), `save_version_uses_legacy_floor_layout` (`8 B`), legacy branch in `load_read_floor_items` (`~13 B`), and `load_read_floor_block_table` (`44 B`, replaced by `load_read_block_table`). |
| `HAL_STORAGE_LEGACY_STORE12_MIGRATION` | `L42-L47`, `L1000-L1001`, `L1808-L1863` | **C64 only** (`Balrog` `$17` checkpoints) | Spreads 12-item store rows across 16-item RAM rows (`load_read_post_known_store12`) | **`~82 B`** | Measured `C64`: `load_read_post_known_store12` (`92 B`) minus `10 B` inline caller `load_read_block_table` setup (`82 B` net on C64; `0 B` on other 6 ports). |
| `HAL_STORAGE_LEGACY_ROOM8_MIGRATION` | `L38-L41`, `L368-L393`, `L699-L701`, `L998-L999`, `L1755-L1797` | **C128 only** | Reads legacy 8-room metadata layout and clears rooms `8..20` (`save_block_table_post_known_room8`, `load_read_post_known_state`, `load_clear_room_metadata_tail`) | **`~109 B`** | `C128` only: `save_block_table_post_known_room8` (`60 B`) + `load_read_post_known_state` (`~21 B` net) + `load_clear_room_metadata_tail` (`28 B`). |
| `save_version_supported` range check | `L2218-L2227` | All 7 | Checks `[OLDEST_SAVE_VERSION, SAVE_VERSION]` inclusive | **`~5 B`** | Simplifies from `12 B` range check to `7 B` exact `cmp #SAVE_VERSION / clc / bne / sec / rts`. |
| **Total Reclaimed (`save.s` Resident / StorageOverlay)** | — | **Per-Port Summary** | — | **`~354–500 B`** | **Standard (`Plus/4`, `Atari8`, `A2`, `CX16`, `BBCM`): `~354–391 B`**; **C64 (`+STORE12`): `~436–473 B`**; **C128 (`+ROOM8`): `~463–500 B`** *(each `~20 B` higher if `door_state` wrapper is also folded)*. |

*(Note: `#if SAVE_TEST_RLE` workspace/compressor at lines `143-179, 2523+` is already compiled out of product builds and untouched here unless unit-test cleanup retires it separately.)*

---

## 5. Atomic Phase 4 Co-Commit Checklist

Save Format V2 changes stream shape, memory layout, playtest inspection, and save-test fixtures simultaneously; all items below must land together in Phase 4:

### 5.1 `core/` (Wave 4.2 `core-items-p4`)
- [x] `core/item_defs.s`: expand `TOTAL_INV_SLOTS` `33 -> 34` (`EQUIP_CLOAK = 32`, `EQUIP_SECONDARY = 33`), set `ID_KNOWN_BYTES = 47` (`(370 + 7) >> 3`), expand `EGO_TYPE_COUNT` (`55` egos, `EGO_ID_MASK = $3F`), enforce Base-255 paging (`ITEM_PAGE_SIZE = 255`, `ITEM_PAGE_BIT = $40`, `#255` vs `FI_EMPTY` invariant), and keep `FLOOR_ITEM_BASE` (`252 B`) unchanged with `fi_meta_hi[42]` placed outside it.
- [x] `core/item.s`, `core/store_inventory_data.s`: size `inv_*` to `34`, pack `ITEM_PAGE_BIT` into `inv_ego` (`0` new inventory array), add `si_meta_hi[128]` + `fi_meta_hi[42]` sidecars, and store unshifted `IF_*` flag bits `0..3` in `si_meta`/`fi_meta` (`FI_META_FLAGS_MASK = $0F`).
- [x] `core/item_identification.s`: resize `id_known_bits` to `47 B`, shuffle tables to contiguous `FLAVOUR_COUNT = 174 B` (`potion_shuffle..staff_shuffle`), and provide resident `item_refresh_fixed_known`.
- [x] `core/dungeon_data.s`: `TRAP_TYPE_COUNT = 18` (`MAX_TRAPS = 16`, `49 B` trap table).
- [x] `core/recall_defs.s`, `core/recall_array_data.s`, `core/recall.s`: expand `RECALL_DATA_SIZE` to `4 * 279 = 1,116 B` and expose `recall_off_lo/hi` + `hal_recall_read_byte`/`hal_recall_write_byte` hooks for `#if HAL_STORAGE_RECALL_CUSTOM`.
- [x] `core/monster_acid.s` & equipment/weight/pseudo-ID loops: include Cloak slot (`EQUIP_CLOAK`).

### 5.2 `platforms/` & `tools/` (Wave 4.2 `save-playtest-p4` + Wave 4.3 port updates)
- [x] `platforms/shared/save.s`:
  - Set `OLDEST_SAVE_VERSION = hal_storage_save_v1_version` (`$20`).
  - Delete V1..V19 migration constants, blocks, and helpers (`SAVE_KNOWN96_VERSION`..`HAL_STORAGE_LEGACY_STORE12_MIGRATION`, `SAVE_FLOOR42_VERSION`, `save_version_uses_legacy_floor_layout`, `load_read_floor_block_table`, `load_floor_item_count`, `load_inv_slots`, `load_read_inventory_state`, `load_stats_migrated`).
  - Update V2 stream tables/readers/writers for `47 B` `id_known_bits` (+ `item_refresh_fixed_known`), `174 B` shuffles (`FLAVOUR_COUNT`), `34` `inv_*` slots (`272 B`), `8 * STORE_TOTAL_SLOTS` (`1,024 B`, including `si_meta_hi`), `42 B` `fi_meta_hi` in `HEAD` (removing `FI_META_EGO_MASK` & `asl; asl; asl`), paged 9-bit `save_sanitize_id_table`/`save_sanitize_inv_ids`/`save_sanitize_floor_ids`/`save_sanitize_store_ids`, and `RECALL_DATA_SIZE` (`1,116 B`) with `#if HAL_STORAGE_RECALL_CUSTOM` byte streaming.
  - Simplify `save_version_supported` to accept only `SAVE_VERSION` (`$20`), rejecting all other versions with `LOAD_RESULT_UNSUPPORTED`.
- [x] All 7 `hal/storage_policy.s` files (`platforms/commodore/{c64,c128,plus4}/hal/storage_policy.s`, `platforms/{atari8,apple2,cx16,bbcmaster}/hal/storage_policy.s`):
  - Bump `hal_storage_save_version` and `hal_storage_save_v1_version` together to `$20` (and `$19` on Atari 8-bit where `hal_storage_save_version = $19` and `hal_storage_save_v1_version = $19`).
  - Remove legacy `hal_storage_save_known*`, `inv*`, `baked_stats`, `door_state`, `store16` constants and `#define HAL_STORAGE_LEGACY_*`.
- [x] Wave 4.3 port memory placement, `#define HAL_STORAGE_RECALL_CUSTOM`, and `PLATFORM_SHUFFLE_BASE` (`174 B`) / bank assertions for expanded RAM tables (`id_known_bits[47]`, `shuffle[174]`, `si_meta_hi[128]`, `fi_meta_hi[42]`, `recall[279] = 1,116 B`) across all 7 `memory*.s` / `check_memory_contract.py` checkers.
- [x] Atari Save Disk growth (`platforms/atari8/memory.s`, `platforms/atari8/disk_setup_atari.s`, `tools/make_atr.py`):
  - Bump `ATARI_SAVE_SLOT_SECTORS` (`56 -> 68`) and `ATARI_SAVE_SERIALIZED_MAX` (`6616 -> 7872`) in `platforms/atari8/memory.s`.
  - Update `save_disk_dir_table` sector counts/start sectors (`SAVE0..3.SAV`), `init_empty_sec_lo/hi`, and `init_vtoc_head` in `platforms/atari8/disk_setup_atari.s`.
  - Update `tools/make_atr.py` `run_selftest()` (`add_preallocated_empty_slot` `56 -> 68`).

### 5.3 `playtest/` (Wave 4.2 `save-playtest-p4`)
- [x] `playtest/moria_playtest/knowledge.py`: update `item_kinds()` to load `platforms/shared/item_catalog/item_catalog_spec.json` (`370` items, 16-bit weight, `missile_type == 0` melee check).
- [x] `playtest/moria_playtest/brain.py`: add `Cloak` (`ICAT_CLOAK`) to `EQUIP_LINE`, `EQUIP_SLOTS`, and `ARMOUR_SLOTS` (preserving optional absence in equipment fixtures), and strip positive `EGO_ARMOUR` suffixes in `gear_pick`.
- [x] `playtest/moria_playtest/disk.py`: set `SAVE_VERSION = 0x20`, `TOTAL_INV_SLOTS = 34`, and add `decode_paged_item(slot_lo, ego)` for Base-255 9-bit paged IDs and 6-bit egos (`0..55`).
- [x] Verify `playtest/moria_playtest/queue.py` (`save_versions()` / `start_loads()`) resets pre-V2 checkpoints cleanly to DL1; run `playtest` unit suite (`playtest/tests/`).

### 5.4 `test_save` & Cross-Port Save Smoke Suites (Wave 4.3)
- [x] `platforms/commodore/c64/tests/test_save.s` and `platforms/commodore/c64/run_tests.sh:4954-4955` (`save_split_item_stats_contract`):
  - Drop `#define HAL_STORAGE_LEGACY_STORE12_MIGRATION`, update `test_save.s` for `$20`, `TOTAL_INV_SLOTS = 34`, Base-255 paged IDs, `55` egos, `si_meta_hi`/`fi_meta_hi`, `47 B` `id_known_bits`, `174 B` shuffles, `1,116 B` recall, retire V1..V19 migration tests (replacing with `SAVE_VERSION - 1` / `SAVE_VERSION + 1` rejection), and sync `save_split_item_stats_contract` needles in `run_tests.sh` after removal of `load_inv_slots`, `load_read_inventory_state`, `load_floor_item_count`, and `load_read_floor_block_table`.
- [x] Save-fixture generators (sync headers, `SAVE_VERSION = $20`, `TOTAL_INV_SLOTS = 34`, `ID_KNOWN_BYTES = 47`, `174 B` shuffles, `si_meta_hi`/`fi_meta_hi` sidecars, `RECALL_DATA_SIZE = 1116`, and map size):
  - `platforms/commodore/c64/tests/make_load_resume_save64.py`
  - `platforms/commodore/plus4/tests/make_load_resume_save_plus4.py` (also update `LOAD_SAVE_MAP_SIZE = 3676` -> `3840`)
  - `platforms/commodore/c128/tests/make_load_resume_save.py` (drop `--legacy-room8` mode and `C128_LEGACY_ROOM8` callers in `platforms/commodore/c128/run_tests128.sh`)
- [x] Runtime save/load smoke harnesses across all 7 ports:
  - `platforms/commodore/{c64,c128,plus4}/run_tests*.sh`
  - `platforms/atari8/harness_smoke.py` & `platforms/atari8/test_cartridge.py` (update expected sector count threshold if needed)
  - `platforms/apple2/harness_smoke.py` (`save_load`, `save_reboot_load`, `save_slot_tracking`, seeded equipment/inventory assertions)
  - `platforms/cx16/harness_smoke.py` (`THE.GAME` / `THE.GAME2` save roundtrips)
  - `platforms/bbcmaster/harness_smoke.py` (`save_load` secondary weapon/cloak slot indices at lines `561-593`)
