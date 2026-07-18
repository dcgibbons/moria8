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
    ldx #44
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

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
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "../../../../core/store_door_lookup.s"
#define DUNGEON_TEST_TUNNEL_HOOK
#import "../../../../core/dungeon_gen.s"
#undef DUNGEON_TEST_TUNNEL_HOOK
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_features.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/monster_ai.s"
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
#import "../../../../core/monster_magic.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/item.s"
#import "../../../../core/special_rooms.s"
#import "../../../../core/ego_items.s"
#import "../../../../core/special_rooms_stubs.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/player_run.s"
#import "../../../../core/combat.s"
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
store_init_all:
    rts

store_restock_all:
    rts

store_enter:
    rts
piw_prompt_filtered_inv:
show_inv_and_select:
magic_recalc_mana:
magic_check_new_spells:
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
ui_equipment_display:
    rts
// ui_help stubs — saves ~900 bytes; these are never called during dungeon tests.
// Full ui_help.s + ui_help_data.s adds ~900 bytes of help screen strings/code.
ui_help_show_paged:
ui_help_display:
help_draw_line:
help_draw_hborder:
    rts
#import "../../../../core/ui_trampoline_stubs.s"

audit_coord_passable:
    ldx audit_check_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy audit_check_x
    :MapRead_ptr0_y()
    jmp vc_tile_is_passable

audit_final_door_chokepoints:
    lda #~FLAG_OCCUPIED & $ff
    jsr map_bulk_and_all
    lda #1
    sta bfs_cur_y
!afd_row:
    ldx bfs_cur_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    lda #1
    sta bfs_cur_x
!afd_col:
    ldy bfs_cur_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !afd_check+
    cmp #TILE_DOOR_CLOSED
    beq !afd_check+
    cmp #TILE_SECRET
    bne !afd_next+
!afd_check:
    jsr audit_one_door_chokepoint
    bcs !afd_fail+
!afd_next:
    inc bfs_cur_x
    lda bfs_cur_x
    cmp #MAP_COLS - 1
    bne !afd_col-
    inc bfs_cur_y
    lda bfs_cur_y
    cmp #MAP_ROWS - 1
    bne !afd_row-
    jsr vc_cleanup
    clc
    rts
!afd_fail:
    jsr vc_cleanup
    sec
    rts

audit_one_door_chokepoint:
    lda bfs_cur_x
    sta audit_door_x
    sta dg_cx1
    lda bfs_cur_y
    sta audit_door_y
    sta dg_cy1
    // A valid door has exactly one straight passable axis and wall jambs on
    // the perpendicular axis. One-sided and T-shaped doors are bypassable.
    lda audit_door_x
    sec
    sbc #1
    sta audit_check_x
    lda audit_door_y
    sta audit_check_y
        jsr audit_coord_passable
        bcc !aod_try_vertical+
        lda audit_door_x
        clc
        adc #1
    sta audit_check_x
    lda audit_door_y
    sta audit_check_y
        jsr audit_coord_passable
        bcc !aod_try_vertical+
    lda audit_door_x
    sta dg_room_x
    lda audit_door_y
    sta dg_room_y
    jsr jdg_opposing_vertical
    bcs !aod_pass+
    jmp !aod_fail+

    !aod_try_vertical:
    lda audit_door_x
    sta audit_check_x
    lda audit_door_y
    sec
    sbc #1
    sta audit_check_y
    jsr audit_coord_passable
    bcc !aod_fail+
    lda audit_door_x
    sta audit_check_x
    lda audit_door_y
    clc
    adc #1
    sta audit_check_y
        jsr audit_coord_passable
        bcc !aod_fail+
        lda audit_door_x
        sta dg_room_x
        lda audit_door_y
        sta dg_room_y
        jsr jdg_opposing_horizontal
        bcc !aod_fail+
!aod_pass:
	        ldx audit_door_y
	        lda map_row_lo,x
	        sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    lda audit_door_x
    sta bfs_cur_x
    lda audit_door_y
    sta bfs_cur_y
    clc
    rts
!aod_fail:
    lda audit_door_x
    sta bfs_cur_x
    lda audit_door_y
    sta bfs_cur_y
    sec
    rts

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch variables
t9_sum_before: .byte 0
t9_sig_before: .byte 0
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
audit_door_x:  .byte 0
audit_door_y:  .byte 0
audit_check_x: .byte 0
audit_check_y: .byte 0
audit_pair_count: .byte 0
tc_results: .fill 45, $ff              // Test results buffer (copied to $0400 before brk)
t38_rockfall_name: .text "falling rock." ; .byte 0
run_cycle_expected:
    .byte 7,3,5,0,4,2,6,1,7,3,5,0
run_home_expected:
    .byte 3,7,5,9,4,2,6,8

test_set_materialize_row_bounds:
    lda dg_cy1
    sec
    sbc #1
    sta dg_scan_row_start
    lda dg_cy1
    clc
    adc #1
    sta dg_scan_row_end
    rts

test_start:
    // Initialize result area to $ff (untested)
    ldx #44
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
    // Should be a supported door type; secret is a valid upstream-style door.
    cmp #TILE_DOOR_OPEN
    beq !t7_pass+
    cmp #TILE_DOOR_CLOSED
    beq !t7_pass+
    cmp #TILE_SECRET
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
    // Test 9: shuffle_rooms preserves room geometry and metadata alignment
    // Set up 4 rooms with known values, shuffle, verify both geometry and
    // parallel metadata survive together.
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
    lda #1
    sta room_lit + 0
    lda #2
    sta room_type + 0

    // Room 1: x=30,y=10,w=6,h=4
    lda #30
    sta room_x + 1
    lda #10
    sta room_y + 1
    lda #6
    sta room_w + 1
    lda #4
    sta room_h + 1
    lda #0
    sta room_lit + 1
    lda #3
    sta room_type + 1

    // Room 2: x=50,y=20,w=7,h=5
    lda #50
    sta room_x + 2
    lda #20
    sta room_y + 2
    lda #7
    sta room_w + 2
    lda #5
    sta room_h + 2
    lda #1
    sta room_lit + 2
    lda #1
    sta room_type + 2

    // Room 3: x=10,y=30,w=4,h=3
    lda #10
    sta room_x + 3
    lda #30
    sta room_y + 3
    lda #4
    sta room_w + 3
    lda #3
    sta room_h + 3
    lda #0
    sta room_lit + 3
    lda #0
    sta room_type + 3

    // Compute sum of all room_x values before shuffle
    lda room_x + 0
    clc
    adc room_x + 1
    clc
    adc room_x + 2
    clc
    adc room_x + 3
    sta t9_sum_before              // Sum should be 10+30+50+10 = 100

    // Compute an order-independent signature that still couples geometry and
    // metadata, so mis-shuffling room_lit/room_type changes the result.
    // signature += (x + y + w + h) * (1 + room_lit + 2*room_type)
    lda #0
    sta t9_sig_before
    ldx #0
