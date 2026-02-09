// config.s — System detection (C64 vs C128, column mode)
//
// Detection method: Read $D030 (C128 test register). On a C128 in C64
// mode, $D030 is the VIC-II test register and reads back non-zero when
// written. On a real C64, $D030 is open bus and reads back differently.
// However, the most reliable method is checking the KERNAL revision byte
// at $FF80: C128 KERNAL stores $03 there, C64 stores $AA (rev 3) or
// other values. We use $FF80 since it works regardless of VIC-II state.
//
// C128 column mode: If C128 detected, check if the 80-column (VDC) screen
// is active by reading $D7 (C128: 40/80 column flag, 0=40, $FF=80).
// On C64 this address is unused, but we only check it after confirming C128.

// KERNAL revision byte
.const KERNAL_REV = $ff80
.const C128_REV   = $03

// C128 40/80 column flag (only valid on C128)
.const C128_MODE_FLAG = $d7

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

    // Check KERNAL revision byte
    lda KERNAL_REV
    cmp #C128_REV
    bne !done+          // Not C128, we're done

    // C128 detected
    lda #MACHINE_C128
    sta zp_machine_type

    // Check 40/80 column mode
    lda C128_MODE_FLAG
    beq !done+          // 0 = 40-column mode
    lda #COLUMNS_80
    sta zp_column_mode

!done:
    rts
