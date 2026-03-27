# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Task
- [x] Implement `BUG-HAGGLE-UI` Phase A in `commodore/common/ui_store.s` using one-visit VMS-style haggle flow with integer counter math.
- [x] Keep Phase A inside the current thin store data model; do not add persistent bargaining-memory or owner-schema work.
- [x] Add focused runtime coverage in `commodore/c64/tests/test_store.s` for parser behavior, buy/sell haggle flow, insult handling, and no-haggle bypasses.
- [x] Run the relevant C64 store/runtime tests and broader C64/C128 regression coverage.
- [x] Record the implementation review outcome here after verification.

- [x] Analyze the live `BUG-HAGGLE-UI` implementation in `commodore/common/ui_store.s` and identify the current buy/sell haggle contract.
- [x] Compare the port's haggle flow against local upstream references in `~/Projects/thirdparty/vms-moria` and `~/Projects/thirdparty/umoria`.
- [x] Draft a bounded design plan that restores one-visit haggle correctness before any larger store-system upgrades.
- [x] Get consultant review on the draft plan and fold that feedback into the final phase split and verification list.
- [x] Record the final planning scope here before presenting it to the user.

### `BUG-HAGGLE-UI` Design

#### Goal
- Restore store haggling to correct one-visit behavior for the current Commodore data model.
- Use VMS-Moria as the semantic baseline for user-visible haggle flow.
- Use Umoria as the implementation reference for integer bargain progression where the original VMS code relies on real-valued ratios.

#### Findings
- The current port uses a simplified fixed-step haggle loop in `commodore/common/ui_store.s`:
  - buy haggling always marches toward the floor by `gap / 4`
  - sell haggling always marches up from `max / 2` by `gap / 4`
  - insult thresholds are hard-coded as `< min / 2` and `> 2 * max`
  - kick happens after `3` insults
  - final phase is a generic Y/N confirmation after `4` rounds
  - accepted price is always the current ask/counter price
- The current store data model is intentionally thin:
  - per-visit `hg_insults`
  - per-store `hg_kicked`
  - no owner-specific haggle parameters
  - no persistent bargaining skill memory
  - no temporary store lockout timer
- Upstream VMS/Umoria haggle behavior is materially richer than the current port:
  - backwards offers are rejected and can count as insults
  - counter progression depends on offer ratio, not a fixed quarter-gap step
  - overshoot/undershoot gets explicit retry reactions
  - final-offer exhaustion has distinct behavior
  - successful business reduces the accumulated insult state

#### Phase A
- Treat this as a parity/regression fix, not a full store-system rewrite.
- Restore one-visit haggle behavior to VMS semantics using Umoria's integer bargaining model, without adding new persistent shop state.
- Cover these behaviors explicitly:
  - offer parser correctness
  - backwards-offer rejection
  - overshoot/undershoot retry behavior
  - integer ratio-based counter-offer progression
  - final-offer exhaustion behavior
  - correct accept-price semantics
  - insult accumulation, kick threshold, and post-deal insult decay
  - cheap-item / Black Market no-haggle bypass behavior
- Keep buy and sell implementations readable even if they share small helpers; do not force an abstract shared haggle core during the parity pass.

#### Phase B
- Leave these as follow-up work unless Phase A proves they are required by the live bug:
  - owner-specific haggle parameters
  - temporary store closure / reopen timing
  - bargaining-memory / no-need-to-bargain state
  - incremental `+/-` haggle input
  - richer speech/comment tables

#### Verification
- Add focused runtime haggle tests for:
  - buy exact-match, over-ask, under-ask, backwards second offer, repeated insulting offers, first-prompt cancel, later cancel, final-offer reject
  - sell exact-match, below-offer, above-offer, backwards second ask, repeated insulting asks, store-full after accepted deal, worthless/cursed/non-buyable exits
  - parser paths: leading spaces, empty input, delete/backspace, 5-digit limit, overflow-ignore, cancel keys
  - state paths: `hg_insults` reset on entry, decremented after a successful deal, `hg_kicked` persistence until its intended reset point
  - bypass paths: cheap-item no-haggle and Black Market no-haggle
- Run the standard C64 store/runtime coverage plus the usual broader C64/C128 regression pass after the fix lands.

#### Review
- Consultant review confirmed the correct boundary is one-visit haggle correctness first, not a full persistent-store refactor.
- The main correction from review was to avoid claiming a direct VMS arithmetic port; VMS should drive behavior, while Umoria should drive the integer implementation shape.
- The plan also now treats parser behavior and post-deal insult decay as first-class Phase A work instead of optional polish.
- Stage A landed in the existing thin store model with new `hg_last_*`, denominator scratch, and concession-percent state only; no persistent bargaining-memory or owner-schema work was added.
- `haggle_buy` and `haggle_sell` now reject backwards offers, retry overshoot/undershoot neutrally, use integer concession ratios for counter-offers, accept at the player's agreed number when appropriate, and decay `hg_insults` after successful no-haggle or haggled transactions.
- Focused store verification passed at `37/37` tests after adding parser, buy/sell flow, insult/kick, and no-haggle bypass coverage.
- Broader regression passed after fixing four C64 test-harness layout regressions that Stage A code growth exposed:
  - `test_main_loop.s`, `test_dungeon.s`, and `test_monster_ai.s` were linking unnecessary store/help payload and crossed reserved boundaries.
  - `test_effects.s` also overlapped its own `$A000` scratch-buffer segment; its buffer was moved above the linked body and the assert was tightened to the real boundary.
- Final verification:
  - `bash commodore/c64/run_tests.sh` -> `33 passed, 0 failed`
  - `make test128-fast` -> passed via tester agent
  - C128 authoritative runner repair:
    - `run_test_internal_worker.sh` now runs unit tests with `-autostart` plus a pass breakpoint and shell-side VICE supervision, so `minimal128` and the rest of the unit batch no longer hang waiting at the monitor.
    - `run_tests128.sh` prompt guard now matches the live Huffman-backed prompt helpers in `player_items.s`.
    - `run_tests128.sh` town overlay smokes now use `until $store_enter`, and `real_input_town_move_diag` now runs all stage breakpoints in one boot instead of 15 separate boots.
    - `run_tests128.sh` `main128_asm` now forces a base rebuild when the active C128 variant is not `base`, so later variant compiles cannot leave `out/moria128.prg` / `out/main.vs` contaminated for the next `c128_artifact_budget` run.
  - Focused C128 verification:
    - `TEST_FILTER='prompt_irq_guard' TEST_FAIL_FAST=1 ./run_tests128.sh` -> `PASS`
    - `TEST_FILTER='minimal128' TEST_FAIL_FAST=1 ./run_tests128.sh` -> `PASS`
    - `TEST_FILTER='town_overlay_female_smoke' TEST_FAIL_FAST=1 ./run_tests128.sh` -> `PASS`
    - `TEST_FILTER='town_overlay_state_smoke' TEST_FAIL_FAST=1 ./run_tests128.sh` -> `PASS`
    - `TEST_FILTER='real_input_town_move_diag' TEST_FAIL_FAST=1 ./run_tests128.sh` -> `PASS`
    - `TEST_FAIL_FAST=1 TEST_FILTER='c128_artifact_budget|main128_layout' ./run_tests128.sh` -> `PASS`
    - Deliberately contaminate `out/moria128.prg` with `C128_TEST_SCRIPTED_INPUT`, then rerun `TEST_FAIL_FAST=1 TEST_FILTER='main128_asm|c128_artifact_budget' ./run_tests128.sh` -> `2 passed, 0 failed`
    - `TEST_FAIL_FAST=1 ./run_tests128.sh` -> `41 passed, 0 failed`
  - Closeout:
    - `BUG-HAGGLE-UI` moved from `commodore/BUILDPLAN.md` to `commodore/BUILDPLAN_HISTORY.md`
    - final diagnosis: Stage A haggle gameplay fix was valid; the last C128 fallout was stale variant artifact reuse plus a runner-footer bug

- [x] Complete the carried-item half of `CA-02` with a dedicated visible-slot cache that does not alias shared message buffers.
- [x] Keep the final cache storage local to `player_items.s` so filtered prompts cannot recreate the earlier `test_item` hang.
- [x] Rebuild and rerun the standard C64/C128 verification on the completed `CA-02` implementation.
- [x] Add a shared visible-slot cache for contiguous equipment selection in `item_takeoff`.
- [x] Keep the plain all-inventory command on its existing absolute-slot behavior.
- [x] Rebuild and rerun the standard C64/C128 verification on the reduced safe implementation.
- [x] Execute `CA-01` by unifying the shared numeric formatting core used by screen output and combat messages.
- [x] Remove the cross-module `decimal_powers_*` dependency on the screen backend so combat formatting owns only common numeric data.
- [x] Add focused runtime coverage for direct screen decimal output and combat decimal-buffer output after the refactor.
- [x] Rebuild and rerun the standard C64/C128 verification, then refresh the audit/headroom/task docs with the live post-change layout.
- [x] Execute `LINT-1` by adding a reproducible 6502 anti-pattern linter to the repo.
- [x] Fail on provably redundant zero-compares, but keep branch-then-jump ladders advisory until they are triaged.
- [x] Clean up the first live redundant-compare hits so the new linter lands green on the current tree.
- [x] Rebuild and rerun the standard C64/C128 verification after the lint-driven source cleanup.
- [x] Execute `ALIGN-1` by auditing hot render/combat/input indexed accesses against the live symbol layout.
- [x] Distinguish page-safe tables from real page-cross candidates in the current C64 and C128 builds.
- [x] Quantify likely cycle impact only where the current hot-path access pattern justifies it.
- [x] Update the audit plan with concrete alignment findings and move the queue to the next unresolved phase.
- [x] Execute `ZP-1` by adding an automated scan for raw zero-page ownership violations.
- [x] Flag raw `$90-$FF` zero-page memory operands outside explicitly blessed KERNAL/MMU helper cases.
- [x] Keep the scan focused on real assembly operands rather than `.byte` data, comments, or immediates.
- [x] Wire the scan into a reproducible project check path and record the first live results in the audit docs.
- [x] Execute `CA-12` by replacing the public one-bit RNG byte path with a real byte-step generator.
- [x] Keep the final implementation inside the C64 banked-payload budget while improving byte-quality output.
- [x] Add focused runtime coverage that proves `rng_next` advances exactly eight reference one-bit steps.
- [x] Run shared RNG verification plus broader regression coverage for common consumers, then refresh the audit/headroom/task docs with the live post-change layout.
- [x] Execute `API-1` by enforcing one caller-visible C128 text contract at the VDC screen layer.
- [x] Make `screen_put_string` accept PETSCII like `screen_put_char` while preserving compatibility for embedded direct VDC/control bytes.
- [x] Add a focused C128 regression that proves lowercase PETSCII strings and direct VDC byte passthrough both survive the new contract.
- [x] Rebuild the C128 target, rerun focused and fast C128 verification, and refresh the audit/headroom docs with the live post-change layout.
- [x] Execute `WRAP-1` by fixing the C128 KERNAL-wrapper IRQ-state contract.
- [x] Preserve the caller `I` bit while still returning the KERNAL carry/flag result.
- [x] Update the focused cold-boot wrapper probe to match the fixed scaffold and the real C128 `$01` low-bit contract.
- [x] Run focused wrapper verification and a broader C128 regression pass on the final patch.
- [x] Execute `CA-11` melee to-hit overflow/sign handling.
- [x] Confirm the live overflow/sign bug in `combat_calc_tohit_common`.
- [x] Add targeted regression coverage for high positive and high negative `PL_TOHIT`.
- [x] Run focused verification for shared callers after the fix.
- [x] Execute `HEADROOM-1` and produce an exact margin report for the constrained C64/C128 regions.
- [x] Rebuild the live C64 and C128 targets before recording headroom numbers.
- [x] Compute exact byte margins for C64 main, banked, and overlay regions.
- [x] Compute exact byte margins for C128 staged-source, banked, overlay, low-runtime, and Bank 1 ownership regions.
- [x] Record the measured headroom report in the Commodore docs.
- [x] Re-verify the older C128 IRQ/KERNAL-wrapper finding from `commodore/AUDIT.md` against the live tree.
- [x] Inspect the current wrapper implementation and existing related diagnostics/tests before changing any code.
- [x] Run a focused verification path for I-flag preservation / runtime IRQ-state restoration across representative wrappers.
- [x] Record the verified outcome in the audit docs and note whether the old finding remains live, stale, or partially true.
- [x] Inventory existing audit notes, architecture constraints, and 6502 gotchas relevant to the Commodore tree.
- [x] Scan `commodore/common/`, `commodore/c64/`, and `commodore/c128/` for repeated helpers, style drift, wasteful instruction patterns, and common 6502 correctness risks.
- [x] Quantify each actionable audit item with rough code-size and/or cycle savings, scope, risk, and likely shared refactor seam.
- [x] Write `commodore/CODE_AUDIT.md` as the consolidated audit plan with prioritized findings and suggested verification steps.
- [x] Review the finished audit against current build/memory/banking constraints and record the review summary here.

## `AUDIT-P1-WRAPPERS` Design

### Goal
- Execute phase 1 of the revised core audit:
  - re-verify the older C128 wrapper/IRQ finding from `commodore/AUDIT.md`
  - determine whether it is still live in the current codebase
  - update the audit docs based on evidence, not historical memory

### Scope
- In scope:
  - `commodore/c128/main.s`
  - `commodore/c128/memory128.s`
  - existing C128 tests/diagnostics relevant to wrapper state preservation
  - targeted verification commands needed to prove the current behavior
- Out of scope:
  - broad refactors of the wrappers unless the bug is proven live
  - unrelated C128 banking changes

### Verification Standard
1. Confirm the current wrapper code shape in source.
2. Check whether existing automated tests already cover IRQ-state preservation.
3. Run a focused verification path for representative wrappers.
4. Update the audit docs with one of:
   - still live
   - stale / already fixed
   - partially true / needs narrower restatement

### Review
- Completed.
- Source review showed the current wrappers no longer match the exact historical phrasing in `commodore/AUDIT.md`, because `php` happens after the KERNAL `jsr`, not immediately after `:EnterKernal()`.
- A direct monitor jump into the full `moria128.prg` wrapper addresses was too stateful to trust without a fully booted runtime, so the verification path pivoted to an isolated cold-boot test using the current wrapper shape plus `memory128.s`.
- The focused probe in `commodore/c128/tests/test_wrapper_irq128.s` confirmed the old bug remains live for the common wrapper scaffold:
  - first failing stage `#$11` = `w_readst` from caller-`CLI`
  - captured interrupt bit `dbg_ibit = $04`
  - meaning the wrapper returned with IRQs disabled even though the caller entered with IRQs enabled
- Result: phase 1 is resolved as `still live`, not stale. `commodore/CODE_AUDIT.md` now promotes this to active item `WRAP-1`.

## `AUDIT-P2-HEADROOM` Design

### Goal
- Execute `HEADROOM-1` as a concrete measurement pass instead of leaving it as a planning-only item.
- Produce one exact headroom report covering:
  - C64 main image
  - C64 banked payload source/runtime
  - C64 overlays
  - C128 staged source / Bank 0 image
  - C128 runtime banked payload
  - C128 overlays
  - C128 `RuntimeLowData`
  - C128 Bank 1 ownership gaps

### Scope
- In scope:
  - `commodore/c64/main.s`
  - `commodore/c64/out/main.vs`
  - `commodore/c128/main.s`
  - `commodore/c128/memory128.s`
  - `commodore/c128/out/main.vs`
- Out of scope:
  - changing any memory layout in this phase
  - implementing the future build-time generated summary