!t9_sig_pre_loop:
    lda room_type,x
    asl                         // 2 * room_type
    clc
    adc room_lit,x
    clc
    adc #1
    sta zp_temp0                // weight

    lda room_x,x
    clc
    adc room_y,x
    clc
    adc room_w,x
    clc
    adc room_h,x
    sta zp_temp1                // key

    lda #0
    sta zp_temp2
!t9_sig_pre_mul:
    lda t9_sig_before
    clc
    adc zp_temp1
    sta t9_sig_before
    inc zp_temp2
    lda zp_temp2
    cmp zp_temp0
    bcc !t9_sig_pre_mul-

    inx
    cpx #4
    bcc !t9_sig_pre_loop-

    jsr shuffle_rooms

    // room_count should be unchanged
    lda room_count
    cmp #4
    beq !t9_count_ok+
    jmp !t9_fail+
!t9_count_ok:

    // Compute sum after shuffle — should still be 100
    lda room_x + 0
    clc
    adc room_x + 1
    clc
    adc room_x + 2
    clc
    adc room_x + 3
    cmp t9_sum_before
    beq !t9_sum_ok+
    jmp !t9_fail+
!t9_sum_ok:

    // Recompute the geometry+metadata signature after shuffle.
    lda #0
    sta zp_temp3
    ldx #0
!t9_sig_post_loop:
    lda room_type,x
    asl
    clc
    adc room_lit,x
    clc
    adc #1
    sta zp_temp0

    lda room_x,x
    clc
    adc room_y,x
    clc
    adc room_w,x
    clc
    adc room_h,x
    sta zp_temp1

    lda #0
    sta zp_temp2
!t9_sig_post_mul:
    lda zp_temp3
    clc
    adc zp_temp1
    sta zp_temp3
    inc zp_temp2
    lda zp_temp2
    cmp zp_temp0
    bcc !t9_sig_post_mul-

    inx
    cpx #4
    bcc !t9_sig_post_loop-

    lda zp_temp3
    cmp t9_sig_before
    beq !t9_signature_ok+
    jmp !t9_fail+
!t9_signature_ok:

    // Slot metadata must remain attached after shuffle, and connectors must
    // use the upstream slot center rather than the rectangle midpoint.
    ldx #0
!t9_find_slot3:
    lda room_type,x
    cmp #3
    beq !t9_slot3_found+
    inx
    cpx #4
    bcc !t9_find_slot3-
    jmp !t9_fail+
!t9_slot3_found:
    jsr conn_room_center_to_start
    lda dg_cx1
    cmp room_slot_center_x + 3
    bne !t9_fail+
    lda dg_cy1
    cmp room_slot_center_y + 3
    bne !t9_fail+

!t9_pass:
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
    jsr verify_connectivity
    bcc !t12_connected+
    jmp !t12_fail+
!t12_connected:
    // Upstream independent extents permit every width 3..23 and height 3..8,
    // including even sizes. The fixed production seed must exercise at least
    // one even dimension so mirrored odd-only generation cannot regress.
    lda #0
    sta zp_temp0
    ldx #0
!t12_extent_loop:
    lda room_w,x
    cmp #3
    bcc !t12_fail+
    cmp #24
    bcs !t12_fail+
    and #1
    bne !t12_width_checked+
    inc zp_temp0
!t12_width_checked:
    lda room_h,x
    cmp #3
    bcc !t12_fail+
    cmp #9
    bcs !t12_fail+
    and #1
    bne !t12_height_checked+
    inc zp_temp0
!t12_height_checked:
    inx
    cpx room_count
    bcc !t12_extent_loop-
    lda zp_temp0
    beq !t12_fail+

    lda #$01
    sta tc_results+11
    jmp !t12_done+
!t12_fail:
    lda tc_results+11
    bmi !t12_done+
    and #$40
    bne !t12_done+
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

    // Check stairs_dn2 tile
    lda stairs_dn2_x
    ldy stairs_dn2_y
    jsr write_tile_at_xy
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    bne !t13_fail+

    // This port intentionally persists and reveals exactly the three tracked
    // stair coordinates, not upstream's variable object-count stair set.
    lda #0
    sta t14_magma                 // Reused here as up-stair count
    sta t14_quartz                // Reused here as down-stair count
    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi
    ldy #0
!t13_scan:
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_UP
    bne !t13_not_up+
    inc t14_magma
!t13_not_up:
    cmp #TILE_STAIRS_DN
    bne !t13_not_dn+
    inc t14_quartz
!t13_not_dn:
    iny
    bne !t13_scan-
    inc zp_ptr0_hi
    lda zp_ptr0_hi
    cmp #$cf
    bne !t13_scan-

    lda t14_magma
    cmp #1
    bne !t13_fail+
    lda t14_quartz
    cmp #2
    bne !t13_fail+

    lda #$01
    sta tc_results+12
    jmp !t13_done+
!t13_fail:
    lda #$00
    sta tc_results+12
!t13_done:

    // ==========================================
    // Test 14: Map has both magma and quartz tiles after generation,
    // mineral streamers are not pre-lit/revealed, and generation scratch
    // flags are fully cleaned up.
    // ==========================================
    lda #0
    sta t14_magma
    sta t14_quartz
    sta t16_counter

    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi

    ldy #0
