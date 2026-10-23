#importonce
// config.s — BBC Master 128 game configuration constants and machine detection.

#import "hal/entropy_consts.s"
#import "hal/lifecycle_policy.s"

.const PLATFORM_COMBAT_MSG_BUF_SIZE = 64
#define PLATFORM_GET_INFRA_RANGE_INLINE
#define PLATFORM_COPY_DEATH_SOURCE
.const PLATFORM_RESIDENT_PLAY = "BeebPlaySlot"

// Huffman decode scratch in low main RAM ($0600-$063F, 64 B).
.const PLATFORM_HD_DECODE_BUF_BASE  = $0600
.const PLATFORM_HD_DECODE_BUF_LIMIT = $0640

// Machine type constants (stored in zp_machine_type)
.const MACHINE_C64       = $00
.const MACHINE_APPLE2    = $40
.const MACHINE_BBCMASTER = $60
.const MACHINE_C128      = $80

// Column mode constants (stored in zp_column_mode)
.const COLUMNS_40 = $00
.const COLUMNS_80 = $80

detect_machine:
    lda #MACHINE_BBCMASTER
    sta zp_machine_type
    lda #COLUMNS_80
    sta zp_column_mode
    rts

.macro AssetLoad() {
    jsr hal_asset_load
}

.const DEATH_ALIVE           = $00
.const DEATH_CHEST_NEEDLE    = $f7
.const DEATH_CHEST_EXPLOSION = $f8
.const DEATH_TRAP_PIT        = $f9
.const DEATH_TRAP_ARROW      = $fa
.const DEATH_TRAP_DART       = $fb
.const DEATH_TRAP_ROCKFALL   = $fc
.const DEATH_CURSED          = $fd
.const DEATH_POISON          = $fe
.const DEATH_STARVE          = $ff
