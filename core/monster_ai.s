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
mat_scene_dirty: .byte 0     // count of immediate non-local visible tile renders this turn (nonzero = cheap redraw path)
mat_action_dirty: .byte 0    // 1 if current monster changed gameplay state
mat_player_stealth: .byte 0  // Race/class threshold cached once per AI tick

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
    jsr player_get_stealth
    sta mat_player_stealth

!mat_loop:
    lda zp_mon_idx
    cmp #MAX_MONSTERS
    bcc !mat_have_slot+
    jmp !mat_done+
!mat_have_slot:

    // Load monster entry into ZP scratch
    tax
    jsr monster_get_ptr         // zp_ptr0 → entry

    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !mat_active_slot+
    jmp !mat_next+              // Skip empty slot
!mat_active_slot:
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
    // Fold player speed into this monster's cadence (Umoria
    // playerChangeSpeed model, applied per-tick so no stored monster state
    // is mutated): an active haste timer or Ring of Speed (PFLAG_SPEED)
    // slows the monster by 1; an active slow timer hastens it by 1. The
    // 0-2 cadence clamp makes stacking haste+ring identical to either
    // alone, so a single step per direction suffices.
    lda zp_eff_speed
    bmi !mat_pc_slow+
    bne !mat_pc_dec+
    lda player_pflags
    and #PFLAG_SPEED
    beq !mat_pc_done+
!mat_pc_dec:
    lda zp_mon_speed
    beq !mat_pc_done+
    dec zp_mon_speed
    jmp !mat_pc_done+
!mat_pc_slow:
    lda zp_mon_speed
    cmp #2
    beq !mat_pc_done+
    inc zp_mon_speed
!mat_pc_done:
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
    rol mat_any_moved          // Carry is set; only zero/nonzero is observed.
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
    rol mat_any_moved          // Preserve the nonzero moved invariant.
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
    lda #$81
    sta mat_action_dirty
!mpo_town_no_move:
    jmp !mpo_writeback+
!mpo_not_town:

    // Check if monster should flee (HP < threshold)
    jsr monster_check_flee
    bcs !mpo_flee+

    // Normal movement: move toward player
    jsr monster_move_toward
    bcc !mpo_toward_no_move+
    lda #$81
    sta mat_action_dirty
!mpo_toward_no_move:
    jmp !mpo_writeback+

!mpo_flee:
    jsr monster_move_away
    bcc !mpo_flee_no_move+
    lda #$81
    sta mat_action_dirty
!mpo_flee_no_move:
    jmp !mpo_writeback+

!mpo_confused:
    jsr monster_move_random
    bcc !mpo_conf_no_move+
    lda #$81
    sta mat_action_dirty
!mpo_conf_no_move:

!mpo_writeback:
    jsr monster_write_back
    lda mat_action_dirty
    bpl !mpo_no_move_dirty+
    jsr mat_mark_move_dirty
!mpo_no_move_dirty:
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
    // Inline mat_tile_within_local_radius: true if the tile is within the
    // light-radius+1 square around zp_mon_scratch0/1. Carry set = covered.
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
    bcs !mtd_done+              // covered by local redraw — done

    lda zp_mon_flags
    and #(MF_VISIBLE | MF_DETECTED)
    beq !mtd_done+

!mtd_mark:
    jsr scene_render_mat_tile
!mtd_done:
    rts

// ============================================================
// monster_wake_check — Check if monster should wake up
// Chebyshev distance to player <= cr_aaf[type], then tick the compact live
// sleep counter toward zero using a scaled approximation of VMS Moria's 75/d
// wake pressure. Wake immediately when the live counter is already zero.
// Sets MF_AWAKE in zp_mon_flags if waking up.
// Clobbers: A, X, Y, zp_temp0-4, zp_math_a/b/tmp0/tmp1
// ============================================================
monster_wake_check:
    jsr monster_distance_to_player
    sta zp_mon_scratch0

    // Compare distance to awareness factor (bit 7 carries CD_OPEN_DOOR)
    ldx zp_mon_type
    lda cr_aaf,x
    and #$7f
    cmp zp_mon_scratch0         // In range when aaf >= distance
    bcs !mwc_in_range+
    lda zp_mon_flags            // Visible monsters are wake-eligible too.
    and #MF_VISIBLE
    beq !mwc_too_far+
