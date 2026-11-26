; game_loop.asm — Resident Z80 Main Dungeon/Town Game Loop (M3)
;
; Exports: game_loop_enter, game_loop_redraw_all, game_loop_redraw_fresh,
;          game_loop_advance_turn, dir_dx, dir_dy
; Preserves IX and IY across every public entry point.

    EXPORT game_loop_enter
    EXPORT game_loop_cmd_ret
    EXPORT game_loop_run_dir_ret
    EXPORT _gl_enter_dungeon
    EXPORT game_loop_redraw_all
    EXPORT game_loop_redraw_fresh
    EXPORT game_loop_advance_turn
    EXPORT dir_dx
    EXPORT dir_dy

_tok_tbl:
    DB   " staircas", 0x80 | 'e'
    DB   "Search mode ", 0x80 | 'o'
    DB   "You", 0x80 | ' '
    DB   "scend th", 0x80 | 'e'
    DB   " here", 0x80 | '.'
    DB   " mode", 0x80 | '.'
    DB   "he", 0x80 | ' '
    DB   "ro", 0x80 | 'm'

_str_search_on:
    DB   0x02, "n.", 0
_str_search_off:
    DB   0x02, "ff.", 0
_str_no_stairs:
    DB   0x03, "see no stairs", 0x05, 0
_str_already_surface:
    DB   0x03, "are already at t", 0x07, "surface.", 0
_str_descend:
    DB   0x03, "de", 0x04, 0x01, ".", 0
_str_ascend:
    DB   0x03, "a", 0x04, 0x01, ".", 0
_str_slain:
    DB   0x03, "have been slain.", 0
_str_winner_save:
    DB   "Winner: Shift+Q to claim victory.", 0
_str_mono_on:
    DB   "Monoch", 0x08, "e", 0x06, 0
_str_color_on:
    DB   "Color", 0x06, 0
_str_adm3a_on:
    DB   "ADM-3A", 0x06, 0
_str_welcome:
    DB   "Welcome to Moria! ?=help. Shift+Q=quit.", 0

; Direction delta tables (0=N, 1=S, 2=W, 3=E, 4=NW, 5=NE, 6=SW, 7=SE)
dir_dx:
game_loop_dir_dx:
    DB   0, 0, -1, 1, -1, 1, -1, 1
dir_dy:
game_loop_dir_dy:
    DB   -1, 1, 0, 0, -1, -1, 1, 1

_gl_vi_keys:
    DB   "kjhlyubn82467913"

; ------------------------------------------------------------
; game_loop_enter — Enter active Town/Dungeon play loop
; ------------------------------------------------------------
game_loop_enter:
    PUSH IX
    PUSH IY

    LD   HL, zp_game_flags
    RES  0, (HL)
    XOR  A
    LD   (player_curse_flags), A
    CALL tramp_modal_recalc_equipment

    LD   HL, turn_scene_dirty
    LD   B, (muv_changed + 1 - turn_scene_dirty)
    ASSERT (muv_changed + 1 - turn_scene_dirty) < 256
    XOR  A
.z_lp:
    LD   (HL), A
    INC  HL
    DJNZ .z_lp

    LD   (regen_frac_lo), A
    LD   (zp_msg_flags), A
    LD   (light_tick_counter), A
    LD   (wizard_wall_walk_active), A
    LD   (recall_query_sc), A
    LD   (recall_last_sc), A
    LD   (recall_last_cat_lo), A
    LD   (recall_last_cat_hi), A

    LD   A, (level_entry_dir)
    CALL _gl_clr_level_latches

    LD   HL, player_data + PL_FLAGS
    RES  4, (HL)
    RES  5, (HL)

    CALL player_sync_to_abi
    CALL _gl_update_vis
    CALL game_loop_redraw_fresh

    LD   HL, game_loaded_flag
    LD   A, (HL)
    LD   (HL), 0
    OR   A
    JR   Z, .new_g
    LD   A, HSTR_SAVE_WELCOME
    CALL msg_print_huff
    JR   .gr_dn
.new_g:
    LD   HL, _str_welcome
    CALL _gl_msg_tok
