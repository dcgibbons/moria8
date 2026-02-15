// spell_effects.s — Shared effect subroutines for spells, potions, scrolls, etc.
//
// Phase 7.0: Extracted from player_items.s inline handlers.
// Each subroutine implements a single effect and does NOT print messages
// (callers handle messaging) unless noted.
//
// Subroutines:
//   eff_heal            — Heal player HP by amount in A
//   eff_light_room      — Light the room the player occupies
//   eff_teleport_self   — Teleport player to random floor tile
//   eff_identify_prompt — Interactive item identification (prints its own messages)
//   eff_cure_poison     — Clear poison status
//   eff_detect_monsters — Reveal all active monsters on map
//   eff_remove_curse    — Clear IF_CURSED on all equipped items

// ============================================================
// Scratch variables
// ============================================================
eff_target_slot: .byte 0           // Target slot for identify
eff_room_idx:    .byte 0           // Room loop index for light

// ============================================================
// eff_heal — Heal player HP
// Input: A = heal amount (8-bit, pre-rolled)
// Output: HP updated in ZP and player_data, capped at max
// Clobbers: A
// ============================================================
eff_heal:
    clc
    adc zp_player_hp_lo
    sta zp_player_hp_lo
    lda zp_player_hp_hi
    adc #0
    sta zp_player_hp_hi

    // Cap at max HP (16-bit compare)
    lda zp_player_hp_hi
    cmp zp_player_mhp_hi
    bcc !eh_ok+
    bne !eh_clamp+
    lda zp_player_hp_lo
    cmp zp_player_mhp_lo
    bcc !eh_ok+
    beq !eh_ok+
!eh_clamp:
    lda zp_player_mhp_lo
    sta zp_player_hp_lo
    lda zp_player_mhp_hi
    sta zp_player_hp_hi
!eh_ok:
    // Sync to player_data
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI
    rts

// ============================================================
// eff_light_room — Light the room the player is in
// Input: none (reads zp_player_x/y, room_* arrays)
// Output: room lit, vis_room_revealed set
// Clobbers: A, X
// ============================================================
eff_light_room:
    lda #0
    sta eff_room_idx

!elr_loop:
    ldx eff_room_idx
    cpx room_count
    bcs !elr_corridor+              // Player not in any room

    // Check bounds: player_x in [room_x-1, room_x+room_w]
    lda room_x,x
    sec
    sbc #1
    cmp zp_player_x
    beq !elr_lx_ok+
    bcs !elr_next+
!elr_lx_ok:
    lda room_x,x
    clc
    adc room_w,x
    cmp zp_player_x
    bcc !elr_next+

    // Check bounds: player_y in [room_y-1, room_y+room_h]
    lda room_y,x
    sec
    sbc #1
    cmp zp_player_y
    beq !elr_ly_ok+
    bcs !elr_next+
!elr_ly_ok:
    lda room_y,x
    clc
    adc room_h,x
    cmp zp_player_y
    bcc !elr_next+

    // Player is in room X — light it
    lda #1
    sta room_lit,x
    sta vis_room_revealed           // Trigger full redraw
    rts

!elr_next:
    inc eff_room_idx
    jmp !elr_loop-

!elr_corridor:
    // In corridor — just set vis_room_revealed for redraw
    lda #1
    sta vis_room_revealed
    rts

// ============================================================
// eff_teleport_self — Teleport player to random floor tile
// Input: none (reads zp_player_x/y)
// Output: player moved, FLAG_OCCUPIED updated, vis_room_revealed set
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_teleport_self:
    jsr find_random_floor

    // Clear FLAG_OCCUPIED at old position
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    lda (zp_ptr0),y
    and #~FLAG_OCCUPIED & $ff
    sta (zp_ptr0),y

    // Move player
    lda df_target_x
    sta zp_player_x
    lda df_target_y
    sta zp_player_y

    // Set FLAG_OCCUPIED at new position
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    lda (zp_ptr0),y
    ora #FLAG_OCCUPIED
    sta (zp_ptr0),y

    // Trigger full visibility update and redraw
    lda #1
    sta vis_room_revealed
    rts