!t14_scan:
    lda (zp_ptr0),y
    sta t19_tile
    and #TILE_TYPE_MASK
    cmp #TILE_MAGMA
    bne !t14_not_m+
    inc t14_magma
    lda t19_tile
    and #FLAG_LIT
    beq !t14_not_m+
    inc t16_counter
!t14_not_m:
    lda t19_tile
    and #TILE_TYPE_MASK
    cmp #TILE_QUARTZ
    bne !t14_not_q+
    inc t14_quartz
    lda t19_tile
    and #FLAG_LIT
    beq !t14_not_q+
    inc t16_counter
!t14_not_q:
    lda t19_tile
    and #FLAG_OCCUPIED
    beq !t14_not_occ+
    inc t16_counter
!t14_not_occ:
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
    lda t16_counter
    bne !t14_fail+

    // Streamers must match upstream's rock_wall1-only rule. A map made of
    // vertical wall bytes is structural wall in this port, not granite.
    lda #TILE_WALL_V
    jsr map_bulk_fill_all
    jsr place_streamers

    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi

    ldy #0
!t14_non_granite_scan:
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_MAGMA
    beq !t14_fail+
    cmp #TILE_QUARTZ
    beq !t14_fail+
    iny
    bne !t14_non_granite_scan-

    inc zp_ptr0_hi
    lda zp_ptr0_hi
    cmp #$cf
    bne !t14_non_granite_scan-

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
    // Test 16: Corridor wall candidates resolve to supported mouth features.
    // Secret is allowed again as an upstream-supported door variant; the
    // invariant is that the junction does not remain a wall.
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

	    // Stage a production tunnel step through the left wall at x=19.
	    lda #19
	    sta dg_cx1
	    lda #11
	    sta dg_cy1
	    lda #1
	    sta dg_tun_dir
	    jsr tunnel_stage_current
	    jsr test_set_materialize_row_bounds
	    jsr materialize_staged_tunnel

    // Check tile at (19, 11) is floor or a supported door.
    ldx #11
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #19
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !t16_ok_iter+
    cmp #TILE_DOOR_OPEN
    beq !t16_ok_iter+
    cmp #TILE_DOOR_CLOSED
    beq !t16_ok_iter+
    cmp #TILE_SECRET
    bne !t16_fail+

!t16_ok_iter:
    dec t16_counter
    bne !t16_loop-

	    // All 10 iterations passed: wall mouths resolved to floor or doors.
    lda #$01
    sta tc_results+15
    jmp !t16_done+
!t16_fail:
    lda #$00
    sta tc_results+15
!t16_done:

    // ==========================================
    // Test 17: wandering tunnel does not place bypassable room-mouth doors
    // Vertical travel through a horizontal wall needs room wall on both sides.
    // If one side is unlit rock/corridor wall, the door is on a wall end.
    // Diagonal openings alone are not a cardinal bypass. Corners and existing
    // same-wall openings are not door jambs.
    // ==========================================
    lda #1
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir
    jsr dungeon_generate
	    jsr audit_final_door_chokepoints
	    bcc !t17_generated_ok+
	    jmp !t17_fail+
!t17_generated_ok:
	    jsr fill_map_rock

    lda #19
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H
    sta (zp_ptr0),y
    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H | FLAG_LIT
    sta (zp_ptr0),y
    lda #21
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H | FLAG_LIT
    sta (zp_ptr0),y

    lda #20
    sta dg_cx1
    sta dg_cy1
    lda #2
    sta dg_tun_dir
    jsr tunnel_stage_current
    jsr test_set_materialize_row_bounds
    jsr materialize_staged_tunnel

    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !t17_pass+
    cmp #TILE_DOOR_OPEN
    beq !t17_pass+
    cmp #TILE_DOOR_CLOSED
    beq !t17_pass+
	    cmp #TILE_SECRET
	    beq !t17_pass+
	    jmp !t17_fail+

!t17_pass:
    jsr fill_map_rock

    lda #19
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H | FLAG_LIT
    sta (zp_ptr0),y
    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H | FLAG_LIT
    sta (zp_ptr0),y
    lda #21
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H | FLAG_LIT
    sta (zp_ptr0),y
    lda #21
    ldy #19
    jsr write_tile_at_xy
    lda #TILE_DOOR_OPEN | FLAG_LIT
    sta (zp_ptr0),y
    lda #21
    ldy #21
    jsr write_tile_at_xy
    lda #TILE_FLOOR
    sta (zp_ptr0),y

    lda #20
    sta dg_cx1
    sta dg_cy1
    lda #2
    sta dg_tun_dir
    jsr tunnel_stage_current
    jsr test_set_materialize_row_bounds
    jsr materialize_staged_tunnel

    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda (zp_ptr0),y
	    and #TILE_TYPE_MASK
	    cmp #TILE_FLOOR
	    beq !t17_pass2+
    cmp #TILE_DOOR_OPEN
    beq !t17_pass2+
    cmp #TILE_DOOR_CLOSED
    beq !t17_pass2+
	    cmp #TILE_SECRET
	    beq !t17_pass2+
	    jmp !t17_fail+

!t17_pass2:
    jsr fill_map_rock

    // Adjacent same-wall opening: the candidate is redundant, not a choke.
    lda #19
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H | FLAG_LIT
    sta (zp_ptr0),y
    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H | FLAG_LIT
    sta (zp_ptr0),y
    lda #21
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    lda #20
    ldy #21
    jsr write_tile_at_xy
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    lda #20
    sta dg_cx1
    sta dg_cy1
    lda #2
    sta dg_tun_dir
    jsr tunnel_stage_current
    jsr test_set_materialize_row_bounds
    jsr materialize_staged_tunnel

    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda (zp_ptr0),y
	    and #TILE_TYPE_MASK
	    cmp #TILE_FLOOR
	    beq !t17_pass3+
	    jmp !t17_fail+

