// test_effects.s — Runtime tests for Phase 5.5: Player Status Effects
//
// Tests: turn_tick_regen, confused movement, starvation damage,
//        poison expiration, blindness visibility skip.
//
// Results at $0400-$0409: $01 = pass, $00 = fail per test
// NOTE: msg_print writes to screen row 0 ($0400+), so we store results
// in tc_results[] and copy to $0400 at the very end.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"

.encoding "screencode_upper"

#import "../zeropage.s"
#import "../memory.s"
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
#import "../monster_ai.s"
#import "../monster_magic.s"
#import "../item.s"
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
#import "../ui_help.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_loop:    .byte 0
tc_ok:      .byte 0
tc_results: .fill 14, $ff      // Result buffer (copied to $0400 at end)

test_start:
    // Bank out BASIC ROM (needed for $A000 area used by BFS)
    :BankOutBasic()

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

    // Clear all effect timers
    lda #0
    sta zp_eff_poison
    sta zp_eff_blind
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta zp_eff_regen
    sta zp_game_flags

    // Set reasonable player stats for testing
    lda #10
    sta player_data + PL_CON_CUR    // CON 10
    sta zp_player_con

    // ==========================================
    // Test 1: Regen counter decrements each turn tick
    // Set counter=5, call turn_tick_regen 4x, verify counter=1
    // ==========================================
    lda #5
    sta zp_regen_counter

    // Set HP below max so regen is active
    lda #10
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #20
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi

    // No poison, no extra regen
    lda #0
    sta zp_eff_poison
    sta zp_eff_regen

    jsr turn_tick_regen     // 5 → 4
    jsr turn_tick_regen     // 4 → 3
    jsr turn_tick_regen     // 3 → 2
    jsr turn_tick_regen     // 2 → 1

    lda zp_regen_counter
    cmp #1
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // ==========================================
    // Test 2: Regen heals 1 HP when counter expires
    // Set HP=10, max=20, counter=1, tick → HP=11
    // ==========================================
!t2:
    lda #10
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #20
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi
    lda #1
    sta zp_regen_counter
    lda #0
    sta zp_eff_poison
    sta zp_eff_regen

    jsr turn_tick_regen

    lda zp_player_hp_lo
    cmp #11
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // ==========================================
    // Test 3: Regen capped at max HP
    // Set HP=max, counter=1, tick → HP unchanged
    // ==========================================
!t3:
    lda #20
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #20
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi
    lda #1
    sta zp_regen_counter
    lda #0
    sta zp_eff_poison
    sta zp_eff_regen

    jsr turn_tick_regen

    lda zp_player_hp_lo
    cmp #20
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // ==========================================
    // Test 4: Poison suppresses regen
    // Set poison>0, counter=1, tick → HP unchanged, counter unchanged
    // ==========================================
!t4:
    lda #10
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #20
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi
    lda #1
    sta zp_regen_counter
    lda #5
    sta zp_eff_poison          // Poisoned!
    lda #0
    sta zp_eff_regen

    jsr turn_tick_regen

    // HP should still be 10 (no regen while poisoned)
    lda zp_player_hp_lo
    cmp #10
    bne !t4_fail+
    // Counter should still be 1 (not decremented)
    lda zp_regen_counter
    cmp #1
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // ==========================================
    // Test 5: Extra regen doubles tick rate
    // Set zp_eff_regen>0, counter=3, tick → counter=1 (decremented by 2)
    // ==========================================
!t5:
    lda #10
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #20
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi
    lda #3
    sta zp_regen_counter
    lda #0
    sta zp_eff_poison
    lda #10
    sta zp_eff_regen           // Extra regen active!

    jsr turn_tick_regen

    lda zp_regen_counter
    cmp #1
    bne !t5_fail+
    lda #$01
    sta tc_results + 4
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 4

    // ==========================================
    // Test 6: Confusion randomizes direction
    // Set confuse>0, call player_try_move 20x with CMD_MOVE_N,
    // count how many times player actually went north.
    // If confused, should NOT always go north (statistically).
    // ==========================================
!t6:
    // Set up a walkable area around the player
    // Player at (20, 20), fill surrounding 5x5 with floor
    lda #20
    sta zp_player_x
    sta zp_player_y
    sta player_data + PL_MAP_X
    sta player_data + PL_MAP_Y

    // Fill a 7x7 block around (20,20) with floor tiles (+ FLAG_LIT)
    ldx #17
