#importonce
// ui_status.s — Bottom status bar rendering (umoria-style, 3 lines)
//
// Three-line status bar at rows 21–23:
//   Row 21: Name, Race, Level, Dungeon Level
//   Row 22: ST:nn IN:nn WI:nn DX:nn CO:nn CH:nn
//   Row 23: HP:nn/nn MP:nn/nn AC:nn AU:nnnnn HUNGRY
//
// Only redraws when zp_ui_dirty bit 0 is set (dirty flag).

#if C128
.const STS_ROW21_NAME_COL = 1
.const STS_ROW21_LV_COL = 58
.const STS_ROW21_DL_COL = 66
.const STS_ROW22_ST_COL = 1
.const STS_ROW22_IN_COL = 14
.const STS_ROW22_WI_COL = 27
.const STS_ROW22_DX_COL = 40
.const STS_ROW22_CO_COL = 53
.const STS_ROW22_CH_COL = 66
.const STS_ROW23_HP_COL = 1
.const STS_ROW23_MP_COL = 16
.const STS_ROW23_AC_COL = 31
.const STS_ROW23_AU_COL = 44
.const STS_ROW23_HUNGER_COL = 63
#else
.const STS_ROW21_NAME_COL = 0
.const STS_ROW21_LV_COL = 28
.const STS_ROW21_DL_COL = 34
.const STS_ROW22_ST_COL = 0
.const STS_ROW22_IN_COL = 7
.const STS_ROW22_WI_COL = 14
.const STS_ROW22_DX_COL = 21
.const STS_ROW22_CO_COL = 28
.const STS_ROW22_CH_COL = 35
.const STS_ROW23_HP_COL = 0
.const STS_ROW23_MP_COL = 10
.const STS_ROW23_AC_COL = 19
.const STS_ROW23_AU_COL = 25
.const STS_ROW23_HUNGER_COL = 34
#endif

// ============================================================
// Subroutines
// ============================================================

// status_draw — Redraw the full status bar (3 rows)
// Preserves: nothing
status_draw:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$24
    jsr c128_town_dump_log
#endif
#if C128_STATUS_SP_CANARY_DIAG
    // Snapshot the live RTS target so we can catch direct corruption of
    // status_draw's return slot even when SP itself stays balanced.
    tsx
    lda $0101,x
    sta c128_status_ret_expected_lo
    lda $0102,x
    sta c128_status_ret_expected_hi
#endif
    // Dirty row bitmask in status_dirty_rows:
    // bit0=row21, bit1=row22, bit2=row23
    lda #$07
    sta status_dirty_rows

    // Cold-start: no cache means draw all three rows.
    lda status_cache_valid
    bne !sd_check+
    jmp !sd_draw+
!sd_check:

    // Cache valid: build per-row dirty mask.
    lda #$00
    sta status_dirty_rows

    // Row 21: LV / DL
    lda zp_player_lvl
    cmp status_prev_lvl
    bne !sd_row21_dirty+
    lda zp_player_dlvl
    cmp status_prev_dlvl
    bne !sd_row21_dirty+
    jmp !sd_check_row22+
!sd_row21_dirty:
    lda status_dirty_rows
    ora #$01
    sta status_dirty_rows

!sd_check_row22:
    // Row 22: stats
    lda zp_player_str
    cmp status_prev_str
    bne !sd_row22_dirty+
    lda zp_player_int
    cmp status_prev_int
    bne !sd_row22_dirty+
    lda zp_player_wis
    cmp status_prev_wis
    bne !sd_row22_dirty+
    lda zp_player_dex
    cmp status_prev_dex
    bne !sd_row22_dirty+
    lda zp_player_con
    cmp status_prev_con
    bne !sd_row22_dirty+
    lda zp_player_chr
    cmp status_prev_chr
    bne !sd_row22_dirty+
    jmp !sd_check_row23+
!sd_row22_dirty:
    lda status_dirty_rows
    ora #$02
    sta status_dirty_rows

