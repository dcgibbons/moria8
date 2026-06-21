#importonce
// item_categories.s — item type category table.

#import "item_defs.s"

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
    .byte ICAT_SHIELD   // 78: Large Shield
    .byte ICAT_ARMOR    // 79: Hard Leather Armor
    .byte ICAT_ARMOR    // 80: Scale Mail
    .byte ICAT_ARMOR    // 81: Plate Mail
    .byte ICAT_ARMOR    // 82: Cloak
    .byte ICAT_HELM     // 83: Steel Helm
    .byte ICAT_GLOVES   // 84: Gauntlets
    .byte ICAT_BOOTS    // 85: Soft Leather Boots
    .byte ICAT_BOOTS    // 86: Hard Leather Boots
    .byte ICAT_HELM     // 87: Metal Cap
    .byte ICAT_WEAPON   // 88: Sabre
    .byte ICAT_WEAPON   // 89: Cutlass
    .byte ICAT_WEAPON   // 90: Tulwar
    .byte ICAT_WEAPON   // 91: Katana
    .byte ICAT_WEAPON   // 92: Flail
    .byte ICAT_WEAPON   // 93: Lucerne Hammer
    .byte ICAT_WEAPON   // 94: Broad Axe
    .byte ICAT_WEAPON   // 95: Awl-Pike
it_category_end:
