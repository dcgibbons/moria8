// test_monster_attack.s — Runtime tests for monster_attack.s
//
// Tests: mon_atk_calc_tohit, mon_atk_roll_tohit, mon_atk_ac_reduce,
//        mon_atk_apply_damage, player_death_check, poison effect,
//        paralysis effect, aggravation effect.
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
#import "../ui_help_clear.s"
#import "../ui_character.s"
#import "../stat_display.s"
#import "../player_create.s"
#import "../sound.s"
#import "../dungeon_gen.s"
#import "../dungeon_features.s"
#import "../monster.s"
#import "../tier_manager.s"
#import "../overlay.s"
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
#import "../store_data.s"
#import "../store.s"
#import "../ui_store.s"
#import "../ui_help.s"
#import "../ui_trampoline_stubs.s"

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

    // Pre-stuff keyboard buffer for -more- prompts
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

    // ==========================================
    // Test 1: mon_atk_calc_tohit type 1 (Normal), level 2
    // Base 60 + 2*3 = 66
    // ==========================================
    lda #ATK_NORMAL
    sta mat_atk_type
    lda #0                      // Creature type 0 (White harpy, level 2)
    sta mat_type2

    jsr mon_atk_calc_tohit

    lda zp_combat_tohit
    cmp #66
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // ==========================================
    // Test 2: mon_atk_calc_tohit type 14 (Poison), level 4
    // Base 5 + 4*3 = 17
    // Creature type 12 = Giant White Rat, level 4
    // ==========================================
!t2:
    lda #ATK_POISON
    sta mat_atk_type
    lda #12                     // Giant White Rat (level 4)
    sta mat_type2

    jsr mon_atk_calc_tohit

    lda zp_combat_tohit
    cmp #17
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // ==========================================
    // Test 3: mon_atk_roll_tohit high tohit vs AC 0 — high hit rate
    // tohit=60, AC=0 → should hit most of the time (>80%)
    // Run 20 trials, count hits
    // ==========================================
!t3:
    lda #60
    sta zp_combat_tohit
    lda #0
    sta zp_player_ac
    lda #20
    sta tc_loop
    lda #0
    sta tc_ok                   // Hit counter

!t3_loop:
    jsr mon_atk_roll_tohit
    bcc !t3_miss+
    inc tc_ok
!t3_miss:
    dec tc_loop
    bne !t3_loop-

    // Expect at least 16 hits out of 20 (80%)
    lda tc_ok
    cmp #16
    bcc !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // ==========================================
    // Test 4: mon_atk_ac_reduce AC=100, damage=10
    // Reduction = (100*10)/200 = 5, result = 5
    // ==========================================
!t4:
    lda #100
    sta zp_player_ac
    lda #10
    sta zp_combat_dmg

    jsr mon_atk_ac_reduce

    lda zp_combat_dmg
    cmp #5
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // ==========================================
    // Test 5: mon_atk_ac_reduce AC=10, damage=8
    // Reduction = (10*8)/200 = 0, result = 8 (no change)
    // ==========================================
!t5:
    lda #10
    sta zp_player_ac
    lda #8
    sta zp_combat_dmg

    jsr mon_atk_ac_reduce

    lda zp_combat_dmg
    cmp #8
    bne !t5_fail+
    lda #$01
    sta tc_results + 4
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 4

    // ==========================================
    // Test 6: mon_atk_apply_damage HP 20→15
    // Set player HP to 20, damage 5, verify HP=15
    // ==========================================
!t6:
    lda #20
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #5
    sta zp_combat_dmg

    jsr mon_atk_apply_damage
    bcs !t6_fail+               // Should not be dead

    lda zp_player_hp_lo
    cmp #15
    bne !t6_fail+
    lda #$01
    sta tc_results + 5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 5

    // ==========================================
    // Test 7: mon_atk_apply_damage HP→0 triggers death
    // Set HP to 3, damage 3, verify game_flags bit 0 set
    // ==========================================
!t7:
    lda #0
    sta zp_game_flags           // Clear game flags
    lda #3
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #3
    sta zp_combat_dmg

    jsr mon_atk_apply_damage
    bcc !t7_fail+               // Should be dead (carry set)

    jsr player_death_check
    lda zp_game_flags
    and #$01
    beq !t7_fail+               // Bit 0 should be set
    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // ==========================================
    // Test 8: Poison effect sets timer
    // Use creature type 2 (White Worm Mass, level 1, ATK_POISON)
    // ==========================================
!t8:
    lda #0
    sta zp_game_flags           // Reset game flags
    sta zp_eff_poison           // Clear existing poison

    lda #2                      // White Worm Mass
    sta mat_type2

    jsr mon_atk_effect_poison

    lda zp_eff_poison
    beq !t8_fail+               // Should be > 0
    lda #$01
    sta tc_results + 7
    jmp !t9+
!t8_fail:
    lda #$00
    sta tc_results + 7

    // ==========================================
    // Test 9: Paralysis effect sets timer (force fail)
    // Use creature type 8 (Floating Eye, level 2)
    // Set class=Warrior (save=18), level=1 → saving=19
    // Run multiple attempts until paralyzed (save roll is random)
    // ==========================================
!t9:
    lda #0
    sta zp_eff_paralyze
    sta zp_eff_free_act         // No free action
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #8                      // Floating Eye
    sta mat_type2

    lda #20
    sta tc_loop
!t9_loop:
    lda #0
    sta zp_eff_paralyze         // Reset each attempt
    jsr mon_atk_effect_paralyze
    lda zp_eff_paralyze
    bne !t9_pass+               // Got paralyzed
    dec tc_loop
    bne !t9_loop-
    // 20 attempts all resisted — unlikely but possible, fail
    lda #$00
    sta tc_results + 8
    jmp !t10+
!t9_pass:
    lda #$01
    sta tc_results + 8

    // ==========================================
    // Test 10: Aggravation wakes sleeping monsters
    // Spawn 3 monsters (asleep), call mon_atk_effect_aggravate,
    // check all have MF_AWAKE set
    // ==========================================
!t10:
    lda #0
    sta zp_game_flags
    jsr monster_init_table

    // Place player at (5,5) so spawn positions don't conflict
    lda #5
    sta zp_player_x
    sta zp_player_y

    // Manually create 3 monsters (asleep)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #4                      // Kobold
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0                      // Asleep
    sta (zp_ptr0),y
    ldy #MX_X
    lda #10
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #10
    sta (zp_ptr0),y

    ldx #1
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #9                      // Jackal
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0                      // Asleep
    sta (zp_ptr0),y
    ldy #MX_X
    lda #20
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #20
    sta (zp_ptr0),y

    ldx #2
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #1                      // Giant White Mouse
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0                      // Asleep
    sta (zp_ptr0),y
    ldy #MX_X
    lda #30
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #30
    sta (zp_ptr0),y

    jsr mon_atk_effect_aggravate

    // Check all 3 have MF_AWAKE
    lda #1
    sta tc_ok

    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    bne !t10_c1+
    lda #0
    sta tc_ok
!t10_c1:
    ldx #1
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    bne !t10_c2+
    lda #0
    sta tc_ok
!t10_c2:
    ldx #2
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    bne !t10_c3+
    lda #0
    sta tc_ok
!t10_c3:
    lda tc_ok
    sta tc_results + 9

!tests_done:
    jmp test_exit_trampoline
