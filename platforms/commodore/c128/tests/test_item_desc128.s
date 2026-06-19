#importonce
// test_item_desc128.s — C128 VDC coverage for real item descriptions

#import "../../../../core/zeropage.s"
#import "../screen_vdc.s"
#import "../../../../core/color.s"
#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/item_defs.s"
.const HD_DECODE_BUF_SIZE = 64
hd_decode_buf: .fill HD_DECODE_BUF_SIZE, 0

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

#import "../../../../core/item_tables.s"
#import "../../../../core/item_identification.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $5000 "Test Code"

banked_ego_put_suffix:
    rts

put_tool_ego_prefix:
    rts

inv_item_id: .fill TOTAL_INV_SLOTS, 0
inv_p1:      .fill TOTAL_INV_SLOTS, 0
inv_to_hit:  .fill TOTAL_INV_SLOTS, 0
inv_to_dam:  .fill TOTAL_INV_SLOTS, 0
inv_to_ac:   .fill TOTAL_INV_SLOTS, 0
inv_flags:   .fill TOTAL_INV_SLOTS, 0
inv_ego:     .fill TOTAL_INV_SLOTS, 0

si_item_id: .byte 0
si_p1:      .byte 0
si_to_hit:  .byte 0
si_to_dam:  .byte 0
si_to_ac:   .byte 0
si_meta:    .byte 0
fi_add_flags: .byte 0
fi_add_ego:   .byte 0

#import "../../../../core/item_desc_banked.s"

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #COL_WHITE
    sta zp_text_color
    jsr screen_clear

    // Test 1: identified weapon prints split to-hit/to-dam suffix.
    jsr test_prepare_row0
    lda #2
    sta itemdesc_item_id
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_ac
    sta itemdesc_ego
    lda #2
    sta itemdesc_to_hit
    lda #$fd
    sta itemdesc_to_dam
    lda #IF_IDENTIFIED
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_weapon_vdc
    sta zp_ptr0
    lda #>expected_weapon_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !weapon_ok+
    jmp test_fail
!weapon_ok:

    // Test 2: identified armor prints base AC and to-AC with bracket glyphs.
    jsr test_prepare_row0
    lda #7
    sta itemdesc_item_id
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_ego
    lda #1
    sta itemdesc_to_ac
    lda #IF_IDENTIFIED
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_armor_suffix_vdc
    sta zp_ptr0
    lda #>expected_armor_suffix_vdc
    sta zp_ptr0_hi
    lda #14
    jsr assert_row0_from_col
    bcs !armor_ok+
    jmp test_fail
!armor_ok:

    // Test 3: sensed-only items show magik but no stat suffix leakage.
    jsr test_prepare_row0
    lda #2
    sta itemdesc_item_id
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_ac
    sta itemdesc_ego
    lda #5
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    lda #IF_SENSED
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_sensed_vdc
    sta zp_ptr0
    lda #>expected_sensed_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !sensed_prefix_ok+
    jmp test_fail
!sensed_prefix_ok:
    lda #14
    jsr read_row0_col
    cmp #SC_SPACE
    beq !sensed_ok+
    jmp test_fail
!sensed_ok:

    // Test 4: known scrolls use Umoria-style category names.
    jsr test_prepare_row0
    lda #1
    sta id_known + 21
    lda #21
    sta itemdesc_item_id
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    sta itemdesc_ego
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_identify_scroll_vdc
    sta zp_ptr0
    lda #>expected_identify_scroll_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !scroll_ok+
    jmp test_fail
!scroll_ok:

    // Test 5: known prayer books include the book category text.
    jsr test_prepare_row0
    lda #48
    sta itemdesc_item_id
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    sta itemdesc_ego
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_prayer_book_vdc
    sta zp_ptr0
    lda #>expected_prayer_book_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !book_ok+
    jmp test_fail
!book_ok:

    // Test 6: every known base item name decodes exactly.
    jsr test_all_known_item_names
    bcs !names_ok+
    jmp test_fail
!names_ok:

    jmp test_pass

test_prepare_row0:
    jsr screen_clear
    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    rts

