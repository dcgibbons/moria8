// item.s — Item data structures, floor items, inventory, and gold spawning
//
// Phase 6.1: Master item type table (SoA), floor item table at $CF00,
// inventory/equipment table, and subroutines for managing both.
// Gold spawning on dungeon floors.

// ============================================================
// Item Category Constants
// ============================================================
.const ICAT_NONE     = 0
.const ICAT_GOLD     = 1
.const ICAT_WEAPON   = 2
.const ICAT_ARMOR    = 3
.const ICAT_SHIELD   = 4
.const ICAT_HELM     = 5
.const ICAT_GLOVES   = 6
.const ICAT_BOOTS    = 7
.const ICAT_LIGHT    = 8
.const ICAT_FOOD     = 9
.const ICAT_POTION   = 10
.const ICAT_SCROLL   = 11
.const ICAT_RING     = 12
.const ICAT_BOOK     = 13
.const ICAT_WAND     = 14
.const ICAT_STAFF    = 15

// Item Instance Flags
.const IF_CURSED     = $01
.const IF_IDENTIFIED = $02
.const IF_TRIED      = $04

// Floor Item Constants
.const MAX_FLOOR_ITEMS = 32
.const FI_EMPTY        = $ff

// Equipment Slot Constants (indices 22-29 in unified table)
.const EQUIP_WEAPON = 22
.const EQUIP_BODY   = 23
.const EQUIP_SHIELD = 24
.const EQUIP_HEAD   = 25
.const EQUIP_HANDS  = 26
.const EQUIP_FEET   = 27
.const EQUIP_LIGHT  = 28
.const EQUIP_RING   = 29

// Inventory Constants
.const MAX_INV_SLOTS   = 22
.const MAX_EQUIP_SLOTS = 8
.const TOTAL_INV_SLOTS = 30

// Master Item Type Count
.const ITEM_TYPE_COUNT = 61

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

// Name strings (screen codes, null-terminated)
itn_0:  .text "GOLD (SMALL)" ; .byte 0
itn_1:  .text "GOLD (LARGE)" ; .byte 0
itn_2:  .text "DAGGER" ; .byte 0
itn_3:  .text "SHORT SWORD" ; .byte 0
itn_4:  .text "LONG SWORD" ; .byte 0
itn_5:  .text "MACE" ; .byte 0
itn_6:  .text "ROBE" ; .byte 0
itn_7:  .text "LEATHER ARMOR" ; .byte 0
itn_8:  .text "CHAIN MAIL" ; .byte 0
itn_9:  .text "SMALL SHIELD" ; .byte 0
itn_10: .text "IRON HELM" ; .byte 0
itn_11: .text "LEATHER GLOVES" ; .byte 0
itn_12: .text "LEATHER BOOTS" ; .byte 0
itn_13: .text "WOODEN TORCH" ; .byte 0
itn_14: .text "BRASS LANTERN" ; .byte 0
itn_15: .text "RATION OF FOOD" ; .byte 0
itn_16: .text "SLIME MOLD" ; .byte 0
itn_17: .text "CURE LIGHT WOUNDS" ; .byte 0
itn_18: .text "SPEED" ; .byte 0
itn_19: .text "POISON" ; .byte 0
itn_20: .text "LIGHT" ; .byte 0
itn_21: .text "IDENTIFY" ; .byte 0
itn_22: .text "TELEPORTATION" ; .byte 0
itn_23: .text "PROTECTION" ; .byte 0
itn_24: .text "STRENGTH" ; .byte 0
itn_25: .text "CURE SERIOUS WOUNDS" ; .byte 0
itn_26: .text "RESTORE MANA" ; .byte 0
itn_27: .text "HEROISM" ; .byte 0
itn_28: .text "BLINDNESS" ; .byte 0
itn_29: .text "CONFUSION" ; .byte 0
itn_30: .text "DETECT MONSTERS" ; .byte 0
itn_31: .text "INFRAVISION" ; .byte 0
itn_32: .text "WORD OF RECALL" ; .byte 0
itn_33: .text "REMOVE CURSE" ; .byte 0
itn_34: .text "ENCHANT WEAPON" ; .byte 0
itn_35: .text "ENCHANT ARMOR" ; .byte 0
itn_36: .text "MONSTER CONFUSION" ; .byte 0
itn_37: .text "AGGRAVATE" ; .byte 0
itn_38: .text "PROTECT FROM EVIL" ; .byte 0
itn_39: .text "WAND OF LIGHT" ; .byte 0
itn_40: .text "WAND OF LIGHTNING" ; .byte 0
itn_41: .text "WAND OF FROST" ; .byte 0
itn_42: .text "WAND OF STINKING CLOUD" ; .byte 0
itn_43: .text "STAFF OF LIGHT" ; .byte 0
itn_44: .text "STAFF OF DETECT MONSTERS" ; .byte 0
itn_45: .text "STAFF OF TELEPORTATION" ; .byte 0
itn_46: .text "STAFF OF CURE LIGHT WOUNDS" ; .byte 0
itn_47: .text "BEGINNER'S SPELLBOOK" ; .byte 0
itn_48: .text "HOLY PRAYER BOOK" ; .byte 0
itn_49: .text "SHORT BOW" ; .byte 0
itn_50: .text "LIGHT CROSSBOW" ; .byte 0
itn_51: .text "SLING" ; .byte 0
itn_52: .text "ARROW" ; .byte 0
itn_53: .text "BOLT" ; .byte 0
itn_54: .text "ROCK" ; .byte 0
itn_55: .text "MAGICK I" ; .byte 0
itn_56: .text "MAGICK II" ; .byte 0
itn_57: .text "THE MAGES GUIDE" ; .byte 0
itn_58: .text "WORDS OF WISDOM" ; .byte 0
itn_59: .text "CHANTS AND BLESSINGS" ; .byte 0
itn_60: .text "EXORCISM" ; .byte 0

// ============================================================
// Floor Item Table — 32 slots x 8 arrays at $CF00 (256 bytes)
// ============================================================
.label fi_item_id = FLOOR_ITEM_BASE + 0       // $CF00: item type (0-24), $FF = empty
.label fi_x       = FLOOR_ITEM_BASE + 32      // $CF20: map X
.label fi_y       = FLOOR_ITEM_BASE + 64      // $CF40: map Y
.label fi_qty     = FLOOR_ITEM_BASE + 96      // $CF60: quantity / gold amount
.label fi_p1      = FLOOR_ITEM_BASE + 128     // $CF80: enchantment / charges
.label fi_flags   = FLOOR_ITEM_BASE + 160     // $CFA0: instance flags
.label fi_ego     = FLOOR_ITEM_BASE + 192     // $CFC0: ego type (0=none)
.label fi_qty_hi  = FLOOR_ITEM_BASE + 224     // $CFE0: gold qty high byte

