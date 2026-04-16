// test_effects.s — Runtime tests for Phase 5.5: Player Status Effects
//
// Tests: turn_tick_regen, confused movement, starvation damage,
//        poison expiration, blindness visibility skip.
//
// Results at $0400+$: $01 = pass, $00 = fail per test
// NOTE: msg_print writes to screen row 0 ($0400+), so we store results
// in tc_results[] and copy to $0400 at the very end.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"

.encoding "screencode_mixed"

// Bootstrap + exit trampoline must stay in "Test Code" so run_tests.sh
// breaks at the BRK below rather than at the end of the imported body.
test_bootstrap:
    :BankOutBasic()
    jmp test_start

// test_finish — Copy results to $0400 and halt.
test_finish:
    sei
    :BankOutBasic()
    ldx #39
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0830 "Main"

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
#import "../../common/ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_loop:    .byte 0
tc_ok:      .byte 0
tc_results: .fill 40, $ff      // Result buffer (copied to $0400 at end)
tv_step_idx: .byte 0
tv_row_idx: .byte 0
tv_prev_x:  .byte 0
tv_prev_y:  .byte 0
tlk_expected_n: .text "n"
tlk_expected_c: .text "c"
tlk_expected_t: .text "t"
tlk_expected_w: .text "w"
tlk_expected_g: .text "G"
tlk_flash_calls: .byte 0
tlk_flash_row:   .byte 0
tlk_flash_col:   .byte 0
tpm_spell_exec_calls: .byte 0
tpm_huff_calls:   .byte 0
tpm_last_huff_id: .byte 0
tpm_cast_loop_ctr: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_input_wait_release:
    rts

test_get_direction_target_east:
    lda zp_player_x
    clc
    adc #1
    sta df_target_x
    lda zp_player_y
    sta df_target_y
    sec
    rts

test_screen_flash_at:
    stx tlk_flash_row
    sty tlk_flash_col
    inc tlk_flash_calls
    rts

test_input_get_key_qmark:
    lda #$3f
    rts

test_input_get_key_a:
    lda #$41
    rts

test_input_get_modal_spell_a:
    lda #$41
    rts

test_tramp_spell_execute_selected:
    inc tpm_spell_exec_calls
    rts

test_huff_print_msg:
    stx tpm_last_huff_id
    inc tpm_huff_calls
    rts

test_pm_select_book:
    lda #0
    sta pm_book_idx
    lda #<book_mask_0
    sta pm_book_mask_lo
    lda #>book_mask_0
    sta pm_book_mask_hi
    sec
    rts

test_pm_pick_visible_spell:
    lda #0
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_start:
    :PatchJump(input_wait_release, test_input_wait_release)

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
    ldx #7
    lda #$20
!seed_keys:
    sta $0277,x
    dex
    bpl !seed_keys-

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
    jmp !t15+
!t14_fail:
    lda #$00
    sta tc_results + 13

    // ==========================================
    // Test 15: Hunger penalty increases spell failure value
    // Set up mage tables, high level player, spell 0: base clamps to 5
    // Set HUNGER_FAINT → +20 penalty → pm_fail_work >= 25
    // ==========================================
!t15:
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

    // Clear death flag
    lda #0
    sta zp_game_flags

    // Set up mage spell tables
    lda #SPELL_MAGE
    sta pm_spell_type
    lda #<mage_spell_fail
    sta pm_fail_tbl_lo
    lda #>mage_spell_fail
    sta pm_fail_tbl_hi
    lda #<mage_spell_level
    sta pm_lvl_tbl_lo
    lda #>mage_spell_level
    sta pm_lvl_tbl_hi
    lda #0
    sta pm_spell_idx                 // Spell 0: fail_base=22, level=1

    // High level player so base failure clamps to 5
    lda #10
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR     // High INT → bonus=3, still clamps to 5

    // Set hunger to FAINT
    lda #HUNGER_FAINT
    sta zp_hunger_state

    jsr calc_spell_failure

    // pm_fail_work should be >= 25 (5 base + 20 hunger penalty)
    lda pm_fail_work
    cmp #25
    bcc !t15_fail+
    lda #$01
    sta tc_results + 14
    jmp !t16+
