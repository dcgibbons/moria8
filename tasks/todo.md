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
- [ ] `PERF-C128-SAVE-LOAD-SLOW`: C128 save/load is far slower than expected;
      measure the current path and identify whether the cost is byte I/O,
      status polling, modal reloads, disk prompts, or channel/MMU wrappers.
  - [x] Current save size estimate: 15,603 bytes total = 2,533 non-map bytes,
        13,068 C128 map bytes, and 2 checksum bytes.
  - [x] Current C128 byte path cost estimate: save performs about 31,206
        KERNAL byte/status calls; load performs about 46,805 KERNAL
        byte/status calls because each byte checks `READST` before and after
        `CHRIN`.
  - [ ] Design a faster C128-safe sequential I/O path. Candidate direction:
        keep KERNAL mode across non-map blocks and add a map-specific loop that
        avoids wrapper-managed enter/exit on every byte while preserving the
        `READST` safety added for short/corrupt saves.
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