.gr_dn:
    CALL game_loop_flush_at_player

.main_loop:
    LD   A, (abi_game_flags)
    RRA
    JP   C, _gl_handle_death

    LD   A, (levelup_magic_pending)
    OR   A
    JR   Z, .no_lvl_magic
    CALL tramp_spell_recalc_levelup
    CALL status_draw
    XOR  A
    LD   (levelup_magic_pending), A
.no_lvl_magic:

    LD   A, (auto_rest_active)
    OR   A
    JR   Z, .chk_run
    CALL _gl_rest_step
    JR   .main_loop

.chk_run:
    LD   A, (zp_run_dir)
    INC  A
    JR   Z, .chk_par
    CALL _gl_run_step
    JR   .main_loop

.chk_par:
    LD   A, (zp_eff_paralyze)
    OR   A
    JR   Z, .read_cmd
    CP   1
    JR   NZ, .par_skip
    XOR  A
    LD   (zp_eff_paralyze), A
    CALL msg_clear
    LD   A, HSTR_EFF_PARALYZE_END
    CALL msg_print_huff
    JR   .read_cmd
.par_skip:
    CALL game_loop_advance_turn
    JR   .main_loop

.read_cmd:
    CALL game_loop_flush_at_player
    CALL input_get_key
game_loop_cmd_ret:
    LD   B, A

    CALL _gl_key_to_dir
    JR   NC, .not_mv
    CALL _gl_begin_cmd
    CALL _gl_cmd_move
    JR   game_loop_enter.main_loop

.not_mv:
    CALL _gl_shifted_to_dir
    JR   NC, .not_sh
    CALL _gl_begin_cmd
    CALL _gl_start_run
    JR   game_loop_enter.main_loop

.not_sh:
    LD   HL, game_loop_enter.main_loop
    PUSH HL

    LD   HL, _gl_ui_tbl
    CALL _gl_lookup_word
    JR   NC, .chk_act
    CALL _gl_begin_cmd
    LD   HL, game_loop_redraw_fresh
    PUSH HL
    EX   DE, HL
    JP   (HL)

.chk_act:
    CALL _gl_lookup_word        ; HL already points to _gl_act_tbl!
    JR   NC, .chk_cmd
    CALL _gl_begin_cmd
    LD   A, (abi_player_dlvl)
    PUSH AF
    CALL _gl_call_de
    POP  BC
    JR   C, .act_ok
.act_ok_chk_dirty:
    LD   A, (hal_layout_visibility_force_redraw)
    LD   HL, turn_scene_dirty
    OR   (HL)
    RET  Z
    JP   game_loop_redraw_fresh
.act_ok:
    LD   A, (abi_game_flags)
    RRA
    RET  C
    LD   A, (abi_player_dlvl)
    CP   B
    JP   NZ, _gl_handle_dlvl_change
    LD   A, (level_force_regen)
    OR   A
    JP   NZ, _gl_handle_dlvl_change
    JP   _gl_search_turn_redraw

.chk_cmd:
    CALL _gl_lookup_word        ; HL already points to _gl_cmd_tbl!
    RET  NC
    CALL _gl_begin_cmd
_gl_call_de:
    EX   DE, HL
    JP   (HL)

_gl_begin_cmd:
    PUSH DE
    PUSH AF
    CALL msg_clear
    XOR  A
    LD   (zp_disturb), A
    POP  AF
    POP  DE
    RET

_gl_handle_death:
    CALL _gl_update_vis
    CALL game_loop_redraw_all
    LD   HL, _str_slain
    CALL _gl_msg_tok
    CALL msg_show_more
    CALL game_loop_flush_at_player
    CALL input_get_key
    CALL tramp_death_screen
_gl_exit_game:
    CALL screen_hard_clear
    POP  IY
    POP  IX
    RET

_gl_lookup_word:
    LD   A, (HL)
    INC  HL
    OR   A
    RET  Z
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    INC  HL
    CP   B
    JR   NZ, _gl_lookup_word
    SCF
    RET

