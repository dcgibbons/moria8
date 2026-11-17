#importonce
// test_item_desc128.s — C128 VDC coverage for real 361-item & 55-ego descriptions,
// categories, base AC, display colors, and floor glyphs across Pages 0 & 1.

#import "../../../../core/zeropage.s"
#import "../../../../core/color.s"
#import "mmu_macros.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $1300 "Bootstrap"
test_start:
    sei
    lda #$3e
    sta $ff00
    jmp test_main
.assert "test_start stays below C128 BASIC ROM", test_start < $4000, true

.pc = $2100 "Test Code"

#import "../screen_vdc.s"

.const VDC_ITEM_CAT_LO_BASE     = $1100
.const VDC_ITEM_CAT_LO_SIZE     = $0f00
.const VDC_CHARSET_BASE         = $2000
.const VDC_ITEM_CAT_CELL_OFFSET = $08

disk_temp:              .byte 0
disk_status:            .byte 0
c128_runtime_load_bank: .byte 0
crl_sa:                 .byte 1

#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../shared/item_catalog/item_cat_data.s"
.label MAP_BASE = item_cat_data

c128_load_runtime_prg:
    clc
    rts

#import "../item_cat_vdc128.s"

// config128.s is not imported by tests; the unit test links all data into one
// RAM bank, so the map/db thunks are direct accesses here.
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
mmu_safe_huff_read_ptr0:
    lda (zp_ptr0),y
    rts
mmu_safe_db_write_ptr0:
    sta (zp_ptr0),y
    rts
mmu_safe_db_read_ptr1:
mmu_safe_huff_read_ptr1:
    lda (zp_ptr1),y
    rts
mmu_safe_db_write_ptr1:
    sta (zp_ptr1),y
    rts

#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/item_defs.s"

inv_item_id: .fill TOTAL_INV_SLOTS, FI_EMPTY
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
si_meta_hi: .byte 0
fi_item_id: .byte FI_EMPTY
fi_meta_hi: .byte 0
fi_add_flags: .byte 0
fi_add_ego:   .byte 0

#import "../../../../core/item_tables.s"
#import "../../../../core/item_identification.s"

banked_ego_put_suffix:
    and #EGO_ID_MASK
    beq !beps_done+
    cmp #EGO_TYPE_COUNT
    bcs !beps_done+
    jsr item_cat_decode_ego
    jmp hal_screen_put_string
!beps_done:
    rts

put_tool_ego_prefix:
    rts

#import "../../../../core/item_desc_banked.s"

test_main:
    sei
    cld
    ldx #$ff
    txs
    lda #$3e
    sta $ff00

    jsr test_seed_vdc_font_sentinels
    jsr c128_load_item_cat_vdc
    bcc !vdc_cat_loaded+
    jmp test_fail
!vdc_cat_loaded:
    jsr test_verify_vdc_cat_boundaries_and_fonts
    bcs !vdc_cat_verified+
    jmp test_fail
!vdc_cat_verified:

    jsr item_refresh_fixed_known
    lda #COL_WHITE
    sta zp_text_color
    jsr screen_clear

    // Test 1: identified weapon prints split to-hit/to-dam suffix.
    jsr test_prepare_row0
    lda #ITEM_SLOT_DAGGER
    sta itemdesc_item_id
    lda #1
    sta itemdesc_qty
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_ac
    lda #ITEM_PAGE_DAGGER
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
    lda #ITEM_SLOT_LEATHER_ARMOR
    sta itemdesc_item_id
    lda #1
    sta itemdesc_qty
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    lda #ITEM_PAGE_LEATHER_ARMOR
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
    lda #ITEM_SLOT_DAGGER
    sta itemdesc_item_id
    lda #1
    sta itemdesc_qty
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_ac
    lda #ITEM_PAGE_DAGGER
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
    lda #ITEM_PAGE_SCROLL_OF_IDENTIFY
    sta item_cur_page
    ldx #ITEM_SLOT_SCROLL_OF_IDENTIFY
    jsr id_known_set
    lda #ITEM_SLOT_SCROLL_OF_IDENTIFY
    sta itemdesc_item_id
    lda #1
    sta itemdesc_qty
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    sta itemdesc_flags
    lda #ITEM_PAGE_SCROLL_OF_IDENTIFY
    sta itemdesc_ego
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
    lda #ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_BEGINNERS_HANDBOOK
    sta itemdesc_item_id
    lda #1
    sta itemdesc_qty
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    sta itemdesc_flags
    lda #ITEM_PAGE_HOLY_BOOK_OF_PRAYERS_BEGINNERS_HANDBOOK
    sta itemdesc_ego
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

    // Test 6: identified amulets show their positive stat bonus.
    jsr test_prepare_row0
    lda #ITEM_SLOT_AMULET_OF_WISDOM
    sta itemdesc_item_id
    lda #1
    sta itemdesc_qty
    lda #3
    sta itemdesc_p1
    lda #0
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    lda #ITEM_PAGE_AMULET_OF_WISDOM
    sta itemdesc_ego
    lda #IF_IDENTIFIED
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_amulet_vdc
    sta zp_ptr0
    lda #>expected_amulet_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !amulet_ok+
    jmp test_fail
!amulet_ok:

    // Test 7: EQUIP_CLOAK (slot 32) formats Cloak [1,+2] via itemdesc_put_inv_slot.
    jsr test_prepare_row0
    lda #ITEM_SLOT_CLOAK
    sta inv_item_id + EQUIP_CLOAK
    lda #1
    sta inv_qty + EQUIP_CLOAK
    lda #2
    sta inv_to_ac + EQUIP_CLOAK
    lda #IF_IDENTIFIED
    sta inv_flags + EQUIP_CLOAK
    lda #ITEM_PAGE_CLOAK
    sta inv_ego + EQUIP_CLOAK
    ldx #EQUIP_CLOAK
    jsr itemdesc_put_inv_slot

    lda #<expected_cloak_vdc
    sta zp_ptr0
    lda #>expected_cloak_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !cloak_ok+
    jmp test_fail
!cloak_ok:

    // Test 8: ego #55 (" of Slay Animal"), Staff of Darkness, & final Page-1 item #360 ("Broken Stick").
    jsr test_prepare_row0
    lda #ITEM_SLOT_ARROW
    sta itemdesc_item_id
    lda #1
    sta itemdesc_qty
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    lda #(ITEM_PAGE_ARROW | EGO_AMMO_SLAY_ANIMAL)
    sta itemdesc_ego
    lda #IF_IDENTIFIED
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_ego55_vdc
    sta zp_ptr0
    lda #>expected_ego55_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !ego55_ok+
    jmp test_fail
!ego55_ok:

    jsr test_prepare_row0
    lda #ITEM_PAGE_STAFF_OF_DARKNESS_L50
    sta item_cur_page
    ldx #ITEM_SLOT_STAFF_OF_DARKNESS_L50
    jsr id_known_set
    lda #ITEM_SLOT_STAFF_OF_DARKNESS_L50
    sta itemdesc_item_id
    lda #1
    sta itemdesc_qty
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    sta itemdesc_flags
    lda #ITEM_PAGE_STAFF_OF_DARKNESS_L50
    sta itemdesc_ego
    jsr itemdesc_put_staged

    lda #<expected_staff_darkness_vdc
    sta zp_ptr0
    lda #>expected_staff_darkness_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !staff_dark_ok+
    jmp test_fail
!staff_dark_ok:

    jsr test_prepare_row0
    lda #ITEM_SLOT_BROKEN_STICK
    sta itemdesc_item_id
    lda #1
    sta itemdesc_qty
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    sta itemdesc_flags
    lda #ITEM_PAGE_BROKEN_STICK
    sta itemdesc_ego
    jsr itemdesc_put_staged

    lda #<expected_item360_vdc
    sta zp_ptr0
    lda #>expected_item360_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !item360_ok+
    jmp test_fail
!item360_ok:

    // Test 9: every known base item name 0..360 across Pages 0 and 1 decodes exactly.
    jsr test_all_known_item_names
    bcs !names_ok+
    jmp test_fail
!names_ok:

    // Test 10: every item 0..360 category, base AC, color, and floor glyph matches VMS spec.
    jsr test_all_item_props
    bcs !props_ok+
    jmp test_fail
!props_ok:

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
    sta item_cur_page
    sta item_name_test_id
