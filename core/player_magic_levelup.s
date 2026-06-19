#importonce
// player_magic_levelup.s — level-up spell-learning helper
//
// Imported into the C64 main segment and the C128 low-runtime segment.
// Kept separate so C128 does not leave the level-up path in the I/O hole.

// ============================================================
// magic_check_new_spells — Recompute how many spells/prayers the player can learn
// Called on level-up after mana recalculation.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr2
// ============================================================
mcns_allowed:    .byte 0
mcns_known:      .byte 0
mcns_learnable:  .byte 0
mcns_stat_adj:   .byte 0

magic_check_new_spells:
    lda #0
    sta player_data + PL_NEW_SPELLS
    lda player_data + PL_SPELL_TYPE
    bne !mcns_has_type+
    rts
!mcns_has_type:
    sta pm_spell_type
    jsr pm_setup_active_tables

    ldx player_data + PL_CLASS
    lda class_spell_min_level,x
    cmp zp_player_lvl
    beq !mcns_level_ok+
    bcc !mcns_level_ok+
    rts
!mcns_level_ok:

    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !mcns_wis+
    lda player_data + PL_INT_CUR
    jmp !mcns_stat+
!mcns_wis:
    lda player_data + PL_WIS_CUR
!mcns_stat:
    jsr mcns_get_stat_adj
    sta mcns_stat_adj

    lda zp_player_lvl
    sec
    sbc class_spell_min_level,x
    clc
    adc #1
    sta zp_temp0

    lda mcns_stat_adj
    cmp #1
    bcc !mcns_no_spells+
    cmp #4
    bcc !mcns_allowed_levels+
    cmp #6
    bcc !mcns_allowed_three_halves+
    cmp #6
    beq !mcns_allowed_double+
    lda zp_temp0
    asl
    clc
    adc zp_temp0
    lsr
    jmp !mcns_cap_total+
!mcns_allowed_levels:
    lda zp_temp0
    jmp !mcns_cap_total+
!mcns_allowed_three_halves:
    lda zp_temp0
    asl
    clc
    adc zp_temp0
    lsr
    jmp !mcns_cap_total+
!mcns_allowed_double:
    lda zp_temp0
    asl
    jmp !mcns_cap_total+
!mcns_no_spells:
    lda #0
    sta mcns_allowed
    rts
!mcns_cap_total:
    sta mcns_allowed
    cmp class_spell_total,x
    bcc !mcns_count_known+
    lda class_spell_total,x
    sta mcns_allowed

!mcns_count_known:
    lda #<player_data + PL_SPELLS_LEARNT_0
    sta zp_ptr0
    lda #>player_data + PL_SPELLS_LEARNT_0
    sta zp_ptr0_hi
    jsr spell_mask_count_ptr
    sta mcns_known

    lda #0
    sta mcns_learnable
    ldx #0
!mcns_scan_spells:
    cpx #SPELL_CATALOG_COUNT
    bcs !mcns_finish+
    lda pm_lvl_tbl_lo
    sta zp_ptr0
    lda pm_lvl_tbl_hi
    sta zp_ptr0_hi
    txa
    tay
    lda (zp_ptr0),y
    cmp #99
    beq !mcns_next_spell+
    cmp zp_player_lvl
    beq !mcns_known_check+
    bcc !mcns_known_check+
!mcns_next_spell:
    inx
    jmp !mcns_scan_spells-
!mcns_known_check:
    lda #<player_data + PL_SPELLS_LEARNT_0
    sta zp_ptr0
    lda #>player_data + PL_SPELLS_LEARNT_0
    sta zp_ptr0_hi
    txa
    jsr spell_mask_test_ptr
    bcs !mcns_next_spell-
    inc mcns_learnable
    inx
    jmp !mcns_scan_spells-

!mcns_finish:
    lda mcns_allowed
    sec
    sbc mcns_known
    bcs !mcns_positive+
    lda #0
!mcns_positive:
    cmp mcns_learnable
    bcc !mcns_store+
    lda mcns_learnable
!mcns_store:
    sta player_data + PL_NEW_SPELLS
    rts

mcns_get_stat_adj:
    cmp #8
    bcc !mcns_adj_0+
    cmp #15
    bcc !mcns_adj_1+
    cmp #18
    bcc !mcns_adj_2+
    cmp #68
    bcc !mcns_adj_3+
    cmp #88
    bcc !mcns_adj_4+
    cmp #108
    bcc !mcns_adj_5+
    cmp #118
    bcc !mcns_adj_6+
    lda #7
    rts
!mcns_adj_6:
    lda #6
    rts
!mcns_adj_5:
    lda #5
    rts
!mcns_adj_4:
    lda #4
    rts
!mcns_adj_3:
    lda #3
    rts
!mcns_adj_2:
    lda #2
    rts
!mcns_adj_1:
    lda #1
    rts
!mcns_adj_0:
    lda #0
    rts
