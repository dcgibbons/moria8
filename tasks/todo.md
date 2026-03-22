# Active Task Scratchpad

This file is a temporary working scratchpad.

## Role
- Put the current task plan here while work is in progress.
- Keep only active checklists, current verification steps, and short working notes.
- Move durable completed-work notes to `commodore/BUILDPLAN_HISTORY.md`.
- Keep the long-lived active backlog in `commodore/BUILDPLAN.md`.

## Current Status
- No active task.
- BUG-LIT is closed as of `fix dark-room redraw after visibility updates` plus the earlier pickup and room-lighting fixes.
- C128 VDC optimization work remains paused.

### Review
- BUG-LIT required three separate fixes:
  - synchronize `room_lit[]` with per-tile `FLAG_LIT`
  - stop forcing full redraw on `cmd_pickup`
  - stop forcing full redraw on clean-scene `command_result_main_or_update_visibility` tails
- Keep treating long-standing redraw bugs as multi-trigger families until gameplay repros are cleared, not just one code path.
