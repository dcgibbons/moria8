#importonce
// map_render.s - CX16 map-to-VERA rendering and viewport helpers.

cx16_render_town:
    lda #0
    sta cx16_draw_y
!row:
    lda #0
    sta cx16_draw_x
!col:
    lda cx16_draw_x
    cmp cx16_player_x
    bne !floor+
    lda cx16_draw_y
    cmp cx16_player_y
    bne !floor+
    lda #SC_PLAYER
    ldx #COL_PLAYER
    bne !put+
!floor:
    jsr cx16_read_draw_tile
    jsr tile_map_byte_to_char_color
    jsr cx16_apply_store_door_display
!put:
    sta cx16_draw_char
    stx cx16_draw_color
    txa
    jsr screen_set_color
    clc
    ldy cx16_draw_y
    tya
    adc #CX16_TOWN_SCREEN_ROW
    tay
    clc
    ldx cx16_draw_x
    txa
    adc #CX16_TOWN_SCREEN_COL
    tax
    lda cx16_draw_char
    jsr screen_put_char_at
    inc cx16_draw_x
    lda cx16_draw_x
    cmp #TOWN_MAP_COLS
    bcc !col-
    inc cx16_draw_y
    lda cx16_draw_y
    cmp #TOWN_MAP_ROWS
    bcc !row-
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    rts

cx16_save_old_player:
    lda cx16_player_x
    sta cx16_old_player_x
    lda cx16_player_y
    sta cx16_old_player_y
    rts

cx16_player_redraw:
    lda cx16_old_player_x
    sta cx16_draw_x
    lda cx16_old_player_y
    sta cx16_draw_y
    jsr cx16_draw_map_cell
    clc
    lda cx16_player_y
    adc #CX16_TOWN_SCREEN_ROW
    tay
    clc
    lda cx16_player_x
    adc #CX16_TOWN_SCREEN_COL
    tax
    lda #COL_PLAYER
    jsr screen_set_color
    lda #SC_PLAYER
    jsr screen_put_char_at
    lda #CX16_TEXT_COLOR
    jmp screen_set_color

cx16_draw_map_cell:
    jsr cx16_read_draw_tile
    jsr tile_map_byte_to_char_color
    jsr cx16_apply_store_door_display
    sta cx16_draw_char
    stx cx16_draw_color
    txa
    jsr screen_set_color
    clc
    ldy cx16_draw_y
    tya
    adc #CX16_TOWN_SCREEN_ROW
    tay
    clc
    ldx cx16_draw_x
    txa
    adc #CX16_TOWN_SCREEN_COL
    tax
    lda cx16_draw_char
    jsr screen_put_char_at
    lda #CX16_TEXT_COLOR
    jmp screen_set_color

cx16_apply_store_door_display:
    stx cx16_draw_color
    sta cx16_draw_char
    lda cx16_draw_x
    sta zp_temp3
    lda cx16_draw_y
    sta zp_temp4
    jsr town_basic_check_xy_store_door
    bcc !not_store+
    clc
    adc #SC_STORE_1
    ldx #COL_STORE
    rts
!not_store:
    lda cx16_draw_char
    ldx cx16_draw_color
    rts

cx16_read_draw_tile:
    ldy cx16_draw_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy cx16_draw_x
    lda (zp_ptr0),y
    rts

cx16_current_tile_type:
    ldy cx16_player_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy cx16_player_x
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    lsr
    lsr
    lsr
    lsr
    rts

cx16_update_dungeon_view:
    lda cx16_player_x
    sec
    sbc #VIEWPORT_W / 2
    bcs !x_ok+
    lda #0
    jmp !store_x+
!x_ok:
    cmp #MAP_COLS - VIEWPORT_W
    bcc !store_x+
    lda #MAP_COLS - VIEWPORT_W
!store_x:
    sta cx16_view_x
    lda cx16_player_y
    sec
    sbc #VIEWPORT_H / 2
    bcs !y_ok+
    lda #0
    jmp !store_y+
!y_ok:
    cmp #MAP_ROWS - VIEWPORT_H
    bcc !store_y+
    lda #MAP_ROWS - VIEWPORT_H
!store_y:
    sta cx16_view_y
    rts

cx16_render_dungeon_viewport:
    lda #0
    sta cx16_draw_y
!row:
    lda cx16_view_y
    clc
    adc cx16_draw_y
    tax
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    lda #0
    sta cx16_draw_x
