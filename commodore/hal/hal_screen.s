#importonce
// Screen/color contract.
//
// Required exports per platform:
//   hal_screen_init
//   hal_screen_clear
//   hal_screen_clear_row
//   hal_screen_put_char
//   hal_screen_put_string
//   hal_screen_put_char_at
//   hal_screen_set_color
//   hal_screen_blank
//   hal_screen_unblank
//   hal_screen_begin_bulk
//   hal_screen_end_bulk
//
// Common code passes logical colors and screen intent. Platform code maps them
// to VIC-II, VDC, TED, or other display hardware.
