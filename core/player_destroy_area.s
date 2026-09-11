#importonce
// player_destroy_area.s — upstream Word of Destruction devastation engine
//
// Oracle: Umoria spellDestroyArea (src/spells.cpp:2254 + replaceSpot:2209),
// VMS Moria destroy_area (source/include/spells.inc:1878).
//
// Sweeps a y±15/x±15 box around the player. Every in-bounds, non-edge tile
// within upstream distance 16 is rewritten by typ roll: dist<13 →
// 1+rng_range(6), dist<16 → 1+rng_range(9); typ 1-3 floor, 4/7 WALL_H
// (granite stand-in), 5/8 MAGMA, 6/9 QUARTZ. The player tile is forced to
// floor (Umoria refinement over VMS). Monsters, floor items, glyphs, and
// traps within distance 16 are deleted outright — monsters silently via
// monster_remove (no XP, no winner flag, matching upstream delete_monster).
// Tile FLAG_LIT and room_lit[] for intersecting rooms are cleared
// (upstream perma_lit_room=false, room-granular in Moria8). Stairs are
// destroyed like any other tile; pmx_mark_stairs_at already tile-validates
// the stored stairs_* coords, so no sentinel handling is needed. In town
// (zp_player_dlvl == 0) only the message and blindness apply. Blindness is
// additive with an 8-bit 255 clamp (upstream += 10 + randint(10)).
//
// Placed per platform in an overlay with room (see platform main.s);
// callers reach it through resident tramp_eff_destroy_area or directly via
// PMX_DESTROY_AREA_TARGET in player_magic_utility.s.

da_cur_x:       .byte 0
da_cur_y:       .byte 0
da_rows_left:   .byte 0
da_cols_left:   .byte 0
da_typ:         .byte 0
da_dist:        .byte 0
da_saved_tile:  .byte 0
da_idx:         .byte 0
da_dx:          .byte 0
da_dy:          .byte 0
da_box_x0:      .byte 0
da_box_y0:      .byte 0
da_box_x1:      .byte 0
da_box_y1:      .byte 0

da_devastate:
    lda zp_player_dlvl
    beq !da_town+
    jsr da_delete_lists
    jsr da_sweep_tiles
    jsr da_darken_rooms
    jsr da_msg_blind
    lda #1
    sta vis_room_revealed
    sta turn_scene_dirty
    rts
!da_town:
    jmp da_msg_blind

// ------------------------------------------------------------
// da_calc_dist — upstream distance max(dx,dy) + min(dx,dy)/2
// Input: A = x, Y = y
// Output: A = distance
// Clobbers: A, Y, da_dx, da_dy. Preserves X, zp_ptr0.
// ------------------------------------------------------------
da_calc_dist:
    sec
    sbc zp_player_x
    bpl !dcd_dx_ok+
    eor #$ff
    clc
    adc #1
!dcd_dx_ok:
    sta da_dx
    tya
    sec
    sbc zp_player_y
    bpl !dcd_dy_ok+
    eor #$ff
    clc
    adc #1
!dcd_dy_ok:
    sta da_dy
    cmp da_dx
    bcc !dcd_dx_max+
    lda da_dx
    lsr
    clc
    adc da_dy
    rts
!dcd_dx_max:
    lda da_dy
    lsr
    clc
    adc da_dx
    rts

// ------------------------------------------------------------
// da_delete_lists — silently delete monsters, floor items, glyphs, and
// traps within upstream distance 16 of the player.
// ------------------------------------------------------------
da_delete_lists:
    // Monsters: monster_remove = upstream delete_monster (no XP/winner)
    lda #0
    sta da_idx
!dll_mon_loop:
    ldx da_idx
    cpx #MAX_MONSTERS
    bcs !dll_mon_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !dll_mon_next+
    ldy #MX_X
    lda (zp_ptr0),y
    sta da_typ
    ldy #MX_Y
    lda (zp_ptr0),y
    tay
    lda da_typ
    jsr da_calc_dist
    cmp #16
    bcs !dll_mon_next+
    ldx da_idx
    jsr monster_remove
!dll_mon_next:
    inc da_idx
    jmp !dll_mon_loop-
