#importonce
// System Info modal hosted inside cold LegalOverlay (LEGALUI).
// Reads live session ZP telemetry only from legal_zp_save so neither active
// zero-page state nor LegalRestore() is ever disturbed.

#import "../build/version_strings.inc"

.assert "SysInfo ZP snapshot bounds", zp_rng_0 >= LEGAL_ZP_SNAPSHOT_BASE && zp_rng_3 <= $8f && zp_turn_lo >= LEGAL_ZP_SNAPSHOT_BASE && zp_turn_hi <= $8f && zp_player_dlvl >= LEGAL_ZP_SNAPSHOT_BASE && zp_game_flags <= $8f && zp_mon_count >= LEGAL_ZP_SNAPSHOT_BASE && zp_item_count <= $8f, true
.assert "RNG bytes contiguous", zp_rng_1 == zp_rng_0 + 1 && zp_rng_2 == zp_rng_0 + 2 && zp_rng_3 == zp_rng_0 + 3, true

.encoding "screencode_mixed"

legal_sysinfo_screen:
    jsr hal_screen_clear
    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<legal_sysinfo_heading
    ldy #>legal_sysinfo_heading
    jsr screen_put_string_ay

    lda #2
    sta legal_sysinfo_row

    // Version
    lda #<legal_sysinfo_lbl_version
    ldy #>legal_sysinfo_lbl_version
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_version_str
    ldy #>legal_sysinfo_version_str
    jsr screen_put_string_ay

    // Save format & catalog
    lda #<legal_sysinfo_lbl_format
    ldy #>legal_sysinfo_lbl_format
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_fmt_pre
    ldy #>legal_sysinfo_fmt_pre
    jsr screen_put_string_ay
    lda #hal_storage_save_version
    jsr legal_sysinfo_put_hex8
    lda #<legal_sysinfo_fmt_post
    ldy #>legal_sysinfo_fmt_post
    jsr screen_put_string_ay

    // Screen and map geometry
    lda #<legal_sysinfo_lbl_display
    ldy #>legal_sysinfo_lbl_display
    jsr legal_sysinfo_begin_row
    lda #SCREEN_COLS
    jsr screen_put_decimal
    lda #'x'
    jsr hal_screen_put_char
    lda #SCREEN_ROWS
    jsr screen_put_decimal
    lda #<legal_sysinfo_map_sep
    ldy #>legal_sysinfo_map_sep
    jsr screen_put_string_ay
    lda #MAP_COLS
    jsr screen_put_decimal
    lda #'x'
    jsr hal_screen_put_char
    lda #MAP_ROWS
    jsr screen_put_decimal

    // Platform rows
    lda #6
    sta legal_sysinfo_row
    jsr legal_sysinfo_draw_platform

    // Active run telemetry (only when a character is loaded/created)
    lda player_data + PL_LEVEL
    bne !active+
    jmp !footer+
!active:
    inc legal_sysinfo_row

    lda #<legal_sysinfo_lbl_session
    ldy #>legal_sysinfo_lbl_session
    jsr legal_sysinfo_begin_row
    lda #<legal_sysinfo_turn_str
    ldy #>legal_sysinfo_turn_str
    jsr screen_put_string_ay
    lda legal_zp_save + zp_turn_lo - LEGAL_ZP_SNAPSHOT_BASE
    sta zp_temp0
    lda legal_zp_save + zp_turn_hi - LEGAL_ZP_SNAPSHOT_BASE
    sta zp_temp1
    jsr screen_put_decimal_16
    lda legal_zp_save + zp_player_dlvl - LEGAL_ZP_SNAPSHOT_BASE
    bne !in_dungeon+
    lda #<legal_sysinfo_town_str
    ldy #>legal_sysinfo_town_str
    jsr screen_put_string_ay
    jmp !active_row+
!in_dungeon:
    pha
    lda #<legal_sysinfo_dlvl_str
    ldy #>legal_sysinfo_dlvl_str
    jsr screen_put_string_ay
    pla
    jsr screen_put_decimal
    lda #'/'
    jsr hal_screen_put_char
    lda player_data + PL_MAX_DLVL
    jsr screen_put_decimal

