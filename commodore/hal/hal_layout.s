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
//   hal_layout_inventory_title_col
//   hal_layout_inventory_footer_col
//   hal_layout_inventory_select_col
//   hal_layout_inventory_identify_col
//   hal_layout_status_row21_name_col
//   hal_layout_status_row21_state_col
//   hal_layout_status_row21_lv_col
//   hal_layout_status_row21_dl_col
//   hal_layout_status_row22_st_col
//   hal_layout_status_row22_in_col
//   hal_layout_status_row22_wi_col
//   hal_layout_status_row22_dx_col
//   hal_layout_status_row22_co_col
//   hal_layout_status_row22_ch_col
//   hal_layout_status_row23_hp_col
//   hal_layout_status_row23_mp_col
//   hal_layout_status_row23_ac_col
//   hal_layout_status_row23_au_col
//   hal_layout_status_row23_hunger_col
//   hal_layout_status_row23_state_col
//   hal_layout_status_searching_on_row21
//   hal_layout_status_searching_on_row23
//
// These constants describe common layout intent. They are not hardware
// addresses and must match the platform's screen implementation. Platform code
// may still expose legacy SCREEN_* and VIEWPORT_* names during migration.
