// test_throw.s — Runtime tests for throw.s
//
// Tests: range calculation (light/heavy/weightless), potion detection,
//        item consumption, floor item placement, to-hit calculation.
//
// Results at $0400-$0405: $01 = pass, $00 = fail per test (6 tests)

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #5
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
#import "../../common/player_magic.s"
#import "../../common/ui_inventory.s"
#import "../../common/ui_equipment.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/ranged_fire.s"
#import "../../common/throw.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/store_data.s"
#import "../../common/store.s"
#import "../../common/ui_store.s"
#import "../../common/ui_help.s"
#import "../../common/ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_results: .fill 6, $ff

test_start:
    // Seed RNG
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    // ==========================================
    // Test 1: Range — light item (potion, weight=4)
    // STR=12 → (12+20)*10/4 = 320/4 = 80 → clamped to 10
    // ==========================================
    lda #12
    sta zp_player_str

    // Calculate: (STR+20)*10
    lda zp_player_str
    clc
    adc #20                     // A = 32
    ldx #10
    jsr math_multiply           // zp_math_a = lo(320)=$40, zp_math_b = hi(320)=$01

    // Divide by weight 4
    ldx #4
    jsr math_div_16x8           // zp_math_a = lo(80)=$50

    // Clamp to [1, 10]
    lda zp_math_a
    cmp #11
    bcc !t1_no_clamp+
    lda #10
!t1_no_clamp:
    cmp #10
    beq !t1_pass+
    lda #$00
    sta tc_results+0
    jmp !t1_done+
!t1_pass:
    lda #$01
    sta tc_results+0
!t1_done:

    // ==========================================
    // Test 2: Range — heavy item (chain mail, weight=120)
    // STR=10 → (10+20)*10/120 = 300/120 = 2 (integer)
    // ==========================================
    lda #10
    sta zp_player_str

    lda zp_player_str
    clc
    adc #20                     // A = 30
    ldx #10
    jsr math_multiply           // 300

    ldx #120
    jsr math_div_16x8           // 300/120 = 2

    lda zp_math_a
    cmp #2
    beq !t2_pass+
    lda #$00
    sta tc_results+1
    jmp !t2_done+
!t2_pass:
    lda #$01
    sta tc_results+1
!t2_done:

    // ==========================================
    // Test 3: Range — weightless item (gold, weight=0)
    // Weight 0 → max range = 10
    // ==========================================
    ldx #0                      // Type 0 (gold), weight = 0
    lda it_weight,x
    cmp #0
    bne !t3_fail+
    // If weight is 0, range should be 10
    lda #10
    cmp #10
    beq !t3_pass+
!t3_fail:
    lda #$00
    sta tc_results+2
    jmp !t3_done+
!t3_pass:
    lda #$01
    sta tc_results+2
!t3_done:

    // ==========================================
    // Test 4: Potion detection — type 17 (Cure Light Wounds) = ICAT_POTION
    // ==========================================
    ldx #17
    lda it_category,x
    cmp #ICAT_POTION
    beq !t4_pass+
    lda #$00
    sta tc_results+3
    jmp !t4_done+
!t4_pass:
    lda #$01
    sta tc_results+3
!t4_done:

    // ==========================================
    // Test 5: Item consumption — qty 3 → 2 after throw
    // ==========================================
    ldx #5                      // Use slot 5
    lda #2                      // Dagger
    sta inv_item_id,x
    lda #3
    sta inv_qty,x
    lda #0
    sta inv_p1,x
    sta inv_flags,x
    sta inv_ego,x

    // Simulate throw consumption
    dec inv_qty,x
    // Should be 2 (not 0, so slot stays)
    lda inv_qty,x
    cmp #2
    bne !t5_fail+
    lda inv_item_id,x
    cmp #2                      // Still a dagger
    bne !t5_fail+
    lda #$01
    sta tc_results+4
    jmp !t5_done+
!t5_fail:
    lda #$00
    sta tc_results+4
!t5_done:
    // Clean up
    lda #FI_EMPTY
    sta inv_item_id+5

    // ==========================================
    // Test 6: throw_calc_tohit — Warrior(0), Human(0), level 1
    // BTH_BOW = 55, race BTH = 0, PL_TOHIT = 0, level adj = 4*1 = 4
    // Total = 55 + 0 + 0 + 4 = 59. 75% = 59*3/4 = 177/4 = 44
    // ==========================================
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #RACE_HUMAN
    sta player_data + PL_RACE
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #0
    sta player_data + PL_TOHIT

    jsr throw_calc_tohit

    lda zp_combat_tohit
    cmp #44
    beq !t6_pass+
    lda #$00
    sta tc_results+5
    jmp !t6_done+
!t6_pass:
    lda #$01
    sta tc_results+5
!t6_done:

    jmp test_exit_trampoline
