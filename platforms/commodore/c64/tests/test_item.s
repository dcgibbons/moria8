// test_item.s — Runtime tests for item.s, player_items.s, combat weapon integration
//
// Tests: floor items, inventory, pickup, drop (prompted), equip, remove, eat,
//        player_recalc_equipment, combat weapon damage.
//
// Results at $0400-$042e: $01 = pass, $00 = fail per test

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

// Bootstrap + exit trampoline at $080E (right after BASIC stub).
// MUST be in "Test Code" segment so run_tests.sh sets breakpoint here (below $A000).
.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    sei                         // Disable IRQs during copy
    :BankOutBasic()             // Ensure BASIC ROM off (tc_results in $A000+)
    ldx #57-1
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0830 "Main"

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
#import "../../../../core/ui_character.s"
#import "../../../../core/stat_display.s"
.segmentdef TestCreateOverlay [start=$D000]
.segment TestCreateOverlay
#import "../../../../core/background_data.s"
#import "../../../../core/player_create.s"
.segment Default
#import "../../../../core/ui_inventory.s"
#import "../../../../core/ui_equipment.s"
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/huffman.s"
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
#import "../../../../core/dungeon_features.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
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
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../../core/spell_effects.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
eff_fear_timer: .byte 0
monster_attack_player:
player_update_hunger_state:
    sec
    rts
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
#define C64_TEST_FULL_ITEMDESC_STUB
ui_help_display:
    rts
#import "../../../../core/ui_trampoline_stubs.s"

// Store/huffman imports in dummy segment to avoid MAP_BASE ($C000) overlap
.segmentdef TestStoreOverlay [start=$d000, min=$d000, max=$ffff]
.segment TestStoreOverlay
#import "../../../../core/store_data.s"
#import "../../../../core/store.s"
#import "../../../../core/ui_store.s"
.segment Default

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer — copy to $0400 at end (msg_print clobbers $0400)
tc_results: .fill 57, $ff
tc_loop_ctr: .byte 0          // Loop counter (safe from ZP clobber)
tc_valid_ctr: .byte 0         // Valid item counter for test 22
t16_base_ac: .byte 0          // Stable scratch for Test 16 across item_wear

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_start:
    // Initialize result area to $ff (untested)
    ldx #57-1
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

    // Set light radius
    lda #1
    sta zp_light_radius

    // Initialize message system (needed for spawning)
    jsr msg_init

    // Set player HP high so we don't die
    lda #200
    sta zp_player_hp_lo
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_hp_hi
    sta zp_player_mhp_hi

    // Set a valid Human Warrior base-stat state. Equipment recalculation now
    // rebuilds current stats before applying equipment bonuses.
    lda #RACE_HUMAN
    sta player_data + PL_RACE
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    ldx #STAT_COUNT - 1
    lda #10
!set_base_stats:
    sta player_data + PL_STR_BASE,x
    dex
    bpl !set_base_stats-
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    jsr player_calc_stats

    // Stuff keyboard buffer to avoid -more- hangs
    lda #1
    sta $c6
    lda #$20
    sta $0277

    // ==========================================
    // Test 1: item_init_floor clears all slots
    // ==========================================
    jsr item_init_floor

    // Check slot 0 = $FF
    lda fi_item_id
    cmp #FI_EMPTY
    bne !t1_fail+

    // Check slot 31 = $FF
    lda fi_item_id + 31
    cmp #FI_EMPTY
    bne !t1_fail+

    // Check count = 0
    lda zp_item_count
    bne !t1_fail+

    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // ==========================================
    // Test 2: floor_item_add writes fields correctly
    // ==========================================
!t2:
    jsr item_init_floor

    // Generate a dungeon for valid map
    lda #1
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir
    jsr level_generate

    // Put a floor tile at (20, 15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y

    // Set player position away from item
    lda #10
    sta zp_player_x
    sta zp_player_y

    // Add item: gold (type 0) at (20, 15), qty=42
    lda #20
    sta fi_add_x
    lda #15
    sta fi_add_y
    lda #0
    sta fi_add_id
    lda #42
    sta fi_add_qty
    lda #0
    sta fi_add_p1

    jsr floor_item_add
    bcc !t2_fail+

    // Check stored fields
    lda fi_item_id
    cmp #0
    bne !t2_fail+
    lda fi_x
    cmp #20
    bne !t2_fail+
    lda fi_y
    cmp #15
    bne !t2_fail+
    lda fi_qty
    cmp #42
    bne !t2_fail+

    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // ==========================================
    // Test 3: floor_item_add sets FLAG_HAS_ITEM on map
    // ==========================================
!t3:
    // Check map byte at (20, 15) has FLAG_HAS_ITEM
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #FLAG_HAS_ITEM
    bne !t3_pass+
    lda #$00
    sta tc_results + 2
    jmp !t4+
!t3_pass:
    lda #$01
    sta tc_results + 2

    // ==========================================
    // Test 4: floor_item_add increments count
    // ==========================================
!t4:
    // Already have 1 item from test 2. Add 2 more.
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #21
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y

    lda #21
    sta fi_add_x
    lda #15
    sta fi_add_y
    lda #1
    sta fi_add_id
    lda #10
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    jsr floor_item_add

    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #22
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y

    lda #22
    sta fi_add_x
    lda #15
    sta fi_add_y
    lda #0
    sta fi_add_id
    lda #5
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    jsr floor_item_add

    // Count should be 3
    lda zp_item_count
    cmp #3
    beq !t4_pass+
    lda #$00
    sta tc_results + 3
    jmp !t5+
!t4_pass:
    lda #$01
    sta tc_results + 3

    // ==========================================
    // Test 5: floor_item_find_at hit
    // ==========================================
!t5:
    lda #20                     // x
    ldy #15                     // y
    jsr floor_item_find_at
    bcc !t5_fail+
    // X should be 0 (first slot)
    cpx #0
    bne !t5_fail+
    lda #$01
    sta tc_results + 4
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 4

    // ==========================================
    // Test 6: floor_item_find_at miss
    // ==========================================
!t6:
    lda #50                     // x (no item here)
    ldy #50                     // y
    jsr floor_item_find_at
    bcs !t6_fail+
    lda #$01
    sta tc_results + 5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 5

    // ==========================================
    // Test 7: floor_item_remove clears slot and flag
    // ==========================================
!t7:
    // Remove item at slot 0 (at 20,15)
    ldx #0
    jsr floor_item_remove

    // Slot 0 should be empty
    lda fi_item_id
    cmp #FI_EMPTY
    bne !t7_fail+

    // FLAG_HAS_ITEM should be cleared (no other item at 20,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #FLAG_HAS_ITEM
    bne !t7_fail+

    // Count should be 2 (was 3, removed 1)
    lda zp_item_count
    cmp #2
    bne !t7_fail+

    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // ==========================================
    // Test 8: inv_add_item places in first empty slot
    // ==========================================
!t8:
    jsr item_init_inventory

    lda #2                      // Dagger
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    jsr inv_add_item
    bcc !t8_fail+

    // Check slot 0
    cpx #0
    bne !t8_fail+
    lda inv_item_id
    cmp #2
    bne !t8_fail+
    lda inv_qty
    cmp #1
    bne !t8_fail+

    lda #$01
    sta tc_results + 7
    jmp !t9+