!next_p0:
    lda #0
    sta item_cur_page
    ldx item_name_test_id
    jsr id_known_set
    lda #0
    sta item_cur_page
    lda item_name_test_id
    jsr item_get_name_ptr
    lda zp_ptr0
    sta zp_ptr1
    lda zp_ptr0_hi
    sta zp_ptr1_hi
    ldx item_name_test_id
    lda expected_item_name_p0_lo,x
    sta zp_ptr0
    lda expected_item_name_p0_hi,x
    sta zp_ptr0_hi
    jsr assert_string_ptrs_equal
    bcc !fail+
    inc item_name_test_id
    lda item_name_test_id
    cmp #ITEM_PAGE_SIZE
    bcc !next_p0-

    lda #0
    sta item_name_test_id
!next_p1:
    lda #ITEM_PAGE_BIT
    sta item_cur_page
    ldx item_name_test_id
    jsr id_known_set
    lda #ITEM_PAGE_BIT
    sta item_cur_page
    lda item_name_test_id
    jsr item_get_name_ptr
    lda zp_ptr0
    sta zp_ptr1
    lda zp_ptr0_hi
    sta zp_ptr1_hi
    ldx item_name_test_id
    lda expected_item_name_p1_lo,x
    sta zp_ptr0
    lda expected_item_name_p1_hi,x
    sta zp_ptr0_hi
    jsr assert_string_ptrs_equal
    bcc !fail+
    inc item_name_test_id
    lda item_name_test_id
    cmp #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)
    bcc !next_p1-
    sec
    rts
!fail:
    clc
    rts

test_all_item_props:
    lda #0
    sta item_name_test_id
!prop_p0:
    lda #0
    sta item_cur_page
    ldx item_name_test_id
    txa
    jsr item_get_category_a
    ldx item_name_test_id
    cmp expected_item_cat_p0,x
    bne !prop_fail+

    lda #0
    sta item_cur_page
    ldy item_name_test_id
    jsr item_get_base_ac
    ldx item_name_test_id
    cmp expected_item_ac_p0,x
    bne !prop_fail+

    lda #0
    sta item_cur_page
    lda item_name_test_id
    jsr item_get_color_a
    ldx item_name_test_id
    cmp expected_item_color_p0,x
    bne !prop_fail+

    lda #0
    sta item_cur_page
    ldx item_name_test_id
    jsr item_get_display_char
    ldx item_name_test_id
    cmp expected_item_glyph_p0,x
    bne !prop_fail+

    inc item_name_test_id
    lda item_name_test_id
    cmp #ITEM_PAGE_SIZE
    bcc !prop_p0-
    bcs !prop_p1_start+
!prop_fail:
    clc
    rts

!prop_p1_start:
    lda #0
    sta item_name_test_id
!prop_p1:
    lda #ITEM_PAGE_BIT
    sta item_cur_page
    ldx item_name_test_id
    txa
    jsr item_get_category_a
    ldx item_name_test_id
    cmp expected_item_cat_p1,x
    bne !prop_fail-

    lda #ITEM_PAGE_BIT
    sta item_cur_page
    ldy item_name_test_id
    jsr item_get_base_ac
    ldx item_name_test_id
    cmp expected_item_ac_p1,x
    bne !prop_fail-

    lda #ITEM_PAGE_BIT
    sta item_cur_page
    lda item_name_test_id
    jsr item_get_color_a
    ldx item_name_test_id
    cmp expected_item_color_p1,x
    bne !prop_fail-

    lda #ITEM_PAGE_BIT
    sta item_cur_page
    ldx item_name_test_id
    jsr item_get_display_char
    ldx item_name_test_id
    cmp expected_item_glyph_p1,x
    bne !prop_fail-

    inc item_name_test_id
    lda item_name_test_id
    cmp #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)
    bcc !prop_p1-
    sec
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
    cpy #ITEM_NAME_DECODE_BUF_SIZE
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
expected_amulet_vdc:
    .byte $41, $0d, $15, $0c, $05, $14, $20, $0f, $06, $20, $57, $09, $13, $04, $0f, $0d, $20, $28, $2b, $33, $29, 0
expected_cloak_vdc:
    .byte $43, $0c, $0f, $01, $0b, $20, $1b, $31, $2c, $2b, $32, $1d, 0
expected_ego55_vdc:
    .byte $41, $12, $12, $0f, $17, $20, $0f, $06, $20, $53, $0c, $01, $19, $20, $41, $0e, $09, $0d, $01, $0c, 0
expected_staff_darkness_vdc:
    .byte $53, $14, $01, $06, $06, $20, $0f, $06, $20, $44, $01, $12, $0b, $0e, $05, $13, $13, 0
expected_item360_vdc:
    .byte $42, $12, $0f, $0b, $05, $0e, $20, $53, $14, $09, $03, $0b, 0

expected_item_name_p0_lo:
    .byte <ein_0, <ein_1, <ein_2, <ein_3, <ein_4, <ein_5, <ein_6, <ein_7
    .byte <ein_8, <ein_9, <ein_10, <ein_11, <ein_12, <ein_13, <ein_14, <ein_15
    .byte <ein_16, <ein_17, <ein_18, <ein_19, <ein_20, <ein_21, <ein_22, <ein_23
    .byte <ein_24, <ein_25, <ein_26, <ein_27, <ein_28, <ein_29, <ein_30, <ein_31
    .byte <ein_32, <ein_33, <ein_34, <ein_35, <ein_36, <ein_37, <ein_38, <ein_39
    .byte <ein_40, <ein_41, <ein_42, <ein_43, <ein_44, <ein_45, <ein_46, <ein_47
    .byte <ein_48, <ein_49, <ein_50, <ein_51, <ein_52, <ein_53, <ein_54, <ein_55
    .byte <ein_56, <ein_57, <ein_58, <ein_59, <ein_60, <ein_61, <ein_62, <ein_63
    .byte <ein_64, <ein_65, <ein_66, <ein_67, <ein_68, <ein_69, <ein_70, <ein_71
    .byte <ein_72, <ein_73, <ein_74, <ein_75, <ein_76, <ein_77, <ein_78, <ein_79
    .byte <ein_80, <ein_81, <ein_82, <ein_83, <ein_84, <ein_85, <ein_86, <ein_87
    .byte <ein_88, <ein_89, <ein_90, <ein_91, <ein_92, <ein_93, <ein_94, <ein_95
    .byte <ein_96, <ein_97, <ein_98, <ein_99, <ein_100, <ein_101, <ein_102, <ein_103
    .byte <ein_104, <ein_105, <ein_106, <ein_107, <ein_108, <ein_109, <ein_110, <ein_111
    .byte <ein_112, <ein_113, <ein_114, <ein_115, <ein_116, <ein_117, <ein_118, <ein_119
    .byte <ein_120, <ein_121, <ein_122, <ein_123, <ein_124, <ein_125, <ein_126, <ein_127
    .byte <ein_128, <ein_129, <ein_130, <ein_131, <ein_132, <ein_133, <ein_134, <ein_135
    .byte <ein_136, <ein_137, <ein_138, <ein_139, <ein_140, <ein_141, <ein_142, <ein_143
    .byte <ein_144, <ein_145, <ein_146, <ein_147, <ein_148, <ein_149, <ein_150, <ein_151
    .byte <ein_152, <ein_153, <ein_154, <ein_155, <ein_156, <ein_157, <ein_158, <ein_159
    .byte <ein_160, <ein_161, <ein_162, <ein_163, <ein_164, <ein_165, <ein_166, <ein_167
    .byte <ein_168, <ein_169, <ein_170, <ein_171, <ein_172, <ein_173, <ein_174, <ein_175
    .byte <ein_176, <ein_177, <ein_178, <ein_179, <ein_180, <ein_181, <ein_182, <ein_183
    .byte <ein_184, <ein_185, <ein_186, <ein_187, <ein_188, <ein_189, <ein_190, <ein_191
    .byte <ein_192, <ein_193, <ein_194, <ein_195, <ein_196, <ein_197, <ein_198, <ein_199
    .byte <ein_200, <ein_201, <ein_202, <ein_203, <ein_204, <ein_205, <ein_206, <ein_207
    .byte <ein_208, <ein_209, <ein_210, <ein_211, <ein_212, <ein_213, <ein_214, <ein_215
    .byte <ein_216, <ein_217, <ein_218, <ein_219, <ein_220, <ein_221, <ein_222, <ein_223
    .byte <ein_224, <ein_225, <ein_226, <ein_227, <ein_228, <ein_229, <ein_230, <ein_231
    .byte <ein_232, <ein_233, <ein_234, <ein_235, <ein_236, <ein_237, <ein_238, <ein_239
    .byte <ein_240, <ein_241, <ein_242, <ein_243, <ein_244, <ein_245, <ein_246, <ein_247
    .byte <ein_248, <ein_249, <ein_250, <ein_251, <ein_252, <ein_253, <ein_254
