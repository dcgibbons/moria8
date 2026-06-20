#importonce
// Commander X16 lifecycle policy.
//
// CX16 bring-up currently keeps all runtime code resident in fixed RAM and has
// no IRQ, overlay, or bank-resync machinery wired into shared gameplay.

.const hal_platform_reassert_before_message_render = 0
.const hal_platform_restore_tier_after_overlay = 0
.const hal_platform_string_bank_load_invalidates_tier = 0
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
.const hal_platform_wizard_40col_resident_enabled = 0
.const hal_platform_wizard_reveal_uses_trampoline = 0
.const hal_platform_levelup_magic_uses_trampoline = 0
.const hal_platform_title_sysinfo_80col = 1
.const hal_platform_title_sysinfo_sx64_probe = 0
.const hal_platform_player_move_diag_labels = 0
.const hal_platform_describe_look_masks_irq = 0
.const hal_platform_game_loop_runtime_resync = 0
.const hal_platform_game_loop_main_loop_begin = 0
.const hal_platform_game_loop_restore_generation_overlay = 0
.const hal_platform_game_loop_save_clears_screen = 1
.const hal_platform_game_loop_save_return_view = 0
.const hal_platform_game_loop_run_stop_reset_input = 0
.const hal_platform_game_loop_scroll_delta_render = 0
.const hal_platform_game_loop_item_actions_trampolined = 0
.const hal_platform_overlay_count = 0
.const hal_platform_overlay_state_external = 0
.const hal_platform_overlay_force_reload = 0
.const hal_platform_overlay_tier_cache_guard = 0
.const hal_platform_overlay_cache_enabled = 0
.const hal_platform_overlay_reu_stash_enabled = 0
.const hal_platform_overlay_prompt_program_media = 0
.const hal_platform_overlay_cpu_port_dma_bank = 0
.const hal_platform_item_prompt_overlay_runtime = 0
.const hal_platform_item_prompt_reload_installs_irq = 0
.const hal_platform_item_prompt_reload_resync = 0
.const hal_platform_equip_prepare_key_before_display = 0
.const hal_platform_monster_bank1_tier_names = 0
.const hal_platform_monster_hidden_name_pool = 0
.const hal_platform_monster_cpu_port_bank = 0
.const hal_platform_monster_overlay_stale_name = 0
.const hal_platform_monster_stale_tier_reload = 0
