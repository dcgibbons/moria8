#importonce
// item_tables.s — immutable item type tables and base item names

// Named item type constants
.const ITEM_FLASK_OIL = 61
.const LANTERN_MAX_CHARGES = 250

// ============================================================
// Master Item Type Table — Struct-of-Arrays
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
    .byte ICAT_WEAPON   // 64: Main Gauche
    .byte ICAT_ARMOR    // 65: Studded Leather Armor
    .byte ICAT_WEAPON   // 66: Rapier
    .byte ICAT_WEAPON   // 67: Broad Sword
    .byte ICAT_WEAPON   // 68: Bastard Sword
    .byte ICAT_WEAPON   // 69: Two-Handed Sword
    .byte ICAT_WEAPON   // 70: Scimitar
    .byte ICAT_WEAPON   // 71: Battle Axe
    .byte ICAT_WEAPON   // 72: War Hammer
    .byte ICAT_WEAPON   // 73: Morningstar
    .byte ICAT_WEAPON   // 74: Spear
    .byte ICAT_WEAPON   // 75: Pike
    .byte ICAT_WEAPON   // 76: Halberd
    .byte ICAT_WEAPON   // 77: Quarterstaff

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
    .byte $2f   // 64: '/' Main Gauche
    .byte $5b   // 65: '[' Studded Leather Armor
    .byte $2f   // 66: '/' Rapier
    .byte $2f   // 67: '/' Broad Sword
    .byte $2f   // 68: '/' Bastard Sword
    .byte $2f   // 69: '/' Two-Handed Sword
    .byte $2f   // 70: '/' Scimitar
    .byte $2f   // 71: '/' Battle Axe
    .byte $2f   // 72: '/' War Hammer
    .byte $2f   // 73: '/' Morningstar
    .byte $2f   // 74: '/' Spear
    .byte $2f   // 75: '/' Pike
    .byte $2f   // 76: '/' Halberd
    .byte $2f   // 77: '/' Quarterstaff

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
    .byte COL_LGREY     // 64: Main Gauche
    .byte COL_BROWN     // 65: Studded Leather Armor
    .byte COL_LGREY     // 66: Rapier
    .byte COL_WHITE     // 67: Broad Sword
    .byte COL_WHITE     // 68: Bastard Sword
    .byte COL_LGREY     // 69: Two-Handed Sword
    .byte COL_WHITE     // 70: Scimitar
    .byte COL_LGREY     // 71: Battle Axe
    .byte COL_LGREY     // 72: War Hammer
    .byte COL_WHITE     // 73: Morningstar
    .byte COL_LGREY     // 74: Spear
    .byte COL_LGREY     // 75: Pike
    .byte COL_LGREY     // 76: Halberd
    .byte COL_BROWN     // 77: Quarterstaff

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
    .byte 30, 90                            // 64-65: new weapon/armor
    .byte 40, 75, 140, 200                  // 66-69: expanded swords
    .byte 40, 170, 120, 150                 // 70-73: expanded hafted/axe
    .byte 50, 160, 190, 40                  // 74-77: polearms/staff

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
    .byte 1, 0                              // 64-65: new weapon/armor
    .byte 1, 2, 3, 3                        // 66-69: expanded swords
    .byte 1, 3, 3, 2                        // 70-73: expanded hafted/axe
    .byte 1, 2, 3, 1                        // 74-77: polearms/staff

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
    .byte 5, 0                              // 64-65: new weapon/armor
    .byte 6, 5, 4, 6                        // 66-69: expanded swords
    .byte 8, 4, 3, 6                        // 70-73: expanded hafted/axe
    .byte 6, 5, 4, 9                        // 74-77: polearms/staff

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
    .byte 0, 5                              // 64-65: new weapon/armor
    .byte 0, 0, 0, 0                        // 66-69: expanded swords
    .byte 0, 0, 0, 0                        // 70-73: expanded hafted/axe
    .byte 0, 0, 0, 0                        // 74-77: polearms/staff

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
    .byte <25, <75
    .byte <42, <70, <120, <180
    .byte <50, <120, <90, <100
    .byte <36, <100, <150, <20

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
    .byte >25, >75
    .byte >42, >70, >120, >180
    .byte >50, >120, >90, >100
    .byte >36, >100, >150, >20

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
    .byte 1, 3                              // 64-65: new weapon/armor
    .byte 2, 4, 6, 8                        // 66-69: expanded swords
    .byte 3, 7, 5, 6                        // 70-73: expanded hafted/axe
    .byte 2, 8, 9, 1                        // 74-77: polearms/staff

