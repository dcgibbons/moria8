#importonce
// monster_ai.s — Monster AI: wake/sleep, movement, speed
//
// Called once per turn from turn_post_action. Iterates all 32 monster
// slots, performs wake checks, and moves awake monsters toward the
// player (greedy movement) or randomly if confused. Speed 0 = slow
// (every other turn), speed 1 = normal, speed 2 = fast (two moves).
// CF_ATTACK_ONLY creatures can attack adjacent player but not move.
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
mat_fleeing:  .byte 0       // 1 = fleeing (suppress attack in try_step)
mat_any_moved: .byte 0       // 1 if any monster moved/spawned this tick
mat_scene_dirty: .byte 0     // 1 if any monster changed a non-local visible tile
mat_action_dirty: .byte 0    // 1 if current monster changed gameplay state

// ============================================================
// monster_ai_tick — Main AI loop
// Iterates all 32 slots. Skips empty. Speed 0 = slow (every other turn).
// Speed 2 monsters get processed twice.
// Clobbers: everything
// ============================================================
monster_ai_tick:
    lda #0
    sta zp_mon_idx
    sta mat_any_moved
    sta mat_scene_dirty

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

    // Check speed, including per-monster spell adjustment stored in
    // MX_SPEED_CNT (-1 = slowed, 0 = normal base speed, +1 = hasted).
    ldx zp_mon_type
    lda cr_speed,x
    sta zp_mon_speed
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_SPEED_CNT
    lda (zp_ptr0),y
    beq !mat_apply_base+
    bpl !mat_speed_up+
    lda zp_mon_speed
    beq !mat_apply_base+
    dec zp_mon_speed
    jmp !mat_apply_base+
!mat_speed_up:
    lda zp_mon_speed
    cmp #2
    bcs !mat_apply_base+
    inc zp_mon_speed
!mat_apply_base:
    lda zp_mon_speed
    bne !mat_not_slow+

    // Speed 0 = slow: act every other turn (even turns only)
    lda zp_turn_lo
    and #$01
    bne !mat_next+              // Skip on odd turns
    lda #1                      // Treat as speed 1 this turn

!mat_not_slow:
    sta zp_mon_speed            // Save speed for double-move check

    // Process once
    jsr monster_process_one
    bcc !mat_no_move1+
    lda #1
    sta mat_any_moved
!mat_no_move1:

    // Check if player died
    lda zp_game_flags
    and #$01
    bne !mat_done+

    // Speed 2 → process again
    lda zp_mon_speed
    cmp #2
    bne !mat_next+
    jsr monster_process_one
    bcc !mat_no_move2+
    lda #1
    sta mat_any_moved
!mat_no_move2:

    // Check if player died on second move
    lda zp_game_flags
    and #$01
    bne !mat_done+

!mat_next:
    inc zp_mon_idx
    jmp !mat_loop-

!mat_done:
    lda mat_any_moved
    beq !mat_done_clear+
    lda mat_scene_dirty
    sec
    rts
!mat_done_clear:
    lda mat_scene_dirty
    clc
    rts

// ============================================================
// monster_process_one — Single action for current monster
// Uses ZP scratch: zp_mon_idx, zp_mon_x/y, zp_mon_type, zp_mon_flags
// After processing, writes back updated state.
// ============================================================
monster_process_one:
    lda #0
    sta mat_action_dirty

    // If not awake, try to wake up
    lda zp_mon_flags
    and #MF_AWAKE
    bne !mpo_awake+

    jsr monster_wake_check
    // Check if now awake
    lda zp_mon_flags
    and #MF_AWAKE
    bne !mpo_awake+
    jmp !mpo_done+              // Still asleep, done

!mpo_awake:
    // Tick stun/confuse timers
    ldx zp_mon_idx
    jsr monster_get_ptr         // zp_ptr0 → entry

    // Check stun timer
    ldy #MX_STUN
    lda (zp_ptr0),y
    beq !mpo_not_stunned+
    sec
    sbc #1
    sta (zp_ptr0),y
    jmp !mpo_writeback+         // Stunned — skip entire turn
!mpo_not_stunned:

    // Check confuse timer
    ldy #MX_CONFUSE
    lda (zp_ptr0),y
    beq !mpo_not_confused+
    sec
    sbc #1
    sta (zp_ptr0),y
    jmp !mpo_confused+          // Random movement (no spellcast)
!mpo_not_confused:

    // Check if monster wants to cast a spell
    jsr monster_can_cast
    bcc !mpo_no_cast+
    jsr monster_pick_spell
    lda #1
    sta mat_action_dirty
    jmp !mpo_writeback+         // Casting used the monster's turn
