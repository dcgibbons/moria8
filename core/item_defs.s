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
.const VISIBLE_EQUIP_LAST = EQUIP_AMULET
.const VISIBLE_EQUIP_END  = VISIBLE_EQUIP_LAST + 1

// Inventory Constants
.const MAX_INV_SLOTS   = 22
.const MAX_EQUIP_SLOTS = 9
.const VISIBLE_EQUIP_SLOTS = VISIBLE_EQUIP_END - EQUIP_WEAPON
.const TOTAL_INV_SLOTS = 31
.const LEGACY_TOTAL_INV_SLOTS = 30

// Item Category for Digging Tools
.const ICAT_DIGGING = 0

// Item Category Constants
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
.const ICAT_AMULET   = 16
.const ICAT_CHEST    = 17
// ICAT_SPIKE: jamming spikes (upstream TV_SPIKE); not wieldable, sold at
// the general store. Like every item in this port, spikes do not merge:
// each occupies its own inventory slot (inv_add_item has no stacking).
// Nothing else shares the category.
.const ICAT_SPIKE    = 18

// Phase 3 item type constants (IDs 96-127)
.const ITEM_TYPE_POT_HEALING        = 96
.const ITEM_TYPE_POT_RESTORATION    = 97
.const ITEM_TYPE_POT_RESIST_HEAT    = 98
.const ITEM_TYPE_POT_RESIST_COLD    = 99
.const ITEM_TYPE_POT_CURE_CRITICAL  = 100
.const ITEM_TYPE_SCR_TELEPORT_LEVEL = 101
.const ITEM_TYPE_SCR_MAGIC_MAPPING  = 102
.const ITEM_TYPE_SCR_OBJECT_DETECT  = 103
.const ITEM_TYPE_SCR_RECHARGING     = 104
.const ITEM_TYPE_SCR_RUNE_PROTECTION = 105
.const ITEM_TYPE_SCR_GENOCIDE       = 106
.const ITEM_TYPE_SCR_MASS_GENOCIDE  = 107
.const ITEM_TYPE_SCR_DESTRUCTION    = 108
.const ITEM_TYPE_RING_RESIST_FIRE   = 109
.const ITEM_TYPE_RING_RESIST_COLD   = 110
.const ITEM_TYPE_RING_SPEED         = 111
.const ITEM_TYPE_RING_SEE_INVIS     = 112
.const ITEM_TYPE_RING_SLAYING       = 113
.const ITEM_TYPE_RING_STRENGTH      = 24
.const ITEM_TYPE_WAND_SLOW          = 114
.const ITEM_TYPE_WAND_STONE_MUD     = 115
.const ITEM_TYPE_WAND_TELEPORT_AWAY = 116
.const ITEM_TYPE_WAND_FIRE_BALL     = 117
.const ITEM_TYPE_WAND_COLD_BALL     = 118
.const ITEM_TYPE_STAFF_DISPEL_EVIL  = 119
.const ITEM_TYPE_STAFF_DESTRUCTION  = 120
.const ITEM_TYPE_STAFF_SPEED        = 121
.const ITEM_TYPE_MITHRIL_CHAIN      = 122
.const ITEM_TYPE_MITHRIL_PLATE      = 123
.const ITEM_TYPE_AMULET_WISDOM      = 124
.const ITEM_TYPE_AMULET_MAGI        = 125
.const ITEM_TYPE_POT_NEUTRALIZE     = 126
.const ITEM_TYPE_STAFF_REMOVE_CURSE = 127

// Chest item type constants (IDs 128-134; docs/CHEST_DESIGN.md)
.const ITEM_TYPE_CHEST_SMALL_WOOD  = 128
.const ITEM_TYPE_CHEST_LARGE_WOOD  = 129
.const ITEM_TYPE_CHEST_SMALL_IRON  = 130
.const ITEM_TYPE_CHEST_LARGE_IRON  = 131
.const ITEM_TYPE_CHEST_SMALL_STEEL = 132
.const ITEM_TYPE_CHEST_LARGE_STEEL = 133
.const ITEM_TYPE_CHEST_RUINED      = 134
.const ITEM_TYPE_IRON_SPIKE        = 135

// Chest p1 state bits (docs/CHEST_DESIGN.md state layout)
.const CHEST_P1_LOCKED      = $01
.const CHEST_P1_TRAP_STR    = $02
.const CHEST_P1_TRAP_POISON = $04
.const CHEST_P1_TRAP_PARA   = $08
.const CHEST_P1_TRAP_EXPL   = $10
.const CHEST_P1_TRAP_SUMMON = $20
.const CHEST_P1_TRAP_FOUND  = $40
.const CHEST_P1_OPENED      = $80
// Any of the five trap bits set = armed
.const CHEST_P1_TRAP_MASK   = $3e

// Persistent equipment-granted effect flags (player_pflags)
.const PFLAG_RESIST_FIRE = $01
.const PFLAG_RESIST_COLD = $02
.const PFLAG_SPEED       = $04
.const PFLAG_SEE_INVIS   = $08

// Master Item Type Count
// Save Format V1 serializes 64 known-item bytes. Do not renumber IDs 0-63.
// Capacity 160 (20-byte bitset) leaves runway past the chest rows at 128-134
// so the next catalog expansion pays no save-format bump.
.const LEGACY_ITEM_TYPE_COUNT = 64
.const ITEM_TYPE_COUNT = 136
.const ITEM_ID_CAPACITY = 160

// Known-item identification state (Save Format V4)
// One bit per item type ID: set = identified/known. 20 bytes at 160 IDs.
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

// ============================================================
// piq_quaff_identify — Mark item type X identified, but only when quaffing it
// produces a noticeable effect (upstream VMS hp_player). Heal-family potions
// at full HP are a silent no-op: no message and no identification. Everything
// else identifies on quaff.
// On C128 this file is resident (roomy); other ports import the identical
// helper in player_item_commands.s where their item code lives (that file is
// in the C128 banked runtime, which has only ~9 bytes free).
// Input: X = item type ID. Clobbers: A, Y (X preserved via id_known_set).
// ============================================================
#if C128
piq_quaff_identify:
    txa
    cmp #17                 // Cure Light Wounds
    beq !pqi_heal+
    cmp #25                 // Cure Serious Wounds
    beq !pqi_heal+
    cmp #ITEM_TYPE_POT_HEALING
    beq !pqi_heal+
    cmp #ITEM_TYPE_POT_CURE_CRITICAL
    beq !pqi_heal+
!pqi_ident:
    jmp id_known_set        // X = item type ID
!pqi_heal:
    // Full HP -> the heal is a no-op -> stays unidentified.
    lda zp_player_hp_hi
    cmp zp_player_mhp_hi
    bcc !pqi_ident-
    bne !pqi_full+
    lda zp_player_hp_lo
    cmp zp_player_mhp_lo
    bcc !pqi_ident-
!pqi_full:
    rts
#endif

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
