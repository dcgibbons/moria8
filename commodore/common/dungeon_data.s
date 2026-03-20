#importonce
// dungeon_data.s — Shared dungeon constants, tables, and variables
//
// Contains all data shared between dungeon_gen.s (generation overlay) and
// the rest of the game engine. Stays in the main segment so it is always
// accessible (map row table, room data, stairs coordinates, etc.).
//
// dungeon_gen.s (overlay) handles generation; all its private constants
// (STORE_W/H, ROOM_MIN/MAX, BFS_QUEUE) remain there.

// ============================================================
// Map constants
// ============================================================
.const C64_MAP_COLS = 80
.const C64_MAP_ROWS = 48
.const C128_MAP_COLS = 198
.const C128_MAP_ROWS = 66

#if C128
.const MAP_COLS     = C128_MAP_COLS
.const MAP_ROWS     = C128_MAP_ROWS
#else
.const MAP_COLS     = C64_MAP_COLS
.const MAP_ROWS     = C64_MAP_ROWS
#endif
.const MAP_SIZE     = MAP_COLS * MAP_ROWS

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
.const FLAG_OCCUPIED = $01  // Bit 0: creature present
.const FLAG_HAS_ITEM = $02  // Bit 1: treasure/item present
.const FLAG_VISITED  = $04  // Bit 2: player has seen this tile
.const FLAG_LIT      = $08  // Bit 3: tile is illuminated

// Town flags: all tiles are lit and visited
.const TOWN_FLAGS    = FLAG_LIT | FLAG_VISITED  // $0C

// Number of stores in the town
.const STORE_COUNT   = 8

// Tile type mask (for extracting type from map byte)
.const TILE_TYPE_MASK = $F0
.const TILE_FLAG_MASK = $0F

// ============================================================
// Dungeon room/generation constants (shared with other modules)
// ============================================================
.const MAX_ROOMS     = 8
.const DUNGEON_FLAGS = FLAG_LIT                  // $08 (rooms are lit)

// Special room type constants
.const RT_NORMAL = 0
.const RT_PIT    = 1
.const RT_VAULT  = 2
.const RT_NEST   = 3

// ============================================================
// Pre-computed row address table
// map_row_lo[n] / map_row_hi[n] = MAP_BASE + n*MAP_COLS
// ============================================================
map_row_lo:
    .fill MAP_ROWS, <(MAP_BASE + i * MAP_COLS)
map_row_hi:
    .fill MAP_ROWS, >(MAP_BASE + i * MAP_COLS)

// ============================================================
// Map accessors (single-tile API boundary)
// ============================================================
// Input: X = column, Y = row
// Output (get): A = tile byte
// Clobbers: A, Y, zp_ptr0/zp_ptr0_hi
map_get_tile:
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    txa
    tay
    :MapRead_ptr0_y()
    rts

// Input: X = column, Y = row, A = tile byte
// Clobbers: Y, zp_ptr0/zp_ptr0_hi
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

// ============================================================
// Store position data
// ============================================================
// Store top-left corners (x, y) — 2 rows of 3 stores + BM + Home
store_pos_x:
    .byte 5, 20, 55, 5, 20, 55, 37, 42
store_pos_y:
    .byte 3,  3,  3, 20, 20, 20, 3, 20

// Store door positions (center of south wall)
store_door_x:
    .byte 10, 25, 60, 10, 25, 60, 42, 47
store_door_y:
    .byte  7,  7,  7, 24, 24, 24, 7, 24

// ============================================================
// Dungeon room table — parallel arrays (SoA)
// ============================================================
room_count:  .byte 0
room_x:      .fill MAX_ROOMS, 0   // Interior left column
room_y:      .fill MAX_ROOMS, 0   // Interior top row
room_w:      .fill MAX_ROOMS, 0   // Interior width
room_h:      .fill MAX_ROOMS, 0   // Interior height
room_lit:    .fill MAX_ROOMS, 0   // 0=dark, 1=lit (set by place_rooms)
room_type:   .fill MAX_ROOMS, 0   // 0=normal, 1=pit, 2=vault, 3=nest

// ============================================================
// Stairs coordinates and level entry direction
// ============================================================
stairs_up_x:    .byte 0
stairs_up_y:    .byte 0
stairs_dn1_x:   .byte 0
stairs_dn1_y:   .byte 0
stairs_dn2_x:   .byte 0
stairs_dn2_y:   .byte 0
level_entry_dir: .byte 0  // 0=descended (place at stairs_up), 1=ascended (place at stairs_dn1)

// ============================================================
// Compile-time validation
// ============================================================
.assert "Map row table size", map_row_hi - map_row_lo, MAP_ROWS
#if C128
.assert "C128 map size = 13068", MAP_SIZE, 13068
#else
.assert "C64 map size = 3840", MAP_SIZE, 3840
#endif
.assert "Town flags = $0C", TOWN_FLAGS, $0c
.assert "Store count", STORE_COUNT, 8

#import "mmu_macros.s"
