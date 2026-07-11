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

// town_generate — Build the shared 66x22 town inside the live map.
// Fills the backing map with blocking town walls first, then carves the
// playable town rectangle, outer walls, 8 stores, and stairs.
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
    // --- Step 1: Fill the live map with blocking unseen walls ---
    // Only the carved town rectangle should be lit/visited. The backing map
    // outside town must stay hidden so larger platform maps do not leak
    // visible wall slabs into the viewport.
    lda #TILE_WALL_H
    jsr map_bulk_fill_all

    // --- Step 2: Carve the fixed 66x22 town floor rectangle ---
    ldx #0
!town_floor_rows:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
    lda #TILE_FLOOR | TOWN_FLAGS
!town_floor_cols:
    :MapWrite_ptr0_y()
    iny
    cpy #TOWN_MAP_COLS
    bne !town_floor_cols-
    inx
    cpx #TOWN_MAP_ROWS
    bne !town_floor_rows-

    // --- Step 3: Draw outer boundary walls ---
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
    ldy #TOWN_MAP_COLS - 1
    :MapWrite_ptr0_y()
    // Horizontal wall between corners
    lda #TILE_WALL_H | TOWN_FLAGS
    ldy #1
!top_wall:
    :MapWrite_ptr0_y()
    iny
    cpy #TOWN_MAP_COLS - 1
    bne !top_wall-

    // Bottom wall: horizontal walls with corners
    lda map_row_lo + TOWN_MAP_ROWS - 1
    sta zp_ptr0
    lda map_row_hi + TOWN_MAP_ROWS - 1
    sta zp_ptr0_hi
    // Bottom-left corner
    lda #TILE_CORNER_BL | TOWN_FLAGS
    ldy #0
    :MapWrite_ptr0_y()
    // Bottom-right corner
    lda #TILE_CORNER_BR | TOWN_FLAGS
    ldy #TOWN_MAP_COLS - 1
    :MapWrite_ptr0_y()
    // Horizontal wall between corners
    lda #TILE_WALL_H | TOWN_FLAGS
    ldy #1
!bot_wall:
    :MapWrite_ptr0_y()
    iny
    cpy #TOWN_MAP_COLS - 1
    bne !bot_wall-

    // Left and right walls (interior rows)
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
    // Right wall (last town column)
    ldy #TOWN_MAP_COLS - 1
    :MapWrite_ptr0_y()
    inx
    cpx #TOWN_MAP_ROWS - 1
    bne !side_walls-

    // --- Step 4: Place 8 store buildings ---
    ldx #0              // Store index
!store_loop:
    stx zp_temp0        // Save store index
    jsr draw_store
    ldx zp_temp0
    inx
    cpx #STORE_COUNT
    bne !store_loop-

    // --- Step 5: Place stairs down near the lower center ---
    lda map_row_lo + TOWN_STAIRS_Y
    sta zp_ptr0
    lda map_row_hi + TOWN_STAIRS_Y
    sta zp_ptr0_hi
    lda #TILE_STAIRS_DN | TOWN_FLAGS
    ldy #TOWN_STAIRS_X
    :MapWrite_ptr0_y()

    // --- Step 6: Set player start left of the town stairs ---
    lda #TOWN_START_X
    sta player_data + PL_MAP_X
    sta zp_player_x
    lda #TOWN_START_Y
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
.const STAIR_PLACE_TRIES = 96   // Global attempts per stair before fallback
.const DUN_PANEL_W      = 66    // Upstream screen-width panel
.const DUN_PANEL_H      = 22    // Upstream screen-height panel
.const ROOM_SLOT_X_STEP = DUN_PANEL_W / 2
.const ROOM_SLOT_Y_STEP = DUN_PANEL_H / 2
.const ROOM_SLOT_X_BASE = DUN_PANEL_W / 4
.const ROOM_SLOT_Y_BASE = DUN_PANEL_H / 4
.const ROOM_SLOT_COLS   = 2 * floor(MAP_COLS / DUN_PANEL_W)
.const ROOM_SLOT_ROWS   = 2 * floor(MAP_ROWS / DUN_PANEL_H)
.const ROOM_SLOT_COUNT  = ROOM_SLOT_COLS * ROOM_SLOT_ROWS
.const ROOM_SLOT_STRIDE = ROOM_SLOT_COLS + 1
.const DUN_ROOM_ROLLS   = 32    // Upstream dun_roo_mea
.const STREAMER_DENSITY   = 5
.const DUN_TUNNELING    = 15    // VMS dun_tun_con
.const DUN_DIR_CHANGE   = 70    // VMS dun_tun_chg
.const DUN_RANDOM_DIR   = 36    // VMS dun_tun_rnd
.const DUN_ROOM_DOORS   = 25    // VMS dun_tun_pen
.const DUN_TUNNEL_DOORS = 15    // VMS dun_tun_jct
.const DGEN_CORR        = FLAG_OCCUPIED
.const DGEN_TUNNEL      = FLAG_VISITED
.const DGEN_JUNCTION    = FLAG_OCCUPIED | FLAG_HAS_ITEM

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
dg_tun_dir:  .byte 0   // 1=horizontal step, 2=vertical step
dg_conn_i:   .byte 0   // Current room being connected
dg_stop_flag:      .byte 0
dg_door_flag:      .byte 0
dg_slot_count:     .byte 0
dg_tun_steps:      .byte 0

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
// VMS order: blank cave, rooms, shuffled staged tunnels, fill granite,
// streamers, boundary, junction doors, stairs/features.
// ============================================================
dungeon_generate:
    lda #0
    sta trap_count
    jsr blank_cave
    jsr place_rooms
    jsr shuffle_rooms
    jsr connect_rooms
    jsr fill_cave_granite
    jsr place_streamers
    jsr place_junction_doors
    jsr tramp_assign_special_room   // Existing port special-room model.
    jsr tramp_vault_seal_entrance   // Seal vault entrance with secret door
    jsr place_stairs_dungeon
    jsr place_traps
    jsr place_secrets
    jsr darken_rooms            // Strip FLAG_LIT from dark rooms (after all generation)
    jsr position_player_dungeon
    rts

