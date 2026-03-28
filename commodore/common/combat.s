#importonce
#import "numeric_format.s"
// combat.s — Player melee combat
//
// Bump-to-attack: to-hit rolls, damage, monster death, XP awards, level-up.
// Faithful to umoria formulas. Monsters don't attack back yet (Phase 5.4).

// ============================================================
// Scratch variables (static RAM, safe across subroutine calls)
// ============================================================
cmb_slot:        .byte 0        // Monster slot index
cmb_type:        .byte 0        // Creature type index
cmb_damage:      .byte 0        // Damage for current blow
cmb_dead:        .byte 0        // Monster died flag
cmb_any_hit:     .byte 0        // Any blow connected this round
cmb_buf_idx:     .byte 0        // Buffer write index for msg builder

// Message composition buffer (42 bytes for longest msg)
combat_msg_buf:  .fill 42, 0

// ============================================================
// Combat strings (screen codes via inherited encoding)
// ============================================================
cmb_you_str:     .text "You " ; .byte 0
cmb_the_str:     .text " the " ; .byte 0
cmb_hit_str:     .text "hit" ; .byte 0
cmb_miss_str:    .text "miss" ; .byte 0
cmb_kill_str:    .text "have slain" ; .byte 0
// cmb_lvlup_str migrated to Huffman (HSTR_CMB_LVLUP)
cmb_period:      .byte $2e, 0   // "."

// ============================================================
// Subroutines
// ============================================================

// player_attack_monster — Entry point for melee attack
// Input:  A = target_x, Y = target_y
// Output: always returns with carry SET (turn consumed)
// Clobbers: everything
player_attack_monster:
    pha
    jsr player_search_mode_off
    pla

    // Find the monster at this position
    jsr monster_find_at         // A=x, Y=y → carry set, X=slot
    bcs !pam_found+
    // No monster found (shouldn't happen, but be safe)
    sec
    rts

!pam_found:
    // Save slot index and load creature type
    stx cmb_slot
    jsr monster_get_ptr         // zp_ptr0 = entry
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type

    // Wake the monster and mark provoked (town creatures need this to fight back)
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_AWAKE | MF_PROVOKED
    sta (zp_ptr0),y

    // Calculate to-hit chance and number of blows
    jsr combat_calc_tohit       // → zp_combat_tohit
    jsr combat_calc_blows       // → zp_combat_blows

    lda #0
    sta cmb_dead
    sta cmb_any_hit

    // Load monster AC for all rolls
    ldx cmb_type
    lda cr_ac,x
    sta zp_combat_atk           // AC storage for combat_roll_tohit

    // --- Blow loop (silent — no messages until end) ---
!pam_blow_loop:
    lda cmb_dead
    bne !pam_summary+
    lda zp_combat_blows
    beq !pam_summary+

    jsr combat_roll_tohit       // carry set = hit
    bcc !pam_next_blow+         // Miss — continue to next blow

    // --- Hit ---
    lda #1
    sta cmb_any_hit

    // Check confuse-on-hit from Monster Confusion scroll
    lda zp_confuse_melee
    beq !pam_no_confuse+
    lda #0
    sta zp_confuse_melee            // Clear — one-time use
    // Set monster's confusion timer
    ldy #MX_CONFUSE
    lda #20                         // 20 turns confused
    sta (zp_ptr0),y
!pam_no_confuse:

    jsr combat_roll_damage      // → cmb_damage
    jsr combat_critical_blow    // May multiply cmb_damage (weapon hits only)

    // Apply damage to monster
    ldx cmb_slot
    lda cmb_damage
    jsr combat_apply_damage     // carry set = dead
    bcc !pam_next_blow+

    // Monster killed
    lda #1
    sta cmb_dead

    // Track kill in recall
    ldx cmb_type
    inc recall_kills,x

    ldx cmb_slot
    jsr monster_remove

!pam_next_blow:
    dec zp_combat_blows
    jmp !pam_blow_loop-

    // --- Print one summary message for the round ---
!pam_summary:
    lda cmb_dead
    beq !pam_not_dead+

    // Killed: "You have slain the <name>."
    lda #<cmb_kill_str
    ldy #>cmb_kill_str
    jsr msg_build_action
    jsr cmb_print_buf

    jsr combat_award_xp
    jsr combat_check_levelup

    lda #SFX_HIT
    jsr sound_play
    jmp !pam_done+

!pam_not_dead:
    lda cmb_any_hit
    beq !pam_all_miss+

    // Hit but alive: "You hit the <name>."
    lda #<cmb_hit_str
    ldy #>cmb_hit_str
    jsr msg_build_action
    jsr cmb_print_buf

    lda #SFX_HIT
    jsr sound_play
    jmp !pam_done+

