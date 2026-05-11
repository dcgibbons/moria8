#importonce
// C64 storage HAL adapter.
//
// Zero-byte aliases over the current C64 storage implementation. Common call
// sites are intentionally not migrated in this step, and C64 default memory is
// too tight for resident adapter code.

#import "storage_policy.s"

.label hal_storage_enter_os = disk_kernal_enter
.label hal_storage_exit_os = disk_kernal_exit
.label hal_storage_probe_media = probe_device
.label hal_storage_require_program_media = disk_prompt_game
.label hal_storage_require_save_media = disk_require_save_media
.label hal_storage_marker_present = disk_marker_present
.label hal_storage_marker_init = disk_marker_init
.label hal_storage_save_media_status = disk_save_media_status
.label hal_storage_setnam = c64_disk_setnam
.label hal_storage_setlfs = c64_disk_setlfs
.label hal_storage_open = c64_disk_open
.label hal_storage_close = c64_disk_close
.label hal_storage_chkin = KERNAL_CHKIN
.label hal_storage_chkout = KERNAL_CHKOUT
.label hal_storage_chrin = KERNAL_CHRIN
.label hal_storage_chrout = KERNAL_CHROUT
.label hal_storage_clrchn = c64_disk_clrchn
.label hal_storage_readst = KERNAL_READST
.label hal_storage_load = KERNAL_LOAD
.label hal_storage_read_command_status = c64_storage_read_command_status
.label hal_storage_save_record = save_game
.label hal_storage_load_record = load_game

// Platform-owned save-disk marker filenames and marker bytes. PETSCII bytes
// for KERNAL SETNAM / sequential marker contents.
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

.segment RuntimeBanked
hal_storage_marker_scratch_name:
    .byte $53, $30, $3a                         // "S0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
.label hal_storage_marker_scratch_name_len = * - hal_storage_marker_scratch_name
.segment Default

// Platform-owned save-record filenames. PETSCII bytes for KERNAL SETNAM.
hal_storage_save_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45 // "THE.GAME"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_save_write_name_len = * - hal_storage_save_write_name
.label hal_storage_save_probe_name = hal_storage_save_write_name + 1
.label hal_storage_save_probe_name_len = hal_storage_save_write_name_len - 1

hal_storage_save_read_name:
    .byte $30, $3a                              // "0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45 // "THE.GAME"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_save_read_name_len = * - hal_storage_save_read_name

// Platform-owned title-art filename. PETSCII bytes for KERNAL LOAD.
hal_storage_title_name:
    .byte $54, $36, $34                         // "T64"
.label hal_storage_title_name_len = * - hal_storage_title_name
