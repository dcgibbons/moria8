# Commander X16 Memory Contract

Placement and banking source of truth for the Commander X16 port (`platforms/cx16/`).
Enforced at link time by `.assert` guards in `platforms/cx16/memory.s` and
`platforms/cx16/main.s`, and at build time by `platforms/cx16/check_memory_contract.py`.

## 1. Fixed Low RAM (`$0000-$9FFF`)

The Commander X16 provides 38.6 KB of unbanked low RAM (`$0801-$9EFF`) plus
`$0400-$07FF` (1,024 bytes unused by the KERNAL because VERA text lives in
VRAM `$1B000`). Switching the active RAM bank via ZP `$00` affects **only**
`$A000-$BFFF`; `$0000-$9EFF` is always visible.

| Address Range | Size | Owner | Notes |
| --- | ---: | --- | --- |
| `$0000` | 1 B | `CX16_RAM_BANK_REG` | Active 8 KB RAM bank at `$A000-$BFFF` (`0..63`) |
| `$0001` | 1 B | `CX16_ROM_BANK_REG` | Active 16 KB ROM bank at `$C000-$FFFF` (`0` = KERNAL) |
| `$0002-$008F` | 142 B | Shared Core ZP (`core/zeropage.s`) | `$02-$7F` is application ZP; `$80-$8F` is saved/restored around KERNAL file I/O (`save_zp`/`restore_zp`) |
| `$0090-$00FF` | 112 B | CX16 KERNAL ZP | Reserved for KERNAL routines |
| `$0100-$01FF` | 256 B | Hardware Stack | Always unbanked |
| `$0200-$03FF` | 512 B | KERNAL Vectors & System Scratch | Reserved for CX16 KERNAL; boot chains the `keyhdl` vector (`$032E`) to `cx16_key_event` (`platforms/cx16/input.s`), which tracks held keys for `input_wait_release` |
| `$0400-$04FF` | 256 B | `FLOOR_ITEM_BASE` | Active level floor-item table |
| `$0500-$05FF` | 256 B | `CREATURE_BASE` | Runtime creature/RLE/high-score scratch |
| `$0600-$06FF` | 256 B | `PLATFORM_HD_DECODE_BUF_BASE` / `DUNGEON_GEN_DOOR_SCAN_BASE` | Shared Huffman decode & dungeon-gen door-scan scratch |
| `$0700-$07FF` | 256 B | `CX16_ROW_STAGE_BASE` (`rv_row_map_buf`, `rv_row_color_buf`) | Shared VERA row staging, page-burst file I/O staging, and IRQ-masked per-chunk `cx16_bank_copy` bounce buffer |
| `$0801-$9AFF` | 37,631 B | Unified Resident + Play Image (`MORIA8.PRG`) | BASIC stub at `$0801`, entry at `$080D`, all resident + gameplay modules |
| `$9B00-$9EFF` | 1,024 B | `PLATFORM_TIER_NAME_POOL_BASE` | Monster name pool: 32 entries of 32 B, one per catalog species slot (`core/monster_catalog.s`) |
| `$9F00-$9FFF` | 256 B | Hardware I/O (`VIA1`/`VIA2` `$9F00-$9F1F`, `VERA` `$9F20-$9F3F`) | Forbidden to code/data |

## 2. Banked RAM Window (`$A000-$BFFF`, 8 KB × 64 Banks)

Each 8 KB RAM bank (`$A000-$BFFF`) has a dedicated, non-overlapping owner:

| RAM Bank | Virtual Address | Payload / File | Owner & Lifecycle |
| ---: | --- | --- | --- |
| `0` | N/A | System / KERNAL `KVARSB0` | Reserved for CX16 KERNAL (keyboard count `$A80A`, etc.); never overwritten |
| `1` | `$2000-$3FFF` | Live Map Low Half (8,192 B) | First 8,192 B of the 198×66 dungeon map (`MAP_BASE = $2000`) |
| `2` | `$4000-$530B` | Live Map High Half (4,876 B) | Remaining 4,876 B of the 198×66 dungeon map (`MAP_END = $530B`) |
| `3` | `$6000-$7FFF` | `CX16.AUXDATA` (`Cx16AuxData`) | Preloaded at boot: item name streams, `it_unknown_idx`, `key_map_petscii`/`key_map_cmd`, store inventory/runtime, recall arrays, spell tables/names, ego suffix slots |
| `4` | `$8000-$9FFF` | `CX16.HUFFDATA` (`Cx16HuffData`) | Preloaded at boot: Huffman tree and compressed string corpus, then the monster catalog's Huffman-coded names |
| `5` | `$A000-$BFFF` | `MONSTER.EXT` (`CX16_BANK_CATALOG_EXT = 5`) | Preloaded at boot: Phase 5 extended monster catalog (`279 × 8 B = 2,232 / 8,192 B`, `$A000-$A8B7`, `5,960 B` free), read via `$00`-preserving `catalog_fetch_ext` (`platforms/cx16/monster_catalog_bank.s`) |
| `6` | `$A000-$BFFF` | `ITEM.CAT` (`CX16_BANK_ITEM_CAT = 6`) | Preloaded at boot: `'ITM2'` item/ego/flavor catalog (`7,573 / 8,192 B`, `$A000-$BD94`, `619 B` free), read via Low-RAM `$00`-preserving helpers (`platforms/cx16/item_cat_bank.s`) |
| `7-8` | `$A000-$BFFF` | Reserved (`CX16_BANK_EXT_BASE..END = 7..8`) | Reclaimed from obsolete `MONSTER.DB.3..4`; free extended HiRAM banks (`16 KB`) |
| `9` | `$A000-$BFFF` | `OVL.START` (`OVL_STARTUP = 1`) | Preloaded at boot: character creation, `player_chargen_cold.s`, & item ID init |
| `10` | `$A000-$BFFF` | `OVL.TOWN` (`OVL_TOWN = 2`) | Preloaded at boot: town stores UI (`store.s`, `ui_store.s`; Home moved to `OVL.HOME` under `HOME_OVERLAY_SEPARATE`) |
| `11` | `$A000-$BFFF` | `OVL.DEATH` (`OVL_DEATH = 3`) | Preloaded at boot: death/retirement/score & heavy area spells |
| `12` | `$A000-$BFFF` | `OVL.GEN` (`OVL_DUNGEON_GEN = 4`) | Preloaded at boot: town & dungeon generator, special rooms, `item_spawn_level_gen` |
| `13` | `$A000-$BFFF` | `OVL.HELP` (`OVL_HELP = 5`) | Preloaded at boot: 80-col help, inventory/equipment, `door_open_close_cold.s`, `item_drop_cold.s`, & `mae_cold_body` (zero-HP cold melee attack effects) |
| `14` | `$A000-$BFFF` | `OVL.UI` (`OVL_UI = 6`) | Preloaded at boot: character sheet, `player_bg_draw_cold.s`, & symbol identify UI |
| `15` | `$A000-$BFFF` | `OVL.ITEMS` (`OVL_ITEMS = 7`) | Preloaded at boot: item actions, `item_pickup`, wear/takeoff/eat/quaff, bash/disarm/tunnel (`7,200 / 8,192 B`, `992 B` free) |
| `16` | `$A000-$BFFF` | `OVL.SPELL` (`OVL_SPELL = 8`) | Preloaded at boot: spell/prayer selection, execution, `eff_wall_to_mud`, level-up; Find Traps and Destroy Traps/Doors (`core/spell_effects_overlay.s`) |
| `17` | `$A000-$BFFF` | `OVL.MODAL` (`OVL_MODAL_MISC = 9`) | Preloaded at boot: 15-field `/` monster recall (`ui_recall.s` + 80-col tables), wizard UI, royal screen, look, `re_equip`, `run_initialize_impl` |
| `18` | `$A000-$BFFF` | `OVL.CHEST` (`OVL_CHEST = 10`) | Preloaded at boot: chest open/disarm/bash, `trap_trigger_cold.s`, door jam/pick, store restock |
| `19` | `$A000-$BFFF` | `OVL.HOME` (`OVL_HOME = 11`) | Preloaded at boot: player Home UI (`core/ui_home.s`, `core/ui_home_text.s`) |
| `20` | `$A000-$BFFF` | `OVL.STORAGE` (`OVL_STORAGE = 12`) | Preloaded at boot: shared save/load engine, `title_load_game_ovl`, & slot menu |
| `21` | `$A000-$BFFF` | `OVL.TITLE` (`OVL_TITLE = 13`) | Preloaded at boot: title screen renderer, menu loop, cold boot init, `starting_kit_cold.s`, & system info |
| `22` | `$A000-$BFFF` | `TITLE` | Preloaded at boot: title screen artwork stream |
| `23` | `$A000-$BFFF` | `MONSTER.CAT` (`Cx16Catalog`) | Preloaded at boot: monster catalog, 21 core engine fields x 279 creatures, level counts, `cat_available` (`279/279` playable), & `cat_undead[35]` (`5,976 / 8,192 B`, `2,216 B` free) |
| `24` | `$A000-$BFFF` | `LEGALUI` (`CX16_BANK_LEGAL = 24`) | Loaded on demand for license/source text; restores prior bank on return |
| `25-63` | `$A000-$BFFF` | Reserved (`CX16_BANK_WARM_BASE..END = 25..63`) | Free warm/extended HiRAM pool (39 banks = 312 KB; `CX16_BANK_COUNT = 64`) |

