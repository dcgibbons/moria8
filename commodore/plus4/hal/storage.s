#importonce
// Plus/4 storage HAL adapter.
//
// Zero-byte aliases over the current Plus/4 storage implementation. The
// low-level plus4_kernal_* names wrap Plus/4 ROM/RAM visibility around KERNAL
// calls; new shared storage work should target these HAL labels instead.

#import "storage_policy.s"
#import "storage_title_name.s"

.label hal_storage_enter_os = plus4_bank_rom
.label hal_storage_exit_os = plus4_bank_ram
.label hal_storage_require_program_media = disk_prompt_game
.label hal_storage_require_save_media = disk_require_save_media
.label hal_storage_marker_present = plus4_storage_marker_present
.label hal_storage_marker_init = disk_marker_init
.label hal_storage_marker_write_resident = plus4_storage_marker_write_resident
.label hal_storage_save_media_status = disk_save_media_status
.label hal_storage_setup_status = disk_setup_status
.label hal_storage_save_stream_status = save_stream_status
.label hal_storage_load_stream_status = load_stream_status
.label hal_storage_setnam = plus4_kernal_setnam
.label hal_storage_setlfs = plus4_kernal_setlfs
.label hal_storage_open = plus4_kernal_open
.label hal_storage_close = plus4_kernal_close
.label hal_storage_chkin = plus4_kernal_chkin
.label hal_storage_chkout = plus4_kernal_chkout
.label hal_storage_chrin = plus4_kernal_chrin
.label hal_storage_chrout = plus4_kernal_chrout
.label hal_storage_clrchn = plus4_kernal_clrchn
.label hal_storage_readst = plus4_kernal_readst
.label hal_storage_load = plus4_kernal_load
.label hal_storage_read_command_status = plus4_disk_read_command_status
.label hal_storage_command_status = disk_command_status
.label hal_storage_diag_code = disk_status
.label hal_storage_diag_phase = disk_error_phase
.label hal_storage_diag_readst = disk_error_readst
.label hal_storage_diag_device = disk_error_device
.label hal_storage_diag_dos0 = disk_error_dos0
.label hal_storage_diag_dos1 = disk_error_dos1
.label hal_storage_save_record = save_game
.label hal_storage_load_record = load_game

// Check whether an IEC device responds.
// Input: X = device number (8-30)
// Output: carry clear = present, carry set = absent/unusable
hal_storage_probe_media:
    stx disk_temp
    jsr plus4_bank_rom

    lda #0
    ldx #0
    ldy #0
    jsr plus4_kernal_setnam
    lda #hal_storage_cmd_channel
    ldx disk_temp
    ldy #hal_storage_cmd_channel
    jsr plus4_kernal_setlfs
    jsr plus4_kernal_open
    bcs !absent+
    jsr plus4_kernal_readst
    bne !close_absent+
    lda #hal_storage_cmd_channel
    jsr plus4_kernal_close
    jsr plus4_kernal_clrchn
    jsr plus4_bank_ram
    clc
    rts
!close_absent:
    lda #hal_storage_cmd_channel
    jsr plus4_kernal_close
!absent:
    jsr plus4_kernal_clrchn
    jsr plus4_bank_ram
    sec
    rts

// Best-effort drive init for the selected prompt device.
hal_storage_init_selected_drive:
    jsr plus4_bank_rom
    lda #2
    ldx #<hal_storage_init_command
    ldy #>hal_storage_init_command
    jsr plus4_kernal_setnam
    lda #hal_storage_cmd_channel
    ldx disk_prompt_device
    ldy #hal_storage_cmd_channel
    jsr plus4_kernal_setlfs
    jsr plus4_kernal_open
    bcs !done+
    lda #hal_storage_cmd_channel
    jsr plus4_kernal_close
!done:
    jsr plus4_kernal_clrchn
    jsr plus4_bank_ram
    rts

// Platform-owned save-disk marker filenames and marker bytes. These must live
// in resident RAM below BASIC/KERNAL ROM because the Plus/4 KERNAL reads
// filename bytes while ROM is visible over $8000-$BFFF.
hal_storage_init_command:
    .byte $49, $30                              // "I0"

hal_storage_marker_magic:
    .byte $4d, $38, $50, $34, $53, $56          // "M8P4SV"
.label hal_storage_marker_magic_len = * - hal_storage_marker_magic

hal_storage_marker_read_name:
    .byte $30, $3a                              // "0:"
    .byte $4d, $4f, $52, $49, $41, $34, $2e, $49, $44 // "MORIA4.ID"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_marker_read_name_len = * - hal_storage_marker_read_name

hal_storage_marker_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $4d, $4f, $52, $49, $41, $34, $2e, $49, $44 // "MORIA4.ID"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_marker_write_name_len = * - hal_storage_marker_write_name

hal_storage_marker_scratch_name:
    .byte $53, $30, $3a                         // "S0:"
    .byte $4d, $4f, $52, $49, $41, $34, $2e, $49, $44 // "MORIA4.ID"
.label hal_storage_marker_scratch_name_len = * - hal_storage_marker_scratch_name

