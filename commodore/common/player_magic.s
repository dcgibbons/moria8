#importonce
// player_magic.s — Cast spell (m) and pray (p) commands
//
// Book-scoped, class-aware spell selection following the full 31-spell model.

#import "ui_restore.s"
#import "input_ui_helpers.s"

.encoding "screencode_mixed"

.const HSTR_PM_BOOK_CAST = HSTR_PM_YOU_CAST
.const HSTR_PM_BOOK_PRAY = HSTR_PM_YOU_PRAY
// ============================================================
// player_cast_spell — Handle 'm' (mage-affinity spell classes)
// Output: carry SET = turn consumed, CLEAR = cancelled
// ============================================================
player_cast_spell:
    lda player_data + PL_SPELL_TYPE
    cmp #SPELL_MAGE
    beq !pm_can_cast+
    ldx #HSTR_PM_NO_CAST
    jsr huff_print_msg
#if C128_TEST_SCRIPTED_SPELL
    jmp c128_test_spell_fail_no_cast_sym
#endif
#if C128_TEST_SCRIPTED_SPELL_CANCEL
    jmp c128_test_spell_fail_no_cast_sym
#endif
#if C64_TEST_SCRIPTED_SPELL
    jmp c64_test_spell_fail_no_cast_sym
#endif
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    jmp c64_test_spell_fail_no_cast_sym
#endif
    clc
    rts
!pm_can_cast:
    jsr pm_require_class_level
    bcs !pm_level_ok+
#if C128_TEST_SCRIPTED_SPELL
    jmp c128_test_spell_fail_level_sym
#endif
#if C128_TEST_SCRIPTED_SPELL_CANCEL
    jmp c128_test_spell_fail_level_sym
#endif
#if C64_TEST_SCRIPTED_SPELL
    jmp c64_test_spell_fail_level_sym
#endif
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    jmp c64_test_spell_fail_level_sym
#endif
    clc
    rts
!pm_level_ok:
    lda #SPELL_MAGE
    sta pm_spell_type
    lsr
    sta pm_mode
    jsr pm_setup_active_tables
    jsr pm_select_book
    bcc !pm_cancel+
    jsr pm_build_known_list_from_book
    lda pm_spell_count
    bne !pm_have_spells+
    ldx #HSTR_PM_NOT_KNOWN
    jsr huff_print_msg
#if C128_TEST_SCRIPTED_SPELL
    jmp c128_test_spell_fail_known_sym
#endif
#if C128_TEST_SCRIPTED_SPELL_CANCEL
    jmp c128_test_spell_fail_known_sym
#endif
#if C64_TEST_SCRIPTED_SPELL
    jmp c64_test_spell_fail_known_sym
#endif
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    jmp c64_test_spell_fail_known_sym
#endif
    clc
    rts
!pm_have_spells:
    jsr pm_prompt_visible_spell_choice
    bcc !pm_cancel+
    jsr pm_validate_selected_spell
    bcs !pm_ready+
#if C128_TEST_SCRIPTED_SPELL
    jmp c128_test_spell_fail_validate_sym
#endif
#if C128_TEST_SCRIPTED_SPELL_CANCEL
    jmp c128_test_spell_fail_validate_sym
#endif
#if C64_TEST_SCRIPTED_SPELL
    jmp c64_test_spell_fail_validate_sym
#endif
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    jmp c64_test_spell_fail_validate_sym
#endif
    clc
    rts
!pm_ready:
    jsr calc_spell_failure
    bcc !pm_success+
    jsr pm_handle_fail_roll
#if C128_TEST_SCRIPTED_SPELL
    jmp c128_test_spell_fail_roll_sym
#endif
#if C128_TEST_SCRIPTED_SPELL_CANCEL
    jmp c128_test_spell_fail_roll_sym
#endif
#if C64_TEST_SCRIPTED_SPELL
    jmp c64_test_spell_fail_roll_sym
#endif
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    jmp c64_test_spell_fail_roll_sym
#endif
    sec
    rts
!pm_success:
    jsr tramp_spell_execute_selected
    jsr pm_finish_success_common
#if C128_TEST_SCRIPTED_SPELL
    inc c128_test_spell_success_count
    inc c128_test_spell_return_pending
#endif
#if C64_TEST_SCRIPTED_SPELL
    inc c64_test_spell_success_count
    inc c64_test_spell_return_pending
#endif
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    inc c64_test_spell_success_count
    lda #12
    sta c64_test_spell_return_pending
#endif
    sec
    rts

!pm_cancel:
#if C128_TEST_SCRIPTED_SPELL
    jmp c128_test_spell_fail_cancel_sym
