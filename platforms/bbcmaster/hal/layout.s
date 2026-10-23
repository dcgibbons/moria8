#importonce
// BBC Master 128 layout HAL constants.
// Physical display is 80x24 in Mode 0 (640x192 in LYNNE $4400-$7FFF):
//   message rows 0-1, viewport rows 2-19, input row 20, status rows 21-23.

.const hal_layout_screen_cols = 80
.const hal_layout_screen_rows = 24
.const hal_layout_viewport_x = 1
.const hal_layout_viewport_y = 2
.const hal_layout_viewport_w = 78
.const hal_layout_viewport_h = 18
.const hal_layout_msg_row = 0
.const hal_layout_status_row = 21
.const hal_layout_input_row = 20
.const hal_layout_map_cols = 198
.const hal_layout_map_rows = 66
.const hal_layout_dungeon_max_rooms = 21
.const hal_layout_dungeon_overlap_local = 0
.const hal_layout_visibility_force_redraw = 1
// Door-scan scratch lives in main RAM at $0640-$0680 (65 B).
.const hal_layout_dungeon_door_scan_base = $0640
.const hal_layout_dungeon_door_scan_limit = $0681
.const hal_layout_store_price_col = 68
.const hal_layout_equipment_title_col = 35
.const hal_layout_equipment_footer_col = 33
.const hal_layout_equipment_row_stride = 1
.const hal_layout_equipment_wrap = 0
.const hal_layout_inventory_title_col = 35
.const hal_layout_inventory_footer_col = 33
.const hal_layout_inventory_select_col = 34
.const hal_layout_inventory_identify_col = 27
.const hal_layout_character_title_col = 33
.const hal_layout_character_wizard_col = 71
.const hal_layout_character_footer_col = 33
.const hal_layout_character_background_col = 22
.const hal_layout_character_col_l = 22
.const hal_layout_character_col_name = 28
.const hal_layout_character_col_mid = 39
.const hal_layout_character_col_r = 43
.const hal_layout_character_stat_col0 = 22
.const hal_layout_character_stat_col1 = 35
.const hal_layout_character_stat_col2 = 48
.const hal_layout_title_art_col_offset = 20
.const hal_layout_wizard_compact_menu = 1
.const hal_layout_wizard_40col_menu = 0
.const hal_layout_wizard_title_col = 37
.const hal_layout_wizard_menu_col = 30
.const hal_layout_wizard_footer_col = 34
.const hal_layout_status_row21_name_col = 1
.const hal_layout_status_row21_state_col = 0
.const hal_layout_status_row21_lv_col = 58
.const hal_layout_status_row21_dl_col = 66
.const hal_layout_status_row22_st_col = 1
.const hal_layout_status_row22_in_col = 14
.const hal_layout_status_row22_wi_col = 27
.const hal_layout_status_row22_dx_col = 40
.const hal_layout_status_row22_co_col = 53
.const hal_layout_status_row22_ch_col = 66
.const hal_layout_status_row23_hp_col = 1
.const hal_layout_status_row23_mp_col = 16
.const hal_layout_status_row23_ac_col = 31
.const hal_layout_status_row23_au_col = 44
.const hal_layout_status_row23_hunger_col = 63
.const hal_layout_status_row23_state_col = 70
.const hal_layout_status_searching_on_row21 = 0
.const hal_layout_status_searching_on_row23 = 1
// Title art loads into Bank 5 MAP_BASE ($8000) and renders via mmu_safe_map_read_ptr1.
.const hal_layout_title_load_uses_cache = 0
.const hal_layout_title_art_bank1_source = 1
.const hal_layout_title_reverse_space_attr = 0
#define HAL_LAYOUT_TITLE_ART_BANK1_SOURCE
#define HAL_LAYOUT_VISIBILITY_FORCE_REDRAW
