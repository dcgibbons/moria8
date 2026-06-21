#importonce
// item_defs.s — Item system constants
//
// Extracted from item.s so player.s (and other early-imported modules)
// can reference equipment slot indices and inventory constants.
// Imported before player.s in the build order.

// Item Instance Flags
.const IF_CURSED     = $01
.const IF_IDENTIFIED = $02
.const IF_TRIED      = $04    // Legacy pseudo-ID bit kept for save compatibility
.const IF_SENSED     = $08    // Umoria-style auto-sensed "magik" marker
.const EGO_TYPE_COUNT = 8
.const ITEM_META_FLAGS_MASK = $0f
.const ITEM_META_EGO_MASK   = $70
.const ITEM_META_EGO_SHIFT  = 4

// Floor Item Constants
.const MAX_FLOOR_ITEMS = 42
.const MAX_GLYPHS      = 4
.const FI_EMPTY        = $ff

// Equipment Slot Constants (indices 22-30 in unified table)
.const EQUIP_WEAPON = 22
.const EQUIP_BODY   = 23
.const EQUIP_SHIELD = 24
.const EQUIP_HEAD   = 25
.const EQUIP_HANDS  = 26
.const EQUIP_FEET   = 27
.const EQUIP_LIGHT  = 28
.const EQUIP_RING   = 29
.const EQUIP_AMULET = 30
.const EQUIP_LAST   = EQUIP_AMULET
.const EQUIP_END    = EQUIP_LAST + 1
.const VISIBLE_EQUIP_LAST = EQUIP_RING
.const VISIBLE_EQUIP_END  = VISIBLE_EQUIP_LAST + 1

// Inventory Constants
.const MAX_INV_SLOTS   = 22
.const MAX_EQUIP_SLOTS = 9
.const VISIBLE_EQUIP_SLOTS = VISIBLE_EQUIP_END - EQUIP_WEAPON
.const TOTAL_INV_SLOTS = 31
.const LEGACY_TOTAL_INV_SLOTS = 30

// Item Categories
.const ICAT_DIGGING = 0
.const ICAT_GOLD    = 1
.const ICAT_WEAPON  = 2
.const ICAT_ARMOR   = 3
.const ICAT_SHIELD  = 4
.const ICAT_HELM    = 5
.const ICAT_GLOVES  = 6
.const ICAT_BOOTS   = 7
.const ICAT_LIGHT   = 8
.const ICAT_FOOD    = 9
.const ICAT_POTION  = 10
.const ICAT_SCROLL  = 11
.const ICAT_RING    = 12
.const ICAT_BOOK    = 13
.const ICAT_WAND    = 14
.const ICAT_STAFF   = 15

// Master Item Type Count
// Save Format V1 serializes 64 known-item bytes. Do not renumber IDs 0-63.
.const LEGACY_ITEM_TYPE_COUNT = 64
.const ITEM_TYPE_COUNT = 96
.const ITEM_ID_CAPACITY = 96
