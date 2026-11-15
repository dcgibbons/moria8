# 7-Port Memory Redesign & Full VMS Expansion Plan

Status: active roadmap — Phases 0–4 complete (`2026-11-15`; baseline `HEAD 3a5ca26`). Complements
`docs/MONSTER_CATALOG_DESIGN.md`, `docs/ITEM_EXPANSION_PLAN.md`,
`docs/SAVE_FILE_MIGRATION.md`, `docs/CROSS_PLATFORM_STRATEGY.md`, and each port's
memory contract (`docs/C128_MEMORY_CONTRACT.md`,
`docs/APPLE2_MEMORY_POLICY.md`, `docs/CX16_MEMORY_CONTRACT.md`,
`docs/ATARI8_MEMORY_CONTRACT.md`, `docs/BBCMASTER_MEMORY_CONTRACT.md`).

---

## 1. Maintainer Decisions & Non-Negotiable Rules (2026-11-13)

1. **Full VMS Parity Target.** Full VMS Moria 4.8 parity (`370` items, `55`
   egos, Cloak slot, `18` traps, and `279` monsters with all four attacks,
   spells, AI, and `279`-species recall) is targeted on **both** cartridge and
   disk builds. The **Enhanced Apple IIe (`128 KB`, `140 KB` ProDOS `.po`,
   disk-only)** is the tightest capacity floor. A separate cut/rebalanced
   "lite" edition is a last-resort fallback only if measured budgets prove full
   parity cannot fit.
2. **Media Posture Across All 7 Ports.**
   - **5 cartridge-primary + disk-backup ports:** Commodore 64 (`EasyFlash`
     `.crt` + `.d64`/REU; stock C64 without REU continues to ship), Commodore
     Plus/4 (`c264` magic cart `.crt` + `.d64`), Commodore 128 (`Magic Desk 128`
     `.crt` + `.d64`/`.d71`/`.d81`/REU), Commander X16 (`.crt` + `.zip`), and
     Atari 8-bit (`AtariMax` `.car` + `800XL`/`130XE` `.atr`).
   - **2 disk-only 128 KB ports:** Apple IIe (`140 KB` `.po`) and Acorn BBC
     Master 128 (`200 KB` `.ssd`; a BBC Master cartridge is **not** a target).
3. **Disk I/O During Play.** Disk loads during play are acceptable on disk
   builds for cold/modal transitions, level generation, save/load, and uncached
   catalog lookups. They are **forbidden** on per-turn movement, line-of-sight,
   rendering, status updates, and per-blow melee/ranged combat.
4. **Single Save-Format Bump.** Backward save compatibility is not required
   (resetting active playtest queue saves to DL1 is acceptable). Bundle all
   persistent schema changes into **one** coordinated Save Format V2 bump,
   accounting for fixed save-slot budgets (Atari Save Disk
   `ATARI_SAVE_SLOT_SECTORS` `56`-sector slots; C64 program/save disk slots)
   and updating `playtest/` and harness ABI readers in the same commit.
