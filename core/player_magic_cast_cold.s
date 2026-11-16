#importonce
// player_magic_cast_cold.s — Cold cast/pray validation & book-known list helpers
//
// Module ownership:
//   owner: PmHelpersSegment (resident / play-slot) when
//     !PLAYER_MAGIC_CAST_HELPERS_EXTERNAL, or co-located with PlayerCastSegment
//     (e.g. SpellOverlay on Atari8) / port cold overlay when
//     PLAYER_MAGIC_CAST_HELPERS_EXTERNAL is defined.
//   lifetime: one 'm' cast or 'p' pray invocation; leaf/resident-only callees
//     with zero nested overlay loads (preserves piw_return_overlay 662921d).
//   callers: player_cast_spell and player_pray (core/player_magic.s; direct when
//     co-located, or via tramp_pm_* when PLAYER_MAGIC_CAST_HELPERS_TRAMPOLINED).

pm_require_class_level:
    ldx player_data + PL_CLASS
    :AuxReadX(class_spell_min_level)
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
    jmp pm_consume_mana

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
    :SpellTblRead_ptr0_y()
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

pm_validate_selected_spell:
    lda pm_mana_tbl_lo
    sta zp_ptr0
    lda pm_mana_tbl_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    :SpellTblRead_ptr0_y()
    sta pm_cost_tmp

    lda pm_lvl_tbl_lo
    sta zp_ptr0
    lda pm_lvl_tbl_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    :SpellTblRead_ptr0_y()
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
