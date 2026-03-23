# Action Plan C4: Resolve C128 Map/Program Memory Collision

**Status:** Completed through C4.8, with post-lock stabilization fixes applied (2026-03-02)  
**Priority:** BLOCKER  
**Owner:** C128 Port Team

## 1. Problem Statement

Current C128 layout puts:
- `MAP_BASE = $0B00` (3,840 bytes, `80x48`)
- Program entry at `$1C0E` with main code growing upward

This leaves no safety margin and has already produced overlap/corruption failures.

## 2. C4 Scope (Strict)

C4 is only:
1. Relocate the map to Bank 1 (`$4000`) for C128.
2. Keep gameplay dimensions at `80x48` for now.
3. Preserve C64 behavior and existing save/gameplay semantics.

Out of scope for C4:
- `198x66` map rollout (Phase 10.3)
- Gameplay redesign
- Broad refactors unrelated to memory banking

## 3. Hard Invariants

These are mandatory during C4:

1. `MAP_COLS=80`, `MAP_ROWS=48`, `MAP_SIZE=3840`.
2. BFS queue remains Bank 0 scratch (`$0400` path), not map-banked.
3. No long-lived ambient Bank 1 context across mixed gameplay logic.
4. Map accesses use atomic C128-safe wrappers/macros, except dedicated bulk helpers.
5. MMU helper routines must preserve interrupt state (must not force-enable IRQ).
6. Boot copy/common-RAM behavior must be validated on both PRG and D64 startup paths.
7. MMU primitives are not called from general common gameplay code:
   - Single-tile map access goes through one API surface (`map_get_tile` / `map_set_tile`).
   - Bulk map operations go through dedicated centralized helpers only.

## 4. Definition of Done

C4 is complete only when all are true:

1. `make -C commodore/c128 build128` passes.
2. C128 smoke boot works from:
   - direct PRG boot
   - D64 `moria8.128` chain-load
3. C128 regression harness passes (`minimal128`, `memory128`, `dungeon128`, `soak128`, `boot_d64_smoke`, `boot_diag_copy`).
4. 200 repeated dungeon generations complete without hang/jam/corruption.
5. BUILDPLAN and architecture notes match actual addresses and current scope.
6. New-game path is stable end-to-end (title -> character creation -> town -> first dungeon entry) without monitor BREAK/jam or render corruption.

## 5. Commit-Sized Execution Plan

Each step should be one small PR/commit with a single intent.

### C4.0 Baseline Snapshot (No behavior changes)
- Capture current failing behavior, crash signatures, and test baseline.
- Record exact symptoms for PRG and D64 startup.
- Output: `C4_BASELINE.md` artifact in `commodore/c128/` (or issue comment equivalent).

**Gate:** reproducible baseline documented.

### C4.1 Add C128 Banking Test Harness
- Add dedicated C128 test sources (do not depend on C64 test imports):
  - `test_memory128.s`
  - `test_dungeon128.s`
  - `test_soak128.s` (added in C4.7)
- Add a C128 test runner script (`run_tests128.sh`) with pass/fail summary.
- Add `make -C commodore/c128 test128` target.

**Gate:** Harness runs and reports failures reliably on current baseline.

### C4.2 Introduce MMU Primitives With IRQ-State Preservation
- Implement C128 map-bank primitives in one place (`config128.s` or `memory128.s`).
- Ensure wrappers preserve prior interrupt state (no unconditional `cli`).
- Add unit tests for:
  - bank switch/restore correctness
  - IRQ state preservation

**Gate:** `test_memory128` passes all new MMU/IRQ tests.

### C4.3 Relocate Map Constants Only (No Call-Site Migration Yet)
- C128-only constants:
  - `MAP_BASE = $4000`
  - `MAP_END = $4EFF` (`3840` bytes total)
- Keep floor items / creature scratch in explicitly safe Bank 0 locations (documented).
- Add compile-time asserts for map size and end-address math.

**Gate:** Build passes with map constants moved; runtime expected to fail until call-site migration is done.

### C4.4 Migrate Map Access Paths to Atomic Wrappers
- Convert map reads/writes in shared code paths to wrapper macros/subroutines.
- Keep this step mechanical: no algorithm changes.
- Explicitly exclude BFS queue accesses (`$0400`), which remain Bank 0 direct.
- Architectural boundary for this step:
  - `common/dungeon_data.s` owns single-tile map access (`map_get_tile` / `map_set_tile`).
  - MMU primitives are consumed only by that single-tile API and by dedicated bulk helpers.
  - Avoid scattering `.if (C128)` MMU conditionals through general common gameplay code.