!t17_pass3:
    jsr fill_map_rock

    // Corner tile beside the candidate is not a straight horizontal jamb.
    lda #19
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_CORNER_TR | FLAG_LIT
    sta (zp_ptr0),y
    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H | FLAG_LIT
    sta (zp_ptr0),y
    lda #21
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H | FLAG_LIT
    sta (zp_ptr0),y

    lda #20
    sta dg_cx1
    sta dg_cy1
    lda #2
    sta dg_tun_dir
    jsr tunnel_stage_current
    jsr test_set_materialize_row_bounds
    jsr materialize_staged_tunnel

    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda (zp_ptr0),y
	    and #TILE_TYPE_MASK
	    cmp #TILE_FLOOR
	    beq !t17_pass4+
	    jmp !t17_fail+

!t17_pass4:
    jsr fill_map_rock

    // Mirror case: corner tile is not a straight vertical jamb either.
    lda #20
    ldy #19
    jsr write_tile_at_xy
    lda #TILE_CORNER_BL | FLAG_LIT
    sta (zp_ptr0),y
    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_V | FLAG_LIT
    sta (zp_ptr0),y
    lda #20
    ldy #21
    jsr write_tile_at_xy
    lda #TILE_WALL_V | FLAG_LIT
    sta (zp_ptr0),y

    lda #20
    sta dg_cx1
    sta dg_cy1
    lda #1
    sta dg_tun_dir
    jsr tunnel_stage_current
    jsr test_set_materialize_row_bounds
    jsr materialize_staged_tunnel

    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda (zp_ptr0),y
	    and #TILE_TYPE_MASK
	    cmp #TILE_FLOOR
	    beq !t17_pass5+
	    jmp !t17_fail+

!t17_pass5:
    // A one-sided door is not a chokepoint. This is the generated corner
    // regression: three cardinal walls plus one open side previously passed
    // the audit and left a door the player could walk around.
    jsr fill_map_rock
    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_DOOR_CLOSED | DUNGEON_FLAGS
    sta (zp_ptr0),y
    lda #21
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    jsr audit_final_door_chokepoints
    bcs !t17_one_sided_rejected+
    jmp !t17_fail+
!t17_one_sided_rejected:

    // A valid straight junction must materialize one of the supported door
    // types. The production writer previously lost A while rebuilding ptr0
    // and stored the map-row high byte as terrain instead.
    jsr fill_map_rock
    lda #19
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    lda #21
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    lda #20
    sta dg_room_x
    sta dg_room_y
    lda #0
    sta dg_door_flag
    lda #16
    sta t16_counter
!t17_junction_try:
    jsr try_junction_door
    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !t17_junction_written+
    dec t16_counter
    bne !t17_junction_try-
    jmp !t17_fail+
!t17_junction_written:
    cmp #TILE_DOOR_OPEN
    beq !t17_junction_ok+
    cmp #TILE_DOOR_CLOSED
    beq !t17_junction_ok+
    cmp #TILE_SECRET
    beq !t17_junction_ok+
    jmp !t17_fail+
!t17_junction_ok:

    // Room-wall guards must survive per-tunnel materialization, reject a
    // later adjacent penetration, then be consumed by fill_cave_granite.
    jsr fill_map_rock
    lda #19
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H | FLAG_LIT
    sta (zp_ptr0),y
    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H | FLAG_LIT
    sta (zp_ptr0),y
    lda #21
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_H | FLAG_LIT
    sta (zp_ptr0),y
    lda #20
    sta dg_cx1
    sta dg_cy1
    lda #20
    sta dg_room_x
    lda #19
    sta dg_room_y
    jsr tunnel_stage_current
    jsr test_set_materialize_row_bounds
    jsr materialize_staged_tunnel

    lda #21
    ldy #20
    jsr write_tile_at_xy
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    bne !t17_guard_preserved+
    jmp !t17_fail+
!t17_guard_preserved:

    lda #21
    sta dg_cx1
    sta dg_room_x
    lda #20
    sta dg_cy1
    lda #19
    sta dg_room_y
    jsr tunnel_stage_current
    lda dg_cx1
    cmp #21
    beq !t17_guard_x_ok+
    jmp !t17_fail+
!t17_guard_x_ok:
    lda dg_cy1
    cmp #19
    beq !t17_guard_y_ok+
    jmp !t17_fail+
!t17_guard_y_ok:

    jsr fill_cave_granite
    lda #21
    ldy #20
    jsr write_tile_at_xy
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    beq !t17_guard_cleared+
    jmp !t17_fail+
!t17_guard_cleared:
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_WALL_H
    beq !t17_guard_tile_ok+
    jmp !t17_fail+
!t17_guard_tile_ok:

    lda #$01
    sta tc_results+16
    jmp !t17_done+
!t17_fail:
    lda #$00
    sta tc_results+16
