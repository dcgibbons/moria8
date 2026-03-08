// dungeon_render_vdc.s — VDC viewport rendering (C128 80-column)
//
// Reads the map and draws a 78x19 viewport via VDC register writes.
// The viewport is centered on the player position, clamped to map edges.
// Screen layout: viewport at rows 2-20, columns 1-78.
//
// Row-batch VDC writes: for each viewport row, screen codes are streamed
// via VDC auto-increment, then attribute bytes are buffered and streamed
// in a second pass. This minimizes VDC address-set overhead.

// ============================================================
// Subroutines
// ============================================================

// Scroll deadband: viewport only recenters when player nears edges.
// This avoids full-redraw-on-every-step behavior on the VDC path.
.const VIEW_SCROLL_MARGIN_X = 12
.const VIEW_SCROLL_MARGIN_Y = 4

// viewport_update — Center viewport on player, clamp to map edges
// Updates zp_view_x, zp_view_y
// Preserves: nothing
viewport_update:
    // Horizontal deadband:
    // keep player in [view_x+M, view_x+VIEWPORT_W-1-M]
    lda zp_view_x
    clc
    adc #VIEW_SCROLL_MARGIN_X
    cmp zp_player_x
    bcc !vx_check_right+
    beq !vx_check_right+
    // Player crossed left deadband edge.
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
    bcs !vy_update+             // Inside deadband.

    // Player crossed right deadband edge.
    lda zp_player_x
    sec
    sbc #VIEWPORT_W - 1 - VIEW_SCROLL_MARGIN_X
    cmp #MAP_COLS - VIEWPORT_W
    bcc !vx_store_right+
    lda #MAP_COLS - VIEWPORT_W
!vx_store_right:
    sta zp_view_x

!vy_update:
    // Vertical deadband:
    // keep player in [view_y+M, view_y+VIEWPORT_H-1-M]
    lda zp_view_y
    clc
    adc #VIEW_SCROLL_MARGIN_Y
    cmp zp_player_y
    bcc !vy_check_bottom+
    beq !vy_check_bottom+
    // Player crossed top deadband edge.
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
    bcs !vy_done+               // Inside deadband.

    // Player crossed bottom deadband edge.
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

// render_viewport — Draw the 78x19 viewport to VDC screen
// For each row: stream screen codes via VDC auto-increment,
// buffer translated colors, then stream attributes.
// Preserves: nothing
render_viewport:
    // Defensive: keep VDC attribute mode/default colors stable even if
    // external ROM paths touched VDC mode registers.
    jsr c128_vdc_reassert_mode

    lda #0
    sta zp_render_y         // Screen row counter (0-18)

!row_loop:
    // Compute map row = view_y + render_y
    lda zp_view_y
    clc
    adc zp_render_y
    tax                     // X = map row

    // Pre-compute |dy| = abs(map_y - player_y) for this row (Opt 4: per-row dimming early-exit)
    txa                     // A = map_y
    sec
    sbc zp_player_y
    bcs !rv_row_dy_pos+
    eor #$ff
    clc
    adc #1
!rv_row_dy_pos:
    sta rv_row_dy           // rv_row_dy = abs(map_y - player_y) for this row

    // Get map row address, pre-slid by view_x (Opt 3: col_loop uses ldy zp_render_x directly)
    lda map_row_lo,x
    clc
    adc zp_view_x           // Pre-add view_x: ptr = row_base + view_x
    sta rv_row_ptr_lo
    lda map_row_hi,x
    adc #0
    sta rv_row_ptr_hi

    // Get VDC screen/attribute row addresses
    lda zp_render_y
    clc
    adc #VIEWPORT_Y         // +2
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
    // Read map byte. Restore row pointer each column because monster/item
    // helpers may clobber zp_ptr0 as a generic scratch pointer.
    lda rv_row_ptr_lo
    sta zp_ptr0
    lda rv_row_ptr_hi
    sta zp_ptr0_hi
    ldy zp_render_x
    :MapRead_ptr0_y()
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
    lda #VDC_BLACK              // Pre-translated VDC black (Opt 2)
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
    lda #VDC_LGREY          // Pre-translated VDC color (Opt 2)
    sta zp_temp1
    jmp !rv_tile_set+
