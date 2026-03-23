#importonce
// ui_character.s — Character sheet display
//
// Shows full character info on screen. Called from character
// creation and via the 'C' command during gameplay.
//
// Layout (40 columns):
//   Row 0:  CHARACTER INFO
//   Row 2:  Name: PLAYERNAMEXXX
//   Row 3:  Race: HALF-ELF     Class: MAGE
//   Row 4:  Level: 1           AC: 10
//   Row 6:  STR: 16   INT: 12   WIS: 10
//   Row 7:  DEX: 14   CON: 13   CHR: 11
//   Row 9:  HP: 8/8   Mana: 4/4
//   Row 10: Gold: 200    XP: 0
//   Row 12: Depth: Town   Hunger: Full
//   Row 14: [PRESS ANY KEY]

#if C128
.const UCHAR_TITLE_COL = (SCREEN_COLS - 14) / 2
.const UCHAR_WIZARD_COL = SCREEN_COLS - 9
.const UCHAR_FOOTER_COL = (SCREEN_COLS - 13) / 2
.const UCHAR_COL_L = (SCREEN_COLS - 36) / 2
.const UCHAR_COL_NAME = UCHAR_COL_L + 6
.const UCHAR_COL_MID = UCHAR_COL_L + 17
.const UCHAR_COL_R = UCHAR_COL_L + 21
.const UCHAR_STAT_COL0 = UCHAR_COL_L
.const UCHAR_STAT_COL1 = UCHAR_COL_L + 13
.const UCHAR_STAT_COL2 = UCHAR_COL_L + 26
#else
.const UCHAR_TITLE_COL = 12
.const UCHAR_WIZARD_COL = 32
.const UCHAR_FOOTER_COL = 10
.const UCHAR_COL_L = 1
.const UCHAR_COL_NAME = 7
.const UCHAR_COL_MID = 18
.const UCHAR_COL_R = 22
.const UCHAR_STAT_COL0 = 1
.const UCHAR_STAT_COL1 = 14
.const UCHAR_STAT_COL2 = 27
#endif

// ============================================================
// Subroutines
// ============================================================

// ui_char_display — Show character sheet
// Preserves: nothing
ui_char_display:
#if C128
    jsr c128_restore_runtime_guards
#if C128_TEST_SCRIPTED_INPUT
    lda #1
    sta c128_test_summary_seen
#elif C128_TEST_CACHE_SURVIVAL
    lda #1
    sta c128_test_summary_seen
#endif
#endif
    lda #COL_WHITE
    sta zp_text_color
    jsr ui_help_clear_all       // Clear row by row (same as help/inventory)

    // Title
    lda #0
    sta zp_cursor_row
    lda #UCHAR_TITLE_COL
    sta zp_cursor_col
    lda #<char_title_str
    sta zp_ptr0
    lda #>char_title_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    beq !ucd_not_wizard+
    lda #COL_YELLOW
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    lda #UCHAR_WIZARD_COL
    sta zp_cursor_col
    lda #<char_wizard_str
    sta zp_ptr0
    lda #>char_wizard_str
    sta zp_ptr0_hi
    jsr screen_put_string