.assert "expected_item_name_p0_lo covers Page 0", * - expected_item_name_p0_lo, ITEM_PAGE_SIZE
expected_item_name_p0_hi:
    .byte >ein_0, >ein_1, >ein_2, >ein_3, >ein_4, >ein_5, >ein_6, >ein_7
    .byte >ein_8, >ein_9, >ein_10, >ein_11, >ein_12, >ein_13, >ein_14, >ein_15
    .byte >ein_16, >ein_17, >ein_18, >ein_19, >ein_20, >ein_21, >ein_22, >ein_23
    .byte >ein_24, >ein_25, >ein_26, >ein_27, >ein_28, >ein_29, >ein_30, >ein_31
    .byte >ein_32, >ein_33, >ein_34, >ein_35, >ein_36, >ein_37, >ein_38, >ein_39
    .byte >ein_40, >ein_41, >ein_42, >ein_43, >ein_44, >ein_45, >ein_46, >ein_47
    .byte >ein_48, >ein_49, >ein_50, >ein_51, >ein_52, >ein_53, >ein_54, >ein_55
    .byte >ein_56, >ein_57, >ein_58, >ein_59, >ein_60, >ein_61, >ein_62, >ein_63
    .byte >ein_64, >ein_65, >ein_66, >ein_67, >ein_68, >ein_69, >ein_70, >ein_71
    .byte >ein_72, >ein_73, >ein_74, >ein_75, >ein_76, >ein_77, >ein_78, >ein_79
    .byte >ein_80, >ein_81, >ein_82, >ein_83, >ein_84, >ein_85, >ein_86, >ein_87
    .byte >ein_88, >ein_89, >ein_90, >ein_91, >ein_92, >ein_93, >ein_94, >ein_95
    .byte >ein_96, >ein_97, >ein_98, >ein_99, >ein_100, >ein_101, >ein_102, >ein_103
    .byte >ein_104, >ein_105, >ein_106, >ein_107, >ein_108, >ein_109, >ein_110, >ein_111
    .byte >ein_112, >ein_113, >ein_114, >ein_115, >ein_116, >ein_117, >ein_118, >ein_119
    .byte >ein_120, >ein_121, >ein_122, >ein_123, >ein_124, >ein_125, >ein_126, >ein_127
    .byte >ein_128, >ein_129, >ein_130, >ein_131, >ein_132, >ein_133, >ein_134, >ein_135
    .byte >ein_136, >ein_137, >ein_138, >ein_139, >ein_140, >ein_141, >ein_142, >ein_143
    .byte >ein_144, >ein_145, >ein_146, >ein_147, >ein_148, >ein_149, >ein_150, >ein_151
    .byte >ein_152, >ein_153, >ein_154, >ein_155, >ein_156, >ein_157, >ein_158, >ein_159
    .byte >ein_160, >ein_161, >ein_162, >ein_163, >ein_164, >ein_165, >ein_166, >ein_167
    .byte >ein_168, >ein_169, >ein_170, >ein_171, >ein_172, >ein_173, >ein_174, >ein_175
    .byte >ein_176, >ein_177, >ein_178, >ein_179, >ein_180, >ein_181, >ein_182, >ein_183
    .byte >ein_184, >ein_185, >ein_186, >ein_187, >ein_188, >ein_189, >ein_190, >ein_191
    .byte >ein_192, >ein_193, >ein_194, >ein_195, >ein_196, >ein_197, >ein_198, >ein_199
    .byte >ein_200, >ein_201, >ein_202, >ein_203, >ein_204, >ein_205, >ein_206, >ein_207
    .byte >ein_208, >ein_209, >ein_210, >ein_211, >ein_212, >ein_213, >ein_214, >ein_215
    .byte >ein_216, >ein_217, >ein_218, >ein_219, >ein_220, >ein_221, >ein_222, >ein_223
    .byte >ein_224, >ein_225, >ein_226, >ein_227, >ein_228, >ein_229, >ein_230, >ein_231
    .byte >ein_232, >ein_233, >ein_234, >ein_235, >ein_236, >ein_237, >ein_238, >ein_239
    .byte >ein_240, >ein_241, >ein_242, >ein_243, >ein_244, >ein_245, >ein_246, >ein_247
    .byte >ein_248, >ein_249, >ein_250, >ein_251, >ein_252, >ein_253, >ein_254
.assert "expected_item_name_p0_hi covers Page 0", * - expected_item_name_p0_hi, ITEM_PAGE_SIZE

expected_item_name_p1_lo:
    .byte <ein_255, <ein_256, <ein_257, <ein_258, <ein_259, <ein_260, <ein_261, <ein_262
    .byte <ein_263, <ein_264, <ein_265, <ein_266, <ein_267, <ein_268, <ein_269, <ein_270
    .byte <ein_271, <ein_272, <ein_273, <ein_274, <ein_275, <ein_276, <ein_277, <ein_278
    .byte <ein_279, <ein_280, <ein_281, <ein_282, <ein_283, <ein_284, <ein_285, <ein_286
    .byte <ein_287, <ein_288, <ein_289, <ein_290, <ein_291, <ein_292, <ein_293, <ein_294
    .byte <ein_295, <ein_296, <ein_297, <ein_298, <ein_299, <ein_300, <ein_301, <ein_302
    .byte <ein_303, <ein_304, <ein_305, <ein_306, <ein_307, <ein_308, <ein_309, <ein_310
    .byte <ein_311, <ein_312, <ein_313, <ein_314, <ein_315, <ein_316, <ein_317, <ein_318
    .byte <ein_319, <ein_320, <ein_321, <ein_322, <ein_323, <ein_324, <ein_325, <ein_326
    .byte <ein_327, <ein_328, <ein_329, <ein_330, <ein_331, <ein_332, <ein_333, <ein_334
    .byte <ein_335, <ein_336, <ein_337, <ein_338, <ein_339, <ein_340, <ein_341, <ein_342
    .byte <ein_343, <ein_344, <ein_345, <ein_346, <ein_347, <ein_348, <ein_349, <ein_350
    .byte <ein_351, <ein_352, <ein_353, <ein_354, <ein_355, <ein_356, <ein_357, <ein_358
    .byte <ein_359, <ein_360
.assert "expected_item_name_p1_lo covers Page 1", * - expected_item_name_p1_lo, ITEM_TYPE_COUNT - ITEM_PAGE_SIZE
expected_item_name_p1_hi:
    .byte >ein_255, >ein_256, >ein_257, >ein_258, >ein_259, >ein_260, >ein_261, >ein_262
    .byte >ein_263, >ein_264, >ein_265, >ein_266, >ein_267, >ein_268, >ein_269, >ein_270
    .byte >ein_271, >ein_272, >ein_273, >ein_274, >ein_275, >ein_276, >ein_277, >ein_278
    .byte >ein_279, >ein_280, >ein_281, >ein_282, >ein_283, >ein_284, >ein_285, >ein_286
    .byte >ein_287, >ein_288, >ein_289, >ein_290, >ein_291, >ein_292, >ein_293, >ein_294
    .byte >ein_295, >ein_296, >ein_297, >ein_298, >ein_299, >ein_300, >ein_301, >ein_302
    .byte >ein_303, >ein_304, >ein_305, >ein_306, >ein_307, >ein_308, >ein_309, >ein_310
    .byte >ein_311, >ein_312, >ein_313, >ein_314, >ein_315, >ein_316, >ein_317, >ein_318
    .byte >ein_319, >ein_320, >ein_321, >ein_322, >ein_323, >ein_324, >ein_325, >ein_326
    .byte >ein_327, >ein_328, >ein_329, >ein_330, >ein_331, >ein_332, >ein_333, >ein_334
    .byte >ein_335, >ein_336, >ein_337, >ein_338, >ein_339, >ein_340, >ein_341, >ein_342
    .byte >ein_343, >ein_344, >ein_345, >ein_346, >ein_347, >ein_348, >ein_349, >ein_350
    .byte >ein_351, >ein_352, >ein_353, >ein_354, >ein_355, >ein_356, >ein_357, >ein_358
    .byte >ein_359, >ein_360
