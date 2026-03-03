// string_bank.s — String bank loader (R7.5)
//
// Loads Huffman-compressed string bank PRG files from disk to $E000.
// Bank files are created by tools/string_bank_encoder.py and share
// the same Huffman tree as the main game strings.
//
// Banks use the $E000 overlay region — loading a bank invalidates
// any overlay or tier data at $E000 (and vice versa).
//
// Bank PRG format (at $E000 after loading):
//   $E000:       string count (1 byte)
//   $E001-$E002: data offset from $E000 (16-bit LE)
//   $E003+:      index table (count x 2 bytes, LE offsets from data start)
//   data start:  Huffman-compressed bitstreams (null-terminated)

#importonce

// ============================================================
// Bank filename (PETSCII for KERNAL — NOT screen codes)
// ============================================================
bank_fn_recall:
    .byte $42,$4e,$4b,$2e,$52,$43,$4c  // "BNK.RCL"
.const BANK_FN_RECALL_LEN = * - bank_fn_recall

// ============================================================
// bank_load_recall — Load recall string bank to $E000
// Uses KERNAL LOAD (KERNAL must be banked in, $01=$36).
// Invalidates any overlay or tier data at $E000.
// Output: carry clear = success, carry set = error
// Clobbers: A, X, Y
// ============================================================
bank_load_recall:
    :EnterKernal()
    // Invalidate overlay and tier state/metadata before loading into $E000.
    lda #OVL_NONE
    sta current_overlay
    jsr tier_invalidate_state

    lda #BANK_FN_RECALL_LEN
    ldx #<bank_fn_recall
    ldy #>bank_fn_recall
    jsr $ffbd               // KERNAL SETNAM

    lda #2                  // Logical file number
    ldx #8                  // Device 8
    ldy #1                  // Secondary 1 = load to PRG header address ($E000)
    jsr $ffba               // KERNAL SETLFS

    lda #0                  // 0 = LOAD
    ldx #$00
    ldy #$e0
    jsr kernal_load         // Platform LOAD (C128: safe IRQ swap)
    // Carry clear = success, carry set = error
    php                     // Save carry (load result)
    lda #2
    jsr $ffc3               // KERNAL CLOSE
    jsr $ffcc               // KERNAL CLRCHN

    lda zp_machine_type
    cmp #MACHINE_C128
    beq !bl_done+

    // C64: restore VIC-II bank 0 after serial I/O.
    lda $dd00
    ora #%00000011
    sta $dd00
!bl_done:
    plp                     // Restore carry
    :ExitKernal()
    rts
