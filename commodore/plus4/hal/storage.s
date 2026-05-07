#importonce
// Plus/4 storage HAL adapter.
//
// Zero-byte aliases over the current Plus/4 storage implementation. The
// low-level plus4_kernal_* names wrap Plus/4 ROM/RAM visibility around KERNAL
// calls; new shared storage work should target these HAL labels instead.

.label hal_storage_enter_os = plus4_bank_rom
.label hal_storage_exit_os = plus4_bank_ram
.label hal_storage_probe_media = probe_device
.label hal_storage_require_program_media = disk_prompt_game
.label hal_storage_require_save_media = disk_require_save_media
.label hal_storage_marker_present = disk_marker_present
.label hal_storage_marker_init = disk_marker_init
.label hal_storage_setnam = plus4_kernal_setnam
.label hal_storage_setlfs = plus4_kernal_setlfs
.label hal_storage_open = plus4_kernal_open
.label hal_storage_close = plus4_kernal_close
.label hal_storage_chkin = plus4_kernal_chkin
.label hal_storage_chkout = plus4_kernal_chkout
.label hal_storage_chrin = plus4_kernal_chrin
.label hal_storage_chrout = plus4_kernal_chrout
.label hal_storage_clrchn = plus4_kernal_clrchn
.label hal_storage_readst = plus4_kernal_readst
.label hal_storage_load = plus4_kernal_load
.label hal_storage_save_record = save_game
.label hal_storage_load_record = load_game
