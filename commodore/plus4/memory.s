// memory.s — Plus/4 memory map and ROM/RAM switching
//
// Plus/4/264 ROM visibility is controlled by shadow registers:
//   $FF3E write: ROM visible
//   $FF3F write: RAM visible under ROM
//
// Unlike C64 $01 banking, this is all-or-nothing for the enabled ROM ranges
// except the always-visible $FC00-$FCFF banking helper page and I/O page.

#import "hal/memory_bank_consts.s"
#import "hal/entropy_consts.s"
#import "../common/bank_port_consts.s"

// Memory region bases
.const MAP_BASE         = $c800
.const MAP_END          = $d6ff
.const FLOOR_ITEM_BASE  = $d700
.const FLOOR_ITEM_END   = $d7ff
.const CREATURE_BASE    = $c820
.const CREATURE_END     = $c8ff
.const PLATFORM_TIER_NAME_POOL_BASE = $d800
.const PLATFORM_TIER_NAME_POOL_END  = $dfff
.const BANKED_DATA_BASE = $e000
.const BANKED_DATA_END  = $ffff
.const BANK1_DB_BASE    = $e000
.const SCREEN_RAM       = $0c00
.const COLOR_RAM        = $0800
.const DUNGEON_GEN_BFS_QUEUE_BASE = $0400
.const DUNGEON_GEN_BFS_QUEUE_MAX  = 512
.const DUNGEON_GEN_BFS_QUEUE_END  = DUNGEON_GEN_BFS_QUEUE_BASE + (DUNGEON_GEN_BFS_QUEUE_MAX * 2) - 1
.const DUNGEON_GEN_DOOR_SCAN_BASE = $033c
.const DUNGEON_GEN_DOOR_SCAN_LIMIT = $0400

.const PLUS4_ROM_ENABLE = $ff3e
.const PLUS4_RAM_ENABLE = $ff3f
.const ZP_SAVE_SIZE     = 142

.const TED_SND1_LO      = $ff0e
.const TED_SND2_LO      = $ff0f
.const TED_SND2_HI      = $ff10
.const TED_IRQ_STATUS   = $ff09
.const TED_IRQ_ENABLE   = $ff0a
.const TED_BMP_SOUND    = $ff12
.const TED_CHARPTR      = $ff13
.const TED_SCREEN_ADDR  = $ff14
.const TED_SCREEN_DEFAULT = $0f
.const TED_CHARSET_LOWER_UPPER = $d4

.macro Plus4RamVisible() {
    sta PLUS4_RAM_ENABLE
}

.macro Plus4RomVisible() {
    sta PLUS4_ROM_ENABLE
}

.macro BankOutBasic() {
    sta PLUS4_RAM_ENABLE
}

.macro BankInBasic() {
    sta PLUS4_ROM_ENABLE
}

.macro BankOutKernal() {
    sta PLUS4_RAM_ENABLE
}

.macro BankInKernal() {
    sta PLUS4_ROM_ENABLE
}

.macro BankOutAll() {
    sta PLUS4_RAM_ENABLE
}

.macro BankRestoreDefault() {
    sta PLUS4_ROM_ENABLE
}

.macro MachineRestoreDefault() {
    sta PLUS4_ROM_ENABLE
}

.macro MachineRestoreAllRam() {
    sta PLUS4_RAM_ENABLE
}

.macro EnterKernal() {
    php
    sei
    sta PLUS4_ROM_ENABLE
}

.macro ExitKernal() {
    sta PLUS4_RAM_ENABLE
    plp
}

plus4_bank_ram:
    sta PLUS4_RAM_ENABLE
    rts

plus4_bank_rom:
    sta PLUS4_ROM_ENABLE
    rts

zp_save_buf: .fill ZP_SAVE_SIZE, 0

save_zp:
    ldx #0
!loop:
    lda zp_temp0,x
    sta zp_save_buf,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    rts

restore_zp:
    ldx #0
!loop:
    lda zp_save_buf,x
    sta zp_temp0,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    rts

read_banked_byte_a000:
    sta PLUS4_RAM_ENABLE
    lda (zp_ptr0),y
    pha
    sta PLUS4_ROM_ENABLE
    pla
    rts

read_banked_byte_e000:
    sei
    sta PLUS4_RAM_ENABLE
    lda (zp_ptr0),y
    pha
    sta PLUS4_ROM_ENABLE
    pla
    rts

copy_to_e000:
    ldy #0
    ldx zp_temp1
    beq !partial+
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
    ldx zp_temp0
    beq !done+
!tail:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    dex
    bne !tail-
!done:
    rts

mmu_select_bank1:
    rts

mmu_select_bank0:
    rts

.assert "Map fits in $C000 region", MAP_END - MAP_BASE + 1, 3840
.assert "Floor items fit", FLOOR_ITEM_END - FLOOR_ITEM_BASE + 1, 256
.assert "Dungeon-gen BFS queue remains page-aligned", <DUNGEON_GEN_BFS_QUEUE_BASE, 0
.assert "Dungeon-gen BFS queue stays in low scratch window", DUNGEON_GEN_BFS_QUEUE_END <= $07ff, true
.assert "Dungeon-gen door scan stays in cassette buffer", DUNGEON_GEN_DOOR_SCAN_BASE >= $033c && DUNGEON_GEN_DOOR_SCAN_BASE + 65 <= $0400, true
.assert "ZP save buffer doesn't overlap CREATURE_BASE", zp_save_buf + ZP_SAVE_SIZE <= CREATURE_BASE, true
.assert "ZP save buffer size", ZP_SAVE_SIZE, 142
