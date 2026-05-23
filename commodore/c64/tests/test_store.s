// test_store.s — Runtime tests for store data, pricing, gold, UI helpers
//
// Tests: category check, restocking, math_mul_16x8, buy/sell price calc,
// gold operations, store door detection, find empty slot, and haggle flow.
//
// Results at $0400-$0428: $01 = pass, $00 = fail per test (41 tests)

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #40
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

#import "../../common/zeropage.s"
#import "../memory.s"
#import "../../common/reu.s"
#import "../screen.s"
#import "../../common/color.s"
#import "../config.s"
#import "../input.s"
#import "../../common/rng.s"
#import "../../common/math.s"
#import "../../common/tables.s"
#import "../../common/item_defs.s"
#import "../../common/player.s"
#import "../../common/ui_messages.s"
#import "../../common/ui_status.s"
#import "../../common/ui_help_clear.s"
#import "../../common/ui_character.s"
#import "../../common/stat_display.s"
.segmentdef TestCreateOverlay [start=$D000]
.segment TestCreateOverlay
#import "../../common/background_data.s"
#import "../../common/player_create.s"
.segment Default
#import "../../common/sound.s"
#import "../../common/dungeon_data.s"
#import "../../common/dungeon_gen.s"
#import "../../common/huffman.s"
#import "../../common/dungeon_features.s"
#import "../../common/monster.s"
#import "../../common/tier_manager.s"
#import "../../common/overlay.s"
#import "../../common/monster_ai.s"
#import "../../common/recall.s"
#import "../../common/monster_magic.s"
#import "../../common/item.s"
#import "../../common/special_rooms.s"
#import "../../common/ego_items.s"
#import "../../common/special_rooms_stubs.s"
#import "../../common/player_items.s"
#import "../../common/spell_data.s"
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/player_magic_state.s"
#import "../../common/player_magic_state_ops.s"
#import "../../common/player_magic.s"
#import "../../common/ui_inventory.s"
#import "../../common/ui_equipment.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/store_data.s"
#import "../../common/store_restock_overlay.s"
#import "../../common/store.s"
#import "../../common/ui_store.s"
#import "../../common/ui_help.s"
#import "../../common/ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer — copy to $0400 at end (msg_print clobbers $0400)
tc_results: .fill 41, $ff
tc_count: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_start:
    // Initialize result area to $ff (untested)
    ldx #40
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    :PatchJump(input_get_key, test_input_get_key)

    // Seed RNG deterministically
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    // Set player CHR to 18 for predictable pricing
    lda #18
    sta player_data + PL_CHR_CUR

    // ============================================================
    // Test 1: store_init_all populates some slots
    // ============================================================
    jsr store_init_all

    // Count non-empty slots
    lda #0
    sta tc_count
    ldx #0
!t1_loop:
    cpx #STORE_TOTAL_SLOTS
    bcs !t1_done+
    lda si_item_id,x
    cmp #FI_EMPTY
    beq !t1_next+
    inc tc_count
!t1_next:
    inx
    jmp !t1_loop-
!t1_done:
    lda tc_count
    cmp #1                      // At least 1 slot filled (random, but very likely)
    bcc !t1_fail+
    lda #$01
    jmp !t1_store+
!t1_fail:
    lda #$00
!t1_store:
    sta tc_results + 0

    // ============================================================
    // Test 2: check_store_category valid — FOOD(9) in store 0 (General)
    // ============================================================
    lda #0
    sta zp_store_idx
    lda #ICAT_FOOD              // 9
    jsr check_store_category
    bcs !t2_pass+
    lda #$00
    jmp !t2_store+
!t2_pass:
    lda #$01
!t2_store:
    sta tc_results + 1

    // ============================================================
    // Test 3: check_store_category invalid — WEAPON(2) NOT in store 0
    // ============================================================
    lda #0
    sta zp_store_idx
    lda #ICAT_WEAPON            // 2
    jsr check_store_category
    bcc !t3_pass+
    lda #$00
    jmp !t3_store+
!t3_pass:
    lda #$01
!t3_store:
    sta tc_results + 2

    // ============================================================
    // Test 4: store_pick_item returns valid type for store 1 (Armory)
    // Uses store 1 to catch the X-clobber bug (store idx 1 = gold type)
    // ============================================================
    lda #1
    sta zp_store_idx
    jsr store_pick_item
    // Returned A should be an armor-category item (not gold!)
    cmp #2                      // Must be >= 2 (skip gold types 0-1)
    bcc !t4_fail+
    tax
    lda it_category,x
    // Must match one of armory categories: ARMOR, SHIELD, HELM, GLOVES, BOOTS, CLOAK
    cmp #ICAT_ARMOR
    beq !t4_pass+
    cmp #ICAT_SHIELD
    beq !t4_pass+
    cmp #ICAT_HELM
    beq !t4_pass+
    cmp #ICAT_GLOVES
    beq !t4_pass+
    cmp #ICAT_BOOTS
    beq !t4_pass+
