#importonce
// item_tables.s — immutable item type tables and base item names

// Named item type constants
.const ITEM_FLASK_OIL = 61
.const LANTERN_MAX_CHARGES = 250

// ============================================================
// Master Item Type Table — Struct-of-Arrays (25 types)
// ============================================================

// Category
it_category:
    .byte ICAT_GOLD     // 0: Gold (small)
    .byte ICAT_GOLD     // 1: Gold (large)
    .byte ICAT_WEAPON   // 2: Dagger
    .byte ICAT_WEAPON   // 3: Short sword
    .byte ICAT_WEAPON   // 4: Long sword
    .byte ICAT_WEAPON   // 5: Mace
    .byte ICAT_ARMOR    // 6: Robe
    .byte ICAT_ARMOR    // 7: Leather armor
    .byte ICAT_ARMOR    // 8: Chain mail
    .byte ICAT_SHIELD   // 9: Small shield
    .byte ICAT_HELM     // 10: Iron helm
    .byte ICAT_GLOVES   // 11: Leather gloves
    .byte ICAT_BOOTS    // 12: Leather boots
    .byte ICAT_LIGHT    // 13: Wooden torch
    .byte ICAT_LIGHT    // 14: Brass lantern
    .byte ICAT_FOOD     // 15: Ration of food
    .byte ICAT_FOOD     // 16: Slime mold
    .byte ICAT_POTION   // 17: Cure light wounds
    .byte ICAT_POTION   // 18: Speed
    .byte ICAT_POTION   // 19: Poison
    .byte ICAT_SCROLL   // 20: Light
    .byte ICAT_SCROLL   // 21: Identify
    .byte ICAT_SCROLL   // 22: Teleportation
    .byte ICAT_RING     // 23: Protection
    .byte ICAT_RING     // 24: Strength
    .byte ICAT_POTION   // 25: Cure Serious Wounds
    .byte ICAT_POTION   // 26: Restore Mana
    .byte ICAT_POTION   // 27: Heroism
    .byte ICAT_POTION   // 28: Blindness
    .byte ICAT_POTION   // 29: Confusion
    .byte ICAT_POTION   // 30: Detect Monsters
    .byte ICAT_POTION   // 31: Infravision
    .byte ICAT_SCROLL   // 32: Word of Recall
    .byte ICAT_SCROLL   // 33: Remove Curse
    .byte ICAT_SCROLL   // 34: Enchant Weapon
    .byte ICAT_SCROLL   // 35: Enchant Armor
    .byte ICAT_SCROLL   // 36: Monster Confusion
    .byte ICAT_SCROLL   // 37: Aggravate
    .byte ICAT_SCROLL   // 38: Protect from Evil
    .byte ICAT_WAND     // 39: Wand of Light
    .byte ICAT_WAND     // 40: Wand of Lightning
    .byte ICAT_WAND     // 41: Wand of Frost
    .byte ICAT_WAND     // 42: Wand of Stinking Cloud
    .byte ICAT_STAFF    // 43: Staff of Light
    .byte ICAT_STAFF    // 44: Staff of Detect Monsters
    .byte ICAT_STAFF    // 45: Staff of Teleportation
    .byte ICAT_STAFF    // 46: Staff of Cure Light Wounds
    .byte ICAT_BOOK     // 47: Beginner's Spellbook (Mage Book 1)
    .byte ICAT_BOOK     // 48: Holy Prayer Book (Priest Book 1)
    .byte ICAT_WEAPON   // 49: Short Bow
    .byte ICAT_WEAPON   // 50: Light Crossbow
    .byte ICAT_WEAPON   // 51: Sling
    .byte ICAT_WEAPON   // 52: Arrow
    .byte ICAT_WEAPON   // 53: Bolt
    .byte ICAT_WEAPON   // 54: Rock
    .byte ICAT_BOOK     // 55: Magick I (Mage Book 2)
    .byte ICAT_BOOK     // 56: Magick II (Mage Book 3)
    .byte ICAT_BOOK     // 57: The Mages Guide to Power (Mage Book 4)
    .byte ICAT_BOOK     // 58: Words of Wisdom (Priest Book 2)
    .byte ICAT_BOOK     // 59: Chants and Blessings (Priest Book 3)
    .byte ICAT_BOOK     // 60: Exorcism and Dispelling (Priest Book 4)
    .byte ICAT_LIGHT    // 61: Flask of Oil
    .byte ICAT_DIGGING  // 62: Shovel
    .byte ICAT_DIGGING  // 63: Pick