// Input: A = row 0 column, zp_ptr0 = expected VDC bytes, 0-terminated.
assert_row0_from_col:
    sta assert_col
    lda #0
    sta zp_cursor_row
    lda assert_col
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldy #0
!loop:
    lda (zp_ptr0),y
    beq !ok+
    sta assert_expected
    sty assert_idx
    ldx #31
    jsr vdc_read_reg
    ldy assert_idx
    cmp assert_expected
    bne !fail+
    iny
    cpy #80
    bcc !loop-
!fail:
    clc
    rts
!ok:
    sec
    rts

read_row0_col:
    sta zp_cursor_col
    lda #0
    sta zp_cursor_row
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jmp vdc_read_reg

test_all_known_item_names:
    lda #0
    sta item_name_test_id
!next_item:
    ldx item_name_test_id
    lda #1
    sta id_known,x
    txa
    jsr item_get_name_ptr
    lda zp_ptr0
    sta zp_ptr1
    lda zp_ptr0_hi
    sta zp_ptr1_hi
    ldx item_name_test_id
    lda expected_item_name_lo,x
    sta zp_ptr0
    lda expected_item_name_hi,x
    sta zp_ptr0_hi
    jsr assert_string_ptrs_equal
    bcc !fail+
    inc item_name_test_id
    lda item_name_test_id
    cmp #ITEM_TYPE_COUNT
    bcc !next_item-
    sec
    rts
!fail:
    clc
    rts

assert_string_ptrs_equal:
    ldy #0
!loop:
    lda (zp_ptr0),y
    cmp (zp_ptr1),y
    bne !fail+
    cmp #0
    beq !ok+
    iny
    cpy #HD_DECODE_BUF_SIZE
    bcc !loop-
!fail:
    clc
    rts
!ok:
    sec
    rts

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass

// Expected VDC Set 1 bytes. Lowercase letters are $01-$1a.
expected_weapon_vdc:
    .byte $44, $01, $07, $07, $05, $12, $20, $28, $2b, $32, $2c, $2d, $33, $29, 0
expected_armor_suffix_vdc:
    .byte $1b, $34, $2c, $2b, $31, $1d, 0
expected_sensed_vdc:
    .byte $44, $01, $07, $07, $05, $12, $20, $28, $0d, $01, $07, $09, $0b, $29, 0
expected_identify_scroll_vdc:
    .byte $53, $03, $12, $0f, $0c, $0c, $20, $0f, $06, $20, $49, $04, $05, $0e, $14, $09, $06, $19, 0
expected_prayer_book_vdc:
    .byte $48, $0f, $0c, $19, $20, $42, $0f, $0f, $0b, $20, $0f, $06, $20, $50, $12, $01, $19, $05, $12, $13, $20, $42, $05, $07, $09, $0e, $0e, $05, $12, $13, $20, $48, $01, $0e, $04, $02, $0f, $0f, $0b, 0

expected_item_name_lo:
    .byte <ein_0, <ein_1, <ein_2, <ein_3, <ein_4, <ein_5, <ein_6, <ein_7
    .byte <ein_8, <ein_9, <ein_10, <ein_11, <ein_12, <ein_13, <ein_14, <ein_15
    .byte <ein_16, <ein_17, <ein_18, <ein_19, <ein_20, <ein_21, <ein_22, <ein_23
    .byte <ein_24, <ein_25, <ein_26, <ein_27, <ein_28, <ein_29, <ein_30, <ein_31
    .byte <ein_32, <ein_33, <ein_34, <ein_35, <ein_36, <ein_37, <ein_38, <ein_39
    .byte <ein_40, <ein_41, <ein_42, <ein_43, <ein_44, <ein_45, <ein_46, <ein_47
    .byte <ein_48, <ein_49, <ein_50, <ein_51, <ein_52, <ein_53, <ein_54, <ein_55
    .byte <ein_56, <ein_57, <ein_58, <ein_59, <ein_60, <ein_61, <ein_62, <ein_63
    .byte <ein_64, <ein_65
    .byte <ein_66, <ein_67, <ein_68, <ein_69
    .byte <ein_70, <ein_71, <ein_72, <ein_73
    .byte <ein_74, <ein_75, <ein_76, <ein_77
    .byte <ein_78, <ein_79
    .byte <ein_80, <ein_81
    .byte <ein_82, <ein_83, <ein_84, <ein_85, <ein_86, <ein_87
    .byte <ein_88, <ein_89, <ein_90, <ein_91
    .byte <ein_92, <ein_93, <ein_94, <ein_95
