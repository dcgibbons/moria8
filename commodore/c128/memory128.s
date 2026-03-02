// memory128.s — Bank switching routines and memory map management (C128)
//
// C128 banking uses BOTH the MMU Configuration Register ($FF00/$D500)
// and the 8502 processor port ($01). A ROM is visible only if BOTH
// the MMU and processor port enable it.
//
// Strategy:
//   - At startup, set $FF00 to $0E (MMU_NORMAL: KERNAL+ScreenEd in, I/O).
//     This permanently removes BASIC ROM ($4000-$BFFF) from the memory map.
//   - Set $01 to $36 (KERNAL + I/O, no BASIC).
//   - Use $01 for runtime banking, identical to C64's memory.s approach.
//     Common code modules (reu.s, tier_manager.s, overlay.s, monster.s)
//     all use $01 directly, so this ensures compatibility.
//   - IMPORTANT: Bit 2 of $01 MUST STAY AT 1 on the C128 to keep I/O visible
//     for the KERNAL IRQ handler. If it is ever 0, the CPU sees CharROM
//     instead of CIA registers, leading to unacknowledged IRQs and crash.
//
// C128 MMU $FF00 bits (Configuration Register):
//   Bits 7-6: RAM bank select — 00=Bank 0, 01=Bank 1, 10/11=banks 2-3
//   Bits 5-4: $C000-$FFFF — 00=System ROM (KERNAL+ScreenEd), 11=RAM
//   Bits 3-2: $8000-$BFFF — 00=BASIC HI, 01=Int Func, 10=Ext Func, 11=RAM
//   Bit    1: $4000-$7FFF — 0=BASIC LOW ROM, 1=RAM
//   Bit    0: $D000 I/O — 0=I/O visible, 1=RAM/CharROM
//
// 8502 processor port ($01) bits — same as C64 6510:
//   Bit 0: LORAM  — 1=BASIC ROM, 0=RAM
//   Bit 1: HIRAM  — 1=KERNAL ROM, 0=RAM
//   Bit 2: CHAREN — 1=I/O at $D000, 0=Char ROM
//
// IMPORTANT:
//   - CPU writes ALWAYS go to RAM regardless of banking (same as C64).
//   - ROM must be banked OUT to READ data from RAM underneath.
//   - $E000–$FFFF: must wrap access in SEI/CLI because hardware
//     IRQ/NMI vectors at $FFFE/$FFFF will read from RAM when
//     KERNAL is banked out.

// ============================================================
// MMU Constants (C128-specific)
// ============================================================
.const MMU_CR           = $ff00 // MMU Configuration Register (fast write)
.const MMU_NORMAL       = $0E   // Bank 0, System ROM (KERNAL+ScreenEd) at $C000, RAM $4000-$BFFF, I/O
                                // Bits 7-6=00(Bank0), 5-4=00(SysROM), 3-2=11(RAM), 1=1(RAM), 0=0(I/O)
.const MMU_RAM_BANK1    = $7E   // Bank 1, all RAM, I/O visible
                                // Bits 7-6=01(Bank1), 5-4=11(RAM), 3-2=11(RAM), 1=1(RAM), 0=0(I/O)
                                // Bank 1 has no ROMs — $C000-$CFFF is RAM, not Screen Ed ROM.
                                // Use to read Bank 0 $C000-$CFFF which is masked by Screen
                                // Editor ROM under MMU_NORMAL. Bank 1 still has the original
                                // game binary loaded there by boot128 (SETBNK A=1 / KERNAL LOAD).
.const MMU_ALL_RAM      = $3E   // Bank 0, all RAM, I/O visible
                                // Bits 7-6=00(Bank0), 5-4=11(RAM), 3-2=11(RAM), 1=1(RAM), 0=0(I/O)
                                // Hides Screen Editor ROM ($C000-$CFFF) AND KERNAL ROM
                                // ($E000-$FFFF) via MMU.  I/O still visible at $D000.
                                // Used as permanent operational mode after init; JMP stubs
                                // at $FFB7-$FFD5 in Bank 0 RAM handle KERNAL calls.

