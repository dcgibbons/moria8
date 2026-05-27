#importonce
// input_contract.s — shared input command IDs and direction tables

// ============================================================
// Command IDs — internal constants, not key codes
// ============================================================
.const CMD_NONE      = $00
.const CMD_MOVE_N    = $01
.const CMD_MOVE_S    = $02
.const CMD_MOVE_W    = $03
.const CMD_MOVE_E    = $04
.const CMD_MOVE_NW   = $05
.const CMD_MOVE_NE   = $06
.const CMD_MOVE_SW   = $07
.const CMD_MOVE_SE   = $08
.const CMD_STAIRS_DN = $09
.const CMD_STAIRS_UP = $0a
.const CMD_REST      = $0b
.const CMD_SEARCH    = $0c
.const CMD_OPEN      = $0d
.const CMD_CLOSE     = $0e
.const CMD_PICKUP    = $0f
.const CMD_DROP      = $10
.const CMD_INVENTORY = $11
.const CMD_EQUIPMENT = $12
.const CMD_WEAR      = $13
.const CMD_TAKEOFF   = $14
.const CMD_EAT       = $15
.const CMD_QUAFF     = $16
.const CMD_READ      = $17
.const CMD_AIM       = $18
.const CMD_USE       = $19
.const CMD_CAST      = $1a
.const CMD_PRAY      = $1b
.const CMD_CHAR_INFO = $1c
.const CMD_MAP       = $1d
.const CMD_RECALL    = $1e
.const CMD_LOOK      = $1f
.const CMD_RUN       = $20
.const CMD_SAVE      = $21
.const CMD_QUIT      = $22
.const CMD_HELP      = $23
.const CMD_VERSION   = $24
.const CMD_RUN_N     = $25
.const CMD_RUN_S     = $26
.const CMD_RUN_W     = $27
.const CMD_RUN_E     = $28
.const CMD_RUN_NW    = $29
.const CMD_RUN_NE    = $2a
.const CMD_RUN_SW    = $2b
.const CMD_RUN_SE    = $2c
.const CMD_GAIN      = $2d
.const CMD_FIRE      = $2e
.const CMD_THROW     = $2f
.const CMD_REFUEL    = $30
.const CMD_BASH      = $31
.const CMD_TUNNEL    = $32
.const CMD_WIZARD    = $33
.const CMD_SEARCH_MODE = $34
.const CMD_DISARM    = $35

// Index = CMD_MOVE_x - CMD_MOVE_N
dir_dx: .byte  0,  0, -1, 1, -1, 1, -1, 1
dir_dy: .byte -1,  1,  0, 0, -1,-1,  1, 1
dir_opposite: .byte 1, 0, 3, 2, 7, 6, 5, 4
