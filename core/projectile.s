#importonce
// projectile.s — Shared projectile tracing helpers
//
// Used by ranged_fire.s, throw.s, spell_effects.s
// Provides calc_direction_index and trace_step.

// ============================================================
// Shared projectile variables
// ============================================================
proj_cx:    .byte 0     // Current trace X
proj_cy:    .byte 0     // Current trace Y
proj_dir:   .byte 0     // Direction index 0-7
proj_steps: .byte 0     // Steps remaining

// ============================================================
// calc_direction_index — Convert df_target_x/y to direction 0-7
// Reads df_target_x/y and zp_player_x/y, searches dir_dx/dir_dy.
// Output: X = direction index, stored in proj_dir. Carry set = found.
//         Carry clear = not found (no valid direction).
// Clobbers: A, X, zp_temp0, zp_temp1
// ============================================================
calc_direction_index:
    lda df_target_x
    sec
    sbc zp_player_x
    sta zp_temp0                    // dx
    lda df_target_y
    sec
    sbc zp_player_y
    sta zp_temp1                    // dy

    ldx #0
!cdi_loop:
    lda dir_dx,x
    cmp zp_temp0
    bne !cdi_next+
    lda dir_dy,x
    cmp zp_temp1
    beq !cdi_found+
!cdi_next:
    inx
    cpx #8
    bcc !cdi_loop-
    clc                             // Not found
    rts
!cdi_found:
    stx proj_dir
    sec                             // Found
    rts

// ============================================================
// trace_step — Advance one step and check bounds + walkability
// Reads proj_cx/cy/dir. Writes proj_cx/cy.
// Output: carry set = new position is walkable
//         carry clear = blocked (out of bounds or non-walkable tile)
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
trace_step:
    // Step in direction
    ldx proj_dir
    lda proj_cx
    clc
    adc dir_dx,x
    sta proj_cx
    lda proj_cy
    clc
    adc dir_dy,x
    sta proj_cy

    // Bounds check
    lda proj_cx
    beq !ts_blocked+
    cmp #MAP_COLS - 1
    bcs !ts_blocked+
    lda proj_cy
    beq !ts_blocked+
    cmp #MAP_ROWS - 1
    bcs !ts_blocked+

    // Walkability check
    ldx proj_cy
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy proj_cx
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    lsr
    lsr
    lsr
    lsr
    tax
    lda walkable_table,x
    beq !ts_blocked+
    sec                             // Walkable
    rts
!ts_blocked:
    clc                             // Blocked
    rts
