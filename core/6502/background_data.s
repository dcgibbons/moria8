#importonce
// background_data.s — Character background history tables
//
// 72 entries from umoria charts 1-23 (family/occupation).
// Appearance charts 50-66 dropped entirely (C-lite approach).
// Any next value >= 50 stored as 0 (terminates chain).
//
// Encoding: parallel metadata arrays + packed string table.
// Lives in StartupOverlay ($E000) — only needed during character creation.

// ============================================================
// Constants
// ============================================================
.const BG_ENTRY_COUNT = 72

// ============================================================
// Race → starting chart ID lookup
// ============================================================
bg_race_start:
    .byte 1     // Human → chart 1
    .byte 4     // Half-Elf → chart 4
    .byte 7     // Elf → chart 7
    .byte 10    // Halfling → chart 10
    .byte 13    // Gnome → chart 13
    .byte 16    // Dwarf → chart 16
    .byte 19    // Half-Orc → chart 19
    .byte 22    // Half-Troll → chart 22

// ============================================================
// Parallel metadata arrays (72 bytes each)
// Entries ordered by chart, then by roll within chart.
// ============================================================

// bg_chart — Which chart this entry belongs to
bg_chart:
    // Chart 1: Human/Half-Orc parentage (4 entries, idx 0-3)
    .byte 1, 1, 1, 1
    // Chart 2: Social class (7 entries, idx 4-10)
    .byte 2, 2, 2, 2, 2, 2, 2
    // Chart 3: Early life (3 entries, idx 11-13)
    .byte 3, 3, 3
    // Chart 4: Half-Elf parental race (6 entries, idx 14-19)
    .byte 4, 4, 4, 4, 4, 4
    // Chart 7: Elf siblings (2 entries, idx 20-21)
    .byte 7, 7
    // Chart 8: Elf parental race (3 entries, idx 22-24)
    .byte 8, 8, 8
    // Chart 9: Elf parent profession (6 entries, idx 25-30)
    .byte 9, 9, 9, 9, 9, 9
    // Chart 10: Halfling siblings (2 entries, idx 31-32)
    .byte 10, 10
    // Chart 11: Halfling parent profession (8 entries, idx 33-40)
    .byte 11, 11, 11, 11, 11, 11, 11, 11
    // Chart 13: Gnome siblings (2 entries, idx 41-42)
    .byte 13, 13
    // Chart 14: Gnome parent profession (5 entries, idx 43-47)
    .byte 14, 14, 14, 14, 14
    // Chart 16: Dwarf siblings (2 entries, idx 48-49)
    .byte 16, 16
    // Chart 17: Dwarf parent profession (6 entries, idx 50-55)
    .byte 17, 17, 17, 17, 17, 17
    // Chart 18: Dwarf early life (3 entries, idx 56-58)
    .byte 18, 18, 18
    // Chart 19: Half-Orc parental race (2 entries, idx 59-60)
    .byte 19, 19
    // Chart 20: Half-Orc adoption (1 entry, idx 61)
    .byte 20
    // Chart 22: Half-Troll parental race (6 entries, idx 62-67)
    .byte 22, 22, 22, 22, 22, 22
    // Chart 23: Troll parent profession (4 entries, idx 68-71)
    .byte 23, 23, 23, 23

// bg_roll — Cumulative d100 roll threshold (1-100)
bg_roll:
    // Chart 1
    .byte 10, 20, 95, 100
    // Chart 2
    .byte 40, 65, 80, 90, 96, 99, 100
    // Chart 3
    .byte 20, 80, 100
    // Chart 4
    .byte 40, 75, 90, 95, 98, 100
    // Chart 7
    .byte 60, 100
    // Chart 8
    .byte 75, 95, 100
    // Chart 9
    .byte 40, 70, 87, 95, 99, 100
    // Chart 10
    .byte 85, 100
    // Chart 11
    .byte 20, 30, 40, 50, 80, 95, 99, 100
    // Chart 13
    .byte 85, 100
    // Chart 14
    .byte 20, 50, 75, 95, 100
    // Chart 16
    .byte 25, 100
    // Chart 17
    .byte 10, 25, 75, 90, 99, 100
    // Chart 18
    .byte 15, 85, 100
    // Chart 19
    .byte 25, 100
    // Chart 20
    .byte 100
    // Chart 22
    .byte 30, 60, 75, 90, 95, 100
    // Chart 23
    .byte 5, 95, 99, 100

