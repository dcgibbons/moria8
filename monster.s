// monster.s — Creature data & active monster table
//
// Embedded creature types for dungeon levels 1-5 (26 types).
// Active monster table: 32 slots x 12 bytes each.
// Spawn, find, remove subroutines for the monster system.

// ============================================================
// Constants
// ============================================================
.const MAX_MONSTERS      = 32
.const MONSTER_ENTRY_SIZE = 12
.const DUNGEON_CREATURES = 26   // Types 0-25: dungeon monsters
.const TOWN_CREATURE_BASE = 26 // First town creature index (must == DUNGEON_CREATURES)
.const TOWN_CREATURE_COUNT = 6 // Types 26-31: townspeople
.const CREATURE_COUNT    = 32  // Total creature types
.assert "Town creatures start after dungeon creatures", TOWN_CREATURE_BASE, DUNGEON_CREATURES
.assert "Creature count = dungeon + town", CREATURE_COUNT, DUNGEON_CREATURES + TOWN_CREATURE_COUNT
.const EMPTY_SLOT        = $ff

// Attack type constants
.const ATK_NONE      = 0
.const ATK_NORMAL    = 1
.const ATK_CONFUSE   = 3
.const ATK_ACID      = 6
.const ATK_PARALYZE  = 11
.const ATK_POISON    = 14
.const ATK_FEAR      = 4
.const ATK_CORRODE   = 9
.const ATK_AGGRAVATE = 20

// Active monster entry offsets (12 bytes per entry)
.const MX_X         = 0
.const MX_Y         = 1
.const MX_TYPE      = 2
.const MX_HP_LO     = 3
.const MX_HP_HI     = 4
.const MX_FLAGS     = 5
.const MX_SPEED_CNT = 6
.const MX_SLEEP_CUR = 7
.const MX_STUN      = 8
.const MX_CONFUSE   = 9
// Bytes 10-11 reserved

// Monster flags
.const MF_AWAKE     = $01
.const MF_CONFUSED  = $02
.const MF_PROVOKED  = $04   // Player attacked this monster; town creatures need this to fight back

// Spell flag constants (needed by cr_spell_flags data below)
.const MSF_BOLT       = $01    // Bit 0: bolt (2d8 + level)
.const MSF_BREATH     = $02    // Bit 1: breath (HP/3)
.const MSF_SUMMON     = $04    // Bit 2: summon
.const MSF_TELEPORT   = $08    // Bit 3: teleport-to
.const MSF_BLIND      = $10    // Bit 4: blind
.const MSF_CONFUSE    = $20    // Bit 5: confuse
.const MSF_HEAL       = $40    // Bit 6: heal self

// ============================================================
// Embedded creature data — Struct-of-Arrays
// Types 0-25: dungeon monsters (levels 1-5)
// Types 26-31: townspeople (level 0, umoria town mobs)
// ============================================================

// Display character (screen codes)
cr_display:
    .byte $08   // 0: H (White harpy)
    .byte $12   // 1: R (Giant white mouse)
    .byte $17   // 2: W (White worm mass)
    .byte $13   // 3: S (Large white snake)
    .byte $0b   // 4: K (Kobold)
    .byte $09   // 5: I (White icky thing)
    .byte $0d   // 6: M (Shrieker mushroom)
    .byte $03   // 7: C (Giant white centipede)
    .byte $05   // 8: E (Floating eye)
    .byte $0a   // 9: J (Jackal)
    .byte $17   // 10: W (Green worm mass)
    .byte $06   // 11: F (Giant frog)
    .byte $12   // 12: R (Giant white rat)
    .byte $07   // 13: G (Poltergeist)
    .byte $02   // 14: B (Huge brown bat)
    .byte $24   // 15: $ (Creeping copper coins)
    .byte $0d   // 16: M (Grey mold)
    .byte $03   // 17: C (Metallic green centipede)
    .byte $0d   // 18: M (Yellow mold)
    .byte $01   // 19: A (Giant black ant)
    .byte $0b   // 20: K (Kobold shaman)
    .byte $01   // 21: A (Giant white ant lion)
    .byte $10   // 22: P (Novice mage)
    .byte $10   // 23: P (Novice priest)
    .byte $13   // 24: S (Giant salamander)
    .byte $0f   // 25: O (Orc shaman)
    // Town creatures (P = person, $10)
    .byte $10   // 26: P (Filthy street urchin)
    .byte $10   // 27: P (Singing happy drunk)
    .byte $10   // 28: P (Mangy leper)
    .byte $10   // 29: P (Squint-eyed rogue)
    .byte $10   // 30: P (Mean mercenary)
    .byte $10   // 31: P (Boil-covered wretch)

