# Moria C64/C128 — Active Build Plan

> Active outstanding work only.
> See [DESIGN.md](DESIGN.md) for architecture reference and [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed phases, fixes, and reviews.

---

## Current State (2026-04-01)

- All core phases 1–9 are complete.
- C128 split, extended-memory database path, larger dungeon, hardened execution boundary, and the current 80-column baseline are complete.
- The Commodore build is centered on [Makefile](Makefile), with the root [Makefile](../Makefile) acting as a thin wrapper.
- Shipping disk artifacts are now split by platform:
  - C64: [out/moria8-c64.d64](out/moria8-c64.d64)
  - C128: [out/moria8-c128.d71](out/moria8-c128.d71)
- C64 now has a working boot-art path that loads a separate `bootart64` asset, copies it into a VIC-safe hidden-RAM bitmap layout, and keeps it visible through the later `MORIA64` load.
- C128 now has a working native 80-column boot-art path that loads a generated VDC custom-charset poster helper, keeps it visible through the later `MORIA128` load, then restores the normal charset contract before the title flow.
- The C128 boot-art helper now writes the poster attribute map before the screen map, so the custom-font poster does not flash briefly under the old charset state first.
- The current shipping-art baseline is the simple shared fallback `MORIA8` deco logo. Higher-fidelity art is deferred until better source art exists.
- The title screen and disk directory cards now show per-platform display versions sourced from [../version.json](../version.json).
- Town now uses a fixed shared `66x22` footprint on both platforms, with the 8-building Commodore layout refit inside that space; C64 clamps town viewport movement to that logical footprint, while C128 preserves the existing wide entry framing and prevents fake border-wall artifacts by keeping out-of-town backing space non-presentational.
- Recent resolved items include BUG-1, BUG-LIT, BUG-M1, BUG-X, BUG-RECALL, BUG-EGO-NAME, BUG-DEEP-SPAWN, BUG-XP-PACE, BUG-GEN-CLEAR-C64, BUG-GEN-STALE-TOWN-C64, BUG-GAMEOVER-CLEAR-C64, BUG-DIG-SHIFT-D, BUG-PROMPT-FILTER, BUG-HAGGLE-UI, BUG-HELP-PAGING, BUG-LOOK-HILITE, BUG-TITLE-DUALDISK-FRAME, BUG-TOWN-KILL-DRAW, BUG-LOAD-C64, BUG-DESCENT-TOPROW-C64, BUG-INV-STATLINE-C64, `BUG-C128-TOWN-TOPROW-RECUR`, `BUG-TOWN-SIZE-DRIFT`, `BUG-C128-BOOTART-ORDER`, OPT-1, OPT-2, REF-1, `AUDIT-IO-C128`, `REF-INPUT-TABLES`, `REF-C128-TRAMP`, `REF-CONSTS`, the major C128 loader / banking stability repairs, the resident C128 banked combat relocation plus cached `OVL.UI`, 10.4 VDC threat/effect color work, the first `PERF-DG-C128` pass (faster dungeon generation plus visible `GENERATING...` feedback on dungeon transitions), the `dungeon_gen` BFS scratch cleanup, the high-value `TST-5` isolated coverage for disk swap plus renderer decision trees, `FEAT-WIZ`, `FEAT-SEARCH-MODE`, and `FEAT-UNIFIED-DISK` / `BUILD-UNIFY`.
- C128 VDC optimization work is paused after the verified left-scroll rollback and subsequent stability regressions; any restart needs a fresh design pass.

## Open Regression Bugs

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `BUG-LOOK-TRAP-DOOR` looking at traps or doors reports `You will have to do better than that.` | Medium | Medium | No | Directed look should describe or identify these terrain/feature targets instead of falling through to the generic failure message. |
| Medium | `BUG-LOOK-WALL-GOLD` looking at walls reports that it sees Gold | Medium | Medium | No | Directed look is misclassifying wall tiles as treasure-bearing targets instead of reporting wall terrain correctly. |

## Open Phases / Display Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `UI-80` refine the C128 80-column layout to a true Umoria-style left status panel | High | Medium | No | Treat as a refinement of the shipped 80-column baseline, not a contradiction of 10.7 completion. |

## Open Test / Cleanup Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Low | `OPT-5` further overlays for magic/spells/UI | High | Low | No | Only useful if main-segment pressure returns. |

## Open Features

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `FEAT-DISK` separate persistence media from the program disk | High | High | No | Probe available save drives, let the player pick a save target, reject the program disk for save/load/high-score persistence, and validate before destructive scratch/delete actions. |
| Medium | `FEAT-BOOT-ART` improve boot presentation beyond the current fallback logo on C64/C128 | High | High | No | The current tree ships a working fallback boot-art baseline on the split platform disks: C64 uses a multicolor bitmap asset and C128 uses a native 80-column VDC custom-charset poster helper. The next art-quality step is better source art plus platform-aware conversion/touch-up, not more low-level boot plumbing. Optional glint animation remains a later embellishment. |
| Medium | `FEAT-DEPTH` restore original Moria depth semantics (`0-1200` feet in `50`-foot increments) | High | Medium | No | The original games use dungeon depth in feet rather than a hard `0-99` floor abstraction. Rework UI, save/load, recall/wizard depth entry, generation/state contracts, and any tier/deep-spawn assumptions so the port can represent original-style depth values faithfully. |
| Medium | `FEAT-PERMADEATH-OPTION` make permadeath a player-selectable creation-time option, potentially via a broader difficulty choice | Medium | Medium | No | Add a character-creation choice that lets the player opt into permadeath rules instead of hardwiring one death policy. Final UI shape is open: standalone permadeath toggle or folded into a difficulty selection. |
| Low | `FEAT1` expand mage/priest spells from 16 to 31 each | High | Medium | No | Requires UI pagination and likely extra overlay pressure. |
| Low | `FEAT-AUD` audible hunger warning (buzz/beep) | Low | Medium | No | Add sound cue for Weak/Faint/Starve states to prevent surprise deaths. |
