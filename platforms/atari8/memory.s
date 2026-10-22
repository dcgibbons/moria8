#importonce
// memory.s — Atari 8-bit (64 KB 800XL/65XE + 128 KB 130XE) memory layout and
// hardware constants. See docs/ATARI8_MEMORY_CONTRACT.md.

#import "hal/layout.s"
#import "hal/memory_bank_consts.s"
#import "../commodore/common/bank_port_consts.s"

// ============================================================
// Atari OS Zero-Page Addresses ($0002-$008F overlapped during SIOV)
// ============================================================
// Accessed only inside EnterSio / exit_trampoline after save_zp.
.label OS_WARMST     = $08
.label OS_DOSVEC     = $0a
.label OS_POKMSK     = $10
.label OS_BRKKEY     = $11
.label OS_RTCLOK_LO  = $14
.label OS_SOUNDR     = $41
.label OS_CRITIC     = $42
.label OS_ATRACT     = $4d

// ============================================================
// Platform-Owned Zero-Page ($0090-$00AF)
// ============================================================
// $90 is reserved as zp_kernal_status (defined in core/zeropage.s, cleared by title_screen.s).
// $92-$AF holds named Atari storage, sector-chain, and 130XE bounce pointers
// so SIOV / 130XE copies never touch core ZP ($02-$8F).
.label atari_io_src     = $92
.label atari_io_src_hi  = $93
.label atari_io_dst     = $94
.label atari_io_dst_hi  = $95
.label atari_io_sec_lo  = $96
.label atari_io_sec_hi  = $97
.label atari_io_rem_lo  = $98
.label atari_io_rem_hi  = $99
.label atari_file_idx   = $9a
.label atari_io_cnt     = $9b
.label atari_io_flags   = $9c
.label atari_io_pages   = $9d
.label atari_io_slot    = $9e
.label atari_io_irq_p   = $9f

// ============================================================
// Atari OS Page 2 Shadows & Page 3 DCB ($0200-$031A Untouched)
// ============================================================
.const OS_SDMCTL  = $022f
.const OS_SDLSTL  = $0230
.const OS_SDLSTH  = $0231
.const OS_GPRIOR  = $026f
.const OS_COLOR0  = $02c4
.const OS_COLOR1  = $02c5
.const OS_COLOR2  = $02c6
.const OS_COLOR3  = $02c7
.const OS_COLOR4  = $02c8
.const OS_CHACT   = $02f3
.const OS_CHBAS   = $02f4

.const DCB_DDEVIC = $0300
.const DCB_DUNIT  = $0301
.const DCB_DCOMND = $0302
.const DCB_DSTATS = $0303
.const DCB_DBUFLO = $0304
.const DCB_DBUFHI = $0305
.const DCB_DTIMLO = $0306
.const DCB_DBYTLO = $0308
.const DCB_DBYTHI = $0309
.const DCB_DAUX1  = $030a
.const DCB_DAUX2  = $030b

.const OS_SIOV    = $e459
.const OS_WARMSV  = $e474
.const OS_COLDSV  = $e477

// ============================================================
// Hardware I/O Window ($D000-$D7FF — Immovable)
// ============================================================
.const IO_HOLE_BASE = $d000
.const IO_HOLE_END  = $d7ff

// GTIA ($D000-$D0FF)
.const COLPF0 = $d016
.const COLPF1 = $d017
.const COLPF2 = $d018
.const COLPF3 = $d019
.const COLBK  = $d01a
.const PRIOR  = $d01b
.const CONSOL = $d01f

// POKEY ($D200-$D2FF)
.const AUDF1  = $d200
.const AUDC1  = $d201
.const AUDF2  = $d202
.const AUDC2  = $d203
.const AUDF3  = $d204
.const AUDC3  = $d205
.const AUDF4  = $d206
.const AUDC4  = $d207
.const AUDCTL = $d208
.const KBCODE = $d209
.const RANDOM = $d20a
.const IRQEN  = $d20e
.const IRQST  = $d20e
.const SKCTL  = $d20f
.const SKSTAT = $d20f

// PIA ($D300-$D3FF)
.const PORTA  = $d300
.const PORTB  = $d301
.const PACTL  = $d302
.const PBCTL  = $d303

