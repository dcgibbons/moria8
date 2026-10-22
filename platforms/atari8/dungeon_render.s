#importonce
// dungeon_render.s — Atari 8-bit 40x25 monochrome ANTIC Mode 2 viewport renderer.
//
// Reads the live 80x48 dungeon map at MAP_BASE ($C100-$CFFF) and renders the
// 38x19 viewport to SCREEN_RAM ($0800).
//
// Monochrome Mode 2 LOS & highlight conventions:
// - Lit / in-LOS floor renders as '.' ($2E); remembered out-of-LOS floor
//   (FLAG_VISITED without FLAG_LIT outside zp_light_radius) renders as space
//   ($20) while remembered walls ('#'), doors ('+'/'\''), and stairs ('<'/'>')
//   remain visible.
// - Player '@' renders in hardware bit-7 inverse video ($80).

#import "memory.s"
#import "screen.s"

// ============================================================
// viewport_update — Center viewport on player, clamp to map edges
// ============================================================
viewport_update:
    lda zp_player_dlvl
    bne !dungeon_bounds+

    // Town uses a fixed 66x22 logical map
    lda zp_player_x
    sec
    sbc #VIEWPORT_W / 2
    bcs !tvx_not_neg+
    lda #0
    beq !tvx_store+
!tvx_not_neg:
    cmp #TOWN_MAP_COLS - VIEWPORT_W
    bcc !tvx_store+
    lda #TOWN_MAP_COLS - VIEWPORT_W
!tvx_store:
    sta zp_view_x

    lda zp_player_y
    sec
    sbc #VIEWPORT_H / 2
    bcs !tvy_not_neg+
    lda #0
    beq !tvy_store+
!tvy_not_neg:
    cmp #TOWN_MAP_ROWS - VIEWPORT_H
    bcc !tvy_store+
    lda #TOWN_MAP_ROWS - VIEWPORT_H
!tvy_store:
    sta zp_view_y
    rts

!dungeon_bounds:
    lda zp_player_x
    sec
    sbc #VIEWPORT_W / 2
    bcs !vx_not_neg+
    lda #0
    beq !vx_store+
!vx_not_neg:
    cmp #MAP_COLS - VIEWPORT_W
    bcc !vx_store+
    lda #MAP_COLS - VIEWPORT_W
!vx_store:
    sta zp_view_x

    lda zp_player_y
    sec
    sbc #VIEWPORT_H / 2
    bcs !vy_not_neg+
    lda #0
    beq !vy_store+
!vy_not_neg:
    cmp #MAP_ROWS - VIEWPORT_H
    bcc !vy_store+
    lda #MAP_ROWS - VIEWPORT_H
!vy_store:
    sta zp_view_y
    rts

// ============================================================
// render_viewport — Draw the 38x19 viewport to SCREEN_RAM
// ============================================================
render_viewport:
    // Cache player viewport-relative X = zp_player_x - zp_view_x
    lda zp_player_x
    sec
    sbc zp_view_x
    sta rv_player_vx

    // Cache whether any warding glyph is active
    lda glyph_active
    ora glyph_active + 1
    ora glyph_active + 2
    ora glyph_active + 3
    sta rv_row_has_glyph

    lda #0
    sta zp_render_y

!row_loop:
    // Compute map row = view_y + render_y
    lda zp_view_y
    clc
    adc zp_render_y
    sta rv_map_y
    tax

    // Hoist per-row player row check and |dy| = |map_y - zp_player_y|
    ldy #0
    cmp zp_player_y
    bne !not_prow+
    iny
!not_prow:
    sty rv_player_row

    sec
    sbc zp_player_y
    bcs !dy_pos+
    eor #$ff
    clc
    adc #1
!dy_pos:
    sta rv_row_dy

    // 16-bit pointer addition: zp_map_ptr = map_row[x] + zp_view_x
    lda map_row_lo,x
    clc
    adc zp_view_x
    sta zp_map_ptr_lo
    lda map_row_hi,x
    adc #0
    sta zp_map_ptr_hi

    // Screen row pointer = screen_row[render_y + VIEWPORT_Y]
    lda zp_render_y
    clc
    adc #VIEWPORT_Y
    tax
    lda screen_row_lo,x
    sta zp_screen_lo
    lda screen_row_hi,x
    sta zp_screen_hi

    // Clear viewport border columns (0 and 39)
    ldy #0
    lda #SC_SPACE
    sta (zp_screen_lo),y
    ldy #39
    sta (zp_screen_lo),y

    // Advance zp_screen_lo/hi by VIEWPORT_X (1) so Y = zp_render_x indexes directly
    inc zp_screen_lo
    bne !scr_ptr_ok+
    inc zp_screen_hi