_gl_ui_tbl:
    DB   'C'        : DW tramp_ui_character
    DB   'i'        : DW tramp_ui_inventory
    DB   'e'        : DW tramp_ui_equipment
    DB   '?'        : DW tramp_help_screen
    DB   'v'        : DW tramp_legal_sysinfo
    DB   'V'        : DW tramp_legal_sysinfo
    DB   0

_gl_act_tbl:
    DB   'o'        : DW tramp_actions_open
    DB   'c'        : DW tramp_actions_close
    DB   'D'        : DW tramp_actions_disarm
    DB   KEY_CTRL_B : DW tramp_actions_bash
    DB   '+'        : DW tramp_actions_tunnel
    DB   KEY_CTRL_D : DW tramp_actions_jam
    DB   'g'        : DW tramp_item_mgt_pickup
    DB   ','        : DW tramp_item_mgt_pickup
    DB   'w'        : DW tramp_item_mgt_wear
    DB   't'        : DW tramp_item_mgt_takeoff
    DB   'd'        : DW tramp_item_mgt_drop
    DB   'E'        : DW tramp_item_mgt_eat
    DB   'R'        : DW tramp_item_mgt_refuel
    DB   'F'        : DW tramp_item_mgt_fire
    DB   'T'        : DW tramp_item_mgt_throw
    DB   'q'        : DW tramp_items_quaff
    DB   'r'        : DW tramp_items_read
    DB   'a'        : DW tramp_items_aim
    DB   'z'        : DW tramp_items_use
    DB   'm'        : DW tramp_spell_cast
    DB   'p'        : DW tramp_spell_pray
    DB   'f'        : DW tramp_spell_gain
    DB   0

_gl_cmd_tbl:
    DB   '.'        : DW _gl_cmd_dot_run
    DB   '5'        : DW _gl_search_turn_redraw
    DB   KEY_CTRL_R : DW _gl_cmd_autorest
    DB   '#'        : DW _gl_cmd_toggle_search
    DB   's'        : DW _gl_cmd_search
    DB   '>'        : DW _gl_cmd_stairs_dn
    DB   '<'        : DW _gl_cmd_stairs_up
    DB   '/'        : DW _gl_cmd_recall
    DB   'x'        : DW tramp_ui_look
    DB   'X'        : DW _gl_cmd_exchange
    DB   KEY_CTRL_W : DW _gl_cmd_wizard
    DB   'S'        : DW _gl_cmd_save
    DB   '='        : DW _gl_cmd_mono
    DB   'Q'        : DW _gl_cmd_quit
    DB   0

_gl_cmd_recall:
    CALL tramp_ui_identify_sym
    RET  NC
    JP   game_loop_redraw_fresh

_gl_cmd_dot_run:
    CALL input_get_key
game_loop_run_dir_ret:
    CALL _gl_key_to_dir
    RET  NC
_gl_start_run:
    JP   tramp_modal_run_init

_gl_cmd_toggle_search:
    LD   HL, player_data + PL_FLAGS
    LD   A, (HL)
    XOR  PLF_SEARCHING
    LD   (HL), A
    AND  PLF_SEARCHING
    LD   HL, _str_search_on
    JR   NZ, .m
    LD   HL, _str_search_off
.m:
    CALL _gl_msg_tok
    JP   _gl_stat_flush

_gl_cmd_search:
    XOR  A
    CALL tramp_actions_search
    JP   _gl_search_turn_redraw

_gl_cmd_exchange:
    CALL tramp_modal_exchange_weapon
    RET  NC
    JP   _gl_search_turn_redraw

_gl_cmd_wizard:
    LD   A, (abi_player_dlvl)
    PUSH AF
    CALL tramp_help_wizard
    POP  BC
    RET  NC
    LD   A, (abi_player_dlvl)
    CP   B
    JR   NZ, .chg
    LD   A, (level_force_regen)
    OR   A
    JR   Z, .s
.chg:
    XOR  A
    LD   (level_force_regen), A
    LD   A, (abi_player_dlvl)
    OR   A
    JR   NZ, .d
    CALL _gl_enter_town
    JR   .s
.d:
    LD   A, (level_entry_dir)
    CALL _gl_enter_dungeon
