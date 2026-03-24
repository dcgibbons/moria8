# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Task
- [x] Add the new refactor backlog intake to `commodore/BUILDPLAN.md`.
- [x] Record the triage/design notes for those refactors here.

## Refactor Backlog Intake

Consultant triage matched the repo reality closely:

- `REF-HAL` is the main structural refactor.
- Shared input tables/constants are worthwhile cleanup once the platform surface is clearer.
- Shared numeric formatting helpers are safe low-risk deduplication.
- C128 trampoline cleanup is worthwhile, but only after the callable surface stabilizes.
- Monster AoS -> SoA is a real performance idea, but it is risky enough that it should stay far in the backlog until profiling justifies it.

## Recommended Order

1. `REF-HAL`
2. `REF-INPUT-TABLES`
3. `REF-CONSTS`
4. `REF-NUMFMT`
5. `REF-C128-TRAMP`
6. `REF-MON-SOA` only if profiling still says it is worth the churn

## Item Notes

### `REF-HAL`
- Goal: move platform-owned runtime services out of shared gameplay files such as `commodore/common/game_loop.s`.
- Likely shape:
  - define a thin platform-services surface in common code
  - keep gameplay flow in common code
  - push C64/C128 quirks into platform-owned entry points
- This should come before any attempt to abstract more C128 trampolines, because it clarifies which calls actually need trampolines.

### `REF-INPUT-TABLES`
- Share:
  - command ids
  - direction tables
  - PETSCII-to-command lookup tables where they are truly identical
- Do not share:
  - platform keyscan
  - modifier/chord decode
  - C128-specific input timing quirks

### `REF-CONSTS`
- Safe target for constants that are genuinely shared:
  - `CMD_*`
  - selected `SC_*`
  - shared color constants
- Do not force platform-specific scan-code or display quirks into fake common headers.

### `REF-NUMFMT`
- Shared target:
  - `screen_put_hex`
  - `screen_put_decimal`
  - `screen_put_decimal_16`
- Keep platform drivers separate; only the formatter logic should move.
- The shared helper should depend only on a platform `screen_put_char` primitive.

### `REF-C128-TRAMP`
- Use a higher-level macro to generate repetitive save-bank / switch / call / restore trampolines in `commodore/c128/main.s`.
- This is cleanup, not a behavior change.
- It should follow `REF-HAL`, not precede it.

### `REF-MON-SOA`
- Potential upside:
  - cheaper field access in `monster.s` / `monster_ai.s`
  - less pointer math and indirect indexing
- Real risks:
  - touches active gameplay state layout
  - touches save/load assumptions
  - touches tests and every monster accessor
- This should stay backlog-only until profiling proves the win is worth the churn.

## Outcome

- `commodore/BUILDPLAN.md` now tracks the refactor ideas as explicit backlog items instead of leaving them as a loose proposal.
- The backlog wording now reflects the real dependency order:
  - `REF-HAL` before `REF-C128-TRAMP`
  - `REF-MON-SOA` only as a late, profiling-justified refactor
