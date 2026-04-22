#importonce
// monster_attack.s — Monster melee attacks on the player
//
// Called from monster_try_step when a monster is adjacent to the player.
// Handles to-hit rolls, damage (with AC reduction for normal attacks),
// special effects (poison, confusion, paralysis, acid, aggravation),
// and player death. Uses umoria formulas.

// ============================================================
// Base to-hit by attack type (from umoria playerTestAttackHits)
// ============================================================
mon_atk_base_tohit:
    .byte 0     // 0: unused
    .byte 60    // 1: ATK_NORMAL
    .byte 0     // 2: unused
    .byte 10    // 3: ATK_CONFUSE
    .byte 10    // 4: ATK_FEAR
    .byte 0     // 5: unused
    .byte 0     // 6: ATK_ACID
    .byte 0     // 7: unused
    .byte 0     // 8: unused
    .byte 0     // 9: ATK_CORRODE
    .byte 0     // 10: unused
    .byte 2     // 11: ATK_PARALYZE
    .byte 0     // 12: unused
    .byte 0     // 13: unused
    .byte 5     // 14: ATK_POISON
    .byte 0     // 15: unused
    .byte 0     // 16: unused
    .byte 0     // 17: unused
    .byte 0     // 18: unused
    .byte 0     // 19: unused
    .byte 0     // 20: ATK_AGGRAVATE (always hits, no roll)

// ============================================================
// Scratch variables (static RAM, safe across subroutine calls)
// ============================================================
mat_slot2:        .byte 0   // Monster slot (from zp_mon_idx)
mat_type2:        .byte 0   // Creature type index
mat_atk_type:     .byte 0   // Current attack's type ID
mat_any_hit:      .byte 0   // Any attack connected this round
mat_total_dmg:    .byte 0   // Total damage accumulated this round

// Strings migrated to Huffman compression (HSTR_MAT_* in huffman_data.s)

// ============================================================
// Subroutines
// ============================================================

// monster_attack_player — Main entry point for monster melee
// Called from monster_try_step when monster is adjacent to player.
// Uses ZP $70-$7F (monster AI scratch) which is still valid.
// Clobbers: everything
monster_attack_player:
    jsr player_search_mode_off

    lda zp_mon_idx
    sta mat_slot2
    lda zp_mon_type
    sta mat_type2
    sta cmb_type                // For combat_append_monster_name reuse

    lda #0
    sta mat_any_hit
    sta mat_total_dmg

    // --- Attack slot 0 ---
    ldx mat_type2
    lda cr_atk0_type,x
    bne !map_has_atk0+
    jmp !map_done+              // ATK_NONE → no attacks
!map_has_atk0:
    sta mat_atk_type

    // Check for aggravation (always hits, no roll)
    cmp #ATK_AGGRAVATE
    bne !map_not_aggro+
    jmp !map_do_aggravate+
!map_not_aggro:

    jsr mon_atk_calc_tohit      // → zp_combat_tohit
    jsr mon_atk_roll_tohit      // carry set = hit
    bcc !map_slot1+             // miss → try slot 1

    // Roll damage for slot 0
    ldx mat_type2
    lda cr_atk0_dice,x
    sta zp_temp0
    lda cr_atk0_sides,x
    tax                         // X = sides
    lda zp_temp0                // A = dice count
    ldy #0                      // No bonus
    jsr math_dice               // → zp_math_a

    lda zp_math_a
    sta zp_combat_dmg

    // Apply effects and AC reduction based on attack type
    jsr mon_atk_effect_dispatch
    // zp_combat_dmg may be modified (AC reduction for normal)

    lda zp_combat_dmg
    beq !map_slot1+             // 0 damage after AC reduce → skip
    clc
    adc mat_total_dmg
    sta mat_total_dmg
    lda #1
    sta mat_any_hit

    // Apply damage to player
    jsr mon_atk_apply_damage
    bcs !map_player_dead+

!map_slot1:
    // --- Attack slot 1 ---
    ldx mat_type2
    lda cr_atk1_type,x
    beq !map_done+              // No second attack
    sta mat_atk_type

    jsr mon_atk_calc_tohit
    jsr mon_atk_roll_tohit
    bcc !map_done+              // miss

    // Roll damage for slot 1
    ldx mat_type2
    lda cr_atk1_dice,x
    sta zp_temp0
    lda cr_atk1_sides,x
    tax
    lda zp_temp0
    ldy #0
    jsr math_dice

    lda zp_math_a
    sta zp_combat_dmg

    jsr mon_atk_effect_dispatch

    lda zp_combat_dmg
    beq !map_done+
    clc
    adc mat_total_dmg
    sta mat_total_dmg
    lda #1
    sta mat_any_hit

    jsr mon_atk_apply_damage
    bcs !map_player_dead+