!t4_fail:
    lda #$00
    jmp !t4_store+
!t4_pass:
    lda #$01
!t4_store:
    sta tc_results + 3

    // ============================================================
    // Test 5: store_restock_one fills slots
    // ============================================================
    // Clear store 0 first
    ldx #0
!t5_clr:
    cpx #STORE_MAX_ITEMS
    bcs !t5_clr_done+
    lda #FI_EMPTY
    sta si_item_id,x
    inx
    jmp !t5_clr-
!t5_clr_done:
    lda #0
    sta zp_store_idx
    jsr store_restock_one

    // Count non-empty slots in store 0
    lda #0
    sta tc_count
    ldx #0
!t5_loop:
    cpx #STORE_MAX_ITEMS
    bcs !t5_done+
    lda si_item_id,x
    cmp #FI_EMPTY
    beq !t5_next+
    inc tc_count
!t5_next:
    inx
    jmp !t5_loop-
!t5_done:
    lda tc_count
    cmp #1                      // At least 1 stocked (random, very likely)
    bcc !t5_fail+
    lda #$01
    jmp !t5_store+
!t5_fail:
    lda #$00
!t5_store:
    sta tc_results + 4

    // ============================================================
    // Test 6: math_mul_16x8 basic — 300 × 130 = 39000
    // ============================================================
    lda #<300
    sta zp_temp0
    lda #>300
    sta zp_temp1
    ldx #130
    jsr math_mul_16x8
    // 39000 = $9858
    lda mul_result_0
    cmp #$58
    bne !t6_fail+
    lda mul_result_1
    cmp #$98
    bne !t6_fail+
    lda mul_result_2
    cmp #$00
    bne !t6_fail+
    lda #$01
    jmp !t6_store+
!t6_fail:
    lda #$00
!t6_store:
    sta tc_results + 5

    // ============================================================
    // Test 7: math_mul_16x8 identity — 100 × 1 = 100
    // ============================================================
    lda #<100
    sta zp_temp0
    lda #>100
    sta zp_temp1
    ldx #1
    jsr math_mul_16x8
    lda mul_result_0
    cmp #<100
    bne !t7_fail+
    lda mul_result_1
    cmp #>100
    bne !t7_fail+
    lda #$01
    jmp !t7_store+
!t7_fail:
    lda #$00
!t7_store:
    sta tc_results + 6

    // ============================================================
    // Test 8: calc_buy_price at CHR 18 — price = base_price (adj=100)
    // Item 2 (Dagger) has base cost 10, p1=0.
    // ============================================================
    lda #18
    sta player_data + PL_CHR_CUR
    lda #0
    sta sb_item_p1              // No enchantment
    lda #2                      // Dagger
    jsr calc_buy_price
    lda sb_price_lo
    cmp #10
    bne !t8_fail+
    lda sb_price_hi
    cmp #0
    bne !t8_fail+
    lda #$01
    jmp !t8_store+
!t8_fail:
    lda #$00
!t8_store:
    sta tc_results + 7

    // ============================================================
    // Test 9: calc_buy_price at CHR 3 — price = 10 × 130 / 100 = 13
    // ============================================================
    lda #3
    sta player_data + PL_CHR_CUR
    lda #0
    sta sb_item_p1              // No enchantment
    lda #2                      // Dagger
    jsr calc_buy_price
    lda sb_price_lo
    cmp #13
    bne !t9_fail+
    lda sb_price_hi
    cmp #0
    bne !t9_fail+
    lda #$01
    jmp !t9_store+
!t9_fail:
    lda #$00
!t9_store:
    sta tc_results + 8

    // ============================================================
    // Test 10: calc_sell_price at CHR 18 — price = 10 × 50 / 100 = 5
    // ============================================================
    lda #18
    sta player_data + PL_CHR_CUR
    lda #0
    sta sb_item_p1              // No enchantment
    sta sb_item_to_hit
    sta sb_item_to_dam
    sta sb_item_to_ac
    lda #2                      // Dagger (base 10)
    jsr calc_sell_price
    lda sb_price_lo
    cmp #5
    bne !t10_fail+
    lda sb_price_hi
    cmp #0
    bne !t10_fail+
    lda #$01
    jmp !t10_store+
!t10_fail:
    lda #$00
!t10_store:
    sta tc_results + 9

    // ============================================================
    // Test 11: gold_check_afford exact amount — carry set
    // ============================================================
    lda #50
    sta player_data + PL_GOLD_0
    lda #0
    sta player_data + PL_GOLD_1
    sta player_data + PL_GOLD_2
    lda #50
    sta sb_price_lo
    lda #0
    sta sb_price_hi
    jsr gold_check_afford
    bcs !t11_pass+
    lda #$00
    jmp !t11_store+
