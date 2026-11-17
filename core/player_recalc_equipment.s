#importonce
#if !HAL_PLATFORM_ADJUST_EQUIPMENT_STAT_EXTERNAL
#import "player_adjust_equipment_stat.s"
#endif
// player_recalc_equipment — Recalculate AC, to-hit, to-damage from equipment
// Called after any equip/unequip action or a change to a worn item.
// Collects the equipment bonuses player_calc_combat adds on every recalc
// (pcc_eq_*: the weapon's to-hit/to-damage, each Ring of Slaying's, the weapon
// ego's AC), then recalculates the persistent equipment flags (resistances,
// See Invisible, Free Action) and player_calc_combat, which the flags routine
// ends in, without rerolling exceptional current stats.
// Clobbers: everything
player_recalc_equipment:
    lda #0
    sta pcc_eq_tohit
    sta pcc_eq_todam
    sta pcc_eq_ac
    ldx #EQUIP_WEAPON
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pre_rings+
    lda inv_to_hit,x
    sta pcc_eq_tohit
    lda inv_to_dam,x
    sta pcc_eq_todam
    lda inv_ego,x
    and #EGO_ID_MASK
    beq !pre_rings+
    jsr tramp_ego_get_ac_bonus  // Defender / Holy Avenger; clobbers X
    sta pcc_eq_ac
!pre_rings:
#if HAL_PLATFORM_COMPACT_PLAY_SLOT
    .assert "Combat-bonus rings live on Page 1", ITEM_PAGE_RING_OF_SLAYING == ITEM_PAGE_BIT && ITEM_PAGE_RING_OF_INCREASE_DAMAGE == ITEM_PAGE_BIT && ITEM_PAGE_RING_OF_INCREASE_TO_HIT == ITEM_PAGE_BIT, true
    ldx #EQUIP_RING
!pre_slay_ring:                 // each hand: EQUIP_RING, then EQUIP_RING2
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    beq !pre_no_slay+
    lda inv_item_id,x
    cmp #ITEM_SLOT_RING_OF_SLAYING
    beq !pre_add_slay+
    cmp #ITEM_SLOT_RING_OF_INCREASE_DAMAGE
    beq !pre_add_slay+
    cmp #ITEM_SLOT_RING_OF_INCREASE_TO_HIT
    bne !pre_no_slay+
!pre_add_slay:
    lda inv_to_hit,x
    clc
    adc pcc_eq_tohit
    sta pcc_eq_tohit
    lda inv_to_dam,x
    clc
    adc pcc_eq_todam
    sta pcc_eq_todam
!pre_no_slay:
    cpx #EQUIP_RING2
    beq !pre_slay_gloves+
    ldx #EQUIP_RING2
    bne !pre_slay_ring-
!pre_slay_gloves:
    ldx #EQUIP_HANDS
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pre_done_slay+
    lda inv_ego,x
    and #EGO_ID_MASK
    cmp #EGO_SLAYING
    beq !pre_add_g+
    cmp #EGO_ENVELOPING
    bne !pre_done_slay+
!pre_add_g:
    lda inv_to_hit,x
    clc
    adc pcc_eq_tohit
    sta pcc_eq_tohit
    lda inv_to_dam,x
    clc
    adc pcc_eq_todam
    sta pcc_eq_todam
!pre_done_slay:
#else
    jsr player_apply_slaying_bonuses
#endif

    #if PLAYER_RECALC_PFLAGS_EXTERNAL || PLAYER_PFLAGS_EXTERNAL
    jmp hal_player_recalc_pflags
    #else
    jmp player_recalc_pflags_equipment   // resident (OVL.ITEMS calls it on the Apple IIe, BBC Master)
    #endif
