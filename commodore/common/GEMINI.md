# GEMINI.md — Common Logic Constraints

This file provides mandates for code shared between the C64 and C128 versions.

## 1. Data Structure Invariants
- **Struct-of-Arrays (SoA):** All entity-level data (Monsters, Items) MUST be stored as SoA. Do not introduce fat C-style object structures. 
- **Consistency:** If you add a monster attribute to `monster.s`, ensure it is added as a parallel array, not inside a record.

## 2. Utility and Library Priority
- **16-bit Math:** Use the `math.s` library for all 16-bit arithmetic (add, sub, mul, div, rolling). Do not inline custom 16-bit carry loops.
- **RNG Usage:** Use the `rng.s` library (32-bit LFSR). Do not use KERNAL RNG or custom unseeded `lda $d012` hacks.
- **String Management:** All new UI or game-world strings MUST be Huffman-encoded via `tools/huff_encoder.py`. Raw `.text` strings are forbidden in resident program code.

## 3. Engineering Quality
- **Naming:** Follow established camelCase and snake_case patterns (e.g., `zp_ptr0`, `mmu_save_p`).
- **Comments:** Provide technical rationale for non-obvious optimizations.
- **Shared Code:** Modifications to `common/` files must be verified on both C64 and C128 if any platform-specific `#if` exists.