// ============================================================
// place_traps — Place hidden traps on the dungeon floor
// Called from dungeon_generate after place_doors.
// Number of traps: rng_range(dlvl+1) + 2, capped at MAX_TRAPS.
// Traps placed at random floor tiles (corridors or rooms).
// ============================================================
place_traps:
    // Don't place traps on town level
    lda zp_player_dlvl
    bne !not_town+
    rts
!not_town:
    // Number of traps = rng_range(dlvl+1) + 2
    lda zp_player_dlvl
    clc
    adc #1
    cmp #MAX_TRAPS
    bcc !cap_ok+
    lda #MAX_TRAPS
!cap_ok:
    jsr rng_range           // [0, dlvl]
    clc
    adc #2                  // [2, dlvl+2]
    cmp #MAX_TRAPS + 1
    bcc !count_ok+
    lda #MAX_TRAPS
!count_ok:
    sta trap_count

    lda #0
    sta dg_idx              // Reuse dungeon gen scratch as trap index

!pt_loop:
    lda dg_idx
    cmp trap_count
    beq !pt_done+

    // Find a random floor tile
    jsr find_random_floor
    bcc !pt_finalize+

    // Store in trap table
    ldx dg_idx
    lda df_target_x
    sta trap_x,x
    lda df_target_y
    sta trap_y,x

    // Random trap type: rng_range(TRAP_TYPE_COUNT)
    lda #TRAP_TYPE_COUNT
    jsr rng_range
    ldx dg_idx
    sta trap_type,x

    inc dg_idx
    jmp !pt_loop-

!pt_finalize:
    lda dg_idx
    sta trap_count
!pt_done:
    rts

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

blank_cave:
    lda #TILE_FLOOR             // Generation null/open cave.
    jmp map_bulk_fill_all

// Convert generation scratch after all tunnels have been materialized:
//   $00 blank cave       -> granite
//   floor|OCCUPIED      -> corridor floor
//   floor|OCC|HAS_ITEM  -> junction candidate for place_junction_doors
//   wall|OCCUPIED       -> protected room wall; clear the temporary guard
fill_cave_granite:
    ldx #0
!fcg_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
!fcg_col:
    :MapRead_ptr0_y()
    sta vc_tile
    beq !fcg_rock+
    cmp #DGEN_CORR
    beq !fcg_floor+
    cmp #DGEN_JUNCTION
    beq !fcg_keep_junction+
    lda vc_tile
    and #(FLAG_OCCUPIED | FLAG_HAS_ITEM)
    cmp #FLAG_OCCUPIED
    bne !fcg_next+
    lda vc_tile
    and #~FLAG_OCCUPIED & $ff
    :MapWrite_ptr0_y()
    jmp !fcg_next+
!fcg_rock:
    lda #TILE_WALL_H
    :MapWrite_ptr0_y()
    jmp !fcg_next+
!fcg_floor:
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    jmp !fcg_next+
!fcg_keep_junction:
    lda #FLAG_HAS_ITEM
    :MapWrite_ptr0_y()
!fcg_next:
    iny
    cpy #MAP_COLS
    bne !fcg_col-
    inx
    cpx #MAP_ROWS
    bne !fcg_row-
    rts

// ============================================================
// place_rooms — Place upstream-style rooms in platform-sized panels
// ============================================================
place_rooms:
    lda #0
    sta room_count
    ldx #0
!clear_slots:
    sta room_slot_selected,x
    inx
    cpx #ROOM_SLOT_COUNT
    bne !clear_slots-

    lda #0
    sta dg_slot_count
    lda #DUN_ROOM_ROLLS
    sta dg_retries
!select_slot:
    lda #ROOM_SLOT_COUNT
    jsr rng_range
    tax
    lda room_slot_selected,x
    bne !select_slot_next+
    lda dg_slot_count
    cmp #MAX_ROOMS
    beq !select_slot_next+
    inc room_slot_selected,x
    inc dg_slot_count
!select_slot_next:
    dec dg_retries
    bne !select_slot-

    lda #0
    sta dg_idx
    sta dg_slot_scan
!room_loop:
    ldx dg_slot_scan
    lda room_slot_selected,x
    bne !place_slot+
    jmp !skip_slot+
!place_slot:
    lda room_slot_center_x,x
    sta dg_cx1
    lda room_slot_center_y,x
    sta dg_cy1

    // Match upstream build_room draw order and independent extents.
    lda #25
    jsr rng_range
    clc
    adc #1
    cmp zp_player_dlvl
    ldx room_count
    lda #0
    bcc !room_dark+
    lda #1
