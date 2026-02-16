// dungeon_render.s — Viewport rendering
//
// Reads the map at $C000 and draws a 38x20 viewport to screen RAM.
// The viewport is centered on the player position, clamped to map edges.
// Screen layout: viewport at rows 1-20, columns 1-38.

// ============================================================
// Subroutines
// ============================================================

// viewport_update — Center viewport on player, clamp to map edges
// Updates zp_view_x, zp_view_y
// Preserves: nothing
viewport_update:
    // view_x = player_x - VIEWPORT_W/2, clamped to [0, MAP_COLS - VIEWPORT_W]
    lda zp_player_x
    sec
    sbc #VIEWPORT_W / 2     // 19
    bcs !vx_not_neg+
    lda #0                  // Underflow, clamp to 0
    jmp !vx_store+
!vx_not_neg:
    cmp #MAP_COLS - VIEWPORT_W  // 42
    bcc !vx_store+
    lda #MAP_COLS - VIEWPORT_W
!vx_store:
    sta zp_view_x

    // view_y = player_y - VIEWPORT_H/2, clamped to [0, MAP_ROWS - VIEWPORT_H]
    lda zp_player_y
    sec
    sbc #VIEWPORT_H / 2     // 10
    bcs !vy_not_neg+
    lda #0
    jmp !vy_store+
!vy_not_neg:
    cmp #MAP_ROWS - VIEWPORT_H  // 28
    bcc !vy_store+
    lda #MAP_ROWS - VIEWPORT_H
!vy_store:
    sta zp_view_y
    rts

// render_viewport — Draw the 38x20 viewport to screen
// Reads map data and writes screen codes + colors.
// Preserves: nothing
render_viewport:
    lda #0
    sta zp_render_y         // Screen row counter (0-19)

!row_loop:
    // Compute map row = view_y + render_y
    lda zp_view_y
    clc
    adc zp_render_y
    tax                     // X = map row

    // Get map row address
    lda map_row_lo,x
    sta zp_map_ptr_lo
    lda map_row_hi,x
    sta zp_map_ptr_hi

    // Get screen row address (render_y + 1 for viewport offset)
    lda zp_render_y
    clc
    adc #VIEWPORT_Y         // +1
    tax
    lda screen_row_lo,x
    sta zp_screen_lo
    lda screen_row_hi,x
    sta zp_screen_hi
    lda color_row_lo,x
    sta zp_color_lo
    lda color_row_hi,x
    sta zp_color_hi

    // Inner loop: 38 columns
    lda #0
    sta zp_render_x         // Screen column counter (0-37)

!col_loop:
    // Compute map column = view_x + render_x
    lda zp_view_x
    clc
    adc zp_render_x
    tay                     // Y = map column offset

    // Read map byte
    lda (zp_map_ptr_lo),y
    sta zp_tile_tmp

    // Check if visited (bit 2)
    and #FLAG_VISITED
    bne !rv_visited+

    // Not visited — check if detect monsters reveals an occupant
    lda eff_detect_timer
    bne !rv_detect_chk+
    jmp !draw_blank+
!rv_detect_chk:
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    bne !rv_detect_render+
    jmp !draw_blank+
!rv_detect_render:
    // Detected monster on unvisited tile — blank background, then monster
    lda #$20                    // Space (blank tile)
    sta zp_temp0
    lda #0                      // Black background
    sta zp_temp1
    jmp !rv_no_item+            // Skip to monster check
!rv_visited:

    // Extract tile type (bits 7-4 → index 0-15)
    lda zp_tile_tmp
    lsr
    lsr
    lsr
    lsr
    tax                     // X = tile type index

    // Wall types 1-6 without FLAG_LIT = corridor rock → render as '#'
    // Room walls have FLAG_LIT from DUNGEON_FLAGS; corridor rock does not.
    cpx #7
    bcs !rv_normal+         // Type >= 7, not a wall
    cpx #1
    bcc !rv_normal+         // Type 0 = floor, not a wall
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rv_normal+         // Lit = room wall, use box-drawing
    // Corridor rock
    lda #$23                // '#' screen code
    sta zp_temp0
    lda #COL_LGREY
    sta zp_temp1
    jmp !rv_tile_set+