// bg_next — Next chart to chain to (0 = terminate)
// Charts 3→50, 9→54, 18→57, 23→62 all become 0 (drop appearance charts)
bg_next:
    // Chart 1 → chart 2
    .byte 2, 2, 2, 2
    // Chart 2 → chart 3
    .byte 3, 3, 3, 3, 3, 3, 3
    // Chart 3 → chart 50 → 0 (terminate — appearance dropped)
    .byte 0, 0, 0
    // Chart 4 → chart 1
    .byte 1, 1, 1, 1, 1, 1
    // Chart 7 → chart 8
    .byte 8, 8
    // Chart 8 → chart 9
    .byte 9, 9, 9
    // Chart 9 → chart 54 → 0 (terminate — appearance dropped)
    .byte 0, 0, 0, 0, 0, 0
    // Chart 10 → chart 11
    .byte 11, 11
    // Chart 11 → chart 3
    .byte 3, 3, 3, 3, 3, 3, 3, 3
    // Chart 13 → chart 14
    .byte 14, 14
    // Chart 14 → chart 3
    .byte 3, 3, 3, 3, 3
    // Chart 16 → chart 17
    .byte 17, 17
    // Chart 17 → chart 18
    .byte 18, 18, 18, 18, 18, 18
    // Chart 18 → chart 57 → 0 (terminate — appearance dropped)
    .byte 0, 0, 0
    // Chart 19 → chart 20
    .byte 20, 20
    // Chart 20 → chart 2
    .byte 2
    // Chart 22 → chart 23
    .byte 23, 23, 23, 23, 23, 23
    // Chart 23 → chart 62 → 0 (terminate — appearance dropped)
    .byte 0, 0, 0, 0

// bg_bonus — Social class bonus (raw umoria value, bonus-50 applied in code)
bg_bonus:
    // Chart 1
    .byte 25, 35, 45, 50
    // Chart 2
    .byte 65, 80, 90, 105, 120, 130, 140
    // Chart 3
    .byte 20, 55, 60
    // Chart 4
    .byte 50, 55, 55, 60, 65, 70
    // Chart 7
    .byte 50, 55
    // Chart 8
    .byte 50, 55, 60
    // Chart 9
    .byte 80, 90, 110, 125, 140, 145
    // Chart 10
    .byte 45, 55
    // Chart 11
    .byte 55, 80, 90, 100, 110, 115, 125, 140
    // Chart 13
    .byte 45, 55
    // Chart 14
    .byte 55, 70, 85, 100, 125
    // Chart 16
    .byte 40, 50
    // Chart 17
    .byte 60, 75, 90, 110, 130, 150
    // Chart 18
    .byte 10, 50, 55
    // Chart 19
    .byte 25, 25
    // Chart 20
    .byte 50
    // Chart 22
    .byte 20, 25, 30, 35, 40, 45
    // Chart 23
    .byte 60, 55, 65, 80

// ============================================================
// String pointer tables (72 entries, lo/hi)
// Multiple entries can point to the same string (deduplication).
// ============================================================
bg_str_lo:
    // Chart 1 (idx 0-3)
    .byte <bg_s00, <bg_s01, <bg_s02, <bg_s03
    // Chart 2 (idx 4-10)
    .byte <bg_s04, <bg_s05, <bg_s06, <bg_s07, <bg_s08, <bg_s09, <bg_s10
    // Chart 3 (idx 11-13)
    .byte <bg_s11, <bg_s12, <bg_s13
    // Chart 4 (idx 14-19)
    .byte <bg_s14, <bg_s15, <bg_s16, <bg_s17, <bg_s18, <bg_s19
    // Chart 7 (idx 20-21)
    .byte <bg_s02, <bg_s20         // idx 20 reuses "You are one of several children "
    // Chart 8 (idx 22-24)
    .byte <bg_s21, <bg_s22, <bg_s23
    // Chart 9 (idx 25-30)
    .byte <bg_s24, <bg_s25, <bg_s_warrior, <bg_s_mage, <bg_s26, <bg_s_king
    // Chart 10 (idx 31-32)
    .byte <bg_s27, <bg_s28
    // Chart 11 (idx 33-40)
    .byte <bg_s29, <bg_s30, <bg_s31, <bg_s32, <bg_s33, <bg_s_warrior, <bg_s_mage, <bg_s34
    // Chart 13 (idx 41-42)
    .byte <bg_s35, <bg_s36
    // Chart 14 (idx 43-47)
    .byte <bg_s37, <bg_s38, <bg_s39, <bg_s_warrior, <bg_s_mage
    // Chart 16 (idx 48-49)
    .byte <bg_s40, <bg_s41
    // Chart 17 (idx 50-55)
    .byte <bg_s42, <bg_s43, <bg_s44, <bg_s_warrior, <bg_s45, <bg_s_king
    // Chart 18 (idx 56-58)
    .byte <bg_s11, <bg_s12, <bg_s13  // Reuse chart 3 strings
    // Chart 19 (idx 59-60)
    .byte <bg_s46, <bg_s47
    // Chart 20 (idx 61)
    .byte <bg_s48
    // Chart 22 (idx 62-67)
    .byte <bg_s49, <bg_s50, <bg_s51, <bg_s52, <bg_s53, <bg_s54
    // Chart 23 (idx 68-71)
    .byte <bg_s55, <bg_s_warrior, <bg_s56, <bg_s57

