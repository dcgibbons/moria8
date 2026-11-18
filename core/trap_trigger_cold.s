#importonce
// trap_trigger_cold.s — Floor-trap trigger handlers and dispatch tables (S2a)
//
// Module ownership:
//   owner: ChestOverlay / TitleOverlay when TRAP_TRIGGER_EXTERNAL is defined
//     (co-located with core/disarm.s); TestUnused in C64 unit tests that do not
//     exercise traps; Default resident otherwise (imported by dungeon_features.s).
//   lifetime: one triggered floor trap (stepping onto a trap or bad-failing disarm).
//   callers: resident trap_check_at_player (via tramp_trap_trigger) and
//     co-located disarm_command (trap_trigger, df_stage_hidden_drop).
//     mon_atk_acid_armour's equipment recalc restores current_overlay via
//     hal_player_recalc_pflags before trap_do_acid resumes.

// ============================================================
// trap_trigger — Execute a trap's effect (traps 0..17, VMS §4.5)
// Input: X = trap table index (trap_type[X] has the type)
// ============================================================
trap_trigger:
    jsr player_search_mode_off   // Must stay first (test_main_loop PatchJump)
    lda trap_type,x
    sta df_search_chance
    tay
    lda trap_handler_hi,y
    pha
    lda trap_handler_lo,y
    pha
    rts

// Covered pit converts into a revealed open pit, then falls through to 2d6.
trap_do_covered_pit:
    lda #TRAP_OPEN_PIT
    sta trap_type,x

// Open pit (and converted covered pit): 2d6 damage (VMS open/covered pits).
trap_do_pit:
    bit player_pflags           // PFLAG_FFALL == $80
    bmi !tdp_ffall+
    lda #0
    beq trap_do_huff_dmg    // Always
!tdp_ffall:
    ldx #HSTR_DF_YOU_FELL
    jsr huff_print_msg
    ldx #HSTR_CHEST_UNAFFECTED
    jmp huff_print_msg

trap_do_arrow:
    lda #1
    bne trap_do_huff_dmg    // Always

// Rockfall: 2d6 damage and tile becomes rubble (removed from trap table).
trap_do_rockfall:
    lda #TILE_RUBBLE | FLAG_VISITED
    jsr trap_remove_set_tile
    lda #2

// Shared handler for Huffman-messaged fixed-dice damage traps (0..3).
trap_do_huff_dmg:
    tay
    lda trap_huff_dsrc_t,y
    sta df_death_source
    lda trap_huff_dhst_t,y
    sta df_death_hstr
    lda trap_huff_dice_t,y
    pha
    lda trap_huff_side_t,y
    pha
    ldx trap_huff_msg_t,y
    jsr huff_print_msg
    pla
    tax
    pla
    jmp trap_apply_damage

// Gas traps: 2=poison (11..20), 12=sleep (5..8 unless Free Action),
// 13=blind (26..75 + invalidate lit room), 14=confuse (16..30).
// Input: Y = trap type (2, 12, 13, 14).
trap_do_gas:
    tya
    sec
    sbc #11
    bpl !tdg_idx+
    lda #0                  // TRAP_POISON_GAS (2) -> 0
!tdg_idx:
    sta df_found
    ldx #HSTR_DF_POISON_GAS
    jsr huff_print_msg
    ldy df_found
    cpy #1                  // Sleep gas: Free Action suppresses
    bne !tdg_not_sleep+
    lda player_pflags
    and #PFLAG_FREE_ACT
    beq !tdg_roll+
    ldx #HSTR_CHEST_UNAFFECTED
    bne !tdg_msg+           // HSTR_CHEST_UNAFFECTED > 0
!tdg_not_sleep:
    cpy #2                  // Blindness gas: invalidate cached room visibility
    bne !tdg_roll+
    lda #1
    sta vis_room_revealed
!tdg_roll:
    lda gas_rng_max,y
    jsr rng_range           // Preserves Y (= df_found)
    clc
    adc gas_rng_base,y
    ldx gas_zp_eff,y
    sta $0000,x
    ldx gas_msg_hstr,y