// PORTB ($D301) banking states
.const PORTB_GAME_RAM = $fe
.const PORTB_OS_ROM   = $ff
.const PORTB_XE_BANK0 = $e2
.const PORTB_XE_BANK1 = $e6
.const PORTB_XE_BANK2 = $ea
.const PORTB_XE_BANK3 = $ee

// ANTIC ($D400-$D4FF)
.const DMACTL = $d400
.const CHACTL = $d401
.const DLISTL = $d402
.const DLISTH = $d403
.const HSCROL = $d404
.const VSCROL = $d405
.const PMBASE = $d407
.const CHBASE = $d409
.const WSYNC  = $d40a
.const VCOUNT = $d40b
.const NMIEN  = $d40e
.const NMIST  = $d40f
.const NMIRES = $d40f

// ============================================================
// Display, Font, & Scratch Regions (< $4000)
// ============================================================
.const DUNGEON_GEN_DOOR_SCAN_BASE    = hal_layout_dungeon_door_scan_base
.const DUNGEON_GEN_DOOR_SCAN_LIMIT   = hal_layout_dungeon_door_scan_limit
.const ATARI_DISPLAY_LIST            = $0380
.const ATARI_CHARSET_BASE            = $0400
.const SCREEN_RAM                    = $0800
.const SCREEN_END                    = $0be7
.const DUNGEON_GEN_SCAN_SCRATCH_BASE = SCREEN_RAM
.const DUNGEON_GEN_SCAN_SCRATCH_LIMIT = SCREEN_RAM + $0400

// ============================================================
// Map & Creature Scratch ($C100-$CFFF — 15 Pages = 3,840 B)
// ============================================================
.const MAP_BASE      = $c100
.const ATARI_MAP_SIZE = $0f00
.const MAP_END       = $cfff
.const CREATURE_BASE = $c120
.const CREATURE_END  = $c1ff

// ============================================================
// High RAM Under OS ROM ($D800-$FFFF, PORTB = $FE)
// ============================================================
.const PLATFORM_TIER_NAME_POOL_BASE  = $d800
.const PLATFORM_TIER_NAME_POOL_END   = $dbff
.const PLATFORM_TIER_NAME_POOL_SIZE  = PLATFORM_TIER_NAME_POOL_END - PLATFORM_TIER_NAME_POOL_BASE + 1

.const FLOOR_ITEM_BASE               = $dc00
.const FLOOR_ITEM_END                = $dcff

.const PLATFORM_HD_DECODE_BUF_BASE   = $dd00
.const PLATFORM_HD_DECODE_BUF_LIMIT  = $dd40

.label zp_save_buf                   = $dd40
.label msg_history_atari             = $ddce

.const BANKED_DATA_BASE              = $e000
.const BANKED_DATA_END               = $ffff

// ============================================================
// Save Slot Capacity Contract
// ============================================================
.const ATARI_SAVE_SLOT_SECTORS       = 56
.const ATARI_SAVE_SECTOR_DATA_BYTES  = 125
.const ATARI_SAVE_SERIALIZED_MAX     = 6616
.const DOS25_LINK_BYTES              = 125
.const DOS25_LINK_HI                 = 126
.const DOS25_LINK_LO                 = 127

// ============================================================
// Link-Time Boundary Assertions
// ============================================================
.assert "ATARI_CHARSET_BASE is 1 KB aligned", (<ATARI_CHARSET_BASE) == 0 && ((>ATARI_CHARSET_BASE) & 3) == 0, true
.assert "SCREEN_RAM stays below $4000", SCREEN_END < $4000, true
.assert "MAP_BASE + ATARI_MAP_SIZE ends at $CFFF below $D000 I/O hole", MAP_BASE + ATARI_MAP_SIZE - 1 == MAP_END && MAP_END == $cfff, true
.assert "MAP_END does not overlap IO_HOLE_BASE", MAP_END < IO_HOLE_BASE, true
.assert "Save slot sector budget fits full serialized save", ATARI_SAVE_SLOT_SECTORS * ATARI_SAVE_SECTOR_DATA_BYTES >= ATARI_SAVE_SERIALIZED_MAX, true

// ============================================================
// High-RAM Visibility Macros
// ============================================================
// On Atari 8-bit, PORTB = $FE keeps RAM visible at $C000-$CFFF and $D800-$FFFF
// throughout gameplay; only EnterSio/ExitSio temporarily switch PORTB = $FF.
.macro BankOutKernal() {
}

.macro BankInKernal() {
}
