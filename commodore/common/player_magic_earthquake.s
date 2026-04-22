#importonce
// player_magic_earthquake.s — shared umoria-style Earthquake terrain effect

eq_cur_x: .byte 0
eq_cur_y: .byte 0
eq_rows_left: .byte 0
eq_cols_left: .byte 0
eq_changed: .byte 0
eq_mon_slot: .byte 0
eq_mon_alive: .byte 0
eq_saved_tile: .byte 0
eq_saved_flags: .byte 0

#if PM_EQ_BANKED
eff_earthquake_banked:
#else
eff_earthquake:
#endif
    lda #<eq_cast_msg
    sta zp_ptr0
    lda #>eq_cast_msg
    sta zp_ptr0_hi
    jsr msg_print

    lda #0
    sta eq_changed

    lda zp_player_y
    sec
    sbc #8
    sta eq_cur_y
    lda #17
    sta eq_rows_left
!eq_row:
    lda zp_player_x
    sec
    sbc #8
    sta eq_cur_x
    lda #17
    sta eq_cols_left
!eq_col:
    lda eq_cur_x
    cmp zp_player_x
    bne !eq_not_player+
    lda eq_cur_y
    cmp zp_player_y
    beq !eq_next+
!eq_not_player:
    lda eq_cur_x
    cmp #MAP_COLS
    bcs !eq_next+
    lda eq_cur_y
    cmp #MAP_ROWS
    bcs !eq_next+
    lda #8
    jsr rng_range
    bne !eq_next+
    jsr eq_process_tile
!eq_next:
    inc eq_cur_x
    dec eq_cols_left
    bne !eq_col-
    inc eq_cur_y
    dec eq_rows_left
    bne !eq_row-

    lda eq_changed
    beq !eq_done+
    lda #1
    sta vis_room_revealed
    sta turn_scene_dirty
!eq_done:
    rts

eq_cast_msg:
    .text "The earth trembles."
    .byte 0

eq_process_tile:
    jsr eq_remove_floor_items

    lda #0
    sta eq_mon_alive
    lda eq_cur_x
    ldy eq_cur_y
    jsr monster_find_at
    bcc !eq_no_monster+
    stx eq_mon_slot
    jsr eq_hit_monster
    bcc !eq_no_monster+
    lda #1
    sta eq_mon_alive
!eq_no_monster:
    ldx eq_cur_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy eq_cur_x
    :MapRead_ptr0_y()
    sta eq_saved_tile
    and #TILE_TYPE_MASK

    cmp #TILE_WALL_H
    beq !eq_wall_to_floor+
    cmp #TILE_WALL_V
    beq !eq_wall_to_floor+
    cmp #TILE_CORNER_TL
    beq !eq_wall_to_floor+
    cmp #TILE_CORNER_TR
    beq !eq_wall_to_floor+
    cmp #TILE_CORNER_BL
    beq !eq_wall_to_floor+
    cmp #TILE_CORNER_BR
    beq !eq_wall_to_floor+
    cmp #TILE_MAGMA
    beq !eq_wall_to_floor+
    cmp #TILE_QUARTZ
    beq !eq_wall_to_floor+
    cmp #TILE_SECRET
    beq !eq_wall_to_floor+
    cmp #TILE_FLOOR
    beq !eq_floor_to_wall+
    rts

!eq_wall_to_floor:
    jsr eq_tile_is_edge
    bcs eq_done_tile
    lda eq_saved_tile
    and #FLAG_VISITED
    sta eq_saved_flags
    lda eq_mon_alive
    beq !eq_wall_write+
    lda eq_saved_flags
    ora #FLAG_OCCUPIED
    sta eq_saved_flags
!eq_wall_write:
    ldy eq_cur_x
    lda #TILE_FLOOR
    ora eq_saved_flags
    :MapWrite_ptr0_y()
    lda #1
    sta eq_changed
eq_done_tile:
    rts

!eq_floor_to_wall:
    jsr eq_tile_is_edge
    bcs eq_done_tile
    lda #10
    jsr rng_range
    cmp #6
    bcc !eq_make_quartz+
    cmp #9
    bcc !eq_make_magma+
    lda #TILE_WALL_H
    bne !eq_wall_kind_ready+
!eq_make_quartz:
    lda #TILE_QUARTZ
    bne !eq_wall_kind_ready+
!eq_make_magma:
    lda #TILE_MAGMA
!eq_wall_kind_ready:
    pha
    lda eq_saved_tile
    and #(FLAG_VISITED | FLAG_LIT | FLAG_OCCUPIED)
    sta eq_saved_flags
    pla
    ldy eq_cur_x
    ora eq_saved_flags
    :MapWrite_ptr0_y()
    lda #1
    sta eq_changed
    rts

eq_remove_floor_items:
!eq_rfi_loop:
    lda eq_cur_x
    ldy eq_cur_y
    jsr floor_item_find_at
    bcc !eq_rfi_done+
    jsr floor_item_remove
    lda #1
    sta eq_changed
    jmp !eq_rfi_loop-
!eq_rfi_done:
    rts

eq_hit_monster:
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda cr_mflags,x
    and #CF_ATTACK_ONLY
    beq !eq_mon_roll+
    lda #<$0bb8
    sta zp_math_a
    lda #>$0bb8
    sta zp_math_b
    bne !eq_mon_apply+
!eq_mon_roll:
    lda #4
    ldx #8
    ldy #0
    jsr math_dice
!eq_mon_apply:
    ldx eq_mon_slot
    jsr combat_apply_damage_16
    bcc !eq_mon_alive+
    jsr eff_kill_monster
    lda #1
    sta eq_changed
    clc
    rts
!eq_mon_alive:
    lda #1
    sta eq_changed
    sec
    rts

eq_tile_is_edge:
    lda eq_cur_x
    beq !eq_edge_yes+
    cmp #MAP_COLS - 1
    beq !eq_edge_yes+
    lda eq_cur_y
    beq !eq_edge_yes+
    cmp #MAP_ROWS - 1
    beq !eq_edge_yes+
    clc
    rts
!eq_edge_yes:
    sec
    rts
