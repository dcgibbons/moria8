#importonce
// dungeon_gen.s — Town and dungeon map generation (loaded as $E000 overlay)
//
// Populates the map at MAP_BASE..MAP_END (`MAP_COLS x MAP_ROWS`, 1 byte/tile).
// Each map byte: bits 7-4 = tile type (0-15), bits 3-0 = flags.
//
// Shared constants and data tables (map_row_lo/hi, room_count, stairs, etc.)
// are defined in dungeon_data.s (main segment) so they are always accessible.
// Only generation-private constants and scratch variables live here.

// ============================================================
// Private generation constants (not shared with other modules)
// ============================================================

// Store sizes (all 10 wide x 5 tall)
.const STORE_W = 10
.const STORE_H = 5

dg_progress_tick:
#if DUNGEON_GEN_BUSY
    jmp generation_busy_tick
#else
    rts
#endif

// ============================================================
// Bulk map helpers (overlay-local, centralized high-volume operations)
// ============================================================
// These are the approved bulk bypass paths for single-tile wrappers.
// They perform one bank enter/exit around the full map walk.

// Input: A = fill byte
// Clobbers: A, X, Y, zp_ptr0/zp_ptr0_hi
map_bulk_fill_all:
    sta map_bulk_fill_val
    ldx #0
!mbf_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
!mbf_col:
    lda map_bulk_fill_val
    :MapWrite_ptr0_y()
    iny
    cpy #MAP_COLS
    bne !mbf_col-
    inx
    cpx #MAP_ROWS
    bne !mbf_row-
    rts

// Input: A = AND mask applied to every map byte
// Clobbers: A, X, Y, zp_ptr0/zp_ptr0_hi
map_bulk_and_all:
    sta map_bulk_and_mask
    ldx #0
!mba_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
!mba_col:
    :MapRead_ptr0_y()
    and map_bulk_and_mask
    :MapWrite_ptr0_y()
    iny
    cpy #MAP_COLS
    bne !mba_col-
    inx
    cpx #MAP_ROWS
    bne !mba_row-
    rts

map_bulk_fill_val: .byte 0
map_bulk_and_mask: .byte 0

// ============================================================
// Subroutines
// ============================================================

// town_generate — Build the town level map
// Fills map at MAP_BASE with floor, outer walls, 6 stores, stairs.
// Sets player start position.
// Preserves: nothing
town_generate:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$73
    jsr c128_town_dump_mark
#endif
    // Clear trap table for safety (town has no traps)
    lda #0
    sta trap_count
    // --- Step 1: Fill entire map with floor + TOWN_FLAGS ---
    lda #TILE_FLOOR | TOWN_FLAGS    // $0C
    jsr map_bulk_fill_all

    // --- Step 2: Draw outer boundary walls ---
    // Top wall (row 0): horizontal walls with corners
    lda map_row_lo + 0
    sta zp_ptr0
    lda map_row_hi + 0
    sta zp_ptr0_hi
    // Top-left corner
    lda #TILE_CORNER_TL | TOWN_FLAGS
    ldy #0
    :MapWrite_ptr0_y()
    // Top-right corner
    lda #TILE_CORNER_TR | TOWN_FLAGS
    ldy #MAP_COLS - 1
    :MapWrite_ptr0_y()
    // Horizontal wall between corners
    lda #TILE_WALL_H | TOWN_FLAGS
    ldy #1
!top_wall:
    :MapWrite_ptr0_y()
    iny
    cpy #MAP_COLS - 1
    bne !top_wall-

    // Bottom wall (row 47): horizontal walls with corners
    lda map_row_lo + MAP_ROWS - 1
    sta zp_ptr0
    lda map_row_hi + MAP_ROWS - 1
    sta zp_ptr0_hi
    // Bottom-left corner
    lda #TILE_CORNER_BL | TOWN_FLAGS
    ldy #0
    :MapWrite_ptr0_y()
    // Bottom-right corner
    lda #TILE_CORNER_BR | TOWN_FLAGS
    ldy #MAP_COLS - 1
    :MapWrite_ptr0_y()
    // Horizontal wall between corners
    lda #TILE_WALL_H | TOWN_FLAGS
    ldy #1
!bot_wall:
    :MapWrite_ptr0_y()
    iny
    cpy #MAP_COLS - 1
    bne !bot_wall-

    // Left and right walls (rows 1 to 46)
    ldx #1              // Row index
!side_walls:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    // Left wall (col 0)
    lda #TILE_WALL_V | TOWN_FLAGS
    ldy #0
    :MapWrite_ptr0_y()
    // Right wall (col 79)
    ldy #MAP_COLS - 1
    :MapWrite_ptr0_y()
    inx
    cpx #MAP_ROWS - 1
    bne !side_walls-

    // --- Step 3: Place 6 store buildings ---
    ldx #0              // Store index
!store_loop:
    stx zp_temp0        // Save store index
    jsr draw_store
    ldx zp_temp0
    inx
    cpx #STORE_COUNT
    bne !store_loop-

    // --- Step 4: Place stairs down at (40, 24) ---
    lda map_row_lo + 24
    sta zp_ptr0
    lda map_row_hi + 24
    sta zp_ptr0_hi
    lda #TILE_STAIRS_DN | TOWN_FLAGS
    ldy #40
    :MapWrite_ptr0_y()

    // --- Step 5: Set player start at (39, 24) ---
    lda #39
    sta player_data + PL_MAP_X
    sta zp_player_x
    lda #24
    sta player_data + PL_MAP_Y
    sta zp_player_y

    rts

// draw_store — Draw one store building on the map
// Input: X = store index (0-5)
// Uses: zp_ptr0/zp_ptr0_hi, zp_ptr1/zp_ptr1_hi, zp_temp1-zp_temp4
// Preserves: nothing
draw_store:
    // Get store position
    lda store_pos_x,x
    sta zp_temp1        // left col
    lda store_pos_y,x
    sta zp_temp2        // top row

    // Calculate right col and bottom row
    lda zp_temp1
    clc
    adc #STORE_W - 1
    sta zp_temp3        // right col

    lda zp_temp2
    clc
    adc #STORE_H - 1
    sta zp_temp4        // bottom row

    // --- Top wall of store ---
    ldx zp_temp2        // top row
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    // Top-left corner
    ldy zp_temp1
    lda #TILE_CORNER_TL | TOWN_FLAGS
    :MapWrite_ptr0_y()

    // Top-right corner
    ldy zp_temp3
    lda #TILE_CORNER_TR | TOWN_FLAGS
    :MapWrite_ptr0_y()

    // Top horizontal wall
    ldy zp_temp1
    iny                 // Start at left+1
    lda #TILE_WALL_H | TOWN_FLAGS
!top_h:
    :MapWrite_ptr0_y()
    iny
    cpy zp_temp3
    bne !top_h-

    // --- Bottom wall of store ---
    ldx zp_temp4        // bottom row
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    // Bottom-left corner
    ldy zp_temp1
    lda #TILE_CORNER_BL | TOWN_FLAGS
    :MapWrite_ptr0_y()

    // Bottom-right corner
    ldy zp_temp3
    lda #TILE_CORNER_BR | TOWN_FLAGS
    :MapWrite_ptr0_y()

    // Bottom horizontal wall (with door gap)
    ldy zp_temp1
    iny
    lda #TILE_WALL_H | TOWN_FLAGS
