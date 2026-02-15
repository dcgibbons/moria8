// ui_trampoline_stubs.s — Test-only aliases for trampolines
//
// In the game build, trampolines bank out KERNAL to call $F000/$E000 code.
// In test builds, the code is at normal addresses so direct calls work.

// $F000 UI screen trampolines
.label tramp_ui_char_display = ui_char_display
.label tramp_ui_inv_display = ui_inv_display
.label tramp_ui_help_display = ui_help_display
.label tramp_ui_equip_display = ui_equip_display

// $E000 store overlay trampolines
.label tramp_store_init_all = store_init_all
.label tramp_store_restock_all = store_restock_all
.label tramp_store_enter = store_enter

// $E000 startup overlay trampolines
.label tramp_player_create = player_create
