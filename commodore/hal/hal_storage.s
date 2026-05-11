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
//   hal_storage_init_selected_drive
//   hal_storage_require_program_media
//   hal_storage_require_save_media
//   hal_storage_marker_present
//   hal_storage_marker_init
//   hal_storage_save_media_status
//   hal_storage_setup_status
//   hal_storage_save_stream_status
//   hal_storage_load_stream_status
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
//   hal_storage_read_command_status
//   hal_storage_save_record
//   hal_storage_load_record
//   hal_storage_save_file_num
//   hal_storage_check_file_num
//   hal_storage_save_sec_write
//   hal_storage_save_sec_read
//   hal_storage_check_sec_read
//   hal_storage_cmd_channel
//   hal_storage_marker_file_num
//   hal_storage_marker_sec_read
//   hal_storage_marker_sec_write
//   hal_storage_program_file_num
//   hal_storage_save_probe_name
//   hal_storage_save_probe_name_len
//   hal_storage_save_read_name
//   hal_storage_save_read_name_len
//   hal_storage_save_write_name
//   hal_storage_save_write_name_len
//   hal_storage_score_read_name
//   hal_storage_score_read_name_len
//   hal_storage_score_write_name
//   hal_storage_score_write_name_len
//   hal_storage_score_scratch_name
//   hal_storage_score_scratch_name_len
//   hal_storage_init_command
//   hal_storage_marker_magic
//   hal_storage_marker_magic_len
//   hal_storage_marker_read_name
//   hal_storage_marker_read_name_len
//   hal_storage_marker_write_name
//   hal_storage_marker_write_name_len
//   hal_storage_marker_scratch_name
//   hal_storage_marker_scratch_name_len
//   hal_storage_title_name
//   hal_storage_title_name_len
//   hal_storage_tier_name_lo
//   hal_storage_tier_name_hi
//   hal_storage_tier_name_len
//   hal_storage_tier_1_name
//   hal_storage_tier_1_name_len
//   hal_storage_tier_2_name
//   hal_storage_tier_2_name_len
//   hal_storage_tier_3_name
//   hal_storage_tier_3_name_len
//   hal_storage_tier_4_name
//   hal_storage_tier_4_name_len
//   hal_storage_overlay_name_lo
//   hal_storage_overlay_name_hi
//   hal_storage_overlay_name_len
//   hal_storage_overlay_start_name
//   hal_storage_overlay_start_name_len
//   hal_storage_overlay_town_name
//   hal_storage_overlay_town_name_len
//   hal_storage_overlay_death_name
//   hal_storage_overlay_death_name_len
//   hal_storage_overlay_gen_name
//   hal_storage_overlay_gen_name_len
//   hal_storage_overlay_help_name
//   hal_storage_overlay_help_name_len
//   hal_storage_overlay_ui_name
//   hal_storage_overlay_ui_name_len
//   hal_storage_overlay_items_name
//   hal_storage_overlay_items_name_len
//
// Tier and overlay filename lengths exclude the trailing zero. The zero is
// still part of the storage-HAL data contract because REU/cache preload
// display prints these same filename labels as zero-terminated strings.
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
// - Save-record, high-score, save-disk marker, title-art, tier-data, and
//   overlay filename labels are platform-owned PETSCII/KERNAL strings. Common
//   code must not hardcode those asset filenames.
// - `hal_storage_probe_media` checks whether the device in X responds.
//   Carry clear means present; carry set means absent/unusable. The drive
//   model is intentionally invisible to common code.
// - `hal_storage_init_selected_drive` sends the platform's drive init command
//   to `disk_prompt_device`. Carry is not meaningful; this is a best-effort
//   media-change synchronization.
// - `hal_storage_read_command_status` reads the active save device's command
//   channel status and stores platform diagnostics in the platform-owned disk
//   error/status bytes. It is callable after `hal_storage_enter_os`; callers
//   that are not already in OS-visible state must enter/exit around it.
// - `hal_storage_save_media_status` classifies the most recent save-media probe
//   failure. It returns A = HAL_STORAGE_STATUS_*. Platform diagnostics remain
//   in the platform-owned disk status bytes.
// - `hal_storage_setup_status` classifies the most recent Disk Setup
//   initialization failure. It returns A = HAL_STORAGE_STATUS_*. Platform
//   diagnostics remain in the platform-owned disk status bytes.
// - `hal_storage_save_stream_status` classifies the most recent save-record
//   stream result. It returns A = HAL_STORAGE_STATUS_*.
// - `hal_storage_load_stream_status` classifies the most recent load-record
//   stream result. It returns A = HAL_STORAGE_STATUS_*.
// - Callers may not assume that A/X/Y survive any OS/device call unless that
//   specific adapter documents it.
//
// Drive model is not part of the contract. 1541, 1551, 1571, SD2IEC, and other
// Commodore-compatible devices must be handled by platform storage code.
