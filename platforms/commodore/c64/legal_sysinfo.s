#importonce
// C64 platform rows for LegalOverlay System Info (LEGALUI).
.encoding "screencode_mixed"

legal_sysinfo_draw_platform:
    // Platform
    lda #<legal_sysinfo_lbl_plat
    ldy #>legal_sysinfo_lbl_plat
    jsr legal_sysinfo_begin_row
    lda c64_hw_flags
    and #C64_HW_C64U
    beq !chk_sx+
    lda #<legal_sysinfo_plat_c64u
    ldy #>legal_sysinfo_plat_c64u
    jmp !put_plat+
!chk_sx:
    lda tsi_krev_cached
    cmp #$43
    bne !std_c64+
    lda #<legal_sysinfo_plat_sx64
    ldy #>legal_sysinfo_plat_sx64
    jmp !put_plat+
!std_c64:
    lda #<legal_sysinfo_plat_c64
    ldy #>legal_sysinfo_plat_c64
!put_plat:
    jsr screen_put_string_ay

    // Build
    lda #<legal_sysinfo_lbl_build
    ldy #>legal_sysinfo_lbl_build
    jsr legal_sysinfo_begin_row
#if C64_CARTRIDGE
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
    ldx #4
!kl:
    cmp legal_sysinfo_krev_table,x
    beq !kf+
    dex
    bpl !kl-
    lda #$3f                    // '?'
    bne !kp+
!kf:
    lda legal_sysinfo_krev_chars,x
!kp:
    jsr hal_screen_put_char
    lda $02a6                   // C64 PAL/NTSC flag (0=NTSC, 1=PAL)
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
    lda reu_present
    beq !no_reu+
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
    jmp !chk_turbo+
!no_reu:
    lda #<legal_sysinfo_mem_64k
    ldy #>legal_sysinfo_mem_64k
    jsr screen_put_string_ay
!chk_turbo:
    lda c64_hw_flags
    and #C64_HW_TURBO_AVAIL
    beq !drives+
    lda #<legal_sysinfo_turbo_str
    ldy #>legal_sysinfo_turbo_str
    jsr screen_put_string_ay

!drives:
    lda #<legal_sysinfo_lbl_drv
    ldy #>legal_sysinfo_lbl_drv
    jsr legal_sysinfo_begin_row
    jsr legal_sysinfo_put_drive_pair

    // Last I/O (C64 HAL aliases phase/readst onto disk_status)
    lda #<legal_sysinfo_lbl_io
    ldy #>legal_sysinfo_lbl_io
    jsr legal_sysinfo_begin_row
    lda hal_storage_diag_code
    beq !io_ok+
    lda #<legal_sysinfo_io_err
    ldy #>legal_sysinfo_io_err
    jsr screen_put_string_ay
    lda hal_storage_diag_code
    jsr legal_sysinfo_put_hex8
    lda #<legal_sysinfo_io_dev
    ldy #>legal_sysinfo_io_dev
    jsr screen_put_string_ay
    lda save_device
    jmp screen_put_decimal
!io_ok:
    lda #<legal_sysinfo_ok_str
    ldy #>legal_sysinfo_ok_str
    jmp screen_put_string_ay

legal_sysinfo_lbl_plat:     .text "Platform:"; .byte 0
legal_sysinfo_lbl_build:    .text "Build:"; .byte 0
legal_sysinfo_lbl_sys:      .text "System:"; .byte 0
legal_sysinfo_lbl_mem:      .text "Memory:"; .byte 0
legal_sysinfo_lbl_drv:      .text "Drives:"; .byte 0
legal_sysinfo_lbl_io:       .text "Last I/O:"; .byte 0

legal_sysinfo_plat_c64:     .text "Commodore 64"; .byte 0
legal_sysinfo_plat_sx64:    .text "Commodore SX-64"; .byte 0
legal_sysinfo_plat_c64u:    .text "C64 Ultimate"; .byte 0
#if C64_CARTRIDGE
legal_sysinfo_build_cart:   .text "EasyFlash Cartridge"; .byte 0
#else
legal_sysinfo_build_disk:   .text "Floppy / Disk"; .byte 0
#endif
legal_sysinfo_kernal_str:   .text "KERNAL R"; .byte 0
legal_sysinfo_pal_str:      .text "  PAL"; .byte 0
legal_sysinfo_ntsc_str:     .text "  NTSC"; .byte 0
legal_sysinfo_mem_64k:      .text "64KB RAM"; .byte 0
legal_sysinfo_mem_reu:      .text "64K + REU "; .byte 0
legal_sysinfo_kb_str:       .text "KB"; .byte 0
legal_sysinfo_turbo_str:    .text " Turbo"; .byte 0
legal_sysinfo_io_err:       .text "Err $"; .byte 0
legal_sysinfo_io_dev:       .text " Dev #"; .byte 0
legal_sysinfo_krev_table:   .byte $aa, $00, $03, $43, $01
legal_sysinfo_krev_chars:   .byte $31, $32, $33, $31, $31
