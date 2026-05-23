// test_item_desc.s — Runtime tests for the real item description formatter
//
// Results at $0400-$0406: $01 = pass, $00 = fail per test (7 tests)

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_finish:
    ldx #6
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0830 "Main"

.encoding "screencode_mixed"

#import "../../common/zeropage.s"
#import "../memory.s"
#import "../screen.s"
#import "../../common/color.s"
#import "../../common/rng.s"
#import "../../common/numeric_format.s"
#import "../../common/item_defs.s"
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

#import "../../common/item_tables.s"
#import "../../common/item_identification.s"

banked_ego_put_suffix:
    rts
put_tool_ego_prefix:
    rts

inv_item_id: .fill TOTAL_INV_SLOTS, 0
inv_qty:     .fill TOTAL_INV_SLOTS, 0
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

#import "../../common/item_desc_banked.s"

test_start:
    jsr screen_clear

    ldx #6
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    // Test 1: identified weapon prints split to-hit/to-dam suffix.
    jsr test_prepare_row0
    lda #2                          // Dagger
    sta itemdesc_item_id
    lda #0
    sta itemdesc_qty
    sta itemdesc_p1
    sta itemdesc_to_ac
    sta itemdesc_ego
    lda #2
    sta itemdesc_to_hit
    lda #$fd                        // -3 damage
    sta itemdesc_to_dam
    lda #IF_IDENTIFIED
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_weapon_desc
    sta zp_ptr0
    lda #>expected_weapon_desc
    sta zp_ptr0_hi
    jsr assert_row0_prefix
    bcc !t1_fail+
    lda #$01
    sta tc_results+0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results+0

    // Test 2: identified armor prints base AC and to-AC with C64 bracket codes.
!t2:
    jsr test_prepare_row0
    lda #7                          // Leather Armor, base AC 4
    sta itemdesc_item_id
    lda #0
    sta itemdesc_qty
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_ego
    lda #1
    sta itemdesc_to_ac
    lda #IF_IDENTIFIED
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda $0400+14
    cmp #$1b                        // '[' screen code, not PETSCII '['
    bne !t2_fail+
    lda $0400+15
    cmp #$34                        // '4'
    bne !t2_fail+
    lda $0400+16
    cmp #$2c                        // ','
    bne !t2_fail+
    lda $0400+17
    cmp #$2b                        // '+'
    bne !t2_fail+
    lda $0400+18
    cmp #$31                        // '1'
    bne !t2_fail+
    lda $0400+19
    cmp #$1d                        // ']' screen code, not PETSCII ']'
    bne !t2_fail+
    lda #$01
    sta tc_results+1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results+1

    // Test 3: sensed-only items show the magik marker but not stat suffixes.
!t3:
    jsr test_prepare_row0
    lda #2                          // Dagger
    sta itemdesc_item_id
    lda #0
    sta itemdesc_qty
    sta itemdesc_p1
    sta itemdesc_to_ac
    sta itemdesc_ego
    lda #5
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    lda #IF_SENSED
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_sensed_desc
    sta zp_ptr0
    lda #>expected_sensed_desc
    sta zp_ptr0_hi
    jsr assert_row0_prefix
    bcc !t3_fail+
    lda $0400+14
    cmp #$20
    bne !t3_fail+
    lda #$01
    sta tc_results+2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results+2

    // Test 4: inventory ammo stacks show visible quantity.
!t4:
    jsr test_prepare_row0
    lda #53                         // Bolt
    sta inv_item_id
    lda #6
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_to_hit
    sta inv_to_dam
    sta inv_to_ac
    sta inv_flags
    sta inv_ego
    ldx #0
    jsr itemdesc_put_inv_slot

    lda #<expected_bolt_stack_desc
    sta zp_ptr0
    lda #>expected_bolt_stack_desc
    sta zp_ptr0_hi
    jsr assert_row0_prefix
    bcc !t4_fail+
    lda #$01
    sta tc_results+3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results+3

    // Test 5: known scrolls use Umoria-style category names.
