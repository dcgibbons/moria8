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
