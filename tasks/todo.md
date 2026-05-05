# Active Task Scratchpad

Active-only backlog. Completed task scratchpad material through 2026-04-29 is
archived in `commodore/BUILDPLAN_HISTORY.md`.

## Reported Failure Gate

No active reported failure gate.

Last closed exact reported command:

```sh
make disk128
```

2026-05-04 closure: restored the missing tracked source file, moved trap-death
cause rendering out of the death overlay, aligned rockfall trap death text with
VMS `take_hit(..., 'falling rock.')`, and verified the exact `make disk128`
gate passes.

Previous C128 product boot failure, now closed: product boot hung while loading
`monster.db.1` from the shipping disk. Live monitor dump stopped inside
`mmu_common_irq` at `$0C27`, with repeated `IRQ -> $0C06` frames and stack
corruption.

2026-05-04 diagnostic/fix status: actual root was the C128 common MMU helper
blob growing past 256 bytes while `init_common_mmu_helpers` still used an
8-bit copy-length loop. The symbol `mmu_common_db_write_ptr1` resolved to
`$0CE4`, but `$0CE4` in common RAM still contained `BRK`, so the first preload
cache write could jump into uncopied helper space. The copy loop now copies the
first full page plus the tail and asserts the supported helper-blob bounds.
Preload IRQ ownership was also tightened: runtime IRQ vectors are installed
only after tier/overlay preload completes, and preload transactions keep
interrupts masked for the whole KERNAL LOAD/CLOSE/CLRCHN/SETBNK transaction.
Verified native product-disk monitor progression reached first tier load,
tier cache stage, tier cache verify, overlay preload, runtime vector restore,
and title entry. Also verified with `make build128`, `make disk128`,
`boot_title_idle_smoke`, `boot_d64_smoke`, `cache_survival_smoke`,
`make test128-fast-smoke` (8/8), and `make test128-fast` cold/snapshot
compare batches. User live-smoked the product paths afterward and confirmed
both C128 and C64 boot/gameplay reached stable operation.

## Active Backlog

- [x] `BUG-C128-WIZARD-CONFIRM-CLEAR`: first-time C128 wizard-mode entry
      should print the `WIZARD? (Y/N)` confirmation as an ordinary gameplay
      message, without clearing/redrawing the gameplay screen before the
      prompt.
  - [x] Remove the C128 UI-overlay restore call from the not-yet-wizard
        confirmation path.
  - [x] Align rendered wizard cancel strings to explicit wording: C128
        `ui_wizard.s` footer uses `Q to cancel`; C64 `wizard.s` menu row and
        footer both use `Q to cancel`.
  - [x] Remove stale `Press any key` wizard-footer copy from the unused
        `ui_wizard.s` C64 branch too, so wizard UI sources consistently use
        `Q to cancel`.
  - [x] Add a focused C128 static contract for prompt ordering.
  - [x] Verify C128 build/tests after the UI-overlay change.
- [x] `BUG-C64-DISK-IO-MODAL-CLEAR`: C64 disk I/O save/load swap prompts
      must clear the whole modal screen immediately after the user dismisses
      `Press any key`, so stale `Loading game...`, save/load prompts, or
      insert-disk copy cannot remain visible during the following disk work.
  - [x] Patch the shared C64 disk prompt owner, not individual save/load
        callsites.
  - [x] Patch Disk Setup insert/confirm/error modal exits too; those can run
        immediately before save/load work and are separate from `disk_prompt`.
  - [x] Suppress the internal monster-tier `Loading...` fallback during
        load-resume; the save-file load already owns the visible loading UI,
        and normal gameplay hides tier loads behind generation/transition UI.
  - [x] Add focused C64 unit/static coverage that dismissal does a full clear.
  - [x] Verify `make disk64`.
  - [x] Verify `make disk128` stays green.
- [x] `REFACTOR-C64-DISK-IO-CLEAR-OWNERSHIP`: remove the C64 main-image
      growth caused by treating `save.s` as the generic full-screen transition
      owner. Consultant consensus: disk/modal producers should clear their own
      residue; save/load should own file I/O and status text only.
  - [x] Remove the new generic `save_prepare_io_screen` clear path from
        `save.s`.
  - [x] Keep `disk_swap.s` clearing immediately after a C64 disk-swap prompt is
        dismissed, before drive re-init.
  - [x] Keep `ui_disk_setup.s` clearing after Disk Setup full-screen modal
        exits; this code lives in overlay ownership rather than C64 main.
  - [x] Move any remaining C64 save/load transition clearing to the caller that
        enters the full-screen save/load flow, not the save-file subsystem.
  - [x] Preserve C128 modal-wrapper transition behavior.
  - [x] Verify C64 main ends below `$C000` with `make disk64`, then verify
        `make disk128` remains green.
