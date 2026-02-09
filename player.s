// player.s — Player data structure and accessors
//
// The player struct is stored in a contiguous block in main RAM.
// Hot fields are mirrored in ZP (zeropage.s) for fast access.
// This module provides the full struct and sync routines between
// ZP and the main struct.
//
// Total struct size: ~128 bytes

// ============================================================
// Player struct layout (offsets)
// ============================================================
.const PL_NAME      = 0    // 17 bytes: name (16 chars + null)
.const PL_RACE      = 17   // 1 byte: race index (0–7)
.const PL_CLASS     = 18   // 1 byte: class index (0–5)
.const PL_LEVEL     = 19   // 1 byte: player level (1–40)
.const PL_DLEVEL    = 20   // 1 byte: dungeon level (0=town)
// Base stats (before modifiers)
.const PL_STR_BASE  = 21
.const PL_INT_BASE  = 22
.const PL_WIS_BASE  = 23
.const PL_DEX_BASE  = 24
.const PL_CON_BASE  = 25
.const PL_CHR_BASE  = 26
// Current stats (after race/class/equipment mods)
.const PL_STR_CUR   = 27
.const PL_INT_CUR   = 28
.const PL_WIS_CUR   = 29
.const PL_DEX_CUR   = 30
.const PL_CON_CUR   = 31
.const PL_CHR_CUR   = 32
// Vitals
.const PL_HP_LO     = 33   // Current HP (16-bit)
.const PL_HP_HI     = 34
.const PL_MHP_LO    = 35   // Max HP (16-bit)
.const PL_MHP_HI    = 36
.const PL_MANA      = 37   // Current mana (8-bit, max 255)
.const PL_MAX_MANA  = 38   // Max mana
// Combat
.const PL_AC        = 39   // Armor class
.const PL_TOHIT     = 40   // To-hit bonus (base + modifiers)
.const PL_TODMG     = 41   // To-damage bonus
.const PL_BLOWS     = 42   // Attacks per round
// Economy / XP
.const PL_GOLD_0    = 43   // Gold (24-bit, up to 16M)
.const PL_GOLD_1    = 44
.const PL_GOLD_2    = 45
.const PL_XP_0      = 46   // Experience (24-bit)
.const PL_XP_1      = 47
.const PL_XP_2      = 48
// Position
.const PL_MAP_X     = 49   // Map X position (0–79)
.const PL_MAP_Y     = 50   // Map Y position (0–47)
// Food / hunger
.const PL_FOOD_LO   = 51   // Food counter (16-bit)
.const PL_FOOD_HI   = 52
.const PL_HUNGER    = 53   // Hunger state (0–3)
// Flags
.const PL_FLAGS     = 54   // Bit flags (see below)
.const PL_LIGHT_RAD = 55   // Light radius
.const PL_MAX_DLVL  = 56   // Deepest dungeon level reached
.const PL_AGE       = 57   // Character age
.const PL_HEIGHT    = 58   // Height (aesthetic)
.const PL_WEIGHT    = 59   // Weight (aesthetic)
.const PL_SPELL_TYPE = 60  // Spell type (0=none, 1=mage, 2=priest)
.const PL_SPELLS_KNOWN = 61 // Bitmask of spells learned (16 bits)
.const PL_SPELLS_KNOWN_HI = 62
// Exceptional STR (0 = none, 1–100 = percentage; 100 displayed as "18/00")
.const PL_STR_EXTRA = 63
// Reserved
.const PL_RESERVED  = 64   // Start of reserved area
.const PL_STRUCT_SIZE = 80  // Total struct size (with padding)

// Player flags
.const PLF_MALE     = $01
.const PLF_SEE_INV  = $02
.const PLF_FREE_ACT = $04
.const PLF_SLOW_DIG = $08
.const PLF_SEARCHING = $10
.const PLF_RESTING  = $20

// ============================================================
// Player struct storage
// ============================================================
player_data:
    .fill PL_STRUCT_SIZE, 0

// ============================================================
// Subroutines
// ============================================================

// player_init — Zero out player struct
// Preserves: nothing
player_init:
    lda #0
    ldx #PL_STRUCT_SIZE - 1
