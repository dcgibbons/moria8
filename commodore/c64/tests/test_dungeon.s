// test_dungeon.s — Runtime tests for dungeon_gen.s
//
// Tests: fill_map_rock, draw_dungeon_room, check_room_overlap,
//        corridor carving, shuffle_rooms, verify_connectivity,
//        and full dungeon_generate integration.
//
// Results at $0400: $01 = pass, $00 = fail per test

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

// Exit trampoline at $080E (right after BASIC stub).
// MUST be in "Test Code" segment so run_tests.sh sets breakpoint here (below $A000).
// This avoids BASIC ROM breakpoint conflict when main code extends above $A000.
.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #34
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

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
#import "../item_defs.s"
#import "../player.s"
#import "../ui_messages.s"
#import "../ui_status.s"
#import "../ui_help_clear.s"
#import "../ui_character.s"
#import "../stat_display.s"
#import "../player_create.s"
#import "../sound.s"
#import "../dungeon_data.s"
#import "../dungeon_gen.s"
#import "../huffman.s"
#import "../dungeon_features.s"
#import "../monster.s"
#import "../tier_manager.s"
#import "../overlay.s"
#import "../monster_ai.s"
// Recall stubs — minimal footprint to keep test below MAP_BASE ($C000).
// Full recall.s adds 267 bytes; stubs save ~260 bytes.
// Safe: dungeon tests never exercise recall code paths.
.const RECALL_DATA_SIZE = MAX_CREATURES * 4
recall_data_start:
recall_kills:   .byte 0
recall_deaths:  .byte 0
recall_attacks: .byte 0
recall_spells:  .byte 0
recall_data_end:
recall_spell_bit: .byte 1, 2, 4, 8, 16, 32, 64
recall_clear: rts
#import "../monster_magic.s"
#import "../item.s"
#import "../special_rooms.s"
#import "../ego_items.s"
#import "../special_rooms_stubs.s"
#import "../player_items.s"
#import "../spell_data.s"
#import "../projectile.s"
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
// ui_help stubs — saves ~900 bytes; these are never called during dungeon tests.
// Full ui_help.s + ui_help_data.s adds ~900 bytes of help screen strings/code.
ui_help_display:
help_draw_line:
help_draw_hborder:
    rts
#import "../ui_trampoline_stubs.s"

.assert "Test code must not cross MAP_BASE", * < MAP_BASE, true

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch variables
t9_sum_before: .byte 0
t14_magma:     .byte 0
t14_quartz:    .byte 0
t16_counter:   .byte 0
t19_found:     .byte 0
t19_save_row:  .byte 0
t19_tile:      .byte 0
t24_carry_result: .byte 0               // Carry result for test 24 (survives subroutine calls)
t29_retry:     .byte 0                   // Retry counter for test 29
t32_pre_count: .byte 0                   // Pre-spawn monster count for test 32
t32_post_count:.byte 0                   // Post-spawn monster count for test 32
t32_check_type:.byte 0                   // Saved creature type for test 32
tc_results: .fill 35, $ff              // Test results buffer (copied to $0400 before brk)

test_start:
    // Initialize result area to $ff (untested)
    ldx #31
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    // Seed RNG deterministically for reproducible tests
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    // Set player dungeon level to 1 (needed by place_traps)
    lda #1
    sta zp_player_dlvl

    // ==========================================
    // Test 1: fill_map_rock fills with $10
    // Spot-check several map locations
    // ==========================================
    jsr fill_map_rock

    // Check (0,0)
    lda MAP_BASE
    cmp #TILE_WALL_H
    bne !t1_fail+
    // Check (40,24) = MAP_BASE + 24*80 + 40 = $C000 + 1960 = $C7A8
    lda MAP_BASE + 1960
    cmp #TILE_WALL_H
    bne !t1_fail+
    // Check last byte: (79,47) = MAP_BASE + 47*80 + 79 = $C000 + 3839 = $CEDF
    lda MAP_BASE + 3839
    cmp #TILE_WALL_H
    bne !t1_fail+
    lda #$01
    sta tc_results
    jmp !t1_done+
!t1_fail:
    lda #$00
    sta tc_results
!t1_done:

    // ==========================================
    // Test 2: draw_dungeon_room produces correct tiles
    // Place room at x=10, y=10, w=5, h=3
    // ==========================================
    jsr fill_map_rock           // Reset map

    lda #10
    sta dg_room_x
    lda #10
    sta dg_room_y
    lda #5
    sta dg_room_w
    lda #3
    sta dg_room_h

    jsr draw_dungeon_room

    // Check top-left corner at (9,9) — should be TILE_CORNER_TL | DUNGEON_FLAGS
    ldx #9
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #9
    lda (zp_ptr0),y
    cmp #TILE_CORNER_TL | DUNGEON_FLAGS
    bne !t2_fail+

    // Check floor at (10,10) — should be TILE_FLOOR | DUNGEON_FLAGS
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    cmp #TILE_FLOOR | DUNGEON_FLAGS
    bne !t2_fail+

    // Check right vertical wall at (15,10) — TILE_WALL_V | DUNGEON_FLAGS
    // wall right = room_x + room_w = 10 + 5 = 15
    ldy #15
    lda (zp_ptr0),y
    cmp #TILE_WALL_V | DUNGEON_FLAGS
    bne !t2_fail+

    lda #$01
    sta tc_results+1
    jmp !t2_done+
!t2_fail:
    lda #$00
    sta tc_results+1
