# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-03-02, updated)

**All core phases (1–9) complete.** Phase 10.0 (C64/C128 split) and the C4 map-collision stabilization track are complete through C4.8, with post-lock stability fixes applied to KERNAL vector/load handling and C128 banked map render paths. C128 now runs with the map in Bank 1 and validated MMU-safe map access paths.

### Build Stats

- **Test suites:** C64: 21 runtime suites, C128: 6 harness suites
- **Compile-time asserts:** 69 (C128) / 71 (C64)
- **Source files:** 64 common + 7 c64-specific + ~10 c128-specific
- **C128 memory model (C4 baseline):** Map at Bank 1 `$4000-$4EFF`; floor items at Bank 0 `$1A00-$1AFF`; creature scratch at Bank 0 `$1B00-$1BFF`; main program starts at `$1C0E`.
- **C128 integration stability:** New game -> character creation -> town -> first dungeon entry is validated after C4 stabilization fixes.

---

## Open Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| **C2** | **BLOCKER** | C128: Keyboard matrix path is incomplete (missing Line 8/9 extended key scan) and input responsiveness is sluggish versus C64 (notably `E` and rapid repeats). | **High Priority** |
| **Q1** | **HIGH** | C128: `Quit` path fails to return cleanly to BASIC; exits to corrupted screen/monitor BREAK state instead of stable BASIC prompt. | **New** |
| **R3** | **HIGH** | C128: RNG startup entropy appears deterministic across runs. Likely cause: `rng_seed` uses only CIA timer reads and is called at highly repeatable startup/menu timing (`main.s` + `game_new_start`), producing repeatable initial seeds in emulator/runtime. | **New** |
| **R4** | **HIGH** | C128: After killing a dungeon monster, the vacated tile can render as the wrong glyph/color (including near/far-dependent color shifts). Likely cause: post-kill map byte/render state mismatch (tile byte after `FLAG_OCCUPIED` clear vs VDC visible/dim path), requiring trace of tile value before/after `monster_remove` and immediate render path inputs. | **New** |
| **R2** | **MED** | C128: In town, pressing `T` can corrupt top-of-screen text (garbled cyan text block appears instead of clean message output). Repro observed while normal gameplay rendering otherwise remains stable. | **New** |
| **M2** | MED | C128: VIC-II screen blanking ($D011) has no effect on VDC display. | Tracked |
| **L3** | LOW | C128: Grey and Light Grey colors collapse to same RGBI value on VDC. | Tracked |
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |

### Investigation Tasks (R3, R4)

1. **R3 seed instrumentation:** Log first 8 RNG outputs at fresh boot and at `game_new_start` across 5 cold runs to confirm repeatability and distinguish boot-seed vs post-menu reseed behavior.
2. **R3 entropy hardening:** Mix CIA timers with user timing jitter (keypress interval counter) and mutable state (frame/turn counters) before first gameplay RNG consumption; keep all-zero guard.
3. **R4 kill-path trace:** At a known kill coordinate, capture map byte before hit, immediately after `monster_remove`, and before render decode (`zp_tile_tmp`) to verify type/flags are preserved except `FLAG_OCCUPIED`.
4. **R4 render branch validation:** Confirm the same tile routes through expected visible/dim branch and that final glyph/color source (tile/item/monster/player override) matches map state.
5. **R4 regression test:** Add C128 harness/assertion covering monster death tile normalization (glyph/type and color path stable after kill at close/far distances).

---

## What's Next

**Phase 10 — C128 Enhancements:**

| # | What | Summary | Status |
|---|------|---------|--------|
| 10.0 | Code split | `common/` + `c64/` + `c128/` directory structure complete. | **Done** |
| 10.1 | 80-column VDC mode | VDC rendering backend with row batching and dirty-rect optimization. | **Done (baseline)** |
| 10.2 | Extended memory | Use C128 128KB MMU bank-switch path for creature/item database. | |
| 10.3 | Larger dungeon | Expand map to 198x66 (original size) in a follow-on plan after C4 baseline. | |
| 10.4 | Enhanced display | VDC color attributes for threat-coded monsters and special effects. | |
| 10.5 | VDC Performance | Implementation of high-speed row-blasting and streaming optimizations. | **Done** |

### Phase 10.2 Execution Plan (2026-03-03)

| Step | Goal | Deliverable | Test Gate | Status |
|---|---|---|---|---|
| **10.2.0** | Baseline + invariants | Freeze current behavior, define no-regression checklist, capture baseline test results | `make test128`, `make test`, manual smoke checklist | **Complete (Automated), Manual Smoke Pending** |
| **10.2.1** | Access abstraction | C128-only banked database access helpers (byte/pointer/block) with clear IRQ/MMU contracts | Existing C128 memory tests + new helper smoke checks | Planned |
| **10.2.2** | Banked tier staging | Copy active tier payload from `$E000` load area into Bank 1 DB region; persist metadata | Tier load/transition tests + boot smoke | Planned |
| **10.2.3** | Consumer migration | Switch C128 tier/name runtime reads (`creature_get_name` path + tier pointer reads) to Bank 1 DB helpers | New tier/name correctness suite + existing gameplay smoke | Planned |
| **10.2.4** | State hardening | Harden overlay/tier/string-bank invalidation and load-fail fallback state on C128 | Failure-path test cases + no BREAK/JAM smoke | Planned |
| **10.2.5** | Regression coverage | Add C128 tests for tier transition/name lookup across banks and stale-pointer fallback | `make test128` all green with new suite(s) | Planned |
| **10.2.6** | Completion + doc sync | Confirm full regressions and update status/history artifacts | C64+C128 full suites + manual end-to-end smoke | Planned |

**10.2 No-Regression Checklist**
- C64 behavior remains unchanged (`make test` green).
- C128 boots to title, accepts input, starts new game, enters town/dungeon without JAM/BREAK.
- C128 save/load path remains functional.
- Existing C4 map banking behavior remains stable.

**10.2.0 Baseline Capture (2026-03-03)**
- `make test128`: **PASS** (`7 passed, 0 failed`)
- `make test`: **PASS** (`24 passed, 0 failed`)
- Manual smoke: **Pending during implementation** (to be re-run after each behavior-changing step)

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
1. Add Line 8 (keypad/extra keys) scanning support (C2).
2. Fix deterministic RNG startup seeding path on C128 (R3).
3. Fix post-monster-kill tile corruption/render mismatch on C128 (R4).

**Low priority (polish/completeness):**
- A6 Large file split — opportunistic refactoring (item.s)
- OPT-5 (Options 2+3) — further overlays for magic/spells and UI screens if main segment tightens again
