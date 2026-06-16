// config.s — System detection (C64 vs C128, column mode)
//
// Detection method: Probe for the C128 VDC (8563) at $D600. The VDC
// status register bit 7 (ready flag) is high most of the time. On a C64
// or C128 in GO64 mode, $D600 is a SID mirror (write-only Voice 1 Freq
// Lo) and reads ~0. This correctly identifies C128 NATIVE mode only —
// C128 in GO64 (C64 mode) is treated as C64, which matches user intent.
//
// Previous $FF80 method was broken: C64 KERNAL rev 3 also has $FF80=$03,
// causing false C128 detection on the most common C64 KERNAL.
//
// C128 column mode: If C128 detected, check $D7 (40/80 column flag).

// KERNAL revision byte (used for revision display + SX-64 detection)
.const KERNAL_REV = $ff80

// C128 40/80 column flag (only valid on C128 native mode)
.const C128_MODE_FLAG = $d7

#import "hal/entropy_consts.s"
#import "hal/lifecycle_policy.s"
#import "hal/storage_title_name.s"

// Machine type constants (stored in zp_machine_type)
.const MACHINE_C64  = $00
.const MACHINE_C128 = $80

// Column mode constants (stored in zp_column_mode)
.const COLUMNS_40 = $00
.const COLUMNS_80 = $80

// detect_machine — Detect C64 vs C128 and column mode
// Output: zp_machine_type = MACHINE_C64 or MACHINE_C128
//         zp_column_mode  = COLUMNS_40 or COLUMNS_80
// Preserves: nothing
detect_machine:
    // Default to C64/40-col
    lda #MACHINE_C64
    sta zp_machine_type
    lda #COLUMNS_40
    sta zp_column_mode

    // Probe for C128 VDC at $D600
    // On C128 native: VDC status register, bit 7 = ready (usually high)
    // On C64 or C128-GO64: SID mirror, reads ~0
    lda #18             // VDC register 18 (Update Address Hi — safe to select)
    sta $d600           // Set VDC register index (harmless SID write on C64)
    nop
    nop
    lda $d600           // Read VDC status (or SID mirror)
    ora $d600
    ora $d600           // OR multiple reads to catch ready flag
    bpl !done+          // Bit 7 clear → no VDC → not C128 native

    // C128 native mode detected
    lda #MACHINE_C128
    sta zp_machine_type

    // Check 40/80 column mode
    lda C128_MODE_FLAG
    beq !done+          // 0 = 40-column mode
    lda #COLUMNS_80
    sta zp_column_mode

!done:
    rts

// kernal_load — Platform LOAD wrapper (C64: direct KERNAL call)
kernal_load:
    jmp $ffd5

.label hal_asset_load = kernal_load

.macro AssetLoad() {
    jsr hal_asset_load
}

hal_asset_load_prg_header:
    php
    jsr $ffbd               // SETNAM
    lda #2
#if C64_UNIT_TEST
    ldx #8
#else
    ldx program_device
#endif
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
    ora #%00000011          // Restore VIC-II bank 0 after serial I/O
    sta $dd00
    plp
    php
    pla
    sta asset_load_save_p
    plp
    lda asset_load_save_p
    pha
    plp
    rts

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
hal_asset_load_title:
    lda #hal_storage_title_name_len
    ldx #<hal_storage_title_name
    ldy #>hal_storage_title_name
    jsr $ffbd               // SETNAM
    lda #2
#if C64_UNIT_TEST
    ldx #8
#else
    ldx program_device
#endif
    ldy #0                  // Use caller destination at MAP_BASE
    jsr $ffba               // SETLFS
    lda #0
    ldx #<MAP_BASE
    ldy #>MAP_BASE
    jsr kernal_load_safe
    php
    lda #2
    jsr $ffc3               // CLOSE
    jsr $ffcc               // CLRCHN
    jsr platform_runtime_resync_c64
    plp
    rts
#else
hal_asset_load_title:
    sec
    rts
#endif

hal_asset_close_channel:
    lda #2
    jsr $ffc3               // CLOSE
    jsr $ffcc               // CLRCHN
    rts

asset_load_save_p: .byte 0

.const DEATH_ALIVE   = $00    // Player is alive
.const DEATH_TRAP_PIT      = $F9    // Killed by an open pit
.const DEATH_TRAP_ARROW    = $FA    // Killed by an arrow trap
.const DEATH_TRAP_DART     = $FB    // Killed by a poison dart
.const DEATH_TRAP_ROCKFALL = $FC    // Killed by falling rock
.const DEATH_CURSED  = $FD    // Killed by cursed item
.const DEATH_POISON  = $FE    // Killed by poison
.const DEATH_STARVE  = $FF    // Killed by starvation

// ============================================================
// C64 map-safe pointer wrappers (no MMU; direct access)
// ============================================================
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

// Bulk map helpers enter/exit (no-op on C64)
map_bulk_enter:
    rts

map_bulk_exit:
    rts

// ============================================================
// C64 DB-safe pointer wrappers (no MMU; direct access)
// ============================================================
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