!bot_h:
    :MapWrite_ptr0_y()
    iny
    cpy zp_temp3
    bne !bot_h-

    // --- Side walls (interior rows) ---
    lda zp_temp2
    clc
    adc #1
    tax                 // Start row = top + 1
!sides:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    // Left wall
    ldy zp_temp1
    lda #TILE_WALL_V | TOWN_FLAGS
    :MapWrite_ptr0_y()
    // Right wall
    ldy zp_temp3
    :MapWrite_ptr0_y()
    // Fill interior with opaque wall (no flags → invisible, non-walkable)
    ldy zp_temp1
    iny
    lda #TILE_WALL_H
!interior:
    :MapWrite_ptr0_y()
    iny
    cpy zp_temp3
    bne !interior-
    inx
    cpx zp_temp4
    bne !sides-

    // --- Place door on south wall (center) ---
    // Door is at store_door_x/y
    ldx zp_temp0        // Recover store index from zp_temp0
    lda store_door_y,x
    tax                 // Row for door
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldx zp_temp0        // Re-get store index
    ldy store_door_x,x
    lda #TILE_DOOR_OPEN | TOWN_FLAGS
    :MapWrite_ptr0_y()

    rts

// ============================================================
// Private dungeon generation constants
// ============================================================
.const ROOM_MIN_W       = 4
.const ROOM_MAX_W       = 11    // 4 + rng(8)
.const ROOM_MIN_H       = 3
.const ROOM_MAX_H       = 7     // 3 + rng(5)
.const ROOM_GAP         = 2     // Min gap between rooms
.const MAX_ROOM_RETRIES = 20    // Retries per room attempt
.const ROOM_EDGE_PAD    = 4     // Keep overlap math away from map edges

// ============================================================
// Local scratch for dungeon generation (safe from rng_range clobbering zp_temp3/4)
dg_room_x:   .byte 0   // Current room x being placed
dg_room_y:   .byte 0   // Current room y being placed
dg_room_w:   .byte 0   // Current room w being placed
dg_room_h:   .byte 0   // Current room h being placed
dg_idx:      .byte 0   // Current room index
dg_retries:  .byte 0   // Retry counter
dg_cx1:      .byte 0   // Corridor center x1
dg_cy1:      .byte 0   // Corridor center y1
dg_cx2:      .byte 0   // Corridor center x2
dg_cy2:      .byte 0   // Corridor center y2

// ============================================================
// level_generate — Dispatch to town or dungeon generation
// ============================================================
level_generate:
    lda zp_player_dlvl
    bne !dungeon+
    jmp town_generate
!dungeon:
    jmp dungeon_generate

// ============================================================
// dungeon_generate — Main dungeon generation routine
// Order matches umoria closely: fill, rooms, streamers, tunnels,
// then features and stairs. Streamers BEFORE corridors ensures
// corridors always overwrite mineral veins they cross.
// ============================================================
dungeon_generate:
    lda #10
    sta dg_gen_retries          // Max regeneration attempts
!dg_gen_retry:
    lda #0
    sta trap_count
    jsr fill_map_rock
    jsr dg_progress_tick
    jsr place_rooms
    jsr dg_progress_tick
    // Safety: if fewer than 2 rooms placed, retry entire generation
    lda room_count
    cmp #2
    bcs !rooms_ok+
    dec dg_gen_retries
    bne !dg_gen_retry-
    jmp !dg_gen_done+           // Give up, use whatever we have
!rooms_ok:
    jsr shuffle_rooms           // Randomize connection order (DG2)
    jsr tramp_assign_special_room   // Pick special room type (if any)
    jsr place_streamers         // Before corridors (umoria order):
                                // corridors overwrite veins they cross
    jsr dg_progress_tick
    jsr connect_rooms
    jsr dg_progress_tick
    jsr tramp_vault_seal_entrance   // Seal vault entrance with secret door
    jsr place_stairs_dungeon
    jsr place_traps
    jsr place_secrets
    jsr darken_rooms            // Strip FLAG_LIT from dark rooms (after all generation)
    jsr dg_progress_tick
    jsr verify_stairs
    jsr position_player_dungeon
!dg_gen_done:
    rts

dg_gen_retries: .byte 0

// ============================================================
// darken_rooms — Strip FLAG_LIT from dark rooms
// Called after all generation so corridors can detect room walls during
// carving (FLAG_LIT distinguishes room wall from rock). For each dark
// room (room_lit[i]==0), clears FLAG_LIT from the full rectangle
// including walls (room_x-1 to room_x+room_w, room_y-1 to room_y+room_h).
// ============================================================
darken_rooms:
    lda #0
    sta dr_idx
!dr_loop:
    lda dr_idx
    cmp room_count
    bcs !dr_done+

    tax
    lda room_lit,x
    bne !dr_next+               // Lit room → skip

    // Dark room: clear FLAG_LIT from entire room rectangle
    lda room_y,x
    sec
    sbc #1
    sta dr_row                  // Start row (top wall)
    lda room_y,x
    clc
    adc room_h,x
    sta dr_end_row              // End row (bottom wall, inclusive)
    lda room_x,x
    sec
    sbc #1
    sta dr_start_col            // Start col (left wall)
    lda room_x,x
    clc
    adc room_w,x
    sta dr_end_col              // End col (right wall, inclusive)

!dr_row_loop:
    ldx dr_row
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    ldy dr_start_col
!dr_col_loop:
    :MapRead_ptr0_y()
    and #~FLAG_LIT              // Clear FLAG_LIT
    :MapWrite_ptr0_y()
    cpy dr_end_col
    beq !dr_row_done+
    iny
    jmp !dr_col_loop-
!dr_row_done:
    inc dr_row
    lda dr_row
    cmp dr_end_row
    beq !dr_row_loop-           // Process end row too
    bcc !dr_row_loop-

!dr_next:
    inc dr_idx
    jmp !dr_loop-
!dr_done:
    rts

dr_idx:       .byte 0
dr_row:       .byte 0
dr_end_row:   .byte 0
dr_start_col: .byte 0
dr_end_col:   .byte 0

// ============================================================
// fill_map_rock — Fill entire map with solid rock (TILE_WALL_H, no flags)
// DG8: Uses TILE_WALL_H ($10) for uncarved rock because the 4-bit tile
// type system (0-15) has no room for a separate TILE_ROCK constant.
// Rock vs room wall is distinguished by FLAG_LIT: room walls have it,
// uncarved rock does not.  The renderer uses this to show '#' for rock.
// ============================================================
fill_map_rock:
    lda #TILE_WALL_H            // $10 — solid rock, no flags
    jmp map_bulk_fill_all

// ============================================================
// place_rooms — Place 4-8 rooms with overlap rejection
// ============================================================
place_rooms:
    // Roll room count: rng_range(5) + 4 → [4, 8]
    lda #5
    jsr rng_range
    clc
    adc #4
    sta room_count

    lda #0
    sta dg_idx                  // Start at room 0

!room_loop:
    lda #MAX_ROOM_RETRIES
    sta dg_retries

