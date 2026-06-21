// dungeon_gen_module.s - CX16 bank-window dungeon-generation module wrapper.
//
// CX16 owns the load address, banked entry ABI, and fixed-RAM map placement.
// Generation semantics come from the shared basic generator slice in core/.

.pc = $a000 "CX16 Dungeon Gen Module"

.const MAP_BASE = $4000
.const MAP_COLS = 198
.const MAP_ROWS = 66
.const TILE_FLOOR = $00
.const TILE_WALL_H = $10
.const TILE_DOOR_OPEN = $70
.const TILE_DOOR_CLOSED = $80
.const TILE_STAIRS_DN = $90
.const TILE_STAIRS_UP = $a0
.const TILE_RUBBLE = $b0
.const TILE_QUARTZ = $d0
.const TILE_TRAP = $e0
.const FLAG_LIT = $08
.const FLAG_VISITED = $04
.const DUNGEON_GEN_BASIC_FLAGS = FLAG_LIT | FLAG_VISITED
.label zp_ptr0 = $06
.label zp_ptr0_hi = $07

cx16_dungeon_module_entry:
    jsr dungeon_gen_basic_generate
    clc
    lda #$d6
    ldx #$16
    ldy #$01
    rts

#import "../../core/dungeon_gen_basic.s"

cx16_dungeon_module_end:
.assert "CX16 dungeon module fits one banked-RAM window", cx16_dungeon_module_end <= $c000, true
