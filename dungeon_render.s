// dungeon_render.s — Viewport rendering
//
// Reads the map at $C000 and draws a 38x20 viewport to screen RAM.
// The viewport is centered on the player position, clamped to map edges.
// Screen layout: viewport at rows 1-20, columns 1-38.

// ============================================================
// Subroutines
// ============================================================

// viewport_update — Center viewport on player, clamp to map edges
// Updates zp_view_x, zp_view_y
// Preserves: nothing
viewport_update:
    // view_x = player_x - VIEWPORT_W/2, clamped to [0, MAP_COLS - VIEWPORT_W]
    lda zp_player_x
    sec
    sbc #VIEWPORT_W / 2     // 19
    bcs !vx_not_neg+
    lda #0                  // Underflow, clamp to 0
    jmp !vx_store+
!vx_not_neg:
    cmp #MAP_COLS - VIEWPORT_W  // 42
    bcc !vx_store+
    lda #MAP_COLS - VIEWPORT_W
!vx_store:
    sta zp_view_x

    // view_y = player_y - VIEWPORT_H/2, clamped to [0, MAP_ROWS - VIEWPORT_H]
    lda zp_player_y
    sec
    sbc #VIEWPORT_H / 2     // 10
    bcs !vy_not_neg+
    lda #0
    jmp !vy_store+
!vy_not_neg:
    cmp #MAP_ROWS - VIEWPORT_H  // 28
    bcc !vy_store+
    lda #MAP_ROWS - VIEWPORT_H
!vy_store:
    sta zp_view_y
    rts

// render_viewport — Draw the 38x20 viewport to screen
// Reads map data and writes screen codes + colors.
// Preserves: nothing
render_viewport:
    lda #0
    sta zp_render_y         // Screen row counter (0-19)

!row_loop:
    // Compute map row = view_y + render_y
    lda zp_view_y
    clc
    adc zp_render_y
    tax                     // X = map row

    // Get map row address
    lda map_row_lo,x
    sta zp_map_ptr_lo
    lda map_row_hi,x
    sta zp_map_ptr_hi

    // Get screen row address (render_y + 1 for viewport offset)
    lda zp_render_y
    clc
    adc #VIEWPORT_Y         // +1
    tax
    lda screen_row_lo,x
    sta zp_screen_lo
    lda screen_row_hi,x
    sta zp_screen_hi
    lda color_row_lo,x
    sta zp_color_lo
    lda color_row_hi,x
    sta zp_color_hi

    // Inner loop: 38 columns
    lda #0
    sta zp_render_x         // Screen column counter (0-37)

!col_loop:
    // Compute map column = view_x + render_x
    lda zp_view_x
    clc
    adc zp_render_x
    tay                     // Y = map column offset

    // Read map byte
    lda (zp_map_ptr_lo),y
    sta zp_tile_tmp

    // Check if visited (bit 2)
    and #FLAG_VISITED
    beq !draw_blank+

    // Extract tile type (bits 7-4 → index 0-15)
    lda zp_tile_tmp
    lsr
    lsr
    lsr
    lsr
    tax                     // X = tile type index

    // Look up screen code and color
    lda tile_screen_codes,x
    sta zp_temp0            // screen code
    lda tile_colors,x
    sta zp_temp1            // color

    // Check if this is the player position
    lda zp_render_x
    clc
    adc zp_view_x
    cmp zp_player_x
    bne !not_player+
    lda zp_render_y
    clc
    adc zp_view_y
    cmp zp_player_y
    bne !not_player+

    // Override with player character
    lda #SC_PLAYER          // '@'
    sta zp_temp0
    lda #COL_PLAYER
    sta zp_temp1
    jmp !write_tile+

!not_player:
    // Skip store door check in dungeon levels (saves ~100 cycles/tile)
    lda zp_player_dlvl
    bne !write_tile+

    // Check if this is a store door (show store number) — town only
    jsr check_store_door
    bcc !write_tile+        // Not a store door

    // A = store number (1-6), convert to screen code ($31-$36)
    clc
    adc #$30
    sta zp_temp0
    lda #COL_STORE
    sta zp_temp1
    jmp !write_tile+

!draw_blank:
    lda #SC_SPACE
    sta zp_temp0
    lda #COL_BLACK
    sta zp_temp1

