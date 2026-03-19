# Chargen Hang Recovery Plan

## Objective

Resolve the C128 character-creation hang that occurs after gender selection.
Current monitor traces show execution still inside the startup overlay at
`player_create`, specifically in the background generation / word-wrap path,
before any character-summary path is reached.

## Facts Established

- The current hang is **not** in the summary display path.
- Recent summary-related edits changed control flow, but the latest trace at
  `$E58A` is still inside chargen overlay code.
- The current workspace contains experimental changes plus backup files, so we
  need a clean diagnostic baseline before making more behavioral edits.

## Plan

Superseded by the later `$1000` / `JSR $1000` Bank 1 trace.

- [ ] Revert only the experimental summary-path changes in `commodore/common/player_create.s` and `commodore/c128/main.s`.
- [ ] Remove backup artifacts created during the failed experiment review from the working set, or at minimum exclude them from further diagnosis.
- [ ] Rebuild C128 and confirm the baseline hang still reproduces after gender selection.
- [ ] Map the `$E58A` / `$E588` overlay addresses back to the exact labels and loop in `create_gen_background` / `bg_word_wrap`.
- [ ] Add narrow runtime probes around background chart selection, string append, terminator placement, and wrap-loop progress.
- [ ] Verify whether the failure is caused by a missing terminator, bad chart chain, bad break condition, or output pointer overrun.
- [ ] Apply the smallest root-cause fix in the background-generation path.
- [ ] Rebuild and verify normal chargen reaches the summary screen.
- [ ] Re-run any relevant targeted tests and do one manual C128 verification pass.

## Executed Fix Plan

- [x] Confirm `viewport_update` is linked at `$1000` while `bank1.dat` was emitted with an `$E000` PRG header.
- [x] Confirm no runtime Stage 2 loader existed for `bank1.dat`.
- [x] Change `Bank1Data` to emit a `$1000` PRG matching its runtime addresses.
- [x] Add a C128-safe runtime loader for `bank1.dat` using the existing KERNAL wrapper path.
- [x] Load `bank1.dat` during startup before any gameplay path can call `viewport_update`.
- [x] Rebuild, regenerate the D64, and run targeted smokes that exercise chargen through first render.

## Review

- Root cause was not chargen summary code. `viewport_update` and related VDC routines are linked at low RAM `$1000`, but `bank1.dat` was never loaded at runtime and the PRG itself still carried an `$E000` load header.
- First repair attempt loaded `bank1.dat` into Bank 1, which was still wrong because normal runtime executes in `MMU_ALL_RAM` (Bank 0) and calls `$1000` directly.
- Correct fix is to emit `bank1.dat` with a `$1000` header and load it into Bank 0 low RAM during startup before the title menu is shown.
- Validation:
  - `make -B -C commodore/c128 build128` ✅
  - `make -C commodore/c128 disk128` ✅
  - `run_boot_title_newgame_smoke` ✅
  - `run_scripted_summary_to_town_smoke` ✅

## 2026-03-18 follow-up
- New failure: CPU JAM at $1016 after sex selection. Backtrace shows `JSR $1000` from $B2D9, and runtime memory at $1016 contains text (`DIRECTORY...`), not executable code.
- Conclusion: chargen progressed farther; current active bug is Bank 1 low-memory runtime corruption or missing staging/loading for `viewport_update` at $1000.
- Next: trace how `BANK1.DAT` is loaded/relocated into Bank 1 reclaimed low RAM ($1000-$3FFF), then patch the root cause.

## 2026-03-18 follow-up 2
- New trace after the first loader fix still JAMs on `JSR $1000`, now with garbage bytes rather than BASIC text.
- Conclusion: the direct `$1000` call executes in visible Bank 0 runtime context, so loading `bank1.dat` into Bank 1 was insufficient.
- Next: retarget the startup loader to Bank 0 low RAM and re-run targeted smokes.

## 2026-03-18 follow-up 2
- New trace after loader fix: CPU JAM still occurs on `JSR $1000`, now with garbage at `$10DA`/`$1016` instead of BASIC text.
- Key implication: the call executes in currently visible Bank 0 context; loading `bank1.dat` only into Bank 1 does not make `$1000` executable from that path.
- Next: prove intended residency/execution bank for `$1000` code, then retarget the loader or trampoline accordingly.

## 2026-03-18 follow-up 3
- Main blocker fixed: game now reaches town. New bug: character summary screen auto-dismisses without a fresh keypress.
- Hypothesis: the gender-selection key is still considered active when summary dismissal runs, so `input_wait_release` / `input_get_key` sequencing is incomplete on this path.
- Next: trace `create_select_gender`, `tramp_player_create`, and `input_wait_release` / `input_get_key`, then patch the smallest fix and verify with the scripted summary smoke.

## 2026-03-18 final outcome
- Root cause of the two-week blocker was the missing/incorrect low-RAM runtime loader contract for callable `$1000` VDC code, not chargen summary logic.
- Final fix: emit `bank1.dat` with a `$1000` header, load it into Bank 0 low RAM during startup, and harden the summary release path for normal-speed runs.
- Manual validation now reaches town successfully; the summary auto-dismiss symptom was only reproduced during warp-mode testing.

## 2026-03-18 next issue
- New UX bug: secondary/prompt input (look direction, wear selection, shop buy/sell, etc.) is too sensitive and appears to pick up phantom keypresses.
- Goal: fix this in the shared C128 input path rather than sprinkling prompt-specific release gates.
- Plan: inspect prompt callsites plus the CIA edge detector, design the smallest shared fix, then verify with focused smokes/manual guidance.

## 2026-03-18 prompt-input outcome
- Shared fix applied: prompt-style input now uses strict 2-sample stabilization, while primary command entry keeps the fast edge path.
- Manual report: secondary prompts feel better and no obvious phantom key issue remains in the quick pass.
- Verification: `test_input128.s` and `run_scripted_summary_to_town_smoke` passed after the split.

## 2026-03-18 inventory-help issue
- New bug: pressing `?` at secondary item prompts clears to inventory display and then hangs with repeated IRQ/BRK frames.
- Monitor evidence: repeated IRQ into `$E036`, with stack pollution and frames around `$383D` / `$F8EB`.
- Goal: map the active crash addresses to symbols, trace the `?` -> inventory display path, and fix the execution/IRQ boundary rather than adding more prompt-local input workarounds.