!pam_all_miss:
    // All blows missed: "You miss the <name>."
    lda #<cmb_miss_str
    ldy #>cmb_miss_str
    jsr msg_build_action
    jsr cmb_print_buf

    lda #SFX_MISS
    jsr sound_play

!pam_done:
    sec                         // Turn consumed
    rts

cct_bth_offset: .byte 0
cct_lvl_offset: .byte 0

// combat_calc_tohit — Compute melee hit chance (entry point)
// Output: zp_combat_tohit = hit chance (capped at 255)
// Clobbers: A, X, Y, zp_math_a/b, zp_temp0
combat_calc_tohit:
    lda #3                          // Melee BTH offset in class_properties
    ldx #0                          // Melee level adj offset

// combat_calc_tohit_common — Shared hit chance calculation
// Input: A = class property offset (3=melee BTH, 4=bow BTH_BOW)
//        X = level adj offset (0=melee BTH/lvl, 1=bow BTH_BOW/lvl)
// Output: zp_combat_tohit = hit chance (capped at 255)
// Clobbers: A, X, Y, zp_math_a/b, zp_temp0
combat_calc_tohit_common:
    sta cct_bth_offset
    stx cct_lvl_offset

    // Get class BTH/BTH_BOW
    lda player_data + PL_CLASS
    ldx #CLASS_PROP_SIZE
    jsr math_multiply           // A = class * 10
    clc
    adc cct_bth_offset          // 3=melee, 4=bow
    tax
    lda class_properties,x
    sta zp_combat_tohit         // Start with base BTH

    // Add race BTH (race_properties offset 7, signed byte)
    lda player_data + PL_RACE
    ldx #RACE_PROP_SIZE
    jsr math_multiply           // A = race * RACE_PROP_SIZE
    clc
    adc #7                      // Offset to BTH field
    tax
    lda race_properties,x       // Race BTH (signed)
    bmi !cct_race_neg+
    clc
    adc zp_combat_tohit
    bcc !cct_race_done+
    lda #255
    bne !cct_race_done+
!cct_race_neg:
    eor #$ff
    clc
    adc #1                      // abs(race BTH)
    sta zp_temp0
    lda zp_combat_tohit
    sec
    sbc zp_temp0
    bcs !cct_race_done+
    lda #0                      // Floor at 0
!cct_race_done:
    sta zp_combat_tohit

    // Add PL_TOHIT * 3
    lda player_data + PL_TOHIT
    // Check sign — PL_TOHIT can be negative (signed)
    bmi !cct_neg_tohit+

    // Positive: if PL_TOHIT >= 86, then PL_TOHIT * 3 already exceeds 255.
    cmp #86
    bcs !cct_pos_sat+
    sta zp_temp0
    asl                         // *2; carry stays clear for values < 86
    adc zp_temp0                // *3
    adc zp_combat_tohit
    bcc !cct_tohit_ok+
!cct_pos_sat:
    lda #255                    // Cap at 255
    bne !cct_tohit_ok+

!cct_neg_tohit:
    // Negative to-hit: if abs(PL_TOHIT) >= 86, subtracting *3 always floors to 0.
    eor #$ff
    clc
    adc #1                      // abs(PL_TOHIT)
    cmp #86
    bcs !cct_neg_floor+
    sta zp_temp0
    asl                         // *2; carry stays clear for values < 86
    adc zp_temp0                // *3 (positive value)
    sta zp_temp0
    // Subtract from tohit
    lda zp_combat_tohit
    sec
    sbc zp_temp0
    bcs !cct_tohit_ok+
!cct_neg_floor:
    lda #0                      // Floor at 0

!cct_tohit_ok:
    sta zp_combat_tohit

    // Add player_level * class level adj
    lda player_data + PL_CLASS
    ldx #CLASS_LVL_SIZE
    jsr math_multiply           // A = class * 5
    clc
    adc cct_lvl_offset          // 0=melee BTH/lvl, 1=bow BTH_BOW/lvl
    tax
    lda class_level_adj,x       // BTH per level
    ldx zp_player_lvl
    jsr math_multiply           // zp_math_a = level * bth_per_level
    lda zp_math_a
    clc
    adc zp_combat_tohit
    bcc !cct_done+
    lda #255                    // Cap at 255
!cct_done:
    sta zp_combat_tohit
    rts

