#importonce
// eff_destroy_traps_doors128.s — Cold Destroy Traps/Doors spell effect body
// hosted in C128's Bank 1-cached DungeonGenOverlay (ovl.gen), reached via
// resident eff_destroy_traps_doors -> c128_call_gen_preserve_ovl (restores
// DeathOverlay on return).

eff_destroy_traps_doors_ovl:
    lda #0
    sta adj_dir_idx
!edtd_tile_loop:
    lda adj_dir_idx
    cmp #8
    bcs !edtd_tiles_done+
    tax
    jsr df_target_from_dir
    jsr !edtd_tile_cb+
    inc adj_dir_idx
    jmp !edtd_tile_loop-
!edtd_tiles_done:
    jsr !edtd_remove_adjacent_traps+
    lda #1
    sta vis_room_revealed
    rts

!edtd_tile_cb:
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    sta zp_temp0

    cmp #TILE_TRAP
    bne !edtd_check_door+
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_FLOOR
    :MapWrite_ptr0_y()
    rts

!edtd_check_door:
    lda zp_temp0
    cmp #TILE_DOOR_CLOSED
    beq !edtd_open_door+
    cmp #TILE_SECRET
    bne !edtd_tile_done+

!edtd_open_door:
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_OPEN
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
    lda df_target_x
    ldy df_target_y
    jsr door_state_clear_at
!edtd_tile_done:
    rts

!edtd_remove_adjacent_traps:
    ldx #0
!edtd_scan:
    cpx trap_count
    bcs !edtd_scan_done+

    lda trap_x,x
    sec
    sbc zp_player_x
    clc
    adc #1
    cmp #3
    bcs !edtd_scan_next+
    lda trap_y,x
    sec
    sbc zp_player_y
    clc
    adc #1
    cmp #3
    bcs !edtd_scan_next+
    lda trap_x,x
    cmp zp_player_x
    bne !edtd_remove+
    lda trap_y,x
    cmp zp_player_y
    beq !edtd_scan_next+

!edtd_remove:
    dec trap_count
    ldy trap_count
    lda trap_x,y
    sta trap_x,x
    lda trap_y,y
    sta trap_y,x
    lda trap_type,y
    sta trap_type,x
    jmp !edtd_scan-

!edtd_scan_next:
    inx
    jmp !edtd_scan-

!edtd_scan_done:
    rts
