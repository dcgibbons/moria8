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

// The item-name decode buffer follows msg_history in high RAM ($DF0E-$DF3D,
// allocated in main.s HighResident) to free resident bytes below MAP_BASE.
#define PLATFORM_ITEM_NAME_BUF_LOW
.const PLATFORM_ITEM_NAME_DECODE_BUF_BASE = $df0e

// The pure scratch buffers the C64 parks in page 2 follow it in the same
// high RAM ($DF3E-$DFBA, uninitialized, read and written with PORTB = $FE as
// msg_history is): the element touches (2026-11-11) took Default past
// MAP_BASE.
#define PLATFORM_SCRATCH_BUFS_IN_PAGE2
.const PLATFORM_COMBAT_MSG_BUF_BASE = PLATFORM_ITEM_NAME_DECODE_BUF_BASE + 48
.const PLATFORM_CREATURE_NAME_BUF_BASE = PLATFORM_COMBAT_MSG_BUF_BASE + PLATFORM_COMBAT_MSG_BUF_SIZE
.const PLATFORM_PM_SPELL_LIST_BASE = PLATFORM_CREATURE_NAME_BUF_BASE + 32
.const PLATFORM_LTB_SCRATCH_BASE = PLATFORM_PM_SPELL_LIST_BASE + 9   // monster.s tier-loader counters
.const PLATFORM_PIW_VISIBLE_SLOTS_BASE = PLATFORM_LTB_SCRATCH_BASE + 2
.const PLATFORM_MD_QUEUE_BASE = PLATFORM_PIW_VISIBLE_SLOTS_BASE + 22   // monster_death.s queue
.const PLATFORM_CHEST_SCRATCH_BASE = PLATFORM_MD_QUEUE_BASE + 1 + 3 * 4  // chest_loot.s scratch
// The item flavour shuffles follow (set at a new game and by a load, saved
// through the low sector buffer): the rings of Lordly Protection (2026-11-11).
#define PLATFORM_SHUFFLES_EXTERNAL
.const PLATFORM_SHUFFLE_BASE = PLATFORM_CHEST_SCRATCH_BASE + 5
// The 8-digit number buffer last (2026-11-11, the crowns).
#define PLATFORM_NF_DIGIT_BUF_EXTERNAL
.const PLATFORM_NF_DIGIT_BUF_BASE = PLATFORM_SHUFFLE_BASE + 38
// The console-key latch (input.s; mainline only, never the IRQ or SIO).
.const A8_CONSOL_RELEASED = PLATFORM_NF_DIGIT_BUF_BASE + 8
// The per-type "known" bits (item_defs.s): cleared at a new game, set by a
// load, saved through the low sector buffer as the shuffles are.
#define PLATFORM_ID_KNOWN_EXTERNAL
.const PLATFORM_ID_KNOWN_BASE = A8_CONSOL_RELEASED + 1
.assert "High-RAM scratch buffers stay below $E000", PLATFORM_ID_KNOWN_BASE + 20 <= $e000, true

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
