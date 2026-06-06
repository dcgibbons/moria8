#importonce
// test_vdc_scroll_delta128.s — Runtime coverage for real VDC scroll-delta paths
//
// Exercises the actual C128 `render_viewport_scroll_delta` implementation,
// including VDC block copy and exposed-strip redraw. This closes the current
// coverage gap where `test_main_loop128.s` stubs the delta routine entirely.

#import "../../common/zeropage.s"
#import "test_helpers128.s"
#import "../memory128.s"
#import "../config128.s"
#import "../../common/item_defs.s"

.const EMPTY_SLOT = $ff
.const MX_X = 0
.const MX_Y = 1
.const MX_TYPE = 2
.const MAX_MONSTERS = 32
.const DETECT_TIMER_EVIL_ONLY = $80 | 20
.const CF_INFRA = $80

#import "../../common/dungeon_data.s"

// Test-only map write helper. Product code no longer exposes map_set_tile.
map_set_tile:
    pha
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    txa
    tay
    pla
    :MapWrite_ptr0_y()
    rts

#import "../../common/color.s"
#import "../screen_vdc.s"
#import "../dungeon_render_vdc.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $4000 "Test Code"

c128_restore_runtime_state:
    rts

// Minimal renderer dependencies for paths we intentionally do not exercise.
eff_detect_timer: .byte 0
test_item_active:    .byte 0
test_item_x:         .byte 0
test_item_y:         .byte 0
test_item_type:      .byte 0
test_item_color:     .byte COL_WHITE
test_mon_active:     .byte 0
test_mon_x:          .byte 0
test_mon_y:          .byte 0
test_mon_type:       .byte 0
test_mon_color_vic:  .byte COL_WHITE
test_infra_enabled:  .byte 0
test_glyph_active:   .byte 0
test_glyph_x:        .byte 0
test_glyph_y:        .byte 0

fi_item_id: .fill MAX_FLOOR_ITEMS, FI_EMPTY
fi_x:       .fill MAX_FLOOR_ITEMS, 0
fi_y:       .fill MAX_FLOOR_ITEMS, 0
it_display: .fill 2, 0

cr_display: .fill 2, 0
cr_color:   .fill 2, 0
cr_mflags:  .fill 2, 0
monster_stub_entry:
    .fill 12, EMPTY_SLOT

item_get_floor_color:
    lda test_item_color
    rts

floor_item_find_at:
    ldx test_item_active
    beq !miss+
    cmp test_item_x
    bne !miss+
    tya
    cmp test_item_y
    bne !miss+
    lda test_item_type
    sta fi_item_id
    ldx #0
    sec
    rts
!miss:
    clc
    rts

monster_find_at:
    ldx test_mon_active
    beq !miss+
    cmp test_mon_x
    bne !miss+
    tya
    cmp test_mon_y
    bne !miss+
    lda test_mon_type
    sta monster_stub_entry + MX_TYPE
    ldx #0
    sec
    rts
!miss:
    clc
    rts

monster_get_ptr:
    lda #<monster_stub_entry
    sta zp_ptr0
    lda #>monster_stub_entry
    sta zp_ptr0_hi
    rts

glyph_find_at:
    ldx test_glyph_active
    beq !miss+
    cmp test_glyph_x
    bne !miss+
    tya
    cmp test_glyph_y
    bne !miss+
    ldx #0
    sec
    rts
!miss:
    clc
    rts

monster_get_threat_color:
    lda test_mon_color_vic
    rts

monster_is_infra_visible_at:
    ldx zp_eff_blind
    bne !miss+
    ldx test_infra_enabled
    beq !miss+
    jsr monster_find_at
    bcc !miss+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda cr_mflags,x
    and #CF_INFRA
    beq !miss+
    sec
    rts
!miss:
    clc
    rts

test_row_seed:
    .byte $11, $18, $1f, $26, $2d, $34, $3b, $42, $49, $50
    .byte $57, $5e, $65, $6c, $73, $7a, $81, $88, $8f

