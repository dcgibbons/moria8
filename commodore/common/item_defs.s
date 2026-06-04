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

// Item Category for Digging Tools
.const ICAT_DIGGING = 0

// Master Item Type Count
// Save Format V1 serializes 64 known-item bytes. Do not renumber IDs 0-63.
.const LEGACY_ITEM_TYPE_COUNT = 64
.const ITEM_TYPE_COUNT = 64
.const ITEM_ID_CAPACITY = 96
