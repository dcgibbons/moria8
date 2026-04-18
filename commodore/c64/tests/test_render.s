// test_render.s — Isolated renderer decision-tree checks
//
// Tests:
//  1. Unvisited tile renders as blank even if item/monster flags are set
//  2. Visible item overrides floor glyph/color
//  3. Visible monster overrides item
//  4. Player overrides monster and item
//  5. Detect Evil hides non-evil monsters on unvisited tiles
//  6. Town viewport clamps to the fixed 66x22 town bounds

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

// Keep the exit trampoline in the "Test Code" segment so run_tests.sh breaks
// on the final BRK after copying tc_results to $0400.
.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #5
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0824 "Main"

.encoding "screencode_mixed"

#import "../../common/zeropage.s"
#import "../memory.s"
#import "../screen.s"
#import "../../common/color.s"

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

#import "../../common/dungeon_data.s"

.const EMPTY_SLOT = $ff
.const MX_X = 0
.const MX_Y = 1
.const MX_TYPE = 2
.const DETECT_TIMER_EVIL_ONLY = $80 | 20

eff_detect_timer: .byte 0
test_item_active:   .byte 0
test_item_x:        .byte 0
test_item_y:        .byte 0
test_item_type:     .byte 0
test_item_color:    .byte COL_WHITE
test_mon_active:    .byte 0
test_mon_x:         .byte 0
test_mon_y:         .byte 0
test_mon_type:      .byte 0
test_expect_char:   .byte 0
test_expect_color:  .byte 0
tc_results:         .fill 6, $ff

fi_item_id: .fill 1, 0
it_display: .fill 2, 0
cr_display: .fill 2, 0
cr_color:   .fill 2, 0
cr_mflags:  .fill 2, 0
monster_stub_entry: .fill 12, EMPTY_SLOT

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

#import "../dungeon_render.s"

test_start:
    sei
    cld
    ldx #$ff
    txs

    ldx #5
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    jsr test_hidden_blank
    jsr test_item_override
    jsr test_monster_override
    jsr test_player_override
    jsr test_detect_evil_hides_non_evil
    jsr test_town_viewport_clamp
    jmp test_exit_trampoline

setup_scene:
    lda #0
    sta test_item_active
    sta test_mon_active
    sta eff_detect_timer
    lda #COL_WHITE
    sta zp_text_color
    jsr screen_clear
    lda #10
    sta zp_view_x
    lda #10
    sta zp_view_y
    lda #20
    sta zp_player_x
    lda #20
    sta zp_player_y
    lda #1
    sta zp_light_radius
    sta zp_player_dlvl
    lda #$69
    sta it_display + 1
    lda #COL_GREEN
    sta test_item_color
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
    sta test_item_active
    lda #24
    sta test_item_x
    lda #20
    sta test_item_y
    lda #1
    sta test_item_type
    lda #1
    sta test_mon_active
    lda #24
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
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
    lda #COL_BLACK
    sta test_expect_color
    jsr assert_rendered_tile
    bcs !fail+
    lda #$01
    sta tc_results
    rts
!fail:
    lda #$00
    sta tc_results
    rts

test_item_override:
    jsr setup_scene
    lda #1
    sta test_item_active
    lda #21
    sta test_item_x
    lda #20
    sta test_item_y
    lda #1
    sta test_item_type
    ldx #21
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_VISITED | FLAG_LIT | FLAG_HAS_ITEM)
    jsr map_set_tile
    lda #21
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda it_display + 1
    sta test_expect_char
    lda test_item_color
    sta test_expect_color
    jsr assert_rendered_tile
    bcs !fail+
    lda #$01
    sta tc_results + 1
    rts
!fail:
    lda #$00
    sta tc_results + 1
    rts

test_monster_override:
    jsr setup_scene
    lda #1
    sta test_item_active
    lda #21
    sta test_item_x
    lda #20
    sta test_item_y
    lda #1
    sta test_item_type
    lda #1
    sta test_mon_active
    lda #21
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    ldx #21
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_VISITED | FLAG_LIT | FLAG_HAS_ITEM | FLAG_OCCUPIED)
    jsr map_set_tile
    lda #21
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda cr_display + 1
    sta test_expect_char
    lda cr_color + 1
    sta test_expect_color
    jsr assert_rendered_tile
    bcs !fail+
    lda #$01
    sta tc_results + 2
    rts
!fail:
    lda #$00
    sta tc_results + 2
    rts

test_player_override:
    jsr setup_scene
    lda #1
    sta test_item_active
    lda #20
    sta test_item_x
    lda #20
    sta test_item_y
    lda #1
    sta test_item_type
    lda #1
    sta test_mon_active
    lda #20
    sta test_mon_x
    lda #20
    sta test_mon_y
    lda #1
    sta test_mon_type
    ldx #20
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_VISITED | FLAG_LIT | FLAG_HAS_ITEM | FLAG_OCCUPIED)
    jsr map_set_tile
    lda #20
    sta zp_temp0
    lda #20
    sta zp_temp1
    jsr render_single_tile
    lda #SC_PLAYER
    sta test_expect_char
    lda #COL_PLAYER
    sta test_expect_color
    jsr assert_rendered_tile
    bcs !fail+
    lda #$01
    sta tc_results + 3
    rts
!fail:
    lda #$00
    sta tc_results + 3
    rts

test_detect_evil_hides_non_evil:
    jsr setup_scene
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
    lda #SC_SPACE
    sta test_expect_char
    lda #COL_BLACK
    sta test_expect_color
    jsr assert_rendered_tile
    bcs !fail+
    lda #$01
    sta tc_results + 4
    rts
!fail:
    lda #$00
    sta tc_results + 4
    rts

test_town_viewport_clamp:
    lda #0
    sta zp_player_dlvl
    lda #TOWN_MAP_COLS - 1
    sta zp_player_x
    lda #TOWN_MAP_ROWS - 1
    sta zp_player_y
    jsr viewport_update
    lda zp_view_x
    cmp #TOWN_MAP_COLS - VIEWPORT_W
    bne !fail+
    lda zp_view_y
    cmp #TOWN_MAP_ROWS - VIEWPORT_H
    bne !fail+
    lda #$01
    sta tc_results + 5
    rts
!fail:
    lda #$00
    sta tc_results + 5
    rts

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
    lda color_row_lo,x
    sta zp_color_lo
    lda color_row_hi,x
    sta zp_color_hi

    lda zp_temp0
    sec
    sbc zp_view_x
    clc
    adc #VIEWPORT_X
    tay

    lda (zp_screen_lo),y
    cmp test_expect_char
    bne !fail+
    lda (zp_color_lo),y
    and #$0f                 // C64 color RAM only guarantees the low nibble
    cmp test_expect_color
    bne !fail+
    clc
    rts
!fail:
    sec
    rts
