; state.inc — Resident BSS layout (ORG BSS_BASE = 0x6A00) and fixed ABI/RAM symbols.
;
; Include at the END of main.asm AFTER SAVEBIN "MORIA8.COM", ... so BSS symbols
; appear in main.sym / main_exp.inc without emitting BSS padding into MORIA8.COM.

    IFNDEF CORE_Z80_STATE_INC
    DEFINE CORE_Z80_STATE_INC 1

    ORG BSS_BASE

    EXPORT bss_start
bss_start:

; ============================================================
; Fixed 64-Byte ABI Block (0x6A00..0x6A3F)
; ============================================================
    EXPORT z80_state
z80_state:
abi_magic:              DS 4
abi_version:            DS 1
    EXPORT abi_monochrome
abi_monochrome:         DS 1
    EXPORT abi_current_overlay
abi_current_overlay:    DS 1
    EXPORT abi_overlay_depth
abi_overlay_depth:      DS 1
    EXPORT abi_rng_seed
abi_rng_seed:           DS 4
    EXPORT abi_entropy_poll
abi_entropy_poll:       DS 4
    EXPORT abi_turn
abi_turn:               DS 2
    EXPORT abi_game_flags
abi_game_flags:         DS 1
    EXPORT abi_player_x
abi_player_x:           DS 1
    EXPORT abi_player_y
abi_player_y:           DS 1
    EXPORT abi_player_dlvl
abi_player_dlvl:        DS 1
    EXPORT abi_player_lvl
abi_player_lvl:         DS 1
    EXPORT abi_player_hp
abi_player_hp:          DS 2
    EXPORT abi_player_mhp
abi_player_mhp:         DS 2
    EXPORT abi_player_mp
abi_player_mp:          DS 1
    EXPORT abi_player_mmp
abi_player_mmp:         DS 1
    EXPORT abi_hunger_state
abi_hunger_state:       DS 1
    EXPORT abi_mon_count
abi_mon_count:          DS 1
    EXPORT abi_item_count
abi_item_count:         DS 1
    EXPORT abi_view_x
abi_view_x:             DS 1
    EXPORT abi_view_y
abi_view_y:             DS 1
    EXPORT abi_light_rad
abi_light_rad:          DS 1
    EXPORT abi_death_source
abi_death_source:       DS 1
    EXPORT abi_save_drive
abi_save_drive:         DS 1
    EXPORT abi_program_drive
abi_program_drive:      DS 1
    EXPORT abi_last_bdos_err
abi_last_bdos_err:      DS 1
    EXPORT abi_esc_pending
abi_esc_pending:        DS 1
    EXPORT abi_term_mode
abi_term_mode:          DS 1
abi_reserved:           DS 23

    ASSERT (abi_magic - z80_state) == Z80_ABI_MAGIC
    ASSERT (abi_version - z80_state) == Z80_ABI_VERSION
    ASSERT (abi_monochrome - z80_state) == Z80_ABI_MONOCHROME
    ASSERT (abi_current_overlay - z80_state) == Z80_ABI_CURRENT_OVL
    ASSERT (abi_overlay_depth - z80_state) == Z80_ABI_OVL_DEPTH
    ASSERT (abi_rng_seed - z80_state) == Z80_ABI_RNG_SEED
    ASSERT (abi_entropy_poll - z80_state) == Z80_ABI_ENTROPY_POLL
    ASSERT (abi_turn - z80_state) == Z80_ABI_TURN
    ASSERT (abi_game_flags - z80_state) == Z80_ABI_GAME_FLAGS
    ASSERT (abi_player_x - z80_state) == Z80_ABI_PLAYER_X
    ASSERT (abi_player_y - z80_state) == Z80_ABI_PLAYER_Y
    ASSERT (abi_player_dlvl - z80_state) == Z80_ABI_PLAYER_DLVL
    ASSERT (abi_player_lvl - z80_state) == Z80_ABI_PLAYER_LVL
    ASSERT (abi_player_hp - z80_state) == Z80_ABI_PLAYER_HP
    ASSERT (abi_player_mhp - z80_state) == Z80_ABI_PLAYER_MHP
    ASSERT (abi_player_mp - z80_state) == Z80_ABI_PLAYER_MP
    ASSERT (abi_player_mmp - z80_state) == Z80_ABI_PLAYER_MMP
    ASSERT (abi_hunger_state - z80_state) == Z80_ABI_HUNGER_STATE
    ASSERT (abi_mon_count - z80_state) == Z80_ABI_MON_COUNT
    ASSERT (abi_item_count - z80_state) == Z80_ABI_ITEM_COUNT
    ASSERT (abi_view_x - z80_state) == Z80_ABI_VIEW_X
    ASSERT (abi_view_y - z80_state) == Z80_ABI_VIEW_Y
    ASSERT (abi_light_rad - z80_state) == Z80_ABI_LIGHT_RAD
    ASSERT (abi_death_source - z80_state) == Z80_ABI_DEATH_SOURCE
    ASSERT (abi_save_drive - z80_state) == Z80_ABI_SAVE_DRIVE
    ASSERT (abi_program_drive - z80_state) == Z80_ABI_PROGRAM_DRIVE
    ASSERT (abi_last_bdos_err - z80_state) == Z80_ABI_LAST_BDOS_ERR
    ASSERT (abi_esc_pending - z80_state) == Z80_ABI_ESC_PENDING
    ASSERT (abi_term_mode - z80_state) == Z80_ABI_TERM_MODE
    ASSERT (abi_reserved - z80_state) == Z80_ABI_RESERVED
    ASSERT ($ - z80_state) == Z80_STATE_SIZE

