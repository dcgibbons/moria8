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

    // Auto-open closed doors on bump
    cmp #8                      // TILE_DOOR_CLOSED >> 4
    bne !not_closed_door+
    // Open the door in-place
    lda (zp_ptr0),y             // Re-read full map byte
    and #TILE_FLAG_MASK         // Keep flags
    ora #TILE_DOOR_OPEN         // Change to open door
    sta (zp_ptr0),y
    lda #7                      // TILE_DOOR_OPEN >> 4 (walkable)
!not_closed_door:

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
    // Suppress bump sound during running
    lda zp_run_dir
    cmp #$ff
    bne !no_bump+
    lda #SFX_BUMP
    jsr sound_play
!no_bump:
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
// Running stop logic
// ============================================================

// Scratch variables for running
run_was_lit:   .byte 0     // FLAG_LIT of tile before this step
run_scratch:   .byte 0     // Loop index for adjacent/intersection checks
run_exits:     .byte 0     // Exit count for intersection detection

// run_check_stop — Master stop condition for corridor running
// Input:  zp_run_dir = direction (0-7), zp_player_x/y = current pos
//         run_was_lit = FLAG_LIT status of tile BEFORE this step
// Output: carry set = STOP, carry clear = CONTINUE
// Clobbers: A, X, Y, zp_ptr0/hi, zp_temp0-2
run_check_stop:
    // 1. Stairs at current tile → stop
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    lda (zp_ptr0),y
    sta zp_temp0            // Save full tile byte
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !rcs_stop+
    cmp #TILE_STAIRS_UP
    beq !rcs_stop+

    // 2. Visible trap at current tile → stop
    cmp #TILE_TRAP
    beq !rcs_stop+

    // 3. Room entry: was in unlit area, now in lit area
    lda run_was_lit
    bne !rcs_not_entry+
    lda zp_temp0
    and #FLAG_LIT
    bne !rcs_stop+          // Entered a lit room → stop
!rcs_not_entry:

    // 4. Room exit: was in lit area, now in unlit area
    lda run_was_lit
    beq !rcs_not_exit+
    lda zp_temp0
    and #FLAG_LIT
    beq !rcs_stop+          // Left a lit room → stop
!rcs_not_exit:

    // 5. Adjacent door check (6 neighbors, skip forward/backward)
    jsr run_check_adjacent_doors
    bcs !rcs_stop+

    // 6. Intersection check (corridors only — unlit area)
    lda zp_temp0
    and #FLAG_LIT
    bne !rcs_continue+      // In lit room → no intersection check
    jsr run_check_intersection
    bcs !rcs_stop+

!rcs_continue:
    clc
    rts
!rcs_stop:
    sec
    rts

// run_check_adjacent_doors — Check 6 neighbors (skip forward/backward) for doors
// Input: zp_run_dir, zp_player_x/y
// Output: carry set = door found, carry clear = no doors
// Clobbers: A, X, Y, zp_ptr0/hi, run_scratch, zp_temp1, zp_temp2
run_check_adjacent_doors:
    lda #0
    sta run_scratch         // Direction loop index

!rcad_loop:
    lda run_scratch
    cmp #8
    bcs !rcad_no_door+      // Checked all 8 → no door found

    // Skip forward direction
    cmp zp_run_dir
    beq !rcad_next+

    // Skip backward direction
    ldx zp_run_dir
    cmp dir_opposite,x
    beq !rcad_next+

    // Compute adjacent tile position
    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta zp_temp1            // adj_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta zp_temp2            // adj_y

    // Bounds check
    lda zp_temp1
    beq !rcad_next+
    cmp #MAP_COLS - 1
    bcs !rcad_next+
    lda zp_temp2
    beq !rcad_next+
    cmp #MAP_ROWS - 1
    bcs !rcad_next+

    // Read map tile
    ldx zp_temp2
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_temp1
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK

    // Check for any door type
    cmp #TILE_DOOR_OPEN
    beq !rcad_found+
    cmp #TILE_DOOR_CLOSED
    beq !rcad_found+
    cmp #TILE_SECRET
    beq !rcad_found+

!rcad_next:
    inc run_scratch
    jmp !rcad_loop-

!rcad_found:
    sec
    rts
!rcad_no_door:
    clc
    rts

// run_check_intersection — Check for corridor intersection
// Checks 4 cardinal directions (N/S/W/E), skipping forward/backward.
// If any passable exit found → intersection detected.
// Only called when current tile is NOT lit (corridor).
// Input: zp_run_dir, zp_player_x/y
// Output: carry set = intersection, carry clear = no intersection
// Clobbers: A, X, Y, zp_ptr0/hi, run_scratch, run_exits, zp_temp1, zp_temp2
run_check_intersection:
    lda #0
    sta run_exits
    sta run_scratch         // Cardinal direction index

!rci_loop:
    lda run_scratch
    cmp #4                  // Only check N(0), S(1), W(2), E(3)
    bcs !rci_check+

    // Skip forward direction
    cmp zp_run_dir
    beq !rci_next+

    // Skip backward direction
    ldx zp_run_dir
    cmp dir_opposite,x
    beq !rci_next+

    // Compute adjacent tile position
    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta zp_temp1
    lda zp_player_y
    clc
    adc dir_dy,x
    sta zp_temp2

    // Bounds check
    lda zp_temp1
    beq !rci_next+
    cmp #MAP_COLS - 1
    bcs !rci_next+
    lda zp_temp2
    beq !rci_next+
    cmp #MAP_ROWS - 1
    bcs !rci_next+

    // Read map tile
    ldx zp_temp2
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_temp1
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    lsr
    lsr
    lsr
    lsr                     // Tile type index 0-15

    // Check walkability
    jsr tile_is_walkable
    bcc !rci_next+

    // Found a passable exit
    inc run_exits

!rci_next:
    inc run_scratch
    jmp !rci_loop-

!rci_check:
    lda run_exits
    beq !rci_no_intersection+
    sec                     // Intersection found
    rts
!rci_no_intersection:
    clc
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Walkable table = 16 entries", tile_is_walkable - walkable_table, 16
