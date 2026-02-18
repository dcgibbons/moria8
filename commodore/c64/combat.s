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
cmb_you_str:     .text "YOU " ; .byte 0
cmb_the_str:     .text " THE " ; .byte 0
cmb_hit_str:     .text "HIT" ; .byte 0
cmb_miss_str:    .text "MISS" ; .byte 0
cmb_kill_str:    .text "HAVE SLAIN" ; .byte 0
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

    ldx cmb_slot
    jsr monster_remove

!pam_next_blow:
    dec zp_combat_blows
    jmp !pam_blow_loop-

    // --- Print one summary message for the round ---
!pam_summary:
    lda cmb_dead
    beq !pam_not_dead+

    // Killed: "YOU HAVE SLAIN THE <name>."
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

    // Hit but alive: "YOU HIT THE <name>."
    lda #<cmb_hit_str
    ldy #>cmb_hit_str
    jsr msg_build_action
    jsr cmb_print_buf

    lda #SFX_HIT
    jsr sound_play
    jmp !pam_done+

!pam_all_miss:
    // All blows missed: "YOU MISS THE <name>."
    lda #<cmb_miss_str
    ldy #>cmb_miss_str
    jsr msg_build_action
    jsr cmb_print_buf

    lda #SFX_MISS
    jsr sound_play

!pam_done:
    sec                         // Turn consumed
    rts

// combat_calc_tohit — Compute hit chance
// hit_chance = class_bth + PL_TOHIT*3 + player_level * class_bth_per_level
// Output: zp_combat_tohit = hit chance (capped at 255)
// Clobbers: A, X, Y, zp_math_a/b
combat_calc_tohit:
    // Get class BTH (class_properties offset 3)
    lda player_data + PL_CLASS
    ldx #CLASS_PROP_SIZE
    jsr math_multiply           // A = class * 10
    clc
    adc #3                      // Offset to BTH field
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
    jmp !cct_race_done+
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

    // Positive: multiply by 3
    sta zp_temp0
    asl                         // *2
    clc
    adc zp_temp0                // *3
    clc
    adc zp_combat_tohit
    bcc !cct_tohit_ok+
    lda #255                    // Cap at 255
    jmp !cct_tohit_ok+

!cct_neg_tohit:
    // Negative to-hit: negate, *3, then subtract
    eor #$ff
    clc
    adc #1                      // abs(PL_TOHIT)
    sta zp_temp0
    asl                         // *2
    clc
    adc zp_temp0                // *3 (positive value)
    sta zp_temp0
    // Subtract from tohit
    lda zp_combat_tohit
    sec
    sbc zp_temp0
    bcs !cct_tohit_ok+
    lda #0                      // Floor at 0

!cct_tohit_ok:
    sta zp_combat_tohit

    // Add player_level * class_bth_per_level (class_level_adj offset 0)
    lda player_data + PL_CLASS
    ldx #CLASS_LVL_SIZE
    jsr math_multiply           // A = class * 5
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
    jmp !ccb_lookup+
!ccb_br1:
    lda #1
    jmp !ccb_lookup+
!ccb_br2:
    lda #2
    jmp !ccb_lookup+
!ccb_br3:
    lda #3
    jmp !ccb_lookup+
!ccb_br4:
    lda #4
    jmp !ccb_lookup+
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

// combat_apply_damage — Subtract damage from monster HP
// Input:  X = monster slot index, A = damage amount
// Output: carry set = monster dead (HP <= 0)
//         carry clear = monster still alive
// Clobbers: A, Y, zp_ptr0
combat_apply_damage:
    sta zp_temp0                // Save damage

    jsr monster_get_ptr         // zp_ptr0 = entry

    // 16-bit subtraction: HP -= damage
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sec
    sbc zp_temp0
    sta (zp_ptr0),y

    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sbc #0                      // Borrow from hi byte
    sta (zp_ptr0),y

    // Check if dead: hi byte negative (bit 7 set) OR both bytes zero
    bmi !cad_dead+              // Hi byte went negative → dead

    // Check if both bytes are zero
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    ldy #MX_HP_HI
    ora (zp_ptr0),y
    beq !cad_dead+              // HP = 0 → dead

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
    sta zp_temp2

    // 16×8→24: (xp_hi:xp_lo) × level
    // Step 1: xp_lo × level
    lda zp_temp0
    ldx zp_temp2
    jsr math_multiply           // zp_math_a/b = lo product
    lda zp_math_a
    sta ccl_adj_0
    lda zp_math_b
    sta ccl_adj_1
    lda #0
    sta ccl_adj_2

    // Step 2: xp_hi × level, add shifted left 8
    lda zp_temp1
    ldx zp_temp2
    jsr math_multiply
    lda ccl_adj_1
    clc
    adc zp_math_a
    sta ccl_adj_1
    lda ccl_adj_2
    adc zp_math_b
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

    rts

// combat_check_levelup — Check if XP exceeds adjusted level threshold
// Adjusted threshold = base_threshold * PL_EXPFACT / 100
// Compares 16-bit PL_XP against adjusted threshold.
// Levels up once if exceeded; caps at 1 level per kill (excess XP halved and retained).
// Clobbers: A, X, Y, zp_math_a/b, zp_temp0-4
combat_check_levelup:
    // Get base threshold for current level
    lda zp_player_lvl
    sec
    sbc #1                      // Index = level - 1
    tax
    lda xp_level_lo,x
    sta zp_temp0
    lda xp_level_hi,x
    sta zp_temp1

    // Multiply threshold by expfact: 16×8 → 24-bit
    // Step 1: threshold_lo * expfact
    lda zp_temp0
    ldx player_data + PL_EXPFACT
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi
    lda zp_math_a
    sta ccl_adj_0
    lda zp_math_b
    sta ccl_adj_1
    lda #0
    sta ccl_adj_2

    // Step 2: threshold_hi * expfact, add shifted left 8
    lda zp_temp1
    ldx player_data + PL_EXPFACT
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi
    lda ccl_adj_1
    clc
    adc zp_math_a
    sta ccl_adj_1
    lda ccl_adj_2
    adc zp_math_b
    sta ccl_adj_2

    // Divide 24-bit product by 100 → adjusted threshold
    lda #100
    sta ccl_divisor
    jsr ccl_div_24x8

    // Result in ccl_adj_0/1 (16-bit). Cap at $FFFF if overflow.
    lda ccl_adj_2
    beq !ccl_no_cap+
    lda #$ff
    sta ccl_adj_0
    sta ccl_adj_1
