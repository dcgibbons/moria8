#importonce
// Resolve FLAG_OCCUPIED against the live monster table and repair stale flags.

pm_live_occ_x: .byte 0
pm_live_occ_y: .byte 0

// Input: A=x, Y=y
// Output: carry set = live monster present, X = slot index
//         carry clear = no live monster; stale FLAG_OCCUPIED cleared
// Clobbers: A, X, Y, zp_ptr0/hi
player_move_check_live_occupant:
    sta pm_live_occ_x
    sty pm_live_occ_y
    jsr monster_find_at
    bcs !found+

    ldx pm_live_occ_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy pm_live_occ_x
    :MapRead_ptr0_y()
    and #~FLAG_OCCUPIED & $ff
    :MapWrite_ptr0_y()
    clc
    rts

!found:
    sec
    rts
