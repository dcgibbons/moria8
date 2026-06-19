#importonce
// spell_data.s — Full spell/prayer data tables and book masks
//
// User-first hybrid source:
// - spell catalog, names, class spell tables, and book masks follow umoria
// - gameplay behavior prefers VMS where the ports diverge materially

// ============================================================
// Constants
// ============================================================
.const SPELL_CATALOG_COUNT = 31
.const SPELL_MASK_BYTES    = 4
.const BOOK_COUNT          = 8
.const SPELL_LIST_MAX      = 9

.const MAGE_SPELL_COUNT    = SPELL_CATALOG_COUNT
.const PRIEST_SPELL_COUNT  = SPELL_CATALOG_COUNT

// ============================================================
// Bit helpers
// ============================================================
spell_bit_mask:
    .byte $01, $02, $04, $08, $10, $20, $40, $80
spell_bit_inverse:
    .byte $fe, $fd, $fb, $f7, $ef, $df, $bf, $7f

spell_mask_shift:
    .byte 0, 0, 0, 0, 0, 0, 0, 0
    .byte 1, 1, 1, 1, 1, 1, 1, 1
    .byte 2, 2, 2, 2, 2, 2, 2, 2
    .byte 3, 3, 3, 3, 3, 3, 3

spell_mask_index:
    .byte 0, 1, 2, 3, 4, 5, 6, 7
    .byte 0, 1, 2, 3, 4, 5, 6, 7
    .byte 0, 1, 2, 3, 4, 5, 6, 7
    .byte 0, 1, 2, 3, 4, 5, 6

// ============================================================
// Class spell metadata
// ============================================================
class_spell_min_level:
    .byte 0, 1, 1, 5, 3, 1

class_spell_total:
    .byte 0, 31, 31, 12, 30, 31

class_spell_mana_lo:
    .byte 0, <mage_spell_mana, <priest_spell_mana, <rogue_spell_mana, <ranger_spell_mana, <paladin_spell_mana
class_spell_mana_hi:
    .byte 0, >mage_spell_mana, >priest_spell_mana, >rogue_spell_mana, >ranger_spell_mana, >paladin_spell_mana
class_spell_level_lo:
    .byte 0, <mage_spell_level, <priest_spell_level, <rogue_spell_level, <ranger_spell_level, <paladin_spell_level
class_spell_level_hi:
    .byte 0, >mage_spell_level, >priest_spell_level, >rogue_spell_level, >ranger_spell_level, >paladin_spell_level
class_spell_fail_lo:
    .byte 0, <mage_spell_fail, <priest_spell_fail, <rogue_spell_fail, <ranger_spell_fail, <paladin_spell_fail
class_spell_fail_hi:
    .byte 0, >mage_spell_fail, >priest_spell_fail, >rogue_spell_fail, >ranger_spell_fail, >paladin_spell_fail

// ============================================================
// Class spell tables (level, mana, fail)
// Based on umoria/data_player.cpp::magic_spells
// ============================================================
mage_spell_level:
    .byte 1, 1, 1, 1, 3, 3, 3, 3, 5, 5, 5, 5, 7, 7, 7, 9
    .byte 9, 9, 9, 11, 11, 13, 15, 17, 19, 21, 23, 25, 29, 33, 37
mage_spell_mana:
    .byte 1, 1, 2, 2, 3, 3, 3, 4, 4, 5, 5, 5, 6, 6, 6, 7
    .byte 7, 7, 7, 7, 7, 7, 9, 9, 12, 12, 12, 12, 18, 21, 25
mage_spell_fail:
    .byte 22, 23, 24, 26, 25, 25, 27, 30, 30, 30, 30, 35, 35, 50, 40, 44
    .byte 45, 75, 45, 45, 99, 50, 50, 50, 55, 90, 60, 65, 65, 80, 95

priest_spell_level:
    .byte 1, 1, 1, 1, 3, 3, 3, 3, 5, 5, 5, 5, 7, 7, 7, 7
    .byte 9, 9, 9, 11, 11, 11, 13, 13, 15, 15, 17, 21, 25, 33, 39
priest_spell_mana:
    .byte 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 7
    .byte 6, 7, 7, 8, 8, 9, 10, 11, 12, 14, 14, 16, 20, 24, 32
priest_spell_fail:
    .byte 10, 15, 20, 25, 25, 27, 27, 28, 29, 30, 32, 34, 36, 38, 38, 38
    .byte 38, 38, 40, 42, 42, 55, 45, 45, 50, 50, 55, 60, 70, 90, 80

rogue_spell_level:
    .byte 99, 5, 7, 9, 11, 13, 99, 15, 99, 17, 19, 21, 99, 23, 99, 99
    .byte 25, 27, 99, 99, 29, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99
rogue_spell_mana:
    .byte 99, 1, 2, 3, 4, 5, 99, 6, 99, 7, 8, 9, 99, 10, 99, 99
    .byte 12, 15, 99, 99, 18, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99