### Review
- Completed.
- Rebuilt the live C64 and C128 targets and used the emitted symbol files as the source of truth for next-free end labels.
- Added `commodore/HEADROOM_REPORT.md` with exact byte margins and risk ranking.
- Most important measured outcomes:
  - C128 `RuntimeLowData` has `0` bytes before floor-item storage at `$1A00`
  - C64 runtime banked payload has `2` bytes before `$FFFA`
  - C64 staged banked payload source has `3` bytes before `$D000`
  - C128 startup overlay has `35` bytes before `$F000`
  - C64 main image has `40` bytes before `MAP_BASE`
  - C64 startup overlay has `44` bytes before `$F000`
- Updated `commodore/CODE_AUDIT.md` so `HEADROOM-1` now references the completed measurement pass instead of only describing the intended deliverable.
- Refreshed the report after the `CA-11` fix changed shared-code size; the current live numbers are the ones above and in `commodore/HEADROOM_REPORT.md`.

## `AUDIT-P3-CA11` Design

### Goal
- Execute `CA-11` by fixing the melee to-hit overflow/sign bug in shared combat logic.
- Preserve the existing contract:
  - final to-hit stays clamped to `0..255`
  - negative penalties can still floor the pre-level value to `0`
  - per-level class adjustment still applies after the `PL_TOHIT` contribution

### Scope
- In scope:
  - `commodore/common/combat.s`
  - `commodore/c64/tests/test_combat.s`
  - `commodore/c64/run_tests.sh`
- Out of scope:
  - broader RNG or combat-balance changes
  - monster attack math

### Review
- Completed.
- Fixed the shared `PL_TOHIT * 3` path by saturating before the intermediate 8-bit multiply wraps, in both the positive and negative branches.
- Added two regression cases to `test_combat.s`:
  - `PL_TOHIT = 100` must cap the final result at `255`
  - `PL_TOHIT = -100` must floor the pre-level total to `0`, then end at `4` after the Warrior level-1 bonus
- Updated the combat suite expectations in `run_tests.sh` from `20` to `25`.
- Focused verification:
  - `tests/test_combat.s` → all `25/25` checkpoints passed
  - `tests/test_throw.s` → all `6/6` checkpoints passed

## `AUDIT-P4-WRAP1` Design

### Goal
- Execute `WRAP-1` by repairing the caller-visible IRQ-state contract for the shared C128 KERNAL wrappers.
- Preserve both of these together:
  - the caller's original `I` bit
  - the KERNAL call's returned Carry/flag result

### Scope
- In scope:
  - `commodore/c128/main.s`
  - `commodore/c128/tests/test_wrapper_irq128.s`
  - focused C128 verification for the wrapper scaffold and affected runtime state
- Out of scope:
  - broader wrapper deduplication / macro-generation (`CA-09`)
  - unrelated C128 banking or overlay refactors

### Review
- Completed.
- Fixed the shared wrapper scaffold by saving caller status before `:EnterKernal()` and restoring the KERNAL return flags with the caller's original `I` bit spliced back in after `:ExitKernal()`.
- Applied the same contract repair to the special-case paths:
  - `w_load`
  - `kernal_load_safe`
  - `safe_setbnk`
- Updated the focused probe in `test_wrapper_irq128.s` to match the repaired scaffold and to validate the real C128 `$01` contract by masking to the low three banking bits.
- Focused verification:
  - `commodore/c128/tests/test_wrapper_irq128.s` → `PASS`
  - `make test128-fast` → `PASS`
- Refreshed the headroom baseline after the wrapper fix:
  - C128 staged source / program image is now `76` bytes below `$E000`
  - C128 cache-state block now ends at `$32F8`

## `AUDIT-P5-API1` Design

### Goal
- Execute `API-1` by giving the C128 screen layer one caller-visible text rule.
- Make the public VDC text entry points behave like the rest of the shared UI code expects:
  - PETSCII in
  - backend-native screen codes out
- Preserve the existing tolerance for embedded direct VDC/control bytes that already exist in packed UI/title data.

### Scope
- In scope:
  - `commodore/c128/screen_vdc.s`
  - focused C128 text/output regression coverage
  - audit/headroom/task docs affected by the layout change
- Out of scope:
  - broad callsite rewrites across shared UI code
  - changes to the VIC-II backend contract

### Verification Standard
1. Confirm the mixed contract in the current VDC backend source.
2. Change the public string path so PETSCII strings and PETSCII chars share the same translation rule.
3. Prove lowercase PETSCII survives the string path on VDC.
4. Prove embedded direct VDC bytes still pass through unchanged.
5. Rebuild C128, rerun the fast C128 suite, and refresh the live headroom/audit docs.

### Review
- Completed.
- Updated `commodore/c128/screen_vdc.s` so the public VDC text contract is now consistent:
  - `screen_put_char` and `screen_put_string` both accept PETSCII
  - embedded direct VDC/control bytes still pass through because the backend translator only remaps PETSCII lowercase
- Added focused regression coverage in `commodore/c128/tests/test_vdc_attr128.s` for:
  - lowercase PETSCII string translation (`"Ab"` writes lowercase `b` as VDC Set 1 code `$02`)
  - direct VDC byte passthrough (`$03` remains `$03`)
- Rebuilt the C128 target and refreshed the post-change layout:
  - C128 staged source / program image is now `73` bytes below `$E000`
  - C128 cache-state block now ends at `$32FB`
  - C128 overlay-state block now ends at `$32F3`
- Verification completed:
  - `commodore/c128/tests/test_vdc_attr128.s` → `PASS`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` → `PASS`
- Environment note:
- `make test128-fast` remained PATH-sensitive in this shell and repeatedly reset the monitor connection while using bare `x128`
- the equivalent explicit-binary batch command above completed cleanly and is the verification result for this phase

## `AUDIT-P6-CA12` Design

### Goal
- Execute `CA-12` by making the public RNG byte API match its name:
  - `rng_next` / `rng_byte` should yield a fresh byte step, not a one-bit shift artifact
- Keep the implementation small enough to stay inside the current C64 banked-payload ceiling.

### Scope
- In scope:
  - `commodore/common/rng.s`
  - `commodore/c64/tests/test_rng.s`
  - `commodore/c64/run_tests.sh`
  - audit/headroom/task docs affected by the layout change
- Out of scope:
  - changing the RNG polynomial or seed source
  - game-balance tuning on top of the better byte-quality distribution

### Verification Standard
1. Prove the current live `rng_next` is still only advancing one bit.
2. Change the public byte path so one call advances eight LFSR steps.
3. Keep the final implementation inside the live C64 memory budget.
4. Add a runtime test that compares the new byte-step path against a local reference-step implementation.
5. Run focused RNG verification and broader shared-gameplay regression coverage before updating the docs.

### Review
- Completed.
- Updated `commodore/common/rng.s` so the public byte API now advances the 32-bit LFSR eight times per call before returning `zp_rng_0`.
- Deliberately did **not** keep a public `rng_step_bit` entry in the final patch:
  - the first split-API draft pushed the C64 banked payload past `$D000`
  - the final implementation kept the byte-step quality fix while recovering the lost headroom
- Tightened `rng_range_word` scratch usage so the final shared patch fits the live C64 banked boundary again:
  - C64 staged banked payload source remains at `$CFFD`, with `3` bytes below `$D000`
  - C128 staged source / program image moved to `$DFCA`, leaving `54` bytes below `$E000`
- Added focused regression coverage in `commodore/c64/tests/test_rng.s` proving `rng_next` matches eight reference one-bit steps.
- Fixed two latent test-harness issues that were uncovered by the broader rerun:
  - `commodore/c64/tests/test_monster_ai.s` test 20 now reloads the monster pointer after clearing the old occupied tile
  - `commodore/c64/tests/test_combat.s` test 20 now falls through to tests 21-25, and test 23 now matches the actual excess-halving level-up behavior
- Verification completed:
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` → `PASS`

## `AUDIT-P7-ZP1` Design

### Goal
- Execute `ZP-1` by turning the declared zero-page ownership contract into an automated check.
- Catch the high-risk drift:
  - raw `$90-$FF` zero-page memory operands outside explicitly blessed cases
  - raw literal zero-page operands where the code should normally be using named labels

### Scope
- In scope:
  - `commodore/common/zeropage.s`
  - assembly sources under `commodore/common/`, `commodore/c64/`, and `commodore/c128/`
  - build plumbing needed to run the scan consistently
  - audit/task docs updated from the first live scan results
- Out of scope:
  - broad renaming of existing zero-page labels
  - changing the zero-page map itself in this phase
  - data-byte style cleanup unrelated to real memory operands

### Verification Standard
1. Confirm the live zero-page contract from `zeropage.s`.
2. Implement a scanner that inspects assembly operands after stripping comments.
3. Prove the scanner ignores false-positive classes such as `#$ff`, `.byte $ff`, and comment text.
4. Run the scanner against the live tree and classify each hit as:
   - real violation to fix
   - explicitly blessed raw usage
   - scanner gap to tighten
5. Update the audit docs with the completed scan result and remaining follow-up, if any.

### Review
- Completed.
- Added `tools/check_zp_usage.py` and root `make check-zp` so the zero-page contract is now enforced by a reproducible project command instead of comments alone.
- Tightened the scanner after the first run so it ignores immediate-expression false positives like `#~FLAG & $ff`, `.byte $ff`, and comment text.
- The first real scan found intentional but undocumented raw accesses to KERNAL / Screen Editor bytes:
  - `$90` status / `READST`
  - `$C6` keyboard buffer count
  - `$CC` Screen Editor cursor/keyboard state
  - `$D8` C128 Screen Editor 80-column mode byte
- Converted those call sites to named symbols in `commodore/common/zeropage.s`, and replaced the remaining raw low-ZP scratch loops with symbolic operands in:
  - `commodore/c64/main.s`
  - `commodore/c64/memory.s`
  - `commodore/c128/boot128.s`
  - `commodore/c128/memory128.s`
- Verification completed:
  - `python3 tools/check_zp_usage.py --self-test` → `PASS`
  - `make check-zp` → `0 error(s), 0 warning(s)`
  - `make -C commodore/c64 build` → `PASS`
  - `make -B -C commodore/c128 build128` → `PASS`
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed` on rerun after the known flaky `render` suite
- `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` → `PASS`

## `AUDIT-P8-ALIGN1` Design

### Goal
- Execute `ALIGN-1` by checking the live build, not just source layout comments, for page-cross penalties in hot render, combat, and input paths.
- Separate:
  - already-safe hot tables that do not need churn
  - real page-cross candidates that are worth future action
  - cold crossings that should not be sold as high-ROI optimization

### Scope
- In scope:
  - `commodore/c64/dungeon_render.s`
  - `commodore/c128/dungeon_render_vdc.s`
  - `commodore/common/combat.s`
  - `commodore/c64/input.s`
  - `commodore/c128/input128.s`
  - `commodore/c128/screen_vdc.s`
  - current C64/C128 symbol outputs used to locate the live table addresses
- Out of scope:
  - speculative percentage speedup claims
  - broad data-layout rewrites in this phase
  - padding/alignment changes that spend headroom without evidence

### Verification Standard
1. Identify the actual indexed tables used in the hot render/combat/input loops.
2. Check their current addresses in the live C64 and C128 symbol maps.
3. Mark each case as:
   - page-safe in the full indexed range
   - crossing, but cold enough to ignore for now
   - crossing in a genuinely hot path
4. Estimate cycle impact only from the real access count and current thresholds.
5. Update the audit docs with the completed findings and the next execution item.

### Review
- Completed.
- Most of the true hot-path row/tile tables are already well placed in the live builds:
  - C64 `map_row_*`, `screen_row_*`, `color_row_*`, `tile_screen_codes`, and `tile_colors` stay within page for their full indexed ranges
  - C128 `map_row_*`, `screen_row_*`, `color_row_*`, `tile_screen_codes`, `tile_vdc_colors`, `cia_scancode_table`, `key_map_petscii`, `key_map_cmd`, and `vic_to_vdc_color` are also page-safe across the indexed ranges actually used
- The highest-value live crossing is the C64 input search table:
  - `key_map_petscii` starts at `$10E6`, so the linear `cmp key_map_petscii,x` loop crosses page once `x >= 26`
  - worst case is `27` extra cycles per full-table search
  - movement keys and common early table hits avoid the penalty, so this is real but not top-tier
- The remaining crossings found in this phase are narrower:
  - C64 `cr_color` at `$35E0` crosses for monster types `>= 32`
  - C128 `cr_display` at `$5EF3` crosses for monster types `>= 13`
  - C128 `cr_level` at `$5FF7` crosses for monster types `>= 9`
- Those creature-table crossings are real, but their savings are modest:
  - roughly `+1` cycle per crossed lookup
  - on C128 the VDC I/O cost dominates total render time, so table realignment here is lower priority than the current audit queue
- A few non-hot/cold crossings still exist, such as C64 `xp_level_lo`, but they do not justify promotion into the hot-path alignment backlog.
- Verification completed:
  - `make -C commodore/c64 build` → `PASS`
  - `make -B -C commodore/c128 build128` → `PASS`
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed` on rerun after the known flaky `render` suite
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` → `PASS`

## `AUDIT-P9-LINT1` Design

### Goal
- Execute `LINT-1` by moving recurring 6502 instruction-shape nits into a reproducible static check.
- Start narrow and high-confidence:
  - fail on provably redundant zero-compares
  - surface branch-then-immediate-jump ladders as advisory warnings, not hard failures

### Scope
- In scope:
  - assembly sources under `commodore/common/`, `commodore/c64/`, and `commodore/c128/`
  - build plumbing needed to run the new linter consistently
  - the first small wave of source cleanup required to land the linter green
  - audit/headroom/task docs affected by the resulting code-size changes
- Out of scope:
  - broad ladder rewrites for every branch-range workaround
  - duplicate-constant linting in this phase
  - test-tree style assertions that intentionally compare against zero

### Verification Standard
1. Implement a source-tree linter with internal self-tests.
2. Restrict the hard-fail rule to cases where:
   - the compare is `cmp/cpx/cpy #0`
   - the previous real instruction already set the relevant N/Z flags
   - the next real instruction branches only on N/Z (`beq/bne/bmi/bpl`)
3. Run the linter on the live tree and fix the first real hits.
4. Keep branch-then-jump shapes as warnings only and record the backlog size.
5. Rebuild C64/C128 and rerun the normal runtime verification before closing the phase.

### Review
- Completed.
- Added `tools/check_6502_lint.py` and root `make check-6502-lint`.
- The initial linter rules are intentionally conservative:
  - hard-fail on redundant `cmp/cpx/cpy #0` only when the surrounding instructions prove the compare is unnecessary
  - warn on branch-then-immediate-jump ladders so the repo can track them without forcing a risky mass rewrite
- Cleaned the first six live redundant-compare hits in shipping source:
  - `commodore/c128/input128.s`
  - `commodore/common/dungeon_gen.s`
  - `commodore/common/ui_character.s`
- First live lint result after cleanup:
  - `make check-6502-lint` → `0 error(s), 320 warning(s)`
  - all warnings are advisory branch-jump ladders; the tool prints only the first batch and suppresses the remainder
- Refreshed the live layout after the cleanup:
## `AUDIT-P10-CA01` Design

### Goal
- Execute `CA-01` with a size-positive shared numeric core, not just a source-only move.
- Remove the duplicated decimal decomposition logic that currently exists separately in:
  - screen decimal output
  - combat message decimal appenders
- Keep the public entry points unchanged:
  - `screen_put_decimal`
  - `screen_put_decimal_rj2`
  - `screen_put_decimal_lz2`
  - `screen_put_decimal_16`
  - `combat_append_decimal`
  - `combat_append_decimal_16`

### Scope
- In scope:
  - `commodore/common/combat.s`
  - `commodore/common/numeric_format.s` (new shared module)
  - `commodore/c64/screen.s`
  - `commodore/c128/screen_vdc.s`
  - focused runtime tests that directly validate numeric output
  - audit/headroom/task docs affected by the layout change
- Out of scope:
  - changing the 24-bit score formatter in this phase
  - changing caller-facing screen or combat APIs
  - broad text/UI refactors unrelated to numeric formatting

