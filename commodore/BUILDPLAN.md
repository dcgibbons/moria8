# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-03-22, updated)

**All core phases (1–9) complete.** Phase 10.0 (C64/C128 split), C4 map-collision stabilization, Phase 10.2 (C128 extended-memory creature DB path), and **Phase 10.7 (full 80-column UI layout)** are complete. C128 now runs with map/tier access on the banked model, full-width 80-column viewport/UI layout, and stabilized VDC color-path mapping after 10.7 regression cleanup. Q1 (Quit/Reboot exit stability) is now resolved. R4 (post-kill render glitch) has also been fixed. **R2 garbled prompt/message corruption, C5 help-screen corruption/JAM, C2 keyboard responsiveness/matrix stabilization, M2 platformized screen blanking hooks, the full TST-2 / TST-2A orchestration harness expansion, the C128 Hardened Execution Boundary, the low-RAM runtime loader repair for the post-chargen town-entry `JAM`, the banked-UI source/recopy repair for help/inventory blank-screen hangs, the dungeon-descent ego-generation `JAM` caused by I/O-hole placement drift, BUG-M1 stale-monster rendering after AI turns, BUG-LIT dark-room full-redraw flash, the OPT-1 main-loop command-dispatch jump-table conversion, OPT-2 room-bounds LOS cleanup, REF-1 trampoline-sprawl consolidation, BUG-X IRQ decimal-mode hardening, and L3 VDC grey/light-grey policy cleanup are resolved.**

### Build Stats

- **Test suites:** C64: 27 runtime suites, C128: 40 harness suites
- **Compile-time asserts:** 182 (C128) / 69 (C64)
- **Source files:** 64 common + 7 c64-specific + ~10 c128-specific
- **C128 memory model (C4 baseline):** Map at Bank 1 `$4000-$4EFF`; floor items at Bank 0 `$1A00-$1AFF`; creature scratch at Bank 0 `$1B00-$1BFF`; main program starts at `$1C0E`.
- **C128 integration stability:** New game -> character creation summary -> town -> first dungeon entry is validated, and 100% C128 test pass (40/40) includes all smoke tests, hardened boot-handoff verification, and the repaired low-RAM VDC runtime loader path.
- **C64 suite stability:** `run_tests.sh` is green with `test_input.s`, `test_main_loop.s`, `test_turn.s`, and `test_config.s` enabled in the default runner.

---

## Open Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| UI-80 | MED | C128 80-col Umoria UI Layout: Implement vertical status panel on the left (stats, HP/MP, AC, Gold) and reposition the viewport to the right, matching the original 80-column Umoria layout. | Backlog |
| FEAT1 | LOW | Expand Mage/Priest spells from 16 to 31 each (62 total). Will require UI pagination and `magic_overlay.prg` if resident RAM limits are hit, but struct and effects logic already support this size. | Feature Request |
| **TST-5** | LOW | Testing: Miscellaneous Mechanics. Add isolated tests for disk swap procedures, palette mapping, and rendering draw routines. | Pending |
## What's Next


**Phase 10 — C128 Enhancements:**

| # | What | Summary | Status |
|---|------|---------|--------|
| 10.0 | Code split | `common/` + `c64/` + `c128/` directory structure complete. | **Done** |
| 10.1 | 80-column VDC mode | VDC rendering backend with row batching and dirty-rect optimization. | **Done (baseline)** |
| 10.2 | Extended memory | Use C128 128KB MMU bank-switch path for creature/item database. | **Done** |
| 10.3 | Larger dungeon | C128 map expanded to `198x66` with Bank 1 ownership redesign, save-format split, and runtime validation. | **Done** |
| 10.4 | Enhanced display | VDC color attributes for threat-coded monsters and special effects. | |
| 10.5 | VDC Performance | Implementation of high-speed row-blasting and streaming optimizations. | **Done** |
| 10.6 | Compile-time platform split hardening | Remove remaining runtime C64/C128 dispatch in `common/` hot paths; replace with compile-time branches and platform hooks. | **Done** |
| 10.7 | Full 80-column UI layout | Replace centered 40-column carry-over with native 80-column layouts for viewport framing, message lines, status panel, title/help/menu screens, and related constants/tables. | **Done** |
| 10.8 | Bank 1 Preload Cache + Ownership Refactor | C128: ownership refactor, tier cache, fixed-slot overlay cache, runtime guard restoration, carry-contract fixes, Gate B validation, and the follow-up hardening pass are complete. `memory128.s` now owns the Bank 1 manifest and overlap rules, `ARCHITECTURE.md` carries the preflight checklist, and coverage includes cache-survival plus tier/overlay fallback-isolation smokes. | **Done** |
| 10.9 | Hardened Execution Boundary | MMU stability, atomic KERNAL I/O, loader-to-game handoff stabilization, and 100% test pass. | **Done (2026-03-14)** |

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

---

### Priority Triage (updated 2026-03-14)

**High priority (C128 Port Stability):**
1. Maintain 100% C128 suite pass rate (40/40).
2. No open C128 memory-ownership hardening blocker; maintain the `memory128.s` ownership manifest and smoke coverage when changing Bank 1 layout.
3. Maintain the startup low-RAM runtime loader contract for callable `$1000` code: symbol address, PRG load header, and visible execution bank must stay aligned.
4. Maintain the C128 smoke seed generator alongside save-format changes so title `L` -> `load_resume_game` coverage stays deterministic in the default runner.

**Low priority (polish/completeness):**
- A6 Large file split — opportunistic refactoring (item.s)
- OPT-5 (Options 2+3) — further overlays for magic/spells and UI screens if main segment tightens again
