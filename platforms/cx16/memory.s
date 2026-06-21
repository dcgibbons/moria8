#importonce
// memory.s - Commander X16 memory and bank macro contract.
//
// CX16 does not have C64-style hidden RAM under KERNAL ROM. Banked RAM is
// selected through the zero-page RAM-bank register and appears at $A000-$BFFF.
//
// CX16 ownership manifest
// ============================================================
// Fixed RAM:
//   - zero page / KERNAL workspace:  $0000-$03FF
//   - dungeon-gen BFS queue:         $0400-$07FF
//   - resident product image:        $0801-(CX16_RESIDENT_PRODUCT_LIMIT-1)
//   - fixed-code growth reserve:     CX16_RESIDENT_PRODUCT_LIMIT-(MAP_BASE-1)
//   - live map, 198x66:              MAP_BASE-MAP_END
//   - floor item table:              FLOOR_ITEM_BASE-FLOOR_ITEM_END
//   - active monster arena:          CREATURE_BASE-CREATURE_END
//   - Huffman decode scratch:        PLATFORM_HD_DECODE_BUF_BASE-PLATFORM_HD_DECODE_BUF_LIMIT-1
//   - VERA/I/O hole:                 $9F00-$9FFF
//
// Banked RAM window:
//   - bank 0:   default/system bank; never persistent cache
//   - banks 1-3: transient scratch/loader/test banks; caller must not assume
//                payload survival across subsystem calls
//   - banks 4-7: persistent monster tier cache, MONSTER.DB.1-4
//   - bank 8:   persistent executable dungeon-generation module, DUNGEON.GEN
//   - banks 9-10: persistent item catalog family, ITEMCAT.1 plus reserved
//                 item text/extra split bank
//   - bank 11:  title-art source/staging bank, TITLE
//   - banks 12-21: reserved Commodore-style overlay slots:
//                  STARTUP, TOWN, DEATH, ROYAL, GEN, HELP, UI, ITEMS,
//                  SPELL, DISARM
//   - banks 22-31: unallocated persistent code-overlay expansion class
//   - banks 32-47: unallocated persistent immutable-data/string cache class
//   - banks 48-63: unallocated transient save/generation/work cache class
//
// Rules:
//   - Product code must stay below MAP_BASE unless it is emitted as an
//     explicit bank-window PRG/module.
//   - Live map stays fixed until a deliberate split-window map accessor exists;
//     the 198x66 map is larger than one 8 KiB banked-RAM window.
//   - Every persistent bank assignment must have a named constant, load base,
//     lifecycle comment, and memory-contract checker coverage.
//   - Bank 0 is not cache storage. Banks 1-3 and 48-63 are scratch by class.
//   - Shared code may read/write banked payloads only through platform-owned
//     helpers that scope and restore the selected RAM bank.

#import "hal/layout.s"

