// spell_data.s — Spell and prayer data tables
//
// Phase 7.1: 16 mage spells + 16 priest prayers.
// Struct-of-arrays layout matching item.s pattern.
// Data only — no gameplay code.

// ============================================================
// Constants
// ============================================================
.const MAGE_SPELL_COUNT   = 16
.const PRIEST_SPELL_COUNT = 16

// ============================================================
// Mage Spell Tables (16 entries each)
// ============================================================

// Mana cost
mage_spell_mana:
    .byte 1, 1, 2, 2, 3, 3, 3, 4, 5, 5, 6, 6, 7, 8, 10, 12

// Minimum caster level
mage_spell_level:
    .byte 1, 1, 1, 1, 3, 3, 5, 5, 7, 7, 9, 9, 11, 13, 15, 17

// Base failure rate (percent)
mage_spell_fail:
    .byte 22, 23, 24, 26, 25, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 50

// ============================================================
// Priest Prayer Tables (16 entries each)
// ============================================================

// Mana cost
priest_spell_mana:
    .byte 1, 1, 2, 2, 2, 3, 3, 4, 5, 5, 6, 6, 7, 8, 10, 12

// Minimum caster level
priest_spell_level:
    .byte 1, 1, 1, 3, 3, 5, 5, 7, 7, 9, 9, 11, 11, 13, 15, 17

// Base failure rate (percent)
priest_spell_fail:
    .byte 10, 15, 20, 24, 25, 27, 30, 32, 36, 38, 38, 42, 44, 46, 48, 52

// ============================================================
// Mage Spell Name Pointers
// ============================================================
mage_spell_name_lo:
    .byte <msn_0,  <msn_1,  <msn_2,  <msn_3
    .byte <msn_4,  <msn_5,  <msn_6,  <msn_7
    .byte <msn_8,  <msn_9,  <msn_10, <msn_11
    .byte <msn_12, <msn_13, <msn_14, <msn_15
mage_spell_name_hi:
    .byte >msn_0,  >msn_1,  >msn_2,  >msn_3
    .byte >msn_4,  >msn_5,  >msn_6,  >msn_7
    .byte >msn_8,  >msn_9,  >msn_10, >msn_11
    .byte >msn_12, >msn_13, >msn_14, >msn_15

// ============================================================
// Priest Prayer Name Pointers
// ============================================================
priest_spell_name_lo:
    .byte <psn_0,  <psn_1,  <psn_2,  <psn_3
    .byte <psn_4,  <psn_5,  <psn_6,  <psn_7
    .byte <psn_8,  <psn_9,  <psn_10, <psn_11
    .byte <psn_12, <psn_13, <psn_14, <psn_15
priest_spell_name_hi:
    .byte >psn_0,  >psn_1,  >psn_2,  >psn_3
    .byte >psn_4,  >psn_5,  >psn_6,  >psn_7
    .byte >psn_8,  >psn_9,  >psn_10, >psn_11
    .byte >psn_12, >psn_13, >psn_14, >psn_15

// ============================================================
// Mage Spell Name Strings (screen codes, null-terminated)
// ============================================================
msn_0:  .text "MAGIC MISSILE" ; .byte 0
.label msn_1 = itn_30   // "DETECT MONSTERS" — shared with item.s
msn_2:  .text "PHASE DOOR" ; .byte 0
msn_3:  .text "LIGHT AREA" ; .byte 0
.label msn_4 = itn_17   // "CURE LIGHT WOUNDS" — shared with item.s
msn_5:  .text "FIND TRAPS/DOORS" ; .byte 0
msn_6:  .text "STINKING CLOUD" ; .byte 0
msn_7:  .text "CONFUSION" ; .byte 0
msn_8:  .text "LIGHTNING BOLT" ; .byte 0
msn_9:  .text "TRAP/DOOR DESTROY" ; .byte 0
msn_10: .text "SLEEP I" ; .byte 0
msn_11: .text "CURE POISON" ; .byte 0
msn_12: .text "TELEPORT SELF" ; .byte 0
msn_13: .text "FROST BOLT" ; .byte 0
msn_14: .text "WALL TO MUD" ; .byte 0
msn_15: .text "FIRE BALL" ; .byte 0

