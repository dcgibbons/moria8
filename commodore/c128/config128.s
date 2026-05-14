#importonce
// config128.s — C128 configuration (hardcoded for MORIA128.PRG)
//
// No runtime detection needed — if this binary is running, we're C128 80-col.
// The bootloader or user already selected MORIA128 explicitly.

// Machine type constants (stored in zp_machine_type)
.const MACHINE_C64  = $00
.const MACHINE_C128 = $80

// Column mode constants (stored in zp_column_mode)
.const COLUMNS_40 = $00
.const COLUMNS_80 = $80

// detect_machine — Set C128/80-col flags (hardcoded)
// Output: zp_machine_type = MACHINE_C128
//         zp_column_mode  = COLUMNS_80
detect_machine:
    lda #MACHINE_C128
    sta zp_machine_type
    lda #COLUMNS_80
    sta zp_column_mode
    rts

// ============================================================
// Death source constants (used by turn.s, player_items.s, score.s)
// ============================================================
// KERNAL revision byte address (same location as C64, different value)
.const KERNAL_REV = $ff80

// ============================================================
// Death source constants (used by turn.s, player_items.s, score.s)
// ============================================================
// kernal_load — Platform LOAD entry (expects EnterKernal() context)
.label kernal_load = $ffd5
.label hal_asset_load = kernal_load
#if C128_PRODUCT_OVERLAY_RUNTIME
.label hal_asset_load_prg_header = c128_preload_asset_load
.label hal_asset_load_title = c128_title_asset_load
#else
hal_asset_load_prg_header:
    sec
    rts
hal_asset_load_title:
    sec
    rts
#endif

.macro AssetLoad() {
    jsr hal_asset_load          // LOAD (via patched KERNAL jump table)
}

.const DEATH_ALIVE   = $00    // Player is alive
.const DEATH_TRAP_PIT      = $F9    // Killed by an open pit
.const DEATH_TRAP_ARROW    = $FA    // Killed by an arrow trap
.const DEATH_TRAP_DART     = $FB    // Killed by a poison dart
.const DEATH_TRAP_ROCKFALL = $FC    // Killed by falling rock
.const DEATH_CURSED  = $FD    // Killed by cursed item
.const DEATH_POISON  = $FE    // Killed by poison
.const DEATH_STARVE  = $FF    // Killed by starvation

// ============================================================
// C128 map-safe pointer access wrappers
// ============================================================
// These are the only MMU primitives used by common map macros.
// Contract: these trampolines land in common-RAM helper code copied to $0C00.
mmu_safe_map_read_ptr0:
    jmp mmu_common_map_read_ptr0

mmu_safe_map_write_ptr0:
    jmp mmu_common_map_write_ptr0

mmu_safe_map_read_ptr1:
    jmp mmu_common_map_read_ptr1

mmu_safe_map_write_ptr1:
    jmp mmu_common_map_write_ptr1

mmu_safe_mark_visited_row_ptr0:
    jmp mmu_common_mark_visited_row_ptr0

// Bulk map helpers enter/exit (single bank transition around hot loops)
map_bulk_enter:
    jsr mmu_select_bank1
    rts

map_bulk_exit:
    jsr mmu_select_bank0
    rts

// ============================================================
// C128 banked-database access helpers (Phase 10.2.1)
// ============================================================
// Contract:
// - These helpers are C128-only and centralize Bank 1 data reads/writes
//   for future creature/item database relocation.
// - All helpers preserve caller IRQ state via mmu_select_bank1/bank0.
// - Pointer access uses zp_ptr0/zp_ptr1 + Y offset for parity with map APIs.

mmu_safe_db_read_ptr0:
    jmp mmu_common_db_read_ptr0

mmu_safe_db_write_ptr0:
    jmp mmu_common_db_write_ptr0

mmu_safe_db_read_ptr1:
    jmp mmu_common_db_read_ptr1

mmu_safe_db_write_ptr1:
    jmp mmu_common_db_write_ptr1

// db_bulk_enter/db_bulk_exit:
// Optional fast-path wrappers for future bulk DB scans/copies.
db_bulk_enter:
    jsr mmu_select_bank1
    rts

db_bulk_exit:
    jsr mmu_select_bank0
    rts
