#importonce
// player_magic_display_data.s — shared spell-display static data

// Keep display strings separate so C128 can place them outside the
// reloadable banked window when space gets tight.
pm_header_str:
    .text "   Name              Mana Lvl" ; .byte 0
pm_footer_cast_prefix:
    .text "Cast which? (a-" ; .byte 0
pm_footer_pray_prefix:
    .text "Pray which? (a-" ; .byte 0
pm_footer_learn_prefix:
    .text "Learn which? (a-" ; .byte 0
pm_footer_suffix:
    .text ", esc)" ; .byte 0
pm_title_mage_str:
    .text "Mage Book" ; .byte 0
pm_title_prayer_str:
    .text "Prayer Book" ; .byte 0
pm_title_learn_str:
    .text "Study" ; .byte 0
