// eff_doors_traps_cold.s — Shared Find Doors and Destroy Traps/Doors bodies
//
// Module ownership:
//   - Direct imports via spell_effects.s (!EFF_FIND_DOORS_EXTERNAL, sets
//     EFF_DOORS_TRAPS_EMIT_DOORS_ONLY) and spell_effects_overlay.s
//     (!EFF_DESTROY_TRAPS_DOORS_EXTERNAL, sets EFF_DOORS_TRAPS_EMIT_DESTROY_ONLY):
//     emits each body into its respective segment (Default / OVL.SPELL).
//   - Direct port overlay import (Apple IIe OVL.DEATH, BBC Master OVL.HELP)
//     with neither selector set: emits both eff_find_doors_impl and
//     eff_destroy_traps_doors_impl sequentially for resident trampolines.
//   lifetime: one Find Doors or Trap/Door Destruction invocation.
//   callers: eff_find_doors / eff_destroy_traps_doors (direct or trampolined).

#if !EFF_DOORS_TRAPS_EMIT_DESTROY_ONLY
eff_fd_row: .byte 0

#if EFF_DOORS_TRAPS_EMIT_DOORS_ONLY
eff_find_doors:
#endif
eff_find_doors_impl:
#if HAL_PLATFORM_TURBO_BURST_HOOKS
    jsr c64u_turbo_fast
#endif
    lda #1
    sta eff_fd_row
!efd_row_loop:
    ldx eff_fd_row
    jsr map_row_ptr0_x
    ldy #1
!efd_col_loop:
    :MapRead_ptr0_y()
    tax
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    bne !efd_col_next+
    txa
    and #TILE_FLAG_MASK
    ora #(TILE_DOOR_CLOSED | FLAG_VISITED)
    :MapWrite_ptr0_y()
!efd_col_next:
    iny
    cpy #MAP_COLS - 1
    bcc !efd_col_loop-
    inc eff_fd_row
    lda eff_fd_row
    cmp #MAP_ROWS - 1
    bcc !efd_row_loop-
#if HAL_PLATFORM_TURBO_BURST_HOOKS
    jsr c64u_turbo_normal
#endif
    lda #1
    sta vis_room_revealed
    rts
#endif

#if !EFF_DOORS_TRAPS_EMIT_DOORS_ONLY
// ============================================================
// eff_destroy_traps_doors — Destroy traps and jam doors open in radius
// Scans 8 adjacent tiles. Traps removed, closed doors opened.
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
#if EFF_DOORS_TRAPS_EMIT_DESTROY_ONLY
eff_destroy_traps_doors:
#endif
eff_destroy_traps_doors_impl:
    // First pass: modify 8 adjacent map tiles
    ldx #7
    stx adj_dir_idx
!edtd_tile_loop:
    ldx adj_dir_idx
    jsr df_target_from_dir
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    sta zp_temp0
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    bne !edtd_check_door+
    lda zp_temp0
    and #TILE_FLAG_MASK             // TILE_FLOOR == $00
    jmp !edtd_write_tile+

!edtd_check_door:
    cmp #TILE_DOOR_CLOSED
    beq !edtd_open_door+
    cmp #TILE_SECRET
    bne !edtd_tile_done+
!edtd_open_door:
    lda zp_temp0
    and #TILE_FLAG_MASK
    ora #(TILE_DOOR_OPEN | FLAG_VISITED)
    :MapWrite_ptr0_y()
    lda df_target_x
    ldy df_target_y
    jsr door_state_clear_at
    jmp !edtd_tile_done+
!edtd_write_tile:
    :MapWrite_ptr0_y()
!edtd_tile_done:
    dec adj_dir_idx
    bpl !edtd_tile_loop-

    // Second pass: remove adjacent traps from the trap table (incl. hidden)
    ldx #0
!edtd_scan:
    cpx trap_count
    bcs !edtd_scan_done+
    lda trap_x,x
    sec
    sbc zp_player_x
    sta zp_temp0
    clc
    adc #1
    cmp #3
    bcs !edtd_scan_next+
    lda trap_y,x
    sec
    sbc zp_player_y
    tay
    clc
    adc #1
    cmp #3
    bcs !edtd_scan_next+
    tya
    ora zp_temp0
    beq !edtd_scan_next+

    dec trap_count
    ldy trap_count
    lda trap_x,y
    sta trap_x,x
    lda trap_y,y
    sta trap_y,x
    lda trap_type,y
    sta trap_type,x
    jmp !edtd_scan-                 // Re-check this index (swapped entry)

!edtd_scan_next:
    inx
    bne !edtd_scan-
!edtd_scan_done:
    lda #1
    sta vis_room_revealed
    rts
#endif