.assert "expected_item_name_p1_hi covers Page 1", * - expected_item_name_p1_hi, ITEM_TYPE_COUNT - ITEM_PAGE_SIZE

expected_item_cat_p0:
    .byte ICAT_GOLD, ICAT_GOLD, ICAT_GOLD, ICAT_GOLD
    .byte ICAT_GOLD, ICAT_GOLD, ICAT_GOLD, ICAT_GOLD
    .byte ICAT_GOLD, ICAT_GOLD, ICAT_GOLD, ICAT_GOLD
    .byte ICAT_GOLD, ICAT_GOLD, ICAT_GOLD, ICAT_GOLD
    .byte ICAT_GOLD, ICAT_GOLD, ICAT_GOLD, ICAT_GOLD
    .byte ICAT_FOOD, ICAT_FOOD, ICAT_FOOD, ICAT_FOOD
    .byte ICAT_FOOD, ICAT_FOOD, ICAT_FOOD, ICAT_FOOD
    .byte ICAT_FOOD, ICAT_FOOD, ICAT_FOOD, ICAT_FOOD
    .byte ICAT_FOOD, ICAT_FOOD, ICAT_FOOD, ICAT_FOOD
    .byte ICAT_FOOD, ICAT_FOOD, ICAT_FOOD, ICAT_FOOD
    .byte ICAT_FOOD, ICAT_FOOD, ICAT_FOOD, ICAT_FOOD
    .byte ICAT_FOOD, ICAT_FOOD, ICAT_FOOD, ICAT_FOOD
    .byte ICAT_FOOD, ICAT_FOOD, ICAT_POTION, ICAT_POTION
    .byte ICAT_POTION, ICAT_POTION, ICAT_POTION, ICAT_POTION
    .byte ICAT_POTION, ICAT_POTION, ICAT_POTION, ICAT_POTION
    .byte ICAT_POTION, ICAT_POTION, ICAT_POTION, ICAT_POTION
    .byte ICAT_POTION, ICAT_POTION, ICAT_POTION, ICAT_POTION
    .byte ICAT_POTION, ICAT_POTION, ICAT_POTION, ICAT_POTION
    .byte ICAT_POTION, ICAT_POTION, ICAT_POTION, ICAT_POTION
    .byte ICAT_POTION, ICAT_POTION, ICAT_POTION, ICAT_POTION
    .byte ICAT_POTION, ICAT_POTION, ICAT_POTION, ICAT_POTION
    .byte ICAT_POTION, ICAT_POTION, ICAT_POTION, ICAT_POTION
    .byte ICAT_POTION, ICAT_POTION, ICAT_POTION, ICAT_POTION
    .byte ICAT_POTION, ICAT_POTION, ICAT_POTION, ICAT_SCROLL
    .byte ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL
    .byte ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL
    .byte ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL
    .byte ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL
    .byte ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL
    .byte ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL
    .byte ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL
    .byte ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL
    .byte ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL
    .byte ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL, ICAT_SCROLL
    .byte ICAT_SCROLL, ICAT_WAND, ICAT_WAND, ICAT_WAND
    .byte ICAT_WAND, ICAT_WAND, ICAT_WAND, ICAT_WAND
    .byte ICAT_WAND, ICAT_WAND, ICAT_WAND, ICAT_WAND
    .byte ICAT_WAND, ICAT_WAND, ICAT_WAND, ICAT_WAND
    .byte ICAT_WAND, ICAT_WAND, ICAT_WAND, ICAT_WAND
    .byte ICAT_WAND, ICAT_WAND, ICAT_WAND, ICAT_WAND
    .byte ICAT_WAND, ICAT_STAFF, ICAT_STAFF, ICAT_STAFF
    .byte ICAT_STAFF, ICAT_STAFF, ICAT_STAFF, ICAT_STAFF
    .byte ICAT_STAFF, ICAT_STAFF, ICAT_STAFF, ICAT_STAFF
    .byte ICAT_STAFF, ICAT_STAFF, ICAT_STAFF, ICAT_STAFF
    .byte ICAT_STAFF, ICAT_STAFF, ICAT_STAFF, ICAT_STAFF
    .byte ICAT_STAFF, ICAT_STAFF, ICAT_STAFF, ICAT_STAFF
    .byte ICAT_STAFF, ICAT_STAFF, ICAT_BOOK, ICAT_BOOK
    .byte ICAT_BOOK, ICAT_BOOK, ICAT_BOOK, ICAT_BOOK
    .byte ICAT_BOOK, ICAT_BOOK, ICAT_LIGHT, ICAT_LIGHT
    .byte ICAT_LIGHT, ICAT_SPIKE, ICAT_DIGGING, ICAT_DIGGING
    .byte ICAT_DIGGING, ICAT_DIGGING, ICAT_DIGGING, ICAT_DIGGING
    .byte ICAT_CHEST, ICAT_CHEST, ICAT_CHEST, ICAT_CHEST
    .byte ICAT_CHEST, ICAT_CHEST, ICAT_CHEST, ICAT_CLOAK
    .byte ICAT_ARMOR, ICAT_ARMOR, ICAT_ARMOR, ICAT_ARMOR
    .byte ICAT_ARMOR, ICAT_ARMOR, ICAT_ARMOR, ICAT_ARMOR
    .byte ICAT_ARMOR, ICAT_ARMOR, ICAT_ARMOR, ICAT_ARMOR
    .byte ICAT_ARMOR, ICAT_ARMOR, ICAT_ARMOR, ICAT_ARMOR
    .byte ICAT_ARMOR, ICAT_ARMOR, ICAT_ARMOR, ICAT_ARMOR
    .byte ICAT_ARMOR, ICAT_ARMOR, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_HELM, ICAT_HELM, ICAT_HELM, ICAT_HELM
    .byte ICAT_HELM, ICAT_HELM, ICAT_HELM, ICAT_HELM
    .byte ICAT_BOOTS, ICAT_BOOTS, ICAT_BOOTS
.assert "expected_item_cat_p0 covers Page 0", * - expected_item_cat_p0, ITEM_PAGE_SIZE
expected_item_cat_p1:
    .byte ICAT_GLOVES, ICAT_GLOVES, ICAT_SHIELD, ICAT_SHIELD
    .byte ICAT_SHIELD, ICAT_SHIELD, ICAT_SHIELD, ICAT_SHIELD
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON, ICAT_WEAPON
    .byte ICAT_WEAPON, ICAT_WEAPON, ICAT_RING, ICAT_RING
    .byte ICAT_RING, ICAT_RING, ICAT_RING, ICAT_RING
    .byte ICAT_RING, ICAT_RING, ICAT_RING, ICAT_RING
    .byte ICAT_RING, ICAT_RING, ICAT_RING, ICAT_RING
    .byte ICAT_RING, ICAT_RING, ICAT_RING, ICAT_RING
    .byte ICAT_RING, ICAT_RING, ICAT_RING, ICAT_RING
    .byte ICAT_RING, ICAT_RING, ICAT_RING, ICAT_RING
    .byte ICAT_RING, ICAT_RING, ICAT_RING, ICAT_RING
    .byte ICAT_RING, ICAT_AMULET, ICAT_AMULET, ICAT_AMULET
    .byte ICAT_AMULET, ICAT_AMULET, ICAT_AMULET, ICAT_AMULET
    .byte ICAT_AMULET, ICAT_AMULET, ICAT_AMULET, ICAT_JUNK
    .byte ICAT_JUNK, ICAT_JUNK, ICAT_JUNK, ICAT_JUNK
    .byte ICAT_JUNK, ICAT_JUNK, ICAT_JUNK, ICAT_JUNK
    .byte ICAT_JUNK, ICAT_JUNK
.assert "expected_item_cat_p1 covers Page 1", * - expected_item_cat_p1, ITEM_TYPE_COUNT - ITEM_PAGE_SIZE

expected_item_ac_p0:
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 1, 2, 4, 5, 6, 7, 6, 6, 8, 11, 1, 13, 14
    .byte 14, 15, 16, 18, 19, 20, 22, 23, 25, 28, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 1, 2, 3, 5, 6, 0, 0, 0, 1, 2, 3
