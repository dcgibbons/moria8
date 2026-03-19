# C128 Test Harness Optimization Plan (Gate C: Extreme Edition)

## Objective
Transition the C128 test suite from "Fast" to "Near-Instant." Target total suite execution (40+ tests) in **<10 seconds**.

## 1. Eliminate JVM Startup (KickAssembler Server)
Even with a master module, single-file changes trigger a JVM reboot.
- **Strategy:** Use `java -jar KickAss.jar -server`.
- **Implementation:** 
  - Start a background KickAssembler server.
  - The Python orchestrator sends "Build" commands over a socket.
- **Result:** Assembly time drops from ~2s to ~200ms.

## 2. Eliminate Boot Latency (The "Golden Snapshot")
The C128 KERNAL boot process is dead time.
- **Strategy:** **VICE Snapshots (.vsf)**.
- **Implementation:**
  - Create a "ready.vsf" snapshot: A C128 booted to BASIC with the MMU already set to `$07` (Common RAM) and `$D011` cleared (blanked).
  - Launch VICE with `x128 -snapshot ready.vsf -binarymonitor`.
- **Result:** Machine is "Ready" in <10ms instead of 1.5s.

## 3. Persistent Binary Monitor Orchestration
Stop using `.prg` files and disk images for unit tests.
- **Strategy:** **Memory Poking via Monitor Port**.
- **Implementation:**
  - Replace the Bash loop with a Python orchestrator (`harness128.py`).
  - For each test:
    1. `memory-set` (POKE): Write the test binary directly into Bank 0 RAM via the monitor socket.
    2. `register-set`: Force the Program Counter (`PC`) to the test entry point and `SP` to `$FF`.
    3. `break-set`: Set a breakpoint at the `brk` instruction or the pass/fail signal address.
    4. `resume`: Let the CPU run at Warp speed.
    5. `memory-get`: Read result from `$0400`.
- **Result:** Zero disk I/O, zero file-system overhead.

## 4. Parallel "Worker" Clusters
Scaling to multi-core.
- **Strategy:** Multi-process VICE Pool.
- **Implementation:** 
  - Spawn `N` persistent VICE instances (where `N` = CPU cores).
  - Each instance listens on a unique monitor port (6510, 6511, etc.).
  - Distribute the 40 tests across the pool using a work queue.
- **Result:** 4x-8x throughput increase.

## 5. Implementation Roadmap
1. **Gate C.1 (The Orchestrator):** Build the Python `VICEConnector` class to handle socket-level binary monitor commands.
2. **Gate C.2 (The Snapshot):** Generate the optimized `.vsf` and verify monitor connectivity.
3. **Gate C.3 (Assembly Server):** Update the Makefile to support an persistent assembly server.
4. **Gate C.4 (Verification):** Port 5 tests to the new harness and compare timings.

### Incremental Step Landed (2026-03-18)
- `run_tests128.sh` now takes a pragmatic first optimization step before the full Gate C rollout:
  - `run_main_assembly_check` reuses `make build128` instead of unconditionally invoking raw KickAssembler
  - unit-test assembly now reuses fresh `.prg` / `.vs` artifacts instead of recompiling every test on every run
  - `TEST_JOBS` controls unit-test parallelism instead of a hardcoded worker count
  - hot-path address normalization reuses the shared shell helper instead of spawning extra Python one-liners
- This is **not** the final OPT-TEST state; it is a safe intermediate reduction in redundant work while the larger snapshot/monitor architecture remains pending.

### Incremental Step Landed (2026-03-18, variant reuse)
- The smoke/diagnostic asset builders in `run_tests128.sh` now reuse fresh outputs instead of blindly rebuilding every variant on each run.
- The harness now tracks which variant currently owns the shared `out/main.vs` / overlay scratch space and only skips work when that ownership matches.
- Base `build128` refresh is forced only when the active scratch outputs belong to a non-base variant, avoiding false reuse without forcing a full `make -B` rebuild.

### Incremental Step Landed (2026-03-18, targeted execution)
- `run_tests128.sh` now accepts `TEST_FILTER` as a regex over suite names.
- The filter applies to:
  - assembly/layout guard suites
  - parallel unit tests
  - smoke/diagnostic suites
- This allows fast focused runs such as `TEST_FILTER='main128_asm|input128' bash run_tests128.sh` and `TEST_FILTER='boot_title_idle_smoke|scripted_summary_to_town_smoke' bash run_tests128.sh`.

