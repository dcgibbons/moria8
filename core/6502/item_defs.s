#importonce
// item_defs.s — Item system constants
//
// Extracted from item.s so player.s (and other early-imported modules)
// can reference equipment slot indices and inventory constants.
// Imported before player.s in the build order.

#import "../../platforms/shared/item_catalog/item_ids.s"

// Item Instance Flags
.const IF_CURSED     = $01
.const IF_IDENTIFIED = $02
.const IF_TRIED      = $04    // Legacy pseudo-ID bit kept for save compatibility
.const IF_SENSED     = $08    // Umoria-style auto-sensed "magik" marker
.const ITEM_META_FLAGS_MASK = $0f

// Base-255 Paged 9-bit Item ID / Ego Packing (V2 catalog)
// Logical 0..254 -> page_bit = 0, slot_lo = id (0..254).
// Logical 255..360 -> page_bit = ITEM_PAGE_BIT ($40), slot_lo = id - 255 (0..105).
// Packed into inv_ego[34], fi_meta_hi[42], si_meta_hi[128] as (page_bit | ego_id).
.const ITEM_PAGE_BIT = $40
.const EGO_ID_MASK   = $3f

// Ego IDs (1..55 match item_catalog_spec.json / ITEM.CAT)
.const EGO_NONE            = 0
.const EGO_SLAY_ANIMAL     = 1
.const EGO_SLAY_EVIL       = 2
.const EGO_SLAY_UNDEAD     = 3
.const EGO_FLAME_TONGUE    = 4
.const EGO_FROST_BRAND     = 5
.const EGO_DEFENDER        = 6
.const EGO_HOLY_AVENGER    = 7
.const EGO_SLAY_DRAGON     = 8
.const EGO_RESIST          = 9
.const EGO_RESIST_ACID     = 10
.const EGO_RESIST_FIRE     = 11
.const EGO_RESIST_COLD     = 12
.const EGO_RESIST_LIGHT    = 13
.const EGO_MAGI            = 14
.const EGO_FREE_ACTION     = 15
.const EGO_SLAYING         = 16
.const EGO_CLUMSINESS      = 17
.const EGO_WEAKNESS        = 18
.const EGO_SLOW_DESCENT    = 19
.const EGO_SPEED           = 20
.const EGO_STEALTH         = 21
.const EGO_SLOWNESS        = 22
.const EGO_NOISE           = 23
.const EGO_GREAT_MASS      = 24
.const EGO_INTELLIGENCE    = 25
.const EGO_WISDOM          = 26
.const EGO_INFRA_VISION    = 27
.const EGO_MIGHT           = 28
.const EGO_LORDLINESS      = 29
.const EGO_BEAUTY          = 30
.const EGO_SEEING          = 31
.const EGO_REGENERATION    = 32
.const EGO_STUPIDITY       = 33
.const EGO_DULLNESS        = 34
.const EGO_BLINDNESS       = 35
.const EGO_TIMIDNESS       = 36
.const EGO_TELEPORTATION   = 37
.const EGO_UGLINESS        = 38
.const EGO_PROTECTION      = 39
.const EGO_IRRITATION      = 40
.const EGO_VULNERABILITY   = 41
.const EGO_ENVELOPING      = 42
.const EGO_AMMO_FIRE       = 43
.const EGO_AMMO_SLAY_EVIL  = 44
.const EGO_DRAGON_SLAYING  = 45
.const EGO_CHEST_EMPTY     = 46
.const EGO_CHEST_LOCKED    = 47
.const EGO_CHEST_POISON    = 48
.const EGO_CHEST_GAS       = 49
.const EGO_CHEST_EXPLOSION = 50
.const EGO_CHEST_SUMMON    = 51
.const EGO_CHEST_MULTI     = 52
.const EGO_CHEST_DISARMED  = 53
.const EGO_CHEST_UNLOCKED  = 54
.const EGO_AMMO_SLAY_ANIMAL = 55
.const EGO_TYPE_COUNT      = 56
.assert "Ego IDs fit the 6-bit page+ego fields", EGO_TYPE_COUNT <= 64, true

