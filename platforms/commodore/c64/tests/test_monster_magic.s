// test_monster_magic.s — Runtime tests for monster_magic.s
//
// Tests: monster_can_cast (4 tests), wound/blind/confuse/fear spells against
//        VMS Moria cast_spell (MON-011), monster_cast_breath, the shared
//        player saving throw (player_save.s) and the paralysis touch save.
//
// Results at $0400-$0419: $01 = pass, $00 = fail per test
// NOTE: msg_print writes to screen row 0 ($0400+), so we store results
// in tc_results[] and copy to $0400 at the very end.
.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #25
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

#define COMPILE_EMBEDDED_DUNGEON_TEST_ROSTER

player_cast_spell:
    rts

player_pray:
    rts

magic_recalc_mana:
    rts

magic_check_new_spells:
    rts

#import "../../../../core/zeropage.s"
#import "../memory.s"
#define REU_DETECT_EXTERNAL      // not exercised here; frees room below MAP_BASE
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
.segment TestCreateOverlay
#import "../../../../core/background_data.s"
#import "../../../../core/player_create.s"
.segment Default
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
#import "../../../../core/special_rooms_stubs.s"
#import "../../../../core/player_items.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"
ui_help_display:
store_init_all:
store_restock_all:
store_enter:
    rts
#import "../../../../core/ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_loop:    .byte 0
tc_ok:      .byte 0
tc_results: .fill 26, $ff      // Result buffer (copied to $0400 at end)

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
    // Test 5: Cause Light Wounds = 3d8 when the save fails (VMS spell 8),
    // and the save adjustment is wis_adj + level (VMS player_saves).
    // Wisdom 18 -> wis_adj 3, level 5 -> adjustment 8.
    // ==========================================
!t5:
    jsr tst_patch_save
    lda #0
    sta tst_save_mode            // Player fails every save
    lda #18
    sta player_data + PL_WIS_CUR
    lda #5
    sta zp_player_lvl
    lda #1
    sta tc_ok
    lda #10
    sta tc_loop
!t5_loop:
    jsr tst_prep
    lda #20                      // Kobold Shaman
    sta zp_mon_type
    lda #0
    sta zp_mon_idx
    lda #$ee
    sta tst_save_adj
    jsr monster_cast_wound_light
    lda #100
    sec
    sbc zp_player_hp_lo          // A = damage dealt
    cmp #3
    bcc !t5_bad+
    cmp #25
    bcs !t5_bad+
    lda tst_save_adj
    cmp #8
    beq !t5_next+
!t5_bad:
    lda #0
    sta tc_ok
!t5_next:
    dec tc_loop
    bne !t5_loop-
    lda tc_ok
    sta tc_results + 4
    jsr tst_unpatch_save

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
    // Test 7: Blind, save failed, not already blind: 12 + randint(3)
    // (VMS spell 11) -> timer in [13, 15] on each of 10 trials.
    // ==========================================
!t7:
    jsr tst_patch_save
    lda #0
    sta tst_save_mode
    lda #1
    sta tc_ok
    lda #10
    sta tc_loop
!t7_loop:
    jsr tst_prep
    lda #0
    sta zp_eff_blind
    lda #22                      // Novice Mage
    sta zp_mon_type
    jsr monster_cast_blind
    lda zp_eff_blind
    cmp #13
    bcc !t7_bad+
    cmp #16
    bcc !t7_next+
!t7_bad:
    lda #0
    sta tc_ok
!t7_next:
    dec tc_loop
    bne !t7_loop-
    lda tc_ok
    sta tc_results + 6

    // ==========================================
    // Test 8: Spell bit 6 dispatches Cause Serious Wounds (VMS spell 9):
    // 8d8 damage on each of 10 trials, at least one above 3d8's maximum of
    // 24, and the caster's HP unchanged (no monster heal spell).
    // ==========================================
