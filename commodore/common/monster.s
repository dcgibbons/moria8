#importonce
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
.const MAX_DUNGEON_CREATURES = 57 // Largest tier (tier 4)
.const MAX_TOWN_CREATURES    = 8  // Town creature slots
.const MAX_CREATURES         = MAX_DUNGEON_CREATURES + MAX_TOWN_CREATURES  // 65
.const TOWN_CREATURE_BASE    = MAX_DUNGEON_CREATURES  // First town index = 57
.const TOWN_CREATURE_COUNT   = 8  // All 8 umoria town creatures
.const NUM_SOA_FIELDS        = 22 // Number of SoA arrays for tier loading
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
.const MX_FLEE_LO  = 10   // Flee threshold HP (lo byte)
.const MX_FLEE_HI  = 11   // Flee threshold HP (hi byte)

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
// Active creature buffers — Struct-of-Arrays (65 entries)
//
// Layout: [0..56] = dungeon creatures (loaded from tier data)
//         [57..64] = town creatures (always resident)
// Indices [active_dungeon_count..56] are unused (zeroed).
// Town creatures at TOWN_CREATURE_BASE (57) are pre-populated below.
// ============================================================

// How many dungeon creatures are currently loaded in the active buffer
active_dungeon_count: .byte 26  // Initial: 26 embedded dungeon creatures

// Display character (screen codes)
cr_display:
    .byte $08, $12, $17, $13, $0b, $09, $0d, $03, $05, $0a  // 0-9
    .byte $17, $06, $12, $07, $02, $24, $0d, $03, $0d, $01  // 10-19
    .byte $0b, $01, $10, $10, $13, $0f                       // 20-25
    .fill 31, 0                                              // 26-56: unused
    .byte $10, $10, $10, $10, $10, $10, $10, $10              // 57-64: town (P)

// Color
cr_color:
    .byte COL_WHITE, COL_GREEN, COL_WHITE, COL_GREEN, COL_GREEN     // 0-4
    .byte COL_WHITE, COL_ORANGE, COL_GREEN, COL_GREEN, COL_YELLOW   // 5-9
    .byte COL_GREEN, COL_GREEN, COL_YELLOW, COL_LGREY, COL_ORANGE   // 10-14
    .byte COL_YELLOW, COL_GREY, COL_GREEN, COL_YELLOW, COL_LGREY   // 15-19
    .byte COL_RED, COL_WHITE, COL_CYAN, COL_LGREEN, COL_RED, COL_GREEN  // 20-25
    .fill 31, 0                                                     // 26-56: unused
    .byte COL_LGREY, COL_LGREY, COL_LGREY, COL_LGREY, COL_CYAN, COL_LGREY, COL_CYAN, COL_RED  // 57-64: town

// Speed (0=slow/every-other-turn, 1=normal, 2=fast)
cr_speed:
    .byte 1, 1, 0, 1, 1, 1, 1, 1, 1, 1                     // 0-9
    .byte 0, 1, 1, 2, 2, 0, 1, 2, 1, 1                     // 10-19
    .byte 1, 1, 1, 1, 1, 1                                  // 20-25
    .fill 31, 0                                              // 26-56
    .byte 1, 1, 1, 1, 1, 1, 1, 1                             // 57-64: town

// Movement/classification flags
.const CF_ATTACK_ONLY = $01
.const CF_UNDEAD      = $02
.const CF_EVIL        = $04
.const CF_ANIMAL      = $08
.const CF_DRAGON      = $10
.const CF_GROUP       = $20   // Pack creature: spawns extras, wakes neighbors
.const CF_BREEDER     = $40   // Multiplying creature: chance to clone each turn

cr_mflags:
    .byte CF_EVIL, CF_ANIMAL, CF_ANIMAL|CF_BREEDER, CF_ANIMAL, CF_EVIL|CF_GROUP         // 0-4
    .byte CF_BREEDER, CF_ATTACK_ONLY, CF_ANIMAL, CF_ATTACK_ONLY, CF_ANIMAL|CF_GROUP     // 5-9
    .byte CF_ANIMAL|CF_BREEDER, CF_ANIMAL, CF_ANIMAL, CF_UNDEAD|CF_EVIL, CF_ANIMAL      // 10-14
    .byte 0, CF_ATTACK_ONLY|CF_BREEDER, CF_ANIMAL, CF_ATTACK_ONLY|CF_BREEDER, CF_ANIMAL // 15-19
    .byte CF_EVIL|CF_GROUP, CF_ANIMAL, CF_EVIL, CF_EVIL, CF_ANIMAL, CF_EVIL|CF_GROUP    // 20-25
    .fill 31, 0                                                           // 26-56
    .byte  0,  0,  0,  0,  0,  0,  0,  0                                  // 57-64: town