// Floor Item Constants
.const MAX_FLOOR_ITEMS = 42
.const MAX_GLYPHS      = 4
.const FI_EMPTY        = $ff

// Equipment Slot Constants (indices 22-33 in unified table)
.const EQUIP_WEAPON    = 22
.const EQUIP_BODY      = 23
.const EQUIP_SHIELD    = 24
.const EQUIP_HEAD      = 25
.const EQUIP_HANDS     = 26
.const EQUIP_FEET      = 27
.const EQUIP_LIGHT     = 28
.const EQUIP_RING      = 29
.const EQUIP_AMULET    = 30
.const EQUIP_RING2     = 31
.const EQUIP_CLOAK     = 32
.const EQUIP_SECONDARY = 33
.const EQUIP_LAST      = EQUIP_CLOAK
.const EQUIP_END       = EQUIP_LAST + 1       // 33: AC sum / pseudo-ID / passives (excludes secondary)
.const VISIBLE_EQUIP_LAST = EQUIP_SECONDARY
.const VISIBLE_EQUIP_END  = VISIBLE_EQUIP_LAST + 1

// Inventory Constants
.const MAX_INV_SLOTS       = 22
.const VISIBLE_EQUIP_SLOTS = VISIBLE_EQUIP_END - EQUIP_WEAPON   // 12
.const TOTAL_INV_SLOTS     = 34
.const MAX_EQUIP_SLOTS     = TOTAL_INV_SLOTS - MAX_INV_SLOTS     // 12
.assert "Cloak ends the worn equipment range", EQUIP_CLOAK + 1, EQUIP_END
.assert "Secondary weapon is the last inventory slot", EQUIP_SECONDARY == EQUIP_CLOAK + 1 && EQUIP_SECONDARY == TOTAL_INV_SLOTS - 1, true
.assert "Visible equipment covers every equipment slot", VISIBLE_EQUIP_END, TOTAL_INV_SLOTS
.assert "7 * TOTAL_INV_SLOTS fits in 8 bits", TOTAL_INV_SLOTS * 7 < 256, true

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
.const ICAT_SPIKE    = 18
.const ICAT_CLOAK    = 19
.const ICAT_JUNK     = 20

// Status timers a cure-wounds/Healing potion cures (eff_potion_cure.s masks;
// bit order follows zp_eff_poison, zp_eff_blind, zp_eff_confuse).
.const EFF_CURE_POISON  = %001
.const EFF_CURE_BLIND   = %010
.const EFF_CURE_CONFUSE = %100
.const EFF_CURE_ALL     = EFF_CURE_POISON | EFF_CURE_BLIND | EFF_CURE_CONFUSE

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
.const PFLAG_RESIST_FIRE  = $01
.const PFLAG_RESIST_COLD  = $02
.const PFLAG_SPEED        = $04
.const PFLAG_SEE_INVIS    = $08
.const PFLAG_FREE_ACT     = $10   // Free Action: Amulet of the Magi, Defender, gloves
.const PFLAG_RESIST_ACID  = $20   // acid breath/touch: armour, Defender, Lordly Acid
.const PFLAG_RESIST_LIGHT = $40   // lightning breath div 3: armour, Defender
.const PFLAG_FFALL        = $80   // Feather Falling: pit/trap-door mitigation, slow descent

// Extended persistent equipment-granted passive flags (player_pflags2)
.const PFLAG2_SLOW_DIGEST = $01
.const PFLAG2_REGEN       = $02
.const PFLAG2_STEALTH     = $04
.const PFLAG2_AGGRAVATE   = $08
.const PFLAG2_TELEPORT    = $10
.const PFLAG2_SEARCH      = $20
.const PFLAG2_INFRA       = $40

