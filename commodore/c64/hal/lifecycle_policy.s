#importonce
// C64 lifecycle HAL policy constants.

.const hal_platform_reassert_before_message_render = 0
.const hal_platform_restore_tier_after_overlay = 1
.const hal_platform_string_bank_load_invalidates_tier = 1
.const hal_platform_mark_modal_restore_perf = 0
.const hal_platform_perf_p1_command_instrumentation = 0
.const hal_platform_render_ball_effect_direct_perf = 0
.const hal_platform_character_sheet_begin_enabled = 0
.const hal_platform_character_background_resync = 0
.const hal_platform_player_magic_helpers_external = 0
.const hal_platform_item_action_key_restores_bank = 0
.const hal_platform_ego_holy_avenger_string_external = 0
.const hal_platform_ego_ac_bonus_external = 0
.const hal_platform_chargen_runtime_resync = 0
.const hal_platform_chargen_cutpoint = -1
.const hal_platform_wizard_entry_uses_overlay = 0
.const hal_platform_wizard_40col_resident_enabled = 1
.const hal_platform_wizard_reveal_uses_trampoline = 1
.const hal_platform_levelup_magic_uses_trampoline = 0
.const hal_platform_title_sysinfo_80col = 0
.const hal_platform_title_sysinfo_sx64_probe = 1
.const hal_platform_player_move_diag_labels = 0
.const hal_platform_describe_look_masks_irq = 0
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
.const hal_platform_item_prompt_overlay_runtime = 1
#else
.const hal_platform_item_prompt_overlay_runtime = 0
#endif
#if PLATFORM_PRODUCT_IRQ_VECTOR_RUNTIME
.const hal_platform_item_prompt_reload_installs_irq = 1
#else
.const hal_platform_item_prompt_reload_installs_irq = 0
#endif
.const hal_platform_item_prompt_reload_resync = 0
.const hal_platform_equip_prepare_key_before_display = 1
#define HAL_PLATFORM_WIZARD_40COL_RESIDENT
#define HAL_PLATFORM_WIZARD_REVEAL_TRAMPOLINE
#define HAL_PLATFORM_EGO_AC_BONUS_LOCAL