!t8_fail:
    lda #$00
    sta tc_results + 7

    // ==========================================
    // Test 9: inv_count_items returns correct count
    // ==========================================
!t9:
    // Already have 1 item (from test 8). Add 2 more.
    lda #3                      // Short sword
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    jsr inv_add_item

    lda #15                     // Ration of food
    sta fi_add_id
    lda #3
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    jsr inv_add_item

    jsr inv_count_items
    cmp #3
    beq !t9_pass+
    lda #$00
    sta tc_results + 8
    jmp !t10+
!t9_pass:
    lda #$01
    sta tc_results + 8

    // ==========================================
    // Test 10: item_spawn_level spawns gold on dlvl=1
    // ==========================================
!t10:
    lda #1
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir
    jsr level_generate

    // Set player position
    lda #10
    sta zp_player_x
    sta zp_player_y

    jsr monster_spawn_level     // Needed since map is fresh
    jsr item_spawn_level

    // zp_item_count should be > 0
    lda zp_item_count
    beq !t10_fail+

    // Check that first item is gold (type 0 or 1)
    lda fi_item_id
    cmp #2
    bcs !t10_fail+              // Type >= 2 means not gold

    lda #$01
    sta tc_results + 9
    jmp !t11+
!t10_fail:
    lda #$00
    sta tc_results + 9

    // ==========================================
    // Test 11: item_pickup gold adds to player gold
    // ==========================================
!t11:
    jsr item_init_floor
    jsr item_init_inventory

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Clear player gold
    lda #0
    sta player_data + PL_GOLD_0
    sta player_data + PL_GOLD_1
    sta player_data + PL_GOLD_2

    // Generate map and set player position
    lda #1
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir
    jsr level_generate

    // Place floor tile at (20, 12)
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y

    // Put player at (20, 12)
    lda #20
    sta zp_player_x
    lda #12
    sta zp_player_y

    // Add gold to floor at player position
    lda #20
    sta fi_add_x
    lda #12
    sta fi_add_y
    lda #0              // Gold (small)
    sta fi_add_id
    lda #50             // 50 gold pieces
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    jsr floor_item_add

    // Stuff keyboard buffer for -more- prompt
    lda #1
    sta $c6
    lda #$20
    sta $0277

    // Pick up
    jsr item_pickup
    bcc !t11_fail+

    // Check player gold = 50
    lda player_data + PL_GOLD_0
    cmp #50
    bne !t11_fail+
    lda player_data + PL_GOLD_1
    bne !t11_fail+

    // Check floor slot 0 is empty
    lda fi_item_id
    cmp #FI_EMPTY
    bne !t11_fail+

    lda #$01
    sta tc_results + 10
    jmp !t12+
!t11_fail:
    lda #$00
    sta tc_results + 10

    // ==========================================
    // Test 12: item_pickup non-gold adds to inventory
    // ==========================================
!t12:
    jsr item_init_floor
    jsr item_init_inventory

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Place floor tile at (20, 12) (reuse from test 11 setup)
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y

    // Player at (20, 12)
    lda #20
    sta zp_player_x
    lda #12
    sta zp_player_y

    // Add dagger (type 2) to floor at player position
    lda #20
    sta fi_add_x
    lda #12
    sta fi_add_y
    lda #2              // Dagger
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    jsr floor_item_add

    // Stuff keyboard buffer
    lda #1
    sta $c6
    lda #$20
    sta $0277

    // Pick up
    jsr item_pickup
    bcc !t12_fail+

    // Check inventory slot 0 has dagger
    lda inv_item_id
    cmp #2
    bne !t12_fail+

    // Check floor slot is empty
    lda fi_item_id
    cmp #FI_EMPTY
    bne !t12_fail+

    lda #$01
    sta tc_results + 11
    jmp !t13+
!t12_fail:
    lda #$00
    sta tc_results + 11

    // ==========================================
    // Test 13: item_pickup nothing -> carry clear
    // ==========================================
!t13:
    jsr item_init_floor

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Player at position with no items
    lda #10
    sta zp_player_x
    sta zp_player_y

    // Stuff keyboard buffer
    lda #1
    sta $c6
    lda #$20
    sta $0277

    jsr item_pickup
    bcs !t13_fail+

    lda #$01
    sta tc_results + 12
    jmp !t14+
!t13_fail:
    lda #$00
    sta tc_results + 12

    // ==========================================
    // Test 14: item_drop (prompted) moves item to floor
    // ==========================================
!t14:
    jsr item_init_floor
    jsr item_init_inventory

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Place floor tile at player position (10, 10)
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y

    // Player at (10, 10)
    lda #10
    sta zp_player_x
    sta zp_player_y

    // Add dagger to inventory slot 0
    lda #2              // Dagger
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    jsr inv_add_item

    // Stuff keyboard buffer: 'A' ($41) to select slot 0, then space for -more-
    lda #2
    sta $c6
    lda #$41            // 'A' — select item in slot 0
    sta $0277
    lda #$20            // Space — dismiss -more-
    sta $0278

    // Drop
    jsr item_drop
    bcc !t14_fail+

    // Check inventory slot 0 is empty
    lda inv_item_id
    cmp #FI_EMPTY
    bne !t14_fail+

    // Check floor has an item at player position
    lda #10
    ldy #10
    jsr floor_item_find_at
    bcc !t14_fail+

    // Check it's a dagger
    lda fi_item_id,x
    cmp #2
    bne !t14_fail+

    lda #$01
    sta tc_results + 13
    jmp !t15+
!t14_fail:
    lda #$00
    sta tc_results + 13

    // ==========================================
    // Test 15: item_wear equips dagger to EQUIP_WEAPON
    // ==========================================
!t15:
    jsr item_init_inventory

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Put dagger (type 2) in inv slot 0
    lda #2
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    // Stuff keyboard: 'A' ($41) to wear slot 0, then space for -more-
    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_wear
    bcc !t15_fail+

    // Check EQUIP_WEAPON has dagger
    lda inv_item_id + EQUIP_WEAPON
    cmp #2
    bne !t15_fail+

    // Check slot 0 is empty (moved to equip)
    lda inv_item_id
    cmp #FI_EMPTY
    bne !t15_fail+

    lda #$01
    sta tc_results + 14
    jmp !t16+
!t15_fail:
    lda #$00
    sta tc_results + 14

    // ==========================================
    // Test 16: item_wear equips armor, AC increases
    // ==========================================
!t16:
    jsr item_init_inventory

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Reset AC to stat-only basis
    jsr player_calc_combat

    // Save base AC
    lda player_data + PL_AC
    sta t16_base_ac

    // Put leather armor (type 7, base AC = 4) in inv slot 0
    lda #7
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    // Stuff keyboard: 'A' to wear, space for -more-
    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_wear
    bcc !t16_fail+

    // Check AC increased by 4
    lda player_data + PL_AC
    sec
    sbc t16_base_ac
    cmp #4
    beq !t16_pass+
!t16_fail:
    lda #$00
    sta tc_results + 15
    jmp !t17+
!t16_pass:
    lda #$01
    sta tc_results + 15

    // ==========================================
    // Test 17: item_takeoff moves to carried slot
    // ==========================================