Bank 23 (`CX16_BANK_CATALOG`, formerly Bank 22 before Phase 2 `OVL.HOME` insertion)
is mapped only by `cx16_catalog_map` and `cx16_catalog_unmap`
(`platforms/cx16/monster_catalog_bank.s`), resident code that saves the
caller's bank (an overlay in Banks 9-21) and interrupt state and restores both,
while Bank 5 (`CX16_BANK_CATALOG_EXT`) holds the 8 extended Phase 5 fields per
creature (`MONSTER.EXT`, `2,232 B` at `$A000-$A8B7`, `5,960 B` free), read into
`cat_ext_record[0..7]` by `$00`-preserving `catalog_fetch_ext`.
The catalog's Huffman-coded names ride in Bank 4 after the corpus
(`Cx16HuffData`, virtual `$8DF6-$9C10`), read like the corpus.
`core/monster_catalog.s` copies a species' 29 fields into resident `cr_*` rows
and decodes its name into the `$9B00` pool. Bank 6 (`CX16_BANK_ITEM_CAT`) holds
the preloaded `'ITM2'` `ITEM.CAT` (`7,573 B` at `$A000-$BD94`, `619 B` free).
Banks 7-8 (`CX16_BANK_EXT_BASE..END`) and Banks 25-63 (`CX16_BANK_WARM_BASE..END`)
are formally partitioned in `platforms/cx16/memory.s` (`0..63`, **23 used / 41 free = 328 KB free**)
and verified without collision at assemble time and by `check_memory_contract.py`.

## 3. Virtual-to-Banked Address Translation (`$2000-$9FFF`)

Every virtual address `V = zp_ptr + Y` in `$2000-$9FFF` maps deterministically
to a 8 KB RAM bank and `$A000-$BFFF` window address:

* Effective 16-bit address: `eff_addr = zp_ptr + Y`, with `eff_hi = eff_addr >> 8` and `eff_lo = eff_addr & $FF`.
* Target RAM bank: `bank = eff_hi >> 5` (`1` for `$20-$3F`, `2` for `$40-$5F`, `3` for `$60-$7F`, `4` for `$80-$9F`).
* Window address inside `$A000-$BFFF`: `win_addr = (((eff_hi & $1F) | $A0) << 8) | eff_lo`.

Because `zp_ptr + Y` is resolved to a 16-bit effective address before computing
`bank` and `win_addr`, indexed accesses `(zp_ptr0),y` and `(zp_ptr1),y` never
cross `$BFFF` into `$C000` ROM even when a map row straddles the `$3FFF/$4000`
boundary between Bank 1 and Bank 2.

All `mmu_safe_map_read_ptr0/1` and `mmu_safe_map_write_ptr0/1` calls execute in
fixed low RAM, save and restore `CX16_RAM_BANK_REG` (`$00`), and preserve `X`,
`Y`, and carry (`C`), so code executing inside any overlay bank (`9..21`) can
freely read and write the Map, `Cx16AuxData`, and `Cx16HuffData`.

### Multi-Bank Extended Helpers (`platforms/cx16/memory_bank.s`)

Fixed low RAM (`< $9B00`) also exposes `$00`-preserving accessors for explicit
bank numbers (`0..63`, covering reclaimed Banks `5..8` and warm pool `25..63`):

* `cx16_bank_read_byte`: reads bank `A` at `(zp_ptr0),y` into `A` (sets `N`/`Z`; preserves `X`, `Y`, `C`, `V`, `$00`).
* `cx16_bank_write_byte`: writes `A` to bank `X` at `(zp_ptr0),y` (preserves `A`, `X`, `Y`, flags, `$00`).
* `cx16_bank_read_block` / `cx16_bank_write_block`: copies `X` bytes (`0` = 256) between bank `A` `(zp_ptr0),y` and fixed Low RAM `(zp_ptr1),y` while restoring caller `$00`.
* `cx16_bank_copy`: copies `A`/`X` (16-bit byte length `lo`/`hi`) from `(zp_temp0, zp_ptr0)` to `(zp_temp1, zp_ptr1)` across any `$A000-$BFFF` banks using the shared 256-byte Low-RAM bounce buffer `CX16_ROW_STAGE_BASE` (`$0700-$07FF`). Each chunk runs under `php; sei ... plp` and restores `$00` between chunks, allocating zero new zero-page variables (reusing `zp_temp0..3`, `zp_ptr0..1`, `cx16_zp_scratch`).

## 4. Verification Gates

* Static memory contract self-test: `make testcx16-memory-contract-selftest` (`check_memory_contract.py --selftest`, `check_cx16_cart.py --selftest`, `test_cartridge.py --selftest`)
* Static linked-symbol & PRG extent gate: `make testcx16-memory-contract` (21 asserts × 2 build dirs + 21-asset cart verification)
* Runtime TestBench suite: `make testcx16-runtime` (26 scenarios in `platforms/cx16/harness_smoke.py`, including `bank_bounce_helpers` and `OVL.HOME` deposit/retrieve in `wizard_flow`)
* Cartridge verification suite: `make testcx16-cartridge` (`tools/check_cx16_cart.py`, `platforms/cx16/test_cartridge.py`)

