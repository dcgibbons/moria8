// monster_ai.s — Monster AI: wake/sleep, movement, speed
//
// Called once per turn from turn_post_action. Iterates all 32 monster
// slots, performs wake checks, and moves awake monsters toward the
// player (greedy movement) or randomly if confused. Speed 0 = immobile,
// speed 1 = one move, speed 2 = two moves per turn.
//
// Combat handled via monster_attack_player when adjacent (Phase 5.4).

// ============================================================
// Scratch variables
// ============================================================
mat_old_x:    .byte 0       // Previous position for FLAG_OCCUPIED clear
mat_old_y:    .byte 0
mat_target_x: .byte 0       // Movement target
mat_target_y: .byte 0
mat_sign_dx:  .byte 0       // Direction sign toward player (-1, 0, +1)
mat_sign_dy:  .byte 0

// ============================================================
// monster_ai_tick — Main AI loop
// Iterates all 32 slots. Skips empty and immobile (speed=0).
// Speed 2 monsters get processed twice.
// Clobbers: everything
// ============================================================
monster_ai_tick:
    lda #0
    sta zp_mon_idx

!mat_loop:
    lda zp_mon_idx
    cmp #MAX_MONSTERS
    bcs !mat_done+

    // Load monster entry into ZP scratch
    tax
    jsr monster_get_ptr         // zp_ptr0 → entry

    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !mat_next+              // Skip empty slot
    sta zp_mon_type

    // Load position
    ldy #MX_X
    lda (zp_ptr0),y
    sta zp_mon_x
    ldy #MX_Y
    lda (zp_ptr0),y
    sta zp_mon_y

    // Load flags
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    sta zp_mon_flags

    // Check speed — skip immobile (speed=0)
    ldx zp_mon_type
    lda cr_speed,x
    beq !mat_next+              // Immobile, skip entirely

    sta zp_mon_speed            // Save speed for double-move check

    // Process once
    jsr monster_process_one

    // Check if player died
    lda zp_game_flags
    and #$01
    bne !mat_done+

    // Speed 2 → process again
    lda zp_mon_speed
    cmp #2
    bne !mat_next+
    jsr monster_process_one

    // Check if player died on second move
    lda zp_game_flags
    and #$01
    bne !mat_done+

!mat_next:
    inc zp_mon_idx
    jmp !mat_loop-

!mat_done:
    rts

// ============================================================
// monster_process_one — Single action for current monster
// Uses ZP scratch: zp_mon_idx, zp_mon_x/y, zp_mon_type, zp_mon_flags
// After processing, writes back updated state.
// ============================================================
monster_process_one:
    // If not awake, try to wake up
    lda zp_mon_flags
    and #MF_AWAKE
    bne !mpo_awake+

    jsr monster_wake_check
    // Check if now awake
    lda zp_mon_flags
    and #MF_AWAKE
    beq !mpo_done+              // Still asleep, done

!mpo_awake:
    // Check confused
    lda zp_mon_flags
    and #MF_CONFUSED
    bne !mpo_confused+

    // Normal movement: move toward player
    jsr monster_move_toward
    jmp !mpo_writeback+

!mpo_confused:
    jsr monster_move_random

!mpo_writeback:
    jsr monster_write_back

!mpo_done:
    rts

// ============================================================
// monster_wake_check — Check if monster should wake up
// Chebyshev distance to player <= cr_aaf[type], then roll vs sleep.
// Sets MF_AWAKE in zp_mon_flags if waking up.
// Clobbers: A, X, Y, zp_temp3, zp_temp4
// ============================================================
monster_wake_check:
    // Compute |player_x - mon_x|
    lda zp_player_x
    sec
    sbc zp_mon_x
    bcs !mwc_dx_pos+
    // Negative — negate
    eor #$ff
    clc
    adc #1
!mwc_dx_pos:
    sta zp_mon_scratch0         // abs_dx

    // Compute |player_y - mon_y|
    lda zp_player_y
    sec
    sbc zp_mon_y
    bcs !mwc_dy_pos+
    eor #$ff
    clc
    adc #1
!mwc_dy_pos:
    // A = abs_dy, compare with abs_dx for max (Chebyshev distance)
    cmp zp_mon_scratch0
    bcs !mwc_have_dist+         // abs_dy >= abs_dx → dist = abs_dy
    lda zp_mon_scratch0         // abs_dx > abs_dy → dist = abs_dx
!mwc_have_dist:
    // A = Chebyshev distance

    // Compare distance to awareness factor
    ldx zp_mon_type
    cmp cr_aaf,x
    beq !mwc_in_range+          // Equal = in range
    bcs !mwc_too_far+           // Greater = too far
!mwc_in_range:

    // In range — check sleep value
    lda cr_sleep,x
    beq !mwc_wake+              // sleep=0 → always wake immediately

    // Roll: rng_range(sleep). If result == 0, wake up.
    // A already has sleep value
    jsr rng_range               // Returns [0, sleep-1]
    cmp #0
    bne !mwc_too_far+           // Didn't wake this turn

!mwc_wake:
    lda zp_mon_flags
    ora #MF_AWAKE
    sta zp_mon_flags
    // Write back flags immediately (wake persists)
    jsr monster_write_back

!mwc_too_far:
    rts

// ============================================================
// monster_move_toward — Greedy 3-try movement toward player
// Try diagonal, then horizontal, then vertical.
// Clobbers: A, X, Y, zp_ptr0/hi
// ============================================================
monster_move_toward:
    // Compute sign_dx = sgn(player_x - mon_x)
    lda zp_player_x
    cmp zp_mon_x
    beq !mmt_dx_zero+
    bcs !mmt_dx_pos+
    // player_x < mon_x → -1
    lda #$ff
    sta mat_sign_dx
    jmp !mmt_dy+
