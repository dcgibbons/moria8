#importonce
// player_magic_learn_op.s — learn/spell-order bookkeeping for study paths
//
// Kept out of the C128 UI overlay so spell-study modal code can stay within
// $E000-$EFFF while still calling the shared learn helper directly.

pm_add_spell_to_order:
    ldx #0
!pm_aso_loop:
    cpx #32
    bcs !pm_aso_done+
    lda player_data + PL_SPELL_ORDER,x
    cmp pm_spell_idx
    beq !pm_aso_done+
    cmp #99
    beq !pm_aso_store+
    inx
    jmp !pm_aso_loop-
!pm_aso_store:
    lda pm_spell_idx
    sta player_data + PL_SPELL_ORDER,x
!pm_aso_done:
    rts

pm_learn_selected_spell:
    lda #<player_data + PL_SPELLS_LEARNT_0
    sta zp_ptr0
    lda #>player_data + PL_SPELLS_LEARNT_0
    sta zp_ptr0_hi
    lda pm_spell_idx
    jsr spell_mask_set_ptr

    lda #<player_data + PL_SPELLS_FORGOTTEN_0
    sta zp_ptr0
    lda #>player_data + PL_SPELLS_FORGOTTEN_0
    sta zp_ptr0_hi
    lda pm_spell_idx
    jsr spell_mask_clear_ptr

    jsr pm_add_spell_to_order

    lda player_data + PL_NEW_SPELLS
    beq !pm_lss_msg+
    dec player_data + PL_NEW_SPELLS

!pm_lss_msg:
    ldx #HSTR_IGS_SUCCESS
    jsr huff_print_msg
    rts
