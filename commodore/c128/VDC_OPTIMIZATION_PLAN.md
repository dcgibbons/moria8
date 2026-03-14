# C128 Test Harness Optimization Plan (Gate C)

## Objective
Reduce the total execution time of the C128 runtime test suite (40+ tests) from ~3-5 minutes to <30 seconds.

## 1. Eliminate JVM Startup Overhead
The current `run_tests128.sh` invokes `java -jar KickAss.jar` for every individual `.s` file.
- **Strategy:** Transition to a **"Master Test Module"** approach or a dependency-aware Makefile.
- **Implementation:** 
  - Create a single `tests/all_tests128.s` that imports all individual test suites.
  - Use `.segment` and `.pc` offsets to pack all tests into a single large binary.
  - This allows a **single assembly pass** (one JVM startup) to generate the entire test executable.
- **Goal:** Save ~60-80 seconds of JVM warm-up time.

## 2. Eliminate VICE Hardware Reset Latency
Launching a new `x128` instance per test incurs a ~2-second boot tax.
- **Strategy:** **Persistent Emulator Session** with binary injection.
- **Implementation:**
  - Launch one `x128` in the background with `-binarymonitor`.
  - Use a python script (`vice_test_runner.py`) to connect to the monitor port.
  - For each test:
    1. `LOAD` the test binary into RAM via the monitor.
    2. `SET PC` to the test entry point.
    3. `RUN` until a `BRK` ($00) or a specific address is hit.
    4. Capture the pass/fail byte from `$0400` (screen RAM).
    5. `RESET` the PC and Stack without rebooting the whole machine.
- **Goal:** Reduce per-test boot latency from 2000ms to <100ms.

## 3. Parallel Execution
The current `for` loop is strictly sequential (Serial Execution).
- **Strategy:** Parallelize the test runner across multiple CPU cores.
- **Implementation:**
  - Use `xargs -P [n]` or a parallel Python `ThreadPoolExecutor`.
  - Each worker launches its own background VICE on a unique monitor port (e.g., 6510, 6511, etc.).
- **Goal:** 4x to 8x speedup on multi-core development machines.

## 4. Testing "Warp Mode" Enforcement
Ensure the emulator is doing zero unnecessary work.
- **Strategy:** Force `-warp` and `-limitcycles`.
- **Implementation:** 
  - Update `run_tests128.sh` to always include `-warp`.
  - Use the VICE monitor `exit` command instead of waiting for cycle timeouts.
- **Goal:** Maximum possible execution speed during the test run.

## 5. Implementation Steps
1. **Gate C.1:** Create `vice_test_runner.py` for binary injection and monitor-based verification.
2. **Gate C.2:** Modify `Makefile` to assemble all tests into a single binary or use a parallel build strategy.
3. **Gate C.3:** Update `run_tests128.sh` to orchestrate the parallel persistent-monitor sessions.
4. **Gate C.4:** Verify all 40+ tests pass in the new optimized harness.

## 6. Success Metric
- Total suite runtime <30 seconds on a standard modern developer machine.
- Zero regressions in test coverage.
