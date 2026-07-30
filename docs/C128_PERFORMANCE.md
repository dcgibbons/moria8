# C128 Performance

Performance audit ledger for the Commodore 128 port. Companion to the
Apple II audit in `docs/APPLE2_PORT.md` (same investigation, 2026-07-25).

## 2026-07-25 audit — viewport scrolling (VDC)

Read-only audit of the player-viewport render path on the 8563 VDC.
Audit method: static call-chain tracing with hand-counted 6502 cycle
estimates (2 MHz), NOT harness profiles; relative ratios are robust,
absolute numbers are estimates. Nothing below has been implemented;
items are tracked candidates pending approval.

### Steady state (already well-tuned)

Deadband scrolling (X margin 12, Y margin 4) + local-area dirty redraw
≈ 6 ms per quiet step. Rows stream to the VDC with auto-increment
bursts and inlined `bit $D600` polling (the in-code comment at
`platforms/commodore/c128/dungeon_render_vdc.s:441-445` notes this saved
~13K cycles/refresh). All VDC rendering runs at 2 MHz (`main.s:381-384`);
the 8563 has its own clock domain so no 1 MHz forcing is needed.

### Bottlenecks

1. **Leftward horizontal scroll always full-redraws (~150 ms vs ~12 ms).**
   `dungeon_render_vdc.s:527-533`: VDC block copy smears when dest > src
   in an overlapping region, so right-shifting rows (player moving left)
   falls back to a full redraw. Half of all horizontal scrolls hit this.
   `!rvsd_h_scroll_right` (582-624) is currently dead code — the dispatch
   never reaches it.
2. **`render_single_tile` uses random-access VDC writes:**
   ~400 cy/cell of register reprogramming (12 register transactions) vs
   ~45 cy/cell in burst mode (`dungeon_render_vdc.s:1178-1203`). Taxes
   every local-area update (25-49 cells/step) and every scroll strip.
3. **Full redraw is compute-bound, not VDC-bound** (~290K cy total):
   per row it unconditionally bank-copies 78 map bytes
   (`memory128.s:762-784`), zeroes + rescans all 42 MAX_FLOOR_ITEMS even
   when empty (~1.5-2K cy), and OR-scans 78 bytes of occupancy
   (~940 cy). Nothing is cached between redraws. Compute ≈ 60%, staging
   ≈ 25%, actual VDC transfer ≈ 25%.
4. **Reg 24 copy-mode re-armed per block copy** (~400 cy to move 77
   bytes; required by hardware since the 8563 samples reg 24 when reg 30
   is written, but `vdc_select_reg` still uses jsr-based polling instead
   of the inlined poll the stream loop uses).

### 8563 features: used vs unused

| Feature | Status |
|---------|--------|
| Reg 31 auto-increment bursts | Used — viewport rows, screen_clear, screen_put_string |
| Block copy (regs 24/30/32/33) | Used — scroll-delta path only; one shift direction disabled (overlap smear) |
| Block fill | NOT used — reverted after a character-creation crash ("Opt 5 revert", screen_vdc.s:228) |
| Hardware scroll (display-start regs 12/13) | NOT used — correctly: viewport is a 78x19 sub-window, display-start would move message/status rows too |
| 2 MHz during VDC ops | Used — set at boot, reasserted after KERNAL work |
| VRAM read-modify-write | Only screen_flash_at (spell bolt); renderers are write-only |

### Candidate improvements — tracked, not approved

| # | Change | Size | Est. impact | Gate |
|---|--------|------|-------------|------|
| P3 | ~~Burst-stream the V-scroll strip; fix leftward H-scroll~~ DONE 2026-07-25 (scratch-hop block copy + shared row renderer) | medium | left scrolls ~150 ms -> ~15 ms; V-strip 78x400 -> ~3.5K cy | `TEST_FILTER='vdc_scroll_delta128' make test128` |
| P7 | VDC block-fill for screen_clear / screen_clear_row (revisit the reverted "Opt 5"; requires root-causing the past character-creation crash first) | small | screen clears at VDC speed | full `make test128` |
| P9 | Column/row-aware burst variant of render_single_tile for local-area updates (batch consecutive cells under one address setup) | medium | ~400 -> ~45 cy/cell on the per-step hot path | render contract + `make test128` |