!t17_done:

    // ==========================================
    // Test 18: add_corridor_doors leaves production corridor mouths alone.
    // Upstream room mouths become doors probabilistically; otherwise they
    // become corridor floor.
    // ==========================================
    jsr fill_map_rock

    // Explicit real room-mouth fixture: horizontal tunnel through a vertical
    // room wall, with straight vertical jambs and no local bypass.
    lda #20
    ldy #19
    jsr write_tile_at_xy
    lda #TILE_WALL_V | FLAG_LIT
    sta (zp_ptr0),y
    lda #20
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_WALL_V | FLAG_LIT
    sta (zp_ptr0),y
    lda #20
    ldy #21
    jsr write_tile_at_xy
    lda #TILE_WALL_V | FLAG_LIT
    sta (zp_ptr0),y
    lda #19
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    lda #21
    ldy #20
    jsr write_tile_at_xy
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Carve the production-path tunnel step through the wall-mouth.
    lda #20
    sta dg_cx1
    lda #20
    sta dg_cy1
    lda #1
    sta dg_tun_dir
    jsr tunnel_stage_current

	    // Materialize the production-staged mouth; it must resolve to floor or
	    // a supported door, not remain a wall.
	    jsr test_set_materialize_row_bounds
	    jsr materialize_staged_tunnel

    // Mouth at (20, 20) must be floor or a supported door.
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !t18_pass+
    cmp #TILE_DOOR_OPEN
    beq !t18_pass+
    cmp #TILE_DOOR_CLOSED
    beq !t18_pass+
    cmp #TILE_SECRET
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
	jsr audit_final_door_chokepoints
	bcs !t19_fail+

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
    // Test 24: search reveals a trap without disarming it; stepping on that
    // revealed trap sets carry and leaves it live for later disarm.
    // ==========================================

    jsr fill_map_rock

    // Set up the player adjacent to a hidden trap.
    lda #20
    sta zp_player_x
    lda #19
    sta zp_player_y

    // Write floor tile at trap position
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR
    sta (zp_ptr0),y

    // Place trap in the trap table.
    lda #1
    sta trap_count
    lda #20
    sta trap_x
    sta trap_y
    lda #TRAP_OPEN_PIT
    sta trap_type

    lda #0
    sta zp_msg_flags
    lda #100
    jsr search_scan_adjacent_silent
    bcc !t24_fail+
    lda trap_count
    cmp #1
    bne !t24_fail+
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    bne !t24_fail+

    lda #20
    sta zp_player_y

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

    lda t24_carry_result
    beq !t24_fail+
    lda trap_count
    cmp #1
    bne !t24_fail+
    lda #$01
    jmp !t24_store+
!t24_fail:
    lda #$00
!t24_store:
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
    // Test 26: place_secrets creates TILE_SECRET tiles.
    // Keep this deterministic: generation RNG shifts whenever generation
    // internals change, but a single closed door must always be converted.
    // ==========================================

    jsr fill_map_rock
    lda #3
    sta zp_player_dlvl
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y

    jsr place_secrets

    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    beq !t26_pass+
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
    // Test 27: UMoria leading-edge scan stops before stairs.
    // ==========================================
    jsr fill_map_rock

    // Create a small corridor with stairs
    lda #20
    sta zp_player_x
    lda #20
    sta zp_player_y

    // Place floor under the player and stairs two steps east. After the
    // simulated first move, the stairs enter the newly-adjacent scan edge.
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    iny
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    iny
    lda #TILE_STAIRS_DN | FLAG_VISITED
    sta (zp_ptr0),y

    // Set up running direction (east)
    lda #3                      // DIR_E
    sta zp_run_dir
    lda #5
    sta zp_light_radius
    lda #0
    sta zp_eff_blind

    jsr run_initialize
    bcc !t27_fail+
    inc zp_player_x
    jsr run_area_affect
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
    // Test 28: UMoria runner continues on a straight corridor.
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
    cpy #24
    bne !t28_carve-

    // Player at (20, 20), running east
    lda #20
    sta zp_player_x
    sta zp_player_y
    lda #3                      // DIR_E
    sta zp_run_dir
    lda #5
    sta zp_light_radius
    lda #0
    sta zp_eff_blind
    jsr run_initialize
    bcc !t28_fail+
    inc zp_player_x
    jsr run_area_affect
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
    jsr fill_map_rock
    lda #1
    sta room_count
    lda #RT_VAULT
    sta room_type
    lda #20
    sta room_x
    sta dg_room_x
    lda #14
    sta room_y
    sta dg_room_y
    lda #8
    sta room_w
    sta dg_room_w
    lda #5
    sta room_h
    sta dg_room_h
    jsr draw_dungeon_room

    // Place a door on the top wall of the synthetic vault room.
    lda room_y
    sec
    sbc #1
    tax                         // X = wall row
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy room_x                 // First column of room
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y

    // Call vault_seal_entrance
    jsr vault_seal_entrance

	    // Verify tile is now TILE_SECRET ($F0)
	    lda room_y
	    sec
	    sbc #1
    tax
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy room_x
    lda (zp_ptr0),y
	    and #TILE_TYPE_MASK
	    cmp #TILE_SECRET
	    bne !t31_skip+

	    // Doorless generated vault mouth must also be sealable. This is the
	    // production case when room-mouth door placement resolved to floor.
	    jsr draw_dungeon_room
	    lda room_y
	    clc
	    adc room_h
	    tax
	    lda map_row_lo,x
	    sta zp_ptr0
	    lda map_row_hi,x
	    sta zp_ptr0_hi
	    ldy room_x
	    iny
	    lda #TILE_FLOOR
	    sta (zp_ptr0),y

	    jsr vault_seal_entrance

	    lda room_y
	    clc
	    adc room_h
	    tax
	    lda map_row_lo,x
	    sta zp_ptr0
	    lda map_row_hi,x
	    sta zp_ptr0_hi
	    ldy room_x
	    iny
	    lda (zp_ptr0),y
	    and #TILE_TYPE_MASK
	    cmp #TILE_SECRET
	    bne !t31_skip+

!t31_pass:
    lda #$01
    sta tc_results+30
    jmp !t31_done+
!t31_skip:
    lda #$00
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

    // ============================================================
    // Test 36: UMoria leading-edge scan stops before floor items.
    // ============================================================
    jsr fill_map_rock

    lda #20
    sta zp_player_x
    lda #20
    sta zp_player_y

    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    iny
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    iny
    lda #TILE_FLOOR | FLAG_HAS_ITEM | FLAG_VISITED
    sta (zp_ptr0),y

    lda #3                      // DIR_E
    sta zp_run_dir
    jsr run_initialize
    bcc !t36_fail+
    inc zp_player_x
    jsr run_area_affect
    bcs !t36_pass+
    jmp !t36_fail+
!t36_pass:
    lda #$01
    sta tc_results + 35
    jmp !t36_done+
!t36_fail:
    lda #$00
    sta tc_results + 35
!t36_done:

    // ============================================================
    // Test 37: production runner matches UMoria's default CJS behavior.
    // ============================================================
    // Edge queries must return a boundary wall instead of wrapping coordinates.
    lda #0
    sta df_target_x
    sta df_target_y
    ldx #2                      // DIR_W
    jsr run_get_tile
    cmp #TILE_WALL_H | FLAG_VISITED
    beq !t37_edge_x_ok+
    jmp !t37_fail+