!t8:
    lda #1
    sta tc_ok
    lda #0
    sta tst_max                  // Highest damage seen
    lda #10
    sta tc_loop
!t8_loop:
    jsr tst_prep
    jsr monster_init_table
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #20
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #10
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    lda cr_spell_flags + 20
    pha
    lda #MSF_WOUND_SERIOUS
    sta cr_spell_flags + 20
    lda #20
    sta zp_mon_type
    lda #0
    sta zp_mon_idx
    lda #0
    sta tst_save_mode
    jsr monster_pick_spell
    pla
    sta cr_spell_flags + 20
    lda #100
    sec
    sbc zp_player_hp_lo          // A = damage dealt
    cmp #8
    bcc !t8_bad+
    cmp #65
    bcs !t8_bad+
    cmp tst_max
    bcc !t8_hp+
    sta tst_max
!t8_hp:
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #10
    beq !t8_next+
!t8_bad:
    lda #0
    sta tc_ok
!t8_next:
    dec tc_loop
    bne !t8_loop-
    lda tst_max
    cmp #25
    bcs !t8_store+
    lda #0
    sta tc_ok
!t8_store:
    lda tc_ok
    sta tc_results + 7
    jsr tst_unpatch_save

    // ==========================================
    // Test 9: Active resist reduces breath damage
    // Set monster HP to 30, breath would do 10; resist reduces to 3
    // ==========================================
!t9:
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

    // Reset player HP and enable timed resist
    lda #100
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    sta zp_game_flags
    lda #$03
    sta zp_eff_resist
    lda #0
    sta eff_resist_cold_timer

    // Set up a monster in slot 0 with HP=30
    jsr monster_init_table
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #24
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

    // Damage = 100 - remaining HP; expect 3 (10/3)
    lda #100
    sec
    sbc zp_player_hp_lo
    cmp #3
    bne !t9_fail+
    lda #$01
    sta tc_results + 8
    jmp !t10+
!t9_fail:
    lda #$00
    sta tc_results + 8

    // Test 10: Cold-only resistance does not reduce current fire breath.
!t10:
    lda #0
    sta zp_msg_flags

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

    lda #100
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    sta zp_game_flags
    sta zp_eff_resist
    lda #$03
    sta eff_resist_cold_timer

    jsr monster_init_table
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #24
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

    lda #100
    sec
    sbc zp_player_hp_lo
    cmp #10
    bne !t10_fail+
    lda #$01
    sta tc_results + 9
    jmp !t11+
!t10_fail:
    lda #$00
    sta tc_results + 9

    // Test 11: Holy Word invulnerability blocks monster spell damage.
!t11:
    lda #50
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #3
    sta eff_invuln_timer
    lda #10
    jsr mm_apply_spell_damage
    lda zp_player_hp_lo
    cmp #50
    bne !t11_fail+
    lda zp_player_hp_hi
    beq !t11_ok+
!t11_fail:
    lda #$00
    sta tc_results + 10
    jmp !t12+
!t11_ok:
    lda #$01
    sta tc_results + 10

    // Test 12: diagonal room-wall geometry blocks monster_can_cast.
    // Regresses snapshot case: Magic User at (45,10), player at (49,6),
    // with wall tiles at (46,9) and (47,8).
!t12:
    lda #0
    sta zp_msg_flags
    sta zp_eff_blind

    lda #49
    sta zp_player_x
    lda #6
    sta zp_player_y

    lda #22                     // Novice Mage; embedded caster with spells
    sta zp_mon_type
    lda #45
    sta zp_mon_x
    lda #10
    sta zp_mon_y

    ldx #22
    lda cr_spell_chance,x
    pha
    lda #100
    sta cr_spell_chance,x

    ldx #6
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #49
    lda #TILE_FLOOR
    sta (zp_ptr0),y

    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #45
    lda #TILE_FLOOR
    sta (zp_ptr0),y

    ldx #9
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #46
    lda #TILE_WALL_H
    sta (zp_ptr0),y

    ldx #8
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #47
    lda #TILE_WALL_H | FLAG_VISITED | FLAG_LIT
    sta (zp_ptr0),y

    lda #49
    sta zp_los_dx
    lda #6
    sta zp_los_dy
    lda #45
    sta mm_los_cx
    lda #10
    sta mm_los_cy
    jsr mm_los_clear_to_target
    bcs !t12_fail+
    lda #$01
    sta tc_results + 11
    jmp !t13+
