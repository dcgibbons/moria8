# VDC Performance Optimization Plan (C128)

I have analyzed the current C128 source tree, specifically `dungeon_render_vdc.s`, `screen_vdc.s`, and the `mmu_safe_map_read_ptr0` macro overhead. While some optimizations from the previous plan have been implemented (like early-exit dimming and pre-translated VDC colors), the core rendering loops still have significant bottlenecks.

## Proposed Changes

### 1. Inline MMU Bank Switching in the Inner Loop
Currently, `render_viewport` calls `MapRead_ptr0_y()` (which calls `mmu_safe_map_read_ptr0`) for every single tile in the `!col_loop`. 
- `mmu_safe_map_read_ptr0` is a subroutine that calls `mmu_select_bank1` and `mmu_select_bank0`, resulting in **70 cycles** of overhead per tile (saving/restoring flags, multiple JSRs, etc.).
- Over an 38x19 viewport (722 tiles), this is ~50,540 cycles spent just switching banks.
- **Solution**: Replace the `MapRead_ptr0_y()` call in the inner `!col_loop` with a tight, inline MMU switch:
  ```assembly
  sei
  lda #MMU_RAM_BANK1
  sta MMU_CR
  lda (zp_map_ptr),y
  pha
  lda #MMU_ALL_RAM
  sta MMU_CR
  cli
  pla
  sta zp_tile_tmp
  ```
- **Estimated Savings**: ~30,000 cycles per frame limit.

### 2. Fully Unroll the VDC Stream Loops
The previous plan called for fully unrolling the 38-iteration character and attribute blasts. The current code uses a shared loop target (`bit / bpl / lda / sta / iny / cpy / bne`), which successfully eliminates the `jsr vdc_wait` overhead, but still spends 21 cycles per byte.
- **Solution**: Use KickAssembler `.for` macros to fully unroll the 38 `lda / bit / bpl *-3 / sta` blocks for both the character stream and attribute stream.
- **Estimated Savings**: Eliminates `iny/cpy/bne` (7 cycles * 38 bytes * 2 passes * 19 rows) ≈ 10,108 cycles per frame.

### 3. Avoid ZP Pointer Reloading per Column
`render_viewport` reloads `zp_ptr0` with `rv_row_ptr_lo/hi` for *every* column because `monster_find_at` and `floor_item_find_at` clobber it.
- **Solution**: Dedicate a new zero-page pointer (e.g., `zp_view_ptr` or configure `zp_ptr2` to be safe from clobbering) specifically for the map read in this loop. Load it once at the start of the `!row_loop`.
- **Estimated Savings**: 15 cycles * 722 tiles ≈ 10,830 cycles per frame.

## Verification Plan

### Automated Tests
Run `make test` to ensure that no regression occurs in pathfinding, FOV, bounding box clipping, or other systems.

### Manual Verification
1. Run `make run` to launch the game in the VICE emulator.
2. Observe the rendering speed while moving around the dungeon.
3. Validate that tiles, monsters, and items continue to render properly with correct PETSCII characters and colors.
