#importonce
// player_magic_tail.s — resident spell runtime helpers

// ============================================================
// magic_recalc_mana — Recalculate max mana based on level + stat
// Formula: max_mana = (level * stat) / 8 + spell_stat_bonus[stat-3]
// Clamped to [1, 255]. Called on level-up.
// Clobbers: A, X, Y, zp_math_a/b
// ============================================================
magic_recalc_mana:
    lda player_data + PL_SPELL_TYPE
    bne !mrm_has_spells+

    lda #0
    sta player_data + PL_MAX_MANA
    sta zp_player_mmp
    sta player_data + PL_MANA
    sta zp_player_mp
    rts

!mrm_has_spells:
    lda player_data + PL_SPELL_TYPE
    cmp #SPELL_MAGE
    bne !mrm_wis+
    lda player_data + PL_INT_CUR
    jmp !mrm_got_stat+
!mrm_wis:
    lda player_data + PL_WIS_CUR

!mrm_got_stat:
    sta pm_cost_tmp

    lda zp_player_lvl
    ldx pm_cost_tmp
    jsr math_multiply

    lsr zp_math_b
    ror zp_math_a
    lsr zp_math_b
    ror zp_math_a
    lsr zp_math_b
    ror zp_math_a

    lda zp_math_b
    bne !mrm_clamp_max+
    lda zp_math_a
    sta pm_cost_tmp

    lda player_data + PL_SPELL_TYPE
    cmp #SPELL_MAGE
    bne !mrm_wis_bonus+
    lda player_data + PL_INT_CUR
    jmp !mrm_bonus+
!mrm_wis_bonus:
    lda player_data + PL_WIS_CUR
!mrm_bonus:
    jsr stat_bonus_index
    lda spell_stat_bonus,x
    clc
    adc pm_cost_tmp
    bcs !mrm_clamp_max+
    cmp #1
    bcs !mrm_store+
    lda #1
    jmp !mrm_store+

!mrm_clamp_max:
    lda #255

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
