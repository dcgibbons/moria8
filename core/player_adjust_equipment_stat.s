#importonce
// Apply/remove a deterministic equipment stat delta.
// Carry set equips; carry clear unequips. Raw arithmetic preserves drains.
player_adjust_equipment_stat:
#if !APPLE2
    ldx piw_equip
#endif
    lda inv_p1,x
    bcs !paes_store+
    eor #$ff
    clc
    adc #1
!paes_store:
    sta stat_work
    lda inv_item_id,x
    cmp #ITEM_TYPE_RING_STRENGTH
    beq !paes_str+
    cmp #ITEM_TYPE_AMULET_WISDOM
    beq !paes_wis+
    cmp #ITEM_TYPE_AMULET_MAGI
    bne !paes_done+
    ldx #PL_INT_CUR - PL_STR_CUR
    bne !paes_apply+
!paes_str:
    ldx #0
    beq !paes_apply+
!paes_wis:
    ldx #PL_WIS_CUR - PL_STR_CUR
!paes_apply:
    lda player_data + PL_STR_CUR,x
    clc
    adc stat_work
    sta player_data + PL_STR_CUR,x
!paes_done:
    rts