!mpo_no_cast:

    // Town creatures wander randomly unless provoked
    lda zp_mon_type
    cmp #TOWN_CREATURE_BASE
    bcc !mpo_not_town+
    lda zp_mon_flags
    and #MF_PROVOKED
    bne !mpo_not_town+
    jsr monster_move_random
    bcc !mpo_town_no_move+
    lda #1
    sta mat_action_dirty
    jsr mat_mark_move_dirty
!mpo_town_no_move:
    jmp !mpo_writeback+
!mpo_not_town:

    // Check if monster should flee (HP < threshold)
    jsr monster_check_flee
    bcs !mpo_flee+

    // Normal movement: move toward player
    jsr monster_move_toward
    bcc !mpo_toward_no_move+
    lda #1
    sta mat_action_dirty
    jsr mat_mark_move_dirty
!mpo_toward_no_move:
    jmp !mpo_writeback+

!mpo_flee:
    jsr monster_move_away
    bcc !mpo_flee_no_move+
    lda #1
    sta mat_action_dirty
    jsr mat_mark_move_dirty
!mpo_flee_no_move:
    jmp !mpo_writeback+

!mpo_confused:
    jsr monster_move_random
    bcc !mpo_conf_no_move+
    lda #1
    sta mat_action_dirty
    jsr mat_mark_move_dirty
!mpo_conf_no_move:

!mpo_writeback:
    jsr monster_write_back
    // Breeder check: clone if CF_BREEDER, room, and lucky roll
    ldx zp_mon_type
    lda cr_mflags,x
    and #CF_BREEDER
    beq !mpo_done+
    lda zp_mon_count
    cmp #MAX_MONSTERS - 4
    bcs !mpo_done+
    lda #12
    jsr rng_range
    cmp #0
    bne !mpo_done+
    // Spawn clone adjacent
    lda zp_mon_x
    sta fae_cx
    lda zp_mon_y
    sta fae_cy
    lda zp_mon_idx
    pha                         // Save original monster index
    jsr find_adjacent_empty
    bcc !breed_fail+
    lda zp_mon_type
    jsr monster_spawn_one
    lda #1
    sta mat_action_dirty
    lda ms_spawn_x
    ldy ms_spawn_y
    jsr mat_mark_tile_dirty_if_nonlocal
!breed_fail:
    pla
    sta zp_mon_idx              // Restore original monster index

!mpo_done:
    lda mat_action_dirty
    beq !mpo_done_clear+
    sec
    rts
!mpo_done_clear:
    clc
    rts

// ============================================================
// mat_mark_move_dirty — mark old/new monster tiles dirty only when the
// normal local redraw does not already cover them.
// Uses zp_mon_type for detect-evil filtering.
// ============================================================
mat_mark_move_dirty:
    lda mat_old_x
    ldy mat_old_y
    jsr mat_mark_tile_dirty_if_nonlocal
    lda zp_mon_x
    ldy zp_mon_y
    // Tail-call the shared tile helper for the new position.
    // If either old or new tile is non-local visible, the turn layer
    // will promote to the expensive redraw path exactly once.
    jmp mat_mark_tile_dirty_if_nonlocal

// ============================================================
// mat_mark_tile_dirty_if_nonlocal — Set mat_scene_dirty only for tiles
// that are both currently render-relevant and outside the normal local
// redraw footprint around the old/current player positions.
// Input: A = map x, Y = map y
// Clobbers: A, X, Y, zp_ptr0/hi, zp_temp0/1, zp_mon_scratch0/1
// ============================================================
mat_mark_tile_dirty_if_nonlocal:
    sta zp_temp0
    sty zp_temp1

    // Skip tiles outside the viewport entirely.
    lda zp_temp0
    sec
    sbc zp_view_x
    bcc !mtd_done+
    cmp #VIEWPORT_W
    bcs !mtd_done+
    lda zp_temp1
    sec
    sbc zp_view_y
    bcc !mtd_done+
    cmp #VIEWPORT_H
    bcs !mtd_done+

    // The existing local redraw already covers tiles near the player.
    // Do not promote those to the full redraw path.
    lda zp_player_x
    sta zp_mon_scratch0
    lda zp_player_y
    sta zp_mon_scratch1
    jsr mat_tile_within_local_radius
    bcs !mtd_done+

    // Inspect the tile's current render state.
    ldx zp_temp1
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_temp0
    :MapRead_ptr0_y()
    sta zp_mon_scratch1

    // Visited + lit tiles are visible remotely and need a redraw.
    lda zp_mon_scratch1
    and #(FLAG_VISITED | FLAG_LIT)
    cmp #(FLAG_VISITED | FLAG_LIT)
    beq !mtd_mark+

!mtd_unvisited:
    // Unvisited tiles only matter while a detect effect is drawing monsters.
    lda eff_detect_timer
    beq !mtd_done+

!mtd_mark:
    lda #1
    sta mat_scene_dirty
!mtd_done:
    rts

// ============================================================
// mat_tile_within_local_radius — true if tile is within the light-radius+1
// square around the center in zp_mon_scratch0/1.
// Input:
//   zp_temp0/zp_temp1 = tile x/y
//   zp_mon_scratch0/1 = center x/y
// Output: carry set = covered by local redraw, clear = non-local
// ============================================================
mat_tile_within_local_radius:
    lda zp_temp0
    sec
    sbc zp_mon_scratch0
    bcs !mtlr_dx_pos+
    eor #$ff
    clc
    adc #1
!mtlr_dx_pos:
    sta zp_mon_scratch0

    lda zp_temp1
    sec
    sbc zp_mon_scratch1
    bcs !mtlr_dy_pos+
    eor #$ff
    clc
    adc #1
!mtlr_dy_pos:
    cmp zp_mon_scratch0
    bcs !mtlr_have_dist+
    lda zp_mon_scratch0
!mtlr_have_dist:
    sta zp_mon_scratch1
    lda zp_light_radius
    clc
    adc #1
    cmp zp_mon_scratch1
    bcs !mtlr_yes+
    clc
    rts
!mtlr_yes:
    sec
    rts

// ============================================================
// monster_wake_check — Check if monster should wake up
// Chebyshev distance to player <= cr_aaf[type], then tick the live sleep
// counter toward zero and wake once it expires.
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
    // In range — tick the live sleep counter down toward wake-up.
    // Contract: monster_process_one enters here with zp_ptr0 already
    // pointing at the current monster entry.
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    beq !mwc_wake+              // sleep=0 → wake immediately
    sec
    sbc #1
    sta (zp_ptr0),y
    bne !mwc_too_far+           // Still asleep this turn

!mwc_wake:
    lda zp_mon_flags
    ora #MF_AWAKE
    sta zp_mon_flags
    // Group wake propagation
    ldx zp_mon_type
    lda cr_mflags,x
    and #CF_GROUP
    beq !mwc_too_far+
    jsr wake_group_nearby

!mwc_too_far:
    rts

// wake_group_nearby — Wake same-type monsters within Chebyshev distance 5
// Input: zp_mon_type, zp_mon_x, zp_mon_y
// Clobbers: A, X, Y, zp_ptr0
wake_group_nearby:
    ldx #0
!wgn_loop:
    cpx #MAX_MONSTERS
    bcs !wgn_done+
    cpx zp_mon_idx
    beq !wgn_next+
    jsr monster_get_ptr         // Preserves X
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !wgn_next+
    cmp zp_mon_type
    bne !wgn_next+
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    bne !wgn_next+
    // Chebyshev distance: max(|dx|, |dy|) <= 5
    ldy #MX_X
    lda (zp_ptr0),y
    sec
    sbc zp_mon_x
    bcs !wdx+
    eor #$ff
    adc #1                      // Carry clear from bcs not taken
!wdx:
    cmp #6
    bcs !wgn_next+
    sta wgn_dist
    ldy #MX_Y
    lda (zp_ptr0),y
    sec
    sbc zp_mon_y
    bcs !wdy+
    eor #$ff
    adc #1
!wdy:
    cmp wgn_dist
    bcc !wmax+
    sta wgn_dist
!wmax:
    lda wgn_dist
    cmp #6
    bcs !wgn_next+
    // Wake it
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_AWAKE
    sta (zp_ptr0),y
!wgn_next:
    inx
    jmp !wgn_loop-
!wgn_done:
    rts
wgn_dist: .byte 0

// ============================================================
// monster_move_toward — Movement toward player with unstick heuristic
// Try diagonal first. Then randomly alternate horizontal/vertical
// to break corner-sticking.
// Clobbers: A, X, Y, zp_ptr0/hi
// ============================================================
monster_move_toward:
    lda #0
    sta mat_fleeing
    jsr mmt_calc_signs          // Set mat_sign_dx/dy toward player
    lda mat_sign_dx
    ora mat_sign_dy
    beq !mmt_done+              // Both zero → no move

    // Try 1: diagonal (sign_dx, sign_dy)
    jsr mmt_set_diag
    jsr monster_try_step
    bcs !mmt_done+

    // Randomly choose horizontal-first or vertical-first (unstick)
    jsr rng_byte
    and #$01
    bne !mmt_vert_first+

    // --- Horizontal first, then vertical ---
    jsr mmt_try_horiz
    bcs !mmt_done+
    jsr mmt_try_vert
    jmp !mmt_done+

