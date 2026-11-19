#importonce
// monster_attack.s — Monster melee attacks on the player
//
// Called from monster_try_step when a monster is adjacent to the player.
// Handles to-hit rolls, damage (with AC reduction for normal attacks),
// 4-slot attack loop (atk0..atk3), 19 VMS ADESC_* attack verbs, all 24 VMS
// ATK_* effects, and player death.

#import "player_save.s"
#import "element_resist.s"

// ============================================================
// Base to-hit by attack type (VMS Moria 4.8 creature.inc make_attack)
// ============================================================
mon_atk_base_tohit:
    .byte 0     // 0: ATK_NONE
    .byte 60    // 1: ATK_NORMAL
    .byte <-3   // 2: ATK_LOSE_STR (VMS test_hit(-3, ...))
    .byte 10    // 3: ATK_CONFUSE
    .byte 10    // 4: ATK_FEAR
    .byte 10    // 5: ATK_FIRE
    .byte 0     // 6: ATK_ACID
    .byte 10    // 7: ATK_COLD
    .byte 10    // 8: ATK_LIGHT
    .byte 0     // 9: ATK_CORRODE
    .byte 2     // 10: ATK_BLIND
    .byte 2     // 11: ATK_PARALYZE
    .byte 5     // 12: ATK_STEAL_GOLD
    .byte 2     // 13: ATK_STEAL_ITEM
    .byte 5     // 14: ATK_POISON
    .byte 0     // 15: ATK_LOSE_DEX
    .byte 0     // 16: ATK_LOSE_CON
    .byte 2     // 17: ATK_LOSE_INT
    .byte 0     // 18: ATK_LOSE_WIS
    .byte 5     // 19: ATK_LOSE_EXP
    .byte 0     // 20: ATK_AGGRAVATE (always hits, no roll)
    .byte 20    // 21: ATK_DISENCHANT
    .byte 5     // 22: ATK_EAT_FOOD
    .byte 5     // 23: ATK_EAT_LIGHT
    .byte 15    // 24: ATK_EAT_CHARGES

// ============================================================
// Scratch variables (static RAM, safe across subroutine calls)
// ============================================================
mat_type2:        .byte 0   // Creature type index
mat_atk_type:     .byte 0   // Current attack's type ID
mat_any_hit:      .byte 0   // Nonzero: at least one blow connected this round
mat_slot_off:     .byte 0   // Current slot offset (0, 3, 6, 9 -> 12)
mat_dice:         .byte 0   // Current attack dice count
mat_sides:        .byte 0   // Current attack sides (0..15)
mat_cur_verb:     .byte 0   // Current attack ADESC_* verb (0..19)
mat_hit_verb:     .byte 0   // Connecting blow ADESC_* verb for round summary

// SoA pointer table for the 4 monster attack slots (atk0..atk3)
mat_arr_lo:
    .byte <cr_atk0_type, <cr_atk0_dice, <cr_atk0_sides
    .byte <cr_atk1_type, <cr_atk1_dice, <cr_atk1_sides
    .byte <cr_atk2_type, <cr_atk2_dice, <cr_atk2_sides
    .byte <cr_atk3_type, <cr_atk3_dice, <cr_atk3_sides
mat_arr_hi:
    .byte >cr_atk0_type, >cr_atk0_dice, >cr_atk0_sides
    .byte >cr_atk1_type, >cr_atk1_dice, >cr_atk1_sides
    .byte >cr_atk2_type, >cr_atk2_dice, >cr_atk2_sides
    .byte >cr_atk3_type, >cr_atk3_dice, >cr_atk3_sides

// ============================================================
// Subroutines
// ============================================================

// mon_atk_next_slot — Load and unpack (type, dice, sides, verb) for mat_slot_off
// Advances mat_slot_off by 3.
mon_atk_next_slot:
    ldx mat_slot_off
    jsr !mans_rd+
    sta mat_atk_type
    jsr !mans_rd+
    sta mat_dice
    jsr !mans_rd+
    stx mat_slot_off
    pha
    and #ATK_SIDES_MASK
    sta mat_sides
    pla
    lsr
    lsr
    lsr
    lsr
    asl mat_atk_type            // C = type_byte[7] = verb[0]
    rol                         // A = ((sides >> 4) << 1) | (type >> 7)
    sta mat_cur_verb
    lsr mat_atk_type            // mat_atk_type = type_byte & ATK_TYPE_MASK
    rts
