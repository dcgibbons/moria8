#importonce
// Banked C64 helpers for high-end prayer targeting/feedback. The C64 resident
// image and spell overlay are byte-tight; these routines are copied to $F000.

#if !PMU_TURN_FEEDBACK_ONLY
pmu_find_visible_flagged:
!pfvf_loop:
    ldx pmx_work_idx
    cpx #MAX_MONSTERS
    bcs !pfvf_none+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !pfvf_next+
    sta cmb_type
    tax
    lda cr_mflags,x
    and pmx_work_flag
    beq !pfvf_next+
    ldy #MX_X
    lda (zp_ptr0),y
    tax
    ldy #MX_Y
    lda (zp_ptr0),y
    tay
    jsr los_is_visible
    bcc !pfvf_next+
    sec
    rts
!pfvf_next:
    inc pmx_work_idx
    bne !pfvf_loop-
!pfvf_none:
    clc
    rts
#endif

combat_msg_monster_runs_frantically:
    lda #<cmb_runs_frantically_str
    ldy #>cmb_runs_frantically_str
    jmp combat_msg_monster_suffix

combat_msg_monster_unaffected:
    lda #<cmb_unaffected_str
    ldy #>cmb_unaffected_str
    jmp combat_msg_monster_suffix

cmb_runs_frantically_str:
    .text " runs frantically!" ; .byte 0
cmb_unaffected_str:
    .text " is unaffected." ; .byte 0