!room_dark:
    sta room_lit,x

    lda #4
    jsr rng_range
    clc
    adc #1
    sta dg_room_h               // top extent, 1..4
    lda dg_cy1
    sec
    sbc dg_room_h
    sta dg_room_y

    lda #3
    jsr rng_range
    clc
    adc #2                      // bottom extent + inclusive center
    adc dg_room_h
    sta dg_room_h               // interior height, 3..8

    lda #11
    jsr rng_range
    clc
    adc #1
    sta dg_room_w               // left extent, 1..11
    lda dg_cx1
    sec
    sbc dg_room_w
    sta dg_room_x

    lda #11
    jsr rng_range
    clc
    adc #2                      // right extent + inclusive center
    adc dg_room_w
    sta dg_room_w               // interior width, 3..23

    ldx room_count
    lda dg_room_x
    sta room_x,x
    lda dg_room_y
    sta room_y,x
    lda dg_room_w
    sta room_w,x
    lda dg_room_h
    sta room_h,x
    lda dg_slot_scan
    sta room_type,x             // Temporary slot id; assign_special_room clears it.

    jsr draw_dungeon_room

    inc room_count
!skip_slot:
    lda dg_slot_scan
    clc
    adc #ROOM_SLOT_STRIDE
    cmp #ROOM_SLOT_COUNT
    bcc !slot_scan_ok+
    sbc #ROOM_SLOT_COUNT
!slot_scan_ok:
    sta dg_slot_scan
    inc dg_idx
    lda dg_idx
    cmp #ROOM_SLOT_COUNT
    beq !rooms_done+
    lda room_count
    cmp #MAX_ROOMS
    bne !more_slots+
    jmp !rooms_done+
!more_slots:
    jmp !room_loop-
!rooms_done:
    rts

room_slot_selected:
    .fill ROOM_SLOT_COUNT, 0
dg_slot_scan:
    .byte 0
room_slot_center_x:
    .fill ROOM_SLOT_COUNT, ROOM_SLOT_X_BASE + ((i - floor(i / ROOM_SLOT_COLS) * ROOM_SLOT_COLS) * ROOM_SLOT_X_STEP)
room_slot_center_y:
    .fill ROOM_SLOT_COUNT, ROOM_SLOT_Y_BASE + (floor(i / ROOM_SLOT_COLS) * ROOM_SLOT_Y_STEP)

// ============================================================
// check_room_overlap — Check if dg_room_* overlaps any placed room
// Output: carry set = overlap, carry clear = no overlap
// ============================================================
#if !C128 || C128_TEST_DUNGEON_OVERLAP
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
#endif

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

    // Swap room_lit[i] ↔ room_lit[j]
    lda room_lit,x
    pha
    lda room_lit,y
    sta room_lit,x
    pla
    sta room_lit,y

    // Swap room_type[i] ↔ room_type[j]
    lda room_type,x
    pha
    lda room_type,y
    sta room_type,x
    pla
    sta room_type,y

!shuf_skip:
    ldx shuf_i
    dex
    bne !shuf_loop-             // Continue while i > 0
!shuf_done:
    rts

shuf_i:     .byte 0
shuf_j_tmp: .byte 0

// ============================================================
// connect_rooms — Connect shuffled room centers as an upstream-style ring.
// ============================================================
connect_rooms:
    lda room_count
    cmp #2
    bcs !conn_start+
    rts
!conn_start:
    lda #1
    sta dg_conn_i

!conn_loop:
    ldx dg_conn_i
    jsr conn_room_center_to_start
    ldx dg_conn_i
    dex
    jsr conn_room_center_to_target
    jsr carve_staged_tunnel
    jsr materialize_staged_tunnel

	    inc dg_conn_i
	    lda dg_conn_i
	    cmp room_count
	    bne !conn_loop-

	    // Upstream copies room 0 to the end of the shuffled location list and
	    // tunnels once more from room 0 back to the last room.
	    ldx #0
	    jsr conn_room_center_to_start
	    ldx room_count
	    dex
	    jsr conn_room_center_to_target
	    jsr carve_staged_tunnel
	    jsr materialize_staged_tunnel
	    rts

conn_room_center_to_start:
    lda room_type,x
    tay
    lda room_slot_center_x,y
    sta dg_cx1
    lda room_slot_center_y,y
    sta dg_cy1
    rts

conn_room_center_to_target:
    lda room_type,x
    tay
    lda room_slot_center_x,y
    sta dg_cx2
    lda room_slot_center_y,y
    sta dg_cy2
    rts

// ============================================================
// carve_staged_tunnel — Walk one upstream-style tunnel, leaving temp markers.
// Input: dg_cx1/dg_cy1 = start, dg_cx2/dg_cy2 = end.
// ============================================================
carve_staged_tunnel:
	    lda #0
	    sta dg_tun_dir
	    sta dg_stop_flag
	    sta dg_door_flag
	    sta dg_tun_steps
!cst_loop:
    lda dg_cx1
    cmp dg_cx2
    bne !cst_not_done+
    lda dg_cy1
    cmp dg_cy2
    beq !cst_done+
	!cst_not_done:
	    lda dg_cx1
	    sta dg_room_x
	    lda dg_cy1
	    sta dg_room_y
	    jsr tunnel_step_toward
	    inc dg_tun_steps
	    jsr tunnel_stage_current
    lda dg_stop_flag
    bne !cst_done+
    jmp !cst_loop-
