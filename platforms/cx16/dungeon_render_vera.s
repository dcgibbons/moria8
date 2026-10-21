#importonce
// dungeon_render_vera.s — Commander X16 80-column VERA dungeon viewport renderer
//
// Draws the 78x18 viewport at screen (1,2) from the banked 198x66 map
// (RAM Banks 1-2). Streams character + 16-color attribute pairs per row
// through VERA_DATA0 with auto-increment = 1 (VERA_INC_1).

.const VIEW_SCROLL_MARGIN_X = 12
.const VIEW_SCROLL_MARGIN_Y = 4

.label rv_row_map_buf = CX16_ROW_STAGE_BASE
rv_row_has_glyph: .byte 0

// ============================================================
// viewport_update — Recenter viewport on player with scroll deadband
// ============================================================
viewport_update:
    lda zp_view_x
    clc
    adc #VIEW_SCROLL_MARGIN_X
    cmp zp_player_x
    bcc !vx_check_right+
    beq !vx_check_right+
    lda zp_player_x
    sec
    sbc #VIEW_SCROLL_MARGIN_X
    bcs !vx_store_left+
    lda #0
!vx_store_left:
    sta zp_view_x
    jmp !vy_update+

!vx_check_right:
    lda zp_view_x
    clc
    adc #VIEWPORT_W - 1 - VIEW_SCROLL_MARGIN_X
    cmp zp_player_x
    bcs !vy_update+
    lda zp_player_x
    sec
    sbc #VIEWPORT_W - 1 - VIEW_SCROLL_MARGIN_X
    cmp #MAP_COLS - VIEWPORT_W
    bcc !vx_store_right+
    lda #MAP_COLS - VIEWPORT_W
!vx_store_right:
    sta zp_view_x

!vy_update:
    lda zp_view_y
    clc
    adc #VIEW_SCROLL_MARGIN_Y
    cmp zp_player_y
    bcc !vy_check_bottom+
    beq !vy_check_bottom+
    lda zp_player_y
    sec
    sbc #VIEW_SCROLL_MARGIN_Y
    bcs !vy_store_top+
    lda #0
!vy_store_top:
    sta zp_view_y
    rts

!vy_check_bottom:
    lda zp_view_y
    clc
    adc #VIEWPORT_H - 1 - VIEW_SCROLL_MARGIN_Y
    cmp zp_player_y
    bcs !vy_done+
    lda zp_player_y
    sec
    sbc #VIEWPORT_H - 1 - VIEW_SCROLL_MARGIN_Y
    cmp #MAP_ROWS - VIEWPORT_H
    bcc !vy_store_bottom+
    lda #MAP_ROWS - VIEWPORT_H
!vy_store_bottom:
    sta zp_view_y
!vy_done:
    rts

// ============================================================
// render_viewport — Draw the 78x18 viewport to VERA VRAM
// ============================================================
render_viewport:
    lda zp_player_x
    sec
    sbc zp_view_x
    sta rv_player_vx

    lda #0
    sta zp_render_y

!row_loop:
    lda zp_view_y
    clc
    adc zp_render_y
    sta rv_row_map_y
    tax

    // Pre-compute |dy| = abs(map_y - player_y)
    txa
    sec
    sbc zp_player_y
    bcs !rv_row_dy_pos+
    eor #$ff
    clc
    adc #1
!rv_row_dy_pos:
    sta rv_row_dy

    // Block-read the 78-byte map row slice from Banks 1-2 into fixed low RAM
    lda map_row_lo,x
    clc
    adc zp_view_x
    sta zp_ptr0
    lda map_row_hi,x
    adc #0
    sta zp_ptr0_hi
    lda #<rv_row_map_buf
    sta zp_ptr1
    lda #>rv_row_map_buf
    sta zp_ptr1_hi
    ldy #0
    ldx #VIEWPORT_W
    jsr mmu_safe_map_read_block

    lda glyph_active
    ora glyph_active+1
    ora glyph_active+2
    ora glyph_active+3
    sta rv_row_has_glyph

    // Point VERA DATA0 at (row = VIEWPORT_Y + zp_render_y, col = 0) with INC_1
    stz VERA_CTRL
    stz VERA_ADDR_L
    lda zp_render_y
    clc
    adc #(VERA_TEXT_BASE_MID + VIEWPORT_Y)
    sta VERA_ADDR_M
    lda #(VERA_TEXT_BASE_HIGH | VERA_INC_1)
    sta VERA_ADDR_H

    // Write left border cell (col 0 = blank space)
    lda #SC_SPACE
    sta VERA_DATA0
    lda #COL_BLACK
    sta VERA_DATA0

    // Player-on-this-row flag
    stz rv_player_row
    lda rv_row_map_y
    cmp zp_player_y
    bne !rv_player_row_done+
    inc rv_player_row
