# Active Task Scratchpad

This file is a temporary working scratchpad.

## Role
- Put the current task plan here while work is in progress.
- Keep only active checklists, current verification steps, and short working notes.
- Move durable completed-work notes to `commodore/BUILDPLAN_HISTORY.md`.
- Keep the long-lived active backlog in `commodore/BUILDPLAN.md`.

## Current Status
- Active task: PERF-DG-C128 design.
- Goal:
  - make dungeon generation substantially faster, especially on C128 `198x66`
  - show a visible `GENERATING...` busy indicator with a rotating PETSCII spinner on both C64 and C128 during dungeon generation

### Review
- Existing hot-path facts:
  - `dungeon_generate` still does multiple expensive whole-map or near-whole-map passes:
    - `fill_map_rock`
    - `place_streamers`
    - `verify_connectivity` with two full-map `map_bulk_and_all` passes plus live BFS
  - the current connectivity verifier uses `BFS_QUEUE = $0400`, i.e. visible C64 screen RAM
  - C128 generator code pays the shared `:MapRead_ptr*_y()` / `:MapWrite_ptr*_y()` call overhead at every tile access
  - new-game / stairs paths already have a clean transition seam around `overlay_load`, `tramp_level_generate`, `monster_spawn_level`, and `item_spawn_level`
- Important consequence:
  - a visible busy spinner on C64 is incompatible with the current `BFS_QUEUE = $0400` design
  - therefore the busy-indicator work and the BFS scratch cleanup are coupled

## PERF-DG-C128 Design

### Target Outcome
1. Make generation visibly faster in real play, with the biggest win on C128.
2. Show `GENERATING...` plus a rotating PETSCII spinner during generation on both platforms.
3. Do this without reopening the newly-stable C128 banking / overlay contracts.

### Recommended Shape

#### Phase A — Add a real generation-progress UI layer
- Add a small shared helper module, e.g. `generation_busy.s`, with:
  - `generation_busy_begin`
  - `generation_busy_tick`
  - `generation_busy_end`
- Display contract:
  - draw `GENERATING...|`
  - last character rotates through a 4-frame PETSCII spinner modeled on the common CLI pattern `| / - \`
  - store the spinner frames as explicit screen-code bytes, not text literals
- Placement:
  - write directly with `screen_clear` + `screen_put_string`
  - do **not** route through `msg_print`, because this is not normal message history and should not touch the `-MORE-` state machine
- Call sites:
  - `game_new_start`
  - `cmd_stairs_dn`
  - `cmd_stairs_up`
  - recall/teleport paths that call `level_generate`
- `generation_busy_tick` should be throttled by a software counter so the spinner updates frequently enough to feel alive but not so often that screen writes become the new bottleneck

#### Phase B — Remove the current screen-RAM/BFS coupling
- Replace `BFS_QUEUE = $0400` with an explicit platform-owned generation scratch region
- Why this must happen first:
  - C64 screen RAM is currently the BFS queue, so any visible spinner/message would be overwritten during connectivity validation
  - C128 80-col hides that problem because it renders through VDC, but the shared design must satisfy both platforms
- Preferred redesign:
  - stop using a live tile-BFS queue in the shipping generation path
  - keep the strong connectivity proof in tests/diagnostics
  - replace runtime connectivity validation with a cheaper structural guarantee

#### Phase C — Remove or narrow the most expensive runtime validation
- The current `verify_connectivity` is a likely major cost center:
  - two full-map `map_bulk_and_all` passes
  - BFS over passable tiles
  - queue bookkeeping
- Recommended production behavior:
  - do **not** run the full tile-BFS verifier in the shipping fast path
  - rely on the room graph construction:
    - `place_rooms`
    - `shuffle_rooms`
    - `connect_rooms` circular chain
  - keep full connectivity validation in:
    - test suites
    - soak/diagnostic builds
    - optional debug/runtime flag if needed
- If runtime verification must remain:
  - downgrade it to a cheaper room-level verification rather than a full tile flood-fill

#### Phase D — Attack the C128-specific hot path
- After the structural cleanup above, optimize the remaining heavy loops for C128 specifically.
- First target: reduce per-tile MMU wrapper cost inside `dungeon_gen.s`
- Preferred direction:
  - add C128-safe bulk helpers for generation-time map operations
  - keep those helpers in the established MMU/common-helper model, not in ad hoc low-RAM executable blobs
  - avoid designs that require running the `$E000` overlay while Bank 1 is the ambient execution bank
- Good candidates:
  - `fill_map_rock`
  - the `map_bulk_and_all` use sites that survive Phase C
  - streamer carving inner loops
  - repeated room-rectangle fill/darken paths
- Bad direction:
  - don’t start by moving more resident code around again
  - don’t repurpose `$0800-$0BFF`
  - don’t rely on the live `$E000-$EFFF` overlay window as a compute staging area

#### Phase E — Extend the visible busy period beyond just `dungeon_generate`
- User-perceived latency is not only map carving.
- The busy indicator should stay active across:
  - `overlay_load` for dungeon-gen overlay
  - `tramp_level_generate`
  - `monster_spawn_level`
  - `item_spawn_level`
  - final `update_visibility`
- This can be done cheaply by:
  - calling `generation_busy_tick` between major phases
  - optionally adding sparse hooks inside monster/item spawn if those are still visibly expensive after Phase C

### Spinner / UX Contract
- Message text: `GENERATING...`
- Spinner cell: one extra trailing character
- Frame sequence:
  - nominally `|`, `/`, `-`, `\\`
  - if backslash screen-code mapping is awkward on one platform, keep the 4-frame intent but substitute an equivalent PETSCII glyph
- Suggested placement:
  - centered on a cleared screen for both platforms
  - use a fixed row, not the message scroller
- Do not blank the display during generation once the spinner path is active
  - on C64, that means the current `screen_blank` call around level generation must be removed or moved after the busy layer is finished

### Risks / Constraints
- The spinner requirement forces the BFS queue cleanup on C64; otherwise the visible text will be corrupted.
- Removing full tile-BFS runtime verification trades some safety for speed, so the test/soak coverage must carry that confidence instead.
- C128 generation helpers must respect the existing MMU/common-helper rules; this is not a place to improvise new executable low-RAM regions.
- The fastest possible design is likely algorithmic first, not micro-optimizing every tile write.

### Recommended Implementation Order
1. Add `generation_busy_begin/tick/end` and wire them into:
   - new game
   - stairs down
   - stairs up
   - recall path
2. Replace the `BFS_QUEUE = $0400` assumption with a non-visible design.
   - preferred: remove live tile-BFS from the shipping path entirely
3. Keep or add targeted/soak tests that still exercise full connectivity guarantees.
4. Re-measure real dungeon-generation latency.
5. If still too slow on C128, add C128-specific generation bulk helpers for the surviving hot loops.
6. Only after that consider narrower micro-optimizations inside `dungeon_gen.s`.

### Verification
- Design only in this step; no code changed yet.
- When implementation starts, the first required checks should be:
  - `make -C commodore/c64 build`
  - `make -B -C commodore/c128 build128`
  - `make test128-fast`
  - targeted runtime/smoke coverage for stairs/new-game transitions on both platforms
  - manual validation that the spinner stays visible and animates during generation