// Missile type table — encodes ranged weapon/ammo relationships
// Only stored for types 49-54 (ranged items). Types < 49 are not ranged (return 0).
// Access via item_get_missile subroutine, NOT direct indexing.
// 0=not ranged, 1=fires arrows, 2=fires bolts, 3=fires rocks
// $81=IS arrow, $82=IS bolt, $83=IS rock
.const IT_MISSILE_BASE = 49     // First type with missile data
.const IT_MISSILE_END  = 55     // One past last type with missile data
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
    cpx #IT_MISSILE_END
    bcs !igm_zero+
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
    .byte <itn_64, <itn_65
    .byte <itn_66, <itn_67, <itn_68, <itn_69
    .byte <itn_70, <itn_71, <itn_72, <itn_73
    .byte <itn_74, <itn_75, <itn_76, <itn_77
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
    .byte >itn_64, >itn_65
    .byte >itn_66, >itn_67, >itn_68, >itn_69
    .byte >itn_70, >itn_71, >itn_72, >itn_73
    .byte >itn_74, >itn_75, >itn_76, >itn_77
it_name_hi_end:

// Tokenized item-name string pool.
// Bytes below $80 are literal screen codes; bytes $80-$95 expand through
// item_name_token_lo/hi. item_get_name_ptr decodes streams into its resident
// item-name buffer.
.const ITOK_SCROLL_OF_ART     = $80
.const ITOK_POTION_SUFFIX     = $81
.const ITOK_OF                = $82
.const ITOK_SCROLL            = $83
.const ITOK_LIGHT             = $84
.const ITOK_WAND              = $85
.const ITOK_A_SILVER          = $86
.const ITOK_LEATHER           = $87
.const ITOK_DETECT_MONSTERS   = $88
.const ITOK_STAFF             = $89
.const ITOK_RING_SUFFIX       = $8a
.const ITOK_TELEPORTATION     = $8b
.const ITOK_WOUNDS_SUFFIX     = $8c
.const ITOK_MAGICK            = $8d
.const ITOK_GOLD              = $8e
.const ITOK_CONFUSION         = $8f
.const ITOK_CURE              = $90
.const ITOK_BEGINNERS         = $91
.const ITOK_ENCHANT           = $92
.const ITOK_A_COPPER          = $93
.const ITOK_CLOUD_SUFFIX      = $94
.const ITOK_SWORD_SUFFIX      = $95
.const ITOK_A_SPACE           = $96
.const ITOK_AN_SPACE          = $97
.const ITEM_NAME_TOKEN_COUNT  = $18

item_name_token_lo:
    .byte <itok_scroll_of_art, <itok_potion_suffix, <itok_of, <itok_scroll
    .byte <itok_light, <itok_wand, <itok_a_silver, <itok_leather
    .byte <itok_detect_monsters, <itok_staff, <itok_ring_suffix, <itok_teleportation
    .byte <itok_wounds_suffix, <itok_magick, <itok_gold, <itok_confusion
    .byte <itok_cure, <itok_beginners, <itok_enchant, <itok_a_copper
    .byte <itok_cloud_suffix, <itok_sword_suffix, <itok_a_space, <itok_an_space
item_name_token_hi:
    .byte >itok_scroll_of_art, >itok_potion_suffix, >itok_of, >itok_scroll
    .byte >itok_light, >itok_wand, >itok_a_silver, >itok_leather
    .byte >itok_detect_monsters, >itok_staff, >itok_ring_suffix, >itok_teleportation
    .byte >itok_wounds_suffix, >itok_magick, >itok_gold, >itok_confusion
    .byte >itok_cure, >itok_beginners, >itok_enchant, >itok_a_copper
    .byte >itok_cloud_suffix, >itok_sword_suffix, >itok_a_space, >itok_an_space

