#importonce
// player_move.s — Player movement and collision
//
// Handles 8-direction movement, tile walkability checks,
// and player position updates.

#if !C128
#import "look_flash_target.s"
#endif

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
    ldx #0
    stx player_move_relocated

    // Convert command to direction index (0-7)
    sec
    sbc #CMD_MOVE_N         // Now A = 0 for N, 1 for S, etc.
    tax

    // Confused? Randomize direction
    lda zp_eff_confuse
    beq !not_confused+
    lda #8
    jsr rng_range           // A = random [0,7]
    tax
!not_confused:

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
#if C128
c128_town_move_diag_after_map_ptr_setup:
#endif
    :MapRead_ptr0_y()
#if C128
c128_town_move_diag_after_map_read:
#endif

    // Extract tile type (bits 7-4 → 0-15)
    lsr
    lsr
    lsr
    lsr

    // Check walkability (closed doors are blocked — use 'o' to open)
#if C128
c128_town_move_diag_before_walkable:
#endif
    jsr tile_is_walkable
#if C128
c128_town_move_diag_after_walkable:
#endif
    bcs !walkable+
    jsr wizard_wall_walk_active
    beq !blocked+
!walkable:

    // Check FLAG_OCCUPIED (monster present)
    ldy zp_temp3                // target_x (column offset)
#if C128
c128_town_move_diag_before_occupied_read:
#endif
    :MapRead_ptr0_y()             // Re-read map byte (zp_ptr0 still valid)
    and #FLAG_OCCUPIED
#if C128
c128_town_move_diag_after_occupied_read:
#endif
    beq !not_occupied+          // No monster → continue to move

    lda zp_temp3
    ldy zp_temp4
    jsr player_move_check_live_occupant
    bcc !not_occupied+          // Stale occupied flag → clear and continue

    // Monster present — attack if not running
    lda zp_run_dir
    cmp #$ff
    bne !blocked+               // Running → just block, don't attack

    // Fear blocks melee attacks
    lda eff_fear_timer
    beq !not_afraid+
    ldx #HSTR_PTM_AFRAID
    jsr huff_print_msg
    sec                         // Turn consumed (too afraid to act)
    rts
!not_afraid:
    lda zp_temp3                // target_x
    ldy zp_temp4                // target_y
    jsr player_attack_monster
    sec                         // Turn consumed
    rts

!not_occupied:
#if C128
c128_town_move_diag_move_success:
#endif
    // Move succeeded — update player position
    lda zp_temp3
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda zp_temp4
    sta zp_player_y
    sta player_data + PL_MAP_Y

    lda #1
    sta player_move_relocated

    sec                     // Carry set = success
    rts

!blocked:
#if C128
c128_town_move_diag_move_blocked:
#endif
    // Suppress bump sound during running
    lda zp_run_dir
    cmp #$ff
    bne !no_bump+
    lda #SFX_BUMP
    jsr sound_play
!no_bump:
    clc                     // Carry clear = blocked
    rts

pm_live_occ_x: .byte 0
pm_live_occ_y: .byte 0

// player_move_check_live_occupant — honor FLAG_OCCUPIED only when a live
// monster table entry still exists at the tile. If the map flag is stale,
// clear it so movement, running, and future renders stop treating the tile as
// blocked by a phantom monster.
// Input:  A = x, Y = y
// Output: carry set = live monster present, X = slot index
//         carry clear = no live monster; stale FLAG_OCCUPIED cleared
// Clobbers: A, X, Y, zp_ptr0/hi
player_move_check_live_occupant:
    sta pm_live_occ_x
    sty pm_live_occ_y
    jsr monster_find_at
    bcs !pm_live_found+

    ldx pm_live_occ_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy pm_live_occ_x
    :MapRead_ptr0_y()
    and #~FLAG_OCCUPIED & $ff
    :MapWrite_ptr0_y()
    clc
    rts

!pm_live_found:
    sec
    rts

