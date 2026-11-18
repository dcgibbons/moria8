#importonce
// monster_attack_effects.s — Phase 5 VMS Moria 4.8 attack verbs (2..19) and
// extended melee attack effects (ATK_LOSE_STR..WIS, ATK_CORRODE,
// ATK_STEAL_GOLD/ITEM, ATK_LOSE_EXP, ATK_DISENCHANT, ATK_EAT_FOOD/LIGHT/CHARGES).
//
// Module ownership:
//   - Hot resident (Default on all 7 ports, <= 470 B): 5-bit packed 19-verb
//     phrase unpacker, extended effect dispatcher, ATK_CORRODE, ATK_LOSE_STR..WIS,
//     mae_recalc_hp_combat, and unified 1-pass uniform reservoir slot picker.
//   - Cold zero-HP effects (mae_cold_body, ~445 B): ATK_STEAL_GOLD/ITEM,
//     ATK_LOSE_EXP, ATK_DISENCHANT, ATK_EAT_FOOD/LIGHT/CHARGES — placed in
//     resident banked RAM on C64/Plus4/Atari8 (RuntimeBanked) and C128
//     (RuntimeBankedCode), in HelpOverlay on Apple2/BBC/CX16, and in Default
//     in standalone unit tests (!PLATFORM_PRODUCT_OVERLAY_RUNTIME).

// ============================================================
// Compact 5-bit packed 19-verb screen-code phrase unpacker (ADESC 2..19)
// ADESC_NONE (0) and ADESC_HITS (1) use HSTR_MAT_HITS directly in monster_attack.s.
// 5-bit symbols: 1..26 = 'a'..'z' (C64 screen codes 1..26), 27 = ' ',
//   28 = "s you.", 29 = "s on you.", 30 = " you.", 31 = "."
// Output: zp_ptr2 -> hd_decode_buf (" <verb phrase>.")
// ============================================================
mon_atk_verb_to_ptr2:
    cmp #ADESC_INSULTS + 1
    bcc !mav_ok+
    lda #ADESC_BITES
!mav_ok:
    ldy #0
    sty zp_temp2                // Bitstream byte index
    sty zp_temp3                // Current shifted byte + sentinel
    sec
    sbc #2
    tax
    beq !mav_go+
!mav_sk:
    jsr mav_get5
    cmp #28
    bcc !mav_sk-
    dex
    bne !mav_sk-
!mav_go:
    lda #' '
    sta hd_decode_buf,x
    inx
!mav_cp:
    jsr mav_get5
    cmp #28
    bcs !mav_end+
    cmp #27
    bcc !mav_ch+
    lda #' '
!mav_ch:
    sta hd_decode_buf,x
    inx
    bne !mav_cp-
!mav_end:
    tay
    lda mav_off - 28,y
    tay
!mav_tl:
    lda mav_tail,y
    sta hd_decode_buf,x
    beq !mav_ptr+
    inx
    iny
    bne !mav_tl-
!mav_ptr:
    lda #<hd_decode_buf
    sta zp_ptr2
    lda #>hd_decode_buf
    sta zp_ptr2_hi
    rts

mav_get5:
    lda #$08                    // 5 shifts left -> C=1 and bits 7..5 == 0
!mg5_lp:
    pha
    lda zp_temp3
    asl
    sta zp_temp3
    bne !mg5_b+
    ldy zp_temp2
    inc zp_temp2
    lda mav_bits,y
    sec
    rol                         // Sentinel 1 in bit 0, MSB in C
    sta zp_temp3
!mg5_b:
    pla
    rol
    bcc !mg5_lp-
    rts
.assert "screencode 'z' == 26", 'z', 26

