#importonce
// detect_machine.s — C64 vs C128 and 40/80-column detection, for config.s.
// Separated so the C64 product can place it in the init-only tail past
// program_end (called once at boot in restart_entry).

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
