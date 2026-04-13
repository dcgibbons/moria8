#importonce
// runtime_ui_strings.s — Shared runtime UI strings that must stay in normal RAM
//
// These strings are dereferenced directly during title/load/disk menu flows.
// On C128 they must not drift into the $D000 I/O hole.

.encoding "screencode_mixed"

save_saving_str:
#if !C128
    .text "Saving..." ; .byte 0
#else
    .text "Saving game..." ; .byte 0
#endif
save_done_str:
#if !C128
    .text "Saved." ; .byte 0
#else
    .text "Game saved." ; .byte 0
#endif
save_load_str:
#if !C128
    .text "Loading..." ; .byte 0
#else
    .text "Loading game..." ; .byte 0
#endif
save_notfound_str:
#if !C128
    .text "No save." ; .byte 0
#else
    .text "Save file not found." ; .byte 0
#endif
save_corrupt_str:
#if !C128
    .text "Bad save!" ; .byte 0
#else
    .text "Save file corrupt!" ; .byte 0
#endif
save_ioerr_str:
#if !C128
    .text "I/O err." ; .byte 0
#else
    .text "Disk error!" ; .byte 0
#endif
save_overwrite_str:
    .text "Overwrite? Y/N" ; .byte 0
save_welcome_str:
#if !C128
    .text "Welcome." ; .byte 0
#else
    .text "Welcome back." ; .byte 0
#endif
title_menu_str:
    .text "N)ew  L)oad  D)isk Setup" ; .byte 0

ds_save_str:       .text "Insert save disk" ; .byte 0
ds_game_str:       .text "Insert program disk" ; .byte 0
ds_ind_pfx:        .text "[Save: " ; .byte 0
disk_need_save_str:
#if !C128
    .text "Need save." ; .byte 0
#else
    .text "Need Save Disk." ; .byte 0
#endif
disk_bad_save_str:
#if !C128
    .text "Bad save." ; .byte 0
#else
    .text "Wrong Save Disk." ; .byte 0
#endif
