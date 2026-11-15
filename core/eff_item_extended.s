#importonce
// eff_item_extended.s — Extended VMS food/mushroom (#248-#269, #365) and
// Page 1 potion (#270-#294) effects.
//
// Imported by player_item_commands.s when !HAL_PLATFORM_COMPACT_PLAY_SLOT &&
// !HAL_PLATFORM_EFF_ITEM_EXTENDED_EXTERNAL, or by player_magic_execute_overlay.s
// (OVL_SPELL) on HAL_PLATFORM_COMPACT_PLAY_SLOT ports.
// Uses only resident helpers + eff_potion_cure.s so it executes safely from
// either Default, RuntimeBanked/OVL_ITEMS, or OVL_SPELL. ZERO new ZP variables.

.const EE_OP_CURE       = 0
.const EE_OP_HEAL_CURE  = 1
.const EE_OP_POISON     = 2
.const EE_OP_TIMER      = 3
.const EE_OP_BOLD       = 4
.const EE_OP_DRAIN      = 5
.const EE_OP_RESTORE    = 6
.const EE_OP_DRINK      = 7
.const EE_OP_TIMED_MISC = 8
.const EE_OP_XP         = 9

eff_ext_arg: .byte 0
eff_ext_tmp: .byte 0

// eff_ext_eat_piw / eff_ext_eat — Execute extended food/mushroom effect.
// Input (eff_ext_eat_piw): piw_ego, piw_item_id.
// Input (eff_ext_eat): A = slot_lo, item_cur_page = $00 or ITEM_PAGE_BIT ($40).
// Clobbers: A, X, Y, zp_temp0-4, zp_math_*, zp_ptr0-1
eff_ext_eat_piw:
    lda piw_ego
    sta item_cur_page
    lda piw_item_id
eff_ext_eat:
    bit item_cur_page
    bvs !eee_p1+
    cmp #248
    bcc !eee_ret+
    sec
    sbc #248                        // 0..6: #248..254
    jmp eff_ext_run
!eee_p1:
    cmp #ITEM_TYPE_ELVISH_WAYBREAD_H - ITEM_PAGE_SIZE
    bne !eee_p1_mush+
    lda #1                          // #365 Elvish Waybread == #249 Waybread
    bne eff_ext_run                 // always
!eee_p1_mush:
    cmp #15
    bcs !eee_ret+
    clc
    adc #7                          // 7..21: #255..269
    bne eff_ext_run                 // always >= 7
!eee_ret:
    rts

// eff_ext_quaff_piw / eff_ext_quaff — Execute Page 1 potion effect (#270-#294 -> lo 15..39).
// Input (eff_ext_quaff_piw): piw_ego, piw_item_id.
// Input (eff_ext_quaff): A = slot_lo, item_cur_page = ITEM_PAGE_BIT ($40).
// Clobbers: A, X, Y, zp_temp0-4, zp_math_*, zp_ptr0-1
eff_ext_quaff_piw:
    lda piw_ego
    sta item_cur_page
    lda piw_item_id
eff_ext_quaff:
    cmp #15
    bcc !eee_ret-
    cmp #40
    bcs !eee_ret-
    clc
    adc #7                          // 22..46: #270..294

eff_ext_run:
    tax
    lda eff_ext_arg_tbl,x
    sta eff_ext_arg
    lda eff_ext_op_tbl,x
    tax
    lda eff_ext_jmp_hi,x
    pha
    lda eff_ext_jmp_lo,x
    pha
    rts

eff_ext_jmp_lo:
    .byte <(ee_op_cure-1), <(ee_op_heal_cure-1), <(ee_op_poison-1), <(ee_op_timer-1)
    .byte <(ee_op_bold-1), <(ee_op_drain-1), <(ee_op_restore-1), <(ee_op_drink-1)
    .byte <(ee_op_timed_misc-1), <(ee_op_xp-1)
eff_ext_jmp_hi:
    .byte >(ee_op_cure-1), >(ee_op_heal_cure-1), >(ee_op_poison-1), >(ee_op_timer-1)
    .byte >(ee_op_bold-1), >(ee_op_drain-1), >(ee_op_restore-1), >(ee_op_drink-1)
    .byte >(ee_op_timed_misc-1), >(ee_op_xp-1)