.s:
    CALL _gl_vis_fresh
    LD   HL, line_buf
    LD   A, (HL)
    OR   A
    RET  Z
    CALL msg_print_str
    JP   game_loop_flush_at_player

_gl_cmd_save:
    LD   HL, zp_game_flags
    LD   A, (abi_game_flags)
    OR   (HL)
    AND  GAME_FLAG_WINNER
    JR   Z, .do_save
    LD   HL, _str_winner_save
    CALL msg_print_str
    JP   game_loop_flush_at_player
.do_save:
    CALL player_sync_to_abi
    CALL tramp_save_game
    JR   C, .cancel
    POP  HL
    JP   _gl_exit_game
.cancel:
    JP   game_loop_redraw_fresh

_gl_cmd_mono:
    LD   A, (abi_term_mode)
    OR   A
    JR   Z, .to_color
    LD   HL, abi_monochrome
    LD   A, (HL)
    OR   A
    JR   Z, .to_mono
    XOR  A
    LD   (abi_term_mode), A
    LD   (HL), 1
    LD   HL, _str_adm3a_on
    JR   .apply
.to_color:
    LD   A, 1
    LD   (abi_term_mode), A
    XOR  A
    LD   (abi_monochrome), A
    LD   HL, _str_color_on
    JR   .apply
.to_mono:
    LD   (HL), 1
    LD   HL, _str_mono_on
.apply:
    PUSH HL
    CALL game_loop_redraw_fresh
    POP  HL
    CALL _gl_msg_tok
    JP   game_loop_flush_at_player

_gl_cmd_quit:
    LD   HL, zp_game_flags
    LD   A, (abi_game_flags)
    OR   (HL)
    AND  GAME_FLAG_WINNER
    JR   NZ, .winner_retire
    LD   A, HSTR_QUIT_CONFIRM
    CALL msg_print_huff
    CALL game_loop_flush_at_player
    CALL input_get_key
    PUSH AF
    CALL msg_clear
    POP  AF
    AND  0xDF
    CP   'Y'
    RET  NZ
    POP  HL
    JP   _gl_exit_game
.winner_retire:
    POP  HL
    CALL tramp_death_royal
    LD   A, DEATH_ALIVE
    LD   (zp_death_source), A
    LD   (abi_death_source), A
    LD   (df_death_source), A
    CALL tramp_death_screen
    JP   _gl_exit_game

; ------------------------------------------------------------
; Turn / Redraw Helpers
; ------------------------------------------------------------
game_loop_advance_turn:
    CALL turn_post_action
    RET  C
_gl_redraw_after_turn:
    LD   A, (abi_game_flags)
    RRA
    RET  C
    CALL _gl_update_vis
    LD   A, (hal_layout_visibility_force_redraw)
    OR   A
    JP   NZ, game_loop_redraw_fresh
    LD   A, (turn_scene_dirty)
    LD   HL, vis_room_revealed
    OR   (HL)
    LD   HL, muv_changed
    OR   (HL)
    JP   NZ, game_loop_redraw_all
    CALL viewport_render
    CALL status_draw
    JP   game_loop_flush_at_player

_gl_search_turn_redraw:
    CALL _gl_turn_post_action_searchable
    RET  C
    JR   _gl_redraw_after_turn

_gl_turn_post_action_searchable:
    LD   A, (chest_pending_summons)
    LD   HL, md_queue_count
    OR   (HL)
    LD   HL, chest_loot_pending
    OR   (HL)
    CALL NZ, tramp_chest_fulfill_loot

    CALL turn_post_action
    RET  C
    LD   A, (player_data + PL_FLAGS)
    AND  PLF_SEARCHING
    RET  Z
    LD   A, (turn_scene_dirty)
    PUSH AF
    LD   A, 0xFF
    CALL tramp_actions_search
    CALL turn_post_action
    POP  BC
    RET  C
    LD   HL, turn_scene_dirty
    LD   A, (HL)
    OR   B
    LD   (HL), A
    RET