// combat_calc_blows — Calculate number of blows per round
// Uses STR-adjusted weapon weight: adj_weight = (STR * 10) / weapon_weight
// Then indexes blows_table[adj_weight_bracket][dex_bracket].
// Too-heavy check: if STR * 15 < weapon_weight, force 1 blow.
// Unarmed = weight class 4 (lightest).
// Output: zp_combat_blows
// Clobbers: A, X, Y, zp_math_a/b
combat_calc_blows:
    // DEX bracket: <10→0, 10-14→1, 15-17→2, 18+→3
    lda player_data + PL_DEX_CUR
    cmp #18
    bcs !ccb_dex3+
    cmp #15
    bcs !ccb_dex2+
    cmp #10
    bcs !ccb_dex1+
    // DEX < 10
    ldx #0
    jmp !ccb_weight+
!ccb_dex1:
    ldx #1
    jmp !ccb_weight+
!ccb_dex2:
    ldx #2
    jmp !ccb_weight+
!ccb_dex3:
    ldx #3
!ccb_weight:
    // X = dex bracket (0-3). Save it.
    stx zp_temp0

    // Check for weapon
    ldy #EQUIP_WEAPON
    lda inv_item_id,y
    cmp #FI_EMPTY
    beq !ccb_unarmed+

    // Get weapon weight
    tay                         // Y = weapon type
    lda it_weight,y             // A = weapon weight (1/10 lbs)
    beq !ccb_unarmed+          // Zero weight → treat as unarmed
    sta ccb_wt_save             // Save weapon weight

    // Too-heavy check: if STR * 15 < weapon_weight, force 1 blow
    // Compute STR * 15 = STR * 16 - STR (fits in 16-bit for stats up to 118)
    lda player_data + PL_STR_CUR
    ldx #15
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi
    // Compare 16-bit (zp_math_b:zp_math_a) vs weapon_weight (8-bit, zero-extended)
    lda zp_math_b
    bne !ccb_not_heavy+         // Hi > 0 → STR*15 >= 256 > any weapon weight
    lda zp_math_a
    cmp ccb_wt_save
    bcs !ccb_not_heavy+         // STR*15 >= weapon_weight → ok
    // Too heavy: force 1 blow
    lda #1
    sta zp_combat_blows
    rts

!ccb_not_heavy:
    // Compute adj_weight = (STR * 10) / weapon_weight
    lda player_data + PL_STR_CUR
    ldx #10
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi (STR*10)
    ldx ccb_wt_save             // X = weapon weight (divisor)
    jsr math_div_16x8           // zp_math_a = quotient lo (adj_weight)

    // Map adj_weight to bracket (0-4)
    // adj_weight < 3 → 0, 3-4 → 1, 5-7 → 2, 8-12 → 3, >= 13 → 4
    lda zp_math_a
    cmp #13
    bcs !ccb_br4+
    cmp #8
    bcs !ccb_br3+
    cmp #5
    bcs !ccb_br2+
    cmp #3
    bcs !ccb_br1+
    lda #0
    beq !ccb_lookup+
!ccb_br1:
    lda #1
    bne !ccb_lookup+
!ccb_br2:
    lda #2
    bne !ccb_lookup+
!ccb_br3:
    lda #3
    bne !ccb_lookup+
!ccb_br4:
    lda #4
    bne !ccb_lookup+
!ccb_unarmed:
    lda #4                      // Weight class 4 (lightest)
!ccb_lookup:
    // A = weight class (row), zp_temp0 = dex bracket (col)
    // Offset = weight_class * 4 + dex_bracket
    asl
    asl                         // * 4
    clc
    adc zp_temp0
    tax
    lda blows_table,x
    sta zp_combat_blows
    rts

// Scratch for combat_calc_blows
ccb_wt_save: .byte 0           // Saved weapon weight

// combat_roll_tohit — Roll d20 to determine if attack hits
// Input:  zp_combat_tohit = hit chance
//         zp_combat_atk = monster AC
// Output: carry set = hit, carry clear = miss
// Clobbers: A, X, zp_temp3, zp_temp4
combat_roll_tohit:
    // Roll d20 (1-20)
    lda #20
    jsr rng_range               // [0,19]
    clc
    adc #1                      // [1,20]

    // Natural 1 = always miss
    cmp #1
    beq !crt_miss+

    // Natural 20 = always hit
    cmp #20
    beq !crt_hit+

    // Normal roll: rng_range(hit_chance) >= monster_ac → hit
    lda zp_combat_tohit
    cmp #2                      // Need at least 2 to have a valid range
    bcc !crt_miss+              // tohit too low
    jsr rng_range               // [0, tohit-1]
    cmp zp_combat_atk           // >= AC?
    bcs !crt_hit+

!crt_miss:
    clc
    rts
!crt_hit:
    sec
    rts