**Gate:** `test_dungeon128` compiles/runs; failures reduced to known remaining bulk-path gaps.

### C4.5 Add Bulk Map Helpers and Replace Hot Loops
- Add dedicated bulk helpers for fill/clear operations (C128-safe, Bank1-internal).
- Replace raw absolute bulk loops in:
  - town/dungeon map fill
  - connectivity cleanup paths
- Do not wrap whole generation routines in ambient Bank1 mode.
- Bulk-helper rule:
  - Performance-critical loops may bypass single-tile API, but only via centralized bulk helper routines.
  - No ad-hoc per-call-site MMU switching in generation/gameplay modules.

**Gate:** dungeon generation regression tests pass without bank-context leakage.

### C4.6 Bootloader and Common-RAM Validation
- Validate boot transfer path explicitly:
  - Bank 1 stage load
  - copy-to-Bank0 logic
  - common-RAM configuration timing
- Add boot diagnostics test mode (small signature writes/checks) behind debug flag.

**Gate:** PRG and D64 boot both reach title/input loop consistently.

### C4.7 Stress and Soak
- Add automated repeated-generation loop test (200 iterations minimum).
- Add deterministic RNG seed variants.
- Fail on any jam, IRQ drift, or map corruption markers.

**Gate:** Soak test clean.

### C4.8 Documentation Lock
- Update:
  - `commodore/BUILDPLAN.md`
  - `c128/ARCHITECTURE.md`
  - this file (`C4_PLAN.md`)
- Ensure no doc claims `198x66` is complete.

**Gate:** docs match shipping code exactly.

### C4.9 Post-Lock Stabilization: KERNAL Vector/LOAD Path (applied)
- Fix C128 KERNAL vector handling in RAM mirror:
  - Do not rewrite `$FFC3..$FFD2` operands as direct JMP targets (they are indirect ROM stubs).
- Fix C128 asset-load path:
  - Use direct `$FF68`/`$FFD5` calls inside `EnterKernal` context to avoid MMU-mode leakage and recursive CLOSE/CLRCHN failures.

**Gate:** New game no longer loops in KERNAL CLOSE/CLRCHN path after disk activity.

### C4.10 Post-Lock Stabilization: Generation/Render Bank Safety (applied)
- Fix generation bulk helpers so overlay code at `$E000` does not execute under a Bank 1 MMU context.
- Fix C128 VDC renderer to read map tiles via MMU-safe map access macros, not raw Bank 0 pointer reads.

**Gate:** Town and first dungeon entry render correctly on C128 after character creation.

## 6. Common Failure Modes to Guard Against

1. Writing map data to Bank 0 due missing/incorrect bank switch.
2. Using map wrappers for non-map memory (ex: BFS queue).
3. Unbalanced MMU transitions around KERNAL/I/O calls.
4. Interrupt state accidentally re-enabled by helper macros.
5. Address math drift (`MAP_END`, map-size comments/asserts mismatch).

## 7. Test Matrix (Minimum)

1. `minimal128`:
   - harness sanity / pass-loop monitor path
2. `test_memory128`:
   - Bank 0 vs Bank 1 isolation at same address
   - wrapper read/write correctness
   - IRQ-state preservation across wrappers
3. `test_dungeon128`:
   - fill/room/corridor/connectivity paths
   - BFS queue integrity (`$0400` path)
4. `test_soak128`:
   - 200 deterministic generation iterations
   - jam prevention, IRQ drift checks, map corruption sentinels
5. integration smoke:
   - boot path (PRG and D64)
   - enter town, descend, generate dungeon, basic movement

## 8. Change Control Rules for C4

1. One behavior change per commit.
2. No mixed refactor + behavior commits.
3. Any new banking helper must ship with a direct test.
4. No "optimize while fixing" changes inside C4.
5. If a step fails its gate, revert that step only and re-approach.
6. Keep MMU logic centralized; reject PRs that introduce new scattered `.if (C128)` MMU call-sites in common gameplay code.

## 9. Exit / Follow-on

After C4 closes, open a separate plan for Phase 10.3 (`198x66`) that starts from the stable C4 banking baseline and includes its own performance and save-format impact analysis.