!rv_normal:
    // Look up screen code and translate VIC color via canonical table path.
    lda tile_screen_codes,x
    sta zp_temp0
    stx rv_tile_type
    lda tile_colors,x
    tax
    lda vic_to_vdc_color,x
    sta zp_temp1
    ldx rv_tile_type
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
    lda #VDC_YELLOW             // Pre-translated VDC color (Opt 2)
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

    // Not lit — use pre-computed rv_row_dy for row-level early exit (Opt 4)
    lda rv_row_dy
    cmp zp_light_radius
    beq !rv_check_dx+           // |dy| == radius: still need |dx| check
    bcc !rv_check_dx+           // |dy| < radius: still need |dx| check
    // |dy| > light_radius: entire tile guaranteed outside torch range
    lda #VDC_DGREY              // Pre-translated VDC dark grey (Opt 2)
    sta zp_temp1
    jmp !rv_no_monster+         // Dimmed tiles never show monsters

!rv_check_dx:
    // |dy| <= light_radius: check |dx| = abs(map_x - player_x)
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
    // A = |dx|; find max(|dx|, rv_row_dy) = Chebyshev distance
    cmp rv_row_dy
    bcs !rv_use_dx+             // |dx| >= |dy|: A already holds max
    lda rv_row_dy               // |dy| > |dx|: use pre-computed |dy|
!rv_use_dx:
    cmp zp_light_radius
    beq !rv_vis_ok+             // Exactly at radius → visible
    bcc !rv_vis_ok+             // Within radius → visible

    // Outside light radius → dimmed (remembered tile)
    lda #VDC_DGREY              // Pre-translated VDC dark grey (Opt 2)
    sta zp_temp1
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
    jsr item_get_floor_color        // A = VIC color (identification-aware)
    tax
    lda vic_to_vdc_color,x          // Translate to VDC RGBI (Opt 2: inline)
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
    lda cr_color,x              // VIC color
    tax
    lda vic_to_vdc_color,x      // Translate to VDC RGBI (Opt 2: inline)
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
    lda #VDC_WHITE          // Pre-translated VDC white (Opt 2: COL_PLAYER = COL_WHITE)
    sta zp_temp1
    jmp !write_tile+

!not_player:
    jmp !write_tile+

!draw_blank:
    lda #SC_SPACE
    sta zp_temp0
    lda #VDC_BLACK          // Pre-translated VDC black (Opt 2)
    sta zp_temp1

!write_tile:
    // Buffer screen code and pre-translated VDC color (all paths set zp_temp1 to VDC-native)
    ldx zp_render_x
    lda zp_temp0
    sta row_char_buf,x
    lda zp_temp1            // Already VDC RGBI (Opt 2: translation moved to each color path)
    sta row_attr_buf,x

    // Next column
    inc zp_render_x
    lda zp_render_x
    cmp #VIEWPORT_W
    beq !col_done+
    jmp !col_loop-
!col_done:

    // Stream char + attr rows to VDC atomically (sei per row = minimal IRQ window)
    // Opt 1: reg 31 selected once per pass; vdc_wait inlined as bit/bpl sharing the loop target.
    // Trick: both bpl (VDC busy → repoll) and bne (next byte) branch to the same !stream: label
    // (the bit instruction). This eliminates jsr vdc_wait overhead (~9 cycles) per byte,
    // saving ~13K cycles/refresh, while keeping code size compact (18 bytes per pass).
    sei

    // Char row: set VDC address, select reg 31 once, then blast 38 bytes
    lda zp_screen_lo
    clc
    adc #VIEWPORT_X
    tay
    lda zp_screen_hi
    adc #0
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg      // Wait + select reg 31 + wait (once per row)
    ldy #0
!char_stream:
    bit VDC_ADDR_REG        // Poll VDC ready (bit 7 → N flag)
    bpl !char_stream-       // N=0 (busy) → repoll; N=1 (ready) → fall through
    lda row_char_buf,y
    sta VDC_DATA_REG
    iny
    cpy #VIEWPORT_W
    bne !char_stream-       // Loop back to bit — also acts as wait for next byte

    // Attr row: same pattern
    lda zp_color_lo
    clc
    adc #VIEWPORT_X
    tay
    lda zp_color_hi
    adc #0
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg
    ldy #0
!attr_stream:
    bit VDC_ADDR_REG
    bpl !attr_stream-
    lda row_attr_buf,y
    sta VDC_DATA_REG
    iny
    cpy #VIEWPORT_W
    bne !attr_stream-

    cli

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

// Row char/attribute buffers — filled during col_loop, streamed to VDC after
row_char_buf: .fill VIEWPORT_W, 0
row_attr_buf: .fill VIEWPORT_W, 0

