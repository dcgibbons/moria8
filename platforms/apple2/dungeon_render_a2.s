#importonce
// dungeon_render_a2.s — Apple IIe 80-column dungeon viewport renderer
//
// Draws the 78x18 viewport at screen (1,2) from the AUX-resident 198x66
// map. One map cell = one text cell. Semantics mirror the C64 oracle
// (platforms/commodore/c64/dungeon_render.s); viewport scrolling uses the
// C128 deadband policy (platforms/commodore/c128/dungeon_render_vdc.s),
// which suits the 78-wide viewport. 1-tile single-axis scrolls shift the
// text page in place (dungeon_scroll_a2.s); everything else falls back to
// full redraw / render_local_area.
//
// Colorless policy: tile_colors, item_get_floor_color, cr_color and the
// dim-to-COL_DGREY override have no display effect and are dropped. The
// remembered-vs-visible GLYPH semantics are preserved exactly: the c64 only
// dims the color of remembered tiles (same glyph), so glyphs are identical
// here; the Chebyshev light-radius computation is KEPT because on the c64 it
// also gates the item and glyph overlays (dimmed tiles skip both but still
// run the monster overlay).
//
// Performance design (80STORE interleave):
//   - The 78-byte map row slice is block-read from AUX into a main-RAM row
//     buffer once per row (two soft-switch toggles per row instead of two
//     per cell); the per-cell read is ldy zp_render_x + lda rv_row_map_buf,y.
//   - Per-cell warding-glyph scan is gated by a per-row "any glyph active"
//     check (glyph_find_at runs only when a glyph exists somewhere).
//   - Per-row |dy| precomputed for the dimming early-exit (C128 Opt 4).
//   - Per viewport row, display bytes are staged into two 40-byte main-RAM
//     buffers (aux half = even screen columns 0/2/../78, main half = odd
//     columns 1/3/../79), then burst-written with exactly two soft-switch
//     toggles per row: sta A2_PAGE2_ON, 40-byte copy, sta A2_PAGE2_OFF,
//     40-byte copy. No per-cell toggling.
//   - Border columns 0 and 79 are permanent spaces baked into the staging
//     buffers (aux index 0, main index 39; cell writes never touch them),
//     replacing the c64's per-row border clear. 40-byte half-row writes can
//     never reach the firmware screen holes at $x78-$x7F.
//   - C64 screen codes are translated through a 128-byte table (staged
//     from A2AuxData into the a2_ss_buf tail once per redraw, P6); codes
//     >= $80 fall back to the a2_map_char branch chain.

// ============================================================
// Constants / staging
// ============================================================

// Scroll deadband: viewport only recenters when the player nears an edge
// (C128 policy, margins fit the 78x18 viewport).
.const VIEW_SCROLL_MARGIN_X = 12
.const VIEW_SCROLL_MARGIN_Y = 4

.const SC_SPACE = $20               // C64 screen-code space (a2_char_map[$20] = A2_SPACE)

// Row staging buffers: one full 40-byte text half-row each.
// rv_aux_buf[i]  -> aux half index i  = screen column 2*i   (even columns)
// rv_main_buf[i] -> main half index i = screen column 2*i+1 (odd columns)
// Cell i (0-77) maps to screen column i+1: even i -> rv_main_buf[i>>1],
// odd i -> rv_aux_buf[(i>>1)+1]. Indices 0 (aux) and 39 (main) are the
// viewport border columns and stay A2_SPACE forever.
rv_aux_buf:  .fill A2_HALF_ROW, A2_SPACE
rv_main_buf: .fill A2_HALF_ROW, A2_SPACE

// Block-read copy of the current 78-byte map row slice (one AUX block
// read per row replaces one per-cell thunked read). Shares the
// save-stream buffer: save/load streams, title staging, and gameplay
// viewport rendering are never live concurrently (same argument as
// a2_title_stage, storage_mli.s), and the row slice is refilled from AUX
// at the top of every row.
.label rv_row_map_buf = a2_ss_buf
// Staged copy of a2_char_map_aux (A2AuxData) for the current redraw (P6):
// offsets 80-207 of a2_ss_buf, clear of the 78-byte row slice at offset 0.
// The buffer's aliasing contract (save streams, title staging, and aux
// string staging never run mid-render) keeps it intact between refills.
.label rv_char_map = a2_ss_buf + 80
// Nonzero when any warding glyph exists; gates the per-cell glyph scan.
rv_row_has_glyph: .byte 0

