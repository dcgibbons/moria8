# Dungeon Generation Contract

Load this document for generation stages, room/tunnel/door/stair/streamer
topology, generation RNG, connectivity, or generation performance. Rendering a
finished map does not require this contract.

## Authority And Goal

- Shared production implementation: `core/dungeon_gen.s`
- Dimensions and room-table capacity: `core/dungeon_data.s` through HAL layout
- Default upstream oracle: pinned VMS Moria dungeon generation sources
- Secondary oracle: pinned Umoria generation sources when VMS is unclear or
  divergent

The algorithm is shared across C64, C128, and Plus/4. Platform conditionals may
select dimensions and capacity constants. A platform-specific generation stage
requires a documented hardware constraint and explicit design approval.

## Production Pipeline

`dungeon_generate` currently owns this exact stage order:

1. reset traps and `blank_cave`
2. `place_rooms`
3. `shuffle_rooms`
4. `connect_rooms`
5. `fill_cave_granite`
6. `place_streamers`
7. `place_junction_doors`
8. assign special room and seal vault entrance
9. `place_stairs_dungeon`
10. place traps and secrets
11. `darken_rooms`
12. `position_player_dungeon`

Changing stage order is a behavioral change even when each individual stage is
unchanged. Generation scratch flags are not persistent terrain semantics and
must be consumed before the stage that repurposes them.

## Observed Production Snapshot

This table is a descriptive snapshot of `core/dungeon_gen.s`, checked
2026-07-10. It is implementation evidence, not semantic authority. Determine
intended behavior from accepted ledger decisions and the pinned upstream oracle
before preserving or changing an observed formula. A deliberate change to a
settled Moria8 rule or resolution of an open choice requires a ledger update.

| Property | Observed production behavior |
| --- | --- |
| Room selection | Always perform 32 random slot rolls; each slot is accepted at most once and no more are accepted after platform `MAX_ROOMS`, preserving all 32 RNG draws |
| Room size | Upstream independent extents: width `3..23` from `rng(11)+1 + rng(11)+1 + 1`; height `3..8` from `rng(4)+1 + rng(3)+1 + 1` |
| Room spacing | Derived slot centers; `ROOM_GAP` and `ROOM_EDGE_PAD` are not used by `place_rooms` |
| Room retries | No per-room retry loop; `MAX_ROOM_RETRIES=20` is currently dead |
| Room capacity | C128 `MAX_ROOMS=21`; C64/Plus4 `MAX_ROOMS=8` |
| Panel model | Shared 66x22 upstream-style panels and derived half-panel slots |
| Tunnel tuning | A current valid direction is retained for rolls `<70`; on the remaining rolls, only `4` of `36` outcomes choose a random cardinal direction and the rest choose a direction toward the target |
| Doors | Room-wall penetration candidates are resolved during tunnel materialization; their adjacent temporary wall guards persist until `fill_cave_granite`; later junction candidates are resolved by `place_junction_doors`; both require a straight two-sided passage through opposing wall jambs |
| Stairs | Exactly one tracked up and two tracked down coordinates; thresholds 3..0 each get 20 attempts (80 total), then an unvalidated random floor fallback; `STAIR_PLACE_TRIES=96` is dead |
| Streamers | Placed after granite and before doors; density constant `5` |

Settled topology invariants:

- all passable room interiors belong to the player's legal movement component
  after generation
- corridors are one tile wide except at legitimate intersections, room
  interiors, or documented special structures
- a door cannot be bypassed by an adjacent open route serving the same boundary
- doors do not terminate in inaccessible rock or replace arbitrary interiors
- rooms remain in bounds and retain wall/interior metadata
- every retry loop has a statically identifiable finite bound or monotonic
  progress measure, plus an adversarial-RNG test when changed

Provenance: connectivity and room/tunnel/door topology derive from pinned VMS
Moria `source/include/generate.inc` (`build_room`, tunnel construction, room-wall
door placement, and junction-door placement) and are retained as explicit
Moria8 correctness requirements by DGN-008. The one-tile corridor rule is the
Moria8 representation of upstream cardinal tunnel carving; documented room
interiors and true intersections are its exceptions.

Legal, unique, reachable fallback stairs are desired but not yet a settled or
enforced invariant because the current final fallback is unchecked (DGN-006).
Do not invent its policy during an unrelated repair.

## RNG And Statistical Acceptance

Use the project RNG. Preserve draw order unless a deliberate statistical change
is recorded. Every changed random range must document inclusive/exclusive bounds
and the reduction method.

The desired comprehensive generation gate would include:

- a fixed seed corpus shared by all platforms
- permanent regression seeds for every discovered topology failure
- aggregate predicates for room count/position, connectivity, corridor width,
  door validity, stair policy, and streamer distribution
- first-failing seed and stage in failure output
- a bounded randomized soak beyond the fixed corpus

Most of that gate is not implemented and is not a prerequisite for an ordinary
repair under a settled invariant. Require focused production evidence and state
the residual gap. A change that directly selects statistical tolerances,
generation distributions, or performance policy must first establish the
relevant corpus, aggregate validator, or budget in a dedicated design and
infrastructure change.

## Decision Ledger