!scr_ptr_ok:

    ldy #0
    sty zp_render_x

!col_loop:
    lda (zp_map_ptr_lo),y
    sta zp_tile_tmp

    and #FLAG_VISITED
    bne !rv_visited+

    // Unvisited: only a live visible/detected monster may render
    lda #SC_SPACE
    sta zp_temp0
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    bne !occ+
    jmp rv_apply_player_override
!occ:
    jmp !rv_live_monster+

!rv_visited:
    lda zp_tile_tmp
    lsr
    lsr
    lsr
    lsr
    tax

    // Wall types 1-6 without FLAG_LIT = corridor rock -> '#'
    cpx #7
    bcs !rv_normal+
    cpx #1
    bcc !rv_normal+
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rv_normal+
    lda #$23
    sta zp_temp0
    bne !rv_tile_set+
!rv_normal:
    lda tile_screen_codes,x
    sta zp_temp0

!rv_tile_set:
    // Store door number override (town only, open door tiles only)
    lda zp_player_dlvl
    bne !rv_no_store+
    cpx #7
    bne !rv_no_store+
    tya
    clc
    adc zp_view_x
    sta rsd_col
    ldx #0
!rv_store_chk:
    lda store_door_x,x
    cmp rsd_col
    bne !rv_store_nxt+
    lda store_door_y,x
    cmp rv_map_y
    bne !rv_store_nxt+
    txa
    clc
    adc #$31
    sta zp_temp0
    bne !rv_no_store+
!rv_store_nxt:
    inx
    cpx #STORE_COUNT
    bne !rv_store_chk-
!rv_no_store:

    // LOS check: if not FLAG_LIT, compare Chebyshev distance against zp_light_radius
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rv_vis_ok+

    // |dx| = |zp_render_x - rv_player_vx|
    lda zp_render_x
    sec
    sbc rv_player_vx
    bcs !rv_dx_pos+
    eor #$ff
    clc
    adc #1
!rv_dx_pos:
    cmp rv_row_dy
    bcs !rv_use_dx+
    lda rv_row_dy
!rv_use_dx:
    cmp zp_light_radius
    beq !rv_vis_ok+
    bcc !rv_vis_ok+

    // Remembered out-of-LOS tile: hide floor '.' ($2E) as blank space ($20)
    lda zp_temp0
    cmp #$2e
    bne !rv_no_glyph+
    lda #SC_SPACE
    sta zp_temp0
    jmp !rv_no_glyph+

!rv_vis_ok:
    // Item check (visible tiles only)
    lda zp_tile_tmp
    and #FLAG_HAS_ITEM
    beq !rv_no_item+
    lda zp_render_x
    clc
    adc zp_view_x
    ldy rv_map_y
    jsr floor_item_find_at
    bcc !rv_no_item+
    lda fi_item_id,x
    tax
    jsr item_get_display_char
    sta zp_temp0
!rv_no_item:
    lda rv_row_has_glyph
    beq !rv_no_glyph+
    lda zp_render_x
    clc
    adc zp_view_x
    ldy rv_map_y
    jsr glyph_find_at
    bcc !rv_no_glyph+
    lda #SC_GLYPH
    sta zp_temp0
!rv_no_glyph:

!rv_live_monster:
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq !rv_no_monster+
    lda zp_render_x
    clc
    adc zp_view_x
    ldy rv_map_y
    jsr monster_find_at
    bcc !rv_no_monster+
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #(MF_VISIBLE | MF_DETECTED)
    beq !rv_no_monster+
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda cr_display,x
    sta zp_temp0

!rv_no_monster:
rv_apply_player_override:
    ldy zp_render_x
    lda rv_player_row
    beq !write_tile+
    cpy rv_player_vx
    bne !write_tile+
    lda #(SC_PLAYER | $80)  // Inverse-video '@'
    sta zp_temp0

