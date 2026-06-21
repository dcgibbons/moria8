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
    bcc !col-
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
cx16_vis_max_y: .byte 0
