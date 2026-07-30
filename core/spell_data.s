#importonce
// spell_data.s — Full spell/prayer data tables and book masks
//
// User-first hybrid source:
// - spell catalog, names, class spell tables, and book masks follow umoria
// - gameplay behavior prefers VMS where the ports diverge materially

#import "spell_data_defs.s"

#if !SPELL_HELPER_TABLES_EXTERNAL
#import "spell_helper_tables.s"
#endif

#if !SPELL_CLASS_DATA_EXTERNAL
#import "spell_class_data.s"
#endif

// ============================================================
// Book metadata
// ============================================================
book_mask_lo:
    .byte <book_mask_0, <book_mask_1, <book_mask_2, <book_mask_3
    .byte <book_mask_4, <book_mask_5, <book_mask_6, <book_mask_7
book_mask_hi:
    .byte >book_mask_0, >book_mask_1, >book_mask_2, >book_mask_3
    .byte >book_mask_4, >book_mask_5, >book_mask_6, >book_mask_7

book_mask_0: .byte $7f, $00, $00, $00   // [Beginners-Magick]
book_mask_1: .byte $80, $ff, $00, $00   // [Magick I]
book_mask_2: .byte $00, $00, $ff, $00   // [Magick II]
book_mask_3: .byte $00, $00, $00, $7f   // [The Mages' Guide to Power]
book_mask_4: .byte $ff, $00, $00, $00   // [Beginners Handbook]
book_mask_5: .byte $00, $ff, $00, $00   // [Words of Wisdom]
book_mask_6: .byte $00, $00, $ff, $01   // [Chants and Blessings]
book_mask_7: .byte $00, $00, $00, $7e   // [Exorcisms and Dispellings]

// ============================================================
// Helpers
// ============================================================
// book_find_index
// Input:  A = item type id
// Output: C clear = found, X = book index (0..7)
//         C set = not a spell/prayer book
book_find_index:
#if APPLE2
    sta zp_temp0
#endif
    ldx #BOOK_COUNT - 1
!bfi_loop:
#if APPLE2
    :AuxReadX(book_type_ids)
    cmp zp_temp0
#else
    cmp book_type_ids,x
#endif
    beq !bfi_found+
    dex
    bpl !bfi_loop-
    sec
    rts
!bfi_found:
    clc
    rts

// spell_mask_test_ptr
// Input:  A = spell id (0-30), zp_ptr0 -> 4-byte mask
// Output: carry set if bit is set, carry clear otherwise
// Preserves: X
// Clobbers: A, Y, zp_temp0, zp_temp1
spell_mask_test_ptr:
    stx zp_temp1
    tax
#if APPLE2
    :AuxReadX(spell_mask_shift)
    tay
#else
    ldy spell_mask_shift,x
#endif
    lda (zp_ptr0),y
    sta zp_temp0
    :AuxReadX(spell_mask_index)
    tax
    :AuxReadX(spell_bit_mask)
    and zp_temp0
    beq !smtp_clear+
    sec
    ldx zp_temp1
    rts
!smtp_clear:
    clc
    ldx zp_temp1
    rts

// spell_mask_set_ptr
// Input:  A = spell id (0-30), zp_ptr0 -> 4-byte mask
// Output: selected bit set in the pointed mask
// Clobbers: A, X, Y, zp_temp0
spell_mask_set_ptr:
    tax
#if APPLE2
    :AuxReadX(spell_mask_shift)
    sta zp_temp1
    tay
#else
    ldy spell_mask_shift,x
#endif
    lda (zp_ptr0),y
    sta zp_temp0
    :AuxReadX(spell_mask_index)
    tax
    :AuxReadX(spell_bit_mask)
    ora zp_temp0
#if APPLE2
    ldy zp_temp1
#endif
    sta (zp_ptr0),y
    rts

// spell_mask_clear_ptr
// Input:  A = spell id (0-30), zp_ptr0 -> 4-byte mask
// Output: selected bit cleared in the pointed mask
// Clobbers: A, X, Y, zp_temp0
spell_mask_clear_ptr:
    tax
#if APPLE2
    :AuxReadX(spell_mask_shift)
    sta zp_temp1
    tay
#else
    ldy spell_mask_shift,x
#endif
    lda (zp_ptr0),y
    sta zp_temp0
    :AuxReadX(spell_mask_index)
    tax
    :AuxReadX(spell_bit_inverse)
    and zp_temp0
#if APPLE2
    ldy zp_temp1
#endif
    sta (zp_ptr0),y
    rts

// spell_mask_count_ptr
// Input:  zp_ptr0 -> 4-byte mask
// Output: A = popcount across all four bytes
// Clobbers: A, X, Y, zp_temp0
spell_mask_count_ptr:
    lda #0
    sta zp_temp0
    ldy #0
!smcp_byte:
#if APPLE2
    sty zp_temp1
#else
    lda (zp_ptr0),y
    tax
#endif
    ldx #7
!smcp_bits:
    :AuxReadX(spell_bit_mask)
#if APPLE2
    ldy zp_temp1
#endif
    and (zp_ptr0),y
    beq !smcp_skip+
    inc zp_temp0
!smcp_skip:
    dex
    bpl !smcp_bits-
    iny
    cpy #SPELL_MASK_BYTES
    bcc !smcp_byte-
    lda zp_temp0
    rts
