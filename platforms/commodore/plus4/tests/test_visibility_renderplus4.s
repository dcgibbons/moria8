// test_visibility_renderplus4.s — Plus/4 production visibility to renderer checks

// Keep monster.s resident in this standalone PRG; the test calls the Plus/4
// monster_update_visibility_all wrapper so RAM visibility policy is covered.
#define PLUS4_INLINE_RUNTIME_BANKED_TEST

.pc = $1000 "Plus/4 visibility render test"

.encoding "screencode_mixed"

#import "../../../../core/zeropage.s"
#import "../memory.s"
#import "../hal/layout.s"
#import "../hal/lifecycle_policy.s"
#import "../screen.s"
#import "../../../../core/color.s"
#import "../../../../core/item_defs.s"

mmu_safe_map_read_ptr0:
    lda (zp_ptr0),y
    rts

mmu_safe_map_write_ptr0:
    sta (zp_ptr0),y
    rts

mmu_safe_db_read_ptr0:
    lda (zp_ptr0),y
    rts

mmu_safe_db_write_ptr0:
    sta (zp_ptr0),y
    rts

mmu_safe_db_read_ptr1:
    lda (zp_ptr1),y
    rts

mmu_safe_db_write_ptr1:
    sta (zp_ptr1),y
    rts

mmu_safe_map_read_ptr1:
    lda (zp_ptr1),y
    rts

mmu_safe_map_write_ptr1:
    sta (zp_ptr1),y
    rts

#import "../../../../core/dungeon_data.s"
#import "../../../../core/store_door_lookup.s"

walkable_table:
    .byte 1,0,0,0,0,0,0,1,0,1,1,1,0,0,1,0

#import "../../../../core/los_trace.s"

rng_range:
    lda #0
    rts

math_dice:
    lda #1
    sta zp_math_a
    lda #0
    sta zp_math_b
    rts

math_div_16x8:
    lda #0
    sta zp_math_a
    sta zp_math_b
    rts

tramp_spawn_special_room_monsters:
    rts

current_tier: .byte 0
current_overlay: .byte 0
dir_dx: .byte  0,  0, -1, 1, -1, 1, -1, 1
dir_dy: .byte -1,  1,  0, 0, -1,-1,  1, 1

#import "../../../../core/monster.s"

#import "../../../../core/player_move_live_occupant.s"
#import "../../../../core/dungeon_los.s"

// Production player_run.s shares the dungeon-feature command scratch block.
df_target_x:        .byte 0
df_target_y:        .byte 0
df_dir_idx:         .byte 0
df_found:           .byte 0
df_disarm_chance:   .byte 0
df_disarm_trap_idx: .byte 0
df_disarm_total:    .byte 0
df_disarm_base:     .byte 0

#import "../../../../core/player_run.s"

test_map_tile: .byte 0
test_map_x:    .byte 0
test_map_y:    .byte 0

map_set_tile:
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

eff_detect_timer: .byte 0
test_expect_char: .byte 0

fi_item_id: .fill MAX_FLOOR_ITEMS, FI_EMPTY
it_display: .fill 2, 0

item_get_floor_color:
    lda #COL_WHITE
    rts

floor_item_find_at:
    clc
    rts

glyph_find_at:
    clc
    rts

// Renderer glyph early-out reads the core array; all-zero => scan skipped,
// matching the always-missing stub above.
glyph_active: .fill MAX_GLYPHS, 0

player_get_infra_range:
    lda #0
    rts

#import "../dungeon_render.s"

test_plus4_irq_hidden_rom:
    lda TED_IRQ_STATUS
    sta TED_IRQ_STATUS
    rti

test_install_ram_irq_vectors:
    php
    sei
    sta PLUS4_RAM_ENABLE
    lda #0
    sta TED_IRQ_ENABLE
    lda TED_IRQ_STATUS
    sta TED_IRQ_STATUS
    lda #<test_plus4_irq_hidden_rom
    sta $fffa
    sta $fffe
    lda #>test_plus4_irq_hidden_rom
    sta $fffb
    sta $ffff
    plp
    rts

