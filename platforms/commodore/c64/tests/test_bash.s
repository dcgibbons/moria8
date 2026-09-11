// test_bash.s — Runtime tests for bash.s
//
// Tests: bash_door (success/fail), bash_monster (hit + HP decrease),
//        bash_stun_check (stun applied), bash_off_balance (paralyze set/safe),
//        and Shift+D dig handoff for tunnelable terrain.
//
// Results at $0400-$040D: $01 = pass, $00 = fail per test (14 tests)
// NOTE: msg_print writes to screen row 0 ($0400+), so we store results
// in tc_results[] and copy to $0400 at the very end.

#define C64_TEST_NAME_STREAMS_A000

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #13
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

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
#import "../../../../core/stat_display.s"
.segmentdef TestCreateOverlay [start=$D000]
.segmentdef TestNameStreams [start=$A000]
.segment TestCreateOverlay
#import "../../../../core/background_data.s"
#import "../../../../core/player_create.s"
.segment Default
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "dungeon_gen_stubs.s"
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
#import "../../../../core/special_rooms_stubs.s"
#import "../../../../core/player_items.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/bash.s"
#import "../../../../core/turn_render_state.s"
// This stub lives in the $D000 test overlay so Main stays below MAP_BASE.
.segment TestCreateOverlay
mon_atk_apply_damage:
    lda zp_player_hp_lo
    sec
    sbc zp_combat_dmg
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sbc #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    bmi !mad_dead+
    ora zp_player_hp_lo
    beq !mad_dead+
    clc
    rts
!mad_dead:
    sec
    rts
.segment Default
eff_fear_timer: .byte 0
// Chest dispatch lives in the platform main; bash.s routes to it when the
// target tile holds a chest. No chest items exist in these tests.
chest_dispatch:
chest_bash_command:
    clc
    rts
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
ui_char_display:
ui_help_display:
    rts
monster_attack_player:
player_update_hunger_state:
    sec
    rts
player_death_check:
    lda zp_player_hp_hi
    bmi !pdc_dead+
    ora zp_player_hp_lo
    beq !pdc_dead+
    rts
!pdc_dead:
    lda zp_game_flags
    ora #$01
    sta zp_game_flags
    rts
#import "../../../../core/store_data.s"
#import "../../../../core/store.s"
#import "../../../../core/ui_store.s"
#import "../../../../core/ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

player_tunnel_resolved_target:
    inc tc_tunnel_calls
    sec
    rts

test_get_direction_target:
    lda #11
    sta df_target_x
    lda #10
    sta df_target_y
    sec
    rts

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

// Test scratch. The test image loads past MAP_BASE ($C000) into the map
// band, so all mutable scratch must live here, below MAP_BASE — data at
// end of file would alias map cells the tests write.
tc_loop:    .byte 0
tc_ok:      .byte 0
tc_results: .fill 14, $ff      // Result buffer (copied to $0400 at end)
tc_saved_hp_lo: .byte 0
tc_saved_hp_hi: .byte 0
tc_tunnel_calls: .byte 0
tb_rng_idx:    .byte 0
tb_flags:      .byte 0
tb_rng_script: .fill 8, 0
tb_rng_saved:  .fill 6, 0        // tb_patch_rng/tb_restore_rng jmp bytes
.assert "test scratch stays below MAP_BASE", * <= MAP_BASE, true

test_start:
    :PatchJump(get_direction_target, test_get_direction_target)

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
    jsr hal_sound_init

    // Direct bash_door formula fixtures do not initialize passive-search
    // state. Keep it suppressed except in the dedicated movement test.
    lda player_data + PL_FLAGS
    ora #PLF_SEARCHING
    sta player_data + PL_FLAGS

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
    // Test 1: bash_door_success — STR 18, loop until door opens
    // Set TILE_DOOR_CLOSED at map position (10,10), bash it.
    // A plain door has a 50% success chance, independent of STR.
    // Loop up to 50 attempts — at least one should succeed.
    // ==========================================

    // Set up target position
    lda #10
    sta df_target_x
    lda #10
    sta df_target_y

    // Write TILE_DOOR_CLOSED at (10,10) on map
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y

    // Set high STR
    lda #18
    sta zp_player_str

    // Clear confusion, fear, paralysis
    lda #0
    sta zp_eff_confuse
    sta eff_fear_timer
    sta zp_eff_paralyze

    // Loop: try bash_door up to 50 times
    lda #50
    sta tc_loop
