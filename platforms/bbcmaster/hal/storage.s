#importonce
// BBC Master 128 storage HAL filename tables (7-char Acorn DFS basenames).

#import "storage_policy.s"

// Commodore drive-init command (unused on DFS; exported for contract).
hal_storage_init_command:
    .byte $49, $30                              // "I0"

// Save-disk marker magic and canonical HAL filenames (mapped to MORIAID on DFS).
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
// at open time by storage.s to SAVE0..SAVE3 on the selected DFS drive).
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

// Canonical HAL high-score filenames (mapped at open time to HISCORE on DFS).
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

// Program-media probe file on the game disk ("TITLE", 5 chars).
hal_storage_program_probe_name:
    .byte $54, $49, $54, $4c, $45               // "TITLE"
.label hal_storage_program_probe_name_len = * - hal_storage_program_probe_name
    .byte 0

// Title-art asset name ("TITLE", 5 chars).
hal_storage_title_name:
    .byte $54, $49, $54, $4c, $45               // "TITLE"
.label hal_storage_title_name_len = * - hal_storage_title_name
    .byte 0

// Tier data filenames (<= 7 chars for Acorn DFS: "MONDB1".."MONDB4").
hal_storage_tier_1_name:
    .byte $4d,$4f,$4e,$44,$42,$31               // "MONDB1"
.label hal_storage_tier_1_name_len = * - hal_storage_tier_1_name
    .byte 0
hal_storage_tier_2_name:
    .byte $4d,$4f,$4e,$44,$42,$32               // "MONDB2"
.label hal_storage_tier_2_name_len = * - hal_storage_tier_2_name
    .byte 0
hal_storage_tier_3_name:
    .byte $4d,$4f,$4e,$44,$42,$33               // "MONDB3"
.label hal_storage_tier_3_name_len = * - hal_storage_tier_3_name
    .byte 0
hal_storage_tier_4_name:
    .byte $4d,$4f,$4e,$44,$42,$34               // "MONDB4"
.label hal_storage_tier_4_name_len = * - hal_storage_tier_4_name
    .byte 0

hal_storage_tier_name_lo:
    .byte <hal_storage_tier_1_name, <hal_storage_tier_2_name, <hal_storage_tier_3_name, <hal_storage_tier_4_name
hal_storage_tier_name_hi:
    .byte >hal_storage_tier_1_name, >hal_storage_tier_2_name, >hal_storage_tier_3_name, >hal_storage_tier_4_name
hal_storage_tier_name_len:
    .byte hal_storage_tier_1_name_len, hal_storage_tier_2_name_len, hal_storage_tier_3_name_len, hal_storage_tier_4_name_len

// Overlay asset filenames (<= 7 chars for Acorn DFS: "OVLSTA".."OVLTTL").
hal_storage_overlay_start_name:
    .byte $4f,$56,$4c,$53,$54,$41               // "OVLSTA"
.label hal_storage_overlay_start_name_len = * - hal_storage_overlay_start_name
    .byte 0
hal_storage_overlay_town_name:
    .byte $4f,$56,$4c,$54,$57,$4e               // "OVLTWN"
.label hal_storage_overlay_town_name_len = * - hal_storage_overlay_town_name
    .byte 0
hal_storage_overlay_death_name:
    .byte $4f,$56,$4c,$44,$54,$48               // "OVLDTH"
.label hal_storage_overlay_death_name_len = * - hal_storage_overlay_death_name
    .byte 0
hal_storage_overlay_gen_name:
    .byte $4f,$56,$4c,$47,$45,$4e               // "OVLGEN"
.label hal_storage_overlay_gen_name_len = * - hal_storage_overlay_gen_name
    .byte 0
hal_storage_overlay_help_name:
    .byte $4f,$56,$4c,$48,$4c,$50               // "OVLHLP"
.label hal_storage_overlay_help_name_len = * - hal_storage_overlay_help_name
    .byte 0
hal_storage_overlay_ui_name:
    .byte $4f,$56,$4c,$55,$49                   // "OVLUI"
