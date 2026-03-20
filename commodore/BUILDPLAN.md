# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-03-18, updated)

**All core phases (1–9) complete.** Phase 10.0 (C64/C128 split), C4 map-collision stabilization, Phase 10.2 (C128 extended-memory creature DB path), and **Phase 10.7 (full 80-column UI layout)** are complete. C128 now runs with map/tier access on the banked model, full-width 80-column viewport/UI layout, and stabilized VDC color-path mapping after 10.7 regression cleanup. Q1 (Quit/Reboot exit stability) is now resolved. R4 (post-kill render glitch) has also been fixed. **R2 garbled prompt/message corruption, C5 help-screen corruption/JAM, C2 keyboard responsiveness/matrix stabilization, M2 platformized screen blanking hooks, the full TST-2 / TST-2A orchestration harness expansion, the C128 Hardened Execution Boundary, the low-RAM runtime loader repair for the post-chargen town-entry `JAM`, the banked-UI source/recopy repair for help/inventory blank-screen hangs, the dungeon-descent ego-generation `JAM` caused by I/O-hole placement drift, the OPT-1 main-loop command-dispatch jump-table conversion, BUG-X IRQ decimal-mode hardening, and L3 VDC grey/light-grey policy cleanup are resolved.**

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
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |
| FEAT1 | LOW | Expand Mage/Priest spells from 16 to 31 each (62 total). Will require UI pagination and `magic_overlay.prg` if resident RAM limits are hit, but struct and effects logic already support this size. | Feature Request |
| **OPT-2** | LOW | Performance: Bounding Box Math. Optimize `dungeon_los.s` room bounds checks to save instructions. | Pending |
| **REF-1** | LOW | Refactor: Trampoline Sprawl. Consolidate the numerous `tramp_*` routines in `main.s` into a generic macro or parameterized `call_banked` routine to reduce redundancy. | Pending |
| **TST-5** | LOW | Testing: Miscellaneous Mechanics. Add isolated tests for disk swap procedures, palette mapping, and rendering draw routines. | Pending |

### Investigation Tasks (R4)
*(Moved to BUILDPLAN_HISTORY pending next cleanup)*

### Recently Resolved

| # | Severity | Description | Resolution Date |
|---|----------|-------------|-----------------|
| **C128-HEB**| **HIGH** | C128 Hardened Execution Boundary: MMU stability, atomic KERNAL I/O, loader-to-game handoff stabilization, and 100% test pass (40/40). | **2026-03-14** |
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
| **LDR-1** | **BLOCKER** | C128 post-chargen town-entry `JAM` fixed by restoring the missing low-RAM runtime loader contract for `runtime.low.prg`, aligning the PRG header with `$1000`, and loading the callable VDC runtime code into Bank 0 before title/runtime rendering under `MMU_ALL_RAM`. | **2026-03-18** |
| **UIB-1** | **BLOCKER** | C128 banked help/inventory blank-screen and dismiss hangs fixed by stopping per-entry recopy from an overlay-clobbered banked-payload source and tightening the inventory/equipment dismiss input path. | **2026-03-18** |
| **DGN-1** | **BLOCKER** | C128 town-to-dungeon descent `JAM` fixed by moving ego-item generation out of the `$D000-$DFFF` I/O hole and into loaded low runtime RAM, with placement asserts covering the entire call path. | **2026-03-18** |
| **OPT-TEST** | **HIGH** | C128 fast-test workflow is operational: `test128-fast` now runs the Python Gate C unit compare batch, `test128-fast-smoke` runs a small high-value smoke subset, and the workflow docs now direct agents to use them. The deeper Gate C.3 KickAssembler-server path remains toolchain-blocked/deferred. | **2026-03-19** |
| **OPT-1** | **MED** | Main-loop command dispatch is now O(1) for the discrete non-movement command set: the `CMD_STAIRS_DN..CMD_TUNNEL` equality chain in `game_loop.s` has been replaced with a bounded jump table while movement/running remain explicit fast paths. | **2026-03-19** |
| **OPT-3** | **MED** | `update_visibility` now caches the current lit room and skips room scans entirely when the player is on an unlit tile, so room bounds are only re-evaluated when the player enters or leaves a lit room. | **2026-03-19** |
| **TST-3** | **MED** | Shared UI menu/view isolation coverage is now in place via the focused C64 `ui_views` runtime suite, which validates character/help/inventory/equipment/recall/store/home layouts and is wired into the standard C64 runner. | **2026-03-19** |
| **TST-4** | **MED** | Subsystem coverage is now in place for Huffman decode, string-bank decode, C64 string-bank loader bookkeeping, C64 overlay bookkeeping, and SID/audio programming via a specialized monitor-driven sound harness. The work also fixed a real `sound_play` dispatch bug that had been collapsing all valid effects to `SFX_BUMP`. | **2026-03-19** |
| **REF-2** | **MED** | `game_loop.s` is now decoupled into a thinner orchestration file plus an in-place-imported `game_loop_helpers.s` split covering UI-only command flows, result-policy helpers, and shared post-turn tails, with focused C64/C128 loop-harness coverage protecting the new seams. | **2026-03-19** |
| **BUG-X** | **LOW** | IRQ decimal-mode hardening complete: C64 `irq_no_blink` and C128 Common-RAM `mmu_common_irq` / `mmu_common_nmi` now execute `cld` on entry, with focused opcode-level regression checks in the C64 config and C128 memory smokes. | **2026-03-20** |
| **L3** | **LOW** | C128 VDC grayscale policy is now coherent: `COL_LGREY` remains the brighter wall/UI grey, while canonical `COL_GREY` intentionally falls back to VDC dark grey so grey and light-grey no longer collapse. | **2026-03-20** |
| **DOC-1** | **LOW** | `commodore/c64/input.s` comments now explicitly state that numeric repeat prefixes are intentionally unimplemented and that `zp_input_count` stays pinned to 1 until the feature is deliberately revived. | **2026-03-20** |
| **TST-1** | **MED** | Input parsing suites, LOS coverage via dungeon/monster tests, and the focused `main_loop` dispatch harness are complete. | **2026-03-11** |
| **TST-2** | **HIGH** | Orchestration coverage expansion complete: added C64 `config` + `turn` runtime suites, C128 `config128` + `main_loop128` harnesses, and a restart-to-title death-path smoke. | **2026-03-11** |
| **TST-2A** | **HIGH** | Deterministic C128 title-load/resume smoke completed with generated `THE.GAME` seed injection and verified title `L` -> `load_resume_game` coverage in the default runner. | **Done (2026-03-11)** |
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
