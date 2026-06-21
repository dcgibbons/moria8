#importonce
// player_items.s — Equip, Remove, Eat, and equipment recalculation
//
// Phase 6.3: Player item interaction routines.
// item_wear: equip an item from carried inventory
// item_takeoff: remove an equipped item back to carried inventory
// item_eat: eat food from inventory
// player_recalc_equipment: recalculate AC/combat after equip changes

#import "ui_restore.s"
#import "input_ui_helpers.s"
#import "player_heal_feedback.s"
#import "player_item_select.s"

#import "player_food_consts.s"

#import "player_item_prompt.s"

// Wear/takeoff/eat/quaff command bodies live separately so C128 can
// place the callable code outside the I/O hole.
#if !PLAYER_ITEM_COMMANDS_EXTERNAL
    #import "player_item_commands.s"
#endif

// ============================================================
// Low-frequency item actions — resident in tests, overlay-owned in product
// builds to keep the main image below the C64/C128 layout ceilings.
// ============================================================
#if !ITEM_ACTIONS_OVERLAY_EXTERNAL
    #import "item_actions_overlay.s"
#endif

// Strings migrated to Huffman compression (HSTR_PIW_*, HSTR_PIQ_* in huffman_data.s)

// ============================================================
// item_gain_spell — Study a spell book to learn qualifying spells
// Books are not consumed.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================
