#importonce
// player_combat_calc.s — shared combat/stat recalculation helpers.

// Umoria combat/stat adjustment helpers. These intentionally do not use
// stat_bonus_index because exceptional 18/xx values have distinct thresholds.
#if !C128_PLAYER_STAT_HELPERS_EXTERNAL
player_adj_m4:
    lda #<-4
    rts
player_adj_m3:
    lda #<-3
    rts
player_adj_m2:
    lda #<-2
    rts
player_adj_m1:
    lda #<-1
    rts
player_adj_0:
    lda #0
    rts
player_adj_1:
    lda #1
    rts
player_adj_2:
    lda #2
    rts
player_adj_3:
    lda #3
    rts
player_adj_4:
    lda #4
    rts
player_adj_5:
    lda #5
    rts
player_adj_6:
    lda #6
    rts

player_str_tohit_adj:
    cmp #4
    bcc player_adj_m3
    cmp #5
    bcc player_adj_m2
    cmp #7
    bcc player_adj_m1
    cmp #18
    bcc player_adj_0
    cmp #94
    bcc player_adj_1
    cmp #109
    bcc player_adj_2
    cmp #117
    bcc player_adj_3
    bcs player_adj_4

player_str_damage_adj:
    cmp #4
    bcc player_adj_m2
    cmp #5
    bcc player_adj_m1
    cmp #16
    bcc player_adj_0
    cmp #17
    bcc player_adj_1
    cmp #18
    bcc player_adj_2
    cmp #94
    bcc player_adj_3
    cmp #109
    bcc player_adj_4
    cmp #117
    bcc player_adj_5
    bcs player_adj_6

player_dex_tohit_adj:
    cmp #4
    bcc player_adj_m3
    cmp #6
    bcc player_adj_m2
    cmp #8
    bcc player_adj_m1
    cmp #16
    bcc player_adj_0
    cmp #17
    bcc player_adj_1
    cmp #18
    bcc player_adj_2
    cmp #69
    bcc player_adj_3
    cmp #118
    bcc player_adj_4
    bcs player_adj_5

player_adj2_m4:
    lda #<-4
    rts
player_adj2_m3:
    lda #<-3
    rts
player_adj2_m2:
    lda #<-2
    rts
player_adj2_m1:
    lda #<-1
    rts
player_adj2_0:
    lda #0
    rts
player_adj2_1:
    lda #1
    rts
player_adj2_2:
    lda #2
    rts
player_adj2_3:
    lda #3
    rts
player_adj2_4:
    lda #4
    rts
player_adj2_5:
    lda #5
    rts

player_dex_ac_adj:
    cmp #4
    bcc player_adj2_m4
    cmp #5
    bcc player_adj2_m3
    cmp #6
    bcc player_adj2_m2
    cmp #7
    bcc player_adj2_m1
    cmp #15
    bcc player_adj2_0
    cmp #18
    bcc player_adj2_1
    cmp #59
    bcc player_adj2_2
    cmp #94
    bcc player_adj2_3
    cmp #117
    bcc player_adj2_4
    bcs player_adj2_5

player_con_hp_adj:
    cmp #7
    bcs !check17+
    sec
    sbc #7
    rts
!check17:
    cmp #17
    bcc player_adj2_0
    cmp #18
    bcc player_adj2_1
    cmp #94
    bcc player_adj2_2
    cmp #117
    bcc player_adj2_3
    bcs player_adj2_4
#endif

// player_calc_combat — Calculate combat bonuses from current stats
// Updates: PL_TOHIT, PL_TODMG, PL_AC (dex bonus portion), PL_BLOWS
// Preserves: nothing
player_calc_combat:
    // STR to-hit bonus
    lda player_data + PL_STR_CUR
    jsr player_str_tohit_adj
    sta zp_temp0            // Accumulate to-hit

    // DEX to-hit bonus
    lda player_data + PL_DEX_CUR
    jsr player_dex_tohit_adj
    clc
    adc zp_temp0
    sta player_data + PL_TOHIT

    // STR damage bonus
    lda player_data + PL_STR_CUR
    jsr player_str_damage_adj
    sta player_data + PL_TODMG

    // AC = DEX bonus + equipment AC (base + split to_ac)
    // Start with DEX AC bonus (signed)
    lda player_data + PL_DEX_CUR
    jsr player_dex_ac_adj
    sta pcc_ac_accum            // Signed accumulator (may be negative)

    // Loop armor-relevant equipment slots: body through current equipment end.
    ldx #EQUIP_BODY
!ac_equip_loop:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ac_next_slot+
    // Add base AC for this item type
    tay                         // Y = item type ID
#if HAL_PLATFORM_ITEM_CATALOG_BANKED
    jsr item_load_base_ac_y
#else
    lda it_base_ac,y
#endif
    clc
    adc pcc_ac_accum
    sta pcc_ac_accum
    // Add split AC bonus (signed)
    lda inv_to_ac,x
    clc
    adc pcc_ac_accum
    sta pcc_ac_accum
!ac_next_slot:
    inx
    cpx #EQUIP_END             // Past last armor-relevant slot
    bne !ac_equip_loop-

    // Clamp AC to [0, 60]
    lda pcc_ac_accum
    bmi !ac_zero+               // Negative -> 0
    cmp #61
    bcc !ac_store+
    lda #60                     // Cap at 60
    jmp !ac_store+
!ac_zero:
    lda #0
!ac_store:
    sta player_data + PL_AC

    // Blows: simplified lookup
    // Weight class based on STR (higher STR = lighter effective weight)
    // For now, default to 1 blow until weapons are implemented
    lda #1
    sta player_data + PL_BLOWS

    rts

// Scratch for player_calc_combat
pcc_ac_accum: .byte 0          // AC accumulator (signed during calculation)