!t15_fail:
    lda #$00
    sta tc_results + 14

    // ==========================================
    // Test 16: No hunger penalty at HUNGER_FULL
    // Same setup but HUNGER_FULL → pm_fail_work == 5 (minimum, no penalty)
    // ==========================================
!t16:
    // Same table setup as test 15 (already set)
    lda #0
    sta pm_spell_idx
    lda #10
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR

    // Set hunger to FULL
    lda #HUNGER_FULL
    sta zp_hunger_state

    jsr calc_spell_failure

    // pm_fail_work should be exactly 5 (minimum, no penalty)
    lda pm_fail_work
    cmp #5
    bne !t16_fail+
    lda #$01
    sta tc_results + 15
    jmp !t17+
!t16_fail:
    lda #$00
    sta tc_results + 15

    // ==========================================
    // Test 17: count_spells_known returns correct count
    // Set PL_SPELLS_KNOWN=$07 (3 spells), PL_SPELLS_KNOWN_HI=$01 (1 spell)
    // Expected: A == 4
    // ==========================================
!t17:
    lda #$07
    sta player_data + PL_SPELLS_KNOWN
    lda #$01
    sta player_data + PL_SPELLS_KNOWN_HI

    jsr count_spells_known

    cmp #4
    bne !t17_fail+
    lda #$01
    sta tc_results + 16
    jmp !t18+
!t17_fail:
    lda #$00
    sta tc_results + 16

    // ==========================================
    // Test 18: Blindness blocks scroll reading (turn not consumed)
    // Set zp_eff_blind=5, call item_read_scroll, verify carry clear
    // ==========================================
!t18:
    lda #5
    sta zp_eff_blind

    jsr item_read_scroll

    // Carry should be clear (no turn consumed)
    bcs !t18_fail+
    lda #$01
    sta tc_results + 17
    jmp !t19+
!t18_fail:
    lda #$00
    sta tc_results + 17

    // ==========================================
    // Test 19: Validated spell cast consumes mana
    // Set up spell 0 (Magic Missile), validate it, then consume mana.
    // ==========================================
!t19:
    // Clear death flag, clear blindness/confusion
    lda #0
    sta zp_game_flags
    sta zp_eff_blind
    sta zp_eff_confuse

    // Set up as mage
    lda #SPELL_MAGE
    sta pm_spell_type
    sta player_data + PL_SPELL_TYPE
    lda #0
    sta pm_spell_idx

    // Set up mage table pointers
    lda #<mage_spell_mana
    sta pm_mana_tbl_lo
    lda #>mage_spell_mana
    sta pm_mana_tbl_hi
    lda #<mage_spell_level
    sta pm_lvl_tbl_lo
    lda #>mage_spell_level
    sta pm_lvl_tbl_hi
    lda #<mage_spell_fail
    sta pm_fail_tbl_lo
    lda #>mage_spell_fail
    sta pm_fail_tbl_hi
    lda #<mage_spell_name_lo
    sta pm_name_lo_lo
    lda #>mage_spell_name_lo
    sta pm_name_lo_hi
    lda #<mage_spell_name_hi
    sta pm_name_hi_lo
    lda #>mage_spell_name_hi
    sta pm_name_hi_hi

    // Mana=50, level high enough to validate spell 0
    lda #50
    sta zp_player_mp
    sta player_data + PL_MANA
    lda #50
    sta zp_player_mmp
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #10
    sta zp_eff_confuse
    lda #18
    sta player_data + PL_INT_CUR

    // HP high so monster effects don't kill
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    jsr pm_validate_selected_spell
    bcc !t19_fail+
    jsr pm_consume_mana

    // Mana should have decreased (Magic Missile costs 1)
    lda zp_player_mp
    cmp #50
    bcs !t19_fail+                   // Mana didn't decrease → bug
    lda #$01
    sta tc_results + 18
    jmp !t20+