; ============================================================
; Overlay, Terminal, Input, Audio, & Asset Cache BSS
; ============================================================
ovl_stack:              DS OVL_STACK_MAX

screen_emit_row:        DS 1
screen_emit_col:        DS 1
screen_emit_sgr:        DS 1
screen_cursor_valid:    DS 1

    EXPORT sound_enabled
sound_enabled:          DS 1

; Huffman 2-record LRU cache (2 x 128 B record buffers + 6 B tags/state = 262 B)
huff_lru:
huff_lru_buf0:          DS CPM_RECORD_SIZE
huff_lru_buf1:          DS CPM_RECORD_SIZE
huff_lru_rec0:          DS 2
huff_lru_rec1:          DS 2
huff_lru_mru:           DS 1
huff_lru_flags:         DS 1
    ASSERT ($ - huff_lru) == 262

; ITEM.CAT 3-record LRU cache (3 x 128 B record buffers + 9 B tags/state = 393 B)
icat_lru:
icat_lru_buf0:          DS CPM_RECORD_SIZE
icat_lru_buf1:          DS CPM_RECORD_SIZE
icat_lru_buf2:          DS CPM_RECORD_SIZE
icat_lru_rec0:          DS 2
icat_lru_rec1:          DS 2
icat_lru_rec2:          DS 2
icat_lru_age0:          DS 1
icat_lru_age1:          DS 1
icat_lru_age2:          DS 1
    ASSERT ($ - icat_lru) == 393

; MORIA8.DAT compact TOC cache (4 B header + 41 x 3 B entries = 127 B)
    EXPORT dat_toc_cache
dat_toc_cache:          DS DAT_CACHE_SIZE
    ASSERT ($ - dat_toc_cache) == DAT_CACHE_SIZE

; ============================================================
; Save Format V2 Core Gameplay & World State BSS
; ============================================================
    EXPORT player_data
player_data:            DS PL_STRUCT_SIZE
    ASSERT ($ - player_data) == 114

    EXPORT player_background
player_background:      DS PL_BG_SIZE
    ASSERT ($ - player_background) == 160

; Save V2 32-byte gameplay state mirror ($40..$5F layout in platforms/shared/save.s)
    EXPORT zp_state
zp_state:
    EXPORT zp_turn
    EXPORT zp_turn_lo
zp_turn:
zp_turn_lo:             DS 1
    EXPORT zp_turn_hi
zp_turn_hi:             DS 1
    EXPORT zp_regen_frac
zp_regen_frac:          DS 1
    EXPORT zp_game_flags
zp_game_flags:          DS 1
    EXPORT zp_current_tier
zp_current_tier:        DS 1
    EXPORT zp_speed_tick
zp_speed_tick:          DS 1
    EXPORT zp_search_count
zp_search_count:        DS 1
    EXPORT zp_run_dir
zp_run_dir:             DS 1
    EXPORT zp_input_cmd
zp_input_cmd:           DS 1
    EXPORT zp_input_count
zp_input_count:         DS 1
    EXPORT zp_hunger_state
zp_hunger_state:        DS 1
    EXPORT zp_light_radius
zp_light_radius:        DS 1
    EXPORT zp_depth_feeling
zp_depth_feeling:       DS 1
    EXPORT zp_mon_count
zp_mon_count:           DS 1
    EXPORT zp_item_count
zp_item_count:          DS 1
    EXPORT zp_confuse_melee
zp_confuse_melee:       DS 1
    EXPORT zp_eff_poison
zp_eff_poison:          DS 1
    EXPORT zp_eff_blind
zp_eff_blind:           DS 1
    EXPORT zp_eff_confuse
zp_eff_confuse:         DS 1
    EXPORT zp_eff_paralyze
zp_eff_paralyze:        DS 1
    EXPORT zp_eff_speed
zp_eff_speed:           DS 1
    EXPORT zp_eff_protect
zp_eff_protect:         DS 1
    EXPORT zp_eff_invis
zp_eff_invis:           DS 1
    EXPORT zp_eff_infra
zp_eff_infra:           DS 1
    EXPORT zp_eff_resist
zp_eff_resist:          DS 1
    EXPORT zp_eff_bless
zp_eff_bless:           DS 1
    EXPORT zp_eff_hero
zp_eff_hero:            DS 1
    EXPORT zp_eff_regen
zp_eff_regen:           DS 1
    EXPORT eff_resist_cold_timer
eff_resist_cold_timer:  DS 1
    EXPORT zp_eff_see_inv
