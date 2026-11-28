#importonce
// ui_character.s — Expanded character sheet display (40-col 2-page & 80-col 1-page)
//
// Shows full character info on screen. Called from character
// creation and via the 'C' command during gameplay.

#import "platform_services_api.s"
#import "spell_data_defs.s"

.const UCHAR_TITLE_COL = hal_layout_character_title_col
.const UCHAR_WIZARD_COL = hal_layout_character_wizard_col
.const UCHAR_FOOTER_COL = hal_layout_character_footer_col
.const UCHAR_COL_L = hal_layout_character_col_l
.const UCHAR_COL_NAME = hal_layout_character_col_name
.const UCHAR_COL_MID = hal_layout_character_col_mid
.const UCHAR_COL_R = hal_layout_character_col_r
.const UCHAR_STAT_COL0 = hal_layout_character_stat_col0
.const UCHAR_STAT_COL1 = hal_layout_character_stat_col1
.const UCHAR_STAT_COL2 = hal_layout_character_stat_col2

// Field table row flags & op IDs
.const UCF_ALIGN9 = $80                 // Set value col = label col + 9
.const UCF_CASTER = $40                 // Skip field if PL_SPELL_TYPE == 0

// Op IDs >= $80 read player_data[op & $7F] and call screen_put_decimal directly.
.const UC_OP_DEC_PL    = $80

.const UC_OP_NAME      = 0
.const UC_OP_RACE      = 1
.const UC_OP_CLASS     = 2
.const UC_OP_TITLE     = 3
.const UC_OP_HUNGER    = 4
.const UC_OP_LEVEL     = UC_OP_DEC_PL | PL_LEVEL
.const UC_OP_AGE       = UC_OP_DEC_PL | PL_AGE
.const UC_OP_HT        = 5
.const UC_OP_WT        = 6
.const UC_OP_DEPTH     = 7
.const UC_OP_AC        = UC_OP_DEC_PL | PL_AC
.const UC_OP_HP        = 8
.const UC_OP_MANA      = 9
.const UC_OP_GOLD      = 10
.const UC_OP_XP        = 11
.const UC_OP_SPELLS    = 12
.const UC_OP_NEXT      = 13
.const UC_OP_SK_FIGHT  = 14
.const UC_OP_SK_BOWS   = 15
.const UC_OP_SK_SAVE   = 16
.const UC_OP_SK_STEALTH= 17
.const UC_OP_SK_SEARCH = 18
.const UC_OP_SK_DISARM = 19
.const UC_OP_SK_INFRA  = 20
.const UC_OP_BLOWS     = 21
.const UC_OP_HITDAM    = 22
.const UC_OP_SEX       = 23
.const UC_OP_SC        = UC_OP_DEC_PL | PL_SOCIAL_CLASS
.const UC_OP_HIT       = 24
.const UC_OP_DAM       = 25
.const UC_OP_BLOWS40   = UC_OP_DEC_PL | PL_BLOWS

// ============================================================
// Entry points
// ============================================================

#if UI_CHAR_MODAL_EXTERNAL
// ui_char_display_modal — 40-col interactive 2-page modal loop.
// P / > / < / Tab toggle pages 1<->2; Space, Esc, Enter, or any other key exits.
ui_char_display_modal:
    lda #0
    sta uchar_page
!ucdm_draw:
    jsr ui_char_draw_current_page
    jsr input_get_modal_dismiss_key
    cmp #$50                    // 'P'
    beq !ucdm_toggle+
    cmp #$d0                    // Shift+'P' (PETSCII)
    beq !ucdm_toggle+
    cmp #$3e                    // '>'
    beq !ucdm_toggle+
    cmp #$3c                    // '<'
    beq !ucdm_toggle+
    cmp #$09                    // Tab / Ctrl+I
    beq !ucdm_toggle+
    rts
!ucdm_toggle:
    lda uchar_page
    eor #1
    sta uchar_page
    jmp !ucdm_draw-
#endif

// ui_char_display — Render Character Sheet (Page 1 on 40-col, full sheet on 80-col).
// Non-blocking (returns immediately after drawing).
ui_char_display:
.if (SCREEN_COLS < 80) {
    lda #0
    sta uchar_page
}
ui_char_draw_current_page:
#if HAL_PLATFORM_CHARACTER_SHEET_BEGIN_ENABLED
    jsr hal_platform_character_sheet_begin
#endif
    lda #COL_WHITE
    sta zp_text_color
    jsr ui_help_clear_all

    // Title (row 0) + optional WIZARD badge
    lda #0
    ldx #UCHAR_TITLE_COL
    jsr uchar_set_pos
    lda #<char_title_str
    ldy #>char_title_str
    jsr screen_put_string_ay

    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    beq !ucd_not_wizard+
    lda #COL_YELLOW
    sta zp_text_color
    lda #0
    ldx #UCHAR_WIZARD_COL
    jsr uchar_set_pos
    lda #<char_wizard_str
    ldy #>char_wizard_str
    jsr screen_put_string_ay