!t19_fail:
    lda #$00
    sta tc_results + 18

    // ==========================================
    // Test 20: Extra regen on odd turn increases mana
    // Set zp_eff_regen=5, zp_turn_lo=1 (odd), mage MP=5/20
    // Extra regen bypasses even-turn check → MP should become 6
    // ==========================================
!t20:
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
    sta zp_eff_word_recall
    sta zp_game_flags

    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #5
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_eff_regen                 // Extra regen active!
    lda #20
    sta zp_player_mmp
    lda #1
    sta zp_turn_lo                   // Odd turn

    jsr turn_tick_effects

    lda zp_player_mp
    cmp #6
    bne !t20_fail+
    lda #$01
    sta tc_results + 19
    jmp !t21+
!t20_fail:
    lda #$00
    sta tc_results + 19

    // ==========================================
    // Test 21: Word of Recall fizzle (town, never visited dungeon)
    // Set dlvl=0, PL_MAX_DLVL=0, recall timer=1 → fizzle, dlvl stays 0
    // ==========================================
!t21:
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

    // Set player in town, never been to dungeon
    lda #0
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    sta player_data + PL_MAX_DLVL    // Never visited dungeon

    // Set recall timer to 1 (will fire this tick)
    lda #1
    sta zp_eff_word_recall

    // Warrior so mana regen doesn't interfere
    lda #0
    sta player_data + PL_SPELL_TYPE

    // HP high so death check doesn't trigger
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Place player at (10,10) with floor tile
    lda #10
    sta zp_player_x
    sta zp_player_y
    sta player_data + PL_MAP_X
    sta player_data + PL_MAP_Y

    jsr turn_tick_effects

    // dlvl should still be 0 (recall fizzled)
    lda zp_player_dlvl
    bne !t21_fail+
    lda #$01
    sta tc_results + 20
    jmp !t22+
!t21_fail:
    lda #$00
    sta tc_results + 20

    // ==========================================
    // Test 22: Visibility room cache sets in lit room and clears in corridor
    // ==========================================
!t22:
    jsr fill_map_rock

    lda #1
    sta zp_player_dlvl
    sta room_count
    lda #20
    sta room_x
    sta dg_room_x
    lda #10
    sta room_y
    sta dg_room_y
    lda #5
    sta room_w
    sta dg_room_w
    lda #3
    sta room_h
    sta dg_room_h
    lda #1
    sta room_lit
    lda #0
    sta zp_eff_blind
    lda #1
    sta zp_light_radius
    lda #$ff
    sta vis_cached_room_idx
    jsr draw_dungeon_room

    lda #20
    sta zp_player_x
    lda #10
    sta zp_player_y
    jsr update_visibility
    lda vis_cached_room_idx
    cmp #0
    bne !t22_fail+

    lda #30
    sta zp_player_x
    lda #10
    sta zp_player_y
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #30
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    jsr update_visibility
    lda vis_cached_room_idx
    cmp #$ff
    bne !t22_fail+

    lda #$01
    sta tc_results + 21
    jmp !t23+
!t22_fail:
    lda #$00
    sta tc_results + 21

    // ==========================================
    // Test 23: Room bounds include perimeter walls only
    // ==========================================
!t23:
    lda #20
    sta room_x
    lda #10
    sta room_y
    lda #5
    sta room_w
    lda #3
    sta room_h

    lda #19                     // Left perimeter wall: inside
    sta zp_player_x
    lda #10
    sta zp_player_y
    ldx #0
    jsr uv_player_in_room_x
    bcc !t23_fail+

    lda #20                     // Top perimeter wall: inside
    sta zp_player_x
    lda #9
    sta zp_player_y
    ldx #0
    jsr uv_player_in_room_x
    bcc !t23_fail+

    lda #18                     // Two tiles left: outside
    sta zp_player_x
    lda #10
    sta zp_player_y
    ldx #0
    jsr uv_player_in_room_x
    bcs !t23_fail+

    lda #20                     // Two tiles above: outside
    sta zp_player_x
    lda #8
    sta zp_player_y
    ldx #0
    jsr uv_player_in_room_x
    bcs !t23_fail+

    lda #$01
    sta tc_results + 22
    jmp !t24+
