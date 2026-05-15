// test_monster_ai.s — Runtime tests for monster_ai.s
//
// Tests: monster_ai_tick, wake check, movement, speed, FLAG_OCCUPIED,
//        confused movement.
//
// Results at $0400-$0409: $01 = pass, $00 = fail per test
// NOTE: msg_print writes to screen row 0 ($0400+), so we store results
// in tc_results[] and copy to $0400 at the very end.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(bootstrap)

.pc = $0810 "Test Code"

.encoding "screencode_mixed"

// Bootstrap — must be before imports so it's in RAM below $A000.
bootstrap:
    lda $01
    and #%11111110          // Clear bit 0 -> bank out BASIC ROM
    sta $01
    jmp test_start

// test_finish — Copy results to $0400 and halt.
test_finish:
    ldx #25
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = * "Test Body"

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
tai_save_x: .byte 0
tai_save_y: .byte 0
tai_ok:     .byte 0
tai_count:  .byte 0
tai_attack_calls: .byte 0
tai_rng_values:   .fill 4, 0
tai_rng_idx:      .byte 0
tc_results: .fill 26, $ff      // Result buffer (copied to $0400 at end)

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_monster_attack_player:
    inc tai_attack_calls
    rts

test_rng_range:
    ldx tai_rng_idx
    lda tai_rng_values,x
    inc tai_rng_idx
    ora #0
    rts

test_rng_range_word:
    ldx tai_rng_idx
    lda tai_rng_values,x
    sta zp_temp2
    inx
    lda tai_rng_values,x
    sta zp_temp3
    inx
    stx tai_rng_idx
    rts

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

    // Initialize message system and sound
    jsr msg_init
    jsr hal_sound_init

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

    // Set player dungeon level to 1
    lda #1
    sta zp_player_dlvl

    // Set light radius
    lda #1
    sta zp_light_radius

    // Set player HP high to survive monster attacks during tests
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #4
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Set player AC to 0 (default)
    lda #4
    sta zp_player_ac
    sta player_data + PL_AC
    sta zp_game_flags

    // Set warrior class for saving throw calculations
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL

    // Generate a dungeon level for all tests
    lda #4
    sta level_entry_dir
    jsr level_generate

    // ==========================================
    // Test 1: monster_ai_tick with empty table — no crash
    // ==========================================
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Put player somewhere
    lda #20
    sta zp_player_x
    lda #20
    sta zp_player_y

    jsr monster_ai_tick

    // If we got here without crashing, it's a pass
    // Also check count is still 0
    lda zp_mon_count
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // ==========================================
    // Test 2: Attack-only monster (CF_ATTACK_ONLY) doesn't move
    // Type 6 (Shrieker mushroom) — speed=1, CF_ATTACK_ONLY
    // ==========================================
!t2:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Restore keyboard buffer
    lda #8
    sta $c6

    // Place a floor tile at (30, 20) and spawn mushroom there
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #30
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    lda #30
    sta ms_spawn_x
    lda #20
    sta ms_spawn_y
    lda #6                      // Shrieker mushroom (speed=1, CF_ATTACK_ONLY)
    jsr monster_spawn_one

    // Save position
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    sta tai_save_x
    ldy #MX_Y
    lda (zp_ptr0),y
    sta tai_save_y

    // Put player nearby to potentially trigger wake
    lda #31
    sta zp_player_x
    lda #20
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Check position unchanged
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp tai_save_x
    bne !t2_fail+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp tai_save_y
    bne !t2_fail+

    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // ==========================================
    // Test 3: Wake check — monster within AAF range eventually wakes
    // Type 0 (White harpy) — sleep=10, aaf=16
    // Run up to 30 AI ticks; with sleep=10, P(wake per tick)~10%,
    // so P(still asleep after 30) = 0.9^30 ~ 4%
    // ==========================================
