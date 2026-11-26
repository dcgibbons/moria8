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

// mcns_get_stat_adj — Map INT/WIS cur stat (0..255 in A) to spell stat_adj 0..7.
// Preserves: X. Clobbers: Y.
mcns_get_stat_adj:
    ldy #7
!mgsa_loop:
    cmp mcns_stat_thresh - 1,y
    bcs !mgsa_done+
    dey
    bne !mgsa_loop-
!mgsa_done:
    tya
    rts
mcns_stat_thresh:
    .byte 8, 15, 18, 68, 88, 108, 118