// combat_roll_damage — Roll weapon or unarmed damage
// If weapon equipped: it_dmg_dice[type] d it_dmg_sides[type] + PL_TODMG
// If unarmed: 1d2 + PL_TODMG
// Output: cmb_damage = damage amount (min 0)
// Clobbers: A, X, Y, zp_math_a/b, zp_temp3, zp_temp4
combat_roll_damage:
    // Check for equipped weapon
    ldx #EQUIP_WEAPON
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !crd_unarmed+

    // Check if weapon is a ranged launcher (it_missile 1-3) — use unarmed for melee
    tax                         // X = weapon type
    jsr item_get_missile
    beq !crd_has_melee+         // 0 = normal melee weapon
    cmp #4
    bcc !crd_unarmed+           // 1-3 = ranged launcher → unarmed in melee
!crd_has_melee:

    // Weapon equipped — use weapon dice
    lda it_dmg_dice,x           // Dice count
    pha                         // Save dice count
    lda it_dmg_sides,x          // Dice sides
    tax                         // X = sides
    pla                         // A = dice count
    ldy #0                      // No bonus on dice roll itself
    jsr math_dice               // Result in zp_math_a
    jmp !crd_add_bonus+

!crd_unarmed:
    // Roll 1d2
    lda #1
    ldx #2
    ldy #0
    jsr math_dice               // result in zp_math_a (1 or 2)

!crd_add_bonus:
    // Add PL_TODMG (signed)
    lda player_data + PL_TODMG
    bmi !crd_neg+
    // Positive bonus
    clc
    adc zp_math_a
    jmp !crd_ego+

!crd_neg:
    // Negative bonus — clamp to min 0
    clc
    adc zp_math_a               // Signed add (may underflow)
    bpl !crd_ego+
    lda #0                      // Clamp to 0

!crd_ego:
    sta cmb_damage

    // --- Ego damage modifiers (banked at $F000) ---
    ldx #EQUIP_WEAPON
    lda inv_ego,x
    beq !crd_ego_done+
    jsr tramp_ego_apply_damage  // Reads/writes cmb_damage, cmb_type

!crd_ego_done:
    rts

// combat_critical_blow — Chance for weapon hits to deal 2-5x damage
// Based on umoria playerWeaponCriticalBlow.
// Trigger: randint(5000) <= (weapon_weight + 5*tohit + class_bth_per_level * level)
// Damage tiers by (weight + randint(650)):
//   < 400: 2x + 5, 400-699: 3x + 10, 700-899: 4x + 15, >= 900: 5x + 20
// Input/Output: cmb_damage modified in place
// Clobbers: A, X, Y, zp_temp0-3, zp_math_a/b
combat_critical_blow:
    // Guard: no weapon = no crit
    ldy #EQUIP_WEAPON
    lda inv_item_id,y
    cmp #FI_EMPTY
    bne !ccb_armed+
    rts
!ccb_armed:

    // Guard: ranged launcher = no crit (melee only)
    tax
    jsr item_get_missile
    beq !ccb_has_weapon+
    cmp #4
    bcs !ccb_has_weapon+
    rts                         // 1-3 = ranged launcher
!ccb_has_weapon:

    // Save weapon weight (8-bit, will zero-extend to 16 later)
    lda it_weight,x
    sta ccb_weight

    // --- Compute 16-bit chance ---
    // Start with weight (zero-extended to 16)
    lda ccb_weight
    sta ccb_chance_lo
    lda #0
    sta ccb_chance_hi

    // Add 5 * zp_combat_tohit
    lda zp_combat_tohit
    ldx #5
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi
    lda ccb_chance_lo
    clc
    adc zp_math_a
    sta ccb_chance_lo
    lda ccb_chance_hi
    adc zp_math_b
    sta ccb_chance_hi

    // Add class_level_adj[class*5+0] * player_level
    lda player_data + PL_CLASS
    ldx #CLASS_LVL_SIZE
    jsr math_multiply           // A = class * 5
    tax
    lda class_level_adj,x       // BTH per level
    ldx zp_player_lvl
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi
    lda ccb_chance_lo
    clc
    adc zp_math_a
    sta ccb_chance_lo
    lda ccb_chance_hi
    adc zp_math_b
    sta ccb_chance_hi

    // Roll rng_range_word(5000) — result in zp_temp2/3
    lda #<5000
    sta zp_temp0
    lda #>5000
    sta zp_temp1
    jsr rng_range_word          // Result: zp_temp2 (lo), zp_temp3 (hi)

    // Compare: if random >= chance, no crit (return)
    // 16-bit compare: zp_temp3:zp_temp2 vs ccb_chance_hi:ccb_chance_lo
    lda zp_temp3
    cmp ccb_chance_hi
    bcc !ccb_crit+              // random_hi < chance_hi → crit
    bne !ccb_no_crit+           // random_hi > chance_hi → no crit
    lda zp_temp2
    cmp ccb_chance_lo
    bcc !ccb_crit+              // random_lo < chance_lo → crit
!ccb_no_crit:
    rts

!ccb_crit:
    // --- Determine damage tier ---
    // tier_weight = weapon_weight + rng_range_word(650)
    lda #<650
    sta zp_temp0
    lda #>650
    sta zp_temp1
    jsr rng_range_word          // Result: zp_temp2 (lo), zp_temp3 (hi)

    // Add weapon weight to random roll (16-bit)
    lda zp_temp2
    clc
    adc ccb_weight
    sta zp_temp2
    lda zp_temp3
    adc #0
    sta zp_temp3                // zp_temp3:zp_temp2 = tier_weight

    // Save original damage for multiplication
    lda cmb_damage
    sta ccb_orig_dmg

    // Compare tier_weight against thresholds (16-bit)
    // >= 900 → 5x+20
    lda zp_temp3
    cmp #>900
    bcc !ccb_below_900+
    bne !ccb_tier5+
    lda zp_temp2
    cmp #<900
    bcs !ccb_tier5+
!ccb_below_900:
    // >= 700 → 4x+15
    lda zp_temp3
    cmp #>700
    bcc !ccb_below_700+
    bne !ccb_tier4+
    lda zp_temp2
    cmp #<700
    bcs !ccb_tier4+
!ccb_below_700:
    // >= 400 → 3x+10
    lda zp_temp3
    cmp #>400
    bcc !ccb_tier2+
    bne !ccb_tier3+
    lda zp_temp2
    cmp #<400
    bcs !ccb_tier3+

!ccb_tier2:
    // 2x + 5
    lda ccb_orig_dmg
    asl                         // * 2
    bcs !ccb_clamp+             // Overflow → 255
    clc
    adc #5
    bcs !ccb_clamp+
    sta cmb_damage
    rts

!ccb_tier3:
    // 3x + 10: orig + orig*2
    lda ccb_orig_dmg
    asl                         // * 2
    bcs !ccb_clamp+
    clc
    adc ccb_orig_dmg            // * 3
    bcs !ccb_clamp+
    clc
    adc #10
    bcs !ccb_clamp+
    sta cmb_damage
    rts

!ccb_tier4:
    // 4x + 15
    lda ccb_orig_dmg
    asl                         // * 2
    bcs !ccb_clamp+
    asl                         // * 4
    bcs !ccb_clamp+
    clc
    adc #15
    bcs !ccb_clamp+
    sta cmb_damage
    rts

!ccb_tier5:
    // 5x + 20: orig*4 + orig
    lda ccb_orig_dmg
    asl                         // * 2
    bcs !ccb_clamp+
    asl                         // * 4
    bcs !ccb_clamp+
    clc
    adc ccb_orig_dmg            // * 5
    bcs !ccb_clamp+
    clc
    adc #20
    bcs !ccb_clamp+
    sta cmb_damage
    rts

!ccb_clamp:
    lda #255
    sta cmb_damage
    rts

// Static vars for combat_critical_blow
ccb_weight:     .byte 0
ccb_chance_lo:  .byte 0
ccb_chance_hi:  .byte 0
ccb_orig_dmg:   .byte 0

// combat_apply_damage — Subtract 8-bit damage from monster HP
// Input:  X = monster slot index, A = damage amount (8-bit)
// Output: carry set = monster dead (HP <= 0)
//         carry clear = monster still alive
// Preserves: X
// Clobbers: A, Y, zp_ptr0, zp_math_a, zp_math_b
combat_apply_damage:
    sta zp_math_a               // Damage lo = A
    lda #0
    sta zp_math_b               // Damage hi = 0
    // Fall through to 16-bit version

// combat_apply_damage_16 — Subtract 16-bit damage from monster HP
// Input:  X = monster slot index, zp_math_a = damage lo, zp_math_b = damage hi
// Output: carry set = monster dead (HP <= 0)
//         carry clear = monster still alive
// Preserves: X
// Clobbers: A, Y, zp_ptr0
combat_apply_damage_16:
    jsr monster_get_ptr         // zp_ptr0 = entry

    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sec
    sbc zp_math_a
    sta (zp_ptr0),y

    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sbc zp_math_b
    sta (zp_ptr0),y

    // Check if dead: hi byte negative (bit 7 set) OR both bytes zero
    bmi !cad_dead+

    ldy #MX_HP_LO
    lda (zp_ptr0),y
    ldy #MX_HP_HI
    ora (zp_ptr0),y
    beq !cad_dead+

    clc                         // Alive
    rts

!cad_dead:
    sec                         // Dead
    rts

// combat_award_xp — Award XP for killing a monster
// Formula: xp_earned = (cr_xp * cr_level) / player_level
// cr_xp is 16-bit (cr_xp_hi:cr_xp_lo). Uses 16×8→24-bit multiply.
// Adds to 24-bit PL_XP_0/1/2.
// Clobbers: A, X, Y, zp_math_a/b, zp_temp0-4
combat_award_xp:
    // Load creature XP (16-bit) and level
    ldx cmb_type
    lda cr_xp_lo,x
    sta zp_temp0
    lda cr_xp_hi,x
    sta zp_temp1
    lda cr_level,x
    tax
    jsr math_mul_16x8
    lda mul_result_0
    sta ccl_adj_0
    lda mul_result_1
    sta ccl_adj_1
    lda mul_result_2
    sta ccl_adj_2

    // Divide 24-bit product by player_level
    lda zp_player_lvl
    bne !cax_div+
    lda #1                      // Safety: prevent div by 0
!cax_div:
    sta ccl_divisor
    jsr ccl_div_24x8

    // Integer-only XP — no min-1 floor (matches umoria behavior).
    // Weak creatures may award 0 XP when player_level >> creature_level.

    // Add 24-bit quotient to PL_XP
    lda player_data + PL_XP_0
    clc
    adc ccl_adj_0
    sta player_data + PL_XP_0

    lda player_data + PL_XP_1
    adc ccl_adj_1
    sta player_data + PL_XP_1

    lda player_data + PL_XP_2
    adc ccl_adj_2
    sta player_data + PL_XP_2

    lda zp_temp4
    beq cax_frac_done
    lda #0
    sta ccl_adj_0
    sta ccl_adj_1
    lda zp_temp4
    sta ccl_adj_2
    lda zp_player_lvl
    bne !cax_frac_div+
    lda #1
!cax_frac_div:
    sta ccl_divisor
    jsr ccl_div_24x8

    lda player_data + PL_XP_FRAC_LO
    clc
    adc ccl_adj_0
    sta player_data + PL_XP_FRAC_LO
    lda player_data + PL_XP_FRAC_HI
    adc ccl_adj_1
    sta player_data + PL_XP_FRAC_HI
    bcc cax_frac_done
    inc player_data + PL_XP_0
    bne cax_frac_done
    inc player_data + PL_XP_1
    bne cax_frac_done
    inc player_data + PL_XP_2
cax_frac_done:
    rts

// combat_compute_level_threshold — Compute adjusted threshold for current level
// Output: ccl_adj_0/1/2 = 24-bit adjusted threshold
// Clobbers: A, X, Y, zp_math_a/b, zp_temp0-4
combat_compute_level_threshold:
    lda zp_player_lvl
    cmp #29
    bcs !ccl_late+

    sec
    sbc #1                      // Index = level - 1
    tax
    lda xp_level_lo,x
    sta zp_temp0
    lda xp_level_hi,x
    sta zp_temp1
    ldx player_data + PL_EXPFACT
    jsr math_mul_16x8
    lda mul_result_0
    sta ccl_adj_0
    lda mul_result_1
    sta ccl_adj_1
    lda mul_result_2
    sta ccl_adj_2
    lda #100
    sta ccl_divisor
    jsr ccl_div_24x8
    rts

!ccl_late:
    sec
    sbc #29                     // Levels 29-39 use threshold/100 tables
    tax
    lda xp_level_late_div100_lo,x
    sta zp_temp0
    lda xp_level_late_div100_hi,x
    sta zp_temp1
    ldx player_data + PL_EXPFACT
    jsr math_mul_16x8
    lda mul_result_0
    sta ccl_adj_0
    lda mul_result_1
    sta ccl_adj_1
    lda mul_result_2
    sta ccl_adj_2
    rts

// combat_check_levelup — Check if XP exceeds adjusted level threshold
// Adjusted threshold = base_threshold * PL_EXPFACT / 100
// Compares 24-bit PL_XP against adjusted threshold and mirrors Umoria's
// repeated level-gain loop with excess halving after each gain.
// Clobbers: A, X, Y, zp_math_a/b, zp_temp0-4
combat_check_levelup:
!ccl_loop:
    lda zp_player_lvl
    cmp #40
    bcc !ccl_can_gain+
    jmp ccl_no
