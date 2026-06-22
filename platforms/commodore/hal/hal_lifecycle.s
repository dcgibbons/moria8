#importonce
// Lifecycle contract.
//
// Required exports per platform:
//   hal_platform_init_early
//   hal_platform_init_runtime
//   hal_platform_main_loop_begin
//   hal_platform_vector_reassert
//   hal_platform_runtime_resync
//   hal_platform_character_sheet_begin
//   hal_platform_shutdown
//   hal_platform_panic
//
// Carry clear = success. Carry set = failure, A = HAL_STATUS_*.
// Each platform file must document register and zero-page clobbers locally.
//
// Service contracts:
// - hal_platform_init_early: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; IRQ state platform-owned; runtime RAM visibility.
// - hal_platform_init_runtime: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; installs runtime-visible machine state.
// - hal_platform_main_loop_begin: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; reasserts state needed before command polling.
// - hal_platform_vector_reassert: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; reasserts runtime vectors after OS-visible paths.
// - hal_platform_runtime_resync: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; restores display/banking state after OS calls.
// - hal_platform_character_sheet_begin: input none; output C=0 success/C=1
//   A=status; clobbers A/X/Y allowed; reasserts platform state needed before
//   character-sheet rendering and owns platform-specific test instrumentation.
// - hal_platform_shutdown: input none; output ignored; clobbers A/X/Y allowed;
//   returns platform to a safe OS-visible state when possible.
// - hal_platform_panic: input A=status; output does not promise return;
//   clobbers all volatile state; may force OS-visible diagnostics.
//
// Policy constants:
// - hal_platform_reassert_before_message_render: boolean; true when the
//   platform must reassert runtime vectors/state before message rendering.
// - hal_platform_restore_tier_after_overlay: boolean; true when modal overlay
//   dismissal must restore the live dungeon tier before gameplay redraw.
// - hal_platform_mark_modal_restore_perf: boolean; true when modal restore
//   should mark the PERF_P1 modal-restore reason before viewport rendering.
// - hal_platform_render_ball_effect_direct_perf: boolean; true when PERF_P1
//   ball-spell effect rendering should use the platform's direct effect tail.
// - hal_platform_character_sheet_begin_enabled: boolean; true when the
//   platform exports and requires hal_platform_character_sheet_begin before
//   character-sheet rendering.
// - hal_platform_title_sysinfo_80col: boolean; true when title sysinfo uses
//   the 80-column machine-label/centering path.
// - hal_platform_title_sysinfo_sx64_probe: boolean; true when title sysinfo
//   should classify SX-64 by the cached KERNAL revision byte.
// - hal_platform_player_move_diag_labels: boolean; true when movement emits
//   product runtime diagnostic labels for platform smoke tests.
// - hal_platform_describe_look_masks_irq: boolean; true when the look/describe
//   message path must mask IRQs while printing the inline object description.
// - hal_platform_turn_monster_ai: boolean; true when shared turn processing
//   should run monster AI after player-action effects.
// - hal_platform_turn_word_recall: boolean; true when shared turn processing
//   owns word-of-recall level transitions.
// - hal_platform_item_prompt_overlay_runtime: boolean; true when filtered
//   item prompts can be invoked from reloadable product overlay code.
// - hal_platform_item_prompt_reload_installs_irq: boolean; true when reloading
//   an item prompt caller overlay must reinstall runtime IRQ vectors.
// - hal_platform_item_prompt_reload_resync: boolean; true when reloading an
//   item prompt caller overlay must resync platform runtime state.
// - hal_platform_equip_prepare_key_before_display: boolean; true when the
//   equipment modal must prepare the dismiss key before drawing the view.
