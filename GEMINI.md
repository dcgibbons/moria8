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

## 3. Engineering Standards
- **Simplicity First:** Impact minimal code. Avoid "just-in-case" alternatives.
- **No Laziness:** Find root causes. No temporary "defensive" traps unless specifically for debugging a known, transient race condition.
- **Idiomatic Quality:** Adhere to existing 6502/KickAssembler conventions (SoA, 16-bit math via `math.s`).

## 4. Verification Protocol
- **Empirical Reproduction:** Bug fixes must start with a reproduction script or test case that fails *before* the fix is applied.
- **Validation is Final:** A change is incomplete without verification logic (tests or manual VICE verification).
