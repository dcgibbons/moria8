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
pmx_feedback_mon_slot:   .byte 0

// pmx_add_speed_msg — Haste for A more turns (A = 1-127). zp_eff_speed is
// one signed timer (> 0 haste, < 0 slow): a signed add, so haste while slowed
// cancels slow turn for turn, and stacking haste stops at +127 instead of
// wrapping into slow.
pmx_add_speed_msg:
    clc
    adc zp_eff_speed
    bvc !pasm_store+
    lda #$7f
!pasm_store:
    sta zp_eff_speed
    ldx #HSTR_PIQ_SPEED
    jmp huff_print_msg

pmx_add_bless_msg:
    ldy #zp_eff_bless
    jsr pmx_add_zp_was_zero
    bne !pabm_done+
    lda #<pmx_righteous_msg
    ldy #>pmx_righteous_msg
    jmp pmx_print_inline
!pabm_done:
    rts

pmx_add_protect_msg:
    ldy #zp_eff_protect
    jsr pmx_add_zp_was_zero
    bne !pabm_done-
    ldx #HSTR_PIQ_PROTECTED
    jmp huff_print_msg

pmx_add_zp_was_zero:
    ldx $0000,y
    jsr pmx_add_zp_sat
    txa
    rts
.assert "Bless/protect timers are zero-page", zp_eff_bless < $100 && zp_eff_protect < $100, true

// pmx_add_resist_heat_cold_msg — Resist Heat and Cold: VMS
// resist_heat += randint(10) + 10; resist_cold += randint(10) + 10, a roll
// each (11-20 turns; until 2026-11-08 one 10-19 roll, copied to both).
pmx_add_resist_heat_cold_msg:
    ldy #zp_eff_resist
    jsr pmx_resist_add
    ldy #eff_resist_cold_timer
    jsr pmx_resist_add
    lda #<pmx_resist_on_msg
    ldy #>pmx_resist_on_msg
    jmp pmx_print_inline

// pmx_resist_add — The zero-page timer at Y += randint(10) + 10, saturating
// at 255. Preserves: Y (rng_range preserves Y)
pmx_resist_add:
    lda #10
    jsr rng_range               // 0-9
    sec                         // + 1: randint(10)
    adc #10
pmx_add_zp_sat:
    clc
    adc $0000,y
    bcc !pra_store+
    lda #255
!pra_store:
    sta $0000,y
    rts
.assert "Resist timers are zero-page (pmx_resist_add)", zp_eff_resist < $100 && eff_resist_cold_timer < $100, true

pmx_slow_poison_msg:
    lda zp_eff_poison
    beq !pspm_done+
    lsr
    ora #1
    sta zp_eff_poison
    ldx #HSTR_EFF_POISON_END
    jmp huff_print_msg
!pspm_done:
    rts

pmx_sleep_adjacent_msg:
    lda #0
    sta pmx_feedback_sleep_hits
    sta pmx_feedback_sleep_seen
    ldx #7
    stx pmx_feedback_dir_idx
!psam_loop:
    ldx pmx_feedback_dir_idx
    lda zp_player_y
    clc
    adc dir_dy,x
    tay
    lda zp_player_x
    clc
    adc dir_dx,x
    jsr monster_find_at
    bcc !psam_next+
    inc pmx_feedback_sleep_seen
    jsr pmx_try_sleep_monster
    bcc !psam_next+
    inc pmx_feedback_sleep_hits
!psam_next:
    dec pmx_feedback_dir_idx
    bpl !psam_loop-
    lda pmx_feedback_sleep_hits
    bne !psam_any+
    lda pmx_feedback_sleep_seen
    beq pmx_print_nothing
    lda #<pmx_sleep_unaffected_msg
    ldy #>pmx_sleep_unaffected_msg
    jmp pmx_print_inline
!psam_any:
    lda #<pmx_sleep_success_msg
    ldy #>pmx_sleep_success_msg
    jmp pmx_print_inline

pmx_try_sleep_monster:
    stx pmx_feedback_mon_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
#if (PLACE_SECRETS_EXTERNAL || PLACE_SECRETS_EMITTED) && !C64_TEST_FULL_ITEMDESC_STUB
    lda cr_cdefense,x
    and #CD_NO_SLEEP
    bne !ptsm_resist+
#endif
    lda #40
    jsr rng_range
    clc
    adc #1                     // VMS randint(40) is 1..40; rng_range is 0..39.
    cmp cr_level,x
    bcc !ptsm_resist+
    ldx pmx_feedback_mon_slot
    lda #$ff
    jsr monster_apply_sleep
    sec
    rts
!ptsm_resist:
    clc
    rts

pmx_report_sleep_result:
    cmp #0
    bne !psam_any-
pmx_print_nothing:
    ldx #HSTR_PIQ_NOTHING
    jmp huff_print_msg

pmx_confuse_monster_dir_msg:
    jsr eff_directional_monster
    bcc pmx_print_nothing
#if (PLACE_SECRETS_EXTERNAL || PLACE_SECRETS_EMITTED) && !C64_TEST_FULL_ITEMDESC_STUB
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda cr_cdefense,x
    and #CD_NO_SLEEP
    bne pmx_print_nothing
#endif
    ldy #MX_CONFUSE
    lda #10
    sta (zp_ptr0),y
    ldx #HSTR_PIW_WAND_CLOUD
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
    jmp huff_print_msg
!pssim_done:
    rts

pmx_print_inline:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp msg_print

pmx_righteous_msg:
    .text "You feel righteous!"
    .byte 0

pmx_sleep_success_msg:
    .text "A monster falls asleep."
    .byte 0

pmx_sleep_unaffected_msg:
    .text "A monster is unaffected."
    .byte 0

pmx_resist_on_msg:
    .text "You feel resistant to heat and cold."
    .byte 0