#importonce
// ui_recall.s — Monster recall display (banked on C64, resident on C128)
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

.const URCL_TITLE_COL = (SCREEN_COLS - 14) / 2
.const URCL_FOOTER_COL = (SCREEN_COLS - 13) / 2

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
    jsr hal_screen_put_string

    // --- Creature char + name (row 2) ---
    lda #2
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col
    lda #$1b                    // '[' screen code
    jsr hal_screen_put_char
    ldx recall_found_type
    lda cr_color,x
    sta zp_text_color
    lda cr_display,x
    jsr hal_screen_put_char
    lda #COL_WHITE
    sta zp_text_color
    lda #$1d                    // ']' screen code
    jsr hal_screen_put_char
    lda #$20
    jsr hal_screen_put_char
    lda #<creature_name_buf
    sta zp_ptr0
    lda #>creature_name_buf
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    // --- LV / AC / HP (row 4) ---
    lda #4
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col

    jsr rcl_grey
    lda #<rcl_s_lv
    ldy #>rcl_s_lv
    jsr rcl_put_str
    jsr rcl_white
    ldx recall_found_type
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
    lda #$44                    // PETSCII 'D' — portable across C64/C128 backends
    jsr hal_screen_put_char
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
    lda #0
    sta rcl_any_atk

    // Print attack 0 if the slot actually carries damage.
    ldx recall_found_type
    lda cr_atk0_type,x
    beq !rcl_atk1+
    sta rcl_atk_type
    lda cr_atk0_dice,x
    beq !rcl_atk1+
    sta rcl_dice
    lda cr_atk0_sides,x
    beq !rcl_atk1+
    sta rcl_sides
    lda rcl_atk_type
    jsr rcl_print_atk
    inc rcl_any_atk

!rcl_atk1:
    // Print attack 1 only if it is real and non-zero.
    ldx recall_found_type
    lda cr_atk1_type,x
    beq !rcl_no_atk+
    sta rcl_atk_type
    lda cr_atk1_dice,x
    beq !rcl_no_atk+
    sta rcl_dice
    lda cr_atk1_sides,x
    beq !rcl_no_atk+
    sta rcl_sides

    lda rcl_any_atk
    beq !rcl_print_atk1+
    lda #$20
    jsr hal_screen_put_char
    lda #$20
    jsr hal_screen_put_char
!rcl_print_atk1:
    lda rcl_atk_type
    jsr rcl_print_atk
    inc rcl_any_atk

!rcl_no_atk:
    lda rcl_any_atk
    bne !rcl_atk_done+
    lda #<rcl_s_none
    ldy #>rcl_s_none
    jsr rcl_put_str
!rcl_atk_done:

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
    jsr hal_screen_put_string

    rts

// ============================================================
// Helpers
// ============================================================

// rcl_put_str — Set zp_ptr0/hi from A/Y and call screen_put_string
rcl_put_str:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp hal_screen_put_string       // Tail call

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
    tax
    lda rcl_atk_3,x
    jsr hal_screen_put_char
    inx
    lda rcl_atk_3,x
    jsr hal_screen_put_char
    inx
    lda rcl_atk_3,x
    jsr hal_screen_put_char
    lda #$20
    jsr hal_screen_put_char
!rpa_dice:
    lda rcl_dice
    jsr screen_put_decimal
    lda #$44                    // PETSCII 'D' — portable across C64/C128 backends
    jsr hal_screen_put_char
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
// Stored as PETSCII-safe uppercase bytes so screen_put_char renders them
// consistently on both the C64 direct-screen path and the C128 VDC path.
rcl_atk_3:
    .byte $20, $20, $20     // 0: ATK_NONE / unused
    .byte $48, $49, $54     // 1: ATK_NORMAL    HIT
    .byte $43, $4e, $46     // 2: ATK_CONFUSE   CNF
    .byte $46, $45, $52     // 3: ATK_FEAR      FER
    .byte $41, $43, $44     // 4: ATK_ACID      ACD
    .byte $43, $4f, $52     // 5: ATK_CORRODE   COR
    .byte $50, $41, $52     // 6: ATK_PARALYZE  PAR
    .byte $50, $53, $4e     // 7: ATK_POISON    PSN
    .byte $41, $47, $47     // 8: ATK_AGGRAVATE AGG

// ATK code (0-20) → abbreviation index
rcl_atk_idx:
    .byte 0,1,0,2,3,0,4,0,0,5,0,6,0,0,7,0,0,0,0,0,8

// Scratch variables
rcl_scratch: .byte 0
rcl_any_atk: .byte 0
rcl_atk_type:.byte 0
rcl_dice:    .byte 0
rcl_sides:   .byte 0