// Sustain bitmask (player_sust_mask, PL_STR_CUR..PL_CHR_CUR bit order 0..5)
.const SUST_STR = $01
.const SUST_INT = $02
.const SUST_WIS = $04
.const SUST_DEX = $08
.const SUST_CON = $10
.const SUST_CHR = $20
.const SUST_ALL = $3f

// ITEM.CAT 32-bit TR_* flags (bytes 0..3 LE in icat_flags_0..3)
.const ITR0_STR         = $01
.const ITR0_DEX         = $02
.const ITR0_CON         = $04
.const ITR0_INT         = $08
.const ITR0_WIS         = $10
.const ITR0_CHR         = $20
.const ITR0_SEARCH      = $40
.const ITR0_SLOW_DIGEST = $80

.const ITR1_STEALTH     = $01
.const ITR1_AGGRAVATE   = $02
.const ITR1_TELEPORT    = $04
.const ITR1_REGEN       = $08
.const ITR1_SPEED       = $10
.const ITR1_SLAY_DRAGON = $20
.const ITR1_SLAY_ANIMAL = $40
.const ITR1_SLAY_EVIL   = $80

.const ITR2_SLAY_UNDEAD  = $01
.const ITR2_FROST_BRAND  = $02
.const ITR2_FLAME_TONGUE = $04
.const ITR2_RES_FIRE     = $08
.const ITR2_RES_ACID     = $10
.const ITR2_RES_COLD     = $20
.const ITR2_SUST_STAT    = $40
.const ITR2_FREE_ACT     = $80

.const ITR3_SEE_INVIS = $01
.const ITR3_RES_LIGHT = $02
.const ITR3_FFALL     = $04
.const ITR3_BLIND     = $08
.const ITR3_TIMID     = $10
.const ITR3_TUNNEL    = $20
.const ITR3_INFRA     = $40
.const ITR3_CURSED    = $80

// Master Item Type Catalog Constants (match item_hot_tables.s)
#define ITEM_DEFS_CONSTS_INCLUDED
.const ITEM_TYPE_COUNT      = 361
.const ITEM_PAGE_SIZE       = 255
.const EGO_COUNT            = 55
.const FLAVOUR_COUNT        = 174
.const FLAVOUR_POTION_COUNT = 46
.const FLAVOUR_SCROLL_COUNT = 49
.const FLAVOUR_RING_COUNT   = 30
.const FLAVOUR_WAND_COUNT   = 24
.const FLAVOUR_STAFF_COUNT  = 25
.const IT_AC_EXTRA_COUNT    = 9

.const ITEM_ID_CAPACITY = 376
.const ID_KNOWN_BYTES   = 47
.assert "ID_KNOWN_BYTES covers ITEM_TYPE_COUNT", ID_KNOWN_BYTES * 8 >= ITEM_TYPE_COUNT, true
.assert "ID_KNOWN_BYTES matches ITEM_ID_CAPACITY", ID_KNOWN_BYTES, floor((ITEM_ID_CAPACITY + 7) / 8)
.assert "Page 0 ends at Hard Leather Boots (254) and Page 1 starts at Leather Gloves (255)", ITEM_HARD_LEATHER_BOOTS == ITEM_PAGE_SIZE - 1 && ITEM_LEATHER_GLOVES == ITEM_PAGE_SIZE && ITEM_BROKEN_STICK == ITEM_TYPE_COUNT - 1, true

// Active Base-255 page bit for paged helpers ($00 for 0..254, ITEM_PAGE_BIT=$40 for 255..360).
item_cur_page: .byte 0

// Known-item identification state (Save Format V2, 47 bytes = 376 bits)
#if PLATFORM_ID_KNOWN_EXTERNAL
.label id_known_bits = PLATFORM_ID_KNOWN_BASE
#else
id_known_bits: .fill ID_KNOWN_BYTES, 0
#endif

