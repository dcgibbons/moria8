#importonce
// dungeon_scroll_a2.s — Apple IIe scroll-delta viewport renderer
//
// render_viewport_scroll_delta handles the common 1-tile single-axis
// viewport scroll by shifting the displayed 80-column text page in place
// and redrawing only the exposed strip, instead of a full 1404-cell
// render_viewport. Mirrors the C128 contract
// (platforms/commodore/c128/dungeon_render_vdc.s): carry set = handled,
// carry clear = caller falls back to full redraw.
//
// Why this is ~7x faster (~40k vs ~300k cycles per scroll):
//   A full redraw recomputes every one of the 1404 cells: an AUX map
//   read through the ZP thunk (~28 cy), tile-flag decode, item/glyph/
//   monster overlays, a2_map_char translation (~27 cy) and the parity
//   shuffle — ~210 cy/cell. A scroll does not change what the cells
//   contain, only where they sit, so instead of recomputing we move the
//   already-rendered bytes (~14 cy/byte-op) and recompute only the
//   newly exposed edge (18-78 cells via render_single_tile):
//     H: 18 rows x (80-byte stage + 78-byte rewrite) ~= 40k cycles
//     V: 17 rows x 2 half-rows x 40 bytes        ~= 37k cycles
//
// Screen mechanics (80STORE on): the 80-column page lives at $0400 with
// PAGE2 ($C054/$C055) selecting the main half (odd columns) or aux half
// (even columns). PAGE2 affects only $0400-$07FF accesses, so these
// loops run from the play slot without the RAMRD/RAMWRT code-fetch
// problem that forces map reads through ZP thunks.
//
// Horizontal shifts stage both 40-byte halves of each row into
// rv_row_map_buf (a2_ss_buf alias, idle here) and rewrite from staging:
// the even/odd interleave means direct in-place main<->aux copies
// clobber not-yet-read sources. Vertical shifts are plain row-to-row
// copies per half (40 bytes, the full half-row; border columns are
// permanent spaces so copying them is harmless).

// ============================================================
// render_viewport_scroll_delta
// Preconditions: old_view_x/old_view_y = previous viewport,
//                zp_view_x/zp_view_y   = current viewport
// Output: C=1 handled, C=0 not a clean 1-tile scroll (full redraw)
// ============================================================
render_viewport_scroll_delta:
    lda vis_room_revealed
    bne !a2sd_no+
    lda zp_view_y
    cmp old_view_y
    beq !a2sd_horiz+
    // Vertical candidate: dx must be 0
    lda zp_view_x
    cmp old_view_x
    bne !a2sd_no+
    lda zp_view_y
    sec
    sbc old_view_y
    cmp #$01
    beq !a2sd_v_up+
    cmp #$ff
    beq !a2sd_v_down+
!a2sd_no:
    clc
    rts
!a2sd_horiz:
    lda zp_view_x
    sec
    sbc old_view_x
    cmp #$01
    beq !a2sd_h_left+
!hr_chk:
    cmp #$ff
    bne !a2sd_no-
    jmp !a2sd_h_right+

// ------------------------------------------------------------
// Vertical, screen shifts UP (viewport moved down):
// row r = row r+1 for r = VIEWPORT_Y .. VIEWPORT_Y+H-2.
// ------------------------------------------------------------
!a2sd_v_up:
    ldx #VIEWPORT_Y
!vu_row:
    jsr a2sd_copy_row_fwd
    inx
    cpx #VIEWPORT_Y + VIEWPORT_H - 1
    bne !vu_row-
    // Exposed bottom map row.
    lda zp_view_y
    clc
    adc #VIEWPORT_H - 1
!a2sd_v_common:
    ldx #1
    jmp a2sd_strip

// ------------------------------------------------------------
// Vertical, screen shifts DOWN (viewport moved up):
// row r = row r-1 for r = VIEWPORT_Y+H-1 .. VIEWPORT_Y+1.
// ------------------------------------------------------------
!a2sd_v_down:
    ldx #VIEWPORT_Y + VIEWPORT_H - 1
!vd_row:
    jsr a2sd_copy_row_back
    dex
    cpx #VIEWPORT_Y
    bne !vd_row-
    // Exposed top map row.
    lda zp_view_y
    jmp !a2sd_v_common-

// ------------------------------------------------------------
// Horizontal, screen shifts RIGHT (viewport moved left).
// new col c = old col c-1 for c=78..1; col 0 is the border.
// ------------------------------------------------------------
!a2sd_h_right:
    ldx #VIEWPORT_Y
!hr_row:
    jsr a2sd_h_stage_row
    // aux[i] = main[i-1] (i=1..39) from the staged main half
    sta A2_PAGE2_ON
    ldy #1
!hr_w1:
    lda rv_row_map_buf + A2_HALF_ROW - 1,y
    sta (zp_ptr0),y
    iny
    cpy #A2_HALF_ROW
    bne !hr_w1-
    sta A2_PAGE2_OFF
    // main[i] = aux[i] (i=1..38) from the staged aux half; cols 1 and 79
    // are the exposed strip / border and stay untouched
    ldy #1