!t23_fail:
    lda #$00
    sta tc_results + 22

    // ==========================================
    // Test 24: Dark-room pickup redraw must not change unrelated viewport tiles
    // Walk inside a dark room using local redraws, then pick up an item hidden
    // under the player and force a full redraw. The viewport image should stay
    // identical because the player already masked the item.
    // ==========================================
!t24:
    jsr tv_setup_dark_room

    lda #5
    sta tv_step_idx
!t24_walk:
    lda zp_player_x
    sta tv_prev_x
    lda zp_player_y
    sta tv_prev_y
    sta old_player_y
    lda tv_prev_x
    sta old_player_x

    inc zp_player_x
    lda zp_player_x
    sta player_data + PL_MAP_X
    lda zp_player_y
    sta player_data + PL_MAP_Y

    jsr update_visibility
    jsr viewport_update
    jsr render_local_area

    dec tv_step_idx
    bne !t24_walk-

    lda zp_player_x
    sta fi_add_x
    lda zp_player_y
    sta fi_add_y
    lda #17                     // Cure Light Wounds potion
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_qty_hi
    sta fi_add_p1
    sta fi_add_flags
    sta fi_add_ego
    jsr floor_item_add
    bcs !t24_item_ok+
    jmp !t24_fail+
!t24_item_ok:
    lda #0
    sta zp_temp0
    lda zp_player_x
    sta zp_temp0
    lda zp_player_y
    sta zp_temp1
    jsr render_single_tile

    // Normalize the viewport before snapshot so the comparison isolates
    // the pickup/full-redraw behavior rather than prior local-redraw drift.
    jsr render_viewport
    jsr tv_snapshot_viewport
    jsr item_pickup
    bcs !t24_pickup_ok+
    jmp !t24_fail+
!t24_pickup_ok:
    jsr render_viewport
    jsr tv_compare_viewport
    bcs !t24_fail+

    lda #$01
    sta tc_results + 23
    jmp !t25+
!t24_fail:
    lda #$00
    sta tc_results + 23

    // ==========================================
    // Test 25: eff_light_room must synchronize room_lit and tile FLAG_LIT
    // ==========================================
!t25:
    jsr tv_setup_dark_room
    jsr eff_light_room

    lda room_lit
    cmp #1
    bne !t25_fail+

    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #24
    lda (zp_ptr0),y
    and #FLAG_LIT
    beq !t25_fail+

    ldy #19                     // Left wall of the room rectangle
    lda (zp_ptr0),y
    and #FLAG_LIT
    beq !t25_fail+

    lda #$01
    sta tc_results + 24
    jmp !t26+
!t25_fail:
    lda #$00
    sta tc_results + 24

    // ==========================================
    // Test 26: look should flash the found visible target cell once
    // ==========================================
!t26:
    jsr tv_setup_dark_room
    :PatchJump(get_direction_target, test_get_direction_target_east)
    :PatchJump(screen_flash_at, test_screen_flash_at)

    lda #0
    sta tlk_flash_calls

    // Place a visible item one tile east of the player.
    lda #23
    sta fi_add_x
    lda #12
    sta fi_add_y
    lda #17                     // Cure Light Wounds potion
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_qty_hi
    sta fi_add_p1
    sta fi_add_flags
    sta fi_add_ego
    jsr floor_item_add
    bcc !t26_fail+

    jsr msg_clear
    jsr do_look

    lda tlk_flash_calls
    cmp #1
    bne !t26_fail+
    lda tlk_flash_row
    cmp #11
    bne !t26_fail+
    lda tlk_flash_col
    cmp #21
    bne !t26_fail+

    lda #$01
    sta tc_results + 25
    jmp !t27+
