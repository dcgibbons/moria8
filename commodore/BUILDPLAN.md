# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-03-05, updated)

**All core phases (1–9) complete.** Phase 10.0 (C64/C128 split), C4 map-collision stabilization, and Phase 10.2 (C128 extended-memory creature DB path) are complete. C128 now runs with the map in Bank 1 and validated MMU-safe map/tier access paths. Q1 (Quit/Reboot exit stability) is now resolved. R4 (post-kill render glitch) has also been fixed. **R2 garbled prompt/message corruption is now resolved** with title-path bank fixes and low-memory pinning of critical trampolines.

### Build Stats

- **Test suites:** C64: 24 runtime suites, C128: 14 harness suites
- **Compile-time asserts:** 98 (C128) / 70 (C64)
- **Source files:** 64 common + 7 c64-specific + ~10 c128-specific
- **C128 memory model (C4 baseline):** Map at Bank 1 `$4000-$4EFF`; floor items at Bank 0 `$1A00-$1AFF`; creature scratch at Bank 0 `$1B00-$1BFF`; main program starts at `$1C0E`.
- **C128 integration stability:** New game -> character creation -> town -> first dungeon entry is validated after C4 stabilization fixes.

---

## Open Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| **C2** | **BLOCKER** | C128: Keyboard matrix path is incomplete (missing Line 8/9 extended key scan) and input responsiveness is sluggish versus C64 (notably `E` and rapid repeats). | **High Priority** |
| **C5** | **BLOCKER** | C128: `?` Help command renders garbled title text and then CPU JAMs at `$1C09` after/during help screen flow. | **Open / Regression** |
| **P1** | **MED**     | C128: VDC viewport rendering is slow. See `c128/VDC_OPTIMIZATION_PLAN.md` for the performance improvement plan. | **Open** |
| **M2** | MED | C128: VIC-II screen blanking ($D011) has no effect on VDC display. | Tracked |
| **L3** | LOW | C128: Grey and Light Grey colors collapse to same RGBI value on VDC. | Tracked |
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |
| FEAT1 | LOW | Expand Mage/Priest spells from 16 to 31 each (62 total). Will require UI pagination and `magic_overlay.prg` if resident RAM limits are hit, but struct and effects logic already support this size. | Feature Request |
| **OPT-1** | **MED** | Performance: O(1) Command Dispatch. Convert massive `cmp`/`bne` chain in `game_loop.s` to a jump table (array of function pointers). | Pending |
| **OPT-2** | LOW | Performance: Bounding Box Math. Optimize `dungeon_los.s` room bounds checks to save instructions. | Pending |
| **OPT-3** | **MED** | Performance: Visibility Updates. Cache room ID and only re-evaluate `update_visibility` room checks upon entering a new room to save per-turn overhead. | Pending |
| **REF-1** | LOW | Refactor: Trampoline Sprawl. Consolidate the numerous `tramp_*` routines in `main.s` into a generic macro or parameterized `call_banked` routine to reduce redundancy. | Pending |
| **REF-2** | **MED** | Refactor: Game Loop Coupling. Decouple `game_loop.s` to separate UI rendering, time management, and logic into an MVC-style pattern for better testability. | Pending |
| **TST-1** | **HIGH** | Testing: Missing critical test suites for input parsing (`test_input.s`), command dispatch, and Line of Sight (`test_los.s`). | Pending |
| **DOC-1** | LOW | Documentation: Fix stale comments in `input.s` regarding numeric prefixes to accurately reflect the broken/deferred state shown in the history. | Pending |

### Investigation Tasks (R4)
*(Moved to BUILDPLAN_HISTORY pending next cleanup)*

### Recently Resolved

| # | Severity | Description | Resolution Date |
|---|----------|-------------|-----------------|
| **R2** | **MED** | C128 garbled prompt/message text in LOOK/TAKE-OFF/title flow. | **2026-03-05** |
| **A7** | **HIGH** | Compile-time split hardening: removed runtime `zp_machine_type` gating from common hot paths and replaced with `#if C128`/`#if !C128`. | **2026-03-05** |
| **A8** | **HIGH** | C128 layout hardening: enforced `<$D000` placement asserts for all `tramp_*`, added game-over end-boundary guards, and added harness assert-coverage enforcement. | **2026-03-05** |
| **C3** | **HIGH** | C128 `wear` prompt stale-key regression fixed by adding release-wait gate before selection read; harness guard added to prevent regression. | **2026-03-05** |
| **C4** | **HIGH** | C128 follow-up prompt audit complete: added release-wait gates for drop/quaff/read/aim/use/gain/throw + menu/recall dismiss paths, with expanded harness chain checks. | **2026-03-05** |
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
1. Fix Help (`?`) garble + CPU JAM at `$1C09` (C5).
2. Add Line 8 (keypad/extra keys) scanning support (C2).

**Low priority (polish/completeness):**
- A6 Large file split — opportunistic refactoring (item.s)
- OPT-5 (Options 2+3) — further overlays for magic/spells and UI screens if main segment tightens again