!col:
    lda cx16_view_x
    clc
    adc cx16_draw_x
    tay
    lda (zp_ptr0),y
    sta cx16_draw_tile
    and #FLAG_VISITED
    bne !visible+
    lda #SC_SPACE
    sta cx16_draw_char
    lda #COL_BLACK
    sta cx16_draw_color
    jmp !check_player+
!visible:
    lda cx16_draw_tile
    jsr tile_map_byte_to_char_color
    sta cx16_draw_char
    stx cx16_draw_color
    lda cx16_draw_tile
    and #FLAG_OCCUPIED
    beq !not_monster+
    lda cx16_view_x
    clc
    adc cx16_draw_x
    pha
    lda cx16_view_y
    clc
    adc cx16_draw_y
    tay
    pla
    jsr cx16_load_monster_draw_at
    bcc !not_monster+
    sta cx16_draw_char
    txa
    sta cx16_draw_color
    jmp !check_player+
!not_monster:
    lda cx16_draw_tile
    and #FLAG_HAS_ITEM
    beq !check_player+
    lda cx16_view_x
    clc
    adc cx16_draw_x
    pha
    lda cx16_view_y
    clc
    adc cx16_draw_y
    tay
    pla
    jsr floor_item_find_at
    bcc !check_player+
    lda fi_item_id,x
    tax
    jsr item_load_display_x
    sta cx16_draw_char
    txa
    jsr item_get_floor_color
    sta cx16_draw_color
!check_player:
    lda cx16_view_x
    clc
    adc cx16_draw_x
    cmp cx16_player_x
    bne !not_player+
    lda cx16_view_y
    clc
    adc cx16_draw_y
    cmp cx16_player_y
    bne !not_player+
    lda #SC_PLAYER
    sta cx16_draw_char
    lda #COL_PLAYER
    sta cx16_draw_color
!not_player:
    lda cx16_draw_color
    jsr screen_set_color
    clc
    ldy cx16_draw_y
    tya
    adc #VIEWPORT_Y
    tay
    clc
    ldx cx16_draw_x
    txa
    adc #VIEWPORT_X
    tax
    lda cx16_draw_char
    jsr screen_put_char_at
    inc cx16_draw_x
    lda cx16_draw_x
    cmp #VIEWPORT_W
    bcs !row_done+
    jmp !col-
!row_done:
    inc cx16_draw_y
    lda cx16_draw_y
    cmp #VIEWPORT_H
    bcs !done+
    jmp !row-
!done:
    lda #CX16_TEXT_COLOR
    jmp screen_set_color

cx16_dungeon_player_redraw:
    lda cx16_old_player_x
    sta cx16_draw_x
    lda cx16_old_player_y
    sta cx16_draw_y
    jsr cx16_draw_dungeon_map_cell
    lda cx16_player_x
    sta cx16_draw_x
    lda cx16_player_y
    sta cx16_draw_y
    lda #COL_PLAYER
    jsr screen_set_color
    lda cx16_draw_y
    sec
    sbc cx16_view_y
    clc
    adc #VIEWPORT_Y
    tay
    lda cx16_draw_x
    sec
    sbc cx16_view_x
    clc
    adc #VIEWPORT_X
    tax
    lda #SC_PLAYER
    jsr screen_put_char_at
    lda #CX16_TEXT_COLOR
    jmp screen_set_color

cx16_render_dungeon_local_area:
    lda cx16_old_player_x
    cmp cx16_player_x
    bcc !min_x_old+
    lda cx16_player_x
!min_x_old:
    sec
    sbc zp_light_radius
    bcs !min_x_pad+
    lda #0
    jmp !min_x_view+
!min_x_pad:
    sec
    sbc #1
    bcs !min_x_view+
    lda #0
!min_x_view:
    cmp cx16_view_x
    bcs !store_min_x+
    lda cx16_view_x
!store_min_x:
    sta cx16_vis_min_x

    lda cx16_old_player_x
    cmp cx16_player_x
    bcs !max_x_old+
    lda cx16_player_x
!max_x_old:
    clc
    adc zp_light_radius
    clc
    adc #1
    sta cx16_vis_max_x
    lda cx16_view_x
    clc
    adc #VIEWPORT_W - 1
    cmp cx16_vis_max_x
    bcs !max_x_map+
    sta cx16_vis_max_x