// ============================================================
// viewport_update — Recenter viewport on player with scroll deadband
// Keeps the player inside [view+margin, view+size-1-margin]; clamps to map
// edges. Mirrors dungeon_render_vdc.s (town needs no special-casing: the
// 66x22 town fits the deadband at view 0). Updates zp_view_x, zp_view_y.
// Preserves: nothing
// ============================================================
viewport_update:
    // Horizontal deadband
    lda zp_view_x
    clc
    adc #VIEW_SCROLL_MARGIN_X
    cmp zp_player_x
    bcc !vx_check_right+
    beq !vx_check_right+
    // Player crossed left deadband edge
    lda zp_player_x
    sec
    sbc #VIEW_SCROLL_MARGIN_X
    bcs !vx_store_left+
    lda #0
!vx_store_left:
    sta zp_view_x
    jmp !vy_update+

!vx_check_right:
    lda zp_view_x
    clc
    adc #VIEWPORT_W - 1 - VIEW_SCROLL_MARGIN_X
    cmp zp_player_x
    bcs !vy_update+             // Inside deadband

    // Player crossed right deadband edge
    lda zp_player_x
    sec
    sbc #VIEWPORT_W - 1 - VIEW_SCROLL_MARGIN_X
    cmp #MAP_COLS - VIEWPORT_W
    bcc !vx_store_right+
    lda #MAP_COLS - VIEWPORT_W
!vx_store_right:
    sta zp_view_x

!vy_update:
    // Vertical deadband
    lda zp_view_y
    clc
    adc #VIEW_SCROLL_MARGIN_Y
    cmp zp_player_y
    bcc !vy_check_bottom+
    beq !vy_check_bottom+
    // Player crossed top deadband edge
    lda zp_player_y
    sec
    sbc #VIEW_SCROLL_MARGIN_Y
    bcs !vy_store_top+
    lda #0
!vy_store_top:
    sta zp_view_y
    rts

!vy_check_bottom:
    lda zp_view_y
    clc
    adc #VIEWPORT_H - 1 - VIEW_SCROLL_MARGIN_Y
    cmp zp_player_y
    bcs !vy_done+               // Inside deadband

    // Player crossed bottom deadband edge
    lda zp_player_y
    sec
    sbc #VIEWPORT_H - 1 - VIEW_SCROLL_MARGIN_Y
    cmp #MAP_ROWS - VIEWPORT_H
    bcc !vy_store_bottom+
    lda #MAP_ROWS - VIEWPORT_H
!vy_store_bottom:
    sta zp_view_y
!vy_done:
    rts

// rv_map_char_staged — Screen code X → Apple display code A via the staged
// char-map table (P6). Codes >= $80 (reverse video; never produced by
// viewport glyph sources) tail into the a2_map_char branch chain, which
// also serves all non-viewport callers. Preserves X, Y.
rv_map_char_staged:
    cpx #$80
    beq !tbl+
    jmp a2_map_char
!tbl:
    lda rv_char_map,x
    rts

// ============================================================
// render_viewport — Draw the 78x18 viewport
// Per row: stage both text half-rows, then burst-write aux + main with two
// soft-switch toggles. Preserves: nothing
// ============================================================
render_viewport:
    // The player is guaranteed inside the viewport; cache the
    // viewport-relative X once so the hot path only compares columns.
    lda zp_player_x
    sec
    sbc zp_view_x
    sta rv_player_vx

    // Stage the char-map table into main RAM for this redraw (P6): one
    // 128-byte AUX block read replaces the per-cell branch chain.
    lda #<a2_char_map_aux
    sta zp_ptr0
    lda #>a2_char_map_aux
    sta zp_ptr0_hi
    lda #<rv_char_map
    sta zp_ptr1
    lda #>rv_char_map
    sta zp_ptr1_hi
    ldy #0
    ldx #$80
    jsr mmu_safe_map_read_block

    lda #0
    sta zp_render_y         // Viewport row counter (0-18)