.label hal_storage_overlay_ui_name_len = * - hal_storage_overlay_ui_name
    .byte 0
hal_storage_overlay_items_name:
    .byte $4f,$56,$4c,$49,$54,$4d               // "OVLITM"
.label hal_storage_overlay_items_name_len = * - hal_storage_overlay_items_name
    .byte 0
hal_storage_overlay_spell_name:
    .byte $4f,$56,$4c,$53,$50,$4c               // "OVLSPL"
.label hal_storage_overlay_spell_name_len = * - hal_storage_overlay_spell_name
    .byte 0
hal_storage_overlay_modal_misc_name:
    .byte $4f,$56,$4c,$4d,$44,$4c               // "OVLMDL"
.label hal_storage_overlay_modal_misc_name_len = * - hal_storage_overlay_modal_misc_name
    .byte 0
.label hal_storage_modal_misc_name = hal_storage_overlay_modal_misc_name
.label hal_storage_modal_misc_name_len = hal_storage_overlay_modal_misc_name_len
hal_storage_overlay_chest_name:
    .byte $4f,$56,$4c,$43,$48,$53               // "OVLCHS"
.label hal_storage_overlay_chest_name_len = * - hal_storage_overlay_chest_name
    .byte 0
hal_storage_overlay_storage_name:
    .byte $4f,$56,$4c,$53,$54,$4f               // "OVLSTO"
.label hal_storage_overlay_storage_name_len = * - hal_storage_overlay_storage_name
    .byte 0
hal_storage_overlay_title_name:
    .byte $4f,$56,$4c,$54,$54,$4c               // "OVLTTL"
.label hal_storage_overlay_title_name_len = * - hal_storage_overlay_title_name
    .byte 0

hal_storage_overlay_name_lo:
    .byte <hal_storage_overlay_start_name, <hal_storage_overlay_town_name, <hal_storage_overlay_death_name, <hal_storage_overlay_gen_name, <hal_storage_overlay_help_name, <hal_storage_overlay_ui_name, <hal_storage_overlay_items_name, <hal_storage_overlay_spell_name, <hal_storage_modal_misc_name, <hal_storage_overlay_chest_name, <hal_storage_overlay_storage_name, <hal_storage_overlay_title_name
hal_storage_overlay_name_hi:
    .byte >hal_storage_overlay_start_name, >hal_storage_overlay_town_name, >hal_storage_overlay_death_name, >hal_storage_overlay_gen_name, >hal_storage_overlay_help_name, >hal_storage_overlay_ui_name, >hal_storage_overlay_items_name, >hal_storage_overlay_spell_name, >hal_storage_modal_misc_name, >hal_storage_overlay_chest_name, >hal_storage_overlay_storage_name, >hal_storage_overlay_title_name
hal_storage_overlay_name_len:
    .byte hal_storage_overlay_start_name_len, hal_storage_overlay_town_name_len, hal_storage_overlay_death_name_len, hal_storage_overlay_gen_name_len, hal_storage_overlay_help_name_len, hal_storage_overlay_ui_name_len, hal_storage_overlay_items_name_len, hal_storage_overlay_spell_name_len, hal_storage_modal_misc_name_len, hal_storage_overlay_chest_name_len, hal_storage_overlay_storage_name_len, hal_storage_overlay_title_name_len

.const BEEB_OVERLAY_TABLE_COUNT = * - hal_storage_overlay_name_len
.assert "Overlay table matches hal_platform_overlay_count", BEEB_OVERLAY_TABLE_COUNT, hal_platform_overlay_count
.assert "Save read name keeps slot-menu digit offset 10", hal_storage_save_read_name_len - 4, 10
.assert "Save write name keeps slot-menu digit offset 11", hal_storage_save_write_name_len - 4, 11
.assert "Probe filename tracks write filename without overwrite marker", hal_storage_save_probe_name_len, hal_storage_save_write_name_len - 1
.assert "Marker magic is 6 bytes", hal_storage_marker_magic_len, 6