!t2_done:

    // ==========================================
    // Test 3: check_room_overlap returns clear for non-overlapping
    // Room 0 at (10,10,5,3), check candidate at (30,30,5,3)
    // ==========================================
    lda #1
    sta dg_idx                  // 1 room placed
    lda #10
    sta room_x
    sta room_y
    lda #5
    sta room_w
    lda #3
    sta room_h

    lda #30
    sta dg_room_x
    sta dg_room_y
    lda #5
    sta dg_room_w
    lda #3
    sta dg_room_h

    jsr check_room_overlap
    bcs !t3_fail+               // Carry set = overlap (bad)

    lda #$01
    sta tc_results+2
    jmp !t3_done+
!t3_fail:
    lda #$00
    sta tc_results+2
!t3_done:

    // ==========================================
    // Test 4: check_room_overlap returns set for overlapping
    // Room 0 at (10,10,5,3), check candidate at (12,11,5,3) — overlaps
    // ==========================================
    lda #12
    sta dg_room_x
    lda #11
    sta dg_room_y
    lda #5
    sta dg_room_w
    lda #3
    sta dg_room_h

    jsr check_room_overlap
    bcc !t4_fail+               // Carry clear = no overlap (bad)

    lda #$01
    sta tc_results+3
    jmp !t4_done+
!t4_fail:
    lda #$00
    sta tc_results+3
!t4_done:

    // ==========================================
    // Test 5: carve_h_corridor creates floor tiles
    // Carve horizontal corridor from x=10 to x=20 at y=5
    // ==========================================
    jsr fill_map_rock

    lda #10
    sta dg_cx1
    lda #20
    sta dg_cx2
    lda #5
    sta dg_cy1

    jsr carve_h_corridor

    // Check tile at (15, 5) — should be floor
    ldx #5
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #15
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !t5_fail+

    lda #$01
    sta tc_results+4
    jmp !t5_done+
!t5_fail:
    lda #$00
    sta tc_results+4
!t5_done:

    // ==========================================
    // Test 6: carve_v_corridor creates floor tiles
    // Carve vertical corridor from y=10 to y=20 at x=5
    // ==========================================
    jsr fill_map_rock

    lda #5
    sta dg_cx1
    lda #10
    sta dg_cy1
    lda #20
    sta dg_cy2

    jsr carve_v_corridor

    // Check tile at (5, 15) — should be floor
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #5
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !t6_fail+

    lda #$01
    sta tc_results+5
    jmp !t6_done+
!t6_fail:
    lda #$00
    sta tc_results+5
!t6_done:

    // ==========================================
    // Test 7: Corridor through lit vertical wall produces door
    // Draw a room, then carve a horizontal corridor through its wall
    // ==========================================
    jsr fill_map_rock

    // Place room at x=20, y=10, w=5, h=3
    lda #20
    sta dg_room_x
    lda #10
    sta dg_room_y
    lda #5
    sta dg_room_w
    lda #3
    sta dg_room_h
    jsr draw_dungeon_room

    // Carve h corridor from x=15 to x=22 at y=11 (through left wall at x=19)
    lda #15
    sta dg_cx1
    lda #22
    sta dg_cx2
    lda #11
    sta dg_cy1
    jsr carve_h_corridor

    // Check tile at (19, 11) — left vertical wall → should be door type
    ldx #11
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #19
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    // Should be TILE_DOOR_OPEN ($70) or TILE_DOOR_CLOSED ($80) — never TILE_SECRET
    cmp #TILE_DOOR_OPEN
    beq !t7_pass+
    cmp #TILE_DOOR_CLOSED
    beq !t7_pass+
    jmp !t7_fail+
!t7_pass:
    lda #$01
    sta tc_results+6
    jmp !t7_done+
!t7_fail:
    lda #$00
    sta tc_results+6
!t7_done:

    // ==========================================
    // Test 8: Corridor through unlit wall tile produces floor
    // Unlit wall = rock fill (no FLAG_LIT set)
    // ==========================================
    jsr fill_map_rock

    // Carve corridor from x=10 to x=20 at y=5 (all rock)
    lda #10
    sta dg_cx1
    lda #20
    sta dg_cx2
    lda #5
    sta dg_cy1
    jsr carve_h_corridor

    // Every tile from x=10 to x=20 at y=5 should be floor (rock has no LIT)
    ldx #5
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !t8_fail+

    lda #$01
    sta tc_results+7
    jmp !t8_done+
!t8_fail:
    lda #$00
    sta tc_results+7
!t8_done:

    // ==========================================
    // Test 9: shuffle_rooms preserves all room data
    // Set up 4 rooms with known values, shuffle, verify all present
    // ==========================================
    lda #4
    sta room_count

    // Room 0: x=10,y=10,w=5,h=3
    lda #10
    sta room_x + 0
    sta room_y + 0
    lda #5
    sta room_w + 0
    lda #3
    sta room_h + 0

    // Room 1: x=30,y=10,w=6,h=4
    lda #30
    sta room_x + 1
    lda #10
    sta room_y + 1
    lda #6
    sta room_w + 1
    lda #4
    sta room_h + 1

    // Room 2: x=50,y=20,w=7,h=5
    lda #50
    sta room_x + 2
    lda #20
    sta room_y + 2
    lda #7
    sta room_w + 2
    lda #5
    sta room_h + 2

    // Room 3: x=10,y=30,w=4,h=3
    lda #10
    sta room_x + 3
    lda #30
    sta room_y + 3
    lda #4
    sta room_w + 3
    lda #3
    sta room_h + 3

    // Compute sum of all room_x values before shuffle
    lda room_x + 0
    clc
    adc room_x + 1
    clc
    adc room_x + 2
    clc
    adc room_x + 3
    sta t9_sum_before              // Sum should be 10+30+50+10 = 100

    jsr shuffle_rooms

    // room_count should be unchanged
    lda room_count
    cmp #4
    bne !t9_fail+

    // Compute sum after shuffle — should still be 100
    lda room_x + 0
    clc
    adc room_x + 1
    clc
    adc room_x + 2
    clc
    adc room_x + 3
    cmp t9_sum_before
    bne !t9_fail+

    lda #$01
    sta tc_results+8
    jmp !t9_done+
