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
#import "hal/layout.s"
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
// The monster catalog splits that hidden span (core/monster_catalog.s,
// common/catalog_fetch.s; maintainer, 2026-11-05): 32 species names of 32
// bytes, then the level index and record-sector table MONSTER.IDX fills at boot.
.const CATALOG_NAME_POOL_BASE = PLATFORM_TIER_NAME_POOL_BASE
.const CATALOG_NAME_POOL_END  = $d3ff
.const CATALOG_HIDDEN_BASE    = CATALOG_NAME_POOL_END + 1
.const CATALOG_HIDDEN_END     = $d4ff
// The rest of that span (2026-11-08): the Huffman string index, copied there
// at boot (main.s platform_services_install64) and read by
// hal_huff_index_word, as on the Plus/4. Its two pages leave the index room
// to grow; $D700-$D7FF is free.
.const HUFF_INDEX_HIDDEN_BASE = CATALOG_HIDDEN_END + 1
.const HUFF_INDEX_HIDDEN_END  = $d6ff
// MONSTER.IDX's boot buffer: the map's last page, unused until the first
// level, past the init-only tail; the $E000 window holds the title's overlay.
.const CATALOG_IDX_LOAD       = $ce00
.assert "MONSTER.IDX's boot buffer is in the map", CATALOG_IDX_LOAD >= MAP_BASE && CATALOG_IDX_LOAD + $ff <= MAP_END, true
.assert "Catalog hidden span, then the Huffman index, lie in the old tier name pool", HUFF_INDEX_HIDDEN_BASE == CATALOG_HIDDEN_END + 1 && HUFF_INDEX_HIDDEN_END <= PLATFORM_TIER_NAME_POOL_END, true
.const C64_TIER_NAME_POOL_BASE = PLATFORM_TIER_NAME_POOL_BASE // Legacy C64 tests
.const C64_TIER_NAME_POOL_END  = PLATFORM_TIER_NAME_POOL_END
// ZP save buffer — stores $02–$8F during game, restored on exit ($D700-$D78D, !C64_CARTRIDGE)
.const ZP_SAVE_SIZE     = 142   // $02–$8F inclusive
// Phase 1 hidden DRAM window under I/O: $D700-$DEFF (2,048 B).
// $DF00-$DFFF stays strictly reserved/untouched so REU I/O registers
// ($DF00-$DF0A) and cartridge I/O ($DFxx) are never touched via I/O or RAM.
.const C64_HIDDEN_AUX_BASE         = $d700
.const C64_HIDDEN_AUX_END          = $deff
.const C64_HIDDEN_RAM_RESERVE_BASE = $df00
.const C64_HIDDEN_RAM_RESERVE_END  = $dfff
.const C64_HIDDEN_ZP_SAVE_BASE     = C64_HIDDEN_AUX_BASE                 // $D700-$D78D (142 B, !C64_CARTRIDGE)
.const C64_HIDDEN_MSG_HIST_BASE    = C64_HIDDEN_ZP_SAVE_BASE + ZP_SAVE_SIZE // $D78E-$D8CD (320 B)
.const C64_HIDDEN_RECALL_BASE      = C64_HIDDEN_MSG_HIST_BASE + 320      // $D8CE-$DD29 (1,116 B, recall[279])
.const C64_HIDDEN_FREE_BASE        = C64_HIDDEN_RECALL_BASE + 1116       // $DD2A-$DEFF (470 B free)
.assert "C64 hidden aux starts right after Huffman index", C64_HIDDEN_AUX_BASE == HUFF_INDEX_HIDDEN_END + 1, true
.assert "C64 hidden aux excludes $DF00-$DFFF I/O page", C64_HIDDEN_AUX_END < C64_HIDDEN_RAM_RESERVE_BASE, true
.assert "C64 recall[279] excludes $DE00-$DFFF cartridge/REU I/O pages", C64_HIDDEN_RECALL_BASE + 1116 <= $de00, true
.assert "C64 hidden aux allocations fit within $D700-$DEFF", C64_HIDDEN_FREE_BASE <= C64_HIDDEN_AUX_END + 1, true
.const BANKED_DATA_BASE = $e000 // Item tiers, recall, spells (under KERNAL ROM)
.const BANKED_DATA_END  = $ffff
// C128-only constant used by shared tier_manager staging metadata.
// C64 never executes this path (runtime machine check), but symbol must exist.
.const BANK1_DB_BASE    = $e000
.const SCREEN_RAM       = $0400
.const COLOR_RAM        = $d800
.const DUNGEON_GEN_SCAN_SCRATCH_BASE = SCREEN_RAM
.const DUNGEON_GEN_SCAN_SCRATCH_SIZE = 1024
.const DUNGEON_GEN_SCAN_SCRATCH_END  = DUNGEON_GEN_SCAN_SCRATCH_BASE + DUNGEON_GEN_SCAN_SCRATCH_SIZE - 1
// The optional EasyFlash boot copier uses $033C-$03FB before application
// entry (cartridge_boot.s asserts the bounds). Generation takes this scratch
// later; the copier is no longer live. KERNAL keyboard state at $0277-$02FF
// must remain untouched by boot copying.
.const DUNGEON_GEN_DOOR_SCAN_BASE = $033c
.const DUNGEON_GEN_DOOR_SCAN_LIMIT = $0400

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