// Color
cr_color:
    .byte COL_WHITE     // 0: White harpy
    .byte COL_GREEN     // 1: Giant white mouse
    .byte COL_WHITE     // 2: White worm mass
    .byte COL_GREEN     // 3: Large white snake
    .byte COL_GREEN     // 4: Kobold
    .byte COL_WHITE     // 5: White icky thing
    .byte COL_ORANGE    // 6: Shrieker mushroom
    .byte COL_GREEN     // 7: Giant white centipede
    .byte COL_GREEN     // 8: Floating eye
    .byte COL_YELLOW    // 9: Jackal
    .byte COL_GREEN     // 10: Green worm mass
    .byte COL_GREEN     // 11: Giant frog
    .byte COL_YELLOW    // 12: Giant white rat
    .byte COL_LGREY     // 13: Poltergeist
    .byte COL_ORANGE    // 14: Huge brown bat
    .byte COL_YELLOW    // 15: Creeping copper coins
    .byte COL_GREY      // 16: Grey mold
    .byte COL_GREEN     // 17: Metallic green centipede
    .byte COL_YELLOW    // 18: Yellow mold
    .byte COL_LGREY     // 19: Giant black ant
    .byte COL_RED       // 20: Kobold shaman
    .byte COL_WHITE     // 21: Giant white ant lion
    .byte COL_CYAN      // 22: Novice mage
    .byte COL_LGREEN    // 23: Novice priest
    .byte COL_RED       // 24: Giant salamander
    .byte COL_GREEN     // 25: Orc shaman
    // Town creatures
    .byte COL_ORANGE    // 26: Filthy street urchin
    .byte COL_LGREY     // 27: Singing happy drunk
    .byte COL_GREEN     // 28: Mangy leper
    .byte COL_RED       // 29: Squint-eyed rogue
    .byte COL_YELLOW    // 30: Mean mercenary
    .byte COL_PURPLE    // 31: Boil-covered wretch

// Speed (0=slow/every-other-turn, 1=normal, 2=fast)
cr_speed:
    .byte 1, 1, 0, 1, 1, 1, 1, 1, 1, 1
    .byte 0, 1, 1, 2, 2, 0, 1, 2, 1, 1
    .byte 1, 1, 1, 1, 1, 1              // New dungeon creatures 20-25
    .byte 1, 0, 0, 1, 1, 0              // Town creatures 26-31

// Movement flags (CF_ATTACK_ONLY = can attack but not move)
.const CF_ATTACK_ONLY = $01
.const CF_UNDEAD      = $02

cr_mflags:
    .byte  0,  0,  0,  0,  0,  0, CF_ATTACK_ONLY, 0, CF_ATTACK_ONLY, 0
    .byte  0,  0,  0,  0,  0,  0, CF_ATTACK_ONLY, 0, CF_ATTACK_ONLY, 0
    .byte  0,  0,  0,  0,  0,  0                  // Dungeon creatures 20-25
    .byte  0,  0,  0,  0,  0,  0                  // Town: all mobile

// Creature level
cr_level:
    .byte 2, 1, 1, 1, 1, 1, 2, 1, 1, 4
    .byte 2, 2, 4, 3, 3, 4, 1, 2, 3, 2
    .byte 3, 4, 4, 4, 5, 5              // Dungeon creatures 20-25
    .byte 0, 0, 0, 0, 0, 0              // Town: level 0

// Hit dice count (number of dice for HP)
cr_hd_num:
    .byte 2, 1, 4, 3, 3, 3, 1, 3, 3, 3
    .byte 6, 2, 2, 2, 2, 7, 1, 4, 8, 3
    .byte 3, 5, 3, 4, 6, 5              // Dungeon creatures 20-25
    .byte 1, 1, 1, 2, 3, 1              // Town creatures

// Hit dice sides
cr_hd_sides:
    .byte 5, 3, 4, 6, 7, 5, 1, 5, 6, 8
    .byte 4, 8, 2, 5, 6, 8, 2, 4, 8, 6
    .byte 6, 8, 6, 6, 8, 8              // Dungeon creatures 20-25
    .byte 4, 2, 1, 8, 8, 2              // Town creatures

