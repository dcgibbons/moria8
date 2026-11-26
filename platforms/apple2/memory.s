// memory.s — Apple IIe memory map constants, ZP save/restore, and soft-switch
// compatibility shims.
//
// Map and layout authority: docs/APPLE2_MEMORY_POLICY.md (M0).
//
// The dungeon map lives in AUXILIARY RAM at $0800-$3B0B; all access goes
// through the MapRead/MapWrite thunks in memory_aux.s. MAP_BASE below is the
// aux-space base used by core/6502/dungeon_data.s row tables. The floor-item table
// and creature scratch share the same numeric addresses in MAIN RAM — legal
// because RAMRD/RAMWRT keep the banks disjoint, and the contract checker
// asserts every map access path is thunked.
//
// Main RAM map:
//   $0200-$028D  zp_save_buf (142 B core ZP snapshot across MLI calls)
//   $0290-$02D0  A2_MLI_PATHNAME (len byte + 64-byte ProDOS pathname)
//   $02E0-$02F4  Aux LC ZP-free bounce buffer (16 B) + LC restore/arg bytes
//   $0301-$033B  claimed platform resident scratch (59 B cap; $033C = door scan)
//   $033C-$037C  dungeon-gen door scan / Huffman decode scratch
//   $0400-$07FF  80-col text page, main half (screen holes never touched)
//   $0800-$08FF  floor-item table (256)
//   $0900-$09FF  creature scratch (256)
//   $0A00-$7BFF  always-resident region
//   $7C00-$9FFF  load-once play payload
//   $A000-$A3FF  tier name pool (core raw-addressed)
//   $A400-$BAFF  shared overlay/tier window (code ends at $B9FF)
//   $BB00-$BEFF  ProDOS MLI file I/O buffer
//   $BF00-$BFFF  ProDOS global page
//
// Aux RAM map:
//   $0000-$01FF  aux ZP + stack (untouched by ZP-free ALTZP=1 LC bounce path)
//   $0200-$03FF  claimed aux scratch/data window (512 B, below aux text page)
//   $0400-$07FF  80-col text page, aux half
//   $0800-$3B0B  aux dungeon map
//   $3B0C-$BFFF  auxdata, monster catalog, compressed overlay/title cache
//   $D000-$DFFF  aux Language Card Bank 1 & Bank 2 (4 KB each, ALTZP=1 data)
//   $E000-$FFF9  aux Language Card high RAM (8,186 B data; $FFFA-$FFFF vectors)

#import "hal/memory_bank_consts.s"
#import "hal/entropy_consts.s"

// ============================================================
// Constants
// ============================================================

.const MAP_BASE         = $0800 // AUX: dungeon map, 198x66 = 13,068 bytes
.const MAP_END          = $3b0b // AUX
.const FLOOR_ITEM_BASE  = $0800 // MAIN: floor item table (256 bytes)
.const FLOOR_ITEM_END   = $08ff
.const CREATURE_BASE    = $0900 // MAIN: runtime scratch (RLE, hiscore)
.const CREATURE_END     = $09ff
.const PLATFORM_TIER_NAME_POOL_BASE = $a000 // Active tier names (core raw-addressed)
.const PLATFORM_TIER_NAME_POOL_END  = $a3ff
.const BANKED_DATA_BASE = $a400 // Shared overlay/tier window
.const BANKED_DATA_END  = $baff
// C128-only constant used by shared tier_manager staging metadata.
// Apple II never executes this path, but the symbol must exist.
.const BANK1_DB_BASE    = BANKED_DATA_BASE
.const SCREEN_RAM       = $0400
.const COLOR_RAM        = $0400  // No color memory; logical colors only
// Dungeon-gen scan scratch: the MLI I/O buffer doubles as the 1,024-byte
// page-aligned scratch. Invariant: no MLI sequence runs while gen scratch is
// live (tier file is closed before OVL.GEN executes).
.const DUNGEON_GEN_SCAN_SCRATCH_BASE = $bb00
.const DUNGEON_GEN_SCAN_SCRATCH_SIZE = 1024
.const DUNGEON_GEN_SCAN_SCRATCH_END  = DUNGEON_GEN_SCAN_SCRATCH_BASE + DUNGEON_GEN_SCAN_SCRATCH_SIZE - 1
.const DUNGEON_GEN_DOOR_SCAN_BASE = hal_layout_dungeon_door_scan_base
.const DUNGEON_GEN_DOOR_SCAN_LIMIT = hal_layout_dungeon_door_scan_limit

// Play/modal slot (broker-owned; see overlay_storage.s)
.const A2_PLAY_SLOT_BASE = $7c00
.const A2_PLAY_SLOT_END  = $9fff
.const A2_PLAY_SLOT_SIZE = A2_PLAY_SLOT_END - A2_PLAY_SLOT_BASE + 1

