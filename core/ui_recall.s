#importonce
// ui_recall.s — Full 279-species monster recall display ('/')
//
// Owner per port: DeathOverlay on C64, Plus/4, Apple IIe, Atari 8-bit, and
// BBC Master 128; UIOverlay on C128; ModalMiscOverlay on Commander X16.
// Lifetime: single modal display call via tramp_ui_recall; caller redraws view.
//
// Layout (40-col and 80-col safe; rows 0..16):
//   Row 0:   Recall
//   Row 2:   [K] KOBOLD
//   Row 4:   LV 1    AC 12   HP 1D8
//   Row 6-7: Atk: HIT 1D4  PSN 1D3  ... (wraps to Row 7 col 7 on 40-col)
//   Row 8:   Spl: Yes / None
//   Row 10:  Hurt: FIR CLD ACD PSN LIT STN / None
//   Row 12:  Traits: INVIS PHASE NO-SLP UNDEAD EVIL / None
//   Row 14:  K: 3          D: 0
//   Row 16:  Press any key

.encoding "screencode_mixed"

.const URCL_TITLE_COL  = (SCREEN_COLS - 14) / 2
.const URCL_FOOTER_COL = (SCREEN_COLS - 13) / 2

// Zero-page scratch (safe zone $08-$0b, $1e-$21; untouched by screen & numeric_format)
.label rcl_dice  = zp_ptr1
.label rcl_idx   = zp_ptr1_hi
.label rcl_flags = zp_ptr2
.label rcl_slot  = zp_ptr2
.label rcl_lpos  = zp_ptr2_hi
.label rcl_tlo   = zp_math_a
.label rcl_thi   = zp_math_b
.label rcl_any   = zp_math_tmp0
.label rcl_sides = zp_math_tmp1

// ============================================================
// ui_recall_display — Show recall screen for one creature
// ============================================================
ui_recall_display:
    jsr rcl_white
    jsr ui_help_clear_all

    // --- Title (row 0) ---
    lda #0
    sta zp_cursor_row
    sta rcl_lpos
    tay
    lda #URCL_TITLE_COL
    sta zp_cursor_col
    jsr rcl_put_str_y

    // --- Creature char + name (row 2) ---
    lda #2
    sta zp_cursor_row
    sta zp_cursor_col
    lda #$1b                    // '['
    jsr hal_screen_put_char
#if HAL_PLATFORM_MONSTER_CATALOG
    lda recall_view_color
    sta zp_text_color
    lda recall_view_display
#else
    ldx recall_found_type
    lda cr_color,x
    sta zp_text_color
    lda cr_display,x
#endif
    jsr hal_screen_put_char
    jsr rcl_white
    lda #$1d                    // ']'
    jsr hal_screen_put_char
    jsr rcl_put_space
    lda #<creature_name_buf
    ldy #>creature_name_buf
    jsr screen_put_string_ay

    // --- LV / AC / HP (row 4) ---
#if HAL_PLATFORM_MONSTER_CATALOG
    lda recall_view_level
    jsr rcl_lbl_dec
    lda recall_view_ac
    jsr rcl_lbl_dec
    jsr rcl_next_lbl
    lda recall_view_hd_sides
    sta rcl_sides
    lda recall_view_hd_num
#else
    ldx recall_found_type
    lda cr_level,x
    jsr rcl_lbl_dec
    ldx recall_found_type
    lda cr_ac,x
    jsr rcl_lbl_dec
    jsr rcl_next_lbl
    ldx recall_found_type
    lda cr_hd_sides,x
    sta rcl_sides
    lda cr_hd_num,x
#endif
    jsr rcl_put_ndm

    // --- Attacks (rows 6-7): all 4 slots (atk0..atk3) ---
    jsr rcl_next_lbl
    lda #0
    sta rcl_any
#if HAL_PLATFORM_MONSTER_CATALOG
    sta rcl_slot
!rcl_atk_loop:
    ldx rcl_slot
    ldy rcl_atk_off,x
    lda recall_view_atk0_dice,y
    sta rcl_dice
    lda recall_view_atk0_sides,y
    sta rcl_sides
    lda recall_view_atk0_type,y
    jsr rcl_emit_atk
    inc rcl_slot
    lda rcl_slot
    cmp #4
    bcc !rcl_atk_loop-