!mmt_vert_first:
    // --- Vertical first, then horizontal ---
    jsr mmt_try_vert
    bcs !mmt_done+
    jsr mmt_try_horiz

!mmt_done:
    rts

// --- Helper: compute sign_dx/sign_dy toward player ---
mmt_calc_signs:
    lda zp_player_x
    cmp zp_mon_x
    beq !dx0+
    bcs !dxp+
    lda #$ff
    .byte $2c               // BIT abs — skip next 2 bytes
!dxp:
    lda #$01
    .byte $2c
!dx0:
    lda #$00
    sta mat_sign_dx
    lda zp_player_y
    cmp zp_mon_y
    beq !dy0+
    bcs !dyp+
    lda #$ff
    .byte $2c
!dyp:
    lda #$01
    .byte $2c
!dy0:
    lda #$00
    sta mat_sign_dy
    rts

// --- Helper: set target to diagonal (mon + sign_dx, mon + sign_dy) ---
mmt_set_diag:
    lda zp_mon_x
    clc
    adc mat_sign_dx
    sta mat_target_x
    lda zp_mon_y
    clc
    adc mat_sign_dy
    sta mat_target_y
    rts

// --- Helper: try horizontal move (sign_dx, 0) ---
// Output: carry set = moved
mmt_try_horiz:
    lda mat_sign_dx
    beq !th_fail+
    lda zp_mon_x
    clc
    adc mat_sign_dx
    sta mat_target_x
    lda zp_mon_y
    sta mat_target_y
    jmp monster_try_step
!th_fail:
    clc
    rts

// --- Helper: try vertical move (0, sign_dy) ---
// Output: carry set = moved
mmt_try_vert:
    lda mat_sign_dy
    beq !tv_fail+
    lda zp_mon_x
    sta mat_target_x
    lda zp_mon_y
    clc
    adc mat_sign_dy
    sta mat_target_y
    jmp monster_try_step
!tv_fail:
    clc
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
// monster_check_flee — Check if monster HP is below flee threshold
// Output: carry set = should flee, carry clear = normal
// Clobbers: A, X, Y, zp_ptr0/hi
// ============================================================
monster_check_flee:
    ldx zp_mon_idx
    jsr monster_get_ptr
    // 16-bit compare: flee_threshold > current_HP?
    ldy #MX_FLEE_HI
    lda (zp_ptr0),y           // flee_hi
    ldy #MX_HP_HI
    cmp (zp_ptr0),y           // flee_hi - hp_hi
    bcc !mcf_no+              // flee < hp → no flee
    bne !mcf_flee+            // flee > hp → flee
    // Hi bytes equal — compare lo bytes
    ldy #MX_FLEE_LO
    lda (zp_ptr0),y           // flee_lo
    ldy #MX_HP_LO
    cmp (zp_ptr0),y           // flee_lo - hp_lo
    beq !mcf_no+              // equal → no flee (flee at strictly less)
    bcc !mcf_no+              // flee < hp → no flee
!mcf_flee:
    sec
    rts
!mcf_no:
    clc
    rts

// ============================================================
// monster_move_away — Greedy 3-try movement AWAY from player
// Same algorithm as monster_move_toward but direction is reversed.
// Sets mat_fleeing=1 to suppress attack in monster_try_step.
// Clobbers: A, X, Y, zp_ptr0/hi
// ============================================================
monster_move_away:
    lda #1
    sta mat_fleeing
    // sign_dx = sgn(mon_x - player_x) — AWAY from player
    lda zp_mon_x
    cmp zp_player_x
    beq !mma_dx_zero+
    bcs !mma_dx_pos+
    lda #$ff
    sta mat_sign_dx
    jmp !mma_dy+
!mma_dx_pos:
    lda #$01
    sta mat_sign_dx
    jmp !mma_dy+
!mma_dx_zero:
    lda #$00
    sta mat_sign_dx
!mma_dy:
    lda zp_mon_y
    cmp zp_player_y
    beq !mma_dy_zero+
    bcs !mma_dy_pos+
    lda #$ff
    sta mat_sign_dy
    jmp !mma_try+
!mma_dy_pos:
    lda #$01
    sta mat_sign_dy
    jmp !mma_try+
!mma_dy_zero:
    lda #$00
    sta mat_sign_dy