// Creature level
cr_level:
    .byte 2, 1, 1, 1, 1, 1, 2, 1, 1, 4                     // 0-9
    .byte 2, 2, 4, 3, 3, 4, 1, 2, 3, 2                     // 10-19
    .byte 3, 4, 4, 4, 5, 5                                  // 20-25
    .fill 31, 0                                              // 26-56
    .byte 0, 0, 0, 0, 0, 0, 0, 0                             // 57-64: town level 0

// Hit dice count (number of dice for HP)
cr_hd_num:
    .byte 2, 1, 4, 3, 3, 3, 1, 3, 3, 3                     // 0-9
    .byte 6, 2, 2, 2, 2, 7, 1, 4, 8, 3                     // 10-19
    .byte 3, 5, 3, 4, 6, 5                                  // 20-25
    .fill 31, 0                                              // 26-56
    .byte 1, 1, 1, 1, 2, 2, 5, 7                             // 57-64: town

// Hit dice sides
cr_hd_sides:
    .byte 5, 3, 4, 6, 7, 5, 1, 5, 6, 8                     // 0-9
    .byte 4, 8, 2, 5, 6, 8, 2, 4, 8, 6                     // 10-19
    .byte 6, 8, 6, 6, 8, 8                                  // 20-25
    .fill 31, 0                                              // 26-56
    .byte 4, 2, 4, 1, 8, 3, 8, 8                             // 57-64: town

// Armor class
cr_ac:
    .byte 17, 4, 1, 30, 16, 7, 1, 10, 6, 16                // 0-9
    .byte  3, 8, 7, 15, 12, 24, 1, 4, 10, 20               // 10-19
    .byte 14, 20, 6, 10, 18, 16                             // 20-25
    .fill 31, 0                                              // 26-56
    .byte  1, 1, 1, 1, 8, 1, 20, 30                          // 57-64: town

// Base sleep value (higher = deeper sleeper)
cr_sleep:
    .byte 10, 20, 10, 99, 10, 10,  0, 40, 10, 30           // 0-9
    .byte 10, 30, 30, 10, 40, 10,  0, 10, 99, 80           // 10-19
    .byte 20, 40, 10, 10, 30, 15                            // 20-25
    .fill 31, 0                                              // 26-56
    .byte 40,  0, 40, 50, 99,  0, 250, 250                   // 57-64: town

// Area affect radius (awareness factor)
cr_aaf:
    .byte 16,  8,  7,  4, 20, 12,  2,  7,  2, 12           // 0-9
    .byte  7, 12,  8,  8,  8,  3,  2,  5,  2,  8           // 10-19
    .byte 15, 10, 16, 14, 10, 16                            // 20-25
    .fill 31, 0                                              // 26-56
    .byte  4,  6, 10, 10, 10, 10, 10, 10                     // 57-64: town

// Experience value (16-bit)
cr_xp_lo:
    .byte 5, 1, 2, 2, 5, 2, 1, 2, 1, 8                     // 0-9
    .byte 3, 6, 1, 6, 4, 9, 1, 3, 9, 8                     // 10-19
    .byte 12, 15, 18, 16, 25, 22                            // 20-25
    .fill 31, 0                                              // 26-56
    .fill 8, 0                                               // 57-64: town 0 XP
cr_xp_hi:
    .fill 26, 0                                              // 0-25: all zero
    .fill 31, 0                                              // 26-56
    .fill 8, 0                                               // 57-64: town 0 XP

// Attack 0 dice
cr_atk0_dice:
    .byte 1, 1, 1, 1, 1, 1, 0, 1, 0, 1                     // 0-9
    .byte 1, 1, 1, 1, 1, 1, 1, 1, 1, 1                     // 10-19
    .byte 1, 2, 1, 1, 2, 1                                  // 20-25
    .fill 31, 0                                              // 26-56
    .byte 0, 0, 0, 0, 1, 0, 1, 2                             // 57-64: town
cr_atk0_sides:
    .byte 1, 2, 2, 1, 6, 2, 0, 2, 0, 6                     // 0-9
    .byte 3, 3, 3, 1, 2, 4, 4, 1, 4, 4                     // 10-19
    .byte 4, 4, 6, 5, 6, 8                                  // 20-25
    .fill 31, 0                                              // 26-56
    .byte 0, 0, 0, 0, 6, 0, 10, 6                            // 57-64: town