!cst_done:
    rts

// tunnel_step_toward — Advance dg_cx1/dg_cy1 one upstream-style cardinal step.
// Output: dg_tun_dir = 1 horizontal, 2 vertical.
tunnel_step_toward:
    lda dg_tun_dir
    beq tst_pick_correct
    lda #100
    jsr rng_range
    cmp #DUN_DIR_CHANGE
    bcs tst_random_or_correct

!tst_keep_dir:
    lda dg_tun_dir
    cmp #1
    beq !tst_keep_h+
    lda dg_cy1
    cmp dg_cy2
    bne !tst_vertical+
    jmp tst_pick_correct
!tst_keep_h:
    lda dg_cx1
    cmp dg_cx2
    beq tst_pick_correct
    jmp !tst_horizontal+

tst_pick_correct:
    lda dg_cx1
    cmp dg_cx2
    beq !tst_vertical+
    lda dg_cy1
    cmp dg_cy2
    beq !tst_horizontal+
    jsr rng_byte
    and #1
    beq !tst_horizontal+
    jmp !tst_vertical+

tst_random_or_correct:
    lda dg_cx1
    cmp #2
    bcc tst_pick_correct
    cmp #MAP_COLS - 2
    bcs tst_pick_correct
    lda dg_cy1
    cmp #2
    bcc tst_pick_correct
    cmp #MAP_ROWS - 2
    bcs tst_pick_correct
    lda #DUN_RANDOM_DIR
    jsr rng_range
    cmp #4
    bcs tst_pick_correct
    tax
    beq !tst_rand_up+
    dex
    beq !tst_rand_down+
    dex
    beq !tst_rand_left+
    lda #1
    sta dg_tun_dir
    inc dg_cx1
    rts
!tst_rand_left:
    lda #1
    sta dg_tun_dir
    dec dg_cx1
    rts
!tst_rand_up:
    lda #2
    sta dg_tun_dir
    dec dg_cy1
    rts
!tst_rand_down:
    lda #2
    sta dg_tun_dir
    inc dg_cy1
    rts

!tst_vertical:
    lda #2
    sta dg_tun_dir
    lda dg_cy1
    cmp dg_cy2
    bcc !tst_v_inc+
    dec dg_cy1
    rts
!tst_v_inc:
    inc dg_cy1
    rts

!tst_horizontal:
    lda #1
    sta dg_tun_dir
    lda dg_cx1
    cmp dg_cx2
    bcc !tst_h_inc+
    dec dg_cx1
    rts
!tst_h_inc:
    inc dg_cx1
    rts

// tunnel_stage_current — Apply one staged VMS tunnel step.
tunnel_stage_current:
    ldx dg_cy1
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy dg_cx1
    :MapRead_ptr0_y()
    sta dg_retries
    cmp #TILE_FLOOR
    beq !tsc_blank+
    cmp #DGEN_TUNNEL
    beq !tsc_done+
    cmp #DGEN_CORR
    beq !tsc_corr+
    cmp #DGEN_JUNCTION
    beq !tsc_corr+
    lda dg_retries
    and #(FLAG_OCCUPIED | FLAG_HAS_ITEM)
    cmp #FLAG_OCCUPIED
    beq !tsc_guarded_wall+
    lda dg_retries
    and #TILE_TYPE_MASK
    beq !tsc_done+              // Room floor or other floor flags.
    cmp #TILE_DOOR_OPEN
    bcs !tsc_done+
    lda dg_retries
    and #FLAG_LIT
    beq !tsc_blank+             // Unlit rock/null fill.
    jsr mark_staged_wall
    lda #0
    sta dg_door_flag
    rts
!tsc_blank:
    lda #DGEN_TUNNEL
    :MapWrite_ptr0_y()
    lda #0
    sta dg_door_flag
    rts
!tsc_corr:
    lda dg_door_flag
    bne !tsc_maybe_stop+
    lda dg_retries
    ora #FLAG_HAS_ITEM
    :MapWrite_ptr0_y()
    lda #1
    sta dg_door_flag
!tsc_maybe_stop:
	    lda #100
	    jsr rng_range
	    cmp #DUN_TUNNELING
	    bcc !tsc_done+
	    lda dg_tun_steps
	    cmp #11
	    bcc !tsc_done+
	    lda #1
	    sta dg_stop_flag
	    rts
!tsc_done:
	    rts
!tsc_guarded_wall:
    // Upstream temporary wall value 9 does not advance the tunnel cursor.
    // Preserve that behavior for neighboring room-wall guards.
    lda dg_room_x
    sta dg_cx1
    lda dg_room_y
    sta dg_cy1
    rts

mark_staged_wall:
    lda dg_retries
    ora #FLAG_HAS_ITEM
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    jsr mark_neighbor_walls_temp
    rts

mark_neighbor_walls_temp:
    lda dg_cy1
    sec
    sbc #1
    sta dg_room_y
!mnw_row:
    ldx dg_room_y
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi
    lda dg_cx1
    sec
    sbc #1
    sta dg_room_x
!mnw_col:
    ldy dg_room_x
    :MapRead_ptr1_y()
    jsr mnw_mark_if_lit_wall
    inc dg_room_x
    lda dg_room_x
    sec
    sbc dg_cx1
    cmp #2
    bcc !mnw_col-
    inc dg_room_y
    lda dg_room_y
    sec
    sbc dg_cy1
    cmp #2
    bcc !mnw_row-
    rts