### Incremental Step Landed (2026-03-18, path hardening)
- `run_tests128.sh` now self-locates via the git repo root and changes into `commodore/c128` before running.
- The default KickAssembler path is now rooted at the detected repo root instead of depending on the caller's current working directory.
- This removes the previous mismatch where `bash commodore/c128/run_tests128.sh` worked differently from `cd commodore/c128 && bash run_tests128.sh`.

### Incremental Step Landed (2026-03-18, temp isolation)
- `run_tests128.sh` now allocates a per-run temp directory under `/tmp` and routes harness logs, monitor scripts, result files, and the KickAssembler symlink through that directory.
- The temp directory path is exported to child worker shells so parallel unit tests share the same run-local scratch space without colliding with other harness invocations.
- This removes the prior shared `/tmp/test128_*` namespace that could leak results across concurrent or back-to-back runs.

### Incremental Step Landed (2026-03-18, selective exclusion)
- `run_tests128.sh` now accepts `TEST_SKIP` as a regex exclusion over suite names.
- `TEST_SKIP` composes with `TEST_FILTER`: a suite must match the filter (if any) and must not match the skip regex.
- This supports focused commands like `TEST_FILTER='main128_asm|input128|config128' TEST_SKIP='input128' bash commodore/c128/run_tests128.sh`.

### Incremental Step Landed (2026-03-18, list-only resolution)
- `run_tests128.sh` now accepts `TEST_LIST=1` to print the resolved suite set without running any tests.
- The listing respects both `TEST_FILTER` and `TEST_SKIP`, and prints a final selected-suite count.
- This gives a cheap way to inspect what the harness will execute before spending time on assembly or VICE startup.

### Incremental Step Landed (2026-03-18, auto worker count)
- `run_tests128.sh` now accepts `TEST_JOBS=auto` to resolve the parallel unit-test worker count from the local CPU count.
- The resolved worker count is printed in the banner, and invalid/non-positive `TEST_JOBS` values fall back to the default worker count.
- This keeps the existing `TEST_JOBS=<n>` override while removing the need to hand-tune worker count on each machine.

### Incremental Step Landed (2026-03-18, timing visibility)
- `run_tests128.sh` now accepts `TEST_TIMINGS=1` to collect and print per-suite timing data.
- Timing data is written through the run-local temp directory and printed as a summary sorted by slowest suite first.
- This provides a measurement baseline for future harness work before moving into deeper architectural changes such as snapshots or persistent monitor orchestration.

### Incremental Step Landed (2026-03-18, repeated execution)
- `run_tests128.sh` now accepts `TEST_REPEAT=<n>` to execute the selected suite set multiple times in one invocation.
- Repeat works with `TEST_FILTER` and `TEST_SKIP`; `TEST_LIST=1` remains single-pass and reports that repeat is ignored in list-only mode.
- This gives a cheap flake-checking tool for a focused subset without external shell loops.

### Incremental Step Landed (2026-03-18, fail-fast execution)
- `run_tests128.sh` now accepts `TEST_FAIL_FAST=1` to stop after the first failing selected suite.
- Unit tests switch to serial execution when fail-fast is enabled so the harness can stop on the first failing unit instead of waiting for a parallel batch to finish.
- This is aimed at focused debugging runs where fast failure signal matters more than aggregate throughput.

### Incremental Step Landed (2026-03-18, machine-readable summaries)
- `run_tests128.sh` now accepts `TEST_SUMMARY=json|tsv` plus optional `TEST_SUMMARY_FILE=/path/to/output`.
- The harness records per-suite outcomes during execution and emits a machine-readable summary file at the end of the run.
- This provides a clean bridge to automation without scraping the human console text.

### Incremental Step Landed (2026-03-18, phase presets)
- `run_tests128.sh` now accepts `TEST_PHASE=` with explicit presets: `guards`, `units`, `smokes`, `diag`, `perf`, and comma-separated combinations.
- Phase presets compose with the existing filter/skip/list/repeat controls.
- This reduces the need to hand-maintain regexes for common harness subsets.

### Incremental Step Landed (2026-03-18, preset discovery)
- `run_tests128.sh` now accepts `TEST_DESCRIBE=1` to print the available phase presets and their suite expansions.
- When `TEST_PHASE` is also set, describe mode limits output to the selected preset names.
- This makes the preset layer discoverable without opening the shell script itself.

