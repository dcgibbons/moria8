#importonce
// ui_weight_helpers.s — Shared Burden header and 80-col per-item weight helpers
//
// Emits compact weight-formatting subroutines per overlay via macros so ports
// with zero resident headroom (e.g. Atari8 Default = 2 B free) incur zero
// resident cost, while 80-col ports share one copy across co-located
// ui_inventory.s + ui_equipment.s.

// Format and print zp_temp0/1 (tenths of a lb) as "N.N" (e.g. "0.5", "128.0").
// Clobbers: A, X, Y, zp_temp0-4, nf_value_2.
.macro UiWeightPutTenthsBody() {
    jsr numeric_format_u16      // nf_digit_buf[0..zp_temp2-1], zp_temp2 >= 1
}

// Entry after numeric_format_u16 (shared with col-69 right-aligned formatter).
.macro UiWeightPutTenthsFromBufBody() {
    ldx zp_temp2
    dex                         // X = integer digit count (0 when value < 10)
    bne !uwp_has_int+
    lda #$30                    // '0'
    jsr hal_screen_put_char
    jmp !uwp_dot+
!uwp_has_int:
    stx zp_temp3
    ldx #0
!uwp_int_loop:
    lda nf_digit_buf,x
    jsr hal_screen_put_char     // preserves X on every 6502 port
    inx
    cpx zp_temp3
    bcc !uwp_int_loop-
!uwp_dot:
    lda #$2e                    // '.'
    jsr hal_screen_put_char
    ldx zp_temp2
    lda nf_digit_buf - 1,x
    jmp hal_screen_put_char
}

// Compute player carry limit in tenths of a lb into zp_temp0/zp_temp1:
// min(3000, PL_STR_CUR * 130 + PL_WEIGHT), matching core/6502/inv_add.s.
.macro UiWeightCalcLimitBody() {
    lda player_data + PL_STR_CUR
    ldx #130
    jsr math_multiply           // zp_math_b:zp_math_a = STR * 130
    clc
    lda zp_math_a
    adc player_data + PL_WEIGHT
    tay
    lda zp_math_b
    adc #0
    cmp #>3000
    bcc !uwcl_ok+
    bne !uwcl_cap+
    cpy #<3000 + 1
    bcc !uwcl_ok+
!uwcl_cap:
    ldy #<3000
    lda #>3000
!uwcl_ok:
    sty zp_temp0
    sta zp_temp1
}

// Draw "Burden: X/Y lb" at (A = row, X = col).
// Requires local labels put_tenths_fn, burden_str, lb_str.
.macro UiWeightDrawBurdenHeaderBody(put_tenths_fn, burden_str, lb_str) {
    sta zp_cursor_row
    stx zp_cursor_col
    lda #COL_LGREY
    sta zp_text_color
    lda #<burden_str
    ldy #>burden_str
    jsr screen_put_string_ay

    lda #COL_WHITE
    sta zp_text_color
    lda inven_weight_lo
    sta zp_temp0
    lda inven_weight_hi
    sta zp_temp1
    jsr put_tenths_fn

    lda #$2f                    // '/'
    jsr hal_screen_put_char

    :UiWeightCalcLimitBody()
    jsr put_tenths_fn

    lda #COL_LGREY
    sta zp_text_color
    lda #<lb_str
    ldy #>lb_str
    jmp screen_put_string_ay
}

// Draw right-aligned "NNN.N lb" at cols 69..76 on current zp_cursor_row
// (with a leading guard space at col 68). Input: iw_res_0/iw_res_1 (tenths).
.macro UiWeightPutCol69Body(put_from_buf_fn, lb_str) {
    lda #COL_LGREY
    sta zp_text_color
    lda #68
    sta zp_cursor_col
    lda #$20                    // guard space before weight column
    jsr hal_screen_put_char

    lda iw_res_0
    sta zp_temp0
    lda iw_res_1
    sta zp_temp1
    jsr numeric_format_u16

    // Pad number field to 5 columns ("0.5" = 3 -> 2 spaces; "12.0" = 4 -> 1; "128.0" = 5 -> 0).
    lda zp_temp2
    cmp #1
    bne !uwc_gt1+
    lda #2
    bne !uwc_pad+
!uwc_gt1:
    lda #4
    sec
    sbc zp_temp2
    bcc !uwc_no_pad+
    beq !uwc_no_pad+
!uwc_pad:
    tax
!uwc_pad_loop:
    lda #$20
    jsr hal_screen_put_char
    dex
    bne !uwc_pad_loop-
!uwc_no_pad:
    jsr put_from_buf_fn
    lda #<lb_str
    ldy #>lb_str
    jmp screen_put_string_ay
}
