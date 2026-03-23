# AGENT.md

This file provides foundational mandates and technical guidance for AI agents (Gemini CLI, Claude Code, etc.) when working with this repository.

## Workflow Orchestration
### 1. Plan Node Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately - don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity
### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One tack per subagent for focused execution
### 3. Self-Improvement Loop
- After ANY correction from the user: update "tasks/lessons.md' with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project
### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness
### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes - don't over-engineer
- Challenge your own work before presenting it
### 6. Autonomous Bug Fizing
- When given a bug report: just fix it. Don't ask for hand-holding. Caveat: if
  asked to just add it to the list, then just add it to the list.
- Point at logs, errors, failing tests - then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how
## Task Management
1. **Plan First**: Write plan to "tasks/todo.md" with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to 'tasks/todo.md"
6. **Capture Lessons**: Update 'tasks/lessons.md' after corrections
## Core Principles
- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimat Impact**: Changes should only touch what's necessary. Avoid introducing bugs.

## Project Overview

Port of the rogue-like game Moria to Commodore 64 and 128, written entirely in 6502 assembly using the Kick Assembler toolchain. Based on [umoria](https://github.com/dungeons-of-moria/umoria) (originally PASCAL on VAX/VMS).

## Build and Test

- **Build:** `make` (or `make build`) — assembles `main.s` → `out/moria8.prg`
- **Run:** `make run` — build and launch in VICE
- **Test:** `make test` — assemble + run all tests in VICE headless
- **C128 fast units:** `make test128-fast` — Python Gate C compare harness for the stable C128 unit batch
- **C128 fast smokes:** `make test128-fast-smoke` — small high-value C128 smoke subset (`boot_title_idle_smoke`, `scripted_summary_to_town_smoke`, `town_overlay_smoke`)
- **C128 full suite:** `make test128` — authoritative full C128 shell harness
- **Disk image:** `make disk` — create a .d64 disk image
- **Clean:** `make clean` — remove build artifacts
- **Assembler:** Kick Assembler — auto-downloaded on first `make` into `tools/kickass/` (override: `make KICKASS=/path/to/KickAss.jar`)
- **Testing:** Kick Assembler `.assert` directives (assembly-time) + VICE headless runtime tests
- **Entry point:** `commodore/c64/main.s`

The root Makefile delegates to `commodore/c64/Makefile`. All make targets work from the project root.

When running VICE headless for testing, be sure to use -warp mode to improve
test speed.

### C128 test-selection policy
- For **fast iteration on C128 unit-level changes**, prefer `make test128-fast`.
- For **fast runtime regression checks on C128 boot/chargen/town paths**, prefer `make test128-fast-smoke`.
- Before declaring a broad C128 refactor or high-risk memory/banking change complete, run the authoritative suite with `make test128`.

## Planning Docs (Commodore port)

When working on the Commodore port:

- **`commodore/BUILDPLAN.md`** — active plans only (current state, priority triage, optimization plans)
- **`commodore/DESIGN.md`** — architecture reference (memory map, design decisions, banking architecture)
- **`commodore/BUILDPLAN_HISTORY.md`** — completed work archive (finished phases, reviews, audits)

When completing a feature or optimization from `commodore/BUILDPLAN.md`, move the finished section to `commodore/BUILDPLAN_HISTORY.md`.

## Memory Segment Boundaries (ABSOLUTE — NEVER VIOLATE)

Moving code or data between segments (e.g., pulling an `#import` out of a `.pseudopc` block into the main segment) changes segment sizes. **You MUST verify segment boundaries after ANY such change.** Violations cause silent corruption, wild jumps into data, and CPU JAMs.

- **Main segment MUST end below $C000.** MAP_BASE (dungeon map) lives at $C000. $D000–$DFFF is the I/O hole — code placed there reads back as register garbage.
- **Banked payload (`.pseudopc $E80E`) must fit below $FFFA** (CPU vectors).
- **Each overlay segment must fit in $E000–$EFFF** (4 KB).
- **Test code MUST start below $A000** (BASIC ROM boundary).

After ANY `#import` reordering: rebuild, check the Memory Map output, confirm Default segment ends below $C000. **NEVER delete boundary-checking `.assert` statements** — if an assert fails, fix your change, not the assert.

## C128 Runtime-Loaded Code Contract (NEW — MUST VERIFY)

Several multi-week C128 regressions came from treating “the symbol exists” as if that meant “the CPU can execute it.” That assumption is false on C128.

For any runtime-loaded, banked, copied, or trampolined C128 code path, you MUST verify all of the following together:

1. **Linked symbol address** — where the assembler says the routine lives
2. **PRG load header** — where the file says it should load
3. **Load destination bank** — which bank actually receives the bytes
4. **Visible execution bank** — which bank the CPU is executing when the call happens
5. **Copy source and destination safety** — whether any staged source used for later recopies survives overlays/boot scrubs and whether the runtime destination stays out of reserved regions

If any one of those is wrong, the bug will usually present as a “random” `JAM`, `BRK`, or moving crash address.

### C128-specific failure modes to keep in mind
- **Low address does not mean common RAM.** `$1000-$3FFF` is **not** common RAM in the shipping C128 runtime. A direct `JSR $1000` only works if the code is loaded into the bank visible at that callsite.
- **The I/O hole executes garbage.** `$D000-$DFFF` is never safe for normal code/data execution with I/O visible. A trampoline below `$D000` is not enough; the callee must also stay out of the hole.
- **Overlay safety includes recopy sources.** A resident `$F000` payload can still be corrupted if the staged source bytes used by `init_copy_banked` overlap `$E000-$EFFF` and get overwritten by overlay loads.
- **Moving crashes usually mean ownership drift.** Re-anchor on the latest monitor trace and ask what memory/bank contract changed, not just which function ran last.

### Mandatory verification after C128 layout or banking changes
- Rebuild and read the Memory Map / `.print` output.
- Check the emitted symbol addresses in `out/main.vs` or `main.sym`.
- Confirm the PRG header matches the intended runtime address.
- Confirm the loader writes to the bank the callsite actually executes.
- Add or update `.assert` statements for both trampolines **and** their callees.

## Architecture

- **Display:** 40-column on C64; 40 or 80-column selectable on C128. PETSCII characters only (no bitmap graphics).
- **Loading:** BASIC stub loader runs the ML program. Cartridge version also supported. Minimize disk access after initial load — organize data so each dungeon level has what it needs in memory (e.g., higher-level monsters only loaded for deeper levels).
- **KERNAL/BASIC:** Use C64/C128 KERNAL routines freely. Do NOT use BASIC routines after the initial loader. Since BASIC is not active, its zero page space is available for program use.
- **Memory:** Use C64 memory banking to access RAM behind BASIC ROM for extra program space. Program should be able to exit cleanly back to BASIC.
- **Source organization:** Small, modular files each targeting a single piece of functionality. C64 sources live in `commodore/c64/`, with `commodore/c128/` reserved for the future C128 port.

## Coding Conventions

- Use canonical 6502 assembly conventions for Kick Assembler
- Every feature must have unit tests (`.assert` for compile-time, VICE headless for runtime)

## Test Bootstrap Requirement

Test files that grow past $A000 will **silently hang** in VICE. `BasicUpstart2(test_start)` generates a BASIC `SYS` to `test_start`, but at startup BASIC ROM is banked in at $A000-$BFFF. If `test_start` lands in that range, SYS jumps into ROM code instead of the test — causing an infinite loop / cycle-limit timeout with no error message.

**Fix:** Any test whose assembled code crosses $A000 must use the bootstrap trampoline pattern (see `test_item.s`): a small stub at $080E that banks out BASIC ROM first, then `jmp test_start`. `BasicUpstart2` points to the stub, not `test_start` directly. The "Test Code" segment label goes on the stub so `run_tests.sh` extracts the correct breakpoint address.

**How to check:** After assembling, look for `test_start` in the symbol file. If its address is >= $A000, the trampoline is required. Adding new `#import` lines (e.g., `reu.s`, `tier_manager.s`) can push `test_start` past $A000 without any other code changes.

## Test Timeouts

NEVER use more than 30 seconds for a test timeout; tests taking longer than
that are failing or stuck.

# AI Team Instructions

## Testing Workflow
- When a feature is implemented, the **tester** agent must run tests.
- Use the `monitor` tool for suites taking longer than 30 seconds.
- The **writer** cannot finalize a task until the **tester** reports 'ALL TESTS PASSED'.

## Environment
- Python: Use the local `.venv` (run commands via `source .venv/bin/activate && ...`)
- Node: Use `npm`
