# Apple IIe Memory Policy (M0 Deliverable)

Placement source of truth for the Apple IIe port, produced by milestone M0 of
`docs/APPLE2_PORT.md`. Where this document and the port plan disagree, this
document wins; the plan is the process record.

## Basis and Method

Measured from a clean `make build` at `f7d322d` (origin/main, post-work16;
trees byte-identical to work16 tip `f8c5b86`). Per-module attribution was
extracted from `platforms/commodore/{c64,c128}/main.s` segment/import order
cross-referenced with `build/{c64,c128}/main.vs` label addresses (module size
= next module's lowest label address minus this module's lowest). Every
payload sum reconciles exactly with on-disk size minus the 2-byte PRG header.
Tolerance inside payloads is a few bytes at module boundaries; payload totals
are exact.

Build-artifact notes:

- C128 overlays grew vs. `docs/ARCHITECTURE.md` (stale): measured max slot is
  **ovl.gen at 4,090 B**, not 4,088. C64's 4,068 figure never governed this
  port.
- Tier payloads measured: **830 / 1,109 / 1,367 / 2,062** (TIER1-4). The
  5,368 B figure in the plan is the C128 tier-cache *window reservation*, not
  a payload size. Tier headroom is therefore 3,314 B, not 8 B — plan risk #2
  dissolves.
- C64 `core/dungeon_gen.s` connectivity is **queue-less** (iterative map-scan
  passes, `dungeon_gen.s:2384+`, scratch `bfs_cur_x/y` at 2567-2568). The
  plan's 1,024 B BFS allocation in the window tail is unnecessary and is
  dropped.
- 128.names.prg links inside the world span but loads into Bank 1 — the
  C128's trick of keeping map+names off the concurrent bank. The Apple II
  equivalent is aux RAM; aux cannot execute code, which is the port's central
  constraint (below).
- Tier-4 name blob = 2,062 − (57 × 22) = **808 B**, so a 1,024 B name pool
  satisfies the `tier_manager.s:525` assert with 216 B margin. The plan's
  2,048 B pool is reduced to 1,024 B, reclaiming 1,024 B for the window.

## Implemented Layout Snapshot (2026-07-21; aux re-plan 2026-11-05)

This snapshot supersedes the M0 estimates and the older slot-hosted overlay
descriptions later in this document. The historical sections remain as the
design record; current ownership is enforced by `platforms/apple2/memory.s`,
`platforms/apple2/main.s`, and `platforms/apple2/cache_layout.s`.

| Range | Current owner and measured use |
| --- | --- |
| main `$0200-$028D` | `zp_save_buf` (`142 B`, relocated out of `Default`; asserted `<= $028F` before `A2_MLI_PATHNAME` at `$0290`) |
| main `$0290-$02CF` | `A2_MLI_PATHNAME` (`64 B`) |
| main `$02E0-$02F3` | `A2_LC_BOUNCE` (`16 B`) + `A2_LC_SAVED_X` / arg registers (`4 B`) for ZP-free `ALTZP=1` Aux LC bounce |
| main `$0301-$033A` | Relocated uninitialized/boot-zeroed resident scratch (`58 B`, strictly `> $0300` and `< $033C` door scan; cleared by `a2_reset_session_state`) |
| main `$033C-$037B` | `DUNGEON_GEN_DOOR_SCAN_BASE` / `PLATFORM_HD_DECODE_BUF_BASE` (`64 B`) |
| main `$0A00-$7BFF` | Always-resident image; current payload `$0A00-$7BCA` (**29,131 / 29,184 B, 53 B free** after Phase 5 `279/279` VMS monster catalog + Wave 5.2 cold evictions, 2026-11-16; see Phase 5 section below) |
| main `$7C00-$9FFF` | Load-once `A2.PLAY`; current payload `$7C00-$9F6D` (**9,070 / 9,216 B, 146 B free** including signature; 2026-11-16) |
| main `$A000-$A3FF` | Name pool (1,024 B): the monster catalog's 32 species names |
| main `$A400-$B9FF` | All 13 code overlays, mutually exclusive (`OVL.START` 4,283 B, `OVL.TOWN` 4,297 B, `OVL.DEATH` 5,592 B [**40 B free**, owns `ui_recall.s`], `OVL.MODAL` 2,453 B, `OVL.GEN` 5,554 B, `OVL.HELP` 4,332 B, `OVL.UI` 1,515 B, `OVL.ITEMS` 5,597 B, `OVL.SPELL` 5,044 B, `OVL.CHEST` 4,307 B, `OVL.HOME` 4,076 B, `OVL.STORAGE` 5,396 B, `OVL.TITLE` 2,882 B [owns `a2_boot_preload_aux_lc` + `store_restock_overlay.s` + `starting_kit_cold.s`]); window 5,632 B |
| main `$BA00-$BAFF` | Window tail reserved; tier data may use through `$BAFF` |
| main `$BB00-$BEFF` | ProDOS MLI I/O/staging buffer |
| main `$BF00-$BFFF` | ProDOS global page |
| aux `$0200-$03FF` | Relocated persistent tables (`512 B`): `id_known_bits[47]` + `potion_shuffle..staff_shuffle` (`174 B`) + `si_meta_hi[128]` + `fi_meta_hi[42]` (`391 / 512 B` used, `121 B` free) |
| aux `$0800-$3B0B` | Live 198x66 map |
| aux `$3B0C-$4FFF` | Current immutable/mutable aux data payload (ends `$4F0B`, `5,120 / 5,364 B`, **244 B free**; stored PackBits-compressed in `MORIA8.PAK` as `A2.AUXDATA.PB` [`2,781 -> 5,120 B`] and unpacked at cold boot by `TitleOverlay:a2_boot_preload_aux_lc`): store inventory, class-spell tables, spell names, externalized message strings, and the message-history ring buffer (`MSG_HISTORY_IN_AUX`; writes execute only via the ZP thunk `mmu_safe_map_write_ptr1`) |
| aux `$5000-$66FF` | Monster catalog fields (`A2.CATALOG`, 5,859 B, **29 B free**; stored PackBits-compressed in `MORIA8.PAK` as `A2.CATALOG.PB` [`4,682 -> 5,859 B`] and unpacked at cold boot by `TitleOverlay:a2_boot_preload_aux_lc`) |
| aux `$6700-$BFFF` | Cache manifest v8: UI `$6700` (`1,515 / 1,536 B`, **21 B free**), SPELL `$6D00` (`5,044 / 5,120 B`, **76 B free**), MODAL `$8100` (`2,453 / 3,072 B`, **619 B free** — `ui_recall.s` relocated to `OVL.DEATH`), the Huffman corpus with the catalog's names + read-only screen-code char-map table `$8D00` (`$8D00-$A990`, `7,313 / 7,424 B`, **111 B free**), ITEMS `$AA00` (`5,597 / 5,632 B`, **35 B free**). Cold overlays (`OVL.START`, `OVL.TOWN`, `OVL.DEATH`, `OVL.GEN`, `OVL.HELP`, `OVL.CHEST`, `OVL.HOME`, `OVL.STORAGE`, `OVL.TITLE`) load on demand from `MORIA8.PAK` |
| aux LC `$D000-$FFF9` | Auxiliary Language Card (`16,378 B`, **10,826 B used / 5,552 B free**, accessed via `SEI` + ZP-free `ALTZP=1` bounce at `$02E0-$02F4` with port-owned Aux interrupt vectors at `$FFFA-$FFFF`): Aux LC Bank 1 `$D000-$D45B` holds `recall[279]` (`1,116 B`, `2,980 B` free in Bank 1), Aux LC Bank 2 `$D000-$D8B7` holds Phase 5 extended monster catalog `A2.CATEXT` (`2,232 B`, `1,864 B` free in Bank 2; unpacked from `A2.CATEXT.PB` [`1,228 -> 2,232 B`] by `TitleOverlay:a2_boot_preload_aux_lc` and read via `catalog_fetch_ext`), and Aux LC High RAM `$E000-$FD35` holds preloaded `'ITM2'` `ITEM.CAT` (`7,478 B` across `361` VMS items, `708 B` free in High RAM; Save Format V2 `SAVE_VERSION = $22`) |

`A2.PLAY` is not a modal swap slot in the implementation: every overlay,
including STORAGE and TITLE, fits the `$A400-$B9FF` code window. Play is
loaded on demand and signature-checked, then remains resident for the session.

Cache manifest v8 (2026-11-05, `cache_layout.s`) replaced v7 for the monster
catalog: OVL.TOWN left the cache (maintainer: "only the town overlay"), the
catalog's fields took aux `$5000`, and its names follow the Huffman corpus,
which moved from `$9900` to `$8D00`. The auxiliary language card (aux
`$D000-$FFFF`, 16 KB) is the next source of room if this tight layout needs
it. The v7 record follows.

Cache manifest v7 is shared by boot and runtime code rather than duplicated:
TOWN `$5A00`, UI `$6F00`, SPELL `$7900`, MODAL `$8D00`, GEN `$9900`, ITEMS
`$AA00`, end `$C000`. TOWN/UI were rebased down 3 pages for the 128-row
catalog (Phase 3, 2026-08-01), growing auxdata to `$59FF`. Page-rounded slots
fill the cache (the UI slot carries
768 B of slack; the rest are exact);
ITEMS is last so the runtime's fixed `$1600`-byte AUXMOVE ends exactly at
`$C000`. Link-time assertions compare every payload extent with its next slot
boundary. This replaces v6 after a captured runtime failure proved the cold
OVL.GEN reopen was unsafe immediately after the tier-file OPEN.

## The Central Finding

C128 gameplay-concurrent (always-resident 44,971 + play 8,430, measured) is
**53,401 B**. The Apple II's concurrent budget (resident region 37,888 −
1,500 B reserve target) is **36,388 B**. The raw gap is ~17K. The plan's
levers 1-3 as drafted (est. 5.5-9.5K) do not close it, and the play/persist
slot cannot help: the slot lives inside the resident region, so reclassifying
bytes into the slot leaves the concurrent sum unchanged (slot invariance).
Only three things reduce the sum: moving data to aux, moving code to overlay
classes, and net platform-code shrink.

Closure is achieved on paper only with the expanded, **all-mandatory** lever
package below, landing at ~900 B aggregate margin — below the 1,500 B
target. Named M1 remediation bytes (below) cover the difference if M1 actuals
overrun. The structural escape hatch, if M1 busts by more than those bytes,
is the Language Card (plan defers it post-M4; this finding does not force it,
but it is the only remaining >4K source).

## Revised Memory Map (supersedes plan tables)

> **SUPERSEDED — historical M0 design record.** The Current Snapshot at the
> top of this document is authoritative. Key deltas from this table: play
> slot is `$7C00-$9FFF` (9,216 B), tier-name pool is `$A000-$A3FF`, and the
> overlay/tier window is `$A400-$B9FF` (`BANKED_DATA_BASE=$A400`), per
> `platforms/apple2/memory.s`. `A2.PLAY` is load-once resident, not a modal
> swap slot, and there is no DISARM class (spell execution is its own SPELL
> class on this port).

### Main RAM