test_start:
    sei
    cld
    sta PLUS4_RAM_ENABLE
    jsr test_install_ram_irq_vectors
    ldx #$ff
    txs
    jsr test_production_visibility_renders_monster
    jsr test_lit_unvisited_production_hides_monster
    jsr test_horizontal_move_production_visibility_clears_monster
    jsr test_vertical_move_production_visibility_clears_monster
    jsr test_shared_sleep_wake_aggravate
    jsr test_runner_horizontal_continue
    jsr test_runner_vertical_continue
    jsr test_runner_production_matrix
    jmp test_pass

setup_scene:
    lda #0
    sta eff_detect_timer
    sta vis_room_revealed
    sta muv_clear_detected
    sta zp_eff_blind
    sta cr_mflags + 1
    sta fi_item_id
    lda #COL_WHITE
    sta zp_text_color
    jsr screen_clear
    jsr monster_init_table
    lda #10
    sta zp_view_x
    sta zp_view_y
    sta old_view_x
    sta old_view_y
    lda #20
    sta zp_player_x
    sta zp_player_y
    sta old_player_x
    sta old_player_y
    lda #4
    sta zp_light_radius
    lda #1
    sta zp_player_dlvl
    lda #$4d
    sta cr_display + 1
    lda #COL_RED
    sta cr_color + 1
    rts

place_monster_at_temp:
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda zp_temp0
    sta (zp_ptr0),y
    ldy #MX_Y
    lda zp_temp1
    sta (zp_ptr0),y
    ldy #MX_TYPE
    lda #1
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldx zp_temp0
    ldy zp_temp1
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    jsr map_set_tile
    rts

place_floor_at_temp:
    ldx zp_temp0
    ldy zp_temp1
    lda #TILE_FLOOR
    jsr map_set_tile
    rts

place_lit_floor_at_temp:
    ldx zp_temp0
    ldy zp_temp1
    lda #TILE_FLOOR | FLAG_LIT
    jsr map_set_tile
    rts

place_horizontal_test_monster:
    lda #20
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr place_floor_at_temp
    lda #21
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr place_floor_at_temp
    lda #22
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr place_floor_at_temp
    lda #23
    sta zp_temp0
    lda #20
    sta zp_temp1
    jmp place_monster_at_temp

place_vertical_test_monster:
    lda #20
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr place_floor_at_temp
    lda #20
    sta zp_temp0
    lda #21
    sta zp_temp1
    jsr place_floor_at_temp
    lda #20
    sta zp_temp0
    lda #22
    sta zp_temp1
    jsr place_floor_at_temp
    lda #20
    sta zp_temp0
    lda #23
    sta zp_temp1
    jmp place_monster_at_temp

assert_monster_visible_flag_set:
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    bne !ok+
    lda #$11
    jmp test_fail
!ok:
    rts

assert_monster_visible_flag_clear:
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    beq !ok+
    lda #$12
    jmp test_fail
!ok:
    rts

test_production_visibility_renders_monster:
    jsr setup_scene
    jsr place_horizontal_test_monster
    jsr monster_update_visibility_all
    jsr assert_monster_visible_flag_set
    jsr render_viewport
    lda #23
    sta zp_temp0
    lda #20
    sta zp_temp1
    lda cr_display + 1
    sta test_expect_char
    jmp assert_rendered_tile

test_lit_unvisited_production_hides_monster:
    jsr setup_scene
    lda #0
    sta zp_light_radius
    lda #20
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr place_lit_floor_at_temp
    lda #21
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr place_lit_floor_at_temp
    lda #22
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr place_lit_floor_at_temp
    lda #23
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr place_monster_at_temp
    ldx #23
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT | FLAG_OCCUPIED
    jsr map_set_tile
    jsr monster_update_visibility_all
    jmp assert_monster_visible_flag_clear