#else
    ldx recall_found_type
    lda cr_atk0_dice,x
    sta rcl_dice
    lda cr_atk0_sides,x
    sta rcl_sides
    lda cr_atk0_type,x
    jsr rcl_emit_atk

    ldx recall_found_type
    lda cr_atk1_dice,x
    sta rcl_dice
    lda cr_atk1_sides,x
    sta rcl_sides
    lda cr_atk1_type,x
    jsr rcl_emit_atk

    ldx recall_found_type
    lda cr_atk2_dice,x
    sta rcl_dice
    lda cr_atk2_sides,x
    sta rcl_sides
    lda cr_atk2_type,x
    jsr rcl_emit_atk

    ldx recall_found_type
    lda cr_atk3_dice,x
    sta rcl_dice
    lda cr_atk3_sides,x
    sta rcl_sides
    lda cr_atk3_type,x
    jsr rcl_emit_atk
#endif
    jsr rcl_none_if_zero

    // --- Spells (row 8): "Spl: Yes/None" ---
    jsr rcl_next_lbl
    ldy #rcl_s_yes - rcl_strs
#if HAL_PLATFORM_MONSTER_CATALOG
    lda recall_view_spells
    bne !rcl_spl_put+
    lda recall_view_spell_chance
    and #MS_FREQ_MASK
    beq !rcl_no_spl+
    lda recall_view_spell_flags2
    and #$1f
    ora recall_view_spell_flags
    bne !rcl_spl_put+
    bit recall_view_spell_chance
    bmi !rcl_spl_put+
#else
    ldx recall_found_type
    :AuxReadX(recall_spells)
    bne !rcl_spl_put+
    ldx recall_found_type
    lda cr_spell_chance,x
    and #MS_FREQ_MASK
    beq !rcl_no_spl+
    lda cr_spell_flags2,x
    and #$1f
    ora cr_spell_flags,x
    bne !rcl_spl_put+
    lda cr_spell_chance,x
    bmi !rcl_spl_put+
#endif
!rcl_no_spl:
    ldy #rcl_s_none - rcl_strs
!rcl_spl_put:
    jsr rcl_put_str_y

    // --- Vulnerabilities (row 10): "Hurt: FIR CLD ACD PSN LIT STN" ---
    jsr rcl_next_lbl
#if HAL_PLATFORM_MONSTER_CATALOG
    lda recall_view_cdefense
#else
    ldx recall_found_type
    lda cr_cdefense,x
#endif
    ldx #0
    ldy #6
    jsr rcl_flag_row

    // --- Traits (row 12): "Traits: INVIS PHASE NO-SLP UNDEAD EVIL" ---
    jsr rcl_next_lbl
#if HAL_PLATFORM_MONSTER_CATALOG
    lda recall_view_cdefense
    and #CD_INVISIBLE | CD_NO_SLEEP
    sta zp_temp0
    lda recall_view_spell_flags2
    and #CM2_PHASE
    ora zp_temp0
    sta zp_temp0
    lda recall_view_mflags
#else
    ldx recall_found_type
    lda cr_cdefense,x
    and #CD_INVISIBLE | CD_NO_SLEEP
    sta zp_temp0
    lda cr_spell_flags2,x
    and #CM2_PHASE
    ora zp_temp0
    sta zp_temp0
    lda cr_mflags,x
#endif
    and #CF_UNDEAD | CF_EVIL
    ora zp_temp0
    ldx #6
    ldy #11
    jsr rcl_flag_row

    // --- Kills / Deaths (row 14) ---
#if HAL_PLATFORM_MONSTER_CATALOG
    lda recall_view_kills
    jsr rcl_lbl_dec
    lda recall_view_deaths
    jsr rcl_lbl_dec
#else
    ldx recall_found_type
    :AuxReadX(recall_kills)
    jsr rcl_lbl_dec
    ldx recall_found_type
    :AuxReadX(recall_deaths)
    jsr rcl_lbl_dec