// ============================================================
// Inventory Table — 30 slots (22 carried + 8 equipped)
// ============================================================
inv_item_id: .fill TOTAL_INV_SLOTS, FI_EMPTY
inv_qty:     .fill TOTAL_INV_SLOTS, 0
inv_p1:      .fill TOTAL_INV_SLOTS, 0
inv_flags:   .fill TOTAL_INV_SLOTS, 0
inv_ego:     .fill TOTAL_INV_SLOTS, 0

// ============================================================
// Scratch variables
// ============================================================
fi_add_x:   .byte 0       // Position for floor_item_add
fi_add_y:   .byte 0
fi_add_id:  .byte 0       // Item type ID
fi_add_qty: .byte 0       // Quantity / gold amount
fi_add_qty_hi: .byte 0    // Gold qty high byte (auto-reset after add)
fi_add_p1:  .byte 0       // Enchantment / charges
fi_add_ego: .byte 0       // Ego type (0=none)
isl_target: .byte 0       // item_spawn_level loop target
isl_idx:    .byte 0       // item_spawn_level loop counter
ici_count:  .byte 0       // inv_count_items scratch counter (RP14-7)

// ============================================================
// Subroutines
// ============================================================

// item_init_floor — Clear all 32 floor item slots
// Sets all fi_item_id to $FF, zp_item_count = 0
// Clobbers: A, X
item_init_floor:
    ldx #MAX_FLOOR_ITEMS - 1
    lda #FI_EMPTY
!iif_loop:
    sta fi_item_id,x
    dex
    bpl !iif_loop-
    lda #0
    sta zp_item_count
    rts

// item_init_inventory — Clear all 30 inventory/equipment slots
// Clobbers: A, X
item_init_inventory:
    ldx #TOTAL_INV_SLOTS - 1
    lda #FI_EMPTY
!iiv_loop:
    sta inv_item_id,x
    dex
    bpl !iiv_loop-
    rts

// floor_item_add — Add an item to the floor item table
// Input: fi_add_x, fi_add_y, fi_add_id, fi_add_qty, fi_add_p1, fi_add_flags
// Output: carry set = success (X = slot), carry clear = table full
// Clobbers: A, X, Y, zp_ptr0
floor_item_add:
    // Find first empty slot
    ldx #0
!fia_scan:
    cpx #MAX_FLOOR_ITEMS
    bcs !fia_full+
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !fia_found+
    inx
    jmp !fia_scan-

!fia_found:
    // Write all fields
    lda fi_add_id
    sta fi_item_id,x
    lda fi_add_x
    sta fi_x,x
    lda fi_add_y
    sta fi_y,x
    lda fi_add_qty
    sta fi_qty,x
    lda fi_add_p1
    sta fi_p1,x
    lda fi_add_flags
    sta fi_flags,x
    lda fi_add_ego
    sta fi_ego,x
    lda fi_add_qty_hi
    sta fi_qty_hi,x
    lda #0
    sta fi_add_qty_hi       // Auto-reset for non-gold callers

    // Set FLAG_HAS_ITEM on map tile at (x, y)
    stx zp_temp4                // Save slot index
    ldy fi_add_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy fi_add_x
    lda (zp_ptr0),y
    ora #FLAG_HAS_ITEM
    sta (zp_ptr0),y
    ldx zp_temp4                // Restore slot index

    // Increment floor item count
    inc zp_item_count

    sec                         // Success
    rts

!fia_full:
    clc                         // Table full
    rts

// floor_item_remove — Remove floor item at slot X
// Input: X = slot index
// Clears FLAG_HAS_ITEM on map if no other item at same position.
// Clobbers: A, Y, zp_ptr0, zp_temp4
floor_item_remove:
    // Save position before clearing
    lda fi_x,x
    sta fi_add_x                // Reuse scratch for saved x
    lda fi_y,x
    sta fi_add_y                // Reuse scratch for saved y

    // Mark slot empty
    lda #FI_EMPTY
    sta fi_item_id,x
    lda #0
    sta fi_qty,x
    sta fi_p1,x
    sta fi_flags,x

    // Decrement count
    dec zp_item_count

    // Check if any other item shares the same (x, y)
    stx zp_temp4                // Save removed slot index
    ldx #0
!fir_scan:
    cpx #MAX_FLOOR_ITEMS
    bcs !fir_clear_flag+        // No other item found — clear flag
    cpx zp_temp4
    beq !fir_next+              // Skip the just-removed slot
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !fir_next+
    lda fi_x,x
    cmp fi_add_x
    bne !fir_next+
    lda fi_y,x
    cmp fi_add_y
    bne !fir_next+
    // Found another item at same position — keep flag
    ldx zp_temp4                // Restore X
    rts
!fir_next:
    inx
    jmp !fir_scan-

!fir_clear_flag:
    // Clear FLAG_HAS_ITEM on map tile
    ldy fi_add_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy fi_add_x
    lda (zp_ptr0),y
    and #~FLAG_HAS_ITEM & $ff
    sta (zp_ptr0),y
    ldx zp_temp4                // Restore X
    rts

// floor_item_find_at — Find a floor item at map position
// Input: A = map_x, Y = map_y
// Output: carry set = found (X = slot), carry clear = not found
// Clobbers: X
// Does NOT use zp_ptr0 (uses absolute indexed addressing into $CF00+)
floor_item_find_at:
    sta fi_add_x                // Stash search x
    sty fi_add_y                // Stash search y
    ldx #0
!fifa_loop:
    cpx #MAX_FLOOR_ITEMS
    bcs !fifa_miss+
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !fifa_next+
    lda fi_x,x
    cmp fi_add_x
    bne !fifa_next+
    lda fi_y,x
    cmp fi_add_y
    bne !fifa_next+
    // Found
    sec
    rts
!fifa_next:
    inx
    jmp !fifa_loop-
!fifa_miss:
    clc
    rts