// ============================================================
// Processor port constants — same values as C64 (used by $01)
// Common code (reu.s, overlay.s, etc.) uses these directly.
// ============================================================
.const BANK_ALL_RAM     = $30  // All RAM, I/O visible (not usually needed)
.const BANK_ALL_ROM     = $37  // Default: BASIC + KERNAL + I/O
.const BANK_NO_BASIC    = $36  // KERNAL + I/O, RAM at $A000–$BFFF
.const BANK_NO_KERNAL   = $35  // I/O + RAM everywhere ($A000, $D000=I/O, $E000)
.const BANK_NO_ROMS     = $34  // I/O only, RAM at $A000 and $E000

// ============================================================
// VIC-II Color Palette Constants (Standard indices)
// ============================================================
.const COL_BLACK    = $00
.const COL_WHITE    = $01
.const COL_RED      = $02
.const COL_CYAN     = $03
.const COL_PURPLE   = $04
.const COL_GREEN    = $05
.const COL_BLUE     = $06
.const COL_YELLOW   = $07
.const COL_ORANGE   = $08
.const COL_BROWN    = $09
.const COL_LRED     = $0a
.const COL_DGREY    = $0b
.const COL_GREY     = $0c
.const COL_LGREEN   = $0d
.const COL_LBLUE    = $0e
.const COL_LGREY    = $0f

// Memory region bases — same as C64 (C128 system RAM layout matches)
// C128 "Lower Safe Zone" strategy:
//   $0400-$09FF: VIC-II/Scratch
//   $0A00-$0AFF: Screen Editor Workspace (RESERVED)
//   $0B00-$19FF: Dungeon Map (3,840 bytes)
//   $1A00-$1AFF: Floor Items (256 bytes)
//   $1B00-$1BFF: Creature Scratch/Misc
//   $1C01:        BASIC Start / Program entry
.const MAP_BASE         = $0b00 // Dungeon map (3,840 bytes)
.const MAP_END          = $19ff
.const FLOOR_ITEM_BASE  = $1a00 // Floor item table (256 bytes)
.const FLOOR_ITEM_END   = $1aff
.const CREATURE_BASE    = $1b00 // Runtime scratch area (RLE, hiscore)
.const CREATURE_END     = $1bff
.const BANKED_DATA_BASE = $e000 // Item tiers, recall, spells (under KERNAL ROM)
.const BANKED_DATA_END  = $ffff
.const SCREEN_RAM       = $0400 // VIC-II screen RAM (used as scratch buffer on C128)
.const COLOR_RAM        = $d800 // VIC-II color RAM (VDC has separate attributes)

// ZP save buffer — stores $02–$8F during game, restored on exit
// Using hardcoded address $0700 (VIC-II scratch RAM) to ensure it 
// doesn't overlap with code or the dungeon map.
.const ZP_SAVE_BUF_ADDR = $0700
.const ZP_SAVE_SIZE     = 142   // $02–$8F inclusive

// ============================================================
// Macros — use $01 for runtime banking (C64-compatible)
// ============================================================

// Bank out BASIC ROM — exposes RAM at $A000–$BFFF
// (On C128, BASIC is already out via MMU; this is a no-op for safety)
// Must keep bit 2 set for I/O.
.macro BankOutBasic() {
    lda $01
    and #%11111110  // Clear bit 0 (LORAM)
    ora #%00000100  // Ensure bit 2 (CHAREN) is 1
    sta $01
}

// Bank in BASIC ROM — restores ROM at $A000–$BFFF
// (On C128, MMU keeps BASIC out regardless, so this is effectively a no-op)
.macro BankInBasic() {
    lda $01
    ora #%00000101  // Set bit 0 (LORAM) and bit 2 (CHAREN)
    sta $01
}