#endif
#if C128_TEST_SCRIPTED_SPELL_CANCEL
    jmp c128_test_spell_cancel_pass_sym
#endif
#if C64_TEST_SCRIPTED_SPELL
    jmp c64_test_spell_fail_cancel_sym
#endif
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    jmp c64_test_spell_fail_cancel_sym
#endif
    jsr msg_clear
    clc
    rts

// ============================================================
// player_pray — Handle 'p' (priest-affinity spell classes)
// Output: carry SET = turn consumed, CLEAR = cancelled
// ============================================================
player_pray:
    lda player_data + PL_SPELL_TYPE
    cmp #SPELL_PRIEST
    beq !pp_can_pray+
    ldx #HSTR_PM_NO_PRAY
    jsr huff_print_msg
#if C128_TEST_SCRIPTED_PRAYER
    jmp c128_test_spell_fail_no_cast_sym
#endif
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    jmp c64_test_spell_fail_no_cast_sym
#endif
    clc
    rts
!pp_can_pray:
    jsr pm_require_class_level
    bcs !pp_level_ok+
#if C128_TEST_SCRIPTED_PRAYER
    jmp c128_test_spell_fail_level_sym
#endif
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    jmp c64_test_spell_fail_level_sym
#endif
    clc
    rts
!pp_level_ok:
    lda #SPELL_PRIEST
    sta pm_spell_type
    lda #0
    sta pm_mode
    jsr pm_setup_active_tables
    jsr pm_select_book
    bcc !pp_cancel+
    jsr pm_build_known_list_from_book
    lda pm_spell_count
    bne !pp_have_prayers+
    ldx #HSTR_PM_NOT_KNOWN
    jsr huff_print_msg
#if C128_TEST_SCRIPTED_PRAYER
    jmp c128_test_spell_fail_known_sym
#endif
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    jmp c64_test_spell_fail_known_sym
#endif
    clc
    rts
!pp_have_prayers:
    jsr pm_prompt_visible_spell_choice
    bcc !pp_cancel+
    jsr pm_validate_selected_spell
    bcs !pp_ready+
#if C128_TEST_SCRIPTED_PRAYER
    jmp c128_test_spell_fail_validate_sym
#endif
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    jmp c64_test_spell_fail_validate_sym
#endif
    clc
    rts
!pp_ready:
    jsr calc_spell_failure
    bcc !pp_success+
    jsr pm_handle_fail_roll
#if C128_TEST_SCRIPTED_PRAYER
    jmp c128_test_spell_fail_roll_sym
#endif
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    jmp c64_test_spell_fail_roll_sym
#endif
    sec
    rts
!pp_success:
    jsr tramp_spell_execute_selected
    jsr pm_finish_success_common
#if C128_TEST_SCRIPTED_PRAYER
    inc c128_test_spell_success_count
    lda c128_test_spell_return_pending
    bne !pp_test_pending_set128+
    lda #20
    sta c128_test_spell_return_pending
!pp_test_pending_set128:
#endif
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    inc c64_test_spell_success_count
    lda c64_test_spell_return_pending
    bne !pp_test_pending_set+
    lda #20
    sta c64_test_spell_return_pending
!pp_test_pending_set:
#endif
    sec
    rts

!pp_cancel:
#if C128_TEST_SCRIPTED_PRAYER
    jmp c128_test_spell_fail_cancel_sym
#endif
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    jmp c64_test_spell_fail_cancel_sym
#endif
    jsr msg_clear
    clc
    rts

// ============================================================
// Helpers
// ============================================================
pm_setup_active_tables:
    ldx player_data + PL_CLASS
    lda class_spell_mana_lo,x
    sta pm_mana_tbl_lo
    lda class_spell_mana_hi,x
    sta pm_mana_tbl_hi
    lda class_spell_level_lo,x
    sta pm_lvl_tbl_lo
    lda class_spell_level_hi,x
    sta pm_lvl_tbl_hi
    lda class_spell_fail_lo,x
    sta pm_fail_tbl_lo
    lda class_spell_fail_hi,x
    sta pm_fail_tbl_hi

    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !pm_setup_priest_names+
    lda #<mage_spell_name_lo
    sta pm_name_lo_lo
    lda #>mage_spell_name_lo
    sta pm_name_lo_hi
    lda #<mage_spell_name_hi
    sta pm_name_hi_lo
    lda #>mage_spell_name_hi
    sta pm_name_hi_hi
    rts
!pm_setup_priest_names:
    lda #<priest_spell_name_lo
    sta pm_name_lo_lo
    lda #>priest_spell_name_lo
    sta pm_name_lo_hi
    lda #<priest_spell_name_hi
    sta pm_name_hi_lo
    lda #>priest_spell_name_hi
    sta pm_name_hi_hi
    rts

