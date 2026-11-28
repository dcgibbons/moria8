# C128 Memory And Banking Contract

Load this document for C128 address placement, MMU or `$01` banking, overlays,
runtime-loaded/copied code, caches, KERNAL transitions, or physical VDC access.
Do not load it for shared gameplay changes that neither alter payload layout nor
touch C128-specific memory services.

`platforms/commodore/c128/memory128.s` is the executable runtime ownership
authority. `platforms/commodore/c128/boot128.s` is the executable authority for
boot-copy modes, physical copy/scrub bounds, and staging transitions. This
document summarizes both. Address changes must update the owning source and its
assertions, not only this table.

## Runtime Modes

| Mode | Configuration | Contract |
| --- | --- | --- |
| Startup/KERNAL | `MMU_NORMAL=$0e` | Bank 0, BASIC removed, system ROM and I/O visible |
| Operational Bank 0 | `MMU_ALL_RAM=$3e` | Bank 0 RAM, I/O visible; KERNAL reached through RAM stubs |
| Bank 1 data/cache | `MMU_RAM_BANK1=$7e` | Bank 1 RAM, I/O visible |
| Bank 1 no-I/O data / boot source | `MMU_RAM_BANK1_NOIO=$7f` | Bank 1 RAM with RAM, not I/O, visible at `$d000-$dfff` (boot staging and `< $4000` `SEI` common-RAM helpers `mmu_common_b1_noio_*` with `$d506=$0d`) |
| Bank 2 data/cache | `MMU_RAM_BANK2=$be` | Bank 2 RAM, I/O visible at `$d000-$dfff` (256KB MMU expansion Bank 2 cache via `mmu_common_xbank_*_page` and `mmu_common_bank_*_ptr1`) |
| Bank 3 probe | `MMU_RAM_BANK3=$fe` | Bank 3 RAM, I/O visible at `$d000-$dfff` (`c128_detect_256k` 4-bank probe target) |
| Boot copy destination | `MMU_ALL_RAM_NOIO=$3f` | Bank 0 RAM with RAM, not I/O, visible at `$d000-$dfff` |

During normal runtime, bit 2 of `$01` stays set. MMU configuration bit 0 also
controls whether I/O or RAM is exposed at `$d000-$dfff`; boot copy and the
bottom-common `< $4000` `SEI` Bank 1 data helpers (`mmu_common_b1_noio_read/write_ptr0/1`,
`C128M-014`) deliberately use `$7f` while preserving `$d506=$0d` (4 KB bottom/top
common RAM + CPU vectors) and restoring `MMU_ALL_RAM` (`$3e`) before `plp`.
Access under KERNAL ROM or `$d000-$dfff` I/O requires the established
interrupt-safe helpers; raw bank changes must not bypass their save/restore
discipline.

## Bank 1 Ownership Snapshot

This is a descriptive snapshot checked 2026-07-09. `memory128.s` constants and
overlap assertions are the executable authority; never edit this table alone.

| Span | Owner/lifetime |
| --- | --- |
| `$0000-$0fff` | common RAM; shared, not cache-safe |
| `$1000-$1fff` | UI overlay cache |
| `$2000-$2fff` | HELP overlay cache |
| `$3000-$3fff` | ITEMS overlay cache |
| `$4000-$730b` | active 198x66 live map span (`13,068 B` — full `MAP_SIZE` on C128; also used at cold boot before title/dungeon generation as the transient `7,478 B` `$4000-$5d35` staging buffer for streaming `ITEM.CAT` into 16 KB VDC RAM under `C128M-015`) |
| `$730c-$73ff` | reserved unowned gap between map and DB regions (`244 B`) |
| `$7400-$7a5f` | DB/data region (`Bank1DB`, `1,632 B`, `C128M-013`/`C128M-015`): `recall[279]` (`1,116 B` at `$7400-$785b`) + `zp_save_buf` (`142 B` at `$785c-$78e9`, `bank1_db_end = $78ea`, `374 B` free to `$7a5f`), accessed through `mmu_safe_db_read/write_ptr0/1`. Replaces the retired `128.names` payload (`ITEM.CAT` serves all `361` VMS item templates and `55` ego names directly from 16 KB VDC RAM on disk builds or MD128 cartridge ROM on `.crt` builds; C128 does not use REU, `reu_present = 0`) |
| `$7a60-$9567` | the monster catalog (C128M-007): `$7a60-$7e5f` the name pool, 32 species slots x 32 B written at species fetch; `$7e60-$9542` `128.cat`, the catalog's 21 fields x 279 creatures, loaded at boot; 37 B spare. Until 2026-11-02 the tier cache, 6920 bytes |
| `$9568-$97ff` | title marker/data cache (663 data bytes; the title art needs 593-624) |
| `$9800-$9cff` | MODAL small-overlay cache (`BANK1_OVERLAY_MODAL`, `5` pages = `1,280 B`; caches `ModalMiscOverlay` `ovl.modal` ID `9`, `$e000-$e473` = `1,139 B` code / `1,141 B` PRG incl. 2 B header, `141 B` free, including `winner_apply_retirement_bonus_storage`) |
| `$9d00-$9fff` | DISARM small-overlay cache |
| `$a000-$afff` | `128.cnm`, the catalog's Huffman-coded names (tree, pointers, bitstreams; 3380 B), loaded at boot (C128M-007). Until 2026-11-02 the STARTUP overlay cache: STARTUP now loads from disk |
| `$b000-$bfff` | TOWN overlay cache |
| `$c000-$cfff` | DEATH overlay cache (`OVL_DEATH` remains cached in Bank 1) |
| `$d000-$dfff` | Bank 1 High Data Window (`4,096 B`, `C128M-014`): `$d000-$d8b7` `128.cex` (`2,232 B`, `279 x 8 B` Phase 5 extended monster catalog rows, loaded at boot from `128.CEX` / `CART_ASSET_CEX`), `$d8b8-$dcb7` `BANK1_STORE_INV_RESERVED` (`1,024 B` reserved), `$dcb8-$df37` `msg_history` (`640 B`, `8 x 80 B` message ring buffer), and `$df38-$dfff` (`200 B` free); accessed strictly via bottom-common `< $4000` `SEI` + `MMU_RAM_BANK1_NOIO ($7f)` helpers (`mmu_common_b1_noio_read/write_ptr0/1`) |
| `$e000-$efff` | DUNGEON overlay cache |
| `$f000-$feff` | runtime top-common view shared with Bank 0; physical Bank 1 `$f000-$fd3a` owns the read-only Huffman corpus, exposed only by the atomic Huffman helpers |
| `$fffa-$fffb` | physical Bank 1 NMI vector bridge used only during transient Huffman reads with top common disabled |

### Bank 2 Ownership Snapshot (256KB MMU Expansion, Disk Builds, `MMU_RAM_BANK2 = $be`)

When `c128_detect_256k` detects 4 independent 64 KB MMU RAM banks (`c128_ram_256k = 1`, `C128M-018`), disk builds preload cold overlays and modal/legal payloads into physical Bank 2 (`memory128.s` `BANK2_*` constants and non-overlap `.assert`s; I/O stays visible at `$d000-$dfff` under `$be`):

| Span | Size | Owner/lifetime |
| --- | --- | --- |
| `$0000-$0fff` | `4,096 B` | Bottom common RAM shared with Bank 0 (`$d506=$0d`) |
| `$1000-$1fff` | `4,096 B` | `OVL_STARTUP` (`128.START`, ID `1`) cache slot |
| `$2000-$2fff` | `4,096 B` | `OVL_CHEST` (`128.CHEST`, ID `10`) cache slot |
| `$3000-$3fff` | `4,096 B` | `OVL_HOME` (`128.HOME`, ID `11`) cache slot |
| `$4000-$4fff` | `4,096 B` | `OVL_STORAGE` (`128.STORAGE`, ID `12`) cache slot |
| `$5000-$59ff` | `2,560 B` | `LEGALUI` (`BANK2_LEGALUI_PAGES = $0a` pages covering `$e000-$e9ff`, strictly below `legal_zp_save = $ee00`; tracked by `C128_BANK2_LEGALUI_BIT`) |
| `$5a00-$5fff` | `1,536 B` | Reserve above `LEGALUI` |
| `$6000-$80ff` | `8,448 B` | `128.PLAY` (`BANK2_PLAY_PAGES = $21` pages = full `$af00-$cfff` modal window; tracked by `C128_BANK2_PLAY_BIT`) |
| `$8100-$92ff` | `4,608 B` | `128.PERSIST` (`BANK2_PERSIST_PAGES = $12` pages covering `$af00-$c0ff`, strictly below `128.PLAY` live state; tracked by `C128_BANK2_PERSIST_BIT`) |
| `$9300-$cfff` | `15,616 B` | Free Bank 2 RAM |
| `$d000-$dfff` | `4,096 B` | I/O window visible under `MMU_RAM_BANK2 = $be` |
| `$e000-$efff` | `4,096 B` | Free Bank 2 RAM (includes `$e000` hardware probe address) |
| `$f000-$ffff` | `4,096 B` | Top common RAM shared with Bank 0 (`$d506=$0d`) |

The staged PRG payload begins at `$1c01`, and the boot page copier physically reads
and scrubs Bank 1 `$1c00-$feff`, including RAM under `$d000-$dfff` while a
no-I/O mode is selected. Post-boot (`c128_load_core_residents` / `msg_init`),
`128.cex` (`$d000-$d8b7`) is loaded into Bank 1 `$d000` and `msg_history`
(`$dcb8-$df37`) is initialized in Bank 1; all runtime reads/writes to
`$d000-$dfff` execute exclusively inside bottom-common `< $4000` (`$0c06+`)
under `sei` + `MMU_RAM_BANK1_NOIO ($7f)` (`C128M-014`). Cache validity cannot be
assumed until the relevant cache has been repopulated and marked valid.

Important Bank 0 ownership includes the consolidated resident image
(`moria128.prg`, `Default` linked `$1c01..<$af00`, absorbing the former
`128.world`, `128.item`, `128.select`, and `128.diskio` sub-PRGs under
`C128M-011` and keeping the modal footer `press_key_str`, `slain_str`, and
cartridge reader `cart_read`/`cart_desc_buf < $8000` resident), `$af00-$cfff`
(`128.persist` / `128.play`), floor items at `$1a00-$1aff`, runtime scratch at
`$1b00-$1bff`, the overlay window at `$e000-$efff` (hosting `ovl.modal` ID `9`
`ModalMiscOverlay` `$e000-$e473` [`1,139 B` payload / `1,141 B` PRG incl. 2 B header,
`141 B` free in `1,280 B` `BANK1_OVERLAY_MODAL`] with
`winner_apply_retirement_bonus_storage`, and uncached `HomeOverlay` ID `11`
`ovl.home` `$e000-$efcd` [`4,045 B`, `51 B` free]), and reloadable banked
code at `$f000` below `$ff00`. `main.s` and `cartridge_copy.s` assertions are
authoritative for resident bounds and the `< $8000` cartridge-bank-safe
boundary (`item_pickup`, `run_initialize`, `hal_item_cat_read_byte`, and
`vdc_item_cat_map_addr` all reside in Bank 0 `Default < $af00` under `C128M-015`).

## 16 KB Physical VDC RAM Ownership Snapshot

`memory128.s` (`VDC_*` constants and overlap `.assert`s) and `dungeon_render_vdc.s`
(`RVSD_SCRATCH_*` `.assert`s) are the executable authority for physical MOS 8563/8568
16 KB VDC RAM (`$0000-$3fff`).

| VDC Span | Size | Owner/lifetime |
| --- | --- | --- |
| `$0000-$07ff` | `2,048 B` | 80x25 character matrix (`$0000-$07cf` = `2,000 B` live; `$07d0-$07ff` = `48 B` `screen_clear` 8-page pad) |
| `$0800-$0fff` | `2,048 B` | 80x25 attribute matrix (`$0800-$0fcf` = `2,000 B` live with `VDC_ATTR_MODE = $80` selecting Set 1; `$0fd0-$0fff` = `48 B` `screen_clear` pad) |
| `$1000-$10ff` | `256 B` | `dungeon_render_vdc.s` overlap-safe right-scroll scratch (`RVSD_SCRATCH_CHAR = $1000`, `RVSD_SCRATCH_ATTR = $1080`, `78 B` each) |
| `$1100-$1fff` | `3,840 B` | `ITEM.CAT[0..3839]` (`VDC_ITEM_CAT_LO_BASE..END`, `C128M-015`, disk builds; untouched on `.crt` which reads MD128 ROM directly) |
| `$2000-$3fff` (bytes `0..7` / 16 B cell) | `4,096 B` | Live 8x8 glyph rasters across all `512` character cells (`$2000-$2fff` Set 0 uppercase/graphics, `$3000-$3fff` Set 1 mixed-case gameplay font; `8` scanlines/row uses only cell bytes `0..7`) |
| `$2000-$3fff` (bytes `8..15` / 16 B cell) | `4,096 B` | Unused scanline tail in 8-scanline text mode: `ITEM.CAT[3840..7477]` (`3,638 B` across `455` cells at `$2008-$200f, $2018-$201f, ..., $3c68-$3c6d`, `458 B` spare to `$3fff`, `C128M-015`). Populated once at boot (`c128_load_core_residents`) strictly AFTER any `JDLCHR` (`$ff62`) font restore |

## Required Change Record

For CPU-memory ownership, address, MMU, load, or copy changes, complete
applicable fields and mark safety-critical irrelevant fields `N/A` with
evidence. A VDC-only change uses the explicit VDC record below instead.

```text
symbol/payload and linked segment:
PRG load header:
source and destination spans:
source/destination bank and lifetime:
MMU/$01 configuration at load, copy, execution and return:
common-RAM and interrupt/vector assumptions:
KERNAL transition path:
overlapping owners and guarding assertions:
production runtime test:
```

Unknown bank visibility, ownership, copy survival or return state blocks the
change. A correct linked address alone is insufficient.

## Physical VDC Contract

VDC screen and attribute memory are not CPU RAM. Changes must identify active
VDC register, internal source/destination address, row stride, copy direction,
ready polling, and whether horizontal/vertical paths share equivalent bounds.
Shared map coordinates must not depend on VDC physical layout.

```text
active VDC register(s):
internal source and destination addresses:
screen/attribute base and row stride:
copy direction, length, and overlap policy:
ready-polling and interrupt assumptions:
horizontal/vertical bound equivalence:
production runtime test:
```

## Failure Interpretation

Presume a memory-contract defect until disproved for CPU JAM, moving crash
addresses after byte-size changes, blank map with valid UI, overlay-specific
corruption, horizontal/vertical VDC divergence, save corruption after layout
work, or a new runtime timeout.

## Verification Matrix

| Change | Required gate |
| --- | --- |
| Any C128 layout change | `make build`, assembler map/prints, all ownership assertions |
| Overlay/cache/load/copy change | linked symbol, PRG header, banks and spans inspected; focused production runtime test |
| Broad banking/MMU/runtime-loaded change | `make test128-fast-smoke`, then authoritative `make test128` |
| Physical VDC change | horizontal, vertical, copied-interior and stale-tile production tests |
| Shared payload composition | affected C64 and Plus/4 build/runtime gates |

A test importing a routine at a convenient address proves its logic, not its
C128 memory contract.

## Executable Enforcement

| Invariant | Current gate | Command/status |
| --- | --- | --- |
| Bank isolation, IRQ-state preservation, CPU-memory row-copy helpers, and Bank 1 `$d000-$dfff` `$7f` bounce spike | `platforms/commodore/c128/tests/test_memory128.s` | `TEST_FILTER='memory128' make test128` |
| Bank 1 ownership, `< $af00` consolidated resident bound, `< $8000` cartridge/legal-stream bounds, and overlay bounds | `.assert` blocks in `memory128.s`, `main.s`, `cartridge_copy.s`, and `legal.s` | `make build128`, `make cartridge128` |
| Built payloads: each standalone PRG at its segment's start and within its max, `moria128.prg` inside `$1c01..$aeff`, resident Bank 0 windows and emitted bytes pairwise disjoint, `Bank1DB` (`recall[279]` + `zp_save_buf`) inside `$7400..$7a5f` before the catalog name pool | `tools/check_c128_payloads.py` (actual emitted bytes, not end labels) | `make check128-payloads`; runs before `make test128` and `make test128-fast-smoke` |
| Overlay/cache runtime behavior and partial preload fallback | `cache_survival_smoke`, `hot_path_zero_disk_smoke`, `overlay_partial_failure_smoke`, `overlay_data_transition_smoke` (`preload_partial_failure_smoke` retired under `C128M-007`) | `TEST_FILTER='cache' make test128`, then authoritative `make test128` for broad changes |
| VDC copy/scroll and VDC `ITEM.CAT` non-overlap physical behavior | `platforms/commodore/c128/tests/test_vdc_scroll_delta128.s`, `platforms/commodore/c128/tests/test_item_desc128.s`, `hot_path_zero_disk_smoke` | `TEST_FILTER='vdc_scroll_delta128|item_desc128|hot_path_zero_disk_smoke' make test128` |
| Complete normal/no-I/O MMU and KERNAL transition matrix | none | `NOT IMPLEMENTED` |

## Decision Ledger

Accepted rows dated 2026-07-09 record explicit maintainer decisions from the
work16 C128 memory review; this ledger is their durable approval provenance.