zp_eff_see_inv:         DS 1
    EXPORT zp_eff_word_recall
zp_eff_word_recall:     DS 1
    EXPORT zp_death_source
zp_death_source:        DS 1
    ASSERT ($ - zp_state) == ZP_STATE_SIZE

    EXPORT eff_fear_timer
eff_fear_timer:         DS 1

; Contiguous 272-byte inventory/equipment SoA block (exact Save V2 stream order)
    EXPORT inv_item_id
inv_item_id:            DS TOTAL_INV_SLOTS
    EXPORT inv_qty
inv_qty:                DS TOTAL_INV_SLOTS
    EXPORT inv_p1
inv_p1:                 DS TOTAL_INV_SLOTS
    EXPORT inv_to_hit
inv_to_hit:             DS TOTAL_INV_SLOTS
    EXPORT inv_to_dam
inv_to_dam:             DS TOTAL_INV_SLOTS
    EXPORT inv_to_ac
inv_to_ac:              DS TOTAL_INV_SLOTS
    EXPORT inv_flags
inv_flags:              DS TOTAL_INV_SLOTS
    EXPORT inv_ego
inv_ego:                DS TOTAL_INV_SLOTS
    EXPORT inv_end
inv_end:
    ASSERT (inv_end - inv_item_id) == (8 * TOTAL_INV_SLOTS)

    EXPORT id_known_bits
id_known_bits:          DS ID_KNOWN_BYTES
    ASSERT ($ - id_known_bits) == 47

; Contiguous 174-byte randomized item flavour shuffle tables
    EXPORT potion_shuffle
potion_shuffle:         DS FLAVOUR_POTION_COUNT
    EXPORT scroll_shuffle
scroll_shuffle:         DS FLAVOUR_SCROLL_COUNT
    EXPORT ring_shuffle
ring_shuffle:           DS FLAVOUR_RING_COUNT
    EXPORT wand_shuffle
wand_shuffle:           DS FLAVOUR_WAND_COUNT
    EXPORT staff_shuffle
staff_shuffle:          DS FLAVOUR_STAFF_COUNT
flavour_shuffle_end:
    ASSERT (flavour_shuffle_end - potion_shuffle) == FLAVOUR_COUNT

; Contiguous 1,024-byte Store + Home SoA block (exact Save V2 stream order)
    EXPORT si_item_id
si_item_id:             DS STORE_TOTAL_SLOTS
    EXPORT si_qty
si_qty:                 DS STORE_TOTAL_SLOTS
    EXPORT si_p1
si_p1:                  DS STORE_TOTAL_SLOTS
    EXPORT si_to_hit
si_to_hit:              DS STORE_TOTAL_SLOTS
    EXPORT si_to_dam
si_to_dam:              DS STORE_TOTAL_SLOTS
    EXPORT si_to_ac
si_to_ac:               DS STORE_TOTAL_SLOTS
    EXPORT si_meta
si_meta:                DS STORE_TOTAL_SLOTS
    EXPORT si_meta_hi
si_meta_hi:             DS STORE_TOTAL_SLOTS
    EXPORT store_inventory_data_end
store_inventory_data_end:
    ASSERT (store_inventory_data_end - si_item_id) == (8 * STORE_TOTAL_SLOTS)

; Contiguous 7-byte stairs & entry direction block
    EXPORT stairs_up_x
stairs_up_x:            DS 1
    EXPORT stairs_up_y
stairs_up_y:            DS 1
    EXPORT stairs_dn_x
    EXPORT stairs_dn1_x
stairs_dn_x:
stairs_dn1_x:           DS 1
    EXPORT stairs_dn_y
    EXPORT stairs_dn1_y
stairs_dn_y:
stairs_dn1_y:           DS 1
    EXPORT stairs_dn2_x
stairs_dn2_x:           DS 1
    EXPORT stairs_dn2_y
stairs_dn2_y:           DS 1
    EXPORT level_entry_dir
level_entry_dir:        DS 1
stairs_end:
    ASSERT (stairs_end - stairs_up_x) == 7

; Contiguous 127-byte room header + SoA block
    EXPORT room_count
room_count:             DS 1
    EXPORT room_x
room_x:                 DS MAX_ROOMS
    EXPORT room_y
room_y:                 DS MAX_ROOMS
    EXPORT room_w
room_w:                 DS MAX_ROOMS
    EXPORT room_h
room_h:                 DS MAX_ROOMS
    EXPORT room_lit
room_lit:               DS MAX_ROOMS
    EXPORT room_type
room_type:              DS MAX_ROOMS
room_end:
    ASSERT (room_end - room_count) == (1 + MAX_ROOMS * 6)

; Contiguous 49-byte trap header + SoA block
    EXPORT trap_count
trap_count:             DS 1
    EXPORT trap_x
trap_x:                 DS MAX_TRAPS
    EXPORT trap_y
trap_y:                 DS MAX_TRAPS
    EXPORT trap_type
trap_type:              DS MAX_TRAPS
trap_end:
    ASSERT (trap_end - trap_count) == (1 + MAX_TRAPS * 3)

