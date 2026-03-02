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

.macro AssetLoad() {
    lda #0
    ldx #0
    jsr $ff68                   // SETBNK: data=Bank 0
    jsr $ffd5                   // LOAD
    php
    lda #0
    ldx #0
    jsr $ff68                   // Restore SETBNK: data=Bank 0
    plp
}

.const DEATH_ALIVE   = $00    // Player is alive
.const DEATH_CURSED  = $FD    // Killed by cursed item
.const DEATH_POISON  = $FE    // Killed by poison
.const DEATH_STARVE  = $FF    // Killed by starvation

// ============================================================
// C128 map-safe pointer access wrappers
// ============================================================
// These are the only MMU primitives used by common map macros.
// Contract: mmu_select_bank1/mmu_select_bank0 preserve caller IRQ state.
mmu_safe_map_read_ptr0:
    jsr mmu_select_bank1
    lda (zp_ptr0),y
    pha
    jsr mmu_select_bank0
    pla
    rts

mmu_safe_map_write_ptr0:
    pha
    jsr mmu_select_bank1
    pla
    sta (zp_ptr0),y
    pha
    jsr mmu_select_bank0
    pla
    rts

mmu_safe_map_read_ptr1:
    jsr mmu_select_bank1
    lda (zp_ptr1),y
    pha
    jsr mmu_select_bank0
    pla
    rts

mmu_safe_map_write_ptr1:
    pha
    jsr mmu_select_bank1
    pla
    sta (zp_ptr1),y
    pha
    jsr mmu_select_bank0
    pla
    rts

// Bulk map helpers enter/exit (single bank transition around hot loops)
map_bulk_enter:
    jsr mmu_select_bank1
    rts

map_bulk_exit:
    jsr mmu_select_bank0
    rts