// inv_add_item — Add item to first empty carried slot (0-21)
// Input: fi_add_id, fi_add_qty, fi_add_p1
// Output: carry set = success (X = slot), carry clear = full
// Clobbers: A, X
inv_add_item:
    ldx #0
!iai_scan:
    cpx #MAX_INV_SLOTS
    bcs !iai_full+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !iai_found+
    inx
    jmp !iai_scan-
!iai_found:
    lda fi_add_id
    sta inv_item_id,x
    lda fi_add_qty
    sta inv_qty,x
    lda fi_add_p1
    sta inv_p1,x
    lda fi_add_flags                // Copy flags (preserves IF_CURSED etc.)
    sta inv_flags,x
    lda fi_add_ego
    sta inv_ego,x
    sec
    rts
!iai_full:
    clc
    rts

// inv_remove_item — Remove item from inventory slot X
// Input: X = slot index (0-29)
// Clobbers: A
inv_remove_item:
    lda #FI_EMPTY
    sta inv_item_id,x
    lda #0
    sta inv_qty,x
    sta inv_p1,x
    sta inv_flags,x
    sta inv_ego,x
    rts

// inv_count_items — Count used carried slots (0-21)
// Output: A = count
// Clobbers: X
inv_count_items:
    lda #0
    sta ici_count               // Dedicated scratch counter (RP14-7)
    ldx #0
!ici_loop:
    cpx #MAX_INV_SLOTS
    bcs !ici_done+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ici_next+
    inc ici_count
!ici_next:
    inx
    jmp !ici_loop-
!ici_done:
    lda ici_count
    rts

// ============================================================
// item_spawn_level — Spawn gold and items on the dungeon floor
// Called after monster_spawn_level at each level transition.
// Phase 1: Gold (2 + rng(3) + dlvl/2, cap 16)
// Phase 2: Non-gold items (1 + rng(2) + dlvl/3, cap 8)
// Phase 3: Treasure room (dlvl >= 3, one room gets extra items)
// Town = 0 items.
// Clobbers: everything
// ============================================================
isl_ngold_target: .byte 0      // Non-gold item count target
isl_treasure_dlvl: .byte 0     // Effective dlvl for treasure room enchant

item_spawn_level:
    jsr item_init_floor

    // Town = no items
    lda zp_player_dlvl
    bne !isl_dungeon+
    rts

!isl_dungeon:
    // ---- Phase 1: Gold ----
    // Base count = 2
    lda #2
    sta isl_target

    // + rng(3) → [0, 2]
    lda #3
    jsr rng_range
    clc
    adc isl_target
    sta isl_target

    // + dlvl / 2
    lda zp_player_dlvl
    lsr                         // A = dlvl / 2
    clc
    adc isl_target
    sta isl_target

    // Cap at 16
    cmp #17
    bcc !isl_gold_capped+
    lda #16
    sta isl_target
!isl_gold_capped:

    lda #0
    sta isl_idx

!isl_gold_loop:
    lda isl_idx
    cmp isl_target
    bcs !isl_gold_done+

    // Find a random floor tile
    jsr find_random_floor

    // Set up floor item add
    lda df_target_x
    sta fi_add_x
    lda df_target_y
    sta fi_add_y

    // Gold type: rng(2) → ID 0 or 1
    lda #2
    jsr rng_range
    sta fi_add_id

    // Gold qty: rng_range_word(dlvl * 10) + 5 (16-bit)
    lda zp_player_dlvl
    ldx #10
    jsr math_multiply           // zp_math_a=lo, zp_math_b=hi
    lda zp_math_a
    sta zp_temp0
    lda zp_math_b
    sta zp_temp1                // N = dlvl * 10
    jsr rng_range_word          // result in zp_temp2/3
    // Add 5 to 16-bit result
    lda zp_temp2
    clc
    adc #5
    sta fi_add_qty
    lda zp_temp3
    adc #0
    sta fi_add_qty_hi

    lda #0
    sta fi_add_p1               // No enchantment for gold
    sta fi_add_flags            // No flags for gold
    sta fi_add_ego              // No ego for gold

    jsr floor_item_add
    // Ignore failure (table full)

    inc isl_idx
    jmp !isl_gold_loop-

!isl_gold_done:

    // ---- Phase 2: Non-gold items ----
    // Count: 1 + rng(2) + dlvl/3, cap 8
    lda #1
    sta isl_ngold_target

    lda #2
    jsr rng_range               // [0, 1]
    clc
    adc isl_ngold_target
    sta isl_ngold_target

    // + dlvl / 3 (approximate: dlvl * 85 / 256 ≈ dlvl/3)
    // Simple approach: subtract 3 repeatedly
    lda zp_player_dlvl
    ldx #0
!isl_div3:
    cmp #3
    bcc !isl_div3_done+
    sec
    sbc #3
    inx
    jmp !isl_div3-
!isl_div3_done:
    txa
    clc
    adc isl_ngold_target
    sta isl_ngold_target

    // Cap at 8
    cmp #9
    bcc !isl_ngold_capped+
    lda #8
    sta isl_ngold_target
!isl_ngold_capped:

    lda #0
    sta isl_idx

!isl_ngold_loop:
    lda isl_idx
    cmp isl_ngold_target
    bcs !isl_ngold_done+

    // Find a random floor tile
    jsr find_random_floor
    lda df_target_x
    sta fi_add_x
    lda df_target_y
    sta fi_add_y

    // Pick item type
    jsr pick_item_type
    sta fi_add_id

    // Roll enchantment
    jsr roll_enchantment
    sta fi_add_p1

    // fi_add_flags set by roll_enchantment (IF_CURSED for cursed items)

    // Roll ego type for weapons (0=none for non-weapons)
    lda fi_add_id
    jsr tramp_roll_ego_type
    sta fi_add_ego

    // Set qty: ammo spawns in stacks, everything else = 1
    lda #1
    sta fi_add_qty
    ldx fi_add_id
    jsr item_get_missile
    bpl !isl_qty_done+          // Bit 7 clear = not ammo
    // Ammo: qty = rng(6) + 5 → [5, 10]
    lda #6
    jsr rng_range
    clc
    adc #5
    sta fi_add_qty
!isl_qty_done:

    jsr floor_item_add
    bcc !isl_ngold_skip+        // Table full — skip

!isl_ngold_skip:
    inc isl_idx
    jmp !isl_ngold_loop-

