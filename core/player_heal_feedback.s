#importonce
// player_heal_feedback.s — shared generic player-heal reporting
//
// Owns the upstream-style 4-tier player-heal message ladder while keeping the
// low-level HP mutation primitive (`eff_heal`) silent for non-message callers.

pmx_feedback_heal_amt:   .byte 0

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
    jmp pmx_heal_report_message

pmx_heal_report_message:
    cmp #5
    bcs !phrm_better+
    ldx #HSTR_PIQ_LITTLE_BETTER
    jmp huff_print_msg

!phrm_better:
    cmp #15
    bcc !phrm_feel_better+
    cmp #35
    bcc !phrm_much_better+
    ldx #HSTR_PIQ_VERY_GOOD
    jmp huff_print_msg

!phrm_feel_better:
    ldx #HSTR_EFF_POISON_END
    jmp huff_print_msg

!phrm_much_better:
    ldx #HSTR_PIQ_MUCH_BETTER
    jmp huff_print_msg