!hr_w2:
    lda rv_row_map_buf,y
    sta (zp_ptr0),y
    iny
    cpy #A2_HALF_ROW - 1
    bne !hr_w2-
    inx
    cpx #VIEWPORT_Y + VIEWPORT_H
    bne !hr_row-
    // Exposed leftmost map column.
    lda zp_view_x
    jmp !a2sd_h_common+

// ------------------------------------------------------------
// Horizontal, screen shifts LEFT (viewport moved right).
// new col c = old col c+1 for c=1..78; col 79 is the border.
// ------------------------------------------------------------
!a2sd_h_left:
    ldx #VIEWPORT_Y
!hl_row:
    jsr a2sd_h_stage_row
    // aux[i] = main[i] (i=1..39) from the staged main half
    sta A2_PAGE2_ON
    ldy #1
!hl_w1:
    lda rv_row_map_buf + A2_HALF_ROW,y
    sta (zp_ptr0),y
    iny
    cpy #A2_HALF_ROW
    bne !hl_w1-
    sta A2_PAGE2_OFF
    // main[i] = aux[i+1] (i=0..38) from the staged aux half
    ldy #0
!hl_w2:
    lda rv_row_map_buf+1,y
    sta (zp_ptr0),y
    iny
    cpy #A2_HALF_ROW - 1
    bne !hl_w2-
    inx
    cpx #VIEWPORT_Y + VIEWPORT_H
    bne !hl_row-
    // Exposed rightmost map column.
    lda zp_view_x
    clc
    adc #VIEWPORT_W - 1
!a2sd_h_common:
    ldx #0
    jmp a2sd_strip

// ------------------------------------------------------------
// a2sd_h_stage_row — Stage both 40-byte halves of text row X into
// rv_row_map_buf (aux half at +0, main half at +A2_HALF_ROW) and
// leave zp_ptr0 = row base, PAGE2 off. Clobbers A, Y.
// ------------------------------------------------------------
a2sd_h_stage_row:
    lda a2_row_lo,x
    sta zp_ptr0
    lda a2_row_hi,x
    sta zp_ptr0_hi
    sta A2_PAGE2_ON
    ldy #A2_HALF_ROW - 1
!sa:
    lda (zp_ptr0),y             // aux half
    sta rv_row_map_buf,y
    dey
    bpl !sa-
    sta A2_PAGE2_OFF
    ldy #A2_HALF_ROW - 1
!sm:
    lda (zp_ptr0),y             // main half
    sta rv_row_map_buf + A2_HALF_ROW,y
    dey
    bpl !sm-
    rts

// ------------------------------------------------------------
// a2sd_copy_row_fwd/back — Copy text row X+1 -> X / X-1 -> X,
// viewport columns (1..VIEWPORT_W) of both halves. X = dest row.
// Clobbers A, X, Y.
// ------------------------------------------------------------
a2sd_copy_row_fwd:
    lda a2_row_lo+1,x
    sta zp_ptr0
    lda a2_row_hi+1,x
    sta zp_ptr0_hi
    jmp a2sd_copy_dst_x
a2sd_copy_row_back:
    lda a2_row_lo-1,x
    sta zp_ptr0
    lda a2_row_hi-1,x
    sta zp_ptr0_hi
    // fall through
a2sd_copy_dst_x:
    lda a2_row_lo,x
    sta zp_ptr1
    lda a2_row_hi,x
    sta zp_ptr1_hi
    sta A2_PAGE2_ON
    jsr a2sd_copy_plane
    sta A2_PAGE2_OFF
    // fall through to the main-plane copy
a2sd_copy_plane:
    // Copy the full 40-byte half-row. Border columns are permanent
    // spaces, so copying them with the row is harmless.
    ldy #0
!cp:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    cpy #A2_HALF_ROW
    bne !cp-
    rts

// ------------------------------------------------------------
// a2sd_strip — Redraw the exposed strip.
// Input: A = fixed map coord (map_x when X=0, map_y when X=1)
//        X = 0: vertical strip (column), 1: horizontal strip (row)
// ------------------------------------------------------------
a2sd_strip:
    sta zp_temp2                // fixed map coord (map_x for H, map_y for V)
    stx a2sd_dir
    lda #0
    sta a2sd_i
!s:
    lda zp_temp2
    ldx a2sd_dir
    bne !s_row+
    sta zp_temp0
    lda zp_view_y
    clc
    adc a2sd_i
    sta zp_temp1
    jmp !s_draw+
!s_row:
    sta zp_temp1
    lda zp_view_x
    clc
    adc a2sd_i
    sta zp_temp0
!s_draw:
    jsr render_single_tile
    inc a2sd_i
    lda a2sd_i
    ldx a2sd_dir
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

a2sd_dir:     .byte 0
a2sd_i:       .byte 0