- [ ] `BUILD-MAKEFILE-KICKASS-CLEANUP`: clean up Makefile target behavior so
      normal builds, forced rebuilds, and platform-directory invocations handle
      KickAssembler bootstrap consistently and do not send agents down the
      wrong diagnostic path.
- [ ] `FEAT-VMS-LOOK-SEMANTICS`: decide whether to keep the compact VMS-style
      baseline or fund a larger parity push later.
  - [ ] Add C128 unit/smoke coverage for shared `look` changes.
  - [ ] Run full regression gates before human playtesting.
- [ ] `BUG-LONG-MESSAGE-TRUNCATION-POLISH`: wrap long combat/status messages
      cleanly across message rows 0-1, preserve sensible `-more-` behavior,
      and decide whether history stores wrapped/continued lines or wider
      entries.
- [x] `PERF-C128-VISIBILITY-MMU`: audit and optimize the per-turn C128
      `update_visibility` path, which currently does per-tile Bank 1
      `MapRead`/`MapWrite` work for torch-radius visibility.
  - [x] Current finding: `update_visibility` marks every tile in the torch
        radius as visited every turn. On C128 each `MapRead_ptr0_y` and
        `MapWrite_ptr0_y` enters common-RAM MMU helper code, switches to Bank
        1 for one byte, then switches back to Bank 0.
  - [x] Low-risk option: skip `MapWrite` when `FLAG_VISITED` is already set.
        This preserves behavior and reduces write-side bank transitions after
        the first pass over a tile; superseded by the row-helper option.
  - [x] Larger C128-specific option: add a common-RAM row helper that ORs
        `FLAG_VISITED` across `vis_min_x..vis_max_x` while Bank 1 is selected,
        switching once per row. Do not use `map_bulk_enter` around ordinary
        code; only code executing from common RAM can safely run while Bank 1
        is visible.
  - [x] Before choosing the row-helper option, verify common-RAM helper size,
        symbol/load/copy placement, and boundary asserts.
- [x] `PERF-C128-ROOM-REVEAL-MMU`: audit room light/reveal loops for avoidable
      per-tile Bank 1 switching during room reveal and permanent light updates.
  - [x] C128 `light_room_x` and `reveal_room` now share the common-RAM row
        helper used by torch visibility. The helper accepts a row-end column,
        OR mask, and optional newly-visited detection flag, so room reveal still
        sets `vis_room_revealed` only when a tile was newly seen.
  - [x] `128.fdisk` runtime-common ownership moved to `$0D60-$0FFF` to keep
        the MMU helper blob and runtime-common payload non-overlapping.
