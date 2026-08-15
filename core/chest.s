#importonce
// chest.s — Classic Moria chest interactions (open/disarm/bash).
//
// Overlay-resident (docs/CHEST_DESIGN.md): chest code is cold, so it lives in
// the chest-only OVL_CHEST window segment. Resident code routes here through
// the platform chest handoffs once chest_find_at_df_target identifies a chest
// at the command target.
//
// Entry contract (all three handlers):
//   Input:  df_target_x/df_target_y hold the resolved command target tile.
//   Output: carry set = turn consumed, carry clear = no turn (mirrors
//           door_try_open / bash_command / disarm_command).
//
// The disarm-skill helpers are mirrored from disarm_helpers.s: that file is
// overlay-resident (ITEMS/DISARM), so the chest overlay cannot call it, and
// C64/Plus4 resident space cannot host it either. Keep the formulas in sync.

// ============================================================
// Scratch
// ============================================================
chest_slot:       .byte 0   // Floor slot of the chest being handled
chest_skill:      .byte 0   // Effective disarm skill / lock threshold
chest_difficulty: .byte 0
chest_p1:         .byte 0   // Chest flag snapshot for trap firing

// ============================================================
// chest_open_command — Open a chest (docs/CHEST_DESIGN.md).
// Locked chests require a lock pick (skill - 2*source_level); success clears
// the lock and grants source_level XP. Once unlocked, armed traps fire in
// VMS order, then the chest is marked opened unless an explosion destroyed
// it. Contents generation lands in step 13.
// ============================================================
chest_open_command:
    jsr chest_find_at_df_target
    bcc !co_no_turn+
    stx chest_slot
    lda fi_p1,x
    and #CHEST_P1_OPENED
    bne !co_reopen+
    lda fi_p1,x
    and #CHEST_P1_LOCKED
    beq !co_unlocked+

    // Locked: confused players cannot pick
    lda zp_eff_confuse
    beq !co_not_confused+
    ldx #HSTR_CHEST_PICK_CONFUSED
    jsr huff_print_msg
    sec
    rts

!co_not_confused:
    // Lock pick: threshold from skill - 2*source_level (VMS)
    jsr chest_disarm_skill
    sta chest_skill
    ldx chest_slot
    lda fi_to_hit,x
    asl                         // difficulty = 2 * source_level
    tax                         // X = difficulty
    lda chest_skill             // A = effective skill
    jsr chest_threshold_value   // A = success threshold (0-100)
    sta chest_skill
    lda #100
    jsr rng_range
    cmp chest_skill
    bcs !co_pick_fail+

    // Picked: clear the lock, award source_level XP (VMS)
    ldx chest_slot
    lda fi_p1,x
    and #~CHEST_P1_LOCKED & $ff
    sta fi_p1,x
    lda fi_to_hit,x
    jsr chest_award_xp
    ldx #HSTR_CHEST_PICKED
    jsr huff_print_msg
    jmp !co_unlocked+

!co_pick_fail:
    ldx #HSTR_CHEST_PICK_FAIL
    jsr huff_print_msg
    sec
    rts

!co_unlocked:
    ldx chest_slot
    lda fi_p1,x
    and #CHEST_P1_TRAP_MASK
    beq !co_opened+
    jsr chest_trigger_traps
    bcs !co_done+             // Chest destroyed by its own explosion
!co_opened:
    ldx chest_slot
    lda fi_p1,x
    ora #CHEST_P1_OPENED
    sta fi_p1,x
    // Contents generation lands in step 13 (loot handoff).
!co_done:
    sec
    rts

!co_reopen:
    // Re-opening an already-opened chest consumes a turn (upstream).
    sec
    rts

!co_no_turn:
    clc
    rts

// ============================================================
// chest_trigger_traps — Fire all armed chest traps in VMS order
// (docs/CHEST_DESIGN.md): lose STR, poison, paralysis, explosion, summoning.
// Triggering identifies the trap (sets found). Explosion removes the chest
// and suppresses contents; deferred summons still stage after a (possibly
// lethal) explosion.
// Input: X = floor slot. Output: carry set = chest destroyed, clear = intact.
// ============================================================
chest_trigger_traps:
    stx chest_slot
    lda fi_p1,x
    sta chest_p1
    ora #CHEST_P1_TRAP_FOUND
    sta fi_p1,x

    // 1. Lose STR: needle, stat decrement, 1d4
    lda chest_p1
    and #CHEST_P1_TRAP_STR
    beq !ctt_no_str+
    ldx #HSTR_CHEST_NEEDLE
    jsr huff_print_msg
    lda player_data + PL_STR_CUR
    cmp #4
    bcc !ctt_str_immune+
    jsr decrement_stat
    sta player_data + PL_STR_CUR
    sta zp_player_str
    ldx #HSTR_CHEST_WEAKENED
    jsr huff_print_msg