mav_off:  .byte 0, 7, 11, 15
mav_tail: .text "s you." ; .byte 0 ; .text "s on you." ; .byte 0
mav_bits:
    .byte $12, $68, $5e, $0d, $81, $bf, $27, $44, $b8, $fc, $a3, $ea, $34, $17, $8b, $48
    .byte $d7, $c3, $87, $45, $9e, $c3, $4f, $0a, $45, $0d, $10, $5e, $ce, $09, $a7, $5a
    .byte $15, $96, $7b, $0e, $d0, $f9, $49, $22, $61, $77, $70, $a5, $9f, $2b, $45, $20
    .byte $8c, $bc, $1c, $83, $76, $76, $45, $61, $43, $32, $cf, $61, $d8, $d8, $fa, $93
    .byte $6f, $36, $e7, $07, $c8, $b3, $f8, $8a, $79, $ef, $2f, $ae, $cc, $f9, $6d, $af
    .byte $71, $73, $f9, $b1, $2d, $2f, $07, $2a, $cd, $05, $e5, $24, $16, $c1, $85, $e1
    .byte $24, $f7, $b3, $a9, $74, $ea, $ca, $70

// ============================================================
// Extended ATK_* Effect Dispatcher (Default resident)
// Input: A = mat_atk_type (2, 9, 12, 13, 15..24)
// ============================================================
mae_mode:        .byte 0        // Shared with mae_tmp (non-overlapping lifetimes)
.label mae_tmp = mae_mode
mae_idx:         .byte 0
mae_dmg_lo:      .byte 0
mae_recalc_pend: .byte 0

mon_atk_effect_ext:
    cmp #ATK_LOSE_STR
    beq mae_lose_str
    cmp #ATK_CORRODE
    beq mae_corrode
    cmp #ATK_LOSE_DEX
    bcc !maee_cold+             // 12..13: STEAL_GOLD / STEAL_ITEM
    cmp #ATK_LOSE_EXP
    bcc mae_lose_stat           // 15..18: LOSE_DEX/CON/INT/WIS
!maee_cold:
    // Zero-HP cold effects (12, 13, 19..24)
    ldy zp_combat_dmg
    sty mae_dmg_lo
    ldx #0
    stx zp_combat_dmg
    stx mae_recalc_pend
    jsr mae_cold_call
    lda mae_recalc_pend
    beq !mc_done+
    jmp mat_recalc_equip

// ============================================================
// ATK_CORRODE (9) — VMS corrode_gas (moria.inc:1672): minus_ac, else +1d8 HP
// ============================================================
mae_corrode:
    ldx #HSTR_DF_POISON_GAS
    jsr huff_print_msg
    jsr mon_atk_acid_armour
    bcs !mc_done+
    lda #8
    jsr rng_range
    sec
    adc zp_combat_dmg
    bcc !mc_st+
    lda #255
!mc_st:
    sta zp_combat_dmg
!mc_done:
    rts

// ============================================================
// Stat Drains: ATK_LOSE_STR (2, 50% when unsustained) & 15..18 (DEX/CON/INT/WIS)
// AC-reduced HP damage + decrement_stat on PL_*_CUR, blocked by player_sust_mask.
// ============================================================
mae_stat_idx: .byte 3, 4, 1, 2  // 15=DEX(3), 16=CON(4), 17=INT(1), 18=WIS(2)
mae_sust_bit: .byte SUST_STR, SUST_INT, SUST_WIS, SUST_DEX, SUST_CON

mae_lose_str:
    ldy #0
    beq !mls_go+
mae_lose_stat:
    tax
    ldy mae_stat_idx - ATK_LOSE_DEX,x
!mls_go:
    sty mae_tmp
    jsr mon_atk_ac_reduce
    ldy mae_tmp
    lda mae_sust_bit,y
    and player_sust_mask
    beq !mls_unsust+
    ldx #HSTR_CHEST_UNAFFECTED
    jmp huff_print_msg
!mls_unsust:
    cpy #0                      // VMS creature.inc case 2: randint(2) = 1
    bne !mls_drain+
    jsr rng_byte
    lsr
    bcs !mc_done-