test_horizontal_move_production_visibility_clears_monster:
    jsr setup_scene
    jsr place_horizontal_test_monster
    jsr monster_update_visibility_all
    jsr assert_monster_visible_flag_set
    jsr render_viewport
    lda #23
    sta zp_temp0
    lda #20
    sta zp_temp1
    lda cr_display + 1
    sta test_expect_char
    jsr assert_rendered_tile

    lda #30
    sta zp_player_x
    jsr monster_update_visibility_all
    jsr assert_monster_visible_flag_clear
    jsr render_local_area
    lda #23
    sta zp_temp0
    lda #20
    sta zp_temp1
    lda #SC_SPACE
    sta test_expect_char
    jmp assert_rendered_tile

test_vertical_move_production_visibility_clears_monster:
    jsr setup_scene
    jsr place_vertical_test_monster
    jsr monster_update_visibility_all
    jsr assert_monster_visible_flag_set
    jsr render_viewport
    lda #20
    sta zp_temp0
    lda #23
    sta zp_temp1
    lda cr_display + 1
    sta test_expect_char
    jsr assert_rendered_tile

    lda #30
    sta zp_player_y
    jsr monster_update_visibility_all
    jsr assert_monster_visible_flag_clear
    jsr render_local_area
    lda #20
    sta zp_temp0
    lda #23
    sta zp_temp1
    lda #SC_SPACE
    sta test_expect_char
    jmp assert_rendered_tile

test_shared_sleep_wake_aggravate:
    jsr setup_scene
    lda #23
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr place_monster_at_temp
    ldx #0
    lda #25
    jsr monster_apply_sleep
    jsr monster_wake
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    bne !sleep_fail+
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    beq !sleep_fail+
    ldx #0
    lda #25
    jsr monster_apply_sleep
    lda #20
    jsr monster_aggravate_all
    ldx #0
    jsr monster_get_ptr
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    bne !sleep_fail+
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    beq !sleep_fail+
    rts
!sleep_fail:
    lda #$61
    jmp test_fail

test_runner_horizontal_continue:
    jsr setup_scene
    ldy #19
!row:
    ldx #18
!wall:
    lda #TILE_WALL_H | FLAG_VISITED
    jsr map_set_tile
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
    jsr map_set_tile
    inx
    cpx #25
    bne !floor-
    lda #20
    sta zp_player_x
    sta zp_player_y
    lda #3
    sta zp_run_dir
    jsr run_initialize
    bcc !fail+
    inc zp_player_x
    jsr run_area_affect
    bcs !fail+
    rts
!fail:
    lda #$62
    jmp test_fail

test_runner_vertical_continue:
    jsr setup_scene
    ldy #18
!row:
    ldx #29
!wall:
    lda #TILE_WALL_H | FLAG_VISITED
    jsr map_set_tile
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
    jsr map_set_tile
    iny
    cpy #25
    bne !floor-
    lda #30
    sta zp_player_x
    lda #20
    sta zp_player_y
    lda #1
    sta zp_run_dir
    jsr run_initialize
    bcc !fail+
    inc zp_player_y
    jsr run_area_affect
    bcs !fail+
    rts
!fail:
    lda #$63
    jmp test_fail

test_fill_runner_region:
    ldy #5
!row:
    ldx #5
!col:
    lda #TILE_WALL_H | FLAG_VISITED
    jsr map_set_tile
    inx
    cpx #36
    bne !col-
    iny
    cpy #36
    bne !row-
    rts

test_runner_production_matrix:
    jsr setup_scene
    jsr test_fill_runner_region

    // Map boundaries are hard walls.
    lda #0
    sta df_target_x
    sta df_target_y
    ldx #2
    jsr run_get_tile
    cmp #TILE_WALL_H | FLAG_VISITED
    beq !edge_x_ok+
    jmp !fail+