!rv_player_row_done:

    stz zp_render_x

!col_loop:
    ldy zp_render_x
    lda rv_row_map_buf,y
    sta zp_tile_tmp

    and #FLAG_VISITED
    bne !rv_visited+

    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq !rv_detect_blank+
    lda #SC_SPACE
    sta zp_temp0
    lda #COL_BLACK
    sta zp_temp1
    jmp !rv_live_monster+
!rv_detect_blank:
    jmp !draw_blank+
!rv_visited:

    lda zp_tile_tmp
    lsr
    lsr
    lsr
    lsr
    tax

    // Wall types 1-6 without FLAG_LIT = corridor rock -> '#'
    cpx #7
    bcs !rv_normal+
    cpx #1
    bcc !rv_normal+
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rv_normal+
    lda #$23
    sta zp_temp0
    lda #COL_LGREY
    sta zp_temp1
    bne !rv_tile_set+
!rv_normal:
    lda tile_screen_codes,x
    sta zp_temp0
    lda tile_colors,x
    sta zp_temp1
!rv_tile_set:

    // Store door number override (town only, open door tiles only)
    lda zp_player_dlvl
    bne !rv_no_store+
    cpx #7
    bne !rv_no_store+
    lda zp_view_x
    clc
    adc zp_render_x
    sta rv_col_tmp
    ldx #0
!rv_store_chk:
    lda store_door_x,x
    cmp rv_col_tmp
    bne !rv_store_nxt+
    lda store_door_y,x
    cmp rv_row_map_y
    bne !rv_store_nxt+
    txa
    clc
    adc #$31
    sta zp_temp0
    lda #COL_STORE
    sta zp_temp1
    bne !rv_no_store+
!rv_store_nxt:
    inx
    cpx #STORE_COUNT
    bne !rv_store_chk-
!rv_no_store:

    // Dimming check: remembered but not currently visible -> dark grey
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rv_vis_ok+

    lda rv_row_dy
    cmp zp_light_radius
    beq !rv_check_dx+
    bcc !rv_check_dx+
    jmp !rv_dimmed+

!rv_check_dx:
    lda zp_view_x
    clc
    adc zp_render_x
    sec
    sbc zp_player_x
    bcs !rv_dx_pos+
    eor #$ff
    clc
    adc #1
!rv_dx_pos:
    cmp rv_row_dy
    bcs !rv_use_dx+
    lda rv_row_dy
!rv_use_dx:
    cmp zp_light_radius
    beq !rv_vis_ok+
    bcc !rv_vis_ok+

!rv_dimmed:
    lda #COL_DGREY
    sta zp_temp1
    jmp !rv_no_glyph+

!rv_vis_ok:
    lda zp_tile_tmp
    and #FLAG_HAS_ITEM
    beq !rv_no_item+
    lda zp_view_x
    clc
    adc zp_render_x
    ldy rv_row_map_y
    jsr floor_item_find_at
    bcc !rv_no_item+
    lda fi_item_id,x
    tax
    jsr item_get_display_char
    sta zp_temp0
    txa
    jsr item_get_floor_color
    sta zp_temp1
!rv_no_item:
    lda rv_row_has_glyph
    beq !rv_no_glyph+
    lda zp_view_x
    clc
    adc zp_render_x
    ldy rv_row_map_y
    jsr glyph_find_at
    bcc !rv_no_glyph+
    lda #SC_GLYPH
    sta zp_temp0
    lda #COL_GLYPH
    sta zp_temp1
!rv_no_glyph:

!rv_live_monster:
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq !rv_no_monster+
    lda zp_view_x
    clc
    adc zp_render_x
    ldy rv_row_map_y
    jsr monster_find_at
    bcc !rv_no_monster+
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #(MF_VISIBLE | MF_DETECTED)
    beq !rv_no_monster+
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda cr_display,x
    sta zp_temp0
    lda cr_color,x
    sta zp_temp1

!rv_no_monster:
rv_apply_player_override:
    lda rv_player_row
    beq !write_tile+
    lda zp_render_x
    cmp rv_player_vx
    bne !write_tile+
    lda #SC_PLAYER
    sta zp_temp0
    lda #COL_PLAYER
    sta zp_temp1
    jmp !write_tile+

!draw_blank:
    lda #SC_SPACE
    sta zp_temp0
    lda #COL_BLACK
    sta zp_temp1
    jmp rv_apply_player_override