!t17:
    jsr item_init_inventory

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Put dagger in EQUIP_WEAPON slot
    lda #2
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #0
    sta inv_p1 + EQUIP_WEAPON
    sta inv_flags + EQUIP_WEAPON

    // Stuff keyboard: 'A' = weapon slot, space for -more-
    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_takeoff
    bcc !t17_fail+

    // Check EQUIP_WEAPON is now empty
    lda inv_item_id + EQUIP_WEAPON
    cmp #FI_EMPTY
    bne !t17_fail+

    // Check carried slot 0 has dagger
    lda inv_item_id
    cmp #2
    bne !t17_fail+

    lda #$01
    sta tc_results + 16
    jmp !t18+
!t17_fail:
    lda #$00
    sta tc_results + 16

    // ==========================================
    // Test 18: item_eat restores food counter
    // ==========================================
!t18:
    jsr item_init_inventory

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Set food to 100
    lda #100
    sta zp_player_food
    lda #0
    sta zp_player_food_hi

    // Put ration of food (type 15) in inv slot 0
    lda #15
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    // Stuff keyboard buffer for -more- (item_eat prints a message)
    lda #1
    sta $c6
    lda #$20
    sta $0277

    jsr item_eat
    bcc !t18_fail+

    // Check food counter = 100 + 1500 = 1600
    // 1600 = $0640. Lo = $40, Hi = $06
    lda zp_player_food
    cmp #<1600
    bne !t18_fail+
    lda zp_player_food_hi
    cmp #>1600
    bne !t18_fail+

    // Shared hunger-state recompute should now classify the player as full.
    lda zp_hunger_state
    cmp #HUNGER_FULL
    bne !t18_fail+

    // Check slot 0 is empty (food consumed)
    lda inv_item_id
    cmp #FI_EMPTY
    bne !t18_fail+

    lda #$01
    sta tc_results + 17
    jmp !t19+
!t18_fail:
    lda #$00
    sta tc_results + 17

    // ==========================================
    // Test 19: item_eat with no food -> carry clear
    // ==========================================
!t19:
    jsr item_init_inventory

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Stuff keyboard buffer for -more- (item_eat prints "YOU HAVE NO FOOD.")
    lda #1
    sta $c6
    lda #$20
    sta $0277

    jsr item_eat
    bcs !t19_fail+

    lda #$01
    sta tc_results + 18
    jmp !t20+
!t19_fail:
    lda #$00
    sta tc_results + 18

    // ==========================================
    // Test 20: player_recalc_equipment sums armor AC
    // ==========================================
!t20:
    jsr item_init_inventory

    // Equip leather armor (type 7, base AC = 4) in BODY slot
    lda #7
    sta inv_item_id + EQUIP_BODY
    lda #1
    sta inv_qty + EQUIP_BODY
    lda #0
    sta inv_p1 + EQUIP_BODY
    sta inv_flags + EQUIP_BODY

    // Equip small shield (type 9, base AC = 2) in SHIELD slot
    lda #9
    sta inv_item_id + EQUIP_SHIELD
    lda #1
    sta inv_qty + EQUIP_SHIELD
    lda #0
    sta inv_p1 + EQUIP_SHIELD
    sta inv_flags + EQUIP_SHIELD

    jsr player_recalc_equipment

    // Get DEX-only AC (player_calc_combat base)
    lda player_data + PL_DEX_CUR
    jsr stat_bonus_index
    lda dex_ac_bonus,x
    bpl !t20_use_dex+
    lda #0                      // Negative DEX bonus -> 0
!t20_use_dex:
    sta zp_temp0                // zp_temp0 = expected DEX AC

    // Expected: dex_bonus + 4 + 2 = dex_bonus + 6
    lda zp_temp0
    clc
    adc #6
    sta zp_temp0

    lda player_data + PL_AC
    cmp zp_temp0
    beq !t20_pass+

    lda #$00
    sta tc_results + 19
    jmp !t21+
!t20_pass:
    lda #$01
    sta tc_results + 19

    // ==========================================
    // Test 21: pick_item_type returns valid type in range 2-46
    // ==========================================
!t21:
    lda #3
    sta zp_player_dlvl

    lda #20
    sta tc_loop_ctr             // Use static RAM for counter (zp_temp0 clobbered by pick_item_type)
!t21_loop:
    jsr pick_item_type
    cmp #2
    bcc !t21_fail+
    cmp #ITEM_TYPE_COUNT
    bcs !t21_fail+
    dec tc_loop_ctr
    bne !t21_loop-

    lda #$01
    sta tc_results + 20
    jmp !t22+
!t21_fail:
    lda #$00
    sta tc_results + 20

    // ==========================================
    // Test 22: pick_item_type respects min_level
    // ==========================================
!t22:
    lda #1
    sta zp_player_dlvl

    lda #0
    sta tc_valid_ctr            // Count of valid items
    lda #20
    sta tc_loop_ctr
!t22_loop:
    jsr pick_item_type
    // Check if min_level <= 3 (dlvl=1+2)
    tax
    jsr iml_get_for_type
    cmp #4
    bcs !t22_over+
    inc tc_valid_ctr
!t22_over:
    dec tc_loop_ctr
    bne !t22_loop-

    // At least 15 of 20 should respect min_level
    lda tc_valid_ctr
    cmp #15
    bcs !t22_pass+
    lda #$00
    sta tc_results + 21
    jmp !t23+
!t22_pass:
    lda #$01
    sta tc_results + 21

    // ==========================================
    // Test 23: roll_enchantment returns 0 for food
    // ==========================================
!t23:
    lda #1
    sta zp_player_dlvl

    lda #15                     // Ration of food
    jsr roll_enchantment
    cmp #0
    beq !t23_pass+
    lda #$00
    sta tc_results + 22
    jmp !t24+
!t23_pass:
    lda #$01
    sta tc_results + 22

    // ==========================================
    // Test 24: roll_enchantment returns charges for torch
    // ==========================================
!t24:
    lda #13                     // Wooden torch
    jsr roll_enchantment
    // Should be in range [67, 133]  (67 + rng(67), each charge = 30 turns)
    cmp #67
    bcc !t24_fail+
    cmp #134
    bcs !t24_fail+
    lda #$01
    sta tc_results + 23
    jmp !t25+
!t24_fail:
    lda #$00
    sta tc_results + 23

    // ==========================================
    // Test 25: item_spawn_level spawns non-gold items
    // ==========================================
!t25:
    lda #3
    sta zp_player_dlvl

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Generate map
    lda #0
    sta level_entry_dir
    jsr level_generate

    // Set player position
    lda #10
    sta zp_player_x
    sta zp_player_y

    // Stuff keyboard buffer for -more-
    lda #1
    sta $c6
    lda #$20
    sta $0277

    jsr monster_spawn_level
    jsr item_spawn_level

    // Scan fi_item_id for any type >= 2
    ldx #0
    lda #0
    sta tc_valid_ctr            // Found flag
!t25_scan:
    cpx #MAX_FLOOR_ITEMS
    bcs !t25_check+
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !t25_next+
    cmp #2
    bcc !t25_next+
    // Found non-gold item
    inc tc_valid_ctr
!t25_next:
    inx
    jmp !t25_scan-