!t1_loop:
    // Reset tile to TILE_DOOR_CLOSED each iteration
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y

    // Set bash_save_tile (bash_door reads this)
    lda #TILE_DOOR_CLOSED
    sta bash_save_tile

    // Re-stuff keyboard buffer for msg_print -more- prompts
    lda #8
    sta $c6

    jsr bash_door

    // Check if tile changed to TILE_DOOR_OPEN
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !t1_pass+

    dec tc_loop
    bne !t1_loop-
    // All 50 attempts failed — fail
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_pass:
    lda #$01
    sta tc_results + 0

    // ==========================================
    // Test 2: bash_door_fail — STR 3, verify at least one attempt
    //   keeps door closed.
    // A plain door has a 50% failure chance, independent of STR.
    // Loop 50 attempts — at least one should fail (door stays closed).
    // ==========================================
!t2:
    lda #3
    sta zp_player_str

    lda #50
    sta tc_loop
    lda #0
    sta tc_ok                   // Will set to 1 if any attempt fails
!t2_loop:
    // Reset tile to TILE_DOOR_CLOSED
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y

    lda #TILE_DOOR_CLOSED
    sta bash_save_tile

    lda #8
    sta $c6

    jsr bash_door

    // Check if tile is still TILE_DOOR_CLOSED
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    bne !t2_next+
    // Door stayed closed — this is a successful fail!
    lda #1
    sta tc_ok
!t2_next:
    dec tc_loop
    bne !t2_loop-

    lda tc_ok
    sta tc_results + 1

    // ==========================================
    // Test 3: bash_monster_hit — Set up monster, bash it, verify HP decreased
    // Create a monster with HP=20 in slot 0. Set STR=18, equip shield.
    // bash_monster should hit at least once in 30 attempts.
    // ==========================================
!t3:
    jsr monster_init_table

    // Place monster at position (11,10) — same row as player
    lda #10
    sta zp_player_x
    sta zp_player_y

    // Create monster in slot 0
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #4                      // Kobold (type 4, cr_ac=16)
    sta (zp_ptr0),y
    ldy #MX_X
    lda #11
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #10
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #20
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldy #MX_STUN
    lda #0
    sta (zp_ptr0),y

    lda #1
    sta zp_mon_count

    // Set STR=18
    lda #18
    sta zp_player_str

    // Equip Small Shield (type 9, weight=50) in shield slot
    lda #9
    sta inv_item_id + EQUIP_SHIELD

    // Set player level (needed for combat)
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS

    // Loop up to 30 attempts — bash_monster directly
    lda #30
    sta tc_loop
    lda #0
    sta tc_ok
!t3_loop:
    // Re-stuff keyboard buffer
    lda #8
    sta $c6

    // Restore monster HP to 20 if it's alive, or reinit
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !t3_still_alive+
    // Monster was killed, reinit
    ldy #MX_TYPE
    lda #4
    sta (zp_ptr0),y
    ldy #MX_X
    lda #11
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #10
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldy #MX_STUN
    lda #0
    sta (zp_ptr0),y
!t3_still_alive:
    ldy #MX_HP_LO
    lda #20
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y

    // Set up cmb_slot for bash_monster (it expects X = slot)
    ldx #0
    stx cmb_slot

    // Call bash_monster (it reads X from stack entry, but actually
    // it does stx cmb_slot itself — we just need X=0 on entry)
    jsr bash_monster

    // Check if HP decreased from 20
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #20
    bcs !t3_next+              // HP >= 20 → miss, try again
    // HP < 20 → hit!
    lda #1
    sta tc_ok
    jmp !t3_done+
!t3_next:
    dec tc_loop
    bne !t3_loop-
