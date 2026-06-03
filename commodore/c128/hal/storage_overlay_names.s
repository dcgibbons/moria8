#importonce
// C128 overlay asset filenames. PETSCII bytes for KERNAL LOAD.
//
// This file is imported into the C128 overlay-state area so the bytes stay in
// resident Bank 0 RAM without consuming the byte-tight Disk I/O payload.

hal_storage_overlay_start_name:
    .byte $31,$32,$38,$2e,$53,$54,$41,$52,$54   // "128.START"
.label hal_storage_overlay_start_name_len = * - hal_storage_overlay_start_name
    .byte 0
hal_storage_overlay_town_name:
    .byte $31,$32,$38,$2e,$54,$4f,$57,$4e       // "128.TOWN"
.label hal_storage_overlay_town_name_len = * - hal_storage_overlay_town_name
    .byte 0
hal_storage_overlay_death_name:
    .byte $31,$32,$38,$2e,$44,$45,$41,$54,$48   // "128.DEATH"
.label hal_storage_overlay_death_name_len = * - hal_storage_overlay_death_name
    .byte 0
hal_storage_overlay_gen_name:
    .byte $31,$32,$38,$2e,$47,$45,$4e           // "128.GEN"
.label hal_storage_overlay_gen_name_len = * - hal_storage_overlay_gen_name
    .byte 0
hal_storage_overlay_help_name:
    .byte $31,$32,$38,$2e,$48,$45,$4c,$50       // "128.HELP"
.label hal_storage_overlay_help_name_len = * - hal_storage_overlay_help_name
    .byte 0
hal_storage_overlay_ui_name:
    .byte $31,$32,$38,$2e,$55,$49               // "128.UI"
.label hal_storage_overlay_ui_name_len = * - hal_storage_overlay_ui_name
    .byte 0
hal_storage_overlay_items_name:
    .byte $31,$32,$38,$2e,$49,$54,$45,$4d,$53   // "128.ITEMS"
.label hal_storage_overlay_items_name_len = * - hal_storage_overlay_items_name
    .byte 0
hal_storage_overlay_disarm_name:
    .byte $31,$32,$38,$2e,$44,$49,$53,$41,$52,$4d // "128.DISARM"
.label hal_storage_overlay_disarm_name_len = * - hal_storage_overlay_disarm_name
    .byte 0
hal_storage_royal_name:
    .byte $31,$32,$38,$2e,$52,$4f,$59,$41,$4c   // "128.ROYAL"
.label hal_storage_royal_name_len = * - hal_storage_royal_name
    .byte 0

hal_storage_overlay_name_lo:
    .byte <hal_storage_overlay_start_name, <hal_storage_overlay_town_name, <hal_storage_overlay_death_name, <hal_storage_overlay_gen_name, <hal_storage_overlay_help_name, <hal_storage_overlay_ui_name, <hal_storage_overlay_items_name, <hal_storage_overlay_disarm_name
hal_storage_overlay_name_hi:
    .byte >hal_storage_overlay_start_name, >hal_storage_overlay_town_name, >hal_storage_overlay_death_name, >hal_storage_overlay_gen_name, >hal_storage_overlay_help_name, >hal_storage_overlay_ui_name, >hal_storage_overlay_items_name, >hal_storage_overlay_disarm_name
hal_storage_overlay_name_len:
    .byte hal_storage_overlay_start_name_len, hal_storage_overlay_town_name_len, hal_storage_overlay_death_name_len, hal_storage_overlay_gen_name_len, hal_storage_overlay_help_name_len, hal_storage_overlay_ui_name_len, hal_storage_overlay_items_name_len, hal_storage_overlay_disarm_name_len