mnw_mark_if_lit_wall:
    sta vc_tile
    and #TILE_TYPE_MASK
    beq !mnw_no+
    cmp #TILE_DOOR_OPEN
    bcs !mnw_no+
    lda vc_tile
    and #FLAG_LIT
    beq !mnw_no+
    lda vc_tile
    ora #FLAG_OCCUPIED
    :MapWrite_ptr1_y()
!mnw_no:
    rts

materialize_staged_tunnel:
    ldx #0
!mst_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
!mst_col:
    :MapRead_ptr0_y()
    sta vc_tile
    cmp #DGEN_TUNNEL
    beq !mst_tunnel+
    lda vc_tile
    and #TILE_TYPE_MASK
    beq !mst_next+
    cmp #TILE_DOOR_OPEN
    bcs !mst_next+
    lda vc_tile
    and #FLAG_HAS_ITEM
    bne !mst_candidate+
    jmp !mst_next+
!mst_tunnel:
    lda #DGEN_CORR
    :MapWrite_ptr0_y()
    jmp !mst_next+
!mst_candidate:
    stx dg_room_y
    sty dg_room_x
    lda #100
	    jsr rng_range
	    ldx dg_room_y
	    cmp #DUN_ROOM_DOORS
	    bcs !mst_candidate_floor+
	    lda vc_tile
	    and #TILE_TYPE_MASK
	    cmp #TILE_WALL_H
	    beq !mst_check_hwall+
	    cmp #TILE_WALL_V
	    bne !mst_candidate_floor+
	    jsr jdg_opposing_vertical
	    jmp !mst_checked_wall+
!mst_check_hwall:
	    jsr jdg_opposing_horizontal
!mst_checked_wall:
	    bcc !mst_candidate_floor+
	    jsr random_door_type
    ldx dg_room_y
    ldy dg_room_x
    :MapWrite_ptr0_y()
    jmp !mst_next+
!mst_candidate_floor:
    ldx dg_room_y
    ldy dg_room_x
    lda #DGEN_CORR
    :MapWrite_ptr0_y()
    jmp !mst_next+
	!mst_next:
	    iny
	    cpy #MAP_COLS
	    beq !mst_row_next+
	    jmp !mst_col-
!mst_row_next:
	    inx
	    cpx #MAP_ROWS
	    beq !mst_done+
	    jmp !mst_row-
!mst_done:
	    rts

// ============================================================
// carve_h_corridor — Carve horizontal corridor from cx1 to cx2 at row cy1
// Input: dg_cx1 = start x, dg_cx2 = end x, dg_cy1 = row y
// Always carves from smaller x to larger x using Y register.
// ============================================================
#if !C128 && C64_UNIT_TEST
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
#endif

// ============================================================
// random_door_type — Return a random supported door tile with DUNGEON_FLAGS
// Output: A = door tile value
// Clobbers: X (via rng_range)
// Preserves: Y
// Note: Upstream also has broken/locked/stuck door object states. This port's
//       tile model only stores open/closed/secret, so use that supported subset.
// ============================================================
random_door_type:
    lda #3
    jsr rng_range               // A = [0, 2]
    tax
    lda rdt_table,x
    rts

rdt_table:
    .byte TILE_SECRET | DUNGEON_FLAGS
    .byte TILE_DOOR_OPEN | DUNGEON_FLAGS
    .byte TILE_DOOR_CLOSED | DUNGEON_FLAGS

// ============================================================
// add_corridor_doors — Legacy no-op compatibility wrapper
// Original-style door placement happens during actual corridor penetration
// in tunnel_stage_current/materialize_staged_tunnel. We intentionally do NOT synthesize
// new room-entry doors just because a corridor floor happens to run alongside
// a room wall; that behavior created aggressive side-entry doors.
// ============================================================
#if !C128 && C64_UNIT_TEST
add_corridor_doors:
    rts
#endif

place_junction_doors:
    ldx #0
!pjd_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
!pjd_col:
    :MapRead_ptr0_y()
    sta vc_tile
    and #TILE_TYPE_MASK
    bne !pjd_next+
    lda vc_tile
    and #FLAG_HAS_ITEM
    beq !pjd_next+
    tya
    sta dg_cx1
    stx dg_cy1
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    lda #0
    sta dg_door_flag

    lda dg_cx1
    sec
    sbc #1
    sta dg_room_x
    lda dg_cy1
    sta dg_room_y
    jsr try_junction_door

    lda dg_cx1
    clc
    adc #1
    sta dg_room_x
    lda dg_cy1
    sta dg_room_y
    jsr try_junction_door

    lda dg_cx1
    sta dg_room_x
    lda dg_cy1
    sec
    sbc #1
    sta dg_room_y
    jsr try_junction_door

    lda dg_cx1
    sta dg_room_x
    lda dg_cy1
    clc
    adc #1
    sta dg_room_y
    jsr try_junction_door

    ldx dg_cy1
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy dg_cx1
!pjd_next:
    iny
    cpy #MAP_COLS
    bne !pjd_col-
    inx
    cpx #MAP_ROWS
    beq !pjd_done+
    jmp !pjd_row-
!pjd_done:
    rts

