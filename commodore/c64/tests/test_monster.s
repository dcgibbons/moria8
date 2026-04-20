// test_monster.s — Runtime tests for monster.s
//
// Tests: monster_init_table, monster_spawn_one, monster_find_at,
//        monster_remove, pick_creature_type, monster_spawn_level.
//
// Results at $0400-$040b: $01 = pass, $00 = fail per test

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

// Exit trampoline at $080E — banks out BASIC, copies results, breaks.
// MUST be in "Test Code" segment so run_tests.sh sets breakpoint here (below $A000).
.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #12
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

player_cast_spell:
    rts

player_pray:
    rts

magic_recalc_mana:
    rts

magic_check_new_spells:
    rts

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
#import "../../common/ui_inventory.s"
#import "../../common/ui_equipment.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
ui_help_display:
store_init_all:
store_restock_all:
store_enter:
    rts
bit_mask_table:
    .byte $01, $02, $04, $08, $10, $20, $40, $80
#import "../../common/ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
t7_count:  .byte 0
t7_ok:     .byte 0
t9_count:  .byte 0
t9_mask:   .byte 0
tc_results: .fill 13, $ff       // Test results buffer (copied to $0400 by trampoline)
test_force_deep_tier_spawn: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_tier_check_transition:
    lda test_force_deep_tier_spawn
    beq !done+
    lda #4
    sta current_tier
    lda #1
    sta tier_loaded
    lda #2
    sta active_dungeon_count
    lda #49
    sta cr_level+0
    lda #60
    sta cr_level+1
!done:
    rts

test_start:
    // Initialize result area to $ff (untested)
    ldx #12
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    :PatchJump(tier_check_transition, test_tier_check_transition)

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
    lda #0
    sta test_force_deep_tier_spawn

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
    // Test 7: pick_creature_type respects the cumulative depth cap (dlvl=1).
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
    cmp #2
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
    // Test 8: pick_creature_type returns the only eligible creature when a
    //         loaded deep roster has a single entry at or below dlvl.
    // ==========================================
    lda cr_level+0
    pha
    lda cr_level+1
    pha
    lda active_dungeon_count
    pha
    lda #49
    sta zp_player_dlvl
    lda #2
    sta active_dungeon_count
    lda #49
    sta cr_level+0
    lda #60
    sta cr_level+1
    jsr pick_creature_type
    cmp #0
    bne !t8_fail+
!t8_pass:
    lda #$01
    sta tc_results+7
    jmp !t8_restore+
!t8_fail:
    lda #$00
    sta tc_results+7
!t8_restore:
    pla
    sta active_dungeon_count
    pla
    sta cr_level+1
    pla
    sta cr_level+0
    jmp !t9+

    // ==========================================
    // Test 9: pick_creature_type uses every loaded creature at or below the
    // current depth instead of collapsing to a narrow high-end band.
    // ==========================================
!t9:
    lda cr_level+0
    pha
    lda cr_level+1
    pha
    lda cr_level+2
    pha
    lda cr_level+3
    pha
    lda active_dungeon_count
    pha

    lda #4
    sta active_dungeon_count
    lda #1
    sta cr_level+0
    lda #20
    sta cr_level+1
    lda #25
    sta cr_level+2
    lda #30
    sta cr_level+3

    lda #35
    sta zp_player_dlvl
    lda #16
    sta t9_count
    lda #0
    sta t9_mask
!t9_loop:
    jsr pick_creature_type
    cmp #4
    bcs !t9_fail+
    tax
    lda t9_mask
    ora bit_mask_table,x
    sta t9_mask
    jmp !t9_next+
!t9_fail:
    lda #$00
    sta tc_results+8
    jmp !t9_restore+
!t9_next:
    dec t9_count
    bne !t9_loop-
    lda t9_mask
    and #%00000111
    beq !t9_fail+
!t9_pass:
    lda #$01
    sta tc_results+8
    jmp !t9_restore+
!t9_fail:
    lda #$00
    sta tc_results+8
!t9_restore:
    pla
    sta active_dungeon_count
    pla
    sta cr_level+3
    pla
    sta cr_level+2
    pla
    sta cr_level+1
    pla
    sta cr_level+0

    // ==========================================
    // Test 10: monster_spawn_level correct count (dlvl=1)
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
    cmp #MAX_MONSTERS+1
    bcs !t9_fail+               // Must be <= MAX_MONSTERS (group spawn adds extras)
    lda #$01
    sta tc_results+9
    jmp !t10+
!t9_fail:
    lda #$00
    sta tc_results+9

    // ==========================================
    // Test 11: monster_spawn_level spawns townspeople (dlvl=0)
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
    sta tc_results+10
    jmp !t11+
!t10_fail:
    lda #$00
    sta tc_results+10

    // ==========================================
    // Test 12: monster_spawn_level uses the active deep roster when it is
    // already valid, rather than collapsing to a single fallback monster.
    // ==========================================
!t11:
    lda cr_level+0
    pha
    lda cr_level+1
    pha
    lda active_dungeon_count
    pha
    lda #49
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir
    jsr level_generate
    lda #10
    sta zp_player_x
    sta zp_player_y
    lda #2
    sta active_dungeon_count
    lda #49
    sta cr_level+0
    lda #60
    sta cr_level+1
    jsr monster_spawn_level

    lda zp_mon_count
    beq !t11_fail+
    ldx #0
!t11_loop:
    cpx zp_mon_count
    bcs !t11_pass+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #0
    bne !t11_fail+
    inx
    jmp !t11_loop-
!t11_pass:
    lda #$01
    sta tc_results+11
    jmp !t11_restore+
!t11_fail:
    lda #$00
    sta tc_results+11
!t11_restore:
    pla
    sta active_dungeon_count
    pla
    sta cr_level+1
    pla
    sta cr_level+0
    jmp !t12+

    // ==========================================
    // Test 13: eff_kill_monster marks a pending redraw when it removes a monster.
    // ==========================================
!t12:
    jsr monster_init_table
    lda #0
    sta turn_scene_dirty
    sta turn_action_redraw_pending
    lda #$60
    sta combat_award_xp
    sta combat_check_levelup

    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    lda #20
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #TOWN_CREATURE_BASE
    jsr monster_spawn_one
    bcc !t12_fail+

    jsr eff_kill_monster

    lda turn_action_redraw_pending
    cmp #1
    bne !t12_fail+
    lda turn_scene_dirty
    bne !t12_fail+

    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !t12_fail+

    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    bne !t12_fail+

    lda #$01
    sta tc_results+12
    jmp !tests_done+
!t12_fail:
    lda #$00
    sta tc_results+12

!tests_done:
    jmp test_exit_trampoline