5. **Ego Count.** VMS has **`55` egos**, with `ego_id = 0` meaning "none"
   (Umoria's 56th entry is the leading `CNIL`/`SN_NULL` empty slot).
6. **Test Hooks Out of Product Images.** Move the `49` test-flag `#if` symbols
   (`177` `#if`/`#elif` lines in `core/`) to harness-side monitor writes and
   Python memory-dump assertions (following the `83a190c` pattern). A test
   variant near its ceiling is converted to harness-side seeding/checks — never
   fixed by relocating product code.
7. **Spike-Gated Legacy Constraints.** `C128M-002` (C128 Bank 1 `$D000-$DFFF`
   reserved I/O gap) and the `"ALTZP stays off"` heading in
   `docs/APPLE2_MEMORY_POLICY.md` were not maintainer rules and may be lifted
   **only** after dedicated VICE/MAME verification spikes prove
   interrupt/banking safety and update the matching contract.
8. **Hard Repo Invariants.** Never delete or weaken `.assert` guards; never
   shorten player-visible strings to recover bytes; load
   `docs/BEHAVIOR_CHANGE_PROTOCOL.md`, `docs/INTERNAL_MANDATES.md`, and matching
   memory contracts before layout edits; run `make test128` for C128 layout
   changes and `make -j7 -O test` for cross-port gates.

---

## 2. Baseline Memory & Media Ledger (`HEAD 3a5ca26`)

| Port | Always-Resident Free (Disk / Cart) | Banked / Play Slot Free | Tightest Overlay / Test Variant | Cartridge / Secondary Media Headroom | Disk Headroom |
| --- | --- | --- | --- | --- | --- |
| **C64** | `Default` `< $C000`: `76 B` disk / `926 B` cart | `64.bank` `< $FFFA`: `6 B` | `ovl.town`, `ovl.spell`: `12 B` free | EasyFlash `ROML`: about `390 KB` free (`8K` mode) | `.d64`: `194 / 664` free blocks |
| **Plus/4** | `Default` `< $C800`: `104 B` disk / `536 B` cart | `4.bank` `< $FC00`: `110 B` disk / `142 B` cart | `ovl.town`: `12 B` free | `c264` `.crt`: `142.4 KB` free | `.d64`: `242 / 664` free blocks |
| **C128** | Bank 0 sub-PRG walls: `396 B` disk / `822 B` cart; `128.play` `< $D000`: `74 B` | `128.bank` `< $FF00`: `34 B` | `ovl.help`: `12 B`, `ovl.gen`: `63 B`; `cache_survival_smoke`: `22 B` free | `MD128` `.crt`: `140.7 KB` free (`31/32` dir slots used) | `.d64`: `175` free blocks (`.d71`: `839`; `.d81`: `2,671`) |
| **CX16** | Unified Low RAM `< $9B00`: `433 B` disk / `404 B` cart | `Bank 3` (`CX16.AUXDATA`): `3,072 B` free; `Banks 5-8` (`32 KB`, tier loader gated off by `#if !HAL_PLATFORM_MONSTER_CATALOG`) + `Banks 24-63` (`320 KB`) = `352 KB` (`44` `8 KB` RAM banks) unused | `ovl.spell`: `2,350 B` free | `.crt`: `29.9 KB` free of `128 KB` (`3.5 MB` max) | `.zip`: FAT32 SD/HostFS (`make disk` sync) |
| **Atari 8-bit** | `Default` `< $C100`: `81 B` disk / `836 B` cart; `HighResident` (`$D800-$DFFF`): `2 B` tail | `ATARI.BNK` `< $FFFA`: `2 B` disk / `228 B` cart | `ovl.town`: `12 B` free | AtariMax Type 41 `.car`: `20.2 KB` free (`128 KB`; Type 42 supports `1 MB`) | ED `.atr`: `145 / 1,023` free sectors (saves on separate Save Disk); `130XE` loses about `10.2 KB` to fixed `4 KB` slot rounding |
| **Apple IIe** | `Default` `< $7C00`: `17 B` | `A2PlaySlot` `< $A000`: `66 B` | `ovl.items`: `50 B` to `$B9FF` code cap (`5,632 B`); `BANKED_DATA_END` is `$BAFF` (`5,888 B` — do not double-count `$BA00-$BAFF`) | None (disk-only) | `.po`: `14 / 280` free ProDOS blocks (`13` sapling index blocks = `6.7 KB`) |
| **BBC Master 128** | `Default` `< $8000`: `17 B` | `BeebPlaySlot` `< $A400`: `44 B`; `SWR Banks 4-7` `256/256` pages assigned; `ANDY`: `291 B` free | `ovl.items`: `550 B` free | None (disk-only) | `.ssd`: `387 / 800` free sectors (`14/31` DFS catalog entries) |

### Zero-Page & Verified Free RAM Inventory

- **Zero-Page Invariant (`core/zeropage.s`):** `$02-$8F` is full (about `1 B`
  spare). New catalog or banking helpers must reuse existing `$02-$0C` scratch
  or caller-save on the CPU stack — never allocate new persistent zero-page
  variables.
- **Verified Free Low / Hidden RAM:**
  - **Plus/4:** `$DF00-$DFFF` (`256 B`) plus `$DC75-$DCFF` / `$DCE5-$DCFF`
    tails (`0` banking cost under `$FF3F`) plus `$0400-$07FF` (`1,024 B` idle
    outside dungeon generation).
  - **C64:** `$D700-$DFFF` (`2,304 B` DRAM under I/O via `SEI` + `$01=$34`;
    keep `$DF00-$DFFF` reserved when REU I/O is active).
  - **Apple IIe:** Main `$0200-$028F` (`144 B`) and `$0300-$033B` (`60 B`), plus
    Aux `$0200-$03FF` (`512 B`) and spike-gated Aux Language Card
    (`$D000-$FFF9`).
  - **BBC Master 128:** `LYNNE` `$3F80-$43FF` (`1,152 B` unassigned below
    `$4400` Mode 0 screen base, accessible only via `< $3000` helpers with
    `ACCCON X=1`).
  - **C128:** VDC `$1100-$1FFF` (`3,840 B` unused; `$2000-$2FFF` is primary
    charset).

---

## 3. Rejected Proposals & Technical Traps (Do Not Revive)

| Rejected / Corrected Idea | Root Cause & Exact Repo Citation | Replacement Direction |
| --- | --- | --- |
| **Cold-paging `it_weight` / `it_dmg_packed` without caching** | `core/combat.s` (`L274`, `L490`, `L605`, `L688`) reads `it_weight` and `it_dmg_packed` on every melee blow; `core/inv_add.s` (`L83-L94`) walks carried `it_weight` on pickup. Cold reads without caching would cause disk I/O mid-combat on 1541/800XL/Apple IIe. | Cache wielded weapon stats at equip time and maintain a 16-bit running carried `inven_weight` before evicting cold item fields. |
| **Generic runtime `hal_overlay_call` caller stack** | Encourages accidental cross-overlay disk ping-pong and pushes call arguments into full zero page (`$02-$8F`). | Generate `tramp_*` stubs from one declarative manifest and statically forbid cross-overlay calls. |
| **AtariMax `$A000-$BFFF` XIP** | `platforms/atari8/cartridge_copy.s` switches Bank 0 (`CART_DIRECTORY`) and asset banks into the sole `$A000-$BFFF` window on every `cart_read`, unmapping XIP callers. | Keep the Atari copy/stream model (`cart_read` below `$A000`). |
| **C64 EasyFlash `16K` (`ROMH`) mode** | About `390 KB` of `ROML` is already free in `8K` mode; `16K` mode unnecessarily hides `$A000-$BFFF` resident RAM on every read. | Stay in `8K` `ROML`-only EasyFlash mode. |
| **Unified `huff_str_data` (`3,197 B`) in C64 `$D700-$DFFF` (`2,304 B`)** | `huff_str_data` exceeds the `2,304 B` window by `893 B`. | Use C64 `$D700-$DFFF` for smaller helper-gated tables (`recall`, `si_*`). |
| **Raw `CATALOG_NAME_POOL` in BBC `LYNNE` (`$3F80-$43FF`)** | `core/monster_catalog.s:237` stores raw `cr_name_lo/hi` pointers dereferenced from `$3000-$7FEF`, which `ACCCON X=1` unmaps. | Keep `CATALOG_NAME_POOL` accessible to `$3000-$7FEF`; put helper-indexed tables (`recall`, `si_*`) in `LYNNE` via `< $3000` accessors. |
| **C128 VDC `$2000-$2FFF` overlay cache** | Rewritten by `JDLCHR` (`platforms/commodore/c128/main.s:885-892`) and boot art; only `$1000-$1FFF` is documented unused. | Use VDC `$1100-$1FFF` (`3,840 B`) only if needed. |
| **BBC Master Sideways ROM cartridge** | Explicitly dropped per maintainer decision (2026-11-13). | Keep BBC Master 128 on `.ssd` only. |
| **Active-level item template cache (mirroring `monster_catalog.s`)** | Up to `204` concurrent items across pack (`34`), `8` stores (`128`), and floor (`42`) span too many distinct templates and would thrash in town and vaults. | Split hot resident lookup bytes from paged cold item definition/name data (`ITEM.CAT`). |

---

## 4. Core Architecture & Schema Design

### 4.1 Hot Residency Law & Measured Hot/Cold Data Split

- **Per-Turn Hot Residency Law:** `main_loop`, `turn`, `player_move`/`run`,
  `combat` (excluding level-up), `monster_ai`, `monster_attack`,
  `monster_magic`, `dungeon_los`, `dungeon_render*`, `ui_status`, hot strings,
  `input`, and `sound` must never trigger overlay swaps or disk I/O.
- **Equip-Time & Running-Total Caching:** Before evicting cold item definition
  tables from resident RAM, cache wielded weapon combat fields (`weight`,
  `dmg_packed`, `missile_class`) in resident variables updated at
  equip/swap/recalc time, and maintain carried `inven_weight` as a 16-bit
  running total updated on pickup, drop, consume, and equip transitions.
- **Resident Item Hot Tables:** Keep hot render/type tables (`it_category`,
  `it_color_ac`, `it_unknown_idx`) resident.

### 4.2 Trampoline Manifest, Overlay Boundaries & Preprocessor Debt

- **Declarative Trampoline Manifest:** Generate the roughly `470` `tramp_*`
  stubs (`52-78` per port `main.s`) from a single declarative manifest, and
  enforce a static checker forbidding cross-overlay calls without returning to
  resident code.
- **Eliminate Stack-Probing Overlay Hacks:** Replace `$0102,x` / `$0104,x`
  stack return-address probing and direct `MMU_ALL_RAM` writes in
  `core/player_items.s:113-176` with the existing explicit `piw_return_overlay`
  mechanism.
- **Clean Overlay Boundaries:** Split `ovl.home` (`home_*` + `ui_home_text`) out
  of `ovl.town`, and evict cold `save.s` / `title` paths into dedicated
  overlays where resident budgets require it.
- **Actual Preprocessor Coupling:** `tools/check_hal_lifecycle_exports.py`
  enforces `40` lifecycle constants (`1` numeric), while `core/` uses about
  `202` distinct symbols across `817` `#if`/`#elif` lines (`0` `#if CARTRIDGE`).
  Keep the deliberate Apple IIe and BBC Master `InvAddCarriedBody` overlay
  copies intact until Phases 1-2 free resident headroom.

### 4.3 Item Schema Above 255 & 55 Egos (Phase 4 Design Record Scope)

Phase 4 requires its own approved schema design record choosing between an
`(ID, category-page)` representation and `16-bit` IDs before code edits begin.
Any design must satisfy all four constraints:

1. Update all `58` direct `it_*,x/y` 8-bit indexed reads in `core/` (`32` of
   which read `it_category`).
2. Prevent `FI_EMPTY = $FF` collision with item ID `255` (for example, when using
   a page bit, reserve `$FF` on every page so `0..254` provides `510` slots for
   `370` VMS items; or introduce a 16-bit empty sentinel).
3. Respect `FLOOR_ITEM_BASE` (`252 / 256 B` in `core/item.s:20-35`, bordered by
   BBC `$0500` and Atari `$DD00`): place any floor ego/page extension as a split
   sidecar beside `fi_to_hit` / `fi_to_dam` / `fi_to_ac` (`core/item.s:55-59`),
   never inside `FLOOR_ITEM_BASE`.
4. Pack any inventory high/page bit into `inv_ego`'s `2` unused bits (`55` egos
   fit in bits `0..5`) rather than adding a 9th `inv_id_hi` array — preserving
   `7 * 34 = 238 < 256` (`core/item_exchange.s:14`) when adding the Cloak slot
   (`33 -> 34`) — and co-update `playtest/moria_playtest/disk.py:367-368` plus
   harness ABI readers in the same commit.