// Armor class
cr_ac:
    .byte 17, 4, 1, 30, 16, 7, 1, 10, 6, 16
    .byte  3, 8, 7, 15, 12, 24, 1, 4, 10, 20
    .byte 14, 20, 6, 10, 18, 16         // Dungeon creatures 20-25
    .byte  2, 1, 1, 8, 16, 1            // Town creatures

// Base sleep value (higher = deeper sleeper)
cr_sleep:
    .byte 10, 20, 10, 99, 10, 10,  0, 40, 10, 30
    .byte 10, 30, 30, 10, 40, 10,  0, 10, 99, 80
    .byte 20, 40, 10, 10, 30, 15         // Dungeon creatures 20-25
    .byte 10,  0, 40,  0,  0, 40         // Town: rogue/merc awake, others light sleep

// Area affect radius (awareness factor)
cr_aaf:
    .byte 16,  8,  7,  4, 20, 12,  2,  7,  2, 12
    .byte  7, 12,  8,  8,  8,  3,  2,  5,  2,  8
    .byte 15, 10, 16, 14, 10, 16           // Dungeon creatures 20-25
    .byte 12,  4,  6, 20, 20,  6           // Town creatures

// Experience value (16-bit, all <=35 for tier 0 — hi bytes all 0)
cr_xp_lo:
    .byte 5, 1, 2, 2, 5, 2, 1, 2, 1, 8
    .byte 3, 6, 1, 6, 4, 9, 1, 3, 9, 8
    .byte 12, 15, 18, 16, 25, 22         // Dungeon creatures 20-25
    .byte 0, 0, 0, 0, 0, 0              // Town: 0 XP
cr_xp_hi:
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0              // Dungeon creatures 20-25
    .byte 0, 0, 0, 0, 0, 0              // Town: 0 XP

// Attack dice (slot 0 only for now; zeroed slots 1-3)
cr_atk0_dice:
    .byte 1, 1, 1, 1, 1, 1, 0, 1, 0, 1
    .byte 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    .byte 1, 2, 1, 1, 2, 1              // Dungeon creatures 20-25
    .byte 1, 1, 1, 1, 2, 1              // Town creatures
cr_atk0_sides:
    .byte 1, 2, 2, 1, 6, 2, 0, 2, 0, 6
    .byte 3, 3, 3, 1, 2, 4, 4, 1, 4, 4
    .byte 4, 4, 6, 5, 6, 8              // Dungeon creatures 20-25
    .byte 2, 1, 1, 6, 6, 1              // Town creatures

// Attack type for slot 0
cr_atk0_type:
    .byte ATK_NORMAL, ATK_NORMAL, ATK_POISON, ATK_NORMAL, ATK_NORMAL
    .byte ATK_NORMAL, ATK_AGGRAVATE, ATK_NORMAL, ATK_PARALYZE, ATK_NORMAL
    .byte ATK_CORRODE, ATK_NORMAL, ATK_POISON, ATK_FEAR, ATK_NORMAL
    .byte ATK_NORMAL, ATK_CONFUSE, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL
    .byte ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL // Dungeon 20-25
    .byte ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL // Town: all normal

// Attack slot 1 (type, dice, sides — 0 = no second attack)
cr_atk1_type:
    .byte ATK_NORMAL, 0, 0, 0, 0, 0, 0, ATK_NORMAL, 0, 0
    .byte          0, 0, 0, 0, 0, ATK_POISON, 0, 0, 0, 0
    .byte          0, 0, 0, 0, 0, 0           // Dungeon 20-25: no second attack
    .byte          0, 0, 0, 0, 0, 0           // Town: no second attack
cr_atk1_dice:
    .byte 1, 0, 0, 0, 0, 0, 0, 1, 0, 0
    .byte 0, 0, 0, 0, 0, 2, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0                    // Dungeon 20-25
    .byte 0, 0, 0, 0, 0, 0                    // Town
cr_atk1_sides:
    .byte 1, 0, 0, 0, 0, 0, 0, 2, 0, 0
    .byte 0, 0, 0, 0, 0, 4, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0                    // Dungeon 20-25
    .byte 0, 0, 0, 0, 0, 0                    // Town

