#importonce
// dungeon_render.s — BBC Master 128 80-column dungeon viewport renderer (< $3000).
//
// Draws the 78x18 viewport at screen (1,2) from the Bank 5 198x66 map ($8000-$B30B).
//
// Performance & Monochrome LOS design:
//   - Block-reads the 78-byte map row slice from Bank 5 into rv_row_map_buf
//     (beeb_ss_buf + 0) once per row via mmu_safe_map_read_block (1 bank switch/row).
//   - Stages the 80-column screen row into rv_row_scr_buf (beeb_ss_buf + 80;
//     border cols 0 and 79 are permanent spaces).
//   - Monochrome LOS differentiation: lit / in-LOS open floor tiles render '.'
//     ($2E); remembered out-of-LOS open floor tiles (!rv_dimmed / !rst_dimmed)
//     render ' ' ($20) while walls (#), doors (+, ', 1-8), and stairs (<, >)
//     keep their structural glyphs.
//   - Flushes each 80-byte staged row to LYNNE ($3800 shadow + $4400 Mode 0
//     bitmap) under a single ACCCON = $05 switch, comparing each cell against
//     beeb_char_shadow and skipping unchanged 8-byte glyph blits in 9 cycles!

// Scroll deadband margins (78x18 viewport, matching C128/Apple II/CX16)
.const VIEW_SCROLL_MARGIN_X = 12
.const VIEW_SCROLL_MARGIN_Y = 4

// Staging buffers in low RAM (aliases of beeb_ss_buf $0700-$07FF in memory.s):
//   $0700-$074D (78 B): rv_row_map_buf (current row's map slice from Bank 5)
//   $0750-$079F (80 B): rv_row_scr_buf (staged 80-col screen codes for row)

// ============================================================
// viewport_update — Recenter viewport on player with scroll deadband
// ============================================================
vu_scroll_margin: .byte VIEW_SCROLL_MARGIN_X, VIEW_SCROLL_MARGIN_Y
vu_far_span:      .byte VIEWPORT_W - 1 - VIEW_SCROLL_MARGIN_X, VIEWPORT_H - 1 - VIEW_SCROLL_MARGIN_Y
vu_max_view:      .byte MAP_COLS - VIEWPORT_W, MAP_ROWS - VIEWPORT_H

viewport_update:
    ldx #0
    jsr vu_update_axis
    ldx #1
vu_update_axis:
    lda zp_view_x,x
    clc
    adc vu_scroll_margin,x
    cmp zp_player_x,x
    bcc !vu_check_far+
    beq !vu_check_far+
    lda zp_player_x,x
    sec
    sbc vu_scroll_margin,x
    bcs !vu_store+
    lda #0
!vu_store:
    sta zp_view_x,x
    rts
!vu_check_far:
    lda zp_view_x,x
    clc
    adc vu_far_span,x
    cmp zp_player_x,x
    bcs !vu_done+
    lda zp_player_x,x
    sec
    sbc vu_far_span,x
    cmp vu_max_view,x
    bcc !vu_store-
    lda vu_max_view,x
    bne !vu_store-
!vu_done:
    rts

// ============================================================
// render_viewport — Draw the 78x18 viewport
// ============================================================
render_viewport:
    lda zp_player_x
    sec
    sbc zp_view_x
    sta rv_player_vx

    // Permanent border spaces at columns 0 and 79
    lda #SC_SPACE
    sta rv_row_scr_buf
    sta rv_row_scr_buf + SCREEN_COLS - 1

    lda #0
    sta zp_render_y

!row_loop:
    lda zp_view_y
    clc
    adc zp_render_y
    tax

    // Block-read 78-byte map row slice from Bank 5 into rv_row_map_buf
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

    lda zp_view_y
    clc
    adc zp_render_y
    sta zp_temp1
    ldx #0
    cmp zp_player_y
    bne !rv_player_row_done+
    inx
!rv_player_row_done:
    stx rv_player_row

    stz zp_render_x

!col_loop:
    ldy zp_render_x
    lda rv_row_map_buf,y
    sta zp_tile_tmp
    and #(FLAG_VISITED | FLAG_OCCUPIED)
    beq !draw_blank+

    lda zp_view_x
    clc
    adc zp_render_x
    sta zp_temp0
    jsr dr_eval_tile_char
    bra !rv_player_chk+