!t11_pass:
    lda #$01
!t11_store:
    sta tc_results + 10

    // ============================================================
    // Test 12: gold_check_afford 1 short — carry clear
    // ============================================================
    lda #49
    sta player_data + PL_GOLD_0
    lda #0
    sta player_data + PL_GOLD_1
    sta player_data + PL_GOLD_2
    lda #50
    sta sb_price_lo
    lda #0
    sta sb_price_hi
    jsr gold_check_afford
    bcc !t12_pass+
    lda #$00
    jmp !t12_store+
!t12_pass:
    lda #$01
!t12_store:
    sta tc_results + 11

    // ============================================================
    // Test 13: gold_subtract_price — gold decreases correctly
    // ============================================================
    lda #100
    sta player_data + PL_GOLD_0
    lda #0
    sta player_data + PL_GOLD_1
    sta player_data + PL_GOLD_2
    lda #30
    sta sb_price_lo
    lda #0
    sta sb_price_hi
    jsr gold_subtract_price
    lda player_data + PL_GOLD_0
    cmp #70
    bne !t13_fail+
    lda #$01
    jmp !t13_store+
!t13_fail:
    lda #$00
!t13_store:
    sta tc_results + 12

    // ============================================================
    // Test 14: gold_add_price — gold increases correctly
    // ============================================================
    lda #70
    sta player_data + PL_GOLD_0
    lda #0
    sta player_data + PL_GOLD_1
    sta player_data + PL_GOLD_2
    lda #25
    sta sb_price_lo
    lda #0
    sta sb_price_hi
    jsr gold_add_price
    lda player_data + PL_GOLD_0
    cmp #95
    bne !t14_fail+
    lda #$01
    jmp !t14_store+
!t14_fail:
    lda #$00
!t14_store:
    sta tc_results + 13

    // ============================================================
    // Test 15: check_player_on_store_door match
    // Store 0 door uses the shared town door table.
    // ============================================================
    lda store_door_x + 0
    sta zp_player_x
    lda store_door_y + 0
    sta zp_player_y
    jsr check_player_on_store_door
    bcc !t15_fail+
    cmp #0                      // Should be store index 0
    bne !t15_fail+
    lda #$01
    jmp !t15_store+
!t15_fail:
    lda #$00
!t15_store:
    sta tc_results + 14

    // ============================================================
    // Test 16: check_player_on_store_door no match
    // ============================================================
    lda #40
    sta zp_player_x
    lda #40
    sta zp_player_y
    jsr check_player_on_store_door
    bcc !t16_pass+
    lda #$00
    jmp !t16_store+
!t16_pass:
    lda #$01
!t16_store:
    sta tc_results + 15

    // ============================================================
    // Test 17: store_find_empty_slot returns first empty
    // ============================================================
    // Clear store 0, put item in slot 0 only
    ldx #0
!t17_clr:
    cpx #STORE_MAX_ITEMS
    bcs !t17_clr_done+
    lda #FI_EMPTY
    sta si_item_id,x
    inx
    jmp !t17_clr-
!t17_clr_done:
    lda #2                      // Dagger in slot 0
    sta si_item_id + 0
    lda #0
    sta zp_store_idx
    jsr store_find_empty_slot
    bcc !t17_fail+
    cpx #1                      // First empty should be abs slot 1
    bne !t17_fail+
    lda #$01
    jmp !t17_store+
!t17_fail:
    lda #$00
!t17_store:
    sta tc_results + 16

    // ============================================================
    // Test 18: calc_buy_price with enchantment — dagger +2/+2 at CHR 18
    // base=10, split stat bonus=(2+2)×100=400, total=410
    // ============================================================
    lda #18
    sta player_data + PL_CHR_CUR
    lda #2
    sta sb_item_to_hit          // +2 enchantment
    sta sb_item_to_dam
    lda #0
    sta sb_item_p1
    sta sb_item_to_ac
    lda #2                      // Dagger (base 10)
    jsr calc_buy_price
    lda sb_price_lo
    cmp #<410
    bne !t18_fail+
    lda sb_price_hi
    cmp #>410
    bne !t18_fail+
    lda #$01
    jmp !t18_store+
!t18_fail:
    lda #$00
!t18_store:
    sta tc_results + 17

    // ============================================================
    // Test 19: calc_sell_price with enchantment — dagger +2/+2 at CHR 18
    // base sell=10×50/100=5, split stat bonus=400, total=405
    // ============================================================
    lda #18
    sta player_data + PL_CHR_CUR
    lda #2
    sta sb_item_to_hit          // +2 enchantment
    sta sb_item_to_dam
    lda #0
    sta sb_item_p1
    sta sb_item_to_ac
    lda #2                      // Dagger (base 10)
    jsr calc_sell_price
    lda sb_price_lo
    cmp #<405
    bne !t19_fail+
    lda sb_price_hi
    cmp #>405
    bne !t19_fail+
    lda #$01
    jmp !t19_store+