!isl_ngold_done:

    // ---- Phase 3: Treasure room ----
    // Only on dlvl >= 3
    lda zp_player_dlvl
    cmp #3
    bcs !isl_has_treasure+
    jmp !isl_all_done+
!isl_has_treasure:

    // Check for vault room → enhanced treasure
    lda #RT_VAULT
    jsr tramp_find_special_room
    bcc !isl_no_vault+

    // Vault: use vault room, dlvl+8, 4-8 items
    stx isl_idx
    lda zp_player_dlvl
    clc
    adc #8                      // dlvl+8
    sta isl_treasure_dlvl
    lda #5
    jsr rng_range               // [0, 4]
    clc
    adc #4                      // [4, 8]
    sta isl_ngold_target
    jmp !isl_treasure_setup_done+

!isl_no_vault:
    // Spawn nest gold if applicable (no-op if no nest)
    jsr tramp_spawn_nest_gold

    // Normal treasure room (pick random room)
    lda room_count
    bne !isl_has_rooms+
    jmp !isl_all_done+
!isl_has_rooms:
    jsr rng_range               // [0, room_count-1]
    sta isl_idx                 // Reuse as room index

    // Effective dlvl for treasure = dlvl + 5
    lda zp_player_dlvl
    clc
    adc #5
    sta isl_treasure_dlvl

    // Extra items: 2 + rng(3)
    lda #3
    jsr rng_range               // [0, 2]
    clc
    adc #2                      // [2, 4]
    sta isl_ngold_target        // Reuse as treasure count

!isl_treasure_setup_done:
    lda #0
    sta isl_target              // Reuse as treasure loop counter

!isl_treasure_loop:
    lda isl_target
    cmp isl_ngold_target
    bcs !isl_all_done+

    // Random position within room bounds
    // x = room_x[idx] + rng(room_w[idx])
    ldx isl_idx
    lda room_w,x
    jsr rng_range
    ldx isl_idx
    clc
    adc room_x,x
    sta fi_add_x

    // y = room_y[idx] + rng(room_h[idx])
    ldx isl_idx
    lda room_h,x
    jsr rng_range
    ldx isl_idx
    clc
    adc room_y,x
    sta fi_add_y

    // Verify it's a floor tile
    ldy fi_add_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy fi_add_x
    lda (zp_ptr0),y
    and #$f0                    // TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !isl_treasure_skip+

    // Pick item with boosted dlvl
    // Temporarily boost dlvl for pick + enchant
    lda zp_player_dlvl
    pha                         // Save real dlvl
    lda isl_treasure_dlvl
    sta zp_player_dlvl

    jsr pick_item_type
    sta fi_add_id

    jsr roll_enchantment
    sta fi_add_p1

    // Roll ego type for treasure room items
    lda fi_add_id
    jsr tramp_roll_ego_type
    sta fi_add_ego

    pla                         // Restore real dlvl
    sta zp_player_dlvl

    lda #1
    sta fi_add_qty

    jsr floor_item_add
    bcc !isl_treasure_skip+

!isl_treasure_skip:
    inc isl_target
    jmp !isl_treasure_loop-

!isl_all_done:
    rts

// ============================================================
// Pickup and Drop
// ============================================================

// item_pickup — Pick up item at player's position
// Output: carry set = turn consumed, carry clear = no action
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0-4
item_pickup:
    // Find item at player position
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcs !ipu_found+

    // Nothing here
    lda #<ipu_nothing_str
    sta zp_ptr0
    lda #>ipu_nothing_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!ipu_found:
    // X = floor slot index. Save it.
    stx ipu_slot

    // Check if it's gold
    lda fi_item_id,x
    tax
    lda it_category,x
    cmp #ICAT_GOLD
    bne !ipu_not_gold+

    // --- Gold pickup ---
    // Add 16-bit fi_qty/fi_qty_hi to 24-bit player gold
    ldx ipu_slot
    lda player_data + PL_GOLD_0
    clc
    adc fi_qty,x
    sta player_data + PL_GOLD_0
    lda player_data + PL_GOLD_1
    adc fi_qty_hi,x
    sta player_data + PL_GOLD_1
    lda player_data + PL_GOLD_2
    adc #0
    sta player_data + PL_GOLD_2

    // Build message: "YOU FOUND N GOLD PIECES."
    lda #0
    sta cmb_buf_idx
    lda #<ipu_found_str
    ldy #>ipu_found_str
    jsr combat_append_str

    ldx ipu_slot
    lda fi_qty,x
    sta zp_temp0
    lda fi_qty_hi,x
    sta zp_temp1
    jsr combat_append_decimal_16

    lda #<ipu_gold_str
    ldy #>ipu_gold_str
    jsr combat_append_str

    // Null-terminate
    jsr cmb_term_and_print

    // Remove from floor
    ldx ipu_slot
    jsr floor_item_remove

    lda #SFX_PICKUP
    jsr sound_play

    sec
    rts

!ipu_not_gold:
    // --- Non-gold item pickup ---
    // Check if inventory full
    jsr inv_count_items
    cmp #MAX_INV_SLOTS
    bcc !ipu_has_room+

    // Pack full
    lda #<ipu_pack_full_str
    sta zp_ptr0
    lda #>ipu_pack_full_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!ipu_has_room:
    // Copy item to inventory
    ldx ipu_slot
    lda fi_item_id,x
    sta fi_add_id
    lda fi_qty,x
    sta fi_add_qty
    lda fi_p1,x
    sta fi_add_p1
    lda fi_flags,x
    sta fi_add_flags                // Preserve floor item flags (IF_CURSED etc.)
    lda fi_ego,x
    sta fi_add_ego
    jsr inv_add_item
    // carry set = success (should always succeed since we checked)

    // Build message: "YOU PICKED UP A <name>."
    lda #0
    sta cmb_buf_idx
    lda #<ipu_picked_str
    ldy #>ipu_picked_str
    jsr combat_append_str

    lda fi_add_id
    jsr item_append_name

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    // Null-terminate
    jsr cmb_term_and_print

    // Remove from floor
    ldx ipu_slot
    jsr floor_item_remove

    lda #SFX_PICKUP
    jsr sound_play

    sec
    rts

// item_drop — Drop a carried item to the floor (prompted)
// Prompts "DROP WHICH ITEM (A-V)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = no action
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0-4
item_drop:
    // Print prompt
    lda #<idr_prompt_str
    sta zp_ptr0
    lda #>idr_prompt_str
    sta zp_ptr0_hi
    jsr msg_print

    // Wait for keypress
    jsr input_get_key

    // '?' shows inventory and re-prompts
    cmp #$3f
    bne !idr_not_inv+
    jsr show_inv_and_restore
    jmp item_drop