; Active monster table (32 x 12 = 384 B)
    EXPORT monster_table
monster_table:          DS (MAX_MONSTERS * MONSTER_ENTRY_SIZE)
    EXPORT monster_table_end
monster_table_end:
    ASSERT (monster_table_end - monster_table) == 384

; Contiguous 49-byte door-state header + SoA block
    EXPORT door_state_count
door_state_count:       DS 1
    EXPORT door_state_x
door_state_x:           DS MAX_DOOR_STATES
    EXPORT door_state_y
door_state_y:           DS MAX_DOOR_STATES
    EXPORT door_state_val
door_state_val:         DS MAX_DOOR_STATES
door_state_end:
    ASSERT (door_state_end - door_state_count) == (1 + MAX_DOOR_STATES * 3)

; Creature SoA (40 x 29 = 1,160 B); first 230 B shared with hiscore_table
    EXPORT hiscore_table
    EXPORT cr_display
hiscore_table:
cr_display:             DS MAX_CREATURES
    EXPORT cr_color
cr_color:               DS MAX_CREATURES
    EXPORT cr_speed
cr_speed:               DS MAX_CREATURES
    EXPORT cr_mflags
cr_mflags:              DS MAX_CREATURES
    EXPORT cr_level
cr_level:               DS MAX_CREATURES
    EXPORT cr_hd_num
cr_hd_num:              DS MAX_CREATURES
    EXPORT cr_hd_sides
cr_hd_sides:            DS MAX_CREATURES
    EXPORT cr_ac
cr_ac:                  DS MAX_CREATURES
    EXPORT cr_sleep
cr_sleep:               DS MAX_CREATURES
    EXPORT cr_aaf
cr_aaf:                 DS MAX_CREATURES
    EXPORT cr_xp_lo
cr_xp_lo:               DS MAX_CREATURES
    EXPORT cr_xp_hi
cr_xp_hi:               DS MAX_CREATURES
    EXPORT cr_atk0_dice
cr_atk0_dice:           DS MAX_CREATURES
    EXPORT cr_atk0_sides
cr_atk0_sides:          DS MAX_CREATURES
    EXPORT cr_atk0_type
cr_atk0_type:           DS MAX_CREATURES
    EXPORT cr_atk1_type
cr_atk1_type:           DS MAX_CREATURES
    EXPORT cr_atk1_dice
cr_atk1_dice:           DS MAX_CREATURES
    EXPORT cr_atk1_sides
cr_atk1_sides:          DS MAX_CREATURES
    EXPORT cr_spell_chance
cr_spell_chance:        DS MAX_CREATURES
    EXPORT cr_spell_flags
cr_spell_flags:         DS MAX_CREATURES
    EXPORT cr_treasure
cr_treasure:            DS MAX_CREATURES
    EXPORT cr_atk2_type
cr_atk2_type:           DS MAX_CREATURES
    EXPORT cr_atk2_dice
cr_atk2_dice:           DS MAX_CREATURES
    EXPORT cr_atk2_sides
cr_atk2_sides:          DS MAX_CREATURES
    EXPORT cr_atk3_type
cr_atk3_type:           DS MAX_CREATURES
    EXPORT cr_atk3_dice
cr_atk3_dice:           DS MAX_CREATURES
    EXPORT cr_atk3_sides
cr_atk3_sides:          DS MAX_CREATURES
    EXPORT cr_spell_flags2
cr_spell_flags2:        DS MAX_CREATURES
    EXPORT cr_cdefense
cr_cdefense:            DS MAX_CREATURES
cr_soa_end:
    ASSERT (cr_soa_end - cr_display) == (MAX_CREATURES * 29)
    ASSERT (cr_soa_end - hiscore_table) >= HISCORE_TABLE_SIZE

; Contiguous 64-byte catalog species slot table + 832-byte tier name pool
    EXPORT cat_slot_id_lo
cat_slot_id_lo:         DS CAT_SLOTS
    EXPORT cat_slot_id_hi
cat_slot_id_hi:         DS CAT_SLOTS
    EXPORT cat_slot_id_end
cat_slot_id_end:
    ASSERT (cat_slot_id_end - cat_slot_id_lo) == (CAT_SLOTS * 2)

    EXPORT tier_name_pool
tier_name_pool:         DS (TIER_NAME_COUNT * TIER_NAME_SIZE)
    EXPORT tier_name_pool_end
tier_name_pool_end:
    ASSERT (tier_name_pool_end - tier_name_pool) == 832

    EXPORT town_name_pool
town_name_pool:         DS (TOWN_CREATURE_COUNT * TIER_NAME_SIZE)
    ASSERT town_name_pool == tier_name_pool_end
    ASSERT ($ - town_name_pool) == 208

; Floor item SoA + sidecars + glyphs (252 + 168 + 12 = 432 B)
    EXPORT fi_item_id
fi_item_id:             DS MAX_FLOOR_ITEMS
    EXPORT fi_x
fi_x:                   DS MAX_FLOOR_ITEMS
    EXPORT fi_y
