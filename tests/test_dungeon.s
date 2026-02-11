// test_dungeon.s — Runtime tests for dungeon_gen.s
//
// Tests: fill_map_rock, draw_dungeon_room, check_room_overlap,
//        corridor carving, shuffle_rooms, verify_connectivity,
//        and full dungeon_generate integration.
//
// Results at $0400: $01 = pass, $00 = fail per test

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
#import "../dungeon_render.s"
#import "../dungeon_los.s"
#import "../player_move.s"
#import "../turn.s"

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
t24_carry_result: .byte 0
t24_result_save:  .fill 28, 0   // Buffer to save $0400-$041b from msg_print clobbering

test_start:
    // Bank out BASIC ROM (needed for $A000 area used by BFS)
    :BankOutBasic()

    // Initialize result area to $ff (untested)
    ldx #31
    lda #$ff
!clr:
    sta $0400,x
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
    sta $0400
    jmp !t1_done+
!t1_fail:
    lda #$00
    sta $0400
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
    sta $0401
    jmp !t2_done+
!t2_fail:
    lda #$00
    sta $0401
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
    sta $0402
    jmp !t3_done+
!t3_fail:
    lda #$00
    sta $0402
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
    sta $0403
    jmp !t4_done+
!t4_fail:
    lda #$00
    sta $0403
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
    sta $0404
    jmp !t5_done+
!t5_fail:
    lda #$00
    sta $0404
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
    sta $0405
    jmp !t6_done+
!t6_fail:
    lda #$00
    sta $0405
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
    sta $0406
    jmp !t7_done+
!t7_fail:
    lda #$00
    sta $0406
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
    sta $0407
    jmp !t8_done+
!t8_fail:
    lda #$00
    sta $0407
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
    sta $0408
    jmp !t9_done+
!t9_fail:
    lda #$00
    sta $0408
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
    sta $0409
    jmp !t10_done+
!t10_fail:
    lda #$00
    sta $0409
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
    sta $040a
    jmp !t11_done+
!t11_fail:
    lda #$00
    sta $040a
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
    sta $040b
    jmp !t12_done+
!t12_fail:
    lda #$00
    sta $040b
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
    sta $040c
    jmp !t13_done+
!t13_fail:
    lda #$00
    sta $040c
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
    sta $040d
    jmp !t14_done+
!t14_fail:
    lda #$00
    sta $040d
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
    sta $040e
    jmp !t15_done+
!t15_fail:
    lda #$00
    sta $040e
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
    sta $040f
    jmp !t16_done+
!t16_fail:
    lda #$00
    sta $040f
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
    sta $0410
    jmp !t17_done+
!t17_fail:
    lda #$00
    sta $0410
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
    sta $0411
    jmp !t18_done+
!t18_fail:
    lda #$00
    sta $0411
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
    sta $0412
    jmp !t19_done+
!t19_fail:
    lda #$00
    sta $0412
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
    sta $0413
    jmp !t20_done+
!t20_fail:
    lda #$00
    sta $0413
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
    sta $0414
    jmp !t21_done+
!t21_fail:
    lda #$00
    sta $0414
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
    sta $0415
    jmp !t22_done+
!t22_fail:
    lda #$00
    sta $0415
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
    sta $0416
    jmp !t23_done+
!t23_fail:
    lda #$00
    sta $0416
!t23_done:

    // ==========================================
    // Test 24: trap_check_at_player sets carry on trap
    // Place a trap at player position, verify carry is set.
    // NOTE: trap_check_at_player calls msg_print which writes to $0400
    // (screen row 0), so we save/restore existing test results.
    // ==========================================

    // Save test results 1-23 from screen row 0 before trap clobbers them
    ldx #27
!t24_save:
    lda $0400,x
    sta t24_result_save,x
    dex
    bpl !t24_save-

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

    // Restore test results 1-23
    ldx #27
!t24_restore:
    lda t24_result_save,x
    sta $0400,x
    dex
    bpl !t24_restore-

    // Now write test 24 result
    lda t24_carry_result
    sta $0417

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
    sta $0418
    jmp !t25_done+
!t25_fail:
    lda #$00
    sta $0418
!t25_done:

    // ==========================================
    // Test 26: place_secrets creates TILE_SECRET tiles
    // Generate a dungeon, then count secret tiles on the map.
    // (place_secrets is called by dungeon_generate now)
    // ==========================================

    // Save test results again — dungeon_generate may call msg-related code
    ldx #27
!t26_save:
    lda $0400,x
    sta t24_result_save,x
    dex
    bpl !t26_save-

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
    sta t19_tile                // Reuse as test 26 result
    jmp !t26_write+
!t26_fail:
    lda #$00
    sta t19_tile
!t26_write:
    // Restore test results, then write 26
    ldx #27
!t26_restore:
    lda t24_result_save,x
    sta $0400,x
    dex
    bpl !t26_restore-
    lda t19_tile
    sta $0419

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
    sta $041a
    jmp !t27_done+
!t27_fail:
    lda #$00
    sta $041a
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
    sta $041b
    jmp !t28_done+
!t28_fail:
    lda #$00
    sta $041b
!t28_done:

    // Done — break into monitor
    brk