---

## 5. Port-by-Port Memory Unlocks & Evictions

- **Commander X16:** Allocate unused `$A000-$BFFF` RAM banks (`Banks 5-8` plus
  `Banks 24+`) for warm/cold code and extended catalog tables via a small
  Low-RAM (`< $9B00`) `$00`-preserving bounce helper; split `279`-species
  `MONSTER.CAT` across `Bank 22` (`21` fields, `5,976 B`) and `Bank 5` (`8` new
  fields, `2,232 B`) so neither bank exceeds `8,192 B`.
- **Commodore Plus/4:** Claim `$DF00-$DFFF` (`256 B`) and the `$DC75-$DCFF` /
  `$DCE5-$DCFF` tails directly under `$FF3F`; use `$0400-$07FF` (`1,024 B`,
  idle outside dungeon generation) as a disk catalog LRU cache; evict
  `save.s`, `title`, and `home_*` from `Default` / `4.bank`.
- **Commodore 64:** Use `$D700-$DFFF` (`2,304 B`) via `SEI` + `$01=$34` helper
  accessors for small state tables (`recall`, `si_*`), keeping `$DF00-$DFFF`
  clear when REU I/O is active; evict `save.s` -> `ovl.save`, `title` ->
  `ovl.title`, and `home_*` -> `ovl.home`; keep EasyFlash in `8K` `ROML` mode
  (about `390 KB` free).
- **Commodore 128:** Merge Bank 0 sub-PRG walls (`$6000`, `$8C50`, `$A800`,
  `$AB00`) under a `docs/C128_MEMORY_CONTRACT.md` change record documenting why
  `$6000` existed and replacing (never deleting) boundary `.assert`s; optionally
  cache an overlay in VDC `$1100-$1FFF` (`3,840 B`) and/or run a VICE spike on
  lifting `C128M-002` (Bank 1 `$D000-$DFFF` under `_NOIO`) if Bank 1 overlay
  caching needs another `4 KB`.
- **Acorn BBC Master 128:** Keep `.ssd`-only; add a `< $3000` `SEI` +
  `ACCCON X=1` accessor to store helper-indexed state (`recall[279]` `1,116 B`
  or `si_*`) in `LYNNE` `$3F80-$43FF`, and ensure all `< $3000` `ROMSEL` helpers
  sync `$00F4`.
- **Atari 8-bit:** Replace `130XE` fixed `4 KB` slot rounding with page-packed
  bank allocation (recovering about `10.2 KB`); keep the AtariMax copy/stream
  model (upgrading `.car` from Type 41 `128 KB` to Type 42 `1 MB` only when
  packed assets exceed `128 KB`, preserving `GINTLK`/`TRIG3` parking in
  `platforms/atari8/cartridge_copy.s:257`); evict `save.s`, `title`, and
  `home_*` on `800XL`; adjust Save Disk `ATARI_SAVE_SLOT_SECTORS` during the
  single save bump.
- **Enhanced Apple IIe:** Claim Main `$0200-$028F` (`zp_save_buf` `142 B`) and
  `$0300-$033B` (`60 B`) plus Aux `$0200-$03FF` (`512 B`); fold standalone `.po`
  sapling files into packed `MORIA8.PAK` (`MLI_SET_MARK`) to reclaim about `16`
  sapling index/tail blocks on the `140 KB` `.po`; run a standalone MAME
  `apple2ee` spike for a `SEI`, ZP-free `ALTZP=1` Aux Language Card
  (`$D000-$FFF9`) data-only copier with port-owned Aux interrupt vectors
  (`$FFFA-$FFFF`) before adopting Aux LC in `docs/APPLE2_MEMORY_POLICY.md`.

---

## 6. Phased Execution Roadmap & Verification Gates

