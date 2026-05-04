#importonce
// player_magic_ball.s — shared ball-style spell effects
//
// Kept out of the execute overlay so ball-family runtime tests can import the
// real production owner without dragging in the whole spell-dispatch overlay.

ball_work_idx:    .byte 0
ball_work_x:      .byte 0
ball_work_y:      .byte 0
ball_work_x2:     .byte 0
ball_work_y2:     .byte 0
ball_work_damage: .byte 0
ball_prev_x:      .byte 0
ball_prev_y:      .byte 0
ball_flash_idx:   .byte 0

ball_flash_dx:
    .byte $ff, $00, $01
    .byte $ff, $00, $01
    .byte $ff, $00, $01

ball_flash_dy:
    .byte $ff, $ff, $ff
    .byte $00, $00, $00
    .byte $01, $01, $01

// eff_ball — Fire a directional ball spell that explodes on the first
// blocking tile or monster and damages monsters in the target area.
// Input: A = base damage
// Clobbers: A, X, Y, zp_ptr0, zp_math_a/b
eff_ball:
    sta ball_work_damage
    jsr get_direction_target
    bcs !eball_have_dir+
    rts
!eball_have_dir:
    jsr calc_direction_index
    bcs !eball_trace_init+
    rts
!eball_trace_init:
    lda zp_player_x
    sta proj_cx
    sta ball_prev_x
    lda zp_player_y
    sta proj_cy
    sta ball_prev_y
    lda #20
    sta proj_steps
!eball_trace:
    dec proj_steps
    beq !eball_explode_prev+
    lda proj_cx
    sta ball_prev_x
    lda proj_cy
    sta ball_prev_y
    jsr trace_step
    bcc !eball_explode_prev+
    lda proj_cy
    sec
    sbc zp_view_y
    bcc !eball_no_anim+
    cmp #VIEWPORT_H
    bcs !eball_no_anim+
    clc
    adc #VIEWPORT_Y
    tax

    lda proj_cx
    sec
    sbc zp_view_x
    bcc !eball_no_anim+
    cmp #VIEWPORT_W
    bcs !eball_no_anim+
    clc
    adc #VIEWPORT_X
    tay
    jsr screen_flash_at
!eball_no_anim:
    lda proj_cx
    ldy proj_cy
    jsr monster_find_at
    bcs !eball_target_here+
    jmp !eball_trace-
!eball_target_here:
    lda proj_cx
    sta ball_work_x
    lda proj_cy
    sta ball_work_y
    jmp !eball_apply+
!eball_explode_prev:
    lda ball_prev_x
    sta ball_work_x
    lda ball_prev_y
    sta ball_work_y
!eball_apply:
    jsr eff_ball_animate_explosion
    lda #0
    sta ball_work_idx
!eball_loop:
    ldx ball_work_idx
    cpx #MAX_MONSTERS
    bcs !eball_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !eball_next+
    ldy #MX_X
    lda (zp_ptr0),y
    sta ball_work_x2
    sec
    sbc ball_work_x
    bcs !eball_dx_pos+
    eor #$ff
    clc
    adc #1
!eball_dx_pos:
    cmp #2
    bcs !eball_next+
    ldy #MX_Y
    lda (zp_ptr0),y
    sta ball_work_y2
    sec
    sbc ball_work_y
    bcs !eball_dy_pos+
    eor #$ff
    clc
    adc #1
!eball_dy_pos:
    cmp #2
    bcs !eball_next+
    ldx ball_work_idx
    lda ball_work_damage
    sta zp_math_a
    lda #0
    sta zp_math_b
    jsr combat_apply_damage_16
    bcc !eball_next+
    jsr combat_kill_message
!eball_next:
    inc ball_work_idx
    jmp !eball_loop-
!eball_done:
#if C128
#if PERF_P1
    jmp perf_p1_render_viewport_effect_direct
#else
    jsr render_viewport
    rts
#endif
#else
    jsr render_viewport
    rts
#endif

eff_ball_animate_explosion:
    lda #0
    sta ball_flash_idx
!eball_flash_loop:
    ldx ball_flash_idx
    cpx #9
    bcs !eball_flash_done+

    lda ball_work_y
    clc
    adc ball_flash_dy,x
    cmp #MAP_ROWS
    bcs !eball_flash_next+
    sec
    sbc zp_view_y
    bcc !eball_flash_next+
    cmp #VIEWPORT_H
    bcs !eball_flash_next+
    clc
    adc #VIEWPORT_Y
    pha

    ldx ball_flash_idx
    lda ball_work_x
    clc
    adc ball_flash_dx,x
    cmp #MAP_COLS
    bcs !eball_flash_discard_row+
    sec
    sbc zp_view_x
    bcc !eball_flash_discard_row+
    cmp #VIEWPORT_W
    bcs !eball_flash_discard_row+
    clc
    adc #VIEWPORT_X
    tay

    pla
    tax
    jsr screen_flash_at
    jmp !eball_flash_next+

!eball_flash_discard_row:
    pla
!eball_flash_next:
    inc ball_flash_idx
    jmp !eball_flash_loop-
!eball_flash_done:
    rts