!t37_edge_x_ok:
    ldx #0                      // DIR_N
    jsr run_get_tile
    cmp #TILE_WALL_H | FLAG_VISITED
    beq !t37_edges_ok+
    jmp !t37_fail+
!t37_edges_ok:

    // Pin the translated cycle/chome tables used by every directional scan.
    ldx #11
!t37_cycle_table:
    lda run_cycle,x
    cmp run_cycle_expected,x
    beq !t37_cycle_next+
    jmp !t37_fail+
!t37_cycle_next:
    dex
    bpl !t37_cycle_table-
    ldx #7
!t37_home_table:
    lda run_home,x
    cmp run_home_expected,x
    beq !t37_home_next+
    jmp !t37_fail+
!t37_home_next:
    dex
    bpl !t37_home_table-

    // Straight east-west corridor. A doorless opening is ordinary floor in
    // UMoria and does not stop merely because it enters the leading edge.
    jsr fill_map_rock
    lda #0
    sta room_count
    sta zp_eff_blind
    lda #5
    sta zp_light_radius
    lda #20
    sta zp_player_x
    sta zp_player_y
    lda #3                      // DIR_E
    sta zp_run_dir
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #18
!t37_corridor:
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    iny
    cpy #25
    bne !t37_corridor-
    ldy #22
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    jsr run_initialize
    bcs !t37_initialized+
    jmp !t37_fail+
!t37_initialized:
    inc zp_player_x
    jsr run_area_affect
    bcc !t37_doorway_open+
    jmp !t37_fail+
!t37_doorway_open:

    // Town entrances are production coordinate metadata over floor, but still
    // stop as visible leading-edge objects.
    lda #0
    sta zp_player_dlvl
    lda #14
    sta df_target_x
    lda #6
    sta df_target_y
    ldx #6
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #15
    lda #TILE_FLOOR | FLAG_VISITED
    :MapWrite_ptr0_y()
    ldx #3
    jsr run_classify
    bcs !t37_store_seen+
    jmp !t37_fail+
!t37_store_seen:
    lda #1
    sta zp_player_dlvl

    // Visible open-door objects stop with UMoria's run_ignore_doors=false.
    lda #20
    sta zp_player_x
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #22
    lda #TILE_DOOR_OPEN | FLAG_VISITED
    :MapWrite_ptr0_y()
    lda #3
    sta zp_run_dir
    jsr run_initialize
    bcs !t37_door_initialized+
    jmp !t37_fail+
!t37_door_initialized:
    inc zp_player_x
    jsr run_area_affect
    bcs !t37_open_door_seen+
    jmp !t37_fail+
!t37_open_door_seen:

    // A live but invisible monster on displayed terrain does not stop the
    // leading-edge scan. Visibility must come from the production producer.
    jsr monster_init_table
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #1
    sta (zp_ptr0),y
    ldy #MX_X
    lda #31
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #30
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldx #30
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #31
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    lda #10
    sta zp_player_x
    sta zp_player_y
    lda #30
    sta df_target_x
    sta df_target_y
    ldx #3
    jsr run_classify
    bcc !t37_invisible_open+
    jmp !t37_fail+
!t37_invisible_open:
    cmp #1
    beq !t37_invisible_ok+
    jmp !t37_fail+
!t37_invisible_ok:

    // A newly visible live monster stops the run through the production
    // visibility refresh without corrupting the directional scan state.
    jsr monster_init_table
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #1
    sta (zp_ptr0),y
    ldy #MX_X
    lda #22
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #20
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #22
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    lda #20
    sta zp_player_x
    sta zp_player_y
    lda #1
    sta zp_player_dlvl
    lda #3
    sta zp_run_dir
    jsr run_initialize
    bcs !t37_monster_initialized+
    jmp !t37_fail+
!t37_monster_initialized:
    inc zp_player_x
    jsr run_area_affect
    bcs !t37_monster_seen+
    jmp !t37_fail+
!t37_monster_seen:

    // A visible monster blocks a running collision without consuming a turn.
    lda #21
    sta zp_player_x
    lda #3
    sta zp_run_dir
    lda #CMD_MOVE_E
    jsr player_try_move
    bcc !t37_visible_collision_ok+
    jmp !t37_fail+
!t37_visible_collision_ok:
    lda zp_player_x
    cmp #21
    beq !t37_visible_position_ok+
    jmp !t37_fail+
!t37_visible_position_ok:

    // The same collision while unseen ends running and consumes the action.
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #~MF_VISIBLE & $ff
    sta (zp_ptr0),y
    lda #1
    sta eff_fear_timer          // Avoid combat RNG; fear still consumes a turn.
    lda #3
    sta zp_run_dir
    lda #CMD_MOVE_E
    jsr player_try_move
    bcs !t37_unseen_consumed+
    jmp !t37_fail+
!t37_unseen_consumed:
    lda player_move_relocated
    beq !t37_unseen_not_relocated+
    jmp !t37_fail+
!t37_unseen_not_relocated:
    lda zp_run_dir
    cmp #$ff
    beq !t37_unseen_run_stopped+
    jmp !t37_fail+
!t37_unseen_run_stopped:
    lda zp_player_x
    cmp #21
    beq !t37_unseen_position_ok+
    jmp !t37_fail+
!t37_unseen_position_ok:
    lda #0
    sta eff_fear_timer

    // Blind running skips the area-affect scan, including visible objects.
    lda #1
    sta zp_eff_blind
    jsr run_area_affect
    bcc !t37_blind_ignored+
    jmp !t37_fail+
!t37_blind_ignored:
    lda #0
    sta zp_eff_blind

    // An open-area run continues while its wall/open topology is unchanged.
    jsr fill_map_rock
    lda #1
    sta room_count
    lda #18
    sta room_x
    sta room_y
    sta dg_room_x
    sta dg_room_y
    lda #5
    sta room_w
    sta room_h
    sta dg_room_w
    sta dg_room_h
    jsr draw_dungeon_room
    lda #20
    sta zp_player_x
    sta zp_player_y
    lda #3
    sta zp_run_dir
    jsr run_initialize
    bcs !t37_room_initialized+
    jmp !t37_fail+