### Verification Standard
1. Replace the duplicated 8-bit and 16-bit decimal decomposition with one shared implementation per build.
2. Move the 16-bit power-of-10 tables into common code so combat no longer depends on backend-local screen data.
3. Preserve exact visible output for:
   - screen decimal print paths
   - combat message decimal appenders
4. Add direct runtime coverage for the refactored screen and combat formatter paths.
5. Rebuild C64/C128, rerun the standard verification, and record the real headroom delta.

### Review
- Completed.
- Added `commodore/common/numeric_format.s` as the shared 8-bit / 16-bit formatter core for:
  - `screen_put_decimal`
  - `screen_put_decimal_rj2`
  - `screen_put_decimal_lz2`
  - `screen_put_decimal_16`
  - `combat_append_decimal`
  - `combat_append_decimal_16`
- Removed the old cross-module `decimal_powers_*` dependency from `combat.s`; combat now formats through common numeric data instead of backend-local screen tables.
- Added direct runtime coverage for the refactor:
  - `commodore/c64/tests/test_score.s` now checks `screen_put_decimal_lz2` and `screen_put_decimal_16`
  - `commodore/c64/tests/test_combat.s` now checks `combat_append_decimal` and `combat_append_decimal_16`
  - `commodore/c128/tests/test_vdc_attr128.s` now checks VDC `screen_put_decimal_16`
- Live headroom improved materially in the constrained staged/source regions:
  - C64 main image margin moved from `40` to `141` bytes below `$C000`
  - C64 staged banked payload source moved from `5` to `106` bytes below `$D000`
  - C128 staged source / program image moved from `79` to `180` bytes below `$E000`
- Verification completed:
  - `make check-zp` → `PASS`
  - `make check-6502-lint` → `PASS` with `318` advisory warnings
  - `java -jar ../../tools/kickass/KickAss.jar main.s -showmem -vicesymbols -o out/moria8.prg` in `commodore/c64` → `PASS`
  - `make -B -C commodore/c128 build128` → `PASS`
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed`
  - `make test128-fast` → `PASS`
- At that checkpoint, the next unresolved audit phase was `CA-02` (now completed in `AUDIT-P20-CA02`).

## `AUDIT-P11-CA02` Design

### Goal
- Execute `CA-02` by building the filtered inventory/equipment visible-slot list once and reusing it across:
  - prompt range generation
  - overlay letters/order
  - key-to-slot mapping
- Preserve the user-visible contracts:
  - filtered prompts still relabel contiguously from `A`
  - full inventory/drop/throw paths still use absolute slot letters
  - zero-match behavior and cancellation stay unchanged

### Scope
- In scope:
  - `commodore/common/player_items.s`
  - `commodore/common/ui_inventory.s`
  - focused runtime coverage that already exercises sparse filtered selection / takeoff mapping / filtered overlays
  - audit/headroom/task docs affected by any layout change
- Out of scope:
  - broad inventory UI redesign
  - changing the all-inventory/drop/throw absolute-letter contract
  - unrelated item/equipment logic

### Verification Standard
1. Build one shared visible-slot cache for filtered carried-item prompts.
2. Build one shared visible-slot cache for contiguous equipped-item selection.
3. Make filtered overlays consume the cache instead of rescanning when applicable.
4. Keep full inventory display and absolute-slot pickers unchanged.
5. Rebuild C64/C128, rerun the standard runtime checks, and record the real headroom delta.

### Review
- Partially completed.
- The first full `player_items.s` cache rewrites were not safe:
  - filtered-inventory cache attempts caused `commodore/c64/tests/test_item.s` to hang instead of return within the project timeout rules
  - the hang disappeared immediately when `player_items.s` was restored to the last known-good filtered selection path
- A reduced implementation is now verified:
  - `item_takeoff` uses a cached contiguous equipment-slot list for prompt count + key-to-slot mapping
  - filtered carried-item prompts remain on the original count-scan + pick-scan path for now
- Verification completed on the reduced implementation:
  - direct `tests/test_item.s` monitor run returned in `~6.4s` with `47/47` passes
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed`
  - `make test128-fast` → `PASS`
- Outcome:
  - `CA-02` is narrowed, not closed
  - the remaining open work is the filtered-inventory cache, and it must be treated as a memory/corruption problem inside `commodore/common/player_items.s`, not a timing problem

### `AUDIT-P20-CA02` Review

- Completed.
- Finished the carried-item half of `CA-02` in `commodore/common/player_items.s` by replacing the filtered prompt count-scan + key-pick rescan pair with one dedicated visible-slot cache.
- Kept the cache storage local to `player_items.s` instead of reusing `combat_msg_buf`; that was the critical safety constraint that prevented the earlier hang from returning.
- Caught and fixed one follow-up bug during verification:
  - the first cache draft failed to preserve the visible-count index across `piw_inv_slot_matches_filter`, which wrote slot numbers at the wrong offsets and broke the late filtered-item tests
- Final measured outcome:
  - filtered carried-item rescans are removed
  - equipment-selection rescans remain removed from the earlier phase-11 reduction
  - no measurable headroom delta versus the phase-19 tree
- Verification:
  - `bash commodore/c64/run_tests.sh`: `33 passed, 0 failed`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`: `PASS`

## `CODE_AUDIT` Review

### Review Pass 1
- The initial audit missed two live correctness risks that are still present in the tree: melee to-hit overflow handling in `combat.s` and the one-bit-step RNG in `rng.s`.
- The numeric-format savings were understated because `score.s` has its own 24-bit formatter in addition to the two screen backends and combat formatter.
- Several smaller refactor items were too optimistic on byte savings; those claims were tightened to realistic ranges.

### Review Pass 2
- Fixed the placement of the `CA-10` verification notes so the audit reads cleanly end-to-end.
- Updated the formatter evidence to cite the score formatter as another actual duplicate.
- Toned down the RNG item so it reads as a quality/design tradeoff rather than a high-priority correctness defect.
- Final audit state is focused on actionable items with realistic savings or explicit cycle-cost tradeoffs where appropriate.

### Review Pass 3
- Reframed the audit around perimeter safety and architectural debt rather than cleanup-first prioritization.
- Added `HEADROOM-1`, `ALIGN-1`, `ZP-1`, `LINT-1`, and `API-1` as governance items ahead of the tactical cleanup backlog.
- Softened `API-1` to require one caller-visible C128 text contract without prematurely forcing one internal storage choice.
- Made the immediate execution order explicit: re-verify the old wrapper bug, produce exact memory-margin reporting, then address the arithmetic and contract issues.

## `CODE-AUDIT` Design

### Goal
- Produce a repo-grounded audit plan for the Commodore codebase focused on:
  - common 6502 mistakes and fragile idioms
  - duplicated or near-duplicated code that should be shared
  - computationally or space-wasteful patterns
  - structure/style/alignment consistency
- The expected artifact is `commodore/CODE_AUDIT.md`, not an implementation patch set.

### Scope
- In scope:
  - `commodore/common/`
  - `commodore/c64/`
  - `commodore/c128/`
  - current project docs when they constrain or explain the code shape
- Out of scope:
  - non-Commodore trees
  - speculative changes that ignore current segment/banking limits
  - claiming measured runtime improvements that were not actually benchmarked

### Audit Method
1. Reuse existing local evidence first:
   - `commodore/AUDIT.md`
   - `commodore/DESIGN.md`
   - `tasks/6502_gotchas.md`
   - active build-plan backlog items
2. Inspect representative shared/runtime-heavy files for:
   - duplicate helpers
   - branch/flag misuse
   - repeated save/restore scaffolding
   - unnecessary loads/stores/compares
   - inconsistent loop/control-flow shapes
3. Prefer findings that are concrete enough to estimate:
   - byte savings
   - per-call or per-tile cycle savings
   - maintenance/risk reduction
4. Present the result as an implementation plan:
   - item
   - evidence
   - proposed cleanup/refactor
   - expected savings
   - verification notes / guardrails

### Constraints
- Do not disturb current memory/banking contracts in the audit recommendations.
- Any suggested shared helper must respect C64/C128 execution-bank differences.
- Savings are estimates unless explicitly measured.

### Review
- Completed. The final audit now leads with governance items for headroom, alignment, zero-page ownership, linting, and the C128 text contract, followed by the tactical cleanup findings and revised execution order.

## Previous Task Notes
- [x] Audit the shared filtered prompt/display paths in `ui_inventory.s`, `player_items.s`, and related item-selection callers.
- [x] Review upstream VMS-Moria and Umoria behavior for filtered item prompts and equipment selection.
- [x] Get consultant input on the safest shared fix shape and regression strategy.
- [x] Lock the local `BUG-PROMPT-FILTER` user-visible contract and implementation seam.
- [x] Write the implementation checklist and focused verification matrix before coding.

## `BUG-PROMPT-FILTER` Design

### Problem Statement
- Active backlog entry: `BUG-PROMPT-FILTER` in `commodore/BUILDPLAN.md`.
- Current filtered item-selection commands still behave like full absolute-slot pickers:
  - prompts advertise the whole range (`a-v` / `a-h`)
  - `?` overlays hide unrelated items but keep absolute slot letters
  - input handlers still parse absolute letters directly and only then reject mismatched categories
- Result: the UI can show a filtered subset while still exposing misleading letters and whole-pack prompt ranges.

### Current Code Facts
- Shared inventory overlay in `commodore/common/ui_inventory.s` already filters rows via `uinv_filter`, but labels filtered entries with absolute slot letters (`A + slot`) instead of contiguous visible letters.
- Shared selection handlers in `commodore/common/player_items.s` still do direct `sbc #$41` absolute-slot parsing for:
  - `item_wear`
  - `item_takeoff`
  - `item_quaff`
  - `item_read_scroll`
  - `item_aim_wand`
  - `item_use_staff`
  - `item_gain_spell`
- `show_inv_and_restore` uses `uinv_filter` only for overlay display, not as a shared source of truth for selection mapping.
- `item_wear` has an extra local eligibility rule beyond category filtering:
  - `ICAT_LIGHT` includes Flask of Oil, but Flask of Oil is not wearable
- Local pack storage is sparse, not compact:
  - `inv_add_item` writes to the first empty carried slot
  - `inv_remove_item` clears a slot and does not compact the pack
- Important scope boundary:
  - `item_drop` and identify-style all-item pickers are unfiltered and do not need this bug’s relabeling
  - `item_eat` auto-selects the first food item and is not a prompted filtered picker today

### Upstream Findings
- **VMS-Moria**
  - `find_range()` in `source/include/moria.inc` discovers the first/last relevant inventory range for a requested object set.
  - `get_item()` then prompts only that filtered range: `(Items a-b, * for inventory list, ^Z to exit) ...`
  - `show_inven()` prints letters from compacted inventory positions within that filtered range.
  - `show_equip()` labels only non-empty equipment entries contiguously (`a`, `b`, `c`, ...).
- **Umoria**
  - `inventoryGetInputForItemId()` in `src/ui_inventory.cpp` is the shared selection gateway for filtered pack/equipment prompts.
  - It prints only the active filtered span (`Items a-b ...`) and keeps the prompt and selection parser in the same shared path.
  - `displayEquipment()` labels only non-empty equipment rows contiguously.
- **Meaning for Moria8**
  - The upstream contract worth preserving is:
    - filtered prompts expose only valid choices
    - visible letters are contiguous
    - `?` overlay letters and accepted input must match
  - The upstream storage assumption is **not** worth copying in this bug:
    - both upstream trees rely on compacted/sorted inventory layouts that Moria8 does not currently have

### Locked User-Visible Contract
1. Any filtered item-selection command must present only valid choices for that command.
2. The `?` overlay for that command must show exactly the same selectable set that the prompt parser accepts.
3. Filtered visible letters must be contiguous from `A` upward with no gaps from hidden sparse slots.
4. Selecting `B` in a filtered prompt must pick the second visible matching item, not the physical slot whose absolute letter is `B`.
5. Prompt text must advertise only the valid visible range, not the whole pack/equipment span.
6. Equipment takeoff selection must use contiguous letters for non-empty equipment rows.
7. Full unfiltered inventory behavior remains unchanged in this bug unless a command is explicitly in the filtered-prompt list.

### Scope Decision
- **In scope for implementation**
  - filtered pack commands:
    - `item_wear`
    - `item_quaff`
    - `item_read_scroll`
    - `item_aim_wand`
    - `item_use_staff`
    - `item_gain_spell`
  - filtered equipment command:
    - `item_takeoff`
- **Out of scope for this bug**
  - pack sorting/compaction
  - global inventory letter redesign for unfiltered views
  - changing storage layout or `inv_add_item` / `inv_remove_item`
  - unrelated all-item pickers such as `item_drop`

### Preferred Design Shape
- Implement this entirely at the prompt/UI-selection layer.
- Do **not** change real inventory/equipment storage order.
- Add one shared mode-aware helper layer in `commodore/common/` for prompted item selection.
- Preferred helper seam:
  - `inv_slot_matches_mode(slot, mode)`:
    - true only if the physical slot is a valid target for the active prompt mode
    - must support command-specific rules such as excluding Flask of Oil from `wear`
  - `inv_count_matches_mode(mode)`:
    - counts visible filtered candidates for dynamic prompt suffixes and zero-match handling
  - `inv_pick_nth_match(letter_index, mode)`:
    - maps visible ordinal `A/B/C...` to the physical sparse pack slot
  - `equip_pick_nth_nonempty(letter_index)`:
    - maps visible ordinal `A/B/C...` to the nth non-empty equipment row
- Use the same helper path from both:
  - overlay rendering (`?`)
  - prompt input parsing
- Keep `uinv_filter` as a rendering hint only if needed for the overlay, but do not let it remain the sole semantic filter source for command selection.

### UI / Prompt Decisions
- Filtered pack overlays should relabel matching items contiguously (`A)`, `B)`, `C)`), not with absolute sparse-slot letters.
- `item_takeoff` should not be redesigned into a different equipment screen.
- Safer equipment approach:
  - keep the existing slot-label rows (`Weapon:`, `Body:`, etc.)
  - add contiguous selection letters only for non-empty rows
  - map `A/B/C...` to the nth occupied equipment row
- Dynamic prompt text should show the actual visible span for the current command:
  - examples: `(A-A)`, `(A-B)`, `(A-C)`
- If there are zero valid items:
  - do not print a misleading `A-V` / `A-H` prompt
  - short-circuit with the appropriate no-valid-item message path before reading input

### Risks / Edge Cases
- Biggest risk: duplicated filter logic between overlay and parser.
  - If the display and parser drift, the bug is still present in a worse form.
- `item_wear` is the main semantic trap.
  - “wearable” is not just category-based because Flask of Oil must stay excluded.
- `item_takeoff` cursed items should remain selectable.
  - They are meaningful targets because selection should still produce the existing cursed rejection.
- Sparse local pack layout means direct upstream range-copying is unsafe.
  - Moria8 must emulate contiguous selection with ordinal mapping, not storage changes.
- Shifted/unshifted letter acceptance should remain compatible with current command behavior.

### Focused Verification Plan
1. **Filtered pack display**
   - Put valid items in non-contiguous slots and verify the `?` overlay shows contiguous letters with no gaps.
2. **Filtered pack selection mapping**
   - Selecting the second visible letter must choose the second matching sparse slot.
3. **Filtered pack rejection**
   - A hidden non-matching absolute slot letter must not select that hidden item.
4. **Wear special case**
   - Flask of Oil must not appear as a wearable candidate.
5. **Equipment sparse selection**
   - Non-adjacent occupied equipment slots must display/select as `A)`, `B)`, etc.
6. **Equipment cursed selection**
   - A cursed equipped item must remain selectable and still produce the existing cursed message.
7. **Zero-match behavior**
   - Each filtered command must avoid a misleading full-range prompt when no valid items exist.
8. **Prompt / overlay parity**
   - The highest prompt letter must equal the number of visible overlay entries.
9. **Regression boundary**
   - Unfiltered inventory/drop behavior remains unchanged.

