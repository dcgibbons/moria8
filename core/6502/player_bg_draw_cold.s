#importonce
// player_bg_draw_cold.s — Character sheet sex, social class, and background renderer
//
// Module ownership:
//   owner: UiOverlay when UI_CHAR_BG_EXTERNAL is defined; Default resident
//     otherwise (imported by core/player.s).
//   lifetime: one character-sheet view (post-chargen summary or 'C' modal).
//   callers: ui_char_display (core/ui_character.s in UiOverlay) exclusively.

// Character sheet strings
char_sex_label:
    .text "Sex: " ; .byte 0
char_sex_male:
    .text "Male" ; .byte 0
char_sex_female:
    .text "Female" ; .byte 0
char_sc_label:
    .text "  SC: " ; .byte 0

.const UDBG_COL = hal_layout_character_background_col

// ui_char_draw_background — Draw sex, social class, background on char sheet
// Renders rows 12-16 of the character sheet.
// Preserves: nothing
ui_char_draw_background:
#if HAL_PLATFORM_CHARACTER_BACKGROUND_RESYNC
    jsr hal_platform_runtime_resync
#endif
    // --- Sex / Social Class (row 12) ---
    lda #12
    sta zp_cursor_row
    lda #UDBG_COL
    sta zp_cursor_col
    lda #COL_LGREY
    sta zp_text_color
    lda #<char_sex_label
    ldy #>char_sex_label
    jsr screen_put_string_ay

    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_FLAGS
    and #PLF_MALE
    beq !udb_female+
    lda #<char_sex_male
    sta zp_ptr0
    lda #>char_sex_male
    sta zp_ptr0_hi
    jmp !udb_print_sex+
!udb_female:
    lda #<char_sex_female
    sta zp_ptr0
    lda #>char_sex_female
    sta zp_ptr0_hi
!udb_print_sex:
    jsr hal_screen_put_string

    lda #COL_LGREY
    sta zp_text_color
    lda #<char_sc_label
    ldy #>char_sc_label
    jsr screen_put_string_ay
    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_SOCIAL_CLASS
    jsr screen_put_decimal

    // --- Background text (rows 13-16) ---
    lda #COL_LGREY
    sta zp_text_color
    ldx #0
!udb_line_loop:
    txa
    pha
    clc
    adc #13
    sta zp_cursor_row
    lda #UDBG_COL
    sta zp_cursor_col
    pla
    tax
    pha
    lda udb_line_lo,x
    sta zp_ptr0
    lda udb_line_hi,x
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    pla
    tax
    inx
    cpx #4
    bcc !udb_line_loop-
    rts

// Background line pointer lookup table
udb_line_lo:
    .byte <player_background, <(player_background + 40)
    .byte <(player_background + 80), <(player_background + 120)
udb_line_hi:
    .byte >player_background, >(player_background + 40)
    .byte >(player_background + 80), >(player_background + 120)