## 5. Cartridge ROM Banks (`$C000-$FFFF`, Banks `32+`, `CX16_CARTRIDGE`)

When built with `-define CX16_CARTRIDGE` into isolated `build/cx16-cart/`:

* `$01` (`CX16_ROM_BANK_REG`) switches the 16 KB `$C000-$FFFF` window between KERNAL ROM (`0`) and Cartridge ROM (`32..39`, 8 × 16 KB = 128 KB NOR-flash image `build/cx16-cart/moria8-cx16.bin`, wrapped in 480-byte `.crt` header as `build/moria8-cx16.crt`).
* Because `$C000-$FFFF` does not overlap fixed low RAM (`$0000-$9EFF`) or the `$A000-$BFFF` banked RAM window (`$00`), cartridge asset copies require **no bounce buffer**.
* Bank `32` `$C000-$C003` carries `"CX16"`; `$C004` (`boot_cold_start` in `platforms/cx16/cartridge_boot.s`) copies a self-contained copier stub to `CART_COPY_STUB_ADDR` (`$0400-$04FF`, `FLOOR_ITEM_BASE`, unused before `entry_bootstrap`), copies `MORIA8.PRG` into `$0801..` from ROM Banks `32+`, restores `$00=0` and `$01=0` (KERNAL Bank 0), flushes `$A80A`, enables interrupts (`cli`), and jumps to `entry_bootstrap` (`$080D`).
* Bank `32` `$C100-$C1FF` holds 23 × 8-byte descriptors (`bank`, `rom_lo`, `rom_hi`, `dest_lo`, `dest_hi`, `ram_bank`, `size_lo`, `size_hi`) for `MORIA8.PRG`, `CX16.AUXDATA` (Bank 3), `CX16.HUFFDATA` (Bank 4), `MONSTER.EXT` (Bank 5), `ITEM.CAT` (Bank 6), `OVL.START..OVL.TITLE` (Banks 9–21, including `OVL.HOME` at Bank 19), `TITLE` (Bank 22), `MONSTER.CAT` (Bank 23), `LEGALUI` (Bank 24), `LICENSE`, and `SOURCE-OFFER`.
* Resident `platforms/cx16/cartridge_copy.s` (`cart_load_asset`, `cart_read`, `cart_load_prg`) saves and restores `$00`, `$01`, and processor status (`P`), never uses zero-page variables, and handles `$FFFF -> $C000` bank boundaries seamlessly.
* Character saves (`"THE.GAME"`..`"THE.GAME4"`) and `HALL.OF.FAME` remain on HostFS / SD Drive 8–11 (`save_device`) and are interchangeable with `build/cx16/MORIA8.PRG`.

## License/source modal ownership (2026-11-10)

`LEGALUI` is an uncached modal loaded on title `A` (About) or Help `L`: temporary Bank 23 $A000-$BFFF; restores the previous RAM bank.
Code ends before overlay base+$600; a 142-byte core-ZP snapshot starts there,
and the disk/ROM input cache occupies base+$700..+$7FF. Both are modal
workspace, never game-data loans or emitted PRG padding. The resident entry saves core ZP before asset loading, after any media
handler that may itself load an overlay.
The viewer reads existing documents through the storage HAL, closes every
channel, retains live sound/redraw state, and restores the caller snapshot.
Linked payload bounds and production-path modal entry/return tests enforce
this ownership. See `docs/LEGAL_VIEWER.md` for the change and verification record.

Verification (2026-11-10): `make -j7 -O test` passed, including the linked PRG
ownership checks and the TestBench title/Help legal-viewer scenario, including
preserved player state and return to gameplay. Bank 23 is temporary; existing
cached banks retain their owners.

Review repair: the build emits uppercase `LEGALUI` directly. The cold modal
uses Bank 23 without invalidating the cached overlay tags in Banks 9-20.
A low-resident reader selects Bank 0 once per 128-byte chunk, uses the idle
row staging buffer, then restores Bank 23 before copying into its cache.
It restores the caller ROM bank too. Fatal READST rejects the refill before
rendering, and a zero-byte refill performs no copy. Injected $42 verifies
the error screen, zero count and untouched Bank 23 cache.

Repair verification (2026-11-11): `make -j7 -O test` passed. Applicable payload
bounds, header/load/execution ownership, missing-file cleanup and production
modal-return rows are complete; see `docs/LEGAL_VIEWER.md` for linked spans and
coverage. Existing banking configurations and persistent cache owners remain;
physical display-layout changes are N/A.

## Cartridge port (`CX16_CARTRIDGE`, 2026-11-13)

`CX16_CARTRIDGE` builds into isolated `build/cx16-cart/`, leaving non-cartridge
`build/cx16/` payloads byte-identical. `MORIA8.PRG` spans `$0801-$98FC`
(leaving `$98FD-$9AFF` free below `PLATFORM_TIER_NAME_POOL_BASE` at `$9B00`);
`LEGALUI` (`$A000-$A39E`, Bank 23) streams `LICENSE` and `SOURCE-OFFER` via
resident `cart_read` (`cart_is_record = 2`) into `legal_input_cache` (`legal_eof`
cleared to `$00` on open and set to `$40` on EOF). All 8
ROM banks (`32..39`, 128 KB raw NOR-flash `moria8-cx16.bin`, 131,552-byte
`build/moria8-cx16.crt`) are packed via `tools/make_cx16_cart.py` (`101,027` B
used, `30,045` B free) and validated by `tools/check_cx16_cart.py` (exact asset
IDs, RAM banks `0/3/4/9..23`, and destination addresses).

Verification (2026-11-13): `make testcx16-memory-contract`, `make testcx16-cartridge`,
and `make testcx16` passed (`check_memory_contract.py` 19 asserts x 2 build dirs,
`check_cx16_cart.py` 20 assets, autonomous `-cart` and `-cartbin` cold-boot GIF
verification with an empty `-fsroot`, autonomous non-testbench/non-warp `-cart`
live 60 Hz VSYNC IRQ / `RDTIM` / `KEYHDL` / VERA PSG WAV playback & silencing +
keyboard flow verification (`P=$32`, `snd_timer=12->0`, `wav_peak=4088`),
interactive `CartBench` handoff (`I=0`, `$A80A=0`, `KEYHDL` chain), preloaded-bank
Fletcher-16 across all 16 banks, `cart_read` edge cases, empty-fsroot
missing-save `L)oad`, title/gameplay legal viewer reaching EOF (`legal_eof = $40`),
DL1/DL16/DL50 monster catalog, and bidirectional `THE.GAME` interchange with disk
`MORIA8.PRG`). Physical VDC/C128 layout rows: N/A.

## Phase 1 Port-Local Memory Unlocks (2026-11-14)

### Change Record (`docs/BEHAVIOR_CHANGE_PROTOCOL.md`)