### Suggested Test Homes
- Extend `commodore/c64/tests/test_item.s` for:
  - wear
  - takeoff
  - quaff
  - read / identify follow-on
  - gain spell if it already has supporting setup nearby
- Extend `commodore/c64/tests/test_wands_staves.s` for:
  - aim wand
  - use staff
- Add focused C128 fast/unit coverage once the shared helper layer exists, because the bug lives in shared prompt/input code.

### Consultant Review
- Consultant consensus:
  - preserve upstream parity at the prompt/UI layer, not the storage layer
  - use one shared ordinal-mapping helper path for both overlays and selection parsing
  - reindex filtered pack prompts and non-empty equipment selection contiguously
  - keep pack sorting/compaction out of this bug

### Review
- Implemented the shared filtered-inventory helper path in `commodore/common/player_items.s` and moved the prompt/selection contract onto that one source of truth.
- Filtered prompts now patch their advertised range dynamically, filtered pack overlays relabel sparse matches contiguously, and equipment overlays show contiguous letters for non-empty rows only.
- `item_wear` now excludes Flask of Oil from both the visible wearable set and the accepted filtered input path, so the overlay/parser contract matches the real equippable set.
- Resident/string-bank Huffman assets were regenerated after removing now-dead filtered-selection error strings and refreshing the subsystem test bank fixture to the current tree.
- Verification completed:
  - `java -jar ../../tools/kickass/KickAss.jar main.s -showmem -vicesymbols -o out/moria8.prg` — PASS (`72` asserts, `0` failed)
  - `bash commodore/c64/run_tests.sh` — PASS (`33` suites passed, `0` failed)

## Current Task
- [x] Confirm the live `BUG-DIG-SHIFT-D` command path and distinguish command-mapping failure from digging-tool / vein-resolution failure.
- [x] Decide the smallest safe fix shape for `Shift+D`, `+`, and bash/tunnel discoverability based on active runtime behavior and project docs.
- [x] Implement the chosen digging-command fix in shared input/help/runtime code with minimal behavior drift.
- [x] Add focused regression coverage for the reported dig path, including the wrong-command symptom and the corrected path.
- [x] Run the relevant C64/C128 regression gates and record the review outcome.

## `BUG-DIG-SHIFT-D` Design

### Problem Statement
- Active backlog entry: `BUG-DIG-SHIFT-D` in `commodore/BUILDPLAN.md`.
- User report says digging into a vein via `Shift+D` can yield `Nothing interesting happens.` even while carrying or wielding a shovel.
- The likely failure classes are:
  - command mapping sends `Shift+D` to the wrong command
  - help/UI advertises one binding while runtime uses another
  - digging-tool recognition or vein-resolution is broken after the command reaches `player_tunnel`

### Current Code Facts
- Live input mapping on both C64 and C128 currently binds:
  - `Shift+D` -> `CMD_BASH`
  - `+` -> `CMD_TUNNEL`
- `bash_command` reports wall/vein targets with the bash-side “nothing happens” path, which matches the reported symptom class.
- `player_tunnel` is the only runtime path that checks digging ability, digging tools, and vein treasure resolution.
- Historical docs for R2.5 explicitly describe tunneling as the `+` command, while the active backlog item is framed around `Shift+D`; this needs an explicit project-local decision, not guesswork.

### Fix Constraints
- Prefer the smallest user-correct fix.
- Do not silently break the existing bash feature.
- Keep the actual digging-tool and vein-resolution runtime intact unless the audit proves it is also broken.
- Add regression coverage before closing the bug.

### Review
- Chosen fix shape: keep the published bindings intact, but make the `Shift+D` bash path hand off to the tunneling runtime when the chosen target is tunnelable terrain.
- This preserves:
  - door bash
  - monster bash
  - explicit `+` tunnel
- It fixes the reported symptom because quartz/magma/wall/rubble targets now reach `player_tunnel` instead of stopping at bash's wall-side "nothing happens" response.
- User-visible follow-up:
  - help row updated to `SHIFT+D Bash/Dig`
- Verification completed:
  - `./commodore/c64/run_tests.sh bash` — PASS (`33` suites passed, `0` failed)
  - `make test128-fast` — PASS
  - `make test128-fast-smoke` — PASS

## Status Update
- The oversized Umoria-style interactive `look` rewrite has been backed out from gameplay code.
- The C64 main program fits again at `$080E-$CFE5`, and `commodore/c64/tests/test_effects.s` fits again at `$0825-$BF1C`.
- Current gameplay code is back on the compact directed scan path while the project decides whether to keep that VMS-style baseline or spend budget on selected richer `look` behavior later.
- Deferred note: closing the remaining VMS/Umoria parity gap for `look` will require significant engineering because the feature is behaviorally complex and the C64 memory budget is already tight.

## Current Task
- [x] Trace the C64 game-over / save-and-quit menu path and compare it to the recently fixed `GENERATING...` presentation bug.
- [x] Implement the smallest prompt-local clear fix in `game_over_prompt`.
- [x] Run the relevant regression gates for the shared screen/prompt change.
- [x] Get manual C64 confirmation that the `Reboot / Restart / Quit` menu now appears on a fully cleared screen.

## `BUG-GAMEOVER-CLEAR-C64` Design

### Problem Statement
- On C64, after save-and-quit or death reaches the `Reboot / Restart / Quit` menu, the prompt can appear without fully clearing the prior gameplay/death status rows.
- This is a prompt-presentation bug on a full-screen transition path.

### Current Code Facts
- `game_over_prompt` lives in `commodore/c64/main.s`.
- Before this fix shape, it prepared the menu on a still-visible screen:
  - `screen_clear`
  - centered prompt draw
  - wait for key
- There is no later writer in this path that should repaint the bottom status rows after the prompt is drawn.
- The recently fixed `BUG-GEN-CLEAR-C64` had the same visible symptom class: a full-screen transition was being prepared live on a visible C64 frame.

### Preferred Fix Shape
- Keep the change local to `game_over_prompt`.
- Blank the screen first, then clear and draw the centered menu, then unblank once the prompt is fully established.
- Do not broaden this into a shared screen-driver refactor unless the local fix fails in real play.

### Verification Status
- Implemented the prompt-local presentation fix in `commodore/c64/main.s`:
  - blank
  - clear
  - draw `Reboot / Restart / Quit`
  - unblank
- Automated verification completed:
  - `make test` — PASS
  - `make test128-fast` — PASS
- Manual C64 confirmation:
  - user reports the `Reboot / Restart / Quit` menu now clears correctly

## Current Task
- [x] Reproduce the C64 `GENERATING...` dirty-screen transition and note which rows/cells survive the clear.
- [x] Trace whether the residue comes from `generation_busy_begin`, the C64 `screen_clear` primitive, or a later transition draw path.
- [x] Implement the smallest safe C64 fix without perturbing the shared dungeon-generation flow.
- [x] Add focused regression coverage for the chosen clear contract.
- [x] Run the relevant C64/C128 regression gates before closing the bug.

## `BUG-GEN-CLEAR-C64` Design

### Problem Statement
- On C64, entering a dungeon can show the full-screen `GENERATING...` busy message over stale gameplay/title contents instead of a cleanly cleared screen.
- This is a UI bug in the visible generation transition, not a dungeon-generation correctness bug.
- The fix should preserve the existing shared generation flow and avoid introducing new generator-time UI calls inside unsafe inner loops.

### Current Code Facts
- Shared busy UI lives in `commodore/common/generation_busy.s`.
- `generation_busy_begin` currently:
  - unblanks the screen
  - switches to white text
  - calls `screen_clear`
  - draws centered `GENERATING...`
- Shared dungeon transition flow in `commodore/common/game_loop.s` calls:
  - `generation_busy_begin_if_dungeon_api`
  - overlay load / generation / spawn / visibility work
  - `generation_busy_end_if_dungeon_api`
  - `screen_clear` and the normal gameplay redraw tail
- The visible bug is therefore in the pre-generation busy-screen setup, not in the post-generation gameplay restore.
- Elsewhere in the codebase, several full-screen UI paths deliberately use row-by-row clearing via `screen_clear_row` instead of `screen_clear`.
- Existing project lessons already warn that full-screen clears are sensitive and that generation UI must stay at coarse safe boundaries.

### Root-Cause Hypotheses
- Most likely: `generation_busy_begin` exposes the busy screen too early by calling `screen_unblank` before the clear and centered text draw complete, so the user can briefly see residual pre-transition contents.
- Next most likely: even with corrected visibility sequencing, the C64 busy UI is using the wrong clear primitive for this path, and a row-by-row clear is more reliable for removing all visible residue before the centered message is drawn.
- Less likely: some later setup path is repainting stale cells after `generation_busy_begin` runs but before the user perceives the busy screen.
- Design rule: prove the residue source first, but bias toward the smallest fix at the busy-screen entry point unless reproduction shows a later writer.

### Preferred Fix Shape
- First fix the busy-screen sequencing in `commodore/common/generation_busy.s`:
  - keep the screen hidden while the busy UI sets color, clears, and draws `GENERATING...`
  - only unblank after the busy frame is fully established
- If C64 still shows residue after that, add a dedicated busy-screen full clear helper in `commodore/common/generation_busy.s`.
- On C64, have that helper clear all 25 rows via `screen_clear_row` before drawing `GENERATING...`.
- On C128, keep the current bulk `screen_clear` path unless reproduction shows the problem is shared.
- Keep the change local to the busy UI entry path:
  - do not alter `level_change_generate_current`
  - do not add extra UI calls inside generation phases
  - do not refactor the general screen driver unless the helper proves insufficient

### Why This Is Preferred
- It targets the exact user-visible bug surface.
- It fixes the most suspicious display-ordering bug before widening the clear strategy.
- It avoids touching shared generation sequencing, overlay ownership, and generator scratch safety.
- It matches existing repo practice for other sensitive full-screen UI clears.
- It keeps any extra cost limited to a transition screen that is already explicitly a blocking/busy UI.

### Verification Plan
1. Reproduce on C64 and identify whether the visible residue is consistent with `generation_busy_begin` unblanking too early.
2. Implement the local busy-screen sequencing fix and verify manually that `GENERATING...` appears only after the clear/draw work is complete.
3. If residue remains on C64, add the C64-only busy clear helper and re-verify manually.
3. Add focused unit coverage for the chosen contract:
   - preferred: extend `commodore/c64/tests/test_main_loop.s`, which already owns the busy-UI shims and dungeon-transition harness
   - assert the busy path establishes its presentation state before generation continues
   - if a dedicated helper is added, assert the C64 busy path uses that helper
4. Run relevant regression gates:
   - focused C64 test for the busy UI helper
   - `make test`
   - `make test128-fast` to prove the shared/common change did not drift on C128

### Verification Status
- Implemented the local busy-screen sequencing fix in `generation_busy_begin`:
  - blank
  - clear
  - draw `GENERATING...`
  - unblank
- Added focused C64 host coverage in `commodore/c64/tests/test_main_loop.s` and updated `commodore/c64/run_tests.sh` so the suite now enforces `main_loop` `15/15` instead of `13/13`.
- Automated verification completed:
  - `make test` — PASS
  - `make test128-fast` — PASS
- Manual C64 confirmation:
  - user reports the generation busy-screen transition looks correct in real play

### Open Question For Reproduction
- Whether the stale content is pure character residue, color-RAM residue, or a later repaint after the busy screen begins. That determines whether the helper needs only row clearing or an additional guard against a later writer.

### Consultant Review
- Consultant verdict: treat this as a `generation_busy.s` presentation bug first, not a dungeon-generation bug.
- Consultant-recommended order:
  - fix busy-screen visibility sequencing locally in `generation_busy_begin`
  - only if needed, fall back to a C64-only row-by-row clear for the busy UI
  - keep `level_change_generate_current` unchanged unless reproduction proves a later writer
  - prefer `commodore/c64/tests/test_main_loop.s` for focused regression coverage rather than creating a new test image

## Current Task
- [x] Lock the reduced directed `look` contract from local primary sources/runtime and record intentional feature deltas.
- [x] Write the `BUG-LOOK-HILITE` parity test matrix before implementation.
- [ ] Move directed `look` coverage into a host test image that still fits C64 test memory limits.
- [x] Reuse shared directed-input handling instead of keeping a bespoke `look` prompt reader.
- [x] Back out the oversized interactive `look` rewrite so the C64 main segment fits again.
- [ ] Decide whether to keep the compact VMS-style baseline or fund a larger parity push later.
- [ ] Add platform-owned target highlight/flash behavior for C64 and C128.
- [ ] Add C128 unit/smoke coverage for the shared `look` changes.
- [ ] Run full regression gates before asking for human playtesting.

## `BUG-LOOK-HILITE` Design And Verification Plan

### Problem Statement
- The current port's `look` command is not end-user equivalent to Umoria.
- Today it uses a straight-ray, single-result scan with no visible target cue.
- Umoria documents different behavior:
  - directional cone search
  - a creature on an object should describe both
  - monster memory is reachable from `look`
- Local VMS-Moria does not implement all-directions `look`; its `look` command is directed-only.
- Local VMS-Moria also keeps `look` materially smaller than Umoria:
  - straight-ray scan
  - non-interactive flow
  - no recall handoff
  - no per-target pause/highlight
- Project decision: drop the Umoria-only all-directions/null-direction feature and keep the rest of the `look` work scoped to directed `look`.
- Open decision after source review: whether Moria8 should keep chasing Umoria-only interactive `look` semantics, or pivot to the smaller VMS-style directed contract that better matches current C64 memory limits.

### Non-Negotiable Requirements
1. End-user directed `look` behavior must match the reduced project contract, with all-directions `look` intentionally excluded.
2. Highlight/flash presentation may be adapted for C64/C128 hardware constraints.
3. No regressions in any other behavior.
4. Everything must be unit-testable before human testing.

### Current Code Facts
- Shared `look` implementation lives in `commodore/common/player_move.s` as `do_look`.
- `do_look` currently depends on `get_direction_target` from `commodore/common/dungeon_features.s`.
- `get_direction_target` still uses the generic `Direction?` prompt rather than VMS-Moria's `Look which direction?`.
- `do_look` currently prints one description and exits.
- There is no current `look`-specific target cue.
- Cross-platform flash primitives already exist:
  - `commodore/c64/screen.s` → `screen_flash_at`
  - `commodore/c128/screen_vdc.s` → `screen_flash_at`
- Existing regression coverage only proves remembered dark tiles do not get revealed by `look`.
- Existing monster recall UI already exists and should be reused rather than reimplemented.
- `FEATURES.md` records the intentional version split: Umoria has all-directions `look`; VMS-Moria and Moria8 do not.

### Architecture Decision
- Keep generic adjacent-action direction handling unchanged.
- Do not treat Umoria-only interactive `look` behavior as settled until the project chooses between Umoria-style and VMS-style directed `look`.
- If the project stays on Umoria-style directed `look`, keep highlight platform-owned and split target selection from target presentation / recall handoff.
- If the project pivots to VMS-style directed `look`, prefer the simpler straight-ray/message path and delete the interactive `look` framework instead of optimizing it piecemeal.

### Behavior Contract To Lock Before Coding
- Shared facts locked from local upstream source trees `~/Projects/thirdparty/umoria` and `~/Projects/thirdparty/vms-moria`:
  - `look` is a free move.
  - blindness check happens before prompting.
  - directed empty look ends with `You see nothing of interest in that direction.`
- Umoria-only directed `look` behavior currently implemented in `~/Projects/thirdparty/umoria/src/dungeon_los.cpp`:
  - panel-bounded cone search
  - interactive, multi-target flow
  - player tile inspected first
  - optional recall handoff
  - layered monster/object/feature messaging with pause/abort between shown targets
  - directed end-of-scan prints `That's all you see in that direction.`
- VMS-Moria directed `look` behavior currently implemented in `~/Projects/thirdparty/vms-moria/source/include/moria.inc`:
  - straight-ray scan along one direction
  - no per-target pause
  - no recall prompt/return flow
  - repeated `msg_print` output as interesting tiles are encountered
  - stops on blocked tile or sight limit
