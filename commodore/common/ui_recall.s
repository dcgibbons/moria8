#importonce
// ui_recall.s — Monster recall display (banked at $F000)
//
// Shows creature info for the creature type in recall_found_type.
// Called from trampoline with KERNAL banked out ($01=$35).
// creature_name_buf has been pre-populated by creature_get_name.
//
// Layout (overlay rows with centered title/footer; width adapts via SCREEN_COLS):
//   Row 0:  MONSTER RECALL
//   Row 2:  [K] KOBOLD
//   Row 4:  LV 1   AC 12   HP 1D8
//   Row 6:  ATK: HIT 1D4   PSN 1D3
//   Row 8:  SPELLS: YES
//   Row 10: KILLED 3   DIED 0
//   Row 16: PRESS ANY KEY

#importonce

#if C128
.const URCL_TITLE_COL = (SCREEN_COLS - 14) / 2
.const URCL_FOOTER_COL = (SCREEN_COLS - 13) / 2
#else
.const URCL_TITLE_COL = 13
.const URCL_FOOTER_COL = 13
#endif

// ============================================================
// ui_recall_display — Show recall screen for one creature
// ============================================================
ui_recall_display:
    lda #COL_WHITE
    sta zp_text_color
    jsr ui_help_clear_all

    // --- Title (row 0) ---
    lda #0
    sta zp_cursor_row
    lda #URCL_TITLE_COL
    sta zp_cursor_col
    lda #<rcl_s_title
    sta zp_ptr0
    lda #>rcl_s_title
    sta zp_ptr0_hi
    jsr screen_put_string

    // --- Creature char + name (row 2) ---
    lda #2
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col
    lda #$1b                    // '[' screen code
    jsr screen_put_char
    ldx recall_found_type
    lda cr_color,x
    sta zp_text_color
    lda cr_display,x
    jsr screen_put_char
    lda #COL_WHITE
    sta zp_text_color
    lda #$1d                    // ']' screen code
    jsr screen_put_char
    lda #$20
    jsr screen_put_char
    lda #<creature_name_buf
    sta zp_ptr0
    lda #>creature_name_buf
    sta zp_ptr0_hi
    jsr screen_put_string

    // --- LV / AC / HP (row 4) ---
    ldx recall_found_type
    lda #4
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col

    jsr rcl_grey
    lda #<rcl_s_lv
    ldy #>rcl_s_lv
    jsr rcl_put_str
    jsr rcl_white
    lda cr_level,x
    jsr screen_put_decimal

    lda #10
    sta zp_cursor_col
    jsr rcl_grey
    lda #<rcl_s_ac
    ldy #>rcl_s_ac
    jsr rcl_put_str
    jsr rcl_white
    ldx recall_found_type
    lda cr_ac,x
    jsr screen_put_decimal

    lda #18
    sta zp_cursor_col
    jsr rcl_grey
    lda #<rcl_s_hp
    ldy #>rcl_s_hp
    jsr rcl_put_str
    jsr rcl_white
    ldx recall_found_type
    lda cr_hd_num,x
    jsr screen_put_decimal
    lda #$04                    // 'D'
    jsr screen_put_char
    ldx recall_found_type
    lda cr_hd_sides,x
    jsr screen_put_decimal

    // --- Attacks (row 6): "ATK: TYP NdM  TYP NdM" ---
    lda #6
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col
    jsr rcl_grey
    lda #<rcl_s_atk
    ldy #>rcl_s_atk
    jsr rcl_put_str

    jsr rcl_white
    ldx recall_found_type
    lda cr_atk0_type,x
    beq !rcl_no_atk+
    // Print attack 0: type + dice
    tay                         // Y = type for lookup
    lda cr_atk0_dice,x
    sta rcl_dice
    lda cr_atk0_sides,x
    sta rcl_sides
    tya
    jsr rcl_print_atk

    // Attack 1 (on same row)
    ldx recall_found_type
    lda cr_atk1_type,x
    beq !rcl_no_atk+
    lda #$20
    jsr screen_put_char
    jsr screen_put_char
    ldx recall_found_type
    lda cr_atk1_type,x
    tay
    lda cr_atk1_dice,x
    sta rcl_dice
    lda cr_atk1_sides,x
    sta rcl_sides
    tya
    jsr rcl_print_atk
