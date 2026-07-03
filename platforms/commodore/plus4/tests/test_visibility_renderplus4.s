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

eff_detect_timer: .byte 0
vis_room_revealed: .byte 0
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
    jsr test_horizontal_move_production_visibility_clears_monster
    jsr test_vertical_move_production_visibility_clears_monster
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
