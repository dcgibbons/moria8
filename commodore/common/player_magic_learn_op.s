#importonce
// player_magic_learn_op.s — learn/spell-order bookkeeping for study paths
//
// Kept out of the C128 UI overlay so spell-study modal code can stay within
// $E000-$EFFF while still calling the shared learn helper directly.

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
