# P1 (C128 VDC) — Responsiveness-First Performance Plan

## Summary
P1 is measured by player-perceived responsiveness in this turn-based game:
movement commands should update the dungeon immediately (no perceived lag),
while preserving rendering correctness and C128 stability.

## Scope and Intent
- Primary goal: movement command -> visible dungeon update with low frame latency.
- Secondary goal: improve render throughput and reduce unnecessary work safely.
- Non-goal: real-time shooter-style frame budgets.

## Implementation Status

### 1. Baseline and Instrumentation (implemented)
- Added compile-time guarded C128 instrumentation (`PERF_P1`) in:
  - `common/perf_p1.s`
  - movement path hooks in `common/game_loop.s`
- Probe records:
  - frame-delta histogram buckets: `0`, `1`, `2`, `>=3`
  - path counters: local-area render, full redraw, scroll-driven full redraw
  - max observed frame delta
- Instrumentation is off by default; release behavior is unchanged.

### 2. Existing fast path lock (implemented)
- Kept `render_local_area` as the primary movement render path when:
  - viewport does not scroll
  - no room-reveal full redraw is required
- Added explicit scroll-path marking in perf mode to distinguish full redraw causes.

### 3. Low-risk-only optimization policy (active)
- P1 phase A only accepts bounded-risk optimizations that preserve behavior.
- High-risk options (major algorithm rewrites, aggressive VDC protocol changes)
  remain gated behind perf evidence.

### 4. High-risk options (deferred, gated)
- Consider only if phase A cannot satisfy responsiveness SLOs:
  - bulk map row copy via existing MMU helpers (`map_bulk_enter/exit`, `mmu_copy_map_row`)
  - entity-overlay architecture changes with parity tests
- VDC readiness polling remains mandatory by default.

## Acceptance Criteria

### A. Functional correctness
- `make test128` passes with instrumentation disabled.
- `PERF_P1=1 make test128` passes with instrumentation enabled.
- Existing C128 dungeon/VDC and MMU safety suites remain green.

### B. Responsiveness SLO (movement)
Measured in frame deltas from movement command recognition to render completion:
- Target profile:
  - `P50 <= 1 frame`
  - `P95 <= 2 frames`
  - `Max <= 3 frames`
- Hard fail:
  - reproducible sustained `>=3` frame movement latency during ordinary play
    (excluding loading/overlay transitions).

### C. Path behavior guarantees
- No-scroll movement continues to use local-area rendering by default.
- Full redraw occurs only when required (viewport scroll, room reveal, explicit redraw).

### D. Safety constraints
- MMU IRQ-state preservation tests remain green.
- No new map-buffer boundary clobber findings in perf-mode tests.
- Manual smoke in VICE (`make run128`) shows no new JAM/crash in movement loops.

## Test and Run Commands

### Default mode (instrumentation OFF)
- `make test128`

### Perf mode (instrumentation ON)
- `PERF_P1=1 make test128`

### Manual smoke
- `make run128`

## Artifacts
- Added: `common/perf_p1.s` (C128 `PERF_P1` probe module).
- Added: `c128/tests/test_perf_p1.s` (histogram/counter runtime validation).
- Updated: `c128/run_tests128.sh` to support `PERF_P1=1` mode.