!tdg_msg:
    jmp huff_print_msg

// Teleport: move player to random floor tile
trap_do_teleport:
    ldx #HSTR_DF_TELEPORTED
    jsr huff_print_msg
// trap_teleport — Move player to a random unoccupied floor tile
trap_teleport:
    jsr find_random_floor
    bcc !tt_done+
#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_COMMAND_EXTERNAL
    jmp disarm_move_player_to_target
#else
    ldx #1
!tt_loop:
    lda df_target_x,x
    sta zp_player_x,x
    sta player_data + PL_MAP_X,x
    dex
    bpl !tt_loop-
#endif
!tt_done:
    rts
.assert "trap_teleport: PL_MAP_Y follows PL_MAP_X", PL_MAP_Y, PL_MAP_X + 1

// Poison dart (1d4 + 50% -1 CON, min 3) and STR dart (1d4 + -1 STR, min 3)
trap_do_dart:
    lda #3
    jsr trap_do_huff_dmg
    beq !tdd_done+
    ldy #0
    lda df_search_chance
    cmp #TRAP_POISON_DART
    bne !tdd_drain+
    jsr rng_byte
    and #1
    beq !tdd_done+
    ldy #PL_CON_CUR - PL_STR_CUR
!tdd_drain:
    tya
    bne !tdd_chk_con_sust+
    lda #SUST_STR
    .byte $2c
!tdd_chk_con_sust:
    lda #SUST_CON
    and player_sust_mask
    bne !tdd_done+
    lda player_data + PL_STR_CUR,y
    cmp #4
    bcc !tdd_done+
    sty df_found
    jsr decrement_stat
    ldy df_found
    sta player_data + PL_STR_CUR,y
    sta zp_player_str,y
    cpy #PL_CON_CUR - PL_STR_CUR
    bne !tdd_combat+
    jsr player_calc_hp
!tdd_combat:
    jsr player_calc_combat
    ldx #HSTR_CHEST_WEAKENED
    jmp huff_print_msg
!tdd_done:
    rts

// Hidden object: remove trap -> floor, stage buried object drop at player tile.
trap_do_hidden_obj:
    jsr trap_remove_floor
// Local mirrors of constants declared later in monster_death.s / monster.s
// (MS_BREATH_FIRE == 5 is asserted in element_resist.s; MD_QUEUE_MAX == 4
// in monster_death.s). Declared here so KickAss resolves immediate operands
// during pass 0 before those files are imported.
.const DF_MD_QUEUE_MAX   = 4
.const DF_MS_BREATH_FIRE = 5

df_stage_hidden_drop:
    ldx md_count
    cpx #DF_MD_QUEUE_MAX
    bcs !dshd_msg+
    lda zp_player_x
    sta md_x,x
    lda zp_player_y
    sta md_y,x
    lda #$11                // Object (bit 0) + randint(2) drops (bit 4)
    sta md_flags,x
    inc md_count
!dshd_msg:
    ldx #HSTR_TUN_FOUND
    jmp huff_print_msg

// Summon monster rune: remove trap -> floor, stage 3..5 (randint(3)+2) summons.
trap_do_summon:
    jsr trap_remove_floor
    lda zp_player_x
    sta chest_summon_x
    lda zp_player_y
    sta chest_summon_y
    lda #3
    jsr rng_range
    clc
    adc #3
    sta chest_pending_summons
    ldx #HSTR_PMU_GLYPH_OK
    jmp huff_print_msg

// Remove trap X and rewrite its tile preserving TILE_FLAG_MASK flags.
trap_remove_floor:
    lda #TILE_FLOOR | FLAG_VISITED
trap_remove_set_tile:
    pha
    lda trap_x,x
    sta df_target_x
    lda trap_y,x
    sta df_target_y
    jsr trap_remove_at_index
    pla
    jmp df_set_target_tile

// Aggravate chute: shriek and wake all monsters on the level.
trap_do_aggravate:
    ldx #HSTR_MAT_SHRIEK
    jsr huff_print_msg
    jmp monster_aggravate_all