!t25_check:
    lda tc_valid_ctr
    bne !t25_pass+
    lda #$00
    sta tc_results + 24
    jmp !t26+
!t25_pass:
    lda #$01
    sta tc_results + 24

    // ==========================================
    // Test 26: Treasure room: extra items placed (dlvl >= 3)
    // ==========================================
!t26:
    lda #5
    sta zp_player_dlvl

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Generate map
    lda #0
    sta level_entry_dir
    jsr level_generate

    // Set player position
    lda #10
    sta zp_player_x
    sta zp_player_y

    // Stuff keyboard buffer for -more-
    lda #1
    sta $c6
    lda #$20
    sta $0277

    jsr monster_spawn_level
    jsr item_spawn_level

    // Count total items — gold + non-gold + treasure
    // With dlvl=5: gold = 2+rng(3)+2 = 4-6, non-gold = 1+rng(2)+1 = 2-3, treasure = 2-4
    // Total should be >= 6 items minimum
    lda zp_item_count
    cmp #6
    bcs !t26_pass+
    lda #$00
    sta tc_results + 25
    jmp !t27+
!t26_pass:
    lda #$01
    sta tc_results + 25

    // ==========================================
    // Test 27: item_get_name_ptr returns real name for known type
    // ==========================================
!t27:
    // Set dagger (type 2) as known (it already should be)
    ldx #2
    jsr id_known_set

    lda #$12
    sta zp_ptr1
    lda #$34
    sta zp_ptr1_hi
    lda #2                          // Dagger
    jsr item_get_name_ptr
    lda zp_ptr1
    cmp #$12
    bne !t27_fail+
    lda zp_ptr1_hi
    cmp #$34
    bne !t27_fail+
    // zp_ptr0 should resolve to the known display name.
    ldy #0
!t27_cmp:
    lda (zp_ptr0),y
    cmp t27_expected_name,y
    bne !t27_fail+
    cmp #0
    beq !t27_pass+
    iny
    bne !t27_cmp-

!t27_pass:
    lda #$01
    sta tc_results + 26
    jmp !t28+
!t27_fail:
    lda #$00
    sta tc_results + 26

    // ==========================================
    // Test 28: item_get_name_ptr returns unid name for unknown potion
    // ==========================================
!t28:
    // Set type 17 (CLW) as unknown
    ldx #17
    jsr id_known_clear

    lda #17
    jsr item_get_name_ptr
    // zp_ptr0 should NOT point to itn_17
    lda zp_ptr0
    cmp #<itn_17
    bne !t28_pass+
    lda zp_ptr0_hi
    cmp #>itn_17
    bne !t28_pass+
    // Both match — that means we got the real name (fail)
    lda #$00
    sta tc_results + 27
    jmp !t29+
!t28_pass:
    lda #$01
    sta tc_results + 27

    // ==========================================
    // Test 29: item_init_identification sets known/unknown correctly
    // ==========================================
!t29:
    jsr item_init_identification

    // Check type 2 (dagger) is known
    ldx #2
    jsr id_known_test
    beq !t29_fail+

    // Check type 17 (CLW potion) is unknown
    ldx #17
    jsr id_known_test
    bne !t29_fail+

    // Check type 23 (Protection ring) is unknown
    ldx #23
    jsr id_known_test
    bne !t29_fail+

    // Appended fixed equipment defaults known; future capacity remains unknown.
    ldx #64
    jsr id_known_test
    beq !t29_fail+
    ldx #65
    jsr id_known_test
    beq !t29_fail+
    ldx #79
    jsr id_known_test
    beq !t29_fail+
    ldx #ITEM_TYPE_AMULET_MAGI
    jsr id_known_test
    beq !t29_fail+
    .if (ITEM_TYPE_COUNT < ITEM_ID_CAPACITY) {
        ldx #ITEM_TYPE_COUNT
        jsr id_known_test
        bne !t29_fail+
    }

    // If an appended fixed item is forced unknown by bad state, it still
    // resolves through fixed item data instead of a shuffled class table.
    ldx #ITEM_TYPE_MITHRIL_CHAIN
    jsr id_known_clear
    lda #ITEM_TYPE_MITHRIL_CHAIN
    jsr item_get_name_ptr
    lda #<t29_expected_appended_name
    sta zp_ptr1
    lda #>t29_expected_appended_name
    sta zp_ptr1_hi
    ldy #0
!t29_cmp_appended:
    lda (zp_ptr0),y
    cmp (zp_ptr1),y
    bne !t29_fail+
    cmp #0
    beq !t29_check_color+
    iny
    bne !t29_cmp_appended-
!t29_check_color:
    lda #ITEM_TYPE_MITHRIL_CHAIN
    jsr item_get_floor_color
    sta t29_expected_color
    ldx #ITEM_TYPE_MITHRIL_CHAIN
    lda it_color_ac,x
    lsr
    lsr
    lsr
    lsr
    cmp t29_expected_color
    bne !t29_fail+

    lda #$01
    sta tc_results + 28
    jmp !t30+
!t29_fail:
    lda #$00
    sta tc_results + 28

    // ==========================================
    // Test 30: Pickup preserves flags (IF_CURSED)
    // ==========================================
!t30:
    jsr item_init_floor
    jsr item_init_inventory

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Generate map
    lda #1
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir
    jsr level_generate

    // Place floor tile at (20, 12)
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y

    // Put player at (20, 12)
    lda #20
    sta zp_player_x
    lda #12
    sta zp_player_y

    // Add cursed item to floor at player position
    lda #20
    sta fi_add_x
    lda #12
    sta fi_add_y
    lda #4                          // Long sword
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #$fd                        // -3 enchant
    sta fi_add_p1
    jsr floor_item_add

    // Set IF_CURSED flag on floor item
    lda #IF_CURSED << FI_META_FLAGS_SHIFT
    sta fi_meta                     // Slot 0

    // Stuff keyboard buffer for -more-
    lda #1
    sta $c6
    lda #$20
    sta $0277

    // Pick up
    jsr item_pickup

    // Check inventory slot 0 has IF_CURSED
    lda inv_flags
    and #IF_CURSED
    bne !t30_pass+
    lda #$00
    sta tc_results + 29
    jmp !t31+
!t30_pass:
    lda #$01
    sta tc_results + 29

    // ==========================================
    // Test 31: item_quaff heals HP (cure light wounds)
    // ==========================================
!t31:
    jsr item_init_inventory

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Set HP to 50/200
    lda #50
    sta zp_player_hp_lo
    lda #0
    sta zp_player_hp_hi
    lda #200
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi

    // Make cure light wounds known so we can verify
    ldx #17
    jsr id_known_set

    // Put CLW potion (type 17) in inv slot 0
    lda #17
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    // Stuff keyboard: 'A' ($41) to select slot 0
    // (2-line message area means no -MORE- between prompt and effect)
    lda #1
    sta $c6
    lda #$41
    sta $0277

    jsr item_quaff

    // HP should be > 50 (healed by 4-11)
    lda zp_player_hp_lo
    cmp #51
    bcc !t31_fail+

    // Slot 0 should be empty (consumed)
    lda inv_item_id
    cmp #FI_EMPTY
    bne !t31_fail+

    lda #$01
    sta tc_results + 30
    jmp !t32+