!max_x_map:
    lda cx16_vis_max_x
    cmp #MAP_COLS
    bcc !store_max_x+
    lda #MAP_COLS - 1
!store_max_x:
    sta cx16_vis_max_x

    lda cx16_old_player_y
    cmp cx16_player_y
    bcc !min_y_old+
    lda cx16_player_y
!min_y_old:
    sec
    sbc zp_light_radius
    bcs !min_y_pad+
    lda #0
    jmp !min_y_view+
!min_y_pad:
    sec
    sbc #1
    bcs !min_y_view+
    lda #0
!min_y_view:
    cmp cx16_view_y
    bcs !store_min_y+
    lda cx16_view_y
!store_min_y:
    sta cx16_vis_min_y

    lda cx16_old_player_y
    cmp cx16_player_y
    bcs !max_y_old+
    lda cx16_player_y
!max_y_old:
    clc
    adc zp_light_radius
    clc
    adc #1
    sta cx16_vis_max_y
    lda cx16_view_y
    clc
    adc #VIEWPORT_H - 1
    cmp cx16_vis_max_y
    bcs !max_y_map+
    sta cx16_vis_max_y
!max_y_map:
    lda cx16_vis_max_y
    cmp #MAP_ROWS
    bcc !store_max_y+
    lda #MAP_ROWS - 1
!store_max_y:
    sta cx16_vis_max_y

    lda cx16_vis_min_y
    sta cx16_draw_y
!row:
    lda cx16_vis_min_x
    sta cx16_draw_x
!col:
    jsr cx16_draw_dungeon_map_cell
    inc cx16_draw_x
    lda cx16_draw_x
    cmp cx16_vis_max_x
    bcc !col-
    beq !col-
    inc cx16_draw_y
    lda cx16_draw_y
    cmp cx16_vis_max_y
    bcc !row-
    beq !row-
    jmp cx16_draw_dungeon_player_only

cx16_draw_dungeon_player_only:
    lda cx16_player_y
    sec
    sbc cx16_view_y
    clc
    adc #VIEWPORT_Y
    tay
    lda cx16_player_x
    sec
    sbc cx16_view_x
    clc
    adc #VIEWPORT_X
    tax
    lda #COL_PLAYER
    jsr screen_set_color
    lda #SC_PLAYER
    jsr screen_put_char_at
    lda #CX16_TEXT_COLOR
    jmp screen_set_color

cx16_draw_dungeon_map_cell:
    ldx cx16_draw_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy cx16_draw_x
    lda (zp_ptr0),y
    sta cx16_draw_tile
    and #FLAG_VISITED
    bne !visible+
    lda #SC_SPACE
    sta cx16_draw_char
    lda #COL_BLACK
    sta cx16_draw_color
    jmp !put+
!visible:
    lda cx16_draw_tile
    jsr tile_map_byte_to_char_color
    sta cx16_draw_char
    stx cx16_draw_color
    lda cx16_draw_tile
    and #FLAG_OCCUPIED
    beq !not_monster+
    lda cx16_draw_x
    ldy cx16_draw_y
    jsr cx16_load_monster_draw_at
    bcc !not_monster+
    sta cx16_draw_char
    txa
    sta cx16_draw_color
    jmp !put+
!not_monster:
    lda cx16_draw_tile
    and #FLAG_HAS_ITEM
    beq !put+
    lda cx16_draw_x
    ldy cx16_draw_y
    jsr floor_item_find_at
    bcc !put+
    lda fi_item_id,x
    tax
    jsr item_load_display_x
    sta cx16_draw_char
    txa
    jsr item_get_floor_color
    sta cx16_draw_color
!put:
    lda cx16_draw_color
    jsr screen_set_color
    lda cx16_draw_y
    sec
    sbc cx16_view_y
    clc
    adc #VIEWPORT_Y
    tay
    lda cx16_draw_x
    sec
    sbc cx16_view_x
    clc
    adc #VIEWPORT_X
    tax
    lda cx16_draw_char
    jsr screen_put_char_at
    lda #CX16_TEXT_COLOR
    jmp screen_set_color

