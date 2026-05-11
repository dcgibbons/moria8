#importonce
// C128 tier data filenames. PETSCII bytes for KERNAL LOAD.
//
// This file is imported into resident main RAM next to C128 cache/overlay
// metadata so the bytes are visible to KERNAL LOAD without growing the
// byte-tight Disk I/O resident payload.

hal_storage_tier_1_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$2e,$31 // "MONSTER.DB.1"
.label hal_storage_tier_1_name_len = * - hal_storage_tier_1_name
    .byte 0
hal_storage_tier_2_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$2e,$32 // "MONSTER.DB.2"
.label hal_storage_tier_2_name_len = * - hal_storage_tier_2_name
    .byte 0
hal_storage_tier_3_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$2e,$33 // "MONSTER.DB.3"
.label hal_storage_tier_3_name_len = * - hal_storage_tier_3_name
    .byte 0
hal_storage_tier_4_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$2e,$34 // "MONSTER.DB.4"
.label hal_storage_tier_4_name_len = * - hal_storage_tier_4_name
    .byte 0

hal_storage_tier_name_lo:
    .byte <hal_storage_tier_1_name, <hal_storage_tier_2_name, <hal_storage_tier_3_name, <hal_storage_tier_4_name
hal_storage_tier_name_hi:
    .byte >hal_storage_tier_1_name, >hal_storage_tier_2_name, >hal_storage_tier_3_name, >hal_storage_tier_4_name
hal_storage_tier_name_len:
    .byte hal_storage_tier_1_name_len, hal_storage_tier_2_name_len, hal_storage_tier_3_name_len, hal_storage_tier_4_name_len