// Display character (screen codes)
it_display:
    .byte $24   // 0: '$' Gold (small)
    .byte $24   // 1: '$' Gold (large)
    .byte $2f   // 2: '/' Dagger
    .byte $2f   // 3: '/' Short sword
    .byte $2f   // 4: '/' Long sword
    .byte $2f   // 5: '/' Mace
    .byte $5b   // 6: '[' Robe
    .byte $5b   // 7: '[' Leather armor
    .byte $5b   // 8: '[' Chain mail
    .byte $29   // 9: ')' Small shield
    .byte $5d   // 10: ']' Iron helm
    .byte $5d   // 11: ']' Leather gloves
    .byte $5d   // 12: ']' Leather boots
    .byte $2a   // 13: '*' Wooden torch
    .byte $2a   // 14: '*' Brass lantern
    .byte $2c   // 15: ',' Ration of food
    .byte $2c   // 16: ',' Slime mold
    .byte $21   // 17: '!' Cure light wounds
    .byte $21   // 18: '!' Speed
    .byte $21   // 19: '!' Poison
    .byte $3f   // 20: '?' Light
    .byte $3f   // 21: '?' Identify
    .byte $3f   // 22: '?' Teleportation
    .byte $3d   // 23: '=' Protection
    .byte $3d   // 24: '=' Strength
    .byte $21   // 25: '!' Cure Serious Wounds
    .byte $21   // 26: '!' Restore Mana
    .byte $21   // 27: '!' Heroism
    .byte $21   // 28: '!' Blindness
    .byte $21   // 29: '!' Confusion
    .byte $21   // 30: '!' Detect Monsters
    .byte $21   // 31: '!' Infravision
    .byte $3f   // 32: '?' Word of Recall
    .byte $3f   // 33: '?' Remove Curse
    .byte $3f   // 34: '?' Enchant Weapon
    .byte $3f   // 35: '?' Enchant Armor
    .byte $3f   // 36: '?' Monster Confusion
    .byte $3f   // 37: '?' Aggravate
    .byte $3f   // 38: '?' Protect from Evil
    .byte $2d   // 39: '-' Wand of Light
    .byte $2d   // 40: '-' Wand of Lightning
    .byte $2d   // 41: '-' Wand of Frost
    .byte $2d   // 42: '-' Wand of Stinking Cloud
    .byte $2f   // 43: '/' Staff of Light
    .byte $2f   // 44: '/' Staff of Detect Monsters
    .byte $2f   // 45: '/' Staff of Teleportation
    .byte $2f   // 46: '/' Staff of Cure Light Wounds
    .byte $3f   // 47: '?' Beginner's Spellbook
    .byte $3f   // 48: '?' Holy Prayer Book
    .byte $1c   // 49: '}' Short Bow
    .byte $1c   // 50: '}' Light Crossbow
    .byte $1c   // 51: '}' Sling
    .byte $1b   // 52: '{' Arrow
    .byte $1b   // 53: '{' Bolt
    .byte $1b   // 54: '{' Rock
    .byte $3f   // 55: '?' Magick I
    .byte $3f   // 56: '?' Magick II
    .byte $3f   // 57: '?' The Mages Guide to Power
    .byte $3f   // 58: '?' Words of Wisdom
    .byte $3f   // 59: '?' Chants and Blessings
    .byte $3f   // 60: '?' Exorcism and Dispelling
    .byte $21   // 61: '!' Flask of Oil
    .byte $5c   // 62: '\' Shovel
    .byte $5c   // 63: '\' Pick

