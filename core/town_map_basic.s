#importonce
// town_map_basic.s - dependency-light deterministic town map builder.
//
// This builds the shared 66x22 town rectangle and store shells into the live
// map. It intentionally does not import full dungeon generation, trap state, or
// gameplay-side town entry behavior.

#import "dungeon_data.s"

town_map_basic_generate:
    jsr town_map_basic_fill_backing
    jsr town_map_basic_carve_floor
    jsr town_map_basic_draw_boundary
    jsr town_map_basic_draw_stores
    ldx #TOWN_STAIRS_X
    ldy #TOWN_STAIRS_Y
    lda #TILE_STAIRS_DN | TOWN_FLAGS
    jmp town_map_basic_write_tile

town_map_basic_fill_backing:
    ldx #0
!row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
    lda #TILE_WALL_H
!col:
    :MapWrite_ptr0_y()
    iny
    cpy #MAP_COLS
    bne !col-
    inx
    cpx #MAP_ROWS
    bne !row-
    rts

town_map_basic_carve_floor:
    ldx #0
!row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
    lda #TILE_FLOOR | TOWN_FLAGS
!col:
    :MapWrite_ptr0_y()
    iny
    cpy #TOWN_MAP_COLS
    bne !col-
    inx
    cpx #TOWN_MAP_ROWS
    bne !row-
    rts

town_map_basic_draw_boundary:
    ldx #0
    ldy #0
    lda #TILE_CORNER_TL | TOWN_FLAGS
    jsr town_map_basic_write_tile
    ldx #TOWN_MAP_COLS - 1
    ldy #0
    lda #TILE_CORNER_TR | TOWN_FLAGS
    jsr town_map_basic_write_tile
    ldx #0
    ldy #TOWN_MAP_ROWS - 1
    lda #TILE_CORNER_BL | TOWN_FLAGS
    jsr town_map_basic_write_tile
    ldx #TOWN_MAP_COLS - 1
    ldy #TOWN_MAP_ROWS - 1
    lda #TILE_CORNER_BR | TOWN_FLAGS
    jsr town_map_basic_write_tile

    ldx #1
!top_bottom:
    txa
    pha
    ldy #0
    lda #TILE_WALL_H | TOWN_FLAGS
    jsr town_map_basic_write_tile
    pla
    tax
    txa
    pha
    ldy #TOWN_MAP_ROWS - 1
    lda #TILE_WALL_H | TOWN_FLAGS
    jsr town_map_basic_write_tile
    pla
    tax
    inx
    cpx #TOWN_MAP_COLS - 1
    bne !top_bottom-

    ldy #1
!left_right:
    tya
    pha
    ldx #0
    lda #TILE_WALL_V | TOWN_FLAGS
    jsr town_map_basic_write_tile
    pla
    tay
    tya
    pha
    ldx #TOWN_MAP_COLS - 1
    lda #TILE_WALL_V | TOWN_FLAGS
    jsr town_map_basic_write_tile
    pla
    tay
    iny
    cpy #TOWN_MAP_ROWS - 1
    bne !left_right-
    rts

town_map_basic_draw_stores:
    ldx #0
!store:
    stx zp_temp0
    jsr town_map_basic_draw_store
    ldx zp_temp0
    inx
    cpx #STORE_COUNT
    bne !store-
    rts

town_map_basic_draw_store:
    ldx zp_temp0
    lda store_pos_x,x
    sta zp_temp1
    clc
    adc #STORE_W - 1
    sta zp_temp3
    lda store_pos_y,x
    sta zp_temp2
    clc
    adc #STORE_H - 1
    sta zp_temp4

    ldx zp_temp1
    ldy zp_temp2
    lda #TILE_CORNER_TL | TOWN_FLAGS
    jsr town_map_basic_write_tile
    ldx zp_temp3
    ldy zp_temp2
    lda #TILE_CORNER_TR | TOWN_FLAGS
    jsr town_map_basic_write_tile
    ldx zp_temp1
    ldy zp_temp4
    lda #TILE_CORNER_BL | TOWN_FLAGS
    jsr town_map_basic_write_tile
    ldx zp_temp3
    ldy zp_temp4
    lda #TILE_CORNER_BR | TOWN_FLAGS
    jsr town_map_basic_write_tile

    lda zp_temp1
    clc
    adc #1
    sta town_basic_x
!store_h:
    ldx town_basic_x
    ldy zp_temp2
    lda #TILE_WALL_H | TOWN_FLAGS
    jsr town_map_basic_write_tile
    ldx town_basic_x
    ldy zp_temp4
    lda #TILE_WALL_H | TOWN_FLAGS
    jsr town_map_basic_write_tile
    inc town_basic_x
    lda town_basic_x
    cmp zp_temp3
    bne !store_h-

    lda zp_temp2
    clc
    adc #1
    sta town_basic_y
!store_v:
    ldx zp_temp1
    ldy town_basic_y
    lda #TILE_WALL_V | TOWN_FLAGS
    jsr town_map_basic_write_tile
    ldx zp_temp3
    ldy town_basic_y
    lda #TILE_WALL_V | TOWN_FLAGS
    jsr town_map_basic_write_tile
    inc town_basic_y
    lda town_basic_y
    cmp zp_temp4
    bne !store_v-

    lda zp_temp2
    clc
    adc #1
    sta town_basic_y
!store_fill_y:
    lda zp_temp1
    clc
    adc #1
    sta town_basic_x
!store_fill_x:
    ldx town_basic_x
    ldy town_basic_y
    lda #TILE_WALL_H
    jsr town_map_basic_write_tile
    inc town_basic_x
    lda town_basic_x
    cmp zp_temp3
    bne !store_fill_x-
    inc town_basic_y
    lda town_basic_y
    cmp zp_temp4
    bne !store_fill_y-

    ldx zp_temp0
    lda store_door_x,x
    tax
    ldy zp_temp0
    lda store_door_y,y
    tay
    lda #TILE_DOOR_OPEN | TOWN_FLAGS
    jmp town_map_basic_write_tile

town_map_basic_write_tile:
    sta town_basic_tile
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    txa
    tay
    lda town_basic_tile
    :MapWrite_ptr0_y()
    rts

town_basic_tile: .byte 0
town_basic_x: .byte 0
town_basic_y: .byte 0