!ucd_not_wizard:

.if (SCREEN_COLS >= 80) {
    lda #<char_fields_80
    ldy #>char_fields_80
    jsr uchar_run_fields
    jsr ui_char_draw_stats
    jsr ui_char_draw_background
    jsr ui_char_draw_skills
    lda #22
    ldx #UCHAR_FOOTER_COL
    jsr uchar_set_lgrey_pos
    lda #<press_key_str
    ldy #>press_key_str
    jmp screen_put_string_ay
} else {
    lda uchar_page
    beq !ucd_p1+
    jmp ui_char_draw_page2
!ucd_p1:
    lda #<char_fields_40
    ldy #>char_fields_40
    jsr uchar_run_fields
    jsr ui_char_draw_stats
    lda #<char_p1_hint_str
    ldy #>char_p1_hint_str
    jmp uchar_put_40_footer

// ui_char_draw_page2 — Render 40-col Page 2/2 (Abilities + Background)
ui_char_draw_page2:
    lda #2
    ldx #1
    jsr uchar_set_pos           // white
    lda #<char_abilities_hdr
    ldy #>char_abilities_hdr
    jsr screen_put_string_ay
    jsr ui_char_draw_skills
    jsr ui_char_draw_background
    lda #<char_p2_hint_str
    ldy #>char_p2_hint_str
uchar_put_40_footer:
    pha
    tya
    pha
    lda #18
    ldx #UCHAR_FOOTER_COL
    jsr uchar_set_lgrey_pos
    lda #<press_key_str
    ldy #>press_key_str
    jsr screen_put_string_ay
    lda #19
    ldx #10
    jsr uchar_set_lgrey_pos
    pla
    tay
    pla
    jmp screen_put_string_ay
}

// ============================================================
// Table-driven field runner
// Record: row_flags ($FF = end), col, <lbl, >lbl, op_id
// ============================================================
uchar_run_fields:
    sta uchar_tbl_lo
    sty uchar_tbl_hi
    lda #0
    sta uchar_tbl_idx
!urf_loop:
    lda uchar_tbl_lo
    sta zp_ptr1
    lda uchar_tbl_hi
    sta zp_ptr1_hi
    ldy uchar_tbl_idx
    lda (zp_ptr1),y
    cmp #$ff
    beq !urf_done+
    sta uchar_tmp
    and #UCF_CASTER
    beq !urf_draw+
    lda player_data + PL_SPELL_TYPE
    beq !urf_next+
!urf_draw:
    lda uchar_tmp
    and #$3f
    sta zp_cursor_row
    iny
    lda (zp_ptr1),y
    sta zp_cursor_col
    sta uchar_col_save
    jsr uchar_lgrey
    iny
    lda (zp_ptr1),y
    pha
    iny
    lda (zp_ptr1),y
    tay
    pla
    jsr screen_put_string_ay
    lda uchar_tmp
    bpl !urf_no_align+
    lda uchar_col_save
    clc
    adc #9
    sta zp_cursor_col
!urf_no_align:
    lda #COL_WHITE
    sta zp_text_color
    ldy uchar_tbl_idx
    iny
    iny
    iny
    iny
    lda (zp_ptr1),y
    bmi !urf_dec_pl+
    tax
    jsr uchar_dispatch_op
    jmp !urf_next+
!urf_dec_pl:
    and #$7f
    tax
    lda player_data,x
    jsr screen_put_decimal
!urf_next:
    lda uchar_tbl_idx
    clc
    adc #5
    sta uchar_tbl_idx
    jmp !urf_loop-
!urf_done:
    rts

uchar_dispatch_op:
    lda uchar_op_hi,x
    pha
    lda uchar_op_lo,x
    pha
    rts

