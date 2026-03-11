# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-03-11, updated)

**All core phases (1–9) complete.** Phase 10.0 (C64/C128 split), C4 map-collision stabilization, Phase 10.2 (C128 extended-memory creature DB path), and **Phase 10.7 (full 80-column UI layout)** are complete. C128 now runs with map/tier access on the banked model, full-width 80-column viewport/UI layout, and stabilized VDC color-path mapping after 10.7 regression cleanup. Q1 (Quit/Reboot exit stability) is now resolved. R4 (post-kill render glitch) has also been fixed. **R2 garbled prompt/message corruption, C5 help-screen corruption/JAM, C2 keyboard responsiveness/matrix stabilization, M2 platformized screen blanking hooks, and the full TST-2 / TST-2A orchestration harness expansion are resolved.**

### Build Stats

- **Test suites:** C64: 27 runtime suites, C128: 32 harness suites
- **Compile-time asserts:** 136 (C128) / 69 (C64)
- **Source files:** 64 common + 7 c64-specific + ~10 c128-specific
- **C128 memory model (C4 baseline):** Map at Bank 1 `$4000-$4EFF`; floor items at Bank 0 `$1A00-$1AFF`; creature scratch at Bank 0 `$1B00-$1BFF`; main program starts at `$1C0E`.
- **C128 integration stability:** New game -> character creation summary -> town -> first dungeon entry is validated, and 10.8/TST-2 coverage now includes idle-title soak, title/new-game, title/load-resume, scripted summary-to-town, cache-survival, tier-transition, town-overlay, death-overlay, restart-to-title, tier-partial-failure, overlay-partial-failure, and boot-copy smokes.
- **C64 suite stability:** `run_tests.sh` is green with `test_input.s`, `test_main_loop.s`, `test_turn.s`, and `test_config.s` enabled in the default runner.

---

## Open Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| **BUG-X** | **LOW** | AUDIT: C64 IRQ `irq_no_blink` and C128 `safe_irq` do not `cld` before executing, making them susceptible to Decimal Mode bugs if math is ever added to the IRQs. | Pending |
| **L3** | LOW | C128: Grey and Light Grey colors collapse to same RGBI value on VDC. | Tracked |
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |
| FEAT1 | LOW | Expand Mage/Priest spells from 16 to 31 each (62 total). Will require UI pagination and `magic_overlay.prg` if resident RAM limits are hit, but struct and effects logic already support this size. | Feature Request |
| **OPT-1** | **MED** | Performance: O(1) Command Dispatch. Convert massive `cmp`/`bne` chain in `game_loop.s` to a jump table (array of function pointers). | Pending |
| **OPT-2** | LOW | Performance: Bounding Box Math. Optimize `dungeon_los.s` room bounds checks to save instructions. | Pending |
| **OPT-3** | **MED** | Performance: Visibility Updates. Cache room ID and only re-evaluate `update_visibility` room checks upon entering a new room to save per-turn overhead. | Pending |
| **REF-1** | LOW | Refactor: Trampoline Sprawl. Consolidate the numerous `tramp_*` routines in `main.s` into a generic macro or parameterized `call_banked` routine to reduce redundancy. | Pending |
| **REF-2** | **MED** | Refactor: Game Loop Coupling. Decouple `game_loop.s` to separate UI rendering, time management, and logic into an MVC-style pattern for better testability. | Pending |
| **TST-1** | **MED** | Testing: Input parsing now has dedicated C64/C128 suites, LOS behavior is covered in existing dungeon/monster tests, and `main_loop` now has a focused dispatch harness (`test_main_loop.s`). | **Done (2026-03-11)** |
| **TST-3** | **MED** | Testing: UI Menus & Views. Add isolation tests for character viewer, help, home, inventory, recall, and store visual layouts. See `TEST_PLAN_TOP5.md` for specific UI routines. | Pending |
| **TST-4** | **MED** | Testing: Subsystems. Add unit tests for decompression (`huffman.s`), strings (`string_bank.s`), overlay execution, and audio (`sound.s`). | Pending |
| **TST-5** | LOW | Testing: Miscellaneous Mechanics. Add isolated tests for disk swap procedures, palette mapping, and rendering draw routines. | Pending |
| **DOC-1** | LOW | Documentation: Fix stale comments in `input.s` regarding numeric prefixes to accurately reflect the broken/deferred state shown in the history. | Pending |

### Investigation Tasks (R4)
*(Moved to BUILDPLAN_HISTORY pending next cleanup)*

### Recently Resolved