!rv_normal:
    // Look up screen code and color
    lda tile_screen_codes,x
    sta zp_temp0            // screen code
    lda tile_colors,x
    sta zp_temp1            // color

    // Secret door orientation fix: TILE_SECRET defaults to '─' but
    // should render as '│' when on a vertical wall (left/right of room).
    // Check tile above AND below for WALL_V/corner (types 2-6).
    // Excludes type 1 (TILE_WALL_H / uncarved rock) to avoid false
    // positives on horizontal walls where rock sits above or below.
    // Checks both directions because a corridor may carve one neighbor.
    cpx #15                     // TILE_SECRET type index
    bne !rv_tile_set+
    // Peek at tile above (map_ptr - MAP_COLS, same column)
    lda zp_map_ptr_lo
    sec
    sbc #MAP_COLS
    sta zp_ptr2
    lda zp_map_ptr_hi
    sbc #0
    sta zp_ptr2_hi
    lda (zp_ptr2),y             // Tile above, same column (Y preserved)
    lsr
    lsr
    lsr
    lsr                         // Extract type index
    // Types 2-6 = WALL_V / corner tiles (not WALL_H / rock)
    cmp #2
    bcc !rv_check_below+        // Type 0-1 → check below too
    cmp #7
    bcs !rv_check_below+        // Type >= 7 → check below too
    // Tile above is WALL_V or corner → vertical wall → render as '│'
    lda #$5d                    // '│' screen code
    sta zp_temp0
    jmp !rv_tile_set+
!rv_check_below:
    // Peek at tile below (map_ptr + MAP_COLS, same column)
    lda zp_map_ptr_lo
    clc
    adc #MAP_COLS
    sta zp_ptr2
    lda zp_map_ptr_hi
    adc #0
    sta zp_ptr2_hi
    lda (zp_ptr2),y             // Tile below, same column (Y preserved)
    lsr
    lsr
    lsr
    lsr                         // Extract type index
    cmp #2
    bcc !rv_tile_set+           // Type 0-1 → horizontal, keep '─'
    cmp #7
    bcs !rv_tile_set+           // Type >= 7 → horizontal, keep '─'
    // Tile below is WALL_V or corner → vertical wall → render as '│'
    lda #$5d                    // '│' screen code
    sta zp_temp0
!rv_tile_set:

    // Store door number override (town only, open door tiles only)
    // Rendered as part of the tile so items/monsters/player take priority.
    lda zp_player_dlvl
    bne !rv_no_store+
    cpx #7                      // TILE_DOOR_OPEN type index
    bne !rv_no_store+
    lda zp_view_x
    clc
    adc zp_render_x
    sta rsd_col
    lda zp_view_y
    clc
    adc zp_render_y
    sta rsd_save_x
    ldx #0
!rv_store_chk:
    lda store_door_x,x
    cmp rsd_col
    bne !rv_store_nxt+
    lda store_door_y,x
    cmp rsd_save_x
    bne !rv_store_nxt+
    txa
    clc
    adc #$31                    // '1'-'6' screen code
    sta zp_temp0
    lda #COL_STORE
    sta zp_temp1
    jmp !rv_no_store+
!rv_store_nxt:
    inx
    cpx #STORE_COUNT
    bne !rv_store_chk-
!rv_no_store:

    // --- Dimming check: remembered but not currently visible → dark grey ---
    // Town tiles always have FLAG_LIT, so this is effectively a no-op on town.
    lda zp_tile_tmp
    and #FLAG_LIT
    bne !rv_vis_ok+             // FLAG_LIT → permanently visible → full color

    // Not lit — check if within torch radius (Chebyshev distance)
    // dx = abs(map_x - player_x)
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
    sta zp_temp2                // |dx| (safe — not used by tile lookup)

    // dy = abs(map_y - player_y)
    lda zp_view_y
    clc
    adc zp_render_y
    sec
    sbc zp_player_y
    bcs !rv_dy_pos+
    eor #$ff
    clc
    adc #1
!rv_dy_pos:
    // A = |dy|, find max(|dx|, |dy|)
    cmp zp_temp2
    bcs !rv_use_dy+
    lda zp_temp2