// ============================================================
// Field descriptor tables
// ============================================================
char_fields_80:
.if (SCREEN_COLS >= 80) {
    .byte 2 | UCF_ALIGN9, 2,  <char_name_label,   >char_name_label,   UC_OP_NAME
    .byte 3 | UCF_ALIGN9, 2,  <char_race_label,   >char_race_label,   UC_OP_RACE
    .byte 4 | UCF_ALIGN9, 2,  <char_class_label,  >char_class_label,  UC_OP_CLASS
    .byte 5 | UCF_ALIGN9, 2,  <char_title_lbl,    >char_title_lbl,    UC_OP_TITLE
    .byte 6 | UCF_ALIGN9, 2,  <char_hunger_lbl,   >char_hunger_lbl,   UC_OP_HUNGER
    .byte 7 | UCF_ALIGN9, 2,  <char_level_label,  >char_level_label,  UC_OP_LEVEL
    .byte 2 | UCF_ALIGN9, 29, <char_age_lbl,      >char_age_lbl,      UC_OP_AGE
    .byte 3 | UCF_ALIGN9, 29, <char_ht_lbl,       >char_ht_lbl,       UC_OP_HT
    .byte 4 | UCF_ALIGN9, 29, <char_wt_lbl,       >char_wt_lbl,       UC_OP_WT
    .byte 5 | UCF_ALIGN9, 29, <char_depth_lbl,    >char_depth_lbl,    UC_OP_DEPTH
    .byte 6 | UCF_ALIGN9, 29, <char_blows_lbl,    >char_blows_lbl,    UC_OP_BLOWS
    .byte 7 | UCF_ALIGN9, 29, <status_ac_str,     >status_ac_str,     UC_OP_AC
    .byte 9 | UCF_ALIGN9, 2,  <status_hp_str,     >status_hp_str,     UC_OP_HP
    .byte 9 | UCF_ALIGN9, 29, <char_mana_label,   >char_mana_label,   UC_OP_MANA
    .byte 9,              53, <char_hitdam_lbl,   >char_hitdam_lbl,   UC_OP_HITDAM
    .byte 10 | UCF_ALIGN9, 2, <char_gold_label,   >char_gold_label,   UC_OP_GOLD
    .byte 10 | UCF_ALIGN9, 29,<status_exp_str,    >status_exp_str,    UC_OP_XP
    .byte 10 | UCF_CASTER, 53,<char_spells_label, >char_spells_label, UC_OP_SPELLS
    .byte 20 | UCF_ALIGN9, 29,<char_next_lbl,     >char_next_lbl,     UC_OP_NEXT
    .byte $ff
}

char_fields_40:
.if (SCREEN_COLS < 80) {
    .byte 2,  UCHAR_COL_L,   <char_name_label,   >char_name_label,   UC_OP_NAME
    .byte 2,  25,            <char_sex_lbl,      >char_sex_lbl,      UC_OP_SEX
    .byte 3,  UCHAR_COL_L,   <char_race_label,   >char_race_label,   UC_OP_RACE
    .byte 3,  UCHAR_COL_R,   <char_class_label,  >char_class_label,  UC_OP_CLASS
    .byte 4,  UCHAR_COL_L,   <char_level_label,  >char_level_label,  UC_OP_LEVEL
    .byte 4,  13,            <char_title_lbl,    >char_title_lbl,    UC_OP_TITLE
    .byte 9,  UCHAR_COL_L,   <status_hp_str,     >status_hp_str,     UC_OP_HP
    .byte 9,  UCHAR_COL_MID, <char_mana_label,   >char_mana_label,   UC_OP_MANA
    .byte 10, UCHAR_COL_L,   <char_gold_label,   >char_gold_label,   UC_OP_GOLD
    .byte 10, UCHAR_COL_MID, <status_exp_str,    >status_exp_str,    UC_OP_XP
    .byte 11 | UCF_CASTER, UCHAR_COL_L, <char_spells_label, >char_spells_label, UC_OP_SPELLS
    .byte 11, UCHAR_COL_MID, <char_depth_lbl,    >char_depth_lbl,    UC_OP_DEPTH
    .byte 12, 1,             <char_age40_lbl,    >char_age40_lbl,    UC_OP_AGE
    .byte 12, 10,            <char_ht40_lbl,     >char_ht40_lbl,     UC_OP_HT
    .byte 12, 18,            <char_wt40_lbl,     >char_wt40_lbl,     UC_OP_WT
    .byte 12, 28,            <char_sc40_lbl,     >char_sc40_lbl,     UC_OP_SC
    .byte 13, 1,             <status_ac_str,     >status_ac_str,     UC_OP_AC
    .byte 13, 9,             <char_hit40_lbl,    >char_hit40_lbl,    UC_OP_HIT
    .byte 13, 20,            <char_dam40_lbl,    >char_dam40_lbl,    UC_OP_DAM
    .byte 13, 31,            <char_bl40_lbl,     >char_bl40_lbl,     UC_OP_BLOWS40
    .byte 14, 1,             <char_hunger_lbl,   >char_hunger_lbl,   UC_OP_HUNGER
    .byte 14, 18,            <char_next_lbl,     >char_next_lbl,     UC_OP_NEXT
    .byte $ff
}

