// test_store.s — Runtime tests for store data, pricing, gold, UI helpers
//
// Tests: category check, restocking, math_mul_16x8, buy/sell price calc,
// gold operations, store door detection, find empty slot.
//
// Results at $0400-$0410: $01 = pass, $00 = fail per test (17 tests)

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #18
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_upper"

#import "../zeropage.s"
#import "../memory.s"
#import "../reu.s"
#import "../screen.s"
#import "../color.s"
#import "../config.s"
#import "../input.s"
#import "../rng.s"
#import "../math.s"
#import "../tables.s"
#import "../player.s"
#import "../ui_messages.s"
#import "../ui_status.s"
#import "../ui_character.s"
#import "../player_create.s"
#import "../sound.s"
#import "../dungeon_gen.s"
#import "../dungeon_features.s"
#import "../monster.s"
#import "../tier_manager.s"
#import "../monster_ai.s"
#import "../monster_magic.s"
#import "../item.s"
#import "../special_rooms.s"
#import "../ego_items.s"
#import "../special_rooms_stubs.s"
#import "../player_items.s"
#import "../spell_data.s"
#import "../spell_effects.s"
#import "../player_magic.s"
#import "../ui_inventory.s"
#import "../dungeon_render.s"
#import "../dungeon_los.s"
#import "../player_move.s"
#import "../combat.s"
#import "../monster_attack.s"
#import "../turn.s"
#import "../store.s"
#import "../ui_store.s"
#import "../ui_help.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer — copy to $0400 at end (msg_print clobbers $0400)
tc_results: .fill 20, $ff
tc_count: .byte 0

test_start:
    // Initialize result area to $ff (untested)
    ldx #16
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

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
    // Store 0 door is at (10, 7)
    // ============================================================
    lda #10
    sta zp_player_x
    lda #7
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
    // Test 18: calc_buy_price with enchantment — dagger +2 at CHR 18
    // base=10, p1=2, bonus=2×100=200, total=10+200=210
    // ============================================================
    lda #18
    sta player_data + PL_CHR_CUR
    lda #2
    sta sb_item_p1              // +2 enchantment
    lda #2                      // Dagger (base 10)
    jsr calc_buy_price
    lda sb_price_lo
    cmp #<210
    bne !t18_fail+
    lda sb_price_hi
    cmp #>210
    bne !t18_fail+
    lda #$01
    jmp !t18_store+
!t18_fail:
    lda #$00
!t18_store:
    sta tc_results + 17

    // ============================================================
    // Test 19: calc_sell_price with enchantment — dagger +2 at CHR 18
    // base sell=10×50/100=5, p1=2, bonus=200, total=5+200=205
    // ============================================================
    lda #18
    sta player_data + PL_CHR_CUR
    lda #2
    sta sb_item_p1              // +2 enchantment
    lda #2                      // Dagger (base 10)
    jsr calc_sell_price
    lda sb_price_lo
    cmp #<205
    bne !t19_fail+
    lda sb_price_hi
    cmp #>205
    bne !t19_fail+
    lda #$01
    jmp !t19_store+
!t19_fail:
    lda #$00
!t19_store:
    sta tc_results + 18

    jmp test_exit_trampoline
