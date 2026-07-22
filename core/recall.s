#importonce
// recall.s — Monster recall data structures and tracking
//
// Per-creature-type counters for the monster recall system (R7.7).
// 4 SoA arrays x MAX_CREATURES entries, laid out contiguously
// for efficient save/load via a single block.
//
// Arrays:
//   recall_kills   — times player killed this creature type
//   recall_deaths  — times this creature type killed the player
//   recall_attacks — attack rounds observed (reveals attack info)
//   recall_spells  — bitmask of spells observed (bits 0-6)
//
// Hooks in: combat.s, monster_attack.s, monster_magic.s
// Persistence: save.s (single contiguous block)

#importonce

#import "recall_defs.s"

#if !RECALL_ARRAY_DATA_EXTERNAL
#import "recall_array_data.s"
#endif

// Spell bit lookup table (7 entries, indexed by spell position 0-6)
recall_spell_bit:
    .byte 1, 2, 4, 8, 16, 32, 64

// ============================================================
// recall_clear — Zero all recall data
// Called when explicitly resetting monster knowledge.
// (Not called on new character — umoria preserves recall
// across deaths as meta-game knowledge.)
// Clobbers: A, X
// ============================================================
recall_clear:
    lda #0
    ldx #0
!rcl_loop:
    :AuxWriteX(recall_kills)
    :AuxWriteX(recall_deaths)
    :AuxWriteX(recall_attacks)
    :AuxWriteX(recall_spells)
    inx
    cpx #MAX_CREATURES
    bcc !rcl_loop-
    rts