char_skill_fields:
.if (SCREEN_COLS >= 80) {
    .byte 18, 2,  <char_fight_lbl,   >char_fight_lbl,   UC_OP_SK_FIGHT
    .byte 19, 2,  <char_bows_lbl,    >char_bows_lbl,    UC_OP_SK_BOWS
    .byte 20, 2,  <char_save_lbl,    >char_save_lbl,    UC_OP_SK_SAVE
    .byte 18, 29, <char_stealth_lbl, >char_stealth_lbl, UC_OP_SK_STEALTH
    .byte 19, 29, <char_search_lbl,  >char_search_lbl,  UC_OP_SK_SEARCH
    .byte 18, 56, <char_disarm_lbl,  >char_disarm_lbl,  UC_OP_SK_DISARM
    .byte 19, 56, <char_infra_lbl,   >char_infra_lbl,   UC_OP_SK_INFRA
} else {
    .byte 3, 1, <char_fight_lbl,   >char_fight_lbl,   UC_OP_SK_FIGHT
    .byte 4, 1, <char_bows_lbl,    >char_bows_lbl,    UC_OP_SK_BOWS
    .byte 5, 1, <char_save_lbl,    >char_save_lbl,    UC_OP_SK_SAVE
    .byte 6, 1, <char_stealth_lbl, >char_stealth_lbl, UC_OP_SK_STEALTH
    .byte 7, 1, <char_search_lbl,  >char_search_lbl,  UC_OP_SK_SEARCH
    .byte 8, 1, <char_disarm_lbl,  >char_disarm_lbl,  UC_OP_SK_DISARM
    .byte 9, 1, <char_infra_lbl,   >char_infra_lbl,   UC_OP_SK_INFRA
}
    .byte $ff

// ============================================================
// Stats & derived skills entry points
// ============================================================
ui_char_draw_skills:
    lda #<char_skill_fields
    ldy #>char_skill_fields
    jmp uchar_run_fields

ui_char_draw_stats:
    ldx #0
!stat_loop:
    stx uchar_idx
.if (SCREEN_COLS >= 80) {
    txa
    clc
    adc #2
    ldx #53
    jsr uchar_set_lgrey_pos
    ldx uchar_idx
    lda stat_name_ptrs_lo,x
    ldy stat_name_ptrs_hi,x
    jsr uchar_lbl_w
    lda #$3a                    // ':'
    jsr hal_screen_put_char
    lda #58
    sta zp_cursor_col
    ldx uchar_idx
    lda player_data + PL_STR_CUR,x
    jsr put_stat_val
    ldx uchar_idx
    lda player_data + PL_STR_CUR,x
    cmp player_data + PL_STR_BASE,x
    beq !stat_next+
    jsr uchar_lgrey
    lda #<char_paren_l
    ldy #>char_paren_l
    jsr screen_put_string_ay
    ldx uchar_idx
    lda player_data + PL_STR_BASE,x
    jsr put_stat_val
    lda #$29                    // ')'
    jsr hal_screen_put_char
} else {
    lda stat40_row,x
    sta zp_cursor_row
    lda stat40_col,x
    sta zp_cursor_col
    jsr uchar_lgrey
    ldx uchar_idx
    lda stat_name_ptrs_lo,x
    ldy stat_name_ptrs_hi,x
    jsr uchar_lbl_w
    lda #$3a
    jsr hal_screen_put_char
    ldx uchar_idx
    lda player_data + PL_STR_CUR,x
    jsr put_stat_val
}
!stat_next:
    ldx uchar_idx
    inx
    cpx #STAT_COUNT
    bcc !stat_loop-
    rts

stat40_row:
.if (SCREEN_COLS < 80) {
    .byte 6, 6, 6, 7, 7, 7
}
stat40_col:
.if (SCREEN_COLS < 80) {
    .byte UCHAR_STAT_COL0, UCHAR_STAT_COL1, UCHAR_STAT_COL2
    .byte UCHAR_STAT_COL0, UCHAR_STAT_COL1, UCHAR_STAT_COL2
}

// ============================================================
// Field op handlers (RTS-dispatched: table entries store label - 1)
// ============================================================
uchar_op_name:
.if (SCREEN_COLS < 80) {
    lda #UCHAR_COL_NAME
    sta zp_cursor_col
}
    lda #<(player_data + PL_NAME)
    ldy #>(player_data + PL_NAME)
    jmp screen_put_string_ay

uchar_op_race:
    ldx player_data + PL_RACE
    lda race_name_ptrs_lo,x
    ldy race_name_ptrs_hi,x
    jmp screen_put_string_ay

uchar_op_class:
    ldx player_data + PL_CLASS
    lda class_name_ptrs_lo,x
    ldy class_name_ptrs_hi,x
    jmp screen_put_string_ay

uchar_op_title:
    lda player_data + PL_LEVEL
    sec
    sbc #1
    bcs !upt_ok+
    lda #0
!upt_ok:
    ldx #0
!upt_div5:
    cmp #5
    bcc !upt_emit+
    sec
    sbc #5
    inx
    cpx #7
    bcc !upt_div5-
!upt_emit:
    lda #<char_ranks
    ldy #>char_ranks
    jmp uchar_put_nth_str

