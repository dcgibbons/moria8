# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Status
- No active task in progress.
- Most recent completed work:
  - `PERF-DG-C128` first implementation pass
  - faster dungeon generation in shipping builds
  - visible full-screen `GENERATING...` feedback on dungeon generation transitions

## Review
- Final behavior intentionally uses a static `GENERATING...` message, not a spinner.
- Reason:
  - after the generation-speed win, the remaining safe phase seams were too coarse for a spinner that felt truthful
  - a static busy message gave correct feedback without implying fine-grained progress that the engine does not currently expose