!write_tile:
    lda zp_temp0
    sta (zp_screen_lo),y
    iny
    sty zp_render_x
    cpy #VIEWPORT_W
    beq !col_done+
    jmp !col_loop-
!col_done:
    inc zp_render_y
    lda zp_render_y
    cmp #VIEWPORT_H
    beq !done+
    jmp !row_loop-
!done:
    lda #0
    sta vis_room_revealed
    rts

rsd_col:          .byte 0
rv_map_y:         .byte 0
rv_player_vx:     .byte 0
rv_player_row:    .byte 0
rv_row_dy:        .byte 0
rv_row_has_glyph: .byte 0

// ============================================================
// render_single_tile — Render one tile at map coordinates (zp_temp0, zp_temp1)
// ============================================================
// Preserves: zp_temp0, zp_temp1, zp_ptr0
render_single_tile:
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha

    // Compute screen row
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

    // Compute screen column offset
    lda zp_temp0
    sec
    sbc zp_view_x
    clc
    adc #VIEWPORT_X
    sta rst_col_tmp

    // Read map byte at (map_x, map_y)
    ldx zp_temp1
    lda map_row_lo,x
    sta zp_map_ptr_lo
    lda map_row_hi,x
    sta zp_map_ptr_hi
    ldy zp_temp0
    lda (zp_map_ptr_lo),y
    sta zp_tile_tmp

    and #FLAG_VISITED
    bne !rst_visited+
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    bne !rst_detect_occ+
    jmp !rst_blank+
!rst_detect_occ:
    lda #SC_SPACE
    sta zp_temp3
    jmp !rst_unvisited_detected+

!rst_visited:
    lda zp_tile_tmp
    lsr
    lsr
    lsr
    lsr
    tax

    cpx #7
    bcs !rst_normal+
    cpx #1
    bcc !rst_normal+
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rst_normal+
    lda #$23
    sta zp_temp3
    bne !rst_tile_set+
!rst_normal:
    lda tile_screen_codes,x
    sta zp_temp3
!rst_tile_set:

    lda zp_player_dlvl
    bne !rst_no_store+
    cpx #7
    bne !rst_no_store+
    ldx #0
!rst_store_chk:
    lda store_door_x,x
    cmp zp_temp0
    bne !rst_store_nxt+
    lda store_door_y,x
    cmp zp_temp1
    bne !rst_store_nxt+
    txa
    clc
    adc #$31
    sta zp_temp3
    bne !rst_no_store+
!rst_store_nxt:
    inx
    cpx #STORE_COUNT
    bne !rst_store_chk-
!rst_no_store:

    // LOS dimming check
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rst_vis_ok+

    lda zp_temp0
    sec
    sbc zp_player_x
    bcs !rst_dx_pos+
    eor #$ff
    clc
    adc #1
!rst_dx_pos:
    sta rst_dim_tmp

    lda zp_temp1
    sec
    sbc zp_player_y
    bcs !rst_dy_pos+
    eor #$ff
    clc
    adc #1
!rst_dy_pos:
    cmp rst_dim_tmp
    bcs !rst_use_dy+
    lda rst_dim_tmp
!rst_use_dy:
    cmp zp_light_radius
    beq !rst_vis_ok+
    bcc !rst_vis_ok+

    // Remembered out-of-LOS tile: hide floor '.' ($2E) as blank space ($20)
    lda zp_temp3
    cmp #$2e
    bne !rst_no_glyph+
    lda #SC_SPACE
    sta zp_temp3
    jmp !rst_no_glyph+

!rst_vis_ok:
    lda zp_tile_tmp
    and #FLAG_HAS_ITEM
    beq !rst_no_item+
    ldy zp_temp1
    lda zp_temp0
    jsr floor_item_find_at
    bcc !rst_no_item+
    lda fi_item_id,x
    tax
    jsr item_get_display_char
    sta zp_temp3
!rst_no_item:
    ldy zp_temp1
    lda zp_temp0
    jsr glyph_find_at
    bcc !rst_no_glyph+
    lda #SC_GLYPH
    sta zp_temp3
!rst_no_glyph:

