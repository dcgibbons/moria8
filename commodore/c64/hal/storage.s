#importonce
// C64 storage HAL adapter.
//
// Zero-byte aliases over the current C64 storage implementation. Common call
// sites are intentionally not migrated in this step, and C64 default memory is
// too tight for resident adapter code.

.label hal_storage_enter_os = disk_kernal_enter
.label hal_storage_exit_os = disk_kernal_exit
.label hal_storage_probe_media = probe_device
.label hal_storage_require_program_media = disk_prompt_game
.label hal_storage_require_save_media = disk_require_save_media
.label hal_storage_marker_present = disk_marker_present
.label hal_storage_marker_init = disk_marker_init
.label hal_storage_setnam = c64_disk_setnam
.label hal_storage_setlfs = c64_disk_setlfs
.label hal_storage_open = c64_disk_open
.label hal_storage_close = c64_disk_close
.label hal_storage_chkin = KERNAL_CHKIN
.label hal_storage_chkout = KERNAL_CHKOUT
.label hal_storage_chrin = KERNAL_CHRIN
.label hal_storage_chrout = KERNAL_CHROUT
.label hal_storage_clrchn = c64_disk_clrchn
.label hal_storage_readst = KERNAL_READST
.label hal_storage_load = KERNAL_LOAD
.label hal_storage_save_record = save_game
.label hal_storage_load_record = load_game