; ------------------------------------------------------------
; Movement & Step Triggers
; ------------------------------------------------------------
_gl_cmd_move:
    LD   B, A
    LD   A, (zp_eff_confuse)
    OR   A
    LD   A, B
    JR   Z, .dr
    LD   A, 8
    CALL rng_range
.dr:
    CALL _gl_try_move
    RET  NC
_gl_after_move_step:
    LD   A, (gl_move_relocated)
    OR   A
    JR   NZ, .reloc
    CALL _gl_stop_run
    JR   .turns
.reloc:
    LD   A, (abi_player_dlvl)
    OR   A
    JR   Z, .town_chk
    CALL _gl_step_post_move
    RET  C
    JR   NZ, .turns
    JR   .chk_run_aa
.town_chk:
    LD   A, (zp_run_dir)
    CP   0xFF
    JR   Z, .chk_ps
    CALL _gl_get_player_tile
    JR   C, .chk_run_aa
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_OPEN
    JR   NZ, .chk_run_aa
    CALL store_door_lookup
    CALL C, _gl_stop_run
.chk_run_aa:
    LD   A, (zp_run_dir)
    CP   0xFF
    JR   Z, .chk_ps
    CALL tramp_modal_run_area_affect
    CALL C, _gl_stop_run
.chk_ps:
    LD   A, (abi_player_dlvl)
    OR   A
    JR   Z, .turns
    LD   A, (player_data + PL_FLAGS)
    AND  PLF_SEARCHING
    JR   NZ, .turns
    CALL player_search_get_fos
    CP   2
    JR   C, .do_ps
    CALL rng_range
    OR   A
    JR   NZ, .turns
.do_ps:
    LD   A, 0xFF
    CALL tramp_actions_search
.turns:
    CALL _gl_turn_post_action_searchable
    RET  C
    CALL _gl_update_vis
    CALL game_loop_redraw_all
    LD   A, (gl_move_relocated)
    OR   A
    JR   Z, .ret_done
    LD   A, (abi_player_dlvl)
    OR   A
    CALL Z, _gl_check_town_door
.ret_done:
    LD   A, (gl_move_relocated)
    CP   1
    RET

_gl_step_post_move:
    CALL _gl_get_player_tile
    LD   (df_target_x), HL      ; L->df_target_x, H->df_target_y
    JR   C, .no
    AND  TILE_TYPE_MASK
    CP   TILE_TRAP
    JR   Z, .trig
    LD   A, (trap_count)
    OR   A
    JR   Z, .no
    LD   B, A
    EX   DE, HL                 ; E=px, D=py (preserved by map_get_tile)
    LD   HL, trap_x
.tlp:
    LD   A, (HL)
    CP   E
    JR   NZ, .tnx
    PUSH HL
    PUSH BC
    LD   BC, MAX_TRAPS
    ADD  HL, BC
    LD   A, (HL)
    POP  BC
    POP  HL
    CP   D
    JR   Z, .trig
.tnx:
    INC  HL
    DJNZ .tlp
.no:
    XOR  A
    RET
.trig:
    CALL _gl_stop_run
    LD   A, (abi_player_dlvl)
    PUSH AF
    CALL tramp_actions_trigger_trap
    POP  BC
    LD   A, (abi_game_flags)
    RRA
    JR   C, _gl_step_stop
    LD   A, (abi_player_dlvl)
    CP   B
    JR   NZ, _gl_handle_dlvl_change
    LD   A, (level_force_regen)
    OR   A
    JR   NZ, _gl_handle_dlvl_change
    LD   A, 1
    OR   A                      ; CF=0, NZ -> skip passive search after surviving trap
    RET
_gl_handle_dlvl_change:
    LD   A, (abi_player_dlvl)
    OR   A
    JR   NZ, .dng
    CALL _gl_enter_town
    JR   .vis
.dng:
    LD   A, (level_entry_dir)
    CALL _gl_enter_dungeon
.vis:
    CALL _gl_vis_fresh
_gl_step_stop:
    SCF
    RET