// Zero-page platform ownership: core keeps $02-$8F; platform owns $90-$EF.
// Aux-read thunks execute from ZP because RAMRD switches instruction fetches
// in $0200-$BFFF (see docs/APPLE2_MEMORY_POLICY.md). Three thunks, no
// self-modifying code: byte-read via zp_ptr0, byte-read via zp_ptr1, block
// read (zp_ptr0 -> zp_ptr1, X = count, 0 = 256).
.const A2_ZP_PLATFORM_BASE = $90
.const A2_ZP_THUNK_READ_P0 = $c0   // 11 bytes
.const A2_ZP_THUNK_READ_P1 = $cb   // 11 bytes
.const A2_ZP_THUNK_READ_BLOCK = $d6 // 15 bytes; ends $e4 <= $ef
.label a2_zp_scratch = $a8          // AuxWriteX value stash
.label a2_save_aux_mode_flag = $a9  // save/load block stream bank dispatch

// ZP save buffer — stores $02-$8F around MLI sequences (ProDOS 8 TRM 3.3.1:
// the MLI uses $40-$4E restored, its disk driver $3A-$3F unrestored; the
// whole footprint is inside the core window).
.const ZP_SAVE_SIZE     = 142   // $02-$8F inclusive

// ============================================================
// Compatibility macros (no banking hardware on the runtime path)
// ============================================================

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

// ============================================================
// Subroutines
// ============================================================

// Claimed Main $0200-$028D: ZP save buffer (strictly before $0290 pathname).
.label zp_save_buf = $0200

// Claimed Main $02E0-$02F4: ZP-free ALTZP=1 Aux LC bounce buffer & state.
.const A2_LC_BOUNCE       = $02e0   // 16-byte bounce ($02E0-$02EF)
.const A2_LC_BOUNCE_SIZE  = 16
.const A2_LC_SAVED_X      = $02f0   // saved Main LC $C080,x index across ALTZP=1
.const A2_LC_ARG_BANK     = $02f1   // $00 = LC Bank 2, $08 = LC Bank 1
.const A2_LC_ARG_COUNT_M1 = $02f2   // chunk byte count - 1 (0..15)
.const A2_LC_ARG_DIR      = $02f3   // 0 = read Aux LC -> bounce, nonzero = write
.const A2_LC_CALLER_X     = $02f4   // preserved caller X across LC HAL calls
.const A2_LC_BANK2        = $00
.const A2_LC_BANK1        = $08
.const A2_LC_DIR_READ     = $00
.const A2_LC_DIR_WRITE    = $01
.const A2_LC_RECALL_BASE  = $d000   // Aux LC Bank 1: persistent recall[279] ($D000-$D45B)
.const A2_LC_CATEXT_BASE  = $d000   // Aux LC Bank 2: preloaded A2.CATEXT ($D000-$D8B7)
.const A2_CATEXT_RECORD_SIZE = 8
.const A2_CATEXT_SIZE     = 279 * A2_CATEXT_RECORD_SIZE
.const A2_LC_ITEM_CAT_BASE = $e000  // Aux LC High RAM: preloaded ITEM.CAT ($E000-$FD94)

// Claimed Main $0301-$033B resident scratch (strictly > $0300, strictly < $033C).
// Cleared on startup/session reset by a2_reset_session_state (main.s).
.const A2_LOW_SCRATCH_BASE     = $0301
.const A2_LOW_SCRATCH_LIMIT    = DUNGEON_GEN_DOOR_SCAN_BASE
.label a2_probe_buf            = $0301 // 8 B ($0301-$0308) marker read-back
.label a2_program_volume       = $0309 // 16 B ($0309-$0318) len-prefixed volume
.label a2_save_volume          = $0319 // 16 B ($0319-$0328) len-prefixed volume
.label a2_last_status          = $0329 // 1 B last HAL_STATUS_* mapped result
.label a2_media_status         = $032a // 1 B last HAL_STORAGE_STATUS_* verdict
.label a2_name_write           = $032b // 1 B pathname parser flag
.label a2_name_replace         = $032c // 1 B pathname parser flag
.label a2_name_scratch         = $032d // 1 B pathname parser flag
.label a2_name_drive           = $032e // 1 B pathname parser flag
.label a2_asset_verify         = $032f // 1 B hal_asset_load verify flag
.label a2_asset_dest           = $0330 // 2 B ($0330-$0331) asset destination
.label a2_diag_code            = $0332 // 1 B last raw ProDOS error code
.label a2_diag_phase           = $0333 // 1 B last HAL_STORAGE_PHASE_*
.label a2_diag_readst          = $0334 // 1 B last synthesized READST
.label a2_diag_device          = $0335 // 1 B last SETLFS advisory device
.label sfa_save_row            = $0336 // 1 B screen_flash_at scratch
.label sfa_save_col            = $0337 // 1 B screen_flash_at scratch
.label sfa_save_char           = $0338 // 1 B screen_flash_at scratch
.label igk_key                 = $0339 // 1 B input_get_key scratch
.label input_kbdbuf_shadow     = $033a // 1 B hal_input_kbdbuf_count alias
.const A2_LOW_SCRATCH_END      = $033a