// Color
it_color:
    .byte COL_YELLOW    // 0: Gold (small)
    .byte COL_YELLOW    // 1: Gold (large)
    .byte COL_LGREY     // 2: Dagger
    .byte COL_LGREY     // 3: Short sword
    .byte COL_WHITE     // 4: Long sword
    .byte COL_LGREY     // 5: Mace
    .byte COL_LGREY     // 6: Robe
    .byte COL_BROWN     // 7: Leather armor
    .byte COL_GREY      // 8: Chain mail
    .byte COL_LGREY     // 9: Small shield
    .byte COL_GREY      // 10: Iron helm
    .byte COL_BROWN     // 11: Leather gloves
    .byte COL_BROWN     // 12: Leather boots
    .byte COL_YELLOW    // 13: Wooden torch
    .byte COL_ORANGE    // 14: Brass lantern
    .byte COL_BROWN     // 15: Ration of food
    .byte COL_GREEN     // 16: Slime mold
    .byte COL_WHITE     // 17: Cure light wounds
    .byte COL_LGREEN    // 18: Speed
    .byte COL_GREEN     // 19: Poison
    .byte COL_WHITE     // 20: Light
    .byte COL_LGREY     // 21: Identify
    .byte COL_CYAN      // 22: Teleportation
    .byte COL_YELLOW    // 23: Protection
    .byte COL_LRED      // 24: Strength
    .byte COL_WHITE     // 25: Cure Serious Wounds
    .byte COL_BLUE      // 26: Restore Mana
    .byte COL_LRED      // 27: Heroism
    .byte COL_GREY      // 28: Blindness
    .byte COL_PURPLE    // 29: Confusion
    .byte COL_YELLOW    // 30: Detect Monsters
    .byte COL_ORANGE    // 31: Infravision
    .byte COL_LGREY     // 32: Word of Recall
    .byte COL_CYAN      // 33: Remove Curse
    .byte COL_WHITE     // 34: Enchant Weapon
    .byte COL_WHITE     // 35: Enchant Armor
    .byte COL_LGREEN    // 36: Monster Confusion
    .byte COL_LRED      // 37: Aggravate
    .byte COL_YELLOW    // 38: Protect from Evil
    .byte COL_YELLOW    // 39: Wand of Light
    .byte COL_CYAN      // 40: Wand of Lightning
    .byte COL_BLUE      // 41: Wand of Frost
    .byte COL_GREEN     // 42: Wand of Stinking Cloud
    .byte COL_YELLOW    // 43: Staff of Light
    .byte COL_LGREEN    // 44: Staff of Detect Monsters
    .byte COL_CYAN      // 45: Staff of Teleportation
    .byte COL_WHITE     // 46: Staff of Cure Light Wounds
    .byte COL_PURPLE    // 47: Beginner's Spellbook
    .byte COL_YELLOW    // 48: Holy Prayer Book
    .byte COL_BROWN     // 49: Short Bow
    .byte COL_LGREY     // 50: Light Crossbow
    .byte COL_BROWN     // 51: Sling
    .byte COL_BROWN     // 52: Arrow
    .byte COL_LGREY     // 53: Bolt
    .byte COL_GREY      // 54: Rock
    .byte COL_PURPLE    // 55: Magick I
    .byte COL_BLUE      // 56: Magick II
    .byte COL_LRED      // 57: The Mages Guide to Power
    .byte COL_YELLOW    // 58: Words of Wisdom
    .byte COL_CYAN      // 59: Chants and Blessings
    .byte COL_WHITE     // 60: Exorcism and Dispelling
    .byte COL_ORANGE    // 61: Flask of Oil
    .byte COL_BROWN     // 62: Shovel
    .byte COL_LGREY     // 63: Pick