| Phase | Status | Scope & Deliverables | Primary Verification Gate |
| --- | --- | --- | --- |
| **Phase 0** | **Complete** | **Measure, De-Hook Tests & Spec Save Bump:** Build `tools/report_memory_budgets.py` covering every product binary, overlay, disk/cart image, and test variant from `.sym` files; migrate tight in-image test hooks (`49` symbols in `core/`, starting with C128 `cache_survival_smoke` at `22 B`) to monitor writes + Python checks (`83a190c` pattern); draft Save Format V2 spec; fix stale notes in `docs/FEATURE_MAP.md:110` (Plus/4 `$FC00` ceiling and TED range) and `platforms/commodore/c64/main.s:1376,2065` (`$01=$34` comments). | Budget script + `make test128` + `make test64` + `make testplus4` |
| **Phase 1** | **Complete** | **Port-Local Memory Unlocks (Zero `core/` Churn):** CX16 RAM banks -> Plus/4 `$DF00` + `$DCxx` tails -> C64 `$D700-$DFFF` helpers -> C128 Bank 0 wall merge (+ optional `C128M-002` VICE spike) -> BBC `LYNNE` accessor + `$00F4` sync -> Atari `130XE` page-packing -> Apple `$0200`/`$0300` + `.po` PAK consolidation + MAME Aux LC spike. | Per-port contract checkers + runtime/cartridge gates (`make testcx16`, `make testplus4`, `make test64`, `make test64-cartridge`, `make test128`, `make testbbcmaster`, `make testatari8`, `make testapple2-runtime`) |
| **Phase 2** | **Complete (`2026-11-14`)** | **Per-Port Cold Code Eviction:** Evict `save.s`, `title`, `home_*`, and cold setup/wizard paths per port using existing trampolines; verify headroom growth with `tools/report_memory_budgets.py`. | `make -j7 -O test` + cartridge smoke gates |
| **Phase 3** | **Complete (`2026-11-14`)** | **Declarative Trampoline Manifest & `piw_return_overlay` Cleanup:** Generate `tramp_*` across all 7 ports from one manifest, enforce static cross-overlay call ban, remove `core/player_items.s` `$0102` stack probing and direct `MMU_ALL_RAM` write. | `make -j7 -O test` |
| **Phase 4** | **Complete (`2026-11-15`)** | **Item Schema, 370 Items, 55 Egos, Cloak Slot & 18 Traps:** Approve item ID schema record -> land equip-time weapon stat cache + running `inven_weight` -> land `ITEM.CAT` paging + `370` items + `55` egos + Cloak + `18` traps + Save Format V2 bump + `playtest/`/harness ABI updates + `docs/WIZARD.md` & `docs/FEATURE_MAP.md` updates. | `make check-item-docs`, `make playtest-selftest`, `make -j7 -O test` |
| **Phase 5** | Pending | **Full Monster Parity (`279` Species, Full Abilities & `recall[279]`):** Expand `MONSTER.CAT` (`+2,232 B`, split across CX16 Banks 22 & 5), implement missing `ATK_*`, `CSPELL`, and `CM_*` behaviors, expand `recall` to `279` species, enable `279/279` in `cat_available`. | `make -j7 -O test` + `make playtest-smoke` |

### Phase 2 Completion Status (`2026-11-14`)

Phase 2 cold code eviction is complete across all 7 ports (`0` product overflows in `tools/report_memory_budgets.py`). Wave 1 standardized `HOME_OVERLAY_SEPARATE` (`OVL_HOME = 11`) and `SAVE_IN_STORAGE_OVERLAY` (`OVL_STORAGE = 12`, `OVL_TITLE = 13`) in shared/Commodore code while leaving `SAVE_IN_STORAGE_OVERLAY` **OFF** on C128 (where `save.s` remains in `128.persist` with `3,692 B` free).