!mans_rd:
    lda mat_arr_lo,x
    sta zp_ptr1
    lda mat_arr_hi,x
    sta zp_ptr1_hi
    inx
    ldy mat_type2
    lda (zp_ptr1),y
    rts

// monster_attack_player — Main entry point for monster melee
// Called from monster_try_step when monster is adjacent to player.
// Uses ZP $70-$7F (monster AI scratch) which is still valid.
// Clobbers: everything
monster_attack_player:
    jsr player_search_mode_off

    lda zp_mon_type
    sta mat_type2
    sta cmb_type                // For combat_append_monster_name reuse

    lda #0
    sta mat_any_hit
    sta mat_hit_verb
    sta mat_slot_off

    // --- Load Attack slot 0 ---
    jsr mon_atk_next_slot
    lda mat_atk_type
    bne !map_has_atk0+
    // ATK_NONE: no physical attacks (Quylthulg). Upstream attacks nothing,
    // so no round, miss message or recall count.
    rts
!map_has_atk0:
    inc zp_disturb

    // Protection from Evil (VMS Moria creature.inc make_attack): while active,
    // every attack of an evil creature with cr_level <= zp_player_lvl is repelled.
    ldx mat_type2
    lda zp_eff_protect
    beq !map_slot_loop+
    lda #CF_EVIL
    and cr_mflags,x
    beq !map_slot_loop+
    lda zp_player_lvl
    cmp cr_level,x
    bcs !map_repelled+          // Player level >= creature level

!map_slot_loop:
    lda mat_atk_type
    beq !map_done+              // ATK_NONE (0): stop attack loop
    cmp #ATK_BLANK
    beq !map_next_slot+         // ATK_BLANK (99): skip slot
    cmp #ATK_AGGRAVATE
    beq !map_do_aggravate+      // Aggravation always hits, no roll

    jsr mon_atk_calc_tohit      // -> zp_combat_tohit, then the roll
    bcc !map_next_slot+         // miss -> next slot

    lda mat_sides
    ldy mat_dice
    jsr mon_atk_hit
    bcs !map_player_dead+

!map_next_slot:
    lda mat_slot_off
    cmp #12
    bcs !map_done+
    jsr mon_atk_next_slot
    jmp !map_slot_loop-

!map_done:
    // Track attack in recall
    ldx mat_type2
#if HAL_PLATFORM_MONSTER_CATALOG
    jsr recall_inc_attacks_slot
#else
    :AuxIncX(recall_attacks)
#endif

    // Build and print summary message
    lda mat_any_hit
    beq !map_miss_msg+

    // Hit message: ADESC_NONE (0) / ADESC_HITS (1) keep HSTR_MAT_HITS;
    // ADESC_BITES..ADESC_INSULTS (2..19) format via mon_atk_verb_to_ptr2.
    lda mat_hit_verb
    cmp #ADESC_BITES
    bcc !map_hits_huff+
    jsr mon_atk_verb_to_ptr2
    jsr mon_atk_build_effect_msg
    jmp !map_hit_sfx+
!map_hits_huff:
    ldx #HSTR_MAT_HITS
    jsr mon_atk_huff_effect_msg
!map_hit_sfx:
    lda #SFX_HIT
    jmp hal_sound_play

!map_miss_msg:
    // Miss message: "THE <name> MISSES YOU."
    ldx #HSTR_MAT_MISS
    jsr mon_atk_huff_effect_msg
    lda #SFX_MISS
    jmp hal_sound_play

!map_repelled:
    ldx #HSTR_MAT_REPELLED
    jmp mon_atk_huff_effect_msg

!map_do_aggravate:
    jsr mon_atk_effect_aggravate
    ldx #HSTR_MAT_SHRIEK
    jmp huff_print_msg

!map_player_dead:
    ldx mat_type2
#if HAL_PLATFORM_MONSTER_CATALOG
    jsr recall_inc_deaths_slot
#else
    :AuxIncX(recall_deaths)
#endif
    stx zp_death_source
    jmp player_death_check