!t3_done:
    lda tc_ok
    sta tc_results + 2

    // ==========================================
    // Test 4: bash_stun_check — Weak monster, verify MX_STUN > 0
    // Use type 1 (Fruit Bat): cr_hd_num=1, cr_hd_sides=3, cr_ac=4.
    // Set HP=2 (low). bash_power = 25 + rng(100) + rng(100) ∈ [25,223].
    // mon_hp_q = 2/4 = 0. avg_max_q = 1*(3+1)/8 = 0.
    // mon_tough = 0 + 0 = 0. bash_power (25-223) > 0 → always stuns!
    // ==========================================
!t4:
    jsr monster_init_table

    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #1                      // Fruit Bat
    sta (zp_ptr0),y
    ldy #MX_X
    lda #11
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #10
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #2
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_STUN
    lda #0
    sta (zp_ptr0),y

    lda #1
    sta zp_mon_count

    // Set combat variables for bash_stun_check
    lda #0
    sta cmb_slot
    lda #1
    sta cmb_type                // Fruit Bat

    // Re-stuff keyboard buffer
    lda #8
    sta $c6

    jsr bash_stun_check

    // Check MX_STUN > 0
    ldx #0
    jsr monster_get_ptr
    ldy #MX_STUN
    lda (zp_ptr0),y
    cmp #1
    bcs !t4_pass+
    lda #$00
    sta tc_results + 3
    jmp !t5+
!t4_pass:
    lda #$01
    sta tc_results + 3

    // ==========================================
    // Test 5: bash_off_balance — Low DEX, run 50 times.
    // DEX=3. rng_range(150) returns [0,149].
    // Off-balance if roll > DEX (i.e., roll > 3).
    // Chance: 146/150 ≈ 97% per try. At least one in 50 should trigger.
    // Verify zp_eff_paralyze > 0 at least once.
    // ==========================================
!t5:
    lda #3
    sta zp_player_dex

    lda #50
    sta tc_loop
    lda #0
    sta tc_ok
!t5_loop:
    lda #0
    sta zp_eff_paralyze

    jsr bash_off_balance

    lda zp_eff_paralyze
    beq !t5_next+
    // Paralyzed! Success.
    lda #1
    sta tc_ok
    jmp !t5_done+
!t5_next:
    dec tc_loop
    bne !t5_loop-
!t5_done:
    lda tc_ok
    sta tc_results + 4

    // ==========================================
    // Test 6: bash_off_balance_safe — High DEX, run 50 times.
    // DEX=150 (well, max stat is 18, but zp_player_dex is just a byte).
    // Actually: rng_range(150) returns [0,149]. If DEX >= 150 then
    // roll is always < DEX → always safe. But DEX caps at 18.
    // DEX=18 → roll > 18 fails (131/150 ≈ 87%). Not guaranteed safe.
    //
    // Instead: Verify that with DEX=18, at least one trial stays safe
    // (roll <= 18 → 19/150 ≈ 13% → in 50 tries, P(all fail) = 0.87^50 ≈ 0.001).
    // ==========================================
!t6:
    lda #18
    sta zp_player_dex

    lda #50
    sta tc_loop
    lda #0
    sta tc_ok
!t6_loop:
    lda #0
    sta zp_eff_paralyze

    jsr bash_off_balance

    lda zp_eff_paralyze
    bne !t6_next+
    // Stayed balanced! Success.
    lda #1
    sta tc_ok
    jmp !t6_done+
!t6_next:
    dec tc_loop
    bne !t6_loop-
!t6_done:
    lda tc_ok
    sta tc_results + 5

    // ==========================================
    // Test 7: bash_command on tunnelable terrain hands off to the
    // tunneling path instead of stopping at the bash wall path.
    // ==========================================
!t7:
    jsr monster_init_table
    lda #0
    sta zp_mon_count
    sta tc_tunnel_calls
    sta eff_fear_timer
    sta zp_eff_confuse
    sta zp_eff_paralyze
    lda #10
    sta zp_player_x
    sta zp_player_y

    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #11
    lda #TILE_QUARTZ
    sta (zp_ptr0),y

    jsr bash_command

    lda tc_tunnel_calls
    cmp #1
    beq !t7_pass+
    lda #$00
    sta tc_results + 6
    jmp !t8+
!t7_pass:
    lda #$01
    sta tc_results + 6

    // ==========================================
    // Test 8: bash_command on a closed door stays on the bash path
    // and does not hand off to tunneling.
    // ==========================================
