// ego_items.s — Ego item generation and suffix strings
//
// Lives at $F000 (RAM under KERNAL ROM), accessed via trampolines.
// Ego types are enchanted weapon variants (e.g., "Long Sword (Flame)").
//
// Ego Type IDs:
//   0 = None
//   1 = Slay Animal — x2 dmg vs CF_ANIMAL
//   2 = Slay Evil   — x2 dmg vs CF_EVIL
//   3 = Slay Undead — x3 dmg vs CF_UNDEAD
//   4 = Flame Tongue — +2d4 bonus dmg always
//   5 = Frost Brand  — +2d4 bonus dmg always
//   6 = Defender     — +5 AC when wielded
//   7 = Holy Avenger — x2 evil + x3 undead + +3 AC

.const EGO_NONE          = 0
.const EGO_SLAY_ANIMAL   = 1
.const EGO_SLAY_EVIL     = 2
.const EGO_SLAY_UNDEAD   = 3
.const EGO_FLAME_TONGUE  = 4
.const EGO_FROST_BRAND   = 5
.const EGO_DEFENDER      = 6
.const EGO_HOLY_AVENGER  = 7
.const EGO_TYPE_COUNT    = 8

// ============================================================
// roll_ego_type — Determine ego type for a spawned item
// Input: A = item type ID
// Output: A = ego type (0 = none)
// Only weapons (ICAT_WEAPON, melee only) can get ego types.
// Chance = min(dlvl * 2, 40) out of 100.
// Clobbers: A, X, Y
// ============================================================
roll_ego_type:
    // Check category — weapons get weapon ego, digging tools get tool ego
    tax
    lda it_category,x
    cmp #ICAT_WEAPON
    beq !ret_weapon_ego+
    jmp roll_tool_ego_check     // Main RAM: handles ICAT_DIGGING check, returns 0 for others
!ret_weapon_ego:

    // Exclude ranged weapons (bows, crossbows, slings) and ammo
    jsr item_get_missile
    bne !ret_zero+          // Non-zero = ranged/ammo → no ego

    // Calculate chance = min(dlvl * 2, 40)
    lda zp_player_dlvl
    asl                     // * 2
    cmp #41
    bcc !ret_chance_ok+
    lda #40
!ret_chance_ok:
    sta ego_chance

    // Roll rng(100)
    lda #100
    jsr rng_range           // [0, 99]
    cmp ego_chance
    bcs !ret_zero+          // roll >= chance → no ego

    // Pick ego type: rng(7) + 1 → [1, 7]
    lda #7
    jsr rng_range           // [0, 6]
    clc
    adc #1                  // [1, 7]
    rts

!ret_zero:
    lda #EGO_NONE
    rts

ego_chance: .byte 0

// ============================================================
// ego_get_suffix_ptr — Get ego suffix string pointer
// Input: A = ego type (1-7)
// Output: zp_ptr0 = pointer to null-terminated suffix string
//         (pointer is in $F000 region — caller must have KERNAL banked out)
// Clobbers: A, X
// ============================================================
ego_get_suffix_ptr:
    tax
    lda ego_suffix_lo,x
    sta zp_ptr0
    lda ego_suffix_hi,x
    sta zp_ptr0_hi
    rts

// Suffix pointer tables (index 0 = unused/empty)
ego_suffix_lo:
    .byte <ego_str_none
    .byte <ego_str_slay_animal, <ego_str_slay_evil, <ego_str_slay_undead
    .byte <ego_str_flame, <ego_str_frost
    .byte <ego_str_defender, <ego_str_holy_avenger
ego_suffix_hi:
    .byte >ego_str_none
    .byte >ego_str_slay_animal, >ego_str_slay_evil, >ego_str_slay_undead
    .byte >ego_str_flame, >ego_str_frost
    .byte >ego_str_defender, >ego_str_holy_avenger

