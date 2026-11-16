#importonce
#import "df_target_dir.s"
#import "df_target_row.s"
// spell_effects_overlay.s — Spell effects whose only product callers live in
// the spell-execution overlay (player_magic_execute_overlay.s) or the
// spell-overlay player_magic_utility.s.
// Owner: the spell overlay where it has room (C64 and Commander X16 OVL.SPELL);
// resident elsewhere, next to spell_effects.s (the Apple IIe keeps only
// eff_destroy_traps_doors in its spell overlay, EFF_DESTROY_TRAPS_DOORS_EXTERNAL;
// docs/CHEST_DESIGN.md step-8 notes). Lifetime: one cast. Callers: the spell
// dispatch tables only; nothing outside the spell overlay may call these.

#if !EFF_FIND_TRAPS_EXTERNAL
#import "eff_find_traps_cold.s"
#endif

#if EFF_DESTROY_TRAPS_DOORS_EXTERNAL
// Apple IIe: body lives in the spell overlay segment in main.s.
#else
// ============================================================
// eff_destroy_traps_doors — Destroy traps and jam doors open in radius
// Scans 8 adjacent tiles. Traps removed, closed doors opened.
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_destroy_traps_doors:
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