!t19_fail:
    lda #$00
!t19_store:
    sta tc_results + 18

    // ============================================================
    // Test 20: calc_buy_min_price — dagger (base=10, p1=0) at CHR 3
    // Should be 10 (no CHR markup), not 13
    // ============================================================
    lda #3
    sta player_data + PL_CHR_CUR
    lda #0
    sta sb_item_p1
    sta sb_item_to_hit
    sta sb_item_to_dam
    sta sb_item_to_ac
    lda #2                      // Dagger (base 10)
    jsr calc_buy_min_price
    lda sb_price_lo
    cmp #10
    bne !t20_fail+
    lda sb_price_hi
    cmp #0
    bne !t20_fail+
    lda #$01
    jmp !t20_store+
!t20_fail:
    lda #$00
!t20_store:
    sta tc_results + 19

    // ============================================================
    // Test 21: calc_buy_min_price — dagger +2/+2 → expect 410
    // base=10 + (2+2)×100=400 = 410
    // ============================================================
    lda #3
    sta player_data + PL_CHR_CUR
    lda #2
    sta sb_item_to_hit
    sta sb_item_to_dam
    lda #0
    sta sb_item_p1
    sta sb_item_to_ac
    lda #2                      // Dagger
    jsr calc_buy_min_price
    lda sb_price_lo
    cmp #<410
    bne !t21_fail+
    lda sb_price_hi
    cmp #>410
    bne !t21_fail+
    lda #$01
    jmp !t21_store+
!t21_fail:
    lda #$00
!t21_store:
    sta tc_results + 20

    // ============================================================
    // Test 22: Gap step math — ask=130, min=100
    // gap = 30, step = 30/4 = 7, new ask = 130-7 = 123
    // ============================================================
    lda #130
    sta hg_ask_lo
    lda #0
    sta hg_ask_hi
    lda #100
    sta hg_min_lo
    lda #0
    sta hg_min_hi

    // gap = ask - min
    lda hg_ask_lo
    sec
    sbc hg_min_lo
    sta hg_tmp0
    lda hg_ask_hi
    sbc hg_min_hi
    sta hg_tmp1
    // step = gap / 4
    lsr hg_tmp1
    ror hg_tmp0
    lsr hg_tmp1
    ror hg_tmp0
    // ask -= step
    lda hg_ask_lo
    sec
    sbc hg_tmp0
    sta hg_ask_lo
    lda hg_ask_hi
    sbc hg_tmp1
    sta hg_ask_hi

    // Expect ask = 123
    lda hg_ask_lo
    cmp #123
    bne !t22_fail+
    lda hg_ask_hi
    cmp #0
    bne !t22_fail+
    lda #$01
    jmp !t22_store+
!t22_fail:
    lda #$00
!t22_store:
    sta tc_results + 21

    // ============================================================
    // Test 23: calc_bm_buy_price — dagger (base=10) × 3 = 30 GP
    // ============================================================
    lda #0
    sta sb_item_p1              // No enchantment
    sta sb_item_to_hit
    sta sb_item_to_dam
    sta sb_item_to_ac
    lda #2                      // Dagger (base 10)
    jsr calc_bm_buy_price
    lda sb_price_lo
    cmp #30
    bne !t23_fail+
    lda sb_price_hi
    cmp #0
    bne !t23_fail+
    lda #$01
    jmp !t23_store+
!t23_fail:
    lda #$00
!t23_store:
    sta tc_results + 22

    // ============================================================
    // Test 24: calc_bm_sell_price — dagger (base=10) / 10 = 1 GP
    // ============================================================
    lda #0
    sta sb_item_p1              // No enchantment
    lda #2                      // Dagger (base 10)
    jsr calc_bm_sell_price
    lda sb_price_lo
    cmp #1
    bne !t24_fail+
    lda sb_price_hi
    cmp #0
    bne !t24_fail+
    lda #$01
    jmp !t24_store+
!t24_fail:
    lda #$00
!t24_store:
    sta tc_results + 23

    // ============================================================
    // Test 25: check_player_on_store_door at BM door → store 6
    // ============================================================
    lda store_door_x + 6
    sta zp_player_x
    lda store_door_y + 6
    sta zp_player_y
    jsr check_player_on_store_door
    bcc !t25_fail+
    cmp #6                      // Should be store index 6 (BM)
    bne !t25_fail+
    lda #$01
    jmp !t25_store+
!t25_fail:
    lda #$00
