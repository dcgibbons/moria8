#importonce
// player_run_stop.s - shared corridor-running stop predicates.

// Scratch variables for running
run_was_lit:   .byte 0     // FLAG_LIT of tile before this step
run_scratch:   .byte 0     // Loop index for adjacent/intersection checks
run_exits:     .byte 0     // Exit count for intersection detection

// run_check_stop - Master stop condition for corridor running
// Input:  zp_run_dir = direction (0-7), zp_player_x/y = current pos
//         run_was_lit = FLAG_LIT status of tile BEFORE this step
// Output: carry set = STOP, carry clear = CONTINUE
// Clobbers: A, X, Y, zp_ptr0/hi, zp_temp0-2
run_check_stop:
    // 1. Stairs at current tile -> stop
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    :MapRead_ptr0_y()
    sta zp_temp0            // Save full tile byte
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !rcs_stop+
    cmp #TILE_STAIRS_UP
    beq !rcs_stop+

    // 2. Visible trap at current tile -> stop
    cmp #TILE_TRAP
    beq !rcs_stop+

    // 3. Item at current tile -> stop
    lda zp_temp0
    and #FLAG_HAS_ITEM
    bne !rcs_stop+

    // 4. Room entry: was in unlit area, now in lit area
    lda run_was_lit
    bne !rcs_not_entry+
    lda zp_temp0
    and #FLAG_LIT
    bne !rcs_stop+          // Entered a lit room -> stop
!rcs_not_entry:

    // 5. Room exit: was in lit area, now in unlit area
    lda run_was_lit
    beq !rcs_not_exit+
    lda zp_temp0
    and #FLAG_LIT
    beq !rcs_stop+          // Left a lit room -> stop
!rcs_not_exit:

    // 6. Adjacent door check (6 neighbors, skip forward/backward)
    jsr run_check_adjacent_doors
    bcs !rcs_stop+

    // 7. Adjacent monster check (6 neighbors, skip forward/backward)
    jsr run_check_adjacent_monsters
    bcs !rcs_stop+

    // 8. Intersection check (corridors only - unlit area)
    lda zp_temp0
    and #FLAG_LIT
    bne !rcs_continue+      // In lit room -> no intersection check
    jsr run_check_intersection
    bcs !rcs_stop+

!rcs_continue:
    clc
    rts
!rcs_stop:
    sec
    rts

// run_check_adjacent_doors - Check 6 neighbors (skip forward/backward) for doors
// Input: zp_run_dir, zp_player_x/y
// Output: carry set = door found, carry clear = no doors
// Clobbers: A, X, Y, zp_ptr0/hi, run_scratch, zp_temp1, zp_temp2
run_check_adjacent_doors:
    lda #0
    sta run_scratch         // Direction loop index

!rcad_loop:
    lda run_scratch
    cmp #8
    bcs !rcad_no_door+      // Checked all 8 -> no door found

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
    :MapRead_ptr0_y()
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

// run_check_adjacent_monsters - Check 6 neighbors for FLAG_OCCUPIED
// Same pattern as run_check_adjacent_doors: skip forward/backward.
// Input: zp_run_dir, zp_player_x/y
// Output: carry set = monster adjacent, carry clear = no monsters
// Clobbers: A, X, Y, zp_ptr0/hi, run_scratch, zp_temp1, zp_temp2
run_check_adjacent_monsters:
    lda #0
    sta run_scratch

!rcam_loop:
    lda run_scratch
    cmp #8
    bcs !rcam_none+

    // Skip forward direction
    cmp zp_run_dir
    beq !rcam_next+

    // Skip backward direction
    ldx zp_run_dir
    cmp dir_opposite,x
    beq !rcam_next+

    // Compute adjacent position
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
    beq !rcam_next+
    cmp #MAP_COLS - 1
    bcs !rcam_next+
    lda zp_temp2
    beq !rcam_next+
    cmp #MAP_ROWS - 1
    bcs !rcam_next+

    // Read map tile and check FLAG_OCCUPIED
    ldx zp_temp2
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_temp1
    :MapRead_ptr0_y()
    and #FLAG_OCCUPIED
    beq !rcam_next+

#if CX16
    bne !rcam_found+
#else
    lda zp_temp1
    ldy zp_temp2
    jsr player_move_check_live_occupant
    bcs !rcam_found+
#endif

!rcam_next:
    inc run_scratch
    jmp !rcam_loop-

!rcam_found:
    sec
    rts
!rcam_none:
    clc
    rts

// run_check_intersection - Check for corridor intersection
// Checks 4 cardinal directions (N/S/W/E), skipping forward/backward.
// If any unlit side exit found, intersection is detected.
// Lit plain-floor side openings are ignored here so running stops on
// actual room entry instead of one tile early at the corridor mouth.
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
    :MapRead_ptr0_y()
    sta zp_temp0

    // Ignore lit plain-floor side openings; room-entry logic handles those.
    lda zp_temp0
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !rci_not_lit_floor+
    lda zp_temp0
    and #FLAG_LIT
    bne !rci_next+
!rci_not_lit_floor:

    lda zp_temp0
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
