# DESIGN_PLAN.md — Staff Engineer Review of REVIEW_REPORT.md

## 1. Assessment of the Review Report's Claims
The `REVIEW_REPORT.md` identifies a critical crash (`BREAK at E2A8E`) caused by the following block in `commodore/c128/main.s`:

```assembly
    // --- Hardened Vector Invariance (Bank 1) ---
    // Even if Top Common is momentarily OFF, Bank 1 must have valid vectors.
    lda #MMU_RAM_BANK1
    sta $ff00             // Execution Bank swapped from Bank 0 to Bank 1!
    lda #<mmu_common_irq  // CPU fetches from Bank 1 (uninitialized, reads $00 = BRK)
    ...
```

**Skepticism & Critical Analysis:**
I have verified the assembly in `commodore/c128/main.s` (lines 816-831) and the C128 hardware behavior. The report's diagnosis is completely accurate. On the C128, a direct write to the MMU register `$FF00` immediately changes the underlying memory map for the current CPU cycle. If the Program Counter (PC) is located in a memory region that is NOT shared between Bank 0 and Bank 1 (i.e. outside of Common RAM), the CPU will fetch its next instruction from the newly paged-in bank. Because Bank 1 contains uninitialized memory ($00) at this address, the CPU hits a `BRK` and crashes.

The logic in `main.s` assumes the CPU can execute a `sta $ff00` to manipulate another bank's vectors while running in standard program space. **This is indeed a fallacy.** You cannot page out the code you are currently executing.

## 2. Evaluation of Proposed Solutions
The report presents three options:

*   **Option A (Delete the Block - Highly Recommended):** The report correctly notes that if the Top Common RAM invariant (`$D506 = $0D` or `$07`) is maintained, vectors are shared. Therefore, writing these vectors to Bank 0's top RAM (when Top Common is ON) automatically populates them for Bank 1 execution context. Top Common RAM literally acts as a window to the underlying Bank 0 RAM for those addresses.
*   **Option B (The Common RAM Trampoline):** Valid, but over-engineered for this purpose. We shouldn't need a trampoline to do setup if we don't even need the data written to a hidden bank.
*   **Option C (LDIR/indsta into Bank 1):** Also valid, but again, unnecessary if Top Common RAM shares the hardware vectors. Furthermore, using `LDIR` requires more setup overhead and introduces complexity where none is required.

## 3. Plan of Action
**Option A** is structurally the soundest path and adheres to the `Simplicity First` mandate in `GEMINI.md`.

We must also confirm the behavior of the mirroring code just above the offending block:
```assembly
    // Mirror KERNAL vectors/stubs into RAM underneath ROM ($FF05-$FFFF)
    // Skipping $FF00-$FF04 to avoid mid-loop MMU bank-switching.
    ldx #5
!mirror:
    lda $ff00,x
    sta $ff00,x
    inx
    bne !mirror-
```
This loop safely reads from ROM and writes to underlying RAM because the C128 MMU (with KERNAL ROM banked in) redirects reads to ROM and writes to underlying RAM automatically for `$FF05-$FFFF`. Once the ROM is swapped out (All-RAM mode), these RAM values persist. If Top Common RAM is enabled for Bank 1 (as it is with `$D506=$0D`), the CPU will see these values.

### Steps:
1.  **Remove the Vulnerable Block:** Delete lines 814-831 in `commodore/c128/main.s` ("Hardened Vector Invariance (Bank 1)").
2.  **Verify the Top Common RAM Invariant:** Ensure the rest of `main.s` enforces Top Common RAM being active when we are in Bank 1 All-RAM mode, ensuring the vectors are visible.
3.  **Run Test Suite:** Re-run `make test128` to ensure the smoke tests and unit tests pass with the block removed.