.assert "expected_item_ac_p0 covers Page 0", * - expected_item_ac_p0, ITEM_PAGE_SIZE
expected_item_ac_p1:
    .byte 1, 2, 2, 3, 4, 3, 4, 5, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 5, 5, 5, 0, 0, 0, 0, 1, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
.assert "expected_item_ac_p1 covers Page 1", * - expected_item_ac_p1, ITEM_TYPE_COUNT - ITEM_PAGE_SIZE

expected_item_color_p0:
    .byte 7, 7, 8, 8, 8, 15, 15, 15, 2, 2, 7, 7, 7, 3, 6, 7
    .byte 10, 1, 5, 14, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9
    .byte 9, 9, 9, 9, 13, 13, 13, 13, 13, 9, 5, 7, 7, 9, 9, 9
    .byte 8, 8, 1, 8, 8, 1, 2, 3, 1, 6, 5, 1, 2, 15, 1, 1
    .byte 1, 1, 1, 7, 5, 12, 4, 5, 13, 5, 13, 9, 1, 1, 12, 12
    .byte 15, 4, 14, 13, 10, 4, 6, 10, 10, 3, 5, 4, 5, 6, 8, 7
    .byte 3, 1, 15, 3, 1, 13, 3, 3, 3, 13, 13, 8, 7, 10, 7, 1
    .byte 1, 15, 15, 10, 9, 10, 7, 3, 13, 13, 10, 8, 7, 10, 1, 15
    .byte 9, 7, 3, 13, 8, 10, 1, 15, 10, 7, 3, 6, 10, 9, 12, 15
    .byte 12, 12, 9, 1, 4, 15, 9, 12, 15, 3, 15, 3, 3, 10, 5, 13
    .byte 15, 7, 7, 9, 9, 2, 3, 9, 9, 9, 10, 5, 9, 15, 11, 1
    .byte 9, 7, 13, 9, 3, 9, 9, 1, 9, 9, 4, 4, 6, 10, 7, 7
    .byte 3, 1, 8, 7, 8, 1, 15, 9, 11, 1, 3, 1, 9, 9, 15, 15
    .byte 1, 1, 9, 15, 15, 9, 9, 9, 9, 9, 9, 9, 9, 12, 12, 12
    .byte 12, 15, 15, 15, 15, 15, 1, 1, 15, 1, 9, 9, 9, 15, 15, 9
    .byte 9, 15, 12, 11, 9, 9, 12, 12, 15, 1, 7, 13, 9, 9, 9
.assert "expected_item_color_p0 covers Page 0", * - expected_item_color_p0, ITEM_PAGE_SIZE
expected_item_color_p1:
    .byte 9, 15, 15, 9, 15, 15, 15, 15, 15, 15, 15, 15, 12, 15, 1, 15
    .byte 15, 1, 15, 1, 1, 1, 1, 15, 15, 1, 1, 15, 1, 15, 1, 12
    .byte 15, 15, 15, 15, 15, 9, 15, 15, 1, 15, 15, 15, 15, 15, 15, 15
    .byte 15, 15, 15, 15, 15, 15, 10, 3, 6, 13, 7, 2, 3, 8, 10, 3
    .byte 10, 3, 3, 3, 10, 13, 3, 1, 3, 5, 3, 7, 3, 13, 3, 2
    .byte 3, 3, 3, 13, 10, 7, 7, 7, 7, 7, 7, 7, 13, 13, 2, 1
    .byte 1, 13, 8, 1, 1, 1, 1, 1, 1, 9
.assert "expected_item_color_p1 covers Page 1", * - expected_item_color_p1, ITEM_TYPE_COUNT - ITEM_PAGE_SIZE

expected_item_glyph_p0:
    .byte $24, $24, $24, $24, $24, $24, $24, $24, $24, $24, $24, $24, $24, $24, $24, $24
    .byte $24, $24, $24, $24, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c
    .byte $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c
    .byte $2c, $2c, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21
    .byte $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21
    .byte $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $3f
    .byte $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f
    .byte $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f
    .byte $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $2d, $2d, $2d, $2d, $2d, $2d, $2d
    .byte $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d
    .byte $2d, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
    .byte $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $3f, $3f, $3f, $3f, $3f, $3f
    .byte $3f, $3f, $2a, $2a, $21, $5c, $5c, $5c, $5c, $5c, $5c, $5c, $26, $26, $26, $26
    .byte $26, $26, $26, $28, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b
    .byte $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $1c, $1c, $1c, $1c, $1c, $1c
    .byte $1b, $1b, $1b, $1b, $5d, $5d, $5d, $5d, $5d, $5d, $5d, $5d, $5d, $5d, $5d
.assert "expected_item_glyph_p0 covers Page 0", * - expected_item_glyph_p0, ITEM_PAGE_SIZE
expected_item_glyph_p1:
    .byte $5d, $5d, $29, $29, $29, $29, $29, $29, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
    .byte $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
    .byte $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
    .byte $2f, $2f, $2f, $2f, $2f, $2f, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d
    .byte $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d
    .byte $3d, $3d, $3d, $3d, $3d, $22, $22, $22, $22, $22, $22, $22, $22, $22, $22, $5c
    .byte $5c, $5c, $5c, $5c, $5c, $5c, $5c, $5c, $5c, $5c
.assert "expected_item_glyph_p1 covers Page 1", * - expected_item_glyph_p1, ITEM_TYPE_COUNT - ITEM_PAGE_SIZE

