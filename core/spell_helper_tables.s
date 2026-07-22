#importonce
// spell_helper_tables.s — Read-only lookup tables used by spell helpers.

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

book_type_ids:
    .byte 47, 55, 56, 57        // Mage books 1-4
    .byte 48, 58, 59, 60        // Priest books 1-4

book_spell_affinity:
    .byte SPELL_MAGE, SPELL_MAGE, SPELL_MAGE, SPELL_MAGE
    .byte SPELL_PRIEST, SPELL_PRIEST, SPELL_PRIEST, SPELL_PRIEST
