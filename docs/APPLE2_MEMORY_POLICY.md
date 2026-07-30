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

## Implemented Layout Snapshot (2026-07-21)

This snapshot supersedes the M0 estimates and the older slot-hosted overlay
descriptions later in this document. The historical sections remain as the
design record; current ownership is enforced by `platforms/apple2/memory.s`,
`platforms/apple2/main.s`, and `platforms/apple2/cache_layout.s`.

| Range | Current owner and measured use |
| --- | --- |
| main `$0A00-$7BFF` | Always-resident image; current payload `$0A00-$7BFF` (29,184 B) |
| main `$7C00-$9FFF` | Load-once `A2.PLAY`; current payload `$7C00-$9FFD` (9,214 B including signature) |
| main `$A000-$A3FF` | Tier-name pool (1,024 B) |
| main `$A400-$B9FF` | All 11 code overlays, mutually exclusive; largest is `OVL.ITEMS`, exactly 5,632 B |
| main `$BA00-$BAFF` | Window tail reserved; tier data may use through `$BAFF` |
| main `$BB00-$BEFF` | ProDOS MLI I/O/staging buffer |
| main `$BF00-$BFFF` | ProDOS global page |
| aux `$0800-$3B0B` | Live 198x66 map |
| aux `$3B0C-$55B5` | Current immutable/mutable aux data payload (6,826 B): Huffman data, item-name streams, store inventory, recall arrays, class-spell tables, spell names, ego suffix slots, externalized message strings, and the screen-code char-map table; 330 B spare to `$56FF` |
| aux `$5700-$BFFF` | Six boot-cached overlays under cache manifest v7; page-rounded slots exactly fill the span |

`A2.PLAY` is not a modal swap slot in the implementation: every overlay,
including STORAGE and TITLE, fits the `$A400-$B9FF` code window. Play is
loaded on demand and signature-checked, then remains resident for the session.

Cache manifest v7 is shared by boot and runtime code rather than duplicated:
TOWN `$5700`, UI `$6C00`, SPELL `$7900`, MODAL `$8D00`, GEN `$9900`, ITEMS
`$AA00`, end `$C000`. Page-rounded slots fill the cache (the UI slot carries
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

### Aux RAM (ALTZP stays off)

| Range | Size | Owner |
| --- | ---: | --- |
| aux `$0400-$07FF` | 1,024 | Text page aux half (even columns) |
| aux `$0800-$3B0B` | 13,068 | Live map, 198x66 — all access via thunked MapRead/MapWrite |
| aux `$3B0C-$56FF` | 7,156 | Aux data: Huffman data, item-name streams, store inventory/runtime, recall arrays, class-spell tables, spell names, ego suffix slots, externalized message strings, char-map table = 6,826 used; 330 B spare |
| aux `$5700-$BFFF` | 26,880 | Hot cache (payloads, page-rounded slots): ovl.town 5,362 + ovl.ui 2,525 + ovl.spell 5,025 + ovl.modal 2,978 + ovl.gen 4,236 + ovl.items 5,632 = 25,758 used; slots TOWN `$5700`, UI `$6C00`, SPELL `$7900`, MODAL `$8D00`, GEN `$9900`, ITEMS `$AA00` |

On-demand from disk (never cached; all cold or disk-appropriate moments):
ovl.start (chargen), ovl.help, ovl.modal, ovl.disarm, OVL.STORAGE,
OVL.TITLE, MONSTER.DB.1-4 (tier loads), TITLE art. Disk-speed overlay loads
are the shipping stock-C64 norm, so this is not a UX regression; the aux
cache is pure latency luxury for the hot classes.

## Payload Classes

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
| ui_messages.s + ui_status.s | 2,088 | ALWAYS code; string data → AUX (L4, est. −1,500) |
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

1. **Linked symbol address**: play payload Kick segment linked at `$7C00`;
   asserts pin `play_end <= $9DFF`.
2. **BIN load address**: `A2.PLAY` file auxtype = `$7C00`; `prg_to_bin.py`
   asserts header match per payload.
3. **Destination bank at load**: main RAM, always visible — trivially
   correct (no banking on the Apple II path); the aux cache at aux `$5700+`
   holds the master copy.
4. **Visible execution bank at call site**: main RAM — trivially correct.
5. **Source-span survival**: aux cache span is disjoint from map
   (`$0800-$3B0B`) and aux data (`$3B0C-$56FF`); checker asserts all aux
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
| `MORIA8.PAK` | BIN | boot container: 512-B header (count + 16-bit lengths) then RES, AUXDATA, OVL.TOWN, OVL.UI, OVL.ITEMS, OVL.SPELL, OVL.MODAL, OVL.GEN payloads in that order |
| `A2.PLAY` | BIN `$7C00` | play payload; loaded on demand by `a2_require_play` (signature `M8P` validated) |
| `OVL.*` (cold set) | BIN `$A400` | left on disk: START, DEATH, HELP, STORAGE, TITLE |
| `MONSTER.DB.1-4` | BIN `$A400` | tier files, loaded on demand into the window |
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
lengths and boot copies are page-rounded): TOWN `$5700`, UI `$6C00`, SPELL
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
