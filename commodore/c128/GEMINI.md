# GEMINI.md — C128 Hardware Invariants

This file provides tactical mandates for C128-specific development. These instructions take precedence over general project rules.

## 1. Banking and MMU Taboos (Absolute Precedence)
- **The Banking Taboo:** NEVER modify `$FF00` (MMU) or `$01` (Processor Port) without an immediate preceding `sei` and a following `cli` (or context-aware restore). 
- **The Context Rule:** No "simple" loads or bulk reads are exempt from atomic banking. Use the established `EnterKernal` and `ExitKernal` macros for all KERNAL entry/exit.
- **The MMU Invariant:** `$D506` (Common RAM Register) is a static system constant. It MUST be `$07` (4KB Bottom/Top Common). Any plan suggesting a change to this value to fix a crash is fundamentally flawed and must be rejected.
- **Hardware Vector Integrity:** Hardware vectors at `$FFFA-$FFFF` MUST point to code that resides in Common RAM or a validated Vector Bridge. If Top Common is shared ($D506 bit 1), the CPU will see the same vectors across all banks.

## 2. Memory Ownership and Layout
- **Bank 1 Contract:** Adhere to the `Bank 1 runtime ownership after boot` map in `memory128.s`. Do not use "unassigned" RAM without an explicit ownership update and compile-time `.assert`.
- **Top/Bottom Common:** Bottom Common RAM ($0000-$0FFF) contains the Stack and Zero Page. Top Common RAM ($FC00-$FFFF) contains the Vectors. Both must remain enabled for system stability.
- **Overlay Slots:** Use the fixed slots defined in `ARCHITECTURE.md` (e.g., OVL_STARTUP at $A000, OVL_TOWN at $B000).
- **Low-RAM Reality:** `$1000-$3FFF` is **Bank-private**, not common RAM. Any direct call into that range must prove the code is loaded into the same bank the CPU is executing.
- **I/O Hole Reality:** `$D000-$DFFF` is not “high RAM you can borrow later.” With I/O visible, execution there reads device space and returns garbage.

### 2a. Segment Boundary Law (ABSOLUTE — NEVER VIOLATE)
The C128 memory map has hard physical boundaries that the assembler cannot enforce automatically. Violating them causes silent corruption, CPU JAMs in data tables, and I/O hole reads that return register garbage instead of code.

- **Main (Default) segment: $1C0E – must end BELOW $C000.** MAP_BASE lives at $C000. Anything past it overwrites the dungeon map or falls into the I/O hole ($D000–$DFFF).
- **Banked payload (`.pseudopc $E80E`): must end below $FFFA** (CPU vectors).
- **Overlay segments: must each fit in $E000–$EFFF** (4 KB window).
- **`first_banked_function` must be >= $F000** so it doesn't overlap the overlay window.

**When moving `#import` statements between the main segment and the `.pseudopc` block (or overlays):**
1. Rebuild and check the Memory Map in build output — confirm Default segment ends below $C000.
2. Check `.print` lines for banked payload and overlay sizes.
3. **NEVER delete `.assert` statements that check boundaries** (e.g., `first_banked_function >= $F000`, `program_end < $C000`). If an assert fails, your change broke the layout. Fix the change, not the assert.

### 2b. Runtime-Loaded / Copied Code Checklist (MANDATORY)
Before changing any C128 runtime-loaded or banked code path, verify all five:
1. **symbol address** — where the routine links
2. **PRG header** — where the file loads
3. **load bank** — where the loader writes it
4. **execution bank** — which bank is visible at the callsite
5. **source-span safety** — whether any staged source used for recopies survives overlays/boot scrub

Failure to check all five caused three separate regressions in this repo:
- post-chargen town-entry `JSR $1000` into unloaded/wrong-bank code
- help/inventory blank-screen hangs from recopying a payload source clobbered by overlays
- dungeon descent `JAM` from a trampoline calling ego-item code that had drifted into `$D000-$DFFF`

Also: asserting the trampoline address is not sufficient. Assert the callee placement too.
The callable residency inventory for those checks now lives in `commodore/c128/io_contracts.s`; update that manifest when a C128 callable surface moves.

## 3. Implementation and Verification
- **No Defensive Traps:** Remove `c128_diag_fail_stage_XX` once a root cause is confirmed. Do not add more labels to debug a crash; instead, fix the atomicity and context-switching logic.
- **Test Suit Verification:** A C128 fix is only complete when `boot_diag_copy` and `boot_tier_transition_smoke` pass. Failure of these is a regression.
- **VDC Re-assertion:** Always use `c128_vdc_reassert_mode` on KERNAL exit paths to ensure the 80-column display remains in its expected state.
- **Trace Discipline:** If monitor traces move, treat the newest PC/backtrace as the active truth. Re-evaluate the load/bank/ownership contract before patching another nearby function.

### C128 Test Workflow
- For fast unit-level iteration, prefer `make test128-fast`.
- For fast runtime regression checks, prefer `make test128-fast-smoke`.
- `make test128` remains the authoritative full C128 suite and must be used before closing high-risk MMU/layout/overlay work.
- If a user reports `make test128-fast` or `make test128` failing, that exact make target is the active gate until it passes.
- Direct `harness128.py` runs, monitor traces, and narrower smokes are diagnostic only in that situation. They cannot be used as closure or as explanation for the failure until the reported make target is green.
- Before trusting the rerun of a reported C128 gate after runtime/layout work, force a fresh build of the named target and avoid stale VICE state.