!t25_store:
    sta tc_results + 24

    // ============================================================
    // Test 26: check_player_on_store_door at Home door → store 7
    // ============================================================
    lda store_door_x + 7
    sta zp_player_x
    lda store_door_y + 7
    sta zp_player_y
    jsr check_player_on_store_door
    bcc !t26_fail+
    cmp #7                      // Should be store index 7 (Home)
    bne !t26_fail+
    lda #$01
    jmp !t26_store+
!t26_fail:
    lda #$00
!t26_store:
    sta tc_results + 25

    // ============================================================
    // Test 27: huff_decode_string — decode string 4 ("Ridiculous!")
    // Verify: R=$52, i=$09, d=$04, !=$21, null at [11], zp_ptr0
    // (screencode_mixed: uppercase A-Z=$41-$5A, lowercase a-z=$01-$1A)
    // ============================================================
    ldx #4                      // String 4 = "Ridiculous!"
    jsr huff_decode_string
    lda hd_decode_buf + 0
    cmp #$52                    // 'R' (uppercase)
    bne !t27_fail+
    lda hd_decode_buf + 1
    cmp #$09                    // 'i' (lowercase)
    bne !t27_fail+
    lda hd_decode_buf + 2
    cmp #$04                    // 'd' (lowercase)
    bne !t27_fail+
    lda hd_decode_buf + 10
    cmp #$21
    bne !t27_fail+
    lda hd_decode_buf + 11
    cmp #$00
    bne !t27_fail+
    lda zp_ptr0
    cmp #<hd_decode_buf
    bne !t27_fail+
    lda zp_ptr0_hi
    cmp #>hd_decode_buf
    bne !t27_fail+
    lda #$01
    jmp !t27_store+
!t27_fail:
    lda #$00
!t27_store:
    sta tc_results + 26

    // ============================================================
    // Test 28: Variable probability restock — empty store fills well
    // Clear store 0, call store_restock_one. With 0 items, 75% fill
    // rate should stock at least 4 of 12 slots.
    // ============================================================
    ldx #0
!t28_clr:
    cpx #STORE_MAX_ITEMS
    bcs !t28_clr_done+
    lda #FI_EMPTY
    sta si_item_id,x
    inx
    jmp !t28_clr-
!t28_clr_done:
    lda #0
    sta zp_store_idx
    jsr store_restock_one

    // Count non-empty slots in store 0
    lda #0
    sta tc_count
    ldx #0
!t28_loop:
    cpx #STORE_MAX_ITEMS
    bcs !t28_done+
    lda si_item_id,x
    cmp #FI_EMPTY
    beq !t28_next+
    inc tc_count
!t28_next:
    inx
    jmp !t28_loop-
!t28_done:
    lda tc_count
    cmp #4                      // At least 4 stocked (75% rate, very likely)
    bcc !t28_fail+
    lda #$01
    jmp !t28_store+
!t28_fail:
    lda #$00
!t28_store:
    sta tc_results + 27

    // ============================================================
    // Test 29: store_restock_one sets IF_IDENTIFIED on stocked items
    // ============================================================
    ldx #0
!t29_clr:
    cpx #STORE_MAX_ITEMS
    bcs !t29_clr_done+
    lda #FI_EMPTY
    sta si_item_id,x
    lda #0
    sta si_meta,x
    inx
    jmp !t29_clr-
!t29_clr_done:
    lda #0
    sta zp_store_idx
    jsr store_restock_one

    // Find first occupied slot and verify IF_IDENTIFIED is set
    ldx #0
!t29_scan:
    cpx #STORE_MAX_ITEMS
    bcs !t29_fail+              // No items stocked → fail
    lda si_item_id,x
    cmp #FI_EMPTY
    beq !t29_next+
    lda si_meta,x
    and #IF_IDENTIFIED
    bne !t29_pass+
    jmp !t29_fail+              // Occupied but flag not set
!t29_next:
    inx
    jmp !t29_scan-
!t29_pass:
    lda #$01
    jmp !t29_store+
!t29_fail:
    lda #$00
!t29_store:
    sta tc_results + 28

    // ============================================================
    // Test 30: input_read_number supports delete and ignores extra digits
    // Script: 1 2 DEL 3 4 5 6 7 RET => 13456
    // ============================================================
    jsr reset_haggle_fixture
    lda #<script_num_edit
    ldy #>script_num_edit
    jsr set_test_input_script
    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    jsr input_read_number
    bcc !t30_fail+
    lda hg_input_lo
    cmp #<13456
    bne !t30_fail+
    lda hg_input_hi
    cmp #>13456
    bne !t30_fail+
    lda #$01
    jmp !t30_store+
!t30_fail:
    lda #$00
