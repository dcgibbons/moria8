#importonce
// memory.s - Commander X16 memory and bank macro contract.
//
// CX16 does not have C64-style hidden RAM under KERNAL ROM. Banked RAM is
// selected through the zero-page RAM-bank register and appears at $A000-$BFFF.
//
// Current runtime contract:
// - Normal product code loads at $0801 and must end before MAP_BASE.
// - The live shared map stays in fixed RAM at MAP_BASE because the 198x66
//   map is larger than one 8 KiB banked-RAM window.
// - The $A000-$BFFF banked window is page-mapped RAM. Resident databases or
//   cached payloads must move through the helpers below so bank selection is
//   scoped and restored; normal gameplay must not treat it as hidden linear RAM.
// - C64/C128-style bank macros remain no-ops until shared runtime code is
//   split into explicit CX16 fixed-RAM and bank-window segments.

#import "hal/layout.s"

.const CX16_RAM_BANK_REG = $00
.const CX16_ROM_BANK_REG = $01
.const CX16_RAM_BANK_DEFAULT = 0
.const CX16_ROM_BANK_KERNAL = 0
.const CX16_PRG_LOAD_BASE = $0801
.const CX16_RESIDENT_CODE_BASE = $0810
.const CX16_RESIDENT_CODE_LIMIT = MAP_BASE
.const CX16_RAM_BANK_PROBE0 = 0
.const CX16_RAM_BANK_PROBE1 = 1
.const CX16_RAM_BANK_PROBE0_SENTINEL = $a5
.const CX16_RAM_BANK_PROBE1_SENTINEL = $5a
.const CX16_FIXED_RAM_BASE = $0000
.const CX16_FIXED_RAM_END  = $9eff
.const CX16_IO_BASE        = $9f00
.const CX16_IO_END         = $9fff
.const CX16_BANKED_RAM_BASE = $a000
.const CX16_BANKED_RAM_END  = $bfff
.const CX16_BANKED_RAM_SIZE = CX16_BANKED_RAM_END - CX16_BANKED_RAM_BASE + 1
.const CX16_FIXED_LIVE_MAP_BASE = MAP_BASE
.const CX16_FIXED_LIVE_MAP_END  = MAP_BASE + (hal_layout_map_cols * hal_layout_map_rows) - 1
.const BANKED_DATA_BASE = CX16_BANKED_RAM_BASE
.const BANKED_DATA_END  = CX16_BANKED_RAM_END
// C128-named compatibility aliases used by shared tier/item metadata.
.const BANK1_DB_BASE    = CX16_BANKED_RAM_BASE
.const BANK1_DB_END     = CX16_BANKED_RAM_END
.const MAP_END          = CX16_FIXED_LIVE_MAP_END
.const FLOOR_ITEM_BASE  = (CX16_FIXED_LIVE_MAP_END + $0100) & $ff00
.const FLOOR_ITEM_END   = FLOOR_ITEM_BASE + $00ff
.const CREATURE_BASE    = FLOOR_ITEM_BASE + $0100
.const CREATURE_END     = CREATURE_BASE + $00ff
.const CX16_FIXED_WORLD_BASE = CX16_FIXED_LIVE_MAP_BASE
.const CX16_FIXED_WORLD_END  = CREATURE_END
.const DUNGEON_GEN_BFS_QUEUE_BASE = $0400
.const DUNGEON_GEN_BFS_QUEUE_MAX  = 512
.const DUNGEON_GEN_BFS_QUEUE_END  = DUNGEON_GEN_BFS_QUEUE_BASE + (DUNGEON_GEN_BFS_QUEUE_MAX * 2) - 1

