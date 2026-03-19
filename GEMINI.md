# GEMINI.md — Global Orchestrator's Law

This file provides foundational mandates that take absolute precedence over general workflows. All agents MUST adhere to these invariants to ensure architectural integrity and prevent context drift.

## 1. Tactical Orchestration
- **Mandatory Plan Mode:** Any task affecting more than 2 files or involving MMU/banking/Zero Page ownership MUST use `enter_plan_mode` to draft a `DESIGN_PLAN.md`.
- **The "Three-Strike" Rule:** If a test or build fails 3 times with the same error, STOP. You are in a loop. Re-read `ARCHITECTURE.md` and use `codebase_investigator` to find the root cause before any further `replace` calls.
- **Regression Alarm:** No task is complete until the full C128 smoke test suite passes. If any existing test fails, the "fix" is a regression and must be discarded.

## 2. Hardware Invariants (Global)
- **Credential Protection:** Never log or commit secrets, API keys, or `.env` files.
- **Source Control:** Do not stage or commit changes unless explicitly requested by the user.
- **Zero Page Integrity:** $02–$8F is "Game-Owned." $90–$FF is "KERNAL-Volatile." Never use KERNAL-Volatile ZP for long-lived game state without a caller-save strategy.

## 2a. Memory Segment Boundaries (ABSOLUTE — NEVER VIOLATE)
Moving code or data between segments (e.g., pulling an `#import` out of a `.pseudopc` block into the main segment, or vice versa) changes segment sizes. **You MUST verify segment boundaries after ANY such change.** Violations cause silent corruption, wild jumps into data, and CPU JAMs that are extremely hard to diagnose.

### C64 Boundaries
- **Main segment MUST end below $C000.** MAP_BASE (dungeon map) lives at $C000. Code past this overwrites the map.
- **Test code MUST start below $A000.** BASIC ROM is banked in at $A000–$BFFF at startup.

### C128 Boundaries
- **Main segment MUST end below $C000.** Same MAP_BASE constraint as C64.
- **$D000–$DFFF is the I/O hole.** Code or data placed here by the assembler will read back as VIC-II/SID/CIA register values, not your code. The CPU will execute garbage.
- **Banked payload (`.pseudopc $E80E`) must fit below $FFFA** (CPU vectors).
- **Each overlay segment must fit in $E000–$EFFF** (4 KB).

### Mandatory Verification Steps
1. **After ANY `#import` reordering or movement between segments:** rebuild and check the Memory Map output. Confirm the Default segment ends below $C000.
2. **Check the `.print` output** for segment sizes (e.g., "Banked payload: NNNN bytes").
3. **Do NOT delete boundary-checking `.assert` statements.** They exist to catch exactly this class of mistake. If an assert fails, it means your change broke the memory layout — fix the change, not the assert.
4. **If the main segment is near $C000:** move overflow code to $F000 (RAM under KERNAL ROM) via trampoline, or into the banked payload / an overlay. Do NOT just pull code from the payload into main.

### C128 Runtime Contract Law (NEW)
For any runtime-loaded or trampolined C128 code path, it is not enough to verify only the trampoline or only the symbol. You must verify the full contract:

1. linked symbol address
2. PRG load header
3. destination bank at load time
4. visible bank at execution time
5. survival of any staged source used for later recopies

Concrete failure patterns that already happened in this repo:
- callable low-RAM code linked at `$1000` but loaded into the wrong bank
- banked UI code recopied from a staged source span later clobbered by overlays
- a safe trampoline below `$D000` calling a callee that had drifted into the `$D000-$DFFF` I/O hole

If the crash address moves, stop treating it as a local logic bug until you have checked this contract.

## 3. Engineering Standards
- **Simplicity First:** Impact minimal code. Avoid "just-in-case" alternatives.
- **No Laziness:** Find root causes. No temporary "defensive" traps unless specifically for debugging a known, transient race condition.
- **Idiomatic Quality:** Adhere to existing 6502/KickAssembler conventions (SoA, 16-bit math via `math.s`).

## 4. Verification Protocol
- **Empirical Reproduction:** Bug fixes must start with a reproduction script or test case that fails *before* the fix is applied.
- **Validation is Final:** A change is incomplete without verification logic (tests or manual VICE verification).
