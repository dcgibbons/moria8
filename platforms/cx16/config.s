// config.s — Commander X16 game configuration constants and machine detection.

#import "hal/entropy_consts.s"
#import "hal/lifecycle_policy.s"

// 80-column message buffer (64 chars).
.const PLATFORM_COMBAT_MSG_BUF_SIZE = 64
#define PLATFORM_GET_INFRA_RANGE_INLINE
#define PLATFORM_COPY_DEATH_SOURCE
.const PLATFORM_RESIDENT_PLAY = "Default"
// Huffman decode scratch and dungeon-gen door-scan scratch share $0600-$06FF.
.const PLATFORM_HD_DECODE_BUF_BASE = $0600
.const PLATFORM_HD_DECODE_BUF_LIMIT = $0700

.const MACHINE_C64    = $00
.const MACHINE_PLUS4  = $20
.const MACHINE_APPLE2 = $40
.const MACHINE_CX16   = $60
.const MACHINE_C128   = $80

.const COLUMNS_40 = $00
.const COLUMNS_80 = $80

detect_machine:
    lda #MACHINE_CX16
    sta zp_machine_type
    lda #COLUMNS_80
    sta zp_column_mode
    rts

.macro AssetLoad() {
    jsr hal_asset_load
}

.const DEATH_ALIVE   = $00
.const DEATH_CHEST_NEEDLE = $F7
.const DEATH_CHEST_EXPLOSION = $F8
.const DEATH_TRAP_PIT      = $F9
.const DEATH_TRAP_ARROW    = $FA
.const DEATH_TRAP_DART     = $FB
.const DEATH_TRAP_ROCKFALL = $FC
.const DEATH_CURSED  = $FD
.const DEATH_POISON  = $FE
.const DEATH_STARVE  = $FF
