// ui_status.s — Bottom status bar rendering
//
// Two-line status bar at rows 21–22:
//   Row 21: "MORIA  DLVL:nn  HP:nnn/nnn  MP:nn/nn"
//   Row 22: "STR:nn  AC:nn  EXP:nnnnn   HUNGRY"
//
// Only redraws when zp_ui_dirty bit 0 is set (dirty flag).

// ============================================================
// Subroutines
// ============================================================

// status_draw — Redraw the full status bar
// Preserves: nothing
status_draw:
    // Save cursor state
    lda zp_cursor_row
    pha
    lda zp_cursor_col
    pha
    lda zp_text_color
    pha

    lda #COL_STATUS
    sta zp_text_color

    // --- Row 21 ---
    lda #STATUS_ROW
    jsr screen_clear_row

    // "MORIA"
    lda #STATUS_ROW
    sta zp_cursor_row
    lda #0
    sta zp_cursor_col
    lda #<status_moria_str
    sta zp_ptr0
    lda #>status_moria_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // "DLVL:"
    lda #7
    sta zp_cursor_col
    lda #<status_dlvl_str
    sta zp_ptr0
    lda #>status_dlvl_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Dungeon level number
    lda zp_player_dlvl
    jsr screen_put_decimal

    // "HP:"
    lda #16
    sta zp_cursor_col
    lda #<status_hp_str
    sta zp_ptr0
    lda #>status_hp_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Color HP by percentage
    jsr status_hp_color

    // Current HP
    lda zp_player_hp_lo
    sta zp_temp0
    lda zp_player_hp_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    // "/"
    lda #COL_STATUS
    sta zp_text_color
    lda #$2f                // '/'
    jsr screen_put_char

    // Max HP
    lda zp_player_mhp_lo
    sta zp_temp0
    lda zp_player_mhp_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    // "MP:"
    lda #29
    sta zp_cursor_col
    lda #<status_mp_str
    sta zp_ptr0
    lda #>status_mp_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Current mana
    lda zp_player_mp
    jsr screen_put_decimal

    lda #$2f                // '/'
    jsr screen_put_char

    // Max mana
    lda zp_player_mmp
    jsr screen_put_decimal

    // --- Row 22 ---
    lda #STATUS_ROW + 1
    jsr screen_clear_row

    lda #COL_STATUS
    sta zp_text_color
    lda #STATUS_ROW + 1
    sta zp_cursor_row

    // "STR:"
    lda #0
    sta zp_cursor_col
    lda #<status_str_str
    sta zp_ptr0
    lda #>status_str_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda zp_player_str
    jsr screen_put_decimal

    // "AC:"
    lda #8
    sta zp_cursor_col
    lda #<status_ac_str
    sta zp_ptr0
    lda #>status_ac_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda zp_player_ac
    jsr screen_put_decimal

    // "AU:"
    lda #15
    sta zp_cursor_col
    lda #<status_au_str
    sta zp_ptr0
    lda #>status_au_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Gold (16-bit for now, low 2 bytes of 24-bit)
    lda player_data + PL_GOLD_0
    sta zp_temp0
    lda player_data + PL_GOLD_1
    sta zp_temp1
    jsr screen_put_decimal_16

    // Hunger state
    lda #28
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
    and #%11111110          // Clear bit 0
    sta zp_ui_dirty

    // Restore cursor state
    pla
    sta zp_text_color
    pla
    sta zp_cursor_col
    pla
    sta zp_cursor_row
    rts

// status_hp_color — Set text color based on HP percentage
// Preserves: nothing (sets zp_text_color)
status_hp_color:
    // Simple comparison: if HP >= MHP, green. If HP >= MHP/2, yellow. Else red.
    // Compare current HP to max HP
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
    sta zp_temp0            // max_hi / 2
    lda zp_player_mhp_lo
    ror
    sta zp_temp1            // max_lo / 2 (with carry from hi)
    // Compare HP to max/2
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
status_moria_str:
    .text "MORIA" ; .byte $20, $00
status_dlvl_str:
    .text "DLVL:" ; .byte $00
status_hp_str:
    .text "HP:" ; .byte $00
status_mp_str:
    .text "MP:" ; .byte $00
status_str_str:
    .text "STR:" ; .byte $00
status_ac_str:
    .text "AC:" ; .byte $00
status_au_str:
    .text "AU:" ; .byte $00
status_exp_str:
    .text "EXP:" ; .byte $00
