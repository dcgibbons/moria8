#importonce
// pick_item_type_cold.s — Depth-bucketed 340-item floor-spawn picker
//
// Module ownership:
//   owner: ChestOverlay (PICKER_IN_CHEST_OVERLAY) or DungeonGenOverlay
//     (PLATFORM_PRODUCT_OVERLAY_RUNTIME) in all 7 product builds; TestUnused
//     in C64 unit tests defining PICK_ITEM_TYPE_EXTERNAL; Default in unit tests
//     that exercise pick_item_type directly.
//   lifetime: one item-type roll during floor/chest/monster-drop spawning.
//   callers: resident pick_item_type wrapper (monster drops) and co-located
//     item_spawn_level_gen / chest_loot.

.const PIT_MAX_LEVEL = 12
.const PIT_SPAWNABLE_COUNT = 340
pit_best_lo: .byte 0
pit_best_hi: .byte 0
pit_tmp:     .byte 0

#if PICKER_IN_CHEST_OVERLAY
.segment ChestOverlay
#elif PLATFORM_PRODUCT_OVERLAY_RUNTIME
.segment DungeonGenOverlay
#endif

// 340 spawnable items (0..360 excluding gold #0..#19 and Ruined Chest #210),
// sorted ascending by min_lvl_m8 (0..12).
.var PIT_ITEMS = List()
.var PIT_TIER_END = List()        // PIT_ITEMS.size() after each depth tier
// Level 0 (25 items)
.eval PIT_ITEMS.add(ITEM_RATION_OF_FOOD, ITEM_HARD_BISCUIT, ITEM_STRIP_OF_BEEF_JERKY, ITEM_PINT_OF_FINE_ALE)
.eval PIT_ITEMS.add(ITEM_PINT_OF_FINE_WINE, ITEM_POTION_OF_SLEEP, ITEM_ICKY_GREEN_POTION_OF_SLIME_MOLD_JUICE, ITEM_LIGHT_BROWN_POTION_OF_APPLE_JUICE)
.eval PIT_ITEMS.add(ITEM_CLEAR_POTION_OF_WATER, ITEM_POTION_OF_SALT_WATER, ITEM_SCROLL_OF_TREASURE_DETECTION, ITEM_WOODEN_TORCH)
.eval PIT_ITEMS.add(ITEM_FLASK_OF_OIL, ITEM_PICK, ITEM_SHOVEL, ITEM_FILTHY_RAGS)
.eval PIT_ITEMS.add(ITEM_DAGGER_MISERICORDE, ITEM_BROKEN_DAGGER, ITEM_BROKEN_SWORD, ITEM_WOODEN_CLUB)
.eval PIT_ITEMS.add(ITEM_EMPTY_BOTTLE, ITEM_SHARDS_OF_POTTERY, ITEM_BROKEN_SET_OF_TEETH, ITEM_LARGE_BROKEN_BONE)
.eval PIT_ITEMS.add(ITEM_BROKEN_STICK)
.eval PIT_TIER_END.add(PIT_ITEMS.size())
// Level 1 (54 items)
.eval PIT_ITEMS.add(ITEM_FOOD_SLIME_MOLD, ITEM_PINT_OF_FINE_GRADE_MUSH, ITEM_POTION_OF_WEAKNESS, ITEM_POTION_OF_CURE_LIGHT_WOUNDS)
.eval PIT_ITEMS.add(ITEM_POTION_OF_BLINDNESS, ITEM_POTION_OF_CONFUSION, ITEM_POTION_OF_POISON, ITEM_POTION_OF_SLOWNESS)
.eval PIT_ITEMS.add(ITEM_POTION_OF_SUPER_HEROISM, ITEM_POTION_OF_BOLDNESS, ITEM_POTION_OF_RESIST_HEAT, ITEM_POTION_OF_RESIST_COLD)
.eval PIT_ITEMS.add(ITEM_POTION_OF_DETECT_INVISIBLE, ITEM_POTION_OF_SLOW_POISON, ITEM_SCROLL_OF_LIGHT, ITEM_SCROLL_OF_SUMMON_MONSTER)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_PHASE_DOOR, ITEM_SCROLL_OF_OBJECT_DETECTION, ITEM_SCROLL_OF_DETECT_INVISIBLE, ITEM_SCROLL_OF_AGGRAVATE)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_DARKNESS, ITEM_SCROLL_OF_BLESSING, ITEM_WAND_OF_HEAL_MONSTER, ITEM_WAND_OF_HASTE_MONSTER)
.eval PIT_ITEMS.add(ITEM_WAND_OF_SLOW_MONSTER, ITEM_WAND_OF_CONFUSE_MONSTER, ITEM_WAND_OF_MAGIC_MISSILE, ITEM_WAND_OF_CLONE_MONSTER)
.eval PIT_ITEMS.add(ITEM_WAND_OF_WONDER, ITEM_IRON_SPIKE, ITEM_ROBE, ITEM_SLING)
.eval PIT_ITEMS.add(ITEM_ARROW, ITEM_ROCK, ITEM_IRON_SHOT, ITEM_SOFT_LEATHER_CAP)
.eval PIT_ITEMS.add(ITEM_HARD_LEATHER_CAP, ITEM_LEATHER_BOOTS, ITEM_SOFT_LEATHER_BOOTS, ITEM_LEATHER_GLOVES)
.eval PIT_ITEMS.add(ITEM_MAIN_GAUCHE, ITEM_DAGGER, ITEM_DAGGER_BODKIN, ITEM_THRUSTING_SWORD_BILBO)
.eval PIT_ITEMS.add(ITEM_FOIL, ITEM_SHORT_SWORD, ITEM_CAT_O_NINE_TAILS, ITEM_JAVELIN)
.eval PIT_ITEMS.add(ITEM_RAT_SKELETON, ITEM_GIANT_CENTIPEDE_SKELETON, ITEM_HUMAN_SKELETON, ITEM_DWARF_SKELETON)
.eval PIT_ITEMS.add(ITEM_ELF_SKELETON, ITEM_GNOME_SKELETON)
.eval PIT_TIER_END.add(PIT_ITEMS.size())
// Level 2 (49 items)
.eval PIT_ITEMS.add(ITEM_MUSHROOM_OF_POISON, ITEM_MUSHROOM_OF_CONFUSION, ITEM_MUSHROOM_OF_CURE_POISON, ITEM_MUSHROOM_OF_CURE_CONFUSION)
.eval PIT_ITEMS.add(ITEM_MUSHROOM_OF_WEAKNESS, ITEM_MUSHROOM_OF_FIRST_AID, ITEM_MUSHROOM_OF_MINOR_CURES, ITEM_PIECE_OF_ELVISH_WAYBREAD_L6)
.eval PIT_ITEMS.add(ITEM_POTION_OF_CURE_CRITICAL_WOUNDS, ITEM_POTION_OF_NEUTRALIZE_POISON, ITEM_POTION_OF_INFRAVISION, ITEM_SCROLL_OF_IDENTIFY)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_MAGIC_MAPPING, ITEM_SCROLL_OF_SLEEP_MONSTER, ITEM_SCROLL_OF_TRAP_DETECTION_L5, ITEM_SCROLL_OF_DOOR_STAIR_LOCATION_L5)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_CREATE_FOOD, ITEM_WAND_OF_SLEEP_MONSTER, ITEM_STAFF_OF_TREASURE_LOCATION, ITEM_STAFF_OF_OBJECT_LOCATION)
.eval PIT_ITEMS.add(ITEM_STAFF_OF_DETECT_INVISIBLE, ITEM_STAFF_OF_DARKNESS_L5, ITEM_SPELLBOOK_BEGINNERS_MAGICK, ITEM_HOLY_BOOK_OF_PRAYERS_BEGINNERS_HANDBOOK)
.eval PIT_ITEMS.add(ITEM_BRASS_LANTERN, ITEM_SMALL_WOODEN_CHEST, ITEM_CLOAK, ITEM_LEATHER_ARMOR)
.eval PIT_ITEMS.add(ITEM_HARD_STUDDED_LEATHER, ITEM_WOVEN_CORD_ARMOR, ITEM_SHORT_BOW, ITEM_BOLT)
.eval PIT_ITEMS.add(ITEM_GAUNTLETS, ITEM_SMALL_SHIELD, ITEM_MEDIUM_LEATHER_SHIELD, ITEM_BACKSWORD)
.eval PIT_ITEMS.add(ITEM_THRUSTING_SWORD_BASELARD, ITEM_RAPIER, ITEM_MACE, ITEM_SPEAR)
.eval PIT_ITEMS.add(ITEM_RING_OF_SEARCHING, ITEM_RING_OF_TELEPORTATION, ITEM_RING_OF_SLOW_DIGESTION, ITEM_RING_OF_FEATHER_FALLING)
.eval PIT_ITEMS.add(ITEM_RING_OF_ADORNMENT_VMS_SUB14, ITEM_RING_OF_ADORNMENT_VMS_SUB15, ITEM_RING_OF_WEAKNESS, ITEM_RING_OF_AGGRAVATE_MONSTER)
.eval PIT_ITEMS.add(ITEM_RING_OF_SUSTAIN_CHARISMA)
.eval PIT_TIER_END.add(PIT_ITEMS.size())
// Level 3 (37 items)
.eval PIT_ITEMS.add(ITEM_MUSHROOM_OF_BLINDNESS, ITEM_MUSHROOM_OF_PARANOIA, ITEM_MUSHROOM_OF_CURE_BLINDNESS, ITEM_MUSHROOM_OF_CURE_PARANOIA)
.eval PIT_ITEMS.add(ITEM_MUSHROOM_OF_LIGHT_CURES, ITEM_POTION_OF_CURE_SERIOUS_WOUNDS, ITEM_POTION_OF_SPEED, ITEM_POTION_OF_LOSE_MEMORIES)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_ENCHANT_WEAPON_TO_HIT, ITEM_SCROLL_OF_ENCHANT_WEAPON_TO_DAM, ITEM_SCROLL_OF_TELEPORTATION, ITEM_SCROLL_OF_MONSTER_CONFUSION)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_TRAP_DETECTION_L12, ITEM_SCROLL_OF_TRAP_CREATION, ITEM_SCROLL_OF_TRAP_DOOR_DESTRUCTION, ITEM_SCROLL_OF_DOOR_CREATION)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_HOLY_CHANT, ITEM_WAND_OF_LIGHT, ITEM_WAND_OF_STONE_TO_MUD, ITEM_WAND_OF_TRAP_DOOR_DESTRUCTION)
.eval PIT_ITEMS.add(ITEM_STAFF_OF_LIGHT, ITEM_STAFF_OF_DOOR_STAIR_LOCATION, ITEM_STAFF_OF_TRAP_LOCATION, ITEM_STAFF_OF_SUMMONING_L10)
.eval PIT_ITEMS.add(ITEM_STAFF_OF_HASTE_MONSTERS, ITEM_STAFF_OF_SLOW_MONSTERS, ITEM_STAFF_OF_SLEEP_MONSTERS, ITEM_STAFF_OF_CURE_LIGHT_WOUNDS)
.eval PIT_ITEMS.add(ITEM_STUDDED_LEATHER_ARMOR, ITEM_SOFT_LEATHER_RING_MAIL, ITEM_HARD_LEATHER_RING_MAIL, ITEM_LIGHT_CROSSBOW)
.eval PIT_ITEMS.add(ITEM_HARD_LEATHER_BOOTS, ITEM_SMALL_METAL_SHIELD, ITEM_LONG_SWORD, ITEM_SABRE)
.eval PIT_ITEMS.add(ITEM_LANCE)
.eval PIT_TIER_END.add(PIT_ITEMS.size())
// Level 4 (31 items)
.eval PIT_ITEMS.add(ITEM_MUSHROOM_OF_HALLUCINATION, ITEM_MUSHROOM_OF_UNHEALTH, ITEM_HAIRY_MOLD_OF_POISON, ITEM_HAIRY_MOLD_OF_CURE_SERIOUS_WOUNDS)
.eval PIT_ITEMS.add(ITEM_POTION_OF_HEALING, ITEM_POTION_OF_HEROISM, ITEM_SCROLL_OF_REMOVE_CURSE, ITEM_SCROLL_OF_DOOR_STAIR_LOCATION_L15)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_SUMMON_UNDEAD, ITEM_WAND_OF_LIGHTNING, ITEM_WAND_OF_STINKING_CLOUD, ITEM_SPELLBOOK_MAGICK_I)
.eval PIT_ITEMS.add(ITEM_HOLY_BOOK_OF_PRAYERS_WORDS_OF_WISDOM, ITEM_LARGE_WOODEN_CHEST, ITEM_LEATHER_SCALE_MAIL, ITEM_LONG_BOW)
.eval PIT_ITEMS.add(ITEM_METAL_CAP, ITEM_LARGE_SHIELD, ITEM_BROAD_SWORD, ITEM_CUTLASS)
.eval PIT_ITEMS.add(ITEM_MACE_LEAD_FILLED, ITEM_AWL_PIKE, ITEM_BEAKED_AXE, ITEM_RING_OF_RESIST_FIRE)
.eval PIT_ITEMS.add(ITEM_RING_OF_RESIST_COLD, ITEM_RING_OF_PROTECTION, ITEM_AMULET_OF_ADORNMENT_VMS_SUB11, ITEM_AMULET_OF_ADORNMENT_VMS_SUB12)
.eval PIT_ITEMS.add(ITEM_AMULET_OF_SEARCHING, ITEM_AMULET_OF_TELEPORTATION, ITEM_AMULET_OF_SLOW_DIGESTION)
.eval PIT_TIER_END.add(PIT_ITEMS.size())
// Level 5 (29 items)
.eval PIT_ITEMS.add(ITEM_MUSHROOM_OF_RESTORE_CONSTITUTION, ITEM_HAIRY_MOLD_OF_HALLUCINATIONS, ITEM_HAIRY_MOLD_OF_CURE_POISON, ITEM_PIECE_OF_ELVISH_WAYBREAD_L20)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_TELEPORT_LEVEL, ITEM_SCROLL_OF_WORD_OF_RECALL, ITEM_WAND_OF_FROST, ITEM_WAND_OF_POLYMORPH)
.eval PIT_ITEMS.add(ITEM_WAND_OF_TELEPORT_AWAY, ITEM_WAND_OF_DISARMING, ITEM_STAFF_OF_TELEPORTATION, ITEM_STAFF_OF_STARLITE)
.eval PIT_ITEMS.add(ITEM_STAFF_OF_DETECT_EVIL, ITEM_ORCISH_PICK, ITEM_GNOMISH_SHOVEL, ITEM_HARD_LEATHER_ARMOR)
.eval PIT_ITEMS.add(ITEM_IRON_HELM, ITEM_MEDIUM_METAL_SHIELD, ITEM_BALL_AND_CHAIN, ITEM_BROAD_AXE)
.eval PIT_ITEMS.add(ITEM_FLAIL, ITEM_WAR_HAMMER, ITEM_FAUCHARD, ITEM_GLAIVE)
.eval PIT_ITEMS.add(ITEM_RING_OF_STUPIDITY, ITEM_RING_OF_INCREASE_DAMAGE, ITEM_RING_OF_INCREASE_TO_HIT, ITEM_AMULET_OF_WISDOM)
.eval PIT_ITEMS.add(ITEM_AMULET_OF_CHARISMA)
.eval PIT_TIER_END.add(PIT_ITEMS.size())
// Level 6 (5 items)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_ENCHANT_ARMOR, ITEM_SCROLL_OF_HOLY_PRAYER, ITEM_BASTARD_SWORD, ITEM_MORNINGSTAR)
.eval PIT_ITEMS.add(ITEM_LUCERNE_HAMMER)
.eval PIT_TIER_END.add(PIT_ITEMS.size())
// Level 7 (14 items)
.eval PIT_ITEMS.add(ITEM_HAIRY_MOLD_OF_UNHEALTH, ITEM_POTION_OF_LOSE_INTELLIGENCE, ITEM_POTION_OF_LOSE_WISDOM, ITEM_POTION_OF_UGLINESS)
.eval PIT_ITEMS.add(ITEM_POTION_OF_RESTORE_MANA, ITEM_WAND_OF_WALL_BUILDING, ITEM_STAFF_OF_CURING, ITEM_SMALL_IRON_CHEST)
.eval PIT_ITEMS.add(ITEM_SCALE_MAIL, ITEM_CHAIN_MAIL, ITEM_RUSTY_CHAIN_MAIL, ITEM_DOUBLE_CHAIN_MAIL)
.eval PIT_ITEMS.add(ITEM_KATANA, ITEM_BATTLE_AXE)
.eval PIT_TIER_END.add(PIT_ITEMS.size())
// Level 8 (22 items)
.eval PIT_ITEMS.add(ITEM_MUSHROOM_OF_RESTORING, ITEM_POTION_OF_GAIN_STRENGTH, ITEM_POTION_OF_GAIN_INTELLIGENCE, ITEM_POTION_OF_GAIN_WISDOM)
.eval PIT_ITEMS.add(ITEM_POTION_OF_CHARISMA, ITEM_POTION_OF_GAIN_CONSTITUTION, ITEM_POTION_OF_GAIN_DEXTERITY, ITEM_SCROLL_OF_PROTECT_FROM_EVIL)
.eval PIT_ITEMS.add(ITEM_WAND_OF_FIRE_BOLTS, ITEM_SPELLBOOK_MAGICK_II, ITEM_HOLY_BOOK_OF_PRAYERS_CHANTS_AND_BLESSINGS, ITEM_AUGMENTED_CHAIN_MAIL)
.eval PIT_ITEMS.add(ITEM_HEAVY_CROSSBOW, ITEM_LARGE_METAL_SHIELD, ITEM_TWO_HANDED_SWORD, ITEM_BATTLE_AXE_BALESTARIUS)
.eval PIT_ITEMS.add(ITEM_PIKE, ITEM_RING_OF_STRENGTH, ITEM_RING_OF_GAIN_DEXTERITY, ITEM_RING_OF_GAIN_CONSTITUTION)
.eval PIT_ITEMS.add(ITEM_RING_OF_GAIN_INTELLIGENCE, ITEM_AMULET_OF_RESIST_ACID)
.eval PIT_TIER_END.add(PIT_ITEMS.size())
// Level 9 (9 items)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_RECHARGING, ITEM_SCROLL_OF_GENOCIDE, ITEM_WAND_OF_LIGHTNING_BALLS, ITEM_LARGE_IRON_CHEST)
.eval PIT_ITEMS.add(ITEM_BAR_CHAIN_MAIL, ITEM_METAL_BRIGANDINE_ARMOR, ITEM_TWO_HANDED_SWORD_ESPADON, ITEM_HALBERD)
.eval PIT_ITEMS.add(ITEM_RING_OF_SEE_INVISIBLE)
.eval PIT_TIER_END.add(PIT_ITEMS.size())
// Level 10 (19 items)
.eval PIT_ITEMS.add(ITEM_POTION_OF_RESTORE_STRENGTH, ITEM_POTION_OF_RESTORE_INTELLIGENCE, ITEM_POTION_OF_RESTORE_WISDOM, ITEM_POTION_OF_RESTORE_CHARISMA)
.eval PIT_ITEMS.add(ITEM_POTION_OF_RESTORE_DEXTERITY, ITEM_POTION_OF_RESTORE_CONSTITUTION, ITEM_POTION_OF_INVULNERABILITY, ITEM_POTION_OF_RESTORE_LIFE_LEVELS)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_DISPEL_UNDEAD, ITEM_SCROLL_OF_STAR_DESTRUCTION, ITEM_WAND_OF_COLD_BALLS, ITEM_STAFF_OF_EARTHQUAKES)
.eval PIT_ITEMS.add(ITEM_STAFF_OF_SPEED, ITEM_STAFF_OF_SLOWNESS, ITEM_DWARVEN_SHOVEL, ITEM_LAMINATED_ARMOR)
.eval PIT_ITEMS.add(ITEM_COMPOSITE_BOW, ITEM_STEEL_HELM, ITEM_EXECUTIONERS_SWORD)
.eval PIT_TIER_END.add(PIT_ITEMS.size())
// Level 11 (14 items)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_RUNE_OF_PROTECTION, ITEM_WAND_OF_DRAIN_LIFE, ITEM_WAND_OF_FIRE_BALLS, ITEM_WAND_OF_ACID_BALLS)
.eval PIT_ITEMS.add(ITEM_STAFF_OF_DISPEL_EVIL, ITEM_SMALL_STEEL_CHEST, ITEM_PARTIAL_PLATE_ARMOR, ITEM_METAL_LAMELLAR_ARMOR)
.eval PIT_ITEMS.add(ITEM_SILVER_CROWN, ITEM_RING_OF_SUSTAIN_STRENGTH, ITEM_RING_OF_SUSTAIN_INTELLIGENCE, ITEM_RING_OF_SUSTAIN_WISDOM)
.eval PIT_ITEMS.add(ITEM_RING_OF_SUSTAIN_CONSTITUTION, ITEM_RING_OF_SUSTAIN_DEXTERITY)
.eval PIT_TIER_END.add(PIT_ITEMS.size())
// Level 12 (32 items)
.eval PIT_ITEMS.add(ITEM_POTION_OF_GAIN_EXPERIENCE, ITEM_POTION_OF_LEARNING, ITEM_SCROLL_OF_MASS_GENOCIDE, ITEM_SCROLL_OF_STAR_ENCHANT_WEAPON)
.eval PIT_ITEMS.add(ITEM_SCROLL_OF_CURSE_WEAPON, ITEM_SCROLL_OF_STAR_ENCHANT_ARMOR, ITEM_SCROLL_OF_CURSE_ARMOR, ITEM_STAFF_OF_SUMMONING_L50)
.eval PIT_ITEMS.add(ITEM_STAFF_OF_DESTRUCTION, ITEM_STAFF_OF_MASS_POLYMORPH, ITEM_STAFF_OF_REMOVE_CURSE, ITEM_STAFF_OF_DARKNESS_L50)
.eval PIT_ITEMS.add(ITEM_SPELLBOOK_THE_MAGES_GUIDE_TO_POWER, ITEM_HOLY_BOOK_OF_PRAYERS_EXORCISM, ITEM_DWARVEN_PICK, ITEM_LARGE_STEEL_CHEST)
.eval PIT_ITEMS.add(ITEM_PLATE_MAIL, ITEM_RIBBED_PLATE_ARMOR, ITEM_GOLDEN_CROWN, ITEM_JEWEL_ENCRUSTED_CROWN)
.eval PIT_ITEMS.add(ITEM_TWO_HANDED_SWORD_FLAMBERGE, ITEM_TWO_HANDED_SWORD_NO_DACHI, ITEM_TWO_HANDED_SWORD_ZWEIHANDER, ITEM_TWO_HANDED_GREAT_FLAIL)
.eval PIT_ITEMS.add(ITEM_RING_OF_SPEED, ITEM_RING_OF_LORDLY_PROTECTION_FIRE, ITEM_RING_OF_LORDLY_PROTECTION_ACID, ITEM_RING_OF_LORDLY_PROTECTION_COLD)
.eval PIT_ITEMS.add(ITEM_RING_OF_WOE, ITEM_RING_OF_SLAYING, ITEM_AMULET_OF_THE_MAGI, ITEM_AMULET_OF_DOOM)
.eval PIT_TIER_END.add(PIT_ITEMS.size())

