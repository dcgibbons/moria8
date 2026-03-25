# Active Task Scratchpad

This file is a temporary working scratchpad.

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
