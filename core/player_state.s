#importonce
// player_state.s — shared player layout and storage.
//
// Keep offsets and storage separate from player behavior so early platform
// bring-up code can seed shared state without importing player.s dependencies.

// ============================================================
// Player struct layout (offsets)
// ============================================================
.const PL_NAME      = 0    // 17 bytes: name (16 chars + null)
.const PL_RACE      = 17   // 1 byte: race index (0-7)
.const PL_CLASS     = 18   // 1 byte: class index (0-5)
.const PL_LEVEL     = 19   // 1 byte: player level (1-40)
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
.const PL_MAP_X     = 49   // Map X position
.const PL_MAP_Y     = 50   // Map Y position
// Food / hunger
.const PL_FOOD_LO   = 51   // Food counter (16-bit)
.const PL_FOOD_HI   = 52
.const PL_HUNGER    = 53   // Hunger state (0-3)
// Flags
.const PL_FLAGS     = 54   // Bit flags (see below)
.const PL_LIGHT_RAD = 55   // Light radius
.const PL_MAX_DLVL  = 56   // Deepest dungeon level reached
.const PL_AGE       = 57   // Character age
.const PL_HEIGHT    = 58   // Height (aesthetic)
.const PL_WEIGHT    = 59   // Weight (aesthetic)
.const PL_SPELL_TYPE = 60  // Spell type (0=none, 1=mage, 2=priest)
.const PL_SPELLS_LEARNT_0 = 61 // 32-bit learned mask (bits 0-30 used)
.const PL_SPELLS_LEARNT_1 = 62
.const PL_SPELLS_LEARNT_2 = 63
.const PL_SPELLS_LEARNT_3 = 64
.const PL_SPELLS_WORKED_0 = 65 // 32-bit worked/successfully-cast mask
.const PL_SPELLS_WORKED_1 = 66
.const PL_SPELLS_WORKED_2 = 67
.const PL_SPELLS_WORKED_3 = 68
.const PL_SPELLS_FORGOTTEN_0 = 69 // 32-bit forgotten mask
.const PL_SPELLS_FORGOTTEN_1 = 70
.const PL_SPELLS_FORGOTTEN_2 = 71
.const PL_SPELLS_FORGOTTEN_3 = 72
.const PL_NEW_SPELLS = 73     // Pending spells/prayers the player can learn
.const PL_SPELL_ORDER = 74    // 32 bytes: learn/remember/forget order; 99 = empty
.const PL_SPELL_ORDER_LAST = PL_SPELL_ORDER + 31
// Backward-compatible aliases used by older tests/helpers during the transition.
.const PL_SPELLS_KNOWN = PL_SPELLS_LEARNT_0
.const PL_SPELLS_KNOWN_HI = PL_SPELLS_LEARNT_1
// Experience factor (race_xp% + class_xp%, range 100-165)
.const PL_EXPFACT   = 106
// Reserved
.const PL_RESERVED  = 107   // Pseudo-ID timer
.const PL_SOCIAL_CLASS = 108 // 1 byte: social class (1-100)
.const PL_XP_FRAC_LO = 109  // Hidden fractional XP (16-bit fixed point)
.const PL_XP_FRAC_HI = 110
.const PL_STRUCT_SIZE = 111  // Total struct size

// Player flags
.const PLF_MALE     = $01
.const PLF_SEE_INV  = $02
.const PLF_FREE_ACT = $04
.const PLF_SLOW_DIG = $08
.const PLF_SEARCHING = $10
.const PLF_RESTING  = $20
.const PLAYER_SEARCH_FLAG_LIT = $08

// ============================================================
// Player struct storage
// ============================================================
player_data:
    .fill PL_STRUCT_SIZE, 0

// Player background text (4 lines x 40 bytes = 160 bytes)
// Populated during character creation, saved/loaded with game.
player_background:
    .fill 160, 0

.assert "Player struct size", PL_STRUCT_SIZE, 111