#endif

    // --- Press any key (row 16) ---
    lda #COL_LGREY
    sta zp_text_color
    lda #16
    sta zp_cursor_row
    lda #URCL_FOOTER_COL
    sta zp_cursor_col
    lda #<press_key_str
    ldy #>press_key_str
    jmp screen_put_string_ay


// ============================================================
// Helpers
// ============================================================

rcl_lbl_dec:
    pha
    jsr rcl_next_lbl
    pla
    jmp screen_put_decimal

// rcl_next_lbl — Stream next (col, high-bit-terminated label) from rcl_lbls.
// Whenever col == 2, advances zp_cursor_row to the next even row (4,6,8,10,12,14).
rcl_next_lbl:
    ldx rcl_lpos
    lda rcl_lbls,x
    sta zp_cursor_col
    cmp #2
    bne !same_row+
    lsr zp_cursor_row
    inc zp_cursor_row
    asl zp_cursor_row
!same_row:
    lda #COL_LGREY
    sta zp_text_color
!lbl_ch:
    inc rcl_lpos
    ldx rcl_lpos
    lda rcl_lbls,x
    pha
    jsr hal_screen_put_char
    pla
    cmp #$20
    bne !lbl_ch-
    inc rcl_lpos
rcl_white:
    lda #COL_WHITE
    sta zp_text_color
    rts

rcl_none_if_zero:
    lda rcl_any
    bne !rniz_done+
    ldy #rcl_s_none - rcl_strs
rcl_put_str_y:
    tya
    clc
    adc #<rcl_strs
    ldy #>rcl_strs
    bcc !+
    iny
!:  jmp screen_put_string_ay
!rniz_done:
    rts

rcl_sep_space:
    lda rcl_any
    bne rcl_put_space
    inc rcl_any
    rts
rcl_put_space:
    lda #$20
    jmp hal_screen_put_char

// rcl_flag_row — Print active flags in A for table indices X..Y-1.
rcl_flag_row:
    sta rcl_flags
    stx rcl_idx
    sty rcl_sides
    lda #0
    sta rcl_any
!rfr_loop:
    ldx rcl_idx
    lda rcl_flags
    and rcl_flag_mask,x
    beq !rfr_next+
    jsr rcl_sep_space
    ldx rcl_idx
    ldy rcl_flag_val,x
    cpx #6
    bcs !rfr_str+
    tya
    jsr rcl_put_tag3
    jmp !rfr_next+
!rfr_str:
    jsr rcl_put_str_y
!rfr_next:
    inc rcl_idx
    lda rcl_idx
    cmp rcl_sides
    bcc !rfr_loop-
    bcs rcl_none_if_zero

// rcl_emit_atk — Input: A = raw type, rcl_dice = dice, rcl_sides = raw sides/verb.
rcl_emit_atk:
    and #ATK_TYPE_MASK
    beq !rea_skip+
    cmp #25
    bcs !rea_skip+
    tax
    dex                         // X = 0..23 (0 = ATK_NORMAL)
    lda rcl_sides
    and #ATK_SIDES_MASK
    sta rcl_sides
    beq !rea_no_dice+
    lda rcl_dice
    bne !rea_ok+
!rea_no_dice:
    sta rcl_dice
    txa
    beq !rea_skip+              // Suppress 0d0 ATK_NORMAL placeholder
!rea_ok:
    stx rcl_idx
    lsr rcl_any
    bcc !rea_print+
#if HAL_LAYOUT_WIZARD_40COL_MENU
    lda zp_cursor_col
    cmp #SCREEN_COLS - 13
    bcc !rea_same+
    lda #7
    sta zp_cursor_row
    sta zp_cursor_col
    bne !rea_print+
!rea_same:
#endif
    jsr rcl_put_space
    jsr rcl_put_space
!rea_print:
    inc rcl_any
    ldx rcl_idx
    jsr rcl_put_tag3_x
    lda rcl_dice
    beq !rea_skip+
    jsr rcl_put_space
    lda rcl_dice
rcl_put_ndm:
    jsr screen_put_decimal
    lda #$44                    // PETSCII 'D'
    jsr hal_screen_put_char
    lda rcl_sides
    jmp screen_put_decimal