!draw_blank:
    lda #SC_SPACE
    sta zp_temp3

!rv_player_chk:
    lda rv_player_row
    beq !write_tile+
    lda zp_render_x
    cmp rv_player_vx
    bne !write_tile+
    lda #SC_PLAYER
    sta zp_temp3

!write_tile:
    ldy zp_render_x
    lda zp_temp3
    sta rv_row_scr_buf + VIEWPORT_X,y

    inc zp_render_x
    lda zp_render_x
    cmp #VIEWPORT_W
    bne !col_loop-

    lda zp_render_y
    clc
    adc #VIEWPORT_Y
    tax
    jsr beeb_flush_row_buf

    inc zp_render_y
    lda zp_render_y
    cmp #VIEWPORT_H
    beq !done+
    jmp !row_loop-
!done:
    stz vis_room_revealed
    rts

// ============================================================
// dr_eval_tile_char — Compute screen char for map tile (zp_temp0, zp_temp1)
// Input:  zp_tile_tmp = map byte, zp_temp0 = map_x, zp_temp1 = map_y
// Output: zp_temp3 = display screen code (handles unvisited detected monsters,
//         wall '#', store doors '1'..'8', monochrome LOS dim, items/glyphs, monsters)
// ============================================================
dr_eval_tile_char:
    lda #SC_SPACE
    sta zp_temp3
    lda zp_tile_tmp
    and #FLAG_VISITED
    bne !detc_visited+
    jmp !detc_monster+
!detc_visited:

    lda zp_tile_tmp
    lsr
    lsr
    lsr
    lsr
    tax

    // Wall types 1-6 without FLAG_LIT = corridor rock -> '#'
    cpx #7
    bcs !detc_normal+
    cpx #1
    bcc !detc_normal+
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !detc_normal+
    lda #$23                // '#'
    sta zp_temp3
    bne !detc_tile_set+
!detc_normal:
    lda tile_screen_codes,x
    sta zp_temp3
!detc_tile_set:

    // Store door number override (town only, open door tiles only)
    lda zp_player_dlvl
    bne !detc_no_store+
    cpx #7
    bne !detc_no_store+
    ldx #0
!detc_store_chk:
    lda store_door_x,x
    cmp zp_temp0
    bne !detc_store_nxt+
    lda store_door_y,x
    cmp zp_temp1
    bne !detc_store_nxt+
    txa
    clc
    adc #$31                // '1'-'8'
    sta zp_temp3
    bne !detc_no_store+
!detc_store_nxt:
    inx
    cpx #STORE_COUNT
    bne !detc_store_chk-
!detc_no_store:

    // --- Visibility gate: remembered vs currently visible ---
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !detc_vis_ok+

    lda zp_temp0
    sec
    sbc zp_player_x
    bcs !detc_dx_pos+
    eor #$ff
    inc
!detc_dx_pos:
    sta rst_dim_tmp

    lda zp_temp1
    sec
    sbc zp_player_y
    bcs !detc_dy_pos+
    eor #$ff
    inc
!detc_dy_pos:
    cmp rst_dim_tmp
    bcs !detc_use_dy+
    lda rst_dim_tmp
!detc_use_dy:
    cmp zp_light_radius
    beq !detc_vis_ok+
    bcc !detc_vis_ok+

    // Monochrome LOS differentiation: remembered floor '.' ($2E) outside
    // light radius renders as space ' ' ($20); structural walls/doors/stairs stay.
    lda zp_temp3
    cmp #$2e
    bne !detc_monster+
    lda #SC_SPACE
    sta zp_temp3
    bne !detc_monster+

!detc_vis_ok:
    lda zp_tile_tmp
    and #FLAG_HAS_ITEM
    beq !detc_no_item+
    ldy zp_temp1
    lda zp_temp0
    jsr floor_item_find_at
    bcc !detc_no_item+
    jsr floor_item_page_x          // A = item id, item_cur_page = its page
    tax
    jsr item_get_display_char
    jsr floor_item_page_restore
    sta zp_temp3