!mwc_in_range:
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    beq !mwc_wake+              // Naturally alert monsters do not roll stealth.

#if C64_UNIT_TEST || C128_UNIT_TEST
#if MONSTER_AI_PRODUCTION_REST_STATE
    lda auto_rest_active
#else
    lda monster_resting
#endif
#else
    lda auto_rest_active
#endif
    bne !mwc_too_far+          // VMS Moria applies no ordinary wake pressure while resting.

    // VMS Moria only applies wake pressure when randint(10) exceeds the
    // player's stealth. rng_range(10) returns 0..9, so >= stealth is the
    // equivalent comparison.
    lda mat_player_stealth
    sta zp_temp2
    lda #10
    jsr rng_range
    cmp zp_temp2
    bcc !mwc_too_far+

    // In range — tick the live sleep counter down toward wake-up.
    // Contract: monster_process_one enters here with zp_ptr0 already
    // pointing at the current monster entry.
    ldx zp_mon_scratch0
    cpx #6
    bcc !mwc_have_wake_step+
    ldx #6
!mwc_have_wake_step:
    lda mwc_wake_step,x
    sta zp_mon_scratch0
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    sec
    sbc zp_mon_scratch0
    bcs !mwc_store_sleep+
    lda #0
!mwc_store_sleep:
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

// Compact scale for VMS Moria's floor(75/d) pressure after compressing the
// upstream sleep counter to one byte. Index 0 is defensive; monsters cannot
// ordinarily occupy the player's tile.
mwc_wake_step:
    .byte 8, 8, 4, 3, 2, 2, 1   // distance 0, 1, 2, 3, 4, 5, 6+
mwc_wake_step_end:
.assert "Wake-pressure table size", mwc_wake_step_end - mwc_wake_step, 7

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
    jsr monster_wake
!wgn_next:
    inx
    jmp !wgn_loop-
!wgn_done:
    rts
wgn_dist: .byte 0
#if C64_UNIT_TEST || C128_UNIT_TEST
#if !MONSTER_AI_PRODUCTION_REST_STATE
monster_resting: .byte 0
#endif
#endif

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
    jmp monster_try_step
    // Don't try alternatives — confused movement is unreliable


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
    txa
    pha
    jsr monster_should_break_glyph
    pla
    tax
    bcc !mts_break_player_glyph+
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
    jmp !mts_door_block+
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
    txa
    pha
    jsr monster_should_break_glyph
    pla
    tax
    bcc !mts_break_glyph+
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

// Blocked tile — Umoria monsterOpenDoor parity: door-capable
// monsters (cr_aaf bit 7) open closed doors and pass secret doors;
// others may bash closed doors. Any door action consumes the move
// without stepping into the doorway.
!mts_door_block:
    lda zp_mon_scratch1
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    beq !mts_secret+
    cmp #TILE_DOOR_CLOSED
    bne !mts_blocked+           // Not a door — blocked
    lda zp_mon_scratch1
    lsr                         // FLAG_OCCUPIED is bit 0
    bcs !mts_blocked+           // Occupied doors cannot be opened/bashed
    ldx zp_mon_type
    lda cr_aaf,x
    bpl !mts_bash+              // Bit 7 clear: bash fallback
    jsr mts_write_open          // Door-capable: silent open (ptr intact)
    jmp !mts_blocked+
!mts_bash:
    jsr mts_bash_roll           // Carry set = door bursts open
    bcc !mts_blocked+
    jsr mts_write_open          // zp_ptr0/y preserved by the roll
    ldx #HSTR_MAT_DOOR_BURST
    jsr huff_print_msg
    jmp !mts_blocked+
