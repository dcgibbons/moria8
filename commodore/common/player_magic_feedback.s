#importonce
// player_magic_feedback.s — shared spell/prayer feedback helpers
//
// Kept separate from the main execute overlay so small unit suites can
// exercise timed-buff and adjacent-effect feedback without importing the
// entire spell dispatch surface.

#import "player_heal_feedback.s"

pmx_feedback_sleep_hits: .byte 0
pmx_feedback_sleep_seen: .byte 0
pmx_feedback_dir_idx:    .byte 0
pmx_feedback_x:          .byte 0
pmx_feedback_y:          .byte 0
pmx_feedback_mon_slot:   .byte 0

pmx_add_speed_msg:
    tax
    txa
    clc
    adc zp_eff_speed
    bcc !pasm_store+
    lda #$7f
!pasm_store:
    sta zp_eff_speed
    ldx #HSTR_PIQ_SPEED
    jsr huff_print_msg
    rts

pmx_add_bless_msg:
    tax
    lda zp_eff_bless
    pha
    txa
    clc
    adc zp_eff_bless
    bcc !pabm_store+
    lda #255
!pabm_store:
    sta zp_eff_bless
    pla
    bne !pabm_done+
    lda #<pmx_righteous_msg
    ldy #>pmx_righteous_msg
    jsr pmx_print_inline
!pabm_done:
    rts

pmx_add_protect_msg:
    tax
    lda zp_eff_protect
    pha
    txa
    clc
    adc zp_eff_protect
    bcc !papm_store+
    lda #255
!papm_store:
    sta zp_eff_protect
    pla
    bne !papm_done+
    ldx #HSTR_PIQ_PROTECTED
    jsr huff_print_msg
!papm_done:
    rts

pmx_set_resist_heat_cold_msg:
    lda zp_eff_resist
    pha
    lda #$03
    sta zp_eff_resist
    pla
    bne !psrhc_done+
    lda #<pmx_resist_on_msg
    ldy #>pmx_resist_on_msg
    jsr pmx_print_inline
!psrhc_done:
    rts

pmx_sleep_adjacent_msg:
    lda #0
    sta pmx_feedback_sleep_hits
    sta pmx_feedback_sleep_seen
    sta pmx_feedback_dir_idx
!psam_loop:
    ldx pmx_feedback_dir_idx
    cpx #8
    bcs !psam_done_scan+
    lda zp_player_x
    clc
    adc dir_dx,x
    sta pmx_feedback_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta pmx_feedback_y
    lda pmx_feedback_x
    ldy pmx_feedback_y
    jsr monster_find_at
    bcc !psam_next+
    inc pmx_feedback_sleep_seen
    stx pmx_feedback_mon_slot
    jsr pmx_try_sleep_monster
    bcc !psam_next+
    inc pmx_feedback_sleep_hits
!psam_next:
    inc pmx_feedback_dir_idx
    jmp !psam_loop-
!psam_done_scan:
    lda pmx_feedback_sleep_hits
    bne !psam_any+
    lda pmx_feedback_sleep_seen
    bne !psam_unaffected+
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
!psam_done:
    rts
!psam_any:
    lda #<pmx_sleep_success_msg
    ldy #>pmx_sleep_success_msg
    jsr pmx_print_inline
    rts
!psam_unaffected:
    lda #<pmx_sleep_unaffected_msg
    ldy #>pmx_sleep_unaffected_msg
    jmp pmx_print_inline

pmx_try_sleep_monster:
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda #40
    jsr rng_range
    cmp cr_level,x
    bcc !ptsm_resist+
    ldx pmx_feedback_mon_slot
    lda #20
    jsr monster_apply_sleep
    sec
    rts
!ptsm_resist:
    clc
    rts

pmx_report_sleep_result:
    cmp #0
    bne !prvs_any+
    ldx #HSTR_PIQ_NOTHING
    jmp huff_print_msg
!prvs_any:
    lda #<pmx_sleep_success_msg
    ldy #>pmx_sleep_success_msg
    jmp pmx_print_inline

pmx_confuse_monster_dir_msg:
    jsr eff_directional_monster
    bcc !pcmd_miss+
    jsr monster_get_ptr
    ldy #MX_CONFUSE
    lda #10
    sta (zp_ptr0),y
    ldx #HSTR_PIW_WAND_CLOUD
    jmp huff_print_msg
!pcmd_miss:
    ldx #HSTR_PIQ_NOTHING
    jmp huff_print_msg

pmx_set_see_invisible_msg:
    lda zp_eff_see_inv
    ora zp_eff_invis
    pha
    lda #1
    sta zp_eff_see_inv
    sta zp_eff_invis
    pla
    bne !pssim_done+
    ldx #HSTR_PIQ_EYES_TINGLE
    jsr huff_print_msg
!pssim_done:
    rts

pmx_print_inline:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp msg_print

pmx_righteous_msg:
    .text "You feel righteous!"
    .byte 0

pmx_resist_on_msg:
    .text "You feel resistant to heat and cold."
    .byte 0

pmx_sleep_success_msg:
    .text "A monster falls asleep."
    .byte 0

pmx_sleep_unaffected_msg:
    .text "A monster is unaffected."
    .byte 0
