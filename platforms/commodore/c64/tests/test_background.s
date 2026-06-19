// test_background.s — Runtime tests for R17: Background, Gender, Gold
//
// Tests: create_gen_background (3 races), create_calc_gold (range, SC
//        variation, female bonus), bg_word_wrap (38-char limit),
//        player_init clears background buffer.
//
// Results at $0400-$0407: $01 = pass, $00 = fail per test (8 tests)

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    :BankOutBasic()
    ldx #7
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0830 "Main"

.encoding "screencode_mixed"

#import "../../../../core/zeropage.s"
#import "../memory.s"
#import "../../common/reu.s"
#import "../screen.s"
#import "../../../../core/color.s"
#import "../config.s"
#import "../input.s"
#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/tables.s"
#import "../../../../core/item_defs.s"
#import "../../../../core/player.s"
#import "../../../../core/ui_messages.s"
#import "../../../../core/ui_status.s"
#import "../../../../core/ui_help_clear.s"
#import "../../../../core/ui_character.s"
#import "../../../../core/stat_display.s"
#import "../../../../core/background_data.s"
#import "../../../../core/player_create.s"
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "../../../../core/dungeon_gen.s"
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_features.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/monster_ai.s"
#import "../../../../core/recall.s"
#import "../../../../core/monster_magic.s"
#import "../../../../core/item.s"
#import "../../../../core/special_rooms.s"
#import "../../../../core/ego_items.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/special_rooms_stubs.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"

store_init_all:
    rts

store_restock_all:
    rts

store_enter:
    rts

ui_help_show_paged:
ui_help_display:
help_draw_line:
help_draw_hborder:
    rts

ui_inv_display:
ui_inv_select_display:
    rts

ui_equip_display:
    rts

show_inv_and_select:
    lda #$20
    rts

piw_prompt_filtered_inv:
    clc
    rts

piw_pick_filtered_inv_key:
    clc
    rts

magic_recalc_mana:
    rts

magic_check_new_spells:
    rts

pm_setup_active_tables:
    rts

eff_teleport_self:
    rts

eff_kill_monster:
    rts

eff_detect_timer:
    .byte 0

#import "../../../../core/ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer
tc_results: .fill 8, $ff

// Saved gold for comparison tests
saved_gold_lo: .byte 0
saved_gold_hi: .byte 0

test_start:
    ldx #7
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    // ==========================================
    // Test 1: Human background — non-empty text + valid SC
    // ==========================================
    jsr seed_rng
    jsr player_init
    lda #RACE_HUMAN
    sta player_data + PL_RACE

    jsr create_gen_background

    lda player_background
    beq !t1_fail+
    lda player_data + PL_SOCIAL_CLASS
    cmp #1
    bcc !t1_fail+
    cmp #101
    bcs !t1_fail+
    lda #$01
    jmp !t1_store+
!t1_fail:
    lda #$00
!t1_store:
    sta tc_results + 0

    // ==========================================
    // Test 2: Elf background — non-empty text + valid SC
    // ==========================================
    jsr seed_rng
    jsr player_init
    lda #RACE_ELF
    sta player_data + PL_RACE

    jsr create_gen_background

    lda player_background
    beq !t2_fail+
    lda player_data + PL_SOCIAL_CLASS
    cmp #1
    bcc !t2_fail+
    cmp #101
    bcs !t2_fail+
    lda #$01
    jmp !t2_store+
!t2_fail:
    lda #$00
!t2_store:
    sta tc_results + 1

    // ==========================================
    // Test 3: Half-Troll background — non-empty text + valid SC
    // ==========================================
    jsr seed_rng
    jsr player_init
    lda #RACE_HALF_TROLL
    sta player_data + PL_RACE

    jsr create_gen_background

    lda player_background
    beq !t3_fail+
    lda player_data + PL_SOCIAL_CLASS
    cmp #1
    bcc !t3_fail+
    cmp #101
    bcs !t3_fail+
    lda #$01
    jmp !t3_store+
!t3_fail:
    lda #$00
!t3_store:
    sta tc_results + 2

    // ==========================================
    // Test 4: Gold formula — SC=50, all stats=10, male
    // gold = 50*6 + rng(25) + 326 - 0 = 626 + [0..24]
    // Expected: $0272-$028A (626-650)
    // ==========================================
    jsr player_init
    lda #50
    sta player_data + PL_SOCIAL_CLASS
    lda #10
    ldx #5
!t4_set:
    sta player_data + PL_STR_CUR,x
    dex
    bpl !t4_set-
    lda #PLF_MALE
    sta player_data + PL_FLAGS
    jsr seed_rng

    jsr create_calc_gold

    lda player_data + PL_GOLD_1
    cmp #$02
    bne !t4_fail+
    lda player_data + PL_GOLD_0
    cmp #$72
    bcc !t4_fail+
    cmp #$8B
    bcs !t4_fail+
    lda #$01
    jmp !t4_store+
