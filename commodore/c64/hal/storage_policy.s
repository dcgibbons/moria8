#importonce
// C64 platform-owned storage logical file numbers and secondary addresses.

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
.const hal_storage_disk_setup_supports_other_drive = 1
.const hal_storage_disk_setup_detail_command_status = 0
.const hal_storage_disk_setup_detail_dos_drive = 0
.const hal_storage_disk_setup_detail_status_phase = 0
.const hal_storage_disk_setup_marker_write_status_required = 0
.const hal_storage_disk_setup_done_value = 2
.const hal_storage_disk_setup_commit_sets_ui_ok = 0
.const hal_storage_save_v1_version = $0f
.const hal_storage_save_known96_version = $10
.const hal_storage_save_version = $11

#define HAL_STORAGE_SAVE_MEDIA_STATUS_LEGACY
#define HAL_STORAGE_SWAP_PROMPT_LEGACY_SETUP_SKIP
#define HAL_STORAGE_SWAP_PROMPT_FULLSCREEN
#define HAL_STORAGE_SWAP_PROMPT_SIMPLE_KEY
#define HAL_STORAGE_SWAP_PROMPT_CPU_PORT_RESTORE
#define HAL_STORAGE_MARKER_PRESENT_DIRECT
#define HAL_STORAGE_DISK_SETUP_OTHER_DRIVE
#define HAL_STORAGE_DISK_SETUP_UI_CPU_PORT
#define HAL_STORAGE_SAVE_SELECT_OUTPUT_NAME_LEGACY
#define HAL_STORAGE_CPU_PORT_RESTORE_AFTER_IO
#define HAL_STORAGE_VIC_BANK_RESTORE_AFTER_SERIAL