// Ego suffix strings (screen codes, null-terminated)
// These are in banked RAM at $F000+ so must be read while KERNAL is banked out.
ego_str_none:         .byte 0
ego_str_slay_animal:  .text " (Slay Animal)" ; .byte 0
ego_str_slay_evil:    .text " (Slay Evil)" ; .byte 0
ego_str_slay_undead:  .text " (Slay Undead)" ; .byte 0
ego_str_flame:        .text " (Flame)" ; .byte 0
ego_str_frost:        .text " (Frost)" ; .byte 0
ego_str_defender:     .text " (Defender)" ; .byte 0
ego_str_holy_avenger: .text " (Holy Avenger)" ; .byte 0

// ============================================================
// Ego data tables (indexed by ego type 0-7)
// ============================================================
ego_slay_mask:
    .byte 0, CF_ANIMAL, CF_EVIL, CF_UNDEAD, 0, 0, 0, CF_EVIL|CF_UNDEAD
ego_slay_mult:
    .byte 0, 2, 2, 3, 0, 0, 0, 2
ego_bonus_dice:
    .byte 0, 0, 0, 0, 2, 2, 0, 0
ego_bonus_sides:
    .byte 0, 0, 0, 0, 4, 4, 0, 0
ego_ac_bonus:
    .byte 0, 0, 0, 0, 0, 0, 5, 3

// ============================================================
// ego_apply_damage — Apply ego damage modifiers (slay + bonus dice)
// Called from trampoline with KERNAL banked out.
// Reads cmb_damage, cmb_type. Writes result to cmb_damage.
// Input: A = ego type (1-7, already validated nonzero by caller)
// Clobbers: A, X, Y, zp_math_a/b, zp_temp3, zp_temp4
// ============================================================
ego_apply_damage:
    sta ead_ego_type

    // Check slay multiplier
    tax
    lda ego_slay_mask,x
    beq !ead_check_bonus+       // No slay mask → check bonus dice
    ldx cmb_type
    and cr_mflags,x
    beq !ead_check_bonus+       // Monster doesn't match

    // Slay hit! Get multiplier
    ldx ead_ego_type
    lda ego_slay_mult,x
    // Holy Avenger special: undead (x3) takes priority over evil (x2)
    cpx #EGO_HOLY_AVENGER
    bne !ead_apply_mult+
    ldx cmb_type
    lda cr_mflags,x
    and #CF_UNDEAD
    beq !ead_ha_evil+
    lda #3                      // x3 for undead
    jmp !ead_apply_mult+
!ead_ha_evil:
    lda #2                      // x2 for evil

!ead_apply_mult:
    // A = multiplier (2 or 3)
    cmp #3
    beq !ead_mult3+
    // x2
    lda cmb_damage
    asl
    bcc !ead_mult_ok+
    lda #255
    jmp !ead_mult_ok+
!ead_mult3:
    // x3 = x2 + x1
    lda cmb_damage
    asl
    bcs !ead_mult_cap+
    clc
    adc cmb_damage
    bcc !ead_mult_ok+
!ead_mult_cap:
    lda #255
!ead_mult_ok:
    sta cmb_damage

!ead_check_bonus:
    // Bonus dice (Flame Tongue / Frost Brand)
    ldx ead_ego_type
    lda ego_bonus_dice,x
    beq !ead_done+
    pha                         // Save dice count
    lda ego_bonus_sides,x
    tax                         // X = sides
    pla                         // A = dice count
    ldy #0                      // No static bonus
    jsr math_dice               // Result in zp_math_a
    lda cmb_damage
    clc
    adc zp_math_a
    bcc !ead_bonus_ok+
    lda #255
!ead_bonus_ok:
    sta cmb_damage

!ead_done:
    rts

ead_ego_type: .byte 0

// ============================================================
// ego_get_ac_bonus — Get AC bonus for an ego type
// Input: A = ego type
// Output: A = AC bonus (0 if none)
// Clobbers: X
// ============================================================
ego_get_ac_bonus:
    tax
    lda ego_ac_bonus,x
    rts
