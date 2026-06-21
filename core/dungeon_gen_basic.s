#importonce
// dungeon_gen_basic.s - dependency-light shared bootstrap dungeon generation.
//
// This is not the full dungeon_gen.s implementation. It is a small shared
// generator slice for platforms that need a runtime-safe stepping stone before
// linking the full generator overlay. Callers must define MAP_BASE, MAP_COLS,
// MAP_ROWS, tile constants, DUNGEON_GEN_BASIC_FLAGS, and zp_ptr0/zp_ptr0_hi.

.macro DungeonGenBasicCarveRoom(x0, y0, width, height) {
    ldx #y0
!row:
    lda dungeon_gen_basic_map_row_lo,x
    sta zp_ptr0
    lda dungeon_gen_basic_map_row_hi,x
    sta zp_ptr0_hi
    ldy #x0
    lda #TILE_FLOOR | DUNGEON_GEN_BASIC_FLAGS
!col:
    sta (zp_ptr0),y
    iny
    cpy #x0 + width
    bne !col-
    inx
    cpx #y0 + height
    bne !row-
}

.macro DungeonGenBasicDrawRoomWalls(x0, y0, width, height) {
    ldx #y0 - 1
    lda dungeon_gen_basic_map_row_lo,x
    sta zp_ptr0
    lda dungeon_gen_basic_map_row_hi,x
    sta zp_ptr0_hi
    ldy #x0 - 1
    lda #TILE_WALL_H | DUNGEON_GEN_BASIC_FLAGS
!top:
    sta (zp_ptr0),y
    iny
    cpy #x0 + width + 1
    bne !top-

    ldx #y0 + height
    lda dungeon_gen_basic_map_row_lo,x
    sta zp_ptr0
    lda dungeon_gen_basic_map_row_hi,x
    sta zp_ptr0_hi
    ldy #x0 - 1
    lda #TILE_WALL_H | DUNGEON_GEN_BASIC_FLAGS
!bottom:
    sta (zp_ptr0),y
    iny
    cpy #x0 + width + 1
    bne !bottom-

    ldx #y0
!side_row:
    lda dungeon_gen_basic_map_row_lo,x
    sta zp_ptr0
    lda dungeon_gen_basic_map_row_hi,x
    sta zp_ptr0_hi
    lda #TILE_WALL_H | DUNGEON_GEN_BASIC_FLAGS
    ldy #x0 - 1
    sta (zp_ptr0),y
    ldy #x0 + width
    sta (zp_ptr0),y
    inx
    cpx #y0 + height
    bne !side_row-
}

.macro DungeonGenBasicCarveHLine(y0, x1, x2) {
    ldx #y0
    lda dungeon_gen_basic_map_row_lo,x
    sta zp_ptr0
    lda dungeon_gen_basic_map_row_hi,x
    sta zp_ptr0_hi
    ldy #x1
    lda #TILE_FLOOR | DUNGEON_GEN_BASIC_FLAGS
!loop:
    sta (zp_ptr0),y
    cpy #x2
    beq !done+
    iny
    jmp !loop-
!done:
}

.macro DungeonGenBasicCarveVLine(x0, y1, y2) {
    ldx #y1
!loop:
    lda dungeon_gen_basic_map_row_lo,x
    sta zp_ptr0
    lda dungeon_gen_basic_map_row_hi,x
    sta zp_ptr0_hi
    ldy #x0
    lda #TILE_FLOOR | DUNGEON_GEN_BASIC_FLAGS
    sta (zp_ptr0),y
    cpx #y2
    beq !done+
    inx
    jmp !loop-
!done:
}

.macro DungeonGenBasicPutTile(x0, y0, tile) {
    ldx #y0
    lda dungeon_gen_basic_map_row_lo,x
    sta zp_ptr0
    lda dungeon_gen_basic_map_row_hi,x
    sta zp_ptr0_hi
    lda #tile | DUNGEON_GEN_BASIC_FLAGS
    ldy #x0
    sta (zp_ptr0),y
}

dungeon_gen_basic_generate:
    ldx #0
!fill_row:
    lda dungeon_gen_basic_map_row_lo,x
    sta zp_ptr0
    lda dungeon_gen_basic_map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
    lda #TILE_WALL_H
!fill_col:
    sta (zp_ptr0),y
    iny
    cpy #MAP_COLS
    bne !fill_col-
    inx
    cpx #MAP_ROWS
    bne !fill_row-

    :DungeonGenBasicDrawRoomWalls(12, 8, 28, 10)
    :DungeonGenBasicDrawRoomWalls(52, 12, 34, 12)
    :DungeonGenBasicDrawRoomWalls(20, 31, 26, 10)
    :DungeonGenBasicDrawRoomWalls(96, 20, 30, 12)
    :DungeonGenBasicCarveRoom(12, 8, 28, 10)
    :DungeonGenBasicCarveRoom(52, 12, 34, 12)
    :DungeonGenBasicCarveRoom(20, 31, 26, 10)
    :DungeonGenBasicCarveRoom(96, 20, 30, 12)
    :DungeonGenBasicCarveHLine(13, 25, 69)
    :DungeonGenBasicCarveVLine(69, 13, 18)
    :DungeonGenBasicCarveVLine(32, 17, 34)
    :DungeonGenBasicCarveHLine(34, 32, 60)
    :DungeonGenBasicCarveVLine(60, 23, 34)
    :DungeonGenBasicCarveHLine(23, 60, 101)

    :DungeonGenBasicPutTile(40, 13, TILE_DOOR_OPEN)
    :DungeonGenBasicPutTile(51, 13, TILE_DOOR_OPEN)
    :DungeonGenBasicPutTile(32, 18, TILE_DOOR_OPEN)
    :DungeonGenBasicPutTile(86, 23, TILE_DOOR_OPEN)
    :DungeonGenBasicPutTile(22, 31, TILE_DOOR_CLOSED)
    :DungeonGenBasicPutTile(36, 34, TILE_RUBBLE)
    :DungeonGenBasicPutTile(58, 23, TILE_QUARTZ)
    :DungeonGenBasicPutTile(72, 16, TILE_TRAP)

    :DungeonGenBasicPutTile(24, 13, TILE_STAIRS_UP)
    :DungeonGenBasicPutTile(77, 18, TILE_STAIRS_DN)
    rts

dungeon_gen_basic_map_row_lo:
    .fill MAP_ROWS, <(MAP_BASE + i * MAP_COLS)
dungeon_gen_basic_map_row_hi:
    .fill MAP_ROWS, >(MAP_BASE + i * MAP_COLS)

.assert "basic dungeon generator assumes wide shared map", MAP_COLS >= 126, true
.assert "basic dungeon generator assumes shared map height", MAP_ROWS >= 42, true
