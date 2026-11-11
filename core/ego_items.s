#importonce
// ego_items.s — Ego item generation and suffix strings
//
// C128: lives in loaded low RAM (`128.runtime.prg`, runtime at `$1000+`) so it stays
// out of the `$D000-$DFFF` I/O hole while remaining callable through the
// existing trampolines. C64/tests may link it elsewhere.
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
//   8 = Slay Dragon  — x4 dmg vs CF_DRAGON (VMS tot_dam, moria.inc; 2026-11-07)
//   9-13 = Resistance armour (body armour and shields; VMS magic_treasure,
//          misc.inc): Resist (fire, cold, acid, lightning; +5 AC), Resist
//          Acid, Resist Fire, Resist Cold, Resist Lightning (2026-11-11)
//   14 = of the Magi (crowns): See Invisible, fire, acid and cold
//        resistance, INT +p1 (VMS magic_treasure; 2026-11-11, MON-030)

// Ego IDs: core/item_defs.s (shared with player.s and monster_acid.s).
.assert "Ego IDs fill EGO_TYPE_COUNT", EGO_MAGI + 1, EGO_TYPE_COUNT
.assert "The crowns are the last item IDs (roll_ego_type, roll_armour_ego: ID >= the Silver Crown)", ITEM_TYPE_CROWN_SILVER == ITEM_TYPE_COUNT - 3 && ITEM_TYPE_CROWN_JEWEL == ITEM_TYPE_COUNT - 1, true
// ============================================================
// roll_ego_type — Determine ego type for a spawned item
// Input: A = item type ID
// Output: A = ego type (0 = none)
// Melee weapons (ICAT_WEAPON): chance = min(dlvl * 2, 40) out of 100.
// Body armour, shields and crowns: resistance armour and the Magi
// (roll_armour_ego). Digging tools: roll_tool_ego_check.
// Called after roll_enchantment for the same item (fi_add_to_ac set).
// Clobbers: A, X, Y
// ============================================================
roll_ego_type:
    // Check category — weapons get weapon ego, digging tools get tool ego
    tax
    tay                         // the item, for roll_armour_ego
    lda it_category,x
    cmp #ICAT_WEAPON
    beq !ret_weapon_ego+
    cmp #ICAT_ARMOR
    beq !ret_armour_ego+
    cmp #ICAT_SHIELD
    beq !ret_armour_ego+
    cmp #ICAT_HELM
    bne !ret_not_armour+
    cpx #ITEM_TYPE_CROWN_SILVER
    bcc !ret_zero+          // helms and caps: none
!ret_armour_ego:
    jmp roll_armour_ego
!ret_not_armour:
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

    // Pick a weapon ego type: rng(8) + 1 → [1, 8]
    lda #EGO_SLAY_DRAGON
    jsr rng_range           // [0, 7]
    clc
    adc #1                  // [1, 8]
    rts

!ret_zero:
    lda #EGO_NONE
    rts

// The resistance armour roll and its data (pick table, suffixes): a port or
// test short of room places them with :EgoArmourSegment()/
// :EgoArmourRestoreSegment() (the code) and :EgoArmourDataSegment()/
// :EgoArmourDataRestoreSegment() (the data; the C128: its world payload).
#if !EGO_ARMOUR_SEGMENT_CUSTOM
.macro EgoArmourSegment() {}
.macro EgoArmourRestoreSegment() {}
#endif
#if !EGO_ARMOUR_DATA_SEGMENT_CUSTOM
.macro EgoArmourDataSegment() {}
.macro EgoArmourDataRestoreSegment() {}
#endif
:EgoArmourSegment()
// roll_armour_ego — VMS magic_treasure (misc.inc) for armour, shields and
// crowns (Y = the item): one that rolled its magic bonus (positive to-AC, so
// not cursed) passes magik(special), special = trunc(magic chance / 6)
// (obj_div_special), the chance min(15 + dlvl, 70) as roll_enchantment's.
// Armour and shields then take randint(9): 1 (R) +5 AC, 2 (RA), 3-4 (RF),
// 5-6 (RC), 7-9 (RL). Crowns (helm subval 6-8) take randint(6) = 3: of the
// Magi, p1 (INT) randint(3); Might, Lordliness, Beauty, Seeing and
// Regeneration (1, 2, 4-6) are not modelled: plain crowns.
roll_armour_ego:
    lda fi_add_to_ac
    beq !rae_none+
    bmi !rae_none+          // Unenchanted or cursed: no resistance
    lda zp_player_dlvl
    clc
    adc #15
    cmp #71
    bcc !rae_chance+
    lda #70
!rae_chance:
    ldx #$ff
    sec
!rae_div6:
    inx
    sbc #6
    bcs !rae_div6-          // X = trunc(chance / 6)
    stx ego_chance
    lda #100
    jsr rng_range           // [0, 99]: randint(100) <= special (keeps Y)
    cmp ego_chance
    bcs !rae_none+
    cpy #ITEM_TYPE_CROWN_SILVER
#if EGO_ARMOUR_DATA_SEGMENT_CUSTOM
    bcc !rae_armour+
    jmp roll_crown_ego          // placed apart with the data