!idr_not_inv:

    // Check for ESC ($03) or space ($20) -> cancel
    cmp #$03
    beq !idr_cancel+
    cmp #$20
    beq !idr_cancel+

    // Convert PETSCII letter to slot index (A-V = $41-$56 -> 0-21)
    sec
    sbc #$41
    bcc !idr_cancel+
    cmp #MAX_INV_SLOTS
    bcs !idr_cancel+

    // Check slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !idr_found+

    // Empty slot
    lda #<idr_no_items_str
    sta zp_ptr0
    lda #>idr_no_items_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!idr_cancel:
    lda #<idr_cancel_str
    sta zp_ptr0
    lda #>idr_cancel_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!idr_found:
    // X = inventory slot. Save it.
    stx ipu_slot

    // Set up floor item from inventory data
    lda zp_player_x
    sta fi_add_x
    lda zp_player_y
    sta fi_add_y
    lda inv_item_id,x
    sta fi_add_id
    lda inv_qty,x
    sta fi_add_qty
    lda inv_p1,x
    sta fi_add_p1
    lda inv_flags,x
    sta fi_add_flags
    lda inv_ego,x
    sta fi_add_ego

    jsr floor_item_add
    bcs !idr_placed+

    // Floor full
    lda #<idr_floor_full_str
    sta zp_ptr0
    lda #>idr_floor_full_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!idr_placed:
    // Remove from inventory
    ldx ipu_slot
    jsr inv_remove_item

    // Build message: "YOU DROP A <name>."
    lda #0
    sta cmb_buf_idx
    lda #<idr_drop_str
    ldy #>idr_drop_str
    jsr combat_append_str

    lda fi_add_id
    jsr item_append_name

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    // Null-terminate
    jsr cmb_term_and_print

    lda #SFX_PICKUP
    jsr sound_play

    sec
    rts

// item_append_name — Append item type name to combat_msg_buf
// Input: A = item type ID
// Uses item_get_name_ptr for identification-aware name resolution.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1
item_append_name:
    jsr item_get_name_ptr           // zp_ptr0 = name string
    lda zp_ptr0
    ldy zp_ptr0_hi
    jsr combat_append_str
    // Append ego suffix if present (reads fi_add_ego set by caller)
    lda fi_add_ego
    jsr tramp_ego_append_suffix
    rts

// Scratch variables for pickup/drop
ipu_slot: .byte 0              // Floor/inventory slot being processed

// ============================================================
// Pickup/Drop strings (screen codes via inherited encoding)
// ============================================================
ipu_nothing_str:   .text "YOU SEE NOTHING HERE." ; .byte 0
ipu_found_str:     .text "YOU FOUND " ; .byte 0
ipu_gold_str:      .text " GOLD PIECES." ; .byte 0
ipu_picked_str:    .text "YOU PICKED UP A " ; .byte 0
ipu_pack_full_str: .text "YOUR PACK IS FULL." ; .byte 0
idr_prompt_str:    .text "DROP WHICH ITEM (A-V)?" ; .byte 0
idr_drop_str:      .text "YOU DROP A " ; .byte 0
idr_no_items_str:  .text "YOU HAVE NOTHING THERE." ; .byte 0
idr_cancel_str:    .text "NEVER MIND." ; .byte 0
idr_floor_full_str: .text "NO ROOM ON THE FLOOR." ; .byte 0

// ============================================================
// pick_item_type — Select a random non-gold item type for floor spawning
// Rejection sampling: roll random type 2-46, accept if min_level <= dlvl+2.
// 1-in-12 "great item" chance bypasses min_level check.
// Fallback after 50 tries: return type 15 (ration of food).
// Output: A = item type ID (2-46)
// Clobbers: A, X, Y
// ============================================================
pit_attempts: .byte 0

pick_item_type:
    lda #50
    sta pit_attempts

!pit_loop:
    // Roll type = rng_range(59) + 2 → range [2, 60]
    // Types 2-60 cover weapons, armor, food, potions, scrolls, rings, wands, staves, bows, ammo, books
    lda #59
    jsr rng_range
    clc
    adc #2
    sta zp_temp0                // Save candidate type

    // 1-in-12 "great item" chance: bypass min_level check
    lda #12
    jsr rng_range
    beq !pit_accept+            // rng(12) == 0 → great item

    // Check min_level: accept if it_min_level[type] <= dlvl + 2
    ldx zp_temp0
    lda zp_player_dlvl
    clc
    adc #2                      // A = dlvl + 2
    cmp it_min_level,x          // dlvl+2 >= min_level?
    bcs !pit_accept+            // Yes → accept

    dec pit_attempts
    bne !pit_loop-

    // Fallback: ration of food (always valid)
    lda #15
    rts

!pit_accept:
    lda zp_temp0
    rts

// ============================================================
// roll_enchantment — Roll enchantment value for a spawned item
// Input: A = item type ID
// Output: A = signed enchantment (p1 value)
//         fi_add_flags scratch = IF_CURSED if cursed, else 0
// For lights: returns charge count instead of enchantment.
// For non-equipment: returns 0.
// Clobbers: A, X, Y
// ============================================================
fi_add_flags: .byte 0          // Scratch: flags for floor_item_add

roll_enchantment:
    sta zp_temp0                // Save item type
    lda #0
    sta fi_add_flags            // Default: not cursed

    // Check category — only equipment gets enchantment
    ldx zp_temp0
    lda it_category,x

    // Special case: lights get charges, not enchantment
    cmp #ICAT_LIGHT
    beq !re_light+

    // Special case: books get random spell index
    cmp #ICAT_BOOK
    beq !re_book+

    // Special case: wands and staves get charges
    cmp #ICAT_WAND
    beq !re_wand+
    cmp #ICAT_STAFF
    beq !re_staff+

    // Equipment categories: WEAPON(2) through BOOTS(7), RING(12)
    cmp #ICAT_WEAPON
    bcc !re_zero+               // NONE(0) or GOLD(1) → no enchant
    cmp #ICAT_LIGHT
    bcc !re_equip+              // WEAPON..BOOTS (2-7) → enchant
    cmp #ICAT_RING
    beq !re_equip+              // RING(12) → enchant
    // FOOD, POTION, SCROLL → no enchant
