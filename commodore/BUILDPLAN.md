# Moria C64/C128 — Active Build Plan

> Active outstanding work only.
> See [DESIGN.md](DESIGN.md) for architecture reference and [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed phases, fixes, and reviews.

---

## Active Scope (2026-04-26)

- Keep this file limited to open phases, cleanup work, and features.
- Completed current-state details and resolved task notes through 2026-04-26 are archived in [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md).

## Open Phases / Display Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `UI-80` refine the C128 80-column layout to a true Umoria-style left status panel | High | Medium | No | Treat as a refinement of the shipped 80-column baseline, not a contradiction of 10.7 completion. |

## Open Test / Cleanup Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `OPT-STATUS-ROW23` split the bottom status row into field-level redraws | Medium | Medium | No | The current status renderer now redraws only dirty rows, but row 23 still clears and repaints `HP`, `MP`, `AC`, `AU`, and hunger/state as a unit. A later optimization pass should keep the forced full-repaint contract for screen/status clears while giving row 23 fixed-width field redraw helpers so single-field changes like mana ticks do not visibly flash the whole bottom row. |
| Low | `OPT-OVERLAY-PRESSURE-RESERVE` further magic/spell/UI overlays only if memory pressure returns | High | Low | No | Conditional reserve item only; do not proactively move more product paths into overlays unless main-segment pressure returns. |

## Open Features

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `FEAT-VMS-LOOK-SEMANTICS` move `look` to the VMS-Moria directed ray contract | High | Medium | No | Replace the current drifted `look` behavior with the simpler VMS-style directed ray scan and message flow. Treat this as a redesign, not an incremental bug fix: `look` has already produced repeated regressions in the current port, so the next pass should re-anchor on upstream VMS semantics (directed rays, repeated messages along the ray, no interactive recall handoff) before changing code. |
| Medium | `FEAT-ITEM-STATS` restore upstream-style item stat descriptions and enchant visibility | High | High | No | VMS-Moria `objdes()` and UMoria `itemDescription()` expose per-item magic stats in descriptions, including weapon `(+to_hit,+to_dam)`, armor `[base_ac,+to_ac]`, charges, and relevant `p1`-style bonuses. The Commodore port currently hides all of that and only carries a simplified single-instance bonus field (`inv_p1`), so enchant weapon/armor effects are real but mostly invisible to the player. A proper pass should decide whether to extend the item instance model toward separate `to_hit` / `to_dam` / `to_ac` fields or preserve the simplified model and at least render the stored bonus consistently, then thread that through inventory, equipment, stores, identify/recall text, and any spell/scroll messaging that depends on visible stat changes. |
