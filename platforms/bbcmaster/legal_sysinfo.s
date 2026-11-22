#importonce
// BBC Master 128 platform rows for LegalOverlay System Info (LEGALUI).
.encoding "screencode_mixed"

legal_sysinfo_draw_platform:
    // Platform
    lda #<legal_sysinfo_lbl_plat
    ldy #>legal_sysinfo_lbl_plat
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_plat_bbc
    ldy #>legal_sysinfo_plat_bbc
    jsr screen_put_string_ay

    // Build
    lda #<legal_sysinfo_lbl_build
    ldy #>legal_sysinfo_lbl_build
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_build_dfs
    ldy #>legal_sysinfo_build_dfs
    jsr screen_put_string_ay

    // System (128KB + MOS version via OSBYTE A=0, X=1 — never X=0 which BRKs!)
    lda #<legal_sysinfo_lbl_sys
    ldy #>legal_sysinfo_lbl_sys
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_sys_pre
    ldy #>legal_sysinfo_sys_pre
    jsr screen_put_string_ay
    lda #0
    ldx #1
    jsr MOS_OSBYTE
    cpx #3
    beq !mos320+
    cpx #4
    beq !mos350+
    cpx #5
    beq !mos_compact+
    lda #<legal_sysinfo_mos_3xx
    ldy #>legal_sysinfo_mos_3xx
    jmp !put_mos+
!mos320:
    lda #<legal_sysinfo_mos_320
    ldy #>legal_sysinfo_mos_320
    jmp !put_mos+
!mos350:
    lda #<legal_sysinfo_mos_350
    ldy #>legal_sysinfo_mos_350
    jmp !put_mos+
!mos_compact:
    lda #<legal_sysinfo_mos_cmp
    ldy #>legal_sysinfo_mos_cmp
!put_mos:
    jsr screen_put_string_ay

    // Drives (Acorn DFS drives :0..:3 from (device - 8) & 3)
    lda #<legal_sysinfo_lbl_drv
    ldy #>legal_sysinfo_lbl_drv
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_p_dfs
    ldy #>legal_sysinfo_p_dfs
    jsr screen_put_string_ay
    lda program_device
    jsr legal_sysinfo_put_dfs_drv
    lda #<legal_sysinfo_s_dfs
    ldy #>legal_sysinfo_s_dfs
    jsr screen_put_string_ay
    lda save_device
    jsr legal_sysinfo_put_dfs_drv
    jsr legal_sysinfo_put_disk_mode_suffix

    // Last I/O
    lda #<legal_sysinfo_lbl_io
    ldy #>legal_sysinfo_lbl_io
    jsr legal_sysinfo_begin_row
    jmp legal_sysinfo_put_last_io_common

legal_sysinfo_put_dfs_drv:
    sec
    sbc #8
    and #$03
    ora #$30
    jsr hal_screen_put_char
    lda #'.'
    jmp hal_screen_put_char

legal_sysinfo_lbl_plat:     .text "Platform:"; .byte 0
legal_sysinfo_lbl_build:    .text "Build:"; .byte 0
legal_sysinfo_lbl_sys:      .text "System:"; .byte 0
legal_sysinfo_lbl_drv:      .text "Drives:"; .byte 0
legal_sysinfo_lbl_io:       .text "Last I/O:"; .byte 0

legal_sysinfo_plat_bbc:     .text "BBC Master 128 (65C02 Mode 0)"; .byte 0
legal_sysinfo_build_dfs:    .text "Acorn DFS Floppy"; .byte 0
legal_sysinfo_sys_pre:      .text "128KB  MOS "; .byte 0
legal_sysinfo_mos_320:      .text "3.20"; .byte 0
legal_sysinfo_mos_350:      .text "3.50"; .byte 0
legal_sysinfo_mos_cmp:      .text "Compact"; .byte 0
legal_sysinfo_mos_3xx:      .text "3.xx"; .byte 0
legal_sysinfo_p_dfs:        .text "P::"; .byte 0
legal_sysinfo_s_dfs:        .text "  S::"; .byte 0