### Incremental Step Landed (2026-03-18, narrower phase presets)
- `run_tests128.sh` now exposes narrower `TEST_PHASE` presets: `boot`, `town`, and `cache`.
- These sit alongside the broader `guards`, `units`, `smokes`, `diag`, and `perf` groups.
- The narrower presets reduce regex churn for the most common focused smoke-debug loops.

### Incremental Step Landed (2026-03-18, suite-name consistency)
- The harness now prints the actual selected suite ids for renamed smokes and diags instead of legacy internal labels.
- This keeps `TEST_FILTER`, `TEST_PHASE`, console output, and summary exports aligned.
- The cleanup covered `boot_title_newgame_smoke`, `boot_tier_transition_smoke`, `real_input_town_move_diag`, and `cache_survival_smoke`.

### Incremental Step Landed (2026-03-18, summary export metadata)
- Summary exports now carry run metadata needed for repeated filtered runs: `phase`, `jobs_requested`, `jobs_resolved`, and per-result `iteration`.
- TSV exports gained an `iteration` column; JSON exports gained matching result-level `iteration` plus top-level run metadata.
- This keeps machine-readable output aligned with the console banner and repeat loop.

### Incremental Step Landed (2026-03-18, rerun from summary)
- `run_tests128.sh` now accepts `TEST_RERUN_FROM=/path/to/summary.{json,tsv}` to rerun only suites that previously failed.
- Replay selection is exact-suite based, deduplicated, and composes with `TEST_PHASE`, `TEST_FILTER`, and `TEST_SKIP`.
- This turns summary exports into a direct debugging input instead of a passive report artifact.

### Incremental Step Landed (2026-03-18, rerun last summary)
- `run_tests128.sh` now accepts `TEST_RERUN_LAST=1` to reuse the most recent recorded summary path automatically.
- When no explicit `TEST_SUMMARY_FILE` is provided, summaries now default to a stable `out/.test128_last_summary.{json,tsv}` path so the next invocation can replay them.
- The harness records the resolved summary path in `out/.test128_last_summary_path` and shows the resolved replay source in the banner.

### Incremental Step Landed (2026-03-18, rerun status selection)
- `run_tests128.sh` now accepts `TEST_RERUN_STATUS=<regex>` to control which summary statuses are replayed.
- The default remains `FAIL`, but replay can now target other statuses or combinations such as `FAIL|SKIP`.
- The active rerun status selector is shown in the banner and recorded in JSON summary metadata.

### Incremental Step Landed (2026-03-18, rerun latest-only selection)
- `run_tests128.sh` now accepts `TEST_RERUN_ONLY_LATEST=1` to evaluate replay status against only the latest summary entry for each suite.
- This avoids replaying suites that failed earlier in a repeated run but passed in a later iteration.
- Latest-only replay uses the summary `iteration` field when present and otherwise falls back to last occurrence order.

### Incremental Step Landed (2026-03-18, inverted replay selection)
- `run_tests128.sh` now accepts `TEST_RERUN_INVERT=1` to run everything except the replay-selected suite set.
- This makes summary-driven “all except known failures/skips” loops possible without hand-writing exclusion regexes.
- The active invert mode is shown in the banner, and JSON summary metadata now records `rerun_invert`.

### Incremental Step Landed (2026-03-18, capped replay selection)
- `run_tests128.sh` now accepts `TEST_RERUN_LIMIT=<n>` to cap the replay-selected suite set after status/latest/invert preprocessing.
- This makes large summary-driven reruns easier to sample or bisect without editing the source summary file.
- The active limit is shown in the banner, and JSON summary metadata now records `rerun_limit`.

### Incremental Step Landed (2026-03-18, replay order selection)
- `run_tests128.sh` now accepts `TEST_RERUN_ORDER=forward|reverse` to control which end of the replay-selected suite set is consumed first when a cap is active.
- This makes `TEST_RERUN_LIMIT` useful for both “first N” and “last N” triage loops.
- The active replay order is shown in the banner when not using the default `forward`, and JSON summary metadata now records `rerun_order`.

## 6. Comparison Table
| Phase | Cold Boot (Current) | Optimized (Gate C) | Improvement |
|-------|--------------------|--------------------|-------------|
| Assembly | 2.0s (per file) | 0.2s (Server) | 10x |
| Boot/Reset | 1.5s (per test) | 0.01s (Snapshot) | 150x |
| Code Load | 0.5s (Disk/VFS) | 0.05s (Monitor Poke) | 10x |
| **Total (40 tests)** | **~160s** | **~10s** | **~16x faster** |