!t30_store:
    sta tc_results + 29

    // ============================================================
    // Test 31: haggle_buy retries overshoot, then accepts exact ask
    // Script: 20 RET, ack, 12 RET
    // ============================================================
    jsr reset_haggle_fixture
    lda #0
    sta zp_store_idx
    sta sb_abs_slot
    lda #2
    sta si_item_id + 0
    lda #0
    sta si_p1 + 0
    sta sb_price_hi
    lda #12
    sta sb_price_lo
    lda #<script_buy_retry
    ldy #>script_buy_retry
    jsr set_test_input_script
    jsr haggle_buy
    bcc !t31_fail+
    lda sb_price_lo
    cmp #12
    bne !t31_fail+
    lda sb_price_hi
    bne !t31_fail+
    lda hg_insults
    bne !t31_fail+
    lda #$01
    jmp !t31_store+
!t31_fail:
    lda #$00
!t31_store:
    sta tc_results + 30

    // ============================================================
    // Test 32: haggle_buy insults backwards second offer, then cancels
    // Script: 6 RET, ack, 5 RET, ack, Q
    // ============================================================
    jsr reset_haggle_fixture
    lda #0
    sta zp_store_idx
    sta sb_abs_slot
    lda #2
    sta si_item_id + 0
    lda #0
    sta si_p1 + 0
    sta sb_price_hi
    lda #12
    sta sb_price_lo
    lda #<script_buy_backwards
    ldy #>script_buy_backwards
    jsr set_test_input_script
    jsr haggle_buy
    bcs !t32_fail+
    lda hg_insults
    cmp #1
    bne !t32_fail+
    lda hg_kicked + 0
    bne !t32_fail+
    lda #$01
    jmp !t32_store+
!t32_fail:
    lda #$00
!t32_store:
    sta tc_results + 31

    // ============================================================
    // Test 33: haggle_sell retries undershoot, then accepts exact offer
    // Script: 4 RET, ack, 5 RET
    // ============================================================
    jsr reset_haggle_fixture
    lda #0
    sta zp_store_idx
    lda #10
    sta sb_price_lo
    lda #0
    sta sb_price_hi
    lda #<script_sell_retry
    ldy #>script_sell_retry
    jsr set_test_input_script
    jsr haggle_sell
    bcc !t33_fail+
    lda sb_price_lo
    cmp #5
    bne !t33_fail+
    lda sb_price_hi
    bne !t33_fail+
    lda hg_insults
    bne !t33_fail+
    lda #$01
    jmp !t33_store+
!t33_fail:
    lda #$00
!t33_store:
    sta tc_results + 32

    // ============================================================
    // Test 34: haggle_sell insults backwards second ask, then cancels
    // Script: 9 RET, ack, 10 RET, ack, Q
    // ============================================================
    jsr reset_haggle_fixture
    lda #0
    sta zp_store_idx
    lda #10
    sta sb_price_lo
    lda #0
    sta sb_price_hi
    lda #<script_sell_backwards
    ldy #>script_sell_backwards
    jsr set_test_input_script
    jsr haggle_sell
    bcs !t34_fail+
    lda hg_insults
    cmp #1
    bne !t34_fail+
    lda hg_kicked + 0
    bne !t34_fail+
    lda #$01
    jmp !t34_store+
!t34_fail:
    lda #$00
!t34_store:
    sta tc_results + 33

    // ============================================================
    // Test 35: BM buy path bypasses haggling and cools insults
    // ============================================================
    jsr reset_haggle_fixture
    lda #STORE_BM
    sta zp_store_idx
    lda #2
    sta hg_insults
    lda #50
    sta player_data + PL_GOLD_0
    ldx #STORE_BM
    lda store_base_idx,x
    tax
    lda #2
    sta si_item_id,x
    lda #1
    sta si_qty,x
    lda #<script_buy_yes
    ldy #>script_buy_yes
    jsr set_test_input_script
    jsr store_buy
    lda inv_item_id + 0
    cmp #2
    bne !t35_fail+
    lda hg_insults
    cmp #1
    bne !t35_fail+
    ldx #STORE_BM
    lda store_base_idx,x
    tax
    lda si_item_id,x
    cmp #FI_EMPTY
    bne !t35_fail+
    lda #$01
    jmp !t35_store+
!t35_fail:
    lda #$00
!t35_store:
    sta tc_results + 34

    // ============================================================
    // Test 36: cheap normal-store buy bypasses haggling and cools insults
    // ============================================================
    jsr reset_haggle_fixture
    lda #0
    sta zp_store_idx
    lda #2
    sta hg_insults
    lda #50
    sta player_data + PL_GOLD_0
    lda #2
    sta si_item_id + 0
    lda #1
    sta si_qty + 0
    lda #<script_buy_yes
    ldy #>script_buy_yes
    jsr set_test_input_script
    jsr store_buy
    lda inv_item_id + 0
    cmp #2
    bne !t36_fail+
    lda hg_insults
    cmp #1
    bne !t36_fail+
    lda si_item_id + 0
    cmp #FI_EMPTY
    bne !t36_fail+
    lda #$01
    jmp !t36_store+
