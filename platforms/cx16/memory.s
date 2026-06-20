#importonce
// memory.s - Commander X16 memory and bank macro contract.
//
// CX16 does not have C64-style hidden RAM under KERNAL ROM. These macros are
// currently no-ops so shared code can assemble while CX16 tier storage is still
// being wired to the machine's RAM-bank model.

#import "hal/layout.s"

.const BANKED_DATA_BASE = $e000
.const BANKED_DATA_END  = $ffff
.const BANK1_DB_BASE    = $e000
.const MAP_END          = MAP_BASE + (hal_layout_map_cols * hal_layout_map_rows) - 1
.const FLOOR_ITEM_BASE  = $7400
.const FLOOR_ITEM_END   = $74ff
.const CREATURE_BASE    = $7500
.const CREATURE_END     = $75ff
.const DUNGEON_GEN_BFS_QUEUE_BASE = $0400
.const DUNGEON_GEN_BFS_QUEUE_MAX  = 512
.const DUNGEON_GEN_BFS_QUEUE_END  = DUNGEON_GEN_BFS_QUEUE_BASE + (DUNGEON_GEN_BFS_QUEUE_MAX * 2) - 1

.assert "CX16 live map span matches HAL layout", MAP_END - MAP_BASE + 1, hal_layout_map_cols * hal_layout_map_rows
.assert "CX16 floor items stay after live map", MAP_END < FLOOR_ITEM_BASE, true
.assert "CX16 floor items fit", FLOOR_ITEM_END - FLOOR_ITEM_BASE + 1, 256
.assert "CX16 creature scratch stays after floor items", FLOOR_ITEM_END < CREATURE_BASE, true
.assert "CX16 dungeon-gen BFS queue remains page-aligned", <DUNGEON_GEN_BFS_QUEUE_BASE, 0

.macro BankOutBasic() {}
.macro BankInBasic() {}
.macro BankOutKernal() {}
.macro BankInKernal() {}
.macro BankOutAll() {}
.macro BankRestoreDefault() {}
.macro MachineRestoreDefault() {}
.macro MachineRestoreAllRam() {}
.macro EnterKernal() { php }
.macro ExitKernal() { plp }