!t9_fail:
    lda #$00
    sta tc_results+8
!t9_done:
    // ==========================================
    // Test 10: verify_connectivity returns clear for connected layout
    // Set up 2 rooms connected by a corridor, place stairs
    // ==========================================
!t10_start:
    jsr fill_map_rock

    lda #2
    sta room_count

    // Room 0: x=10, y=10, w=5, h=3
    lda #10
    sta room_x + 0
    sta room_y + 0
    sta dg_room_x
    sta dg_room_y
    lda #5
    sta room_w + 0
    sta dg_room_w
    lda #3
    sta room_h + 0
    sta dg_room_h
    jsr draw_dungeon_room

    // Room 1: x=30, y=10, w=5, h=3
    lda #30
    sta room_x + 1
    sta dg_room_x
    lda #10
    sta room_y + 1
    sta dg_room_y
    lda #5
    sta room_w + 1
    sta dg_room_w
    lda #3
    sta room_h + 1
    sta dg_room_h
    jsr draw_dungeon_room

    // Connect with a horizontal corridor at y=11 from x=12 to x=32
    lda #12
    sta dg_cx1
    lda #32
    sta dg_cx2
    lda #11
    sta dg_cy1
    jsr carve_h_corridor

    // Place stairs_up in room 0
    lda #12
    sta stairs_up_x
    lda #11
    sta stairs_up_y

    jsr verify_connectivity
    bcs !t10_fail+

    lda #$01
    sta tc_results+9
    jmp !t10_done+
!t10_fail:
    lda #$00
    sta tc_results+9
!t10_done:

    // ==========================================
    // Test 11: verify_connectivity returns set for isolated room
    // Two rooms, no corridor between them
    // ==========================================
    jsr fill_map_rock

    lda #2
    sta room_count

    // Room 0 at (10,10,5,3)
    lda #10
    sta room_x + 0
    sta room_y + 0
    sta dg_room_x
    sta dg_room_y
    lda #5
    sta room_w + 0
    sta dg_room_w
    lda #3
    sta room_h + 0
    sta dg_room_h
    jsr draw_dungeon_room

    // Room 1 at (50,30,5,3) — completely isolated
    lda #50
    sta room_x + 1
    sta dg_room_x
    lda #30
    sta room_y + 1
    sta dg_room_y
    lda #5
    sta room_w + 1
    sta dg_room_w
    lda #3
    sta room_h + 1
    sta dg_room_h
    jsr draw_dungeon_room

    // Stairs up in room 0
    lda #12
    sta stairs_up_x
    lda #11
    sta stairs_up_y

    jsr verify_connectivity
    bcc !t11_fail+               // Should be carry SET (unreachable)

    lda #$01
    sta tc_results+10
    jmp !t11_done+
!t11_fail:
    lda #$00
    sta tc_results+10
!t11_done:

    // ==========================================
    // Test 12: Full dungeon_generate produces >= 2 rooms
    // ==========================================
    lda #1
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir

    jsr dungeon_generate

    lda room_count
    cmp #2
    bcs !t12_pass+
    jmp !t12_fail+
!t12_pass:
    lda #$01
    sta tc_results+11
    jmp !t12_done+
!t12_fail:
    lda #$00
    sta tc_results+11
!t12_done:

    // ==========================================
    // Test 13: Stairs tiles exist on map after generation
    // Check that stairs_up tile is correct on map
    // ==========================================
    lda stairs_up_x
    ldy stairs_up_y
    jsr write_tile_at_xy
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_UP
    bne !t13_fail+

    // Check stairs_dn1 tile
    lda stairs_dn1_x
    ldy stairs_dn1_y
    jsr write_tile_at_xy
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    bne !t13_fail+

    lda #$01
    sta tc_results+12
    jmp !t13_done+
!t13_fail:
    lda #$00
    sta tc_results+12
!t13_done:

    // ==========================================
    // Test 14: Map has both magma and quartz tiles after generation
    // Scan entire map ($C000-$CEFF, 15 pages) for magma and quartz
    // ==========================================
    lda #0
    sta t14_magma
    sta t14_quartz

    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi

    ldy #0
!t14_scan:
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_MAGMA
    bne !t14_not_m+
    inc t14_magma
!t14_not_m:
    cmp #TILE_QUARTZ
    bne !t14_not_q+
    inc t14_quartz
!t14_not_q:
    iny
    bne !t14_scan-

    inc zp_ptr0_hi
    lda zp_ptr0_hi
    cmp #$cf                // Pages $C0-$CE = 15 pages = 3840 bytes
    bne !t14_scan-

    // Need both types present
    lda t14_magma
    beq !t14_fail+
    lda t14_quartz
    beq !t14_fail+

    lda #$01
    sta tc_results+13
    jmp !t14_done+
!t14_fail:
    lda #$00
    sta tc_results+13