!ctt_str_immune:
    lda #DEATH_CHEST_NEEDLE
    sta df_death_source
    lda #HSTR_CHEST_DEATH_NEEDLE
    sta df_death_hstr
    lda #1
    ldx #4
    ldy #0
    jsr trap_apply_damage
!ctt_no_str:

    // 2. Poison: needle, 1d6, poison timer += 10 + rng(20) (saturating)
    lda chest_p1
    and #CHEST_P1_TRAP_POISON
    beq !ctt_no_poison+
    ldx #HSTR_CHEST_NEEDLE
    jsr huff_print_msg
    lda #DEATH_CHEST_NEEDLE
    sta df_death_source
    lda #HSTR_CHEST_DEATH_NEEDLE
    sta df_death_hstr
    lda #1
    ldx #6
    ldy #0
    jsr trap_apply_damage
    lda #20
    jsr rng_range
    clc
    adc #10
    clc
    adc zp_eff_poison
    bcc !ctt_poison_ok+
    lda #$ff
!ctt_poison_ok:
    sta zp_eff_poison
!ctt_no_poison:

    // 3. Paralysis: yellow gas; free action suppresses
    lda chest_p1
    and #CHEST_P1_TRAP_PARA
    beq !ctt_no_para+
    ldx #HSTR_CHEST_GAS
    jsr huff_print_msg
    lda player_data + PL_FLAGS
    and #PLF_FREE_ACT
    beq !ctt_para_apply+
    ldx #HSTR_CHEST_UNAFFECTED
    jsr huff_print_msg
    jmp !ctt_no_para+
!ctt_para_apply:
    ldx #HSTR_CHEST_CHOKE
    jsr huff_print_msg
    lda #20
    jsr rng_range
    clc
    adc #10
    sta zp_eff_paralyze
!ctt_no_para:

    // 4. Explosion: chest removed from the floor, then 5d8
    lda chest_p1
    and #CHEST_P1_TRAP_EXPL
    beq !ctt_no_expl+
    ldx #HSTR_CHEST_EXPLOSION
    jsr huff_print_msg
    ldx chest_slot
    jsr floor_item_remove
    lda #DEATH_CHEST_EXPLOSION
    sta df_death_source
    lda #HSTR_CHEST_DEATH_EXPLODING
    sta df_death_hstr
    lda #5
    ldx #8
    ldy #0
    jsr trap_apply_damage
!ctt_no_expl:

    // 5. Summoning: deferred to the resident handoff (three attempts);
    // stages even after a lethal explosion (VMS order).
    lda chest_p1
    and #CHEST_P1_TRAP_SUMMON
    beq !ctt_no_summon+
    lda #3
    sta chest_pending_summons
!ctt_no_summon:

    // Clear armed trap bits if the chest still exists (lock preserved).
    ldx chest_slot
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !ctt_destroyed+
    lda fi_p1,x
    and #~CHEST_P1_TRAP_MASK & $ff
    sta fi_p1,x
    clc
    rts
!ctt_destroyed:
    sec
    rts

// ============================================================
// chest_award_xp — Add A (0-255) to player XP (24-bit accumulate).
// ============================================================
chest_award_xp:
    clc
    adc player_data + PL_XP_0
    sta player_data + PL_XP_0
    bcc !cax_done+
    inc player_data + PL_XP_1
    bne !cax_done+
    inc player_data + PL_XP_2
!cax_done:
    rts

// ============================================================
// chest_threshold_value — Value-based disarm success threshold.
// Mirror of disarm_calc_success_threshold (disarm_helpers.s) taking the
// difficulty as a value instead of a trap_difficulty table index.
// Input:  A = signed disarm total, X = difficulty (e.g., 2*source_level)
// Output: A = threshold for rng_range(100); 100 means guaranteed success.
// ============================================================
chest_threshold_value:
    stx chest_difficulty
    sta zp_math_a
    lda #0
    sta zp_math_b
    lda zp_math_a
    bpl !ctv_hi+
    lda #$ff
    sta zp_math_b
!ctv_hi:
    clc
    lda zp_math_a
    adc #99
    sta zp_math_a
    lda zp_math_b
    adc #0
    sta zp_math_b
    sec
    lda zp_math_a
    sbc chest_difficulty
    sta zp_math_a
    lda zp_math_b
    sbc #0
    sta zp_math_b
    lda zp_math_b
    bmi !ctv_zero+
    bne !ctv_cap+
    lda zp_math_a
    cmp #100
    bcc !ctv_done+