// Plain-message damage traps (8..11: TRAP_DOOR, CORRODE, FIRE, ACID).
trap_do_trap_door:
    bit player_pflags           // PFLAG_FFALL == $80
    bmi !td_ffall+
    jsr trap_do_plain_apply
    beq !td_done+
    bne !td_descend+
!td_ffall:
    ldx #0                      // "You fell through a trap door!"
    jsr trap_get_8_str_x
    jsr msg_print
    ldx #HSTR_CHEST_UNAFFECTED
    jsr huff_print_msg
!td_descend:
    // Trap door: descend 1 level (clamped at 99) and regenerate
    lda zp_player_dlvl
    cmp #99
    bcs !td_regen+
    inc zp_player_dlvl
    lda zp_player_dlvl
    sta player_data + PL_DLEVEL
    cmp player_data + PL_MAX_DLVL
    bcc !td_regen+
    sta player_data + PL_MAX_DLVL
!td_regen:
    lda #0
    sta level_entry_dir
    jmp scroll_teleport_level_exec

trap_do_corrode:
    jsr trap_do_plain_apply
    beq !td_done+
    jmp mon_atk_acid_armour

trap_do_acid:
    jsr trap_do_plain_setup
    lda zp_math_a           // 4d6 <= 24; preserve rolled damage across overlay recalc
    pha
    jsr mon_atk_acid_armour
    lda #1
    adc #0                  // Divisor 2 when worn piece took acid (C=1), else 1
    tax
    pla
    sta zp_math_a
    lda #0
    sta zp_math_b
    lda player_pflags
    and #PFLAG_RESIST_ACID
    beq trap_div_apply
    inx
    inx                     // +2 for Resist Acid -> divisor 3 or 4
    bne trap_div_apply      // Always (X is 3 or 4)

trap_do_fire:
    jsr trap_do_plain_setup
    lda #1
    ldx #DF_MS_BREATH_FIRE
    jsr mm_element_divisor_entry
    ldx mm_divisor
trap_div_apply:
    jsr math_div_16x8       // X >= 1 (divisor 1 leaves quotient unchanged)
    jmp trap_apply_rolled_damage
!td_done:
    rts

trap_do_plain_apply:
    jsr trap_do_plain_setup
    jmp trap_apply_rolled_damage

// Set up plain-string trap (df_search_chance in 8..11): death metadata,
// message, pre-staged creature_name_buf death noun, and rolled dice.
trap_do_plain_setup:
    lda df_search_chance
    sec
    sbc #TRAP_TRAP_DOOR
    pha
    tax
    lda trap_dsrc_8,x
    sta df_death_source
    lda #0
    sta df_death_hstr
    jsr trap_get_8_str_x
    jsr msg_print
    pla
    ora #4                  // Offset 4..7 = plain death noun for 0..3
    tax
    jsr trap_get_8_str_x
    ldy #0
!tdps_copy_death:
    lda (zp_ptr0),y
    sta creature_name_buf,y
    beq !tdps_death_done+
    iny
    bne !tdps_copy_death-
!tdps_death_done:
    ldx #6
    lda #4                  // 4d6 for CORRODE, FIRE, ACID
    ldy df_death_source
    cpy #DEATH_TRAP_PIT
    bne !tdps_roll+
    lda #2                  // 2d8 for TRAP_TRAP_DOOR
    ldx #8
!tdps_roll:
    ldy #0
    jmp math_dice

// Point zp_ptr0/hi at plain trap string X (0..3=hit msg, 4..7=death noun).
// Preserves Y, clobbers A.
trap_get_8_str_x:
    lda #<trap_8_strs
    clc
    adc trap_8_off,x
    sta zp_ptr0
    lda #>trap_8_strs
    adc #0
    sta zp_ptr0_hi
    rts

trap_handler_lo:
    .byte <(trap_do_pit - 1),        <(trap_do_arrow - 1),     <(trap_do_gas - 1),       <(trap_do_teleport - 1)
    .byte <(trap_do_dart - 1),       <(trap_do_rockfall - 1),  <(trap_do_covered_pit - 1), <(trap_do_dart - 1)
    .byte <(trap_do_trap_door - 1),  <(trap_do_corrode - 1),   <(trap_do_fire - 1),      <(trap_do_acid - 1)
    .byte <(trap_do_gas - 1),        <(trap_do_gas - 1),       <(trap_do_gas - 1)
    .byte <(trap_do_hidden_obj - 1), <(trap_do_summon - 1),    <(trap_do_aggravate - 1)
