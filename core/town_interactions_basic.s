#importonce
// town_interactions_basic.s - dependency-light town interaction probes.
//
// These helpers mirror the shared gameplay contracts without importing store
// inventory, UI overlays, or dungeon transition code.

#import "dungeon_data.s"
#import "zeropage.s"

// town_basic_check_store_door - Check if the player is standing on a store door.
// Input:  zp_player_x/zp_player_y
// Output: carry set + A = store index (0-7) if on a door
//         carry clear if not on any store door
// Clobbers: A, X
town_basic_check_store_door:
    ldx #STORE_COUNT - 1
!loop:
    lda zp_player_x
    cmp store_door_x,x
    bne !next+
    lda zp_player_y
    cmp store_door_y,x
    bne !next+
    txa
    sec
    rts
!next:
    dex
    bpl !loop-
    clc
    rts

// town_basic_check_xy_store_door - Check arbitrary town coordinates.
// Input:  zp_temp3 = x, zp_temp4 = y
// Output: carry set + A = store index (0-7) if on a door
//         carry clear if not on any store door
// Clobbers: A, X
town_basic_check_xy_store_door:
    ldx #STORE_COUNT - 1
!loop:
    lda zp_temp3
    cmp store_door_x,x
    bne !next+
    lda zp_temp4
    cmp store_door_y,x
    bne !next+
    txa
    sec
    rts
!next:
    dex
    bpl !loop-
    clc
    rts

// town_basic_check_stairs_at_player - Return stairs type at player position.
// Input:  zp_player_x/zp_player_y
// Output: A = TILE_STAIRS_DN >> 4, TILE_STAIRS_UP >> 4, or 0
// Clobbers: A, X, Y, zp_ptr0/zp_ptr0_hi
town_basic_check_stairs_at_player:
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !stairs+
    cmp #TILE_STAIRS_UP
    beq !stairs+
    lda #0
    rts
!stairs:
    lsr
    lsr
    lsr
    lsr
    rts