bg_str_hi:
    // Chart 1 (idx 0-3)
    .byte >bg_s00, >bg_s01, >bg_s02, >bg_s03
    // Chart 2 (idx 4-10)
    .byte >bg_s04, >bg_s05, >bg_s06, >bg_s07, >bg_s08, >bg_s09, >bg_s10
    // Chart 3 (idx 11-13)
    .byte >bg_s11, >bg_s12, >bg_s13
    // Chart 4 (idx 14-19)
    .byte >bg_s14, >bg_s15, >bg_s16, >bg_s17, >bg_s18, >bg_s19
    // Chart 7 (idx 20-21)
    .byte >bg_s02, >bg_s20
    // Chart 8 (idx 22-24)
    .byte >bg_s21, >bg_s22, >bg_s23
    // Chart 9 (idx 25-30)
    .byte >bg_s24, >bg_s25, >bg_s_warrior, >bg_s_mage, >bg_s26, >bg_s_king
    // Chart 10 (idx 31-32)
    .byte >bg_s27, >bg_s28
    // Chart 11 (idx 33-40)
    .byte >bg_s29, >bg_s30, >bg_s31, >bg_s32, >bg_s33, >bg_s_warrior, >bg_s_mage, >bg_s34
    // Chart 13 (idx 41-42)
    .byte >bg_s35, >bg_s36
    // Chart 14 (idx 43-47)
    .byte >bg_s37, >bg_s38, >bg_s39, >bg_s_warrior, >bg_s_mage
    // Chart 16 (idx 48-49)
    .byte >bg_s40, >bg_s41
    // Chart 17 (idx 50-55)
    .byte >bg_s42, >bg_s43, >bg_s44, >bg_s_warrior, >bg_s45, >bg_s_king
    // Chart 18 (idx 56-58)
    .byte >bg_s11, >bg_s12, >bg_s13
    // Chart 19 (idx 59-60)
    .byte >bg_s46, >bg_s47
    // Chart 20 (idx 61)
    .byte >bg_s48
    // Chart 22 (idx 62-67)
    .byte >bg_s49, >bg_s50, >bg_s51, >bg_s52, >bg_s53, >bg_s54
    // Chart 23 (idx 68-71)
    .byte >bg_s55, >bg_s_warrior, >bg_s56, >bg_s57

// ============================================================
// Packed null-terminated strings (screen codes)
// Shared strings listed first for deduplication.
// ============================================================

// --- Shared strings (used by multiple entries) ---
// BPE dictionary ($80+ tokens expand recursively to bg_dict_l, bg_dict_r)
bg_dict_l:
    .byte $20, $2e, $81, $05, $80, $59, $85, $05, $14, $0f, $09, $89, $17, $04, $86, $8e
    .byte $8c, $88, $91, $92, $86, $94, $03, $96, $8f, $93, $0e, $12, $0c, $0c, $88, $45
    .byte $2d, $06, $98, $97, $87, $0f, $0c, $95, $95, $a8, $0c, $01, $a9, $a7, $a0, $54
    .byte $af, $b0, $47, $2d, $14, $0e, $09, $97, $89, $07, $03, $01, $ba, $bc, $bd, $be
    .byte $bf, $b7, $c1, $b4, $ab, $a5, $c5, $a5, $c7, $c8, $c9, $a2, $98, $50, $16, $16
    .byte $0d, $09, $d1, $01, $01, $d3, $ce, $cc, $b6, $b2, $b2, $da, $a0, $9a, $8d, $8b
    .byte $8b, $8a, $17, $15, $e3, $e4, $14, $0d, $0c, $09, $09, $06, $04, $02