!mls_drain:
    ldy mae_tmp
    lda player_data + PL_STR_CUR,y
    jsr decrement_stat
    ldy mae_tmp
    sta player_data + PL_STR_CUR,y
    sta zp_player_str,y
    jsr mae_recalc_hp_combat
    ldx #HSTR_DF_CON_DRAIN
    jmp huff_print_msg

mae_recalc_hp_combat:
    jsr player_calc_combat
    jsr player_calc_hp          // Returns A = player_data + PL_MHP_HI
    sta zp_player_mhp_hi
    ldx player_data + PL_MHP_LO
    stx zp_player_mhp_lo
    cpx zp_player_hp_lo
    sbc zp_player_hp_hi
    bcs !msm_ok+
    stx zp_player_hp_lo
    stx player_data + PL_HP_LO
    lda zp_player_mhp_hi
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
!msm_ok:
    rts

// ============================================================
// Unified 1-pass uniform reservoir slot picker (Default resident)
// Mode $00: pack (0..21) any item; Mode $01: pack food; Mode $02: pack charged wand/staff;
// Mode $80: armour (maea_slots[0..5]) any worn piece.
// Output: Z=0 and X = mat_acid_slot = chosen slot if found; Z=1 if none match.
// ============================================================
mae_pick_slot:
    sta mae_mode
    ldy #0                      // Y = matching slot count
    ldx #MAX_INV_SLOTS - 1
    asl                         // Bit 7 ($80) -> C=1
    bcc !mps_lp+
    ldx #5
!mps_lp:
    stx mae_idx
    bit mae_mode
    bpl !mps_chk+
    lda maea_slots,x
    tax
!mps_chk:
    jsr mae_slot_ok
    bcc !mps_nx+
    stx zp_temp0
    iny
    tya
    jsr rng_range               // Preserves Y & zp_temp0; Z=1 iff A==0 (prob 1/Y)
    bne !mps_nx+
    lda zp_temp0
    sta mat_acid_slot
!mps_nx:
    ldx mae_idx
    dex
    bpl !mps_lp-
    ldx mat_acid_slot
    tya
    rts

mae_slot_ok:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !mso_no+
    lda mae_mode
    beq !mso_yes+               // Mode $00: any non-empty pack slot
    bmi !mso_yes+               // Mode $80: any non-empty armour slot
    lsr                         // Mode $01 -> Z=1,C=1; Mode $02 -> A=1,C=0
    beq !mso_food+
    lda inv_p1,x                // Mode $02: charged wand/staff
    beq !mso_no+
    jsr item_get_category_inv_x // Preserves X, Y
    sec
    sbc #ICAT_WAND
    cmp #2
    bcc !mso_yes+
!mso_no:
    clc
    rts
!mso_food:
    jsr item_get_category_inv_x
    cmp #ICAT_FOOD
    bne !mso_no-
!mso_yes:
    sec
    rts
.assert "ICAT_STAFF immediately follows ICAT_WAND", ICAT_STAFF, ICAT_WAND + 1

// ============================================================
// Platform-safe resident bridge to mae_cold_body
// Input: A = mat_atk_type (preserved from mon_atk_effect_ext)
// ============================================================
mae_cold_call:
#if !PLATFORM_PRODUCT_OVERLAY_RUNTIME || HAL_PLATFORM_RUNTIME_BANKED_ALWAYS_VISIBLE
    jmp mae_cold_body
#elif HAL_PLATFORM_MONSTER_BANK1_TIER_NAMES
    cmp #ATK_LOSE_EXP
    bcc !mcc_items+             // 12..13 -> ItemActionsOverlay (cached #7)
    cmp #ATK_DISENCHANT
    bcc !mcc_bank+              // 19..20 -> RuntimeBankedCode ($F000)
    ldx #OVL_HOME               // 21..24 -> HomeOverlay (#11)
    .byte $2c
!mcc_items:
    ldx #OVL_ITEMS
    lda current_overlay
    pha
    txa
    jsr overlay_load
    bcs !mcc_rest+
    jsr mae_cold_body
!mcc_rest:
    pla
    beq !mcc_ret+
    jmp overlay_load