!rcl_no_atk:

    // --- Spells (row 8): "SPELLS: YES/NONE" ---
    lda #8
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col
    jsr rcl_grey
    lda #<rcl_s_spl
    ldy #>rcl_s_spl
    jsr rcl_put_str

    jsr rcl_white
    ldx recall_found_type
    lda recall_spells,x
    bne !rcl_has_spl+
    lda #<rcl_s_none
    ldy #>rcl_s_none
    jmp !rcl_spl_print+
!rcl_has_spl:
    lda #<rcl_s_yes
    ldy #>rcl_s_yes
!rcl_spl_print:
    jsr rcl_put_str

    // --- Kills / Deaths (row 10) ---
    lda #10
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col
    jsr rcl_grey
    lda #<rcl_s_kill
    ldy #>rcl_s_kill
    jsr rcl_put_str
    jsr rcl_white
    ldx recall_found_type
    lda recall_kills,x
    jsr screen_put_decimal

    lda #16
    sta zp_cursor_col
    jsr rcl_grey
    lda #<rcl_s_died
    ldy #>rcl_s_died
    jsr rcl_put_str
    jsr rcl_white
    ldx recall_found_type
    lda recall_deaths,x
    jsr screen_put_decimal

    // --- Press any key (row 16) ---
    lda #COL_LGREY
    sta zp_text_color
    lda #16
    sta zp_cursor_row
    lda #URCL_FOOTER_COL
    sta zp_cursor_col
    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    jsr screen_put_string

    rts

// ============================================================
// Helpers
// ============================================================

// rcl_put_str — Set zp_ptr0/hi from A/Y and call screen_put_string
rcl_put_str:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp screen_put_string       // Tail call

// rcl_grey / rcl_white — Set text color
rcl_grey:
    lda #COL_LGREY
    sta zp_text_color
    rts
rcl_white:
    lda #COL_WHITE
    sta zp_text_color
    rts

// rcl_print_atk — Print "TYP NdM" for one attack
// Input: A = attack type (ATK_*), rcl_dice/rcl_sides set
// Clobbers: A, Y, X
rcl_print_atk:
    // Print 3-char type name
    tay
    cpy #21
    bcs !rpa_dice+              // Out of range — skip name
    lda rcl_atk_idx,y
    sta rcl_scratch
    asl                         // *2
    clc
    adc rcl_scratch             // *3
    tay
    lda rcl_atk_3,y
    jsr screen_put_char
    lda rcl_atk_3+1,y
    jsr screen_put_char
    lda rcl_atk_3+2,y
    jsr screen_put_char
    lda #$20
    jsr screen_put_char
!rpa_dice:
    lda rcl_dice
    jsr screen_put_decimal
    lda #$04                    // 'D'
    jsr screen_put_char
    lda rcl_sides
    jmp screen_put_decimal      // Tail call

// ============================================================
// String data (screen codes, null-terminated)
// ============================================================
rcl_s_title: .text "Recall" ; .byte 0
rcl_s_lv:    .text "LV " ; .byte 0
rcl_s_ac:    .text "AC " ; .byte 0
rcl_s_hp:    .text "HP " ; .byte 0
rcl_s_atk:   .text "Atk: " ; .byte 0
rcl_s_spl:   .text "Spl: " ; .byte 0
rcl_s_kill:  .text "K: " ; .byte 0
rcl_s_died:  .text "D: " ; .byte 0
rcl_s_none:  .text "None" ; .byte 0
rcl_s_yes:   .text "Yes" ; .byte 0

// Attack type 3-char abbreviations (9 × 3 = 27 bytes)
rcl_atk_3:
    .text "   "     // 0: ATK_NONE / unused
    .text "HIT"     // 1: ATK_NORMAL
    .text "CNF"     // 2: ATK_CONFUSE
    .text "FER"     // 3: ATK_FEAR
    .text "ACD"     // 4: ATK_ACID
    .text "COR"     // 5: ATK_CORRODE
    .text "PAR"     // 6: ATK_PARALYZE
    .text "PSN"     // 7: ATK_POISON
    .text "AGG"     // 8: ATK_AGGRAVATE

// ATK code (0-20) → abbreviation index
rcl_atk_idx:
    .byte 0,1,0,2,3,0,4,0,0,5,0,6,0,0,7,0,0,0,0,0,8

// Scratch variables
rcl_scratch: .byte 0
rcl_dice:    .byte 0
rcl_sides:   .byte 0