pit_sorted_lo:
    .fill PIT_ITEMS.size(), (PIT_ITEMS.get(i) < ITEM_PAGE_SIZE ? PIT_ITEMS.get(i) : PIT_ITEMS.get(i) - ITEM_PAGE_SIZE)
pit_sorted_lo_end:

// Packed page bits (1 bit per sorted index: 1 = Page 1 [255..360], 0 = Page 0)
pit_sorted_hi_bits:
    .fill (PIT_ITEMS.size() + 7) >> 3, ((i*8+0 < PIT_ITEMS.size() && PIT_ITEMS.get(i*8+0) >= ITEM_PAGE_SIZE ? $01 : 0) | (i*8+1 < PIT_ITEMS.size() && PIT_ITEMS.get(i*8+1) >= ITEM_PAGE_SIZE ? $02 : 0) | (i*8+2 < PIT_ITEMS.size() && PIT_ITEMS.get(i*8+2) >= ITEM_PAGE_SIZE ? $04 : 0) | (i*8+3 < PIT_ITEMS.size() && PIT_ITEMS.get(i*8+3) >= ITEM_PAGE_SIZE ? $08 : 0) | (i*8+4 < PIT_ITEMS.size() && PIT_ITEMS.get(i*8+4) >= ITEM_PAGE_SIZE ? $10 : 0) | (i*8+5 < PIT_ITEMS.size() && PIT_ITEMS.get(i*8+5) >= ITEM_PAGE_SIZE ? $20 : 0) | (i*8+6 < PIT_ITEMS.size() && PIT_ITEMS.get(i*8+6) >= ITEM_PAGE_SIZE ? $40 : 0) | (i*8+7 < PIT_ITEMS.size() && PIT_ITEMS.get(i*8+7) >= ITEM_PAGE_SIZE ? $80 : 0))
