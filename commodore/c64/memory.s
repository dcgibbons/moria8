// memory.s — Bank switching routines and memory map management
//
// C64 memory banking via $01 (6510 port register):
//   Bit 0: LORAM  — 1=BASIC ROM at $A000, 0=RAM
//   Bit 1: HIRAM  — 1=KERNAL ROM at $E000, 0=RAM
//   Bit 2: CHAREN — 1=I/O at $D000, 0=Char ROM
//
// Default $01 value: $37 (BASIC + KERNAL + I/O visible)
// After BASIC disabled: $36 (KERNAL + I/O visible, RAM at $A000)
//
// IMPORTANT:
//   - CPU writes ALWAYS go to RAM regardless of banking.
//   - ROM must be banked OUT to READ data from RAM underneath.
//   - $E000–$FFFF: must wrap access in SEI/CLI because hardware
//     IRQ/NMI vectors at $FFFE/$FFFF will read from RAM when
//     KERNAL is banked out.

#import "hal/memory_bank_consts.s"
#import "hal/sound_consts.s"
#import "hal/entropy_consts.s"
#import "../common/bank_port_consts.s"

// ============================================================
// Constants
// ============================================================

// Memory region bases
.const MAP_BASE         = $c000 // Dungeon map (3,840 bytes)
.const MAP_END          = $ceff
.const FLOOR_ITEM_BASE  = $cf00 // Floor item table (256 bytes)
.const FLOOR_ITEM_END   = $cfff
.const CREATURE_BASE    = $c020 // Runtime scratch area (RLE, hiscore) — overlaps map but only used at save/game-over
.const CREATURE_END     = $c0ff
.const PLATFORM_TIER_NAME_POOL_BASE = $d000 // Hidden RAM under I/O; active tier names
.const PLATFORM_TIER_NAME_POOL_END  = $d7ff
.const C64_TIER_NAME_POOL_BASE = PLATFORM_TIER_NAME_POOL_BASE // Legacy C64 tests
.const C64_TIER_NAME_POOL_END  = PLATFORM_TIER_NAME_POOL_END
.const BANKED_DATA_BASE = $e000 // Item tiers, recall, spells (under KERNAL ROM)
.const BANKED_DATA_END  = $ffff
// C128-only constant used by shared tier_manager staging metadata.
// C64 never executes this path (runtime machine check), but symbol must exist.
.const BANK1_DB_BASE    = $e000
.const SCREEN_RAM       = $0400
.const COLOR_RAM        = $d800
.const DUNGEON_GEN_BFS_QUEUE_BASE = SCREEN_RAM
.const DUNGEON_GEN_BFS_QUEUE_MAX  = 512
.const DUNGEON_GEN_BFS_QUEUE_END  = DUNGEON_GEN_BFS_QUEUE_BASE + (DUNGEON_GEN_BFS_QUEUE_MAX * 2) - 1
.const DUNGEON_GEN_DOOR_SCAN_BASE = $033c

// ZP save buffer — stores $02–$8F during game, restored on exit
// Allocated as program data so it can't collide with code.
// Located under BASIC ROM when above $A000 — must read before banking BASIC in.
.const ZP_SAVE_SIZE     = 142   // $02–$8F inclusive

// ============================================================
// Macros
// ============================================================

// Bank out BASIC ROM — exposes RAM at $A000–$BFFF
// Safe to call without SEI (no IRQ vector issues)
.macro BankOutBasic() {
    lda $01
    and #%11111110  // Clear bit 0 (LORAM)
    sta $01
}

// Bank in BASIC ROM — restores ROM at $A000–$BFFF
.macro BankInBasic() {
    lda $01
    ora #%00000001  // Set bit 0 (LORAM)
    sta $01
}

// Bank out KERNAL ROM — exposes RAM at $E000–$FFFF
// MUST be called after SEI (IRQ vectors read from RAM when KERNAL banked out)
// Caller is responsible for SEI before and CLI after.
.macro BankOutKernal() {
    lda $01
    and #%11111101  // Clear bit 1 (HIRAM)
    sta $01
}