!map_done:
    // Track attack in recall
    ldx mat_type2
    inc recall_attacks,x

    // Build and print summary message
    lda mat_any_hit
    beq !map_miss_msg+

    // Hit message: "THE <name> HITS YOU."
    ldx #HSTR_MAT_HITS
    jsr huff_decode_to_ptr2
    jsr mon_atk_build_effect_msg
    lda #SFX_HIT
    jmp sound_play

!map_miss_msg:
    // Miss message: "THE <name> MISSES YOU."
    ldx #HSTR_MAT_MISS
    jsr huff_decode_to_ptr2
    jsr mon_atk_build_effect_msg
    lda #SFX_MISS
    jmp sound_play

!map_do_aggravate:
    jsr mon_atk_effect_aggravate
    // Print shriek message
    ldx #HSTR_MAT_SHRIEK
    jmp huff_print_msg

!map_player_dead:
    ldx mat_type2
    inc recall_deaths,x
    stx zp_death_source
    jmp player_death_check

// mon_atk_calc_tohit — Compute monster's hit chance
// hit_chance = base_to_hit[atk_type] + cr_level * 3
// Output: zp_combat_tohit
// Clobbers: A, X
mon_atk_calc_tohit:
    ldx mat_atk_type
    lda mon_atk_base_tohit,x    // Base to-hit for this attack type
    sta zp_combat_tohit

    // Add cr_level * 3
    ldx mat_type2
    lda cr_level,x              // creature level
    sta zp_temp0
    asl                         // *2
    clc
    adc zp_temp0                // *3
    clc
    adc zp_combat_tohit
    bcc !mact_no_cap+
    lda #255                    // Cap at 255
!mact_no_cap:
    sta zp_combat_tohit
    rts

// mon_atk_roll_tohit — d20 roll with natural 1/20 rules
// Input: zp_combat_tohit = hit chance
// Output: carry set = hit, carry clear = miss
// Clobbers: A, X, zp_temp3, zp_temp4
mon_atk_roll_tohit:
    // Roll d20 (1-20)
    lda #20
    jsr rng_range               // [0,19]
    clc
    adc #1                      // [1,20]

    // Natural 1 = always miss
    cmp #1
    beq !mart_miss+

    // Natural 20 = always hit
    cmp #20
    beq !mart_hit+

    // Normal: rng_range(hit_chance) >= player_AC → hit
    lda zp_combat_tohit
    cmp #2
    bcc !mart_miss+             // tohit too low
    jsr rng_range               // [0, tohit-1]
    cmp zp_player_ac            // >= AC?
    bcs !mart_hit+              // Greater or equal = hit

!mart_miss:
    clc
    rts
!mart_hit:
    sec
    rts

// mon_atk_apply_damage — Subtract damage from player HP
// Input: zp_combat_dmg = damage amount (already reduced)
// Output: carry set = player dead
// Clobbers: A
mon_atk_apply_damage:
    lda eff_invuln_timer
    beq !mad_apply+
    clc
    rts
!mad_apply:
    // 16-bit subtraction: player HP -= damage
    lda zp_player_hp_lo
    sec
    sbc zp_combat_dmg
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO

    lda zp_player_hp_hi
    sbc #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Check if dead: hi byte negative or both bytes zero
    bmi !mad_dead+

    // Check both bytes zero
    ora zp_player_hp_lo
    beq !mad_dead+

    clc                         // Alive
    rts
!mad_dead:
    sec                         // Dead
    rts

// mon_atk_ac_reduce — AC damage reduction for normal attacks
// damage -= (player_AC * damage) / 200
// Input: zp_combat_dmg = raw damage
// Output: zp_combat_dmg = reduced damage (min 0)
// Clobbers: A, X, Y, zp_math_a/b, zp_math_tmp0/1
mon_atk_ac_reduce:
    // Compute AC * damage
    lda zp_player_ac
    ldx zp_combat_dmg
    jsr math_multiply           // zp_math_a/b = AC * damage (16-bit)

    // Divide by 200
    ldx #200
    jsr math_div_16x8           // zp_math_a = quotient lo (reduction)

    // Subtract reduction from damage
    lda zp_combat_dmg
    sec
    sbc zp_math_a
    bcs !macr_ok+
    lda #0                      // Floor at 0
!macr_ok:
    sta zp_combat_dmg
    rts

