# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Status
- No active task in progress.
- Most recent completed work:
  - backlog correction for the stale `spell_effects` platformization note
  - platformized `dungeon_gen` BFS queue ownership through C64/C128 memory config

## Plan
- No active implementation plan.

## Findings

### 1. `spell_effects.s` cleanup item is stale
- The active BUILDPLAN line still says:
  - `spell_effects.s:574` screen-to-color RAM assumption
- That pointer is no longer real.
- Current code at `commodore/common/spell_effects.s:555-561` already routes the only live display-specific spell effect (`eff_bolt` flash) through the screen helper boundary:
  - `screen_flash_at`
  - and, on C128, `screen_flash_set_color` / `screen_flash_reset_color`
- The actual platform-specific behavior now lives in:
  - `commodore/c64/screen.s`
  - `commodore/c128/screen_vdc.s`
- Current line `574` in `spell_effects.s` is just `stx zp_temp2`.

### 2. `dungeon_gen.s` cleanup item is real
- `commodore/common/dungeon_gen.s:1756-1759` still hardcodes:
  - `BFS_QUEUE = $0400`
  - `BFS_QUEUE_MAX = 512`
- The shared generator is therefore assuming:
  - a 1 KB scratch window at `$0400-$07FF`
  - and, on C64, that this is screen RAM and safe during generation
- The current shipping hot path no longer calls `verify_connectivity`, but the code still exists and the shared assumption is still wrong architecturally.

## Recommended Design

### A. `spell_effects.s`
- Do not do a code refactor now.
- Treat this as a backlog wording cleanup, not an implementation task.
- Recommended BUILDPLAN correction:
  - remove the stale `spell_effects.s:574` wording
  - either drop the item entirely, or retitle it narrowly as:
    - `spell_effects` transient flash API remains platform-specific
- Merge judgment:
  - not a blocker
  - not worth touching unless a new concrete bug appears

Why:
- The cleanup already happened in substance when the bolt flash path was moved behind screen helpers.
- A new abstraction layer now would likely just add churn around a working interface.

### B. `dungeon_gen.s`
- This is the legitimate cleanup item.
- Keep the BFS queue design exactly as scratch data, but make the ownership platform-defined instead of hardcoded in shared code.

Recommended shape:
1. Define platform constants in the memory layer:
   - C64 `memory.s`
   - C128 `memory128.s`
2. Use names such as:
   - `DUNGEON_GEN_BFS_QUEUE_BASE`
   - `DUNGEON_GEN_BFS_QUEUE_MAX`
   - optionally `DUNGEON_GEN_BFS_QUEUE_END`
3. Replace raw `$0400` in `commodore/common/dungeon_gen.s` with those platform constants.
4. Add compile-time asserts in the platform memory files proving:
   - the queue size remains 1 KB
   - the chosen scratch region is actually owned and non-overlapping
5. Update comments so the contract is explicit:
   - scratch only
   - not executable
   - safe because generation redraws afterwards

Recommended first destination:
- Keep `$0400-$07FF` on both C64 and C128 for now.
- Only platformize the ownership.
- Do not turn this into a relocation project unless there is a real bug or a future feature needs visible screen RAM during generation again.

Why:
- The real problem is not the address itself; it is that the address is buried in shared logic instead of being a platform memory contract.
- That makes future work brittle, especially after the recent generation busy UI and larger-map work.

## Pitfalls To Avoid
- Do not turn the `dungeon_gen` cleanup into a banking change.
- Do not try to make the BFS queue executable or move it into low-RAM/runtime-loaded code regions.
- Do not use `$0800-$0BFF` or `$E000-$EFFF` for any new permanent code/data ownership just because they look convenient.
- Do not widen the `spell_effects` work into a new shared UI abstraction without a concrete bug driving it.

## Consultant Second Opinion
- The consultant agreed that:
  - `spell_effects` is mostly a stale backlog note now
  - `dungeon_gen` is the real cleanup item
  - `dungeon_gen` should be platformized as a named scratch contract, not turned into a bigger memory redesign

## Review
- `spell_effects`:
  - the stale `spell_effects.s:574` backlog item was removed from `BUILDPLAN.md`
  - no gameplay code change was needed there
- `dungeon_gen`:
  - added `DUNGEON_GEN_BFS_QUEUE_BASE/MAX/END` to both:
    - `commodore/c64/memory.s`
    - `commodore/c128/memory128.s`
  - replaced raw `BFS_QUEUE` constants in `commodore/common/dungeon_gen.s` with those platform-owned memory constants
  - added asserts proving the queue remains page-aligned and stays inside the intended scratch window
- Verification passed:
  - `make -C commodore/c64 build`
  - `make -B -C commodore/c128 build128`
  - `make test128-fast`