// Weight (in 1/10 lbs)
it_weight:
    .byte 0, 0, 12, 30, 50, 50, 20, 80, 120, 50
    .byte 30, 5, 10, 10, 30, 10, 5, 4, 4, 4
    .byte 2, 2, 2, 2, 2, 4, 4, 4, 4, 4
    .byte 4, 4, 2, 2, 2, 2, 2, 2, 2
    .byte 10, 10, 10, 10, 50, 50, 50, 50
    .byte 30, 30                            // Books (47-48)
    .byte 30, 50, 5, 2, 2, 4               // Bows, ammo
    .byte 30, 30, 30, 30, 30, 30           // Books (55-60)
    .byte 10                               // 61: Flask of Oil
    .byte 60, 50                            // 62: Shovel, 63: Pick

// Damage dice count
it_dmg_dice:
    .byte 0, 0, 1, 1, 1, 2, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0                              // Books (47-48)
    .byte 0, 0, 0, 1, 1, 1                  // Bows=0d0, Arrow=1d4, Bolt=1d5, Rock=1d2
    .byte 0, 0, 0, 0, 0, 0                  // Books (55-60)
    .byte 2                                  // 61: Flask of Oil (2d6)
    .byte 1, 1                              // 62: Shovel (1d2), 63: Pick (1d3)

// Damage dice sides
it_dmg_sides:
    .byte 0, 0, 4, 6, 8, 4, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0                              // Books (47-48)
    .byte 0, 0, 0, 4, 5, 2                  // Bows=0d0, Arrow=1d4, Bolt=1d5, Rock=1d2
    .byte 0, 0, 0, 0, 0, 0                  // Books (55-60)
    .byte 6                                  // 61: Flask of Oil (2d6)
    .byte 2, 3                              // 62: Shovel (1d2), 63: Pick (1d3)

// Base armor class
it_base_ac:
    .byte 0, 0, 0, 0, 0, 0, 2, 4, 6, 2
    .byte 1, 1, 1, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 1, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0                              // Books (47-48)
    .byte 0, 0, 0, 0, 0, 0                  // Bows, ammo: no AC
    .byte 0, 0, 0, 0, 0, 0                  // Books (55-60): no AC
    .byte 0                                  // 61: Flask of Oil: no AC
    .byte 0, 0                              // 62: Shovel, 63: Pick (no AC)

// Base cost (lo)
it_cost_lo:
    .byte <0, <0, <10, <25, <60, <45, <15, <30, <80, <20
    .byte <15, <8, <10, <2, <20, <3, <2, <50, <75, <5
    .byte <15, <50, <40, <100, <120
    .byte <100, <150, <80, <5, <5, <60, <40
    .byte <200, <80, <250, <250, <50, <5, <100
    .byte <50, <200, <250, <150, <60, <100, <300, <200
    .byte <100, <100                        // Books (47-48)
    .byte <50, <120, <10, <1, <2, <1        // Bows, ammo
    .byte <300, <500, <800, <300, <500, <800 // Books (55-60)
    .byte <10                                // 61: Flask of Oil
    .byte <15, <50                          // 62: Shovel (15gp), 63: Pick (50gp)

// Base cost (hi)
it_cost_hi:
    .byte >0, >0, >10, >25, >60, >45, >15, >30, >80, >20
    .byte >15, >8, >10, >2, >20, >3, >2, >50, >75, >5
    .byte >15, >50, >40, >100, >120
    .byte >100, >150, >80, >5, >5, >60, >40
    .byte >200, >80, >250, >250, >50, >5, >100
    .byte >50, >200, >250, >150, >60, >100, >300, >200
    .byte >100, >100                        // Books (47-48)
    .byte >50, >120, >10, >1, >2, >1        // Bows, ammo
    .byte >300, >500, >800, >300, >500, >800 // Books (55-60)
    .byte >10                                // 61: Flask of Oil
    .byte >15, >50                          // 62: Shovel (15gp), 63: Pick (50gp)