!t8:
    jsr monster_init_table
    lda #0
    sta zp_mon_count
    sta tc_tunnel_calls
    sta eff_fear_timer
    sta zp_eff_confuse
    sta zp_eff_paralyze
    lda #10
    sta zp_player_x
    sta zp_player_y
    lda #18
    sta zp_player_str

    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #11
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y

    lda #8
    sta $c6

    jsr bash_command

    lda tc_tunnel_calls
    beq !t8_pass+
    lda #$00
    sta tc_results + 7
    jmp !tests_done+
!t8_pass:
    lda #$01
    sta tc_results + 7

    // ==========================================
    // Test 9: bash-killing the Balrog sets the winner flag (combat_note_kill
    // wiring in the bash_monster kill path).
    // ==========================================
!t9:
    jsr monster_init_table
    lda zp_game_flags
    and #~GAME_FLAG_WINNER & $ff
    sta zp_game_flags
    lda #0
    sta cmb_winner_pending
    sta tc_ok
    lda #100
    sta cr_level + CREATURE_BALROG

    // Slot 0: one-HP Balrog at (11,10)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #CREATURE_BALROG
    sta (zp_ptr0),y
    ldy #MX_X
    lda #11
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #10
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #1
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_STUN
    lda #0
    sta (zp_ptr0),y

    lda #1
    sta zp_mon_count

    lda #18
    sta zp_player_str
    lda #9
    sta inv_item_id + EQUIP_SHIELD
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS

    lda #40
    sta tc_loop
!t9_loop:
    lda #8
    sta $c6
    ldx #0
    stx cmb_slot
    jsr bash_monster
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !t9_killed+
    dec tc_loop
    bne !t9_loop-
    jmp !t9_fail+
!t9_killed:
    lda zp_game_flags
    and #GAME_FLAG_WINNER
    beq !t9_fail+
    lda #$01
    sta tc_results + 8
    jmp !t9_done+
!t9_fail:
    lda #$00
    sta tc_results + 8
!t9_done:
    lda zp_game_flags
    and #~GAME_FLAG_WINNER & $ff
    sta zp_game_flags

    :BankOutBasic()             // Script helpers live after name data at $A000
    jsr test_bash_door_locked_success
    jsr test_bash_door_locked_fail
    jsr test_bash_door_stuck_success
    jsr test_bash_door_full_table_break
    jsr test_bash_door_passive_search

!tests_done:
    jmp test_exit_trampoline

// ============================================================
// Test 10: bash_door on a locked door — Umoria formula success path.
// STR 18 → chance 93 (18 + 75 proxy), |s| = 15 → spread 93*35 = 3255,
// threshold 10*78 = 780. Scripted word roll 779 succeeds; break roll 1
// (no break) clears state; player steps into the doorway.
// ============================================================
test_bash_door_locked_success:
    jsr tb_setup_locked_door
    // Script: word roll 779, break roll 1
    lda #0
    sta tb_rng_idx
    lda #<779
    sta tb_rng_script
    lda #>779
    sta tb_rng_script + 1
    lda #1
    sta tb_rng_script + 2
    jsr tb_patch_rng
    jsr bash_door
    php
    pla
    sta tb_flags
    jsr tb_restore_rng

    lda tb_flags
    and #$01                // Carry: turn consumed
    beq !t10_fail+
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    bne !t10_fail+
    lda door_state_count    // No break → state entry removed
    bne !t10_fail+
    lda zp_player_x         // Step-through into the doorway
    cmp #10
    bne !t10_fail+
    lda zp_player_y
    cmp #12
    bne !t10_fail+
    lda #$01
    sta tc_results + 9
    jmp !t10_done+
!t10_fail:
    lda #$00
    sta tc_results + 9
!t10_done:
    rts