.const CX16_RAM_BANK_REG = $00
.const CX16_ROM_BANK_REG = $01
.const CX16_RAM_BANK_COUNT = 64
.const CX16_RAM_BANK_LAST = CX16_RAM_BANK_COUNT - 1
.const CX16_RAM_BANK_DEFAULT = 0
.const CX16_ROM_BANK_KERNAL = 0
.const CX16_PRG_LOAD_BASE = $0801
.const CX16_RESIDENT_CODE_BASE = $0810
.const CX16_RESIDENT_CODE_LIMIT = MAP_BASE
.const CX16_RESIDENT_PRODUCT_LIMIT = $6000
.const CX16_RAM_BANK_PROBE0 = 0
.const CX16_RAM_BANK_PROBE1 = 1
.const CX16_RAM_BANK_PROBE0_SENTINEL = $a5
.const CX16_RAM_BANK_PROBE1_SENTINEL = $5a
.const CX16_TRANSIENT_BANK_BASE = 1
.const CX16_TRANSIENT_BANK_END = 3
.const CX16_FIXED_RAM_BASE = $0000
.const CX16_FIXED_RAM_END  = $9eff
.const CX16_IO_BASE        = $9f00
.const CX16_IO_END         = $9fff
.const CX16_BANKED_RAM_BASE = $a000
.const CX16_BANKED_RAM_END  = $bfff
.const CX16_BANKED_RAM_SIZE = CX16_BANKED_RAM_END - CX16_BANKED_RAM_BASE + 1
.const CX16_TIER_BANK_BASE = 4
.const CX16_TIER_BANK_END = CX16_TIER_BANK_BASE + 3
.const CX16_DUNGEON_MODULE_BANK = CX16_TIER_BANK_END + 1
.const CX16_ITEM_CATALOG_BANK_BASE = CX16_DUNGEON_MODULE_BANK + 1
.const CX16_ITEM_CATALOG_BANK_END = CX16_ITEM_CATALOG_BANK_BASE + 1
.const CX16_TITLE_SOURCE_BANK = CX16_ITEM_CATALOG_BANK_END + 1
.const CX16_TITLE_SOURCE_LOAD_BASE = CX16_BANKED_RAM_BASE
.const CX16_TITLE_SOURCE_LOAD_END = CX16_BANKED_RAM_END
.const CX16_OVERLAY_CACHE_BANK_BASE = CX16_TITLE_SOURCE_BANK + 1
.const CX16_OVERLAY_CACHE_BANK_END = 31
.const CX16_OVERLAY_STARTUP_BANK = CX16_OVERLAY_CACHE_BANK_BASE
.const CX16_OVERLAY_TOWN_BANK = CX16_OVERLAY_STARTUP_BANK + 1
.const CX16_OVERLAY_DEATH_BANK = CX16_OVERLAY_TOWN_BANK + 1
.const CX16_OVERLAY_ROYAL_BANK = CX16_OVERLAY_DEATH_BANK + 1
.const CX16_OVERLAY_GEN_BANK = CX16_OVERLAY_ROYAL_BANK + 1
.const CX16_OVERLAY_HELP_BANK = CX16_OVERLAY_GEN_BANK + 1
.const CX16_OVERLAY_UI_BANK = CX16_OVERLAY_HELP_BANK + 1
.const CX16_OVERLAY_ITEMS_BANK = CX16_OVERLAY_UI_BANK + 1
.const CX16_OVERLAY_SPELL_BANK = CX16_OVERLAY_ITEMS_BANK + 1
.const CX16_OVERLAY_DISARM_BANK = CX16_OVERLAY_SPELL_BANK + 1
.const CX16_OVERLAY_SLOT_BANK_BASE = CX16_OVERLAY_STARTUP_BANK
.const CX16_OVERLAY_SLOT_BANK_END = CX16_OVERLAY_DISARM_BANK
.const CX16_OVERLAY_FREE_BANK_BASE = CX16_OVERLAY_SLOT_BANK_END + 1
.const CX16_OVERLAY_FREE_BANK_END = CX16_OVERLAY_CACHE_BANK_END
.const CX16_DATA_CACHE_BANK_BASE = CX16_OVERLAY_CACHE_BANK_END + 1
.const CX16_DATA_CACHE_BANK_END = 47
.const CX16_WORK_BANK_BASE = CX16_DATA_CACHE_BANK_END + 1
.const CX16_WORK_BANK_END = CX16_RAM_BANK_LAST
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
.const CX16_ACTIVE_MONSTER_TABLE_BYTES = 32 * 12
.const CREATURE_END     = CREATURE_BASE + CX16_ACTIVE_MONSTER_TABLE_BYTES - 1
.const CX16_FIXED_WORLD_BASE = CX16_FIXED_LIVE_MAP_BASE
.const CX16_FIXED_WORLD_END  = CREATURE_END
.const DUNGEON_GEN_BFS_QUEUE_BASE = $0400
.const DUNGEON_GEN_BFS_QUEUE_MAX  = 512
.const DUNGEON_GEN_BFS_QUEUE_END  = DUNGEON_GEN_BFS_QUEUE_BASE + (DUNGEON_GEN_BFS_QUEUE_MAX * 2) - 1