// Compact dispatch tables for indices 0..46 (#248..294).
eff_ext_op_tbl:
    // 0..6: Page 0 #248..254
    .byte EE_OP_HEAL_CURE, EE_OP_HEAL_CURE, EE_OP_CURE, EE_OP_POISON
    .byte EE_OP_TIMER, EE_OP_DRAIN, EE_OP_HEAL_CURE
    // 7..21: Page 1 #255..269
    .byte EE_OP_CURE, EE_OP_TIMER, EE_OP_TIMER, EE_OP_HEAL_CURE
    .byte EE_OP_CURE, EE_OP_BOLD, EE_OP_TIMER, EE_OP_POISON
    .byte EE_OP_DRAIN, EE_OP_HEAL_CURE, EE_OP_TIMER, EE_OP_CURE
    .byte EE_OP_RESTORE, EE_OP_DRAIN, EE_OP_RESTORE
    // 22..46: Page 1 #270..294
    .byte EE_OP_TIMER, EE_OP_DRINK, EE_OP_DRINK, EE_OP_DRINK
    .byte EE_OP_DRINK, EE_OP_TIMED_MISC, EE_OP_BOLD, EE_OP_TIMED_MISC
    .byte EE_OP_DRAIN, EE_OP_TIMED_MISC, EE_OP_TIMED_MISC, EE_OP_XP
    .byte EE_OP_DRAIN, EE_OP_DRAIN, EE_OP_DRAIN, EE_OP_TIMED_MISC
    .byte EE_OP_RESTORE, EE_OP_RESTORE, EE_OP_RESTORE, EE_OP_RESTORE
    .byte EE_OP_RESTORE, EE_OP_RESTORE, EE_OP_XP, EE_OP_XP, EE_OP_XP

eff_ext_arg_tbl:
    // #248..254
    .byte $18 | EFF_CURE_BLIND, $40 | EFF_CURE_POISON, EFF_CURE_CONFUSE, 1
    .byte 0, STAT_STR, $20 | EFF_CURE_ALL
    // #255..269
    .byte EFF_CURE_POISON, 1, 2, $10 | EFF_CURE_BLIND
    .byte EFF_CURE_BLIND, 0, 3, 2
    .byte STAT_CON, $30 | EFF_CURE_BLIND | EFF_CURE_CONFUSE, 3, EFF_CURE_POISON
    .byte STAT_CON, STAT_CON | $80, $ff
    // #270..294
    .byte 4, 100, 0, 125
    .byte 200, 0, 1, 1
    .byte STAT_STR, 2, 4, 0
    .byte STAT_INT, STAT_WIS, STAT_CHR, 3
    .byte STAT_STR, STAT_INT, STAT_WIS, STAT_CHR
    .byte STAT_DEX, STAT_CON, 1, 2, 3

// ============================================================
// Opcode handlers (entered via RTS dispatch)
// ============================================================

ee_op_cure:
    lda eff_ext_arg
    jmp eff_cure_timers

ee_op_heal_cure:
    lda eff_ext_arg
    lsr
    lsr
    lsr
    lsr
    tay                             // Y = dice count
    ldx #8
    lda eff_ext_arg
    and #$08
    beq !eehc_sides+
    ldx #4
!eehc_sides:
    lda eff_ext_arg
    and #$07
    jmp eff_potion_heal_cure

ee_op_poison:
    lda eff_ext_arg
    ldx #8
    ldy #0
    jsr math_dice
    lda zp_math_a
    jsr ee_apply_hp_damage
    lda #10
    jsr rng_range
    clc
    adc #10
    clc
    adc zp_eff_poison
    bcc !eep_ok+
    lda #255
!eep_ok:
    sta zp_eff_poison
    ldx #HSTR_PIQ_TERRIBLE
    jmp huff_print_msg

ee_op_timer:
    ldx eff_ext_arg
    bne !eet_not0+
    // 0: Confusion (rng(15)+10)
    lda #15
    ldx #10
    ldy #2                          // zp_eff_confuse = zp_eff_poison + 2
    jsr ee_add_zp_timer
    ldx #HSTR_PIQ_DIZZY
    jmp huff_print_msg
!eet_not0:
    cpx #1
    bne !eet_not1+
    // 1: Blindness (rng(100)+100)
    lda #100
    ldx #100
    ldy #1                          // zp_eff_blind = zp_eff_poison + 1
    jsr ee_add_zp_timer
    ldx #HSTR_PIQ_CANT_SEE
    jmp huff_print_msg
