#importonce
// item_state.s — shared inventory/equipment storage.
//
// Keep the inventory arrays separate from item behavior so early platform
// bring-up can use real equipment state without importing floor-item logic.

inv_item_id: .fill TOTAL_INV_SLOTS, FI_EMPTY
inv_qty:     .fill TOTAL_INV_SLOTS, 0
inv_p1:      .fill TOTAL_INV_SLOTS, 0
inv_to_hit:  .fill TOTAL_INV_SLOTS, 0
inv_to_dam:  .fill TOTAL_INV_SLOTS, 0
inv_to_ac:   .fill TOTAL_INV_SLOTS, 0
inv_flags:   .fill TOTAL_INV_SLOTS, 0
inv_ego:     .fill TOTAL_INV_SLOTS, 0
