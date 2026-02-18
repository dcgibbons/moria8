// tables.s — Game data tables
//
// Race stat modifiers, class data, XP thresholds, stat bonus tables.
// All values from umoria source (data_player.cpp, player_stats.cpp).
//
// Stat encoding: values 3–18 stored as-is. 18/01–18/100 stored as 19–118.
// Bonus tables indexed by stat-3 (16 entries for stats 3-18).
// Stats above 18 (18/xx) use the same bonus as stat 18 (index 15).

// ============================================================
// Race indices
// ============================================================
.const RACE_HUMAN     = 0
.const RACE_HALF_ELF  = 1
.const RACE_ELF       = 2
.const RACE_HALFLING  = 3
.const RACE_GNOME     = 4
.const RACE_DWARF     = 5
.const RACE_HALF_ORC  = 6
.const RACE_HALF_TROLL = 7
.const RACE_COUNT     = 8

// ============================================================
// Class indices
// ============================================================
.const CLASS_WARRIOR  = 0
.const CLASS_MAGE     = 1
.const CLASS_PRIEST   = 2
.const CLASS_ROGUE    = 3
.const CLASS_RANGER   = 4
.const CLASS_PALADIN  = 5
.const CLASS_COUNT    = 6

// Spell types
.const SPELL_NONE     = 0
.const SPELL_MAGE     = 1
.const SPELL_PRIEST   = 2

// Stat indices
.const STAT_STR = 0
.const STAT_INT = 1
.const STAT_WIS = 2
.const STAT_DEX = 3
.const STAT_CON = 4
.const STAT_CHR = 5
.const STAT_COUNT = 6

// ============================================================
// Race stat adjustments (signed bytes, 8 races x 6 stats)
// Order: STR, INT, WIS, DEX, CON, CHR per race
// ============================================================
race_stat_adj:
    //       STR  INT  WIS  DEX  CON  CHR
    .byte     0,   0,   0,   0,   0,   0   // Human
    .byte    -1,   1,   0,   1,  -1,   1   // Half-Elf
    .byte    -1,   2,   1,   1,  -2,   1   // Elf
    .byte    -2,   2,   1,   3,   1,   1   // Halfling
    .byte    -1,   2,   0,   2,   1,  -2   // Gnome
    .byte     2,  -3,   1,  -2,   2,  -3   // Dwarf
    .byte     2,  -1,   0,   0,   1,  -4   // Half-Orc
    .byte     4,  -4,  -2,  -4,   3,  -6   // Half-Troll

// ============================================================
// Class stat adjustments (signed bytes, 6 classes x 6 stats)
// ============================================================
class_stat_adj:
    //       STR  INT  WIS  DEX  CON  CHR
    .byte     5,  -2,  -2,   2,   2,  -1   // Warrior
    .byte    -5,   3,   0,   1,  -2,   1   // Mage
    .byte    -3,  -3,   3,  -1,   0,   2   // Priest
    .byte     2,   1,  -2,   3,   1,  -1   // Rogue
    .byte     2,   2,   0,   1,   1,   1   // Ranger
    .byte     3,  -3,   1,   0,   2,   2   // Paladin

// ============================================================
// Race properties table
// Each race: hit_die, infravision, xp_factor_pct, disarm, search,
//            stealth, fos, bth, bth_bow, save
// 10 bytes per race
// ============================================================
.const RACE_PROP_SIZE = 10
race_properties:
    //       HD  INF  XP%  DIS  SRC  STL  FOS  BTH  BOW  SAV
    .byte   10,   0, 100,   0,   0,   0,   0,   0,   0,   0  // Human
    .byte    9,   2, 110,   2,   6,   1,  -1,  -1,   5,   3  // Half-Elf
    .byte    8,   3, 120,   5,   8,   1,  -2,  -5,  15,   6  // Elf
    .byte    6,   4, 110,  15,  12,   4,  -5, -10,  20,  18  // Halfling
    .byte    7,   4, 125,  10,   6,   3,  -3,  -8,  12,  12  // Gnome
    .byte    9,   5, 120,   2,   7,  -1,   0,  15,   0,   9  // Dwarf
    .byte   10,   3, 110,  -3,   0,  -1,   3,  12,  -5,  -3  // Half-Orc
    .byte   12,   3, 120,  -5,  -1,  -2,   5,  20, -10,  -8  // Half-Troll

// ============================================================
// Race class restrictions (bitmask per race)
// Bit 0=Warrior, 1=Mage, 2=Priest, 3=Rogue, 4=Ranger, 5=Paladin
// ============================================================
race_class_flags:
    .byte %00111111     // Human: all classes
    .byte %00111111     // Half-Elf: all classes
    .byte %00011111     // Elf: Warrior, Mage, Priest, Rogue, Ranger
    .byte %00001011     // Halfling: Warrior, Mage, Rogue
    .byte %00001111     // Gnome: Warrior, Mage, Priest, Rogue
    .byte %00000101     // Dwarf: Warrior, Priest
    .byte %00001101     // Half-Orc: Warrior, Priest, Rogue
    .byte %00000101     // Half-Troll: Warrior, Priest