bg_dict_r:
    .byte $01, $20, $20, $20, $20, $0f, $15, $12, $08, $06, $0c, $84, $01, $20, $80, $12
    .byte $13, $87, $20, $90, $12, $20, $08, $8a, $83, $84, $20, $05, $20, $06, $83, $9d
    .byte $9f, $01, $9e, $8d, $82, $0e, $05, $a1, $0d, $0f, $9c, $0e, $99, $99, $82, $12
    .byte $0f, $aa, $9b, $b1, $20, $0f, $0e, $04, $20, $05, $0b, $12, $b5, $17, $a6, $04
    .byte $b9, $9b, $9a, $09, $82, $83, $b8, $0c, $19, $20, $a3, $ca, $c6, $12, $87, $05
    .byte $c4, $07, $08, $9c, $14, $c2, $d5, $13, $07, $19, $05, $0e, $20, $4f, $a3, $48
    .byte $47, $0c, $0e, $0e, $01, $c0, $82, $83, $01, $14, $05, $82, $82, $15

// Compressed background fragment strings (screen codes + $80+ BPE tokens, NUL terminated)
bg_s_warrior:
    .byte $57, $bb, $12, $09, $0f, $12, $82, $00 // "Warrior.  "
bg_s_mage:
    .byte $4d, $01, $b9, $82, $00 // "Mage.  "
bg_s_king:
    .byte $4b, $d8, $82, $00 // "King.  "
bg_s00:
    .byte $a2, $8a, $a6, $07, $e9, $09, $0d, $d4, $05, $80, $0e, $8d, $e5, $de, $00 // "You are the illegitimate and unacknowledged child "
bg_s01:
    .byte $a2, $8a, $a6, $07, $e9, $09, $0d, $d4, $83, $ed, $14, $80, $c0, $de, $00 // "You are the illegitimate but acknowledged child "
bg_s02:
    .byte $d7, $05, $d6, $00 // "You are one of several children "
bg_s03:
    .byte $a2, $06, $09, $12, $13, $b4, $a3, $00 // "You are the first child "
bg_s04:
    .byte $8b, $53, $87, $eb, $00 // "of a Serf.  "
bg_s05:
    .byte $8b, $59, $05, $0f, $d0, $00 // "of a Yeoman.  "
bg_s06:
    .byte $8b, $54, $0f, $e2, $13, $d0, $00 // "of a Townsman.  "
bg_s07:
    .byte $e0, $15, $8a, $04, $13, $d0, $00 // "of a Guildsman.  "
bg_s08:
    .byte $8b, $4c, $ab, $04, $05, $8d, $4b, $0e, $d2, $e6, $00 // "of a Landed Knight.  "
bg_s09:
    .byte $8b, $54, $e9, $a6, $8d, $4e, $0f, $02, $a6, $82, $00 // "of a Titled Noble.  "
bg_s10:
    .byte $8b, $52, $0f, $19, $d3, $42, $0c, $0f, $0f, $8d, $4c, $b6, $05, $82, $00 // "of a Royal Blood Line.  "
bg_s11:
    .byte $a2, $02, $e8, $ba, $20, $13, $08, $05, $05, $10, $20, $b8, $9e, $a1, $0d, $8a, $19, $82, $00 // "You are the black sheep of the family.  "
bg_s12:
    .byte $8f, $05, $84, $03, $9b, $04, $09, $b4, $14, $0f, $20, $9e, $a1, $0d, $8a, $19, $82, $00 // "You are a credit to the family.  "
bg_s13:
    .byte $8f, $05, $84, $17, $05, $aa, $0c, $09, $0b, $05, $8d, $b7, $82, $00 // "You are a well liked child.  "
bg_s14:
    .byte $ac, $db, $ae, $00 // "Your mother was a Green-Elf.  "
bg_s15:
    .byte $ad, $db, $ae, $00 // "Your father was a Green-Elf.  "
bg_s16:
    .byte $ac, $d9, $ae, $00 // "Your mother was a Grey-Elf.  "
bg_s17:
    .byte $ad, $d9, $ae, $00 // "Your father was a Grey-Elf.  "
bg_s18:
    .byte $ac, $48, $d2, $ae, $00 // "Your mother was a High-Elf.  "
bg_s19:
    .byte $ad, $48, $d2, $ae, $00 // "Your father was a High-Elf.  "
bg_s20:
    .byte $cb, $00 // "You are the only child "
bg_s21:
    .byte $8b, $db, $dc, $00 // "of a Green-Elf "
