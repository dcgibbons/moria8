# Moria C64/C128 — Active Build Plan

> Active outstanding work only.
> See [DESIGN.md](DESIGN.md) for architecture reference and [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed phases, fixes, and reviews.

---

## Current State (2026-03-27)

- All core phases 1–9 are complete.
- C128 split, extended-memory database path, larger dungeon, hardened execution boundary, and the current 80-column baseline are complete.
- Recent resolved items include BUG-1, BUG-LIT, BUG-M1, BUG-X, BUG-RECALL, BUG-EGO-NAME, BUG-DEEP-SPAWN, BUG-XP-PACE, BUG-GEN-CLEAR-C64, BUG-GAMEOVER-CLEAR-C64, BUG-DIG-SHIFT-D, BUG-PROMPT-FILTER, BUG-HAGGLE-UI, BUG-HELP-PAGING, BUG-LOOK-HILITE, BUG-TITLE-DUALDISK-FRAME, BUG-TOWN-KILL-DRAW, OPT-1, OPT-2, REF-1, `AUDIT-IO-C128`, `REF-INPUT-TABLES`, `REF-C128-TRAMP`, `REF-CONSTS`, the major C128 loader / banking stability repairs, the resident C128 banked combat relocation plus cached `OVL.UI`, 10.4 VDC threat/effect color work, the first `PERF-DG-C128` pass (faster dungeon generation plus visible `GENERATING...` feedback on dungeon transitions), the `dungeon_gen` BFS scratch cleanup, the high-value `TST-5` isolated coverage for disk swap plus renderer decision trees, and `FEAT-WIZ` Wizard Mode.
- C128 VDC optimization work is paused after the verified left-scroll rollback and subsequent stability regressions; any restart needs a fresh design pass.

## Open Phases / Display Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `UI-80` refine the C128 80-column layout to a true Umoria-style left status panel | High | Medium | No | Treat as a refinement of the shipped 80-column baseline, not a contradiction of 10.7 completion. |

## Open Test / Cleanup Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Low | `REF-MON-SOA` evaluate converting the active monster table from AoS to SoA | High | High | No | Potential 6502 performance win, but risky: it touches AI, accessors, save/load, and tests. Keep it firmly backlog-only until profiling proves the win is worth the churn. |
| Low | `OPT-5` further overlays for magic/spells/UI | High | Low | No | Only useful if main-segment pressure returns. |

## Open Features

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `FEAT-DISK` separate persistence media from the program disk | High | High | No | Probe available save drives, let the player pick a save target, reject the program disk for save/load/high-score persistence, and validate before destructive scratch/delete actions. |
| Medium | `FEAT-SEARCH-MODE` restore original search-mode and passive auto-search behavior | Medium | Medium | No | Keep the existing one-turn search command, but add the original persistent search toggle plus the `fos`-style passive auto-search frequency stat so searching works like VMS-Moria/Umoria instead of only as a manual single-turn action. |
| Medium | `FEAT-DEPTH` restore original Moria depth semantics (`0-1200` feet in `50`-foot increments) | High | Medium | No | The original games use dungeon depth in feet rather than a hard `0-99` floor abstraction. Rework UI, save/load, recall/wizard depth entry, generation/state contracts, and any tier/deep-spawn assumptions so the port can represent original-style depth values faithfully. |
| Medium | `FEAT-PERMADEATH-OPTION` make permadeath a player-selectable creation-time option, potentially via a broader difficulty choice | Medium | Medium | No | Add a character-creation choice that lets the player opt into permadeath rules instead of hardwiring one death policy. Final UI shape is open: standalone permadeath toggle or folded into a difficulty selection. |
| Low | `FEAT1` expand mage/priest spells from 16 to 31 each | High | Medium | No | Requires UI pagination and likely extra overlay pressure. |
| Low | `FEAT-AUD` audible hunger warning (buzz/beep) | Low | Medium | No | Add sound cue for Weak/Faint/Starve states to prevent surprise deaths. |
