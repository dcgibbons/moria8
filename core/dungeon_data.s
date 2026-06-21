#importonce
// dungeon_data.s — Shared dungeon constants, tables, and variables
//
// Contains all data shared between dungeon_gen.s (generation overlay) and
// the rest of the game engine. Stays in the main segment so it is always
// accessible (map row table, room data, stairs coordinates, etc.).
//
// dungeon_gen.s (overlay) handles generation; only generation-private
// constants remain there. Platform-owned scratch regions such as the BFS
// queue now come from the memory layer.

// ============================================================
// Map constants
// ============================================================
#import "dungeon_consts.s"

.const MAP_COLS     = hal_layout_map_cols
.const MAP_ROWS     = hal_layout_map_rows
.const MAP_SIZE     = MAP_COLS * MAP_ROWS

// ============================================================
// Pre-computed row address table
// map_row_lo[n] / map_row_hi[n] = MAP_BASE + n*MAP_COLS
// ============================================================
map_row_lo:
    .fill MAP_ROWS, <(MAP_BASE + i * MAP_COLS)
map_row_hi:
    .fill MAP_ROWS, >(MAP_BASE + i * MAP_COLS)

// ============================================================
// Map accessor (single-tile API boundary)
// ============================================================
// Input: X = column, Y = row
// Output: A = tile byte
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

// ============================================================
// Store position data
// ============================================================
// Store top-left corners (x, y) — fixed 4x2 layout inside the 66x22 town.
store_pos_x:
    .byte 10, 22, 34, 46, 10, 22, 34, 46
store_pos_y:
    .byte  2,  2,  2,  2, 12, 12, 12, 12

// Store door positions (center of south wall)
store_door_x:
    .byte 15, 27, 39, 51, 15, 27, 39, 51
store_door_y:
    .byte  6,  6,  6,  6, 16, 16, 16, 16

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
sr_room_idx: .byte 0              // Special room working room index
sr_count:    .byte 0              // Special room working loop/count scratch
sr_mode:     .byte 0              // 0=nest, 1=pit
sr_fixed_type: .byte 0            // Fixed pit type / temp

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
.assert "Platform map size matches HAL layout", MAP_SIZE, hal_layout_map_cols * hal_layout_map_rows
.assert "Town flags = $0C", TOWN_FLAGS, $0c
.assert "Store count", STORE_COUNT, 8
.assert "Town map width", TOWN_MAP_COLS, 66
.assert "Town map height", TOWN_MAP_ROWS, 22
.assert "Town store width", STORE_W, 10
.assert "Town store height", STORE_H, 5
.assert "Town stairs inside town width", TOWN_STAIRS_X < TOWN_MAP_COLS, true
.assert "Town stairs inside town height", TOWN_STAIRS_Y < TOWN_MAP_ROWS, true

#import "mmu_macros.s"
