#importonce
// Atari 8-bit storage HAL adapter and canonical asset/save filename tables.

#import "storage_policy.s"
#import "storage_title_name.s"

// Platform-owned save-disk marker filenames and marker bytes.
hal_storage_init_command:
    .byte $49, $30                              // "I0"

hal_storage_marker_magic:
    .byte $4d, $38, $53, $41, $56, $45          // "M8SAVE"
.label hal_storage_marker_magic_len = * - hal_storage_marker_magic

hal_storage_marker_read_name:
    .byte $30, $3a                              // "0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_marker_read_name_len = * - hal_storage_marker_read_name

hal_storage_marker_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_marker_write_name_len = * - hal_storage_marker_write_name

hal_storage_marker_scratch_name:
    .byte $53, $30, $3a                         // "S0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
.label hal_storage_marker_scratch_name_len = * - hal_storage_marker_scratch_name

// Canonical HAL save-record filenames (patched by save_slot_menu.s and mapped
// at open time by save_stream.s to SAVE0.SAV..SAVE3.SAV).
hal_storage_save_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45 // "THE.GAME"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_save_write_name_len = * - hal_storage_save_write_name
    .byte $57                                   // spare suffix byte for "THE.GAME2"
.label hal_storage_save_probe_name = hal_storage_save_write_name + 1
.label hal_storage_save_probe_name_len = hal_storage_save_write_name_len - 1

hal_storage_save_read_name:
    .byte $30, $3a                              // "0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45 // "THE.GAME"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_save_read_name_len = * - hal_storage_save_read_name
    .byte $52                                   // spare suffix byte for "THE.GAME2"

// Canonical HAL high-score filenames (mapped at open time to HISCORE.DAT).
hal_storage_score_read_name:
    .byte $30, $3a                              // "0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45 // "HALL.OF.FAME"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_score_read_name_len = * - hal_storage_score_read_name

hal_storage_score_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45 // "HALL.OF.FAME"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_score_write_name_len = * - hal_storage_score_write_name

hal_storage_score_scratch_name:
    .byte $53, $30, $3a                         // "S0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45 // "HALL.OF.FAME"
.label hal_storage_score_scratch_name_len = * - hal_storage_score_scratch_name

// Platform-owned tier data 8.3 filenames ("MONSTER.DB1".."MONSTER.DB4").
hal_storage_tier_1_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$31 // "MONSTER.DB1"
.label hal_storage_tier_1_name_len = * - hal_storage_tier_1_name
    .byte 0
hal_storage_tier_2_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$32 // "MONSTER.DB2"
.label hal_storage_tier_2_name_len = * - hal_storage_tier_2_name
    .byte 0
hal_storage_tier_3_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$33 // "MONSTER.DB3"
.label hal_storage_tier_3_name_len = * - hal_storage_tier_3_name
    .byte 0
hal_storage_tier_4_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$34 // "MONSTER.DB4"
.label hal_storage_tier_4_name_len = * - hal_storage_tier_4_name
    .byte 0

hal_storage_tier_name_lo:
    .byte <hal_storage_tier_1_name, <hal_storage_tier_2_name, <hal_storage_tier_3_name, <hal_storage_tier_4_name
hal_storage_tier_name_hi:
    .byte >hal_storage_tier_1_name, >hal_storage_tier_2_name, >hal_storage_tier_3_name, >hal_storage_tier_4_name
hal_storage_tier_name_len:
    .byte hal_storage_tier_1_name_len, hal_storage_tier_2_name_len, hal_storage_tier_3_name_len, hal_storage_tier_4_name_len

// Platform-owned overlay asset 8.3 filenames ("OVL.STA".."OVL.CHS").
hal_storage_overlay_start_name:
    .byte $4f,$56,$4c,$2e,$53,$54,$41           // "OVL.STA"
.label hal_storage_overlay_start_name_len = * - hal_storage_overlay_start_name
    .byte 0
hal_storage_overlay_town_name:
    .byte $4f,$56,$4c,$2e,$54,$57,$4e           // "OVL.TWN"
.label hal_storage_overlay_town_name_len = * - hal_storage_overlay_town_name
    .byte 0
hal_storage_overlay_death_name:
    .byte $4f,$56,$4c,$2e,$44,$54,$48           // "OVL.DTH"
.label hal_storage_overlay_death_name_len = * - hal_storage_overlay_death_name
    .byte 0
hal_storage_overlay_gen_name:
    .byte $4f,$56,$4c,$2e,$47,$45,$4e           // "OVL.GEN"
.label hal_storage_overlay_gen_name_len = * - hal_storage_overlay_gen_name
    .byte 0
hal_storage_overlay_help_name:
    .byte $4f,$56,$4c,$2e,$48,$4c,$50           // "OVL.HLP"
.label hal_storage_overlay_help_name_len = * - hal_storage_overlay_help_name
    .byte 0
hal_storage_overlay_ui_name:
    .byte $4f,$56,$4c,$2e,$55,$49               // "OVL.UI"
.label hal_storage_overlay_ui_name_len = * - hal_storage_overlay_ui_name
    .byte 0
hal_storage_overlay_items_name:
    .byte $4f,$56,$4c,$2e,$49,$54,$4d           // "OVL.ITM"
.label hal_storage_overlay_items_name_len = * - hal_storage_overlay_items_name
    .byte 0
hal_storage_overlay_spell_name:
    .byte $4f,$56,$4c,$2e,$53,$50,$4c           // "OVL.SPL"
.label hal_storage_overlay_spell_name_len = * - hal_storage_overlay_spell_name
    .byte 0
hal_storage_overlay_modal_misc_name:
hal_storage_modal_misc_name:
    .byte $4f,$56,$4c,$2e,$4d,$44,$4c           // "OVL.MDL"
.label hal_storage_overlay_modal_misc_name_len = * - hal_storage_overlay_modal_misc_name
.label hal_storage_modal_misc_name_len = hal_storage_overlay_modal_misc_name_len
    .byte 0
hal_storage_overlay_chest_name:
    .byte $4f,$56,$4c,$2e,$43,$48,$53           // "OVL.CHS"
.label hal_storage_overlay_chest_name_len = * - hal_storage_overlay_chest_name
    .byte 0

hal_storage_overlay_name_lo:
    .byte <hal_storage_overlay_start_name, <hal_storage_overlay_town_name, <hal_storage_overlay_death_name, <hal_storage_overlay_gen_name, <hal_storage_overlay_help_name, <hal_storage_overlay_ui_name, <hal_storage_overlay_items_name, <hal_storage_overlay_spell_name, <hal_storage_modal_misc_name, <hal_storage_overlay_chest_name
hal_storage_overlay_name_hi:
    .byte >hal_storage_overlay_start_name, >hal_storage_overlay_town_name, >hal_storage_overlay_death_name, >hal_storage_overlay_gen_name, >hal_storage_overlay_help_name, >hal_storage_overlay_ui_name, >hal_storage_overlay_items_name, >hal_storage_overlay_spell_name, >hal_storage_modal_misc_name, >hal_storage_overlay_chest_name
hal_storage_overlay_name_len:
    .byte hal_storage_overlay_start_name_len, hal_storage_overlay_town_name_len, hal_storage_overlay_death_name_len, hal_storage_overlay_gen_name_len, hal_storage_overlay_help_name_len, hal_storage_overlay_ui_name_len, hal_storage_overlay_items_name_len, hal_storage_overlay_spell_name_len, hal_storage_modal_misc_name_len, hal_storage_overlay_chest_name_len