!mcc_bank:
    jmp mae_cold_body
!mcc_ret:
    rts
#elif HAL_PLATFORM_HUFFMAN_DATA_AUX
    lda current_overlay
    pha
    lda #OVL_HELP
    jsr overlay_load
    bcs !mcc_skip+
    jsr mae_cold_body
!mcc_skip:
    pla
    beq !mcc_done+
    jmp overlay_load
!mcc_done:
    rts
#elif HAL_PLATFORM_MONSTER_CPU_PORT_BANK
    php
    sei
    lda hal_memory_cpu_port
    pha
    lda #BANK_NO_KERNAL
    sta hal_memory_cpu_port
    jsr mae_cold_body
    pla
    sta hal_memory_cpu_port
    plp
    rts
#else
    php
    sei
    jsr plus4_bank_ram
    jsr mae_cold_body
    jsr plus4_bank_ram
    plp
    rts
#endif

// ============================================================
// Cold segment switch for mae_cold_body (restored to Default at EOF)
// ============================================================
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
#if HAL_PLATFORM_MONSTER_BANK1_TIER_NAMES
.segment RuntimeBankedCode
#elif HAL_PLATFORM_HUFFMAN_DATA_AUX
.segment HelpOverlay
#else
.segment RuntimeBanked
#endif
#endif

mae_cold_body:
    lda mat_atk_type
    cmp #ATK_LOSE_EXP
    bcc !mcb_stl+               // 12..13: STEAL_GOLD / STEAL_ITEM
    beq !mcb_exp+               // 19: LOSE_EXP
    cmp #ATK_DISENCHANT
    bcc !mcb_agg+               // 20: AGGRAVATE
    beq !mcb_dis+               // 21: DISENCHANT
    cmp #ATK_EAT_LIGHT
    bcc !mcb_food+              // 22: EAT_FOOD
    beq !mcb_light+             // 23: EAT_LIGHT
    jmp mae_eat_charges         // 24: EAT_CHARGES
!mcb_stl:
    jmp mae_steal
!mcb_agg:
    jmp mon_atk_effect_aggravate
!mcb_exp:
    jmp mae_lose_exp
!mcb_dis:
    jmp mae_disenchant
!mcb_food:
    jmp mae_eat_food
!mcb_light:
    jmp mae_eat_light

// ============================================================
// ATK_STEAL_GOLD (12) & ATK_STEAL_ITEM (13) — VMS creature.inc:498-534
// ============================================================
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME && HAL_PLATFORM_MONSTER_BANK1_TIER_NAMES
.segment ItemActionsOverlay
#endif
mae_steal:
    lda zp_eff_paralyze
    bne !ms_theft+
    lda #124
    jsr rng_range
    clc
    adc #1                      // randint(124) in 1..124
    cmp zp_player_dex
    bcc !ms_blink+              // Anti-theft roll succeeded!
!ms_theft:
    lda mat_atk_type
    cmp #ATK_STEAL_ITEM
    beq !ms_item+
    ldy #PL_GOLD_0
    lda #10
    jsr mae_load_ccl_div        // ccl_adj_0..2 = au div 10
    lda #25
    jsr rng_range
    clc
    adc #1                      // 1..25 = randint(25)
    ldx #0
    ldy #PL_GOLD_0
    jsr mae_add_sub24
    jmp !ms_blink+
!ms_item:
    lda #0                      // Mode 0: any non-empty pack slot
    jsr mae_pick_slot
    beq !ms_blink+
    jsr inv_consume_one
!ms_blink:
    jsr rng_byte                // VMS randint(2) = 1: 50% blink away
    lsr
    bcs !ms_done+
    jsr find_random_floor
    bcc !ms_done+
    ldx zp_mon_y
    ldy zp_mon_x
    jsr mae_toggle_occ
    ldx df_target_y
    ldy df_target_x
    jsr mae_toggle_occ
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #1
!ms_pos:
    lda df_target_x,y
    sta zp_mon_x,y
    sta (zp_ptr0),y
    dey
    bpl !ms_pos-
    lda zp_mon_flags
    and #~MF_VISIBLE & $ff
    sta zp_mon_flags
    ldy #MX_FLAGS
    sta (zp_ptr0),y
    inc zp_dirty_count