## 2026-03-18 inventory-help outcome
- The exact-length copy experiment was a regression. Its tail copy reached `$FF00`, which is the C128 MMU control register, so startup could break before overlays loaded.
- The final root cause was the **source span** for the banked UI payload, not just the exit trampoline: the staged payload bytes extend into `$E000-$EFFF`, so any post-overlay `init_copy_banked` call recopies overlay-clobbered source bytes back into the resident `$F000` banked UI window.
- Final fix:
  - keep the startup `init_copy_banked` copy
  - remove per-entry `init_copy_banked` calls from the C128 UI trampolines
  - restore runtime guards + runtime vectors in `tramp_ui_exit`
  - use `input_wait_release` + `input_get_key_fast` for inventory/equipment dismiss on C128
- Validation:
  - `make -B -C commodore/c128 build128`
  - manual validation: `i`, item-prompt `?`, and help `?` all render content and dismiss correctly

## 2026-03-18 dungeon-descent JAM
- New blocker: descending from town into the first dungeon level triggers a CPU `JAM` at `$D323`.
- Fresh symbol mapping shows the live path is `item_spawn_level -> tramp_roll_ego_type -> roll_ego_type`, with the trampoline at `$307D` calling a callee at `$D310`.
- The built PRG contains valid ego-item code at `$D310`, but runtime execution sees I/O-hole garbage there, so this is an execution-placement bug rather than data corruption.
- Goal: move the ego-item runtime block back into always-executable RAM and add asserts so ego generation can never silently drift above `$D000` again.

## 2026-03-18 dungeon-descent outcome
- Root cause: `ego_items.s` had drifted into the main program at `$D310+`, so `tramp_roll_ego_type` entered the `$D000-$DFFF` I/O hole during dungeon item generation.
- Final fix:
  - move `ego_items.s` into the loaded low-RAM runtime block (`bank1.dat`, runtime `$1000+`)
  - remove the late Default-segment import that allowed ego code to spill into the I/O hole
  - add placement asserts so `roll_ego_type`, `ego_apply_damage`, and `ego_get_ac_bonus` must stay below `FLOOR_ITEM_BASE`
- Validation:
  - `make -B -C commodore/c128 build128`
  - manual validation: town -> first dungeon descent now completes without CPU `JAM`

## 2026-03-18 documentation hardening
- Goal: bake the expensive C128 stability lessons into agent-facing and architecture docs so future work checks the full load/bank/execute/copy contract up front.
- Updated:
  - `AGENTS.md`
  - `GEMINI.md`
  - `commodore/c128/GEMINI.md`
  - `commodore/c128/ARCHITECTURE.md`
  - `commodore/DESIGN.md`
- Key rule now repeated in the docs: for runtime-loaded or banked C128 code, verify linked address, PRG header, load bank, execution bank, and recopy-source safety together.

## 2026-03-18 BUILDPLAN cleanup
- Cleaned the active backlog so `commodore/BUILDPLAN.md` reflects true open work.
- Removed `TST-1` from the open-issues table and recorded it only under resolved work.
- Removed pending `OPT-TEST` from the resolved table and kept it only in the open backlog.

## 2026-03-18 OPT-TEST first slice
- Goal: reduce obvious redundant work in the C128 harness before attempting the larger snapshot/monitor rewrite.
- Implemented in `commodore/c128/run_tests128.sh`:
  - `run_main_assembly_check` now reuses `make build128`
  - unit tests reuse fresh `.prg` / `.vs` artifacts instead of always reassembling
  - `TEST_JOBS` now controls the unit-test worker count
  - repeated address normalization now uses the existing shell helper
- This is an incremental harness optimization, not the full Gate C implementation from `commodore/c128/TEST_OPTIMIZATION_PLAN.md`.

## 2026-03-18 OPT-TEST regression correction
- First OPT-TEST pass broke the real runner even though `bash -n` passed.
- Causes:
  - helper functions were not exported to the `xargs` worker shells
  - `run_symbol_placement_check` still expected the pre-UIB-1 `init_copy_banked` contract
  - the default VICE path in `run_tests128.sh` still pointed at a dead app-bundle path on this machine
- Correction:
  - export `normalize_monitor_addr` and `c128_target_is_stale`
  - update the layout guard to enforce the current `tramp_ui_exit` restore contract and reject stale per-entry `init_copy_banked`
  - prefer `x128` / `/opt/homebrew/bin/x128` before the legacy app path

## 2026-03-18 OPT-TEST variant reuse slice
- Goal: stop rebuilding every smoke/diagnostic asset variant on every `test128` run when the current outputs are already fresh.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add shared freshness helpers for multi-file outputs plus explicit active-variant tracking for the shared `out/main.vs` / overlay scratch space
  - reuse fresh base boot assets only when the active scratch owner is `base`
  - reuse fresh diagnostic/smoke variants only when the active scratch owner matches that variant
  - force base refresh via `make -W main.s -W boot128.s build128 disk128` when returning from a non-base variant, instead of a broad `make -B` that would retrigger the KickAssembler download rule
- Function-level verification:
  - repeated `build_boot_assets` leaves timestamps unchanged
  - repeated `build_real_boot_diag_assets` leaves timestamps unchanged
  - repeated `build_scripted_input_boot_assets` leaves timestamps unchanged
  - switching scripted/diag variants back to `build_boot_assets` refreshes the base outputs and resets the active variant to `base`

