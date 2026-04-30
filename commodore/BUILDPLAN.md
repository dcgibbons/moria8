# Moria C64/C128 — Active Build Plan

> Active outstanding work only.
> See [DESIGN.md](DESIGN.md) for architecture reference and [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed phases, fixes, and reviews.

---

## Active Scope (2026-04-29)

- Keep this file limited to open phases, cleanup work, and features.
- Completed current-state details and resolved task notes through 2026-04-29 are archived in [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md).

## Open Phases / Display Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `UI-80` refine the C128 80-column layout to a true Umoria-style left status panel | High | Medium | No | Treat as a refinement of the shipped 80-column baseline, not a contradiction of 10.7 completion. |

## Open Test / Cleanup Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| High | `TEST-C128-BLANK-SAVE-DISK-SMOKE` add a real C128 product-path blank save-disk initialization smoke | Medium | High | Yes | Boot the product disk, attach a blank drive-9 save disk, drive Disk Setup through initialization, and verify the save image contains a valid sequential `MORIA8.ID`. The `disk_swap128` unit is useful but cannot be the closure gate for live disk transactions. |
| Medium | `OPT-STATUS-ROW23` split the bottom status row into field-level redraws | Medium | Medium | No | The current status renderer now redraws only dirty rows, but row 23 still clears and repaints `HP`, `MP`, `AC`, `AU`, and hunger/state as a unit. A later optimization pass should keep the forced full-repaint contract for screen/status clears while giving row 23 fixed-width field redraw helpers so single-field changes like mana ticks do not visibly flash the whole bottom row. |
| Low | `OPT-OVERLAY-PRESSURE-RESERVE` further magic/spell/UI overlays only if memory pressure returns | High | Low | No | Conditional reserve item only; do not proactively move more product paths into overlays unless main-segment pressure returns. |

## Open Features

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `FEAT-VMS-LOOK-SEMANTICS` move `look` to the VMS-Moria directed ray contract | High | Medium | No | Replace the current drifted `look` behavior with the simpler VMS-style directed ray scan and message flow. Treat this as a redesign, not an incremental bug fix: `look` has already produced repeated regressions in the current port, so the next pass should re-anchor on upstream VMS semantics (directed rays, repeated messages along the ray, no interactive recall handoff) before changing code. |
