# Active Task Scratchpad

Active-only backlog. Completed task scratchpad material through 2026-04-29 is
archived in `commodore/BUILDPLAN_HISTORY.md`.

## Reported Failure Gate

None.

## Active Backlog

- [ ] `TEST-C128-BLANK-SAVE-DISK-SMOKE`: add a real C128 product-path blank
      save-disk initialization smoke.
  - [ ] Boot the product disk.
  - [ ] Attach a blank drive-9 save disk.
  - [ ] Drive Disk Setup through initialization.
  - [ ] Verify the save image contains a valid sequential `MORIA8.ID` marker.
  - [ ] Treat mocked `disk_swap128` coverage as diagnostic only, not closure
        for the live disk transaction.
- [ ] `BUG-TRAP-HP-UNDERFLOW`: reproduce the rockfall-trap HP corruption from
      the live gameplay path before attempting a product fix.
- [ ] `C64-TITLE-LOAD-SMOKE`: add dedicated disk-backed C64 title-load smoke
      coverage for the real `L` path.
- [ ] `FEAT-VMS-LOOK-SEMANTICS`: decide whether to keep the compact VMS-style
      baseline or fund a larger parity push later.
  - [ ] Add C128 unit/smoke coverage for shared `look` changes.
  - [ ] Run full regression gates before human playtesting.
- [ ] `BUG-LONG-MESSAGE-TRUNCATION-POLISH`: wrap long combat/status messages
      cleanly across message rows 0-1, preserve sensible `-more-` behavior,
      and decide whether history stores wrapped/continued lines or wider
      entries.

## Build Plan Cross-References

- [ ] `UI-80`: refine the C128 80-column layout to a true Umoria-style left
      status panel.
- [ ] `OPT-STATUS-ROW23`: split bottom status row redraws into field-level
      helpers.
- [ ] `OPT-OVERLAY-PRESSURE-RESERVE`: consider further magic/spell/UI overlays
      only if main-segment pressure returns.

## Review Notes

- 2026-04-29: C128 save/load transport optimization completed and archived in
  `commodore/BUILDPLAN_HISTORY.md`.