- Intentionally excluded from Moria8 already:
  - null direction `5`
  - `.` all-directions `look`
  - all-directions completion/empty messages
- Still awaiting explicit project choice:
  - Umoria-only interactive cone/reveal/recall behavior beyond the shared directed `look` baseline

### Known Port-vs-Upstream Gaps
- Current port `do_look` is single-result, straight-ray, and non-interactive.
- Local VMS-Moria keeps scanning down the ray and can emit multiple messages for successive interesting tiles; current Moria8 returns after the first interesting result.
- Local VMS-Moria can describe multiple things on one tile in sequence; current Moria8 picks a single highest-priority result and exits.
- Current Moria8 reports generic doors, stairs, traps, rubble, and wall hits; local VMS-Moria `look` is narrower and mainly reports monsters, items, and rock/mineral features.
- Local VMS-Moria explicitly prints the blindness failure message; current Moria8 does not have a `do_look`-local blind-message branch.
- Current port reports walls directly, which does not match upstream default seam behavior.
- Current port has no look-time recall prompt or return-to-look flow.
- Current port has no per-target cursor/highlight step.

### Candidate Selection Strategy
- Preferred implementation shape:
  - reproduce the upstream two-pass `lookSee` / `lookRay` behavior closely enough that target order and prompts match the observed Umoria flow
  - preserve panel bounds and pause-per-target interaction
- Important rule:
  - implementation does not define behavior
  - if a simpler scan cannot reproduce upstream target order and interaction semantics, replace it with a closer source-matched traversal

### Shared-Code Safety Rules
- Do not add null-direction/all-directions `look`.
- Do not modify global `rest` semantics.
- Reuse shared directed-input handling, but do not force `look` through `get_direction_target` if it still needs direction identity rather than an adjacent tile.
- Do not refactor the main renderer as part of this bug.
- Do not touch player-facing strings for memory relief.
- Do not merge unrelated input or recall cleanup into this task.

### Step-By-Step Implementation Plan
1. Verify the reduced directed-only `look` contract against local Umoria and VMS-Moria sources.
2. Write targeted parity tests that fail under the current implementation.
3. Reuse directed input handling where possible; only add `look`-specific input code if directed `look` still needs it.
4. Introduce a shared `look` state record:
   - active direction
   - current pass (`objects` / `rocks`)
   - current descriptive prefix (`You see`, `It is on`, `It is in`)
   - current query/abort key
   - current target coordinates / target kind
5. Replace the inline straight-ray logic in `do_look` with an interactive target iterator.
6. Implement upstream-style pause-per-target behavior and `ESCAPE` abort.
7. Implement the Umoria-correct text flow:
   - monster first with `[(r)ecall]`
   - item second if present
   - feature third if present / enabled
8. Hook look-time monster recall into the existing recall UI path, then restore gameplay view and continue the active look flow using the key returned from recall dismissal.
9. Add a shared highlight call that moves attention to the current target tile before waiting for input.
10. Adapt the C64/C128 flash primitive behavior if the existing `*` flash is not the best platform-appropriate representation.
11. Run full regression gates and only then hand off for manual verification.

### Test Matrix

#### Input Contract
- [ ] `look` accepts all 8 directions.
- [ ] Invalid `look` direction input exits cleanly without consuming a turn.

#### Visibility Contract
- [ ] `look` does not describe remembered-but-not-currently-visible monsters.
- [ ] `look` does not describe remembered-but-not-currently-visible items.
- [ ] `look` respects the 20-tile range limit.
- [ ] `look` rejects tiles outside the selected directional cone.

#### Panel / Screen Contract
- [x] Upstream is panel-bounded.
- [ ] Visible off-panel targets do not participate in `look`.
- [ ] Selected target coordinates are converted to correct screen row/column for both C64 and C128.
- [ ] `look` highlights each shown target before waiting for input.

#### Target Priority Contract
- [ ] Target visitation order matches the chosen directed traversal for representative straight and diagonal cases.
- [ ] Monsters are shown before objects/features on the same tile.
- [ ] Objects/features are only shown when their lighting/mark rules match upstream behavior.
- [ ] Town behavior is covered in all directions, not just dungeon rooms/corridors.

#### Description Contract
- [ ] Feature-only tiles print the correct feature description.
- [ ] Monster-only tiles print the correct monster description.
- [ ] Item-only tiles print the correct item description.
- [ ] Monster-on-object tiles produce the correct upstream sequence:
  - monster line first
  - object line next using `It is on ...`
- [ ] Object-in-wall / seam cases produce the correct upstream `It is in ...` / wall text sequence.
- [ ] Directed empty look prints `You see nothing of interest in that direction.`
- [ ] Directed end-of-scan prints `That's all you see in that direction.`

#### Recall Contract
- [ ] Monster prompt includes `[(r)ecall]`.
- [ ] Pressing `r` from look enters recall for the shown monster.
- [ ] Recall returns cleanly to the active look flow.
- [ ] `ESCAPE` from recall aborts the whole look, matching upstream returned-key behavior.
- [ ] Existing non-`look` recall command behavior does not regress.

#### Highlight Contract
- [ ] Highlight/flash marks the same target that the text description selected.
- [ ] Flash restores the underlying tile cleanly.
- [ ] C64 flash path does not corrupt screen/color RAM state.
- [ ] C128 flash path does not corrupt VDC state or IRQ-sensitive screen state.

#### Regression Contract
- [ ] Existing `look` remembered-dark regression still passes.
- [ ] Existing input mapping tests still pass.
- [ ] Existing recall UI tests still pass.
- [ ] Existing C64 gameplay regression suites still pass.
- [ ] Existing C128 fast unit suite still passes.
- [ ] Existing C128 smoke coverage still passes.

### Current Size Findings
- Dropping all-directions `look` saved only `0xD9` bytes in the C64 main image.
- Reusing the shared directed-input seam saved only about 12 more bytes.
- The remaining main-image overage is concentrated in:
  - traversal setup / coordinate transform
  - `look_process_tile`
  - the custom `look` row-0 print/pause helpers
- Reverting to the compact directed scan path immediately restored the C64 layout:
  - main program fits again at `$080E-$CFE5`
  - `test_effects` fits again at `$0825-$BF1C`
- `commodore/c64/tests/test_look.s` is structurally too large in its current standalone form and should not be revived as-is.
- `commodore/c64/tests/test_effects.s` also tips over its own body-size assert with the current `player_move.s` import, so the next host candidate should be a lighter existing image such as `test_main_loop.s` or a purpose-built minimal harness.

### Verification Gates Before Human Testing
1. New C64 unit tests fail on the current behavior and pass on the new behavior.
2. Existing C64 test suite remains green.
3. New C128 input/unit coverage passes.
4. `make test128-fast` passes.
5. Relevant C128 smoke path passes.
6. Only after those gates are green should manual gameplay verification begin.

### Consultant Review
- Consultant verdict: architecture is sound.
- Consultant recommendations adopted:
  - keep `look` separate from generic direction helpers
  - keep highlight platform-owned
  - use test-first parity work
  - treat cone semantics, dual-description behavior, and recall interaction as parity obligations
  - do not let a clean implementation redefine the visible game behavior
- Updated consultant conclusion after the memory-map recheck:
  - the C64-safe path is to pivot toward the smaller VMS-style directed contract
  - the interactive Umoria-style machinery is the bulk of the overage, not the input seam

## Current Task
- [x] Reproduce the C128 dungeon-entry JAM from the user's `make clean128; make disk128` path.
- [x] Trace the reported `$E18C` crash against the C128 tier/overlay ownership contract.
- [x] Restore the dungeon-generation overlay before post-generation special-room helpers run.
- [x] Add C128 regression coverage for the post-tier overlay restore path.
- [x] Audit the current XP/level-up implementation and history context for `BUG-XP-PACE`.
- [x] Compare the current behavior against original Umoria source/runtime expectations.
- [x] Get a consultant second opinion on the likely remaining pace drift.
- [x] Write a concrete `BUG-XP-PACE` design with recommended audit/fix order.
- [x] Implement the threshold / level-up parity fix and prove it with runtime coverage.

## Plan
- [x] Rebuild the same C128 disk image path the user is testing.
- [x] Reconcile the reported backtrace with `level_change_generate_current`, `tier_check_transition`, and `$E000` overlay ownership.
- [x] Implement the minimal root-cause fix in the shared descent path.
- [x] Prove the fix with both C128 unit coverage and real D64 boot/descent smoke coverage.
- [x] Inspect `combat_award_xp`, `combat_compute_level_threshold`, and `combat_check_levelup`.
- [x] Re-read the prior fractional-XP history entry so the new design does not duplicate solved work.
- [x] Verify original Umoria level-threshold / expfact / level-up-halving behavior from primary source.
- [x] Identify which remaining drift hypotheses are most plausible and cheapest to prove.
- [x] Write the recommended design and consultant-backed next steps here.

## Working Read

### Current code facts
- `commodore/common/combat.s`
  - `combat_award_xp` still uses `(cr_xp * cr_level) / player_level`.
  - Fractional remainders are accumulated in `PL_XP_FRAC_LO/HI`.
  - `combat_compute_level_threshold` multiplies the threshold table by `PL_EXPFACT / 100`.
  - `combat_check_levelup` compares only the whole 16-bit threshold against the 24-bit whole XP and then applies the original-style one-level-per-kill excess-halving behavior.
- `commodore/common/tables.s`
  - XP thresholds are still a 16-bit table with `65535` sentinels for level 30+.
- `commodore/common/player_create.s`
  - `PL_EXPFACT` is still stored as `race_xp% + class_xp%`.

### Prior history that matters
- `commodore/BUILDPLAN_HISTORY.md` already records MC2.2 fractional XP accumulation as complete.
- That means `BUG-XP-PACE` should be treated as a fresh audit of remaining drift, not a rerun of the old min-1 / truncation bug.

## Consultant Second Opinion

- The consultant agreed that the strongest remaining suspects are on the threshold/data side, not the basic kill-award formula.
- Recommended audit order:
  1. prove a small regression matrix first
  2. verify monster XP/level data and the full threshold curve against original source
  3. re-check the level-up retention contract
  4. only then change award/threshold code
- Important reminder:
  - if the XP math matches original but leveling still feels fast in play, the bug may really be content pacing (monster distribution / deep spawns), not XP arithmetic

## `BUG-XP-PACE` Design

### Problem Statement
- Playtesting suggests characters gain levels faster than stock Umoria.
- A prior fix already restored hidden fractional XP accumulation, so the remaining drift is likely elsewhere.

### Proven Current State
1. **Kill XP formula matches the expected Umoria shape**
   - `combat_award_xp` uses `(cr_xp * cr_level) / player_level`.
   - It also carries fractional remainders in `PL_XP_FRAC_LO/HI`.
2. **Experience factor shape also matches Umoria structurally**
   - `PL_EXPFACT` is built as race XP factor + class XP factor.
   - Original Umoria does the same additive composition.
3. **One major parity risk is already visible in current code**
   - `xp_level_lo/hi` in `commodore/common/tables.s` saturates to `65535` for level 29+.
   - Original Umoria continues rising to 75,000 / 100,000 / 150,000 / 200,000 / 300,000 / 400,000 / 500,000 / 750,000 / 1,500,000 / 2,500,000 / 5,000,000 / 10,000,000.
   - So late-game advancement is definitely too fast today, even before any deeper audit.

### Likely Root-Cause Buckets
1. **Threshold truncation**
   - Highest-confidence bug.
   - The current 16-bit threshold representation cannot encode the original late-game curve.
2. **Unverified threshold parity before level 29**
   - The low/mid table entries look source-matched, but they should still be proven as a full curve instead of assumed from comments.
3. **Level-up progression contract**
   - Current code hard-caps to one level-up per kill, then halves retained excess.
   - Original Umoria loops while XP still exceeds the next threshold, with halving applied during each gain-level step.
   - This is a real parity difference, though it would usually make the port level more slowly on very large awards, not faster.
4. **Content pacing masquerading as XP pacing**
   - If the arithmetic/threshold audit passes for the levels users are actually reaching, the remaining culprit is likely monster distribution:
     - deeper/higher-XP monsters appearing too early
     - roster/tier/deep-fallback behavior producing richer XP than stock Umoria

### Recommended Fix Shape
1. **Split the work into Phase A and Phase B**
   - Phase A:
     - audit and repair XP math/threshold parity
   - Phase B:
     - only if needed, audit gameplay/content pacing separately
2. **Phase A implementation target**
   - Replace the current 16-bit threshold representation with a 24-bit threshold table or equivalent 24-bit computation path.
   - Update `combat_compute_level_threshold` to produce a real 24-bit adjusted threshold.
   - Update `combat_check_levelup` to compare full 24-bit XP against the full adjusted threshold.
3. **Phase A scope discipline**
   - Do not change monster spawn/tier logic in the same patch.
   - Do not change the basic kill-XP formula unless original-source verification disproves it.
   - Treat multi-level-per-award parity as a separate sub-decision after the threshold audit:
     - if strict Umoria fidelity is the goal, the current one-level cap should probably be revisited
     - if practical gameplay parity is already restored by threshold repair, that follow-up can stay separate

### Required Proof Before Code Change
1. Verify original Umoria primary sources for:
   - full base XP threshold curve
   - additive race+class experience factor contract
   - kill XP formula
   - multi-level gain behavior and excess-halving semantics
2. Add focused regression coverage for:
   - low-level threshold gate
   - non-100 `PL_EXPFACT` threshold scaling
   - level-29+ threshold values beyond 65535
   - retained-excess behavior after level-up
3. Add one explicit “late-game threshold” test that would fail under the current 16-bit sentinel table.

### Decision Rule After Phase A
1. If the corrected threshold/multi-level parity brings leveling in line with stock Umoria:
   - close `BUG-XP-PACE`
2. If play still feels fast after the arithmetic audit:
   - re-scope the remaining work as content pacing, likely around monster-level / monster-XP distribution rather than XP math itself

### Recommended Next Step
- Start with a narrow source-and-test audit focused on threshold representation.
- That is the highest-confidence fix, the lowest-risk change, and the one most clearly proven wrong by the current code.

## Review

### `AUDIT-P12-CA03` Review

- Completed.
- Added shared helper `player_update_hunger_state` in `commodore/common/turn.s` and switched both the turn-time hunger tick and `item_eat` in `commodore/common/player_items.s` to use it.
- Kept starvation damage turn-owned; the shared helper only classifies `FULL/HUNGRY/WEAK/FAINT` from the current food counter.
- Added focused runtime coverage in `commodore/c64/tests/test_item.s` to prove eating from low food immediately restores `zp_hunger_state` to `HUNGER_FULL`.
- While verifying, `commodore/c64/tests/test_render.s` exposed a separate harness defect: it compared the full byte read from C64 color RAM even though only the low nibble is stable. Fixed the test by masking with `$0f` and removed the old render-specific retry from `commodore/c64/run_tests.sh` so future regressions fail directly.
- Verification:
  - direct `test_render.s` loop: `6/6` clean runs
  - `bash commodore/c64/run_tests.sh`: `33 passed, 0 failed`
  - `make test128-fast`: `PASS`

### `AUDIT-P13-CA04` Review

- Completed.
- Added `commodore/common/ui_restore.s` as the shared seam for gameplay-view restoration after modal UI flows.
- Centralized the two real restore behaviors:
  - `ui_view_restore_modal_overlay` for read-only overlay dismissal
  - `ui_view_redraw_gameplay_view` for full-screen wizard/menu returns
- Switched the matching call sites in `commodore/common/player_items.s`, `commodore/common/player_magic.s`, `commodore/common/game_loop_helpers.s`, `commodore/common/wizard.s`, and `commodore/common/ui_wizard.s` to those helpers.
- Verification:
  - `bash commodore/c64/run_tests.sh`: `33 passed, 0 failed`
  - `make test128-fast`: `PASS`

