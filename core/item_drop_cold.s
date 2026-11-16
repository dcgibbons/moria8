#importonce
// item_drop_cold.s — Prompted inventory drop ('d') command handler (S4)
//
// Module ownership:
//   owner: HelpOverlay / TitleOverlay / DeathOverlay when ITEM_DROP_EXTERNAL
//     is defined; Default resident otherwise (imported by core/item.s).
//   lifetime: one discrete player 'd' command.
//   callers: cmd_drop in core/game_loop.s (via tramp_item_drop when external).
//     Pressing '?' sets piw_return_overlay = current_overlay so
//     show_inv_and_select reloads the caller overlay before returning.

// item_drop — Drop a carried item to the floor (prompted)
// Prompts "Drop which item (a-v)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = no action
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0-4
item_drop:
    :ItemDropBody()
