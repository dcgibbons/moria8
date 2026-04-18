#importonce
// player_magic_feedback.s — shared spell/prayer feedback helpers
//
// Kept separate from the main execute overlay so small unit suites can
// exercise timed-buff and adjacent-effect feedback without importing the
// entire spell dispatch surface.

pmx_feedback_sleep_hits: .byte 0
pmx_feedback_dir_idx:    .byte 0
pmx_feedback_x:          .byte 0
pmx_feedback_y:          .byte 0
pmx_feedback_heal_amt:   .byte 0

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
    lda #<pmx_msg_bless_on
    ldy #>pmx_msg_bless_on
    jsr pmx_print_inline
!pabm_done:
    rts

pmx_heal_and_report:
    sta pmx_feedback_heal_amt

    lda zp_player_hp_hi
    cmp zp_player_mhp_hi
    bcc !phar_apply+
    bne !phar_done+
    lda zp_player_hp_lo
    cmp zp_player_mhp_lo
    bcc !phar_apply+
!phar_done:
    rts

!phar_apply:
    lda pmx_feedback_heal_amt
    jsr eff_heal
    lda pmx_feedback_heal_amt
    cmp #15
    bcc !phar_small+
    ldx #HSTR_PIQ_MUCH_BETTER
    jsr huff_print_msg
    rts
!phar_small:
    ldx #HSTR_PIQ_FEEL_BETTER
    jmp huff_print_msg

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
    lda #<pmx_msg_resist_on
    ldy #>pmx_msg_resist_on
    jsr pmx_print_inline
!psrhc_done:
    rts

pmx_sleep_adjacent_msg:
    lda #0
    sta pmx_feedback_sleep_hits
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
    lda #20
    jsr monster_apply_sleep
    inc pmx_feedback_sleep_hits
!psam_next:
    inc pmx_feedback_dir_idx
    jmp !psam_loop-
!psam_done_scan:
    lda pmx_feedback_sleep_hits
    bne !psam_any+
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
!psam_done:
    rts
!psam_any:
    lda #<pmx_msg_sleep_success
    ldy #>pmx_msg_sleep_success
    jsr pmx_print_inline
    rts

pmx_report_sleep_result:
    cmp #0
    bne !prvs_any+
    ldx #HSTR_PIQ_NOTHING
    jmp huff_print_msg
!prvs_any:
    lda #<pmx_msg_sleep_success
    ldy #>pmx_msg_sleep_success
    jmp pmx_print_inline

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

pmx_msg_bless_on:
    .text "You feel righteous!" ; .byte 0
pmx_msg_resist_on:
    .text "You feel resistant to heat and cold." ; .byte 0
pmx_msg_sleep_success:
    .text "A monster falls asleep." ; .byte 0