expected_item_name_hi:
    .byte >ein_0, >ein_1, >ein_2, >ein_3, >ein_4, >ein_5, >ein_6, >ein_7
    .byte >ein_8, >ein_9, >ein_10, >ein_11, >ein_12, >ein_13, >ein_14, >ein_15
    .byte >ein_16, >ein_17, >ein_18, >ein_19, >ein_20, >ein_21, >ein_22, >ein_23
    .byte >ein_24, >ein_25, >ein_26, >ein_27, >ein_28, >ein_29, >ein_30, >ein_31
    .byte >ein_32, >ein_33, >ein_34, >ein_35, >ein_36, >ein_37, >ein_38, >ein_39
    .byte >ein_40, >ein_41, >ein_42, >ein_43, >ein_44, >ein_45, >ein_46, >ein_47
    .byte >ein_48, >ein_49, >ein_50, >ein_51, >ein_52, >ein_53, >ein_54, >ein_55
    .byte >ein_56, >ein_57, >ein_58, >ein_59, >ein_60, >ein_61, >ein_62, >ein_63
    .byte >ein_64, >ein_65
    .byte >ein_66, >ein_67, >ein_68, >ein_69
    .byte >ein_70, >ein_71, >ein_72, >ein_73
    .byte >ein_74, >ein_75, >ein_76, >ein_77
    .byte >ein_78, >ein_79
    .byte >ein_80, >ein_81
    .byte >ein_82, >ein_83, >ein_84, >ein_85, >ein_86, >ein_87
    .byte >ein_88, >ein_89, >ein_90, >ein_91
    .byte >ein_92, >ein_93, >ein_94, >ein_95