!row_loop:
    // Map row = view_y + render_y
    lda zp_view_y
    clc
    adc zp_render_y
    sta rv_row_map_y
    tax                     // X = map row

    // Pre-compute |dy| = abs(map_y - player_y) for this row
    txa
    sec
    sbc zp_player_y
    bcs !rv_row_dy_pos+
    eor #$ff
    clc
    adc #1
!rv_row_dy_pos:
    sta rv_row_dy

    // Block-read the 78-byte map row slice from AUX into main RAM: two
    // soft-switch toggles per row instead of two per cell. zp_ptr0/zp_ptr1
    // are scratch after this; the cell path reads rv_row_map_buf only.
    lda map_row_lo,x
    clc
    adc zp_view_x
    sta zp_ptr0
    lda map_row_hi,x
    adc #0
    sta zp_ptr0_hi
    lda #<rv_row_map_buf
    sta zp_ptr1
    lda #>rv_row_map_buf
    sta zp_ptr1_hi
    ldy #0
    ldx #VIEWPORT_W
    jsr mmu_safe_map_read_block

    // Cache whether any warding glyph exists (per row); the per-cell
    // glyph_find_at scan is skipped entirely when none are placed.
    lda glyph_active
    ora glyph_active+1
    ora glyph_active+2
    ora glyph_active+3
    sta rv_row_has_glyph

    // Screen row base (render_y + VIEWPORT_Y)
    lda zp_render_y
    clc
    adc #VIEWPORT_Y
    tax
    lda a2_row_lo,x
    sta zp_screen_lo
    lda a2_row_hi,x
    sta zp_screen_hi

    // Player-on-this-row flag for the cheap per-cell player check
    lda #0
    sta rv_player_row
    lda rv_row_map_y
    cmp zp_player_y
    bne !rv_player_row_done+
    inc rv_player_row
!rv_player_row_done:

    lda #0
    sta zp_render_x         // Viewport column counter (0-77)

!col_loop:
    // Map byte for this cell (row slice block-read into main RAM per row)
    ldy zp_render_x
    lda rv_row_map_buf,y
    sta zp_tile_tmp

    // Check if visited (bit 2)
    and #FLAG_VISITED
    bne !rv_visited+

    // Not visited — only a live visible/detected monster may render.
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq !rv_detect_blank+
    lda #SC_SPACE
    sta zp_temp0
    jmp !rv_live_monster+
!rv_detect_blank:
    jmp !draw_blank+
!rv_visited:

    // Extract tile type (bits 7-4 → index 0-15)
    lda zp_tile_tmp
    lsr
    lsr
    lsr
    lsr
    tax                     // X = tile type index

    // Wall types 1-6 without FLAG_LIT = corridor rock → '#'
    cpx #7
    bcs !rv_normal+         // Type >= 7, not a wall
    cpx #1
    bcc !rv_normal+         // Type 0 = floor, not a wall
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rv_normal+         // Lit = room wall, use table glyph
    lda #$23                // '#' screen code
    sta zp_temp0
    bne !rv_tile_set+
!rv_normal:
    lda tile_screen_codes,x
    sta zp_temp0
!rv_tile_set:

    // Store door number override (town only, open door tiles only).
    // Rendered as part of the tile so items/monsters/player take priority.
    lda zp_player_dlvl
    bne !rv_no_store+
    cpx #7                      // TILE_DOOR_OPEN type index
    bne !rv_no_store+
    lda zp_view_x
    clc
    adc zp_render_x
    sta rv_col_tmp              // map_x
    ldx #0
!rv_store_chk:
    lda store_door_x,x
    cmp rv_col_tmp
    bne !rv_store_nxt+
    lda store_door_y,x
    cmp rv_row_map_y
    bne !rv_store_nxt+
    txa
    clc
    adc #$31                    // '1'-'8' screen code
    sta zp_temp0
    bne !rv_no_store+
!rv_store_nxt:
    inx
    cpx #STORE_COUNT
    bne !rv_store_chk-
!rv_no_store:

    // --- Visibility gate: remembered but not currently visible ---
    // Colorless: no dim color exists, but this check still gates the item
    // and glyph overlays exactly as on the c64.
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rv_vis_ok+

    // Not lit — row-level early exit via pre-computed |dy|
    lda rv_row_dy
    cmp zp_light_radius
    beq !rv_check_dx+           // |dy| == radius: still need |dx|
    bcc !rv_check_dx+           // |dy| < radius: still need |dx|
    jmp !rv_dimmed+             // |dy| > radius: guaranteed outside light

