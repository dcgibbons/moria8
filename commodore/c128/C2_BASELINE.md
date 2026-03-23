# C2 Baseline Snapshot (2026-03-02)

## 1. Scope

Baseline for C2 (C128 keyboard matrix completeness + responsiveness) before C2 implementation work.

This snapshot captures current known input defects:
1. Missing extended matrix lines (rows 8/9) support.
2. Sluggish command response versus C64 path (notably `E`, and some other keys).

## 2. Current Behavior

### 2.1 Matrix Coverage

- C128 scanner currently handles CIA keyboard rows 0-7.
- Extended C128 lines driven via `$D02F` (rows 8/9) are not yet integrated.
- Practical impact:
  - Numeric keypad movement support is incomplete/missing.
  - ESC and other extended keys are not reliably available via current command path.

### 2.2 Responsiveness

- C128 input feels slower than C64 in gameplay.
- Fast repeated key taps (especially `E`) can feel delayed or intermittently dropped.
- Current implementation uses direct polling with release-then-press gating, which increases perceived latency.

## 3. Repro Scripts (Manual)

### 3.1 Sluggish `E` Repro

1. Boot C128 build to main loop.
2. Enter gameplay where `E` command is valid.
3. Tap `E` repeatedly at moderate-fast cadence.
4. Compare to C64 build under same cadence.

Observed baseline:
- C128 command response cadence is visibly slower and less consistent than C64.

### 3.2 Extended Key Coverage Repro

1. Boot C128 build to gameplay.
2. Attempt keypad movement (`KP 8/2/4/6`, diagonals, `KP 5`) and ESC-driven action where applicable.

Observed baseline:
- Extended keypad/ESC behavior is incomplete or absent in command mapping path.

## 4. Exit Criteria to Validate Improvement

After C2 implementation:
1. Rows 8/9 decode correctly and map as documented.
2. Keypad movement + keypad rest operate in town and dungeon.
3. Rapid repeated `E` and movement keys register without sluggish release-gate feel.
4. C128 input regression test suite passes in `run_tests128.sh`.