pit_sorted_hi_bits_end:

// Cumulative 16-bit item count per compressed depth tier (0..12)
.var PIT_TIER_SIZES = List().add(25, 54, 49, 37, 31, 29, 5, 14, 22, 9, 19, 14, 32)
.assert "PIT_ITEMS holds every spawnable item", PIT_ITEMS.size(), PIT_SPAWNABLE_COUNT
.assert "One PIT_TIER_END entry per depth tier", PIT_TIER_END.size(), PIT_MAX_LEVEL + 1
.assert "One PIT_TIER_SIZES entry per depth tier", PIT_TIER_SIZES.size(), PIT_MAX_LEVEL + 1
.assert "Deepest tier bound is the whole spawnable pool", PIT_TIER_END.get(PIT_MAX_LEVEL), PIT_SPAWNABLE_COUNT
.for (var t = 0; t <= PIT_MAX_LEVEL; t++) {
    .var pit_tier_start = (t == 0) ? 0 : PIT_TIER_END.get(t - 1)
    .assert "Depth tier " + t + " item count", PIT_TIER_END.get(t) - pit_tier_start, PIT_TIER_SIZES.get(t)
    // pick_item_type_overlay rerolls within one tier with 8-bit rng_range.
    .assert "Depth tier " + t + " span is 1..255", PIT_TIER_SIZES.get(t) >= 1 && PIT_TIER_SIZES.get(t) <= 255, true
}
pit_level_bounds_lo:
    .fill PIT_MAX_LEVEL + 1, <PIT_TIER_END.get(i)