// ============================================================
// eff_identify_prompt — Interactive item identification
// Input: none (prompts user for slot)
// Output: item type identified (id_known set), instance flagged IF_IDENTIFIED,
//         message printed
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_identify_prompt:
    // Prompt: "IDENTIFY WHICH ITEM (A-V)?"
    lda #<piq_identify_prompt
    sta zp_ptr0
    lda #>piq_identify_prompt
    sta zp_ptr0_hi
    jsr msg_print

    jsr input_get_key

    // Cancel check
    cmp #$03
    beq !eip_cancel+
    cmp #$20
    beq !eip_cancel+

    // Convert to slot
    sec
    sbc #$41
    bcc !eip_cancel+
    cmp #MAX_INV_SLOTS
    bcs !eip_cancel+

    sta eff_target_slot
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !eip_cancel+

    // Identify that item type
    tax
    lda #1
    sta id_known,x

    // Set IF_IDENTIFIED on the item instance
    ldx eff_target_slot
    lda inv_flags,x
    ora #IF_IDENTIFIED
    sta inv_flags,x

    // Build message: "THIS IS A <real name>."
    lda #0
    sta cmb_buf_idx

    lda #<piq_thisis_str
    ldy #>piq_thisis_str
    jsr combat_append_str

    ldx eff_target_slot
    lda inv_item_id,x
    tax
    lda it_name_lo,x                // Always real name (type is now known)
    ldy it_name_hi,x
    jsr combat_append_str

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    jsr cmb_term_and_print

    rts

!eip_cancel:
    // Scroll already consumed — just print generic message
    lda #<piq_nothing_str
    sta zp_ptr0
    lda #>piq_nothing_str
    sta zp_ptr0_hi
    jsr msg_print
    rts

// ============================================================
// eff_cure_poison — Clear poison status
// Input: none
// Output: zp_eff_poison = 0
// Clobbers: A
// ============================================================
eff_cure_poison:
    lda #0
    sta zp_eff_poison
    rts

// ============================================================
// eff_detect_monsters — Reveal all active monsters on map
// Sets FLAG_VISITED on each active monster's tile so it renders.
// Input: none
// Output: vis_room_revealed = 1
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0
// ============================================================
eff_detect_monsters:
    ldx #0
!edm_loop:
    cpx #MAX_MONSTERS
    bcs !edm_done+

    stx zp_temp0                    // Save monster index
    jsr monster_get_ptr             // zp_ptr0 = pointer to monster entry

    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !edm_next+

    // Get monster Y coordinate -> map row pointer
    ldy #MX_Y
    lda (zp_ptr0),y
    tax                             // X = monster Y coord
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi

    // Get monster X coordinate
    ldy #MX_X
    lda (zp_ptr0),y
    tay                             // Y = monster X coord

    // Set FLAG_VISITED on tile
    lda (zp_ptr1),y
    ora #FLAG_VISITED
    sta (zp_ptr1),y

!edm_next:
    ldx zp_temp0                    // Restore monster index
    inx
    jmp !edm_loop-

!edm_done:
    lda #1
    sta vis_room_revealed
    rts

// ============================================================
// eff_remove_curse — Clear IF_CURSED on all equipped items
// Input: none
// Output: IF_CURSED cleared from all equipment slots
// Clobbers: A, X
// ============================================================
eff_remove_curse:
    ldx #EQUIP_WEAPON               // Equipment starts at slot 22
!erc_loop:
    cpx #TOTAL_INV_SLOTS
    bcs !erc_done+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !erc_next+
    lda inv_flags,x
    and #~IF_CURSED & $ff
    sta inv_flags,x
!erc_next:
    inx
    jmp !erc_loop-
!erc_done:
    rts

// ============================================================
// eff_phase_door — Short-range teleport (up to 10 tiles away)
// Picks a random floor tile; if > 10 distance, retries (max 20).
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_pd_attempts: .byte 0

eff_phase_door:
    lda #20
    sta eff_pd_attempts

!epd_loop:
    jsr find_random_floor

    // Check Chebyshev distance <= 10
    lda df_target_x
    sec
    sbc zp_player_x
    bpl !epd_dx_pos+
    eor #$ff
    clc
    adc #1
!epd_dx_pos:
    sta zp_temp0                    // |dx|

    lda df_target_y
    sec
    sbc zp_player_y
    bpl !epd_dy_pos+
    eor #$ff
    clc
    adc #1
!epd_dy_pos:
    // max(|dx|, |dy|) = Chebyshev distance
    cmp zp_temp0
    bcs !epd_use_dy+
    lda zp_temp0
!epd_use_dy:
    cmp #11
    bcc !epd_ok+

    dec eff_pd_attempts
    bne !epd_loop-

!epd_ok:
    // Move player (df_target_x/y already set by find_random_floor)
    jmp eff_teleport_self

// ============================================================
// eff_find_traps — Reveal all hidden traps in LOS range
// Instantly reveals all traps (no probability).
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_find_traps:
    ldx #0
!eft_loop:
    cpx trap_count
    bcs !eft_done+

    // Reveal trap on map
    ldy trap_y,x
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy trap_x,x
    lda (zp_ptr0),y
    and #TILE_FLAG_MASK
    ora #TILE_TRAP
    ora #FLAG_VISITED
    sta (zp_ptr0),y

    inx
    jmp !eft_loop-

!eft_done:
    // Don't remove traps from table — just reveal them
    lda #1
    sta vis_room_revealed
    rts

// ============================================================
// eff_find_doors — Reveal all secret doors on the map
// Converts TILE_SECRET to TILE_DOOR_CLOSED.
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_fd_row: .byte 0

eff_find_doors:
    lda #1
    sta eff_fd_row

!efd_row_loop:
    lda eff_fd_row
    cmp #MAP_ROWS - 1
    bcs !efd_done+

    ldx eff_fd_row
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    ldy #1
!efd_col_loop:
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    bne !efd_col_next+

    // Convert to closed door
    lda (zp_ptr0),y
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_CLOSED
    ora #FLAG_VISITED
    sta (zp_ptr0),y

!efd_col_next:
    iny
    cpy #MAP_COLS - 1
    bcc !efd_col_loop-

    inc eff_fd_row
    jmp !efd_row_loop-

!efd_done:
    lda #1
    sta vis_room_revealed
    rts

// ============================================================
// eff_sleep_adjacent — Put all adjacent monsters to sleep
// Clobbers: A, X, Y, zp_ptr0, zp_temp0-1
// ============================================================
eff_sa_dir: .byte 0

eff_sleep_adjacent:
    lda #0
    sta eff_sa_dir

!esa_loop:
    lda eff_sa_dir
    cmp #8
    bcs !esa_done+

    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    tay
    lda df_target_x

    // A = x, Y = y
    jsr monster_find_at
    bcc !esa_next+

    // Monster found in X — set sleep timer
    jsr monster_get_ptr             // zp_ptr0 = entry
    ldy #MX_SLEEP_CUR
    lda #20                         // Sleep for 20 turns
    sta (zp_ptr0),y

!esa_next:
    inc eff_sa_dir
    jmp !esa_loop-

!esa_done:
    rts

// ============================================================
// eff_confuse_adjacent — Confuse all adjacent monsters
// Clobbers: A, X, Y, zp_ptr0, zp_temp0-1
// ============================================================
eff_ca_dir: .byte 0

eff_confuse_adjacent:
    lda #0
    sta eff_ca_dir

