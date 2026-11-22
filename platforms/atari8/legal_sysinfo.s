#importonce
// Atari 8-bit platform rows for LegalOverlay System Info (LEGALUI).
.encoding "screencode_mixed"

legal_sysinfo_draw_platform:
    // Platform
    lda #<legal_sysinfo_lbl_plat
    ldy #>legal_sysinfo_lbl_plat
    jsr legal_sysinfo_begin_row
#if ATARI8_CARTRIDGE
    lda #<legal_sysinfo_plat_cart
    ldy #>legal_sysinfo_plat_cart
#else
    lda xe_present
    bne !xe+
    lda #<legal_sysinfo_plat_xl
    ldy #>legal_sysinfo_plat_xl
    jmp !put_plat+
!xe:
    lda #<legal_sysinfo_plat_xe
    ldy #>legal_sysinfo_plat_xe
!put_plat:
#endif
    jsr screen_put_string_ay

    // Build
    lda #<legal_sysinfo_lbl_build
    ldy #>legal_sysinfo_lbl_build
    jsr legal_sysinfo_begin_row
#if ATARI8_CARTRIDGE
    lda #<legal_sysinfo_build_cart
    ldy #>legal_sysinfo_build_cart
#else
    lda #<legal_sysinfo_build_disk
    ldy #>legal_sysinfo_build_disk
#endif
    jsr screen_put_string_ay

    // System (RAM size + GTIA $D014 PAL/NTSC)
    // xe_present is initialized at cold boot by xe_detect (disk) or atari_cart_xe_probe (cart).
    lda #<legal_sysinfo_lbl_sys
    ldy #>legal_sysinfo_lbl_sys
    jsr legal_sysinfo_begin_row
    lda xe_present
    bne !mem_128+
    lda #<legal_sysinfo_mem_64k
    ldy #>legal_sysinfo_mem_64k
    jmp !put_mem+
!mem_128:
    lda #<legal_sysinfo_mem_128k
    ldy #>legal_sysinfo_mem_128k
!put_mem:
    jsr screen_put_string_ay
    lda $d014
    and #$0e
    cmp #$0e
    beq !ntsc+
    lda #<legal_sysinfo_pal_str
    ldy #>legal_sysinfo_pal_str
    jmp !put_vid+
!ntsc:
    lda #<legal_sysinfo_ntsc_str
    ldy #>legal_sysinfo_ntsc_str
!put_vid:
    jsr screen_put_string_ay

    // Drives (map HAL 8/9 -> Atari D1:/D2:)
    lda #<legal_sysinfo_lbl_drv
    ldy #>legal_sysinfo_lbl_drv
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_pd_str
    ldy #>legal_sysinfo_pd_str
    jsr screen_put_string_ay
    lda program_device
    jsr legal_sysinfo_put_atari_drv
    lda #<legal_sysinfo_sd_str
    ldy #>legal_sysinfo_sd_str
    jsr screen_put_string_ay
    lda save_device
    jsr legal_sysinfo_put_atari_drv
    jsr legal_sysinfo_put_disk_mode_suffix

    // Last I/O
    lda #<legal_sysinfo_lbl_io
    ldy #>legal_sysinfo_lbl_io
    jsr legal_sysinfo_begin_row
    jmp legal_sysinfo_put_last_io_common

legal_sysinfo_put_atari_drv:
    sec
    sbc #7
    jsr screen_put_decimal
    lda #':'
    jmp hal_screen_put_char

legal_sysinfo_lbl_plat:     .text "Platform:"; .byte 0
legal_sysinfo_lbl_build:    .text "Build:"; .byte 0
legal_sysinfo_lbl_sys:      .text "System:"; .byte 0
legal_sysinfo_lbl_drv:      .text "Drives:"; .byte 0
legal_sysinfo_lbl_io:       .text "Last I/O:"; .byte 0

#if ATARI8_CARTRIDGE
legal_sysinfo_plat_cart:    .text "Atari XL/XE"; .byte 0
legal_sysinfo_build_cart:   .text "128KB Cartridge"; .byte 0
#else
legal_sysinfo_plat_xl:      .text "Atari 800XL"; .byte 0
legal_sysinfo_plat_xe:      .text "Atari 130XE"; .byte 0
legal_sysinfo_build_disk:   .text "DOS 2.5 Floppy"; .byte 0
#endif
legal_sysinfo_mem_64k:      .text "64KB RAM"; .byte 0
legal_sysinfo_mem_128k:     .text "128KB RAM"; .byte 0
legal_sysinfo_pal_str:      .text "  PAL"; .byte 0
legal_sysinfo_ntsc_str:     .text "  NTSC"; .byte 0
legal_sysinfo_pd_str:       .text "P:D"; .byte 0
legal_sysinfo_sd_str:       .text "  S:D"; .byte 0