| ID | Status | Owner/date | Scope and selected rule | Evidence/enforcement | Supersedes |
| --- | --- | --- | --- | --- | --- |
| C128M-001 | Accepted | Project maintainer, 2026-07-09 | `memory128.s` constants/assertions are executable ownership authority | `make build`, `test_memory128.s` | prose-only ownership |
| C128M-002 | Superseded in part by C128M-014 | Project maintainer, 2026-07-09 | After boot staging is scrubbed, `$d000-$dfff` remained an I/O-visible reserved runtime/cache gap in Bank 1 until Phase 5 (`C128M-014`) adopted guarded `< $4000` `SEI` + `$7f` runtime data ownership; Bank 1 overlay page-copier cache slots still avoid `$d000-$dfff` | maintainer decision; overlap assertions; boot-copy mode review | none |
| C128M-003 | Accepted | Project maintainer, 2026-07-09 | New cache/map/common-RAM use requires a separate layout design and overlap assertions | build assertions and authoritative `make test128` | none |
| C128M-004 | Accepted | Project maintainer, 2026-08-12 | Modal-misc overlay gets a Bank 1 cache slot at `$9800-$9CFF`, carved from title-cache slack (title art needs 593-624 B of the former 1928 B cache); overlay cache covers IDs 1-9 with a second ready-bit byte | maintainer direction this session; `memory128.s` overlap asserts; `cache_survival_smoke` and partial-failure smokes | none |
| C128M-005 | Accepted | Project maintainer, 2026-10-25 | Store init/restock (`store_restock_overlay.s`) moves from the items overlay (ID 7, full after store stacking) to the cold chest overlay (ID 10); `tramp_store_init_all`/`tramp_store_restock_all` load ID 10, a disk load at new game and town re-entry. Bank 1 has no free slot to cache ID 10 (largest free span: 244 B at `$730C`). Maintainer: "I don't want the load, but let's do it for now." | `main.s` ID assert and overlay-fit asserts; `make test128` | cache ID 10 if Bank 1 space is found |
| C128M-007 | Accepted | Project maintainer, 2026-11-02 | The monster catalog replaces the tiers (`docs/MONSTER_CATALOG_DESIGN.md`): it takes the tier cache window (name pool, then `128.cat` fields) and the STARTUP overlay slot (`128.cnm` names, Huffman-coded with their own tree). STARTUP is no longer cached: New Game loads it from disk. The level index is resident in `128.world`; the fetch reads Bank 1 through the safe DB and Huffman helpers. Names on disk were declined unless needed. Maintainer: "let's not cache the start overlay. and then huffman-code the names, but avoid #2 unless we need to." | `memory128.s` catalog spans and overlap asserts; `main.s` segment asserts; `make check128-payloads`; `catalog_spawn_smoke`, `cache_survival_smoke`; `make test128` | C128M-004's STARTUP cache slot; the tier cache |
| C128M-006 | Accepted | Project maintainer, 2026-10-31 | `slain_str` ("You have been slain.", 21 B, read-only, read only by Bank 0 `core/game_loop.s`) moves from `128.item` to the always-resident `128.diskio`, beside `press_key_str`, because the 33-slot inventory arrays (+16 B) would overflow `128.item` by 3 B. `128.item` keeps 18 B free; `128.diskio` 30 B (21 B in the tightest test variant) | `docs/X_WEAPON_SWAP_DESIGN.md` §3.5 and §14 answer 1; `main.s` asserts `slain_str` lies inside the disk-I/O payload; `make check128-payloads`; `make test128` | none |
| C128M-008 | Proposed (awaiting maintainer review) | 2026-11-09 | The program-media probe (`disk_program_media_present`, `c128_program_play_exists`, `c128_ppe_tries`, `c128_program_read_command_status`, `c128_program_play_read_filename`; 201 B of Bank 0 code and data, called only from Bank 0 resident code) moves from `128.item` to `128.world`, because 16-item stores (+224 B of store arrays) overflowed `128.item` by 166 B. Both payloads are always resident in Bank 0 and `128.world` loads first (`c128_load_core_residents`), so the probe is present at least as early as before. `128.world` now ends at `$8B58` (247 B free), `128.item` at `$A7DC` (35 B free) | `main.s` asserts the probe lies inside the world payload; `make check128-payloads`; `make test128` | none |
| C128M-009 | Proposed (awaiting maintainer review) | 2026-11-11 | `eff_find_doors` and its row counter (Detect Doors/Stairs, 66 B) move from `128.item` to the tail of `128.play`, because the four VMS wands (MON-031) overflowed `128.item` by 25 B. It runs only in play (the spell and the wizard), never while `128.persist` holds the `$AF00` window. The wands' own effects (`core/wand_bolt_entries.s`) ride the death overlay beside the other Phase 3 handlers its table calls | `main.s` asserts `eff_find_doors` lies between `c128_resident_play_body` and `c128_resident_play_end`; `make check128-payloads`; `make test128` | none |
| C128M-010 | Proposed (awaiting maintainer review) | 2026-11-12 | `look_flash_target.s` (30 B) and `player_adjust_equipment_stat.s` (31 B) move from `Default` to the tail of `128.world` (`C128ResidentWorld`), because the legal-viewer merge pushed `Default` in `title_art_smoke` (+26 B) and `cache_survival_smoke` (+32 B) past `$6000`. `128.world` is always-resident Bank 0 RAM below `$D000` (`$6000-$8C4F`), loaded before `128.item`/`128.play`, leaving 25 B free in `128.world` and ≥29 B free below `$6000` in the tightest test variant (403 B in product) | `main.s` asserts both symbols lie inside `C128ResidentWorld`; `io_contracts.s` `C128AuditBelowIo`; `make check128-payloads`; `make test128` | none |
| C128M-011 | Proposed (awaiting maintainer review) | 2026-11-14 | Consolidate the four historical always-resident Bank 0 sub-PRGs — `128.world` (`$6000`), `128.item` (`$8c50`), `128.select` (`$a800`), and `128.diskio` (`$ab00`) — into the single contiguous Bank 0 `Default` resident image `moria128.prg` (`$1c01..<$af00`). Those internal boundaries originated when separate pre-allocated Bank 0 segments were loaded off disk at fixed base addresses; keeping four fixed buckets trapped small slacks behind artificial walls (`$6000`/`$8c50`/`$a800`/`$ab00`), forcing ad-hoc symbol relocations (`C128M-006`/`008`/`010`). Merging them into `Default` frees dead boundary slack (`605 B` free `< $af00` on disk, `1,020 B` free `< $af00` on cartridge), drops 4 runtime preload files (`23 -> 19` / `26 -> 22`), and frees 4 Magic Desk 128 directory slots (`CART_ASSET_COUNT` `31 -> 27` of `32`), while leaving `$af00-$cfff` (`128.persist`/`128.play`), `$0a80-$3fff` low common/runtime payloads (`128.fdisk`/`RuntimeLowData`/`boot_copier`), Bank 1 payloads, and `$e000-$efff` overlays untouched. Cartridge-bank-safe code/data running with External Function ROM mapped at `$8000-$bfff` (`MMU_CR=$3a`) remains strictly `< $8000` (`cart_reader_end=$21d1`, `legal_os_fill_cache=$2f76`). | `main.s` asserts `program_end <= $af00`, `* == program_end`, and `< $af00` resident symbol bounds; `cartridge_copy.s` asserts `cart_read`, `cart_desc_buf + CART_DESCRIPTOR_SIZE`, and `cart_reader_end <= $8000`; `legal.s` asserts `legal_os_fill_cache < $8000`; `tools/check_c128_payloads.py`; `tools/check_c128_md128.py`; `make test128` | `C128M-006`, `C128M-008`, `C128M-010` cross-wall placements |
| C128M-012 | Proposed (awaiting maintainer review) | 2026-11-14 | Phase 2 cold code eviction on C128 (`docs/MEMORY_REDESIGN_PLAN.md` §4.2, §5, §6): (1) enable `HOME_OVERLAY_SEPARATE` and `RECALL_VIEW_OVERLAYED`, moving `core/ui_home.s` (from `128.bank`) and `core/ui_home_text.s` (from `ovl.town`) into a new uncached on-demand `$e000` overlay `ovl.home` (`128.home`, `OVL_HOME = 11`, skipped by `c128_preload_all_overlays`), wired via `platforms/commodore/c128/overlays.mk`, `hal_platform_overlay_count = 11`, 12-byte `ovl_ready_mask`/`ovl_ready_mask_hi`, `tramp_store_enter` `#STORE_HOME` dispatch, and `CART_ASSET_HOME = 23` (`CART_ASSET_COUNT` `27 -> 28` of `32`); (2) keep `SAVE_IN_STORAGE_OVERLAY` OFF (`128.persist` already holds `save.s`/`save_slot_menu.s`/`title_screen.s`); (3) evict `wizard_generate_item_execute` (`:WizardGenExecSegment()`) from `128.play` into `128.bank` (`RuntimeBankedCode` `$f000`) rather than `ovl.modal` so Bank 1 `cache.ovl.modal` (`225 B` free) does not overflow, move `recall_view_body` (`:RecallViewBodySegment()`) from `128.play` into `ovl.ui`, move `eff_find_doors`/`eff_fd_row` from `128.play` into `Default`, and move `core/ui_disk_setup.s` from `ovl.help` into `128.persist` (`disk_setup_runtime128.s` enters via `c128_modal_require_persist`). | `main.s` segment/ID/mask `.assert`s; `io_contracts.s` `C128AuditHomeOverlay`; `cartridge_contract.s` `28`-asset `.assert`; `check_c128_payloads.py --both` (`24` payloads); `check_c128_md128.py`; `test128-fast-smoke`, `test128`, `test128-cartridge` | `C128M-009` placement of `eff_find_doors` in `128.play` |
| C128M-013 | Proposed (awaiting maintainer review) | 2026-11-15 | Phase 4 full VMS item/ego/trap/recall/Save V2 integration on C128 (`docs/MEMORY_REDESIGN_PLAN.md` §4.3, §6): (1) retire `128.names` from Bank 1 `$7400-$7a5f` (`Bank1DB`) and place `recall[279]` (`1,116 B`, `$7400-$785b`) + `zp_save_buf` (`142 B`, `$785c-$78e9`, `bank1_db_end = $78ea`, `374 B` free) in `Bank1DB` accessed via `mmu_safe_db_read/write_ptr0/1`; (2) adopt `'ITM2'` `item.cat` (`7,573 B` at Phase 4; now `7,478 B`) + `item.idx` (since retired on C128 by `C128M-015`), reading records into Bank 0 `$1b00-$1bff` (`icat_sector_buf`) from REU Bank 2 (`$020000`) when REU is present, from MD128 cartridge ROM (`CART_ASSET_ITEM_CAT = 25`), or via 1541/1571/1581 direct `U1` sector reads (`common/item_cat_fetch.s`); (3) enable `SAVE_IN_STORAGE_OVERLAY` (`ovl.storage` / `128.storage`, `OVL_STORAGE = 12`, `$e000-$effa`, `4,091 B`, `5 B` free, uncached on-demand `$e000` overlay) and move `platforms/shared/save.s` into `StorageOverlay` while `128.persist` (`$af00-$c028`, `4,393 B`, `4,055 B` free) retains `title_screen.s`, `save_slot_menu.s`, `ui_disk_setup.s`, and `item_cat_boot_load`; (4) update MD128 cartridge directory to `29/32` slots (`CART_ASSET_COUNT = 29`, `126,172 B` free) and Save Format V2 (`SAVE_VERSION = $20` / `17,161 B` at Phase 4; now `$22` / `17,164 B` stream). | `memory128.s` & `main.s` `.assert`s; `check_c128_payloads.py --both`; `check_c128_md128.py` (`29/32` assets); `report_memory_budgets.py --port c128`; `make test128` & `make test128-cartridge` | `128.names` in Bank 1 `$7400-$7a5f`; `C128M-012` keeping `SAVE_IN_STORAGE_OVERLAY` OFF |
| C128M-014 | Proposed (awaiting maintainer review) | 2026-11-16 | Phase 5 full `279/279` VMS monster catalog (`29` SoA fields, `4` attacks, `19` `ADESC_*` verbs, `24` `ATK_*` effects, `5` `MSF2_*` spells, `CD_*`/`CM2_*`) & Bank 1 `$d000-$dfff` data adoption (`docs/MEMORY_REDESIGN_PLAN.md` §4.3, §5, §6): (1) amend `C128M-002` to allocate Bank 1 `$d000-$dfff` (`4,096 B`) to `128.cex` (`$d000-$d8b7`, `2,232 B`, `279 x 8 B` extended species rows loaded at boot via `c128_load_catalog_ext_prg` / `CART_ASSET_CEX`), `BANK1_STORE_INV_RESERVED` (`$d8b8-$dcb7`, `1,024 B` reserved), and `msg_history` (`$dcb8-$df37`, `640 B`, freeing `640 B` of Bank 0 `Default` RAM; `$df38-$dfff` = `200 B` free), accessed strictly via bottom-common `< $4000` (`$0c06+`) `SEI` + `MMU_RAM_BANK1_NOIO ($7f)` pointer thunks (`mmu_common_b1_noio_read/write_ptr0/1` with `$d506 = $0d`), while keeping `OVL_DEATH` cached at `$c000-$cfff`; (2) evict Wave 5.2 cold code (`player_chargen_cold.s`, `trap_trigger_cold.s`/`trap_damage_cold.s`, `door_open_close_cold.s`, `item_drop_cold.s`, `starting_kit_cold.s`, `player_bg_draw_cold.s`, `ui_help_cmd_cold.s`) and cold zero-HP melee effects (`mae_steal` -> `ovl.items`, `mae_lose_exp`/`ATK_AGGRAVATE` -> `128.bank`, `mae_disenchant`..`mae_eat_charges` -> `ovl.home`), plus 80-col `ui_recall.s` tables in `ovl.ui`; (3) update MD128 cartridge directory to `30/32` slots (`CART_ASSET_COUNT = 30`, `140,399 / 262,144 B` used, `121,745 B` free). | `memory128.s` `$d000-$dfff` `.assert`s; `catalog_ext_fetch128.s`; `check_c128_payloads.py --both`; `check_c128_md128.py` (`30/32` assets); `report_memory_budgets.py --port c128`; `make test128` & `make test128-cartridge` | `C128M-002` blanket post-boot runtime ban on Bank 1 `$d000-$dfff`; Bank 0 `msg_history` |
| C128M-015 | Proposed (awaiting maintainer review) | 2026-11-16 | Eliminate all runtime floppy disk seeks on C128 disk builds across `ITEM.CAT` reads, `g` item pickup, `Shift+dir` running, `o`/`c` plain + locked doors, and floor traps using native C128 Bank 0 + 16 KB VDC RAM only (C128 never uses REU): (1) replace `ITEM.IDX` + `item_catalog_records.s` sector streaming on disk builds with `platforms/commodore/c128/item_cat_vdc128.s`, which loads `ITEM.CAT` (`7,478 B` in current 361-item catalog) at boot (`c128_load_core_residents`, strictly after any `$ff62` `JDLCHR` font restore, keeping `20/20` startup load count unchanged) via `crl_sa = 0` into Bank 1 `MAP_BASE` (`$4000-$5d35`), verifies `'ITM2'`, and streams `ITEM.CAT[0..3839]` into VDC `$1100-$1fff` (`3,840 B`) and `ITEM.CAT[3840..7477]` into the unused scanlines `8..15` of `455` character cells in VDC `$2008-$3c6d` (`4,096 B` capacity, `458 B` spare, leaving all Set 0 `$2000` and Set 1 `$3000` scanlines `0..7` untouched); `C128_CARTRIDGE` retains `hal_item_cat_cart_read_byte` (`< $8000`); (2) promote `item_pickup` (`220 B`, out of uncached `StorageOverlay`, retiring `HAL_PLATFORM_ITEM_PICKUP_OVERLAY` and `tramp_item_pickup`) and `run_initialize` (`166 B`, out of `ModalMiscOverlay`) into Bank 0 `Default` (`moria128.prg` `$1c01-$adb2`, raising disk `Default` headroom `155 -> 334 B`, `128.play` `233 -> 268 B`, `cache.ovl.modal` `39 -> 205 B`, and `ovl.storage` `3 -> 223 B`); keep `door_try_open`/`close` in cached `OVL_HELP` and `door_pick_roll` in cached `OVL_DISARM`. | `memory128.s`, `dungeon_render_vdc.s`, & `main.s` VDC/resident `.assert`s; `io_contracts.s`; `check_c128_payloads.py --both`; `check_c128_md128.py`; `check_overlay_calls.py --port c128 --check-sym`; `item_desc128`, `cache_survival_smoke`, `hot_path_zero_disk_smoke`; `make test128` & `make test128-legal` | `C128M-013` runtime `ITEM.IDX`/`U1` sector streaming on C128 disk builds; `item_pickup` in `ovl.storage`; `run_initialize` in `ovl.modal` |
| C128M-016 | Proposed (awaiting maintainer review) | 2026-11-20 | `catalog_place_far` (`core/monster_catalog.s`: the win creature at generation and the turn's VMS wanderer, MON-039; `catalog_place_win_creature` / `catalog_place_wanderer` entries, 105 B) moves from Bank 0 `Default` to the head of `128.play` (`C128ResidentPlay`, `$af03-$af6b`) through `:CatalogWinBegin()`/`:CatalogWinEnd()` in `monster_catalog128.s`, because 920c0c0 left the product image 64 B below `$af00` and put the `C128_TEST_TITLE_ART_CONTENT` variant 66 B over it. The play signature (`c128_resident_play_sig0..2`) is now emitted before `monster_catalog128.s` so it stays the payload's first three bytes. Callers: `monster_spawn_level` (Bank 0, called only from `game_loop.s` in `128.play`) and `turn_post_action` (`128.play`); the modal `128.persist` that shares `$af00` calls neither | `main.s` asserts (program image `<= $af00`, play signature at `$af00`, play `<= $d000`, persist below `main_loop`/`player_died`), `monster.s` assert `catalog_place_win_creature < $e000`, `check_c128_payloads.py`; `make test128` | none |
| C128M-017 | Proposed (awaiting maintainer review) | 2026-11-26 | Extract MON-044 Gain-Stat helpers (`core/6502/player_gain_stat_helpers.s`: `player_step_healthy_sum_y`, `player_apply_stat_delta_y`, behind `PLAYER_GAIN_STAT_HELPERS_EXTERNAL`) from Bank 0 `Default` (`player.s`) into `C128ResidentPlay` (`128.play`), freeing `Default` headroom (`program_end = $ae83`, `125 B` free `< $af00` disk; `$ac54`, `684 B` free cart) while leaving `128.play` at `$cf74` (`140 B` free `< $d000`). Sole caller `eff_gain_stat.s` runs from `ovl.storage` during gameplay when `128.play` is mapped (`$af00-$cfff`), and the helpers jump only to Bank 0 `Default` (`pses_zero_res_write_y`, `pses_write_cur_y`, `player_step_equip_stat_y`) | `main.s` `player_step_healthy_sum_y >= c128_resident_play_body && player_step_healthy_sum_y < c128_resident_play_end && player_apply_stat_delta_y >= c128_resident_play_body && player_apply_stat_delta_y < c128_resident_play_end`, `check_c128_payloads.py --both`, `make test128` | `player_step_healthy_sum_y`/`player_apply_stat_delta_y` in `Default` |
| C128M-018 | Proposed (awaiting maintainer review) | 2026-11-27 | Detect, report, and utilize internal 256KB C128 MMU RAM upgrades (4×64KB banks via `$FF00` bits 7–6, `MMU_RAM_BANK2=$BE` / `MMU_RAM_BANK3=$FE`): (1) `c128_detect_256k` (`memory128.s`) runs a non-destructive 2-pass 4-bank isolation probe at `$E000` (unowned in Bank 2 `$E000-$EFFF`, keeping I/O mapped with `MMU_RAM_BANK1=$7E` and saving/restoring Bank 0/1 `$E000` and IRQ state) and sets `c128_ram_256k` (`hal_platform_256k_present`); (2) `legal_sysinfo.s` reports `"256KB (4x64KB Banks)"` vs `"128KB (2x64KB Banks)"` and `title_sysinfo_banked.s` (`#if HAL_PLATFORM_TITLE_SYSINFO_256K_PROBE`) centers `"C128  KERNAL R1  256KB"` on the Title bottom sysinfo line (both disk and `moria8-c128.crt`); (3) on 256KB disk builds (`HAL_PLATFORM_OVERLAY_CACHE_EXTENDED_256K`), boot preload rises from `20` to `26` files to cache `OVL_STARTUP` (`$1000`), `OVL_CHEST` (`$2000`), `OVL_HOME` (`$3000`), `OVL_STORAGE` (`$4000`), `LEGALUI` (`$5000`, `10` pages), `128.PLAY` (`$6000`, `33` pages), and `128.PERSIST` (`$8100`, `18` pages `< wizard_wall_walk_enabled`/`main_loop`/`player_died`) in Bank 2 via fast 29 cyc/B common-RAM page helpers (`mmu_common_xbank_{read,write}_page`) and `mmu_common_bank_{read,write}_ptr1`, eliminating Program Disk swaps across gameplay, `Shift+V`, Disk Setup, Save, Load, and Game Over/Retirement (Title `A` / `? -> L` still prompts for Program Disk when reading uncached `LICENSE`/`SOURCE-OFFER`) | `memory128.s` Bank 2, `BANK2_PERSIST_PAGES`, `BANK2_LEGALUI_PAGES`, & `bank_overlay_cache_mmu` `.assert`s; `test_memory128.s` `test6_256k_probe_and_banks`; `c128_256k_cache_smoke` (`-c128fullbanks` blank Drive 8 zero-swap incl. Load & Game Over); `test_cartridge.py` `run_256k_cartridge_check`; `make test128-fast-smoke`, `make test128` | C128 128KB-only cold status for `OVL_STARTUP`, `OVL_CHEST`, `OVL_HOME`, `OVL_STORAGE`, `LEGALUI`, `128.PLAY`/`128.PERSIST` on 256KB systems |

## License/source modal ownership (2026-11-10)

`LEGALUI` is an uncached modal loaded on title `A` (About) or Help `L`: Bank 0 $E000-$EFFF; existing w_* KERNAL wrappers; no Bank 1 cache slot.
Code ends before overlay base+$600; a 142-byte core-ZP snapshot starts there,
and the disk/ROM input cache occupies base+$700..+$7FF. Both are modal
workspace, never game-data loans or emitted PRG padding. The resident entry saves core ZP before asset loading, after any media
handler that may itself load an overlay.
The viewer reads existing documents through the storage HAL, closes every
channel, retains live sound/redraw state, and restores the caller snapshot.
Linked payload bounds and production-path modal entry/return tests enforce
this ownership. See `docs/LEGAL_VIEWER.md` for the change and verification record.

Verification (2026-11-10): `make -j7 -O test` passed, including the 27-payload
span check, all 139 C128 suites, and the production title/Help legal-viewer
tests. LEGALUI links and loads at $E000 in Bank 0 and executes with $FF00=$3E;
its workspace stays inside the existing overlay window. Physical VDC layout
changes are N/A.

Review repair: the resident entry uses the normal program-media prompt and
required asset retry path; only successful entry calls `tramp_ui_enter`.
DOS status is validated before data-channel selection, then the file is
reopened because closing command channel 15 closes drive data channels.
A lost first status byte retries a fresh OPEN up to three times; other DOS
errors are final. Refills reject fatal READST bits before exposing cached
bytes, retaining EOI-only final bytes. Production fault tests cover byte
0/63/127 and status $02/$80/$42/$40.
The low-resident chunk reader remains below $6000, enters/exits KERNAL once
per 128 bytes, writes through ROM to Bank 0 $E700, and returns to the overlay
under $FF00=$3E. No staged source span or Bank 1 allocation changes.

Repair verification (2026-11-11): `make -j7 -O test` passed. Applicable payload
bounds, header/load/execution ownership, missing-file cleanup and production
modal-return rows are complete; see `docs/LEGAL_VIEWER.md` for linked spans and
coverage. Existing banking configurations and persistent cache owners remain;
physical display-layout changes are N/A.

## Change Record — `C128_CARTRIDGE` Magic Desk 128 Port (2026-11-13)

- **Scope & Isolation**: Added isolated `-define C128_CARTRIDGE` build in
  `build/c128-cart/` producing 256 KB `Magic Desk 128` CRT v2.0 (`Hardware ID 4`)
  image `build/moria8-c128.crt` (`platforms/commodore/c128/cartridge_{contract,boot,copy}.s`).
  Non-cartridge C128 layout (`build/c128/`) and memory ownership remain unchanged;
  a pre-existing `save_write_map_banked:` label-placement bug in `platforms/shared/save.s`
  (C128-only `#if HAL_STORAGE_STREAM_CHUNKED && HAL_STORAGE_MAP_BANKED` block) was also
  fixed so `save_game` persists the 13,068-byte Bank 1 map on both disk and cartridge.
- **External Function ROM & MMU Banking**: Cold boot (`rom0.bin` at `$8000-$80BB`) copies
  `boot_copier` to `$1800` (Bank 0 RAM below `$1C01`), executes C128 KERNAL init (`IOINIT`,
  `RAMTAS`, `RESTOR`, `CINT`) under `$FF00=$00`, then sets `$D506=$05` and `$FF00=$3A`
  (`MMU_EXT_ROM_IO`) to copy `moria128.prg` across `$DE00` banks `0..15` (`$8000-$BFFF`)
  before jumping to `entry` (`$1C0E`). `exit_trampoline` resets `CART_REG_BANK=0` (`$DE00`)
  and `$D506=$00` (disabling common RAM), then sets `$FF00=$00` before `jmp ($fffc)`.
- **Bottom-Common Bounce Thunk (`memory128.s`)**: Under `#if C128_CARTRIDGE`,
  `mmu_common_cart_copy_chunk` occupies `$0FB0-$0FF3` (`MMU_COMMON_CART_BASE`) and
  32-byte bounce buffer/control state (`mmu_common_cart_{bank,dst_mmu,dst_d506,len,buf}`)
  extends `mmu_common_helpers_blob` (`$0D2E-$0D51`), keeping `128.fdisk.prg` (`$0D60-$0FA6`)
  below `$0FB0`. Under `sei`, Bank 1 Huffman/vector loads (`128.huff.prg`, `128.hvec.prg`)
  use `CART_DEST_BANK1_TOP_OFF` (`$D506=$05`, `$FF00=$7E`) and restore `$D506=$0D` plus
  caller `$FF00` & `P`. No `$1000-$5FFF` or `$8000+` code switches Bank 1 or `$D506`.
- **Verification (2026-11-13)**: `make test128-cartridge` (PAL 22/22 + NTSC 22/22,
  including real `Shift+Q`, `exit_trampoline`, zero-disk cancels, `disk_require_save_media`
  / `disk_init_drive` / missing-save recovery, declined overwrite preservation, and
  Drive 8/9 `.d71` save/load interchange), `check_c128_md128.py` (`--selftest` and
  CRT/bin), `check_c128_payloads.py` (`build/c128-cart`, 27 payloads),
  `cartconv -c build/moria8-c128.crt`, `make check-hal-boundaries`, and
  `make check-6502-lint` (0 errors) all passed. Applicable header/load/execution
  ownership, Bank 1 vector/Huffman isolation, common-RAM `.assert`s,
  `exit_trampoline_end <= $4000`, overlay loading (all 10 overlays including
  `ovl.chest`), legal ROM streaming, and `.d71` save/load interchange rows are
  complete; physical VDC display layout changes are N/A.

## Change Record — Phase 1 Bank 0 Consolidation (`C128M-011`) & `C128M-002` Verification Spike (2026-11-14)

### 1. Protocol Change Record (`BEHAVIOR_CHANGE_PROTOCOL.md`)

```text
Problem and success criteria:
  Eliminate internal Bank 0 resident boundary fragmentation (`$6000` `128.world`,
  `$8c50` `128.item`, `$a800` `128.select`, `$ab00` `128.diskio`) by merging those
  four always-resident sub-PRGs into `Default` (`moria128.prg`, `$1c01..<$af00`)
  with zero `core/` or `platforms/shared/` edits, freeing Magic Desk 128
  cartridge directory slots (`31 -> 27` of `32`) and reclaiming boundary slack
  while preserving `$af00-$cfff` (`128.persist`/`128.play`), `$0a80-$3fff` low
  common/runtime payloads, Bank 1 payloads, `$e000-$efff` overlays, and
  `< $8000` cartridge-bank-safe code (`cart_reader_end <= $8000`). Also verify via
  a VICE `x128` spike (`test_memory128.s`) whether Bank 1 `$d000-$dfff` (`4 KB`)
  survives `SEI` + `$7F` (`MMU_RAM_BANK1_NOIO`) common-RAM bounce without
  corrupting I/O, VDC, CIA, IRQs, or KERNAL/Huffman transitions.

State being changed:
  Link-time Bank 0 segment placement, disk/cartridge asset tables (`CART_ASSET_COUNT`
  `31 -> 27`), startup preload file count (`23 -> 19` / `26 -> 22`), `.assert`
  bounds (`< $af00`, `< $8000`), payload/CRT static validators, and unit test
  `test_memory128.s` (`Test 5`). Zero runtime gameplay/monster/RNG/save state
  schema changes.

Search scope and terms:
  Searched `platforms/commodore/`, `tools/`, and `docs/` for
  `C128ResidentWorld`, `C128ResidentItems`, `C128ResidentSelect`,
  `C128ResidentDiskIo`, `128.world`, `128.item`, `128.select`, `128.diskio`,
  `CART_ASSET_`, `cart_read`, `cart_desc_buf`, and `preload_partial_failure_smoke`.

Relevant readers/writers found and known exclusions:
  Updated all C128 callers/packers/validators (`main.s`, `monster_catalog128.s`,
  `disk_setup_runtime128.s`, `io_contracts.s`, `legal.s`, `legal_stream.s`,
  `cartridge_contract.s`, `cartridge_copy.s`, `platforms/commodore/Makefile`
  `C128_*` only, `run_tests128.sh`, `test_cartridge.py`, `check_c128_payloads.py`,
  `make_c128_md128.py`, `check_c128_md128.py`, `test_memory128.s`). Excluded
  `core/`, `platforms/shared/`, C64/Plus/4, non-Commodore ports, and
  `tools/report_memory_budgets.py`. `HAL_PLATFORM_PICK_ITEM_RESIDENT_ITEMS_SEGMENT`
  stays defined in `platforms/commodore/c128/hal/lifecycle_policy.s` while
  segment macros in `main.s` resolve to `.segment Default` (`core/` unchanged).

Initialization, reset and persistence points:
  - Disk `boot128.s`: loads `MORIA128` into Bank 1 `$1c01..<$af00` below
    `stub_start`'s `$b000-$bfff` clear, copies Bank 1 `$1c00-$feff` -> Bank 0,
    scrubs Bank 1, and jumps to `entry`.
  - Direct `x128` unit autostart: KERNAL `LOAD` writes to Bank 0 `$1c01..<$af00`.
  - MD128 `.crt`: `boot_copier` at `$1800` copies `moria128.prg` directly into
    Bank 0 `$1c01..<$af00`.
  - Save/load persistence (`128.persist`/`128.play` `$af00-$cfff`) and `.d71`
    save format are unchanged; startup preload skips the 4 merged files and
    `overlay_partial_failure_smoke` exercises missing-preload fallback.

Affected production sequence through the changed transition:
  Boot (`boot128.s` / MD128 `boot_copier`) -> startup preload (count `19`/`22`) ->
  Bank 0 resident execution (`$1c01..<$af00`, `cart_read` `< $8000` under
  `MMU_CR=$3A`) -> title/help/legal/new-game/town/save transitions.

Contract decision or selected upstream oracle with source locations:
  Moria8 C128 port-local layout decision `C128M-011` (`docs/C128_MEMORY_CONTRACT.md`)
  plus `C128M-002` lift verification spike (`platforms/commodore/c128/tests/test_memory128.s`).
  Upstream Umoria gameplay semantics are unaffected (`N/A` — pure link/boot
  consolidation and memory-spike verification).

Intentional Moria8 deviations:
  Consolidating the four C128 Bank 0 resident sub-PRGs into `moria128.prg` is a
  port-local loader/linker simplification; player-visible gameplay, strings,
  save format, and overlays remain unchanged.

Input/intermediate widths, signedness, carry, range and overflow policy:
  16-bit unsigned addresses constrained by `.assert`s and Python packers:
  `moria128.prg` `$1c01..$aeff` (`program_end <= $af00`, `* == program_end`),
  `cart_reader_end <= $8000`, `legal_os_fill_cache < $8000`,
  `CART_ASSET_COUNT = 27 <= 32`, and `SPIKE_COMMON_BASE = $0f00 < MMU_COMMON_CART_BASE ($0fb0)`.

RNG reduction and bias, if applicable:
  N/A — zero RNG state, seeding, or reduction code modified (`core/rng.s` untouched).

Affected platforms, overlays, banks and owners:
  Commodore 128 disk and MD128 cartridge only (`Bank 0` `$1c01..<$af00` consolidated
  resident; MD128 directory `27/32`; `test_memory128.s` `Bank 1` `$d000-$dfff`
  spike). C64, Plus/4, Apple IIe, CX16, Atari 8-bit, BBC Master 128, `Bank 0`
  `$af00-$cfff`, `$0a80-$3fff`, `Bank 1` payloads, and `$e000-$efff` overlays keep
  existing ownership unchanged.

Required production-path tests:
  `make build128`, `make disk128`, `make cartridge128`,
  `tools/isolated.sh make -C platforms/commodore check128-payloads`,
  `check_c128_md128.py`, `make check-hal-boundaries`,
  `make test128-fast-smoke`, `make test128` (including `test_cartridge.py` PAL/NTSC,
  `test_legal.py`, `memory128`, `soak128`, `overlay_partial_failure_smoke`), and
  `make test128-legal`.

Known behavior explicitly out of scope:
  Actually relocating runtime caches/data into Bank 1 `$d000-$dfff` (`C128M-002`
  stays in force for production code pending Phase 2/3), `core/` changes,
  `tools/report_memory_budgets.py`, and non-C128 ports.

Unresolved uncertainty and risk:
  Under heavy concurrent host CPU contention (`r=33..36`), `make test128-fast`'s
  `soak128` (`harness128_batch.py` 30.0s wall-clock cap) timed out twice at
  `44.006s`, whereas `soak128` in `make test128` (`run_tests128.sh`,
  `-limitcycles 2000000000`) passes cleanly (`139/139`). `C128M-011` stays
  `Proposed` pending maintainer review.
```

### 2. Required CPU-Memory Change Record (`C128M-011`: Bank 0 Resident Merge)

```text
symbol/payload and linked segment:
  Consolidated `moria128.prg` in segment `Default` (`$1c01..<$af00`), absorbing the
  removed `C128ResidentWorld` (`128.world`), `C128ResidentItems` (`128.item`),
  `C128ResidentSelect` (`128.select`), and `C128ResidentDiskIo` (`128.diskio`)
  sub-PRGs (`main.s`, `monster_catalog128.s`, `disk_setup_runtime128.s`).
  Includes `title_str`, `press_key_str`, `slain_str`, `disk_program_media_present`..
  `c128_program_play_read_filename`, `look_flash_target`,
  `player_adjust_equipment_stat`, `disk_marker_init`, `disk_setup_run`,
  `uinv_title_str`/`uinv_sep_str`, `roll_ego_type`/`ego_*`, and (on cartridge
  builds) `cartridge_copy.s` (`cart_read`..`cart_reader_end`).

PRG load header:
  - Disk `build/c128/moria128.prg`: load header `$1c01`, emitted span `$1c01-$aca2`
    (`program_end = $aca3`, `605 B` free below `$af00`; `legal_os_fill_cache = $2f76`).
  - Cartridge `build/c128-cart/moria128.prg`: load header `$1c01`, emitted span
    `$1c01-$ab03` (`program_end = $ab04`, `1,020 B` free below `$af00`;
    `cart_read = $1ff9`, `cart_desc_buf = $21c0`, `cart_reader_end = $21d1`,
    `24,111 B` free below `$8000`).

source and destination spans:
  - Disk boot (`boot128.s`): `LOAD "MORIA128"` stages into Bank 1 `$1c01..<$af00`
    (safely below `stub_start`'s `$b000-$bfff` clear and `< $d000`), then copies
    Bank 1 `$1c00-$feff` -> Bank 0 `$1c00-$feff` and scrubs Bank 1.
  - Direct `x128` unit autostart: KERNAL `LOAD` writes directly through ROMs into
    Bank 0 `$1c01..<$af00`.
  - Magic Desk 128 cartridge (`cartridge_boot.s`/`cartridge_copy.s`): `boot_copier`
    (staged at `$1800`) streams `moria128.prg` from `$de00` ROM banks (`$8000-$bfff`)
    directly into Bank 0 `$1c01..<$af00`, jumping to `entry`. `CART_ASSET_COUNT`
    drops from `31` to `27` of `32` directory slots (`5` free).

source/destination bank and lifetime:
  Execution bank is Bank 0 (`$1c01..<$af00`), always resident for the full
  game/program lifetime. `$af00-$cfff` (`128.persist` / `128.play`), `$0a80-$3fff`
  low common/runtime payloads (`128.fdisk`, `RuntimeLowData`, `boot_copier`),
  Bank 1 cache/Huffman payloads, and `$e000-$efff` overlays retain their existing
  banks and lifetimes unchanged.

MMU/$01 configuration at load, copy, execution and return:
  - Disk `boot128.s`: KERNAL `LOAD` targets Bank 1 via `SETBNK(1, 0)`; `stub_start`
    copies Bank 1 -> Bank 0 using `MMU_RAM_BANK1_NOIO ($7f)` and returns to
    `MMU_ALL_RAM_IO ($3f)` / Bank 0 execution (`entry` -> `MMU_GAME_CFG`).
  - Cartridge (`cartridge_copy.s`): `cart_read` and `cart_desc_buf` execute with
    `MMU_CR = $3a` (`$8000-$bfff` mapped to External Function ROM, I/O visible) and
    restore caller `MMU_CR` on return; therefore `cart_reader_end <= $8000` is
    mandatory and asserted at compile time (`cart_reader_end = $21d1 < $8000`).
    `legal_os_fill_cache` remains `< $8000` (`$2f76`).
  - Execution/runtime: unchanged (`MMU_GAME_CFG` / `$ff00` common helpers).

common-RAM and interrupt/vector assumptions:
  Bottom common RAM (`$0400-$0fff` / `$0b00-$0fff` depending on build) and top
  common RAM (`$f000-$ffff`) remain unchanged; `moria128.prg` stays strictly inside
  Bank 0 `$1c01..<$af00`, below `128.persist`/`128.play` (`$af00-$cfff`) and I/O
  (`$d000-$dfff`). Zero Bank 1 or shared-common allocation changes.

KERNAL transition path:
  Disk `boot128.s` uses standard pre-handoff KERNAL `LOAD`; runtime KERNAL calls
  continue through `EnterKernal`/`ExitKernal` below `$4000` (`$3f/$3e -> $00`);
  no new code calls KERNAL from `$4000-$bfff`.

overlapping owners and guarding assertions:
  - `main.s`: `.assert program_end <= $af00`, `.assert * == program_end`, plus
    `<= $af00` / `< $af00` bounds on `title_str`, `press_key_str`, `slain_str`,
    `disk_program_media_present`..`c128_program_play_read_filename`,
    `look_flash_target`, `player_adjust_equipment_stat`, `disk_marker_init`,
    `disk_setup_run`, `uinv_title_str`/`uinv_sep_str`, and `roll_ego_type`/`ego_*`.
  - `cartridge_copy.s`: `.assert cart_read < $8000`,
    `.assert cart_desc_buf + CART_DESCRIPTOR_SIZE <= $8000`,
    `.assert cart_reader_end <= $8000`.
  - `legal.s`: `.assert legal_os_fill_cache < $8000`.
  - Static checkers: `tools/check_c128_payloads.py` (`moria128.prg` `$1c01..$aeff`
    span + emitted-byte disjointness against all Bank 0 payloads) and
    `tools/check_c128_md128.py` (`.crt` `27`-asset bounds + `< $8000` reader
    checks).
  - N/A: Physical VDC screen/attribute layout (`Physical VDC Contract` fields N/A —
    no VDC register, VRAM address, stride, or scroll change).

production runtime test:
  `make build128`, `make disk128`, `make cartridge128`, `make check128-payloads`,
  `make test128-fast` (`75/76`; `soak128` subject to `30s` batch wall timeout
  under host contention), `make test128-fast-smoke`, `make test128` (including
  `soak128`, `overlay_partial_failure_smoke` over the remaining preload/overlay
  media, and Magic Desk 128 cartridge PAL/NTSC tests), and `make test128-legal`.
```

### 3. Verification Spike — Lifting `C128M-002` (Bank 1 `$D000-$DFFF` via Common-RAM Bounce)

- **Scope & Mechanism Tested (`platforms/commodore/c128/tests/test_memory128.s`, Test 5 `test5_b1_d000_spike`)**:
  Verified whether Bank 1 `$d000-$dfff` (`4 KB`) can serve as runtime data/cache
  RAM when accessed exclusively through a bottom-common-RAM bounce stub
  (`SPIKE_COMMON_BASE = $0f00`, below `MMU_COMMON_CART_BASE = $0fb0`) under
  `sei` + `MMU_RAM_BANK1_NOIO` (`$7f`, with top common `$f000-$ffff` enabled and
  I/O hidden so Bank 1 RAM is visible at `$d000-$dfff`), restoring `$ff00` and
  caller `P` (`CLI`/`SEI`) before returning.
- **Verified Behavior in VICE `x128` (`memory128` under `make test128` / `harness128_batch.py`)**:
  - Common-RAM-bounced writes/reads succeeded across 12 representative addresses
    spanning the full 4 KB window (`$d000`, `$d020`, `$d500`, `$d600`, `$d601`,
    `$d800`, `$dc04`, `$dc05`, `$dd04`, `$dd05`, `$de00`, `$dfff`) under both
    `CLI` and `SEI` callers, keeping Bank 0 `$d020` (`$3f`) isolated from Bank 1
    `$d020`.
  - Hardware state remained intact across `$7f` bounce accesses: VIC border `$d020`
    (`$03`), VDC VRAM (`$07ff=$5d` pre-test and post-`$7f` read/write `$07fe=$6c`),
    and stopped CIA1/CIA2 timer latches.
  - Hardware IRQ delivery remained intact: enabling a real CIA1 Timer A IRQ while
    exercising `$0f00` `$7f` bounces delivered the pending IRQ safely through
    `$fffe/$ffff` -> `spike_common_irq_stub` -> `mmu_common_irq` without losing
    vectors or banking state.
  - Subsequent runtime transitions (`EnterKernal` / `SETLFS` / `ExitKernal` and
    `mmu_common_huff_read_ptr0`) passed without corruption after the `$7f` bounces.
- **Architectural Implication**:
  `C128M-002` remains enforced for unguarded/direct `$d000-$dfff` access, while
  this spike demonstrates in `x128` that a guarded, `sei` + `$7f` bottom-common
  bounce protocol safely unlocks Bank 1 `$d000-$dfff` (`4 KB`) without
  corrupting I/O chips, IRQs, VDC, or KERNAL/Huffman transitions if adopted in a
  subsequent phase.

### 4. Verification Matrix Status (`C128M-011`)

- **Any C128 layout change**: `make build128`, `make disk128`, `make cartridge128`,
  `check128-payloads`, `check_c128_md128.py`, and all `main.s` / `memory128.s` /
  `cartridge_copy.s` / `legal.s` `.assert` bounds enforce the new layout.
- **Overlay/cache/load/copy change**: inspected load headers/spans (`$1c01-$aca2`
  disk, `$1c01-$ab03` cartridge), `boot128.s` Bank 1 staging (`< $b000`),
  `cartridge_copy.s` `< $8000` reader invariant under `$3a`, and `test_memory128.s`
  spike.
- **Broad banking/MMU/runtime-loaded change**: `make test128-fast`,
  `make test128-fast-smoke`, `make test128`, and `make test128-legal` constitute
  the required acceptance gates.
- **Physical VDC change**: N/A (zero VDC register, address, stride, or scroll
  changes).
- **Shared payload composition**: N/A (`core/`, C64, and Plus/4 payloads are
  unmodified; `disk_setup_runtime128.s` is C128-only).

## Change Record — Phase 2 Cold Code Eviction (`C128M-012`) (2026-11-14)

### 1. Protocol Change Record (`BEHAVIOR_CHANGE_PROTOCOL.md`)

```text
Problem and success criteria:
  Relieve tight runtime headroom in `128.play` (`74 B` free in product, `39 B`
  free in `main_save_media_fail`), `ovl.help` (`12 B` free), `128.bank` (`34 B`
  free), and `ovl.town` (`100 B` free) by implementing Phase 2 cold code
  eviction on C128 (`docs/MEMORY_REDESIGN_PLAN.md` §4.2, §5, §6) without
  overflowing Bank 1 overlay caches (`cache.ovl.modal` `225 B` free,
  `cache.ovl.disarm` `34 B` free) or editing `core/`, `platforms/shared/`,
  `platforms/commodore/Makefile`, or non-C128 ports.
  Measured success: `128.play` `>= 200 B` free (`354 B` product, `319 B`
  `main_save_media_fail`), `ovl.help` `>= 200 B` free (`1,501 B`), `128.bank`
  `+460 B` (`34 B -> 494 B` free), `ovl.town` `+115 B` (`100 B -> 215 B` free),
  `128.persist` `3,692 B` free, `ovl.home` `$e000-$e397` (`3,177 B` free),
  MD128 directory `28/32`, and all C128 static/VICE/cartridge suites green.

State being changed:
  Link-time Bank 0 / overlay placement (`ovl.home` added at ID `11`;
  `ui_home.s`/`ui_home_text.s` -> `ovl.home`; `wizard_generate_item_execute`
  -> `128.bank`; `recall_view_body` -> `ovl.ui`; `eff_find_doors` -> `Default`;
  `ui_disk_setup.s` -> `128.persist`), C128 overlay/asset tables
  (`hal_platform_overlay_count = 11`, `12`-byte `ovl_ready_mask`/`_hi`,
  `CART_ASSET_HOME = 23`, `CART_ASSET_COUNT = 28`), `tramp_store_enter`
  `#STORE_HOME` dispatch, `disk_setup_runtime128.s` `c128_modal_require_persist`
  handoff, and disk/CRT packers/validators/tests. Zero gameplay, RNG, monster,
  or `.d71` save schema changes.

Search scope and terms:
  Searched `platforms/commodore/c128/`, `platforms/commodore/common/`, and
  `tools/` for `HOME_OVERLAY_SEPARATE`, `RECALL_VIEW_OVERLAYED`,
  `WizardGenExecSegment`, `RecallViewBodySegment`, `ovl_ready_mask`,
  `c128_preload_all_overlays`, `tramp_store_enter`, `ui_home`, `ui_disk_setup`,
  `disk_setup_runtime128`, `eff_find_doors`, `C128_EXTRA_OVERLAYS`,
  `CART_ASSET_`, and `128.home` / `ovl.home`.

Relevant readers/writers found and known exclusions:
  Updated C128 owners only: `platforms/commodore/c128/overlays.mk` (new),
  `platforms/commodore/c128/hal/lifecycle_policy.s`,
  `platforms/commodore/c128/hal/storage_overlay_names.s`,
  `platforms/commodore/c128/main.s`, `platforms/commodore/c128/io_contracts.s`,
  `platforms/commodore/c128/cartridge_contract.s`,
  `platforms/commodore/c128/test_cartridge.py`,
  `platforms/commodore/c128/run_tests128.sh`,
  `platforms/commodore/common/disk_setup_runtime128.s`,
  `tools/make_c128_md128.py`, `tools/check_c128_md128.py`, and
  `tools/check_c128_payloads.py` (`--both`).
  Excluded by Wave 1 / Phase 2 design: `SAVE_IN_STORAGE_OVERLAY` remains OFF
  on C128 (`128.persist` already owns save/title screens and `ovl.storage`/
  `ovl.title` are unneeded on MD128); `core/`, `platforms/shared/`,
  `platforms/commodore/Makefile`, `platforms/commodore/common/overlay.s`,
  C64, Plus/4, and non-Commodore ports untouched. `tramp_wizard_generate_item`
  (`:WizardGenExecSegment()` in `128.bank` with Bank 0 common banked window)
  avoids adding `+140 B` to `ovl.modal` whose `cache.ovl.modal` Bank 1 slot only
  has `225 B` slack.

Initialization, reset and persistence points:
  - `c128_preload_all_overlays` still skips cold overlays (`> OVL_CHEST`, so
    both `ovl.chest` and `ovl.home` (`11`) load on demand from disk or MD128).
  - `ovl_ready_mask` (`$82ad`) and `ovl_ready_mask_hi` (`$82b9`) allocate 12
    bytes (`0..11`) matching `hal_platform_overlay_count` (`11`, max index `11`)
    and `OVERLAY_CACHE_COUNT` (`9`).
  - `tramp_store_enter` checks `zp_store_idx == #STORE_HOME` -> `overlay_load #11`
    + `jmp home_enter`, else `overlay_load #2` (`ovl.town`) + `jmp store_enter`;
    overlay load failure returns via `jmp entry_main`.
  - `tramp_disk_setup` and `tramp_disk_prepare_selected` now ensure `128.persist`
    is swapped into `$af00` via `jsr c128_modal_require_persist` without loading
    `ovl.help`.

Affected production sequence through the changed transition:
  Startup preload -> `128.play` town/dungeon loop -> Town Home entry
  (`tramp_store_enter` -> `ovl.home` `$e000` -> `home_enter`), Disk Setup
  (`c128_modal_require_persist` -> `128.persist` `ui_disk_setup`), Monster
  Memory recall (`ovl.ui` `recall_view_body`), Wizard item gen (`128.bank`
  `wizard_generate_item_execute`), and Detect Doors/Stairs (`Default`
  `eff_find_doors`).

Contract decision or selected upstream oracle with source locations:
  `docs/MEMORY_REDESIGN_PLAN.md` §4.2, §5, §6 and Moria8 C128 decision
  `C128M-012` (`docs/C128_MEMORY_CONTRACT.md`), backed by Wave 1 hooks in
  `core/store_data_defs.s`, `core/ui_home.s`, `core/ui_recall.s`, and
  `core/wizard.s`. Upstream Umoria gameplay behavior is unchanged.

Intentional Moria8 deviations:
  1) C128 maps `:WizardGenExecSegment()` to `RuntimeBankedCode` (`128.bank`)
     instead of `ovl.modal` so Bank 1 `cache.ovl.modal` (`1,280 B` cap, `225 B`
     free) stays below its 5-page ceiling without enlarging Bank 1 cache
     geometry.
  2) `SAVE_IN_STORAGE_OVERLAY` remains OFF on C128 because `128.persist`
     (`$af00-$cfff`, `3,692 B` free after absorbing `ui_disk_setup.s`) already
     swaps `save.s` and `title_screen.s` out of `128.play`.

