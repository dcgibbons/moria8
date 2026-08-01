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

// Item Category for Digging Tools
.const ICAT_DIGGING = 0

// Master Item Type Count
// Save Format V1 serializes 64 known-item bytes. Do not renumber IDs 0-63.
.const LEGACY_ITEM_TYPE_COUNT = 64
.const ITEM_TYPE_COUNT = 96
.const ITEM_ID_CAPACITY = 128

// Known-item identification state (Save Format V4)
// One bit per item type ID: set = identified/known. 16 bytes at 128 IDs.
.const ID_KNOWN_BYTES = (ITEM_ID_CAPACITY + 7) / 8

id_known_bits: .fill ID_KNOWN_BYTES, 0

idk_bit_mask: .byte 1, 2, 4, 8, 16, 32, 64, 128
idk_mask:     .byte 0

// id_known_test — Report whether item type X is identified/known.
// Input:  X = item type ID
// Output: A = 0 and Z set when the item is UNKNOWN (mirrors lda id_known,x)
// Clobbers: A, Y (X preserved)
id_known_test:
    txa
    pha
    and #7
    tay
    lda idk_bit_mask,y
    sta idk_mask
    pla
    lsr
    lsr
    lsr
    tay
    lda id_known_bits,y
    and idk_mask
    rts

// id_known_set — Mark item type X as identified/known.
// Input:  X = item type ID
// Clobbers: A, Y (X preserved)
id_known_set:
    txa
    pha
    and #7
    tay
    lda idk_bit_mask,y
    sta idk_mask
    pla
    lsr
    lsr
    lsr
    tay
    lda id_known_bits,y
    ora idk_mask
    sta id_known_bits,y
    rts

// id_known_set_y — Mark item type Y as identified/known.
// Input:  Y = item type ID
// Clobbers: A, Y (X preserved)
id_known_set_y:
    tya
    pha
    and #7
    tay
    lda idk_bit_mask,y
    sta idk_mask
    pla
    lsr
    lsr
    lsr
    tay
    lda id_known_bits,y
    ora idk_mask
    sta id_known_bits,y
    rts

// id_known_clear — Mark item type X as unknown.
// Input:  X = item type ID
// Clobbers: A, Y (X preserved)
id_known_clear:
    txa
    pha
    and #7
    tay
    lda idk_bit_mask,y
    eor #$ff
    sta idk_mask
    pla
    lsr
    lsr
    lsr
    tay
    lda id_known_bits,y
    and idk_mask
    sta id_known_bits,y
    rts