!loop:
    sta player_data,x
    dex
    bpl !loop-
    rts

// player_sync_to_zp — Copy hot fields from struct to ZP
// Called after loading a save or modifying the struct directly.
// Preserves: nothing
player_sync_to_zp:
    lda player_data + PL_MAP_X
    sta zp_player_x
    lda player_data + PL_MAP_Y
    sta zp_player_y
    lda player_data + PL_HP_LO
    sta zp_player_hp_lo
    lda player_data + PL_HP_HI
    sta zp_player_hp_hi
    lda player_data + PL_MHP_LO
    sta zp_player_mhp_lo
    lda player_data + PL_MHP_HI
    sta zp_player_mhp_hi
    lda player_data + PL_MANA
    sta zp_player_mp
    lda player_data + PL_MAX_MANA
    sta zp_player_mmp
    lda player_data + PL_LEVEL
    sta zp_player_lvl
    lda player_data + PL_DLEVEL
    sta zp_player_dlvl
    lda player_data + PL_AC
    sta zp_player_ac
    lda player_data + PL_STR_CUR
    sta zp_player_str
    lda player_data + PL_INT_CUR
    sta zp_player_int
    lda player_data + PL_WIS_CUR
    sta zp_player_wis
    lda player_data + PL_DEX_CUR
    sta zp_player_dex
    lda player_data + PL_CON_CUR
    sta zp_player_con
    lda player_data + PL_CHR_CUR
    sta zp_player_chr
    lda player_data + PL_RACE
    sta zp_player_race
    lda player_data + PL_CLASS
    sta zp_player_class
    lda player_data + PL_FOOD_LO
    sta zp_player_food
    lda player_data + PL_FOOD_HI
    sta zp_player_food_hi
    lda player_data + PL_LIGHT_RAD
    sta zp_light_radius
    rts

// player_sync_from_zp — Copy ZP hot fields back to struct
// Called before saving.
// Preserves: nothing
player_sync_from_zp:
    lda zp_player_x
    sta player_data + PL_MAP_X
    lda zp_player_y
    sta player_data + PL_MAP_Y
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    lda zp_player_mhp_hi
    sta player_data + PL_MHP_HI
    lda zp_player_mp
    sta player_data + PL_MANA
    lda zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda zp_player_lvl
    sta player_data + PL_LEVEL
    lda zp_player_dlvl
    sta player_data + PL_DLEVEL
    lda zp_player_ac
    sta player_data + PL_AC
    lda zp_player_food
    sta player_data + PL_FOOD_LO
    lda zp_player_food_hi
    sta player_data + PL_FOOD_HI
    rts

// player_calc_stats — Recalculate current stats from base + modifiers
// Applies race and class stat adjustments, clamps to 3–18.
// Preserves: nothing
player_calc_stats:
    // Get race offset into stat adj table
    lda player_data + PL_RACE
    // Multiply by 6 (STAT_COUNT)
    asl         // x2
    sta zp_temp0
    asl         // x4
    clc
    adc zp_temp0  // x4 + x2 = x6
    tax         // X = race * 6

    // Get class offset
    lda player_data + PL_CLASS
    asl
    sta zp_temp0
    asl
    clc
    adc zp_temp0
    sta zp_temp1  // zp_temp1 = class * 6

    // Process each stat
    ldy #0      // Stat index
!stat_loop:
    // Start with base stat
    lda player_data + PL_STR_BASE,y
    clc
    adc race_stat_adj,x     // Add race modifier (signed)
    clc
    stx zp_temp2            // Save race index
    ldx zp_temp1
    adc class_stat_adj,x    // Add class modifier (signed)
    ldx zp_temp2            // Restore race index

    // Clamp to 3–18 (handle signed underflow: negative wraps to 128+)
    bmi !clamp_low+         // Bit 7 set = negative result → clamp to 3
    cmp #3
    bcc !clamp_low+         // Below 3 → clamp to 3
    cmp #19
    bcc !store+             // 3–18 → keep
    lda #18                 // Above 18 → clamp to 18
    jmp !store+
!clamp_low:
    lda #3
