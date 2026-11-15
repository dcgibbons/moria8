#importonce
// recall_defs.s — Recall constants needed before platform placement.

#if HAL_PLATFORM_MONSTER_CATALOG
.const RECALL_COUNT     = 279
.const RECALL_DATA_SIZE = RECALL_COUNT * 4
#else
.const RECALL_DATA_SIZE = MAX_CREATURES * 4
#endif

.const RECALL_FIELD_KILLS   = 0
.const RECALL_FIELD_DEATHS  = 1
.const RECALL_FIELD_ATTACKS = 2
.const RECALL_FIELD_SPELLS  = 3