!dll_mon_done:

    // Floor items
    lda #0
    sta da_idx
!dll_item_loop:
    ldx da_idx
    cpx #MAX_FLOOR_ITEMS
    bcs !dll_item_done+
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !dll_item_next+
    lda fi_y,x
    tay
    lda fi_x,x
    jsr da_calc_dist
    cmp #16
    bcs !dll_item_next+
    ldx da_idx
    jsr floor_item_remove
!dll_item_next:
    inc da_idx
    jmp !dll_item_loop-
!dll_item_done:

    // Glyphs of warding (separate table, invisible to floor_item_find_at)
    lda #0
    sta da_idx
!dll_glyph_loop:
    ldx da_idx
    cpx #MAX_GLYPHS
    bcs !dll_glyph_done+
    lda glyph_active,x
    beq !dll_glyph_next+
    lda glyph_y,x
    tay
    lda glyph_x,x
    jsr da_calc_dist
    cmp #16
    bcs !dll_glyph_next+
    ldx da_idx
    lda #0
    sta glyph_active,x
!dll_glyph_next:
    inc da_idx
    jmp !dll_glyph_loop-
!dll_glyph_done:

    // Trap table, downward swap-remove; no player-tile exclusion
    // (upstream deletes the object under the player too)
    lda trap_count
    beq !dll_trap_done+
    sta da_idx
!dll_trap_loop:
    dec da_idx
    ldx da_idx
    lda trap_y,x
    tay
    lda trap_x,x
    jsr da_calc_dist
    cmp #16
    bcs !dll_trap_next+
    ldx da_idx
    jsr trap_remove_at_index
!dll_trap_next:
    lda da_idx
    bne !dll_trap_loop-
!dll_trap_done:
    rts

// ------------------------------------------------------------
// da_sweep_tiles — rewrite every in-radius, non-edge tile by typ roll.
// Row pointer is hoisted once per row. Tiles whose rewritten byte equals
// the old byte skip the map write; the RNG draw still happens for every
// replaced tile (upstream RNG order).
// ------------------------------------------------------------
da_sweep_tiles:
    lda zp_player_y
    sec
    sbc #15
    sta da_cur_y
    lda #31
    sta da_rows_left
!dst_row:
    lda da_cur_y
    cmp #MAP_ROWS
    bcc !dst_row_in+
    jmp !dst_row_next+
!dst_row_in:
    ldx da_cur_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    lda zp_player_x
    sec
    sbc #15
    sta da_cur_x
    lda #31
    sta da_cols_left
!dst_col:
    jsr dst_process_col
    inc da_cur_x
    dec da_cols_left
    bne !dst_col-
!dst_row_next:
    inc da_cur_y
    dec da_rows_left
    beq !dst_row_done+
    jmp !dst_row-
!dst_row_done:
    rts

// One sweep column at (da_cur_x, da_cur_y); row pointer is preset.
dst_process_col:
    lda da_cur_x
    cmp #MAP_COLS
    bcc !dpc_in_bounds+
    rts
!dpc_in_bounds:
    // Player tile: force floor, no RNG draw
    lda da_cur_x
    cmp zp_player_x
    bne !dpc_not_player+
    lda da_cur_y
    cmp zp_player_y
    bne !dpc_not_player+
    lda #TILE_FLOOR
    sta da_typ
    jmp !dpc_write+
!dpc_not_player:
    // Map-edge tiles are permanent (Moria8 boundary walls are
    // coordinate-based)
    lda da_cur_x
    beq !dpc_edge+
    cmp #MAP_COLS - 1
    beq !dpc_edge+
    lda da_cur_y
    beq !dpc_edge+
    cmp #MAP_ROWS - 1
    bne !dpc_not_edge+
!dpc_edge:
    rts
!dpc_not_edge:
    // Upstream distance gate: only dist < 16 is replaced
    lda da_cur_x
    ldy da_cur_y
    jsr da_calc_dist
    sta da_dist
    cmp #16
    bcc !dpc_in_range+
    rts
!dpc_in_range:
    lda da_dist
    cmp #13
    bcs !dpc_outer+
    lda #6
    bne !dpc_roll+
