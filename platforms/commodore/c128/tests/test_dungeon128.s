#importonce
// test_dungeon128.s — Dungeon render color-path regression checks (C128)

#import "../../../../core/zeropage.s"
#import "test_helpers128.s"
#import "../memory128.s"
#import "../hal/lifecycle_policy.s"
#import "../../../../core/dungeon_data.s"
#import "../../../../core/store_door_lookup.s"
#import "../../../../core/color.s"
#import "../screen_vdc.s"
#import "../monster_threat_vdc.s"

.const RACE_PROP_SIZE = 10

#define COMPILE_EMBEDDED_DUNGEON_TEST_ROSTER
#define C128_UNIT_TEST

walkable_table:
    .byte 1,0,0,0,0,0,0,1,0,1,1,1,0,0,1,0

#import "../../../../core/dungeon_los.s"
#import "../../../../core/monster.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $4000 "Test Code"

c128_restore_runtime_state:
    rts

eff_detect_timer: .byte 0

player_get_infra_range:
    lda #0
    rts

math_multiply:
    lda #0
    sta zp_math_a
    sta zp_math_b
    rts

dir_dx: .byte  0,  0, -1, 1, -1, 1, -1, 1
dir_dy: .byte -1,  1,  0, 0, -1,-1,  1, 1

mmu_safe_map_read_ptr0:
    jsr mmu_select_bank1
    lda (zp_ptr0),y
    pha
    jsr mmu_select_bank0
    pla
    rts

mmu_safe_map_write_ptr0:
    pha
    jsr mmu_select_bank1
    pla
    sta (zp_ptr0),y
    pha
    jsr mmu_select_bank0
    pla
    rts

mmu_safe_map_read_ptr1:
    jsr mmu_select_bank1
    lda (zp_ptr1),y
    pha
    jsr mmu_select_bank0
    pla
    rts

mmu_safe_map_write_ptr1:
    pha
    jsr mmu_select_bank1
    pla
    sta (zp_ptr1),y
    pha
    jsr mmu_select_bank0
    pla
    rts

mmu_safe_db_read_ptr1:
    jmp mmu_safe_map_read_ptr1

mmu_safe_mark_visited_row_ptr0:
    sta test_mark_visited_row_end
    lda #0
    sta test_mark_visited_seen_new
    jsr mmu_select_bank1
!mark:
    lda (zp_ptr0),y
    sta test_mark_visited_tile_tmp
    lda mmu_common_row_detect_new
    beq !write+
    lda test_mark_visited_tile_tmp
    and #FLAG_VISITED
    bne !write+
    lda #1
    sta test_mark_visited_seen_new
!write:
    lda test_mark_visited_tile_tmp
    ora mmu_common_row_mask
    sta (zp_ptr0),y
    cpy test_mark_visited_row_end
    beq !done+
    iny
    jmp !mark-
!done:
    jsr mmu_select_bank0
    lda test_mark_visited_seen_new
    rts

test_mark_visited_row_end:
    .byte 0
test_mark_visited_seen_new:
    .byte 0
test_mark_visited_tile_tmp:
    .byte 0

// Production player_run.s shares the dungeon-feature command scratch block.
df_target_x:        .byte 0
df_target_y:        .byte 0
df_dir_idx:         .byte 0
df_found:           .byte 0
df_disarm_chance:   .byte 0
df_disarm_trap_idx: .byte 0
df_disarm_total:    .byte 0
df_disarm_base:     .byte 0
#import "../../../../core/player_move_live_occupant.s"
#import "../../../../core/player_run.s"

test_map_tile: .byte 0
test_map_x:    .byte 0
test_map_y:    .byte 0

test_set_map_tile:
    sta test_map_tile
    stx test_map_x
    sty test_map_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    txa
    tay
    lda test_map_tile
    :MapWrite_ptr0_y()
    ldx test_map_x
    ldy test_map_y
    rts

test_runner_horizontal_continue:
    lda #1
    sta zp_player_dlvl
    lda #20
    sta zp_player_x
    sta zp_player_y
    ldy #19
!row:
    ldx #18
!wall:
    lda #TILE_WALL_H | FLAG_VISITED
    jsr test_set_map_tile
    inx
    cpx #25
    bne !wall-
    iny
    cpy #22
    bne !row-
    ldx #18
!floor:
    ldy #20
    lda #TILE_FLOOR | FLAG_VISITED
    jsr test_set_map_tile
    inx
    cpx #25
    bne !floor-
    lda #3
    sta zp_run_dir
    jsr run_initialize
    bcc !fail+
    inc zp_player_x
    jsr run_area_affect
    bcs !fail+
    rts