// ============================================================
// Priest Prayer Name Strings (screen codes, null-terminated)
// ============================================================
psn_0:  .text "DETECT EVIL" ; .byte 0
.label psn_1 = itn_17   // "CURE LIGHT WOUNDS" — shared with item.s
psn_2:  .text "BLESS" ; .byte 0
psn_3:  .text "REMOVE FEAR" ; .byte 0
psn_4:  .text "CALL LIGHT" ; .byte 0
psn_5:  .text "FIND TRAPS" ; .byte 0
psn_6:  .text "DETECT DOORS" ; .byte 0
psn_7:  .text "SLOW POISON" ; .byte 0
psn_8:  .text "BLIND CREATURE" ; .byte 0
psn_9:  .text "PORTAL" ; .byte 0
psn_10: .text "CURE MEDIUM WOUNDS" ; .byte 0
psn_11: .text "CHANT" ; .byte 0
psn_12: .text "SANCTUARY" ; .byte 0
psn_13: .text "REMOVE CURSE" ; .byte 0
psn_14: .text "CURE SERIOUS WOUNDS" ; .byte 0
psn_15: .text "DISPEL UNDEAD" ; .byte 0

// ============================================================
// Bit mask helper for spell known checks
// Index 0-7 maps to bits within a byte (lo or hi)
// ============================================================
spell_bit_mask:
    .byte $01, $02, $04, $08, $10, $20, $40, $80

// ============================================================
// Book → Spell Mapping Tables
// ============================================================
// 8 books: 4 mage (types 47,55,56,57), 4 priest (types 48,58,59,60)
// Each book covers 4 consecutive spells.
.const BOOK_COUNT = 8

book_type_ids:
    .byte 47, 55, 56, 57        // Mage books 1-4
    .byte 48, 58, 59, 60        // Priest books 1-4

book_spell_class:
    .byte SPELL_MAGE, SPELL_MAGE, SPELL_MAGE, SPELL_MAGE
    .byte SPELL_PRIEST, SPELL_PRIEST, SPELL_PRIEST, SPELL_PRIEST

book_spell_start:
    .byte 0, 4, 8, 12           // Mage: spells 0-3, 4-7, 8-11, 12-15
    .byte 0, 4, 8, 12           // Priest: spells 0-3, 4-7, 8-11, 12-15

// book_get_info — Look up book metadata from item type ID
// Input:  A = item type ID
// Output: C=0 found: A = spell_start, X = spell_class
//         C=1 not a book
// Clobbers: X
book_get_info:
    ldx #BOOK_COUNT - 1
!bgi_loop:
    cmp book_type_ids,x
    beq !bgi_found+
    dex
    bpl !bgi_loop-
    sec                         // Not a book
    rts
!bgi_found:
    lda book_spell_start,x
    pha
    lda book_spell_class,x
    tax
    pla                         // A = spell_start, X = spell_class
    clc
    rts

// ============================================================
// Compile-time asserts
// ============================================================

// Table size checks (next table minus this table == count)
.assert "Mage spell mana count",    mage_spell_level - mage_spell_mana,   MAGE_SPELL_COUNT
.assert "Mage spell level count",   mage_spell_fail  - mage_spell_level,  MAGE_SPELL_COUNT
.assert "Mage spell fail count",    priest_spell_mana - mage_spell_fail,  MAGE_SPELL_COUNT
.assert "Priest spell mana count",  priest_spell_level - priest_spell_mana, PRIEST_SPELL_COUNT
.assert "Priest spell level count", priest_spell_fail  - priest_spell_level, PRIEST_SPELL_COUNT

// Name pointer table size checks
.assert "Mage name lo count",   mage_spell_name_hi  - mage_spell_name_lo,  MAGE_SPELL_COUNT
.assert "Priest name lo count", priest_spell_name_hi - priest_spell_name_lo, PRIEST_SPELL_COUNT

// Priest spell fail table size (last numeric table — check against name pointers)
.assert "Priest spell fail count", mage_spell_name_lo - priest_spell_fail, PRIEST_SPELL_COUNT
