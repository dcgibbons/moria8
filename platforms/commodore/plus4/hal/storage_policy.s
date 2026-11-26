#importonce
// Plus/4 platform-owned storage logical file numbers and secondary addresses.
#if PLUS4_CARTRIDGE
#define HAL_STORAGE_PROGRAM_MEDIA_ALWAYS_AVAILABLE
#define HAL_STORAGE_ASSET_LOAD_INFALLIBLE
#endif

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
// resident here; core/6502/score_io.s).
#define HAL_STORAGE_SCORE_PROBES_FILE
.const hal_storage_marker_file_num = 6
.const hal_storage_marker_sec_read = 2
.const hal_storage_marker_sec_write = 2
.const hal_storage_program_file_num = 7
.const hal_storage_disk_setup_supports_other_drive = 1
.const hal_storage_disk_setup_detail_command_status = 0
.const hal_storage_disk_setup_detail_dos_drive = 1
.const hal_storage_disk_setup_detail_status_phase = 1
#define HAL_STORAGE_DISK_SETUP_DETAIL_DOS_DRIVE
#define HAL_STORAGE_DISK_SETUP_DETAIL_STATUS_PHASE
.const hal_storage_disk_setup_marker_write_status_required = 1
.const hal_storage_disk_setup_done_value = 2
.const hal_storage_disk_setup_commit_sets_ui_ok = 0
// $22 (Save Format V2): canonical 361-item VMS catalog, 34 inventory slots
// (with Cloak), 174 flavours, 55 egos, 128 store items with meta_hi, and
// 279-species persistent monster recall. Only SAVE_VERSION ($22) is accepted.
.const hal_storage_save_version = $22

#define HAL_STORAGE_DISK_SETUP_MARKER_PROBE_DOS
#define HAL_STORAGE_DISK_SETUP_MARKER_WRITE_STATUS_REQUIRED
#define HAL_STORAGE_EXTENDED_DISK_DIAG
#define HAL_STORAGE_COMMAND_STATUS_FROM_ERROR_DIAG
#define HAL_STORAGE_SETUP_STATUS_ERROR_FIRST
#define HAL_STORAGE_SAVE_MEDIA_STATUS_ERROR_DIAG
#define HAL_STORAGE_SWAP_PROMPT_LEGACY_SETUP_SKIP
#define HAL_STORAGE_SWAP_PROMPT_FULLSCREEN
#define HAL_STORAGE_SWAP_PROMPT_SIMPLE_KEY
#define HAL_STORAGE_SWAP_PROMPT_RETURN_AFTER_INIT
#define HAL_STORAGE_MARKER_PRESENT_DIRECT
#define HAL_STORAGE_DISK_SETUP_OTHER_DRIVE
#define HAL_STORAGE_DISK_SETUP_UI_PLUS4_BANK_RAM
#define HAL_STORAGE_SAVE_MAGIC_ALT_SIGNATURE
#define HAL_STORAGE_SAVE_CONFIRM_OVERWRITE_PROBE
#define HAL_STORAGE_FRIENDLY_STATUS_MESSAGES
#define HAL_STORAGE_STREAM_STATUS_HELPERS
#define HAL_STORAGE_APPEND_DISK_DETAIL
#define HAL_STORAGE_MASK_CHRIN_WRITE_TIMEOUT_STATUS
#define HAL_STORAGE_PRESERVE_X_DURING_BYTE_STREAM
#define HAL_STORAGE_CLOSE_SAVE_FILE_BEFORE_LOAD
#define HAL_STORAGE_READST_AFTER_LOAD_OPEN
#define HAL_STORAGE_RETURN_LOCAL_STATUS
#define HAL_STORAGE_SCORE_OPEN_RESTORES_RUNTIME
// save_game reads the drive's command channel after the write: CBM DOS
// reports a write-protected or full disk only there.
#define HAL_STORAGE_SAVE_CHECKS_DOS_STATUS
#if !PLUS4_CARTRIDGE
#define HAL_STORAGE_LOAD_PROGRAM_MEDIA_PROBE
#endif
#define HAL_STORAGE_NO_UNIT_TEST_STUBS

#if !PLUS4_CARTRIDGE
#define HAL_STORAGE_LEGAL_COMMAND_STATUS
#endif