P7 and P9 are **backlogged** (maintainer decision 2026-07-28); tracked in
`docs/BACKLOG.md`.

## 2026-07-25 — P1 implemented (glyph + item scan early-outs)

Done with the A2 P2 work (full record in `docs/APPLE2_PORT.md`):

- `rv_populate_row_items` skips the 42-slot floor-item scan when
  `zp_item_count` = 0 (the occupancy row is still zeroed).
- The per-cell `glyph_find_at` call in `render_viewport` is gated by an
  inline OR of `glyph_active[0..3]` (no cache byte: RuntimeLowData sits 3
  bytes under FLOOR_ITEM_BASE; the boundary assert caught the overflow).
- Verified: `vdc_scroll_delta128`, `main_loop128`, `make test128-fast`
  all PASS; test stub `test_vdc_scroll_delta128.s` aliases
  `glyph_active` to its `test_glyph_active` flag.

Cross-platform items P1 (item-scan early-out — the 42-slot floor-item
rescan per row here), P5 (tile-level scene-dirty in core), and the
shared full-redraw trigger structure are tracked in
`docs/APPLE2_PORT.md` (2026-07-25 audit).

Contract notes: physical VDC access is governed by
`docs/C128_MEMORY_CONTRACT.md`; any block-copy/fill change needs the
scroll-delta runtime test gate, and broad VDC changes need
`make test128` before completion.

## 2026-07-25 — P3 implemented (leftward scroll fast path + V-strip bursts)

VDC change record (Physical VDC Contract):

- active VDC registers: 18/19 (update addr), 32/33 (block source), 24
  (copy mode), 30 (word-count trigger); 31 (data) on the row burst.
- internal src/dst: char plane base $0000, attr plane base $0800, row
  stride 80; new scratch lines $1000 (char) / $1080 (attr), asserted
  clear of attribute RAM (8563 16KB).
- copy direction/length/overlap: rightward shift (dst > src, overlapping)
  now hops each 77-byte row segment through the scratch line
  (src -> scratch -> dst); both hops are non-overlapping, eliminating the
  smear that forced the full-redraw fallback. Leftward shift and vertical
  copies unchanged (already overlap-safe).
- ready polling/interrupts: vdc_wait bit-7 poll; php/sei held per segment
  (existing rvsd_copy_segment discipline).
- horizontal/vertical bound equivalence: both axes use the same viewport
  bounds; strips now render through the shared row renderer.
- production runtime test: TEST_FILTER='vdc_scroll_delta128' make test128
  (new test_h_scroll_right_fast_path replaces test_left_scroll_falls_back;
  distinct per-cell seeds detect smear), main_loop128, test128-fast.

Changes:

- Leftward horizontal scroll (player moving left) uses the delta path
  instead of a full redraw: ~150 ms -> ~15 ms. The previously dead
  !rvsd_h_scroll_right block was rewired and made overlap-safe.
- The exposed-row strips for vertical scrolls now call rv_render_row
  (extracted from render_viewport's row body; render_viewport loops over
  it) instead of 78 render_single_tile calls: 78 x ~400 cy of register
  programming -> one burst (~3.5K cy), and strip output converges with
  full redraw by construction. rv_cache_player_vx keeps the player
  override correct on strips.
- Copy machinery deduplicated (shared plane addr vars + one plane-copy
  routine; shared exposed-column strip loop) to fit RuntimeLowData:
  c128_ui_scratch_end = $19EE ($12 under FLOOR_ITEM_BASE).
- Verification: build asserts clean; vdc_scroll_delta128 PASS;
  main_loop128 PASS; test128-fast PASS.

Pre-existing infrastructure defect (present at HEAD with and without this
change, A/B verified): make test128 stops early — prompt_irq_guard and
item_overlay_key_guard FAIL, and real_boot_crash_harness fails to
assemble its diag build (StartupOverlay $e000-$f012 exceeds
$e000-$efff; C128ResidentPlay $af00-$d053 exceeds $af00-$cfff; diag
bounds look stale relative to product growth). Reported to maintainer;
not caused by and not blocking this change's contract gates.

### 2026-07-27 — harness defect fixed (all 135 suites green)

Root causes and fixes, per maintainer direction:

