#importonce
// player_recalc_equipment — Recalculate AC, to-hit, to-damage from equipment
// Called after any equip/unequip action.
// player_calc_combat already handles DEX bonus + equipment AC (R1.6).
// This adds weapon to-hit/to-damage and ego bonuses.
// Clobbers: everything
player_recalc_equipment:
    // Resets PL_AC (with equipment), PL_TOHIT, PL_TODMG from stats
    jsr player_calc_combat

    // Add weapon split to-hit and to-damage bonuses
    ldx #EQUIP_WEAPON
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pre_no_weapon+
    lda inv_to_hit,x
    clc
    adc player_data + PL_TOHIT
    sta player_data + PL_TOHIT
    lda inv_to_dam,x
    clc
    adc player_data + PL_TODMG
    sta player_data + PL_TODMG

    // Ego AC bonus (Defender/HA — checked in banked code at $F000)
    ldx #EQUIP_WEAPON
    lda inv_ego,x
    beq !pre_no_ego_ac+
    jsr tramp_ego_get_ac_bonus
    beq !pre_no_ego_ac+
    clc
    adc player_data + PL_AC
    sta player_data + PL_AC
!pre_no_ego_ac:
!pre_no_weapon:

    // Sync back to ZP
    lda player_data + PL_AC
    sta zp_player_ac

    rts
