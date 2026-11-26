#importonce
// eff_detect_evil_cold.s — Cold Detect Evil panel-scan effect body
//
// Module ownership:
//   owner: Default resident / play-slot when !EFF_DETECT_EVIL_EXTERNAL, or port
//     spell/utility overlay when EFF_DETECT_EVIL_EXTERNAL is defined (while
//     detect_evil_clear_reveal stays resident in player_magic_detect_evil_effect.s).
//   lifetime: one Detect Evil cast/staff/scroll invocation.
//   callers: player_magic_execute_overlay.s / item effects (directly if co-located
//     or via port trampoline).

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
