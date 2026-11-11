#importonce
// Apply/remove a deterministic equipment stat delta.
// Carry set equips; carry clear unequips. Raw arithmetic preserves drains.
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