try_junction_door:
    lda dg_door_flag
    bne !tjd_no+
    lda dg_room_x
    cmp #1
    bcc !tjd_no+
    cmp #MAP_COLS - 1
    bcs !tjd_no+
    lda dg_room_y
    cmp #1
    bcc !tjd_no+
    cmp #MAP_ROWS - 1
    bcs !tjd_no+
    ldx dg_room_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy dg_room_x
    :MapRead_ptr0_y()
	// Upstream junction doors are placed only on corridor floor, never room
	// floor (which still carries FLAG_LIT at this stage).
    cmp #TILE_FLOOR
    bne !tjd_no+
	    lda #100
	    jsr rng_range
	    cmp #DUN_TUNNEL_DOORS
	    bcc !tjd_no+
    jsr junction_door_geometry_ok
    bcc !tjd_no+
    jsr random_door_type
    ldy dg_room_x
    :MapWrite_ptr0_y()
    inc dg_door_flag
!tjd_no:
    rts

junction_door_geometry_ok:
    // Straight east-west corridor through north/south wall jambs.
    jsr jdg_opposing_vertical
    bcc !jdg_try_vertical+
    jsr jdg_corridor_left_right
    bcs !jdg_yes+
!jdg_try_vertical:
    // Straight north-south corridor through west/east wall jambs.
    jsr jdg_opposing_horizontal
    bcc !jdg_no+
    jsr jdg_corridor_up_down
    bcs !jdg_yes+
!jdg_no:
    clc
    rts
!jdg_yes:
    sec
    rts

jdg_corridor_left_right:
    ldx dg_room_y
    ldy dg_room_x
    dey
    jsr jdg_cell_is_corridor
    bcc !jclr_no+
    ldx dg_room_y
    ldy dg_room_x
    iny
    jsr jdg_cell_is_corridor
    bcc !jclr_no+
    sec
    rts
!jclr_no:
    clc
    rts

jdg_corridor_up_down:
    ldx dg_room_y
    dex
    ldy dg_room_x
    jsr jdg_cell_is_corridor
    bcc !jcud_no+
    ldx dg_room_y
    inx
    ldy dg_room_x
    jsr jdg_cell_is_corridor
    bcc !jcud_no+
    sec
    rts
!jcud_no:
    clc
    rts

jdg_cell_is_corridor:
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi
    :MapRead_ptr1_y()
    cmp #TILE_FLOOR
    beq !jcic_yes+
    clc
    rts
!jcic_yes:
    sec
    rts

jdg_opposing_vertical:
    ldx dg_room_y
    dex
    ldy dg_room_x
    jsr jdg_cell_is_wall
    bcc !jov_no+
    ldx dg_room_y
    inx
    ldy dg_room_x
    jsr jdg_cell_is_wall
    bcc !jov_no+
    sec
    rts
!jov_no:
    clc
    rts

jdg_opposing_horizontal:
    ldx dg_room_y
    ldy dg_room_x
    dey
    jsr jdg_cell_is_wall
    bcc !joh_no+
    ldx dg_room_y
    ldy dg_room_x
    iny
    jsr jdg_cell_is_wall
    bcc !joh_no+
    sec
    rts
!joh_no:
    clc
    rts

jdg_cell_is_wall:
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi
    :MapRead_ptr1_y()
jdg_is_wall:
	    and #TILE_TYPE_MASK
	    cmp #TILE_WALL_H
	    beq !jiw_yes+
	    cmp #TILE_WALL_V
	    beq !jiw_yes+
!jiw_no:
	    clc
	    rts
!jiw_yes:
	    sec
	    rts

// ============================================================
// place_stairs_dungeon — Place the tracked 1 up-stairs + 2 down-stairs.
// Upstream places 1-2 up and 3-4 down stairs as objects. This port currently
// tracks only these three coordinates for save, detect-stairs, and level entry,
// so generation intentionally creates only tracked stairs.
// ============================================================
place_stairs_dungeon:
    lda #0
    sta stairs_up_x
    sta stairs_up_y
    sta stairs_dn1_x
    sta stairs_dn1_y
    sta stairs_dn2_x
    sta stairs_dn2_y

    ldx #0
    jsr random_wall_adj_stair_floor
    sta stairs_up_x
    sty stairs_up_y
    jsr write_tile_at_xy
    lda #TILE_STAIRS_UP | DUNGEON_FLAGS
    :MapWrite_ptr0_y()

    ldx #1
    jsr random_wall_adj_stair_floor
    sta stairs_dn1_x
    sty stairs_dn1_y
    jsr write_tile_at_xy
    lda #TILE_STAIRS_DN | DUNGEON_FLAGS
    :MapWrite_ptr0_y()

    ldx #2
    jsr random_wall_adj_stair_floor
    sta stairs_dn2_x
    sty stairs_dn2_y
    jsr write_tile_at_xy
    lda #TILE_STAIRS_DN | DUNGEON_FLAGS
    :MapWrite_ptr0_y()
    rts

.label rrd_start_x  = dg_cx2
.label rrd_start_y  = dg_cy2
.label rrd_target_x = dg_room_x
.label rrd_target_y = dg_room_y
.label rrd_min_x    = dg_room_w
.label rrd_max_x    = dg_room_h
.label rrd_min_y    = dg_retries
.label rrd_max_y    = dg_tun_dir

.label stair_room_idx       = dg_idx
.label stair_place_tries    = dg_retries
.label stair_wall_threshold = dg_tun_dir
.label stair_candidate_x    = dg_room_x
.label stair_candidate_y    = dg_room_y
.label stair_wall_count     = dg_room_w

