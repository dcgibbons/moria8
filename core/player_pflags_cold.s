#importonce
// player_pflags_cold.s — Equipment-derived effect flags and wielded-weapon cache
//
// Module ownership:
//   owner: ModalMiscOverlay / HelpOverlay / RuntimeBanked via PflagsSegment or
//     when PLAYER_PFLAGS_EXTERNAL is defined; Default resident otherwise.
//   lifetime: one equipment/stat recalculation call (equip, takeoff, acid,
//     enchant, restore, load).
//   callers: player_calc_stats (core/player.s) and player_recalc_equipment
//     (core/player_recalc_equipment.s). Overlay callers reach it via
//     hal_player_recalc_pflags, which saves and restores current_overlay / $01.

player_recalc_pflags_equipment:
    .assert "player_pflags..wield_flags_3 are 12 contiguous bytes", wield_flags_3 - player_pflags, 11
    lda #0
    ldx #3
!pfe_zero_f:
    sta pfe_f0,x
    dex
    bpl !pfe_zero_f-
    ldx #11
!pfe_zero_wield:
    sta player_pflags,x
    dex
    bpl !pfe_zero_wield-

    ldx #EQUIP_WEAPON
!pfe_slot:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pfe_chk_ego+
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    sta item_cur_page
    lda inv_item_id,x
    jsr item_cat_select_id
    jsr item_cat_get_effects
    jsr !pfe_merge_flags+
    lda icat_flags_2
    and #ITR2_SUST_STAT
    beq !pfe_not_item_sust+
    ldy icat_p1_lo
    cpy #7
    bcc !pfe_sust_ok+
    ldy #0
!pfe_sust_ok:
    lda sust_p1_to_mask,y
    ora player_sust_mask
    sta player_sust_mask
!pfe_not_item_sust:
    cpx #EQUIP_WEAPON
    bne !pfe_chk_ego+
    // Cache hot wielded weapon stats so combat/turn never touch ITEM.CAT
    jsr item_cat_get_weight         // A=lo, Y=hi
    sta wield_weight_lo
    sty wield_weight_hi
    jsr item_cat_get_dmg_packed
    sta wield_dmg_packed
    jsr item_get_category_inv_x     // preserves X
    cmp #ICAT_WEAPON
    bne !pfe_wield_flags+
    jsr item_cat_get_missile_type
    sta wield_missile_type
!pfe_wield_flags:
    jsr !pfe_or_wield_flags+
!pfe_chk_ego:
    lda inv_ego,x
    and #EGO_ID_MASK
    beq !pfe_next+
    // Digging tools store prefix IDs (1..4) in inv_ego, not weapon ego IDs.
    tay
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pfe_load_ego+
    jsr item_get_category_inv_x
    cmp #ICAT_DIGGING
    beq !pfe_next+
!pfe_load_ego:
    tya
    jsr item_cat_get_ego
    lda inv_ego,x
    and #EGO_ID_MASK
    cmp #EGO_SLOWNESS
    bne !pfe_ego_ok+
    lda icat_flags_1
    and #($ff ^ ITR1_SPEED)
    sta icat_flags_1
!pfe_ego_ok:
    jsr !pfe_merge_flags+
    lda icat_flags_2
    and #ITR2_SUST_STAT
    beq !pfe_ego_wield+
    lda icat_flags_0
    and #ITR0_STR
    beq !pfe_ego_wield+
    lda #SUST_STR
    ora player_sust_mask
    sta player_sust_mask
!pfe_ego_wield:
    cpx #EQUIP_WEAPON
    bne !pfe_next+
    jsr !pfe_or_wield_flags+
!pfe_next:
    inx
    cpx #EQUIP_END
    beq !pfe_slots_done+
    jmp !pfe_slot-
!pfe_slots_done:
    lda pfe_f3
    and #(ITR3_BLIND | ITR3_TIMID)
    sta player_curse_flags

    ldx #14
!pfe_map_loop:
    ldy pfe_src_off,x
    lda pfe_f0,y
    and pfe_src_mask,x
    beq !pfe_map_next+
    cpx #8
    bcs !pfe_map_pf2+
    lda player_pflags
    ora pfe_dst_mask,x
    sta player_pflags
    bne !pfe_map_next+              // always non-zero
!pfe_map_pf2:
    lda player_pflags2
    ora pfe_dst_mask,x
    sta player_pflags2
!pfe_map_next:
    dex
    bpl !pfe_map_loop-

    // Update combat bonuses from stats
    jmp player_calc_combat

!pfe_or_wield_flags:
    ldy #3
!pfe_we_loop:
    lda wield_flags_0,y
    ora icat_flags_0,y
    sta wield_flags_0,y
    dey
    bpl !pfe_we_loop-
    rts

!pfe_merge_flags:
    ldy #3
!pmf_loop:
    lda pfe_f0,y
    ora icat_flags_0,y
    sta pfe_f0,y
    dey
    bpl !pmf_loop-
    rts

pfe_f0: .byte 0
pfe_f1: .byte 0
pfe_f2: .byte 0
pfe_f3: .byte 0
sust_p1_to_mask:
    .byte SUST_ALL, SUST_STR, SUST_INT, SUST_WIS, SUST_CON, SUST_DEX, SUST_CHR
.assert "sust_p1_to_mask covers 0..6", * - sust_p1_to_mask, 7

pfe_src_off:
    .byte 2, 2, 1, 3, 2, 2, 3, 3
    .byte 0, 1, 1, 1, 1, 0, 3
pfe_src_mask:
    .byte ITR2_RES_FIRE, ITR2_RES_COLD, ITR1_SPEED, ITR3_SEE_INVIS
    .byte ITR2_FREE_ACT, ITR2_RES_ACID, ITR3_RES_LIGHT, ITR3_FFALL
    .byte ITR0_SLOW_DIGEST, ITR1_REGEN, ITR1_STEALTH, ITR1_AGGRAVATE
    .byte ITR1_TELEPORT, ITR0_SEARCH, ITR3_INFRA
pfe_dst_mask:
    .byte PFLAG_RESIST_FIRE, PFLAG_RESIST_COLD, PFLAG_SPEED, PFLAG_SEE_INVIS
    .byte PFLAG_FREE_ACT, PFLAG_RESIST_ACID, PFLAG_RESIST_LIGHT, PFLAG_FFALL
    .byte PFLAG2_SLOW_DIGEST, PFLAG2_REGEN, PFLAG2_STEALTH, PFLAG2_AGGRAVATE
    .byte PFLAG2_TELEPORT, PFLAG2_SEARCH, PFLAG2_INFRA
.assert "pfe flag maps have 15 aligned entries", * - pfe_dst_mask, 15
