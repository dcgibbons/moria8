#importonce
// recall_array_data.s — Mutable monster-recall counters.
//
// Kept separate so a platform may place the contiguous block in data-only
// memory while recall_spell_bit remains readable.

#if HAL_PLATFORM_MONSTER_CATALOG
// Interleaved [kills, deaths, attacks, spells] per catalog species (0..278).
recall_data_start:
    .fill RECALL_DATA_SIZE, 0
recall_data_end:

.assert "recall_data_size", recall_data_end - recall_data_start, RECALL_DATA_SIZE
#else
recall_data_start:
recall_kills:     .fill MAX_CREATURES, 0   // Times player killed this type
recall_deaths:    .fill MAX_CREATURES, 0   // Times this type killed player
recall_attacks:   .fill MAX_CREATURES, 0   // Attack rounds observed
recall_spells:    .fill MAX_CREATURES, 0   // Spell bitmask observed
recall_data_end:

.assert "recall_data_size", recall_data_end - recall_data_start, RECALL_DATA_SIZE
#endif
