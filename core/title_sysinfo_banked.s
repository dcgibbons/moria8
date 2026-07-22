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
#if APPLE2
    // Apple II: detect machine from ROM ID bytes (Apple II Miscellaneous
    // Technical Note #7), and ProDOS version from KVERSION ($BFFF).
    ldx #28                     // center for ~24 chars
    stx zp_cursor_col

    lda $fbb3                   // family byte: $06 = IIe/IIc family
    cmp #$06
    bne !generic+
    lda $fbc0
    cmp #$ea                    // IIe
    beq !iie+
    cmp #$e0                    // IIe enhanced
    beq !iie+
    cmp #$00                    // IIc
    beq !iic+
!generic:
    lda #<tsi_apple2_str
    ldy #>tsi_apple2_str
    jmp !tsi_print_machine+
!iie:
    lda #<tsi_apple_iie_str
    ldy #>tsi_apple_iie_str
    jmp !tsi_print_machine+
!iic:
    lda #<tsi_apple_iic_str
    ldy #>tsi_apple_iic_str
!tsi_print_machine:
    jsr tsi_print

    // ProDOS version: KVERSION ($BFFF); suppress if implausible.
    lda $bfff
    beq !done+
    cmp #$80
    bcs !done+
    sta zp_temp0
    lda #<tsi_prodos_str
    ldy #>tsi_prodos_str
    jsr tsi_print
    lda zp_temp0
    lsr
    lsr
    lsr
    lsr
    jsr tsi_digit
    lda #$2e                    // '.'
    jsr hal_screen_put_char
    lda zp_temp0
    and #$0f
    jsr tsi_digit
!done:
    rts

tsi_digit:
    cmp #10
    bcs !td_q+
    ora #$30                    // screencode digit
    jmp hal_screen_put_char
!td_q:
    lda #$3f                    // '?'
    jmp hal_screen_put_char
#else
    // Start column: compact 40-column centering.
#if HAL_PLATFORM_TITLE_SYSINFO_80COL
    ldx #((SCREEN_COLS - 15) / 2)   // "C128  KERNAL R1"
#else
    ldx #16
#endif
    lda reu_present
    beq !+
    ldx #10
!:  stx zp_cursor_col

    // Machine type
#if HAL_PLATFORM_TITLE_SYSINFO_80COL
    lda #<tsi_c128_str
    ldy #>tsi_c128_str
#else
#if HAL_PLATFORM_TITLE_SYSINFO_SX64_PROBE
    ldx #0                      // C64 default; check for SX-64
    // C64 — check for SX-64 (KERNAL_REV = $43)
    lda tsi_krev_cached         // Cached by trampoline before banking
    cmp #$43
    bne !pm+
    ldx #1                      // SX-64
!pm:
    lda ultimate_model_present
    beq !pmu+
    ldx #2                      // C64 Ultimate / Ultimate-family UCI
!pmu:
    lda tsi_mach_lo,x
    ldy tsi_mach_hi,x
#else
    lda ultimate_model_present
    beq !pm_c64+
    lda #<tsi_c64u_str
    ldy #>tsi_c64u_str
    bne !pmu+
!pm_c64:
    lda #<tsi_c64_str
    ldy #>tsi_c64_str
!pmu:
#endif
#endif
    jsr tsi_print

    // " R"
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
!kp: jsr hal_screen_put_char

    // REU info if present
    lda reu_present
    beq !done+
    lda #<tsi_expansion_str
    ldy #>tsi_expansion_str
    jsr tsi_print
    lda reu_size_kb
    sta zp_temp0
    lda reu_size_kb + 1
    sta zp_temp1
    jsr screen_put_decimal_16
#if HAL_PLATFORM_TITLE_SYSINFO_80COL
    lda #<tsi_kb_str
    ldy #>tsi_kb_str
    jsr tsi_print
#else
    lda #$4b                    // "K"
    jsr hal_screen_put_char
#endif
!done:
    rts
#endif

tsi_print:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp hal_screen_put_string

tsi_mach_lo:
#if HAL_PLATFORM_TITLE_SYSINFO_SX64_PROBE
    .byte <tsi_c64_str, <tsi_sx64_str, <tsi_c64u_str
#endif
tsi_mach_hi:
#if HAL_PLATFORM_TITLE_SYSINFO_SX64_PROBE
    .byte >tsi_c64_str, >tsi_sx64_str, >tsi_c64u_str
#endif
#if APPLE2
tsi_apple2_str:    .text "APPLE II" ; .byte 0
tsi_apple_iie_str: .text "APPLE IIe" ; .byte 0
tsi_apple_iic_str: .text "APPLE IIc" ; .byte 0
tsi_prodos_str:    .text "  PRODOS " ; .byte 0
#endif
tsi_c64_str:    .text "C64" ; .byte 0
tsi_c64u_str:   .text "C64U" ; .byte 0
#if HAL_PLATFORM_TITLE_SYSINFO_80COL
tsi_c128_str:   .text "C128" ; .byte 0
#endif
#if HAL_PLATFORM_TITLE_SYSINFO_SX64_PROBE
tsi_sx64_str:   .text "SX-64" ; .byte 0
#endif
#if HAL_PLATFORM_TITLE_SYSINFO_80COL
tsi_kernal_str: .text "  KERNAL R" ; .byte 0
#else
tsi_kernal_str: .text " R" ; .byte 0
#endif
tsi_expansion_str:
    .byte $20, $20, $52, $45, $55, $20, 0
#if HAL_PLATFORM_TITLE_SYSINFO_80COL
tsi_kb_str:     .text "KB" ; .byte 0
#endif
tsi_krev_table: .byte $aa, $00, $03, $43, $01
tsi_krev_chars: .byte $31, $32, $33, $31, $31