!retry:
    // Roll width: rng_range(8) + 4 → [4, 11]
    lda #8
    jsr rng_range
    clc
    adc #ROOM_MIN_W
    sta dg_room_w

    // Roll height: rng_range(5) + 3 → [3, 7]
    lda #5
    jsr rng_range
    clc
    adc #ROOM_MIN_H
    sta dg_room_h

    // Roll x position: rng_range((MAP_COLS - ROOM_EDGE_PAD - 1) - w) + ROOM_EDGE_PAD
    // Keeps wall + overlap math in-bounds while scaling with MAP_COLS.
    lda #MAP_COLS - ROOM_EDGE_PAD - 1
    sec
    sbc dg_room_w
    jsr rng_range
    clc
    adc #ROOM_EDGE_PAD
    sta dg_room_x

    // Roll y position: rng_range((MAP_ROWS - ROOM_EDGE_PAD - 1) - h) + ROOM_EDGE_PAD
    // Keeps wall + overlap math in-bounds while scaling with MAP_ROWS.
    lda #MAP_ROWS - ROOM_EDGE_PAD - 1
    sec
    sbc dg_room_h
    jsr rng_range
    clc
    adc #ROOM_EDGE_PAD
    sta dg_room_y

    // Check overlap with all existing rooms
    jsr check_room_overlap
    bcs !overlap+               // Carry set = overlap found

    // No overlap — place the room
    ldx dg_idx
    lda dg_room_x
    sta room_x,x
    lda dg_room_y
    sta room_y,x
    lda dg_room_w
    sta room_w,x
    lda dg_room_h
    sta room_h,x

    // Draw the room
    jsr draw_dungeon_room

    // Determine if room is lit (umoria: lit if dlvl <= randint(1,25))
    // rng_range(25) → [0,24], add 1 → [1,25]. Lit if dlvl <= result.
    lda #25
    jsr rng_range               // A = [0, 24]
    clc
    adc #1                      // A = [1, 25]
    cmp zp_player_dlvl          // Compare threshold vs dungeon level
    ldx dg_idx
    lda #0                      // Default: dark
    bcc !room_dark+             // threshold < dlvl → dark
    lda #1                      // threshold >= dlvl → lit
!room_dark:
    sta room_lit,x

    // Next room
    inc dg_idx
    lda dg_idx
    cmp room_count
    beq !rooms_placed+
    jmp !room_loop-
!rooms_placed:
    rts

!overlap:
    dec dg_retries
    beq !retries_exhausted+
    jmp !retry-
!retries_exhausted:
    // Max retries exhausted — skip this room, reduce count
    dec room_count
    lda dg_idx
    cmp room_count
    beq !rooms_placed2+
    jmp !room_loop-
!rooms_placed2:
    rts

// ============================================================
// check_room_overlap — Check if dg_room_* overlaps any placed room
// Output: carry set = overlap, carry clear = no overlap
// ============================================================
check_room_overlap:
    ldx #0
    cpx dg_idx
    bne !check_loop+
    jmp !no_overlap+            // No rooms placed yet

!check_loop:
    // Check bounding box with ROOM_GAP separation
    // Pad only room A (new room) by GAP; B (existing) uses raw wall bounds.
    // No overlap if: A.left >= B.right OR A.right <= B.left
    //            OR  A.top >= B.bottom OR A.bottom <= B.top

    // Compute A.left = dg_room_x - 1 - GAP
    lda dg_room_x
    sec
    sbc #1 + ROOM_GAP
    sta dg_cx1                  // A.left (reusing scratch)

    // Compute A.right = dg_room_x + dg_room_w + GAP
    lda dg_room_x
    clc
    adc dg_room_w
    adc #ROOM_GAP
    sta dg_cy1                  // A.right

    // Compute B.left = room_x[x] - 1 (wall bound, no GAP)
    lda room_x,x
    sec
    sbc #1
    sta dg_cx2                  // B.left

    // Compute B.right = room_x[x] + room_w[x] (wall bound, no GAP)
    lda room_x,x
    clc
    adc room_w,x
    sta dg_cy2                  // B.right

    // Test: A.left >= B.right? (no X overlap)
    lda dg_cx1
    cmp dg_cy2
    bcs !next_room+

    // Test: A.right <= B.left? (no X overlap)
    lda dg_cy1
    cmp dg_cx2
    bcc !next_room+
    beq !next_room+

    // X overlaps — now check Y axis
    // A.top = dg_room_y - 1 - GAP
    lda dg_room_y
    sec
    sbc #1 + ROOM_GAP
    sta dg_cx1                  // A.top

    // A.bottom = dg_room_y + dg_room_h + GAP
    lda dg_room_y
    clc
    adc dg_room_h
    adc #ROOM_GAP
    sta dg_cy1                  // A.bottom

    // B.top = room_y[x] - 1 (wall bound, no GAP)
    lda room_y,x
    sec
    sbc #1
    sta dg_cx2                  // B.top

    // B.bottom = room_y[x] + room_h[x] (wall bound, no GAP)
    lda room_y,x
    clc
    adc room_h,x
    sta dg_cy2                  // B.bottom

    // Test: A.top >= B.bottom? (no Y overlap)
    lda dg_cx1
    cmp dg_cy2
    bcs !next_room+

    // Test: A.bottom <= B.top? (no Y overlap)
    lda dg_cy1
    cmp dg_cx2
    bcc !next_room+
    beq !next_room+

    // Both axes overlap — rooms too close
    sec                         // Overlap found
    rts

!next_room:
    inx
    cpx dg_idx
    bne !check_loop-

!no_overlap:
    clc                         // No overlap
    rts

// ============================================================
// draw_dungeon_room — Draw walls and floor for room at dg_room_*
// Uses: zp_ptr0, zp_temp1-zp_temp4
// ============================================================
draw_dungeon_room:
    // Compute wall coordinates
    // Wall left = dg_room_x - 1
    lda dg_room_x
    sec
    sbc #1
    sta zp_temp1                // wall left col

    // Wall top = dg_room_y - 1
    lda dg_room_y
    sec
    sbc #1
    sta zp_temp2                // wall top row

    // Wall right = dg_room_x + dg_room_w
    lda dg_room_x
    clc
    adc dg_room_w
    sta zp_temp3                // wall right col

    // Wall bottom = dg_room_y + dg_room_h
    lda dg_room_y
    clc
    adc dg_room_h
    sta zp_temp4                // wall bottom row

    // --- Top wall ---
    ldx zp_temp2
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    // Top-left corner
    ldy zp_temp1
    lda #TILE_CORNER_TL | DUNGEON_FLAGS
    :MapWrite_ptr0_y()

    // Top-right corner
    ldy zp_temp3
    lda #TILE_CORNER_TR | DUNGEON_FLAGS
    :MapWrite_ptr0_y()

    // Horizontal wall between corners
    ldy zp_temp1
    iny
    lda #TILE_WALL_H | DUNGEON_FLAGS
!dr_top_h:
    :MapWrite_ptr0_y()
    iny
    cpy zp_temp3
    bne !dr_top_h-

    // --- Bottom wall ---
    ldx zp_temp4
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    // Bottom-left corner
    ldy zp_temp1
    lda #TILE_CORNER_BL | DUNGEON_FLAGS
    :MapWrite_ptr0_y()

    // Bottom-right corner
    ldy zp_temp3
    lda #TILE_CORNER_BR | DUNGEON_FLAGS
    :MapWrite_ptr0_y()

    // Horizontal wall between corners
    ldy zp_temp1
    iny
    lda #TILE_WALL_H | DUNGEON_FLAGS
!dr_bot_h:
    :MapWrite_ptr0_y()
    iny
    cpy zp_temp3
    bne !dr_bot_h-

    // --- Side walls + interior ---
    lda zp_temp2
    clc
    adc #1
    tax                         // Start row = wall_top + 1