// mon_atk_effect_dispatch — Route to type-specific handler
// Input: mat_atk_type, zp_combat_dmg = raw damage
// Output: zp_combat_dmg may be modified, effects applied
// Clobbers: A, X, Y, zp_math_*
mon_atk_effect_dispatch:
    lda mat_atk_type

    cmp #ATK_NORMAL
    beq !maed_normal+
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
    cmp #ATK_CORRODE
    beq !maed_corrode+
    // Unknown type — treat as normal
    jmp !maed_normal+

!maed_normal:
    jmp mon_atk_ac_reduce
!maed_poison:
    // Full dice damage, no AC reduction (matches umoria)
    jmp mon_atk_effect_poison
!maed_confuse:
    // Full dice damage, no AC reduction (matches umoria)
    // 50% chance of applying confusion effect
    lda #2
    jsr rng_range               // [0, 1]
    bne !maed_conf_done+        // 0 = apply, 1 = skip
    jsr mon_atk_effect_confuse
!maed_conf_done:
    rts
!maed_paralyze:
    // Full dice damage passes through (matches umoria), then apply effect
    jmp mon_atk_effect_paralyze
!maed_acid:
    // Acid: full damage, no AC reduction
    jmp mon_atk_effect_acid
!maed_fear:
    // Fear: full dice damage, no AC reduction (matches umoria)
    jmp mon_atk_effect_fear
!maed_corrode:
    // Corrode: full damage, no AC reduce. Equipment corrosion deferred.
    rts

// mon_atk_effect_poison — Set/stack poison timer (umoria stacking)
// Always adds rng_range(cr_level) + 5 to poison timer.
// Message only printed on first poisoning.
// Clobbers: A, X, zp_temp3, zp_temp4
mep_was_poisoned: .byte 0

mon_atk_effect_poison:
    lda zp_eff_poison
    sta mep_was_poisoned        // Save whether already poisoned

    // Compute addition: rng_range(cr_level) + 5
    ldx mat_type2
    lda cr_level,x
    cmp #1
    bne !mep_roll+
    // Level 1: 0 + 5 + 1 = 6
    lda #6
    jmp !mep_add+
!mep_roll:
    jsr rng_range               // [0, level-1]
    clc
    adc #5
!mep_add:
    // Add to existing poison timer
    clc
    adc zp_eff_poison
    bcc !mep_store+
    lda #255                    // Cap at 255
!mep_store:
    sta zp_eff_poison

    // Only print message if newly poisoned (wasn't before)
    lda mep_was_poisoned
    bne !mep_done+

    // Print "THE <name> POISONS YOU."
    ldx #HSTR_MAT_POISON
    jsr huff_decode_to_ptr2
    jsr mon_atk_build_effect_msg
!mep_done:
    rts

// mon_atk_effect_confuse — Set/stack confusion timer (umoria stacking)
// First: timer = rng_range(cr_level) + 3. Stacking: timer += 3.
// Clobbers: A, X, zp_temp3, zp_temp4
mon_atk_effect_confuse:
    lda zp_eff_confuse
    bne !mec_stack+

    // First confusion: rng_range(cr_level) + 3
    ldx mat_type2
    lda cr_level,x
    cmp #1
    bne !mec_roll+
    lda #4                      // Level 1: 0 + 3 + 1 = 4
    sta zp_eff_confuse
    jmp !mec_msg+
!mec_roll:
    jsr rng_range               // [0, level-1]
    clc
    adc #3
    sta zp_eff_confuse
!mec_msg:
    // Print "THE <name> CONFUSES YOU."
    ldx #HSTR_MAT_CONFUSE
    jsr huff_decode_to_ptr2
    jmp mon_atk_build_effect_msg

!mec_stack:
    // Already confused: add 3 turns (umoria stacking)
    lda zp_eff_confuse
    clc
    adc #3
    bcc !mec_stack_ok+
    lda #255                    // Cap at 255
!mec_stack_ok:
    sta zp_eff_confuse
    rts

