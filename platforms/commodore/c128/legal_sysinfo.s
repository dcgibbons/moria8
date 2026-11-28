#importonce
// C128 platform rows for LegalOverlay System Info (LEGALUI).
.encoding "screencode_mixed"

legal_sysinfo_draw_platform:
    // Platform
    lda #<legal_sysinfo_lbl_plat
    ldy #>legal_sysinfo_lbl_plat
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_plat_c128
    ldy #>legal_sysinfo_plat_c128
    jsr screen_put_string_ay

    // Build
    lda #<legal_sysinfo_lbl_build
    ldy #>legal_sysinfo_lbl_build
    jsr legal_sysinfo_begin_row
#if C128_CARTRIDGE
    lda #<legal_sysinfo_build_cart
    ldy #>legal_sysinfo_build_cart
#else
    lda #<legal_sysinfo_build_disk
    ldy #>legal_sysinfo_build_disk
#endif
    jsr screen_put_string_ay

    // System (KERNAL revision + PAL/NTSC)
    lda #<legal_sysinfo_lbl_sys
    ldy #>legal_sysinfo_lbl_sys
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_kernal_str
    ldy #>legal_sysinfo_kernal_str
    jsr screen_put_string_ay
    lda tsi_krev_cached
    cmp #$01
    bne !unknown_rev+
    lda #'1'
    bne !put_rev+
!unknown_rev:
    lda #'?'
!put_rev:
    jsr hal_screen_put_char
    lda $0a03                   // C128 PAL/NTSC flag (0=NTSC, 1=PAL)
    beq !ntsc+
    lda #<legal_sysinfo_pal_str
    ldy #>legal_sysinfo_pal_str
    jmp !put_vid+
!ntsc:
    lda #<legal_sysinfo_ntsc_str
    ldy #>legal_sysinfo_ntsc_str
!put_vid:
    jsr screen_put_string_ay

    // Memory
    lda #<legal_sysinfo_lbl_mem
    ldy #>legal_sysinfo_lbl_mem
    jsr legal_sysinfo_begin_row
    lda c128_ram_256k
    bne !mem_256k+
    lda #<legal_sysinfo_mem_128k
    ldy #>legal_sysinfo_mem_128k
    bne !put_mem+
!mem_256k:
    lda #<legal_sysinfo_mem_256k
    ldy #>legal_sysinfo_mem_256k
!put_mem:
    jsr screen_put_string_ay
    lda reu_present
    beq !drives+
    lda #<legal_sysinfo_mem_reu
    ldy #>legal_sysinfo_mem_reu
    jsr screen_put_string_ay
    lda reu_size_kb
    sta zp_temp0
    lda reu_size_kb + 1
    sta zp_temp1
    jsr screen_put_decimal_16
    lda #<legal_sysinfo_kb_str
    ldy #>legal_sysinfo_kb_str
    jsr screen_put_string_ay

!drives:
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
legal_sysinfo_lbl_mem:      .text "Memory:"; .byte 0
legal_sysinfo_lbl_drv:      .text "Drives:"; .byte 0
legal_sysinfo_lbl_io:       .text "Last I/O:"; .byte 0

legal_sysinfo_plat_c128:    .text "Commodore 128 (80-col VDC)"; .byte 0
#if C128_CARTRIDGE
legal_sysinfo_build_cart:   .text "Cartridge"; .byte 0
#else
legal_sysinfo_build_disk:   .text "Floppy / Disk"; .byte 0
#endif
legal_sysinfo_kernal_str:   .text "KERNAL R"; .byte 0
legal_sysinfo_pal_str:      .text "  PAL"; .byte 0
legal_sysinfo_ntsc_str:     .text "  NTSC"; .byte 0
legal_sysinfo_mem_128k:     .text "128KB (2x64KB Banks)"; .byte 0
legal_sysinfo_mem_256k:     .text "256KB (4x64KB Banks)"; .byte 0
legal_sysinfo_mem_reu:      .text " + REU "; .byte 0
legal_sysinfo_kb_str:       .text "KB"; .byte 0