| Range | Size | Owner |
| --- | ---: | --- |
| `$0000-$00FF` | 256 | ZP: core `$02-$8F` unchanged; platform `$90-$EF`; `$F0-$FF` reserved |
| `$0100-$01FF` | 256 | Stack |
| `$0200-$03CF` | 464 | Platform scratch: ZP save buffer (142 B), MLI param blocks, boot loader staging |
| `$03D0-$03FF` | 48 | ProDOS/reset/IRQ vectors — reserved |
| `$0400-$07FF` | 1,024 | 80x24 text page, main half (odd columns); screen holes never touched |
| `$0800-$09FF` | 512 | Floor-item table (256) + creature scratch (256) — core raw-addressed |
| `$0A00-$7BFF` | 29,184 | Always-resident region (Kick segments, C128-style splits) |
| `$7C00-$9DFF` | 8,704 | Play/modal slot: play payload during gameplay; OVL.STORAGE / OVL.TITLE payloads overwrite it in modal phases |
| `$9E00-$A1FF` | 1,024 | Tier name pool (`PLATFORM_TIER_NAME_POOL_BASE=$9E00`, `END=$A1FF`; need 808 B, margin 216 B) — core raw-addressed |
| `$A200-$BAFF` | 6,144 | Shared overlay/tier window (`BANKED_DATA_BASE`); code region `$A200-$B3FF` (4,608 B; max overlay 4,090 → **518 B headroom**); tier mode may use the whole window (max tier 2,062 → 4,082 B headroom); no BFS allocation |
| `$BB00-$BEFF` | 1,024 | ProDOS MLI file I/O buffer (page-aligned, one open file) |
| `$BF00-$BFFF` | 256 | ProDOS global page (MLI entry `JSR $BF00`) |

Slot arithmetic: play payload 8,430 ≤ 8,704 (274 B slack). Modal payloads
must also fit the slot: OVL.STORAGE est. ~4,100 (save.s 2,558 + slot menu
519 + stream shims ~400 + disk-setup UI ~636) ✓; OVL.TITLE est. ~2,000 ✓.

### Aux RAM (ALTZP off by default; verified SEI ZP-free bounce path in Phase 1)

> **UPDATED (2026-11-14 Phase 1):** The legacy `"ALTZP stays off"` blanket
> restriction is lifted **only** for the verified data-only bounce helper
> `a2_aux_lc_bounce_xfer` (`platforms/apple2/memory_aux.s`; `SEI`, zero
> ZP/stack accesses while `$C009` `ALTZP=1` is asserted, `abs,x` bounce via
> Main `$02E0-$02EF`, port-owned Aux vectors at Aux `$FFFA-$FFFF`, and exact
> restore of `$C008` + saved Main LC bank/mode before `PLP`). See the Phase 1
> section below for MAME `apple2ee` verification findings. Aux `$0200-$03FF`
> (`512 B`, `a2_aux_scratch_base..end`) is also claimed as reserved aux scratch.

| Range | Size | Owner |
| --- | ---: | --- |
| aux `$0400-$07FF` | 1,024 | Text page aux half (even columns) |
| aux `$0800-$3B0B` | 13,068 | Live map, 198x66 — all access via thunked MapRead/MapWrite |
| aux `$3B0C-$59FF` | 7,924 | Aux data: Huffman data, item-name streams, store inventory/runtime, recall arrays, class-spell tables, spell names, ego suffix slots, externalized message strings, char-map table; boundary raised from `$56FF` for the 128-row catalog (Phase 3, 2026-08-01) |
| aux `$5A00-$BFFF` | 26,112 | Hot cache (payloads, page-rounded slots): ovl.town 5,362 + ovl.ui 2,525 + ovl.spell 5,025 + ovl.modal 2,978 + ovl.gen 4,236 + ovl.items 5,632 = 25,758 used; slots TOWN `$5A00`, UI `$6F00`, SPELL `$7900`, MODAL `$8D00`, GEN `$9900`, ITEMS `$AA00` |

On-demand from disk (never cached; all cold or disk-appropriate moments):
ovl.start (chargen), ovl.help, ovl.modal, ovl.disarm, OVL.STORAGE,
OVL.TITLE, MONSTER.DB.1-4 (tier loads), TITLE art. Disk-speed overlay loads
are the shipping stock-C64 norm, so this is not a UX regression; the aux
cache is pure latency luxury for the hot classes.

## Payload Classes

> **SUPERSEDED — historical M0 design record.** In the implementation,
> OVL.STORAGE and OVL.TITLE are window-hosted (`$A400`) like every other
> overlay class; nothing overwrites the play slot, and there is no DISARM
> class. See the Current Snapshot.

Existing classes carry over unchanged (START, TOWN, DEATH — which doubles as
the spell-execution class per C128, MODAL, GEN, HELP, UI, ITEMS, DISARM).
New classes:

- **OVL.STORAGE** — save engine (`platforms/shared/save.s`), save-slot menu, disk-setup
  UI, MLI stream shims. Loads into the **play/modal slot** ($7C00), not the
  window: it overwrites play, which the broker restores afterward. Fits
  (est. ~4,100 ≤ 8,704).
- **OVL.TITLE** — title/menu/sysinfo flow, boot and death-restart only.
  Also slot-hosted.
- **Play slot** — C128's play class verbatim (measured 8,430 B:
  dungeon_los, monster_attack, combat, player_move/run, game_loop, turn,
  wizard, helpers). Restored from aux cache via AUXMOVE (~100 ms at firmware
  move speed) instead of disk.
- **Aux data** — item names, huffman tables, store data, recall data; read
  via AUXMOVE block copies into main-RAM scratch (per-byte thunks only for
  the live map).

## Per-Module Classification (C128 measured basis)

`ALWAYS` = always-resident region ($0A00-$7BFF, budget 29,184). `PLAY` =
slot. `OVL.*` = window classes. `AUX` = aux data. `GONE` = commodore-only,
replaced by the Apple II HAL budget line.

### From moria128.prg (17,403) and 128.world.prg (11,423)

| Module | Bytes | Class |
| --- | ---: | --- |
| main.s inline glue (KERNAL wrappers, loaders, tramp_*, turbo detect) | ~4,000 | GONE — a2 glue budgeted below |
| memory128.s | 938 | GONE — memory.s/memory_aux.s |
| color, sound, rng, math, tables, numeric_format, platform_services_api | 2,021 | ALWAYS |
| screen_vdc.s / input128.s | 893 + 866 | GONE — screen_a2.s/input.s |
| title_sysinfo_banked.s | 141 | OVL.TITLE |
| reu.s + reu_loading_banked.s | 987 | GONE — reu_stub.s (~20) |
| input_contract, input_run_cancel | 64 | ALWAYS |
| player.s | 1,349 | ALWAYS |
| ui_messages.s + ui_status.s | 2,088 | ALWAYS code; string data → AUX (L4, est. −1,500); `msg_history` ring buffer → AUX (2026-09, `MSG_HISTORY_IN_AUX`) |
| generation_busy(+api), ui_help_clear, stat_display | 308 | ALWAYS |
| huffman.s (decoder) | 155 | ALWAYS |
| huffman_data.s | 2,911 | AUX (L3) |
| runtime_ui_strings.s | 70 | ALWAYS |
| score_io.s | 349 | OVL.STORAGE |
| storage_status.s, disk_swap.s | 651 | GONE — MLI status map + always-present probes |
| dungeon_data.s, dungeon_features.s | 1,698 | ALWAYS |
| monster.s + monster_ai.s + monster_magic.s | 5,262 | ALWAYS |
| tier_manager.s | 976 | ALWAYS |
| overlay.s (+ filename tables) | 552 | ALWAYS (broker calls it) |
| recall.s | 289 | AUX (L3) |
| los_trace.s | 292 | ALWAYS |
| spell_data.s | 769 | ALWAYS |
| spell_effects.s (+ item-prg block) | 1,344 | ALWAYS |
| dungeon_room_center_helpers.s | 32 | ALWAYS |

### From 128.item.prg (6,993), 128.select.prg (757), 128.diskio.prg (1,002), 128.runtime/fdisk/input/proj (3,470), 128.bank.prg (3,823)

| Module | Bytes | Class |
| --- | ---: | --- |
| item.s | 2,722 | ALWAYS |
| item_tables.s (non-name) | 1,264 | ALWAYS |
| item_tables.s (name streams = 128.names.prg) | 821 | AUX |
| item_identification.s | 1,543 | bulk → OVL class (L6, −1,200); pseudo-id timers stay ALWAYS |
| ego_items.s | 286 | ALWAYS |
| store_data.s (+door lookup) | 811 | AUX (L3) |
| player_items.s, player_item_select, heal_feedback, ui_restore | 604 | ALWAYS |
| storage.s, storage_drive.s, disk_setup* | 1,014 | GONE — storage_mli.s; disk-setup UI → OVL.STORAGE |
| monster.s RuntimeLowData block | 338 | ALWAYS |
| dungeon_render_vdc.s | 2,023 | GONE — screen_a2 renderer |
| title_cache_runtime.s, restart128.s | 278 | OVL.TITLE / GONE |
| combat helper inline (fdisk), player_magic_slow/turn_banked | 382 | ALWAYS |
| input_run_raw128.s | 248 | GONE — input.s |
| projectile.s | 124 | ALWAYS |
| map_row_store_common.s | 63 | GONE — map thunks |
| ui_home.s, item_desc_banked.s | 1,095 | ALWAYS |
| player_magic*.s cluster (display, state_ops, magic, levelup, learn_op, tail) | 1,481 | partial → OVL class (L7, −1,200); state ops stay ALWAYS |
| player_recalc_equipment.s, player_item_commands.s | 1,154 | ALWAYS (first M1 remediation byte-source) |

### 128.persist.prg (3,079) → OVL.STORAGE (slot-hosted); 128.play.prg (8,430) → PLAY slot (verbatim).

## Closure Equation (all levers mandatory)

```
C128 gameplay-concurrent (measured)                      53,401
− commodore-only code (reu, vdc, disk_swap/setup, KERNAL
  glue, trampolines, turbo detect)                      −10,400
+ Apple II HAL (screen/renderer, input, storage_mli,
  memory_aux+thunks, services, broker, map thunks)        +6,200  (estimate; hard budget 5,500)
− L2  title/sysinfo/cache → OVL.TITLE                       −419
− L3  huffman_data + store_data + recall → AUX            −4,011
− L4  ui_messages/ui_status string data → AUX             −1,500  (estimate)
− L6  item_identification bulk → OVL                      −1,200
− L7  player_magic cluster partial → OVL                  −1,200
= Apple II gameplay-concurrent                           39,871
```

Wait — the sum above is stated conservatively; with the platform budget
held at 5,500 the figure is 39,171. Region check:

```
ALWAYS  = 39,171 − 8,430 (play) = 30,741  vs  29,184 region   → short 1,557
```

**This does not close.** Remediation byte-sources, pre-named, applied in
order until ALWAYS ≤ 29,184 − 1,500 = 27,684:

| # | Lever | Bytes |
| --- | --- | ---: |
| R1 | player_item_commands.s → new OVL class (discrete commands; C64 overlays its siblings already) | −1,097 |
| R2 | wizard.s (in play) merged into OVL.UI's ui_wizard | −290 |
| R3 | ego_items.s → OVL with item naming callers | −286 |
| R4 | platform budget 5,500 → 4,800 (renderer shares row table with screen; drop IIc fallback paths to M4) | −700 |
| R5 | tables.s stat-bonus lookups → AUX with thunked read (hot-ish; last resort) | −761 |

R1+R2+R3+R4 = −2,373 → ALWAYS = 28,368 ≤ 29,184 (slack 816; slot slack
274; window slack 518; **aggregate margin 1,608 ≥ 1,500 ✓**). R5 stays in
reserve. M1 gate zero enforces actuals; if measured ALWAYS exceeds the
region after R1-R4, the decision point is R5 vs. Language Card — that is a
user decision, flagged here in advance.

## Zero-Page Policy and Thunk Addresses

Platform owns `$90-$EF`:

| Range | Owner |
| --- | --- |
| `$90-$93` | Entropy counters (4 B, ticked in input wait loop) |
| `$94` | Aux/cache state flags |
| `$95-$97` | MLI scratch, storage phase byte |
| `$98-$BF` | Reserve |
| `$C0-$CF` | `a2_aux_read_byte` thunk (16 B): `sta $C003 / lda (zp_map_ptr),y / sta $C002 / rts` + aux |
| `$D0-$DF` | `a2_aux_read_block` thunk (16 B): small RAMRD-on copy loop |
| `$E0-$EF` | Reserve (IIc deltas) |