!t31_fail:
    lda #$00
    sta tc_results + 30

    // ==========================================
    // Test 32: item_read_scroll identifies item (identify scroll)
    // ==========================================
!t32:
    jsr item_init_inventory

    // Clear message state
    lda #0
    sta zp_msg_flags

    // Reset id_known for type 17 to unknown
    ldx #17
    jsr id_known_clear

    // Put identify scroll (type 21) in inv slot 0
    lda #21
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    // Put unknown potion (type 17) in inv slot 1
    lda #17
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1

    // Stuff keyboard buffer:
    // 1. 'A' ($41) — select scroll in slot 0
    // 2. 'A' ($41) — select the first visible item to identify
    // 3. Space ($20) — dismiss -MORE- after "THIS IS A..." message
    // (2-line message area: prompt + identify fit in rows 0-1, no -MORE- between them)
    lda #3
    sta $c6
    lda #$41                        // 'A' — read the scroll in slot 0
    sta $0277
    lda #$41                        // 'A' — identify the first visible item
    sta $0278
    lda #$20                        // Space — dismiss -MORE- after result
    sta $0279

    jsr item_read_scroll

    // id_known[17] should now be 1
    ldx #17
    jsr id_known_test
    beq !t32_fail+

    // Scroll in slot 0 should be consumed, compacting the potion into slot 0
    lda inv_item_id
    cmp #17
    bne !t32_fail+

    // Scroll type 21 should also be known (auto-identified on use)
    ldx #21
    jsr id_known_test
    beq !t32_fail+

    lda #$01
    sta tc_results + 31
    jmp !t33+
!t32_fail:
    lda #$00
    sta tc_results + 31

    // ==========================================
    // Test 33: CSW potion heals in range [10, 45]
    // ==========================================
!t33:
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags

    // Set HP to 50/200
    lda #50
    sta zp_player_hp_lo
    lda #0
    sta zp_player_hp_hi
    lda #200
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi

    // Sync to player_data
    lda #50
    sta player_data + PL_HP_LO
    lda #0
    sta player_data + PL_HP_HI
    lda #200
    sta player_data + PL_MHP_LO
    lda #0
    sta player_data + PL_MHP_HI

    // Put CSW potion (type 25) in inv slot 0
    lda #25
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    // Stuff keyboard: 'A' and space
    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_quaff

    // HP should be in [60, 95] (50 + [10, 45])
    lda zp_player_hp_lo
    cmp #60
    bcc !t33_fail+
    cmp #96
    bcs !t33_fail+

    lda #$01
    sta tc_results + 32
    jmp !t34+
!t33_fail:
    lda #$00
    sta tc_results + 32

    // ==========================================
    // Test 34: Restore Mana sets MP = max MP
    // ==========================================
!t34:
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags

    // Set mana to 5/30
    lda #5
    sta zp_player_mp
    lda #30
    sta zp_player_mmp

    // Put Restore Mana potion (type 26) in inv slot 0
    lda #26
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_quaff

    // MP should be 30
    lda zp_player_mp
    cmp #30
    bne !t34_fail+

    lda #$01
    sta tc_results + 33
    jmp !t35+
!t34_fail:
    lda #$00
    sta tc_results + 33

    // ==========================================
    // Test 35: Enchant Weapon increments p1
    // ==========================================
!t35:
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags

    // Equip a dagger (type 2) with +2 combat stats in weapon slot
    lda #2
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #2
    sta inv_to_hit + EQUIP_WEAPON
    sta inv_to_dam + EQUIP_WEAPON
    lda #0
    sta inv_flags + EQUIP_WEAPON

    // Put Enchant Weapon scroll (type 34) in inv slot 0
    lda #34
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_read_scroll

    // Weapon combat stats should be 3
    lda inv_to_hit + EQUIP_WEAPON
    cmp #3
    bne !t35_fail+
    lda inv_to_dam + EQUIP_WEAPON
    cmp #3
    bne !t35_fail+

    lda #$01
    sta tc_results + 34
    jmp !t36+
!t35_fail:
    lda #$00
    sta tc_results + 34

    // ==========================================
    // Test 36: Word of Recall sets timer
    // ==========================================
!t36:
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags
    sta zp_eff_word_recall

    // Put Word of Recall scroll (type 32) in inv slot 0
    lda #32
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_read_scroll

    // zp_eff_word_recall should be in [15, 29]
    lda zp_eff_word_recall
    cmp #15
    bcc !t36_fail+
    cmp #30
    bcs !t36_fail+

    lda #$01
    sta tc_results + 35
    jmp !t37+
!t36_fail:
    lda #$00
    sta tc_results + 35

    // ==========================================
    // Test 37: Blindness potion sets zp_eff_blind
    // ==========================================
!t37:
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags
    sta zp_eff_blind

    // Put Blindness potion (type 28) in inv slot 0
    lda #28
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_quaff

    // zp_eff_blind should be in [100, 199]
    lda zp_eff_blind
    cmp #100
    bcc !t37_fail+
    cmp #200
    bcs !t37_fail+

    lda #$01
    sta tc_results + 36
    jmp !t38+
!t37_fail:
    lda #$00
    sta tc_results + 36

    // ==========================================
    // Test 38: pick_item_type returns new types (25+) on deep levels
    // ==========================================
!t38:
    lda #10
    sta zp_player_dlvl

    lda #0
    sta tc_valid_ctr            // Count types >= 25
    lda #50
    sta tc_loop_ctr
!t38_loop:
    jsr pick_item_type
    cmp #25
    bcc !t38_under+
    inc tc_valid_ctr
!t38_under:
    dec tc_loop_ctr
    bne !t38_loop-

    // At least 1 of 50 should be >= 25
    lda tc_valid_ctr
    bne !t38_pass+
    lda #$00
    sta tc_results + 37
    jmp !t39+
!t38_pass:
    lda #$01
    sta tc_results + 37

    // ==========================================
    // Test 39: Enchant Weapon on cursed item clears curse and stat penalties
    // ==========================================
!t39:
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags
    sta zp_eff_blind                 // Clear blindness from test 37

    // Equip a cursed long sword (type 4) with combat stats=$FD (-3)
    lda #4
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #$fd                        // -3 enchantment
    sta inv_to_hit + EQUIP_WEAPON
    sta inv_to_dam + EQUIP_WEAPON
    lda #IF_CURSED
    sta inv_flags + EQUIP_WEAPON

    // Put Enchant Weapon scroll (type 34) in inv slot 0
    lda #34
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_read_scroll

    // Combat stats at EQUIP_WEAPON should be 0 (curse removed, reset)
    lda inv_to_hit + EQUIP_WEAPON
    bne !t39_fail+
    lda inv_to_dam + EQUIP_WEAPON
    bne !t39_fail+

    // IF_CURSED should be cleared
    lda inv_flags + EQUIP_WEAPON
    and #IF_CURSED
    bne !t39_fail+

    lda #$01
    sta tc_results + 38
    jmp !t40+
!t39_fail:
    lda #$00
    sta tc_results + 38

    // ==========================================
    // Test 40: Enchant Weapon at cap (p1=5) does nothing
    // ==========================================