!dr_sides:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    // Left wall
    ldy zp_temp1
    lda #TILE_WALL_V | DUNGEON_FLAGS
    :MapWrite_ptr0_y()

    // Right wall
    ldy zp_temp3
    :MapWrite_ptr0_y()

    // Fill interior with floor
    ldy zp_temp1
    iny
    lda #TILE_FLOOR | DUNGEON_FLAGS
!dr_interior:
    :MapWrite_ptr0_y()
    iny
    cpy zp_temp3
    bne !dr_interior-

    inx
    cpx zp_temp4
    bne !dr_sides-

    rts

// ============================================================
// shuffle_rooms — Fisher-Yates shuffle of room arrays
// Randomizes connection order to avoid predictable linear chains.
// Swaps all 4 parallel arrays (room_x, room_y, room_w, room_h).
// Preserves: nothing
// ============================================================
shuffle_rooms:
    ldx room_count
    dex                         // Start at last index
    beq !shuf_done+             // 0 or 1 rooms, nothing to shuffle
!shuf_loop:
    // Pick random j in [0, x]
    stx shuf_i                  // Save i (X will be clobbered by rng_range)
    txa
    clc
    adc #1                      // rng_range(i+1) → [0, i]
    jsr rng_range               // A = j
    tay                         // Y = j
    ldx shuf_i                  // X = i

    // If i == j, no swap needed
    sty shuf_j_tmp
    cpx shuf_j_tmp
    beq !shuf_skip+

    // Swap room_x[i] ↔ room_x[j]
    lda room_x,x
    pha
    lda room_x,y
    sta room_x,x
    pla
    sta room_x,y

    // Swap room_y[i] ↔ room_y[j]
    lda room_y,x
    pha
    lda room_y,y
    sta room_y,x
    pla
    sta room_y,y

    // Swap room_w[i] ↔ room_w[j]
    lda room_w,x
    pha
    lda room_w,y
    sta room_w,x
    pla
    sta room_w,y

    // Swap room_h[i] ↔ room_h[j]
    lda room_h,x
    pha
    lda room_h,y
    sta room_h,x
    pla
    sta room_h,y

!shuf_skip:
    ldx shuf_i
    dex
    bne !shuf_loop-             // Continue while i > 0
!shuf_done:
    rts

shuf_i:     .byte 0
shuf_j_tmp: .byte 0

// ============================================================
// connect_rooms — Connect rooms in circular chain with L-shaped corridors
// Connects room[0]→[1]→...→[N-1]→[0] so every room has >= 2 connections.
// ============================================================
connect_rooms:
    lda room_count
    cmp #2
    bcs !conn_start+
    jmp !conn_done+             // Need at least 2 rooms
!conn_start:
    lda #0
    sta dg_idx                  // Room pair index

!conn_loop:
    // Compute center of room[idx]
    ldx dg_idx
    lda room_w,x
    lsr
    clc
    adc room_x,x
    sta dg_cx1

    lda room_h,x
    lsr
    clc
    adc room_y,x
    sta dg_cy1

    // Compute center of room[(idx+1) % room_count] (circular chain)
    lda dg_idx
    clc
    adc #1
    cmp room_count
    bcc !conn_no_wrap+
    lda #0                       // Wrap around to room 0
!conn_no_wrap:
    tax
    lda room_w,x
    lsr
    clc
    adc room_x,x
    sta dg_cx2

    lda room_h,x
    lsr
    clc
    adc room_y,x
    sta dg_cy2

    // Coin flip: horizontal-first or vertical-first
    jsr rng_byte
    and #1
    beq !h_first+

    // Vertical first, then horizontal
    jsr carve_v_corridor         // Vertical from cy1 to cy2 at x=cx1
    lda dg_cy2
    sta dg_cy1                   // Now at cy2
    jsr carve_h_corridor         // Horizontal from cx1 to cx2 at y=cy2
    jmp !conn_next+

!h_first:
    // Horizontal first, then vertical
    jsr carve_h_corridor         // Horizontal from cx1 to cx2 at y=cy1
    lda dg_cx2
    sta dg_cx1                   // Now at cx2
    jsr carve_v_corridor         // Vertical from cy1 to cy2 at x=cx2
!conn_next:
    inc dg_idx
    lda dg_idx
    cmp room_count               // Stop after room_count iterations (circular)
    bcs !conn_done+
    jmp !conn_loop-

!conn_done:
    rts

// ============================================================
// carve_h_corridor — Carve horizontal corridor from cx1 to cx2 at row cy1
// Input: dg_cx1 = start x, dg_cx2 = end x, dg_cy1 = row y
// Always carves from smaller x to larger x using Y register.
// ============================================================
carve_h_corridor:
    ldx dg_cy1
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    // Ensure we iterate from smaller to larger
    lda dg_cx1
    cmp dg_cx2
    bcc !hc_cx1_smaller+
    beq !hc_single+
    // cx1 > cx2: swap so we go from cx2 to cx1
    ldy dg_cx2                  // Start at smaller
    lda dg_cx1
    sta dg_room_x               // End at larger (temp)
    jmp !hc_loop+
!hc_cx1_smaller:
    ldy dg_cx1                  // Start at smaller
    lda dg_cx2
    sta dg_room_x               // End at larger (temp)
!hc_loop:
    :MapRead_ptr0_y()             // Read existing tile
    tax                         // Stash full byte in X
    and #TILE_TYPE_MASK
    beq !hc_advance+            // $00 floor → skip
    cmp #TILE_DOOR_OPEN
    beq !hc_advance+            // $70 door open → skip
    cmp #TILE_DOOR_CLOSED
    beq !hc_advance+            // $80 door closed → skip
    cmp #TILE_STAIRS_DN
    bcs !hc_carve_floor+        // $90+ (streamers etc) → carve to floor
    // Types $10-$60: wall tiles — check FLAG_LIT to distinguish room wall from rock
    txa                         // Recover full byte
    and #FLAG_LIT
    beq !hc_carve_floor+        // Not lit = rock fill → carve to floor
    // LIT room wall — only place door on perpendicular (vertical) wall
    txa
    and #TILE_TYPE_MASK
    cmp #TILE_WALL_V
    beq !hc_place_door+         // Vertical wall → door
    // Parallel wall (horiz) or corner → carve to floor
!hc_carve_floor:
    lda #TILE_FLOOR               // No flags — corridor starts invisible
    :MapWrite_ptr0_y()
    jmp !hc_advance+
!hc_place_door:
    sty dg_retries               // Save Y (column pos; dg_retries not live here)
    jsr random_door_type         // A = door tile value with flags
    ldy dg_retries
    :MapWrite_ptr0_y()
!hc_advance:
    cpy dg_room_x
    beq !hc_done+
    iny
    jmp !hc_loop-
!hc_single:
    ldy dg_cx1
    :MapRead_ptr0_y()             // Read existing tile
    tax
    and #TILE_TYPE_MASK
    beq !hc_done+               // Floor → skip
    cmp #TILE_DOOR_OPEN
    beq !hc_done+
    cmp #TILE_DOOR_CLOSED
    beq !hc_done+
    cmp #TILE_STAIRS_DN
    bcs !hc_single_floor+       // $90+ → carve
    txa
    and #FLAG_LIT
    beq !hc_single_floor+       // Not lit = rock → floor
    txa
    and #TILE_TYPE_MASK
    cmp #TILE_WALL_V
    beq !hc_single_door+        // Perpendicular vertical wall → door