fi_y:                   DS MAX_FLOOR_ITEMS
    EXPORT fi_qty
fi_qty:                 DS MAX_FLOOR_ITEMS
    EXPORT fi_p1
fi_p1:                  DS MAX_FLOOR_ITEMS
    EXPORT fi_meta
fi_meta:                DS MAX_FLOOR_ITEMS
    ASSERT ($ - fi_item_id) == (MAX_FLOOR_ITEMS * 6)

    EXPORT fi_to_hit
fi_to_hit:              DS MAX_FLOOR_ITEMS
    EXPORT fi_to_dam
fi_to_dam:              DS MAX_FLOOR_ITEMS
    EXPORT fi_to_ac
fi_to_ac:               DS MAX_FLOOR_ITEMS
    EXPORT fi_meta_hi
fi_meta_hi:             DS MAX_FLOOR_ITEMS
    EXPORT fi_end
fi_end:
    ASSERT ($ - fi_item_id) == (MAX_FLOOR_ITEMS * 10)

    EXPORT glyph_x
glyph_x:                DS MAX_GLYPHS
    EXPORT glyph_y
glyph_y:                DS MAX_GLYPHS
    EXPORT glyph_active
glyph_active:           DS MAX_GLYPHS
    ASSERT ($ - glyph_x) == (MAX_GLYPHS * 3)

; Monster memory recall array (279 * 4 = 1,116 B)
    EXPORT recall_data
    EXPORT recall_data_start
recall_data:
recall_data_start:      DS RECALL_DATA_SIZE
    EXPORT recall_data_end
recall_data_end:
    ASSERT (recall_data_end - recall_data) == 1116

; 8 x 80 message history ring buffer (640 B)
    EXPORT msg_history
msg_history:            DS MSG_HIST_BYTES
msg_history_end:
    ASSERT (msg_history_end - msg_history) == 640

; ============================================================
; Runtime Core Flags, Store, Catalog, Combat, UI & Scratch BSS
; ============================================================
    EXPORT hal_layout_visibility_force_redraw
hal_layout_visibility_force_redraw: DS 1
    EXPORT save_slot_selected
save_slot_selected:     DS 1
    EXPORT hiscore_count
hiscore_count:          DS 1
    EXPORT active_dungeon_count
active_dungeon_count:   DS 1
    EXPORT zp_ui_dirty
zp_ui_dirty:            DS 1
    EXPORT zp_msg_flags
zp_msg_flags:           DS 1
    EXPORT regen_frac_lo
regen_frac_lo:          DS 1

    EXPORT hg_kicked
hg_kicked:              DS STORE_COUNT
    EXPORT item_cur_page
item_cur_page:          DS 1
    EXPORT inven_weight_lo
inven_weight_lo:        DS 1
    EXPORT inven_weight_hi
inven_weight_hi:        DS 1

; Item add / staging parameters (shared by stores, home, pickup, drop)
    EXPORT fi_add_x
fi_add_x:               DS 1
    EXPORT fi_add_y
fi_add_y:               DS 1
    EXPORT fi_add_id
fi_add_id:              DS 1
    EXPORT fi_add_qty
fi_add_qty:             DS 1
    EXPORT fi_add_qty_hi
fi_add_qty_hi:          DS 1
    EXPORT fi_add_p1
fi_add_p1:              DS 1
    EXPORT fi_add_to_hit
fi_add_to_hit:          DS 1
    EXPORT fi_add_to_dam
fi_add_to_dam:          DS 1
    EXPORT fi_add_to_ac
fi_add_to_ac:           DS 1
    EXPORT fi_add_flags
fi_add_flags:           DS 1
    EXPORT fi_add_ego
fi_add_ego:             DS 1

    EXPORT item_name_decode_buf
item_name_decode_buf:   DS ITEM_NAME_DECODE_BUF_SIZE

; ITEM.CAT cold reader state and decoded fields
    EXPORT icat_sel_id
icat_sel_id:            DS 2
    EXPORT icat_cached_id
icat_cached_id:         DS 2
    EXPORT icat_rec_0
icat_rec_0:             DS 1
    EXPORT icat_rec_1
icat_rec_1:             DS 1
    EXPORT icat_rec_2
icat_rec_2:             DS 1
    EXPORT icat_rec_3
icat_rec_3:             DS 1
    EXPORT icat_cost_lo
icat_cost_lo:           DS 1
    EXPORT icat_cost_hi
icat_cost_hi:           DS 1
    EXPORT icat_weight_lo
icat_weight_lo:         DS 1
    EXPORT icat_weight_hi
icat_weight_hi:         DS 1
    EXPORT icat_dmg_dice
icat_dmg_dice:          DS 1
    EXPORT icat_dmg_sides
icat_dmg_sides:         DS 1
    EXPORT icat_flags_0
icat_flags_0:           DS 1
    EXPORT icat_flags_1
icat_flags_1:           DS 1
    EXPORT icat_flags_2
icat_flags_2:           DS 1
    EXPORT icat_flags_3