## 2026-03-18 OPT-TEST TEST_FILTER slice
- Goal: allow fast targeted harness runs without editing `run_tests128.sh`.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_FILTER` as a regex match over suite names
  - apply it to assembly/layout guards, parallel unit tests, and smoke/diagnostic suites
  - keep default behavior unchanged when `TEST_FILTER` is unset
- Verified from `commodore/c128`:
  - `TEST_FILTER='main128_asm|input128' bash run_tests128.sh` ✅
  - `TEST_FILTER='boot_title_idle_smoke|scripted_summary_to_town_smoke' bash run_tests128.sh` ✅

## 2026-03-18 OPT-TEST path-hardening slice
- Goal: remove the current-working-directory dependency from `commodore/c128/run_tests128.sh`.
- Implemented in `commodore/c128/run_tests128.sh`:
  - detect `REPO_ROOT` via git
  - derive `RUN_TESTS128_DIR` from that root
  - `cd` into `commodore/c128` before any relative-path work
  - root the default `KICKASS` path at the detected repo root
- Verified:
  - `TEST_FILTER='main128_asm|input128' bash commodore/c128/run_tests128.sh` ✅
  - `cd commodore/c128 && TEST_FILTER='main128_asm|input128' bash run_tests128.sh` ✅

## 2026-03-18 OPT-TEST temp-isolation slice
- Goal: remove shared `/tmp/test128_*` state so separate harness runs cannot interfere with each other.
- Implemented in `commodore/c128/run_tests128.sh`:
  - create a per-run temp directory with `mktemp -d`
  - route build logs, monitor command files, monitor logs, unit-test result files, and the KickAssembler symlink through that run-local directory
  - export the temp directory and helper to child worker shells so `xargs` unit tests stay isolated from other harness invocations
- Verified:
  - `TEST_FILTER='main128_asm|input128' bash commodore/c128/run_tests128.sh` ✅
  - `TEST_FILTER='boot_title_idle_smoke|scripted_summary_to_town_smoke' bash commodore/c128/run_tests128.sh` ✅
  - two concurrent `TEST_FILTER='main128_asm|input128'` root-path runs both completed cleanly with no duplicate suite output ✅

## 2026-03-18 OPT-TEST TEST_SKIP slice
- Goal: allow focused exclusion of known-bad or irrelevant suites without editing the harness.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_SKIP` as a regex exclusion over suite names
  - compose skip logic with the existing `TEST_FILTER` matcher
  - print the active skip regex in the harness banner when set
- Verified:
  - `TEST_FILTER='main128_asm|input128|config128' TEST_SKIP='input128' bash commodore/c128/run_tests128.sh` ✅
  - `TEST_FILTER='boot_title_idle_smoke|scripted_summary_to_town_smoke' TEST_SKIP='scripted_summary_to_town_smoke' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_LIST slice
- Goal: inspect the resolved suite set after filter/skip matching without running assembly or VICE.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_LIST=1` list-only mode
  - print selected suite names instead of executing them
  - report a final selected-suite count
- Verified:
  - `TEST_LIST=1 TEST_FILTER='main128_asm|input128|config128' TEST_SKIP='input128' bash commodore/c128/run_tests128.sh` ✅
  - `TEST_LIST=1 TEST_FILTER='boot_title_idle_smoke|scripted_summary_to_town_smoke' TEST_SKIP='scripted_summary_to_town_smoke' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_JOBS auto slice
- Goal: remove the last machine-specific tuning knob for parallel unit-test workers.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_JOBS=auto` worker-count resolution via local CPU count
  - keep `TEST_JOBS=<n>` as an explicit override
  - print the resolved jobs value in the harness banner
  - fall back to the default worker count for invalid explicit values
- Verified:
  - `TEST_JOBS=auto TEST_FILTER='main128_asm|config128|input128' bash commodore/c128/run_tests128.sh` ✅
  - `TEST_JOBS=3 TEST_LIST=1 TEST_FILTER='main128_asm|config128|input128' TEST_SKIP='input128' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_TIMINGS slice
- Goal: surface real per-suite cost before attempting deeper harness architecture changes.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_TIMINGS=1` timing collection mode
  - collect suite timings into the run-local temp directory
  - print a final timing summary sorted by slowest suite first
  - include timing data in unit-test status lines and selected single-suite paths
- Verified:
  - `TEST_TIMINGS=1 TEST_FILTER='main128_asm|config128|input128' bash commodore/c128/run_tests128.sh` ✅
  - `TEST_TIMINGS=1 TEST_FILTER='boot_title_idle_smoke|scripted_summary_to_town_smoke' TEST_SKIP='scripted_summary_to_town_smoke' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_REPEAT slice
- Goal: make focused flake checks possible without wrapping the harness in outer shell loops.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_REPEAT=<n>` iteration control
  - repeat the selected suite set `n` times in one invocation
  - keep `TEST_LIST=1` single-pass and explicitly note that repeat is ignored in list-only mode
- Verified:
  - `TEST_REPEAT=2 TEST_FILTER='main128_asm|config128' bash commodore/c128/run_tests128.sh` ✅
  - `TEST_REPEAT=3 TEST_LIST=1 TEST_FILTER='main128_asm|config128|input128' TEST_SKIP='input128' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_FAIL_FAST slice
- Goal: stop wasting time on later selected suites once the first focused failure is already known.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_FAIL_FAST=1` control
  - stop after the first failing selected suite
  - switch unit tests to serial execution under fail-fast so the harness can stop at the first failing unit
  - print an explicit early-stop summary line