!active_row:
    lda #<legal_sysinfo_lbl_active
    ldy #>legal_sysinfo_lbl_active
    jsr legal_sysinfo_begin_row
    lda legal_zp_save + zp_mon_count - LEGAL_ZP_SNAPSHOT_BASE
    jsr screen_put_decimal
    lda #<legal_sysinfo_mon_str
    ldy #>legal_sysinfo_mon_str
    jsr screen_put_string_ay
    lda legal_zp_save + zp_item_count - LEGAL_ZP_SNAPSHOT_BASE
    jsr screen_put_decimal
    lda #<legal_sysinfo_items_str
    ldy #>legal_sysinfo_items_str
    jsr screen_put_string_ay

    lda #<legal_sysinfo_lbl_mode
    ldy #>legal_sysinfo_lbl_mode
    jsr legal_sysinfo_begin_row
    lda legal_zp_save + zp_game_flags - LEGAL_ZP_SNAPSHOT_BASE
    and #GAME_FLAG_WINNER
    beq !chk_wiz+
    lda #<legal_sysinfo_mode_winner
    ldy #>legal_sysinfo_mode_winner
    jsr screen_put_string_ay
    lda legal_zp_save + zp_game_flags - LEGAL_ZP_SNAPSHOT_BASE
    and #GAME_FLAG_WIZARD
    beq !rng_row+
    lda #<legal_sysinfo_mode_plus_wiz
    ldy #>legal_sysinfo_mode_plus_wiz
    jsr screen_put_string_ay
    jmp !rng_row+
!chk_wiz:
    lda legal_zp_save + zp_game_flags - LEGAL_ZP_SNAPSHOT_BASE
    and #GAME_FLAG_WIZARD
    beq !mode_norm+
    lda #<legal_sysinfo_mode_wizard
    ldy #>legal_sysinfo_mode_wizard
    jsr screen_put_string_ay
    jmp !rng_row+
!mode_norm:
    lda #<legal_sysinfo_mode_normal
    ldy #>legal_sysinfo_mode_normal
    jsr screen_put_string_ay

!rng_row:
    lda #<legal_sysinfo_lbl_rng
    ldy #>legal_sysinfo_lbl_rng
    jsr legal_sysinfo_begin_row
    lda #'$'
    jsr hal_screen_put_char
    ldx #0
!rng_loop:
    stx legal_sysinfo_tmp
    lda legal_zp_save + zp_rng_0 - LEGAL_ZP_SNAPSHOT_BASE,x
    jsr legal_sysinfo_put_hex8
    ldx legal_sysinfo_tmp
    inx
    cpx #4
    bcc !rng_loop-

!footer:
    lda #COL_LGREY
    sta zp_text_color
    lda #SCREEN_ROWS - 1
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda legal_entry_mode
    bne !direct_footer+
    lda #<legal_sysinfo_footer_menu
    ldy #>legal_sysinfo_footer_menu
    jmp !draw_footer+
!direct_footer:
    lda #<legal_sysinfo_footer_direct
    ldy #>legal_sysinfo_footer_direct
!draw_footer:
    jsr screen_put_string_ay

legal_sysinfo_wait:
    jsr legal_key
    cmp #$4c                    // L — License & Source menu
    bne !chk_back+
    jmp legal_menu
!chk_back:
    cmp #$51                    // Q — back
    beq !leave+
    cmp #$20                    // Space — back
    beq !leave+
    cmp #$0d                    // Return — back
    beq !leave+
    jsr input_is_modal_escape_key
    bne legal_sysinfo_wait
!leave:
    lda legal_entry_mode
    bne !exit_viewer+
    jmp legal_menu
!exit_viewer:
    jmp legal_return

// Print row label in COL_CYAN at col 1, advance cursor to col 11 in COL_WHITE,
// and increment legal_sysinfo_row.
// Input: A/Y = label string pointer.
legal_sysinfo_begin_row:
    pha
    tya
    pha
    lda legal_sysinfo_row
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #COL_CYAN
    sta zp_text_color
    pla
    tay
    pla
    jsr screen_put_string_ay
    lda #11
    sta zp_cursor_col
    lda #COL_WHITE
    sta zp_text_color
    inc legal_sysinfo_row
    rts

// Print A as two uppercase hexadecimal characters at the cursor.
legal_sysinfo_put_hex8:
    sta legal_sysinfo_hex_byte
    lsr
    lsr
    lsr
    lsr
    jsr legal_sysinfo_put_hex4
    lda legal_sysinfo_hex_byte
    and #$0f
legal_sysinfo_put_hex4:
    cmp #10
    bcc !digit+
    clc
    adc #$37                    // 'A'..'F' ($41..$46)
    jmp hal_screen_put_char
!digit:
    ora #$30                    // '0'..'9' ($30..$39)
    jmp hal_screen_put_char

// Append " (1-drv)" or " (2-drv)" when disk_mode is 1 or 2.
legal_sysinfo_put_disk_mode_suffix:
    lda disk_mode
    beq !done+
    cmp #1
    bne !two+
    lda #<legal_sysinfo_drv1_str
    ldy #>legal_sysinfo_drv1_str
    jmp screen_put_string_ay