!rv_use_dy:
    // A = Chebyshev distance
    cmp zp_light_radius
    beq !rv_vis_ok+             // Exactly at radius → visible
    bcc !rv_vis_ok+             // Within radius → visible

    // Outside light radius → dimmed (remembered tile)
    lda #COL_DGREY
    sta zp_temp1                // Override color to dark grey
    jmp !rv_no_monster+         // Dimmed tiles never show monsters

!rv_vis_ok:
    // Item check (visible tiles only)
    lda zp_tile_tmp
    and #FLAG_HAS_ITEM
    beq !rv_no_item+
    // Compute map x,y for item lookup
    lda zp_view_x
    clc
    adc zp_render_x
    pha                         // Save map_x
    lda zp_view_y
    clc
    adc zp_render_y
    tay                         // Y = map_y
    pla                         // A = map_x
    jsr floor_item_find_at
    bcc !rv_no_item+
    // X = slot — look up item type
    lda fi_item_id,x
    tax
    lda it_display,x
    sta zp_temp0
    txa                             // A = item type ID
    jsr item_get_floor_color        // A = identification-aware color
    sta zp_temp1
!rv_no_item:

    // Monster check (visible tiles only — overrides items)
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq !rv_no_monster+
    // Compute map x,y
    lda zp_view_x
    clc
    adc zp_render_x
    sta rv_mon_x
    lda zp_view_y
    clc
    adc zp_render_y
    tay                         // Y = map_y
    lda rv_mon_x                // A = map_x
    jsr monster_find_at
    bcc !rv_no_monster+         // Not found (stale flag?)
    // X = slot index — get creature type
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax                         // X = creature type
    lda cr_display,x
    sta zp_temp0
    lda cr_color,x
    sta zp_temp1

!rv_no_monster:
    // Check if this is the player position
    lda zp_render_x
    clc
    adc zp_view_x
    cmp zp_player_x
    bne !not_player+
    lda zp_render_y
    clc
    adc zp_view_y
    cmp zp_player_y
    bne !not_player+

    // Override with player character
    lda #SC_PLAYER          // '@'
    sta zp_temp0
    lda #COL_PLAYER
    sta zp_temp1
    jmp !write_tile+

!not_player:
    jmp !write_tile+

!draw_blank:
    lda #SC_SPACE
    sta zp_temp0
    lda #COL_BLACK
    sta zp_temp1

!write_tile:
    // Screen column = render_x + VIEWPORT_X (1)
    ldy zp_render_x
    iny                     // +1 for viewport offset

    // Write screen code
    lda zp_temp0
    sta (zp_screen_lo),y
    // Write color
    lda zp_temp1
    sta (zp_color_lo),y

    // Next column
    inc zp_render_x
    lda zp_render_x
    cmp #VIEWPORT_W
    beq !col_done+
    jmp !col_loop-
!col_done:

    // Next row
    inc zp_render_y
    lda zp_render_y
    cmp #VIEWPORT_H
    beq !done+
    jmp !row_loop-
!done:
    rts

// Scratch bytes for store door check in render_viewport
rsd_col:    .byte 0
rsd_save_x: .byte 0

// render_single_tile — Render one tile at map coordinates
// Used by dirty rendering to update only changed tiles.
// Input: zp_temp0 = map_x, zp_temp1 = map_y
// Preserves: zp_temp0, zp_temp1
render_single_tile:
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
    lda color_row_lo,x
    sta zp_color_lo
    lda color_row_hi,x
    sta zp_color_hi

    // Compute and save screen column offset
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

    // Check visited flag
    and #FLAG_VISITED
    bne !rst_visited+
    jmp !rst_blank+
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
    lda #COL_LGREY
    sta zp_temp4
    jmp !rst_tile_set+
!rst_normal:
    lda tile_screen_codes,x
    sta zp_temp3
    lda tile_colors,x
    sta zp_temp4
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
    adc #$31                    // '1'-'6' screen code
    sta zp_temp3
    lda #COL_STORE
    sta zp_temp4
    jmp !rst_no_store+
