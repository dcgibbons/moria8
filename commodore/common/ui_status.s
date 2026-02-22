// ui_status.s — Bottom status bar rendering (umoria-style, 3 lines)
//
// Three-line status bar at rows 21–23:
//   Row 21: Name, Race, Level, Dungeon Level
//   Row 22: ST:nn IN:nn WI:nn DX:nn CO:nn CH:nn
//   Row 23: HP:nn/nn MP:nn/nn AC:nn AU:nnnnn HUNGRY
//
// Only redraws when zp_ui_dirty bit 0 is set (dirty flag).

// ============================================================
// Subroutines
// ============================================================

// status_draw — Redraw the full status bar (3 rows)
// Preserves: nothing
status_draw:
    // Save cursor state
    lda zp_cursor_row
    pha
    lda zp_cursor_col
    pha
    lda zp_text_color
    pha

    // Clear input row (row 24) — many code paths bypass vp_render_status_loop
    lda #INPUT_ROW
    jsr screen_clear_row

    // ========== Row 21: Name / Race / Level / Dungeon Level ==========
    lda #STATUS_ROW
    jsr screen_clear_row
    lda #STATUS_ROW
    sta zp_cursor_row

    // Player name
    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_col
    lda #<(player_data + PL_NAME)
    sta zp_ptr0
    lda #>(player_data + PL_NAME)
    sta zp_ptr0_hi
    jsr screen_put_string

    // Space separator
    lda #$20
    jsr screen_put_char

    // Race name
    lda #COL_STATUS
    sta zp_text_color
    ldx zp_player_race
    lda race_name_ptrs_lo,x
    sta zp_ptr0
    lda race_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string

    // "LV:" at col 28
    lda #28
    sta zp_cursor_col
    lda #<status_lv_str
    sta zp_ptr0
    lda #>status_lv_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda zp_player_lvl
    jsr screen_put_decimal

    // "DL:" at col 34
    lda #COL_STATUS
    sta zp_text_color
    lda #34
    sta zp_cursor_col
    lda #<status_dl_str
    sta zp_ptr0
    lda #>status_dl_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda zp_player_dlvl
    jsr screen_put_decimal

    // ========== Row 22: All 6 stats ==========
    lda #STATUS_ROW + 1
    jsr screen_clear_row
    lda #STATUS_ROW + 1
    sta zp_cursor_row
    lda #COL_STATUS
    sta zp_text_color

    // ST: at col 0
    lda #0
    sta zp_cursor_col
    lda #<stat_st_str
    sta zp_ptr0
    lda #>stat_st_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #COL_WHITE
    sta zp_text_color
    lda zp_player_str
    jsr status_put_stat_val

    // IN: at col 7
    lda #COL_STATUS
    sta zp_text_color
    lda #7
    sta zp_cursor_col
    lda #<stat_in_str
    sta zp_ptr0
    lda #>stat_in_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #COL_WHITE
    sta zp_text_color
    lda zp_player_int
    jsr status_put_stat_val

    // WI: at col 14
    lda #COL_STATUS
    sta zp_text_color
    lda #14
    sta zp_cursor_col
    lda #<stat_wi_str
    sta zp_ptr0
    lda #>stat_wi_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #COL_WHITE
    sta zp_text_color
    lda zp_player_wis
    jsr status_put_stat_val

    // DX: at col 21
    lda #COL_STATUS
    sta zp_text_color
    lda #21
    sta zp_cursor_col
    lda #<stat_dx_str
    sta zp_ptr0
    lda #>stat_dx_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #COL_WHITE
    sta zp_text_color
    lda zp_player_dex
    jsr status_put_stat_val

    // CO: at col 28
    lda #COL_STATUS
    sta zp_text_color
    lda #28
    sta zp_cursor_col
    lda #<stat_co_str
    sta zp_ptr0
    lda #>stat_co_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #COL_WHITE
    sta zp_text_color
    lda zp_player_con
    jsr status_put_stat_val

    // CH: at col 35
    lda #COL_STATUS
    sta zp_text_color
    lda #35
    sta zp_cursor_col
    lda #<stat_ch_str
    sta zp_ptr0
    lda #>stat_ch_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #COL_WHITE
    sta zp_text_color
    lda zp_player_chr
    jsr status_put_stat_val

    // ========== Row 23: HP / MP / AC / Gold / Hunger ==========
    lda #STATUS_ROW + 2
    jsr screen_clear_row
    lda #STATUS_ROW + 2
    sta zp_cursor_row
    lda #COL_STATUS
    sta zp_text_color

    // "HP:" at col 0
    lda #0
    sta zp_cursor_col
    lda #<status_hp_str
    sta zp_ptr0
    lda #>status_hp_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Color HP by percentage
    jsr status_hp_color

    // Current HP (16-bit)
    lda zp_player_hp_lo
    sta zp_temp0
    lda zp_player_hp_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    // "/"
    lda #COL_STATUS
    sta zp_text_color
    lda #$2f
    jsr screen_put_char

    // Max HP
    lda zp_player_mhp_lo
    sta zp_temp0
    lda zp_player_mhp_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    // "MP:" at col 10
    lda #COL_STATUS
    sta zp_text_color
    lda #10
    sta zp_cursor_col
    lda #<status_mp_str
    sta zp_ptr0
    lda #>status_mp_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda zp_player_mp
    jsr screen_put_decimal
    lda #COL_STATUS
    sta zp_text_color
    lda #$2f
    jsr screen_put_char
    lda #COL_WHITE
    sta zp_text_color
    lda zp_player_mmp
    jsr screen_put_decimal

    // "AC:" at col 19
    lda #COL_STATUS
    sta zp_text_color
    lda #19
    sta zp_cursor_col
    lda #<status_ac_str
    sta zp_ptr0
    lda #>status_ac_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda zp_player_ac
    jsr screen_put_decimal

    // "AU:" at col 25
    lda #COL_YELLOW
    sta zp_text_color
    lda #25
    sta zp_cursor_col
    lda #<status_au_str
    sta zp_ptr0
    lda #>status_au_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda player_data + PL_GOLD_0
    sta zp_temp0
    lda player_data + PL_GOLD_1
    sta zp_temp1
    jsr screen_put_decimal_16

    // Hunger state at col 34
    lda #34
    sta zp_cursor_col
    // Color-code hunger
    lda zp_hunger_state
    cmp #HUNGER_FULL
    beq !hunger_ok+
    cmp #HUNGER_HUNGRY
    beq !hunger_warn+
    // Weak or faint
    lda #COL_RED
    sta zp_text_color
    jmp !hunger_print+
