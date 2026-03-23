# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Task
- Design pass: re-evaluate the backlog item for remaining 40-column assumptions in shared UI/data files.

## Plan
- [x] Inspect the current backlog wording and the named files for real width-coupled behavior.
- [x] Get a consultant second opinion on which assumptions are real cleanup vs stale/non-issues.
- [x] Consolidate the result into a cleanup design with recommended backlog re-triage.

## Review
The backlog item is mostly stale. The named files fall into three different buckets:

1. Already width-aware, no cleanup needed
- `commodore/common/ui_messages.s`
  - `MSG_HIST_LEN = SCREEN_COLS`
  - `MSG_MORE_MAX_COL = SCREEN_COLS - MSG_MORE_LEN`
  - this is already a proper width-derived implementation, not a leftover 40-col bug
- `commodore/common/disk_swap.s`
  - prompt placement is centered from `SCREEN_COLS`
  - the only fixed values are prompt-string widths and chosen rows
  - that is prompt-layout math, not a stale 40-col assumption worth its own backlog item

2. Data/assets intentionally authored for 40-column presentation
- `commodore/common/title_data.s`
  - this is a literal 40-col art stream with fixed columns (`1`, `38`, 36-char borders, etc.)
  - `commodore/common/title_screen.s` already compensates on C128 with `TITLE_ART_COL_OFFSET = (SCREEN_COLS - 40) / 2`
  - if we want a true 80-col title, that is a new native-80 art task, not a cleanup of shared logic
- `commodore/common/ui_help_data.s`
  - the renderer in `ui_help.s` is already width-aware
  - the actual 40-col coupling is in the packed help content/tab stops (`10`, `20`, two-column packing)
  - if we want a true 80-col help screen, the work is a data reflow / content redesign, not a renderer refactor

3. Work that already belongs under `UI-80`
- `commodore/common/ui_status.s`
  - this already has explicit C64 and C128 layout tables
  - the C128 side is the current 80-col baseline
  - any further cleanup or refinement belongs under `UI-80`, not under a generic 40-col-assumption cleanup item

## Consultant Second Opinion
- The consultant reached the same conclusion:
  - `ui_messages.s` should drop out entirely
  - `disk_swap.s` is mostly fine as-is
  - `ui_status.s` belongs under `UI-80`
  - `title_data.s` and `ui_help_data.s` are the only real 40-col-native assets, and only matter if we decide to create true 80-col-native replacements

## Recommended Backlog Re-triage

### Remove as stale/non-issues
- `ui_messages.s`
- `disk_swap.s`

### Fold into existing `UI-80`
- `ui_status.s`

### Split into optional native-80 follow-ons only if desired
- `title_data.s` + `title_screen.s`
  - optional `UI-80-TITLE`: native 80-col title art
- `ui_help_data.s` + `ui_help.s`
  - optional `UI-80-HELP`: native 80-col help content layout

## Recommended Implementation Order
1. Keep the current backlog item out of `BUILDPLAN.md` as a single mixed bucket.
2. Treat status-bar refinement only as part of `UI-80`.
3. If we want more native 80-col polish after that:
   - reflow `ui_help_data.s` first
   - then decide whether a native 80-col title screen is worth a separate art task
4. Do not schedule `ui_messages.s` or `disk_swap.s` cleanup unless a real bug appears.

## Bottom Line
- This is not one real cleanup task anymore.
- The only substantial remaining work is:
  - `UI-80`
  - optionally, native-80 help data
  - optionally, native-80 title art
- The current BUILDPLAN wording should eventually be simplified to match that.

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
