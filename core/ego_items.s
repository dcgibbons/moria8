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
.assert "Ego IDs fill EGO_TYPE_COUNT", EGO_AMMO_SLAY_ANIMAL + 1, EGO_TYPE_COUNT
.assert "Crowns are contiguous", ITEM_TYPE_CROWN_JEWEL == ITEM_TYPE_CROWN_SILVER + 2, true
// ============================================================
// roll_ego_type — Determine ego type for a spawned item
// Input: A = item slot_lo, item_cur_page = 0 or ITEM_PAGE_BIT
// Output: A = ego type (0 = none)
// Melee weapons & ammo (ICAT_WEAPON): chance = min(dlvl * 2, 40) out of 100.
// Armor/shield/helm/crown/gloves/boots/cloak: roll_armour_ego.
// Digging tools: roll_tool_ego_check.
// Called after roll_enchantment for the same item (fi_add_* set).
// Clobbers: A, X, Y
// ============================================================
roll_ego_type:
    tax
    tay                         // Y = slot_lo
    jsr item_get_category_a     // A = ICAT_*, preserves X, Y
    cmp #ICAT_WEAPON
    beq !ret_weapon_ego+
    sta ego_cat
    cmp #ICAT_CLOAK
    beq !ret_armour_ego+
    cmp #ICAT_ARMOR
    bcc !ret_not_armour+
    cmp #ICAT_BOOTS + 1
    bcc !ret_armour_ego+
!ret_not_armour:
    jmp roll_tool_ego_check     // Main RAM: A = ICAT_*; handles ICAT_DIGGING, else 0
!ret_armour_ego:
    jmp roll_armour_ego
!ret_weapon_ego:
    jsr item_get_missile        // A = 0 melee, 1..3 launcher, $81..$83 ammo (keeps X, Y)
    beq !ret_roll_wep+
    bpl !ret_zero+              // Launchers never get ego
    tax
    lda fi_add_flags
    and #IF_CURSED
    bne !ret_zero+
    txa
!ret_roll_wep:
    sta ego_cat                 // 0 = melee, negative = ammo
    // Calculate chance = min(dlvl * 2, 40)
    lda zp_player_dlvl
    asl
    cmp #41
    bcc !ret_chance_ok+
    lda #40
!ret_chance_ok:
    sta ego_chance
    lda #100
    jsr rng_range               // [0, 99]
    cmp ego_chance
    bcs !ret_zero+
    bit ego_cat
    bmi !ret_ammo_ego+
    lda #EGO_SLAY_DRAGON
    jsr rng_range               // [0, 7]
    clc
    adc #1                      // [1, 8]
    rts
!ret_ammo_ego:
    lda #4
    jsr rng_range
    tax
    lda ego_ammo_pick,x
    rts
!ret_zero:
    lda #EGO_NONE
    rts

// The resistance armour roll and its data (pick table): a port or
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
// roll_armour_ego — VMS magic_treasure (misc.inc) for armour, shields,
// crowns, helms, gloves, boots and cloaks (Y = slot_lo, ego_cat = ICAT_*).
roll_armour_ego:
    lda fi_add_to_ac
    beq !rae_none+
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
    bcs !rae_div6-              // X = trunc(chance / 6)
    stx ego_chance
    lda #100
    jsr rng_range               // [0, 99] (keeps Y)
    cmp ego_chance
    bcs !rae_none+
    bit fi_add_to_ac
    bpl !rae_pos+
    jmp roll_cursed_armour_ego
!rae_pos:
    lda ego_cat
    cmp #ICAT_HELM
    beq !rae_helm+
    cmp #ICAT_GLOVES
    beq !rae_gloves+
    cmp #ICAT_BOOTS
    bne !+
    jmp !rae_boots+
!:  cmp #ICAT_CLOAK
    beq !rae_cloak+
    // ICAT_ARMOR / ICAT_SHIELD
    lda #9
    jsr rng_range
    tax
    lda ego_armour_pick,x
    cmp #EGO_RESIST
    bne !rae_done+
    lda fi_add_to_ac
    clc
    adc #5
    sta fi_add_to_ac
    lda #EGO_RESIST
!rae_done:
    rts
!rae_none:
    lda #EGO_NONE
    rts
!rae_cloak:
    lda #2
    jsr rng_range
    beq !rae_c_prot+
    bne !rae_stealth_p1+
!rae_c_prot:
    lda #3
    jsr !rae_1_to_a+
    clc
    adc fi_add_to_ac
    sta fi_add_to_ac
    lda #EGO_PROTECTION
    rts
!rae_helm:
    bit item_cur_page
    bvs !rae_reg_helm+
    cpy #ITEM_TYPE_CROWN_SILVER
    bcc !rae_reg_helm+
    cpy #ITEM_TYPE_CROWN_JEWEL + 1
    bcs !rae_reg_helm+
    jmp roll_crown_ego