.const STAIR_WALL_TRIES = 20

random_wall_adj_stair_floor:
	    stx stair_room_idx
	    cpx room_count
	    bcc !rwas_room_ok+
	    lda #0
	    sta stair_room_idx
!rwas_room_ok:
	    lda #3
	    sta stair_wall_threshold
!rwas_threshold:
    lda #STAIR_WALL_TRIES
    sta stair_place_tries
!rwas_try:
    ldx stair_room_idx
    jsr random_floor_in_room
    sta stair_candidate_x
    sty stair_candidate_y
    jsr stair_candidate_valid
    bcc !rwas_next+
    jsr count_stair_adj_walls
    cmp stair_wall_threshold
    bcs !rwas_found+
!rwas_next:
	    dec stair_place_tries
	    bne !rwas_try-
	    lda stair_wall_threshold
	    beq !rwas_fallback+
	    dec stair_wall_threshold
	    jmp !rwas_threshold-

!rwas_found:
	    lda stair_candidate_x
	    ldy stair_candidate_y
	    rts

!rwas_fallback:
	    ldx stair_room_idx
	    jsr random_floor_in_room
	    rts

stair_candidate_valid:
    lda stair_candidate_x
    ldy stair_candidate_y
    jsr write_tile_at_xy
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !scv_no+
    sec
    rts
!scv_no:
    clc
    rts

count_stair_adj_walls:
    lda #0
    sta stair_wall_count

    ldx stair_candidate_y
    dex
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy stair_candidate_x
    :MapRead_ptr0_y()
    jsr stair_count_wall

    ldx stair_candidate_y
    inx
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy stair_candidate_x
    :MapRead_ptr0_y()
    jsr stair_count_wall

    ldx stair_candidate_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy stair_candidate_x
    dey
    :MapRead_ptr0_y()
    jsr stair_count_wall

    ldy stair_candidate_x
    iny
    :MapRead_ptr0_y()
    jsr stair_count_wall

    lda stair_wall_count
    rts

stair_count_wall:
    tax
    and #TILE_TYPE_MASK
    beq !scw_no+
    cmp #TILE_DOOR_OPEN
    bcs !scw_no+
    txa
    and #FLAG_LIT
    beq !scw_no+
    inc stair_wall_count
!scw_no:
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
    lda #TILE_MAGMA
    sta dg_room_w
    jsr carve_streamer
    jsr carve_streamer
    jsr carve_streamer

    lda #TILE_QUARTZ
    sta dg_room_w
    jsr carve_streamer
    jsr carve_streamer
    rts

// ============================================================
// carve_streamer — Carve one mineral streamer across the map
// Input: dg_room_w = mineral tile type
// Matches upstream start/density/direction and walks until out of bounds.
// ============================================================
carve_streamer:
    // y = MAP_ROWS/2 + 10 - rng_range(23), matching upstream's
    // trunc(cur_height/2.0) + 11 - randint(23).
    lda #23
    jsr rng_range
    sta dg_retries
    lda #MAP_ROWS / 2 + 10
    sec
    sbc dg_retries
    sta dg_cy1

    // x = MAP_COLS/2 + 15 - rng_range(33), matching upstream's
    // trunc(cur_width/2.0) + 16 - randint(33).
    lda #33
    jsr rng_range
    sta dg_retries
    lda #MAP_COLS / 2 + 15
    sec
    sbc dg_retries
    sta dg_cx1

    jsr rng_byte
    and #7
    tax
    lda cs_dx_table,x
    sta dg_room_x
    lda cs_dy_table,x
    sta dg_room_h

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

    lda dg_cx1
    sta dg_cx2
    lda dg_cy1
    sta dg_cy2
    lda #STREAMER_DENSITY
    sta dg_tun_dir

!cs_stamp:
    lda #5
    jsr rng_range
    sec
    sbc #2
    clc
    adc dg_cx2
    sta dg_cx1

    lda #5
    jsr rng_range
    sec
    sbc #2
    clc
    adc dg_cy2
    sta dg_cy1

    lda dg_cx1
    cmp #1
    bcc !cs_no_write+
    cmp #MAP_COLS - 1
    bcs !cs_no_write+
    lda dg_cy1
    cmp #1
    bcc !cs_no_write+
    cmp #MAP_ROWS - 1
    bcs !cs_no_write+

    // Write mineral tile — only overwrite plain granite. Upstream checks
    // rock_wall1 exactly; in this port that is TILE_WALL_H with no flags.
    ldx dg_cy1
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy dg_cx1
    :MapRead_ptr0_y()
    cmp #TILE_WALL_H
    bne !cs_no_write+
    // Plain granite → overwrite with mineral.
    lda dg_room_w               // Mineral tile value
    :MapWrite_ptr0_y()
    // Treasure roll matches VMS-Moria constants: magma 1-in-95, quartz 1-in-55.
    lda dg_room_w
    and #TILE_TYPE_MASK
    cmp #TILE_QUARTZ
    beq !cs_quartz_roll+
    lda #95                     // Magma: 1-in-95
    .byte $2c                   // BIT abs — skip next 2 bytes