!re_zero:
    lda #0
    rts

!re_light:
    // Torch (type 13): 20 + rng(30)
    lda zp_temp0
    cmp #13
    bne !re_lantern+
    lda #30
    jsr rng_range
    clc
    adc #20
    rts

!re_lantern:
    // Lantern (type 14): 50 + rng(50)
    lda #50
    jsr rng_range
    clc
    adc #50
    rts

!re_wand:
    lda zp_temp0
    cmp #39                         // Wand of Light: [10,15]
    beq !re_wand_light+
    lda #4                          // Others: [5,8]
    jsr rng_range
    clc
    adc #5
    rts
!re_wand_light:
    lda #6
    jsr rng_range
    clc
    adc #10
    rts

!re_staff:
    lda zp_temp0
    cmp #43                         // Staff of Light: [10,15]
    beq !re_staff_light+
    cmp #45                         // Staff of Teleportation: [3,5]
    beq !re_staff_tele+
    lda #6                          // Others: [3,8]
    jsr rng_range
    clc
    adc #3
    rts
!re_staff_tele:
    lda #3
    jsr rng_range
    clc
    adc #3
    rts
!re_staff_light:
    lda #6
    jsr rng_range
    clc
    adc #10
    rts

!re_book:
    // Books: p1=0 (spell range determined by book type)
    lda #0
    rts

!re_equip:
    // magic_chance = min(15 + dlvl, 70)
    lda zp_player_dlvl
    clc
    adc #15
    cmp #71
    bcc !re_chance_ok+
    lda #70
!re_chance_ok:
    sta zp_temp1                // zp_temp1 = magic_chance

    // if rng(100) >= magic_chance: no enchantment
    lda #100
    jsr rng_range               // [0, 99]
    cmp zp_temp1
    bcs !re_zero-               // roll >= chance → no magic

    // bonus = rng(1 + dlvl/5) + 1
    lda zp_player_dlvl
    lsr
    lsr                         // dlvl/4 (close enough to dlvl/5)
    // Actually: dlvl/5. Use divide: dlvl * 205/1024 ≈ dlvl/5
    // Simpler: use lookup or just lsr twice + adjust
    // For simplicity and correctness: divide by 5 via subtraction
    // But let's use dlvl/4 as a reasonable approximation since
    // the difference is minor (max bonus off by 1 at dlvl 20)
    clc
    adc #1                      // range = 1 + dlvl/4
    jsr rng_range               // [0, dlvl/4]
    clc
    adc #1                      // [1, 1+dlvl/4]
    sta zp_temp1                // zp_temp1 = bonus

    // 1-in-13 chance of cursed
    lda #13
    jsr rng_range
    bne !re_not_cursed+

    // Cursed: negate bonus (2's complement)
    lda zp_temp1
    eor #$ff
    clc
    adc #1
    sta zp_temp1
    lda #IF_CURSED
    sta fi_add_flags
!re_not_cursed:
    lda zp_temp1
    rts

// ============================================================
// Item Identification System
// ============================================================

// Per-type identification state (0=unknown, 1=known)
id_known:
    .byte 1, 1              // 0-1: Gold — always known
    .byte 1, 1, 1, 1        // 2-5: Weapons — always known
    .byte 1, 1, 1           // 6-8: Armor — always known
    .byte 1                  // 9: Shield — always known
    .byte 1                  // 10: Helm — always known
    .byte 1, 1              // 11-12: Gloves, boots — always known
    .byte 1, 1              // 13-14: Lights — always known
    .byte 1, 1              // 15-16: Food — always known
    .byte 0, 0, 0           // 17-19: Potions — unknown at start
    .byte 0, 0, 0           // 20-22: Scrolls — unknown at start
    .byte 0, 0              // 23-24: Rings — unknown at start
    .byte 0, 0, 0, 0, 0, 0, 0  // 25-31: Potions — unknown at start
    .byte 0, 0, 0, 0, 0, 0, 0  // 32-38: Scrolls — unknown at start
    .byte 0, 0, 0, 0           // 39-42: Wands — unknown at start
    .byte 0, 0, 0, 0           // 43-46: Staves — unknown at start
    .byte 1, 1                  // 47-48: Books — always known
    .byte 1, 1, 1, 1, 1, 1      // 49-54: Ranged weapons/ammo — always known
    .byte 1, 1, 1, 1, 1, 1      // 55-60: Books — always known

// Shuffle tables: map category-local index → description index
// 12 potions, 12 scrolls, 4 rings — full pool shuffled, first N used
potion_shuffle: .fill 12, 0
scroll_shuffle: .fill 12, 0
ring_shuffle:   .fill 4, 0
wand_shuffle:   .fill 5, 0
staff_shuffle:  .fill 5, 0

// Lookup tables: item type ID → local category index ($FF = not that category)
potion_local_idx:
    .fill 17, $ff       // 0-16: not potions
    .byte 0, 1, 2       // 17-19: CLW, Speed, Poison
    .fill 5, $ff        // 20-24: not potions
    .byte 3, 4, 5, 6, 7, 8, 9  // 25-31: CSW, RestMana, Hero, Blind, Conf, DetMon, Infra
    .fill 18, $ff       // 32-48: not potions
    .fill 6, $ff        // 49-54: not potions
    .fill 6, $ff        // 55-60: not potions (books)

scroll_local_idx:
    .fill 20, $ff       // 0-19: not scrolls
    .byte 0, 1, 2       // 20-22: Light, Identify, Teleport
    .fill 2, $ff        // 23-24: not scrolls
    .fill 7, $ff        // 25-31: not scrolls
    .byte 3, 4, 5, 6, 7, 8, 9  // 32-38: WoR, RemCurse, EnchW, EnchA, MonConf, Aggrav, ProtEvil
    .fill 10, $ff       // 39-48: not scrolls
    .fill 6, $ff        // 49-54: not scrolls
    .fill 6, $ff        // 55-60: not scrolls (books)

