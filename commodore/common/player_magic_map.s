#importonce
// player_magic_map.s — umoria-style Sense Surroundings area mapping

pm_map_min_x: .byte 0
pm_map_max_x: .byte 0
pm_map_min_y: .byte 0
pm_map_max_y: .byte 0

eff_map_area:
    lda zp_player_dlvl
    beq !emap_town+

    lda #20
    jsr rng_range
    sta zp_temp0
    lda zp_view_x
    sec
    sbc zp_temp0
    bcs !emap_dun_min_x+
    lda #0
!emap_dun_min_x:
    sta pm_map_min_x

    lda #20
    jsr rng_range
    sta zp_temp0
    lda zp_view_x
    clc
    adc #VIEWPORT_W - 1
    clc
    adc zp_temp0
    cmp #MAP_COLS
    bcc !emap_dun_max_x+
    lda #MAP_COLS - 1
!emap_dun_max_x:
    sta pm_map_max_x

    lda #10
    jsr rng_range
    sta zp_temp0
    lda zp_view_y
    sec
    sbc zp_temp0
    bcs !emap_dun_min_y+
    lda #0
!emap_dun_min_y:
    sta pm_map_min_y

    lda #10
    jsr rng_range
    sta zp_temp0
    lda zp_view_y
    clc
    adc #VIEWPORT_H - 1
    clc
    adc zp_temp0
    cmp #MAP_ROWS
    bcc !emap_dun_max_y+
    lda #MAP_ROWS - 1
!emap_dun_max_y:
    sta pm_map_max_y
    jmp !emap_scan+

!emap_town:
    lda #20
    jsr rng_range
    sta zp_temp0
    lda zp_view_x
    sec
    sbc zp_temp0
    bcs !emap_town_min_x+
    lda #0
!emap_town_min_x:
    sta pm_map_min_x

    lda #20
    jsr rng_range
    sta zp_temp0
    lda zp_view_x
    clc
    adc #VIEWPORT_W - 1
    clc
    adc zp_temp0
    cmp #TOWN_MAP_COLS
    bcc !emap_town_max_x+
    lda #TOWN_MAP_COLS - 1
!emap_town_max_x:
    sta pm_map_max_x

    lda #10
    jsr rng_range
    sta zp_temp0
    lda zp_view_y
    sec
    sbc zp_temp0
    bcs !emap_town_min_y+
    lda #0
!emap_town_min_y:
    sta pm_map_min_y

    lda #10
    jsr rng_range
    sta zp_temp0
    lda zp_view_y
    clc
    adc #VIEWPORT_H - 1
    clc
    adc zp_temp0
    cmp #TOWN_MAP_ROWS
    bcc !emap_town_max_y+
    lda #TOWN_MAP_ROWS - 1
!emap_town_max_y:
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

    lda zp_player_dlvl
    beq !emap_adj_town+

    txa
    cmp #MAP_ROWS - 1
    bcs !emap_adj_max_y_dun+
    clc
    adc #1
!emap_adj_max_y_dun:
    sta zp_temp2

    pla
    pha
    cmp #MAP_COLS - 1
    bcs !emap_adj_max_x_dun+
    clc
    adc #1
!emap_adj_max_x_dun:
    sta zp_temp4
    jmp !emap_adj_rows+

!emap_adj_town:
    txa
    cmp #TOWN_MAP_ROWS - 1
    bcs !emap_adj_max_y_town+
    clc
    adc #1
!emap_adj_max_y_town:
    sta zp_temp2

    pla
    pha
    cmp #TOWN_MAP_COLS - 1
    bcs !emap_adj_max_x_town+
    clc
    adc #1
!emap_adj_max_x_town:
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
    lda #1
    sta vis_room_revealed
    rts