```text
Problem and success criteria: Reclaim CX16 HiRAM Banks 5-8 (32 KB freed when HAL_PLATFORM_MONSTER_CATALOG superseded MONSTER.DB.1..4) and Banks 24-63 without churn in core/ or platforms/shared/; add .assert-guarded $00-preserving byte/block/cross-bank bounce helpers in fixed Low RAM < $9B00; keep Low-RAM headroom >= 400 B free on both disk and cart (< $9B00 and <= $9980 cart live-test floor); enforce the full 64-bank partition and helper/Low-RAM bounds in check_memory_contract.py (--selftest included) and exercise them in x16emu TestBench.
State being changed: Bank allocation constants (platforms/cx16/memory.s, legal.s), fixed Low-RAM multi-bank helpers (platforms/cx16/memory_bank.s), Bank 3 AuxData placement for key_map_petscii/key_map_cmd (platforms/cx16/input.s), shared resident trampolines/copy calls (platforms/cx16/main.s, storage_kernal.s, save_stream.s, cartridge_copy.s), static contract checker (platforms/cx16/check_memory_contract.py), and TestBench harness (platforms/cx16/harness_smoke.py).
Search scope and terms: rg across platforms/cx16/, core/, platforms/commodore/, and tools/ for CX16_BANK_*, Cx16AuxData, key_map_petscii, key_map_cmd, key_map_count, cx16_zp_scratch, title_str, ckev_code.
Relevant readers/writers found and known exclusions: Only platforms/cx16/input.s reads key_map_petscii/key_map_cmd (core/game_loop.s and core/dungeon_features.s only call petscii_to_command); save_write_map_banked shares cx16_zp_scratch with mmu_safe_map_read_ptr0 at $3F00 so save_write_map_banked uses stack phx/plx across mmu_safe_map_read_block; non-CX16 ports and core/ are untouched and excluded.
Initialization, reset and persistence points: entry_main runs cx16_preload_banks to load CX16.AUXDATA into Bank 3 before restart_entry/title_menu_loop/petscii_to_command; Banks 5-8 and 24-63 remain RAM initialized by callers when used; key_map_* is immutable read-only table data.
Affected production sequence through the changed transition: entry_main -> cx16_preload_banks -> title_load_and_draw -> hal_asset_load_title (calls cx16_bank_copy Bank 21 -> Bank 1 via $0700); gameplay/title input -> petscii_to_command (php; sei, saves/restores $00, reads key_map_* from Bank 3 via (addr & $1FFF) | $A000, restores $00; plp); save_game -> save_write_map_banked -> mmu_safe_map_read_block; OVL.SPELL trampolines -> tramp_spell_dispatch.
Contract decision or selected upstream oracle with source locations: Commander X16 512 KB minimum HiRAM bank layout and virtual-to-banked contract (docs/CX16_MEMORY_CONTRACT.md, docs/MEMORY_REDESIGN_PLAN.md §5, platforms/cx16/memory.s).
Intentional Moria8 deviations: key_map_petscii and key_map_cmd reside in Bank 3 AuxData rather than Low RAM; Banks 5-8 stay reserved for Phase 5 monster extensions / extended slots while HAL_PLATFORM_MONSTER_CATALOG is active. No gameplay semantics changed.
Input/intermediate widths, signedness, carry, range and overflow policy: cx16_bank_read_byte/write_byte take bank in 0..63 and (zp_ptr0),y in $A000-$BFFF; cx16_bank_read_block/write_block take X in 0..255 (0=256 bytes); cx16_bank_copy takes unsigned 16-bit byte count (A=lo, X=hi) bounded within single source/destination banks ($A000-$BFFF), clearing C on completion; per-chunk $0700 bounce runs under php; sei ... plp.
RNG reduction and bias, if applicable: N/A — memory layout, bank helpers, and static/TestBench contract checks introduce no RNG calls or range reductions.
Affected platforms, overlays, banks and owners: Commander X16 only; Disk MORIA8.PRG ($0801-$993B, 452 B free < $9B00), Cart MORIA8.PRG ($0801-$9951, 430 B free < $9B00, <= $9980 live-test floor), CX16.AUXDATA Bank 3 ($6000-$74FF, 2,816 B free), Bank 5 (CX16_BANK_CATALOG_EXT), Banks 6-8 (CX16_BANK_EXT_BASE..END), Banks 9-20 overlays, Bank 21 TITLE, Bank 22 MONSTER.CAT, Bank 23 LEGALUI (CX16_BANK_LEGAL), Banks 24-63 (CX16_BANK_WARM_BASE..END).
Required production-path tests: check_memory_contract.py (--selftest and disk+cart checks), diskcx16 (LICENSE + SOURCE-OFFER in build/moria8-cx16.zip), cartridgecx16 (check_cx16_cart.py), testcx16 (26 x16emu TestBench scenarios incl. bank_bounce_helpers and save_load/save_reboot_load), testcx16-cartridge (cold-boot, IRQ/WAV, preloaded bank Fletcher-16, bidirectional disk/cart save interchange).
Known behavior explicitly out of scope: Populating Bank 5 MONSTER.CAT extensions (Phase 5) or Banks 6-8 / 24-63 runtime payloads (Phases 2/4/5), and any changes to core/, platforms/shared/, or sibling ports.
Unresolved uncertainty and risk: None in Phase 1; callers of cx16_bank_copy must ensure source/destination slices stay within one 8 KB $A000-$BFFF bank and callers of cx16_bank_read/write_block stay within one 256-byte page window from Y.
```

Verification (2026-11-14):

* `make testcx16-memory-contract-selftest`: PASS (`check_memory_contract.py --selftest` 16 asserts, `check_cx16_cart.py --selftest`, `test_cartridge.py --selftest`).
* `make testcx16-memory-contract`: PASS (`check_memory_contract.py` 20 asserts x 2 build dirs covering `20/64` used / `44` free banks, `low_ram_free=452B` disk / `430B` cart, `auxdata_free=2816B`; `check_cx16_cart.py` 20 assets).
* `make diskcx16` & `make cartridgecx16`: PASS (`build/moria8-cx16.zip` 20 files incl. `LICENSE`/`SOURCE-OFFER`; `build/moria8-cx16.crt` 131,552 B, 101,418/131,072 B used, 29,654 B free).
* `make testcx16`: PASS (26/26 TestBench scenarios in `platforms/cx16/harness_smoke.py`, including `bank_bounce_helpers` 16/16 asserts verifying `cx16_bank_read_byte`/`write_byte`/`read_block`/`write_block`/`copy` across Banks 5/6/24/63 and Bank 3 `petscii_to_command` while Bank 9 stays active in `$00`, plus full `test_cartridge.py`).
* `make testcx16-cartridge`: PASS (`cartridge_test_live.s` `$9980` guard + cold-boot CRT/BIN, IRQ/WAV, Fletcher-16, legal viewer, monster catalog, and disk/cart save interchange). Physical VDC/C128 and other ports: N/A (CX16-only change).

## Phase 2 Cold Code Eviction (2026-11-14)

### Change Record (`docs/BEHAVIOR_CHANGE_PROTOCOL.md`)