pit_level_bounds_lo_end:
pit_level_bounds_hi:
    .fill PIT_MAX_LEVEL + 1, >PIT_TIER_END.get(i)
pit_level_bounds_hi_end:
pit_bit_masks:
    .byte $01, $02, $04, $08, $10, $20, $40, $80

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
pick_item_type_overlay:
#else
pick_item_type:
#endif
    // Compressed level: eff_level = min((dlvl + 3) / 4, PIT_MAX_LEVEL).
    lda zp_player_dlvl
    clc
    adc #3
    lsr
    lsr
    cmp #PIT_MAX_LEVEL + 1
    bcc !pit_level_ok+
    lda #PIT_MAX_LEVEL
!pit_level_ok:
    tay                          // Y = eff_level (preserved by rng_range)

    // Great item, 1 in 12 (none at town level 0)
    lda #12
    jsr rng_range                // [0, 11]
    bne !pit_no_great+
    tya
    beq !pit_no_great+
    lda #PIT_MAX_LEVEL
    jsr rng_range                // [0, 11]
    clc
    adc #1
    sta zp_temp1                 // randint(12)
    tya
    asl
    asl
    sta zp_temp0                 // eff * 4
    asl                          // C clear: eff * 8 <= 96
    adc zp_temp0                 // eff * 12 (<= 144)
    ldy #0
    sec