!t40:
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags
    sta zp_eff_blind                 // Ensure blindness is clear

    // Equip dagger (type 2) with combat stats at cap
    lda #2
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #5
    sta inv_to_hit + EQUIP_WEAPON
    sta inv_to_dam + EQUIP_WEAPON
    lda #0
    sta inv_flags + EQUIP_WEAPON

    // Put Enchant Weapon scroll (type 34) in inv slot 0
    lda #34
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_read_scroll

    // Combat stats should still be 5 (not 6)
    lda inv_to_hit + EQUIP_WEAPON
    cmp #5
    bne !t40_fail+
    lda inv_to_dam + EQUIP_WEAPON
    cmp #5
    bne !t40_fail+

    lda #$01
    sta tc_results + 39
    jmp !t41+
!t40_fail:
    lda #$00
    sta tc_results + 39

    // ==========================================
    // Test 41: Enchant Armor on cursed item clears curse, sets p1=0
    // ==========================================
!t41:
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags
    sta zp_eff_blind

    // Equip cursed leather armor (type 7) at EQUIP_BODY with AC=$FD (-3)
    lda #7
    sta inv_item_id + EQUIP_BODY
    lda #1
    sta inv_qty + EQUIP_BODY
    lda #$fd                        // -3 enchantment
    sta inv_to_ac + EQUIP_BODY
    lda #IF_CURSED
    sta inv_flags + EQUIP_BODY

    // Put Enchant Armor scroll (type 35) in inv slot 0
    lda #35
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_read_scroll

    // AC at EQUIP_BODY should be 0 (curse removed, reset)
    lda inv_to_ac + EQUIP_BODY
    bne !t41_fail+

    // IF_CURSED should be cleared
    lda inv_flags + EQUIP_BODY
    and #IF_CURSED
    bne !t41_fail+

    lda #$01
    sta tc_results + 40
    jmp !t42+
!t41_fail:
    lda #$00
    sta tc_results + 40

    // ==========================================
    // Test 42: Enchant Armor at cap (p1=5) does nothing
    // ==========================================
!t42:
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags
    sta zp_eff_blind

    // Equip leather armor (type 7) at EQUIP_BODY with AC at cap
    lda #7
    sta inv_item_id + EQUIP_BODY
    lda #1
    sta inv_qty + EQUIP_BODY
    lda #5
    sta inv_to_ac + EQUIP_BODY
    lda #0
    sta inv_flags + EQUIP_BODY

    // Put Enchant Armor scroll (type 35) in inv slot 0
    lda #35
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_read_scroll

    // AC should still be 5 (not 6)
    lda inv_to_ac + EQUIP_BODY
    cmp #5
    bne !t42_fail+

    lda #$01
    sta tc_results + 41
    jmp !t43+
!t42_fail:
    lda #$00
    sta tc_results + 41

    // ==========================================
    // Test 43: Enchant Armor targets shield when body slot is empty
    // ==========================================
!t43:
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags
    sta zp_eff_blind

    // Equip small leather shield (type 9) with room to enchant
    lda #9
    sta inv_item_id + EQUIP_SHIELD
    lda #1
    sta inv_qty + EQUIP_SHIELD
    lda #2
    sta inv_to_ac + EQUIP_SHIELD
    lda #0
    sta inv_flags + EQUIP_SHIELD

    // Put Enchant Armor scroll (type 35) in inv slot 0
    lda #35
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_read_scroll

    // Shield AC should increment; body slot should remain empty.
    lda inv_to_ac + EQUIP_SHIELD
    cmp #3
    bne !t43_fail+
    lda inv_item_id + EQUIP_BODY
    cmp #FI_EMPTY
    bne !t43_fail+

    lda #$01
    sta tc_results + 42
    jmp !t44+
!t43_fail:
    lda #$00
    sta tc_results + 42

    // ==========================================
    // Test 44: pick_item_type depth curve produces high-level items
    // ==========================================
!t44:
    lda #8
    sta zp_player_dlvl

    lda #0
    sta tc_valid_ctr            // Count items with min_level >= 3
    lda #60
    sta tc_loop_ctr
!t44_loop:
    jsr pick_item_type
    tax
    jsr iml_get_for_type
    cmp #3
    bcc !t44_under+
    inc tc_valid_ctr
!t44_under:
    dec tc_loop_ctr
    bne !t44_loop-

    // At least 15 of 60 should have min_level >= 3
    // (depth curve biases toward higher-level items)
    lda tc_valid_ctr
    cmp #15
    bcs !t44_pass+
    lda #$00
    sta tc_results + 43
    jmp !tests_done+
!t44_pass:
    lda #$01
    sta tc_results + 43

    // ==========================================
    // Test 45: item_spawn_level skips placement when no floor exists
    // ==========================================
!t45:
    jsr item_init_floor
    jsr fill_map_rock

    lda #10
    sta zp_player_dlvl

    lda #0
    sta room_count

    jsr item_spawn_level

    lda zp_item_count
    beq !t45_check_flag+
    lda #$00
    sta tc_results + 44
    jmp !t46+

!t45_check_flag:
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #FLAG_HAS_ITEM
    beq !t45_pass+
    lda #$00
    sta tc_results + 44
    jmp !t46+

!t45_pass:
    lda #$01
    sta tc_results + 44
    jmp !t46+

    // ==========================================
    // Test 46: pickup preserves split combat stats and metadata
    // ==========================================
!t46:
    jsr item_init_floor
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags

    // Place floor tile and player at (20, 12)
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y

    lda #20
    sta zp_player_x
    lda #12
    sta zp_player_y

    lda #20
    sta fi_add_x
    lda #12
    sta fi_add_y
    lda #2                          // Dagger
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    sta fi_add_to_ac
    lda #2
    sta fi_add_to_hit
    lda #3
    sta fi_add_to_dam
    lda #IF_IDENTIFIED
    sta fi_add_flags
    lda #4
    sta fi_add_ego
    jsr floor_item_add

    lda #1
    sta $c6
    lda #$20
    sta $0277

    jsr item_pickup
    bcc !t46_fail+

    lda inv_item_id
    cmp #2
    bne !t46_fail+
    lda inv_to_hit
    cmp #2
    bne !t46_fail+
    lda inv_to_dam
    cmp #3
    bne !t46_fail+
    lda inv_flags
    and #IF_IDENTIFIED
    beq !t46_fail+
    lda inv_ego
    cmp #4
    bne !t46_fail+

    lda #$01
    sta tc_results + 45
    jmp !t47+
!t46_fail:
    lda #$00
    sta tc_results + 45

    // ==========================================
    // Test 47: drop preserves split combat stats and metadata
    // ==========================================
!t47:
    jsr item_init_floor
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags

    // Place floor tile and player at (10, 10)
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y

    lda #10
    sta zp_player_x
    sta zp_player_y

    lda #2                          // Dagger
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_to_ac
    lda #4
    sta inv_to_hit
    lda #5
    sta inv_to_dam
    lda #IF_IDENTIFIED
    sta inv_flags
    lda #2
    sta inv_ego

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_drop
    bcc !t47_fail+

    lda #10
    ldy #10
    jsr floor_item_find_at
    bcc !t47_fail+

    lda fi_item_id,x
    cmp #2
    bne !t47_fail+
    lda fi_to_hit,x
    cmp #4
    bne !t47_fail+
    lda fi_to_dam,x
    cmp #5
    bne !t47_fail+
    jsr floor_item_get_flags_x
    and #IF_IDENTIFIED
    beq !t47_fail+
    jsr floor_item_get_ego_x
    cmp #2
    bne !t47_fail+

    lda #$01
    sta tc_results + 46
    jmp !t48+
