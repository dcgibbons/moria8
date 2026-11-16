#importonce
// calc_dig_cold.s — Digging ability formula for tunneling (S6)
//
// Module ownership:
//   owner: ItemActionsOverlay / TitleOverlay when CALC_DIG_EXTERNAL is defined
//     (co-located with core/tunnel.s under CALC_DIG_CO_LOCATED); ResidentPlay /
//     Default otherwise (imported by core/game_loop.s).
//   lifetime: one tunneling attempt ('+' or Shift+D terrain bash).
//   callers: core/tunnel.s (direct jsr calc_dig_ability when CALC_DIG_CO_LOCATED,
//     else jsr tramp_dig_ability).

// ============================================================
// calc_dig_ability — Calculate digging ability (STR + tool/weapon bonus)
// New formula for R14: (STR>>2) + base_bonus + (ego*12) for digging tools
// Output: tun_dig_ability set
// Clobbers: A, X
// ============================================================
calc_dig_ability:
    // Check equipped weapon
    ldx inv_item_id + EQUIP_WEAPON
    cpx #$FF
    bne !cda_has_weapon+

    // Bare hands: ability = 0
    lda #0
    sta tun_dig_ability
    rts

!cda_has_weapon:
    stx zp_temp0                // Save weapon slot_lo
    ldx #EQUIP_WEAPON
    jsr item_get_category_inv_x // Sets item_cur_page, A = it_category
    ldx zp_temp0                // X = weapon slot_lo
    cmp #ICAT_DIGGING
    beq !cda_dig_tool+

    // Regular weapon: ability = (STR >> 2) + max(0, PL_TODMG >> 1)
    lda zp_player_str
    lsr
    lsr                         // STR >> 2
    sta tun_dig_ability
    lda player_data + PL_TODMG
    bmi !cda_done+              // Negative TODMG -> skip (leave ability = STR>>2)
    lsr                         // TODMG >> 1
    clc
    adc tun_dig_ability
    bcc !cda_ok+
    lda #$FF                    // Cap at 255
!cda_ok:
    sta tun_dig_ability
!cda_done:
    rts

!cda_dig_tool:
    // Digging tool: ability = (STR >> 2) + base_bonus + (ego * 12)
    lda zp_player_str
    lsr
    lsr                         // STR >> 2
    sta tun_dig_ability

    lda item_cur_page
    bne !cda_done-              // All digging tools are Page 0 (#62,#63,#157..160)
    cpx #157
    bcc !cda_legacy_tool+
    cpx #161
    bcs !cda_done-
    lda dig_base_ext - 157,x
    clc
    adc tun_dig_ability
    bcc !cda_ext_ok+
    lda #$FF
!cda_ext_ok:
    sta tun_dig_ability
    rts

!cda_legacy_tool:
    // Add base bonus from table (#62 Shovel, #63 Pick)
    txa
    sec
    sbc #62                     // Index into dig_base_table (0=Shovel, 1=Pick)
    tax
    lda dig_base_table,x
    clc
    adc tun_dig_ability
    sta tun_dig_ability

    // Add ego bonus: ego * 12
    lda inv_ego + EQUIP_WEAPON
    and #EGO_ID_MASK
    beq !cda_done-              // ego=0, no bonus
    // Multiply ego (1 or 2) by 12
    // ego * 12 = ego * 8 + ego * 4
    sta zp_temp2                // save ego
    asl                         // *2
    asl                         // *4
    sta zp_temp3                // ego*4
    asl                         // *8
    clc
    adc zp_temp3                // *8 + *4 = *12
    clc
    adc tun_dig_ability
    bcc !cda_ego_ok+
    lda #$FF                    // Cap at 255
!cda_ego_ok:
    sta tun_dig_ability
    rts

dig_base_table:
    .byte 6, 20                 // Shovel base=6, Pick base=20
dig_base_ext:
    .byte 18, 32, 30, 44        // #157 Gnomish S, #158 Orcish P, #159 Dwarven S, #160 Dwarven P
