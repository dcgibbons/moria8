#importonce
// Apple IIe platform rows for LegalOverlay System Info (LEGALUI).
.encoding "screencode_mixed"

legal_sysinfo_draw_platform:
    // Platform (Monitor ROM ID bytes $FBB3 / $FBC0)
    lda #<legal_sysinfo_lbl_plat
    ldy #>legal_sysinfo_lbl_plat
    jsr legal_sysinfo_begin_row
    lda $fbb3
    cmp #$06
    bne !generic+
    lda $fbc0
    cmp #$e0
    beq !iie_enh+
    cmp #$ea
    beq !iie+
    cmp #$00
    beq !iic+
!generic:
    lda #<legal_sysinfo_plat_a2
    ldy #>legal_sysinfo_plat_a2
    jmp !put_plat+
!iie_enh:
    lda #<legal_sysinfo_plat_iie_enh
    ldy #>legal_sysinfo_plat_iie_enh
    jmp !put_plat+
!iie:
    lda #<legal_sysinfo_plat_iie
    ldy #>legal_sysinfo_plat_iie
    jmp !put_plat+
!iic:
    lda #<legal_sysinfo_plat_iic
    ldy #>legal_sysinfo_plat_iic
!put_plat:
    jsr screen_put_string_ay

    // Build + ProDOS KVERSION ($BFFF)
    lda #<legal_sysinfo_lbl_build
    ldy #>legal_sysinfo_lbl_build
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_build_str
    ldy #>legal_sysinfo_build_str
    jsr screen_put_string_ay
    lda $bfff
    beq !mem+
    cmp #$80
    bcs !mem+
    sta legal_sysinfo_tmp
    lda #<legal_sysinfo_v_str
    ldy #>legal_sysinfo_v_str
    jsr screen_put_string_ay
    lda legal_sysinfo_tmp
    lsr
    lsr
    lsr
    lsr
    jsr legal_sysinfo_put_hex4
    lda #'.'
    jsr hal_screen_put_char
    lda legal_sysinfo_tmp
    and #$0f
    jsr legal_sysinfo_put_hex4

!mem:
    // Memory
    lda #<legal_sysinfo_lbl_mem
    ldy #>legal_sysinfo_lbl_mem
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_mem_str
    ldy #>legal_sysinfo_mem_str
    jsr screen_put_string_ay

    // Drives (ProDOS unit bytes: bits 6..4 = slot, bit 7 = drive-1)
    lda #<legal_sysinfo_lbl_drv
    ldy #>legal_sysinfo_lbl_drv
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_p_colon
    ldy #>legal_sysinfo_p_colon
    jsr screen_put_string_ay
    lda program_device
    jsr legal_sysinfo_put_unit
    lda #<legal_sysinfo_s_colon
    ldy #>legal_sysinfo_s_colon
    jsr screen_put_string_ay
    lda save_device
    jsr legal_sysinfo_put_unit
    lda disk_mode
    cmp #A2_DISK_MODE_SWAP
    bne !chk_two_drv+
    lda #<legal_sysinfo_drv1_str
    ldy #>legal_sysinfo_drv1_str
    jsr screen_put_string_ay
    jmp !last_io+
!chk_two_drv:
    cmp #A2_DISK_MODE_TWO_DRIVE
    bne !last_io+
    lda #<legal_sysinfo_drv2_str
    ldy #>legal_sysinfo_drv2_str
    jsr screen_put_string_ay

!last_io:
    lda #<legal_sysinfo_lbl_io
    ldy #>legal_sysinfo_lbl_io
    jsr legal_sysinfo_begin_row
    jmp legal_sysinfo_put_last_io_common

legal_sysinfo_put_unit:
    bne !valid+
    lda #<legal_sysinfo_dash2_str
    ldy #>legal_sysinfo_dash2_str
    jmp screen_put_string_ay
!valid:
    sta legal_sysinfo_tmp
    lda #'S'
    jsr hal_screen_put_char
    lda legal_sysinfo_tmp
    lsr
    lsr
    lsr
    lsr
    and #$07
    ora #$30
    jsr hal_screen_put_char
    lda #'D'
    jsr hal_screen_put_char
    lda #$31
    bit legal_sysinfo_tmp
    bpl !drv1+
    lda #$32
!drv1:
    jmp hal_screen_put_char

legal_sysinfo_lbl_plat:     .text "Platform:"; .byte 0
legal_sysinfo_lbl_build:    .text "Build:"; .byte 0
legal_sysinfo_lbl_mem:      .text "Memory:"; .byte 0
legal_sysinfo_lbl_drv:      .text "Drives:"; .byte 0
legal_sysinfo_lbl_io:       .text "Last I/O:"; .byte 0

legal_sysinfo_plat_a2:      .text "Apple II (65C02 80-col)"; .byte 0
legal_sysinfo_plat_iie:     .text "Apple IIe (65C02 80-col)"; .byte 0
legal_sysinfo_plat_iie_enh: .text "Apple IIe Enhanced (80-col)"; .byte 0
legal_sysinfo_plat_iic:     .text "Apple IIc (65C02 80-col)"; .byte 0
legal_sysinfo_build_str:    .text "ProDOS 140KB"; .byte 0
legal_sysinfo_v_str:        .text " v"; .byte 0
legal_sysinfo_mem_str:      .text "128KB (64K Main + 64K Aux)"; .byte 0
legal_sysinfo_p_colon:      .text "P:"; .byte 0
legal_sysinfo_s_colon:      .text "  S:"; .byte 0
legal_sysinfo_dash2_str:    .text "--"; .byte 0
