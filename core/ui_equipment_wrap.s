#importonce

#if HAL_LAYOUT_EQUIPMENT_WRAP
ueq_wrap_enable:
    php
    sei
    lda screen_vectors + 4
    sta ueq_saved_char_lo
    lda screen_vectors + 5
    sta ueq_saved_char_hi
    lda screen_vectors + 7
    sta ueq_saved_string_lo
    lda screen_vectors + 8
    sta ueq_saved_string_hi
    lda #<ueq_wrap_put_char
    sta screen_vectors + 4
    lda #>ueq_wrap_put_char
    sta screen_vectors + 5
    lda #<ueq_wrap_put_string
    sta screen_vectors + 7
    lda #>ueq_wrap_put_string
    sta screen_vectors + 8
    lda #0
    sta ueq_pending_space
    plp
    rts

ueq_wrap_disable:
    php
    sei
    lda ueq_saved_char_lo
    sta screen_vectors + 4
    lda ueq_saved_char_hi
    sta screen_vectors + 5
    lda ueq_saved_string_lo
    sta screen_vectors + 7
    lda ueq_saved_string_hi
    sta screen_vectors + 8
    plp
    rts

ueq_wrap_put_char:
    sta ueq_wrap_char
    txa
    pha
    lda ueq_pending_space
    beq !ueqw_no_pending+
    lda #0
    sta ueq_pending_space
    lda ueq_wrap_char
    cmp #$28
    beq !ueqw_paren_after_space+
    cmp #$1b
    beq !ueqw_paren_after_space+
    lda #$20
    jsr screen_put_char
    jmp !ueqw_no_pending+
!ueqw_paren_after_space:
    // Deferred space before a suffix paren: wrap on the first row so the
    // suffix stays whole; on the continuation row write both inline.
    lda ueq_wrap_line
    bne !ueqw_flush_space+
    jmp !ueqw_wrap+
!ueqw_flush_space:
    lda #$20
    jsr screen_put_char
!ueqw_no_pending:
    lda ueq_wrap_char
    cmp #$20
    bne !ueqw_not_space+
    // Defer spaces near the right edge on the first row only; the
    // continuation row writes them inline.
    lda ueq_wrap_line
    bne !ueqw_write+
    ldx zp_cursor_col
    cpx #(SCREEN_COLS - 14)
    bcc !ueqw_write+
    lda #1
    sta ueq_pending_space
    pla
    tax
    rts
!ueqw_not_space:
    lda ueq_wrap_char
    cmp #$28
    beq !ueqw_suffix_check+
    cmp #$1b
    bne !ueqw_edge_check+
!ueqw_suffix_check:
    // Keep a suffix parenthetical whole on the first row only; on the
    // continuation row fall through to the hard-edge clip.
    lda ueq_wrap_line
    bne !ueqw_edge_check+
    ldx zp_cursor_col
    cpx #(SCREEN_COLS - 14)
    bcs !ueqw_wrap+
!ueqw_edge_check:
    ldx zp_cursor_col
    cpx #SCREEN_COLS
    bcc !ueqw_write+
    lda ueq_wrap_line
    bne !ueqw_done+             // Continuation overflow: clip cleanly
!ueqw_wrap:
    inc ueq_wrap_line
    inc zp_cursor_row
    lda ueq_wrap_col
    sta zp_cursor_col
!ueqw_write:
    lda ueq_wrap_char
    jsr screen_put_char
    pla
    tax
    rts
!ueqw_done:
    pla
    tax
    rts

ueq_wrap_put_string:
    ldy #0
!ueqws_loop:
    sty ueq_string_idx
    lda (zp_ptr0),y
    beq !ueqws_done+
    jsr ueq_wrap_put_char
    ldy ueq_string_idx
    iny
    bne !ueqws_loop-
!ueqws_done:
    rts

ueq_saved_char_lo: .byte 0
ueq_saved_char_hi: .byte 0
ueq_saved_string_lo: .byte 0
ueq_saved_string_hi: .byte 0
ueq_wrap_col: .byte 0
ueq_wrap_line: .byte 0
ueq_string_idx: .byte 0
ueq_wrap_char: .byte 0
ueq_pending_space: .byte 0
#endif
