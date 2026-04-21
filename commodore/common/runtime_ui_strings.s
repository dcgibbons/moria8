#importonce
// runtime_ui_strings.s — Shared runtime UI strings that must stay in normal RAM
//
// These strings are dereferenced directly during title/load/disk menu flows.
// On C128 they must not drift into the $D000 I/O hole.

.encoding "screencode_mixed"

// Save/load status and feedback messages now live in huffman_data.s so the
// resident runtime image does not carry duplicate raw text.
title_menu_str:
    .text "N)ew  L)oad  D)isk Setup" ; .byte 0

ds_save_str:       .text "Insert save disk" ; .byte 0
ds_game_str:       .text "Insert program disk" ; .byte 0
ds_ind_pfx:        .text "[Save: " ; .byte 0