// Attack 0 type
cr_atk0_type:
    .byte ATK_NORMAL, ATK_NORMAL, ATK_POISON, ATK_NORMAL, ATK_NORMAL     // 0-4
    .byte ATK_NORMAL, ATK_AGGRAVATE, ATK_NORMAL, ATK_PARALYZE, ATK_NORMAL // 5-9
    .byte ATK_CORRODE, ATK_NORMAL, ATK_POISON, ATK_FEAR, ATK_NORMAL      // 10-14
    .byte ATK_NORMAL, ATK_CONFUSE, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL    // 15-19
    .byte ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL // 20-25
    .fill 31, 0                                                           // 26-56
    .byte ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL, ATK_NORMAL // 57-64: town

// Attack slot 1 (type, dice, sides — 0 = no second attack)
cr_atk1_type:
    .byte ATK_NORMAL, 0, 0, 0, 0, 0, 0, ATK_NORMAL, 0, 0   // 0-9
    .byte          0, 0, 0, 0, 0, ATK_POISON, 0, 0, 0, 0   // 10-19
    .byte          0, 0, 0, 0, 0, 0                          // 20-25
    .fill 31, 0                                              // 26-56
    .byte ATK_NORMAL, 0, 0, 0, ATK_NORMAL, 0, 0, 0           // 57-64: town
cr_atk1_dice:
    .byte 1, 0, 0, 0, 0, 0, 0, 1, 0, 0                     // 0-9
    .byte 0, 0, 0, 0, 0, 2, 0, 0, 0, 0                     // 10-19
    .byte 0, 0, 0, 0, 0, 0                                  // 20-25
    .fill 31, 0                                              // 26-56
    .fill 8, 0                                               // 57-64: town
cr_atk1_sides:
    .byte 1, 0, 0, 0, 0, 0, 0, 2, 0, 0                     // 0-9
    .byte 0, 0, 0, 0, 0, 4, 0, 0, 0, 0                     // 10-19
    .byte 0, 0, 0, 0, 0, 0                                  // 20-25
    .fill 31, 0                                              // 26-56
    .fill 8, 0                                               // 57-64: town

// Spell chance (probability out of 100 that monster casts instead of melee)
cr_spell_chance:
    .byte  0,  0,  0,  0,  0,  0,  0,  0,  0,  0           // 0-9
    .byte  0,  0,  0,  0,  0,  0,  0,  0,  0,  0           // 10-19
    .byte 30,  0, 40, 35, 25, 35                            // 20-25: spellcasters
    .fill 31, 0                                              // 26-56
    .fill 8, 0                                               // 57-64: town

// Spell flags (bitmask of available spells)
cr_spell_flags:
    .byte  0,  0,  0,  0,  0,  0,  0,  0,  0,  0           // 0-9
    .byte  0,  0,  0,  0,  0,  0,  0,  0,  0,  0           // 10-19
    .byte MSF_BOLT | MSF_HEAL                               // 20: Kobold shaman
    .byte 0                                                  // 21: Giant white ant lion
    .byte MSF_BOLT | MSF_CONFUSE | MSF_BLIND                // 22: Novice mage
    .byte MSF_HEAL | MSF_SUMMON                             // 23: Novice priest
    .byte MSF_BREATH                                        // 24: Giant salamander
    .byte MSF_BOLT | MSF_CONFUSE | MSF_HEAL                 // 25: Orc shaman
    .fill 31, 0                                              // 26-56
    .fill 8, 0                                               // 57-64: town

// Name pointer tables (lo/hi)
cr_name_lo:
    .byte <crn_0,  <crn_1,  <crn_2,  <crn_3,  <crn_4       // 0-4
    .byte <crn_5,  <crn_6,  <crn_7,  <crn_8,  <crn_9       // 5-9
    .byte <crn_10, <crn_11, <crn_12, <crn_13, <crn_14       // 10-14
    .byte <crn_15, <crn_16, <crn_17, <crn_18, <crn_19       // 15-19
    .byte <crn_20, <crn_21, <crn_22, <crn_23, <crn_24, <crn_25  // 20-25
    .fill 31, 0                                              // 26-56
    .byte <crn_t0, <crn_t1, <crn_t2, <crn_t3, <crn_t4, <crn_t5, <crn_t6, <crn_t7 // 57-64: town
cr_name_hi:
    .byte >crn_0,  >crn_1,  >crn_2,  >crn_3,  >crn_4       // 0-4
    .byte >crn_5,  >crn_6,  >crn_7,  >crn_8,  >crn_9       // 5-9
    .byte >crn_10, >crn_11, >crn_12, >crn_13, >crn_14       // 10-14
    .byte >crn_15, >crn_16, >crn_17, >crn_18, >crn_19       // 15-19
    .byte >crn_20, >crn_21, >crn_22, >crn_23, >crn_24, >crn_25  // 20-25
    .fill 31, 0                                              // 26-56
    .byte >crn_t0, >crn_t1, >crn_t2, >crn_t3, >crn_t4, >crn_t5, >crn_t6, >crn_t7 // 57-64: town