!ctv_cap:
    lda #100
    rts
!ctv_zero:
    lda #0
!ctv_done:
    rts

// ============================================================
// chest_disarm_skill — Mirror of player_disarm_get_effective_chance
// (disarm_helpers.s) so the chest overlay can compute the existing effective
// disarm skill without a cross-overlay call.
// Output: A = signed effective disarm total
// ============================================================
chest_disarm_skill:
    jsr chest_disarm_dex_adj
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
    beq !cds_mul_zero+
    bmi !cds_mul_neg+
    tax
    lda #0
!cds_mul_pos_loop:
    clc
    adc df_disarm_base
    bvs !cds_mul_pos_sat+
    bmi !cds_mul_pos_sat+
    dex
    bne !cds_mul_pos_loop-
    beq !cds_mul_store+
!cds_mul_pos_sat:
    lda #127
    bne !cds_mul_store+
!cds_mul_zero:
    lda #0
    beq !cds_mul_store+
!cds_mul_neg:
    eor #$ff
    clc
    adc #1
    tax
    lda #0
!cds_mul_neg_loop:
    sec
    sbc df_disarm_base
    bvs !cds_mul_neg_sat+
    dex
    bne !cds_mul_neg_loop-
    beq !cds_mul_store+
!cds_mul_neg_sat:
    lda #$80
!cds_mul_store:
    sta df_disarm_chance

    jsr chest_disarm_int_adj
    jsr chest_disarm_add_signed

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
    jsr chest_disarm_add_signed

    lda zp_eff_confuse
    beq !cds_not_confused+
    jsr chest_disarm_divide_by_10
!cds_not_confused:
    lda zp_eff_blind
    bne !cds_dim+
    jsr player_search_has_no_light
    bcc !cds_done+
!cds_dim:
    jsr chest_disarm_divide_by_10
!cds_done:
    lda df_disarm_chance
    rts

chest_disarm_add_signed:
    clc
    adc df_disarm_chance
    bvc !cds_as_store+
    bmi !cds_as_neg_ov+
    lda #$80
    bne !cds_as_store+
!cds_as_neg_ov:
    lda #127
!cds_as_store:
    sta df_disarm_chance
    rts

chest_disarm_divide_by_10:
    lda df_disarm_chance
    bpl !cds_d10_pos+
    eor #$ff
    clc
    adc #1
    jsr player_search_divide_by_10
    eor #$ff
    clc
    adc #1
    sta df_disarm_chance
    rts
!cds_d10_pos:
    jsr player_search_divide_by_10
    sta df_disarm_chance
    rts

chest_disarm_dex_adj:
    lda player_data + PL_DEX_CUR
    cmp #18
    bcs !cds_dex18plus+
    tax
    dex
    dex
    dex
    lda dex_disarm_bonus,x
    rts
!cds_dex18plus:
    cmp #59
    bcc !cds_dex4+
    cmp #94
    bcc !cds_dex5+
    cmp #117
    bcc !cds_dex6+
    lda #8
    rts
!cds_dex6:
    lda #6
    rts
!cds_dex5:
    lda #5
    rts
!cds_dex4:
    lda #4
    rts

chest_disarm_int_adj:
    lda player_data + PL_INT_CUR
    cmp #8
    bcs !cds_int_ge8+
    cmp #6
    bcs !cds_int_zero+
    sec
    sbc #6
    rts
!cds_int_zero:
    lda #0
    rts
!cds_int_ge8:
    cmp #15
    bcs !cds_int_ge15+
    lda #1
    rts
!cds_int_ge15:
    cmp #18
    bcs !cds_int_ge18+
    lda #2
    rts
!cds_int_ge18:
    cmp #19
    bcs !cds_int_18xx+
    lda #3
    rts
!cds_int_18xx:
    cmp #69
    bcc !cds_int4+
    lda #5
    rts
!cds_int4:
    lda #4
    rts

// ============================================================
// chest_roll_bad_fail — Mirror of disarm_roll_bad_fail (disarm_helpers.s).
// Input:  A = signed disarm total
// Output: carry set = bad fail / trap fires, carry clear = ordinary fail
// ============================================================
chest_roll_bad_fail:
    bmi !crbf_bad+
    cmp #6
    bcc !crbf_bad+
    jsr rng_range
    cmp #5
    bcc !crbf_bad+
    clc
    rts
!crbf_bad:
    sec
    rts

// ============================================================
// Stubs for steps 10-11 (disarm/bash chest branches)
// ============================================================
chest_bash_command:
chest_disarm_command:
    clc
    rts