!eca_loop:
    lda eff_ca_dir
    cmp #8
    bcs !eca_done+

    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    tay
    lda df_target_x

    jsr monster_find_at
    bcc !eca_next+

    // Monster found in X — set confuse timer
    jsr monster_get_ptr
    ldy #MX_CONFUSE
    lda #10                         // Confuse for 10 turns
    sta (zp_ptr0),y

!eca_next:
    inc eff_ca_dir
    jmp !eca_loop-

!eca_done:
    rts

// ============================================================
// eff_bolt — Fire a bolt in a direction, damaging first monster hit
// Input: A = dice count, X = dice sides
//        Must call get_direction_target first (df_target_x/y set)
//        Direction stored in eff_bolt_dir (index 0-7)
// Clobbers: A, X, Y, zp_ptr0, zp_temp0-4, zp_math_a/b
// ============================================================
eff_bolt_dice:  .byte 0
eff_bolt_sides: .byte 0
eff_bolt_dir:   .byte 0
eff_bolt_cx:    .byte 0     // Current X
eff_bolt_cy:    .byte 0     // Current Y
eff_bolt_steps: .byte 0

eff_bolt:
    sta eff_bolt_dice
    stx eff_bolt_sides

    // Get direction from player
    jsr get_direction_target
    bcc !eb_no_dir+

    // Calculate direction index
    lda df_target_x
    sec
    sbc zp_player_x
    sta zp_temp0                    // dx (signed)
    lda df_target_y
    sec
    sbc zp_player_y
    sta zp_temp1                    // dy (signed)

    // Find matching direction in dir_dx/dir_dy
    ldx #0
!eb_find_dir:
    lda dir_dx,x
    cmp zp_temp0
    bne !eb_dir_next+
    lda dir_dy,x
    cmp zp_temp1
    beq !eb_dir_found+
!eb_dir_next:
    inx
    cpx #8
    bcc !eb_find_dir-
!eb_no_dir:
    rts                             // No valid direction

!eb_dir_found:
    stx eff_bolt_dir

    // Start from player position
    lda zp_player_x
    sta eff_bolt_cx
    lda zp_player_y
    sta eff_bolt_cy
    lda #20
    sta eff_bolt_steps

!eb_trace:
    dec eff_bolt_steps
    bne !eb_has_steps+
    jmp !eb_fizzle+
!eb_has_steps:

    // Step in direction
    ldx eff_bolt_dir
    lda eff_bolt_cx
    clc
    adc dir_dx,x
    sta eff_bolt_cx
    lda eff_bolt_cy
    clc
    adc dir_dy,x
    sta eff_bolt_cy

    // Bounds check
    lda eff_bolt_cx
    beq !eb_oob+
    cmp #MAP_COLS - 1
    bcs !eb_oob+
    lda eff_bolt_cy
    beq !eb_oob+
    cmp #MAP_ROWS - 1
    bcc !eb_bounds_ok+
!eb_oob:
    jmp !eb_fizzle+
!eb_bounds_ok:

    // Read map tile — use walkable_table to determine passability
    ldx eff_bolt_cy
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy eff_bolt_cx
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    lsr
    lsr
    lsr
    lsr                             // Tile type index 0-15
    tax
    lda walkable_table,x
    bne !eb_check_mon+
    jmp !eb_fizzle+                 // Blocked tile

!eb_check_mon:
    // Check for monster at this position
    lda eff_bolt_cx
    ldy eff_bolt_cy
    jsr monster_find_at
    bcc !eb_trace-              // No monster, keep going

    // Hit a monster! X = slot index
    // Roll damage
    stx zp_temp2                // Save monster slot
    lda eff_bolt_dice
    ldx eff_bolt_sides
    ldy #0                      // No bonus
    jsr math_dice               // Result in zp_math_a

    // Apply damage to monster
    ldx zp_temp2
    jsr monster_get_ptr         // zp_ptr0 = monster entry
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sec
    sbc zp_math_a
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sbc zp_math_b
    sta (zp_ptr0),y

    // Check if dead (HP <= 0)
    bmi !eb_dead+
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    ldy #MX_HP_HI
    ora (zp_ptr0),y
    bne !eb_fizzle+             // Still alive (HP > 0)