- Verified:
  - `TEST_FAIL_FAST=1 TEST_FILTER='main128_asm|config128' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST Gate C.1 initial connector slice

### Plan
- [x] Extract a reusable Python VICE monitor connector from the old one-off test runner.
- [x] Add a small `commodore/c128/harness128.py` CLI that can spawn `x128`, attach to the monitor socket, and run one test PRG end-to-end from `.vs` symbols.
- [x] Keep `commodore/c128/tests/vice_test_runner.py` working as a compatibility wrapper over the shared connector.
- [x] Prove the live monitor-driven path against `tests/test_minimal128.prg`.
- [x] Record the Gate C.1 slice in the optimization plan.

### Review
- The repo already had a prototype text-monitor socket runner in `commodore/c128/tests/vice_test_runner.py`; Gate C.1 did not need a second implementation.
- The new shared module `commodore/c128/tests/vice_connector.py` now owns:
  - monitor socket connect/retry
  - prompt reads
  - zero-page/MMU/common-RAM test reset
  - PRG load
  - breakpoint management
  - pass/fail/JAM polling
- `commodore/c128/harness128.py` is the first reusable Python entry point for the monitor path. It is intentionally narrow: one test case, one VICE instance, no snapshots yet.
- Important VICE 3.10 detail: the text remote monitor is exposed on `127.0.0.1:6510`; the `6502` socket is the separate binary-monitor endpoint and is not spoken by this slice yet.
- Live proof command:
  - `python3 -u commodore/c128/harness128.py --name minimal128 --prg commodore/c128/tests/test_minimal128.prg --vice /opt/homebrew/bin/x128 --timeout 5 --connect-timeout 12 --verbose`
- Live proof result:
  - `PASS: minimal128`
- Expected next Gate C steps remain unchanged:
  - snapshot boot path
  - persistent VICE workers
  - assembly server
  - actual `run_tests128.sh` integration/replacement

## 2026-03-19 OPT-TEST Gate C.2 initial snapshot slice

### Plan
- [x] Determine the actual VICE 3.10 snapshot save/load contract instead of assuming a command-line flag.
- [x] Add snapshot creation support to `commodore/c128/harness128.py`.
- [x] Add snapshot restore support to `commodore/c128/harness128.py`.
- [x] Prove a test can run from a prepared snapshot without the cold-start reset sequence.
- [x] Record the Gate C.2 slice and the VICE 3.10 contract in the optimization docs.

### Review
- VICE 3.10 monitor-side snapshot commands are `dump` and `undump`.
- The reliable restore path for this harness is **not** `-autostart <snapshot.vsf>`. That path did not behave like an exact state restore for the prepared machine state.
- The harness now supports:
  - `--prepare-snapshot <path>` to create a ready `.vsf`
  - `--snapshot <path>` to restore it via `undump`
  - `--ensure-snapshot` to create it lazily
- Prepared snapshot setup currently writes:
  - `FF00 = $3E`
  - `D506 = $07`
  - `D011 = $00`
- Verified exact restored state through a direct monitor probe after `undump`:
  - `FF00 = $3E`
  - `D506 = $07`
  - `D011` read back as `$80` on VICE 3.10, so MMU/common-RAM are the trusted invariants from this slice
- Live proof commands:
  - `python3 -u commodore/c128/harness128.py --prepare-snapshot commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12 --verbose`
  - `python3 -u commodore/c128/harness128.py --name minimal128 --prg commodore/c128/tests/test_minimal128.prg --snapshot commodore/c128/out/ready.vsf --no-reset-environment --vice /opt/homebrew/bin/x128 --connect-timeout 12 --verbose`
- Live proof result:
  - `PASS: minimal128`

## 2026-03-19 OPT-TEST Gate C.3 investigation

### Plan
- [x] Verify whether the bundled KickAssembler actually exposes server mode.
- [x] Check both runtime behavior and bundled documentation before writing integration code.
- [x] Record the result and stop if the capability is absent.

### Review
- The repo-bundled assembler is `tools/kickass/KickAss.jar` version `5.25`.
- Probes run:
  - `java -jar tools/kickass/KickAss.jar -server`
  - `java -jar tools/kickass/KickAss.jar --server`
- Both were interpreted as missing input files, not as a server mode.
- The bundled manual (`tools/kickass/KickAssembler.pdf`) contains no server-mode documentation.
- `strings`/class inspection of the jar also found no server-related identifiers.
- Conclusion:
  - Gate C.3 cannot be completed against the current bundled KickAssembler.
  - The next real move is either to provide a newer server-capable KickAssembler or to re-scope the optimization plan away from KickAssembler server mode.

## 2026-03-19 OPT-TEST Gate C.4 initial 5-test slice

### Plan
- [x] Choose a small stable first-port set instead of forcing the full suite into the Python harness at once.
- [x] Add a Python batch runner for repeated C128 test execution and timing comparison.
- [x] Prove the selected test subset in both cold and snapshot modes.
- [x] Record the first timing comparison and the excluded tests that did not fit the starter slice.

### Review
- Added `commodore/c128/harness128_batch.py` as the first batch-oriented Python runner over the C.1/C.2 harness pieces.
- Final starter set:
  - `minimal128`
  - `config128`
  - `memory128`
  - `status_coherence128`
  - `vdc_attr128`
- Verified comparison command:
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --tests minimal128,config128,memory128,status_coherence128,vdc_attr128 --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
- Verified result on this machine:
  - cold total: `2.052s`
  - snapshot total: `1.540s`
- Explicitly excluded from the first slice after direct probes:
  - `input128` — timed out at 5s
  - `db128` — timed out at 5s
  - `monster128` — timed out at 5s
- Practical meaning:
  - the Python harness now has a real 5-test C128 subset with measurable snapshot-backed improvement
  - further C.4 work should either raise per-test timeouts selectively or port the next stable tests one by one
  - `KICKASS=/tmp/does-not-exist.jar TEST_FAIL_FAST=1 TEST_FILTER='main128_asm|config128' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-19 OPT-TEST Gate C.4 stable batch expansion plan

### Plan
- [x] Probe the next C128 candidates under the Python snapshot harness instead of assuming they fit the batch path.
- [x] Update `commodore/c128/harness128_batch.py` so its default test set matches the stable passing slice.
- [x] Expand the batch catalog with the next proven snapshot-friendly tests.
- [x] Verify both direct snapshot runs and `--mode compare` on the expanded set.
- [x] Record timings and the pass/fail boundary for the still-excluded tests.

### Review
- Probed the next candidate tests directly through `commodore/c128/harness128.py --snapshot commodore/c128/out/ready.vsf` before widening the batch runner.
- Added the next proven snapshot-friendly tests to `commodore/c128/harness128_batch.py`:
  - `msg_prompt128`
  - `tier128`
  - `dungeon128`
- Updated the batch runner default set to the current stable 8-test slice:
  - `minimal128`
  - `config128`
  - `memory128`
  - `status_coherence128`
  - `vdc_attr128`
  - `msg_prompt128`
  - `tier128`
  - `dungeon128`
- Verified explicit compare run:
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --tests minimal128,config128,memory128,status_coherence128,vdc_attr128,msg_prompt128,tier128,dungeon128 --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
  - cold total: `3.270s`
  - snapshot total: `2.298s`
- Verified default compare run:
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
  - cold total: `3.261s`
  - snapshot total: `2.301s`
- Boundary from direct snapshot probes:
  - passes: `msg_prompt128`, `tier128`, `dungeon128`
  - not in the stable batch set yet: `main_loop128` (stopped without pass/fail), `input128` (timeout after 8.0s), `db128` (timeout after 8.0s), `monster128` (timeout after 8.0s), `soak128` (timeout after 8.0s)

## 2026-03-18 OPT-TEST TEST_SUMMARY slice
- Goal: let automation consume suite outcomes directly without parsing the human console output.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_SUMMARY=json|tsv`
  - add optional `TEST_SUMMARY_FILE=/path`
  - record per-suite results during execution
  - emit machine-readable summary output at end of run
- Verified:
  - `TEST_SUMMARY=json TEST_SUMMARY_FILE=/tmp/test128_summary_check.json TEST_FILTER='main128_asm|config128|input128' TEST_SKIP='input128' bash commodore/c128/run_tests128.sh` ✅
  - `TEST_SUMMARY=tsv TEST_SUMMARY_FILE=/tmp/test128_summary_check.tsv TEST_FILTER='boot_title_idle_smoke|scripted_summary_to_town_smoke' TEST_SKIP='scripted_summary_to_town_smoke' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_PHASE slice
