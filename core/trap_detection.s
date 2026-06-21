#importonce
// trap_detection.s — Shared floor-trap detection after movement.

// ============================================================
// trap_check_at_player — Check if player stepped on a trap
// Scans trap table for player's (x, y). If found: reveal trap on map and
// trigger it. Matching umoria, ordinary triggered floor traps remain live and
// can still be disarmed later.
// Called after successful movement.
// ============================================================
trap_check_at_player:
    lda trap_count
    beq !tcp_done+          // No traps

    ldx #0
!tcp_loop:
    cpx trap_count
    bcs !tcp_done+

    lda trap_x,x
    cmp zp_player_x
    bne !tcp_next+
    lda trap_y,x
    cmp zp_player_y
    bne !tcp_next+

    // Found a trap at player position!
    // Save trap index
    stx df_dir_idx

    // Reveal trap on map: change tile to TILE_TRAP | flags
    ldy zp_player_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy zp_player_x
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK     // Keep existing flags
    ora #TILE_TRAP          // Set tile type to trap
    ora #FLAG_VISITED       // Ensure visible
    :MapWrite_ptr0_y()

    // Trigger the trap effect
    ldx df_dir_idx
    jsr trap_trigger

    // Done (only one trap per tile)
    sec                     // Carry set = trap fired
    rts

!tcp_next:
    inx
    jmp !tcp_loop-

!tcp_done:
    clc                     // Carry clear = no trap
    rts
