#importonce
// store_data_defs.s — Store constants needed before platform placement.

.const STORE_MAX_ITEMS   = 12
.const STORE_TOTAL_SLOTS = 96   // 8 × 12
.const STORE_PICK_RETRIES = 30  // Max rejection sampling attempts
.const STORE_BM   = 6           // Black Market store index
.const STORE_HOME = 7           // Player Home store index