!ccl_no_cap:

    // Compare 16-bit: PL_XP >= adjusted threshold?
    lda player_data + PL_XP_1
    cmp ccl_adj_1
    bcc !ccl_no+                // XP_hi < threshold_hi → no
    bne !ccl_yes+               // XP_hi > threshold_hi → yes
    lda player_data + PL_XP_0
    cmp ccl_adj_0
    bcc !ccl_no+                // XP_lo < threshold_lo → no

!ccl_yes:
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
    jsr magic_recalc_mana
    jsr magic_check_new_spells

    // Play level-up sound
    lda #SFX_LEVELUP
    jsr sound_play

    // Print level-up message: "WELCOME TO LEVEL N."
    jsr msg_build_levelup
    jsr cmb_print_buf

    // Halve excess XP above new threshold (umoria behavior).
    // Prevents a single big kill from cascading through many levels.
    // ccl_adj_0/1 still holds the adjusted threshold from the comparison.
    lda player_data + PL_XP_0
    sec
    sbc ccl_adj_0
    sta zp_temp0                    // excess_lo
    lda player_data + PL_XP_1
    sbc ccl_adj_1
    sta zp_temp1                    // excess_hi
    lsr zp_temp1                    // 16-bit halve
    ror zp_temp0
    lda ccl_adj_0                   // new XP = threshold + excess/2
    clc
    adc zp_temp0
    sta player_data + PL_XP_0
    lda ccl_adj_1
    adc zp_temp1
    sta player_data + PL_XP_1

    // Cap at 1 level per kill — excess XP retained (halved above)
    rts

!ccl_no:
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

// msg_build_action — "YOU <action> THE <name>."
// Input: A = action string ptr lo, Y = action string ptr hi
// Clobbers: A, X, Y, zp_ptr1
msg_build_action:
    sta mba_action_lo
    sty mba_action_hi
    lda #0
    sta cmb_buf_idx

    lda #<cmb_you_str
    ldy #>cmb_you_str
    jsr combat_append_str       // "YOU "

    lda mba_action_lo
    ldy mba_action_hi
    jsr combat_append_str       // action verb

    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str       // " THE "

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

// msg_build_levelup — "WELCOME TO LEVEL N."
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
    sta zp_temp0                // Save value
    ldx cmb_buf_idx
    lda #0
    sta zp_temp1                // Leading zero flag

    // Hundreds
    lda zp_temp0
    ldy #0
!cad_hundreds:
    cmp #100
    bcc !cad_tens+
    sbc #100
    iny
    jmp !cad_hundreds-
!cad_tens:
    sta zp_temp0                // Remainder
    tya
    beq !cad_skip_h+
    ora #$30                    // Digit screen code
    sta combat_msg_buf,x
    inx
    lda #1
    sta zp_temp1                // Printed a digit
!cad_skip_h:

    // Tens
    lda zp_temp0
    ldy #0
!cad_tens_loop:
    cmp #10
    bcc !cad_ones+
    sbc #10
    iny
    jmp !cad_tens_loop-
!cad_ones:
    sta zp_temp0                // Remainder (ones)
    tya
    bne !cad_print_t+
    // Check if we need a leading zero for tens
    ldy zp_temp1
    beq !cad_skip_t+
!cad_print_t:
    ora #$30
    sta combat_msg_buf,x
    inx
!cad_skip_t:

    // Ones (always printed)
    lda zp_temp0
    ora #$30
    sta combat_msg_buf,x
    inx

    stx cmb_buf_idx
    rts

// combat_append_decimal_16 — Append 16-bit decimal number to buffer
// Input: zp_temp0 = lo, zp_temp1 = hi
// Clobbers: A, X, Y, zp_temp0-3
combat_append_decimal_16:
    ldx cmb_buf_idx
    lda #0
    sta zp_temp2                // Leading zero flag
    ldy #4                      // 5 digits: index 4..0
!cad16_digit:
    lda #0
    sta zp_temp3                // Digit counter
!cad16_sub:
    lda zp_temp0
    sec
    sbc decimal_powers_lo,y
    pha
    lda zp_temp1
    sbc decimal_powers_hi,y
    bcc !cad16_done+            // Underflow — done with this digit
    sta zp_temp1
    pla
    sta zp_temp0
    inc zp_temp3
    jmp !cad16_sub-
!cad16_done:
    pla                         // Discard underflowed lo
    lda zp_temp3
    bne !cad16_print+
    lda zp_temp2
    beq !cad16_next+            // Still leading zeros, skip
!cad16_print:
    lda #1
    sta zp_temp2                // No more leading zeros
    lda zp_temp3
    ora #$30                    // Digit → screen code
    sta combat_msg_buf,x
    inx
!cad16_next:
    dey
    bne !cad16_digit-
    // Always print ones digit
    lda zp_temp0
    ora #$30
    sta combat_msg_buf,x
    inx
    stx cmb_buf_idx
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "combat_msg_buf size", cmb_you_str - combat_msg_buf, 42
