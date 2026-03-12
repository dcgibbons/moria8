// runtime_ui_strings.s — Shared runtime UI strings that must stay in normal RAM
//
// These strings are dereferenced directly during title/load/disk menu flows.
// On C128 they must not drift into the $D000 I/O hole.

.encoding "screencode_mixed"

save_saving_str:
    .text "Saving game..." ; .byte 0
save_done_str:
    .text "Game saved." ; .byte 0
save_load_str:
    .text "Loading game..." ; .byte 0
save_notfound_str:
    .text "Save file not found." ; .byte 0
save_corrupt_str:
    .text "Save file corrupt!" ; .byte 0
save_ioerr_str:
    .text "Disk error!" ; .byte 0
save_welcome_str:
    .text "Welcome back to Moria8!" ; .byte 0
title_menu_str:
    .text "N)ew  L)oad  D)ual Disk" ; .byte 0

ds_save_str:    .text "Insert save disk" ; .byte 0
ds_game_str:    .text "Insert game disk" ; .byte 0
ds_dual_str:    .text "[Save Disk]" ; .byte 0
ds_menu_str:    .text "S)ame W)swap #)Drive #" ; .byte 0
de_prompt_str:  .text "Save drive (8-30): " ; .byte 0
de_ind_pfx:     .text "[Drive " ; .byte 0
de_nodev_str:   .text "Drive not found!" ; .byte 0