cx16_load_monster_draw_at:
    sta cx16_mon_draw_x
    sty cx16_mon_draw_y
    lda zp_ptr0
    sta cx16_mon_draw_saved_ptr
    lda zp_ptr0_hi
    sta cx16_mon_draw_saved_ptr_hi
    lda cx16_mon_draw_x
    ldy cx16_mon_draw_y
    jsr cx16_find_monster_draw_at
    bcc !miss+
    ldy #CX16_ACTIVE_MONSTER_TYPE_OFFSET
    lda (zp_ptr0),y
    sta cx16_mon_draw_type
    lda #CX16_TIER_FIELD_DISPLAY
    jsr cx16_read_monster_draw_tier_field
    sta cx16_mon_draw_char
    lda #CX16_TIER_FIELD_COLOR
    jsr cx16_read_monster_draw_tier_field
    tax
    lda cx16_mon_draw_saved_ptr
    sta zp_ptr0
    lda cx16_mon_draw_saved_ptr_hi
    sta zp_ptr0_hi
    lda cx16_mon_draw_char
    sec
    rts
!miss:
    lda cx16_mon_draw_saved_ptr
    sta zp_ptr0
    lda cx16_mon_draw_saved_ptr_hi
    sta zp_ptr0_hi
    clc
    rts

cx16_find_monster_draw_at:
    lda #<CREATURE_BASE
    sta zp_ptr0
    lda #>CREATURE_BASE
    sta zp_ptr0_hi
    ldx #0
!loop:
    cpx #CX16_ACTIVE_MONSTER_COUNT
    bcs !miss+
    ldy #CX16_ACTIVE_MONSTER_TYPE_OFFSET
    lda (zp_ptr0),y
    cmp #CX16_ACTIVE_MONSTER_EMPTY_SLOT
    beq !next+
    ldy #CX16_ACTIVE_MONSTER_X_OFFSET
    lda (zp_ptr0),y
    cmp cx16_mon_draw_x
    bne !next+
    ldy #CX16_ACTIVE_MONSTER_Y_OFFSET
    lda (zp_ptr0),y
    cmp cx16_mon_draw_y
    bne !next+
    sec
    rts
!next:
    clc
    lda zp_ptr0
    adc #CX16_ACTIVE_MONSTER_ENTRY_SIZE
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #0
    sta zp_ptr0_hi
    inx
    jmp !loop-
!miss:
    clc
    rts

cx16_read_monster_draw_tier_field:
    sta cx16_mon_draw_field_idx
    jsr cx16_monster_draw_current_tier_count
    sta cx16_mon_draw_tier_count
    lda #<CX16_TIER_LOAD_BASE
    sta zp_ptr0
    lda #>CX16_TIER_LOAD_BASE
    sta zp_ptr0_hi
    lda cx16_mon_draw_field_idx
    beq !add_type+
!field_loop:
    clc
    lda zp_ptr0
    adc cx16_mon_draw_tier_count
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #0
    sta zp_ptr0_hi
    dec cx16_mon_draw_field_idx
    bne !field_loop-
!add_type:
    clc
    lda zp_ptr0
    adc cx16_mon_draw_type
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #0
    sta zp_ptr0_hi
    ldy #0
    lda cx16_loaded_tier_bank
    jmp cx16_read_byte_from_bank_a000

cx16_monster_draw_current_tier_count:
    lda cx16_loaded_tier
    cmp #2
    bne !not_tier2+
    lda #TIER2_COUNT
    rts
!not_tier2:
    cmp #3
    bne !not_tier3+
    lda #TIER3_COUNT
    rts
!not_tier3:
    cmp #4
    bne !tier1+
    lda #TIER4_COUNT
    rts
!tier1:
    lda #TIER1_COUNT
    rts

cx16_old_player_x: .byte 0
cx16_old_player_y: .byte 0
cx16_draw_x: .byte 0
cx16_draw_y: .byte 0
cx16_draw_char: .byte 0
cx16_draw_color: .byte 0
cx16_draw_tile: .byte 0
cx16_view_x: .byte 0
cx16_view_y: .byte 0
cx16_old_view_x: .byte 0
cx16_old_view_y: .byte 0
cx16_vis_min_x: .byte 0
cx16_vis_max_x: .byte 0
cx16_vis_min_y: .byte 0
cx16_mon_draw_x: .byte 0
cx16_mon_draw_y: .byte 0
cx16_mon_draw_type: .byte 0
cx16_mon_draw_char: .byte 0
cx16_mon_draw_field_idx: .byte 0
cx16_mon_draw_tier_count: .byte 0
cx16_mon_draw_saved_ptr: .byte 0
cx16_mon_draw_saved_ptr_hi: .byte 0
cx16_vis_max_y: .byte 0