!t36_fail:
    lda #$00
!t36_store:
    sta tc_results + 35

    // ============================================================
    // Test 37: repeated insulting buy offers kick the player out
    // Script: 4 RET, ack, 4 RET, ack, 4 RET, ack
    // ============================================================
    jsr reset_haggle_fixture
    lda #0
    sta zp_store_idx
    sta sb_abs_slot
    lda #2
    sta si_item_id + 0
    lda #0
    sta si_p1 + 0
    sta sb_price_hi
    lda #12
    sta sb_price_lo
    lda #<script_buy_kick
    ldy #>script_buy_kick
    jsr set_test_input_script
    jsr haggle_buy
    bcs !t37_fail+
    lda hg_kicked + 0
    cmp #1
    bne !t37_fail+
    lda hg_insults
    cmp #3
    bne !t37_fail+
    lda #$01
    jmp !t37_store+
!t37_fail:
    lda #$00
!t37_store:
    sta tc_results + 36

    // ============================================================
    // Test 38: store_buy preserves split combat stats and metadata
    // ============================================================
    jsr reset_haggle_fixture
    lda #STORE_BM
    sta zp_store_idx
    lda #$ff
    sta player_data + PL_GOLD_0
    sta player_data + PL_GOLD_1
    sta player_data + PL_GOLD_2
    ldx #STORE_BM
    lda store_base_idx,x
    tax
    lda #2
    sta si_item_id,x
    lda #1
    sta si_qty,x
    lda #4
    sta si_to_hit,x
    lda #5
    sta si_to_dam,x
    lda #0
    sta si_to_ac,x
    lda #(IF_IDENTIFIED | (3 << ITEM_META_EGO_SHIFT))
    sta si_meta,x
    lda #<script_buy_yes
    ldy #>script_buy_yes
    jsr set_test_input_script
    jsr store_buy
    lda inv_item_id + 0
    cmp #2
    bne !t38_fail+
    lda inv_to_hit + 0
    cmp #4
    bne !t38_fail+
    lda inv_to_dam + 0
    cmp #5
    bne !t38_fail+
    lda inv_flags + 0
    and #IF_IDENTIFIED
    beq !t38_fail+
    lda inv_ego + 0
    cmp #3
    bne !t38_fail+
    lda #$01
    jmp !t38_store+
!t38_fail:
    lda #$00
!t38_store:
    sta tc_results + 37

    // ============================================================
    // Test 39: store_sell preserves split combat stats and metadata
    // ============================================================
    jsr reset_haggle_fixture
    lda #STORE_BM
    sta zp_store_idx
    lda #2
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #6
    sta inv_to_hit + 0
    lda #7
    sta inv_to_dam + 0
    lda #0
    sta inv_to_ac + 0
    lda #IF_IDENTIFIED
    sta inv_flags + 0
    lda #4
    sta inv_ego + 0
    lda #<script_sell_yes
    ldy #>script_sell_yes
    jsr set_test_input_script
    jsr store_sell
    ldx #STORE_BM
    lda store_base_idx,x
    tax
    lda si_item_id,x
    cmp #2
    bne !t39_fail+
    lda si_to_hit,x
    cmp #6
    bne !t39_fail+
    lda si_to_dam,x
    cmp #7
    bne !t39_fail+
    lda si_meta,x
    and #ITEM_META_FLAGS_MASK
    cmp #IF_IDENTIFIED
    bne !t39_fail+
    lda si_meta,x
    and #ITEM_META_EGO_MASK
    cmp #(4 << ITEM_META_EGO_SHIFT)
    bne !t39_fail+
    lda inv_item_id + 0
    cmp #FI_EMPTY
    bne !t39_fail+
    lda #$01
    jmp !t39_store+
!t39_fail:
    lda #$00
!t39_store:
    sta tc_results + 38

    // ============================================================
    // Test 40: sro_set_p1 initializes light fuel for store stock
    // ============================================================
    lda #13                     // Wooden Torch
    sta si_item_id + 0
    lda #0
    sta srr_abs_slot
    lda #ICAT_LIGHT
    jsr sro_set_p1
    lda si_p1 + 0
    cmp #134
    bne !t40_fail+

    lda #14                     // Brass Lantern
    sta si_item_id + 1
    lda #1
    sta srr_abs_slot
    lda #ICAT_LIGHT
    jsr sro_set_p1
    lda si_p1 + 1
    cmp #LANTERN_MAX_CHARGES
    bne !t40_fail+

    lda #ITEM_FLASK_OIL
    sta si_item_id + 2
    lda #2
    sta srr_abs_slot
    lda #ICAT_LIGHT
    jsr sro_set_p1
    lda si_p1 + 2
    cmp #LANTERN_MAX_CHARGES
    bne !t40_fail+
    lda #$01
    jmp !t40_store+