uchar_op_hunger:
    ldx player_data + PL_HUNGER
    bne !uph_tbl+
    lda #<char_full_str
    ldy #>char_full_str
    jmp screen_put_string_ay
!uph_tbl:
    cpx #4
    bcc !uph_ok+
    ldx #0
!uph_ok:
    lda hunger_name_ptrs_lo,x
    ldy hunger_name_ptrs_hi,x
    jmp screen_put_string_ay

uchar_op_ht:
    lda player_data + PL_HEIGHT
    jsr screen_put_decimal
    lda #$22                    // '"'
    jmp hal_screen_put_char

uchar_op_wt:
    lda player_data + PL_WEIGHT
    jsr screen_put_decimal
    lda #<char_wt_unit_str
    ldy #>char_wt_unit_str
    jmp screen_put_string_ay

uchar_op_depth:
    lda player_data + PL_DLEVEL
    bne !upd_deep+
    lda #<char_town_str
    ldy #>char_town_str
    jmp screen_put_string_ay
!upd_deep:
    ldx #50
    jsr math_multiply
    lda zp_math_a
    sta zp_temp0
    lda zp_math_b
    sta zp_temp1
    jsr screen_put_decimal_16
    lda #$27                    // '\''
    jmp hal_screen_put_char

uchar_op_blows:
.if (SCREEN_COLS >= 80) {
    lda player_data + PL_BLOWS
    jsr screen_put_decimal
    lda #<char_rnd_str
    ldy #>char_rnd_str
    jmp screen_put_string_ay
}

uchar_op_hp:
    ldx #PL_HP_LO
    jsr !uhp_put16+
    jsr uchar_put_slash
    ldx #PL_MHP_LO
!uhp_put16:
    lda player_data,x
    sta zp_temp0
    lda player_data + 1,x
    sta zp_temp1
    jmp screen_put_decimal_16

uchar_op_mana:
    lda player_data + PL_MANA
    jsr screen_put_decimal
    jsr uchar_put_slash
    lda player_data + PL_MAX_MANA
    jmp screen_put_decimal

// Row 10 Gold/XP (zp_cursor_row = 10 comes from char_fields_*)
uchar_op_gold:
    lda #COL_YELLOW
    sta zp_text_color
    ldx #PL_GOLD_0
    .byte $2c                   // BIT abs skips ldx #PL_XP_0
uchar_op_xp:
    ldx #PL_XP_0
    lda player_data,x
    sta zp_temp0
    lda player_data + 1,x
    sta zp_temp1
    lda player_data + 2,x
    sta nf_value_2
    jmp screen_put_decimal_u24

uchar_op_spells:
    jsr count_spells_known
    jsr screen_put_decimal
    jsr uchar_put_slash
    ldx player_data + PL_CLASS
    :AuxReadX(class_spell_total)
    jmp screen_put_decimal

uchar_put_slash:
    lda #$2f
    jmp hal_screen_put_char

uchar_op_hitdam:
.if (SCREEN_COLS >= 80) {
    lda player_data + PL_TOHIT
    jsr uchar_put_signed8
    jsr uchar_put_slash
    lda player_data + PL_TODMG
    jmp uchar_put_signed8
}

uchar_op_sex:
.if (SCREEN_COLS < 80) {
    ldx #0
    lda player_data + PL_FLAGS
    and #PLF_MALE
    beq !sex_emit+
    inx
!sex_emit:
    lda #<char_sex_strs
    ldy #>char_sex_strs
    jmp uchar_put_nth_str
}

uchar_op_hit:
.if (SCREEN_COLS < 80) {
    ldx #PL_TOHIT
    .byte $2c                   // BIT abs skips 2-byte ldx #PL_TODMG
}
uchar_op_dam:
.if (SCREEN_COLS < 80) {
    ldx #PL_TODMG
    lda player_data,x
    jmp uchar_put_signed8
}

uchar_op_sk_fight:
    ldx #0
    beq !bth_go+
uchar_op_sk_bows:
    ldx #1
!bth_go:
    jsr uchar_calc_bth_skill
    jmp uchar_put_rating

uchar_op_sk_save:
    ldx #2
    jsr uchar_calc_prop_skill
    jmp uchar_put_rating

uchar_op_sk_stealth:
    jsr player_get_stealth      // 0..9
    asl
    asl
    asl
    asl                         // * 16 -> 0..144
    jmp uchar_put_rating

uchar_op_sk_search:
    jsr player_search_get_base_chance
    jsr screen_put_decimal
    lda #$25                    // '%'
    jmp hal_screen_put_char

uchar_op_sk_disarm:
    ldx #3
    jsr uchar_calc_prop_skill
    sta uchar_tmp
    lda player_data + PL_DEX_CUR
    cmp #18
    bcc !dis_dex_lo+
    lda #18