!t14_done:

    // ==========================================
    // Test 15: Single-tile corridor (cx1 == cx2) handled correctly
    // ==========================================
    jsr fill_map_rock

    lda #15
    sta dg_cx1
    sta dg_cx2              // Same start and end
    lda #10
    sta dg_cy1

    jsr carve_h_corridor

    // Tile at (15, 10) should be floor
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #15
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !t15_fail+

    lda #$01
    sta tc_results+14
    jmp !t15_done+
!t15_fail:
    lda #$00
    sta tc_results+14
!t15_done:

    // ==========================================
    // Test 16: Corridor doors are never secret (DG5 fix)
    // Carve corridors through room walls 10 times; verify
    // no TILE_SECRET ($F0) is produced at the junction.
    // ==========================================
    lda #10
    sta t16_counter
!t16_loop:
    jsr fill_map_rock

    // Place room at x=20, y=10, w=5, h=3
    lda #20
    sta dg_room_x
    lda #10
    sta dg_room_y
    lda #5
    sta dg_room_w
    lda #3
    sta dg_room_h
    jsr draw_dungeon_room

    // Carve h corridor through left wall at x=19
    lda #15
    sta dg_cx1
    lda #22
    sta dg_cx2
    lda #11
    sta dg_cy1
    jsr carve_h_corridor

    // Check tile at (19, 11) — must NOT be TILE_SECRET
    ldx #11
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #19
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    beq !t16_fail+

    dec t16_counter
    bne !t16_loop-

    // All 10 iterations passed — no secret doors at junctions
    lda #$01
    sta tc_results+15
    jmp !t16_done+
!t16_fail:
    lda #$00
    sta tc_results+15
!t16_done:

    // ==========================================
    // Test 17: add_corridor_doors creates door when corridor is adjacent to room
    // Set up a room, then manually place corridor floor tiles adjacent to the
    // room's right wall. Call add_corridor_doors. The wall between them should
    // become a door.
    // ==========================================
    jsr fill_map_rock

    // Place room at x=20, y=10, w=4, h=3
    lda #20
    sta dg_room_x
    lda #10
    sta dg_room_y
    lda #4
    sta dg_room_w
    lda #3
    sta dg_room_h
    jsr draw_dungeon_room

    // Also populate room arrays (add_corridor_doors iterates rooms)
    lda #1
    sta room_count
    lda #20
    sta room_x
    lda #10
    sta room_y
    lda #4
    sta room_w
    lda #3
    sta room_h

    // Room right wall is at x=24 (room_x + room_w = 20+4)
    // Place corridor floor at x=25, y=11 (adjacent to right wall)
    ldx #11
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #25
    lda #TILE_FLOOR                 // Corridors have no flags
    sta (zp_ptr0),y

    // Verify the wall at (24, 11) is currently TILE_WALL_V
    ldy #24
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_WALL_V
    bne !t17_fail+

    // Run add_corridor_doors
    jsr add_corridor_doors

    // Now check (24, 11) — should be a door (TILE_DOOR_OPEN or TILE_DOOR_CLOSED)
    ldx #11
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #24
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !t17_pass+
    cmp #TILE_DOOR_CLOSED
    beq !t17_pass+
    jmp !t17_fail+

!t17_pass:
    lda #$01
    sta tc_results+16
    jmp !t17_done+
!t17_fail:
    lda #$00
    sta tc_results+16
!t17_done:

    // ==========================================
    // Test 18: add_corridor_doors does NOT create door when only one side is floor
    // Wall with floor on one side and rock on the other should stay a wall.
    // ==========================================
    jsr fill_map_rock

    // Place room at x=20, y=10, w=4, h=3
    lda #20
    sta dg_room_x
    lda #10
    sta dg_room_y
    lda #4
    sta dg_room_w
    lda #3
    sta dg_room_h
    jsr draw_dungeon_room

    // Also populate room arrays
    lda #1
    sta room_count
    lda #20
    sta room_x
    lda #10
    sta room_y
    lda #4
    sta room_w
    lda #3
    sta room_h

    // DON'T place any corridor floor — right wall has room floor on left, rock on right

    // Run add_corridor_doors
    jsr add_corridor_doors

    // Wall at (24, 11) should still be TILE_WALL_V (no corridor on other side)
    ldx #11
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #24
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_WALL_V
    beq !t18_pass+
    jmp !t18_fail+

!t18_pass:
    lda #$01
    sta tc_results+17
    jmp !t18_done+
!t18_fail:
    lda #$00
    sta tc_results+17
!t18_done:

    // ==========================================
    // Test 19: Corridor floor has no FLAG_VISITED after generation
    // After dungeon_generate, corridor floor tiles should have no flags.
    // ==========================================
    // Generate a fresh dungeon
    lda #1
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir
    jsr dungeon_generate

    // Find a corridor floor tile: scan for TILE_FLOOR without FLAG_LIT
    // (Room floors have FLAG_LIT; corridor floors do not)
    lda #0
    sta t19_found
    ldx #1
!t19_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    stx t19_save_row

    ldy #1
!t19_col:
    lda (zp_ptr0),y
    sta t19_tile
    and #TILE_TYPE_MASK
    bne !t19_next_col+          // Not floor → skip
    // It's a floor tile — check if it has FLAG_LIT
    lda t19_tile
    and #FLAG_LIT
    bne !t19_next_col+          // Has FLAG_LIT → room floor, skip
    // Corridor floor found — check FLAG_VISITED is NOT set
    lda t19_tile
    and #FLAG_VISITED
    bne !t19_fail+              // FLAG_VISITED set → FAIL
    lda #1
    sta t19_found
    jmp !t19_check+             // Found one good tile, that's enough