// Platform-owned save-record filenames. PETSCII bytes for KERNAL SETNAM.
// These must live in resident RAM below BASIC/KERNAL ROM because the Plus/4
// KERNAL reads filename bytes while ROM is visible over $8000-$BFFF.
hal_storage_save_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $50, $34, $2e, $54, $48, $45, $2e, $47, $41, $4d, $45 // "P4.THE.GAME"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_save_write_name_len = * - hal_storage_save_write_name
.label hal_storage_save_probe_name = hal_storage_save_write_name + 1
.label hal_storage_save_probe_name_len = hal_storage_save_write_name_len - 1

hal_storage_save_read_name:
    .byte $30, $3a                              // "0:"
    .byte $50, $34, $2e, $54, $48, $45, $2e, $47, $41, $4d, $45 // "P4.THE.GAME"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_save_read_name_len = * - hal_storage_save_read_name

// Platform-owned high-score filenames. PETSCII bytes for KERNAL SETNAM.
// These must live in resident RAM below BASIC/KERNAL ROM because the Plus/4
// KERNAL reads filename bytes while ROM is visible over $8000-$BFFF.
hal_storage_score_read_name:
    .byte $30, $3a                              // "0:"
    .byte $50, $34, $2e, $48, $41, $4c, $4c, $2e, $46, $41, $4d, $45 // "P4.HALL.FAME"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_score_read_name_len = * - hal_storage_score_read_name

hal_storage_score_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $50, $34, $2e, $48, $41, $4c, $4c, $2e, $46, $41, $4d, $45 // "P4.HALL.FAME"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_score_write_name_len = * - hal_storage_score_write_name

hal_storage_score_scratch_name:
    .byte $53, $30, $3a                         // "S0:"
    .byte $50, $34, $2e, $48, $41, $4c, $4c, $2e, $46, $41, $4d, $45 // "P4.HALL.FAME"
.label hal_storage_score_scratch_name_len = * - hal_storage_score_scratch_name

// Platform-owned tier data filenames. PETSCII bytes for KERNAL LOAD.
// Lengths exclude the trailing zero; display paths use the same labels as
// zero-terminated strings.
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

// Platform-owned overlay asset filenames. PETSCII bytes for KERNAL LOAD.
hal_storage_overlay_start_name:
    .byte $34,$2e,$53,$54,$41,$52,$54           // "4.START"
.label hal_storage_overlay_start_name_len = * - hal_storage_overlay_start_name
    .byte 0
hal_storage_overlay_town_name:
    .byte $34,$2e,$54,$4f,$57,$4e               // "4.TOWN"
.label hal_storage_overlay_town_name_len = * - hal_storage_overlay_town_name
    .byte 0
hal_storage_overlay_death_name:
    .byte $34,$2e,$44,$45,$41,$54,$48           // "4.DEATH"
.label hal_storage_overlay_death_name_len = * - hal_storage_overlay_death_name
    .byte 0
hal_storage_overlay_gen_name:
    .byte $34,$2e,$47,$45,$4e                   // "4.GEN"
.label hal_storage_overlay_gen_name_len = * - hal_storage_overlay_gen_name
    .byte 0
hal_storage_overlay_help_name:
    .byte $34,$2e,$48,$45,$4c,$50               // "4.HELP"
.label hal_storage_overlay_help_name_len = * - hal_storage_overlay_help_name
    .byte 0
hal_storage_overlay_ui_name:
    .byte $34,$2e,$55,$49                       // "4.UI"
.label hal_storage_overlay_ui_name_len = * - hal_storage_overlay_ui_name
    .byte 0
hal_storage_overlay_items_name:
    .byte $34,$2e,$49,$54,$45,$4d,$53           // "4.ITEMS"
.label hal_storage_overlay_items_name_len = * - hal_storage_overlay_items_name
    .byte 0
hal_storage_overlay_spell_name:
    .byte $34,$2e,$53,$50,$45,$4c,$4c           // "4.SPELL"
.label hal_storage_overlay_spell_name_len = * - hal_storage_overlay_spell_name
    .byte 0
hal_storage_royal_name:
    .byte $34,$2e,$52,$4f,$59,$41,$4c           // "4.ROYAL"
.label hal_storage_royal_name_len = * - hal_storage_royal_name
    .byte 0

hal_storage_overlay_name_lo:
    .byte <hal_storage_overlay_start_name, <hal_storage_overlay_town_name, <hal_storage_overlay_death_name, <hal_storage_overlay_gen_name, <hal_storage_overlay_help_name, <hal_storage_overlay_ui_name, <hal_storage_overlay_items_name, <hal_storage_overlay_spell_name
hal_storage_overlay_name_hi:
    .byte >hal_storage_overlay_start_name, >hal_storage_overlay_town_name, >hal_storage_overlay_death_name, >hal_storage_overlay_gen_name, >hal_storage_overlay_help_name, >hal_storage_overlay_ui_name, >hal_storage_overlay_items_name, >hal_storage_overlay_spell_name
hal_storage_overlay_name_len:
    .byte hal_storage_overlay_start_name_len, hal_storage_overlay_town_name_len, hal_storage_overlay_death_name_len, hal_storage_overlay_gen_name_len, hal_storage_overlay_help_name_len, hal_storage_overlay_ui_name_len, hal_storage_overlay_items_name_len, hal_storage_overlay_spell_name_len
