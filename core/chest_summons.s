#importonce
// chest_summons.s — Resident handoff for chest summoning traps
// (docs/CHEST_DESIGN.md). The chest overlay stages chest_pending_summons;
// the resident verb trampolines call chest_run_pending_summons after the
// handler returns, because monster_spawn_one reads the tier buffer that
// aliases the overlay window. Placed via the platform ChestSummonsSegment
// macros so tight ports can park it outside full payloads.

// chest_pending_summons — Pending chest summoning-trap spawn attempts.
// Staged by the chest overlay (trap fire); consumed here as the loop
// counter, so it is always zero on return.
chest_pending_summons: .byte 0

// chest_run_pending_summons — Each attempt picks a random adjacent tile
// around the staged chest position (chest_summon_x/y) and spawns a
// depth-appropriate monster if the tile is walkable, monster-free, and not
// the player's own tile (same invariant as find_adjacent_empty); failures
// discard the attempt (VMS form). Preserves the caller's flags: cmd_disarm
// and chest_run_deferred carry the turn-consumed result across this call.
// Clobbers: A, X, Y, zp_ptr0
:ChestSummonsSegment()
chest_run_pending_summons:
    php
    lda chest_pending_summons
    beq !crps_done+
!crps_loop:
    lda #8
    jsr rng_range
    tax
    lda chest_summon_y
    clc
    adc dir_dy,x
    tay                         // Y = candidate y
    lda chest_summon_x
    clc
    adc dir_dx,x                // A = candidate x

    // Never the player's own tile
    cpy zp_player_y
    bne !crps_not_player+
    cmp zp_player_x
    beq !crps_attempt_done+
!crps_not_player:
    sta ms_spawn_x
    sty ms_spawn_y

    // Walkable tile (floor or open door)?
    tya
    tax                         // X = candidate y (row-table index)
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
    dec chest_pending_summons
    bne !crps_loop-
!crps_done:
    plp
    rts
:ChestSummonsRestoreSegment()