!rv_check_dx:
    // |dx| = abs(view_x + render_x - player_x)
    lda zp_view_x
    clc
    adc zp_render_x
    sec
    sbc zp_player_x
    bcs !rv_dx_pos+
    eor #$ff
    clc
    adc #1
!rv_dx_pos:
    // A = |dx|; Chebyshev = max(|dx|, |dy|)
    cmp rv_row_dy
    bcs !rv_use_dx+
    lda rv_row_dy
!rv_use_dx:
    cmp zp_light_radius
    beq !rv_vis_ok+             // Exactly at radius → visible
    bcc !rv_vis_ok+             // Within radius → visible

!rv_dimmed:
    // Remembered tile outside light: terrain glyph only; skip item and
    // glyph overlays (c64 branches to the same post-glyph point), but the
    // shared monster overlay still runs.
    jmp !rv_no_glyph+

!rv_vis_ok:
    // Item check (visible tiles only)
    lda zp_tile_tmp
    and #FLAG_HAS_ITEM
    beq !rv_no_item+
    lda zp_view_x
    clc
    adc zp_render_x
    ldy rv_row_map_y
    jsr floor_item_find_at      // A = map_x, Y = map_y
    bcc !rv_no_item+
    // X = slot — look up item display glyph (color dropped: colorless)
    lda fi_item_id,x
    tax
    lda it_display,x
    sta zp_temp0
!rv_no_item:
    lda rv_row_has_glyph
    beq !rv_no_glyph+
    lda zp_view_x
    clc
    adc zp_render_x
    ldy rv_row_map_y
    jsr glyph_find_at           // A = map_x, Y = map_y
    bcc !rv_no_glyph+
    lda #SC_GLYPH
    sta zp_temp0
!rv_no_glyph:

!rv_live_monster:
    // Monster check — overrides items/glyphs
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq !rv_no_monster+
    lda zp_view_x
    clc
    adc zp_render_x
    ldy rv_row_map_y
    jsr monster_find_at         // A = map_x, Y = map_y
    bcc !rv_no_monster+         // Not found (stale flag?)
    // X = slot index — get creature type
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #(MF_VISIBLE | MF_DETECTED)
    beq !rv_no_monster+
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax                         // X = creature type
    lda cr_display,x
    sta zp_temp0                // cr_color dropped: colorless

!rv_no_monster:
rv_apply_player_override:
    // Player position override (cheap: row flag + cached column)
    lda rv_player_row
    beq !write_tile+
    lda zp_render_x
    cmp rv_player_vx
    bne !write_tile+
    lda #SC_PLAYER              // '@'
    sta zp_temp0
    jmp !write_tile+            // SC_PLAYER is $00; BNE would fall through

!draw_blank:
    lda #SC_SPACE
    sta zp_temp0
    jmp rv_apply_player_override

!write_tile:
    // Translate screen code → Apple display code and stage into the
    // correct half-row buffer. Cell i: even i → main (odd screen column),
    // odd i → aux (even screen column); half index = i>>1. The parity
    // branch runs before the call: rv_map_char_staged preserves X and Y,
    // so no php/plp shuffle is needed.
    ldx zp_temp0
    lda zp_render_x
    lsr                         // A = half index, C = column parity
    tay
    bcs !stage_aux+
    jsr rv_map_char_staged
    sta rv_main_buf,y           // even i → screen col 2*(i>>1)+1 (main)
    jmp !next_col+
!stage_aux:
    jsr rv_map_char_staged
    sta rv_aux_buf + 1,y        // odd i → screen col 2*((i>>1)+1) (aux)
!next_col:

    inc zp_render_x
    lda zp_render_x
    cmp #VIEWPORT_W
    beq !col_done+
    jmp !col_loop-
!col_done:

    // Burst-write the staged half-rows: two soft-switch toggles per row.
    sta A2_PAGE2_ON             // aux text half (even screen columns)
    ldy #A2_HALF_ROW - 1
!aux_wr:
    lda rv_aux_buf,y
    sta (zp_screen_lo),y
    dey
    bpl !aux_wr-
    sta A2_PAGE2_OFF            // main text half (odd screen columns)
    ldy #A2_HALF_ROW - 1