!mmt_dx_pos:
    lda #$01
    sta mat_sign_dx
    jmp !mmt_dy+
!mmt_dx_zero:
    lda #$00
    sta mat_sign_dx

!mmt_dy:
    // Compute sign_dy = sgn(player_y - mon_y)
    lda zp_player_y
    cmp zp_mon_y
    beq !mmt_dy_zero+
    bcs !mmt_dy_pos+
    lda #$ff
    sta mat_sign_dy
    jmp !mmt_try+
!mmt_dy_pos:
    lda #$01
    sta mat_sign_dy
    jmp !mmt_try+
!mmt_dy_zero:
    lda #$00
    sta mat_sign_dy

!mmt_try:
    // If both zero, already on player (shouldn't happen) — no move
    lda mat_sign_dx
    ora mat_sign_dy
    beq !mmt_done+

    // Try 1: diagonal (sign_dx, sign_dy)
    lda zp_mon_x
    clc
    adc mat_sign_dx
    sta mat_target_x
    lda zp_mon_y
    clc
    adc mat_sign_dy
    sta mat_target_y
    jsr monster_try_step
    bcs !mmt_done+              // Success

    // Try 2: horizontal only (sign_dx, 0) — if sign_dx != 0
    lda mat_sign_dx
    beq !mmt_try_vert+
    lda zp_mon_x
    clc
    adc mat_sign_dx
    sta mat_target_x
    lda zp_mon_y
    sta mat_target_y
    jsr monster_try_step
    bcs !mmt_done+

!mmt_try_vert:
    // Try 3: vertical only (0, sign_dy) — if sign_dy != 0
    lda mat_sign_dy
    beq !mmt_done+
    lda zp_mon_x
    sta mat_target_x
    lda zp_mon_y
    clc
    adc mat_sign_dy
    sta mat_target_y
    jsr monster_try_step
    // Carry set/clear doesn't matter, we're done either way

!mmt_done:
    rts

// ============================================================
// monster_move_random — Confused movement: pick random direction
// Clobbers: A, X, Y, zp_ptr0/hi, zp_temp3, zp_temp4
// ============================================================
monster_move_random:
    lda #8
    jsr rng_range               // [0, 7] = direction index
    tax
    lda zp_mon_x
    clc
    adc dir_dx,x
    sta mat_target_x
    lda zp_mon_y
    clc
    adc dir_dy,x
    sta mat_target_y
    jsr monster_try_step
    // Don't try alternatives — confused movement is unreliable
    rts

// ============================================================
// monster_try_step — Validate and execute a single tile move
// Input: mat_target_x, mat_target_y = target position
//        zp_mon_x/y = current position
// Output: carry set = moved, carry clear = blocked
// Side effects: updates zp_mon_x/y, clears old FLAG_OCCUPIED,
//               sets new FLAG_OCCUPIED
// Clobbers: A, X, Y, zp_ptr0/hi
// ============================================================
monster_try_step:
    // Check: target is not the player's position
    lda mat_target_x
    cmp zp_player_x
    bne !mts_not_player+
    lda mat_target_y
    cmp zp_player_y
    bne !mts_not_player+

    // Monster is adjacent → attack player
    jsr monster_attack_player
    jmp !mts_blocked+           // Monster stays in place
!mts_not_player:

    // Bounds check
    lda mat_target_x
    beq !mts_blocked+
    cmp #MAP_COLS - 1
    bcs !mts_blocked+
    lda mat_target_y
    beq !mts_blocked+
    cmp #MAP_ROWS - 1
    bcs !mts_blocked+

    // Read map tile at target
    ldx mat_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy mat_target_x
    lda (zp_ptr0),y
    sta zp_mon_scratch1         // Save full tile byte

    // Check walkable
    lsr
    lsr
    lsr
    lsr                         // Tile type index 0-15
    jsr tile_is_walkable
    bcc !mts_blocked+

    // Check FLAG_OCCUPIED
    lda zp_mon_scratch1
    and #FLAG_OCCUPIED
    bne !mts_blocked+           // Another monster there

    // --- Move is valid --- execute it

    // Save old position
    lda zp_mon_x
    sta mat_old_x
    lda zp_mon_y
    sta mat_old_y

    // Update monster position in ZP scratch
    lda mat_target_x
    sta zp_mon_x
    lda mat_target_y
    sta zp_mon_y

    // Clear FLAG_OCCUPIED on old tile
    ldx mat_old_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy mat_old_x
    lda (zp_ptr0),y
    and #~FLAG_OCCUPIED & $ff
    sta (zp_ptr0),y

    // Set FLAG_OCCUPIED on new tile
    ldx mat_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy mat_target_x
    lda (zp_ptr0),y
    ora #FLAG_OCCUPIED
    sta (zp_ptr0),y

    sec                         // Success
    rts

!mts_blocked:
    clc
    rts

// ============================================================
// monster_write_back — Write ZP scratch back to monster table
// Writes: MX_X, MX_Y, MX_FLAGS from zp_mon_x/y, zp_mon_flags
// Uses: zp_mon_idx
// Clobbers: A, X, Y, zp_ptr0/hi
// ============================================================
monster_write_back:
    ldx zp_mon_idx
    jsr monster_get_ptr

    ldy #MX_X
    lda zp_mon_x
    sta (zp_ptr0),y

    ldy #MX_Y
    lda zp_mon_y
    sta (zp_ptr0),y

    ldy #MX_FLAGS
    lda zp_mon_flags
    sta (zp_ptr0),y

    rts