// Name strings (screen codes, null-terminated)
// Dungeon creatures
crn_0:  .text "White Harpy" ; .byte 0
crn_1:  .text "Giant White Mouse" ; .byte 0
crn_2:  .text "White Worm Mass" ; .byte 0
crn_3:  .text "Large White Snake" ; .byte 0
crn_4:  .text "Kobold" ; .byte 0
crn_5:  .text "White Icky Thing" ; .byte 0
crn_6:  .text "Shrieker Mushroom" ; .byte 0
crn_7:  .text "Giant White Centipede" ; .byte 0
crn_8:  .text "Floating Eye" ; .byte 0
crn_9:  .text "Jackal" ; .byte 0
crn_10: .text "Green Worm Mass" ; .byte 0
crn_11: .text "Giant Frog" ; .byte 0
crn_12: .text "Giant White Rat" ; .byte 0
crn_13: .text "Poltergeist" ; .byte 0
crn_14: .text "Huge Brown Bat" ; .byte 0
crn_15: .text "Creeping Copper Coins" ; .byte 0
crn_16: .text "Grey Mold" ; .byte 0
crn_17: .text "Metallic Green Centipede" ; .byte 0
crn_18: .text "Yellow Mold" ; .byte 0
crn_19: .text "Giant Black Ant" ; .byte 0
crn_20: .text "Kobold Shaman" ; .byte 0
crn_21: .text "Giant White Ant Lion" ; .byte 0
crn_22: .text "Novice Mage" ; .byte 0
crn_23: .text "Novice Priest" ; .byte 0
crn_24: .text "Giant Salamander" ; .byte 0
crn_25: .text "Orc Shaman" ; .byte 0
// Town creatures (referenced from indices 57-64)
crn_t0: .text "Filthy Street Urchin" ; .byte 0
crn_t1: .text "Blubbering Idiot" ; .byte 0
crn_t2: .text "Pitiful-Looking Beggar" ; .byte 0
crn_t3: .text "Mangy-Looking Leper" ; .byte 0
crn_t4: .text "Squint-Eyed Rogue" ; .byte 0
crn_t5: .text "Singing, Happy Drunk" ; .byte 0
crn_t6: .text "Mean-Looking Mercenary" ; .byte 0
crn_t7: .text "Battle-Scarred Veteran" ; .byte 0

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

// monster_wake — Set MF_AWAKE flag on a monster
// Input: X = monster slot index
// Clobbers: A, Y, zp_ptr0/hi
monster_wake:
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_AWAKE
    sta (zp_ptr0),y
    rts

// monster_apply_sleep — Clear awake state and set the live sleep counter
// Input: A = sleep duration, X = monster slot index
// Clobbers: A, Y, zp_ptr0/hi
monster_apply_sleep:
    pha
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #<~MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    pla
    sta (zp_ptr0),y
    rts

// monster_init_table — Mark all 32 slots empty, reset count
// Clears 384 bytes (32 slots × 12 bytes). Two-pass loop because
// cpx #384 truncates to cpx #128 on 6502 (8-bit immediate).
// Preserves: nothing
monster_init_table:
    ldx #0
    lda #EMPTY_SLOT
!loop1:
    sta monster_table,x
    inx
    bne !loop1-                 // Clear bytes 0-255
!loop2:
    sta monster_table + 256,x
    inx
    cpx #(MAX_MONSTERS * MONSTER_ENTRY_SIZE - 256)  // 128
    bne !loop2-                 // Clear bytes 256-383
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
    :MapRead_ptr0_y()

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
// Uses the loaded dungeon roster and chooses uniformly from all creatures with
// cr_level <= current dungeon depth. Unlike the old narrow-band picker, this
// cannot collapse deep floors to a single monster just because the tier has
// sparse high-end entries.
// Output: A = creature type index within [0, active_dungeon_count)
// Clobbers: X, Y, zp_temp3
pick_creature_type:
    lda zp_player_dlvl
    beq !pct_fallback+
    lda active_dungeon_count
    beq !pct_fallback+
    ldx #0
    ldy #0
!pct_count_loop:
    cpx active_dungeon_count
    bcs !pct_count_done+
    lda cr_level,x
    cmp zp_player_dlvl
    bcc !pct_count_hit+
    bne !pct_count_next+
!pct_count_hit:
    iny
!pct_count_next:
    inx
    jmp !pct_count_loop-