!t26_fail:
    lda #$00
    sta tc_results + 25

    // ==========================================
    // Test 27: look must not reveal monsters on remembered dark tiles
    // ==========================================
!t27:
    jsr tv_setup_dark_room
    lda #0
    sta tlk_flash_calls

    // Mark the second tile east as remembered but still dark.
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #24
    :MapRead_ptr0_y()
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()

    // Spawn a monster on that remembered tile.
    lda #24
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #1
    jsr monster_spawn_one
    bcc !t27_fail+

    jsr msg_clear
    jsr do_look

    lda $0408                   // "You see n..." vs "You see a..."
    cmp tlk_expected_n
    bne !t27_fail+
    lda tlk_flash_calls
    bne !t27_fail+

    lda #$01
    sta tc_results + 26
    jmp !t28+
!t27_fail:
    lda #$00
    sta tc_results + 26
    jmp !t28+

    // ==========================================
    // Test 28: look should preserve closed-door terrain messaging across flash
    // ==========================================
!t28:
    jsr tv_setup_dark_room
    lda #0
    sta tlk_flash_calls

    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #23
    lda #TILE_DOOR_CLOSED | FLAG_VISITED | FLAG_LIT
    :MapWrite_ptr0_y()

    jsr msg_clear
    jsr do_look

    lda $040a                   // "You see a c..."
    cmp tlk_expected_c
    bne !t28_fail+

    lda #$01
    sta tc_results + 27
    jmp !t29+
!t28_fail:
    lda #$00
    sta tc_results + 27

    // ==========================================
    // Test 29: look should preserve trap terrain messaging across flash
    // ==========================================
!t29:
    jsr tv_setup_dark_room
    lda #0
    sta tlk_flash_calls

    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #23
    lda #TILE_TRAP | FLAG_VISITED | FLAG_LIT
    :MapWrite_ptr0_y()

    jsr msg_clear
    jsr do_look

    lda $040a                   // "You see a t..."
    cmp tlk_expected_t
    bne !t29_fail+

    lda #$01
    sta tc_results + 28
    jmp !t30+
!t29_fail:
    lda #$00
    sta tc_results + 28

    // ==========================================
    // Test 30: look should prefer wall terrain over stale wall occupants/items
    // ==========================================
!t30:
    jsr tv_setup_dark_room
    lda #0
    sta tlk_flash_calls

    lda #23
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #57                     // Mean-Looking Mercenary
    jsr monster_spawn_one
    bcc !t30_fail+

    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #23
    lda #TILE_WALL_H | FLAG_VISITED | FLAG_LIT
    :MapWrite_ptr0_y()

    lda #23
    sta fi_add_x
    lda #12
    sta fi_add_y
    lda #0                      // Gold (small)
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_qty_hi
    sta fi_add_p1
    sta fi_add_flags
    sta fi_add_ego
    jsr floor_item_add
    bcc !t30_fail+

    jsr msg_clear
    jsr do_look

    lda $040a                   // "You see a w..."
    cmp tlk_expected_w
    bne !t30_fail+

    lda #$01
    sta tc_results + 29
    jmp !t31+
!t30_fail:
    lda #$00
    sta tc_results + 29

    // ==========================================
    // Test 31: look should still report floor gold as an item
    // ==========================================
!t31:
    jsr tv_setup_dark_room
    lda #0
    sta tlk_flash_calls

    lda #23
    sta fi_add_x
    lda #12
    sta fi_add_y
    lda #0                      // Gold (small)
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_qty_hi
    sta fi_add_p1
    sta fi_add_flags
    sta fi_add_ego
    jsr floor_item_add
    bcc !t31_fail+

    jsr msg_clear
    jsr do_look

    lda $040a                   // "You see a G..."
    cmp tlk_expected_g
    bne !t31_fail+

    lda #$01
    sta tc_results + 30
    jmp !t32+
