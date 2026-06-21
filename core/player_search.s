#importonce
// player_search.s — Search chance helpers shared by movement, searching, and
// disarm code.

// player_search_has_light — Returns carry set when the player has no local light
// source and is not standing on a lit tile.
player_search_has_no_light:
    lda zp_light_radius
    bne !has_light+

    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    :MapRead_ptr0_y()
    and #PLAYER_SEARCH_FLAG_LIT
    beq !no_light+
!has_light:
    clc
    rts
!no_light:
    sec
    rts

// player_search_get_base_chance — Race/class-derived active search chance
// Output: A = base search chance
player_search_get_base_chance:
    // Class search is unsigned at offset 8.
    lda player_data + PL_CLASS
    ldx #CLASS_PROP_SIZE
    jsr math_multiply
    clc
    adc #8
    tax
    lda class_properties,x
    sta zp_temp0

    // Race search adjustment is signed at offset 4; the shipped tables keep
    // the combined total in the positive range, so 8-bit add is sufficient.
    lda player_data + PL_RACE
    ldx #RACE_PROP_SIZE
    jsr math_multiply
    clc
    adc #4
    tax
    lda race_properties,x
    clc
    adc zp_temp0
    rts

// player_search_get_fos — Race/class-derived passive auto-search frequency
// Output: A = fos (<=1 means always search on movement)
player_search_get_fos:
    // Class fos is unsigned at offset 9.
    lda player_data + PL_CLASS
    ldx #CLASS_PROP_SIZE
    jsr math_multiply
    clc
    adc #9
    tax
    lda class_properties,x
    sta zp_temp0

    lda player_data + PL_RACE
    ldx #RACE_PROP_SIZE
    jsr math_multiply
    clc
    adc #6
    tax
    lda race_properties,x
    clc
    adc zp_temp0
    rts

// player_search_get_effective_chance — Apply live status/light penalties
// Output: A = effective chance used by active and passive search scans
player_search_get_effective_chance:
    jsr player_search_get_base_chance
    sta player_search_work

    lda zp_eff_confuse
    beq !not_confused+
    lda player_search_work
    jsr player_search_divide_by_10
    sta player_search_work
!not_confused:

    lda zp_eff_blind
    bne !dim_penalty+
    jsr player_search_has_no_light
    bcc !done+
!dim_penalty:
    lda player_search_work
    jsr player_search_divide_by_10
    sta player_search_work
!done:
    lda player_search_work
    rts

// player_search_divide_by_10 — Floor(A / 10)
// Output: A = quotient
player_search_divide_by_10:
    sta zp_math_a
    lda #0
    sta zp_math_b
    ldx #10
    jsr math_div_16x8
    lda zp_math_a
    rts

player_search_work: .byte 0
