#importonce
// los_trace.s — Shared compact tile-blocked LOS trace

.label mm_los_cx  = zp_temp0        // LOS trace current X
.label mm_los_cy  = zp_temp1        // LOS trace current Y
.label mm_los_sdx = zp_mon_scratch3 // LOS step direction X (-1/0/+1)
.label mm_los_sdy = zp_mon_scratch4 // LOS step direction Y (-1/0/+1)

// ============================================================
// mm_los_clear_to_target — Trace tile-blocked LOS to zp_los_dx/zp_los_dy
// Input: mm_los_cx/cy = start, zp_los_dx/dy = target
//        zp_los_step = maximum Chebyshev steps to trace
// Output: carry set = clear, carry clear = blocked
// Clobbers: A, X, Y, zp_ptr0, zp_ptr0_hi, zp_temp0, zp_temp1, zp_temp4,
//           zp_los_err, zp_los_step, zp_mon_scratch3-4
// ============================================================
mm_los_clear_to_target:
    lda zp_los_dx
    sec
    sbc mm_los_cx
    beq !mlx_zero+
    bcc !mlx_neg+
    sta mlos_adx
    lda #1
    bne !mlx_store+
!mlx_neg:
    eor #$ff
    clc
    adc #1
    sta mlos_adx
    lda #$ff
    bne !mlx_store+
!mlx_zero:
    sta mlos_adx
    lda #0
!mlx_store:
    sta mm_los_sdx

    lda zp_los_dy
    sec
    sbc mm_los_cy
    beq !mly_zero+
    bcc !mly_neg+
    sta mlos_ady
    lda #1
    bne !mly_store+
!mly_neg:
    eor #$ff
    clc
    adc #1
    sta mlos_ady
    lda #$ff
    bne !mly_store+
!mly_zero:
    sta mlos_ady
    lda #0
!mly_store:
    sta mm_los_sdy

    lda mlos_adx
    cmp mlos_ady
    bcs !mlos_have_steps+
    lda mlos_ady
!mlos_have_steps:
    tax
    stx mlos_steps
    stx zp_los_step
    beq !mlos_clear_now+
    lda #0
    sta zp_los_err
    sta zp_temp4
    jmp !mlos_step+
!mlos_clear_now:
    sec
    rts

!mlos_step:
    lda mm_los_cx
    sta mlos_oldx
    lda mm_los_cy
    sta mlos_oldy

    lda zp_los_err
    clc
    adc mlos_adx
    cmp mlos_steps
    bcc !mlos_no_x+
    sbc mlos_steps
    sta zp_los_err
    lda mm_los_cx
    clc
    adc mm_los_sdx
    sta mm_los_cx
    jmp !mlos_y+
!mlos_no_x:
    sta zp_los_err

!mlos_y:
    lda zp_temp4
    clc
    adc mlos_ady
    cmp mlos_steps
    bcc !mlos_no_y+
    sbc mlos_steps
    sta zp_temp4
    lda mm_los_cy
    clc
    adc mm_los_sdy
    sta mm_los_cy
    jmp !mlos_target+
!mlos_no_y:
    sta zp_temp4

!mlos_target:
!mlos_side_check:
    lda mm_los_cx
    cmp mlos_oldx
    beq !mlos_check_tile+
    lda mm_los_cy
    cmp mlos_oldy
    beq !mlos_check_tile+

    // Diagonal edge crossing: at least one orthogonal side cell must be open.
    ldx mlos_oldy
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy mm_los_cx
    :MapRead_ptr0_y()
    jsr mlos_tile_open
    bcs !mlos_check_tile+
    ldx mm_los_cy
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy mlos_oldx
    :MapRead_ptr0_y()
    jsr mlos_tile_open
    bcc !mlos_blocked+

!mlos_check_tile:
    // The target tile may hold the monster/player; do not treat it as blocking.
    lda mm_los_cx
    cmp zp_los_dx
    bne !mlos_read_tile+
    lda mm_los_cy
    cmp zp_los_dy
    beq !mlos_clear+

!mlos_read_tile:
    ldx mm_los_cy
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy mm_los_cx
    :MapRead_ptr0_y()
    jsr mlos_tile_open
    bcc !mlos_blocked+
    dec zp_los_step
    beq !mlos_clear+
    jmp !mlos_step-

!mlos_blocked:
    clc
    rts

!mlos_clear:
    sec
    rts

mlos_tile_open:
    and #TILE_TYPE_MASK
    lsr
    lsr
    lsr
    lsr
    tax
    lda walkable_table,x
    beq !closed+
    sec
    rts
!closed:
    clc
    rts

mlos_adx:   .byte 0
mlos_ady:   .byte 0
mlos_steps: .byte 0
mlos_oldx:  .byte 0
mlos_oldy:  .byte 0
