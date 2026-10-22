#importonce
// config.s — Atari 8-bit platform configuration, ZP save/restore, and MMU helpers.

#import "memory.s"
#import "hal/entropy_consts.s"
#import "hal/lifecycle_policy.s"
#import "hal/storage_title_name.s"

.const PLATFORM_COMBAT_MSG_BUF_SIZE = 42
#define PLATFORM_GET_INFRA_RANGE_INLINE
#define PLATFORM_COPY_DEATH_SOURCE
#define PLATFORM_REQUIRES_MEDIA_PROBE
.const PLATFORM_RESIDENT_PLAY = "Default"

// Route help box lines through hal_screen_put_char (ANTIC Mode 2 has no COLOR_RAM).
#define HAL_SCREEN_HELP_LINE_USES_API

// Route msg_history ($DDCE-$DF0D, 320 B) into high RAM under OS ROM.
#define MSG_HISTORY_IN_AUX
.macro MsgHistorySegment() {
    .segment HighResident
}
.macro MsgHistoryRestoreSegment() {
    .segment Default
}

.const MACHINE_C64    = $00
.const MACHINE_C128   = $80
.const MACHINE_PLUS4  = $40
.const MACHINE_ATARI8 = $20

.const COLUMNS_40 = $00
.const COLUMNS_80 = $80

detect_machine:
    lda #MACHINE_ATARI8
    sta zp_machine_type
    lda #COLUMNS_40
    sta zp_column_mode
    rts

// KERNAL enter/exit macros are no-ops because save_stream.s and storage.s
// manage PORTB ($FE <-> $FF) atomically per sector inside EnterSio/ExitSio.
.macro EnterKernal() {
}

.macro ExitKernal() {
}

.macro AssetLoad() {
    jsr hal_asset_load
}

.const DEATH_ALIVE           = $00
.const DEATH_CHEST_NEEDLE    = $f7
.const DEATH_CHEST_EXPLOSION = $f8
.const DEATH_TRAP_PIT        = $f9
.const DEATH_TRAP_ARROW      = $fa
.const DEATH_TRAP_DART       = $fb
.const DEATH_TRAP_ROCKFALL   = $fc
.const DEATH_CURSED          = $fd
.const DEATH_POISON          = $fe
.const DEATH_STARVE          = $ff

// ============================================================
// Zero-Page Save / Restore ($02-$8F <-> zp_save_buf at $DD40-$DDCD)
// ============================================================
// MUST be called only while PORTB = $FE (RAM visible at $D800-$FFFF).
save_zp:
    ldx #$8e
!loop:
    lda zp_temp0 - 1,x
    sta zp_save_buf - 1,x
    dex
    bne !loop-
    rts

restore_zp:
    ldx #$8e
!loop:
    lda zp_save_buf - 1,x
    sta zp_temp0 - 1,x
    dex
    bne !loop-
    rts

// ============================================================
// Safe Pointer Access Helpers (Shared Core Compatibility)
// ============================================================
mmu_safe_map_read_ptr0:
mmu_safe_db_read_ptr0:
mmu_safe_read_ptr0:
    lda (zp_ptr0),y
    rts

mmu_safe_map_write_ptr0:
mmu_safe_db_write_ptr0:
mmu_safe_write_ptr0:
    sta (zp_ptr0),y
    rts

mmu_safe_map_read_ptr1:
mmu_safe_db_read_ptr1:
mmu_safe_read_ptr1:
    lda (zp_ptr1),y
    rts

mmu_safe_map_write_ptr1:
mmu_safe_db_write_ptr1:
mmu_safe_write_ptr1:
    sta (zp_ptr1),y
    rts

db_bulk_enter:
db_bulk_exit:
    rts

// ============================================================
// Lifecycle HAL Entry Points
// ============================================================
hal_platform_character_sheet_begin:
    rts
