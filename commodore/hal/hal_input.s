#importonce
// Input contract.
//
// Required exports per platform:
//   hal_input_get_key
//   hal_input_get_command
//   hal_input_get_text_char
//   hal_input_wait_release
//   hal_input_any_key_held
//   hal_input_run_cancel_check
//   hal_input_followup_prepare
//   hal_input_modal_prepare
//   hal_input_modal_finish
//
// Platform code owns matrix scans, KERNAL input, debounce, shift state, and
// key-repeat policy. Common code consumes normalized key/command values.
//
// Required constants per platform:
//   hal_input_kbdbuf_count
//   hal_input_modal_dismiss_uses_fast_key
//   hal_input_modal_escape_primary
//   hal_input_modal_escape_secondary
//   hal_input_flush_run_cancel_buffer
//   hal_input_help_footer_uses_esc_stop
//
// Service contracts:
// - hal_input_get_key: input none; output A=normalized key or 0, C=0 success;
//   clobbers X/Y allowed; must apply platform debounce policy.
// - hal_input_get_command: input none; output A=normalized game command or 0;
//   clobbers X/Y allowed; owns matrix/KERNAL translation.
// - hal_input_get_text_char: input none; output A=normalized text char or 0;
//   clobbers X/Y allowed; must not auto-repeat a held key unless requested.
// - hal_input_wait_release: input none; output no key held; clobbers A/X/Y
//   allowed; must include modifier keys that affect commands.
// - hal_input_any_key_held: input none; output A=0 none/nonzero held;
//   clobbers X/Y allowed; does not consume key events.
// - hal_input_run_cancel_check: input none; output C=1 cancel requested;
//   clobbers A/X/Y allowed; maps platform RUN/STOP or equivalent.
// - hal_input_followup_prepare: input none; output C=status; clobbers A/X/Y
//   allowed; prepares a secondary prompt after the initiating command key.
// - hal_input_modal_prepare: input none; output C=status; clobbers A/X/Y
//   allowed; enters modal prompt input policy.
// - hal_input_modal_finish: input none; output C=status; clobbers A/X/Y
//   allowed; restores normal gameplay input policy.
