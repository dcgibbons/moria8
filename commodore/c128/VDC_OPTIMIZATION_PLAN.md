# VDC Performance Optimization Plan (C128)

I have analyzed the current C128 source tree, specifically `dungeon_render_vdc.s`, `screen_vdc.s`, and the `mmu_safe_map_read_ptr0` macro overhead. The core rendering loops still have significant bottlenecks. The following plan details architectural shifts required to achieve playable frame rates on the 8-bit C128.

## Proposed Architectural Changes

### 1. Bank 1 -> Bank 0 Line Buffer Copy (Per-Row Bank Switching)
Currently, `render_viewport` performs an MMU bank switch for *every single tile* (722 times per frame), which destroys interrupt latency and wastes cycles.
- **Solution**: Never bank-switch per byte. Use **Common RAM** (shared memory visible in both Bank 0 and Bank 1, e.g., `$0000-$03FF` or a dedicated 1K block at the top of memory). Create a small routine in common RAM that:
  1. Disables interrupts (`sei`).
  2. Switches to Bank 1.
  3. Copies an entire 38-tile row into a contiguous "Line Buffer" in Bank 0.
  4. Switches back to Bank 0 and re-enables interrupts (`cli`).
- **Estimated Savings**: Drops bank switches from 722 per frame to **19 per frame**, saving ~40,000+ cycles and dramatically improving system interrupt stability.

### 2. Implement Painter's Algorithm for Entities (Decouple Map vs. Entities)
Currently, the engine checks "Is there a monster here? Is there an item here?" for all 722 viewport tiles ($O(W \times H)$ complexity) leading to excessive `zp_ptr` clobbering and lookup overhead.
- **Solution**: Decouple map rendering from entity rendering.
  1. **Base Render**: Render the base dungeon tiles for the viewport using the fast line buffer approach.
  2. **Entity Overlay**: Implement a secondary pass that iterates *only* over the active monster and item lists ($O(N)$ where $N$ is the number of active entities in the level).
  3. For each active entity, perform a quick bounds check against the current viewport coordinates. If it's on-screen, calculate its VDC offset and dynamically overwrite that single character/color in the VDC memory.
- **Estimated Savings**: Iterating over 15-20 active entities avoids 722 function calls to a lookup routine. This change alone will likely double rendering speed.

### 3. Fully Unroll the VDC Stream Loops (with Conditional Polling)
The current stream loops use a shared target (`bit / bpl / lda / sta / iny / cpy / bne`), costing ~21 cycles per byte.
- **Solution**: Use KickAssembler `.for` macros to fully unroll the 38 `lda / sta` blocks for both the character stream and attribute stream, sourcing from the new Line Buffer.
- **Refinement**: Structure the unrolled macro so that VDC readiness polling (`bit VDC_STATUS / bpl *-3`) is conditionally compiled. 
  - Profile the code in both `SLOW` (1MHz) and `FAST` (2MHz) CPU modes. In 1MHz mode, the CPU is often slower than the VDC, so the `bit/bpl` check can safely be omitted to save cycles. In 2MHz mode, the polling might be strictly mandatory to prevent VDC overrun.
- **Estimated Savings**: Eliminates `iny/cpy/bne` looping overhead entirely (saving ~10,000 cycles), plus potential savings from dropping unnecessary VDC status polling in 1MHz mode.

## Verification Plan

### Automated Tests
Run `make test` to ensure that no regression occurs in pathfinding, FOV, bounding box clipping, or other systems. Ensure the new Common RAM routines don't clash with existing Zero Page or stack usage.

### Manual Verification
1. Run `make run` to launch the game in the VICE emulator in both C128 modes (if applicable).
2. Observe the rendering speed while moving around the dungeon with many monsters.
3. Validate that tiles, monsters, and items continue to render properly (Painter's Algorithm correctly overlays entities on the base map) with correct PETSCII characters and colors.