// mon_atk_huff_effect_msg — Decode Huffman string X and build monster effect msg
mon_atk_huff_effect_msg:
    jsr huff_decode_to_ptr2
    jmp mon_atk_build_effect_msg

// mon_atk_hit — An attack that connected: roll Y dice of A sides, apply the
// attack type's effect, then the damage (none once AC reduces it to 0).
// Output: carry set = player dead
mon_atk_hit:
    inc mat_any_hit             // Any connecting blow prevents "misses you."
    pha
    ldx mat_cur_verb
    beq !mah_verb_done+
    cpx #ADESC_BITES
    bcs !mah_set_verb+
    lda mat_hit_verb
    bne !mah_verb_done+
!mah_set_verb:
    stx mat_hit_verb
!mah_verb_done:
    pla
    tax                         // X = sides
    tya                         // A = dice count
    ldy #0                      // No bonus
    jsr math_dice               // -> zp_math_b:zp_math_a
    lda zp_math_a
    sta zp_combat_dmg
    lda zp_math_b
    sta mad_dmg_hi

    jsr mon_atk_effect_dispatch // zp_combat_dmg may be modified

    lda zp_combat_dmg
    beq !mah_none+              // 0 damage after effect / AC reduce
    jmp mon_atk_apply_damage
!mah_none:
    clc
    rts

// mon_atk_calc_tohit — Compute monster's hit chance, then roll it
// hit_chance = signed base_to_hit[atk_type] + cr_level * 3, clamped [0, 255]
// Output: zp_combat_tohit; carry set = hit (mon_atk_roll_tohit)
mon_atk_calc_tohit:
    lda #0
    sta zp_temp1
    ldx mat_type2
    lda cr_level,x
    sta zp_temp0
    asl
    rol zp_temp1
    clc
    adc zp_temp0
    bcc !mact_l3+
    inc zp_temp1                // zp_temp1:A = cr_level * 3 (0..765)
!mact_l3:
    ldx mat_atk_type
    cpx #ATK_LOSE_STR
    bne !mact_nonneg+
    sec                         // ATK_LOSE_STR (2): bth = -3
    sbc #3
    bcs !mact_chk_cap+
    dec zp_temp1
    bpl !mact_chk_cap+
    lda #0                      // Signed sum < 0 -> floor at 0
    beq !mact_store+
!mact_nonneg:
    cpx #25
    bcs !mact_chk_cap+
    clc
    adc mon_atk_base_tohit,x
    bcc !mact_chk_cap+
    inc zp_temp1
!mact_chk_cap:
    ldy zp_temp1
    beq !mact_store+
    lda #255                    // Sum >= 256 -> cap at 255
!mact_store:
    sta zp_combat_tohit
    // Fall through: roll the hit

// mon_atk_roll_tohit — d20 roll with natural 1/20 rules
// Input: zp_combat_tohit = hit chance
// Output: carry set = hit, carry clear = miss
mon_atk_roll_tohit:
    lda #20
    jsr rng_range               // [0,19]
    cmp #19
    beq !mart_hit+              // 19 (+1 = natural 20) -> always hit
    ora #0
    beq !mart_miss+             // 0 (+1 = natural 1) -> always miss

    // VMS creature.inc:318-323: Steal Gold (12) and Steal Item (13) roll
    // against py.misc.lev (zp_player_lvl) rather than player AC.
    lda zp_combat_tohit
    cmp #2
    bcc !mart_miss+             // tohit too low
    jsr rng_range               // [0, tohit-1]
    pha
    lda mat_atk_type
    sec
    sbc #ATK_STEAL_GOLD
    cmp #2                      // 12 (STEAL_GOLD) or 13 (STEAL_ITEM)
    bcs !mart_vs_ac+
    lda zp_player_lvl
    jmp !mart_cmp+
!mart_vs_ac:
    jsr mon_atk_effective_ac
!mart_cmp:
    sta mat_eff_ac
    pla
    cmp mat_eff_ac              // >= AC / level?
    bcs !mart_hit+

!mart_miss:
    clc
    rts
!mart_hit:
    sec
    rts
.assert "ATK_STEAL_ITEM follows ATK_STEAL_GOLD", ATK_STEAL_ITEM, ATK_STEAL_GOLD + 1

// mon_atk_apply_damage — Subtract damage from player HP
mon_atk_apply_damage:
    lda #0
    sta mad_dmg_hi
