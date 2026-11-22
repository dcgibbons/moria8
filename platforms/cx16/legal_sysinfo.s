#importonce
// Commander X16 platform rows for LegalOverlay System Info (LEGALUI).
.encoding "screencode_mixed"

legal_sysinfo_draw_platform:
    // Platform
    lda #<legal_sysinfo_lbl_plat
    ldy #>legal_sysinfo_lbl_plat
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_plat_cx16
    ldy #>legal_sysinfo_plat_cx16
    jsr screen_put_string_ay

    // Build
    lda #<legal_sysinfo_lbl_build
    ldy #>legal_sysinfo_lbl_build
    jsr legal_sysinfo_begin_row
#if CX16_CARTRIDGE
    lda #<legal_sysinfo_build_cart
    ldy #>legal_sysinfo_build_cart
#else
    lda #<legal_sysinfo_build_disk
    ldy #>legal_sysinfo_build_disk
#endif
    jsr screen_put_string_ay

    // System (ROM rev + HiRAM)
    lda #<legal_sysinfo_lbl_sys
    ldy #>legal_sysinfo_lbl_sys
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_rom_str
    ldy #>legal_sysinfo_rom_str
    jsr screen_put_string_ay
    lda tsi_krev_cached
    beq !krev_unk+
    cmp #$ff
    beq !krev_unk+
    bpl !krev_rel+
    eor #$ff
    clc
    adc #1
    jsr screen_put_decimal
    lda #'+'
    jsr hal_screen_put_char
    bra !ram+
!krev_rel:
    jsr screen_put_decimal
    bra !ram+
!krev_unk:
    lda #'?'
    jsr hal_screen_put_char
!ram:
    lda #<legal_sysinfo_sep2
    ldy #>legal_sysinfo_sep2
    jsr screen_put_string_ay
    lda tsi_ram_banks_cached
    bne !nz_banks+
    stz zp_temp0
    lda #>2048
    sta zp_temp1
    bra !put_kb+
!nz_banks:
    sta zp_temp0
    stz zp_temp1
    asl zp_temp0
    rol zp_temp1
    asl zp_temp0
    rol zp_temp1
    asl zp_temp0
    rol zp_temp1
!put_kb:
    jsr screen_put_decimal_16
    lda #<legal_sysinfo_hiram_str
    ldy #>legal_sysinfo_hiram_str
    jsr screen_put_string_ay

    // Drives
    lda #<legal_sysinfo_lbl_drv
    ldy #>legal_sysinfo_lbl_drv
    jsr legal_sysinfo_begin_row
    jsr legal_sysinfo_put_drive_pair

    // Last I/O
    lda #<legal_sysinfo_lbl_io
    ldy #>legal_sysinfo_lbl_io
    jsr legal_sysinfo_begin_row
    jmp legal_sysinfo_put_last_io_common

legal_sysinfo_lbl_plat:     .text "Platform:"; .byte 0
legal_sysinfo_lbl_build:    .text "Build:"; .byte 0
legal_sysinfo_lbl_sys:      .text "System:"; .byte 0
legal_sysinfo_lbl_drv:      .text "Drives:"; .byte 0
legal_sysinfo_lbl_io:       .text "Last I/O:"; .byte 0

legal_sysinfo_plat_cx16:    .text "Commander X16 (80-col VERA)"; .byte 0
#if CX16_CARTRIDGE
legal_sysinfo_build_cart:   .text "ROM Cartridge"; .byte 0
#else
legal_sysinfo_build_disk:   .text "SD / HostFS"; .byte 0
#endif
legal_sysinfo_rom_str:      .text "ROM R"; .byte 0
legal_sysinfo_sep2:         .text "  "; .byte 0
legal_sysinfo_hiram_str:    .text "KB HiRAM"; .byte 0
