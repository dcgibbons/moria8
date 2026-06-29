#importonce
// player_magic_detect.s — shared detect spell/prayer feedback helpers
//
// Kept separate from the main execute overlay so focused suites can verify
// result vs no-result messaging without importing the full dispatch surface.

pmx_detect_monsters_msg:
    jsr eff_detect_monsters
    jsr pmx_any_active_monster
    bcc !pdm_done+
    ldx #HSTR_PIQ_SENSE
    jsr huff_print_msg
    rts
!pdm_done:
    lda #<pmx_msg_no_creatures
    ldy #>pmx_msg_no_creatures
    jmp pmx_detect_print_inline

pmx_detect_evil_msg:
    jsr eff_detect_evil_only
    beq !pdem_none+
    lda #<pmx_msg_evil_on
    ldy #>pmx_msg_evil_on
    jmp pmx_detect_print_inline
!pdem_none:
    lda #<pmx_msg_no_evil
    ldy #>pmx_msg_no_evil
    jmp pmx_detect_print_inline

pmx_any_active_monster:
    ldx #0
!paam_loop:
    cpx #MAX_MONSTERS
    bcs !paam_none+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !paam_found+
    inx
    jmp !paam_loop-
!paam_found:
    sec
    rts
!paam_none:
    clc
    rts

pmx_detect_print_inline:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp msg_print

pmx_msg_evil_on:
    .text "You sense the presence of evil!" ; .byte 0
pmx_msg_no_evil:
    .text "You sense no evil nearby." ; .byte 0
pmx_msg_no_creatures:
    .text "You sense no creatures nearby." ; .byte 0

#if !PMX_DETECT_EFFECTS_EXTERNAL
eff_detect_evil_only:
    lda #0
    sta muv_clear_detected
    sta eff_detect_timer
    sta vis_room_revealed
    ldx #0
!edeo_loop:
    cpx #MAX_MONSTERS
    bcs !edeo_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !edeo_next+
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #~MF_DETECTED & $ff
    sta (zp_ptr0),y
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tay
    lda cr_mflags,y
    and #$04
    beq !edeo_next+

    ldy #MX_Y
    lda (zp_ptr0),y
    sta zp_temp1
    sec
    sbc zp_view_y
    bcc !edeo_next+
    cmp #VIEWPORT_H
    bcs !edeo_next+

    ldy #MX_X
    lda (zp_ptr0),y
    sta zp_temp0
    sec
    sbc zp_view_x
    bcc !edeo_next+
    cmp #VIEWPORT_W
    bcs !edeo_next+

    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_DETECTED
    sta (zp_ptr0),y
    lda #1
    sta eff_detect_evil_mode
    lda #DETECT_TIMER_EVIL_ONLY
    sta eff_detect_timer
    lda #1
    sta vis_room_revealed
!edeo_next:
    inx
    jmp !edeo_loop-
!edeo_done:
    lda vis_room_revealed
    rts
#endif
