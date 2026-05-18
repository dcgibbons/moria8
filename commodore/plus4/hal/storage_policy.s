#importonce
// Plus/4 platform-owned storage logical file numbers and secondary addresses.

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
.const hal_storage_disk_setup_detail_dos_drive = 1
.const hal_storage_disk_setup_detail_status_phase = 1

#define HAL_STORAGE_EXTENDED_DISK_DIAG
#define HAL_STORAGE_COMMAND_STATUS_FROM_ERROR_DIAG
#define HAL_STORAGE_SETUP_STATUS_ERROR_FIRST
#define HAL_STORAGE_SAVE_MEDIA_STATUS_ERROR_DIAG
#define HAL_STORAGE_SWAP_PROMPT_FULLSCREEN
#define HAL_STORAGE_SWAP_PROMPT_SIMPLE_KEY
#define HAL_STORAGE_SWAP_PROMPT_RETURN_AFTER_INIT
#define HAL_STORAGE_MARKER_PRESENT_DIRECT
