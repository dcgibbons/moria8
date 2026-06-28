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

eff_detect_timer: .byte 0
test_mon_active:    .byte 0
test_mon_x:         .byte 0
test_mon_y:         .byte 0
test_mon_type:      .byte 0
test_mon_flags:     .byte 0
test_glyph_active:  .byte 0
test_glyph_x:       .byte 0
test_glyph_y:       .byte 0

fi_item_id: .fill MAX_FLOOR_ITEMS, FI_EMPTY
it_display: .fill 2, 0
cr_display: .fill 2, 0
cr_color:   .fill 2, 0
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

test_start:
    sei
    cld
    ldx #$ff
    txs
    jsr test_detect_monsters_unvisited_skips_glyph
    jmp test_pass

test_detect_monsters_unvisited_skips_glyph:
    lda #0
    sta test_mon_active
    sta test_glyph_active
    sta eff_detect_timer
    lda #COL_WHITE
    sta zp_text_color
    jsr screen_clear
    lda #10
    sta zp_view_x
    sta zp_view_y
    lda #20
    sta zp_player_x
    sta zp_player_y
    lda #1
    sta zp_light_radius
    sta zp_player_dlvl
    lda #$4d
    sta cr_display + 1
    lda #COL_RED
    sta cr_color + 1

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
    bne test_fail
    rts

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