!t31_fail:
    lda #$00
    sta tc_results + 30

    // ==========================================
    // Test 32: Non-confused movement obeys the command direction
    // Regresses player_try_move entry bookkeeping.
    // ==========================================
!t32:
    lda #20
    sta zp_player_x
    sta player_data + PL_MAP_X
    sta zp_player_y
    sta player_data + PL_MAP_Y

    ldx #17
!t32_fill_y:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #17
!t32_fill_x:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #24
    bcc !t32_fill_x-
    inx
    cpx #24
    bcc !t32_fill_y-

    lda #0
    sta zp_eff_confuse
    lda #$ff
    sta zp_run_dir

    lda #CMD_MOVE_E
    jsr player_try_move
    bcc !t32_fail+
    lda zp_player_x
    cmp #21
    bne !t32_fail+
    lda zp_player_y
    cmp #20
    bne !t32_fail+
    lda player_move_relocated
    cmp #1
    bne !t32_fail+
    lda #$01
    sta tc_results + 31
    jmp !t33+
!t32_fail:
    lda #$00
    sta tc_results + 31

    // ==========================================
    // Test 33: Learnable spell scan preserves the catalog index
    // Build the level-50 mage list for [Beginners-Magick] and
    // verify we get the expected 7 entries instead of looping.
    // ==========================================
!t33:
    jsr player_init
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #SPELL_MAGE
    sta pm_spell_type
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL

    lda #<book_mask_0
    sta pm_book_mask_lo
    lda #>book_mask_0
    sta pm_book_mask_hi

    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3

    jsr pm_setup_active_tables
    jsr pm_build_learnable_list_from_book

    lda pm_spell_count
    cmp #7
    bne !t33_fail+
    lda pm_spell_list + 0
    cmp #0
    bne !t33_fail+
    lda pm_spell_list + 6
    cmp #6
    bne !t33_fail+
    lda #$01
    sta tc_results + 32
    jmp !t34+
!t33_fail:
    lda #$00
    sta tc_results + 32

    // ==========================================
    // Test 34: Repeated casts of an already-selected spell
    // keep mana/worked bookkeeping stable.
    // ==========================================
!t34:
    :PatchJump(huff_print_msg, test_huff_print_msg)

    jsr player_init
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda #1
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    lda #0
    sta pm_spell_idx
    lda #1
    sta pm_spell_count

    lda #16
    sta tpm_cast_loop_ctr
!t34_cast_loop:
    lda #1
    sta pm_cost_tmp
    jsr pm_consume_mana
    jsr pm_mark_worked
    dec tpm_cast_loop_ctr
    lda tpm_cast_loop_ctr
    bne !t34_cast_loop-

    lda zp_player_mp
    cmp #4
    bne !t34_fail+
    lda player_data + PL_MANA
    cmp #4
    bne !t34_fail+
    lda pm_spell_idx
    cmp #0
    bne !t34_fail+
    lda pm_spell_count
    cmp #1
    bne !t34_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$01
    cmp #$01
    bne !t34_fail+
    lda #$01
    sta tc_results + 33
    jmp !t35+
!t34_fail:
    lda #$00
    sta tc_results + 33

    // ==========================================
    // Test 35: Rogue level 1 fails early with
    // the "not experienced enough" message.
    // ==========================================
!t35:
    jsr player_init
    lda #CLASS_ROGUE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #0
    sta inv_item_id + 0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    jsr player_cast_spell
    bcs !t35_fail+
    lda tpm_huff_calls
    beq !t35_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PM_NO_EXP
    bne !t35_fail+
    lda #$01
    sta tc_results + 34
    jmp !t36+