!pit_great_div:
    iny                          // quotient + 1
    sbc zp_temp1
    bcs !pit_great_div-
    cpy #PIT_MAX_LEVEL + 1
    bcc !pit_no_great+
    ldy #PIT_MAX_LEVEL
!pit_no_great:

    // 16-bit pool_size = pit_level_bounds[eff_level] -> zp_temp0/1
    lda pit_level_bounds_lo,y
    sta zp_temp0
    lda pit_level_bounds_hi,y
    sta zp_temp1

    // 50/50 coin flip: flat pick vs best-of-3
    lda #2
    jsr rng_range
    bne !pit_best_of_3+

    jsr rng_range_word           // [0, pool_size-1] in zp_temp2/3

!pit_return_idx:
    // Decode 16-bit index (zp_temp2=lo, zp_temp3=hi) into (item_cur_page, A=slot_lo)
    lda zp_temp2
    and #$07
    tay
    lda zp_temp2
    sta pit_tmp
    lda zp_temp3
    lsr
    ror pit_tmp
    lsr
    ror pit_tmp
    lsr
    ror pit_tmp
    ldx pit_tmp
    lda pit_sorted_hi_bits,x
    and pit_bit_masks,y
    beq !pit_page0+
    lda #ITEM_PAGE_BIT
    bne !pit_set_page+
