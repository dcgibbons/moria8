#importonce
// dungeon_scroll_vera.s — Commander X16 scroll-delta viewport renderer
//
// Uses VERA dual data ports (VERA_DATA0 = $9F23, VERA_DATA1 = $9F24) to shift
// the 78x18 viewport in VRAM for 1-tile single-axis scrolls and redraws only
// the newly exposed strip via render_single_tile.

.const VERA_DATA1 = $9f24

render_viewport_scroll_delta:
    lda vis_room_revealed
    bne !vsd_no+
    lda zp_view_y
    cmp old_view_y
    beq !vsd_horiz+
    // Vertical candidate: dx must be 0
    lda zp_view_x
    cmp old_view_x
    bne !vsd_no+
    lda zp_view_y
    sec
    sbc old_view_y
    cmp #$01
    beq !vsd_v_up+
    cmp #$ff
    beq !vsd_v_down+
!vsd_no:
    clc
    rts
!vsd_horiz:
    lda zp_view_x
    sec
    sbc old_view_x
    cmp #$01
    beq !vsd_h_left+
    cmp #$ff
    bne !vsd_no-
    jmp !vsd_h_right+

// Vertical, screen shifts UP (viewport moved down): row r = row r+1
!vsd_v_up:
    ldx #VIEWPORT_Y
!vu_row:
    txa
    clc
    adc #1
    tay                         // Y = src row (r+1), X = dst row (r)
    jsr vsd_copy_row
    inx
    cpx #VIEWPORT_Y + VIEWPORT_H - 1
    bne !vu_row-
    lda zp_view_y
    clc
    adc #VIEWPORT_H - 1
!vsd_v_common:
    ldx #1
    jmp vsd_strip

// Vertical, screen shifts DOWN (viewport moved up): row r = row r-1
!vsd_v_down:
    ldx #VIEWPORT_Y + VIEWPORT_H - 1
!vd_row:
    txa
    sec
    sbc #1
    tay                         // Y = src row (r-1), X = dst row (r)
    jsr vsd_copy_row
    dex
    cpx #VIEWPORT_Y
    bne !vd_row-
    lda zp_view_y
    bra !vsd_v_common-

// Horizontal, screen shifts LEFT (viewport moved right): col c = col c+1 (c=1..77)
!vsd_h_left:
    php
    sei
    ldx #VIEWPORT_Y
!hl_row:
    // DATA0 = src (row X, col 2 -> byte offset 4)
    stz VERA_CTRL
    lda #4
    sta VERA_ADDR_L
    txa
    clc
    adc #VERA_TEXT_BASE_MID
    sta VERA_ADDR_M
    lda #(VERA_TEXT_BASE_HIGH | VERA_INC_1)
    sta VERA_ADDR_H
    // DATA1 = dst (row X, col 1 -> byte offset 2)
    lda #1
    sta VERA_CTRL
    lda #2
    sta VERA_ADDR_L
    txa
    clc
    adc #VERA_TEXT_BASE_MID
    sta VERA_ADDR_M
    lda #(VERA_TEXT_BASE_HIGH | VERA_INC_1)
    sta VERA_ADDR_H
    ldy #(VIEWPORT_W - 1) * 2
!hl_copy:
    lda VERA_DATA0
    sta VERA_DATA1
    dey
    bne !hl_copy-
    inx
    cpx #VIEWPORT_Y + VIEWPORT_H
    bne !hl_row-
    stz VERA_CTRL
    plp
    lda zp_view_x
    clc
    adc #VIEWPORT_W - 1
!vsd_h_common:
    ldx #0
    jmp vsd_strip

// Horizontal, screen shifts RIGHT (viewport moved left): col c = col c-1 (c=78..2)
// Stage 154 bytes (cols 1..77) to rv_row_map_buf first so forward write doesn't overlap.
!vsd_h_right:
    php
    sei
    ldx #VIEWPORT_Y
!hr_row:
    stz VERA_CTRL
    lda #2                      // col 1 -> byte offset 2
    sta VERA_ADDR_L
    txa
    clc
    adc #VERA_TEXT_BASE_MID
    sta VERA_ADDR_M
    lda #(VERA_TEXT_BASE_HIGH | VERA_INC_1)
    sta VERA_ADDR_H
    ldy #0
!hr_read:
    lda VERA_DATA0
    sta rv_row_map_buf,y
    iny
    cpy #(VIEWPORT_W - 1) * 2
    bne !hr_read-
    // Write staged bytes to col 2..78 (byte offset 4)
    lda #4
    sta VERA_ADDR_L
    ldy #0
!hr_write:
    lda rv_row_map_buf,y
    sta VERA_DATA0
    iny
    cpy #(VIEWPORT_W - 1) * 2
    bne !hr_write-
    inx
    cpx #VIEWPORT_Y + VIEWPORT_H
    bne !hr_row-
    stz VERA_CTRL
    plp
    lda zp_view_x
    bra !vsd_h_common-

// vsd_copy_row — Copy 78 viewport cells (156 bytes) from row Y to row X
// Preserves: X
vsd_copy_row:
    php
    sei
    stz VERA_CTRL
    lda #2                      // col 1 -> byte offset 2
    sta VERA_ADDR_L
    tya
    clc
    adc #VERA_TEXT_BASE_MID
    sta VERA_ADDR_M
    lda #(VERA_TEXT_BASE_HIGH | VERA_INC_1)
    sta VERA_ADDR_H

    lda #1
    sta VERA_CTRL
    lda #2
    sta VERA_ADDR_L
    txa
    clc
    adc #VERA_TEXT_BASE_MID
    sta VERA_ADDR_M
    lda #(VERA_TEXT_BASE_HIGH | VERA_INC_1)
    sta VERA_ADDR_H

    ldy #VIEWPORT_W * 2
!cp:
    lda VERA_DATA0
    sta VERA_DATA1
    dey
    bne !cp-
    stz VERA_CTRL
    plp
    rts

// vsd_strip — Redraw the exposed strip via render_single_tile
vsd_strip:
    sta zp_temp2
    stx vsd_dir
    stz vsd_i
!s:
    lda zp_temp2
    ldx vsd_dir
    bne !s_row+
    sta zp_temp0
    lda zp_view_y
    clc
    adc vsd_i
    sta zp_temp1
    jmp !s_draw+
!s_row:
    sta zp_temp1
    lda zp_view_x
    clc
    adc vsd_i
    sta zp_temp0
!s_draw:
    jsr render_single_tile
    inc vsd_i
    lda vsd_i
    ldx vsd_dir
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

vsd_dir: .byte 0
vsd_i:   .byte 0
