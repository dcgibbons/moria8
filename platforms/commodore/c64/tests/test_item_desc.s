// test_item_desc.s — Runtime tests for the real item description formatter
//
// Results at $0400-$0409: $01 = pass, $00 = fail per test (10 tests)

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_finish:
    ldx #9
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0830 "Main"

.encoding "screencode_mixed"

#import "../../../../core/zeropage.s"
#import "../memory.s"
#import "../screen.s"
#import "../../../../core/color.s"
#import "mmu_macros.s"

// Thunks from config.s, which is not imported by tests (main.s-only file).
mmu_safe_map_read_ptr0:
    lda (zp_ptr0),y
    rts
mmu_safe_map_write_ptr0:
    sta (zp_ptr0),y
    rts
mmu_safe_map_read_ptr1:
    lda (zp_ptr1),y
    rts
mmu_safe_map_write_ptr1:
    sta (zp_ptr1),y
    rts
mmu_safe_db_read_ptr0:
    lda (zp_ptr0),y
    rts
mmu_safe_db_write_ptr0:
    sta (zp_ptr0),y
    rts
mmu_safe_db_read_ptr1:
    lda (zp_ptr1),y
    rts
mmu_safe_db_write_ptr1:
    sta (zp_ptr1),y
    rts

#import "../../../../core/rng.s"
#import "../../../../core/numeric_format.s"
#import "../../../../core/item_defs.s"
.const HD_DECODE_BUF_SIZE = 64
hd_decode_buf: .fill HD_DECODE_BUF_SIZE, 0

#import "../../../../core/item_tables.s"
#import "../../../../core/item_identification.s"

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

#import "../../../../core/item_desc_banked.s"

test_start:
    jsr screen_clear

    ldx #9
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
    ldx #21
    jsr id_known_set
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

    // Test 7: inventory formatter renders appended weapon ID 64.
!t7:
    jsr test_prepare_row0
    lda #64
    sta inv_item_id
    lda #1
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

    lda #<expected_main_gauche_desc
    sta zp_ptr0
    lda #>expected_main_gauche_desc
    sta zp_ptr0_hi
    jsr assert_row0_prefix
    bcc !t7_fail+
    lda #$01
    sta tc_results+6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results+6

    // Test 8: inventory formatter renders appended armor ID 65.
!t8:
    jsr test_prepare_row0
    lda #65
    sta inv_item_id
    lda #1
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

    lda #<expected_studded_leather_desc
    sta zp_ptr0
    lda #>expected_studded_leather_desc
    sta zp_ptr0_hi
    jsr assert_row0_prefix
    bcc !t8_fail+
    lda #$01
    sta tc_results+7
    jmp !t9+
!t8_fail:
    lda #$00
    sta tc_results+7

    // Test 9: identified amulets show their positive stat bonus and all
    // known base item names decode exactly.
!t9:
    jsr test_prepare_row0
    lda #ITEM_TYPE_AMULET_WISDOM
    sta itemdesc_item_id
    lda #0
    sta itemdesc_qty
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    sta itemdesc_ego
    lda #3
    sta itemdesc_p1
    lda #IF_IDENTIFIED
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_amulet_desc
    sta zp_ptr0
    lda #>expected_amulet_desc
    sta zp_ptr0_hi
    jsr assert_row0_prefix
    bcc !t9_fail+
    jsr test_all_known_item_names
    bcc !t9_fail+
    lda #$01
    sta tc_results+8
    jmp !t10+
!t9_fail:
    lda #$00
    sta tc_results+8

    // Test 10: pool-wrap coverage — appended randomized-class rows use the
    // approved class-local indexes, every randomized-class type resolves
    // inside its pool, and wrapped indexes produce distinct appearances.
!t10:
    jsr item_init_identification

    // Part A: approved wrap indexes for appended randomized-class rows.
    ldx #0
!t10a_loop:
    stx t10_cursor
    lda t10_wrap_ids,x
    tax
    jsr iuk_index_for_type
    ldx t10_cursor
    cmp t10_wrap_idx,x
    bne !t10_fail+
    inx
    cpx #27
    bcc !t10a_loop-

    // Part B: every randomized-class type resolves inside its pool.
    ldx #0
!t10b_loop:
    stx t10_cursor
    ldy it_category,x
    cpy #ICAT_POTION
    beq !t10b_pool12+
    cpy #ICAT_SCROLL
    beq !t10b_pool12+
    cpy #ICAT_RING
    beq !t10b_pool4+
    cpy #ICAT_WAND
    beq !t10b_pool5+
    cpy #ICAT_STAFF
    beq !t10b_pool5+
    jmp !t10b_next+
!t10b_pool12:
    lda #12
    bne !t10b_check+
!t10b_pool4:
    lda #4
    bne !t10b_check+
!t10b_pool5:
    lda #5
!t10b_check:
    sta t10_pool_max
    ldx t10_cursor
    jsr iuk_index_for_type
    cmp t10_pool_max
    bcs !t10_fail+
!t10b_next:
    ldx t10_cursor
    inx
    cpx #ITEM_TYPE_COUNT
    bcc !t10b_loop-

    // Part C: distinct class-local indexes (96 -> 10, 98 -> 0) produce
    // distinct unknown appearances; index-0-only tables would collapse them.
    // Unknown names decode into one shared buffer, so compare contents.
    lda #96
    jsr item_get_name_ptr
    ldy #0
!t10_copy:
    lda (zp_ptr0),y
    sta t10_name_buf,y
    beq !t10_copy_done+
    iny
    cpy #32
    bcc !t10_copy-
