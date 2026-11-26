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
    .byte ITEM_SLOT_SPELLBOOK_BEGINNERS_MAGICK
    .byte ITEM_SLOT_SPELLBOOK_MAGICK_I
    .byte ITEM_SLOT_SPELLBOOK_MAGICK_II
    .byte ITEM_SLOT_SPELLBOOK_THE_MAGES_GUIDE_TO_POWER
    .byte ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_BEGINNERS_HANDBOOK
    .byte ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_WORDS_OF_WISDOM
    .byte ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_CHANTS_AND_BLESSINGS
    .byte ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_EXORCISM

book_spell_affinity:
    .byte SPELL_MAGE, SPELL_MAGE, SPELL_MAGE, SPELL_MAGE
    .byte SPELL_PRIEST, SPELL_PRIEST, SPELL_PRIEST, SPELL_PRIEST
