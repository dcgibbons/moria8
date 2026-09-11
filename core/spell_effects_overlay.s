#importonce
// spell_effects_overlay.s — Spell effects whose only product callers live in
// the spell-execution overlay (player_magic_execute_overlay.s) or the
// spell-overlay player_magic_utility.s. Platforms with resident headroom
// import this next to spell_effects.s; Apple IIe imports it into the spell
// overlay so the resident image fits (see docs/CHEST_DESIGN.md step-8 notes).

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
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_TRAP
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()

    inx
    jmp !eft_loop-

!eft_done:
#if CHEST_ROUTING_ENABLED
    // Chest branch (docs/CHEST_DESIGN.md): upstream Find Traps also reveals
    // chest traps — mark found on every armed floor chest.
    jsr chest_mark_found_all
#endif

    // Don't remove traps from table — just reveal them
    lda #1
    sta vis_room_revealed
    rts

#if EFF_DESTROY_TRAPS_DOORS_EXTERNAL
// Apple IIe: body lives in the spell overlay segment in main.s.
#else
// ============================================================
// eff_destroy_traps_doors — Destroy traps and jam doors open in radius
// Scans 8 adjacent tiles. Traps removed, closed doors opened.
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_destroy_traps_doors:
    // First pass: modify map tiles
    lda #0
    sta adj_dir_idx
!edtd_tile_loop:
    lda adj_dir_idx
    cmp #8
    bcs !edtd_tiles_done+
    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y
    jsr !edtd_tile_cb+
    inc adj_dir_idx
    jmp !edtd_tile_loop-
!edtd_tiles_done:
    // Second pass: remove adjacent traps from the trap table. Do this from the
    // table itself so hidden adjacent traps are destroyed too.
    jsr !edtd_remove_adjacent_traps+
    lda #1
    sta vis_room_revealed
    rts

!edtd_tile_cb:
    // Read map tile
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    sta zp_temp0

    // Check for trap
    cmp #TILE_TRAP
    bne !edtd_check_door+
    // Remove trap — set to floor
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_FLOOR
    :MapWrite_ptr0_y()
    rts

!edtd_check_door:
    // Check for closed door or secret door
    lda zp_temp0
    cmp #TILE_DOOR_CLOSED
    beq !edtd_open_door+
    cmp #TILE_SECRET
    bne !edtd_tile_done+

!edtd_open_door:
    // Open the door; any locked/stuck state clears with the lock
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_OPEN
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
    lda df_target_x
    ldy df_target_y
    jsr door_state_clear_at
!edtd_tile_done:
    rts

!edtd_remove_adjacent_traps:
    ldx #0
!edtd_scan:
    cpx trap_count
    bcs !edtd_scan_done+

    lda trap_x,x
    sec
    sbc zp_player_x
    clc
    adc #1
    cmp #3
    bcs !edtd_scan_next+
    lda trap_y,x
    sec
    sbc zp_player_y
    clc
    adc #1
    cmp #3
    bcs !edtd_scan_next+
    lda trap_x,x
    cmp zp_player_x
    bne !edtd_remove+
    lda trap_y,x
    cmp zp_player_y
    beq !edtd_scan_next+

!edtd_remove:
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
    rts
#endif