!hc_single_floor:
    lda #TILE_FLOOR               // No flags — corridor starts invisible
    :MapWrite_ptr0_y()
    jmp !hc_done+
!hc_single_door:
    sty dg_retries
    jsr random_door_type
    ldy dg_retries
    :MapWrite_ptr0_y()
!hc_done:
    rts

// ============================================================
// carve_v_corridor — Carve vertical corridor from cy1 to cy2 at col cx1
// Input: dg_cx1 = column x, dg_cy1 = start y, dg_cy2 = end y
// Always carves from smaller y to larger y using X register.
// ============================================================
carve_v_corridor:
    lda dg_cy1
    cmp dg_cy2
    bcc !vc_cy1_smaller+
    beq !vc_single+
    // cy1 > cy2: iterate from cy2 to cy1
    ldx dg_cy2
    lda dg_cy1
    sta dg_room_y               // End row (temp)
    jmp !vc_loop+
!vc_cy1_smaller:
    ldx dg_cy1
    lda dg_cy2
    sta dg_room_y               // End row (temp)
!vc_loop:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy dg_cx1
    :MapRead_ptr0_y()             // Read existing tile
    sta dg_retries              // Stash full byte (scratch — not live here)
    and #TILE_TYPE_MASK
    beq !vc_advance+            // $00 floor → skip
    cmp #TILE_DOOR_OPEN
    beq !vc_advance+            // $70 door open → skip
    cmp #TILE_DOOR_CLOSED
    beq !vc_advance+            // $80 door closed → skip
    cmp #TILE_STAIRS_DN
    bcs !vc_carve_floor+        // $90+ (streamers etc) → carve to floor
    // Types $10-$60: wall tiles — check FLAG_LIT
    lda dg_retries              // Recover full byte
    and #FLAG_LIT
    beq !vc_carve_floor+        // Not lit = rock fill → carve to floor
    // LIT room wall — only place door on perpendicular (horizontal) wall
    lda dg_retries
    and #TILE_TYPE_MASK
    cmp #TILE_WALL_H
    beq !vc_place_door+         // Horizontal wall → door
    // Parallel wall (vert) or corner → carve to floor
!vc_carve_floor:
    lda #TILE_FLOOR               // No flags — corridor starts invisible
    :MapWrite_ptr0_y()
    jmp !vc_advance+
!vc_place_door:
    stx dg_retries               // Save row counter (dg_retries free here)
    sty shuf_j_tmp               // Save column (reuse shuffle scratch)
    jsr random_door_type         // A = random door tile with flags
    ldx dg_retries
    ldy shuf_j_tmp
    :MapWrite_ptr0_y()
!vc_advance:
    cpx dg_room_y
    beq !vc_done+
    inx
    jmp !vc_loop-
!vc_single:
    ldx dg_cy1
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy dg_cx1
    :MapRead_ptr0_y()             // Read existing tile
    sta dg_retries
    and #TILE_TYPE_MASK
    beq !vc_done+               // Floor → skip
    cmp #TILE_DOOR_OPEN
    beq !vc_done+
    cmp #TILE_DOOR_CLOSED
    beq !vc_done+
    cmp #TILE_STAIRS_DN
    bcs !vc_single_floor+       // $90+ → carve
    lda dg_retries
    and #FLAG_LIT
    beq !vc_single_floor+       // Not lit = rock → floor
    lda dg_retries
    and #TILE_TYPE_MASK
    cmp #TILE_WALL_H
    beq !vc_single_door+        // Perpendicular horizontal wall → door
!vc_single_floor:
    lda #TILE_FLOOR               // No flags — corridor starts invisible
    :MapWrite_ptr0_y()
    jmp !vc_done+
!vc_single_door:
    sty shuf_j_tmp
    jsr random_door_type
    ldy shuf_j_tmp
    :MapWrite_ptr0_y()
!vc_done:
    rts

// ============================================================
// random_door_type — Return a random door tile byte with DUNGEON_FLAGS
// Output: A = door tile value (50% open, 50% closed)
// Clobbers: X (via rng_range)
// Preserves: Y
// Note: Secret doors are placed by place_secrets post-processing,
//       NOT here. Placing secrets at corridor junctions creates
//       impassable walls that block room connectivity.
// ============================================================
random_door_type:
    lda #2
    jsr rng_range               // A = [0, 1]
    cmp #0
    beq !rdt_open+
    lda #TILE_DOOR_CLOSED | DUNGEON_FLAGS
    rts
!rdt_open:
    lda #TILE_DOOR_OPEN | DUNGEON_FLAGS
    rts

// ============================================================
// mark_corridor_walls — Make walls adjacent to corridors visible
//
// Post-processing pass: scans entire map.  For each floor tile
// with FLAG_VISITED set, marks all 8 adjacent non-floor tiles
// with FLAG_VISITED so the renderer shows corridor boundaries
// as stone walls.  Idempotent (room walls already have the flag).
// ============================================================
mark_corridor_walls:
    ldx #1                      // Start at row 1 (skip boundary)
!mcw_row:
    stx mcw_save_row
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    ldy #1                      // Start at col 1
!mcw_col:
    :MapRead_ptr0_y()
    // Is this a visited floor tile?
    tax
    and #TILE_TYPE_MASK
    bne !mcw_next+              // Not floor type → skip
    txa
    and #FLAG_VISITED
    beq !mcw_next+              // Floor but not visited → skip

    // Found a visited floor tile — mark 8 adjacent walls
    sty mcw_save_col

    // --- Same row: left (Y-1) and right (Y+1) ---
    dey
    jsr mcw_mark_p0
    ldy mcw_save_col
    iny
    jsr mcw_mark_p0

    // --- Row above (X-1): 3 tiles ---
    ldx mcw_save_row
    dex
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi
    ldy mcw_save_col
    dey
    jsr mcw_mark_p1
    iny
    jsr mcw_mark_p1
    iny
    jsr mcw_mark_p1

    // --- Row below (X+1): 3 tiles ---
    ldx mcw_save_row
    inx
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi
    ldy mcw_save_col
    dey
    jsr mcw_mark_p1
    iny
    jsr mcw_mark_p1
    iny
    jsr mcw_mark_p1

    // Restore Y for column scan
    ldy mcw_save_col

!mcw_next:
    iny
    cpy #MAP_COLS - 1
    bne !mcw_col-

    ldx mcw_save_row
    inx
    cpx #MAP_ROWS - 1
    beq !mcw_done+
    jmp !mcw_row-
!mcw_done:
    rts

// Mark tile at ptr0[Y] as visited if it's a non-floor, unvisited tile
mcw_mark_p0:
    :MapRead_ptr0_y()
    tax
    and #FLAG_VISITED
    bne !mcw_skip+              // Already visited
    txa
    and #TILE_TYPE_MASK
    beq !mcw_skip+              // Floor → skip
    txa
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
!mcw_skip:
    rts

// Mark tile at ptr1[Y] as visited if it's a non-floor, unvisited tile
mcw_mark_p1:
    lda (zp_ptr1),y
    tax
    and #FLAG_VISITED
    bne !mcw_skip+
    txa
    and #TILE_TYPE_MASK
    beq !mcw_skip+
    txa
    ora #FLAG_VISITED
    sta (zp_ptr1),y
!mcw_skip:
    rts

mcw_save_row: .byte 0
mcw_save_col: .byte 0

