# Active Task Scratchpad

This file is a temporary working scratchpad.

## Role
- Put the current task plan here while work is in progress.
- Keep only active checklists, current verification steps, and short working notes.
- Move durable completed-work notes to `commodore/BUILDPLAN_HISTORY.md`.
- Keep the long-lived active backlog in `commodore/BUILDPLAN.md`.

## Current Status
- Pickup-triggered BUG-LIT is fixed.
- The umbrella BUG-LIT issue stays open until monster-death and other forced-redraw triggers are rechecked.

### Objective
- Reproduce and fix the remaining dark-room redraw inconsistency that still reveals hidden room tiles after pickup/full redraw.
- Determine whether the bug is in room/light state, the visibility contract, or local-vs-full redraw divergence.

### Plan
- [x] Step 1: Re-anchor on the user repro and inspect the current BUG-LIT-related visibility, pickup, and redraw paths.
- [ ] Step 2: Add or strengthen a test that reproduces the remaining dark-room pickup/full-redraw mismatch.
- [ ] Step 3: Implement the narrowest fix that makes local and full redraw agree in the dark-room case.
- [ ] Step 4: Verify with focused tests plus the normal build/C128 fast suite before declaring BUG-LIT closed again.

### Review
- The earlier `light_room_x` / `eff_light_room` fix removed one real state-drift bug but did not close the full issue.
- The later `cmd_pickup -> command_result_main_or_status_only` change fixed the live gold-pickup repro.
- Do not close the umbrella BUG-LIT item until kill/death redraw cases are also rechecked.