| Port | Resident / Play Free (Before -> After) | Banked / Cache Free (Before -> After) | New & Rebalanced Overlays (Size / Free) | Shipping Media / Extended Banks |
| --- | --- | --- | --- | --- |
| **C64** | `Default (< $C000)`: `340 B` -> **`1,866 B`** (`$B8B6`, `+1,526 B`) disk; `1,074 B` -> **`2,637 B`** (`$B5B3`, `+1,563 B`) cart; `SaveResidentStateProbe` <= `$A000`: **`1,104 B`** disk / **`1,742 B`** cart free | `64.bank (< $FFFA)`: `6 B` -> **`347 B`** (`$FE9F`, `+341 B`) | `ovl.home`: `919 B` / **`3,177 B`** free; `ovl.storage`: `3,593 B` / **`503 B`** free; `ovl.title`: `193 B` / **`3,903 B`** free; `ovl.town`: `12 B` -> **`123 B`**; `ovl.spell`: `12 B` -> **`223 B`** | `.d64`: `194/658` free; `.crt`: **`21`** assets (`103,501 B`), `409,600 B` free; `.zip`: **`32`** files |
| **Plus/4** | `Default (< $C800)`: `251 B` -> **`1,840 B`** (`$C0D0`, `+1,589 B`) disk; `693 B` -> **`2,293 B`** (`$BF0B`, `+1,600 B`) cart | `4.bank (< $FC00)`: `110 B` -> **`662 B`** (`$F96A`) disk; `142 B` -> **`694 B`** (`$F94A`) cart | `ovl.home`: `919 B` / **`3,177 B`** free; `ovl.storage`: `3,823 B` / **`273 B`** disk (`3,826 B` / **`270 B`** cart); `ovl.title`: `177 B` / **`3,919 B`** free; `ovl.town`: `8 B` -> **`123 B`**; `ovl.help`: `278 B` -> **`1,914 B`**; `ovl.modal`: `88 B` -> **`690 B`** | `.d64`: `240/658` free; Magic Desk `.crt`: **`21`** assets (`103,590 B`), `142,170 B` free |
| **C128** | `Default (< $AF00)`: `593 B` -> **`512 B`** (`$AD00`) disk; `1,008 B` -> **`927 B`** (`$AB61`) cart; `128.play (< $D000)`: `74 B` -> **`354 B`** (`$CE9E`, `+280 B`) | `128.bank (< $FF00)`: `34 B` -> **`494 B`** (`$FD12`, `+460 B`); `128.persist`: `5,181 B` -> **`3,692 B`** (`$C194`) | `ovl.home` (`128.home`, uncached `#11`; `SAVE_IN_STORAGE_OVERLAY` OFF): `919 B` / **`3,177 B`** free; `ovl.help`: `12 B` -> **`1,501 B`**; `ovl.town`: `100 B` -> **`215 B`**; `ovl.ui`: `229 B` -> **`96 B`** | `MD128` `.crt`: **`28/32`** dir slots (`28` assets, `140,555 B` free, `24` verified payloads); `.d64`/`.d71`/`.d81`: `174` / `838` / `2,670` free blocks |
| **Atari 8-bit** | `Default (< $C100)`: `81 B` -> **`2,236 B`** (`$B844`, `+2,155 B`) disk; `836 B` -> **`3,008 B`** (`$B540`, `+2,172 B`) cart | `ATARI.BNK (< $FFFA)`: `2 B` -> **`554 B`** (`$FDD0`, `+552 B`) disk; `228 B` -> **`780 B`** (`$FCEE`) cart | `OVL.HOM`: `919 B` / **`3,177 B`** free; `OVL.STO`: `3,560 B` / **`536 B`** disk (`3,556 B` / **`540 B`** cart); `OVL.TTL`: `285 B` / **`3,811 B`** disk (`252 B` / **`3,844 B`** cart); `OVL.TWN`: `8 B` -> **`123 B`**; `OVL.HLP`: `413 B` -> **`1,937 B`** | `130XE`: **`235/256`** pages (`Slots 0..18`, Banks `64/64/64/43p`), **`21`** contiguous free (`5,376 B` at Bank 3 `$6B00-$7FFF`); `.atr`: **`20/64`** files, `140/1,023` free; `.car`: **`20`** assets (`102,937 B`), `19,712 B` free |
| **Apple IIe** | `Default (< $7C00)`: `43 B` -> **`290 B`** (`$7ADE`, `+247 B`); `A2PlaySlot (< $A000)`: `66 B` -> **`334 B`** (`$9EB2`, `+268 B`) | Pre-existing Aux caches unchanged (`0` overflows) | `ovl.home`: `1,308 B` (`$A91C`) / **`4,324 B`** free; `ovl.town`: `265 B` -> **`1,190 B`**; `ovl.storage`: `347 B` -> **`153 B`**; `ovl.title`: `542 B` / **`5,090 B`** free | `MORIA8.PAK`: **`20/42`** entries (`104,317 B`); `.po`: **`250/280`** blocks used (**`30`** free = `15,360 B`) |
| **BBC Master 128** | `Default (< $8000)`: `128 B` -> **`323 B`** (`$7EBD`, `+195 B`); `BeebPlaySlot (< $A400)`: `44 B` -> **`323 B`** (`$A2BD`, `+279 B`) | `SWR Banks 4-7`: `256/256` pages; `BeebLynneAux`: `992 B` free; `cache.ovl.modal`: `225 B` -> **`311 B`** free | `ovl.home` (`OVLHOM`): `1,294 B` (`$AD0E`) / **`4,850 B`** free; `ovl.town`: `795 B` -> **`1,706 B`**; `ovl.storage`: **`2,344 B`** free; `ovl.title`: **`5,866 B`** free | `.ssd`: **`416/800`** sectors used (**`384`** free), **`15/31`** DFS catalog entries |
| **CX16** | `Default (< $9B00)`: `452 B` -> **`1,797 B`** (`$93FB`, `+1,345 B`) disk; `430 B` -> **`1,775 B`** (`$9411`, `+1,345 B`; **`1,391 B`** free `<= $9980` `CartLiveHelperLimit`) cart | HiRAM (`$A000-$BFFF`): `20/64` -> **`21/64`** banks used, **`43`** free (**`344 KB`** free: Banks `5-8` + `25-63`) | `OVL.HOME` (Bank 19): `1,181 B` / **`7,011 B`** free; `OVL.STORAGE` (Bank 20): `3,344 B` / **`4,848 B`** free; `OVL.TITLE` (Bank 21): `544 B` / **`7,648 B`** free; `TITLE` (Bank 22), `MONSTER.CAT` (Bank 23), `LEGALUI` (Bank 24) | `.crt`: **`21`** assets (`101,264 B`), `29,296 B` free; `.zip`: **`21`** files |

- **Tightest Remaining Watchlist (`< 64 B` free in `tools/report_memory_budgets.py`, `35` product slots, `0` overflows):**
  - **BBC Master 128:** `ANDY (beeb.huffdata)` (`35 B`), `cache.ovl.items (Bank 7)` (`38 B`).
  - **C128:** `128.input` (`2 B`), `128.proj` (`4 B`), `128.runtime` (`5 B`), `128.fdisk` (`9 B` cart / `42 B` disk), `128.names (Bank1)` (`24 B`), `cache.ovl.disarm (Bank1)` (`34 B`), `128.huff (Bank1)` (`35 B`), `128.cat (Bank1)` (`37 B`), `ovl.gen` (`63 B`).
  - **Apple IIe:** `MainLowScratch` (`1 B`), `MainZPSave (zp_save_buf)` (`2 B`), `cache.ovl.spell (Aux)` (`20 B`), `A2Catalog` (`29 B`), `A2AuxData` (`34 B`), `ovl.items` / `cache.ovl.items (Aux)` (`50 B`).
  - **Atari 8-bit:** `HighResident` (`0 B` `< $DF3E`), `HighRAM Tail` (`2 B` `< $E000`).
  - **C64 & Plus/4:** `C64HuffIndex` (`16 B` `< $D700`) / `Plus4HuffIndex` (`16 B` `< $DF00`).
- **Apple IIe Verification Status:** `make -C platforms/apple2 build disk test-memory-contract` (`22/22` contract asserts + `11/11` selftest) and `./tools/isolated.sh make testapple2-runtime` (`26/26` MAME `apple2ee` scenarios PASS, including `help_overlay` `28/28` after fixing the mid-string `"Command Reference"` / `"L:License"` poll race at `platforms/apple2/harness_smoke.py:559,615`).

### Phase 3 Completion Status (`2026-11-14`)

Phase 3 declarative trampoline generation, cross-overlay call enforcement, and `piw_return_overlay` / HAL boundary cleanup are complete across all 7 ports (`0` product overflows and `0` missing segments in `tools/report_memory_budgets.py`):

