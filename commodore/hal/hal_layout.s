#importonce
// Layout/capability constant contract.
//
// Required constants per platform:
//   hal_layout_screen_cols
//   hal_layout_screen_rows
//   hal_layout_viewport_x
//   hal_layout_viewport_y
//   hal_layout_viewport_w
//   hal_layout_viewport_h
//   hal_layout_msg_row
//   hal_layout_status_row
//   hal_layout_input_row
//   hal_layout_map_cols
//   hal_layout_map_rows
//   hal_layout_store_price_col
//   hal_layout_equipment_title_col
//   hal_layout_equipment_footer_col
//
// These constants describe common layout intent. They are not hardware
// addresses and must match the platform's screen implementation. Platform code
// may still expose legacy SCREEN_* and VIEWPORT_* names during migration.
