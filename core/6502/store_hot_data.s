#importonce
// store_hot_data.s — Small store state used from multiple overlays.

hg_kicked:      .fill 8, 0                    // Resets on town re-entry

// Base index into SoA arrays for each store (store * STORE_MAX_ITEMS).
store_base_idx:
    .fill 8, i * STORE_MAX_ITEMS