!t35_fail:
    lda #$00
    sta tc_results + 34

    // ==========================================
    // Test 36: Ranger level 1 fails early with
    // the "not experienced enough" message.
    // ==========================================
!t36:
    jsr player_init
    lda #CLASS_RANGER
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #0
    sta inv_item_id + 0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    jsr player_cast_spell
    bcs !t36_fail+
    lda tpm_huff_calls
    beq !t36_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PM_NO_EXP
    bne !t36_fail+
    lda #$01
    sta tc_results + 35
    jmp !t37+
!t36_fail:
    lda #$00
    sta tc_results + 35

    // ==========================================
    // Test 37: Repeated full player_cast_spell
    // calls keep the cast UI/execute flow stable.
    // ==========================================
!t37:
    :PatchJump(input_get_key, test_input_get_key_a)
    :PatchJump(input_get_modal_dismiss_key, test_input_get_modal_spell_a)
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_spell_execute_selected)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_pick_visible_spell, test_pm_pick_visible_spell)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)

    jsr player_init
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda #1
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    sta tpm_spell_exec_calls
    sta tpm_huff_calls
    sta tpm_last_huff_id
    lda #8
    sta tpm_cast_loop_ctr
!t37_cast_loop:
    jsr player_cast_spell
    bcc !t37_fail+
    dec tpm_cast_loop_ctr
    bne !t37_cast_loop-

    lda tpm_spell_exec_calls
    cmp #8
    bne !t37_fail+
    lda zp_player_mp
    cmp #12
    bne !t37_fail+
    lda player_data + PL_MANA
    cmp #12
    bne !t37_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$01
    cmp #$01
    bne !t37_fail+
    lda #$01
    sta tc_results + 36
    jmp !t38+
!t37_fail:
    lda #$00
    sta tc_results + 36

    // ==========================================
    // Test 38: Mage using pray shows the explicit
    // "no pray" message instead of silently flashing.
    // ==========================================
!t38:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    jsr player_init
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    jsr player_pray
    bcs !t38_fail+
    lda tpm_huff_calls
    beq !t38_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PM_NO_PRAY
    bne !t38_fail+
    lda #$01
    sta tc_results + 37
    jmp !t39+
!t38_fail:
    lda #$00
    sta tc_results + 37

    // ==========================================
    // Test 39: Priest using magic shows the explicit
    // "no cast" message instead of silently flashing.
    // ==========================================
!t39:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    jsr player_init
    lda #CLASS_PRIEST
    sta player_data + PL_CLASS
    lda #SPELL_PRIEST
    sta player_data + PL_SPELL_TYPE
    lda #0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    jsr player_cast_spell
    bcs !t39_fail+
    lda tpm_huff_calls
    beq !t39_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PM_NO_CAST
    bne !t39_fail+
    lda #$01
    sta tc_results + 38
    jmp !t40+
!t39_fail:
    lda #$00
    sta tc_results + 38

    // ==========================================
    // Test 40: Book prompt wording follows the
    // current action (cast / pray / study).
    // ==========================================
!t40:
    lda #0
    sta pm_mode
    lda #SPELL_MAGE
    sta pm_spell_type
    jsr pm_book_prompt_huff_id
    cpx #HSTR_PM_BOOK_CAST
    bne !t40_fail+

    lda #0
    sta pm_mode
    lda #SPELL_PRIEST
    sta pm_spell_type
    jsr pm_book_prompt_huff_id
    cpx #HSTR_PM_BOOK_PRAY
    bne !t40_fail+

    lda #1
    sta pm_mode
    lda #SPELL_PRIEST
    sta pm_spell_type
    jsr pm_book_prompt_huff_id
    cpx #HSTR_IGS_PROMPT
    bne !t40_fail+

    lda #$01
    sta tc_results + 39
    jmp !tests_done+
!t40_fail:
    lda #$00
    sta tc_results + 39

!tests_done:
    jmp test_finish