!ccl_can_gain:

    jsr combat_compute_level_threshold

    // Compare 24-bit: PL_XP >= adjusted threshold?
    lda player_data + PL_XP_2
    cmp ccl_adj_2
    bcc ccl_no_short            // XP_hi < threshold_hi → no
    bne !ccl_yes+               // XP_hi > threshold_hi → yes
    lda player_data + PL_XP_1
    cmp ccl_adj_1
    bcc ccl_no_short            // XP_mid < threshold_mid → no
    bne !ccl_yes+               // XP_mid > threshold_mid → yes
    lda player_data + PL_XP_0
    cmp ccl_adj_0
    bcc ccl_no_short           // XP_lo < threshold_lo → no
    jmp !ccl_yes+

ccl_no_short:
    jmp ccl_no

!ccl_yes:
    jsr combat_apply_levelup

    // Halve excess XP above new threshold (umoria behavior).
    // Prevents a single big kill from cascading through many levels.
    // Operates on full XP total (24-bit whole + 16-bit fraction).
    lda player_data + PL_XP_0
    sec
    sbc ccl_adj_0
    sta zp_temp0                    // excess_lo
    lda player_data + PL_XP_1
    sbc ccl_adj_1
    sta zp_temp1                    // excess_mid
    lda player_data + PL_XP_2
    sbc ccl_adj_2
    sta zp_temp2                    // excess_hi
    lda player_data + PL_XP_FRAC_LO
    sta zp_temp3                    // excess fraction lo
    lda player_data + PL_XP_FRAC_HI
    sta zp_temp4                    // excess fraction hi
    lda zp_temp2
    lsr
    sta zp_temp2
    lda zp_temp1
    ror
    sta zp_temp1
    lda zp_temp0
    ror
    sta zp_temp0
    lda zp_temp4
    ror
    sta zp_temp4
    lda zp_temp3
    ror
    sta zp_temp3
    lda zp_temp0                   // new XP = threshold + halved excess
    clc
    adc ccl_adj_0
    sta player_data + PL_XP_0
    lda zp_temp1
    adc ccl_adj_1
    sta player_data + PL_XP_1
    lda zp_temp2
    adc ccl_adj_2
    sta player_data + PL_XP_2
    lda zp_temp3
    sta player_data + PL_XP_FRAC_LO
    lda zp_temp4
    sta player_data + PL_XP_FRAC_HI

    jmp !ccl_loop-

ccl_no:
    rts

// combat_apply_levelup — Apply one real level-up event
// Shared by normal XP gain and Wizard Mode. Performs the actual level
// increment, HP/mana/combat recompute, spell learning, sound, and message.
combat_apply_levelup:
    // Level up!
    inc zp_player_lvl
    lda zp_player_lvl
    sta player_data + PL_LEVEL

    // Recalculate HP
    jsr player_calc_hp

    // Heal to full
    lda player_data + PL_MHP_LO
    sta player_data + PL_HP_LO
    sta zp_player_hp_lo
    lda player_data + PL_MHP_HI
    sta player_data + PL_HP_HI
    sta zp_player_hp_hi

    // Sync max HP to ZP
    lda player_data + PL_MHP_LO
    sta zp_player_mhp_lo
    lda player_data + PL_MHP_HI
    sta zp_player_mhp_hi

    // Recalculate combat bonuses (may change with level)
    jsr player_calc_combat

    // Recalculate mana and learn new spells
 #if C128
    jsr tramp_magic_recalc_mana
#else
    jsr magic_recalc_mana
#endif
#if C128
    jsr tramp_magic_check_new_spells
#else
    jsr magic_check_new_spells
#endif

    // Play level-up sound
    lda #SFX_LEVELUP
    jsr sound_play

    // Print level-up message: "Welcome to level N."
    jsr msg_build_levelup
    jsr cmb_print_buf
    rts

// Scratch for 24-bit threshold computation
ccl_adj_0: .byte 0             // 24-bit product / result (lo)
ccl_adj_1: .byte 0             // (mid)
ccl_adj_2: .byte 0             // (hi)
ccl_divisor: .byte 0           // Divisor for ccl_div_24x8
// ccl_div_24x8 — Divide ccl_adj_0/1/2 by ccl_divisor
// Uses shift-subtract algorithm (24 iterations)
// Input: ccl_divisor = divisor
// Result: quotient overwrites ccl_adj_0/1/2
// Clobbers: A, X
ccl_div_24x8:
    lda #0
    sta zp_temp4                // Remainder
    ldx #24                     // 24 bits
!cd24_loop:
    asl ccl_adj_0               // Shift dividend left
    rol ccl_adj_1
    rol ccl_adj_2
    rol zp_temp4                // MSB into remainder
    lda zp_temp4
    cmp ccl_divisor             // Try subtract divisor
    bcc !cd24_skip+
    sbc ccl_divisor
    sta zp_temp4
    inc ccl_adj_0               // Set quotient bit