Input/intermediate widths, signedness, carry, range and overflow policy:
  Unsigned 16-bit addresses and 8-bit overlay indices (`0..11`, max ID
  `C128_HOME_OVERLAY_ID = 11` matched to `hal_platform_overlay_count = 11`).
  Segment caps enforced at assembly time and by `check_c128_payloads.py --both`:
  `Default <= $af00`, `128.persist <= $d000`, `128.play <= $d000`,
  `RuntimeBankedCode <= $ff00`, overlays `<= $f000`, `CART_ASSET_COUNT = 28 <= 32`.

RNG reduction and bias, if applicable:
  N/A — no RNG state or reduction code changed.

Affected platforms, overlays, banks and owners:
  Commodore 128 disk and MD128 cartridge only (`Default`, `128.persist`,
  `128.play`, `128.bank`, `ovl.town`, `ovl.help`, `ovl.ui`, `ovl.home`, MD128
  directory `28/32`). C64, Plus/4, Apple IIe, CX16, Atari 8-bit, BBC Master 128,
  Bank 1 payload/cache bounds, and `.d71`/`.d64` save format untouched.

Required production-path tests:
  `make -C platforms/commodore build128 disk128 cartridge128`,
  `python3 tools/check_c128_payloads.py --both`,
  `python3 tools/check_c128_md128.py --selftest`,
  `python3 tools/check_c128_md128.py build/moria8-c128.crt build/c128-cart`,
  `make check-hal-boundaries check-6502-lint`,
  `tools/isolated.sh make -C platforms/commodore test128-fast-smoke`, and
  `tools/isolated.sh make -C platforms/commodore test128 test128-cartridge`.