!pct_count_done:
    tya
    beq !pct_fallback+
    jsr rng_range
    sta zp_temp3
    ldx #0
!pct_pick_loop:
    cpx active_dungeon_count
    bcs !pct_fallback+
    lda cr_level,x
    cmp zp_player_dlvl
    bcc !pct_pick_hit+
    bne !pct_pick_next+
!pct_pick_hit:
    lda zp_temp3
    beq !pct_found+
    dec zp_temp3
!pct_pick_next:
    inx
    jmp !pct_pick_loop-
!pct_fallback:
    lda #0
    rts
!pct_found:
    txa
    rts

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

    // Compute flee threshold = rolled_HP / 4
    // zp_math_a/b still hold HP from math_dice
    lda zp_math_b           // HP hi byte
    lsr                     // /2 hi
    sta zp_mon_scratch0     // temp hi
    lda zp_math_a           // HP lo byte
    ror                     // /2 lo (carry from hi)
    lsr zp_mon_scratch0     // /4 hi
    ror                     // /4 lo (carry from hi)
    ldy #MX_FLEE_LO
    sta (zp_ptr0),y
    lda zp_mon_scratch0
    ldy #MX_FLEE_HI
    sta (zp_ptr0),y

    // Set FLAG_OCCUPIED on map tile
    ldx ms_spawn_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy ms_spawn_x
    :MapRead_ptr0_y()
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()

    // Increment monster count
    inc zp_mon_count

    ldx zp_mon_idx              // Return slot index in X
    sec                         // Success
    rts

!mso_fail:
    clc
    rts

// find_adjacent_empty — Find adjacent empty floor tile
// Input: fae_cx, fae_cy = center position
// Output: carry set = found (ms_spawn_x/y set), carry clear = none
// Tries 8 adjacent tiles starting at random direction
// Clobbers: A, X, Y, zp_ptr0, zp_temp3, zp_temp4
find_adjacent_empty:
    lda #8
    jsr rng_range               // Random start [0,7]
    sta fae_dir
    lda #8
    sta fae_tries
!fae_loop:
    ldx fae_dir
    lda fae_cx
    clc
    adc dir_dx,x
    sta ms_spawn_x
    lda fae_cy
    clc
    adc dir_dy,x
    sta ms_spawn_y
    // Check tile: floor + unoccupied
    ldx ms_spawn_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy ms_spawn_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK | FLAG_OCCUPIED
    bne !fae_next+
    // Not player pos
    lda ms_spawn_x
    cmp zp_player_x
    bne !fae_found+
    lda ms_spawn_y
    cmp zp_player_y
    beq !fae_next+
!fae_found:
    sec
    rts
!fae_next:
    inc fae_dir
    lda fae_dir
    and #$07
    sta fae_dir
    dec fae_tries
    bne !fae_loop-
    clc
    rts
fae_cx:    .byte 0
fae_cy:    .byte 0
fae_dir:   .byte 0
fae_tries: .byte 0

// spawn_group_extras — Spawn 1-3 extra same-type monsters adjacent
// Input: ms_type = creature type, ms_spawn_x/y = center position
// Clobbers: everything
spawn_group_extras:
    lda ms_spawn_x
    sta fae_cx
    lda ms_spawn_y
    sta fae_cy
    lda #3
    jsr rng_range               // [0,2]
    clc
    adc #1                      // [1,3]
    sta sge_count
!sge_loop:
    jsr find_adjacent_empty
    bcc !sge_done+
    lda ms_type
    jsr monster_spawn_one
    bcc !sge_done+              // Table full
    dec sge_count
    bne !sge_loop-
!sge_done:
    rts
sge_count: .byte 0

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
    bcc !msl_skip+              // Spawn failed
    // Group spawn check
    ldx ms_type
    lda cr_mflags,x
    and #CF_GROUP
    beq !msl_skip+
    jsr spawn_group_extras

!msl_skip:
    inc msl_idx
    jmp !msl_loop-

