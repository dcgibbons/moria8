#importonce
// runtime_ui_strings.s — Shared runtime UI strings that must stay in normal RAM
//
// These strings are dereferenced directly during title/load/disk menu flows.
// On C128 they must not drift into the $D000 I/O hole.

.encoding "screencode_mixed"

// Save/load status and feedback messages now live in huffman_data.s so the
// resident runtime image does not carry duplicate raw text.
// Each port centres it from its length (title_menu_str_end - title_menu_str):
// the A)bout entry grew it from 24 to 32 characters, and a hard-coded 35 left
// it off centre on every port (2026-11-12).
title_menu_str:
#if HAL_PLATFORM_LEGAL_VIEWER
    .text "N)ew  L)oad  D)isk Setup  A)bout"
#else
    .text "N)ew  L)oad  D)isk Setup"
#endif
title_menu_str_end:
    .byte 0
.assert "Title menu fits the screen", title_menu_str_end - title_menu_str <= SCREEN_COLS, true

ds_save_str:       .text "Insert save disk" ; .byte 0
ds_game_str:       .text "Insert program disk" ; .byte 0
ds_ind_pfx:        .text "[Save: " ; .byte 0