// ============================================================
// Class properties table
// Each class: hp_die, spell_type, xp_factor, bth, bth_bow,
//             disarm, save, stealth, search, fos
// 10 bytes per class
// ============================================================
.const CLASS_PROP_SIZE = 10
class_properties:
    //       HD  SPL  XP%  BTH  BOW  DIS  SAV  STL  SRC  FOS
    .byte    9,   0,   0,  70,  55,  25,  18,   1,  14,  38  // Warrior
    .byte    0,   1,  30,  34,  20,  30,  36,   2,  16,  20  // Mage
    .byte    2,   2,  20,  48,  35,  25,  30,   2,  16,  32  // Priest
    .byte    6,   1,   0,  60,  66,  45,  30,   5,  32,  16  // Rogue
    .byte    4,   1,  40,  56,  72,  30,  30,   3,  24,  24  // Ranger
    .byte    6,   2,  35,  68,  40,  20,  24,   1,  12,  38  // Paladin

// Class per-level progression (bth, bth_bow, device, disarm, save per level)
.const CLASS_LVL_SIZE = 5
class_level_adj:
    //       BTH  BOW  DEV  DIS  SAV
    .byte     4,   4,   2,   2,   3   // Warrior
    .byte     2,   2,   4,   3,   3   // Mage
    .byte     2,   2,   4,   3,   3   // Priest
    .byte     3,   4,   3,   4,   3   // Rogue
    .byte     3,   4,   3,   3,   3   // Ranger
    .byte     3,   3,   3,   2,   3   // Paladin

// ============================================================
// XP level thresholds (16-bit, 40 levels)
// Base XP values — multiply by (race_xp% + class_xp%) / 100
// Values >65535 stored as hi=255 sentinel (level 30+, handled specially)
// ============================================================
xp_level_lo:
    .byte <10, <25, <45, <70, <100
    .byte <140, <200, <280, <380, <500
    .byte <650, <850, <1100, <1400, <1800
    .byte <2300, <2900, <3600, <4400, <5400
    .byte <6800, <8400, <10200, <12500, <17500
    .byte <25000, <35000, <50000, <65535, <65535
    .byte <65535, <65535, <65535, <65535, <65535
    .byte <65535, <65535, <65535, <65535, <65535

xp_level_hi:
    .byte >10, >25, >45, >70, >100
    .byte >140, >200, >280, >380, >500
    .byte >650, >850, >1100, >1400, >1800
    .byte >2300, >2900, >3600, >4400, >5400
    .byte >6800, >8400, >10200, >12500, >17500
    .byte >25000, >35000, >50000, >65535, >65535
    .byte >65535, >65535, >65535, >65535, >65535
    .byte >65535, >65535, >65535, >65535, >65535

// ============================================================
// Stat bonus tables (indexed by stat value 3–18)
// Index = stat_value - 3 (so index 0 = stat 3, index 15 = stat 18)
// ============================================================
.const STAT_TABLE_SIZE = 16  // 3..18

// STR to-hit bonus
str_tohit_bonus:
    .byte <-3, <-2, <-1, <-1, 0, 0, 0, 0  // STR 3-10
    .byte   0,   0,   0,   0, 0, 1, 1, 1  // STR 11-18

// STR damage bonus
str_damage_bonus:
    .byte <-2, <-1, 0, 0, 0, 0, 0, 0      // STR 3-10
    .byte   0,   0, 0, 1, 2, 3, 3, 3      // STR 11-18

// DEX to-hit bonus
dex_tohit_bonus:
    .byte <-3, <-2, <-2, <-1, <-1, 0, 0, 0  // DEX 3-10
    .byte   0,   0,   0,   1,   2, 3, 3, 3  // DEX 11-18

// DEX AC bonus (positive = better AC)
dex_ac_bonus:
    .byte <-4, <-3, <-2, <-1, 0, 0, 0, 0  // DEX 3-10
    .byte   0,   0,   1,   2, 2, 2, 3, 3  // DEX 11-18

// CON HP bonus (per level)
con_hp_bonus:
    .byte <-4, <-3, <-2, <-1, 0, 0, 0, 0  // CON 3-10
    .byte   0,   0,   0,   0, 0, 1, 2, 2  // CON 11-18

// DEX disarm bonus
dex_disarm_bonus:
    .byte <-8, <-6, <-4, <-2, <-1, 0, 0, 0  // DEX 3-10
    .byte   0,   0,   1,   1,   1, 2, 2, 4  // DEX 11-18

// INT/WIS spell bonus (extra spells)
spell_stat_bonus:
    .byte  0,  0,  0,  0,  0,  1,  1,  1  // 3-10
    .byte  1,  1,  1,  2,  2,  3,  3,  3  // 11-18

// CHR price adjustment (percentage, 100 = no change)
chr_price_adj:
    .byte 130, 125, 122, 120, 118, 116, 114, 112  // CHR 3-10
    .byte 110, 108, 106, 104, 103, 102, 101, 100  // CHR 11-18

