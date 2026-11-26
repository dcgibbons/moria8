#importonce
// store_inventory_data.s — Persistent store inventory arrays.
//
// Kept separate so platforms may place the contiguous block in a data-only
// bank without also moving store helper code or directly-read lookup tables.

// Struct-of-arrays: eight STORE_TOTAL_SLOTS-byte tables, contiguous for save/load dispatch.
si_item_id:     .fill STORE_TOTAL_SLOTS, $FF   // $FF = empty
si_qty:         .fill STORE_TOTAL_SLOTS, 0
si_p1:          .fill STORE_TOTAL_SLOTS, 0
si_to_hit:      .fill STORE_TOTAL_SLOTS, 0
si_to_dam:      .fill STORE_TOTAL_SLOTS, 0
si_to_ac:       .fill STORE_TOTAL_SLOTS, 0
si_meta:        .fill STORE_TOTAL_SLOTS, 0     // bits 0-3 flags
si_meta_hi:     .fill STORE_TOTAL_SLOTS, 0     // bit 6 ITEM_PAGE_BIT, bits 0-5 ego ID

.label store_inventory_data_end = si_meta_hi + STORE_TOTAL_SLOTS
.assert "Store inventory arrays stay contiguous", store_inventory_data_end - si_item_id, STORE_TOTAL_SLOTS * 8