// Unidentified name strings (screen codes, null-terminated)
pn_0:  .text "A BLUE POTION" ; .byte 0
pn_1:  .text "A RED POTION" ; .byte 0
pn_2:  .text "A GREEN POTION" ; .byte 0
pn_3:  .text "A YELLOW POTION" ; .byte 0
pn_4:  .text "A CLEAR POTION" ; .byte 0
pn_5:  .text "AN AZURE POTION" ; .byte 0
pn_6:  .text "A SMOKY POTION" ; .byte 0
pn_7:  .text "A BROWN POTION" ; .byte 0
pn_8:  .text "A SILVER POTION" ; .byte 0
pn_9:  .text "A PINK POTION" ; .byte 0
pn_10: .text "A CLOUDY POTION" ; .byte 0
pn_11: .text "A GOLDEN POTION" ; .byte 0

sn_0:  .text "A WHITE SCROLL" ; .byte 0
sn_1:  .text "A BROWN SCROLL" ; .byte 0
sn_2:  .text "A GREY SCROLL" ; .byte 0
sn_3:  .text "A FADED SCROLL" ; .byte 0
sn_4:  .text "A GLOWING SCROLL" ; .byte 0
sn_5:  .text "A SCROLL OF LUMEN" ; .byte 0
sn_6:  .text "A SCROLL OF VERITAS" ; .byte 0
sn_7:  .text "A SCROLL OF DURA" ; .byte 0
sn_8:  .text "A SCROLL OF LIBERA" ; .byte 0
sn_9:  .text "A SCROLL OF ACUTA" ; .byte 0
sn_10: .text "A SCROLL OF FEROX" ; .byte 0
sn_11: .text "A SCROLL OF TUTELA" ; .byte 0

rn_0: .text "A GOLD RING" ; .byte 0
rn_1: .text "A SILVER RING" ; .byte 0
rn_2: .text "A BRONZE RING" ; .byte 0
rn_3: .text "A COPPER RING" ; .byte 0

// Pointer tables for unidentified names
potion_name_lo:
    .byte <pn_0, <pn_1, <pn_2, <pn_3, <pn_4, <pn_5
    .byte <pn_6, <pn_7, <pn_8, <pn_9, <pn_10, <pn_11
potion_name_hi:
    .byte >pn_0, >pn_1, >pn_2, >pn_3, >pn_4, >pn_5
    .byte >pn_6, >pn_7, >pn_8, >pn_9, >pn_10, >pn_11

scroll_name_lo:
    .byte <sn_0, <sn_1, <sn_2, <sn_3, <sn_4, <sn_5
    .byte <sn_6, <sn_7, <sn_8, <sn_9, <sn_10, <sn_11
scroll_name_hi:
    .byte >sn_0, >sn_1, >sn_2, >sn_3, >sn_4, >sn_5
    .byte >sn_6, >sn_7, >sn_8, >sn_9, >sn_10, >sn_11

ring_name_lo: .byte <rn_0, <rn_1, <rn_2, <rn_3
ring_name_hi: .byte >rn_0, >rn_1, >rn_2, >rn_3

// Unidentified color tables (indexed by shuffle output)
potion_colors:
    .byte COL_BLUE, COL_LRED, COL_GREEN, COL_YELLOW, COL_WHITE, COL_CYAN
    .byte COL_GREY, COL_BROWN, COL_LGREY, COL_LRED, COL_WHITE, COL_YELLOW
scroll_colors:
    .byte COL_WHITE, COL_BROWN, COL_GREY, COL_LGREY, COL_LGREEN, COL_CYAN
    .byte COL_BLUE, COL_ORANGE, COL_PURPLE, COL_LRED, COL_RED, COL_YELLOW
ring_colors:   .byte COL_YELLOW, COL_LGREY, COL_BROWN, COL_ORANGE

// Wand identification
wn_0: .text "AN IRON WAND" ; .byte 0
wn_1: .text "A COPPER WAND" ; .byte 0
wn_2: .text "A SILVER WAND" ; .byte 0
wn_3: .text "A BONE WAND" ; .byte 0
wn_4: .text "AN OAK WAND" ; .byte 0

wand_name_lo: .byte <wn_0, <wn_1, <wn_2, <wn_3, <wn_4
wand_name_hi: .byte >wn_0, >wn_1, >wn_2, >wn_3, >wn_4
wand_colors:  .byte COL_LGREY, COL_ORANGE, COL_WHITE, COL_LGREY, COL_BROWN

// Staff identification
sfn_0: .text "A BIRCH STAFF" ; .byte 0
sfn_1: .text "A PINE STAFF" ; .byte 0
sfn_2: .text "A MAPLE STAFF" ; .byte 0
sfn_3: .text "A WILLOW STAFF" ; .byte 0
sfn_4: .text "AN ASH STAFF" ; .byte 0

staff_name_lo: .byte <sfn_0, <sfn_1, <sfn_2, <sfn_3, <sfn_4
staff_name_hi: .byte >sfn_0, >sfn_1, >sfn_2, >sfn_3, >sfn_4
staff_colors:  .byte COL_WHITE, COL_BROWN, COL_ORANGE, COL_LGREEN, COL_LGREY

// ============================================================
// item_init_identification — Reset id_known and shuffle tables
// Called once at new game start.
// Clobbers: A, X, Y
// ============================================================
item_init_identification:
    // Reset id_known: types 0-16 = known(1), 17-46 = unknown(0), 47-48 = known(1)
    ldx #16
    lda #1
!iid_known_1:
    sta id_known,x
    dex
    bpl !iid_known_1-
    ldx #17
    lda #0
!iid_unknown:
    sta id_known,x
    inx
    cpx #47                     // Up to type 46 (inclusive)
    bcc !iid_unknown-
    ldx #47
    lda #1
!iid_known_2:
    sta id_known,x
    inx
    cpx #ITEM_TYPE_COUNT
    bcc !iid_known_2-

    // Initialize shuffle tables to identity (0..11 / 0..3 / 0..4)
    ldx #11                         // For 12 elements (0-11)
!iid_init_ps:
    txa
    sta potion_shuffle,x
    sta scroll_shuffle,x
    dex
    bpl !iid_init_ps-
    ldx #3                          // For 4 elements (0-3)
!iid_init_rs:
    txa
    sta ring_shuffle,x
    dex
    bpl !iid_init_rs-
    ldx #4                          // For 5 elements (0-4)
!iid_init_ws:
    txa
    sta wand_shuffle,x
    sta staff_shuffle,x
    dex
    bpl !iid_init_ws-

    // Fisher-Yates shuffle: potions (12 elements)
    ldx #11                         // i = 11 down to 1