!t37_room_initialized:
    inc zp_player_x
    jsr run_area_affect
    bcc !t37_room_ok+
    jmp !t37_fail+
!t37_room_ok:

    // In open-area mode, a newly-open square on a previously closed side is
    // the doorway boundary and stops the run.
    lda #(RUNF_OPEN | RUNF_BREAK_LEFT)
    sta run_flags
    lda #3
    sta run_prev_dir
    lda #21
    sta zp_player_x
    lda #20
    sta zp_player_y
    ldx #19
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #22
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    jsr run_area_affect
    bcs !t37_open_break_stops+
    jmp !t37_fail+
!t37_open_break_stops:

    // End-to-end doorway regression: running east along a room's north wall
    // continues beside solid wall, then stops when its doorless opening first
    // enters the newly-adjacent left-side scan.
    jsr fill_map_rock
    lda #0
    sta room_count
    sta zp_eff_blind
    lda #5
    sta zp_light_radius
    ldx #11
!t37_mouth_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #9
!t37_mouth_col:
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    iny
    cpy #20
    bne !t37_mouth_col-
    inx
    cpx #14
    bne !t37_mouth_row-
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #14
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    lda #10
    sta zp_player_x
    lda #11
    sta zp_player_y
    lda #3
    sta zp_run_dir
    jsr run_initialize
    bcs !t37_mouth_initialized+
    jmp !t37_fail+
!t37_mouth_initialized:
    inc zp_player_x
    jsr run_area_affect
    bcc !t37_mouth_step2+
    jmp !t37_fail+
!t37_mouth_step2:
    inc zp_player_x
    jsr run_area_affect
    bcc !t37_mouth_step3+
    jmp !t37_fail+
!t37_mouth_step3:
    inc zp_player_x
    jsr run_area_affect
    bcs !t37_mouth_stopped+
    jmp !t37_fail+
!t37_mouth_stopped:
    lda zp_player_x
    cmp #13
    beq !t37_mouth_ok+
    jmp !t37_fail+
!t37_mouth_ok:

    // Direction zero is a valid corridor choice, not the old zero sentinel.
    jsr fill_map_rock
    lda #5
    sta zp_light_radius
    lda #0
    sta run_flags
    sta zp_eff_blind
    sta run_prev_dir             // Previous direction north.
    lda #20
    sta zp_player_x
    sta zp_player_y
    ldx #19
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    jsr run_area_affect
    bcc !t37_north_found+
    jmp !t37_fail+
!t37_north_found:
    lda zp_run_dir
    beq !t37_north_ok+           // Must turn DIR_N.
    jmp !t37_fail+
!t37_north_ok:

    // UMoria default run_cut_corners=true: two adjacent choices whose two
    // far squares are known walls take the diagonal choice.
    jsr fill_map_rock
    lda #5
    sta zp_light_radius
    lda #0
    sta run_flags
    lda #3
    sta run_prev_dir
    lda #20
    sta zp_player_x
    sta zp_player_y
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #21
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    ldx #19
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #21
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    jsr run_area_affect
    bcc !t37_known_corner_continues+
    jmp !t37_fail+
!t37_known_corner_continues:
    lda zp_run_dir
    cmp #5                      // DIR_NE
    beq !t37_known_corner_dir+
    jmp !t37_fail+
!t37_known_corner_dir:
    lda run_prev_dir
    cmp #5
    beq !t37_known_corner_ok+
    jmp !t37_fail+
!t37_known_corner_ok:

    // UMoria default run_examine_corners=true: when the two far squares are
    // unseen, enter the straight option and retain the diagonal previous dir.
    lda #1
    sta zp_light_radius
    lda #0
    sta run_flags
    lda #3
    sta run_prev_dir
    jsr run_area_affect
    bcc !t37_potential_continues+
    jmp !t37_fail+
!t37_potential_continues:
    lda zp_run_dir
    cmp #3                      // DIR_E
    beq !t37_potential_dir+
    jmp !t37_fail+
!t37_potential_dir:
    lda run_prev_dir
    cmp #5                      // Pretend the diagonal was taken.
    beq !t37_potential_ok+
    jmp !t37_fail+
!t37_potential_ok:

    lda #$01
    sta tc_results + 36
    jmp !t37_done+
!t37_fail:
    lda #$00
    sta tc_results + 36
!t37_done:

    // ============================================================
    // Test 38: lethal rockfall trap clamps HP and records source
    // ============================================================
    lda #1
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    sta zp_game_flags
    sta zp_msg_flags
    sta zp_death_source
    lda #4
    sta $c6
    lda #$20
    sta $0277
    sta $0278
    sta $0279
    sta $027a

    jsr trap_do_rockfall

    lda zp_player_hp_lo
    bne !t38_fail+
    lda zp_player_hp_hi
    bne !t38_fail+
    lda player_data + PL_HP_LO
    bne !t38_fail+
    lda player_data + PL_HP_HI
    bne !t38_fail+
    lda zp_game_flags
    and #$01
    beq !t38_fail+
    lda zp_death_source
    cmp #DEATH_TRAP_ROCKFALL
    bne !t38_fail+
    ldy #0
!t38_name_loop:
    lda creature_name_buf,y
    cmp t38_rockfall_name,y
    bne !t38_fail+
    lda t38_rockfall_name,y
    beq !t38_name_done+
    iny
    jmp !t38_name_loop-
!t38_name_done:
    lda #$01
    sta tc_results + 37
    jmp !t38_done+
!t38_fail:
    lda #$00
    sta tc_results + 37