rogue_spell_fail:
    .byte 0, 50, 55, 60, 65, 70, 0, 75, 0, 80, 85, 90, 0, 95, 0, 0
    .byte 95, 99, 0, 0, 99, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

ranger_spell_level:
    .byte 3, 3, 3, 5, 5, 5, 7, 7, 9, 9, 11, 11, 13, 13, 15, 15
    .byte 17, 17, 21, 21, 23, 23, 25, 25, 27, 29, 31, 33, 35, 37, 99
ranger_spell_mana:
    .byte 1, 2, 2, 3, 3, 4, 5, 6, 7, 8, 8, 9, 10, 11, 12, 13
    .byte 17, 17, 17, 19, 25, 20, 20, 21, 21, 23, 25, 25, 25, 30, 99
ranger_spell_fail:
    .byte 30, 35, 35, 35, 40, 45, 40, 40, 40, 45, 40, 45, 45, 55, 50, 50
    .byte 55, 90, 55, 60, 95, 60, 60, 65, 65, 95, 70, 75, 80, 95, 0

paladin_spell_level:
    .byte 1, 2, 3, 5, 5, 7, 7, 9, 9, 9, 11, 11, 11, 13, 13, 15
    .byte 15, 17, 17, 19, 19, 21, 23, 25, 27, 29, 31, 33, 35, 37, 39
paladin_spell_mana:
    .byte 1, 2, 3, 3, 4, 5, 5, 7, 7, 8, 9, 10, 10, 10, 11, 13
    .byte 15, 15, 15, 15, 15, 17, 17, 20, 21, 22, 24, 28, 32, 36, 38
paladin_spell_fail:
    .byte 30, 35, 35, 35, 35, 40, 40, 40, 40, 40, 40, 45, 45, 45, 45, 45
    .byte 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 60, 60, 70, 90, 90

// ============================================================
// Book metadata
// ============================================================
book_type_ids:
    .byte 47, 55, 56, 57        // Mage books 1-4
    .byte 48, 58, 59, 60        // Priest books 1-4

book_spell_affinity:
    .byte SPELL_MAGE, SPELL_MAGE, SPELL_MAGE, SPELL_MAGE
    .byte SPELL_PRIEST, SPELL_PRIEST, SPELL_PRIEST, SPELL_PRIEST

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
    ldx #BOOK_COUNT - 1
!bfi_loop:
    cmp book_type_ids,x
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
    ldy spell_mask_shift,x
    lda (zp_ptr0),y
    sta zp_temp0
    lda spell_mask_index,x
    tax
    lda spell_bit_mask,x
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
    ldy spell_mask_shift,x
    lda (zp_ptr0),y
    sta zp_temp0
    lda spell_mask_index,x
    tax
    lda spell_bit_mask,x
    ora zp_temp0
    sta (zp_ptr0),y
    rts

// spell_mask_clear_ptr
// Input:  A = spell id (0-30), zp_ptr0 -> 4-byte mask
// Output: selected bit cleared in the pointed mask
// Clobbers: A, X, Y, zp_temp0
spell_mask_clear_ptr:
    tax
    ldy spell_mask_shift,x
    lda (zp_ptr0),y
    sta zp_temp0
    lda spell_mask_index,x
    tax
    lda spell_bit_inverse,x
    and zp_temp0
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
    lda (zp_ptr0),y
    tax
    ldx #7
!smcp_bits:
    lda spell_bit_mask,x
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

// ============================================================
// Compile-time asserts
// ============================================================
.assert "Mage level count", mage_spell_mana - mage_spell_level, SPELL_CATALOG_COUNT
.assert "Mage mana count", mage_spell_fail - mage_spell_mana, SPELL_CATALOG_COUNT
.assert "Mage fail count", priest_spell_level - mage_spell_fail, SPELL_CATALOG_COUNT
.assert "Priest level count", priest_spell_mana - priest_spell_level, SPELL_CATALOG_COUNT
.assert "Priest mana count", priest_spell_fail - priest_spell_mana, SPELL_CATALOG_COUNT
.assert "Priest fail count", rogue_spell_level - priest_spell_fail, SPELL_CATALOG_COUNT
.assert "Rogue level count", rogue_spell_mana - rogue_spell_level, SPELL_CATALOG_COUNT
.assert "Rogue mana count", rogue_spell_fail - rogue_spell_mana, SPELL_CATALOG_COUNT
.assert "Rogue fail count", ranger_spell_level - rogue_spell_fail, SPELL_CATALOG_COUNT
.assert "Ranger level count", ranger_spell_mana - ranger_spell_level, SPELL_CATALOG_COUNT
.assert "Ranger mana count", ranger_spell_fail - ranger_spell_mana, SPELL_CATALOG_COUNT
.assert "Ranger fail count", paladin_spell_level - ranger_spell_fail, SPELL_CATALOG_COUNT
.assert "Paladin level count", paladin_spell_mana - paladin_spell_level, SPELL_CATALOG_COUNT
.assert "Paladin mana count", paladin_spell_fail - paladin_spell_mana, SPELL_CATALOG_COUNT