test_attr_seed:
    .byte $0, $3, $6, $9, $c, $f, $2, $5, $8, $b
    .byte $e, $1, $4, $7, $a, $d, $0, $3, $6

test_row_rel:      .byte 0
test_col_rel:      .byte 0
test_expected_char:.byte 0
test_expected_attr:.byte 0
test_work:         .byte 0
test_abs_row:      .byte 0
test_abs_col:      .byte 0
test_copy_row:     .byte 0
test_copy_col:     .byte 0
test_src_row:      .byte 0

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #MMU_ALL_RAM
    sta MMU_CR

    lda #COL_WHITE
    sta zp_text_color
    lda #1
    sta zp_player_dlvl
    lda #6
    sta zp_light_radius
    lda #140
    sta zp_player_x
    lda #50
    sta zp_player_y
    lda #0
    sta eff_detect_timer

    jsr init_floor_items
    jsr test_render_single_tile_hidden_blank
    jsr test_render_single_tile_infra_warm_unvisited
    jsr test_render_single_tile_infra_cold_hidden
    jsr test_render_single_tile_infra_blind_hidden
    jsr test_render_single_tile_infra_warm_dimmed
    jsr test_render_single_tile_item_override
    jsr test_render_single_tile_monster_override
    jsr test_render_single_tile_player_override
    jsr test_render_single_tile_detect_evil_hides_non_evil
    jsr test_render_viewport_infra_warm_unvisited
    jsr test_render_viewport_glyph_overlay
    jsr test_h_scroll_left_fast_path
    jsr test_left_scroll_falls_back
    jsr test_v_scroll_up_first_op_uses_copy_mode
    jsr test_v_scroll_up_fast_path
    jsr test_v_scroll_down_fast_path

    jmp test_pass

init_floor_items:
    ldx #MAX_FLOOR_ITEMS - 1
    lda #FI_EMPTY
!loop:
    sta fi_item_id,x
    dex
    bpl !loop-
    jsr reset_render_overrides
    lda #$69
    sta it_display + 1
    lda #$4d
    sta cr_display + 1
    lda #0
    sta cr_mflags + 1
    rts

reset_render_overrides:
    lda #0
    sta test_item_active
    sta test_mon_active
    sta test_infra_enabled
    sta zp_eff_blind
    sta test_glyph_active
    rts

setup_single_tile_scene:
    jsr reset_render_overrides
    jsr screen_clear
    lda #10
    sta zp_view_x
    sta old_view_x
    sta zp_view_y
    sta old_view_y
    lda #20
    sta zp_player_x
    sta old_player_x
    lda #20
    sta zp_player_y
    sta old_player_y
    lda #1
    sta zp_light_radius
    lda #1
    sta zp_player_dlvl
    rts

test_render_single_tile_hidden_blank:
    jsr setup_single_tile_scene
    lda #1
    sta test_item_active
    lda #24
    sta test_item_x
    lda #20
    sta test_item_y
    lda #1
    sta test_item_type
    lda #COL_GREEN
    sta test_item_color
    lda #1
    sta test_mon_active
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    lda #COL_RED
    sta test_mon_color_vic
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_HAS_ITEM | FLAG_OCCUPIED)
    jsr map_set_tile
    lda #24
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda #10
    sta test_row_rel
    lda #14
    sta test_col_rel
    lda #SC_SPACE
    sta test_expected_char
    lda #VDC_BLACK
    sta test_expected_attr
    jsr assert_vdc_cell
    rts

test_render_single_tile_infra_warm_unvisited:
    jsr setup_single_tile_scene
    lda #1
    sta test_infra_enabled
    sta test_mon_active
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    lda #COL_RED
    sta test_mon_color_vic
    lda #CF_INFRA
    sta cr_mflags + 1
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    jsr map_set_tile
    lda #24
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda #10
    sta test_row_rel
    lda #14
    sta test_col_rel
    lda cr_display + 1
    sta test_expected_char
    lda vic_to_vdc_color + COL_RED
    sta test_expected_attr
    jsr assert_vdc_cell
    rts