// Spell chance (probability out of 100 that monster casts instead of melee)
cr_spell_chance:
    .byte  0,  0,  0,  0,  0,  0,  0,  0,  0,  0  // Types 0-9: no spells
    .byte  0,  0,  0,  0,  0,  0,  0,  0,  0,  0  // Types 10-19: no spells
    .byte 30,  0, 40, 35, 25, 35                   // Types 20-25: spellcasters
    .byte  0,  0,  0,  0,  0,  0                   // Types 26-31: town

// Spell flags (bitmask of available spells)
cr_spell_flags:
    .byte  0,  0,  0,  0,  0,  0,  0,  0,  0,  0  // Types 0-9
    .byte  0,  0,  0,  0,  0,  0,  0,  0,  0,  0  // Types 10-19
    .byte MSF_BOLT | MSF_HEAL                      // 20: Kobold shaman
    .byte 0                                        // 21: Giant white ant lion
    .byte MSF_BOLT | MSF_CONFUSE | MSF_BLIND       // 22: Novice mage
    .byte MSF_HEAL | MSF_SUMMON                    // 23: Novice priest
    .byte MSF_BREATH                               // 24: Giant salamander
    .byte MSF_BOLT | MSF_CONFUSE | MSF_HEAL        // 25: Orc shaman
    .byte  0,  0,  0,  0,  0,  0                   // Types 26-31: town

// Name pointer tables
cr_name_lo:
    .byte <crn_0,  <crn_1,  <crn_2,  <crn_3,  <crn_4
    .byte <crn_5,  <crn_6,  <crn_7,  <crn_8,  <crn_9
    .byte <crn_10, <crn_11, <crn_12, <crn_13, <crn_14
    .byte <crn_15, <crn_16, <crn_17, <crn_18, <crn_19
    .byte <crn_20, <crn_21, <crn_22, <crn_23, <crn_24, <crn_25
    .byte <crn_26, <crn_27, <crn_28, <crn_29, <crn_30, <crn_31
cr_name_hi:
    .byte >crn_0,  >crn_1,  >crn_2,  >crn_3,  >crn_4
    .byte >crn_5,  >crn_6,  >crn_7,  >crn_8,  >crn_9
    .byte >crn_10, >crn_11, >crn_12, >crn_13, >crn_14
    .byte >crn_15, >crn_16, >crn_17, >crn_18, >crn_19
    .byte >crn_20, >crn_21, >crn_22, >crn_23, >crn_24, >crn_25
    .byte >crn_26, >crn_27, >crn_28, >crn_29, >crn_30, >crn_31

// Name strings (screen codes, null-terminated)
crn_0:  .text "WHITE HARPY" ; .byte 0
crn_1:  .text "GIANT WHITE MOUSE" ; .byte 0
crn_2:  .text "WHITE WORM MASS" ; .byte 0
crn_3:  .text "LARGE WHITE SNAKE" ; .byte 0
crn_4:  .text "KOBOLD" ; .byte 0
crn_5:  .text "WHITE ICKY THING" ; .byte 0
crn_6:  .text "SHRIEKER MUSHROOM" ; .byte 0
crn_7:  .text "GIANT WHITE CENTIPEDE" ; .byte 0
crn_8:  .text "FLOATING EYE" ; .byte 0
crn_9:  .text "JACKAL" ; .byte 0
crn_10: .text "GREEN WORM MASS" ; .byte 0
crn_11: .text "GIANT FROG" ; .byte 0
crn_12: .text "GIANT WHITE RAT" ; .byte 0
crn_13: .text "POLTERGEIST" ; .byte 0
crn_14: .text "HUGE BROWN BAT" ; .byte 0
crn_15: .text "CREEPING COPPER COINS" ; .byte 0
crn_16: .text "GREY MOLD" ; .byte 0
crn_17: .text "METALLIC GREEN CENTIPEDE" ; .byte 0
crn_18: .text "YELLOW MOLD" ; .byte 0
crn_19: .text "GIANT BLACK ANT" ; .byte 0
crn_20: .text "KOBOLD SHAMAN" ; .byte 0
crn_21: .text "GIANT WHITE ANT LION" ; .byte 0
crn_22: .text "NOVICE MAGE" ; .byte 0
crn_23: .text "NOVICE PRIEST" ; .byte 0
crn_24: .text "GIANT SALAMANDER" ; .byte 0
crn_25: .text "ORC SHAMAN" ; .byte 0
// Town creatures
crn_26: .text "FILTHY STREET URCHIN" ; .byte 0
crn_27: .text "SINGING HAPPY DRUNK" ; .byte 0
crn_28: .text "MANGY LEPER" ; .byte 0
crn_29: .text "SQUINT-EYED ROGUE" ; .byte 0
crn_30: .text "MEAN MERCENARY" ; .byte 0
crn_31: .text "BOIL-COVERED WRETCH" ; .byte 0