!msl_done:
    jsr tramp_spawn_special_room_monsters
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

    // Pick random town creature [TOWN_CREATURE_BASE, TOWN_CREATURE_BASE+7]
    lda #TOWN_CREATURE_COUNT    // 8
    jsr rng_range               // [0, 7]
    clc
    adc #TOWN_CREATURE_BASE     // [57, 64]

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
    :MapRead_ptr0_y()
    and #~FLAG_OCCUPIED & $ff   // Clear bit 0
    :MapWrite_ptr0_y()

    // Decrement count
    dec zp_mon_count
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Monster table size", MAX_MONSTERS * MONSTER_ENTRY_SIZE, 384
.assert "Monster table >256 bytes", MAX_MONSTERS * MONSTER_ENTRY_SIZE > 256, true
.assert "Max creatures", MAX_CREATURES, 65
.assert "Town creature base", TOWN_CREATURE_BASE, 57
.assert "cr_display size", cr_color - cr_display, MAX_CREATURES
.assert "cr_color size", cr_speed - cr_color, MAX_CREATURES
.assert "cr_speed size", cr_mflags - cr_speed, MAX_CREATURES
.assert "cr_mflags size", cr_level - cr_mflags, MAX_CREATURES
.assert "cr_level size", cr_hd_num - cr_level, MAX_CREATURES
.assert "cr_spell_chance size", cr_spell_flags - cr_spell_chance, MAX_CREATURES

// ============================================================
// load_tier_to_buffer — Copy tier SoA data into active creature buffers
// ============================================================
// Input: zp_ptr0 = pointer to tier data start
//        A = creature count for this tier
// The tier data is sequential SoA arrays in this order:
//   display, color, speed, mflags, level, hd_num, hd_sides, ac, sleep, aaf,
//   xp_lo, xp_hi, atk0_type, atk0_dice, atk0_sides,
//   atk1_type, atk1_dice, atk1_sides, spell_chance, spell_flags,
//   name_lo, name_hi
// Each array is `count` bytes long.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1
load_tier_to_buffer:
    sta active_dungeon_count
    sta ltb_count

    ldx #0                      // Array index
!ltb_array:
    // Get destination base from table
    lda ltb_dst_lo,x
    sta zp_ptr1
    lda ltb_dst_hi,x
    sta zp_ptr1_hi

    // Copy ltb_count bytes from (zp_ptr0) to (zp_ptr1)
    stx ltb_array_idx           // Save array counter
    ldy #0
!ltb_byte:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    cpy ltb_count
    bne !ltb_byte-

    // Advance source pointer by count
    clc
    lda zp_ptr0
    adc ltb_count
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #0
    sta zp_ptr0_hi

    ldx ltb_array_idx           // Restore array counter
    inx
    cpx #NUM_SOA_FIELDS         // 22 arrays
    bne !ltb_array-

    rts

ltb_count:     .byte 0
ltb_array_idx: .byte 0

// Destination pointer table — maps field index to active buffer base address
ltb_dst_lo:
    .byte <cr_display, <cr_color, <cr_speed, <cr_mflags, <cr_level
    .byte <cr_hd_num, <cr_hd_sides, <cr_ac, <cr_sleep, <cr_aaf
    .byte <cr_xp_lo, <cr_xp_hi
    .byte <cr_atk0_type, <cr_atk0_dice, <cr_atk0_sides
    .byte <cr_atk1_type, <cr_atk1_dice, <cr_atk1_sides
    .byte <cr_spell_chance, <cr_spell_flags
    .byte <cr_name_lo, <cr_name_hi
ltb_dst_hi:
    .byte >cr_display, >cr_color, >cr_speed, >cr_mflags, >cr_level
    .byte >cr_hd_num, >cr_hd_sides, >cr_ac, >cr_sleep, >cr_aaf
    .byte >cr_xp_lo, >cr_xp_hi
    .byte >cr_atk0_type, >cr_atk0_dice, >cr_atk0_sides
    .byte >cr_atk1_type, >cr_atk1_dice, >cr_atk1_sides
    .byte >cr_spell_chance, >cr_spell_flags
    .byte >cr_name_lo, >cr_name_hi


// ============================================================
// creature_get_name — Get creature name with KERNAL ROM banking
// ============================================================
// Input: X = creature type index
// Output: A = name string ptr lo, Y = name string ptr hi
// For tier-loaded creatures: reads name pointers from the tier
// overlay at $E000 and copies name to creature_name_buf.
// For resident/town creatures: returns pointer directly if in
// normal RAM, or copies via banking if under KERNAL ROM.
// Clobbers: A, Y, zp_ptr1
creature_get_name:
#if C128
    lda #0
    sta cgn_src_banked
#endif

    lda current_tier
    bne !cgn_has_tier+
    jmp !cgn_no_tier+           // No tier → use cr_name tables (no banking)
!cgn_has_tier:
    cpx active_dungeon_count
    bcc !cgn_tier_indexed+      // X < count → read via tier name arrays

    // Tier loaded but X >= active_dungeon_count.
    // Creature may have a valid $E0xx name pointer from current tier.
    lda cr_name_hi,x
    bne !+
    jmp !cgn_stale+             // Null pointer → "?"