// player_move_maybe_passive_search — Movement-owned passive auto-search.
// Only runs after an ordinary successful relocation, never on melee-only turns.
player_move_maybe_passive_search:
    lda player_move_relocated
    beq !done+

    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    bne !done+

    jsr player_search_get_fos
    cmp #2
    bcc !search+
    jsr rng_range
    bne !done+

!search:
    jsr search_scan_effective_silent
!done:
    rts

// 1 when the most recent player_try_move changed the player's map position.
player_move_relocated: .byte 0

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
    :MapRead_ptr0_y()

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
    :MapRead_ptr0_y()
    sta zp_temp0            // Save full tile byte
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !rcs_stop+
    cmp #TILE_STAIRS_UP
    beq !rcs_stop+

    // 2. Visible trap at current tile → stop
    cmp #TILE_TRAP
    beq !rcs_stop+

    // 3. Item at current tile → stop
    lda zp_temp0
    and #FLAG_HAS_ITEM
    bne !rcs_stop+

    // 4. Room entry: was in unlit area, now in lit area
    lda run_was_lit
    bne !rcs_not_entry+
    lda zp_temp0
    and #FLAG_LIT
    bne !rcs_stop+          // Entered a lit room → stop
!rcs_not_entry:

    // 5. Room exit: was in lit area, now in unlit area
    lda run_was_lit
    beq !rcs_not_exit+
    lda zp_temp0
    and #FLAG_LIT
    beq !rcs_stop+          // Left a lit room → stop
!rcs_not_exit:

    // 6. Adjacent door check (6 neighbors, skip forward/backward)
    jsr run_check_adjacent_doors
    bcs !rcs_stop+

    // 7. Adjacent monster check (6 neighbors, skip forward/backward)
    jsr run_check_adjacent_monsters
    bcs !rcs_stop+

    // 8. Intersection check (corridors only — unlit area)
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

// run_check_adjacent_monsters — Check 6 neighbors for FLAG_OCCUPIED
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

    lda zp_temp1
    ldy zp_temp2
    jsr player_move_check_live_occupant
    bcs !rcam_found+

!rcam_next:
    inc run_scratch
    jmp !rcam_loop-

!rcam_found:
    sec
    rts
!rcam_none:
    clc
    rts

// run_check_intersection — Check for corridor intersection
// Checks 4 cardinal directions (N/S/W/E), skipping forward/backward.
// If any unlit side exit found → intersection detected.
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

// ============================================================
// do_look — Scan along a direction and describe the first thing found
// Skips over empty floor tiles. Reports monsters, items, doors, stairs,
// traps, rubble, or walls. Stops at non-visible tiles or map edge.
// Free action: does not consume a turn.
// Output: carry clear always (no turn consumed)
// ============================================================
do_look:
    jsr get_direction_target
    bcs !dl_valid+
    clc
    rts                         // Invalid direction
!dl_valid:
    // Compute direction delta for multi-tile scanning
    lda df_target_x
    sec
    sbc zp_player_x
    sta dl_dx
    lda df_target_y
    sec
    sbc zp_player_y
    sta dl_dy

!dl_scan:
    // Bounds check (unsigned: negative wraps to >128, > MAP size)
    lda df_target_x
    cmp #MAP_COLS
    bcc !dl_x_ok+
    jmp !dl_nothing+
!dl_x_ok:
    lda df_target_y
    cmp #MAP_ROWS
    bcc !dl_y_ok+
    jmp !dl_nothing+
!dl_y_ok:

    // Read map tile at (df_target_x, df_target_y)
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    sta dl_tile

    // Must be currently visible, not just remembered.
    ldx df_target_x
    ldy df_target_y
    jsr los_is_visible
    bcs !dl_visible+
    jmp !dl_nothing+
!dl_visible:
    // Only trust monster table coordinates when the live map tile still
    // carries FLAG_OCCUPIED. This matches renderer ownership and avoids
    // stale level-transition/cached-table lookups on empty tiles.
    lda dl_tile
    and #FLAG_OCCUPIED
    beq !dl_no_monster+

    lda df_target_x
    ldy df_target_y
    jsr monster_find_at
    bcc !dl_no_monster+

    // Found a monster — "YOU SEE A <name>."
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    jsr creature_get_name       // A=lo, Y=hi (handles KERNAL banking)
    sta dl_name_lo
    sty dl_name_hi
    jsr dl_print_you_see
    clc
    rts