itok_scroll_of_art:   .text "a Scroll of " ; .byte 0
itok_potion_suffix:   .text " Potion" ; .byte 0
itok_of:              .text " of " ; .byte 0
itok_scroll:          .text "Scroll" ; .byte 0
itok_light:           .text "Light" ; .byte 0
itok_wand:            .text "Wand" ; .byte 0
itok_a_silver:        .text "a Silver" ; .byte 0
itok_leather:         .text "Leather " ; .byte 0
itok_detect_monsters: .text "Detect Monsters" ; .byte 0
itok_staff:           .text "Staff" ; .byte 0
itok_ring_suffix:     .text " Ring" ; .byte 0
itok_teleportation:   .text "Teleportation" ; .byte 0
itok_wounds_suffix:   .text " Wounds" ; .byte 0
itok_magick:          .text "Magick" ; .byte 0
itok_gold:            .text "Gold" ; .byte 0
itok_confusion:       .text "Confusion" ; .byte 0
itok_cure:            .text "Cure " ; .byte 0
itok_beginners:       .text "Beginners" ; .byte 0
itok_enchant:         .text "Enchant " ; .byte 0
itok_a_copper:        .text "a Copper" ; .byte 0
itok_cloud_suffix:    .text " Cloud" ; .byte 0
itok_sword_suffix:    .text " Sword" ; .byte 0
itok_a_space:         .text "a " ; .byte 0
itok_an_space:        .text "an " ; .byte 0

