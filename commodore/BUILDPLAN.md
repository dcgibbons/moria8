# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-02-21 — R17 complete)

**All core phases (1–9) complete.** The game is fully playable from title screen through dungeon exploration, combat, magic, stores, save/load, death, and high scores. All feature work (R1.1–R17), optimizations (OPT-1–OPT-5), and 47 bug fixes complete. See BUILDPLAN_HISTORY.md for the full phase completion summary and resolved bug list.

### Build Stats

- **Test suites:** 24 (320 runtime tests)
- **Compile-time asserts:** 71
- **Source files:** ~51 .s files
- **Program size:** $B47C (program_end) — **2,948 bytes headroom** to MAP_BASE ($C000)
- **Banked code:** $F000-$FF98 (at limit)
- **Banked payload:** $B4A9-$C444
- **Town overlay:** 3,016 of 4,096 bytes (1,080 free)
- **Startup overlay:** 4,017 of 4,096 bytes (79 free)
- **DungeonGen overlay:** 3,530 of 4,096 bytes (566 free)

---

## Open Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| BUG-48 | MED | Title screen shows stale character stats after S)tart from game-over loop — when selecting Start after saving/quitting, the title screen redraws but the bottom 3 lines still show the previous session's character name, race, stats, and HP. The restart path doesn't clear the status bar area before redrawing the title screen. Fix: clear the full screen (including status lines 22–24) before drawing the title screen on restart. | Open |
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |

---

## What's Next

**Phase 10 — C128 Enhancements** (not started):

| # | What | Summary |
|---|------|---------|
| 10.0 | Separate binaries | BOOT.PRG + MORIA64 + MORIA128 — prerequisite for all C128 work |
| 10.1 | 80-column VDC mode | Second rendering backend for VDC 80x25 display |
| 10.2 | Extended memory | C128 128KB MMU bank-switch path (no disk tier loading) |
| 10.3 | Larger dungeon | Expand map to 120x80+, more rooms, up to 64 active monsters |
| 10.4 | Enhanced display | VDC color attributes for threat-coded monsters |

---

### Priority Triage (updated 2026-02-21)

**Low priority (polish/completeness):**
- A6 Large file split — opportunistic refactoring (item.s)
- OPT-5 (Options 2+3) — further overlays for magic/spells and UI screens if main segment tightens again
