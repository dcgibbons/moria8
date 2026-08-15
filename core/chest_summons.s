#importonce
// chest_summons.s — Resident handoff for chest summoning traps
// (docs/CHEST_DESIGN.md). The chest overlay stages chest_pending_summons;
// the resident verb trampolines call chest_run_pending_summons after the
// handler returns, because monster_spawn_one reads the tier buffer that
// aliases the overlay window. Placed via the platform ChestSummonsSegment
// macros so tight ports can park it outside full payloads.

// chest_pending_summons — Pending chest summoning-trap spawn attempts.
// Staged by the chest overlay (trap fire); consumed here.
chest_pending_summons: .byte 0

// chest_run_pending_summons — Each attempt picks a random adjacent tile
// around the chest and spawns a depth-appropriate monster if the tile is
// free; failures discard the attempt (VMS form).
// Clobbers: A, X, Y, zp_ptr0
:ChestSummonsSegment()
chest_run_pending_summons:
    lda chest_pending_summons
    beq !crps_done+
    sta crps_count
!crps_loop:
    lda #8
    jsr rng_range
    tax
    lda df_target_x
    clc
    adc dir_dx,x
    sta ms_spawn_x
    lda df_target_y
    clc
    adc dir_dy,x
    sta ms_spawn_y

    // Walkable tile (floor or open door)?
    ldx ms_spawn_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy ms_spawn_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !crps_free+
    cmp #TILE_DOOR_OPEN
    bne !crps_attempt_done+
!crps_free:
    // Unoccupied?
    lda ms_spawn_x
    ldy ms_spawn_y
    jsr monster_find_at
    bcs !crps_attempt_done+
    jsr pick_creature_type
    jsr monster_spawn_one
!crps_attempt_done:
    dec crps_count
    bne !crps_loop-
    lda #0
    sta chest_pending_summons
!crps_done:
    rts

crps_count: .byte 0
:ChestSummonsRestoreSegment()