!t6_fill_y:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #17
!t6_fill_x:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #24
    bcc !t6_fill_x-
    inx
    cpx #24
    bcc !t6_fill_y-

    lda #10
    sta zp_eff_confuse         // Confused!
    lda #$ff
    sta zp_run_dir             // Not running

    // Player HP high so death check doesn't trigger
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Count moves that result in position change
    lda #0
    sta tc_ok                  // Count of moves that didn't go north

    lda #20
    sta tc_loop                // 20 iterations
!t6_loop:
    // Reset player to center
    lda #20
    sta zp_player_x
    sta zp_player_y
    sta player_data + PL_MAP_X
    sta player_data + PL_MAP_Y

    // Try to move north (CMD_MOVE_N = $01)
    lda #CMD_MOVE_N
    jsr player_try_move

    // Check if player actually went north (y would be 19)
    lda zp_player_y
    cmp #19
    beq !t6_went_north+
    // Didn't go north — confusion worked!
    inc tc_ok
!t6_went_north:

    dec tc_loop
    bne !t6_loop-

    // If confused, at least some moves should NOT have been north
    // With 20 tries and 8 possible directions, probability of all north = (1/8)^20 ≈ 0
    lda tc_ok
    beq !t6_fail+              // All went north → confusion didn't work
    lda #$01
    sta tc_results + 5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 5

    // ==========================================
    // Test 7: Starvation deals damage
    // Set food=0, call turn_tick_hunger, verify HP decreased
    // ==========================================
!t7:
    lda #0
    sta zp_eff_confuse         // Clear confusion
    lda #50
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    sta zp_player_food
    sta zp_player_food_hi
    sta zp_game_flags

    jsr turn_tick_hunger

    lda zp_player_hp_lo
    cmp #49
    bne !t7_fail+
    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // ==========================================
    // Test 8: Starvation can kill
    // Set food=0, HP=1, call turn_tick_hunger, verify GF_DEAD
    // ==========================================
!t8:
    lda #1
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    sta zp_player_food
    sta zp_player_food_hi
    sta zp_game_flags

    jsr turn_tick_hunger

    lda zp_game_flags
    and #$01                   // GF_DEAD bit
    beq !t8_fail+
    lda #$01
    sta tc_results + 7
    jmp !t9+
!t8_fail:
    lda #$00
    sta tc_results + 7

    // ==========================================
    // Test 9: Poison expiration resets timer and prints message
    // Set poison=1, tick → poison=0
    // ==========================================
!t9:
    // Clear death flag
    lda #0
    sta zp_game_flags

    // Refill keyboard buffer for -more- prompts
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

    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #1
    sta zp_eff_poison

    jsr turn_tick_effects

    // Poison should now be 0 (expired)
    lda zp_eff_poison
    bne !t9_fail+
    // HP should NOT have decreased (damage only when timer > 0 after dec)
    lda zp_player_hp_lo
    cmp #200
    bne !t9_fail+
    lda #$01
    sta tc_results + 8
    jmp !t10+
!t9_fail:
    lda #$00
    sta tc_results + 8

    // ==========================================
    // Test 10: Blindness skips visibility
    // Set blind>0, call update_visibility, verify no new FLAG_VISITED
    // ==========================================
!t10:
    // Set up: player at (20,20), dlvl=1 (dungeon)
    lda #1
    sta zp_player_dlvl
    lda #20
    sta zp_player_x
    sta zp_player_y
    lda #1
    sta zp_light_radius

    // Clear FLAG_VISITED from player tile
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    lda (zp_ptr0),y
    and #~FLAG_VISITED
    sta (zp_ptr0),y

    // Set blindness
    lda #5
    sta zp_eff_blind

    jsr update_visibility

    // Check that player tile still does NOT have FLAG_VISITED
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    lda (zp_ptr0),y
    and #FLAG_VISITED
    bne !t10_fail+             // FLAG_VISITED set → blindness didn't block
    lda #$01
    sta tc_results + 9
    jmp !t11+
!t10_fail:
    lda #$00
    sta tc_results + 9

    // ==========================================
    // Test 11: Mage mana regen — MP increases after even turn
    // Set PL_SPELL_TYPE=1 (mage), MP=5, MMP=20, even turn, no extra regen
    // ==========================================
!t11:
    // Clear all effects so other timers don't fire
    lda #0
    sta zp_eff_poison
    sta zp_eff_blind
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta zp_eff_speed
    sta zp_eff_protect
    sta zp_eff_invis
    sta zp_eff_infra
    sta zp_eff_bless
    sta zp_eff_hero
    sta zp_eff_regen
    sta zp_eff_word_recall

    lda #1
    sta player_data + PL_SPELL_TYPE  // Mage
    lda #5
    sta zp_player_mp
    sta player_data + PL_MANA
    lda #20
    sta zp_player_mmp
    lda #0
    sta zp_turn_lo                   // Even turn
    sta zp_eff_regen                 // No extra regen

    jsr turn_tick_effects

    lda zp_player_mp
    cmp #6
    bne !t11_fail+
    lda #$01
    sta tc_results + 10
    jmp !t12+
