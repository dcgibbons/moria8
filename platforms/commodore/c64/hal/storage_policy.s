#importonce
#if C64_CARTRIDGE
#define HAL_STORAGE_PROGRAM_MEDIA_ALWAYS_AVAILABLE
#define HAL_STORAGE_ASSET_LOAD_INFALLIBLE
#endif
// C64 platform-owned storage logical file numbers and secondary addresses.

.const hal_storage_save_file_num = 2
.const hal_storage_check_file_num = 3
.const hal_storage_save_sec_write = 2
.const hal_storage_save_sec_read = 2
.const hal_storage_check_sec_read = hal_storage_save_sec_read
.const hal_storage_cmd_channel = 15
// The save-slot probe reads the drive's status before any CHKIN on a slot
// file (IEC: a CHKIN on a file the drive refused can hang the KERNAL).
#define HAL_STORAGE_SAVE_PROBE_ASKS_DRIVE
// hiscore_load asks the drive before reading HALL.OF.FAME (the probe is
// resident here; core/score_io.s).
#define HAL_STORAGE_SCORE_PROBES_FILE
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
// $21 (Save Format V2): expanded 370-item catalog, 34 inventory slots (with
// Cloak), 174 flavours, 55 egos, 128 store items with meta_hi, and 279-species
// persistent monster recall. Only SAVE_VERSION ($21) is accepted.
.const hal_storage_save_version = $21

#define HAL_STORAGE_SAVE_MEDIA_STATUS_LEGACY
#define HAL_STORAGE_SWAP_PROMPT_LEGACY_SETUP_SKIP
#define HAL_STORAGE_SWAP_PROMPT_FULLSCREEN
#define HAL_STORAGE_SWAP_PROMPT_SIMPLE_KEY
#define HAL_STORAGE_SWAP_PROMPT_CPU_PORT_RESTORE
#define HAL_STORAGE_MARKER_PRESENT_DIRECT
#define HAL_STORAGE_MARKER_INIT_SKIP_SCRATCH
// The program-media probe asks the drive (storage_file_exists): no CHKIN.
#define HAL_STORAGE_PROGRAM_MEDIA_ASKS_DRIVE
#if C64_PRODUCT_OVERLAY_RUNTIME
#define HAL_STORAGE_PROGRAM_MEDIA_PRESENT_EXTERNAL
#endif
#define HAL_STORAGE_DISK_SETUP_OTHER_DRIVE
#define HAL_STORAGE_DISK_SETUP_UI_CPU_PORT
#define HAL_STORAGE_SAVE_SELECT_OUTPUT_NAME_LEGACY
#define HAL_STORAGE_RETURN_LOCAL_STATUS
#define HAL_STORAGE_VIC_BANK_RESTORE_AFTER_SERIAL
#define HAL_STORAGE_SCORE_OPEN_RESTORES_RUNTIME
// save_game reads the drive's command channel after the write: CBM DOS
// reports a write-protected or full disk only there.
#define HAL_STORAGE_SAVE_CHECKS_DOS_STATUS
// A failed save names the cause (write-protected, full, not ready), as on
// every other port.
#define HAL_STORAGE_FRIENDLY_STATUS_MESSAGES
// The command-status read leaves the DOS code itself in disk_status.
#define HAL_STORAGE_COMMAND_STATUS_FROM_DOS_CODE
#define HAL_STORAGE_UNIT_TEST_STUBS

#if !C64_CARTRIDGE
#define HAL_STORAGE_LEGAL_COMMAND_STATUS
#endif
