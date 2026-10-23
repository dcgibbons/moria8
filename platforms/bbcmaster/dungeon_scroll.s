#importonce
// dungeon_scroll.s — BBC Master 128 scroll-delta viewport renderer (< $3000).
//
// Handles 1-tile single-axis viewport scrolls by staging the shifted 80-byte
// shadow row into rv_row_scr_buf, diff-flushing only changed cells to LYNNE
// via beeb_flush_row_buf, and redrawing the newly exposed strip via
// render_single_tile.

render_viewport_scroll_delta:
    lda vis_room_revealed
    bne !bsd_no+
    lda zp_view_y
    cmp old_view_y
    beq !bsd_horiz+
    lda zp_view_x
    cmp old_view_x
    bne !bsd_no+
    lda zp_view_y
    sec
    sbc old_view_y
    cmp #$01
    beq !bsd_v_up+
    cmp #$ff
    beq !bsd_v_down+
!bsd_no:
    clc
    rts
!bsd_horiz:
    lda zp_view_x
    sec
    sbc old_view_x
    cmp #$01
    beq !bsd_h_left+
    cmp #$ff
    bne !bsd_no-
    jmp !bsd_h_right+

// ------------------------------------------------------------
// Vertical, screen shifts UP (viewport moved down):
// row r = row r+1 for r = VIEWPORT_Y .. VIEWPORT_Y+H-2.
// ------------------------------------------------------------
!bsd_v_up:
    ldx #VIEWPORT_Y
!vu_row:
    stx bsd_cur_row
    inx
    jsr bsd_stage_shadow_row
    ldx bsd_cur_row
    jsr beeb_flush_row_buf
    ldx bsd_cur_row
    inx
    cpx #VIEWPORT_Y + VIEWPORT_H - 1
    bne !vu_row-
    lda zp_view_y
    clc
    adc #VIEWPORT_H - 1
!bsd_v_common:
    ldx #1
    jmp bsd_strip

// ------------------------------------------------------------
// Vertical, screen shifts DOWN (viewport moved up):
// row r = row r-1 for r = VIEWPORT_Y+H-1 .. VIEWPORT_Y+1.
// ------------------------------------------------------------
!bsd_v_down:
    ldx #VIEWPORT_Y + VIEWPORT_H - 1
!vd_row:
    stx bsd_cur_row
    dex
    jsr bsd_stage_shadow_row
    ldx bsd_cur_row
    jsr beeb_flush_row_buf
    ldx bsd_cur_row
    dex
    cpx #VIEWPORT_Y
    bne !vd_row-
    lda zp_view_y
    jmp !bsd_v_common-

// ------------------------------------------------------------
// Horizontal, screen shifts RIGHT (viewport moved left):
// new col c = old col c-1 for c = 78..2; col 0 and 79 stay SC_SPACE.
// ------------------------------------------------------------
!bsd_h_right:
    ldx #VIEWPORT_Y
!hr_row:
    stx bsd_cur_row
    jsr bsd_stage_shadow_row
    ldy #VIEWPORT_W
!hr_shift:
    lda rv_row_scr_buf - 1,y
    sta rv_row_scr_buf,y
    dey
    cpy #1
    bne !hr_shift-
    ldx bsd_cur_row
    jsr beeb_flush_row_buf
    ldx bsd_cur_row
    inx
    cpx #VIEWPORT_Y + VIEWPORT_H
    bne !hr_row-
    lda zp_view_x
    jmp !bsd_h_common+

// ------------------------------------------------------------
// Horizontal, screen shifts LEFT (viewport moved right):
// new col c = old col c+1 for c = 1..77; col 0 and 79 stay SC_SPACE.
// ------------------------------------------------------------
!bsd_h_left:
    ldx #VIEWPORT_Y
!hl_row:
    stx bsd_cur_row
    jsr bsd_stage_shadow_row
    ldy #1
!hl_shift:
    lda rv_row_scr_buf + 1,y
    sta rv_row_scr_buf,y
    iny
    cpy #VIEWPORT_W
    bne !hl_shift-
    ldx bsd_cur_row
    jsr beeb_flush_row_buf
    ldx bsd_cur_row
    inx
    cpx #VIEWPORT_Y + VIEWPORT_H
    bne !hl_row-
    lda zp_view_x
    clc
    adc #VIEWPORT_W - 1
!bsd_h_common:
    ldx #0
    jmp bsd_strip

// bsd_strip — Redraw the exposed edge strip via render_single_tile.
bsd_strip:
    sta zp_temp2
    stx bsd_dir
    lda #0
    sta bsd_i
!s:
    lda zp_temp2
    ldx bsd_dir
    bne !s_row+
    sta zp_temp0
    lda zp_view_y
    clc
    adc bsd_i
    sta zp_temp1
    jmp !s_draw+
!s_row:
    sta zp_temp1
    lda zp_view_x
    clc
    adc bsd_i
    sta zp_temp0
!s_draw:
    jsr render_single_tile
    inc bsd_i
    lda bsd_i
    ldx bsd_dir
    beq !s_col+
    cmp #VIEWPORT_W
    bne !s-
    sec
    rts
!s_col:
    cmp #VIEWPORT_H
    bne !s-
    sec
    rts

bsd_cur_row: .byte 0
bsd_dir:     .byte 0
bsd_i:       .byte 0