!t11_fail:
    lda #$00
    sta tc_results + 10

    // ==========================================
    // Test 12: Warrior no mana regen
    // Set PL_SPELL_TYPE=0, MP=5, MMP=20, even turn
    // ==========================================
!t12:
    // Clear all effects
    lda #0
    sta zp_eff_poison
    sta zp_eff_blind
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta zp_eff_speed
    sta zp_eff_protect
    sta zp_eff_invis
    sta zp_eff_infra
    sta zp_eff_bless
    sta zp_eff_hero
    sta zp_eff_regen
    sta zp_eff_word_recall

    lda #0
    sta player_data + PL_SPELL_TYPE  // Warrior (no magic)
    lda #5
    sta zp_player_mp
    sta player_data + PL_MANA
    lda #20
    sta zp_player_mmp
    lda #0
    sta zp_turn_lo                   // Even turn

    jsr turn_tick_effects

    lda zp_player_mp
    cmp #5
    bne !t12_fail+
    lda #$01
    sta tc_results + 11
    jmp !t13+
!t12_fail:
    lda #$00
    sta tc_results + 11

    // ==========================================
    // Test 13: Recall from dungeon to town
    // Set dlvl=3, PL_MAX_DLVL=3, recall timer=1 → fires, dlvl becomes 0
    // ==========================================
!t13:
    // Refill keyboard buffer for -more- prompts
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

    // Set player in dungeon at dlvl 3
    lda #3
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    sta player_data + PL_MAX_DLVL

    // Place player at (10,10) with floor tile
    lda #10
    sta zp_player_x
    sta zp_player_y
    sta player_data + PL_MAP_X
    sta player_data + PL_MAP_Y
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Clear all effects except recall
    lda #0
    sta zp_eff_poison
    sta zp_eff_blind
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta zp_eff_speed
    sta zp_eff_protect
    sta zp_eff_invis
    sta zp_eff_infra
    sta zp_eff_bless
    sta zp_eff_hero
    sta zp_eff_regen
    sta zp_game_flags

    // Set recall timer to 1 (will fire this tick)
    lda #1
    sta zp_eff_word_recall

    // Set spell type so mana regen doesn't crash
    lda #0
    sta player_data + PL_SPELL_TYPE

    // HP high so death check doesn't trigger
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    jsr turn_tick_effects

    // Verify we're now at town (dlvl 0)
    lda zp_player_dlvl
    cmp #0
    bne !t13_fail+
    lda #$01
    sta tc_results + 12
    jmp !t14+
!t13_fail:
    lda #$00
    sta tc_results + 12

    // ==========================================
    // Test 14: Recall from town to dungeon
    // Set dlvl=0, PL_MAX_DLVL=5, recall timer=1 → fires, dlvl becomes 5
    // ==========================================
!t14:
    // Refill keyboard buffer for -more- prompts
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

    // Set player in town at dlvl 0
    lda #0
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    lda #5
    sta player_data + PL_MAX_DLVL

    // Place player at (10,10) with floor tile
    lda #10
    sta zp_player_x
    sta zp_player_y
    sta player_data + PL_MAP_X
    sta player_data + PL_MAP_Y
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Clear all effects except recall
    lda #0
    sta zp_eff_poison
    sta zp_eff_blind
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta zp_eff_speed
    sta zp_eff_protect
    sta zp_eff_invis
    sta zp_eff_infra
    sta zp_eff_bless
    sta zp_eff_hero
    sta zp_eff_regen
    sta zp_game_flags

    // Set recall timer to 1 (will fire this tick)
    lda #1
    sta zp_eff_word_recall

    // Set spell type so mana regen doesn't crash
    lda #0
    sta player_data + PL_SPELL_TYPE

    // HP high so death check doesn't trigger
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    jsr turn_tick_effects

    // Verify we're now at dlvl 5
    lda zp_player_dlvl
    cmp #5
    bne !t14_fail+
    lda #$01
    sta tc_results + 13
    jmp !tests_done+
!t14_fail:
    lda #$00
    sta tc_results + 13

!tests_done:
    // Copy results from tc_results to $0400 (screen row 0)
    ldx #13
!copy_results:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy_results-

    brk