!pit_page0:
    lda #0
!pit_set_page:
    sta item_cur_page
    ldx zp_temp2
    lda zp_temp3
    bne !pit_hi_slice+
    lda pit_sorted_lo,x
    rts
!pit_hi_slice:
    lda pit_sorted_lo + 256,x
    rts

!pit_best_of_3:
    jsr rng_range_word
    lda zp_temp2
    sta pit_best_lo
    lda zp_temp3
    sta pit_best_hi

    ldy #2
!pit_bo3_loop:
    sty pit_tmp
    jsr rng_range_word
    lda pit_best_lo
    cmp zp_temp2
    lda pit_best_hi
    sbc zp_temp3
    bcs !pit_bo3_keep+
    lda zp_temp2
    sta pit_best_lo
    lda zp_temp3
    sta pit_best_hi
!pit_bo3_keep:
    ldy pit_tmp
    dey
    bne !pit_bo3_loop-

    // Find winner's depth tier X (0..PIT_MAX_LEVEL) where pit_best < bounds[X]
    ldx #0
!pit_find_tier:
    lda pit_best_lo
    cmp pit_level_bounds_lo,x
    lda pit_best_hi
    sbc pit_level_bounds_hi,x
    bcc !pit_found_tier+
    inx
    cpx #PIT_MAX_LEVEL
    bcc !pit_find_tier-