!write_tile:
    // Screen column = render_x + VIEWPORT_X (1)
    ldy zp_render_x
    iny                     // +1 for viewport offset

    // Write screen code
    lda zp_temp0
    sta (zp_screen_lo),y
    // Write color
    lda zp_temp1
    sta (zp_color_lo),y

    // Next column
    inc zp_render_x
    lda zp_render_x
    cmp #VIEWPORT_W
    bne !col_loop-

    // Next row
    inc zp_render_y
    lda zp_render_y
    cmp #VIEWPORT_H
    beq !done+
    jmp !row_loop-
!done:
    rts

// check_store_door — Check if current map position is a store door
// Input: map position from zp_view_x + zp_render_x, zp_view_y + zp_render_y
// Output: carry set if store door, A = store number (1-6)
//         carry clear if not a store door
// Preserves: zp_temp0, zp_temp1
check_store_door:
    // Compute map x
    lda zp_render_x
    clc
    adc zp_view_x
    sta zp_temp2            // map x

    // Compute map y
    lda zp_render_y
    clc
    adc zp_view_y
    sta zp_temp3            // map y

    ldx #0                  // Store index
!check_loop:
    lda store_door_x,x
    cmp zp_temp2
    bne !next+
    lda store_door_y,x
    cmp zp_temp3
    bne !next+

    // Match! Return store number (1-based)
    txa
    clc
    adc #1
    sec                     // Set carry = found
    rts

!next:
    inx
    cpx #STORE_COUNT
    bne !check_loop-

    clc                     // Clear carry = not found
    rts

// render_single_tile — Render one tile at map coordinates
// Used by dirty rendering to update only changed tiles.
// Input: zp_temp0 = map_x, zp_temp1 = map_y
// Preserves: zp_temp0, zp_temp1
render_single_tile:
    // Compute screen row
    lda zp_temp1
    sec
    sbc zp_view_y
    clc
    adc #VIEWPORT_Y
    tax
    lda screen_row_lo,x
    sta zp_screen_lo
    lda screen_row_hi,x
    sta zp_screen_hi
    lda color_row_lo,x
    sta zp_color_lo
    lda color_row_hi,x
    sta zp_color_hi

    // Compute and save screen column offset
    lda zp_temp0
    sec
    sbc zp_view_x
    clc
    adc #VIEWPORT_X
    sta rst_col_tmp

    // Read map byte at (map_x, map_y)
    ldx zp_temp1
    lda map_row_lo,x
    sta zp_map_ptr_lo
    lda map_row_hi,x
    sta zp_map_ptr_hi
    ldy zp_temp0
    lda (zp_map_ptr_lo),y
    sta zp_tile_tmp

    // Check visited flag
    and #FLAG_VISITED
    beq !rst_blank+

    // Extract tile type (bits 7-4)
    lda zp_tile_tmp
    lsr
    lsr
    lsr
    lsr
    tax
    lda tile_screen_codes,x
    sta zp_temp3
    lda tile_colors,x
    sta zp_temp4

    // Player position override?
    lda zp_temp0
    cmp zp_player_x
    bne !rst_store+
    lda zp_temp1
    cmp zp_player_y
    bne !rst_store+
    lda #SC_PLAYER
    sta zp_temp3
    lda #COL_PLAYER
    sta zp_temp4
    jmp !rst_write+

!rst_store:
    // Skip store door check in dungeon levels
    lda zp_player_dlvl
    bne !rst_write+

    // Check store doors (inline — check_store_door clobbers zp_temp2/3)
    ldx #0
!rst_store_loop:
    lda store_door_x,x
    cmp zp_temp0
    bne !rst_next_store+
    lda store_door_y,x
    cmp zp_temp1
    bne !rst_next_store+
    // Store door match
    txa
    clc
    adc #$31                // '1'-'6' screen code
    sta zp_temp3
    lda #COL_STORE
    sta zp_temp4
    jmp !rst_write+
!rst_next_store:
    inx
    cpx #STORE_COUNT
    bne !rst_store_loop-
    jmp !rst_write+

!rst_blank:
    lda #SC_SPACE
    sta zp_temp3
    lda #COL_BLACK
    sta zp_temp4

!rst_write:
    ldy rst_col_tmp
    lda zp_temp3
    sta (zp_screen_lo),y
    lda zp_temp4
    sta (zp_color_lo),y
    rts

rst_col_tmp: .byte 0

// Saved positions for dirty render detection
old_view_x:    .byte 0
old_view_y:    .byte 0
old_player_x:  .byte 0
old_player_y:  .byte 0

// ============================================================
// Compile-time validation
// ============================================================
.assert "Viewport width", VIEWPORT_W, 38
.assert "Viewport height", VIEWPORT_H, 20