// Minimum dungeon level to appear
it_min_level:
    .byte 0, 0, 1, 1, 3, 2, 1, 2, 4, 2
    .byte 3, 1, 1, 0, 2, 0, 1, 1, 3, 1
    .byte 1, 2, 3, 4, 5, 3, 5, 4, 1, 1
    .byte 2, 2, 5, 4, 6, 6, 3, 1, 4
    .byte 3, 4, 5, 4, 3, 3, 5, 3
    .byte 2, 2                              // Books (47-48)
    .byte 2, 3, 1, 1, 2, 1                  // Bows, ammo
    .byte 4, 8, 12, 4, 8, 12                // Books (55-60)
    .byte 0                                  // 61: Flask of Oil (available immediately)
    .byte 0, 0                              // 62: Shovel, 63: Pick (available immediately)

// Missile type table — encodes ranged weapon/ammo relationships
// Only stored for types 49-54 (ranged items). Types < 49 are not ranged (return 0).
// Access via item_get_missile subroutine, NOT direct indexing.
// 0=not ranged, 1=fires arrows, 2=fires bolts, 3=fires rocks
// $81=IS arrow, $82=IS bolt, $83=IS rock
.const IT_MISSILE_BASE = 49     // First type with missile data
it_missile:
    .byte 1             // 49: Short Bow — fires arrows
    .byte 2             // 50: Light Crossbow — fires bolts
    .byte 3             // 51: Sling — fires rocks
    .byte $81           // 52: Arrow — IS arrow ammo
    .byte $82           // 53: Bolt — IS bolt ammo
    .byte $83           // 54: Rock — IS rock ammo

// item_get_missile — Get missile type for an item
// Input: X = item type ID
// Output: A = missile value (0 if not ranged)
// Preserves: X, Y
item_get_missile:
    cpx #IT_MISSILE_BASE
    bcc !igm_zero+
    lda it_missile - IT_MISSILE_BASE,x
    rts
!igm_zero:
    lda #0
    rts

// Name pointer tables
it_name_lo:
    .byte <itn_0,  <itn_1,  <itn_2,  <itn_3,  <itn_4
    .byte <itn_5,  <itn_6,  <itn_7,  <itn_8,  <itn_9
    .byte <itn_10, <itn_11, <itn_12, <itn_13, <itn_14
    .byte <itn_15, <itn_16, <itn_17, <itn_18, <itn_19
    .byte <itn_20, <itn_21, <itn_22, <itn_23, <itn_24
    .byte <itn_25, <itn_26, <itn_27, <itn_28, <itn_29
    .byte <itn_30, <itn_31, <itn_32, <itn_33, <itn_34
    .byte <itn_35, <itn_36, <itn_37, <itn_38
    .byte <itn_39, <itn_40, <itn_41, <itn_42
    .byte <itn_43, <itn_44, <itn_45, <itn_46
    .byte <itn_47, <itn_48
    .byte <itn_49, <itn_50, <itn_51, <itn_52, <itn_53, <itn_54
    .byte <itn_55, <itn_56, <itn_57, <itn_58, <itn_59, <itn_60
    .byte <itn_61, <itn_62, <itn_63
it_name_hi:
    .byte >itn_0,  >itn_1,  >itn_2,  >itn_3,  >itn_4
    .byte >itn_5,  >itn_6,  >itn_7,  >itn_8,  >itn_9
    .byte >itn_10, >itn_11, >itn_12, >itn_13, >itn_14
    .byte >itn_15, >itn_16, >itn_17, >itn_18, >itn_19
    .byte >itn_20, >itn_21, >itn_22, >itn_23, >itn_24
    .byte >itn_25, >itn_26, >itn_27, >itn_28, >itn_29
    .byte >itn_30, >itn_31, >itn_32, >itn_33, >itn_34
    .byte >itn_35, >itn_36, >itn_37, >itn_38
    .byte >itn_39, >itn_40, >itn_41, >itn_42
    .byte >itn_43, >itn_44, >itn_45, >itn_46
    .byte >itn_47, >itn_48
    .byte >itn_49, >itn_50, >itn_51, >itn_52, >itn_53, >itn_54
    .byte >itn_55, >itn_56, >itn_57, >itn_58, >itn_59, >itn_60
    .byte >itn_61, >itn_62, >itn_63