!rea_skip:
    rts

// rcl_put_tag3 — Unpack and print 3 uppercase chars at index A (or X) in 0..24.
rcl_put_tag3:
    tax
rcl_put_tag3_x:
    lda rcl_tag_lo,x
    sta rcl_tlo
    lda rcl_tag_hi,x
    sta rcl_thi
    jsr !ch+
    jsr !ch+
!ch:
    lda #$08
!b5:
    asl rcl_tlo
    rol rcl_thi
    rol
    bcc !b5-
    ora #$40
    jmp hal_screen_put_char

// ============================================================
// Compact tables (overlay-owned on 80-col; shared with recall_defs.s on 40-col)
// ============================================================

#if !HAL_LAYOUT_WIZARD_40COL_MENU
rcl_lbls:
    .byte 2  ; .text "LV "
    .byte 10 ; .text "AC "
    .byte 18 ; .text "HP "
    .byte 2  ; .text "Atk: "
    .byte 2  ; .text "Spl: "
    .byte 2  ; .text "Hurt: "
    .byte 2  ; .text "Traits: "
    .byte 2  ; .text "K: "
    .byte 16 ; .text "D: "

rcl_strs:
rcl_s_title: .text "Recall" ; .byte 0
rcl_s_none:  .text "None" ; .byte 0
rcl_s_yes:   .text "Yes" ; .byte 0
rcl_t_invis: .text "INVIS" ; .byte 0
rcl_t_phase: .text "PHASE" ; .byte 0
rcl_t_noslp: .text "NO-SLP" ; .byte 0
rcl_t_und:   .text "UNDEAD" ; .byte 0
rcl_t_evil:  .text "EVIL" ; .byte 0
.assert "Recall strings fit 1-byte offset", * - rcl_strs <= 255, true

rcl_tag_lo:
    .byte <rclPack3("HIT"), <rclPack3("STR"), <rclPack3("CNF"), <rclPack3("FER")
    .byte <rclPack3("FIR"), <rclPack3("ACD"), <rclPack3("CLD"), <rclPack3("LTG")
    .byte <rclPack3("COR"), <rclPack3("BLD"), <rclPack3("PAR"), <rclPack3("GLD")
    .byte <rclPack3("ITM"), <rclPack3("PSN"), <rclPack3("DEX"), <rclPack3("CON")
    .byte <rclPack3("INT"), <rclPack3("WIS"), <rclPack3("EXP"), <rclPack3("SHR")
    .byte <rclPack3("DIS"), <rclPack3("FOD"), <rclPack3("LIT"), <rclPack3("CHG")
    .byte <rclPack3("STN")
rcl_tag_hi:
    .byte >rclPack3("HIT"), >rclPack3("STR"), >rclPack3("CNF"), >rclPack3("FER")
    .byte >rclPack3("FIR"), >rclPack3("ACD"), >rclPack3("CLD"), >rclPack3("LTG")
    .byte >rclPack3("COR"), >rclPack3("BLD"), >rclPack3("PAR"), >rclPack3("GLD")
    .byte >rclPack3("ITM"), >rclPack3("PSN"), >rclPack3("DEX"), >rclPack3("CON")
    .byte >rclPack3("INT"), >rclPack3("WIS"), >rclPack3("EXP"), >rclPack3("SHR")
    .byte >rclPack3("DIS"), >rclPack3("FOD"), >rclPack3("LIT"), >rclPack3("CHG")
    .byte >rclPack3("STN")
#endif

rcl_flag_mask:
    .byte $02, $01, $08, $04, $10, $20
    .byte $80, $20, $40, $02, $04

rcl_flag_val:
    .byte 4, 6, 5, 13, 22, 24
    .byte rcl_t_invis - rcl_strs, rcl_t_phase - rcl_strs, rcl_t_noslp - rcl_strs
    .byte rcl_t_und - rcl_strs, rcl_t_evil - rcl_strs

#if HAL_PLATFORM_MONSTER_CATALOG
rcl_atk_off:
    .byte 0, 3, 8, 11
#endif