1. **Stale guard strings** (prompt_irq_guard, item_overlay_key_guard):
   run_tests128.sh still matched the lowercase
   `#if hal_platform_item_action_key_restores_bank` after 6b9cadb renamed
   it `HAL_PLATFORM_ITEM_ACTION_KEY_RESTORES_BANK`. Guard tokens updated.
2. **Diag variant overflow**: 6b9cadb's `.const`-to-`#define` repair
   activated previously-dead `#if C128_REAL_BOOT_DIAG` instrumentation
   (+102B Play, +46B Startup, +96B Default vs origin/main), pushing the
   diag build past the hard segment bounds. Fixes:
   - Diag variants now exclude wizard mode (`core/wizard.s`,
     `core/ui_wizard.s`; stubs for `cmd_wizard_entry`,
     `wizard_reset_session_state`, `wizard_wall_walk_active`,
     `ui_wizard_display`). The boot/crash scenarios never enter wizard
     commands; frees ~300B in the Play payload.
   - `tramp_player_create`'s `$33` stack-guard begin had no matching
     check; completed the pair (Default) so it brackets the entire
     `jsr player_create` overlay call. The two chargen pairs in
     `core/player_create.s` ($71-$74, around plain jsr's to
     always-resident `player_calc_stats`/`player_calc_hp`) were redundant
     subset coverage and were removed (20B in the STARTUP overlay).
3. **Latent instrumentation bug**: `w_load`'s `$51` guard begin captured
   SP *after* `php; pha` while the `$54` check compared after the final
   `plp` — a guaranteed 2-byte false positive, dormant while the guards
   were dead. Begin moved before the pushes.

Verified: full `make test128` 135/135 PASS.

Known remaining issue (pre-existing, not blocking): the diag variant's
Default segment still exceeds the world-payload boundary (program image
to ~$6576 vs $6000). KickAssembler exits 0 on `.assert` failures, so
this soft violation has been silent since before origin/main; the diag
test passes because the scenario does not touch the overlapped tail.
Fixing it needs ~1.4KB of diag instrumentation moved or the diag variant
slimmed further — a separate follow-up.

### 2026-07-27 — diag-variant boundary overflow fixed; assert failures now loud

Option 1 (fit): the diag variants now build with zero assertion failures.
The diag main image is $1C01-$5F2B (was $657A, bound $6000); the diag
world payload fits below the items payload again. Savings:

- Single shared fail trap replaces the per-stage stub table (~70 stubs)
  and cmp-chain dispatcher (~503B): ~780B. Guards still jump to
  `c128_diag_fail_sym` with the stage id in `c128_stack_guard_stage`;
  the harness now breaks at the single trap address and dumps the
  expected/actual/stage/fail_code/substage bytes for attribution
  (`boot_diag_dump_cmds` takes the stage address).
- Diag variants exclude the sound module (482B) and score file I/O
  (348B): scenarios verify no audio and never reach the death flow.
  Stubs keep SFX constants/call sites and the DeathOverlay
  hiscore_insert references linkable.
- `overlay.s` preload-all lost its end-of-operation validate call
  (per-overlay loads already validate internally; world was 4B over).

Option 2 (loudness): `build_real_boot_diag_assets` and
`build_overlay_transition_diag_assets` now grep the assembly log for
`ERROR IN ASSERTION` and FAIL, so boundary violations in the diag
variants can no longer pass silently (KickAssembler exits 0 on `.assert`
failures). Not applied to the normal product build (Makefile path);
the product build currently reports 0 assert failures.

Verified: `make build` clean; both diag variants assemble with no
assert failures; full `make test128` 135/135 PASS.

### 2026-07-27 — assert-failure check extended to product builds

`tools/kickass_java.sh` wraps every product KickAssembler invocation
(both `JAVA ?=` defaults: `platforms/commodore/Makefile`,
`platforms/apple2/Makefile`, referenced as `../../tools/kickass_java.sh`
— recipes run unquoted under `/bin/sh`, so an absolute path with spaces
breaks). It streams the assembler output and exits nonzero on
`ERROR IN ASSERTION`, closing the same exit-0-on-assert hole in the
normal product build path. Verified: `make build` and `make disk`
clean; a synthetic failing `.assert` makes the wrapper exit 1 while raw
java exits 0. Environment `JAVA=` overrides still bypass the wrapper,
same as before.
