# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-02-21 — Phase 10.0 code split complete)

**All core phases (1–9) complete.** Phase 10.0 (C64/C128 code split) done — codebase reorganized into `common/` (64 shared files), `c64/` (7 platform files), and skeletal `c128/main.s`. Game loop extracted from main.s into `common/game_loop.s` (~1,382 lines). All tests pass.

### Build Stats

- **Test suites:** 24 (321 runtime tests)
- **Compile-time asserts:** 71
- **Source files:** 64 common + 7 c64-specific + 23 test files
- **Program size:** $B4BB (program_end) — headroom to MAP_BASE ($C000)
- **Banked code:** $F000-$FF98 (at limit)
- **Town overlay:** 3,016 of 4,096 bytes (1,080 free)
- **Startup overlay:** 4,017 of 4,096 bytes (79 free)
- **DungeonGen overlay:** 3,530 of 4,096 bytes (566 free)

---

## Open Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |

---

## What's Next

**Phase 10 — C128 Enhancements:**

| # | What | Summary | Status |
|---|------|---------|--------|
| 10.0 | Code split | `common/` + `c64/` + `c128/` directory structure, game loop extraction | **Done** |
| 10.1 | 80-column VDC mode | Second rendering backend for VDC 80x25 display | Next |
| 10.2 | Extended memory | C128 128KB MMU bank-switch path (no disk tier loading) | |
| 10.3 | Larger dungeon | Expand map to 120x80+, more rooms, up to 64 active monsters | |
| 10.4 | Enhanced display | VDC color attributes for threat-coded monsters | |

### Phase 10.0 — Known Platform Dependencies in common/

These files in `common/` contain minor C64-specific code that will need parameterization for C128:

| File | Issue | Future Fix |
|------|-------|-----------|
| `spell_effects.s:574` | `adc #$d4` screen→color RAM trick | Abstract via macro or screen.s helper |
| `dungeon_gen.s:1901` | `BFS_QUEUE = $0400` (screen RAM as scratch) | Use a platform constant |
| `overlay.s:115-117` | `$DD00` CIA2 VIC bank restore | Conditional compile or platform hook |
| `tier_manager.s:314-316` | Same `$DD00` restore | Same fix as overlay.s |
| `ui_messages.s:17` | `MSG_HIST_LEN = 40` tied to 40-col | Use SCREEN_COLS constant |
| `title_data.s` | Hardcoded 40-col layout | Create 80-col version later |
| `ui_help.s:6` | 40-col layout | Parameterize or create 80-col version |
| `ui_status.s` | Hardcoded column positions | Replace with named constants |
| `disk_swap.s` | Centering hardcoded for 40 cols | Use SCREEN_COLS/2 arithmetic |
| `game_loop.s` | `$d011` VIC-II DEN bit, `$c6` keyboard buffer | Platform hooks or constants |

---

### Priority Triage (updated 2026-02-21)

**Low priority (polish/completeness):**
- A6 Large file split — opportunistic refactoring (item.s)
- OPT-5 (Options 2+3) — further overlays for magic/spells and UI screens if main segment tightens again
