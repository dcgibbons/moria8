#importonce
// player_move_basic.s - dependency-light player movement primitives.
//
// This file deliberately stops before combat, traps, running, sound, and search.
// Those remain owned by the full player_move.s path while new ports adopt the
// same map, tile, and player-position contracts incrementally.

#import "dungeon_data.s"
#import "input_contract.s"
#import "player_state.s"
#import "tile_walkability.s"

// player_move_compute_target - Compute a dungeon target and read its map byte.
// Input:  X = direction index (0-7)
// Output: carry set if target is inside dungeon movement bounds
//         zp_temp3 = target x, zp_temp4 = target y, zp_temp0 = target tile byte
// Clobbers: A, X, Y, zp_ptr0/zp_ptr0_hi
player_move_compute_target:
    lda zp_player_x
    clc
    adc dir_dx,x
    sta zp_temp3

    lda zp_player_y
    clc
    adc dir_dy,x
    sta zp_temp4

    lda zp_temp3
    beq !blocked+
    cmp #MAP_COLS - 1
    bcs !blocked+

    lda zp_temp4
    beq !blocked+
    cmp #MAP_ROWS - 1
    bcs !blocked+

    jsr player_move_read_target_tile
    sec
    rts

!blocked:
    clc
    rts

// player_move_compute_town_target - Compute a town target and read its map byte.
// Input:  X = direction index (0-7)
// Output: carry set if target is inside the fixed town rectangle
//         zp_temp3 = target x, zp_temp4 = target y, zp_temp0 = target tile byte
// Clobbers: A, X, Y, zp_ptr0/zp_ptr0_hi
player_move_compute_town_target:
    lda zp_player_x
    clc
    adc dir_dx,x
    sta zp_temp3

    lda zp_player_y
    clc
    adc dir_dy,x
    sta zp_temp4

    lda zp_temp3
    cmp #TOWN_MAP_COLS
    bcs !blocked+

    lda zp_temp4
    cmp #TOWN_MAP_ROWS
    bcs !blocked+

    jsr player_move_read_target_tile
    sec
    rts

!blocked:
    clc
    rts

// player_move_read_target_tile - Read map byte at zp_temp3/zp_temp4.
// Output: zp_ptr0 points at target row, Y = target x, A/zp_temp0 = tile byte
// Clobbers: A, X, Y, zp_ptr0/zp_ptr0_hi
player_move_read_target_tile:
    ldx zp_temp4
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_temp3
    :MapRead_ptr0_y()
    sta zp_temp0
    rts

// player_move_target_walkable - Check the tile byte in zp_temp0.
// Output: carry set = walkable, carry clear = blocked
// Preserves: X, Y
player_move_target_walkable:
    lda zp_temp0
    and #TILE_TYPE_MASK
    lsr
    lsr
    lsr
    lsr
    jmp tile_is_walkable

// player_move_commit_target - Commit zp_temp3/zp_temp4 as player position.
// Clobbers: A
player_move_commit_target:
    lda zp_temp3
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda zp_temp4
    sta zp_player_y
    sta player_data + PL_MAP_Y
    rts