#if !C64_CARTRIDGE
// The disk build owns this session-long BASIC exit snapshot in hidden DRAM
// ($D700-$D78D); the cartridge lifecycle stays in the game/title and has no
// BASIC-return caller.
.label zp_save_buf = C64_HIDDEN_ZP_SAVE_BASE

// save_zp — Copy $02–$8F to zp_save_buf ($D700-$D78D) under SEI + $01=$34
// Preserves: $01, I flag (clobbers A, X)
save_zp:
    php
    sei
    lda $01
    pha
    lda #BANK_NO_ROMS
    sta $01
    ldx #0
!loop:
    lda zp_temp0,x
    sta zp_save_buf,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    pla
    sta $01
    plp
    rts

// restore_zp — Copy zp_save_buf ($D700-$D78D) back to $02–$8F under SEI + $01=$34
// Preserves: $01, I flag (clobbers A, X)
restore_zp:
    php
    sei
    lda $01
    pha
    lda #BANK_NO_ROMS
    sta $01
    ldx #0
!loop:
    lda zp_save_buf,x
    sta zp_temp0,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    pla
    sta $01
    plp
    rts
#endif

// ============================================================
// Hidden DRAM helpers ($D700-$DEFF under SEI + $01=$34)
// ============================================================
c64_hidden_tmp: .byte 0

// c64_hidden_write_ptr0 / c64_hidden_write_ptr1
// Write A to (zp_ptr0),y or (zp_ptr1),y in hidden RAM under SEI + $01=$34.
// Preserves: A, X, Y, $01, I flag
c64_hidden_write_ptr1:
    php
    sei
    sta c64_hidden_tmp
    lda #zp_ptr1
    bne c64_hidden_write_zp
c64_hidden_write_ptr0:
    php
    sei
    sta c64_hidden_tmp
    lda #zp_ptr0
c64_hidden_write_zp:
    sta !hw_op+ + 1
    lda $01
    pha
    lda #BANK_NO_ROMS
    sta $01
    lda c64_hidden_tmp
!hw_op:
    sta (zp_ptr0),y
c64_hidden_exit:
    pla
    sta $01
    plp
    lda c64_hidden_tmp
    rts

// c64_hidden_read_ptr0 / c64_hidden_read_ptr1
// Read (zp_ptr0),y or (zp_ptr1),y from hidden RAM under SEI + $01=$34 into A (N/Z set).
// Preserves: X, Y, $01, I flag
c64_hidden_read_ptr1:
    lda #zp_ptr1
    .byte $2c               // BIT abs: skips next 2-byte lda #zp_ptr0
c64_hidden_read_ptr0:
    lda #zp_ptr0
    php
    sei
    sta !hr_op+ + 1
    lda $01
    pha
    lda #BANK_NO_ROMS
    sta $01
!hr_op:
    lda (zp_ptr0),y
    sta c64_hidden_tmp
    jmp c64_hidden_exit

// c64_hidden_inc_ptr0
// Increment byte at (zp_ptr0),y in hidden RAM under SEI + $01=$34; A = new value (N/Z set).
// Preserves: X, Y, $01, I flag
c64_hidden_inc_ptr0:
    php
    sei
    lda $01
    pha
    lda #BANK_NO_ROMS
    sta $01
    lda (zp_ptr0),y
    clc
    adc #1
    sta (zp_ptr0),y
    sta c64_hidden_tmp
    jmp c64_hidden_exit

// c64_hidden_copy
// Copy X bytes (1..255; X=0 copies 256 bytes) from (zp_ptr0) to (zp_ptr1)
// under SEI + $01=$34 (supports both directions with $D700-$DEFF).
// Clobbers: A, X, Y   Preserves: $01, I flag, zp_ptr0, zp_ptr1
c64_hidden_copy:
    php
    sei
    lda $01
    pha
    lda #BANK_NO_ROMS
    sta $01
    ldy #0
!copy:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    dex
    bne !copy-
    pla
    sta $01
    plp
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
.assert "Dungeon-gen scan scratch remains page-aligned", <DUNGEON_GEN_SCAN_SCRATCH_BASE, 0
.assert "Dungeon-gen scan scratch stays in screen scratch window", DUNGEON_GEN_SCAN_SCRATCH_END <= $07ff, true
.assert "Dungeon-gen door scan stays in cassette buffer", DUNGEON_GEN_DOOR_SCAN_BASE >= $033c && DUNGEON_GEN_DOOR_SCAN_BASE + 65 <= $0400, true
#if !C64_CARTRIDGE
.assert "ZP save buffer sits in $D700-$D78D hidden aux", zp_save_buf >= C64_HIDDEN_AUX_BASE && zp_save_buf + ZP_SAVE_SIZE <= C64_HIDDEN_MSG_HIST_BASE, true
.assert "restore_zp stays reachable below BASIC ROM", restore_zp < $a000, true
#endif
.assert "ZP save buffer size", ZP_SAVE_SIZE, 142