- **Declarative Trampoline Manifest:** `511` `tramp_*` labels across 7 ports — `367` generated (`71.8%`) across `45` template kinds plus `144` declared `custom` entries carrying explicit `owner_file`, targets, and reasons. Enforced on every clean tree via `python3 -B tools/gen_trampolines.py --selftest` and `--check` inside `make check-hal-boundaries`.
- **Static Cross-Overlay Call Enforcement:** `tools/check_overlay_calls.py` runs pre-build inside `make check-hal-boundaries` (including `--selftest` and clean-tree handling of generated `*_trampolines.inc` and `build/version_strings.inc` imports when `build/` does not exist) and post-build with `.sym` cross-checks (`--check-sym`) inside root `test-prebuild`, reporting `0` cross-overlay violations across all 7 ports.
- **`piw_return_overlay` & HAL Boundary Cleanup:** Eliminated `$0102,x`/`$0104,x` 6502 return-stack probing in `core/player_items.s` and removed direct CPU-port (`$01`) and C128 MMU writes from `core/player_items.s` and `core/item_actions_overlay.s` behind `hal_overlay_post_reload` and `hal_platform_item_action_restore_bank` (`PLAYER_ITEM_SELECT_EXTERNAL` and `HAL_PLATFORM_ITEM_ACTION_KEY_RESTORES_BANK`), guarded by `check_hal_cpu_port_exports.py` and `check_hal_c128_mmu_diag_exports.py`. Fixed Mage Spell #20 (`Identify`, `'?'`) `OVL_SPELL` eviction after item selection on Apple IIe, BBC Master 128, and CX16 via `ovl_spell_restore`, with CX16 MAME/emulator regression scenario `mage_identify_selector` added.
- **Tightest Watchlist (`< 64 B` free, `35` product items, `0` overflows):** Apple IIe `ovl.items` / `cache.ovl.items (Aux)` moved `50 B` -> **`45 B`** free and BBC Master 128 `cache.ovl.items (Bank 7)` moved `38 B` -> **`33 B`** free due to `ovl_spell_restore`; all other Phase 2 tight watchlist items remained unchanged (`0` overflows).

| Port | Resident / Play Free (Phase 2 -> Phase 3) | Banked / Cache Free (Phase 2 -> Phase 3) | Overlay Impact (`ovl.items` / `ovl.spell`) | Shipping Media / Extended Banks |
| --- | --- | --- | --- | --- |
| **C64** | `Default (< $C000)`: `1,866 B` -> **`1,907 B`** (`$B88D`, `+41 B`) disk; `2,637 B` -> **`2,678 B`** (`$B58A`, `+41 B`) cart; `SaveResidentStateProbe <= $A000`: `1,104 B` -> **`1,154 B`** (`+50 B`) disk / `1,742 B` -> **`1,792 B`** (`+50 B`) cart | `64.bank (< $FFFA)`: `347 B` (`$FE9F`, unchanged) | `ovl.items`: `4,006 B` / **`90 B`** free (`$EFA6`); `ovl.spell`: `3,873 B` / **`223 B`** free (`$EF21`) | `.d64`: `194/658` free; `.crt`: `21` assets (`103,460 B`), `409,600 B` free; `.zip`: `32` files (`116,957 B` uncomp) |
| **Plus/4** | `Default (< $C800)`: `1,840 B` -> **`1,887 B`** (`$C0A1`, `+47 B`) disk; `2,293 B` -> **`2,340 B`** (`$BEDC`, `+47 B`) cart | `4.bank (< $FC00)`: `662 B` (`$F96A`) disk / `694 B` (`$F94A`) cart (unchanged) | `ovl.items`: `3,729 B` / **`367 B`** free (`$EE91`); `ovl.spell`: `4,007 B` / **`89 B`** free (`$EFA7`) | `.d64`: `240/658` free; Magic Desk `.crt`: `21` assets (`103,543 B`), `142,170 B` -> **`142,217 B`** free (`+47 B`) |
| **C128** | `Default (< $AF00)`: `512 B` -> **`539 B`** (`$ACE5`, `+27 B`) disk; `927 B` -> **`954 B`** (`$AB46`, `+27 B`) cart; `128.play (< $D000)`: `354 B` (`$CE9E`, unchanged) | `128.bank (< $FF00)`: `494 B` (`$FD12`); `128.persist`: `3,692 B` (`$C194`) (unchanged) | `ovl.items`: `3,837 B` / **`259 B`** free (`$EEFD`); `ovl.gen`: **`63 B`** free; `cache.ovl.disarm (Bank 1)`: **`34 B`** free | `MD128` `.crt`: `28/32` dir slots (`28` assets, `105,164 B`), `140,555 B` -> **`140,596 B`** free (`+41 B`); `.d64`/`.d71`/`.d81`: `174` / `838` / `2,670` free blocks |
| **Atari 8-bit** | `Default (< $C100)`: `2,236 B` -> **`2,269 B`** (`$B823`, `+33 B`) disk; `3,008 B` -> **`3,041 B`** (`$B51F`, `+33 B`) cart | `ATARI.BNK (< $FFFA)`: `554 B` (`$FDD0`) disk / `780 B` (`$FCEE`) cart (unchanged) | `OVL.ITM`: `3,953 B` / **`143 B`** free (`$EF71`); `OVL.SPL`: `3,897 B` / **`199 B`** free (`$EF39`) | `130XE`: `235/256` pages (`21` contiguous free); `.atr`: `20/64` files, `140/1,023` free; `.car`: `20` assets (`102,904 B`), `19,712 B` -> **`19,968 B`** free (`+256 B`) |
| **Apple IIe** | `Default (< $7C00)`: `290 B` -> **`308 B`** (`$7ACC`, `+18 B`); `A2PlaySlot (< $A000)`: `334 B` (`$9EB2`, unchanged) | `cache.ovl.items (Aux)`: `50 B` -> **`45 B`** free (`-5 B`); `cache.ovl.spell (Aux)`: **`20 B`** free | `ovl.items`: `5,587 B` / `50 B` -> **`45 B`** free (`$B9D3`); `ovl.spell`: `5,100 B` / **`532 B`** free (`$B7EC`) | `MORIA8.PAK`: `20/42` entries (`104,304 B`); `.po`: `250/280` blocks (`30` free = `15,360 B`) |
| **BBC Master 128** | `Default (< $8000)`: `323 B` -> **`330 B`** (`$7EB6`, `+7 B`); `BeebPlaySlot (< $A400)`: `323 B` (`$A2BD`, unchanged) | `cache.ovl.items (Bank 7)`: `38 B` -> **`33 B`** free (`-5 B`); `cache.ovl.spell (Bank 7)`: **`124 B`** free; `SWR Banks 4-7`: `256/256` pages; `BeebLynneAux`: `992 B` free | `ovl.items`: `5,599 B` / **`545 B`** free (`$BDDF`); `ovl.spell`: `5,252 B` / **`892 B`** free (`$BC84`) | `.ssd`: `416/800` sectors used (`384` free), `15/31` DFS catalog entries |
| **CX16** | `Default (< $9B00)`: `1,797 B` -> **`1,800 B`** (`$93F8`, `+3 B`) disk; `1,775 B` -> **`1,778 B`** (`$940E`, `+3 B`; `1,391 B` -> **`1,394 B`** free `<= $9980` `CartLiveHelperLimit`) cart | HiRAM (`$A000-$BFFF`): `21/64` banks used, **`43`** free (`344 KB` free) | `OVL.ITEMS`: `5,829 B` / `2,363 B` -> `5,834 B` / **`2,358 B`** free (`$B6CA`, `-5 B`); `OVL.SPELL`: `5,945 B` / **`2,247 B`** free (`$B739`) | `.crt`: `21` assets (`101,266 B`), `29,296 B` -> **`29,294 B`** free; `.zip`: `21` files (`101,293 B` uncomp) |

