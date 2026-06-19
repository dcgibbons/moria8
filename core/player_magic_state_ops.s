#importonce
// player_magic_state_ops.s — resident spell-state bookkeeping helpers
//
// These routines operate only on resident player/spell state, so keeping them
// resident avoids wasting C128 banked payload space on non-I/O-facing logic.

pm_finish_success_common:
    jsr pm_mark_worked
    lda #SFX_SPELL
    jsr hal_sound_play
    jmp pm_consume_mana
pm_finish_success_common_end:

pm_mark_worked:
    lda #<player_data + PL_SPELLS_WORKED_0
    sta zp_ptr0
    lda #>player_data + PL_SPELLS_WORKED_0
    sta zp_ptr0_hi
    lda pm_spell_idx
    jmp spell_mask_set_ptr
pm_mark_worked_end:
