#importonce
// player_dig_ability.s — shared digging ability helpers.

// calc_dig_ability — Calculate digging ability (STR + tool/weapon bonus)
// Formula: (STR>>2) + base_bonus + (ego*12) for digging tools.
// Output: tun_dig_ability set
// Clobbers: A, X
calc_dig_ability:
    ldx inv_item_id + EQUIP_WEAPON
    cpx #FI_EMPTY
    bne !cda_has_weapon+

    lda #0
    sta tun_dig_ability
    rts

!cda_has_weapon:
#if HAL_PLATFORM_ITEM_CATALOG_BANKED
    jsr item_load_category_x
#else
    lda it_category,x
#endif
    cmp #ICAT_DIGGING
    beq !cda_dig_tool+

    lda zp_player_str
    lsr
    lsr
    sta tun_dig_ability
    lda player_data + PL_TODMG
    bmi !cda_done+
    lsr
    clc
    adc tun_dig_ability
    bcc !cda_ok+
    lda #$ff
!cda_ok:
    sta tun_dig_ability
!cda_done:
    rts

!cda_dig_tool:
    lda zp_player_str
    lsr
    lsr
    sta tun_dig_ability

    txa
    sec
    sbc #62
    tax
    lda dig_base_table,x
    clc
    adc tun_dig_ability
    sta tun_dig_ability

    lda inv_ego + EQUIP_WEAPON
    beq !cda_done-
    sta zp_temp2
    asl
    asl
    sta zp_temp3
    asl
    clc
    adc zp_temp3
    clc
    adc tun_dig_ability
    bcc !cda_ego_ok+
    lda #$ff
!cda_ego_ok:
    sta tun_dig_ability
    rts

dig_base_table:
    .byte 6, 20

// roll_tool_ego_check — Handle ego roll for digging tools.
// Called from roll_ego_type when category != ICAT_WEAPON.
// A = category value from it_category lookup
// Returns: A = ego type (0, 1, or 2)
// Clobbers: A, X
roll_tool_ego_check:
    cmp #ICAT_DIGGING
    bne !rtc_zero+
    lda zp_player_dlvl
    cmp #10
    bcc !rtc_zero+
    lda #100
    jsr rng_range
    cmp #10
    bcc !rtc_ego2+
    cmp #35
    bcc !rtc_ego1+
!rtc_zero:
    lda #0
    rts
!rtc_ego2:
    lda zp_player_dlvl
    cmp #20
    bcc !rtc_ego1+
    lda #2
    rts
!rtc_ego1:
    lda #1
    rts
