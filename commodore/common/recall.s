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

// ============================================================
// Recall data arrays (260 bytes total, contiguous for save/load)
// ============================================================
.const RECALL_DATA_SIZE = MAX_CREATURES * 4

recall_data_start:
recall_kills:     .fill MAX_CREATURES, 0   // Times player killed this type
recall_deaths:    .fill MAX_CREATURES, 0   // Times this type killed player
recall_attacks:   .fill MAX_CREATURES, 0   // Attack rounds observed
recall_spells:    .fill MAX_CREATURES, 0   // Spell bitmask observed
recall_data_end:

// Compile-time validation
.assert "recall_data_size", recall_data_end - recall_data_start, RECALL_DATA_SIZE

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
    sta recall_kills,x
    sta recall_deaths,x
    sta recall_attacks,x
    sta recall_spells,x
    inx
    cpx #MAX_CREATURES
    bcc !rcl_loop-
    rts
