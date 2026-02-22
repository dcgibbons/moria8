// string_bank_banked.s — String bank decoder (banked at $F000)
//
// Runs in the $F000 banked region with KERNAL ROM banked out ($01=$35).
// Reads compressed string data from bank loaded at $E000 (RAM).
// Decodes using the same Huffman tree as the main game strings.

// ============================================================
// bank_decode_string — Decode string N from bank at $E000
//
// Input:  A = string index (0-based)
// Output: hd_decode_buf filled with null-terminated screen codes
//         zp_ptr0/hi -> hd_decode_buf
// Requires: KERNAL banked out ($01=$35), bank loaded at $E000
// Clobbers: A, X, Y, zp_ptr0/hi
// ============================================================
bank_decode_string:
    asl                         // index * 2 for word offset
    tay                         // Y = index * 2

    // Compute compressed data pointer:
    //   ptr = $E000 + data_offset + string_offset
    //   data_offset at $E001-$E002, string_offset at $E003+Y

    // 16-bit add: data_offset + string_offset
    lda $e003,y                 // string_offset lo
    clc
    adc $e001                   // + data_offset lo
    sta zp_ptr0
    lda $e004,y                 // string_offset hi
    adc $e002                   // + data_offset hi + carry

    // Add $E000 base (only hi byte, lo is $00)
    clc
    adc #$e0
    sta zp_ptr0_hi

    // Decode Huffman bitstream to hd_decode_buf
    jmp huff_decode_from_ptr