!rae_armour:
#else
    bcs roll_crown_ego
#endif
    lda #9
    jsr rng_range           // randint(9) - 1
    tax
    lda ego_armour_pick,x
    cmp #EGO_RESIST
    bne !rae_done+
    lda fi_add_to_ac        // (R): +5 to-AC (at most 1 + 70/4 + 5)
    clc
    adc #5
    sta fi_add_to_ac
    lda #EGO_RESIST
!rae_done:
    rts
!rae_none:
    lda #EGO_NONE
    rts
:EgoArmourRestoreSegment()

:EgoArmourDataSegment()
// roll_crown_ego — roll_armour_ego's crowns, past its magik(special): with
// the data, which a port short of room places apart from the code (the
// C128: its world payload; both stay resident).
roll_crown_ego:
    lda #6
    jsr rng_range           // randint(6) - 1
    cmp #2
    bne !rce_none+
    lda #3
    jsr rng_range           // carry clear
    adc #1
    sta fi_add_p1           // INT +1..3
    lda #EGO_MAGI
    rts
!rce_none:
    lda #EGO_NONE
    rts
ego_armour_pick:
    .byte EGO_RESIST, EGO_RESIST_ACID, EGO_RESIST_FIRE, EGO_RESIST_FIRE
    .byte EGO_RESIST_COLD, EGO_RESIST_COLD, EGO_RESIST_LIGHT, EGO_RESIST_LIGHT, EGO_RESIST_LIGHT
ego_str_resist:       .text " (Resist)" ; .byte 0
ego_str_resist_acid:  .text " (Resist Acid)" ; .byte 0
ego_str_resist_fire:  .text " (Resist Fire)" ; .byte 0
ego_str_resist_cold:  .text " (Resist Cold)" ; .byte 0
ego_str_resist_light: .text " (Resist Lightning)" ; .byte 0
ego_str_magi:         .text " of the Magi" ; .byte 0
:EgoArmourDataRestoreSegment()

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
    .byte <ego_str_defender, <ego_str_holy_avenger, <ego_str_slay_dragon
    .byte <ego_str_resist, <ego_str_resist_acid, <ego_str_resist_fire
    .byte <ego_str_resist_cold, <ego_str_resist_light, <ego_str_magi
ego_suffix_hi:
    .byte >ego_str_none
    .byte >ego_str_slay_animal, >ego_str_slay_evil, >ego_str_slay_undead
    .byte >ego_str_flame, >ego_str_frost
    .byte >ego_str_defender, >ego_str_holy_avenger, >ego_str_slay_dragon
    .byte >ego_str_resist, >ego_str_resist_acid, >ego_str_resist_fire
    .byte >ego_str_resist_cold, >ego_str_resist_light, >ego_str_magi
.assert "ego_suffix_lo has EGO_TYPE_COUNT entries", ego_suffix_hi - ego_suffix_lo, EGO_TYPE_COUNT

#if !EGO_SUFFIX_STRINGS_EXTERNAL
#import "ego_suffix_strings.s"
#endif

// ============================================================
// Ego data tables, by the weapon slot's ego only (weapons 1-8, digging
// tools 1-3): no entries for the armour and crown egos.
// ============================================================
ego_slay_mask:
    .byte 0, CF_ANIMAL, CF_EVIL, CF_UNDEAD, 0, 0, 0, CF_EVIL|CF_UNDEAD, CF_DRAGON
ego_slay_mult:
    .byte 0, 2, 2, 3, 0, 0, 0, 2, 4
ego_ac_bonus:
    .byte 0, 0, 0, 0, 0, 0, 5, 3, 0             // armour's +5 (R) is in its to-AC
ego_ac_bonus_end:
.assert "ego_slay_mask has the weapon egos", ego_slay_mult - ego_slay_mask, EGO_RESIST
.assert "ego_slay_mult has the weapon egos", ego_ac_bonus - ego_slay_mult, EGO_RESIST
.assert "ego_ac_bonus has the weapon egos", ego_ac_bonus_end - ego_ac_bonus, EGO_RESIST

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
    bne !ead_apply_mult+
!ead_ha_evil:
    lda #2                      // x2 for evil

!ead_apply_mult:
    // A = multiplier (2, 3 or 4)
    cmp #3
    beq !ead_mult3+
    // x2 or x4 (Slay Dragon): one or two doublings
    lsr
    tay
    lda cmb_damage
!ead_double:
    asl
    bcs !ead_mult_cap+
    dey
    bne !ead_double-
    beq !ead_mult_ok+           // Always
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
    // Flame Tongue and Frost Brand both add 2d4 bonus damage.
    lda ead_ego_type
    cmp #EGO_FLAME_TONGUE
    beq !ead_bonus_roll+
    cmp #EGO_FROST_BRAND
    bne !ead_done+
!ead_bonus_roll:
    lda #2
    ldx #4
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
#if HAL_PLATFORM_EGO_AC_BONUS_LOCAL
ego_get_ac_bonus:
    tax
    lda ego_ac_bonus,x
    rts
#endif
