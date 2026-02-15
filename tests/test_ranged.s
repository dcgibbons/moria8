// test_ranged.s — Runtime tests for ranged_fire.s
//
// Tests: item_get_missile, ammo matching, ammo depletion,
//        melee unarmed fallback with bow, ranged_fire validation.
//
// Results at $0400-$0407: $01 = pass, $00 = fail per test (8 tests)

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #7
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
#import "../ranged_fire.s"
#import "../monster_attack.s"
#import "../turn.s"
#import "../store.s"
#import "../ui_store.s"
#import "../ui_help.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_results: .fill 8, $ff
tr_save: .byte 0

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
    // Test 1: item_get_missile(49) = 1 (Short Bow)
    // ==========================================
    ldx #49
    jsr item_get_missile
    cmp #1
    beq !t1_pass+
    lda #$00
    sta tc_results+0
    jmp !t1_done+
!t1_pass:
    lda #$01
    sta tc_results+0
!t1_done:

    // ==========================================
    // Test 2: item_get_missile(52) = $81 (Arrow)
    // ==========================================
    ldx #52
    jsr item_get_missile
    cmp #$81
    beq !t2_pass+
    lda #$00
    sta tc_results+1
    jmp !t2_done+
!t2_pass:
    lda #$01
    sta tc_results+1
!t2_done:

    // ==========================================
    // Test 3: item_get_missile(1) = 0 (Dagger, not ranged)
    // ==========================================
    ldx #1
    jsr item_get_missile
    cmp #0
    beq !t3_pass+
    lda #$00
    sta tc_results+2
    jmp !t3_done+
!t3_pass:
    lda #$01
    sta tc_results+2
!t3_done:

    // ==========================================
    // Test 4: Crossbow(50)→2, Bolt(53)→$82, Sling(51)→3, Rock(54)→$83
    // ==========================================
    ldx #50
    jsr item_get_missile
    cmp #2
    bne !t4_fail+
    ldx #53
    jsr item_get_missile
    cmp #$82
    bne !t4_fail+
    ldx #51
    jsr item_get_missile
    cmp #3
    bne !t4_fail+
    ldx #54
    jsr item_get_missile
    cmp #$83
    bne !t4_fail+
    lda #$01
    sta tc_results+3
    jmp !t4_done+
!t4_fail:
    lda #$00
    sta tc_results+3
!t4_done:

    // ==========================================
    // Test 5: Ammo matching — bow ammo_type matches arrow type
    // bow it_missile=1, arrow it_missile=$81, ($81 & $7f) == 1
    // ==========================================
    ldx #49
    jsr item_get_missile
    sta tr_save               // 1 (bow ammo type)
    ldx #52
    jsr item_get_missile
    and #$7f                  // Strip high bit → 1
    cmp tr_save
    beq !t5_pass+
    lda #$00
    sta tc_results+4
    jmp !t5_done+
!t5_pass:
    lda #$01
    sta tc_results+4
!t5_done:

    // ==========================================
    // Test 6: Ammo depletion — qty 1 → 0 clears slot
    // ==========================================
    ldx #3
    lda #52                   // Arrow
    sta inv_item_id,x
    lda #1
    sta inv_qty,x
    // Simulate consumption
    dec inv_qty,x
    bne !t6_nz+
    lda #FI_EMPTY
    sta inv_item_id,x
!t6_nz:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !t6_pass+
    lda #$00
    sta tc_results+5
    jmp !t6_done+
!t6_pass:
    lda #$01
    sta tc_results+5
!t6_done:

    // ==========================================
    // Test 7: No weapon → ranged_fire returns carry clear
    // ==========================================
    jsr msg_init
    ldx #EQUIP_WEAPON
    lda #FI_EMPTY
    sta inv_item_id,x
    jsr ranged_fire
    bcc !t7_pass+
    lda #$00
    sta tc_results+6
    jmp !t7_done+
!t7_pass:
    lda #$01
    sta tc_results+6
!t7_done:

    // ==========================================
    // Test 8: Melee with bow → combat_roll_damage uses 1d2
    // (not 0d0 from bow). Run 10 trials, all should be 1-2.
    // ==========================================
    ldx #EQUIP_WEAPON
    lda #49                   // Short Bow
    sta inv_item_id,x
    lda #1
    sta inv_qty,x
    lda #0
    sta player_data + PL_TODMG

    lda #10
    sta tr_save
!t8_loop:
    jsr combat_roll_damage
    lda zp_math_a
    beq !t8_fail+             // 0 means 0d0 (bow dice), wrong
    cmp #3
    bcs !t8_fail+             // 3+ impossible for 1d2
    dec tr_save
    bne !t8_loop-
    lda #$01
    sta tc_results+7
    jmp !t8_done+
!t8_fail:
    lda #$00
    sta tc_results+7
!t8_done:

    jmp test_exit_trampoline
