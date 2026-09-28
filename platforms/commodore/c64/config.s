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

.const PLATFORM_COMBAT_MSG_BUF_SIZE = 42
#define PLATFORM_GET_INFRA_RANGE_INLINE
#define PLATFORM_COPY_DEATH_SOURCE
#if C64_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_REQUIRES_MEDIA_PROBE
#endif
.const PLATFORM_RESIDENT_PLAY = "Default"
.const PLATFORM_HD_DECODE_BUF_BASE = $033c
.const PLATFORM_HD_DECODE_BUF_LIMIT = $0400

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

// krill_active — $ff while drive code is installed, $00 on KERNAL fallback.
// Standard-DOS transactions suspend from the overlay that remains resident
// for the operation; title context may reinstall with the compact installer.
// Lives next to the boot handoff magic in the always-RAM $0334-$033B gap
// (below the cassette-buffer / door-scan window, which starts at $033C —
// memory.s DUNGEON_GEN_DOOR_SCAN_BASE; literal here so unit tests that import
// config.s without memory.s still assemble).
.label krill_active = $0336
// krill_boot_used — nonzero when init_load_banked loaded the $F000 payload
// through the Krill boot resident (fastload smoke evidence byte).
.label krill_boot_used = $0337
.label krill_suspended = $0338
.label krill_drive_1541 = $0339
.label krill_boot_art_used = $033a
.label krill_boot_device = $033b
.assert "krill state bytes stay below the cassette-buffer window", krill_boot_device < $033c, true
.assert "boot device handoff follows art evidence", krill_boot_device, krill_boot_art_used + 1

// Krill's Loader entry constants. The boot-time resident is loaded to $0400
// by boot.s (screen RAM — but it is only ever used by the chain stub, before
// the game takes over the display); the runtime
// resident rides inside 64.bank at $F000 (see main.s RuntimeBanked segment).
.const KRILL_BOOT_LOADRAW    = $0400
.const KRILL_BOOT_UNINSTALL  = $0400 + 225
// Runtime resident adds the bounded save-loader API to the original build.
.const KRILL_RUNTIME_LOADRAW    = $F000
.const KRILL_RUNTIME_LOADRAW_BOUNDED = $F004
.const KRILL_RUNTIME_UNINSTALL  = $F000 + 369
// krill_load_file wrapper, pinned immediately after the resident in the
// RuntimeBanked segment (main.s asserts the label lands here). Kept as an
// address constant so unit tests that import config.s without main.s link.
.const KRILL_LOAD_FILE          = $F000 + 382
.const KRILL_LOAD_FILE_BOUNDED  = KRILL_LOAD_FILE + 6
.const KRILL_ZP_LOADADDR_LO     = $e0
.const KRILL_ZP_LOADADDR_HI     = $e1
.const KRILL_ZP_BOUNDEND_LO     = $e4
.const KRILL_ZP_BOUNDEND_HI     = $e5

// Krill's Loader entry constants (resident assembled at $F000, see main.s
// RuntimeBanked segment). Status codes returned in A by loadraw.
.const KRILL_STATUS_OK                 = $00
.const KRILL_STATUS_LOAD_ADDRESS_MISMATCH = $f6
.const KRILL_STATUS_FILE_TOO_SMALL     = $f8
.const KRILL_STATUS_FILE_TOO_LARGE     = $f9
.const KRILL_STATUS_DEVICE_INCOMPATIBLE = $fb
.const KRILL_STATUS_TOO_MANY_DEVICES   = $fc
.const KRILL_STATUS_GENERIC_KERNAL_ERROR = $fd
.const KRILL_STATUS_DEVICE_NOT_PRESENT = $fe
.const KRILL_STATUS_FILE_NOT_FOUND     = $ff

hal_asset_load_prg_header:
#if !C64_UNIT_TEST
    bit krill_active
    bmi hal_asset_krill_call
#endif
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
    lda #%00000011          // Restore VIC-II bank 0, IEC lines released,
    sta $dd00               // upper 6 bits 0 (Krill $DD00 contract)
    pla                     // A = result flags
    tax
    plp                     // restore caller flags
    txa
    pha
    plp                     // restore result flags (carry)
    rts

// Krill path shared by all asset loads. Caller may be in any banking/IRQ
// state; the Krill resident lives under KERNAL at $F000, so bank to all-RAM
// for the call. IRQs are not masked: the RAM wedge vectors RTI them, and the
// Krill 2-bit+ATN protocol is fully asynchronous. Result carry is preserved
// across the bank restore.
// Input:  X/Y = 0-terminated PETSCII filename.
// Output: carry clear = success, carry set = error (same contract as KERNAL path).
hal_asset_krill_call:
    lda $01
    pha
    lda #$35                // I/O + RAM under KERNAL visible
    sta $01
    jsr KRILL_LOAD_FILE
    php                     // push result flags
    tay                     // preserve Krill status while restoring banking
    pla
    tax                     // X = result flags (pla/tax keep carry in P1 byte)
    pla
    sta $01                 // restore caller banking
    txa
    pha
    plp                     // restore result flags (carry)
    tya
    rts

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
hal_asset_load_title:
    lda #hal_storage_title_name_len
    ldx #<hal_storage_title_name
    ldy #>hal_storage_title_name
    jsr hal_asset_load_prg_header
    php
    jsr platform_runtime_resync_c64
    plp
    rts
#else
hal_asset_load_title:
    sec
    rts
#endif

hal_asset_close_channel:
    bit krill_active
    bpl !open+              // Krill owns the drive; no KERNAL file table to clean
    rts
!open:
    lda #2
    jsr $ffc3               // CLOSE
    jsr $ffcc               // CLRCHN
    rts

.const DEATH_ALIVE   = $00    // Player is alive
.const DEATH_CHEST_NEEDLE = $F7
.const DEATH_CHEST_EXPLOSION = $F8
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
