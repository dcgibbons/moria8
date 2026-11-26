#importonce
// player_adjust_equipment_stat.s — Apply/remove a deterministic equipment stat
// delta (carry set equips; carry clear unequips; raw arithmetic preserves drains).
// Owner: Default resident on C64, Plus/4, and Atari 8-bit; C128ResidentWorld
// (128.world) on C128; A2PlaySlot (a2.play) on Apple IIe; ItemActionsOverlay
// (OVL.ITEMS) on CX16. (BBC Master defines its equivalent in BeebPlaySlot+OVL.ITEMS.)
// Lifetime: one call per wield/wear/takeoff/exchange or player_recalc_equipment.
// Callers: player_recalc_equipment.s and player_item_commands.s (both in
// OVL.ITEMS on CX16, reached externally via tramp_item_recalc; resident or in
// OVL.ITEMS on the four Default/128.world ports). Calls resident equip_stat_mask_x
// and player_apply_stat_delta_y.
player_adjust_equipment_stat:
#if !HAL_PLATFORM_COMPACT_PLAY_SLOT
    ldx piw_equip
#endif
    lda inv_p1,x
    beq !paes_done+
    bcs !paes_store+
    eor #$ff
    adc #1                      // carry clear: -p1
!paes_store:
    sta stat_work
    jsr equip_stat_mask_x       // A = 6-bit mask (bit 0=STR..5=CHR), preserves X
    beq !paes_done+
    ldy #0
!paes_bit:
    lsr
    bcc !paes_skip+
    pha
    lda stat_work
    jsr player_apply_stat_delta_y
    cpy #PL_CON_CUR - PL_STR_CUR
    bne !paes_pop+
    txa
    pha
    jsr player_calc_hp
    pla
    tax
    ldy #PL_CON_CUR - PL_STR_CUR
!paes_pop:
    pla
!paes_skip:
    beq !paes_done+
    iny
    cpy #STAT_COUNT
    bcc !paes_bit-
!paes_done:
    rts