!t19_next_col:
    iny
    cpy #MAP_COLS - 1
    bne !t19_col-

    ldx t19_save_row
    inx
    cpx #MAP_ROWS - 1
    bne !t19_row-

!t19_check:
    lda t19_found
    beq !t19_fail+              // Didn't find any corridor floor (unlikely)

    lda #$01
    sta tc_results+18
    jmp !t19_done+
!t19_fail:
    lda #$00
    sta tc_results+18
!t19_done:

    // ==========================================
    // Test 20: Lit room floor has FLAG_LIT but no FLAG_VISITED
    // After generation, room floors with FLAG_LIT should NOT have FLAG_VISITED.
    // ==========================================
    // Use the dungeon from test 19 (still valid)
    lda #0
    sta t19_found               // Reuse as found flag
    ldx #0
!t20_room_loop:
    cpx room_count
    bcs !t20_check+

    // Only check lit rooms
    lda room_lit,x
    beq !t20_next_room+

    // Check floor tile at (room_x[i], room_y[i])
    stx t19_save_row            // Save room index
    ldy room_y,x
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy room_x,x
    lda (zp_ptr0),y
    sta t19_tile

    // Should have FLAG_LIT
    and #FLAG_LIT
    beq !t20_fail+

    // Should NOT have FLAG_VISITED
    lda t19_tile
    and #FLAG_VISITED
    bne !t20_fail+

    lda #1
    sta t19_found
    ldx t19_save_row
    jmp !t20_next_room+

!t20_next_room:
    inx
    jmp !t20_room_loop-

!t20_check:
    lda t19_found
    beq !t20_fail+

    lda #$01
    sta tc_results+19
    jmp !t20_done+
!t20_fail:
    lda #$00
    sta tc_results+19
!t20_done:

    // ==========================================
    // Test 21: update_visibility sets FLAG_VISITED within torch radius
    // Set player at known position, call update_visibility, verify tiles.
    // ==========================================
    // Generate fresh dungeon to have clean flags
    lda #1
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir
    jsr dungeon_generate

    // Player is positioned by dungeon_generate
    // Set light radius to 1
    lda #1
    sta zp_light_radius

    // Ensure player tile does NOT have FLAG_VISITED before update
    // (It shouldn't, since we removed FLAG_VISITED from generation)
    // Call update_visibility
    jsr update_visibility

    // Check that tile at player position now has FLAG_VISITED
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    lda (zp_ptr0),y
    and #FLAG_VISITED
    beq !t21_fail+

    // Check an adjacent tile (player_x+1, player_y) — within radius 1
    ldy zp_player_x
    iny
    lda (zp_ptr0),y
    and #FLAG_VISITED
    beq !t21_fail+

    lda #$01
    sta tc_results+20
    jmp !t21_done+
!t21_fail:
    lda #$00
    sta tc_results+20
!t21_done:

    // ==========================================
    // Test 22: reveal_room sets FLAG_VISITED on all room tiles
    // Set up a room, call reveal_room, check corner and floor tiles.
    // ==========================================
    jsr fill_map_rock

    // Place room at x=20, y=10, w=5, h=3
    lda #1
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
    sta room_lit                // Mark as lit

    jsr draw_dungeon_room

    // Verify tiles DON'T have FLAG_VISITED yet (DUNGEON_FLAGS = FLAG_LIT only)
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #FLAG_VISITED
    bne !t22_fail+              // Should NOT be visited yet

    // Now reveal the room
    ldx #0
    jsr reveal_room

    // Check floor at (20, 10) — should now have FLAG_VISITED
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #FLAG_VISITED
    beq !t22_fail+

    // Check top-left corner at (19, 9) — should also have FLAG_VISITED
    ldx #9
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #19
    lda (zp_ptr0),y
    and #FLAG_VISITED
    beq !t22_fail+

    // Check bottom-right corner at (25, 13)
    ldx #13
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #25
    lda (zp_ptr0),y
    and #FLAG_VISITED
    beq !t22_fail+

    lda #$01
    sta tc_results+21
    jmp !t22_done+
!t22_fail:
    lda #$00
    sta tc_results+21
!t22_done:

    // ==========================================
    // Test 23: Dark room has no FLAG_LIT after darken_rooms
    // Set up rooms, set one as dark, call darken_rooms.
    // ==========================================
    jsr fill_map_rock

    lda #2
    sta room_count

    // Room 0: x=10, y=10, w=5, h=3 — dark
    lda #10
    sta room_x
    sta room_y
    sta dg_room_x
    sta dg_room_y
    lda #5
    sta room_w
    sta dg_room_w
    lda #3
    sta room_h
    sta dg_room_h
    lda #0
    sta room_lit                // Dark room
    jsr draw_dungeon_room

    // Room 1: x=30, y=10, w=5, h=3 — lit
    lda #30
    sta room_x + 1
    sta dg_room_x
    lda #10
    sta room_y + 1
    sta dg_room_y
    lda #5
    sta room_w + 1
    sta dg_room_w
    lda #3
    sta room_h + 1
    sta dg_room_h
    lda #1
    sta room_lit + 1            // Lit room
    jsr draw_dungeon_room

    // Before darken_rooms, dark room floor at (10,10) should have FLAG_LIT
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    and #FLAG_LIT
    beq !t23_fail+              // Should be lit before darken

    // Call darken_rooms
    jsr darken_rooms

    // Dark room floor at (10,10) should NOT have FLAG_LIT
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    and #FLAG_LIT
    bne !t23_fail+              // Should be dark now

    // Dark room wall at (9,9) should also NOT have FLAG_LIT
    ldx #9
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #9
    lda (zp_ptr0),y
    and #FLAG_LIT
    bne !t23_fail+              // Wall should be dark too

    // Lit room floor at (30,10) should STILL have FLAG_LIT
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #30
    lda (zp_ptr0),y
    and #FLAG_LIT
    beq !t23_fail+              // Lit room should be unchanged

    lda #$01
    sta tc_results+22
    jmp !t23_done+