!dis_dex_lo:
    cmp #3
    bcs !dis_dex_ok+
    lda #3
!dis_dex_ok:
    sec
    sbc #3
    tax
    lda dex_disarm_bonus,x
    jsr uchar_add_signed_tmp
    jmp uchar_put_rating

uchar_op_sk_infra:
    lda player_data + PL_RACE
    ldx #RACE_PROP_SIZE
    jsr math_multiply
    ldx zp_math_a
    lda race_properties + 1,x
    ldx zp_eff_infra
    beq !inf_chk_pf+
    clc
    adc #1
!inf_chk_pf:
    sta uchar_tmp
    lda player_pflags2
    and #PFLAG2_INFRA
    beq !inf_done+
    inc uchar_tmp
    inc uchar_tmp
!inf_done:
    lda uchar_tmp
    beq !inf_none+
    jsr screen_put_decimal
    lda #<char_ft_str
    ldy #>char_ft_str
    jmp screen_put_string_ay
!inf_none:
    lda #<char_none_str
    ldy #>char_none_str
    jmp screen_put_string_ay

// ============================================================
// Shared helpers
// ============================================================
uchar_set_lgrey_pos:
    jsr uchar_set_pos
uchar_lgrey:
    lda #COL_LGREY
    sta zp_text_color
    rts

uchar_set_pos:
    sta zp_cursor_row
    stx zp_cursor_col
    rts

uchar_lbl_w:
    jsr screen_put_string_ay
    lda #COL_WHITE
    sta zp_text_color
    rts

uchar_put_signed8:
    pha
    bpl !ups_pos+
    lda #$2d                    // '-'
    jsr hal_screen_put_char
    pla
    eor #$ff
    clc
    adc #1
    jmp screen_put_decimal
!ups_pos:
    lda #$2b                    // '+'
    jsr hal_screen_put_char
    pla
    jmp screen_put_decimal

// Compute XP needed for next level (matching combat_compute_level_threshold).
uchar_op_next:
    lda player_data + PL_LEVEL
    beq !upn_max+
    cmp #40
    bcc !upn_calc+
!upn_max:
    lda #<char_max_str
    ldy #>char_max_str
    jmp screen_put_string_ay
!upn_calc:
    sta zp_player_lvl
    jsr combat_compute_level_threshold
    lda ccl_adj_0
    sta zp_temp0
    lda ccl_adj_1
    sta zp_temp1
    lda ccl_adj_2
    sta nf_value_2
    jmp screen_put_decimal_u24

// uchar_calc_bth_skill — X = 0 (Fighting) or 1 (Bows/Throw) -> A (0..255)
uchar_calc_bth_skill:
    jsr uchar_calc_prop_skill
    sta uchar_tmp
    lda player_data + PL_TOHIT
    pha
    bpl !ucb_mag+
    eor #$ff
    clc
    adc #1
!ucb_mag:
    ldx #3
    jsr math_multiply
    pla
    bmi !ucb_sub+
    lda zp_math_b
    bne !ucb_cap+
    lda uchar_tmp
    clc
    adc zp_math_a
    bcc !ucb_ret+
!ucb_cap:
    lda #255
!ucb_ret:
    rts
!ucb_sub:
    lda zp_math_b
    bne !ucb_zero+
    lda uchar_tmp
    sec
    sbc zp_math_a
    bcs !ucb_ret-
!ucb_zero:
    lda #0
    rts

// uchar_calc_prop_skill — X = skill index 0..3 -> A (0..255)
uchar_calc_prop_skill:
    stx uchar_idx
    lda player_data + PL_CLASS
    ldx #CLASS_PROP_SIZE
    jsr math_multiply
    ldx uchar_idx
    lda zp_math_a
    clc
    adc ucp_cls_off,x
    tax
    lda class_properties,x
    sta uchar_tmp

    lda player_data + PL_CLASS
    ldx #CLASS_LVL_SIZE
    jsr math_multiply
    ldx uchar_idx
    lda zp_math_a
    clc
    adc ucp_lvl_off,x
    tax
    lda class_level_adj,x
    ldx player_data + PL_LEVEL
    jsr math_multiply
    lda zp_math_b
    bne !ucp_lvl_cap+
    lda uchar_tmp
    clc
    adc zp_math_a
    bcc !ucp_lvl_ok+
!ucp_lvl_cap:
    lda #255
!ucp_lvl_ok:
    sta uchar_tmp

    lda player_data + PL_RACE
    ldx #RACE_PROP_SIZE
    jsr math_multiply
    ldx uchar_idx
    lda zp_math_a
    clc
    adc ucp_race_off,x
    tax
    lda race_properties,x
