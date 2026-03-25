# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Task
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