!t23_fail:
    lda #$00
    sta tc_results+22
!t23_done:

    // ==========================================
    // Test 24: trap_check_at_player sets carry on trap
    // Place a trap at player position, verify carry is set.
    // ==========================================

    jsr fill_map_rock

    // Set up a floor tile at player position
    lda #20
    sta zp_player_x
    lda #20
    sta zp_player_y

    // Write floor tile at player position
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR
    sta (zp_ptr0),y

    // Place trap at player's position in the trap table
    lda #1
    sta trap_count
    lda #20
    sta trap_x
    sta trap_y
    lda #TRAP_OPEN_PIT
    sta trap_type

    // Set up enough player state so trap_apply_damage won't crash
    lda #50
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Clear message state so -more- prompt doesn't wait for keypress.
    // msg_print sets MSG_PENDING, so the second msg_print in trap handler
    // will trigger -more- and call input_get_key. Pre-stuff keyboard buffer.
    lda #0
    sta zp_msg_flags
    lda #4
    sta $c6                     // Keyboard buffer count (enough for multiple -more-)
    lda #$20                    // Space key
    sta $0277
    sta $0278
    sta $0279
    sta $027a

    jsr trap_check_at_player
    // Save carry result immediately (screen may be clobbered)
    lda #$00
    bcc !t24_no_carry+
    lda #$01
!t24_no_carry:
    sta t24_carry_result

    // Now write test 24 result
    lda t24_carry_result
    sta tc_results+23

    // ==========================================
    // Test 25: trap_check_at_player clears carry on no trap
    // No traps in table → carry should be clear.
    // ==========================================
    lda #0
    sta trap_count              // Empty trap table

    jsr trap_check_at_player
    bcc !t25_pass+
    jmp !t25_fail+

!t25_pass:
    lda #$01
    sta tc_results+24
    jmp !t25_done+
!t25_fail:
    lda #$00
    sta tc_results+24
!t25_done:

    // ==========================================
    // Test 26: place_secrets creates TILE_SECRET tiles
    // Generate a dungeon, then count secret tiles on the map.
    // (place_secrets is called by dungeon_generate now)
    // ==========================================

    lda #3
    sta zp_player_dlvl          // Use deeper level for more doors
    lda #0
    sta level_entry_dir
    jsr dungeon_generate

    // Scan map for TILE_SECRET tiles
    lda #0
    sta t19_found               // Reuse as counter
    ldx #1
!t26_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    stx t19_save_row
    ldy #1
!t26_col:
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    bne !t26_next+
    inc t19_found
!t26_next:
    iny
    cpy #MAP_COLS - 1
    bne !t26_col-
    ldx t19_save_row
    inx
    cpx #MAP_ROWS - 1
    bne !t26_row-

    // Should have at least 1 secret door (place_secrets converts 1-3)
    // Note: might be 0 if no closed doors were found; try multiple times
    lda t19_found
    bne !t26_pass+
    // Retry with a different seed
    lda #$aa
    sta zp_rng_0
    lda #$55
    sta zp_rng_1
    jsr dungeon_generate
    // Scan again
    lda #0
    sta t19_found
    ldx #1
!t26_row2:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    stx t19_save_row
    ldy #1
!t26_col2:
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    bne !t26_next2+
    inc t19_found
!t26_next2:
    iny
    cpy #MAP_COLS - 1
    bne !t26_col2-
    ldx t19_save_row
    inx
    cpx #MAP_ROWS - 1
    bne !t26_row2-
    lda t19_found
    bne !t26_pass+
    jmp !t26_fail+

!t26_pass:
    lda #$01
    sta tc_results+25
    jmp !t26_done+
!t26_fail:
    lda #$00
    sta tc_results+25
!t26_done:

    // ==========================================
    // Test 27: run_check_stop stops at stairs
    // Place player on stairs tile, verify carry set.
    // ==========================================
    jsr fill_map_rock

    // Create a small corridor with stairs
    lda #20
    sta zp_player_x
    lda #20
    sta zp_player_y

    // Place stairs tile at player position
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_STAIRS_DN
    sta (zp_ptr0),y

    // Set up running direction (east)
    lda #3                      // DIR_E
    sta zp_run_dir

    // Set run_was_lit to 0 (corridor)
    lda #0
    sta run_was_lit

    jsr run_check_stop
    bcs !t27_pass+
    jmp !t27_fail+

!t27_pass:
    lda #$01
    sta tc_results+26
    jmp !t27_done+
!t27_fail:
    lda #$00
    sta tc_results+26