// Bank out KERNAL ROM — exposes RAM at $E000–$FFFF
// MUST be called after SEI.
.macro BankOutKernal() {
    lda $01
    and #%11111101  // Clear bit 1 (HIRAM)
    ora #%00000100  // Ensure bit 2 (CHAREN) is 1
    sta $01
}

// Bank in KERNAL ROM — restores ROM at $E000–$FFFF
.macro BankInKernal() {
    lda $01
    ora #%00000110  // Set bit 1 (HIRAM) and bit 2 (CHAREN)
    sta $01
}

// Bank out both BASIC and KERNAL — RAM everywhere except I/O
// Caller MUST have called SEI first.
.macro BankOutAll() {
    lda $01
    and #%11111100  // Clear bits 0 and 1
    ora #%00000100  // Ensure bit 2 (CHAREN) is 1
    sta $01
}

// Restore default banking (BASIC + KERNAL + I/O)
.macro BankRestoreDefault() {
    lda #BANK_ALL_ROM
    sta $01
}

// MachineRestoreDefault — Ensure MMU and processor port are in a
// safe, operational state for KERNAL/Screen Editor.
// $FF00 = $0E (Bank 0, ROMs, I/O)
// $01   = $37 (All ROMs + I/O visible)
.macro MachineRestoreDefault() {
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_ALL_ROM
    sta $01
}

// MachineRestoreAllRam — Restore the game's operational MMU state.
// $FF00 = $3E (Bank 0, All RAM, I/O visible)
.macro MachineRestoreAllRam() {
    lda #MMU_ALL_RAM
    sta $ff00
}

// EnterKernal — Prepare for KERNAL calls (C128)
.macro EnterKernal() {
    php
    sei
    :MachineRestoreDefault()
}

// ExitKernal — Restore game state after KERNAL calls (C128)
.macro ExitKernal() {
    :MachineRestoreAllRam()
    plp
}

// MMU Bank 1 Access Macros
.macro Bank1Read() {
    lda #MMU_RAM_BANK1
    sta MMU_CR
}

.macro Bank1Write() {
    lda #MMU_RAM_BANK1
    sta MMU_CR
}

.macro Bank0Restore() {
    lda #MMU_NORMAL
    sta MMU_CR
}

// ============================================================
// Subroutines
// ============================================================

// save_zp — Copy $02–$8F to ZP_SAVE_BUF_ADDR
save_zp:
    ldx #0
!loop:
    lda $02,x
    sta ZP_SAVE_BUF_ADDR,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    rts

// restore_zp — Copy ZP_SAVE_BUF_ADDR back to $02–$8F
restore_zp:
    ldx #0
!loop:
    lda ZP_SAVE_BUF_ADDR,x
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

// read_banked_byte_e000 — Read a byte from Bank 1 RAM
// Input:  zp_ptr0/zp_ptr0_hi = address in $E000–$FFFF
//         Y = offset from pointer
// Output: A = byte read
// Preserves: X, Y
read_banked_byte_e000:
    sei
    lda #MMU_RAM_BANK1
    sta $ff00
    lda (zp_ptr0),y
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    pla
    rts

// copy_to_e000 — Bulk copy to RAM under KERNAL ROM
// Input:  zp_ptr0 = source address (lo/hi)
//         zp_ptr1 = dest address in $E000–$FFFF (lo/hi)
//         zp_temp0 = byte count lo
//         zp_temp1 = byte count hi
// Preserves: nothing
copy_to_e000:
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
.assert "Map fits in $1000 region", MAP_END - MAP_BASE + 1, 3840
.assert "Floor items fit", FLOOR_ITEM_END - FLOOR_ITEM_BASE + 1, 256
.assert "ZP save buffer doesn't overlap CREATURE_BASE", ZP_SAVE_BUF_ADDR + ZP_SAVE_SIZE <= CREATURE_BASE, true
.assert "ZP save buffer size", ZP_SAVE_SIZE, 142
