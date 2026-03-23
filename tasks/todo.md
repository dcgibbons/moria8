# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Task
- [x] Audit `BUG-LIGHT-RANGE` against original Umoria/VMS Moria source and close or narrow it.

## Plan
- [x] Inspect the current carried-light implementation and all places that hard-code light radius.
- [x] Verify what original Umoria documentation actually says about carried light versus room lighting.
- [x] Get a consultant second opinion on the safest product goal and implementation shape.
- [x] Write the recommended `BUG-LIGHT-RANGE` design.

## Review
`BUG-LIGHT-RANGE` is resolved as a source-confirmed non-bug: original source code shows that carried light is a 3x3 local bubble around the player, and torch vs lantern differ by fuel duration, not by a larger visibility radius.

Source findings:
- The current port hard-codes carried light to `zp_light_radius = 1` in multiple places:
  - equipping a light in `commodore/common/player_items.s`
  - removing/depleting a light in `commodore/common/player_items.s` / `commodore/common/turn.s`
  - starting equipment/new game in `commodore/common/game_loop.s`
  - player bootstrap defaults in `commodore/common/player_create.s`
- Visibility uses a Chebyshev-distance bubble in `commodore/common/dungeon_los.s`, separate from room-level lighting via `room_lit[]`.
- `umoria` source uses a boolean carried-light state and lights a 3x3 area around the player:
  - `~/Projects/thirdparty/umoria/src/dungeon.cpp` `sub1MoveLight()`
  - `~/Projects/thirdparty/umoria/src/dungeon.cpp` `dungeonMoveCharacterLight()`
- `vms-moria` shows the same rule:
  - `~/Projects/thirdparty/vms-moria/source/include/moria.inc` `sub1_move_light`
  - `~/Projects/thirdparty/vms-moria/source/include/misc.inc` `test_light`
- In both original trees, torch and lantern share the same visibility semantics; they differ by fuel capacity / refueling behavior, not light radius.
- We already matched original fuel-duration behavior earlier; the remaining gap is visibility semantics, not charge length.

Consultant second opinion:
- With the source finding in hand, this should no longer be treated as a gameplay bug.
- The safest next step is optional cleanup only: centralize the carried-light contract and add tests so future changes do not drift from the confirmed original rule.

## `BUG-LIGHT-RANGE` Audit Result

### Confirmed Behavior
- carried light = local radius-1 / 3x3 bubble
- room lighting remains a separate concept
- torch and lantern differ by duration/refuel behavior, not viewport radius

### Cleanup Rules If Revisited Later
1. Do **not** change room-lighting semantics (`room_lit[]`, `FLAG_LIT`, room reveal) as part of this bug.
2. Do **not** conflate "lantern should feel stronger" with "lit rooms should flood-fill."
3. Do **not** invent a torch-vs-lantern radius distinction unless a deeper source contradiction is found.
4. Make carried-light behavior come from one helper/table, not repeated `lda #1` writes.

### Optional Cleanup Shape
1. Add a single shared helper or table-driven routine, e.g. `player_update_light_radius` or `item_light_radius_for_id`.
   - Inputs: equipped light item id and possibly charge count
   - Output: canonical `zp_light_radius`
2. Replace duplicated hard-coded light-radius writes in:
   - `commodore/common/player_items.s`
   - `commodore/common/turn.s`
   - `commodore/common/game_loop.s`
   - `commodore/common/player_create.s`
3. Keep `commodore/common/dungeon_los.s` and the renderers unchanged unless the original-game research proves the visibility geometry itself is wrong.

### Optional Test Additions
If we want extra hardening later, add focused runtime coverage for:
1. equipping a torch sets the expected canonical radius
2. equipping a lantern sets the expected canonical radius
3. removing/depleting the light clears the radius
4. visibility around the player matches the canonical radius on both C64 and C128 paths

### Outcome
- No gameplay change is needed.
- Close the backlog bug.
- Leave only optional cleanup/proof work if we want to harden the contract later.

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
