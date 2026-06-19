#importonce
// player_magic_display.s — failure calculation shared by cast/pray logic

// ============================================================
// calc_spell_failure — Calculate adjusted failure rate and roll
// ============================================================
calc_spell_failure:
    lda pm_fail_tbl_lo
    sta zp_ptr0
    lda pm_fail_tbl_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y
    sta pm_fail_work

    lda pm_lvl_tbl_lo
    sta zp_ptr0
    lda pm_lvl_tbl_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y
    sta zp_temp0

    lda zp_player_lvl
    sec
    sbc zp_temp0
    bcs !csf_lvl_ok+
    lda #0
!csf_lvl_ok:
    sta zp_temp0
    asl
    bcs !csf_clamp_min+
    clc
    adc zp_temp0
    bcs !csf_clamp_min+
    sta zp_temp0
    lda pm_fail_work
    sec
    sbc zp_temp0
    bcc !csf_clamp_min+
    sta pm_fail_work

    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !csf_wis+
    lda player_data + PL_INT_CUR
    jmp !csf_stat+
!csf_wis:
    lda player_data + PL_WIS_CUR
!csf_stat:
    jsr stat_bonus_index
    lda spell_stat_bonus,x
    sta zp_temp0
    lda pm_fail_work
    sec
    sbc zp_temp0
    bcc !csf_clamp_min+
    sta pm_fail_work
    jmp !csf_cap_high+

!csf_clamp_min:
    lda #5
    sta pm_fail_work

!csf_cap_high:
    lda pm_fail_work
    cmp #96
    bcc !csf_hunger+
    lda #95
    sta pm_fail_work

    // Preserve the existing faint-hunger failure penalty.
!csf_hunger:
    lda zp_hunger_state
    cmp #HUNGER_FAINT
    bcc !csf_roll+
    lda pm_fail_work
    clc
    adc #20
    cmp #96
    bcc !csf_hunger_store+
    lda #95
!csf_hunger_store:
    sta pm_fail_work

    // Overcasting follows the upstream model: missing mana raises fail rate
    // sharply, but does not block the cast outright.
!csf_overcast:
    lda pm_cost_tmp
    sec
    sbc zp_player_mp
    bcc !csf_roll+
    beq !csf_roll+
    sta zp_temp0
    asl
    bcs !csf_overcap+
    asl
    bcs !csf_overcap+
    clc
    adc zp_temp0
    bcs !csf_overcap+
    clc
    adc pm_fail_work
    bcc !csf_over_store+
!csf_overcap:
    lda #95
!csf_over_store:
    cmp #96
    bcc !csf_over_ok+
    lda #95
!csf_over_ok:
    sta pm_fail_work

!csf_roll:
    lda #100
    jsr rng_range
    cmp pm_fail_work
    bcc !csf_fail+
    clc
    rts
!csf_fail:
    sec
    rts

calc_spell_failure_end:
