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
.const EGO_NONE          = 0
.const EGO_SLAY_ANIMAL   = 1
.const EGO_SLAY_EVIL     = 2
.const EGO_SLAY_UNDEAD   = 3
.const EGO_FLAME_TONGUE  = 4
.const EGO_FROST_BRAND   = 5
.const EGO_DEFENDER      = 6
.const EGO_HOLY_AVENGER  = 7
.const EGO_SLAY_DRAGON   = 8
.const EGO_RESIST        = 9    // VMS (R)
.const EGO_RESIST_ACID   = 10   // VMS (RA)
.const EGO_RESIST_FIRE   = 11   // VMS (RF)
.const EGO_RESIST_COLD   = 12   // VMS (RC)
.const EGO_RESIST_LIGHT  = 13   // VMS (RL)
.const EGO_MAGI          = 14   // VMS crowns "of the Magi" (MON-030)
.const EGO_TYPE_COUNT = 15   // weapon egos 1-8, resistance armour 9-13, the Magi 14 (core/ego_items.s)
.assert "Ego IDs fit the 4-bit store and floor ego fields", EGO_TYPE_COUNT <= 16, true
.const ITEM_META_FLAGS_MASK = $0f
// Ego bits 4-7 (bits 4-6 until Slay Dragon, 2026-11-07: bit 7 was unused,
// so every saved store item reads as before).
.const ITEM_META_EGO_MASK   = $f0
.const ITEM_META_EGO_SHIFT  = 4

// Floor Item Constants
.const MAX_FLOOR_ITEMS = 42
.const MAX_GLYPHS      = 4
.const FI_EMPTY        = $ff

// Equipment Slot Constants (indices 22-32 in unified table)
// Rings: VMS's two hands (moria.inc:528, inventory[29] right, [30] left):
// EQUIP_RING the right, EQUIP_RING2 the left (2026-11-08; slot 31 was
// reserved for a cloak slot, which will take a new slot when it lands).
.const EQUIP_WEAPON = 22
.const EQUIP_BODY   = 23
.const EQUIP_SHIELD = 24
.const EQUIP_HEAD   = 25
.const EQUIP_HANDS  = 26
.const EQUIP_FEET   = 27
.const EQUIP_LIGHT  = 28
.const EQUIP_RING   = 29               // right hand: a ring goes here when it is free
.const EQUIP_AMULET = 30
.const EQUIP_RING2  = 31               // left hand: else here, replacing what is worn
.const EQUIP_SECONDARY = 32            // VMS inventory[34]: SHIFT+X swaps it with EQUIP_WEAPON
.const EQUIP_LAST   = EQUIP_RING2
.const EQUIP_END    = EQUIP_LAST + 1   // AC sum / pseudo-ID: never the secondary
.const VISIBLE_EQUIP_LAST = EQUIP_SECONDARY   // equipment screen and take-off
.const VISIBLE_EQUIP_END  = VISIBLE_EQUIP_LAST + 1

// Inventory Constants
.const MAX_INV_SLOTS   = 22
.const VISIBLE_EQUIP_SLOTS = VISIBLE_EQUIP_END - EQUIP_WEAPON
.const TOTAL_INV_SLOTS = 33
.const MAX_EQUIP_SLOTS = TOTAL_INV_SLOTS - MAX_INV_SLOTS
.const LEGACY_INV30_SLOTS = 30         // saves before the amulet slot
.const LEGACY_INV31_SLOTS = 31         // saves before the slot-31 (left ring) and secondary slots
.assert "The left-hand ring ends the AC range", EQUIP_RING2 + 1, EQUIP_END
.assert "Secondary weapon is the last inventory slot", EQUIP_SECONDARY == EQUIP_RING2 + 1 && EQUIP_SECONDARY == TOTAL_INV_SLOTS - 1, true
.assert "Visible equipment covers every equipment slot", VISIBLE_EQUIP_END, TOTAL_INV_SLOTS

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
// the general store. Identical spikes stack in one slot (inv_add_item), as
// do food, potions, scrolls, flasks of oil and ammunition (VMS inven_carry).
// Nothing else shares the category.
.const ICAT_SPIKE    = 18
.const ITEM_TYPE_FLASK_OF_OIL = 61   // ICAT_LIGHT, but a consumable that stacks
.const ITEM_TYPE_WOODEN_TORCH = 13   // ICAT_LIGHT; stacks with equal turns of light (VMS, Umoria)

