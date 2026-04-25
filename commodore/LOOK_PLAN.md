# FEAT-VMS-LOOK-SEMANTICS Plan

## Purpose

This document is the implementation plan for `FEAT-VMS-LOOK-SEMANTICS`.

The goal is to redesign `look` around a `VMS-Moria` core contract while keeping a few small `Moria8` quality-of-life affordances that fit Commodore hardware well. This is intentionally not an `Umoria` interactive-inspector project.

This plan is decision-complete. It records the locked product direction, the user-facing `look` contract, the implementation shape, the explicit VMS deviations, and the verification expectations.

## Locked Product Decisions

The following choices are fixed for this feature:

- Keep `look` as a directed straight-ray scan.
- Do not import `Umoria` cone/peripheral traversal.
- Do not add `Umoria` all-directions or null-direction `look`.
- Do not add interactive per-target pause flow.
- Do not add look-time monster recall handoff.
- Keep `look` a free action.
- Keep `Moria8` target flash as a presentation affordance on both `C64` and `C128`.
- Change current `Moria8` behavior from first-hit-only to repeated findings along the ray.
- Require current visibility, not remembered-dark knowledge.
- Treat any deviations from strict local `VMS-Moria` behavior as explicit product choices, not accidental drift.

## User-Facing Behavior Contract

The shared gameplay contract for `look` is:

1. Prompt with `Look which direction?`
2. If the player is blind, fail immediately with the blind-look message and do not scan
3. Walk tile-by-tile in the chosen direction
4. Only describe tiles that are currently visible
5. For each interesting visible tile:
   - flash the target cell
   - print its description
   - continue scanning
6. Stop when:
   - sight limit is reached
   - map bounds are exceeded
   - blocked terrain ends the scan
7. If nothing interesting is found, print `You see nothing of interest in that direction.`

This keeps `look` as a fast examine command instead of turning it into a mini interaction mode.

## Upstream Positioning

### `VMS-Moria`

Local `VMS-Moria` is the authoritative source for traversal and scan flow:

- directed-only straight ray
- repeated messages along the ray
- no recall handoff
- no cone search
- no pause-per-target interaction

### `Umoria`

Local `Umoria` is intentionally out of scope for this feature:

- cone/peripheral scan
- all-directions `look`
- target-by-target pause flow
- optional recall handoff
- broader interactive inspection behavior

Those behaviors are useful in their own context, but they are a different product shape with higher code/UI cost and higher regression risk on `C64`/`C128`.

### Current `Moria8`

Current `Moria8` is already closer to `VMS-Moria` than to `Umoria`, but it is still narrower than the target contract:

- straight directed ray
- current-visibility only
- target flash
- first interesting result only

The main redesign is therefore:

- preserve the directed ray
- preserve flash
- remove the first-hit-only limitation
- tighten prompt and message semantics around the `VMS-Moria` contract

## Result Ordering And Tile Semantics

The scan should classify each visited tile in a stable priority order.

Initial intended order:

1. visible monster
2. visible floor item / object
3. interesting terrain / seam / wall-like feature

Behavioral rules:

- current `first interesting thing wins` behavior is removed
- the scan may emit multiple messages across multiple tiles
- same-tile output should stay conservative; do not turn `look` into a layered `Umoria` inspect flow unless a specific VMS parity gap requires it
- terrain coverage should be reviewed against local `VMS-Moria` so `Moria8` does not keep drifting into over-broad narration

## Implementation Shape

Refactor `do_look` in [player_move.s](common/player_move.s) from a single-result early-return scan into a continuation-based directed scan:

- add a `found_any` state for the whole scan
- separate tile classification from continuation/stop decisions
- keep message emission small and deterministic
- preserve `look_flash_target` as the shared platform-owned cue

Prompt handling should stop reusing the generic direction prompt in [dungeon_features.s](common/dungeon_features.s) for `look`. Add a dedicated `look` prompt string and use it only for this command.

Do not build a new interactive `look` framework. The implementation should stay close to the current shared scan path and avoid reopening the larger parity experiment that was previously backed out.

## Explicit Deviations From Strict Local `VMS-Moria`

These are locked product decisions:

- **Blind-first UX**
  - local `VMS-Moria` prompts before rejecting blind `look`
  - `Moria8` should reject blind `look` before prompt for a cleaner user experience

- **Target flash retained**
  - local `VMS-Moria` does not have the current platform flash cue
  - `Moria8` keeps flash because it improves clarity cheaply on both platforms

- **Terrain wording may stay somewhat richer**
  - strict `VMS-Moria` terrain output is narrower than current `Moria8`
  - `Moria8` may keep some useful terrain readability where it is already cheap and stable, as long as traversal and message-flow semantics stay anchored on `VMS-Moria`

## Important Interfaces And Contracts

- `do_look` changes from “describe first interesting target and stop” to “scan ray and report successive findings”
- `look` gets its own direction prompt string: `Look which direction?`
- no changes to the separate recall command/UI contract
- no all-directions `look`
- no new interaction mode or pause/continue loop

## Test Plan

### Behavioral tests

- blind player gets the blind-look message and no scan
- invalid or cancelled direction exits cleanly
- empty directed `look` prints `You see nothing of interest in that direction.`
- a ray with multiple interesting tiles emits multiple descriptions in scan order
- scan stops at blocked terrain or sight limit
- remembered-but-not-currently-visible tiles are not described

### Content tests

- monster on ray is described when currently visible
- floor item on ray is described when currently visible
- terrain/seam/wall reporting matches the locked reduced contract
- if a nearer tile and a farther tile are both interesting, both appear in order

### Regression gates

- `make test64`
- `make test128-fast`
- `make test128-fast-smoke`

Add or extend `look`-focused runtime tests on both platforms so they verify:

- multi-hit scan order
- empty-look message
- blindness handling
- current-visibility-only behavior
- target flash still occurs for reported findings

## Assumptions

- The chosen product direction is `VMS core + QoL`, not strict `VMS-Moria` and not `Umoria` interactive look
- repeated along-ray reporting is desired even though current `Moria8` is first-hit-only
- `Umoria` recall integration remains out of scope and should be treated as a separate future feature if ever desired
- exact wording for some terrain descriptions may remain slightly `Moria8`-specific as long as traversal and message-flow semantics stay anchored on `VMS-Moria`
