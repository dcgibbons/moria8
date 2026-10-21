// memory.s — Commander X16 memory map constants, ZP save/restore, and
// bank-register definitions.
//
// Authority: docs/CX16_MEMORY_CONTRACT.md.
//
// Fixed low RAM ($0000-$9EFF):
//   $0000-$0001  CX16 RAM/ROM bank registers
//   $0002-$008F  shared core ZP (saved/restored around KERNAL file I/O)
//   $0090-$00FF  CX16 KERNAL ZP
//   $0100-$01FF  hardware stack
//   $0200-$03FF  KERNAL vectors and system scratch
//   $0400-$04FF  floor-item table (256 B)
//   $0500-$05FF  creature/RLE/hiscore scratch (256 B)
//   $0600-$06FF  Huffman decode & dungeon-gen door-scan scratch (256 B)
//   $0700-$07FF  VERA viewport row staging buffers (256 B)
//   $0801-$9AFF  unified Resident + Play image (MORIA8.PRG)
//   $9B00-$9EFF  active monster tier name pool (1,024 B)
//   $9F00-$9FFF  hardware I/O hole (VIA1/VIA2 + VERA)
//
// Banked RAM window ($A000-$BFFF, 8 KB x 64 banks via ZP $00):
//   Bank 0:      KERNAL KVARSB0 (never overwritten)
//   Banks 1-2:   198x66 live map (virtual $2000-$530B)
//   Bank 3:      Cx16AuxData (virtual $6000-$7FFF)
//   Bank 4:      Cx16HuffData (virtual $8000-$9FFF)
//   Banks 5-8:   MONSTER.DB.1..4
//   Banks 9-20:  12 code overlays (OVL_STARTUP..OVL_TITLE = IDs 1..12)
//   Bank 21:     TITLE art stream

#import "hal/memory_bank_consts.s"
#import "hal/entropy_consts.s"

// ============================================================
// Hardware Bank Registers & Bank Assignments
// ============================================================
.const CX16_RAM_BANK_REG        = $00
.const CX16_ROM_BANK_REG        = $01
.const CX16_ROM_BANK_KERNAL     = $00

.const CX16_BANK_KERNAL_VARS    = 0
.const CX16_BANK_MAP_LO         = 1
.const CX16_BANK_MAP_HI         = 2
.const CX16_BANK_AUXDATA        = 3
.const CX16_BANK_HUFFDATA       = 4
.const CX16_BANK_TIER_BASE      = 5
.const CX16_BANK_TIER_END       = 8
.const CX16_BANK_OVERLAY_BASE   = 9
.const CX16_BANK_OVERLAY_END    = 20
.const CX16_BANK_TITLE_ART      = 21

// ============================================================
// Virtual & Physical Memory Map Constants
// ============================================================
.const MAP_BASE                 = $2000 // Virtual: Banks 1-2 ($2000-$530B = 13,068 B)
.const MAP_END                  = $530b
.const CX16_AUXDATA_VIRT_BASE   = $6000 // Virtual: Bank 3 ($6000-$7FFF)
.const CX16_AUXDATA_VIRT_END    = $7fff
.const CX16_HUFFDATA_VIRT_BASE  = $8000 // Virtual: Bank 4 ($8000-$9FFF)
.const CX16_HUFFDATA_VIRT_END   = $9fff

.const FLOOR_ITEM_BASE          = $0400 // Fixed low RAM: floor item table (256 B)
.const FLOOR_ITEM_END           = $04ff
.const CREATURE_BASE            = $0500 // Fixed low RAM: creature/hiscore scratch (256 B)
.const CREATURE_END             = $05ff
.const DUNGEON_GEN_DOOR_SCAN_BASE  = hal_layout_dungeon_door_scan_base
.const DUNGEON_GEN_DOOR_SCAN_LIMIT = hal_layout_dungeon_door_scan_limit
.const CX16_ROW_STAGE_BASE      = $0700 // Fixed low RAM: VERA row staging (256 B)
.const CX16_ROW_STAGE_END       = $07ff

.const CX16_RESIDENT_BASE       = $0801
.const CX16_RESIDENT_LIMIT      = $9b00

.const PLATFORM_TIER_NAME_POOL_BASE = $9b00 // Fixed low RAM: active tier names (1,024 B)
.const PLATFORM_TIER_NAME_POOL_END  = $9eff

.const CX16_IO_BASE             = $9f00
.const CX16_IO_END              = $9fff

.const BANKED_DATA_BASE         = $a000 // 8 KB banked RAM window ($A000-$BFFF)
.const BANKED_DATA_END          = $bfff
.const BANK1_DB_BASE            = BANKED_DATA_BASE
.const SCREEN_RAM               = $ffff // Unused on CX16; VERA text lives at VRAM $1B000
.const COLOR_RAM                = $ffff

.const ZP_SAVE_BASE             = $80
.const ZP_SAVE_SIZE             = 16    // $80-$8F inclusive (saved around KERNAL file I/O)

// ============================================================
// Compatibility macros
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
// Subroutines & Scratch
// ============================================================
zp_save_buf:            .fill ZP_SAVE_SIZE, 0
cx16_zp_scratch:        .byte 0
cx16_save_aux_mode_flag: .byte 0

// save_zp — Copy $80-$8F to zp_save_buf around KERNAL file I/O
// Preserves: nothing (uses A, X)
save_zp:
    ldx #0
!loop:
    lda ZP_SAVE_BASE,x
    sta zp_save_buf,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    rts

// restore_zp — Copy zp_save_buf back to $80-$8F
// Preserves: nothing (uses A, X)
restore_zp:
    ldx #0
!loop:
    lda zp_save_buf,x
    sta ZP_SAVE_BASE,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    rts

mmu_select_bank1:
    rts

mmu_select_bank0:
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Banked map fits 198x66", MAP_END - MAP_BASE + 1, 13068
.assert "Map virtual base starts at Bank 1 ($2000)", (MAP_BASE >> 13), CX16_BANK_MAP_LO
.assert "Map virtual end lands in Bank 2 ($4000-$5FFF)", (MAP_END >> 13), CX16_BANK_MAP_HI
.assert "AuxData virtual base starts at Bank 3 ($6000)", (CX16_AUXDATA_VIRT_BASE >> 13), CX16_BANK_AUXDATA
.assert "HuffData virtual base starts at Bank 4 ($8000)", (CX16_HUFFDATA_VIRT_BASE >> 13), CX16_BANK_HUFFDATA
.assert "Floor items fit 256 bytes", FLOOR_ITEM_END - FLOOR_ITEM_BASE + 1, 256
.assert "Creature scratch fits 256 bytes", CREATURE_END - CREATURE_BASE + 1, 256
.assert "Door scan scratch stays in $0600-$06FF", DUNGEON_GEN_DOOR_SCAN_BASE >= $0600 && DUNGEON_GEN_DOOR_SCAN_BASE + 65 <= $0700, true
.assert "Tier name pool is 1,024 bytes below $9F00 I/O hole", PLATFORM_TIER_NAME_POOL_END - PLATFORM_TIER_NAME_POOL_BASE + 1 == 1024 && PLATFORM_TIER_NAME_POOL_END < CX16_IO_BASE, true
.assert "Resident ceiling ends at tier name pool base", CX16_RESIDENT_LIMIT, PLATFORM_TIER_NAME_POOL_BASE
.assert "Banked window is 8,192 bytes ($A000-$BFFF)", BANKED_DATA_END - BANKED_DATA_BASE + 1, 8192
.assert "ZP save buffer size", ZP_SAVE_SIZE, 16
