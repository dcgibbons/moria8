// player_move.s — Player movement and collision
//
// Handles 8-direction movement, tile walkability checks,
// and player position updates.

// ============================================================
// Walkable tile table
// Indexed by tile type (0-15). 1 = walkable, 0 = blocked.
// ============================================================
walkable_table:
    .byte 1     // 0: Floor — walkable
    .byte 0     // 1: Wall horizontal — blocked
    .byte 0     // 2: Wall vertical — blocked
    .byte 0     // 3: Corner TL — blocked
    .byte 0     // 4: Corner TR — blocked
    .byte 0     // 5: Corner BL — blocked
    .byte 0     // 6: Corner BR — blocked
    .byte 1     // 7: Door open — walkable
    .byte 0     // 8: Door closed — blocked
    .byte 1     // 9: Stairs down — walkable
    .byte 1     // 10: Stairs up — walkable
    .byte 1     // 11: Rubble — walkable
    .byte 0     // 12: Magma — blocked
    .byte 0     // 13: Quartz — blocked
    .byte 1     // 14: Trap — walkable
    .byte 0     // 15: Secret door — blocked

// ============================================================
// Subroutines
// ============================================================

// tile_is_walkable — Check if a tile type is walkable
// Input: A = tile type index (0-15)
// Output: carry set = walkable, carry clear = blocked
// Preserves: X, Y
tile_is_walkable:
    stx zp_temp2            // Save X
    tax
    lda walkable_table,x
    ldx zp_temp2            // Restore X
    lsr                     // Bit 0 into carry
    rts

// player_try_move — Attempt to move the player in a direction
// Input: A = command ID (CMD_MOVE_N through CMD_MOVE_SE)
// Output: carry set = move succeeded, carry clear = blocked
// Preserves: nothing
player_try_move:
    // Convert command to direction index (0-7)
    sec
    sbc #CMD_MOVE_N         // Now A = 0 for N, 1 for S, etc.
    tax

    // Compute target position
    lda zp_player_x
    clc
    adc dir_dx,x
    sta zp_temp3            // target_x

    lda zp_player_y
    clc
    adc dir_dy,x
    sta zp_temp4            // target_y

    // Bounds check: target_x must be in [1, MAP_COLS-2]
    // (can't walk into boundary walls)
    lda zp_temp3
    beq !blocked+           // x = 0
    cmp #MAP_COLS - 1
    bcs !blocked+           // x >= 79

    // target_y must be in [1, MAP_ROWS-2]
    lda zp_temp4
    beq !blocked+           // y = 0
    cmp #MAP_ROWS - 1
    bcs !blocked+           // y >= 47

    // Read target tile from map
    ldx zp_temp4            // map row
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_temp3            // map column
    lda (zp_ptr0),y

    // Extract tile type (bits 7-4 → 0-15)
    lsr
    lsr
    lsr
    lsr

    // Check walkability
    jsr tile_is_walkable
    bcc !blocked+

    // Move succeeded — update player position
    lda zp_temp3
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda zp_temp4
    sta zp_player_y
    sta player_data + PL_MAP_Y

    sec                     // Carry set = success
    rts

!blocked:
    // Play bump sound
    lda #SFX_BUMP
    jsr sound_play
    clc                     // Carry clear = blocked
    rts

// check_stairs_at_player — Check if player is standing on stairs
// Output: A = tile type if stairs (9 = down, 10 = up), or 0 if not stairs
// Preserves: nothing
check_stairs_at_player:
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    lda (zp_ptr0),y

    // Extract tile type
    lsr
    lsr
    lsr
    lsr

    // Check for stairs down (9) or stairs up (10)
    cmp #9                  // TILE_STAIRS_DN >> 4
    beq !is_stairs+
    cmp #10                 // TILE_STAIRS_UP >> 4
    beq !is_stairs+

    lda #0                  // Not stairs
!is_stairs:
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Walkable table = 16 entries", tile_is_walkable - walkable_table, 16