- Only RAMRD-on *reads* require ZP execution (instruction-fetch trap);
  main→aux writes run from ordinary resident code under RAMWRT.
- AUXMOVE is firmware ROM: callable from resident code; wrapper saves/
  restores `$3C-$43` (8 B). INTC3ROM selection (`$C00B`) pinned at boot.
- MLI sequences: blanket `$02-$8F` save/restore (142 B buffer at
  `$0200-$03CF` scratch) + thunk reinstall afterward. Verified against
  the ProDOS 8 TRM (prodos8.com/docs/techref/memory-use/, §3.3.1): the
  MLI uses `$40-$4E` (restored before each call completes) and its
  disk driver uses `$3A-$3F` (not restored) — the entire MLI ZP
  footprint sits inside the core window; high ZP is never touched.
- Thunks installed at boot, reinstalled by the storage adapter. The M1
  contract checker asserts thunk residency and the `$C0-$DF` span.

## Play/Persist Broker (five-facts applied)

> **SUPERSEDED — historical design record.** The shipped implementation does
> not swap play: `A2.PLAY` loads once at `$7C00-$9FFF`, is signature-checked,
> and stays resident; STORAGE/TITLE modals run as window overlays. Asserts
> pin `play_end <= $9FFF`, not `$9DFF`. See the Current Snapshot.

1. **Linked symbol address**: play payload Kick segment linked at `$7C00`;
   asserts pin `play_end <= $9DFF`.
2. **BIN load address**: `A2.PLAY` file auxtype = `$7C00`; `prg_to_bin.py`
   asserts header match per payload.
3. **Destination bank at load**: main RAM, always visible — trivially
   correct (no banking on the Apple II path); the aux cache at aux `$5A00+`
   holds the master copy.
4. **Visible execution bank at call site**: main RAM — trivially correct.
5. **Source-span survival**: aux cache span is disjoint from map
   (`$0800-$3B0B`) and aux data (`$3B0C-$59FF`); checker asserts all aux
   spans. Broker sequence (C128 `c128_modal_require_*` pattern): modal entry
   → AUXMOVE play → aux cache (or mark cache stale) → load modal payload
   into slot; modal exit → AUXMOVE cache → `$7C00` → validate 3-byte
   signature (`M8P` equivalent) → resume gameplay. Signature mismatch =
   fatal storage error path.

## Boot File List (current, M2)

ProDOS volume `MORIA8`:

| File | Type | Destination |
| --- | --- | --- |
| `MORIA8.SYSTEM` | SYS `$2000` | boot.s; relocates itself to `$0800-$09FF` scratch (its `$2000` origin is inside the resident span) |
| `MORIA8.PAK` | BIN | boot container: 512-B header (count + 16-bit lengths) then RES, AUXDATA, A2.CATALOG (the monster catalog's fields), OVL.UI, OVL.ITEMS, OVL.SPELL, OVL.MODAL, A2.HUFFDATA (the Huffman corpus and the catalog's names) payloads in that order |
| `A2.PLAY` | BIN `$7C00` | play payload; loaded on demand by `a2_require_play` (signature `M8P` validated) |
| `OVL.*` (cold set) | BIN `$A400` | left on disk: START, TOWN, DEATH, GEN, HELP, CHEST, STORAGE, TITLE |
| `TITLE` | BIN `$4000` | title art, on demand |

Boot: ProDOS kernel → MORIA8.SYSTEM (relocates to `$0800`) → one OPEN of
MORIA8.PAK → header read to `$A400` → 8 sequential READs (RES →
`$0A00-$7BFF` direct; the rest staged at `$7C00` and RAMWRT-copied to aux:
AUXDATA → `$3B0C`, cache slots below) → CLOSE → jump `$0A00`. The loader
shows a `MORIA8  LOADING  n/8` progress line at text row 11 (both 40-col
and 80-col paths); the text page is untouched by every boot stage, so the
line persists until the resident payload reinitializes the screen.

The single-open sequential container replaces an earlier per-file
OPEN/GFI/READ/CLOSE boot design after that design reproduced a late-file
hang under MAME 0.288 with ProDOS 2.4.3. The exact driver-level cause is not
established; the PAK is retained because it removes the failing boot access
pattern, not as proof that all runtime file opens are unsafe.

Aux cache manifest v7 (shared by `cache_layout.s`; payloads are exact byte
lengths and boot copies are page-rounded): TOWN `$5A00`, UI `$6F00`, SPELL
`$7900`, MODAL `$8D00`, GEN `$9900`, ITEMS `$AA00-$BFFF`. DEATH, HELP, and
STORAGE remain cold. Link-time assertions bind every payload extent to its
next slot and the fixed runtime-copy bound.

Exit = MLI QUIT. `/RAM` volume is disconnected at init (TRM 5.2.2.2);
aux overwrite is then safe.

## Open Items Carried to M1

- AUXMOVE carry polarity, INTC3ROM-vs-SLOTC3ROM, register clobbers —
  firmware, not covered by the ProDOS TRM; the MAME spike (needs
  `A2ROMS`) is the verifier, and the M2 boot scenario proves it
  empirically regardless.
- MLI ZP usage — RESOLVED (TRM §3.3.1): `$3A-$4E` only; save window set
  to `$02-$8F` (142 B).
- ProDOS 8 1.x vs 2.x `/RAM` creation behavior (TRM §3.2 confirms
  `/RAM` first-search on 1.x; 2.x behavior to confirm in the MAME
  spike). `PRODOS` file sourcing: 2.4.3 is freely distributed at
  prodos8.com (John Brooks) but no explicit license text — policy:
  never vendored in the repo; auto-downloaded at build time into
  gitignored `tools/prodos/` with `PRODOS`/`BOOTBLOCKS` overrides for
  user-supplied files (like the `KICKASS` override).
- ProDOS MLI residency — RESOLVED (TRM §3.3 Figure 3-1): the MLI
  itself lives in the main Language Card (`$D000-$FFFF`); aux LC is
  partially used by ProDOS/BASIC.SYSTEM. LC-for-code stays out of
  scope. System bit map (§3.3.3) protects pages 0, 1, 4-7, BF only;
  our `$BB00` buffer is supplied per-OPEN — no conflict by
  construction.
- Huffman/store_data/recall/ui-string aux read paths: block-copy mechanics
  and max-string bounds (decoder reads via `zp_ptr0`; copy to scratch then
  decode). These are the only core-touching lever items; each lands as its
  own reviewed change under the behavior-change protocol.
- MAME aux-region peek mechanics; AppleCommander CLI pin; `A2ROMS` env.

## Gate Restatement

M0 closes iff: the classification above assigns every measured byte (done);
the equation closes with ≥ 1,500 B aggregate margin **including the R1-R4
remediation levers** (done — 1,608 B, on estimates for platform code and
L4/L6/L7 splits); and the correction set vs. the plan is recorded (below).
M1 gate zero (full link + `.assert`s + contract checker) converts every
estimate here into a hard failure if exceeded.

## Amendments to docs/APPLE2_PORT.md Implied by M0

> **SUPERSEDED in part — M0-era record.** Items 2, 5, and 6 were later
> revised: the window is `$A400-$B9FF`, the play slot is 9,216 B
> (`$7C00-$9FFF`), aux data is `$3B0C-$59FF`, and the hot cache is
> `$5A00-$BFFF`. See the Current Snapshot at the top of this document.

1. Closure levers 1-4 reframed: slot invariance means only aux-data moves,
   overlay-class moves, and region/platform changes reduce the concurrent
   sum; L1-L7 + R1-R5 above replace the plan's lever list.
2. Name pool 2,048 → 1,024 B; window moved to `$A200-$BAFF` (6,144 B);
   overlay headroom 518 B; BFS allocation dropped (queue-less connectivity).
3. Tier risk #2 dissolved: max tier payload 2,062 vs. 6,144 B window.
4. New classes OVL.STORAGE and OVL.TITLE are slot-hosted ($7C00), not
   window-hosted; persist payload as a class disappears into OVL.STORAGE.
5. Resident/play split at `$7C00`; play slot 8,704 B.
6. Aux layout pinned: map `$0800-$3B0B`, aux data `$3B0C-$4FFF`, hot cache
   `$5000-$BFFF`; on-demand list fixed.

## License/source modal ownership (2026-11-10)

`LEGALUI` is an uncached modal loaded on title `A` (About) or Help `L`: main RAM $A400-$B9FF; no auxiliary cache slot.
Code ends before overlay base+$600; a 142-byte core-ZP snapshot starts there,
and the disk/ROM input cache occupies base+$700..+$7FF. Both are modal
workspace, never game-data loans or emitted PRG padding. The resident entry saves core ZP before asset loading, after any media
handler that may itself load an overlay.
The viewer reads existing documents through the storage HAL, closes every
channel, retains live sound/redraw state, and restores the caller snapshot.
Linked payload bounds and production-path modal entry/return tests enforce
this ownership. See `docs/LEGAL_VIEWER.md` for the change and verification record.

Verification (2026-11-10): `make -j7 -O test` passed, including the linked PRG
ownership checks and the MAME title/Help legal-viewer scenario. The play slot
and auxiliary cache remain intact; the 140 KB image format is unchanged.

Optional legal loads retain bounded asset retries, then offer Escape at the
resident program-disk prompt. One caller snapshot survives every retry. Escape
restores ZP after the prompt and returns with carry set; Help exits directly to
gameplay, and Title redraws only its resident menu. Neither return reloads the
invalidated overlay while the program disk is absent. No Storage overlay or
unavailable play-slot verifier is called. See the Pass 3 record in
`docs/LEGAL_VIEWER.md` for the save-disk, retry and cancel-boundary tests.

Repair verification (2026-11-11): `make -j7 -O test` passed. Applicable payload
bounds, header/load/execution ownership, missing-file cleanup and production
modal-return rows are complete; see `docs/LEGAL_VIEWER.md` for linked spans and
coverage. Existing banking configurations and persistent cache owners remain;
physical display-layout changes are N/A.


Pass 3 verification (2026-11-11): `make -j7 -O test` passed. The added
save-disk fixtures verify cold Title cancellation to its resident menu,
Help cancellation to gameplay without a cold reload, failed/successful retry
snapshot survival and restored core ZP at the cancel-return boundary. All
linked bounds and the existing bank/cache owners remain enforced. See
`docs/LEGAL_VIEWER.md` for the carry contract and physical media preconditions.

## Phase 1 Memory Unlocks & Aux LC Spike (2026-11-14)

Port-local memory reclaim and ProDOS container consolidation with zero `core/`
edits.

### 1. Reclaimed Address Windows

- **Main `$0200-$028D` (`142 B`):** `zp_save_buf` relocated out of `Default`
  via `.label zp_save_buf = $0200` (`platforms/apple2/memory.s`), asserted
  `zp_save_buf + ZP_SAVE_SIZE <= A2_MLI_PATHNAME` (`$0290`).
- **Main `$02E0-$02F3` (`20 B`):** `A2_LC_BOUNCE` (`16 B`, `$02E0-$02EF`) and
  transfer arg/restore state (`$02F0-$02F3`), asserted `>= A2_MLI_PATHNAME + 65`
  and `<= $02FF`.
- **Main `$0301-$033A` (`58 B`):** 20 relocated uninitialized/boot-zeroed
  resident scratch variables (`a2_probe_buf`, `a2_program_volume`,
  `a2_save_volume`, `a2_last_status`, `a2_media_status`, `a2_name_*`,
  `a2_asset_verify`, `a2_asset_dest`, `a2_diag_*` aliased by
  `hal_storage_diag_*`, `sfa_save_*`, `igk_key`, `input_kbdbuf_shadow`),
  asserted strictly `> $0300` and `< DUNGEON_GEN_DOOR_SCAN_BASE` (`$033C`)
  and cleared on boot/session reset by `a2_reset_session_state`.