!edge_x_ok:
    ldx #0
    jsr run_get_tile
    cmp #TILE_WALL_H | FLAG_VISITED
    beq !edges_ok+
    jmp !fail+
!edges_ok:

    // Visible features and real town entrance metadata stop running.
    lda #20
    sta df_target_x
    sta df_target_y
    ldx #21
    ldy #20
    lda #TILE_STAIRS_DN | FLAG_VISITED
    jsr map_set_tile
    ldx #3
    jsr run_classify
    bcs !stairs_ok+
    jmp !fail+
!stairs_ok:
    ldx #21
    ldy #20
    lda #TILE_DOOR_OPEN | FLAG_VISITED
    jsr map_set_tile
    ldx #3
    jsr run_classify
    bcs !door_ok+
    jmp !fail+
!door_ok:
    ldx #21
    ldy #20
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_HAS_ITEM
    jsr map_set_tile
    ldx #3
    jsr run_classify
    bcs !item_ok+
    jmp !fail+
!item_ok:
    lda #0
    sta zp_player_dlvl
    lda #14
    sta df_target_x
    lda #6
    sta df_target_y
    ldx #15
    ldy #6
    lda #TILE_FLOOR | FLAG_VISITED
    jsr map_set_tile
    ldx #3
    jsr run_classify
    bcs !store_ok+
    jmp !fail+
!store_ok:
    lda #1
    sta zp_player_dlvl

    // Stale occupancy is repaired, while a live but invisible monster is
    // ignored and the same production monster in lit LOS stops the run.
    jsr monster_init_table
    lda #29
    sta df_target_x
    lda #20
    sta df_target_y
    ldx #30
    ldy #20
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_OCCUPIED
    jsr map_set_tile
    ldx #3
    jsr run_classify
    bcc !stale_class_ok+
    jmp !fail+
!stale_class_ok:
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #30
    :MapRead_ptr0_y()
    and #FLAG_OCCUPIED
    beq !stale_clear_ok+
    jmp !fail+
!stale_clear_ok:
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #1
    sta (zp_ptr0),y
    ldy #MX_X
    lda #34
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #30
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldx #34
    ldy #30
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_OCCUPIED
    jsr map_set_tile
    lda #6
    sta zp_player_x
    sta zp_player_y
    lda #33
    sta df_target_x
    lda #30
    sta df_target_y
    ldx #3
    jsr run_classify
    bcc !invisible_ok+
    jmp !fail+
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
    lda #10
    sta zp_player_x
    sta zp_player_y
    ldx #10
!los_floor:
    ldy #10
    lda #TILE_FLOOR | FLAG_VISITED
    jsr map_set_tile
    inx
    cpx #13
    bne !los_floor-
    ldx #12
    ldy #10
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_OCCUPIED
    jsr map_set_tile
    lda #11
    sta df_target_x
    lda #10
    sta df_target_y
    ldx #3
    jsr run_classify
    bcs !visible_ok+
    jmp !fail+
!visible_ok:

    // Open-area topology stops at a newly opened side boundary.
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
    jsr map_set_tile
    jsr run_area_affect
    bcs !topology_ok+
    jmp !fail+
!topology_ok:
    rts
!fail:
    lda #$64
    jmp test_fail

assert_rendered_tile:
    lda zp_temp1
    sec
    sbc zp_view_y
    clc
    adc #VIEWPORT_Y
    tax
    lda screen_row_lo,x
    sta zp_screen_lo
    lda screen_row_hi,x
    sta zp_screen_hi

    lda zp_temp0
    sec
    sbc zp_view_x
    clc
    adc #VIEWPORT_X
    tay

    lda (zp_screen_lo),y
    cmp test_expect_char
    beq !ok+
    lda #$51
    jmp test_fail
!ok:
    rts

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
