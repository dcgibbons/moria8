#importonce
// C128 lifecycle HAL policy constants.

.const hal_platform_reassert_before_message_render = 1
.const hal_platform_restore_tier_after_overlay = 0
.const hal_platform_string_bank_load_invalidates_tier = 0
.const hal_platform_mark_modal_restore_perf = 1
.const hal_platform_perf_p1_command_instrumentation = 1
.const hal_platform_render_ball_effect_direct_perf = 1
.const hal_platform_character_sheet_begin_enabled = 1
.const hal_platform_character_background_resync = 1
.const hal_platform_player_magic_helpers_external = 1
.const hal_platform_item_action_key_restores_bank = 1
.const hal_platform_ego_holy_avenger_string_external = 1
.const hal_platform_ego_ac_bonus_external = 1
.const hal_platform_chargen_runtime_resync = 1
#if C128_TEST_CHARGEN_CUTPOINT
.const hal_platform_chargen_cutpoint = C128_TEST_CHARGEN_CUTPOINT
#else
.const hal_platform_chargen_cutpoint = -1
#endif
.const hal_platform_wizard_entry_uses_overlay = 1
.const hal_platform_wizard_40col_resident_enabled = 0
.const hal_platform_wizard_reveal_uses_trampoline = 0
.const hal_platform_levelup_magic_uses_trampoline = 1
.const hal_platform_title_sysinfo_80col = 1
.const hal_platform_title_sysinfo_sx64_probe = 0
.const hal_platform_player_move_diag_labels = 1
.const hal_platform_describe_look_masks_irq = 1
#define HAL_PLATFORM_TITLE_SYSINFO_80COL
#if C128_PRODUCT_OVERLAY_RUNTIME
.const hal_platform_item_prompt_overlay_runtime = 1
#else
.const hal_platform_item_prompt_overlay_runtime = 0
#endif
.const hal_platform_item_prompt_reload_installs_irq = 0
.const hal_platform_item_prompt_reload_resync = 1
.const hal_platform_equip_prepare_key_before_display = 0
#define HAL_PLATFORM_WIZARD_ENTRY_OVERLAY
#define HAL_PLATFORM_EGO_HOLY_AVENGER_STRING_EXTERNAL
#define HAL_PLATFORM_EGO_AC_BONUS_EXTERNAL
#define HAL_PLATFORM_CURE_POISON_MSG_EXTERNAL