test_render_single_tile_infra_cold_hidden:
    jsr setup_single_tile_scene
    lda #1
    sta test_infra_enabled
    sta test_mon_active
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    lda #COL_RED
    sta test_mon_color_vic
    lda #0
    sta cr_mflags + 1
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    jsr map_set_tile
    lda #24
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda #10
    sta test_row_rel
    lda #14
    sta test_col_rel
    lda #SC_SPACE
    sta test_expected_char
    lda #VDC_BLACK
    sta test_expected_attr
    jsr assert_vdc_cell
    rts

test_render_single_tile_infra_blind_hidden:
    jsr setup_single_tile_scene
    lda #1
    sta test_infra_enabled
    sta test_mon_active
    sta zp_eff_blind
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    lda #COL_RED
    sta test_mon_color_vic
    lda #CF_INFRA
    sta cr_mflags + 1
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    jsr map_set_tile
    lda #24
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda #10
    sta test_row_rel
    lda #14
    sta test_col_rel
    lda #SC_SPACE
    sta test_expected_char
    lda #VDC_BLACK
    sta test_expected_attr
    jsr assert_vdc_cell
    rts

test_render_single_tile_infra_warm_dimmed:
    jsr setup_single_tile_scene
    lda #1
    sta test_infra_enabled
    sta test_mon_active
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    lda #COL_RED
    sta test_mon_color_vic
    lda #CF_INFRA
    sta cr_mflags + 1
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_VISITED | FLAG_OCCUPIED)
    jsr map_set_tile
    lda #24
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda #10
    sta test_row_rel
    lda #14
    sta test_col_rel
    lda cr_display + 1
    sta test_expected_char
    lda vic_to_vdc_color + COL_RED
    sta test_expected_attr
    jsr assert_vdc_cell
    rts

test_render_single_tile_item_override:
    jsr setup_single_tile_scene
    lda #1
    sta test_item_active
    lda #21
    sta test_item_x
    lda #20
    sta test_item_y
    lda #1
    sta test_item_type
    lda #COL_GREEN
    sta test_item_color
    ldx #21
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_VISITED | FLAG_LIT | FLAG_HAS_ITEM)
    jsr map_set_tile
    lda #21
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda #10
    sta test_row_rel
    lda #11
    sta test_col_rel
    lda it_display + 1
    sta test_expected_char
    lda vic_to_vdc_color + COL_GREEN
    sta test_expected_attr
    jsr assert_vdc_cell
    rts

test_render_single_tile_monster_override:
    jsr setup_single_tile_scene
    lda #1
    sta test_item_active
    lda #21
    sta test_item_x
    lda #20
    sta test_item_y
    lda #1
    sta test_item_type
    lda #COL_GREEN
    sta test_item_color
    lda #1
    sta test_mon_active
    lda #21
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    lda #COL_RED
    sta test_mon_color_vic
    ldx #21
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_VISITED | FLAG_LIT | FLAG_HAS_ITEM | FLAG_OCCUPIED)
    jsr map_set_tile
    lda #21
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda #10
    sta test_row_rel
    lda #11
    sta test_col_rel
    lda cr_display + 1
    sta test_expected_char
    lda vic_to_vdc_color + COL_RED
    sta test_expected_attr
    jsr assert_vdc_cell
    rts

test_render_single_tile_player_override:
    jsr setup_single_tile_scene
    lda #1
    sta test_item_active
    lda #20
    sta test_item_x
    lda #20
    sta test_item_y
    lda #1
    sta test_item_type
    lda #COL_GREEN
    sta test_item_color
    lda #1
    sta test_mon_active
    lda #20
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    lda #COL_RED
    sta test_mon_color_vic
    ldx #20
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_VISITED | FLAG_LIT | FLAG_HAS_ITEM | FLAG_OCCUPIED)
    jsr map_set_tile
    lda #20
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda #10
    sta test_row_rel
    lda #10
    sta test_col_rel
    lda #SC_PLAYER
    sta test_expected_char
    lda #VDC_WHITE
    sta test_expected_attr
    jsr assert_vdc_cell
    rts