!t4_fail:
    lda #$00
!t4_store:
    sta tc_results + 3

    // ==========================================
    // Test 5: Gold varies with SC (SC=100 > SC=1)
    // Stats still all 10 from test 4
    // ==========================================
    jsr seed_rng
    lda #1
    sta player_data + PL_SOCIAL_CLASS
    jsr create_calc_gold
    lda player_data + PL_GOLD_0
    sta saved_gold_lo
    lda player_data + PL_GOLD_1
    sta saved_gold_hi

    jsr seed_rng
    lda #100
    sta player_data + PL_SOCIAL_CLASS
    jsr create_calc_gold

    // SC=100 gold must be > SC=1 gold
    lda player_data + PL_GOLD_1
    cmp saved_gold_hi
    bcc !t5_fail+
    bne !t5_pass+
    lda player_data + PL_GOLD_0
    cmp saved_gold_lo
    beq !t5_fail+
    bcc !t5_fail+
!t5_pass:
    lda #$01
    jmp !t5_store+
!t5_fail:
    lda #$00
!t5_store:
    sta tc_results + 4

    // ==========================================
    // Test 6: Female +50 gold bonus
    // SC=50, all stats=10. Reseed before each call.
    // ==========================================
    lda #50
    sta player_data + PL_SOCIAL_CLASS

    // Male
    jsr seed_rng
    lda #PLF_MALE
    sta player_data + PL_FLAGS
    jsr create_calc_gold
    lda player_data + PL_GOLD_0
    sta saved_gold_lo
    lda player_data + PL_GOLD_1
    sta saved_gold_hi

    // Female (same RNG seed)
    jsr seed_rng
    lda #0
    sta player_data + PL_FLAGS
    jsr create_calc_gold

    // female_gold should == male_gold + 50
    lda saved_gold_lo
    clc
    adc #50
    sta zp_temp0
    lda saved_gold_hi
    adc #0
    sta zp_temp1

    lda player_data + PL_GOLD_0
    cmp zp_temp0
    bne !t6_fail+
    lda player_data + PL_GOLD_1
    cmp zp_temp1
    bne !t6_fail+
    lda #$01
    jmp !t6_store+
!t6_fail:
    lda #$00
!t6_store:
    sta tc_results + 5

    // ==========================================
    // Test 7: Word-wrap respects 38-char line limit
    // 80-char string with spaces → 3 lines, each <= 38 chars
    // ==========================================
    jsr player_init

    ldx #0
!t7_fill:
    lda t7_test_string,x
    sta bg_text_buf,x
    beq !t7_fill_done+
    inx
    cpx #200
    bcc !t7_fill-
!t7_fill_done:
    stx bg_text_len

    jsr bg_word_wrap

    // Line 0: non-empty + <= 38 chars
    ldy #0
!t7_s0:
    lda player_background,y
    beq !t7_l0_ok+
    iny
    cpy #39
    bcc !t7_s0-
    jmp !t7_fail+
!t7_l0_ok:
    cpy #0
    beq !t7_fail+

    // Line 1: <= 38 chars
    ldy #0
!t7_s1:
    lda player_background + 40,y
    beq !t7_l1_ok+
    iny
    cpy #39
    bcc !t7_s1-
    jmp !t7_fail+
!t7_l1_ok:

    // Line 2: <= 38 chars
    ldy #0
!t7_s2:
    lda player_background + 80,y
    beq !t7_l2_ok+
    iny
    cpy #39
    bcc !t7_s2-
    jmp !t7_fail+
!t7_l2_ok:

    lda #$01
    jmp !t7_store+
!t7_fail:
    lda #$00
!t7_store:
    sta tc_results + 6

    // ==========================================
    // Test 8: player_init clears player_background
    // ==========================================
    lda #$41
    ldx #0
!t8_fill:
    sta player_background,x
    inx
    cpx #160
    bcc !t8_fill-

    jsr player_init

    ldx #0
!t8_check:
    lda player_background,x
    bne !t8_fail+
    inx
    cpx #160
    bcc !t8_check-
    lda #$01
    jmp !t8_store+
!t8_fail:
    lda #$00
!t8_store:
    sta tc_results + 7

    jmp test_exit_trampoline

// ==========================================
// Helper: Seed RNG to deterministic values
// ==========================================
seed_rng:
    lda #$a5
    sta zp_rng_0
    lda #$3c
    sta zp_rng_1
    lda #$17
    sta zp_rng_2
    lda #$e9
    sta zp_rng_3
    rts

// ==========================================
// Test data: 80-char string for word-wrap test
// ==========================================
t7_test_string:
    .text "The quick brown fox jumps over the lazy dog and runs away to find some food now."
    .byte 0