!eb_dead:
    // Monster killed — award XP and remove
    ldx zp_temp2
    jsr eff_kill_monster

!eb_fizzle:
    rts

// ============================================================
// eff_damage_adjacent — Damage all adjacent monsters (area effect)
// Input: A = dice count, X = dice sides
// Clobbers: A, X, Y, zp_ptr0, zp_temp0-4, zp_math_a/b
// ============================================================
eff_da_dice:  .byte 0
eff_da_sides: .byte 0
eff_da_dir:   .byte 0

eff_damage_adjacent:
    sta eff_da_dice
    stx eff_da_sides
    lda #0
    sta eff_da_dir

!eda_loop:
    lda eff_da_dir
    cmp #8
    bcs !eda_done+

    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    tay
    lda df_target_x

    jsr monster_find_at
    bcc !eda_next+

    // Monster found — roll damage
    stx zp_temp2                    // Save monster slot
    lda eff_da_dice
    ldx eff_da_sides
    ldy #0
    jsr math_dice

    // Apply damage
    ldx zp_temp2
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sec
    sbc zp_math_a
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sbc zp_math_b
    sta (zp_ptr0),y

    bmi !eda_dead+
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    ldy #MX_HP_HI
    ora (zp_ptr0),y
    bne !eda_next+              // Still alive (HP > 0)
!eda_dead:
    // Monster killed
    ldx zp_temp2
    jsr eff_kill_monster

!eda_next:
    inc eff_da_dir
    jmp !eda_loop-

!eda_done:
    rts

// ============================================================
// eff_directional_monster — Get direction, find monster at target
// Output: carry SET = monster found (X = slot index),
//         carry CLEAR = no monster
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_directional_monster:
    jsr get_direction_target
    bcc !edm_fail+

    lda df_target_x
    ldy df_target_y
    jsr monster_find_at
    rts                             // Carry state from monster_find_at

!edm_fail:
    clc
    rts

// ============================================================
// eff_destroy_traps_doors — Destroy traps and jam doors open in radius
// Scans 8 adjacent tiles. Traps removed, closed doors opened.
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_dtd_dir: .byte 0

eff_destroy_traps_doors:
    lda #0
    sta eff_dtd_dir

!edtd_loop:
    lda eff_dtd_dir
    cmp #8
    bcs !edtd_done+

    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y

    // Read map tile
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    sta zp_temp0

    // Check for trap
    cmp #TILE_TRAP
    bne !edtd_check_door+
    // Remove trap — set to floor
    lda (zp_ptr0),y
    and #TILE_FLAG_MASK
    ora #TILE_FLOOR
    sta (zp_ptr0),y
    jmp !edtd_next+

!edtd_check_door:
    // Check for closed door or secret door
    lda zp_temp0
    cmp #TILE_DOOR_CLOSED
    beq !edtd_open_door+
    cmp #TILE_SECRET
    bne !edtd_next+

!edtd_open_door:
    // Open the door
    lda (zp_ptr0),y
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_OPEN
    ora #FLAG_VISITED
    sta (zp_ptr0),y

!edtd_next:
    inc eff_dtd_dir
    jmp !edtd_loop-

!edtd_done:
    // Remove matching traps from trap table for all 8 adjacent positions
    lda #0
    sta eff_dtd_dir              // Reuse as direction counter

!edtd_trap_dir:
    lda eff_dtd_dir
    cmp #8
    bcs !edtd_trap_done+

    // Compute adjacent position for this direction
    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y

    // Scan trap table for match
    ldx #0