- **Aux `$0200-$03FF` (`512 B`):** `a2_aux_scratch_base = $0200` through
  `a2_aux_scratch_end = $03FF`, asserted above Aux ZP/stack and strictly below
  the Aux 80-column text page (`$0400`).

### 2. Packed `MORIA8.PAK` Container (`MLI_SET_MARK = $CE`)

- **`tools/make_pak.py`:** `512 B` header stores count at byte 0 (`<= 42` so
  all metadata fits the 256-byte read prefix), 16-bit LE lengths at bytes `2..`,
  and 24-bit LE byte offsets from start of file at bytes `128..`.
- **19 entries (`103,920 B`, 204 blocks):** Entries `0..7` remain sequential
  at boot (`boot.s` checks count `>= PAK_COUNT` and loads only the first 8:
  `MORIA8.RES`, `A2.AUXDATA`, `A2.CATALOG`, `OVL.UI`, `OVL.ITEMS`, `OVL.SPELL`,
  `OVL.MODAL`, `A2.HUFFDATA`). Entries `8..18` fold the 11 formerly standalone
  sapling files (`A2.PLAY`, `OVL.START`, `OVL.TOWN`, `OVL.DEATH`, `OVL.GEN`,
  `OVL.HELP`, `OVL.CHEST`, `OVL.STORAGE`, `OVL.TITLE`, `LEGALUI`, `TITLE`).
- **Runtime resolution (`platforms/apple2/storage_mli.s`):** `a2_pak_resolve`
  maps normalized overlay/`A2.PLAY`/`LEGALUI` names to entry IDs and load
  addresses; `a2_pak_open_seek` opens `"MORIA8.PAK"`, reads the 256-byte
  header prefix into `a2_ss_buf`, seeks via `A2_MLI_SET_MARK ($CE)`, and reads
  `a2_pak_len`. `hal_asset_load_title` streams `A2_PAK_ENTRY_TITLE` directly
  from `MORIA8.PAK`. `hal_storage_probe_media` probes `"MORIA8.PAK"`.
  `hal_storage_marker_init` moved into `StorageOverlay` (`disk_setup_a2.s` is
  its sole caller), and `a2_map_error` / `a2_map_media_error` share a compact
  lookup table.
- **Release compliance (`AGENTS.md` Rule 7):** `LICENSE` (`344 B`) and
  `SOURCE.OFFER` (`499 B`) stay standalone ProDOS `TXT` files on
  `build/moria8-apple2.po`. Volume utilization improved from 266/280 (**14**
  free) to **249/280 blocks used (`31` blocks / `15,872 B` free)**.

### 3. Aux Language Card (`$D000-$FFF9`) Policy & MAME `apple2ee` Spike

- **Policy amendment:** The legacy `"ALTZP stays off"` prohibition is lifted
  strictly for `a2_aux_lc_bounce_xfer` (`platforms/apple2/memory_aux.s`):
  1. `hal_platform_init_early` calls `a2_aux_lc_init_vectors` to populate
     port-owned Aux interrupt vectors at Aux `$FFFA-$FFFF` (`NMI` ->
     `a2_aux_nmi_rti`, `RESET` -> `a2_aux_reset_stub`, `IRQ/BRK` ->
     `a2_aux_nmi_rti`). Data is restricted to `$D000-$FFF9` (`A2_LC_MAX_DATA_END`).
  2. `a2_aux_lc_bounce_xfer` stays in resident `< $7C00`, wraps transfer in
     `PHP; SEI`, captures Main `$C011` (`RDBNK2`) and `$C012` (`RDLCRAM`)
     before asserting `$C009` (`ALTZP=1`), performs **zero** ZP (`$00-$FF`) or
     stack (`$0100-$01FF`) references while `ALTZP=1`, selects Read-RAM WP
     (`$C080`/`$C088`) for reads or two consecutive `$C083`/`$C08B` reads for
     writes, copies 1..16 bytes via Main `$02E0-$02EF` using `abs,x`, clears LC
     write-enable (`bit $C080`), asserts `$C008` (`ALTZP=0`), and restores the
     exact saved Main LC switch before `PLP`.
- **MAME `apple2ee` hardware spike finding (`harness_smoke.py` `aux_lc_spike`):**
  - Reading `A2_LC_SWITCH_BASE,x` (`$C080,x`) overwrites `A` with open-bus
    garbage; the initial run proved `tax` must run *before* the first `$C080,x`
    read with a clean bypass for reads vs. two `$C083`/`$C08B` reads for writes.
  - Passing spike (`17/17` assertions) proved on MAME `apple2ee`: boot
    Aux `$FFFA-$FFFF` vector initialization and preservation; Aux LC Bank 1 vs.
    Bank 2 `$D000` non-aliasing; shared upper `$E000` and near-vector
    `$FFE9-$FFF8` read/write integrity; 512/512 Aux ZP/Stack guard bytes
    untouched; 256/256 Main ZP, live Main Stack, `SP`, and `$C011/$C012/$C016`
    (`RDALTZP=0`) preserved; and clean ProDOS `MORIA8.PAK` `MLI_SET_MARK ($CE)`
    loads (`A2.PLAY`, `OVL.START`, `OVL.TOWN`) into Town immediately afterward.

### 4. Behavioral Change Protocol Record (Phase 1)

```text
Problem and success criteria: Relieve tight Apple IIe Main resident (< $7C00) and ProDOS 140 KB floppy block budgets, claim Aux $0200-$03FF, and prove safe ALTZP=1 Aux LC ($D000-$FFF9) access under MAME apple2ee without touching core/. Success = Default <= $7BFF with positive margin, >= 28 free .po blocks with LICENSE/SOURCE.OFFER standalone, Aux LC MAME spike PASS, and all Apple II contract/runtime suites PASS.
State being changed: Placement of zp_save_buf ($0200-$028D) and 20 resident scratch bytes ($0301-$033A); Aux $0200-$03FF window bounds; Aux LC vector/data protocol via $02E0-$02F3 bounce; MORIA8.PAK entry count (8 -> 19) and cold BIN packing.
Search scope and terms: rg across platforms/apple2/, core/, platforms/commodore/, tools/ for zp_save_buf, DUNGEON_GEN_DOOR_SCAN_BASE, PLATFORM_HD_DECODE_BUF_BASE, hal_asset_load, hal_storage_marker_init, hal_storage_program_probe_name, A2.PLAY, legal_ui_filename, a2_ss_buf, and moved scratch symbol names.
Relevant readers/writers found and known exclusions: Main $0200-$028F only read/written by save_zp/restore_zp (a2_mli_begin/end) and legal.s; $0301-$033A owned solely by Apple II storage/screen/input drivers and cleared in a2_reset_session_state (strictly < $033C DUNGEON_GEN_DOOR_SCAN_BASE / PLATFORM_HD_DECODE_BUF_BASE); $02E0-$02F3 owned solely by a2_aux_lc_*; Aux $FFFA-$FFFF owned solely by a2_aux_lc_init_vectors; save_device..disk_setup_done ($0A03-$0A06) deliberately kept at fixed Default addresses for harness compatibility.
Initialization, reset and persistence points: a2_reset_session_state clears $0301-$033A on boot and session restart; hal_platform_init_early calls a2_aux_lc_init_vectors once at boot; Aux $0200-$03FF reserved unallocated; save file format unchanged.
Affected production sequence through the changed transition: MORIA8.SYSTEM boot reads PAK entries 0..7 sequentially (header count >= 8) -> Default enters hal_platform_init_early (installs Aux vectors) -> a2_reset_session_state zeros $0301-$033A -> Title/legal/chargen/town/storage load TITLE/LEGALUI/A2.PLAY/OVL.* via a2_pak_resolve + a2_pak_open_seek (MLI_SET_MARK $CE) inside a2_mli_begin/end (zp_save_buf at $0200).
Contract decision or selected upstream oracle with source locations: Apple IIe TRM §3.3.1 (MLI ZP $3A-$4E), TRM §5.2.2.2 (/RAM disconnect), Sather Understanding the Apple IIe Ch. 5 ($C008/$C009 ALTZP + $C080-$C08B LC double-read write-enable semantics), ProDOS MLI SET_MARK ($CE), AGENTS.md Rule 7 (standalone LICENSE & SOURCE.OFFER).
Intentional Moria8 deviations: None to gameplay; hal_asset_load drops standalone raw-file fallback for uncached assets because all code/title assets live inside MORIA8.PAK (only LICENSE/SOURCE.OFFER/saves/marker/scores are standalone ProDOS files).
Input/intermediate widths, signedness, carry, range and overflow policy: make_pak.py enforces MAX_ENTRIES = 42 so 256-byte prefix (2 + 42*2 = 86; 128 + 42*3 = 254 < 256) never overflows 256-byte a2_ss_buf, and entries <= 65,535 B; a2_pak_open_seek bounds-checks entry_id < 42 and < a2_ss_buf[0] and zero-length guard; a2_aux_lc_bounce_xfer handles count 1..16 (bounce 16 B) and masks bank to $00/$08.
RNG reduction and bias, if applicable: N/A (no RNG logic modified; verified zero core/ RNG edits).
Affected platforms, overlays, banks and owners: platforms/apple2/, tools/make_pak.py, and tools/check_hal_asset_exports.py (Apple IIe PAK contract checks) only. Core/, shared platforms/, and all other ports untouched.
Required production-path tests: platforms/apple2/check_memory_contract.py (--selftest + full contract), make diskapple2 (MORIA8.PAK 19 entries + LICENSE/SOURCE.OFFER standalone + 31 free blocks), tools/check_hal_storage_exports.py, test_prayer_regression.py, and MAME apple2ee suite make testapple2-runtime including aux_lc_spike.
Known behavior explicitly out of scope: Moving runtime code/data (e.g., tier blobs, strings, or overlays) into Aux LC $D000-$FFF9 or Aux $0200-$03FF (deferred to later phases).
Unresolved uncertainty and risk: MAME apple2ee spike verifies the ALTZP=1 bounce mechanism in emulation; real enhanced Apple IIe silicon shares identical Sather LC/ALTZP hardware rules, with risk explicitly isolated to future phases that enable Aux LC payloads. No Aux LC payload writes happen during gameplay yet.
```

### 5. Verification Rows (Phase 1)

| Contract / Domain Check | Status | Evidence (2026-11-14) |
| --- | --- | --- |
| Main `$0A00-$7BFF` always-resident ceiling (`< $7C00`) | PASS | `check_memory_contract.py`: `moria8a2.prg` `$0A00-$7BD4` (`29,141 / 29,184 B`, **43 B free**) |
| Main `$0200-$028F`, `$02E0-$02F3`, `$0301-$033B`, Aux `$0200-$03FF` bounds | PASS | `memory.s` KickAss `.assert`s (`424/424`), `check_memory_contract.py --selftest` (`11/11`), `check_memory_contract.py` (`21/21`) |
| `MORIA8.PAK` 19-entry boot (0..7) + `MLI_SET_MARK ($CE)` cold loads (8..18) + standalone `LICENSE`/`SOURCE.OFFER` | PASS | `make diskapple2` (`103,920 B` PAK, `249/280` blocks, **31 free**); `make testapple2-runtime` exercises boot, title art, legal modal, chargen, overlays, save/load, and disk setup |
| `ALTZP=1` Aux LC `$D000-$FFF9` (`SEI`, ZP-free, stack-free, Aux vectors `$FFFA-$FFFF`, Bank 1/2 isolation, Main restore) | PASS | MAME `apple2ee` `aux_lc_spike` (`17/17` asserts PASS, incl. post-spike `MORIA8.PAK` `MLI_SET_MARK` Town load) |
| Exported HAL storage labels & contract boundaries | PASS | `PYTHONDONTWRITEBYTECODE=1 make check-hal-boundaries` PASS (19/19 checks exit 0, incl. `tools/check_hal_storage_exports.py` `98 labels x 7 platforms` and `tools/check_hal_asset_exports.py` with `check_apple2_pak_loader()`) |
| Physical display-layout / `core/` parity | N/A | Zero `core/` or display-geometry changes |