ein_0: .text "Gold (small)" ; .byte 0
ein_1: .text "Gold (large)" ; .byte 0
ein_2: .text "Copper" ; .byte 0
ein_3: .text "Copper" ; .byte 0
ein_4: .text "Copper" ; .byte 0
ein_5: .text "Silver" ; .byte 0
ein_6: .text "Silver" ; .byte 0
ein_7: .text "Silver" ; .byte 0
ein_8: .text "Garnets" ; .byte 0
ein_9: .text "Garnets" ; .byte 0
ein_10: .text "Gold" ; .byte 0
ein_11: .text "Gold" ; .byte 0
ein_12: .text "Gold" ; .byte 0
ein_13: .text "Opals" ; .byte 0
ein_14: .text "Sapphires" ; .byte 0
ein_15: .text "Gold" ; .byte 0
ein_16: .text "Rubies" ; .byte 0
ein_17: .text "Diamonds" ; .byte 0
ein_18: .text "Emeralds" ; .byte 0
ein_19: .text "Mithril" ; .byte 0
ein_20: .text "Mushroom of Poison" ; .byte 0
ein_21: .text "Mushroom of Blindness" ; .byte 0
ein_22: .text "Mushroom of Paranoia" ; .byte 0
ein_23: .text "Mushroom of Confusion" ; .byte 0
ein_24: .text "Mushroom of Hallucination" ; .byte 0
ein_25: .text "Mushroom of Cure Poison" ; .byte 0
ein_26: .text "Mushroom of Cure Blindness" ; .byte 0
ein_27: .text "Mushroom of Cure Paranoia" ; .byte 0
ein_28: .text "Mushroom of Cure Confusion" ; .byte 0
ein_29: .text "Mushroom of Weakness" ; .byte 0
ein_30: .text "Mushroom of Unhealth" ; .byte 0
ein_31: .text "Mushroom of Restore Constitution" ; .byte 0
ein_32: .text "Mushroom of First-Aid" ; .byte 0
ein_33: .text "Mushroom of Minor Cures" ; .byte 0
ein_34: .text "Mushroom of Light Cures" ; .byte 0
ein_35: .text "Mushroom of Restoring" ; .byte 0
ein_36: .text "Hairy Mold of Poison" ; .byte 0
ein_37: .text "Hairy Mold of Hallucinations" ; .byte 0
ein_38: .text "Hairy Mold of Cure Poison" ; .byte 0
ein_39: .text "Hairy Mold of Unhealth" ; .byte 0
ein_40: .text "Hairy Mold of Cure Serious Wounds" ; .byte 0
ein_41: .text "Ration of Food" ; .byte 0
ein_42: .text "Slime Mold" ; .byte 0
ein_43: .text "Piece of Elvish Waybread" ; .byte 0
ein_44: .text "Piece of Elvish Waybread" ; .byte 0
ein_45: .text "Pint of Fine Grade Mush" ; .byte 0
ein_46: .text "Hard Biscuit" ; .byte 0
ein_47: .text "Strip of Beef Jerky" ; .byte 0
ein_48: .text "Pint of Fine Ale" ; .byte 0
ein_49: .text "Pint of Fine Wine" ; .byte 0
ein_50: .text "Potion of Gain Strength" ; .byte 0
ein_51: .text "Potion of Weakness" ; .byte 0
ein_52: .text "Potion of Restore Strength" ; .byte 0
ein_53: .text "Potion of Gain Intelligence" ; .byte 0
ein_54: .text "Potion of Lose Intelligence" ; .byte 0
ein_55: .text "Potion of Restore Intelligence" ; .byte 0
ein_56: .text "Potion of Gain Wisdom" ; .byte 0
ein_57: .text "Potion of Lose Wisdom" ; .byte 0
ein_58: .text "Potion of Restore Wisdom" ; .byte 0
ein_59: .text "Potion of Charisma" ; .byte 0
ein_60: .text "Potion of Ugliness" ; .byte 0
ein_61: .text "Potion of Restore Charisma" ; .byte 0
ein_62: .text "Potion of Cure Light Wounds" ; .byte 0
ein_63: .text "Potion of Cure Serious Wounds" ; .byte 0
ein_64: .text "Potion of Cure Critical Wounds" ; .byte 0
ein_65: .text "Potion of Healing" ; .byte 0
ein_66: .text "Potion of Gain Constitution" ; .byte 0
ein_67: .text "Potion of Gain Experience" ; .byte 0
ein_68: .text "Potion of Sleep" ; .byte 0
ein_69: .text "Potion of Blindness" ; .byte 0
ein_70: .text "Potion of Confusion" ; .byte 0
ein_71: .text "Potion of Poison" ; .byte 0
ein_72: .text "Potion of Speed" ; .byte 0
ein_73: .text "Potion of Slowness" ; .byte 0
ein_74: .text "Icky Green Potion of Slime Mold Juice" ; .byte 0
ein_75: .text "Light Brown Potion of Apple Juice" ; .byte 0
ein_76: .text "Clear Potion of Water" ; .byte 0
ein_77: .text "Potion of Gain Dexterity" ; .byte 0
ein_78: .text "Potion of Restore Dexterity" ; .byte 0
ein_79: .text "Potion of Restore Constitution" ; .byte 0
ein_80: .text "Potion of Learning" ; .byte 0
ein_81: .text "Potion of Lose Memories" ; .byte 0
ein_82: .text "Potion of Salt Water" ; .byte 0
ein_83: .text "Potion of Invulnerability" ; .byte 0
ein_84: .text "Potion of Heroism" ; .byte 0
ein_85: .text "Potion of Super Heroism" ; .byte 0
ein_86: .text "Potion of Boldness" ; .byte 0
ein_87: .text "Potion of Restore Life Levels" ; .byte 0
ein_88: .text "Potion of Resist Heat" ; .byte 0
ein_89: .text "Potion of Resist Cold" ; .byte 0
ein_90: .text "Potion of Detect Invisible" ; .byte 0
ein_91: .text "Potion of Slow Poison" ; .byte 0
ein_92: .text "Potion of Neutralize Poison" ; .byte 0
ein_93: .text "Potion of Restore Mana" ; .byte 0
ein_94: .text "Potion of Infravision" ; .byte 0
ein_95: .text "Scroll of Enchant Weapon To-Hit" ; .byte 0
ein_96: .text "Scroll of Enchant Weapon To-Dam" ; .byte 0
ein_97: .text "Scroll of Enchant Armor" ; .byte 0
ein_98: .text "Scroll of Identify" ; .byte 0
ein_99: .text "Scroll of Remove Curse" ; .byte 0
ein_100: .text "Scroll of Light" ; .byte 0
ein_101: .text "Scroll of Summon Monster" ; .byte 0
ein_102: .text "Scroll of Phase Door" ; .byte 0
ein_103: .text "Scroll of Teleportation" ; .byte 0
ein_104: .text "Scroll of Teleport Level" ; .byte 0
ein_105: .text "Scroll of Monster Confusion" ; .byte 0
ein_106: .text "Scroll of Magic Mapping" ; .byte 0
ein_107: .text "Scroll of Sleep Monster" ; .byte 0
ein_108: .text "Scroll of Rune of Protection" ; .byte 0
ein_109: .text "Scroll of Treasure Detection" ; .byte 0
ein_110: .text "Scroll of Object Detection" ; .byte 0
ein_111: .text "Scroll of Trap Detection" ; .byte 0
ein_112: .text "Scroll of Trap Detection" ; .byte 0
ein_113: .text "Scroll of Door/Stair Location" ; .byte 0
ein_114: .text "Scroll of Door/Stair Location" ; .byte 0
ein_115: .text "Scroll of Mass Genocide" ; .byte 0
ein_116: .text "Scroll of Detect Invisible" ; .byte 0
ein_117: .text "Scroll of Aggravate" ; .byte 0
ein_118: .text "Scroll of Trap Creation" ; .byte 0
ein_119: .text "Scroll of Trap/Door Destruction" ; .byte 0
ein_120: .text "Scroll of Door Creation" ; .byte 0
ein_121: .text "Scroll of Recharging" ; .byte 0
ein_122: .text "Scroll of Genocide" ; .byte 0
ein_123: .text "Scroll of Darkness" ; .byte 0
ein_124: .text "Scroll of Protect from Evil" ; .byte 0
ein_125: .text "Scroll of Create Food" ; .byte 0
ein_126: .text "Scroll of Dispel Undead" ; .byte 0
ein_127: .text "Scroll of *Enchant Weapon*" ; .byte 0
ein_128: .text "Scroll of Curse Weapon" ; .byte 0
ein_129: .text "Scroll of *Enchant Armor*" ; .byte 0
ein_130: .text "Scroll of Curse Armor" ; .byte 0
ein_131: .text "Scroll of Summon Undead" ; .byte 0
ein_132: .text "Scroll of Blessing" ; .byte 0
ein_133: .text "Scroll of Holy Chant" ; .byte 0
ein_134: .text "Scroll of Holy Prayer" ; .byte 0
ein_135: .text "Scroll of Word of Recall" ; .byte 0
ein_136: .text "Scroll of *Destruction*" ; .byte 0
ein_137: .text "Wand of Light" ; .byte 0
ein_138: .text "Wand of Lightning" ; .byte 0
ein_139: .text "Wand of Frost" ; .byte 0
ein_140: .text "Wand of Fire Bolts" ; .byte 0
ein_141: .text "Wand of Stone-to-Mud" ; .byte 0
ein_142: .text "Wand of Polymorph" ; .byte 0
ein_143: .text "Wand of Heal Monster" ; .byte 0
ein_144: .text "Wand of Haste Monster" ; .byte 0
ein_145: .text "Wand of Slow Monster" ; .byte 0
ein_146: .text "Wand of Confuse Monster" ; .byte 0
ein_147: .text "Wand of Sleep Monster" ; .byte 0
ein_148: .text "Wand of Drain Life" ; .byte 0
ein_149: .text "Wand of Trap/Door Destruction" ; .byte 0
ein_150: .text "Wand of Magic Missile" ; .byte 0
ein_151: .text "Wand of Wall Building" ; .byte 0
ein_152: .text "Wand of Clone Monster" ; .byte 0
ein_153: .text "Wand of Teleport Away" ; .byte 0
ein_154: .text "Wand of Disarming" ; .byte 0
ein_155: .text "Wand of Lightning Balls" ; .byte 0
ein_156: .text "Wand of Cold Balls" ; .byte 0
ein_157: .text "Wand of Fire Balls" ; .byte 0
ein_158: .text "Wand of Stinking Cloud" ; .byte 0
ein_159: .text "Wand of Acid Balls" ; .byte 0
ein_160: .text "Wand of Wonder" ; .byte 0
ein_161: .text "Staff of Light" ; .byte 0
ein_162: .text "Staff of Door/Stair Location" ; .byte 0
ein_163: .text "Staff of Trap Location" ; .byte 0
ein_164: .text "Staff of Treasure Location" ; .byte 0
ein_165: .text "Staff of Object Location" ; .byte 0
ein_166: .text "Staff of Teleportation" ; .byte 0
ein_167: .text "Staff of Earthquakes" ; .byte 0
ein_168: .text "Staff of Summoning" ; .byte 0
ein_169: .text "Staff of Summoning" ; .byte 0
ein_170: .text "Staff of Destruction" ; .byte 0
ein_171: .text "Staff of Starlite" ; .byte 0
ein_172: .text "Staff of Haste Monsters" ; .byte 0
ein_173: .text "Staff of Slow Monsters" ; .byte 0
ein_174: .text "Staff of Sleep Monsters" ; .byte 0
ein_175: .text "Staff of Cure Light Wounds" ; .byte 0
ein_176: .text "Staff of Detect Invisible" ; .byte 0
ein_177: .text "Staff of Speed" ; .byte 0
ein_178: .text "Staff of Slowness" ; .byte 0
ein_179: .text "Staff of Mass Polymorph" ; .byte 0
ein_180: .text "Staff of Remove Curse" ; .byte 0
ein_181: .text "Staff of Detect Evil" ; .byte 0
ein_182: .text "Staff of Curing" ; .byte 0
ein_183: .text "Staff of Dispel Evil" ; .byte 0
ein_184: .text "Staff of Darkness" ; .byte 0
ein_185: .text "Staff of Darkness" ; .byte 0
ein_186: .text "Spellbook Beginners-Magick" ; .byte 0
ein_187: .text "Spellbook Magick I" ; .byte 0
ein_188: .text "Spellbook Magick II" ; .byte 0
ein_189: .text "Spellbook The Mages Guide to Power" ; .byte 0
ein_190: .text "Holy Book of Prayers Beginners Handbook" ; .byte 0
ein_191: .text "Holy Book of Prayers Words of Wisdom" ; .byte 0
ein_192: .text "Holy Book of Prayers Chants and Blessings" ; .byte 0
ein_193: .text "Holy Book of Prayers Exorcism" ; .byte 0
ein_194: .text "Brass Lantern" ; .byte 0
ein_195: .text "Wooden Torch" ; .byte 0
ein_196: .text "Flask of Oil" ; .byte 0
ein_197: .text "Iron Spike" ; .byte 0
ein_198: .text "Pick" ; .byte 0
ein_199: .text "Shovel" ; .byte 0
ein_200: .text "Orcish Pick" ; .byte 0
ein_201: .text "Dwarven Pick" ; .byte 0
ein_202: .text "Gnomish Shovel" ; .byte 0
ein_203: .text "Dwarven Shovel" ; .byte 0
ein_204: .text "Small Wooden Chest" ; .byte 0
ein_205: .text "Large Wooden Chest" ; .byte 0
ein_206: .text "Small Iron Chest" ; .byte 0
ein_207: .text "Large Iron Chest" ; .byte 0
ein_208: .text "Small Steel Chest" ; .byte 0
ein_209: .text "Large Steel Chest" ; .byte 0
ein_210: .text "Ruined Chest" ; .byte 0
ein_211: .text "Cloak" ; .byte 0
ein_212: .text "Robe" ; .byte 0
ein_213: .text "Leather Armor" ; .byte 0
ein_214: .text "Studded Leather Armor" ; .byte 0
ein_215: .text "Hard Leather Armor" ; .byte 0
ein_216: .text "Hard Studded Leather" ; .byte 0
ein_217: .text "Woven Cord Armor" ; .byte 0
ein_218: .text "Soft Leather Ring Mail" ; .byte 0
ein_219: .text "Hard Leather Ring Mail" ; .byte 0
ein_220: .text "Leather Scale Mail" ; .byte 0
ein_221: .text "Filthy Rags" ; .byte 0
ein_222: .text "Scale Mail" ; .byte 0
ein_223: .text "Chain Mail" ; .byte 0
ein_224: .text "Rusty Chain Mail" ; .byte 0
ein_225: .text "Double Chain Mail" ; .byte 0
ein_226: .text "Augmented Chain Mail" ; .byte 0
ein_227: .text "Bar Chain Mail" ; .byte 0
ein_228: .text "Metal Brigandine Armor" ; .byte 0
ein_229: .text "Laminated Armor" ; .byte 0
ein_230: .text "Partial Plate Armor" ; .byte 0
ein_231: .text "Metal Lamellar Armor" ; .byte 0
ein_232: .text "Plate Mail" ; .byte 0
ein_233: .text "Ribbed Plate Armor" ; .byte 0
ein_234: .text "Short Bow" ; .byte 0
ein_235: .text "Long Bow" ; .byte 0
ein_236: .text "Composite Bow" ; .byte 0
ein_237: .text "Light Crossbow" ; .byte 0
ein_238: .text "Heavy Crossbow" ; .byte 0
ein_239: .text "Sling" ; .byte 0
ein_240: .text "Arrow" ; .byte 0
ein_241: .text "Bolt" ; .byte 0
ein_242: .text "Rock" ; .byte 0
ein_243: .text "Iron Shot" ; .byte 0
ein_244: .text "Soft Leather Cap" ; .byte 0
ein_245: .text "Hard Leather Cap" ; .byte 0
ein_246: .text "Metal Cap" ; .byte 0
ein_247: .text "Iron Helm" ; .byte 0
ein_248: .text "Steel Helm" ; .byte 0
ein_249: .text "Silver Crown" ; .byte 0
ein_250: .text "Golden Crown" ; .byte 0
ein_251: .text "Jewel Encrusted Crown" ; .byte 0
ein_252: .text "Leather Boots" ; .byte 0
ein_253: .text "Soft Leather Boots" ; .byte 0
ein_254: .text "Hard Leather Boots" ; .byte 0
ein_255: .text "Leather Gloves" ; .byte 0
ein_256: .text "Gauntlets" ; .byte 0
ein_257: .text "Small Shield" ; .byte 0
ein_258: .text "Medium Leather Shield" ; .byte 0
ein_259: .text "Large Shield" ; .byte 0
ein_260: .text "Small Metal Shield" ; .byte 0
ein_261: .text "Medium Metal Shield" ; .byte 0
ein_262: .text "Large Metal Shield" ; .byte 0
ein_263: .text "Main Gauche" ; .byte 0
ein_264: .text "Dagger (Misericorde)" ; .byte 0
ein_265: .text "Dagger" ; .byte 0
ein_266: .text "Dagger (Bodkin)" ; .byte 0
ein_267: .text "Broken Dagger" ; .byte 0
ein_268: .text "Backsword" ; .byte 0
ein_269: .text "Bastard Sword" ; .byte 0
ein_270: .text "Thrusting Sword (Bilbo)" ; .byte 0
ein_271: .text "Thrusting Sword (Baselard)" ; .byte 0
ein_272: .text "Broad Sword" ; .byte 0
ein_273: .text "Two-Handed Sword" ; .byte 0
ein_274: .text "Cutlass" ; .byte 0
ein_275: .text "Two-Handed Sword (Espadon)" ; .byte 0
ein_276: .text "Executioner's Sword" ; .byte 0
ein_277: .text "Two-Handed Sword (Flamberge)" ; .byte 0
ein_278: .text "Foil" ; .byte 0
ein_279: .text "Katana" ; .byte 0
ein_280: .text "Long Sword" ; .byte 0
ein_281: .text "Two-Handed Sword (No-Dachi)" ; .byte 0
ein_282: .text "Rapier" ; .byte 0
ein_283: .text "Sabre" ; .byte 0
ein_284: .text "Short Sword" ; .byte 0
ein_285: .text "Two-Handed Sword (Zweihander)" ; .byte 0
ein_286: .text "Broken Sword" ; .byte 0
ein_287: .text "Battle Axe (Balestarius)" ; .byte 0
ein_288: .text "Ball and Chain" ; .byte 0
ein_289: .text "Battle Axe" ; .byte 0
ein_290: .text "Broad Axe" ; .byte 0
ein_291: .text "Cat-o'-Nine-Tails" ; .byte 0
ein_292: .text "Wooden Club" ; .byte 0
ein_293: .text "Flail" ; .byte 0
ein_294: .text "Two-Handed Great Flail" ; .byte 0
ein_295: .text "Morningstar" ; .byte 0
ein_296: .text "Mace" ; .byte 0
ein_297: .text "War Hammer" ; .byte 0
ein_298: .text "Mace (Lead-Filled)" ; .byte 0
ein_299: .text "Awl-Pike" ; .byte 0
ein_300: .text "Beaked Axe" ; .byte 0
ein_301: .text "Fauchard" ; .byte 0
ein_302: .text "Glaive" ; .byte 0
ein_303: .text "Halberd" ; .byte 0
ein_304: .text "Lucerne Hammer" ; .byte 0
ein_305: .text "Pike" ; .byte 0
ein_306: .text "Spear" ; .byte 0
ein_307: .text "Lance" ; .byte 0
ein_308: .text "Javelin" ; .byte 0
ein_309: .text "Ring of Strength" ; .byte 0
ein_310: .text "Ring of Gain Dexterity" ; .byte 0
ein_311: .text "Ring of Gain Constitution" ; .byte 0
ein_312: .text "Ring of Gain Intelligence" ; .byte 0
ein_313: .text "Ring of Speed" ; .byte 0
ein_314: .text "Ring of Searching" ; .byte 0
ein_315: .text "Ring of Teleportation" ; .byte 0
ein_316: .text "Ring of Slow Digestion" ; .byte 0
ein_317: .text "Ring of Resist Fire" ; .byte 0
ein_318: .text "Ring of Resist Cold" ; .byte 0
ein_319: .text "Ring of Feather Falling" ; .byte 0
ein_320: .text "Ring of Adornment" ; .byte 0
ein_321: .text "Ring of Adornment" ; .byte 0
ein_322: .text "Ring of Weakness" ; .byte 0
ein_323: .text "Ring of Lordly Protection (Fire)" ; .byte 0
ein_324: .text "Ring of Lordly Protection (Acid)" ; .byte 0
ein_325: .text "Ring of Lordly Protection (Cold)" ; .byte 0
ein_326: .text "Ring of WOE" ; .byte 0
ein_327: .text "Ring of Stupidity" ; .byte 0
ein_328: .text "Ring of Increase Damage" ; .byte 0
ein_329: .text "Ring of Increase To-Hit" ; .byte 0
ein_330: .text "Ring of Protection" ; .byte 0
ein_331: .text "Ring of Aggravate Monster" ; .byte 0
ein_332: .text "Ring of See Invisible" ; .byte 0
ein_333: .text "Ring of Sustain Strength" ; .byte 0
ein_334: .text "Ring of Sustain Intelligence" ; .byte 0
ein_335: .text "Ring of Sustain Wisdom" ; .byte 0
ein_336: .text "Ring of Sustain Constitution" ; .byte 0
ein_337: .text "Ring of Sustain Dexterity" ; .byte 0
ein_338: .text "Ring of Sustain Charisma" ; .byte 0
ein_339: .text "Ring of Slaying" ; .byte 0
ein_340: .text "Amulet of Adornment" ; .byte 0
ein_341: .text "Amulet of Adornment" ; .byte 0
ein_342: .text "Amulet of Wisdom" ; .byte 0
ein_343: .text "Amulet of Charisma" ; .byte 0
ein_344: .text "Amulet of Searching" ; .byte 0
ein_345: .text "Amulet of Teleportation" ; .byte 0
ein_346: .text "Amulet of Slow Digestion" ; .byte 0
ein_347: .text "Amulet of Resist Acid" ; .byte 0
ein_348: .text "Amulet of the Magi" ; .byte 0
ein_349: .text "Amulet of DOOM" ; .byte 0
ein_350: .text "Rat Skeleton" ; .byte 0
ein_351: .text "Giant Centipede Skeleton" ; .byte 0
ein_352: .text "Empty Bottle" ; .byte 0
ein_353: .text "Shards of Pottery" ; .byte 0
ein_354: .text "Human Skeleton" ; .byte 0
ein_355: .text "Dwarf Skeleton" ; .byte 0
ein_356: .text "Elf Skeleton" ; .byte 0
ein_357: .text "Gnome Skeleton" ; .byte 0
ein_358: .text "Broken Set of Teeth" ; .byte 0
ein_359: .text "Large Broken Bone" ; .byte 0
ein_360: .text "Broken Stick" ; .byte 0

