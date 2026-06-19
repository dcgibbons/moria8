#importonce
// disarm_helpers.s — Umoria-style direct trap disarm math.

// disarm_calc_success_threshold — Convert Umoria's floor-trap success test to
// the local rng_range(100) convention.
//
// Umoria tests: total + 100 - trap_level > randomNumber(100), where
// randomNumber(100) returns 1..100. rng_range(100) returns 0..99, so the
// equivalent threshold is total + 99 - trap_level, clamped to 0..100.
//
// Input:  A = signed disarm total, X = trap type index
// Output: A = threshold for rng_range(100); 100 means guaranteed success.
disarm_calc_success_threshold:
    sta zp_math_a
    lda #0
    sta zp_math_b
    lda zp_math_a
    bpl !hi_done+
    lda #$ff
    sta zp_math_b
!hi_done:
    clc
    lda zp_math_a
    adc #99
    sta zp_math_a
    lda zp_math_b
    adc #0
    sta zp_math_b

    sec
    lda zp_math_a
    sbc trap_difficulty,x
    sta zp_math_a
    lda zp_math_b
    sbc #0
    sta zp_math_b

    lda zp_math_b
    bmi !zero+
    bne !cap+
    lda zp_math_a
    cmp #100
    bcc !done+
!cap:
    lda #100
    rts
!zero:
    lda #0
!done:
    rts

// disarm_roll_bad_fail — Umoria bad-fail test for floor traps.
//
// Umoria tests: if total > 5 && randomNumber(total) > 5, ordinary failure;
// otherwise the trap is set off. With rng_range(total), randomNumber(total)>5
// is equivalent to rng_range(total)>=5.
//
// Input:  A = signed disarm total
// Output: carry set = bad fail / trap fires, carry clear = ordinary fail
disarm_roll_bad_fail:
    bmi !bad+
    cmp #6
    bcc !bad+
    jsr rng_range
    cmp #5
    bcc !bad+
    clc
    rts
!bad:
    sec
    rts

player_disarm_get_effective_chance:
    jsr player_disarm_dex_adj
    sta df_disarm_total

    lda player_data + PL_CLASS
    ldx #CLASS_PROP_SIZE
    jsr math_multiply
    clc
    adc #5
    tax
    lda class_properties,x
    sta df_disarm_chance

    lda player_data + PL_RACE
    ldx #RACE_PROP_SIZE
    jsr math_multiply
    clc
    adc #3
    tax
    lda race_properties,x
    clc
    adc df_disarm_chance
    sta df_disarm_chance

    lda df_disarm_total
    clc
    adc df_disarm_chance
    clc
    adc #2
    sta df_disarm_base

    lda df_disarm_total
    beq !mul_zero+
    bmi !mul_neg+
    tax
    lda #0
!mul_pos_loop:
    clc
    adc df_disarm_base
    bvs !mul_pos_sat+
    bmi !mul_pos_sat+
    dex
    bne !mul_pos_loop-
    beq !mul_store+
!mul_pos_sat:
    lda #127
    bne !mul_store+
!mul_zero:
    lda #0
    beq !mul_store+
!mul_neg:
    eor #$ff
    clc
    adc #1
    tax
    lda #0
!mul_neg_loop:
    sec
    sbc df_disarm_base
    bvs !mul_neg_sat+
    dex
    bne !mul_neg_loop-
    beq !mul_store+
!mul_neg_sat:
    lda #$80
!mul_store:
    sta df_disarm_chance

!add_int:
    jsr player_disarm_int_adj
    jsr disarm_add_signed_to_total

    lda player_data + PL_CLASS
    ldx #CLASS_LVL_SIZE
    jsr math_multiply
    clc
    adc #3
    tax
    lda class_level_adj,x
    ldx zp_player_lvl
    jsr math_multiply
    ldx #3
    jsr math_div_16x8
    lda zp_math_a
    jsr disarm_add_signed_to_total

    lda zp_eff_confuse
    beq !not_confused+
    jsr disarm_divide_total_by_10
!not_confused:
    lda zp_eff_blind
    bne !dim+
    jsr player_search_has_no_light
    bcc !done+
!dim:
    jsr disarm_divide_total_by_10
!done:
    lda df_disarm_chance
    rts

disarm_add_signed_to_total:
    clc
    adc df_disarm_chance
    bvc !store+
    bmi !pos_overflow+
    lda #$80
    bne !store+
!pos_overflow:
    lda #127
!store:
    sta df_disarm_chance
    rts

disarm_divide_total_by_10:
    lda df_disarm_chance
    bpl !positive+
    eor #$ff
    clc
    adc #1
    jsr player_search_divide_by_10
    eor #$ff
    clc
    adc #1
    sta df_disarm_chance
    rts
!positive:
    jsr player_search_divide_by_10
    sta df_disarm_chance
    rts

player_disarm_dex_adj:
    lda player_data + PL_DEX_CUR
    cmp #18
    bcs !dex18plus+
    tax
    dex
    dex
    dex
    lda dex_disarm_bonus,x
    rts
!dex18plus:
    cmp #59
    bcc !dex4+
    cmp #94
    bcc !dex5+
    cmp #117
    bcc !dex6+
    lda #8
    rts
!dex6:
    lda #6
    rts
!dex5:
    lda #5
    rts
!dex4:
    lda #4
    rts

player_disarm_int_adj:
    lda player_data + PL_INT_CUR
    cmp #8
    bcs !ge8+
    cmp #6
    bcs !zero+
    sec
    sbc #6
    rts
!zero:
    lda #0
    rts
!ge8:
    cmp #15
    bcs !ge15+
    lda #1
    rts
!ge15:
    cmp #18
    bcs !ge18+
    lda #2
    rts
!ge18:
    cmp #19
    bcs !int18xx+
    lda #3
    rts
!int18xx:
    cmp #69
    bcc !int4+
    lda #5
    rts
!int4:
    lda #4
    rts
