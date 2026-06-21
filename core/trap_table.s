#importonce
// trap_table.s — Shared trap table lookup/removal helpers.

// trap_remove_at_index — Remove trap table entry X by swapping with the last.
trap_remove_at_index:
    dec trap_count
    ldy trap_count
    lda trap_x,y
    sta trap_x,x
    lda trap_y,y
    sta trap_y,x
    lda trap_type,y
    sta trap_type,x
    rts

// trap_find_target_visible — Find a visible target trap with matching table entry.
// Requires df_target_x/df_target_y from get_direction_target.
// Output: carry set = found, X/index stored in df_disarm_trap_idx.
trap_find_target_visible:
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    bne !not_found+

    ldx #0
!scan:
    cpx trap_count
    bcs !not_found+
    lda trap_x,x
    cmp df_target_x
    bne !next+
    lda trap_y,x
    cmp df_target_y
    bne !next+
    stx df_disarm_trap_idx
    sec
    rts
!next:
    inx
    jmp !scan-
!not_found:
    clc
    rts
