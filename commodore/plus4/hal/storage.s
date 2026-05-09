#importonce
// Plus/4 storage HAL adapter.
//
// Zero-byte aliases over the current Plus/4 storage implementation. The
// low-level plus4_kernal_* names wrap Plus/4 ROM/RAM visibility around KERNAL
// calls; new shared storage work should target these HAL labels instead.

#import "storage_policy.s"

.label hal_storage_enter_os = plus4_bank_rom
.label hal_storage_exit_os = plus4_bank_ram
.label hal_storage_probe_media = probe_device
.label hal_storage_require_program_media = disk_prompt_game
.label hal_storage_require_save_media = disk_require_save_media
.label hal_storage_marker_present = disk_marker_present
.label hal_storage_marker_init = disk_marker_init
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
.label hal_storage_save_record = save_game
.label hal_storage_load_record = load_game

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