!eet_not1:
    cpx #2
    bne !eet_not2+
    // 2: Paranoia / Fear
    lda #10
    jsr rng_range
    sec
    adc #10
    clc
    adc eff_fear_timer
    bcc !eet_fear_ok+
    lda #255
!eet_fear_ok:
    sta eff_fear_timer
    lda #<ee_msg_afraid
    ldy #>ee_msg_afraid
    jmp msg_print_ay
!eet_not2:
    cpx #3
    bne !eet_sleep+
    // 3: Hallucination (confusion fallback)
    lda #15
    ldx #15
    ldy #2
    jsr ee_add_zp_timer
    lda #<ee_msg_halluc
    ldy #>ee_msg_halluc
    jmp msg_print_ay
!eet_sleep:
    // 4: Sleep (Free Action resists)
    lda player_pflags
    and #PFLAG_FREE_ACT
    beq !eet_sleep_do+
    ldx #HSTR_PIQ_NOTHING
    jmp huff_print_msg
!eet_sleep_do:
    lda #4
    ldx #4
    ldy #3                          // zp_eff_paralyze = zp_eff_poison + 3
    jsr ee_add_zp_timer
    lda #<ee_msg_sleep
    ldy #>ee_msg_sleep
    jmp msg_print_ay

ee_op_bold:
    lda eff_fear_timer
    beq !eeb_msg+
    lda #0
    sta eff_fear_timer
    lda eff_ext_arg
    bne !eeb_bold+
    ldx #HSTR_EFF_FEAR_END
    jmp huff_print_msg
!eeb_msg:
    lda eff_ext_arg
    beq !eeb_done+
!eeb_bold:
    lda #<ee_msg_bold
    ldy #>ee_msg_bold
    jmp msg_print_ay
!eeb_done:
    rts

ee_op_drain:
    lda eff_ext_arg
    and #$07
    tax
    lda ee_sust_tbl,x
    and player_sust_mask
    bne !eed_sustained+
    lda player_data + PL_STR_CUR,x
    cmp #4
    bcc !eed_sustained+
    stx eff_ext_tmp
    jsr decrement_stat
    ldx eff_ext_tmp
    sta player_data + PL_STR_CUR,x
    sta zp_player_str,x
    lda #<ee_msg_weak
    ldy #>ee_msg_weak
    jsr msg_print_ay
    jmp !eed_unhealth+
!eed_sustained:
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
!eed_unhealth:
    bit eff_ext_arg
    bpl !eed_done+
    lda #10
    ldx #10
    ldy #0
    jsr math_dice                   // 10d10 unhealth damage (<= 100)
    lda zp_math_a
    jmp ee_apply_hp_damage
!eed_done:
    rts

ee_op_restore:
    lda eff_ext_arg
    cmp #$ff
    bne !eer_single+
    jsr player_calc_stats
    ldx #HSTR_PIQ_RESTORED
    jmp huff_print_msg
!eer_single:
    sta eff_ext_tmp
    ldx #5
!eer_push:
    lda player_data + PL_STR_CUR,x
    pha
    dex
    bpl !eer_push-
    jsr player_calc_stats           // Recalculates all CUR from BASE + equipment
    ldx #0
!eer_pop:
    pla
    cpx eff_ext_tmp
    beq !eer_keep_new+
    cmp player_data + PL_STR_CUR,x
    bcs !eer_keep_new+              // Keep drained value on un-targeted stats
    sta player_data + PL_STR_CUR,x
    sta zp_player_str,x
!eer_keep_new:
    inx
    cpx #STAT_COUNT
    bcc !eer_pop-
    ldx #HSTR_PIQ_RESTORED
    jmp huff_print_msg

ee_op_drink:
    lda eff_ext_arg
    bne !eedk_add+
    // Salt Water emetic: reduce food to <= 100, cure poison, +4 paralysis
    lda player_data + PL_FOOD_HI
    bne !eedk_reset_food+
    lda player_data + PL_FOOD_LO
    cmp #101
    bcc !eedk_food_ok+
!eedk_reset_food:
    lda #100
    sta zp_player_food
    sta player_data + PL_FOOD_LO
    lda #0
    sta zp_player_food_hi
    sta player_data + PL_FOOD_HI
    jsr player_update_hunger_state
!eedk_food_ok:
    jsr eff_cure_poison
    lda zp_eff_paralyze
    clc
    adc #4
    bcc !eedk_par_ok+
    lda #255