!edtd_scan:
    cpx trap_count
    bcs !edtd_scan_done+

    lda trap_x,x
    cmp df_target_x
    bne !edtd_scan_next+
    lda trap_y,x
    cmp df_target_y
    bne !edtd_scan_next+

    // Match — swap with last entry, decrement count
    dec trap_count
    ldy trap_count
    lda trap_x,y
    sta trap_x,x
    lda trap_y,y
    sta trap_y,x
    lda trap_type,y
    sta trap_type,x
    jmp !edtd_scan-             // Re-check this index (swapped entry)

!edtd_scan_next:
    inx
    jmp !edtd_scan-

!edtd_scan_done:
    inc eff_dtd_dir
    jmp !edtd_trap_dir-

!edtd_trap_done:
    lda #1
    sta vis_room_revealed
    rts

// ============================================================
// eff_wall_to_mud — Turn a wall tile to floor in chosen direction
// Must call get_direction_target first.
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_wall_to_mud:
    jsr get_direction_target
    bcc !ewtm_fail+

    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK

    // Check if it's a wall type
    cmp #TILE_WALL_H
    beq !ewtm_dig+
    cmp #TILE_WALL_V
    beq !ewtm_dig+
    // Not a wall
!ewtm_fail:
    rts

!ewtm_dig:
    // Replace with floor + flags
    lda (zp_ptr0),y
    and #TILE_FLAG_MASK
    ora #TILE_FLOOR
    ora #FLAG_VISITED | FLAG_LIT
    sta (zp_ptr0),y

    lda #1
    sta vis_room_revealed
    rts

// ============================================================
// eff_kill_monster — Remove a dead monster and award XP
// Input: X = monster slot index (saved in zp_temp2 by caller)
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0-4, zp_math_a/b
// ============================================================
eff_kill_monster:
    stx zp_temp2                    // Save slot

    // Get monster type for XP award
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type                    // Set cmb_type for combat_award_xp

    // Remove monster from active list (clears FLAG_OCCUPIED + slot)
    ldx zp_temp2
    jsr monster_remove

    // Award XP using existing combat function
    jsr combat_award_xp
    jsr combat_check_levelup

    rts

// ============================================================
// eff_dispel_undead — Damage all active undead monsters
// Damage = (1d3) * player_level per monster
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0-4, zp_math_a/b
// ============================================================
eff_du_idx: .byte 0

eff_dispel_undead:
    lda #0
    sta eff_du_idx

!edu_loop:
    ldx eff_du_idx
    cpx #MAX_MONSTERS
    bcs !edu_done+

    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !edu_next+

    // Check CF_UNDEAD flag
    tax                             // X = creature type
    lda cr_mflags,x
    and #CF_UNDEAD
    beq !edu_next+

    // Undead monster — roll 1d3 * player_level
    lda #3
    jsr rng_range                   // A = [0, 2]
    clc
    adc #1                          // A = [1, 3]
    ldx zp_player_lvl              // X = level
    jsr math_multiply               // zp_math_a = lo, zp_math_b = hi

    // Apply damage
    ldx eff_du_idx
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sec
    sbc zp_math_a
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sbc zp_math_b
    sta (zp_ptr0),y

    // Check if dead (HP <= 0)
    bmi !edu_dead+
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    ldy #MX_HP_HI
    ora (zp_ptr0),y
    bne !edu_next+              // Still alive (HP > 0)
!edu_dead:
    // Monster killed
    ldx eff_du_idx
    jsr eff_kill_monster

!edu_next:
    inc eff_du_idx
    jmp !edu_loop-

!edu_done:
    rts

// ============================================================
// eff_aggravate — Wake all monsters (clear sleep timer)
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_aggravate:
    ldx #0
!eag_loop:
    cpx #MAX_MONSTERS
    bcs !eag_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !eag_next+
    ldy #MX_SLEEP_CUR
    lda #0
    sta (zp_ptr0),y             // Clear sleep
!eag_next:
    inx
    jmp !eag_loop-
!eag_done:
    rts