!main_wr:
    lda rv_main_buf,y
    sta (zp_screen_lo),y
    dey
    bpl !main_wr-

    // Next row
    inc zp_render_y
    lda zp_render_y
    cmp #VIEWPORT_H
    beq !done+
    jmp !row_loop-
!done:
    lda #0
    sta vis_room_revealed       // c64 contract: full render consumes reveal
    rts

// scene_render_mat_tile — mat's immediate tile render (P5). Falls through
// into render_single_tile; render_single_tile preserves zp_ptr0 for its
// callers in the monster-AI loop.
scene_render_mat_tile:
    inc mat_scene_dirty
// ============================================================
// render_single_tile — Render one tile at map coordinates
// Used by dirty rendering to update only changed tiles.
// Input: zp_temp0 = map_x, zp_temp1 = map_y
// Preserves: zp_temp0, zp_temp1
// ============================================================
render_single_tile:
    // Preserve zp_ptr0 across the lookup calls below (monster_find_at and
    // friends iterate through monster_get_ptr, clobbering it). Callers in
    // the monster-AI loop depend on that pointer surviving.
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha
    // Screen row base
    lda zp_temp1
    sec
    sbc zp_view_y
    clc
    adc #VIEWPORT_Y
    tax
    lda a2_row_lo,x
    sta zp_screen_lo
    lda a2_row_hi,x
    sta zp_screen_hi

    // Absolute screen column
    lda zp_temp0
    sec
    sbc zp_view_x
    clc
    adc #VIEWPORT_X
    sta rst_col_tmp

    // Read map byte at (map_x, map_y) from AUX. zp_ptr0 is safe here: the
    // single read happens before any monster call clobbers it.
    ldx zp_temp1
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_temp0
    jsr mmu_safe_map_read_ptr0
    sta zp_tile_tmp

    // Check visited flag
    and #FLAG_VISITED
    bne !rst_visited+
    // Not visited — only a live visible/detected monster may render.
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    bne !rst_detect_occ+
    jmp !rst_blank+
!rst_detect_occ:
    lda #SC_SPACE
    sta zp_temp3
    jmp !rst_monster+
!rst_visited:

    // Extract tile type (bits 7-4)
    lda zp_tile_tmp
    lsr
    lsr
    lsr
    lsr
    tax

    // Corridor rock check (same as render_viewport)
    cpx #7
    bcs !rst_normal+
    cpx #1
    bcc !rst_normal+
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rst_normal+
    lda #$23                // '#'
    sta zp_temp3
    bne !rst_tile_set+
!rst_normal:
    lda tile_screen_codes,x
    sta zp_temp3
!rst_tile_set:

    // Store door number override (town only, open door tiles only)
    lda zp_player_dlvl
    bne !rst_no_store+
    cpx #7                      // TILE_DOOR_OPEN type index
    bne !rst_no_store+
    ldx #0
!rst_store_chk:
    lda store_door_x,x
    cmp zp_temp0                // map_x
    bne !rst_store_nxt+
    lda store_door_y,x
    cmp zp_temp1                // map_y
    bne !rst_store_nxt+
    txa
    clc
    adc #$31                    // '1'-'8' screen code
    sta zp_temp3
    bne !rst_no_store+
!rst_store_nxt:
    inx
    cpx #STORE_COUNT
    bne !rst_store_chk-
!rst_no_store:

    // --- Visibility gate for single tile (colorless: overlay gating only) ---
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rst_vis_ok+

    // Chebyshev distance: max(|map_x - player_x|, |map_y - player_y|)
    lda zp_temp0                // map_x
    sec
    sbc zp_player_x
    bcs !rst_dx_pos+
    eor #$ff
    clc
    adc #1
!rst_dx_pos:
    sta rst_dim_tmp             // |dx|

    lda zp_temp1                // map_y
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

    // Outside light radius: remembered terrain only, skip item/glyph
    jmp !rst_monster+

!rst_vis_ok:
    // Item check (visible tiles only)
    lda zp_tile_tmp
    and #FLAG_HAS_ITEM
    beq !rst_no_item+
    ldy zp_temp1                // Y = map_y
    lda zp_temp0                // A = map_x
    jsr floor_item_find_at
    bcc !rst_no_item+
    lda fi_item_id,x
    tax
    lda it_display,x
    sta zp_temp3