!t3:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Restore keyboard buffer
    lda #8
    sta $c6

    // Place floor at (25, 20) and surrounding tiles for movement
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #24
!t3_fill:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #32
    bne !t3_fill-

    lda #25
    sta ms_spawn_x
    lda #20
    sta ms_spawn_y
    lda #0                      // White harpy (sleep=10, aaf=16)
    jsr monster_spawn_one

    // Place player within AAF range (distance=5)
    lda #24
    sta zp_player_x
    lda #20
    sta zp_player_y

    // Reset HP before combat
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Run up to 30 AI ticks checking for wake
    lda #30
    sta tai_count
!t3_loop:
    // Restore keyboard buffer for -more- prompts
    lda #8
    sta $c6

    jsr monster_ai_tick

    // Check MF_AWAKE
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    bne !t3_pass+

    dec tai_count
    bne !t3_loop-

    // 30 ticks and still asleep — fail
    lda #$00
    sta tc_results + 2
    jmp !t4+
!t3_pass:
    lda #$01
    sta tc_results + 2

    // ==========================================
    // Test 4: Wake check — monster outside AAF range stays asleep
    // Type 9 (Jackal) — aaf=12
    // ==========================================
!t4:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Place floor at (10, 10)
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    lda #10
    sta ms_spawn_x
    lda #10
    sta ms_spawn_y
    lda #9                      // Jackal (aaf=12)
    jsr monster_spawn_one

    // Place player far away (distance > 12)
    lda #40
    sta zp_player_x
    lda #40
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Check MF_AWAKE is NOT set
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    beq !t4_pass+
    lda #$00
    sta tc_results + 3
    jmp !t5+
!t4_pass:
    lda #$01
    sta tc_results + 3

    // ==========================================
    // Test 5: Awake monster moves toward player
    // Place monster, set awake, verify distance decreases
    // ==========================================