!sd_check_row23:
    // Row 23: HP / MP / AC / AU / hunger
    lda zp_player_hp_lo
    cmp status_prev_hp_lo
    bne !sd_row23_dirty+
    lda zp_player_hp_hi
    cmp status_prev_hp_hi
    bne !sd_row23_dirty+
    lda zp_player_mhp_lo
    cmp status_prev_mhp_lo
    bne !sd_row23_dirty+
    lda zp_player_mhp_hi
    cmp status_prev_mhp_hi
    bne !sd_row23_dirty+

    lda zp_player_mp
    cmp status_prev_mp
    bne !sd_row23_dirty+
    lda zp_player_mmp
    cmp status_prev_mmp
    bne !sd_row23_dirty+
    lda zp_player_ac
    cmp status_prev_ac
    bne !sd_row23_dirty+

    lda player_data + PL_GOLD_0
    cmp status_prev_gold_lo
    bne !sd_row23_dirty+
    lda player_data + PL_GOLD_1
    cmp status_prev_gold_hi
    bne !sd_row23_dirty+

    lda zp_hunger_state
    cmp status_prev_hunger
    bne !sd_row23_dirty+
    jmp !sd_dirty_ready+
!sd_row23_dirty:
    lda status_dirty_rows
    ora #$04
    sta status_dirty_rows

!sd_dirty_ready:
    // Any visible change redraws the full 3-line status block.
    // Row-level partial redraw proved invalid because other flows may clear
    // status lines independently; keep bar updates atomic.
    lda status_dirty_rows
    beq !sd_no_change+
    lda #$07
    sta status_dirty_rows
    jmp !sd_draw+
!sd_no_change:
    // No visible status changes: either force redraw (bit7) or clear dirty and return.
    lda zp_ui_dirty
    and #%10000000
    beq !sd_no_force+
    lda #$07
    sta status_dirty_rows
    jmp !sd_draw+
!sd_no_force:
    jmp !sd_clear_dirty_only+

!sd_draw:
    // Save cursor state
    lda zp_cursor_row
    pha
    lda zp_cursor_col
    pha
    lda zp_text_color
    pha

    // Clear the full 3-line status block before redrawing it. Several
    // numeric fields are variable-width, so redraw without a clear can leave
    // stale trailing digits behind (for example 21 -> 211).
    ldx #STATUS_ROW
!sd_clear_rows:
    txa
    jsr screen_clear_row
    inx
    cpx #STATUS_ROW + 3
    bne !sd_clear_rows-

    // Clear input row (row 24) — many code paths bypass vp_render_status_loop
    lda #INPUT_ROW
    jsr screen_clear_row

    // ========== Row 21: Name / Race / Level / Dungeon Level ==========
    lda status_dirty_rows
    and #$01
    bne !sd_row21_draw+
    jmp !sd_row22+
!sd_row21_draw:
    lda #STATUS_ROW
    sta zp_cursor_row

    // Player name
    lda #COL_WHITE
    sta zp_text_color
    lda #STS_ROW21_NAME_COL
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

    lda #STS_ROW21_LV_COL
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

    // "DL:"
    lda #COL_STATUS
    sta zp_text_color
    lda #STS_ROW21_DL_COL
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

!sd_row22:
    // ========== Row 22: All 6 stats ==========
    lda status_dirty_rows
    and #$02
    bne !sd_row22_draw+
    jmp !sd_row23+
!sd_row22_draw:
    lda #STATUS_ROW + 1
    sta zp_cursor_row
    lda #COL_STATUS
    sta zp_text_color

    lda #STS_ROW22_ST_COL
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

    // IN:
    lda #COL_STATUS
    sta zp_text_color
    lda #STS_ROW22_IN_COL
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

    // WI:
    lda #COL_STATUS
    sta zp_text_color
    lda #STS_ROW22_WI_COL
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

    // DX:
    lda #COL_STATUS
    sta zp_text_color
    lda #STS_ROW22_DX_COL
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

    // CO:
    lda #COL_STATUS
    sta zp_text_color
    lda #STS_ROW22_CO_COL
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

    // CH:
    lda #COL_STATUS
    sta zp_text_color
    lda #STS_ROW22_CH_COL
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