!rst_unvisited_detected:
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq !rst_no_monster+
    ldy zp_temp1
    lda zp_temp0
    jsr monster_find_at
    bcc !rst_no_monster+
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #(MF_VISIBLE | MF_DETECTED)
    beq !rst_no_monster+
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda cr_display,x
    sta zp_temp3

!rst_no_monster:
rst_apply_player_override:
    lda zp_temp0
    cmp zp_player_x
    bne !rst_write+
    lda zp_temp1
    cmp zp_player_y
    bne !rst_write+
    lda #(SC_PLAYER | $80)
    sta zp_temp3
    jmp !rst_write+

!rst_blank:
    lda #SC_SPACE
    sta zp_temp3
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq rst_apply_player_override
    bne !rst_unvisited_detected-

!rst_write:
    ldy rst_col_tmp
    lda zp_temp3
    sta (zp_screen_lo),y
    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    rts

rst_col_tmp:  .byte 0
rst_dim_tmp:  .byte 0
old_view_x:   .byte 0
old_view_y:   .byte 0
old_player_x: .byte 0
old_player_y: .byte 0

// ============================================================
// render_local_area — Render tiles around old and new player positions
// ============================================================
render_local_area:
    lda old_player_x
    cmp zp_player_x
    bcc !rla_ox+
    lda zp_player_x
!rla_ox:
    sec
    sbc zp_light_radius
    bcs !rla_mx1+
    lda #0
    beq !rla_mx2+
!rla_mx1:
    sec
    sbc #1
    bcs !rla_mx2+
    lda #0
!rla_mx2:
    cmp zp_view_x
    bcs !rla_mx3+
    lda zp_view_x
!rla_mx3:
    sta rla_min_x

    lda old_player_x
    cmp zp_player_x
    bcs !rla_ox2+
    lda zp_player_x
!rla_ox2:
    clc
    adc zp_light_radius
    clc
    adc #1
    sta rla_max_x
    lda zp_view_x
    clc
    adc #VIEWPORT_W - 1
    cmp rla_max_x
    bcs !rla_mx4+
    sta rla_max_x
!rla_mx4:
    lda rla_max_x
    cmp #MAP_COLS
    bcc !rla_mx5+
    lda #MAP_COLS - 1
    sta rla_max_x
!rla_mx5:

    lda old_player_y
    cmp zp_player_y
    bcc !rla_oy+
    lda zp_player_y
!rla_oy:
    sec
    sbc zp_light_radius
    bcs !rla_my1+
    lda #0
    beq !rla_my2+
!rla_my1:
    sec
    sbc #1
    bcs !rla_my2+
    lda #0
!rla_my2:
    cmp zp_view_y
    bcs !rla_my3+
    lda zp_view_y
!rla_my3:
    sta rla_min_y

    lda old_player_y
    cmp zp_player_y
    bcs !rla_oy2+
    lda zp_player_y
!rla_oy2:
    clc
    adc zp_light_radius
    clc
    adc #1
    sta rla_max_y
    lda zp_view_y
    clc
    adc #VIEWPORT_H - 1
    cmp rla_max_y
    bcs !rla_my4+
    sta rla_max_y
!rla_my4:
    lda rla_max_y
    cmp #MAP_ROWS
    bcc !rla_my5+
    lda #MAP_ROWS - 1
    sta rla_max_y
!rla_my5:

    lda rla_min_y
    sta rla_cur_y
!rla_row:
    lda rla_min_x
    sta rla_cur_x
!rla_col:
    lda rla_cur_x
    sta zp_temp0
    lda rla_cur_y
    sta zp_temp1
    jsr render_single_tile

    lda rla_cur_x
    cmp rla_max_x
    beq !rla_col_done+
    inc rla_cur_x
    bne !rla_col-
!rla_col_done:
    lda rla_cur_y
    cmp rla_max_y
    beq !rla_done+
    inc rla_cur_y
    bne !rla_row-
!rla_done:
    rts

rla_min_x: .byte 0
rla_max_x: .byte 0
rla_min_y: .byte 0
rla_max_y: .byte 0
rla_cur_x: .byte 0
rla_cur_y: .byte 0

.assert "Viewport width", VIEWPORT_W, 38
.assert "Viewport height", VIEWPORT_H, 19