!dl_no_monster:
    // Check tile type — non-floor terrain is authoritative for look.
    lda dl_tile
    and #TILE_TYPE_MASK

    cmp #TILE_DOOR_OPEN
    bne !dl_not_open+
    ldx #HSTR_DL_OPEN_DOOR
    bne dl_print_tile
!dl_not_open:
    cmp #TILE_DOOR_CLOSED
    bne !dl_not_closed+
    ldx #HSTR_DL_CLOSED_DOOR
    bne dl_print_tile
!dl_not_closed:
    cmp #TILE_STAIRS_DN
    bne !dl_not_sdn+
    ldx #HSTR_DL_STAIRS_DN
    bne dl_print_tile
!dl_not_sdn:
    cmp #TILE_STAIRS_UP
    bne !dl_not_sup+
    ldx #HSTR_DL_STAIRS_UP
    bne dl_print_tile
!dl_not_sup:
    cmp #TILE_TRAP
    bne !dl_not_trap+
    ldx #HSTR_DL_TRAP
    bne dl_print_tile
!dl_not_trap:
    cmp #TILE_RUBBLE
    bne !dl_not_rubble+
    ldx #HSTR_DL_RUBBLE
    bne dl_print_tile
!dl_not_rubble:
    cmp #TILE_FLOOR
    beq !dl_floor+

    // Wall/secret/mineral seam (any other non-floor tile) — report it.
    ldx #HSTR_DL_WALL
    jmp dl_print_tile

// dl_print_you_see — Print "YOU SEE A <name>."
// Input: dl_name_lo/hi = name string pointer
dl_print_you_see:
    jsr look_flash_target
#if C128
    php
    sei
#endif
    ldx #HSTR_DL_YOU_SEE
    jsr huff_print_msg
    // Append name inline on message row
    lda zp_text_color
    pha
    lda #COL_MSG_TEXT
    sta zp_text_color
    lda dl_name_lo
    sta zp_ptr0
    lda dl_name_hi
    sta zp_ptr0_hi
    jsr screen_put_string
    // Append "."
    lda #$2e
    jsr screen_put_char
    pla
    sta zp_text_color
#if C128
    plp
#endif
    rts

// dl_print_tile — Print a tile description message
// Input: X = Huffman string ID (HSTR_*)
dl_print_tile:
    txa
    pha
    jsr look_flash_target
    pla
    tax
dl_print_tile_no_flash:
    jsr huff_print_msg
    clc
    rts

!dl_floor:
    lda df_target_x
    ldy df_target_y
    jsr floor_item_find_at
    bcs !dl_item+
    jsr glyph_find_at_stashed
    bcc !dl_step+               // Empty floor — keep scanning
    ldx #HSTR_PMU_GLYPH_OK
    bne dl_print_tile

    // Found an item on floor — get its name
!dl_item:
    lda fi_item_id,x
    jsr item_get_name_ptr
    lda zp_ptr0
    sta dl_name_lo
    lda zp_ptr0_hi
    sta dl_name_hi
    jsr dl_print_you_see
    clc
    rts

!dl_step:
    // Step to next tile along scan direction
    lda df_target_x
    clc
    adc dl_dx
    sta df_target_x
    lda df_target_y
    clc
    adc dl_dy
    sta df_target_y
    jmp !dl_scan-

!dl_nothing:
    ldx #HSTR_DL_NOTHING
    jmp dl_print_tile_no_flash

// Look command scratch
dl_tile:     .byte 0
dl_scratch:  .byte 0
dl_name_lo:  .byte 0
dl_name_hi:  .byte 0
dl_dx:       .byte 0
dl_dy:       .byte 0

// Strings migrated to Huffman compression (HSTR_DL_*, HSTR_PTM_* in huffman_data.s)

// ============================================================
// Compile-time validation
// ============================================================
.assert "Walkable table = 16 entries", tile_is_walkable - walkable_table, 16