// Pre-translated VDC attribute bytes for standard tile types (indexed by tile type 0-15).
// Values are VDC RGBI + Set1 flag ($80), matching vic_to_vdc_color[tile_colors[i]].
// Eliminates the runtime vic_to_vdc_color lookup for the common (non-overridden) tile path.
tile_vdc_colors:
    .byte VDC_DGREY     // 0: Floor
    .byte VDC_LGREY     // 1: Wall (horizontal)
    .byte VDC_LGREY     // 2: Wall (vertical)
    .byte VDC_LGREY     // 3: Wall (corner TL)
    .byte VDC_LGREY     // 4: Wall (corner TR)
    .byte VDC_LGREY     // 5: Wall (corner BL)
    .byte VDC_LGREY     // 6: Wall (corner BR)
    .byte VDC_BROWN     // 7: Door (open)
    .byte VDC_BROWN     // 8: Door (closed)
    .byte VDC_WHITE     // 9: Stairs down
    .byte VDC_WHITE     // 10: Stairs up
    .byte VDC_GREY      // 11: Rubble
    .byte VDC_RED       // 12: Magma stream
    .byte VDC_WHITE     // 13: Quartz vein
    .byte VDC_RED       // 14: Trap (visible)
    .byte VDC_LGREY     // 15: Secret door

// render_single_tile — Render one tile at map coordinates via VDC
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
    stx rst_row_tmp             // Save screen row for VDC addressing
    lda screen_row_lo,x
    sta zp_screen_lo
    lda screen_row_hi,x
    sta zp_screen_hi
    lda color_row_lo,x
    sta zp_color_lo
    lda color_row_hi,x
    sta zp_color_hi

    // Compute and save absolute screen column (viewport-relative + VIEWPORT_X)
    lda zp_temp0
    sec
    sbc zp_view_x
    clc
    adc #VIEWPORT_X
    sta rst_col_tmp

    // Read map byte at (map_x, map_y)
    ldx zp_temp1
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_temp0
    :MapRead_ptr0_y()
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
    lda #VDC_LGREY          // Pre-translated VDC color (Opt 2)
    sta zp_temp4
    jmp !rst_tile_set+
!rst_normal:
    lda tile_screen_codes,x
    sta zp_temp3
    stx rv_tile_type
    lda tile_colors,x
    tax
    lda vic_to_vdc_color,x
    sta zp_temp4
    ldx rv_tile_type
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
    lda #VDC_YELLOW             // Pre-translated VDC color (Opt 2)
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
    sta rst_dim_tmp

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
    lda #VDC_DGREY              // Pre-translated VDC dark grey (Opt 2)
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
    jsr item_get_floor_color        // A = VIC color (identification-aware)
    tax
    lda vic_to_vdc_color,x          // Translate to VDC RGBI (Opt 2: inline)
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
    lda cr_color,x              // VIC color
    tax
    lda vic_to_vdc_color,x      // Translate to VDC RGBI (Opt 2: inline)
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
    lda #VDC_WHITE              // Pre-translated (Opt 2: COL_PLAYER = COL_WHITE)
    sta zp_temp4
    jmp !rst_write+

!rst_blank:
    lda #SC_SPACE
    sta zp_temp3
    lda #VDC_BLACK              // Pre-translated VDC black (Opt 2)
    sta zp_temp4

!rst_write:
    sei                         // IRQ off: protect char + attr VDC writes as atomic pair

    // Set VDC address to screen position and write char
    lda zp_screen_lo
    clc
    adc rst_col_tmp
    tay
    lda zp_screen_hi
    adc #0
    jsr vdc_set_update_addr
    lda zp_temp3
    jsr vdc_write_data

    // Set VDC address to attribute position and write pre-translated VDC color
    lda zp_color_lo
    clc
    adc rst_col_tmp
    tay
    lda zp_color_hi
    adc #0
    jsr vdc_set_update_addr
    lda zp_temp4                // Already VDC RGBI (Opt 2: translation moved to each color path)
    jsr vdc_write_data
    cli                         // IRQ on: char + attr written consistently
    rts

rst_col_tmp: .byte 0
rst_row_tmp: .byte 0
rst_dim_tmp: .byte 0          // Scratch for dimming distance calc
rv_mon_x:    .byte 0          // Monster check scratch
rv_row_dy:   .byte 0          // Pre-computed |dy| for current row (Opt 4)
rv_row_ptr_lo: .byte 0        // Stable map-row pointer (view_x applied)
rv_row_ptr_hi: .byte 0
rv_tile_type: .byte 0         // Preserve tile type index across color translation

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
.assert "Viewport width", VIEWPORT_W, 78
.assert "Viewport height", VIEWPORT_H, 19