// CHR sell price adjustment (percentage of base price stores will pay)
// Index = CHR - 3. CHR 3 = 25%, CHR 18 = 50%.
chr_sell_adj:
    .byte 25, 27, 29, 31, 33, 35, 37, 39   // CHR 3-10
    .byte 41, 43, 44, 45, 46, 47, 48, 50   // CHR 11-18

// ============================================================
// Attack blows table (STR-adjusted, umoria-faithful)
// Rows: STR-adjusted weight bracket (adj_weight = STR*10/weapon_weight)
//   0: adj<3 (too weak), 1: 3-4, 2: 5-7, 3: 8-12, 4: >=13 / unarmed
// Cols: DEX bracket (0=<10, 1=10-14, 2=15-17, 3=18+)
// Returns number of blows per round (1-4)
// ============================================================
.const BLOWS_COLS = 4
blows_table:
    //       DEX<10  10-14  15-17   18+
    .byte      1,     1,     1,    1   // row 0: weak for weapon
    .byte      1,     1,     2,    2   // row 1: fair
    .byte      1,     2,     2,    3   // row 2: good
    .byte      2,     2,     3,    3   // row 3: strong
    .byte      2,     3,     3,    4   // row 4: mighty / unarmed

// ============================================================
// Race name strings (screen codes, null-terminated)
// ============================================================
race_name_ptrs_lo:
    .byte <race_name_0, <race_name_1, <race_name_2, <race_name_3
    .byte <race_name_4, <race_name_5, <race_name_6, <race_name_7
race_name_ptrs_hi:
    .byte >race_name_0, >race_name_1, >race_name_2, >race_name_3
    .byte >race_name_4, >race_name_5, >race_name_6, >race_name_7

race_name_0: .text "HUMAN" ; .byte 0
race_name_1: .text "HALF-ELF" ; .byte 0
race_name_2: .text "ELF" ; .byte 0
race_name_3: .text "HALFLING" ; .byte 0
race_name_4: .text "GNOME" ; .byte 0
race_name_5: .text "DWARF" ; .byte 0
race_name_6: .text "HALF-ORC" ; .byte 0
race_name_7: .text "HALF-TROLL" ; .byte 0

// ============================================================
// Class name strings (screen codes, null-terminated)
// ============================================================
class_name_ptrs_lo:
    .byte <class_name_0, <class_name_1, <class_name_2
    .byte <class_name_3, <class_name_4, <class_name_5
class_name_ptrs_hi:
    .byte >class_name_0, >class_name_1, >class_name_2
    .byte >class_name_3, >class_name_4, >class_name_5

class_name_0: .text "WARRIOR" ; .byte 0
class_name_1: .text "MAGE" ; .byte 0
class_name_2: .text "PRIEST" ; .byte 0
class_name_3: .text "ROGUE" ; .byte 0
class_name_4: .text "RANGER" ; .byte 0
class_name_5: .text "PALADIN" ; .byte 0

// ============================================================
// Stat name strings (screen codes, null-terminated)
// ============================================================
stat_name_ptrs_lo:
    .byte <stat_str, <stat_int, <stat_wis, <stat_dex, <stat_con, <stat_chr
stat_name_ptrs_hi:
    .byte >stat_str, >stat_int, >stat_wis, >stat_dex, >stat_con, >stat_chr

stat_str: .text "STR" ; .byte 0
stat_int: .text "INT" ; .byte 0
stat_wis: .text "WIS" ; .byte 0
stat_dex: .text "DEX" ; .byte 0
stat_con: .text "CON" ; .byte 0
stat_chr: .text "CHR" ; .byte 0

// ============================================================
// Hunger state constants and strings
// ============================================================
.const HUNGER_FULL      = 0
.const HUNGER_HUNGRY    = 1
.const HUNGER_WEAK      = 2
.const HUNGER_FAINT     = 3
hunger_name_ptrs_lo:
    .byte <hunger_0, <hunger_1, <hunger_2, <hunger_3
hunger_name_ptrs_hi:
    .byte >hunger_0, >hunger_1, >hunger_2, >hunger_3

hunger_0: .text "FULL  " ; .byte 0
hunger_1: .text "HUNGRY" ; .byte 0
hunger_2: .text "WEAK  " ; .byte 0
hunger_3: .text "FAINT " ; .byte 0

// ============================================================
// HP regeneration rate: turns per 1 HP healed, indexed by CON-3
// CON 3 = slow (50 turns), CON 18 = fast (8 turns)
// ============================================================
regen_rate:
    .byte 50, 45, 40, 35, 30, 28, 25, 22  // CON 3-10
    .byte 20, 18, 16, 14, 12, 10,  9,  8  // CON 11-18

// ============================================================
// Compile-time validation
// ============================================================
.assert "Race stat table size", RACE_COUNT * STAT_COUNT, 48
.assert "Class stat table size", CLASS_COUNT * STAT_COUNT, 36
.assert "Race prop table size", RACE_COUNT * RACE_PROP_SIZE, 80
.assert "Class prop table size", CLASS_COUNT * CLASS_PROP_SIZE, 60
.assert "XP table size", 40, 40
.assert "Stat bonus table size", STAT_TABLE_SIZE, 16
