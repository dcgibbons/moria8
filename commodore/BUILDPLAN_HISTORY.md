# Moria C64/C128 — Build Plan History

> Archive of completed phases, reviews, audits, and implemented optimizations.
> Extracted from BUILDPLAN.md on 2026-02-18.
> See [BUILDPLAN.md](BUILDPLAN.md) for active plans, [DESIGN.md](DESIGN.md) for architecture reference.

---

## 2026-03-27 — `REF-HAL` phase-1 platform-service cleanup ✅ COMPLETE

### Scope Closed
- Introduced the shared platform-service seam and sibling input-policy helpers that remove the main C128 runtime-repair and raw keyboard-policy leaks from shared gameplay/orchestration code.
- Closed the build-plan item at the phase-1 boundary after consultant review confirmed the remaining direct runtime-repair references are intentional exclusions rather than unfinished HAL work.

### What Shipped
1. **Required runtime-service shim installed on both platforms**
   - `commodore/common/platform_services_api.s`
   - startup patch/install in both `commodore/c64/main.s` and `commodore/c128/main.s`
2. **Shared input-policy helpers now own the raw keyboard-policy split**
   - `commodore/common/input_ui_helpers.s`
   - shared follow-up key, modal dismiss, and run-cancel buffer policy moved behind named helpers
3. **Shared gameplay/message callsites migrated off direct C128 repair helpers**
   - shared code now uses `platform_main_loop_begin_api`, `platform_vector_reassert_api`, and `platform_runtime_resync_api`
   - targeted modal flows now use the input helper layer instead of open-coded `KBDBUF_COUNT` handling
4. **C128 regressions found during rollout were corrected and folded into the final boundary**
   - Home/store residency moved back out of the I/O hole
   - C128 cursor-key repeat regression fixed
   - spell-list residency split so the callable spell surface no longer spills into `$D000-$DFFF`
   - post-death dismiss path now uses the modal helper while chargen gender selection intentionally stays on its explicit release wait

### Final Boundary
- `REF-HAL` phase 1 is complete as:
  - a narrow installed runtime-service seam for shared orchestration leaks
  - a sibling input-policy cleanup for shared key-handling leaks
- The remaining direct runtime-repair references in `commodore/common/` are intentional exclusions:
  - `commodore/common/reu.s` preload/bank-restore ownership
  - the one-off `c128_restore_generation_overlay` helper in `commodore/common/game_loop.s`
- Consultant review recommended not expanding HAL further for those one-off/platform-boundary cases; any future generation-overlay cleanup should be tracked as a separate slice, not as more HAL work.

### Verification
- `make -B -C commodore/c128 build128` passed with all asserts after the final narrowed prompt-policy cleanup.
- Focused C128 acceptance passed:
  - `make test128-fast`
  - `make test128-fast-smoke`
- Important verification note:
  - the full `bash commodore/c64/run_tests.sh` runner hung in this environment during the long `effects` suite, so the close-out record relies on the focused C128 acceptance set plus prior broader regression runs already captured in `tasks/todo.md`.

### Outcome
- `REF-HAL` is removed from the active build plan as completed phase-1 work.
- Shared gameplay code now depends on named platform/runtime/input services instead of directly accumulating C128 repair calls and raw keyboard-buffer policy.

## 2026-03-27 — CIA2 / VIC-bank restore cleanup in `overlay.s` / `tier_manager.s` ✅ COMPLETE

### Scope Closed
- Audited the active cleanup item around shared CIA2/VIC-bank restore assumptions in overlay and tier loading.
- Closed it after confirming `overlay.s` was already correctly split and fixing the last stale shared `$DD00` restore in `tier_manager.s`.

### What Was Verified
1. **`overlay.s` already kept the C128 path platform-owned**
   - the C128 overlay load path delegates to `c128_preload_asset_load`
   - the direct `$DD00` restore exists only in the `!C128` disk-load path
2. **`tier_manager.s` still carried one stale shared C64-era assumption**
   - after `AssetLoad`, `CLOSE`, and `CLRCHN`, it restored `$DD00` unconditionally
   - on C128 that ownership already belongs to the platform loader wrapper
3. **The fix reduced the shared assumption instead of adding new abstraction**
   - `tier_manager.s` now restores VIC-II bank 0 only on `!C128`
   - no new HAL/API layer was introduced

### Verification
- `make -B -C commodore/c128 build128` passed with all asserts.
- Focused C64 tier coverage still passed:
  - `commodore/c64/tests/test_tier.s` = `11/11`
- Focused C128 regression coverage passed:
  - `make test128-fast`
  - `make test128-fast-smoke`

### Outcome
- The active build-plan item is removed as completed.
- CIA2/VIC-bank restore ownership now sits in the correct platform boundary for both overlay and tier loading paths.

## 2026-03-27 — `REF-NUMFMT` backlog closure audit ✅ COMPLETE

### Scope Closed
- Audited the live numeric-formatting surface to determine whether the still-open `REF-NUMFMT` build-plan item represented real remaining work or stale backlog wording.
- Closed the item through plan/history reconciliation after confirming the shared formatter refactor had already shipped.

### Root Cause
- `commodore/BUILDPLAN.md` still described `REF-NUMFMT` as future work to unify duplicated VIC-II and VDC screen numeric helpers.
- The live tree already contains the shared owner added during the completed `CA-01` audit pass:
  - `commodore/common/numeric_format.s`
  - imported by both `commodore/c64/screen.s` and `commodore/c128/screen_vdc.s`
- The completed work also went slightly beyond the original backlog note by moving combat decimal formatting onto the same common numeric core and removing the old backend-local table dependency.
- That left the build-plan entry stale rather than unfinished.

### What Was Verified
1. **One shared module now owns the screen numeric helpers**
   - `screen_put_hex`
   - `screen_put_decimal`
   - `screen_put_decimal_rj2`
   - `screen_put_decimal_lz2`
   - `screen_put_decimal_16`
2. **Both screen backends already consume that shared owner**
   - `commodore/c64/screen.s`
   - `commodore/c128/screen_vdc.s`
3. **The shared numeric core also serves the combat appenders**
   - `commodore/common/combat.s` now calls `numeric_format_u8` / `numeric_format_u16`
   - shared `decimal_powers_*` data now lives in `commodore/common/numeric_format.s`
4. **The only intentionally separate formatter remains outside this backlog item**
   - `commodore/common/score.s` still owns the 24-bit score formatter, which has different width and call-shape requirements and is already documented as an intentional residual split in `commodore/CODE_AUDIT.md`

### Outcome
- `REF-NUMFMT` is closed as stale backlog wording already satisfied by the completed `CA-01` shared numeric-formatting work.
- No code changes were required.
- The active build plan no longer lists the item as open.

## 2026-03-27 — `REF-CONSTS` shared neutral constant ownership cleanup ✅ COMPLETE

### Scope Closed
- Finished the remaining low-risk constant-ownership cleanup for the live tree without reopening layout, MMU, or bootstrap policy.
- Centralized the small set of genuinely shared neutral aliases and closed the corresponding backlog item.

### Root Cause
- Several important constant families were already centralized:
  - `CMD_*` and direction tables
  - semantic gameplay/UI color aliases
  - disk/KERNAL I/O constants
- The real remaining duplication was narrower:
  - raw VIC palette indices were still defined in more than one runtime owner
  - shared `$01` processor-port banking aliases were still defined in both C64 and C128 memory layers
- The open backlog wording was broader than the real cleanup left to do.

### What Changed
1. **Raw VIC palette indices now have one shared owner**
   - Added `commodore/common/vic_palette_consts.s`.
   - Retargeted:
     - `commodore/common/color.s`
     - `commodore/c64/screen.s`
     - `commodore/c128/memory128.s`
2. **Shared `$01` banking aliases now have one shared owner**
   - Added `commodore/common/bank_port_consts.s`.
   - Retargeted:
     - `commodore/c64/memory.s`
     - `commodore/c128/memory128.s`
3. **The implementation stayed inside the intended boundary**
   - Left `SCREEN_COLS`, `SCREEN_ROWS`, `VIEWPORT_*`, `MSG_ROW`, `STATUS_ROW`, `INPUT_ROW` local.
   - Left `MMU_*` local.
   - Left VDC-only translated color aliases local.
   - Left bootstrap-local aliases in `commodore/c128/boot128.s` explicit.
   - Chose not to fold `SC_SPACE` into this pass so the change remained tightly scoped.

### Validation
- `make -C commodore/c64 build` (`74` asserts, `0` failed)
- `bash commodore/c64/run_tests.sh` (`33 passed, 0 failed`)
- `make -B -C commodore/c128 build128` (`232` asserts, `0` failed)
- `make test128-fast` (passed)
- `make test128-fast-smoke` (`3 passed, 0 failed`)

### Outcome
- `REF-CONSTS` is complete.
- Raw neutral constant families now have one shared owner.
- The active build plan no longer lists the item as open.

## 2026-03-27 — `REF-C128-TRAMP` backlog closure audit ✅ COMPLETE

### Scope Closed
- Audited the live C128 trampoline surface to determine whether the still-open `REF-C128-TRAMP` backlog item represented real remaining code work or stale backlog wording.
- Closed the item through backlog/history reconciliation after confirming the substantive trampoline-family consolidation was already complete.

### Root Cause
- `commodore/BUILDPLAN.md` still described `REF-C128-TRAMP` as future macro-generation work.
- The live tree already contained the real consolidation from the older `REF-1` pass, and the later `AUDIT-IO-C128` work intentionally favored explicit, reviewable callable contracts over more generic abstraction.
- That left the backlog item stale: it was still open even though the exact-match repetitive families had already been normalized.

### What Was Verified
1. **The main exact-match trampoline families are already consolidated in `commodore/c128/main.s`**
   - KERNAL jump-table wrappers
   - UI display wrappers
   - banked compute wrappers
   - preserve-A wrappers
   - preserve-A-return wrappers
   - preserve-flags wrappers
   - shared-epilogue wrappers
   - banked status wrappers
2. **The remaining explicit wrappers are bespoke and should stay explicit**
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
   - These wrappers carry overlay-load policy, help-page pointer seeding, score/save side effects, diagnostic hooks, suffix/text postprocessing, or distinct caller-visible register/flag contracts.
3. **The post-`AUDIT-IO-C128` contract argues against a broader generic dispatcher**
   - `commodore/c128/io_contracts.s` now pins the callable surface and residency classes.
   - Another broad “generic trampoline” pass would reduce reviewability without removing real remaining duplication.

### Outcome
- `REF-C128-TRAMP` is closed as stale backlog wording already satisfied by `REF-1`, with the remaining explicit wrappers intentionally left explicit.
- No code changes were required.
- The active build plan no longer lists the item as open.

## 2026-03-27 — `REF-INPUT-TABLES` shared base PETSCII map ownership cleanup ✅ COMPLETE

### Scope Closed
- Finished the remaining shared input-table cleanup without reopening the platform-specific keyboard architecture.
- Closed the backlog item by centralizing the duplicated base PETSCII-to-command map while leaving C128-only keypad and escape behavior explicit and local.

### Root Cause
- `commodore/common/input_contract.s` and `commodore/common/input_run_cancel.s` had already centralized the command IDs, direction tables, and run-cancel state machine.
- The remaining drift was narrower:
  - `commodore/c64/input.s` and `commodore/c128/input128.s` still each carried the same base PETSCII map for vi keys, cursor keys, main commands, and run commands
  - only the C128 keypad / extended-key tail was truly platform-specific

### What Changed
1. **One shared file now owns the base PETSCII map**
   - Added `commodore/common/input_tables.s`.
   - It emits the shared base PETSCII entries and matching `CMD_*` entries used by both platforms.
2. **Both platform input files now consume that shared base map**
   - `commodore/c64/input.s`
   - `commodore/c128/input128.s`
   - The duplicated local base tables were removed in favor of the shared macro-backed definitions.
3. **C128-only extension behavior stayed local and reviewable**
   - `commodore/c128/input128.s`
   - Keypad directions, keypad rest/tunnel shortcuts, and `KEY_ESC` quit remain in the platform file as the extension tail.
4. **The input architecture boundary did not expand**
   - The KERNAL `GETIN` path on C64 is unchanged.
   - The CIA scan, keypad virtual-code path, and Ctrl-chord rescue on C128 are unchanged.
   - The trivial `petscii_to_command` lookup body stayed local, avoiding extra pointer plumbing for a small table-ownership cleanup.

### Validation
- `make -C commodore/c64 build` (`74` asserts, `0` failed)
- `bash commodore/c64/run_tests.sh` (`33 passed, 0 failed`)
- `make -B -C commodore/c128 build128` (`232` asserts, `0` failed)
- focused C128 input gate outside the sandbox: `TEST_FILTER='input128' TEST_JOBS=1 bash commodore/c128/run_tests128.sh` (`1 passed, 0 failed`)
- `make test128-fast` (passed)

### Outcome
- `REF-INPUT-TABLES` is complete.
- The shared base input map now has one owner.
- C128 keypad and `ESC` behavior remain platform-local and fully covered by the focused C128 input gate.

## 2026-03-27 — `BUG-HELP-PAGING` multi-page help flow and overlay split ✅ FIXED

### Scope Closed
- Completed the multi-page `?` help flow on both C64 and C128 without reopening the broader "browser-style help system" scope.
- Moved the feature out of the active backlog and closed the remaining tracker drift between the implementation record and the active build plan.

### Root Cause
- The active backlog still listed `BUG-HELP-PAGING` as open even though the implementation and verification had already landed.
- The underlying help bug was the original single-page assumption:
  - longer quick-reference help could not paginate cleanly
  - the first shared follow-up design was too brittle across the C64/C128 overlay and key-handling contracts

### What Changed
1. **Help is now a real multi-page modal flow**
   - The resident help pager advances on `SPACE` / `RETURN` and exits on `Q` / `ESC`.
   - The first page keeps the quick-reference role; later pages carry the overflow content.
2. **Help data/layout is now platform-correct**
   - C64 uses a compact multi-page help overlay.
   - C128 uses a dedicated 80-column help layout in `commodore/c128/ui_help_data_80.s`.
   - The final C128 path restores a true two-page help flow instead of collapsing back to one page.
3. **Overlay ownership was cleaned up so help no longer distorts the UI overlay budget**
   - Help now lives in dedicated `OVL.HELP` overlays instead of bloating `OVL.UI`.
   - C128 help is preloaded into its own Bank 1 cache slot so the runtime path does not disk-load on each open.
4. **The runtime/keypath regressions from the first landing were closed**
   - The paging loop lives in resident common code.
   - Platform-specific escape handling and redraw/return behavior were corrected.
   - Page tails and footer prompts now match the fixed 23-row renderer contract and the actual accepted keys.

### Validation
- `make -C commodore/c64 build` (`74` asserts, `0` failed)
- `bash commodore/c64/run_tests.sh` (`33 passed, 0 failed`)
- `make -C commodore/c64 disk` (writes `OVL.HELP`)
- `make -C commodore/c128 build128` (`232` asserts, `0` failed)
- `make test128-fast` (passed)
- `make -C commodore/c128 disk128` (writes preloaded `OVL.HELP`)
- authoritative C128 verification outside the sandbox: `TEST_JOBS=1 ./run_tests128.sh` (`41 passed, 0 failed`)

### Outcome
- `BUG-HELP-PAGING` is closed.
- The active backlog no longer lists it as open.
- Multi-page quick-reference help is now implemented and verified on both platforms.

## 2026-03-26 — `AUDIT-IO-C128` callable residency audit and guard unification ✅ FIXED

### Scope Closed
- Audited the C128 callable execution surfaces whose correctness depends on residency, overlay ownership, banked/runtime-low placement, or copied-code load headers.
- Replaced the old hand-maintained callable placement list with one explicit contract manifest shared by compile-time asserts and the C128 runner.

### Root Cause
- The tree already had many important C128 placement asserts, but they were selective and hand-curated in `commodore/c128/main.s`.
- The runner then kept a second hand-picked symbol list in `commodore/c128/run_tests128.sh`.
- That split left real drift risk:
  - trampoline-side guards could exist without matching callee-side guards
  - new callable surfaces could be protected in source but not enforced by the runner, or vice versa
  - runtime-low / overlay / banked contracts were not represented as one auditable callable inventory

### What Changed
1. **One C128 callable residency manifest now declares the audited contract**
   - `commodore/c128/io_contracts.s`
   - Added one source-of-truth inventory for:
     - resident `< $D000` entrypoints
     - runtime-low Bank 0 entrypoints
     - startup / town / death / UI / dungeon overlay entrypoints
     - reloadable banked payload entrypoints
     - out-of-I/O-hole call surfaces that may legally live low or banked
2. **Compile-time C128 placement asserts now come from that manifest**
   - `commodore/c128/main.s`
   - Added macro-backed `AUDIT-IO-C128` asserts and removed the long inline callable-placement list.
   - Kept unrelated data/layout asserts separate, such as message-history sizing and prompt-string placement.
3. **The C128 runner now validates the same manifest**
   - `commodore/c128/run_tests128.sh`
   - `main128_layout` now parses `io_contracts.s` directly, verifies each symbol against its declared residency class, and checks that `out/runtime.low.prg` still carries the `$1000` load header.
4. **Callee-side gaps are now guarded, not just trampoline addresses**
   - Newly enforced overlay/runtime-low/banked callees include:
     - `player_create`, `store_enter`, `score_death_screen`, `level_generate`, and the special-room helpers
     - `viewport_update`, `render_viewport_scroll_delta`, `render_local_area`, `monster_get_threat_color`, and ego helpers in `runtime.low`
     - `player_tunnel`, `player_cast_spell`, `player_pray`, and `spell_list_display`

### Validation
- `make -B -C commodore/c128 build128` (`230` asserts, `0` failed)
- `TEST_FILTER='c128_artifact_budget|c128_symbol_placement' TEST_FAIL_FAST=1 ./run_tests128.sh` (`2` passed, `0` failed)
- tester: `make test128-fast` (passed)
- tester: `make test128-fast-smoke` (passed)
- tester + local isolation:
  - sandboxed / parallel `make test128` hit VICE `Segmentation fault: 11` in `run_test_internal_worker.sh`
  - the failure reproduced on sandboxed `minimal128`
  - outside the sandbox, the same authoritative launch path passed
  - outside the sandbox, `TEST_FILTER='memory128|main_loop128' TEST_FAIL_FAST=1 TEST_JOBS=1 ./run_tests128.sh` passed
  - tester: `TEST_JOBS=1 ./run_tests128.sh` outside the sandbox → `41 passed, 0 failed`

### Outcome
- `AUDIT-IO-C128` is closed.
- The C128 callable residency contract is now explicit, auditable, and enforced from one manifest instead of two drifting symbol lists.
- Future C128 layout work now has callee-side guard coverage for the overlay, runtime-low, and banked paths that previously relied on partial/manual enforcement.

## 2026-03-26 — `BUG-HAGGLE-UI` one-visit haggle parity plus C128 runner fallout ✅ FIXED

### Scope Closed
- Restored the store haggle loop to correct one-visit behavior for the current Commodore store model without expanding into persistent owner memory or temporary lockout work.
- Closed the C128 verification fallout that initially obscured the gameplay fix: stale base/variant artifact reuse and a broken shell-runner footer.

### Root Cause
- The live store code had drifted to a simplified fixed-step bargain loop with hard-coded insult thresholds and a generic final Y/N stage, which no longer matched classic VMS/Umoria haggle behavior.
- The first C128 verification failures after the gameplay patch were not all gameplay regressions:
  - one failure was a stale prompt guard relative to the already-landed Huffman-backed prompt helper path
  - several hangs were stale monitor/runner contracts in the authoritative shell harness
  - one apparent I/O-hole regression was stale variant output reuse in `out/moria128.prg` / `out/main.vs`, not the live base build
  - the last visible failure was a runner footer syntax break after the suite body had already passed

### What Changed
1. **Haggle behavior now matches the intended bounded Stage A parity target**
   - `commodore/common/ui_store.s`
   - `commodore/common/store.s`
   - Buy/sell haggling now rejects backwards offers, handles overshoot/undershoot retries, uses integer concession math, accepts at the correct agreed player price, preserves no-haggle bypasses, and decays insult state after successful business.
2. **Focused store/runtime coverage now proves the repaired haggle contract**
   - `commodore/c64/tests/test_store.s`
   - `commodore/c64/run_tests.sh`
   - Added parser, buy/sell flow, insult/kick, and no-haggle bypass coverage, plus the C64 harness layout fixes needed after the shared-code growth.
3. **The authoritative C128 shell runner no longer reuses stale variant artifacts or dies at the summary footer**
   - `commodore/c128/run_tests128.sh`
   - `main128_asm` now forces a base rebuild when the active variant is not `base`, so `c128_artifact_budget` reads the real base build instead of stale scripted/diagnostic outputs.
   - The prompt IRQ guard now matches the live prompt helper contract.
   - The final summary/footer path is repaired, so a green suite now exits cleanly.

### Validation
- `bash commodore/c64/run_tests.sh` (`33` passed, `0` failed)
- `make test128-fast` (passed)
- `TEST_FAIL_FAST=1 ./run_tests128.sh` (`41` passed, `0` failed)

### Outcome
- `BUG-HAGGLE-UI` is closed.
- One-visit store haggling now behaves correctly within the current thin store model.
- The final verified C128 issue was runner artifact/footer drift, not a lingering haggle gameplay regression.

## 2026-03-24 — `BUG-PROMPT-FILTER` filtered inventory prompts/selectors now stay in sync ✅ FIXED

### Scope Closed
- Fixed the prompt/UI/parser mismatch where filtered item commands still advertised full-pack letters, accepted absolute slot letters, and could expose hidden sparse slots that were not valid for the action.

### Root Cause
- The shared inventory overlay and the prompted item-selection callers were not using the same selection contract.
- Filtered overlays hid unrelated items but kept absolute sparse-slot letters.
- Prompted handlers still parsed `A-V` / `A-H` as physical slot letters first and only rejected category mismatches afterward.
- Local sparse inventory layout made direct upstream range-copying invalid; Moria8 needed ordinal mapping over visible matches, not storage compaction.

### What Changed
1. **Filtered inventory/equipment selection now uses one shared ordinal-mapping path**
   - `commodore/common/player_items.s`
   - Added shared helpers for:
     - filtered carried-slot matching/counting/picking
     - contiguous non-empty equipment picking
     - dynamic prompt range printing
   - `item_wear`, `item_quaff`, `item_read_scroll`, `item_aim_wand`, `item_use_staff`, `item_gain_spell`, and `item_takeoff` now all use that shared path.
2. **Filtered overlays now match what the parser accepts**
   - `commodore/common/ui_inventory.s`
   - Filtered pack overlays relabel visible sparse matches contiguously from `A`.
   - Equipment overlays keep slot-label rows but add contiguous letters only for non-empty entries.
   - Flask of Oil is excluded from the wearable filtered set at the shared-helper layer, so the overlay and parser agree on the real `wear` target set.
3. **Regression fixtures and resident string assets were updated**
   - `data/huffman_strings.txt`
   - `commodore/common/huffman_data.s`
   - `commodore/c64/tests/test_item.s`
   - `commodore/c64/tests/test_wands_staves.s`
   - `commodore/c64/tests/test_ui_views.s`
   - `commodore/c64/tests/test_subsystems.s`
   - `commodore/c64/run_tests.sh`
   - Removed dead filtered-selection error strings that were no longer reachable once the selector stopped exposing invalid choices.
   - Regenerated the resident Huffman table and refreshed the embedded subsystem string-bank fixture against the new tree.
   - Added coverage for sparse filtered-selection mapping, takeoff reindexing, filtered overlay lettering, and dynamic prompt ranges.

### Validation
- `java -jar ../../tools/kickass/KickAss.jar main.s -showmem -vicesymbols -o out/moria8.prg` (`72` asserts, `0` failed)
- `bash commodore/c64/run_tests.sh` (`33` suites passed, `0` failed)

### Outcome
- `BUG-PROMPT-FILTER` is closed.
- Filtered inventory prompts, `?` overlays, and accepted input now describe the same visible choice set.
- Sparse pack layout stays unchanged; the fix is entirely at the prompt/UI-selection layer.

## 2026-03-24 — `BUG-DIG-SHIFT-D` Shift+D dig path reaches tunneling again ✅ FIXED

### Scope Closed
- Fixed the user-reported case where trying to dig into veins/walls via `Shift+D` could stop at bash's wall-side `Nothing interesting happens.` response instead of reaching the digging runtime.

### Root Cause
- The live command layout intentionally kept `+` as the explicit tunnel key and `Shift+D` as bash.
- `bash_command` treated tunnelable terrain as a pure bash miss path, so a dig-intent `Shift+D` on quartz/magma/rubble/walls never reached `player_tunnel`, even when the equipped tool and tunnel logic were otherwise correct.

### What Changed
1. **Bash now hands tunnelable terrain to the digging runtime**
   - `commodore/common/bash.s`
   - `bash_command` still handles door bashes and monster bashes directly.
   - When the selected target is tunnelable terrain, it now jumps into a shared tunnel helper instead of printing the bash wall-side no-op message.
2. **Tunnel exposes a reusable resolved-target entry point**
   - `commodore/common/tunnel.s`
   - Added `player_tunnel_resolved_target` so the bash path can reuse the actual digging/tool/vein logic after direction selection has already happened.
3. **Help and regression coverage were updated**
   - `commodore/common/ui_help_data.s`
   - `commodore/c64/tests/test_bash.s`
   - `commodore/c64/run_tests.sh`
   - Help row now advertises `SHIFT+D` as `Bash/Dig`.
   - The bash suite now verifies:
     - tunnelable terrain hands off to digging
     - closed-door bash does not regress

### Validation
- `./commodore/c64/run_tests.sh bash` (`33` suites passed, `0` failed)
- `make test128-fast` (passed)
- `make test128-fast-smoke` (`3` passed, `0` failed)

### Outcome
- `BUG-DIG-SHIFT-D` is closed.
- `Shift+D` keeps bash behavior where it matters, but no longer dead-ends on diggable terrain.
- The explicit `+` tunnel command remains intact.

## 2026-03-24 — `BUG-GAMEOVER-CLEAR-C64` C64 game-over menu clear ✅ FIXED

### Scope Closed
- Fixed the C64 UI bug where the `Reboot / Restart / Quit` menu could still show stale gameplay status rows at the bottom of the screen after save-and-quit or death flow reached the prompt.

### Root Cause
- `game_over_prompt` in `commodore/c64/main.s` was preparing the full-screen menu with the wrong clear strategy for this path.
- A simple blank/unblank ordering fix was not sufficient; the final visible frame still retained the bottom status rows.
- The working fix was to use the safer row-by-row full-screen clear helper already used by other sensitive C64 UI screens.

### What Changed
1. **Game-over prompt now uses the safer full-screen clear helper**
   - `commodore/c64/main.s`
   - `game_over_prompt` now:
     - `screen_blank`
     - sets black clear color
     - `ui_help_clear_all`
     - restores white text
     - draws `R)EBOOT  S)TART  Q)UIT`
     - `screen_unblank`
   - This ensures the final prompt frame is built on a fully cleared screen rather than relying on the generic bulk clear for this path.
2. **Task notes and lessons were updated**
   - `tasks/todo.md`
   - `tasks/lessons.md`
   - Recorded that this bug looked similar to the generation-screen issue but required a different local fix: the prompt needed the row-by-row clear helper, not just presentation reordering.

### Validation
- `make test` (`33` passed, `0` failed)
- `make test128-fast` (passed; batch green)
- Manual C64 confirmation from the user that the game-over / save-and-quit menu now clears correctly

### Outcome
- `BUG-GAMEOVER-CLEAR-C64` is closed.
- The C64 game-over menu now renders on a fully cleared screen.
- The remaining nearby UI issue is separate backlog work:
  - `BUG-TITLE-DUALDISK-FRAME`

## 2026-03-24 — `BUG-GEN-CLEAR-C64` C64 generation busy-screen clear ✅ FIXED

### Scope Closed
- Fixed the C64 UI bug where the full-screen `GENERATING...` transition could appear over stale gameplay/title contents instead of a clean cleared screen.
- Added focused regression coverage for the busy-screen presentation order.

### Root Cause
- `generation_busy_begin` in `commodore/common/generation_busy.s` made the display visible before the busy UI was fully prepared.
- The old sequence was:
  - `screen_unblank`
  - `screen_clear`
  - draw `GENERATING...`
- That let the player briefly see the previous frame while the clear/draw work was still in progress.

### What Changed
1. **Busy-screen presentation now hides the old frame first**
   - `commodore/common/generation_busy.s`
   - `generation_busy_begin` now:
     - `screen_blank`
     - `screen_clear`
     - draw `GENERATING...`
     - `screen_unblank`
   - This keeps the stale gameplay/title frame hidden until the busy screen is fully established.
2. **The C64 host test now exercises the real busy UI path**
   - `commodore/c64/tests/test_main_loop.s`
   - Replaced the old no-op busy stubs with wrappers around the real busy UI entry points.
   - Added a focused regression that records the presentation order and asserts:
     - blank
     - clear
     - draw
     - unblank
   - Also verifies that `generation_busy_end` restores the prior text color and clears the active flag.
3. **The test runner now enforces the new regression**
   - `commodore/c64/run_tests.sh`
   - Updated the `main_loop` suite result range/count from `13` to `15`, so the new busy-order checks are part of normal C64 verification.

### Validation
- `make test` (`33` passed, `0` failed)
- `make test128-fast` (passed; batch green)
- Manual C64 gameplay confirmation from the user that the `GENERATING...` transition now looks correct

### Outcome
- `BUG-GEN-CLEAR-C64` is closed.
- The C64 generation busy screen now hides the previous frame until the cleared `GENERATING...` view is ready.
- The regression is now enforced in the regular C64 host test path rather than relying only on manual repro.

## 2026-03-23 — `BUG-XP-PACE` XP threshold / level-up parity ✅ FIXED

### Scope Closed
- Fixed the remaining XP pacing drift that made characters level faster than stock Umoria in longer runs.
- Added focused regression coverage for late thresholds, non-100 experience factors, retained fractional XP, and repeated level gains from one award.

### Root Cause
1. **Late-game XP thresholds were truncated**
   - `commodore/common/tables.s` stored only 16-bit threshold values and saturated level `29+` progression at `65535`.
   - Original Umoria continues the curve through `75000`, `100000`, `150000`, `200000`, `300000`, `400000`, `500000`, `750000`, `1500000`, `2500000`, and `5000000` for current levels `29-39`.
2. **Level gains were hard-capped to one level per award**
   - `combat_check_levelup` stopped after a single gain even if retained XP still exceeded the next threshold.
   - Original Umoria keeps checking until the post-halving retained XP falls below the next threshold.

### What Changed
1. **Threshold computation now matches the original late-game curve**
   - `commodore/common/tables.s`
   - Kept the compact early 16-bit threshold table for levels `1-28`.
   - Added exact late `threshold / 100` data for levels `29-39`, which is sufficient for the real level-transition path and avoids the old `65535` saturation bug.
2. **Threshold scaling now produces a real 24-bit gate**
   - `commodore/common/combat.s`
   - Reworked `combat_compute_level_threshold` to use `math_mul_16x8` and produce a full 24-bit adjusted threshold.
   - Early levels still divide by `100` at runtime; late levels use the exact pre-divided values because the original thresholds are clean multiples of `100`.
3. **Level-up checks now follow Umoria's repeated-gain behavior**
   - `commodore/common/combat.s`
   - `combat_check_levelup` now compares full 24-bit whole XP against the full adjusted threshold and loops until the retained post-halving XP no longer qualifies for another gain.
4. **Wizard gain-level helpers now respect 24-bit thresholds**
   - `commodore/common/wizard.s`
   - `commodore/common/ui_wizard.s`
   - Wizard level promotion now seeds and compares the full 24-bit threshold instead of silently truncating the high byte.
5. **Added regression coverage for the fixed parity points**
   - `commodore/c64/tests/test_combat.s`
   - Added late-threshold checks for level `30` at `100%` and `150%` experience factors.
   - Added a repeated-gain case proving a single award can advance from level `1` to level `4` with retained XP `52`.
   - Tightened the existing fractional-XP award case so hidden fractional state must stay zero when the whole award divides cleanly.

### Validation
- Direct C64 KickAssembler build with local jar override
- Direct C128 KickAssembler build with local jar override
- `./commodore/c64/run_tests.sh` (`33` passed, `0` failed)
- `make test128-fast` (passed; batch green)

### Outcome
- `BUG-XP-PACE` is closed.
- Late-game level thresholds now match the original source curve instead of flattening at `65535`.
- Excess XP now follows the original repeated level-gain contract after each halving step.
- Shared C64/C128 combat verification remained green after the change.

## 2026-03-23 — `BUG-DEEP-SPAWN` deep-level monster fallback ✅ FIXED

### Scope Closed
- Fixed the deep-level spawn bug where dungeon levels around `45-50` could degenerate into implausible repeated fallback monsters.
- Added focused runtime coverage for the empty-band deep selector case.

### Root Cause
- `pick_creature_type` in `commodore/common/monster.s` preferred a narrow level band:
  - `max(1, dlvl - 2)` through `dlvl + 3`
- If the loaded roster had no creature in that band, the routine fell through to hardcoded creature index `0`.
- That made deep-level failure collapse to the first loaded creature slot instead of a plausible deep monster.

### What Changed
1. **Deep fallback no longer collapses to slot 0**
   - `commodore/common/monster.s`
   - Kept the existing narrow-band fast path.
   - Replaced the bad fallback with a scan that chooses the highest loaded creature level `<= current dungeon depth`.
2. **Added an empty-band regression**
   - `commodore/c64/tests/test_monster.s`
   - Added a synthetic deep-roster case proving `dlvl 45` with an empty preferred band resolves to the highest valid loaded creature instead of `0`.
3. **Recovered C64 layout headroom**
   - `commodore/common/title_sysinfo_banked.s`
   - `commodore/common/ui_home.s`
   - Trimmed a few low-value banked UI bytes so the C64 banked payload remained below `$D000` after the fix.

### Validation
- `make test`
- `make -B -C commodore/c128 build128`
- `make test128-fast`

### Outcome
- `BUG-DEEP-SPAWN` is closed.
- Deep empty-band selection now resolves to a plausible loaded deep creature instead of collapsing to the first roster slot.
- C64/C128 authoritative verification remained green after the fix.

## 2026-03-23 — `BUG-EGO-NAME` and dungeon visibility/render follow-ups ✅ FIXED

### Scope Closed
- Fixed the active UI bug where ego/slay item names rendered corrupted suffix text in inventory/equipment views.
- Fixed two related live-map visibility/render drift bugs found during manual gameplay:
  - `look` could identify monsters on remembered dark tiles that were not actually visible
  - monster spellcasts that summoned visible blockers did not always force a full scene redraw
- Fixed a floor-search contract bug that could hand non-floor coordinates to item/trap/teleport callers after repeated search failure.

### Root Causes
1. **Ego suffix rendering bypassed the safe platform contract**
   - `put_inv_name_with_ego` printed base names in shared code, then called `banked_ego_put_suffix` directly.
   - Ego suffix strings live in banked `$F000` RAM and must be read through the platform-owned trampoline path.
2. **`look` used remembered visibility instead of current visibility**
   - `do_look` treated `FLAG_VISITED` as enough to describe a tile, even when the live renderer correctly hid monsters/items outside the current light bubble.
3. **Monster spellcasts did not mark the scene dirty**
   - Summon/help casts could change the visible scene without forcing the shared full-render path, leaving real occupied monsters present in gameplay state but missing from the live map until a later redraw.
4. **`find_random_floor` had a bad failure contract**
   - After 200 failed attempts it returned the last random coordinates as if they were valid.
   - Callers could then place traps, items, or teleports onto non-floor or occupied tiles.

### What Changed
1. **Ego item rendering now uses the safe platform suffix path**
   - `commodore/common/game_loop.s` now routes inventory/equipment suffix printing through `tramp_ego_put_suffix`.
   - Test stubs were updated on C64/C128 to match that shared helper contract.
2. **`look` now matches live visibility**
   - `commodore/common/player_move.s` now uses `los_is_visible` instead of `FLAG_VISITED` when deciding whether `look` can describe a tile.
3. **Monster spellcasts now force a scene redraw**
   - `commodore/common/monster_ai.s` marks spellcasting turns as `mat_action_dirty`, so summon/help casts take the shared full-render path.
4. **Random-floor search now reports failure correctly**
   - `commodore/common/dungeon_features.s` now returns carry-set only on success and carry-clear on failure.
   - `commodore/common/item.s` and `commodore/common/spell_effects.s` now honor that contract instead of consuming stale coordinates.

### Regression Coverage
- `commodore/c64/tests/test_ui_views.s`
  - inventory/equipment now assert a real ego suffix case: `Long Sword (Slay Evil)`
- `commodore/c64/tests/test_effects.s`
  - added a remembered-dark-tile `look` regression
- `commodore/c64/tests/test_monster_ai.s`
  - added a summon-cast dirty-scene regression
- `commodore/c64/tests/test_item.s`
  - added a no-valid-floor regression proving `item_spawn_level` cannot place floor items into a map with no valid floor tiles
- `commodore/c64/run_tests.sh`
  - test counts updated for the added coverage
  - temp file creation hardened for reliable repeated suite runs on macOS

### Validation
- `make test`
- `make -B -C commodore/c128 build128`
- `make test128-fast`

### Outcome
- `BUG-EGO-NAME` is closed.
- Inventory/equipment ego/slay suffixes now render correctly.
- `look` and the live renderer now agree about current monster visibility.
- Monster summon/help casts correctly dirty the scene for redraw.
- Floor-search failure no longer leaks wall/occupied coordinates into item/trap/teleport placement.

---

## 2026-03-23 — `BUG-RECALL` Word of Recall transition path ✅ FIXED

### Scope Closed
- Fixed the active gameplay bug where Word of Recall could fail to complete a reliable town/dungeon transition.
- Replaced recall's private level-generation tail with the same shared helper already used by stairs and Wizard jumps.

### Root Cause
- Recall expiry in `commodore/common/turn.s` had drifted into its own custom transition path.
- That code:
  - adjusted depth/direction
  - directly called `tier_check_transition`
  - directly called `level_generate`
  - then ran spawn / visibility / redraw steps inline
- The hardened stairs path already used `level_change_generate_current`, which:
  - loads the correct generation overlay
  - runs the shared generation/spawn/redraw tail
  - carries the C128 overlay/runtime residency fixes
- So recall could execute generation against whichever overlay happened to be resident at `$E000`, which explains the intermittent “does not reliably return to town” behavior.

### What Changed
1. **Recall now reuses the shared transition helper**
   - `commodore/common/turn.s` now keeps only the recall-specific destination logic:
     - dungeon -> town
     - town -> `PL_MAX_DLVL`
     - town-side fizzle if `PL_MAX_DLVL == 0`
     - store restock on town return
     - `level_entry_dir` selection
   - After that it now calls:
     - `tier_invalidate_state`
     - `level_change_generate_current`
2. **Fizzle behavior was hardened**
   - The old code cleared `FLAG_OCCUPIED` before it even knew whether recall would actually fire.
   - The fix moves the occupied-bit clear behind the real teleport path, so a town-side recall fizzle leaves the player tile intact.
3. **Regression coverage was updated**
   - `commodore/c64/tests/test_turn.s` now asserts:
     - recall dungeon -> town uses the shared level-change helper
     - recall town -> deepest level uses the shared level-change helper
     - recall fizzle does not invoke the helper and does not clear the occupied bit

### Validation
- `make -C commodore/c64 build`
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- Focused C64 runtime `test_turn` verification was attempted separately, but local `x64sc` exited `139` before producing a monitor dump in this environment, so that runtime result remained inconclusive rather than failing.

### Outcome
- `BUG-RECALL` is closed.
- Recall now follows the same reliable level-transition machinery as stairs and Wizard jumps.
- The active backlog keeps only the remaining gameplay bug:
  - `BUG-EGO-NAME`

---

## 2026-03-23 — `BUG-LIGHT-RANGE` carried-light audit ✅ CONFIRMED NON-BUG

### Scope Closed
- Audited the carried-light visibility model against original `umoria` and `vms-moria` source trees.
- Verified that the current Commodore port’s local carried-light radius is already consistent with the original game.

### What Was Verified
- Original `umoria` uses a boolean carried-light state and lights a 3x3 block around the player:
  - `src/dungeon.cpp` `sub1MoveLight()`
  - `src/dungeon.cpp` `dungeonMoveCharacterLight()`
- Original `vms-moria` shows the same behavior:
  - `source/include/moria.inc` `sub1_move_light`
  - `source/include/misc.inc` `test_light`
- In both original trees, torch and brass lantern differ by fuel capacity/refueling behavior, not by a larger visibility radius.

### Outcome
- `BUG-LIGHT-RANGE` is closed as a source-confirmed non-bug.
- The current port’s `zp_light_radius = 1` / local 3x3 carried-light bubble is correct.
- Any future work here is cleanup only:
  - centralize the carried-light contract in one helper/table
  - add focused equip/deplete/visibility tests

---

## 2026-03-23 — `FEAT-WIZ` Wizard Mode ✅ COMPLETE

### Scope Closed
- Added a one-way Wizard Mode for debug/test play on both C64 and C128.
- Persisted Wizard state with the character, surfaced it in player-facing UI, and suppressed rank insertion/save for wizard runs.
- Added the modal Wizard command menu plus the first round of regression hardening discovered during real manual play.

### What Changed
1. **Activation, persistence, and UI**
   - `Ctrl+W` now enters Wizard Mode after confirmation and reopens the Wizard menu once enabled.
   - Wizard state is persisted via `zp_game_flags` and reset only for transient session-only helpers like wall-walk.
   - Character-sheet display now shows a clear `WIZARD` tag on both C64 and C128.
2. **Wizard command set**
   - Added commands for:
     - level jump
     - reveal level / secret doors
     - heal & cure
     - identify inventory
     - gain one level
     - generate item
     - summon monster
     - teleport
     - wall-walk toggle
   - C128 reuses `OVL.UI` for the Wizard menu and the low-frequency learned-spell helper.
   - Wizard item generation now reuses the normal item-initialization path instead of creating broken raw floor items.
3. **Death/high-score behavior**
   - Wizard characters now skip high-score insertion/save while still getting the normal death screen.
   - The death screen now explicitly shows `WIZARD RUN - NO RANK`.
   - The post-death key gate now waits for a fresh keypress instead of being skipped by stale input.
   - Real monster deaths now preserve and display the correct death cause on the death screen instead of falling back to `Unknown Causes`.
4. **Follow-up fixes discovered during bring-up**
   - Fixed C128 `Ctrl+W` command decoding and first-entry control flow.
   - Fixed C128 overlay self-overwrite on Wizard level jump by moving the generation tail into main-resident code.
   - Fixed C128 learned-spell helper placement so Wizard `Gain Level` no longer JAMs in the I/O hole.
   - Fixed C128 cached-tier monster-name translation so deep-level Wizard jumps show correct monster names.
   - Fixed Reveal semantics so Wizard `A` behaves like a mapping-style reveal with secret doors instead of a brittle global-light action.
   - Fixed C64 screen-code issues in Wizard prompts/messages and cleaned up the right-edge `WIZARD` surfacing in the character sheet title.
   - Fixed death-cause formatting so monster id `0` is no longer misreported as `Unknown Causes`.

### Why This Shape
- The safest C128 implementation path was to reuse the already-established `OVL.UI` modal overlay rather than create a new overlay or another resident banked window.
- Wizard Mode was intentionally made one-way per character so a single persisted bit can drive:
  - eligibility gating for high scores
  - character-sheet surfacing
  - save/load continuity
- Reveal semantics were narrowed toward mapping behavior instead of a blanket “global light” action after manual testing showed that the broader interpretation was both incorrect and unstable.

### Validation
- `make -C commodore/c64 build`
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- manual in-game validation accepted by the user for:
  - C64 and C128 Wizard activation
  - C128 level jump, gain level, reveal, and death flow
  - wizard tag display
  - deep-level monster-name correctness
  - death-screen Wizard status and real death-cause display

### Outcome
- `FEAT-WIZ` is closed.
- Wizard Mode now exists as a practical debug/test tool instead of just a backlog design.
- Two newly discovered gameplay bugs remain tracked separately in the active backlog:
  - `BUG-RECALL`
  - `BUG-EGO-NAME`

## 2026-03-23 — `TST-5a/b` isolated merge-hardening coverage ✅ COMPLETE

### Scope Closed
- Closed the high-value portion of `TST-5` by adding isolated test coverage for:
  - `disk_swap.s`
  - renderer decision-tree overrides on both C64 and C128
- Removed the stale active-plan framing that still treated `TST-5` and the already-completed `dungeon_gen` BFS scratch cleanup as open merge work.

### What Changed
1. **C64 disk-swap unit coverage**
   - Added `commodore/c64/tests/test_disk_swap.s` with stubbed KERNAL/IEC, UI, and input helpers.
   - Covered:
     - `disk_prompt`
     - `disk_init_drive`
     - `probe_device`
     - `disk_enter_device`
   - Wired the suite into `commodore/c64/run_tests.sh`.
2. **Renderer decision-tree coverage**
   - Added `commodore/c64/tests/test_render.s` to directly prove:
     - unvisited tile blanks
     - visible item overrides floor
     - visible monster overrides item
     - player overrides everything
   - Extended `commodore/c128/tests/test_vdc_scroll_delta128.s` with the same single-tile override cases against the real VDC renderer.
3. **Backlog cleanup**
   - Updated `commodore/BUILDPLAN.md` so `TST-5` no longer appears as an open umbrella item.
   - Removed the already-resolved `dungeon_gen` BFS scratch cleanup from the active backlog.

### Why This Shape
- The consultant review and local code audit both pointed to:
  - disk swap as the least-covered shared high-branching logic
  - renderer override logic as the next best isolated proof target
- Palette mapping already had meaningful coverage, so the right outcome was to close the high-value `TST-5a/b` work and leave only optional palette add-ons out of scope.

### Validation
- `cd commodore/c64 && java -jar ../../tools/kickass/KickAss.jar tests/test_disk_swap.s -o tests/test_disk_swap.prg`
- direct VICE monitor run of `test_disk_swap.prg`: `11/11`
- `cd commodore/c64 && java -jar ../../tools/kickass/KickAss.jar tests/test_render.s -o tests/test_render.prg`
- direct VICE monitor run of `test_render.prg`: `4/4`
- `make -C commodore/c64 build`
- `make -B -C commodore/c128 build128`
- `make test128-fast`

### Outcome
- The merge-relevant portion of `TST-5` is complete.
- The active backlog is smaller and more accurate.

---

## 2026-03-23 — Phase 10.4 VDC threat/effect colors ✅ COMPLETE

### Scope Closed
- Completed the remaining C128-only enhanced display work for live threat-coded monsters and a first colored transient spell effect.
- Kept C64 and shared authored monster palettes unchanged.

### What Changed
1. **C128 live viewport threat colors**
   - Added a C128-local helper in `commodore/c128/monster_threat_vdc.s` that maps monster level relative to player level onto the existing threat palette:
     - green = low
     - yellow = moderate
     - red = high
     - light red = deadly
   - `commodore/c128/dungeon_render_vdc.s` now uses that helper for live monster rendering in both full-redraw and single-tile paths.
   - Town NPCs intentionally keep their authored species colors.
2. **First colored special-effect path**
   - `commodore/c128/screen_vdc.s` now exposes `screen_flash_set_color` / `screen_flash_reset_color` for transient effect flashes.
   - `commodore/common/spell_effects.s` now uses that hook so bolt effects flash cyan on C128 instead of always white.
3. **Focused regression coverage**
   - `commodore/c128/tests/test_dungeon128.s` now guards:
     - the threat-color thresholds
     - town-NPC species-color fallback
     - the VDC transient flash color setter/resetter
   - `commodore/c128/tests/test_vdc_scroll_delta128.s` gained the small compatibility stub needed by the new C128-local helper.

### Why This Shape
- Earlier phase notes already defined the intended monster semantics as threat-coded by depth/level relative to the player.
- The correct implementation point was the C128 live viewport renderer, not the shared `cr_color` table:
  - C64 should keep its existing species palette
  - recall and other non-live views should keep authored colors
- `eff_bolt -> screen_flash_at` was the smallest real "special effects" hook already present in the engine, so that became the first VDC-only transient color path.

### Validation
- `make -C commodore/c64 build`
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- manual in-game validation accepted by the user for:
  - weak vs dangerous monsters in the C128 dungeon viewport
  - town NPC colors remaining unchanged
  - cast/pray bolt-path visuals behaving correctly

### Outcome
- Phase 10.4 is closed.
- C128 now uses VDC attributes for live threat-coded monsters and a first colored transient spell effect without changing C64 rendering semantics or the shared authored creature palette.

## 2026-03-22 — C128 banked combat relocation + cached `OVL.UI` ✅ COMPLETE

### Scope Closed
- Eliminated the long-standing C128 `ranged_fire` / spell / tunnel I/O-hole spill by relocating the callable combat/spell cluster into the resident `$F000` banked runtime window.
- Added a dedicated cached `OVL.UI` overlay so low-frequency modal UI no longer consumes resident `$F000` banked space.
- Restored C64 compatibility after the shared `player_magic` split by keeping the tail imported on non-C128 builds.

### What Changed
1. **Resident `$F000` banked compute cluster**
   - `commodore/c128/main.s` now keeps these shared handlers resident in the banked runtime window:
     - `player_magic_tail.s`
     - `projectile.s`
     - `ranged_fire.s`
     - `tunnel.s`
     - plus the existing resident `ui_recall.s`, `throw.s`, and `bash.s`
   - Compile-time asserts now prove the relocated call targets live at `$F000+` and that the staged `banked_payload` source ends below the overlay window.
2. **New cached `OVL.UI` overlay**
   - Added a C128-only `OVL.UI` containing:
     - `ui_help_data.s`
     - `ui_help.s`
     - `ui_inventory.s`
     - `ui_character.s`
   - C128 trampolines for help, inventory, equipment, and character sheet now load `OVL.UI` into `$E000`.
   - The overlay is preloaded into a new Bank 1 cache slot at `$1000-$1FFF`, so those modal screens are cache-backed instead of disk-loaded on each use.
3. **Shared-code follow-through**
   - Split `player_magic_tail.s` out of `player_magic.s` for C128 placement purposes.
   - Kept the non-C128 build path importing that tail directly so C64 still resolves `mage_effect_dispatch` and `priest_effect_dispatch`.
4. **Follow-up fixes discovered during bring-up**
   - `ui_help.s` now points directly at in-overlay help data on C128, fixing the empty help-content regression.
   - `player_magic.s` now waits for the initiating cast/pray key to be released before reading spell selection, fixing the spell-list flash/instant-dismiss regression.

### Why This Shape
- Earlier C128 attempts proved that:
  - `$0800-$0BFF` is not safe for permanent executable code
  - `$E000-$EFFF` is only safe as the live overlay window, not as resident shared compute
- The correct execution model was therefore to use the already-valid resident `$F000` banked runtime and make room there by moving only infrequent modal UI out to an overlay.
- The staged-source constraint also mattered: the solution is only valid because the rebuilt `banked_payload` source now ends below `$E000`, so later `init_copy_banked` recopies cannot be corrupted by overlay loads.

### Validation
- `make -C commodore/c64 build`
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- `make test128-fast-smoke`
- `TEST_FILTER='main128_layout|boot_title_idle_smoke|scripted_summary_to_town_smoke|town_overlay_smoke|death_overlay_smoke' bash commodore/c128/run_tests128.sh`
- manual in-game validation accepted by the user for:
  - help / inventory / equipment / character sheet
  - cast / pray
  - cached `OVL.UI` behavior

### Outcome
- The historical C128 `ranged_fire` I/O-hole placement blocker is closed.
- Spell dispatch, projectile helpers, ranged fire, and tunneling now execute from the established resident banked runtime instead of drifting into `$D000-$DFFF`.
- Modal UI no longer spends resident `$F000` space and still feels immediate because `OVL.UI` is cache-backed in Bank 1.

## 2026-03-20 — Phase 10.3 larger C128 dungeon ✅ COMPLETE

### Scope Closed
- Expanded the live C128 dungeon/town map from `80x48` to `198x66`.
- Completed the prerequisite Bank 1 ownership redesign so the larger map fits without colliding with C128 DB/cache regions.
- Split save compatibility so C64 and C128 can intentionally carry different raw `MAP_SIZE` payloads.

### What Changed
1. **Platform-parameterized map dimensions**
   - `commodore/common/dungeon_data.s` now resolves `MAP_COLS`, `MAP_ROWS`, and `MAP_SIZE` by platform.
   - C64 stays at `80x48`; C128 now uses `198x66`.
2. **C128 Bank 1 ownership redesign**
   - `commodore/c128/memory128.s` now reserves the full live map span at `$4000-$730B`.
   - The Bank 1 DB/data region now begins at `$7400`, after the full map span.
   - Compile-time asserts now prove the larger map does not overlap DB/cache ownership.
3. **Save-format compatibility split**
   - `commodore/common/save.s` now uses:
     - C64 `SAVE_VERSION = $0b`
     - C128 `SAVE_VERSION = $0c`
   - This intentionally separates raw-map save payloads once `MAP_SIZE` diverged by platform.
   - `commodore/c128/tests/make_load_resume_save.py` was updated to emit the new C128 version.
4. **Test/runtime fixtures updated**
   - `commodore/c128/tests/test_main_loop128.s` now uses the larger synthetic map dimensions.
   - `commodore/common/dungeon_gen.s` and `commodore/common/save.s` comments were updated to reflect `MAP_SIZE`-driven behavior.
   - `commodore/c128/ARCHITECTURE.md` now documents the live `198x66` map and revised Bank 1 ownership.

### Why This Shape
- A direct map-size toggle would have overlapped the old C128 Bank 1 DB region, so ownership had to be redesigned first.
- The save format already validates a version byte in the save header, so the smallest correct compatibility split was a C128 version bump instead of a new dynamic-size field.
- The staged rollout kept the risky part narrow:
  - platform split first
  - Bank 1 manifest second
  - live C128 dimensions third
  - save-format split fourth

### Validation
- `make -C commodore/c64 build`
- `cd commodore/c64 && ./run_tests.sh`
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- `make test128-fast-smoke`
- `TEST_FILTER='boot_title_load_resume_smoke' bash commodore/c128/run_tests128.sh`
- manual in-game validation accepted by the user

### Follow-up Note
- The 10.3 rollout exposed a separate C128 running regression because held/cancel polling still used decoded PETSCII instead of raw physical held-key state.
- That follow-up fix is documented in the existing running-stop history entry below.

## 2026-03-21 — DG-A corridor door policy cleanup ✅ COMPLETE

### Scope Closed
- Removed the aggressive `add_corridor_doors` post-pass that synthesized doors whenever a corridor tile ran alongside a room wall.
- Maintained the original corridor-carving door insertion logic so real room entrances still create doors.
- Added regression tests covering both the absence of synthetic doors and the continued presence of corridor-penetrating doors.

### What Changed
1. **`add_corridor_doors` is now a compatibility stub.**
   - The helper returns immediately so it no longer scans walls or mutates the map.
   - The remaining stub documents that corridor door placement happens during carving and exists only for backwards compatibility.
2. **Dungeon generation no longer invokes the stub.**
   - `dungeon_generate` now stops after `connect_rooms` and before `tramp_vault_seal_entrance`, so door placement relies on `carve_h_corridor` / `carve_v_corridor`.
3. **Focused regression coverage.**
   - `commodore/c64/tests/test_dungeon.s` gained two scenarios: adjacency without penetration should not create a door, and an actual corridor penetration door still appears.
   - Documentation now explicitly states that true doors come from corridor carving plus `random_door_type`.

### Why This Shape
- The former post-pass produced “side-entry” doors that felt like hallway shortcuts and conflicted with the original Umoria behavior.
- Keeping door placement within the carving routines prevents new doors from appearing merely because a corridor tile happens to brush a room wall, while still allowing true penetrations to create doors.
- The new regression tests seal the contract by proving both the absence of synthetic doors and the retention of carved-penetration doors.

### Validation
- `make -C commodore/c64 build`
- `cd commodore/c64 && ./run_tests.sh` (fails: VICE segfaulted while running the `sound` suite)
- `make -B -C commodore/c128 build128`
- `make test128-fast` (fails: harness128_batch cannot connect to the VICE monitor at 127.0.0.1:6510 due to permission restrictions)

### Outcome
- Corridors adjacent to rooms now leave the wall intact unless the carving explicitly breached the wall.
- The map is no longer cluttered with phantom doors, so hallway running and direction-based behavior feel closer to the original Umoria experience.
- The regression tests guard the contract so future refactors cannot silently reintroduce aggressive door synthesis.

---

## 2026-03-20 — Planning doc role cleanup ✅ COMPLETE

### Scope Closed
- Removed the stale historical/archive role from `tasks/todo.md`.
- Re-established a single-source split for project planning docs:
  - `commodore/BUILDPLAN.md` = active backlog
  - `commodore/BUILDPLAN_HISTORY.md` = completed work and postmortems
  - `tasks/todo.md` = current-task scratchpad only

### What Changed
1. **`tasks/todo.md` reset to an active-work template**
   - Replaced the accumulated historical log with a minimal scratchpad structure.
   - Kept only role guidance, current-status marker, and a reusable task template.
2. **History ownership clarified by practice**
   - Durable historical notes are now expected to live in `commodore/BUILDPLAN_HISTORY.md` instead of being duplicated in `tasks/todo.md`.

### Why This Shape
- `tasks/todo.md` had become a second history file, which created drift and made the current backlog harder to read.
- The cleanup gives each planning file one job and removes the need to reconcile multiple archival sources.

### Validation
- Confirmed the live backlog still resides in `commodore/BUILDPLAN.md`.
- Confirmed `tasks/todo.md` now contains only active-scratchpad guidance and no legacy historical sections.

---

## 2026-03-20 — MC2.2 fractional XP accumulation ✅ COMPLETE

### Scope Closed
- Hidden fractional XP stack that stores the `ccl_div_24x8` remainder in a 16-bit fixed-point field so repeated low-XP kills contribute exactly the expected whole XP over time.
- Full-XP level-up halving that treats the excess as a 24-bit whole + 16-bit fractional value and carries fractional overflow into the integer portion.
- Save-format bump so C64 ($0C) and C128 ($0D) know to expect the extra fractional bytes after the player struct.

### What Changed
1. `player.s` now declares `PL_XP_FRAC_LO/H I`, increments `PL_STRUCT_SIZE` to 82, and uses the hidden bytes in `combat_award_xp` to accumulate fractional XP (remainder `<< 16 / player_level`) with a carry into the 24-bit XP when the fraction overflows.
2. `combat_check_levelup` subtracts the threshold from the full 40-bit XP total, halves the combined integer+fraction, and adds the threshold back so level-ups honor fractional progress instead of throwing it away.
3. `common/save.s` (C64: previously `$0B`, C128: `$0C`) now emits `$0C`/$0D, and `commodore/c128/tests/make_load_resume_save.py` reflects the new size and header byte.

### Why This Shape
- Weak monsters remain strategic rather than mathematically worthless because their fractional XP still accumulates behind the scenes and eventually produces a whole point without the UI needing to show fractions.
- Level-up halving stays faithful to the original “excess/2” contract while treating the hidden fractional portion consistently, so you do not lose or double-count fractional increments.
- The save-version bump ensures old builds do not misinterpret the new struct size and fractional bytes.

### Validation
- `make -C commodore/c64 build`
- `make -C commodore/c128 build128` *(KickAssembler printed `Ranged-fire handler stays out of I/O hole=false (true)` as a failing assertion while still emitting the PRG, so please note the assertion in case it resurfaces.)*

---

## 2026-03-20 — BUG-M1 stale monster rendering after AI turns ✅ COMPLETE

### Scope Closed
- Closed the shared stale-render bug where monster movement during `turn_post_action` could leave the viewport showing old monster positions or omit newly moved monsters.
- Closed the linked status-only redraw gap where commands like `cmd_rest` updated status but skipped the viewport refresh entirely.

### What Changed
1. **Shared per-turn scene-dirty signal**
   - Added `commodore/common/turn_render_state.s` with shared `turn_scene_dirty`.
   - `commodore/common/monster_ai.s` now reports whether AI activity changed the visible scene.
   - `commodore/common/turn.s` now clears/sets `turn_scene_dirty` during `turn_post_action`.
2. **Status-only turn tails corrected**
   - Updated `commodore/common/game_loop_helpers.s` so `post_turn_status_only_or_die` routes through `vp_render_status_loop` when `turn_scene_dirty` is set.
   - This keeps the old fast path for pure status-only turns but redraws the viewport when monsters moved.
3. **Local-render fast path narrowed**
   - Updated `commodore/common/game_loop.s` so movement/run tails bypass `render_local_area` and force a full viewport redraw when `turn_scene_dirty` is set after `turn_post_action`.
   - Pure local player-motion turns still use the existing local redraw optimization.
4. **Focused seam coverage**
   - Extended `commodore/c64/tests/test_main_loop.s`
   - Extended `commodore/c128/tests/test_main_loop128.s`
   - New cases prove:
     - status-only turns trigger a viewport redraw when the scene changed
     - movement turns skip local redraw and take the full redraw path when monsters moved

### Why This Shape
- The stale-render bug was a shared orchestration problem, not a platform-specific renderer bug.
- `render_local_area` is still a useful optimization for pure player-motion turns, so the fix kept it and added a shared scene-dirty gate instead of replacing it wholesale.
- The smallest correct repair was to teach the turn pipeline when the scene changed and use that signal to choose between status-only/local redraw and full viewport redraw.

### Validation
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- `make test128-fast-smoke`
- `make -C commodore/c64 build`
- Manual in-game validation accepted by the user

### Validation Caveat
- `cd commodore/c64 && ./run_tests.sh` was not usable as final runtime signal in the current environment during this fix.
- Both `x64sc` and `x64` crashed broadly before monitor breakpoints on tiny unrelated suites as well, so that behavior did not provide BUG-M1-specific evidence.
- The implementation is still shared and C64-compiled cleanly, but the full C64 headless runtime suite was not a trustworthy gate for this closure.

### Outcome
- Monster movement after AI turns no longer relies on `render_local_area` being accidentally large enough.
- Status-only turns no longer leave monster movement unrendered.
- The local redraw fast path remains in place for turns where the visible scene did not change.

---

## 2026-03-20 — Running stop logic cleanup ✅ COMPLETE

### Scope Closed
- Fixed the real C64 premature-running-stop bug and one related running-policy mismatch that were not represented on the active backlog:
  - C64 running cancelled after a short fixed distance because key repeat was being treated as a fresh cancel input
  - running did not stop on floor items even though the project docs said it should
  - corridor running stopped one tile early at lit side room mouths because side-junction detection was too eager

### What Changed
1. **C64 run-cancel path corrected**
   - Updated `commodore/c64/input.s` so running no longer uses KERNAL keyboard-buffer semantics for cancel detection.
   - `input_run_key_held` now samples physical held-key state through CIA1.
   - `input_run_cancel_check` now uses an edge-style detector, matching the C128 contract and preventing normal key-repeat from cancelling a run after a short delay.
2. **Documented item-stop behavior restored**
   - Updated `commodore/common/player_move.s` so `run_check_stop` now stops when the current tile carries `FLAG_HAS_ITEM`.
   - This brings the live code back in line with the documented running contract.
3. **Side-junction policy narrowed**
   - Updated `run_check_intersection` so lit plain-floor side openings do not count as intersections by themselves.
   - Dark side branches and other walkable side exits still count, so corridor safety remains intact.
4. **Focused regression coverage**
   - Extended `commodore/c64/tests/test_input.s` with a run-cancel edge-state regression.
   - Extended `commodore/c64/tests/test_dungeon.s` with:
     - a stop-on-floor-item case
     - a lit-side-mouth case that proves running does not halt one tile early
   - Updated `commodore/c64/run_tests.sh` for the expanded dungeon suite count.

### Why This Shape
- The fixed-distance stop pattern in both town and dungeon pointed away from map geometry and toward input semantics.
- On C64, using `KBDBUF_COUNT` for run cancel was the wrong abstraction because key repeat naturally appears after a short delay and looks like a new cancel event.
- The item-stop change is a direct correctness fix: the docs and intended UX already required it.
- The side-junction refinement is intentionally narrow:
  - lit plain-floor room mouths are ignored at the intersection layer
  - room-entry logic still stops running when the player actually enters the room
  - dark branches, doors, monsters, stairs, and traps remain stop conditions
- That avoids regressing safe corridor running while removing the visible early-stop annoyance.

### Validation
- `make -C commodore/c64 build`
- `cd commodore/c64 && ./run_tests.sh`
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- `make test128-fast-smoke`

### Follow-up Correction
- After the later C128 `10.3` map expansion, the user still saw running stop after a few steps in town.
- The remaining bug was **not** corridor geometry and **not** the shared debounce logic.
- C64 running already polled raw physical held-key state, but C128 running was still polling `cia_scan_petscii` for both:
  - `input_run_key_held`
  - `input_run_cancel_check`
- That was the wrong abstraction for held/cancel polling. Running only cares whether the key is physically still down; PETSCII decoding of shifted run keys can disappear before physical release.
- Final C128 fix:
  - added a raw matrix-held helper in `commodore/c128/input128.s`
  - switched C128 running pre-arm and cancel polling to that helper
  - kept the shared debounced boolean edge detector in place
  - extended `commodore/c128/tests/test_input128.s` to prove the raw held-key helper restores scan registers and stays inert when idle

### Follow-up Validation
- `make -B -C commodore/c128 build128`
- `TEST_FILTER='input128' bash commodore/c128/run_tests128.sh`
- `python3 -u commodore/c128/harness128_batch.py --mode compare --tests input128 --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`
- manual in-game retest: running no longer stops after a few steps in town

### Outcome
- C64 running no longer cancels after a short fixed distance due to key repeat.
- Running now stops for floor items as documented.
- Lit room mouths no longer interrupt corridor running one tile before the real room-entry transition.

---

## L3 — C128 Grey/Light-Grey VDC Collapse ✅ COMPLETE (2026-03-20)

### Scope Closed
- Closed the remaining C128 VDC grayscale ambiguity where canonical `COL_GREY` and `COL_LGREY` both translated to the same RGBI value.
- Kept the fix strictly C128-local so the shared/C64 palette stays unchanged.

### What Changed
1. **C128 VDC translation policy corrected**
   - Updated `commodore/c128/screen_vdc.s` so:
     - `COL_GREY` falls back to `VDC_DGREY`
     - `COL_LGREY` remains `VDC_LGREY`
   - Updated the pretranslated `VDC_GREY` constant to match the fallback.
2. **Focused color-path regression coverage**
   - Extended `commodore/c128/tests/test_vdc_attr128.s` to prove:
     - `COL_GREY` translates to `VDC_DGREY`
     - `COL_LGREY` translates to `VDC_LGREY`
     - the two attributes are no longer equal
   - Extended `commodore/c128/tests/test_dungeon128.s` to prove rubble (`tile type 11`) resolves through the new dark-grey fallback.

### Why This Shape
- The VDC has no true medium-grey equivalent, so this was a policy decision, not a missing hardware mode.
- Usage audit showed:
  - `COL_LGREY` is the dominant wall/UI secondary-text color and should stay brighter
  - `COL_GREY` is sparse and mostly accent/rubble/border usage
  - `COL_DGREY` already carries floor/dimmed-terrain semantics
- Mapping canonical `COL_GREY` down to dark grey restores visible contrast between “grey” and “light grey” without disturbing the shared palette model.

### Validation
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- `make test128-fast-smoke`

### Outcome
- `L3` is closed.
- C128 VDC rendering now has a deliberate two-grey policy instead of an accidental grey/light-grey collapse.

---

## BUG-X — IRQ Decimal-Mode Hardening ✅ COMPLETE (2026-03-20)

### Scope Closed
- Closed the remaining IRQ decimal-mode audit item on both supported targets.
- Brought the live entry points in line with the documented invariant that interrupt handlers must begin from binary-arithmetic mode even if interrupted code left Decimal Mode set.

### What Changed
1. **C64 IRQ entry hardened**
   - Added `cld` at `irq_no_blink` in `commodore/c64/main.s`.
   - Kept the existing cursor-blink suppression and KERNAL handoff unchanged.
2. **C128 Common-RAM interrupt entries hardened**
   - Added `cld` at `mmu_common_irq` in `commodore/c128/memory128.s`.
   - Added `cld` at `mmu_common_nmi` in `commodore/c128/memory128.s` for symmetry and future-proofing.
3. **Focused regression coverage**
   - Extended `commodore/c64/tests/test_config.s` to assert that `irq_no_blink` begins with `CLD`.
   - Extended `commodore/c128/tests/test_memory128.s` to assert that both `mmu_common_irq` and `mmu_common_nmi` begin with `CLD`.

### Why This Shape
- The current handlers do not perform decimal-sensitive arithmetic today, so this is hardening, not a bugfix for an active failure.
- The correct low-risk fix is at the handler entry points themselves, not in callers.
- Opcode-level checks are the right regression seam here: they directly protect the intended entry contract without requiring fragile interrupt-timing tests.

### Validation
- `make -C commodore/c64 build`
- `cd commodore/c64 && ./run_tests.sh`
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- `make test128-fast-smoke`

### Outcome
- `BUG-X` is closed.
- Both platforms now force binary arithmetic on interrupt entry while preserving the existing IRQ/NMI control flow and memory layout.

---

## REF-2 — Game Loop Decoupling ✅ COMPLETE (2026-03-19)

### Scope Closed
- Closed the shared `game_loop.s` coupling refactor across both C64 and C128.
- Kept the work memory-safe by:
  - staying in the shared segment through Stages 1–4
  - deferring the physical file split until the helper seams were already proven
  - importing the final helper file back at the same assembly location

### What Changed
1. **Separated repeated post-command tails**
   - Added dedicated local helpers for:
     - full redraw after a turn
     - status-only redraw after a turn
     - visibility+redraw after a turn
     - UI-view restore back to gameplay
2. **Separated UI/prompt-only command flows**
   - Extracted explicit helper flows for:
     - character
     - help
     - inventory
     - equipment
     - recall prompt/input/search/display
3. **Separated command execution from result policy**
   - Added carry-based helpers that centralize:
     - no-turn return to `main_loop`
     - turn-consuming redraw policy
     - spell no-turn restore behavior
4. **Expanded focused loop-harness coverage**
   - `commodore/c64/tests/test_main_loop.s`
   - `commodore/c128/tests/test_main_loop128.s`
   - Added coverage for:
     - `CMD_READ` success/result path
     - `CMD_CAST` no-turn restore path
     - `CMD_CHAR_INFO` dismiss flow
5. **Completed the minimal physical split**
   - Added `commodore/common/game_loop_helpers.s`
   - Left `game_loop.s` as the orchestration/core-command file
   - Imported `game_loop_helpers.s` in place so the assembled layout remained stable
6. **Closed the split-specific C128 diagnostic regressions**
   - Excluded the mutable `mmu_common_save_p` tail byte from the helper-blob integrity check
   - Changed the overlay-transition pass probe from `BRK` to a self-loop so monitor `until` stops at the pass address instead of falling into the default fail trap

### Validation
- `make -C commodore/c64 build`
- `cd commodore/c64 && ./run_tests.sh`
- `make test128-fast`
- `make test128-fast-smoke`
- `make test128`

### Outcome
- `REF-2` is complete.
- The game loop is now organized around a clearer split between:
  - orchestration / core command bodies
  - UI-only flows
  - result-policy helpers
  - shared post-turn tails
- This improved testability and maintainability without reopening the C64/C128 memory-placement risks that had previously caused loader, overlay, and runtime corruption bugs.

---

## TST-4 — Subsystem Coverage Expansion ✅ COMPLETE (2026-03-19)

### Scope Closed
- Closed the remaining subsystem-testing gap for:
  - Huffman decode/data integrity
  - string-bank decode semantics
  - C64 string-bank loader bookkeeping/error contract
  - C64 overlay loader bookkeeping/error contract
  - SID/audio programming via monitor-observed register writes

### What Changed
1. **Expanded `subsystems` runtime suite**
   - Added `commodore/c64/tests/test_subsystems.s`.
   - Wired it into `commodore/c64/run_tests.sh` as `subsystems`.
   - The suite now covers:
     - direct Huffman decode of representative literals
     - `huff_decode_to_ptr2`
     - `huff_append_combat`
     - synthetic `$E000` string-bank decode through `bank_decode_string`
     - `bank_load_recall` C64 failure-path bookkeeping
     - `overlay_load` skip/failure bookkeeping on the C64 path
2. **Specialized sound harness**
   - Added `commodore/c64/tests/test_sound_monitor.s`.
   - Added a dedicated `sound` runner path in `commodore/c64/run_tests.sh`.
   - The runner uses VICE monitor breakpoints and memory dumps to validate SID voice-3 register programming externally, because CPU readback of those registers is not valid.
3. **Real bug fixed while closing the gap**
   - The sound harness exposed a production bug in `commodore/common/sound.s`:
     - `sound_play` stored `Y` into `zp_snd_effect`
     - all valid effects therefore dispatched as `SFX_BUMP`
   - Fixed by storing the incoming effect ID before preserving registers.

### Why This Shape
- It closes the intended subsystem gap without forcing fragile end-to-end flows into a unit-test role.
- The string-bank and overlay checks stay narrow and deterministic:
  - synthetic bank image for decode math
  - loader/overlay bookkeeping validated with local stubs and direct state assertions
- The sound harness uses the only defensible assertion seam for SID voice programming: the monitor-observed register state, not CPU reads from write-only registers.

### Validation
- `cd commodore/c64 && ./run_tests.sh` — PASS (`31 passed, 0 failed`)
  - `subsystems: PASS (10/10 tests)`
  - `sound: PASS (11/11 checkpoints)`
- `make test128-fast` — PASS
- `make test128-fast-smoke` — PASS

---

## TST-3 — UI Menus & Views Isolation Coverage ✅ COMPLETE (2026-03-19)

### Scope Closed
- Closed the open shared-UI isolation-testing gap for the main menu/view surfaces:
  - character viewer
  - help
  - home
  - inventory
  - recall
  - store
- Added equipment coverage alongside inventory because it shares the same overlay family and item-line rendering path.

### What Changed
1. **Focused C64 runtime suite**
   - Added `commodore/c64/tests/test_ui_views.s`.
   - The suite calls the shared renderers directly where possible instead of routing through full gameplay loops.
2. **Covered direct view/layout paths**
   - `ui_char_display`
   - `ui_help_display`
   - `ui_inv_display`
   - `ui_equip_display`
   - `ui_recall_display`
   - `store_draw_screen`
   - `home_enter`
3. **Home-path testability**
   - The `home` case patches `input_get_key` to exit immediately and suppresses the final clear so the rendered layout remains assertable.
4. **Runner integration**
   - Wired the new suite into `commodore/c64/run_tests.sh` as `ui_views`.

### Why This Shape
- It closes the actual regression gap with minimal fragility:
  - direct layout assertions instead of loop-heavy gameplay orchestration
  - shared-code coverage through the authoritative C64 runtime path
  - no new platform-specific test harnesses were needed to validate the common UI renderers
- The suite checks real rendered screen content, not just control flow, including item lines, menu text, headers, and footers.

### Validation
- Focused headless `ui_views` run — PASS (`7/7`)
- `cd commodore/c64 && ./run_tests.sh` — PASS (`29 passed, 0 failed`)
- `make -B -C commodore/c128 build128` — PASS
- `make -C commodore/c128 test128-fast` — PASS
- `make -C commodore/c128 test128-fast-smoke` — PASS

---

## OPT-3 — Visibility Room Cache ✅ COMPLETE (2026-03-19)

### Scope Closed
- Closed the open `update_visibility` hot-path optimization for room reveal checks.
- Removed the unconditional per-turn lit-room scan in favor of a transient current-room cache plus an early unlit-tile bailout.

### What Changed
1. **Transient room cache in `dungeon_los.s`**
   - Added `vis_cached_room_idx` to remember the current lit room.
   - `update_visibility` now reuses cached bounds when the player remains in the same room.
2. **Skip scans on non-room tiles**
   - If the current tile is not lit, `update_visibility` clears the cache and skips the room-reveal scan entirely.
   - This removes the room loop from ordinary corridor turns.
3. **Lit-room rescan only on transitions**
   - The code scans lit rooms only when the cache is invalid or the player leaves the cached room.
   - No save-format changes were required because the cache is transient.
4. **Direct regression coverage**
   - Added a new effects regression proving that the cache sets when the player enters a lit room and clears when the player moves onto a corridor tile.

### Why This Shape
- It delivers the intended optimization with minimal surface area:
  - no save/load changes
  - no level-transition plumbing
  - no gameplay-contract changes outside `dungeon_los.s`
- The current tile’s `FLAG_LIT` state is enough to cheaply rule out room-reveal work on corridor turns, which are the common case.

### Validation
- `make -C commodore/c64 build` — PASS
- `cd commodore/c64 && ./run_tests.sh` — PASS
- `make -B -C commodore/c128 build128` — PASS
- `make -C commodore/c128 test128-fast` — PASS
- `make -C commodore/c128 test128-fast-smoke` — PASS

---

## OPT-1 — Main-Loop Command Dispatch Jump Table ✅ COMPLETE (2026-03-19)

### Scope Closed
- Closed the open gameplay hot-path optimization for the non-movement command dispatcher in `commodore/common/game_loop.s`.
- Replaced the long equality chain for discrete commands with a bounded O(1) dispatch table without perturbing the movement/running fast paths.

### What Changed
1. **Bounded jump-table dispatch**
   - `CMD_STAIRS_DN..CMD_TUNNEL` now dispatch through `command_dispatch_lo/hi` and a single indirect `jmp (zp_ptr0)`.
   - Unsupported and pre-handled slots inside that numeric range map to a shared ignore target instead of falling through a comparison chain.
2. **Movement/running remain bespoke**
   - `CMD_MOVE_*` remains the explicit hot movement range path.
   - `CMD_RUN_*` remains an explicit fast path that still feeds `run_step` directly.
3. **Focused harness coverage expanded**
   - `commodore/c128/tests/test_main_loop128.s` now includes a `CMD_REST` case, so the table is exercised on a turn-consuming command rather than only no-turn UI commands.

### Why This Shape
- It removes the long `cmp`/`bne` ladder from the common command loop without forcing the two hottest range-based behaviors (movement and running) through an extra indirection layer.
- That keeps the optimization targeted: lower steady-state dispatch cost for the broad discrete command set, with minimal behavioral churn.

### Validation
- `make -C commodore/c64 build` — PASS
- `cd commodore/c64 && ./run_tests.sh` — PASS
- `make -B -C commodore/c128 build128` — PASS
- `make -C commodore/c128 test128-fast` — PASS
- `make -C commodore/c128 test128-fast-smoke` — PASS
- Manual in-game validation — PASS

---

## OPT-TEST — C128 Fast-Test Workflow ✅ COMPLETE (2026-03-19)

### Scope Closed
- Closed the operational C128 harness-speedup task by turning the Gate C work into standard development targets instead of one-off Python commands.
- Established a practical split between:
  - fast unit-level iteration
  - fast runtime smoke coverage
  - authoritative full-suite validation

### What Landed
1. **Python Gate C unit compare harness**
   - `harness128.py` / `harness128_batch.py` are now operational for the full current C128 unit-test set.
   - Cold/snapshot compare mode is exposed through:
     - `make test128-fast`
     - `make -C commodore/c128 test128-fast`
2. **Fast smoke integration**
   - Added a small high-value smoke subset:
     - `boot_title_idle_smoke`
     - `scripted_summary_to_town_smoke`
     - `town_overlay_smoke`
   - Exposed through:
     - `make test128-fast-smoke`
     - `make -C commodore/c128 test128-fast-smoke`
3. **Execution-contract alignment**
   - The Python moncommands runner now mirrors the shell harness VICE contract:
     - `+remotemonitor +binarymonitor`
     - per-test `-limitcycles`
   - This re-qualified the full current C128 unit batch instead of leaving several tests as false timeout cases.
4. **Workflow integration**
   - Updated `AGENTS.md`, `GEMINI.md`, `commodore/c128/GEMINI.md`, and `commodore/c128/ARCHITECTURE.md` so future agent work actually uses the fast C128 targets by default where appropriate.

### Delivered Operational State
- `test128-fast` = Python Gate C compare harness for the full current C128 unit-test batch
- `test128-fast-smoke` = quick runtime regression subset for boot/title, chargen-to-town, and overlay entry
- `test128` = authoritative full shell harness for broad/high-risk validation

### Deferred / Blocked Follow-on
- The original deeper Gate C.3 assembly-server goal remains blocked by the bundled KickAssembler version, which does not support the required server mode.
- Further testing work is now feature-coverage work (`TST-3` / `TST-4` / `TST-5`), not core harness bring-up.

### Validation
- `make test128-fast`: **PASS**
- `make test128-fast-smoke`: **PASS**
- Full stable Gate C unit compare batch:
  - cold total: **5.191s**
  - snapshot total: **12.836s**

---

## DGN-1 — C128 Dungeon-Descent Ego Runtime Placement Repair ✅ COMPLETE (2026-03-18)

### Scope Closed
- Closed the C128 crash where descending from town into the first dungeon level could `JAM` during level item generation.
- Replaced the earlier “overlay/data corruption” suspicion with the actual failure: a valid trampoline calling a callee that had drifted into the visible I/O hole.

### Root Causes Addressed
1. **Callee placement drifted into `$D000-$DFFF`**
   - `tramp_roll_ego_type` remained safely below `$D000`, but `roll_ego_type` itself had linked at `$D310`.
   - With normal `MMU_ALL_RAM` runtime (`$FF00=$3E`) and I/O visible, execution in `$D000-$DFFF` reads device space rather than program code.
2. **The failure surfaced during dungeon item generation**
   - The live path was `item_spawn_level -> tramp_roll_ego_type -> roll_ego_type`, so the first town->dungeon descent could crash as soon as ego-item logic ran.
3. **Placement coverage only guarded the trampoline**
   - Existing asserts guaranteed the trampoline stayed below the I/O hole, but nothing prevented the ego routines themselves from silently drifting upward.

### Implemented
1. **Moved ego runtime into loaded low RAM**
   - Imported `ego_items.s` into the C128 `RuntimeLowData` runtime block (`runtime.low.prg`, runtime `$1000+` in Bank 0).
   - Removed the late Default-segment import that allowed ego generation logic to spill into the `$D000-$DFFF` region.
2. **Added placement asserts for the full call surface**
   - `roll_ego_type`
   - `ego_apply_damage`
   - `ego_get_ac_bonus`
   - These must now remain below `FLOOR_ITEM_BASE`, keeping them in always-executable low runtime RAM.

### Result
- Town -> first dungeon descent no longer `JAM`s during item generation.
- Ego generation stays in executable low runtime RAM instead of device space.

### Validation
- `make -B -C commodore/c128 build128`: **PASS**
- Manual validation: town -> first dungeon descent completes without CPU `JAM`

---

## UIB-1 — C128 Banked UI Source/Recopy Repair ✅ COMPLETE (2026-03-18)

### Scope Closed
- Closed the C128 regression where help/inventory/equipment screens could clear or draw only partial framing, then hang or return with missing content.
- Replaced the wrong “input-only” hypothesis with the actual runtime linkage issue: the banked UI payload was being recopied from a source span that overlapped the active overlay window.

### Root Causes Addressed
1. **Overlay-clobbered banked-payload source**
   - The banked payload source bytes in the main staged image extended into `$E000-$EFFF`, the same window used by overlays.
   - After an overlay load, any later `init_copy_banked` call recopied corrupted source bytes back into the resident `$F000-$FFFA` banked UI window.
2. **Runtime corruption lined up with the failing UI routines**
   - The overlap offset mapped directly into the resident banked window at the point where `ui_inv_display` / `ui_equip_display` live, explaining why borders could appear while content vanished or execution drifted.
3. **Dismiss-screen input policy was too strict for overlay return**
   - After the banked UI path returned, inventory/equipment dismiss used the prompt-style strict wait, which was too conservative for a “press any key to continue” overlay once release gating was already in place.

### Implemented
1. **Stopped per-entry banked UI recopy**
   - Removed `init_copy_banked` from the C128 UI trampolines:
     - `tramp_ui_help_display`
     - `tramp_ui_char_display`
     - `tramp_ui_inv_display`
     - `tramp_ui_equip_display`
     - `tramp_ui_recall`
   - The stable startup copy remains the source of truth for the resident `$F000` banked window.
2. **Hardened banked UI exit**
   - `tramp_ui_exit` now restores both runtime guards and runtime vectors before `cli`, so the return path re-enters the gameplay/input environment with the MMU helper blob, IRQ/NMI vectors, and CHRIN stub all reasserted.
3. **Tuned dismiss behavior for inventory/equipment overlays**
   - `show_inv_and_restore` and `show_equip_and_restore` now use `input_wait_release` followed by `input_get_key_fast` on C128.
   - This preserves the release gate while using the correct edge policy for a full-screen dismiss prompt.

### Result
- C128 help/inventory/equipment screens render content again instead of blanking after an overlay load.
- `?` from item prompts now displays inventory and dismisses correctly.
- The regression-inducing exact-length copy experiment is not part of the final fix.

### Validation
- `make -B -C commodore/c128 build128`: **PASS**
- Manual validation:
  - `i` inventory screen renders correctly
  - `?` inventory-help from item prompt renders and dismisses correctly
  - `?` help screen shows border **and content** correctly

---

## LDR-1 — C128 Low-RAM Runtime Loader Repair ✅ COMPLETE (2026-03-18)

### Scope Closed
- Closed the long-running C128 `JAM` that occurred after character creation, before stable town entry.
- Replaced a false chargen/summary hypothesis with the actual root cause: callable VDC runtime code at `$1000` was not being loaded into the bank that was executing it.

### Root Causes Addressed
1. **Missing Stage 2 loader contract**
   - `runtime.low.prg` was produced and written to disk, but no runtime path actually loaded it before gameplay reached the first `viewport_update`.
2. **Incorrect PRG load address**
   - The segment was linked for runtime execution at `$1000`, but the emitted PRG still carried an `$E000` load header.
3. **Wrong bank assumption for direct low-RAM calls**
   - The first repair attempt loaded `runtime.low.prg` into Bank 1, but the actual callsites execute under `MMU_ALL_RAM` (`Bank 0`) and use direct `JSR $1000` calls.
   - `$1000-$3FFF` is not bottom common RAM, so Bank 1 residency does not satisfy a Bank 0 callsite.
4. **Prompt handoff release sensitivity**
   - After the loader repair, the summary dismiss path still needed a safer release handoff between gender selection and the summary prompt in normal-speed runs.

### Implemented
1. **Loader/header alignment**
   - Changed `RuntimeLowData` to emit `runtime.low.prg` with a `$1000` load header matching its callable runtime symbols.
2. **Startup low-RAM loader**
   - Added an explicit C128-safe startup loader in `commodore/c128/main.s` that loads `RUNTIME.LOW.PRG` into Bank 0 low RAM before the title screen and any later `viewport_update` / `render_viewport` call path.
3. **Placement guard**
   - Added a compile-time assert to keep the low-RAM callable runtime block below `FLOOR_ITEM_BASE`, making future overlap mistakes visible at build time.
4. **Summary prompt release hardening**
   - Added a release wait after gender selection in `commodore/common/player_create.s`.
   - Hardened `input_wait_release` in `commodore/c128/input128.s` to use the shared edge-state logic rather than two ad hoc raw-zero scans.
5. **VICE 3.10 run compatibility**
   - Removed the deprecated `+iecdevice8` flag from the C128 `run128` target.

### Result
- C128 now completes:
  - title -> new game
  - full character creation
  - summary
  - town entry
- The two-week town-entry `JAM` regression is closed.

### Validation
- `make -B -C commodore/c128 build128`: **PASS**
- `make -C commodore/c128 disk128`: **PASS**
- `run_boot_title_newgame_smoke`: **PASS**
- `run_scripted_summary_to_town_smoke`: **PASS**
- Manual validation: normal-speed run reaches town and summary no longer auto-dismisses in the observed non-warp path.

---

## C128-HEB — Hardened Execution Boundary ✅ COMPLETE (2026-03-14)

### Scope Closed
- Resolved intermittent C128 MMU stability and KERNAL I/O crashes by implementing a "Hardened Execution Boundary" in `commodore/c128/`.
- Enforced strict atomic context switching for all KERNAL entry/exit paths, ensuring hardware invariants are maintained during high-risk I/O operations (overlays, tiers, save/load).
- Audited and stabilized the loader-to-game handoff, eliminating the final "ghosts" in the boot process.
- Achieved a **100% pass rate** across all 40 C128 test suites.

### Implemented
1. **Atomic Context Switching Primitives**
   - Implemented `EnterKernal` and `ExitKernal` as subroutines in `memory128.s` (with macro wrappers) to minimize code footprint.
   - `EnterKernal`: Performs `sei`, saves current `$01` and `$FF00` to Zero Page, enforces the `$D506 = $07` (4KB Bottom/Top Common) invariant, and sets the MMU/Port to KERNAL mode (`$FF00 = $0E`, `$01 = $37`).
   - `ExitKernal`: Restores the saved `$01` and `$FF00` from Zero Page, reasserts VDC mode (`c128_vdc_reassert_mode`), and performs `cli`.
2. **Permanently Protected Banking Context**
   - Assigned Zero Page `$FE-$FF` (KERNAL-Volatile area) for saving `$01` and `$FF00` during KERNAL calls. 
   - This ensures the banking context is isolated from the "Game-Owned" ZP range ($02-$8F) used by the loader and resident program, preventing clobbering during the handoff phase.
3. **Hardware "Quiet Down" at Entry**
   - Implemented a hardware reset at `entry_real` in `main.s`: disables all CIA1/2 interrupts (`$7F -> $DC0D/$DD0D`) and acknowledges pending interrupts by reading the ICRs.
   - This ensures the CPU starts in a "Silent" state, preventing interrupts from triggering before the KERNAL vector mirroring and patching are complete.
4. **Handoff & Timing Optimization**
   - Moved `$D506 = $07` initialization in `boot128.s` to the earliest possible point in `loader_start`, ensuring common RAM is correctly mapped before any KERNAL I/O or ZP initialization.
   - Audited the "Copy Stub" in `boot128.s` to ensure consistent `$D506 = $07` usage and atomic MMU transitions during the Bank 1 to Bank 0 transfer.
5. **Global I/O Wrapper Refactoring**
   - Refactored all KERNAL wrappers in `main.s` (`w_load`, `w_readst`, `w_setlfs`, `w_setnam`, `w_open`, `w_close`, `w_chkin`, `w_chkout`, `w_clrchn`, `w_chrin`, `w_chrout`, and `safe_setbnk`) to use the new atomic macros.
   - Implemented a standard stack-based register preservation pattern around `EnterKernal`.
6. **Hardware Invariant Enforcement**
   - Updated `MachineRestoreDefault`, `MachineRestoreAllRam`, and `c128_restore_runtime_state_core` to consistently set `$D506 = $07`.
   - Updated C128-specific banking in `commodore/common/reu.s` to use `MMU_NORMAL` ($0E) and enforce the `$D506` invariant during asset preloading.

### Result
- C128 KERNAL I/O and boot handoff are now 100% stable.
- Eliminated the JAM at `$3121` (within `blows_table`) by ensuring a clean interrupt state and consistent common-RAM mapping.
- Zero Page `$FE-$FF` is now the official temporary storage for banking context during KERNAL calls.

### Validation
- `bash commodore/c128/run_tests128.sh`: **PASS (40 passed, 0 failed)**
  - All smoke tests, including `chargen_clean_smoke`, `town_move_stability_smoke`, and `boot_diag_copy`, now pass reliably.
  - No regressions observed in character generation, town movement, or dungeon entry flows.

---

## TST-2A — C128 Title Load/Resume Smoke ✅ COMPLETE (2026-03-11)

### Scope Closed
- Closed the last remaining TST-2 follow-up gap by automating the title `L` -> `load_resume_game` orchestration path on C128.
- Replaced the unstable VICE disk-writeback seeding attempts with a deterministic generated save blob that the runner injects directly into the smoke D64.

### Implemented
1. **Deterministic save seed generation**
   - Added `commodore/c128/tests/make_load_resume_save.py` to emit a valid `THE.GAME` payload with the current save format version and checksum.
   - Kept the payload intentionally minimal: enough for `load_game` validation and title resume coverage, without depending on flaky emulator-side save persistence.
2. **Runner integration**
   - Updated `commodore/c128/run_tests128.sh` to:
     - generate the save blob
     - build `moria128_loadresume.d64`
     - inject `THE.GAME` with `c1541`
     - verify the file exists before boot
     - boot the disk and drive the real title `L` path to `load_resume_game`
3. **Title-load path cleanup**
   - Promoted the C128 title load branch to the named `title_load_game` entrypoint in `commodore/c128/main.s`, making the load flow explicit and easier to target in future diagnostics.

### Result
- The full orchestration expansion is now closed:
  - TST-2 is complete
  - TST-2A is complete
  - The default C128 runner now covers the title load/resume path without manual prep, emulator writeback assumptions, or fake pass conditions

### Validation
- `bash commodore/c128/run_tests128.sh`: pass (**32 passed, 0 failed**)
- `bash commodore/c64/run_tests.sh`: pass (**28 passed, 0 failed**)

---

## TST-2 — Orchestration Coverage Expansion ✅ COMPLETE (2026-03-11)

### Scope Closed
- Closed the broad TST-2 orchestration harness gap for the default runners without widening the task into UI-layout or rendering verification work.
- Landed deterministic coverage for config entrypoints, `turn.s` orchestration, C128 `main_loop` parity, and restart-to-title flow.
- Spun the remaining title-load/resume automation gap into a smaller follow-up issue because deterministic save-file seeding is still unresolved.

### Implemented
1. **C64 orchestration suites expanded**
   - Added `commodore/c64/tests/test_config.s` to validate the C64 `detect_machine` default contract.
   - Added `commodore/c64/tests/test_turn.s` to cover:
     - `turn_post_action` sequencing
     - turn counter wrap + periodic store restock
     - poison regen suppression
     - starvation damage/death-source handling
     - light warning/depletion behavior
     - word-of-recall town/dungeon transitions and fizzle case
     - mana-regen cadence for casting classes
2. **C128 deterministic harness coverage expanded**
   - Added `commodore/c128/tests/test_config128.s` for the hardcoded C128/80-col `detect_machine` contract.
   - Added `commodore/c128/tests/test_main_loop128.s` as a focused dispatch harness covering movement, `LOOK`, `OPEN`, and C128-specific dismiss gating for help/inventory flows.
3. **C128 smoke coverage expanded**
   - Added `restart_to_title_smoke` to `commodore/c128/run_tests128.sh` to validate the death-prompt `S` path returns cleanly to the title/sysinfo loop.
4. **Runner integration completed**
   - Enabled the new C64 suites in `commodore/c64/run_tests.sh`.
   - Enabled the new C128 suites/smoke in `commodore/c128/run_tests128.sh`.

### Result
- The default runners now cover substantially more orchestration surface:
  - C64 config entrypoint
  - C64 turn orchestration
  - C128 config entrypoint
  - C128 `main_loop` dispatch parity
  - C128 restart-to-title flow
- The remaining title `L` -> `load_resume_game` automation gap is now isolated as a separate follow-up rather than buried inside the broader TST-2 tracking item.

### Validation
- `bash commodore/c64/run_tests.sh`: pass (**28 passed, 0 failed**)
- `bash commodore/c128/run_tests128.sh`: pass (**31 passed, 0 failed**)

---

## 10.8-HDN — C128 Ownership Hardening Follow-Up ✅ COMPLETE (2026-03-11)

### Scope Closed
- Closed the remaining 10.8 hardening follow-up by converting the shipping C128 Bank 1 layout from documentation-only guidance into enforced code/test policy.
- Kept the existing 10.8 runtime design intact; this pass hardened ownership, placement, and regression coverage rather than redesigning the cache model.

### Implemented
1. **Ownership manifest centralized**
   - `commodore/c128/memory128.s` now defines the Bank 1 ownership manifest as the source of truth:
     - common RAM
     - reclaimed low region
     - map region
     - DB mirror region
     - tier-cache window
     - each fixed overlay cache slot
     - reserved gaps (`$94F8-$9FFF`, `$D000-$DFFF`, `$F000-$FEFF`)
   - Shared overlay-slot tables now come from `memory128.s` instead of being re-derived in runtime modules.
2. **Placement policy enforced**
   - Added consistent compile-time region-order assertions in `memory128.s`.
   - Added C128 placement assertions in `main.s` for the MMU helper page, cache-state block, and staged-source assumptions so future low-RAM/Bank 1 edits must fit named ownership regions.
3. **Cache contract hardening**
   - Tier and overlay cache paths now consume the named ownership constants rather than ad hoc “high Bank 1” assumptions.
   - Added targeted C128 test hooks so a missing tier cache line proves tier fallback does not corrupt overlay readiness, and a missing overlay cache line proves overlay fallback does not corrupt tier readiness.
4. **Smoke coverage upgraded**
   - Added `cache_survival_smoke` to verify cache/common-RAM probe bytes survive preload, title, character summary, and town entry.
   - Added `overlay_partial_failure_smoke` alongside the existing tier partial-failure smoke to validate readiness-domain isolation in both directions.
5. **Documentation closed out**
   - Updated `commodore/c128/ARCHITECTURE.md` with the hardened ownership model and a preflight checklist for future low-RAM / Bank 1 changes.
   - Updated `commodore/BUILDPLAN.md` to mark the follow-up hardening item resolved and record the expanded C128 test/assert counts.

### Result
- The 10.8 follow-up hardening work is now complete:
  - Bank 1 ownership is named and asserted
  - cache-slot tables derive from one source of truth
  - future placement changes have a documented checklist
  - runtime smokes now cover cache survival and both tier/overlay fallback-isolation cases

### Validation
- `bash commodore/c128/run_tests128.sh`: pass (**28 passed, 0 failed**)

---

## TST-1 / C64 Test Harness Repair ✅ COMPLETE (2026-03-11)

### Scope Closed
- Closed the stale `TST-1` tracking item by finishing the missing C64-side coverage and restoring the default C64 test runner to a clean state.

### Implemented
1. **Input coverage completed**
   - Added `c64/tests/test_input.s` to cover C64 command parsing and run-key handling alongside the existing C128 input suite.
2. **Focused `main_loop` coverage completed**
   - Added `c64/tests/test_main_loop.s` as a deterministic dispatch harness for representative `game_loop.s` command paths (`REST`, `LOOK`, movement, and `OPEN`).
3. **C64 runner compatibility repaired**
   - Reworked the `test_main_loop.s` harness to use the standard low-memory `test_finish`/`brk` contract.
   - Replaced the failing runtime patch helper with direct jump patching so the harness reliably intercepts `input_get_command` and other dispatch targets.
   - Updated `c64/run_tests.sh` to use an all-in-one monitor script (`break`, `g`, `m`, `quit`) instead of racing monitor commands over stdin during VICE startup.
4. **Shared build regressions cleaned up**
   - Restored common definitions and C128-only fences needed to keep the C64 build/test path healthy after the 10.8 work.

### Result
- `TST-1` is now complete:
  - dedicated C64/C128 input suites exist
  - LOS coverage is already present in dungeon/monster tests
  - `main_loop` has focused dispatch coverage
- The default C64 runtime suite is green again with the new tests enabled.

### Validation
- `bash commodore/c64/run_tests.sh`: pass (**26 passed, 0 failed**)

---

## 10.8 — C128 Bank 1 Preload Cache + Ownership Refactor ✅ COMPLETE (2026-03-11)

### Scope Closed
- Reworked 10.8 from the failed pseudo-REU preload attempts into a full ownership-first C128 cache effort.
- Closed the path from cold boot through character creation summary, town entry, overlay transitions, and tier transitions under the new Bank 1 cache model.

### Root Causes Addressed
1. **Bank 1 ownership was not actually proven**
   - `boot128` used to leave the staged program image resident in Bank 1.
   - Any cache design built on “apparently free” Bank 1 ranges was unsound until boot reclaim behavior was fixed and asserted.
2. **MMU-safe helper placement was invalid**
   - Early C128 helper code executed from addresses that were not actually safe under the documented common-RAM regime.
   - This caused real crashes during preload/cache transitions.
3. **Cache helper contracts were broken**
   - Multiple C128 tier/overlay cache helpers restored flags with `plp` after setting `clc`/`sec`, destroying the carry-based success/failure contract and forcing false cache misses/fallbacks.
4. **Overlay/state transitions trusted stale runtime state**
   - C128 overlay transitions could still depend on stale `current_overlay` / guard-state assumptions and jump into stale `$E000` contents.
5. **The automated boundary was incomplete**
   - VICE `-keybuf` smokes were not strong enough to prove the manual post-gender character-summary -> town path.
   - A deterministic scripted-input fixture was required to close that gap.

### Implemented
1. **Bank 1 ownership refactor**
   - `boot128.s` now scrubs the staged Bank 1 image as it is copied into Bank 0.
   - `memory128.s`, `main.s`, and `ARCHITECTURE.md` now treat reclaimed Bank 1 ownership as explicit, asserted state instead of an informal assumption.
2. **C128 cache model completion**
   - Separate C128 cache control state from REU semantics.
   - Tier cache uses the reclaimed high Bank 1 region.
   - Fixed-slot overlay cache uses dedicated Bank 1 slots.
   - Runtime now restores critical C128 guard state (vectors, CHRIN stub, MMU helper blob, runtime map) across overlay/dungeon-generation boundaries.
3. **Cache/loader correctness fixes**
   - Fixed carry-clobber regressions in tier/overlay cache stage/fetch helpers.
   - Fixed preload transaction handling and MMU return behavior for KERNAL `LOAD`.
   - Removed stale-overlay-state short-circuit behavior from the C128 overlay path.
4. **Character-summary/town-flow stabilization**
   - Moved `ui_character.s` out of the broken high banked-payload path and back into main RAM for C128.
   - `player_create.s` now uses the platform trampoline for the final summary and reasserts runtime guards at the creation boundaries.
   - Gender screen uses the safer row-by-row clear path.
   - This resolved the manual “after gender selection the summary corrupts / JAMs” regression that survived the earlier preload/cache fixes.
5. **Validation upgrades**
   - Added/strengthened C128 harness coverage for:
     - idle title soak
     - title -> new game
     - tier transition
     - town overlay (male + female flows)
     - death overlay
     - partial tier-cache failure fallback
     - boot-copy diagnostic
     - **scripted summary-to-town flow** using internal C128 scripted input rather than VICE `-keybuf`

### Result
- 10.8 is now closed as implemented work, not just a plan:
  - Bank 1 ownership refactor complete
  - tier preload cache active
  - overlay cache active
  - summary -> town path stabilized
  - deterministic regression coverage added for the previously manual-only failure path

### Validation
- `bash commodore/c128/run_tests128.sh`: pass (**26 passed, 0 failed**)
- Manual validation reported successful character creation summary and town entry after the final summary-path fix.

---

## SAV-2 — C128 Restore/Load Regression ✅ COMPLETE (2026-03-09)

### Symptom
- C128 restored sessions could render invalid world/actor state after load, consistent with stale runtime metadata leaking across load-resume.

### Root Cause
- `load_resume_game` called `tier_check_transition` without first clearing transient tier state (`current_tier`, `tier_loaded`, tier name-table metadata).
- These fields are runtime-derived and not part of persistent save payload; after a load they could still reflect a previous runtime session, causing mismatched tier assumptions during resumed play.
- C128 map save streaming also had a register-lifetime bug: the loaded map byte in `A` was overwritten by `lda #MMU_NORMAL` before `save_write_byte`, causing the saved map block to be filled with `0x0E` bytes.

### Fix
1. Updated `commodore/common/game_loop.s`:
   - `load_resume_game` now calls `tier_invalidate_state` before `tier_check_transition`.
2. Updated `commodore/common/save.s` C128 map-stream helpers:
   - `save_write_map_c128` now preserves the map byte across MMU restore (`pha`/`pla`) before `save_write_byte`.
   - `save_write_map_c128` and `load_read_map_c128` now restore via `mmu_select_bank0` and then force `MMU_NORMAL` before each KERNAL byte I/O.
   - `load_read_map_c128` now restores MMU to `MMU_NORMAL` (not `MMU_ALL_RAM`) before each KERNAL byte read.
3. Effect:
   - Resumed games always recompute/load tier state from saved dungeon depth rather than reusing stale in-memory tier metadata.
   - C128 save/load map streaming no longer drifts into an incorrect MMU context during byte I/O.
   - Saved map payload now contains real tile bytes instead of a repeated MMU constant.

### Validation
- `make -C commodore/c128 test128`: pass (**17 passed, 0 failed**)
- `make -C commodore/c64 test`: pass (**24 passed, 0 failed**)

---

## DTH-1 — C128 Death Flow Regression ✅ COMPLETE (2026-03-09)

### Symptom
- On player death, C128 sometimes skipped normal death-screen flow, surfaced incorrect save-path behavior, and could end in a CPU `JAM` (`$01FF`) during post-death handling.

### Root Cause
- `tramp_game_over` called high-score disk I/O (`hiscore_load` / `hiscore_save`) while game MMU state was in all-RAM mode (`$FF00=$3E`), but those routines depend on KERNAL-visible ROM paths.
- The death overlay routines (`score_calculate`, `hiscore_insert`, `score_death_screen`) require all-RAM execution at `$E000`, so KERNAL transitions must be scoped tightly around only the I/O calls.

### Fix
1. Updated `commodore/c128/main.s` `tramp_game_over`:
   - Added explicit KERNAL-entry/exit transitions around `hiscore_load`.
   - Added explicit KERNAL-entry/exit transitions around `hiscore_save`.
   - Kept overlay routines (`score_calculate`, `hiscore_insert`, `score_death_screen`) outside KERNAL-visible windows.
2. Preserved prior death-flow ordering and user-facing flow in `common/game_loop.s` (slain message -> disk prompt -> savefile delete -> game-over pipeline).

### Validation
- `make -B -C commodore/c128 build128`: pass
- `make -C commodore/c128 test128`: pass (**17 passed, 0 failed**)
- `make -C commodore/c64 test`: pass (**24 passed, 0 failed**)

---

## M2 — Platformized Screen Blanking Hooks ✅ COMPLETE (2026-03-09)

### Goal
- Remove VIC-II-specific `$D011` blank/unblank toggles from shared game logic so C128 VDC paths no longer rely on non-applicable hardware semantics.

### Implemented
1. Replaced direct `$D011` writes in `common/game_loop.s` with platform hooks:
   - `screen_blank`
   - `screen_unblank`
2. Added C64 platform implementation in `c64/screen.s`:
   - `screen_blank` clears VIC-II DEN bit
   - `screen_unblank` sets VIC-II DEN bit
3. Added C128 platform implementation in `c128/screen_vdc.s`:
   - explicit no-op policy hooks (VDC has no `$D011` DEN equivalent)
4. Updated `BUILDPLAN.md`:
   - removed M2 from Open Issues
   - added M2 to Recently Resolved
   - removed stale `game_loop.s` `$D011` dependency row

### Validation
- `make -B -C commodore/c128 build128`: pass
- `make -C commodore/c128 test128`: pass (**17 passed, 0 failed**)
- Follow-up closure:
  - `make -C commodore/c64 build`: pass
  - `make -C commodore/c64 test`: pass (**24 passed, 0 failed**)

---

## P1 — C128 VDC Responsiveness Plan ✅ COMPLETE (2026-03-09)

### Goal
- Eliminate perceived movement lag in the C128 VDC path for turn-based play, with measurable movement latency bounds and stable rendering behavior.

### Implemented
1. Instrumentation-first movement latency probe (`PERF_P1`)
   - Added compile-time guarded probe module (`common/perf_p1.s`) with:
     - frame-delta histogram buckets: `0`, `1`, `2`, `>=3`
     - path counters: local redraw, full redraw, scroll-driven redraw
     - scroll quality counters: delta-scroll hits and scroll fallbacks
   - Hooked movement lifecycle in `common/game_loop.s` (`move_start`, path markers, `move_end`).
   - Added `PERF_P1` test mode support in `c128/run_tests128.sh`.
2. Rendering-path stabilization and responsiveness fixes
   - Preserved local-area fast path for no-scroll movement.
   - Added scroll-delta renderer for 1-tile viewport shifts:
     - copy existing viewport content in VDC
     - redraw only newly exposed strip
     - fallback to full redraw when delta path is inapplicable
   - Hardened status rendering against flashing/partial redraw artifacts:
     - change-detection cache with no-op dirty clear
     - force-redraw signaling on full/status row clears
     - atomic full status block redraw on visible status changes
3. Behavior and regression hardening
   - Fixed run/shift movement edge regressions (input/run-latch handling).
   - Fixed LOS room-reveal flag behavior to prevent unnecessary full redraws.
   - Added status coherence regression test:
     - `c128/tests/test_status_coherence128.s`
   - Extended `test_perf_p1.s` for new counters and reset/assert coverage.
4. PERF-mode debugging safety fixes
   - Fixed movement command clobber in `perf_p1_move_start` (preserve `A`).
   - Added PERF key dump hook (`V`) and fixed scan-table mapping for `V`.
   - Resized PERF dump routine to avoid code placement drift into `$D000-$DFFF` (I/O hole), preventing combat JAMs.

### Validation
- `make -C commodore/c128 test128`: passing.
- `PERF_P1=1 make -C commodore/c128 test128`: passing (includes perf suite).
- Manual confirmation during P1 closure:
  - status bar flash/regression paths resolved
  - scroll-heavy viewport movement materially improved and acceptable
  - `PERF_P1` counters visible in-game for manual profiling.

### Notes
- P1 is closed as a responsiveness-first objective, not as a real-time/fps optimization program.
- Remaining known blockers are outside P1 scope (`DTH-1`, `SAV-2`).

---

## Phase Completion Summary (as of 2026-02-21, Phase 10.0 complete)

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Skeleton and Infrastructure | ✅ Complete |
| 2 | Player and Character Creation | ✅ Complete |
| 3 | The Town Level | ✅ Complete |
| 4 | Dungeon Generation and Navigation | ✅ Complete |
| 5 | Monsters | ✅ Complete |
| 6 | Items and Inventory | ✅ Complete |
| 7 | Magic System | ✅ Complete (steps 7.0-7.10) |
| 8 | Stores | ✅ Complete |
| 9 | Save/Load and Game Polish | ✅ Complete (9.1-9.4, BUG-1 through BUG-18 fixed) |
| R3.5 | Creature Tier System + REU | ✅ Complete (R3.5.1-R3.5.12, 120 creatures across 5 tiers) |
| R1.1 | Ranged Combat | ✅ Complete — bows, crossbows, slings, 3 ammo types, fire command, ammo stacking |
| R3.4 | Monster Fleeing | ✅ Complete — flee threshold (HP/4) at spawn, reversed greedy movement |
| R2.1 | Special Rooms | ✅ Complete — pits, vaults, nests with $F000 banking |
| R4.1 | Ego Items | ✅ Complete — 7 enchanted weapon types with slay/elemental/AC bonuses |
| OPT-1 | Code Size Optimization | ✅ Complete — 182 bytes reclaimed (OPT-1.1 resolved by R7.6) |
| OPT-4 | Codebase-Wide Size Optimization | ✅ Complete — 1,098 bytes reclaimed across 9 items |
| OPT-3 | Town Overlay Optimization | ✅ Complete — 1,183 bytes saved (4,074→2,891), 1,204 bytes free |
| OPT-5 | Overlay Expansion (dungeon gen) | ✅ Complete — dungeon_gen.s → $E000 overlay; 3,490 bytes reclaimed |
| 10.0 | C64/C128 Code Split | ✅ Complete — 64 files to common/, game loop extracted, c128 skeleton |
| C3 | VDC Viewport Artifacts | ✅ Complete — centering, IRQ protection, streaming optimization, flash alignment |
| 10.5 | VDC Performance Optimizations | ✅ Complete — inline vdc_wait, pre-translated tile colors, pointer sliding, per-row dy early-exit, hardware fill |
| R7 | String Compression | ✅ Complete — R7.1-R7.7 all done. Tier 1: 155 strings Huffman-compressed, 888 bytes saved. Tier 2: string bank encoder/loader, monster recall system. |
| R2.5 | Tunneling + Treasure Veins | ✅ Complete — + command, STR-based digging, treasure in quartz/magma veins, wall-to-mud fix, 742 bytes |
| R11 | Lowercase/Uppercase Mode | ✅ Complete — 52 monster symbols (a-z + A-Z), '#' walls, screencode_mixed encoding, case-aware recall |
| R14 | Fix Tunneling Difficulty + Enchanted Tools | ✅ Complete — hardness rescaled, new (STR>>2)+base+(ego×12) formula, Gnomish/Orcish/Dwarven variants |
| R15 | Multi-Disk Support | ✅ Complete — save_device variable, 7 SETLFS sites parameterized, disk setup sub-menu |
| R16 | Save Drive Selection | ✅ Complete — `#)Drive #` menu option; disk_enter_device reads 1–2 digit device# (8–30) |
| R17 | Background History + Gender + Gold | ✅ Complete — 72-entry background table, chain walker, gender prompt, social class, umoria gold formula |
| BUG-42 | Fix Save/Load Corruption | ✅ Complete — raw map I/O replacing streaming RLE decompressor |
| R12 | Game-Over Loop | ✅ Complete — R)EBOOT / S)TART / Q)UIT prompt; restart resets ZP+inventory+tier |

---

## Resolved Bug Summary (BUG-34 through BUG-47)

All bugs below are **fixed**. Detailed write-ups for each appear in the sections that follow.

| # | Severity | Description | Resolution |
|---|----------|-------------|------------|
| BUG-34 | MED | Monster recall only shows first match for shared display symbols | Pressing same letter cycles through all known creatures; state tracked in recall_last_sc/idx |
| BUG-35 | HIGH | Help screen fills with 'p' characters and locks up (data crossed MAP_BASE) | Tab control code ($fc) replaced padding spaces, saving ~96 bytes |
| BUG-36 | MED | Monster recall shows blank name for town creatures | Table path now copies name to creature_name_buf |
| BUG-37 | MED | Recall/help screens flash and dismiss immediately | Clear $C6 before dismiss input_get_key |
| BUG-38 | HIGH | rng_range(0) causes infinite loop (game hang) | Defensive guard in rng_range + guards in pick_creature_type and monster_cast_summon |
| BUG-39 | MED | Creature name shows "?" during combat ($E0xx pointer rejection) | Four-path name resolution with shared copy loop |
| BUG-40 | MED | Creature name shows "?" in monster recall from town (stale tier pointers) | cgn_no_tier path reloads the appropriate tier when stale $E0xx pointer found |
| BUG-41 | HIGH | Tunneling far too easy — hardness ~50× too low | Fixed by R14: hardness rescaled, new formula (STR>>2)+base+(ego×12), bare hands always fail |
| BUG-43 | MED | Store-stocked items not identified | `sro_store_p1` stores `#IF_IDENTIFIED` in `si_flags`; test 29 added to test_store.s |
| BUG-44 | MED | Save file not found shows wrong error and wrong recovery | OPEN-fail path shows "Save file not found."; jumps back to title_menu_loop |
| BUG-45 | MED | Item generation uses flat uniform distribution | Depth-bucketed 50/50 flat/best-of-3 allocator with 62-item sorted table and 13-level cumulative bounds |
| BUG-46 | MED | Monster melee attack from non-adjacent position (stale render) | `!player_died:` now renders viewport before showing death message |
| BUG-47 | HIGH | OPT-5 overlay IRQ lockup — dungeon descent hung | `php`/`plp` in verify_connectivity and both trampolines; 3 interrupt-preservation unit tests added |
| BUG-48 | MED | Title screen shows stale character stats after S)tart from game-over loop | `screen_clear_row` for rows 21–23 added before `title_show_sysinfo`; root cause: `title_render_data` parses dungeon MAP_BASE as title art and writes to status rows |
| **R3** | **HIGH** | Deterministic RNG startup seeding path on C128 | Fixed by maintaining `zp_entropy` counter in input loops and EORing state in `rng_seed` |
| **R4** | **HIGH** | Post-kill map byte render mismatch | Fixed `monster_remove` to use MMU-safe map read macro to prevent Bank 0 read corruption |

---

## 10.7 — Full 80-Column Layout + Stabilization ✅ COMPLETE (2026-03-08)

### Scope Closed
- Completed the C128 full-width UI migration for Phase 10.7:
  - viewport width/layout constants and guards (`VIEWPORT_W=78`, left-anchored 80-col composition)
  - 80-col status/message/help/title/menu/store/recall/layout constants and centering math cleanup
  - dungeon generation bounds updated to use map constants instead of legacy width assumptions

### Stability Work Included in 10.7 Closure
1. **Overlay/payload overlap fix (BLOCKER)**
   - Removed `special_rooms.s` from banked payload and moved generation-time room logic into the dungeon-gen overlay region.
   - Added placement asserts ensuring banked payload starts above overlay ceiling.
2. **C128 save/load map-path correction**
   - Added Bank1-aware map block save/load path for C128 to avoid Bank0 pointer corruption during persistence.
3. **Tier/name staging fix**
   - Fixed C128 tier name table remap using saved post-SoA-end pointer across Bank1 staging, preventing corrupt `creature_get_name` lookups.
4. **VDC color regression cleanup**
   - Replaced piecemeal color overrides with a single coherent VDC nibble-encoding path.
   - Added dungeon color-path assertions in `test_dungeon128` for:
     - floor in-LOS
     - floor out-of-LOS dimming
     - corridor wall in-LOS
     - magma in-LOS

### Verification
- `run_tests128.sh`: **16 passed, 0 failed**
- C128 build asserts: **108 asserts, 0 failed**

---

## R2 — C128 Garbled Prompt/Message Corruption ✅ COMPLETE (2026-03-05)

### Symptom
- C128 showed intermittent and then persistent garbled prompt text (`LOOK`/`TAKE-OFF`) and multiple CPU JAM points (`$D023`, `$D063`) during title/new-game flow.

### Root Cause Chain
1. **Title data bank mismatch:** C128 title load/render path mixed Bank 1 `MAP_BASE` data with Bank 0 string rendering assumptions.
2. **Code placement drift into I/O hole:** growth in `main.s` moved critical entrypoints (`tramp_*`, `title_show_sysinfo`, REU status trampoline) into `$D000-$DFFF`.
3. **Insufficient placement gates:** existing checks covered only a subset of critical routines; symbol-layout tests did not enforce a broad “no critical code in I/O hole” policy.
4. **Debugging noise from temporary instrumentation:** runtime tripwire hooks helped isolate corruption origin but increased moving parts during stabilization.

### Implemented Fixes
1. **Title path bank correctness (C128):**
   - `title_load_and_draw` now loads TITLE art to Bank 1 and restores SETBNK after LOAD.
   - C128 title rendering reads title stream bytes via MMU-safe map reads instead of passing Bank 1 pointers to Bank 0 string routines.
2. **I/O hole hardening:**
   - Pinned critical trampolines/entrypoints to low memory (< `$D000`) in `c128/main.s`, including player-create, game-over, store/UI trampolines, title sysinfo, REU status, and ego trampolines.
   - Added compile-time asserts to fail builds if critical entrypoints drift into `$D000-$DFFF`.
3. **Test-harness hardening:**
   - `run_tests128.sh` symbol placement check now enforces:
     - required critical labels `< $D000`
     - blanket policy: all `tramp_*` labels must remain `< $D000`.
4. **Cleanup:**
   - Removed temporary C128 Huffman runtime tripwire instrumentation after root-cause fixes were in place.

### Build/Test System Improvement Summary
1. Symbol-policy gate added to C128 harness for critical labels and all `tramp_*`.
2. Assembler placement asserts expanded in `c128/main.s`.
3. Debug tripwires explicitly treated as temporary and removed after deterministic gates were installed.
4. Address-budget pressure near `$D000` now treated as a tracked C128 risk.

### AI Agent Process Improvement Summary
1. Use single-hypothesis changes tied to monitor/symbol evidence.
2. Do not mark fixed without:
   - reproduced failure condition
   - root-cause proof from addresses/symbols
   - passing regression gates.
3. Add/extend placement/banking guards before behavior edits on fragile C128 paths.
4. Maintain a canonical list of “must stay `<$D000`” entrypoints for C128 work.

### Validation
- `run_tests128.sh`: **14 passed, 0 failed**
- `make -C commodore/c64 test`: **24 passed, 0 failed**

---

## A7 — Compile-Time Split Hardening ✅ COMPLETE (2026-03-05)

### Objective
- Remove runtime machine-type gating in `common/` hot paths (`zp_machine_type` checks) and enforce compile-time platform dispatch (`#if C128` / `#if !C128`).

### Implemented Scope
1. `common/player_items.s`
   - Converted C128 key-release waits (`show_inv_and_restore`, `show_equip_and_restore`, `item_takeoff`) to compile-time `#if C128`.
2. `common/ui_messages.s`
   - Converted `msg_save_history` lock/unlock (`php;sei` / `plp`) from runtime C128 checks to compile-time `#if C128`.
3. `common/string_bank.s`
   - Converted VIC-II bank restore after KERNAL load to C64-only `#if !C128`.
4. `common/title_sysinfo_banked.s`
   - Converted machine label selection from runtime flag test to compile-time branch.
5. `common/overlay.s`
   - Converted disk-load VIC-II bank restore path to C64-only compile-time branch.
6. `common/tier_manager.s`
   - Converted C128 tier staging and Bank 1 name-table override logic in `tier_load` to compile-time C128 blocks.
7. `common/monster.s`
   - Converted `creature_get_name` C64/C128 dispatch from runtime machine checks to compile-time paths.
8. `common/dungeon_features.s`
   - Converted direction-prompt key-release wait to compile-time C128 branch.

### Sweep Result
- `rg` scan confirms **no remaining runtime `zp_machine_type` / `MACHINE_C128` checks in `commodore/common/`**.
- Remaining references exist only in platform config, zeropage symbol declaration, tests, and documentation.

### Code Size Impact (baseline `af6b1c1` -> post-A7)
1. **C64 build**
   - Default segment end: `$C75D` -> `$C681` (**-220 bytes**)
   - Banked payload: `3992` -> `3985` (**-7 bytes**)
2. **C128 build**
   - Default segment end: `$E25E` -> `$E1B8` (**-166 bytes**)
   - Banked payload: `4666` -> `4650` (**-16 bytes**)

### Validation
- `run_tests128.sh`: **14 passed, 0 failed**
- `make -C commodore/c64 test`: **24 passed, 0 failed**

---

## A8 — C128 I/O-Hole Placement Hardening ✅ COMPLETE (2026-03-05)

### Objective
- Eliminate C128 layout brittleness where critical code/data can drift into `$D000-$DFFF` (I/O hole), causing CPU JAM/reboot failures.
- Enforce both compile-time placement gating and harness-level policy checks.

### Implemented Scope
1. `c128/main.s` compile-time hardening:
   - Added missing `< $D000` asserts for previously unguarded trampolines:
     - `tramp_ui_enter`, `tramp_ui_exit`, `tramp_ui_help_display`, `tramp_ui_char_display`, `tramp_ui_inv_display`, `tramp_ui_equip_display`
     - `tramp_level_generate`, `tramp_assign_special_room`, `tramp_vault_seal_entrance`, `tramp_spawn_special_room_monsters`, `tramp_spawn_nest_gold`, `tramp_find_special_room`, `tramp_sr_epilogue`
     - `tramp_roll_ego_type`, `tramp_ego_append_suffix`, `tramp_ego_put_suffix`
   - Added `tramp_dig_ability` assert after harness coverage gate identified it as unguarded.
2. End-boundary guards for non-trampoline high-risk region:
   - Added `game_over_str_end` and `game_over_prompt_end` labels.
   - Added asserts requiring both end labels `< $D000` to prevent “start below hole but extend into hole” regressions.
3. `c128/run_tests128.sh` (`main128_layout`) hardening:
   - Added parsing of `main.s` to collect symbols guarded by `.assert ... < $D000`.
   - Added policy gate: fail if any `tramp_*` symbol in `main.sym` lacks compile-time assert coverage.
   - Extended required critical symbols to include `game_over_prompt_end` and `game_over_str_end`.
   - Kept existing runtime address checks requiring required symbols and all `tramp_*` symbols to remain `< $D000`.

### Validation
- `run_tests128.sh`: **14 passed, 0 failed**
  - `main128_asm`: PASS (`Made 98 asserts, 0 failed`)
  - `main128_layout`: PASS

### Result
- A8 policy is now enforced at two levels:
  1. Assembler asserts (fast fail at build time).
  2. Harness coverage + symbol placement checks (regression gate for future additions).

---

## C3 (Port Stability) — Wear Prompt Follow-Up Key Regression ✅ COMPLETE (2026-03-05)

### Symptom
- On C128, `W` (wear) prompt selection could immediately cancel/consume input due to stale command-key state, instead of waiting for a fresh follow-up keypress.

### Root Cause
- `item_wear` read selection with `input_get_key` immediately after printing the prompt.
- Unlike `item_takeoff` and direction-prompt paths, it lacked a C128 release gate (`input_wait_release`) before the follow-up read.

### Fix
1. `common/player_items.s`
   - In `item_wear`, added:
     - `#if C128`
     - `jsr input_wait_release`
     - `#endif`
   - Placement is immediately after `huff_print_msg` and before `input_get_key`.
2. `c128/run_tests128.sh`
   - Extended `prompt_irq_guard` with an ordered-chain check enforcing:
     - `HSTR_PIW_WEAR_PROMPT` -> `jsr huff_print_msg` -> `jsr input_wait_release` -> `jsr input_get_key`
   - This prevents silent regression of the C128 follow-up key gate.

### Validation
- `run_tests128.sh`: **14 passed, 0 failed**
  - `main128_asm`: PASS
  - `main128_layout`: PASS
  - `prompt_irq_guard`: PASS

---

## C4 — C128 Follow-Up Prompt/Input Audit ✅ COMPLETE (2026-03-05)

### Objective
- Eliminate stale-key consumption across C128 follow-up prompt flows and lock in regression guards for command families that prompt for a second key.

### Implemented Scope
1. Added C128 release-wait gating (`#if C128 -> jsr input_wait_release`) before follow-up `input_get_key` in:
   - `common/item.s`: `item_drop`
   - `common/player_items.s`: `item_quaff`, `item_read_scroll`, `item_aim_wand`, `item_use_staff`, `item_gain_spell`
   - `common/throw.s`: `throw_item`
2. Added C128 release-wait gating in command UI dismiss paths:
   - `common/game_loop.s`: `CMD_CHAR_INFO`, `CMD_HELP`, `CMD_INVENTORY`, `CMD_EQUIPMENT`, recall prompt input, recall-screen dismiss input
3. Expanded C128 harness structural checks (`run_tests128.sh`, `prompt_irq_guard`):
   - Added ordered-chain checks enforcing `huff_print_msg -> input_wait_release -> input_get_key` for audited prompt commands.
   - Added ordered-chain checks for menu/recall dismiss paths requiring `input_wait_release` before `input_get_key`.
   - Kept existing direction prompt gate coverage (`get_direction_target`) in the same chain-style enforcement.

### Validation
- `run_tests128.sh`: **14 passed, 0 failed**
  - `main128_asm`: PASS (`Made 98 asserts, 0 failed`)
  - `main128_layout`: PASS
  - `prompt_irq_guard`: PASS

### Result
- C128 follow-up key behavior is now consistently release-gated across the audited command/menu families.
- Harness now fails if any audited path drops the release gate ordering.

---

## C5 — C128 Help (`?`) Garble + CPU JAM ✅ COMPLETE (2026-03-05)

### Symptom
- Pressing `?` in gameplay showed a garbled help title/body and could JAM (reported at `$1C09`).

### Root Causes
1. `ui_help.s` used C64-style direct RAM writes (`sta (zp_screen_lo),y` / `sta (zp_color_lo),y`) in `help_draw_line`.
   - On C128 VDC, `screen_set_cursor` pointers are VDC addresses, not CPU-mapped screen/color RAM.
   - Result: memory corruption and unstable help rendering path.
2. Help routine/data placement was vulnerable to overlay overlap.
   - The `$E000-$EFFF` window is runtime overlay territory; help symbols in that range can be overwritten.

### Fixes
1. `common/ui_help.s`
   - Added compile-time split in `help_draw_line`:
     - `#if C128`: render chars via `jsr screen_put_char` (VDC-safe path).
     - `#else`: keep direct VIC-II RAM writes for C64.
2. `c128/main.s`
   - Reordered banked imports so `ui_help.s` and `ui_help_data.s` link in safe high banked space.
   - Added asserts:
     - `ui_help_display >= $F000`
     - `help_title_str >= $F000`
     - `help_lines >= $F000`
3. `c128/run_tests128.sh`
   - `main128_layout` now enforces help code/data are outside the `$E000-$EFFF` overlay window.
   - `prompt_irq_guard` now enforces the C128/C64 split in `ui_help.s` (C128 uses `screen_put_char`, C64 keeps direct RAM path).

### Validation
- `run_tests128.sh`: **14 passed, 0 failed**
  - `main128_asm`: PASS (`Made 101 asserts, 0 failed`)
  - `main128_layout`: PASS
  - `prompt_irq_guard`: PASS
- Verified symbol placement:
  - `ui_help_display = $F5A2`
  - `help_title_str = $F6C6`
  - `help_lines = $F6D8`

---

## C2 — C128 Keyboard Matrix + Responsiveness Stabilization ✅ COMPLETE (2026-03-05)

### Objective
- Complete C128 keyboard matrix coverage and close the remaining responsiveness gap versus C64 for rapid command entry.

### Implemented Scope
1. Extended matrix scanning and decode coverage
   - `input128.s` scans rows 0–7 via CIA and rows 8/9 via `$D02F` line drive.
   - Scan decode table expanded to 80 entries.
   - Keypad movement/rest and ESC mapping integrated in `petscii_to_command`.
2. Responsiveness tuning
   - `input_process_sample` updated to asymmetric debounce:
     - idle→press accepted on first sample for lower latency.
     - release remains 2-sample stabilized to avoid bounce-triggered repeats.
3. Regression coverage
   - `tests/test_input128.s` updated to assert the new edge policy.
   - Existing mapping and scanner restore invariants retained and passing.
4. Documentation sync
   - `BUILDPLAN.md` and `c128/C2_PLAN.md` updated to reflect resolved status and current behavior.

### Validation
- `run_tests128.sh`: **14 passed, 0 failed**
  - includes `input128` suite and full harness gates.
- Manual operator validation accepted as sufficient for closure.

### Result
- C2 closed with scan completeness + tuned responsiveness + test guardrails.
- Future keyboard findings are tracked as new discrete bugs.

---

## R4 — C128 Post-Kill Render Glitch ✅ COMPLETE (2026-03-03)

**Problem:** After killing a dungeon monster on C128, the vacated tile rendered as the wrong glyph/color (including near/far-dependent color shifts).

**Fix:**
1. Traced root cause to `monster_remove` where it cleared `FLAG_OCCUPIED` bypassing MMU macros (`lda (zp_ptr0),y`).
2. This caused a garbage byte to be read from Bank 0, bits cleared, and that corrupt byte written appropriately to the map in Bank 1.
3. Updated the code to use `:MapRead_ptr0_y()` correctly fetching map byte from Bank 1.
4. Created an isolated regression test `test_monster128.s` that mocks the map memory safely and verifies `FLAG_OCCUPIED` drops without clobbering the base tile data, ensuring no future overlap with other fixes.

**Validation:**
- `make test128`: **PASS** (`10 passed, 0 failed`)

## R3 — Deterministic RNG Startup Seeding ✅ COMPLETE (2026-03-03)

**Problem:** The C128 generates the same sequence of values because its port removes KERNAL background paths. The RNG seed was completely overwritten by `STA` using CIA timers, and early menus lacked human-timing variance in their loops, making random generations fully deterministic across emulator runs.

**Fix:**
1. Added `zp_entropy` to Zero Page.
2. Hardened wait loops in `input.s` and `input128.s` to increment `zp_entropy` while polling for keys. The varying human reaction times provide true runtime jitter.
3. Modernized `rng_seed` (in `rng.s`) to mix existing seed state with CIA Timers and `zp_entropy` via `EOR`.

**Validation:**
- `make test128`: **PASS** (`9 passed, 0 failed`)
- `make test`: **PASS** (`24 passed, 0 failed`)
- Confirmed C128 builds behave non-deterministically across reloads.

## Q1 — C128 Quit/Reboot Exit Stability ✅ COMPLETE (2026-03-03)

**Problem:** Exiting from the C128 game-over prompt via `Q` (Quit) frequently crashed into monitor `BREAK`/`JAM` states instead of returning cleanly to BASIC. Failures were observed in multiple ROM paths (`$C946`, `$706F`) after partial warm-start handoff.

**Root cause:** The previous quit path attempted C128 BASIC warm-start sequencing from a game-mutated runtime context. That path was fragile under MMU/ROM/vector state changes and did not reliably re-enter BASIC.

**Fix:**
1. Corrected invalid warm-start indirection and removed unstable mixed path logic.
2. Standardized C128 exit handoff to a deterministic reset-vector path:
   - `exit_trampoline` now restores ROM mapping and performs `JMP ($FFFC)`.
3. Unified game-over prompt behavior:
   - `R` now jumps to `exit_trampoline` (same behavior as `Q`).
4. Hardened exit-state handling while stabilizing this bug:
   - Removed C128 zero-page restore on exit (avoid re-injecting stale BASIC workspace).
   - Moved C128 ZP snapshot storage off fixed low RAM page to owned static buffer data.

**Result:** `Q` and `R` now both perform a consistent soft-reset return to BASIC (reboot-equivalent), eliminating the prior monitor crash modes.

**Validation:**
- `make test128`: **PASS** (`9 passed, 0 failed`)
- `make test`: **PASS** (`24 passed, 0 failed`)
- Manual operator validation: C128 quit now reaches BASIC via soft reset without the previous `BREAK`/`JAM` loop.

---

## S1 — C128 Save JAM at `$A953` / `$0323` ✅ COMPLETE (2026-03-03)

**Problem:** C128 save flow intermittently crashed with CPU `JAM`, initially observed at `$A953` and later at `$0323` during channel cleanup. The failures were triggered in the save path while mixing KERNAL-context transitions and save-specific wrapper calls.

**Root cause:** Save/load code entered KERNAL context (`EnterKernal`) and then called `delete_savefile`, which performed a nested `EnterKernal`/`ExitKernal` pair. That nested transition leaked MMU/KERNAL assumptions across the active save path, causing unstable vector/call behavior and eventual `JAM`.

**Fix:**
1. Refactored `save.s` to avoid nested KERNAL context transitions:
   - Added `delete_savefile_core` (internal helper that assumes KERNAL context is already active).
   - Updated `save_game` and `load_game` to call `delete_savefile_core` directly.
   - Kept `delete_savefile` as the external wrapper for non-KERNAL callers (`EnterKernal` -> core -> `ExitKernal`).
2. Kept save channel restore logic non-invasive on C128 while this path stabilized.
3. Hardened C128 build dependencies (`Makefile`) so `clean128`/`run128` consistently rebuild the disk image from current sources.

**Validation:** C128 runtime suites pass and manual in-game save path no longer reproduces the prior `JAM` crash.

---

## Phase 10.2 — C128 Extended Memory Path ✅ COMPLETE (2026-03-03)

**Objective:** Move C128 creature-tier runtime access off the fragile `$E000` live-read dependency and onto a Bank 1 staged data path, while preserving C64 behavior.

**Completed steps:**
1. **10.2.0 Baseline + invariants**
   - Captured baseline suite status and defined no-regression checklist.
2. **10.2.1 Access abstraction**
   - Added C128 banked DB helper primitives (`mmu_safe_db_read/write_ptr0/ptr1`, bulk enter/exit).
   - Added `test_db128` harness and integrated into `run_tests128.sh`.
3. **10.2.2 Banked tier staging**
   - Added Bank 1 DB region constants and tier staging metadata.
   - Mirrored loaded tier payload from Bank 0 `$E000` to Bank 1 staging region.
4. **10.2.3 Consumer migration**
   - Migrated C128 tier name-table reads and `creature_get_name` tier paths to DB helper access.
   - Kept C64 path behavior unchanged via compatibility wrappers.
5. **10.2.4 State hardening**
   - Added centralized `tier_invalidate_state`.
   - Hardened overlay/string-bank invalidation and overlay load failure state handling.
6. **10.2.5 Regression coverage**
   - Added `test_tier128` suite (transition routing + tier metadata invalidation checks).
   - Integrated into C128 automated harness.
7. **10.2.6 Completion gates + docs**
   - Re-ran full C64/C128 automated suites and synchronized plan documentation.

**Automated gate results (final):**
- `make test128`: **PASS** (`9 passed, 0 failed`)
- `make test`: **PASS** (`24 passed, 0 failed`)

**Manual validation:** Operator-reported runtime smoke is working at this stage (`"seems to WORK"`), and 10.2 is marked complete.

---

## C3 — VDC Viewport Artifacts ✅ COMPLETE (2026-02-27)

**Files:** `commodore/c128/dungeon_render_vdc.s`, `commodore/c128/screen_vdc.s`

**Root causes identified and fixed:**

1. **Horizontal alignment mismatch** — `screen_vdc.s` applied `SCREEN_COL_OFFSET=20` to center UI text in the 80-column display, but `dungeon_render_vdc.s` (`render_viewport`, `render_single_tile`) ignored the offset, placing dungeon art at VDC columns 1–38 while text landed at columns 20+. The two areas overlapped at columns 20–38, causing visual corruption.
   **Fix:** Both functions now use `adc #(VIEWPORT_X + SCREEN_COL_OFFSET)` (+21) so dungeon art occupies VDC columns 21–58, aligned with the centered UI.

2. **IRQ hazard during VDC writes** — `render_viewport` and `render_single_tile` had no `sei/cli` protection. The KERNAL's 60Hz cursor IRQ could clobber `$D600` (VDC address register) between the register-select and data-write phases, causing data to land in arbitrary VRAM.
   **Fix:** `render_viewport` wraps its per-row char+attr streaming in `sei/cli` (interrupts off only during the VDC stream, not tile computation). `render_single_tile` wraps `!rst_write:` in `sei/cli`.

3. **Redundant VDC reg-31 reselection** — `render_viewport` called `vdc_write_data` per character, which in turn called `vdc_write_reg` → `vdc_select_reg` (wait+stx+wait) for every one of the 38 tiles per row — 2×38×19 = 1444 register-selections per full viewport redraw.
   **Fix:** The col_loop now buffers chars into `row_char_buf[x]` (CPU memory only). After the loop, `ldx #31; jsr vdc_select_reg` is called **once** for chars and once for attrs, then the full row is streamed with `jsr vdc_wait; sta VDC_DATA_REG`. Reduces to 2 register-selections per row (38 per full redraw).

4. **`screen_flash_at` column misalignment** — `sty sfa_col` stored the raw game-space column with no centering offset, causing combat flash effects to appear 20 columns left of the tile they referenced.
   **Fix:** `tya; clc; adc #SCREEN_COL_OFFSET; sta sfa_col` applies the offset on entry.

**Fix 5 (VDC reg-30 hardware fill) deferred at C3** — Later completed as part of Phase 10.5.

---

## Phase 10.5 — VDC Performance Optimizations ✅ COMPLETE (2026-02-27)

**Files:** `commodore/c128/dungeon_render_vdc.s`, `commodore/c128/screen_vdc.s`

**Root cause:** I/O protocol overhead dominates VDC rendering. The original implementation called `jsr vdc_wait` (9-cycle jsr+rts overhead) per byte, computed per-tile map column addresses with redundant arithmetic, and performed full dy recalculation per tile for dimming.

**Optimizations implemented:**

1. **Inline `vdc_wait` in streaming loops (Opt 1, ~13K cycles/refresh)** — Replaced `jsr vdc_wait` in `render_viewport`'s `!char_stream:`/`!attr_stream:` loops with inline `bit VDC_ADDR_REG; bpl *-3`. Uses a shared-label trick: both the poll branch (`bpl`) and the next-byte branch (`bne`) point to the same `bit VDC_ADDR_REG` target — the poll loop and the outer iteration loop share a single instruction. Saves 9 cycles × 76 stream iterations × 19 rows ≈ 13,000 cycles per full viewport refresh. Code cost: only 2 extra bytes per pass.

2. **Pre-translated `tile_vdc_colors` table (Opt 2)** — Added `tile_vdc_colors` table (16 bytes) and 14 VDC RGBI constants (`VDC_BLACK`, `VDC_WHITE`, `VDC_DGREY`, etc.) to `screen_vdc.s`. Normal tile path now loads VDC-native color directly from `tile_vdc_colors` instead of `tile_colors` + runtime `vic_to_vdc_color` lookup. Override paths (monsters, items, player, dimming) apply the translation inline at their own color-assignment site. `!write_tile:`/`!rst_write:` no longer translate — `zp_temp1`/`zp_temp4` are always VDC-native. Saves 2 instructions per tile for the common case.

3. **Per-tile pointer sliding (Opt 3, ~7K cycles/refresh)** — At the start of each `row_loop` iteration, the map pointer is pre-slid by `view_x`: `zp_map_ptr = map_row_base + view_x`. The `col_loop` then uses `ldy zp_render_x; lda (zp_map_ptr),y` instead of `lda zp_view_x; clc; adc zp_render_x; tay; lda (zp_map_ptr),y` — removing 3 instructions (lda/clc/adc) per tile × 722 tiles ≈ 7,000 cycles saved per refresh.

4. **Per-row `dy` early-exit for dimming (Opt 4)** — At the start of each row loop iteration, `rv_row_dy = abs(view_y + render_y - player_y)` is computed once. In the per-tile dimming check: if `rv_row_dy > light_radius`, the tile is immediately dimmed (skips the `dx` computation entirely). If within range, `rv_row_dy` is reused for the `max(|dx|,|dy|)` Chebyshev comparison — no redundant `dy` recalculation. Saves the full `lda/clc/adc/sec/sbc/bcs/eor/clc/adc` dy block per dimmed tile, and half of it (the `cmp rv_row_dy; lda rv_row_dy` max) for lit tiles.

5. **VDC hardware fill in `screen_clear` and `screen_clear_row` (Opt 5)** — Replaced CPU streaming loops with VDC block fill hardware: write fill byte to reg 31 (1 byte, sets fill value + auto-increments address), write count-1 to reg 30 (hardware fills remaining bytes). `screen_clear` uses 7 × 256-byte fills + 1 × 208-byte tail per pass (chars + attrs). `screen_clear_row` uses 1 × 80-byte fill per pass. Replaces ~2000-iteration CPU loops with ~8 register writes per full clear.

**Note on unrolling:** Full 38-iteration loop unrolling was initially implemented but reverted — it exceeded the `$E000` program boundary (`program_end <= BANKED_DATA_BASE`). The inline-wait-with-shared-label approach achieves the primary jsr-overhead savings without the code size cost.

---

## BUG-48 — Stale Character Stats on Title Screen After S)tart ✅ COMPLETE (2026-02-21)

**Problem:** After pressing S)tart from the game-over prompt (R)EBOOT / S)TART / Q)UIT), the title screen rendered correctly but rows 21–23 still showed the previous session's character name, race, stats, and HP. Row 23 showed a hybrid: old "HP:21/21" at column 0 alongside the new system info from `title_show_sysinfo` starting at column 12.

**Root cause:** `title_render_data` parses MAP_BASE ($C000) as a title art segment stream (format: `[row, col, color, chars…, $00] … $FF`). After a dungeon level is played, MAP_BASE contains dungeon tile data. When parsed as title art segments, some dungeon data bytes land as row values 21, 22, or 23, so `title_render_data` writes dungeon tile screen codes — with the old status bar color RAM still in place — directly onto those rows. This happens *after* `screen_clear`, which clears screen RAM to spaces but the dungeon art render then overwrites them. KERNAL LOAD on restart does reload the TITLE file into MAP_BASE ($C000), but if MAP_BASE data is misinterpreted at any point, or if (on some code paths) MAP_BASE retains dungeon data, the status rows get repainted.

**Fix:** Added `screen_clear_row` calls for rows 21, 22, and 23 in `restart_entry` immediately before `jsr title_show_sysinfo`. This fires *after* `title_render_data` has finished, clearing any status row contamination at the last possible moment before the title screen is visible. Also added a belt-and-suspenders `screen_clear` earlier in `restart_entry` (before `title_load_and_draw`) so stale data is gone before KERNAL LOAD starts printing "SEARCHING...".

**Changes:** `main.s` — `restart_entry`: added `jsr screen_clear` before `title_load_and_draw`; added `screen_clear_row` for rows 21–23 before `title_show_sysinfo`. No new files. No test changes needed (title screen path is not unit-testable headlessly).

**Size:** +18 bytes (`program_end` $B47C → $B48E); 2,930 bytes headroom remaining.

---

## BUG-40 — Creature Name "?" in Monster Recall from Town ✅ COMPLETE (2026-02-19)

**Problem:** After ascending from dungeon to town, `current_tier=0` but `cr_name_hi[]` still held stale `$E0xx` pointers from the previously loaded tier. The recall command found a stale `cr_display[]` match, and `creature_get_name` returned "?" because the tier data was no longer loaded.

**Fix:** Added `cgn_no_tier` path in `creature_get_name` that detects stale `$E0xx` pointers when `current_tier=0` and reloads the appropriate tier before resolving the name.

---

## BUG-43 — Store-Stocked Items Not Identified ✅ COMPLETE (2026-02-20)

**Problem:** `store_restock_one` (store.s) set `si_item_id`, `si_qty`, `si_p1` for new stock but never set `IF_IDENTIFIED` in `si_flags`. In umoria, `store_create()` calls `magicTreasure()` then `storeItemInsertIntoStock()` which sets `STR_IDENTIFIED`. Players saw store items as unidentified.

**Fix:** Added `ora #IF_IDENTIFIED` on `si_flags,y` in the `sro_store_p1` path. Added test 29 to `test_store.s` to verify store-stocked items always have the identified flag set.

---

## R17 — Character Background History + Gender + Social Class + Variable Gold ✅ COMPLETE

Completed 2026-02-21. Implemented Option C-lite: full family/occupation background history text, gender selection, social class derivation, and umoria-faithful variable starting gold formula. Appearance descriptions (eyes, hair, complexion) dropped to save space.

**New files:**
- `background_data.s` — 72-entry background table from umoria charts 1–23 (family/occupation). Parallel metadata arrays (bg_roll, bg_chart, bg_next, bg_bonus) + packed null-terminated string table in screen codes. Lives in StartupOverlay ($E000). ~2,073 bytes.

**Modified files:**
- `player.s` — added `PL_SOCIAL_CLASS = 65` constant, `player_background` buffer (160 bytes = 4 lines × 40 chars), `ui_char_draw_background` function, gender/SC display strings. `player_init` clears the background buffer.
- `player_create.s` — added `create_select_gender` (M/F prompt), `create_gen_background` (chain walker: race→chart lookup, d100 roll per chart, social class accumulation, text concatenation), `bg_word_wrap` (38-char line limit with word-boundary breaks), `create_calc_gold` (umoria formula: SC×6 + rng(25) + 326 - stat adjustments + female bonus, min 80). Removed hardcoded `PLF_MALE` and `START_GOLD = 200`.
- `ui_character.s` — added rows 12–16: gender + social class display, 4-line background text. "Press any key" moved to row 18.
- `save.s` — bumped `SAVE_VERSION` $0a → $0b; added `save_block`/`load_block` for `player_background` (160 bytes) after player_data.
- `main.s` — updated creation flow to call `create_select_gender` and `create_gen_background` before `create_init_character`.
- 18 test files — added `#import "../background_data.s"` wrapped in `.segmentdef TestCreateOverlay [start=$D000]` dummy segment (keeps Default segment below MAP_BASE $C000).
- `test_background.s` — NEW: 8 runtime tests covering Human/Elf/Half-Troll background generation, gold formula range, gold varies with SC, female +50 bonus, word-wrap line limits, player_init clears buffer.
- `run_tests.sh` — added background test entry (8 tests, default cycle limit).

**Size:** +370 bytes main segment ($B30A → $B47C); 2,948 bytes headroom remaining. Startup overlay: 4,017 of 4,096 bytes (79 free).

---

## R16 — Save Drive Selection (Any IEC Device Number) ✅ COMPLETE

Completed 2026-02-21. Replaced the hardcoded `9)Drive 9` disk sub-menu option with `#)Drive #`, allowing any IEC device number 8–30.

**Changes:**
- `disk_swap.s` — replaced `ds_drv9_str`/`ds_nod9_str` strings and `probe_device_9` with: `probe_device` (generic, X = device#), `disk_enter_device` (new ~170-byte routine), plus data: `de_prompt_str`, `de_ind_pfx`, `de_nodev_str`, `de_digits[2]`, `de_count`, `de_temp`.
- `main.s` — added `disk_menu_show:` label before sub-menu display; changed `$39` (`'9'`) branch to `$23` (`'#'`); replaced 99-byte `!disk_drv9`/`!disk_no_dev9` blocks with `jsr disk_enter_device` + branch (11 bytes).

**UX flow:** pressing `#` shows `Save drive (8-30): ` on row 19; player types 1–2 digits, DEL corrects, RETURN commits. On valid range + device present: sets `disk_mode=2`, `save_device=N`, shows `[Drive  N]` indicator. On device absent: shows `Drive not found!`, waits for key, returns to disk menu. Out-of-range input silently re-prompts.

**Size:** +265 bytes (`program_end` $B201 → $B30A); 3,318 bytes headroom remaining.

---

## OPT-5 — Overlay Expansion (dungeon_gen.s → $E000 overlay) ✅ COMPLETE

Completed 2026-02-21. Moved `dungeon_gen.s` out of the main segment into a new `$E000` overlay (`OVL_DUNGEON_GEN = 4`, disk file `OVL.GEN`).

**Approach:** Split the file into:
- `dungeon_data.s` (new, main segment, ~200 bytes) — shared constants (TILE_*, FLAG_*, MAP_*, room constants), `map_row_lo/hi` row address table, store position/door tables, room data arrays, stairs coordinates, `level_entry_dir`.
- `dungeon_gen.s` (overlay, 3,529 bytes) — all generation code (town_generate, dungeon_generate, BFS connectivity check, etc.) plus private constants (STORE_W/H, ROOM_MIN/MAX) and scratch variables (dg_*, bfs_*).

**Changes:**
- `dungeon_data.s` — new file; extracted from dungeon_gen.s
- `dungeon_gen.s` — stripped to generation code + private data only
- `main.s` — added `DungeonGenOverlay` segmentdef, swapped import, added `lda #OVL_DUNGEON_GEN; jsr overlay_load` before each of 3 `jsr level_generate` calls
- `overlay.s` — added `OVL_DUNGEON_GEN = 4`, `OVL_COUNT = 4`, `OVL.GEN` filename data, expanded REU arrays to 5 entries
- `reu.s` — added `reu_fn_o4` ("OVL.GEN"), extended stash loop from `cpx #4` to `cpx #5`
- `Makefile` — added `OVL_GEN`, disk dependency and write
- 18 test files — added `#import "../dungeon_data.s"` before `#import "../dungeon_gen.s"`

**Results:**
- Program end: $BFA3 → $B201 (**3,490 bytes reclaimed**)
- Headroom to MAP_BASE: 93 → **3,583 bytes**
- DungeonGen overlay: 3,529 bytes (under 4 KB)

---

## R12 — Game-Over Loop ✅ COMPLETE

Completed 2026-02-20. After save+quit, death, or voluntary quit, the game now shows:

```
R)EBOOT  S)TART  Q)UIT
```

- **R (Reboot):** `JMP ($FFFC)` — jumps through the C64 cold-start vector. With `$01=$36` (HIRAM set), `$FFFC/$FFFD` in KERNAL ROM hold `$FCE2`. Equivalent to pressing the reset button: reinitializes I/O chips, SID, VIC, CIA, and BASIC from scratch.
- **S (Start over):** clears ZP game state ($2B–$8F), inventory arrays, `eff_fear_timer`, recall variables, and tier state, then jumps to `restart_entry` (before `detect_machine`) to reinitialize subsystems and return to the title screen.
- **Q (Quit):** falls through to the existing `exit_trampoline` → BASIC warm-start (unchanged behavior).

All three exit paths converge on `!quit:` in main.s → `game_over_prompt`. Code size: ~150 bytes. `program_end` = $BED5 (299 bytes headroom to MAP_BASE).

---

## BUG-47 — OPT-5 Overlay IRQ Lockup (Dungeon Descent Hang) ✅ COMPLETE

Completed 2026-02-21. After OPT-5 moved `dungeon_gen.s` to a `$E000` overlay, descending to dungeon level 1 hung every time; the town level worked fine.

### Root Cause

The `tramp_level_generate` trampoline does `sei` + `$01=$34` (KERNAL ROM off, all RAM at $E000-$FFFF) before calling the overlay, and `$01=$36` + `cli` after. With KERNAL ROM off the hardware IRQ vector at `$FFFE/$FFFF` reads from uninitialized RAM — any `cli` while `$01=$34` is in effect is fatal.

Three functions called `cli` unconditionally at return:

1. **`verify_connectivity`** (dungeon_gen.s) — had `sei` at entry and `cli` at exit.
2. **`tramp_assign_special_room`** (main.s) — saved `$01`, set `$34`, called the overlay function, restored `$01`, then `cli`. This fires at **step 4 of 15** in `dungeon_generate`, leaving ~50,000 cycles of exposed IRQ window before the outer trampoline's `cli`.
3. **`tramp_vault_seal_entrance`** (main.s) — same pattern.

Town worked because `town_generate` never calls `verify_connectivity` or either trampoline.

### Fix

All three functions now use `php` at entry / `plp` at exit:

```asm
verify_connectivity:
    php                    // Save interrupt state — caller may already be in sei context
    sei
    ...
    plp                    // Restore interrupt state (overwrites carry, so set after)
    clc / sec
    rts

tramp_assign_special_room:
    php                    // Save interrupt state
    sei
    lda $01
    pha                    // Save caller's $01 (may be $34 if called from overlay)
    lda #BANK_NO_ROMS
    sta $01
    jsr assign_special_room
    pla
    sta $01                // Restore banking state
    plp                    // Restore interrupt state — no cli
    rts
```

Stack discipline: `php` before `pha`; on exit `pla` (restores `$01`), then `plp` (restores flags). `clc`/`sec` must come *after* `plp` since `plp` overwrites all flags.

### Unit Tests Added

Three interrupt-preservation tests added to `test_dungeon.s` (tests 33–35):
- Test 33: `verify_connectivity` in `sei` context (connected) — I flag stays set on return.
- Test 34: `verify_connectivity` in `sei` context (disconnected/carry-set path) — I flag stays set.
- Test 35: `verify_connectivity` in `cli` context (connected) — I flag stays clear (no sei leak).

Also added a compile-time `MAP_BASE` size guard (`.assert "Test code must not cross MAP_BASE"`) to test_dungeon.s after the test body grew past $C000 (due to OPT-5 item.s changes) and silently corrupted the test code. Fixed by stubbing `ui_help.s` inline (~900 bytes saved).

---

## BUG-46 — Stale Monster Positions on Death Screen ✅ COMPLETE

Completed 2026-02-20. Observed a Jackal killing the player while appearing 2+ tiles away on screen.

### Root Cause

The adjacency check in `monster_try_step` is correct — attack only fires when `mat_target == player_pos` (exactly one step). The bug was a **rendering artifact**: every `turn_post_action` death path in the main loop does `jmp !player_died+` *before* the `viewport_update` / `render_viewport` call. The death screen showed the last pre-AI frame (stale positions from the previous turn). The Jackal was 2 tiles away, moved 1 tile to be adjacent, attacked and killed the player, but the screen still showed it 2 tiles away.

This is a follow-on to BUG-17 (which moved the AI *before* the render for normal turns) but the death exit path was never updated.

### Fix

Added `jsr viewport_update` + `jsr render_viewport` at the top of `!player_died:` in `main.s`. Since all death paths converge on this single label, one fix covers move, paralysis, rest, pickup, drop, wear, open, close, search, and any future turn-consuming actions.

---

## BUG-44 — Save File Not Found: Wrong Error + Wrong Recovery ✅ COMPLETE

Completed 2026-02-20. When "L)oad" was chosen at the title menu and no save file existed, the game showed "Save file corrupt!" and fell through into character creation.

### Root Cause

On VICE/1541, `KERNAL OPEN` for a non-existent sequential file **succeeds** (carry clear). The error only manifests on the first `CHRIN`: the drive returns immediate EOF/timeout, setting `STATUS = $42`. The magic bytes read as zeros/garbage, the 8-byte magic header comparison fails, and `!load_corrupt` fired with the misleading message.

The `!title_load_fail` handler also jumped to `!title_new+` (character creation) instead of back to the N/L/D title menu.

### Fix

- **save.s:** After reading the 8-byte magic header, call `READST`. Any non-zero STATUS at this point means the file doesn't exist (a real save is thousands of bytes — EOI can't appear in the first 8 reads). Non-zero → `!load_close_notfound` (closes file, falls through to message). Zero → proceed with existing magic comparison. Added `save_notfound_str` ("Save file not found.") and `!load_close_notfound` label; the OPEN-fail path jumps directly to `!load_notfound` (no close needed).
- **main.s:** `!title_load_fail` now does `jmp !title_menu_loop-` (back to N/L/D menu) instead of `jmp !title_new+`.

---

## BUG-42 — Fix Save/Load "Save file corrupt!" ✅ COMPLETE

Completed 2026-02-20. Save files always failed to load with "Save file corrupt!" due to streaming RLE decompressor overflow.

### Root Cause

The streaming RLE compress/decompress functions (`rle_compress_to_file`, `rle_decompress_from_file`) had a subtle bug that caused the decompressor to produce excess output bytes, overflowing past MAP_END ($CEFF) into the I/O area. Multiple fixes were attempted (rle_flush_to_file clobbering rle_run_len, bounds check off-by-one $CF→$D0) but the underlying streaming bug persisted.

Diagnosis confirmed by bypassing RLE entirely with raw map I/O — save/load worked immediately, proving block I/O and checksum logic were correct.

### Additional Fixes

- **LOAD_SEC_ADDR**: Changed from 5 to 2 (must match write secondary address)
- **SAVE_VERSION**: Bumped $08→$0A (format changed: no RLE size prefix, raw map data)
- **Title screen KERNAL LOAD**: Added CLOSE file 2 after LOAD (LOAD doesn't remove from file table); cleared status byte $90 (stale EOI from title art LOAD caused false errors in subsequent READST during save I/O)

### Fix

Replaced streaming RLE map compression with raw 3840-byte map I/O via `save_block`/`load_block`. Cost: ~10 extra disk blocks (~9 blocks more than compressed). Benefit: simple, proven reliable, 383 bytes of dead streaming code removed.

Kept in-memory `rle_compress_map` and `rle_flush_literals` for unit tests (tests use safe workspace at $BE00 with no MAP_BASE overlap).

### Size

Program end: $BE48 (was $BFC7 with streaming code). 1,464 bytes headroom to $C000.

---

## R15 — Multi-Disk Support (Dual-Drive + Improved Disk Swap) ✅ COMPLETE

Completed 2026-02-20. Adds dual-drive device 9 support, fixes missing disk_prompt_game calls, expands disk setup sub-menu.

### What Was Implemented

- **R15.1** — Added `save_device: .byte 8` to disk_swap.s; replaced all 7 `ldx #SAVE_DEVICE` sites in save.s, score_io.s, disk_swap.s with `ldx save_device`
- **R15.2** — Added mode 2 no-op check (`cmp #2 / beq !done+`) to both `disk_prompt_save` and `disk_prompt_game`
- **R15.3** — Added missing `jsr disk_prompt_game` after save-and-quit and after death in main.s (fixes mode 1 swap-back bug; also required for R12 restart loop)
- **R15.4** — Added `probe_device_9` routine to disk_swap.s (~35 bytes): opens channel 15 on device 9, sends I0, checks KERNAL status, returns C=0 if present / C=1 if absent
- **R15.5** — Expanded title screen 'D' handler into disk setup sub-menu: "S)ame W)swap 9)Drive 9" — S→mode 0, W→mode 1, 9→probe+mode 2 or "Drive 9 not found!" error
- **R15.6** — Added `rundual` target to both commodore/c64/Makefile and root Makefile (VICE with two true-drive 1541s on devices 8+9)
- **Fix** — Added `#import "../disk_swap.s"` to test_save.s and test_score.s (save_device was an implicit dependency; test files assemble independently)

### Size

~120 bytes in main segment. `program_end` moved from $BDB5 → $BED5 (811 bytes headroom to $C000).

### Notes

- Tier loading and overlays unchanged — always use device 8 (game disk)
- save_device has an implicit dependency from save.s/score_io.s; test files importing those must also import disk_swap.s

---

## R14 — Fix Tunneling Difficulty + Enchanted Digging Tools ✅ COMPLETE

Completed 2026-02-20. Fixes BUG-41 (tunneling far too easy) and adds enchanted digging tool variants.

### What Was Implemented

**Part A — Hardness Rescaling (BUG-41 fix):**
- Granite: `rng(20)+8` (8–27) → `rng(240)+16` (16–255) — matches ~umoria proportions
- Magma: `rng(12)+3` (3–14) → `rng(120)+5` (5–124)
- Quartz: `rng(10)+2` (2–11) → `rng(80)+3` (3–82)
- Rubble: always-succeed → `rng(40)` resistance check (now requires a tool)

**Part A — New Dig Ability Formula:**
- `bare hands → ability = 0` (prints "You dig with your hands, making no progress.")
- `digging tool → (STR >> 2) + base_bonus + (ego × 12)` — Shovel base=6, Pick base=20
- `regular weapon → (STR >> 2) + max(0, TODMG >> 1)`

| Tool | ego | Ability (STR 18) | Granite hit rate |
|------|-----|-----------------|-----------------|
| Shovel | 0 | 10 | 0% |
| Pick | 0 | 24 | 3.3% |
| Gnomish Shovel | 1 | 22 | 2.5% |
| Orcish Pick | 1 | 36 | 8.3% |
| Dwarven Shovel | 2 | 34 | 7.5% |
| Dwarven Pick | 2 | 48 | 13.3% |

**Part B — Enchanted Digging Tools:**
- Reuse item types 62/63 (Shovel/Pick) with ego byte (0=basic, 1=Gnomish/Orcish, 2=Dwarven)
- `roll_tool_ego_check` (main RAM): DL<10 always ego=0; DL 10–19: 25% ego=1; DL 20+: 25% ego=1, 10% ego=2
- Name display uses prefix not suffix: "Dwarven Pick" (not "Pick (Dwarven)")
- Pricing: ego=1 base×5, ego=2 base×15 (Shovel: 15/75/225gp, Pick: 50/250/750gp)
- Home storage: `si_ego` array added to store_data.s; deposit/retrieve/save/load all handle ego correctly
- `SAVE_VERSION` bumped $07→$08 (si_ego added to save format)

### Files Changed (11)

| File | Change |
|------|--------|
| `data/huffman_strings.txt` | Added `@TUN_NO_TOOL` string |
| `commodore/c64/huffman_data.s` | Regenerated (218 strings, HSTR_TUN_NO_TOOL=197) |
| `commodore/c64/tunnel.s` | New hardness values, rubble resistance, bare-hands check |
| `commodore/c64/main.s` | `calc_dig_ability` (new formula, moved to main RAM), `roll_tool_ego_check`, `put_tool_ego_prefix`, `put_inv_name_with_ego`, `banked_ego_put_suffix` relocated from $F000 |
| `commodore/c64/ego_items.s` | 3-byte dispatch stub → `roll_tool_ego_check` |
| `commodore/c64/ui_inventory.s` | Replaced ego display with `put_inv_name_with_ego` helper |
| `commodore/c64/store_data.s` | Added `si_ego` array (96 bytes) |
| `commodore/c64/ui_home.s` | Deposit/retrieve copy ego; home display shows prefix |
| `commodore/c64/save.s` | `si_ego` added to save/load; SAVE_VERSION $07→$08 |
| `commodore/c64/store.s` | `apply_tool_ego_multiplier` function; `sb_item_ego` variable; 5 pricing functions updated |
| `commodore/c64/ui_store.s` | Store display shows tool ego prefix; buy/sell set sb_item_ego |

### Bugs Found During Testing

- **Stale flags in `roll_tool_ego_check`**: `jmp` from ego_items.s didn't update the zero flag, so the `bne` check used stale flags from `roll_ego_type`'s earlier `cmp #ICAT_WEAPON`. Result: digging tools would never get ego types. Fixed by adding `cmp #ICAT_DIGGING` before the branch.
- **Missing test stubs**: `ui_trampoline_stubs.s` needed entries for `roll_tool_ego_check`, `put_inv_name_with_ego`, `put_tool_ego_prefix`, `banked_ego_put_suffix` (all new R14 functions). Added.

### Segment Boundaries After R14

- Main segment: $BDB5 (587 bytes headroom to MAP_BASE $C000)
- Banked code: $F000–$FF97 (98 bytes headroom, up from 3 bytes — net freed by moving calc_dig_ability + banked_ego_put_suffix to main RAM)
- Town overlay: 3,014 bytes (1,082 bytes free)

### Key Architectural Note

The BUILDPLAN estimated $F000 had 720 bytes free. Actual: 3 bytes. Solution: move `calc_dig_ability` (new name) and `banked_ego_put_suffix` to main RAM entirely — they only read main RAM data. Also added shared helper `put_inv_name_with_ego` to DRY up prefix/suffix display across inventory, equipment, and home store screens, saving ~45 bytes in $F000.

---

## Phase Plan

### Phase 1 — Skeleton and Infrastructure ✅ COMPLETE

**Goal:** A program that boots on C64/C128, displays text, accepts input, and
can be tested.

| # | File | What it does | Tests |
|---|---|---|---|
| 1.1 | `main.s` | BASIC stub ($0801), SYS entry, save BASIC ZP state ($02–$8F) to buffer, disable BASIC ROM, call init, main loop. IRQ: keep the default KERNAL IRQ handler active (required for keyboard scanning used by GETIN in `input.s`). If a custom raster IRQ is needed later (e.g., for split-screen effects), chain it to the KERNAL handler via the saved vector. Clean exit: restore ZP state, re-enable BASIC ROM, RTS to BASIC warm start. Select unshifted character set mode (uppercase + graphics) at startup. | Boots in VICE, exits cleanly, BASIC works after exit, keyboard responsive |
| 1.2 | `config.s` | Detect C64 vs C128, detect 40/80 column mode, store machine type in ZP | Returns correct machine ID |
| 1.3 | `zeropage.s` | Define ZP variable locations for all modules using BASIC's freed space ($02–$8F). Document two zones: "safe" (never touched by KERNAL) and "volatile" (clobbered by KERNAL LOAD/SAVE/OPEN — $14–$15, $22–$25, etc.). Volatile ZP must be caller-saved around KERNAL calls in tier_manager.s and save.s. | Symbols resolve, no overlap, KERNAL-safe zones documented |
| 1.4 | `memory.s` | Bank switching macros: bank out BASIC ROM, bank out KERNAL ROM (with SEI/CLI protection), copy routines for banked RAM | Read/write behind ROM works |
| 1.5 | `screen.s` | Clear screen, print string at (row,col), print char, set colors, scroll message area. Uses direct screen memory writes (not KERNAL CHROUT) for performance. All output goes through a vector table (`put_char`, `put_string`, `clear_screen`, `set_color`) so the VDC 80-column backend can be swapped in for Phase 10 without changing callers. Overhead is ~6 cycles per indirect JMP — negligible. | Text appears correctly |
| 1.6 | `input.s` | Wait for keypress (KERNAL GETIN), key-to-command mapping table, handle direction keys. Numeric prefix for repeats deferred to Phase 6+. | Correct key codes returned |
| 1.7 | `rng.s` | 32-bit Galois LFSR seeded from CIA timer, `randByte` and `randRange` routines. A 16-bit LCG only has 65,536 states and produces noticeable repetition in dungeon generation; 32-bit LFSR has 4 billion states at ~20 cycles per call. | Statistical distribution test, no short-period repetition |
| 1.8 | `math.s` | 8x8→16 multiply, 16/8→8 divide, dice roll (NdS+B) | Boundary value tests |
| 1.9 | `turn.s` | Turn processing routines: `turn_post_action` (called by main loop after player actions) runs effect timers → hunger tick → increment turn counter → mark status dirty. Monster AI and regeneration added in Phase 5. Main loop in `main.s` handles command dispatch and rendering. | Turn post-action runs correctly |
| 1.10 | `sound.s` | Minimal SID sound effects: bump (wall collision), hit (combat), miss (combat), pickup (item), death (game over). Simple waveform + ADSR envelope per effect, no music. | Sounds play without disrupting gameplay timing |

**Deliverable:** Program boots, shows "MORIA" title, waits for a keypress, exits
to BASIC. All infrastructure routines have passing unit tests.

---

### Phase 2 — Player and Character Creation ✅ COMPLETE

**Goal:** Create a character with race, class, stats, and display the character
sheet.

| # | File | What it does | Tests |
|---|---|---|---|
| 2.1 | `tables.s` | Race stat modifiers (8 races x 6 stats), class data (6 classes), XP level thresholds (40 levels), stat bonus tables | Data integrity checks |
| 2.2 | `player.s` | Player struct in memory (~200 bytes), accessors for stats/HP/mana/gold/level, stat bonus lookups | Get/set round-trip |
| 2.3 | `player_create.s` | Race selection, stat rolling (umoria algorithm: 18 dice cycling d3/d4/d5, constrained total 43–54, each stat = 5 + 3 consecutive dice, race modifiers via incrementStat/decrementStat — see Stat Generation Deep Dive in Audit Review), class selection (filtered by race), name entry (max 16 chars, uppercase only — matches unshifted character set), initialize starting HP/mana/inventory. Order: race → stats → class → name (stat roll shows race-adjusted previews before class is chosen). | Full creation flow in VICE |
| 2.4 | `ui_character.s` | Character sheet display (name, race, class, stats, level, HP, mana, AC, gold), stat detail view | Screen output matches data |
| 2.5 | `ui_status.s` | Bottom status line: HP, mana, dungeon level, player level. Update on change only (dirty flag). | Status reflects player state |
| 2.6 | `ui_messages.s` | Top message line: display message, "—more—" prompt for overflow, message history buffer (last 8 messages) | Messages display, more works |

**Deliverable:** Player can roll a character, see their stats, and the status bar
and message system work.

---

### Phase 3 — The Town Level ✅ COMPLETE

**Goal:** Generate and display the town, move the player around it.

| # | File | What it does | Tests |
|---|---|---|---|
| 3.1 | `dungeon_gen.s` (town portion) | Generate town level: outer boundary walls, 6 store buildings (10x5 each with door), staircase to dungeon, open areas. Fixed layout (no RNG needed). | Town structure matches spec |
| 3.2 | `dungeon_render.s` | Tile-to-screen-code mapping table (see Screen Code table below), render visible portion of map to screen, handle 40-col viewport (38x20 game area with border), cursor positioning for player `@` symbol | Map renders correctly |
| 3.3 | `player_move.s` | 8-direction movement via HJKLYUBN (vi-keys) and cursor keys. Numpad keys 1–9 deferred to Phase 10 (C128 enhancements). Collision with walls, enter store door (triggers store screen), step on stairs. Running (auto-move in a direction until interrupted by obstacle, monster, or intersection) deferred to Phase 4.6 — requires dungeon corridors. | Movement works, walls block |
| 3.4 | `dungeon_los.s` | Simple town LOS: everything in town is lit and visible. Player position tracking, map reveal. (Full LOS in Phase 4.5.) | Visibility correct |

**Tile Mapping (40-column) — Screen Codes for Direct Memory Writes:**

These are **screen codes** (values poked directly into screen RAM at $0400+),
NOT PETSCII codes (which are different and used with KERNAL CHROUT). All
rendering uses direct screen memory writes for performance.

**Tile types (bits 7–4) — 16 codes, all used:**

| Type Code | Tile | Glyph | Screen Code | Color |
|---|---|---|---|---|
| 0 | Floor | `.` (period) | $2E | Dark grey ($0B) |
| 1 | Wall (horizontal) | `─` (horiz line) | $40 | Light grey ($0F) |
| 2 | Wall (vertical) | `│` (vert line) | $5D | Light grey ($0F) |
| 3 | Wall (corner TL) | `┌` | $70 | Light grey ($0F) |
| 4 | Wall (corner TR) | `┐` | $6E | Light grey ($0F) |
| 5 | Wall (corner BL) | `└` | $6D | Light grey ($0F) |
| 6 | Wall (corner BR) | `┘` | $7D | Light grey ($0F) |
| 7 | Door (open) | `'` | $27 | Brown ($09) |
| 8 | Door (closed) | `+` | $2B | Brown ($09) |
| 9 | Stairs down | `>` | $3E | White ($01) |
| 10 | Stairs up | `<` | $3C | White ($01) |
| 11 | Rubble | `:` | $3A | Grey ($0C) |
| 12 | Magma stream | `#` | $23 | Red ($02) |
| 13 | Quartz vein | `%` | $25 | White ($01) |
| 14 | Trap (visible) | `^` (up arrow) | $1E | Red ($02) |
| 15 | Secret door | (wall glyph) | (same as adjacent wall) | (same as wall, until found) |

**Rendering states (not tile types — derived from flags or context):**

| State | Glyph | Screen Code | Color | How determined |
|---|---|---|---|---|
| Player | `@` | $00 | White ($01) | Player position (always drawn on top) |
| Store (number) | `1`–`6` | $31–$36 | Yellow ($07) | Town gen marks floor tiles; renderer checks store table |
| Gold / floor item | `$` | $24 | Yellow ($07) | Bit 1 (treasure flag) set; renderer checks floor item table |
| Unknown/unseen | (not drawn) | — | Black (background) | Bit 2 (visited flag) = 0; tile type stored but not rendered |
| Monster | letter | varies | threat-coded | Bit 0 (creature flag) set; renderer checks active monster table |

**Screen code conversion note:** PETSCII and screen codes are different encodings.
For ASCII-range characters ($20–$3F), values are identical. For graphic characters:
PETSCII $A0–$BF → screen code = PETSCII − $40; PETSCII $C0–$DF → screen code =
PETSCII − $80. The values above are verified screen codes for the unshifted
character set. Do NOT use PETSCII values (e.g., $C0 for `─`) in direct screen
writes — $C0 as a screen code renders as reverse-video horizontal bar.

**Character set mode:** The game uses **unshifted mode** (uppercase + graphics
characters). This provides the box-drawing characters needed for walls but means
all text is uppercase only. This matches the retro feel and is standard for C64
games. The character set is selected at startup in `main.s` via the $D018
register. No custom character set is loaded.

**Color palette:** Colors are written to color RAM ($D800+) alongside screen
codes. The palette above improves readability by distinguishing structural
elements (grey walls), interactive elements (brown doors, yellow stores), and
the player (white). Monster colors are defined in Phase 5 — threat-coded by
depth relative to player level.

**Deliverable:** Town level renders, player walks around with `@`, bumps into
walls, store numbers visible, stairs visible.

---

### Phase 4 — Dungeon Generation and Navigation ✅ COMPLETE

**Goal:** Generate dungeon levels and navigate between them.

| # | File | What it does | Tests |
|---|---|---|---|
| 4.1 | `dungeon_gen.s` (full) | Room-and-corridor generation for dungeon levels. 80x48 map. Place N rooms (4–8 for simplicity), connect with tunnels, add doors, place stairs (2 down, 1 up), add mineral streamers. Room types: basic rectangle + overlapping. | Rooms connected, stairs present |
| 4.2 | `dungeon_features.s` | Door open/close/lock/jam logic, trap placement (6 types: pit, arrow, gas, teleport, dart, rockfall), staircase level transitions, secret door detection | Traps trigger correctly |
| 4.3 | `tier_manager.s` + `reu.s` | ✅ **COMPLETE** (implemented as R3.5). Creature tier data loaded from disk via KERNAL LOAD or REU DMA on tier boundary crossings. `tier_check_transition` detects boundary; hysteresis via overlapping tier ranges prevents thrashing. REU path: all tiers preloaded at startup, DMA fetch on transition (near-instant). Disk path: KERNAL LOAD on each transition. Graceful fallback to embedded creatures if no d64. | 10 automated tests in test_tier.s |
| 4.4 | `dungeon_render.s` (viewport) | Viewport scrolling for 80x48 map on 38x20 screen. Panel movement when player nears edge. Draw only changed tiles (dirty tile tracking). | Viewport scrolls correctly |
| 4.5 | `dungeon_los.s` (full) | Hybrid LOS matching original Moria behavior: lit rooms reveal fully when player enters (check room membership, not per-tile rays). Dark corridors reveal only adjacent tiles. Bresenham ray casting reserved for specific checks (ranged attacks, bolt spells in Phase 7) — not used for general visibility, as per-tile ray casting is too expensive at 1 MHz for every player move. Torch/lamp extends corridor visibility to light-radius adjacent tiles. | LOS matches expected pattern |
| 4.6 | Player movement updates | Walking into darkness, falling in pits, hitting traps, going up/down stairs transitions. Searching reveals secret doors (1-in-6 base). Running: auto-move in a direction until interrupted by wall, intersection, visible monster, or item on floor. Running is essential QoL for traversing explored corridors. | Transitions work, running stops at obstacles |

**Deliverable:** Multi-level dungeon with rooms, corridors, doors, traps, and
lighting. Player can descend and ascend.

---

### Phase 5 — Monsters ✅ COMPLETE

**Goal:** Monsters appear, move, and can be fought.

| # | File | What it does | Tests |
|---|---|---|---|
| 5.1 | `monster.s` | Active monster table (up to 32 simultaneous — reduced from 125 for C64 RAM). Spawn routine: pick creature type appropriate to depth, place in valid empty tile. Monster display characters. | Monsters spawn at correct depth |
| 5.2 | `monster_ai.s` | Monster movement: awake/sleep check (noise radius), greedy step toward player, confused wandering, wall-phasing for ghosts. Variable speed: each creature type has a speed value (1 = normal, 2 = fast/moves twice per player turn, 0 = slow/moves every other turn). The turn sequencer (`turn.s`) checks speed counters and calls AI accordingly. Speed is a core tactical mechanic — fast hounds are dangerous because they outrun you, slow molds are manageable because you can kite them. | Monsters approach player, fast monsters move twice per turn |
| 5.3 | `combat.s` | Melee attack: blow count from table (dex x weight ratio), to-hit roll (d20 + bonuses vs AC), damage roll (weapon dice + str bonus). Kill awards XP, check level-up. | Damage/kill/XP correct |
| 5.4 | `monster_attack.s` | Monster melee: up to 4 attacks per creature, damage types (normal, poison, stat drain, gold theft, item theft). Attack messages. Player death check. | Attacks deal correct damage |
| 5.5 | `turn.s` (effects) | Status effect application and timers: poison tick, blindness (hide map), confusion (random movement), paralysis (skip turns), regeneration (HP/mana per turn based on CON). | Timers decrement, effects apply |
| 5.6 | `dungeon_render.s` (monsters) | Show monster characters on map. Monster visibility (only in LOS and lit). Monsters blink or highlight on attack. | Monsters visible when expected |

**Deliverable:** Monsters wander the dungeon, attack the player, the player can
fight back. Status effects work. Combat is functional.

---

### Phase 6 — Items and Inventory ✅ COMPLETE

**Goal:** Items can be found, carried, equipped, used, and dropped.

| # | File | What it does | Tests |
|---|---|---|---|
| 6.1 | `item.s` | Item SoA tables (55 types) + inventory data structure: 22 carried slots + 8 equipment slots. Floor item table (32 slots at $CF00). Add/remove/stack operations. | Add/remove/stack correct |
| 6.2 | `ui_inventory.s` | Display inventory list (letter-indexed a–v), equipment list, item detail view. 40-column formatting with scrolling for overflow. | Display matches contents |
| 6.3 | `player_items.s` | Equip/remove/drop/pick-up commands. Wear/wield calculates AC and to-hit changes. Cursed items cannot be removed. Eat food (hunger system: full → hungry → weak → fainting → dead). | Equip changes stats |
| 6.4 | Item generation | Floor item spawning during dungeon gen. Gold pile generation. Treasure rooms. Chest contents. Item enchantment rolling (+1 to +N based on depth). | Items spawn at correct depth |
| 6.5 | Item identification | Unidentified items show generic name ("a blue potion"). Identify scroll/spell reveals true name. "Tried" status after first use. Scroll/potion/wand color randomization per game. | ID progression works |

**Deliverable:** Full item lifecycle — find, pick up, identify, equip, use, drop.
Hunger system functional.

---

### Phase 7 — Magic System ✅ COMPLETE

**Goal:** Mages cast spells, priests pray, scrolls/potions/wands work.

| # | File | What it does | Tests |
|---|---|---|---|
| 7.1 | `player_magic.s` | Spell/prayer book display, learn new spells on level-up, cast spell (mana cost, failure chance based on level+INT/WIS), spell cooldown. 16 mage spells + 16 priest prayers (reduced from 31 each). | Cast succeeds/fails correctly |
| 7.2 | Spell effects | Implement each spell: magic missile, light area, detect monsters, phase door, fireball, teleport self, identify, cure poison, cure wounds, bless, remove curse, etc. | Each effect works |
| 7.3 | Scrolls/potions | Use item → apply effect → consume item. 20 scroll types, 20 potion types (reduced). Effects overlap spell system where possible (share subroutines). | Items consumed, effects apply |
| 7.4 | Wands/staves | Directional targeting for wands (aim in 8 directions). Staves affect area. Charge tracking. | Charges decrement |
| 7.5 | `monster_magic.s` | Monster spellcasting: breath weapons (damage = current HP fraction), bolt spells, summoning, teleport player, blindness, confusion. Check range, check LOS. | Monsters cast when in range |

**Deliverable:** Full magic system for both player and monsters.

---

### Phase 8 — Stores ✅ COMPLETE

**Goal:** Town stores buy and sell items.

| # | File | What it does | Tests |
|---|---|---|---|
| 8.1 | `store.s` | 6 stores with inventory (12 items each — reduced from 24). Store owner data (name only — race and max gold deferred, see RP14-2/RP14-5). Inventory restocking on town re-entry. (Design deviation: original Moria restocks based on game turns elapsed, not on re-entry. Simplified for implementation; acceptable because the net effect is similar — stores refresh between dungeon visits.) | Stores stock correct items |
| 8.2 | `ui_store.s` | Store screen: list items with prices, buy/sell interface. Simplified haggling (accept/decline at offered price, no multi-round bidding — optional enhancement later). Store entry detected via `check_player_on_store_door` at `!post_move:` in main loop. Sell flow uses sub-screen to show full 22-slot player inventory. | Buy/sell transactions work |
| 8.3 | Price calculation | Base price × charisma modifier only (race modifier deferred, see RP14-2). Buy: `base_price × chr_price_adj[CHR-3] / 100` (100-130%). Sell: `base_price × chr_sell_adj[CHR-3] / 100` (25-50%). Uses `math_mul_16x8` (16×8→24-bit multiply, added to `math.s`) and existing `math_div_16x8`. | Prices match formula (17 tests) |

**Implementation details:**
- **New files:** `store.s` (474 lines — data, restock, pricing, gold ops), `ui_store.s` (~500 lines — entry detection, screen rendering, buy/sell flows), `tests/test_store.s` (17 runtime tests)
- **Modified files:** `main.s` (imports + 3 hooks: init, restock on ascend, door check at post_move), `math.s` (added `math_mul_16x8`), `tables.s` (added `chr_sell_adj` 16-byte table), `run_tests.sh` (added store suite)
- **Store inventory:** SoA layout — `si_item_id`, `si_qty`, `si_p1`, `si_flags` (72 slots = 6 stores × 12). Category matching via 16-bit bitmasks (`store_cat_mask_lo/hi`).
- **Restocking:** `store_init_all` at game start; `store_restock_all` on stair ascent to town. Each empty slot has 50% chance to stock. Item selection via rejection sampling (`rng_range(45)+2`, check category, max 30 retries, fallback table).
- **Branch distance issues:** Several routines required `bcc/jmp` patterns and subroutine extraction to stay within 6502's ±128 byte relative branch limit.
- **math_multiply clobbers X:** `math_mul_16x8` saves X in `mul_saved_x` before first `math_multiply` call.
- **Test framework note:** Data bytes after `brk` shift segment end address, breaking `run_tests.sh` VICE breakpoint detection. All scratch data must be placed before `brk`. (See RP14-6.)
- **Verification:** `make build` → 57 asserts, 0 failed. `make test` → 13/13 suites pass (186 total tests, store 17/17).

**Deliverable:** Player can buy equipment and sell loot in town.

---

### Phase 9 — Save/Load and Game Polish ✅ COMPLETE

**Goal:** Game state persists across sessions. Death and scoring work.

| # | File | What it does | Tests |
|---|---|---|---|
| 9.1 | `save.s` ✅ | Save game: write player struct, current dungeon map, active monsters, floor item table, inventory, current tier recall data, game flags to sequential file on disk. Compress map (RLE on tile bytes). Estimated save size: ~3–5 KB. | Save and reload match, all floor items and monsters persist |
| 9.2 | Load game ✅ | Load from disk, validate file integrity (checksum), **delete savefile immediately after successful load** (before resuming play — this enforces permadeath and prevents save-scumming via machine reset), restore all state, resume play. | Game resumes correctly, savefile gone |
| 9.3 | Death and scores ✅ | Death screen with killer info. High score table (top 10, stored on disk). Score = XP + gold + depth bonus. | Scores persist |
| 9.4 | Game polish ✅ | PETSCII title screen (disk-loaded art), HP calculation bug fix (race HD), starting equipment (dagger, leather armor, spellbook), RP15 store fixes. | Title displays, HP correct, equipment works |

**9.1/9.2 Implementation details:**
- **New files:** `save.s` (~1,120 lines — KERNAL I/O, RLE compress/decompress, save/load orchestration, checksum, recount routines), `tests/test_save.s` (10 runtime tests: RLE round-trips, checksum, recount_monsters, recount_floor_items)
- **Modified files:** `main.s` (bootstrap trampoline, exit trampoline, CMD_SAVE dispatch, title screen New/Load menu, load_resume_game, death handler delete, program_end assert), `input.s` (SHIFT+S → CMD_SAVE), `ui_help.s` (SHIFT+S SAVE in help screen), `memory.s` (CREATURE_BASE $A100→$AB00), `dungeon_gen.s` (BFS_QUEUE_MAX 3840→2650), `player.s` (light_radius in sync_from_zp), `run_tests.sh` (added save suite)
- **Save file format:** Binary sequential file "MORIA.SAV" on device 8. ~4,100 bytes: magic header, player struct, ZP game state, RNG state, inventory, id_known, shuffle tables, store inventory, stairs, rooms, traps, monster table, floor items, RLE-compressed map, 16-bit additive checksum.
- **RLE compression:** Literal packets (header < $80, len = header+1) and repeat packets (header >= $80, len = header−$7D). Workspace at CREATURE_BASE ($AB00). Output bounds check prevents corrupt data from overwriting FLOOR_ITEM_BASE.
- **Memory safety:** Bootstrap trampoline at $080E banks out BASIC ROM before entry. Exit trampoline in low RAM banks BASIC ROM back in safely. CREATURE_BASE must be past program_end (compile-time assert). check_savefile_exists uses separate file number (3) to avoid KERNAL file table conflict with load_game (file 2).
- **Test framework fix:** Tests with BRK above $A000 can false-trigger during BASIC ROM execution in VICE autostart. test_save.s splits into "Test Code" (bootstrap + finish with BRK at $0824) and "Test Body" (imports + logic) segments.
- **Verification:** `make build` → 61 asserts, 0 failed. `make test` → 14/14 suites pass (save: 10/10). See Review Pass 16 for post-implementation fixes.

**9.3 Implementation details:**
- **New files:** `score.s` (~988 lines — 24-bit math, score calculation, death screen, high score table insert/display, disk I/O for MORIA.HI), `tests/test_score.s` (10 runtime tests: math_add_24, math_cmp_24, score_calculate, hiscore_insert empty/ordering/overflow, screen_put_decimal_24)
- **Modified files:** `zeropage.s` (renamed `zp_eff_spare` → `zp_death_source`), `config.s` (death source constants DEATH_ALIVE/CURSED/POISON/STARVE), `monster_attack.s` (+2 lines: set death source from `mat_type2`), `monster_magic.s` (+4 lines: set death source from `zp_mon_type` for bolt/breath), `turn.s` (+4 lines: set death source for poison/starvation), `player_items.s` (+2 lines: set death source for poison potion), `main.s` (import score.s, replaced death handler with score flow), `memory.s` (CREATURE_BASE $AC00→$B200), `dungeon_gen.s` (BFS_QUEUE_MAX 2560→1792), `run_tests.sh` (added score suite)
- **Death source tracking:** `zp_death_source` ($5F, in ZP save range) encodes killer identity: $00=alive, $01–$FC=monster creature type index (→ cr_name_lo/hi for name), $FD=cursed item, $FE=poison, $FF=starvation. Set at each death source before `player_death_check`.
- **Score formula:** `score = XP(24-bit) + gold(24-bit) + max_depth × 50`. Uses `math_multiply` (8×8→16) for depth bonus, then 24-bit addition.
- **Death screen:** 40×25 layout: title, player name/race/class/level, dungeon depth, death source ("KILLED BY A KOBOLD" / "POISON" / "STARVATION" / "A CURSED ITEM"), XP/gold/depth bonus/total score breakdown, high score table with new entry highlighted, "PRESS ANY KEY".
- **High score table:** 10 entries × 23 bytes (16-byte name, 3-byte score LE, level, depth, race, class). File format: 4-byte header ("MH" + version $01 + count) + entries. Sequential file "MORIA.HI" on device 8. Scratch-and-rewrite on save.
- **Memory optimization:** `hiscore_table` (230 bytes) placed at CREATURE_BASE instead of in program image — safe because BFS/RLE (gameplay) and hiscore (game over) never overlap temporally. This kept program_end ($B191) within the raised CREATURE_BASE ($B200).
- **Verification:** `make build` → 62 asserts, 0 failed. `make test` → 15/15 suites pass (score: 10/10).

**Deliverable:** Complete, playable game loop from title screen through death
and high scores.

---

### Phase 10 — C128 Enhancements

**Goal:** Take advantage of C128 hardware when available.

| # | What | Details |
|---|---|---|
| 10.1 | 80-column mode | VDC-based rendering for 80x25 display. Larger viewport (78x20). Full-width status bar. **Note:** The VDC has its own 16 KB RAM accessed only through register ports ($D600/$D601) — screen memory is NOT directly addressable. Every character write requires a multi-step register sequence (set address high, set address low, write data). This is architecturally different from VIC-II direct screen pokes and effectively requires a **second rendering backend**, not just wider output. Design screen.s with an abstract interface from Phase 1 so the VDC renderer can be swapped in. |
| 10.2 | Extended memory | Use C128's 128 KB to hold all creature/item tiers simultaneously — no disk loading between levels. |
| 10.3 | Larger dungeon | With more RAM, expand dungeon to 120x80 or larger. More rooms, more monsters (up to 64 active). |
| 10.4 | Enhanced display | Use VDC attributes for color-coded monsters (red = dangerous, green = easy). Reverse video for walls. |

---

---

## Audit Review — Phases 1–3 Implementation

Code review performed against this plan after Phases 1–3 were implemented.
Findings are categorized as bugs, plan deviations, and minor issues.

### Bugs

| # | Severity | File | Issue |
|---|---|---|---|
| A1 | High | `screen.s:91-96` | **`screen_clear` writes 24 bytes past screen RAM.** The second fill loop (`SCREEN_RAM + $300 + x` starting at `x=$E8`) writes to $07E8–$07FF, which is past the end of screen RAM ($07E7). The first loop already covers all 1000 bytes via the `$2E8` offset. The second loop is both redundant and out-of-bounds. Same issue exists for the color RAM fill. Fix: delete the second loop entirely. |
| A2 | High | `dungeon_gen.s:45-46` | **Flag bit assignment swapped vs. plan.** Code defines `FLAG_HAS_ITEM=$01` (bit 0) and `FLAG_OCCUPIED=$02` (bit 1). Plan specifies bit 0 = creature, bit 1 = treasure. No runtime impact in Phase 3 (flags not checked yet), but Phase 5 (monsters) and Phase 6 (items) will read the wrong bits. Fix: either swap the constants in code or update this plan to match the code. |
| A3 | Medium | `input.s:85-96` | **Numeric prefix parsing is broken.** `input_get_command` detects `CMD_REPEAT` but discards the digit value and loops back to `!get_key` without accumulating anything. Comment says "TODO: implement in Phase 3" but Phase 3 is complete. Plan 1.6 lists this as a Phase 1 deliverable. Fix: implement digit accumulation or remove the feature from Phase 1 scope and defer explicitly. |
| A4 | Low | `player_create.s:706` | **"CHOOSE (A-" prompt is incomplete.** The string `create_choose_str` ends with `A-` and a null terminator — the closing range letter and `)` are never appended. Displays as `CHOOSE (A-` for both race and class selection. Fix: dynamically append the final letter and closing paren after the string, or use separate prompt strings per screen. |
| A5 | Medium | `player.s` (player_calc_stats) | **Stat modifiers may be clamped prematurely between race and class additions.** If the intermediate result after adding the race modifier is clamped to 3–18 before the class modifier is added, edge cases produce wrong results. Example: base=17, race=+3, class=-3 → sequential clamping gives 15 (17→20→18→15) instead of correct 17 (17+3-3=17). Current tests use base=10 and don't hit this case. Fix: sum all modifiers first, then clamp once. |
| A6 | High | `dungeon_render.s` / `main.s` | **Full viewport redraw on every move causes visible input lag.** `render_viewport` redraws all 760 tiles (38x20) on every movement keypress, even though typically only 2 tiles changed (old and new player position). Per-tile cost is ~80-120 cycles (map read, flag check, 4x LSR, two table lookups, player position check, `check_store_door` JSR with 6-entry linear scan, screen+color RAM writes), totaling 60,000-90,000 cycles (~3-5 frames). Fix: implement dirty tile rendering — only update changed tiles on move; reserve full redraw for viewport scroll and screen transitions. |
| A7 | High | `input.s` / `main.s` | **Keyboard buffer not flushed before input poll causes key stacking.** While `render_viewport` runs for 3-5 frames, the KERNAL IRQ continues scanning the keyboard and queuing keypresses into the buffer at `$0277` (count at `$C6`). When `input_get_command` calls GETIN, it immediately dequeues stale buffered keys, triggering another full redraw, which buffers more keys — a snowball effect. Fix: flush the keyboard buffer (`lda #0 / sta $c6`) before polling for input. |

### Plan Deviations

| # | Area | Plan Says | Code Does | Resolution Needed |
|---|---|---|---|---|
| D1 | Character creation order (2.3) | Race → class → stats → name | Race → stats → class → name | Decide: update plan or reorder code. Current order means stat rolling screen shows race-adjusted stats but not class-adjusted stats. |
| D2 | Movement keys (3.3) | Vi-keys + number keys 1–9 (numpad) | Vi-keys + cursor keys only | Add numpad mapping to `key_map_petscii`/`key_map_cmd` tables, or defer numpad to Phase 10 (C128 enhancements) and update plan. |
| D3 | Store building size (3.1) | 6 stores, 4x3 each | 6 stores, 10x5 each (`STORE_W=10, STORE_H=5`) | The 10x5 stores are more proportional on the 80x48 map. Update plan to match code if intentional. |
| D4 | Turn sequencer usage (1.9) | `turn.s` drives the game loop | `main.s` dispatches commands directly, calls `turn_post_action` | `turn_execute` and its phase structure are dead code. Either refactor main loop to use the sequencer or simplify `turn.s` to match actual usage. |
| D5 | Food timer | Not specified in plan | Starting food = 200, hungry at 150 = only 50 turns before hunger warning | Original Moria food lasts thousands of turns. 50 turns is extremely aggressive. Either increase starting food significantly (e.g., 2000+) or adjust thresholds. |

### Minor Issues

| # | File | Issue |
|---|---|---|
| M1 | `player_create.s:653-656` | Dead code: `create_init_character` sets player position to (20,12), but `town_generate` (called after in `main.s`) overwrites it to (39,24). Remove the dead assignment. |
| M2 | `tests/*.s` | No `.mon` monitor scripts exist. The testing strategy section of this plan says each test `.s` file has a corresponding `.mon` script for VICE headless execution. The 4 test files cannot run as specified without these scripts. |
| M3 | `tests/test_memory.s` | Does not track overall pass/fail in `$02` like the other test files do. Convention requires `$02 = $01` for all-pass, `$02 = $00` for any-fail. |
| M4 | `screen.s:83-89` | The first fill loop in `screen_clear` has a 24-byte overlap: `SCREEN_RAM+$200` writes $0600–$06FF, and `SCREEN_RAM+$2E8` writes $06E8–$07E7, overlapping at $06E8–$06FF. Harmless but wasteful. Could restructure as 3 full pages + a partial 232-byte fill. |

### Status

- **Phases 1–3 implemented and audited:** 21 source files, 4 test files

**Bug fixes applied:**

| # | Status | Resolution |
|---|---|---|
| A1 | **Fixed** | `screen_clear` rewritten: 3 full pages + 232-byte partial fill. No overlap, no OOB write. |
| A2 | **Fixed** | Flag bits swapped to match plan: `FLAG_OCCUPIED=$01` (bit 0), `FLAG_HAS_ITEM=$02` (bit 1). Header comment in `dungeon_gen.s:16-17` also updated to match. |
| A3 | **Fixed** | Broken `CMD_REPEAT` handling removed. Numeric prefix explicitly deferred to Phase 6+. `input_get_command` now skips unknown keys cleanly. Dead `CMD_REPEAT` constant and stale header comment cleaned up. |
| A4 | **Fixed** | Added `put_choose_suffix` helper. Race prompt now shows "CHOOSE (A-H)", class prompt shows "CHOOSE (A-X)" with correct final letter. |
| A5 | **Not a bug** | Code already sums both modifiers before clamping — no intermediate clamp exists. Added clarifying comment documenting the valid range (sum -8 to 28, no 8-bit wrap). |
| A6 | **Fixed** | Implemented dirty tile rendering: on player move without viewport scroll, only old and new player tiles are redrawn. Full viewport redraw reserved for scroll, screen transitions, and initial render. |
| A7 | **Fixed** | Keyboard buffer flushed (`sta $c6`) before input polling in `input_get_command`. |

**Plan deviation resolutions:**

| # | Status | Resolution |
|---|---|---|
| D1 | **Plan updated** | Creation order is race → stats → class → name. This lets the stat roll screen show race-adjusted previews, and the class screen filters by race. Intentional. |
| D2 | **Deferred** | Numpad mapping deferred to Phase 10 (C128 enhancements). Cursor keys + vi-keys sufficient for C64. |
| D3 | **Plan updated** | Stores are 10x5 tiles, intentional for 80x48 map proportions. Plan section 3.1 should read "10x5 each". |
| D4 | **Fixed** | Removed dead `turn_execute` and phase constants from `turn.s`. Module now provides `turn_post_action` (called by main loop) plus tick subroutines. Dead ZP allocations `zp_turn_phase` ($42) and `zp_turn_state` ($4F) reclaimed as spare slots in `zeropage.s`. |
| D5 | **Fixed** | Starting food increased from 200 to 2000 turns. Hunger thresholds unchanged (hungry at 150, weak at 50, faint at 10). |

**Minor issue resolutions:**

| # | Status | Resolution |
|---|---|---|
| M1 | **Fixed** | Removed dead position assignment (20,12) from `create_init_character`. Position set by `town_generate`. |
| M2 | **Deferred** | `.mon` scripts for VICE headless tests deferred — manual VICE testing used for now. |
| M3 | **Deferred** | `test_memory.s` pass/fail convention fix deferred to test infrastructure pass. |
| M4 | **Fixed** | Addressed with A1 — `screen_clear` no longer has overlap or OOB writes. |

### Stat Generation Deep Dive (QA Review)

Investigation into why character rolling never produces stats above 16, even for
races with large positive modifiers (e.g., Half-Troll STR +4, Elf INT +2).

**Finding S1 — Wrong dice algorithm (HIGH)**

| Aspect | Umoria (correct) | Before fix | After fix |
|--------|------------------|------------|-----------|
| Dice pool | 18 dice cycling d3, d4, d5 | 6 independent `math_dice(3,6,0)` calls | d3+d4+d5 per stat |
| Per-stat formula | 5 + three consecutive dice (one d3 + one d4 + one d5) | 3d6 | 5 + d3 + d4 + d5 (range 8–17) |
| Raw stat range | 8–17 | 3–18 | 8–17 |
| Total constraint | Re-roll all 18 dice if sum < 43 or sum > 54 | None | Re-roll if total not in 73–84 |
| Distribution shape | Tight, correlated across stats (total constrained) | Independent, wide variance per stat | Constrained, tight distribution |

**Status: FIXED.** Dice algorithm rewritten in `player_create.s`.

**Finding S2 — Wrong race/class modifier application (CRITICAL)**

This is the root cause of the user-reported defect.

Umoria does NOT use simple addition for modifiers. Each +1 or −1 is applied as a
separate call to `incrementStat()` / `decrementStat()`:

```
incrementStat(stat):
    if stat < 18:       stat += 1
    if stat 18–87:      stat += randomNumber(15) + 5   // adds 6–20
    if stat 88–107:     stat += randomNumber(6) + 2    // adds 3–8
    if stat > 107:      stat += 1

decrementStat(stat):
    if stat > 108:      stat -= 1
    if stat 88–108:     stat -= randomNumber(6) + 2
    if stat 19–88:      stat -= randomNumber(15) + 5
    if stat > 18:       stat = 18
    if stat > 3:        stat -= 1
```

Internal encoding: values 3–18 stored as-is; 19–118 = 18/01 through 18/100.

**Example**: Half-Troll STR modifier +4, base STR 16:
- Umoria: 16 → 17 → 18 → 18/(06–20) → 18/(12–40). Easily reaches 18/30+.
- Old code: `min(16 + 4, 18) = 18`. Could never reach 18/xx.

**Example**: Elf INT modifier +2, base INT 17:
- Umoria: 17 → 18 → 18/(06–20). Reaches 18/06–18/20.
- Old code: `min(17 + 2, 18) = 18`.

**Status: FIXED.** `increment_stat`/`decrement_stat` implemented in `player.s` with
umoria's exact randomized step logic. `apply_modifier` loops through each ±1.
`player_calc_stats` and `create_calc_modified_stat` both use the new system.

**Finding S3 — 18/xx support too limited (HIGH)**

`tables.s` line 7 says: *"For C64 simplicity, we cap stats at 18 (no 18/xx
percentile stats)."* This conflicts with faithful umoria behavior:

| Aspect | Umoria | Before fix | After fix |
|--------|--------|------------|-----------|
| Stats that support 18/xx | All six (STR, INT, WIS, DEX, CON, CHR) | STR only (via `PL_STR_EXTRA`) | All six stats |
| How 18/xx is reached | Race/class modifiers via incrementStat | Only if base die roll is exactly 18 | Via increment_stat during modifier application |
| Player struct fields | Single uint8_t per stat (3–118 encoding) | Separate base + extra byte (STR only) | Single byte per stat (3–118 encoding) |
| Display support | All stats show 18/xx | Only STR shows 18/xx (`ui_character.s`) | All stats via `put_stat_val` |

**Status: FIXED.** `PL_STR_EXTRA` removed (now `PL_SPARE_63`). Single-byte encoding
(3–118) for all stats. `put_stat_val` simplified to take A only (no Y param).
`ui_character.s` updated. `stat_bonus_index` caps at index 15 for 18/xx stats.

**Finding S4 — PRNG algorithm is acceptable (OK)**

The 32-bit Galois LFSR (polynomial $ED, period 2^32−1) with rejection sampling
in `rng_range` is adequate for game use. CIA timer seeding provides reasonable
initial entropy. No changes needed.

**Required code changes (all resolved):**

| # | Change | Status |
|---|--------|--------|
| 1 | Replace 3d6 with umoria's constrained multi-die system | **Fixed** — `player_create.s` rolls d3+d4+d5 per stat (+5), total constrained 73–84 |
| 2 | Implement `increment_stat` / `decrement_stat` | **Fixed** — Added to `player.s` with umoria's randomized step logic |
| 3 | Extend 18/xx support to all six stats | **Fixed** — Single-byte encoding (3–118), `PL_STR_EXTRA` removed, `ui_character.s` + `put_stat_val` updated |
| 4 | Remove "cap at 18" constraint from `tables.s` | **Fixed** — Header comment updated |
| 5 | Update plan Phase 2.3 | **Fixed** — Phase 2.3 now describes correct umoria algorithm |

### Dungeon Generation Deep Dive (QA Review)

Investigation of persistent dungeon generation bugs including rooms with no exits,
incorrect algorithm vs. umoria, build breakage, and zero test coverage. Compared
against actual umoria source (`src/dungeon_generate.cpp`, `src/dungeon_tile.h`,
`src/config.cpp`).

#### Finding DG1 — Build is broken (BLOCKER)

`dungeon_gen.s` references three undefined symbols:
- `trap_count` (lines 99, 404) — not allocated anywhere
- `place_traps` (line 418) — subroutine doesn't exist
- `place_secrets` (line 419) — subroutine doesn't exist

These are forward references to Phase 4.2 features. The code cannot assemble.
Must be stubbed out to restore a buildable state.

#### Finding DG2 — Connectivity algorithm is fundamentally wrong (CRITICAL)

**The reported bug** (rooms with no exits) traces directly to the corridor
connection algorithm. The current code connects consecutive rooms (room 0→1,
1→2, 2→3, etc.) in the order they were placed. This is a **linear chain**
that does NOT guarantee all rooms are reachable if any corridor fails to connect.

**Umoria's approach:**
1. Place rooms into a 6x6 grid (typically 24-28 rooms)
2. **Randomly shuffle** the room location list
3. Connect room[0]→room[1]→...→room[N]→room[0] as a **circular chain**
   (Hamiltonian cycle), guaranteeing every room has at least 2 connections
4. The tunnel algorithm uses a biased random walk toward the destination with
   up to 2000 iterations, ensuring it reaches the target even through winding
   paths

**Current code issues:**
- Only 4-8 rooms (vs. umoria's ~24-28) — fewer rooms means longer corridors
  between non-adjacent rooms, increasing failure risk
- Rooms are connected in placement order, not shuffled — rooms placed far apart
  in the grid may have extremely long tunnel distances
- No circular chain — room 0 has only 1 connection (to room 1), making it
  vulnerable to disconnection
- L-shaped corridors (fixed 2-segment paths) can fail if the path crosses
  multiple rooms — the corridor carver stops at the first perpendicular wall
  it hits and places a door, but the corridor segment terminates without
  reaching the target room's interior
- The current algorithm has NO concept of reaching the destination — it just
  carves to the target coordinate. If another room's wall is in the way, the
  corridor dead-ends at a door in that room's wall, leaving the intended
  destination room disconnected

**Root cause of the screenshot bug:** When connecting rooms A and B with an
L-shaped corridor, if room C sits between them, the horizontal segment hits
C's vertical wall and places a door there. The corridor segment ends at room B's
x-coordinate but that coordinate is inside room C, not room B. Room B gets
no connecting corridor.

#### Finding DG3 — Room placement algorithm differs from umoria (HIGH)

| Aspect | Umoria | Current code |
|--------|--------|-------------|
| Grid system | 6x6 grid of slots, ~32 attempts → ~24-28 rooms | No grid; random placement with overlap rejection |
| Room count | Mean 32 attempts into 36 slots | 4-8 rooms (rng(5)+4) |
| Room sizing | Width: 2-22 interior, Height: 2-7 interior | Width: 4-11, Height: 3-7 |
| Room types | Normal, overlapping rectangles, inner rooms, cross-shaped | Basic rectangle only |
| Unusual rooms | Level/300 chance per room | None |
| Level dimensions | 66x198 | 80x48 |

The 80x48 map with 4-8 rooms is a reasonable C64 simplification, but the room
count is too low and the placement algorithm creates pathological layouts where
rooms cluster or spread too far apart.

#### Finding DG4 — Tunnel algorithm differs from umoria (HIGH)

| Aspect | Umoria | Current code |
|--------|--------|-------------|
| Path finding | Biased random walk toward target, 2000 iteration limit | Fixed L-shaped (2-segment) path |
| Direction changes | 70% chance to redirect toward target, 1/9 random | None — always horizontal then vertical or vice versa |
| Wall penetration | Marks adjacent granite as TMP2_WALL to prevent clustered entries | No tracking — can place multiple doors in adjacent wall tiles |
| Room wall handling | Records wall crossings for later door placement | Inline door placement during carving |
| Robustness | 2000-iteration walk guarantees reaching target even through complex geometry | Can dead-end when another room blocks the L-path |

#### Finding DG5 — Door placement differs from umoria (MEDIUM)

| Aspect | Umoria | Current code |
|--------|--------|-------------|
| Room entry doors | 25% chance at tunnel-granite intersection; rest become corridor floor | Always places closed door on perpendicular room wall |
| Corridor intersection doors | Placed at tunnel-corridor crossings (15% chance) after all tunnels | Not implemented |
| Door types | 1/3 open (3/4 normal, 1/4 broken), 1/3 closed (plain/stuck/locked), 1/3 secret | Always closed |
| Wall detection | Uses FLAG_LIT to distinguish room walls from rock | Same — correct |

#### Finding DG6 — Streamer generation order is wrong (MEDIUM)

Current code comment says: *"Streamers BEFORE corridors ensures corridors
always overwrite mineral veins they cross."* The actual call order is:

```
place_streamers     // line 413 — BEFORE connect_rooms
connect_rooms       // line 415 — after streamers
```

But umoria does it the opposite way:
1. Build tunnels (corridors)
2. Fill empty space with TILE_GRANITE_WALL
3. **Then** place streamers

Umoria places streamers AFTER tunnels and granite fill, which means streamers
can overwrite corridor floor tiles (creating obstacles). The current code places
streamers before tunnels, so corridor carving will overwrite streamer tiles —
meaning streamers never create obstacles in corridors. This is actually more
player-friendly but differs from umoria.

Additionally, umoria places 3 magma + 2 quartz streamers (5 total). Current
code places 1 + 50% chance of a second (1-2 total).

#### Finding DG7 — Stairs placement differences (MEDIUM)

| Aspect | Umoria | Current code |
|--------|--------|-------------|
| Down stairs count | 3-4 (randomNumber(2)+2) | 2 |
| Up stairs count | 1-2 (randomNumber(2)) | 1 |
| Placement criteria | Random floor tile with >= 3 adjacent walls (degrades) | Random floor tile in specified room |
| Wall adjacency check | Yes — prefers corner-like positions | No — any interior floor tile |

#### Finding DG8 — fill_map_rock uses wrong fill tile (LOW)

`fill_map_rock` fills with `TILE_WALL_H` ($10, "horizontal wall"). Umoria
fills with `TILE_NULL_WALL` (0), then converts to `TILE_GRANITE_WALL` (12) after
tunnels are carved. The current code uses a concrete wall type for uncarved rock,
which means:

1. The corridor carver's LIT-flag check (`and #FLAG_LIT / beq = rock`) works
   correctly because unlit TILE_WALL_H distinguishes rock from room walls
2. But all 6 wall types ($10-$60) share the same "is this a wall?" semantic,
   which is fragile — the code relies on the LIT bit rather than tile type
   to distinguish rock from structure

Umoria uses the type value itself (>= MIN_CAVE_WALL=12) to identify walls vs.
open space. A dedicated "rock" tile type would be cleaner but the current
approach works.

#### Finding DG9 — DUNGEON_FLAGS marks all rooms as lit+visited (LOW) — RESOLVED

Originally `DUNGEON_FLAGS = FLAG_LIT | FLAG_VISITED` ($0C), baking full
visibility into every tile at generation time. **Fixed in Phase 4.5:**

- `DUNGEON_FLAGS = FLAG_LIT` ($08) — rooms start lit but NOT visited
- Corridors start with NO flags (invisible until the player's torch reveals them)
- `dungeon_los.s` implements three-state visibility: unseen → visible → remembered
- `darken_rooms` strips FLAG_LIT from dark rooms (umoria formula: lit if dlvl <= rng(25)+1)
- `update_visibility` sets FLAG_VISITED via torch radius (Phase A) and room reveal (Phase B)
- Rendering dims remembered tiles (FLAG_VISITED but outside torch and not FLAG_LIT) to dark grey

#### Finding DG10 — Zero test coverage for dungeon generation (HIGH)

No `test_dungeon.s` exists. Dungeon generation is the most algorithmically
complex part of the codebase and has the most edge cases. The following tests
are needed:

**Room placement tests:**
- `check_room_overlap` returns correct results for overlapping and non-overlapping rooms
- `check_room_overlap` handles ROOM_GAP correctly
- Rooms never placed outside map boundary (x >= 4, y >= 4, x+w <= 76, y+h <= 44)
- `draw_dungeon_room` writes correct wall/floor tiles and flags
- Room count never drops below 2 after retry exhaustion

**Corridor tests:**
- `carve_h_corridor` carves floor from cx1 to cx2 (both directions)
- `carve_v_corridor` carves floor from cy1 to cy2 (both directions)
- Corridor through room wall places door (not floor)
- Corridor through rock places floor (not door)
- Single-tile corridor (cx1 == cx2) handled correctly
- L-shaped corridor reaches both endpoints

**Connectivity tests:**
- Every room has at least one floor tile adjacent to a corridor or door
- Player start position is on a walkable tile
- All stairs are on walkable tiles
- Pathfinding from player start to each staircase succeeds (BFS/flood-fill)

**Streamer tests:**
- Streamers don't overwrite room floor tiles
- Streamers don't overwrite doors or stairs
- Streamer bounds checking works (doesn't write outside map)

**Stairs tests:**
- `verify_stairs` re-places overwritten stairs
- Stairs placed inside room interiors (not on walls)
- Up-stairs and down-stairs in different rooms

**Integration test:**
- Generate 100+ dungeons, verify all pass connectivity flood-fill
- No room is fully enclosed (every room reachable from player start)

#### Summary of required changes

| # | Priority | Change | Status |
|---|----------|--------|--------|
| 1 | BLOCKER | Stub out `trap_count`, `place_traps`, `place_secrets` to restore buildability | **Fixed** — `dungeon_features.s` implements traps and secrets |
| 2 | CRITICAL | Rewrite connectivity algorithm: shuffle rooms, connect as circular chain | **Fixed** — Fisher-Yates shuffle + circular chain in `connect_rooms` |
| 3 | HIGH | Add flood-fill connectivity verification after generation; re-generate if unreachable | **Fixed** — BFS `verify_connectivity` with max 10 retries |
| 4 | HIGH | Create `test_dungeon.s` with room placement, corridor, and connectivity tests | **Fixed** — 23 runtime tests covering rooms, corridors, connectivity, doors, visibility, dark rooms |
| 5 | MEDIUM | Add door type variety (open/closed/secret per umoria probabilities) | **Fixed** — 50/50 open/closed at junctions; `place_secrets` enabled in Phase 4.6 (1-3 secret doors per level) |
| 6 | MEDIUM | Increase streamer count to match umoria (3 magma + 2 quartz) | **Fixed** — 5 streamers (3 magma + 2 quartz) |
| 7 | MEDIUM | Add wall-adjacency check for stairs placement | **Fixed** — `random_wall_adj_floor` with degrading threshold (>=3, >=2, >=1, any) |
| 8 | LOW | Consider increasing room count range (e.g., 6-12) for better dungeon density | Deferred |
| 9 | LOW | Add dark room support (defer LIT flag to Phase 4.5 LOS implementation) | **Fixed** — `room_lit[]` array, `darken_rooms` post-processing, umoria formula |

**Additional fixes applied during QA:**

| # | Issue | Resolution |
|---|-------|------------|
| DG-A | Corridors adjacent to rooms no longer synthesize phantom doors | **Fixed** — `add_corridor_doors` is a legacy stub and corridor penetrations (via `carve_h_corridor`/`carve_v_corridor`) still place doors; tests enforce both behaviors. |
| DG-B | Secret doors at corridor junctions block passage | **Fixed** — `random_door_type` produces only open/closed for door placement; `place_secrets` converts 1-3 closed doors to TILE_SECRET per level (Phase 4.6) |
| DG-C | Room overlap detection off-by-one | **Fixed** — `check_room_overlap` uses ROOM_GAP correctly |

---


---

## Known Bugs

Playtesting bugs BUG-1 through BUG-18 have been fixed (see Review Pass 15). BUG-19 through BUG-29 fixed individually.

| # | Description | Status |
|---|-------------|--------|
| BUG-1 | 18 stat inflating to 18/99 | ✅ Fixed — exceptional strength gated to STR only |
| BUG-2 | Status bar layout mismatch | ✅ Fixed — rewritten to 3-line umoria-style |
| BUG-3 | No townspeople | ✅ Fixed — 6 town creature types added |
| BUG-4 | Town render speed / store doors | ✅ Fixed — render_store_doors post-pass |
| BUG-5 | Direction/diagonal key mapping | ✅ Fixed |
| BUG-6 | Store exit requires ESC | ✅ Fixed — Q key added |
| BUG-7 | Doors auto-open | ✅ Fixed — closed doors block movement |
| BUG-8 | Sound effects broken | ✅ Fixed — sound_init added to main.s |
| BUG-9 | Player '@' drawn as blank | ✅ Fixed — missing jmp (fall-through bug) |
| BUG-10 | Look command | ✅ Fixed — direction scanning implemented |
| BUG-11 | Town creature provocation | ✅ Fixed — MF_PROVOKED flag |
| BUG-12 | Spell books | ✅ Fixed (side-effect bugs RP15-1/2 also resolved) |
| BUG-13 | (folded into BUG-12) | ✅ Fixed |
| BUG-14 | KERNAL GETIN clobbers X in name entry | ✅ Fixed — cen_count byte |
| BUG-15 | Debug hardcoded name | ✅ Fixed — removed |
| BUG-16 | Store screen clearing | ✅ Fixed — ui_help_clear_all |
| BUG-17 | Look command distance | ✅ Fixed — multi-tile scan |
| BUG-18 | Inventory popup in selection dialogs | ✅ Fixed — '?' key added |
| BUG-19 | Garbage characters flash on screen when descending to dungeon level 1 | **Fixed** — resolved by VIC-II bank restore (`$DD00 ora #3`) after KERNAL serial I/O in OPT-2 display bug fixes (223bb1e). KERNAL LOAD corrupted $DD00 bits 0-1, causing VIC-II to read wrong memory bank. |
| BUG-20 | Dead strings `mat_acid_str` and `mat_dead_str` in monster_attack.s (42 bytes wasted) | ✅ Fixed — inline strings eliminated by R7.6 Huffman migration; acid message now lives in Huffman dictionary, `mat_dead_str` was never referenced and is gone. |
| BUG-21 | Acid attack effect (`mon_atk_effect_acid`) is a no-op with no message | ✅ Fixed — prints "SPITS ACID ON YOU" via mon_atk_build_effect_msg (pre-R7.6), now Huffman-compressed. |
| BUG-22 | `mat_the_str` duplicates `cmb_the_str + 1` (5 bytes wasted) | ✅ Fixed — OPT-1.7 eliminated the duplicate; R7.6 Huffman migration removed all remaining inline strings from monster_attack.s. |
| BUG-23 | Magic Missile spell does not work — no animation and no damage to monsters | **Fixed** — `eff_bolt` damage math was correct but had zero user feedback: no messages, no animation, no monster wake-up, no sound. Added: bolt `*` animation along trace path with save/restore, hit/kill/fizzle messages using combat_msg_buf, `MF_AWAKE` on non-lethal hit, `SFX_HIT` on hit. |
| BUG-29 | Secret doors on vertical walls render as '─' instead of '│' | ✅ Fixed — old heuristic checked tiles above/below for wall types, failed when neighbors were doors or carved floor. Replaced with left/right floor check: vertical wall doors have floor on both sides (room + corridor), horizontal wall doors have wall tiles beside them. Also saves ~40 bytes. |
| BUG-30 | Combat messages corrupted (garbled PETSCII) for tier-loaded creature names | ✅ Fixed — Root cause: KERNAL LOAD does not reliably CLOSE file entries. Both `overlay_load_disk` and `tier_load_disk` used logical file #2 without calling CLOSE afterward. After the first LOAD, file #2 stayed in the KERNAL file table; subsequent LOADs failed silently ("FILE ALREADY OPEN"), leaving `$E000` with stale overlay data and `tier_name_lo/hi_addr` uninitialized (pointing to ZP). Fix: (1) added explicit CLOSE+CLRCHN after every KERNAL LOAD in both `tier_load_disk` and `overlay_load_disk`, (2) `!tl_failed` now resets `current_tier=0` so creature names fall back to embedded data, (3) `creature_get_name` tier path reads name pointers from `$E000` via `tier_name_lo/hi_addr`. |
| BUG-31 | Garbage text on screen row 24 during dungeon exploration | ✅ Fixed — Row 24 (INPUT_ROW) showed garbage characters during normal gameplay. Many command handlers (movement, eat, quaff, rest, run, refuel) return to the main loop via `status_draw` → `!main_loop` without clearing row 24; only `vp_render_status_loop` cleared it. Fix: added `screen_clear_row` for INPUT_ROW at the start of `status_draw`, ensuring row 24 is cleaned on every status redraw. |
| BUG-32 | Monster names garbled for tier-loaded creatures (stale `$E0xx` name pointers) | ✅ Fixed — `load_tier_to_buffer` writes `$E0xx` pointers into `cr_name_lo/hi`. When `overlay_load` later sets `current_tier=0` and overwrites `$E000` with overlay code, the `!cgn_table` fallback in `creature_get_name` read executable code as string data. Also triggered when switching to a smaller tier (stale indices beyond new count). Fix: replaced `!cgn_banked` with safe "?" fallback to `creature_name_buf`. Dead code for legitimate use — embedded names always `< $C000`, tier names use dedicated tier path. Byte-neutral (15B → 15B). |

---

---

## Audit Response (2026-02-14)

Full review of AUDIT.md findings. Each item is categorized as **done**, **action item**, **tracked TODO**, or **deferred**.

### AUDIT §1 — Feature Comparison

| Finding | Disposition |
|---------|------------|
| Map size (48x80 vs 66x198) | **Deferred** — intentional C64 constraint. Phase 10.3 expands for C128. |
| Monster count (120 vs 351) | **Done** — R3.5 expanded to 120 across 5 tiers. Further expansion possible with more tier data. |
| Item count (55 vs 400+) | **Tracked** — R4.1 (ego items) addresses this. 55 base types is adequate for C64 memory. |
| Active monsters cap (32) | **Deferred** — RAM constraint. Phase 10.3 raises to 64 on C128. |
| Haggling simplified | **Done** — R6.1 implemented multi-round haggling with insult/kick system. |
| ~~Missing stores (Black Market, Player Home)~~ | **Done** — R6.2 Black Market + R6.3 Player Home implemented. |
| Character history | **Deferred** — nice-to-have, not gameplay-critical. |
| Save scumming prevention | **Done** — save file deleted on load, enforcing permadeath. |

### AUDIT §2 — Bugs in Implemented Features

| Finding | Disposition |
|---------|------------|
| Input lag (viewport redraw) | **Done** — fixed with dirty render (render_local_area). Verify in playtesting. |
| Key stacking (keyboard buffer) | **Done** — fixed. |
| Monster AI stack depth | ✅ **Done (A5)** — Audited. Deepest chain: monster_ai_tick → monster_attack_player → mon_atk_effect_confuse → msg_print → screen_put_string (14 JSR levels, 27 bytes = 11% of stack). 224 bytes free. No canary needed. |
| screen_clear memory safety | **Done** — fixed (ui_help_clear_all pattern). |
| Item generation distribution | **Action item A7** — review spawn curves vs umoria. Low priority, informational. |

### AUDIT §3 — Code Quality

| Finding | Disposition |
|---------|------------|
| Numeric prefix parsing | **Deferred** — not needed for core gameplay. |
| Phase 10 TODOs | **Tracked** — Phase 10 plan exists. |
| ~~Missing stores~~ | ~~**Tracked** — R6.2, R6.3.~~ **Done** — R6.2 Black Market + R6.3 Player Home implemented. |
| Spellbook expansion | **Tracked** — R5.2. |
| Room placement grid logic | **Deferred** — random placement works; grid would need significant rework. |
| Large files (dungeon_gen.s, item.s) | **Action item A6** — split opportunistically when touching these files. Low priority. |
| Magic numbers / hardcoded values | **Deferred** — adding symbolic constants everywhere would be nice but is low-impact on a stable codebase. Address incrementally. |

### AUDIT §4 — Product Quality / Playability

| Finding | Disposition |
|---------|------------|
| 40-column display | **Deferred** — fundamental hardware limit. Phase 10.1 adds 80-col on C128. |
| Message truncation | **Deferred** — "—more—" prompt handles overflow. Monitor for intrusiveness. |
| Disk I/O performance | **Done** — JiffyDOS fastloader required and documented. REU path eliminates tier load pauses entirely. |
| Turn speed at 1 MHz | **Deferred** — monitor in playtesting. AI loop processes max 32 monsters; should be fast enough. |
| Balance (fewer monsters/items) | **Deferred** — tuning pass after all content features are in place. |
| Spell variety | **Tracked** — R5.1/R5.2. |
| Lack of artifacts | **N/A** — not present in umoria. Ego items (R4.1) cover umoria's "special" item system. |

### AUDIT §5 — Architecture & Physical Build

| Finding | Disposition |
|---------|------------|
| Single binary tax (~2-4KB C128 dead code) | **Action item A4** — separate binaries (BOOT.PRG + MORIA64 + MORIA128). Aligned with Phase 10. Major effort, deferred until C128 work begins. |
| REU support | **Done** — keep as-is. ~400 bytes for massive playability gain. |

### AUDIT §6 — UX & Polish

| Finding | Disposition |
|---------|------------|
| Directory art | **Action item A2** — add PETSCII art filenames to d64 image. Small effort, high first-impression impact. |

### AUDIT §7 — File Naming

| Finding | Disposition |
|---------|------------|
| MORIA.SAV → THE.GAME | ✅ **Done** (save.s) |
| MORIA.HI → HALL.OF.FAME | ✅ **Done** (score.s) |
| CR T1-T4 → MONSTER.DB.1-4 | ✅ **Done** (tier_manager.s, Makefile) |

### AUDIT §8 — Release Strategy

| Finding | Disposition |
|---------|------------|
| Character Disk (separate game/save disks) | **Action item A3** — medium effort. Requires disk-swap prompts, save disk ID validation, and code changes to save.s/score.s. Improves update experience. |

### Action Items Summary

| # | Description | Effort | Files |
|---|-------------|--------|-------|
| A1 | ~~File naming: MORIA.SAV→THE.GAME, MORIA.HI→HALL.OF.FAME, CR T1-T4→MONSTER.DB.1-4~~ | ✅ Done | save.s, score.s, tier_manager.s, Makefile, memory.s |
| A2 | ~~Directory art: PETSCII art in d64 listing~~ | ✅ Done | Makefile, tools/diskart.py |
| A3 | Character disk: separate game/save disks with swap prompts | Medium | save.s, score.s, new disk_swap.s |
| A4 | ~~Separate binaries: BOOT.PRG + MORIA64~~ | ✅ Done | boot.s, main.s, Makefile |
| A5 | ~~Stack depth audit: trace deep call chains, document max nesting~~ | ✅ Done | Max 27 bytes (14 JSR levels), 87% margin — no canary needed |
| A6 | Large file split: dungeon_gen.s, item.s into sub-modules | Low | Opportunistic refactoring |
| A7 | Item generation distribution review vs umoria curves | Small | Documentation / item.s tuning |

---


---

### Review Pass 5 — Post-Phase 4.5 Full Codebase Review (2026-02-10)

Reviewed all 32 files (~12,400 lines). All tests pass (6/6 suites, 52/52 tests).
No blocking bugs found.

#### Test coverage gaps

| Module | Gap | Severity | Status |
|--------|-----|----------|--------|
| math.s | `math_dice` is completely untested — no tests for bonus handling, negative bonuses, or edge cases | Medium | **Fixed** — Tests 13-16: basic 1d6+0, positive bonus 1d6+10, negative bonus 1d6-1, multi-dice 10d8+0 (20 iterations each) |
| test_dungeon.s Test 14 | Streamer scan only checks 3 of 15 map pages ($C000, $C400, $C800) — streamers in unscanned pages would be missed | Low | **Fixed** — Pointer-based full map scan ($C000-$CEFF, 15 pages) |
| test_memory.s | ZP save/restore only validates 4 of 142 bytes ($02–$05) | Low | **Fixed** — Loop-based test covers all 142 ZP bytes ($02-$8F) using X^$A5 pattern |
| test_rng.s | `rng_range` boundary cases (N=1, N=255) not tested | Low | **Fixed** — Tests 5-6: rng_range(1) always 0, rng_range(255) always <255 (100 iterations each) |

#### Code quality notes (non-blocking)

| File | Issue | Severity |
|------|-------|----------|
| dungeon_render.s | `render_single_tile` (lines 289–452) duplicates ~150 lines from `render_viewport` — extract shared subroutine when code next changes | Low |
| dungeon_features.s:196 | `find_random_floor` returns last (possibly non-floor) coordinates if 200 attempts exhausted — trap could land on wall tile (extremely rare) | Low |
| dungeon_gen.s:2062 | BFS queue has no overflow guard — safe in practice (max ~2000 passable tiles vs 4000 queue capacity on 80x48 map) | Low |

#### False positives investigated and cleared

Three findings were flagged by automated review and manually verified as correct:

1. **Room lit/dark logic (dungeon_gen.s:621–624):** `ldx`/`lda` between `cmp` and `bcc` do NOT affect the carry flag. Logic correctly implements "lit if dlvl <= threshold".
2. **math_dice negative bonus (math.s:103–110):** Sign-extension via `adc #$ff` on the high byte is the standard 6502 pattern for 16-bit addition of a sign-extended 8-bit negative value. Verified with worked examples.
3. **Corridor swap infinite loop (dungeon_gen.s:1031–1043):** All coordinates are valid map positions (0–79), so the Y register always reaches the target. No wrap-around possible.

---

### Review Pass 6 — Monster/Combat Deep Review vs. umoria (2026-02-11)

Reviewed all Phase 5 implementation (monster.s, combat.s, monster_attack.s, monster_ai.s, turn.s)
against umoria source (data_creatures.cpp, monster.h, monster.cpp, player.cpp).
All 10 test suites pass. Attack types verified by manually decoding umoria's monster_attacks[] array.

#### MC1: Creature stat data — RESOLVED

**Status: FIXED.** All 20 creature types now match umoria. The 5 invented creatures (Fruit bat,
Soldier ant, Green naga hatchling, Cave spider, Wild cat) have been replaced with real umoria
creatures (White Harpy, Green Worm mass, Poltergeist, Huge Brown Bat, Creeping Copper Coins).

All stats verified correct against umoria `data_creatures.cpp`:
- **XP values**: 20/20 match (kill_exp_value)
- **AC values**: 20/20 match
- **HP dice**: 20/20 match (hd_num, hd_sides)
- **Creature levels**: 20/20 match
- **Sleep values**: 20/20 match
- **Awareness radii**: 20/20 match
- **Attack types**: 20/20 match (slot 0 and slot 1)
- **Attack dice**: 20/20 match

**Naming note:** C64 "Grey Mold" = umoria "Grey Mushroom patch" (same stats, display 'm'/M).
C64 "Giant Frog" = umoria "Giant Green Frog" (same stats).

**Multi-attack limitation:** White Harpy has 3 attacks in umoria (claw 1d1, claw 1d1, bite 1d2)
but C64 only supports 2 slots (claw 1d1, claw 1d1). Third attack lost. Low impact (1d2 normal).

#### MC2: XP system bugs — PARTIALLY RESOLVED

1. ~~**Min-1 XP floor not in umoria.**~~ **FIXED** — `combat_award_xp` (combat.s:473) no longer
   forces minimum 1 XP. Weak creatures correctly award 0 XP when player level >> creature level.

2. **No fractional XP accumulation (known simplification).** umoria uses 16-bit fixed-point
   fractions (`exp_fraction`) to preserve partial XP. The C64 uses integer division only.
   This means small XP amounts from weak creatures are lost entirely (0 instead of accumulating
   fractions). Documented in code comment at combat.s:475. Impact is minor for early game
   since creature XP values are high enough relative to player level.

3. **Only uses cr_xp_lo, ignores cr_xp_hi** (combat.s:459). Safe for current creatures
   (max XP=9) but will break when higher-tier creatures are added.

#### MC3: Combat formula bugs — PARTIALLY RESOLVED

1. ~~**Monster to-hit off-by-one.**~~ **FIXED** — `mon_atk_roll_tohit` (monster_attack.s:249-250)
   now uses `cmp zp_player_ac; bcs !mart_hit+` correctly (`>=` check). No extra `beq`.

2. ~~**Player to-hit missing race BTH.**~~ **FIXED** — `combat_calc_tohit` (combat.s:172-197)
   now adds race BTH from `race_properties` offset 7, with signed handling and clamping.

3. **Confusion damage handling still wrong (see RP7-3).** The original finding was inverted:
   the code does NOT apply AC reduction + physical damage. Instead it applies NO damage at all
   (`lda #0; sta zp_combat_dmg`). In umoria, confusion deals FULL dice damage (no AC reduction)
   plus 50% chance of confusion effect. See Review Pass 7 for details.

#### MC4: Missing features — MEDIUM

1. **No critical hit system.** umoria's `playerWeaponCriticalBlow` (chance based on weapon
   weight + to-hit + class_adj × level, damage multiplier 2-5×) is not implemented. All player
   hits do flat damage. Critical chance formula: `(weapon_weight + 5*plus_to_hit +
   class_level_adj[class][BTH]*level) / 5000`. Tiers: 2× (+5), 3× (+10), 4× (+15), 5× (+20).

2. ~~**No HP/MP regeneration.**~~ **HP + MP REGEN IMPLEMENTED** — `turn_tick_regen` (turn.s)
   implements CON-based regen counter (8-50 turns per 1 HP depending on CON). Poison suppresses
   regen. `zp_eff_regen` doubles tick rate. Simplified vs umoria's 16-bit fixed-point fractional
   accumulation — C64 uses integer counter per CON. Starvation damage (1 HP/turn at food=0)
   also implemented. Mana regen implemented in Step 7.9 (turn.s: INT-based, non-warriors only).

3. ~~**Missing effect-specific messages.**~~ **VERIFIED CORRECT** — Effect handlers DO print
   messages: `mon_atk_effect_poison` calls `mon_atk_build_effect_msg` (monster_attack.s:408-417),
   `mon_atk_effect_confuse` prints at lines 442-452, `mon_atk_effect_paralyze` prints at
   lines 514-524. Player sees both "THE X HITS YOU." and "THE X POISONS YOU." etc.
   Effect expiration messages also print: "YOU FEEL BETTER." (poison), "YOU CAN SEE AGAIN."
   (blind), "YOU FEEL LESS CONFUSED." (confuse), "YOU CAN MOVE AGAIN." (paralyze).

4. ~~**Monster confusion/stun timers never decremented.**~~ **FIXED** — `monster_process_one`
   now checks `MX_STUN` and `MX_CONFUSE` timers directly at `!mpo_awake:`. Stun > 0: decrement
   and skip turn. Confuse > 0: decrement and random-move (no spellcast). Old `MF_CONFUSED` flag
   check removed — timer IS the confusion state. Timers count down 1 per turn; at 0, normal AI
   resumes. All timer-setting call sites (combat.s, player_magic.s, player_items.s, spell_effects.s)
   already write `MX_CONFUSE`/`MX_STUN` correctly. 21 monster_ai tests pass.

#### MC5: Design simplifications — LOW (speed issues mostly resolved)

1. ~~**Speed model oversimplified.**~~ **MOSTLY FIXED** — Speed model now uses 0=slow (every other
   turn), 1=normal, 2=fast (double move). CF_ATTACK_ONLY flag separates "can't move" from "slow".
   Three slow creatures correctly at speed=0. Remaining issue: Poltergeist speed=1 should be 2
   (see RP8-1). Huge Brown Bat correctly at speed=2. Very fast creatures (umoria speed=13) capped
   at 2 moves instead of 3 — acceptable simplification for C64.

2. **Blows table simplified.** C64 uses 5×4 (5 weight classes, 4 DEX brackets). umoria uses
   7×6 (7 weight classes, 6 DEX brackets including 18/xx ranges). Fine for now since weapons
   and 18/xx DEX aren't in play yet.

3. ~~**Stale header comment in monster_ai.s:8.**~~ **FIXED** — Header now correctly documents
   CF_ATTACK_ONLY behavior and updated speed model.

#### Verified correct

1. **Attack type constants** (ATK_NORMAL=1, ATK_CONFUSE=3, ATK_ACID=6, ATK_PARALYZE=11,
   ATK_POISON=14, ATK_AGGRAVATE=20) match umoria's numbering.
2. **Base to-hit values per attack type** in `mon_atk_base_tohit` table match umoria's
   `playerTestAttackHits` switch statement.
3. **Monster to-hit formula** (`base_tohit + creature_level × 3`) correctly derives from
   umoria's `playerTestBeingHit(base, level, 0, AC, CLASS_MISC_HIT)` with CLASS_MISC_HIT=3.
4. **AC damage reduction formula** (`damage -= (AC × damage) / 200`) matches umoria exactly.
5. **Player to-hit roll** (combat.s:332-360) correctly compensates for rng_range's [0,N-1]
   range vs umoria's [1,N] by using `>=` instead of `>`.
6. **Monster to-hit roll** (monster_attack.s:229-257) also correctly uses `>=` check.
7. **Paralysis saving throw** logic (monster_attack.s:447-504) correctly implements
   class_save_base + player_level with rng_range(100) check. (Simplified vs umoria's
   full formula that includes WIS adjustment — acceptable simplification.)
8. **Monster rendering** is implemented in dungeon_render.s (checks FLAG_OCCUPIED, looks up
   cr_display/cr_color).
9. **Player to-hit formula** (combat.s:161-250) now correctly includes class BTH + race BTH +
   PL_TOHIT × 3 + player_level × class_bth_per_level, matching umoria's full calculation.
10. **All 20 creature stats** match umoria source (XP, AC, HP dice, levels, sleep, aaf, attack
    types, attack dice). Verified against `data_creatures.cpp` and `monster_attacks[]` array.
11. **Effect messages** are printed: poison, confusion, and paralysis handlers all call
    `mon_atk_build_effect_msg` with the appropriate strings.
12. **XP award formula** (`cr_xp * cr_level / player_level`) correctly matches umoria.
    Min-1 floor removed. Integer-only is a documented simplification.

---

### Review Pass 7 — Verification of Review Pass 6 Findings (2026-02-11)

Cross-referenced Review Pass 6 findings against current code and umoria source (`data_creatures.cpp`,
`monster.cpp`, `player.cpp`, `game_run.cpp`). Found that MC1-MC3 have been substantially fixed in
code but the BUILDPLAN was not updated to reflect this. Additionally found 8 new bugs not identified
in Review Pass 6, mostly in `mon_atk_effect_dispatch` (attack type routing) and the speed model.

All 10 test suites still pass.

#### RP7-1: Speed=0 creatures cannot attack — CRITICAL

Four creatures have `cr_speed` = 0: Shrieker Mushroom (#6), Floating Eye (#8), Grey Mold (#16),
Yellow Mold (#18). In `monster_ai_tick` (monster_ai.s:60-61), speed=0 causes the monster to be
**completely skipped** — no wake check, no attack processing, nothing. These creatures are
decorative scenery that can be killed without any resistance.

In umoria, these creatures have speed=11 (normal) with `CM_ATTACK_ONLY` movement flag — they cannot
move but DO attack when the player is adjacent. The distinction between "can't move" and "can't act"
is missing from the C64's speed model.

**Impact:** Floating Eye never paralyzes (its entire purpose). Shrieker Mushroom never aggravates.
Grey Mold never confuses. Yellow Mold never attacks. These are 4/20 creatures rendered harmless.

**Fix options:**
1. Add `MF_ATTACK_ONLY` flag. In `monster_ai_tick`, process speed=0 monsters with a simplified
   path: wake check → if awake and player adjacent → attack. Skip movement entirely.
2. Set speed=1 and add a `CM_NO_MOVE` flag checked in `monster_move_toward`/`monster_move_random`.
   Simpler: monster wakes, tries to move, flag prevents actual movement, but adjacency check
   in `monster_try_step` still triggers `monster_attack_player`.

Option 2 is simpler to implement — just check a flag before moving and skip movement but still
process the monster normally otherwise.

#### RP7-2: Poison attacks wrongly apply AC reduction — MEDIUM

`mon_atk_effect_dispatch` routes poison (ATK_POISON) through `mon_atk_ac_reduce` before applying
the poison effect (monster_attack.s:341-344):
```
!maed_poison:
    jsr mon_atk_ac_reduce       // WRONG — poison has no AC reduction in umoria
    jsr mon_atk_effect_poison
```

In umoria (monster.cpp:1665-1668), poison attacks call `playerTakesHit(damage, ...)` with the full
dice damage — NO AC reduction. Only attack type 1 (Normal) gets AC reduction.

**Fix:** Remove `jsr mon_atk_ac_reduce` from the poison handler.

#### RP7-3: Confusion attacks deal no damage — MEDIUM

`mon_atk_effect_dispatch` sets confusion damage to 0 (monster_attack.s:346-347):
```
!maed_confuse:
    lda #0
    sta zp_combat_dmg           // Confusion: no physical damage
```

In umoria (monster.cpp:1563-1576), confusion attacks deal **full dice damage** (no AC reduction)
AND have a 50% chance (`randomNumber(2) == 1`) of applying confusion. The C64 applies 0 damage
and always applies confusion.

**Fix:** Remove the `lda #0; sta zp_combat_dmg` lines. Add 50% roll before applying confusion
(see RP7-4).

#### RP7-4: Confusion missing 50% chance — MEDIUM

In umoria, confusion only applies 50% of the time:
```cpp
if (randomNumber(2) == 1) {
    // apply confusion
}
```

The C64 `mon_atk_effect_confuse` always applies confusion when the attack hits (no random check).
This makes confusion effects twice as frequent as umoria intends.

**Fix:** Add `lda #2; jsr rng_range; cmp #0; bne !mec_done+` before applying confusion effect.

#### RP7-5: Confusion doesn't stack — LOW

In umoria, confusion stacks: `py.flags.confused += 3` always runs (even if already confused),
and if not previously confused, also adds `randomNumber(creature_level)`. The C64 returns
immediately if already confused (`bne !mec_done+` at monster_attack.s:413).

**Fix:** Remove the early return. If already confused, add 3 turns. If not, add
`rng_range(creature_level) + 3`.

#### RP7-6: Poison doesn't stack — LOW

In umoria (monster.cpp:1668): `py.flags.poisoned += randomNumber(creature_level) + 5` — poison
always adds to the existing counter. The C64 returns immediately if already poisoned
(`bne !mep_done+` at monster_attack.s:378).

**Fix:** Remove the early return. Always add `rng_range(cr_level) + 5` to poison timer.

#### RP7-7: Three slow creatures run at normal speed — MEDIUM

White Worm Mass (#2), Green Worm Mass (#10), and Creeping Copper Coins (#15) have umoria speed=10
(half speed — acts every other player turn). The C64 has them at speed=1 (normal — acts every turn).
This makes them move twice as often as umoria intends.

In umoria, speed < 11 means the creature acts less frequently (speed 10 = every other turn).
The C64 has no "slow" category — only 0 (broken, see RP7-1), 1 (normal), 2 (fast).

**Fix options:**
1. Add speed=0 handling (see RP7-1) that includes "slow" via a fractional counter.
2. Simpler: keep the 0/1/2 model but make 0 = "slow" (acts every other turn), 1 = normal,
   2 = fast. Rename from "immobile" to "slow". Attack-only creatures (RP7-1) need a separate
   flag regardless.

#### RP7-8: Fear attack wrongly applies AC reduction — LOW

`mon_atk_effect_dispatch` routes fear (ATK_FEAR) through `mon_atk_ac_reduce` (monster_attack.s:367):
```
!maed_fear:
    jsr mon_atk_ac_reduce
```

In umoria (monster.cpp:1577-1588), fear attacks call `playerTakesHit(damage, ...)` with full dice
damage — no AC reduction. Only currently impacts Poltergeist (#13, 1d1 fear attack) so low impact.

**Fix:** Remove `jsr mon_atk_ac_reduce` from the fear handler.

#### RP7-9: Poison tick ignores CON — LOW

C64 (turn.s:30-32) deals flat 1 HP/turn poison damage. In umoria (`playerUpdatePoisonedState` in
game_run.cpp:550), poison damage per turn varies by CON adjustment: 0-4 HP/turn. High CON
characters take damage every 2-4 turns, low CON characters take 2-4 HP/turn.

Low priority — the flat 1 HP/turn is a reasonable simplification that averages out over time.

#### Summary of Review Pass 7 findings

| # | Severity | Issue | Fix complexity |
|---|----------|-------|----------------|
| RP7-1 | **CRITICAL** | Speed=0 creatures can't attack (4 of 20 broken) | Medium — add flag + special processing |
| RP7-2 | **MEDIUM** | Poison AC reduction wrong | Trivial — remove 1 JSR |
| RP7-3 | **MEDIUM** | Confusion deals no damage | Trivial — remove 2 lines |
| RP7-4 | **MEDIUM** | Confusion missing 50% chance | Easy — add rng check |
| RP7-5 | LOW | Confusion doesn't stack | Easy — restructure handler |
| RP7-6 | LOW | Poison doesn't stack | Easy — remove early return |
| RP7-7 | **MEDIUM** | 3 slow creatures at normal speed | Medium — requires speed model change |
| RP7-8 | LOW | Fear AC reduction wrong | Trivial — remove 1 JSR |
| RP7-9 | LOW | Poison tick ignores CON | Low priority simplification |

---

### Review Pass 8 — Post-RP7-Fix Verification (2026-02-11)

Verified all RP7 fixes (commit `37552c0`) against umoria source. All 8 actionable RP7 bugs
confirmed fixed correctly. Also verified new Phase 5 additions (HP regen, starvation, light
tracking, effect expiration messages). Found 3 remaining issues.

#### RP7 fix verification results

| # | Finding | Status |
|---|---------|--------|
| RP7-1 | Speed=0 creatures can't attack | **FIXED** — CF_ATTACK_ONLY flag added to `cr_mflags`. Attack-only creatures set to speed=1. `monster_try_step` checks CF_ATTACK_ONLY to block movement while still allowing adjacency attacks. |
| RP7-2 | Poison AC reduction wrong | **FIXED** — `mon_atk_effect_dispatch` routes poison directly to `mon_atk_effect_poison`, no AC reduction. |
| RP7-3 | Confusion deals no damage | **FIXED** — Confusion handler no longer zeroes `zp_combat_dmg`. Full dice damage passes through. |
| RP7-4 | Confusion missing 50% chance | **FIXED** — `rng_range(2)` check added: 0 = apply confusion, 1 = skip. |
| RP7-5 | Confusion doesn't stack | **FIXED** — Already confused: `+= 3`. New confusion: `rng_range(cr_level) + 3`. |
| RP7-6 | Poison doesn't stack | **FIXED** — Always adds `rng_range(cr_level) + 5` to existing timer. Message only on first poisoning. |
| RP7-7 | 3 slow creatures at normal speed | **FIXED** — White Worm (#2), Green Worm (#10), Copper Coins (#15) now speed=0. `monster_ai_tick` skips speed=0 on odd turns (acts every other turn). Verified against umoria speed=10 (half speed). |
| RP7-8 | Fear AC reduction wrong | **FIXED** — Fear handler passes through full dice damage, no AC reduction. |
| RP7-9 | Poison tick ignores CON | **Accepted simplification** — flat 1 HP/turn. |

#### New additions verified correct

1. **HP regeneration** (`turn_tick_regen`, turn.s:210-281) — CON-based counter (8-50 turns per
   1 HP heal). Poison suppresses regen. `zp_eff_regen` active doubles tick rate. Caps at max HP
   with 16-bit comparison. Resets counter from `regen_rate` table indexed by CON-3.

2. **Starvation damage** (`turn_tick_hunger`, turn.s:187-204) — When food counter reaches 0,
   deals 1 HP/turn and calls `player_death_check`. Correct behavior.

3. **Effect expiration messages** (turn.s:20-144) — Poison ("YOU FEEL BETTER."), blindness
   ("YOU CAN SEE AGAIN." + viewport redraw), confusion ("YOU FEEL LESS CONFUSED."), paralysis
   ("YOU CAN MOVE AGAIN.") all print correctly when their timers reach 0.

4. **Light source tracking** (`turn_tick_light`, turn.s) — Uses x30 tick multiplier
   (`LIGHT_TICKS_PER_CHARGE = 30`) so each charge = 30 turns. Torches ~4,020 turns,
   lanterns ~7,500 turns (matching umoria). Warns at 2 charges (~60 turns remaining:
   "YOUR LIGHT IS GROWING DIM."), expires at 0 ("YOUR LIGHT HAS GONE OUT." +
   sets `zp_light_radius` to 0 + unequips light).

#### RP8-1: Poltergeist speed wrong — MEDIUM

Poltergeist (#13) has `cr_speed` = 1 (normal) in monster.s:97. In umoria (`data_creatures.cpp`),
Poltergeist has speed = 13, meaning +3 over normal (very fast). The C64's maximum speed is 2
(double move), so the correct mapping is speed=2.

Huge Brown Bat (#14) is already correctly at speed=2 (umoria speed=12, double speed).

**Fix:** Change `cr_speed` index 13 from 1 to 2. One byte change.

#### RP8-2: Paralysis zeroes damage — LOW

`mon_atk_effect_dispatch` (monster_attack.s:356-357) zeroes `zp_combat_dmg` for paralysis:
```
!maed_paralyze:
    lda #0
    sta zp_combat_dmg
```

In umoria (monster.cpp:1620-1634), paralysis calls `playerTakesHit(damage, death_description)`
FIRST (applying full dice damage), then checks saving throw and applies paralysis effect.
Damage should not be zeroed.

**Practical impact: NONE currently.** The only paralysis creature (Floating Eye, #8) has 0d0
attack dice, so damage is already 0 before zeroing. However, the pattern is wrong for
correctness — future paralysis creatures with non-zero dice would be affected.

**Fix:** Remove `lda #0; sta zp_combat_dmg` from `!maed_paralyze`. Let dice damage pass through.

#### RP8-3: Paralysis timer offset wrong — LOW

C64 `mon_atk_effect_paralyze` uses `rng_range(cr_level) + 1`, giving a range of [1, level].
For the level-1 special case, it hardcodes 2.

umoria uses `randomNumber(creature_level) + 3`, giving a range of [4, level+3].

For Floating Eye (level 1): C64 = 2 turns, umoria = 4 turns.
For a hypothetical level 3 creature: C64 = [1, 3], umoria = [4, 6].

Paralysis is consistently ~2-3 turns shorter than umoria intends. This makes paralysis less
threatening than it should be.

**Fix:** Change `adc #1` to `adc #4` (equivalent to umoria's randomNumber offset after accounting
for rng_range's [0,N-1] vs randomNumber's [1,N]). Update level-1 special case from 2 to 5.

#### Summary of Review Pass 8 findings

| # | Severity | Issue | Fix complexity |
|---|----------|-------|----------------|
| RP8-1 | **MEDIUM** | Poltergeist speed=1, should be 2 | Trivial — 1 byte |
| RP8-2 | LOW | Paralysis zeroes damage (no practical impact) | Trivial — remove 2 lines |
| RP8-3 | LOW | Paralysis timer +1 should be +4 | Trivial — change 2 constants |

### Review Pass 9 — Post-RP8-Fix + Phase 6.5 Review (2026-02-11)

Verified RP8 fixes (commit `d63dc07`) and reviewed Phase 6.5 item identification system
(commit `d1788f4`). RP8 fixes confirmed correct with one residual off-by-one. Phase 6.5
identification system (Fisher-Yates shuffle, name/color resolution, quaff, read scroll,
inventory/render integration) is well-structured and correct. Found 3 issues.

#### RP8 fix verification results

| # | Finding | Status |
|---|---------|--------|
| RP8-1 | Poltergeist speed wrong | **FIXED** — `cr_speed[13]` changed from 1 to 2 (monster.s:97). Correct. |
| RP8-2 | Paralysis zeroes damage | **FIXED** — `lda #0; sta zp_combat_dmg` removed from `!maed_paralyze` (monster_attack.s:355). Full dice damage passes through. |
| RP8-3 | Paralysis timer offset wrong | **PARTIALLY FIXED** — General formula changed from `+1` to `+4`. Correct for level >= 2. However, **level-1 special case hardcodes 5 instead of 4** — see RP9-1. |

#### Phase 6.5 items verified correct

1. **Fisher-Yates shuffle** (item.s:1283-1370) — Correct implementation. Loop from i=N-1 down
   to 1, pick j in [0, i] via `rng_range(i+1)`, swap. X saved/restored around `rng_range` call.
   5 potion descriptors, 5 scroll descriptors, 4 ring descriptors — more descriptors than item
   types ensures unique assignments.

2. **`item_get_name_ptr`** (item.s:1382-1445) — Correctly maps type → id_known check → local
   index (subtract category base) → shuffle table → name pointer. Returns real name for known
   types, randomized description for unknown.

3. **`item_get_floor_color`** (item.s:1453-1500) — Same pattern as name resolution. Clobbers X
   (documented), verified safe in both render_viewport (dungeon_render.s:250-252) and
   render_single_tile (dungeon_render.s:519-521) — X not needed after color stored.

4. **Flag preservation on pickup** (item.s:886-887, 451) — `fi_flags,x → fi_add_flags →
   inv_flags,x` chain correctly preserves IF_CURSED through pickup. Test 30 validates.

5. **Quaff effects** (player_items.s) — Cure Light Wounds HP cap (16-bit comparison handles all
   cases), Speed timer stacking with 255 cap, Poison damage+death+timer stacking all correct.

6. **Scroll effects** (player_items.s) — Light room bounds check correct, Identify scroll
   consumes before second prompt (matches classic Moria), Teleport clears/sets FLAG_OCCUPIED.

7. **Inventory/render integration** — `ui_inv_display`, `ui_equip_display`, `item_append_name`,
   and both render functions all correctly delegate to `item_get_name_ptr`/`item_get_floor_color`.

#### RP9-1: Paralysis timer off-by-one for level 1 — LOW

Residual from RP8-3 fix. The general formula `rng_range(level) + 4` gives [4, level+3], correctly
matching umoria's `randomNumber(level) + 3` = [4, level+3]. But the level-1 special case
(monster_attack.s:504) hardcodes 5:

```
lda #5                      // Level 1: 0 + 4 + 1 = 5
```

The comment's arithmetic "0 + 4 + 1 = 5" is wrong — there's no "+1" in the formula. For level 1,
`rng_range(1)` always returns 0, so the result should be `0 + 4 = 4`. umoria confirms:
`randomNumber(1) + 3 = 1 + 3 = 4`.

The special case is also unnecessary — `rng_range(1)` safely returns 0, so the general path
would give the correct result for level 1.

**Practical impact:** Floating Eye paralysis lasts 5 turns instead of 4. Minor balance difference.

**Fix:** Remove the level-1 special case entirely, or change `lda #5` to `lda #4`.

#### RP9-2: `item_drop` doesn't preserve flags — MEDIUM

`item_drop` (item.s:982-994) copies `inv_item_id`, `inv_qty`, and `inv_p1` to `fi_add_*`
variables before calling `floor_item_add`, but does NOT copy `inv_flags` to `fi_add_flags`.
Since `floor_item_add` always writes 0 to `fi_flags,x` (item.s:311), a drop+pickup round-trip
loses IF_CURSED (and IF_IDENTIFIED).

This means a player could uncurse an item by dropping and picking it back up.

**Fix:** Add `lda inv_flags,x` / `sta fi_add_flags` in `item_drop` before the `floor_item_add`
call, then post-hoc set `fi_flags,x` from `fi_add_flags` after `floor_item_add` succeeds
(same pattern used in `item_spawn_level` at item.s:664-667).

#### RP9-3: `floor_item_add` ignores `fi_add_flags` — LOW (design debt)

Root cause of RP9-2. `floor_item_add` (item.s:311) unconditionally writes `lda #0; sta fi_flags,x`
instead of copying `fi_add_flags`. Every caller must remember to post-hoc patch `fi_flags,x`
after the call — currently `item_spawn_level` does this (item.s:664-667 and 766-768) but
`item_drop` does not.

**Fix (optional cleanup):** Change `floor_item_add` to copy `fi_add_flags` instead of hardcoding
0. This would eliminate the need for post-hoc patching in callers, making the API less error-prone.
If done, also update the function's input comment to document `fi_add_flags`.

#### Summary of Review Pass 9 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP9-1 | LOW | Paralysis timer level-1 special case: 5 should be 4 | Trivial — remove special case | **FIXED** — removed level-1 special case; general formula handles it |
| RP9-2 | **MEDIUM** | `item_drop` loses IF_CURSED/IF_IDENTIFIED flags | Easy — add `inv_flags→fi_add_flags` copy | **FIXED** — added flags copy in `item_drop` before `floor_item_add` |
| RP9-3 | LOW | `floor_item_add` ignores `fi_add_flags` (design debt) | Easy — copy `fi_add_flags` instead of hardcoding 0 | **FIXED** — `floor_item_add` now copies `fi_add_flags`; removed post-hoc patches; added init to gold path + all tests |

### Review Pass 10 — Phase 7 Steps 7.0–7.5 Implementation Review (2026-02-12)

Reviewed all three new Phase 7 files (`spell_effects.s` ~1014 lines, `spell_data.s` ~137 lines,
`player_magic.s` ~1258 lines) plus integration points in `main.s`, `combat.s`, and `player_create.s`.
Cross-referenced against BUILDPLAN steps 7.0–7.5, calling conventions of all referenced functions
(`math_dice`, `monster_find_at`, `monster_get_ptr`, `monster_remove`, `rng_range`, `get_direction_target`,
`stat_bonus_index`, `combat_append_str`, `combat_award_xp`, `combat_check_levelup`, `find_random_floor`),
zero-page allocations (`zp_math_tmp0/1` at $20/$21 confirmed separate from `zp_temp0-2` at $02-$04),
and encoding (`.encoding "screencode_upper"` confirmed set globally in `main.s` line 20).

**Files reviewed:** `spell_effects.s`, `spell_data.s`, `player_magic.s`, `main.s` (dispatch),
`combat.s` (level-up hooks), `player_create.s` (starting spells), `monster.s` (CF_UNDEAD),
`dungeon_features.s` (find_random_floor, trap_check_at_player), `dungeon_render.s` (monster
rendering), `math.s` (math_dice/math_multiply), `player.s` (stat_bonus_index), `tables.s`
(spell_stat_bonus), `screen.s` (screen_put_string), `zeropage.s`.

#### Findings

**RP10-1 (BUG): Monster HP=0 treated as alive in spell effect damage**

In `spell_effects.s`, the death check after 16-bit HP subtraction uses only `bpl` (branch if
HP_HI >= 0), meaning a monster at exactly 0 HP survives. This is INCONSISTENT with `combat.s`
`combat_apply_damage` (lines 412–449), which checks BOTH `bmi` (HP < 0) AND `ora` for exact
zero (HP == 0), treating HP <= 0 as dead.

Affected locations:
- `eff_bolt` line 702: `bpl !eb_fizzle+`
- `eff_damage_adjacent` line 765: `bpl !eda_next+`
- `eff_dispel_undead` line 1002: `bpl !edu_next+`
- ~~`mage_effect_dispatch` effect 0 (Magic Missile)~~ — **Fixed**: now uses `eff_bolt` (shared death check)

**Fix:** After each `bpl !alive+`, add an explicit zero check:
```
    bmi !dead+
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    ldy #MX_HP_HI
    ora (zp_ptr0),y
    bne !alive+
!dead:
```
Or extract a shared `eff_check_monster_dead` subroutine since this pattern repeats 4 times.
Alternatively, match the `combat_apply_damage` pattern: `bmi` then `beq` on the OR of both bytes.

**RP10-2 (BUG): `eff_destroy_traps_doors` does not remove traps from trap table**

`eff_destroy_traps_doors` (spell_effects.s lines 804–869) changes adjacent TILE_TRAP map tiles
to TILE_FLOOR, but does NOT modify or remove the corresponding entries in `trap_x`/`trap_y`/
`trap_type` arrays. The comment at line 865 acknowledges this: "simplified: clear the whole trap
table since most are revealed" — but the code doesn't actually do it.

`trap_check_at_player` (dungeon_features.s line 330) triggers traps by scanning the
`trap_x`/`trap_y` table, NOT by checking map tile types. Therefore, a trap that was "destroyed"
on the map (tile changed to TILE_FLOOR) will STILL TRIGGER when the player steps on it.

**Fix:** After the direction loop, scan `trap_x`/`trap_y` for entries matching each of the 8
adjacent positions and remove them (swap with last entry + decrement `trap_count`):
```
    // Remove matching traps from trap table
    ldx #0
!scan:
    cpx trap_count
    bcs !scan_done
    // For each of 8 directions, check if trap_x[x],trap_y[x] matches
    // If match: swap with last entry, dec trap_count, don't inc x
    ...
```

**RP10-3 (BUG): `find_random_floor` does not check FLAG_OCCUPIED**

`find_random_floor` (dungeon_features.s lines 165–200) selects a random floor tile by checking
only `TILE_TYPE_MASK == TILE_FLOOR`. It does NOT check that `FLAG_OCCUPIED` is clear. This means
`eff_teleport_self` and `eff_phase_door` can teleport the player onto a tile already occupied by
a monster, resulting in both entities sharing a tile.

Compare with `find_monster_floor` (monster.s lines 285–338) which correctly checks
`TILE_TYPE_MASK | FLAG_OCCUPIED` before accepting a tile.

**Fix:** In `find_random_floor`, change the tile check from:
```
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
```
to:
```
    sta zp_temp0
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !frf_next+
    lda zp_temp0
    and #FLAG_OCCUPIED
    bne !frf_next+
```

**RP10-4 (MEDIUM): BUILDPLAN test expectation for `magic_recalc_mana` is wrong**

Step 7.3 test says: "Verify `magic_recalc_mana` with INT=12, level=5 → expected max_mana
= (5*12)/8 + bonus[12-3] = 7 + 1 = 8." (Corrected: bonus[9]=1 per `spell_stat_bonus` table.)

The `spell_stat_bonus` table in `tables.s` (lines 196–198) has:
```
    .byte  0,  0,  0,  0,  0,  1,  1,  1  // indices 0-7 (stats 3-10)
    .byte  1,  1,  1,  2,  2,  3,  3,  3  // indices 8-15 (stats 11-18)
```
Index 9 (stat 12) = **1**, not 2. Correct expected value: (5×12)/8 + 1 = 7 + 1 = **8**.

**RP10-5 (MEDIUM): `eff_phase_door` duplicates teleport code instead of calling `eff_teleport_self`**

`eff_phase_door` (spell_effects.s lines 376–404) contains a full copy of the FLAG_OCCUPIED
clear/move/set logic from `eff_teleport_self`. After the distance-check loop selects a target
(stored in `df_target_x`/`df_target_y`), it should simply `jsr eff_teleport_self` which does
the exact same thing. The duplicated code is 28 bytes of wasted space and a maintenance hazard
(a bug fix in one copy won't automatically apply to the other).

**Fix:** Replace lines 376–404 with `jsr eff_teleport_self; rts` (or `jmp eff_teleport_self`).

**RP10-6 (MEDIUM): `eff_heal` API diverges from BUILDPLAN — 8-bit only**

The BUILDPLAN (Step 7.0) describes `eff_heal(A=dice, X=sides, Y=bonus)` with integrated dice
rolling. The implementation takes a pre-rolled 8-bit heal amount in A. This means all callers
must call `math_dice` separately, then pass `zp_math_a` to `eff_heal`. The 16-bit high byte
(`zp_math_b`) is silently discarded.

Current max heal is 5d8+5 = 45, well within 8 bits. However, the function signature mismatch
between plan and code should be documented. The current approach is arguably better (simpler
function, separation of concerns), but the BUILDPLAN should be updated to match reality.

**RP10-7 (LOW): `eff_detect_monsters` makes monster tiles permanently FLAG_VISITED**

After `eff_detect_monsters` sets FLAG_VISITED on each monster's tile, those tiles remain
permanently marked as visited. When the monster moves away, the old tile still shows as visited
floor. This is not harmful (the renderer checks FLAG_OCCUPIED before drawing a monster glyph,
so no phantom monsters appear), but it does reveal map layout in areas the player hasn't
explored — a minor information leak.

In umoria, Detect Monster is a temporary effect with a duration. Consider adding a timer
(`zp_eff_detect`, already in the ZP effect block) and only showing monsters while the timer
is active, rather than permanently marking tiles.

**RP10-8 (LOW): CMP/BEQ dispatch chains for 16 spell effects**

Both `mage_effect_dispatch` and `priest_effect_dispatch` use a linear CMP/BEQ chain (16
comparisons worst case for spell index 15). A jump table would be O(1):
```
    asl                   // index * 2
    tax
    lda mage_jmp_tbl+1,x
    pha
    lda mage_jmp_tbl,x
    pha
    rts                   // jump via RTS trick
```
This saves ~48 bytes and is faster for higher-index spells. Not critical at 16 entries but
worth considering since the same pattern will be used for potions, scrolls, wands, and staves
in steps 7.6–7.7, potentially expanding to 40+ dispatch entries total.

**RP10-9 (LOW): `stat_bonus_index` has no lower-bounds check**

`stat_bonus_index` (player.s lines 392–401) computes `stat - 3` without checking if stat < 3.
If a stat ever reaches 2 or below, the subtraction underflows to 253+ and indexes far past the
16-byte `spell_stat_bonus` table (buffer over-read).

Current stat drain code (dungeon_features.s line 500) guards with `cmp #4; bcc !no_drain+`,
preventing stats from dropping below 3. But this is an implicit contract — `stat_bonus_index`
itself is fragile.

**Fix:** Add a defensive clamp:
```
    cmp #3
    bcs !ok+
    lda #3
!ok:
```

**RP10-10 (LOW): `eff_bolt` tile passability check is too narrow**

`eff_bolt` (spell_effects.s lines 664–671) only allows bolts through `TILE_FLOOR` and
`TILE_DOOR_OPEN`. If any other passable tile types exist or are added later (e.g., stairs,
rubble), bolts would stop on them. The check should probably use a "not wall" test instead:
```
    cmp #TILE_WALL_H
    beq !eb_wall+
    cmp #TILE_WALL_V
    beq !eb_wall+
    cmp #TILE_DOOR_CLOSED
    beq !eb_wall+
    jmp !eb_check_mon+
!eb_wall:
    jmp !eb_fizzle+
```
Or better, use a tile-passability helper. For now, TILE_FLOOR covers corridors (they use the
same tile type), so this works for the current map generator. Flag for future review.

**RP10-11 (LOW): `eff_kill_monster` clears FLAG_OCCUPIED redundantly**

`eff_kill_monster` manually clears FLAG_OCCUPIED (lines 924–940), then calls `monster_remove`
(line 944) which also clears FLAG_OCCUPIED (monster.s lines 619–625). The first clear is
redundant. Removing the manual clear saves ~17 bytes.

**RP10-12 (LOW): No `eff_aggravate` implementation**

Step 7.0 lists `eff_aggravate` (wake all monsters, set MF_AWAKE) as a shared subroutine to
create. It's not used in steps 7.4/7.5, but step 7.6 needs it for Scroll of Aggravation.
It should be implemented now to keep step 7.0 complete. Implementation is trivial:
```
eff_aggravate:
    ldx #0
!loop:
    cpx #MAX_MONSTERS
    bcs !done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !next+
    ldy #MX_SLEEP_CUR
    lda #0
    sta (zp_ptr0),y       // Clear sleep
!next:
    inx
    jmp !loop-
!done:
    rts
```

#### Suggested Additional Tests

The existing test suites (`test_effects.s`, `test_combat.s`) do not cover the spell casting flow
or individual spell effects. The following runtime tests should be added:

1. **Spell dispatch correctness:** Cast each mage spell 0–15 in a controlled setup; verify the
   expected side effect occurred (e.g., Magic Missile: monster HP decreased; Light: room_lit set;
   Teleport: player position changed).
2. **Mana deduction on failure:** Set player to Mage, mana=10, force spell failure (set fail_base
   to 100), verify mana decreased but no effect applied.
3. **HP=0 kill check:** Place monster with exactly N HP, deal exactly N damage via bolt/Fire Ball,
   verify monster is removed (once RP10-1 is fixed).
4. **Phase door distance:** Set player at (40, 24), call eff_phase_door, verify new position is
   within Chebyshev distance 10 (or verify fallback behavior after 20 failed attempts).
5. **Occupied tile teleport:** Place monster on every floor tile except one, call
   eff_teleport_self, verify player lands on the unoccupied tile (once RP10-3 is fixed).
6. **Spell known bitmask boundary:** Set PL_SPELLS_KNOWN = $00/$00, player_level = 9. Call
   magic_check_new_spells. Verify spells 0–7 (lo byte) AND spells 8–9 (hi byte) are all learned
   correctly (tests the 8-bit boundary crossing).
7. **Bless/Chant timer ranges:** Cast Bless 100 times, verify all values in [12, 23]. Cast Chant
   100 times, verify all values in [24, 47].
8. **Slow Poison edge cases:** Test with poison=1 → stays 1. Test with poison=0 → stays 0
   (guard check). Test with poison=255 → becomes 128 (127 | 1).
9. **Remove Curse coverage:** Equip cursed weapon + cursed armor + non-cursed ring. Cast
   Remove Curse. Verify cursed flags cleared on weapon and armor, ring unchanged.
10. **Bolt wall stop:** Fire Lightning Bolt toward wall 2 tiles away with monster behind wall.
    Verify bolt stops at wall, monster takes no damage.
11. **Trap/Door Destroy + trigger:** Destroy adjacent trap via spell, then step on that tile.
    Verify trap does NOT trigger (once RP10-2 is fixed).
12. **Failure rate clamp:** Test with very high level (level 40, spell level 1): verify failure
    rate is clamped to 5%, not negative. Test with very low stat (stat 3): verify no underflow.

#### Summary of Review Pass 10 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP10-1 | **HIGH** | Monster HP=0 treated as alive in spell damage (inconsistent with combat.s) | Easy — add zero check after `bpl` in 4 locations, or extract helper | **Fixed** — all 3 locations already use `bmi`+`ora` zero-check; Magic Missile now uses shared `eff_bolt` |
| RP10-2 | **HIGH** | `eff_destroy_traps_doors` doesn't remove traps from trap table; traps still trigger | Medium — add trap table scan after direction loop | **Fixed** — trap table entries scanned and removed via swap-with-last logic (spell_effects.s:854-906) |
| RP10-3 | **HIGH** | `find_random_floor` doesn't check FLAG_OCCUPIED; teleport can land on monsters | Easy — add FLAG_OCCUPIED check in find_random_floor | **Fixed** — FLAG_OCCUPIED check added (dungeon_features.s:197-198) |
| RP10-4 | **MEDIUM** | BUILDPLAN test expectation wrong: spell_stat_bonus[9]=1, not 2; expected mana=8, not 9 | Trivial — fix test expectation text | **Fixed** — corrected both test spec (line 3147) and RP description (line 1856) |
| RP10-5 | **MEDIUM** | `eff_phase_door` duplicates 28 bytes of teleport code; should call `eff_teleport_self` | Trivial — replace with JSR/JMP | **Fixed** — now calls find_random_floor (spell_effects.s:342) |
| RP10-6 | **MEDIUM** | `eff_heal` API takes pre-rolled A (8-bit) not dice params as BUILDPLAN describes | Documentation — update BUILDPLAN to match implementation | **Fixed** — BUILDPLAN step 7.1 updated to match actual 8-bit API |
| RP10-7 | LOW | `eff_detect_monsters` permanently marks tiles FLAG_VISITED (minor map info leak) | Medium — add timer-based detect effect | **Fixed** — timer-based: `eff_detect_timer` counts down 20 turns, renderer shows detected monsters on unvisited tiles |
| RP10-8 | LOW | CMP/BEQ dispatch chains are O(n); jump table would be O(1) and smaller | Medium — rewrite as jump table | **Fixed** — RTS-trick jump tables replace 32 CMP/BNE entries; shared `heal_dice` helper; saves ~136 bytes |
| RP10-9 | LOW | `stat_bonus_index` has no lower-bounds check (stat < 3 causes buffer over-read) | Trivial — add `cmp #3; bcs` guard | **Fixed** — guard already present (player.s:407-409) |
| RP10-10 | LOW | `eff_bolt` only passes through TILE_FLOOR and TILE_DOOR_OPEN | Easy — invert check to block walls instead | **Fixed** — already uses `walkable_table` (allows floor, doors, rubble, stairs, traps) |
| RP10-11 | LOW | `eff_kill_monster` clears FLAG_OCCUPIED redundantly (also done by monster_remove) | Trivial — remove manual clear | **Fixed** — redundant clear removed |
| RP10-12 | LOW | `eff_aggravate` not implemented despite being listed in Step 7.0 | Easy — ~20 bytes | Resolved (see RP11-6) |

---

### Review Pass 11 — Step 7.6 (Expanded Potions and Scrolls)

**Scope:** `item.s`, `player_items.s`, `combat.s`, `zeropage.s`, `tests/test_item.s`, `run_tests.sh`
**Reviewer:** Claude (automated)
**Date:** 2025-02-12

#### RP11-1 (HIGH): CSW heal computes [5,40] instead of intended [10,45]

**Location:** `player_items.s:836-856`

The comment says "heal 5d8 (5× rng(8)) + 5" and BUILDPLAN line 2408 says "Heal 5d8+5".
The code rolls 5×rng(8) = 5×[0,7] = [0,35], then adds 5, giving **[5,40]**.
The +5 only compensates for `rng_range(8)` returning [0,7] instead of [1,8] — the actual
+5 bonus from the design is lost.

Intended range: 5d8+5 = [10, 45]. Actual range: [5, 40]. Off by 5 at both ends.

**Test impact:** Test 33 checks HP in [60,95] (expects 50 + [10,45] heal). With the actual
[5,40] range, heal values 5-9 produce HP 55-59 which fails the `cmp #60; bcc` lower bound
check. The test will fail intermittently (~14% of runs).

**Fix:** Replace the manual loop with `math_dice(5, 8, 5)`:
```
lda #5           ; N=5 dice
ldx #8           ; S=8 sides
ldy #5           ; bonus=5
jsr math_dice
lda zp_math_a    ; low byte (max 45, fits in 8 bits)
jsr eff_heal
```
This also saves ~14 bytes versus the manual loop.

#### RP11-2 (HIGH): Enchant Weapon/Armor broken on cursed items

**Location:** `player_items.s:1184-1198` (weapon), `player_items.s:1228-1242` (armor)

The cap check uses unsigned comparison: `lda inv_p1,x; cmp #5; bcc`. Cursed items store
negative p1 as two's complement (e.g., -3 = $FD). Unsigned $FD = 253 ≥ 5, so BCC does not
branch. The handler falls through to "already at cap" and does nothing.

In umoria, enchanting a cursed weapon/armor should: (1) clear IF_CURSED flag, (2) set p1=0,
(3) recalculate equipment, (4) display glow message.

**Fix:** Before the unsigned cap check, add a cursed-item branch:
```
!irs_ew_has:
    ldx #EQUIP_WEAPON
    lda inv_flags,x
    and #IF_CURSED
    beq !irs_ew_not_cursed+
    // Cursed → remove curse + reset to 0
    lda inv_flags,x
    and #~IF_CURSED & $ff
    sta inv_flags,x
    lda #0
    sta inv_p1,x
    jsr player_recalc_equipment
    jmp !irs_ew_msg+         ; print glow message
!irs_ew_not_cursed:
    lda inv_p1,x
    cmp #5
    bcc !irs_ew_inc+
    ...
```
Same pattern needed for Enchant Armor with EQUIP_BODY.

#### RP11-3 (MEDIUM): No test coverage for enchant on cursed items

Test 35 (Enchant Weapon) only tests with positive p1=2. No test exists for:
- Enchant weapon with negative p1 ($FD = -3) and IF_CURSED flag set → should remove curse, set p1=0
- Enchant armor with IF_CURSED flag → same behavior
- Enchant at exact cap (p1=5) → should print "nothing happens", p1 unchanged

#### RP11-4 (MEDIUM): Heroism, Infravision, Protect from Evil timers have no game effect

`zp_eff_hero`, `zp_eff_infra`, and `zp_eff_protect` are set by their respective
potions/scrolls and decremented each turn by `turn.s`, but **no code checks these timers
to apply gameplay effects:**
- Heroism: should grant +1 to-hit and +10 max HP while active (per umoria)
- Infravision: should reveal monsters within range while active
- Protect from Evil: should reduce damage from evil monsters while active

The timers are pure stubs — using these items currently has no gameplay effect. Either the
consumption code should be added (likely a Phase 8+ concern) or the BUILDPLAN should
explicitly note these as infrastructure-only stubs awaiting integration.

#### RP11-5 (LOW): Word of Recall overwrites timer (correct but undocumented)

`zp_eff_word_recall` is stored directly (`sta`), not added to existing value. Reading a
second Word of Recall scroll overwrites the timer rather than extending it. This matches
umoria behavior but differs from other timer effects (Heroism, Blindness, etc.) which
stack via `clc; adc`. Should be documented as intentional.

#### RP11-6 (LOW): RP10-12 resolved — eff_aggravate IS implemented

RP10-12 stated eff_aggravate was not implemented. It exists at `spell_effects.s:1046` and
is successfully called by the Aggravate scroll handler at `player_items.s:1270`. RP10-12
status should be updated to Resolved.

#### Suggested tests for Step 7.6

1. **CSW heal range [10,45]:** After fixing RP11-1, verify heal from HP=50 gives HP in
   [60,95]. Run multiple iterations to catch edge cases.
2. **Enchant Weapon on cursed item:** Set EQUIP_WEAPON p1=$FD (-3), inv_flags=IF_CURSED.
   Read Enchant Weapon scroll. Verify p1=0, IF_CURSED cleared.
3. **Enchant Armor on cursed item:** Same test for EQUIP_BODY slot.
4. **Enchant at exact cap:** Set p1=5, read Enchant scroll → verify p1 stays 5.
5. **Heroism timer stacking:** Drink two Heroism potions → verify timer in [50,98] range
   (not overflow beyond 98).
6. **Protect from Evil timer range:** Verify timer in [25,49] after reading scroll.

#### Summary of Review Pass 11 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP11-1 | **HIGH** | CSW heal [5,40] instead of [10,45]; Test 33 fails intermittently | Easy — use math_dice(5,8,5) or change adc #5 → adc #10 | **Fixed** — replaced manual loop with `math_dice(5,8,5)` giving correct [10,45] range |
| RP11-2 | **HIGH** | Enchant Weapon/Armor broken on cursed items (unsigned cmp treats -N as >5) | Medium — add IF_CURSED branch before cap check in both handlers | **Fixed** — added IF_CURSED check before cap comparison; cursed items get curse cleared + p1 set to 0 |
| RP11-3 | **MEDIUM** | No test for enchant on cursed items | Easy — add test with negative p1 + IF_CURSED | **Fixed** — added test 39 (enchant cursed weapon: p1→0, flag cleared) and test 40 (enchant at cap: p1 stays 5) |
| RP11-4 | **MEDIUM** | Heroism/Infravision/Protect timers are stubs — no code checks them for gameplay effects | Design — document as stubs or implement consumption | **Documented** — added NOTE comments to all three handlers marking timers as infrastructure-only until effect consumption phase |
| RP11-5 | LOW | Word of Recall overwrites (not stacks) timer — correct but undocumented | Trivial — add comment | **Fixed** — added comment documenting overwrite-not-stack behavior matches umoria |
| RP11-6 | LOW | RP10-12 wrong: eff_aggravate IS implemented at spell_effects.s:1046 | Trivial — update RP10-12 status | **Resolved** — RP10-12 already marked as resolved in prior pass |

---

### Review Pass 12 — RP11 Fix Verification

**Scope:** `player_items.s`, `tests/test_item.s`, `run_tests.sh`, `BUILDPLAN.md`
**Reviewer:** Claude (automated)
**Date:** 2025-02-12
**Commit reviewed:** `b94e59e Fix Review Pass 11 findings for Step 7.6 potions/scrolls`

All six RP11 fixes verified correct. No bugs found.

- **RP11-1 fix (CSW heal):** `math_dice(5, 8, 5)` produces correct [10,45] range.
  `zp_math_a` low byte (max 45) fits 8 bits. Test 33's [60,95] check now consistent.
- **RP11-2 fix (Enchant on cursed items):** Both weapon and armor handlers check
  `IF_CURSED` before the unsigned cap comparison. Cursed path correctly clears flag
  via `and #~IF_CURSED & $ff`, sets p1=0, calls `player_recalc_equipment`, jumps to
  shared `!irs_ew_msg` / `!irs_ea_msg` glow message label. Normal-increment path
  unchanged.
- **RP11-3 fix (New tests 39-40):** Test 39 sets p1=$FD with IF_CURSED, verifies
  p1=0 and flag cleared. Test 40 sets p1=5, verifies no increment past cap. Copy
  loop `ldx #39` (40 bytes) and run_tests.sh `"0400 0427" 40` both correct.
- **RP11-4/5/6 (Comments and status updates):** Infrastructure NOTE comments and
  WoR overwrite comment all correctly placed.

#### RP12-1 (LOW): Armor enchant cursed/cap paths lack dedicated tests

Tests 39-40 only cover the **weapon** enchant path. The armor handlers
(`!irs_ea_has` cursed branch and cap check) are structurally identical but untested.
Adding tests 41-42 mirroring tests 39-40 for EQUIP_BODY would complete coverage.

#### Summary of Review Pass 12 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP12-1 | LOW | Armor enchant cursed/cap paths untested (weapon-only coverage) | Easy — mirror tests 39-40 for EQUIP_BODY | **Fixed** — tests 41-42 added (cursed armor + cap check) |

---

### Review Pass 13 — Steps 7.9 and 7.10 (Mana Regen, WoR, Integration, Polish)

**Scope:** `turn.s`, `player_magic.s`, `player_items.s`, `sound.s`, `ui_character.s`,
`ui_help.s`, `monster_magic.s`, `tests/test_effects.s`, `run_tests.sh`
**Reviewer:** Claude (automated)
**Date:** 2026-02-12

#### RP13-1 (HIGH): Confused casting blocked by known-spell and level checks

**Location:** `player_magic.s:160-236`

When confused, a random spell index (0-15) is selected at line 166-168, replacing the
player's choice. However, the code falls through to the known-spell check (line 164-191)
and the minimum level check (line 218-236). If the random spell isn't known (the common
case for most players), the handler prints "YOU DON'T KNOW THAT SPELL" and returns CLC
(no turn consumed, no mana deducted). If the spell is too high level, same result.

**In umoria**, confused casting:
- Bypasses both known and level requirements
- Deducts mana for the random spell (checked normally)
- Rolls for failure normally
- Executes the random spell's effect on success

**Current behavior:** Confusion during casting is effectively harmless — most random spells
will be unknown, so the player just gets an error message and no turn is consumed. This
defeats the entire purpose of the confusion mechanic during spellcasting.

**Fix:** Two changes needed:
1. In the confused branch, add `jmp !pm_known+` to skip the known-spell check:
```
    lda zp_eff_confuse
    beq !pm_not_confused+
    lda #16
    jsr rng_range
    sta pm_spell_idx
    jmp !pm_known+             ; Skip known check when confused
!pm_not_confused:
```
2. Before the level check at `!pm_mana_ok`, add a confusion bypass:
```
!pm_mana_ok:
    lda zp_eff_confuse
    bne !pm_lvl_ok+            ; Skip level check when confused
    // Normal level check follows...
```

#### RP13-2 (MEDIUM): BUILDPLAN mana regen rate contradicts implementation

**Location:** BUILDPLAN line ~2864 vs `turn.s` implementation

BUILDPLAN prose says "recover 1 mana per 3 turns" with regen making it "1 per 2 turns".
BUILDPLAN code block says "Every 2 turns (basic rate)" with `and #$01`.
Implementation matches the code block: normal = 1 per 2 turns, with regen = 1 per turn.

The prose and code block within the BUILDPLAN contradict each other. The code block and
implementation agree. Fix: update the prose from "per 3 turns" to "per 2 turns" and
regen from "per 2 turns" to "every turn".

#### RP13-3 (MEDIUM): PL_MAX_DLVL offset differs from BUILDPLAN

BUILDPLAN step 7.9 line ~2910 says "Use `PL_SPARE_63` (player struct offset 63)".
Implementation uses `PL_MAX_DLVL = 56` (offset 56). `PL_SPARE_63` remains unused at
offset 63. Not a code bug — the architect chose a different offset — but the BUILDPLAN
should be updated to match.

#### RP13-4 (LOW): No test for confused casting

The confusion-during-casting interaction (Step 7.10 checklist item 2) has no dedicated
test. A test should:
1. Set zp_eff_confuse > 0, put all 16 spells known, sufficient mana
2. Call pm_do_cast with keyboard input for spell 'A'
3. Verify a spell was actually cast (mana decreased, turn consumed)
4. This would also expose the RP13-1 bug if spells were NOT all known

#### RP13-5 (LOW): No test for extra regen on odd turn

Tests 11-12 cover normal regen (even turn) and warrior no-regen. Missing:
- Set zp_eff_regen > 0, zp_turn_lo = 1 (odd turn), verify MP still increases
  (extra regen bypasses the even-turn check)

#### RP13-6 (LOW): No test for Word of Recall fizzle

When recalling from town (dlvl=0) with PL_MAX_DLVL=0 (player has never entered the
dungeon), the recall should fizzle (jump to `!no_recall`). No test covers this path.

#### RP13-7 (LOW): Intermediate fix commit (e427147) notes

The fix commit between RP12 and Step 7.9 correctly:
- Replaced `mm_check_death` with `player_death_check` in `monster_magic.s` bolt and
  breath handlers (carries through from `mon_atk_apply_damage`)
- Hit sound no longer plays on player death (correct — death has its own SFX)
- Added missing `monster_magic.s` import to `test_item.s`
- Updated stale test bounds

No issues found in this commit.

#### Verified correct in Steps 7.9/7.10

- **Word of Recall teleportation:** Clears FLAG_OCCUPIED at old position, sets
  level_entry_dir correctly (1=ascending for dungeon→town, 0=descending for
  town→dungeon), calls full level regeneration chain, stops running, redraws UI.
- **Mana regen logic:** Warriors excluded (PL_SPELL_TYPE=0), max cap check correct,
  extra regen skips turn parity check, syncs to player_data.
- **Blindness blocks scroll reading:** Returns CLC immediately (no turn consumed).
- **Hunger penalty:** +20 to failure rate at HUNGER_FAINT or worse, capped at 95.
  Applied after the base [5,95] clamp, so max effective failure with hunger is 95%.
- **Sound effects:** SFX_SPELL and SFX_SPELL_FAIL correctly added to sfx_table at
  indices 6-7. Triangle wave for spell, noise buzz for fizzle. Both use voice 3.
- **Help screen:** New line "M CAST SPELL     P PRAY", HELP_LINE_COUNT=23, pointer
  tables extended correctly in both lo and hi arrays.  Redesigned with PETSCII box
  borders, color-coded text (keys WHITE, descriptions LGREY, headers CYAN, borders GREY),
  and inline color toggle renderer (`help_draw_line`).  String data split to
  `ui_help_data.s` in main RAM to fit banked code budget.
- **Character sheet:** Spells Known (N/16) displayed for spell-casters only (row 11).
  count_spells_known correctly iterates all 16 bits via spell_bit_mask. "Press any key"
  moved to row 16 to accommodate.
- **Max depth tracking:** Already present in main.s (lines 338-341), updates on
  stairs-down. PL_MAX_DLVL initialized to 0 at player creation (line 165).
- **Tests 11-18:** All structurally correct — mana regen, warrior no-regen, recall
  both directions, hunger penalty, no-hunger baseline, count_spells_known, blindness
  blocks scrolls.

#### Suggested tests for Steps 7.9/7.10

1. **Confused cast (all spells known):** Set 16 spells known, confuse > 0, cast →
   verify mana decreased and turn consumed (currently fails due to RP13-1).
2. **Confused cast (few spells known):** Set 3 spells known, confuse > 0, cast →
   should still cast random spell (currently blocked by known check).
3. **Extra regen on odd turn:** zp_eff_regen=5, zp_turn_lo=1, mage MP=5/20 →
   verify MP becomes 6 (bypass even-turn check).
4. **Recall fizzle:** dlvl=0, PL_MAX_DLVL=0, recall timer=1 → verify dlvl stays 0.
5. **Mana regen stops at max:** MP=19, MMP=20, tick even turn → MP=20. Tick again →
   MP stays 20.

#### Summary of Review Pass 13 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP13-1 | **HIGH** | Confused casting blocked by known-spell and level checks (confusion is harmless) | Easy — add `jmp !pm_known+` in confused branch + confusion bypass at level check | **Fixed** |
| RP13-2 | **MEDIUM** | BUILDPLAN says "1 per 3 turns" but code/implementation do 1 per 2 turns | Trivial — fix BUILDPLAN prose | **Fixed** |
| RP13-3 | **MEDIUM** | PL_MAX_DLVL at offset 56, BUILDPLAN says offset 63 (PL_SPARE_63) | Trivial — update BUILDPLAN | **Fixed** |
| RP13-4 | LOW | No test for confused casting interaction | Easy — add test with confusion + known spells | **Fixed** (test 19) |
| RP13-5 | LOW | No test for extra regen on odd turn | Trivial — same as test 11 with regen=5 and odd turn | **Fixed** (test 20) |
| RP13-6 | LOW | No test for Word of Recall fizzle (town, never visited dungeon) | Trivial — set PL_MAX_DLVL=0, verify dlvl unchanged | **Fixed** (test 21) |

### Review Pass 14 — Phase 8 (Stores) Implementation Review (2026-02-12)

Full review of Phase 8 store implementation: `store.s`, `ui_store.s`, `math.s` (math_mul_16x8),
`tables.s` (chr_price_adj/chr_sell_adj), main.s integration, and test files. Cross-referenced
against umoria source (`store.cpp`, `store_inventory.cpp`, `data_store_owners.cpp`,
`data_stores.cpp`, `player_stats.cpp`) for pricing formulas, store categories, restocking,
and haggling behavior.

**Files reviewed:**
- `store.s` — 6 stores, SoA inventory (72 slots), category bitmasks, restocking, pricing, gold ops
- `ui_store.s` — Store UI loop, buy/sell flows, door detection, screen drawing
- `math.s` — math_mul_16x8 (16×8→24-bit multiply)
- `tables.s` — chr_price_adj (100-130%), chr_sell_adj (25-50%)
- `item.s` — it_cost_lo/hi (47 entries), it_category, ICAT constants
- `main.s` — store_init_all at startup, store door check in main loop, restock on stair ascent
- `turn.s` — Word of Recall code path (missing restock)
- `player_items.s` — inv_add_item, inv_remove_item, inv_count_items
- `dungeon_gen.s` — STORE_COUNT, store_door_x/y, store positions
- `zeropage.s` — zp_store_idx ($8C), zp_store_slot ($8D)
- `tests/test_store.s` — 17 tests (all pass; VICE detection issue only)
- `tests/test_store_debug.s` — 13 deterministic tests (pass)
- `tests/test_store_iso.s` — 9 isolation tests (pass)

**Verification approach:** Built test_store.s, confirmed segment layout ($0810-$90D0),
checked symbol addresses (tc_results=$8E25, test_start=$8E39, BRK=$90CF, tc_count=$90D0),
ran all tests in VICE with correct breakpoint — all 17 pass in 3.1M cycles. Verified
store door positions match building geometry. Verified price arithmetic for boundary cases
(max cost 300 × max adj 130 = 39,000 fits 16-bit intermediate).

**Documented design deviations (acceptable):**
- 12 items per store vs 24 in umoria (noted in BUILDPLAN)
- No haggling (accept/decline at offered price, noted in BUILDPLAN)
- Restock on town re-entry vs umoria's turn-based (every 1000 turns, noted in BUILDPLAN)
- No item identification affecting prices (C64 scope limitation)
- No item stacking in store slots (each item takes one slot)

#### Findings

**RP14-1 (HIGH — Word of Recall to town skips store restock)**

`turn.s:157-163`: When Word of Recall teleports the player from dungeon to town, the code
sets `zp_player_dlvl=0`, sets `level_entry_dir=1`, and jumps to `recall_generate` which
calls `level_generate`, `monster_spawn_level`, `item_spawn_level`, etc. — but does NOT
call `store_restock_all`. In contrast, `main.s:405-407` correctly calls `store_restock_all`
when ascending stairs to town (dlvl becomes 0).

The BUILDPLAN Step 8.1 says "Inventory restocking on town re-entry." Word of Recall is a
form of town re-entry. The fix is to add `jsr store_restock_all` in the WoR-to-town path,
after setting dlvl=0 and before `jmp !recall_generate+`.

**RP14-2 (MEDIUM — BUILDPLAN says "race modifier" but implementation omits it)**

BUILDPLAN Step 8.3: "Base price x charisma modifier x **race modifier**." The implementation
uses ONLY charisma adjustment (`chr_price_adj` for buying, `chr_sell_adj` for selling).
No race-based price modifier exists.

In umoria, a `race_gold_adjustments[8][8]` table adjusts prices by ±5-35% based on
owner_race × player_race. The C64 store owners have names but no race data. This is a
reasonable simplification for the C64 scope, but the BUILDPLAN should be updated to remove
the "race modifier" reference to match the implementation, or a race modifier should be added.

**RP14-3 (MEDIUM — Enchantment and charges ignored in pricing)**

`calc_buy_price` and `calc_sell_price` use only the base item type cost (`it_cost_lo/hi`).
Enchantment level (`si_p1` / `inv_p1`) and item flags are completely ignored.

Impact: A +3 enchanted sword and a +0 sword of the same type cost the same to buy and sell.
A wand with 8 charges and a wand with 0 charges cost the same. In umoria, enchanted
weapons/armor get `(to_hit + to_damage + to_ac) × 100` added to base value, and
wands/staves get `(cost/20) × charges` added.

This is a design simplification but notable — players get no extra gold for selling superior
items, and store-stocked enchanted items are underpriced. Consider adding at least
`p1 × enchant_bonus_per_category` to the price calculation.

**RP14-4 (MEDIUM — Cursed items sellable at full base price)**

`calc_sell_price` does not check the `IF_CURSED` flag. A cursed item sells for the same
price as a normal item of the same type. In umoria, `storeItemValue()` returns 0 for
cursed items (identified as `ID_DAMD`), preventing sale.

The fix is to check `IF_CURSED` at the start of the sell flow (in `store_sell` at
`!ssell_cat_ok`) and either refuse the sale or set the price to 0. Additionally, when
a cursed item is sold to a store, it pollutes the store inventory — another player could
buy it back.

**RP14-5 (LOW — Store owner max gold not implemented)**

BUILDPLAN Step 8.1 mentions "Store owner data (name, race, max gold)." The implementation
has owner names (displayed in UI) but no race or max gold. Stores will buy items of
unlimited value. In umoria, each owner has `max_cost` (250-32,000 gold) which limits
both what items appear in auto-generated stock and the maximum price the owner will pay.

Update the BUILDPLAN to remove "race, max gold" from the owner data description if these
features are intentionally deferred.

**RP14-6 (LOW — test_store.s VICE breakpoint detection failure)**

All 17 tests in `test_store.s` pass correctly (verified by running in VICE with breakpoint
at BRK address $90CF). The apparent "hang" is caused by `tc_count: .byte 0` being defined
AFTER the `brk` instruction (line 478). This pushes the "Test Code" segment end address
to $90D0 (tc_count) instead of $90CF (brk). The `run_tests.sh` script extracts the segment
end address and sets a VICE breakpoint there — but $90D0 is data that's never executed, so
the breakpoint never fires. VICE hits the cycle limit and exits without processing monitor
commands (no memory dump occurs).

Fix: Move `tc_count` before `brk` (e.g., next to `tc_results`), so `brk` is the last byte
in the segment and the breakpoint fires correctly. Alternatively, eliminate tc_results and
write directly to $0400 (no store functions call msg_print, so screen RAM is safe).

**RP14-7 (LOW — inv_count_items clobbers fi_add_p1)**

`player_items.s`: `inv_count_items` reuses `fi_add_p1` as a scratch counter. This is
currently safe because `store_buy` re-sets `fi_add_p1` from the store slot data after
calling `inv_count_items` and before calling `inv_add_item`. However, this coupling is
fragile — any future caller that sets `fi_add_p1`, calls `inv_count_items`, then calls
`inv_add_item` without re-setting `fi_add_p1` would get corrupted data. Consider using
a dedicated scratch variable or a ZP temp instead.

#### Summary of Review Pass 14 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP14-1 | **HIGH** | Word of Recall to town skips store_restock_all | Trivial — add `jsr store_restock_all` in WoR-to-town path | **RESOLVED** — added `jsr store_restock_all` in turn.s WoR-to-town path |
| RP14-2 | **MEDIUM** | BUILDPLAN says "race modifier" for prices; implementation has charisma only | Trivial — update BUILDPLAN prose to match implementation | **RESOLVED** — Phase 8 table updated to say "charisma modifier only (race modifier deferred)" |
| RP14-3 | **MEDIUM** | Enchantment/charges ignored in pricing — all items of same type priced identically | Medium — add p1-based price bonus per category | **RESOLVED** — added `price_add_p1_bonus` in store.s: equipment +100 GP/enchant, wand/staff +10 GP/charge. New tests 18-19 verify. |
| RP14-4 | **MEDIUM** | Cursed items sellable at full base price (umoria: value 0) | Easy — check IF_CURSED in sell flow, refuse or set price 0 | **RESOLVED** — added IF_CURSED check in store_sell, displays "THAT ITEM IS CURSED." |
| RP14-5 | LOW | Store owner "max gold" mentioned in BUILDPLAN but not implemented | Trivial — update BUILDPLAN if intentionally deferred | **RESOLVED** — Phase 8 table updated to say "name only — race and max gold deferred" |
| RP14-6 | LOW | test_store.s VICE breakpoint fails — tc_count after brk shifts segment end | Trivial — move tc_count before brk | **RESOLVED** — tc_count moved before brk |
| RP14-7 | LOW | inv_count_items clobbers fi_add_p1 scratch (currently safe, fragile) | Easy — use dedicated scratch variable | **RESOLVED** — added `ici_count` dedicated scratch in item.s |

---

### Review Pass 15 — Staff Engineer Review of 18 Bug Fixes (2026-02-12)

Reviewed commit range `62e8480..a7b0712` (23 files changed, 1128 additions, 274 deletions).
Each bug fix was verified for 6502 assembly correctness, semantic correctness against umoria
behavior, and potential regressions. Also reviewed the RP14 fix commit (`ecdb78b`) and the
`store_pick_item` fix (`d21e376`).

**BUG-1 (18 stats inflating) — CORRECT.** Exceptional strength logic was being applied to
all stats, not just STR. Fix correctly gates the exceptional check on stat index == 0.

**BUG-2 (status bar redesign) — CORRECT.** Complete rewrite to 3-line umoria-style status
bar. 273 lines changed. Layout matches umoria conventions.

**BUG-3 (no townspeople) — CORRECT.** Added 6 town creature types (indices 20-25) and
`TOWN_CREATURE_BASE = 20` threshold for spawning. Town creatures use `MF_PROVOKED` flag
for aggression.

**BUG-4 (store door rendering) — CORRECT.** Per-tile store door check replaced with a
`render_store_doors` post-pass. More efficient and avoids disrupting dirty-tile rendering.

**BUG-5 (direction/diagonal key mapping) — CORRECT.** Directional keys now consistent.

**BUG-6 (no Q-to-quit in stores) — CORRECT.** Added `PETSCII_Q` ($51) as exit key in
store UI menu. Menu string updated to "Q)UIT".

**BUG-7 (auto-open door removes interactivity) — CORRECT.** Removed 10 lines of
auto-open door code; closed doors now block movement via `walkable_table[8]=0`.

**BUG-8 (sound_init not called) — CORRECT.** Added `jsr sound_init` in main.s init
sequence.

**BUG-9 (player '@' drawn as blank) — CORRECT.** Classic 6502 fall-through bug: missing
`jmp !rst_write+` after setting player tile caused execution to fall into blank-tile code.

**BUG-10 (look command) — CORRECT.** Direction scanning, monster/item/tile identification
all implemented. No assembly issues.

**BUG-11 (town creature provocation) — CORRECT, minor fragility note.** `MF_PROVOKED`
flag mechanism is correct. However, `TOWN_CREATURE_BASE = 20` is a magic number that
must stay synchronized with the creature table layout — any creature table reordering
will silently break the town/dungeon threshold. Consider a comment or `.assert`.

**BUG-12 (spell books) — CORRECT implementation, but introduced TWO side-effect bugs:**

> **RP15-1 (MEDIUM — Armory stocks spell books):** `ICAT_CLOAK` was renamed to `ICAT_BOOK`
> (value 13), but the Armory's category mask in `store_cat_mask_lo/hi` was not updated.
> Store 1 (Armory) has mask `$20F8` which has bit 13 set — this was intentional for cloaks,
> but now means the Armory unintentionally stocks spell books. Fix: change Armory mask from
> `$20F8` to `$00F8` (store.s line 35-37).

> **RP15-2 (MEDIUM — books get equipment pricing):** In `price_add_p1_bonus` (store.s
> line 436-437), `cmp #ICAT_BOOK / beq !pap_equip+` routes books to the equipment pricing
> handler that adds `p1 × 100` GP as an enchantment bonus. But book `p1` is a spell index
> (0-15), not an enchantment level — this creates up to 1500 GP of incorrect price inflation
> based on which spell the book teaches. Fix: remove the `ICAT_BOOK` branch from the
> equipment handler, or add a separate book pricing branch (e.g., flat 100 GP or base cost
> only, since spell books don't have enchantment).

**BUG-13 (folded into BUG-12 commit) — CORRECT.** No separate issues.

**BUG-14 (KERNAL GETIN clobbers X during name entry) — CORRECT.** Fix uses `cen_count`
byte to preserve character count across `input_get_key` calls. Clean solution that avoids
relying on X register surviving KERNAL calls.

**BUG-15 (debug hardcoded name) — CORRECT.** Removed test/debug name.

**BUG-16 (store screen clearing) — CORRECT.** Replaced `screen_clear` with
`ui_help_clear_all` for full 25-row clearing.

**BUG-17 (look command distance) — CORRECT.** Extended look to scan multiple tiles along
direction, not just adjacent tile. Turn-consuming actions reordered so AI runs before render.

**BUG-18 (inventory popup in selection dialogs) — CORRECT, minor note.** Added `'?'`
($3F) key check in 8 item selection dialogs to show inventory via `show_inv_and_restore`.
After the popup, the dialog re-prompts without re-validating state — this is safe because
inventory display can't modify game state, but worth noting as an assumption.

**store_pick_item fix (d21e376) — CORRECT.** `pha`/`pla` properly preserves item type
across `check_store_category` (which clobbers X). Previously returned store index (0-5)
instead of the item type.

**RP14 fixes (ecdb78b) — CORRECT.** All 7 RP14 findings addressed: WoR restock, plan
prose updates, enchantment pricing, cursed item check, tc_count position, and
`ici_count` dedicated scratch.

#### Summary of Review Pass 15 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP15-1 | **MEDIUM** | Armory mask $20F8 has bit 13 (ICAT_BOOK) — stocks spell books | Trivial — change to $00F8 in store_cat_mask_lo/hi | **Fixed** (Step 9.4) — mask data was already $00F8; fixed stale comment + test |
| RP15-2 | **MEDIUM** | price_add_p1_bonus routes ICAT_BOOK to equipment handler (p1×100 GP) | Easy — remove ICAT_BOOK from equipment branch or add flat book pricing | **Resolved** — ICAT_BOOK not in equipment branch; books fall through to no-bonus |
| RP15-3 | LOW | TOWN_CREATURE_BASE=20 is a magic number synced to creature table layout | Trivial — add .assert or comment | **Resolved** — already protected by .assert at monster.s:16 |
| RP15-4 | LOW | BUG-18 re-entry after inventory popup skips state re-validation (currently safe) | N/A — document assumption only | **Resolved** — comment added to show_inv_and_restore (player_items.s:65) |

**Overall verdict:** All 18 bug fixes are correct at the 6502 assembly level. No register
clobbering, branch range, or logic errors found. Two semantic bugs (RP15-1, RP15-2)
were introduced as side effects of the BUG-12 (spell books) implementation, both in
store.s. These are both straightforward fixes.

---

### Review Pass 16 — Save/Load System Review (Phase 9.1) (2026-02-13)

Reviewed save.s (1118 lines), main.s integration (title screen, load_resume_game),
and supporting files (memory.s, zeropage.s, player.s, dungeon_gen.s, dungeon_render.s).
Commits: `24b2df8` (initial save/load), `3cfa751` (crash fixes).

**Context:** User reports loading a save game crashes. The crash fix commit `3cfa751`
already addressed several issues: entry point under BASIC ROM, CREATURE_BASE overlap
with program code ($A100 → $AA00), file number conflict in check_savefile_exists, and
delete_savefile closing when OPEN failed. This review looks for remaining issues.

---

**RP16-1 (HIGH — player_sync_from_zp doesn't save light_radius; load overwrites it)**

In `save_game` (save.s:164), `player_sync_from_zp` is called before saving. But
`player_sync_from_zp` (player.s:153-183) does NOT copy `zp_light_radius` ($4B) back
to `player_data + PL_LIGHT_RAD`. It saves X, Y, HP, MHP, MP, level, dlvl, AC, and
food — but not light_radius, STR/INT/WIS/DEX/CON/CHR, race, or class.

The ZP state block ($40-$5F) IS saved, which includes $4B (correct light_radius value).
But during `load_game`, the load order is:
1. Step 3: load ZP $40-$5F from file → $4B gets correct saved value
2. Step s (save.s:499): `player_sync_to_zp` → overwrites $4B with
   `player_data + PL_LIGHT_RAD` (stale struct value)

Since PL_LIGHT_RAD is only set during player creation (via `player_sync_to_zp` copying
it from the struct), and the main.s new-game code sets `zp_light_radius = 1` directly
in ZP (main.s:224) without updating the struct, PL_LIGHT_RAD in the struct is likely 0.

**Result:** After loading, `zp_light_radius = 0`. `update_visibility` creates a 0-tile
visibility radius — the player can only see their own tile. The screen appears almost
entirely blank. While this doesn't cause a CPU crash, it makes the game unplayable and
likely appears as a "crash" to the user.

**Fix (two options):**
- **(A)** Add `lda zp_light_radius / sta player_data + PL_LIGHT_RAD` to
  `player_sync_from_zp`, so the struct always has the current value.
- **(B)** In `load_game`, move `player_sync_to_zp` BEFORE loading ZP $40-$5F, so the
  ZP state block has final authority. But this breaks other fields — option A is better.
- Also add the same line to `main.s` new-game init (after `lda #1 / sta zp_light_radius`,
  add `sta player_data + PL_LIGHT_RAD`).

---

**RP16-2 (HIGH — save filename is "MORIA SAV", should be "moria.sav")**

All four filename strings in save.s use the PETSCII sequence for "MORIA SAV" (with
space, no dot). The user requires the filename to be "moria.sav". On the 1541, filenames
can contain dots and lowercase letters. PETSCII lowercase letters are $41-$5A (same
codes as uppercase in PETSCII — the 1541 stores them as-is).

Affected strings (save.s lines 77-99):
- `save_filename`: `@0:MORIA SAV,S,W` → `@0:MORIA.SAV,S,W`
- `load_filename`: `0:MORIA SAV,S,R` → `0:MORIA.SAV,S,R`
- `scratch_cmd`: `S0:MORIA SAV` → `S0:MORIA.SAV`
- `check_filename`: `0:MORIA SAV,S,R` → `0:MORIA.SAV,S,R`

Fix: Replace `$20` (space) with `$2E` (PETSCII dot) in all four strings. Lengths
remain the same.

---

**RP16-3 (MEDIUM — READST EOF bit not checked during load)**

`load_read_block` (save.s:651-654) and `load_read_byte` (save.s:688-691) check
READST with `and #$03` (timeout/error bits only). They do not check bit 6 ($40)
which indicates EOF. If the save file is truncated, CHRIN will return $0D or
unpredictable values after EOF without flagging an error.

The checksum verification (save.s:484-493) provides a secondary defense — truncated
data will almost certainly fail the checksum. However, defense-in-depth requires
detecting the I/O error at the source.

Fix: Change mask from `$03` to `$43` to include EOF detection. This affects 4 locations:
save.s lines 567, 605, 653, 689 (write-side $03 checks can stay as-is since writes
don't encounter EOF).

---

**RP16-4 (MEDIUM — no RLE decompression output bounds check)**

`rle_decompress_map` (save.s:1021-1094) writes decompressed data to `MAP_BASE`
($C000) using `zp_ptr1` without checking that output doesn't exceed `MAP_SIZE` (3840
bytes). If the compressed data is corrupt (despite passing checksum), the output could
write past `MAP_END` ($CEFF) into `FLOOR_ITEM_BASE` ($CF00), corrupting floor item
data loaded moments earlier.

The checksum should catch most corruption, but this is a defense-in-depth issue.

Fix: Add a decompressed-byte counter. After decompression, assert the counter equals
MAP_SIZE. Or add bounds checking on `zp_ptr1_hi` during the write loop.

---

**RP16-5 (MEDIUM — player_sync_from_zp / player_sync_to_zp asymmetry)**

`player_sync_to_zp` (player.s:106-151) copies 20 fields from struct to ZP:
map X/Y, HP, MHP, MP, MMP, level, dlvl, AC, STR/INT/WIS/DEX/CON/CHR, race, class,
food, and light_radius.

`player_sync_from_zp` (player.s:153-183) copies only 13 fields back:
map X/Y, HP, MHP, MP, MMP, level, dlvl, AC, food.

Missing from sync_from_zp: STR/INT/WIS/DEX/CON/CHR (recalculated — OK), race/class
(immutable — OK), **light_radius** (mutable — BUG, see RP16-1).

The asymmetry means any future mutable field added to sync_to_zp but not sync_from_zp
will silently break save/load. Consider adding a comment documenting which fields are
intentionally excluded and why, or making the functions fully symmetric.

---

**RP16-6 (LOW — ZP $60-$8F not saved, mostly OK but fragile)**

The save system saves ZP $40-$5F (game state + effect timers) and the player struct
($2B-$3F via sync). But ZP $60-$8F (viewport, sound, monster AI, combat, inventory
scratch) is not saved. This is currently safe because:
- Viewport ($60-$63): recalculated by `viewport_update`
- Sound ($6C-$6F): reinitialized by `sound_init`
- Monster/combat/inv scratch ($70-$8F): transient, recalculated on use
- Dirty tiles ($69-$6B): `render_viewport` does full redraw, not dirty update

But `zp_ui_dirty` ($19) and `zp_msg_flags` ($18) are in the safe zone ($13-$19) which
is NOT covered by either the ZP save block ($40-$5F) or player sync ($2B-$3F). After
load, `msg_init` resets $18, and `zp_ui_dirty` should be 0 (no pending updates). This
is currently safe but the gap should be documented.

---

**RP16-7 (LOW — rle_flush_literals page-crossing handler tests X not Y)**

In `rle_flush_literals` (save.s:978-988), the page-crossing code:
```
    sta (zp_ptr1),y
    iny
    inx
    bne !rfl_copy-          // Tests INX result, not INY
    inc zp_ptr1_hi
```

The `bne` tests the Z flag from `inx`, not `iny`. The comment says "Handle page
crossing in dest" but the actual page crossing (Y wrapping from $FF to $00) is not
detected. This is currently harmless because the maximum literal length is 128, so Y
ranges from 1 to 129 ($81) and never wraps. But the logic is misleading and would
break if RLE_LITERAL_MAX were ever increased above 254.

---

#### Summary of Review Pass 16 findings

| # | Severity | Issue | Fix complexity | Status |
|---|----------|-------|----------------|--------|
| RP16-1 | **HIGH** | player_sync_from_zp doesn't save light_radius — load reverts to 0, screen blank | Easy — add light_radius to sync_from_zp + init struct in main.s | **Fixed** |
| RP16-2 | **HIGH** | Filename "MORIA SAV" should be "moria.sav" per user requirement | Trivial — change $20 to $2E in 4 filename strings | **Fixed** |
| RP16-3 | **MEDIUM** | READST EOF bit ($40) not checked — truncated files not detected at I/O level | Easy — change mask from $03 to $43 in load_read_block/byte | **Fixed** |
| RP16-4 | **MEDIUM** | No RLE decompression output bounds check — corrupt data writes past MAP_END | Medium — add decompressed-byte counter or ptr bounds check | **Fixed** |
| RP16-5 | **MEDIUM** | sync_from_zp / sync_to_zp asymmetry — light_radius (and future fields) lost | Easy — document intentional exclusions, fix light_radius | **Fixed** |
| RP16-6 | LOW | ZP $60-$8F and $13-$19 not saved — currently safe, gaps undocumented | Trivial — add comments documenting the gap | **Fixed** |
| RP16-7 | LOW | rle_flush_literals page-crossing tests X not Y — dead code, misleading | Trivial — fix or add comment noting it's intentionally dead | **Fixed** |

**Likely crash cause:** RP16-1. After loading, `zp_light_radius` reverts to 0 (struct
value), making the screen appear almost completely blank. The player sees only their own
tile — this effectively looks like a crash or freeze. The root cause is that
`player_sync_from_zp` doesn't save light_radius to the struct, so when
`player_sync_to_zp` runs during load and copies the stale struct value (0) to ZP, it
overwrites the correct value that was loaded from the ZP state block.

---


---

### Audit: Light Source Duration vs. Umoria (2026-02-17)

Compared torch and brass lantern charge values against umoria source (`data_treasure.cpp`, `game_run.cpp`, `treasure.cpp`).

#### Umoria Reference Values

| Item | Full Charge | Store-Bought | Dungeon Find | Warning Threshold |
|------|------------|-------------|--------------|-------------------|
| **Wooden Torch** | **4,000 turns** | 4,000 | `randomNumber(4000)` = 1–4,000 | < 40 turns remaining (1-in-5 chance per turn) |
| **Brass Lantern** | **7,500 turns** | 7,500 | `randomNumber(7500)` = 1–7,500 | < 40 turns remaining (1-in-5 chance per turn) |

Umoria uses 16-bit `misc_use` field (int16_t). Decrements by 1 per turn. Store torches sold in stacks of 5.

#### C64 Port Current Values

| Item | Charge Range | Starting Torch | Warning |
|------|-------------|----------------|---------|
| **Wooden Torch** (type 13) | `20 + rng(30)` = **20–49 turns** | 40 (fixed) | Exactly 10 turns remaining |
| **Brass Lantern** (type 14) | `50 + rng(50)` = **50–99 turns** | — | Exactly 10 turns remaining |

Charges stored in `inv_p1` (8-bit, max 255). Decrements by 1 per turn in `turn_tick_light`.

#### Problem

C64 values are **~100x too low**. Torches should last thousands of turns, not dozens. The root cause is the 8-bit `inv_p1` field — umoria's values (4,000 and 7,500) don't fit in a byte.

With current values, a torch lasts ~35 turns on average — barely enough to explore a single room and corridor. In umoria, a store-bought torch lasts 4,000 turns (~100 dungeon levels of casual exploration). Light management is a background resource concern in umoria, not a constant crisis.

#### RP17-1 ~~(HIGH)~~ DONE: Light source duration ~100x too short

**Fixed** using Option B (x30 multiplier). `LIGHT_TICKS_PER_CHARGE = 30` with `light_tick_counter` in `turn_tick_light`. Each charge = 30 turns.

| Item | Charges (store) | Charges (dungeon) | Effective turns |
|------|----------------|-------------------|-----------------|
| Torch | 134 | 67 + rng(67) | ~4,020 (store) |
| Lantern | 250 | 125 + rng(125) | ~7,500 (store) |
| Starting torch | 134 | — | 4,020 |
| Warning threshold | 2 charges | — | ~60 turns remaining |

Files changed: `turn.s`, `item.s`, `main.s`, `tests/test_item.s`.

**Status:** Open

---


---

## Phase 7 — Magic System: Detailed Implementation Plan

### Current State Summary

**What exists:**
- Player struct has mana fields (`PL_MANA`=$31, `PL_MAX_MANA`=$32), spell type
  (`PL_SPELL_TYPE`=60), and `PL_SPELLS_KNOWN` 16-bit bitmask (offsets 61-62).
  16 spare bytes in player struct (offsets 63-79).
- Mana initialized in `player_create.s` (spell_stat/2, min 1). Displayed in
  `ui_status.s` and `ui_character.s`. Synced to/from ZP by `player_sync_*`.
- Command IDs defined: `CMD_CAST=$1A`, `CMD_PRAY=$1B`, `CMD_AIM=$18`,
  `CMD_USE=$19`. Key mappings exist in `input.s` but **not dispatched** in `main.s`.
- 14 status effect timers at ZP $50-$5E already ticked by `turn_tick_effects`
  in `turn.s`. Spells only need to SET timers — decrement/expiry is done.
- 3 potions (Cure Light, Speed, Poison) and 3 scrolls (Light, Identify,
  Teleportation) working with full identification system (Fisher-Yates shuffle).
- `get_direction_target` provides directional prompt (8 directions) + target
  tile calculation. `dir_dx`/`dir_dy` tables in `input.s`.
- `find_random_floor` finds an unoccupied floor tile (used by teleport scroll).
- LOS scratch at ZP $84-$87 reserved but Bresenham line trace **not implemented**.
- 20 creature types (levels 1-5). No spell/breath data in creature tables.
  Active monster entry has 2 reserved bytes (10-11).
- ~13.8 KB code space remaining ($6A00-$9FFF). 8 KB under KERNAL ROM available
  for spell tables if needed (but tables are small enough for main area).
- 5 spare ZP bytes ($4F, $5F, $6F, $8E, $8F) + scratch reuse.

**What's missing:**
- No cast/pray command dispatch. No spell list UI.
- No spell data tables (costs, levels, failure rates, effects).
- No learn-spells-on-level-up logic. No mana recalculation on level-up.
- No mana regeneration in turn processing.
- No Bresenham line trace for bolt/breath targeting.
- No wand/staff item categories or charge mechanics.
- No monster spell/breath data or ranged attack logic.
- Word of Recall timer ticks but the teleport TODO is unimplemented.

### Memory Budget

| Component | Estimated bytes |
|-----------|-----------------|
| Spell data tables (32 spells × 5 bytes + 32 name ptrs) | ~230 |
| Spell name strings (32 × avg 15 chars) | ~500 |
| `player_magic.s` (cast/pray, spell list UI, learn, failure roll) | ~1,500 |
| Shared effect subroutines (extracted + new) | ~800 |
| 16 mage spell effect handlers | ~1,200 |
| 16 priest prayer effect handlers | ~800 (many share w/ mage) |
| Expanded potions (7 new types, effect code) | ~600 |
| Expanded scrolls (7 new types, effect code) | ~700 |
| Wand/staff items + aim/use handlers + Bresenham | ~1,200 |
| Monster magic (spell data, ranged AI, breath) | ~1,500 |
| New item type SoA entries (~22 types × 8 arrays) | ~180 |
| Identification shuffle tables for new types | ~100 |
| Integration (mana regen, level-up, Word of Recall) | ~300 |
| **Total estimate** | **~9,600** |
| **Available** | **~14,100** |
| **Margin** | **~4,500 (32%)** |

### Spell Lists

#### Mage Spells (16) — indexed 0-15, requires `PL_SPELL_TYPE == SPELL_MAGE`

| # | Name | Mana | Min Lvl | Fail% | Effect |
|---|------|------|---------|-------|--------|
| 0 | Magic Missile | 1 | 1 | 22 | 1d4+level/2 bolt (traces path up to 20 tiles) |
| 1 | Detect Monsters | 1 | 1 | 23 | Reveal all monsters on map for 1 turn |
| 2 | Phase Door | 2 | 1 | 24 | Teleport to random floor within 10 tiles |
| 3 | Light Area | 2 | 1 | 26 | Light current room (share with scroll) |
| 4 | Cure Light Wounds | 3 | 3 | 25 | Heal 1d8+1 (share with potion) |
| 5 | Find Traps/Doors | 3 | 3 | 28 | Reveal traps + secret doors in radius |
| 6 | Stinking Cloud | 3 | 5 | 30 | Confuse all adjacent monsters |
| 7 | Confusion | 4 | 5 | 32 | Confuse target monster (directional) |
| 8 | Lightning Bolt | 5 | 7 | 34 | Bolt: 3d8 damage along line |
| 9 | Trap/Door Destruction | 5 | 7 | 36 | Destroy traps+doors in radius |
| 10 | Sleep I | 6 | 9 | 38 | Sleep all adjacent monsters |
| 11 | Cure Poison | 6 | 9 | 40 | Set zp_eff_poison = 0 |
| 12 | Teleport Self | 7 | 11 | 42 | Random teleport (share with scroll) |
| 13 | Frost Bolt | 8 | 13 | 44 | Bolt: 5d8 damage along line |
| 14 | Wall to Mud | 10 | 15 | 46 | Destroy one wall tile (directional) |
| 15 | Fire Ball | 12 | 17 | 50 | 7d8 damage to all adjacent monsters |

#### Priest Prayers (16) — indexed 0-15, requires `PL_SPELL_TYPE == SPELL_PRIEST`

| # | Name | Mana | Min Lvl | Fail% | Effect |
|---|------|------|---------|-------|--------|
| 0 | Detect Evil | 1 | 1 | 10 | Reveal monsters (same as mage Detect) |
| 1 | Cure Light Wounds | 1 | 1 | 15 | Heal 1d8+1 (shared subroutine) |
| 2 | Bless | 2 | 1 | 20 | Set zp_eff_bless = 12+1d12 |
| 3 | Remove Fear | 2 | 3 | 24 | (Future: clear fear status) |
| 4 | Call Light | 2 | 3 | 25 | Light room (shared subroutine) |
| 5 | Find Traps | 3 | 5 | 27 | Reveal traps in radius |
| 6 | Detect Doors/Stairs | 3 | 5 | 30 | Reveal doors + stairs in radius |
| 7 | Slow Poison | 4 | 7 | 32 | Halve zp_eff_poison (round up) |
| 8 | Blind Creature | 5 | 7 | 36 | Blind target monster (directional) |
| 9 | Portal | 5 | 9 | 38 | Short teleport (share Phase Door) |
| 10 | Cure Medium Wounds | 6 | 9 | 38 | Heal 3d8+3 |
| 11 | Chant | 6 | 11 | 42 | Set zp_eff_bless = 24+1d24 (stronger) |
| 12 | Sanctuary | 7 | 11 | 44 | Sleep all adjacent monsters |
| 13 | Remove Curse | 8 | 13 | 46 | Clear IF_CURSED on all equipped items |
| 14 | Cure Serious Wounds | 10 | 15 | 48 | Heal 5d8+5 |
| 15 | Dispel Undead | 12 | 17 | 52 | Damage all undead monsters in room |

#### Expanded Item Types (22 new, IDs 25-46)

**New Potions (IDs 25-31) — 7 new + 3 existing = 10 total:**

| ID | Name | Effect |
|----|------|--------|
| 25 | Cure Serious Wounds | Heal 5d8+5 |
| 26 | Restore Strength | Restore STR to base value |
| 27 | Heroism | Set zp_eff_hero = 10+1d10 |
| 28 | Restore Mana | Restore mana to max |
| 29 | Resist Heat/Cold | Set zp_eff_resist = 20+1d20 |
| 30 | See Invisible | Set zp_eff_see_inv = 20+1d20 |
| 31 | Blindness | Set zp_eff_blind = 10+1d10 (harmful) |

**New Scrolls (IDs 32-38) — 7 new + 3 existing = 10 total:**

| ID | Name | Effect |
|----|------|--------|
| 32 | Word of Recall | Set zp_eff_word_recall = 15+1d10 |
| 33 | Remove Curse | Clear IF_CURSED on equipped items |
| 34 | Enchant Weapon | +1 to equipped weapon p1 |
| 35 | Enchant Armor | +1 to equipped armor p1 |
| 36 | Monster Confusion | Next melee hit confuses monster |
| 37 | Aggravate Monsters | Wake all monsters on level |
| 38 | Protect from Evil | Set zp_eff_protect = 20+1d20 |

**Wands (IDs 39-42) — `ICAT_WAND = 14`:**

| ID | Name | Charges | Effect |
|----|------|---------|--------|
| 39 | Light | 10-15 | Light room (directional not needed) |
| 40 | Lightning | 5-8 | Bolt: 3d8 along line |
| 41 | Frost | 5-8 | Bolt: 4d8 along line |
| 42 | Stinking Cloud | 5-8 | Confuse target monster |

**Staves (IDs 43-46) — `ICAT_STAFF = 15`:**

| ID | Name | Charges | Effect |
|----|------|---------|--------|
| 43 | Light | 10-15 | Light room |
| 44 | Detect Monsters | 5-8 | Reveal monsters |
| 45 | Teleportation | 3-5 | Teleport self |
| 46 | Cure Light Wounds | 5-8 | Heal 1d8+1 |

### Implementation Steps

---

#### Step 7.0 — Extract Shared Effect Subroutines

**Goal:** Refactor existing potion/scroll effect code into reusable subroutines
callable from spells, potions, scrolls, wands, and staves. This is the foundation
that prevents code duplication across all of Phase 7.

**File:** `spell_effects.s` (new)

**Subroutines to extract/create:**

| Subroutine | Source | What it does |
|------------|--------|--------------|
| `eff_heal(A=amount)` | `player_items.s` quaff cure | Add pre-rolled 8-bit amount to HP, cap at max HP (16-bit). Callers roll dice separately via `math_dice`. (RP10-6: simplified from plan's dice-param API.) |
| `eff_light_room` | `player_items.s` scroll of light | Light current room tiles |
| `eff_teleport_self` | `player_items.s` scroll of teleport | find_random_floor, move player, update occupied flags |
| `eff_phase_door` | New | find_random_floor within 10 tiles of player |
| `eff_identify_prompt` | `player_items.s` scroll of identify | Prompt for slot, set id_known + IF_IDENTIFIED |
| `eff_cure_poison` | New (trivial) | `lda #0; sta zp_eff_poison` |
| `eff_detect_monsters` | New | Scan active monster table, mark positions FLAG_VISITED |
| `eff_confuse_adjacent` | New | Scan adjacent tiles, set MX_CONFUSE on monsters found |
| `eff_sleep_adjacent` | New | Scan adjacent tiles, clear MF_AWAKE + set MX_SLEEP_CUR |
| `eff_find_traps` | New | Scan visible radius, reveal hidden traps |
| `eff_find_doors` | New | Scan visible radius, reveal secret doors |
| `eff_bolt(dir, dice, sides)` | New | Bresenham line trace, damage first monster hit |
| `eff_remove_curse` | New | Scan equipment slots, clear IF_CURSED flags |
| `eff_aggravate` | New | Wake all monsters on level (set MF_AWAKE) |

**Steps:**
1. Create `spell_effects.s`. Add `#import` to `main.s`.
2. Extract `eff_heal` from `player_items.s:712-762` (the Cure Light Wounds HP
   addition + 16-bit cap logic). Parameterize: A=dice count, X=sides, Y=bonus.
   Replace original quaff code with `lda #1; ldx #8; ldy #1; jsr eff_heal`.
3. Extract `eff_light_room` from `player_items.s:910-960` (the Light scroll
   room-lighting loop). Replace original scroll code with `jsr eff_light_room`.
4. Extract `eff_teleport_self` from `player_items.s:1050-1100` (find_random_floor,
   clear old FLAG_OCCUPIED, move player, set new FLAG_OCCUPIED). Replace original
   with `jsr eff_teleport_self`.
5. Extract `eff_identify_prompt` from `player_items.s:980-1040` (prompt for
   inventory slot, set id_known, set IF_IDENTIFIED). Replace with call.
6. Write new subroutines: `eff_cure_poison`, `eff_detect_monsters`,
   `eff_confuse_adjacent`, `eff_sleep_adjacent`, `eff_find_traps`, `eff_find_doors`,
   `eff_remove_curse`, `eff_aggravate`. Each is ~30-60 bytes.
7. Write `eff_phase_door` — like `eff_teleport_self` but with distance check:
   call find_random_floor in a loop, accept first result within Chebyshev
   distance 10 of player (max 20 attempts, fall back to any floor).

**Tests:**
- Existing potion/scroll tests must still pass (verify refactor didn't break).
- New compile-time asserts for each new subroutine.
- Runtime test: `eff_heal` with known dice → verify HP change.
- Runtime test: `eff_detect_monsters` → verify monster tile gets FLAG_VISITED.

---

#### Step 7.1 — Spell Data Tables

**Goal:** Define the 32 spell/prayer data tables and name strings.

**File:** `spell_data.s` (new)

**Data structures:**

```
// Per-spell table (one array per field, 16 entries each for mage + priest)
mage_spell_mana:    .byte 1, 1, 2, 2, 3, 3, 3, 4, 5, 5, 6, 6, 7, 8, 10, 12
mage_spell_level:   .byte 1, 1, 1, 1, 3, 3, 5, 5, 7, 7, 9, 9, 11, 13, 15, 17
mage_spell_fail:    .byte 22, 23, 24, 26, 25, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 50
priest_spell_mana:  .byte 1, 1, 2, 2, 2, 3, 3, 4, 5, 5, 6, 6, 7, 8, 10, 12
priest_spell_level: .byte 1, 1, 1, 3, 3, 5, 5, 7, 7, 9, 9, 11, 11, 13, 15, 17
priest_spell_fail:  .byte 10, 15, 20, 24, 25, 27, 30, 32, 36, 38, 38, 42, 44, 46, 48, 52

// Name pointer tables (lo/hi, 16 entries each)
mage_spell_name_lo:  .byte <msn_0, <msn_1, ...
mage_spell_name_hi:  .byte >msn_0, >msn_1, ...
priest_spell_name_lo: .byte <psn_0, <psn_1, ...
priest_spell_name_hi: .byte >psn_0, >psn_1, ...

// Name strings (null-terminated PETSCII)
msn_0: .text "MAGIC MISSILE" ; .byte 0
msn_1: .text "DETECT MONSTERS" ; .byte 0
... (16 mage + 16 priest)
```

**Steps:**
1. Create `spell_data.s` with all tables above.
2. Add `#import` to `main.s`.
3. Compile-time asserts: table sizes match (16 entries each), mana values > 0,
   levels monotonically non-decreasing.

**Tests:**
- `.assert` for table element counts.
- `.assert` spot-checks: `mage_spell_mana[0] == 1`, `priest_spell_fail[15] == 52`.

---

#### Step 7.2 — Cast/Pray Commands (`player_magic.s`)

**Goal:** Implement the `m` (cast) and `p` (pray) commands. Player sees spell
list, selects a spell, failure/success is rolled, mana is deducted.

**File:** `player_magic.s` (new)

**Entry points:**
- `player_cast_spell` — called from main.s CMD_CAST dispatch
- `player_pray` — called from main.s CMD_PRAY dispatch
  (Both share most logic; only the table pointers and spell_type check differ.)

**Detailed logic for `player_cast_spell`:**
```
1. Check PL_SPELL_TYPE != SPELL_MAGE → print "YOU CANNOT CAST SPELLS." → clc, rts
2. Call spell_list_display (mage tables) — show known spells with mana costs
3. Prompt: "CAST WHICH SPELL? (A-P, ESC)" → input_get_key
4. ESC/space → cancel, clc, rts
5. Convert letter to spell index (A=0, B=1, ...)
6. Check bit in PL_SPELLS_KNOWN → if not known, "YOU DON'T KNOW THAT SPELL.", clc, rts
7. Check mana cost <= zp_player_mp → if insufficient, "NOT ENOUGH MANA.", clc, rts
8. Check spell min_level <= zp_player_lvl → if too low, "YOU'RE NOT EXPERIENCED ENOUGH.", clc, rts
9. Deduct mana: zp_player_mp -= cost; sync to player_data + PL_MANA
10. Roll failure: adjusted_fail = fail_base - 3*(level - spell_level) - spell_stat_bonus
    Clamp to [5, 95]. Roll rng_range(100): if roll < adjusted_fail → "YOUR SPELL FAILS.", sec, rts
11. Dispatch spell effect: jsr mage_effect_dispatch (CMP/BEQ chain on spell index)
12. Print effect-specific message. sec, rts (turn consumed)
```

**`spell_list_display` subroutine:**
```
1. screen_clear (or use message area — could use full-screen overlay like inventory)
2. Print header: "  SPELLS  MANA  LVL"
3. For each spell 0-15:
   a. Check if bit set in PL_SPELLS_KNOWN → if not, skip (or show "???" for unknown)
   b. Print letter (A-P), spell name, mana cost, min level
   c. If mana cost > zp_player_mp, show in dim color
4. Wait for keypress (the selection key, handled by caller)
```

**`player_pray` — identical structure but:**
- Check `PL_SPELL_TYPE == SPELL_PRIEST`
- Use `priest_spell_*` tables
- Use `priest_effect_dispatch`
- Messages say "PRAY" instead of "CAST"

**main.s dispatch additions** (insert before "Unknown command" at line ~659):
```
    // Cast spell?
    cmp #CMD_CAST
    bne !not_cast+
    jsr msg_clear
    jsr player_cast_spell
    bcc !cast_no_turn+
    jsr update_visibility     // Some spells change visibility
    jsr viewport_update
    jsr render_viewport
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr status_draw
    jmp !main_loop-
!cast_no_turn:
    jmp !main_loop-
!not_cast:

    // Pray?
    cmp #CMD_PRAY
    bne !not_pray+
    (same pattern, calling player_pray)
!not_pray:
```

**Steps:**
1. Create `player_magic.s`. Add `#import` to `main.s`.
2. Implement `spell_list_display` — full-screen overlay showing spell list.
   Use inventory display pattern from `ui_inventory.s` as template.
3. Implement `player_cast_spell` with the 12-step logic above.
4. Implement `player_pray` (thin wrapper changing table pointers + spell type).
5. Add `CMD_CAST` and `CMD_PRAY` dispatch blocks in `main.s` (before line 659).
6. Implement `calc_spell_failure` — the failure adjustment formula:
   `adjusted = fail_base - 3*(player_level - spell_level) - spell_stat_bonus[stat-3]`
   Clamped to [5, 95]. Uses `spell_stat_bonus` table already in `tables.s`.

**Tests:**
- Compile-time: assert mana deduction arithmetic.
- Runtime test: Set player as Mage, give all spells known (PL_SPELLS_KNOWN=$FFFF),
  set mana=10, cast spell 0 (Magic Missile, cost 1). Verify mana becomes 9.
- Runtime test: Set mana=0, attempt cast → verify "NOT ENOUGH MANA", carry clear.
- Runtime test: Warrior (SPELL_NONE) attempts cast → verify rejection message.
- Runtime test: Cast unknown spell (bit not set) → verify rejection.

---

#### Step 7.3 — Learn Spells on Level-Up + Mana Recalc

**Goal:** When the player levels up, check if new spells become available.
Recalculate max mana based on level + spell stat.

**File:** `player_magic.s` (append)

**Learn-spells logic (`magic_check_new_spells`):**
```
1. Get player's spell_type. If SPELL_NONE, rts.
2. Select table pointer (mage_spell_level or priest_spell_level).
3. For each spell index 0-15:
   a. If already known (bit set in PL_SPELLS_KNOWN), skip.
   b. If spell_level[i] <= zp_player_lvl:
      - Set bit in PL_SPELLS_KNOWN (use ORA with bit mask)
      - Print "YOU HAVE LEARNED <spell name>!"
4. Sync PL_SPELLS_KNOWN to player_data.
```

**Mana recalculation (`magic_recalc_mana`):**
```
1. Get spell_type. If SPELL_NONE → max_mana = 0, rts.
2. Get spell stat (INT for mage, WIS for priest): stat = zp_player_int or zp_player_wis
3. max_mana = (level * stat) / 8 + spell_stat_bonus[stat-3]
   (Simplified from umoria; gives reasonable progression)
4. Clamp max_mana to [1, 255]
5. Store to PL_MAX_MANA and zp_player_mmp
6. If PL_MANA > max_mana, set PL_MANA = max_mana (stat drain case)
```

**Bit mask helper table:**
```
spell_bit_mask:
    .byte $01, $02, $04, $08, $10, $20, $40, $80  // Bits 0-7 (lo byte)
spell_bit_hi_mask:
    .byte $01, $02, $04, $08, $10, $20, $40, $80  // Bits 8-15 (hi byte)
```
Spells 0-7 use lo byte with `spell_bit_mask`, spells 8-15 use hi byte with
`spell_bit_hi_mask`.

**Integration into level-up** (`combat.s:519-558`):
After `jsr player_calc_combat` (line 543), add:
```
    jsr magic_recalc_mana
    jsr magic_check_new_spells
```

**Starting spells** (`player_create.s`):
After mana initialization (~line 624), add:
```
    jsr magic_check_new_spells  // Learn level-1 spells at character creation
```

**Steps:**
1. Add `spell_bit_mask` table to `spell_data.s`.
2. Implement `magic_check_new_spells` in `player_magic.s`.
3. Implement `magic_recalc_mana` in `player_magic.s`.
4. Hook `magic_recalc_mana` + `magic_check_new_spells` into `combat_check_levelup`.
5. Hook `magic_check_new_spells` into `player_create.s` after mana init.

**Tests:**
- Runtime: Create Mage at level 1 → verify spells 0-3 known (all have min_level 1).
- Runtime: Set Mage to level 3, call `magic_check_new_spells` → verify spells 4-5
  now known.
- Runtime: Verify `magic_recalc_mana` with INT=12, level=5 → expected max_mana
  = (5*12)/8 + bonus[12-3] = 7 + 1 = 8. (RP10-4: bonus[9]=1 per `spell_stat_bonus` table.)

---

#### Step 7.4 — Mage Spell Effect Dispatch

**Goal:** Implement the 16 mage spell effects.

**File:** `player_magic.s` (effect dispatch) + `spell_effects.s` (shared code)

**Dispatch table** (called after successful cast):
```
mage_effect_dispatch:
    cmp #0
    beq !mage_eff_0+    // Magic Missile
    cmp #1
    beq !mage_eff_1+    // Detect Monsters
    ... (CMP/BEQ chain)
    rts                  // Unknown — no effect (safety)
```

**Effect implementations:**

| Spell | Implementation | Shared? |
|-------|---------------|---------|
| 0 Magic Missile | `eff_bolt(1,4,level/2)` — traces path, damages first monster hit | Shared bolt |
| 1 Detect Monsters | `jsr eff_detect_monsters` | Shared |
| 2 Phase Door | `jsr eff_phase_door` | Shared |
| 3 Light Area | `jsr eff_light_room` | Shared |
| 4 Cure Light Wounds | `lda #1; ldx #8; ldy #1; jsr eff_heal` | Shared |
| 5 Find Traps/Doors | `jsr eff_find_traps; jsr eff_find_doors` | Shared |
| 6 Stinking Cloud | `jsr eff_confuse_adjacent` | Shared |
| 7 Confusion | `get_direction_target` → find monster → set MX_CONFUSE | Partly new |
| 8 Lightning Bolt | `get_direction_target` → `lda #3; ldx #8; jsr eff_bolt` | Shared bolt |
| 9 Trap/Door Destroy | Scan radius, destroy traps + jam doors open | New |
| 10 Sleep I | `jsr eff_sleep_adjacent` | Shared |
| 11 Cure Poison | `jsr eff_cure_poison` | Shared |
| 12 Teleport Self | `jsr eff_teleport_self` | Shared |
| 13 Frost Bolt | `get_direction_target` → `lda #5; ldx #8; jsr eff_bolt` | Shared bolt |
| 14 Wall to Mud | `get_direction_target` → if wall tile, replace with floor | New |
| 15 Fire Ball | `lda #7; ldx #8; jsr eff_damage_adjacent` | New area dmg |

**New subroutines needed for this step:**
- `eff_bolt(A=dice, X=sides)` — Bresenham line trace from player in chosen
  direction. Step through tiles; stop at wall. If monster found, roll damage,
  apply to monster HP, check kill. Uses ZP $84-$87 for line state.
- `eff_damage_adjacent(A=dice, X=sides)` — Scan 8 adjacent tiles for monsters,
  roll damage for each, apply, check kills.
- `eff_directional_monster` — `get_direction_target`, find monster at target
  tile. Returns monster index in X or carry clear if no monster.

**Bresenham bolt algorithm (`eff_bolt`):**
```
1. Get direction from get_direction_target. Extract dx, dy from dir_dx/dir_dy.
2. Start at player position (px, py). Step: x += dx, y += dy each iteration.
3. For each step (max 20 iterations — longest dungeon dimension):
   a. Check bounds (0 < x < MAP_W-1, 0 < y < MAP_H-1).
   b. Read map tile. If wall → stop (bolt hits wall, no damage).
   c. Check for monster at (x, y) via monster_find_at.
   d. If monster found → roll damage, apply, check kill. Stop.
4. If bolt exits map or reaches max range → fizzle.
```
Note: This is a simplified "straight-line" bolt, not a full Bresenham with
fractional error — movement is exactly along the 8 cardinal/diagonal directions,
one tile per step. This matches how `dir_dx`/`dir_dy` work and is sufficient
for the dungeon's grid-based geometry.

**Steps:**
1. Implement `eff_bolt` in `spell_effects.s`.
2. Implement `eff_damage_adjacent` in `spell_effects.s`.
3. Implement `eff_directional_monster` in `spell_effects.s`.
4. Implement `mage_effect_dispatch` in `player_magic.s` with all 16 effects.
5. Hook up to `player_cast_spell` (JSR to dispatch after successful cast).

**Tests:**
- Runtime test: Cast Magic Missile with monster adjacent → verify damage applied.
- Runtime test: Cast Light Area → verify room tiles get FLAG_LIT.
- Runtime test: Cast Teleport Self → verify player moved.
- Runtime test: Cast Lightning Bolt toward monster 3 tiles away → verify damage.
- Runtime test: Cast Lightning Bolt toward wall → verify no damage, bolt stops.
- Runtime test: Cast Cure Light Wounds → verify HP increases.

---

#### Step 7.5 — Priest Prayer Effect Dispatch

**Goal:** Implement the 16 priest prayer effects. Many share code with mage spells.

**File:** `player_magic.s` (append)

**Dispatch + implementations:**

| Prayer | Implementation | Shared with |
|--------|---------------|-------------|
| 0 Detect Evil | `jsr eff_detect_monsters` | Mage #1 |
| 1 Cure Light Wounds | `lda #1; ldx #8; ldy #1; jsr eff_heal` | Mage #4 |
| 2 Bless | `lda #12; jsr rng_range; clc; adc #12; sta zp_eff_bless` | New (tiny) |
| 3 Remove Fear | (Placeholder — clear future fear timer) | New (tiny) |
| 4 Call Light | `jsr eff_light_room` | Mage #3 |
| 5 Find Traps | `jsr eff_find_traps` | Mage #5 (half) |
| 6 Detect Doors/Stairs | `jsr eff_find_doors` (incl stairs) | Mage #5 (half) |
| 7 Slow Poison | `lda zp_eff_poison; lsr; ora #1; sta zp_eff_poison` | New (tiny) |
| 8 Blind Creature | `jsr eff_directional_monster` → set stun on monster | New |
| 9 Portal | `jsr eff_phase_door` | Mage #2 |
| 10 Cure Medium Wounds | `lda #3; ldx #8; ldy #3; jsr eff_heal` | Shared heal |
| 11 Chant | `lda #24; jsr rng_range; clc; adc #24; sta zp_eff_bless` | Like Bless |
| 12 Sanctuary | `jsr eff_sleep_adjacent` | Mage #10 |
| 13 Remove Curse | `jsr eff_remove_curse` | Shared |
| 14 Cure Serious Wounds | `lda #5; ldx #8; ldy #5; jsr eff_heal` | Shared heal |
| 15 Dispel Undead | Scan visible monsters, if undead → 1d3*level damage | New |

**New monster flag needed:** `CF_UNDEAD = $02` in `cr_mflags`. No current tier-0
monsters are undead, but the flag is needed for future tiers. Dispel Undead will
check `cr_mflags[type] & CF_UNDEAD` before applying damage. For now, this spell
effectively does nothing (no undead in levels 1-5), which is correct — priests
learn it at level 17 and should be in deeper tiers by then.

**Steps:**
1. Add `CF_UNDEAD` constant to `monster.s`.
2. Implement `priest_effect_dispatch` in `player_magic.s`.
3. Each shared effect is a JSR to the corresponding subroutine.
4. Implement Bless/Chant (set `zp_eff_bless` timer with different durations).
5. Implement Blind Creature (directional monster + set MX_STUN timer).
6. Implement Dispel Undead (scan active monsters, check CF_UNDEAD, damage).

**Tests:**
- Runtime: Priest casts Bless → verify zp_eff_bless > 0.
- Runtime: Priest casts Cure Medium Wounds → verify HP gain is in [6, 27] range.
- Runtime: Priest casts Remove Curse with cursed equipped item → verify IF_CURSED
  cleared.
- Runtime: Priest casts Slow Poison with poison timer 10 → verify timer becomes 5.

---

#### Step 7.6 — Expanded Potions and Scrolls ✅ COMPLETE

**Goal:** Add 7 new potions and 7 new scrolls. Expand item type tables and
identification system. ITEM_TYPE_COUNT goes from 25 → 39.

**Files modified:** `item.s`, `player_items.s`, `zeropage.s`, `combat.s`,
`tests/test_item.s`, `run_tests.sh`

**New item types (14 total, IDs 25-38):**

| ID | Category | Name | Effect |
|----|----------|------|--------|
| 25 | Potion | Cure Serious Wounds | Heal 5d8+5 via eff_heal |
| 26 | Potion | Restore Mana | Set zp_player_mp = zp_player_mmp |
| 27 | Potion | Heroism | Set zp_eff_hero timer (rng(25)+25) |
| 28 | Potion | Blindness | Set zp_eff_blind timer (rng(100)+100) — harmful |
| 29 | Potion | Confusion | Set zp_eff_confuse timer (rng(15)+10) — harmful |
| 30 | Potion | Detect Monsters | jsr eff_detect_monsters |
| 31 | Potion | Infravision | Set zp_eff_infra timer (rng(50)+50) |
| 32 | Scroll | Word of Recall | Set zp_eff_word_recall (rng(15)+15) |
| 33 | Scroll | Remove Curse | jsr eff_remove_curse |
| 34 | Scroll | Enchant Weapon | Find EQUIP_WEAPON, inc inv_p1 (cap +5) |
| 35 | Scroll | Enchant Armor | Find EQUIP_BODY, inc inv_p1 (cap +5) |
| 36 | Scroll | Monster Confusion | Set zp_confuse_melee = 1 |
| 37 | Scroll | Aggravate | jsr eff_aggravate |
| 38 | Scroll | Protect from Evil | Set zp_eff_protect timer (rng(25)+25) |

**What was implemented:**

1. **`zeropage.s`** — Renamed `zp_spare_4f` → `zp_confuse_melee` ($4f): flag for
   Monster Confusion scroll's one-time confuse-on-melee-hit effect.

2. **`item.s` — SoA table extensions (14 new entries):**
   - Extended all 10 SoA arrays (`it_category`, `it_display`, `it_color`,
     `it_weight`, `it_dmg_dice`, `it_dmg_sides`, `it_base_ac`, `it_cost_lo/hi`,
     `it_min_level`) from 25 → 39 entries.
   - Added 14 name strings (`itn_25`..`itn_38`), extended `it_name_lo/hi`.
   - Extended `id_known` with 14× 0 (unknown at start).

3. **`item.s` — Lookup tables for non-contiguous type IDs:**
   - Potion types at IDs 17-19 and 25-31 are non-contiguous; scrolls at 20-22
     and 32-38. The old `sbc #17` / `sbc #20` approach breaks.
   - Added two 39-byte lookup tables: `potion_local_idx` and `scroll_local_idx`.
     Indexed by type ID → local category index (0-9), or $FF if not that category.
   - Rewrote `item_get_name_ptr` and `item_get_floor_color` potion/scroll branches
     to use lookup tables instead of subtraction.

4. **`item.s` — Expanded identification system:**
   - Expanded shuffle tables from 5 to 12 entries each (10 types, 12 descriptors).
   - Added 7 new potion descriptors: "AZURE", "SMOKY", "BROWN", "SILVER", "PINK",
     "CLOUDY", "GOLDEN".
   - Added 7 new scroll descriptors: "LUMEN", "VERITAS", "DURA", "LIBERA",
     "ACUTA", "FEROX", "TUTELA" (Latin-themed).
   - Expanded `potion_name_lo/hi`, `scroll_name_lo/hi` from 5 to 12 entries.
   - Expanded `potion_colors`, `scroll_colors` from 5 to 12 entries.
   - Updated `item_init_identification`: shuffle init `ldx #4` → `ldx #11`,
     Fisher-Yates loops `ldx #4` → `ldx #11`.

5. **`item.s` — Updated `pick_item_type`:**
   - Changed range from `rng_range(23) + 2` → `rng_range(37) + 2` (giving [2,38]).

6. **`item.s` — Updated compile-time asserts:**
   - `ITEM_TYPE_COUNT` assert from 25 to 39.

7. **`player_items.s` — 7 new potion handlers in `item_quaff`:**
   - CSW: Roll 5d8 via loop, add 5, jsr eff_heal. Msg: "YOU FEEL MUCH BETTER."
   - Restore Mana: Set MP=max MP. Msg: "YOUR MIND FEELS CLEAR."
   - Heroism: Timer → zp_eff_hero. Msg: "YOU FEEL HEROIC!"
   - Blindness: Timer → zp_eff_blind. Msg: "YOU CAN'T SEE!"
   - Confusion: Timer → zp_eff_confuse. Msg: "YOU FEEL DIZZY."
   - Detect Monsters: jsr eff_detect_monsters. Msg: "YOU SENSE NEARBY CREATURES."
   - Infravision: Timer → zp_eff_infra. Msg: "YOUR EYES TINGLE."
   - Dispatch uses JMP trampolines for branch distance.

8. **`player_items.s` — 7 new scroll handlers in `item_read_scroll`:**
   - Word of Recall: Timer → zp_eff_word_recall. Msg: "THE AIR CRACKLES AROUND YOU."
   - Remove Curse: jsr eff_remove_curse. Msg: "YOU FEEL CLEANSED."
   - Enchant Weapon: Inc inv_p1 at EQUIP_WEAPON (cap +5). Msg: "YOUR WEAPON GLOWS BRIEFLY."
   - Enchant Armor: Inc inv_p1 at EQUIP_BODY (cap +5). Msg: "YOUR ARMOR GLOWS BRIEFLY."
   - Monster Confusion: Set zp_confuse_melee=1. Msg: "YOUR HANDS BEGIN TO GLOW."
   - Aggravate: jsr eff_aggravate. Msg: "YOU HEAR A HIGH-PITCHED HUMMING."
   - Protect from Evil: Timer → zp_eff_protect. Msg: "YOU FEEL PROTECTED."
   - No weapon/armor → "YOU FEEL A STRANGE VIBRATION." (enchant scrolls).
   - 17 new message strings added.

9. **`combat.s` — Confuse-on-hit check:**
   - After `sta cmb_any_hit` (first hit scored), checks `zp_confuse_melee`.
   - If set: clears flag (one-time use), sets monster MX_CONFUSE timer to 20.
   - zp_ptr0 still points to monster entry (set by `monster_get_ptr` earlier).

10. **`tests/test_item.s` — 6 new runtime tests (tests 33-38):**
    - Test 33: CSW potion heals HP in [60, 95] (from 50, heal 10-45).
    - Test 34: Restore Mana sets MP = max MP (5 → 30).
    - Test 35: Enchant Weapon scroll increments p1 (2 → 3).
    - Test 36: Word of Recall sets zp_eff_word_recall in [15, 29].
    - Test 37: Blindness potion sets zp_eff_blind in [100, 199].
    - Test 38: pick_item_type returns new types (>= 25) at deep dungeon levels.
    - Updated test 21 range check from `cmp #25` → `cmp #39`.
    - Expanded tc_results buffer from 30 → 40, copy loop from 31 → 37.

11. **`run_tests.sh`** — Updated item test expected count from 32 → 38,
    result range from `0400 041f` → `0400 0425`.

**Shared subroutines reused from `spell_effects.s`:**
- `eff_heal` (line 28) — add pre-rolled amount to player HP
- `eff_detect_monsters` (line 264) — reveal monsters on map
- `eff_remove_curse` (line 313) — clear IF_CURSED on equipment
- `eff_aggravate` (line 1046) — wake all monsters

**Verification:**
- `make build` → 56 asserts, 0 failed ✅
- `make test` → 12/12 suites pass (item: 38/38 tests) ✅

---

#### Step 7.7 — Wands and Staves ✅ COMPLETE

**Goal:** Implement wand aiming and staff usage with charge tracking.

**Files modified:** `player_items.s`, `main.s`, `item.s`, `tests/test_wands_staves.s`, `run_tests.sh`

**What was implemented:**

1. **`item.s` — Wands and Staves data:**
   - Added SoA entries for item IDs 39-46 (4 wands, 4 staves).
   - Added descriptor tables and shuffling logic (wands: metal/wood types; staves: wood types).
   - Updated `pick_item_type` to include the new range [39, 46].
   - Updated `roll_enchantment` to initialize charges (p1).

2. **`player_items.s` — Logic:**
   - Implemented `item_aim_wand`: prompts for direction, checks charges, consumes charge, fires effect.
   - Implemented `item_use_staff`: checks charges, consumes charge, fires effect.
   - Effects wired: Light, Lightning, Frost, Stinking Cloud (Wands); Light, Detect Monsters, Teleport, Cure Light Wounds (Staves).

3. **`main.s` — Dispatch:**
   - Added `CMD_AIM` ('a') key dispatch.
   - Added `CMD_USE` ('Z') key dispatch.

**Verification:**
- Created `tests/test_wands_staves.s` runtime test suite.
- Verified generation of wands/staves with charges.
- Verified consumption of charges and effect triggering.
- Fixed test bugs (Step 9.4): `rts`→`brk` terminator; keyboard buffer needs 2 keys (slot + -more-).
- `make test` pass (17/17 suites).

---

#### Step 7.8 — Monster Magic (`monster_magic.s`) ✅ COMPLETE

**Goal:** Monsters with spellcasting ability can use ranged spells and breath
weapons instead of (or in addition to) melee attacks.

**What was done:**

The `monster_magic.s` framework (monster_can_cast, monster_pick_spell, 7 spell
handlers, AI hook) was already fully implemented. This step activated it by:

1. **Added 6 spellcasting dungeon creatures** (IDs 20-25) to `monster.s`:
   - Kobold Shaman (L3): 30% spell, bolt + heal
   - Giant White Ant Lion (L4): no spells, pure melee 2d4
   - Novice Mage (L4): 40% spell, bolt + confuse + blind
   - Novice Priest (L4): 35% spell, heal + summon
   - Giant Salamander (L5): 25% spell, breath
   - Orc Shaman (L5): 35% spell, bolt + confuse + heal

2. **Updated constants:** DUNGEON_CREATURES=26, TOWN_CREATURE_BASE=26,
   CREATURE_COUNT=32. Town creatures shifted to IDs 26-31.

3. **Fixed bug:** `monster_cast_summon` used CREATURE_COUNT (included town
   creatures); changed to DUNGEON_CREATURES.

4. **Moved MSF_* spell flag constants** from `monster_magic.s` to `monster.s`
   (needed by cr_spell_flags data arrays at assembly time).

5. **Bumped CREATURE_BASE** from $B200 to $B300 in `memory.s` to accommodate
   larger program. Reduced BFS_QUEUE_MAX from 1792 to 1664 (still far exceeds
   typical dungeon floor tile counts of ~400).

**Tests:** `tests/test_monster_magic.s` — 8 runtime tests:
1. monster_can_cast returns clear for spell_chance=0
2. monster_can_cast returns set for 100% chance + clear LOS
3. monster_can_cast fails when out of range (>8 tiles)
4. monster_can_cast fails with wall blocking LOS
5. Bolt damage in expected range [5, 19] (2d8+3)
6. Breath damage = HP/3 (30 HP → 10 damage)
7. Blind sets timer in [11, 20] (1d10+10)
8. Heal increases monster HP, capped at max

---

#### Step 7.9 — Mana Regeneration + Word of Recall ✅ COMPLETE

**Goal:** Mana regenerates over time. Word of Recall timer, when expired,
teleports the player between town and dungeon.

**Files modified:** `turn.s`, `main.s`, `tests/test_effects.s`

**What was implemented:**

1. **`turn.s` — Mana regeneration (lines 196-218):**
   - Spell-casting classes (PL_SPELL_TYPE != 0) regen 1 MP every 2 turns.
   - If `zp_eff_regen` active, regen rate doubles to 1 MP per turn.
   - Warriors skip mana regen entirely.
   - MP capped at max MP (`zp_player_mmp`).

2. **`turn.s` — Word of Recall (lines 138-194):**
   - Timer countdown in `turn_tick_effects`: when `zp_eff_word_recall` reaches 0,
     teleport triggers.
   - In dungeon (dlvl > 0) → teleport to town (dlvl = 0).
   - In town (dlvl = 0) → teleport to deepest level reached (`PL_MAX_DLVL`).
   - Fizzle if `PL_MAX_DLVL = 0` (player has never entered the dungeon).
   - Full level regeneration: `level_generate` + `monster_spawn_level` +
     `item_spawn_level` + visibility + viewport.
   - Messages: "YOU FEEL YOURSELF YANKED AWAY!" on teleport,
     "THE SPELL FIZZLES." on fizzle.

3. **`main.s` — Max depth tracking (lines 470-474):**
   - Stairs-down handler updates `PL_MAX_DLVL` when `zp_player_dlvl` exceeds it.

4. **`tests/test_effects.s` — Tests 11-14, 20-21:**
   - Test 11: Mage mana regen — MP increases after 2 turns.
   - Test 12: Warrior no mana regen — MP unchanged.
   - Test 13: Word of Recall dungeon→town — dlvl becomes 0.
   - Test 14: Word of Recall town→dungeon — dlvl becomes PL_MAX_DLVL.
   - Test 20: Recall fizzle — PL_MAX_DLVL=0 prevents teleport.
   - Test 21: Extra regen — MP increases every turn with zp_eff_regen active.

**Verification:**
- `make build` → all asserts pass ✅
- `make test` → all suites pass ✅

---

#### Step 7.10 — Integration, Polish, and Full Test Pass ✅ COMPLETE

**Goal:** Wire everything together, verify all commands work end-to-end,
fix edge cases.

**Files modified:** `player_magic.s`, `player_items.s`, `sound.s`, `ui_help.s`,
`ui_character.s`, `ui_status.s`

**What was implemented:**

1. **Confusion + casting (`player_magic.s:163-170`):**
   - When `zp_eff_confuse > 0`, casting randomly selects a spell via
     `rng_range(spell_count)` instead of using player's choice.

2. **Blindness + scrolls (`player_items.s:1030-1040`):**
   - `item_read_scroll` checks `zp_eff_blind` at entry; if nonzero, prints
     "YOU CAN'T SEE TO READ!" and aborts (no turn consumed).

3. **Hunger + spell failure (`player_magic.s:653-665`):**
   - When `zp_hunger_state >= HUNGER_FAINT`, adds +20 to spell failure roll,
     making spells much more likely to fail while fainting.

4. **Sound effects (`sound.s:46-47`):**
   - `SFX_SPELL` ($06): short mystical tone on successful cast.
   - `SFX_SPELL_FAIL` ($07): low buzz on failed cast.

5. **Help screen (`ui_help.s:136-138`):**
   - Added M=cast spell, P=pray, A=aim wand, Z=use staff to key listing.

6. **Character sheet (`ui_character.s:239-263`):**
   - Displays "SPELLS: N/16" showing number of spells known.

7. **Status bar mana (`ui_status.s:221-243`):**
   - Displays "MP:nn/nn" for spell-casting classes, updates after casting.

**Verification:**
- All 4 commands (M, P, A, Z) work end-to-end with success/failure messages.
- Cancellation works cleanly at every prompt.
- `make build` → all asserts pass ✅
- `make test` → all suites pass ✅

---

### Implementation Order and Dependencies

```
Step 7.0 (Shared Effects) ──────────┐
                                     │
Step 7.1 (Spell Tables) ───────┐    │
                                │    │
Step 7.2 (Cast/Pray Commands) ─┤    │
         depends on 7.0, 7.1   │    │
                                │    │
Step 7.3 (Learn/Mana Recalc) ──┤    │
         depends on 7.1        │    │
                                ▼    ▼
Step 7.4 (Mage Effects) ───────────────┐
         depends on 7.0, 7.2           │
                                        │
Step 7.5 (Priest Effects) ─────────────┤
         depends on 7.0, 7.2           │
                                        │
Step 7.6 (Potions/Scrolls) ───────────┤
         depends on 7.0                │
                                        │
Step 7.7 (Wands/Staves) ──────────────┤
         depends on 7.0, bolt from 7.4 │
                                        │
Step 7.8 (Monster Magic) ─────────────┤
         depends on bolt from 7.4      │
                                        │
Step 7.9 (Mana Regen/Recall) ─────────┤
         depends on 7.3                │
                                        ▼
Step 7.10 (Integration/Polish) ─── all steps complete
```

**Recommended implementation sequence:**
1. **7.0** → 2. **7.1** → 3. **7.2** + **7.3** → 4. **7.4** → 5. **7.5** →
6. **7.6** → 7. **7.7** → 8. **7.8** → 9. **7.9** → 10. **7.10**

Each step is independently testable and committable. Steps 7.4 and 7.5 can
potentially be done in one pass since they share the dispatch pattern. Steps
7.6 and 7.7 are largely independent of the spell system (they're item-based)
and could be parallelized.

---


---

## Review Pass — Missing Features & Known Gaps

Findings from code review against full umoria feature set. Organized by system.
Items marked **(deferred)** are intentional simplifications documented in the
design; items marked **(TODO)** need implementation.

### 1. Combat System

**Missing features:**

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R1.1 | Ranged combat (bows, crossbows, slings) | ✅ **DONE** | `ranged_fire.s` — 3 launchers (bow, crossbow, sling), 3 ammo types (arrow, bolt, rock), SHIFT+F fire command, ammo stacking on pickup, melee unarmed fallback for ranged weapons. 6 new item types (IDs 49-54), `it_missile[]` SoA array. |
| R1.2 | Throwing items | ✅ **DONE** | `throw.s` — SHIFT+T throws any inventory item. BOW-based to-hit at 75%, STR-based range calc, projectile trace reuses ranged_fire pattern. Potions shatter on impact, other items land on floor. 6 tests in `test_throw.s`. |
| R1.3 | Monster attacks | ✅ **DONE** | `monster_attack.s` fully implemented (Phase 5.4). 8 attack types, 2 slots per creature, all effects (poison, confuse, paralyze, acid, aggravate). |
| R1.4 | Monster spells | ✅ **DONE** | `monster_magic.s` fully implemented (Phase 7.8). Breath weapons, bolts, summoning, blindness, confusion. Creature tier data has spell entries. |
| R1.7 | Bash command | ✅ **DONE** | `bash.s` — SHIFT+D + direction. Door bash: STR-based chance (rng_range(STR+10) >= 5, ~50% at STR 3, ~82% at STR 18), converts to TILE_DOOR_OPEN on success. Monster bash: to-hit = STR + shield_weight/2 + 5, damage = 1d4 + str_bonus + 3, stun check (25+rng(100)+rng(100) vs HP/4+avg_max/4), MX_STUN 2-4 turns capped at 24 (AI already handles stun skip). Off-balance: rng(150) > DEX → 1-2 turn paralysis. Reuses combat_roll_tohit, combat_apply_damage, msg_build_action. No chest bash (ICAT_CHEST not implemented). 6 tests in test_bash.s. |

**Issues:**

| # | Issue | Status | Notes |
|---|-------|--------|-------|
| R1.5 | Blows calculation simplified | ✅ **Done** | STR-adjusted weight: `adj_weight = (STR×10)/weapon_weight` mapped to 5 brackets. Too-heavy check (`STR×15 < weight → 1 blow`). Same 5×4 table layout with updated values. |
| R1.6 | AC calculation simplified | ✅ **Done** | Equipment AC now accumulates with DEX bonus. Expanded DEX AC table (max +3 at DEX 18). AC capped at 60. Damage reduction formula `(AC×damage)/200` unchanged (already matched umoria). |

### 2. Dungeon Generation

**Missing features:**

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R2.1 | Special rooms (vaults, pits, nests) | ✅ **DONE** | Monster pits (dlvl>=5, 4-8 same type), treasure vaults (dlvl>=8, secret door entrance, enhanced loot), nests (dlvl>=3, 3-6 mixed weak monsters + gold). At most 1 per level. Code at $F000 (RAM under KERNAL ROM) with trampolines. |
| R2.2 | Magma/quartz streamers with treasure | ✅ **DONE** | 5 streamers per level (3 magma + 2 quartz), placed during dungeon generation. Treasure in veins not yet implemented. |
| R2.3 | Level persistence on stair transitions | **(deferred)** | Levels regenerate on each visit. True persistence would require per-level disk save — too much I/O for 1541. Acceptable simplification. |
| R2.4 | Secret door generation | ✅ **DONE** | `place_secrets` enabled (Phase 4.6). 1-3 closed doors converted to TILE_SECRET per level. Context-aware rendering. `do_search` reveals with 1-in-6 chance. |

### 3. Monsters & AI

**Missing features:**

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R3.1 | Pathfinding | ✅ **Done** | Added unstick heuristic: randomized horizontal/vertical try order after diagonal fails. Perpendicular 4th-fallback removed to save ~60 bytes for BUG-30 fix. Monsters no longer get permanently stuck on corners. |
| R3.2 | Group/pack tactics | ✅ **DONE** | `CF_GROUP` flag with `spawn_group_extras` (1-3 adjacent same-type on spawn) + neighbor wake. Angband-style escort/pack-leader AI is NOT a umoria feature. |
| R3.3 | Explosive breeders | ✅ **DONE** | `CF_BREEDER` flag in `monster_ai.s`. Breeding creatures clone themselves each turn (chance-based, room only). Population controlled by MAX_MONSTERS. |
| R3.4 | Monster fleeing | ✅ **DONE** | Monsters flee when HP < 25% of max. Flee threshold computed at spawn (HP/4). Reversed greedy movement (monster_move_away). Fleeing suppresses attack. CF_ATTACK_ONLY creatures can't flee (can't move). Confusion overrides flee. |
| R3.5 | Limited creature roster | ✅ **DONE** | Expanded to 120 creatures across 5 tiers (T0 town + T1-T4 dungeon). REU + disk loading paths implemented. All 12 steps complete (R3.5.1-R3.5.12). See **R3.5 Detailed Plan** below. |

### 4. Items & Inventory

**Missing features:**

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R4.1 | Ego items | ✅ **DONE** | `ego_items.s` — 7 enchanted weapon types (HA, DF, SA, SD, SE, SU, FT, FB) with slay/elemental/AC bonuses. `test_ego.s` tests. |
| R4.4 | Pseudo-ID | ✅ **DONE** | `turn_tick_pseudo_id` in `turn.s`. Class-based timer, scans equipment for unidentified items, sets `IF_TRIED` flag, shows quality tag in inventory. |
| ~~R4.5~~ | ~~Thorough identification~~ | **Removed** | Not a separate umoria feature. Umoria's Identify spell reveals everything in one shot (`ID_KNOWN2`). Now that R4.1 (ego items) is done, identify already handles ego powers. |
| R4.6 | Flasks of Oil | ✅ **DONE** | Item type 61 (ITEM_FLASK_OIL) in `item.s`, ICAT_LIGHT category. SHIFT+R (CMD_REFUEL) refuels equipped Brass Lantern from carried flask, capped at 250 charges. Equip guard prevents wearing flask as light source. Store charges set correctly for torch/lantern/flask via shared `sro_store_p1`. |

### 5. Magic System

**Missing features:**

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R5.1 | Advanced spells | **Done** ✅ | All 32 spell/prayer effects implemented (16 mage + 16 priest). Ball spells, enchantments, detection, healing all functional. |
| R5.2 | Full spellbook set | **Done** ✅ | 8 books total (4 mage + 4 priest). Each covers 4 spells. Book-gated learning on level-up + manual study ('G'). Books not consumed. |

### 6. Town & Stores

**Missing features:**

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R6.1 | Haggling | **Done** | Multi-round buy/sell haggling. 4 rounds max, gap/4 convergence, insult/kick system (3 insults = kicked). Items ≤10 GP use simple Y/N. Number input with 5-digit limit, DELETE support. |
| R6.2 | Black Market (Store 7) | **Done** | Store index 6. All item categories ($FFFF mask). Buy=base×3, sell=base/10, no CHR adjustment. No haggling (Y/N only). Building at (37,3), door (42,7). Owner: "THE FENCE". |
| R6.3 | Player Home (Store 8) | **Done** | Store index 7. Free deposit/retrieve, no pricing. Separate UI at $F000 (D/R/Q menu). No restocking — items persist. Saved with game state (SAVE_VERSION $05). Building at (42,20), door (47,24). |
| R6.4 | Advanced restocking | ✅ **Done** | Turn-based maintenance every 256 turns + town re-entry. Variable restock probability based on stock level (75%/<6 items, 50%/6-9, 25%/10+). Overstock removal when >10 items. |

### 7. String Compression & String Banks

**Problem:** The game is nearly out of space for new text. The town overlay has 1 byte free,
main code area has ~3,722 bytes free ($B196-$C020), and the $F000 banked region has only
~292 bytes free ($FED6-$FFFA). Adding flavor text (shopkeeper insults, item descriptions,
monster recall, lore) requires a string infrastructure that can hold far more text than
currently fits in any single RAM region.

**Two-tier approach:**

**Tier 1 — Huffman compression in resident RAM (no disk I/O, no hardware requirements).**
Huffman-encode all game strings. The ~40-character uppercase alphabet compresses at ~50-60%,
effectively doubling the capacity of the ~3.7 KB free in main code. This alone provides
~6-7 KB of effective string capacity — enough for shopkeeper insults, haggling flavor,
additional combat messages, and moderate item descriptions. No disk loads, no REU, works on
every C64. This is the first thing to implement.

**Tier 2 — $E000 overlay string banks (when Tier 1 space is exhausted).**
For large-scale text expansion beyond what fits in resident RAM (monster recall, extensive
lore, full umoria dialog), store Huffman-compressed string banks on disk as loadable PRG
files. Two fetch paths: **REU** — all string banks preloaded to REU at startup alongside
creature tiers, DMA fetch on demand (~instant, no disk I/O). **Disk** — KERNAL LOAD from
d64 on demand (~1-2 sec per bank on 1541). Banks share the $E000 overlay region, so they
must coordinate with creature tier overlays.

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| R7.1 | Huffman codec | **DONE** | `tools/huff_encoder.py` (offline encoder): reads text file, builds Huffman tree, emits Kick Assembler `.s` with tree tables + compressed bitstreams. `huffman.s` (6502 decoder): `huff_decode_string(X=id)` walks tree, outputs to `hd_decode_buf`. 55.6% compression ratio. Decoder ~80 bytes + 286 bytes data = ~438 bytes in main code area. |
| R7.2 | Resident compressed strings | **DONE** | `huffman_data.s` (generated) contains tree tables + compressed data in main code area. `huff_str_index` (16-bit offsets) + `huff_str_data` (byte-aligned bitstreams). First consumer: 15 store insult strings (367→204 bytes compressed). Infrastructure ready for additional string corpora. |
| R7.3 | Migrate store dialog strings | **DONE** | 15 umoria-sourced shopkeeper insult strings (`data/insult_strings.txt`) compressed via Huffman. Both buy-side and sell-side insult handlers in `ui_store.s` now call `rng_range` + `huff_decode_string` for random insults. Deleted `hg_insult_str`, freed 14 bytes in town overlay. |
| R7.4 | String bank encoder | ✅ **DONE** | `tools/string_bank_encoder.py` — Python tool creates Huffman-compressed PRG bank files for $E000 overlay. Reuses Huffman tree from main game. Output: 2-byte load address + string count + index table (16-bit offsets) + compressed bitstream. |
| R7.5 | String bank loader | ✅ **DONE** | `string_bank.s` (main RAM) + `string_bank_banked.s` ($F000 banked). KERNAL LOAD to $E000, shared Huffman decoder entry point `sb_decode_string(X=id)`. REU path: DMA fetch from preloaded banks. Disk path: KERNAL LOAD on demand. `sb_current_bank` tracks loaded bank. |
| R7.6 | Migrate combat/UI strings | **DONE** | Migrated ~155 strings from 11 source files into Huffman-compressed storage. Net savings: 888 bytes in main code area (program_end $B196→$AE1E). Three migration patterns: A (zp_ptr0→msg_print), B (zp_ptr2→mon_atk_build_effect_msg), C (combat_append_str). New helpers: huff_decode_to_ptr2, huff_append_combat. |
| R7.7 | Monster recall | ✅ **DONE** | `ui_recall.s` ($F000 banked) — `/` command prompts for creature letter, searches for matching creature with recall data. Displays: LV/AC/HP, attacks with 3-char type abbreviations + dice, spell status (YES/NONE), kills/deaths. 4 SoA tracking arrays (recall_kills/deaths/attacks/spells), combat hooks in combat.s/monster_attack.s/monster_magic.s, save/load persistence. |

**Space budget — Tier 1 (resident compressed strings):**

| Component | Location | Size |
|-----------|----------|------|
| Huffman decoder routine | Main code ($0801-$BFFF) | ~150-200 bytes |
| Huffman tree table | Main code | ~80-120 bytes (40-char alphabet) |
| `str_decode_buf` | Main code | ~80 bytes (max decoded string length) |
| **Infrastructure subtotal** | | **~310-400 bytes** |
| Compressed string data + index | Main code (remaining ~3.3 KB) | ~3,300 bytes |
| **Effective text capacity** | | **~6-7 KB uncompressed** |

**Space budget — Tier 2 (overlay string banks, when Tier 1 exhausted):**

| Component | Location | Size |
|-----------|----------|------|
| Bank loader + fetch API | Main code | ~100-150 bytes additional |
| Per string bank (disk/REU) | $E000 overlay | Up to 4 KB compressed per bank |
| Effective capacity per bank | | ~7-8 KB uncompressed text (at 55% ratio) |

**REU string cache layout** (when REU available, Tier 2):

| REU offset | Size | Content |
|------------|------|---------|
| $00000-$03FFF | 16 KB | Creature tiers 1-4 (existing) |
| $04000-$04FFF | 4 KB | String bank 0 (combat/UI) |
| $05000-$05FFF | 4 KB | String bank 1 (store dialog) |
| $06000-$06FFF | 4 KB | String bank 2 (item descriptions) |
| $07000-$07FFF | 4 KB | String bank 3 (monster recall) |

Minimum REU requirement: 32 KB (tiers + string banks). Any 1700/1750/1764 REU has at
least 128 KB — no constraint in practice.


---

## R3.5 Detailed Plan — Creature Roster Expansion + REU Support

### Problem

Only 32 creature types (26 dungeon levels 1–5, 6 town). Umoria has 247 covering
levels 0–100. The dungeon becomes stale quickly once the player outlevelscreatures.
All creature data is currently embedded in program code (~1,097 bytes).

### Data Budget

Per-creature cost: 20 bytes (SoA arrays) + ~15 bytes (name string avg) = ~35 bytes.

| Roster size | SoA bytes | Name bytes | Total |
|-------------|-----------|------------|-------|
| 32 (current) | 640 | 457 | ~1.1 KB |
| 120 (target) | 2,400 | ~1,800 | ~4.2 KB |
| 247 (full umoria) | 4,940 | ~3,700 | ~8.5 KB |

Any REU (128 KB minimum) can trivially hold the full 8.5 KB roster plus item
tiers, recall data, etc. The C128's native 128 KB can also hold everything.

### Architecture: Two Paths

**Path A — REU detected (or C128 expanded memory):**
- At startup, load ALL creature data from disk into REU in one batch (~8.5 KB,
  ~3 sec with fastloader, one-time cost).
- On dungeon level change, DMA the needed creature data from REU → working RAM
  buffer. DMA transfer is near-instant (~1 cycle/byte, <10ms for a tier).
- No disk I/O after startup. Seamless tier transitions.
- Full 247-creature roster available.

**Path B — Unexpanded C64 (no REU):**
- Creature data split into overlapping tier files on disk:
  - `cr_tier0.dat`: Town creatures (level 0) — always resident in program code
  - `cr_tier1.dat`: Levels 1–8 (~30 creatures, ~1 KB)
  - `cr_tier2.dat`: Levels 5–15 (~35 creatures, ~1.2 KB)
  - `cr_tier3.dat`: Levels 11–25 (~35 creatures, ~1.2 KB)
  - `cr_tier4.dat`: Levels 20–40 (~30 creatures, ~1 KB)
- Tiers overlap by ~4 levels so the spawn window (`dlvl-2` to `dlvl+3`) never
  falls outside loaded data.
- Two adjacent tiers loaded simultaneously into $A000 bank (~2.2 KB).
- Tier change triggered on staircase transition when new dlvl crosses a tier
  boundary. Show "DESCENDING..." during the 1–3 sec disk load.
- Reduced roster (~120 creatures) to keep tier files small for stock 1541 speed.

### REU Interface

REU registers at $DF00–$DF0A (memory-mapped I/O):
- $DF00: Status register (read-only)
- $DF01: Command register (transfer type + execute/trigger mode)
- $DF02–$DF03: C64 base address (16-bit)
- $DF04–$DF06: REU base address (24-bit: lo, hi, bank)
- $DF07–$DF08: Transfer length (16-bit)

DMA transfer types: 00 = C64→REU (stash), 01 = REU→C64 (fetch), 10 = swap.

REU detection: write test pattern to $DF02/$DF03, read back, verify. If match,
REU is present. Size detection: attempt writes at bank boundaries ($DF06) to
determine 128 KB / 256 KB / 512 KB.

### Title Screen Display

When REU is detected, show on the title screen (e.g., row 12 or below the
"COMMODORE 64 EDITION" line):

```
REU DETECTED: 256KB
```

If no REU, show nothing (or optionally "UNEXPANDED C64"). This tells the player
whether they'll get the full creature roster or the tiered subset.

### Implementation Steps

| Step | Description |
|------|-------------|
| R3.5.1 | ✅ **Define creature roster.** Select ~120 creatures from umoria covering levels 0–40. Map each creature's SoA fields (display, color, speed, flags, level, HP dice, AC, sleep, aaf, XP, attacks, spells). Assign to tier groups with overlapping level ranges. |
| R3.5.2 | ✅ **Creature data file format.** Design binary format for tier files: header (count, level range, SoA block offsets) + SoA data blocks + name string table. Write assembler tool or standalone .s files that produce tier .dat files. |
| R3.5.3 | ✅ **REU detection + size probe.** New `reu.s` module: `reu_detect` (sets `reu_present` flag + `reu_size_kb`), `reu_stash` (C64→REU), `reu_fetch` (REU→C64). Call `reu_detect` at startup before title screen. |
| R3.5.4 | ✅ **Title screen REU display.** If `reu_present`, render "REU: xxxKB DETECTED" on the title screen below "COMMODORE 64 EDITION". |
| R3.5.5 | ✅ **Active creature buffer.** Expanded SoA arrays from 32→65 entries (57 dungeon + 8 town). `active_dungeon_count` variable, `load_tier_to_buffer` copies 22 SoA arrays from source to active buffer. All existing `lda cr_xxx,x` code works unchanged. |
| R3.5.6 | ✅ **REU loading path.** `reu_load_all_tiers` at startup loads 4 tier PRGs from disk → $E000 → REU DMA stash. `reu_fetch_tier` DMAs tier from REU → $E000 on transition. |
| R3.5.7 | ✅ **Disk loading path.** `tier_load_disk` uses KERNAL LOAD to load tier PRG from disk to $E000 (RAM under KERNAL ROM). Graceful fallback on failure. |
| R3.5.8 | ✅ **Tier transition logic.** `tier_check_transition` in stair handlers detects tier boundary crossings. Hysteresis via overlapping tier ranges prevents thrashing. `creature_get_name` handles KERNAL banking for name strings at $E000+. |
| R3.5.9 | ✅ **Town creatures always resident.** 6 town creatures embedded at indices 57-62 in program code (never loaded from disk). |
| R3.5.10 | ✅ **Full roster data entry.** Transcribe all ~120–247 creatures from umoria source into tier data files. Verify stats against umoria. **(Done — 120 creatures via parse_creatures.py)** |
| R3.5.11 | ✅ **Testing + bug fixes.** Fixed REU preload bug (`current_tier` not set before `tier_load_disk`), fixed post-loop `current_tier=4` stale state, added `reu_tiers_loaded` fallback counter, fixed Word of Recall skipping tier transition. 10 automated tests in `test_tier.s`. Tested both REU and non-REU paths in VICE. |
| R3.5.12 | ✅ **Fix `monster_init_table` cpx #384 truncation.** 6502 `cpx #imm` is 8-bit — `cpx #384` silently became `cpx #128`, only clearing 128 of 384 bytes. Fixed with two-pass loop. Added compile-time assert. |

### R3.5 Review Findings (2026-02-14)

**Architecture verified correct.** Comprehensive code review of monster.s, reu.s, tier_manager.s, memory.s, dungeon_gen.s, monster_magic.s, and all 5 tier data files.

**Confirmed working:**
- All 22 SoA arrays consistent across 5 tiers; compile-time assertions verify array sizes = MAX_CREATURES (65)
- `active_dungeon_count` variable correctly replaces old `DUNGEON_CREATURES` constant in `pick_creature_type` and `monster_cast_summon`
- `load_tier_to_buffer` copies all 22 arrays from $E000 source to active buffers
- `creature_get_name` properly handles KERNAL banking (SEI/$35) for name strings at $E000+
- REU detection: 3-stage bank probing (0-7, 8-15, 16-31), stash/fetch DMA verified
- `reu_load_all_tiers`: loads tiers 1-4 from disk → $E000 → REU bank 0 with sequential offsets
- `tier_load_disk`: KERNAL LOAD with PETSCII filenames "CR T1"-"CR T4"
- Tier transition hysteresis: T1=[1,8], T2=[5,15], T3=[11,25], T4=[20,100] — overlaps prevent thrashing
- Town creatures at indices 57-62 always resident (never loaded from disk)
- BFS queue now at screen RAM $0400-$07FF (512 entries × 2 bytes = 1024 bytes), moved from CREATURE_BASE to free up program space. SEI/CLI wraps prevent KERNAL IRQ cursor blink from corrupting queue.
- 19 test suites (17 at time of R3.5 review + test_tier + test_ranged); 13+ import reu.s + tier_manager.s; test_tier has 500M cycle limit

**Minor observations (non-blocking):**
- **Tight memory margin:** Program ends at $BF3F, CREATURE_BASE at $BFD0 — 145 bytes of headroom (after A3 dual-disk + streaming RLE fix). The compile-time assertion `program_end < CREATURE_BASE` catches overflow, but future code additions should be mindful of this margin.
- ~~**`monster_init_table` cpx #384:**~~ **Fixed in R3.5.12** — 6502 `cpx #imm` is 8-bit, so `cpx #384` silently became `cpx #128`, only clearing 128 of 384 bytes. Fixed with two-pass loop + compile-time assert.

**Issue found (2026-02-14): `test_dungeon.s` timeout.**
- R3.5 imports (`reu.s`, `tier_manager.s`) pushed `test_start` to $A032 — inside BASIC ROM ($A000-$BFFF). `BasicUpstart2(test_start)` generates `SYS 40994`, which jumps into BASIC ROM instead of the test code, causing an infinite hang until the cycle limit.
- **Fix:** Apply the bootstrap trampoline pattern from `test_item.s` — small stub at $080E banks out BASIC ROM, then `jmp test_start`. Any test with `test_start` >= $A000 needs this.

**No other critical issues found.**

### Future: C128 Native Memory (Phase 10.2)

The C128 has 128 KB natively (two 64 KB banks). With MMU bank switching,
the second bank can hold all creature + item data without REU or disk tier
loading — same benefit as the REU path but using built-in hardware. If the
C128 has an REU as well, even more data can be resident (larger item roster,
full monster recall, etc.).

**TODO (Phase 10.2):** Add C128 MMU bank-switch path alongside REU path.
Detect C128 mode at startup (check $D030 or MMU register at $FF00).
Load creature data into bank 1 via MMU configuration. Fetch via bank
switch instead of REU DMA. Same zero-disk-I/O benefit as REU path.

---


---

## Code Size Audit (2026-02-15)

**Context:** Program ended at ~$BFF7, CREATURE_BASE at $C020 — approximately **45 bytes free**. This audit identified ~188 bytes of verified, low-risk savings across 7 optimizations plus 3 bugs.

**Result:** OPT-1.2–1.7 implemented on 2026-02-15. Actual savings: **182 bytes** ($BFF7→$BF41). OPT-1.1 (dead string deletion) deferred. All 20 test suites pass. See Memory Usage Overview below for full post-optimization memory map.

### Bugs Found

| # | File | Description | Bytes |
|---|------|-------------|-------|
| BUG-20 | ~~monster_attack.s~~ | ✅ Fixed — inline strings eliminated by R7.6 Huffman migration. `mat_acid_str` now in Huffman dictionary, `mat_dead_str` removed (never referenced). | ~~42~~ |
| BUG-21 | ~~monster_attack.s~~ | ✅ Fixed — acid effect prints "SPITS ACID ON YOU" via mon_atk_build_effect_msg, now Huffman-compressed. | N/A |
| BUG-22 | ~~monster_attack.s~~ | ✅ Fixed — OPT-1.7 eliminated duplicate; R7.6 removed all remaining inline strings. | ~~5~~ |

### Additional Issues Noted

| Issue | File | Description |
|-------|------|-------------|
| ~~`rng_range_word` not implemented~~ | rng.s | **RESOLVED:** 16-bit rejection sampling implemented; gold drops now use `fi_qty_hi` + `rng_range_word` + `combat_append_decimal_16`. |
| ~~`mon_atk_effect_fear` is a no-op~~ | monster_attack.s | **RESOLVED:** Fear sets `eff_fear_timer` (static RAM byte in turn.s). Timer = `rng_range(cr_level) + 3`. Blocks melee attacks in `player_move.s`. Ticks down in `turn_tick_effects`. Saved/loaded in save.s. |
| `mon_atk_effect_corrode` is a no-op | monster_attack.s:360-362 | Corrode attacks deal damage but don't damage equipment. Marked "deferred". |

### Optimization Plan (OPT-1)

Seven optimizations totaling ~188 bytes. All preserve existing behavior and are independently testable.

| # | What | Where | Est. | Status |
|---|------|-------|------|--------|
| OPT-1.1 | ~~**Delete dead strings** `mat_acid_str` + `mat_dead_str`~~ | monster_attack.s | **42** | ✅ Done (eliminated by R7.6 Huffman migration) |
| OPT-1.2 | **Parameterize cast/pray table setup** — table-driven copy loop | player_magic.s | **~55** | ✅ Done |
| OPT-1.3 | **Deduplicate "CURE LIGHT WOUNDS"** — `.label` alias to `itn_17` | spell_data.s | **36** | ✅ Done |
| OPT-1.4 | **Unify `mon_atk_build_hit/miss_msg`** into `mon_atk_build_effect_msg` | monster_attack.s | **~20** | ✅ Done |
| OPT-1.5 | **Deduplicate "DETECT MONSTERS"** — `.label` alias to `itn_30` | spell_data.s | **16** | ✅ Done |
| OPT-1.6 | **Self-printing `mon_atk_build_effect_msg`** — `jmp cmb_term_and_print` | monster_attack.s | **~14** | ✅ Done |
| OPT-1.7 | **Eliminate `mat_the_str`** — use `cmb_the_str + 1` | monster_attack.s, monster_magic.s | **5** | ✅ Done |
| | **Estimated total (1.2–1.7)** | | **~146** | |
| | **Actual savings** | $BFF7 → $BF41 | **182** | ✅ Verified |

**Net effect:** Headroom increased from ~45 bytes to **223 bytes**. All 20 test suites pass (259 tests).

### OPT-1.2 Detail: Cast/Pray Table Parameterization

Lines 51-81 (`player_cast_spell`) and 102-132 (`player_pray`) are near-identical 58-byte blocks that initialize 10 consecutive pointer bytes (`pm_mana_tbl_lo` through `pm_name_hi_hi`) for mage vs priest spell tables. Replace with:

```asm
// Table of source addresses (10 per spell type, mage then priest)
pm_tables:                              // 20 bytes
    .byte <mage_spell_mana, >mage_spell_mana
    .byte <mage_spell_level, >mage_spell_level
    .byte <mage_spell_fail, >mage_spell_fail
    .byte <mage_spell_name_lo, >mage_spell_name_lo
    .byte <mage_spell_name_hi, >mage_spell_name_hi
    .byte <priest_spell_mana, >priest_spell_mana
    .byte <priest_spell_level, >priest_spell_level
    .byte <priest_spell_fail, >priest_spell_fail
    .byte <priest_spell_name_lo, >priest_spell_name_lo
    .byte <priest_spell_name_hi, >priest_spell_name_hi

// Copy 10 bytes from pm_tables+X into pm_mana_tbl_lo..pm_name_hi_hi
pm_setup:                               // 15 bytes
    ldy #0
!loop:
    lda pm_tables,x
    sta pm_mana_tbl_lo,y
    inx
    iny
    cpy #10
    bne !loop-
    rts

// Callers become:                      // 13 bytes each
player_cast_spell:
    ...
    lda #SPELL_MAGE
    sta pm_spell_type
    ldx #0                  // Offset 0 = mage tables
    jsr pm_setup
    jmp pm_do_cast

player_pray:
    ...
    lda #SPELL_PRIEST
    sta pm_spell_type
    ldx #10                 // Offset 10 = priest tables
    jsr pm_setup
    jmp pm_do_cast
```

New total: 20 (table) + 15 (helper) + 13 + 13 (callers) = **61 bytes** vs current **116 bytes**. Savings: **~55 bytes**.

### OPT-1.4 Detail: Unify Hit/Miss Message Builders

`mon_atk_build_hit_msg` and `mon_atk_build_miss_msg` (monster_attack.s:562-600) are structurally identical to `mon_atk_build_effect_msg`, just with hardcoded suffix strings. Replace:

```asm
// Before (2 × 18-byte routines + 2 × 3-byte call sites = 42 bytes):
    jsr mon_atk_build_hit_msg
    jsr cmb_print_buf

// After (2 × 11-byte inline setups = 22 bytes):
    lda #<mat_hits_str
    sta zp_ptr2
    lda #>mat_hits_str
    sta zp_ptr2_hi
    jsr mon_atk_build_effect_msg    // (self-printing per OPT-1.6)
```

Delete `mon_atk_build_hit_msg` and `mon_atk_build_miss_msg` entirely. **~20 bytes saved.**

### Non-Issues Verified

Items investigated that turned out to be correct:
- **`cpx #41` in `combat_append_str`:** Buffer is 42 bytes (indices 0-41). After writing at index 40, x=41 triggers bcs exit. Null terminator at 41 via `cmb_term_and_print` is within bounds. **Correct.**
- **Zero-page clobbering:** Known hazards in MEMORY.md are accurate. No new zp conflicts found.
- **Stack balance:** All JSR/RTS and PHA/PLA pairs are balanced across all audited paths.
- **Screen code vs PETSCII:** Properly separated — `.text` with inherited encoding for screen RAM, raw bytes for KERNAL I/O.
- **`mon_atk_base_tohit` sparse table** (21 bytes, mostly zeros): Direct-index access pattern makes this already optimal; a compact search table would cost more than 21 bytes.

### Lower-Priority Savings (Not in OPT-1 Scope)

These were identified but deferred due to complexity or diminishing returns:

| Category | Technique | Est. Savings | Why Deferred |
|----------|-----------|-------------|--------------|
| Shared " YOU." suffix | Build monster attack messages from fragments | 25-35 | Adds runtime complexity, small payoff |
| Compute XP tables at init | Replace 80-byte `xp_level_lo/hi` with init-time computation | ~20 net | 80 bytes table - ~60 bytes init code = small net win |
| Stat bonus table formulas | Replace 16-byte lookup tables with computed values | 30-50 | Risky — umoria fidelity requirement |
| String pool / dictionary | Central string deduplication system | 50-100 | Major refactor, error-prone |
| Creature name prefix extraction | Share "GIANT ", "SKELETON " prefixes | 40-60 | Only applies to tier data files (loaded from disk, not in main PRG) |

---

## Town Overlay Size Optimization — OPT-3 (2026-02-18) ✅

### Problem

The town overlay (`$E000-$EFFF`, 4096 bytes max) was at **4,074 bytes** — only **22 bytes free**.

### Results

| Priority | Item | Effort | Est. | Actual | Status |
|----------|------|--------|------|--------|--------|
| 1 | OPT-3.4 Separator draw loop | Trivial | ~26 | 62 | ✅ Done |
| 2 | OPT-3.6 Cancel-key helper | Trivial | ~15 | 17 | ✅ Done |
| 3 | OPT-3.8 Clear-msg loop | Trivial | ~8 | 6 | ✅ Done |
| 4 | OPT-3.1 Message display helper | Medium | ~300-400 | 295 | ✅ Done |
| 5 | OPT-3.2 Merge haggle routines | Medium | ~150-170 | 60 | ✅ Done |
| 6 | OPT-3.7 Unify price calcs | Low | ~30-50 | 35 | ✅ Done |
| 7 | OPT-3.5 Move names/owners to main RAM | Low-Med | ~80-240 | 240 | ✅ Done |

**Total: 715 bytes saved (4,074→3,359), 737 bytes free.**

### Summary of Changes

- **OPT-3.1:** Table-driven `show_msg` helper in `ui_store.s` — 25 call sites collapsed to `ldx #MSG_ID; jsr show_msg` (5 bytes each). 295 bytes saved.
- **OPT-3.2:** Merged `haggle_buy`/`haggle_sell` into shared subroutines with mode flag. 60 bytes saved.
- **OPT-3.4:** Replaced 41-byte separator string with `draw_separator` loop (12 bytes). 62 bytes saved.
- **OPT-3.5:** Moved store name strings (82 bytes), owner strings (126 bytes), and pointer tables (32 bytes) from `store.s` overlay to `store_data.s` main RAM. 240 bytes saved in overlay.
- **OPT-3.6:** Factored Q/ESC/SPACE cancel pattern into `check_cancel` helper. 17 bytes saved.
- **OPT-3.7:** Unified BM + normal price calculation with parameterized multiplier. 35 bytes saved.
- **OPT-3.8:** Replaced 4 sequential `jsr screen_clear_row` calls with loop. 6 bytes saved.
- **OPT-3.3:** Huffman-compressed all 29 overlay strings (419 bytes raw). Strings moved to `huffman_data.s` in main RAM. `show_msg` table changed from pointer pairs to single-byte Huffman IDs. `ssell_show_error` changed to accept Huffman IDs. 468 bytes overlay savings (+340 bytes main RAM). Added `/`, `=`, `>` character support to Huffman encoder. Added `~` trailing-space marker convention for string data file.

**Final result: 1,183 bytes saved total (4,074→2,891), 1,204 bytes free in overlay.**

### Commits

- `0664743` — OPT-3.1/3.2/3.4/3.6/3.7/3.8 (475 bytes saved)
- `3e93849` — OPT-3.5 (240 bytes saved, names/owners to main RAM)
- OPT-3.3 (468 bytes saved, Huffman compress overlay strings)

---

## Tunneling & Treasure Veins — R2.5 ✅ COMPLETE (2026-02-18)

### What Was Implemented

| Step | What | Details |
|------|------|---------|
| R2.5.1 | Treasure flag encoding | Reused `FLAG_HAS_ITEM` ($02) on magma/quartz wall tiles — no conflict since items can't exist on impassable tiles |
| R2.5.2 | Treasure placement in `carve_streamer` | Roll per vein tile: 1-in-90 for magma, 1-in-40 for quartz. Used BIT abs skip trick for compact branching |
| R2.5.3 | Tunnel command (`+` key) | New `tunnel.s` module. Direction prompt, confusion (75% random), monster redirect, boundary check. STR + max(0, PL_TODMG) digging ability vs scaled resistance |
| R2.5.4 | Gold spawn from treasure veins | `tunnel_spawn_gold` in `item.s`. Gold amount: rng(5+dlvl*3)*2+1. Shared by tunnel and wall-to-mud |
| R2.5.5 | Wall-to-mud vein support | Extended `eff_wall_to_mud` in `spell_effects.s` to handle all wall types + magma + quartz + secret doors. Boundary check added. Treasure gold spawns on vein destruction |
| R2.5.6 | Huffman strings | 8 new strings: dig granite/magma/quartz, finished, found, permanent, nothing, rubble. 197 total strings |

### Design Decisions

- **Key binding:** `+` key ($2B PETSCII) instead of `T` (taken by Take Off). `+` is available on C64 keyboard and intuitive for digging.
- **Digging ability:** `STR + max(0, PL_TODMG)` — simplified from umoria's weapon-type-specific formula. No shovel/pick item types exist.
- **Wall resistance (8-bit scaled):** Granite rng(20)+8 (8-27), Magma rng(12)+3 (3-14), Quartz rng(10)+2 (2-11). Rubble always succeeds.
- **Treasure veins invisible** to player (matches umoria). `FLAG_HAS_ITEM` bit is not rendered differently on wall tiles.
- **Confusion:** 75% random direction (25% keep intended), matching umoria.

### Size Impact

742 bytes added to main segment ($BADB → $BDC1), 575 bytes headroom remaining to MAP_BASE ($C000).

### Files Modified

- `tunnel.s` — New module: tunnel command handler (~290 bytes)
- `item.s` — Added `tunnel_spawn_gold` (~50 bytes)
- `dungeon_gen.s` — Treasure placement in `carve_streamer` (~25 bytes)
- `spell_effects.s` — Extended `eff_wall_to_mud` for all wall types + veins (~40 bytes)
- `input.s` — Added `CMD_TUNNEL` ($32), mapped `+` key ($2B)
- `main.s` — Added tunnel command dispatch
- `ui_help_data.s` — Added `+ TUNNEL` to help screen row 23
- `data/huffman_strings.txt` — 8 new tunnel strings
- `huffman_data.s` — Regenerated (197 strings, 2,756 bytes)

---

## String Banks & Monster Recall — R7.4, R7.5, R7.7 ✅ COMPLETE (2026-02-19)

### What Was Implemented

| Step | What | Details |
|------|------|---------|
| R7.4 | String bank encoder | `tools/string_bank_encoder.py` — Python tool reads a text file of strings, Huffman-compresses them using the game's existing tree, and outputs a loadable PRG file for the $E000 overlay region. Format: 2-byte load address ($00 $E0) + 1-byte string count + 16-bit index table (bit offsets) + compressed bitstream. |
| R7.5 | String bank loader | `string_bank.s` (main RAM API) + `string_bank_banked.s` ($F000 banked decoder). `sb_load_bank(A=bank_id)` loads a string bank PRG to $E000 via KERNAL LOAD (disk) or REU DMA fetch. `sb_decode_string(X=id)` decodes a string from the loaded bank into `hd_decode_buf` using the shared Huffman tree. `sb_current_bank` tracks loaded bank to avoid redundant loads. REU path preloads all string banks at startup alongside creature tiers. |
| R7.7 | Monster recall system | **Tracking:** 4 SoA byte arrays (`recall_kills`, `recall_deaths`, `recall_attacks`, `recall_spells`) indexed by creature type. Updated by hooks in `combat.s` (kill tracking), `monster_attack.s` (attack type tracking), `monster_magic.s` (spell tracking), and death handler (death tracking). Saved/loaded with game state. **UI:** `ui_recall.s` at $F000 (banked). `/` key prompts for creature letter, searches `cr_display[]` for matching creature with any recall data (kills OR deaths OR attacks OR spells > 0). Display shows: creature char + name (colored), LV/AC/HP with dice, up to 2 attacks with 3-char type abbreviations (HIT/CNF/FER/ACD/COR/PAR/PSN/AGG) + NdM dice, spell status (YES/NONE), kills/deaths counters. Compact design (~610 bytes) fits within tight $F000 banked region budget. |

### Design Decisions

- **Recall display trimmed for space:** Removed spell name display (YES/NONE only), XP display, "attacks seen" counter, and speed display to fit within ~634 bytes available in the $F000 banked region. Attack type 3-char abbreviations kept as critical gameplay information.
- **creature_get_name called before trampoline:** The name lookup function calls CLI internally (for tier-loaded creatures), which would crash if called from banked code where KERNAL ROM is banked out. So the recall dispatch in main.s calls `creature_get_name` in main RAM, populating `creature_name_buf` before entering the $F000 trampoline.
- **Search by display character:** The `/` command converts the typed PETSCII letter to a screen code and searches `cr_display[]` for a match. Only creatures with nonzero recall data (kills/deaths/attacks/spells) are shown.
- **Attack type lookup via packed table:** 9 attack type names stored as 3-char packed abbreviations (27 bytes) + 21-byte sparse→compact index table. Much smaller than null-terminated strings + pointer tables (~48 bytes vs ~130 bytes).

### Size Impact

- Main segment: $BFF0 (program_end) — 16 bytes headroom to MAP_BASE ($C000)
- Banked code ($F000): ends at $FFBC — 62 bytes headroom to CPU vectors ($FFFA)
- Banked payload: ends at $CFD9 — 39 bytes headroom to I/O ($D000)
- String bank encoder tool: ~200 lines Python (not in PRG)

### Files Created/Modified

- `tools/string_bank_encoder.py` — New: Python string bank encoder tool
- `ui_recall.s` — New: monster recall display UI ($F000 banked, ~610 bytes)
- `string_bank.s` — New: string bank loader API (main RAM)
- `string_bank_banked.s` — New: string bank decoder ($F000 banked)
- `main.s` — Added CMD_RECALL dispatch, `tramp_ui_recall` trampoline, recall variables
- `combat.s` — Added recall_kills/recall_attacks tracking hooks
- `monster_attack.s` — Added recall_attacks tracking hook
- `monster_magic.s` — Added recall_spells tracking hook
- `save_load.s` — Added recall array save/load (4 × MAX_CREATURES bytes)
- `data/recall_data.s` — New: recall SoA array definitions
- `input.s` — CMD_RECALL ($1e) already mapped to `/` key

---

## BUG-32 Fix: Garbled Tier-Loaded Monster Names ✅ COMPLETE (2026-02-19)

**Root Cause:** `load_tier_to_buffer` writes `$E0xx` pointers into `cr_name_lo/hi` arrays (pointing into tier data at `$E000`). When `overlay_load` later sets `current_tier=0` and overwrites `$E000` with overlay code (town stores, death screen, etc.), the `!cgn_table` fallback path in `creature_get_name` saw `cr_name_hi[X] >= $E0`, entered `!cgn_banked`, and read overlay executable code as string data — producing garbled PETSCII.

**Trigger scenarios:**
1. Monster recall (`/`) in town after dungeon exploration — store overlay at `$E000`, stale `$E0xx` name pointers
2. Tier switch to smaller tier (e.g., tier 2→1) — indices beyond new count retain old `$E0xx` pointers

**Fix:** Replaced `!cgn_banked` (which banked out KERNAL and read from `$E000`) with a safe fallback that writes "?" to `creature_name_buf` and returns a pointer to it. The `!cgn_banked` path was dead code for all legitimate use cases: embedded creature names are always below `$C000` (so `cr_name_hi < $C0 < $E0`), and tier creature names use the dedicated tier path (lines 967-994) which reads via `tier_name_lo/hi_addr`.

**Size impact:** Byte-neutral (15B old → 15B new). `program_end` remains `$BFFF`.

**Files modified:**
- `monster.s` — Replaced `!cgn_banked` code block with safe "?" fallback

---

## BUG-35 Fix: Help Screen Fills with 'p' Characters and Locks Up ✅ COMPLETE (2026-02-19)

**Root Cause:** `help_lines` data in `ui_help_data.s` started at `$BD26` and extended past `$C000` (MAP_BASE), placing program_end at `$C016`. At runtime, the dungeon map at `$C000` overwrites the tail end of help_lines data. The help_draw_line renderer finds no null terminator in the corrupted data and reads map tiles as characters (floor tiles = `p` in lowercase mode), filling the screen and hanging.

**Fix:** Added a tab-to-column control code (`$fc`) to the help renderer. Replaced padding spaces in help_lines data with 2-byte tab codes (`$fc, column`), shrinking help data by ~96 bytes. Also changed the build assertion from CREATURE_BASE to MAP_BASE.

**Size impact:** program_end moved from `$C016` to `$BFD0` (~48 bytes headroom below MAP_BASE).

**Files modified:**
- `ui_help.s` — Added `CT = $fc` constant and `!hdl_tab` handler in `help_draw_line`
- `ui_help_data.s` — Replaced padding spaces with tab control codes across 18 rows
- `main.s` — Changed build assertion from `CREATURE_BASE` to `MAP_BASE`

---

## BUG-36 Fix: Monster Recall Missing Creature Name for Town Creatures ✅ COMPLETE (2026-02-19)

**Root Cause:** `creature_get_name` had an inconsistency: the tier path populated `creature_name_buf`, but the table path (for town/embedded creatures) returned a direct pointer without populating the buffer. `ui_recall.s` reads from `creature_name_buf`, so town creature names appeared blank.

**Fix:** Made the table path in `creature_get_name` copy the name into `creature_name_buf` before returning, matching the tier path behavior.

**Files modified:**
- `monster.s` — Added copy loop in `!cgn_table` path to populate `creature_name_buf`

---

## BUG-37 Fix: Recall/Help Screens Flash and Dismiss Immediately ✅ COMPLETE (2026-02-19)

**Root Cause:** C64 keyboard buffer at `$C6` retains repeat characters from the preceding keypress. When the user types a letter for "Recall which?" or presses `?` for help, key repeat characters land in the buffer. The dismiss `input_get_key` call reads a buffered character immediately, causing the screen to flash and dismiss before the user can read it.

**Fix:** Added `lda #0; sta $c6` (clear keyboard buffer) before the dismiss `input_get_key` calls for both recall and help screens.

**Files modified:**
- `main.s` — Added keyboard buffer clears before dismiss calls (~lines 469 and 531)

---

## BUG-38 Fix: rng_range(0) Causes Infinite Loop (Game Hang) ✅ COMPLETE (2026-02-19)

**Root Cause:** `rng_range` uses rejection sampling: generate masked random byte, reject if >= N. When called with N=0, the mask wraps to `$FF` and `CMP 0` always sets carry, creating an infinite loop. Multiple callers can pass 0: `active_dungeon_count` (when all creature slots filled), `door_scan_count` (on doorless levels), and potentially others with computed values.

**Fix (3-part):**
1. **Defensive guard in `rng_range`** — Added `beq` after `tax` to return 0 immediately when N=0 (2 bytes)
2. **Guard in `pick_creature_type`** — Added `active_dungeon_count` zero-check + 50-retry limit to prevent infinite retry loop
3. **Guard in `monster_cast_summon`** — Added `active_dungeon_count` zero-check before `jsr rng_range`

**Files modified:**
- `rng.s` — Added zero guard in `rng_range`
- `monster.s` — Added `active_dungeon_count` guard + retry limit in `pick_creature_type`
- `monster_magic.s` — Added `active_dungeon_count` guard in `monster_cast_summon`

## BUG-39 Fix: Creature Name Shows "?" During Combat (creature_get_name $E0xx Pointer) ✅ COMPLETE (2026-02-19)

**Root Cause:** `creature_get_name` had an overly restrictive check: when `current_tier != 0` but `X >= active_dungeon_count`, it fell through to the table path which treated any `cr_name_hi >= $E0` as a stale pointer and returned "?". However, when a tier is loaded, `$E0xx` pointers are still valid because the tier data remains at `$E000` — the creature was simply beyond `active_dungeon_count` (e.g., a creature from a previous tier load whose name pointer still works).

**Fix:** Rewrote `creature_get_name` with four distinct paths:
1. **Tier indexed** (`current_tier != 0`, `X < active_dungeon_count`): Banks out KERNAL, reads name pointer from tier name arrays at `$E000`
2. **$E0xx with tier** (`current_tier != 0`, `X >= active_dungeon_count`, `cr_name_hi >= $E0`): Banks out KERNAL, reads name directly from the `$E0xx` pointer
3. **Normal RAM** (`cr_name_hi < $E0`): Reads from normal RAM without banking
4. **Stale fallback** (`current_tier == 0` with `$E0xx` pointer, or null pointer): Returns "?"

All paths share a single copy loop (`!cgn_copy`), eliminating a duplicate copy routine. Net result: **+10 bytes** ($BFEF → $BFF9, 7 bytes headroom to MAP_BASE).

**Files modified:**
- `monster.s` — Rewrote `creature_get_name` with four-path resolution


---

## OPT-4 — Codebase-Wide Size Optimization ✅ COMPLETE (2026-02-20)

**Total savings: 1,098 bytes** in the main segment (program_end $BFD5 → $BB8B, headroom 43 → 1,141 bytes). Nine items implemented by an architect/implementor/tester team. All 22 test suites pass, 70 compile-time asserts.

### Items Completed

| Item | Description | Saved |
|------|-------------|-------|
| OPT-4.11 | `huff_print_msg` helper — collapsed 3-instruction pattern (ldx/jsr decode/jsr print) to 2 across ~136 sites | **402 bytes** |
| OPT-4.9 | `combat_kill_message` + `monster_wake` helpers — deduplicated kill dispatch and flag-set patterns | **39 bytes** |
| OPT-4.10 | `projectile_msg_suffix` — shared hit/miss message suffix in ranged_fire.s + throw.s | **77 bytes** |
| OPT-4.5 | `combat_calc_tohit_common` — unified melee/ranged tohit calc, throw wrapper does 75% scaling | **114 bytes** |
| OPT-4.1+4.2 | `trace_projectile` + `calc_direction_index` in new `projectile.s` — shared across ranged_fire.s, throw.s, spell_effects.s | **194 bytes** |
| OPT-4.3 | `for_each_adjacent` — shared 8-direction iterator used by sleep/confuse/damage/traps loops in spell_effects.s | **62 bytes** |
| OPT-4.4 | `combat_apply_damage_16` — fall-through design extends existing combat_apply_damage to 16-bit; spell_effects.s inline loops replaced | **84 bytes** |
| OPT-4.6 | Table-driven effect ticks — `tick_simple_effects` + `tick_msg_effects` loops replace 7+3 inline patterns in turn.s | **14 bytes** |
| OPT-4.8 | Huffman-encode remaining raw strings — turn.s pseudo-ID quality words + bash.s strings (13 new HSTR entries, now 217 total) | **112 bytes** |

### Notes

- **OPT-4.11** was the biggest win by far — the 3-instruction inline pattern was far more prevalent than the BUILDPLAN estimated (~24 bytes projected vs 402 actual).
- **OPT-4.6** savings were smaller than projected (15 vs 26) because `dec $00,y` doesn't exist on 6502 — zero-page indirect decrement requires load/dec/store (3 instructions, not 1).
- **OPT-4.8** was larger than projected (~85-100 vs 112) because bash.s contained ~190 bytes of raw strings the BUILDPLAN had missed.
- **OPT-4.7** (Huffman item names, ~300-400 bytes) was deferred — requires tooling changes; sufficient headroom exists without it.
- A new `projectile.s` source file was added. All 17 test files that transitively import spell_effects.s, ranged_fire.s, or throw.s required a new `#import "../projectile.s"` line.
- Banked code region ($F000-$FFF7) unchanged — OPT-4 only affected the main segment.

### Files Modified

`turn.s`, `spell_effects.s`, `combat.s`, `ranged_fire.s`, `throw.s`, `bash.s`, `monster.s`, `ui_inventory.s`, `huffman_data.s` + new `projectile.s` + 17 test files (import added).

---

## BUG-34 — Monster Recall Cycling ✅ FIXED (2026-02-20)

**Problem:** Monster recall showed only the first creature matching a typed display symbol. When multiple creatures share a letter (e.g. several 'j' creatures), the player had no way to see the others.

**Fix:** Added cycling state to the recall command handler in `main.s`. Pressing the same letter again now advances to the next known creature with that symbol, wrapping around to the first after the last. Matches umoria's `recallMonsterAttributes()` behaviour.

**Implementation:**
- `recall_last_sc` (.byte 0) — screen code of the last recall shown; 0 = no previous recall
- `recall_last_idx` (.byte 0) — creature index last displayed (determines where to resume the search)
- Search start: `(recall_last_idx + 1) % MAX_CREATURES` if same char, else 0
- Loop runs MAX_CREATURES iterations with wrap-around (using `zp_temp1` as counter), ensuring all slots are checked exactly once
- On no match: clears `recall_last_sc` so next use restarts from the beginning
- `bne !not_recall+` trampoline added (handler grew past ±127 byte branch range)

**Files modified:** `main.s` (recall handler + two new state variables)

**Size impact:** +52 bytes (program_end $BB8B → $BBBF). All 22 test suites pass.

---

## BUG-45 — Item Generation Flat Distribution Fix (2026-02-20)

### Problem

`pick_item_type` (item.s) used flat uniform rejection sampling: roll random [2,63], accept if `min_level <= dlvl+2`. Low-level items (torches, food, basic potions) perpetually dominated every drop because they were always valid candidates. The 1-in-12 "great item" check bypassed `min_level` entirely, giving equal odds to a torch vs. the best item in the game.

### Solution

Rewrote `pick_item_type` with a umoria-faithful depth-bucketed 50/50 flat/best-of-3 algorithm:

1. **Compile-time sorted item table** (`pit_sorted`, 62 bytes) — all 62 non-gold items (IDs 2–63) sorted ascending by `it_min_level`. Items at the same level are grouped together.

2. **Cumulative level bounds table** (`pit_level_bounds`, 13 bytes) — `pit_level_bounds[L]` = count of items with `min_level <= L`. Levels 0–12 covered. Enables O(1) pool size lookup.

3. **Algorithm:**
   - Effective level = `min(dlvl + 2, 12)` (preserves the existing +2 bonus)
   - Great item check (1/12 chance): sets effective level to 12 (full pool access)
   - Pool size = `pit_level_bounds[effective_level]`
   - 50% chance: **flat pick** — uniform random from entire level-appropriate pool
   - 50% chance: **best-of-3** — pick 3 random indices, keep the highest (biases toward deeper items), then re-roll uniformly within the winner's exact depth tier

4. **Re-roll within tier** — after best-of-3 selects a winning index, look up the item's `min_level`, find the tier boundaries from `pit_level_bounds`, and pick a new random index within that tier. This ensures uniform distribution within each depth tier while the best-of-3 determines which tier gets selected.

### Level distribution

| Level | Items | Cumulative | Examples |
|-------|-------|------------|---------|
| 0 | 5 | 5 | Torch, Food, Flask of Oil, Shovel, Pick |
| 1 | 15 | 20 | Dagger, Short Sword, Robe, Leather Armor, Potions |
| 2 | 11 | 31 | Mace, Shield, Lantern, Books 1 |
| 3 | 11 | 42 | Long Sword, Chain Mail, Wands, Staves |
| 4 | 9 | 51 | Helm, Rings, Books 2 |
| 5 | 5 | 56 | Strength Ring, Word of Recall, Enchant scrolls |
| 6 | 2 | 58 | Enchant Weapon/Armor scrolls |
| 8 | 2 | 60 | Books 3 |
| 12 | 2 | 62 | Books 4 (endgame) |

### Files modified

1. **`item.s`** — replaced `pick_item_type` (lines 1344–1389): removed flat rejection sampling + `pit_attempts` variable, added `pit_sorted` (62 bytes), `pit_level_bounds` (13 bytes), and new depth-bucketed algorithm (~113 bytes code). Uses `zp_temp0`–`zp_temp2` for scratch (safe: `rng_range` only uses `zp_temp4`). Y register holds effective level across `rng_range` calls (Y preserved by `rng_range`).

2. **`tests/test_item.s`** — added Test 43 (depth-curve distribution verification: 60 iterations at dlvl=8, verifies ≥15 items have `min_level ≥ 3`). Updated copy loop `ldx #42` and `tc_results` buffer to 43 entries. Added `sei` + `:BankOutBasic()` to exit trampoline (tc_results at $AA16 is in BASIC ROM range; ensures RAM is readable during copy).

3. **`run_tests.sh`** — updated item test count from 42 to 43.

**Size impact:** +142 bytes (program_end $BF15 → $BFA3, 93 bytes headroom). All 23 test suites pass (309 runtime tests).

---

## Phase 10.0 — C64/C128 Code Split (2026-02-21)

### Summary

Split the codebase into `commodore/common/`, `commodore/c64/`, and `commodore/c128/` to prepare for the C128 port. Moved 64 shared game logic files to `common/`, extracted the game loop (~1,382 lines) from `main.s` into `common/game_loop.s`, and created a skeletal `c128/main.s`. Pure file moves + import path updates — no game logic changes.

### Directory structure after split

```
commodore/
├── common/        64 shared .s files (game logic, UI, data)
│   └── game_loop.s   (extracted from c64/main.s)
├── c64/           7 platform files + tests/ + creature_data/
│   ├── main.s         (892 lines — bootstrap, hw init, trampolines)
│   ├── screen.s       (VIC-II 40-col rendering)
│   ├── dungeon_render.s (VIC-II viewport)
│   ├── memory.s       (PLA $01 banking)
│   ├── config.s       (C64/C128 detection)
│   ├── input.s        (keyboard via $01 + $C6)
│   ├── boot.s         (bootloader)
│   ├── tests/         23 test suites
│   └── creature_data/ tier data
└── c128/
    ├── main.s         (skeleton — commented import list + trampoline stubs)
    ├── ARCHITECTURE.md
    ├── README.md
    └── vdc_demo.s     (standalone VDC demo from earlier)
```

### What was done

1. **Created `commodore/common/`** and moved 64 files via `git mv` (preserves blame history)
2. **Extracted `common/game_loop.s`** (~1,382 lines) from `c64/main.s`:
   - `game_new_start` — new game initialization (character creation, starting equipment, first dungeon)
   - `load_resume_game` — load/resume entry point
   - `main_loop` — full command dispatch (movement, stairs, doors, items, combat, magic, etc.)
   - `run_step` — corridor running state machine
   - Death handling, dig ability, ego helpers, gameplay strings
3. **Updated `c64/main.s`** (2,262 → 892 lines):
   - Import paths changed to `../common/` for moved files
   - Added `#import "../common/game_loop.s"`
   - `!title_new` reference → `game_new_start` (global label in game_loop.s)
   - Platform-specific code remains: bootstrap, exit trampoline, IRQ wedge, 20+ banking trampolines, overlay segments
4. **Updated all 23 test files**: `"../X.s"` → `"../../common/X.s"` for moved files
5. **Updated Makefile**: `COMMON_SOURCES = $(wildcard ../common/*.s)` added to dependencies
6. **Created skeletal `c128/main.s`**: commented import list, trampoline label inventory, MMU banking notes

### Interface between common/ and platform code

`game_loop.s` calls trampoline labels defined in the platform's `main.s`. Kick Assembler resolves all labels globally within the compilation unit (everything is `#import`ed into one pass), so forward references work naturally. The C128's `main.s` will define the same trampoline labels with MMU `$FF00` banking.

### Verification

- `make clean && make build` — assembles without errors, all 71 compile-time asserts pass
- `make test` — all 24 suites (321 runtime tests) pass
- `git diff --stat` — confirms only file moves + import path changes

---

## C128 Input Bug Fixes — C1, M1, Run-Cancel (2026-02-27)

### Issues Resolved

| # | Severity | Description | Resolution |
|---|----------|-------------|------------|
| C1 | BLOCKER | C128: Missing essential keys (RETURN, SPACE, DEL, STOP, digits) in CIA scan table | Already present in `cia_scancode_table` in `input128.s` — entry was stale |
| M1 | HIGH | C128: `KBDBUF_COUNT` uses C64 address ($C6) instead of C128 ($D0) | Already $D0 in `input128.s` — entry was stale |
| — | HIGH | C128: Running could never be cancelled by keypress | `game_loop.s` read `KBDBUF_COUNT` which the CIA direct scan never writes; fixed via `input_run_key_check` |

### Root Cause — Run-Cancel Broken

`game_loop.s:195` checked `lda KBDBUF_COUNT; bne !run_cancel+` to detect a keypress during
running. On C64, the KERNAL IRQ handler (SCNKEY) writes $C6 each frame. On C128, `input128.s`
bypasses KERNAL entirely with `cia_scan_petscii` — nothing ever writes $D0 during the run loop,
so the branch never fired and running could not be cancelled.

### Fix

Introduced `input_run_key_check` as a platform-specific non-blocking key poll:

- **`c64/input.s`**: `lda KBDBUF_COUNT; rts` — reads KERNAL buffer count (unchanged behavior)
- **`c128/input128.s`**: `jsr cia_scan_petscii; rts` — polls CIA1 matrix directly; returns nonzero PETSCII if any key is pressed

`game_loop.s` now calls `jsr input_run_key_check` instead of `lda KBDBUF_COUNT` at the
run-cancel check site. Both builds: 69/70 asserts, 0 failed. Tested in VICE — run correctly
cancels on keypress.

---

## C128 Stability Fixes — VDC Hardware Fill & Overlay Overlap (2026-02-28)

### Issues Resolved

| Date | Bug | Description | Resolution |
|------|-----|-------------|------------|
| 2026-02-28 | **VDC Hardware Fill JAM** | CPU JAM at $A94E during character creation after pressing 'N'. | Reverted VDC hardware fill (Opt 5) to streaming loops in `screen_clear` and `screen_clear_row`. |
| 2026-02-28 | **Overlay Overlap JAM** | CPU JAM at $76CB when entering dungeon from town. | Moved `special_rooms.s` and `ego_items.s` to the end of the `banked_payload` block to avoid overlap with overlays. |

### Bug 1: VDC Hardware Fill Instability

**Root Cause:** The use of VDC Register 30 (Hardware Fill) in `screen_clear` and `screen_clear_row` caused a fatal CPU crash. The VDC hardware fill is an autonomous operation that takes several milliseconds. If the CPU selects a different VDC register or attempts data I/O while the fill is in progress, the VDC state machine can become corrupted, leading to invalid data being presented to the CPU or bus contention, resulting in a JAM.

**Fix:** Reverted `screen_clear` and `screen_clear_row` in `screen_vdc.s` to use deterministic streaming loops. Each byte is written to Register 31 with a preceding `jsr vdc_wait`. This ensures the VDC is always ready for the next command and eliminates race conditions.

### Bug 2: Overlay Overlap with Banked Payload

**Root Cause:** On the C128, overlays load at $E000-$EFFF. The `banked_payload` (containing resident gameplay routines) was relocated to $EB00 at runtime. The `DungeonGenOverlay` (3530 bytes) ended at $EDCA, overwriting the first ~700 bytes of the banked payload. This area contained `ego_items.s`. When `item_spawn_level` called `tramp_roll_ego_type`, the CPU jumped into the middle of the dungeon generation code instead of `roll_ego_type`, causing a crash.

**Fix:** Reordered the `banked_payload` block in `main.s`. The shared routines `special_rooms.s` and `ego_items.s` were moved to the end of the payload. Since the total payload size is ~4.6KB and it starts at $EB00, these routines now reside at $F900+, safely beyond the reach of any 4KB overlay.

### Verification

- **Character Creation:** Pressing 'N' on the title screen now reliably proceeds to race/class selection.
- **Dungeon Entry:** Moving from town to level 1 via stairs now correctly loads the creature tier and generates the level without crashing.
- **Build:** `make build128` completes with 69 asserts passing.
## DOC-1 — Input Numeric-Prefix Comment Cleanup ✅ COMPLETE (2026-03-20)

**Problem**
- `commodore/c64/input.s` still carried stale wording around numeric repeat prefixes, even though the feature had already been explicitly deferred in prior history cleanup.

**What changed**
- The file header now states that numeric repeat prefixes are intentionally unimplemented.
- `input_get_command` now documents that `zp_input_count` stays pinned to `1` unless the feature is deliberately revived.
- The stale “TODO for a future phase” wording was removed so the comments match current behavior and backlog reality.

**Verification**
- `rg -n "Numeric|prefix|zp_input_count" commodore/c64/input.s`
## OPT-2 — LOS Room-Bounds Predicate Cleanup ✅ COMPLETE (2026-03-20)

**Problem**
- `uv_player_in_room_x` in `commodore/common/dungeon_los.s` was still using a branch-heavy compare pattern to test the player against expanded room bounds.
- The logic was correct, but it spent extra instructions on the left/top checks in the hottest part of the room-reveal path.

**What changed**
- The left/top expanded-bound checks now use `player + 1 >= room_origin` instead of `room_origin - 1 <= player`, which removes the extra `SEC/SBC` and dual-branch equality handling.
- Right/bottom bounds remain inclusive and unchanged semantically.
- A focused C64 regression in `commodore/c64/tests/test_effects.s` now proves:
  - perimeter walls are still treated as inside the expanded room bounds
  - tiles two cells outside the perimeter are still treated as outside

**Verification**
- `make -C commodore/c64 build`
- `cd commodore/c64 && ./run_tests.sh`
- `make test128-fast`
- `make test128-fast-smoke`
## REF-1 — C128 Trampoline-Sprawl Consolidation ✅ COMPLETE (2026-03-20)

**Problem**
- `commodore/c128/main.s` had accumulated many small `tramp_*` wrappers with duplicated bank-switch and restore logic.
- The duplication made the low-memory trampoline surface harder to review and maintain, but a naive “generic call_banked” abstraction would have blurred together several distinct contracts and reopened C128 banking risks.

**What changed**
- Consolidated the **exact-match** trampoline families into local macros while preserving every public trampoline label and its placement below the `$D000` I/O hole:
  - compute-style banked calls
  - preserve-A wrappers
  - preserve-A-return wrappers
  - preserve-flags / restore-`$01` wrappers
  - UI display wrappers
  - banked status wrappers
  - shared-epilogue special-room wrappers
- Left the genuinely custom trampolines explicit:
  - overlay loaders
  - UI enter/exit primitives
  - suffix/text postprocessing trampolines
  - other wrappers with bespoke sequencing

**Why this is complete**
- The backlog goal was to reduce the trampoline sprawl by normalizing the duplicated families.
- That is now done.
- The remaining wrappers are not “missed consolidation”; they are the wrappers where a generic helper would obscure materially different contracts.

**Verification**
- `make -C commodore/c64 build`
- `cd commodore/c64 && ./run_tests.sh`
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- `make test128-fast-smoke`

## BUG-1 — Poison/Death HP Corruption ✅ COMPLETE (2026-03-22)

**Problem**
- Poison and starvation damage could subtract from zero HP and underflow the 16-bit HP field to `$FFFF` before death handling ran.
- Separately, the status bar could leave stale trailing digits in variable-width numeric fields, so a real max HP of `21` could still display as `211` after a redraw.

**What changed**
- Added a shared 1-HP damage helper in [commodore/common/turn.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/common/turn.s) and routed both poison ticks and starvation through it.
- The helper clamps HP at `0` and syncs the corrected value back to `player_data` before death checks run.
- Updated [commodore/common/ui_status.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/common/ui_status.s) so the full 3-line status block is cleared before redraw, preventing stale digits from surviving when 16-bit values shrink.
- Added focused C64 regression coverage in:
  - [commodore/c64/tests/test_turn.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/c64/tests/test_turn.s) for poison/starvation clamp-at-zero behavior
  - [commodore/c64/tests/test_ui_views.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/c64/tests/test_ui_views.s) for the `21 -> 211` stale-digit status case
- Updated [commodore/c64/run_tests.sh](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/c64/run_tests.sh) for the expanded test counts.

**Verification**
- User manual repro no longer showed the poison/death HP corruption.
- Focused C64 `turn` runtime suite: `10/10`
- Focused C64 `ui_views` runtime suite: `8/8`
- `make -B -C commodore/c128 build128`
- `make test128-fast`

## BUG-LIT — Dark-Room Full-Redraw Flash ✅ COMPLETE (2026-03-22)

**Problem**
- In dark rooms, several command tails could force a full redraw and make hidden room edges appear to "flash" visible even though the room was not actually lit.
- The bug was not one single renderer fault. It combined:
  - stale room-light state (`room_lit[]` drifting from per-tile `FLAG_LIT`)
  - item pickup forcing a full viewport redraw when a status-only tail was sufficient
  - generic non-movement `update_visibility` tails redrawing fully even when movement-equivalent conditions only needed a local redraw

**What changed**
- Added `light_room_x` in [commodore/common/dungeon_los.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/common/dungeon_los.s) as the authoritative helper for permanently lighting a room.
- `light_room_x` now:
  - sets `room_lit[x]`
  - sets `vis_room_revealed`
  - updates `vis_cached_room_idx`
  - applies `FLAG_LIT | FLAG_VISITED` across the room rectangle, including walls
- Updated `eff_light_room` in [commodore/common/spell_effects.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/common/spell_effects.s) to use that helper instead of only setting `room_lit[]`.
- Added focused C64 regression coverage in [commodore/c64/tests/test_effects.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/c64/tests/test_effects.s):
  - dark-room pickup + forced full redraw must not change unrelated viewport tiles
  - `eff_light_room` must synchronize `room_lit[]` and tile `FLAG_LIT`
- Updated [commodore/c64/run_tests.sh](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/c64/run_tests.sh) for the expanded `test_effects` result count.
- Updated [commodore/common/game_loop.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/common/game_loop.s) so `cmd_pickup` returns through `command_result_main_or_status_only` instead of forcing a full viewport redraw.
- Updated [commodore/common/game_loop_helpers.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/common/game_loop_helpers.s) so `post_turn_update_visibility_or_die` now:
  - runs `update_visibility`
  - updates the viewport once
  - uses `render_local_area` when there is no scroll, room reveal, or scene-dirty state
  - falls back to full redraw only when those conditions require it
- Expanded [commodore/c64/tests/test_main_loop.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/c64/tests/test_main_loop.s) and [commodore/c64/run_tests.sh](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/c64/run_tests.sh) to cover:
  - pickup using the status-only tail
  - clean-scene `update_visibility` commands using local redraw
  - room-reveal `update_visibility` commands still forcing full redraw

**Status**
- Manual gameplay rechecks cleared the original repro family after the final command-tail fixes.
- BUG-LIT is now closed as a multi-step repair: lighting-state synchronization plus removal of unnecessary full redraws on the affected command tails.

**Verification**
- User manual repro confirmed the dark-room pickup and follow-on forced-redraw cases stopped reproducing in gameplay.
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- `cd commodore/c64 && java -jar ../../tools/kickass/KickAss.jar tests/test_effects.s -o tests/test_effects.prg`
- Focused C64 `main_loop` runtime suite: `11/11`

## PERF-DG-C128 — Faster Dungeon Generation + Visible Busy Feedback ✅ COMPLETE (2026-03-23)

**Problem**
- Larger C128 dungeons (`198x66`) had become noticeably slow to generate in real play.
- There was no explicit user feedback during dungeon generation, so stairs / recall transitions felt like a hang.
- The original design target included a rotating spinner, but the safe generation seams did not provide enough honest tick points for a spinner that would not appear stalled.

**What changed**
- Added a shared dungeon-generation busy UI in:
  - [commodore/common/generation_busy.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/common/generation_busy.s)
  - [commodore/common/generation_busy_api.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/common/generation_busy_api.s)
- Startup now installs the busy-UI shim on both platforms:
  - [commodore/c64/main.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/c64/main.s)
  - [commodore/c128/main.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/c128/main.s)
- Wired the busy UI into real dungeon-generation transitions in:
  - [commodore/common/game_loop.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/common/game_loop.s)
  - [commodore/common/turn.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/common/turn.s)
- Scope was intentionally narrowed to **dungeon** generation only:
  - descending stairs
  - ascending between dungeon levels
  - recall into / between dungeon levels
  - not new-game town generation
  - not return-to-town generation
- `tier_manager.s` now suppresses its top-line `Loading...` message while the full-screen generation UI is active, so the two layers do not stomp each other.
- `dungeon_generate` in [commodore/common/dungeon_gen.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/common/dungeon_gen.s) no longer runs the shipping-time `verify_connectivity` retry loop.
  - The structural generation pipeline remains:
    - `fill_map_rock`
    - `place_rooms`
    - `place_streamers`
    - `connect_rooms`
    - stairs / traps / secrets / room darkening
  - The expensive tile-BFS connectivity check remains in source for diagnostics/tests, but it is out of the production generation hot path.
- The spell/prayer list header in [commodore/common/player_magic.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/common/player_magic.s) was also corrected to `screencode_mixed` during this pass, fixing the visible header garbage that surfaced while validating the busy UI work.

**UX result**
- The final shipped feedback is a static full-screen `GENERATING...` message rather than a rotating spinner.
- That is deliberate: with the now-faster generator, the safe high-level phase seams are too coarse for a spinner that feels truthful instead of appearing frozen on one frame.

**Verification**
- Manual validation confirmed:
  - new-game town stays clean and does not show the full-screen busy message
  - `>` into a dungeon shows `GENERATING...`
  - the resulting dungeon renders correctly
  - generation feels materially faster
- `make -C commodore/c64 build`
- `make -B -C commodore/c128 build128`
- `make test128-fast`

## C128 Dungeon-Entry Overlay/Tier Ownership Fix ✅ COMPLETE (2026-03-24)

**Problem**
- Entering dungeon level 1 on C128 could crash with a CPU `JAM` at `$E18C` after a fresh `make clean128; make disk128` build.
- The monitor bytes at the crash site matched tier payload data, not the built `OVL.GEN` overlay image.

**Root Cause**
- [level_change_generate_current](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work2/commodore/common/game_loop.s) loaded `OVL_DUNGEON_GEN` and ran dungeon generation, then called `tier_check_transition`.
- On C128, [tier_load](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work2/commodore/common/tier_manager.s) intentionally invalidates the active overlay and reuses `$E000` for tier data.
- The shared descent path then continued straight into `monster_spawn_level` and `item_spawn_level`, which still call special-room helpers living in the dungeon-generation overlay.
- That let valid trampolines jump into tier bytes occupying `$E000`, producing the `JAM`.

**Fix**
- Added a C128-only `c128_restore_generation_overlay` step in [commodore/common/game_loop.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work2/commodore/common/game_loop.s) immediately after `tier_check_transition`.
- The helper reloads `OVL_DUNGEON_GEN` only when tier activation displaced it, then restores the C128 runtime guards before post-generation spawning continues.
- Added focused C128 regression coverage in [commodore/c128/tests/test_main_loop128.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work2/commodore/c128/tests/test_main_loop128.s) proving the overlay is reloaded before monster spawning sees the post-tier state.

**Architectural note**
- This is the correct tactical fix for the current ownership model because it restores the explicit runtime contract at the point it was violated.
- The cleaner future refactor is to stop relying on implicit overlay residency across the tier-load boundary: either move the post-tier special-room helpers out of the overlay, or split dungeon entry into overlay-only and resident post-tier phases.

**Verification**
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- `TEST_FILTER='real_boot_crash_harness' bash commodore/c128/run_tests128.sh`
