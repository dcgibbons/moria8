// test_monster.s — Runtime tests for monster.s
//
// Tests: monster_init_table, monster_spawn_one, monster_find_at,
//        monster_remove, pick_creature_type, monster_spawn_level.
//
// Results at $0400-$0409: $01 = pass, $00 = fail per test

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
t7_count:  .byte 0
t7_ok:     .byte 0
t9_count:  .byte 0
tc_results: .fill 10, $ff       // Test results buffer (copied to $0400 by trampoline)

test_start:
    // Initialize result area to $ff (untested)
    ldx #9
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    // Seed RNG deterministically
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    // Set player dungeon level to 1
    lda #1
    sta zp_player_dlvl

    // Set light radius for rendering tests
    lda #1
    sta zp_light_radius

    // ==========================================
    // Test 1: monster_init_table clears all slots
    // ==========================================
    jsr monster_init_table

    // Check slot 0 type = $ff
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !t1_fail+

    // Check slot 31 type = $ff
    ldx #31
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !t1_fail+

    // Check count = 0
    lda zp_mon_count
    bne !t1_fail+

    lda #$01
    sta tc_results+0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results+0

    // ==========================================
    // Test 2: monster_spawn_one places monster correctly
    // ==========================================
!t2:
    jsr monster_init_table

    // First we need a floor tile. Generate a dungeon level.
    lda #1
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir
    jsr level_generate

    // Put player somewhere safe
    lda #10
    sta zp_player_x
    sta zp_player_y

    // Set spawn position
    lda #20
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y

    // Write a floor tile at (20,15) for the test
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Spawn type 4 (Kobold)
    lda #4
    jsr monster_spawn_one
    bcc !t2_fail+

    // X should be slot index 0
    cpx #0
    bne !t2_fail+

    // Check stored position
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #20
    bne !t2_fail+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #15
    bne !t2_fail+

    // Check type
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #4
    bne !t2_fail+

    // Check HP > 0
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    bne !t2_pass+
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    beq !t2_fail+

!t2_pass:
    lda #$01
    sta tc_results+1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results+1

    // ==========================================
    // Test 3: monster_spawn_one sets FLAG_OCCUPIED
    // ==========================================
!t3:
    // Check the map tile at (20,15) has FLAG_OCCUPIED set
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    bne !t3_pass+
    lda #$00
    sta tc_results+2
    jmp !t4+
!t3_pass:
    lda #$01
    sta tc_results+2

    // ==========================================
    // Test 4: monster_find_at returns correct index
    // ==========================================
!t4:
    lda #20                     // x
    ldy #15                     // y
    jsr monster_find_at
    bcc !t4_fail+
    cpx #0                      // Should be slot 0
    bne !t4_fail+
    lda #$01
    sta tc_results+3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results+3

    // ==========================================
    // Test 5: monster_find_at miss returns carry clear
    // ==========================================
!t5:
    lda #30                     // x (no monster here)
    ldy #30                     // y
    jsr monster_find_at
    bcs !t5_fail+
    lda #$01
    sta tc_results+4
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results+4

    // ==========================================
    // Test 6: monster_remove clears slot, flag, and count
    // ==========================================
!t6:
    // Count should be 1 (from test 2 spawn)
    lda zp_mon_count
    cmp #1
    bne !t6_fail+

    ldx #0
    jsr monster_remove

    // Check slot is empty
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !t6_fail+

    // Check FLAG_OCCUPIED cleared on map
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    bne !t6_fail+

    // Check count decremented to 0
    lda zp_mon_count
    bne !t6_fail+

    lda #$01
    sta tc_results+5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results+5

    // ==========================================
    // Test 7: pick_creature_type within range (dlvl=1)
    // Level range: max(1, 1-2)=1 to 1+3=4
    // ==========================================
!t7:
    lda #1
    sta zp_player_dlvl
    lda #10
    sta t7_count
    lda #1
    sta t7_ok                   // Assume pass

!t7_loop:
    jsr pick_creature_type
    tax
    lda cr_level,x
    // Must be >= 1
    cmp #1
    bcc !t7_bad+
    // Must be <= 4
    cmp #5
    bcs !t7_bad+
    jmp !t7_next+
!t7_bad:
    lda #0
    sta t7_ok
!t7_next:
    dec t7_count
    bne !t7_loop-

    lda t7_ok
    sta tc_results+6

    // ==========================================
    // Test 8: pick_creature_type within range (dlvl=3)
    // Level range: max(1, 3-2)=1 to 3+3=6
    // ==========================================
    lda #3
    sta zp_player_dlvl
    lda #10
    sta t7_count
    lda #1
    sta t7_ok

!t8_loop:
    jsr pick_creature_type
    tax
    lda cr_level,x
    cmp #1
    bcc !t8_bad+
    cmp #7
    bcs !t8_bad+
    jmp !t8_next+
!t8_bad:
    lda #0
    sta t7_ok
!t8_next:
    dec t7_count
    bne !t8_loop-

    lda t7_ok
    sta tc_results+7

    // ==========================================
    // Test 9: monster_spawn_level correct count (dlvl=1)
    // Count = 2 + rng(4) + 1/3 = 2 + [0,3] + 0 = [2,5], cap 14
    // ==========================================
    lda #1
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir
    jsr level_generate          // Need a fresh map

    // Set player position
    lda #10
    sta zp_player_x
    sta zp_player_y

    jsr monster_spawn_level

    lda zp_mon_count
    cmp #2
    bcc !t9_fail+
    cmp #15
    bcs !t9_fail+               // Must be <= 14
    lda #$01
    sta tc_results+8
    jmp !t10+
!t9_fail:
    lda #$00
    sta tc_results+8

    // ==========================================
    // Test 10: monster_spawn_level spawns townspeople (dlvl=0)
    // Count should be 4-7 (4 + rng(4))
    // ==========================================
!t10:
    lda #0
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir
    jsr level_generate          // Need a town map for floor tiles
    lda #10
    sta zp_player_x
    sta zp_player_y
    jsr monster_spawn_level

    // Count should be >= 4 and <= 7
    lda zp_mon_count
    cmp #4
    bcc !t10_fail+
    cmp #8
    bcs !t10_fail+
    lda #$01
    sta tc_results+9
    jmp !tests_done+
!t10_fail:
    lda #$00
    sta tc_results+9

!tests_done:
    jmp test_exit_trampoline