- [x] `PERF-C128-FULL-REDRAW-CAUSES`: identify gameplay paths that force full
      C128 viewport redraws instead of `render_local_area`, and prove the
      deterministic product-path causes the current trace harness can support.
  - [x] Add C128 `PERF_P1` reason counters for full-redraw causes without
        changing normal rendering behavior. Reason IDs are:
        `0=scroll fallback`, `1=room reveal`, `2=scene dirty`,
        `3=command forced`, `4=update-visibility tail`, `5=modal restore`,
        `6=transition`, `7=direct effect`.
  - [x] Keep PERF helper code in `RuntimeCommonData`, keep PERF counter storage
        in the resident gameplay payload that updates it, and guard C128
        resident play with a `$CF00` floor-item boundary assert so PERF
        callsites cannot grow into floor-item storage.
  - [x] Remove the standalone `perf_p1_measure.py` path from the trusted
        workflow after consultant review. It was creating a second C128 launch
        contract instead of observing the product/test path.
  - [x] Add C128 trace validation that proves the resident-play export code
        reads the intended PERF symbols. `perf_p1_trace_smoke` now assembles
        grouped `C128_TEST_PERF_P1_TRACE` variants and validates the emitted
        `128.play` bytes against `out/main.vs`; it no longer drives the full
        title/new-character path through monitor breakpoints.
        2026-05-03 correction: the earlier live monitor ranking was invalid.
        C128 resident-play addresses collided with earlier boot/main execution,
        and data watchpoints also fired during loader/bulk-clear writes. Those
        monitor setup/initialization stops could look like valid trace hits.
        The trusted gate is now split: `perf_p1` proves direct decision
        semantics, while `perf_p1_trace_smoke` proves resident export ownership
        and one scripted product-path first-move sample.
  - [x] Add a new focused product-path measurement fixture before ranking full
        redraw causes. It must have a unique post-render synchronization point
        that cannot fire during boot, runtime loads, bulk clears, or unrelated
        resident-address execution. Do not report counter rankings from monitor
        setup echoes or loader memory writes.
        2026-04-30 update: base C128 test builds now force rebuild and pass
        `PERF_P1=1` through to `commodore/Makefile`; previously the symbol
        file could be from a PERF build while `moria128.d71` was still a
        non-PERF image. The sampler now rejects impossible `$FF` counter
        blocks instead of producing a false ranking. 2026-05-03 consultant
        reset: the standalone sampler is not a trusted carrier unless it uses
        the same product artifact and launch contract; measurement must ride on
        `run_tests128.sh` and report `INVALID` rather than turning into a
        second C128 harness. 2026-05-03 consultant follow-up: do not add
        verifier/assert code to `C128ResidentPlay`; a 36-byte trace-build
        overflow proved that is the wrong ownership boundary. Resident PLAY
        should only produce existing PERF facts. The live proof must be
        harness-owned through monitor reads of existing counters, or use a
        test-owned trace/export buffer outside resident gameplay if monitor
        bank reads cannot be made trustworthy.
        Implemented as a split trace: resident PLAY jumps to a test-owned
        `Default` capture routine, while resident PLAY keeps only tiny unique
        pass/fail loops for synchronization. The live trace now proves the
        scripted product first movement records `local=1` and `full=0`; grouped
        static variants still validate the exported counter/reason symbols.
  - [x] Add first deterministic full-redraw cause sample to the trusted trace:
        inventory modal open/dismiss now proves `modal restore` records
        `full=1` and `reason[modal_restore]=1` through the product path.
  - [x] Add command-forced full-redraw sample to the trusted trace:
        scripted search now proves `command forced` records `full=1` and
        `reason[command_forced]=1` through the product path.
  - [x] Add transition full-redraw sample to the trusted trace:
        level-generation render tail now proves `transition` records
        `full=1` and `reason[transition]=1` through the product path.
  - [x] Defer broader ranking and the direct-effect product-path sample. A
        trace-only Fire Ball path would require pulling scripted spell setup
        into resident PLAY and pushed `RuntimeCommonData` and
        `C128ResidentPlay` over their C128 segment ceilings. Do not revive that
        approach without a separate ownership redesign.
- [ ] `PERF-C128-SECRET-SCAN`: measure generation-time full-map scans such as
      secret-door placement; keep lower priority unless dungeon generation
      becomes visibly slow.

## Build Plan Cross-References

- [ ] `UI-80`: refine the C128 80-column layout to a true Umoria-style left
      status panel.
- [ ] `OPT-STATUS-ROW23`: split bottom status row redraws into field-level
      helpers; row 23 currently clears/redraws HP, MP, AC, AU, hunger, and
      search state as one coarse dirty unit.
- [ ] `OPT-OVERLAY-PRESSURE-RESERVE`: consider further magic/spell/UI overlays
      only if main-segment pressure returns.

## Review Notes
- 2026-05-04: `BUG-C128-WIZARD-CONFIRM-CLEAR` completed. Root cause: the C128
  first-time wizard confirmation path called `ui_wizard_restore_gameplay_view`
  before printing `WIZARD? (Y/N)`, forcing a full gameplay clear/redraw before
  an ordinary message prompt. The confirm path now prints directly, and
  C128 `ui_wizard.s` and the actual rendered C64 `wizard.s` menu row/footer
  now use explicit wording, `Q to cancel`. `run_tests128.sh` guards the C128
  overlay text and the remaining shared wizard strings, and `run_tests.sh`
  guards both actual C64 wizard strings, so the obsolete `Q cancel`,
  `Q cancels`, and wizard-footer `Press any key` wording cannot come back
  through either path.
  Verified with `make disk128`, `make test128-fast-smoke`, and `make disk64`.
- 2026-05-04: `BUG-C64-DISK-IO-MODAL-CLEAR` completed. C64 one-drive
  save/load/game-disk prompts and Disk Setup insert/confirm/error modals now
  clear the full modal screen immediately after the user dismisses
  `Press any key` or answers the prompt, before drive init and subsequent disk
  work. Verification: `make disk64` passed, `make disk128` passed, focused
  `test_disk_swap` monitor run returned 14/14 pass bytes, and the Disk Setup
  insert-dismiss static contract passed. Follow-up: load-resume now suppresses
  the internal monster-tier `Loading...` message so restored games match the
  regular gameplay transition behavior. Verified `make disk64`, `make
  disk128`, the load-resume static contract, and C64/C128 main-loop test
  assembly. The initial broad C64 rerun exposed current-work regressions in
  several C64 test fixtures/contracts; those were corrected and the full
  `bash commodore/c64/run_tests.sh` gate now passes, 134/134 suites.
