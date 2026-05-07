#importonce
// Storage contract.
//
// Phase-2 adapter exports per platform. These are deliberately low-level first
// so the tree can grow a real HAL boundary without rewriting save/load in the
// same step:
//
//   hal_storage_enter_os
//   hal_storage_exit_os
//   hal_storage_probe_media
//   hal_storage_require_program_media
//   hal_storage_require_save_media
//   hal_storage_marker_present
//   hal_storage_marker_init
//   hal_storage_setnam
//   hal_storage_setlfs
//   hal_storage_open
//   hal_storage_close
//   hal_storage_chkin
//   hal_storage_chkout
//   hal_storage_chrin
//   hal_storage_chrout
//   hal_storage_clrchn
//   hal_storage_readst
//   hal_storage_load
//   hal_storage_save_record
//   hal_storage_load_record
//
// Raw KERNAL-like calls preserve the platform's existing low-level carry and
// register behavior. Higher-level HAL calls use this error convention:
//
//   Carry clear = success.
//   Carry set = failure.
//   A = HAL_STATUS_* normalized code when available.
//   X = platform/raw disk code when available, otherwise 0.
//   Y = HAL_STORAGE_PHASE_* or platform-specific phase.
//
// Residency and banking:
//
// - `hal_storage_enter_os` returns with the platform's OS/KERNAL-visible state.
// - `hal_storage_exit_os` returns with the platform's documented all-RAM
//   runtime visibility.
// - Filename, command, and transfer buffers passed to KERNAL-like services must
//   be visible to the OS/device implementation while the call executes.
// - Callers may not assume that A/X/Y survive any OS/device call unless that
//   specific adapter documents it.
//
// Drive model is not part of the contract. 1541, 1551, 1571, SD2IEC, and other
// Commodore-compatible devices must be handled by platform storage code.
