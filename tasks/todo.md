# Active Task Scratchpad

This file is a temporary working scratchpad.

## Role
- Put the current task plan here while work is in progress.
- Keep only active checklists, current verification steps, and short working notes.
- Move durable completed-work notes to `commodore/BUILDPLAN_HISTORY.md`.
- Keep the long-lived active backlog in `commodore/BUILDPLAN.md`.

## Current Status
- Working on the cautious reintroduction of OPT‑VDC enhancements without retriggering the low‑RAM/overlay corruption that caused the recent dungeon/town hang.

### Objective
- Revisit the VDC renderer (`render_viewport`, scroll helpers, and screen helpers) and plan a phased return of the block-copy + occupancy optimizations, ensuring every new helper/data block lives inside `RuntimeLowData`, avoids `$D000-$DFFF`, and keeps the runtime layout assertions satisfied.

### Plan
- [x] Step 1: Review the current `commodore/c128/dungeon_render_vdc.s`/`screen_vdc.s` flow and the temporary OPT-VDC patchset to understand where helpers, buffers, and data must live so we can pin future additions to the correct segments.
- [ ] Step 2: Draft the “safe VDC optimization path” roadmap (block copy, row buffers, occupancy caches) with explicit placement guidelines (e.g., `.segment RuntimeLowData` for helpers, `.assert`s for I/O-hole avoidance, tracker for bank ownership) so future edits don’t drift into unsafe memory.
- [ ] Step 3: Define the gating verification steps (KickAssembler `build128`, memory-map review, targeted smoke tests) that each new VDC change must pass before we commit again, and note how we’ll capture lessons if we hit regressions.
### Step 2 details
- **Phase A – Block-copy helpers**: Implemented `rvsd_block_copy_chars`, `rvsd_block_copy_attrs`, and `rvsd_issue_block_copy` plus the supporting zero-page scratch bytes inside `RuntimeLowData`; we now stage the dest/source pairs before writing the copy length and triggering the VDC block-copy engine via registers 24/30. Everything stays in runtime-low RAM and the helpers are exposed through `screen_vdc.s`.
- **Phase B – Row-batching & occupancy caches**: Add `rv_map_row_buf`, `rv_row_monsters`, `rv_row_items` (and their populations) to the low-RAM segment. Use `map_bulk_enter/exit` before the row loops and keep the per-row caches in the same segment so calls from `render_viewport` never jump into an unloaded helper. Document in the roadmap which bank is active when each helper runs and add `.assert` checks or comments for the I/O-hole boundaries.
- **Phase C – VDC burst streaming**: Replace the repeated `for` loops that poke register 31 with a single `rv_stream_buffer` that holds `rv_stream_buf_lo/hi` for the active row buffer. Register this helper and its workspace in `RuntimeLowData` so the renderer can call it safely even under Bank 0/1 switching.

### Verification
- [x] `make -C commodore/c128 build128` (baseline with the 2 MHz toggle + new block-copy helpers; still only the historical “Ranged-fire handler stays out of I/O hole=false” assertion)
- [ ] Memory map / `.vs` diff review to confirm new helpers/buffers stay below $C000 and outside the I/O hole once they’re added

### Review
- Record any further lessons about runtime segments, banked helpers, or overlay collisions in `tasks/lessons.md` while the plan is active.

### Step 3 details
- **Build verification:** `make -C commodore/c128 build128` must pass after every staged addition (particularly after we add new helpers/buffers) and the existing `.assert` for "Ranged-fire handler stays out of I/O hole" should remain the only failure noted before reintroduction.
- **Memory-map review:** Whenever we add a new helper or buffer, run `rg`/`sed` on the emitted `.map` or `main.sym` to confirm the symbol resides below `$C000` (or in `RuntimeLowData`) and not in `$D000-$DFFF`. Document these placements with inline comments or `.assert`s.
- **Targeted runtime check:** After Phase B or C adds new caches, run the `town_overlay` or `dungeon_overlay` path (via limited smoke or `make test128-fast-smoke` once Phase C is stable) to ensure we no longer hang in dungeon/town creation.