!rae_reg_helm:
    lda #3
    jsr rng_range
    pha
    clc
    adc #EGO_INTELLIGENCE
    tay                         // Y = 25..27 (rng_range preserves Y)
    pla
    cmp #2                      // Infra-Vision +1..4, INT/WIS +1..2
    lda #2
    bcc !rae_h_p1+
    lda #4
!rae_h_p1:
    jsr !rae_p1_1_to_a+
    tya
    rts
!rae_gloves:
    lda #2
    jsr rng_range
    beq !rae_g_fa+
    lda #3
    jsr !rae_1_to_a+
    clc
    adc fi_add_to_hit
    sta fi_add_to_hit
    lda #3
    jsr !rae_1_to_a+
    clc
    adc fi_add_to_dam
    sta fi_add_to_dam
    lda #EGO_SLAYING
    rts
!rae_g_fa:
    lda #EGO_FREE_ACTION
    rts
!rae_boots:
    lda #3
    jsr rng_range
    clc
    adc #EGO_SLOW_DESCENT
    cmp #EGO_SPEED
    bne !rae_b_chk_st+
    ldx #1
    stx fi_add_p1
    rts
!rae_b_chk_st:
    cmp #EGO_STEALTH
    beq !rae_stealth_p1+
    rts
!rae_stealth_p1:
    lda #3
    jsr !rae_p1_1_to_a+
    lda #EGO_STEALTH
    rts
!rae_p1_1_to_a:
    jsr !rae_1_to_a+
    sta fi_add_p1
    rts
!rae_1_to_a:
    jsr rng_range
    clc
    adc #1
    rts
:EgoArmourRestoreSegment()

:EgoArmourDataSegment()
// roll_crown_ego / roll_cursed_armour_ego / ego_armour_pick — placed apart with data when requested.
roll_crown_ego:
    lda #6
    jsr rng_range
    tax
    lda ego_crown_pick,x
    cmp #EGO_REGENERATION
    beq !rce_ret+
    pha
    lda #3
    jsr rng_range
    clc
    adc #1
    sta fi_add_p1
    pla
!rce_ret:
    rts

roll_cursed_armour_ego:
    lda ego_cat
    cmp #ICAT_HELM
    beq !rcae_helm+
    cmp #ICAT_GLOVES
    beq !rcae_gloves+
    cmp #ICAT_BOOTS
    beq !rcae_boots+
    cmp #ICAT_CLOAK
    beq !rcae_cloak+
    lda #EGO_NONE
    rts
!rcae_helm:
    lda #6
    jsr rng_range
    clc
    adc #EGO_STUPIDITY
    cmp #EGO_BLINDNESS
    bcc !rcae_neg_p1+
    cmp #EGO_UGLINESS
    beq !rcae_neg_p1+
    bne !rcae_mark_cursed+
!rcae_gloves:
    lda #2
    jsr rng_range
    clc
    adc #EGO_CLUMSINESS
!rcae_neg_p1:
    pha
    lda #4
    jsr rng_range
    eor #$ff                    // -(rng(4) + 1) = -1..-4
    sta fi_add_p1
    pla
    jmp !rcae_mark_cursed+
!rcae_boots:
    lda #3
    jsr rng_range
    clc
    adc #EGO_SLOWNESS
    cmp #EGO_SLOWNESS
    bne !rcae_mark_cursed+
    ldx #$ff
    stx fi_add_p1
    bne !rcae_mark_cursed+
!rcae_cloak:
    lda #3
    jsr rng_range
    clc
    adc #EGO_IRRITATION
    cmp #EGO_VULNERABILITY
    beq !rcae_vuln+
    cmp #EGO_ENVELOPING
    bne !rcae_mark_cursed+
    lda fi_add_to_hit
    sec
    sbc #3
    sta fi_add_to_hit
    lda fi_add_to_dam
    sec
    sbc #3
    sta fi_add_to_dam
    lda #EGO_ENVELOPING
    bne !rcae_mark_cursed+
!rcae_vuln:
    lda fi_add_to_ac
    sec
    sbc #10
    sta fi_add_to_ac
    lda #EGO_VULNERABILITY
!rcae_mark_cursed:
    pha
    lda fi_add_flags
    ora #IF_CURSED
    sta fi_add_flags
    pla
    rts

ego_armour_pick:
    .byte EGO_RESIST, EGO_RESIST_ACID, EGO_RESIST_FIRE, EGO_RESIST_FIRE
    .byte EGO_RESIST_COLD, EGO_RESIST_COLD, EGO_RESIST_LIGHT, EGO_RESIST_LIGHT, EGO_RESIST_LIGHT
ego_crown_pick:
    .byte EGO_MIGHT, EGO_LORDLINESS, EGO_MAGI, EGO_BEAUTY, EGO_SEEING, EGO_REGENERATION
ego_ammo_pick:
    .byte EGO_AMMO_FIRE, EGO_AMMO_SLAY_EVIL, EGO_DRAGON_SLAYING, EGO_AMMO_SLAY_ANIMAL
:EgoArmourDataRestoreSegment()

