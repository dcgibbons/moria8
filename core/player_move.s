#importonce
// player_move.s — Player movement and collision
//
// Handles 8-direction movement, tile walkability checks,
// and player position updates.

#import "look_flash_target.s"

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
// Preserves: Y
tile_is_walkable:
    tax
    lda walkable_table,x
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
    bne !target_x_nonzero+
    jmp !blocked+           // x = 0
!target_x_nonzero:
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
#if HAL_PLATFORM_GAME_LOOP_PLAYER_MOVE_DIAG_LABELS
c128_town_move_diag_after_map_ptr_setup:
#endif
    :MapRead_ptr0_y()
#if HAL_PLATFORM_GAME_LOOP_PLAYER_MOVE_DIAG_LABELS
c128_town_move_diag_after_map_read:
#endif
    sta zp_temp0

    // Extract tile type (bits 7-4 → 0-15)
    lda zp_temp0
    lsr
    lsr
    lsr
    lsr

    // Check walkability (closed doors are blocked — use 'o' to open)
#if HAL_PLATFORM_GAME_LOOP_PLAYER_MOVE_DIAG_LABELS
c128_town_move_diag_before_walkable:
#endif
    jsr tile_is_walkable
#if HAL_PLATFORM_GAME_LOOP_PLAYER_MOVE_DIAG_LABELS
c128_town_move_diag_after_walkable:
#endif
    bcs !walkable+
    jsr wizard_wall_walk_active
    beq !blocked+
!walkable:

    // Check FLAG_OCCUPIED (monster present)
    ldy zp_temp3                // target_x (column offset)
#if HAL_PLATFORM_GAME_LOOP_PLAYER_MOVE_DIAG_LABELS
c128_town_move_diag_before_occupied_read:
#endif
    :MapRead_ptr0_y()             // Re-read map byte (zp_ptr0 still valid)
    and #FLAG_OCCUPIED
#if HAL_PLATFORM_GAME_LOOP_PLAYER_MOVE_DIAG_LABELS
c128_town_move_diag_after_occupied_read:
#endif
    beq !not_occupied+          // No monster → continue to move

    lda zp_temp3
    ldy zp_temp4
    jsr player_move_check_live_occupant
    bcc !not_occupied+          // Stale occupied flag → clear and continue

    // A visible monster stops running without consuming a turn. An unseen
    // monster ends running and is attacked, matching UMoria's collision path.
    lda zp_run_dir
    cmp #$ff
    beq !not_running_monster+
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    bne !blocked+
    lda #$ff
    sta zp_run_dir
!not_running_monster:

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
#if HAL_PLATFORM_GAME_LOOP_PLAYER_MOVE_DIAG_LABELS
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
#if HAL_PLATFORM_GAME_LOOP_PLAYER_MOVE_DIAG_LABELS
c128_town_move_diag_move_blocked:
#endif
    // Suppress bump sound during running
    lda zp_run_dir
    cmp #$ff
    bne !no_bump+
    lda #SFX_BUMP
    jsr hal_sound_play
!no_bump:
    clc                     // Carry clear = blocked
    rts

#import "player_move_live_occupant.s"

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
    ldx zp_player_x
    ldy zp_player_y
    jsr map_get_tile

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

#if PLAYER_LOOK_EXTERNAL
    :PlayerMoveLookSegment()
#endif

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
    bcs !dl_nothing+
    lda df_target_y
    cmp #MAP_ROWS
    bcs !dl_nothing+

    // Read map tile at (df_target_x, df_target_y)
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    sta dl_tile

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

    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #(MF_VISIBLE | MF_DETECTED)
    beq !dl_no_monster+

    // Found a monster — "YOU SEE A <name>."
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
    // Must be currently visible, not just remembered. Monster perception is
    // handled above so infravision/detection targets can still be described.
    ldx df_target_x
    ldy df_target_y
    jsr los_is_visible
    bcs !dl_visible+
    lda dl_tile
    and #TILE_TYPE_MASK
    beq !dl_step+
    bne !dl_nothing+
!dl_nothing:
    ldx #HSTR_DL_NOTHING
    jmp dl_print_tile_no_flash
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
!dl_visible:
    // Visibility predicates can qualify lit terrain by room light; look still
    // must not describe terrain through blocking walls or closed doors.
    stx zp_los_dx
    sty zp_los_dy
    lda zp_player_x
    sta mm_los_cx
    lda zp_player_y
    sta mm_los_cy
    jsr mm_los_clear_to_target
    bcc !dl_nothing-
!dl_los_clear:
    // Check tile type — non-floor terrain is authoritative for look.
    lda dl_tile
    and #TILE_TYPE_MASK

    cmp #TILE_DOOR_OPEN
    bne !dl_not_open+
    ldx #HSTR_DL_OPEN_DOOR
    jmp dl_print_tile
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
    bne dl_print_tile

// dl_print_you_see — Print "YOU SEE A <name>."
// Input: dl_name_lo/hi = name string pointer
dl_print_you_see:
    jsr look_flash_target
#if HAL_PLATFORM_DESCRIBE_LOOK_MASKS_IRQ
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
    jsr hal_screen_put_string
    // Append "."
    lda #$2e
    jsr hal_screen_put_char
    pla
    sta zp_text_color
#if HAL_PLATFORM_DESCRIBE_LOOK_MASKS_IRQ
    plp
#endif
    rts

// dl_print_item_you_see — Print "YOU SEE A <item>."
// Input: A = item type ID
// item_get_name_ptr returns a shared item-name buffer, so copy the resolved
// name into combat_msg_buf before composing the message.
dl_print_item_you_see:
    sta dl_scratch
    jsr look_flash_target
#if HAL_PLATFORM_DESCRIBE_LOOK_MASKS_IRQ
    php
    sei
#endif
    lda #0
    sta cmb_buf_idx
    ldx #HSTR_DL_YOU_SEE
    jsr huff_append_combat
    lda dl_scratch
    jsr item_get_name_ptr
    lda zp_ptr0
    ldy zp_ptr0_hi
    jsr combat_append_str
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jsr cmb_term_and_print
#if HAL_PLATFORM_DESCRIBE_LOOK_MASKS_IRQ
    plp
#endif
    rts

// dl_print_tile — Print a tile description message
// Input: X = Huffman string ID (HSTR_*)
dl_print_tile:
    stx dl_scratch
    jsr look_flash_target
    ldx dl_scratch
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
    bcs !dl_glyph+
    jmp !dl_step-               // Empty floor — keep scanning
!dl_glyph:
    ldx #HSTR_PMU_GLYPH_OK
    bne dl_print_tile

    // Found an item on floor — get its name
!dl_item:
    lda fi_item_id,x
    jsr dl_print_item_you_see
    clc
    rts

// Strings migrated to Huffman compression (HSTR_DL_*, HSTR_PTM_* in huffman_data.s)

#if PLAYER_LOOK_EXTERNAL && PLAYER_LOOK_SCRATCH_RESIDENT
    :PlayerMoveRestoreResidentSegment()
#endif

// Look command scratch remains resident; overlay code must not own persistent
// state that disappears when another overlay replaces the window.
dl_tile:     .byte 0
dl_scratch:  .byte 0
dl_name_lo:  .byte 0
dl_name_hi:  .byte 0
dl_dx:       .byte 0
dl_dy:       .byte 0

#if PLAYER_LOOK_EXTERNAL && !PLAYER_LOOK_SCRATCH_RESIDENT
    :PlayerMoveRestoreResidentSegment()
#endif

// ============================================================
// Compile-time validation
// ============================================================
.assert "Walkable table = 16 entries", tile_is_walkable - walkable_table, 16