### `AUDIT-P14-CA06` Review

- Completed.
- Replaced the per-save `msg_hist_idx * SCREEN_COLS` offset recomputation in `commodore/common/ui_messages.s` with a rolling destination pointer (`msg_hist_ptr_lo/hi`).
- Kept the existing ring-buffer contract:
  - `msg_hist_idx` still wraps mod 8
  - the history buffer still stores null-terminated screen-code strings in fixed-size slots
  - C128 still keeps the history copy atomic under `SEI`
- Added a focused regression in `commodore/c64/tests/test_ui_views.s` that drives `msg_save_history` directly, proves the ring wraps after eight writes, and proves the ninth message overwrites slot 0 while later slots retain their expected contents.
- Updated the `ui_views` suite expectation in `commodore/c64/run_tests.sh` from `12` to `13`.
- Verification:
  - `bash commodore/c64/run_tests.sh`: `33 passed, 0 failed`
  - `make test128-fast`: `PASS`

### `AUDIT-P15-CA05` Review

- Completed.
- Replaced the potion and scroll compare/jump ladders in `commodore/common/player_items.s` with compact indexed dispatch tables plus generic fallback entries for the sparse item-ID holes.
- Kept the existing effect handlers and user-visible behavior intact; the refactor only changed how the handler target is selected.
- Fixed two follow-up issues during verification:
  - converted overlong forward branches into local trampolines plus absolute `jmp`
  - corrected the scroll-table hole count so IDs `32-38` map to the intended handlers
- Verification:
  - `commodore/c64/tests/test_item.s`: `47/47` passed
  - `bash commodore/c64/run_tests.sh`: `33 passed, 0 failed`
  - `make test128-fast`: `PASS`

### `AUDIT-P16-CA08` Review

- Completed.
- Added `fi_add_clear_plain_meta` in `commodore/common/item.s` to clear `fi_add_qty_hi`, `fi_add_p1`, `fi_add_flags`, and `fi_add_ego` for fresh plain generated-item setup.
- Retargeted the matching plain-item / gold producers in:
  - `commodore/common/item.s`
  - `commodore/common/wizard.s`
  - `commodore/common/ui_wizard.s`
  - `commodore/common/special_rooms.s`
- This also hardens the nest-gold path in `special_rooms.s`, which previously cleared only part of the metadata set and could inherit stale `fi_add_ego` / `fi_add_qty_hi`.
- Verification:
  - `bash commodore/c64/run_tests.sh`: `33 passed, 0 failed`
  - `make test128-fast`: `PASS`

### `AUDIT-P17-CA07` Review

- Completed.
- Added `ui_clear_full_screen_safe` in `commodore/common/ui_help_clear.s` and made the platform split explicit:
  - C64 keeps the known-safe row-by-row full-screen clear
  - C128 uses `screen_clear` for the full-screen modal/helper path
- The existing `ui_help_clear_all` callers now inherit that split automatically, so help, inventory, character, store, wizard, recall, and home screens stop paying the full 25-row clear cost on C128.
- Replaced the remaining direct full-screen row loops in `commodore/common/player_create.s` and `commodore/common/score.s` with the same shared helper.
- Measured layout impact on the live tree:
  - C64 main image margin improved from `141` to `191` bytes below `$C000`
  - C64 staged banked source margin improved from `106` to `156` bytes below `$D000`
  - C128 staged/program image margin improved from `180` to `208` bytes below `$E000`
- Verification:
  - `bash commodore/c64/run_tests.sh`: `33 passed, 0 failed`
  - `make test128-fast`: `PASS`

### `AUDIT-P18-CA09` Review

- Completed.
- Added `C128KernalJumpTableWrapper` in `commodore/c128/main.s` and moved the ten simple KERNAL jump-table wrappers (`w_readst` through `w_chrout`) to that shared scaffold.
- Kept `w_load` and `kernal_load_safe` explicit because they still carry load-specific diagnostics / side effects that do not fit the simple wrapper template cleanly.
- Measured layout impact on the live tree:
  - C128 staged/program image margin improved from `208` to `271` bytes below `$E000`
- Verification:
  - `make -B -C commodore/c128 build128`: passed, `197` asserts, `0` failed
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`: `PASS`

### `AUDIT-P19-CA10` Review

- Completed.
- Added `commodore/common/input_contract.s` for the shared input command IDs and direction tables used by both platforms.
- Added `commodore/common/input_run_cancel.s` for the shared debounced run-cancel state machine.
- Retargeted `commodore/c64/input.s` and `commodore/c128/input128.s` to those shared contract files while keeping the hardware scan / PETSCII decode logic platform-local.
- Verification:
  - `bash commodore/c64/run_tests.sh`: `33 passed, 0 failed`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`: `PASS`

### C128 dungeon-entry JAM follow-up

#### Root Cause
- `level_change_generate_current` called `tier_check_transition` and then immediately entered `monster_spawn_level` / `item_spawn_level`.
- On C128, `tier_load` reuses `$E000` for tier payloads, invalidating the dungeon-generation overlay that still owned `find_special_room`, `spawn_special_room_monsters`, and `spawn_nest_gold`.
- So the first dungeon descent could jump through valid special-room trampolines into whatever tier bytes now occupied `$E000`, matching the user's `$E18C` JAM report.

#### Fix
- Added a C128-only `c128_restore_generation_overlay` step in `commodore/common/game_loop.s` immediately after `tier_check_transition`.
- That helper reloads `OVL_DUNGEON_GEN` when tier activation has displaced the overlay and then reasserts the C128 runtime guards before monster/item spawning continues.
- Strengthened `commodore/c128/tests/test_main_loop128.s` so the C128 main-loop test now proves:
  - the overlay is loaded once for generation
  - tier activation invalidates it
  - `level_change_generate_current` loads it a second time before monster spawning
  - monster spawning sees `OVL_DUNGEON_GEN` active again

#### Validation
- `make -B -C commodore/c128 build128`: passed, `197` asserts, `0` failed
- `make test128-fast`: passed
- `TEST_FILTER='boot_tier_transition_smoke' ./commodore/c128/run_tests128.sh`: passed
- `TEST_FILTER='real_boot_crash_harness' ./commodore/c128/run_tests128.sh`: passed

### Implemented
- Replaced the late-game `65535` threshold saturation with source-matched current-level transition thresholds.
- Reworked `combat_compute_level_threshold` to produce a 24-bit adjusted threshold without blowing the C64 main segment past `$C000`.
- Reworked `combat_check_levelup` to loop like original Umoria instead of hard-capping to one gain per award.
- Updated C64 and C128 wizard gain-level helpers to compare and seed the full 24-bit threshold.
- Added focused C64 combat regressions for:
  - level-30 threshold at `100%`
  - level-30 threshold at `150%`
  - repeated level gains from one award
  - clean fractional-XP carry behavior

### Validation
- Direct C64 KickAssembler build with local jar override: passed, `program_end` back below `$C000`
- Direct C128 KickAssembler build with local jar override: passed, `197` asserts, `0` failed
- `./commodore/c64/run_tests.sh`: `33` passed, `0` failed
- `make test128-fast`: passed

### Result
- `BUG-XP-PACE` is fixed and can be closed from the active build plan.

## Current Task
- [x] Review the current C128 residency / I/O-hole contract across `commodore/c128/main.s`, `commodore/c128/memory128.s`, `commodore/c128/run_tests128.sh`, and the C128 architecture docs.
- [x] Define the scope boundary for `AUDIT-IO-C128` so it audits callable execution surfaces rather than trying to classify every C128 symbol.
- [x] Get consultant review on the draft audit boundary, deliverables, and sequencing.
- [x] Fold consultant corrections into the final plan.
- [x] Record the final `AUDIT-IO-C128` design here before implementation starts.

## `AUDIT-IO-C128` Design

### Goal
- Execute a full C128 callable-code audit that proves every important runtime entrypoint executes from a valid residency domain instead of silently drifting into the `$D000-$DFFF` I/O hole or the wrong bank.
- Turn the current hand-maintained placement guards into one explicit, reviewable callable-surface contract that future C128 layout work can keep green.
- Keep this phase focused on auditability and guard coverage, not on refactoring the trampoline/platform architecture.

### Scope Boundary
- In scope:
  - all C128 callable entrypoints whose correctness depends on residency, banking, overlay ownership, or copied/runtime-loaded placement
  - the compile-time and runner-time guard model that proves those entrypoints stay legal
  - the runtime verification paths that catch I/O-hole execution during representative boot / overlay / town / generation flows
- Callable surfaces to inventory explicitly:
  - resident Bank 0 gameplay entrypoints that must stay below `$D000`
  - low-runtime Bank 0 routines loaded to `$1000-$3FFF`
  - overlay entrypoints that must execute only from `$E000-$EFFF`
  - reloadable banked payload entrypoints that must execute only from `$F000-$FFFA`
  - trampolines / common-RAM bridges that are allowed to call across those regions
  - loader entrypoints whose PRG header, destination bank, and callsite execution bank form part of the runtime contract
- Out of scope:
  - a general whole-program `jsr` / `jmp` graph extractor
  - refactoring shared gameplay code behind `REF-HAL`
  - macro-generating trampoline boilerplate under `REF-C128-TRAMP`
  - non-callable strings/data unless their placement is part of a callable path contract

### Why This Boundary
- The live regressions in this repo came from cross-region callable paths:
  - trampolines below `$D000` calling callees that had drifted into the I/O hole
  - low-RAM runtime code being loaded into the wrong bank for the callsite
  - banked payload recopies sourcing from bytes later clobbered by overlay loads
- A symbol-exhaustive audit would be expensive, noisy, and hard to maintain.
- A curated callable-surface contract is narrower, reviewable, and directly tied to the failure modes the project has already paid for.

### Deliverables
- One authoritative C128 callable-surface inventory, grouped by residency domain:
  - resident `< $D000`
  - low-runtime Bank 0
  - overlay `$E000-$EFFF`
  - reloadable banked `$F000-$FFFA`
  - trampolines / bridges / loaders
- One explicit allowed-residency contract for each inventoried entrypoint:
  - `below_io_hole`
  - `overlay_window`
  - `banked_window`
  - `runtime_low_bank0`
  - `bridge_only` / `trampoline`
- One source-of-truth guard definition that can drive both:
  - compile-time `.assert` coverage
  - runner-time symbol-placement checks
- Additional guards for paths that currently prove only the trampoline and not the callee.
- A short audit note in the Commodore docs recording:
  - what was inventoried
  - which symbols were newly guarded
  - which paths still rely on runtime smoke coverage rather than static placement alone

### Guard Model Gaps To Close
- The current runner parses placement asserts only from `commodore/c128/main.s`; that is workable today but brittle if contracts move into shared files or helper includes.
- The current model is symbol-placement heavy but contract-light:
  - it proves many labels are out of the I/O hole
  - it does not yet express one normalized residency class for every audited callable surface
- The current runner has hand-picked `must_have_asserts` and grouped symbol lists; those are useful, but they can drift separately from the actual callable inventory.
- Some live guards still protect only one side of a call path:
  - trampoline placement is asserted
  - callee placement or runtime-load residency may still rely on scattered one-off checks
- The five-point runtime-loaded-code checklist is documented, but not yet represented as one auditable artifact for low-runtime and copied/banked paths:
  - symbol address
  - PRG header
  - load destination bank
  - execution bank
  - source-span safety

### Implementation Shape To Prefer
- Prefer a curated manifest or macro-backed contract list over heuristic source scraping.
- Keep the contract close to the C128 runtime layout source so a reviewer can inspect symbol, residency intent, and guard together.
- Reuse the existing runner philosophy:
  - source declares the rule
  - runner proves the emitted symbols still satisfy it
- Add narrow runtime smokes only where static placement cannot prove the live execution context by itself.
- Avoid trying to infer legality from “low address” alone; low-runtime and bridge code need explicit bank/execution ownership in the inventory.

### Verification Strategy
1. Rebuild the exact C128 target and read the emitted memory map / `.print` output.
2. Verify the audited symbol set against `main.sym` / `out/main.vs`.
3. Verify runtime-loaded paths against the five-point checklist:
   - symbol address
   - PRG header
   - load bank
   - execution bank
   - source-span safety
4. Extend the runner so every audited contract is enforced from one inventory, not partly from ad hoc symbol groups.
5. Keep or add runtime I/O-hole tripwire smokes for representative flows where live execution matters:
   - boot to town
   - overlay transitions
   - generation / special-room / ego-item paths
   - low-runtime callsites
6. Before closing implementation, run:
   - `make -B -C commodore/c128 build128`
   - `make test128-fast`
   - `make test128-fast-smoke`
   - `make test128`

### Sequencing Relative To Other Open Work
- `AUDIT-IO-C128` should happen before `REF-C128-TRAMP`.
- Reason:
  - the audit needs the current callable surface pinned down first
  - macro-generating trampolines before that would hide the surface area while the rules are still being defined
- `AUDIT-IO-C128` can proceed before `REF-HAL`, but it should not expand into doing `REF-HAL`.
- Reason:
  - `REF-HAL` is a structural cleanup of shared platform hooks
  - this audit is a safety/specification pass on the existing callable surface
  - the resulting inventory should become an input to `REF-HAL`, not a blocker waiting on it
- If `REF-HAL` later moves or consolidates entrypoints, the `AUDIT-IO-C128` inventory should be updated as the acceptance gate for that refactor.

### Success Criteria
- Every inventoried C128 callable surface has one declared residency contract.
- The compile-time guards and the runner read from the same logical inventory.
- No audited callable path can regress into `$D000-$DFFF` without either a failed `.assert`, a failed runner guard, or a failed runtime smoke.
- The final design remains small enough that future C128 work will maintain it instead of bypassing it.

### Review
- Completed.
- Consultant review agreed that the audit should inventory callable execution surfaces, not every emitted symbol in the C128 build.
- The main correction was to make the deliverable one authoritative residency-contract inventory that can feed both compile-time asserts and runner checks, instead of adding more hand-maintained symbol lists in parallel.
- The review also confirmed the right sequencing:
  - do `AUDIT-IO-C128` before `REF-C128-TRAMP`
  - do not block on `REF-HAL`, but keep this audit narrowly scoped so its inventory can become an input to `REF-HAL` later
- Final design choice:
  - keep the audit focused on safety/specification of the current callable surface
  - leave broader trampoline/platform refactors explicitly out of scope for this phase

### Implementation Review
- Completed.
- Added `commodore/c128/io_contracts.s` as the source-of-truth callable residency manifest for:
  - resident `< $D000` entrypoints
  - runtime-low Bank 0 entrypoints
  - startup / town / death / UI / dungeon overlay entrypoints
  - reloadable banked-payload entrypoints
  - out-of-I/O-hole call surfaces that may legally live low or banked
- `commodore/c128/main.s` now emits compile-time `AUDIT-IO-C128` placement asserts from that manifest instead of maintaining a long hand-written callable assert list inline.
- `commodore/c128/run_tests128.sh` now parses `io_contracts.s` directly, verifies the emitted symbol placement against the declared residency class, and also checks that `out/runtime.low.prg` still carries the `$1000` load header.
- The new audit inventory also closed real callee-side gaps that were previously only protected at the trampoline side:
  - overlay callees such as `player_create`, `store_enter`, `score_death_screen`, `level_generate`, and the special-room helpers
  - runtime-low callees such as `viewport_update`, `render_viewport_scroll_delta`, `render_local_area`, and `monster_get_threat_color`
  - banked/out-of-hole callees such as `player_tunnel`, `player_cast_spell`, `player_pray`, and `spell_list_display`