// Name streams (screen codes plus item-name tokens, null-terminated)
itn_0:  .byte ITOK_GOLD ; .text " (small)" ; .byte 0
itn_1:  .byte ITOK_GOLD ; .text " (large)" ; .byte 0
itn_2:  .text "Dagger" ; .byte 0
itn_3:  .text "Short" ; .byte ITOK_SWORD_SUFFIX ; .byte 0
itn_4:  .text "Long" ; .byte ITOK_SWORD_SUFFIX ; .byte 0
itn_5:  .text "Mace" ; .byte 0
itn_6:  .text "Robe" ; .byte 0
itn_7:  .byte ITOK_LEATHER ; .text "Armor" ; .byte 0
itn_8:  .text "Chain Mail" ; .byte 0
itn_9:  .text "Small Shield" ; .byte 0
itn_10: .text "Iron Helm" ; .byte 0
itn_11: .byte ITOK_LEATHER ; .text "Gloves" ; .byte 0
itn_12: .byte ITOK_LEATHER ; .text "Boots" ; .byte 0
itn_13: .text "Wooden Torch" ; .byte 0
itn_14: .text "Brass Lantern" ; .byte 0
itn_15: .text "Ration" ; .byte ITOK_OF ; .text "Food" ; .byte 0
itn_16: .text "Slime Mold" ; .byte 0
itn_17: .byte ITOK_CURE ; .byte ITOK_LIGHT ; .byte ITOK_WOUNDS_SUFFIX ; .byte 0
itn_18: .text "Speed" ; .byte 0
itn_19: .text "Poison" ; .byte 0
itn_20: .byte ITOK_LIGHT ; .byte 0
itn_21: .text "Identify" ; .byte 0
itn_22: .byte ITOK_TELEPORTATION ; .byte 0
itn_23: .text "Protection" ; .byte 0
itn_24: .text "Strength" ; .byte 0
itn_25: .byte ITOK_CURE ; .text "Serious" ; .byte ITOK_WOUNDS_SUFFIX ; .byte 0
itn_26: .text "Restore Mana" ; .byte 0
itn_27: .text "Heroism" ; .byte 0
itn_28: .text "Blindness" ; .byte 0
itn_29: .byte ITOK_CONFUSION ; .byte 0
itn_30: .byte ITOK_DETECT_MONSTERS ; .byte 0
itn_31: .text "Infravision" ; .byte 0
itn_32: .text "Word" ; .byte ITOK_OF ; .text "Recall" ; .byte 0
itn_33: .text "Remove Curse" ; .byte 0
itn_34: .byte ITOK_ENCHANT ; .text "Weapon" ; .byte 0
itn_35: .byte ITOK_ENCHANT ; .text "Armor" ; .byte 0
itn_36: .text "Monster " ; .byte ITOK_CONFUSION ; .byte 0
itn_37: .text "Aggravate" ; .byte 0
itn_38: .text "Protect from Evil" ; .byte 0
itn_39: .byte ITOK_WAND ; .byte ITOK_OF ; .byte ITOK_LIGHT ; .byte 0
itn_40: .byte ITOK_WAND ; .byte ITOK_OF ; .byte ITOK_LIGHT ; .text "ning" ; .byte 0
itn_41: .byte ITOK_WAND ; .byte ITOK_OF ; .text "Frost" ; .byte 0
itn_42: .byte ITOK_WAND ; .byte ITOK_OF ; .text "Stinking" ; .byte ITOK_CLOUD_SUFFIX ; .byte 0
itn_43: .byte ITOK_STAFF ; .byte ITOK_OF ; .byte ITOK_LIGHT ; .byte 0
itn_44: .byte ITOK_STAFF ; .byte ITOK_OF ; .byte ITOK_DETECT_MONSTERS ; .byte 0
itn_45: .byte ITOK_STAFF ; .byte ITOK_OF ; .byte ITOK_TELEPORTATION ; .byte 0
itn_46: .byte ITOK_STAFF ; .byte ITOK_OF ; .byte ITOK_CURE ; .byte ITOK_LIGHT ; .byte ITOK_WOUNDS_SUFFIX ; .byte 0
itn_47: .byte ITOK_BEGINNERS ; .text "-" ; .byte ITOK_MAGICK ; .byte 0
itn_48: .byte ITOK_BEGINNERS ; .text " Handbook" ; .byte 0
itn_49: .text "Short Bow" ; .byte 0
itn_50: .byte ITOK_LIGHT ; .text " Crossbow" ; .byte 0
itn_51: .text "Sling" ; .byte 0
itn_52: .text "Arrow" ; .byte 0
itn_53: .text "Bolt" ; .byte 0
itn_54: .text "Rock" ; .byte 0
itn_55: .byte ITOK_MAGICK ; .text " I" ; .byte 0
itn_56: .byte ITOK_MAGICK ; .text " II" ; .byte 0
itn_57: .text "The Mages Guide to Power" ; .byte 0
itn_58: .text "Words" ; .byte ITOK_OF ; .text "Wisdom" ; .byte 0
itn_59: .text "Chants and Blessings" ; .byte 0
itn_60: .text "Exorcism" ; .byte 0
itn_61: .text "Flask" ; .byte ITOK_OF ; .text "Oil" ; .byte 0
itn_62: .text "Shovel" ; .byte 0
itn_63: .text "Pick" ; .byte 0
itn_64: .text "Main Gauche" ; .byte 0
itn_65: .text "Studded " ; .byte ITOK_LEATHER ; .text "Armor" ; .byte 0
itn_66: .text "Rapier" ; .byte 0
itn_67: .text "Broad" ; .byte ITOK_SWORD_SUFFIX ; .byte 0
itn_68: .text "Bastard" ; .byte ITOK_SWORD_SUFFIX ; .byte 0
itn_69: .text "Two-Handed" ; .byte ITOK_SWORD_SUFFIX ; .byte 0
itn_70: .text "Scimitar" ; .byte 0
itn_71: .text "Battle Axe" ; .byte 0
itn_72: .text "War Hammer" ; .byte 0
itn_73: .text "Morningstar" ; .byte 0
itn_74: .text "Spear" ; .byte 0
itn_75: .text "Pike" ; .byte 0
itn_76: .text "Halberd" ; .byte 0
itn_77: .text "Quarterstaff" ; .byte 0