test_render_single_tile_detect_evil_hides_non_evil:
    jsr setup_single_tile_scene
    lda #DETECT_TIMER_EVIL_ONLY
    sta eff_detect_timer
    lda #1
    sta test_mon_active
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    lda #COL_RED
    sta test_mon_color_vic
    lda #0
    sta cr_mflags + 1
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    jsr map_set_tile
    lda #24
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda #10
    sta test_row_rel
    lda #14
    sta test_col_rel
    lda #SC_SPACE
    sta test_expected_char
    lda #VDC_BLACK
    sta test_expected_attr
    jsr assert_vdc_cell
    rts

test_render_viewport_infra_warm_unvisited:
    jsr setup_single_tile_scene
    lda #1
    sta test_infra_enabled
    sta test_mon_active
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    lda #COL_RED
    sta test_mon_color_vic
    lda #CF_INFRA
    sta cr_mflags + 1
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    jsr map_set_tile
    jsr render_viewport
    lda #10
    sta test_row_rel
    lda #14
    sta test_col_rel
    lda cr_display + 1
    sta test_expected_char
    lda vic_to_vdc_color + COL_RED
    sta test_expected_attr
    jsr assert_vdc_cell
    rts

test_render_viewport_glyph_overlay:
    jsr setup_single_tile_scene
    lda #1
    sta test_glyph_active
    lda #24
    sta test_glyph_x
    lda #20
    sta test_glyph_y
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_VISITED | FLAG_LIT)
    jsr map_set_tile
    jsr render_viewport
    lda #10
    sta test_row_rel
    lda #14
    sta test_col_rel
    lda #SC_GLYPH
    sta test_expected_char
    lda #VDC_DGREY
    sta test_expected_attr
    jsr assert_vdc_cell
    rts

test_h_scroll_left_fast_path:
    jsr prepare_pattern_screen
    lda #10
    sta old_view_x
    sta zp_view_y
    sta old_view_y
    lda #11
    sta zp_view_x
    jsr seed_right_strip_tiles
    jsr render_viewport_scroll_delta
    bcs !ok+
    jmp test_fail
!ok:

    lda #0
    sta test_row_rel
    lda #0
    sta test_col_rel
    ldx #0
    ldy #1
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #9
    sta test_row_rel
    lda #10
    sta test_col_rel
    ldx #9
    ldy #11
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #18
    sta test_row_rel
    lda #40
    sta test_col_rel
    ldx #18
    ldy #41
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #0
    sta test_row_rel
    lda #VIEWPORT_W - 1
    sta test_col_rel
    ldx #0
    jsr expect_tile_index
    jsr assert_vdc_cell

    lda #9
    sta test_row_rel
    lda #VIEWPORT_W - 1
    sta test_col_rel
    ldx #9
    jsr expect_tile_index
    jsr assert_vdc_cell

    lda #18
    sta test_row_rel
    lda #VIEWPORT_W - 1
    sta test_col_rel
    ldx #18
    jsr expect_tile_index
    jsr assert_vdc_cell
    rts

test_left_scroll_falls_back:
    jsr prepare_pattern_screen
    lda #11
    sta old_view_x
    lda #10
    sta zp_view_x
    lda #10
    sta zp_view_y
    sta old_view_y
    jsr render_viewport_scroll_delta
    bcc !ok+
    jmp test_fail
!ok:

    lda #0
    sta test_row_rel
    lda #0
    sta test_col_rel
    ldx #0
    ldy #0
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #9
    sta test_row_rel
    lda #17
    sta test_col_rel
    ldx #9
    ldy #17
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #18
    sta test_row_rel
    lda #VIEWPORT_W - 1
    sta test_col_rel
    ldx #18
    ldy #VIEWPORT_W - 1
    jsr expect_seed_cell
    jsr assert_vdc_cell
    rts

test_v_scroll_up_fast_path:
    jsr prepare_pattern_screen
    lda #10
    sta zp_view_x
    sta old_view_x
    sta old_view_y
    lda #11
    sta zp_view_y
    jsr seed_bottom_strip_tiles
    jsr render_viewport_scroll_delta
    bcs !ok+
    jmp test_fail
