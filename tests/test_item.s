// test_item.s — Runtime tests for item.s
//
// Tests: item_init_floor, floor_item_add, floor_item_find_at,
//        floor_item_remove, inv_add_item, inv_count_items, item_spawn_level.
//
// Results at $0400-$0409: $01 = pass, $00 = fail per test

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
#import "../item.s"
#import "../dungeon_render.s"
#import "../dungeon_los.s"
#import "../player_move.s"
#import "../combat.s"
#import "../monster_attack.s"
#import "../turn.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer — copy to $0400 at end (msg_print clobbers $0400)
tc_results: .fill 16, $ff

test_start:
    // Bank out BASIC ROM (needed for $A000 area used by BFS)
    :BankOutBasic()

    // Initialize result area to $ff (untested)
    ldx #15
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
    // Item at (21, 15)
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

    // Item at (22, 15)
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
    // Test 13: item_pickup nothing → carry clear
    // ==========================================
!t13:
    jsr item_init_floor

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
    // Test 14: item_drop moves item to floor
    // ==========================================
!t14:
    jsr item_init_floor
    jsr item_init_inventory

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

    // Stuff keyboard buffer
    lda #1
    sta $c6
    lda #$20
    sta $0277

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
    jmp !tests_done+
!t14_fail:
    lda #$00
    sta tc_results + 13

!tests_done:
    // Copy results to $0400 for VICE memory dump
    ldx #15
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-

    brk
