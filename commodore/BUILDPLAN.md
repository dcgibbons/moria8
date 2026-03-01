# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Recent Fixes

| Date | Bug | Description |
|------|-----|-------------|
| 2026-02-28 | **Overlay Overlap** | Fixed CPU JAM at $76CB when entering dungeon. `DungeonGenOverlay` was overwriting `ego_items.s` in banked payload. |
| 2026-02-28 | **VDC JAM** | Fixed CPU JAM at $A94E during character creation. Reverted VDC hardware fill to streaming loops. |

## Current State (2026-02-28, updated)

**All core phases (1–9) complete.** Phase 10.0 (C64/C128 code split) is complete — codebase reorganized into `common/`, `c64/`, and `c128/`. The project is currently focusing on Phase 10.1 (VDC 80-column rendering) and resolving critical C128 input issues.

### Build Stats

- **Test suites:** 24 (321 runtime tests)
- **Compile-time asserts:** 71
- **Source files:** 64 common + 7 c64-specific + ~10 c128-specific
- **Bank 0 Physical Map**: Contiguous code from $1C0E to $BFFF. Map at $0B00.

---

## Open Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| **C2** | **BLOCKER** | C128: Keyboard matrix scan lacks Line 8 (keypad/extended keys) support. | **High Priority** |
| **C4** | **BLOCKER** | C128: Memory Collision — Dungeon Map ($0B00) overwrites Program ($1C0E). | **Critical** |
| **M2** | MED | C128: VIC-II screen blanking ($D011) has no effect on VDC display. | Tracked |
| **L3** | LOW | C128: Grey and Light Grey colors collapse to same RGBI value on VDC. | Tracked |
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |

---

## What's Next

**Phase 10 — C128 Enhancements:**

| # | What | Summary | Status |
|---|------|---------|--------|
| 10.0 | Code split | `common/` + `c64/` + `c128/` directory structure complete. | **Done** |
| 10.1 | 80-column VDC mode | Implement VDC rendering backend, optimized with row batching and dirty-rect. | **In Progress** |
| 10.2 | Extended memory | Use C128 128KB MMU bank-switch path for creature/item database. | |
| 10.3 | Larger dungeon | Expand map to 198x66 (original size) at $4000 in Bank 0. | |
| 10.4 | Enhanced display | VDC color attributes for threat-coded monsters and special effects. | |
| 10.5 | VDC Performance | Implementation of high-speed row-blasting and streaming optimizations. | **Done** |

---

### Phase 10 — Known Platform Dependencies in common/

These files in `common/` contain minor C64-specific code that will need parameterization or hooks for C128:

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
| `game_loop.s` | `$d011` VIC-II DEN bit | Platform hooks for VDC blanking |

---

### Priority Triage (updated 2026-02-27)

**High priority (C128 Port Stability):**
1. Resolve Memory Collision between Dungeon Map and Program (C4).
2. Add Line 8 (keypad/extra keys) scanning support (C2).

**Low priority (polish/completeness):**
- A6 Large file split — opportunistic refactoring (item.s)
- OPT-5 (Options 2+3) — further overlays for magic/spells and UI screens if main segment tightens again