```text
Problem and success criteria: Enable Wave 1 HOME_OVERLAY_SEPARATE on Commander X16 with OVL_HOME = 11 (OVL.HOME in Bank 19, shifting OVL_STORAGE = 12 -> Bank 20, OVL_TITLE = 13 -> Bank 21, TITLE -> Bank 22, MONSTER.CAT -> Bank 23, LEGALUI -> Bank 24, warm pool -> Banks 25-63), relieve OVL.TOWN, and evict cold/uncommon code from Low RAM Default (< $9B00) into HiRAM overlays so Default gains >= 1 KB free even on CX16_CARTRIDGE without leaving any overlay cramped.
State being changed: platforms/cx16/main.s (HOME_OVERLAY_SEPARATE, HOME/ITEM_SPAWN/ITEM_PICKUP/RE_EQUIP/WALL_TO_MUD/PLAYER_RUN_INITIALIZE/CX16_DETECT_MACHINE segment placements, tramp_gen_dispatch dedup, tramp_store_enter #STORE_HOME dispatch, $00-preserving tramp_disk_setup/run_initialize/re_equip_entry, cold boot & title loop moved to OVL.TITLE / OVL.STORAGE), hal/lifecycle_policy.s (hal_platform_overlay_count=13, HAL_PLATFORM_ITEM_PICKUP_OVERLAY), memory.s, cartridge_contract.s, storage_kernal.s, overlay_storage.s, config.s, Makefile, check_memory_contract.py (LOW_RAM_MIN_FREE=1500, OVL.HOME, Bank 25..63, --selftest), harness_smoke.py, test_cartridge.py, tools/make_cx16_cart.py, tools/check_cx16_cart.py.
Search scope and terms: rg across platforms/cx16/, core/, and tools/ for HOME_OVERLAY_SEPARATE, STORE_HOME, OVL_*, HAL_PLATFORM_ITEM_PICKUP_OVERLAY, ITEM_SPAWN_IN_GEN_OVERLAY, RE_EQUIP_SEGMENT_CUSTOM, WALL_TO_MUD_SEGMENT_CUSTOM, PLAYER_RUN_INITIALIZE_EXTERNAL, tramp_disk_setup, Bank 2[0-4], CART_ASSET_*.
Relevant readers/writers found and known exclusions: core/ui_home.s + ui_home_text.s moved to HomeOverlay (inv_add_carried stays resident since HAL_PLATFORM_INV_ADD_CARRIED_EXTERNAL is unset on CX16); tramp_store_enter dispatches #STORE_HOME to OVL_HOME and stores to OVL_TOWN; tramp_disk_setup preserves $00 so TitleOverlay callers return to Bank 21; non-CX16 ports, core/, platforms/shared/, and tools/check_hal_*.py / tools/report_memory_budgets.py are excluded and untouched.
Initialization, reset and persistence points: entry_main runs hal_platform_init_early -> cx16_preload_banks (Banks 3..4 & 9..23) -> generation_busy_install -> overlay_load #OVL_TITLE -> cx16_cold_boot_init (cx16_reset_session_state, detect_machine, platform_services_install_cx16) -> platform_services_assert_installed -> tier_init -> hal_sound_init -> rng_seed -> title_enter_menu (jumps to OVL_TITLE:title_enter_menu_ovl); cartridge boot directory at Bank 32 $C100-$C1FF carries 21 descriptors (0..20).
Affected production sequence through the changed transition: try_store_entry -> tramp_store_enter (#STORE_HOME -> OVL_HOME:home_enter, else OVL_TOWN:store_enter); title_enter_menu -> OVL_TITLE:title_enter_menu_ovl -> title_menu_loop ('D' -> tramp_disk_setup saves/restores $00 across OVL_STORAGE; 'L' -> tramp_title_load_game -> OVL_STORAGE:title_load_game_ovl); cmd_pickup -> tramp_item_pickup -> OVL_ITEMS:item_pickup; cmd_run -> run_initialize -> OVL_MODAL:run_initialize_impl; recalc_stats/equip -> re_equip_entry -> OVL_MODAL:re_equip; dungeon gen/chest -> OVL_GEN:item_spawn_level_gen; spell -> OVL_SPELL:eff_wall_to_mud.
Contract decision or selected upstream oracle with source locations: Standardized Phase 2 14-ID overlay layout (OVL_HOME = 11, OVL_STORAGE = 12, OVL_TITLE = 13) per docs/MEMORY_REDESIGN_PLAN.md §4.2, §5, §6 and Wave 1 #181 notes; no VMS/Umoria gameplay semantics changed.
Intentional Moria8 deviations: No gameplay or string changes; cold boot/title/menu/item-spawn/pickup/re-equip/wall-to-mud/run-init execute from preloaded HiRAM overlay banks via $00-preserving resident trampolines.
Input/intermediate widths, signedness, carry, range and overflow policy: run_initialize saves/restores $00 preserving C (run_initialize_impl returns sec); re_equip_entry saves/restores $00 preserving A and N/Z (tax/txa); tramp_item_pickup clears C when overlay load fails; tramp_disk_setup saves/restores $00 preserving C; cartridge directory size = 21 * 8 = 168 B <= 256 B ($C100-$C1FF).
RNG reduction and bias, if applicable: N/A — eviction preserves all RNG call sequences and item/monster tables unchanged.
Affected platforms, overlays, banks and owners: Commander X16 only. Disk Default $0801-$93FA (35,834 B used, 1,797 B free < $9B00; +1,345 B vs Phase 1 452 B); Cart Default $0801-$9410 (35,856 B used, 1,775 B free < $9B00, 1,391 B free <= $9980; +1,345 B vs Phase 1 430 B). OVL.HOME (Bank 19) 1,181 B (7,011 B free); OVL.TOWN (Bank 10) 4,325 B (3,867 B free); OVL.GEN 5,234 B (2,958 B free); OVL.ITEMS 5,829 B (2,363 B free); OVL.SPELL 5,945 B (2,247 B free); OVL.MODAL 3,243 B (4,949 B free); OVL.STORAGE 3,344 B (4,848 B free); OVL.TITLE 544 B (7,648 B free); OVL.START 4,213 B; OVL.DEATH 3,345 B; OVL.HELP 2,273 B; OVL.UI 2,483 B; OVL.CHEST 2,520 B. Used HiRAM banks: 21/64 (43 free: Banks 5-8 & 25-63 = 344 KB).
Required production-path tests: make -C platforms/cx16 build disk cartridge test-memory-contract test-memory-contract-selftest, check_cx16_cart.py --selftest, make check-hal-boundaries check-6502-lint, and x16emu ./tools/isolated.sh make -C platforms/cx16 test-runtime test-cartridge (26 runtime scenarios incl. Home deposit/retrieve & Town store in wizard_flow and disk_setup + full cartridge suite).
Known behavior explicitly out of scope: Phase 3/4/5 optimizations and any edits to core/, platforms/shared/, or sibling ports.
Unresolved uncertainty and risk: None in Phase 2; eff_wall_to_mud inside OVL.SPELL is only verified indirectly via overlay/cast suites (no dedicated wall-to-mud spell scenario in harness_smoke.py).
```

Verification (2026-11-14):

