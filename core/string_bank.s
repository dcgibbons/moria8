#importonce
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
// Uses the platform asset-loader HAL PRG-header transaction.
// Invalidates any overlay or tier data at $E000.
// Output: carry clear = success, carry set = error
// Clobbers: A, X, Y
// ============================================================
bank_load_recall:
    // Invalidate overlay before loading into $E000.
    // 40-column ports use the $E000 tier window; C128 tier metadata points to Bank 1 DB.
    lda #OVL_NONE
    sta current_overlay
#if HAL_PLATFORM_STRING_BANK_LOAD_INVALIDATES_TIER
    jsr tier_invalidate_state
#endif

    lda #BANK_FN_RECALL_LEN
    ldx #<bank_fn_recall
    ldy #>bank_fn_recall
    jmp hal_asset_load_prg_header