!ms_done:
    rts
.assert "MX_X=0, MX_Y=1 and zp_mon_y=zp_mon_x+1", MX_X == 0 && MX_Y == 1 && zp_mon_y == zp_mon_x + 1, true

mae_toggle_occ:
    jsr map_row_ptr0_x          // Preserves Y
    :MapRead_ptr0_y()
    eor #FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    rts

// ============================================================
// ATK_LOSE_EXP (19) — VMS creature.inc:583-588, spells.inc lose_exp
// ============================================================
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME && HAL_PLATFORM_MONSTER_BANK1_TIER_NAMES
.segment RuntimeBankedCode
#endif
mae_lose_exp:
    ldy #PL_XP_0
    lda #100
    jsr mae_load_ccl_div        // ccl_adj_0..2 = PL_XP div 100
    asl ccl_adj_0               // * 2 (VMS mon$drain_life = 2)
    rol ccl_adj_1
    rol ccl_adj_2
    lda mae_dmg_lo
    ldx mad_dmg_hi
    ldy #PL_XP_0
    jsr mae_add_sub24
    bcs !mle_lvl_lp+
    sta player_data + PL_XP_FRAC_LO
    sta player_data + PL_XP_FRAC_HI
!mle_lvl_lp:
    lda zp_player_lvl
    cmp #2
    bcc !mle_done+
    dec zp_player_lvl
    jsr combat_compute_level_threshold
    lda player_data + PL_XP_0
    cmp ccl_adj_0
    lda player_data + PL_XP_1
    sbc ccl_adj_1
    lda player_data + PL_XP_2
    sbc ccl_adj_2
    bcc !mle_drop+
    inc zp_player_lvl
    bcs !mle_done+
!mle_drop:
    lda zp_player_lvl
    sta player_data + PL_LEVEL
    jsr mae_recalc_hp_combat
    jmp !mle_lvl_lp-
!mle_done:
    ldx #HSTR_DF_CON_DRAIN
    jmp huff_print_msg

// ============================================================
// ATK_DISENCHANT (21) — VMS creature.inc:590-623
// Pick 1 random worn equipment slot in {WEAPON, BODY, SHIELD, HEAD, HANDS, FEET, CLOAK};
// lower any positive to_hit, to_dam, to_ac by randint(2) floored at 0 + stage recalc.
// ============================================================
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME && HAL_PLATFORM_MONSTER_BANK1_TIER_NAMES
.segment HomeOverlay
#endif
mae_disenchant:
    lda #7
    jsr rng_range               // 0..6
    cmp #6
    bcc !md_slot+
    lda #EQUIP_CLOAK - EQUIP_WEAPON - 1 // C=1: + EQUIP_WEAPON + 1 = EQUIP_CLOAK
!md_slot:
    adc #EQUIP_WEAPON
    tay
    lda inv_item_id,y
    cmp #FI_EMPTY
    beq !md_done+
    tya
    clc
    adc #2 * TOTAL_INV_SLOTS    // Start at inv_to_ac,y (90..100), step -34 x 3
!md_lp:
    tay
    lda inv_to_hit,y
    bmi !md_nx+
    beq !md_nx+
    inc mae_recalc_pend
    pha
    jsr rng_byte                // Preserves Y
    lsr
    pla
    sbc #1                      // -1 or -2 (randint(2))
    bpl !md_st+
    lda #0
!md_st:
    sta inv_to_hit,y
!md_nx:
    tya
    sec
    sbc #TOTAL_INV_SLOTS
    bpl !md_lp-                 // 90..100 -> 56..66 -> 22..32 -> -12..-2 (bmi exits!)
    lda mae_recalc_pend
    beq !md_done+
    ldx #HSTR_PIQ_AIR_CRACKLE
    jmp huff_print_msg