!iid_pot_loop:
    txa
    clc
    adc #1                          // rng_range(i+1) → [0, i]
    stx iid_save_x
    jsr rng_range
    ldx iid_save_x
    tay                             // Y = j = random index
    // Swap potion_shuffle[i] and potion_shuffle[j]
    lda potion_shuffle,x
    pha
    lda potion_shuffle,y
    sta potion_shuffle,x
    pla
    sta potion_shuffle,y
    dex
    bne !iid_pot_loop-

    // Fisher-Yates shuffle: scrolls (12 elements)
    ldx #11
!iid_scr_loop:
    txa
    clc
    adc #1
    stx iid_save_x
    jsr rng_range
    ldx iid_save_x
    tay
    // Swap scroll_shuffle[i] and scroll_shuffle[j]
    lda scroll_shuffle,x
    pha
    lda scroll_shuffle,y
    sta scroll_shuffle,x
    pla
    sta scroll_shuffle,y
    dex
    bne !iid_scr_loop-

    // Fisher-Yates shuffle: rings (4 elements)
    ldx #3
!iid_ring_loop:
    txa
    clc
    adc #1
    stx iid_save_x
    jsr rng_range
    ldx iid_save_x
    tay
    lda ring_shuffle,x
    pha
    lda ring_shuffle,y
    sta ring_shuffle,x
    pla
    sta ring_shuffle,y
    dex
    bne !iid_ring_loop-

    // Fisher-Yates shuffle: wands (5 elements)
    ldx #4
!iid_wand_loop:
    txa
    clc
    adc #1
    stx iid_save_x
    jsr rng_range
    ldx iid_save_x
    tay
    lda wand_shuffle,x
    pha
    lda wand_shuffle,y
    sta wand_shuffle,x
    pla
    sta wand_shuffle,y
    dex
    bne !iid_wand_loop-

    // Fisher-Yates shuffle: staves (5 elements)
    ldx #4
!iid_staff_loop:
    txa
    clc
    adc #1
    stx iid_save_x
    jsr rng_range
    ldx iid_save_x
    tay
    lda staff_shuffle,x
    pha
    lda staff_shuffle,y
    sta staff_shuffle,x
    pla
    sta staff_shuffle,y
    dex
    bne !iid_staff_loop-

    rts

iid_save_x: .byte 0                // Scratch for Fisher-Yates

// ============================================================
// item_get_name_ptr — Get name string pointer for an item type
// Input: A = item type ID
// Output: zp_ptr0 = pointer to null-terminated name string
// Clobbers: A, X, Y
// ============================================================
item_get_name_ptr:
    tax
    // Check if this type is known
    lda id_known,x
    bne !ignp_known+

    // Unknown — look up randomized description
    lda it_category,x
    cmp #ICAT_POTION
    beq !ignp_potion+
    cmp #ICAT_SCROLL
    beq !ignp_scroll+
    cmp #ICAT_RING
    beq !ignp_ring+
    cmp #ICAT_WAND
    beq !ignp_wand+
    cmp #ICAT_STAFF
    beq !ignp_staff+

    // Fallback (shouldn't happen): return real name
!ignp_known:
    lda it_name_lo,x
    sta zp_ptr0
    lda it_name_hi,x
    sta zp_ptr0_hi
    rts

!ignp_potion:
    lda potion_local_idx,x          // Local index for this potion type
    tax
    lda potion_shuffle,x            // Shuffled description index
    tax
    lda potion_name_lo,x
    sta zp_ptr0
    lda potion_name_hi,x
    sta zp_ptr0_hi
    rts

!ignp_scroll:
    lda scroll_local_idx,x          // Local index for this scroll type
    tax
    lda scroll_shuffle,x
    tax
    lda scroll_name_lo,x
    sta zp_ptr0
    lda scroll_name_hi,x
    sta zp_ptr0_hi
    rts

!ignp_ring:
    // Local index = type - 23
    txa
    sec
    sbc #23
    tax
    lda ring_shuffle,x
    tax
    lda ring_name_lo,x
    sta zp_ptr0
    lda ring_name_hi,x
    sta zp_ptr0_hi
    rts

!ignp_wand:
    // Local index = type - 39
    txa
    sec
    sbc #39
    tax
    lda wand_shuffle,x
    tax
    lda wand_name_lo,x
    sta zp_ptr0
    lda wand_name_hi,x
    sta zp_ptr0_hi
    rts

!ignp_staff:
    // Local index = type - 43
    txa
    sec
    sbc #43
    tax
    lda staff_shuffle,x
    tax
    lda staff_name_lo,x
    sta zp_ptr0
    lda staff_name_hi,x
    sta zp_ptr0_hi
    rts

// ============================================================
// item_get_floor_color — Get display color for a floor item
// Input: A = item type ID
// Output: A = color byte
// Clobbers: X
// ============================================================
item_get_floor_color:
    tax
    // Check if known
    lda id_known,x
    bne !igfc_known+

    // Unknown — return randomized color
    lda it_category,x
    cmp #ICAT_POTION
    beq !igfc_potion+
    cmp #ICAT_SCROLL
    beq !igfc_scroll+
    cmp #ICAT_RING
    beq !igfc_ring+
    cmp #ICAT_WAND
    beq !igfc_wand+
    cmp #ICAT_STAFF
    beq !igfc_staff+

!igfc_known:
    lda it_color,x
    rts

!igfc_potion:
    lda potion_local_idx,x
    tax
    lda potion_shuffle,x
    tax
    lda potion_colors,x
    rts

!igfc_scroll:
    lda scroll_local_idx,x
    tax
    lda scroll_shuffle,x
    tax
    lda scroll_colors,x
    rts

!igfc_ring:
    txa
    sec
    sbc #23
    tax
    lda ring_shuffle,x
    tax
    lda ring_colors,x
    rts

!igfc_wand:
    txa
    sec
    sbc #39
    tax
    lda wand_shuffle,x
    tax
    lda wand_colors,x
    rts

!igfc_staff:
    txa
    sec
    sbc #43
    tax
    lda staff_shuffle,x
    tax
    lda staff_colors,x
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Item type count", ITEM_TYPE_COUNT, 61
.assert "it_category size", it_display - it_category, ITEM_TYPE_COUNT
.assert "it_display size", it_color - it_display, ITEM_TYPE_COUNT
.assert "it_color size", it_weight - it_color, ITEM_TYPE_COUNT
.assert "Floor item base", FLOOR_ITEM_BASE, $cf00
.assert "Inventory total slots", TOTAL_INV_SLOTS, 30