!cs_quartz_roll:
    lda #55                     // Quartz: 1-in-55
    jsr rng_range               // A = rng(chance), Y preserved
    bne !cs_no_write+           // Treasure only if A == 0
    :MapRead_ptr0_y()
    ora #FLAG_HAS_ITEM          // Set treasure flag on vein tile
    :MapWrite_ptr0_y()
!cs_no_write:

    dec dg_tun_dir
    beq !cs_stamp_done+
    jmp !cs_stamp-
!cs_stamp_done:

    lda dg_cx2
    sta dg_cx1
    lda dg_cy2
    sta dg_cy1

    // Advance position along the selected upstream direction.
    lda dg_cx1
    clc
    adc dg_room_x               // dx
    sta dg_cx1

    lda dg_cy1
    clc
    adc dg_room_h               // dy
    sta dg_cy1

    jmp !cs_step-

!cs_end:
    rts

cs_dx_table:
    .byte $ff, $00, $01, $ff, $01, $ff, $00, $01
cs_dy_table:
    .byte $ff, $ff, $ff, $00, $00, $01, $01, $01

#if !C128 && C64_UNIT_TEST
// ============================================================
// verify_connectivity — Flood-fill to ensure all rooms reachable
// Starts from stairs_up position, propagates visited marks through passable
// tiles. This deliberately uses repeated map scans instead of a queue so the
// C64 can keep the visible generation screen in $0400-$07ff.
// Checks that every room has at least one reachable interior tile.
// Output: carry set = failed (unreachable room), carry clear = OK
// ============================================================

verify_connectivity:
    php                          // Save interrupt state — caller may already be in sei context
    // --- Step 1: Clear FLAG_OCCUPIED on all map tiles ---
    // We reuse bit 0 as the flood-fill visited marker.
    lda #~FLAG_OCCUPIED & $ff
    jsr map_bulk_and_all

    // Mark start tile as visited
    ldx stairs_up_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy stairs_up_x
    :MapRead_ptr0_y()
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()

    // --- Step 2: Propagate visited marks until a full scan adds none. ---
!vc_pass:
    lda #0
    sta vc_changed
    sta bfs_cur_y
!vc_row:
    ldx bfs_cur_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    lda #0
    sta bfs_cur_x
!vc_col:
    ldy bfs_cur_x
    :MapRead_ptr0_y()
    sta vc_tile
    and #FLAG_OCCUPIED
    bne !vc_next_col+
    lda vc_tile
    jsr vc_tile_is_passable
    bcc !vc_next_col+
    jsr vc_has_visited_neighbor
    bcc !vc_next_col+
    ldy bfs_cur_x
    lda vc_tile
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    lda #1
    sta vc_changed
!vc_next_col:
    inc bfs_cur_x
    lda bfs_cur_x
    cmp #MAP_COLS
    bne !vc_col-
    inc bfs_cur_y
    lda bfs_cur_y
    cmp #MAP_ROWS
    bne !vc_row-
    lda vc_changed
    bne !vc_pass-

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
#endif

#if !C128 || C128_TEST_DUNGEON_OVERLAP
// vc_cleanup — Clear FLAG_OCCUPIED from entire map
vc_cleanup:
    lda #~FLAG_OCCUPIED & $ff
    jmp map_bulk_and_all

// vc_tile_is_passable — Carry set if A is a tile flood-fill may traverse.
vc_tile_is_passable:
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !passable+
    cmp #TILE_DOOR_OPEN
    beq !passable+
    cmp #TILE_DOOR_CLOSED
    beq !passable+
    cmp #TILE_STAIRS_DN
    beq !passable+
    cmp #TILE_STAIRS_UP
    beq !passable+
    cmp #TILE_RUBBLE
    beq !passable+
    cmp #TILE_TRAP
    beq !passable+
    cmp #TILE_SECRET
    beq !passable+
    clc
    rts
!passable:
    sec
    rts

// vc_has_visited_neighbor — Carry set if the current cell has a cardinal
// neighbor already marked with FLAG_OCCUPIED.
vc_has_visited_neighbor:
    lda bfs_cur_x
    beq !check_east+
    tay
    dey
    :MapRead_ptr0_y()
    and #FLAG_OCCUPIED
    bne !found+
!check_east:
    lda bfs_cur_x
    cmp #MAP_COLS - 1
    bcs !check_north+
    tay
    iny
    :MapRead_ptr0_y()
    and #FLAG_OCCUPIED
    bne !found+
!check_north:
    lda bfs_cur_y
    beq !check_south+
    tax
    dex
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi
    ldy bfs_cur_x
    :MapRead_ptr1_y()
    and #FLAG_OCCUPIED
    bne !found+
!check_south:
    lda bfs_cur_y
    cmp #MAP_ROWS - 1
    bcs !not_found+
    tax
    inx
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi
    ldy bfs_cur_x
    :MapRead_ptr1_y()
    and #FLAG_OCCUPIED
    bne !found+
!not_found:
    clc
    rts
!found:
    sec
    rts
#endif

// Connectivity scratch variables
bfs_cur_x:   .byte 0
bfs_cur_y:   .byte 0
vc_changed:  .byte 0
vc_tile:     .byte 0

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
#if C128
.assert "MAX_ROOMS", MAX_ROOMS, 21
#else
.assert "MAX_ROOMS", MAX_ROOMS, 8
#endif
.assert "TILE_WALL_H = $10", TILE_WALL_H, $10
.assert "DUNGEON_FLAGS = $08", DUNGEON_FLAGS, $08