* `PYTHONDONTWRITEBYTECODE=1 make -C platforms/cx16 build disk cartridge test-memory-contract test-memory-contract-selftest`: PASS (`check_memory_contract.py` 21 asserts x 2 build dirs: `low_ram_free=1797B` disk / `1775B` cart, `auxdata_free=2816B`, `21/64 used` / `43 free`; `check_cx16_cart.py` 21 assets verified in `build/moria8-cx16.crt` `131,552 B`, `101,776/131,072 B` used / `29,296 B` free; `build/moria8-cx16.zip` `21` files incl. `OVL.HOME`, `LICENSE`, `SOURCE-OFFER`; all three `--selftest` gates PASS).
* `PYTHONDONTWRITEBYTECODE=1 python3 -B tools/check_cx16_cart.py --selftest`: PASS.
* `PYTHONDONTWRITEBYTECODE=1 make check-hal-boundaries check-6502-lint`: PASS (all HAL export/boundary/manifest checks PASS; `check_6502_lint.py` 0 errors across 386 files).
* `./tools/isolated.sh make -C platforms/cx16 test-runtime test-cartridge`: PASS (`26/26` TestBench scenarios incl. `wizard_flow` Home deposit/retrieve + General Store and `disk_setup`; `test_cartridge.py: ALL CX16 CARTRIDGE SCENARIOS PASSED` incl. Bank 19 `OVL.HOME` Fletcher-16 and Bank 24 `LEGALUI`). Physical VDC/C128 and other ports: N/A (CX16-only change).

## Phase 3 Generated Trampolines & Identify Selector Restoration (2026-11-14)

Change Record (Behavior Change Protocol):

* Problem and success criteria: Migrate Commander X16 generated resident trampolines (`tools/trampoline_manifest.py` `CX16_ENTRIES`: `67` generated, `16` custom) to `#import "../../build/trampolines/cx16_trampolines.inc"` in `.segment Default` (`<= $9AFF`), generate `build/trampolines/cx16_trampolines.inc` from `platforms/cx16/Makefile`, preserve all `16` custom stubs and non-`tramp_*` helpers, keep disk/cart `MORIA8.PRG` `<= $9B00` (and cart `<= $9980` live test ceiling) with `>= 1,500 B` free, and verify Wave 1's Mage Spell #20 (`Identify`) `'?'`-selector `OVL_SPELL` restoration (`ovl_spell_restore` in `tramp_spell_execute_selected`) in `x16emu`.
* State being changed: `platforms/cx16/Makefile` (`TRAMPOLINES_INC` rule + `CX16_MAIN_STAMP`/`CX16_CART_STAMP` prerequisites), `platforms/cx16/main.s` (remove `67` generated `tramp_*` definitions, `#import "../../build/trampolines/cx16_trampolines.inc"` in `Default`), and `platforms/cx16/harness_smoke.py` (`scenario_mage_identify_selector` added to `SCENARIO_FUNCS`).
* Search scope and terms: `CX16_ENTRIES` in `tools/trampoline_manifest.py`, generated `build/trampolines/cx16_trampolines.inc`, `tramp_*` definitions across `platforms/cx16/main.s` and `platforms/cx16/legal.s`, `Identify` spell tables/handlers in `core/spell_data.s`, `core/spell_class_data.s`, `core/spell_effects.s`, `core/ui_inventory.s`, and `platforms/cx16/harness_smoke.py`.
* Relevant readers/writers found and known exclusions: Only `platforms/cx16/main.s` imports `cx16_trampolines.inc` in `Default`; `platforms/cx16/legal.s` keeps custom `tramp_ui_legal_display`; `platforms/cx16/hal/lifecycle_policy.s` keeps `HAL_PLATFORM_AUX_PERSISTENT_DATA` defined and `hal_platform_item_action_key_restores_bank = 0`; `core/`, `tools/`, and sibling ports are untouched and excluded.
* Initialization, reset and persistence points: `TRAMPOLINES_INC` regenerates deterministically via `tools/gen_trampolines.py --port cx16`; `piw_return_overlay` initializes to `OVL_NONE` (`$FF`) at boot and resets to `OVL_NONE` on `tramp_restore_spell_overlay`; no persistent save format changes.
* Affected production sequence through the changed transition: All `67` migrated overlay/direct trampolines dispatch through `build/trampolines/cx16_trampolines.inc` in `Default`; for Mage Spell #20 (`Identify`) `'?'`-selector: `main_loop` -> `tramp_player_cast_spell` (`OVL.SPELL`) -> `tramp_spell_execute_selected` (`ovl_spell_restore` in `Default`) -> `eff_identify_prompt` (`OVL.SPELL`) -> `tramp_select_filtered_inv` (`OVL.ITEMS`, sets `piw_return_overlay = #OVL_ITEMS`) -> `show_inv_and_select` (`Default`) -> `'?'` -> `tramp_ui_inv_select_display` (`OVL.HELP`, evicting `OVL.SPELL` & `OVL.ITEMS`) -> `piw_return_overlay` reload of `OVL.ITEMS` -> `tramp_restore_spell_overlay` (`OVL.SPELL`, clears `piw_return_overlay`) -> `eff_identify_prompt` -> `tramp_spell_execute_selected` tail `jmp tramp_restore_spell_overlay` (`OVL.SPELL`) -> `player_cast_spell` -> `main_loop`.
* Contract decision or selected upstream oracle with source locations: `docs/CX16_MEMORY_CONTRACT.md`, `tools/trampoline_manifest.py` (`CX16_ENTRIES`), `build/trampolines/cx16_trampolines.inc` (`ovl_spell_restore` + `ay_dispatch` `jmp` stubs), `core/spell_effects.s` (`eff_identify_prompt`), and `core/player_item_select.s`.
* Intentional Moria8 deviations: No gameplay or string changes; `cx16_trampolines.inc` uses `jmp` for `ay_dispatch` stubs so placement anywhere in `Default <= $9AFF` cannot hit the 65C02 `bra` `+/-127 B` limit; `ovl_spell_restore` restores `OVL_SPELL` around `spell_execute_selected`.
* Input/intermediate widths, signedness, carry, range and overflow policy: All `cx16_trampolines.inc` stubs preserve caller carry/register contracts (`tramp_restore_spell_overlay` preserves `P`/`A`/`X` via `php; pha; txa; pha ...`, `brk` on unexpected `overlay_load` failure); `piw_return_overlay` holds `OVL_NONE` (`$FF`) or overlay ID `0..12`.
* RNG reduction and bias, if applicable: N/A — trampoline code-generation migration and `ovl_spell_restore` wrapper leave all RNG sequences unchanged.
* Affected platforms, overlays, banks and owners: Commander X16 only. Disk `Default` (`MORIA8.PRG`): `$0801-$93F7` (`35,831 B` / `37,631 B`, `1,800 B` free `< $9B00`); Cart `Default` (`MORIA8.PRG`): `$0801-$940D` (`35,853 B` / `37,631 B`, `1,778 B` free `< $9B00`, `1,394 B` free `<= $9980`). Overlays (`$A000-$BFFF` window): `OVL.ITEMS` `$A000-$B6C9` (`5,834 B`, `2,358 B` free), `OVL.SPELL` `$A000-$B738` (`5,945 B`, `2,247 B` free), `OVL.START` `$A000-$B074` (`4,213 B`, `3,979 B` free), `OVL.TOWN` `$A000-$B0E4` (`4,325 B`, `3,867 B` free), `OVL.DEATH` `$A000-$AD10` (`3,345 B`, `4,847 B` free), `OVL.MODAL` `$A000-$ACAA` (`3,243 B`, `4,949 B` free), `OVL.GEN` `$A000-$B471` (`5,234 B`, `2,958 B` free), `OVL.HELP` `$A000-$A8E0` (`2,273 B`, `5,919 B` free), `OVL.UI` `$A000-$A9B2` (`2,483 B`, `5,709 B` free), `OVL.CHEST` `$A000-$A9D7` (`2,520 B`, `5,672 B` free), `OVL.HOME` `$A000-$A49C` (`1,181 B`, `7,011 B` free), `OVL.STORAGE` `$A000-$AD0F` (`3,344 B`, `4,848 B` free), `OVL.TITLE` `$A000-$A21F` (`544 B`, `7,648 B` free). `21/64` HiRAM banks used (`43` free: Banks 5-8 & 25-63).
* Required production-path tests: `make -C platforms/cx16 build disk cartridge test-memory-contract test-memory-contract-selftest`, `python3 -B tools/check_overlay_calls.py --port cx16 --check-sym`, `python3 -B tools/check_overlay_calls.py --selftest`, `python3 -B tools/gen_trampolines.py --selftest`, `python3 -B tools/check_hal_boundaries.py`, `python3 -B tools/check_6502_lint.py`, and `./tools/isolated.sh make testcx16` (`27/27` `harness_smoke.py` scenarios incl. `mage_identify_selector` + `test_cartridge.py`).
* Known behavior explicitly out of scope: Sibling port Wave 2 migrations, global multi-port `tools/gen_trampolines.py --check` before all 7 ports finish Wave 2, and any edits to `core/`, `tools/`, or `platforms/commodore/`.
* Unresolved uncertainty and risk: None on CX16.

