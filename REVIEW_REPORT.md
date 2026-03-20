# Review Report: C128 Stability Postmortem — Two-Part Loader/Execution Failure

## 1. Executive Summary

The long C128 stability incident was not one bug. It was two distinct memory/loader failures that presented as one “wandering crash”:

1. **First half:** title-load bank-safety and KERNAL-wrapper issues corrupted live Bank 0 code during boot/title flow.
2. **Second half:** callable VDC runtime code linked at `$1000` was not being loaded into the bank that actually executed it after character creation.

Both bugs produced misleading symptoms:

- crashes moved around
- the PC often landed in data instead of code
- adjacent subsystems looked guilty even when they were only the last code to run

The key outcome is that the C128 port now has a clearer rule:

**For any runtime-loaded code path, the symbol address, PRG load header, destination bank, and visible execution bank must all agree.**

---

## 2. Part I — Title/Boot Memory Corruption

This was the **first half** of the larger problem and the original focus of this report.

### What happened

The title-load path and related KERNAL wrapper behavior could write data into the wrong bank or return with corrupted banking assumptions. That caused live Bank 0 code to be overwritten during the title/boot sequence.

### Why it was hard to diagnose

- the corruption happened earlier than the eventual crash
- the observed `BRK`/`JAM` location depended on what code got executed after the overwrite
- the visible failure often looked like an MMU or revision/alignment problem rather than a plain RAM corruption problem

### First-half root causes

1. **Title art destination banking had to be explicit**
   - the title art PRG loads at `$4000`
   - on C128, that load must be directed to the correct bank with `SETBNK`
   - if the destination bank is wrong, the loader writes over live Bank 0 program RAM

2. **`safe_setbnk` had to preserve registers correctly**
   - any wrapper bug around `SETBNK` effectively turns a correct loader call into a silent wrong-bank write

3. **Boot/runtime copy paths needed exact page coverage**
   - partial copy or off-by-one page behavior can leave callable code partly uninitialized
   - that makes later crashes look unrelated to the original loader defect

### First-half fixes

- restored/kept explicit bank-safe title loading
- hardened `safe_setbnk` register handling
- corrected low-level copy assumptions so callable code is fully initialized

### What this solved

It removed the early boot/title corruption class and stabilized the loader-to-runtime handoff enough to expose the next real bug instead of masking it.

---

## 3. Part II — Low-RAM Runtime Loader Contract Failure

Once the first-half corruption was removed, the remaining blocker became visible:

- after character creation
- before stable town entry
- direct `JSR $1000`
- CPU executing garbage / stale bytes

### Actual root cause

`viewport_update` / `render_viewport` were linked at low RAM `$1000`, but the runtime loader contract for that code was broken.

Specifically:

1. `runtime_low.prg` existed on disk but **was not actually loaded by the engine** before the first render-capable runtime path.
2. The segment was linked for execution at `$1000`, but the emitted PRG initially still carried the wrong load assumptions.
3. The first attempted repair loaded the code into **Bank 1**, but the real callsites execute under `MMU_ALL_RAM` — **Bank 0**.
4. `$1000-$3FFF` is **not** bottom common RAM, so Bank 1 residency does not satisfy a direct Bank 0 `JSR $1000`.

### Why this looked like chargen/summary corruption

- the crash happened immediately after sex selection / summary flow
- the last visible UI step was chargen
- monitor traces moved between summary-adjacent paths and low RAM
- the failure only became obvious once the active PC was re-anchored on the latest trace

### Second-half fixes

1. **Aligned header and symbol address**
   - `runtime_low.prg` now emits with a `$1000` PRG header

2. **Added the missing startup loader**
   - startup now explicitly loads `RUNTIME_LOW.PRG` before the title screen and any later VDC render path

3. **Loaded into the correct bank**
   - the callable `$1000` runtime block is loaded into **Bank 0**, matching the actual `MMU_ALL_RAM` execution context

4. **Added placement guardrails**
   - compile-time assertions now protect the low-RAM callable block from overlapping gameplay data

5. **Hardened the summary prompt handoff**
   - added explicit release-wait behavior around the gender-selection → summary transition
   - improved `input_wait_release` so it uses the shared key edge-state logic instead of a fragile raw-scan heuristic

### What this solved

- title -> new game
- full character creation
- summary
- town entry

This was the blocker that consumed the final two-week stretch of the investigation.

---

## 4. Combined Lessons

### A. A moving crash address usually means ownership, not the current function

When a C128 crash keeps moving, the first question should be:

- what memory got overwritten?
- what bank is visible here?
- is the CPU executing the bank we think it is?

### B. Low address does not imply common RAM

On C128, a callable symbol at `$1000` is **not** automatically safe across banks. Bottom common ends at `$0FFF` in the shipping runtime configuration.

### C. Loader correctness is four-part, not one-part

For any runtime-loaded code/data block, verify all four:

1. linked symbol address
2. PRG load header
3. destination bank at load time
4. visible bank at execution time

If any one of those differs, the bug will often present as “random code corruption.”

### D. Re-anchor on the latest monitor trace

Do not keep patching the earlier hypothesis once the PC/backtrace moves. Treat the latest trace as the current source of truth.

---

## 5. Final State

The C128 town-entry crash is closed.

The repo now records both halves of the incident:

- the **first half**: title/boot bank-safety corruption
- the **second half**: low-RAM runtime loader/execution-bank mismatch

That is the correct historical framing for this bug. The original title-corruption report was useful, but incomplete by itself. This version preserves it as the first half of the full postmortem.