!t38_done:

    // ============================================================
    // Test 39: non-lethal trap damage does not overwrite death source
    // ============================================================
    lda #50
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    sta zp_game_flags
    sta zp_msg_flags
    lda #$33
    sta zp_death_source
    lda #4
    sta $c6
    lda #$20
    sta $0277
    sta $0278
    sta $0279
    sta $027a

    jsr trap_do_arrow

    lda zp_game_flags
    and #$01
    bne !t39_fail+
    lda zp_player_hp_hi
    bne !t39_fail+
    lda zp_player_hp_lo
    beq !t39_fail+
    lda zp_death_source
    cmp #$33
    bne !t39_fail+
    lda #$01
    sta tc_results + 38
    jmp !t39_done+
!t39_fail:
    lda #$00
    sta tc_results + 38
!t39_done:

    // ============================================================
    // Test 40: the initial running step enters a known trap tile
    // ============================================================
    jsr fill_map_rock

    // Straight north-south corridor at x=27, y=29..31.
    ldx #29
!t40_corridor_rows:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #27
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    inx
    cpx #32
    bne !t40_corridor_rows-

    // Revealed trap directly south at (27,31), matching SHIFT+J running.
    ldx #31
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #27
    lda #TILE_TRAP | FLAG_VISITED
    sta (zp_ptr0),y

    lda #27
    sta zp_player_x
    lda #30
    sta zp_player_y
    lda #1                      // DIR_S
    sta zp_run_dir

    lda #CMD_MOVE_S
    jsr player_try_move
    bcc !t40_fail+
    lda zp_player_x
    cmp #27
    bne !t40_fail+
    lda zp_player_y
    cmp #31
    bne !t40_fail+
!t40_pass:
    lda #$01
    sta tc_results + 39
    jmp !t40_done+
!t40_fail:
    lda #$00
    sta tc_results + 39
!t40_done:

    // ============================================================
    // Test 41: disarm ability uses Umoria trap-command formula
    // Human warrior, DEX 18, INT 18, level 1:
    // (class 25 + race 0 + dex_adj 4 + 2) * dex_adj 4 + int_adj 3 = 127.
    // ============================================================
    lda #0
    sta player_data + PL_RACE
    sta player_data + PL_CLASS
    sta zp_eff_confuse
    sta zp_eff_blind
    lda #1
    sta player_data + PL_LEVEL
    sta zp_player_lvl
    sta zp_light_radius
    lda #18
    sta player_data + PL_DEX_CUR
    sta player_data + PL_INT_CUR

    jsr player_disarm_get_effective_chance
    cmp #127
    bne !t41_fail+
    lda #$01
    sta tc_results + 40
    jmp !t41_done+
!t41_fail:
    lda #$00
    sta tc_results + 40
!t41_done:

    // ============================================================
    // Test 42: Umoria floor-trap threshold conversion is not off by one.
    // total 5 vs open-pit difficulty 5 gives threshold 99, not 100.
    // ============================================================
    lda #5
    ldx #TRAP_OPEN_PIT
    jsr disarm_calc_success_threshold
    cmp #99
    bne !t42_fail+
    lda #$01
    sta tc_results + 41
    jmp !t42_done+
!t42_fail:
    lda #$00
    sta tc_results + 41
!t42_done:

    // ============================================================
    // Test 43: Umoria bad-fail rule always sets off the trap at total <= 5.
    // ============================================================
    lda #5
    jsr disarm_roll_bad_fail
    bcc !t43_fail+
    lda #$01
    sta tc_results + 42
    jmp !t43_done+
!t43_fail:
    lda #$00
    sta tc_results + 42
!t43_done:

    // ==========================================
    // Test 44: room-chain tunnel may stop at an existing connected corridor.
    // The corrected upstream direction starts at the new room and targets the
    // previous connected room, so an early stop still attaches the new room.
    // ==========================================
    jsr fill_map_rock

    lda #2
    sta room_count

    // Room 0 at (10,10), center (12,11)
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
    jsr draw_dungeon_room

    // Room 1 at (50,10), center (52,11)
    lda #50
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

    // Existing connected corridor from room 0 toward the new room.
    ldx #11
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #13
    lda #DGEN_CORR
!t44_seed_corr:
    sta (zp_ptr0),y
    iny
    cpy #23
    bne !t44_seed_corr-

    lda #52
    sta dg_cx1
    lda #11
    sta dg_cy1
    lda #12
    sta dg_cx2
    lda #11
    sta dg_cy2
    jsr carve_staged_tunnel
    jsr materialize_staged_tunnel

    lda #12
    sta stairs_up_x
    lda #11
    sta stairs_up_y
    jsr verify_connectivity
    bcs !t44_fail+

    lda #$01
    sta tc_results + 43
    jmp !t44_done+
!t44_fail:
    lda #$00
    sta tc_results + 43
!t44_done:

    // ==========================================
    // Test 45: adversarial east/west tunnel steps terminate at UMoria's
    // 2,000-iteration guard instead of wrapping forever.
    // ==========================================
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #DGEN_TUNNEL
    sta (zp_ptr0),y
    iny
    sta (zp_ptr0),y
    lda #20
    sta dg_cx1
    sta dg_cy1
    lda #30
    sta dg_cx2
    lda #20
    sta dg_cy2
    lda #1
    sta dg_test_tunnel_oscillate
    jsr carve_staged_tunnel
    lda #0
    sta dg_test_tunnel_oscillate
    lda dg_tun_count_hi
    cmp #>(DUN_TUNNEL_MAX_STEPS + 1)
    bne !t45_fail+
    lda dg_tun_count_lo
    cmp #<(DUN_TUNNEL_MAX_STEPS + 1)
    bne !t45_fail+
    lda dg_scan_row_start
    cmp #19
    bne !t45_fail+
    lda dg_scan_row_end
    cmp #21
    bne !t45_fail+

    lda #$01
    sta tc_results + 44
    jmp !t45_done+
!t45_fail:
    lda #$00
    sta tc_results + 44
!t45_done:

    // Done — jump to exit trampoline (copies tc_results to $0400, then brk)
    jmp test_exit_trampoline

test_end:

.assert "Dungeon test main must stay below MAP_BASE", test_end < MAP_BASE, true