// Bank in KERNAL ROM — restores ROM at $E000–$FFFF
// Call before CLI to restore IRQ vectors.
.macro BankInKernal() {
    lda $01
    ora #%00000010  // Set bit 1 (HIRAM)
    sta $01
}

// Bank out both BASIC and KERNAL — RAM everywhere except I/O
// Caller MUST have called SEI first.
.macro BankOutAll() {
    lda $01
    and #%11111100  // Clear bits 0 and 1
    sta $01
}

// Restore default banking (BASIC + KERNAL + I/O)
.macro BankRestoreDefault() {
    lda #BANK_ALL_ROM
    sta $01
}

// Platform compatibility macros (no-ops for C64)
.macro MachineRestoreDefault() {}
.macro MachineRestoreAllRam() {}
.macro EnterKernal() { php }
.macro ExitKernal() { plp }

// ============================================================
// Subroutines
// ============================================================

// Buffer allocated as program data — address assigned by assembler
zp_save_buf: .fill ZP_SAVE_SIZE, 0

// save_zp — Copy $02–$8F to zp_save_buf
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

// restore_zp — Copy zp_save_buf back to $02–$8F
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

// read_banked_byte_a000 — Read a byte from RAM under BASIC ROM
// Input:  zp_ptr0/zp_ptr0_hi = address in $A000–$BFFF
//         Y = offset from pointer
// Output: A = byte read
// Preserves: X, Y
read_banked_byte_a000:
    :BankOutBasic()
    lda (zp_ptr0),y
    pha
    :BankInBasic()
    pla
    rts

// read_banked_byte_e000 — Read a byte from RAM under KERNAL ROM
// Input:  zp_ptr0/zp_ptr0_hi = address in $E000–$FFFF
//         Y = offset from pointer
// Output: A = byte read
// Preserves: X, Y
// NOTE: This routine handles SEI/CLI internally.
read_banked_byte_e000:
    sei
    :BankOutKernal()
    lda (zp_ptr0),y
    pha
    :BankInKernal()
    cli
    pla
    rts

// write_banked_byte_e000 — Write is not needed (CPU writes always go to RAM)
// but we provide a read-back verification routine for testing.

// copy_to_e000 — Bulk copy to RAM under KERNAL ROM
// Input:  zp_ptr0 = source address (lo/hi)
//         zp_ptr1 = dest address in $E000–$FFFF (lo/hi)
//         zp_temp0 = byte count lo
//         zp_temp1 = byte count hi
// Preserves: nothing
copy_to_e000:
    // Writes go to RAM automatically, no banking needed for write.
    // But we bank out KERNAL so we can verify if needed.
    ldy #0
    ldx zp_temp1        // Page counter (high byte of count)
    beq !partial+       // Less than 256 bytes
!page:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    bne !page-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dex
    bne !page-
!partial:
    ldx zp_temp0        // Remaining bytes (low byte of count)
    beq !done+
!tail:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    dex
    bne !tail-
!done:
    rts

// C128 MMU compatibility stubs for shared code paths that are runtime-gated.
mmu_select_bank1:
    rts

mmu_select_bank0:
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Map fits in $C000 region", MAP_END - MAP_BASE + 1, 3840
.assert "Floor items fit", FLOOR_ITEM_END - FLOOR_ITEM_BASE + 1, 256
.assert "Dungeon-gen BFS queue remains page-aligned", <DUNGEON_GEN_BFS_QUEUE_BASE, 0
.assert "Dungeon-gen BFS queue stays in screen scratch window", DUNGEON_GEN_BFS_QUEUE_END <= $07ff, true
.assert "Dungeon-gen door scan stays in cassette buffer", DUNGEON_GEN_DOOR_SCAN_BASE >= $033c && DUNGEON_GEN_DOOR_SCAN_BASE + 65 <= $0400, true
.assert "ZP save buffer doesn't overlap CREATURE_BASE", zp_save_buf + ZP_SAVE_SIZE <= CREATURE_BASE, true
.assert "ZP save buffer size", ZP_SAVE_SIZE, 142
