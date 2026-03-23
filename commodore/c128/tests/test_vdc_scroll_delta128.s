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

#import "../../common/dungeon_data.s"
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

fi_item_id: .fill MAX_FLOOR_ITEMS, FI_EMPTY
fi_x:       .fill MAX_FLOOR_ITEMS, 0
fi_y:       .fill MAX_FLOOR_ITEMS, 0
it_display: .fill 1, 0

cr_display: .fill 1, 0
cr_color:   .fill 1, 0
monster_stub_entry:
    .fill 3, EMPTY_SLOT

item_get_floor_color:
    lda #COL_WHITE
    rts

floor_item_find_at:
    clc
    rts

monster_find_at:
    clc
    rts

monster_get_ptr:
    lda #<monster_stub_entry
    sta zp_ptr0
    lda #>monster_stub_entry
    sta zp_ptr0_hi
    rts

monster_get_threat_color:
    lda #COL_WHITE
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

    jsr test_h_scroll_left_fast_path
    jsr test_left_scroll_falls_back
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