!hunger_warn:
    lda #COL_YELLOW
    sta zp_text_color
    jmp !hunger_print+
!hunger_ok:
    lda #COL_STATUS
    sta zp_text_color
!hunger_print:
    lda zp_hunger_state
    tax
    lda hunger_name_ptrs_lo,x
    sta zp_ptr0
    lda hunger_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string

    // Clear dirty flag
    lda zp_ui_dirty
    and #%11111110
    sta zp_ui_dirty

    // Restore cursor state
    pla
    sta zp_text_color
    pla
    sta zp_cursor_col
    pla
    sta zp_cursor_row
    rts

// status_put_stat_val — Display stat value for status bar (cap 18/xx to 18)
// Input: A = stat value (3-118)
// Output: prints right-justified 2-char number
status_put_stat_val:
    cmp #19
    bcc !sv_normal+
    lda #18                 // 18/xx → show 18
!sv_normal:
    jsr screen_put_decimal_rj2
    rts

// status_hp_color — Set text color based on HP percentage
// Preserves: nothing (sets zp_text_color)
status_hp_color:
    // Simple comparison: if HP >= MHP, green. If HP >= MHP/2, yellow. Else red.
    lda zp_player_hp_hi
    cmp zp_player_mhp_hi
    bcc !check_half+
    bne !full+
    lda zp_player_hp_lo
    cmp zp_player_mhp_lo
    bcc !check_half+
!full:
    lda #COL_HP_OK
    sta zp_text_color
    rts
!check_half:
    // HP < max. Check if >= max/2
    lda zp_player_mhp_hi
    lsr
    sta zp_temp0
    lda zp_player_mhp_lo
    ror
    sta zp_temp1
    lda zp_player_hp_hi
    cmp zp_temp0
    bcc !critical+
    bne !warn+
    lda zp_player_hp_lo
    cmp zp_temp1
    bcc !critical+
!warn:
    lda #COL_HP_WARN
    sta zp_text_color
    rts
!critical:
    lda #COL_HP_CRIT
    sta zp_text_color
    rts

// status_mark_dirty — Set the status bar dirty flag
// Preserves: A, X, Y
status_mark_dirty:
    pha
    lda zp_ui_dirty
    ora #$01
    sta zp_ui_dirty
    pla
    rts

// ============================================================
// String data (screen codes, null-terminated)
// ============================================================
status_lv_str:
    .text "LV:" ; .byte $00
status_dl_str:
    .text "DL:" ; .byte $00
stat_st_str:
    .text "ST:" ; .byte $00
stat_in_str:
    .text "IN:" ; .byte $00
stat_wi_str:
    .text "WI:" ; .byte $00
stat_dx_str:
    .text "DX:" ; .byte $00
stat_co_str:
    .text "CO:" ; .byte $00
stat_ch_str:
    .text "CH:" ; .byte $00
status_hp_str:
    .text "HP:" ; .byte $00
status_mp_str:
    .text "MP:" ; .byte $00
status_ac_str:
    .text "AC:" ; .byte $00
status_au_str:
    .text "AU:" ; .byte $00
status_exp_str:
    .text "EXP:" ; .byte $00