!dpc_outer:
    lda #9
!dpc_roll:
    jsr rng_range
    clc
    adc #1                  // typ 1..6 inner, 1..9 outer
    cmp #4
    bcs !dpc_wall+
    lda #TILE_FLOOR         // typ 1-3: corridor floor
    sta da_typ
    jmp !dpc_write+
!dpc_wall:
    // typ 4/7 → WALL_H, 5/8 → MAGMA, 6/9 → QUARTZ
    sec
    sbc #4
    cmp #3
    bcc !dpc_kind+
    sbc #3
!dpc_kind:
    tax
    lda da_wall_kinds,x
    sta da_typ
    jmp !dpc_write+
!dpc_write:
    ldy da_cur_x
    :MapRead_ptr0_y()
    sta da_saved_tile
    and #FLAG_VISITED       // keep VISITED; clear LIT/HAS_ITEM/OCCUPIED
    ora da_typ
    cmp da_saved_tile
    beq !dpc_done+
    :MapWrite_ptr0_y()
    // da_typ is never a door type, so any written door tile is destroyed;
    // purge unconditionally (the table scan early-outs cheaply when empty)
    lda da_cur_x
    ldy da_cur_y
    jsr door_state_clear_at
!dpc_done:
    rts

// ------------------------------------------------------------
// da_darken_rooms — clear room_lit[] for every room rectangle
// intersecting the blast box (upstream perma_lit_room=false, applied at
// Moria8's room granularity), and drop the lit-room cache.
// ------------------------------------------------------------
da_darken_rooms:
    // Clamp the blast box to the map
    lda zp_player_x
    sec
    sbc #15
    bcs !ddr_x0_ok+
    lda #0
!ddr_x0_ok:
    sta da_box_x0
    lda zp_player_x
    clc
    adc #15
    cmp #MAP_COLS - 1
    bcc !ddr_x1_ok+
    lda #MAP_COLS - 1
!ddr_x1_ok:
    sta da_box_x1
    lda zp_player_y
    sec
    sbc #15
    bcs !ddr_y0_ok+
    lda #0
!ddr_y0_ok:
    sta da_box_y0
    lda zp_player_y
    clc
    adc #15
    cmp #MAP_ROWS - 1
    bcc !ddr_y1_ok+
    lda #MAP_ROWS - 1
!ddr_y1_ok:
    sta da_box_y1

    lda #0
    sta da_idx
!ddr_loop:
    ldx da_idx
    cpx room_count
    bcs !ddr_done+
    lda room_x,x
    cmp da_box_x1
    beq !ddr_x_in+
    bcs !ddr_next+
!ddr_x_in:
    lda room_x,x
    clc
    adc room_w,x
    sec
    sbc #1                  // room right edge (room_w >= 1)
    cmp da_box_x0
    bcc !ddr_next+
    lda room_y,x
    cmp da_box_y1
    beq !ddr_y_in+
    bcs !ddr_next+
!ddr_y_in:
    lda room_y,x
    clc
    adc room_h,x
    sec
    sbc #1
    cmp da_box_y0
    bcc !ddr_next+
    lda #0
    sta room_lit,x
!ddr_next:
    inc da_idx
    jmp !ddr_loop-
!ddr_done:
    lda #$ff
    sta vis_cached_room_idx
    rts

// ------------------------------------------------------------
// da_msg_blind — "There is a searing blast of light!" and additive
// blindness 11..20 (upstream 10 + randint(10)), saturating at 255.
// Runs in town too.
// ------------------------------------------------------------
da_msg_blind:
    lda #<da_blast_msg
    sta zp_ptr0
    lda #>da_blast_msg
    sta zp_ptr0_hi
    jsr msg_print
    lda #10
    jsr rng_range
    clc
    adc #11                 // 11..20 = upstream 10 + randint(10)
    clc
    adc zp_eff_blind
    bcc !dmb_ok+
    lda #255
!dmb_ok:
    sta zp_eff_blind
    rts

da_blast_msg:
    .text "There is a searing blast of light!"
    .byte 0

da_wall_kinds:
    .byte TILE_WALL_H, TILE_MAGMA, TILE_QUARTZ
