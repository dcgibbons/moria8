#importonce
// store_hot_data.s — Small store state used from multiple overlays.

hg_kicked:      .fill 8, 0                    // Resets on town re-entry

// Base index into SoA arrays for each store (store * 12).
store_base_idx:
    .byte 0, 12, 24, 36, 48, 60, 72, 84
