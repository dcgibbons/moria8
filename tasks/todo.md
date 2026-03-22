# Active Task Scratchpad

This file is a temporary working scratchpad.

## Role
- Put the current task plan here while work is in progress.
- Keep only active checklists, current verification steps, and short working notes.
- Move durable completed-work notes to `commodore/BUILDPLAN_HISTORY.md`.
- Keep the long-lived active backlog in `commodore/BUILDPLAN.md`.

## Current Status
- No active task.
- BUG-1 is closed as of the poison/death HP corruption fix.
- C128 VDC optimization work remains paused.

### Review
- BUG-1 had two distinct causes:
  - poison/starvation damage could underflow HP to `$FFFF` before death handling
  - status redraw could leave stale trailing digits because row 23 was redrawn without clearing variable-width numeric fields first
- Fix both the state mutation and the display path when a bug report shows “bad number on screen”; one is often hiding the other.