- Goal: make common suite groups selectable without writing ad hoc regexes each time.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_PHASE=` preset groups: `guards`, `units`, `smokes`, `diag`, `perf`
  - allow comma-separated phase combinations
  - compose phase selection with the existing filter/skip/list controls
- Verified:
  - `TEST_PHASE=guards TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_PHASE='units,smokes' TEST_LIST=1 TEST_FILTER='config128|boot_title_idle_smoke|real_boot_crash_harness|input128' TEST_SKIP='input128' bash commodore/c128/run_tests128.sh` ✅
  - `TEST_PHASE=units TEST_FILTER='config128|input128' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_DESCRIBE slice
- Goal: make the `TEST_PHASE` preset layer discoverable without opening `run_tests128.sh`.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_DESCRIBE=1`
  - print all preset definitions by default
  - print only the selected phase definitions when `TEST_PHASE` is also set
  - exit before any test execution
- Verified:
  - `TEST_DESCRIBE=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_DESCRIBE=1 TEST_PHASE='units,diag' bash commodore/c128/run_tests128.sh` ✅
  - `TEST_DESCRIBE=1 TEST_FILTER='config128' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST narrower phase presets slice
- Goal: cut down on repeated custom regexes for the most common smoke-debug loops.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_PHASE=boot`
  - add `TEST_PHASE=town`
  - add `TEST_PHASE=cache`
  - include the new presets in `TEST_DESCRIBE=1` default output
- Verified:
  - `TEST_PHASE=boot TEST_LIST=1 bash commodore/c128/run_tests128.sh`
  - `TEST_PHASE='town,cache' TEST_LIST=1 TEST_FILTER='town_overlay_smoke|cache_survival_smoke|real_boot_crash_harness|overlay_partial_failure_smoke' TEST_SKIP='real_boot_crash_harness' bash commodore/c128/run_tests128.sh`
  - `TEST_PHASE=boot TEST_FILTER='boot_title_idle_smoke|boot_title_newgame_smoke' bash commodore/c128/run_tests128.sh`

## 2026-03-18 OPT-TEST suite-name consistency slice
- Goal: keep selected suite ids, printed console labels, and summary rows aligned.
- Implemented in `commodore/c128/run_tests128.sh`:
  - rename the printed label for `run_boot_title_newgame_smoke` to `boot_title_newgame_smoke`
  - rename the printed label for `run_boot_tier_transition_smoke` to `boot_tier_transition_smoke`
  - rename the printed label for `run_real_input_town_move_diag` to `real_input_town_move_diag`
  - rename the printed label for `run_cache_survival_smoke` to `cache_survival_smoke`
- Verified:
  - `TEST_FILTER='boot_title_newgame_smoke|boot_tier_transition_smoke|real_input_town_move_diag|cache_survival_smoke' TEST_FAIL_FAST=1 bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST summary export metadata slice
- Goal: make machine-readable summaries useful for repeated filtered runs without scraping console state.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add top-level JSON metadata for `phase`, `jobs_requested`, and `jobs_resolved`
  - add per-result `iteration` to JSON exports
  - add `iteration` column to TSV exports
  - thread the current repeat iteration through summary recording
- Verified:
  - `TEST_REPEAT=2 TEST_SUMMARY=json TEST_SUMMARY_FILE=/tmp/test128_summary_meta.json TEST_FILTER='main128_asm|config128' TEST_SKIP='input128' bash commodore/c128/run_tests128.sh` ✅
  - `TEST_REPEAT=2 TEST_SUMMARY=tsv TEST_SUMMARY_FILE=/tmp/test128_summary_meta.tsv TEST_FILTER='boot_title_idle_smoke' bash commodore/c128/run_tests128.sh` ✅
  - `TEST_PHASE=boot TEST_SUMMARY=json TEST_SUMMARY_FILE=/tmp/test128_summary_phase.json TEST_FILTER='boot_title_idle_smoke' TEST_FAIL_FAST=1 bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_RERUN_FROM slice
- Goal: let a previous summary export drive a focused rerun without rewriting filters by hand.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_RERUN_FROM=/path/to/summary.{json,tsv}`
  - load failed suite ids from JSON or TSV summary files
  - deduplicate exact suite names into a rerun selection set
  - compose rerun selection with `TEST_PHASE`, `TEST_FILTER`, and `TEST_SKIP`
  - print rerun source path and selected rerun suite count in the banner
- Verified:
  - `TEST_RERUN_FROM=/tmp/test128_rerun.json TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun.tsv TEST_PHASE=boot TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_exec.json TEST_FAIL_FAST=1 bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_RERUN_LAST slice
- Goal: replay the most recent summary without manually copying its path into `TEST_RERUN_FROM`.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_RERUN_LAST=1`
  - default unspecific summary output to `out/.test128_last_summary.{json,tsv}`
  - record the resolved last-summary path in `out/.test128_last_summary_path`
  - resolve replay source from that marker when `TEST_RERUN_LAST=1`
  - show both `rerun-last: ON` and the resolved `rerun-from:` path in the banner
- Verified:
  - `KICKASS=/tmp/missing.jar TEST_SUMMARY=json TEST_FAIL_FAST=1 TEST_FILTER='main128_asm|config128' bash commodore/c128/run_tests128.sh || true` followed by `TEST_RERUN_LAST=1 TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `KICKASS=/tmp/missing.jar TEST_SUMMARY=json TEST_SUMMARY_FILE=/tmp/test128_last_explicit.json TEST_FAIL_FAST=1 TEST_FILTER='main128_asm|config128' bash commodore/c128/run_tests128.sh || true` followed by `TEST_RERUN_LAST=1 TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_RERUN_STATUS slice
- Goal: let summary replay target more than just failed suites when summaries carry other useful statuses.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_RERUN_STATUS=<regex>` with default `FAIL`
  - apply the status selector to both JSON and TSV replay sources
  - show the active rerun status selector in the banner
  - record `rerun_status` in JSON summary metadata
- Verified:
  - `TEST_RERUN_FROM=/tmp/test128_rerun_status.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_status.tsv TEST_RERUN_STATUS='SKIP' TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_status_exec.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_FAIL_FAST=1 bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_RERUN_ONLY_LATEST slice