.assert "CX16 PRG load base matches BASIC stub", CX16_PRG_LOAD_BASE, $0801
.assert "CX16 resident machine-code base", CX16_RESIDENT_CODE_BASE, $0810
.assert "CX16 live map starts at fixed RAM MAP_BASE", CX16_FIXED_LIVE_MAP_BASE, MAP_BASE
.assert "CX16 live map span matches HAL layout", MAP_END - MAP_BASE + 1, hal_layout_map_cols * hal_layout_map_rows
.assert "CX16 live map is larger than one banked-RAM window", MAP_END - MAP_BASE + 1 > CX16_BANKED_RAM_SIZE, true
.assert "CX16 floor items stay after live map", MAP_END < FLOOR_ITEM_BASE, true
.assert "CX16 floor item table is page-aligned", <FLOOR_ITEM_BASE, 0
.assert "CX16 floor items fit", FLOOR_ITEM_END - FLOOR_ITEM_BASE + 1, 256
.assert "CX16 creature scratch stays after floor items", FLOOR_ITEM_END < CREATURE_BASE, true
.assert "CX16 creature scratch is page-aligned", <CREATURE_BASE, 0
.assert "CX16 Huffman decode buffer stays after fixed world", CX16_FIXED_WORLD_END < PLATFORM_HD_DECODE_BUF_BASE, true
.assert "CX16 Huffman decode buffer stays below VERA I/O hole", PLATFORM_HD_DECODE_BUF_LIMIT <= CX16_IO_BASE, true
.assert "CX16 dungeon-gen BFS queue remains page-aligned", <DUNGEON_GEN_BFS_QUEUE_BASE, 0
.assert "CX16 dungeon-gen BFS queue stays below PRG load base", DUNGEON_GEN_BFS_QUEUE_END < CX16_PRG_LOAD_BASE, true
.assert "CX16 banked RAM window is 8 KiB", CX16_BANKED_RAM_SIZE, $2000
.assert "CX16 fixed live map stays below VERA I/O hole", MAP_END < CX16_IO_BASE, true
.assert "CX16 floor items stay below VERA I/O hole", FLOOR_ITEM_END < CX16_IO_BASE, true
.assert "CX16 creature scratch stays below VERA I/O hole", CREATURE_END < CX16_IO_BASE, true
.assert "CX16 fixed world stays below VERA I/O hole", CX16_FIXED_WORLD_END < CX16_IO_BASE, true
.assert "CX16 bank window starts after fixed world", CX16_BANKED_RAM_BASE > CX16_FIXED_WORLD_END, true
.assert "CX16 shared banked-data alias matches bank window", BANKED_DATA_BASE, CX16_BANKED_RAM_BASE
.assert "CX16 C128 DB alias maps to bank window", BANK1_DB_BASE, CX16_BANKED_RAM_BASE

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

cx16_memory_init:
    lda #CX16_ROM_BANK_KERNAL
    sta CX16_ROM_BANK_REG
    lda #CX16_RAM_BANK_DEFAULT
    sta CX16_RAM_BANK_REG
    jmp cx16_probe_ram_banks

// CX16 bank-window helpers. These operate only on the RAM bank visible at
// $A000-$BFFF; callers own the selected bank number and pointer validity.
cx16_saved_ram_bank: .byte 0
cx16_transfer_bank: .byte 0
cx16_probe_bank0_save: .byte 0
cx16_probe_bank1_save: .byte 0

cx16_save_ram_bank:
    lda CX16_RAM_BANK_REG
    sta cx16_saved_ram_bank
    rts

cx16_select_ram_bank_a:
    sta CX16_RAM_BANK_REG
    rts

cx16_restore_ram_bank:
    lda cx16_saved_ram_bank
    sta CX16_RAM_BANK_REG
    rts

read_banked_byte_a000:
    lda (zp_ptr0),y
    rts

write_banked_byte_a000:
    sta (zp_ptr0),y
    rts

// Copy zp_temp1 full pages plus zp_temp0 trailing bytes from fixed RAM
// (zp_ptr0) to the currently selected bank window (zp_ptr1).
// Clobbers A/X/Y and advances high bytes in zp_ptr0/zp_ptr1 for full pages.
cx16_copy_fixed_to_banked_selected:
    lda zp_temp0
    ora zp_temp1
    beq !done+
    ldx zp_temp1
    beq !tail+