mon_atk_apply_damage_16:
    lda eff_invuln_timer
    beq !mad_apply+
    clc
    rts
!mad_apply:
    lda zp_player_hp_lo
    sec
    sbc zp_combat_dmg
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO

    lda zp_player_hp_hi
    sbc mad_dmg_hi
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    bmi !mad_dead+
    ora zp_player_hp_lo
    beq !mad_dead+

    clc                         // Alive
    rts
!mad_dead:
    sec                         // Dead
    rts

mad_dmg_hi: .byte 0

// mon_atk_ac_reduce — AC damage reduction for normal/physical status attacks
// damage -= (player_AC * damage) / 200
mon_atk_ac_reduce:
    jsr mon_atk_effective_ac
    ldx zp_combat_dmg
    jsr math_multiply           // zp_math_a/b = AC * damage (16-bit)
    ldx #200
    jsr math_div_16x8           // zp_math_a = quotient lo (reduction)
    lda zp_combat_dmg
    sec
    sbc zp_math_a
    bcs !macr_ok+
    lda #0                      // Floor at 0
!macr_ok:
    sta zp_combat_dmg
    rts

mat_eff_ac: .byte 0

// mon_atk_effective_ac — Player AC with active bless (+2 AC) adjustment.
mon_atk_effective_ac:
    lda zp_player_ac
    ldx zp_eff_bless
    beq !maea_done+
    clc
    adc #2
    bcc !maea_done+
    lda #255
!maea_done:
    rts

// mon_atk_effect_dispatch — Route to type-specific handler
mon_atk_effect_dispatch:
    lda mat_atk_type

    cmp #ATK_NORMAL
    beq mon_atk_ac_reduce
    cmp #ATK_POISON
    beq !maed_poison+
    cmp #ATK_CONFUSE
    beq !maed_confuse+
    cmp #ATK_PARALYZE
    beq !maed_paralyze+
    cmp #ATK_ACID
    beq !maed_acid+
    cmp #ATK_FEAR
    beq !maed_fear+
    cmp #ATK_BLIND
    beq !maed_blind+
    cmp #ATK_LOSE_STR
    beq !maed_ext+
    // Fire, cold, lightning (5, 7, 8; acid 6 is taken above)
    cmp #ATK_FIRE
    bcc mon_atk_ac_reduce
    cmp #ATK_LIGHT + 1
    bcc mon_atk_effect_element
    cmp #ATK_EAT_CHARGES + 1
    bcc !maed_ext+
    bcs mon_atk_ac_reduce
!maed_ext:
    jmp mon_atk_effect_ext
!maed_poison:
    jmp mon_atk_effect_poison
!maed_paralyze:
    jmp mon_atk_effect_paralyze
!maed_acid:
    jmp mon_atk_effect_acid
!maed_fear:
    jmp mon_atk_effect_fear
!maed_confuse:
    lda #2
    jsr rng_range               // 50% chance
    bne !maed_conf_done+
    jmp mon_atk_effect_confuse
!maed_conf_done:
    rts
.assert "The element touches are 5-8 with acid between", ATK_FIRE == 5 && ATK_ACID == 6 && ATK_COLD == 7 && ATK_LIGHT == 8, true

// mon_atk_effect_element — Fire, cold and lightning touches (5, 7, 8)
mon_atk_effect_element:
    ldy mat_atk_type
    ldx maee_msg - ATK_FIRE,y
    jsr mon_atk_huff_effect_msg
    ldy mat_atk_type
    ldx maee_kind - ATK_FIRE,y
    lda #1
    jsr mm_element_divisor_entry
    ldx mm_divisor
    jmp mat_div_dmg
maee_msg:  .byte HSTR_MAT_FIRE, 0, HSTR_MAT_COLD, HSTR_MAT_LIGHT
maee_kind: .byte MS_BREATH_FIRE, 0, MS_BREATH_FROST, MS_BREATH_LIGHTNING
.assert "The element touches are attack types 5-8", ATK_FIRE == 5 && ATK_COLD == 7 && ATK_LIGHT == 8, true

// Shared helper: A = rng_range(cr_level) + Y; C = 0
mon_atk_roll_lvl_plus_y:
    sty zp_temp0
    ldx mat_type2
    lda cr_level,x
    jsr rng_range
    clc
    adc zp_temp0
    rts