- Goal: avoid replaying stale failures from earlier iterations in repeated summary files.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_RERUN_ONLY_LATEST=1`
  - evaluate replay status against only the latest entry per suite
  - use explicit `iteration` when present, else fall back to last occurrence order
  - show `rerun-only-latest: ON` in the banner
  - record `rerun_only_latest` in JSON summary metadata
- Verified:
  - `TEST_RERUN_FROM=/tmp/test128_rerun_latest.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_ONLY_LATEST=1 TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_latest.tsv TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_ONLY_LATEST=1 TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_latest_exec.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_ONLY_LATEST=1 TEST_FAIL_FAST=1 bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_RERUN_INVERT slice
- Goal: run everything except the replay-selected suite set from a summary file.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_RERUN_INVERT=1`
  - invert `TEST_RERUN_FROM` / `TEST_RERUN_LAST` selection after status and latest-only filtering
  - show `rerun-invert: ON` in the banner
  - show `excluded rerun suites` count instead of `rerun suites` in invert mode
  - record `rerun_invert` in JSON summary metadata
- Verified:
  - `TEST_RERUN_FROM=/tmp/test128_rerun_invert.json TEST_RERUN_STATUS='FAIL' TEST_RERUN_INVERT=1 TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_invert.tsv TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_INVERT=1 TEST_PHASE=boot TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_invert_exec.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_INVERT=1 TEST_FAIL_FAST=1 TEST_FILTER='main128_asm|config128|input128' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_RERUN_LIMIT slice
- Goal: cap the replay-selected suite set after replay preprocessing so large summaries can be sampled quickly.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_RERUN_LIMIT=<n>`
  - apply the limit after replay status/latest filtering
  - show `rerun-limit` in the banner
  - record `rerun_limit` in JSON summary metadata
- Verified:
  - `TEST_RERUN_FROM=/tmp/test128_rerun_limit.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_LIMIT=2 TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_limit.tsv TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_LIMIT=1 TEST_PHASE=boot TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_limit_exec.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_LIMIT=2 TEST_FAIL_FAST=1 TEST_FILTER='main128_asm|config128|input128' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_RERUN_ORDER slice
- Goal: choose whether capped replay consumes the start or end of the replay-selected suite set.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_RERUN_ORDER=forward|reverse`
  - apply ordering before `TEST_RERUN_LIMIT` truncation
  - show `rerun-order` in the banner when using non-default `reverse`
  - record `rerun_order` in JSON summary metadata
- Verified:
  - `TEST_RERUN_FROM=/tmp/test128_rerun_order.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_LIMIT=2 TEST_RERUN_ORDER=reverse TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_order.tsv TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_LIMIT=1 TEST_RERUN_ORDER=reverse TEST_PHASE=boot TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_order_exec.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_LIMIT=2 TEST_RERUN_ORDER=reverse TEST_FAIL_FAST=1 TEST_FILTER='main128_asm|config128|input128' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_RERUN_SHUFFLE slice
- Goal: let capped replay take a deterministic sample of a large replay-selected suite set.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_RERUN_SHUFFLE=1`
  - add `TEST_RERUN_SEED=<n>` with default `0`
  - apply seeded shuffle before `TEST_RERUN_LIMIT`
  - show `rerun-shuffle` and `rerun-seed` in the banner
  - record `rerun_shuffle` and `rerun_seed` in JSON summary metadata
- Verified:
  - `TEST_RERUN_FROM=/tmp/test128_rerun_shuffle.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_LIMIT=2 TEST_RERUN_SHUFFLE=1 TEST_RERUN_SEED=17 TEST_LIST=1 bash commodore/c128/run_tests128.sh` twice => identical selection ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_shuffle.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_LIMIT=2 TEST_RERUN_SHUFFLE=1 TEST_RERUN_SEED=23 TEST_LIST=1 bash commodore/c128/run_tests128.sh` => different selection ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_shuffle.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_LIMIT=2 TEST_RERUN_SHUFFLE=1 TEST_RERUN_SEED=17 TEST_FAIL_FAST=1 TEST_FILTER='main128_asm|config128|input128|memory128' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_RERUN_STRIDE slice
- Goal: let replay sampling deterministically take every nth suite from the replay-selected set.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_RERUN_STRIDE=<n>` with default `1`
  - apply stride after replay order/shuffle and before replay limit
  - show `rerun-stride` in the banner
  - record `rerun_stride` in JSON summary metadata
- Verified:
  - `TEST_RERUN_FROM=/tmp/test128_rerun_stride.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_STRIDE=2 TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_stride.tsv TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_STRIDE=2 TEST_PHASE=boot TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_stride.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_STRIDE=2 TEST_FAIL_FAST=1 TEST_FILTER='main128_asm|config128|input128|memory128' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-18 OPT-TEST TEST_RERUN_OFFSET slice
- Goal: let deterministic replay sampling start from an arbitrary index instead of always from the first selected suite.
- Implemented in `commodore/c128/run_tests128.sh`:
  - add `TEST_RERUN_OFFSET=<n>` with default `0`
  - apply offset before replay stride and replay limit
  - show `rerun-offset` in the banner
  - record `rerun_offset` in JSON summary metadata
- Verified:
  - `TEST_RERUN_FROM=/tmp/test128_rerun_offset.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_STRIDE=2 TEST_RERUN_OFFSET=1 TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_offset.tsv TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_STRIDE=2 TEST_RERUN_OFFSET=1 TEST_PHASE=boot TEST_LIST=1 bash commodore/c128/run_tests128.sh` ✅
  - `TEST_RERUN_FROM=/tmp/test128_rerun_offset.json TEST_RERUN_STATUS='FAIL|SKIP' TEST_RERUN_STRIDE=2 TEST_RERUN_OFFSET=1 TEST_FAIL_FAST=1 TEST_FILTER='main128_asm|config128|input128|memory128' bash commodore/c128/run_tests128.sh` ✅

## 2026-03-19 OPT-TEST Gate C.4 main_loop128 investigation

### Plan
- [x] Compare `test_main_loop128` assumptions with the current Python harness launch/reset path.
- [x] Reproduce the `main_loop128` snapshot-harness failure with enough monitor detail to classify it.
- [x] Patch the harness or test contract at the root cause instead of widening timeouts blindly.
- [x] Verify `main_loop128` directly through `harness128.py`.
- [x] Verify `main_loop128` through the shell harness after repairing the unit-test worker path.
- [x] Verify `main_loop128` in isolated Gate C.4 compare mode.
- [x] Keep it out of the default stable batch set until the unrelated compare regressions are resolved.