!detc_no_item:
    ldy zp_temp1
    lda zp_temp0
    jsr glyph_find_at
    bcc !detc_monster+
    lda #SC_GLYPH
    sta zp_temp3

!detc_monster:
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq !detc_done+
    ldy zp_temp1
    lda zp_temp0
    jsr monster_find_at
    bcc !detc_done+
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #(MF_VISIBLE | MF_DETECTED)
    beq !detc_done+
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda cr_display,x
    sta zp_temp3
!detc_done:
    rts

// ============================================================
// scene_render_mat_tile / render_single_tile
// ============================================================
scene_render_mat_tile:
    inc mat_scene_dirty
render_single_tile:
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha
    lda zp_cursor_row
    pha

    lda zp_temp1
    sec
    sbc zp_view_y
    clc
    adc #VIEWPORT_Y
    sta zp_cursor_row
    jsr screen_set_cursor

    lda zp_temp0
    sec
    sbc zp_view_x
    clc
    adc #VIEWPORT_X
    sta rst_col_tmp

    ldx zp_temp1
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_temp0
    jsr mmu_safe_map_read_ptr0
    sta zp_tile_tmp

    jsr dr_eval_tile_char

rst_apply_player_override:
    lda zp_temp0
    cmp zp_player_x
    bne !rst_write+
    lda zp_temp1
    cmp zp_player_y
    bne !rst_write+
    lda #SC_PLAYER
    sta zp_temp3

!rst_write:
    lda zp_temp3
    ldx rst_col_tmp
    jsr beeb_write_cell
    pla
    sta zp_cursor_row
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

rla_view_span: .byte VIEWPORT_W - 1, VIEWPORT_H - 1
rla_map_limit: .byte MAP_COLS, MAP_ROWS

render_local_area:
    ldx #0
    jsr rla_calc_axis
    ldx #1
    jsr rla_calc_axis

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
    beq !rla_col_done+
    inc rla_cur_x
    bne !rla_col-
!rla_col_done:

    lda rla_cur_y
    cmp rla_max_y
    beq !rla_done+
    inc rla_cur_y
    bne !rla_row-
!rla_done:
    rts

rla_calc_axis:
    lda old_player_x,x
    cmp zp_player_x,x
    bcc !rla_min_ok+
    lda zp_player_x,x
!rla_min_ok:
    sec
    sbc zp_light_radius
    bcs !rla_m1+
    lda #0
    beq !rla_m2+
!rla_m1:
    sec
    sbc #1
    bcs !rla_m2+
    lda #0
!rla_m2:
    cmp zp_view_x,x
    bcs !rla_m3+
    lda zp_view_x,x
!rla_m3:
    sta rla_min,x

    lda old_player_x,x
    cmp zp_player_x,x
    bcs !rla_max_ok+
    lda zp_player_x,x
!rla_max_ok:
    clc
    adc zp_light_radius
    clc
    adc #1
    sta rla_max,x
    lda zp_view_x,x
    clc
    adc rla_view_span,x
    cmp rla_max,x
    bcs !rla_m4+
    sta rla_max,x
!rla_m4:
    lda rla_max,x
    cmp rla_map_limit,x
    bcc !rla_m5+
    lda rla_map_limit,x
    dec
    sta rla_max,x
!rla_m5:
    rts

rv_player_vx:  .byte 0
rv_player_row: .byte 0
rst_col_tmp:   .byte 0
rst_dim_tmp:   .byte 0
rla_min:
rla_min_x:     .byte 0
rla_min_y:     .byte 0
rla_max:
rla_max_x:     .byte 0
rla_max_y:     .byte 0
rla_cur_x:     .byte 0
rla_cur_y:     .byte 0

.assert "Contiguous ZP pairs for axis helpers", zp_view_y == zp_view_x + 1 && zp_player_y == zp_player_x + 1 && old_player_y == old_player_x + 1, true

.assert "Viewport width", VIEWPORT_W, 78
.assert "Viewport height", VIEWPORT_H, 18
.assert "Staged screen row fits in beeb_ss_buf", rv_row_scr_buf + SCREEN_COLS <= beeb_ss_buf + $100, true