// ============================================================
// add_corridor_doors — Legacy no-op compatibility wrapper
// Original-style door placement happens during actual corridor penetration
// in carve_h_corridor / carve_v_corridor. We intentionally do NOT synthesize
// new room-entry doors just because a corridor floor happens to run alongside
// a room wall; that behavior created aggressive side-entry doors.
// ============================================================
add_corridor_doors:
    rts

// ============================================================
// random_wall_adj_floor — Pick a floor tile in room X, preferring wall-adjacent
// Tries up to 20 times to find a tile with >= 3 adjacent walls (corner-like).
// Falls back to >= 2, >= 1, then any floor tile.
// Input: X = room index
// Output: A = x coordinate, Y = y coordinate
// Clobbers: zp_ptr0, zp_temp3, zp_temp4
// ============================================================
.const WALL_ADJ_TRIES = 20

random_wall_adj_floor:
    stx rwaf_room_idx

    // Try for >= 3 adjacent walls
    lda #3
    sta rwaf_threshold
    lda #WALL_ADJ_TRIES
    sta rwaf_attempts
!rwaf_try:
    ldx rwaf_room_idx
    jsr random_floor_in_room    // A = x, Y = y
    sta rwaf_result_x
    sty rwaf_result_y

    // Count adjacent wall tiles (4 cardinal directions)
    jsr count_adj_walls         // A = wall count
    cmp rwaf_threshold
    bcs !rwaf_found+            // >= threshold → accept

    dec rwaf_attempts
    bne !rwaf_try-

    // Degrade threshold
    dec rwaf_threshold
    lda rwaf_threshold
    beq !rwaf_found+            // Threshold 0 → accept anything
    lda #WALL_ADJ_TRIES
    sta rwaf_attempts
    jmp !rwaf_try-

!rwaf_found:
    lda rwaf_result_x
    ldy rwaf_result_y
    rts

// count_adj_walls — Count wall tiles adjacent to (rwaf_result_x, rwaf_result_y)
// Output: A = count of wall tiles in 4 cardinal directions (0-4)
count_adj_walls:
    lda #0
    sta rwaf_wall_count

    // North (y-1)
    ldx rwaf_result_y
    dex
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy rwaf_result_x
    :MapRead_ptr0_y()
    jsr caw_check_wall

    // South (y+1)
    ldx rwaf_result_y
    inx
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy rwaf_result_x
    :MapRead_ptr0_y()
    jsr caw_check_wall

    // West (x-1)
    ldx rwaf_result_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy rwaf_result_x
    dey
    :MapRead_ptr0_y()
    jsr caw_check_wall

    // East (x+1)
    ldy rwaf_result_x
    iny
    :MapRead_ptr0_y()
    jsr caw_check_wall

    lda rwaf_wall_count
    rts

// caw_check_wall — If tile A is a wall type ($10-$60), increment rwaf_wall_count
caw_check_wall:
    and #TILE_TYPE_MASK
    beq !caw_no+                // $00 = floor
    cmp #TILE_DOOR_OPEN
    bcs !caw_no+                // $70+ = not wall
    inc rwaf_wall_count
!caw_no:
    rts

rwaf_room_idx:   .byte 0
rwaf_threshold:  .byte 0
rwaf_attempts:   .byte 0
rwaf_result_x:   .byte 0
rwaf_result_y:   .byte 0
rwaf_wall_count: .byte 0

// ============================================================
// place_stairs_dungeon — Place 1 up-stairs + 2 down-stairs
// Uses random_wall_adj_floor for wall-adjacent placement preference.
// ============================================================
place_stairs_dungeon:
    // Stairs up in room 0
    ldx #0
    jsr random_wall_adj_floor
    sta stairs_up_x
    sty stairs_up_y
    // Write to map
    jsr write_tile_at_xy
    lda #TILE_STAIRS_UP | DUNGEON_FLAGS
    :MapWrite_ptr0_y()

    // Stairs down 1 — pick a different room
    lda room_count
    sec
    sbc #1
    jsr rng_range               // [0, count-2]
    clc
    adc #1                      // [1, count-1] — avoids room 0
    tax
    jsr random_wall_adj_floor
    sta stairs_dn1_x
    sty stairs_dn1_y
    jsr write_tile_at_xy
    lda #TILE_STAIRS_DN | DUNGEON_FLAGS
    :MapWrite_ptr0_y()

    // Stairs down 2 — pick another different room if possible
    lda room_count
    cmp #3
    bcc !use_room0+             // Only 2 rooms, reuse room 0 area
    lda room_count
    sec
    sbc #2
    jsr rng_range               // [0, count-3]
    clc
    adc #2                      // [2, count-1]
    tax
    jmp !place_dn2+
!use_room0:
    ldx #0
!place_dn2:
    jsr random_wall_adj_floor
    sta stairs_dn2_x
    sty stairs_dn2_y
    jsr write_tile_at_xy
    lda #TILE_STAIRS_DN | DUNGEON_FLAGS
    :MapWrite_ptr0_y()
    rts

// ============================================================
// random_floor_in_room — Pick a random floor tile inside room X
// Input: X = room index
// Output: A = x coordinate, Y = y coordinate
// Clobbers: zp_ptr0, zp_temp3, zp_temp4
// ============================================================
random_floor_in_room:
    // Save room data to local scratch before calling rng_range
    lda room_x,x
    sta dg_room_x
    lda room_y,x
    sta dg_room_y
    lda room_w,x
    sta dg_room_w
    lda room_h,x
    sta dg_room_h

    // Random x offset within room interior
    lda dg_room_w
    jsr rng_range               // [0, w-1]
    clc
    adc dg_room_x
    pha                         // Save x on stack

    // Random y offset within room interior
    lda dg_room_h
    jsr rng_range               // [0, h-1]
    clc
    adc dg_room_y
    tay                         // Y = y coordinate

    pla                         // A = x coordinate
    rts

// ============================================================
// write_tile_at_xy — Set up zp_ptr0 for map tile at (A, Y)
// Input: A = x, Y = y
// Output: zp_ptr0 points to row Y, Y register = x offset
// ============================================================
write_tile_at_xy:
    pha                         // Save x
    tya
    tax                         // X = row
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    pla
    tay                         // Y = column offset
    rts

// ============================================================
// place_streamers — Place 5 mineral streamers (3 magma + 2 quartz)
// Matches umoria: 3 magma streamers, then 2 quartz streamers.
// ============================================================
place_streamers:
    // 3 magma streamers
    lda #TILE_MAGMA | DUNGEON_FLAGS
    sta dg_room_w
    jsr carve_streamer
    lda #TILE_MAGMA | DUNGEON_FLAGS
    sta dg_room_w
    jsr carve_streamer
    lda #TILE_MAGMA | DUNGEON_FLAGS
    sta dg_room_w
    jsr carve_streamer
    // 2 quartz streamers
    lda #TILE_QUARTZ | DUNGEON_FLAGS
    sta dg_room_w
    jsr carve_streamer
    lda #TILE_QUARTZ | DUNGEON_FLAGS
    sta dg_room_w
    jsr carve_streamer
    rts

// ============================================================
// carve_streamer — Carve one mineral streamer across the map
// Input: dg_room_w = tile value to write (mineral type with flags)
// Picks random edge start, walks diagonally with jitter
// ============================================================
carve_streamer:

    // Pick starting edge and position
    // Start from a random edge
    jsr rng_byte
    and #3                      // 0=top, 1=bottom, 2=left, 3=right

    cmp #0
    bne !cs_not_top+
    // Top edge: x = random, y = 1
    lda #78
    jsr rng_range
    clc
    adc #1
    sta dg_cx1                  // x
    lda #1
    sta dg_cy1                  // y
    lda #1                      // dy = +1 (going down)
    sta dg_room_h
    jmp !cs_pick_dx+
