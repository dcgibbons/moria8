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

#define HAL_STORAGE_COMMAND_STATUS_FROM_DISK_DIAG
#define HAL_STORAGE_SETUP_STATUS_COMMAND_FIRST
#define HAL_STORAGE_SAVE_MEDIA_STATUS_MARKER_DOS
#define HAL_STORAGE_MEDIA_STATE_TRACKING
#define HAL_STORAGE_SWAP_PROMPT_MODAL_DISMISS
#define HAL_STORAGE_SWAP_PROMPT_CLEAR_ROWS_AND_TRACK_MEDIA
#define HAL_STORAGE_DIR_READ_FNAME
#define HAL_STORAGE_KERNAL_ENTER_REQUIRED
#define HAL_STORAGE_MARKER_PRESENT_INLINE