.assert "CX16 PRG load base matches BASIC stub", CX16_PRG_LOAD_BASE, $0801
.assert "CX16 resident machine-code base", CX16_RESIDENT_CODE_BASE, $0810
.assert "CX16 resident product limit stays below live-map base", CX16_RESIDENT_PRODUCT_LIMIT < CX16_RESIDENT_CODE_LIMIT, true
.assert "CX16 resident product keeps at least 2KB fixed-code reserve", CX16_RESIDENT_CODE_LIMIT - CX16_RESIDENT_PRODUCT_LIMIT >= $0800, true
.assert "CX16 RAM bank count covers 512KB banked RAM", CX16_RAM_BANK_COUNT * CX16_BANKED_RAM_SIZE, 512 * 1024
.assert "CX16 default bank is bank 0", CX16_RAM_BANK_DEFAULT, 0
.assert "CX16 transient bank class starts after default bank", CX16_TRANSIENT_BANK_BASE, CX16_RAM_BANK_DEFAULT + 1
.assert "CX16 transient bank span is three banks", CX16_TRANSIENT_BANK_END - CX16_TRANSIENT_BANK_BASE + 1, 3
.assert "CX16 live map starts at fixed RAM MAP_BASE", CX16_FIXED_LIVE_MAP_BASE, MAP_BASE
.assert "CX16 live map span matches HAL layout", MAP_END - MAP_BASE + 1, hal_layout_map_cols * hal_layout_map_rows
.assert "CX16 live map is larger than one banked-RAM window", MAP_END - MAP_BASE + 1 > CX16_BANKED_RAM_SIZE, true
.assert "CX16 floor items stay after live map", MAP_END < FLOOR_ITEM_BASE, true
.assert "CX16 floor item table is page-aligned", <FLOOR_ITEM_BASE, 0
.assert "CX16 floor items fit", FLOOR_ITEM_END - FLOOR_ITEM_BASE + 1, 256
.assert "CX16 active monster arena stays after floor items", FLOOR_ITEM_END < CREATURE_BASE, true
.assert "CX16 active monster arena is page-aligned", <CREATURE_BASE, 0
.assert "CX16 active monster arena is 384 bytes", CREATURE_END - CREATURE_BASE + 1, CX16_ACTIVE_MONSTER_TABLE_BYTES
.assert "CX16 active monster arena fits shared active table", CREATURE_END - CREATURE_BASE + 1 >= CX16_ACTIVE_MONSTER_TABLE_BYTES, true
.assert "CX16 Huffman decode buffer stays after fixed world", CX16_FIXED_WORLD_END < PLATFORM_HD_DECODE_BUF_BASE, true
.assert "CX16 Huffman decode buffer stays below VERA I/O hole", PLATFORM_HD_DECODE_BUF_LIMIT <= CX16_IO_BASE, true
.assert "CX16 dungeon-gen BFS queue remains page-aligned", <DUNGEON_GEN_BFS_QUEUE_BASE, 0
.assert "CX16 dungeon-gen BFS queue stays below PRG load base", DUNGEON_GEN_BFS_QUEUE_END < CX16_PRG_LOAD_BASE, true
.assert "CX16 banked RAM window is 8 KiB", CX16_BANKED_RAM_SIZE, $2000
.assert "CX16 fixed live map stays below VERA I/O hole", MAP_END < CX16_IO_BASE, true
.assert "CX16 floor items stay below VERA I/O hole", FLOOR_ITEM_END < CX16_IO_BASE, true
.assert "CX16 active monster arena stays below VERA I/O hole", CREATURE_END < CX16_IO_BASE, true
.assert "CX16 fixed world stays below VERA I/O hole", CX16_FIXED_WORLD_END < CX16_IO_BASE, true
.assert "CX16 bank window starts after fixed world", CX16_BANKED_RAM_BASE > CX16_FIXED_WORLD_END, true
.assert "CX16 shared banked-data alias matches bank window", BANKED_DATA_BASE, CX16_BANKED_RAM_BASE
.assert "CX16 C128 DB alias maps to bank window", BANK1_DB_BASE, CX16_BANKED_RAM_BASE
.assert "CX16 tier banks do not use default bank", CX16_TIER_BANK_BASE > CX16_RAM_BANK_DEFAULT, true
.assert "CX16 tier bank span is four banks", CX16_TIER_BANK_END - CX16_TIER_BANK_BASE + 1, 4
.assert "CX16 dungeon module bank follows tier banks", CX16_DUNGEON_MODULE_BANK > CX16_TIER_BANK_END, true
.assert "CX16 item catalog banks follow dungeon module", CX16_ITEM_CATALOG_BANK_BASE > CX16_DUNGEON_MODULE_BANK, true
.assert "CX16 item catalog bank span is two banks", CX16_ITEM_CATALOG_BANK_END - CX16_ITEM_CATALOG_BANK_BASE + 1, 2
.assert "CX16 title source bank follows item catalog", CX16_TITLE_SOURCE_BANK > CX16_ITEM_CATALOG_BANK_END, true
.assert "CX16 title source load base is bank-window base", CX16_TITLE_SOURCE_LOAD_BASE, CX16_BANKED_RAM_BASE
.assert "CX16 title source load end is bank-window end", CX16_TITLE_SOURCE_LOAD_END, CX16_BANKED_RAM_END
.assert "CX16 overlay cache class follows title source", CX16_OVERLAY_CACHE_BANK_BASE, CX16_TITLE_SOURCE_BANK + 1
.assert "CX16 overlay cache class span", CX16_OVERLAY_CACHE_BANK_END - CX16_OVERLAY_CACHE_BANK_BASE + 1, 20
.assert "CX16 overlay slot base starts overlay cache class", CX16_OVERLAY_SLOT_BANK_BASE, CX16_OVERLAY_CACHE_BANK_BASE
.assert "CX16 overlay startup slot is first overlay slot", CX16_OVERLAY_STARTUP_BANK, CX16_OVERLAY_SLOT_BANK_BASE
.assert "CX16 overlay town slot follows startup", CX16_OVERLAY_TOWN_BANK, CX16_OVERLAY_STARTUP_BANK + 1
.assert "CX16 overlay death slot follows town", CX16_OVERLAY_DEATH_BANK, CX16_OVERLAY_TOWN_BANK + 1
.assert "CX16 overlay royal slot follows death", CX16_OVERLAY_ROYAL_BANK, CX16_OVERLAY_DEATH_BANK + 1
.assert "CX16 overlay gen slot follows royal", CX16_OVERLAY_GEN_BANK, CX16_OVERLAY_ROYAL_BANK + 1
.assert "CX16 overlay help slot follows gen", CX16_OVERLAY_HELP_BANK, CX16_OVERLAY_GEN_BANK + 1
.assert "CX16 overlay ui slot follows help", CX16_OVERLAY_UI_BANK, CX16_OVERLAY_HELP_BANK + 1
.assert "CX16 overlay items slot follows ui", CX16_OVERLAY_ITEMS_BANK, CX16_OVERLAY_UI_BANK + 1
.assert "CX16 overlay spell slot follows items", CX16_OVERLAY_SPELL_BANK, CX16_OVERLAY_ITEMS_BANK + 1
.assert "CX16 overlay disarm slot follows spell", CX16_OVERLAY_DISARM_BANK, CX16_OVERLAY_SPELL_BANK + 1
.assert "CX16 overlay slot end is disarm slot", CX16_OVERLAY_SLOT_BANK_END, CX16_OVERLAY_DISARM_BANK
.assert "CX16 overlay free class follows named slots", CX16_OVERLAY_FREE_BANK_BASE, CX16_OVERLAY_SLOT_BANK_END + 1
.assert "CX16 overlay free class ends at overlay cache end", CX16_OVERLAY_FREE_BANK_END, CX16_OVERLAY_CACHE_BANK_END
.assert "CX16 current dungeon module is separate from future gen overlay slot", CX16_DUNGEON_MODULE_BANK < CX16_OVERLAY_GEN_BANK, true
.assert "CX16 data cache class follows overlay cache", CX16_DATA_CACHE_BANK_BASE, CX16_OVERLAY_CACHE_BANK_END + 1
.assert "CX16 data cache class span", CX16_DATA_CACHE_BANK_END - CX16_DATA_CACHE_BANK_BASE + 1, 16
.assert "CX16 work bank class follows data cache", CX16_WORK_BANK_BASE, CX16_DATA_CACHE_BANK_END + 1
.assert "CX16 work bank class reaches last bank", CX16_WORK_BANK_END, CX16_RAM_BANK_LAST

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
