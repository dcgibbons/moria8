# Active Task Scratchpad

Active-only backlog. Completed task scratchpad material through 2026-04-26 is archived in `commodore/BUILDPLAN_HISTORY.md`.

## Active Backlog

- [ ] `BUG-TRAP-HP-UNDERFLOW`: reproduce the rockfall-trap HP corruption from the live gameplay path before attempting a product fix.
- [ ] `BUG-C128-TITLE-L-GAMEWRITTEN-SAVE-REPRO`: reproduce the game-written save title-load path.
- [ ] C64 rendering backlog:
  - [ ] Add dedicated disk-backed C64 title-load smokes for the real `L` path.
- [ ] `FEAT-VMS-LOOK-SEMANTICS`: decide whether to keep the compact VMS-style baseline or fund a larger parity push later.
  - [ ] Add C128 unit/smoke coverage for shared `look` changes.
  - [ ] Run full regression gates before human playtesting.
- [ ] `BUG-LONG-MESSAGE-TRUNCATION-POLISH`: wrap long combat/status messages cleanly across message rows 0-1, preserve sensible `-more-` behavior, and decide whether history stores wrapped/continued lines or wider entries.

## Build Plan Cross-References

- [ ] `UI-80`: refine the C128 80-column layout to a true Umoria-style left status panel.
- [ ] `OPT-STATUS-ROW23`: split bottom status row redraws into field-level helpers.
- [ ] `OPT-OVERLAY-PRESSURE-RESERVE`: consider further magic/spell/UI overlays only if main-segment pressure returns.
- [ ] `FEAT-ITEM-STATS`: restore upstream-style item stat descriptions and enchant visibility.
