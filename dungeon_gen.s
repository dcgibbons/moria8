// dungeon_gen.s — Town map generation
//
// Populates the 3,840-byte map at $C000-$CEFF (80x48 tiles, 1 byte/tile).
// Each map byte: bits 7-4 = tile type (0-15), bits 3-0 = flags.
//
// Tile types (pre-shifted values for upper nibble):
//   $00 = floor, $10 = wall horiz, $20 = wall vert, $30 = corner TL,
//   $40 = corner TR, $50 = corner BL, $60 = corner BR,
//   $70 = door open, $80 = door closed, $90 = stairs down,
//   $A0 = stairs up, $B0 = rubble, $C0 = magma, $D0 = quartz,
//   $E0 = trap, $F0 = secret door
//
// Flag bits (lower nibble):
//   Bit 3 = LIT (tile is illuminated)
//   Bit 2 = VISITED (player has seen this tile)
//   Bit 1 = OCCUPIED (monster on tile)
//   Bit 0 = HAS_ITEM (item on tile)

// ============================================================
// Constants
// ============================================================
.const MAP_COLS     = 80
.const MAP_ROWS     = 48
.const MAP_SIZE     = MAP_COLS * MAP_ROWS  // 3840

// Tile type values (upper nibble)
.const TILE_FLOOR   = $00
.const TILE_WALL_H  = $10
.const TILE_WALL_V  = $20
.const TILE_CORNER_TL = $30
.const TILE_CORNER_TR = $40
.const TILE_CORNER_BL = $50
.const TILE_CORNER_BR = $60
.const TILE_DOOR_OPEN = $70
.const TILE_DOOR_CLOSED = $80
.const TILE_STAIRS_DN = $90
.const TILE_STAIRS_UP = $A0
.const TILE_RUBBLE  = $B0
.const TILE_MAGMA   = $C0
.const TILE_QUARTZ  = $D0
.const TILE_TRAP    = $E0
.const TILE_SECRET  = $F0

// Flag bits (lower nibble)
.const FLAG_HAS_ITEM = $01
.const FLAG_OCCUPIED = $02
.const FLAG_VISITED  = $04
.const FLAG_LIT      = $08

// Town flags: all tiles are lit and visited
.const TOWN_FLAGS    = FLAG_LIT | FLAG_VISITED  // $0C

// Number of stores in the town
.const STORE_COUNT   = 6

// Tile type mask (for extracting type from map byte)
.const TILE_TYPE_MASK = $F0
.const TILE_FLAG_MASK = $0F

// ============================================================
// Pre-computed row address table (80 bytes per row, base $C000)
// map_row_lo[n] / map_row_hi[n] = $C000 + n*80
// ============================================================
map_row_lo:
    .fill MAP_ROWS, <(MAP_BASE + i * MAP_COLS)
map_row_hi:
    .fill MAP_ROWS, >(MAP_BASE + i * MAP_COLS)

// ============================================================
// Store position data
// ============================================================
// Store top-left corners (x, y) — 2 rows of 3 stores
store_pos_x:
    .byte 5, 20, 55, 5, 20, 55
store_pos_y:
    .byte 3,  3,  3, 20, 20, 20

// Store sizes (all 10 wide x 5 tall)
.const STORE_W = 10
.const STORE_H = 5

// Store door positions (center of south wall)
store_door_x:
    .byte 10, 25, 60, 10, 25, 60
store_door_y:
    .byte  7,  7,  7, 24, 24, 24

// ============================================================
// Subroutines
// ============================================================

// town_generate — Build the town level map
// Fills map at $C000 with floor, outer walls, 6 stores, stairs.
// Sets player start position.
// Preserves: nothing
town_generate:
    // --- Step 1: Fill entire map with floor + TOWN_FLAGS ---
    lda #TILE_FLOOR | TOWN_FLAGS    // $0C
    ldx #0
!fill_page0:
    sta MAP_BASE,x
    sta MAP_BASE + $100,x
    sta MAP_BASE + $200,x
    sta MAP_BASE + $300,x
    sta MAP_BASE + $400,x
    sta MAP_BASE + $500,x
    sta MAP_BASE + $600,x
    sta MAP_BASE + $700,x
    sta MAP_BASE + $800,x
    sta MAP_BASE + $900,x
    sta MAP_BASE + $a00,x
    sta MAP_BASE + $b00,x
    sta MAP_BASE + $c00,x
    sta MAP_BASE + $d00,x
    sta MAP_BASE + $e00,x
    inx
    bne !fill_page0-

    // --- Step 2: Draw outer boundary walls ---
    // Top wall (row 0): horizontal walls with corners
    lda map_row_lo + 0
    sta zp_ptr0
    lda map_row_hi + 0
    sta zp_ptr0_hi
    // Top-left corner
    lda #TILE_CORNER_TL | TOWN_FLAGS
    ldy #0
    sta (zp_ptr0),y
    // Top-right corner
    lda #TILE_CORNER_TR | TOWN_FLAGS
    ldy #MAP_COLS - 1
    sta (zp_ptr0),y
    // Horizontal wall between corners
    lda #TILE_WALL_H | TOWN_FLAGS
    ldy #1
!top_wall:
    sta (zp_ptr0),y
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
    sta (zp_ptr0),y
    // Bottom-right corner
    lda #TILE_CORNER_BR | TOWN_FLAGS
    ldy #MAP_COLS - 1
    sta (zp_ptr0),y
    // Horizontal wall between corners
    lda #TILE_WALL_H | TOWN_FLAGS
    ldy #1
!bot_wall:
    sta (zp_ptr0),y
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
    sta (zp_ptr0),y
    // Right wall (col 79)
    ldy #MAP_COLS - 1
    sta (zp_ptr0),y
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
    sta (zp_ptr0),y

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
    sta (zp_ptr0),y

    // Top-right corner
    ldy zp_temp3
    lda #TILE_CORNER_TR | TOWN_FLAGS
    sta (zp_ptr0),y

    // Top horizontal wall
    ldy zp_temp1
    iny                 // Start at left+1
    lda #TILE_WALL_H | TOWN_FLAGS
!top_h:
    sta (zp_ptr0),y
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
    sta (zp_ptr0),y

    // Bottom-right corner
    ldy zp_temp3
    lda #TILE_CORNER_BR | TOWN_FLAGS
    sta (zp_ptr0),y

    // Bottom horizontal wall (with door gap)
    ldy zp_temp1
    iny
    lda #TILE_WALL_H | TOWN_FLAGS
!bot_h:
    sta (zp_ptr0),y
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
    sta (zp_ptr0),y
    // Right wall
    ldy zp_temp3
    sta (zp_ptr0),y
    // Fill interior with floor (already floor, but ensure correct flags)
    ldy zp_temp1
    iny
    lda #TILE_FLOOR | TOWN_FLAGS
!interior:
    sta (zp_ptr0),y
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
    sta (zp_ptr0),y

    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Map row table size", map_row_hi - map_row_lo, MAP_ROWS
.assert "Map size = 3840", MAP_SIZE, 3840
.assert "Town flags = $0C", TOWN_FLAGS, $0c
.assert "Store count", STORE_COUNT, 6