// ============================================================
// Active monster table — 32 slots x 12 bytes
// ============================================================
monster_table:
    .fill MAX_MONSTERS * MONSTER_ENTRY_SIZE, EMPTY_SLOT

// Pre-computed offset tables for fast entry access
monster_offset_lo:
    .fill MAX_MONSTERS, <(i * MONSTER_ENTRY_SIZE)
monster_offset_hi:
    .fill MAX_MONSTERS, >(i * MONSTER_ENTRY_SIZE)

// ============================================================
// Scratch variables
// ============================================================
ms_spawn_x: .byte 0            // Spawn position for monster_spawn_one
ms_spawn_y: .byte 0
ms_type:    .byte 0             // Creature type for spawn
ms_count:   .byte 0             // Loop counter for monster_spawn_level
mfa_x:      .byte 0             // monster_find_at scratch
mfa_y:      .byte 0

// ============================================================
// Subroutines
// ============================================================

// monster_get_ptr — Set zp_ptr0 to monster_table entry X
// Input:  X = monster index (0-31)
// Output: zp_ptr0/hi = pointer to entry
// Preserves: X, Y
monster_get_ptr:
    lda monster_offset_lo,x
    clc
    adc #<monster_table
    sta zp_ptr0
    lda monster_offset_hi,x
    adc #>monster_table
    sta zp_ptr0_hi
    rts

// monster_init_table — Mark all 32 slots empty, reset count
// Preserves: nothing
monster_init_table:
    ldx #0
    lda #EMPTY_SLOT
!loop:
    sta monster_table,x
    inx
    cpx #MAX_MONSTERS * MONSTER_ENTRY_SIZE
    bne !loop-
    lda #0
    sta zp_mon_count
    rts

// monster_find_free_slot — Find first empty slot
// Output: carry set = found, X = index
//         carry clear = table full
// Preserves: Y
monster_find_free_slot:
    ldx #0
!loop:
    cpx #MAX_MONSTERS
    bcs !full+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !found+
    inx
    jmp !loop-
!found:
    sec
    rts
!full:
    clc
    rts

// find_monster_floor — Find a random floor tile suitable for monster placement
// Requirements: TILE_FLOOR, no FLAG_OCCUPIED, not player position
// Output: ms_spawn_x, ms_spawn_y = position
//         carry set = found, carry clear = failed (200 tries)
// Clobbers: A, X, Y, zp_ptr0, zp_temp3, zp_temp4
find_monster_floor:
    ldx #200                    // Max attempts
!fmf_loop:
    stx ms_count                // Save attempt counter (safe — not clobbered by rng_range)

    // Random x in [1, MAP_COLS-2]
    lda #MAP_COLS - 2           // 78
    jsr rng_range               // [0, 77]
    clc
    adc #1                      // [1, 78]
    sta ms_spawn_x

    // Random y in [1, MAP_ROWS-2]
    lda #MAP_ROWS - 2           // 46
    jsr rng_range               // [0, 45]
    clc
    adc #1                      // [1, 46]
    sta ms_spawn_y

    // Check tile type = TILE_FLOOR
    tax                         // X = y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy ms_spawn_x
    lda (zp_ptr0),y

    // Must be floor tile (upper nibble = $00) with no FLAG_OCCUPIED
    and #TILE_TYPE_MASK | FLAG_OCCUPIED
    bne !fmf_next+              // Not a clean floor tile

    // Must not be player position
    lda ms_spawn_x
    cmp zp_player_x
    bne !fmf_ok+
    lda ms_spawn_y
    cmp zp_player_y
    beq !fmf_next+              // Same as player
!fmf_ok:
    sec                         // Found
    rts

!fmf_next:
    ldx ms_count
    dex
    bne !fmf_loop-
    clc                         // Failed
    rts

// pick_creature_type — Pick random creature type for current dungeon level
// Range: cr_level in [max(1, dlvl-2), dlvl+3], from dungeon creatures only
// Output: A = creature type index (0-19)
// Clobbers: X, Y, zp_temp3, zp_temp4
pick_creature_type:
    // Compute min_level = max(1, dlvl - 2)
    lda zp_player_dlvl
    sec
    sbc #2
    bcs !pct_minok+
    lda #0                      // Underflow
