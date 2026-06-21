#importonce
// effect_heal.s — shared silent HP heal primitive.

// eff_heal — Heal player HP
// Input: A = heal amount (8-bit, pre-rolled)
// Output: HP updated in ZP and player_data, capped at max
// Clobbers: A
eff_heal:
    clc
    adc zp_player_hp_lo
    sta zp_player_hp_lo
    lda zp_player_hp_hi
    adc #0
    sta zp_player_hp_hi

    // Cap at max HP (16-bit compare)
    lda zp_player_hp_hi
    cmp zp_player_mhp_hi
    bcc !eh_ok+
    bne !eh_clamp+
    lda zp_player_hp_lo
    cmp zp_player_mhp_lo
    bcc !eh_ok+
    beq !eh_ok+
!eh_clamp:
    lda zp_player_mhp_lo
    sta zp_player_hp_lo
    lda zp_player_mhp_hi
    sta zp_player_hp_hi
!eh_ok:
    // Sync to player_data
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI
    rts
