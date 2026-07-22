// memory.s — Apple IIe memory map constants, ZP save/restore, and soft-switch
// compatibility shims.
//
// Map and layout authority: docs/APPLE2_MEMORY_POLICY.md (M0).
//
// The dungeon map lives in AUXILIARY RAM at $0800-$3B0B; all access goes
// through the MapRead/MapWrite thunks in memory_aux.s. MAP_BASE below is the
// aux-space base used by core/dungeon_data.s row tables. The floor-item table
// and creature scratch share the same numeric addresses in MAIN RAM — legal
// because RAMRD/RAMWRT keep the banks disjoint, and the contract checker
// asserts every map access path is thunked.
//
// Main RAM map:
//   $0200-$03CF  platform scratch (ZP save buffer, MLI params, loader staging)
//   $0400-$07FF  80-col text page, main half (screen holes never touched)
//   $0800-$08FF  floor-item table (256)
//   $0900-$09FF  creature scratch (256)
//   $0A00-$7BFF  always-resident region
//   $7C00-$9FFF  load-once play payload
//   $A000-$A3FF  tier name pool (core raw-addressed)
//   $A400-$BAFF  shared overlay/tier window (code ends at $B9FF)
//   $BB00-$BEFF  ProDOS MLI file I/O buffer
//   $BF00-$BFFF  ProDOS global page

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

// Buffer allocated as program data — address assigned by assembler.
zp_save_buf: .fill ZP_SAVE_SIZE, 0

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
.assert "ZP save buffer size", ZP_SAVE_SIZE, 142
.assert "Read-p0 thunk lands in platform ZP", A2_ZP_THUNK_READ_P0 >= A2_ZP_PLATFORM_BASE && A2_ZP_THUNK_READ_P0 <= $ef, true
.assert "Read-p1 thunk lands in platform ZP", A2_ZP_THUNK_READ_P1 >= A2_ZP_PLATFORM_BASE && A2_ZP_THUNK_READ_P1 <= $ef, true
.assert "Read-block thunk lands in platform ZP", A2_ZP_THUNK_READ_BLOCK >= A2_ZP_PLATFORM_BASE && A2_ZP_THUNK_READ_BLOCK + 15 - 1 <= $ef, true
.assert "Aux scratch and save mode are distinct", a2_zp_scratch != a2_save_aux_mode_flag, true
.assert "Aux scratch stays in platform ZP before thunks", a2_zp_scratch >= A2_ZP_PLATFORM_BASE && a2_zp_scratch < A2_ZP_THUNK_READ_P0, true
.assert "Save aux mode stays in platform ZP before thunks", a2_save_aux_mode_flag >= A2_ZP_PLATFORM_BASE && a2_save_aux_mode_flag < A2_ZP_THUNK_READ_P0, true