trap_handler_lo_end:
.assert "trap_handler_lo covers TRAP_TYPE_COUNT", trap_handler_lo_end - trap_handler_lo, TRAP_TYPE_COUNT

trap_handler_hi:
    .byte >(trap_do_pit - 1),        >(trap_do_arrow - 1),     >(trap_do_gas - 1),       >(trap_do_teleport - 1)
    .byte >(trap_do_dart - 1),       >(trap_do_rockfall - 1),  >(trap_do_covered_pit - 1), >(trap_do_dart - 1)
    .byte >(trap_do_trap_door - 1),  >(trap_do_corrode - 1),   >(trap_do_fire - 1),      >(trap_do_acid - 1)
    .byte >(trap_do_gas - 1),        >(trap_do_gas - 1),       >(trap_do_gas - 1)
    .byte >(trap_do_hidden_obj - 1), >(trap_do_summon - 1),    >(trap_do_aggravate - 1)
trap_handler_hi_end:
.assert "trap_handler_hi covers TRAP_TYPE_COUNT", trap_handler_hi_end - trap_handler_hi, TRAP_TYPE_COUNT

trap_huff_msg_t:  .byte HSTR_DF_YOU_FELL, HSTR_DF_ARROW_HITS, HSTR_DF_ROCKFALL, HSTR_DF_DART_HITS
trap_huff_dsrc_t: .byte DEATH_TRAP_PIT, DEATH_TRAP_ARROW, DEATH_TRAP_ROCKFALL, DEATH_TRAP_DART
trap_huff_dhst_t: .byte HSTR_DF_TRAP_0, HSTR_DF_TRAP_1, HSTR_DF_DEATH_ROCKFALL, HSTR_DF_TRAP_4
trap_huff_dice_t: .byte 2, 1, 2, 1
trap_huff_side_t: .byte 6, 8, 6, 4

gas_rng_max:  .byte 10, 4, 50, 15
gas_rng_base: .byte 11, 5, 26, 16
gas_zp_eff:   .byte zp_eff_poison, zp_eff_paralyze, zp_eff_blind, zp_eff_confuse
gas_msg_hstr: .byte HSTR_DF_POISONED, HSTR_CHEST_CHOKE, HSTR_PIQ_CANT_SEE, HSTR_PIQ_DIZZY
.assert "Gas timers are zero-page", zp_eff_poison < $100 && zp_eff_paralyze < $100 && zp_eff_blind < $100 && zp_eff_confuse < $100, true

trap_dsrc_8: .byte DEATH_TRAP_PIT, DEATH_TRAP_ARROW, DEATH_TRAP_ROCKFALL, DEATH_TRAP_ROCKFALL
trap_8_off:
    .byte trap_8_s0 - trap_8_strs, trap_8_s1 - trap_8_strs, trap_8_s2 - trap_8_strs, trap_8_s3 - trap_8_strs
    .byte trap_8_s4 - trap_8_strs, trap_8_s5 - trap_8_strs, trap_8_s6 - trap_8_strs, trap_8_s7 - trap_8_strs
trap_8_strs:
trap_8_s0: .text "A trap door opens!" ; .byte 0
trap_8_s1: .text "A blade hits you!" ; .byte 0
trap_8_s2: .text "Flames hit you!" ; .byte 0
trap_8_s3: .text "Acid hits you!" ; .byte 0
trap_8_s4: .text "a trap door" ; .byte 0
trap_8_s5: .text "a blade" ; .byte 0
trap_8_s6: .text "a fire trap" ; .byte 0
trap_8_s7: .text "an acid trap" ; .byte 0
trap_8_strs_end:
.assert "trap_8_strs fits 256 bytes", trap_8_strs_end - trap_8_strs <= 256, true