!t5:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Create a clear corridor: floor tiles from (20,15) to (30,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
!t5_fill:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #31
    bne !t5_fill-

    // Spawn type 4 (Kobold, speed=1) at (20,15)
    lda #20
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #0
    jsr monster_spawn_one

    // Manually set MF_AWAKE
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    // Player at (30, 15) — distance=10
    lda #30
    sta zp_player_x
    lda #15
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Check monster moved closer to player (x increased from 20)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #21                     // Should have moved from 20 to 21
    bne !t5_fail+
    lda #$01
    sta tc_results + 4
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 4

    // ==========================================
    // Test 6: Monster blocked by wall finds alternate path
    // Wall in diagonal, should try horizontal or vertical
    // ==========================================
!t6:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Set up: monster at (20,15), player at (22,14)
    // Block diagonal (21,14) with a wall, leave (21,15) and (20,14) as floor

    // Floor at (20,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    // Floor at (21,15)
    ldy #21
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    // Floor at (22,15)
    ldy #22
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Row 14: wall at (21,14), floor at (20,14), floor at (22,14)
    ldx #14
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    ldy #21
    lda #TILE_WALL_H | FLAG_LIT // Wall blocks diagonal
    sta (zp_ptr0),y
    ldy #22
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Spawn monster at (20,15)
    lda #20
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #4                      // Kobold
    jsr monster_spawn_one

    // Set awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    // Player at (22,14)
    lda #22
    sta zp_player_x
    lda #14
    sta zp_player_y

    // Run AI tick — diagonal (21,14) is wall, should try horizontal (21,15)
    jsr monster_ai_tick

    // Monster should have moved — either (21,15) horizontal or (20,14) vertical
    // Both are valid due to random horizontal/vertical swap in unstick heuristic
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    sta tai_save_x
    ldy #MX_Y
    lda (zp_ptr0),y
    sta tai_save_y
    // Accept (21,15)
    lda tai_save_x
    cmp #21
    bne !t6_try_vert+
    lda tai_save_y
    cmp #15
    beq !t6_pass+
!t6_try_vert:
    // Accept (20,14)
    lda tai_save_x
    cmp #20
    bne !t6_fail+
    lda tai_save_y
    cmp #14
    bne !t6_fail+
!t6_pass:
    lda #$01
    sta tc_results + 5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 5

    // ==========================================
    // Test 7: Monster stays in place when adjacent to player
    // (now it attacks instead of just blocking, but still stays put)
    // ==========================================
!t7:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Restore keyboard buffer
    lda #8
    sta $c6

    // Reset HP before combat
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Floor at (25,15) and (26,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #25
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    ldy #26
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Spawn monster at (25,15)
    lda #25
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #4                      // Kobold
    jsr monster_spawn_one

    // Set awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    // Player at (26,15) — adjacent!
    lda #26
    sta zp_player_x
    lda #15
    sta zp_player_y

    // Run AI tick — monster attacks but stays in place
    jsr monster_ai_tick

    // Monster should stay at (25,15)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #25
    bne !t7_fail+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #15
    bne !t7_fail+

    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // ==========================================
    // Test 8: Speed 2 monster moves twice per tick
    // Type 14 (Huge brown bat) — speed=2
    // ==========================================
!t8:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Create floor corridor from (20,15) to (30,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
!t8_fill:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #31
    bne !t8_fill-

    // Spawn huge brown bat at (20,15)
    lda #20
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #14                     // Huge brown bat (speed=2)
    jsr monster_spawn_one

    // Set awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    // Player at (30,15) — distance=10
    lda #30
    sta zp_player_x
    lda #15
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Monster should be at (22,15) — moved 2 tiles (speed=2)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #22
    bne !t8_fail+

    lda #$01
    sta tc_results + 7
    jmp !t9+
!t8_fail:
    lda #$00
    sta tc_results + 7

    // ==========================================
    // Test 9: FLAG_OCCUPIED updated correctly on move
    // Old tile should have flag cleared, new tile should have it set
    // ==========================================
!t9:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Floor at (20,20) and (21,20)
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    ldy #21
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Spawn Kobold at (20,20)
    lda #20
    sta ms_spawn_x
    lda #20
    sta ms_spawn_y
    lda #3
    jsr monster_spawn_one

    // Set awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    // Player at (30,20)
    lda #30
    sta zp_player_x
    lda #20
    sta zp_player_y

    // Run AI tick — monster should move from (20,20) to (21,20)
    jsr monster_ai_tick

    // Check old tile (20,20) — FLAG_OCCUPIED should be CLEAR
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    bne !t9_fail+

    // Check new tile (21,20) — FLAG_OCCUPIED should be SET
    ldy #21
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    beq !t9_fail+

    lda #$01
    sta tc_results + 8
    jmp !t10+
!t9_fail:
    lda #$00
    sta tc_results + 8

    // ==========================================
    // Test 10: Confused monster moves randomly
    // Run several times, check that position changes at least once
    // ==========================================
!t10:
    lda #0
    sta tai_ok                  // Track if any movement happened
    sta zp_game_flags

    lda #5
    sta tai_count               // Try up to 5 iterations

!t10_retry:
    jsr monster_init_table

    // Create a 5x5 floor area around (25,25) for random movement
    ldx #23
!t10_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #23
!t10_col:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #28
    bne !t10_col-
    inx
    cpx #28
    bne !t10_row-

    // Spawn Kobold at (25,25)
    lda #25
    sta ms_spawn_x
    lda #25
    sta ms_spawn_y
    lda #4
    jsr monster_spawn_one

    // Set awake, then set MX_CONFUSE timer
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_CONFUSE
    lda #5
    sta (zp_ptr0),y

    // Player far away (won't affect direction)
    lda #5
    sta zp_player_x
    lda #5
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Check if monster moved from (25,25)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #25
    bne !t10_moved+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #25
    beq !t10_nomove+

!t10_moved:
    lda #1
    sta tai_ok

!t10_nomove:
    dec tai_count
    bne !t10_retry-

    // After 5 tries, check if at least one moved
    lda tai_ok
    beq !t10_fail+
    lda #$01
    sta tc_results + 9
    jmp !t11+
!t10_fail:
    lda #$00
    sta tc_results + 9

    // ==========================================
    // Test 11: monster_can_cast with spell_chance=0 → carry clear
    // All tier 0 creatures have spell_chance=0
    // ==========================================
!t11:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Set up a monster (type 0, spell_chance=0)
    lda #0
    sta zp_mon_type
    lda #20
    sta zp_mon_x
    lda #20
    sta zp_mon_y

    // Player nearby
    lda #21
    sta zp_player_x
    lda #20
    sta zp_player_y

    jsr monster_can_cast
    bcs !t11_fail+

    lda #$01
    sta tc_results + 10
    jmp !t12+
!t11_fail:
    lda #$00
    sta tc_results + 10

    // ==========================================
    // Test 12: monster_can_cast with spell_chance=100 and in range/LOS
    // → carry set
    // ==========================================
!t12:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Restore keyboard buffer
    lda #8
    sta $c6

    // Temporarily set spell_chance[0] = 100, spell_flags[0] = 1
    lda #100
    sta cr_spell_chance
    lda #MSF_BOLT
    sta cr_spell_flags

    // Create floor tiles between monster and player for LOS
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
!t12_fill:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #20
    bne !t12_fill-

    // Set up monster at (10, 15)
    lda #0
    sta zp_mon_type
    lda #10
    sta zp_mon_x
    lda #15
    sta zp_mon_y

    // Player at (15, 15) — distance 5, within MAX_CAST_RANGE
    lda #15
    sta zp_player_x
    lda #15
    sta zp_player_y

    jsr monster_can_cast
    bcc !t12_fail+

    lda #$01
    sta tc_results + 11
    jmp !t12_cleanup+
!t12_fail:
    lda #$00
    sta tc_results + 11

!t12_cleanup:
    // Restore spell_chance and flags
    lda #0
    sta cr_spell_chance
    sta cr_spell_flags

    // ==========================================
    // Test 13: monster_can_cast with LOS blocked by wall → carry clear
    // ==========================================
!t13:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Set spell_chance[0] = 100
    lda #100
    sta cr_spell_chance
    lda #MSF_BOLT
    sta cr_spell_flags

    // Create floor at (10,15) and (12,15), wall at (11,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    ldy #11
    lda #TILE_WALL_H | FLAG_LIT   // Wall blocks LOS
    sta (zp_ptr0),y
    ldy #12
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Monster at (10, 15)
    lda #0
    sta zp_mon_type
    lda #10
    sta zp_mon_x
    lda #15
    sta zp_mon_y

    // Player at (12, 15) — wall at (11,15) blocks LOS
    lda #12
    sta zp_player_x
    lda #15
    sta zp_player_y

    jsr monster_can_cast
    bcs !t13_fail+

    lda #$01
    sta tc_results + 12
    jmp !t13_cleanup+
!t13_fail:
    lda #$00
    sta tc_results + 12

!t13_cleanup:
    lda #0
    sta cr_spell_chance
    sta cr_spell_flags

    // ==========================================
    // Test 14: Breath weapon damage = HP/3
    // Set monster HP to 30, breath should do 10 damage
    // ==========================================
!t14:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Restore keyboard buffer
    lda #8
    sta $c6

    // Reset player HP
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Set spell data for creature type 0
    lda #100
    sta cr_spell_chance
    lda #MSF_BREATH
    sta cr_spell_flags

    // Create floor at spawn position
    ldx #18
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Spawn monster type 0 at (10, 18)
    lda #10
    sta ms_spawn_x
    lda #18
    sta ms_spawn_y
    lda #0
    jsr monster_spawn_one

    // Set monster HP to 30 (known value)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #30
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y

    // Set up ZP scratch for monster_pick_spell
    lda #0
    sta zp_mon_type
    sta zp_mon_idx

    // Call monster_pick_spell directly (breath handler)
    jsr monster_pick_spell

    // Player HP should be 200 - 10 = 190
    lda zp_player_hp_lo
    cmp #190
    bne !t14_fail+
    lda zp_player_hp_hi
    cmp #0
    bne !t14_fail+

    lda #$01
    sta tc_results + 13
    jmp !t14_cleanup+
!t14_fail:
    lda #$00
    sta tc_results + 13

!t14_cleanup:
    lda #0
    sta cr_spell_chance
    sta cr_spell_flags

    // ==========================================
    // Test 15: monster_cast_heal restores monster HP
    // ==========================================
!t15:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Restore keyboard buffer
    lda #8
    sta $c6

    // Set spell data for creature type 0 — heal only
    lda #100
    sta cr_spell_chance
    lda #MSF_HEAL
    sta cr_spell_flags

    // Create floor at spawn position
    ldx #19
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Spawn monster type 0 at (10, 19)
    lda #10
    sta ms_spawn_x
    lda #19
    sta ms_spawn_y
    lda #0
    jsr monster_spawn_one

    // Set monster HP to 1 (reduced HP)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #1
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y

    // Set up ZP scratch for monster_pick_spell
    lda #0
    sta zp_mon_type
    sta zp_mon_idx

    // Call monster_pick_spell (will pick heal since it's the only spell)
    jsr monster_pick_spell

    // Monster HP should be > 1 (healed by 3d8 = 3-24)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #2
    bcc !t15_fail+             // HP < 2 means heal didn't work

    lda #$01
    sta tc_results + 14
    jmp !t16+
!t15_fail:
    lda #$00
    sta tc_results + 14

    // ==========================================
    // Test 16: Full HP monster moves TOWARD player (regression guard)
    // Spawn with full HP, flee_threshold = HP/4, so HP > threshold
    // ==========================================
!t16:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Restore keyboard buffer
    lda #8
    sta $c6

    // Create floor corridor from (20,15) to (30,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
!t16_fill:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #31
    bne !t16_fill-

    // Spawn Kobold at (20,15) — full HP
    lda #20
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #4                      // Kobold (speed=1, mobile)
    jsr monster_spawn_one

    // Set awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    // Player at (30, 15) — monster should move toward
    lda #30
    sta zp_player_x
    lda #15
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Monster should have moved from x=20 to x=21 (toward player)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #21
    bne !t16_fail+

    lda #$01
    sta tc_results + 15
    jmp !t17+
!t16_fail:
    lda #$00
    sta tc_results + 15

    // ==========================================
    // Test 17: Low HP monster moves AWAY from player
    // Set HP=1, flee_threshold=5 → HP < threshold → flees
    // ==========================================
!t17:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Restore keyboard buffer
    lda #8
    sta $c6

    // Create floor corridor from (20,15) to (30,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #15
!t17_fill:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #35
    bne !t17_fill-

    // Spawn Kobold at (25,15)
    lda #25
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #4                      // Kobold
    jsr monster_spawn_one

    // Set awake, set HP=1, set flee_threshold=5
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #1
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLEE_LO
    lda #5
    sta (zp_ptr0),y
    ldy #MX_FLEE_HI
    lda #0
    sta (zp_ptr0),y

    // Player at (30, 15) — monster should move AWAY (toward lower x)
    lda #30
    sta zp_player_x
    lda #15
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Monster should have moved from x=25 to x=24 (away from player)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #24
    bne !t17_fail+

    lda #$01
    sta tc_results + 16
    jmp !t18+
!t17_fail:
    lda #$00
    sta tc_results + 16

    // ==========================================
    // Test 18: CF_ATTACK_ONLY monster at low HP stays put
    // Type 6 (Shrieker) — can't move even when fleeing
    // ==========================================
!t18:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Restore keyboard buffer
    lda #8
    sta $c6

    // Place floor at (30, 20)
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #30
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    // Also place floor at (29, 20) for potential flee target
    ldy #29
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Spawn Shrieker at (30, 20)
    lda #30
    sta ms_spawn_x
    lda #20
    sta ms_spawn_y
    lda #6                      // Shrieker mushroom (CF_ATTACK_ONLY)
    jsr monster_spawn_one

    // Set awake, low HP, high flee threshold
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #1
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLEE_LO
    lda #5
    sta (zp_ptr0),y
    ldy #MX_FLEE_HI
    lda #0
    sta (zp_ptr0),y

    // Player at (31, 20)
    lda #31
    sta zp_player_x
    lda #20
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Monster should still be at (30, 20) — CF_ATTACK_ONLY can't move
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #30
    bne !t18_fail+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #20
    bne !t18_fail+

    lda #$01
    sta tc_results + 17
    jmp !t19+
!t18_fail:
    lda #$00
    sta tc_results + 17

    // ==========================================
    // Test 19: Confused + low HP → moves randomly (confusion overrides flee)
    // Confused movement picks random direction, NOT flee direction
    // Run multiple times, check position differs from flee path
    // ==========================================
!t19:
    lda #0
    sta tai_ok
    sta zp_game_flags

    lda #5
    sta tai_count

!t19_retry:
    jsr monster_init_table

    // Create a 5x5 floor area around (25,25)
    ldx #23
!t19_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #23
!t19_col:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #28
    bne !t19_col-
    inx
    cpx #28
    bne !t19_row-

    // Spawn Kobold at (25,25)
    lda #25
    sta ms_spawn_x
    lda #25
    sta ms_spawn_y
    lda #4
    jsr monster_spawn_one

    // Set awake, low HP, high flee threshold, MX_CONFUSE timer
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_CONFUSE
    lda #5
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #1
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLEE_LO
    lda #10
    sta (zp_ptr0),y
    ldy #MX_FLEE_HI
    lda #0
    sta (zp_ptr0),y

    // Player at (24, 25) — flee direction would be +x (to 26,25)
    // Confused movement should sometimes go other directions
    lda #24
    sta zp_player_x
    lda #25
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Check if monster moved at all (confused might fail to move)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #25
    bne !t19_moved+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #25
    beq !t19_nomove+

!t19_moved:
    lda #1
    sta tai_ok

!t19_nomove:
    dec tai_count
    beq !t19_done+
    jmp !t19_retry-
!t19_done:

    // After 5 tries, check if at least one moved (proves confusion path taken)
    lda tai_ok
    beq !t19_fail+
    lda #$01
    sta tc_results + 18
    jmp !t20+
!t19_fail:
    lda #$00
    sta tc_results + 18

    // ==========================================
    // Test 20: Confusion timer expires — monster acts normally after
    // Set MX_CONFUSE=1, run tick (confused, decrements to 0),
    // run again (timer=0, monster moves toward player)
    // ==========================================
!t20:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Create floor corridor from (20,15) to (30,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
!t20_fill:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #31
    bne !t20_fill-

    // Spawn Kobold at (20,15)
    lda #20
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #4
    jsr monster_spawn_one

    // Set awake, MX_CONFUSE=1
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_CONFUSE
    lda #1
    sta (zp_ptr0),y

    // Player at (30,15)
    lda #30
    sta zp_player_x
    lda #15
    sta zp_player_y

    // Tick 1: confused (timer=1 → decremented to 0, random move)
    jsr monster_ai_tick

    // Read monster position after first tick (could be anywhere nearby)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    sta tai_save_x
    ldy #MX_Y
    lda (zp_ptr0),y
    sta tai_save_y

    // Verify confuse timer is now 0
    ldy #MX_CONFUSE
    lda (zp_ptr0),y
    bne !t20_fail+

    // Clear occupied flag at the actual first-tick destination before
    // teleporting the monster back for the deterministic second tick.
    ldx tai_save_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy tai_save_x
    lda (zp_ptr0),y
    and #($ff - FLAG_OCCUPIED)
    sta (zp_ptr0),y

    // Re-place monster at (20,15) for clean second tick
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda #20
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #15
    sta (zp_ptr0),y
    // Clear FLAG_OCCUPIED on old tile, set on (20,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    ora #FLAG_OCCUPIED
    sta (zp_ptr0),y

    // Tick 2: timer=0, should move toward player (x=20 → x=21)
    jsr monster_ai_tick

    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #21                     // Should have moved toward player
    bne !t20_fail+

    lda #$01
    sta tc_results + 19
    jmp !t21+
!t20_fail:
    lda #$00
    sta tc_results + 19

    // ==========================================
    // Test 21: Stun skips monster turn entirely
    // Set MX_STUN=1, run tick (stunned, decrements to 0, no move),
    // run again (timer=0, monster moves normally)
    // ==========================================
!t21:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Create floor corridor from (20,15) to (30,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
!t21_fill:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #31
    bne !t21_fill-

    // Spawn Kobold at (25,15)
    lda #25
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #4
    jsr monster_spawn_one

    // Set awake, MX_STUN=1
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_STUN
    lda #1
    sta (zp_ptr0),y

    // Player at (30,15)
    lda #30
    sta zp_player_x
    lda #15
    sta zp_player_y

    // Tick 1: stunned — monster should stay at (25,15)
    jsr monster_ai_tick

    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #25
    bne !t21_fail+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #15
    bne !t21_fail+

    // Verify stun timer is now 0
    ldy #MX_STUN
    lda (zp_ptr0),y
    bne !t21_fail+

    // Tick 2: timer=0, should move toward player (x=25 → x=26)
    jsr monster_ai_tick

    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #26                     // Should have moved toward player
    bne !t21_fail+

    lda #$01
    sta tc_results + 20
    jmp !t22+
!t21_fail:
    lda #$00
    sta tc_results + 20

    // ==========================================
    // Test 22: summon spell marks scene dirty through monster_ai_tick
    // Spellcasts that change visible state must force the shared full-render path.
    // ==========================================
!t22:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    // Clear a 5x5 floor area around the caster so summon cannot fail on adjacency.
    ldx #13
!t22_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #23
!t22_col:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #28
    bne !t22_col-
    inx
    cpx #18
    bne !t22_row-

    // Spawn caster at (25,15) and force summon-only casting.
    lda #25
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #0
    jsr monster_spawn_one

    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    lda #100
    sta cr_spell_chance
    lda #MSF_SUMMON
    sta cr_spell_flags

    lda #27
    sta zp_player_x
    lda #15
    sta zp_player_y

    jsr monster_ai_tick
    bcc !t22_fail+

    lda zp_mon_count
    cmp #2
    bcc !t22_fail+

    lda #$01
    sta tc_results + 21
    jmp !t22_cleanup+
!t22_fail:
    lda #$00
    sta tc_results + 21
!t22_cleanup:
    lda #0
    sta cr_spell_chance
    sta cr_spell_flags
    jmp !t23+

    // ==========================================
    // Test 23: the live sleep counter, not the
    // species base sleep value, controls waking.
    // ==========================================
!t23:
    jsr monster_init_table
    lda #0
    sta zp_game_flags

    lda #8
    sta $c6

    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
!t23_fill:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #31
    bne !t23_fill-

    lda #20
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #4
    jsr monster_spawn_one

    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    lda #2
    sta (zp_ptr0),y

    lda #20
    sta zp_player_x
    lda #15
    sta zp_player_y

    ldx #0
    stx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    sta zp_mon_x
    ldy #MX_Y
    lda (zp_ptr0),y
    sta zp_mon_y
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta zp_mon_type
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    sta zp_mon_flags

    jsr monster_wake_check

    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    cmp #1
    bne !t23_fail+
    lda zp_mon_flags
    and #MF_AWAKE
    bne !t23_fail+

    jsr monster_wake_check

    ldx #0
    jsr monster_get_ptr
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    bne !t23_fail+
    lda zp_mon_flags
    and #MF_AWAKE
    beq !t23_fail+

    lda #$01
    sta tc_results + 22
    jmp !t24+
!t23_fail:
    lda #$00
    sta tc_results + 22

    // ==========================================
    // Test 24: nearby monster movement should not
    // promote the non-local redraw latch.
    // ==========================================
!t24:
    lda #0
    sta mat_scene_dirty
    sta eff_detect_timer

    lda #20
    sta zp_player_x
    sta old_player_x
    lda #15
    sta zp_player_y
    sta old_player_y
    lda #0
    sta zp_view_x
    sta old_view_x
    sta zp_view_y
    sta old_view_y
    lda #1
    sta zp_light_radius

    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
!t24_fill:
    lda #TILE_FLOOR | FLAG_VISITED
    sta (zp_ptr0),y
    iny
    cpy #24
    bne !t24_fill-

    lda #4
    sta zp_mon_type
    lda #22
    ldy #15
    jsr mat_mark_tile_dirty_if_nonlocal
    lda mat_scene_dirty
    bne !t24_fail+

    lda #$01
    sta tc_results + 23
    jmp !t25+
!t24_fail:
    lda #$00
    sta tc_results + 23

    // ==========================================
    // Test 25: remote lit-room movement still
    // promotes the non-local redraw latch.
    // ==========================================
!t25:
    lda #0
    sta mat_scene_dirty
    sta eff_detect_timer

    lda #20
    sta zp_player_x
    sta old_player_x
    lda #15
    sta zp_player_y
    sta old_player_y
    lda #0
    sta zp_view_x
    sta old_view_x
    sta zp_view_y
    sta old_view_y
    lda #1
    sta zp_light_radius

    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
!t25_fill:
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #30
    bne !t25_fill-

    lda #4
    sta zp_mon_type
    lda #28
    ldy #15
    jsr mat_mark_tile_dirty_if_nonlocal
    lda mat_scene_dirty
    cmp #1
    bne !t25_fail+

    lda #$01
    sta tc_results + 24
    jmp !t26+
!t25_fail:
    lda #$00
    sta tc_results + 24

    // ==========================================
    // Test 26: glyphs use umoria break odds and
    // a broken glyph stops blocking the player tile.
    // ==========================================
!t26:
    :PatchJump(rng_range_word, test_rng_range_word)
    lda #4
    sta zp_mon_type
    lda #20
    sta cr_level + 4

    :PatchJump(monster_attack_player, test_monster_attack_player)
    jsr glyph_clear_all
    lda #20
    sta zp_player_x
    lda #15
    sta zp_player_y
    lda zp_player_x
    ldy zp_player_y
    jsr glyph_add_at
    bcs !t26_add_ok+
    jmp !t26_fail+
!t26_add_ok:
    lda #0
    sta tai_rng_idx
    lda #19                     // 19 is not < level-1 (19): glyph holds
    sta tai_rng_values + 0
    lda #0
    sta tai_rng_values + 1
    lda #0
    sta tai_attack_calls
    sta mat_action_dirty
    sta mat_fleeing
    lda zp_player_x
    sta mat_target_x
    lda zp_player_y
    sta mat_target_y
    jsr monster_try_step
    lda glyph_active + 0
    beq !t26_fail+
    lda tai_attack_calls
    bne !t26_fail+

    jsr glyph_clear_all
    lda zp_player_x
    ldy zp_player_y
    jsr glyph_add_at
    bcc !t26_fail+
    lda #0
    sta tai_rng_idx
    lda #4
    sta zp_mon_type
    lda #18                     // 18 is < level-1 (19): glyph breaks
    sta tai_rng_values + 0
    lda #0
    sta tai_rng_values + 1
    sta tai_attack_calls
    sta mat_action_dirty
    sta mat_fleeing
    lda zp_player_x
    sta mat_target_x
    lda zp_player_y
    sta mat_target_y
    jsr monster_try_step
    lda glyph_active + 0
    bne !t26_fail+
    lda tai_attack_calls
    cmp #1
    beq !t26_attack_ok+
    jmp !t26_fail+
!t26_attack_ok:
    lda #$01
    sta tc_results + 25
    jmp !tests_done+
!t26_fail:
    lda #$00
    sta tc_results + 25

!tests_done:
    jmp test_finish

test_end:

.assert "Monster AI test body must stay below MAP_BASE", test_end < MAP_BASE, true