_gl_try_move:
    PUSH AF
    XOR  A
    LD   (gl_move_relocated), A
    POP  AF
    CALL _gl_step_coords_dir    ; B=ty, C=tx
    LD   A, C
    DEC  A
    CP   MAP_COLS - 2
    JR   NC, .blk
    LD   A, B
    DEC  A
    CP   MAP_ROWS - 2
    JR   NC, .blk
    CALL map_get_tile
    JR   C, .blk                ; OOB -> blocked
    LD   D, A
    BIT  0, A                   ; FLAG_OCCUPIED?
    JR   Z, .terrain
    CALL monster_find_at
    JR   C, .mon_hit
    ; Stale FLAG_OCCUPIED: clear flag and check terrain
    CALL _mc_tile_clr_occ
    LD   A, D
    JR   .terrain
.mon_hit:
    LD   A, (zp_run_dir)
    CP   0xFF
    JR   Z, .not_run
    LD   DE, MX_FLAGS
    ADD  HL, DE
    LD   A, (HL)
    AND  MF_VISIBLE
    JR   NZ, .blk               ; visible monster stops auto-run without attacking
    CALL _gl_stop_run           ; unseen monster ends run & triggers melee
.not_run:
    LD   A, (eff_fear_timer)
    OR   A
    JR   Z, .do_atk
    LD   A, HSTR_PTM_AFRAID
    CALL msg_print_huff
    SCF
    RET
.do_atk:
    CALL tramp_modal_player_attack
    SCF
    RET
.terrain:
    CALL tile_is_walkable_a
    JR   C, .step_ok
    LD   A, (abi_game_flags)
    AND  GAME_FLAG_WIZARD
    JR   Z, .blk
    LD   A, (wizard_wall_walk_active)
    OR   A
    JR   Z, .blk
.step_ok:
    LD   A, 1
    LD   (gl_move_relocated), A
    CALL _gl_set_player_pos
    SCF
    RET
.blk:
    LD   A, (zp_run_dir)
    CP   0xFF
    CALL Z, sound_bell
    OR   A
    RET

; Input: A = dir 0..7 -> B=ty, C=tx
_gl_step_coords_dir:
    LD   E, A
    LD   D, 0
    LD   HL, dir_dx
    ADD  HL, DE
    LD   A, (abi_player_x)
    ADD  A, (HL)
    LD   C, A
    LD   HL, dir_dy
    ADD  HL, DE
    LD   A, (abi_player_y)
    ADD  A, (HL)
    LD   B, A
    RET

_gl_get_player_tile:
    LD   HL, (abi_player_x)     ; L=x, H=y
    LD   C, L
    LD   B, H
    JP   map_get_tile

_gl_set_player_pos:
    LD   L, C
    LD   H, B
    LD   (abi_player_x), HL
    LD   (player_data + PL_MAP_X), HL
    RET

_gl_check_town_door:
    CALL _gl_get_player_tile
    JR   C, .nd
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_OPEN
    JR   NZ, .nd
    CALL store_door_lookup
    RET  NC
    CP   STORE_HOME
    JR   NZ, .st
    CALL tramp_home_enter
    JR   .ret
.st:
    CALL tramp_store_enter
.ret:
    CALL game_loop_redraw_fresh
    SCF
    RET
.nd:
    OR   A
    RET

; ------------------------------------------------------------
; CJS Auto-Run (TRN-006)
; ------------------------------------------------------------
_gl_run_step:
    CALL _gl_repeat_interrupted
    JR   NZ, _gl_stop_run
    LD   A, (run_count)
    CP   101
    JR   NC, _gl_stop_run
    LD   A, (zp_eff_confuse)
    OR   A
    JR   Z, .ok_dir
    LD   A, (run_count)
    OR   A
    JR   NZ, _gl_stop_run
    LD   A, 8
    CALL rng_range
    JR   .mv
.ok_dir:
    LD   A, (zp_run_dir)
.mv:
    CALL _gl_try_move
    JR   NC, _gl_stop_run

    LD   HL, run_count
    INC  (HL)
    CALL _gl_after_move_step
    RET  NC

_gl_stop_run:
    LD   A, 0xFF
    LD   (zp_run_dir), A
    XOR  A
    LD   (run_flags), A
    LD   (run_count), A
    RET