uchar_add_signed_tmp:
    bmi !ucp_neg+
    clc
    adc uchar_tmp
    bcc !ucp_done+
    lda #255
!ucp_done:
    rts
!ucp_neg:
    eor #$ff
    clc
    adc #1
    sta uchar_rem
    lda uchar_tmp
    sec
    sbc uchar_rem
    bcs !ucp_done-
    lda #0
    rts

// Table of property offsets for (0=Fight, 1=Bows, 2=Save, 3=Disarm)
ucp_cls_off:  .byte 3, 4, 6, 5
ucp_race_off: .byte 7, 8, 9, 3
ucp_lvl_off:  .byte 0, 1, 4, 3

uchar_put_rating:
    ldx #0
!upr_loop:
    cmp #18
    bcc !upr_emit+
    sec
    sbc #18
    inx
    cpx #7
    bcc !upr_loop-
!upr_emit:
    lda #<char_ratings
    ldy #>char_ratings
uchar_put_nth_str:
    sta zp_ptr0
    sty zp_ptr0_hi
    ldy #0
    txa
    beq !upns_print+
!upns_skip:
    lda (zp_ptr0),y
    iny
    bne !upns_same+
    inc zp_ptr0_hi
!upns_same:
    cmp #0
    bne !upns_skip-
    dex
    bne !upns_skip-
!upns_print:
    tya
    clc
    adc zp_ptr0
    ldy zp_ptr0_hi
    bcc !upns_go+
    iny
!upns_go:
    jmp screen_put_string_ay

// Dispatch table (entry points minus 1 for RTS dispatch)
uchar_op_lo:
    .byte <(uchar_op_name - 1), <(uchar_op_race - 1), <(uchar_op_class - 1)
    .byte <(uchar_op_title - 1), <(uchar_op_hunger - 1)
    .byte <(uchar_op_ht - 1), <(uchar_op_wt - 1), <(uchar_op_depth - 1)
    .byte <(uchar_op_hp - 1), <(uchar_op_mana - 1), <(uchar_op_gold - 1)
    .byte <(uchar_op_xp - 1), <(uchar_op_spells - 1), <(uchar_op_next - 1)
    .byte <(uchar_op_sk_fight - 1), <(uchar_op_sk_bows - 1), <(uchar_op_sk_save - 1)
    .byte <(uchar_op_sk_stealth - 1), <(uchar_op_sk_search - 1), <(uchar_op_sk_disarm - 1)
    .byte <(uchar_op_sk_infra - 1)
.if (SCREEN_COLS >= 80) {
    .byte <(uchar_op_blows - 1), <(uchar_op_hitdam - 1)
} else {
    .byte 0, 0
    .byte <(uchar_op_sex - 1), <(uchar_op_hit - 1), <(uchar_op_dam - 1)
}
uchar_op_hi:
    .byte >(uchar_op_name - 1), >(uchar_op_race - 1), >(uchar_op_class - 1)
    .byte >(uchar_op_title - 1), >(uchar_op_hunger - 1)
    .byte >(uchar_op_ht - 1), >(uchar_op_wt - 1), >(uchar_op_depth - 1)
    .byte >(uchar_op_hp - 1), >(uchar_op_mana - 1), >(uchar_op_gold - 1)
    .byte >(uchar_op_xp - 1), >(uchar_op_spells - 1), >(uchar_op_next - 1)
    .byte >(uchar_op_sk_fight - 1), >(uchar_op_sk_bows - 1), >(uchar_op_sk_save - 1)
    .byte >(uchar_op_sk_stealth - 1), >(uchar_op_sk_search - 1), >(uchar_op_sk_disarm - 1)
    .byte >(uchar_op_sk_infra - 1)
.if (SCREEN_COLS >= 80) {
    .byte >(uchar_op_blows - 1), >(uchar_op_hitdam - 1)
} else {
    .byte 0, 0
    .byte >(uchar_op_sex - 1), >(uchar_op_hit - 1), >(uchar_op_dam - 1)
}

// ============================================================
// Scratch (8 bytes)
// ============================================================
uchar_page:     .byte 0
uchar_idx:      .byte 0
uchar_tbl_idx:  .byte 0
uchar_tbl_lo:   .byte 0
uchar_tbl_hi:   .byte 0
uchar_col_save: .byte 0
uchar_tmp:      .byte 0
uchar_rem:      .byte 0