pm_require_class_level:
    ldx player_data + PL_CLASS
    lda class_spell_min_level,x
    cmp zp_player_lvl
    beq !pm_rcl_ready+
    bcc !pm_rcl_ready+
    ldx #HSTR_PM_NO_EXP
    jsr huff_print_msg
    clc
    rts
!pm_rcl_ready:
    sec
    rts

pm_handle_fail_roll:
    ldx #HSTR_PM_FAIL
    jsr huff_print_msg
    lda #SFX_SPELL_FAIL
    jsr hal_sound_play
    jsr pm_consume_mana
    rts

pm_select_book:
!pm_select_retry:
    jsr pm_book_prompt_huff_id
    lda #PIW_FILTER_MAGE_BOOK + 1
    sec
    sbc pm_spell_type
    jsr piw_prompt_filtered_inv
    bcc !pm_book_cancel+
!pm_have_books:
    jsr input_prepare_modal_dismiss_key
    jsr input_get_key
    cmp #$3f
    bne !pm_not_inv+
    lda piw_filter
    jsr show_inv_and_select
!pm_not_inv:
    cmp #$20
    beq !pm_book_cancel+
    jsr input_is_modal_escape_key
    beq !pm_book_cancel+
    jsr piw_pick_filtered_inv_key
    bcs !pm_book_slot_ok+
!pm_book_cancel:
    clc
    rts
!pm_book_slot_ok:
    jsr book_find_index
    bcc !pm_book_type_ok+
    clc
    rts
!pm_book_type_ok:
    stx pm_book_idx
    lda book_spell_affinity,x
    cmp pm_spell_type
    beq !pm_book_aff_ok+
    ldx #HSTR_IGS_WRONG_TYPE
    jsr huff_print_msg
    clc
    rts
!pm_book_aff_ok:
    lda book_mask_lo,x
    sta pm_book_mask_lo
    lda book_mask_hi,x
    sta pm_book_mask_hi
    jsr msg_clear
    sec
    rts

#if !C128
pm_book_prompt_huff_id:
    lda pm_mode
    beq !pm_prompt_not_study+
    ldx #HSTR_IGS_PROMPT
    rts
!pm_prompt_not_study:
    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !pm_prompt_pray+
    ldx #HSTR_PM_BOOK_CAST
    rts
!pm_prompt_pray:
    ldx #HSTR_PM_BOOK_PRAY
    rts
#endif

pm_build_known_list_from_book:
    lda #0
    sta pm_spell_count
    ldx #0
!pm_bk_loop:
    cpx #SPELL_CATALOG_COUNT
    bcs !pm_bk_done+

    lda pm_lvl_tbl_lo
    sta zp_ptr0
    lda pm_lvl_tbl_hi
    sta zp_ptr0_hi
    txa
    tay
    lda (zp_ptr0),y
    cmp #99
    beq !pm_bk_next+

    lda pm_book_mask_lo
    sta zp_ptr0
    lda pm_book_mask_hi
    sta zp_ptr0_hi
    txa
    jsr spell_mask_test_ptr
    bcc !pm_bk_next+

    lda #<player_data + PL_SPELLS_LEARNT_0
    sta zp_ptr0
    lda #>player_data + PL_SPELLS_LEARNT_0
    sta zp_ptr0_hi
    txa
    jsr spell_mask_test_ptr
    bcc !pm_bk_next+

    ldy pm_spell_count
    txa
    sta pm_spell_list,y
    inc pm_spell_count
!pm_bk_next:
    inx
    jmp !pm_bk_loop-
!pm_bk_done:
    rts

pm_build_learnable_list_from_book:
    lda #0
    sta pm_spell_count
    ldx #0
!pm_bl_loop:
    cpx #SPELL_CATALOG_COUNT
    bcs !pm_bl_done+

    lda pm_lvl_tbl_lo
    sta zp_ptr0
    lda pm_lvl_tbl_hi
    sta zp_ptr0_hi
    txa
    tay
    lda (zp_ptr0),y
    cmp #99
    beq !pm_bl_next+
    cmp zp_player_lvl
    beq !pm_bl_check_book+
    bcc !pm_bl_check_book+
    jmp !pm_bl_next+

!pm_bl_check_book:
    lda pm_book_mask_lo
    sta zp_ptr0
    lda pm_book_mask_hi
    sta zp_ptr0_hi
    txa
    jsr spell_mask_test_ptr
    bcc !pm_bl_next+

    lda #<player_data + PL_SPELLS_LEARNT_0
    sta zp_ptr0
    lda #>player_data + PL_SPELLS_LEARNT_0
    sta zp_ptr0_hi
    txa
    jsr spell_mask_test_ptr
    bcs !pm_bl_next+

    ldy pm_spell_count
    txa
    sta pm_spell_list,y
    inc pm_spell_count
