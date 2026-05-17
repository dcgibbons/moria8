#importonce
// C128 lifecycle HAL policy constants.

.const hal_platform_reassert_before_message_render = true
.const hal_platform_restore_tier_after_overlay = false
.const hal_platform_mark_modal_restore_perf = true
.const hal_platform_perf_p1_command_instrumentation = true
.const hal_platform_render_ball_effect_direct_perf = true
.const hal_platform_character_sheet_begin_enabled = true
.const hal_platform_wizard_entry_uses_overlay = 1
.const hal_platform_wizard_40col_resident_enabled = 0
.const hal_platform_wizard_reveal_uses_trampoline = 0
.const hal_platform_levelup_magic_uses_trampoline = true
#define HAL_PLATFORM_WIZARD_ENTRY_OVERLAY