!t12_fail:
    lda #$00
    sta tc_results + 11

    // Test 13: blocked diagonal room-wall geometry blocks monster_can_cast.
!t13:
    jsr monster_can_cast
    bcs !t13_fail+
    lda #$01
    sta tc_results + 12
    jmp !t13_restore+
!t13_fail:
    lda #$00
    sta tc_results + 12
!t13_restore:
    pla
    sta cr_spell_chance + 22

    // Test 14: full AI cannot blind through the same blocked geometry.
!t14:
    lda #0
    sta zp_msg_flags
    sta zp_eff_blind
    sta zp_game_flags

    jsr monster_init_table
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda #45
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #10
    sta (zp_ptr0),y
    ldy #MX_TYPE
    lda #22
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #10
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_SPEED_CNT
    lda #0
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    sta (zp_ptr0),y
    ldy #MX_STUN
    sta (zp_ptr0),y
    ldy #MX_CONFUSE
    sta (zp_ptr0),y
    ldy #MX_FLEE_LO
    sta (zp_ptr0),y
    ldy #MX_FLEE_HI
    sta (zp_ptr0),y

    lda #0
    sta zp_mon_idx
    lda #22
    sta zp_mon_type
    lda #45
    sta zp_mon_x
    lda #10
    sta zp_mon_y
    lda #MF_AWAKE
    sta zp_mon_flags

    lda cr_spell_chance + 22
    pha
    lda cr_spell_flags + 22
    pha
    lda #100
    sta cr_spell_chance + 22
    lda #MSF_BLIND
    sta cr_spell_flags + 22

    jsr monster_process_one

    lda zp_eff_blind
    bne !t14_fail+
    lda #$01
    sta tc_results + 13
    jmp !t14_restore+
!t14_fail:
    lda #$00
    sta tc_results + 13
!t14_restore:
    pla
    sta cr_spell_flags + 22
    pla
    sta cr_spell_chance + 22

    // ==========================================
    // Tests 15-22: blind/confuse/fear timers and resisted spells (VMS
    // spells 11-13, MON-011). Saves are forced by the patched stub.
    // ==========================================
!t15:
    jsr tst_patch_save
    lda #0
    sta tst_save_mode
    lda #22
    sta zp_mon_type
    // Test 15: already blind 10 -> +6 = 16
    jsr tst_prep
    lda #10
    sta zp_eff_blind
    jsr monster_cast_blind
    lda zp_eff_blind
    cmp #16
    jsr tst_result_eq
    sta tc_results + 14

    // Test 16: blind resisted: timer stays 0, no damage
    jsr tst_prep
    lda #1
    sta tst_save_mode
    lda #0
    sta zp_eff_blind
    jsr monster_cast_blind
    lda zp_eff_blind
    ora #0
    jsr tst_result_eq
    sta tc_results + 15
    lda #0
    sta tst_save_mode

    // Test 17: confuse fresh: randint(5) + 3 -> [4, 8]
    jsr tst_prep
    lda #0
    sta zp_eff_confuse
    jsr monster_cast_confuse
    lda zp_eff_confuse
    ldx #4
    ldy #9
    jsr tst_result_range
    sta tc_results + 16

    // Test 18: already confused 5 -> +2 = 7
    jsr tst_prep
    lda #5
    sta zp_eff_confuse
    jsr monster_cast_confuse
    lda zp_eff_confuse
    cmp #7
    jsr tst_result_eq
    sta tc_results + 17
    lda #0
    sta zp_eff_confuse

    // Test 19: bit 7 dispatches fear: fresh randint(5) + 3 -> [4, 8],
    // and recall records spell bit 7.
    jsr tst_prep
    lda #0
    sta eff_fear_timer
    sta zp_eff_hero
    sta recall_spells + 20
    lda cr_spell_flags + 20
    pha
    lda #MSF_FEAR
    sta cr_spell_flags + 20
    lda #20
    sta zp_mon_type
    jsr monster_pick_spell
    pla
    sta cr_spell_flags + 20
    lda recall_spells + 20
    cmp #$80
    bne !t19_fail+
    lda eff_fear_timer
    ldx #4
    ldy #9
    jsr tst_result_range
    jmp !t19_store+