Known behavior explicitly out of scope:
  Creating `ovl.storage` or `ovl.title` on C128, modifying `core/`,
  `platforms/shared/`, `platforms/commodore/Makefile`, Bank 1 cache geometry,
  or non-C128 platforms.

Unresolved uncertainty and risk:
  `cache.ovl.disarm` (`34 B` free) and `ovl.gen` (`63 B` free) were unchanged by
  Phase 2 and remain on the tight-budget watchlist; `ovl.ui` tightened from
  `229 B` to `96 B` free after absorbing `recall_view_body` (`133 B`). `C128M-012`
  stays `Proposed` awaiting maintainer review.
```

### 2. Required CPU-Memory Change Record (`C128M-012`: Phase 2 Cold Code Eviction)

```text
symbol/payload and linked segment:
  - Added uncached overlay `ovl.home` (`128.home`, `OVL_HOME = 11`, segment
    `HomeOverlay`, `$e000-$e397`, `919 B` payload, `3,177 B` free) containing
    `core/ui_home_text.s` (evicted from `ovl.town`) and `core/ui_home.s`
    (evicted from `128.bank`); exports `home_enter` (`$e18d`), `home_retrieve`
    (`$e1be`), `home_deposit` (`$e290`).
  - `wizard_generate_item_execute` (`:WizardGenExecSegment()`, `$f000`) moved
    from `C128ResidentPlay` (`128.play`) to `RuntimeBankedCode` (`128.bank`,
    `$f000-$fd12`, `3,346 B` used, `494 B` free `< $ff00`).
  - `recall_view_body` (`:RecallViewBodySegment()`, `$e000`) moved from
    `C128ResidentPlay` (`128.play`) to `UiOverlay` (`ovl.ui`, `$e000-$efa0`,
    `4,000 B` used, `96 B` free `< $f000`).
  - `eff_find_doors` (`$acbf` disk / `$ab20` cart) + `eff_fd_row` moved from
    `C128ResidentPlay` (`128.play`) to `Default` (`moria128.prg`, `program_end`
    `$ad00` disk / `$ab61` cart).
  - `core/ui_disk_setup.s` (`uds_show_insert_prompt` `$bced`) moved from
    `HelpOverlay` (`ovl.help`, `$e000-$ea23`, `1,501 B` free) to
    `C128ResidentPersist` (`128.persist`, `$af00-$c194`, `3,692 B` free
    `< $d000`); `128.play` ends at `$ce9e` (`354 B` free in product; `$cec1` /
    `319 B` free in `main_save_media_fail`).
  - `ovl_ready_mask` (`$82ad`) and `ovl_ready_mask_hi` (`$82b9`) resized to
    12 bytes (`0..11`).