!rst_no_item:
    ldy zp_temp1                // Y = map_y
    lda zp_temp0                // A = map_x
    jsr glyph_find_at
    bcc !rst_monster+
    lda #SC_GLYPH
    sta zp_temp3

!rst_monster:
    // Monster check — overrides items/glyphs
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq !rst_no_monster+
    ldy zp_temp1                // Y = map_y
    lda zp_temp0                // A = map_x
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
    // Player position override?
    lda zp_temp0
    cmp zp_player_x
    bne !rst_write+
    lda zp_temp1
    cmp zp_player_y
    bne !rst_write+
    lda #SC_PLAYER
    sta zp_temp3
    jmp !rst_write+             // SC_PLAYER is $00; BNE would fall through

!rst_blank:
    lda #SC_SPACE
    sta zp_temp3
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq rst_apply_player_override
    bne !rst_monster-

!rst_write:
    // Translate and write one cell (single-tile path; per-cell toggle via
    // the shared screen backend is acceptable outside the bulk renderer)
    ldx zp_temp3
    jsr a2_map_char
    ldx rst_col_tmp
    jsr a2_write_cell
    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    rts

// ============================================================
// Saved positions for dirty render detection (owned by game_loop)
// ============================================================
old_view_x:    .byte 0
old_view_y:    .byte 0
old_player_x:  .byte 0
old_player_y:  .byte 0

// ============================================================
// render_local_area — Render tiles around old and new player positions
// Computes bounding box encompassing light_radius+1 around both positions,
// clamped to viewport. Calls render_single_tile for each.
// Uses old_player_x/y and zp_player_x/y.
// Preserves: nothing
// ============================================================
render_local_area:
    // min_x = min(old_player_x, player_x) - light_radius - 1
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
    // Clamp to viewport left
    cmp zp_view_x
    bcs !rla_mx3+
    lda zp_view_x
!rla_mx3:
    sta rla_min_x

    // max_x = max(old_player_x, player_x) + light_radius + 1
    lda old_player_x
    cmp zp_player_x
    bcs !rla_ox2+
    lda zp_player_x
!rla_ox2:
    clc
    adc zp_light_radius
    clc
    adc #1
    // Clamp to viewport right
    sta rla_max_x
    lda zp_view_x
    clc
    adc #VIEWPORT_W - 1
    cmp rla_max_x
    bcs !rla_mx4+
    sta rla_max_x
!rla_mx4:
    // Clamp to map right
    lda rla_max_x
    cmp #MAP_COLS
    bcc !rla_mx5+
    lda #MAP_COLS - 1
    sta rla_max_x
!rla_mx5:

    // min_y = min(old_player_y, player_y) - light_radius - 1
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

    // max_y = max(old_player_y, player_y) + light_radius + 1
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

    // Iterate the bounding box and render each tile
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

// ============================================================
// Scratch state
// ============================================================
rv_row_map_y:  .byte 0          // Current map row (item/glyph/monster lookups)
rv_row_dy:     .byte 0          // Pre-computed |dy| for current row
rv_player_vx:  .byte 0          // Cached player viewport-relative X
rv_player_row: .byte 0          // Nonzero when current row contains the player
rv_col_tmp:    .byte 0          // map_x scratch for the store door check
rst_col_tmp:   .byte 0          // render_single_tile screen column
rst_dim_tmp:   .byte 0          // render_single_tile dimming distance scratch
rla_min_x:     .byte 0
rla_max_x:     .byte 0
rla_min_y:     .byte 0
rla_max_y:     .byte 0
rla_cur_x:     .byte 0
rla_cur_y:     .byte 0

// ============================================================
// Compile-time validation
// ============================================================
.assert "Viewport width", VIEWPORT_W, 78
.assert "Viewport height", VIEWPORT_H, 18
.assert "Half row is 40 bytes", A2_HALF_ROW, 40
.assert "Staging buffers sized to half row", rv_main_buf - rv_aux_buf, A2_HALF_ROW
.assert "Staged char map fits a2_ss_buf tail", rv_char_map + $80 <= a2_ss_buf + $100, true