tv_setup_dark_room:
    jsr fill_map_rock
    jsr item_init_floor
    jsr monster_init_table
    lda #0
    sta vis_room_revealed
    lda #$ff
    sta vis_cached_room_idx
    lda #0
    sta room_count

    lda #1
    sta room_count
    lda #20
    sta room_x
    sta dg_room_x
    lda #10
    sta room_y
    sta dg_room_y
    lda #10
    sta room_w
    sta dg_room_w
    lda #6
    sta room_h
    sta dg_room_h
    lda #0
    sta room_lit
    jsr draw_dungeon_room
    jsr darken_rooms

    lda #22
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #12
    sta zp_player_y
    sta player_data + PL_MAP_Y
    lda #1
    sta zp_player_dlvl
    lda #0
    sta zp_eff_blind
    lda #1
    sta zp_light_radius
    sta player_data + PL_LIGHT_RAD
    lda #COL_BLACK
    sta zp_text_color
    jsr screen_clear
    jsr update_visibility
    jsr viewport_update
    jsr render_viewport
    rts

tv_snapshot_viewport:
    lda $01
    pha
    and #%11111110
    sta $01
    lda #<tv_snapshot_screen
    sta zp_ptr0
    lda #>tv_snapshot_screen
    sta zp_ptr0_hi
    lda #0
    sta tv_row_idx
!tv_snap_row:
    ldx tv_row_idx
    txa
    clc
    adc #VIEWPORT_Y
    tax
    lda screen_row_lo,x
    clc
    adc #VIEWPORT_X
    sta zp_screen_lo
    lda screen_row_hi,x
    adc #0
    sta zp_screen_hi

    ldy #0
!tv_snap_col:
    lda (zp_screen_lo),y
    sta (zp_ptr0),y
    iny
    cpy #VIEWPORT_W
    bne !tv_snap_col-

    lda zp_ptr0
    clc
    adc #VIEWPORT_W
    sta zp_ptr0
    bcc !tv_snap_screen_advance_done+
    inc zp_ptr0_hi
!tv_snap_screen_advance_done:
    inc tv_row_idx
    lda tv_row_idx
    cmp #VIEWPORT_H
    beq !tv_snap_done+
    jmp !tv_snap_row-
!tv_snap_done:
    pla
    sta $01
    rts

tv_compare_viewport:
    lda $01
    pha
    and #%11111110
    sta $01
    lda #<tv_snapshot_screen
    sta zp_ptr0
    lda #>tv_snapshot_screen
    sta zp_ptr0_hi
    lda #0
    sta tv_row_idx
!tv_cmp_row:
    ldx tv_row_idx
    txa
    clc
    adc #VIEWPORT_Y
    tax
    lda screen_row_lo,x
    clc
    adc #VIEWPORT_X
    sta zp_screen_lo
    lda screen_row_hi,x
    adc #0
    sta zp_screen_hi

    ldy #0
!tv_cmp_col:
    lda (zp_screen_lo),y
    cmp (zp_ptr0),y
    bne !tv_cmp_mismatch+
!tv_cmp_next:
    iny
    cpy #VIEWPORT_W
    bne !tv_cmp_col-

    lda zp_ptr0
    clc
    adc #VIEWPORT_W
    sta zp_ptr0
    bcc !tv_cmp_screen_advance_done+
    inc zp_ptr0_hi
!tv_cmp_screen_advance_done:
    inc tv_row_idx
    lda tv_row_idx
    cmp #VIEWPORT_H
    beq !tv_cmp_match+
    jmp !tv_cmp_row-
!tv_cmp_mismatch:
    pla
    sta $01
    sec
    rts
!tv_cmp_match:
    pla
    sta $01
    clc
    rts

effects_test_body_end:
.assert "effects test body stays below scratch buffers", effects_test_body_end <= $bad9, true

.segmentdef TestEffectsBuffers [start=$bad9]
.segment TestEffectsBuffers
tv_snapshot_screen: .fill VIEWPORT_W * VIEWPORT_H, 0