PRG load header:
  - `ovl.home`: header `$e000`, payload `919 B`, span `$e000-$e397` (`921 B` file).
  - `128.persist.prg`: header `$af00`, payload `4,756 B`, span `$af00-$c194`.
  - `128.play.prg`: header `$af00`, payload `8,094 B`, span `$af00-$ce9e`.
  - `128.bank.prg`: header `$f000`, payload `3,346 B`, span `$f000-$fd12`.
  - `ovl.town`: header `$e000`, payload `3,881 B`, span `$e000-$ef29`.
  - `ovl.help`: header `$e000`, payload `2,595 B`, span `$e000-$ea23`.
  - `ovl.ui`: header `$e000`, payload `4,000 B`, span `$e000-$efa0`.
  - `moria128.prg`: header `$1c01`, payload `37,119 B` / span `$1c01-$ad00`
    (disk), payload `36,704 B` / span `$1c01-$ab61` (cartridge).

source and destination spans:
  - `ovl.home`: loaded on demand from disk (`128.home` on `.d64`/`.d71`/`.d81`)
    or MD128 cartridge asset `#23` (`CART_ASSET_HOME`) into Bank 0 `$e000-$e397`;
    not preloaded into Bank 1 cache (`C128_HOME_OVERLAY_ID = 11 > OVL_CHEST`).
  - `128.bank` (`$f000-$fd12`), `128.persist` (`$af00-$c194`), `128.play`
    (`$af00-$ce9e`), `ovl.town` (`$e000-$ef29`), `ovl.help` (`$e000-$ea23`),
    `ovl.ui` (`$e000-$efa0`), and `moria128.prg` (`$1c01-$ad00` / `$1c01-$ab61`)
    keep their existing load/copy/swap paths.

source/destination bank and lifetime:
  - `ovl.home`: executes in Bank 0 `$e000-$efff`; transient modal lifetime while
    inside the Home (`tramp_store_enter` `#STORE_HOME`), evicted whenever another
    overlay (`$e000-$efff`) loads.
  - `128.persist` (`$af00-$c194`): Bank 0 `$af00-$cfff` modal persist window,
    swapped in by `c128_modal_require_persist` for Disk Setup/Save/Title and
    restored to `128.play` (`$af00-$ce9e`) on gameplay resume.
  - `128.bank` (`wizard_generate_item_execute` `$f000`): top common RAM /
    `RuntimeBankedCode` lifetime matching existing `128.bank` helpers.
  - `Default` (`eff_find_doors`): Bank 0 always-resident below `$af00`.

MMU/$01 configuration at load, copy, execution and return:
  - `ovl.home` loads through `overlay_load` (same Bank 0 `$e000-$efff`
    KERNAL/cartridge loader used by `ovl.chest`), runs under standard
    `MMU_GAME_CFG`, and returns to `tramp_store_enter` -> gameplay.
  - `tramp_disk_setup`/`tramp_disk_prepare_selected` invoke
    `c128_modal_require_persist` to swap `128.persist` into Bank 0 `$af00` and
    restore `128.play` on exit without touching Bank 1 caches.
  - `cart_reader_end` (`$21d1`) and `legal_os_fill_cache` (`$2f89`) remain
    `< $8000` under `MMU_CR=$3a`.

common-RAM and interrupt/vector assumptions:
  - `RuntimeBankedCode` (`$f000-$fd12`) preserves `$ff00-$ffff` MMU registers
    and hardware IRQ/NMI vectors (`banked_code_end <= $ff00`); `128.bank` gains
    `+460 B` (`$fede -> $fd12`).
  - Bottom common RAM (`128.proj`, `128.input`, `128.fdisk`, `128.runtime`) and
    Bank 1 `$e000-$e4ff` overlay caches (`cache.ovl.modal`, `cache.ovl.disarm`)
    are unchanged.

KERNAL transition path:
  Disk overlay/persist swaps (`128.home`, `128.persist`, `128.play`) continue
  using `overlay_load` / `c128_modal_require_persist` -> `< $4000`
  `EnterKernal`/`ExitKernal`; no code in moved segments calls KERNAL directly
  from `$4000-$bfff`.

overlapping owners and guarding assertions:
  - `main.s`: `.assert C128_HOME_OVERLAY_ID == hal_platform_overlay_count`,
    `overlay_home` / `ovl_home_end <= $f000`, `wizard_generate_item_execute >=
    banked_payload && < banked_code_end`, `recall_view_body >= overlay_ui &&
    < ovl_ui_end`, `uds_show_insert_prompt` inside `C128ResidentPersist` and
    `c128_resident_persist_end <= player_died` (`<= main_loop` in product
    builds), `eff_find_doors < program_end`, `ovl_ready_mask_hi -
    ovl_ready_mask == hal_platform_overlay_count + 1` (12 bytes), plus existing
    `program_end <= $af00` and `banked_code_end <= $ff00`.
  - `io_contracts.s`: `home_enter`, `home_retrieve`, `home_deposit` checked
    under `C128AuditHomeOverlay`.
  - `cartridge_contract.s`: `CART_ASSET_HOME == 23`, `CART_OVERLAY_COUNT == 11`,
    `CART_ASSET_COUNT == 28 <= 32`.
  - Static checkers: `tools/check_c128_payloads.py --both` (`24` payloads
    disk + cartridge), `tools/check_c128_md128.py` (`16` banks, `28` assets),
    `run_c128_io_contract_check` (`home_overlay`/`ovl_home_end`).

production runtime test:
  `make -C platforms/commodore build128 disk128 cartridge128`,
  `check_c128_payloads.py --both`, `check_c128_md128.py --selftest`,
  `make check-hal-boundaries check-6502-lint`,
  `tools/isolated.sh make -C platforms/commodore test128-fast-smoke` (`10/10`),
  and `tools/isolated.sh make -C platforms/commodore test128 test128-cartridge`
  (`139/139` `run_tests128.sh`, `test128-legal` `6/6`,
  `test_product_scripted_smoke.py` `4/4`, `test128-cartridge` PAL `22/22` +
  NTSC `22/22` incl. `ovl.home` cold load verification).
```

### 3. Verification Matrix Status (`C128M-012`)

- **Any C128 layout change**: `make -C platforms/commodore build128 disk128 cartridge128`,
  `tools/check_c128_payloads.py --both` (`24` payloads disk + cartridge),
  `tools/check_c128_md128.py` (`16` banks, `28` verified assets), and all
  `main.s`/`io_contracts.s`/`cartridge_contract.s` `.assert` guards enforced
  the new spans.
- **Overlay/cache/load/copy change**: inspected PRG load headers and spans for
  `ovl.home` (`$e000-$e397`), `128.persist` (`$af00-$c194`), `128.play`
  (`$af00-$ce9e`), `128.bank` (`$f000-$fd12`), `ovl.town` (`$e000-$ef29`),
  `ovl.help` (`$e000-$ea23`), `ovl.ui` (`$e000-$efa0`), and `moria128.prg`;
  Bank 1 `cache.ovl.modal` (`225 B` free) and `cache.ovl.disarm` (`34 B` free)
  remained unchanged; MD128 `test_cartridge.py` explicitly tested `ovl.home`
  on-demand `overlay_load` in both PAL and NTSC (`22/22` each).
- **Broad banking/MMU/runtime-loaded change**: `make -C platforms/commodore test128-fast-smoke`
  (`10/10`) and authoritative `make -C platforms/commodore test128 test128-cartridge`
  (`139/139` `run_tests128.sh` incl. `memory128`, `cache_survival_smoke`,
  `overlay_partial_failure_smoke`, `soak128`, `test128-legal`, and MD128 PAL/NTSC
  cartridge) passed.
- **Physical VDC change**: N/A (zero VDC register, VRAM address, stride, or
  scroll changes).
- **Shared payload composition**: N/A (`core/`, `platforms/shared/`, C64, and
  Plus/4 payloads are unmodified; `disk_setup_runtime128.s` is C128-only).

## Change Record — Phase 3 Wave 2 C128 HAL Exports & Generated Trampolines (2026-11-14)

### 1. Protocol Change Record (`BEHAVIOR_CHANGE_PROTOCOL.md`)

```text
Problem and success criteria:
  Wire C128 to the Wave 1 core HAL and trampoline-generator changes without
  altering core/, tools/, platforms/commodore/Makefile, or other ports:
  (1) implement `hal_overlay_post_reload` and
      `hal_platform_item_action_restore_bank` in Bank 0 resident below-I/O RAM
      (`Default`, `< $AF00` / `< $D000`) so `core/player_items.s`
      (`show_inv_and_select`) and `core/item_actions_overlay.s`
      (`item_action_get_key`) no longer hardcode `$0102,x`/`$0104,x` stack probes
      or inline C128 MMU/$01 register sequences;
  (2) migrate the 43 manifest-generated `tramp_*` stubs (`tools/trampoline_manifest.py`
      `C128_ENTRIES`, `kind != "custom"`) out of `platforms/commodore/c128/main.s`
      into `#import "../../../build/trampolines/c128_trampolines.inc"`, while
      retaining all 33 `custom` trampolines/fallthroughs in `main.s` (and
      `legal.s`, `look_trampoline.s`, `disk_setup_runtime128.s`);
  (3) keep all `c128_trampolines.inc` stubs and both new HAL exports strictly
      below `$D000` (inside `Default`, `< $AF00`) and preserve exact `A` and `N`/`Z`
      semantics across `hal_platform_item_action_restore_bank`;
  (4) update `platforms/commodore/c128/run_tests128.sh` to regenerate
      `build/trampolines/c128_trampolines.inc` at startup before standalone
      KickAssembler runs and update its static guard checks accordingly.

State being changed:
  Resident Bank 0 `Default` layout in `platforms/commodore/c128/main.s`
  (adding `hal_overlay_post_reload` at `$2D81` disk / `$2FDF` cart and
  `hal_platform_item_action_restore_bank` at `$2D8F` disk / `$2FED` cart;
  hoisting `:C128BankedPreserveFlagsTrampoline` and
  `:C128BankedSharedEpilogueTrampoline` above the `#import` point; importing
  `build/trampolines/c128_trampolines.inc` in `.segment Default` after
  `../common/overlay.s` so `OVL_TOWN`/`OVL_DEATH` are in scope; deleting the 43
  hand-written generated `tramp_*` definitions) and static/bootstrap assertions
  in `platforms/commodore/c128/run_tests128.sh`. Zero changes to gameplay rules,
  item/monster state, RNG, save schema, VDC layout, Bank 1 caches, or overlays.

Search scope and terms:
  Searched `platforms/commodore/c128/`, `core/player_items.s`,
  `core/item_actions_overlay.s`, `tools/trampoline_manifest.py`, and
  `tools/gen_trampolines.py` for `hal_overlay_post_reload`,
  `hal_platform_item_action_restore_bank`, `item_action_get_key`, `iagk_key`,
  `$0102`/`$0104`, `C128_ENTRIES`, and all 43 generated `tramp_*` names.

Relevant readers/writers found and known exclusions:
  - `core/player_items.s` (`show_inv_and_select`) calls `jsr hal_overlay_post_reload`
    after `overlay_load` under `PLATFORM_PRODUCT_OVERLAY_RUNTIME &&
    !HAL_PLATFORM_AUX_PERSISTENT_DATA`; standalone C128 unit tests
    (`test_soak128.s`, `test_identify128.s`) do not compile `player_items.s` with
    `PLATFORM_PRODUCT_OVERLAY_RUNTIME`.
  - `core/item_actions_overlay.s` (`item_action_get_key`) ends with
    `jmp hal_platform_item_action_restore_bank` when
    `HAL_PLATFORM_ITEM_ACTION_KEY_RESTORES_BANK` is non-zero (`c128/hal/lifecycle_policy.s`);
    no standalone C128 unit test defines `HAL_PLATFORM_ITEM_ACTION_KEY_RESTORES_BANK`
    without `main.s`.
  - `platforms/commodore/c128/io_contracts.s` (`:C128AuditBelowIo`) audits all
    resident `tramp_*` entrypoints `< $D000` (`program_end <= $AF00` tightens
    this to `< $AF00`).
  - `tools/gen_trampolines.py --check` (`validate_manifest_and_sources`) enforces
    0 hand-defined generated `tramp_*` definitions and 100% custom/generated
    manifest coverage for `c128`.

Initialization, reset and persistence points:
  Unchanged from `C128M-011`/`C128M-012`. Generated `c128_trampolines.inc`
  stubs live in Bank 0 `Default` (`moria128.prg`), copied from Bank 1 to Bank 0
  at boot (`boot128.s` / `cartridge_boot.s`) and never overwritten during
  persist/play swaps or overlay loads (`$AF00-$EFFF`).

Affected production sequence through the changed transition:
  1) Item overlay `?` inventory return (`show_inv_and_select` ->
     `overlay_load` -> `jsr hal_overlay_post_reload`): calls
     `jsr hal_platform_runtime_resync` (`c128_restore_runtime_guards`), sets
     `MMU_ALL_RAM` (`$3E`) in `$FF00`, `sei`, `BANK_NO_KERNAL` (`$35`) in `$01`,
     `rts` back to `$E000` overlay caller with `P`/`A` matching original inline
     code.
  2) Item overlay key read (`item_action_get_key` -> `jsr hal_input_get_key` ->
     `jmp hal_platform_item_action_restore_bank`): saves `A` (`pha`), writes
     `MMU_ALL_RAM` (`$3E`) to `$FF00` and `BANK_NO_ROMS` (`$34`) to `$01`, then
     `pla` (restoring `A` and setting `N`/`Z` from key byte) and `rts` directly
     to `item_action_get_key`'s caller (tail-call saving 10 B in `ovl.items`).
  3) All 43 migrated `tramp_*` entrypoints execute from `c128_trampolines.inc`
     inside `Default` (`< $AF00`), calling macros/helpers (`overlay_load`,
     `BankOutKernal()`, `c128_restore_runtime_guards`, `tramp_sr_epilogue`,
     `c128_return_to_death_overlay`) with identical banking/interrupt behavior.

Contract decision or selected upstream oracle with source locations:
  C128 memory ownership `C128M-011` / `C128M-012` (`Default <= $AF00`, resident
  callable entrypoints `< $D000`), HAL contract (`core/platform_services_api.s`,
  `platforms/commodore/c128/hal/lifecycle_policy.s`), and Wave 1 manifest
  (`tools/trampoline_manifest.py` `C128_ENTRIES`).

Intentional Moria8 deviations:
  `c128_trampolines.inc` is imported inside `.segment Default` after
  `#import "../common/overlay.s"` (and after `:C128BankedPreserveFlagsTrampoline`
  / `:C128BankedSharedEpilogueTrampoline`) rather than immediately at the legacy
  L1590 block, because `tramp_item_init_identification` (`OVL_TOWN`) and
  `tramp_spell_execute_selected` (`OVL_DEATH`) expand `.const` IDs declared by
  `platforms/commodore/common/overlay.s` (`OVL_*` cannot be duplicated earlier
  in `main.s`). Both `hal_*` exports and all 43 generated stubs remain in
  `.segment Default` strictly below `$AF00` (`< $D000`).

