// test_combat.s — Runtime tests for combat.s
//
// Tests: combat_calc_tohit, combat_calc_blows, combat_roll_damage,
//        combat_apply_damage, combat_award_xp, combat_check_levelup,
//        msg_build_combat.
//
// Results at $0400-$0409: $01 = pass, $00 = fail per test
// NOTE: msg_print writes to screen row 0 ($0400+), so we store results
// in tc_results[] and copy to $0400 at the very end.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

// Exit trampoline at $080E — banks out BASIC, copies results, breaks.
// MUST be in "Test Code" segment so run_tests.sh sets breakpoint here (below $A000).
.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #9
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
#import "../monster_attack.s"
#import "../turn.s"
#import "../store.s"
#import "../ui_store.s"
#import "../ui_help.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_loop:    .byte 0
tc_ok:      .byte 0
tc_results: .fill 10, $ff      // Result buffer (copied to $0400 at end)

test_start:
    // Seed RNG deterministically
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    // Initialize message system
    jsr msg_init

    // Initialize sound (needed to avoid crash on sound_play)
    jsr sound_init

    // ==========================================
    // Test 1: combat_calc_tohit for Warrior level 1, TOHIT=0
    // Expected: class_bth(70) + TOHIT*3(0) + level*bth_per_level(1*4) = 74
    // ==========================================
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #0
    sta player_data + PL_TOHIT

    jsr combat_calc_tohit

    lda zp_combat_tohit
    cmp #74
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // ==========================================
    // Test 2: combat_calc_tohit with PL_TOHIT=2
    // Expected: 70 + 2*3(6) + 1*4 = 80
    // ==========================================
!t2:
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #2
    sta player_data + PL_TOHIT

    jsr combat_calc_tohit

    lda zp_combat_tohit
    cmp #80
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // ==========================================
    // Test 3: combat_calc_blows with DEX 12 (unarmed)
    // DEX 12 → bracket 1 → blows_table[16+1] = 2
    // ==========================================
!t3:
    lda #12
    sta player_data + PL_DEX_CUR

    jsr combat_calc_blows

    lda zp_combat_blows
    cmp #2
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // ==========================================
    // Test 4: combat_calc_blows with DEX 18 (unarmed)
    // DEX 18 → bracket 3 → blows_table[16+3] = 4
    // ==========================================
!t4:
    lda #18
    sta player_data + PL_DEX_CUR

    jsr combat_calc_blows

    lda zp_combat_blows
    cmp #4
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // ==========================================
    // Test 5: combat_roll_damage returns values in [1,2] range
    // Run 20 times, all must be in range
    // ==========================================
!t5:
    lda #0
    sta player_data + PL_TODMG  // No damage bonus
    lda #20
    sta tc_loop
    lda #1
    sta tc_ok

!t5_loop:
    jsr combat_roll_damage
    lda cmb_damage
    cmp #1
    bcc !t5_bad+                // < 1
    cmp #3
    bcs !t5_bad+                // >= 3
    jmp !t5_next+
!t5_bad:
    lda #0
    sta tc_ok
!t5_next:
    dec tc_loop
    bne !t5_loop-

    lda tc_ok
    sta tc_results + 4

    // ==========================================
    // Test 6: combat_apply_damage kills at HP=0
    // Set monster HP to 3, apply 3 damage → dead (carry set)
    // ==========================================
!t6:
    jsr monster_init_table

    // Manually create a monster in slot 0
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #4                      // Kobold
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #3
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y

    ldx #0
    lda #3                      // 3 damage
    jsr combat_apply_damage
    bcs !t6_pass+
    lda #$00
    sta tc_results + 5
    jmp !t7+
!t6_pass:
    lda #$01
    sta tc_results + 5

    // ==========================================
    // Test 7: combat_apply_damage alive when HP > 0
    // Set monster HP to 5, apply 2 damage → alive (carry clear), HP = 3
    // ==========================================