!t47_fail:
    lda #$00
    sta tc_results + 46

    // ==========================================
    // Test 48: Phase 3 potions apply their effects
    // ==========================================
!t48:
    // --- Potion of Healing (96): heal 200, capped at max ---
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags

    lda #50
    sta zp_player_hp_lo
    lda #0
    sta zp_player_hp_hi
    lda #200
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi

    lda #ITEM_TYPE_POT_HEALING
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_quaff

    lda zp_player_hp_lo
    cmp #200
    beq !t48_h_ok+
    jmp !t48_fail+
!t48_h_ok:
    lda inv_item_id
    cmp #FI_EMPTY
    beq !t48_h2_ok+
    jmp !t48_fail+
!t48_h2_ok:

    // --- Potion of Neutralize Poison (126): clears poison timer ---
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags
    lda #40
    sta zp_eff_poison

    lda #ITEM_TYPE_POT_NEUTRALIZE
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_quaff

    lda zp_eff_poison
    beq !t48_n_ok+
    jmp !t48_fail+
!t48_n_ok:

    // --- Potion of Resist Heat (98): sets heat timer ---
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags

    lda #ITEM_TYPE_POT_RESIST_HEAT
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_quaff

    lda zp_eff_resist
    bne !t48_rh_ok+
    jmp !t48_fail+
!t48_rh_ok:

    // --- Potion of Resist Cold (99): sets cold timer ---
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags

    lda #ITEM_TYPE_POT_RESIST_COLD
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_quaff

    lda eff_resist_cold_timer
    bne !t48_rc_ok+
    jmp !t48_fail+
!t48_rc_ok:

    // --- Potion of Restoration (97): recalc restores drained stat ---
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags

    // Base CON 12, drained to 8; restoration recalcs CUR from the baked base
    // (race/class modifiers are folded into BASE at creation, not re-applied).
    lda #0
    sta player_data + PL_RACE
    sta player_data + PL_CLASS
    lda #12
    sta player_data + PL_CON_BASE
    sta t48_expected_con
    lda #8
    sta player_data + PL_CON_CUR

    lda #ITEM_TYPE_POT_RESTORATION
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_quaff

    lda player_data + PL_CON_CUR
    cmp t48_expected_con
    beq !t48_r_ok+
    jmp !t48_fail+
!t48_r_ok:

    lda #$01
    sta tc_results + 47
    jmp !t49+
!t48_fail:
    lda #$00
    sta tc_results + 47

    // ==========================================
    // Test 49: rings set persistent flags at recalc; slaying applies bonuses
    // ==========================================
!t49:
    jsr item_init_inventory

    // Resist Fire ring equipped → PFLAG_RESIST_FIRE at recalc
    lda #ITEM_TYPE_RING_RESIST_FIRE
    sta inv_item_id + EQUIP_RING
    lda #1
    sta inv_qty + EQUIP_RING
    jsr player_calc_stats
    lda player_pflags
    and #PFLAG_RESIST_FIRE
    beq !t49_fail+

    // Ring of Speed equipped → PFLAG_SPEED
    jsr item_init_inventory
    lda #ITEM_TYPE_RING_SPEED
    sta inv_item_id + EQUIP_RING
    lda #1
    sta inv_qty + EQUIP_RING
    jsr player_calc_stats
    lda player_pflags
    and #PFLAG_SPEED
    beq !t49_fail+
    lda player_pflags
    and #PFLAG_RESIST_FIRE
    bne !t49_fail+

    // Amulet of the Magi equipped → PFLAG_SEE_INVIS
    jsr item_init_inventory
    lda #ITEM_TYPE_AMULET_MAGI
    sta inv_item_id + EQUIP_AMULET
    lda #1
    sta inv_qty + EQUIP_AMULET
    jsr player_calc_stats
    lda player_pflags
    and #PFLAG_SEE_INVIS
    beq !t49_fail+

    // Ring of Slaying with +3/+4 to-hit/dam adds them to PL_TOHIT/PL_TODMG
    // (measure delta vs empty ring since stat adjustments also contribute)
    jsr item_init_inventory
    jsr player_recalc_equipment
    lda player_data + PL_TOHIT
    sta t49_base_tohit
    lda player_data + PL_TODMG
    sta t49_base_todmg
    lda #ITEM_TYPE_RING_SLAYING
    sta inv_item_id + EQUIP_RING
    lda #1
    sta inv_qty + EQUIP_RING
    lda #3
    sta inv_to_hit + EQUIP_RING
    lda #4
    sta inv_to_dam + EQUIP_RING
    jsr player_recalc_equipment
    lda player_data + PL_TOHIT
    sec
    sbc t49_base_tohit
    cmp #3
    bne !t49_fail+
    lda player_data + PL_TODMG
    sec
    sbc t49_base_todmg
    cmp #4
    bne !t49_fail+

    lda #$01
    sta tc_results + 48
    jmp !t50+
!t49_fail:
    lda #$00
    sta tc_results + 48

    // ==========================================
    // Test 50: roll_enchantment handles Phase 3 categories
    // ==========================================
!t50:
    // New wand (114) gets charges in [5, 8]
    lda #ITEM_TYPE_WAND_SLOW
    jsr roll_enchantment
    cmp #5
    bcc !t50_fail+
    cmp #9
    bcs !t50_fail+

    // New staff (119) gets charges in [3, 8]
    lda #ITEM_TYPE_STAFF_DISPEL_EVIL
    jsr roll_enchantment
    cmp #3
    bcc !t50_fail+
    cmp #9
    bcs !t50_fail+

    // Amulet of the Magi (125) gets a stat-bonus p1 (nonzero) — retry past
    // the magic_chance gate (dlvl 60 → 70% per try)
    lda #60
    sta zp_player_dlvl
    ldx #8
!t50_am_loop:
    stx t50_retries
    lda #ITEM_TYPE_AMULET_MAGI
    jsr roll_enchantment
    bne !t50_am_ok+
    ldx t50_retries
    dex
    bne !t50_am_loop-
    jmp !t50_fail+
!t50_am_ok:

    // Ring of Slaying (113) rolls to-hit and to-damage bonuses
    ldx #8
!t50_sl_loop:
    stx t50_retries
    lda #ITEM_TYPE_RING_SLAYING
    jsr roll_enchantment
    lda fi_add_to_hit
    beq !t50_sl_retry+
    lda fi_add_to_dam
    bne !t50_sl_ok+
!t50_sl_retry:
    ldx t50_retries
    dex
    bne !t50_sl_loop-
    jmp !t50_fail+
!t50_sl_ok:

    lda #$01
    sta tc_results + 49
    jmp !t51+
!t50_fail:
    lda #$00
    sta tc_results + 49

    // ==========================================
    // Test 51: calc_stats applies Amulet of the Magi p1 deterministically.
    // Regression guard: equipment bonuses must use raw arithmetic; the
    // randomized chargen stat stepping (increment_stat) ratchets 18+ stats
    // upward on every load otherwise.
    // ==========================================