!pm_bl_next:
    inx
    jmp !pm_bl_loop-
!pm_bl_done:
    rts

pm_prompt_visible_spell_choice:
!pm_psc_prompt:
    // On C128, release-gate before drawing the follow-up prompt so a quick
    // book-letter -> spell-letter transition does not get swallowed by a
    // post-render wait.
    jsr input_prepare_followup_key
    ldx #HSTR_PM_FOOTER_PRAY
    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !pm_psc_prompt_ready+
    ldx #HSTR_PM_FOOTER_CAST
!pm_psc_prompt_ready:
    lda pm_spell_count
    jsr piw_print_prompt_with_count
#if C128
    jsr input_get_key_fast
#else
    jsr input_get_key
#endif
    cmp #$3f
    beq !pm_psc_show_list+
    jsr pm_pick_visible_spell
    bcc !pm_psc_done+
    jsr msg_clear
    sec
    rts
!pm_psc_done:
    rts

!pm_psc_show_list:
    // Match other selectable overlays: release-gate before drawing the list
    // so a quick first selection/cancel key is not swallowed by the gate.
#if C128
    jsr input_prepare_followup_key
#else
    jsr input_prepare_modal_dismiss_key
#endif
    jsr tramp_spell_list_display
#if C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY || C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY
    jmp test_assert_spell_list_overlay
#endif
#if C128
    jsr input_get_key_fast
#else
    jsr input_get_key
#endif
    pha
    jsr ui_view_restore_modal_overlay
    pla
    cmp #$20
    beq !pm_psc_cancel+
    jsr input_is_modal_escape_key
    beq !pm_psc_cancel+
    jsr pm_pick_visible_spell
    bcc !pm_psc_prompt-
    jsr msg_clear
    sec
    rts
!pm_psc_cancel:
    clc
    rts

pm_pick_visible_spell:
    cmp #$61
    bcc !pm_pick_upper_ready+
    cmp #$7b
    bcs !pm_pick_upper_ready+
    and #$df
!pm_pick_upper_ready:
    sec
    sbc #$41
    bcc !pm_pick_fail+
    cmp pm_spell_count
    bcs !pm_pick_fail+
    tay
    lda pm_spell_list,y
    sta pm_spell_idx
    sec
    rts
!pm_pick_fail:
    clc
    rts

pm_validate_selected_spell:
    lda pm_mana_tbl_lo
    sta zp_ptr0
    lda pm_mana_tbl_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y
    sta pm_cost_tmp

    lda pm_lvl_tbl_lo
    sta zp_ptr0
    lda pm_lvl_tbl_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y
    cmp zp_player_lvl
    beq !pm_valid_done+
    bcc !pm_valid_done+
    ldx #HSTR_PM_NO_EXP
    jsr huff_print_msg
    clc
    rts
!pm_valid_done:
    sec
    rts

pm_consume_mana:
    lda pm_cost_tmp
    cmp zp_player_mp
    bcc !pm_cm_normal+
    beq !pm_cm_normal+

    sbc zp_player_mp
    sta zp_temp0

    ldx #HSTR_PM_NO_MANA
    jsr huff_print_msg
    // The faint reason is important feedback; acknowledge it during the
    // initiating action so forced paralysis turns never enter -MORE-.
    jsr msg_show_more
    jsr input_get_key

    lda #5
    ldx zp_temp0
    jsr math_multiply
    lda zp_math_a
    beq !pm_cm_zero_mp+
    jsr rng_range
    clc
    adc #1
    sta zp_eff_paralyze
!pm_cm_zero_mp:
    lda #0
    sta zp_player_mp
    sta player_data + PL_MANA

    lda #3
    jsr rng_range
    lsr
    bcc !pm_cm_done+
    lda player_data + PL_CON_CUR
    cmp #4
    bcc !pm_cm_done+
    dec player_data + PL_CON_CUR
    dec zp_player_con
    jsr player_calc_hp
    rts

!pm_cm_normal:
    lda zp_player_mp
    sec
    sbc pm_cost_tmp
    sta zp_player_mp
    sta player_data + PL_MANA
!pm_cm_done:
    rts

#if !C128
    #import "player_magic_levelup.s"
    #import "player_magic_display.s"
    #import "player_magic_tail.s"
#endif

.assert "pm_spell_type mage", SPELL_MAGE, 1
.assert "pm_spell_type priest", SPELL_PRIEST, 2
