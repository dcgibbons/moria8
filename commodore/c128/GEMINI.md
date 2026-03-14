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

## 3. Implementation and Verification
- **No Defensive Traps:** Remove `c128_diag_fail_stage_XX` once a root cause is confirmed. Do not add more labels to debug a crash; instead, fix the atomicity and context-switching logic.
- **Test Suit Verification:** A C128 fix is only complete when `boot_diag_copy` and `boot_tier_transition_smoke` pass. Failure of these is a regression.
- **VDC Re-assertion:** Always use `c128_vdc_reassert_mode` on KERNAL exit paths to ensure the 80-column display remains in its expected state.
