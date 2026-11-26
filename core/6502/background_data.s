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
bg_s_warrior:
    .text "Warrior.  " ; .byte 0
bg_s_mage:
    .text "Mage.  " ; .byte 0
bg_s_king:
    .text "King.  " ; .byte 0

// --- Chart 1: Parentage ---
bg_s00:
    .text "You are the illegitimate and unacknowledged child " ; .byte 0
bg_s01:
    .text "You are the illegitimate but acknowledged child " ; .byte 0
bg_s02:
    .text "You are one of several children " ; .byte 0
bg_s03:
    .text "You are the first child " ; .byte 0

// --- Chart 2: Social class ---
bg_s04:
    .text "of a Serf.  " ; .byte 0
bg_s05:
    .text "of a Yeoman.  " ; .byte 0
bg_s06:
    .text "of a Townsman.  " ; .byte 0
bg_s07:
    .text "of a Guildsman.  " ; .byte 0
bg_s08:
    .text "of a Landed Knight.  " ; .byte 0
bg_s09:
    .text "of a Titled Noble.  " ; .byte 0
bg_s10:
    .text "of a Royal Blood Line.  " ; .byte 0

// --- Chart 3/18: Early life (shared between Human and Dwarf paths) ---
bg_s11:
    .text "You are the black sheep of the family.  " ; .byte 0
bg_s12:
    .text "You are a credit to the family.  " ; .byte 0
bg_s13:
    .text "You are a well liked child.  " ; .byte 0

// --- Chart 4: Half-Elf parental race ---
bg_s14:
    .text "Your mother was a Green-Elf.  " ; .byte 0
bg_s15:
    .text "Your father was a Green-Elf.  " ; .byte 0
bg_s16:
    .text "Your mother was a Grey-Elf.  " ; .byte 0
bg_s17:
    .text "Your father was a Grey-Elf.  " ; .byte 0
bg_s18:
    .text "Your mother was a High-Elf.  " ; .byte 0
bg_s19:
    .text "Your father was a High-Elf.  " ; .byte 0

// --- Chart 7: Elf siblings ---
// bg_s02 reused for "You are one of several children "
bg_s20:
    .text "You are the only child " ; .byte 0

// --- Chart 8: Elf parental race ---
bg_s21:
    .text "of a Green-Elf " ; .byte 0
bg_s22:
    .text "of a Grey-Elf " ; .byte 0
bg_s23:
    .text "of a High-Elf " ; .byte 0

// --- Chart 9: Elf parent profession ---
bg_s24:
    .text "Ranger.  " ; .byte 0
bg_s25:
    .text "Archer.  " ; .byte 0
// bg_s_warrior reused for "Warrior.  "
// bg_s_mage reused for "Mage.  "
bg_s26:
    .text "Prince.  " ; .byte 0
// bg_s_king reused for "King.  "

// --- Chart 10: Halfling siblings ---
bg_s27:
    .text "You are one of several children of a Halfling " ; .byte 0
bg_s28:
    .text "You are the only child of a Halfling " ; .byte 0

// --- Chart 11: Halfling parent profession ---
bg_s29:
    .text "Bum.  " ; .byte 0
bg_s30:
    .text "Tavern Owner.  " ; .byte 0
bg_s31:
    .text "Miller.  " ; .byte 0
bg_s32:
    .text "Home Owner.  " ; .byte 0
bg_s33:
    .text "Burglar.  " ; .byte 0
// bg_s_warrior and bg_s_mage reused
bg_s34:
    .text "Clan Elder.  " ; .byte 0

// --- Chart 13: Gnome siblings ---
bg_s35:
    .text "You are one of several children of a Gnome " ; .byte 0
bg_s36:
    .text "You are the only child of a Gnome " ; .byte 0

// --- Chart 14: Gnome parent profession ---
bg_s37:
    .text "Beggar.  " ; .byte 0
bg_s38:
    .text "Braggart.  " ; .byte 0
bg_s39:
    .text "Prankster.  " ; .byte 0
// bg_s_warrior and bg_s_mage reused

// --- Chart 16: Dwarf siblings ---
bg_s40:
    .text "You are one of two children of a Dwarven " ; .byte 0
bg_s41:
    .text "You are the only child of a Dwarven " ; .byte 0

// --- Chart 17: Dwarf parent profession ---
bg_s42:
    .text "Thief.  " ; .byte 0
bg_s43:
    .text "Prison Guard.  " ; .byte 0
bg_s44:
    .text "Miner.  " ; .byte 0
// bg_s_warrior reused
bg_s45:
    .text "Priest.  " ; .byte 0
// bg_s_king reused

// --- Chart 18: Dwarf early life (reuses chart 3 strings bg_s11-bg_s13) ---

// --- Chart 19: Half-Orc parental race ---
bg_s46:
    .text "Your mother was an Orc, but it is unacknowledged.  " ; .byte 0
bg_s47:
    .text "Your father was an Orc, but it is unacknowledged.  " ; .byte 0

// --- Chart 20: Half-Orc adoption ---
bg_s48:
    .text "You are the adopted child " ; .byte 0

// --- Chart 22: Half-Troll parental race ---
bg_s49:
    .text "Your mother was a Cave-Troll " ; .byte 0
bg_s50:
    .text "Your father was a Cave-Troll " ; .byte 0
bg_s51:
    .text "Your mother was a Hill-Troll " ; .byte 0
bg_s52:
    .text "Your father was a Hill-Troll " ; .byte 0
bg_s53:
    .text "Your mother was a Water-Troll " ; .byte 0
bg_s54:
    .text "Your father was a Water-Troll " ; .byte 0

// --- Chart 23: Troll parent profession ---
bg_s55:
    .text "Cook.  " ; .byte 0
// bg_s_warrior reused
bg_s56:
    .text "Shaman.  " ; .byte 0
bg_s57:
    .text "Clan Chief.  " ; .byte 0

// ============================================================
// Scratch buffer for text accumulation (overlay-only, temporary)
// ============================================================
bg_text_buf:
    .fill 200, 0
