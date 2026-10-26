#importonce
// player_magic_tail.s — resident spell runtime helpers

// ============================================================
// magic_recalc_mana — Recalculate max mana based on level + stat
// Umoria newMana/playerGainMana: levels = level - first spell level + 1;
// mana = levels * [0, 1, 1, 1.5, 2, 2.5, 3, 4][stat_adj] + 1 (0 when
// stat_adj is 0 or the class has no spell yet). Called on level-up.
// Clobbers: A, X, Y, zp_math_a/b
// ============================================================
mrm_mana_halves:
    .byte 0, 2, 2, 3, 4, 5, 6, 8

magic_recalc_mana:
    lda player_data + PL_SPELL_TYPE
    beq !mrm_no_mana+
    cmp #SPELL_MAGE
    bne !mrm_wis+
    lda player_data + PL_INT_CUR
    jmp !mrm_got_stat+
!mrm_wis:
    lda player_data + PL_WIS_CUR
!mrm_got_stat:
    jsr mcns_get_stat_adj
    beq !mrm_no_mana+
    pha
    ldx player_data + PL_CLASS
    :AuxReadX(class_spell_min_level)    // may clobber Y (Apple IIe)
    sta pm_cost_tmp
    pla
    tay
    lda zp_player_lvl
    sec
    sbc pm_cost_tmp
    bcc !mrm_no_mana+
    adc #0                  // C=1: levels = level - min + 1
    ldx mrm_mana_halves,y
    jsr math_multiply

    lsr zp_math_b
    ror zp_math_a
    lda zp_math_b
    bne !mrm_clamp_max+
    lda zp_math_a
    clc
    adc #1
    bcc !mrm_store+

!mrm_clamp_max:
    lda #255
    jmp !mrm_store+

!mrm_no_mana:
    lda #0
    sta player_data + PL_MAX_MANA
    sta zp_player_mmp
    sta player_data + PL_MANA
    sta zp_player_mp
    rts

!mrm_store:
    sta player_data + PL_MAX_MANA
    sta zp_player_mmp
    lda zp_player_mp
    cmp player_data + PL_MAX_MANA
    bcc !mrm_done+
    beq !mrm_done+
    lda player_data + PL_MAX_MANA
    sta zp_player_mp
    sta player_data + PL_MANA
!mrm_done:
    rts
