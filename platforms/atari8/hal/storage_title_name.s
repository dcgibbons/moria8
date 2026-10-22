#importonce
// Atari 8-bit title-art DOS 2.5 8.3 filename ("TITLE.DAT").

hal_storage_title_name:
    .byte $54,$49,$54,$4c,$45,$2e,$44,$41,$54   // "TITLE.DAT"
.label hal_storage_title_name_len = * - hal_storage_title_name