!t19_fail:
    lda #0
!t19_store:
    sta tc_results + 18

    // Test 20: already afraid 3 -> +2 = 5
    jsr tst_prep
    lda #3
    sta eff_fear_timer
    jsr monster_cast_fear
    lda eff_fear_timer
    cmp #5
    jsr tst_result_eq
    sta tc_results + 19

    // Test 21: heroism blocks fear even when the save fails
    jsr tst_prep
    lda #0
    sta eff_fear_timer
    lda #5
    sta zp_eff_hero
    jsr monster_cast_fear
    lda #0
    sta zp_eff_hero
    lda eff_fear_timer
    ora #0
    jsr tst_result_eq
    sta tc_results + 20

    // Test 22: Cause Light Wounds resisted: no damage
    jsr tst_prep
    lda #1
    sta tst_save_mode
    lda #20
    sta zp_mon_type
    jsr monster_cast_wound_light
    lda zp_player_hp_lo
    cmp #100
    jsr tst_result_eq
    sta tc_results + 21
    jsr tst_unpatch_save

    // ==========================================
    // Test 23: player_save_value = race save + class save + adjustment,
    // clamped at 0 (core/tables.s values; MON-011).
    // ==========================================
!t23:
    lda #1
    sta tc_ok
    lda #7                       // Half-Troll (save -8)
    sta player_data + PL_RACE
    lda #0                       // Warrior (save 18)
    sta player_data + PL_CLASS
    lda #0
    jsr player_save_value
    cmp #10
    bne !t23_fail+
    lda #<-20
    jsr player_save_value        // -8 + 18 - 20 < 0 -> 0
    cmp #0
    bne !t23_fail+
    lda #3                       // Halfling (save 18)
    sta player_data + PL_RACE
    lda #1                       // Mage (save 36)
    sta player_data + PL_CLASS
    lda #20
    jsr player_save_value
    cmp #74
    beq !t23_store+
!t23_fail:
    lda #0
    sta tc_ok
!t23_store:
    lda tc_ok
    sta tc_results + 22

    // ==========================================
    // Test 24: player_wis_save_adj matches VMS wis_adj at every threshold
    // ==========================================
!t24:
    lda #1
    sta tc_ok
    ldy #0
!t24_loop:
    lda tst_wis_in,y
    jsr player_wis_save_adj
    cmp tst_wis_out,y
    beq !t24_next+
    lda #0
    sta tc_ok
!t24_next:
    iny
    cpy #14
    bne !t24_loop-
    lda tc_ok
    sta tc_results + 23

    // ==========================================
    // Test 25: player_saving_throw (unpatched): a 0 target never saves,
    // a target above 100 always saves (roll 0..99 < target).
    // ==========================================
!t25:
    lda #7
    sta player_data + PL_RACE
    lda #0
    sta player_data + PL_CLASS
    lda #1
    sta tc_ok
    lda #50
    sta tc_loop
!t25_loop:
    lda #<-100
    jsr player_saving_throw      // target 0
    bcs !t25_ok1+
    lda #0
    sta tc_ok