assert_col: .byte 0
assert_idx: .byte 0
assert_expected: .byte 0
item_name_test_id: .byte 0

// As core/ui_messages.s (not imported here): hal_screen_put_string with A/Y
// = pointer
screen_put_string_ay:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp hal_screen_put_string

// Seed Set 0 ($2000, $2010) and Set 1 ($3000, LAST_CAT_CELL) scanlines 0..7 with
// non-zero sentinels before c128_load_item_cat_vdc streams into VDC RAM.
test_seed_vdc_font_sentinels:
    ldx #0
!seed_cell:
    cpx #4
    bcs !seed_done+
    lda vdc_font_sentinel_hi,x
    ldy vdc_font_sentinel_lo,x
    stx vdc_sentinel_idx
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg
    ldy #0
!seed_byte:
    tya
    eor #$a5
    jsr vdc_wait
    sta VDC_DATA_REG
    iny
    cpy #8
    bcc !seed_byte-
    ldx vdc_sentinel_idx
    inx
    jmp !seed_cell-
!seed_done:
    rts

test_verify_vdc_cat_boundaries_and_fonts:
    // 1. Verify vdc_item_cat_map_addr exact boundary mapping across both spans.
    ldx #0
!chk_map:
    cpx #8
    bcs !chk_fonts+
    lda vdc_map_off_lo,x
    sta item_cat_off_lo
    lda vdc_map_off_hi,x
    sta item_cat_off_hi
    jsr vdc_item_cat_map_addr
    cmp vdc_map_exp_hi,x
    bne !vdc_verify_fail+
    tya
    cmp vdc_map_exp_lo,x
    bne !vdc_verify_fail+
    inx
    jmp !chk_map-