!:  cmp #$e0
    bcs !+
    jmp !cgn_setup_normal+      // Normal RAM pointer
 !:  // $E0xx pointer, tier still at $E000 — bank out KERNAL and read
    sta zp_ptr1_hi
    lda cr_name_lo,x
    sta zp_ptr1
#if C128
    jmp !cgn_do_bank_c128+
#else
    jmp !cgn_do_bank_c64+
#endif
#if C128
!cgn_do_bank_c128:
    lda #1
    sta cgn_src_banked
    jmp !cgn_translate_b1_ptr+
#endif

!cgn_tier_indexed:
    // --- Tier creature: read ptr from active tier name tables ---
    // C128: read from the active Bank 1 tier cache slot via helper wrappers.
    // C64: existing $E000 banked read path.
#if C128
    php
    sei
    txa
    tay
    lda tier_name_lo_addr
    sta zp_ptr1
    lda tier_name_lo_addr+1
    sta zp_ptr1_hi
    jsr mmu_safe_db_read_ptr1
    pha
    lda tier_name_hi_addr
    sta zp_ptr1
    lda tier_name_hi_addr+1
    sta zp_ptr1_hi
    jsr mmu_safe_db_read_ptr1
    sta zp_ptr1_hi
    pla
    sta zp_ptr1
    plp
    lda #1
    sta cgn_src_banked
    jmp !cgn_translate_b1_ptr+
#else
    jmp !cgn_tier_c64+
#endif

!cgn_translate_b1_ptr:
#if C128
    // C128 tier name pointers are typically encoded as historical $E0xx
    // payload addresses; convert those to the active Bank 1 tier cache slot.
    // Do not assume every cached tier lives at $8000. Tier 2/3/4 occupy later
    // Bank 1 slots, so translate by offset-from-$E000 plus the current tier's
    // actual cache base. If pointers are already inside the reclaimed Bank 1
    // cache window, keep them. Any other range is invalid for banked fetch.
    lda zp_ptr1_hi
    cmp #$e0
    bcc !cgn_ptr_maybe_b1+
    sec
    lda zp_ptr1
    sbc #<BANKED_DATA_BASE
    sta cgn_saved_x
    lda zp_ptr1_hi
    sbc #>BANKED_DATA_BASE
    sta cgn_saved_p01
    ldx current_tier
    lda c128_tier_cache_slot_lo,x
    clc
    adc cgn_saved_x
    sta zp_ptr1
    lda c128_tier_cache_slot_hi,x
    adc cgn_saved_p01
    sta zp_ptr1_hi
    jmp !cgn_copy+
!cgn_ptr_maybe_b1:
    cmp #>BANK1_FREE_HIGH_BASE
    bcs !cgn_ptr_check_hi+
    jmp !cgn_stale+
!cgn_ptr_check_hi:
    cmp #>(BANK1_FREE_HIGH_END + 1)
    bcc !cgn_copy+
    jmp !cgn_stale+
#endif
    jmp !cgn_copy+

#if !C128
!cgn_tier_c64:
    // C64 active tier names are copied to hidden RAM under I/O during tier
    // activation. Use the resident cr_name pointer; do not depend on the
    // transient $E000 tier staging image.
    lda cr_name_hi,x
    bne !cgn_setup_normal+
    jmp !cgn_stale+
#endif

!cgn_do_bank_c64:
#if !C128
    // C64/Plus4: bank out KERNAL for $E0xx pointer reads.
    php
    sei
#if !PLUS4
    lda hal_memory_cpu_port
    sta cgn_saved_p01
#endif
    :BankOutKernal()
    jmp !cgn_copy+
#endif

!cgn_no_tier:
    // No tier loaded — cr_name tables only (can't resolve $E0xx)
    lda cr_name_hi,x
    bne !cgn_hi_ok+
    jmp !cgn_stale+             // Null pointer → "?"
!cgn_hi_ok:
    cmp #$e0
    bcs !+
    jmp !cgn_setup_normal+      // Normal RAM pointer — use directly
!:  // Stale $E0xx pointer: tier was previously loaded but current_tier was reset.
#if !C128
    // If an overlay is currently executing from $E000, reloading tier names
    // would overwrite the running overlay before the caller returns. Use a
    // generic monster name for overlay-local combat messages instead.
    lda current_overlay
    beq !cgn_reload_allowed+
    jmp !cgn_overlay_name+
!cgn_reload_allowed:
#endif
#if !C128
    // C64 active tier names are no longer owned by $E000. A stale $E0xx
    // pointer means old state, not a recoverable gameplay owner.
    jmp !cgn_stale+
#else
    // Reload the smallest tier that covers creature index X (e.g. recall in town).
    stx cgn_saved_x
    lda #1
    sta current_tier