!t25_ok1:
    lda #100
    jsr player_saving_throw      // target 110
    bcc !t25_ok2+
    lda #0
    sta tc_ok
!t25_ok2:
    dec tc_loop
    bne !t25_loop-
    lda tc_ok
    sta tc_results + 24

    // ==========================================
    // Test 26: paralysis touch saves with VMS con_adj (creature.inc attack
    // 11): CON 3 -> -4; a saved roll leaves the player unparalyzed, a failed
    // one paralyzes for randint(level) + 3.
    // ==========================================
!t26:
    jsr tst_patch_save
    jsr tst_prep
    lda #3
    sta player_data + PL_CON_CUR
    lda #20
    sta mat_type2
    lda #0
    sta zp_eff_paralyze
    lda #1
    sta tst_save_mode
    jsr mon_atk_effect_paralyze
    lda tst_save_adj
    cmp #<-4
    bne !t26_fail+
    lda zp_eff_paralyze
    bne !t26_fail+
    lda #0
    sta tst_save_mode
    jsr mon_atk_effect_paralyze
    lda zp_eff_paralyze
    beq !t26_fail+
    lda #$01
    sta tc_results + 25
    jmp !t26_done+
!t26_fail:
    lda #$00
    sta tc_results + 25
!t26_done:
    lda #0
    sta zp_eff_paralyze
    jsr tst_unpatch_save

!tests_done:
    jmp test_exit_trampoline

// ------------------------------------------------------------
// Helpers for tests 5-26
// ------------------------------------------------------------
tst_save_mode: .byte 0           // 0 = the player fails, 1 = the player saves
tst_save_adj:  .byte 0           // Adjustment passed to player_saving_throw
tst_save_orig: .byte 0, 0, 0
tst_max:       .byte 0           // Test 8: highest damage seen

// tst_save_stub — Replaces player_saving_throw while patched.
tst_save_stub:
    sta tst_save_adj
    lda tst_save_mode
    eor #1
    lsr                          // Carry clear when the player saves
    rts

tst_patch_save:
    ldx #2
!copy:
    lda player_saving_throw,x
    sta tst_save_orig,x
    dex
    bpl !copy-
    lda #$4c
    sta player_saving_throw
    lda #<tst_save_stub
    sta player_saving_throw + 1
    lda #>tst_save_stub
    sta player_saving_throw + 2
    rts

tst_unpatch_save:
    ldx #2
!copy:
    lda tst_save_orig,x
    sta player_saving_throw,x
    dex
    bpl !copy-
    rts

// tst_prep — Clear message state, refill the -more- keys, player HP 100.
tst_prep:
    lda #0
    sta zp_msg_flags
    sta zp_game_flags
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #100
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #8
    sta $c6
    lda #$20
    ldx #7
!fill:
    sta $0277,x
    dex
    bpl !fill-
    rts

// tst_result_eq — A = $01 when the preceding compare set Z, else $00.
tst_result_eq:
    beq !yes+
    lda #$00
    rts
!yes:
    lda #$01
    rts

// tst_result_range — A = $01 when X <= A < Y, else $00.
tst_result_range:
    stx tc_loop
    cmp tc_loop
    bcc !no+
    sty tc_loop
    cmp tc_loop
    bcs !no+
    lda #$01
    rts
!no:
    lda #$00
    rts

// VMS wis_adj boundaries: wisdom in, adjustment out.
tst_wis_in:  .byte 7, 8, 14, 15, 17, 18, 67, 68, 87, 88, 107, 108, 117, 118
tst_wis_out: .byte 0, 1,  1,  2,  2,  3,  3,  4,  4,  5,   5,   6,   6,   7
// Dropped ui_* imports to keep the test body under MAP_BASE (map-overlap
// boundary); stubs satisfy the trampoline references.
ui_char_display:
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
    rts
count_spells_known:
    jmp spell_mask_count_ptr

.assert "Test body fits below MAP_BASE", * <= MAP_BASE, true
