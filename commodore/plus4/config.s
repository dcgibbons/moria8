// config.s — Plus/4 configuration

.const KERNAL_REV = $ff80

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
    :EnterKernal()
    jsr $ffbd               // SETNAM
    lda #2
    ldx #8
    ldy #1                  // Use PRG header address
    jsr $ffba               // SETLFS
    lda #0
    ldx #$00
    ldy #$e0
    jsr hal_asset_load
    php
    lda #2
    jsr $ffc3               // CLOSE
    jsr $ffcc               // CLRCHN
    lda $dd00
    ora #%00000011
    sta $dd00
    plp
    php
    pla
    sta asset_load_save_p
    :ExitKernal()
    lda asset_load_save_p
    pha
    plp
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
