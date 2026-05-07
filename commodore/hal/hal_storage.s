#importonce
// Storage contract.
//
// Required exports per platform:
//   hal_storage_probe_media
//   hal_storage_require_program_media
//   hal_storage_require_save_media
//   hal_storage_open_read
//   hal_storage_open_write
//   hal_storage_read_byte
//   hal_storage_write_byte
//   hal_storage_close
//   hal_storage_command
//   hal_storage_read_status
//   hal_storage_save_record
//   hal_storage_load_record
//
// Carry clear = success. Carry set = failure.
// On failure:
//   A = HAL_STATUS_* normalized code
//   X = platform/raw disk code when available, otherwise 0
//   Y = HAL_STORAGE_PHASE_* or platform-specific phase
//
// Drive model is not part of the contract. 1541, 1551, 1571, SD2IEC, and other
// Commodore-compatible devices must be handled by platform storage code.
