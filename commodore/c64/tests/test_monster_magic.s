// test_monster_magic.s — Runtime tests for monster_magic.s
//
// Tests: monster_can_cast (4 tests), monster_cast_bolt, monster_cast_breath,
//        monster_cast_blind, monster_cast_heal.
//
// Results at $0400-$0407: $01 = pass, $00 = fail per test
// NOTE: msg_print writes to screen row 0 ($0400+), so we store results
// in tc_results[] and copy to $0400 at the very end.

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
#import "../ui_help_clear.s"
#import "../ui_character.s"
#import "../stat_display.s"
#import "../player_create.s"
#import "../sound.s"
#import "../dungeon_gen.s"
#import "../huffman.s"
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
tc_results: .fill 8, $ff      // Result buffer (copied to $0400 at end)

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

    // Set up basic player state
    lda #100
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    sta zp_game_flags

    // Generate a dungeon to get a valid map for LOS checks
    lda #3
    sta zp_player_dlvl
    jsr dungeon_generate

    // Place player at a known position
    lda #10
    sta zp_player_x
    lda #10
    sta zp_player_y

    // ==========================================
    // Test 1: monster_can_cast returns clear for spell_chance=0
    // Type 0 (White Harpy) has cr_spell_chance = 0
    // ==========================================
    lda #0
    sta zp_mon_type             // White Harpy
    lda #12
    sta zp_mon_x                // Place nearby
    lda #10
    sta zp_mon_y

    jsr monster_can_cast
    bcs !t1_fail+               // Should NOT set carry
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // ==========================================
    // Test 2: monster_can_cast returns set for high chance
    // Type 20 (Kobold Shaman, chance=30)
    // Temporarily override to 100 for deterministic test
    // Place monster within range, ensure clear LOS (floor tiles)
    // ==========================================
!t2:
    // Re-stuff keyboard buffer (msg_print may have consumed some)
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

    lda #0
    sta zp_msg_flags

    // Find player's room — place player on a floor tile and monster nearby
    // Use a simple approach: find floor at (10,10), place monster at (12,10)
    // First ensure both positions are floor tiles
    lda #20                     // Kobold Shaman
    sta zp_mon_type

    // Save original spell chance, override to 100 for deterministic pass
    ldx #20
    lda cr_spell_chance,x
    sta tc_ok                   // Save original
    lda #100
    sta cr_spell_chance,x       // 100% chance

    // Place monster on floor near player — find suitable floor tiles
    // Use player position from dungeon gen
    lda zp_player_x
    sta zp_mon_x
    lda zp_player_y
    clc
    adc #1
    sta zp_mon_y

    // Ensure monster tile is walkable (place floor if needed)
    ldx zp_mon_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_mon_x
    lda #TILE_FLOOR             // Force floor tile
    sta (zp_ptr0),y

    // Also ensure player tile is floor
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    lda #TILE_FLOOR
    sta (zp_ptr0),y

    jsr monster_can_cast
    bcc !t2_fail+               // Should set carry (100% chance)

    lda #$01
    sta tc_results + 1
    jmp !t2_restore+
!t2_fail:
    lda #$00
    sta tc_results + 1
!t2_restore:
    // Restore original spell chance
    ldx #20
    lda tc_ok
    sta cr_spell_chance,x

    // ==========================================
    // Test 3: monster_can_cast fails when out of range (>8 tiles)
    // ==========================================
!t3:
    lda #20                     // Kobold Shaman
    sta zp_mon_type

    // Override chance to 100
    ldx #20
    lda #100
    sta cr_spell_chance,x

    // Place monster 12 tiles away
    lda zp_player_x
    clc
    adc #12
    sta zp_mon_x
    lda zp_player_y
    sta zp_mon_y

    jsr monster_can_cast
    bcs !t3_fail+               // Should NOT set carry (out of range)
    lda #$01
    sta tc_results + 2
    jmp !t3_restore+
!t3_fail:
    lda #$00
    sta tc_results + 2
!t3_restore:
    // Restore spell chance
    ldx #20
    lda tc_ok
    sta cr_spell_chance,x

    // ==========================================
    // Test 4: monster_can_cast fails with wall blocking LOS
    // Place monster 3 tiles away with a wall between
    // ==========================================