!mma_try:
    lda mat_sign_dx
    ora mat_sign_dy
    beq !mma_done+
    // Try 1: diagonal
    lda zp_mon_x
    clc
    adc mat_sign_dx
    sta mat_target_x
    lda zp_mon_y
    clc
    adc mat_sign_dy
    sta mat_target_y
    jsr monster_try_step
    bcs !mma_done+
    // Try 2: horizontal
    lda mat_sign_dx
    beq !mma_vert+
    lda zp_mon_x
    clc
    adc mat_sign_dx
    sta mat_target_x
    lda zp_mon_y
    sta mat_target_y
    jsr monster_try_step
    bcs !mma_done+
!mma_vert:
    // Try 3: vertical
    lda mat_sign_dy
    beq !mma_done+
    lda zp_mon_x
    sta mat_target_x
    lda zp_mon_y
    clc
    adc mat_sign_dy
    sta mat_target_y
    jsr monster_try_step
!mma_done:
    lda #0
    sta mat_fleeing
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

    // Fleeing monsters don't attack — just blocked
    lda mat_fleeing
    beq !mts_not_fleeing+
    jmp !mts_blocked+
!mts_not_fleeing:
    lda zp_player_x
    ldy zp_player_y
    jsr glyph_find_at
    bcc !mts_glyph_done_player+
    stx zp_temp0
    jsr monster_should_break_glyph
    ldx zp_temp0
    bcs !mts_break_player_glyph+
    jmp !mts_blocked+
!mts_break_player_glyph:
    jsr glyph_remove
!mts_glyph_done_player:

    // Town creatures don't attack unless provoked
    lda zp_mon_type
    cmp #TOWN_CREATURE_BASE
    bcc !mts_do_attack+
    lda zp_mon_flags
    and #MF_PROVOKED
    bne !mts_do_attack+         // Provoked — attack
    jmp !mts_blocked+           // Not provoked — don't attack
!mts_do_attack:
    // Monster is adjacent → attack player
    jsr monster_attack_player
    jmp !mts_blocked+           // Monster stays in place
!mts_not_player:

    // Bounds check
    lda mat_target_x
    bne !mts_x_nonzero+
    jmp !mts_blocked+
!mts_x_nonzero:
    cmp #MAP_COLS - 1
    bcc !mts_x_inbounds+
    jmp !mts_blocked+
!mts_x_inbounds:
    lda mat_target_y
    bne !mts_y_nonzero+
    jmp !mts_blocked+
!mts_y_nonzero:
    cmp #MAP_ROWS - 1
    bcc !mts_y_inbounds+
    jmp !mts_blocked+
!mts_y_inbounds:

    // Read map tile at target
    ldx mat_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy mat_target_x
    :MapRead_ptr0_y()
    sta zp_mon_scratch1         // Save full tile byte

    // Check walkable
    lsr
    lsr
    lsr
    lsr                         // Tile type index 0-15
    jsr tile_is_walkable
    bcs !mts_walk_ok+
    jmp !mts_blocked+
!mts_walk_ok:

    // Check FLAG_OCCUPIED
    lda zp_mon_scratch1
    and #FLAG_OCCUPIED
    beq !mts_unoccupied+
    jmp !mts_blocked+           // Another monster there
!mts_unoccupied:
    lda mat_target_x
    ldy mat_target_y
    jsr glyph_find_at
    bcc !mts_no_glyph+
    stx zp_temp0
    jsr monster_should_break_glyph
    ldx zp_temp0
    bcs !mts_break_glyph+
    jmp !mts_blocked+
!mts_break_glyph:
    jsr glyph_remove
    lda #1
    sta mat_action_dirty
!mts_no_glyph:

    // Check CF_ATTACK_ONLY — prevent actual movement
    ldx zp_mon_type
    lda cr_mflags,x
    and #CF_ATTACK_ONLY
    beq !mts_can_move+
    jmp !mts_blocked+           // Can't move (but player attack above still fires)
!mts_can_move:

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
    :MapRead_ptr0_y()
    and #~FLAG_OCCUPIED & $ff
    :MapWrite_ptr0_y()

    // Set FLAG_OCCUPIED on new tile
    ldx mat_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy mat_target_x
    :MapRead_ptr0_y()
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()

    sec                         // Success
    rts

!mts_blocked:
    clc
    rts

monster_should_break_glyph:
    lda #12
    jsr rng_range
    bne !msg_hold+
    lda #250
    jsr rng_range
    ldx zp_mon_type
    cmp cr_level,x
    bcc !msg_break+
!msg_hold:
    clc
    rts
!msg_break:
    sec
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