!fail:
    jmp test_fail

test_runner_vertical_continue:
    lda #30
    sta zp_player_x
    lda #20
    sta zp_player_y
    ldy #18
!row:
    ldx #29
!wall:
    lda #TILE_WALL_H | FLAG_VISITED
    jsr test_set_map_tile
    inx
    cpx #32
    bne !wall-
    iny
    cpy #25
    bne !row-
    ldy #18
!floor:
    ldx #30
    lda #TILE_FLOOR | FLAG_VISITED
    jsr test_set_map_tile
    iny
    cpy #25
    bne !floor-
    lda #1
    sta zp_run_dir
    jsr run_initialize
    bcc !fail+
    inc zp_player_y
    jsr run_area_affect
    bcs !fail+
    rts
!fail:
    jmp test_fail

test_fill_runner_region:
    ldy #5
!row:
    ldx #5
!col:
    lda #TILE_WALL_H | FLAG_VISITED
    jsr test_set_map_tile
    inx
    cpx #56
    bne !col-
    iny
    cpy #36
    bne !row-
    rts

test_runner_production_matrix:
    jsr test_fill_runner_region
    lda #1
    sta zp_player_dlvl
    lda #0
    sta zp_eff_blind
    lda #5
    sta zp_light_radius

    // Map boundaries are hard walls.
    lda #0
    sta df_target_x
    sta df_target_y
    ldx #2
    jsr run_get_tile
    cmp #TILE_WALL_H | FLAG_VISITED
    beq !edge_x_ok+
    jmp test_fail
!edge_x_ok:
    ldx #0
    jsr run_get_tile
    cmp #TILE_WALL_H | FLAG_VISITED
    beq !edges_ok+
    jmp test_fail
!edges_ok:

    // Visible dungeon features stop the leading-edge scan.
    lda #20
    sta df_target_x
    sta df_target_y
    ldx #21
    ldy #20
    lda #TILE_STAIRS_DN | FLAG_VISITED
    jsr test_set_map_tile
    ldx #3
    jsr run_classify
    bcs !stairs_ok+
    jmp test_fail
!stairs_ok:
    ldx #21
    ldy #20
    lda #TILE_DOOR_OPEN | FLAG_VISITED
    jsr test_set_map_tile
    ldx #3
    jsr run_classify
    bcs !door_ok+
    jmp test_fail
!door_ok:
    ldx #21
    ldy #20
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_HAS_ITEM
    jsr test_set_map_tile
    ldx #3
    jsr run_classify
    bcs !item_ok+
    jmp test_fail
!item_ok:

    // Town entrances are coordinate metadata over ordinary floor.
    lda #0
    sta zp_player_dlvl
    lda #14
    sta df_target_x
    lda #6
    sta df_target_y
    ldx #15
    ldy #6
    lda #TILE_FLOOR | FLAG_VISITED
    jsr test_set_map_tile
    ldx #3
    jsr run_classify
    bcs !store_ok+
    jmp test_fail
!store_ok:
    lda #1
    sta zp_player_dlvl

    // A stale occupied bit is repaired and remains ordinary open floor.
    jsr monster_init_table
    lda #39
    sta df_target_x
    lda #20
    sta df_target_y
    ldx #40
    ldy #20
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_OCCUPIED
    jsr test_set_map_tile
    ldx #3
    jsr run_classify
    bcc !stale_class_ok+
    jmp test_fail
!stale_class_ok:
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #40
    :MapRead_ptr0_y()
    and #FLAG_OCCUPIED
    beq !stale_clear_ok+
    jmp test_fail
!stale_clear_ok:

    // A live monster outside LOS does not stop; moving that same production
    // monster into lit LOS does stop without manually seeding MF_VISIBLE.
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #1
    sta (zp_ptr0),y
    ldy #MX_X
    lda #50
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #30
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldx #50
    ldy #30
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_OCCUPIED
    jsr test_set_map_tile
    lda #10
    sta zp_player_x
    sta zp_player_y
    lda #49
    sta df_target_x
    lda #30
    sta df_target_y
    ldx #3
    jsr run_classify
    bcc !invisible_ok+
    jmp test_fail
