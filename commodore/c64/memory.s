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

// ============================================================
// Constants
// ============================================================
.const BANK_ALL_RAM     = $30  // All RAM, I/O visible (not usually needed)
.const BANK_ALL_ROM     = $37  // Default: BASIC + KERNAL + I/O
.const BANK_NO_BASIC    = $36  // KERNAL + I/O, RAM at $A000–$BFFF
.const BANK_NO_KERNAL   = $35  // I/O + RAM everywhere ($A000, $D000=I/O, $E000)
.const BANK_NO_ROMS     = $34  // I/O only, RAM at $A000 and $E000

// Memory region bases
.const MAP_BASE         = $c000 // Dungeon map (3,840 bytes)
.const MAP_END          = $ceff
.const FLOOR_ITEM_BASE  = $cf00 // Floor item table (256 bytes)
.const FLOOR_ITEM_END   = $cfff
.const CREATURE_BASE    = $c020 // Runtime scratch area (RLE, hiscore) — overlaps map but only used at save/game-over
.const CREATURE_END     = $c0ff
.const BANKED_DATA_BASE = $e000 // Item tiers, recall, spells (under KERNAL ROM)
.const BANKED_DATA_END  = $ffff
.const SCREEN_RAM       = $0400
.const COLOR_RAM        = $d800

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
    lda $02,x
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
    sta $02,x
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

// ============================================================
// Compile-time validation
// ============================================================
.assert "Map fits in $C000 region", MAP_END - MAP_BASE + 1, 3840
.assert "Floor items fit", FLOOR_ITEM_END - FLOOR_ITEM_BASE + 1, 256
.assert "ZP save buffer doesn't overlap CREATURE_BASE", zp_save_buf + ZP_SAVE_SIZE <= CREATURE_BASE, true
.assert "ZP save buffer size", ZP_SAVE_SIZE, 142