## Phase 2 Cold Code Eviction & `OVL.HOME` (2026-11-14)

Port-local cold-code eviction and `HOME_OVERLAY_SEPARATE` adoption inside `platforms/apple2/` (zero `core/` edits).

### 1. Standardized Overlay IDs & Dedicated `OVL.HOME`

- **Enabled `#define HOME_OVERLAY_SEPARATE`** in `platforms/apple2/main.s`:
  - `OVL.TOWN` retains `store.s`, `ui_store.s`, and `inv_add_carried: { :InvAddCarriedBody() }` (`4,442 / 5,632 B`, **1,190 B free**, up from `265 B`).
  - `HomeOverlay` (`ovl.home`, `$A400-$A91B`, `1,308 / 5,632 B`, **4,324 B free**) owns `core/ui_home.s` (including its scoped `home_inv_add_carried: { :InvAddCarriedBody() }` under `HAL_PLATFORM_INV_ADD_CARRIED_EXTERNAL`) and `core/ui_home_text.s`.
  - Resident `tramp_store_enter` dispatches `#STORE_HOME` (`zp_store_idx == 7`) to `OVL_HOME` (`home_enter`) and townsfolk stores to `OVL_TOWN` (`store_enter`) via `tramp_ovl_dispatch`.
- **Standardized overlay indices (`13` overlay classes, `hal_platform_overlay_count = 13`):**
  - Because `HAL_PLATFORM_MAP_GET_TILE_USES_SUBROUTINE` gates entries `11..13` in `common/overlay.s`, `platforms/apple2/main.s` explicitly defines `OVL_HOME = 11`, `OVL_STORAGE = 12`, and `OVL_TITLE = 13`.
  - `platforms/apple2/overlay_storage.s` (`a2_ovl_cache_lo/hi`, asserted `== hal_platform_overlay_count`) marks `OVL_CHEST`, `OVL_HOME`, `OVL_STORAGE`, and `OVL_TITLE` as cold on-demand (`$00`).
  - `platforms/apple2/storage_mli.s` adds `hal_storage_overlay_home_name` (`"OVL.HOME"`), inserts PAK entry `15` for `OVL.HOME` between `OVL.CHEST` (`14`) and `OVL.STORAGE` (`16`) / `OVL.TITLE` (`17`), and shifts `A2_PAK_ENTRY_LEGALUI = 18` and `A2_PAK_ENTRY_TITLE = 19`.
  - `MORIA8.PAK` grows from `19` to `20/42` entries (`104,317 B`); `build/moria8-apple2.po` uses `250/280` blocks (**30 blocks = 15,360 B free**, standalone `LICENSE` and `SOURCE.OFFER` preserved).

### 2. Cold Code Eviction (`Default` & `A2PlaySlot` Relief)

- **`save_stream.s` map/mode helpers -> `StorageOverlay` (`+194 B` in `Default`):**
  - `a2_save_block_mode` / `hal_storage_save_block_mode`, `save_write_map_c128`, and `load_read_map_c128` (`194 B`) are called solely from `platforms/shared/save.s` (which already resides in `StorageOverlay`) and moved into `.segment StorageOverlay`. `ovl.storage` moves from `347 B` free to **153 B free** (`$A400-$B966`).
- **Cold spell/potion handlers -> `DeathOverlay` behind `tramp_death_call_restore_spell`:**
  - Enabled `#define EFF_FIND_DOORS_EXTERNAL` (`58 B`) and `#define EFF_DESTROY_TRAPS_DOORS_EXTERNAL` (`170 B`) around `core/spell_effects.s` / `core/spell_effects_overlay.s` and moved `eff_find_doors_impl` (with `eff_fd_row` in `DeathOverlay`) and `eff_destroy_traps_doors_impl` into `DeathOverlay`.
  - Relocated `#import "../../core/eff_gain_stat.s"` (`102 B`) out of `A2PlaySlot` into `DeathOverlay` (routed from `SpellOverlay` `iq_dispatch_p3_spell` via resident `tramp_eff_potion_gain_stat`, updated assert `eff_potion_gain_stat >= $a400 && eff_potion_gain_stat < ovl_death_end`).
  - Factored `tramp_eff_earthquake`, `tramp_eff_map_area`, `tramp_eff_destroy_area`, `eff_destroy_traps_doors`, `eff_find_doors`, and `tramp_eff_potion_gain_stat` through shared resident `tramp_death_call_restore_spell` (`X/Y` target in `OVL.DEATH`, `A` preserved on stack across `overlay_load`, returning via `tramp_restore_spell_overlay`). `ovl.death` moves from `1,653 B` free to **1,322 B free** (`$A400-$B4D5`).
- **`run_initialize_impl` & trampoline factoring (`Default` `43 -> 290 B` free, `A2PlaySlot` `66 -> 334 B` free):**
  - Switched `:PlayerRunInitializeSegment()` from `A2PlaySlot` to `Default` (`166 B` moved to keep `run_initialize` resident without disk/overlay dependency) and replaced the 3-byte `jmp run_initialize_impl` stub with `.label run_initialize = run_initialize_impl`.
  - Extracted `tramp_ovl_dispatch` (`A/Y` target, `X` overlay ID) for single-call no-arg overlay trampolines (`OVL_DUNGEON_GEN`, `OVL_UI`, `OVL_SPELL`, `OVL_MODAL_MISC`, `OVL_CHEST`, `OVL_STARTUP`, `OVL_STORAGE`, `tramp_store_enter`).

### 3. Behavioral Change Protocol Record (Phase 2)

```text
Problem and success criteria: Apple IIe Default (< $7C00) had 43 B free, A2PlaySlot (< $A000) had 66 B free, and ovl.town had 265 B free. Phase 2 target: adopt HOME_OVERLAY_SEPARATE (ovl.home, OVL_HOME = 11, OVL_STORAGE = 12, OVL_TITLE = 13), relieve BOTH Default and A2PlaySlot to >= 250+ B free without touching core/ or shared files, update check_memory_contract.py, and keep moria8-apple2.po within 280 ProDOS blocks with LICENSE/SOURCE.OFFER intact.
State being changed: Placement of ui_home.s + ui_home_text.s (TownOverlay -> HomeOverlay); PAK entries 15..19 and overlay IDs 11..13; placement of a2_save_block_mode / save_write_map_c128 / load_read_map_c128 (Default -> StorageOverlay); placement of eff_find_doors_impl + eff_destroy_traps_doors_impl (Default -> DeathOverlay) and eff_gain_stat.s (A2PlaySlot -> DeathOverlay); placement of run_initialize_impl (A2PlaySlot -> Default); trampoline factoring via tramp_death_call_restore_spell and tramp_ovl_dispatch.
Search scope and terms: rg across core/, platforms/shared/, platforms/apple2/, and tools/ for OVL_, hal_platform_overlay_count, a2_ovl_cache, A2_PAK_ENTRY, tramp_store_enter, store_enter, home_enter, STORE_HOME, eff_find_doors, eff_destroy_traps_doors, eff_potion_gain_stat, iq_dispatch_p3_spell, run_initialize, a2_save_block_mode, save_write_map, load_read_map.
Relevant readers/writers found and known exclusions: try_store_entry (core/game_loop.s) sets zp_store_idx and calls tramp_store_enter; ui_home.s is self-contained under HOME_OVERLAY_SEPARATE with scoped home_inv_add_carried; save block/map helpers are called solely by shared/save.s inside StorageOverlay; eff_find_doors and eff_destroy_traps_doors are called solely from SpellOverlay (wizard.s direct jmp is compiled out under HAL_PLATFORM_WIZARD_REVEAL_TRAMPOLINE); eff_potion_gain_stat is called solely by iq_dispatch_p3_spell in SpellOverlay (player_item_commands.s direct call is compiled out under HAL_PLATFORM_COMPACT_PLAY_SLOT); run_initialize is called solely from game_loop.s. Aux LC $D000-$FFF9 was checked and intentionally excluded from code placement because ALTZP=1 swaps ZP and Stack.
Initialization, reset and persistence points: a2_ovl_cache_lo/hi and a2_overlay_pak_id tables validated at assembly time against hal_platform_overlay_count (13); eff_fd_row and egs_old live inside DeathOverlay (initialized on entry, transient per load); save format and ZP/low-scratch/Aux-data allocations are unchanged.
Affected production sequence through the changed transition: Step onto Home door -> check_player_on_store_door returns STORE_HOME (7) -> tramp_store_enter loads OVL.HOME from MORIA8.PAK entry 15 and jumps to home_enter; Cast/pray/quaff gain-stat from SpellOverlay -> resident stub enters tramp_death_call_restore_spell (preserves A across overlay_load #OVL_DEATH) -> executes in DeathOverlay -> tramp_restore_spell_overlay reloads OVL_SPELL from Aux cache -> returns cleanly to caller; Save/load -> StorageOverlay directly invokes colocated a2_save_block_mode / save_write_map_c128 / load_read_map_c128.
Contract decision or selected upstream oracle with source locations: core/ui_home.s and platforms/commodore/common/overlay.s Phase 2 Wave 1 contract (HOME_OVERLAY_SEPARATE, OVL_HOME=11..OVL_TITLE=13); Apple IIe window $A400-$B9FF overlay mutual exclusion and Aux cache $5A00-$BFFF slots in platforms/apple2/cache_layout.s; AGENTS.md Rule 7 standalone ProDOS LICENSE/SOURCE.OFFER.
Intentional Moria8 deviations: Because HAL_PLATFORM_MAP_GET_TILE_USES_SUBROUTINE suppresses OVL_HOME/OVL_STORAGE/OVL_TITLE inside common/overlay.s, Apple IIe defines 11..13 explicitly in platforms/apple2/main.s and inserts OVL.HOME at MORIA8.PAK index 15 (shifting LEGALUI/TITLE to 18/19).
Input/intermediate widths, signedness, carry, range and overflow policy: hal_platform_overlay_count == 13 asserted against hal_storage_overlay_name_len, a2_ovl_cache_lo/hi, and a2_overlay_pak_id; all 20 PAK entries remain <= 42 max; tramp_death_call_restore_spell preserves A across overlay_load via stack (single byte push/pop on balanced load-fail path) and returns flags via tramp_restore_spell_overlay PLP; tramp_ovl_dispatch preserves target A/X/Y/P via indirected JMP $0000 after overlay_load.
RNG reduction and bias, if applicable: N/A (zero RNG code modified; eff_gain_stat.s still calls resident rng_range verbatim).
Affected platforms, overlays, banks and owners: platforms/apple2/ only (main.s, save_stream.s, storage_mli.s, overlay_storage.s, hal/lifecycle_policy.s, check_memory_contract.py, Makefile) and docs/APPLE2_MEMORY_POLICY.md. Zero core/, platforms/shared/, or other port changes.
Required production-path tests: platforms/apple2/check_memory_contract.py (--selftest + full 22-assert contract), make -C platforms/apple2 build disk (20-entry PAK, 250/280 .po blocks with LICENSE/SOURCE.OFFER), make check-hal-boundaries check-6502-lint, and MAME apple2ee runtime suite make -C platforms/apple2 test-runtime.
Known behavior explicitly out of scope: Aux LC $D000-$FFF9 payload relocation and Aux $0200-$03FF data migration (deferred beyond Phase 2).
Unresolved uncertainty and risk: MAME apple2ee runtime suite tests boot, title, legal, chargen, overlays, wizard reveal, save/load, and disk setup; interactive Home deposit/retrieve and gain-stat potion paths are verified by assembly layout, contract assertions, and shared core/ui_home.s Wave 1 parity.
```

### 4. Verification Rows (Phase 2)