!store:
    sta player_data + PL_STR_CUR,y

    inx         // Next race stat
    inc zp_temp1 // Next class stat
    iny
    cpy #STAT_COUNT
    bne !stat_loop-

    // Update to-hit and to-damage bonuses from stats
    jsr player_calc_combat
    rts

// player_calc_combat — Calculate combat bonuses from current stats
// Updates: PL_TOHIT, PL_TODMG, PL_AC (dex bonus portion), PL_BLOWS
// Preserves: nothing
player_calc_combat:
    // STR to-hit bonus
    lda player_data + PL_STR_CUR
    sec
    sbc #3                  // Index = stat - 3
    tax
    lda str_tohit_bonus,x
    sta zp_temp0            // Accumulate to-hit

    // DEX to-hit bonus
    lda player_data + PL_DEX_CUR
    sec
    sbc #3
    tax
    lda dex_tohit_bonus,x
    clc
    adc zp_temp0
    sta player_data + PL_TOHIT

    // STR damage bonus
    lda player_data + PL_STR_CUR
    sec
    sbc #3
    tax
    lda str_damage_bonus,x
    sta player_data + PL_TODMG

    // DEX AC bonus (signed: negative means worse AC)
    // AC starts at 0, DEX adds/subtracts. Clamp to min 0.
    lda player_data + PL_DEX_CUR
    sec
    sbc #3
    tax
    lda dex_ac_bonus,x
    bmi !ac_zero+           // Negative bonus → AC stays 0
    sta player_data + PL_AC
    jmp !ac_done+
!ac_zero:
    lda #0
    sta player_data + PL_AC
!ac_done:

    // Blows: simplified lookup
    // Weight class based on STR (higher STR = lighter effective weight)
    // For now, default to 1 blow until weapons are implemented
    lda #1
    sta player_data + PL_BLOWS

    rts

// player_calc_hp — Calculate max HP based on level, class HD, CON bonus
// Preserves: nothing
player_calc_hp:
    // Max HP = class_hit_die + (level-1) * (class_hit_die/2 + CON_bonus)
    // Simplified: at level 1, HP = hit die. Each level adds hit_die/2 + CON bonus.
    lda player_data + PL_CLASS
    tax
    // Get class properties — hp die is first byte
    lda #CLASS_PROP_SIZE
    jsr mul_x_by_a          // A = class * CLASS_PROP_SIZE
    tax
    lda class_properties,x  // Hit die
    sta zp_temp0            // Save hit die

    // CON HP bonus
    lda player_data + PL_CON_CUR
    sec
    sbc #3
    tax
    lda con_hp_bonus,x
    sta zp_temp1            // CON bonus per level

    // HP per level = hit_die/2 + CON bonus (min 1)
    lda zp_temp0
    lsr                     // hit_die / 2
    clc
    adc zp_temp1            // + CON bonus
    bpl !min_check+
    lda #1                  // Minimum 1 HP per level
!min_check:
    cmp #1
    bcs !ok+
    lda #1
!ok:
    sta zp_temp1            // HP per additional level

    // Total max HP = hit_die + (level-1) * hp_per_level
    lda player_data + PL_LEVEL
    sec
    sbc #1                  // level - 1
    tax
    lda zp_temp1            // HP per level
    jsr math_multiply       // result in zp_math_a (lo), zp_math_b (hi)
    lda zp_math_a
    clc
    adc zp_temp0            // + base hit die
    sta player_data + PL_MHP_LO
    lda zp_math_b
    adc #0
    sta player_data + PL_MHP_HI
    rts

// mul_x_by_a — Helper: multiply X by A, result in A
// Only works for small products (<256)
// Preserves: Y
mul_x_by_a:
    sta zp_temp3
    txa
    ldx zp_temp3
    jsr math_multiply
    lda zp_math_a
    rts

// player_get_stat_bonus — Get stat bonus for a given stat index and table
// Input: X = stat value (3–18), Y = bonus table offset
// Output: A = bonus value (signed)
// Table pointers are pre-set by caller.
player_get_stat_bonus:
    txa
    sec
    sbc #3                  // Index = stat - 3
    tax
    lda (zp_ptr0),y         // Read from bonus table
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Player struct size", PL_STRUCT_SIZE, 80