!cs_not_top:
    cmp #1
    bne !cs_not_bottom+
    // Bottom edge
    lda #78
    jsr rng_range
    clc
    adc #1
    sta dg_cx1
    lda #MAP_ROWS - 2
    sta dg_cy1
    lda #$ff                    // dy = -1 (going up)
    sta dg_room_h
    jmp !cs_pick_dx+
!cs_not_bottom:
    cmp #2
    bne !cs_right+
    // Left edge
    lda #1
    sta dg_cx1
    lda #46
    jsr rng_range
    clc
    adc #1
    sta dg_cy1
    lda #1                      // dx = +1 (going right)
    sta dg_room_x
    jmp !cs_pick_dy+
!cs_right:
    // Right edge
    lda #MAP_COLS - 2
    sta dg_cx1
    lda #46
    jsr rng_range
    clc
    adc #1
    sta dg_cy1
    lda #$ff                    // dx = -1 (going left)
    sta dg_room_x
    jmp !cs_pick_dy+

!cs_pick_dx:
    // Pick random dx: -1 or +1
    jsr rng_byte
    and #1
    beq !cs_dx_neg+
    lda #1
    jmp !cs_dx_set+
!cs_dx_neg:
    lda #$ff
!cs_dx_set:
    sta dg_room_x
    jmp !cs_walk+

!cs_pick_dy:
    // Pick random dy: -1 or +1
    jsr rng_byte
    and #1
    beq !cs_dy_neg+
    lda #1
    jmp !cs_dy_set+
!cs_dy_neg:
    lda #$ff
!cs_dy_set:
    sta dg_room_h

!cs_walk:
    // Walk 20-49 steps: rng_range(30) + 20
    lda #30
    jsr rng_range
    clc
    adc #20
    sta dg_retries              // Step counter

!cs_step:
    // Bounds check
    lda dg_cx1
    cmp #1
    bcc !cs_oob+
    cmp #MAP_COLS - 1
    bcs !cs_oob+
    lda dg_cy1
    cmp #1
    bcc !cs_oob+
    cmp #MAP_ROWS - 1
    bcc !cs_in_bounds+
!cs_oob:
    jmp !cs_end+
!cs_in_bounds:

    // Write mineral tile — only overwrite wall tiles (types 1-6)
    // Matches umoria: streamers replace granite but never floors,
    // corridors, doors, stairs, or other non-wall tiles.
    ldx dg_cy1
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy dg_cx1
    :MapRead_ptr0_y()             // Read existing tile
    tax                         // Save full byte
    and #TILE_TYPE_MASK         // Extract type nibble
    beq !cs_no_write+           // $00 = floor — skip
    cmp #TILE_DOOR_OPEN         // $70 = first non-wall type
    bcs !cs_no_write+           // Types 7-15 — skip
    // Types 1-6 ($10-$60) are wall tiles — skip if room wall (FLAG_LIT)
    txa
    and #FLAG_LIT
    bne !cs_no_write+           // Room wall → preserve
    // Regular rock → overwrite with mineral
    lda dg_room_w               // Mineral tile value
    :MapWrite_ptr0_y()
    // Treasure roll: 1-in-90 for magma, 1-in-40 for quartz
    lda dg_room_w
    and #TILE_TYPE_MASK
    cmp #TILE_QUARTZ
    beq !cs_quartz_roll+
    lda #90                     // Magma: 1-in-90
    .byte $2c                   // BIT abs — skip next 2 bytes
!cs_quartz_roll:
    lda #40                     // Quartz: 1-in-40
    jsr rng_range               // A = rng(chance), Y preserved
    bne !cs_no_write+           // Treasure only if A == 0
    :MapRead_ptr0_y()
    ora #FLAG_HAS_ITEM          // Set treasure flag on vein tile
    :MapWrite_ptr0_y()
!cs_no_write:

    // Advance position with jitter
    // x += dx, with 25% chance of jitter on y
    lda dg_cx1
    clc
    adc dg_room_x               // dx
    sta dg_cx1

    lda dg_cy1
    clc
    adc dg_room_h               // dy
    sta dg_cy1

    // 25% jitter: randomly shift x or y by 1
    jsr rng_byte
    and #3
    cmp #0
    bne !cs_no_jitter+
    // Jitter x by +/-1
    jsr rng_byte
    and #2
    sec
    sbc #1                      // -1 or +1
    clc
    adc dg_cx1
    sta dg_cx1
!cs_no_jitter:

    dec dg_retries
    beq !cs_end+
    jmp !cs_step-

!cs_end:
    rts

// ============================================================
// verify_stairs — Ensure all 3 stair tiles still exist after streamers
// Re-place any that were overwritten
// ============================================================
verify_stairs:
    // Check stairs up
    lda stairs_up_x
    ldy stairs_up_y
    jsr write_tile_at_xy
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_UP
    beq !vs_dn1+
    lda #TILE_STAIRS_UP | DUNGEON_FLAGS
    :MapWrite_ptr0_y()

!vs_dn1:
    lda stairs_dn1_x
    ldy stairs_dn1_y
    jsr write_tile_at_xy
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !vs_dn2+
    lda #TILE_STAIRS_DN | DUNGEON_FLAGS
    :MapWrite_ptr0_y()

!vs_dn2:
    lda stairs_dn2_x
    ldy stairs_dn2_y
    jsr write_tile_at_xy
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !vs_done+
    lda #TILE_STAIRS_DN | DUNGEON_FLAGS
    :MapWrite_ptr0_y()

!vs_done:
    rts

// ============================================================
// verify_connectivity — BFS flood-fill to ensure all rooms reachable
// Starts from stairs_up position, floods through passable tiles.
// Checks that every room has at least one reachable interior tile.
// Output: carry set = failed (unreachable room), carry clear = OK
// Uses: BFS queue at $0400 (screen RAM — safe, screen redrawn after generation)
// ============================================================
.const BFS_QUEUE = $0400
.const BFS_QUEUE_MAX = 512         // Max queue entries (×2 bytes = 1024, fits $0400–$07FF)

verify_connectivity:
    php                          // Save interrupt state — caller may already be in sei context
    sei                          // Disable IRQ — cursor blink writes to $0400 (BFS queue)
    // --- Step 1: Clear FLAG_OCCUPIED on all map tiles ---
    // We reuse bit 0 as "visited" marker for BFS
    lda #~FLAG_OCCUPIED & $ff
    jsr map_bulk_and_all

    // --- Step 2: BFS from stairs_up position ---
    // Queue head/tail as 16-bit indices into BFS_QUEUE
    lda #0
    sta bfs_head_lo
    sta bfs_head_hi
    sta bfs_tail_lo
    sta bfs_tail_hi

    // Enqueue start position (stairs_up_x, stairs_up_y) and mark visited
    lda stairs_up_x
    sta bfs_cur_x
    lda stairs_up_y
    sta bfs_cur_y

    // Mark start tile as visited
    ldx bfs_cur_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy bfs_cur_x
    :MapRead_ptr0_y()
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()

    jsr bfs_enqueue

