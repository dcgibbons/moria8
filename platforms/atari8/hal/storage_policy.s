#importonce
// Atari 8-bit platform-owned storage logical file numbers, secondary addresses,
// and save-format version policy.
//
// Every feature-version constant is pinned to the oldest supported save
// version ($15), so no legacy save migration code is carried. The one
// exception is the 33-slot inventory ($16, reserved cloak + secondary
// weapon): $15 saves still load, through the shared 31-slot inventory path.

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
.const hal_storage_save_inv33_version = $16
.const hal_storage_save_version = $16
.assert "Atari $15 saves are 31-slot saves (no 30-slot loader)", hal_storage_save_inv31_version == hal_storage_save_v1_version, true
.assert "Atari 33-slot saves are the one version past the oldest", hal_storage_save_inv33_version == hal_storage_save_version && hal_storage_save_version == hal_storage_save_v1_version + 1, true

#define HAL_STORAGE_MARKER_PRESENT_DIRECT
#define HAL_STORAGE_SAVE_CONFIRM_OVERWRITE_PROBE
#define HAL_STORAGE_FRIENDLY_STATUS_MESSAGES
#define HAL_STORAGE_STREAM_STATUS_HELPERS
#define HAL_STORAGE_RETURN_LOCAL_STATUS
// SIO retries each sector itself: one repeat of a failed asset load is enough.
#define HAL_STORAGE_ASSET_LOAD_TWO_ATTEMPTS
#define HAL_STORAGE_NO_UNIT_TEST_STUBS