ego_chance: .byte 0
ego_cat:    .byte 0

// ============================================================
// ego_get_suffix_ptr — Decode ego suffix string via ITEM.CAT
// Input: A = ego type (0..55, masked by EGO_ID_MASK)
// Output: zp_ptr0 = pointer to null-terminated string in item_name_decode_buf
// Clobbers: A, Y
// ============================================================
ego_get_suffix_ptr:
    and #EGO_ID_MASK
    beq !egsp_none+
    cmp #EGO_TYPE_COUNT
    bcc !egsp_decode+
!egsp_none:
    lda #0
    sta item_name_decode_buf
    lda #<item_name_decode_buf
    sta zp_ptr0
    lda #>item_name_decode_buf
    sta zp_ptr0_hi
    rts
!egsp_decode:
    jmp item_cat_decode_ego

#if !EGO_SUFFIX_STRINGS_EXTERNAL
#import "ego_suffix_strings.s"
#endif

// ============================================================
// Ego data tables (weapons 1-8)
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
// Input: A = ego type (1..55, masked by EGO_ID_MASK)
// Clobbers: A, X, Y, zp_math_a/b, zp_temp3, zp_temp4
// ============================================================
ego_apply_damage:
    and #EGO_ID_MASK
    bne !+
    rts
!:  sta ead_ego_type
    cmp #EGO_SLAY_DRAGON + 1
    bcs !ead_ammo_check+

    // Melee weapon ego 1..8
    tax
    lda ego_slay_mask,x
    beq !ead_to_bonus+
    ldx cmb_type
    and cr_mflags,x
    beq !ead_to_bonus+

    ldx ead_ego_type
    lda ego_slay_mult,x
    cpx #EGO_HOLY_AVENGER
    bne !ead_apply_mult+
    ldx cmb_type
    lda cr_mflags,x
    and #CF_UNDEAD
    beq !ead_ha_evil+
    lda #3
    bne !ead_apply_mult+
!ead_ha_evil:
    lda #2
    bne !ead_apply_mult+
!ead_to_bonus:
    jmp !ead_check_bonus+

!ead_ammo_check:
    ldx cmb_type
    cmp #EGO_AMMO_FIRE
    beq !ead_elem_fire+
    cmp #EGO_AMMO_SLAY_EVIL
    beq !ead_ammo_evil+
    cmp #EGO_DRAGON_SLAYING
    beq !ead_ammo_dragon+
    cmp #EGO_AMMO_SLAY_ANIMAL
    bne !ead_done+
    lda cr_mflags,x
    and #CF_ANIMAL
    beq !ead_done+
    lda #2
    bne !ead_apply_mult+
!ead_ammo_evil:
    lda cr_mflags,x
    and #CF_EVIL
    beq !ead_done+
    lda #3
    bne !ead_apply_mult+
!ead_ammo_dragon:
    lda cr_mflags,x
    and #CF_DRAGON
    beq !ead_done+
    lda #5

!ead_apply_mult:
    tay
    lda #0
!ead_mult_loop:
    clc
    adc cmb_damage
    bcs !ead_mult_cap+
    dey
    bne !ead_mult_loop-
    beq !ead_mult_ok+
!ead_mult_cap:
    lda #255
!ead_mult_ok:
    sta cmb_damage

!ead_check_bonus:
#if (PLACE_SECRETS_EXTERNAL || PLACE_SECRETS_EMITTED) && !C64_TEST_FULL_ITEMDESC_STUB
    ldx cmb_type
    lda ead_ego_type
    cmp #EGO_FLAME_TONGUE
    beq !ead_elem_fire+
    cmp #EGO_FROST_BRAND
    bne !ead_done+
    lda #CD_FROST
    .byte $2c                       // BIT abs: skip lda #CD_FIRE
!ead_elem_fire:
    lda #CD_FIRE
    and cr_cdefense,x
    beq !ead_bonus_roll+
    // VMS moria.inc tot_dam: trunc(tdam * 1.5) against CD_FIRE / CD_FROST
    lda cmb_damage
    lsr
    clc
    adc cmb_damage
    bcc !ead_elem_ok+
    lda #255
!ead_elem_ok:
    sta cmb_damage
#else
    lda ead_ego_type
    cmp #EGO_FLAME_TONGUE
    beq !ead_bonus_roll+
    cmp #EGO_FROST_BRAND
    bne !ead_done+
!ead_elem_fire:
#endif
!ead_bonus_roll:
    lda #2
    ldx #4
    ldy #0
    jsr math_dice
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
// Input: A = ego type (masked by EGO_ID_MASK)
// Output: A = AC bonus (0 if none)
// Clobbers: X
// ============================================================
#if HAL_PLATFORM_EGO_AC_BONUS_LOCAL
ego_get_ac_bonus:
    and #EGO_ID_MASK
    cmp #EGO_RESIST
    bcs !egab_zero+
    tax
    lda ego_ac_bonus,x
    rts
!egab_zero:
    lda #0
    rts
#endif