!pct_minok:
    cmp #1
    bcs !pct_min1+
    lda #1                      // Floor at 1
!pct_min1:
    sta pct_min_lvl

    // Compute max_level = dlvl + 3
    lda zp_player_dlvl
    clc
    adc #3
    sta pct_max_lvl

!pct_retry:
    // Pick random creature index [0, DUNGEON_CREATURES-1]
    lda #DUNGEON_CREATURES
    jsr rng_range
    tax                         // X = candidate type

    // Check cr_level in [min_lvl, max_lvl]
    lda cr_level,x
    cmp pct_min_lvl
    bcc !pct_retry-             // Too low
    cmp pct_max_lvl
    beq !pct_accept+            // Equal to max = ok
    bcs !pct_retry-             // Too high
!pct_accept:
    txa                         // A = type index
    rts

pct_min_lvl: .byte 0
pct_max_lvl: .byte 0

// monster_spawn_one — Create one monster at ms_spawn_x/y
// Input:  A = creature type index
//         ms_spawn_x, ms_spawn_y = position
// Output: carry set = success, X = slot index
//         carry clear = table full
// Clobbers: A, X, Y, zp_ptr0, zp_math_a/b, zp_math_tmp0/1, zp_temp3, zp_temp4
monster_spawn_one:
    sta ms_type

    // Find free slot
    jsr monster_find_free_slot
    bcs !mso_have_slot+
    jmp !mso_fail+              // Table full
!mso_have_slot:

    // X = slot index, zp_ptr0 = entry pointer (from find_free_slot)
    // Set position
    ldy #MX_X
    lda ms_spawn_x
    sta (zp_ptr0),y
    ldy #MX_Y
    lda ms_spawn_y
    sta (zp_ptr0),y

    // Set type
    ldy #MX_TYPE
    lda ms_type
    sta (zp_ptr0),y

    // Roll HP: cr_hd_num[type] d cr_hd_sides[type]
    stx zp_mon_idx              // Save slot index
    ldx ms_type
    lda cr_hd_num,x             // N dice
    pha                         // Save on stack
    ldy cr_hd_sides,x           // S sides
    pla                         // A = N
    // math_dice(A=N, X=S, Y=bonus=0)
    sty zp_temp0                // Save sides
    ldx zp_temp0                // X = sides
    ldy #0                      // No bonus
    jsr math_dice               // Result in zp_math_a (lo), zp_math_b (hi)

    // Restore slot pointer (math_dice does NOT clobber zp_ptr0)
    ldx zp_mon_idx
    jsr monster_get_ptr         // Restore zp_ptr0 (safe to re-derive)

    ldy #MX_HP_LO
    lda zp_math_a
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda zp_math_b
    sta (zp_ptr0),y

    // Set flags (start asleep)
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y

    // Set speed counter = 0
    ldy #MX_SPEED_CNT
    lda #0
    sta (zp_ptr0),y

    // Set sleep counter from creature sleep value
    ldy #MX_SLEEP_CUR
    ldx ms_type
    lda cr_sleep,x
    sta (zp_ptr0),y

    // Set stun/confuse to 0
    ldy #MX_STUN
    lda #0
    sta (zp_ptr0),y
    ldy #MX_CONFUSE
    sta (zp_ptr0),y

    // Clear reserved bytes 10-11
    ldy #10
    sta (zp_ptr0),y
    ldy #11
    sta (zp_ptr0),y

    // Set FLAG_OCCUPIED on map tile
    ldx ms_spawn_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy ms_spawn_x
    lda (zp_ptr0),y
    ora #FLAG_OCCUPIED
    sta (zp_ptr0),y

    // Increment monster count
    inc zp_mon_count

    ldx zp_mon_idx              // Return slot index in X
    sec                         // Success
    rts

!mso_fail:
    clc
    rts

// monster_spawn_level — Spawn monsters for current dungeon level
// Dungeon: count = 2 + rng(4) + dlvl/3, capped at 14.
// Town (dlvl=0): 4 + rng(4) townspeople.
// Clobbers: everything
monster_spawn_level:
    // Initialize table
    jsr monster_init_table

    // Town = townspeople
    lda zp_player_dlvl
    bne !msl_dungeon+
    jmp monster_spawn_town

