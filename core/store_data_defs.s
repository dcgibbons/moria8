#importonce
// store_data_defs.s — Store constants needed before platform placement.

.const STORE_MAX_ITEMS   = 16
.const STORE_TOTAL_SLOTS = 128  // 8 × 16
// The store screen lists the items on rows 3 on, then the menu and gold row
// (ui_store.s, ui_home.s); messages use rows 20-23.
.const STORE_MENU_ROW    = 3 + STORE_MAX_ITEMS
.assert "The store menu row sits above the message rows", STORE_MENU_ROW, 19
.const STORE_PICK_RETRIES = 30  // Max rejection sampling attempts
// VMS store_maint keep bounds, unscaled: store$min_inven 14 / store$max_inven
// 20 (constants.inc), with store$turn_around. Scaled to the store (9/13 of
// 16), the General Store, whose few kinds stack, drew half as much stock: a
// lantern was in on 15% of town visits, 31% at VMS's bounds (2026-11-09).
// With 16 slots a store never passes 20, so stocking stops when it is full.
.const STORE_MIN_KEEP    = 14
.const STORE_MAX_KEEP    = 20
.const STORE_TURN_AROUND = 3
// Umoria storeCarryItem caps a store stack at 24.
.const STORE_STACK_MAX   = 24
.assert "Store keep bounds are ordered", STORE_MIN_KEEP < STORE_MAX_KEEP, true
// A full store must reach the turnover branch, or its stock never changes.
.assert "A full store reaches the keep minimum", STORE_MIN_KEEP <= STORE_MAX_ITEMS, true
// store_restock_overlay.s marks "no slot" with $FF and tests slots with N.
.assert "Store slot indexes stay below $80", STORE_TOTAL_SLOTS <= $80, true
.const STORE_BM   = 6           // Black Market store index
.const STORE_HOME = 7           // Player Home store index
