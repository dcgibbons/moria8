#importonce
// dungeon_consts.s - shared dungeon tile and map-domain constants.

.const MAP40_COLS = 80
.const MAP40_ROWS = 48
.const C128_MAP_COLS = 198
.const C128_MAP_ROWS = 66
.const TOWN_MAP_COLS = 66
.const TOWN_MAP_ROWS = 22
.const TOWN_STAIRS_X = 32
.const TOWN_STAIRS_Y = 18
.const TOWN_START_X = 31
.const TOWN_START_Y = 18
.const STORE_W = 10
.const STORE_H = 5

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
.const FLAG_OCCUPIED = $01
.const FLAG_HAS_ITEM = $02
.const FLAG_VISITED  = $04
.const FLAG_LIT      = $08

.const TOWN_FLAGS    = FLAG_LIT | FLAG_VISITED
.const STORE_COUNT   = 8
.const TILE_TYPE_MASK = $F0
.const TILE_FLAG_MASK = $0F

.const MAX_ROOMS     = 8
.const DUNGEON_FLAGS = FLAG_LIT

.const RT_NORMAL = 0
.const RT_PIT    = 1
.const RT_VAULT  = 2
.const RT_NEST   = 3

.const MAX_TRAPS = 16
.const TRAP_OPEN_PIT    = 0
.const TRAP_ARROW       = 1
.const TRAP_POISON_GAS  = 2
.const TRAP_TELEPORT    = 3
.const TRAP_POISON_DART = 4
.const TRAP_ROCKFALL    = 5
.const TRAP_TYPE_COUNT  = 6