// ============================================================
// Test 11: bash_door on a locked door — failure path.
// Word roll 780 >= threshold 780 → door holds; tile closed, state
// intact, player stays put, turn consumed.
// ============================================================
test_bash_door_locked_fail:
    jsr tb_setup_locked_door
    lda #0
    sta tb_rng_idx
    lda #<780
    sta tb_rng_script
    lda #>780
    sta tb_rng_script + 1
    lda #0                  // off-balance DEX roll: 0 < DEX → safe
    sta tb_rng_script + 2
    jsr tb_patch_rng
    jsr bash_door
    php
    pla
    sta tb_flags
    jsr tb_restore_rng

    lda tb_flags
    and #$01
    beq !t11_fail+
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    bne !t11_fail+
    lda door_state_count
    cmp #1
    bne !t11_fail+
    lda door_state_val
    cmp #15
    bne !t11_fail+
    lda zp_player_x
    cmp #9                  // Unmoved
    bne !t11_fail+
    lda zp_eff_paralyze
    bne !t11_fail+          // Safe DEX roll: no off-balance
    lda #$01
    sta tc_results + 10
    jmp !t11_done+
!t11_fail:
    lda #$00
    sta tc_results + 10
!t11_done:
    rts

// ============================================================
// Test 12: bash_door on a stuck door — magnitude must decode via the
// sign-bit mask: val $8f (stuck, magnitude 15) → |s| = 15, NOT the
// two's-complement value 113 (which made stuck doors unbashable).
// Same math as test 10: chance 93, spread 3255, threshold 780; word
// roll 779 succeeds, break roll 1 clears state, player steps through.
// ============================================================
test_bash_door_stuck_success:
    jsr tb_setup_stuck_door
    // Script: word roll 779, break roll 1
    lda #0
    sta tb_rng_idx
    lda #<779
    sta tb_rng_script
    lda #>779
    sta tb_rng_script + 1
    lda #1
    sta tb_rng_script + 2
    jsr tb_patch_rng
    jsr bash_door
    php
    pla
    sta tb_flags
    jsr tb_restore_rng

    lda tb_flags
    and #$01                // Carry: turn consumed
    beq !t12_fail+
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    bne !t12_fail+
    lda door_state_count    // No break → state entry removed
    bne !t12_fail+
    lda zp_player_x         // Step-through into the doorway
    cmp #10
    bne !t12_fail+
    lda zp_player_y
    cmp #12
    bne !t12_fail+
    lda #$01
    sta tc_results + 11
    jmp !t12_done+
!t12_fail:
    lda #$00
    sta tc_results + 11
!t12_done:
    rts

// ============================================================
// Test 13: a plain-door break roll with a full state table opens the
// door unbroken. The broken result cannot be represented, so it must
// not be passed to door_state_set_at and silently dropped.
// ============================================================
test_bash_door_full_table_break:
    jsr tb_setup_locked_door
    // Make the target plain/untracked while keeping the table full.
    ldx #MAX_DOOR_STATES - 1
    lda #63
!t13_x:
    sta door_state_x,x
    dex
    bpl !t13_x-
    ldx #MAX_DOOR_STATES - 1
    lda #21
!t13_y:
    sta door_state_y,x
    dex
    bpl !t13_y-
    lda #MAX_DOOR_STATES
    sta door_state_count
    // Plain-door bash: word roll 0 succeeds; break roll 0 requests broken.
    lda #0
    sta tb_rng_idx
    sta tb_rng_script
    sta tb_rng_script + 1
    sta tb_rng_script + 2
    jsr tb_patch_rng
    jsr bash_door
    php
    pla
    sta tb_flags
    jsr tb_restore_rng

    lda tb_flags
    and #$01
    beq !t13_fail+
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    bne !t13_fail+
    lda door_state_count
    cmp #MAX_DOOR_STATES       // No unrepresentable broken entry added
    bne !t13_fail+
    lda #$01
    sta tc_results + 12
    rts
!t13_fail:
    lda #$00
    sta tc_results + 12
    rts

