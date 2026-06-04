#importonce
// C128 platform-owned storage logical file numbers and secondary addresses.

.const hal_storage_save_file_num = 2
.const hal_storage_check_file_num = 3
.const hal_storage_save_sec_write = 2
.const hal_storage_save_sec_read = 2
.const hal_storage_check_sec_read = hal_storage_save_sec_read
.const hal_storage_cmd_channel = 15
.const hal_storage_marker_file_num = 13
.const hal_storage_marker_sec_read = 2
.const hal_storage_marker_sec_write = 2
.const hal_storage_program_file_num = 7
.const hal_storage_disk_setup_supports_other_drive = 1
.const hal_storage_disk_setup_detail_command_status = 1
.const hal_storage_disk_setup_detail_dos_drive = 0
.const hal_storage_disk_setup_detail_status_phase = 0
.const hal_storage_disk_setup_marker_write_status_required = 0
.const hal_storage_disk_setup_done_value = 1
.const hal_storage_disk_setup_commit_sets_ui_ok = 1
.const hal_storage_save_v1_version = $10
.const hal_storage_save_version = $11

#define HAL_STORAGE_DISK_SETUP_OTHER_DRIVE
#define HAL_STORAGE_DISK_SETUP_COMMIT_SETS_UI_OK
#define HAL_STORAGE_COMMAND_STATUS_FROM_DISK_DIAG
#define HAL_STORAGE_SETUP_STATUS_COMMAND_FIRST
#define HAL_STORAGE_SAVE_MEDIA_STATUS_MARKER_DOS
#define HAL_STORAGE_MEDIA_STATE_TRACKING
#define HAL_STORAGE_SWAP_PROMPT_MODAL_DISMISS
#define HAL_STORAGE_SWAP_PROMPT_CLEAR_ROWS_AND_TRACK_MEDIA
#define HAL_STORAGE_DIR_READ_FNAME
#define HAL_STORAGE_KERNAL_ENTER_REQUIRED
#define HAL_STORAGE_MARKER_PRESENT_INLINE
#define HAL_STORAGE_DISK_SETUP_UI_TRAMPOLINE
#define HAL_STORAGE_SAVE_CONFIRM_OVERWRITE_PROBE
#define HAL_STORAGE_FRIENDLY_STATUS_MESSAGES
#define HAL_STORAGE_STREAM_STATUS_HELPERS
#define HAL_STORAGE_STREAM_CHUNKED
#define HAL_STORAGE_MAP_BANKED
#define HAL_STORAGE_RETURN_DIRECT
#define HAL_STORAGE_PRESERVE_X_DURING_BYTE_STREAM
#define HAL_STORAGE_RESTORE_VIC_BANK_AFTER_SAVE_PROBE
