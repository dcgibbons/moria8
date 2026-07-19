#importonce
// Minimal dungeon generation entry points for broad C64 runtime suites.
// These tests validate unrelated systems and only need the labels pulled in by
// production modules; importing the full generator can push direct-injected
// test PRGs into MAP_BASE/runtime memory.

map_bulk_fill_all:
    sta map_bulk_fill_val
    ldx #0
!mbf_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
!mbf_col:
    lda map_bulk_fill_val
    :MapWrite_ptr0_y()
    iny
    cpy #MAP_COLS
    bne !mbf_col-
    inx
    cpx #MAP_ROWS
    bne !mbf_row-
    rts

map_bulk_and_all:
level_generate:
town_generate:
dungeon_generate:
place_streamers:
place_traps:
position_player_dungeon:
    rts

fill_map_rock:
    lda #TILE_WALL_H
    jmp map_bulk_fill_all

random_floor_in_room:
    lda room_x,x
    ldy room_y,x
    clc
    rts

map_bulk_fill_val: .byte 0