- Live verification:
  - `make -B -C commodore/c128 build128` → `230` asserts, `0` failed
  - `TEST_FILTER='c128_artifact_budget|c128_symbol_placement' TEST_FAIL_FAST=1 ./run_tests128.sh` → `2 passed, 0 failed`
  - tester: `make test128-fast` → passed
  - tester: `make test128-fast-smoke` → passed
  - tester: sandboxed / parallel `make test128` hit VICE `Segmentation fault: 11` in `run_test_internal_worker.sh` while launching unit workers
  - isolated repro:
    - sandboxed `TEST_FILTER='minimal128' TEST_FAIL_FAST=1 TEST_JOBS=1 ./run_tests128.sh` reproduces the launch failure
    - outside the sandbox, the same `minimal128` authoritative path passes
    - outside the sandbox, `TEST_FILTER='memory128|main_loop128' TEST_FAIL_FAST=1 TEST_JOBS=1 ./run_tests128.sh` passes
  - authoritative closure:
    - tester: `TEST_JOBS=1 ./run_tests128.sh` outside the sandbox → `=== Results: 41 passed, 0 failed (of 41 suites) ===`

## Current Task
- [x] Inspect the live help command path, packed help data layout, and current C64/C128 test coverage.
- [x] Compare the port's current `?` help behavior against local VMS-Moria and Umoria help behavior.
- [x] Draft the bounded `BUG-HELP-PAGING` design and verification plan.
- [x] Get consultant review on the design and fold feedback into the final phase split and risk list.
- [x] Record the final planning scope here before any implementation starts.

## `BUG-HELP-PAGING` Design

### Goal
- Extend the current Commodore `?` help screen so it can paginate cleanly without regressing the existing fast modal-help flow.
- Preserve the current direct in-game quick-reference intent for `?`, but stop treating one 23-line screen as the hard maximum.
- Keep the design compatible with the existing C64 main-image budget and the C128 `OVL.UI` overlay contract.

### Upstream Findings
- Local VMS-Moria keeps `?` as a one-page quick reference and uses separate `h` / `moria_help` flows for deeper topic help.
- Local Umoria routes `?` to a paged text-help file viewer that shows 23 lines at a time and advances on keypress.
- The current Moria8 `?` behavior is closer in spirit to the VMS quick-reference panel than to Umoria's file-driven help browser.
- Therefore `BUG-HELP-PAGING` should be treated as "multi-page quick reference inside the current modal help UI," not as a requirement to recreate Umoria's disk-backed general help subsystem.

### Current Port Findings
- `cmd_show_help_view` in `commodore/common/game_loop_helpers.s` enters the help overlay, waits for a dismiss key, and restores gameplay view.
- `ui_help_display` in `commodore/common/ui_help.s` renders exactly one fixed page:
  - top frame + title
  - 23 packed content rows from `help_lines`
  - bottom frame + `Press any key`
- The help content is a single sequential packed table in `commodore/common/ui_help_data.s`.
- On C64, help data lives in the main image and `help_lines_src_lo/hi` points at it during startup.
- On C128, the same help data is imported into `OVL.UI` and explicitly asserted to stay inside `$E000-$EFFF`.
- Existing automated coverage proves:
  - the help view renders expected title/body/footer text on C64
  - the help command remains a no-turn modal UI flow and redraws correctly on C128
  - the current dismiss path depends on keyboard-buffer clearing / key-release gating and must not regress

### Design Boundary
- Keep `?` as the single help entry point for now.
- Do not add disk-backed external help files in this phase.
- Do not add topic search, scrolling within a page, or a new VMS-style `h` command in this phase.
- Do not change the current bank/overlay ownership model for help.
- Prefer a data-driven page table over duplicating multiple bespoke help renderers.

### Proposed Phase A
- Refactor the help data format from "one fixed 23-line table" to "N pages of 23-line tables" while preserving the existing per-line packed encoding.
- Add page metadata in `ui_help_data.s`:
  - page count
  - page title pointer or page-local title string
  - compact page-offset / page-pointer table for each page
- Keep `help_draw_line` and border rendering mostly unchanged; only the page selection should change.
- Update `ui_help_display` to render the currently selected page from the metadata table instead of assuming one hard-coded `help_lines` block.
- Keep page content resident where it already lives on each platform:
  - C64: main image data
  - C128: `OVL.UI` data

### Paging Interaction Contract
- First page should preserve the current quick-reference role and existing visible strings as much as practical.
- If only one page exists, behavior stays effectively unchanged.
- If multiple pages exist:
  - non-final pages show a footer/prompt that indicates continuation, e.g. `SPACE next  ESC quit`
  - final page shows an exit prompt, e.g. `ESC/SPACE done`
- `SPACE`, `RETURN`, and likely `?` should advance to the next help page.
- `ESCAPE`, `Q`, and platform cancel keys should dismiss help immediately from any page.
- After the final page, advancing should exit help and restore gameplay view exactly once.
- C128 key-release gating and the C64 keyboard-buffer clear need to happen in a way that does not auto-skip pages from the original `?` keypress.
- Do not add backward paging or wraparound in Phase A unless the implementation proves essentially free; the minimum viable contract is forward paging plus explicit dismiss.

### Preferred Implementation Split
1. Keep `ui_help_display` as a pure "draw one selected page" routine.
2. Add a small help pager driver in common code that:
   - initializes page index to 0
   - draws a page
   - waits for an allowed paging/dismiss key
   - loops until dismiss or end-of-pages
3. Let `cmd_show_help_view` call that pager driver instead of assuming one draw + one key + exit.

### Why This Split
- It preserves the existing testable seam where help drawing is separate from gameplay restore.
- It avoids reloading the overlay between pages on C128.
- It keeps the paging policy local to the help command instead of infecting generic modal-return helpers.
- It allows focused rendering tests to keep calling a one-page draw entry point if that remains useful.

### Data/Layout Guidance
- Reuse the current packed line encoding (`HTYPE_*`, `CT`, `CH`, `CK`, `CD`) so new pages only add small pointer/count metadata.
- Keep all pages at 23 content rows to preserve the current frame and viewport assumptions on both 40-column backends.
- Reserve the first page for the current "command reference" overview.
- Put overflow content onto later pages instead of trying to shrink the existing command labels aggressively.
- If later pages need different titles, add per-page title pointers; if not, reuse `Command Reference`.

### Risks
- C64 main-image growth: extra help pages add resident bytes and could pressure `MAP_BASE` headroom. Live slack is only `191` bytes.
- C128 UI overlay growth: extra help pages consume `OVL.UI` space and must stay within the existing `$E000-$EFFF` assertion. Live slack is only `290` bytes.
- Dismiss semantics: naive paging can accidentally consume the original `?` keypress and skip page 1, or consume the advance key twice on C128.
- Test fragility: existing tests that assume a single footer string or single dismiss key may need controlled expansion rather than blanket rewrites.
- Scope drift: a disk-backed/browser-style help system would pull in loader/state complexity far beyond the memory budget and should be deferred to a separate feature if ever needed.

### Verification
- Add explicit byte-budget gates for this feature before landing implementation:
  - C64 main image must remain below `MAP_BASE`
  - C128 `OVL.UI` must remain below `$F000`
- Add focused C64 help-view coverage for:
  - page 1 title/body/footer strings
  - page 2 body/footer strings
  - page count boundary: advancing from final page exits
  - dismiss keys exit immediately from page 1 and page N
- Add focused command-flow coverage for:
  - initial `?` does not auto-skip page 1
  - `SPACE`/`RETURN` advances exactly one page
  - `ESCAPE` exits without consuming a turn
  - gameplay view restore still occurs exactly once on exit
- Extend C128 modal-help coverage for:
  - page advance path
  - final-page exit path
  - preserved `input_wait_release` / redraw behavior
- Rebuild and inspect the emitted memory map / symbol placement for help code and help data on both targets after the change.
- Rebuild and run the standard C64 suite plus at least fast C128 coverage after the implementation.

### Consultant Review
- Completed.
- Consultant review agreed that the parity target should remain a VMS-style paged quick-reference panel, not an Umoria-style file-backed help browser.
- The strongest correction was to treat memory as the primary constraint:
  - C64 main-image slack is only `191` bytes
  - C128 `OVL.UI` slack is only `290` bytes
- The review recommended a compact page-offset/pointer table rather than duplicated fixed-size page blocks.
- The review also tightened the behavioral boundary:
  - keep `ui_help_display` as a draw-one-page primitive
  - keep pager state local to a tiny help-specific driver
  - avoid adding backward paging, wraparound, or browser-style state unless the minimal forward-paging version proves essentially free

### Final Planning Scope
- Phase A will implement only forward multi-page quick-reference help within the existing modal overlay flow.
- It will not implement disk-backed help files, topic browsing, search, scrollback, or a new dedicated help command.
- Acceptance requires both behavior proof and memory proof:
  - paging/dismiss/restore behavior verified on C64 and C128
  - C64 main image still below `MAP_BASE`
  - C128 `OVL.UI` still below `$F000`

### Implementation Review
- The original shared paged-help follow-up was still too cramped and brittle:
  - C128 page 2 was using a 40-column-style layout inside an 80-column screen
  - the shared footer degraded to a useless bare `Press`
  - C64 page 2 could fall through into trailing table bytes when the fixed 23-row contract was underfilled
- Final follow-up architecture:
  - help is now a dedicated `OVL.HELP` overlay on both targets
  - the generic pager remains resident in common code
  - C64 keeps a compact multi-page help flow inside `OVL.HELP`
  - C128 now uses a dedicated 80-column help page in `commodore/c128/ui_help_data_80.s`
  - `OVL.UI` is back to inventory/equipment/character/wizard only
- Final overlay outcome:
  - C64:
    - `Help overlay: 1387 bytes at $E000-$E56B`
    - `UI overlay: 1 byte at $E000-$E001` (reserved placeholder to preserve shared overlay numbering)
  - C128:
    - `Help overlay: 1320 bytes at $E000-$E528`
    - `UI overlay: 2756 bytes at $E000-$EAC4`
    - `Program image: $1C01-$DF99`
- Behavioral cleanup included:
  - the page-2 blank tail now emits the full 14 blank rows required by the fixed 23-line renderer contract
  - help footers now state the actual keys instead of a truncated `Press`
  - the help pager now advances on `SPACE` / `RETURN` and exits on `Q` / `ESC`, matching the displayed footer contract
- Verification completed:
  - `make -C commodore/c64 build` passed with `74` asserts and `0` failures
  - `bash commodore/c64/run_tests.sh` passed with `33 passed, 0 failed (of 33 suites)`
  - `make -C commodore/c64 disk` passed and writes `OVL.HELP`
  - `make -B -C commodore/c128 build128` passed with `231` asserts and `0` failures
  - `make test128-fast` passed
  - authoritative C128 verification outside the sandbox: `TEST_JOBS=1 ./run_tests128.sh` passed with `41 passed, 0 failed (of 41 suites)`
- Final C128 follow-up after user review:
  - the first 80-column pass was still wrong because it collapsed help to one page, allowed several right-column notes to wrap badly, and skipped help-overlay preload/caching
  - the final correction restored a true two-page C128 help flow in `commodore/c128/ui_help_data_80.s`
  - C128 help now uses a dedicated Bank 1 cache slot at `$2000-$2FFF`, so `OVL.HELP` is preloaded alongside the other overlays instead of disk-loading each time
  - final C128 memory outcome after that correction:
    - `Help overlay: 1322 bytes at $E000-$E52A`
    - `UI overlay: 2756 bytes at $E000-$EAC4`
    - `Program image: $1C01-$DF95`
  - final verification repeated after the cache/layout correction:
    - `make -C commodore/c128 build128` passed with `232` asserts and `0` failures
    - `make test128-fast` passed
    - `make -C commodore/c128 disk128` passed and writes preloaded `OVL.HELP`
    - authoritative C128 verification outside the sandbox again passed: `TEST_JOBS=1 ./run_tests128.sh` → `41 passed, 0 failed (of 41 suites)`
- Latest C128 page-2 polish:
  - page 2 now uses a graphical movement-key diagram patterned after classic Moria help, with both keypad directions and letter directions shown side by side
  - the notes/prompts copy was tightened so the diagram fits cleanly in the 80-column layout without relying on wraps
  - the first attempt to preserve diagonal connectors with punctuation still looked wrong at runtime, so the final version now uses a clean glyph-independent 3x3 key grid instead of diagonal art
  - after live screenshot review, the first grid pass was still too cramped, so the final C128 layout widens the 3x3 blocks and inserts breathing room between the key grid, the `stay` row, and the diagonal legend
  - final C128 memory outcome after the graphical page-2 pass:
    - `Help overlay: 1508 bytes at $E000-$E5E4`
    - `UI overlay: 2756 bytes at $E000-$EAC4`
    - `Program image: $1C01-$DF95`
  - verification repeated after the graphical page-2 pass:
    - `make -C commodore/c128 build128` passed with `232` asserts and `0` failures
    - `make test128-fast` passed
    - authoritative C128 verification outside the sandbox again passed: `TEST_JOBS=1 ./run_tests128.sh` → `41 passed, 0 failed (of 41 suites)`
    - `bash commodore/c64/run_tests.sh` still passed with `33 passed, 0 failed (of 33 suites)`
- Latest C64 page-2 polish:
  - C64 page 2 now uses the same graphical movement-key treatment in a 40-column-safe form, with the roguelike letter directions shown as a compact diagram
  - the C64 version intentionally omits the numeric keypad for now and keeps the prompt/selection copy in the lower half of the page
  - the first punctuation-only diagonal fallback still looked wrong at runtime, so the final C64 page uses a compact glyph-independent 3x3 letters grid plus explicit diagonal labels
  - final C64 memory outcome after the letters-diagram pass:
    - `Help overlay: 1490 bytes at $E000-$E5D2`
    - `Program: $080E-$CBAA`
  - verification repeated after the C64 page-2 update:
    - `make -C commodore/c64 build` passed with `74` asserts and `0` failures
    - `bash commodore/c64/run_tests.sh` passed with `33 passed, 0 failed (of 33 suites)`
    - `make -C commodore/c128 build128` passed with `232` asserts and `0` failures
    - `make test128-fast` passed
    - authoritative C128 verification outside the sandbox still passed: `TEST_JOBS=1 ./run_tests128.sh` → `41 passed, 0 failed (of 41 suites)`
- The first landing was not correct at runtime:
  - C64 could enter help and JAM instead of drawing text
  - C128 could draw a junk second page and ignored `ESC`
  - the original test coverage was too renderer-focused and missed the real platform trampolines / key contracts
- Final implementation shape after the correction:
  - `ui_help_display` stays draw-only inside `OVL.UI`
  - the paging loop moved back to resident common code in `cmd_show_help_view`
  - target trampolines now load `OVL.UI`, seed a resident `help_pages_src_lo/hi`, draw one page, and return
  - both help pages live inside `OVL.UI` on both targets
  - `ESC` handling now uses the platform keycode contract (`KEY_ESC` on C128, `$1B` on C64)
- Why this shape held up:
  - it avoids waiting for input while still inside the C64 overlay execution context
  - it keeps C128 page data out of the I/O hole by ensuring page pointers always resolve inside the loaded UI overlay
  - it preserves the original design goal that the renderer and pager remain separate seams
- Final memory / build outcome:
  - C64 shell suite passes with the paged help path in place
  - C128 main program stays below the map region
  - C128 `OVL.UI` now exactly fits the 4 KB slot:
    - `UI overlay: 4096 bytes at $E000-$F000`
    - `Program image: $1C01-$DF69`
- Verification completed:
  - `make -B -C commodore/c128 build128` passed with `230` asserts and `0` failures
  - `make test128-fast` passed, including `main_loop128`
  - `bash commodore/c64/run_tests.sh` passed with `33 passed, 0 failed (of 33 suites)`
- Follow-up harness correction:
  - `commodore/c128/tests/test_main_loop128.s` still treated the second help-page draw as a failure
  - the runtime contract is two draws for a two-page help flow, so the harness threshold was raised to allow the second draw and fail only on an unexpected third call

## Current Task
- [x] Audit the current ownership of shared versus platform-local input tables across C64/C128 input code.
- [x] Get a consultant-style second opinion on the safest scope and sequencing for `REF-INPUT-TABLES`.
- [x] Record the final `REF-INPUT-TABLES` design before implementation starts.