// mon_atk_effect_paralyze — Saving throw, then set paralysis timer
// Saving throw: class_save_base + player_level
// Resist if rng_range(100) < saving
// Timer = rng_range(cr_level) + 1
// Clobbers: A, X, Y, zp_temp3, zp_temp4, zp_math_*
mon_atk_effect_paralyze:
    // Check free action flag
    lda zp_eff_free_act
    bne !mepa_resist+           // Free action blocks paralysis

    // Already paralyzed? No stacking
    lda zp_eff_paralyze
    bne !mepa_done+

    // Compute saving throw = class_save_base + player_level
    // class_save_base is class_properties offset 6
    lda player_data + PL_CLASS
    ldx #CLASS_PROP_SIZE
    jsr math_multiply           // zp_math_a = class * 10
    lda zp_math_a
    clc
    adc #6                      // Offset to save field
    tax
    lda class_properties,x      // save base
    clc
    adc zp_player_lvl           // + player level
    sta zp_temp0                // saving throw value

    // Roll: rng_range(100). Resist if roll < saving.
    lda #100
    jsr rng_range               // [0, 99]
    cmp zp_temp0
    bcc !mepa_resist+           // roll < saving → resist

    // Failed save — set paralysis timer (umoria: randomNumber(level) + 3)
    // rng_range(level) gives [0, level-1], + 4 gives [4, level+3]
    ldx mat_type2
    lda cr_level,x
    jsr rng_range               // [0, level-1]
    clc
    adc #4                      // [4, level+3] — matches umoria
    sta zp_eff_paralyze
!mepa_msg:
    // Print "THE <name> PARALYZES YOU."
    ldx #HSTR_MAT_PARALYZE
    jsr huff_decode_to_ptr2
    jsr mon_atk_build_effect_msg
!mepa_done:
    rts
!mepa_resist:
    rts

// mon_atk_effect_acid — Acid attack (no AC reduction, full damage)
// Damage already applied; print effect message.
mon_atk_effect_acid:
    ldx #HSTR_MAT_ACID
    jsr huff_decode_to_ptr2
    jmp mon_atk_build_effect_msg

// mon_atk_effect_fear — Set fear timer (blocks melee)
// Timer = rng_range(cr_level) + 3. Message only on first fear.
// Replace timer only if new value > current (no stacking, just extend).
// Clobbers: A, X, zp_temp3, zp_temp4
mon_atk_effect_fear:
    // Compute new timer: rng_range(cr_level) + 3
    ldx mat_type2
    lda cr_level,x
    cmp #1
    bne !mef_roll+
    lda #4                      // Level 1: 0 + 3 + 1 = 4
    jmp !mef_check+
!mef_roll:
    jsr rng_range               // [0, level-1]
    clc
    adc #3
!mef_check:
    // Only replace if new > current
    cmp eff_fear_timer
    bcc !mef_done+
    beq !mef_done+

    // Check if this is first fear (for message)
    pha                         // Save new timer
    lda eff_fear_timer
    bne !mef_no_msg+

    // Print "THE <name> FRIGHTENS YOU." (first fear only)
    ldx #HSTR_MAT_FEAR
    jsr huff_decode_to_ptr2
    jsr mon_atk_build_effect_msg
!mef_no_msg:
    pla                         // Restore new timer
    sta eff_fear_timer
!mef_done:
    rts

// mon_atk_effect_aggravate — Wake all sleeping monsters
// Clobbers: A, X, Y, zp_ptr0
mon_atk_effect_aggravate:
    ldx #0
!mea_loop:
    cpx #MAX_MONSTERS
    bcs !mea_done+

    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !mea_next+

    // Set MF_AWAKE
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_AWAKE
    sta (zp_ptr0),y

!mea_next:
    inx
    jmp !mea_loop-
!mea_done:
    rts

// player_death_check — Check if player is dead, set game flag
// Sets zp_game_flags bit 0 if HP <= 0
// Clobbers: A
player_death_check:
    // Check hi byte negative
    lda zp_player_hp_hi
    bmi !pdc_dead+

    // Check both bytes zero
    ora zp_player_hp_lo
    beq !pdc_dead+

    rts                         // Still alive

!pdc_dead:
    lda zp_game_flags
    ora #$01                    // Set GF_DEAD (bit 0)
    sta zp_game_flags
    lda #SFX_DEATH
    jmp sound_play

// ============================================================
// Message builders
// ============================================================

// mon_atk_build_effect_msg — "THE <name> <effect string>"
// Input: zp_ptr2 = effect string pointer (lo/hi)
mon_atk_build_effect_msg:
    lda #0
    sta cmb_buf_idx

    lda #<cmb_the_str + 1
    ldy #>cmb_the_str + 1
    jsr combat_append_str

    jsr combat_append_monster_name

    lda zp_ptr2
    ldy zp_ptr2_hi
    jsr combat_append_str

    jmp cmb_term_and_print

// ============================================================
// Compile-time validation
// ============================================================
.assert "ATK_NORMAL", ATK_NORMAL, 1
.assert "ATK_AGGRAVATE", ATK_AGGRAVATE, 20