// Phase 3 item type constants (IDs 96-127)
.const ITEM_TYPE_POT_HEALING        = 96
.const ITEM_TYPE_POT_RESTORATION    = 97
.const ITEM_TYPE_POT_RESIST_HEAT    = 98
.const ITEM_TYPE_POT_RESIST_COLD    = 99
.const ITEM_TYPE_POT_CURE_CRITICAL  = 100
// Status timers a cure-wounds/Healing potion cures (eff_potion_cure.s masks;
// bit order follows zp_eff_poison, zp_eff_blind, zp_eff_confuse).
.const EFF_CURE_POISON  = %001
.const EFF_CURE_BLIND   = %010
.const EFF_CURE_CONFUSE = %100
.const EFF_CURE_ALL     = EFF_CURE_POISON | EFF_CURE_BLIND | EFF_CURE_CONFUSE
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
.const ITEM_TYPE_SCR_PHASE_DOOR    = 136   // VMS Scroll of Phase Door (teleport(10))

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
.const PFLAG_FREE_ACT    = $10   // Free Action: the Amulet of the Magi (VMS)
.const PFLAG_RESIST_ACID = $20   // acid breath and touch (VMS acid_dam); armour, Defender
.const PFLAG_RESIST_LIGHT = $40  // lightning breath div 3 (VMS light_dam); armour, Defender

// Master Item Type Count
// Save Format V1 serializes 64 known-item bytes. Do not renumber IDs 0-63.
// Capacity 160 (20-byte bitset) leaves runway past the chest rows at 128-134
// so the next catalog expansion pays no save-format bump.
.const LEGACY_ITEM_TYPE_COUNT = 64
.const ITEM_TYPE_COUNT = 153
// VMS Moria rings of Lordly Protection and the Amulet of Resist Acid
// (values.inc; 2026-11-11, MON-029): resistance in the ring and amulet slots
.const ITEM_TYPE_RING_LORDLY_FIRE = 146
.const ITEM_TYPE_RING_LORDLY_ACID = 147
.const ITEM_TYPE_RING_LORDLY_COLD = 148
.const ITEM_TYPE_AMULET_RESIST_ACID = 149
// VMS Moria crowns (values.inc; 2026-11-11, MON-030): helms that may roll
// the Magi ego (roll_armour_ego)
.const ITEM_TYPE_CROWN_SILVER = 150
.const ITEM_TYPE_CROWN_GOLDEN = 151
.const ITEM_TYPE_CROWN_JEWEL  = 152
// VMS Moria potions of gain stat (values.inc; 2026-11-07), in PL_*_BASE order
.const ITEM_TYPE_POT_GAIN_STR = 140
.const ITEM_TYPE_POT_GAIN_CHR = 145
.const ITEM_ID_CAPACITY = 160

// Known-item identification state (Save Format V4)
// One bit per item type ID: set = identified/known. 20 bytes at 160 IDs.
.const ID_KNOWN_BYTES = (ITEM_ID_CAPACITY + 7) / 8

#if PLATFORM_ID_KNOWN_EXTERNAL
.label id_known_bits = PLATFORM_ID_KNOWN_BASE   // a port's free RAM (the Atari: high RAM); item_init_identification clears it
#else
id_known_bits: .fill ID_KNOWN_BYTES, 0
#endif

idk_bit_mask: .byte 1, 2, 4, 8, 16, 32, 64, 128
idk_mask:     .byte 0

// idk_index_x / idk_index_a — The bit of item type X (or A): idk_mask = its
// mask, Y = its byte in id_known_bits, A = that byte. Shared by the four
// helpers below, which repeated it whole until 2026-11-07.
// Clobbers: A, Y (X preserved)
idk_index_x:
    txa
idk_index_a:
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
    rts

// id_known_test — Report whether item type X is identified/known.
// Input:  X = item type ID
// Output: A = 0 and Z set when the item is UNKNOWN (mirrors lda id_known,x)
// Clobbers: A, Y (X preserved)
id_known_test:
    jsr idk_index_x
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
#if HAL_PLATFORM_QUAFF_IDENTIFY_RESIDENT
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
idks_a:
    jsr idk_index_a
    ora idk_mask
    sta id_known_bits,y
    rts

// id_known_set_y — Mark item type Y as identified/known.
// Input:  Y = item type ID
// Clobbers: A, Y (X preserved)
id_known_set_y:
    tya
    jmp idks_a

#if C64_UNIT_TEST || C128_UNIT_TEST
// id_known_clear — Mark item type X as unknown. No product caller; the unit
// tests keep it to reset knowledge (test_identify128.s has its own copy).
// Input:  X = item type ID
// Clobbers: A, Y (X preserved)
id_known_clear:
    jsr idk_index_x
    lda idk_mask
    eor #$ff
    and id_known_bits,y
    sta id_known_bits,y
    rts
#endif
