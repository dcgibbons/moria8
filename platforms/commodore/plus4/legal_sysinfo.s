#importonce
// Plus/4 platform rows for LegalOverlay System Info (LEGALUI).
.encoding "screencode_mixed"

legal_sysinfo_draw_platform:
    // Platform
    lda #<legal_sysinfo_lbl_plat
    ldy #>legal_sysinfo_lbl_plat
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_plat_plus4
    ldy #>legal_sysinfo_plat_plus4
    jsr screen_put_string_ay

    // Build
    lda #<legal_sysinfo_lbl_build
    ldy #>legal_sysinfo_lbl_build
    jsr legal_sysinfo_begin_row
#if PLUS4_CARTRIDGE
    lda #<legal_sysinfo_build_cart
    ldy #>legal_sysinfo_build_cart
#else
    lda #<legal_sysinfo_build_disk
    ldy #>legal_sysinfo_build_disk
#endif
    jsr screen_put_string_ay

    // System (64KB RAM + TED PAL/NTSC bit 6: 0=PAL, 1=NTSC)
    lda #<legal_sysinfo_lbl_sys
    ldy #>legal_sysinfo_lbl_sys
    jsr legal_sysinfo_begin_row
    lda $ff07
    and #$40
    bne !ntsc+
    lda #<legal_sysinfo_sys_pal
    ldy #>legal_sysinfo_sys_pal
    jmp !put_sys+
!ntsc:
    lda #<legal_sysinfo_sys_ntsc
    ldy #>legal_sysinfo_sys_ntsc
!put_sys:
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

legal_sysinfo_plat_plus4:   .text "Commodore Plus/4"; .byte 0
#if PLUS4_CARTRIDGE
legal_sysinfo_build_cart:   .text "Cartridge"; .byte 0
#else
legal_sysinfo_build_disk:   .text "Floppy / Disk"; .byte 0
#endif
legal_sysinfo_sys_pal:      .text "64KB RAM  PAL"; .byte 0
legal_sysinfo_sys_ntsc:     .text "64KB RAM  NTSC"; .byte 0