!cd24_skip:
    dex
    bne !cd24_loop-
    rts

// ============================================================
// Message builders — compose strings in combat_msg_buf
// ============================================================

// msg_build_action — "You <action> the <name>."
// Input: A = action string ptr lo, Y = action string ptr hi
// Clobbers: A, X, Y, zp_ptr1
msg_build_action:
    sta mba_action_lo
    sty mba_action_hi
    lda #0
    sta cmb_buf_idx

    lda #<cmb_you_str
    ldy #>cmb_you_str
    jsr combat_append_str       // "You "

    lda mba_action_lo
    ldy mba_action_hi
    jsr combat_append_str       // action verb

    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str       // " the "

    jsr combat_append_monster_name

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str       // "."

    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x
    rts
mba_action_lo: .byte 0
mba_action_hi: .byte 0

// combat_kill_message — Kill monster, print "You have slain the <name>.", play SFX
// Input: X = monster slot index
// Calls eff_kill_monster (awards XP, removes monster), builds and prints
// the kill message, plays SFX_HIT.
// Clobbers: A, X, Y, zp_ptr0/hi, zp_ptr1/hi, zp_math_a/b, zp_temp0-4
combat_kill_message:
    jsr eff_kill_monster
    lda #<cmb_kill_str
    ldy #>cmb_kill_str
    jsr msg_build_action
    jsr cmb_print_buf
    lda #SFX_HIT
    jmp sound_play

// cmb_term_and_print — Null-terminate combat_msg_buf and print it
// Clobbers: A, X
cmb_term_and_print:
    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x
// cmb_print_buf — Print combat_msg_buf via msg_print
// Clobbers: A
cmb_print_buf:
    lda #<combat_msg_buf
    sta zp_ptr0
    lda #>combat_msg_buf
    sta zp_ptr0_hi
    jmp msg_print

// projectile_msg_suffix — Append " VERB THE <name>." and print
// Input: X = HSTR ID for verb string (e.g., HSTR_RF_HITS, HSTR_RF_MISSES)
//        combat_msg_buf already contains prefix text (e.g., "THE ARROW")
//        cmb_slot = target monster slot
// Appends decoded HSTR + " THE <name>." to combat_msg_buf, then prints.
// Clobbers: A, X, Y, zp_ptr0/hi, zp_ptr1/hi
projectile_msg_suffix:
    jsr huff_append_combat
    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str
    jsr combat_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jmp cmb_term_and_print

// msg_build_levelup — "Welcome to level N."
msg_build_levelup:
    lda #0
    sta cmb_buf_idx

    ldx #HSTR_CMB_LVLUP
    jsr huff_append_combat

    lda zp_player_lvl
    jsr combat_append_decimal

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x
    rts

// combat_append_str — Append null-terminated string to combat_msg_buf
// Input: A = string ptr lo, Y = string ptr hi
// Clobbers: A, X, Y, zp_ptr1
combat_append_str:
    sta zp_ptr1
    sty zp_ptr1_hi
    ldx cmb_buf_idx
    ldy #0
!cas_loop:
    lda (zp_ptr1),y
    beq !cas_done+
    sta combat_msg_buf,x
    inx
    iny
    cpx #41                     // Buffer overflow protection
    bcs !cas_done+
    jmp !cas_loop-
!cas_done:
    stx cmb_buf_idx
    rts

// combat_append_monster_name — Append current monster's name to buffer
// Uses cmb_type to look up cr_name_lo/hi
// Clobbers: A, X, Y, zp_ptr1
combat_append_monster_name:
    ldx cmb_type
    jsr creature_get_name       // A=lo, Y=hi (handles KERNAL banking)
    jsr combat_append_str
    rts

// combat_append_decimal — Append 8-bit decimal number to buffer
// Input: A = value (0-255)
// Clobbers: A, X
combat_append_decimal:
    jsr numeric_format_u8
    jmp combat_append_digits

// combat_append_decimal_16 — Append 16-bit decimal number to buffer
// Input: zp_temp0 = lo, zp_temp1 = hi
// Clobbers: A, X, Y, zp_temp0-3
combat_append_decimal_16:
    jsr numeric_format_u16
    // Fall through to the shared buffer emitter.
combat_append_digits:
    ldx cmb_buf_idx
    ldy #0
!cad_emit:
    lda nf_digit_buf,y
    sta combat_msg_buf,x
    inx
    iny
    cpy zp_temp2
    bne !cad_emit-
    stx cmb_buf_idx
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "combat_msg_buf size", cmb_you_str - combat_msg_buf, 42