Input/intermediate widths, signedness, carry, range and overflow policy:
  `hal_platform_item_action_restore_bank` preserves 8-bit unsigned key in `A`
  via `pha`/`pla`, restoring `N`/`Z` identically to `lda iagk_key`. Segment
  bounds enforced at assemble time: `Default` `program_end <= $AF00`,
  `128.play`/`128.persist <= $D000`, `128.bank <= $FF00`, overlays `<= $F000`.

RNG reduction and bias, if applicable:
  N/A — no RNG state or reduction code changed.

Affected platforms, overlays, banks and owners:
  Commodore 128 disk and MD128 cartridge only (`Default` `moria128.prg`, plus
  Wave 1 `ovl.items` `-10 B` footprint already emitted by Wave 1 `core/`).
  Bank 1 caches, `$AF00` modal slots, `$F000` banked runtime, low common/runtime
  segments, C64/Plus/4/Apple IIe/CX16/Atari 8-bit/BBC Master 128 untouched.

Required production-path tests:
  `python3 -B tools/gen_trampolines.py --check` (0 `c128` errors),
  `python3 -B tools/check_overlay_calls.py`,
  `make check-hal-boundaries`,
  `make -C platforms/commodore build128 disk128 cartridge128 check128-payloads`,
  `python3 -B tools/check_c128_payloads.py --both`,
  `python3 -B tools/check_c128_md128.py build/moria8-c128.crt build/c128-cart`,
  and `./tools/isolated.sh make test128` (authoritative full C128 runtime,
  `test128-legal`, `test_product_scripted_smoke.py`, and PAL/NTSC `test128-cartridge`).

Known behavior explicitly out of scope:
  Modifying `core/`, `tools/`, `platforms/commodore/Makefile`, non-C128 ports,
  or regenerating/migrating any of the 33 declared `custom` C128 trampolines.

Unresolved uncertainty and risk:
  Tight budgets unchanged (`ovl.gen` end `$EFC1` / `63 B` free, `cache.ovl.disarm`
  `34 B` free). Both `moria128.prg` disk (`539 B` free `< $AF00`) and cartridge
  (`954 B` free `< $AF00`) gained `+27 B` over `C128M-012` from deleting
  redundant legacy stubs/probing vs adding the two HAL exports.
