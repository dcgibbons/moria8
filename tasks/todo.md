# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Task
- Design pass: persistence-media policy feature to keep save/load/high-score writes off the program disk.

## Plan
- [x] Inspect the current save/load/disk-swap/high-score flows and existing drive-selection behavior.
- [x] Get a consultant second opinion on the proposed requirements and technical constraints.
- [x] Consolidate the revised requirements and feature design into a backlog-ready spec.

## Review
This feature should be treated as a persistence-policy change, not just a save prompt tweak.

Current state from the code:
- `save_device` already controls:
  - save/load game in `commodore/common/save.s`
  - high-score load/save in `commodore/common/score_io.s`
- `disk_mode` currently means:
  - `0 = same disk`
  - `1 = swap disk`
  - `2 = dedicated second drive`
- save/load/game-over flows already bracket persistence with `disk_prompt_save` / `disk_prompt_game` in the main loop, but they do not validate what disk is actually in the selected save drive.
- destructive persistence happens too early today:
  - `save_game` scratches the old save before proving the target is acceptable
  - `hiscore_save` scratches the old hall-of-fame file before proving the target is acceptable

## Revised Requirements

Original user goals were directionally right, but they need to be tightened:

1. Prompting
- Keep save-disk prompting on save and load, but only in swap mode.
- Keep the same save-disk prompt around death/high-score persistence too, because those writes use the same `save_device`.
- In dedicated-save-drive mode, do not prompt.

2. Program-disk rejection
- Expand the requirement from “reject saving if the program disk label is present” to:
  - reject any persistence transaction if the selected save target appears to be the program disk
  - this applies to:
    - save
    - load
    - delete-savefile
    - high-score load/save
- This validation must happen before any scratch/delete/open-for-write action.

3. Drive detection and selection
- Reframe “detect how many drives are available” as:
  - probe a small set of candidate IEC devices and present the responding ones
- IEC/KERNAL can tell us which device numbers answer, not authoritatively how many “real drives” exist or what disk is inserted.
- Manual numeric entry should remain as expert fallback, not the primary path.

## Consultant Second Opinion
- The consultant agreed on the main adjustments:
  - this is basically the old “character disk” idea, but stricter
  - the current `same disk` mode conflicts with program-disk rejection and should be removed or hidden
  - validation must cover save/load/high-score, not just save
  - drive probing is realistic; disk identity is only best-effort via directory/header label checks

## Recommended Feature Model

### Runtime modes
Replace the user-facing model with only two supported modes:
- `swap save disk`
- `dedicated save drive`

Do not expose `same disk` if the goal is to keep persistence off the program disk.

Internal state can remain compact:
- mode = swap
- mode = dedicated
- selected `save_device`

### Save target setup UX
At title/menu setup time:
1. Probe common device candidates first
   - likely `8` and `9` first, optionally up through `30` only for manual fallback
2. If only one usable target is found:
   - configure swap mode on that device
3. If more than one usable target is found:
   - let the player choose the save drive from the detected list
   - choosing the program drive should not be offered as a save target
4. Keep numeric entry fallback for unusual IEC setups

### Validation policy
Add a new validation layer ahead of all persistence actions:
- `save_target_validate_for_read`
- `save_target_validate_for_write`

Responsibilities:
- probe drive presence
- inspect disk identity best-effort
- reject the known program disk label
- return carry set/clear or a compact status code for UI messaging

Validation should run:
- before save
- before load
- before delete-savefile
- before hiscore load/save

### Disk identity check
Use directory/header label inspection as a best-effort guard.

Design stance:
- reliable enough to reject the known program disk
- not treated as cryptographic truth

Behavior:
- if label matches the Moria program disk signature, reject
- if label cannot be read:
  - fail safe for write paths
  - for read paths, show a clear disk error and return to caller

### Save/load/death behavior
- `save_game` should return success/failure to the caller instead of unconditionally leading to quit behavior.
- The save caller should only exit/quit when save succeeds.
- Load flow should remain:
  - prompt/validate save disk
  - load savefile
  - restore game disk
  - `load_resume_game`
- Death/high-score flow should be treated as one persistence transaction:
  - prompt/validate save disk once
  - delete savefile if needed
  - load/save hall of fame
  - restore game disk once

## Required Code Changes

### `commodore/common/disk_swap.s`
- replace the current exposed mode model
- add save-target setup UI around probed devices
- keep numeric-entry fallback
- add new validation helpers / result codes
- revise prompt strings to match the new policy

### `commodore/common/save.s`
- validate before `delete_savefile_core`
- make `save_game` return success/failure
- avoid destructive actions on rejected or unknown media

### `commodore/common/score_io.s`
- validate before scratch/write
- use the same save-target policy as save/load

### `commodore/common/game_loop.s`
- change save command flow to honor `save_game` success/failure
- keep swap-back only after an actual swap-mode persistence transaction
- keep death-path persistence grouped into one prompt window

### Title/menu entry points (`commodore/c64/main.s`, `commodore/c128/main.s`)
- replace the current `S)ame W)swap #)Drive #` setup menu
- drive selection should come from probed devices first

## Edge Cases To Handle
- one responding drive only
- two responding drives
- manual numeric entry to unusual IEC devices
- save disk missing after setup
- wrong disk inserted later
- program disk inserted in selected save drive
- failure during save should not quit the game
- failure during death-path hiscore save should not crash the death screen

## Recommended Implementation Order
1. Refactor mode model and setup menu first.
2. Add non-destructive validation helpers next.
3. Make `save_game` return status and fix save caller behavior.
4. Apply the same validation policy to `score_io.s`.
5. Add focused unit tests for:
   - validation results
   - save command no-quit on failure
   - death-path score persistence on rejected media

## Bottom Line
- This should be added to the backlog as a medium-priority feature.
- The real goal is:
  - separate program media from persistence media
  - validate before destructive actions
  - unify save/load/high-score drive policy
- It is not just a prompt enhancement.

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