### Phase 4 Completion Status (`2026-11-15`)

Phase 4 item-schema expansion, `ITEM.CAT` (`'ITM2'`, `7,573 B` across `370` VMS Moria 4.8 item templates + `55` ego templates + `174` randomized flavors), `TOTAL_INV_SLOTS = 34` (`EQUIP_CLOAK = 32`, `EQUIP_SECONDARY = 33`), `18` floor traps (`TRAP_TYPE_COUNT = 18`), `279`-species `recall` (`1,116 B`), and atomic Save Format V2 (`SAVE_VERSION = $20`, `OLDEST_SAVE_VERSION = $20`; Atari `SAVE_VERSION = $19`, `ATARI_SAVE_SLOT_SECTORS = 68`) are complete across all 7 ports + 5 cartridges (`0` product overflows and `0` missing segments in `tools/report_memory_budgets.py`):

| Port | Resident / Play Free (Phase 3 -> Phase 4) | Banked / Cache / Aux Free (Phase 4) | Tightest Overlays (`ovl.items` / `ovl.storage` / `ovl.ui`) | Shipping Media / Extended Banks |
| --- | --- | --- | --- | --- |
| **C64** | `Default (< $C000)`: `1,907 B` -> **`189 B`** (`$BF43`) disk; `2,678 B` -> **`1,868 B`** (`$B8B4`) cart; `SaveResidentStateProbe < $A000`: **`3,201 B`** disk / **`4,744 B`** cart | `64.bank (< $FFFA)`: **`24 B`** (`$FFE2`); `C64HiddenAux ($D700-$DEFF)`: `1,578 B` (`recall[279]` `1,116 B` at `$D8CE-$DD29`), **`470 B`** free; `C64HuffIndex`: **`16 B`** free | `ovl.items`: `4,088 B` / **`8 B`** free (`$EFF8`); `ovl.ui`: `4,040 B` / **`56 B`** free (`$EFC8`); `ovl.start`: **`72 B`** free; `ovl.spell`: **`100 B`** free; `ovl.storage`: `3,772 B` / **`324 B`** free; `ovl.home`: `3,602 B` / **`494 B`** free | `.d64`: `527/658` blocks (**`131`** free); EasyFlash `.crt`: **`22`** assets (`117,635 B`, `roml_used=125,827 B`), **`393,216 B`** free; `.zip`: **`34`** files (`132,391 B` uncomp) |
| **Plus/4** | `Default (< $C800)`: `1,887 B` -> **`229 B`** (`$C71B`, incl. `recall[279]` `1,116 B`) disk; `2,340 B` -> **`1,261 B`** (`$C313`) cart | `4.bank (< $FC00)`: **`9 B`** (`$FBF7`) disk / **`41 B`** (`$FBD7`) cart; `Plus4HighBss ($DF00-$DFFF)`: `254 B` sector buf (**`2 B`** free) disk / **`256 B`** free cart; `Plus4HuffIndex`: **`16 B`** free | `ovl.ui`: `4,040 B` / **`56 B`** free (`$EFC8`); `ovl.storage`: `4,040 B` / **`56 B`** free disk (`4,043 B` / **`53 B`** free cart); `ovl.spell`: `4,027 B` / **`69 B`** free (`$EFBB`); `ovl.start`: **`72 B`** free; `ovl.items`: `3,576 B` / **`520 B`** free | `.d64`: `483/658` blocks (**`175`** free); Magic Desk `.crt`: **`22`** assets (`119,118 B`), **`126,642 B`** (`126.6 KB`) free |
| **C128** | `Default (< $AF00)`: `539 B` -> **`263 B`** (`$ADF9`) disk; `954 B` -> **`1,292 B`** (`$A9F4`) cart; `128.play (< $D000)`: `354 B` -> **`63 B`** (`$CFC1`) | `128.bank (< $FF00)`: **`28 B`** (`$FEE4`); `128.persist`: **`4,055 B`** (`$C029`); `Bank1DB ($7400-$7A5F)`: `1,258 B` (`recall[279]` + `zp_save_buf`, replacing retired `128.names`), **`374 B`** free; `cache.ovl.disarm`: **`14 B`** free; `cache.ovl.modal`: **`39 B`** free | `ovl.storage` (`128.storage`, `OVL_STORAGE = 12`): `4,091 B` / **`5 B`** free (`$EFFB`); `ovl.death`: `4,052 B` / **`44 B`** free (`$EFD4`); `ovl.start`: **`68 B`** free; `ovl.ui`: **`70 B`** free; `ovl.items`: `3,795 B` / **`301 B`** free | `MD128` `.crt`: **`29/32`** dir slots (`29` assets, `119,588 B`), **`126,172 B`** (`126.2 KB`) free; `.d64`/`.d71`/`.d81`: **`115`** / **`779`** / **`2,611`** free blocks |
| **Atari 8-bit** | `Default (< $C100)`: `2,269 B` -> **`127 B`** (`$C081`, incl. `recall[279]` `1,116 B`) disk; `3,041 B` -> **`971 B`** (`$BD35`) cart | `ATARI.BNK (< $FFFA)`: **`6 B`** (`$FFF4`) disk / **`232 B`** (`$FF12`) cart; `HighResident`: `368/368 B` (`0 B` free); `HighRAM Tail ($DF3E-$E000)`: `134 B` (`$DFC4`), **`60 B`** free | `OVL.UI`: `4,040 B` / **`56 B`** free (`$EFC8`); `OVL.STA`: `4,024 B` / **`72 B`** free (`$EFB8`); `OVL.ITM`: `3,980 B` / **`116 B`** free (`$EF8C`); `OVL.STO`: `3,149 B` / **`947 B`** free disk (`3,145 B` / **`951 B`** cart) | `130XE`: **`256/256`** pages used (`0` free across Slots `0..18`, Banks `64/64/64/64p`); `.atr`: **`21/64`** files, `1,006/1,023` sectors (**`17`** free); `.car`: **`21`** assets (`118,479 B`), **`4,203 B`** free; Save Disk: `68` sec/slot (`SAVE_VERSION = $19`) |
| **Apple IIe** | `Default (< $7C00)`: `308 B` -> **`86 B`** (`$7BAA`); `A2PlaySlot (< $A000)`: `334 B` -> **`6 B`** (`$9FFA`) | `A2AuxData ($3B0C-$4FFF)`: `5,120 B`, **`244 B`** free; `A2Catalog`: **`29 B`** free; `A2HuffData`: **`111 B`** free; `cache.ovl.spell`: **`20 B`** free; `cache.ovl.items`: **`35 B`** free; `cache.ovl.modal`: **`44 B`** free; Aux LC (`$D000-$FFF9`): **`8,689 / 16,378 B`** used (`recall[279]` `1,116 B` at Bank 1 `$D000-$D45B` + `ITEM.CAT` `7,573 B` at `$E000-$FD94`), **`7,689 B`** free | `ovl.items`: `5,597 B` / **`35 B`** free (`$B9DD`); `ovl.gen`: `5,554 B` / **`78 B`** free (`$B9B2`); `ovl.storage`: `5,181 B` / **`451 B`** free; `ovl.spell`: `5,100 B` / **`532 B`** free | `MORIA8.PAK`: **`20/42`** entries (`110,794 B`, plus standalone `ITEM.CAT` `7,573 B`); `.po`: **`279/280`** blocks used (**`1`** free = `512 B`) |
| **BBC Master 128** | `Default (< $8000)`: `330 B` -> **`36 B`** (`$7FDC`); `BeebPlaySlot (< $A400)`: `323 B` -> **`6 B`** (`$A3FA`) | `SWR Banks 4-7`: `256/256` pages (Bank 6 `BeebAuxData` `19p` `40 B` free + `BEEB_ICAT_B6` `2p` + `BeebCatalog` `37p` `233 B` free + `cache.ovl.ui` `6p` `69 B` free; Bank 7 `cache.ovl.spell` `21p` `106 B` free + `cache.ovl.items` `23p` `167 B` free + `cache.ovl.gen` `16p` `174 B` free + `BEEB_ICAT_CACHE` `4p`); `BeebLynneAux ($3F80-$43FF)`: `1,116 B` (`recall[279]`), **`36 B`** free; `ANDY`: **`35 B`** free | `ovl.items`: `5,721 B` / **`423 B`** free (`$BE59`, `167 B` free in `23p` Bank 7 cache); `ovl.home`: `5,315 B` / **`829 B`** free; `ovl.spell`: `5,270 B` / **`874 B`** free; `ovl.gen`: `3,922 B` / **`2,222 B`** free (`174 B` free in `16p` Bank 7 cache) | `.ssd`: **`467/800`** sectors used (**`333`** free), **`16/31`** DFS catalog entries (adds `ITEMCAT`) |
| **CX16** | `Default (< $9B00)`: `1,800 B` -> **`1,977 B`** (`$9347`, `+177 B`) disk; `1,778 B` -> **`1,979 B`** (`$9345`, `+201 B`; **`1,595 B`** free `<= $9980` `CartLiveHelperLimit`) cart | HiRAM (`$A000-$BFFF`): **`22/64`** banks used, **`42`** free (**`336 KB`** free: Bank 5 `CX16_BANK_CATALOG_EXT`, Banks `7-8`, Banks `25-63`); `Bank 3 CX16.AUXDATA`: `5,858 B` (incl. `recall[279]`), **`2,334 B`** free; `Bank 6 ITEM.CAT`: `7,573 B` (`$A000-$BD95`), **`619 B`** free | `OVL.ITEMS`: `6,338 B` / **`1,854 B`** free (`$B8C2`); `OVL.SPELL`: `5,965 B` / **`2,227 B`** free (`$B74D`); `OVL.CHEST`: `5,358 B` / **`2,834 B`** free; `OVL.HOME`: `5,258 B` / **`2,934 B`** free | `.crt`: **`22`** assets (`116,097 B`, `116,609 / 131,072 B` used), **`14,463 B`** (`14.5 KB`) free; `.zip`: **`22`** files (`116,150 B` uncomp) |

