#importonce
#if ATARI8_CARTRIDGE
#define HAL_STORAGE_PROGRAM_MEDIA_ALWAYS_AVAILABLE
#define HAL_STORAGE_ASSET_LOAD_INFALLIBLE
#endif
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
// $20 (Save Format V2): expanded 370-item catalog, 34 inventory slots (with
// Cloak), 174 flavours, 55 egos, 128 store items with meta_hi, and 279-species
// persistent monster recall. Older V1..V19 saves are no longer accepted.
.const hal_storage_save_v1_version = $20
.const hal_storage_save_version = $20
.assert "Atari Save Format V2 pins oldest accepted version to $20", hal_storage_save_v1_version == $20 && hal_storage_save_version == $20, true

#define HAL_STORAGE_MARKER_PRESENT_DIRECT
#define HAL_STORAGE_SAVE_CONFIRM_OVERWRITE_PROBE
#define HAL_STORAGE_FRIENDLY_STATUS_MESSAGES
#define HAL_STORAGE_STREAM_STATUS_HELPERS
#define HAL_STORAGE_RETURN_LOCAL_STATUS
// SIO retries each sector itself: one repeat of a failed asset load is enough.
#define HAL_STORAGE_ASSET_LOAD_TWO_ATTEMPTS
#define HAL_STORAGE_NO_UNIT_TEST_STUBS
