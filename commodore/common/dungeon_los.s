// dungeon_los.s — Line of sight / visibility
//
// Three-state tile visibility:
//   Unseen:    no FLAG_VISITED → renders as blank (black)
//   Visible:   FLAG_VISITED AND (FLAG_LIT OR within light_radius) → full color
//   Remembered: FLAG_VISITED but not FLAG_LIT and outside light_radius → dimmed
//
// update_visibility is called each turn:
//   Phase A: Torch radius — mark nearby tiles FLAG_VISITED
//   Phase B: Room reveal — if player is in a lit room, reveal entire room

// ============================================================
// Data
// ============================================================
vis_room_revealed: .byte 0    // Set to 1 if a room was batch-revealed this turn

// Scratch for update_visibility
vis_min_x: .byte 0
vis_max_x: .byte 0
vis_min_y: .byte 0
vis_max_y: .byte 0

// ============================================================
// Subroutines
// ============================================================

// town_light_all — Mark all town tiles as lit + visited
// No-op: town_generate already sets LIT+VISITED flags on all tiles.
// Preserves: A, X, Y
town_light_all:
    rts

// update_visibility — Mark tiles around player as visited
// Called every player turn (movement, search, rest, etc.)
// Town level: no-op (town is fully visible).
// Dungeon: Phase A (torch radius) + Phase B (room reveal).
// Preserves: nothing
update_visibility:
    // Blindness — skip all visibility updates
    lda zp_eff_blind
    beq !uv_not_blind+
    jmp !uv_blind_skip+
!uv_not_blind:

    lda zp_player_dlvl
    bne !uv_dungeon+
    rts                         // Town: everything pre-lit

!uv_dungeon:
    lda #0
    sta vis_room_revealed

    // === Phase A: Torch radius ===
    // Mark all tiles within Chebyshev distance of zp_light_radius as VISITED.
    // Compute bounding box clamped to map edges.

    // vis_min_x = max(0, player_x - radius)
    lda zp_player_x
    sec
    sbc zp_light_radius
    bcs !uv_minx_ok+
    lda #0                      // Underflow → clamp to 0
!uv_minx_ok:
    sta vis_min_x

    // vis_max_x = min(MAP_COLS-1, player_x + radius)
    lda zp_player_x
    clc
    adc zp_light_radius
    cmp #MAP_COLS
    bcc !uv_maxx_ok+
    lda #MAP_COLS - 1
!uv_maxx_ok:
    sta vis_max_x

    // vis_min_y = max(0, player_y - radius)
    lda zp_player_y
    sec
    sbc zp_light_radius
    bcs !uv_miny_ok+
    lda #0
!uv_miny_ok:
    sta vis_min_y

    // vis_max_y = min(MAP_ROWS-1, player_y + radius)
    lda zp_player_y
    clc
    adc zp_light_radius
    cmp #MAP_ROWS
    bcc !uv_maxy_ok+
    lda #MAP_ROWS - 1
!uv_maxy_ok:
    sta vis_max_y

    // Iterate rows vis_min_y..vis_max_y
    ldx vis_min_y
!uv_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    ldy vis_min_x
.if (C128) { :Bank1Write() }
!uv_col:
    lda (zp_ptr0),y
    ora #FLAG_VISITED
    sta (zp_ptr0),y
    cpy vis_max_x
    beq !uv_col_done+
    iny
    jmp !uv_col-
!uv_col_done:
.if (C128) { :Bank0Restore() }

    // Also mark adjacent walls (1 tile beyond torch in each direction)
    // This ensures corridor walls are visible when standing next to them.
    // Already handled: torch radius marks the walls within range.

    cpx vis_max_y
    beq !uv_torch_done+
    inx
    jmp !uv_row-
!uv_torch_done:

    // === Phase B: Room reveal ===
    // Check if player is inside any lit room (expanded bounds include walls).
    lda #0
    sta vis_min_x               // Reuse as room loop index

!uv_room_loop:
    ldx vis_min_x
    cpx room_count
    bcs !uv_done+

    // Skip dark rooms (no batch reveal)
    lda room_lit,x
    beq !uv_next_room+

    // Check player within expanded room bounds:
    // x: [room_x-1, room_x+room_w]  y: [room_y-1, room_y+room_h]

    // Check left bound: player_x >= room_x[i] - 1
    lda room_x,x
    sec
    sbc #1
    cmp zp_player_x
    beq !uv_x_ok+               // Equal is within
    bcs !uv_next_room+          // room_x-1 > player_x → outside