icat_flags_3:           DS 1
    EXPORT icat_p1_lo
icat_p1_lo:             DS 1
    EXPORT icat_p1_hi
icat_p1_hi:             DS 1
    EXPORT icat_tohit
icat_tohit:             DS 1
    EXPORT icat_todam
icat_todam:             DS 1
    EXPORT icat_toac
icat_toac:              DS 1
    EXPORT icat_ego_cost_lo
icat_ego_cost_lo:       DS 1
    EXPORT icat_ego_cost_hi
icat_ego_cost_hi:       DS 1
icat_stream_byte_off:   DS 2
icat_cur_byte:          DS 1
icat_bits_left:         DS 1
icat_outer_byte_off:    DS 2
icat_outer_byte:        DS 1
icat_outer_bits:        DS 1
icat_str_id:            DS 2
icat_skip_cnt:          DS 1
icat_code:              DS 2
icat_sym_idx:           DS 1
icat_bit_len:           DS 1
icat_dst_ptr:           DS 2
icat_dst_rem:           DS 1

; item_desc staged fields
    EXPORT itemdesc_item_id
itemdesc_item_id:       DS 1
    EXPORT itemdesc_qty
itemdesc_qty:           DS 1
    EXPORT itemdesc_p1
itemdesc_p1:            DS 1
    EXPORT itemdesc_to_hit
itemdesc_to_hit:        DS 1
    EXPORT itemdesc_to_dam
itemdesc_to_dam:        DS 1
    EXPORT itemdesc_to_ac
itemdesc_to_ac:         DS 1
    EXPORT itemdesc_flags
itemdesc_flags:         DS 1
    EXPORT itemdesc_ego
itemdesc_ego:           DS 1

; Player passive flags, wield cache, combat accumulators, stat residuals
    EXPORT player_pflags
player_pflags:          DS 1
    EXPORT player_pflags2
player_pflags2:         DS 1
    EXPORT player_curse_flags
player_curse_flags:     DS 1
    EXPORT player_sust_mask
player_sust_mask:       DS 1
    EXPORT wield_weight_lo
wield_weight_lo:        DS 1
    EXPORT wield_weight_hi
wield_weight_hi:        DS 1
    EXPORT wield_dmg_packed
wield_dmg_packed:       DS 1
    EXPORT wield_missile_type
wield_missile_type:     DS 1
    EXPORT wield_flags_0
wield_flags_0:          DS 1
    EXPORT wield_flags_1
wield_flags_1:          DS 1
    EXPORT wield_flags_2
wield_flags_2:          DS 1
    EXPORT wield_flags_3
wield_flags_3:          DS 1
    ASSERT ($ - player_pflags) == 12
    EXPORT pcc_eq_tohit
pcc_eq_tohit:           DS 1
    EXPORT pcc_eq_todam
pcc_eq_todam:           DS 1
    EXPORT pcc_eq_ac
pcc_eq_ac:              DS 1
pcc_ac_accum:           DS 1
    EXPORT player_stat_res
player_stat_res:        DS STAT_COUNT
    EXPORT player_eq_stat_mod
player_eq_stat_mod:     DS STAT_COUNT

; Message & status bar working state
msg_hist_idx:           DS 1
msg_hist_count_used:    DS 1
msg_row1_col:           DS 1
    EXPORT status_cache_valid
status_cache_valid:     DS 1
status_dirty_rows:      DS 1
status_prev_lvl:        DS 1
status_prev_dlvl:       DS 1
status_prev_stats:      DS STAT_COUNT
status_prev_hp:         DS 2
status_prev_mhp:        DS 2
status_prev_mp:         DS 1
status_prev_mmp:        DS 1
status_prev_ac:         DS 1
status_prev_gold:       DS 3
status_prev_hunger:     DS 1
status_prev_state:      DS 1

; ============================================================
; Shared Line / Formatting / Scratch Buffers
; ============================================================
    EXPORT line_buf
line_buf:               DS 82
    EXPORT temp_str_buf
temp_str_buf:           DS 82
    EXPORT bss_scratch
bss_scratch:            DS 64

; viewport_render fast-path working scalars (resident-internal)
vr_any_glyph:           DS 1
vr_map_y:               DS 1
vr_row_map_ptr:         DS 2
vr_end_e:               DS 1
vr_cur_cell:            DS 1
vr_rows_rem:            DS 1
vr_pl_in_view:          DS 1
vr_pl_same:             DS 1
vr_pl_old_attr:         DS 1
vr_pl_char_ptr:         DS 2
vr_tmp_x:               DS 1

; M3 Turn/Render, Run/Rest, Feature/Chest/UI/Death shared BSS scalars
    EXPORT turn_scene_dirty
turn_scene_dirty:       DS 1
    EXPORT zp_disturb
zp_disturb:             DS 1
    EXPORT zp_dirty_count
zp_dirty_count:         DS 1
    EXPORT vis_room_revealed
vis_room_revealed:      DS 1
    EXPORT vis_cached_room_idx
vis_cached_room_idx:    DS 1
    EXPORT auto_rest_active
