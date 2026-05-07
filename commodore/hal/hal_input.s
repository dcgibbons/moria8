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
//   hal_input_modal_prepare
//   hal_input_modal_finish
//
// Platform code owns matrix scans, KERNAL input, debounce, shift state, and
// key-repeat policy. Common code consumes normalized key/command values.