!ucd_not_wizard:

    lda #COL_LGREY
    sta zp_text_color

    // --- Name ---
    lda #2
    sta zp_cursor_row
    lda #UCHAR_COL_L
    sta zp_cursor_col
    lda #<char_name_label
    sta zp_ptr0
    lda #>char_name_label
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda #UCHAR_COL_NAME
    sta zp_cursor_col
    lda #<(player_data + PL_NAME)
    sta zp_ptr0
    lda #>(player_data + PL_NAME)
    sta zp_ptr0_hi
    jsr screen_put_string

    // --- Race / Class ---
    lda #COL_LGREY
    sta zp_text_color
    lda #3
    sta zp_cursor_row
    lda #UCHAR_COL_L
    sta zp_cursor_col
    lda #<char_race_label
    sta zp_ptr0
    lda #>char_race_label
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    ldx player_data + PL_RACE
    lda race_name_ptrs_lo,x
    sta zp_ptr0
    lda race_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_LGREY
    sta zp_text_color
    lda #UCHAR_COL_R
    sta zp_cursor_col
    lda #<char_class_label
    sta zp_ptr0
    lda #>char_class_label
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    ldx player_data + PL_CLASS
    lda class_name_ptrs_lo,x
    sta zp_ptr0
    lda class_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string

    // --- Level / AC ---
    lda #COL_LGREY
    sta zp_text_color
    lda #4
    sta zp_cursor_row
    lda #UCHAR_COL_L
    sta zp_cursor_col
    lda #<char_level_label
    sta zp_ptr0
    lda #>char_level_label
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_LEVEL
    jsr screen_put_decimal

    lda #COL_LGREY
    sta zp_text_color
    lda #UCHAR_COL_R
    sta zp_cursor_col
    lda #<status_ac_str
    sta zp_ptr0
    lda #>status_ac_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_AC
    jsr screen_put_decimal

    // --- Stats (row 6-7) ---
    jsr ui_char_draw_stats

    // --- HP / Mana (row 9) ---
    lda #COL_LGREY
    sta zp_text_color
    lda #9
    sta zp_cursor_row
    lda #UCHAR_COL_L
    sta zp_cursor_col
    lda #<status_hp_str
    sta zp_ptr0
    lda #>status_hp_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_HP_LO
    sta zp_temp0
    lda player_data + PL_HP_HI
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #$2f                // '/'
    jsr screen_put_char
    lda player_data + PL_MHP_LO
    sta zp_temp0
    lda player_data + PL_MHP_HI
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_LGREY
    sta zp_text_color
    lda #UCHAR_COL_MID
    sta zp_cursor_col
    lda #<char_mana_label
    sta zp_ptr0
    lda #>char_mana_label
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_MANA
    jsr screen_put_decimal
    lda #$2f
    jsr screen_put_char
    lda player_data + PL_MAX_MANA
    jsr screen_put_decimal

    // --- Gold / XP (row 10) ---
    lda #COL_LGREY
    sta zp_text_color
    lda #10
    sta zp_cursor_row
    lda #UCHAR_COL_L
    sta zp_cursor_col
    lda #<char_gold_label
    sta zp_ptr0
    lda #>char_gold_label
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_YELLOW
    sta zp_text_color
    lda player_data + PL_GOLD_0
    sta zp_temp0
    lda player_data + PL_GOLD_1
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_LGREY
    sta zp_text_color
    lda #UCHAR_COL_MID
    sta zp_cursor_col
    lda #<status_exp_str
    sta zp_ptr0
    lda #>status_exp_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_XP_0
    sta zp_temp0
    lda player_data + PL_XP_1
    sta zp_temp1
    jsr screen_put_decimal_16

    // --- Spells Known (row 11, spell-casters only) ---
    lda player_data + PL_SPELL_TYPE
    beq !ucd_no_spells+

    lda #COL_LGREY
    sta zp_text_color
    lda #11
    sta zp_cursor_row
    lda #UCHAR_COL_L
    sta zp_cursor_col
    lda #<char_spells_label
    sta zp_ptr0
    lda #>char_spells_label
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    jsr count_spells_known       // Returns count in A
    jsr screen_put_decimal
    lda #$2f                     // '/'
    jsr screen_put_char
    lda #16
    jsr screen_put_decimal
!ucd_no_spells:

    // --- Sex, Social Class, Background (rows 12-16) ---
    jsr ui_char_draw_background

    // --- Press any key ---
    lda #COL_LGREY
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #UCHAR_FOOTER_COL
    sta zp_cursor_col
    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    jsr screen_put_string

    rts

// ui_char_draw_stats — Draw the 6 stats in 2 rows of 3
// Row 6: STR, INT, WIS
// Row 7: DEX, CON, CHR
ui_char_draw_stats:
    ldx #0                  // Stat index

!stat_loop:
    // Calculate row and column
    txa
    cmp #3
    bcc !row6+
    // Row 7, stat index 3-5
    lda #7
    sta zp_cursor_row
    txa
    sec
    sbc #3
    jmp !calc_col+
!row6:
    lda #6
    sta zp_cursor_row
    txa
!calc_col:
    // Column: 0=col 1, 1=col 14, 2=col 27
    cmp #0
    bne !not_0+
    lda #UCHAR_STAT_COL0
    jmp !set_col+
!not_0:
    cmp #1
    bne !not_1+
    lda #UCHAR_STAT_COL1
    jmp !set_col+
!not_1:
    lda #UCHAR_STAT_COL2
!set_col:
    sta zp_cursor_col

    // Print stat name
    txa
    pha                     // Save stat index
    tax
    lda #COL_LGREY
    sta zp_text_color
    lda stat_name_ptrs_lo,x
    sta zp_ptr0
    lda stat_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string

    // ":"
    lda #$3a
    jsr screen_put_char

    // Print stat value (right-justified, 18/xx aware)
    pla                     // Restore stat index
    pha
    tax
    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_STR_CUR,x
    jsr put_stat_val

    pla
    tax
    inx
    cpx #STAT_COUNT
    bcc !stat_loop-
    rts

// ============================================================
// String data (screen codes)
// ============================================================
char_title_str:
    .text "Character Info" ; .byte $00
char_name_label:
    .text "Name: " ; .byte $00
char_race_label:
    .text "Race: " ; .byte $00
char_class_label:
    .text "Class: " ; .byte $00
char_level_label:
    .text "Level: " ; .byte $00
char_wizard_str:
    .text "WIZARD" ; .byte $00
char_mana_label:
    .text "Mana: " ; .byte $00
char_gold_label:
    .text "Gold: " ; .byte $00
char_spells_label:
    .text "Spells: " ; .byte $00

// count_spells_known — Count set bits in PL_SPELLS_KNOWN (16 bits)
// Returns: A = count (0-16)
// Clobbers: X, zp_temp0
count_spells_known:
    lda #0
    sta zp_temp0
    ldx #7
!csk_lo:
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN
    beq !csk_lo_skip+
    inc zp_temp0
!csk_lo_skip:
    dex
    bpl !csk_lo-
    ldx #7
!csk_hi:
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN_HI
    beq !csk_hi_skip+
    inc zp_temp0
!csk_hi_skip:
    dex
    bpl !csk_hi-
    lda zp_temp0
    rts
