// config.s — Apple IIe game configuration constants and machine detection.
//
// There is nothing to detect: the port targets exactly one machine class
// (Apple IIe 128K / enhanced IIe / IIc, 80-column). detect_machine exists to
// satisfy the shared entry sequence and stores fixed values.

#import "hal/entropy_consts.s"
#import "hal/lifecycle_policy.s"

// 80-column message buffer (C128 class): covers the longest wear/wield
// line ("You are wielding a Two-Handed Sword (Holy Avenger) (+9,+9)." =
// 60 chars + NUL) with margin. 42 was a 40-column C64 inheritance.
.const PLATFORM_COMBAT_MSG_BUF_SIZE = 64
#define PLATFORM_GET_INFRA_RANGE_INLINE
#define PLATFORM_COPY_DEATH_SOURCE
.const PLATFORM_RESIDENT_PLAY = "A2PlaySlot"
// Huffman decode scratch and dungeon-gen door-scan scratch share the platform
// $0200-$03CF block at different times (same dual-use pattern as C64).
.const PLATFORM_HD_DECODE_BUF_BASE = $033c
.const PLATFORM_HD_DECODE_BUF_LIMIT = $0400
// Place 48-byte item_name_decode_buf in unused page-3 scratch after door-scan.
#define PLATFORM_ITEM_NAME_BUF_LOW
.const PLATFORM_ITEM_NAME_DECODE_BUF_BASE = $0380
.assert "item_name_decode_buf clears hd_decode_buf and door-scan scratch", PLATFORM_ITEM_NAME_DECODE_BUF_BASE >= $037d, true
.assert "item_name_decode_buf fits below ProDOS Page-3 vectors ($03D0)", PLATFORM_ITEM_NAME_DECODE_BUF_BASE + 48 <= $03d0, true

// Machine type constants (stored in zp_machine_type; core never branches on
// this byte — it is platform/test diagnostic only).
.const MACHINE_C64    = $00
.const MACHINE_APPLE2 = $40
.const MACHINE_C128   = $80

// Column mode constants (stored in zp_column_mode)
.const COLUMNS_40 = $00
.const COLUMNS_80 = $80

// detect_machine — Store fixed Apple IIe / 80-column identity
// Output: zp_machine_type = MACHINE_APPLE2
//         zp_column_mode  = COLUMNS_80
// Preserves: nothing
detect_machine:
    lda #MACHINE_APPLE2
    sta zp_machine_type
    lda #COLUMNS_80
    sta zp_column_mode
    rts

.macro AssetLoad() {
    jsr hal_asset_load
}

.const DEATH_ALIVE   = $00    // Player is alive
.const DEATH_CHEST_NEEDLE = $F7
.const DEATH_CHEST_EXPLOSION = $F8
.const DEATH_TRAP_PIT      = $F9    // Killed by an open pit
.const DEATH_TRAP_ARROW    = $FA    // Killed by an arrow trap
.const DEATH_TRAP_DART     = $FB    // Killed by a poison dart
.const DEATH_TRAP_ROCKFALL = $FC    // Killed by falling rock
.const DEATH_CURSED  = $FD    // Killed by cursed item
.const DEATH_POISON  = $FE    // Killed by poison
.const DEATH_STARVE  = $FF    // Killed by starvation