auto_rest_active:       DS 1
    EXPORT auto_rest_turns
auto_rest_turns:        DS 1
    EXPORT levelup_magic_pending
levelup_magic_pending:  DS 1
    EXPORT run_flags
run_flags:              DS 1
    EXPORT run_prev_dir
run_prev_dir:           DS 1
    EXPORT run_count
run_count:              DS 1
    ASSERT (run_count + 1 - turn_scene_dirty) == 11
    EXPORT look_cursor_x
look_cursor_x:          DS 1
    EXPORT look_cursor_y
look_cursor_y:          DS 1
    EXPORT df_target_x
df_target_x:            DS 1
    EXPORT df_target_y
df_target_y:            DS 1
    EXPORT df_dir_idx
df_dir_idx:             DS 1
    EXPORT df_found
df_found:               DS 1
    EXPORT df_search_chance
df_search_chance:       DS 1
    EXPORT df_death_source
df_death_source:        DS 1
    EXPORT df_death_hstr
df_death_hstr:          DS 1
    EXPORT df_disarm_chance
df_disarm_chance:       DS 1
    EXPORT df_disarm_trap_idx
df_disarm_trap_idx:     DS 1
    EXPORT df_disarm_total
df_disarm_total:        DS 1
    EXPORT df_disarm_base
df_disarm_base:         DS 1
    EXPORT df_tile_tmp
df_tile_tmp:            DS 1
    EXPORT chest_pending_summons
chest_pending_summons:  DS 1
    EXPORT chest_summon_x
chest_summon_x:         DS 1
    EXPORT chest_summon_y
chest_summon_y:         DS 1
    EXPORT sr_room_idx
sr_room_idx:            DS 1
    EXPORT sr_count
sr_count:               DS 1
    EXPORT sr_mode
sr_mode:                DS 1
    EXPORT sr_fixed_type
sr_fixed_type:          DS 1
    EXPORT death_cause_buf
death_cause_buf:        DS 32

; ============================================================
; M4 Monster, Combat, Detection, Catalog, & Spell Cross-Overlay BSS
; ============================================================
; Invulnerability effect timer (complementing zp_eff_* / eff_fear_timer)
    EXPORT eff_invuln_timer
eff_invuln_timer:       DS 1

; Monster death drop queue (MON-014: max 4 staged kills per command)
    EXPORT md_queue_count
md_queue_count:         DS 1
    EXPORT md_queue_flags
md_queue_flags:         DS MD_QUEUE_MAX
    EXPORT md_queue_x
md_queue_x:             DS MD_QUEUE_MAX
    EXPORT md_queue_y
md_queue_y:             DS MD_QUEUE_MAX

; Detection & visibility state
    EXPORT eff_detect_timer
eff_detect_timer:       DS 1
    EXPORT eff_detect_evil_mode
eff_detect_evil_mode:   DS 1
    EXPORT muv_clear_detected
muv_clear_detected:     DS 1
    EXPORT muv_changed
muv_changed:            DS 1

; Monster AI / attack / magic / spawn handoff scalars
    EXPORT zp_mon_idx
zp_mon_idx:             DS 1
    EXPORT zp_mon_type
zp_mon_type:            DS 1
    EXPORT me_any_hit
me_any_hit:             DS 1
    EXPORT me_hit_verb
me_hit_verb:            DS 1
    EXPORT zp_mon_x
zp_mon_x:               DS 1
    EXPORT zp_mon_y
zp_mon_y:               DS 1
    EXPORT zp_mon_flags
zp_mon_flags:           DS 1
    EXPORT mat_action_dirty
mat_action_dirty:       DS 1
    EXPORT mat_force_new_dirty
mat_force_new_dirty:    DS 1
    EXPORT mat_fast
mat_fast:               DS 1
    EXPORT mat_turn_mod
mat_turn_mod:           DS 4
    EXPORT mfa_x
mfa_x:                  DS 1
    EXPORT mfa_y
mfa_y:                  DS 1
    EXPORT ms_spawn_x
ms_spawn_x:             DS 1
    EXPORT ms_spawn_y
ms_spawn_y:             DS 1

; Monster catalog & recall cursors
    EXPORT cat_id_lo
cat_id_lo:              DS 1
    EXPORT cat_id_hi
cat_id_hi:              DS 1
    EXPORT cat_slot
cat_slot:               DS 1
    EXPORT cat_level_adj
cat_level_adj:          DS 1
    EXPORT recall_query_sc
recall_query_sc:        DS 1
    EXPORT recall_last_sc
recall_last_sc:         DS 1
    EXPORT recall_last_cat_lo
recall_last_cat_lo:     DS 1
    EXPORT recall_last_cat_hi
recall_last_cat_hi:     DS 1

; Player combat, item-selection, spell-cast & projectile handoff
    EXPORT cmb_target_x
cmb_target_x:           DS 1
    EXPORT cmb_target_y
cmb_target_y:           DS 1
    EXPORT cmb_slot
cmb_slot:               DS 1
    EXPORT cmb_type