// ============================================================
// String data (screen codes)
// ============================================================
char_title_str:  .text "Character Info" ; .byte 0
char_wizard_str: .text "WIZARD" ; .byte 0
char_name_label: .text "Name: " ; .byte 0
char_race_label: .text "Race: " ; .byte 0
char_class_label:.text "Class: " ; .byte 0
char_level_label:.text "Level: " ; .byte 0
char_mana_label: .text "Mana: " ; .byte 0
char_gold_label: .text "Gold: " ; .byte 0
char_spells_label:.text "Spells: " ; .byte 0
char_title_lbl:  .text "Title: " ; .byte 0
char_hunger_lbl: .text "Hunger: " ; .byte 0
char_depth_lbl:  .text "Depth: " ; .byte 0
char_next_lbl:   .text "Next: " ; .byte 0
char_town_str:   .text "Town" ; .byte 0
char_full_str:   .text "Full" ; .byte 0
char_max_str:    .text "Max" ; .byte 0
char_none_str:   .text "None" ; .byte 0
char_ft_str:     .text "0 ft" ; .byte 0

char_wt_unit_str:
.if (SCREEN_COLS >= 80) {
    .text " lb" ; .byte 0
} else {
    .text "lb" ; .byte 0
}

char_age_lbl:    .if (SCREEN_COLS >= 80) { .text "Age: " ; .byte 0 }
char_ht_lbl:     .if (SCREEN_COLS >= 80) { .text "Height: " ; .byte 0 }
char_wt_lbl:     .if (SCREEN_COLS >= 80) { .text "Weight: " ; .byte 0 }
char_blows_lbl:  .if (SCREEN_COLS >= 80) { .text "Blows: " ; .byte 0 }
char_rnd_str:    .if (SCREEN_COLS >= 80) { .text "/rnd" ; .byte 0 }
char_hitdam_lbl: .if (SCREEN_COLS >= 80) { .text "Hit/Dam: " ; .byte 0 }
char_paren_l:    .if (SCREEN_COLS >= 80) { .text " (" ; .byte 0 }

char_sex_lbl:       .if (SCREEN_COLS < 80) { .text "Sex: " ; .byte 0 }
char_sex_strs:      .if (SCREEN_COLS < 80) { .text "Female" ; .byte 0 ; .text "Male" ; .byte 0 }
char_age40_lbl:     .if (SCREEN_COLS < 80) { .text "Age:" ; .byte 0 }
char_ht40_lbl:      .if (SCREEN_COLS < 80) { .text "Ht:" ; .byte 0 }
char_wt40_lbl:      .if (SCREEN_COLS < 80) { .text "Wt:" ; .byte 0 }
char_sc40_lbl:      .if (SCREEN_COLS < 80) { .text "SC:" ; .byte 0 }
char_hit40_lbl:     .if (SCREEN_COLS < 80) { .text "Hit:" ; .byte 0 }
char_dam40_lbl:     .if (SCREEN_COLS < 80) { .text "Dam:" ; .byte 0 }
char_bl40_lbl:      .if (SCREEN_COLS < 80) { .text "Bl:" ; .byte 0 }
char_abilities_hdr: .if (SCREEN_COLS < 80) { .text "Abilities:" ; .byte 0 }
char_p1_hint_str:   .if (SCREEN_COLS < 80) { .text "[P:Page 1/2  Skills]" ; .byte 0 }
char_p2_hint_str:   .if (SCREEN_COLS < 80) { .text "[P:Page 2/2  Stats ]" ; .byte 0 }

char_fight_lbl:   .text "Fighting   : " ; .byte 0
char_bows_lbl:    .text "Bows/Throw : " ; .byte 0
char_save_lbl:    .text "Saving Thrw: " ; .byte 0
char_stealth_lbl: .text "Stealth    : " ; .byte 0
char_search_lbl:  .text "Searching  : " ; .byte 0
char_disarm_lbl:  .text "Disarming  : " ; .byte 0
char_infra_lbl:   .text "Infravision: " ; .byte 0

char_ranks:
    .text "Novice" ; .byte 0
    .text "Initiate" ; .byte 0
    .text "Apprentice" ; .byte 0
    .text "Journeyman" ; .byte 0
    .text "Veteran" ; .byte 0
    .text "Hero" ; .byte 0
    .text "Master" ; .byte 0
    .text "Grand Master" ; .byte 0

char_ratings:
    .text "Bad" ; .byte 0
    .text "Poor" ; .byte 0
    .text "Fair" ; .byte 0
    .text "Good" ; .byte 0
    .text "Very Good" ; .byte 0
    .text "Superb" ; .byte 0
    .text "Heroic" ; .byte 0
    .text "Legendary" ; .byte 0

// count_spells_known — Count set bits in the widened learned mask
// Returns: A = count
// Clobbers: A, X, Y, zp_temp0
count_spells_known:
    lda #0
    sta zp_temp0
    ldy #SPELL_MASK_BYTES - 1
!csk_byte:
    lda player_data + PL_SPELLS_LEARNT_0,y
    ldx #8
!csk_bit:
    lsr
    bcc !csk_next+
    inc zp_temp0
!csk_next:
    dex
    bne !csk_bit-
    dey
    bpl !csk_byte-
    lda zp_temp0
    rts