!bfs_loop:
    // Check if queue empty: head == tail
    lda bfs_head_lo
    cmp bfs_tail_lo
    bne !bfs_not_empty+
    lda bfs_head_hi
    cmp bfs_tail_hi
    beq !bfs_done+
!bfs_not_empty:

    // Dequeue (x, y) from head
    jsr bfs_dequeue

    // Try 4 cardinal neighbors: N, S, W, E
    // North (y-1)
    lda bfs_cur_y
    beq !bfs_skip_n+            // y=0, skip
    sec
    sbc #1
    sta bfs_nb_y
    lda bfs_cur_x
    sta bfs_nb_x
    jsr bfs_try_neighbor
!bfs_skip_n:

    // South (y+1)
    lda bfs_cur_y
    cmp #MAP_ROWS - 1
    bcs !bfs_skip_s+
    clc
    adc #1
    sta bfs_nb_y
    lda bfs_cur_x
    sta bfs_nb_x
    jsr bfs_try_neighbor
!bfs_skip_s:

    // West (x-1)
    lda bfs_cur_x
    beq !bfs_skip_w+
    sec
    sbc #1
    sta bfs_nb_x
    lda bfs_cur_y
    sta bfs_nb_y
    jsr bfs_try_neighbor
!bfs_skip_w:

    // East (x+1)
    lda bfs_cur_x
    cmp #MAP_COLS - 1
    bcs !bfs_skip_e+
    clc
    adc #1
    sta bfs_nb_x
    lda bfs_cur_y
    sta bfs_nb_y
    jsr bfs_try_neighbor
!bfs_skip_e:

    jmp !bfs_loop-

!bfs_done:
    // --- Step 3: Check each room has a reachable floor tile ---
    ldx #0
!vc_check_room:
    cpx room_count
    bcs !vc_all_ok+

    // Check interior tile at (room_x[i], room_y[i])
    stx bfs_cur_x               // Save room index (reuse scratch)
    ldy room_y,x
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy room_x,x
    :MapRead_ptr0_y()
    and #FLAG_OCCUPIED
    beq !vc_unreachable+         // Not reached by BFS → fail

    ldx bfs_cur_x               // Restore room index
    inx
    jmp !vc_check_room-

!vc_all_ok:
    // --- Step 4: Clean up FLAG_OCCUPIED from all tiles ---
    jsr vc_cleanup
    plp                          // Restore interrupt state (plp overwrites carry, so set it after)
    clc                          // carry clear = all rooms reachable
    rts

!vc_unreachable:
    jsr vc_cleanup
    plp                          // Restore interrupt state
    sec                          // carry set = unreachable room found
    rts

// vc_cleanup — Clear FLAG_OCCUPIED from entire map
vc_cleanup:
    lda #~FLAG_OCCUPIED & $ff
    jmp map_bulk_and_all

// bfs_try_neighbor — Check neighbor tile, enqueue if passable and unvisited
// Input: bfs_nb_x, bfs_nb_y = neighbor coordinates
bfs_try_neighbor:
    ldx bfs_nb_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy bfs_nb_x
    :MapRead_ptr0_y()

    // Already visited?
    tax
    and #FLAG_OCCUPIED
    bne !btn_skip+               // Already in BFS set

    // Check if passable: floor, door (open/closed), stairs, rubble, trap
    txa
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !btn_passable+
    cmp #TILE_DOOR_OPEN
    beq !btn_passable+
    cmp #TILE_DOOR_CLOSED
    beq !btn_passable+
    cmp #TILE_STAIRS_DN
    beq !btn_passable+
    cmp #TILE_STAIRS_UP
    beq !btn_passable+
    cmp #TILE_RUBBLE
    beq !btn_passable+
    cmp #TILE_TRAP
    beq !btn_passable+
    cmp #TILE_SECRET
    beq !btn_passable+           // Secret doors are passage points

    // Not passable
!btn_skip:
    rts

!btn_passable:
    // Mark as visited
    txa                          // Full tile byte (without OCCUPIED)
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()

    // Enqueue this neighbor (uses bfs_nb_x/bfs_nb_y directly)
    jsr bfs_enqueue_nb
    rts

// bfs_enqueue — Add (bfs_cur_x, bfs_cur_y) to BFS queue at tail
bfs_enqueue:
    lda bfs_cur_x
    sta bfs_eq_x
    lda bfs_cur_y
    sta bfs_eq_y
    jmp bfs_enqueue_do

// bfs_enqueue_nb — Add (bfs_nb_x, bfs_nb_y) to BFS queue at tail
bfs_enqueue_nb:
    lda bfs_nb_x
    sta bfs_eq_x
    lda bfs_nb_y
    sta bfs_eq_y

bfs_enqueue_do:
    // Bounds check: drop entry if queue is full
    lda bfs_tail_hi
    cmp #>BFS_QUEUE_MAX
    bcc !bfe_ok+
    bne !bfe_full+
    lda bfs_tail_lo
    cmp #<BFS_QUEUE_MAX
    bcc !bfe_ok+
!bfe_full:
    rts
!bfe_ok:

    // Address = BFS_QUEUE + tail * 2
    lda bfs_tail_lo
    asl
    sta zp_ptr1
    lda bfs_tail_hi
    rol
    clc
    adc #>BFS_QUEUE
    sta zp_ptr1_hi

    ldy #0
    lda bfs_eq_x
    sta (zp_ptr1),y
    iny
    lda bfs_eq_y
    sta (zp_ptr1),y

    // Increment tail
    inc bfs_tail_lo
    bne !bfe_done+
    inc bfs_tail_hi
!bfe_done:
    rts

bfs_eq_x: .byte 0
bfs_eq_y: .byte 0

// bfs_dequeue — Remove (x, y) from BFS queue at head → bfs_cur_x/y
bfs_dequeue:
    // Address = BFS_QUEUE + head * 2
    lda bfs_head_lo
    asl
    sta zp_ptr1
    lda bfs_head_hi
    rol
    clc
    adc #>BFS_QUEUE
    sta zp_ptr1_hi

    ldy #0
    lda (zp_ptr1),y
    sta bfs_cur_x
    iny
    lda (zp_ptr1),y
    sta bfs_cur_y

    // Increment head
    inc bfs_head_lo
    bne !bfd_done+
    inc bfs_head_hi
!bfd_done:
    rts

// BFS scratch variables
bfs_head_lo: .byte 0
bfs_head_hi: .byte 0
bfs_tail_lo: .byte 0
bfs_tail_hi: .byte 0
bfs_cur_x:   .byte 0
bfs_cur_y:   .byte 0
bfs_nb_x:    .byte 0
bfs_nb_y:    .byte 0

// ============================================================
// position_player_dungeon — Place player at appropriate stairs
// ============================================================
position_player_dungeon:
    lda level_entry_dir
    bne !ascended+

    // Descended — place at stairs up (where player came from)
    lda stairs_up_x
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda stairs_up_y
    sta zp_player_y
    sta player_data + PL_MAP_Y
    rts

!ascended:
    // Ascended — place at stairs down 1
    lda stairs_dn1_x
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda stairs_dn1_y
    sta zp_player_y
    sta player_data + PL_MAP_Y
    rts

// ============================================================
// Compile-time validation (dungeon)
// ============================================================
.assert "MAX_ROOMS", MAX_ROOMS, 8
.assert "TILE_WALL_H = $10", TILE_WALL_H, $10
.assert "DUNGEON_FLAGS = $08", DUNGEON_FLAGS, $08