Verification (2026-11-14):

* `PYTHONDONTWRITEBYTECODE=1 make -C platforms/cx16 build disk cartridge test-memory-contract test-memory-contract-selftest`: PASS (`388` KickAssembler asserts `0` failed on disk & cart builds; `check_memory_contract.py` `21 asserts 0 failures` on disk `low_ram_free=1800B` and cart `low_ram_free=1778B`, `auxdata_free=2816B`, `21/64 used` / `43 free`; `check_cx16_cart.py` PASS `21` assets verified in `build/moria8-cx16.crt` [`131,552 B`], `101,778/131,072 B` used [`29,294 B` free]; `check_memory_contract.py --selftest` `16 asserts 0 failures`; `check_cx16_cart.py --selftest` PASS; `test_cartridge.py --selftest` PASS).
* `PYTHONDONTWRITEBYTECODE=1 python3 -B tools/check_overlay_calls.py --port cx16 --check-sym`: PASS (`1 port(s), 0 cross-overlay violations`); `--selftest` PASS.
* `PYTHONDONTWRITEBYTECODE=1 python3 -B tools/gen_trampolines.py --selftest`: PASS (`all 7 ports, 45 template kinds, 6 fixture assertions`).
* `PYTHONDONTWRITEBYTECODE=1 python3 -B tools/check_hal_boundaries.py`: PASS (`0 baseline entries`); `PYTHONDONTWRITEBYTECODE=1 python3 -B tools/check_6502_lint.py`: PASS (`Scanned 386 files: 0 error(s)`).
* `PYTHONDONTWRITEBYTECODE=1 ./tools/isolated.sh make testcx16`: PASS (`27/27` `harness_smoke.py` scenarios / `233` asserts `0` failures, incl. `mage_identify_selector` [`7` asserts `0` failures]; `test_cartridge.py: ALL CX16 CARTRIDGE SCENARIOS PASSED`). Physical VDC/C128 and other ports: N/A (CX16-only change).

## Phase 4 `ITEM.CAT` HiRAM Bank 6 Preload & Save Format V2 (2026-11-15)

- **HiRAM Bank 6 (`CX16_BANK_ITEM_CAT = 6`):** Preloads `'ITM2'` `ITEM.CAT` (`7,573 / 8,192 B`, `$A000-$BD94`, **`619 B` free**) at boot on both disk (`cx16_preload_banks`) and cartridge (`CART_ASSET_ITEM_CAT`, 22nd descriptor in Bank 32 `$C100-$C1FF`). `22/64` HiRAM banks are used and **`42/64` (`336 KB`)** remain free (`Bank 5` `CX16_BANK_CATALOG_EXT`, `Banks 7-8`, `Banks 25-63`).
- **Low RAM & Bank 3 `CX16.AUXDATA`:** Disk `MORIA8.PRG` spans `$0801-$9346` (`35,654 / 37,631 B`, **`1,977 B` free** `< $9B00`); Cart `MORIA8.PRG` spans `$0801-$9344` (`35,652 / 37,631 B`, **`1,979 B` free** `< $9B00`, **`1,595 B` free** `<= $9980` `CartLiveHelperLimit`). Bank 3 `CX16.AUXDATA` (`$6000-$76E1`, `5,858 / 8,192 B`, **`2,334 B` free**) hosts `recall[279]` (`1,116 B`), `si_meta_hi[128]`, `id_known_bits[47]`, and `potion_shuffle..staff_shuffle` (`174 B`).
- **Overlays & Shipping Media:** All 13 overlays fit `$A000-$BFFF` (`OVL.ITEMS` `6,338 B` / `1,854 B` free, `OVL.SPELL` `5,965 B` / `2,227 B` free, `OVL.CHEST` `5,358 B` / `2,834 B` free, `OVL.HOME` `5,258 B` / `2,934 B` free, `OVL.START` `4,117 B`, `OVL.TOWN` `3,926 B`, `OVL.GEN` `3,718 B`, `OVL.DEATH` `3,354 B`, `OVL.STORAGE` `3,186 B`, `OVL.MODAL` `2,772 B`, `OVL.UI` `2,542 B`, `OVL.HELP` `2,273 B`, `OVL.TITLE` `630 B`). `build/moria8-cx16.crt` packs `22` assets (`116,097 B` payload, `116,609 / 131,072 B` used, **`14,463 B` free**); `build/moria8-cx16.zip` packages `22` files (`116,150 B` uncompressed).

## Phase 5 Split `MONSTER.CAT` (Bank 23) + `MONSTER.EXT` (Bank 5) & Cold Evictions (2026-11-16)

### 1. Summary of Phase 5 Memory & Bank Layout