- **Tightest Remaining Watchlist (`< 64 B` free in `tools/report_memory_budgets.py`, `0` product overflows):**
  - **C64:** `ovl.items` (`8 B`), `C64HuffIndex` (`16 B`), `64.bank` (`24 B`), `ovl.ui` (`56 B`).
  - **Plus/4:** `Plus4HighBss` (`2 B` disk), `4.bank` (`9 B` disk / `41 B` cart), `Plus4HuffIndex` (`16 B`), `ovl.storage` (`53 B` cart / `56 B` disk), `ovl.ui` (`56 B`).
  - **C128:** `128.input` (`2 B`), `128.proj` (`4 B`), `128.runtime` (`4 B`), `ovl.storage` (`5 B`), `128.fdisk` (`13 B` cart / `46 B` disk), `cache.ovl.disarm (Bank1)` (`14 B`), `128.bank` (`28 B`), `128.huff (Bank1)` (`35 B`), `128.cat (Bank1)` (`37 B`), `cache.ovl.modal (Bank1)` (`39 B`), `ovl.death` (`44 B`), `128.play` (`63 B`).
  - **Atari 8-bit:** `HighResident` (`0 B` `< $DF3E`), `ATARI.BNK` (`6 B` disk), `OVL.UI` (`56 B`), `HighRAM Tail` (`60 B` `< $E000`).
  - **Apple IIe:** `MainZPSave (zp_save_buf)` (`2 B`), `MainLowScratch` (`3 B`), `A2PlaySlot (a2.play)` (`6 B`), `cache.ovl.spell (Aux)` (`20 B`), `A2Catalog (Aux)` (`29 B`), `ovl.items` / `cache.ovl.items (Aux)` (`35 B`), `cache.ovl.modal (Aux)` (`44 B`).
  - **BBC Master 128:** `BeebPlaySlot (beeb.play)` (`6 B`), `ANDY (beeb.huffdata)` (`35 B`), `Default (moria8.res)` (`36 B`), `BeebLynneAux (LYNNE)` (`36 B`), `BeebAuxData (Bank 6)` (`40 B`).
  - **CX16:** None `< 64 B` (tightest is `ITEM.CAT (Bank 6)` with `619 B` free).

