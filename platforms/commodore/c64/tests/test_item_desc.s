// test_item_desc.s — Runtime tests for the real item description formatter
//
// Results at $0400-$040B: $01 = pass, $00 = fail per test (12 tests)

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_finish:
    ldx #11
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0830 "Main"

.encoding "screencode_mixed"

#import "../../../../core/6502/zeropage.s"
#import "../memory.s"
#import "../screen.s"
#import "../../../../core/6502/color.s"
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

#import "../../../../core/6502/rng.s"
#import "../../../../core/6502/numeric_format.s"
#import "../../../../core/6502/item_defs.s"
.const HD_DECODE_BUF_SIZE = 64
hd_decode_buf: .fill HD_DECODE_BUF_SIZE, 0

#import "../../../../core/6502/item_tables.s"
#import "../../../../core/6502/item_identification.s"

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
si_meta_hi: .byte 0
fi_item_id: .byte FI_EMPTY
fi_meta_hi: .byte 0
fi_add_flags: .byte 0
fi_add_ego:   .byte 0

#import "../../../../core/6502/item_desc_banked.s"

test_start:
    jsr screen_clear

    ldx #11
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    // Test 1: identified weapon prints split to-hit/to-dam suffix.
    jsr test_prepare_row0
    lda #ITEM_SLOT_DAGGER                          // Dagger
    sta itemdesc_item_id
    lda #0
    sta itemdesc_qty
    sta itemdesc_p1
    sta itemdesc_to_ac
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
    }
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
    lda #ITEM_SLOT_LEATHER_ARMOR                          // Leather Armor, base AC 4
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
    lda #ITEM_SLOT_DAGGER                          // Dagger
    sta itemdesc_item_id
    lda #0
    sta itemdesc_qty
    sta itemdesc_p1
    sta itemdesc_to_ac
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
    }
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
    lda #ITEM_SLOT_BOLT                         // Bolt
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
    ldx #ITEM_SLOT_SCROLL_OF_IDENTIFY
    jsr id_known_set
    lda #ITEM_SLOT_SCROLL_OF_IDENTIFY                         // Identify
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
    lda #ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_BEGINNERS_HANDBOOK                         // Priest book 1
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
    lda #ITEM_SLOT_MAIN_GAUCHE
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_to_hit
    sta inv_to_dam
    sta inv_to_ac
    sta inv_flags
    .if (ITEM_PAGE_MAIN_GAUCHE != 0) {
        lda #ITEM_PAGE_MAIN_GAUCHE
    }
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
    lda #ITEM_SLOT_STUDDED_LEATHER_ARMOR
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
    lda #ITEM_SLOT_AMULET_OF_WISDOM
    sta itemdesc_item_id
    lda #0
    sta itemdesc_qty
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    .if (ITEM_PAGE_AMULET_OF_WISDOM != 0) {
        lda #ITEM_PAGE_AMULET_OF_WISDOM
    }
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

    // Part A: approved flavour indexes for appended randomized-class rows.
    ldx #0
!t10a_loop:
    stx t10_cursor
    lda t10_wrap_pages,x
    sta item_cur_page
    lda t10_wrap_ids,x
    jsr item_get_unknown_idx_a
    ldx t10_cursor
    cmp t10_wrap_idx,x
    beq !t10a_match+
    jmp !t10_fail+
!t10a_match:
    inx
    cpx #27
    bcc !t10a_loop-
    lda #0
    sta item_cur_page

    // Part B: every randomized-class type resolves inside its pool (or $FF if fixed-flavour)
    // across Page 0 and Page 1.
    lda #0
    sta item_cur_page
    lda #ITEM_PAGE_SIZE
    jsr !t10b_scan_page+
    bcs !t10b_p1+
    jmp !t10_fail+
!t10b_p1:
    lda #ITEM_PAGE_BIT
    sta item_cur_page
    lda #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)
    jsr !t10b_scan_page+
    bcs !t10c_part+
    jmp !t10_fail+

!t10b_scan_page:
    sta t10_page_limit
    ldx #0
!t10b_loop:
    stx t10_cursor
    txa
    jsr item_get_category_a
    cmp #ICAT_POTION
    beq !t10b_potion+
    cmp #ICAT_SCROLL
    beq !t10b_scroll+
    cmp #ICAT_RING
    beq !t10b_ring+
    cmp #ICAT_WAND
    beq !t10b_wand+
    cmp #ICAT_STAFF
    beq !t10b_staff+
    jmp !t10b_next+
!t10b_potion:
    lda #FLAVOUR_POTION_COUNT
    bne !t10b_check+
!t10b_scroll:
    lda #FLAVOUR_SCROLL_COUNT
    bne !t10b_check+
!t10b_ring:
    lda #FLAVOUR_RING_COUNT
    bne !t10b_check+
!t10b_wand:
    lda #FLAVOUR_WAND_COUNT
    bne !t10b_check+
