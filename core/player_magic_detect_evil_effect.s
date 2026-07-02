#importonce

eff_detect_evil_only:
    lda #0
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
    sec
    sbc zp_view_x
    bcc !edeo_next+
    cmp #VIEWPORT_W
    bcs !edeo_next+

    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_DETECTED
    sta (zp_ptr0),y
    // VMS-Moria/Umoria Detect Evil is an immediate current-panel reveal.
    // The mode byte is only a pending post-redraw clear latch.
    lda #1
    sta eff_detect_evil_mode
    sta vis_room_revealed
!edeo_next:
    inx
    jmp !edeo_loop-
!edeo_done:
    lda vis_room_revealed
    rts

detect_evil_clear_reveal:
    lda eff_detect_evil_mode
    beq !decr_done+
    dec eff_detect_evil_mode
    sta muv_clear_detected
    sta vis_room_revealed
#if C128
    sta vis_force_redraw_pending
#endif
    jsr monster_update_visibility_all
!decr_done:
    rts