ein_0:  .text "Gold (small)" ; .byte 0
ein_1:  .text "Gold (large)" ; .byte 0
ein_2:  .text "Dagger" ; .byte 0
ein_3:  .text "Short Sword" ; .byte 0
ein_4:  .text "Long Sword" ; .byte 0
ein_5:  .text "Mace" ; .byte 0
ein_6:  .text "Robe" ; .byte 0
ein_7:  .text "Leather Armor" ; .byte 0
ein_8:  .text "Chain Mail" ; .byte 0
ein_9:  .text "Small Shield" ; .byte 0
ein_10: .text "Iron Helm" ; .byte 0
ein_11: .text "Leather Gloves" ; .byte 0
ein_12: .text "Leather Boots" ; .byte 0
ein_13: .text "Wooden Torch" ; .byte 0
ein_14: .text "Brass Lantern" ; .byte 0
ein_15: .text "Ration of Food" ; .byte 0
ein_16: .text "Slime Mold" ; .byte 0
ein_17: .text "Potion of Cure Light Wounds" ; .byte 0
ein_18: .text "Potion of Speed" ; .byte 0
ein_19: .text "Potion of Poison" ; .byte 0
ein_20: .text "Scroll of Light" ; .byte 0
ein_21: .text "Scroll of Identify" ; .byte 0
ein_22: .text "Scroll of Teleportation" ; .byte 0
ein_23: .text "Ring of Protection" ; .byte 0
ein_24: .text "Ring of Strength" ; .byte 0
ein_25: .text "Potion of Cure Serious Wounds" ; .byte 0
ein_26: .text "Potion of Restore Mana" ; .byte 0
ein_27: .text "Potion of Heroism" ; .byte 0
ein_28: .text "Potion of Blindness" ; .byte 0
ein_29: .text "Potion of Confusion" ; .byte 0
ein_30: .text "Potion of Detect Monsters" ; .byte 0
ein_31: .text "Potion of Infravision" ; .byte 0
ein_32: .text "Scroll of Word of Recall" ; .byte 0
ein_33: .text "Scroll of Remove Curse" ; .byte 0
ein_34: .text "Scroll of Enchant Weapon" ; .byte 0
ein_35: .text "Scroll of Enchant Armor" ; .byte 0
ein_36: .text "Scroll of Monster Confusion" ; .byte 0
ein_37: .text "Scroll of Aggravate" ; .byte 0
ein_38: .text "Scroll of Protect from Evil" ; .byte 0
ein_39: .text "Wand of Light" ; .byte 0
ein_40: .text "Wand of Lightning" ; .byte 0
ein_41: .text "Wand of Frost" ; .byte 0
ein_42: .text "Wand of Stinking Cloud" ; .byte 0
ein_43: .text "Staff of Light" ; .byte 0
ein_44: .text "Staff of Detect Monsters" ; .byte 0
ein_45: .text "Staff of Teleportation" ; .byte 0
ein_46: .text "Staff of Cure Light Wounds" ; .byte 0
ein_47: .text "Spellbook Beginners-Magick" ; .byte 0
ein_48: .text "Holy Book of Prayers Beginners Handbook" ; .byte 0
ein_49: .text "Short Bow" ; .byte 0
ein_50: .text "Light Crossbow" ; .byte 0
ein_51: .text "Sling" ; .byte 0
ein_52: .text "Arrow" ; .byte 0
ein_53: .text "Bolt" ; .byte 0
ein_54: .text "Rock" ; .byte 0
ein_55: .text "Spellbook Magick I" ; .byte 0
ein_56: .text "Spellbook Magick II" ; .byte 0
ein_57: .text "Spellbook The Mages Guide to Power" ; .byte 0
ein_58: .text "Holy Book of Prayers Words of Wisdom" ; .byte 0
ein_59: .text "Holy Book of Prayers Chants and Blessings" ; .byte 0
ein_60: .text "Holy Book of Prayers Exorcism" ; .byte 0
ein_61: .text "Flask of Oil" ; .byte 0
ein_62: .text "Shovel" ; .byte 0
ein_63: .text "Pick" ; .byte 0
ein_64: .text "Main Gauche" ; .byte 0
ein_65: .text "Studded Leather Armor" ; .byte 0
ein_66: .text "Rapier" ; .byte 0
ein_67: .text "Broad Sword" ; .byte 0
ein_68: .text "Bastard Sword" ; .byte 0
ein_69: .text "Two-Handed Sword" ; .byte 0
ein_70: .text "Scimitar" ; .byte 0
ein_71: .text "Battle Axe" ; .byte 0
ein_72: .text "War Hammer" ; .byte 0
ein_73: .text "Morningstar" ; .byte 0
ein_74: .text "Spear" ; .byte 0
ein_75: .text "Pike" ; .byte 0
ein_76: .text "Halberd" ; .byte 0
ein_77: .text "Quarterstaff" ; .byte 0
ein_78: .text "Large Shield" ; .byte 0
ein_79: .text "Hard Leather Armor" ; .byte 0
ein_80: .text "Scale Mail" ; .byte 0
ein_81: .text "Plate Mail" ; .byte 0
ein_82: .text "Cloak" ; .byte 0
ein_83: .text "Steel Helm" ; .byte 0
ein_84: .text "Gauntlets" ; .byte 0
ein_85: .text "Soft Leather Boots" ; .byte 0
ein_86: .text "Hard Leather Boots" ; .byte 0
ein_87: .text "Metal Cap" ; .byte 0
ein_88: .text "Sabre" ; .byte 0
ein_89: .text "Cutlass" ; .byte 0
ein_90: .text "Tulwar" ; .byte 0
ein_91: .text "Katana" ; .byte 0
ein_92: .text "Flail" ; .byte 0
ein_93: .text "Lucerne Hammer" ; .byte 0
ein_94: .text "Broad Axe" ; .byte 0
ein_95: .text "Awl-Pike" ; .byte 0

assert_col: .byte 0
assert_idx: .byte 0
assert_expected: .byte 0
item_name_test_id: .byte 0
inv_qty: .fill TOTAL_INV_SLOTS, 0