!mts_secret:
    ldx zp_mon_type
    lda cr_aaf,x
    bpl !mts_blocked+           // Not door-capable: blocked
    jmp !mts_walk_ok-           // Door-capable monsters pass secret doors

!mts_blocked:
    clc
    rts

// ============================================================
// mts_write_open — Convert the target closed door to open.
// Expects zp_ptr0/y addressing the target tile (preserved across
// tile_is_walkable); bash path restores the pointer first.
// Marks gameplay state changed and dirties the tile when relevant.
// Clobbers: A, X, Y, zp_temp0/1, zp_mon_scratch0/1
// ============================================================
mts_write_open:
    lda zp_mon_scratch1
    eor #$f0                    // $8_ closed -> $7_ open, flag nibble kept
    :MapWrite_ptr0_y()
    lda #1
    sta mat_action_dirty
    lda mat_target_x
    ldy mat_target_y
    jmp mat_mark_tile_dirty_if_nonlocal

// ============================================================
// mts_bash_roll — Umoria bash fallback for monsters without
// CM_OPEN_DOOR: randomNumber((hp+1)*80) < 40*(hp-20) with current
// HP (clamped to 254 so hp+1 fits a byte; hp 255+ plays as 254,
// a <=0.1% probability shift). rng_range_word rolls 0..N-1, so the
// success threshold is 40*(hp-20)-1. HP <= 20 can never bash.
// Output: carry set = door bursts open, carry clear = holds
// Preserves zp_ptr0/y (the target-tile pointer for mts_write_open).
// Clobbers: A, X, zp_temp0-3, zp_math_*
// ============================================================
mts_bash_roll:
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    beq !mbr_lo+
    lda #$fe                    // 16-bit HP: play as 254
    bne !mbr_capped+            // always
!mbr_lo:
    ldy #MX_HP_LO
    lda (zp_ptr0),y
!mbr_capped:
    cmp #$ff
    bne !mbr_in_range+
    lda #$fe                    // clamp 255 -> 254 so hp+1 fits a byte
!mbr_in_range:
    cmp #21
    bcc !mbr_out+               // hp <= 20: no bash chance (carry already clear)
    tay                         // Y = hp across both multiplies
    // K = 40*(hp-20) - 1 (16-bit success threshold)
    sbc #20                     // carry set by cmp (hp >= 21)
    ldx #40
    jsr math_multiply           // A = lo, zp_math_b = hi
    sec
    sbc #1
    sta mbr_k_lo
    lda zp_math_b
    sbc #0
    sta mbr_k_hi
    // N = (hp+1)*80 (hp <= 254, so N <= 20400)
    tya
    clc
    adc #1
    ldx #80
    jsr math_multiply           // A = lo, zp_math_b = hi
    sta zp_temp0
    lda zp_math_b
    sta zp_temp1
    jsr rng_range_word          // zp_temp2/3 = roll in [0, N-1]
    sec
    lda zp_temp2
    sbc mbr_k_lo
    lda zp_temp3
    sbc mbr_k_hi
    bcc !mbr_win+               // roll < K: door bursts
    clc
    jmp !mbr_out+
!mbr_win:
    sec
!mbr_out:
    // PLA/STA/LDY do not affect carry; the result survives the restore.
    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    ldy mat_target_x            // Restore target Y index
    rts

mbr_k_lo:  .byte 0
mbr_k_hi:  .byte 0

monster_should_break_glyph:
    lda #<$0bb8
    sta zp_temp0
    lda #>$0bb8
    sta zp_temp1
    jsr rng_range_word          // upstream: randint(3000) < monster level
    lda zp_temp3
    bne !msg_hold+
    inc zp_temp2                // convert 0..2999 to upstream 1..3000
    beq !msg_hold+
    lda zp_temp2
    ldx zp_mon_type
    cmp cr_level,x
    rts
!msg_hold:
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