!sd_row23:
    // ========== Row 23: HP / MP / AC / Gold / Hunger ==========
    lda status_dirty_rows
    and #$04
    bne !sd_row23_draw+
    jmp !sd_update_cache+
!sd_row23_draw:
    lda #STATUS_ROW + 2
    sta zp_cursor_row
    lda #COL_STATUS
    sta zp_text_color

    lda #STS_ROW23_HP_COL
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

    // "MP:"
    lda #COL_STATUS
    sta zp_text_color
    lda #STS_ROW23_MP_COL
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

    // "AC:"
    lda #COL_STATUS
    sta zp_text_color
    lda #STS_ROW23_AC_COL
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

    // "AU:"
    lda #COL_YELLOW
    sta zp_text_color
    lda #STS_ROW23_AU_COL
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

    lda #STS_ROW23_HUNGER_COL
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

!sd_update_cache:
    // Update status cache after successful redraw.
    lda zp_player_lvl
    sta status_prev_lvl
    lda zp_player_dlvl
    sta status_prev_dlvl

    lda zp_player_str
    sta status_prev_str
    lda zp_player_int
    sta status_prev_int
    lda zp_player_wis
    sta status_prev_wis
    lda zp_player_dex
    sta status_prev_dex
    lda zp_player_con
    sta status_prev_con
    lda zp_player_chr
    sta status_prev_chr

    lda zp_player_hp_lo
    sta status_prev_hp_lo
    lda zp_player_hp_hi
    sta status_prev_hp_hi
    lda zp_player_mhp_lo
    sta status_prev_mhp_lo
    lda zp_player_mhp_hi
    sta status_prev_mhp_hi

    lda zp_player_mp
    sta status_prev_mp
    lda zp_player_mmp
    sta status_prev_mmp
    lda zp_player_ac
    sta status_prev_ac

    lda player_data + PL_GOLD_0
    sta status_prev_gold_lo
    lda player_data + PL_GOLD_1
    sta status_prev_gold_hi

    lda zp_hunger_state
    sta status_prev_hunger
    lda #1
    sta status_cache_valid

!sd_clear_dirty:
    // Clear dirty flag
    lda zp_ui_dirty
    and #%01111110          // clear bit0 (status dirty) and bit7 (force redraw)
    sta zp_ui_dirty

    // Restore cursor state.
    pla
    sta zp_text_color
    pla
    sta zp_cursor_col
    pla
    sta zp_cursor_row
!sd_done:
#if C128_STATUS_SP_CANARY_DIAG
    tsx
    lda $0101,x
    sta c128_status_ret_actual_lo
    cmp c128_status_ret_expected_lo
    bne !sd_ret_corrupt+
    lda $0102,x
    sta c128_status_ret_actual_hi
    cmp c128_status_ret_expected_hi
    bne !sd_ret_corrupt+
#endif
    rts

#if C128_STATUS_SP_CANARY_DIAG
!sd_ret_corrupt:
    lda #$e2
    sta c128_stack_guard_fail_code
    jmp c128_status_ret_corrupt
#endif

!sd_clear_dirty_only:
    // No drawing happened; only clear dirty flag.
    lda zp_ui_dirty
    and #%01111110          // clear bit0 (status dirty) and bit7 (force redraw)
    sta zp_ui_dirty
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

// ============================================================
// Status cache (skip redraw when visible values are unchanged)
// ============================================================
status_cache_valid: .byte 0
status_prev_lvl:    .byte 0
status_prev_dlvl:   .byte 0
status_prev_str:    .byte 0
status_prev_int:    .byte 0
status_prev_wis:    .byte 0
status_prev_dex:    .byte 0
status_prev_con:    .byte 0
status_prev_chr:    .byte 0
status_prev_hp_lo:  .byte 0
status_prev_hp_hi:  .byte 0
status_prev_mhp_lo: .byte 0
status_prev_mhp_hi: .byte 0
status_prev_mp:     .byte 0
status_prev_mmp:    .byte 0
status_prev_ac:     .byte 0
status_prev_gold_lo:.byte 0
status_prev_gold_hi:.byte 0
status_prev_hunger: .byte 0
status_dirty_rows:  .byte 0