## `REF-INPUT-TABLES` Design

### Goal
- Finish centralizing genuinely shared input lookup data without reopening the platform-specific keyboard pipelines.
- Remove the duplicated base PETSCII-to-command mapping data from `commodore/c64/input.s` and `commodore/c128/input128.s`.
- Keep C128-only keypad / extended-key behavior explicitly local.

### Current Code Facts
- `commodore/common/input_contract.s` already centralizes:
  - `CMD_*` command IDs
  - `dir_dx`
  - `dir_dy`
  - `dir_opposite`
- `commodore/common/input_run_cancel.s` already centralizes the debounced run-cancel state machine used by both platforms.
- The remaining duplication is narrower than the backlog wording now suggests:
  - `commodore/c64/input.s` and `commodore/c128/input128.s` each carry the same base PETSCII key map for vi-keys, cursor keys, main commands, and run commands
  - both files also carry the same linear `petscii_to_command` scan body
- `commodore/c128/input128.s` still has real platform-specific additions that must stay local:
  - virtual keypad directions
  - keypad `5` rest
  - keypad `+` tunnel
  - `KEY_ESC` quit shortcut
- The scan/normalization front half is intentionally different by platform:
  - C64 uses KERNAL `GETIN`
  - C128 uses direct CIA scan, virtual keypad codes, and Ctrl-chord rescue

### Scope Boundary
- In scope:
  - one shared source of truth for the base PETSCII-to-`CMD_*` map used by both platforms
  - optionally one shared generic lookup body if it can be adopted without pointer plumbing or new scratch-state requirements
  - keeping the C128 extension tail local and obvious
- Out of scope:
  - `input_get_key`, `input_get_key_fast`, CIA scan, `GETIN`, shift handling, or Ctrl-chord normalization
  - run-cancel behavior, which is already shared
  - a broader `REF-CONSTS` sweep
  - `REF-HAL` platform-service cleanup

### Preferred Implementation Shape
1. Add a new common include such as `commodore/common/input_tables.s` rather than further bloating `input_contract.s`.
2. Make that file the single owner of the shared base key-map entries.
3. Prefer one pair-driven or macro-driven key-map definition over manually duplicated parallel tables:
   - avoid maintaining the same PETSCII/command rows in two platform files
   - keep the emitted order deterministic so the existing linear scan still works
4. Keep platform file ownership simple:
   - C64 emits only the shared base entries
   - C128 emits the shared base entries plus a short local extension tail for keypad / `ESC`
5. Only share the `petscii_to_command` routine if it stays trivial:
   - no pointer-based generic search
   - no extra zero-page contract
   - no indirection that makes the runtime path harder to inspect than the current straight-line scan

### Why This Shape
- Most of `REF-INPUT-TABLES` is already done by the existing `input_contract.s` / `input_run_cancel.s` split.
- The remaining maintainability win is in removing the duplicated base mapping data, not in re-architecting platform input.
- A table-first cleanup captures almost all of the value with very low behavior risk.
- A more generic lookup abstraction would add complexity, scratch-state pressure, and another failure surface without solving a real current problem.

### Sequencing Relative To Other Open Work
- `REF-INPUT-TABLES` should not block on `REF-HAL`.
- Reason:
  - `REF-HAL` is about shared platform service hooks and runtime call surfaces
  - this item is just ownership cleanup for input lookup data
- `REF-INPUT-TABLES` should also stay separate from `REF-CONSTS`.
- Reason:
  - `CMD_*` input constants are already centralized
  - the remaining `REF-CONSTS` work is broader (`SC_*`, `COL_*`, and other neutral constants)
  - folding this item into `REF-CONSTS` would blur a now-small, self-contained cleanup
- If desired, `REF-INPUT-TABLES` can land before `REF-CONSTS` as a narrow follow-up to `AUDIT-P19`, or be folded into the first `REF-CONSTS` patch only if the implementation remains strictly table-only.

### Key Risks
- Changing table order or alignment would silently remap commands.
- Moving shared data between files can still change segment sizes, so both C64 and C128 builds need fresh boundary verification.
- Over-generalizing the lookup helper could force extra indirection or scratch-state for no meaningful gain.
- Hiding the C128 keypad / `ESC` tail inside a too-generic shared layer would make platform-specific behavior harder to review and easier to regress.

### Verification Strategy
1. Rebuild both targets and inspect the emitted segment/assert output.
2. Prove one common source now owns the shared base PETSCII-to-command entries.
3. Prove C64 no longer carries a local copy of that base map.
4. Prove C128 keeps only the platform-specific extension tail locally.
5. Run the existing C64 suite so shared letter/cursor/command mappings stay green.
6. Run focused C128 input coverage plus the fast unit suite so keypad / `ESC` behavior stays correct.

### Smallest High-Value Acceptance Gates
- `make -C commodore/c64 build`
- `bash commodore/c64/run_tests.sh`
- `make -B -C commodore/c128 build128`
- `TEST_FILTER='input128' bash commodore/c128/run_tests128.sh`
- `make test128-fast`

### Consultant Review
- Consultant verdict: treat `REF-INPUT-TABLES` as a narrow table-ownership cleanup, not a second input-architecture rewrite.
- Strongest recommendation:
  - keep the hardware scan and modifier normalization fully platform-local
  - centralize only the shared base PETSCII mapping data and, at most, the trivial lookup body
- The consultant also recommended keeping this independent from the two neighboring backlog items:
  - do not expand it into `REF-HAL`
  - do not absorb it into the broader `REF-CONSTS` sweep unless the implementation remains a tiny table-only change
- Preferred acceptance bar:
  - one shared base key map
  - C128 keypad / `ESC` tail still local
  - existing C64 and focused C128 input tests still green

### Implementation Review
- Completed.
- Added `commodore/common/input_tables.s` as the single owner of the shared base PETSCII-to-command map entries.
- Retargeted both `commodore/c64/input.s` and `commodore/c128/input128.s` to import that shared file instead of carrying duplicate base tables locally.
- Kept the C128-only extension tail explicitly local in `commodore/c128/input128.s`:
  - keypad directions
  - keypad `5` rest
  - keypad `+` tunnel
  - `KEY_ESC` quit shortcut
- Kept the platform-specific scan and normalization logic unchanged:
  - C64 still uses the KERNAL `GETIN` path
  - C128 still uses CIA scanning, keypad virtual codes, and Ctrl-chord rescue
- Left the trivial linear `petscii_to_command` lookup body in place on each platform, matching the design choice to avoid over-generalizing the runtime path for a small data-only cleanup.
- Verification:
  - `make -C commodore/c64 build` passed with `74` asserts and `0` failures
  - `bash commodore/c64/run_tests.sh` passed with `33 passed, 0 failed (of 33 suites)`
  - `make -B -C commodore/c128 build128` passed with `232` asserts and `0` failures
  - focused C128 input gate outside the sandbox: `TEST_FILTER='input128' TEST_JOBS=1 bash commodore/c128/run_tests128.sh` passed with `1 passed, 0 failed`
  - `make test128-fast` passed

## Current Task
- [x] Inspect the current C128 trampoline surface in `commodore/c128/main.s` against the active backlog wording.
- [x] Compare that surface against the older completed trampoline-consolidation history and the post-`AUDIT-IO-C128` callable contract.
- [x] Get a consultant review on whether `REF-C128-TRAMP` still represents real remaining work or a stale backlog item.
- [x] Record the final `REF-C128-TRAMP` design before any further implementation.

## `REF-C128-TRAMP` Design

### Goal
- Re-scope `REF-C128-TRAMP` to match the live tree instead of repeating already-completed trampoline consolidation work.
- Decide whether any exact-match trampoline family still remains unnormalized after `REF-1` and `AUDIT-IO-C128`.
- If real work remains, keep it narrow, reviewable, and fully subordinate to the current callable-residency contract.

### Current Code Facts
- `commodore/BUILDPLAN.md` still describes `REF-C128-TRAMP` as macro-generating repetitive C128 trampoline boilerplate in `commodore/c128/main.s`.
- The current tree already contains substantial macro consolidation in `commodore/c128/main.s`:
  - `C128KernalJumpTableWrapper`
  - `C128UIBankedDisplayTrampoline`
  - `C128UIOverlayDisplayTrampoline`
  - `C128BankedComputeTrampoline`
  - `C128BankedPreserveATrampoline`
  - `C128BankedPreserveAReturnTrampoline`
  - `C128BankedStatusTrampoline`
  - `C128BankedPreserveFlagsTrampoline`
  - `C128BankedSharedEpilogueTrampoline`
- `commodore/BUILDPLAN_HISTORY.md` already records `REF-1 — C128 Trampoline-Sprawl Consolidation` as complete on `2026-03-20`, with exactly those family-level consolidations called out.
- `commodore/c128/io_contracts.s` now pins the C128 callable surface and residency contract after `AUDIT-IO-C128`.
- That means the old open backlog wording is broader than the real remaining work.

### What Still Looks Custom
- The remaining explicit wrappers in `commodore/c128/main.s` are not generic boilerplate; they carry real bespoke sequencing or side effects:
  - `tramp_player_create`
  - `tramp_game_over`
  - `tramp_ui_help_display`
  - `tramp_magic_check_new_spells`
  - `tramp_level_generate`
  - `tramp_ego_append_suffix`
  - `tramp_ego_put_suffix`
  - `w_load`
  - `kernal_load_safe`
  - `safe_setbnk`
- These differ materially in one or more of:
  - overlay-load policy
  - help-page pointer seeding
  - score/save side effects
  - diagnostic hooks
  - postprocessing of suffix/text data
  - caller-visible register/flag behavior

### Design Decision
- Treat `REF-C128-TRAMP` as a stale or at least overstated backlog item.
- Preferred next step is not another broad abstraction pass.
- Preferred next step is a closure audit:
  - verify whether any exact-match trampoline family still exists outside the current macro families
  - if none do, close the item from the backlog without code changes
  - if a tiny exact-match family remains, scope the implementation only to that family

### Scope Boundary
- In scope:
  - auditing for any genuinely repetitive, exact-match trampoline family still left unconsolidated
  - a tiny follow-up macroization only if the wrappers have identical entry/exit contract and residency expectations
  - backlog/documentation cleanup if the item proves stale
- Out of scope:
  - generic trampoline dispatchers
  - table-driven wrapper generation that obscures call contracts
  - merging overlay-call, banked-call, and KERNAL-visible wrappers behind one abstraction
  - any change to `io_contracts.s` residency classes unless the callable surface itself truly changes
  - broader `REF-HAL` platform-service work

### Non-Negotiable Safety Rules
1. Preserve every public `tramp_*` symbol name and call surface.
2. Keep `commodore/c128/io_contracts.s` as the source of truth for callable residency.
3. Do not make a reviewer infer legality indirectly from a dispatcher table or pointer indirection.
4. Do not merge wrappers that preserve different caller-visible state, even if they look superficially similar.
5. Do not accept any refactor that makes the low-memory callable surface harder to inspect than the current local wrapper shapes.

### Preferred Implementation Shape If Work Remains
1. Start with a symbol-by-symbol audit of the wrappers not already emitted through the existing family macros.
2. Partition them by exact behavioral contract, not by vague similarity:
   - preserved registers
   - preserved flags
   - `$01` / MMU restore path
   - overlay-load behavior
   - custom side effects before or after the call
3. Only macroize wrappers that match on all of those axes.
4. Leave bespoke wrappers explicit, even if that means the final code diff is very small.
5. If the audit finds no remaining exact-match family, close the item as stale backlog drift and record that `REF-1` plus `AUDIT-IO-C128` already covered the real work.

### Why This Shape
- The historical consolidation work is already present in the live tree.
- `AUDIT-IO-C128` deliberately made the callable surface explicit and reviewable.
- A fresh “more generic trampoline” pass would risk undoing that clarity for very little gain.
- The remaining wrappers are mostly explicit because they carry genuinely different runtime contracts, not because the codebase missed an obvious macro cleanup.

### Sequencing Relative To Other Open Work
- `REF-C128-TRAMP` should remain after `AUDIT-IO-C128`, exactly as the earlier audit plan required.
- It should not block on `REF-HAL`, but it also should not expand into `REF-HAL`.
- If the closure audit concludes the item is stale, it should be removed from `commodore/BUILDPLAN.md` and recorded in `commodore/BUILDPLAN_HISTORY.md` before any new trampoline work is attempted.

### Key Risks
- Collapsing wrappers that preserve different registers or flags.
- Hiding overlay/banked/KERNAL-visible distinctions behind a too-generic helper.
- Accidentally shifting low trampolines upward toward the `$D000` I/O hole.
- Reopening exactly the reviewability problem that `AUDIT-IO-C128` was meant to solve.

### Verification Strategy
1. Re-read the existing trampoline families in `commodore/c128/main.s`.
2. Compare the remaining explicit wrappers against the completed `REF-1` history entry.
3. Confirm that any proposed consolidation preserves the same public labels and the same `io_contracts.s` residency coverage.
4. If no new code is needed, close the backlog item through documentation only.
5. If a small code change is needed, rebuild and rerun the C128 gates appropriate to the size of the refactor.

### Smallest High-Value Acceptance Gates
- If the item proves stale and closes without code changes:
  - update `commodore/BUILDPLAN.md`
  - add the closure note to `commodore/BUILDPLAN_HISTORY.md`
- If a tiny exact-match family is still consolidated:
  - `make -B -C commodore/c128 build128`
  - `make test128-fast`
  - `make test128-fast-smoke`
  - `make test128` if the change touches multiple callable families or materially changes low-memory placement

### Consultant Review
- Consultant verdict: `REF-C128-TRAMP` is mostly stale and should be rescoped before anyone writes code.
- Strongest recommendation:
  - treat the current task as a rescope-or-close audit, not another broad macro-generation pass
  - preserve every public trampoline label and the post-`AUDIT-IO-C128` residency contract
  - do not introduce a table-driven or pointer-driven generic trampoline dispatcher
- Consultant-confirmed already-consolidated families:
  - KERNAL jump-table wrappers
  - UI display wrappers
  - banked compute wrappers
  - preserve-A wrappers
  - preserve-A-return wrappers
  - preserve-flags wrappers
  - shared-epilogue wrappers
  - banked status wrappers
- Consultant-confirmed wrappers that should mostly remain explicit:
  - `tramp_player_create`
  - `tramp_game_over`
  - `tramp_ui_help_display`
  - `tramp_magic_check_new_spells`
  - `tramp_level_generate`
  - `tramp_ego_append_suffix`
  - `tramp_ego_put_suffix`
  - `w_load`
  - `kernal_load_safe`
  - `safe_setbnk`

### Implementation Review
- Completed.
- Performed a source audit of the live C128 trampoline surface in `commodore/c128/main.s` against:
  - the active backlog wording for `REF-C128-TRAMP`
  - the older `REF-1` completion record in `commodore/BUILDPLAN_HISTORY.md`
  - the post-`AUDIT-IO-C128` callable contract in `commodore/c128/io_contracts.s`
- Confirmed the exact-match repetitive families are already consolidated in the live tree:
  - KERNAL jump-table wrappers
  - UI display wrappers
  - banked compute wrappers
  - preserve-A wrappers
  - preserve-A-return wrappers
  - preserve-flags wrappers
  - shared-epilogue wrappers
  - banked status wrappers
- Confirmed the remaining explicit wrappers are bespoke and should remain explicit because they carry custom sequencing or side effects:
  - overlay-load policy
  - help-page source seeding
  - score/save side effects
  - diagnostic hooks
  - suffix/text postprocessing
  - custom caller-visible register/flag behavior
- Result:
  - no new exact-match trampoline family remained to consolidate
  - `REF-C128-TRAMP` was closed as stale backlog wording already satisfied by `REF-1`, with the later `AUDIT-IO-C128` work reinforcing the need to keep the remaining custom wrappers explicit and reviewable
- Verification:
  - source audit only
  - no code changes
  - no test rerun required for the closure-doc update