bg_s22:
    .byte $8b, $d9, $dc, $00 // "of a Grey-Elf "
bg_s23:
    .byte $df, $d2, $dc, $00 // "of a High-Elf "
bg_s24:
    .byte $52, $ab, $07, $a4, $00 // "Ranger.  "
bg_s25:
    .byte $41, $12, $96, $a4, $00 // "Archer.  "
bg_s26:
    .byte $cd, $b6, $03, $05, $82, $00 // "Prince.  "
bg_s27:
    .byte $d7, $05, $d6, $df, $01, $9d, $0c, $d8, $20, $00 // "You are one of several children of a Halfling "
bg_s28:
    .byte $cb, $df, $01, $9d, $0c, $d8, $20, $00 // "You are the only child of a Halfling "
bg_s29:
    .byte $42, $15, $0d, $82, $00 // "Bum.  "
bg_s30:
    .byte $54, $01, $ce, $dd, $e2, $a4, $00 // "Tavern Owner.  "
bg_s31:
    .byte $4d, $e1, $a4, $00 // "Miller.  "
bg_s32:
    .byte $48, $0f, $e7, $4f, $e2, $a4, $00 // "Home Owner.  "
bg_s33:
    .byte $42, $15, $12, $07, $0c, $bb, $82, $00 // "Burglar.  "
bg_s34:
    .byte $43, $e8, $9a, $45, $0c, $04, $a4, $00 // "Clan Elder.  "
bg_s35:
    .byte $d7, $05, $d6, $e0, $b5, $e7, $00 // "You are one of several children of a Gnome "
bg_s36:
    .byte $cb, $e0, $b5, $e7, $00 // "You are the only child of a Gnome "
bg_s37:
    .byte $42, $05, $07, $07, $bb, $82, $00 // "Beggar.  "
bg_s38:
    .byte $42, $12, $01, $07, $07, $bb, $e6, $00 // "Braggart.  "
bg_s39:
    .byte $cd, $ab, $0b, $13, $14, $a4, $00 // "Prankster.  "
bg_s40:
    .byte $cc, $14, $17, $0f, $20, $c2, $8b, $44, $8c, $12, $cf, $9a, $00 // "You are one of two children of a Dwarven "
bg_s41:
    .byte $cb, $8b, $44, $8c, $12, $cf, $9a, $00 // "You are the only child of a Dwarven "
bg_s42:
    .byte $54, $08, $ea, $eb, $00 // "Thief.  "
bg_s43:
    .byte $cd, $09, $13, $0f, $9a, $47, $15, $bb, $ec, $00 // "Prison Guard.  "
bg_s44:
    .byte $4d, $b6, $a4, $00 // "Miner.  "
bg_s45:
    .byte $cd, $ea, $13, $e6, $00 // "Priest.  "
bg_s46:
    .byte $a9, $93, $80, $dd, $12, $03, $2c, $20, $ed, $c3, $c3, $13, $20, $e5, $ec, $00 // "Your mother was an Orc, but it is unacknowledged.  "
bg_s47:
    .byte $a7, $93, $80, $dd, $12, $03, $2c, $20, $ed, $c3, $c3, $13, $20, $e5, $ec, $00 // "Your father was an Orc, but it is unacknowledged.  "
bg_s48:
    .byte $98, $88, $05, $80, $04, $0f, $10, $14, $05, $de, $00 // "You are the adopted child "
bg_s49:
    .byte $ac, $43, $01, $cf, $b3, $00 // "Your mother was a Cave-Troll "
bg_s50:
    .byte $ad, $43, $01, $cf, $b3, $00 // "Your father was a Cave-Troll "
bg_s51:
    .byte $ac, $48, $e1, $b3, $00 // "Your mother was a Hill-Troll "
bg_s52:
    .byte $ad, $48, $e1, $b3, $00 // "Your father was a Hill-Troll "
bg_s53:
    .byte $ac, $57, $d4, $87, $b3, $00 // "Your mother was a Water-Troll "
bg_s54:
    .byte $ad, $57, $d4, $87, $b3, $00 // "Your father was a Water-Troll "
bg_s55:
    .byte $43, $0f, $0f, $0b, $82, $00 // "Cook.  "
bg_s56:
    .byte $53, $08, $01, $d0, $00 // "Shaman.  "
bg_s57:
    .byte $43, $e8, $9a, $43, $08, $ea, $eb, $00 // "Clan Chief.  "

bg_text_buf:
    .fill 200, 0
