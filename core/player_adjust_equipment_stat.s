#importonce
// player_adjust_equipment_stat.s — Apply/remove a deterministic equipment stat
// delta (carry set equips; carry clear unequips; raw arithmetic preserves drains).
// Owner: Default resident on C64, Plus/4, and Atari 8-bit; C128ResidentWorld
// (128.world) on C128; ItemActionsOverlay (OVL.ITEMS) on CX16. (Apple IIe and
// BBC Master define platform-specific equivalents in A2PlaySlot+OVL.ITEMS and
// OVL.ITEMS respectively rather than importing this file.)
// Lifetime: one call per wield/wear/takeoff/exchange or player_recalc_equipment.
// Callers: player_recalc_equipment.s and player_item_commands.s (both in
// OVL.ITEMS on CX16, reached externally via tramp_item_recalc; resident or in
// OVL.ITEMS on the four Default/128.world ports). Calls resident equip_stat_index.
player_adjust_equipment_stat:
#if !HAL_PLATFORM_COMPACT_PLAY_SLOT
    ldx piw_equip
#endif
    lda inv_p1,x
    bcs !paes_store+
    eor #$ff
    adc #1                      // carry clear: -p1
!paes_store:
    sta stat_work
    jsr equip_stat_index
    bcc !paes_done+
    lda player_data + PL_STR_CUR,y
    clc
    adc stat_work
    sta player_data + PL_STR_CUR,y
!paes_done:
    rts