!pit_found_tier:
    txa
    beq !pit_reroll_l0+
    stx pit_tmp
    lda pit_level_bounds_lo,x
    sec
    sbc pit_level_bounds_lo - 1,x   // Every tier span <= 55 < 256
    jsr rng_range
    ldx pit_tmp
    clc
    adc pit_level_bounds_lo - 1,x
    sta zp_temp2
    lda pit_level_bounds_hi - 1,x
    adc #0
    sta zp_temp3
    jmp !pit_return_idx-

!pit_reroll_l0:
    lda pit_level_bounds_lo
    jsr rng_range
    sta zp_temp2
    lda #0
    sta zp_temp3
    jmp !pit_return_idx-

#if HAL_PLATFORM_PICK_ITEM_RESIDENT_ITEMS_SEGMENT
:ResidentItemsSegment()
#elif HAL_PLATFORM_PICK_ITEM_IN_GEN_OVERLAY
.segment Default
#endif

#if HAL_PLATFORM_PICK_ITEM_PLUS4_BANK_RAM
pick_item_type:
    lda current_overlay
#if PICKER_IN_CHEST_OVERLAY
    cmp #OVL_CHEST
#else
    cmp #OVL_DUNGEON_GEN
#endif
    beq !pit_overlay_loaded+

#if PICKER_IN_CHEST_OVERLAY
    ldx #OVL_CHEST - 1
