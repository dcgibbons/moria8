#importonce
// numeric_format.s — Shared numeric formatting helpers
//
// This file owns the decimal decomposition logic and power-of-10 tables used
// by both screen output and combat message composition. Screen entry points
// still rely on a backend-local `screen_put_char`.

nf_digit_buf:
    .fill 5, 0

// numeric_format_emit_screen — Emit nf_digit_buf[0..zp_temp2-1] via screen_put_char
// Input: nf_digit_buf, zp_temp2 = digit count
// Clobbers: A, X
numeric_format_emit_screen:
    ldx #0
!loop:
    lda nf_digit_buf,x
    jsr screen_put_char
    inx
    cpx zp_temp2
    bne !loop-
    rts

// screen_put_hex — Write a byte as 2-digit hex at cursor
// Input: A = byte to display
screen_put_hex:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr !hex_digit+
    jsr screen_put_char
    pla
    and #$0f
    jsr !hex_digit+
    jmp screen_put_char
!hex_digit:
    cmp #$0a
    bcc !digit+
    sbc #$09
    rts
!digit:
    ora #$30
    rts

// numeric_format_u8 — Convert an 8-bit value to screen-code digits
// Input:  A = value (0-255)
// Output: nf_digit_buf[0..zp_temp2-1] = digits, zp_temp2 = digit count
// Clobbers: A, X, Y, zp_temp4
numeric_format_u8:
    sta zp_temp4
    ldx #0
    ldy #0
    lda zp_temp4
!hundreds:
    cmp #100
    bcc !hundreds_done+
    sbc #100
    iny
    jmp !hundreds-
!hundreds_done:
    sta zp_temp4
    tya
    beq !tens+
    ora #$30
    sta nf_digit_buf,x
    inx
!tens:
    ldy #0
    lda zp_temp4
!tens_loop:
    cmp #10
    bcc !ones+
    sbc #10
    iny
    jmp !tens_loop-
!ones:
    sta zp_temp4
    tya
    bne !print_tens+
    cpx #0
    beq !print_ones+
    lda #$30
!print_tens:
    ora #$30
    sta nf_digit_buf,x
    inx
!print_ones:
    lda zp_temp4
    ora #$30
    sta nf_digit_buf,x
    inx
    stx zp_temp2
    rts

// screen_put_decimal — Write an 8-bit value as decimal at cursor
// Input: A = value (0-255)
screen_put_decimal:
    jsr numeric_format_u8
    jmp numeric_format_emit_screen

// screen_put_decimal_rj2 — Print 8-bit value right-justified in 2-char field
screen_put_decimal_rj2:
    jsr numeric_format_u8
    lda zp_temp2
    cmp #1
    bne !emit+
    lda #$20
    jsr screen_put_char
!emit:
    jmp numeric_format_emit_screen

// screen_put_decimal_lz2 — Print 8-bit value with leading zero in 2-char field
screen_put_decimal_lz2:
    jsr numeric_format_u8
    lda zp_temp2
    cmp #1
    bne !emit+
    lda #$30
    jsr screen_put_char
!emit:
    jmp numeric_format_emit_screen

// numeric_format_u16 — Convert zp_temp0/zp_temp1 to screen-code digits
// Input:  zp_temp0 = lo, zp_temp1 = hi
// Output: nf_digit_buf[0..zp_temp2-1] = digits, zp_temp2 = digit count
// Clobbers: A, X, Y, zp_temp0-4
numeric_format_u16:
    ldx #0
    ldy #4
!digit_loop:
    lda #0
    sta zp_temp3
!sub_loop:
    lda zp_temp0
    sec
    sbc decimal_powers_lo,y
    pha
    lda zp_temp1
    sbc decimal_powers_hi,y
    bcc !digit_done+
    sta zp_temp1
    pla
    sta zp_temp0
    inc zp_temp3
    jmp !sub_loop-
!digit_done:
    pla
    lda zp_temp3
    bne !print_digit+
    cpx #0
    beq !next_digit+
    lda #$30
    bne !store_digit+
!print_digit:
    ora #$30
!store_digit:
    sta nf_digit_buf,x
    inx
!next_digit:
    dey
    bne !digit_loop-
    lda zp_temp0
    ora #$30
    sta nf_digit_buf,x
    inx
    stx zp_temp2
    rts

// screen_put_decimal_16 — Write a 16-bit value as decimal at cursor
// Input: zp_temp0 = lo byte, zp_temp1 = hi byte
screen_put_decimal_16:
    jsr numeric_format_u16
    jmp numeric_format_emit_screen

decimal_powers_lo:
    .byte <1, <10, <100, <1000, <10000
decimal_powers_hi:
    .byte >1, >10, >100, >1000, >10000