// Shared helper: A = min(255, A + Y)
mon_atk_sat_add_y:
    sty zp_temp0
    clc
    adc zp_temp0
    bcc !masay_ok+
    lda #255
!masay_ok:
    rts

!maed_blind:
    // VMS creature.inc:454: AC-reduced HP + 10 + randint(level) blind (+5 stack)
    jsr mon_atk_ac_reduce
    lda zp_eff_blind
    bne !mb_stack+
    ldy #11
    jsr mon_atk_roll_lvl_plus_y
    sta zp_eff_blind
    ldx #HSTR_MM_BLIND
    jmp mon_atk_huff_effect_msg
!mb_stack:
    ldy #5
    jsr mon_atk_sat_add_y
    sta zp_eff_blind
    rts

mep_was_poisoned: .byte 0

// mon_atk_effect_poison — Set/stack poison timer (randint(level) + 5)
mon_atk_effect_poison:
    ldy zp_eff_poison
    sty mep_was_poisoned
    ldy #6
    jsr mon_atk_roll_lvl_plus_y
    ldy zp_eff_poison
    jsr mon_atk_sat_add_y
    sta zp_eff_poison
    lda mep_was_poisoned
    bne !mep_done+
    ldx #HSTR_MAT_POISON
    jmp mon_atk_huff_effect_msg
!mep_done:
    rts

// mon_atk_effect_confuse — Set/stack confusion timer (randint(level) + 3, +3 stack)
mon_atk_effect_confuse:
    lda zp_eff_confuse
    bne !mec_stack+
    ldy #4
    jsr mon_atk_roll_lvl_plus_y
    sta zp_eff_confuse
    ldx #HSTR_MAT_CONFUSE
    jmp mon_atk_huff_effect_msg
!mec_stack:
    ldy #3
    jsr mon_atk_sat_add_y
    sta zp_eff_confuse
    rts

// mon_atk_effect_paralyze — Saving throw, Free Action check, then paralysis timer
mon_atk_effect_paralyze:
    lda zp_eff_paralyze
    bne !mepa_done+
    lda player_data + PL_CON_CUR
    jsr player_con_hp_adj       // VMS con_adj
    jsr player_saving_throw
    bcc !mepa_done+             // Saved -> resist
    lda player_pflags
    and #PFLAG_FREE_ACT
    beq !mepa_held+
    ldx #HSTR_CHEST_UNAFFECTED
    jmp huff_print_msg
!mepa_held:
    ldy #4
    jsr mon_atk_roll_lvl_plus_y
    sta zp_eff_paralyze
    ldx #HSTR_MAT_PARALYZE
    jmp mon_atk_huff_effect_msg
!mepa_done:
    rts

#if !MON_ATK_ACID_EXTERNAL
#import "monster_acid.s"
#endif

// mon_atk_effect_fear — Fear attack (Heroism / WIS save, 3 + randint(level), +3 stack)
mon_atk_effect_fear:
    lda zp_eff_hero
    bne !mef_done+
    lda player_data + PL_WIS_CUR
    jsr player_wis_save_adj
    jsr player_saving_throw
    bcc !mef_done+              // Saved
    lda eff_fear_timer
    beq !mef_new+
    ldy #3
    jsr mon_atk_sat_add_y
    sta eff_fear_timer
    rts
!mef_new:
    ldy #4
    jsr mon_atk_roll_lvl_plus_y
    sta eff_fear_timer
    ldx #HSTR_MAT_FEAR
    jmp mon_atk_huff_effect_msg
!mef_done:
    rts

// player_death_check — Check if player is dead, set game flag
player_death_check:
    lda zp_player_hp_hi
    bmi !pdc_dead+
    ora zp_player_hp_lo
    beq !pdc_dead+
    rts
!pdc_dead:
    lda zp_game_flags
    ora #$01                    // Set GF_DEAD (bit 0)
    sta zp_game_flags
    lda #SFX_DEATH
    jmp hal_sound_play

// ============================================================
// Compile-time validation
// ============================================================
.assert "ATK_NORMAL", ATK_NORMAL, 1
.assert "ATK_AGGRAVATE", ATK_AGGRAVATE, 20