!uv_x_ok:

    // Check right bound: player_x <= room_x[i] + room_w[i]
    lda room_x,x
    clc
    adc room_w,x
    cmp zp_player_x
    bcc !uv_next_room+          // room_x+w < player_x → outside

    // Check top bound: player_y >= room_y[i] - 1
    lda room_y,x
    sec
    sbc #1
    cmp zp_player_y
    beq !uv_y_ok+
    bcs !uv_next_room+
!uv_y_ok:

    // Check bottom bound: player_y <= room_y[i] + room_h[i]
    lda room_y,x
    clc
    adc room_h,x
    cmp zp_player_y
    bcc !uv_next_room+

    // Player is inside this lit room — reveal it
    jsr reveal_room
    lda #1
    sta vis_room_revealed
    jmp !uv_done+               // Only one room at a time

!uv_next_room:
    inc vis_min_x
    jmp !uv_room_loop-

!uv_blind_skip:
!uv_done:
    rts

// reveal_room — Set FLAG_VISITED on all tiles in room X (including walls)
// Input: X = room index
// Iterates room_x-1..room_x+room_w, room_y-1..room_y+room_h
// Preserves: nothing
reveal_room:
    // Compute bounds
    lda room_y,x
    sec
    sbc #1
    sta vis_min_y               // Top wall row
    lda room_y,x
    clc
    adc room_h,x
    sta vis_max_y               // Bottom wall row

    lda room_x,x
    sec
    sbc #1
    sta vis_min_x               // Left wall col (reusing for bounds now)
    lda room_x,x
    clc
    adc room_w,x
    sta vis_max_x               // Right wall col

    ldx vis_min_y
!rr_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    ldy vis_min_x
.if (C128) { :Bank1Write() }
!rr_col:
    lda (zp_ptr0),y
    ora #FLAG_VISITED
    sta (zp_ptr0),y
    cpy vis_max_x
    beq !rr_col_done+
    iny
    jmp !rr_col-
!rr_col_done:
.if (C128) { :Bank0Restore() }

    cpx vis_max_y
    beq !rr_done+
    inx
    jmp !rr_row-
!rr_done:
    rts

// los_is_visible — Check if a map position is currently visible to the player
// Input: X = map x, Y = map y
// Output: carry set = visible, carry clear = not visible
// Checks: FLAG_LIT on tile OR within light_radius Chebyshev distance
// Preserves: X, Y
los_is_visible:
    // Read tile
    tya
    pha                         // Save map y
    txa
    pha                         // Save map x

    // Get map pointer for row Y
    lda map_row_lo,y
    sta zp_ptr1
    lda map_row_hi,y
    sta zp_ptr1_hi

    // Read tile at (X, Y)
    txa
    tay
.if (C128) { :Bank1Read() }
    lda (zp_ptr1),y
.if (C128) { :Bank0Restore() }

    // Check FLAG_LIT
    and #FLAG_LIT
    bne !lov_yes+               // Lit tiles always visible

    // Check Chebyshev distance: max(|dx|, |dy|) <= light_radius
    pla                         // Restore map x
    tax
    pla                         // Restore map y
    tay

    // dx = abs(map_x - player_x)
    txa
    sec
    sbc zp_player_x
    bcs !lov_dx_pos+
    eor #$ff
    clc
    adc #1
!lov_dx_pos:
    sta zp_los_dx               // |dx|

    // dy = abs(map_y - player_y)
    tya
    sec
    sbc zp_player_y
    bcs !lov_dy_pos+
    eor #$ff
    clc
    adc #1
!lov_dy_pos:
    // A = |dy|, compare with |dx| to find max
    cmp zp_los_dx
    bcs !lov_use_dy+
    lda zp_los_dx               // dx is larger
!lov_use_dy:
    // A = max(|dx|, |dy|) = Chebyshev distance
    cmp zp_light_radius
    beq !lov_within+
    bcs !lov_no+                // distance > radius
!lov_within:
    sec                         // Within radius → visible
    rts
!lov_no:
    clc                         // Outside radius → not visible
    rts

!lov_yes:
    pla                         // Discard saved x
    pla                         // Discard saved y
    sec
    rts