```

### 2. Required CPU-Memory & Verification Matrix Status (Wave 2)

- **Any C128 layout change**: `Default` `moria128.prg` spans `$1C01-$ACE5` (`37,092 B` payload, `539 B` free `< $AF00`) on disk and `$1C01-$AB46` (`36,677 B` payload, `954 B` free `< $AF00`) on cartridge. `hal_overlay_post_reload` (`$2D81` disk / `$2FDF` cart), `hal_platform_item_action_restore_bank` (`$2D8F` disk / `$2FED` cart), and all 43 generated trampolines in `c128_trampolines.inc` (e.g., `tramp_item_init_identification` `$A0F0`/`$9F51`, `tramp_store_restock_all` `$A2B8`/`$A119`, `tramp_chest_open` `$A302`/`$A163`) link inside `.segment Default` below `$AF00` and below `$D000`. Cartridge ROM-safe readers stay `< $8000` (`cart_reader_end <= $8000`, `legal_os_fill_cache < $8000`). Enforced by `679` disk / `686` cartridge KickAss `.assert`s (`io_contracts.s` `:C128AuditBelowIo`, `program_end <= $AF00`), `tools/check_c128_payloads.py --both` (`24` payloads each PASS), `tools/check_c128_md128.py` (`16` banks, `28` assets PASS), `tools/gen_trampolines.py --check` (`0` C128 errors), `tools/check_overlay_calls.py` (`0` violations), and `make check-hal-boundaries`.
- **Overlay/cache/load/copy change**: `ovl.items` ends at `$EEFD` (`259 B` free `< $F000`); `128.play.prg` (`$AF00-$CE9E`, `354 B` free `< $D000`), `128.persist.prg` (`$AF00-$C194`, `3,692 B` free `< $D000`), `128.bank.prg` (`$F000-$FD12`, `494 B` free `< $FF00`), and all `$E000` overlays (`ovl.start` `$EFBC`, `ovl.town` `$EF29`, `ovl.death` `$EF6D`, `ovl.modal` `$E41F`, `ovl.gen` `$EFC1`, `ovl.help` `$EA23`, `ovl.ui` `$EFA0`, `ovl.disarm` `$E2DE`, `ovl.chest` `$EA15`, `ovl.home` `$E397`) preserve PRG load headers, copy spans, and Bank 1 cache windows unchanged.
- **Broad banking/MMU/runtime-loaded change**: `hal_overlay_post_reload` and `hal_platform_item_action_restore_bank` execute in `< $4000` Bank 0 RAM (`MMU_ALL_RAM` `$3E`, `BANK_NO_KERNAL` `$35` / `BANK_NO_ROMS` `$34`); `run_tests128.sh` regenerates `c128_trampolines.inc` via `python3 -B ../../../tools/gen_trampolines.py` and passes all 12 filtered static/assembly guard suites (`main128_asm`, `c128_artifact_budget`, `c128_symbol_placement`, `c128_prompt_irq_guard`, `c128_item_overlay_key_guard`, etc.). Authoritative runtime verification runs via `./tools/isolated.sh make test128`.
- **Physical VDC change**: N/A (zero VDC register, VRAM address, stride, or scroll changes).
- **Shared payload composition**: N/A (Wave 2 edits only `platforms/commodore/c128/**` and `docs/C128_MEMORY_CONTRACT.md`; `core/`, `tools/`, and all other platforms untouched).

## Phase 4 Item Catalog (`ITEM.CAT`), `OVL_STORAGE = 12`, & Bank 1 `recall[279]` (`C128M-013`, 2026-11-15)

### 1. Required CPU-Memory Change Record (`C128M-013`)

```text
symbol/payload and linked segment:
  - `Bank1DB` (`virtual` segment in Bank 1 `$7400-$7A5F`, `1,632 B`): `recall[279]`
    (`1,116 B` at `$7400-$785B`) + `zp_save_buf` (`142 B` at `$785C-$78E9`,
    `bank1_db_end = $78EA`, `374 B` free), replacing retired `128.names.prg`.
  - `StorageOverlay` (`build/c128/ovl.storage.prg` / `128.storage`, `OVL_STORAGE = 12`,
    `$E000-$EFFA`, `4,091 B`, `5 B` free `< $F000`): hosts `platforms/shared/save.s`
    under `SAVE_IN_STORAGE_OVERLAY`.
  - `item.cat` (`7,478 B` current / `7,573 B` at Phase 4 `'ITM2'` cold item/ego/flavor catalog) and `item.idx`
    (`65 B` header + 30-sector track/sector table loaded into `icat_idx_table`, superseded on C128 by `C128M-015`),
    with 254-byte sector buffer `icat_sector_buf` in Bank 0 `$1B00-$1BFF`.
  - `Default` (`moria128.prg`, `$1C01-$ADF8` disk [`37,368 B`, `263 B` free `< $AF00`] /
    `$1C01-$A9F3` cart [`36,339 B`, `1,292 B` free `< $AF00`]), `128.play.prg`
    (`$AF00-$CFC0`, `8,385 B`, `63 B` free `< $D000`), `128.persist.prg`
    (`$AF00-$C028`, `4,393 B`, `4,055 B` free `< $D000`), `128.bank.prg`
    (`$F000-$FEE3`, `3,812 B`, `28 B` free `< $FF00`), and MD128 `.crt` directory
    (`29/32` slots used: adds `CART_ASSET_STORAGE = 24` and `CART_ASSET_ITEM_CAT = 25`,
    retiring `CART_ASSET_NAMES`).

PRG load header:
  - `ovl.storage.prg` (`128.storage`): `$00 $E0` (`$E000`).
  - `item.cat`: 2-byte header + `'ITM2'` binary (`7,478 B` current / `7,573 B` at Phase 4); `item.idx` (retired on C128 by `C128M-015`): 2-byte load header +
    `65 B` payload (`5 B` header + `60 B` track/sector pairs patched by
    `tools/fix_c128_item_idx.py` on `.d64`/`.d71`/`.d81`).

source and destination spans:
  - `Bank1DB` (`$7400-$78E9` in Bank 1): zero-initialized at boot (`boot128.s` /
    `cartridge_boot.s` Bank 1 scrub) and read/written at runtime via
    `mmu_safe_db_read_ptr0/1` and `mmu_safe_db_write_ptr0/1`.
  - `128.storage` (`$E000-$EFFA` in Bank 0): loaded on demand into `$E000-$EFFF`
    overlay window during save/load (`save_game` / `load_game` resident trampolines).
  - `item.cat` sectors: streamed on demand into Bank 0 `icat_sector_buf` (`$1B00-$1BFD`)
    from REU Bank 2 (`$020000`), MD128 cartridge ROM (`CART_ASSET_ITEM_CAT`), or
    IEC `U1` block reads (`common/item_cat_fetch.s`).

source/destination bank and lifetime:
  - `Bank1DB` lives permanently in Bank 1 (`$7400-$78E9`) across the entire session.
  - `128.storage` is an uncached cold overlay in Bank 0 `$E000-$EFFF` (`OVL_STORAGE = 12`).
  - `icat_sector_buf` (`$1B00-$1BFD` in Bank 0) caches the most recently fetched
    254-byte `item.cat` sector (`icat_cached_sec`).

MMU/$01 configuration at load, copy, execution and return:
  - `Bank1DB` accessors (`mmu_safe_db_*` in Bank 0 common RAM `< $0400`) switch
    `MMU_RAM_BANK1` (`$7E`) under `sei` and restore `MMU_ALL_RAM` (`$3E`).
  - `128.storage` executes in Bank 0 `$E000-$EFFA` with `MMU_ALL_RAM` (`$3E`) and
    `$01 = BANK_NO_ROMS` (`$34`) / `BANK_NO_KERNAL` (`$35`), calling Bank 0
    `w_*` KERNAL wrappers (`< $0400`) during IEC save/load streaming and
    restoring caller overlay on return.
  - MD128 cartridge `item.cat` reads invoke `cart_read` (`$1FBA-$2202 < $8000`)
    which maps External Function ROM at `$8000-$BFFF` (`MMU_CR = $3A`) and
    restores `MMU_ALL_RAM` (`$3E`) before returning.

common-RAM and interrupt/vector assumptions:
  - Unchanged from `C128M-011`/`C128M-012`: Bank 0 `$0000-$0FFF` and `$F000-$FFFF`
    top common remain shared; `cart_reader_end = $2202 <= $8000` and
    `legal_os_fill_cache < $8000` remain strictly below `$8000`.

KERNAL transition path:
  - Unchanged: all disk `item.cat` sector reads (`U1` on channel 2) and
    `128.storage` save/load streams route through existing `< $0400` `w_*`
    KERNAL wrappers with `zp_save_buf` in Bank 1 `$785C-$78E9`.

overlapping owners and guarding assertions:
  - `memory128.s` and `main.s` assert `bank1_db_end = $78EA <= $7A60`,
    `program_end <= $AF00`, `c128_resident_play_end <= $D000`,
    `c128_resident_persist_end <= $D000`, `banked_code_end <= $FF00`, and all
    12 `$E000` overlays `<= $F000`.
  - `tools/check_c128_payloads.py --both` and `tools/check_c128_md128.py` enforce
    disjoint Bank 0/Bank 1 spans and `29/32` MD128 cartridge assets.

production runtime test:
  - `./tools/isolated.sh make test128` (`139+` unit/runtime suites,
    `test128-legal`, `test_product_scripted_smoke.py`, and PAL/NTSC
    `test128-cartridge`) plus `tools/report_memory_budgets.py --port c128`
    (`0` overflows).
```

### 2. Verification Matrix Status (`C128M-013`, 2026-11-15)

- **Any C128 layout change**: `Default` `moria128.prg` ends at `$ADF9` (`263 B` free `< $AF00`) on disk and `$A9F4` (`1,292 B` free `< $AF00`) on cartridge; `128.play.prg` ends at `$CFC1` (`63 B` free `< $D000`); `128.persist.prg` ends at `$C029` (`4,055 B` free `< $D000`); `128.bank.prg` ends at `$FEE4` (`28 B` free `< $FF00`); `Bank1DB` spans `$7400-$78EA` (`1,258 / 1,632 B`, `374 B` free).
- **Overlay/cache/load/copy change**: All 12 `$E000-$EFFF` overlays fit (`ovl.start` `68 B` free, `ovl.town` `290 B` free, `ovl.death` `44 B` free, `ovl.modal` `39 B` free in `$9800-$9CFF` cache, `ovl.gen` `491 B` free, `ovl.help` `1,129 B` free, `ovl.ui` `70 B` free, `ovl.items` `301 B` free, `ovl.disarm` `14 B` free in `$9D00-$9FFF` cache, `ovl.chest` `124 B` free, `ovl.home` `415 B` free, `ovl.storage` `5 B` free at `$EFFB`). MD128 `.crt` uses `29/32` directory slots (`119,588 B` packed, `126,172 B` free).
- **Broad banking/MMU/runtime-loaded change**: Verified by `tools/check_c128_payloads.py --both`, `tools/check_c128_md128.py`, `tools/report_memory_budgets.py --port c128` (`0` overflows), and `make test128`.
- **Physical VDC change**: N/A.
- **Shared payload composition**: Verified alongside C64 and Plus/4 in `tools/report_memory_budgets.py` and `playtest/tests/test_game.py` (`DiskCheckTest` 780/780 PASS).

## Change Record — Phase 5 Full 279-Species Catalog (`128.cex`), Bank 1 `$D000-$DFFF` Adoption (`C128M-014`), & Cold Evictions (2026-11-16)

### 1. Protocol & CPU-Memory Change Record (`BEHAVIOR_CHANGE_PROTOCOL.md` + `C128_MEMORY_CONTRACT.md`)

```text
Problem and success criteria:
  Enable full VMS Moria 4.8 279/279 monster parity on C128 disk and Magic Desk 128
  cartridge (widening active cr_* buffers from 21 to 29 SoA fields = +320 B in
  Bank 0 Default, adding cat_undead[35] to resident catalog_index.s, adding the
  2,232 B 8-field extended catalog 128.cex, 4-attack loop, 19 ADESC_* verbs,
  all 24 ATK_* effects, 5 MSF2_* spells, CD_* vulnerabilities/immunities,
  CM2_PHASE/EATS_OTHER/PICKS_UP, and 15-field '/' recall) without evicting
  OVL_DEATH from its Bank 1 $C000-$CFFF cache slot or overflowing Default (< $AF00),
  128.play (< $D000), 128.bank (< $FF00), any $E000 overlay, or the 32-slot MD128
  cartridge directory.

symbol/payload and linked segment:
  - `128.cex.prg` (`128.CEX` on disk / `CART_ASSET_CEX` on MD128 `.crt`,
    `BANK1_CATALOG_EXT_BASE..END` = `$D000-$D8B7`, `2,232 B` = `279 x 8 B`
    extended species rows), plus `BANK1_STORE_INV_RESERVED` (`$D8B8-$DCB7`,
    `1,024 B`) and `msg_history` (`$DCB8-$DF37`, `640 B`, `msg_history_end = $DF38`,
    leaving `200 B` free at `$DF38-$DFFF` in Bank 1).
  - `catalog_fetch_ext` (`platforms/commodore/c128/catalog_ext_fetch128.s`, in
    Bank 0 `Default`) + `cat_ext_record[8]` (`8 B` in `Default`), reading via
    `mmu_common_b1_noio_read_ptr0` (`$0C06+` bottom common RAM).
  - Cold evictions from `Default` / `128.play`: Wave 5.2 cold modules
    (`player_chargen_cold.s` -> `ovl.start`, `trap_trigger_cold.s` &
    `trap_damage_cold.s` -> `ovl.chest`, `door_open_close_cold.s`,
    `item_drop_cold.s`, & `ui_help_cmd_cold.s` -> `ovl.help`,
    `starting_kit_cold.s` -> `ovl.start`, `player_bg_draw_cold.s` -> `ovl.ui`),
    cold zero-HP melee attack effects (`mae_steal` -> `ovl.items`,
    `mae_lose_exp` & `ATK_AGGRAVATE` -> `128.bank`, `mae_disenchant`..`mae_eat_charges`
    -> `ovl.home`), and 80-col `ui_recall.s` tables (`0 B` in `Default`, inside `ovl.ui`).
  - Measured spans: `Default` (`moria128.prg`) `$1C01-$AE7E` (`37,501 B`,
    `130 B` free `< $AF00`) disk / `$1C01-$AA37` (`36,406 B`, `1,225 B` free)
    cartridge; `cart_reader < $8000`: `$1FBF-$220F` (`592 B`); `128.play`:
    `$AF00-$CF0E` (`8,206 B`, `242 B` free `< $D000`); `128.persist`:
    `$AF00-$C029` (`4,393 B`, `4,055 B` free); `128.bank`: `$F000-$FEC8`
    (`3,784 B`, `56 B` free `< $FF00`); MD128 `.crt`: `30/32` directory slots.

PRG load header:
  - `128.cex.prg`: `$00 $D0` (`$D000`, emitted by `tools/build_catalog.py ext-rows --prg 0xD000`).

source and destination spans:
  - Disk boot (`c128_load_core_residents` -> `c128_load_catalog_ext_prg`):
    `c128_load_runtime_prg` streams `128.CEX` (`2,232 B`) via Bank 0 KERNAL
    wrappers into Bank 1 `$D000-$D8B7` (`c128_runtime_load_bank = 1`, which uses
    `mmu_common_b1_noio_write_ptr1` at `$7F`).
  - Cartridge boot (`CART_ASSET_CEX` via `cart_load_asset`): copies `2,232 B`
    from External Function ROM (`$8000-$BFFF` under `MMU_CR = $3A`) through the
    32-byte bottom-common bounce buffer `mmu_common_cart_copy_chunk` (`$0FB0`)
    into Bank 1 `$D000-$D8B7` with `dst_mmu = $7F` (`MMU_RAM_BANK1_NOIO`) and
    `dst_d506 = $0D`.
  - Runtime: `catalog_fetch_ext` reads `8 B` from `$D000 + id * 8` into Bank 0
    `cat_ext_record[0..7]`, and `ui_messages.s` reads/writes `msg_history` at
    `$DCB8-$DF37` via `mmu_common_b1_noio_read/write_ptr0/1`.

source/destination bank and lifetime:
  - `128.cex` (`$D000-$D8B7`) and `msg_history` (`$DCB8-$DF37`) live permanently
    in Bank 1 across the session after boot preload / `msg_init`.
  - `OVL_DEATH` remains permanently cached in Bank 1 `$C000-$CFFF`.

MMU/$01 configuration at load, copy, execution and return:
  - `mmu_common_select_bank1` (`memory128.s`, executing in bottom common RAM at
    `$0C06+ < $0FFF`) executes `php; sei; pla; sta mmu_common_save_p; lda #$7F;
    sta MMU_CR` (`MMU_RAM_BANK1_NOIO`, exposing physical Bank 1 RAM across
    `$1000-$EFFF` including `$D000-$DFFF` while `$D506 = $0D` keeps 4 KB bottom
    and top common RAM mapped). `mmu_common_select_bank0` restores `MMU_ALL_RAM`
    (`$3E`) and caller `P` before returning to Bank 0 / `$E000` overlay callers.

common-RAM and interrupt/vector assumptions:
  - `SEI` masks IRQs for the single-byte pointer thunk (`~26` cycles); `$D506`
    remains `$0D` throughout, so `$0000-$0FFF` (ZP, stack, common helpers) and
    `$F000-$FFFF` (top common RAM + NMI vector `mmu_common_nmi` at `$FFFA-$FFFB`)
    remain mapped even if a RESTORE NMI occurs (`mmu_common_nmi` only touches CIA2
    after `mmu_common_select_bank0` or harmlessly reads Bank 1 `$DD0D` without
    writing). `cart_reader_end = $220F <= $8000` and `legal_os_fill_cache < $8000`
    remain strictly below `$8000`.

KERNAL transition path:
  - Unchanged: `EnterKernal`/`ExitKernal` only run from Bank 0 operational state
    (`MMU_CR = $3E`), never inside a `mmu_common_b1_noio_*` critical section.

overlapping owners and guarding assertions:
  - `memory128.s` lines 1052-1059 assert `BANK1_OVERLAY_DEATH_END < BANK1_CATALOG_EXT_BASE`,
    `BANK1_CATALOG_EXT_BASE == $D000`, `BANK1_CATALOG_EXT_END == $D8B7`,
    `BANK1_STORE_INV_RESERVED_END == $DCB7`, `BANK1_MSG_HISTORY_END == $DF37`,
    and `BANK1_HIGH_DATA_END < BANK1_OVERLAY_DUNGEON_BASE` (`$E000`).
  - `tools/check_c128_payloads.py --both` and `tools/check_c128_md128.py` enforce
    all payload spans and `30/32` MD128 directory slots.

production runtime test:
  - `make check128-payloads`, `tools/check_c128_md128.py`, `tools/report_memory_budgets.py`,
    `make test128` (incl. `test_memory128`, `catalog_spawn_smoke`, `cache_survival_smoke`,
    and scripted smokes), and `make test128-cartridge`.
```

### 2. Verification Matrix Status (`C128M-014`, 2026-11-16)

- **Any C128 layout change**: `Default` (`moria128.prg`) `$1C01-$AE7E` (`37,501 B`, **`130 B` free** `< $AF00`) disk / `$1C01-$AA37` (`36,406 B`, **`1,225 B` free**) cart; `128.play` `$AF00-$CF0E` (`8,206 B`, **`242 B` free** `< $D000`); `128.persist` `$AF00-$C029` (`4,393 B`, **`4,055 B` free**); `128.bank` `$F000-$FEC8` (`3,784 B`, **`56 B` free** `< $FF00`); `128.runtime` `19 B` free; `128.fdisk` `46 B` disk / `13 B` cart; `Bank1High` `$D000-$DF37` (`3,896 / 4,096 B` used, **`200 B` free**).
- **Overlay/cache/load/copy change**: All 12 `$E000-$EFFF` overlays and Bank 1 cache slots fit (`ovl.storage` `3 B` free at `$EFFD`, `cache.ovl.disarm` `14 B` free, `ovl.death` `24 B` free at `$EFE8` and cached at `$C000-$CFFF`, `ovl.items` `37 B` free, `cache.ovl.modal` `39 B` free, `ovl.home` `65 B` free, `ovl.start` `68 B` free, `ovl.ui` `73 B` free, `ovl.gen` `76 B` free, `ovl.town` `80 B` free, `ovl.help` `80 B` free, `ovl.chest` `81 B` free). Media: `.d64` **`99` blocks free**, `.d71` **`763` free**, `.d81` **`2,595` free**, `.crt` **`30/32` MD128 slots** (`121,745 B` free).
- **Broad banking/MMU/runtime-loaded change**: Verified by `check_c128_payloads.py --both`, `check_c128_md128.py`, `report_memory_budgets.py` (`0` overflows), `make test128`, `make test128-cartridge`, and `make playtest-gate`.
- **Physical VDC change**: N/A.
- **Shared payload composition**: Verified across all 7 ports + 5 cartridges in Phase 5 integration (`42f8f7e7`).

## Change Record — Zero-Disk Hot Gameplay Residency & 16 KB VDC `ITEM.CAT` Preload (`C128M-015`, 2026-11-16)

### 1. Protocol Change Record (`BEHAVIOR_CHANGE_PROTOCOL.md`)

```text
Problem and success criteria:
  Eliminate all gameplay floppy disk seeks on C128 disk builds (`.d64`/`.d71`/`.d81`)
  across normal movement, `Shift+dir` running, `o`/`c` doors (plain, stuck, and
  locked `door_pick_roll`), floor trap stepping (`trap_trigger`), and `g` item
  pickup (plus all `ITEM.CAT` item/ego catalog lookups across inventory, equipment,
  drop, wear, and stores) using native C128 Bank 0 RAM, Bank 1 RAM, and 16 KB VDC
  RAM only (`reu_present = 0` permanently on C128). Prove `0` calls to `w_open`,
  `w_load`, and `overlay_load_disk` after level entry in an automated C128 `.d71`
  runtime smoke test.

State being changed:
  - C128 disk `ITEM.CAT` backing store: moved from on-demand 1541/1571/1581 `U1`
    sector streaming (`common/item_catalog_records.s` + `ITEM.IDX`) to boot-preloaded
    physical 16 KB VDC RAM (`$1100-$1fff` + cell scanlines `8..15` at `$2008-$3c6d`,
    `platforms/commodore/c128/item_cat_vdc128.s`).
  - C128 code residency: `item_pickup` moved from uncached `StorageOverlay`
    (`OVL_STORAGE = 12`) to Bank 0 `Default` (`< $af00`), retiring
    `HAL_PLATFORM_ITEM_PICKUP_OVERLAY` and `tramp_item_pickup` on C128;
    `run_initialize` (`run_initialize_impl`) moved from `ModalMiscOverlay` (`OVL 9`)
    to Bank 0 `Default` (`< $af00`).
  - Zero gameplay formula, RNG, monster AI, turn-consumption, or save-format changes.

Search scope and terms:
  Searched `platforms/commodore/c128/`, `platforms/commodore/common/`, `core/`,
  `tools/`, and `playtest/` for `hal_item_cat_read_byte`, `item_catalog_records`,
  `ITEM.IDX`, `ITEM.CAT`, `HAL_PLATFORM_ITEM_PICKUP_OVERLAY`, `tramp_item_pickup`,
  `run_initialize`, `door_try_open`, `door_pick_roll`, `trap_trigger`,
  `vdc_set_update_addr`, `RVSD_SCRATCH`, `$ff62`, and `vdc_screenshot`.

Relevant readers/writers found and known exclusions:
  - Bank 1 `$4000-$730b` (`13,068 B`) was verified to be 100% live (`198x66` map in
    `hal/layout.s` and `save_map_span_c128`), so placing `ITEM.CAT` permanently in
    Bank 1 `$4f00-$730b` was rejected to prevent map/save corruption.
  - Physical VDC `$3000-$3fff` bytes `0..7` per cell were verified to be live Set 1
    mixed-case glyphs (`VDC_ATTR_MODE = $80` and `playtest` `vdc_screenshot`), while
    bytes `8..15` of all `512` character cells in `$2000-$3fff` (`4,096 B`) plus
    `$1100-$1fff` (`3,840 B`) are never read or written after `$ff62` `JDLCHR`.
  - `C128_CARTRIDGE` continues to use `hal_item_cat_cart_read_byte` (`< $8000`)
    directly from MD128 External Function ROM; `item.cat` remains on C128
    shipping/test disk images (`item.idx` is retired from C128 disk images).

Initialization, reset and persistence points:
  - Cold boot (`restart_entry` -> `c128_load_core_residents`): runs strictly AFTER
     both `c128_prepare_startup_loading_screen` and the test-variant
    `c128_restore_vdc_rom_font` (`$ff62` `JDLCHR`) calls, loads `"ITEM.CAT"` with
    `crl_sa = 0` into Bank 1 `MAP_BASE` (`$4000-$5d35`), validates `'ITM2'`, and
    streams `7,478 B` into VDC `$1100-$1fff` + `$2008-$3c6d` before title art or
    dungeon generation uses `MAP_BASE`.
  - Soft restart (`game_restart` -> `title_enter_menu`): skips `JDLCHR`, preserving
    the preloaded VDC `ITEM.CAT` across unlimited sessions.

Affected production sequence through the changed transition:
  Boot preload (`20/20` files) -> `c128_load_item_cat_vdc` -> title -> chargen ->
  town -> `>` DL 1 `198x66` generation -> `player_try_move` / `Shift+dir`
  (`run_initialize` + `run_step`) / `o` & `c` (`OVL_HELP` + `OVL_DISARM` Bank 1
  cache) / `trap_trigger` / `g` (`item_pickup` + VDC `hal_item_cat_read_byte`).

Contract decision or selected upstream oracle with source locations:
  Port-local C128 memory/VDC residency change `C128M-015` (`memory128.s`,
  `item_cat_vdc128.s`, `main.s`). Gameplay behavior is unchanged (`N/A` upstream).

Intentional Moria8 deviations:
  None — player-visible strings, UI, and gameplay rules are 100% unchanged.

Input/intermediate widths, signedness, carry, range and overflow policy:
  `vdc_item_cat_map_addr` maps unsigned 16-bit `off` (`0..7477 < $1d36`):
  - `off_hi < $0f`: `vdc = $1100 + off` (`$1100..$1fff`, no carry out).
  - `off_hi >= $0f`: `rel = off - $0f00` (`$0000..$0e35`), `S = rel >> 3` (`0..454`),
    `B = rel & 7`: `asl` shifts bit 4 of `S` into `C`, preserved across `ora`/`tay`/
    `lda` into `rol`, then `ora #$20` -> `$2008..$3c6d <= $3fff`.

RNG reduction and bias, if applicable:
  N/A — zero RNG calls added, removed, or reordered.

Affected platforms, overlays, banks and owners:
  Commodore 128 only (`platforms/commodore/c128/**`, `docs/C128_MEMORY_CONTRACT.md`,
  `C128_ENTRIES` in `tools/trampoline_manifest.py`). Zero changes to `core/`,
  C64, Plus/4, or non-Commodore ports.

Required production-path tests:
  `make check-hal-boundaries`, `check_c128_payloads.py --both`,
  `check_c128_md128.py`, `check_overlay_calls.py --port c128 --check-sym`,
  `item_desc128`, `cache_survival_smoke`, `hot_path_zero_disk_smoke`,
  `make test128` (including `test128-cartridge`), and `make test128-legal`.

Known behavior explicitly out of scope:
  Cold modals/commands (`w` wear, `t` takeoff, `E` eat, `q` quaff, `Shift+X`
  exchange in `ovl.storage`; `ovl.home`; `ovl.chest`; `ovl.start` on New Game)
  remain in their existing segments (`ITEM.CAT` reads inside them are now 0-disk).

Unresolved uncertainty and risk:
  None; `C128M-015` recorded as `Proposed` pending maintainer review.
```

### 2. Required CPU-Memory Change Record (`C128M-015`)

```text
symbol/payload and linked segment:
  - `item_cat_vdc128.s` (`vdc_item_cat_map_addr`, `hal_item_cat_read_byte`,
    `c128_load_item_cat_vdc`), `item_pickup` (`core/item.s`), and `run_initialize`
    (`run_initialize_impl`, `core/player_run.s`) linked in Bank 0 `Default`
    (`moria128.prg`, `$1c01..<$af00`).
  - Retires `item_catalog_records.s`, `c128_load_item_idx_prg`,
    `c128_copy_item_idx_data`, and `tramp_item_pickup` from `Default`.

PRG load header:
  - `moria128.prg`: `$1c01` (`$1c01-$adb2` disk = `334 B` free `< $af00`;
    `$1c01-$ab7d` cart = `899 B` free `< $af00`).
  - `item.cat`: `$7400` on disk (`7,480 B` = 2 B header + `7,478 B` `'ITM2'`),
    loaded at boot with `crl_sa = 0` (`SETLFS` `SA=0`) to relocate into Bank 1
    `MAP_BASE` (`$4000-$5d35`).

source and destination spans:
  - Boot disk load: `"ITEM.CAT"` -> Bank 1 `$4000-$5d35` (`7,478 B`, inside
    `$4000-$730b` `MAP_BASE` prior to title/dungeon map use) -> streamed via
    `mmu_safe_map_read_ptr0` into 16 KB VDC RAM (`$1100-$1fff` + `$2008-$3c6d`).
  - Cartridge: `hal_item_cat_read_byte` jumps to `hal_item_cat_cart_read_byte`
    (`< $8000` in `cartridge_copy.s`), reading `CART_ASSET_ITEM_CATALOG` directly
    from External Function ROM.

source/destination bank and lifetime:
  - Code (`item_pickup`, `run_initialize`, `hal_item_cat_read_byte`): Bank 0
    `Default` (`< $af00`), permanent session lifetime.
  - `ITEM.CAT` data (disk): Bank 1 `$4000-$5d35` transient during boot preload
    only; physical 16 KB VDC RAM (`$1100-$1fff` + `$2008-$3c6d`) permanent across
    the entire session and `game_restart` cycles.

MMU/$01 configuration at load, copy, execution and return:
  - `c128_load_item_cat_vdc` loads via `c128_load_runtime_prg` (`SETBNK(1,0)`,
    `EnterKernal`/`ExitKernal`), then reads Bank 1 `$4000-$5d35` from Bank 0
    `Default` via bottom-common `mmu_safe_map_read_ptr0` (`$7f` -> `$3e`), writing
    `$d600/$d601` under `MMU_ALL_RAM` (`$3e`, I/O visible) and `sei`.
  - `hal_item_cat_read_byte` executes in Bank 0 `Default` under `MMU_ALL_RAM`
    (`$3e`, `$01 = $36`, I/O visible) wrapped in `php / sei / ... / plp`,
    preserving `X`, all ZP, and MMU state.

common-RAM and interrupt/vector assumptions:
  - Zero bottom/top common-RAM edits; all Bank 1 staging reads use existing
    `mmu_safe_map_read_ptr0` (`$0c06+`), and all VDC transactions mask IRQs via
    `php / sei / ... / plp`. Zero new ZP bytes used.

KERNAL transition path:
  - Boot `"ITEM.CAT"` load uses `c128_load_runtime_prg` (`w_setnam`/`w_setlfs`/
    `w_load` below `$4000`, `crl_sa` restored to `1` on exit). Runtime gameplay
    `hal_item_cat_read_byte`, `item_pickup`, and `run_initialize` perform **zero**
    KERNAL transitions.

overlapping owners and guarding assertions:
  - `memory128.s`: asserts `VDC_SCRATCH_END < VDC_ITEM_CAT_LO_BASE` (`$10ff < $1100`),
    `VDC_ITEM_CAT_LO_END < VDC_CHARSET_BASE` (`$1fff < $2000`), cell tail offset `8`
    + `8 == 16`, and `VDC_CHARSET_END == $3fff`.
  - `dungeon_render_vdc.s` & `main.s`: assert `RVSD_SCRATCH_ATTR + VIEWPORT_W <= $1100`,
    `ITMCAT_TOTAL_SIZE <= VDC_ITEM_CAT_TOTAL_CAP` (`7,478 <= 7,936`),
    `MAP_BASE + ITMCAT_TOTAL_SIZE - 1 <= MAP_END`, and `item_pickup` &
    `run_initialize` inside `$1c01..program_end <= $af00`.
  - `io_contracts.s`: `C128AuditBelowIo` on `item_pickup`, `run_initialize`, and
    `hal_item_cat_read_byte`.

production runtime test:
  - `hot_path_zero_disk_smoke` (real `.d71` boot -> chargen -> town -> `>` DL 1
    `198x66` generation -> normal moves, `Shift+L` corridor run, `o`/`c` plain door,
    `o` locked door `door_pick_roll`, floor pit `trap_trigger`, and `g` non-gold
    ego item pickup with `w_open`, `w_load`, and `overlay_load_disk` breakpoints
    proving `0` disk calls and verifying VDC-decoded `ITEM.CAT` item text in
    Bank 1 `msg_history`).
```

### 3. Physical VDC Contract Record (`C128M-015`)

```text
active VDC register(s):
  Regs `18`/`19` (Update Address Hi/Lo via `vdc_set_update_addr`) and Reg `31`
  (VRAM Data Read/Write via `vdc_select_reg` / `vdc_read_reg` / `VDC_DATA_REG`).

internal source and destination addresses:
  - `ITEM.CAT[0..3839]` (`off = $0000..$0eff`): linear VDC `$1100..$1fff`.
  - `ITEM.CAT[3840..7477]` (`off = $0f00..$1d35`, `rel = off - $0f00`, `S = rel >> 3`
    in `0..454`, `B = rel & 7`): cell-tail VDC `$2000 + 16*S + 8 + B`
    (`$2008..$200f, $2018..$201f, ..., $3c68..$3c6d`).

screen/attribute base and row stride:
  Unchanged (`VDC_SCREEN_BASE = $0000`, `VDC_ATTRIB_BASE = $0800`, stride `80`;
  scroll-delta scratch `$1000-$10cd < $1100`; Set 0 `$2000` & Set 1 `$3000` live
  glyph scanlines `0..7` at `cell*16 + 0..7` untouched).

copy direction, length, and overlap policy:
  CPU -> VDC streaming write at boot (`3,840 B` continuous auto-increment at
  `$1100`, then `455` 8-byte cell-tail bursts reseeded every 8 bytes so bytes `0..7`
  of every character cell are skipped); single-byte CPU <- VDC read via Reg `31`
  during gameplay. Disjoint by construction and compile-time `.assert`s from screen,
  attributes, scroll-delta scratch, and 8x8 glyph rasters.

ready-polling and interrupt assumptions:
  Every `$d600` register select and `$d601` data access polls `$d600` bit 7
  (`vdc_wait`) under `php / sei / ... / plp`. All screen/viewport callers re-establish
  Regs `18`/`19` inside their own `sei` critical sections and never call
  `item_catalog.s` mid-stream.

horizontal/vertical bound equivalence:
  Scroll-delta horizontal scratch (`RVSD_SCRATCH_CHAR = $1000`,
  `RVSD_SCRATCH_ATTR = $1080`, end `$10cd`) and vertical row copies (`$0000-$0fcf`)
  both remain strictly below `$1100`.

production runtime test:
  `item_desc128` (all 361 item names + ego suffixes decoded from live `x128` VDC RAM
  with Set 0/Set 1 glyph scanline `0..7` sentinel verification),
  `vdc_scroll_delta128`, and `hot_path_zero_disk_smoke`.
```

### 4. Verification Matrix Status (`C128M-015`, 2026-11-16)

- **Any C128 layout change**: `Default` (`moria128.prg`) `$1c01-$adb2` (`37,297 B`, **`334 B` free** `< $af00`, `+179 B` vs baseline) disk / `$1c01-$ab7d` (`36,732 B`, **`899 B` free**) cart; `128.play` `$af00-$cef4` (**`268 B` free**, `+35 B`); `cache.ovl.modal` `$e000-$e433` (**`205 B` free**, `+166 B`); `ovl.storage` `$e000-$ef21` (**`223 B` free**, `+220 B`).
- **Overlay/cache/load/copy change**: Verified by `check_c128_payloads.py --both`, `check_c128_md128.py`, `check_overlay_calls.py --port c128 --check-sym`, `cache_survival_smoke`, and `hot_path_zero_disk_smoke`.
- **Broad banking/MMU/runtime-loaded change**: Verified by `make check-hal-boundaries`, `make test128` (including `test128-cartridge`), and `make test128-legal`.
- **Physical VDC change**: Verified by `item_desc128`, `vdc_scroll_delta128`, and `hot_path_zero_disk_smoke`.
- **Shared payload composition**: N/A (`core/` and shared Commodore files untouched).

## Change Record — Catalog Placement Into `128.play` (`C128M-016`, 2026-11-20)

```text
symbol/payload and linked segment: catalog_place_win_creature $af03,
  catalog_place_wanderer $af05, catalog_place_far $af06-$af6b in
  C128ResidentPlay (128.play.prg), formerly Bank 0 Default ($6a6a-$6ad3)
PRG load header: build/c128/128.play.prg starts 00 af, then 4d 38 50 ("M8P",
  c128_resident_play_sig0..2) and the catalog code at $af03
source and destination spans: 128.play.prg $af00-$cf1e (226 B to $d000) loaded
  to Bank 0 $af00 by the existing play loader / cartridge copy; unchanged path
source/destination bank and lifetime: Bank 0, the play payload's lifetime
  (reloaded after every 128.persist modal before main_loop resumes)
MMU/$01 configuration at load, copy, execution and return: unchanged play-slot
  loader; executes in Operational Bank 0 (MMU_ALL_RAM $3e) like the rest of
  128.play; calls Bank 0 Default (find_monster_floor, pick_creature_type,
  catalog_slot_for_id, monster_spawn_awake) and returns there
common-RAM and interrupt/vector assumptions: none new; no banking inside
KERNAL transition path: catalog_slot_for_id's species fetch reads Bank 1
  through the existing mmu_safe_db helpers, as before the move
overlapping owners and guarding assertions: 128.persist shares $af00 but never
  runs while monster_spawn_level or turn_post_action can (both reached only
  from 128.play code); main.s play-signature, play <= $d000, persist below
  main_loop/player_died, program_end <= $af00 asserts; monster.s
  "catalog_place_win_creature is called directly only below $E000"
production runtime test: make test128 (catalog_spawn_smoke and the generation
  soaks place the win creature path; turn tests run turn_post_action)
```

Verification rows: linked address `$af03-$af6b` (`build/c128/main.sym`); load
header `$af00` with the signature first (`128.play.prg`); load bank Bank 0 (play
loader, unchanged); execution bank Bank 0 `MMU_ALL_RAM`; copy safety: no copied
or staged span changed, only the play payload's contents (`check_c128_payloads`
PASS, 24 payloads). Headroom: program image `171 B` below `$af00` (product, was
`64 B`), `41 B` with `C128_TEST_TITLE_ART_CONTENT` (was `-66 B`); `128.play`
`226 B` below `$d000` (was `333 B`).

## Change Record — Gain-Stat Helpers Into `128.play` (`C128M-017`, 2026-11-26)

```text
symbol/payload and linked segment: player_step_healthy_sum_y $cad5,
  player_apply_stat_delta_y $caea in C128ResidentPlay (128.play.prg), split into
  core/6502/player_gain_stat_helpers.s behind PLAYER_GAIN_STAT_HELPERS_EXTERNAL
PRG load header: build/c128/128.play.prg starts 00 af, followed by "M8P" signature
source and destination spans: 128.play.prg $af00-$cf73 (140 B free to $d000) loaded
  to Bank 0 $af00 by existing play loader / cartridge copy
source/destination bank and lifetime: Bank 0, gameplay lifetime (while 128.play is
  mapped; 128.persist shares $af00 for title/save/disk-setup modals only)
MMU/$01 configuration at load, copy, execution and return: Operational Bank 0
  (MMU_ALL_RAM $3e); called from eff_gain_stat.s (StorageOverlay $e000) during active
  play and calls/jumps only into Bank 0 Default (pses_zero_res_write_y,
  pses_write_cur_y, player_step_equip_stat_y)
common-RAM and interrupt/vector assumptions: N/A (zero common-RAM or vector change)
KERNAL transition path: N/A (pure stat arithmetic, zero KERNAL calls)
overlapping owners and guarding assertions: 128.persist shares $af00 but never
  invokes eff_gain_stat.s; main.s asserts program_end <= $af00, c128_resident_play_end
  <= $d000, and player_step_healthy_sum_y >= c128_resident_play_body &&
  player_step_healthy_sum_y < c128_resident_play_end &&
  player_apply_stat_delta_y >= c128_resident_play_body &&
  player_apply_stat_delta_y < c128_resident_play_end; check_c128_payloads.py --both
production runtime test: make test128 (incl. vic40_blanked_boot_smoke,
  boot_title_load_then_save_new_empty_smoke, chest_open_product_smoke128)
```

## Change Record — Internal 256KB MMU Expansion Support (`C128M-018`, 2026-11-27)

### 1. Protocol Change Record (`BEHAVIOR_CHANGE_PROTOCOL.md`)

```text
Problem and success criteria:
  Detect internal 256KB C128 MMU RAM upgrades (4×64KB banks selected via $FF00
  bits 7-6, matching VICE x128 -c128fullbanks), display the detected capacity on
  the Title bottom sysinfo line and About/Shift+V System Info screen, and use
  Bank 2 on 256KB disk builds to preload all remaining cold overlays plus
  LEGALUI, 128.PLAY, and 128.PERSIST at boot so single-drive users require zero
  Program Disk swaps across gameplay, Shift+V, Disk Setup, Save, Load, and Game
  Over/Retirement (Title A / ? -> L still reads uncached LICENSE/SOURCE-OFFER
  from Program Disk). Cartridge builds detect and display 256KB while
  continuing to stream assets from MD128 ROM.
State being changed:
  c128_ram_256k (hal_platform_256k_present), c128_xbank_cr, c128_bank2_flags,
  bank_overlay_cache_mmu, 13-entry bank1_overlay_cache_slot_{lo,hi} /
  bank1_overlay_cache_pages, ovl_ready_mask_hi bits 1-3 for IDs 10-12,
  c128_load_progress_total (20 vs 26), and title/sysinfo VDC display lines. No
  save-file format, monster/item schema, RNG, or Bank 1 allocation changes.
Search scope and terms:
  Searched platforms/commodore/c128/, platforms/commodore/common/, core/6502/,
  and docs/ for MMU_RAM_BANK, bank1_overlay_cache, ovl_ready_mask_hi,
  c128_modal_require, disk_prompt_game, c128_load_runtime, and title_sysinfo.
Relevant readers/writers found and known exclusions:
  Updated core/6502/game_loop.s (HAL-gated game-over disk prompt hook),
  core/6502/title_sysinfo_banked.s, platforms/commodore/c128/ (memory128.s,
  hal/lifecycle_policy.s, io_contracts.s, main.s, legal.s, legal_sysinfo.s,
  tests/test_memory128.s, test_cartridge.py, run_tests128.sh),
  platforms/commodore/Makefile, and platforms/commodore/common/overlay.s.
  Stock 128KB behavior, REU paths, and non-C128 ports remain unchanged.
Initialization, reset and persistence points:
  restart_entry calls c128_detect_256k right after :MachineRestoreAllRam()
  (top+bottom 4KB common RAM active, $D506=$0D) and clears c128_bank2_flags;
  title screen preload populates Bank 1/2 overlay caches and calls
  c128_preload_bank2_extras; warm restart (restart128.s -> game_restart) jumps
  straight to title_enter_menu, preserving the boot-detected Bank 2 caches.
  Probe address $E000 lies outside Bank 2's allocated $1000-$92FF region.
Affected production sequence through the changed transition:
  Boot -> restart_entry (c128_detect_256k) -> c128_load_core_residents ->
  c128_preload_bank2_extras -> c128_preload_all_overlays (IDs 1..12, graceful
  Bank 2 fallback) -> Title (C128  KERNAL R1  256KB) -> D)isk Setup / N)ew /
  L)oad / Shift+V / Save / Game Over / Chest / Home / Storage (zero Program
  Disk swaps once cached).
Contract decision and verification:
  See C128M-018 in the Decision Ledger above and the CPU-Memory record below.
```

### 2. CPU-Memory Change Record

```text
symbol/payload and linked segment:
  - memory128.s (Default + copied bottom-common helpers): c128_detect_256k,
    c128_ram_256k (hal_platform_256k_present), c128_xbank_cr, c128_bank2_flags,
    13-entry overlay cache tables + bank_overlay_cache_mmu,
    mmu_common_{select_bank_a,bank_read_ptr1,bank_write_ptr1}, and (disk only)
    mmu_common_xbank_{read,write}_page inside mmu_common_helpers_blob ($0c06+);
  - main.s Default + C128ResidentPlay + game_loop.s HAL hook:
    Default ($1c01-$aeac disk, 84 B free < $af00; $1c01-$ac67 cart, 665 B free)
    hosts c128_rt_tbl_* / c128_load_runtime_table_x, c128_all_runtime_cached,
    c128_b2_setup_play, c128_bank2_setup_ptrs, c128_copy_from_bank2,
    c128_b2_load_persist_and_restore_play, c128_b2_restore_and_verify_play,
    eff_fear_timer, light_tick_counter, and wizard_wall_walk_enabled (moved out
    of C128ResidentPlay via EFF_FEAR_TIMER_EXTERNAL/WIZARD_WALL_WALK_EXTERNAL);
  - RuntimeCommonData ($0d60-$0ff7 disk, 9 B free < $1000; $0d60-$0fa3 cart, 13 B free < MMU_COMMON_CART_BASE):
    hosts c128_preload_bank2_extras (disk only);
  - RuntimeBankedCode ($f000-$fefe disk, 2 B free < $ff00; $f000-$fef2 cart, 14 B free):
    hosts tramp_winner_royal;
  - C128ResidentPersist ($af00-$c04f, 4,017 B free): c128_stage_to_bank2 and
    c128_bank2_stage_persist_and_legal;
  - C128ResidentPlay ($af00-$cf7b disk, 133 B free; $af00-$cf71 cart, 143 B free):
    hal_storage_game_over_disk_prompt_game;
  - legalui ($e000-$e8ac, 1,364 B free < $ee00): legal_sysinfo.s 128KB/256KB +
    legal_os_prompt_program_media;
  - ovl.town ($e000-$efad, 83 B free): title_sysinfo_banked.s "  256KB" suffix.
PRG load header:
  moria128.prg $01 $1c; 128.persist.prg $00 $af; 128.play.prg $00 $af;
  legalui $00 $e0; overlays $00 $e0.
source and destination spans:
  Bank 0 -> Bank 2 under MMU_RAM_BANK2 ($be):
  - $e000-$efff -> Bank 2 $1000-$1fff (OVL_STARTUP), $2000-$2fff (OVL_CHEST),
    $3000-$3fff (OVL_HOME), $4000-$4fff (OVL_STORAGE), and $e000-$e9ff ->
    Bank 2 $5000-$59ff (LEGALUI, 10 pages, below legal_zp_save $ee00);
  - $af00-$cfff -> Bank 2 $6000-$80ff (128.PLAY, 33 pages) and
    $af00-$c0ff -> Bank 2 $8100-$92ff (128.PERSIST, 18 pages, strictly below
    128.PLAY mutable state at wizard_num_digits/main_loop/player_died).
source/destination bank and lifetime:
  Physical Bank 2 caches survive across gameplay, modal swaps ($af00), overlay
  swaps ($e000), and Title return; Bank 2 stays untouched on 128KB hardware and
  on MD128 cartridge builds.
MMU/$01 configuration at load, copy, execution and return:
  Common-RAM helpers execute in $0c06+ with $d506=$0d under SEI, switching
  $ff00 (from MMU_ALL_RAM $3e to $7e/$be/$fe and back to $3e) with I/O visible
  so mmu_common_nmi continues to acknowledge $dd0d safely.
common-RAM and interrupt/vector assumptions:
  Requires top+bottom 4KB common RAM ($d506=$0d); top common stays enabled so
  $fffa-$ffff vectors and KERNAL wrappers remain safe during all Bank 2 accesses.
KERNAL transition path:
  c128_preload_bank2_extras loads 128.persist ($af00) and c128_bank2_stage_persist_and_legal
  loads legalui ($e000) into Bank 0 under MMU_ALL_RAM via existing KERNAL stubs
  before staging to Bank 2 and restoring 128.play from Bank 2 with signature check.
overlapping owners and guarding assertions:
  memory128.s asserts BANK1_COMMON_END < BANK2_OVERLAY_STARTUP_BASE, pairwise
  disjoint Bank 2 spans through BANK2_PERSIST_END < BANK1_RESERVED_IO_BASE,
  33-page PLAY coverage, and 13-entry overlay table lengths (including
  bank_overlay_cache_mmu); main.s asserts Default < $af00, PERSIST pages
  <= wizard_num_digits/main_loop/player_died, Default residency for
  eff_fear_timer/light_tick_counter/wizard_wall_walk_enabled, LEGALUI pages <= legal_zp_save,
  and loader table lengths; tools/check_c128_payloads.py --both and
  tools/check_c128_md128.py enforce emitted bytes.
production runtime test:
  memory128 (stock 128KB), memory128_256k (-c128fullbanks),
  cache_survival_smoke, c128_256k_cache_smoke (blank Drive 8 zero-swap through
  setup_disk, create_character, Shift+V, save with live eff_fear_timer + light_tick_counter + wizard_wall_walk_enabled + wizard_target_depth (verified post-save after Bank 2 PLAY restore), Load,
  Game Over return, and all 12 overlays), test128-fast-smoke,
  test128-cartridge PAL+NTSC (incl. -c128fullbanks check), and make test128.
```


