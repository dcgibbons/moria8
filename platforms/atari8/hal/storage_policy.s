#importonce
// Atari 8-bit platform-owned storage logical file numbers, secondary addresses,
// and save-format version policy.
//
// OLDEST_SAVE_VERSION is pinned equal to SAVE_VERSION ($15) on Atari 8-bit so
// no legacy save migration code is carried.

.const hal_storage_save_file_num = 2
.const hal_storage_check_file_num = 3
.const hal_storage_save_sec_write = 1
.const hal_storage_save_sec_read = 0
.const hal_storage_check_sec_read = 0
.const hal_storage_cmd_channel = 15
.const hal_storage_marker_file_num = 6
.const hal_storage_marker_sec_read = 0
.const hal_storage_marker_sec_write = 1
.const hal_storage_program_file_num = 7
.const hal_storage_disk_setup_supports_other_drive = 1
.const hal_storage_disk_setup_detail_command_status = 0
.const hal_storage_disk_setup_detail_dos_drive = 0
.const hal_storage_disk_setup_detail_status_phase = 0
.const hal_storage_disk_setup_marker_write_status_required = 0
.const hal_storage_disk_setup_done_value = 1
.const hal_storage_disk_setup_commit_sets_ui_ok = 0
.const hal_storage_save_v1_version = $15
.const hal_storage_save_known96_version = $15
.const hal_storage_save_inv31_version = $15
.const hal_storage_save_known_bits_version = $15
.const hal_storage_save_baked_stats_version = $15
.const hal_storage_save_known160_version = $15
.const hal_storage_save_door_state_version = $15
.const hal_storage_save_version = $15

#define HAL_STORAGE_MARKER_PRESENT_DIRECT
#define HAL_STORAGE_SAVE_CONFIRM_OVERWRITE_PROBE
#define HAL_STORAGE_FRIENDLY_STATUS_MESSAGES
#define HAL_STORAGE_STREAM_STATUS_HELPERS
#define HAL_STORAGE_RETURN_LOCAL_STATUS
#define HAL_STORAGE_NO_UNIT_TEST_STUBS