| # | Severity | Description | Resolution Date |
|---|----------|-------------|-----------------|
| **R2** | **MED** | C128 garbled prompt/message text in LOOK/TAKE-OFF/title flow. | **2026-03-05** |
| **UX80 / 10.7** | **HIGH** | C128 full 80-column layout + post-rollout VDC color regression cleanup (coherent color mapping restored; dungeon color-path guard tests added). | **2026-03-08** |
| **A7** | **HIGH** | Compile-time split hardening: removed runtime `zp_machine_type` gating from common hot paths and replaced with `#if C128`/`#if !C128`. | **2026-03-05** |
| **A8** | **HIGH** | C128 layout hardening: enforced `<$D000` placement asserts for all `tramp_*`, added game-over end-boundary guards, and added harness assert-coverage enforcement. | **2026-03-05** |
| **C3** | **HIGH** | C128 `wear` prompt stale-key regression fixed by adding release-wait gate before selection read; harness guard added to prevent regression. | **2026-03-05** |
| **C4** | **HIGH** | C128 follow-up prompt audit complete: added release-wait gates for drop/quaff/read/aim/use/gain/throw + menu/recall dismiss paths, with expanded harness chain checks. | **2026-03-05** |
| **C5** | **BLOCKER** | C128 help (`?`) corruption/JAM fixed by C128-safe help renderer path and help code/data relocation out of overlay window, with assert+harness placement gates. | **2026-03-05** |
| **C2** | **BLOCKER** | C128 keyboard matrix + responsiveness stabilization complete: rows 8/9 scan path, keypad/ESC mappings, asymmetric debounce tuning, and regression coverage validated. | **2026-03-05** |
| **P1** | **MED** | C128 VDC responsiveness: instrumentation-first tuning complete (status redraw coherence, scroll-delta rendering for 1-tile shifts, movement latency counters/harness guards). | **2026-03-09** |
| **M2** | MED | Platformized screen blank/unblank hooks: removed direct `$D011` toggles from shared `game_loop.s`; C64 keeps VIC-II DEN behavior, C128 uses explicit no-op VDC policy hook. | **2026-03-09** |
| **DTH-1** | **BLOCKER** | C128 death flow regression fixed by bracketing high-score KERNAL I/O in `tramp_game_over` with explicit MMU/ROM transitions while keeping death overlay routines in all-RAM mode. | **2026-03-09** |
| **SAV-2** | **BLOCKER** | C128 restore/load stabilization: fixed load-resume stale tier metadata reuse and corrected C128 map stream handling so map bytes are preserved across MMU restore (instead of being clobbered to `MMU_NORMAL`), with KERNAL byte I/O running in `MMU_NORMAL` context. | **2026-03-09** |
| **BUG-Y / 10.8** | **BLOCKER** | C128 preload/cache rebaseline complete: Bank 1 ownership refactor, tier+overlay cache contract fixes, carry-return repair, runtime guard restoration, and character-summary/town-flow stabilization with deterministic scripted-input coverage. | **2026-03-11** |
| **10.8-HDN** | **MED** | Follow-up hardening complete: `memory128.s` is now the ownership source of truth, placement rules are assert-backed, the C128 architecture doc has a preflight checklist, and smoke coverage now verifies cache survival plus tier/overlay fallback isolation. | **2026-03-11** |
| **TST-2** | **HIGH** | Orchestration coverage expansion complete: added C64 `config` + `turn` runtime suites, C128 `config128` + `main_loop128` harnesses, and a restart-to-title death-path smoke. | **2026-03-11** |
| **TST-2A** | **HIGH** | Deterministic C128 title-load/resume smoke completed with generated `THE.GAME` seed injection and verified title `L` -> `load_resume_game` coverage in the default runner. | **2026-03-11** |
## What's Next

**Phase 10 — C128 Enhancements:**

| # | What | Summary | Status |
|---|------|---------|--------|
| 10.0 | Code split | `common/` + `c64/` + `c128/` directory structure complete. | **Done** |
| 10.1 | 80-column VDC mode | VDC rendering backend with row batching and dirty-rect optimization. | **Done (baseline)** |
| 10.2 | Extended memory | Use C128 128KB MMU bank-switch path for creature/item database. | **Done** |
| 10.3 | Larger dungeon | Expand map to 198x66 (original size) in a follow-on plan after C4 baseline. | |
| 10.4 | Enhanced display | VDC color attributes for threat-coded monsters and special effects. | |
| 10.5 | VDC Performance | Implementation of high-speed row-blasting and streaming optimizations. | **Done** |
| 10.6 | Compile-time platform split hardening | Remove remaining runtime C64/C128 dispatch in `common/` hot paths; replace with compile-time branches and platform hooks. | **Done** |
| 10.7 | Full 80-column UI layout | Replace centered 40-column carry-over with native 80-column layouts for viewport framing, message lines, status panel, title/help/menu screens, and related constants/tables. | **Done** |
| 10.8 | Bank 1 Preload Cache + Ownership Refactor | C128: ownership refactor, tier cache, fixed-slot overlay cache, runtime guard restoration, carry-contract fixes, Gate B validation, and the follow-up hardening pass are complete. `memory128.s` now owns the Bank 1 manifest and overlap rules, `ARCHITECTURE.md` carries the preflight checklist, and coverage includes cache-survival plus tier/overlay fallback-isolation smokes. | **Done** |

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

### Priority Triage (updated 2026-03-11)

**High priority (C128 Port Stability):**
1. No open C128 blocker after DTH-1/SAV-2 closure.
2. No open C128 memory-ownership hardening blocker after 10.8-HDN closure; maintain the `memory128.s` ownership manifest and smoke coverage when changing Bank 1 layout.
3. Maintain the C128 smoke seed generator alongside save-format changes so title `L` -> `load_resume_game` coverage stays deterministic in the default runner.

**Low priority (polish/completeness):**
- A6 Large file split — opportunistic refactoring (item.s)
- OPT-5 (Options 2+3) — further overlays for magic/spells and UI screens if main segment tightens again
