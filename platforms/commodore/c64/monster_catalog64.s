#importonce
// monster_catalog64.s — C64 monster catalog placement
// (docs/MONSTER_CATALOG_DESIGN.md, core/6502/monster_catalog.s,
// common/catalog_fetch.s; memory.s owns the hidden spans).
//
// The name pool, the level index and the record-sector table are hidden RAM
// under I/O ($D000-$D7FF): the picker and the fetch reach them with every
// ROM and I/O banked out and interrupts off, the KERNAL back for the drive.
// Records come from the REU when one is present (catalog_reu_preload stashed
// them at boot), else from the drive. The optional C64_CARTRIDGE build
// imports cartridge_catalog.s instead: ROM records, the same hidden RAM owners.

// Win-creature placement (generation, from DL50) and the turn's wanderer
// (catalog_place_far) live in the $F000 runtime: the resident image has no
// room for them.
#if !HAL_PLATFORM_CATALOG_WIN_TRAMPOLINE   // hal/lifecycle_policy.s defines it first
#define HAL_PLATFORM_CATALOG_WIN_TRAMPOLINE
#endif
.macro CatalogWinBegin() {
    .segment RuntimeBanked
}
.macro CatalogWinEnd() {
    .segment Default
}
.macro CatalogMap() {
    jsr c64_catalog_map
}
.macro CatalogUnmap() {
    jsr c64_catalog_unmap
}
.macro CatalogPoolWrite() {
    sta (zp_ptr1),y
}
.macro CatalogKernalIn() {
    lda hal_memory_cpu_port
    sta c64_catalog_drive_port
    lda #BANK_NO_BASIC
    sta hal_memory_cpu_port
}
.macro CatalogKernalOut() {
    lda c64_catalog_drive_port
    sta hal_memory_cpu_port
}

// tramp_catalog_place_win / tramp_catalog_place_wanderer — The $F000
// runtime with the ROMs out, as the special-room trampolines run it
// (interrupts masked; caller's banking back). C picks the creature
// (catalog_place_far) and survives the banking.
tramp_catalog_place_win:
    sec
    .byte $24                   // BIT zp: skip the clc
tramp_catalog_place_wanderer:
    clc
    php
    sei
    lda hal_memory_cpu_port
    pha
    lda #BANK_NO_ROMS
    sta hal_memory_cpu_port     // php, sei, lda, pha and sta keep C
    jsr catalog_place_far
    pla
    sta hal_memory_cpu_port
    plp
    rts

c64_catalog_saved_port: .byte 0
c64_catalog_saved_p:    .byte 0
c64_catalog_drive_port: .byte 0

// c64_catalog_map — All RAM (interrupts masked): the hidden spans visible.
// Clobbers: A
c64_catalog_map:
    php
    pla
    sta c64_catalog_saved_p
    sei
    lda hal_memory_cpu_port
    sta c64_catalog_saved_port
    lda #BANK_ALL_RAM
    sta hal_memory_cpu_port
    rts

// c64_catalog_unmap — The banking and interrupt state the map saved.
// Clobbers: A
c64_catalog_unmap:
    lda c64_catalog_saved_port
    sta hal_memory_cpu_port
    lda c64_catalog_saved_p
    pha
    plp
    rts

#if C64_CARTRIDGE
#import "cartridge_catalog.s"
#else
#import "../common/catalog_fetch.s"
#endif