!chk_fonts:
    // 2. Verify Set 0 and Set 1 glyph scanlines 0..7 were never touched by preload.
    ldx #0
!chk_cell:
    cpx #4
    bcs !chk_last_byte+
    lda vdc_font_sentinel_hi,x
    ldy vdc_font_sentinel_lo,x
    stx vdc_sentinel_idx
    jsr vdc_set_update_addr
    ldy #0
!chk_byte:
    sty assert_idx
    ldx #31
    jsr vdc_read_reg
    ldy assert_idx
    sta assert_expected
    tya
    eor #$a5
    cmp assert_expected
    bne !vdc_verify_fail+
    iny
    cpy #8
    bcc !chk_byte-
    ldx vdc_sentinel_idx
    inx
    jmp !chk_cell-

!chk_last_byte:
    // 3. Verify final byte of ITEM.CAT (ITMCAT_TOTAL_SIZE - 1) round-trips.
    lda #<(ITMCAT_TOTAL_SIZE - 1)
    sta item_cat_off_lo
    lda #>(ITMCAT_TOTAL_SIZE - 1)
    sta item_cat_off_hi
    jsr hal_item_cat_read_byte
    cmp item_cat_data + ITMCAT_TOTAL_SIZE - 1
    bne !vdc_verify_fail+
    sec
    rts

!vdc_verify_fail:
    clc
    rts

.const LAST_CAT_OFF  = ITMCAT_TOTAL_SIZE - 1
.const LAST_CAT_TAIL = LAST_CAT_OFF - VDC_ITEM_CAT_LO_SIZE
.const LAST_CAT_VDC  = VDC_CHARSET_BASE + ((LAST_CAT_TAIL >> 3) << 4) + VDC_ITEM_CAT_CELL_OFFSET + (LAST_CAT_TAIL & 7)
.const LAST_CAT_CELL = LAST_CAT_VDC & $fff0

vdc_sentinel_idx: .byte 0
vdc_font_sentinel_lo: .byte $00, $10, $00, <LAST_CAT_CELL
vdc_font_sentinel_hi: .byte $20, $20, $30, >LAST_CAT_CELL
vdc_map_off_lo: .byte $00, $ff, $00, $07, $08, $7f, $80, <LAST_CAT_OFF
vdc_map_off_hi: .byte $00, $0e, $0f, $0f, $0f, $0f, $0f, >LAST_CAT_OFF
vdc_map_exp_lo: .byte $00, $ff, $08, $0f, $18, $ff, $08, <LAST_CAT_VDC
vdc_map_exp_hi: .byte $11, $1f, $20, $20, $20, $20, $21, >LAST_CAT_VDC
.assert "test_item_desc128 stays below C128 I/O window", * <= $d000, true