!rst_store_nxt:
    inx
    cpx #STORE_COUNT
    bne !rst_store_chk-
!rst_no_store:

    // --- Dimming check for single tile ---
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
    sta rst_dim_tmp         // Stash |dx| (byte after rst_col_tmp; safe scratch)

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

    // Dimmed
    lda #COL_DGREY
    sta zp_temp4
    jmp !rst_no_monster+        // Dimmed tiles never show monsters

!rst_vis_ok:
    // Item check (visible tiles only)
    lda zp_tile_tmp
    and #FLAG_HAS_ITEM
    beq !rst_no_item+
    ldy zp_temp1                // Y = map_y
    lda zp_temp0                // A = map_x
    jsr floor_item_find_at
    bcc !rst_no_item+
    // X = slot — look up item type
    lda fi_item_id,x
    tax
    lda it_display,x
    sta zp_temp3
    txa                             // A = item type ID
    jsr item_get_floor_color        // A = identification-aware color
    sta zp_temp4
!rst_no_item:

    // Monster check (visible tiles only — overrides items)
    lda zp_tile_tmp
    and #FLAG_OCCUPIED
    beq !rst_no_monster+
    // zp_temp0 = map_x, zp_temp1 = map_y
    ldy zp_temp1                // Y = map_y
    lda zp_temp0                // A = map_x
    jsr monster_find_at
    bcc !rst_no_monster+        // Not found
    // X = slot index
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda cr_display,x
    sta zp_temp3
    lda cr_color,x
    sta zp_temp4

!rst_no_monster:
    // Player position override?
    lda zp_temp0
    cmp zp_player_x
    bne !rst_write+
    lda zp_temp1
    cmp zp_player_y
    bne !rst_write+
    lda #SC_PLAYER
    sta zp_temp3
    lda #COL_PLAYER
    sta zp_temp4
    jmp !rst_write+

!rst_blank:
    lda #SC_SPACE
    sta zp_temp3
    lda #COL_BLACK
    sta zp_temp4

!rst_write:
    ldy rst_col_tmp
    lda zp_temp3
    sta (zp_screen_lo),y
    lda zp_temp4
    sta (zp_color_lo),y
    rts

rst_col_tmp: .byte 0
rst_dim_tmp: .byte 0          // Scratch for dimming distance calc
rv_mon_x:    .byte 0          // Monster check scratch

// Saved positions for dirty render detection
old_view_x:    .byte 0
old_view_y:    .byte 0
old_player_x:  .byte 0
old_player_y:  .byte 0

// render_local_area — Render tiles around old and new player positions
// Computes bounding box encompassing light_radius+1 around both positions,
// clamped to viewport. Calls render_single_tile for each.
// Uses old_player_x/y and zp_player_x/y.
// Preserves: nothing
render_local_area:
    // Compute min_x = min(old_player_x, player_x) - light_radius - 1
    lda old_player_x
    cmp zp_player_x
    bcc !rla_ox+
    lda zp_player_x
!rla_ox:
    sec
    sbc zp_light_radius
    bcs !rla_mx1+
    lda #0
    jmp !rla_mx2+
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

    // Compute max_x = max(old_player_x, player_x) + light_radius + 1
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

    // Compute min_y = min(old_player_y, player_y) - light_radius - 1
    lda old_player_y
    cmp zp_player_y
    bcc !rla_oy+
    lda zp_player_y
!rla_oy:
    sec
    sbc zp_light_radius
    bcs !rla_my1+
    lda #0
    jmp !rla_my2+
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

    // Compute max_y = max(old_player_y, player_y) + light_radius + 1
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
    jmp !rla_col-
!rla_col_done:

    lda rla_cur_y
    cmp rla_max_y
    beq !rla_done+
    inc rla_cur_y
    jmp !rla_row-
!rla_done:
    rts

rla_min_x: .byte 0
rla_max_x: .byte 0
rla_min_y: .byte 0
rla_max_y: .byte 0
rla_cur_x: .byte 0
rla_cur_y: .byte 0

// ============================================================
// Compile-time validation
// ============================================================
.assert "Viewport width", VIEWPORT_W, 38
.assert "Viewport height", VIEWPORT_H, 20
