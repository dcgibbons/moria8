#importonce
// player_magic_find_stairs.s — Detect Doors/Stairs stair half, in the execute
// overlay; its own file so tests run the production routine (needs
// pmx_work_y, map_row_ptr0_x and vis_room_revealed).

eff_find_stairs:
    // Every stair tile: levels hold untracked extra stairs (DGN-016).
    lda #1
    sta pmx_work_y
!efs_row:
    ldx pmx_work_y
    cpx #MAP_ROWS - 1
    bcs !efs_done+
    jsr map_row_ptr0_x
    ldy #1
!efs_col:
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !efs_mark+
    cmp #TILE_STAIRS_UP
    bne !efs_next+
!efs_mark:
    :MapRead_ptr0_y()
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
!efs_next:
    iny
    cpy #MAP_COLS - 1
    bcc !efs_col-
    inc pmx_work_y
    bne !efs_row-
!efs_done:
    lda #1
    sta vis_room_revealed
    rts