!ok:

    lda #0
    sta test_row_rel
    lda #0
    sta test_col_rel
    ldx #1
    ldy #0
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #8
    sta test_row_rel
    lda #33
    sta test_col_rel
    ldx #9
    ldy #33
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #17
    sta test_row_rel
    lda #55
    sta test_col_rel
    ldx #18
    ldy #55
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #VIEWPORT_H - 1
    sta test_row_rel
    lda #0
    sta test_col_rel
    ldx #0
    jsr expect_tile_index
    jsr assert_vdc_cell

    lda #VIEWPORT_H - 1
    sta test_row_rel
    lda #37
    sta test_col_rel
    ldx #37
    jsr expect_tile_index
    jsr assert_vdc_cell

    lda #VIEWPORT_H - 1
    sta test_row_rel
    lda #VIEWPORT_W - 1
    sta test_col_rel
    ldx #VIEWPORT_W - 1
    jsr expect_tile_index
    jsr assert_vdc_cell
    rts

test_v_scroll_up_first_op_uses_copy_mode:
    jsr prepare_pattern_screen
    lda #10
    sta zp_view_x
    sta old_view_x
    sta old_view_y
    lda #11
    sta zp_view_y
    jsr seed_bottom_strip_tiles
    jsr force_vdc_fill_mode_and_seed_char
    jsr render_viewport_scroll_delta
    bcs !ok+
    jmp test_fail
!ok:

    lda #0
    sta test_row_rel
    lda #0
    sta test_col_rel
    ldx #1
    ldy #0
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #0
    sta test_row_rel
    lda #33
    sta test_col_rel
    ldx #1
    ldy #33
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #0
    sta test_row_rel
    lda #VIEWPORT_W - 1
    sta test_col_rel
    ldx #1
    ldy #VIEWPORT_W - 1
    jsr expect_seed_cell
    jsr assert_vdc_cell
    rts

test_v_scroll_down_fast_path:
    jsr prepare_pattern_screen
    lda #10
    sta zp_view_x
    sta old_view_x
    lda #11
    sta old_view_y
    lda #10
    sta zp_view_y
    jsr seed_top_strip_tiles
    jsr render_viewport_scroll_delta
    bcs !ok+
    jmp test_fail
!ok:

    lda #1
    sta test_row_rel
    lda #0
    sta test_col_rel
    ldx #0
    ldy #0
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #10
    sta test_row_rel
    lda #29
    sta test_col_rel
    ldx #9
    ldy #29
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #VIEWPORT_H - 1
    sta test_row_rel
    lda #63
    sta test_col_rel
    ldx #VIEWPORT_H - 2
    ldy #63
    jsr expect_seed_cell
    jsr assert_vdc_cell

    lda #0
    sta test_row_rel
    lda #0
    sta test_col_rel
    ldx #0
    jsr expect_tile_index
    jsr assert_vdc_cell

    lda #0
    sta test_row_rel
    lda #41
    sta test_col_rel
    ldx #41
    jsr expect_tile_index
    jsr assert_vdc_cell

    lda #0
    sta test_row_rel
    lda #VIEWPORT_W - 1
    sta test_col_rel
    ldx #VIEWPORT_W - 1
    jsr expect_tile_index
    jsr assert_vdc_cell
    rts

prepare_pattern_screen:
    jsr screen_clear
    jsr seed_viewport_pattern
    rts

seed_viewport_pattern:
    lda #0
    sta test_row_rel
!row_loop:
    ldx test_row_rel
    lda screen_row_lo + VIEWPORT_Y,x
    clc
    adc #VIEWPORT_X
    tay
    lda screen_row_hi + VIEWPORT_Y,x
    adc #0
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg

    ldx test_row_rel
    lda test_row_seed,x
    sta test_expected_char
    ldy #0
!char_loop:
    jsr vdc_wait
    lda test_expected_char
    sta VDC_DATA_REG
    inc test_expected_char
    iny
    cpy #VIEWPORT_W
    bne !char_loop-

    ldx test_row_rel
    lda color_row_lo + VIEWPORT_Y,x
    clc
    adc #VIEWPORT_X
    tay
    lda color_row_hi + VIEWPORT_Y,x
    adc #0
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg

    ldx test_row_rel
    lda test_attr_seed,x
    sta test_work
    ldy #0
