# VDC Performance Optimization Plan (Phase 10.5 — REVISED)

This plan replaces the previous version with technically verified optimizations based on the Phase 10.1 and C3 implementation baseline.

## Revised Root Cause Analysis

-   **I/O Throttling**: The VDC (8563) is the bottleneck. While the CPU runs at 2MHz, the VDC data port ($D601) requires a status-bit poll ($D600) between every write.
-   **Subroutine Overhead**: `jsr vdc_wait` adds 9 cycles (JSR+RTS) per byte. Over a full viewport refresh (1,444 bytes), this is ~13,000 wasted cycles.
-   **Per-Tile Arithmetic**: Calculating map coordinates for every tile (`clc/adc`) is more expensive than the per-row pointer lookups.

## The Corrected Optimizations

### 1. Inlined VDC Wait and Unrolled Streaming
Replace `jsr vdc_wait` and `jsr vdc_write_data` in the row-blasting loop with inlined code.
- **Implementation**: Inline `bit $D600; bpl *-3; sta $D601` inside the loop.
- **Unrolling**: Unroll the 38-iteration character and attribute blasts. This eliminates `iny/cpy/bne` overhead (another 7 cycles per byte).
- **Benefit**: ~23,000 cycles saved per refresh.

### 2. Pre-Translated Tile Tables (Narrow Scope)
Create `tile_vdc_colors` containing RGBI values for standard tiles.
- **Implementation**: Look up these values during the base tile render path.
- **Constraint**: Override paths (monsters, items, player, dimming) will still use the `vic_to_vdc_color` translation table to maintain code modularity.

### 3. Per-Tile Pointer "Sliding" (X-Offset Removal)
Eliminate the `adc` for every tile in the `col_loop`.
- **Implementation**: At the start of each row, set `zp_map_ptr` directly to `view_y_ptr + view_x`. 
- **Effect**: The inner loop becomes a simple `lda (zp_map_ptr),y` where `y` increments from 0 to 37.
- **Benefit**: ~7,000 cycles saved per refresh.

### 4. Per-Row `dy` Early-Exit (Dimming Optimization)
Replace the per-tile Chebyshev distance check with a per-row pre-check.
- **Implementation**: At the start of the row loop, compute `dy = abs(map_y - player_y)`.
- **Early Exit**: If `dy > light_radius`, flag the entire row as "Dimmed Only." This allows skipping monster/item checks and the `dx` distance check for the entire 38-column row.

### 5. Unified Hardware Fill
Utilize VDC Registers 24-30 for `screen_clear`. This is a verified speedup for UI-level operations.

## Success Criteria

- Viewport rendering performance exceeds 15 FPS during movement.
- Zero redundant register selections or subroutine calls in the "Critical Path" (streaming loop).
- Correct lighting/dimming logic maintained near map boundaries.