!t10b_staff:
    lda #FLAVOUR_STAFF_COUNT
!t10b_check:
    sta t10_pool_max
    lda t10_cursor
    jsr item_get_unknown_idx_a
    cmp #$ff
    beq !t10b_next+
    cmp t10_pool_max
    bcc !t10b_next+
    clc
    rts
!t10b_next:
    ldx t10_cursor
    inx
    cpx t10_page_limit
    bcc !t10b_loop-
    sec
    rts

!t10c_part:
    // Part C: distinct class-local indexes (96 -> 10, 98 -> 12) produce
    // distinct unknown appearances; index-0-only tables would collapse them.
    // Unknown names decode into one shared buffer, so compare contents.
    lda #ITEM_PAGE_POTION_OF_HEALING
    sta item_cur_page
    lda #ITEM_SLOT_POTION_OF_HEALING
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
    lda #ITEM_SLOT_POTION_OF_RESIST_HEAT
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

    // Test 11: an unidentified light shows its fuel, as upstream: a
    // burnt-out kit torch reads "(0 turns)", not like a fresh one.
!t11:
    jsr test_prepare_row0
    lda #ITEM_SLOT_WOODEN_TORCH
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

    lda #<expected_spent_torch_desc
    sta zp_ptr0
    lda #>expected_spent_torch_desc
    sta zp_ptr0_hi
    jsr assert_row0_prefix
    bcc !t11_fail+
    lda #$01
    sta tc_results+10
    jmp !t12+
!t11_fail:
    lda #$00
    sta tc_results+10

    // Test 12: a crown of the Magi (MON-030) shows its AC, then its INT
    // bonus as VMS "(%P1)"; a plain crown (p1 0) nothing after its AC. The
    // suffix printer is stubbed here (test_ego.s t23 checks " of the Magi").
!t12:
    jsr test_prepare_row0
    lda #ITEM_SLOT_GOLDEN_CROWN
    sta itemdesc_item_id
    lda #0
    sta itemdesc_qty
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    lda #2
    sta itemdesc_p1
    lda #3
    sta itemdesc_to_ac
    lda #EGO_MAGI
    sta itemdesc_ego
    lda #IF_IDENTIFIED
    sta itemdesc_flags
    jsr itemdesc_put_staged
    lda #<expected_magi_crown_desc
    sta zp_ptr0
    lda #>expected_magi_crown_desc
    sta zp_ptr0_hi
    jsr assert_row0_prefix
    bcc !t12_fail+
    lda $0400 + expected_magi_crown_desc_end - expected_magi_crown_desc - 1
    cmp #$20
    bne !t12_fail+
    jsr test_prepare_row0
    lda #ITEM_SLOT_SILVER_CROWN
    sta itemdesc_item_id
    lda #0
    sta itemdesc_p1
    sta itemdesc_ego
    lda #1
    sta itemdesc_to_ac
    jsr itemdesc_put_staged
    lda #<expected_plain_crown_desc
    sta zp_ptr0
    lda #>expected_plain_crown_desc
    sta zp_ptr0_hi
    jsr assert_row0_prefix
    bcc !t12_fail+
    lda $0400 + expected_plain_crown_desc_end - expected_plain_crown_desc - 1
    cmp #$20
    bne !t12_fail+
    lda #$01
    sta tc_results+11
    jmp !tests_done+
!t12_fail:
    lda #$00
    sta tc_results+11

!tests_done:
    jmp test_finish

t10_cursor:  .byte 0
t10_page_limit: .byte 0
t10_pool_max: .byte 0
t10_name_buf: .fill 32, 0
t10_wrap_ids:
    .byte ITEM_SLOT_POTION_OF_HEALING, ITEM_SLOT_POTION_OF_RESIST_HEAT, ITEM_SLOT_POTION_OF_RESIST_COLD, ITEM_SLOT_POTION_OF_CURE_CRITICAL_WOUNDS, ITEM_SLOT_SCROLL_OF_TELEPORT_LEVEL, ITEM_SLOT_SCROLL_OF_MAGIC_MAPPING, ITEM_SLOT_SCROLL_OF_OBJECT_DETECTION, ITEM_SLOT_SCROLL_OF_RECHARGING, ITEM_SLOT_SCROLL_OF_RUNE_OF_PROTECTION, ITEM_SLOT_SCROLL_OF_GENOCIDE, ITEM_SLOT_SCROLL_OF_MASS_GENOCIDE
    .byte ITEM_SLOT_SCROLL_OF_STAR_DESTRUCTION, ITEM_SLOT_RING_OF_RESIST_FIRE, ITEM_SLOT_RING_OF_RESIST_COLD, ITEM_SLOT_RING_OF_SPEED, ITEM_SLOT_RING_OF_SEE_INVISIBLE, ITEM_SLOT_RING_OF_SLAYING, ITEM_SLOT_WAND_OF_SLOW_MONSTER, ITEM_SLOT_WAND_OF_STONE_TO_MUD, ITEM_SLOT_WAND_OF_TELEPORT_AWAY, ITEM_SLOT_WAND_OF_FIRE_BALLS, ITEM_SLOT_WAND_OF_COLD_BALLS, ITEM_SLOT_STAFF_OF_DISPEL_EVIL
    .byte ITEM_SLOT_STAFF_OF_DESTRUCTION, ITEM_SLOT_STAFF_OF_SPEED, ITEM_SLOT_POTION_OF_NEUTRALIZE_POISON, ITEM_SLOT_STAFF_OF_REMOVE_CURSE
