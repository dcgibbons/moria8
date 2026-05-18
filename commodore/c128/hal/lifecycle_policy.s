#importonce
// C128 lifecycle HAL policy constants.

.const hal_platform_reassert_before_message_render = true
.const hal_platform_restore_tier_after_overlay = false
.const hal_platform_string_bank_load_invalidates_tier = false
.const hal_platform_mark_modal_restore_perf = true
.const hal_platform_perf_p1_command_instrumentation = true
.const hal_platform_render_ball_effect_direct_perf = true
.const hal_platform_character_sheet_begin_enabled = true
.const hal_platform_character_background_resync = true
.const hal_platform_player_magic_helpers_external = true
.const hal_platform_item_action_key_restores_bank = true
.const hal_platform_ego_holy_avenger_string_external = true
.const hal_platform_ego_ac_bonus_external = true
.const hal_platform_chargen_runtime_resync = true
#if C128_TEST_CHARGEN_CUTPOINT
.const hal_platform_chargen_cutpoint = C128_TEST_CHARGEN_CUTPOINT
#else
.const hal_platform_chargen_cutpoint = -1
#endif
.const hal_platform_wizard_entry_uses_overlay = 1
.const hal_platform_wizard_40col_resident_enabled = 0
.const hal_platform_wizard_reveal_uses_trampoline = 0
.const hal_platform_levelup_magic_uses_trampoline = true
#define HAL_PLATFORM_WIZARD_ENTRY_OVERLAY
#define HAL_PLATFORM_EGO_HOLY_AVENGER_STRING_EXTERNAL
#define HAL_PLATFORM_EGO_AC_BONUS_EXTERNAL
