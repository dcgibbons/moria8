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
//   hal_screen_set_cursor
//   hal_screen_set_color
//   hal_screen_blank
//   hal_screen_unblank
//   hal_screen_begin_bulk
//   hal_screen_end_bulk
//
// Required constants per platform:
//   hal_screen_full_clear_uses_bulk
//   hal_screen_box_vertical_char
//
// Common code passes logical colors and screen intent. Platform code maps them
// to VIC-II, VDC, TED, or other display hardware.
//
// Service contracts:
// - hal_screen_init: input none; output C=0 success/C=1 A=status; clobbers
//   A/X/Y allowed; establishes platform text mode and default colors.
// - hal_screen_clear: input A=logical color or platform default; output C=status;
//   clobbers A/X/Y allowed; clears visible text and attributes.
// - hal_screen_clear_row: input Y=row, A=logical color; output C=status;
//   clobbers A/X allowed; leaves display mode unchanged.
// - hal_screen_put_char: input A=platform-normalized char; output C=status;
//   clobbers A/X/Y allowed; uses platform cursor/write position.
// - hal_screen_put_string: input pointer convention is platform-owned;
//   output C=status; clobbers A/X/Y allowed; zero terminator ends string.
// - hal_screen_put_char_at: input A=char, X=column, Y=row; output C=status;
//   clobbers A/X/Y allowed; writes one cell and matching attribute if needed.
// - hal_screen_set_cursor: input zp_cursor_row/zp_cursor_col; output
//   platform cursor/write pointers updated; clobbers A/X allowed, preserves Y
//   only where the platform backend documents that behavior.
// - hal_screen_set_color: input A=logical color; output C=status; clobbers A
//   allowed; maps logical color to platform attribute state.
// - hal_screen_blank: input none; output C=status; clobbers A allowed; hides
//   display during long operations without changing text buffers.
// - hal_screen_unblank: input none; output C=status; clobbers A allowed;
//   restores visible display after hal_screen_blank.
// - hal_screen_begin_bulk: input none; output C=status; clobbers A/X/Y allowed;
//   enters platform bulk-update mode if one exists.
// - hal_screen_end_bulk: input none; output C=status; clobbers A/X/Y allowed;
//   exits platform bulk-update mode and makes updates visible.
