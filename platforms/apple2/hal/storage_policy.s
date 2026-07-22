#importonce
// Apple IIe platform-owned storage policy: logical file numbers and secondary
// addresses. On ProDOS these are logical IDs mapped by save_stream.s onto the
// single open MLI ref_num; there is no command channel and no second drive.
// Save-format versions match the Commodore ports (shared serialization).

.const hal_storage_save_file_num = 2
.const hal_storage_check_file_num = 3
.const hal_storage_save_sec_write = 2
.const hal_storage_save_sec_read = 2
.const hal_storage_check_sec_read = hal_storage_save_sec_read
.const hal_storage_cmd_channel = 15
.const hal_storage_marker_file_num = 6
.const hal_storage_marker_sec_read = 2
.const hal_storage_marker_sec_write = 2
.const hal_storage_program_file_num = 7
.const hal_storage_disk_setup_supports_other_drive = 0
.const hal_storage_disk_setup_detail_command_status = 0
.const hal_storage_disk_setup_detail_dos_drive = 0
.const hal_storage_disk_setup_detail_status_phase = 0
.const hal_storage_disk_setup_marker_write_status_required = 0
.const hal_storage_disk_setup_done_value = 2
.const hal_storage_disk_setup_commit_sets_ui_ok = 0
.const hal_storage_save_v1_version = $0f
.const hal_storage_save_known96_version = $10
.const hal_storage_save_version = $11

// ProDOS MLI error codes used by the status classifier (shared by
// storage_mli.s and save_stream.s).
.const A2ERR_IO           = $27
.const A2ERR_NO_DEVICE    = $28
.const A2ERR_WRITE_PROT   = $2b
.const A2ERR_DISK_SWITCHED = $2e
.const A2ERR_PATH_NOT_FOUND = $44
.const A2ERR_VOL_NOT_FOUND = $45
.const A2ERR_NOT_FOUND    = $46
.const A2ERR_DUPLICATE    = $47
.const A2ERR_DISK_FULL    = $48
.const A2ERR_EOF          = $4c
.const A2ERR_ACCESS       = $4e

// Stream-status byte values synthesized by save_stream.s (READST shape:
// bit 6 = EOF, bits 0-1 = timeout-style error, matching save.s masks).
.const A2_SS_ERR_WRITE    = $01
.const A2_SS_ERR_READ     = $02
.const A2_SS_EOF          = $40

// Marker presence is a direct GET_FILE_INFO probe on MORIA8.ID; overwrite
// confirm is a GET_FILE_INFO probe; status classification uses the helper
// layer over the ProDOS-error-to-HAL_STATUS map.
#define HAL_STORAGE_MARKER_PRESENT_DIRECT
#define HAL_STORAGE_SAVE_CONFIRM_OVERWRITE_PROBE
#define HAL_STORAGE_FRIENDLY_STATUS_MESSAGES
#define HAL_STORAGE_STREAM_STATUS_HELPERS
#define HAL_STORAGE_RETURN_LOCAL_STATUS
// The map lives in aux RAM: excluded from the generic save-block table and
// streamed by the platform map helpers (save_stream.s) like C128's Bank 1.
#define HAL_STORAGE_MAP_BANKED
