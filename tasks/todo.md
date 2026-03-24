# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Task
- [x] Fix `BUG-DEEP-SPAWN`.

## Plan
- [x] Re-check the deep-spawn selector and original Umoria behavior.
- [x] Implement the selector/fallback fix in `pick_creature_type`.
- [x] Add a focused runtime regression for the empty-band deep fallback case.
- [x] Keep C64/C128 authoritative verification green after the fix.

## Review
`BUG-DEEP-SPAWN` is fixed.

### Root cause
- Deep-level selection in `commodore/common/monster.s:pick_creature_type` used a narrow preferred level band:
  - `min = max(1, dlvl - 2)`
  - `max = dlvl + 3`
- When no loaded creature matched that band, the code fell through to hardcoded creature index `0`.
- That made deep-level failure collapse to whatever happened to live at slot `0`, which is structurally wrong.

### Fix shape
- Kept the existing narrow-band fast path so shallow/normal selection behavior stays familiar.
- Replaced the bad fallback with:
  - scan the currently loaded roster
  - choose the highest loaded creature level `<= current dungeon depth`
  - return that slot instead of `0`
- This is the narrow fix from the design, not a full Umoria-weighted selector rewrite.

### Additional support work
- `commodore/c64/tests/test_monster.s`
  - added a synthetic empty-band deep fallback regression (`dlvl 45`, roster `[1,20,25,30]`, expects index `3`)
- `commodore/common/title_sysinfo_banked.s`
  - removed unused machine-string/table bytes from the C64 banked payload
- `commodore/common/ui_home.s`
  - shortened one low-value home prompt to recover the last C64 banked-payload bytes needed to stay below `$D000`

### Why the support trims were needed
- The selector fix itself was small, but C64 banked payload was already near the `$D000` ceiling.
- After the selector/test changes, the C64 banked payload crossed the I/O-hole guard by a handful of bytes.
- The title/home byte trims were the smallest safe way to restore the payload contract without redesigning more code.

### Verification
- `make test`
- `make -B -C commodore/c128 build128`
- `make test128-fast`

### Outcome
- Deep empty-band selection no longer collapses to creature index `0`.
- The specific DL45-50 repeated-`White Harpy` failure mode is closed.
- C64 and C128 authoritative verification are green.
