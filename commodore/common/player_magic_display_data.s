#importonce
// player_magic_display_data.s — shared spell-display static data

// Keep display strings separate so C128 can place them outside the
// reloadable banked window when space gets tight.
pm_header_str:
    .text "   Name              Mana Lvl" ; .byte 0
