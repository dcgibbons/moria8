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
    // Bare hands and baseline: STR >> 2
    lda zp_player_str
    lsr
    lsr
    sta tun_dig_ability

    // Check equipped weapon
    ldx inv_item_id + EQUIP_WEAPON
    cpx #$FF
    beq !cda_done+

    stx zp_temp0                // Save weapon slot_lo
    ldx #EQUIP_WEAPON
    jsr item_get_category_inv_x // Sets item_cur_page, A = it_category
    ldx zp_temp0                // X = weapon slot_lo
    cmp #ICAT_DIGGING
    beq !cda_dig_tool+

    // Regular weapon: ability = (STR >> 2) + max(0, PL_TODMG >> 1)
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
    lda item_cur_page
    bne !cda_done-              // All digging tools are Page 0
    .assert "Digging tools 198..203 contiguous on Page 0", ITEM_SHOVEL == ITEM_PICK + 1 && ITEM_ORCISH_PICK == ITEM_PICK + 2 && ITEM_DWARVEN_PICK == ITEM_PICK + 3 && ITEM_GNOMISH_SHOVEL == ITEM_PICK + 4 && ITEM_DWARVEN_SHOVEL == ITEM_PICK + 5 && ITEM_PAGE_DWARVEN_SHOVEL == 0, true
    txa
    sec
    sbc #ITEM_SLOT_PICK
    cmp #6
    bcs !cda_done-
    tax
    lda dig_base_table,x
    clc
    adc tun_dig_ability
    bcc !cda_base_ok+
    lda #$FF
!cda_base_ok:
    sta tun_dig_ability
    cpx #2                      // Only base Pick (0) and Shovel (1) add tool ego * 12
    bcs !cda_done-

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
    .byte 20, 6, 32, 44, 18, 30 // Pick, Shovel, Orcish P, Dwarven P, Gnomish S, Dwarven S
