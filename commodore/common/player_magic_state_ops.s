#importonce
// player_magic_state_ops.s — resident spell-state bookkeeping helpers
//
// These routines operate only on resident player/spell state, so keeping them
// resident avoids wasting C128 banked payload space on non-I/O-facing logic.

pm_print_cast_message:
    rts

pm_mark_worked:
    lda #<player_data + PL_SPELLS_WORKED_0
    sta zp_ptr0
    lda #>player_data + PL_SPELLS_WORKED_0
    sta zp_ptr0_hi
    lda pm_spell_idx
    jmp spell_mask_set_ptr

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