!cgn_find_tier:
    ldx current_tier
    cpx #5
    bcc !cgn_tier_idx_ok+
    jmp !cgn_reload_fail+       // Beyond tier 4 → give up
!cgn_tier_idx_ok:
    lda tier_count_table,x      // Creature count for this tier
    cmp cgn_saved_x             // compare count vs creature index
    bcc !cgn_next_tier+         // count < index → not in this tier
    beq !cgn_next_tier+         // count == index → index out of [0..count-1]
    // count > index → this tier covers creature X
    lda #1
    sta tier_silent_restore
    jsr tier_load               // Internal stale-name recovery; no visible load msg
    lda #0
    sta tier_silent_restore
    ldx current_tier
    bne !cgn_reload_ok+
    jmp !cgn_reload_fail+       // Load failed (disk error) → "?"
!cgn_reload_ok:
    ldx cgn_saved_x
    jmp !cgn_tier_indexed-      // Use tier-indexed path to read name
!cgn_next_tier:
    inc current_tier
    jmp !cgn_find_tier-
!cgn_reload_fail:
    ldx cgn_saved_x
    jmp !cgn_stale+
#endif

!cgn_setup_normal:
#if !C128
    cmp #>PLATFORM_TIER_NAME_POOL_BASE
    bcc !cgn_setup_linear_c64+
    cmp #>(PLATFORM_TIER_NAME_POOL_END + 1)
    bcc !cgn_setup_hidden_c64+
!cgn_setup_linear_c64:
#endif
    // Valid pointer in normal RAM — set up and share copy loop
    sta zp_ptr1_hi
    lda cr_name_lo,x
    sta zp_ptr1
#if !C128
    php
    sei
#if !PLUS4
    lda hal_memory_cpu_port
    sta cgn_saved_p01           // Save bank config without using stack
#endif
    jmp !cgn_copy+
#endif
    // C128 falls through to shared copy loop.

#if !C128
!cgn_setup_hidden_c64:
    // Hidden $D000-$D7FF RAM is only visible with I/O banked out.
    sta zp_ptr1_hi
    lda cr_name_lo,x
    sta zp_ptr1
    php
    sei
#if !PLUS4
    lda hal_memory_cpu_port
    sta cgn_saved_p01
    lda #BANK_ALL_RAM
    sta hal_memory_cpu_port
#endif
    jmp !cgn_copy+
#endif

!cgn_copy:
#if C128
    // C128 Bank 1 cache copy path (no $01 banking required).
    lda cgn_src_banked
    beq !cgn_copy_linear+
    php
    sei
    ldx #0
!cgn_copy_bank_lp:
    ldy #0
    jsr mmu_safe_db_read_ptr1
    sta creature_name_buf,x
    beq !cgn_copy_bank_done+
    inc zp_ptr1
    bne !cgn_copy_bank_ptr_ok+
    inc zp_ptr1_hi
!cgn_copy_bank_ptr_ok:
    inx
    cpx #31
    bne !cgn_copy_bank_lp-
    lda #0
    sta creature_name_buf,x
!cgn_copy_bank_done:
    plp
    lda #<creature_name_buf
    ldy #>creature_name_buf
    rts
#endif

!cgn_copy_linear:
    ldy #0
!cgn_copy_lp:
    lda (zp_ptr1),y
    sta creature_name_buf,y
    beq !cgn_done+
    iny
    cpy #31
    bne !cgn_copy_lp-
    lda #0
    sta creature_name_buf,y
!cgn_done:
#if !C128
#if !PLUS4
    lda cgn_saved_p01
    sta hal_memory_cpu_port
#endif
    plp
#endif
    lda #<creature_name_buf
    ldy #>creature_name_buf
    rts

!cgn_stale:
    // No valid name pointer — return "?" as safety fallback
    lda #$3f                    // '?'
    sta creature_name_buf
    lda #0
    sta creature_name_buf+1
    lda #<creature_name_buf
    ldy #>creature_name_buf
    rts

#if !C128
!cgn_overlay_name:
    lda #<cgn_monster_str
    ldy #>cgn_monster_str
    rts
#endif

#if C128
tier_name_lo_addr: .word 0
tier_name_hi_addr: .word 0
#endif
creature_name_buf: .fill 32, 0
cgn_saved_x: .byte 0           // scratch: saved creature index for tier reload
#if C128
cgn_src_banked: .byte 0        // 1 = copy name via C128 Bank 1 DB helper
#endif
cgn_saved_p01: .byte 0         // saved $01 for linear copy restore (stack-free)
#if !C128
cgn_monster_str: .text "monster" ; .byte 0
#endif