- 2026-05-04: Consultant-backed ownership refactor completed after the first
  save/load clear attempt pushed C64 main past `MAP_BASE`. `save.s` no longer
  owns generic full-screen transition cleanup; C64 title/gameplay callers own
  the save/load entry transition, Disk Setup owns its modal exits, and C128
  modal wrappers preserve the existing fullscreen prep. `make disk64` now
  reports `Program fits below MAP_BASE=true` with 0 failed asserts, and
  `make disk128` reports 0 failed asserts.
- 2026-04-29: C128 save/load transport optimization completed and archived in
  `commodore/BUILDPLAN_HISTORY.md`.
- 2026-04-29: `PERF-C128-VISIBILITY-MMU` completed. C128 torch-radius
  visibility now marks each row through a common-RAM Bank 1 helper instead of
  doing per-tile read/write helper calls; `128.fdisk` moved to `$0D60` to keep
  runtime-common ownership explicit.
- 2026-04-29: `PERF-C128-ROOM-REVEAL-MMU` completed. C128 room light/reveal
  uses the same shared common-RAM row helper and preserves first-time room
  reveal detection.
- 2026-04-30: `PERF-C128-FULL-REDRAW-CAUSES` instrumentation pass added.
  `PERF_P1=1` builds now expose full-redraw reason counters in
  `perf_p1_reason_lo[]`, while normal non-PERF C64/C128 builds remain
  behavior-equivalent. First measurement attempts showed pass/fail smokes are
  unsuitable as counter sources unless a dedicated measurement smoke produces a
  validated post-movement dump.
- 2026-04-30 verification: normal `make -C commodore build128` and
  `make -C commodore build64` passed all assembler assertions; `make
  test128-fast` passed cold and snapshot batches; `PERF_P1=1
  TEST_FILTER='perf_p1' bash commodore/c128/run_tests128.sh` passed; and
  `PERF_P1=1 TEST_FILTER='scripted_summary_to_town_smoke' bash
  commodore/c128/run_tests128.sh` passed. The remaining open item is an
  instrumented gameplay sample that reaches movement and ranks the counters.
- 2026-04-30 PERF gameplay sampling found and fixed a memory-layout blocker:
  PERF-only resident-play growth had crossed the floor-item table start at
  `$cf00`. `C128ResidentPlay` now has a hard `$ceff` segment ceiling and an
  explicit `c128_resident_play_end <= $CF00` assert; the PERF reason helpers
  live in `RuntimeCommonData` to keep resident play below the floor-item page.
- 2026-05-03 PERF measurement scope reset after consultant review: the
  standalone sampler path was removed from the trusted workflow because it
  created a parallel C128 launch contract. The next accepted measurement must
  come from a dedicated `run_tests128.sh` product-path smoke and must report no
  ranking unless the post-movement counter block validates.
- 2026-05-03 PERF trace smoke added: `perf_p1_trace_smoke` now reaches a
  product-path post-movement proof through the scripted C128 disk path. The
  resident PLAY hook only jumps to a test-owned `Default` capture routine; the
  live assert proves the deterministic first movement records `local=1` and
  `full=0`. The modal variant opens/dismisses inventory and proves modal
  restore records `full=1` and `reason[modal_restore]=1`. The command variant
  drives scripted search through the real command redraw tail and proves
  command-forced redraw records `full=1` and `reason[command_forced]=1`.
  The transition variant captures the level-generation render tail and proves
  transition records `full=1` and `reason[transition]=1`. Verification:
  `PERF_P1=1 TEST_FILTER='perf_p1' bash commodore/c128/run_tests128.sh`
  passed with both `perf_p1` and `perf_p1_trace_smoke`.
- 2026-05-03 PERF trace ownership tightened after consultant review: grouped
  `perf_p1_trace_smoke` variants validate the resident export jump and the
  test-owned capture routine's assembled counter/reason loads against
  `out/main.vs`. The gate no longer reports sorted rankings from raw monitor
  memory reads; the completed trusted scope is deterministic product-path
  proof for first move, modal restore, command-forced redraw, and transition.
  Direct-effect product tracing was deferred because the trace-only Fire Ball
  setup exceeded the C128 runtime-common and resident-play segment ceilings.
- 2026-05-03 PERF semantics audit follow-up: `perf_p1_reset` was compacted to
  clear the contiguous PERF data block with one indexed loop, preserving the
  C128 runtime-common boundary. Storage remains at the beginning of
  `C128ResidentPlay`; runtime-common and main-image storage placements were
  rejected after monitor/runtime bank views showed unstable bytes.
