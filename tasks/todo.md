# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Task
- None active. `TST-5a` and `TST-5b` are complete; only optional `TST-5c` palette add-ons remain.

## Plan
- [x] Inspect the existing disk-swap code paths and current test harness pattern.
- [x] Add a focused C64 `test_disk_swap.s` with stubbed KERNAL/UI/input helpers.
- [x] Wire the new test into `commodore/c64/run_tests.sh`.
- [x] Verify the new test plus baseline C64/C128 build/test gates.
- [x] Add narrow isolated renderer decision-tree coverage on C64 and C128.
- [x] Verify the renderer tests plus baseline C64/C128 gates.

## Review
- Added `commodore/c64/tests/test_disk_swap.s` covering:
  - `disk_prompt`
  - `disk_init_drive`
  - `probe_device`
  - `disk_enter_device`
- Added `commodore/c64/tests/test_render.s` covering:
  - unvisited tile blanks
  - visible item overrides floor
  - visible monster overrides item
  - player overrides monster/item
- Extended `commodore/c128/tests/test_vdc_scroll_delta128.s` with the same single-tile override cases against the real VDC renderer.
- Added the suite to `commodore/c64/run_tests.sh`.
- Verification completed:
  - `java -jar tools/kickass/KickAss.jar commodore/c64/tests/test_disk_swap.s -o commodore/c64/tests/test_disk_swap.prg`
  - direct VICE monitor run of `test_disk_swap.prg`: `11/11` result bytes at `$0400-$040A`
  - `cd commodore/c64 && java -jar ../../tools/kickass/KickAss.jar tests/test_render.s -o tests/test_render.prg`
  - direct VICE monitor run of `test_render.prg`: `4/4` result bytes at `$0400-$0403`
  - `make -C commodore/c64 build`
  - `make -B -C commodore/c128 build128`
  - `make test128-fast`

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