Accepted rows dated 2026-07-09 record explicit maintainer decisions from the
work16 dungeon-generation design review; this ledger is their durable record.

| ID | Status | Owner/date | Scope and selected rule | Evidence/enforcement | Supersedes |
| --- | --- | --- | --- | --- | --- |
| DGN-001 | Accepted | Project maintainer, 2026-07-09 | One shared generation algorithm; platforms vary only through named capacity/layout constants unless hardware forces otherwise | maintainer design decision; structural enforcement `NOT IMPLEMENTED` | earlier divergent C128 paths |
| DGN-002 | Accepted | Project maintainer, 2026-07-09 | Production tracks one up and two down stairs rather than upstream variable object counts | `place_stairs_dungeon`; C64 dungeon test count | none |
| DGN-003 | Open | Project maintainer, 2026-07-09 | Room-center distribution tolerance and canonical seed corpus | `NOT IMPLEMENTED` | none |
| DGN-004 | Open | Project maintainer, 2026-07-09 | Area-normalized streamer density/shape tolerance | `NOT IMPLEMENTED` | none |
| DGN-005 | Open | Project maintainer, 2026-07-09 | Platform generation-time budgets | `NOT IMPLEMENTED` | none |
| DGN-006 | Open | Project maintainer, 2026-07-09 | Stair fallback validity/uniqueness policy | current fallback is unchecked; no policy gate | none |
| DGN-007 | Open | Project maintainer, 2026-07-09 | Whether `verify_connectivity` belongs in production | helper is C64-unit-test-only; design/RNG/performance analysis required | none |
| DGN-008 | Accepted | Project maintainer, 2026-07-09 | Generated room interiors remain connected through cardinal one-tile tunnels; temporary neighboring room-wall guards persist across tunnel construction; doors occupy straight, two-sided room-wall penetrations or junctions and cannot be bypassed by a parallel opening | maintainer decision; pinned VMS Moria `generate.inc`; focused C64 topology and guard-lifecycle fixtures | earlier ad hoc post-generation door repair rules |
| DGN-009 | Accepted | Project maintainer, 2026-07-10 | Normal rooms use upstream independent left/right/top/bottom extents; tunnel endpoints remain on the original panel-slot center rather than a derived rectangle midpoint | maintainer decision; pinned VMS Moria `build_room`; C64 extent-range and shuffled-slot-center fixtures | symmetric odd-only room approximation |

## Current Conditional Verification Matrix

These are required only where the criterion is already settled. Rows explicitly
delegated to the future-gate table do not block ordinary repairs.

| Change | Required evidence |
| --- | --- |
| Rooms | bounds, overlap/gap, count, maximum capacity; preserve all 32 selection draws unless deliberately changing RNG order |
| Tunnels | reachability, width, intersections, duplicate/parallel passage checks |
| Doors | dead-end, corner, walk-around, room-boundary and junction cases |
| Stairs | settled count policy and normal-placement legal terrain/reachability; record unchecked fallback as residual risk |
| Streamers | count, continuity, and width for the changed fixture; aggregate density/distribution is a future gate |
| Retry/termination | adversarial RNG termination when changing a retry loop; numeric runtime budgets are a future gate |
| Shared algorithm | implementation review of stage entry/order on all platforms; platform constants tested separately |

## Future Acceptance Gates

| Policy area | Status |
| --- | --- |
| Room-center distribution tolerance and canonical corpus | DGN-003, `NOT IMPLEMENTED` |
| Streamer aggregate density/shape tolerance | DGN-004, `NOT IMPLEMENTED` |
| Platform generation-time budgets | DGN-005, `NOT IMPLEMENTED` |
| Stair fallback legality, uniqueness, and reachability | DGN-006, `NOT IMPLEMENTED` |

Screenshots and VICE snapshots are reproductions, not the topology oracle. Tests
must inspect generated map data.

## Executable Enforcement

| Invariant | Current gate | Command/status |
| --- | --- | --- |
| C64 room/corridor/shuffle/connectivity/stairs/streamer/door fixtures | `platforms/commodore/c64/tests/test_dungeon.s` | `TEST_FILTER='dungeon' make test64` |
| C64 full generated-map connectivity | same suite calls test-only `verify_connectivity` | implemented for tested seed/path only |
| C128 focused generation-routine integration | `platforms/commodore/c128/tests/test_soak128.s` imports production generation with test-local startup/MMU wrappers | `TEST_FILTER='soak128' make test128`; shipping overlay/loader/dispatch coverage `NOT IMPLEMENTED` |
| C128 dungeon renderer color path | `platforms/commodore/c128/tests/test_dungeon128.s` | does not execute production generation |
| Plus/4 generation entry | Plus/4 dungeon-entry smoke | `TEST_FILTER='^dungeon_entry_plus4$' make testplus4`; topology coverage incomplete |
| Shared fixed seed corpus and permanent failure-seed registry | none | `NOT IMPLEMENTED` |
| Aggregate topology/statistical validator with first failing seed/stage | none | `NOT IMPLEMENTED` |
| Platform generation performance budget | none | `NOT IMPLEMENTED` |
| Automatic enforcement that all platforms use only the shared generation stages plus constants | none | `NOT IMPLEMENTED`; DGN-001 requires review |
