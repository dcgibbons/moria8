#importonce
// player_magic_map.s — umoria-style Sense Surroundings area mapping

#if !PM_MAP_SCRATCH_EXTERNAL
pm_map_min_x: .byte 0
pm_map_max_x: .byte 0
pm_map_min_y: .byte 0
pm_map_max_y: .byte 0
pm_map_max_col: .byte 0
pm_map_max_row: .byte 0
#endif

eff_map_area:
#if C64_PRODUCT_OVERLAY_RUNTIME && !PM_MAP_BANKED
    jsr c64u_turbo_fast
#endif
    // Select map dimension clamps by location (dungeon vs town).
    ldx #MAP_COLS - 1
    lda #MAP_ROWS - 1
    ldy zp_player_dlvl
    bne !emap_dims_ok+
    ldx #TOWN_MAP_COLS - 1
    lda #TOWN_MAP_ROWS - 1
!emap_dims_ok:
    stx pm_map_max_col
    sta pm_map_max_row

    lda #20
    jsr rng_range
    sta zp_temp0
    lda zp_view_x
    sec
    sbc zp_temp0
    bcs !emap_min_x+
    lda #0
!emap_min_x:
    sta pm_map_min_x

    lda #20
    jsr rng_range
    sta zp_temp0
    lda zp_view_x
    clc
    adc #VIEWPORT_W - 1
    clc
    adc zp_temp0
    cmp pm_map_max_col
    bcc !emap_max_x+
    beq !emap_max_x+
    lda pm_map_max_col
!emap_max_x:
    sta pm_map_max_x

    lda #10
    jsr rng_range
    sta zp_temp0
    lda zp_view_y
    sec
    sbc zp_temp0
    bcs !emap_min_y+
    lda #0
!emap_min_y:
    sta pm_map_min_y

    lda #10
    jsr rng_range
    sta zp_temp0
    lda zp_view_y
    clc
    adc #VIEWPORT_H - 1
    clc
    adc zp_temp0
    cmp pm_map_max_row
    bcc !emap_max_y+
    beq !emap_max_y+
    lda pm_map_max_row
!emap_max_y:
    sta pm_map_max_y

!emap_scan:
    ldx pm_map_min_y
!emap_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy pm_map_min_x
!emap_col:
    :MapRead_ptr0_y()
    sta zp_temp0
    and #TILE_TYPE_MASK
    beq !emap_floor+
    jmp !emap_next+

!emap_floor:
    lda zp_temp0
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()

    txa
    pha
    tya
    pha

    txa
    beq !emap_adj_min_y0+
    sec
    sbc #1
!emap_adj_min_y0:
    sta zp_temp1

    pla
    pha
    beq !emap_adj_min_x0+
    sec
    sbc #1
!emap_adj_min_x0:
    sta zp_temp3

    txa
    cmp pm_map_max_row
    bcs !emap_adj_max_y_ok+
    clc
    adc #1
!emap_adj_max_y_ok:
    sta zp_temp2

    pla
    pha
    cmp pm_map_max_col
    bcs !emap_adj_max_x_ok+
    clc
    adc #1
!emap_adj_max_x_ok:
    sta zp_temp4

!emap_adj_rows:
    ldx zp_temp1
!emap_adj_row:
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi
    ldy zp_temp3
!emap_adj_col:
    :MapRead_ptr1_y()
    sta zp_temp0
    and #TILE_TYPE_MASK
    beq !emap_adj_next+
    cmp #TILE_SECRET
    beq !emap_adj_next+
    lda zp_temp0
    ora #FLAG_VISITED
    :MapWrite_ptr1_y()
!emap_adj_next:
    cpy zp_temp4
    beq !emap_adj_row_done+
    iny
    jmp !emap_adj_col-
!emap_adj_row_done:
    cpx zp_temp2
    beq !emap_adj_done+
    inx
    jmp !emap_adj_row-
!emap_adj_done:
    pla
    tay
    pla
    tax

!emap_next:
    cpy pm_map_max_x
    beq !emap_row_done+
    iny
    jmp !emap_col-
!emap_row_done:
    cpx pm_map_max_y
    beq !emap_done+
    inx
    jmp !emap_row-
!emap_done:
#if C64_PRODUCT_OVERLAY_RUNTIME && !PM_MAP_BANKED
    jsr c64u_turbo_normal
#endif
    lda #1
    sta vis_room_revealed
    rts