cmb_type:               DS 1
    EXPORT cmb_damage
cmb_damage:             DS 1
    EXPORT cmb_dead
cmb_dead:               DS 1
    EXPORT cmb_any_hit
cmb_any_hit:            DS 1
    EXPORT cmb_hit_count
cmb_hit_count:          DS 1
    EXPORT cmb_blow_count
cmb_blow_count:         DS 1
    EXPORT cmb_total_tohit
cmb_total_tohit:        DS 1
    EXPORT cmb_target_lit
cmb_target_lit:         DS 1

    EXPORT piw_slot
piw_slot:               DS 1
    EXPORT piw_equip
piw_equip:              DS 1
    EXPORT piw_item_id
piw_item_id:            DS 1
    EXPORT piw_ego
piw_ego:                DS 1
    EXPORT piw_flags
piw_flags:              DS 1
    EXPORT piw_recalc_pending
piw_recalc_pending:     DS 1
    EXPORT piw_filter
piw_filter:             DS 1
    EXPORT piw_visible_count
piw_visible_count:      DS 1
    EXPORT piw_visible_slots
piw_visible_slots:      DS TOTAL_INV_SLOTS

    EXPORT pm_spell_type
pm_spell_type:          DS 1
    EXPORT pm_spell_idx
pm_spell_idx:           DS 1
    EXPORT pm_mode
pm_mode:                DS 1
    EXPORT pm_book_idx
pm_book_idx:            DS 1
    EXPORT pm_book_slot
pm_book_slot:           DS 1
    EXPORT pm_spell_count
pm_spell_count:         DS 1
    EXPORT pm_spell_list
pm_spell_list:          DS 16

    EXPORT ball_harm
ball_harm:              DS 1
    EXPORT proj_elem
proj_elem:              DS 1
    EXPORT proj_dmg
proj_dmg:               DS 1
    EXPORT proj_range
proj_range:             DS 1
    EXPORT proj_radius
proj_radius:            DS 1
    EXPORT proj_dir
proj_dir:               DS 1
    EXPORT proj_x
proj_x:                 DS 1
    EXPORT proj_y
proj_y:                 DS 1
    EXPORT eff_arg0
eff_arg0:               DS 1
    EXPORT eff_arg1
eff_arg1:               DS 1
    EXPORT eff_arg2
eff_arg2:               DS 1
    EXPORT eff_arg3
eff_arg3:               DS 1

; Internal resident monster/AI scratch moved from code space into BSS (18 B)
_mc_sp_type:            DS 1
_mc_sp_slot:            DS 1
_mc_cat_level:          DS 1
_mc_frf_limit:          DS 1
_muv_type:              DS 1
_muv_dist:              DS 1
_muv_old_flags:         DS 1
_mai_stealth:           DS 1
_mai_moves:             DS 1
_mai_scene_dirty:       DS 1
_mai_old_x:             DS 1
_mai_old_y:             DS 1
_mai_tgt_x:             DS 1
_mai_tgt_y:             DS 1
_mai_tgt_tile:          DS 1
_mai_eat_slot:          DS 1
_mai_door_abs:          DS 1
    EXPORT light_tick_counter
light_tick_counter:     DS 1
    EXPORT gl_move_relocated
gl_move_relocated:      DS 1
    EXPORT wizard_wall_walk_active
wizard_wall_walk_active: DS 1
    EXPORT level_force_regen
level_force_regen:      DS 1
    EXPORT legal_entry_mode
legal_entry_mode:       DS 1
    EXPORT disk_setup_done
disk_setup_done:        DS 1
    EXPORT game_loaded_flag
game_loaded_flag:       DS 1
    EXPORT chest_loot_pending
chest_loot_pending:     DS 1
    EXPORT chest_loot_x
chest_loot_x:           DS 1
    EXPORT chest_loot_y
chest_loot_y:           DS 1
    EXPORT chest_loot_flags
chest_loot_flags:       DS 1

    EXPORT bss_end
bss_end:
    ASSERT_BSS_FIT bss_start, bss_end

; ============================================================
; Fixed Above-BSS Memory Contract Symbols
; ============================================================
    EXPORT stack_bottom
stack_bottom            EQU STACK_BOTTOM
    EXPORT stack_canary
stack_canary            EQU STACK_CANARY_ADDR
    EXPORT stack_top
stack_top               EQU STACK_TOP
    EXPORT cpm_char_shadow
cpm_char_shadow         EQU CPM_CHAR_SHADOW_BASE
    EXPORT cpm_color_shadow
cpm_color_shadow        EQU CPM_COLOR_SHADOW_BASE
    EXPORT map_base
map_base                EQU MAP_BASE
    EXPORT fcb_dat
fcb_dat                 EQU FCB_DAT_ADDR
    EXPORT fcb_save
fcb_save                EQU FCB_SAVE_ADDR
    EXPORT fcb_tmp
fcb_tmp                 EQU FCB_TMP_ADDR
    EXPORT cpm_dma_buf
cpm_dma_buf             EQU CPM_DMA_BUF_BASE

    ENDIF