!invisible_ok:

    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda #12
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #10
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldx #10
!los_floor:
    ldy #10
    lda #TILE_FLOOR | FLAG_VISITED
    jsr test_set_map_tile
    inx
    cpx #13
    bne !los_floor-
    ldx #12
    ldy #10
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_OCCUPIED
    jsr test_set_map_tile
    lda #11
    sta df_target_x
    lda #10
    sta df_target_y
    ldx #3
    jsr run_classify
    bcs !visible_ok+
    jmp test_fail
!visible_ok:

    // Open-area topology stops when a newly open side breaks the wall.
    lda #RUNF_OPEN | RUNF_BREAK_LEFT
    sta run_flags
    lda #3
    sta run_prev_dir
    lda #21
    sta zp_player_x
    lda #20
    sta zp_player_y
    ldx #22
    ldy #19
    lda #TILE_FLOOR | FLAG_VISITED
    jsr test_set_map_tile
    jsr run_area_affect
    bcs !topology_ok+
    jmp test_fail
!topology_ok:
    rts

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #MMU_ALL_RAM
    sta $ff00

    // Test 1: map base/end are writable/readable
    lda #$a5
    sta MAP_BASE
    lda #$5a
    sta MAP_END
    lda MAP_BASE
    cmp #$a5
    bne !fail1+
    lda MAP_END
    cmp #$5a
    bne !fail1+

    // Test 2: SCREEN_RAM writes don't clobber sampled map bytes
    lda MAP_BASE
    sta $02f0
    lda MAP_END
    sta $02f1

    lda #$11
    sta SCREEN_RAM + 0
    lda #$22
    sta SCREEN_RAM + 1
    lda #$33
    sta SCREEN_RAM + 2
    lda #$44
    sta SCREEN_RAM + 3

    lda MAP_BASE
    cmp $02f0
    bne !fail1+
    lda MAP_END
    cmp $02f1
    bne !fail1+

    // Test 3: Color translation consistency used by dungeon renderer
    // Floor in LOS: tile type 0 -> COL_DGREY -> VDC_DGREY
    ldx tile_colors + 0
    lda vic_to_vdc_color,x
    cmp #VDC_DGREY
    bne !fail1+

    // Floor out of LOS: dimming path writes VDC_DGREY directly.
    lda #VDC_DGREY
    cmp vic_to_vdc_color + COL_DGREY
    bne !fail1+

    // Corridor rock in LOS: hardcoded VDC_LGREY path must match palette.
    lda #VDC_LGREY
    cmp vic_to_vdc_color + COL_LGREY
    bne !fail1+

    // Rubble uses canonical grey, which intentionally falls back to VDC dark grey.
    ldx tile_colors + 11
    lda vic_to_vdc_color,x
    cmp #VDC_DGREY
    bne !fail1+

    // Magma in LOS: tile type 12 -> COL_RED -> VDC_RED
    ldx tile_colors + 12
    lda vic_to_vdc_color,x
    cmp #VDC_RED
    bne !fail1+

    // Guard runtime nibble encoding so dim floor/wall/magma don't drift.
    lda #VDC_DGREY
    cmp #(vdc_encode_rgbi(8) | VDC_ATTR_MODE)
    bne !fail1+
    lda #VDC_LGREY
    cmp #(vdc_encode_rgbi(7) | VDC_ATTR_MODE)
    bne !fail1+
    lda #VDC_RED
    cmp #(vdc_encode_rgbi(4) | VDC_ATTR_MODE)
    bne !fail1+

    jmp !after_fail1+
!fail1:
    jmp test_fail
!after_fail1:

    // Test 4: threat-coded monster colors stay stable on C128 live render path.
    lda #5
    sta zp_player_lvl

    lda #1
    sta cr_level + 1
    lda #3
    sta cr_level + 13
    lda #5
    sta cr_level + 24
    lda #COL_CYAN
    sta cr_color + 57

    ldx #1                      // cr_level = 1, town-safe dungeon creature
    jsr monster_get_threat_color
    cmp #COL_THREAT_LOW
    bne !fail2+

    ldx #13                     // cr_level = 3
    jsr monster_get_threat_color
    cmp #COL_THREAT_MED
    bne !fail2+

    lda #3
    sta zp_player_lvl
    ldx #24                     // cr_level = 5
    jsr monster_get_threat_color
    cmp #COL_THREAT_HIGH
    bne !fail2+

    lda #2
    sta zp_player_lvl
    ldx #24                     // cr_level = 5
    jsr monster_get_threat_color
    cmp #COL_THREAT_DEADLY
    bne !fail2+

    ldx #57                     // Town NPCs keep authored species colors
    jsr monster_get_threat_color
    cmp cr_color + 57
    bne !fail2+

    // Test 5: VDC special-effect flash color setter/resetter stay in sync
    // with the VIC->VDC palette translation table.
    ldx #17
    lda #COL_CYAN
    jsr screen_flash_set_color
    lda sfa_flash_attr
    cmp vic_to_vdc_color + COL_CYAN
    bne !fail2+
    cpx #17
    bne !fail2+

    ldx #17
    jsr screen_flash_reset_color
    lda sfa_flash_attr
    cmp #VDC_WHITE
    bne !fail2+
    cpx #17
    bne !fail2+

    jmp !after_fail2+