// Name strings (screen codes, null-terminated)
itn_0:  .text "Gold (small)" ; .byte 0
itn_1:  .text "Gold (large)" ; .byte 0
itn_2:  .text "Dagger" ; .byte 0
itn_3:  .text "Short Sword" ; .byte 0
itn_4:  .text "Long Sword" ; .byte 0
itn_5:  .text "Mace" ; .byte 0
itn_6:  .text "Robe" ; .byte 0
itn_7:  .text "Leather Armor" ; .byte 0
itn_8:  .text "Chain Mail" ; .byte 0
itn_9:  .text "Small Shield" ; .byte 0
itn_10: .text "Iron Helm" ; .byte 0
itn_11: .text "Leather Gloves" ; .byte 0
itn_12: .text "Leather Boots" ; .byte 0
itn_13: .text "Wooden Torch" ; .byte 0
itn_14: .text "Brass Lantern" ; .byte 0
itn_15: .text "Ration of Food" ; .byte 0
itn_16: .text "Slime Mold" ; .byte 0
itn_17: .text "Cure Light Wounds" ; .byte 0
itn_18: .text "Speed" ; .byte 0
itn_19: .text "Poison" ; .byte 0
itn_20: .text "Light" ; .byte 0
itn_21: .text "Identify" ; .byte 0
itn_22: .text "Teleportation" ; .byte 0
itn_23: .text "Protection" ; .byte 0
itn_24: .text "Strength" ; .byte 0
itn_25: .text "Cure Serious Wounds" ; .byte 0
itn_26: .text "Restore Mana" ; .byte 0
itn_27: .text "Heroism" ; .byte 0
itn_28: .text "Blindness" ; .byte 0
itn_29: .text "Confusion" ; .byte 0
itn_30: .text "Detect Monsters" ; .byte 0
itn_31: .text "Infravision" ; .byte 0
itn_32: .text "Word of Recall" ; .byte 0
itn_33: .text "Remove Curse" ; .byte 0
itn_34: .text "Enchant Weapon" ; .byte 0
itn_35: .text "Enchant Armor" ; .byte 0
itn_36: .text "Monster Confusion" ; .byte 0
itn_37: .text "Aggravate" ; .byte 0
itn_38: .text "Protect from Evil" ; .byte 0
itn_39: .text "Wand of Light" ; .byte 0
itn_40: .text "Wand of Lightning" ; .byte 0
itn_41: .text "Wand of Frost" ; .byte 0
itn_42: .text "Wand of Stinking Cloud" ; .byte 0
itn_43: .text "Staff of Light" ; .byte 0
itn_44: .text "Staff of Detect Monsters" ; .byte 0
itn_45: .text "Staff of Teleportation" ; .byte 0
itn_46: .text "Staff of Cure Light Wounds" ; .byte 0
itn_47: .text "Beginner's Spellbook" ; .byte 0
itn_48: .text "Holy Prayer Book" ; .byte 0
itn_49: .text "Short Bow" ; .byte 0
itn_50: .text "Light Crossbow" ; .byte 0
itn_51: .text "Sling" ; .byte 0
itn_52: .text "Arrow" ; .byte 0
itn_53: .text "Bolt" ; .byte 0
itn_54: .text "Rock" ; .byte 0
itn_55: .text "Magick I" ; .byte 0
itn_56: .text "Magick II" ; .byte 0
itn_57: .text "The Mages Guide" ; .byte 0
itn_58: .text "Words of Wisdom" ; .byte 0
itn_59: .text "Chants and Blessings" ; .byte 0
itn_60: .text "Exorcism" ; .byte 0
itn_61: .text "Flask of Oil" ; .byte 0
itn_62: .text "Shovel" ; .byte 0
itn_63: .text "Pick" ; .byte 0