!t27_done:

    // ==========================================
    // Test 28: run_check_stop continues on straight corridor
    // Place player on floor tile in a straight corridor with no
    // intersections, doors, or special tiles → carry clear.
    // ==========================================
    jsr fill_map_rock

    // Create a straight horizontal corridor at y=20, x=18..22
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #18
!t28_carve:
    lda #TILE_FLOOR             // No flags (corridor)
    sta (zp_ptr0),y
    iny
    cpy #23
    bne !t28_carve-

    // Player at (20, 20), running east
    lda #20
    sta zp_player_x
    sta zp_player_y
    lda #3                      // DIR_E
    sta zp_run_dir
    lda #0
    sta run_was_lit             // Corridor (unlit)

    jsr run_check_stop
    bcc !t28_pass+
    jmp !t28_fail+

!t28_pass:
    lda #$01
    sta tc_results+27
    jmp !t28_done+
!t28_fail:
    lda #$00
    sta tc_results+27
!t28_done:

    // ============================================================
    // Test 29: assign_special_room on dlvl=8 sets at least one
    //          room_type != RT_NORMAL (100 fast iterations,
    //          RNG evolves naturally from previous tests)
    // ============================================================
    lda #0
    sta t29_retry
!t29_loop:
    // Set up conditions for assign_special_room (no reseed)
    lda #8
    sta zp_player_dlvl
    lda #5
    sta room_count

    jsr assign_special_room

    // Check if any room_type != RT_NORMAL
    ldx room_count
    dex
!t29_scan:
    lda room_type,x
    bne !t29_found+             // Non-zero = special
    dex
    bpl !t29_scan-
    // Not found this iteration — try again
    inc t29_retry
    lda t29_retry
    cmp #100
    bne !t29_loop-
    // Failed all 100 attempts
    lda #$00
    sta tc_results+28
    jmp !t29_done+
!t29_found:
    lda #$01
    sta tc_results+28
!t29_done:

    // ============================================================
    // Test 30: assign_special_room on dlvl=1 leaves all RT_NORMAL
    //          (dlvl < 3 → early exit, 10 fast iterations)
    // ============================================================
    lda #10
    sta t29_retry
!t30_loop:
    lda #1
    sta zp_player_dlvl
    lda #5
    sta room_count

    jsr assign_special_room

    // All room_type should be RT_NORMAL
    ldx room_count
    dex
!t30_scan:
    lda room_type,x
    bne !t30_fail+              // Non-zero = unexpected special
    dex
    bpl !t30_scan-
    dec t29_retry
    bne !t30_loop-
    // All 10 passes were normal
    lda #$01
    sta tc_results+29
    jmp !t30_done+
!t30_fail:
    lda #$00
    sta tc_results+29
!t30_done:

    // ============================================================
    // Test 31: vault_seal_entrance converts a door to TILE_SECRET
    //          on vault room perimeter
    // ============================================================
    // Generate at dlvl=5, then force a vault on room 1
    lda #5
    sta zp_player_dlvl
    jsr dungeon_generate

    // Force room 1 as vault (regardless of what assign_special_room picked)
    lda room_count
    cmp #2
    bcc !t31_skip+              // Need at least 2 rooms

    // Clear all room types, set room 1 to vault
    ldx room_count
    dex
    lda #RT_NORMAL
!t31_clear:
    sta room_type,x
    dex
    bpl !t31_clear-
    lda #RT_VAULT
    sta room_type + 1

    // Place a door on the top wall of room 1
    // Top wall row = room_y[1] - 1
    lda room_y + 1
    sec
    sbc #1
    tax                         // X = wall row
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy room_x + 1             // First column of room
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y

    // Call vault_seal_entrance
    jsr vault_seal_entrance

    // Verify tile is now TILE_SECRET ($F0)
    lda room_y + 1
    sec
    sbc #1
    tax
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy room_x + 1
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    beq !t31_pass+
!t31_skip:
    lda #$00
    sta tc_results+30
    jmp !t31_done+
!t31_pass:
    lda #$01
    sta tc_results+30
!t31_done:

    // ============================================================
    // Test 32: spawn_special_room_monsters with RT_PIT creates
    //          monsters (verify count increased, all same type)
    // ============================================================
    // Generate at dlvl=4 (embedded creatures go to level ~5,
    // pick_creature_type needs cr_level in [max(1,dlvl-2), dlvl+3])
    lda #4
    sta zp_player_dlvl
    jsr dungeon_generate

    // Force room 1 as pit
    lda room_count
    cmp #2
    bcs !t32_has_rooms+
    jmp !t32_skip+
!t32_has_rooms:
    ldx room_count
    dex
    lda #RT_NORMAL
!t32_clear:
    sta room_type,x
    dex
    bpl !t32_clear-
    lda #RT_PIT
    sta room_type + 1

    // Clear monster table
    jsr monster_init_table
    lda #0
    sta zp_mon_count

    // Place player away from room 1 (at 1,1)
    lda #1
    sta zp_player_x
    sta zp_player_y

    // Save pre-spawn count
    lda zp_mon_count
    sta t32_pre_count

    // Spawn special room monsters
    jsr spawn_special_room_monsters

    // Recount monsters (inline — save.s not imported)
    lda #0
    sta zp_mon_count
    ldx #0
!t32_recount:
    cpx #MAX_MONSTERS
    bcs !t32_rc_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !t32_rc_next+
    inc zp_mon_count
!t32_rc_next:
    inx
    jmp !t32_recount-
!t32_rc_done:
    lda zp_mon_count
    sta t32_post_count

    // Must have spawned at least 1 (pit spawns 4-8)
    lda t32_post_count
    cmp t32_pre_count
    beq !t32_skip+              // No new monsters = fail
    bcc !t32_skip+              // Somehow fewer = fail

    // Verify all spawned monsters are the same type (pit property)
    // Read first monster's type
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !t32_skip+              // No monster in slot 0
    sta t32_check_type

    // Check remaining slots
    ldx #1