| Contract / Domain Check | Status | Evidence (2026-11-14) |
| --- | --- | --- |
| Main `$0A00-$7BFF` always-resident ceiling (`< $7C00`) & `A2PlaySlot` (`$7C00-$9FFF`) headroom | PASS | `check_memory_contract.py` + `report_memory_budgets.py`: `moria8a2.prg` `$0A00-$7ADD` (`28,894 / 29,184 B`, **290 B free**); `a2.play` `$7C00-$9EB1` (`8,882 / 9,216 B`, **334 B free**) |
| All 13 overlays (`$A400-$B9FF`), `OVL.HOME`, Aux cache slots, ZP/scratch bounds | PASS | `check_memory_contract.py --selftest` (`11/11`) + `check_memory_contract.py` (`22/22` asserts, incl. `ovl.home $A400-$A91B` `1,308 B`, `ovl.town $A400-$B559` `4,442 B`, `ovl.death $A400-$B4D5` `4,310 B`, `ovl.storage $A400-$B966` `5,479 B`) |
| `MORIA8.PAK` 20-entry container & ProDOS `.po` capacity + `LICENSE`/`SOURCE.OFFER` | PASS | `make -C platforms/apple2 disk`: `MORIA8.PAK` `20/42` entries (`104,317 B`); `build/moria8-apple2.po` `250/280` blocks used (**30 free / 15,360 B**), standalone `LICENSE` (`344 B`) & `SOURCE.OFFER` (`499 B`) intact |
| HAL boundaries & 6502 lint | PASS | `PYTHONDONTWRITEBYTECODE=1 make check-hal-boundaries check-6502-lint` PASS (`0` HAL violations; `386` files, `0` errors, `0` warnings in `platforms/apple2/`) |
| MAME `apple2ee` runtime suite (`make -C platforms/apple2 test-runtime`) | PASS | `26/26` MAME `apple2ee` scenarios PASS (`boot_title`, `priest_pray`, `priest_map_area`, `help_overlay` `28/28`, `wizard_flow`, `wizard_summon_town`, `scroll_rune`, `balrog_victory`, `quaff_p3`, `scroll_objdet`, `deep_objdet`, `scroll_map`, `dungeon_descend`, `catalog_spawn`, `death_flow`, `save_load`, `mage_list`, `scroll_delta`, `disk_setup_two_drive`, `disk_setup_swap`, `disk_setup_adopt`, `save_slot_tracking`, `weapon_exchange`, `acid_armour`, `aux_lc_spike`, `save_reboot_load`) after updating `platforms/apple2/harness_smoke.py:559,615` to wait for both `"Command Reference"` and `"L:License"` |
| Physical display-layout / `core/` parity | N/A | Zero `core/`, `platforms/shared/`, or display-geometry edits |

## Phase 3 Declarative Trampolines & Identify Spell Restore (2026-11-14)

Port wiring for `build/trampolines/apple2_trampolines.inc` (`tools/trampoline_manifest.py` `APPLE2_ENTRIES`) and `ovl_spell_restore` fix for Mage Spell #20 (`Identify`) `OVL_SPELL` eviction.

### 1. Generated Trampolines & `Identify` Fix Summary

