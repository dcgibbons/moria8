# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Task
- [x] Implement `BUG-RECALL` by routing Word of Recall through the shared level-transition helper.

## Plan
- [x] Inspect the current Word of Recall code path, related state, and existing regression coverage.
- [x] Compare the recall transition path with the hardened stairs / level-change path.
- [x] Get parallel second opinions on likely root cause and safest fix shape.
- [x] Write the recommended `BUG-RECALL` design.
- [x] Patch recall expiry to invalidate transient tier state and reuse the shared level-change helper.
- [x] Update regression coverage for the new recall path.
- [x] Verify with C64/C128 builds and tests.

## Review
`BUG-RECALL` is most likely a transition-path drift bug, not a scroll/timer bug.

Key findings:
- The scroll-use path in `commodore/common/player_items.s` only arms `zp_eff_word_recall`; nothing looks wrong there.
- The expiry path in `commodore/common/turn.s` duplicates its own level-change orchestration instead of reusing the hardened shared helper in `commodore/common/game_loop.s`.
- Recall currently does:
  - adjust `zp_player_dlvl`
  - set `level_entry_dir`
  - maybe restock stores
  - call `tier_check_transition`
  - call `level_generate` directly
  - then run spawn / visibility / redraw directly
- The stairs path instead uses `level_change_generate_current`, which:
  - loads `OVL_DUNGEON_GEN`
  - uses `tramp_level_generate`
  - restores C128 runtime guards
  - runs the shared generation / redraw tail in one place

Most likely root cause:
- `level_generate` lives in the dungeon-generation overlay, so the recall path can execute whatever overlay happens to be resident at `$E000` instead of the real generation code.
- That explains a “does not reliably return to town” report much better than the timer math does, and it also explains why the existing unit tests did not catch it.

Secondary risk:
- Recall currently does only `sta current_tier` with `0` before recomputing the transition.
- The hardened load-resume path already learned that stale tier metadata (`tier_loaded`, name-table pointers, cache-size state) can survive across transitions and produce hybrid runtime state.
- A safer recall design should use `tier_invalidate_state`, not just clear `current_tier`.

Test gap:
- Existing C64 unit tests in `commodore/c64/tests/test_turn.s` and `commodore/c64/tests/test_effects.s` stub out `level_generate` and the rest of the transition tail with counters.
- That proves timer/orchestration intent, but it cannot catch overlay-residency or stale-tier-state bugs.
- Current C128 coverage does not appear to exercise a real recall teleport transition end-to-end.

Consultant / subagent second opinion:
- Strong agreement that the overlay mismatch is the primary suspect.
- Recommended design: all level-changing paths should share one transition helper, with recall responsible only for choosing destination and preconditions.
- Also flagged one design choice to settle explicitly: whether recall destination should be based on live depth when the timer expires, or snapshotted when the scroll is read.

## Recommended `BUG-RECALL` Design

### Product Goal
- Make Word of Recall use the same reliable town/dungeon transition machinery as stairs and Wizard jumps.
- Eliminate any path-specific generation / overlay / redraw logic from the recall timer expiry branch.

### Core Design
1. Keep the timer arming logic where it is.
2. In the expiry path, keep only the recall-specific decision logic:
   - dungeon -> town
   - town -> `PL_MAX_DLVL`
   - fizzle if `PL_MAX_DLVL == 0`
   - restock stores on town re-entry
   - set `level_entry_dir`
3. After that, hand off to the same shared transition helper the stairs path uses:
   - `level_change_generate_current`
4. Invalidate transient tier state before recomputing the transition:
   - use `tier_invalidate_state`
   - do not rely on only `current_tier = 0`

### Why This Is The Right Shape
- It removes overlay-load drift by making recall load/use `OVL_DUNGEON_GEN` the same way as stairs.
- It removes duplicated generation/redraw logic.
- It reuses the path that already carries the C128 runtime-guard and overlay correctness work.
- It aligns with the earlier `SAV-2` lesson that transient tier metadata must be invalidated on cross-level entry points.

### Open Semantics Decision
- Current behavior chooses destination from live `zp_player_dlvl` when the timer expires.
- That may be acceptable if it matches original Moria behavior.
- If the user wants stronger reliability semantics, a follow-up design could snapshot the intended destination when the scroll is read.
- Recommendation: keep current live-depth semantics unless original-source review or user expectation says otherwise; fix the transition machinery first.

### Test Plan
1. Strengthen unit tests:
   - recall dungeon -> town
   - recall town -> deepest level
   - recall fizzle in town with `PL_MAX_DLVL = 0`
   - assert `tier_invalidate_state`-equivalent state reset, not just `current_tier = 0`
2. Add integration coverage that does **not** stub the generation path:
   - one real C64 runtime recall transition
   - one real C128 smoke recall transition
3. Specifically verify:
   - town map after recall is actually town
   - store restock happens on town return
   - correct arrival message
   - no stale dungeon-tier creature state/name pointers remain after town return

### Likely Outcome
- Small code change if implemented elegantly:
  - mostly deleting duplicated recall-tail code and reusing the shared helper
- High confidence payoff:
  - fixes the likely real bug
  - reduces future drift between stairs, Wizard jumps, and recall

## Implementation Result

### What Changed
- `commodore/common/turn.s`
  - recall expiry now keeps only the destination decision logic
  - actual town/dungeon transition now goes through:
    - `tier_invalidate_state`
    - `level_change_generate_current`
  - the old duplicated generation/redraw tail was deleted
  - the occupied-bit clear now happens only on real recall teleports, not on town-side recall fizzles
- `commodore/c64/tests/test_turn.s`
  - added focused stubs/counters for `tier_invalidate_state` and `level_change_generate_current`
  - strengthened the dungeon->town and town->deepest assertions to prove the shared helper is used
  - added a fizzle assertion that the current tile remains occupied when recall does not fire