!t51:
    jsr item_init_inventory
    lda #11
    sta player_data + PL_INT_BASE    // Baked natural stat (mods included)

    lda #ITEM_TYPE_AMULET_MAGI
    sta inv_item_id + EQUIP_AMULET
    lda #1
    sta inv_qty + EQUIP_AMULET
    lda #19
    sta inv_p1 + EQUIP_AMULET

    jsr player_calc_stats
    lda player_data + PL_INT_CUR
    cmp #30                     // 11 + 19, exactly
    bne !t51_fail+
    jsr player_calc_stats
    lda player_data + PL_INT_CUR
    cmp #30                     // idempotent rebuild, no ratchet
    bne !t51_fail+

    lda #$01
    sta tc_results + 50
    jmp !t52+
!t51_fail:
    lda #$00
    sta tc_results + 50

    // ==========================================
    // Test 52: legacy-save stat migration folds race/class modifiers into
    // the base exactly once with deterministic arithmetic.
    // ==========================================
!t52:
    jsr item_init_inventory
    lda #2
    sta player_data + PL_RACE     // Elf: INT +2
    lda #1
    sta player_data + PL_CLASS    // Mage: INT +3
    lda #14
    sta player_data + PL_INT_BASE

    lda #0
    sta stat_bake_mode
    jsr player_bake_stat_modifiers
    lda player_data + PL_INT_BASE
    cmp #19                     // 14 + 2 + 3, exactly
    bne !t52_fail+
    lda player_data + PL_INT_CUR
    cmp #19                     // mirrored to current
    bne !t52_fail+
    jsr player_calc_stats
    lda player_data + PL_INT_CUR
    cmp #19                     // load-path rebuild preserves it
    bne !t52_fail+

    lda #$01
    sta tc_results + 51
    jmp !t53+
!t52_fail:
    lda #$00
    sta tc_results + 51

    // ==========================================
    // Test 53: chest_find_at_df_target hits a chest (carry set, slot in X)
    // ==========================================
!t53:
    jsr item_init_floor
    lda #ITEM_TYPE_CHEST_SMALL_WOOD
    sta fi_item_id
    lda #10
    sta fi_x
    sta df_target_x
    lda #12
    sta fi_y
    sta df_target_y
    jsr chest_find_at_df_target
    bcc !t53_fail+
    cpx #0
    bne !t53_fail+
    lda #$01
    sta tc_results + 52
    jmp !t54+
!t53_fail:
    lda #$00
    sta tc_results + 52

    // ==========================================
    // Test 54: chest_find_at_df_target ignores a non-chest floor item
    // ==========================================
!t54:
    jsr item_init_floor
    lda #2                      // Dagger — not a chest
    sta fi_item_id
    lda #10
    sta fi_x
    sta df_target_x
    lda #12
    sta fi_y
    sta df_target_y
    jsr chest_find_at_df_target
    bcs !t54_fail+
    lda #$01
    sta tc_results + 53
    jmp !t55+
!t54_fail:
    lda #$00
    sta tc_results + 53

    // ==========================================
    // Test 55: chest_find_at_df_target misses on an empty tile
    // ==========================================
!t55:
    jsr item_init_floor
    lda #10
    sta df_target_x
    lda #12
    sta df_target_y
    jsr chest_find_at_df_target
    bcs !t55_fail+
    lda #$01
    sta tc_results + 54
    jmp !t56+
!t55_fail:
    lda #$00
    sta tc_results + 54

    // ==========================================
    // Test 56: chest spawn trap-init bands (VMS randint(depth)+4)
    // p1 = band trap bits | locked for each raw rng band; to_hit = 7
    // for the small wooden chest. rng_range is patched to scripted returns.
    // ==========================================
!t56:
    lda rng_range
    sta t56_save0
    lda rng_range + 1
    sta t56_save1
    lda rng_range + 2
    sta t56_save2
    :PatchJump(rng_range, test_rng_range)

    lda #20
    sta zp_player_dlvl
    lda #0
    sta t56_idx
!t56_loop:
    ldx t56_idx
    lda t56_band_table,x
    sta t_rng_ret
    lda #ITEM_TYPE_CHEST_SMALL_WOOD
    jsr roll_enchantment
    ldx t56_idx
    cmp t56_band_table + 1,x
    bne !t56_fail+
    lda fi_add_to_hit
    cmp #7
    bne !t56_fail+
    lda t56_idx
    clc
    adc #2
    sta t56_idx
    cmp #12
    bcc !t56_loop-
    lda #$01
    sta tc_results + 55
    jmp !t57+
!t56_fail:
    lda #$00
    sta tc_results + 55

    // ==========================================
    // Test 57: chest source levels per ID (128-134) land in to_hit;
    // ruined chest carries source level 0.
    // ==========================================
!t57:
    lda #0
    sta t_rng_ret
    lda #20
    sta zp_player_dlvl
    lda #0
    sta t56_idx
!t57_loop:
    lda t56_idx
    clc
    adc #ITEM_TYPE_CHEST_SMALL_WOOD
    jsr roll_enchantment
    ldx t56_idx
    lda fi_add_to_hit
    cmp chest_source_level,x
    bne !t57_fail+
    inc t56_idx
    lda t56_idx
    cmp #7
    bcc !t57_loop-
    lda #$01
    sta tc_results + 56
    jmp !t57_done+
!t57_fail:
    lda #$00
    sta tc_results + 56
!t57_done:

    // Restore rng_range's original entry
    lda t56_save0
    sta rng_range
    lda t56_save1
    sta rng_range + 1
    lda t56_save2
    sta rng_range + 2

!tests_done:
    // Jump to trampoline at $033C (below $A000) to copy results + BRK
    jmp test_exit_trampoline

t56_save0: .byte 0
t56_save1: .byte 0
t56_save2: .byte 0
t56_idx:   .byte 0
t_rng_ret: .byte 0

test_rng_range:
    lda t_rng_ret
    rts

t56_band_table:
    .byte 0,  (CHEST_P1_TRAP_POISON | CHEST_P1_LOCKED)
    .byte 2,  (CHEST_P1_TRAP_PARA | CHEST_P1_LOCKED)
    .byte 5,  (CHEST_P1_TRAP_EXPL | CHEST_P1_LOCKED)
    .byte 7,  (CHEST_P1_TRAP_SUMMON | CHEST_P1_LOCKED)
    .byte 10, (CHEST_P1_TRAP_STR | CHEST_P1_TRAP_POISON | CHEST_P1_TRAP_PARA | CHEST_P1_LOCKED)
    .byte 13, (CHEST_P1_TRAP_SUMMON | CHEST_P1_TRAP_EXPL | CHEST_P1_LOCKED)

t27_expected_name:
    .text "Dagger" ; .byte 0
t29_expected_appended_name:
    .text "Mithril Chain Mail" ; .byte 0
t29_expected_color: .byte 0
t48_expected_con: .byte 0
t50_retries: .byte 0
t49_base_tohit: .byte 0
t49_base_todmg: .byte 0

item_test_body_end:

.assert "Item test stays below MAP_BASE", item_test_body_end <= MAP_BASE, true