!write_tile:
    lda zp_temp0
    sta VERA_DATA0
    lda zp_temp1
    and #$0f
    sta VERA_DATA0

    inc zp_render_x
    lda zp_render_x
    cmp #VIEWPORT_W
    beq !col_done+
    jmp !col_loop-
!col_done:
    // Write right border cell (col 79 = blank space)
    lda #SC_SPACE
    sta VERA_DATA0
    lda #COL_BLACK
    sta VERA_DATA0

    inc zp_render_y
    lda zp_render_y
    cmp #VIEWPORT_H
    beq !done+
    jmp !row_loop-
!done:
    lda #0
    sta vis_room_revealed
    rts

// ============================================================
// scene_render_mat_tile / render_single_tile
// Input: zp_temp0 = map_x, zp_temp1 = map_y
// Preserves: zp_temp0, zp_temp1, zp_ptr0
// ============================================================
!rst_clip_out:
    rts
scene_render_mat_tile:
    inc mat_scene_dirty
render_single_tile:
    lda zp_temp1
    sec
    sbc zp_view_y
    cmp #VIEWPORT_H
    bcs !rst_clip_out-
    clc
    adc #VIEWPORT_Y
    sta rst_row_tmp

    lda zp_temp0
    sec
    sbc zp_view_x
    cmp #VIEWPORT_W
    bcs !rst_clip_out-
    clc
    adc #VIEWPORT_X
    sta rst_col_tmp

    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha

    ldx zp_temp1
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_temp0
    jsr mmu_safe_map_read_ptr0
    sta zp_tile_tmp

    and #FLAG_VISITED
    bne !rst_visited+
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    bne !rst_detect_occ+
    jmp !rst_blank+
!rst_detect_occ:
    lda #SC_SPACE
    sta zp_temp3
    lda #COL_BLACK
    sta rst_color_tmp
    jmp !rst_monster+
!rst_visited:

    lda zp_tile_tmp
    lsr
    lsr
    lsr
    lsr
    tax

    cpx #7
    bcs !rst_normal+
    cpx #1
    bcc !rst_normal+
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rst_normal+
    lda #$23
    sta zp_temp3
    lda #COL_LGREY
    sta rst_color_tmp
    bne !rst_tile_set+
!rst_normal:
    lda tile_screen_codes,x
    sta zp_temp3
    lda tile_colors,x
    sta rst_color_tmp
!rst_tile_set:

    lda zp_player_dlvl
    bne !rst_no_store+
    cpx #7
    bne !rst_no_store+
    ldx #0
!rst_store_chk:
    lda store_door_x,x
    cmp zp_temp0
    bne !rst_store_nxt+
    lda store_door_y,x
    cmp zp_temp1
    bne !rst_store_nxt+
    txa
    clc
    adc #$31
    sta zp_temp3
    lda #COL_STORE
    sta rst_color_tmp
    bne !rst_no_store+
!rst_store_nxt:
    inx
    cpx #STORE_COUNT
    bne !rst_store_chk-
!rst_no_store:

    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rst_vis_ok+

    lda zp_temp0
    sec
    sbc zp_player_x
    bcs !rst_dx_pos+
    eor #$ff
    clc
    adc #1
!rst_dx_pos:
    sta rst_dim_tmp

    lda zp_temp1
    sec
    sbc zp_player_y
    bcs !rst_dy_pos+
    eor #$ff
    clc
    adc #1
!rst_dy_pos:
    cmp rst_dim_tmp
    bcs !rst_use_dy+
    lda rst_dim_tmp
!rst_use_dy:
    cmp zp_light_radius
    beq !rst_vis_ok+
    bcc !rst_vis_ok+

    lda #COL_DGREY
    sta rst_color_tmp
    jmp !rst_monster+

!rst_vis_ok:
    lda zp_tile_tmp
    and #FLAG_HAS_ITEM
    beq !rst_no_item+
    ldy zp_temp1
    lda zp_temp0
    jsr floor_item_find_at
    bcc !rst_no_item+
    lda fi_item_id,x
    tax
    jsr item_get_display_char
    sta zp_temp3
    txa
    jsr item_get_floor_color
    sta rst_color_tmp
!rst_no_item:
    ldy zp_temp1
    lda zp_temp0
    jsr glyph_find_at
    bcc !rst_monster+
    lda #SC_GLYPH
    sta zp_temp3
    lda #COL_GLYPH
    sta rst_color_tmp

!rst_monster:
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq !rst_no_monster+
    ldy zp_temp1
    lda zp_temp0
    jsr monster_find_at
    bcc !rst_no_monster+
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #(MF_VISIBLE | MF_DETECTED)
    beq !rst_no_monster+
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda cr_display,x
    sta zp_temp3
    lda cr_color,x
    sta rst_color_tmp

