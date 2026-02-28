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
// kernal_load — Platform LOAD wrapper (C128: swaps in original IRQ handler)
// Defined in main.s as kernal_load_safe
.label kernal_load = kernal_load_safe

.macro AssetLoad() {
    lda #0
    ldx #0
    jsr safe_setbnk             // SETBNK: data=Bank 0 (via safe wrapper)
    jsr kernal_load_safe        // Load asset
    php
    lda #0
    ldx #0
    jsr safe_setbnk             // Restore SETBNK: data=Bank 0
    plp
}

.const DEATH_ALIVE   = $00    // Player is alive
.const DEATH_CURSED  = $FD    // Killed by cursed item
.const DEATH_POISON  = $FE    // Killed by poison
.const DEATH_STARVE  = $FF    // Killed by starvation
