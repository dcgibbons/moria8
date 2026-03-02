# C2 — C128 Keyboard Matrix Completeness and Input Responsiveness

**Status:** Open  
**Priority:** BLOCKER  
**Scope:** C128 input subsystem only (`input128.s`, C128 tests/docs)

## 1. Problem Statement

Current C128 keyboard behavior has two defects:

1. Matrix coverage is incomplete:
   - Scanner currently handles CIA rows 0-7 only.
   - Extended keyboard lines (8/9 via `$D02F`) are not scanned.
   - Numeric keypad and ESC path are therefore missing/incomplete.

2. Input responsiveness is degraded versus C64:
   - Key handling feels sluggish (notably `E`, plus other keys).
   - Current C128 `input_get_key` waits for full release before accepting a new press, which increases perceived latency and can miss fast repeated taps.

## 2. Root Causes

1. **Scan coverage gap**
   - `cia_scan_petscii` is limited to scan codes 0-63 (8 rows x 8 columns).
   - C128 extended lines require explicit drive through processor port `$D02F` bits 6/7.

2. **Latency behavior mismatch**
   - C64 path uses KERNAL buffered key input.
   - C128 path uses direct polling with strict release gating and no edge-transition queueing/repeat policy.

3. **No C128 input regression harness**
   - No dedicated automated test for scan completeness, decode correctness, and key transition behavior.

## 3. C2 Hard Invariants

1. Preserve existing C64 key semantics in shared gameplay code.
2. C128 scanner must restore hardware state after each scan (`$DC00/$DC02/$DC03/$D02F` neutral/expected).
3. No KERNAL SCNKEY/GETIN in C128 gameplay input path.
4. Existing vi/cursor mappings must remain functional.
5. Additions must be test-backed (no unverified key table changes).

## 4. Definition of Done

C2 is complete only when all are true:

1. Rows 0-9 are scanned correctly on C128.
2. Keypad `1..9` maps to 8-way movement and keypad `5` maps to rest.
3. ESC and keypad symbol keys are decoded per documented mapping.
4. Input responsiveness is improved:
   - no full-release-only lag on normal repeated command entry,
   - fast repeated presses of `E` and movement keys are reliably captured.
5. No regression in existing command mappings (vi/cursor/shifted commands).
6. C128 input tests pass in `run_tests128.sh`.
7. BUILDPLAN/ARCHITECTURE/C2 docs match implementation.

## 5. Commit-Sized Plan

### C2.0 Baseline Capture (No behavior change) ✅ Completed (2026-03-02)
- Capture current behavior notes:
  - missing keypad/ESC paths,
  - sluggish key response examples (`E`, direction keys).
- Add a short reproducible manual script in doc comments (title -> in-game key checks).
- Artifact: `commodore/c128/C2_BASELINE.md`

**Gate:** baseline artifact captured in this plan file.

### C2.1 Extend Matrix Scan to Rows 8/9 ✅ Completed (2026-03-02)
- Update `cia_scan_petscii`:
  - Rows 0-7: drive via `$DC00`, read `$DC01`.
  - Row 8: deselect CIA rows (`$DC00=$FF`), drive `$D02F` bit 6 low, read `$DC01`.
  - Row 9: deselect CIA rows (`$DC00=$FF`), drive `$D02F` bit 7 low, read `$DC01`.
- Preserve/restore `$D02F` state around scan.
- Scope note: this step adds row 8/9 scan-path plumbing and safe register restoration only; extended-key command mapping remains in C2.2/C2.4.

**Gate:** raw row/column decode works for lines 8/9 without breaking lines 0-7.

### C2.2 Expand Scan Decode Tables ✅ Completed (2026-03-02)
- Expand scan decode table from 64 to 80 entries (or explicit row-dispatch tables).
- Add row 8/9 mappings for:
  - keypad digits and symbols,
  - ESC and other supported extended keys.
- Keep unmapped keys explicit as `0`.

**Gate:** decoded PETSCII/virtual key codes match expected row/column map.

### C2.3 Improve Key Transition Logic (Responsiveness) 🚧 In Progress
- Replace strict blocking “release-then-press” loop with edge-based state tracking:
  - detect new press transitions,
  - allow fast repeated taps without requiring long release windows.
- Optional: add bounded repeat delay/rate if needed for held keys.
- Current status:
  - edge-transition state machine implemented in `input_get_key`,
  - SHIFT detection moved inline into the main scan loop (removed extra pre-scan passes),
  - automated C128 harness remains green,
  - manual feel validation for `E`/rapid taps still required before marking complete.

**Gate:** `E` and movement commands feel immediate and reliably repeat on rapid taps.

### C2.4 Map Extended Keys to Commands 🚧 In Progress
- Extend `petscii_to_command` mapping:
  - keypad `8/2/4/6` -> N/S/W/E
  - keypad `7/9/1/3` -> NW/NE/SW/SE
  - keypad `5` -> `CMD_REST`
  - ESC -> configured cancel/quit behavior (document exact choice)
- Preserve existing vi/cursor/shift mappings.
- Current status:
  - keypad movement and keypad `5` rest mappings implemented,
  - keypad `+` mapped to tunnel for parity with `+`,
  - ESC currently mapped to `CMD_QUIT` (pending UX confirmation).

**Gate:** keypad movement and rest verified in town + dungeon.

### C2.5 Add C128 Input Regression Tests 🚧 In Progress
- Add `tests/test_input128.s`:
  - row decode correctness (including rows 8/9 path),
  - mapping checks for keypad and ESC,
  - key transition behavior checks (press/release edges).
- Integrate into `run_tests128.sh` and C128 test target.
- Current status:
  - `test_input128.s` added and integrated in `run_tests128.sh`,
  - mapping coverage for keypad movement/rest, keypad `+`, ESC, and unmapped-key fallback is automated,
  - row-drive hardware path and edge-transition behavior tests still pending follow-up harness work.

**Gate:** input suite passes consistently with no flakes.

### C2.6 Integration and Docs Lock
- Manual integration checks:
  - title/menu navigation,
  - in-game repeated command entry speed,
  - no ghosting/cross-trigger with mixed key groups.
- Update:
  - `commodore/BUILDPLAN.md` (C2 status),
  - `commodore/c128/ARCHITECTURE.md` (input model),
  - this file.

**Gate:** docs reflect shipping input behavior exactly.

## 6. Key Mapping Target (Extended Rows)

Row 8 (Line 8 / `$D02F` bit 6 driven low), sense bits 0-7:
1. ALT
2. KP 8
3. KP 5
4. KP 2
5. KP 4
6. KP 7
7. KP 1
8. KP 0

Row 9 (Line 9 / `$D02F` bit 7 driven low), sense bits 0-7:
1. ESC
2. KP +
3. KP -
4. LINE FEED
5. KP 9
6. KP 6
7. KP 3
8. KP .

Note: final PETSCII/command encoding for non-gameplay keys (ALT, LINE FEED) should remain explicit and documented, even if mapped to `CMD_NONE`.

## 7. Risks to Guard Against

1. Leaving `$D02F` in driven-low state after scan (breaks keyboard behavior globally).
2. Regressing existing row 0-7 decode while adding row 8/9 support.
3. Introducing held-key flood without a repeat policy.
4. Ghost/phantom inputs from ambiguous multi-key states.
5. Mapping collisions between keypad codes and existing PETSCII commands.