#else
    ldx #OVL_DUNGEON_GEN - 1
#endif
    jsr overlay_load_disk        // asks for the program disk until it loads
#if PICKER_IN_CHEST_OVERLAY
    lda #OVL_CHEST
#else
    lda #OVL_DUNGEON_GEN
#endif
    sta current_overlay

!pit_overlay_loaded:
    sei
    jsr plus4_bank_ram
    jsr pick_item_type_overlay
    pha
    jsr plus4_bank_ram
    cli
    pla
    rts
#elif PLATFORM_PRODUCT_OVERLAY_RUNTIME
pick_item_type:
#if PICKER_IN_CHEST_OVERLAY
    lda #OVL_CHEST
#else
    lda #OVL_DUNGEON_GEN
#endif
    jsr overlay_load
    bcc !pit_overlay_loaded+
    .assert "Dagger fallback item lives on Page 1", ITEM_PAGE_DAGGER, ITEM_PAGE_BIT
    lda #ITEM_PAGE_DAGGER
    sta item_cur_page
    lda #ITEM_SLOT_DAGGER       // Fallback to Dagger on media error.
    rts
!pit_overlay_loaded:
    sei
    :BankOutKernal()
    jsr pick_item_type_overlay
    pha
    :BankInKernal()
    cli
    pla
    rts
#endif

.assert "pit_sorted_lo size (excludes gold and ruined chest)", pit_sorted_lo_end - pit_sorted_lo, PIT_SPAWNABLE_COUNT
.assert "pit_sorted_hi_bits size", pit_sorted_hi_bits_end - pit_sorted_hi_bits, (PIT_SPAWNABLE_COUNT + 7) >> 3
.assert "pit_level_bounds_lo size", pit_level_bounds_lo_end - pit_level_bounds_lo, PIT_MAX_LEVEL + 1
.assert "pit_level_bounds_hi size", pit_level_bounds_hi_end - pit_level_bounds_hi, PIT_MAX_LEVEL + 1
#if !PICK_ITEM_TYPE_EXTERNAL
.assert "pick_item_type entry stays resident", pick_item_type < $e000, true
#else
.assert "pick_item_type parked in TestUnused window", pick_item_type >= $e100 && pick_item_type <= $fff9, true
#endif
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
.assert "pick_item_type overlay impl lives in the $E000 overlay window", pick_item_type_overlay >= BANKED_DATA_BASE && pick_item_type_overlay <= BANKED_DATA_END, true
#endif
