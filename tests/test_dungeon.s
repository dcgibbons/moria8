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
    // Scan map for at least one magma ($C0) and one quartz ($D0)
    // ==========================================
    lda #0
    sta t14_magma
    sta t14_quartz

    ldx #0
!t14_scan:
    lda MAP_BASE,x
    and #TILE_TYPE_MASK
    cmp #TILE_MAGMA
    bne !t14_not_m+
    inc t14_magma
!t14_not_m:
    cmp #TILE_QUARTZ
    bne !t14_not_q+
    inc t14_quartz
!t14_not_q:
    inx
    bne !t14_scan-

    // Scan pages 1-14 (we already scanned page 0)
    // Just check a subset for efficiency — scan page $C4 and $C8
    ldx #0
!t14_scan2:
    lda MAP_BASE + $400,x
    and #TILE_TYPE_MASK
    cmp #TILE_MAGMA
    bne !t14_not_m2+
    inc t14_magma
!t14_not_m2:
    cmp #TILE_QUARTZ
    bne !t14_not_q2+
    inc t14_quartz
!t14_not_q2:
    lda MAP_BASE + $800,x
    and #TILE_TYPE_MASK
    cmp #TILE_MAGMA
    bne !t14_not_m3+
    inc t14_magma
!t14_not_m3:
    cmp #TILE_QUARTZ
    bne !t14_not_q3+
    inc t14_quartz
!t14_not_q3:
    inx
    bne !t14_scan2-

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

    // Done — break into monitor
    brk