!eedk_par_ok:
    sta zp_eff_paralyze
    lda #<ee_msg_vomit
    ldy #>ee_msg_vomit
    jmp msg_print_ay
!eedk_add:
    // eff_ext_arg is half of the nutrition amount (100/125/200 -> 200/250/400)
    ldy #0
    asl
    bcc !eedk_no_hi+
    iny
!eedk_no_hi:
    clc
    adc zp_player_food
    sta zp_player_food
    tya
    adc zp_player_food_hi
    sta zp_player_food_hi
    lda #FOOD_MAX_LO
    cmp zp_player_food
    lda #FOOD_MAX_HI
    sbc zp_player_food_hi
    bcs !eedk_cap_ok+
    lda #FOOD_MAX_LO
    sta zp_player_food
    lda #FOOD_MAX_HI
    sta zp_player_food_hi
!eedk_cap_ok:
    lda zp_player_food
    sta player_data + PL_FOOD_LO
    lda zp_player_food_hi
    sta player_data + PL_FOOD_HI
    jsr player_update_hunger_state
    lda eff_ext_arg
    cmp #200                        // Slime Mold Juice
    bne !eedk_water+
    ldx #HSTR_PIW_YUCK
    jmp huff_print_msg
!eedk_water:
    lda #<ee_msg_drink
    ldy #>ee_msg_drink
    jmp msg_print_ay

ee_op_timed_misc:
    ldx eff_ext_arg
    bne !eetm_not0+
    // 0: Slowness
    lda #25
    jsr rng_range
    sec
    adc #15
    sta eff_ext_tmp
    lda zp_eff_speed
    sec
    sbc eff_ext_tmp
    bvc !eetm_slow_ok+
    lda #$81
!eetm_slow_ok:
    sta zp_eff_speed
    lda #<ee_msg_slow
    ldy #>ee_msg_slow
    jmp msg_print_ay
!eetm_not0:
    cpx #1
    bne !eetm_not1+
    // 1: Slow Poison
    lda zp_eff_poison
    beq !eetm_ret+
    lsr
    ora #1
    sta zp_eff_poison
    ldx #HSTR_EFF_POISON_END
    jmp huff_print_msg
!eetm_ret:
    rts
!eetm_not1:
    cpx #2
    bne !eetm_not2+
    // 2: Detect Invisible
    lda #1
    sta zp_eff_see_inv
    lda #12
    ldx #12
    ldy #zp_eff_invis - zp_eff_poison
    jsr ee_add_zp_timer
    ldx #HSTR_PIQ_EYES_TINGLE
    jmp huff_print_msg
!eetm_not2:
    cpx #3
    bne !eetm_shero+
    // 3: Invulnerability
    lda #10
    jsr rng_range
    sec
    adc #10
    clc
    adc eff_invuln_timer
    bcc !eetm_inv_ok+
    lda #255
!eetm_inv_ok:
    sta eff_invuln_timer
    lda #<ee_msg_invuln
    ldy #>ee_msg_invuln
    jmp msg_print_ay
!eetm_shero:
    // 4: Super Heroism
    lda #0
    sta eff_fear_timer
    lda zp_eff_hero
    bne !eetm_sh_timer+
    lda player_data + PL_MHP_LO
    clc
    adc #10
    sta player_data + PL_MHP_LO
    sta zp_player_mhp_lo
    bcc !eetm_sh_mhp+
    inc player_data + PL_MHP_HI
    inc zp_player_mhp_hi
!eetm_sh_mhp:
    lda #10
    jsr eff_heal
!eetm_sh_timer:
    lda #30
    jsr pmx_heal_and_report
    lda #25
    ldx #25
    ldy #zp_eff_hero - zp_eff_poison
    jsr ee_add_zp_timer
    ldx #HSTR_PIQ_HEROIC
    jmp huff_print_msg

ee_op_xp:
    ldx eff_ext_arg
    bne !eex_not0+
    // 0: Lose Memories (xp -= xp >> 2)
    lda player_data + PL_XP_2
    lsr
    sta zp_temp2
    lda player_data + PL_XP_1
    ror
    sta zp_temp1
    lda player_data + PL_XP_0
    ror
    lsr zp_temp2
    ror zp_temp1
    ror
    sta zp_temp0
    lda player_data + PL_XP_0
    sec
    sbc zp_temp0
    sta player_data + PL_XP_0
    lda player_data + PL_XP_1
    sbc zp_temp1
    sta player_data + PL_XP_1
    lda player_data + PL_XP_2
    sbc zp_temp2
    sta player_data + PL_XP_2
    lda #<ee_msg_memories
    ldy #>ee_msg_memories
    jmp msg_print_ay
