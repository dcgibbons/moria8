# Review Report: C128 Stability - The Title Corruption Root Cause

## 1. Executive Summary: The "Wandering Crash" Solved

The instability reported as a "Revision Misalignment" or "MMU Failure" is actually a **Memory Corruption Bug** caused by the Title Screen loader.

### A. The Root Cause: Bank 0 Code Overwrite
In `commodore/common/title_screen.s`, the `SETBNK` call required to load the title art into Bank 1 is incorrectly wrapped in `#if C128_REAL_BOOT_DIAG`. In production builds, this guard is **FALSE**, and the `SETBNK` call is deleted.

1. The Title Art is a PRG file with a load address of `$4000`.
2. Without `SETBNK` to override the destination, the KERNAL defaults to **Bank 0**.
3. The KERNAL writes the title art data directly into **Bank 0 RAM at $4000+**.
4. This **overwrites 1-3 KB of the Game Engine code**.
5. When the game subsequently attempts to execute code in the `$4000-$4FFF` range, it executes title art bytes as instructions, leading to wild jumps and the reported `BRK` at random addresses like `$F2B6`.

### B. The `safe_setbnk` Clobbering Bug
Even if the guard were enabled, the wrapper `safe_setbnk` in `main.s` (Line 552) is defective:
```asm
safe_setbnk:
    :EnterKernal()    // Clobbers A with nesting depth (2)
    jsr $ff68         // SETBNK receives A=2, not A=1
```
On a 128KB machine, Bank 2 aliases to Bank 0, so the corruption would occur regardless.

### C. The `init_copy_banked` Latent Bug
The copy loop for the banked payload in `memory128.s` contains a logic error that skips the final page ($FF). This leaves the last ~48 bytes of the UI/character sheet code uninitialized (filled with KERNAL ROM mirror data).

## 2. Definitive Fixes (Mandatory)

### 1. Fix the Title Loader Guards
In `commodore/common/title_screen.s`, change `#if C128_REAL_BOOT_DIAG` to `#if C128`. The `SETBNK` call is required for **all** C128 builds.

### 2. Harden the `safe_setbnk` Wrapper
The `safe_setbnk` routine in `main.s` must preserve registers like all other KERNAL wrappers:
```asm
safe_setbnk:
    pha
    txa
    pha
    :EnterKernal()
    pla
    tax
    pla
    jsr $ff68
    php
    pha
    :ExitKernal()
    pla
    plp
    rts
```

### 3. Adjust the Page-Skip Boundary
In `memory128.s`, the `init_copy_banked` loop must be adjusted to include the `$FF` page. Change the comparison from `cmp #$ff` to `cmp #$00` (wrapping) or adjust the boundary to `$100`.

## 3. Conclusion
The "Revision Misalignment" theory was an incorrect interpretation of the crash address. The crash at `$F2B6` was not a KERNAL error, but the PC landing in corrupted RAM. **Restore the Title Load bank-safety, and the system will stabilize.**