### Why This Fix
- It removes recall's private overlay/generation path and reuses the already-hardened stairs transition helper.
- It fixes the likely real failure mode on C128: direct `level_generate` calls against whichever overlay happened to be resident at `$E000`.
- It also aligns recall with the learned tier-state invalidation rules from earlier cross-level fixes.

### Verification
- `make -C commodore/c64 build`
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- Focused C64 runtime `test_turn` verification was attempted separately, but local `x64sc` exited `139` before any monitor dump in this environment, so that result is inconclusive rather than failing.

## Coverage Read

### Already covered enough to avoid duplication
- **C128 palette mapping**
  - `commodore/c128/tests/test_vdc_attr128.s`
  - `commodore/c128/tests/test_dungeon128.s`
- **C128 scroll-delta / renderer integration**
  - `commodore/c128/tests/test_vdc_scroll_delta128.s`
- **C64 redraw behavior around dark-room bugs**
  - `commodore/c64/tests/test_effects.s`
- **Dungeon generation room drawing**
  - `commodore/c64/tests/test_dungeon.s`

### Weak / missing
- **Palette mapping**
  - The backlog wording overstated this. It is mostly covered already.
  - At most, it needs a small consistency add-on, not a large new suite.

## Consultant Second Opinion
- The consultant agreed with the same ordering:
  1. disk swap is the real missing isolated-test gap
  2. renderer draw-routine logic is next
  3. palette mapping is mostly already good enough

## Recommended `TST-5` Split

### `TST-5a` — Disk swap unit tests
Priority: highest

Add a new small C64 test module focused on `commodore/common/disk_swap.s`.

Target routines:
- `disk_prompt`
- `disk_init_drive`
- `probe_device`
- `disk_enter_device`

Design:
- Stub all KERNAL/IEC entry points:
  - `KERNAL_SETNAM`
  - `KERNAL_SETLFS`
  - `KERNAL_OPEN`
  - `KERNAL_CLOSE`
  - `KERNAL_READST`
  - `KERNAL_CLRCHN`
- Stub UI/input helpers:
  - `input_get_key`
  - `screen_put_string`
  - `screen_put_char`
  - `screen_put_decimal_rj2`
  - `screen_clear_row`
- Record:
  - whether prompts were shown
  - whether key wait happened
  - whether drive init happened
  - what device number was probed
  - final `disk_mode`
  - final `save_device`

Minimum test cases:
1. `disk_prompt` is a no-op in mode 0
2. `disk_prompt` is a no-op in mode 2
3. `disk_prompt` in mode 1 draws prompt, waits for key, then calls `disk_init_drive`
4. `probe_device` returns present when `OPEN` succeeds and `READST` has no error bits
5. `probe_device` returns absent when `OPEN` fails
6. `probe_device` returns absent when `READST` reports error bits
7. `disk_enter_device` accepts a valid one-digit entry (`8`) and sets `disk_mode=2`, `save_device=8`
8. `disk_enter_device` accepts a valid two-digit entry (`30`) and sets `save_device=30`
9. `disk_enter_device` rejects out-of-range input and re-prompts
10. `disk_enter_device` handles absent device by showing error and returning carry set

Why this matters:
- This is the least-covered high-branching shared code left.
- It touches save/score/disk UX but is cheap to validate with pure unit stubs.

### `TST-5b` — Renderer decision-tree unit tests
Priority: medium

Goal:
- Add one narrow draw-logic test for C64
- Add one narrow draw-logic test for C128

What to test:
- visible floor tile renders tile glyph/color
- unseen tile renders blank/background
- visible item overrides floor
- visible monster overrides item
- player overrides everything
- dim/remembered tiles do not show monsters

Recommended shape:
- **C64**:
  - new dedicated render unit test, or extend `test_effects.s` only if that stays small
  - call `render_single_tile` directly against a synthetic map / monster / item setup
  - assert resulting screen code + color RAM at the target cell
- **C128**:
  - extend `test_vdc_scroll_delta128.s`
  - keep it renderer-local, not another game-loop smoke
  - assert the chosen VDC attribute/glyph outcomes for one or two representative override cases

Why this matters:
- It covers the draw selection logic directly.
- It avoids re-testing scroll delta, overlay loading, or whole turn flow.

### `TST-5c` — Palette consistency add-on
Priority: low

Only do this if there is still budget.

Scope:
- tiny table-level consistency checks
- no new smoke suite

Likely additions:
- keep `vic_to_vdc_color` table invariants explicit for the most important colors
- optionally assert a couple of authored palette contracts used by live rendering:
  - player white
  - gold yellow
  - wall/floor grey split

Why low priority:
- current coverage is already pretty good here
- recent 10.4 work added even more direct C128 palette assertions

## Recommended Merge Triage

### Do before merge if possible
- `TST-5a` disk swap
- `TST-5b` renderer decision tree

### Safe to defer
- most of `TST-5c` palette work

## Pitfalls To Avoid
- Do not turn `TST-5` into a banking/layout refactor.
- Do not rely on real disk access for disk-swap unit tests; stub KERNAL/IEC behavior.
- Do not duplicate existing scroll-delta or broad color tests.
- For any new C128 runtime test, keep the bootstrap/address rules in mind if code size grows toward `$A000`.
- Keep draw-routine tests narrow and synthetic; do not funnel them through the whole game loop unless the game loop itself is what you are testing.

## Bottom Line
- `TST-5` should be treated as:
  - `TST-5a` disk swap
  - `TST-5b` renderer decision tree
  - `TST-5c` palette consistency
- The high-value part is disk swap.
- The merge-useful part after that is renderer decision logic.
- Palette work is largely already covered.