!eex_not0:
    cpx #1
    bne !eex_not1+
    // 1: Restore Life Levels
    lda #<ee_msg_restore_lvl
    ldy #>ee_msg_restore_lvl
    jmp msg_print_ay
!eex_not1:
    cpx #2
    bne !eex_gain+
    // 2: Learning
    lda player_data + PL_SPELL_TYPE
    beq !eex_learn_msg+
    inc player_data + PL_NEW_SPELLS
!eex_learn_msg:
    lda #<ee_msg_learn
    ldy #>ee_msg_learn
    jmp msg_print_ay
!eex_gain:
    // 3: Gain Experience: xp += (xp >> 1) + 10
    lda player_data + PL_XP_2
    lsr
    sta zp_temp2
    lda player_data + PL_XP_1
    ror
    sta zp_temp1
    lda player_data + PL_XP_0
    ror
    clc
    adc #10
    sta zp_temp0
    bcc !eex_g1+
    inc zp_temp1
    bne !eex_g1+
    inc zp_temp2
!eex_g1:
    lda player_data + PL_XP_0
    clc
    adc zp_temp0
    sta player_data + PL_XP_0
    lda player_data + PL_XP_1
    adc zp_temp1
    sta player_data + PL_XP_1
    lda player_data + PL_XP_2
    adc zp_temp2
    bcc !eex_g_ok+
    lda #$ff
    sta player_data + PL_XP_0
    sta player_data + PL_XP_1
!eex_g_ok:
    sta player_data + PL_XP_2
    lda #<ee_msg_gain_xp
    ldy #>ee_msg_gain_xp
    jsr msg_print_ay
    jmp combat_check_levelup

// ============================================================
// Shared tiny helpers + data
// ============================================================

// ee_add_zp_timer — zp_eff_poison[Y] += rng_range(A) + X, saturating at 255.
// Preserves: Y
ee_add_zp_timer:
    stx eff_ext_tmp
    jsr rng_range
    clc
    adc eff_ext_tmp
    clc
    adc zp_eff_poison,y
    bcc !eazt_ok+
    lda #255
!eazt_ok:
    sta zp_eff_poison,y
    rts

// ee_apply_hp_damage — Subtract A HP (sets DEATH_POISON + GF_DEAD on <= 0).
ee_apply_hp_damage:
    sta eff_ext_tmp
    lda zp_player_hp_lo
    sec
    sbc eff_ext_tmp
    sta zp_player_hp_lo
    lda zp_player_hp_hi
    sbc #0
    sta zp_player_hp_hi
    bmi !eah_dead+
    bne !eah_sync+
    lda zp_player_hp_lo
    bne !eah_sync+
!eah_dead:
    lda #0
    sta zp_player_hp_lo
    sta zp_player_hp_hi
    lda #DEATH_POISON
    sta zp_death_source
    lda zp_game_flags
    ora #$01
    sta zp_game_flags
!eah_sync:
    jmp eff_heal_sync

ee_sust_tbl:
    .byte SUST_STR, SUST_INT, SUST_WIS, SUST_DEX, SUST_CON, SUST_CHR

ee_msg_afraid:      .text "You tremble with fear." ; .byte 0
ee_msg_halluc:      .text "Everything looks strange!" ; .byte 0
ee_msg_sleep:       .text "You fall asleep." ; .byte 0
ee_msg_bold:        .text "You feel bold." ; .byte 0
ee_msg_weak:        .text "You feel weaker." ; .byte 0
ee_msg_vomit:       .text "The potion makes you vomit!" ; .byte 0
ee_msg_drink:       .text "You feel refreshed." ; .byte 0
ee_msg_slow:        .text "You feel yourself slow down." ; .byte 0
ee_msg_invuln:      .text "You feel invulnerable." ; .byte 0
ee_msg_memories:    .text "You feel memories fading." ; .byte 0
ee_msg_restore_lvl: .text "You feel your life returning." ; .byte 0
ee_msg_learn:       .text "You feel more knowledgeable." ; .byte 0
ee_msg_gain_xp:     .text "You feel more experienced." ; .byte 0
