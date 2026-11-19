#importonce
// player_magic_browse_cold.s — Cold study-book learnable-spell list builder
//
// Module ownership:
//   owner: PmHelpersSegment (resident / play-slot) when !PLAYER_MAGIC_BROWSE_EXTERNAL,
//     or UiOverlay (`ovl.ui`, co-located with item_gain_spell) / port cold overlay
//     when PLAYER_MAGIC_BROWSE_EXTERNAL is defined.
//   lifetime: one 'G' gain-spell book-study invocation; performs no nested
//     overlay switches, leaving piw_return_overlay (662921d) untouched.
//   callers: item_gain_spell (core/player_gain_spell_impl.s; direct when
//     co-located in UiOverlay, or via tramp_pm_build_learnable when
//     PLAYER_MAGIC_BROWSE_TRAMPOLINED is defined).

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
    :SpellTblRead_ptr0_y()
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