// ============================================================
// Test 14: successful door bash steps through via the production bash_door
// path and performs movement-owned passive search (Umoria playerBashClosedDoor
// -> playerMove). A guaranteed search reveals the adjacent secret door.
// ============================================================
test_bash_door_passive_search:
    jsr tb_setup_locked_door
    lda player_data + PL_FLAGS
    and #~PLF_SEARCHING & $ff
    sta player_data + PL_FLAGS
    lda #0
    sta player_data + PL_CLASS
    sta player_data + PL_RACE
    sta trap_count

    // Keep the destination lit so effective search chance is not dimmed.
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_DOOR_CLOSED | FLAG_LIT
    sta (zp_ptr0),y
    sta bash_save_tile
    iny
    lda #TILE_SECRET
    sta (zp_ptr0),y

    // Word roll 0 succeeds, break roll 1 leaves the door intact; remaining
    // zeroes guarantee the passive-frequency and secret-discovery rolls.
    lda #0
    sta tb_rng_idx
    sta tb_rng_script
    sta tb_rng_script + 1
    lda #1
    sta tb_rng_script + 2
    lda #0
    sta tb_rng_script + 3
    sta tb_rng_script + 4
    lda #8
    sta $c6
    jsr tb_patch_rng
    jsr bash_door
    php
    pla
    sta tb_flags
    jsr tb_restore_rng

    lda tb_flags
    and #$01
    beq !t14_fail+
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #11
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    bne !t14_fail+
    lda #$01
    sta tc_results + 13
    rts
!t14_fail:
    lda #$00
    sta tc_results + 13
    rts

// tb_setup_stuck_door — Same door as tb_setup_locked_door but stuck
// with magnitude 15: val = $80 | 15 = $8f (bit 7 set = stuck/jammed).
tb_setup_stuck_door:
    jsr tb_setup_locked_door
    lda #$8f
    sta door_state_val
    rts

// tb_setup_locked_door — Closed door at (10,12) with locked state 15;
// player at (9,12), STR 18, no confusion/fear/paralysis, DEX 18. Row 12
// keeps the mutable map cell beyond this test image's executable body.
tb_setup_locked_door:
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y
    lda #TILE_DOOR_CLOSED
    sta bash_save_tile
    lda #10
    sta df_target_x
    lda #12
    sta df_target_y
    lda #1
    sta door_state_count
    lda #10
    sta door_state_x
    lda #12
    sta door_state_y
    lda #15
    sta door_state_val
    lda #18
    sta zp_player_str
    sta zp_player_dex
    lda #9
    sta zp_player_x
    lda #12
    sta zp_player_y
    lda #0
    sta zp_eff_confuse
    sta eff_fear_timer
    sta zp_eff_paralyze
    sta player_move_relocated
    lda player_data + PL_FLAGS
    ora #PLF_SEARCHING          // Isolate door-roll tests from passive search
    sta player_data + PL_FLAGS
    rts

// Scripted RNG: test_rng_word_scripted returns tb_rng_script word entries
// (lo,hi pairs) in zp_temp2/3; test_rng_range_scripted returns the following
// bytes for rng_range calls. NOTE: ldx must follow the incs — tb_rng_idx is
// advanced in memory, so X must be loaded after incrementing for the -2/-1
// compensation to address the intended script byte.
test_rng_word_scripted:
    inc tb_rng_idx
    inc tb_rng_idx
    ldx tb_rng_idx
    lda tb_rng_script - 2,x
    sta zp_temp2
    lda tb_rng_script - 1,x
    sta zp_temp3
    rts

test_rng_range_scripted:
    inc tb_rng_idx
    ldx tb_rng_idx
    lda tb_rng_script - 1,x
    rts

tb_patch_rng:
    lda rng_range
    sta tb_rng_saved
    lda rng_range + 1
    sta tb_rng_saved + 1
    lda rng_range + 2
    sta tb_rng_saved + 2
    lda rng_range_word
    sta tb_rng_saved + 3
    lda rng_range_word + 1
    sta tb_rng_saved + 4
    lda rng_range_word + 2
    sta tb_rng_saved + 5
    :PatchJump(rng_range_word, test_rng_word_scripted)
    :PatchJump(rng_range, test_rng_range_scripted)
    rts

tb_restore_rng:
    lda tb_rng_saved
    sta rng_range
    lda tb_rng_saved + 1
    sta rng_range + 1
    lda tb_rng_saved + 2
    sta rng_range + 2
    lda tb_rng_saved + 3
    sta rng_range_word
    lda tb_rng_saved + 4
    sta rng_range_word + 1
    lda tb_rng_saved + 5
    sta rng_range_word + 2
    rts

.assert "Bash test main stays below MAP_BASE", * <= MAP_BASE, true