- **Split Monster Catalog Across Bank 23 (`MONSTER.CAT`) + Bank 5 (`MONSTER.EXT`):**
  - **HiRAM Bank 23 (`CX16_BANK_CATALOG = 23`, shifted from legacy Bank 22 in Phase 2):** Preloads `MONSTER.CAT` (`$A000-$B758`, `5,976 / 8,192 B`, **`2,216 B` free**): the `21` core SoA engine fields × `279` creatures (`catalog_fields.s`), plus `catalog_index.s` (`cat_level_raw[41]`, `cat_level_playable[41]`, `cat_available` with `279/279` playable, and Phase 5's `cat_undead[35]` undead summon bitmap).
  - **HiRAM Bank 5 (`CX16_BANK_CATALOG_EXT = 5`):** Preloads `MONSTER.EXT` (`$A000-$A8B8`, `2,232 / 8,192 B`, **`5,960 B` free**): `279 × 8 B` contiguous row-major extended species records (`cat_atk2_*`, `cat_atk3_*`, `cat_spell_flags2`, `cat_cdefense`) on both disk (`cx16_preload_banks`) and 128 KB cartridge (`CART_ASSET_CATALOG_EXT`, 23rd descriptor in Bank 32 `$C100-$C1FF`).
  - `catalog_fetch_ext` (`platforms/cx16/monster_catalog_bank.s`, asserted `<= $9980` in fixed Low RAM) maps Bank 5 under `php; sei`, copies `8 B` from `$A000 + id * 8` into `cat_ext_record[0..7]`, and restores `CX16_RAM_BANK_REG` (`$00`), flags, and all ZP slots. **`23 / 64` HiRAM banks are used and `41 / 64` (`328 KB`) remain free** (`Banks 7–8` and `Banks 25–63`).
- **Wave 5.2 Cold Evictions Preserving `LOW_RAM_MIN_FREE = 1500`:**
  - Evicts cold routines out of unified Low RAM `Default` (`MORIA8.PRG`): `PLAYER_CHARGEN_EXTERNAL` (`player_chargen_cold.s` -> `OVL.START`), `UI_CHAR_BG_EXTERNAL` (`player_bg_draw_cold.s` -> `OVL.UI`), `TRAP_TRIGGER_EXTERNAL` (`trap_trigger_cold.s` -> `OVL.CHEST`), `STARTING_KIT_EXTERNAL` (`starting_kit_cold.s` -> `OVL.TITLE`), `DOOR_OPEN_CLOSE_EXTERNAL` + `ITEM_DROP_EXTERNAL` + `mae_cold_body` (`-> OVL.HELP`), and 80-col `ui_recall.s` tables (`0 B` in `Default`, inside `OVL.MODAL`).
  - Measured Low RAM (`42f8f7e7`): Disk `MORIA8.PRG` `$0801-$9368` (`35,687 / 37,631 B`, **`1,944 B` free** `< $9B00`); Cart `MORIA8.PRG` `$0801-$934C` (`35,659 / 37,631 B`, **`1,972 B` free** `< $9B00`, **`1,588 B` free** `<= $9980` `CartLiveHelperLimit` — comfortably above `LOW_RAM_MIN_FREE = 1500`!).
  - Overlays & Media: Tightest `$A000-$BFFF` overlay is `OVL.ITEMS` (`7,200 / 8,192 B`, **`992 B` free**); `.zip` packages `23` files (`121,055 B` uncompressed, `LICENSE` & `SOURCE-OFFER` included); `.crt` packs `23` assets (`121,486 / 131,072 B` used, **`9,586 B` free**).

### 2. Change Record (`docs/BEHAVIOR_CHANGE_PROTOCOL.md`)

```text
Problem and success criteria: Wire Phase 5's 29-field cr_* buffers (+320 B), 279/279 playable catalog, cat_undead[35], 2,232 B MONSTER.EXT, 15-field '/' recall, 4-attack loop, 19 ADESC_* verbs, 24 ATK_* effects, 5 MSF2_* spells, and CD_*/CM2_* behaviors on Commander X16 disk (.zip) and 128 KB cartridge (.crt) while keeping LOW_RAM_MIN_FREE = 1500 (< $9B00 and <= $9980 cart live-test ceiling) intact.
State being changed: platforms/cx16/{main.s,memory.s,monster_catalog_bank.s,storage_kernal.s,cartridge_contract.s,Makefile,check_memory_contract.py} & tools/{make_cx16_cart.py,check_cx16_cart.py} — preload MONSTER.EXT into Bank 5 (CX16_BANK_CATALOG_EXT), add $00-preserving catalog_fetch_ext <= $9980, add cat_undead[35] to Bank 23 MONSTER.CAT, evict Wave 5.2 cold modules + mae_cold_body into HiRAM overlays, and register 23rd cartridge asset.
Search scope and terms: rg across platforms/cx16/, core/, and tools/ for CX16_BANK_CATALOG_EXT, catalog_fetch_ext, cat_ext_record, LOW_RAM_MIN_FREE, UI_CHAR_BG_EXTERNAL, TRAP_TRIGGER_EXTERNAL, STARTING_KIT_EXTERNAL, mae_cold_body.
Relevant readers/writers found and known exclusions: catalog_fetch_ext saves/restores $00 under php; sei using self-modified absolute address $A000 + id * 8 (zero ZP touched) so overlay callers in Banks 9..21 never lose their mapped bank; cat_ext_record and catalog_fetch_ext_end are asserted <= $9980 for cartridge_test_live.s compatibility.
Initialization, reset and persistence points: cx16_preload_banks loads MONSTER.EXT into Bank 5 at boot alongside Bank 23 MONSTER.CAT; Save Format V2 (SAVE_VERSION = $20, 17,161 B) unchanged.
Affected production sequence through the changed transition: entry_main -> cx16_preload_banks (loads Bank 5 MONSTER.EXT & Bank 23 MONSTER.CAT) -> gameplay cat_fetch / catalog_recall_match_and_fill -> catalog_fetch_ext (maps Bank 5, copies 8 B -> cat_ext_record, restores caller $00) -> '/' recall dispatches OVL.MODAL -> ui_recall_display.
Contract decision or selected upstream oracle with source locations: Commander X16 64-bank HiRAM partition (platforms/cx16/memory.s, check_memory_contract.py) and VMS Moria 4.8 279-creature catalog.
Intentional Moria8 deviations: None to VMS gameplay; splitting core 21 fields + index in Bank 23 (5,976 B) and 8 extended fields in Bank 5 (2,232 B) keeps every segment inside a single 8 KB $A000-$BFFF bank without cross-bank straddling.
Input/intermediate widths, signedness, carry, range and overflow policy: 9-bit catalog ID (0..278) * 8 = 0..2224 ORed with $A000 ($A000..$A8B7 <= $BFFF); 23 * 8 = 184 B <= 256 B cartridge directory ($C100-$C1FF).
RNG reduction and bias, if applicable: N/A for CX16 bank layout and cold evictions.
Affected platforms, overlays, banks and owners: Commander X16 Disk MORIA8.PRG ($0801-$9368, 1,944 B free < $9B00), Cart MORIA8.PRG ($0801-$934C, 1,972 B free < $9B00, 1,588 B <= $9980), Bank 5 MONSTER.EXT (2,232 B), Bank 23 MONSTER.CAT (5,976 B), 23/64 HiRAM banks used (41 free = 328 KB), .crt (9,586 B free).
Required production-path tests: make testcx16-memory-contract, tools/report_memory_budgets.py --port cx16, make testcx16, make testcx16-cartridge, and make playtest-gate.
Known behavior explicitly out of scope: Banks 7-8 and 25-63 remain free reserve (328 KB).
Unresolved uncertainty and risk: moria8-cx16.crt has 9,586 B free out of 128 KB; enforced fail-closed by make_cx16_cart.py and check_cx16_cart.py.
```

Verification (2026-11-16):

* `make testcx16-memory-contract` & `--selftest`: PASS (`23/64` banks used / `41` free, `low_ram_free = 1,944 B` disk / `1,972 B` cart `>= 1,500 B`, `23` `.crt` assets verified).
* `make testcx16` & `make testcx16-cartridge` + `make playtest-gate`: PASS (`0` findings).