!t5:
    jsr test_prepare_row0
    lda #1
    sta id_known + 21
    lda #21                         // Identify
    sta itemdesc_item_id
    lda #0
    sta itemdesc_qty
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    sta itemdesc_ego
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_identify_scroll_desc
    sta zp_ptr0
    lda #>expected_identify_scroll_desc
    sta zp_ptr0_hi
    jsr assert_row0_prefix
    bcc !t5_fail+
    lda #$01
    sta tc_results+4
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results+4

    // Test 6: known prayer books include the book category text.
!t6:
    jsr test_prepare_row0
    lda #48                         // Priest book 1
    sta itemdesc_item_id
    lda #0
    sta itemdesc_qty
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    sta itemdesc_ego
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_prayer_book_desc
    sta zp_ptr0
    lda #>expected_prayer_book_desc
    sta zp_ptr0_hi
    jsr assert_row0_prefix
    bcc !t6_fail+
    lda #$01
    sta tc_results+5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results+5

    // Test 7: every known base item name decodes exactly.
!t7:
    jsr test_all_known_item_names
    bcc !t7_fail+
    lda #$01
    sta tc_results+6
    jmp !tests_done+
!t7_fail:
    lda #$00
    sta tc_results+6

!tests_done:
    jmp test_finish

test_prepare_row0:
    jsr screen_clear
    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    rts

assert_row0_prefix:
    ldy #0
!loop:
    lda (zp_ptr0),y
    beq !ok+
    cmp $0400,y
    bne !fail+
    iny
    cpy #40
    bcc !loop-
!fail:
    clc
    rts
!ok:
    sec
    rts

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

expected_weapon_desc:
    .text "Dagger (+2,-3)" ; .byte 0
expected_sensed_desc:
    .text "Dagger (magik)" ; .byte 0
expected_bolt_stack_desc:
    .text "6 Bolt" ; .byte 0
expected_identify_scroll_desc:
    .text "Scroll of Identify" ; .byte 0
expected_prayer_book_desc:
    .text "Holy Book of Prayers Beginners Handbook" ; .byte 0

expected_item_name_lo:
    .byte <ein_0, <ein_1, <ein_2, <ein_3, <ein_4, <ein_5, <ein_6, <ein_7
    .byte <ein_8, <ein_9, <ein_10, <ein_11, <ein_12, <ein_13, <ein_14, <ein_15
    .byte <ein_16, <ein_17, <ein_18, <ein_19, <ein_20, <ein_21, <ein_22, <ein_23
    .byte <ein_24, <ein_25, <ein_26, <ein_27, <ein_28, <ein_29, <ein_30, <ein_31
    .byte <ein_32, <ein_33, <ein_34, <ein_35, <ein_36, <ein_37, <ein_38, <ein_39
    .byte <ein_40, <ein_41, <ein_42, <ein_43, <ein_44, <ein_45, <ein_46, <ein_47
    .byte <ein_48, <ein_49, <ein_50, <ein_51, <ein_52, <ein_53, <ein_54, <ein_55
    .byte <ein_56, <ein_57, <ein_58, <ein_59, <ein_60, <ein_61, <ein_62, <ein_63
expected_item_name_hi:
    .byte >ein_0, >ein_1, >ein_2, >ein_3, >ein_4, >ein_5, >ein_6, >ein_7
    .byte >ein_8, >ein_9, >ein_10, >ein_11, >ein_12, >ein_13, >ein_14, >ein_15
    .byte >ein_16, >ein_17, >ein_18, >ein_19, >ein_20, >ein_21, >ein_22, >ein_23
    .byte >ein_24, >ein_25, >ein_26, >ein_27, >ein_28, >ein_29, >ein_30, >ein_31
    .byte >ein_32, >ein_33, >ein_34, >ein_35, >ein_36, >ein_37, >ein_38, >ein_39
    .byte >ein_40, >ein_41, >ein_42, >ein_43, >ein_44, >ein_45, >ein_46, >ein_47
    .byte >ein_48, >ein_49, >ein_50, >ein_51, >ein_52, >ein_53, >ein_54, >ein_55
    .byte >ein_56, >ein_57, >ein_58, >ein_59, >ein_60, >ein_61, >ein_62, >ein_63

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

item_name_test_id: .byte 0
tc_results: .fill 7, $ff

item_desc_test_body_end:
.assert "Item desc test stays below MAP_BASE", item_desc_test_body_end <= MAP_BASE, true
