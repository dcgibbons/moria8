#importonce
// recall_array_data.s — Mutable monster-recall counters.
//
// Kept separate so a platform may place the contiguous block in data-only
// memory while recall_clear and recall_spell_bit remain executable/readable.

recall_data_start:
recall_kills:     .fill MAX_CREATURES, 0   // Times player killed this type
recall_deaths:    .fill MAX_CREATURES, 0   // Times this type killed player
recall_attacks:   .fill MAX_CREATURES, 0   // Attack rounds observed
recall_spells:    .fill MAX_CREATURES, 0   // Spell bitmask observed
recall_data_end:

.assert "recall_data_size", recall_data_end - recall_data_start, RECALL_DATA_SIZE
