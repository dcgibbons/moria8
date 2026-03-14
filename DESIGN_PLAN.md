# DESIGN PLAN: Gate C.1 - Persistent VICE Test Runner

## Objective
Implement a Python-based test runner (`vice_test_runner.py`) that uses the VICE binary monitor to inject test binaries, execute them in "Warp Mode," and verify results without a full hardware reboot.

## 1. Architectural Strategy
Instead of `x128 -> boot -> run test -> exit`, we will move to a "Server/Client" model for testing:
- **Server:** A background `x128` instance listening on a binary monitor port (e.g., 6510).
- **Client:** `vice_test_runner.py` which connects, sends commands, and reads memory.

## 2. The `vice_test_runner.py` Workflow
For each `.prg` test file:
1. **Connect:** Establish a socket connection to `127.0.0.1:6510`.
2. **Reset/Quiet:** 
   - `reset 0` (Soft reset).
   - `fill 0000 00ff 00` (Clear Zero Page).
   - `> ff00 3e` (Ensure Bank 0 RAM/IO context).
   - `> d506 07` (Enforce Common RAM invariant).
3. **Inject:** `binload "[test_file].prg"` (Binary injection via monitor is near-instant).
4. **Execute:** 
   - `g [start_address]` (Jump to test entry).
   - Monitor for `stop` or a specific breakpoint address.
5. **Verify:**
   - Read `$0400` (Result code: $01=Pass, $02=Fail).
   - If Fail, read `$0401`+ for error message strings.
6. **Report:** Output results to console; return non-zero exit code if any test fails.

## 3. Hardware Invariants & Safety
- **MMU Isolation:** The runner MUST re-assert `$FF00=$3E` and `$D506=$07` before every test to prevent state leakage from previous crashes.
- **Interrupts:** The runner will assume `sei` is handled by the test entry point, but it can explicitly disable CIA interrupts via monitor `fill` if needed.

## 4. Implementation Phase C.1
- **File:** `commodore/c128/tests/vice_test_runner.py`
- **Dependencies:** Python 3.x, `socket` module (standard library).
- **Integration:** Update `commodore/c128/run_tests128.sh` to use the new runner.

## 5. Verification Plan
1. Launch `x128` manually with `-binarymonitor -console`.
2. Run `vice_test_runner.py` against `test_minimal128.prg`.
3. Verify the runner captures the "PASS" result correctly.
4. Intentionally break a test and verify the "FAIL" capture and error reporting.
5. Benchmark 5 tests: Target < 2 seconds total.