idk_bit_mask: .byte 1, 2, 4, 8, 16, 32, 64, 128
idk_mask:     .byte 0
idk_hi:       .byte 0

// idk_index_x / idk_index_a — Compute byte index and bit mask for paged item
// (item_cur_page, A/X). Logical ID = slot_lo + (page_bit ? 255 : 0).
// Output: idk_mask = 1 << (logical_id & 7), Y = logical_id >> 3 (0..46),
//         A = id_known_bits,y.
// Clobbers: A, Y (preserves X)
idk_index_x:
    txa
idk_index_a:
    ldy #0
    bit item_cur_page
    bvc !idk_p0+
    clc
    adc #ITEM_PAGE_SIZE
    bcc !idk_p0+
    ldy #32                     // +256 bytes >> 3 == +32 bytes
!idk_p0:
    sty idk_hi
    pha
    and #7
    tay
    lda idk_bit_mask,y
    sta idk_mask
    pla
    lsr
    lsr
    lsr
    clc
    adc idk_hi
    tay
    lda id_known_bits,y
    rts

// id_known_test — Report whether paged item (item_cur_page, X) is identified/known.
// Input:  X = item slot_lo (0..254), item_cur_page = $00 or $40
// Output: A = 0 and Z set when the item is UNKNOWN
// Clobbers: A, Y (X preserved)
id_known_test:
    jsr idk_index_x
    and idk_mask
    rts

// ============================================================
// piq_quaff_identify — Mark paged item (item_cur_page, X) identified on quaff
// Heal-family potions on Page 0 at full HP are a silent no-op: no message and
// no identification. Everything else identifies on quaff.
// Input: X = item slot_lo, item_cur_page ($00 or $40). Clobbers: A, Y (X preserved).
// ============================================================
#if HAL_PLATFORM_QUAFF_IDENTIFY_RESIDENT
.assert "Heal-family potions live on Page 0", ITEM_PAGE_POTION_OF_CURE_LIGHT_WOUNDS == 0 && ITEM_PAGE_POTION_OF_CURE_SERIOUS_WOUNDS == 0 && ITEM_PAGE_POTION_OF_HEALING == 0 && ITEM_PAGE_POTION_OF_CURE_CRITICAL_WOUNDS == 0, true
piq_quaff_identify:
    bit item_cur_page
    bvs !pqi_ident+             // All Page 1 potions identify unconditionally on quaff
    txa
    cmp #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    beq !pqi_heal+
    cmp #ITEM_SLOT_POTION_OF_CURE_SERIOUS_WOUNDS
    beq !pqi_heal+
    cmp #ITEM_SLOT_POTION_OF_HEALING
    beq !pqi_heal+
    cmp #ITEM_SLOT_POTION_OF_CURE_CRITICAL_WOUNDS
    beq !pqi_heal+
!pqi_ident:
    jmp id_known_set            // (item_cur_page, X)
!pqi_heal:
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

// id_known_set — Mark paged item (item_cur_page, X) as identified/known.
// Input:  X = item slot_lo, item_cur_page
// Clobbers: A, Y (X preserved)
id_known_set:
    txa
idks_a:
    jsr idk_index_a
    ora idk_mask
    sta id_known_bits,y
    rts

// id_known_set_y — Mark paged item (item_cur_page, Y) as identified/known.
// Input:  Y = item slot_lo, item_cur_page
// Clobbers: A, Y (X preserved)
id_known_set_y:
    tya
    jmp idks_a

#if C64_UNIT_TEST || C128_UNIT_TEST
// id_known_clear — Mark paged item (item_cur_page, X) as unknown (tests only).
// Input:  X = item slot_lo, item_cur_page
// Clobbers: A, Y (X preserved)
id_known_clear:
    jsr idk_index_x
    lda idk_mask
    eor #$ff
    and id_known_bits,y
    sta id_known_bits,y
    rts
#endif