!fail2:
    jmp test_fail
!after_fail2:

    // Test 6: los_is_visible must read the live Bank 1 map on C128.
    // Bank 0 mirror at the same address is deliberately dark, while Bank 1
    // carries a lit tile; raw pointer reads would see the wrong bank.
    lda #10
    sta zp_player_y
    lda #10
    sta zp_player_x
    lda #0
    sta zp_light_radius

    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    ldy #12
    lda #TILE_FLOOR
    sta (zp_ptr0),y

    jsr mmu_select_bank1
    ldy #12
    lda #TILE_WALL_H | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y
    jsr mmu_select_bank0

    ldx #12
    ldy #10
    jsr los_is_visible
    bcs !bank_los_ok+
    jmp test_fail
!bank_los_ok:

    // Test 7: real LOS tracing on C128 must honor live Bank 1 doors.
    // A closed door between player and target blocks; an open door clears.
    jsr mmu_select_bank1
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    ldy #11
    sta (zp_ptr0),y
    ldy #12
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y
    ldy #13
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    ldy #14
    sta (zp_ptr0),y
    jsr mmu_select_bank0

    lda #10
    sta zp_player_x
    sta zp_player_y
    sta zp_temp0
    sta zp_temp1
    lda #14
    sta zp_los_dx
    lda #10
    sta zp_los_dy
    jsr mm_los_clear_to_target
    bcc !closed_door_blocks+
    jmp test_fail
!closed_door_blocks:

    jsr mmu_select_bank1
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #12
    lda #TILE_DOOR_OPEN
    sta (zp_ptr0),y
    jsr mmu_select_bank0

    lda #10
    sta zp_temp0
    sta zp_temp1
    lda #14
    sta zp_los_dx
    lda #10
    sta zp_los_dy
    jsr mm_los_clear_to_target
    bcs !open_door_clears+
    jmp test_fail
!open_door_clears:

    // Test 8: diagonal LOS on C128 must honor live Bank 1 corner blockers.
    // A diagonal target is blocked when both orthogonal side cells are closed.
    jsr mmu_select_bank1
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    ldy #21
    lda #TILE_WALL_H
    sta (zp_ptr0),y
    ldx #19
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_WALL_H
    sta (zp_ptr0),y
    ldy #21
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    jsr mmu_select_bank0

    lda #20
    sta zp_temp0
    sta zp_temp1
    lda #21
    sta zp_los_dx
    lda #19
    sta zp_los_dy
    jsr mm_los_clear_to_target
    bcc !corner_blocks+
    jmp test_fail
!corner_blocks:

    jsr mmu_select_bank1
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #21
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    jsr mmu_select_bank0

    lda #20
    sta zp_temp0
    sta zp_temp1
    lda #21
    sta zp_los_dx
    lda #19
    sta zp_los_dy
    jsr mm_los_clear_to_target
    bcs !corner_open_clears+
    jmp test_fail
!corner_open_clears:

    // Tests 9-10: shared UMoria runner continues through straight corridors
    // using the C128 production Bank 1 map access path.
    jsr test_runner_horizontal_continue
    jsr test_runner_vertical_continue
    jsr test_runner_production_matrix

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass

race_properties: .fill RACE_PROP_SIZE, 0

// Dependencies outside the visibility/runner slice under test.
rng_range: rts
rng_range_word: rts
math_dice: rts
math_div_16x8: rts
ccl_div_24x8: rts
tramp_spawn_special_room_monsters: rts
tramp_ego_apply_damage: rts
tier_load: rts
item_get_missile: rts
floor_item_find_at: rts
hal_sound_play: rts
msg_build_action: rts
cmb_print_buf: rts

current_tier: .byte 0
tier_silent_restore: .byte 0
tier_count_table: .fill 5, 0
c128_tier_cache_slot_lo: .fill 5, 0
c128_tier_cache_slot_hi: .fill 5, 0