- **`platforms/apple2/Makefile`:** Added `TRAMPOLINES_INC = $(BUILD)/trampolines/apple2_trampolines.inc` rule invoking `python3 -B "$(GEN_TRAMPOLINES_TOOL)" --port apple2 --output "$@"` (depending on `tools/gen_trampolines.py` and `tools/trampoline_manifest.py`) and added `$(TRAMPOLINES_INC)` as a prerequisite of `$(A2_MAIN_STAMP)`.
- **`platforms/apple2/main.s`:** Replaced all `66` generated `tramp_*` definitions (`kind != "custom"` in `APPLE2_ENTRIES`) with `#import "../../build/trampolines/apple2_trampolines.inc"` in `.segment Default` (strictly `< $7C00`, keeping `A2PlaySlot` unchanged). Preserved all `16` `custom` trampolines (`15` in `platforms/apple2/main.s` — `tramp_dig_ability` in `A2PlaySlot`, `tramp_ovl_dispatch`, `tramp_death_call_restore_spell`, `tramp_store_enter`, `tramp_game_over_run`, `tramp_do_look`, `tramp_inv_add_carried`, `tramp_items_dispatch`, `tramp_items_jmp`, `tramp_spell_call_items`, `!restore_overlay` tail block `tramp_ui_view_restore_spell_overlay`..`tramp_combat_apply_levelup_modal`, and `tramp_ego_append_suffix` — plus `tramp_ui_legal_display` in `platforms/apple2/legal.s`) and all non-`tramp_*` helpers and shared fallthroughs intact.
- **Mage Spell #20 (`Identify`) `OVL_SPELL` restore fix:** `tramp_spell_execute_selected` in `build/trampolines/apple2_trampolines.inc` is generated as `ovl_spell_restore` (`lda #OVL_SPELL / jsr overlay_load / bcs !done+ / jsr spell_execute_selected / !done: jmp tramp_restore_spell_overlay`), restoring `OVL_SPELL` in `$A400-$B9FF` when `eff_identify_prompt` invokes `show_inv_and_select` (`OVL_UI`) with `+0 B` in `OVL.SPELL` (`cache.ovl.spell` remains `5,100 / 5,120 B`, **20 B free**).
- **Before / After Memory Headroom (Phase 2 -> Phase 3 Wave 1+2):**
  - `Default` (`moria8a2.prg` / `MORIA8.RES`, `< $7C00`): `$0A00-$7ADD` (`28,894 B`, **290 B free**) -> `$0A00-$7ACB` (`28,876 / 29,184 B`, **308 B free**, **+18 B headroom** combined with Wave 1's `-18 B` removal of the `$0102,x`/`$0104,x` stack probe in `core/player_items.s`; note `apple2_trampolines.inc` currently still retains the safe idempotent `piw_return_overlay` stores in `tramp_select_filtered_inv*` / `tramp_restore_spell_overlay`).
  - `A2PlaySlot` (`a2.play`, `< $A000`): `$7C00-$9EB1` (`8,882 / 9,216 B`, **334 B free**) -> **unchanged** (`$7C00-$9EB1`, **334 B free**).
  - `cache.ovl.spell` / `ovl.spell` (Aux cache `$6D00-$80FF`, `5,120 B` cap): `5,100 B` (**20 B free**) -> **unchanged** (`5,100 B`, **20 B free** in cache; `532 B` free vs `$BA00`).
  - `cache.ovl.items` / `ovl.items` (Aux cache `$AA00-$BFFF`, `5,632 B` cap): `5,582 B` (**50 B free**) -> `5,587 / 5,632 B` (**45 B free**, `+5 B` from Wave 1 `core/player_item_select.s` `#OVL_ITEMS` store under `PLAYER_ITEM_SELECT_EXTERNAL`).

### 2. Behavioral Change Protocol Record (Phase 3)

```text
Problem and success criteria: Replace hand-maintained generated tramp_* stubs in platforms/apple2/main.s with build/trampolines/apple2_trampolines.inc generated from tools/trampoline_manifest.py (APPLE2_ENTRIES), fix Mage Spell #20 (Identify) OVL_SPELL eviction when eff_identify_prompt invokes show_inv_and_select (OVL_UI) via ovl_spell_restore on tramp_spell_execute_selected, and wire build/trampolines/apple2_trampolines.inc into platforms/apple2/Makefile within all Apple IIe memory/cache budgets. Success = all Apple IIe build, disk, memory-contract (22 + 11 selftest), trampoline/overlay checks, and 26/26 MAME apple2ee runtime scenarios PASS.
State being changed: platforms/apple2/Makefile adds TRAMPOLINES_INC rule/prerequisite for $(A2_MAIN_STAMP); platforms/apple2/main.s removes 66 generated tramp_* stubs and imports build/trampolines/apple2_trampolines.inc in Default (< $7C00); tramp_spell_execute_selected adopts ovl_spell_restore (jsr spell_execute_selected -> jmp tramp_restore_spell_overlay). Default footprint changes from $0A00-$7ADD (28,894 B, 290 B free) to $0A00-$7ACB (28,876 B, 308 B free); OVL.ITEMS moves from 5,582 B (50 B free) to 5,587 B (45 B free) from Wave 1 core/player_item_select.s; A2PlaySlot (8,882 B, 334 B free) and OVL.SPELL (5,100 B, 20 B free in cache.ovl.spell) are unchanged.
Search scope and terms: rg -n "piw_return_overlay" across core/ and platforms/apple2/; APPLE2_ENTRIES in tools/trampoline_manifest.py; platforms/apple2/main.s; platforms/apple2/legal.s; core/player_items.s; core/player_item_select.s; core/player_magic.s; core/player_magic_execute_overlay.s; core/spell_effects.s.
Relevant readers/writers found and known exclusions: show_inv_and_select (core/player_items.s) unconditionally reads X = piw_return_overlay and clears piw_return_overlay = #OVL_NONE; piw_select_filtered_inv_key (core/player_item_select.s) sets piw_return_overlay = #OVL_ITEMS under PLAYER_ITEM_SELECT_EXTERNAL before calling show_inv_and_select; apple2_trampolines.inc retains safe idempotent piw_return_overlay stores in tramp_select_filtered_inv, tramp_select_filtered_inv_key_spell, and tramp_restore_spell_overlay (tools/ is outside this task's file ownership). tramp_spell_execute_selected is called solely by player_cast_spell and player_pray (OVL_SPELL) -> spell_execute_selected (OVL_SPELL). Exclusions: 16 custom trampolines (15 in main.s + tramp_ui_legal_display in legal.s) and non-tramp_* helpers/fallthroughs (eff_destroy_traps_doors, eff_find_doors, chest_dispatch, etc.) stay hand-authored; core/, tools/, and other ports untouched.
Initialization, reset and persistence points: Unchanged; piw_return_overlay is initialized/cleared inside show_inv_and_select and session reset, and Aux cache slots (overlay_storage.s) and save file layout are unchanged.
Affected production sequence through the changed transition: Build: make -C platforms/apple2 updates build/trampolines/apple2_trampolines.inc before KickAss assembles main.s into Default. Runtime (Identify spell): player_cast_spell (OVL_SPELL) -> tramp_spell_execute_selected (Default) loads OVL_SPELL and JSRs spell_execute_selected -> eff_identify_prompt (Default) -> show_inv_and_select (OVL_UI, evicting OVL_SPELL at $A400-$B9FF) -> returns to tramp_spell_execute_selected -> jmp tramp_restore_spell_overlay reloads OVL_SPELL from Aux cache $6D00-$80FF with preserved A/X/P and returns safely to player_cast_spell.
Contract decision or selected upstream oracle with source locations: Single mutually-exclusive $A400-$B9FF overlay window and Aux cache slot discipline in docs/APPLE2_MEMORY_POLICY.md / platforms/apple2/overlay_storage.s; Phase 3 manifest and caller-restore invariant in tools/trampoline_manifest.py (APPLE2_ENTRIES) and tools/check_overlay_calls.py.
Intentional Moria8 deviations: None to gameplay; ovl_spell_restore keeps the OVL_SPELL restoration inside resident Default ($0A00-$7ACB) so Mage Spell #20 ?-selector eviction of OVL_SPELL adds 0 B to tight cache.ovl.spell (20 B free).
Input/intermediate widths, signedness, carry, range and overflow policy: tramp_spell_execute_selected branches on overlay_load carry fail (bcs !done+) before JSR; normal return enters tramp_restore_spell_overlay which preserves A/X/P across overlay_load #OVL_SPELL via stack (pha/txa/pha/php/plp). Default stays strictly < $7C00 (308 B free) and all 13 overlays fit $A400-$B9FF and their Aux cache slots.
RNG reduction and bias, if applicable: N/A (zero RNG code changed; zero core/ edits in Wave 2).
Affected platforms, overlays, banks and owners: platforms/apple2/Makefile, platforms/apple2/main.s (Default < $7C00), and docs/APPLE2_MEMORY_POLICY.md only. A2PlaySlot, Aux RAM segments, and all 13 overlay binaries are unchanged by Wave 2 (OVL.ITEMS +5 B and Default -18 B stack probe come from Wave 1 core/ edits).
Required production-path tests: make -C platforms/apple2 build disk test-memory-contract test-memory-contract-selftest; python3 -B tools/gen_trampolines.py --port apple2 --output build/trampolines/apple2_trampolines.inc --check; strict validate_manifest_and_sources(..., strict_migrated=True) for apple2; python3 -B tools/check_overlay_calls.py --port apple2 --check-sym; python3 -B tools/report_memory_budgets.py --port apple2; ./tools/isolated.sh make testapple2-runtime (26/26 MAME apple2ee scenarios).
Known behavior explicitly out of scope: Stripping the now-redundant piw_return_overlay stores in tools/gen_trampolines.py (Wave 1 ownership) and relocating runtime payloads into Aux LC $D000-$FFF9 or Aux $0200-$03FF.
Unresolved uncertainty and risk: cache.ovl.spell has 20 B free (5,100 / 5,120 B) and cache.ovl.items / ovl.items has 45 B free (5,587 / 5,632 B), both enforced by check_memory_contract.py. The 26/26 MAME apple2ee suite verifies cast, pray, inventory/recharge item-selection, help/legal, save/load, and overlay switching end-to-end; interactive Mage Spell #20 Identify ?-selector invocation is verified by static cross-overlay call/symbol checks (check_overlay_calls.py --check-sym) and inspection of the generated ovl_spell_restore path rather than a dedicated new Identify scenario.
```

### 3. Verification Rows (Phase 3)

| Contract / Domain Check | Status | Evidence (2026-11-14) |
| --- | --- | --- |
| Main `$0A00-$7BFF` always-resident ceiling (`< $7C00`) & `A2PlaySlot` (`$7C00-$9FFF`) headroom | PASS | `check_memory_contract.py` + `report_memory_budgets.py --port apple2`: `MORIA8.RES` / `Default` `$0A00-$7ACB` (`28,876 / 29,184 B`, **308 B free**); `A2.PLAY` / `A2PlaySlot` `$7C00-$9EB1` (`8,882 / 9,216 B`, **334 B free**) |
| Tight Aux cache & overlay headroom (`cache.ovl.spell`, `cache.ovl.items` / `ovl.items`, 13 overlays `$A400-$B9FF`) | PASS | `check_memory_contract.py` (`22` asserts, `0` failures) + `check_memory_contract.py --selftest` (`11` asserts, `0` failures) + `report_memory_budgets.py`: `ovl.spell` / `cache.ovl.spell` `5,100 / 5,120 B` (**20 B free**; `532 B` vs `$BA00`), `ovl.items` / `cache.ovl.items` `$A400-$B9D2` `5,587 / 5,632 B` (**45 B free**) |
| Declarative trampoline manifest & cross-overlay call verification (`apple2`) | PASS | `tools/gen_trampolines.py --port apple2 --output build/trampolines/apple2_trampolines.inc --check` PASS (`unchanged`); strict `validate_manifest_and_sources(..., strict_migrated=True)` for `apple2`: `(82, 66, 16)`, `0` errors; `tools/check_overlay_calls.py --port apple2 --check-sym`: PASS (`0` cross-overlay violations) |
| `MORIA8.PAK` 20-entry container & ProDOS `.po` capacity + `LICENSE`/`SOURCE.OFFER` | PASS | `make -C platforms/apple2 disk`: `MORIA8.PAK` `20/42` entries (`104,304 B`); `build/moria8-apple2.po` `250/280` blocks used (**30 free / 15,360 B**), standalone `LICENSE` (`344 B`) & `SOURCE.OFFER` (`499 B`) intact |
| MAME `apple2ee` runtime suite (`./tools/isolated.sh make testapple2-runtime`) | PASS | `26/26` MAME `apple2ee` scenarios PASS (`0` failures across `boot_title`, `priest_pray`, `priest_map_area`, `help_overlay`, `wizard_flow`, `wizard_summon_town`, `scroll_rune`, `balrog_victory`, `quaff_p3`, `scroll_objdet`, `deep_objdet`, `scroll_map`, `dungeon_descend`, `catalog_spawn`, `death_flow`, `save_load`, `mage_list`, `scroll_delta`, `disk_setup_two_drive`, `disk_setup_swap`, `disk_setup_adopt`, `save_slot_tracking`, `weapon_exchange`, `acid_armour`, `aux_lc_spike`, `save_reboot_load`) |
| Physical display-layout / `core/` parity | N/A | Zero `core/` or display-geometry edits in Apple IIe Wave 2 |

## Phase 4 Item Catalog (`ITEM.CAT`), Aux LC Preload, & Save Format V2 (2026-11-15)

### 1. Summary of Phase 4 Memory & Media Layout

- **Aux Language Card (`$D000-$FFF9`, `16,378 B`) Production Adoption:** Preloads `'ITM2'` `ITEM.CAT` (`7,478 B` at `$E000-$FD35` in current 361-item catalog; `7,573 B` at `$E000-$FD94` at Phase 4) at boot into Aux LC High RAM and places `recall[279]` (`1,116 B`) in Aux LC Bank 1 `$D000-$D45B`, accessed through the `SEI`, ZP-free `ALTZP=1` bounce at `$02E0-$02F3` (`platforms/apple2/memory_aux_lc.s`) with port-owned Aux interrupt vectors (`$FFFA-$FFFF`).
- **Aux Low (`$0200-$03FF`, `512 B`) & `A2AuxData` (`$3B0C-$4FFF`):** Places `id_known_bits[47]`, `potion_shuffle..staff_shuffle` (`174 B`), `si_meta_hi[128]`, and `fi_meta_hi[42]` in Aux `$0200-$0386` (`391 B` used, `121 B` free), and retires legacy resident/aux item-name streams in favor of `ITEM.CAT`, leaving `A2AuxData` at `$3B0C-$4F0B` (`5,120 / 5,364 B`, **244 B free**).
- **Main Resident & Overlays:** `Default` (`moria8a2.prg`) spans `$0A00-$7BA9` (`29,098 / 29,184 B`, **86 B free** `< $7C00`); `A2PlaySlot` (`a2.play`) spans `$7C00-$9FF9` (`9,210 / 9,216 B`, **6 B free** `< $A000`); all 13 overlays fit `$A400-$B9FF` (`5,632 B`) and their Aux cache slots (`ovl.items` `5,597 / 5,632 B`, **35 B free**; `ovl.gen` `5,554 / 5,632 B`, **78 B free**; `ovl.storage` `5,181 / 5,632 B`, **451 B free**; `ovl.spell` `5,100 / 5,120 B`, **20 B free** in cache; `ovl.modal` `3,028 / 3,072 B`, **44 B free** in cache).
- **Shipping `140 KB` ProDOS `.po` (`build/moria8-apple2.po`, Phase 4 snapshot):** `MORIA8.PAK` (`20/42` entries, `110,794 B`) + standalone `ITEM.CAT` (`7,573 B` at Phase 4; consolidated into `MORIA8.PAK` at `7,478 B` in Phase 5) + `LICENSE` (`344 B`) + `SOURCE.OFFER` (`499 B`) = **`279 / 280` blocks used (`1` block = `512 B` free)**.

### 2. Verification Rows (Phase 4)

| Contract / Domain Check | Status | Evidence (2026-11-15) |
| --- | --- | --- |
| Main `$0A00-$7BFF` (`< $7C00`) & `A2PlaySlot` (`$7C00-$9FFF`) bounds | PASS | `check_memory_contract.py` + `report_memory_budgets.py --port apple2`: `Default` `$0A00-$7BAA` (`29,098 / 29,184 B`, **86 B free**); `A2PlaySlot` `$7C00-$9FFA` (`9,210 / 9,216 B`, **6 B free**) |
| Aux RAM (`$0200-$03FF`, `$3B0C-$BFFF`) & Aux LC (`$D000-$FFF9`) ownership | PASS | `A2AuxData` `5,120 / 5,364 B` (**244 B free**), `A2Catalog` `5,859 / 5,888 B` (**29 B free**), `A2HuffData` `7,313 / 7,424 B` (**111 B free**), `cache.ovl.spell` **20 B free**, `cache.ovl.items` **35 B free**, `cache.ovl.modal` **44 B free**, Aux LC `8,689 / 16,378 B` (**7,689 B free**) |
| ProDOS `.po` capacity (`279/280` blocks) + `ITEM.CAT` + `LICENSE`/`SOURCE.OFFER` | PASS | `report_memory_budgets.py --port apple2` (`0` overflows): `MORIA8.PAK` `20/42` entries (`110,794 B`), `ITEM.CAT` (`7,573 B` at Phase 4; now `7,478 B`), `.po` `279/280` blocks (`1` free) |
| Save Format V2 (`SAVE_VERSION = $20` at Phase 4, now `$22` / `17,164 B`) & playtest/contract gates | PASS | `make check-hal-boundaries`, `make check-item-docs`, `tools/report_memory_budgets.py --selftest`, and `playtest` unit suite (`780/780` PASS) |

## Phase 5 PackBits `MORIA8.PAK`, Aux LC Bank 2 `A2.CATEXT`, & Full 279-Species Catalog (2026-11-16)

### 1. Summary of Phase 5 Memory & Media Layout

- **PackBits Boot Container (`MORIA8.PAK` `22/42` entries, `119,228 B`) & `TitleOverlay:a2_boot_preload_aux_lc`:**
  - `MORIA8.SYSTEM` (`boot.s`, `PAK_COUNT = 6`) sequentially reads the 6 uncompressed boot-prefix entries (`MORIA8.RES`, `OVL.UI`, `OVL.ITEMS`, `OVL.SPELL`, `OVL.MODAL`, `A2.HUFFDATA`), then jumps to `entry_main`, which loads `OVL.TITLE` (`TitleOverlay`) and executes `a2_boot_preload_aux_lc` (`platforms/apple2/storage_mli.s`) using `A2PlaySlot` (`$7C00-$9FFF`, idle before `a2_require_play`) as staging workspace:
    1. Zeroes `recall[279]` (`1,116 B`) in Aux LC Bank 1 (`$D000-$D45B`).
    2. Opens `MORIA8.PAK` once at entry `#18` (`a2_preload_open_pak`), caches the 4 contiguous entry lengths (`#18..#21`), and streams all 4 preload payloads sequentially on the kept-open `a2_open_ref` (`a2_preload_read_next`, eliminating 3 redundant Disk II `MLI_OPEN`/directory-scan/`SET_MARK`/`MLI_CLOSE` cycles and closing `a2_open_ref` after `#21` and on every error path):
       - PackBits `A2.AUXDATA.PB` (`2,781 -> 5,120 B`) into `$7C00`, unpacked (`a2_packbits_unpack` with `RAMWRT=1`) to Aux `$3B0C-$4F0B` (`a2_preload_check_ptr1` verifies exact end).
       - PackBits `A2.CATALOG.PB` (`4,682 -> 5,859 B`) into `$7C00`, unpacked to Aux `$5000-$66E2`.
       - PackBits `A2.CATEXT.PB` (`1,228 -> 2,232 B`) into `$9000` (`A2_CATEXT_STAGE`), unpacked to Main `$7C00-$84B7`, verified as exact `2,232 B` (`279 x 8 B`), and copied into **Aux LC Bank 2 `$D000-$D8B7`** via `a2_preload_copy_play_to_lc_b2` (`1,864 B` free in Aux LC Bank 2).
       - Raw `'ITM2'` `ITEM.CAT` (`7,478 B`, PAK entry `#21`) into `$7C00`, validated for `'ITM2'` signature, copied into Aux LC High RAM `$E000-$FD35`, and `$7C00` cleared so `A2.PLAY`'s signature check stays clean.
  - At runtime, `catalog_fetch_ext` (`platforms/apple2/monster_catalog_a2.s`) fetches any species' `8` extended Phase 5 bytes from Aux LC Bank 2 (`$D000 + id * 8`) into `cat_ext_record[0..7]` with zero disk I/O and zero ZP writes via `SEI`-guarded `a2_aux_lc_bounce_xfer`. Total Aux LC usage across Bank 1 + Bank 2 + High RAM is **`10,826 / 16,378 B` (`5,552 B` free)**.
- **`ui_recall.s` Relocated to `DeathOverlay` & Wave 5.2 Cold Evictions:**
  - Moving `core/ui_recall.s` (including its 80-col read-only string/tag tables, `0 B` in `Default`) from `ModalMiscOverlay` to `DeathOverlay` relieves `cache.ovl.modal` to **`2,453 / 3,072 B` (`619 B` free)** while `ovl.death` fits at `$A400-$B9D8` (`5,592 / 5,632 B`, **`40 B` free**).
  - Wave 5.2 cold evictions (`player_chargen_cold.s` -> `ovl.start`, `trap_trigger_cold.s`/`trap_damage_cold.s` -> `ovl.chest`, `door_open_close_cold.s`/`item_drop_cold.s`/`ui_help_cmd_cold.s`/`mae_cold_body` -> `ovl.help`, `store_restock_overlay.s`/`starting_kit_cold.s` -> `ovl.title`, `player_bg_draw_cold.s` -> `ovl.ui`, `item_refresh_known_cold.s`/`load_resume_reset_cold.s` -> `ovl.storage`) fund the widened `29`-field `cr_*` buffers (`+320 B`), `cat_undead[35]`, 4-attack loop, 19 `ADESC_*` verbs, 24 `ATK_*` effects, 5 `MSF2_*` spells, and `CD_*`/`CM2_*` traits while leaving `Default` (`moria8a2.prg`) at `$0A00-$7BCB` (`29,131 / 29,184 B`, **`53 B` free** `< $7C00`) and `A2PlaySlot` (`a2.play`) at `$7C00-$9F6E` (`9,070 / 9,216 B`, **`146 B` free** `< $A000`).
- **Shipping `140 KB` ProDOS `.po` (`build/moria8-apple2.po`):** Consolidating `ITEM.CAT` + PackBits `.PB` segments into `MORIA8.PAK` (`22/42` entries, `119,228 B` = `234` blocks) leaves 5 root ProDOS files (`PRODOS` `35` blks, `MORIA8.SYSTEM` `1` blk, `MORIA8.PAK` `234` blks, `LICENSE` `1` blk, `SOURCE.OFFER` `1` blk = `272` file blocks + `7` boot/directory/bitmap blocks = **`279 / 280` blocks used, `1` block = `512 B` free**; 3 of the 4 volume directory blocks remain empty reserve).

### 2. Behavioral Change Protocol Record (Phase 5)

```text
Problem and success criteria: Fit Phase 5's widened 29-field cr_* buffers (+320 B), cat_undead[35], 2,232 B extended monster catalog A2.CATEXT, 15-field '/' recall UI, 4-attack loop, 19 ADESC_* verbs, 24 ATK_* effects, 5 MSF2_* spells, and CD_*/CM2_* behaviors into Apple IIe Main RAM (< $7C00 Default, < $A000 A2PlaySlot), Aux cache slots, Aux LC, and the 280-block 140 KB ProDOS .po disk without losing LICENSE/SOURCE.OFFER or runtime/cold-boot performance (boot_title & aux_lc_spike <= 30.0 emulated seconds).
State being changed: platforms/apple2/{Makefile,boot.s,main.s,memory.s,storage_mli.s,monster_catalog_a2.s,check_memory_contract.py} — PackBits compression of A2.AUXDATA.PB, A2.CATALOG.PB, and A2.CATEXT.PB inside 22-entry MORIA8.PAK; TitleOverlay:a2_boot_preload_aux_lc opening MORIA8.PAK once at #18 and sequentially reading/unpacking #18..#21 (A2.AUXDATA, A2.CATALOG, A2.CATEXT -> Aux LC Bank 2 $D000-$D8B7, ITEM.CAT -> Aux LC High $E000-$FD35); catalog_fetch_ext reading 8 B via a2_aux_lc_bounce_xfer; ui_recall.s moved from ModalMiscOverlay to DeathOverlay; Wave 5.2 cold code and mae_cold_body evictions across overlays.
Search scope and terms: rg across core/, platforms/apple2/, and tools/ for A2_LC_, a2_aux_lc_bounce_xfer, catalog_fetch_ext, cat_ext_record, ui_recall_display, load_resume_reset, PAK_COUNT, A2_PAK_ENTRY, a2_boot_preload_aux_lc, mae_cold_body.
Relevant readers/writers found and known exclusions: TitleOverlay:a2_boot_preload_aux_lc runs once at entry_main before A2.PLAY is loaded into $7C00-$9FFF, keeps MORIA8.PAK open across sequential entries #18..#21 (using ProDOS I/O buffer $BB00-$BEFF, disjoint from Main $7C00-$9FFF / Aux / Aux LC), closes a2_open_ref after #21 and on all error paths, and clears $7C00 afterward; catalog_fetch_ext uses Main $02F4 (A2_LC_CALLER_X) and 16-byte A2_LC_BOUNCE ($02E0-$02EF) with zero ZP mutations; DeathOverlay owns ui_recall_display + 80-col recall tables via tramp_ui_recall; HelpOverlay owns cold zero-HP melee effects (mae_cold_body) via overlay-restoring mae_cold_call.
Initialization, reset and persistence points: Aux LC Bank 1 recall[279] is zeroed and Aux LC Bank 2 A2.CATEXT + High RAM ITEM.CAT are populated in a2_boot_preload_aux_lc; Save Format V2 (SAVE_VERSION = $22, 17,164 B).
Affected production sequence through the changed transition: Cold boot MORIA8.SYSTEM (6 sequential PAK entries) -> entry_main -> overlay_load(OVL_TITLE) -> a2_boot_preload_aux_lc (1 MLI_OPEN + SET_MARK at #18, 4 sequential MLI_READs #18..#21, MLI_CLOSE: unpacks A2.AUXDATA, A2.CATALOG, A2.CATEXT -> Aux LC Bank 2 $D000-$D8B7, copies ITEM.CAT -> Aux LC High $E000) -> gameplay cat_fetch / catalog_recall_match_and_fill -> catalog_fetch_ext (8 B Aux LC Bank 2 bounce) -> '/' recall loads OVL_DEATH -> ui_recall_display.
Contract decision or selected upstream oracle with source locations: VMS Moria 4.8 279-creature catalog (platforms/shared/catalog/monster_catalog_spec.json) and Apple IIe Aux LC ZP-free SEI bounce discipline (platforms/apple2/memory.s, memory_aux.s, check_memory_contract.py).
Intentional Moria8 deviations: None to VMS gameplay; PackBits compression + single-open sequential preload in MORIA8.PAK are transparent at cold boot (~6.2 KB saved on MORIA8.PAK, 3 Disk II open/seek/close cycles eliminated).
Input/intermediate widths, signedness, carry, range and overflow policy: 9-bit catalog ID (0..278) shifted left 3 bits into 16-bit offset 0..2224 added to $D000 ($D000..$D8B7 <= $DFFF asserted in monster_catalog_a2.s); contiguous PAK entry IDs #18..#21 asserted at compile time; exact read lengths and unpacked end pointers checked by a2_preload_read_next / a2_preload_check_ptr1 (closes open ref if needed and panics with $EE on mismatch).
RNG reduction and bias, if applicable: N/A for Apple IIe memory/loader placement (shared core Phase 5 RNG rules documented in MONSTER_STATE_CONTRACT.md).
Affected platforms, overlays, banks and owners: Apple IIe Default ($0A00-$7BCB, 53 B free), A2PlaySlot ($7C00-$9F6E, 146 B free), Aux LC Bank 2 ($D000-$D8B7, 2,232 B), OVL.DEATH ($A400-$B9D8, 40 B free), OVL.TITLE ($A400-$AF42, 2,750 B free), cache.ovl.modal (619 B free), MORIA8.PAK (22/42 entries, 119,228 B), moria8-apple2.po (279/280 blocks).
Required production-path tests: make testapple2-memory-contract, make testapple2-memory-contract-selftest, tools/report_memory_budgets.py --port apple2, make testapple2-runtime (26/26 within unmodified 30.0 emulated-second boot poll), and make playtest-gate.
Known behavior explicitly out of scope: Relocating executable code into Aux RAM/Aux LC (prohibited by ALTZP stack/ZP hazard).
Unresolved uncertainty and risk: Default has 53 B free (< $7C00), A2Catalog 29 B, cache.ovl.ui 21 B, ovl.items 35 B, ovl.death 40 B, and moria8-apple2.po has 1 block (512 B) free (with 3 unused directory blocks recoverable if ever needed); all guarded fail-closed by KickAssembler .asserts and check_memory_contract.py.
```

### 3. Verification Rows (Phase 5)

| Contract / Domain Check | Status | Evidence (2026-11-16) |
| --- | --- | --- |
| Main `$0A00-$7BFF` (`< $7C00`) & `A2PlaySlot` (`$7C00-$9FFF`) bounds | PASS | `check_memory_contract.py` + `report_memory_budgets.py --port apple2`: `Default` `$0A00-$7BCB` (`29,131 / 29,184 B`, **53 B free**); `A2PlaySlot` `$7C00-$9F6E` (`9,070 / 9,216 B`, **146 B free**) |
| Aux RAM, `ui_recall.s` in `ovl.death`, & Aux LC Bank 2 `A2.CATEXT` (`$D000-$D8B7`) | PASS | `A2AuxData` `5,120 B` (**244 B free**), `A2Catalog` `5,859 B` (**29 B free**), `cache.ovl.ui` **21 B free**, `cache.ovl.items` **35 B free**, `cache.ovl.spell` **76 B free**, `cache.ovl.modal` **619 B free**, `ovl.death` `$A400-$B9D8` (**40 B free**), Aux LC `10,921 / 16,378 B` (**5,457 B free**, incl. `A2.CATEXT` `2,232 B` in Bank 2) |
| PackBits `MORIA8.PAK` (`22/42`) & ProDOS `.po` (`279/280` blocks) + `LICENSE`/`SOURCE.OFFER` | PASS | `MORIA8.PAK` `22/42` entries (`119,228 B`), `.po` `279/280` blocks (`1` block = `512 B` free), standalone `LICENSE` & `SOURCE.OFFER` verified |
| MAME `apple2ee` runtime suite & `playtest-gate` | PASS | `make testapple2-runtime` (`26/26` PASS, unmodified `30.0s` emulated boot poll) + `make playtest-gate` (`apple2` seed + tour, `0` findings) |




## Ambient Spawning Placement (MON-039, 2026-11-20)

`catalog_place_far` (`core/monster_catalog.s`: the win creature at generation
and the turn's wanderer, VMS `alloc_monster`) lives in `A2PlaySlot`, not
`Default`: `CatalogWinBegin()` / `CatalogWinEnd()` in
`platforms/apple2/monster_catalog_a2.s` switch to `A2PlaySlot` and back. Its
only callers are `monster_spawn_level` (called from `game_loop.s`) and
`turn_post_action` (`core/turn.s`), both reached only from play-slot code, so
the slot is always loaded when it runs. Because it is the first code the slot
receives, the `"M8P"` signature (`a2_play_start`, checked by
`a2_require_play` and `check_memory_contract.py` at `$7C00`) is now emitted
just before `monster_catalog_a2.s` is imported. Budgets after the change
(`report_memory_budgets.py --port apple2`): `Default` `$0A00-$7B8F`
(**113 B free**, was 46), `A2PlaySlot` `$7C00-$9FD6` (**42 B free**, was 178).