### Review
- Root cause in `test_main_loop128.s`: the reduced local hook stubs were one-byte `rts` bodies, but `install_jump_patch` writes three-byte `jmp` patches. That corrupted adjacent local stubs and produced false hangs.
- Root cause in `run_tests128.sh`: the shell unit-test worker path was too fragile. Replacing the exported-function worker call with `commodore/c128/run_test_internal_worker.sh` made the shell path deterministic again.
- `test_main_loop128.s` now assembles as a focused non-wrapping unit test:
  - `.test_start=$0300`
  - `.test_fail=$0303`
  - `.test_pass=$0306`
  - payload end `$4779`
- `main_loop128` now passes in:
  - `python3 -u commodore/c128/harness128.py ... --snapshot ...`
  - `python3 -u commodore/c128/harness128.py ...` (cold/reset)
  - `TEST_FILTER='main_loop128' bash commodore/c128/run_tests128.sh`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --tests main_loop128 ...`
- The broader default batch set remains unchanged for now because a separate compare run exposed unrelated failures in `memory128`, `msg_prompt128`, and `tier128`.

## 2026-03-19 OPT-TEST Gate C.4 stable compare-set correction

### Plan
- [x] Reproduce the remaining Python batch failures in `memory128`, `msg_prompt128`, and `tier128`.
- [x] Compare the Python harness behavior against the shell-harness moncommands path.
- [x] Correct the default Gate C.4 batch set to only include tests proven under both cold and snapshot modes.
- [x] Make unsupported Python batch selections fail immediately with explicit reasons.

### Review
- Root cause: shell-harness success did not imply Python batch readiness. `memory128`, `msg_prompt128`, and `tier128` still depend on execution conditions that the current Python cold/snapshot paths do not reproduce faithfully.
- The default Gate C.4 compare batch is now the verified six-test set:
  - `minimal128`
  - `config128`
  - `status_coherence128`
  - `vdc_attr128`
  - `dungeon128`
  - `main_loop128`
- Verified with:
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
  - cold: `2.761s`
  - snapshot: `2.416s`
- Explicit Python batch selection of the unsupported tests now stops immediately with honest status instead of long timeouts:
  - `not cold-batch-ready`
  - `not snapshot-ready`

## 2026-03-19 OPT-TEST Gate C.4 moncommands contract alignment

### Plan
- [x] Compare the Python moncommands runner against the shell harness invocation directly.
- [x] Restore the missing VICE execution contract in the Python moncommands path.
- [x] Carry shell-equivalent `-limitcycles` budgets for moncommands-driven batch tests.
- [x] Re-qualify `memory128`, `msg_prompt128`, and `tier128` under cold and snapshot compare mode.
- [x] Restore the proven tests to the default stable Gate C.4 compare set.

### Review
- Root cause: the Python moncommands path was not actually equivalent to the shell harness. It was missing:
  - `+remotemonitor +binarymonitor`
  - the per-test `-limitcycles` budget
- Without that contract, VICE remained alive at the monitor prompt and the Python batch harness reported false timeouts.
- After aligning the contract, the previously excluded tests now pass in both cold and snapshot compare mode:
  - `memory128`
  - `msg_prompt128`
  - `tier128`
- Verified with:
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --tests memory128,msg_prompt128,tier128 --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
- The stable default Gate C.4 compare batch is now:
  - `minimal128`
  - `config128`
  - `memory128`
  - `status_coherence128`
  - `vdc_attr128`
  - `msg_prompt128`
  - `tier128`
  - `dungeon128`
  - `main_loop128`

## 2026-03-19 OPT-TEST Gate C.4 input128 requalification

### Plan
- [x] Reproduce `input128` under the shell harness and Python batch harness.
- [x] Verify whether `input128` is a timeout problem or another moncommands-selection problem.
- [x] Route `input128` through the shell-equivalent moncommands contract in the Python batch harness.
- [x] Re-verify `input128` alone and in the default Gate C.4 compare set.

### Review
- Root cause: `input128` has normal 16-bit symbols, so `symbols_need_moncommands()` did not flag it, but it still behaves correctly only under the moncommands-driven execution path.
- Fix:
  - `input128` now carries explicit moncommands metadata in `harness128_batch.py`
  - cycle budget: `20,000,000`
- Verified with:
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --tests input128 --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
- The stable default Gate C.4 compare batch now includes:
  - `minimal128`
  - `config128`
  - `memory128`
  - `input128`
  - `status_coherence128`
  - `vdc_attr128`
  - `msg_prompt128`
  - `tier128`
  - `dungeon128`
  - `main_loop128`

## 2026-03-19 OPT-TEST Gate C.4 full unit-batch requalification

### Plan
- [x] Reproduce the remaining excluded unit tests under shell and Python paths.
- [x] Verify whether `db128`, `monster128`, and `soak128` are moncommands-driven like the other recent failures.
- [x] Add explicit moncommands metadata and shell-equivalent cycle budgets where required.
- [x] Re-verify each test in cold and snapshot compare mode.
- [x] Re-verify the full default Gate C.4 compare batch.

### Review
- Root cause: the last excluded unit tests were not special snapshot blockers. They were ordinary 16-bit-symbol tests that still require the shell-style moncommands contract:
  - `db128`
  - `monster128`
  - `soak128`
- Added explicit batch metadata:
  - `db128` → `20,000,000` cycles
  - `monster128` → `20,000,000` cycles
  - `soak128` → `300,000,000` cycles
- Verified with:
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --tests db128 --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --tests monster128 --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --tests soak128 --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
- The stable default Gate C.4 compare batch now contains all current unit tests:
  - `minimal128`
  - `config128`
  - `memory128`
  - `input128`
  - `db128`
  - `status_coherence128`
  - `vdc_attr128`
  - `msg_prompt128`
  - `tier128`
  - `dungeon128`
  - `main_loop128`
  - `monster128`
  - `soak128`

## 2026-03-19 OPT-TEST fast smoke target integration

### Plan
- [x] Identify a minimal high-value smoke subset worth exposing as a standard fast target.
- [x] Add Makefile targets for the smoke subset at both the C128 and repo root levels.
- [x] Verify both new make entry points.

### Review
- Added `test128-fast-smoke` with this subset:
  - `boot_title_idle_smoke`
  - `scripted_summary_to_town_smoke`
  - `town_overlay_smoke`
- New entry points:
  - `make -C commodore/c128 test128-fast-smoke`
  - `make test128-fast-smoke`
- Verified:
  - `make -C commodore/c128 test128-fast-smoke`
  - `make test128-fast-smoke`
- This keeps `test128-fast` focused on the Python unit compare path while giving agents and humans a separate fast smoke pass for the most failure-prone runtime flows.

## 2026-03-19 OPT-1 command dispatch jump table

### Plan
- [x] Map the current `main_loop` command dispatch hot path and identify the commands that still need bespoke range handling.
- [x] Replace the discrete `cmp`/branch chain with a bounded jump table while keeping movement and running as explicit fast paths.
- [x] Extend the focused C128 `main_loop128` test so the new table is exercised on a turn-consuming command.
- [x] Verify shared-path correctness on C64 and C128 builds/tests.

### Review
- Replaced the discrete `CMD_STAIRS_DN..CMD_TUNNEL` equality chain in `commodore/common/game_loop.s` with a bounded indirect jump table backed by `command_dispatch_lo/hi`.
- Kept movement and running as explicit fast paths outside the table, preserving the existing range-based behavior and avoiding extra per-step table work on the hot movement path.
- Added a `CMD_REST` case to the focused C128 `main_loop128` harness so the table is exercised on a turn-consuming command, instead of only display/no-turn handlers.
- Verified with:
  - `make -C commodore/c64 build`
  - `cd commodore/c64 && ./run_tests.sh`
  - `make -B -C commodore/c128 build128`
  - `make -C commodore/c128 test128-fast`
  - `make -C commodore/c128 test128-fast-smoke`
- Manual in-game check confirmed normal command behavior after the dispatch change.

## 2026-03-19 OPT-3 visibility room-cache optimization

### Plan
- [x] Inspect the current `update_visibility` room-reveal path and identify where the per-turn room scan still happens.
- [x] Design a transient room-cache approach that avoids save-format churn and preserves corridor / lit-room behavior.
- [x] Patch `dungeon_los.s` and add a direct regression covering room-cache set/clear behavior.
- [x] Verify shared-path correctness on C64 and C128 builds/tests.

### Review
- Added `vis_cached_room_idx` in `commodore/common/dungeon_los.s` and changed `update_visibility` to:
  - clear the cache on blind/town/unlit-tile paths
  - skip the room scan entirely when the current tile is not lit
  - reuse the cached room bounds when the player stays inside the same lit room
  - rescan lit rooms only when the cache is invalid or the player has left the cached room
- Kept the cache transient only; no save-format or level-transition serialization changes were required.
- Added a direct C64 regression in `commodore/c64/tests/test_effects.s` covering cache set-in-room and clear-in-corridor behavior.
- Updated the C64 effects runner expectation in `commodore/c64/run_tests.sh`.
- Verified with:
  - `make -C commodore/c64 build`
  - `cd commodore/c64 && ./run_tests.sh`
  - `make -B -C commodore/c128 build128`
  - `make -C commodore/c128 test128-fast`
  - `make -C commodore/c128 test128-fast-smoke`

## 2026-03-19 TST-3 UI view isolation tests

### Plan
- [x] Audit the shared UI render entry points and choose the smallest direct-draw coverage that matches the `TST-3` backlog scope.
- [x] Add a focused C64 runtime suite covering character, help, inventory, equipment, recall, store, and home layouts.
- [x] Wire the suite into the standard C64 runner and verify the updated C64/C128 test paths.
- [x] Update the backlog/history docs to close `TST-3`.

### Review
- Added `commodore/c64/tests/test_ui_views.s`, a focused runtime suite that directly exercises the shared view renderers for:
  - character sheet
  - help
  - inventory
  - equipment
  - recall
  - store
  - home
- Kept the coverage isolated to direct draw/layout paths where possible:
  - `ui_char_display`
  - `ui_help_display`
  - `ui_inv_display`
  - `ui_equip_display`
  - `ui_recall_display`
  - `store_draw_screen`
  - `home_enter` with patched input and exit-clear suppression so the rendered screen remains inspectable
- Fixed the test expectations to match real screen-code rendering:
  - slot letters are written as screen codes (`$01` for `A`) rather than textual `A`
  - recall stat assertions now follow the stable rendered row instead of assuming ad hoc test data
- Wired the suite into `commodore/c64/run_tests.sh` as `ui_views`.
- Verified with:
  - focused headless `ui_views` run → `7/7`
  - `cd commodore/c64 && ./run_tests.sh` → `29 passed, 0 failed`
  - `make -B -C commodore/c128 build128`
  - `make -C commodore/c128 test128-fast`
  - `make -C commodore/c128 test128-fast-smoke`

## 2026-03-19 TST-4 subsystem test expansion

### Plan
- [x] Audit the four open subsystem gaps (`huffman.s`, `string_bank.s`, overlay execution, `sound.s`) and order them by implementation risk.
- [x] Define a staged closure plan instead of trying to land all four subsystem families in one patch.
- [x] Implement the first focused slice: direct C64 runtime coverage for Huffman decode correctness.
- [x] Verify the updated C64 runner and shared C128 fast paths.
- [ ] Follow with separate slices for string-bank decode/load behavior and narrow overlay execution contracts.

### Notes
- The practical order is:
  1. `huffman.s` decode/data integrity
  2. `sound.s` via a specialized harness that does not rely on CPU readback from write-only SID voice registers
  3. `string_bank.s` / `string_bank_banked.s` (requires loader/banked decode harness)
  4. overlay execution contracts (likely C64 + C128 focused harnesses around invalidate/load/return behavior)
- `TST-4` should be closed only after those later sound/string-bank/overlay slices land; the first patch is intentionally a partial closure step, not the full item.

### Review
- Added `commodore/c64/tests/test_subsystems.s` and wired it into `commodore/c64/run_tests.sh` as `subsystems`.
- The first slice is intentionally Huffman-only:
  - index/data integrity for representative entries
  - direct decode of `Direction?`
  - direct decode of `Take off which item (a-h)?`
  - `huff_decode_to_ptr2`
  - `huff_append_combat`
- Fixed the helper bug uncovered during bring-up: the expected-string compare path was using an indirect pointer in normal RAM instead of zero page, so valid literals failed at runtime. The helper now uses `zp_ptr1`.
- `sound.s` stays deferred. SID voice-register CPU readback is not a valid runtime assertion mechanism because those registers are write-only; that subsystem needs a specialized harness.
- Verified with:
  - `cd commodore/c64 && ./run_tests.sh`
  - `make test128-fast`
  - `make test128-fast-smoke`