!attr_loop:
    jsr vdc_wait
    lda test_work
    ora #VDC_ATTR_MODE
    sta VDC_DATA_REG
    inc test_work
    lda test_work
    and #$0f
    sta test_work
    iny
    cpy #VIEWPORT_W
    bne !attr_loop-

    inc test_row_rel
    lda test_row_rel
    cmp #VIEWPORT_H
    bne !row_loop-
    rts

seed_right_strip_tiles:
    lda zp_view_x
    clc
    adc #VIEWPORT_W - 1
    sta test_abs_col
    lda #0
    sta test_row_rel
!loop:
    ldx test_row_rel
    txa
    and #$0f
    asl
    asl
    asl
    asl
    ora #FLAG_VISITED | FLAG_LIT
    sta test_work
    ldx test_abs_col
    ldy test_row_rel
    tya
    clc
    adc zp_view_y
    tay
    lda test_work
    jsr map_set_tile
    inc test_row_rel
    lda test_row_rel
    cmp #VIEWPORT_H
    bne !loop-
    rts

seed_bottom_strip_tiles:
    lda zp_view_y
    clc
    adc #VIEWPORT_H - 1
    sta test_abs_row
    lda #0
    sta test_col_rel
!loop:
    ldx test_col_rel
    txa
    and #$0f
    asl
    asl
    asl
    asl
    ora #FLAG_VISITED | FLAG_LIT
    sta test_work
    ldx test_col_rel
    txa
    clc
    adc zp_view_x
    tax
    ldy test_abs_row
    lda test_work
    jsr map_set_tile
    inc test_col_rel
    lda test_col_rel
    cmp #VIEWPORT_W
    bne !loop-
    rts

seed_top_strip_tiles:
    lda zp_view_y
    sta test_abs_row
    lda #0
    sta test_col_rel
!loop:
    ldx test_col_rel
    txa
    and #$0f
    asl
    asl
    asl
    asl
    ora #FLAG_VISITED | FLAG_LIT
    sta test_work
    ldx test_col_rel
    txa
    clc
    adc zp_view_x
    tax
    ldy test_abs_row
    lda test_work
    jsr map_set_tile
    inc test_col_rel
    lda test_col_rel
    cmp #VIEWPORT_W
    bne !loop-
    rts

force_vdc_fill_mode_and_seed_char:
    lda #$07
    ldy #$ff
    jsr vdc_set_update_addr
    lda #$55
    ldx #31
    jsr vdc_write_reg
    lda #$00
    ldx #24
    jsr vdc_write_reg
    rts

expect_seed_cell:
    sty test_work
    lda test_row_seed,x
    clc
    adc test_work
    sta test_expected_char

    lda test_attr_seed,x
    clc
    adc test_work
    and #$0f
    ora #VDC_ATTR_MODE
    sta test_expected_attr
    rts

expect_tile_index:
    txa
    and #$0f
    tax
    lda tile_screen_codes,x
    sta test_expected_char
    lda tile_vdc_colors,x
    sta test_expected_attr
    rts

assert_vdc_cell:
    jsr read_vdc_char
    cmp test_expected_char
    beq !char_ok+
    jmp test_fail
!char_ok:
    jsr read_vdc_attr
    cmp test_expected_attr
    beq !attr_ok+
    jmp test_fail
!attr_ok:
    rts

read_vdc_char:
    lda test_row_rel
    clc
    adc #VIEWPORT_Y
    tax
    lda screen_row_lo,x
    clc
    adc #VIEWPORT_X
    adc test_col_rel
    tay
    lda screen_row_hi,x
    adc #0
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    rts

read_vdc_attr:
    lda test_row_rel
    clc
    adc #VIEWPORT_Y
    tax
    lda color_row_lo,x
    clc
    adc #VIEWPORT_X
    adc test_col_rel
    tay
    lda color_row_hi,x
    adc #0
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    rts

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