!t10_copy_done:
    lda #98
    jsr item_get_name_ptr
    ldy #0
!t10_cmp:
    lda (zp_ptr0),y
    cmp t10_name_buf,y
    bne !t10_pass+
    cmp #0
    beq !t10_fail+
    iny
    cpy #32
    bcc !t10_cmp-
!t10_fail:
    lda #$00
    sta tc_results+9
    jmp !tests_done+
!t10_pass:
    lda #$01
    sta tc_results+9

!tests_done:
    jmp test_finish

t10_cursor:  .byte 0
t10_pool_max: .byte 0
t10_name_buf: .fill 32, 0
t10_wrap_ids:
    .byte 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107
    .byte 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119
    .byte 120, 121, 126, 127
t10_wrap_idx:
    .byte 10, 11, 0, 1, 2, 10, 11, 0, 1, 2, 3, 4
    .byte 5, 2, 3, 0, 1, 2, 4, 0, 1, 2, 3, 4
    .byte 0, 1, 3, 2

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
    jsr id_known_set
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
expected_main_gauche_desc:
    .text "Main Gauche" ; .byte 0
expected_studded_leather_desc:
    .text "Studded Leather Armor" ; .byte 0
expected_amulet_desc:
    .text "Amulet of Wisdom (+3)" ; .byte 0

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
    .byte <ein_96, <ein_97, <ein_98, <ein_99
    .byte <ein_100, <ein_101, <ein_102, <ein_103
    .byte <ein_104, <ein_105, <ein_106, <ein_107
    .byte <ein_108, <ein_109, <ein_110, <ein_111
    .byte <ein_112, <ein_113, <ein_114, <ein_115
    .byte <ein_116, <ein_117, <ein_118, <ein_119
    .byte <ein_120, <ein_121, <ein_122, <ein_123
    .byte <ein_124, <ein_125, <ein_126, <ein_127
    .byte <ein_128, <ein_129, <ein_130, <ein_131
    .byte <ein_132, <ein_133, <ein_134
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
    .byte >ein_96, >ein_97, >ein_98, >ein_99
    .byte >ein_100, >ein_101, >ein_102, >ein_103
    .byte >ein_104, >ein_105, >ein_106, >ein_107
    .byte >ein_108, >ein_109, >ein_110, >ein_111
    .byte >ein_112, >ein_113, >ein_114, >ein_115
    .byte >ein_116, >ein_117, >ein_118, >ein_119
    .byte >ein_120, >ein_121, >ein_122, >ein_123
    .byte >ein_124, >ein_125, >ein_126, >ein_127
    .byte >ein_128, >ein_129, >ein_130, >ein_131
    .byte >ein_132, >ein_133, >ein_134

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
ein_96: .text "Potion of Healing" ; .byte 0
ein_97: .text "Potion of Restoration" ; .byte 0
ein_98: .text "Potion of Resist Heat" ; .byte 0
ein_99: .text "Potion of Resist Cold" ; .byte 0
ein_100: .text "Potion of Cure Critical Wounds" ; .byte 0
ein_101: .text "Scroll of Teleport Level" ; .byte 0
ein_102: .text "Scroll of Magic Mapping" ; .byte 0
ein_103: .text "Scroll of Object Detection" ; .byte 0
ein_104: .text "Scroll of Recharging" ; .byte 0
ein_105: .text "Scroll of Rune of Protection" ; .byte 0
ein_106: .text "Scroll of Genocide" ; .byte 0
ein_107: .text "Scroll of Mass Genocide" ; .byte 0
ein_108: .text "Scroll of *Destruction*" ; .byte 0
ein_109: .text "Ring of Resist Fire" ; .byte 0
ein_110: .text "Ring of Resist Cold" ; .byte 0
ein_111: .text "Ring of Speed" ; .byte 0
ein_112: .text "Ring of See Invisible" ; .byte 0
ein_113: .text "Ring of Slaying" ; .byte 0
ein_114: .text "Wand of Slow Monster" ; .byte 0
ein_115: .text "Wand of Stone-to-Mud" ; .byte 0
ein_116: .text "Wand of Teleport Away" ; .byte 0
ein_117: .text "Wand of Fire Balls" ; .byte 0
ein_118: .text "Wand of Cold Balls" ; .byte 0
ein_119: .text "Staff of Dispel Evil" ; .byte 0
ein_120: .text "Staff of Destruction" ; .byte 0
ein_121: .text "Staff of Speed" ; .byte 0
ein_122: .text "Mithril Chain Mail" ; .byte 0
ein_123: .text "Mithril Plate Mail" ; .byte 0
ein_124: .text "Amulet of Wisdom" ; .byte 0
ein_125: .text "Amulet of the Magi" ; .byte 0
ein_126: .text "Potion of Neutralize Poison" ; .byte 0
ein_127: .text "Staff of Remove Curse" ; .byte 0
ein_128: .text "Small Wooden Chest" ; .byte 0
ein_129: .text "Large Wooden Chest" ; .byte 0
ein_130: .text "Small Iron Chest" ; .byte 0
ein_131: .text "Large Iron Chest" ; .byte 0
ein_132: .text "Small Steel Chest" ; .byte 0
ein_133: .text "Large Steel Chest" ; .byte 0
ein_134: .text "Ruined Chest" ; .byte 0

item_name_test_id: .byte 0
tc_results: .fill 10, $ff
tc_results_end:

item_desc_test_body_end:
.assert "Item desc result count", tc_results_end - tc_results, 10
.assert "Item desc test stays below MAP_BASE", item_desc_test_body_end <= MAP_BASE, true