!t7:
    jsr monster_init_table

    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #4                      // Kobold
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #5
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y

    ldx #0
    lda #2                      // 2 damage
    jsr combat_apply_damage
    bcc !t7_alive+
    lda #$00
    sta tc_results + 6
    jmp !t8+
!t7_alive:
    // Check HP = 3
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #3
    bne !t7_fail+
    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // ==========================================
    // Test 8: combat_award_xp adds correct XP
    // Kobold (type 4): cr_xp=5, cr_level=1, player_level=1
    // XP = (5*1)/1 = 5
    // ==========================================
!t8:
    // Clear player XP
    lda #0
    sta player_data + PL_XP_0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2

    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #4                      // Kobold
    sta cmb_type

    jsr combat_award_xp

    lda player_data + PL_XP_0
    cmp #5
    bne !t8_fail+
    lda player_data + PL_XP_1
    bne !t8_fail+               // Should be 0
    lda #$01
    sta tc_results + 7
    jmp !t9+
!t8_fail:
    lda #$00
    sta tc_results + 7

    // ==========================================
    // Test 9: combat_check_levelup triggers at threshold
    // XP threshold for level 1→2 is 10. Set XP=10, level=1.
    // ==========================================
!t9:
    // Pre-stuff keyboard buffer for -more- prompt from levelup message
    lda #8
    sta $c6
    lda #$20
    sta $0277
    sta $0278
    sta $0279
    sta $027a
    sta $027b
    sta $027c
    sta $027d
    sta $027e

    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    // Set base stats for HP calc
    lda #12
    sta player_data + PL_STR_CUR
    sta player_data + PL_DEX_CUR
    sta player_data + PL_CON_CUR

    lda #10
    sta player_data + PL_XP_0
    lda #0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2

    jsr combat_check_levelup

    lda zp_player_lvl
    cmp #2
    bne !t9_fail+
    lda #$01
    sta tc_results + 8
    jmp !t10+
!t9_fail:
    lda #$00
    sta tc_results + 8

    // ==========================================
    // Test 10: msg_build_hit produces correct string
    // msg_build_hit with cmb_type=4 (Kobold)
    // Expected: "YOU HIT THE KOBOLD."
    // ==========================================
!t10:
    lda #4
    sta cmb_type

    jsr msg_build_hit

    // Check: "YOU HIT THE KOBOLD."
    // Y(19) O(0f) U(15) ' '(20) H(08) I(09) T(14) ' '(20) T(14) H(08) E(05) ' '(20)
    // K(0b) O(0f) B(02) O(0f) L(0c) D(04) .(2e) null(00)
    lda combat_msg_buf + 0
    cmp #$19                    // 'Y'
    bne !t10_fail+
    lda combat_msg_buf + 1
    cmp #$0f                    // 'O'
    bne !t10_fail+
    lda combat_msg_buf + 2
    cmp #$15                    // 'U'
    bne !t10_fail+
    lda combat_msg_buf + 3
    cmp #$20                    // ' '
    bne !t10_fail+
    lda combat_msg_buf + 4
    cmp #$08                    // 'H'
    bne !t10_fail+
    lda combat_msg_buf + 5
    cmp #$09                    // 'I'
    bne !t10_fail+
    lda combat_msg_buf + 6
    cmp #$14                    // 'T'
    bne !t10_fail+
    // Check "KOBOLD." at offset 12
    lda combat_msg_buf + 12
    cmp #$0b                    // 'K'
    bne !t10_fail+
    lda combat_msg_buf + 18
    cmp #$2e                    // '.'
    bne !t10_fail+
    lda combat_msg_buf + 19
    cmp #$00                    // null
    bne !t10_fail+

    lda #$01
    sta tc_results + 9
    jmp !tests_done+

!t10_fail:
    lda #$00
    sta tc_results + 9

!tests_done:
    jmp test_exit_trampoline
