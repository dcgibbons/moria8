#importonce
// eff_find_traps_cold.s — Cold Find Traps map/chest reveal effect
//
// Module ownership:
//   owner: same segment as spell_effects_overlay.s when !EFF_FIND_TRAPS_EXTERNAL,
//     or port spell/utility overlay when EFF_FIND_TRAPS_EXTERNAL is defined.
//   lifetime: one Find Traps spell/scroll/staff invocation.
//   callers: spell/item dispatch tables (directly if co-located or via port
//     trampoline).

#import "df_target_row.s"

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
    jsr map_row_ptr0_y
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
