# Code Health & Bug Audit: Moria8 C64/C128

**Date:** March 22, 2026  
**Auditor:** Senior Quality Engineer  
**Status:** Operational with Critical Gameplay & Performance Issues

---

## 1. Executive Summary
The Moria8 codebase is a robust and sophisticated 6502 assembly project with a clear separation between common game logic and platform-specific drivers for C64 and C128. However, several critical bugs and performance bottlenecks were identified during this audit that affect gameplay balance, random number quality, and system performance on the C128.

---

## 2. Critical Bugs & Quality Issues

### 2.1 Combat BTH Overflow (Shared Logic)
**Location:** `commodore/common/combat.s:230-250` (`combat_calc_tohit_common`)  
**Issue:** The 16-bit logic for `PL_TOHIT * 3` is implemented using 8-bit arithmetic without proper overflow handling.
**Impact:** If a player's `TOHIT` bonus is large (e.g., > 85), the calculation wraps around. For example, a `TOHIT` of 100 results in an added bonus of 44 instead of 300 (capped at 255). Conversely, very large negative penalties also wrap, potentially making weak characters hit much more often than intended.
**Recommendation:** Implement 16-bit addition or explicit carry checks before clearing the carry for the next addition.

### 2.2 RNG Correlation / 1-Bit LFSR (Shared Utility)
**Location:** `commodore/common/rng.s:55` (`rng_next`)  
**Issue:** The 32-bit Galois LFSR only advances by **one bit** per `rng_next` call.  
**Impact:** Sequential calls to `rng_next` return bytes that are 87.5% correlated (bit-shifted versions of each other). This leads to extremely poor 16-bit distributions in `rng_range_word` and visible patterns in dungeon generation and combat rolls.
**Recommendation:** Loop the LFSR shift 8 times inside `rng_next` to produce a fresh, uncorrelated byte per call.

### 2.3 C128 IRQ Disabling via KERNAL Wrappers (Platform C128)
**Location:** `commodore/c128/main.s:450+` (`w_readst`, `w_open`, etc.)  
**Issue:** The KERNAL wrappers use `php` to capture the processor status **after** `EnterKernal` has already executed `sei`.  
**Impact:** `ExitKernal` always restores the status with the Interrupt flag set. This means **every KERNAL call permanently disables IRQs** until the next explicit `cli` (which is rare in the main loop). This breaks KERNAL features like the STOP-key check and prevents any background IRQ tasks from running.
**Recommendation:** Move `php` to the very top of the wrapper, before `EnterKernal`.

### 2.4 C128 Bulk Map Performance (Platform C128)
**Location:** `commodore/common/dungeon_gen.s:27` (`map_bulk_fill_all`)  
**Issue:** Despite being labeled as "bulk," these routines use the single-tile `:MapWrite_ptr0_y()` macro.  
**Impact:** On C128, every single byte write triggers two bank switches (Bank 0 -> Bank 1 -> Bank 0). A full map fill performs over 26,000 bank switches. This is orders of magnitude slower than a single `jsr map_bulk_enter` followed by direct `sta (zp),y` writes.
**Recommendation:** Refactor `map_bulk_fill_all` and `map_bulk_and_all` to use platform-specific bulk enter/exit hooks.

---

## 3. 6502 Assembly Health

### 3.1 Redundant Comparisons
**Pattern:** `jsr some_func / cmp #0 / bne ...`  
**Finding:** Pervasive redundant `cmp #0` calls throughout the codebase. Since `lda`, `ldx`, `ldy`, `inx`, `dex`, and most math operations already set the Zero flag, these are unnecessary and consume both space and cycles.

### 3.2 8502 2MHz Silicon Bug
**Finding:** The project is aware of the 2MHz RMW bug (as seen in `huffman.s`). While other RMW instructions (`inc zp_ptr0`) exist, they are safe because the project keeps the VIC-II blanked on C128, preventing the DMA cycle-stealing that triggers the corruption.

---

## 4. Platform-Specific Observations

### 4.1 Commodore 64
*   **Memory Margin:** EXTREMELY TIGHT. `program_end` ($BFF0) is only 16 bytes away from `MAP_BASE` ($C000). Any significant code addition will require further Huffman compression or moving logic to overlays.
*   **Safety:** Banking and IRQ handling are correct and robust. `input_get_key` correctly preserves the I-flag state.

### 4.2 Commodore 128
*   **Memory Margin:** Good in Bank 0, but Bank 1 is tightly packed.
*   **Innovation:** Excellent use of Common RAM ($0C00) for bank-switching bridges and hardware vectors.
*   **Inconsistency:** `screen_put_char` translates PETSCII, but `screen_put_string` expects pre-translated screen codes. This is managed by the assembler encoding but remains a potential trap for runtime-generated strings.

---

## 5. Coverage Analysis
*   **Unit Tests:** Extensive Python-driven unit tests for C128.
*   **Smoke Tests:** Good coverage for boot, title, and transitions.
*   **Gap:** Melee combat formulas and high-range `TOHIT` bonuses lack automated edge-case verification, which allowed the overflow bug to remain undetected.

---

## 6. Recommendations for Next Steps
1.  **Fix `combat_calc_tohit` overflow** to restore gameplay balance.
2.  **Upgrade RNG to 8-step** to improve procedural generation quality.
3.  **Repair C128 KERNAL wrappers** to stop accidental IRQ disabling.
4.  **Implement true Bulk Map paths** for C128 to speed up generation.
5.  **Audit C64 memory usage** to find at least 256 bytes of emergency headroom.