!md_done:
    rts
.assert "inv_to_hit/dam/ac contiguous & fit <128", inv_to_dam == inv_to_hit + TOTAL_INV_SLOTS && inv_to_ac == inv_to_dam + TOTAL_INV_SLOTS && EQUIP_CLOAK + 2 * TOTAL_INV_SLOTS < 128 && EQUIP_WEAPON < TOTAL_INV_SLOTS, true

// ============================================================
// ATK_EAT_FOOD (22), ATK_EAT_LIGHT (23), ATK_EAT_CHARGES (24)
// ============================================================
mae_eat_food:
    lda #1                      // Mode 1: ICAT_FOOD
    jsr mae_pick_slot
    beq !mef_ret+
    jmp inv_consume_one
!mef_ret:
    rts

mae_eat_light:
    lda inv_item_id + EQUIP_LIGHT
    cmp #FI_EMPTY
    beq !mef_ret-
    lda inv_p1 + EQUIP_LIGHT
    beq !mef_ret-
    lda #9
    jsr rng_range               // C=0 on exit (A < zp_temp4)
    adc #8                      // 8..16 charges (~240..480 turns)
    sta zp_temp0
    lda inv_p1 + EQUIP_LIGHT
    sec
    sbc zp_temp0
    bcc !mel_flr+
    bne !mel_st+
!mel_flr:
    lda #1
!mel_st:
    sta inv_p1 + EQUIP_LIGHT
    ldx #HSTR_TTL_DIM
    jmp huff_print_msg

mae_eat_charges:
    lda #2                      // Mode 2: charged wand/staff
    jsr mae_pick_slot
    beq !mef_ret-
    ldy inv_p1,x
    lda #0
    sta inv_p1,x
    tya
    tax                         // X = drained charges
    ldy mat_type2
    lda cr_level,y
    jsr math_multiply           // zp_math_b:zp_math_a = cr_level * charges
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    clc
    adc zp_math_a
    sta (zp_ptr0),y
    iny                         // MX_HP_HI == MX_HP_LO + 1
    lda (zp_ptr0),y
    adc zp_math_b
    bpl !mec_ok+
    lda #$ff
    dey
    sta (zp_ptr0),y
    iny
    lda #$7f
!mec_ok:
    sta (zp_ptr0),y
    ldx #HSTR_PIQ_VIBRATION
    jmp huff_print_msg

// mae_load_ccl_div — ccl_adj_0..2 = player_data[Y..Y+2] div A
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME && HAL_PLATFORM_MONSTER_BANK1_TIER_NAMES
.segment RuntimeBankedCode
#endif
mae_load_ccl_div:
    sta ccl_divisor
    ldx #0
!mlcd_lp:
    lda player_data,y
    sta ccl_adj_0,x
    iny
    inx
    cpx #3
    bcc !mlcd_lp-
    jmp ccl_div_24x8

// mae_add_sub24 — ccl_adj_0..2 += X:A, then player_data[Y..Y+2] = max(0, val - ccl_adj_0..2)
mae_add_sub24:
    clc
    adc ccl_adj_0
    sta ccl_adj_0
    txa
    adc ccl_adj_1
    sta ccl_adj_1
    bcc !mas24_sub+
    inc ccl_adj_2
!mas24_sub:
    lda #3
    sta ccl_divisor
    ldx #0
    sec
!ms24_lp:
    lda player_data,y
    sbc ccl_adj_0,x
    sta player_data,y
    iny
    inx
    dec ccl_divisor             // Preserves C from sbc!
    bne !ms24_lp-
    bcs !ms24_ok+
    lda #0
!ms24_zr:
    dey
    sta player_data,y
    dex
    bne !ms24_zr-
!ms24_ok:
    rts
.assert "ccl_adj_0..2 are contiguous", ccl_adj_1 == ccl_adj_0 + 1 && ccl_adj_2 == ccl_adj_1 + 1, true

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
.segment Default
#endif
