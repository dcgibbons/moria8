// test_renderplus4.s — Plus/4 renderer parity checks

.pc = $1000 "Plus/4 render test"

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

mmu_safe_map_read_ptr1:
    lda (zp_ptr1),y
    rts

mmu_safe_map_write_ptr1:
    sta (zp_ptr1),y
    rts

#import "../../../../core/dungeon_data.s"

walkable_table:
    .byte 1,0,0,0,0,0,0,1,0,1,1,1,0,0,1,0

#import "../../../../core/los_trace.s"

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

.const EMPTY_SLOT = $ff
.const MX_X = 0
.const MX_Y = 1
.const MX_TYPE = 2
.const MX_FLAGS = 5
.const MF_VISIBLE = $08
.const MF_DETECTED = $10
.const DETECT_TIMER_TURNS = 20
.const CF_EVIL = $04
.const MAX_MONSTERS = 1

eff_detect_timer: .byte 0
eff_detect_evil_mode: .byte 0
vis_room_revealed: .byte 0
muv_clear_detected: .byte 0
test_mon_active:    .byte 0
test_mon_x:         .byte 0
test_mon_y:         .byte 0
test_mon_type:      .byte 0
test_mon_flags:     .byte 0
test_glyph_active:  .byte 0
test_glyph_x:       .byte 0
test_glyph_y:       .byte 0
test_expect_char:   .byte 0

fi_item_id: .fill MAX_FLOOR_ITEMS, FI_EMPTY
it_display: .fill 2, 0
cr_display: .fill 2, 0
cr_color:   .fill 2, 0
cr_mflags:  .fill 2, 0
monster_stub_entry: .fill 12, EMPTY_SLOT

item_get_floor_color:
    lda #COL_WHITE
    rts

floor_item_find_at:
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
    lda test_mon_flags
    sta monster_stub_entry + MX_FLAGS
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

monster_update_visibility_all:
    lda muv_clear_detected
    beq !done+
    lda monster_stub_entry + MX_FLAGS
    and #~MF_DETECTED & $ff
    sta monster_stub_entry + MX_FLAGS
    lda test_mon_flags
    and #~MF_DETECTED & $ff
    sta test_mon_flags
    lda #0
    sta muv_clear_detected
    lda #1
    rts
!done:
    lda #0
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

#import "../dungeon_render.s"
#import "../../../../core/player_magic_detect_evil_effect.s"

test_start:
    sei
    cld
    sta PLUS4_RAM_ENABLE
    ldx #$ff
    txs
    jsr test_detect_monsters_unvisited_skips_glyph
    jsr test_detect_evil_unvisited_shows_monster
    jsr test_visible_unvisited_shows_monster
    jsr test_detect_evil_effect_is_one_shot
    jsr test_hidden_blank
    jsr test_detect_timer_hides_unmarked_monster
    jsr test_real_los_diagonal_corner_block
    jsr test_horizontal_move_repairs_stale_monster
    jsr test_vertical_move_repairs_stale_monster
    jmp test_pass

setup_scene:
    lda #0
    sta test_mon_active
    sta test_glyph_active
    sta eff_detect_timer
    sta eff_detect_evil_mode
    sta test_mon_flags
    sta fi_item_id
    lda #COL_WHITE
    sta zp_text_color
    jsr screen_clear
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
    lda #1
    sta zp_light_radius
    sta zp_player_dlvl
    lda #$4d
    sta cr_display + 1
    lda #COL_RED
    sta cr_color + 1
    lda #0
    sta cr_mflags + 1
    rts

test_hidden_blank:
    jsr setup_scene
    lda #1
    sta test_mon_active
    sta test_mon_type
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_HAS_ITEM | FLAG_OCCUPIED)
    jsr map_set_tile
    lda #24
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda #SC_SPACE
    sta test_expect_char
    jmp assert_rendered_tile

test_detect_timer_hides_unmarked_monster:
    jsr setup_scene
    lda #DETECT_TIMER_TURNS
    sta eff_detect_timer
    lda #1
    sta test_mon_active
    sta test_mon_type
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #0
    sta test_mon_flags
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    jsr map_set_tile
    jsr render_viewport
    ldx #VIEWPORT_Y + 10
    lda screen_row_lo,x
    sta zp_screen_lo
    lda screen_row_hi,x
    sta zp_screen_hi
    ldy #VIEWPORT_X + 14
    lda (zp_screen_lo),y
    cmp #SC_SPACE
    beq !ok+
    jmp test_fail
!ok:
    rts

test_real_los_diagonal_corner_block:
    jsr setup_scene
    ldx #20
    ldy #20
    lda #(TILE_FLOOR | FLAG_VISITED | FLAG_LIT)
    jsr map_set_tile
    ldx #21
    ldy #20
    lda #(TILE_WALL_H | FLAG_VISITED | FLAG_LIT)
    jsr map_set_tile
    ldx #20
    ldy #19
    lda #(TILE_WALL_H | FLAG_VISITED | FLAG_LIT)
    jsr map_set_tile
    ldx #21
    ldy #19
    lda #(TILE_FLOOR | FLAG_VISITED | FLAG_LIT)
    jsr map_set_tile

    lda #20
    sta zp_player_x
    sta zp_player_y
    sta zp_temp0
    sta zp_temp1
    lda #21
    sta zp_los_dx
    lda #19
    sta zp_los_dy
    jsr mm_los_clear_to_target
    bcc !blocked+
    jmp test_fail
