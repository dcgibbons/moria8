#importonce
// reu_loading_banked.s — REU loading status display (banked at $F000)
//
// Shows "X/YYYКB" progress during REU preloading.
// Called via trampoline in reu.s (banks out KERNAL first).

// reu_show_status_banked — Display "X/YYYKB" progress on row 2
// Reads reu_tier_offset_lo/hi for used bytes, reu_size_kb for total.
// Used KB = ceiling(reu_tier_offset / 1024).
// Clobbers: A, X, Y
reu_show_status_banked:
    // Clear row 2 to avoid leftover digits
    lda #2
    jsr hal_screen_clear_row

    // Compute used KB = ceiling(offset / 1024)
    // = (offset + 1023) >> 10
    // Since offset <= ~18KB, result fits in 8 bits.
    clc
    lda reu_tier_offset_lo
    adc #$ff                    // Add 1023 low byte
    lda reu_tier_offset_hi
    adc #$03                    // Add 1023 high byte + carry
    lsr                         // >> 2 to get KB
    lsr
    // A = used KB (0-255 range, actual max ~18)

    // Position and print used KB
    pha
    lda #2
    sta zp_cursor_row
    sta zp_cursor_col
    pla
    jsr screen_put_decimal      // Print used KB (8-bit)

    // Print "/"
    lda #$2f                    // Screen code for '/'
    jsr hal_screen_put_char

    // Print total REU size in KB (16-bit)
    lda reu_size_kb
    sta zp_temp0
    lda reu_size_kb + 1
    sta zp_temp1
    jsr screen_put_decimal_16

    // Print "KB"
    lda #<rlb_kb_str
    sta zp_ptr0
    lda #>rlb_kb_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    rts

rlb_kb_str: .text "KB" ; .byte 0
