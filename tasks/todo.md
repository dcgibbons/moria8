# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Task
- [x] Analyze and design `BUG-EGO-NAME`.

## Plan
- [x] Trace the item-name rendering path for inventory/equipment ego items.
- [x] Inspect ego suffix storage and platform trampoline paths.
- [x] Get a consultant second opinion on likely root cause and safest fix shape.
- [x] Write the recommended implementation/test plan.

## Review
`BUG-EGO-NAME` is most likely a suffix-rendering contract bug, not a base-item-name bug.

Key findings:
- Base item names are resolved through `item_get_name_ptr` in [item.s](commodore/common/item.s), and that path already handles identified/unidentified names correctly.
- Inventory and equipment views call `put_inv_name_with_ego` in [game_loop.s](commodore/common/game_loop.s), which:
  - prints the base item name with `screen_put_string`
  - then appends the ego suffix via `banked_ego_put_suffix`
- `banked_ego_put_suffix` directly reads suffix strings through `ego_get_suffix_ptr`, whose comment in [ego_items.s](commodore/common/ego_items.s) explicitly says the strings live in banked `$F000+` RAM and must be read with KERNAL banked out.
- On C64 there is already a platform-owned safe helper for exactly this operation: `tramp_ego_put_suffix` in [c64/main.s](commodore/c64/main.s), which:
  - banks out KERNAL
  - reads the `$F000` suffix string
  - writes each character to screen
  - restores normal banking

Most likely root cause:
- `put_inv_name_with_ego` is bypassing the platform trampoline and calling `banked_ego_put_suffix` directly.
- That means UI code is relying on an implicit “KERNAL already banked out” contract that is not safe for inventory/equipment views on C64.
- Symptom match is strong:
  - base item name displays fine
  - appended ego/slay text is garbage
  - digging tools use a main-RAM prefix path instead of the banked suffix path, so they are much less likely to show the bug

Secondary possibility:
- C128 MMU drift could also corrupt suffix reads, but the direct C64 banked-RAM misuse is the cleaner and more probable root cause.
- The consultant also flagged cursor-state coupling as a lesser risk, but nothing in the current code is as suspicious as the direct `$F000` suffix read.

Test gap:
- `test_ui_views.s` exercises inventory/equipment rendering, but not with a known ego/slay item that forces suffix output.
- `test_ego.s` covers ego mechanics and persistence of `inv_ego`, not UI rendering of the suffix text.
- So the current suite can stay green while this visible bug survives.

Consultant second opinion:
- Agreed that the failure is most likely in the name-composition path rather than `item_get_name_ptr`.
- Also agreed that the safest fix is to keep base-name resolution alone and harden the suffix-print path plus coverage.

## Recommended `BUG-EGO-NAME` Design

### Product Goal
- Make inventory/equipment item names render ego/slay text correctly and consistently on both C64 and C128.
- Preserve the existing digging-tool prefix behavior (`Gnomish Shovel`, `Orcish Pick`) while fixing suffix-based ego names (`Long Sword (Slay Evil)`).

### Core Design
1. Keep `item_get_name_ptr` unchanged.
   - It already owns the base-name contract.
2. Stop letting `put_inv_name_with_ego` read banked suffix strings directly.
   - Replace the direct `banked_ego_put_suffix` call with the platform-owned suffix trampoline path.
   - On C64/C128, that means `tramp_ego_put_suffix` should be the only public path that reads ego suffix text from banked `$F000`.
3. Narrow `banked_ego_put_suffix` responsibility.
   - Either remove it entirely if no longer needed, or keep it as an internal helper only where the banking contract is already explicitly owned.
4. Leave tool-prefix behavior alone.
   - `put_tool_ego_prefix` lives in main RAM and is not the likely source of the corruption.

### Why This Is The Right Shape
- It fixes the actual ownership bug instead of papering over the symptom.
- It uses the already-existing platform trampolines instead of adding a second suffix-reading contract.
- It keeps the change small and local:
  - one shared UI name helper
  - one focused regression test

### Test Plan
1. Extend `commodore/c64/tests/test_ui_views.s` with inventory/equipment cases that use:
   - a non-tool ego weapon, e.g. `Long Sword` + `EGO_SLAY_EVIL`
   - optionally a second suffix case like `Defender`
2. Assert the rendered screen text contains the expected suffix bytes, not just the base item name.
3. Keep a tool-prefix case if helpful to prove the prefix path still behaves.
4. Re-run:
   - `make test`
   - `make -B -C commodore/c128 build128`
   - `make test128-fast`

### Likely Outcome
- Small implementation.
- High confidence.
- Most probable code change is to route inventory/equipment suffix printing through `tramp_ego_put_suffix` and add missing UI regression coverage.

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
## 2026-03-23 — Invisible blockers / items-in-walls investigation

- Root-cause candidate: `find_random_floor` in `commodore/common/dungeon_features.s` returned the last random tile even after 200 failed attempts, and multiple callers treated that as valid.
- That contract can place traps, teleports, and spawned floor items onto non-floor or occupied tiles, which matches the “item in wall” reports.
- Fix shape:
  - make `find_random_floor` return carry-set on success / carry-clear on failure
  - update all callers to stop on failure instead of consuming stale coordinates
  - add a runtime regression proving `item_spawn_level` cannot place floor items when the map has no valid floor tiles