!rst_no_monster:
rst_apply_player_override:
    lda zp_temp0
    cmp zp_player_x
    bne !rst_write+
    lda zp_temp1
    cmp zp_player_y
    bne !rst_write+
    lda #SC_PLAYER
    sta zp_temp3
    lda #COL_PLAYER
    sta rst_color_tmp
    jmp !rst_write+

!rst_blank:
    lda #SC_SPACE
    sta zp_temp3
    lda #COL_BLACK
    sta rst_color_tmp
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq rst_apply_player_override
    bne !rst_monster-

!rst_write:
    stz VERA_CTRL
    lda rst_col_tmp
    asl
    sta VERA_ADDR_L
    lda rst_row_tmp
    clc
    adc #VERA_TEXT_BASE_MID
    sta VERA_ADDR_M
    lda #(VERA_TEXT_BASE_HIGH | VERA_INC_1)
    sta VERA_ADDR_H
    lda zp_temp3
    sta VERA_DATA0
    lda rst_color_tmp
    and #$0f
    sta VERA_DATA0

    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    rts

// ============================================================
// Saved positions & render_local_area
// ============================================================
old_view_x:    .byte 0
old_view_y:    .byte 0
old_player_x:  .byte 0
old_player_y:  .byte 0

render_local_area:
    lda old_player_x
    cmp zp_player_x
    bcc !rla_ox+
    lda zp_player_x
!rla_ox:
    sec
    sbc zp_light_radius
    bcs !rla_mx1+
    lda #0
    beq !rla_mx2+
!rla_mx1:
    sec
    sbc #1
    bcs !rla_mx2+
    lda #0
!rla_mx2:
    cmp zp_view_x
    bcs !rla_mx3+
    lda zp_view_x
!rla_mx3:
    sta rla_min_x

    lda old_player_x
    cmp zp_player_x
    bcs !rla_ox2+
    lda zp_player_x
!rla_ox2:
    clc
    adc zp_light_radius
    clc
    adc #1
    sta rla_max_x
    lda zp_view_x
    clc
    adc #VIEWPORT_W - 1
    cmp rla_max_x
    bcs !rla_mx4+
    sta rla_max_x
!rla_mx4:
    lda rla_max_x
    cmp #MAP_COLS
    bcc !rla_mx5+
    lda #MAP_COLS - 1
    sta rla_max_x
!rla_mx5:

    lda old_player_y
    cmp zp_player_y
    bcc !rla_oy+
    lda zp_player_y
!rla_oy:
    sec
    sbc zp_light_radius
    bcs !rla_my1+
    lda #0
    beq !rla_my2+
!rla_my1:
    sec
    sbc #1
    bcs !rla_my2+
    lda #0
!rla_my2:
    cmp zp_view_y
    bcs !rla_my3+
    lda zp_view_y
!rla_my3:
    sta rla_min_y

    lda old_player_y
    cmp zp_player_y
    bcs !rla_oy2+
    lda zp_player_y
!rla_oy2:
    clc
    adc zp_light_radius
    clc
    adc #1
    sta rla_max_y
    lda zp_view_y
    clc
    adc #VIEWPORT_H - 1
    cmp rla_max_y
    bcs !rla_my4+
    sta rla_max_y
!rla_my4:
    lda rla_max_y
    cmp #MAP_ROWS
    bcc !rla_my5+
    lda #MAP_ROWS - 1
    sta rla_max_y
!rla_my5:

    lda rla_min_y
    sta rla_cur_y
!rla_row:
    lda rla_min_x
    sta rla_cur_x
!rla_col:
    lda rla_cur_x
    sta zp_temp0
    lda rla_cur_y
    sta zp_temp1
    jsr render_single_tile

    lda rla_cur_x
    cmp rla_max_x
    bcs !rla_col_done+
    inc rla_cur_x
    bne !rla_col-
!rla_col_done:

    lda rla_cur_y
    cmp rla_max_y
    bcs !rla_done+
    inc rla_cur_y
    bne !rla_row-
!rla_done:
    rts

rv_row_map_y:  .byte 0
rv_row_dy:     .byte 0
rv_player_vx:  .byte 0
rv_player_row: .byte 0
rv_col_tmp:    .byte 0
rst_row_tmp:   .byte 0
rst_col_tmp:   .byte 0
rst_color_tmp: .byte 0
rst_dim_tmp:   .byte 0
rla_min_x:     .byte 0
rla_max_x:     .byte 0
rla_min_y:     .byte 0
rla_max_y:     .byte 0
rla_cur_x:     .byte 0
rla_cur_y:     .byte 0

.assert "Viewport width", VIEWPORT_W, 78
.assert "Viewport height", VIEWPORT_H, 18