_gl_repeat_interrupted:
    CALL input_poll_key
    OR   A
    RET  NZ
    LD   A, (zp_msg_flags)
    LD   HL, zp_disturb
    OR   (HL)
    RET

; ------------------------------------------------------------
; Auto-Rest (TRN-014)
; ------------------------------------------------------------
_gl_cmd_autorest:
    CALL player_search_mode_off
    CALL _gl_stop_run
    CALL _gl_at_full_hp_mp
    JR   C, _gl_stat_flush
    LD   A, 1
    LD   (auto_rest_active), A
    LD   HL, player_data + PL_FLAGS
    SET  5, (HL)
    JR   _gl_stat_flush

_gl_rest_step:
    CALL _gl_repeat_interrupted
    JR   NZ, _gl_stop_rest
    CALL _gl_at_full_hp_mp
    JR   C, _gl_stop_rest
    JP   game_loop_advance_turn

_gl_stop_rest:
    XOR  A
    LD   (auto_rest_active), A
    LD   HL, player_data + PL_FLAGS
    RES  5, (HL)
_gl_stat_flush:
    CALL status_mark_dirty
    CALL status_draw
    JP   game_loop_flush_at_player

_gl_at_full_hp_mp:
    LD   HL, (player_data + PL_HP_LO)
    LD   DE, (player_data + PL_MHP_LO)
    OR   A
    SBC  HL, DE
    CCF
    RET  NC
    LD   A, (player_data + PL_SPELL_TYPE)
    INC  A
    DEC  A
    RET  Z
    LD   A, (player_data + PL_MANA)
    LD   HL, player_data + PL_MAX_MANA
    CP   (HL)
    CCF
    RET

; ------------------------------------------------------------
; Stairs '>' and '<'
; ------------------------------------------------------------
_gl_cmd_stairs_dn:
    LD   D, TILE_STAIRS_DN
    LD   HL, _str_no_stairs
    CALL _gl_require_tile
    RET  NC
    LD   HL, abi_player_dlvl
    INC  (HL)
    LD   A, (HL)
    LD   (player_data + PL_DLEVEL), A
    LD   HL, player_data + PL_MAX_DLVL
    CP   (HL)
    JR   C, .mx
    LD   (HL), A
.mx:
    XOR  A
    CALL _gl_finish_dng_stairs
    CALL msg_clear
    LD   HL, _str_descend
    CALL _gl_msg_tok
    JP   game_loop_flush_at_player

_gl_cmd_stairs_up:
    LD   D, TILE_STAIRS_UP
    LD   HL, _str_no_stairs
    CALL _gl_require_tile
    RET  NC
    LD   A, (abi_player_dlvl)
    OR   A
    LD   HL, _str_already_surface
    JP   Z, _gl_msg_tok
    LD   HL, abi_player_dlvl
    DEC  (HL)
    LD   A, (HL)
    LD   (player_data + PL_DLEVEL), A
    OR   A
    JR   NZ, .du
    CALL _gl_enter_town
    CALL _gl_vis_fresh
    JR   .up_msg
.du:
    LD   A, 1
    CALL _gl_finish_dng_stairs
.up_msg:
    CALL msg_clear
    LD   HL, _str_ascend
    CALL _gl_msg_tok
    JP   game_loop_flush_at_player
_gl_finish_dng_stairs:
    CALL _gl_enter_dungeon
_gl_vis_fresh:
    CALL _gl_update_vis
    JP   game_loop_redraw_fresh

_gl_require_tile:
    PUSH HL
    CALL _gl_get_player_tile
    POP  HL
    JR   C, .fail
    AND  TILE_TYPE_MASK
    CP   D
    SCF
    RET  Z
.fail:
    CALL _gl_msg_tok
    OR   A
    RET

; Expand phrase-tokenized string HL (0x01..0x0F -> _tok_tbl) into temp_str_buf & print
_gl_msg_tok:
    LD   DE, temp_str_buf
.lp:
    LD   A, (HL)
    INC  HL
    OR   A
    JR   Z, .dn
    CP   0x20
    JR   NC, .lit
    PUSH HL
    LD   HL, _tok_tbl
    LD   B, A
    JR   .nt