// Claimed Aux $0200-$03FF scratch/data window (512 bytes, above Aux ZP/stack,
// strictly below the Aux 80-column text page at $0400).
.const A2_AUX_SCRATCH_BASE = $0200
.const A2_AUX_SCRATCH_END  = $03ff
.const A2_AUX_SCRATCH_SIZE = A2_AUX_SCRATCH_END - A2_AUX_SCRATCH_BASE + 1
.label a2_aux_scratch_base = A2_AUX_SCRATCH_BASE
.label a2_aux_scratch_end  = A2_AUX_SCRATCH_END

// save_zp — Copy $02-$8F to zp_save_buf
// Preserves: nothing (uses A, X)
save_zp:
    ldx #0
!loop:
    lda zp_temp0,x
    sta zp_save_buf,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    rts

// restore_zp — Copy zp_save_buf back to $02-$8F
// Preserves: nothing (uses A, X)
restore_zp:
    ldx #0
!loop:
    lda zp_save_buf,x
    sta zp_temp0,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    rts

// C128 MMU compatibility stubs for shared code paths that are runtime-gated.
mmu_select_bank1:
    rts

mmu_select_bank0:
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Aux map fits 198x66", MAP_END - MAP_BASE + 1, 13068
.assert "Floor items fit", FLOOR_ITEM_END - FLOOR_ITEM_BASE + 1, 256
.assert "Creature scratch fits", CREATURE_END - CREATURE_BASE + 1, 256
.assert "Tier name pool covers tier-4 name blob with margin", PLATFORM_TIER_NAME_POOL_END - PLATFORM_TIER_NAME_POOL_BASE + 1, 1024
.assert "Window is 5,888 bytes", BANKED_DATA_END - BANKED_DATA_BASE + 1, 5888
.assert "Play slot is 9,216 bytes", A2_PLAY_SLOT_SIZE, 9216
.assert "Dungeon-gen scan scratch remains page-aligned", <DUNGEON_GEN_SCAN_SCRATCH_BASE, 0
.assert "Dungeon-gen scan scratch stays inside the MLI buffer", DUNGEON_GEN_SCAN_SCRATCH_END <= $beff, true
.assert "Dungeon-gen door scan stays in platform scratch", DUNGEON_GEN_DOOR_SCAN_BASE >= $033c && DUNGEON_GEN_DOOR_SCAN_BASE + 65 <= $0400, true
.assert "ZP save buffer starts at $0200", zp_save_buf, $0200
.assert "ZP save buffer size", ZP_SAVE_SIZE, 142
.assert "ZP save buffer fits before MLI pathname", zp_save_buf + ZP_SAVE_SIZE <= $0290, true
.assert "Aux LC bounce stays in Main $02D1-$02FF below $0300", A2_LC_BOUNCE >= $02d1 && A2_LC_CALLER_X < $0300, true
.assert "Low scratch stays strictly above $0300", A2_LOW_SCRATCH_BASE > $0300, true
.assert "Low scratch stays strictly below door scan", A2_LOW_SCRATCH_END < DUNGEON_GEN_DOOR_SCAN_BASE, true
.assert "Aux scratch starts at $0200", A2_AUX_SCRATCH_BASE, $0200
.assert "Aux scratch size is 512 bytes", A2_AUX_SCRATCH_SIZE, 512
.assert "Aux scratch ends below aux text page", A2_AUX_SCRATCH_END < $0400, true
.assert "Read-p0 thunk lands in platform ZP", A2_ZP_THUNK_READ_P0 >= A2_ZP_PLATFORM_BASE && A2_ZP_THUNK_READ_P0 <= $ef, true
.assert "Read-p1 thunk lands in platform ZP", A2_ZP_THUNK_READ_P1 >= A2_ZP_PLATFORM_BASE && A2_ZP_THUNK_READ_P1 <= $ef, true
.assert "Read-block thunk lands in platform ZP", A2_ZP_THUNK_READ_BLOCK >= A2_ZP_PLATFORM_BASE && A2_ZP_THUNK_READ_BLOCK + 15 - 1 <= $ef, true
.assert "Aux scratch and save mode are distinct", a2_zp_scratch != a2_save_aux_mode_flag, true
.assert "Aux scratch stays in platform ZP before thunks", a2_zp_scratch >= A2_ZP_PLATFORM_BASE && a2_zp_scratch < A2_ZP_THUNK_READ_P0, true
.assert "Save aux mode stays in platform ZP before thunks", a2_save_aux_mode_flag >= A2_ZP_PLATFORM_BASE && a2_save_aux_mode_flag < A2_ZP_THUNK_READ_P0, true
