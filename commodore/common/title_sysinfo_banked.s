#importonce
// title_sysinfo_banked.s — System info display (banked at $F000)
//
// Shows machine type, KERNAL revision, and REU info on title screen.
// Called via trampoline in main.s which caches KERNAL_REV before banking.
// All tsi_* strings and data tables live here to save main RAM.

title_show_sysinfo_banked:
    lda #COL_DGREY
    sta zp_text_color
    lda #23
    sta zp_cursor_row
    // Start column: centered baseline; shift left when REU info is shown.
#if C128
    ldx #((SCREEN_COLS - 15) / 2)   // "C128  KERNAL R1"
#else
    ldx #12
#endif
    lda reu_present
    beq !+
    dex
    dex
    dex
    dex
    dex
!:  stx zp_cursor_col

    // Machine type: X = 0(C64), 1(C128), 2(SX-64)
#if C128
    ldx #1                      // C128 build
#else
    ldx #0                      // C64 default; check for SX-64
    // C64 — check for SX-64 (KERNAL_REV = $43)
    lda tsi_krev_cached         // Cached by trampoline before banking
    cmp #$43
    bne !pm+
    ldx #2                      // SX-64
#endif
!pm:
    lda tsi_mach_lo,x
    ldy tsi_mach_hi,x
    jsr tsi_print

    // "  KERNAL R"
    lda #<tsi_kernal_str
    ldy #>tsi_kernal_str
    jsr tsi_print

    // Revision digit lookup (using cached value)
    lda tsi_krev_cached
    ldx #4
!kl: cmp tsi_krev_table,x
    beq !kf+
    dex
    bpl !kl-
    lda #$3f                    // '?' screen code
    bne !kp+                    // always taken (A != 0)
!kf: lda tsi_krev_chars,x
!kp: jsr screen_put_char

    // REU info if present
    lda reu_present
    beq !done+
    lda #<tsi_reu_str
    ldy #>tsi_reu_str
    jsr tsi_print
    lda reu_size_kb
    sta zp_temp0
    lda reu_size_kb + 1
    sta zp_temp1
    jsr screen_put_decimal_16
    lda #<tsi_kb_str
    ldy #>tsi_kb_str
    jsr tsi_print
!done:
    rts

tsi_print:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp screen_put_string

tsi_mach_lo:    .byte <tsi_c64_str, <tsi_c128_str, <tsi_sx64_str
tsi_mach_hi:    .byte >tsi_c64_str, >tsi_c128_str, >tsi_sx64_str
tsi_c64_str:    .text "C64" ; .byte 0
tsi_c128_str:   .text "C128" ; .byte 0
tsi_sx64_str:   .text "SX-64" ; .byte 0
tsi_kernal_str: .text "  KERNAL R" ; .byte 0
tsi_reu_str:    .text "  REU " ; .byte 0
tsi_kb_str:     .text "KB" ; .byte 0
tsi_krev_table: .byte $aa, $00, $03, $43, $01
tsi_krev_chars: .byte $31, $32, $33, $31, $31
