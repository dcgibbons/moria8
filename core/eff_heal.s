#importonce
// eff_heal.s — Player HP heal and player_data sync, shared by spell effects
// and turn processing (HP regeneration, per-turn damage). Imported from
// spell_effects.s first on every platform, so it is placed there.

// ============================================================
// eff_heal — Heal player HP
// Input: A = heal amount (8-bit, pre-rolled)
// Output: HP updated in ZP and player_data, capped at max
// Clobbers: A
// ============================================================
eff_heal:
    clc
    adc zp_player_hp_lo
    sta zp_player_hp_lo
    lda zp_player_hp_hi
    adc #0
    sta zp_player_hp_hi

    // Cap at max HP (16-bit unsigned compare)
    lda zp_player_mhp_lo
    cmp zp_player_hp_lo
    lda zp_player_mhp_hi
    sbc zp_player_hp_hi
    bcs eff_heal_sync               // HP <= max HP
    lda zp_player_mhp_lo
    sta zp_player_hp_lo
    lda zp_player_mhp_hi
    sta zp_player_hp_hi
// eff_heal_sync — Copy ZP HP to player_data
eff_heal_sync:
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI
    rts