!blocked:
    ldx #21
    ldy #20
    lda #(TILE_FLOOR | FLAG_VISITED | FLAG_LIT)
    jsr map_set_tile

    lda #20
    sta zp_temp0
    sta zp_temp1
    lda #21
    sta zp_los_dx
    lda #19
    sta zp_los_dy
    jsr mm_los_clear_to_target
    bcs !open+
    jmp test_fail
!open:
    rts

test_detect_monsters_unvisited_skips_glyph:
    jsr setup_scene
    lda #DETECT_TIMER_TURNS
    sta eff_detect_timer
    lda #1
    sta test_glyph_active
    sta test_mon_active
    lda #24
    sta test_glyph_x
    sta test_mon_x
    lda #20
    sta test_glyph_y
    sta test_mon_y
    lda #1
    sta test_mon_type
    lda #MF_DETECTED
    sta test_mon_flags
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    jsr map_set_tile
    jsr render_viewport

    ldx #VIEWPORT_Y + 10
    lda screen_row_lo,x
    sta zp_screen_lo
    lda screen_row_hi,x
    sta zp_screen_hi
    ldy #VIEWPORT_X + 14
    lda (zp_screen_lo),y
    cmp cr_display + 1
    beq !ok+
    jmp test_fail
!ok:
    rts

test_detect_evil_unvisited_shows_monster:
    jsr setup_scene
    lda #1
    sta eff_detect_evil_mode
    sta test_mon_active
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    lda #MF_DETECTED
    sta test_mon_flags
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    jsr map_set_tile
    jsr render_viewport

    ldx #VIEWPORT_Y + 10
    lda screen_row_lo,x
    sta zp_screen_lo
    lda screen_row_hi,x
    sta zp_screen_hi
    ldy #VIEWPORT_X + 14
    lda (zp_screen_lo),y
    cmp cr_display + 1
    beq !ok+
    jmp test_fail
!ok:
    rts

test_visible_unvisited_shows_monster:
    jsr setup_scene
    lda #1
    sta test_mon_active
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    lda #MF_VISIBLE
    sta test_mon_flags
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    jsr map_set_tile
    jsr render_viewport

    ldx #VIEWPORT_Y + 10
    lda screen_row_lo,x
    sta zp_screen_lo
    lda screen_row_hi,x
    sta zp_screen_hi
    ldy #VIEWPORT_X + 14
    lda (zp_screen_lo),y
    cmp cr_display + 1
    beq !ok+
    jmp test_fail
!ok:
    rts

test_detect_evil_effect_is_one_shot:
    lda #0
    sta test_mon_active
    sta eff_detect_timer
    sta eff_detect_evil_mode
    sta vis_room_revealed
    sta muv_clear_detected
    sta test_mon_flags
    sta cr_mflags
    lda #CF_EVIL
    sta cr_mflags + 1
    lda #1
    sta test_mon_active
    sta test_mon_type
    sta monster_stub_entry + MX_TYPE
    lda #24
    sta test_mon_x
    sta monster_stub_entry + MX_X
    lda #20
    sta test_mon_y
    sta monster_stub_entry + MX_Y
    lda #10
    sta zp_view_x
    sta zp_view_y

    jsr eff_detect_evil_only
    bne !detected+
    jmp test_fail
!detected:
    lda eff_detect_evil_mode
    cmp #1
    beq !mode_ok+
    jmp test_fail
!mode_ok:
    lda monster_stub_entry + MX_FLAGS
    and #MF_DETECTED
    bne !flag_ok+
    jmp test_fail
!flag_ok:

    jsr detect_evil_clear_reveal
    lda eff_detect_evil_mode
    beq !cleared+
    jmp test_fail
!cleared:
    lda muv_clear_detected
    beq !clear_latch_ok+
    jmp test_fail
!clear_latch_ok:
    lda monster_stub_entry + MX_FLAGS
    and #MF_DETECTED
    beq !clear_flag_ok+
    jmp test_fail
!clear_flag_ok:
    lda test_mon_flags
    and #MF_DETECTED
    beq !clear_mirror_ok+
    jmp test_fail
!clear_mirror_ok:
    rts

test_horizontal_move_repairs_stale_monster:
    jsr setup_scene
    lda #MF_VISIBLE
    ora #MF_DETECTED
    sta test_mon_flags
    lda #1
    sta test_mon_active
    sta test_mon_type
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    ldx #24
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    jsr map_set_tile
    jsr render_viewport
    lda #24
    sta zp_temp0
    lda #20
    sta zp_temp1
    lda cr_display + 1
    sta test_expect_char
    jsr assert_rendered_tile

    lda #25
    sta zp_player_x
    lda #0
    sta test_mon_flags
    jsr render_local_area
    lda #24
    sta zp_temp0
    lda #20
    sta zp_temp1
    lda #SC_SPACE
    sta test_expect_char
    jmp assert_rendered_tile

test_vertical_move_repairs_stale_monster:
    jsr setup_scene
    lda #MF_VISIBLE
    ora #MF_DETECTED
    sta test_mon_flags
    lda #1
    sta test_mon_active
    sta test_mon_type
    lda #20
    sta test_mon_x
    lda #24
    sta test_mon_y
    ldx #20
    ldy #24
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    jsr map_set_tile
    jsr render_viewport
    lda #20
    sta zp_temp0
    lda #24
    sta zp_temp1
    lda cr_display + 1
    sta test_expect_char
    jsr assert_rendered_tile

    lda #25
    sta zp_player_y
    lda #0
    sta test_mon_flags
    jsr render_local_area
    lda #20
    sta zp_temp0
    lda #24
    sta zp_temp1
    lda #SC_SPACE
    sta test_expect_char
    jmp assert_rendered_tile

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
    beq !char_ok+
    jmp test_fail
!char_ok:
    rts

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