!two:
    lda #<legal_sysinfo_drv2_str
    ldy #>legal_sysinfo_drv2_str
    jmp screen_put_string_ay
!done:
    rts

// Print "P#<prog>  S#<save>" + disk_mode suffix (for standard device-number ports).
legal_sysinfo_put_drive_pair:
    lda #<legal_sysinfo_p_hash_str
    ldy #>legal_sysinfo_p_hash_str
    jsr screen_put_string_ay
    lda program_device
    jsr screen_put_decimal
    lda #<legal_sysinfo_s_hash_str
    ldy #>legal_sysinfo_s_hash_str
    jsr screen_put_string_ay
    lda save_device
    jsr screen_put_decimal
    jmp legal_sysinfo_put_disk_mode_suffix

// Print standard Last I/O diagnostic summary ("OK" or "Err $XX St $YY P$ZZ").
legal_sysinfo_put_last_io_common:
    lda hal_storage_diag_code
    ora hal_storage_diag_readst
    bne !err+
    lda #<legal_sysinfo_ok_str
    ldy #>legal_sysinfo_ok_str
    jmp screen_put_string_ay
!err:
    lda #<legal_sysinfo_err_pre
    ldy #>legal_sysinfo_err_pre
    jsr screen_put_string_ay
    lda hal_storage_diag_code
    jsr legal_sysinfo_put_hex8
    lda #<legal_sysinfo_st_pre
    ldy #>legal_sysinfo_st_pre
    jsr screen_put_string_ay
    lda hal_storage_diag_readst
    jsr legal_sysinfo_put_hex8
    lda #<legal_sysinfo_phase_pre
    ldy #>legal_sysinfo_phase_pre
    jsr screen_put_string_ay
    lda hal_storage_diag_phase
    jmp legal_sysinfo_put_hex8

legal_sysinfo_row:      .byte 0
legal_sysinfo_tmp:      .byte 0
legal_sysinfo_hex_byte: .byte 0

legal_sysinfo_heading:      .text "Moria 8 - System Info"; .byte 0
legal_sysinfo_version_str:
    :EmitTitleVersion()
    .byte 0

legal_sysinfo_lbl_version:  .text "Version:"; .byte 0
legal_sysinfo_lbl_format:   .text "Format:"; .byte 0
legal_sysinfo_lbl_display:  .text "Display:"; .byte 0
legal_sysinfo_lbl_session:  .text "Session:"; .byte 0
legal_sysinfo_lbl_active:   .text "Active:"; .byte 0
legal_sysinfo_lbl_mode:     .text "Mode:"; .byte 0
legal_sysinfo_lbl_rng:      .text "RNG:"; .byte 0

legal_sysinfo_fmt_pre:      .text "Save V2 ($"; .byte 0
legal_sysinfo_fmt_post:     .text ")  279m/361i"; .byte 0
legal_sysinfo_map_sep:      .text "  Map: "; .byte 0
legal_sysinfo_turn_str:     .text "Turn "; .byte 0
legal_sysinfo_town_str:     .text "  Town"; .byte 0
legal_sysinfo_dlvl_str:     .text "  Dlvl "; .byte 0
legal_sysinfo_mon_str:      .text " mon, "; .byte 0
legal_sysinfo_items_str:    .text " items"; .byte 0
legal_sysinfo_mode_normal:  .text "Normal"; .byte 0
legal_sysinfo_mode_wizard:  .text "Wizard"; .byte 0
legal_sysinfo_mode_winner:  .text "Winner"; .byte 0
legal_sysinfo_mode_plus_wiz:.text " + Wiz"; .byte 0

legal_sysinfo_drv1_str:     .text " (1-drv)"; .byte 0
legal_sysinfo_drv2_str:     .text " (2-drv)"; .byte 0
legal_sysinfo_p_hash_str:   .text "P#"; .byte 0
legal_sysinfo_s_hash_str:   .text "  S#"; .byte 0
legal_sysinfo_ok_str:       .text "OK"; .byte 0
legal_sysinfo_err_pre:      .text "Err $"; .byte 0
legal_sysinfo_st_pre:       .text " St $"; .byte 0
legal_sysinfo_phase_pre:    .text " P$"; .byte 0

legal_sysinfo_footer_menu:   .text "L: License menu  Q/Space: back"; .byte 0
legal_sysinfo_footer_direct: .text "L: License  Q/Esc/Space: back"; .byte 0