!t32_type_loop:
    cpx #MAX_MONSTERS
    bcs !t32_type_ok+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !t32_next+
    cmp t32_check_type
    bne !t32_skip+              // Different type = not a proper pit
!t32_next:
    inx
    jmp !t32_type_loop-
!t32_type_ok:
    lda #$01
    sta tc_results+31
    jmp !t32_done+
!t32_skip:
    lda #$00
    sta tc_results+31
!t32_done:

    // ============================================================
    // Test 33: verify_connectivity preserves I flag (sei context, connected)
    // If verify_connectivity called cli unconditionally, the I flag would be
    // cleared on return even though the caller held sei.  With php/plp this
    // can't happen.  Layout: 2 rooms + corridor, connected.
    // ============================================================
    jsr fill_map_rock
    lda #2
    sta room_count
    // Room 0 at (10,10,5,3)
    lda #10
    sta dg_room_x
    sta dg_room_y
    sta room_x
    sta room_y
    lda #5
    sta dg_room_w
    sta room_w
    lda #3
    sta dg_room_h
    sta room_h
    jsr draw_dungeon_room
    // Room 1 at (30,10,5,3)
    lda #30
    sta dg_room_x
    sta room_x + 1
    lda #10
    sta dg_room_y
    sta room_y + 1
    lda #5
    sta dg_room_w
    sta room_w + 1
    lda #3
    sta dg_room_h
    sta room_h + 1
    jsr draw_dungeon_room
    // Connect rooms
    lda #12
    sta dg_cx1
    lda #32
    sta dg_cx2
    lda #11
    sta dg_cy1
    jsr carve_h_corridor
    lda #12
    sta stairs_up_x
    lda #11
    sta stairs_up_y
    // Call with sei active; I flag must still be set on return
    sei
    jsr verify_connectivity     // Connected → carry clear; I flag must stay set
    php                         // Capture processor status
    pla                         // Into A
    and #$04                    // Bit 2 = I flag
    beq !t33_fail+              // I=0 means cli was called — FAIL
    lda #$01
    sta tc_results + 32
    jmp !t33_done+
!t33_fail:
    lda #$00
    sta tc_results + 32
!t33_done:
    cli                         // Restore normal interrupt state

    // ============================================================
    // Test 34: verify_connectivity preserves I flag (sei context, disconnected)
    // Same check on the failure/carry-set path (unreachable room).
    // ============================================================
    jsr fill_map_rock
    lda #2
    sta room_count
    // Room 0 at (10,10,5,3)
    lda #10
    sta dg_room_x
    sta dg_room_y
    sta room_x
    sta room_y
    lda #5
    sta dg_room_w
    sta room_w
    lda #3
    sta dg_room_h
    sta room_h
    jsr draw_dungeon_room
    // Room 1 at (50,30,5,3) — isolated (no corridor)
    lda #50
    sta dg_room_x
    sta room_x + 1
    lda #30
    sta dg_room_y
    sta room_y + 1
    lda #5
    sta dg_room_w
    sta room_w + 1
    lda #3
    sta dg_room_h
    sta room_h + 1
    jsr draw_dungeon_room
    lda #12
    sta stairs_up_x
    lda #11
    sta stairs_up_y
    // Call with sei; carry set expected (unreachable); I flag must stay set
    sei
    jsr verify_connectivity     // Disconnected → carry set; I flag must stay set
    php
    pla
    and #$04
    beq !t34_fail+
    lda #$01
    sta tc_results + 33
    jmp !t34_done+
!t34_fail:
    lda #$00
    sta tc_results + 33
!t34_done:
    cli

    // ============================================================
    // Test 35: verify_connectivity preserves I=0 in normal (cli) context
    // Ensures php/plp doesn't accidentally leave IRQs disabled after a
    // call made without sei.  Layout: connected (success path).
    // ============================================================
    jsr fill_map_rock
    lda #2
    sta room_count
    // Room 0 at (10,10,5,3)
    lda #10
    sta dg_room_x
    sta dg_room_y
    sta room_x
    sta room_y
    lda #5
    sta dg_room_w
    sta room_w
    lda #3
    sta dg_room_h
    sta room_h
    jsr draw_dungeon_room
    // Room 1 at (30,10,5,3)
    lda #30
    sta dg_room_x
    sta room_x + 1
    lda #10
    sta dg_room_y
    sta room_y + 1
    lda #5
    sta dg_room_w
    sta room_w + 1
    lda #3
    sta dg_room_h
    sta room_h + 1
    jsr draw_dungeon_room
    lda #12
    sta dg_cx1
    lda #32
    sta dg_cx2
    lda #11
    sta dg_cy1
    jsr carve_h_corridor
    lda #12
    sta stairs_up_x
    lda #11
    sta stairs_up_y
    // Call without sei (I=0); I flag must still be clear on return
    cli
    jsr verify_connectivity     // Connected → carry clear; I must stay clear
    php
    pla
    and #$04                    // I flag
    bne !t35_fail+              // I=1 means sei leaked — FAIL
    lda #$01
    sta tc_results + 34
    jmp !t35_done+
!t35_fail:
    lda #$00
    sta tc_results + 34
!t35_done:

    // Done — jump to exit trampoline (copies tc_results to $0400, then brk)
    jmp test_exit_trampoline
