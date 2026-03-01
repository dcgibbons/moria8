# Action Plan C4: Resolve Memory Collision (Dungeon Map vs Program)

**Status:** COMPLETE (2026-02-28)
**Priority:** BLOCKER / CRITICAL
**Owner:** Senior Principal Engineer (C128)

## 1. Executive Summary
The C128 memory map has been successfully optimized. The Dungeon Map, Floor Items, and Creature Scratch areas have been relocated to **Bank 1** at `$4000`. The resident program segment has been moved down to `$0B00` (utilizing recovered RAM), resulting in ~4KB of new headroom in Bank 0 and support for the original 198x66 map size in Bank 1.

## 2. Technical Analysis
- **Current State (Bank 0):**
    - `$0B00–$19FF`: Dungeon Map (80x48 = 3840 bytes)
    - `$1A00–$1AFF`: Floor Items (256 bytes)
    - `$1B00–$1BFF`: Creature Scratch (256 bytes)
    - `$1C01`: Program Entry (BASIC Stub)
- **Problem:** Total data usage ($1100 bytes) + BASIC Stub ($0D bytes) = `$1C0E`. The program entry point is `$1C0E`. There is no margin for error.
- **Solution:** Utilize C128 MMU to store this data in Bank 1 ($128KB mode).

## 3. Implementation Plan

### Phase 1: Infrastructure (MMU Accessors)
We must implement high-performance macros and subroutines for inter-bank memory access. Since the map is accessed in tight loops (LOS, rendering), we cannot afford heavy KERNAL overhead.

- **Tools:** MMU Configuration Register at `$FF00` (writes only) or `$D500` (I/O).
- **Strategy:** Use `zp_ptr0` as the map pointer. Create a specialized `lda_map` / `sta_map` that handles the bank flip.

```assembly
// Example optimized Bank 1 Map Access (Read)
// Input: Y = column, (zp_ptr0) = row base
// Output: A = tile
map_get_tile_banked:
    sei
    lda #MMU_RAM_BANK1  // $7E: Bank 1, RAM, I/O in
    sta $ff00
    lda (zp_ptr0),y     // Read from Bank 1
    pha
    lda #MMU_ALL_RAM    // $3E: Bank 0, RAM, I/O in
    sta $ff00
    pla
    cli
    rts
```

### Phase 2: Relocation
Update `memory128.s` to redefine the addresses. Note that we can keep the *logical* address at `$0B00` in Bank 1, or move it higher to avoid any C128 system mirroring.

- **New Bank 1 Layout:**
    - `$4000–$72EF`: Expanded Dungeon Map (198x66 = 13,068 bytes)
    - `$7300–$73FF`: Floor Items
    - `$7400–$74FF`: Creature Scratch

### Phase 3: Code Updates
1.  **Search & Replace:** Identify all direct accesses to `MAP_BASE` and replace with `map_get_tile` / `map_set_tile` calls.
2.  **Row Tables:** Update `map_row_lo/hi` in `dungeon_data.s` to reflect the new `$4000` base.
3.  **Initial Load:** Update `boot128.s` or the loader to ensure Bank 1 is cleared/initialized before the map generator runs.

## 4. Verification & Testing

### Unit Tests (C128-specific)
We must verify that data persists in Bank 1 and is not accidentally written to Bank 0.

1.  **Bank Continuity Test:**
    - Write value `$AA` to Bank 1 `$4000`.
    - Write value `$BB` to Bank 0 `$4000`.
    - Read Bank 1 `$4000` and assert it is still `$AA`.
2.  **Map Accessor Test:**
    - Call `map_set_tile(10, 10, TILE_FLOOR)`.
    - Manually switch MMU to Bank 1 and verify the byte at `$4000 + (10*MAP_COLS) + 10` is correct.
3.  **Boundary Test:**
    - Verify that writing to the end of the 198x66 map does not corrupt Floor Items at `$7300`.

### Integration Test
- Run `make test` on C128 target (VICE headless).
- Verify `test_dungeon.s` passes with the new banking logic.

## 5. Risks
- **Interrupts:** If an IRQ occurs while the MMU is pointed at Bank 1, and the IRQ handler is in Bank 0 (which it is), the CPU will crash unless we either wrap access in `SEI/CLI` or mirror the IRQ handler in Bank 1.
    - *Decision:* Use `SEI/CLI` for now as it's safer and the map access is bursty, not continuous. Performance impact is negligible at 2MHz (C128).
- **VDC Mirroring:** Ensure Bank 1 usage does not conflict with VDC shared memory if 80-column attributes are eventually mapped to system RAM. (Currently VDC uses private 64KB, so no conflict).

## 6. Next Steps
1.  Define `MMU_RAM_BANK1` in `memory128.s`.
2.  Relocate constants in `memory128.s`.
3.  Implement `map_get_tile` / `map_set_tile` wrappers in `dungeon_data.s` (platform-conditional).
4.  Run verification suite.
