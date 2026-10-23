#importonce
// store_data_defs.s — Store constants needed before platform placement.

.const STORE_MAX_ITEMS   = 12
.const STORE_TOTAL_SLOTS = 96   // 8 × 12
.const STORE_PICK_RETRIES = 30  // Max rejection sampling attempts
// VMS store_maint keep bounds (store$min_inven 14 / store$max_inven 20 of a
// 24-item store), scaled to STORE_MAX_ITEMS; store$turn_around is unscaled.
.const STORE_MIN_KEEP    = 7
.const STORE_MAX_KEEP    = 10
.const STORE_TURN_AROUND = 3
.assert "Store keep bounds fit the store", STORE_MIN_KEEP < STORE_MAX_KEEP && STORE_MAX_KEEP + 2 <= STORE_MAX_ITEMS, true
// store_restock_overlay.s marks "no slot" with $FF and tests slots with N.
.assert "Store slot indexes stay below $80", STORE_TOTAL_SLOTS <= $80, true
.const STORE_BM   = 6           // Black Market store index
.const STORE_HOME = 7           // Player Home store index