t10_wrap_pages:
    .byte ITEM_PAGE_POTION_OF_HEALING, ITEM_PAGE_POTION_OF_RESIST_HEAT, ITEM_PAGE_POTION_OF_RESIST_COLD, ITEM_PAGE_POTION_OF_CURE_CRITICAL_WOUNDS, ITEM_PAGE_SCROLL_OF_TELEPORT_LEVEL, ITEM_PAGE_SCROLL_OF_MAGIC_MAPPING, ITEM_PAGE_SCROLL_OF_OBJECT_DETECTION, ITEM_PAGE_SCROLL_OF_RECHARGING, ITEM_PAGE_SCROLL_OF_RUNE_OF_PROTECTION, ITEM_PAGE_SCROLL_OF_GENOCIDE, ITEM_PAGE_SCROLL_OF_MASS_GENOCIDE
    .byte ITEM_PAGE_SCROLL_OF_STAR_DESTRUCTION, ITEM_PAGE_RING_OF_RESIST_FIRE, ITEM_PAGE_RING_OF_RESIST_COLD, ITEM_PAGE_RING_OF_SPEED, ITEM_PAGE_RING_OF_SEE_INVISIBLE, ITEM_PAGE_RING_OF_SLAYING, ITEM_PAGE_WAND_OF_SLOW_MONSTER, ITEM_PAGE_WAND_OF_STONE_TO_MUD, ITEM_PAGE_WAND_OF_TELEPORT_AWAY, ITEM_PAGE_WAND_OF_FIRE_BALLS, ITEM_PAGE_WAND_OF_COLD_BALLS, ITEM_PAGE_STAFF_OF_DISPEL_EVIL
    .byte ITEM_PAGE_STAFF_OF_DESTRUCTION, ITEM_PAGE_STAFF_OF_SPEED, ITEM_PAGE_POTION_OF_NEUTRALIZE_POISON, ITEM_PAGE_STAFF_OF_REMOVE_CURSE
t10_wrap_idx:
    .byte 10, 12, 13, 14, 10, 11, 12, 13, 14, 15, 16
    .byte 17, 2, 3, 4, 5, 6, 4, 5, 6, 7, 8, 4
    .byte 5, 6, 15, 7
.assert "t10_wrap table lengths match", (t10_wrap_pages - t10_wrap_ids) == 27 && (t10_wrap_idx - t10_wrap_pages) == 27, true

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
    sta item_cur_page
    sta item_name_test_id
!next_p0_item:
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
    cmp #ITEM_PAGE_SIZE
    bcc !next_p0_item-

    lda #ITEM_PAGE_BIT
    sta item_cur_page
    lda #0
    sta item_name_test_id
!next_p1_item:
    ldx item_name_test_id
    jsr id_known_set
    txa
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
    bcc !next_p1_item-

    lda #0
    sta item_cur_page
    sec
    rts
!fail:
    lda #0
    sta item_cur_page
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
expected_spent_torch_desc:
    .text "Wooden Torch (0 turns)" ; .byte 0
expected_magi_crown_desc:
    .text "Golden Crown [0,+3] (+2)" ; .byte 0
expected_magi_crown_desc_end:
expected_plain_crown_desc:
    .text "Silver Crown [0,+1]" ; .byte 0
expected_plain_crown_desc_end:
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
expected_item_name_hi:
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
.assert "expected_item_name_hi covers Page 0 (0..254)", * - expected_item_name_hi, ITEM_PAGE_SIZE
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
.assert "expected_item_name_p1_hi covers Page 1 (255..360)", * - expected_item_name_p1_hi, ITEM_TYPE_COUNT - ITEM_PAGE_SIZE

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

item_name_test_id: .byte 0
tc_results: .fill 12, $ff
tc_results_end:


// As core/6502/ui_messages.s (not imported here): hal_screen_put_string with A/Y
// = pointer
screen_put_string_ay:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp hal_screen_put_string

item_desc_test_body_end:
.assert "Item desc result count", tc_results_end - tc_results, 12
.assert "Item desc test stays below MAP_BASE", item_desc_test_body_end <= MAP_BASE, true