.skp:
    BIT  7, (HL)
    INC  HL
    JR   Z, .skp
.nt:
    DJNZ .skp
.cpy:
    LD   A, (HL)
    INC  HL
    BIT  7, A
    JR   NZ, .last
    LD   (DE), A
    INC  DE
    JR   .cpy
.last:
    AND  0x7F
    POP  HL
.lit:
    LD   (DE), A
    INC  DE
    JR   .lp
.dn:
    LD   (DE), A
    LD   HL, temp_str_buf
    JP   msg_print_str

_gl_enter_dungeon:
    CALL _gl_clr_level_latches
    JP   tramp_gen_dungeon

_gl_enter_town:
    XOR  A
    LD   (abi_player_dlvl), A
    LD   (player_data + PL_DLEVEL), A
    LD   A, 1
    CALL _gl_clr_level_latches
    LD   A, 1
    CALL tramp_town_restock_all
    CALL tramp_gen_town
    LD   BC, (TOWN_STAIRS_Y << 8) | TOWN_STAIRS_X
    JP   _gl_set_player_pos

_gl_clr_level_latches:
    LD   (level_entry_dir), A
    XOR  A
    LD   (zp_disturb), A
    LD   (auto_rest_active), A
    LD   (md_queue_count), A
    LD   (chest_pending_summons), A
    LD   (chest_loot_pending), A
    LD   (eff_detect_evil_mode), A
    LD   (eff_detect_timer), A
    LD   (level_force_regen), A
    LD   HL, player_data + PL_FLAGS
    RES  4, (HL)                ; PLF_SEARCHING off on level transition
    RES  5, (HL)                ; PLF_RESTING off on level transition (TRN-014)
    LD   A, 0xFF
    LD   (vis_cached_room_idx), A
    LD   (zp_run_dir), A
    RET

_gl_update_vis:
    LD   A, (abi_player_dlvl)
    OR   A
    CALL NZ, los_update_visibility
    CALL monster_update_visibility_all
    OR   A
    RET  Z
    LD   A, 1
    LD   (vis_room_revealed), A
    RET

; ------------------------------------------------------------
; Direction Mappers
; ------------------------------------------------------------
_gl_key_to_dir:
    CP   KEY_UP
    JR   C, .na
    CP   KEY_RIGHT + 1
    JR   NC, .na
    SUB  KEY_UP
    SCF
    RET
.na:
    PUSH BC
    LD   BC, 16
_gl_vi_scan:
    LD   HL, _gl_vi_keys
    CPIR
    JR   NZ, .miss
    LD   A, 15
    SUB  C
    AND  7
    POP  BC
    SCF
    RET
.miss:
    POP  BC
_gl_dir_nc:
    OR   A
    RET

_gl_shifted_to_dir:
    CP   'A'
    JR   C, _gl_dir_nc
    CP   'Z' + 1
    JR   NC, _gl_dir_nc
    OR   0x20
    PUSH BC
    LD   BC, 8
    JR   _gl_vi_scan

; ------------------------------------------------------------
; Public Redraw Helpers
; ------------------------------------------------------------
game_loop_redraw_fresh:
    XOR  A
    LD   (hal_layout_visibility_force_redraw), A
    CALL screen_hard_clear
    CALL status_mark_dirty
game_loop_redraw_all:
    CALL viewport_center_on_player
    CALL viewport_render
    XOR  A
    LD   (vis_room_revealed), A
    LD   (muv_changed), A
    CALL status_draw
    LD   A, (eff_detect_evil_mode)
    OR   A
    CALL NZ, detect_evil_clear_reveal
game_loop_flush_at_player:
    LD   DE, (abi_player_x)
    LD   HL, (abi_view_x)
    LD   A, D
    SUB  H
    ADD  A, VIEWPORT_Y
    LD   B, A
    LD   A, E
    SUB  L
    ADD  A, VIEWPORT_X
    LD   C, A
    PUSH BC
    CALL screen_flush
    POP  BC
    JP   screen_set_cursor
