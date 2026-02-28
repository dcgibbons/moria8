# VDC Performance Optimization Plan (Phase 10.5)

The C128 VDC (8563) bottleneck is I/O protocol overhead, not CPU speed. This plan outlines five "Force Multiplier" optimizations to achieve high-frame-rate rendering on the 80-column display.

## Current State Analysis

-   **I/O Throttling**: The VDC register port ($D600/$D601) is hardware-throttled to 1MHz, regardless of the 8502's 2MHz mode.
-   **Register Overhead**: Every `vdc_write_data` call currently performs a status poll + register select + status poll + data write. This is a massive tax during character streaming.

## The "Force Multiplier" Optimizations

### 1. Select-Once-Blast-Row (Streaming)
Stop re-selecting VDC Register 31 (Data Port) for every character.
- **Implementation**: In `render_viewport`, select Register 31 **once** before the column loop. Within the loop, perform only a `vdc_wait` and a raw `sta VDC_DATA_REG`.
- **Target**: ~70% reduction in per-character VDC I/O overhead.

### 2. Double-Buffered Row Blasting
Separate game logic (map lookups, monster detection, light radius) from VDC I/O.
- **Implementation**: Use 2MHz mode to fill two 38-byte ZP buffers (`row_char_buf` and `row_attr_buf`) with translated screen codes and RGBI colors for an entire row.
- **Execution**: Once buffered, switch back to 1MHz (as needed for I/O) and blast the buffer to the VDC data port using an unrolled loop.

### 3. Pre-Translated VDC Tile Tables
Remove runtime color translation.
- **Implementation**: Create a `tile_vdc_colors` table during data initialization (or at compile-time) that stores the pre-translated VDC RGBI values.
- **Target**: Saves 2 instructions (`ldx/lda`) per tile.

### 4. Zero-Page Pointer "Sliding"
Avoid repeated 16-bit row address lookups in the inner loop.
- **Implementation**: Initialize `zp_map_ptr` to the start of the viewport's top row. Advance it by `MAP_WIDTH` (198) at the end of each row.
- **Target**: Replace table lookups with simple 16-bit addition, saving cycles during the logic pass.

### 5. Static Distance Map (Chebyshev Optimization)
Optimize the "dimming" calculation for unlit tiles.
- **Implementation**: Since the player is always at the center of the 38x19 viewport, the distance from each viewport coordinate (X:0-37, Y:0-18) to the player is static. Pre-calculate a 38x19 distance map.
- **Target**: Replace 2 `abs()` and 1 `max()` with a single `lda (ptr),y`.

## Implementation Roadmap

1.  **Phase 10.5.1**: Implement Optimization #1 (Streaming) in `render_viewport` and `render_single_tile`.
2.  **Phase 10.5.2**: Update `tile_data` to include pre-translated VDC colors.
3.  **Phase 10.5.3**: Refactor `render_viewport` to use double-buffering and unrolled blasting.
4.  **Phase 10.5.4**: Integrate the pre-calculated distance map for dimming.

## Success Criteria

- Viewport rendering speed increases by 300% or more.
- Smooth scrolling even with multiple active monsters visible.
- Full screen refresh is visually instantaneous to the user.
