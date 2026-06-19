// config.s — Plus/4 configuration

.const KERNAL_REV = $ff80

#import "hal/entropy_consts.s"
#import "hal/lifecycle_policy.s"
#import "hal/storage_title_name.s"

.const PLATFORM_COMBAT_MSG_BUF_SIZE = 42
#define PLATFORM_DISARM_COMMAND_INLINE
#define PLATFORM_GET_INFRA_RANGE_INLINE
#define PLATFORM_COPY_DEATH_SOURCE
#define PLATFORM_REQUIRES_MEDIA_PROBE
.const PLATFORM_RESIDENT_PLAY = "Default"
.const PLATFORM_HD_DECODE_BUF_BASE = $033c
.const PLATFORM_HD_DECODE_BUF_LIMIT = $0400

.const MACHINE_C64  = $00
.const MACHINE_C128 = $80
.const MACHINE_PLUS4 = $40

.const COLUMNS_40 = $00
.const COLUMNS_80 = $80

detect_machine:
    lda #MACHINE_PLUS4
    sta zp_machine_type
    lda #COLUMNS_40
    sta zp_column_mode
    rts

kernal_load:
    jmp $ffd5

.label hal_asset_load = kernal_load

.macro AssetLoad() {
    jsr hal_asset_load
}

hal_asset_load_prg_header:
    jsr plus4_kernal_setnam
    lda #2
    ldx program_device
    ldy #1                  // Use PRG header address
    jsr plus4_kernal_setlfs
    lda #0
    ldx #$00
    ldy #$e0
    jsr plus4_kernal_load
    php
    lda #2
    jsr plus4_kernal_close
    jsr plus4_kernal_clrchn
    plp
    php
    pla
    sta asset_load_save_p
    lda asset_load_save_p
    pha
    plp
    rts

hal_asset_load_title:
    lda #hal_storage_title_name_len
    ldx #<hal_storage_title_name
    ldy #>hal_storage_title_name
    jsr plus4_kernal_setnam
    lda #2
    ldx program_device
    ldy #0                  // Use caller destination at MAP_BASE
    jsr plus4_kernal_setlfs
    lda #0
    ldx #<MAP_BASE
    ldy #>MAP_BASE
    jsr plus4_kernal_load
    php
    lda #2
    jsr plus4_kernal_close
    jsr plus4_kernal_clrchn
    plp
    php
    pla
    sta asset_load_save_p
    lda asset_load_save_p
    pha
    plp
    rts

hal_asset_close_channel:
    :EnterKernal()
    lda #2
    jsr $ffc3               // CLOSE
    jsr $ffcc               // CLRCHN
    :ExitKernal()
    rts

asset_load_save_p: .byte 0

.const DEATH_ALIVE   = $00
.const DEATH_TRAP_PIT      = $F9
.const DEATH_TRAP_ARROW    = $FA
.const DEATH_TRAP_DART     = $FB
.const DEATH_TRAP_ROCKFALL = $FC
.const DEATH_CURSED  = $FD
.const DEATH_POISON  = $FE
.const DEATH_STARVE  = $FF

mmu_safe_map_read_ptr0:
    lda (zp_ptr0),y
    rts

mmu_safe_map_write_ptr0:
    sta (zp_ptr0),y
    rts

mmu_safe_map_read_ptr1:
    lda (zp_ptr1),y
    rts

mmu_safe_map_write_ptr1:
    sta (zp_ptr1),y
    rts

map_bulk_enter:
    rts

map_bulk_exit:
    rts

mmu_safe_db_read_ptr0:
    lda (zp_ptr0),y
    rts

mmu_safe_db_write_ptr0:
    sta (zp_ptr0),y
    rts

mmu_safe_db_read_ptr1:
    lda (zp_ptr1),y
    rts

mmu_safe_db_write_ptr1:
    sta (zp_ptr1),y
    rts

db_bulk_enter:
    rts

db_bulk_exit:
    rts