!msl_dungeon:
    // Base count = 2
    lda #2
    sta msl_target

    // + rng(4) → [0,3]
    lda #4
    jsr rng_range
    clc
    adc msl_target
    sta msl_target

    // + dlvl / 3
    lda zp_player_dlvl
    sta zp_math_a
    lda #0
    sta zp_math_b
    ldx #3
    jsr math_div_16x8           // zp_math_a = quotient lo
    lda zp_math_a
    clc
    adc msl_target
    sta msl_target

    // Cap at 14
    cmp #15
    bcc !msl_capped+
    lda #14
    sta msl_target
!msl_capped:

    lda #0
    sta msl_idx

!msl_loop:
    lda msl_idx
    cmp msl_target
    bcs !msl_done+

    // Find floor tile
    jsr find_monster_floor
    bcc !msl_skip+              // No tile found, skip

    // Pick creature type
    jsr pick_creature_type

    // Spawn it
    jsr monster_spawn_one
    // Ignore failure (table could be full)

!msl_skip:
    inc msl_idx
    jmp !msl_loop-

!msl_done:
    rts

msl_target: .byte 0
msl_idx:    .byte 0

// monster_spawn_town — Spawn 4-7 townspeople for dlvl=0
// Clobbers: everything
monster_spawn_town:
    // Count = 4 + rng(4) = [4, 7]
    lda #4
    jsr rng_range               // [0, 3]
    clc
    adc #4                      // [4, 7]
    sta msl_target

    lda #0
    sta msl_idx

!mst_loop:
    lda msl_idx
    cmp msl_target
    bcs !mst_done+

    // Find a floor tile
    jsr find_monster_floor
    bcc !mst_skip+

    // Pick random town creature [TOWN_CREATURE_BASE, TOWN_CREATURE_BASE+5]
    lda #TOWN_CREATURE_COUNT    // 6
    jsr rng_range               // [0, 5]
    clc
    adc #TOWN_CREATURE_BASE     // [20, 25]

    jsr monster_spawn_one

!mst_skip:
    inc msl_idx
    jmp !mst_loop-

!mst_done:
    rts

// monster_find_at — Find monster at map position
// Input:  A = x, Y = y
// Output: carry set = found, X = slot index
//         carry clear = not found
// Clobbers: zp_ptr0, mfa_x, mfa_y
monster_find_at:
    sta mfa_x
    sty mfa_y
    ldx #0
!mfa_loop:
    cpx #MAX_MONSTERS
    bcs !mfa_miss+

    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !mfa_next+

    // Check x
    ldy #MX_X
    lda (zp_ptr0),y
    cmp mfa_x
    bne !mfa_next+

    // Check y
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp mfa_y
    bne !mfa_next+

    // Found
    sec
    rts

!mfa_next:
    inx
    jmp !mfa_loop-

!mfa_miss:
    clc
    rts

// monster_remove — Remove monster at slot X
// Clears FLAG_OCCUPIED on map, marks slot empty, decrements count.
// Input:  X = slot index
// Clobbers: A, Y, zp_ptr0
monster_remove:
    jsr monster_get_ptr

    // Get position for clearing flag
    ldy #MX_X
    lda (zp_ptr0),y
    sta mfa_x                   // Reuse scratch
    ldy #MX_Y
    lda (zp_ptr0),y
    sta mfa_y

    // Mark slot empty (fill with $ff)
    lda #EMPTY_SLOT
    ldy #0
!mr_clear:
    sta (zp_ptr0),y
    iny
    cpy #MONSTER_ENTRY_SIZE
    bne !mr_clear-

    // Clear FLAG_OCCUPIED on map tile
    ldx mfa_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy mfa_x
    lda (zp_ptr0),y
    and #~FLAG_OCCUPIED & $ff   // Clear bit 0
    sta (zp_ptr0),y

    // Decrement count
    dec zp_mon_count
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Monster table size", MAX_MONSTERS * MONSTER_ENTRY_SIZE, 384
.assert "Creature count", CREATURE_COUNT, 32
.assert "cr_display size", cr_color - cr_display, CREATURE_COUNT
.assert "cr_color size", cr_speed - cr_color, CREATURE_COUNT
.assert "cr_speed size", cr_mflags - cr_speed, CREATURE_COUNT
.assert "cr_mflags size", cr_level - cr_mflags, CREATURE_COUNT
.assert "cr_level size", cr_hd_num - cr_level, CREATURE_COUNT
.assert "cr_spell_chance size", cr_spell_flags - cr_spell_chance, CREATURE_COUNT