!page:
    ldy #0
!page_loop:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    bne !page_loop-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dex
    bne !page-
!tail:
    ldx zp_temp0
    beq !done+
    ldy #0
!tail_loop:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    dex
    bne !tail_loop-
!done:
    rts

// Copy zp_temp1 full pages plus zp_temp0 trailing bytes from the currently
// selected bank window (zp_ptr1) to fixed RAM (zp_ptr0).
// Clobbers A/X/Y and advances high bytes in zp_ptr0/zp_ptr1 for full pages.
cx16_copy_banked_to_fixed_selected:
    lda zp_temp0
    ora zp_temp1
    beq !done+
    ldx zp_temp1
    beq !tail+
!page:
    ldy #0
!page_loop:
    lda (zp_ptr1),y
    sta (zp_ptr0),y
    iny
    bne !page_loop-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dex
    bne !page-
!tail:
    ldx zp_temp0
    beq !done+
    ldy #0
!tail_loop:
    lda (zp_ptr1),y
    sta (zp_ptr0),y
    iny
    dex
    bne !tail_loop-
!done:
    rts

// Input: A = RAM bank, zp_ptr0 = fixed RAM address, zp_ptr1 = bank-window
// address, zp_temp1:zp_temp0 = byte count. Restores the previous RAM bank.
cx16_copy_fixed_to_banked:
    sta cx16_transfer_bank
    jsr cx16_save_ram_bank
    lda cx16_transfer_bank
    jsr cx16_select_ram_bank_a
    jsr cx16_copy_fixed_to_banked_selected
    jmp cx16_restore_ram_bank

// Input: A = RAM bank, zp_ptr0 = fixed RAM address, zp_ptr1 = bank-window
// address, zp_temp1:zp_temp0 = byte count. Restores the previous RAM bank.
cx16_copy_banked_to_fixed:
    sta cx16_transfer_bank
    jsr cx16_save_ram_bank
    lda cx16_transfer_bank
    jsr cx16_select_ram_bank_a
    jsr cx16_copy_banked_to_fixed_selected
    jmp cx16_restore_ram_bank

cx16_probe_ram_banks:
    jsr cx16_save_ram_bank

    lda #CX16_RAM_BANK_PROBE0
    jsr cx16_select_ram_bank_a
    lda CX16_BANKED_RAM_BASE
    sta cx16_probe_bank0_save
    lda #CX16_RAM_BANK_PROBE0_SENTINEL
    sta CX16_BANKED_RAM_BASE

    lda #CX16_RAM_BANK_PROBE1
    jsr cx16_select_ram_bank_a
    lda CX16_BANKED_RAM_BASE
    sta cx16_probe_bank1_save
    lda #CX16_RAM_BANK_PROBE1_SENTINEL
    sta CX16_BANKED_RAM_BASE

    lda #CX16_RAM_BANK_PROBE0
    jsr cx16_select_ram_bank_a
    lda CX16_BANKED_RAM_BASE
    cmp #CX16_RAM_BANK_PROBE0_SENTINEL
    bne !fail+
    lda cx16_probe_bank0_save
    sta CX16_BANKED_RAM_BASE

    lda #CX16_RAM_BANK_PROBE1
    jsr cx16_select_ram_bank_a
    lda CX16_BANKED_RAM_BASE
    cmp #CX16_RAM_BANK_PROBE1_SENTINEL
    bne !fail+
    lda cx16_probe_bank1_save
    sta CX16_BANKED_RAM_BASE

    jsr cx16_restore_ram_bank
    clc
    rts

!fail:
    lda #CX16_RAM_BANK_PROBE0
    jsr cx16_select_ram_bank_a
    lda cx16_probe_bank0_save
    sta CX16_BANKED_RAM_BASE
    lda #CX16_RAM_BANK_PROBE1
    jsr cx16_select_ram_bank_a
    lda cx16_probe_bank1_save
    sta CX16_BANKED_RAM_BASE
    jsr cx16_restore_ram_bank
    sec
    rts