!t40_fail:
    lda #$00
!t40_store:
    sta tc_results + 39

    // ============================================================
    // Test 41: store_draw_screen clears long names before price field
    // ============================================================
    jsr reset_haggle_fixture
    lda #0
    sta zp_store_idx
    lda #57                     // Spellbook The Mages Guide to Power
    sta si_item_id + 0
    lda #1
    sta si_qty + 0
    lda #IF_IDENTIFIED
    sta si_meta + 0
    jsr store_draw_screen
    lda #3
    sta zp_cursor_row
    lda #30
    sta zp_cursor_col
    jsr screen_set_cursor
    ldy #0
    lda (zp_screen_lo),y
    cmp #$20
    bne !t41_fail+
    lda #3
    sta zp_cursor_row
    lda #37
    sta zp_cursor_col
    jsr screen_set_cursor
    ldy #0
    lda (zp_screen_lo),y
    cmp #$20
    bne !t41_fail+
    iny
    lda (zp_screen_lo),y
    cmp #$20
    bne !t41_fail+
    lda #$01
    jmp !t41_store+
!t41_fail:
    lda #$00
!t41_store:
    sta tc_results + 40

    jmp test_exit_trampoline

reset_haggle_fixture:
    jsr screen_clear

    lda #18
    sta player_data + PL_CHR_CUR

    lda #0
    sta player_data + PL_GOLD_1
    sta player_data + PL_GOLD_2
    lda #200
    sta player_data + PL_GOLD_0

    ldx #7
    lda #0
!clr_kick:
    sta hg_kicked,x
    dex
    bpl !clr_kick-

    lda #0
    sta hg_ask_lo
    sta hg_ask_hi
    sta hg_min_lo
    sta hg_min_hi
    sta hg_last_lo
    sta hg_last_hi
    sta hg_input_lo
    sta hg_input_hi
    sta hg_den_lo
    sta hg_den_hi
    sta hg_pct
    sta hg_round
    sta hg_insults
    sta hg_tmp0
    sta hg_tmp1
    sta hg_digit_cnt
    sta sb_price_lo
    sta sb_price_hi
    sta sb_abs_slot
    sta ss_inv_slot
    sta ss_item_id
    sta sb_item_p1
    sta sb_item_ego
    sta zp_store_idx

    ldx #STORE_TOTAL_SLOTS - 1
    lda #FI_EMPTY
!clr_store_id:
    sta si_item_id,x
    dex
    bpl !clr_store_id-

    ldx #STORE_TOTAL_SLOTS - 1
    lda #0
!clr_store_rest:
    sta si_qty,x
    sta si_p1,x
    sta si_to_hit,x
    sta si_to_dam,x
    sta si_to_ac,x
    sta si_meta,x
    dex
    bpl !clr_store_rest-

    ldx #MAX_INV_SLOTS - 1
    lda #FI_EMPTY
!clr_inv_id:
    sta inv_item_id,x
    dex
    bpl !clr_inv_id-

    ldx #MAX_INV_SLOTS - 1
    lda #0
!clr_inv_rest:
    sta inv_qty,x
    sta inv_p1,x
    sta inv_to_hit,x
    sta inv_to_dam,x
    sta inv_to_ac,x
    sta inv_flags,x
    sta inv_ego,x
    dex
    bpl !clr_inv_rest-
    rts

set_test_input_script:
    sta zp_ptr2
    sty zp_ptr2_hi
    lda #0
    sta test_input_idx
    rts

test_input_get_key:
    ldy test_input_idx
    lda (zp_ptr2),y
    beq !default+
    iny
    sty test_input_idx
    rts
!default:
    lda #PETSCII_Q
    rts

test_input_idx:    .byte 0

script_num_edit:
    .byte '1', '2', $14, '3', '4', '5', '6', '7', $0d, 0
script_buy_retry:
    .byte '2', '0', $0d, 'X', '1', '2', $0d, 0
script_buy_backwards:
    .byte '6', $0d, 'X', '5', $0d, 'X', PETSCII_Q, 0
script_sell_retry:
    .byte '4', $0d, 'X', '5', $0d, 0
script_sell_backwards:
    .byte '9', $0d, 'X', '1', '0', $0d, 'X', PETSCII_Q, 0
script_buy_yes:
    .byte PETSCII_A, PETSCII_Y, 0
script_sell_yes:
    .byte PETSCII_A, PETSCII_Y, 'X', 0
script_buy_kick:
    .byte '4', $0d, 'X', '4', $0d, 'X', '4', $0d, 'X', 0