!t4:
    lda #0
    sta zp_msg_flags

    lda #20                     // Kobold Shaman
    sta zp_mon_type

    // Override chance to 100
    ldx #20
    lda #100
    sta cr_spell_chance,x

    // Place monster 3 tiles to the right of player
    lda zp_player_x
    clc
    adc #3
    sta zp_mon_x
    lda zp_player_y
    sta zp_mon_y

    // Ensure monster tile is floor
    ldx zp_mon_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_mon_x
    lda #TILE_FLOOR
    sta (zp_ptr0),y

    // Place a wall between player and monster (at player_x + 1)
    lda zp_player_x
    clc
    adc #1
    tay
    // Same row as monster, ptr0 still valid
    lda #TILE_WALL_H            // $10 — horizontal wall (not walkable)
    sta (zp_ptr0),y

    jsr monster_can_cast
    bcs !t4_fail+               // Should NOT set carry (wall blocks LOS)
    lda #$01
    sta tc_results + 3
    jmp !t4_restore+
!t4_fail:
    lda #$00
    sta tc_results + 3
!t4_restore:
    // Restore wall tile to floor (cleanup)
    ldx zp_mon_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    lda zp_player_x
    clc
    adc #1
    tay
    lda #TILE_FLOOR
    sta (zp_ptr0),y

    // Restore spell chance
    ldx #20
    lda tc_ok
    sta cr_spell_chance,x

    // ==========================================
    // Test 5: Bolt damage range check
    // Call monster_cast_bolt with type 20 (Kobold Shaman, level 3)
    // Damage = 2d8 + 3, range [5, 19]
    // Run 10 trials, verify all in range
    // ==========================================
!t5:
    lda #0
    sta zp_msg_flags

    // Re-stuff keyboard buffer
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
    sta tc_ok                   // Assume pass
    lda #10
    sta tc_loop

!t5_loop:
    // Reset player HP to 100 before each trial
    lda #100
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    sta zp_game_flags
    sta zp_msg_flags

    lda #20                     // Kobold Shaman (level 3)
    sta zp_mon_type
    lda #0
    sta zp_mon_idx              // Dummy slot

    jsr monster_cast_bolt

    // Damage = 100 - remaining HP
    lda #100
    sec
    sbc zp_player_hp_lo         // A = damage dealt

    // Check range [5, 19]
    cmp #5
    bcc !t5_out+                // Too low
    cmp #20
    bcc !t5_in+                 // < 20 → in range
!t5_out:
    lda #0
    sta tc_ok
!t5_in:
    dec tc_loop
    bne !t5_loop-

    lda tc_ok
    sta tc_results + 4

    // ==========================================
    // Test 6: Breath damage = HP/3
    // Set monster HP to 30, call monster_cast_breath
    // Expected damage = 10
    // ==========================================
!t6:
    lda #0
    sta zp_msg_flags

    // Re-stuff keyboard buffer
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

    // Reset player HP
    lda #100
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    sta zp_game_flags

    // Set up a monster in slot 0 with HP=30
    jsr monster_init_table
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #24                     // Giant Salamander
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #30
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_X
    lda #12
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #12
    sta (zp_ptr0),y

    lda #24
    sta zp_mon_type
    lda #0
    sta zp_mon_idx

    jsr monster_cast_breath

    // Damage = 100 - remaining HP; expect 10 (30/3)
    lda #100
    sec
    sbc zp_player_hp_lo
    cmp #10
    bne !t6_fail+
    lda #$01
    sta tc_results + 5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 5

    // ==========================================
    // Test 7: Blind sets timer in range [11, 20]
    // monster_cast_blind rolls 1d10+10
    // ==========================================
!t7:
    lda #0
    sta zp_msg_flags
    sta zp_eff_blind

    // Re-stuff keyboard buffer
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

    lda #22                     // Novice Mage
    sta zp_mon_type

    jsr monster_cast_blind

    // Check zp_eff_blind in [11, 20]
    lda zp_eff_blind
    cmp #11
    bcc !t7_fail+               // < 11
    cmp #21
    bcs !t7_fail+               // >= 21
    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // ==========================================
    // Test 8: Heal caps at max HP
    // Set monster HP to 1, max = 6*8 = 48 (Giant Salamander)
    // After heal (3d8, range [3,24]), HP should be in [4, 48]
    // ==========================================
!t8:
    lda #0
    sta zp_msg_flags

    // Re-stuff keyboard buffer
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

    // Set up monster in slot 0 with HP=1, type 24 (Giant Salamander, 6d8 max=48)
    jsr monster_init_table
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #24
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #1
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_X
    lda #12
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #12
    sta (zp_ptr0),y

    lda #24
    sta zp_mon_type
    lda #0
    sta zp_mon_idx

    jsr monster_cast_heal

    // Read monster HP — should be in [4, 48]
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    // Check >= 4
    cmp #4
    bcc !t8_fail+
    // Check <= 48
    cmp #49
    bcs !t8_fail+
    // Check hi byte is 0
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    bne !t8_fail+

    lda #$01
    sta tc_results + 7
    jmp !tests_done+
!t8_fail:
    lda #$00
    sta tc_results + 7

!tests_done:
    jmp test_exit_trampoline
