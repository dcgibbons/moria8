; ============================================================================
; ovl_actions.asm — Dungeon Feature Actions & All 18 Floor Traps
;                   (OVL_ACTIONS = 17, DAT slot 22)
; ============================================================================
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0 : JP ovl_actions_open         () -> CF=1 turn consumed, CF=0 cancel
;   +3 : JP ovl_actions_close        () -> CF=1 turn consumed, CF=0 cancel
;   +6 : JP ovl_actions_search       (A=0xFF passive, else active 's') -> CF=1
;   +9 : JP ovl_actions_disarm       () -> CF=1 turn consumed, CF=0 cancel
;   +12: JP ovl_actions_bash         () -> CF=1 turn consumed, CF=0 cancel
;   +15: JP ovl_actions_tunnel       () -> CF=1 turn consumed, CF=0 cancel
;   +18: JP ovl_actions_trigger_trap (df_target_x/y -> fires trap 0..17)
;   +21: JP ovl_actions_jam          () -> CF=1 turn consumed, CF=0 cancel
; ============================================================================
; ABI / Contract Invariants:
;   - Preserves IX, IY on every public entry vector.
;   - Zero direct calls to other overlays (uses tramp_modal_* and tramp_chest_*).
;   - Live state across tramp_* kept strictly on CPU stack or resident BSS.
; ============================================================================

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "item_ids_z80.inc"
    DEFINE HUFF_CONSTS_ONLY 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_CONSTS_ONLY
    INCLUDE "main_exp.inc"

    ORG  OVL_WINDOW_BASE

ovl_start:
    JP   ovl_actions_open           ; +0
    JP   ovl_actions_close          ; +3
    JP   ovl_actions_search         ; +6
    JP   ovl_actions_disarm         ; +9
    JP   ovl_actions_bash           ; +12
    JP   ovl_actions_tunnel         ; +15
    JP   ovl_actions_trigger_trap   ; +18
    JP   ovl_actions_jam            ; +21

; ============================================================================
; Tables (mirrors core/6502/tables.s & core/6502/disarm*.s & DGN-019)
; ============================================================================
ovl_actions_trap_diff:
    DB   5, 15, 10, 20, 20, 25, 10, 20, 20
    DB   30, 30, 30, 15, 20, 20, 0, 25, 20
ovl_actions_trap_xp:
    DB   1, 3, 2, 5, 6, 8, 2, 6, 5
    DB   10, 10, 10, 3, 5, 5, 0, 8, 5

ovl_actions_race_disarm:
    DB   0, 2, 5, 15, 10, 2, 0xFD, 0xFB     ; +0,2,5,15,10,2,-3,-5
ovl_actions_class_disarm:
    DB   25, 30, 25, 45, 30, 20
ovl_actions_class_lvl_disarm:
    DB   2, 3, 3, 4, 3, 2
ovl_actions_dex_disarm_tbl:
    DB   0xF8, 0xFA, 0xFC, 0xFE, 0xFF
    DB   0, 0, 0, 0, 0
    DB   1, 1, 1, 2, 2, 4

ovl_actions_race_search:
    DB   0, 6, 8, 12, 6, 7, 0, 0xFF         ; +0,6,8,12,6,7,0,-1
ovl_actions_class_search:
    DB   14, 16, 16, 32, 24, 12

; Armor slots damaged via shared tramp_mon_ext_acid_armour

; Trap trigger jump table (types 0..17)
ovl_actions_trap_tbl:
    DW   ovl_actions_t0_open_pit
    DW   ovl_actions_t1_arrow
    DW   ovl_actions_t2_poison_gas
    DW   ovl_actions_t3_teleport
    DW   ovl_actions_t4_poison_dart
    DW   ovl_actions_t5_rockfall
    DW   ovl_actions_t6_covered_pit
    DW   ovl_actions_t7_str_dart
    DW   ovl_actions_t8_trap_door
    DW   ovl_actions_t9_corrode
    DW   ovl_actions_t10_fire
    DW   ovl_actions_t11_acid
    DW   ovl_actions_t12_sleep_gas
    DW   ovl_actions_t13_blind_gas
    DW   ovl_actions_t14_confuse_gas
    DW   ovl_actions_t15_hidden_obj
    DW   ovl_actions_t16_summon
    DW   ovl_actions_t17_aggravate

; Transient scratch (NOT held across tramp_* calls)
ovl_actions_dig_pow:    DB 0
ovl_actions_tmp_a:      DB 0
ovl_actions_tmp_b:      DB 0

; Compact inline messages not in Huffman dictionary
ovl_actions_str_no_disarm:  DB "I do not see anything to disarm there.", 0
ovl_actions_str_disarm_ok:  DB "You have disarmed the trap.", 0
ovl_actions_str_disarm_no:  DB "You failed to disarm the trap.", 0
ovl_actions_str_disarm_bad: DB "You set the trap off!", 0
ovl_actions_str_jam_ok:     DB "You jam the door with a spike.", 0
ovl_actions_str_jam_close:  DB "The door must be closed first.", 0
ovl_actions_str_no_spikes:  DB "But you have no spikes.", 0
ovl_actions_str_jam_full:   DB "The door will not hold a spike.", 0
ovl_actions_str_trap_door:  DB "A trap door opens!", 0
ovl_actions_str_corrode:    DB "A blade hits you!", 0
ovl_actions_str_fire:       DB "Flames hit you!", 0
ovl_actions_str_acid:       DB "Acid hits you!", 0
ovl_actions_str_td_die:     DB "a trap door", 0
ovl_actions_str_blade_die:  DB "a blade", 0
ovl_actions_str_fire_die:   DB "a fire trap", 0
ovl_actions_str_acid_die:   DB "an acid trap", 0

; ============================================================================
; +0: ovl_actions_open
; Open closed/locked door OR open floor chest (via tramp_chest_open).
; Updates los_update_visibility + zp_dirty_count on door open.
; Output: CF = 1 turn consumed, CF = 0 cancelled/nothing
; Preserves: IX, IY
; ============================================================================
ovl_actions_open:
.ask_dir:
    CALL tramp_modal_direction_prompt
    RET  NC

    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL ovl_actions_has_chest_at
    JP   C, tramp_chest_open

    CALL map_get_tile
    JR   NC, .in_bounds
    LD   A, HSTR_DF_NO_DOOR
    CALL msg_print_huff
    OR   A
    RET

.in_bounds:
    LD   D, A                   ; D = full tile byte
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_OPEN
    JR   NZ, .chk_closed
    LD   A, HSTR_DF_ALREADY_OPEN
    CALL msg_print_huff
    OR   A
    RET

.chk_closed:
    CP   TILE_DOOR_CLOSED
    JR   Z, .is_closed
    LD   A, HSTR_DF_NO_DOOR
    CALL msg_print_huff
    OR   A
    RET

.is_closed:
    ; B=df_target_y, C=df_target_x, D=full tile
    CALL ovl_actions_find_door_state ; CF=1 -> E=idx, A=door_state_val
    JR   NC, .open_now
    OR   A
    JR   Z, .open_now
    BIT  7, A
    JR   Z, .locked_door
    ; Jammed / stuck door
    LD   A, HSTR_DF_STUCK
    CALL msg_print_huff
    SCF
    RET

.locked_door:
    ; E = idx, A = lock difficulty (1..127)
    LD   L, A
    LD   A, (zp_eff_confuse)
    OR   A
    JR   Z, .pick_lock
    LD   A, HSTR_DF_PICK_CONFUSED
    CALL msg_print_huff
    SCF
    RET

.pick_lock:
    PUSH DE                     ; E = door_state idx
    PUSH HL                     ; L = lock diff
    CALL ovl_actions_disarm_skill ; A = signed total (-128..+127)
    POP  HL
    BIT  7, A
    JR   NZ, .pick_fail
    SUB  L
    JR   C, .pick_fail
    OR   A
    JR   Z, .pick_fail
    DEC  A                      ; skill - lock - 1
    CP   101
    JR   C, .pick_cap
    LD   A, 100
.pick_cap:
    LD   H, A
    LD   A, 100
    CALL rng_range
    CP   H
    POP  DE
    JR   C, .pick_ok
    LD   A, HSTR_DF_PICK_FAIL
    CALL msg_print_huff
    SCF
    RET
.pick_fail:
    POP  DE
    LD   A, HSTR_DF_PICK_FAIL
    CALL msg_print_huff
    SCF
    RET

.pick_ok:
    LD   A, E
    CALL ovl_actions_remove_door_state
    LD   A, 1
    CALL ovl_actions_add_xp_a
    LD   A, HSTR_DF_PICKED
    CALL msg_print_huff

.open_now:
    LD   A, HSTR_DF_DOOR_OPENED
    CALL msg_print_huff

.finish_open:
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL map_get_tile
    AND  TILE_FLAG_MASK
    OR   (TILE_DOOR_OPEN | FLAG_VISITED)
    RES  0, A                   ; Clear any stale FLAG_OCCUPIED
    CALL map_set_tile
    CALL los_update_visibility
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; ============================================================================
; +3: ovl_actions_close
; Close TILE_DOOR_OPEN unless broken (door_state_val==1) or OCCUPIED/HAS_ITEM.
; Preserves: IX, IY
; ============================================================================
ovl_actions_close:
    CALL tramp_modal_direction_prompt
    RET  NC

    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL map_get_tile
    JR   NC, .in_b
    LD   A, HSTR_DF_NO_DOOR
    CALL msg_print_huff
    OR   A
    RET

.in_b:
    LD   D, A
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_CLOSED
    JR   NZ, .chk_open
    LD   A, HSTR_DF_ALREADY_CLOSED
    CALL msg_print_huff
    OR   A
    RET

.chk_open:
    CP   TILE_DOOR_OPEN
    JR   Z, .is_open
    LD   A, HSTR_DF_NO_DOOR
    CALL msg_print_huff
    OR   A
    RET

.is_open:
    ; Check broken door (state 1) FIRST -> consumes turn (6502 door_open_close_cold.s)
    CALL ovl_actions_find_door_state
    JR   NC, .chk_occ
    CP   1
    JR   NZ, .chk_occ
    LD   A, HSTR_DF_DOOR_BROKEN
    CALL msg_print_huff
    SCF
    RET

.chk_occ:
    ; Items do NOT block closing; only a live monster does (repair stale FLAG_OCCUPIED)
    BIT  0, D
    JR   Z, .close_now
    CALL monster_find_at
    JR   NC, .stale_occ
    CALL _oa_print_in_way
    SCF
    RET
.stale_occ:
    RES  0, D

.close_now:
    LD   A, D
    AND  TILE_FLAG_MASK
    OR   (TILE_DOOR_CLOSED | FLAG_VISITED)
    CALL map_set_tile
    LD   A, HSTR_DF_DOOR_CLOSED
    CALL msg_print_huff
    CALL los_update_visibility
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; ============================================================================
; +6: ovl_actions_search
; Input: A = 0xFF passive search (no "You found nothing."), else active 's'.
; Scans 8 adjacent tiles around player for hidden traps, secret doors & chests.
; Output: CF = 1
; Preserves: IX, IY
; ============================================================================
ovl_actions_search:
    PUSH AF                     ; Keep mode across tramp_chest_search
    XOR  A
    LD   (df_found), A
    LD   (ovl_actions_tmp_a), A

    CALL ovl_actions_calc_search_chance
    LD   (df_search_chance), A

    LD   E, 0                   ; dir 0..7
.dir_lp:
    PUSH DE
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
    OR   A
    JR   Z, .cell_next
    CP   MAP_ROWS - 1
    JR   NC, .cell_next
    LD   A, C
    OR   A
    JR   Z, .cell_next
    CP   MAP_COLS - 1
    JR   NC, .cell_next
    CALL map_get_tile
    JR   C, .cell_next
    LD   L, A
    BIT  1, L                   ; FLAG_HAS_ITEM -> remember for single tramp_chest_search
    JR   Z, .no_item
    LD   A, 1
    LD   (ovl_actions_tmp_a), A
.no_item:
    LD   A, L
    AND  TILE_TYPE_MASK
    CP   TILE_SECRET
    JR   Z, .chk_secret
    CP   TILE_TRAP
    JR   Z, .cell_next          ; Already revealed trap (6502 skips TILE_TRAP)
    OR   A                      ; Wait: also reveal hidden traps on floor/any non-TRAP
    JR   NZ, .cell_next
    PUSH HL
    CALL ovl_actions_find_trap_at ; Preserves B=y, C=x; CF=1 if trap_x/y hits here
    POP  HL
    JR   NC, .cell_next
.chk_trap:
    CALL .roll_search
    JR   NC, .cell_next
    LD   A, L
    AND  TILE_FLAG_MASK
    OR   (TILE_TRAP | FLAG_VISITED)
    CALL map_set_tile
    CALL .mark_found
    PUSH BC
    LD   A, HSTR_DF_FOUND_TRAP
    CALL msg_print_huff
    POP  BC
    JR   .cell_next

.chk_secret:
    CALL .roll_search
    JR   NC, .cell_next
    LD   A, L
    AND  TILE_FLAG_MASK
    OR   (TILE_DOOR_CLOSED | FLAG_VISITED)
    RES  0, A
    CALL map_set_tile
    CALL .mark_found
    PUSH BC
    LD   A, HSTR_DF_FOUND_SECRET
    CALL msg_print_huff
    POP  BC

.cell_next:
    POP  DE
    INC  E
    LD   A, E
    CP   8
    JP   C, .dir_lp

    LD   A, (ovl_actions_tmp_a)
    OR   A
    CALL NZ, tramp_chest_search ; Updates df_found & zp_disturb

    POP  AF                     ; Recover mode A
    CP   0xFF
    JR   Z, .s_done
    LD   A, (df_found)
    OR   A
    JR   NZ, .s_done
    LD   A, HSTR_DF_FOUND_NOTHING
    CALL msg_print_huff
.s_done:
    SCF
    RET

.roll_search:
    LD   A, (df_search_chance)
    OR   A
    RET  Z
    LD   H, A
    LD   A, 100
    CALL rng_range
    CP   H                      ; CF = 1 if rng < chance
    RET

.mark_found:
    LD   A, 1
    LD   (df_found), A
    LD   HL, zp_disturb
    INC  (HL)
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

; ============================================================================
; +9: ovl_actions_disarm
; Disarms floor trap or chest (prompts direction unless player stands on
; chest/visible trap with no adjacent trap/chest). Failure fires trap!
; Output: CF = 1 turn consumed, CF = 0 nothing/cancelled
; Preserves: IX, IY
; ============================================================================
ovl_actions_disarm:
    CALL tramp_modal_direction_prompt
    RET  NC

.at_target:
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL ovl_actions_has_chest_at
    JP   C, tramp_chest_disarm

    CALL map_get_tile
    JR   C, .nothing
    LD   D, A
    AND  TILE_TYPE_MASK
    CP   TILE_TRAP
    JR   NZ, .nothing
    BIT  2, D
    JR   NZ, .trap_tile
.nothing:
    LD   HL, ovl_actions_str_no_disarm
    CALL msg_print_str
    OR   A
    RET

.trap_tile:
    CALL ovl_actions_find_trap_at ; CF=1 -> E=idx, A=type
    JR   NC, .nothing
    CP   TRAP_TYPE_COUNT
    JR   C, .t_ok
    XOR  A
.t_ok:
    PUSH DE                     ; E = trap_idx
    PUSH AF                     ; A = trap_type
    CALL ovl_actions_disarm_skill ; A = signed total (-128..+127)
    LD   H, A                   ; H = signed total
    POP  AF
    LD   L, A                   ; L = trap_type

    LD   E, A
    LD   D, 0
    PUSH HL
    LD   HL, ovl_actions_trap_diff
    ADD  HL, DE
    LD   B, (HL)                ; B = diff
    POP  HL                     ; H = signed total, L = trap_type

    ; threshold = clamp(sign_ext(total) + 99 - diff, 0, 100)
    PUSH HL                     ; preserve H = signed total, L = trap_type
    LD   L, H
    LD   H, 0
    BIT  7, L
    JR   Z, .t_pos
    LD   H, 0xFF
.t_pos:
    LD   DE, 99
    ADD  HL, DE
    LD   E, B
    LD   D, 0
    OR   A
    SBC  HL, DE
    BIT  7, H
    JR   NZ, .t_zero
    LD   A, H
    OR   A
    JR   NZ, .t_100
    LD   A, L
    CP   101
    JR   C, .t_roll_pop
.t_100:
    LD   A, 100
    JR   .t_roll_pop
.t_zero:
    XOR  A
.t_roll_pop:
    POP  HL                     ; H = signed total, L = trap_type
    PUSH HL
    LD   B, A
    LD   A, 100
    CALL rng_range
    CP   B
    POP  HL
    POP  DE                     ; E = trap_idx
    JR   C, .disarm_success

    ; Failed: minor fail if signed total >= 6 && rng_range(total) >= 5
    BIT  7, H
    JR   NZ, .bad_fail
    LD   A, H
    CP   6
    JR   C, .bad_fail
    CALL rng_range
    CP   5
    JR   C, .bad_fail
    LD   HL, ovl_actions_str_disarm_no
    CALL msg_print_str
    SCF
    RET

.bad_fail:
    LD   HL, ovl_actions_str_disarm_bad
    CALL msg_print_str
    ; Move player onto target floor trap (core/6502/disarm.s:97) and trigger it
    CALL ovl_actions_move_player_to_target
    JP   ovl_actions_trigger_trap

.disarm_success:
    ; Convert tile to TILE_FLOOR preserving flags, remove trap entry, move player onto tile, grant XP
    PUSH HL                     ; L = trap_type
    PUSH DE                     ; E = trap_idx
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL map_get_tile
    AND  TILE_FLAG_MASK
    OR   (TILE_FLOOR | FLAG_VISITED)
    CALL map_set_tile

    POP  DE
    LD   A, E
    CP   0xFF
    CALL NZ, ovl_actions_remove_trap
    CALL ovl_actions_move_player_to_target

    POP  HL                     ; L = trap_type
    PUSH HL
    LD   E, L
    LD   D, 0
    LD   HL, ovl_actions_trap_xp
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    CALL NZ, ovl_actions_add_xp_a

    POP  HL                     ; L = trap_type
    LD   A, L
    CP   TRAP_HIDDEN_OBJECT
    JR   NZ, .norm_disarm
    CALL ovl_actions_stage_hidden_drop
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

.norm_disarm:
    LD   HL, ovl_actions_str_disarm_ok
    CALL msg_print_str
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

ovl_actions_move_player_to_target:
    LD   A, (df_target_x)
    LD   (abi_player_x), A
    LD   (player_data + PL_MAP_X), A
    LD   A, (df_target_y)
    LD   (abi_player_y), A
    LD   (player_data + PL_MAP_Y), A
    CALL los_update_visibility
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

; ============================================================================
; +12: ovl_actions_bash
; Bash monster, chest, or closed door. Confused player picks random direction.
; Preserves: IX, IY
; ============================================================================
ovl_actions_bash:
    LD   A, (eff_fear_timer)
    OR   A
    JR   Z, .not_afraid
    LD   A, HSTR_PTM_AFRAID
    CALL msg_print_huff
    OR   A
    RET
.not_afraid:
    CALL tramp_modal_direction_prompt
    RET  NC

    LD   A, (zp_eff_confuse)
    OR   A
    JR   Z, .chk_mon
    LD   A, 8
    CALL rng_range
    LD   (df_dir_idx), A
    LD   E, A
    LD   D, 0
    LD   HL, dir_dx
    ADD  HL, DE
    LD   A, (abi_player_x)
    ADD  A, (HL)
    LD   (df_target_x), A
    LD   HL, dir_dy
    ADD  HL, DE
    LD   A, (abi_player_y)
    ADD  A, (HL)
    LD   (df_target_y), A

.chk_mon:
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL monster_find_at
    JP   C, ovl_actions_bash_monster

.chk_chest:
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL ovl_actions_has_chest_at
    JR   NC, .chk_door

    ; Bash chest in-overlay (slot in A): allows bashing even opened chests (6502 chest.s)
    LD   E, A
    LD   D, 0
    ; 1/10 chance to smash chest into Ruined Chest (contents lost, p1=0, to_hit=0)
    LD   A, 10
    CALL rng_range
    OR   A
    JR   NZ, .bash_chest_lock
    LD   HL, fi_item_id
    ADD  HL, DE
    LD   (HL), ITEM_SLOT_RUINED_CHEST
    LD   HL, fi_p1
    ADD  HL, DE
    LD   (HL), 0
    LD   HL, fi_to_hit
    ADD  HL, DE
    LD   (HL), 0
    LD   HL, fi_meta_hi
    ADD  HL, DE
    LD   (HL), 0
    LD   A, HSTR_CHEST_DESTROYED
    CALL msg_print_huff
    LD   A, HSTR_CHEST_DESTROYED_CONTENTS
    CALL msg_print_huff
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

.bash_chest_lock:
    LD   HL, fi_p1
    ADD  HL, DE
    BIT  0, (HL)                ; CHEST_P1_LOCKED
    JR   Z, .chest_holds
    LD   A, 10
    CALL rng_range
    OR   A
    JR   NZ, .chest_holds
    RES  0, (HL)
    LD   A, HSTR_CHEST_LOCK_BREAKS
    CALL msg_print_huff
    SCF
    RET
.chest_holds:
    LD   A, HSTR_CHEST_HOLDS_FIRM
    CALL msg_print_huff
    SCF
    RET

.chk_door:
    CALL map_get_tile
    JR   C, .bash_empty
    LD   D, A
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_CLOSED
    JR   Z, .bash_door
    ; Hand off tunnelable terrain (walls, rubble, veins, secret doors) to tunnel
    CP   TILE_WALL_H
    JR   C, .bash_empty
    CP   TILE_DOOR_OPEN
    JP   C, ovl_actions_tunnel_resolved
    CP   TILE_RUBBLE
    JR   C, .bash_empty
    CP   TILE_TRAP
    JP   C, ovl_actions_tunnel_resolved
    CP   TILE_SECRET
    JP   Z, ovl_actions_tunnel_resolved
.bash_empty:
    LD   A, HSTR_BASH_EMPTY
    CALL msg_print_huff
    SCF
    RET

.bash_door:
    PUSH BC
    PUSH DE
    LD   A, HSTR_BASH_SMASH
    CALL msg_print_huff
    POP  DE
    POP  BC

    ; chance = STR_CUR + 75 (clamped 255); rng_word(chance*(20+|s|)) < 10*(chance-|s|)
    LD   A, (player_data + PL_STR_CUR)
    ADD  A, 75
    JR   NC, .bd_ch_ok
    LD   A, 255
.bd_ch_ok:
    LD   L, A                   ; L = chance
    PUSH HL
    CALL ovl_actions_find_door_state ; CF=1 -> E=idx, A=val
    JR   NC, .mag_zero
    AND  0x7F
    JR   .cmp_bash
.mag_zero:
    LD   E, 0xFF
    XOR  A
.cmp_bash:
    POP  HL                     ; L = chance
    LD   H, A                   ; H = mag (|s|)
    LD   A, L
    SUB  H                      ; diff = chance - mag
    JR   C, .bash_holds
    JR   Z, .bash_holds

    ; spread = chance * (20 + mag)
    PUSH DE                     ; save E = door_state idx, D = tile
    PUSH AF                     ; save A = diff
    PUSH HL                     ; L = chance, H = mag
    LD   A, H
    ADD  A, 20
    LD   E, A
    LD   D, 0
    LD   A, L                   ; A = chance
    CALL mul_de_a               ; HL = spread
    CALL _oa_rng_word_hl        ; HL = roll in [0, spread-1]
    POP  DE                     ; (discard L, H)
    POP  AF                     ; A = diff
    PUSH HL                     ; save roll
    LD   E, A
    LD   D, 0
    LD   A, 10
    CALL mul_de_a               ; HL = 10 * diff (threshold)
    EX   DE, HL                 ; DE = threshold
    POP  HL                     ; HL = roll
    OR   A
    SBC  HL, DE
    POP  DE                     ; E = door_state idx, D = tile
    JR   C, .bash_success

.bash_holds:
    LD   A, HSTR_BASH_HOLDS
    CALL msg_print_huff
    CALL ovl_actions_bash_offbalance_door
    SCF
    RET

.bash_success:
    LD   A, 2
    CALL rng_range
    OR   A
    JR   Z, .break_door
    LD   A, E
    CP   0xFF
    CALL NZ, ovl_actions_remove_door_state
    JR   .set_open_door

.break_door:
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    LD   A, 1
    CALL ovl_actions_set_door_state

.set_open_door:
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL map_get_tile
    AND  TILE_FLAG_MASK
    OR   (TILE_DOOR_OPEN | FLAG_VISITED)
    RES  0, A
    CALL map_set_tile
    LD   A, HSTR_BASH_CRASH
    CALL msg_print_huff
    ; Step into the doorway & run passive search when NOT searching (6502 bash.s:228)
    CALL ovl_actions_move_player_to_target
    LD   A, (player_data + PL_FLAGS)
    AND  PLF_SEARCHING
    JR   NZ, .bd_ret
    CALL player_search_get_fos
    CP   2
    JR   C, .bd_ps
    CALL rng_range
    OR   A
    JR   NZ, .bd_ret
.bd_ps:
    LD   A, 0xFF
    CALL ovl_actions_search
.bd_ret:
    SCF
    RET

ovl_actions_bash_offbalance_door:
    LD   A, 150
    CALL rng_range
    LD   HL, player_data + PL_DEX_CUR
    CP   (HL)
    RET  C
    LD   A, 2
    CALL rng_range
    ADD  A, 2                   ; 2..3 overwrite (6502 bash_off_balance_door)
    LD   (zp_eff_paralyze), A
    LD   A, HSTR_BASH_OFFBAL
    JP   msg_print_huff

; Sample HL uniformly in [0..HL-1] using tightest power-of-2 mask (HL > 0).
_oa_rng_word_hl:
    LD   B, H
    LD   C, L                   ; BC = limit
    LD   A, 1
.mk:
    ADD  A, A
    JR   C, .mk_ff
    CP   B
    JR   C, .mk
    JR   Z, .mk
    DEC  A
    JR   .go
.mk_ff:
    LD   A, 0xFF
.go:
    LD   D, A
    LD   E, 0xFF
    JP   _oa_rng16

; ============================================================================
; +15: ovl_actions_tunnel
; Prompt direction (fear + 75% confusion), then dig walls, magma, quartz,
; rubble, closed doors, secret doors, or attack blocking monster.
; Preserves: IX, IY
; ============================================================================
ovl_actions_tunnel:
    LD   A, (eff_fear_timer)
    OR   A
    JR   Z, .tun_not_afraid
    LD   A, HSTR_PTM_AFRAID
    CALL msg_print_huff
    OR   A
    RET
.tun_not_afraid:
    CALL tramp_modal_direction_prompt
    RET  NC

    LD   A, (zp_eff_confuse)
    OR   A
    JR   Z, ovl_actions_tunnel_resolved
    LD   A, 4
    CALL rng_range
    OR   A
    JR   Z, ovl_actions_tunnel_resolved ; 25% keep intended dir
    LD   A, 8
    CALL rng_range
    LD   E, A
    LD   D, 0
    LD   HL, dir_dx
    ADD  HL, DE
    LD   A, (abi_player_x)
    ADD  A, (HL)
    LD   (df_target_x), A
    LD   HL, dir_dy
    ADD  HL, DE
    LD   A, (abi_player_y)
    ADD  A, (HL)
    LD   (df_target_y), A

ovl_actions_tunnel_resolved:
    LD   A, (df_target_x)
    LD   C, A
    LD   A, (df_target_y)
    LD   B, A
    CALL monster_find_at
    JP   C, tramp_modal_player_attack

    ; Boundary check: edge tiles are permanent rock
    LD   A, C
    OR   A
    JR   Z, .perm
    CP   MAP_COLS - 1
    JR   NC, .perm
    LD   A, B
    OR   A
    JR   Z, .perm
    CP   MAP_ROWS - 1
    JR   NC, .perm
    CALL map_get_tile
    JR   C, .perm

    LD   D, A                   ; D = full tile byte
    AND  TILE_TYPE_MASK
    CP   TILE_RUBBLE
    JR   Z, .dig_rubble
    CP   TILE_MAGMA
    JR   Z, .dig_magma
    CP   TILE_QUARTZ
    JR   Z, .dig_quartz
    CP   TILE_WALL_H
    JR   C, .nothing
    CP   TILE_CORNER_BR + 1
    JR   C, .dig_granite
    CP   TILE_DOOR_CLOSED
    JR   Z, .dig_granite
    CP   TILE_SECRET
    JR   Z, .dig_granite
.nothing:
    LD   A, HSTR_TUN_NOTHING
    CALL msg_print_huff
    OR   A
    RET

.perm:
    LD   A, HSTR_TUN_PERMANENT
    CALL msg_print_huff
    OR   A
    RET

.dig_rubble:
    PUSH BC
    PUSH DE
    CALL tramp_modal_calc_dig
    LD   (ovl_actions_dig_pow), A
    LD   A, 40
    CALL rng_range              ; [0, 39]
    LD   H, HSTR_TUN_DIG_GRANITE
    LD   L, 1                   ; L=1 marks rubble
    JR   .dig_compare

.dig_granite:
    PUSH BC
    PUSH DE
    CALL tramp_modal_calc_dig
    LD   (ovl_actions_dig_pow), A
    LD   A, 240
    CALL rng_range
    ADD  A, 16                  ; 16..255
    LD   H, HSTR_TUN_DIG_GRANITE
    LD   L, 0
    JR   .dig_compare

.dig_magma:
    PUSH BC
    PUSH DE
    CALL tramp_modal_calc_dig
    LD   (ovl_actions_dig_pow), A
    LD   A, 120
    CALL rng_range
    ADD  A, 5                   ; 5..124
    LD   H, HSTR_TUN_DIG_MAGMA
    LD   L, 0
    JR   .dig_compare

.dig_quartz:
    PUSH BC
    PUSH DE
    CALL tramp_modal_calc_dig
    LD   (ovl_actions_dig_pow), A
    LD   A, 80
    CALL rng_range
    ADD  A, 3                   ; 3..82
    LD   H, HSTR_TUN_DIG_QUARTZ
    LD   L, 0

.dig_compare:
    ; A = resistance, H = fail_hstr, L = is_rubble, stack: DE=tile, BC=coords
    LD   E, A
    LD   A, (ovl_actions_dig_pow)
    CP   E
    JR   C, .dig_fail
    JR   NZ, .dig_ok
    CALL rng_next_u8
    AND  1
    JR   NZ, .dig_ok
.dig_fail:
    LD   A, H
    CALL msg_print_huff
    POP  DE
    POP  BC
    SCF
    RET

.dig_ok:
    LD   A, L
    OR   A
    POP  DE                     ; D = original full tile byte
    POP  BC                     ; B = target y, C = target x
    PUSH AF                     ; save is_rubble flag
    LD   A, TILE_FLOOR | FLAG_VISITED | FLAG_LIT
    CALL map_set_tile

    ; Clear persistent door state if tunneled closed door
    LD   A, D
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_CLOSED
    JR   NZ, .no_dstate
    PUSH DE
    CALL ovl_actions_find_door_state
    LD   A, E
    POP  DE
    CALL C, ovl_actions_remove_door_state
.no_dstate:
    POP  AF
    JR   Z, .not_rubble
    LD   A, HSTR_TUN_RUBBLE
    JR   .tun_msg_redraw
.not_rubble:
    BIT  1, D                   ; FLAG_HAS_ITEM in treasure vein?
    JR   Z, .tun_plain_fin
    PUSH BC
    CALL ovl_actions_spawn_vein_gold
    POP  BC
    LD   A, TILE_FLOOR | FLAG_VISITED | FLAG_LIT | FLAG_HAS_ITEM
    CALL C, map_set_tile
    LD   A, HSTR_TUN_FOUND
    JR   .tun_msg_redraw
.tun_plain_fin:
    LD   A, HSTR_TUN_FINISHED
.tun_msg_redraw:
    CALL msg_print_huff
    LD   A, 1
    LD   (vis_room_revealed), A
    CALL los_update_visibility
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; ============================================================================
; +18: ovl_actions_trigger_trap
; Execute trap at (df_target_x, df_target_y) across all 18 trap types (0..17).
; Output: CF = 1
; Preserves: IX, IY
; ============================================================================
ovl_actions_trigger_trap:
    CALL player_search_mode_off
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL ovl_actions_find_trap_at ; CF=1 -> E=idx, A=type
    JR   C, .found
    LD   E, 0xFF
    XOR  A
.found:
    CP   TRAP_TYPE_COUNT
    JR   C, .type_ok
    XOR  A
.type_ok:
    LD   (df_disarm_trap_idx), A ; Note: also hold trap_idx in E (stack)
    LD   A, E
    LD   (ovl_actions_tmp_b), A
    ; Reveal trap tile (TILE_TRAP | FLAG_VISITED, preserving flags) unless overwritten by rockfall/stash/summon
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL map_get_tile
    JR   C, .dispatch
    AND  TILE_FLAG_MASK
    OR   (TILE_TRAP | FLAG_VISITED)
    CALL map_set_tile
    LD   HL, zp_dirty_count
    INC  (HL)

.dispatch:
    LD   A, (df_disarm_trap_idx)
    ADD  A, A
    LD   E, A
    LD   D, 0
    LD   HL, ovl_actions_trap_tbl
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    EX   DE, HL
    JP   (HL)

; --- Trap 6: Covered pit -> mutates to TRAP_OPEN_PIT, falls through to Trap 0 ---
ovl_actions_t6_covered_pit:
    LD   A, (ovl_actions_tmp_b)
    CP   MAX_TRAPS
    JR   NC, ovl_actions_t0_open_pit
    LD   E, A
    LD   D, 0
    LD   HL, trap_type
    ADD  HL, DE
    LD   (HL), TRAP_OPEN_PIT
    ; Fall through to open pit

; --- Trap 0: Open pit (2d6 unless PFLAG_FFALL, DEATH_TRAP_PIT) ---
ovl_actions_t0_open_pit:
    LD   A, HSTR_DF_YOU_FELL
    CALL msg_print_huff
    LD   A, (player_pflags)
    AND  PFLAG_FFALL
    JR   Z, .pit_dam
    LD   A, HSTR_CHEST_UNAFFECTED
    CALL msg_print_huff
    SCF
    RET
.pit_dam:
    LD   B, 2
    LD   C, 6
    CALL ovl_actions_roll_dice
    LD   A, HSTR_DF_TRAP_0
    LD   E, DEATH_TRAP_PIT
    CALL ovl_actions_set_hstr_death
    CALL ovl_actions_apply_trap_dmg
    SCF
    RET

; --- Trap 1: Arrow (1d8, DEATH_TRAP_ARROW) ---
ovl_actions_t1_arrow:
    LD   A, HSTR_DF_ARROW_HITS
    CALL msg_print_huff
    LD   B, 1
    LD   C, 8
    CALL ovl_actions_roll_dice
    LD   A, HSTR_DF_TRAP_1
    LD   E, DEATH_TRAP_ARROW
    CALL ovl_actions_set_hstr_death
    CALL ovl_actions_apply_trap_dmg
    SCF
    RET

; --- Trap 2: Poison gas (zp_eff_poison = 11..20) ---
ovl_actions_t2_poison_gas:
    LD   A, HSTR_DF_POISON_GAS
    CALL msg_print_huff
    LD   A, HSTR_DF_POISONED
    CALL msg_print_huff
    LD   A, 10
    CALL rng_range
    ADD  A, 11
    LD   (zp_eff_poison), A
    SCF
    RET

; --- Trap 3: Teleport to random open floor via find_random_floor ---
ovl_actions_t3_teleport:
    LD   A, HSTR_DF_TELEPORTED
    CALL msg_print_huff
    XOR  A
    CALL find_random_floor
    JR   NC, .tel_done
    LD   A, C
    LD   (abi_player_x), A
    LD   (player_data + PL_MAP_X), A
    LD   A, B
    LD   (abi_player_y), A
    LD   (player_data + PL_MAP_Y), A
    CALL los_update_visibility
    LD   HL, zp_dirty_count
    INC  (HL)
.tel_done:
    SCF
    RET

; --- Trap 4: Poison dart (1d4 + 50% CON -1 unless SUST_CON) ---
ovl_actions_t4_poison_dart:
    LD   A, HSTR_DF_DART_HITS
    CALL msg_print_huff
    LD   B, 1
    LD   C, 4
    CALL ovl_actions_roll_dice
    LD   A, HSTR_DF_TRAP_4
    LD   E, DEATH_TRAP_DART
    CALL ovl_actions_set_hstr_death
    CALL ovl_actions_apply_trap_dmg
    RET  C
    CALL rng_next_u8
    AND  1
    JR   Z, .done_con
    LD   A, (player_sust_mask)
    AND  SUST_CON
    JR   NZ, .done_con
    LD   A, STAT_CON
    CALL player_drain_stat_a
    JR   NC, .done_con
    LD   A, HSTR_CHEST_WEAKENED
    CALL msg_print_huff
.done_con:
    SCF
    RET

; --- Trap 5: Rockfall (converts tile -> TILE_RUBBLE + removes trap BEFORE 2d6 dmg) ---
ovl_actions_t5_rockfall:
    LD   A, (ovl_actions_tmp_b)
    PUSH AF
    LD   A, HSTR_DF_ROCKFALL
    CALL msg_print_huff
    POP  DE                     ; D = trap_idx
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL map_get_tile
    JR   C, .rock_dmg
    AND  TILE_FLAG_MASK
    OR   (TILE_RUBBLE | FLAG_VISITED)
    CALL map_set_tile
    LD   A, D
    CP   MAX_TRAPS
    CALL C, ovl_actions_remove_trap
    CALL los_update_visibility
    LD   HL, zp_dirty_count
    INC  (HL)
.rock_dmg:
    LD   B, 2
    LD   C, 6
    CALL ovl_actions_roll_dice
    LD   A, HSTR_DF_DEATH_ROCKFALL
    LD   E, DEATH_TRAP_ROCKFALL
    CALL ovl_actions_set_hstr_death
    CALL ovl_actions_apply_trap_dmg
    SCF
    RET

; --- Trap 7: Strength dart (1d4 + STR -1 unless SUST_STR) ---
ovl_actions_t7_str_dart:
    LD   A, HSTR_DF_DART_HITS
    CALL msg_print_huff
    LD   B, 1
    LD   C, 4
    CALL ovl_actions_roll_dice
    LD   A, HSTR_DF_TRAP_4
    LD   E, DEATH_TRAP_DART
    CALL ovl_actions_set_hstr_death
    CALL ovl_actions_apply_trap_dmg
    RET  C
    LD   A, (player_sust_mask)
    AND  SUST_STR
    JR   Z, .drain_str
    SCF
    RET
.drain_str:
    LD   A, STAT_STR
    CALL player_drain_stat_a
    JR   NC, .done_str
    LD   A, HSTR_CHEST_WEAKENED
    CALL msg_print_huff
.done_str:
    SCF
    RET

; --- Trap 8: Trap door (2d8 unless PFLAG_FFALL; always force-regen on survival) ---
ovl_actions_t8_trap_door:
    LD   HL, ovl_actions_str_trap_door
    CALL msg_print_str
    LD   A, (player_pflags)
    AND  PFLAG_FFALL
    JR   Z, .td_dmg
    LD   A, HSTR_CHEST_UNAFFECTED
    CALL msg_print_huff
    JR   .descend
.td_dmg:
    LD   B, 2
    LD   C, 8
    CALL ovl_actions_roll_dice
    LD   DE, ovl_actions_str_td_die
    LD   A, DEATH_TRAP_PIT
    CALL ovl_actions_set_str_death
    CALL ovl_actions_apply_trap_dmg
    RET  C
.descend:
    LD   A, (abi_player_dlvl)
    CP   99
    JR   NC, .dlvl_ok
    INC  A
.dlvl_ok:
    LD   (abi_player_dlvl), A
    LD   (player_data + PL_DLEVEL), A
    LD   HL, player_data + PL_MAX_DLVL
    CP   (HL)
    JR   C, .max_ok
    LD   (HL), A
.max_ok:
    XOR  A
    LD   (level_entry_dir), A
    INC  A
    LD   (level_force_regen), A
    LD   (vis_room_revealed), A
    LD   HL, zp_disturb
    INC  (HL)
    SCF
    RET

; --- Trap 9: Corrode (A blade hits you! + 4d6 HP + acid armor) ---
ovl_actions_t9_corrode:
    LD   HL, ovl_actions_str_corrode
    CALL msg_print_str
    LD   B, 4
    LD   C, 6
    CALL ovl_actions_roll_dice
    LD   DE, ovl_actions_str_blade_die
    LD   A, DEATH_TRAP_ARROW
    CALL ovl_actions_set_str_death
    CALL ovl_actions_apply_trap_dmg
    JR   C, .t9_ret
    LD   HL, 0
    CALL tramp_mon_ext_acid_armour
.t9_ret:
    SCF
    RET

; --- Trap 10: Fire trap ("Flames hit you!", 4d6, stack perm+temp /3 up to /9) ---
ovl_actions_t10_fire:
    LD   HL, ovl_actions_str_fire
    CALL msg_print_str
    LD   B, 4
    LD   C, 6
    CALL ovl_actions_roll_dice
    LD   A, (player_pflags)
    AND  PFLAG_RESIST_FIRE
    JR   Z, .chk_tmp_f
    LD   C, 3
    CALL div_hl_c
.chk_tmp_f:
    LD   A, (zp_eff_resist)
    OR   A
    JR   Z, .apply_f
    LD   C, 3
    CALL div_hl_c
.apply_f:
    LD   DE, ovl_actions_str_fire_die
    LD   A, DEATH_TRAP_ROCKFALL
    CALL ovl_actions_set_str_death
    CALL ovl_actions_apply_trap_dmg
    SCF
    RET

; --- Trap 11: Acid trap ("Acid hits you!", 4d6, div (1 + armor + 2*resist)) ---
ovl_actions_t11_acid:
    LD   HL, ovl_actions_str_acid
    CALL msg_print_str
    LD   B, 4
    LD   C, 6
    CALL ovl_actions_roll_dice
    PUSH HL
    CALL tramp_mon_ext_acid_armour ; CF=1 if a worn armour piece took it
    POP  HL
    LD   C, 1
    JR   NC, .a_chk_p
    INC  C
.a_chk_p:
    LD   A, (player_pflags)
    AND  PFLAG_RESIST_ACID
    JR   Z, .a_div
    INC  C
    INC  C
.a_div:
    CALL div_hl_c
    LD   DE, ovl_actions_str_acid_die
    LD   A, DEATH_TRAP_ROCKFALL
    CALL ovl_actions_set_str_death
    CALL ovl_actions_apply_trap_dmg
    SCF
    RET

; --- Trap 12: Sleep gas ("A cloud of gas...", overwrite zp_eff_paralyze = 5..8) ---
ovl_actions_t12_sleep_gas:
    LD   A, HSTR_DF_POISON_GAS
    CALL msg_print_huff
    LD   A, (player_pflags)
    AND  PFLAG_FREE_ACT
    JR   Z, .slp_hit
    LD   A, HSTR_CHEST_UNAFFECTED
    CALL msg_print_huff
    SCF
    RET
.slp_hit:
    LD   A, 4
    CALL rng_range
    ADD  A, 5
    LD   (zp_eff_paralyze), A
    LD   A, HSTR_CHEST_CHOKE
    CALL msg_print_huff
    SCF
    RET

; --- Trap 13: Blind gas ("A cloud of gas...", overwrite zp_eff_blind = 26..75) ---
ovl_actions_t13_blind_gas:
    LD   A, HSTR_DF_POISON_GAS
    CALL msg_print_huff
    LD   A, 50
    CALL rng_range
    ADD  A, 26
    LD   (zp_eff_blind), A
    LD   A, HSTR_PIQ_CANT_SEE
    CALL msg_print_huff
    LD   A, 1
    LD   (vis_room_revealed), A
    CALL los_update_visibility
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; --- Trap 14: Confuse gas ("A cloud of gas...", overwrite zp_eff_confuse = 16..30) ---
ovl_actions_t14_confuse_gas:
    LD   A, HSTR_DF_POISON_GAS
    CALL msg_print_huff
    LD   A, 15
    CALL rng_range
    ADD  A, 16
    LD   (zp_eff_confuse), A
    LD   A, HSTR_PIQ_DIZZY
    CALL msg_print_huff
    SCF
    RET

; --- Trap 15: Hidden object (clear trap, stage buried object drop + HSTR_TUN_FOUND) ---
ovl_actions_t15_hidden_obj:
    LD   A, (ovl_actions_tmp_b)
    CP   MAX_TRAPS
    CALL C, ovl_actions_remove_trap
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL map_get_tile
    JR   C, .ho_msg
    AND  TILE_FLAG_MASK
    OR   (TILE_FLOOR | FLAG_VISITED)
    CALL map_set_tile
.ho_msg:
    CALL ovl_actions_stage_hidden_drop
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; --- Trap 16: Summoning rune (HSTR_PMU_GLYPH_OK + 3..5 awake summons) ---
ovl_actions_t16_summon:
    LD   A, (ovl_actions_tmp_b)
    CP   MAX_TRAPS
    CALL C, ovl_actions_remove_trap
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL map_get_tile
    JR   C, .sm_msg
    AND  TILE_FLAG_MASK
    OR   (TILE_FLOOR | FLAG_VISITED)
    CALL map_set_tile
.sm_msg:
    LD   A, HSTR_PMU_GLYPH_OK
    CALL msg_print_huff
    LD   A, (abi_player_x)
    LD   (chest_summon_x), A
    LD   A, (abi_player_y)
    LD   (chest_summon_y), A
    LD   A, 3
    CALL rng_range
    ADD  A, 3
    LD   (chest_pending_summons), A
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; --- Trap 17: Aggravate (HSTR_MAT_SHRIEK + monster_aggravate_all) ---
ovl_actions_t17_aggravate:
    LD   A, HSTR_MAT_SHRIEK
    CALL msg_print_huff
    CALL monster_aggravate_all
    LD   HL, zp_disturb
    INC  (HL)
    SCF
    RET

; ============================================================================
; +21: ovl_actions_jam
; ============================================================================
ovl_actions_jam:
    CALL tramp_modal_direction_prompt
    RET  NC

    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL map_get_tile
    JR   C, .no_door
    LD   D, A
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_CLOSED
    JR   Z, .chk_mon
    CP   TILE_DOOR_OPEN
    JR   NZ, .no_door
    LD   HL, ovl_actions_str_jam_close
    CALL msg_print_str
    OR   A
    RET
.no_door:
    LD   A, HSTR_DF_NO_DOOR
    CALL msg_print_huff
    OR   A
    RET

.chk_mon:
    BIT  0, D
    JR   Z, .find_spike
    CALL monster_find_at
    JR   NC, .find_spike
    CALL _oa_print_in_way
    SCF
    RET

.find_spike:
    LD   E, 0
    LD   D, 0
.spk_lp:
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   ITEM_SLOT_IRON_SPIKE
    JR   NZ, .spk_nx
    LD   HL, inv_ego
    ADD  HL, DE
    BIT  6, (HL)
    JR   NZ, .spk_nx
    LD   HL, inv_qty
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    JR   NZ, .got_spike
.spk_nx:
    INC  E
    LD   A, E
    CP   MAX_INV_SLOTS
    JR   C, .spk_lp
    LD   HL, ovl_actions_str_no_spikes
    CALL msg_print_str
    SCF
    RET

.got_spike:
    PUSH DE
    CALL ovl_actions_find_door_state ; CF=1 -> E=idx, A=val
    JR   NC, .new_jam
    AND  0x7F
    ADD  A, 20                  ; flat +20 (6502 dungeon_features.s:671)
    BIT  7, A
    JR   Z, .jam_cap_ok
    LD   A, 127
.jam_cap_ok:
    OR   0x80
    LD   D, 0
    LD   HL, door_state_val
    ADD  HL, DE
    LD   (HL), A
    JR   .consume_spike

.new_jam:
    LD   A, (door_state_count)
    CP   MAX_DOOR_STATES
    JR   C, .alloc_jam
    POP  DE
    LD   HL, ovl_actions_str_jam_full
    CALL msg_print_str
    SCF
    RET
.alloc_jam:
    LD   A, 20 | 0x80
    CALL ovl_actions_set_door_state

.consume_spike:
    POP  DE
    LD   A, E
    CALL inv_consume_one
    CALL player_sync_to_abi
    LD   HL, ovl_actions_str_jam_ok
    CALL msg_print_str
    SCF
    RET

; ============================================================================
; Internal Helpers
; ============================================================================

; ovl_actions_has_chest_at — CF=1 & A=slot if chest at (B=y, C=x). Preserves B, C.
ovl_actions_has_chest_at:
    LD   E, 0
    LD   D, 0
.lp:
    LD   HL, fi_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .nx
    SUB  ITEM_SLOT_SMALL_WOODEN_CHEST
    CP   7
    JR   NC, .nx
    LD   HL, fi_meta_hi
    ADD  HL, DE
    BIT  6, (HL)
    JR   NZ, .nx
    LD   HL, fi_x
    ADD  HL, DE
    LD   A, (HL)
    CP   C
    JR   NZ, .nx
    LD   HL, fi_y
    ADD  HL, DE
    LD   A, (HL)
    CP   B
    JR   NZ, .nx
    LD   A, E
    SCF
    RET
.nx:
    INC  E
    LD   A, E
    CP   MAX_FLOOR_ITEMS
    JR   C, .lp
    OR   A
    RET

; ovl_actions_find_door_state — At (B=y, C=x): CF=1 -> E=idx, A=door_state_val.
; Preserves B, C.
ovl_actions_find_door_state:
    LD   A, (door_state_count)
    OR   A
    RET  Z                      ; Note OR A clears CF!
    LD   D, A                   ; count
    LD   E, 0
.lp:
    PUSH DE
    LD   D, 0
    LD   HL, door_state_x
    ADD  HL, DE
    LD   A, (HL)
    CP   C
    JR   NZ, .nx
    LD   HL, door_state_y
    ADD  HL, DE
    LD   A, (HL)
    CP   B
    JR   NZ, .nx
    LD   HL, door_state_val
    ADD  HL, DE
    LD   A, (HL)
    POP  DE                     ; E = idx
    SCF
    RET
.nx:
    POP  DE
    INC  E
    LD   A, E
    CP   D
    JR   C, .lp
    OR   A
    RET

; ovl_actions_set_door_state — Set/add door_state entry at (B=y, C=x) = A
ovl_actions_set_door_state:
    PUSH AF
    CALL ovl_actions_find_door_state
    JR   C, .upd
    LD   A, (door_state_count)
    CP   MAX_DOOR_STATES
    JR   C, .add
    POP  AF
    RET
.add:
    LD   E, A
    INC  A
    LD   (door_state_count), A
.upd:
    LD   D, 0
    LD   HL, door_state_x
    ADD  HL, DE
    LD   (HL), C
    LD   HL, door_state_y
    ADD  HL, DE
    LD   (HL), B
    LD   HL, door_state_val
    ADD  HL, DE
    POP  AF
    LD   (HL), A
    RET

; ovl_actions_remove_door_state — Remove door_state entry at idx A via swap-with-last
ovl_actions_remove_door_state:
    LD   E, A
    LD   A, (door_state_count)
    OR   A
    RET  Z
    CP   E
    RET  C
    RET  Z
    DEC  A
    LD   (door_state_count), A
    CP   E
    RET  Z                      ; Was already last element
    ; Move slot A (last) into E
    LD   B, 0
    LD   C, A
    LD   D, 0
    LD   HL, door_state_x
    ADD  HL, BC
    LD   A, (HL)
    LD   HL, door_state_x
    ADD  HL, DE
    LD   (HL), A
    LD   HL, door_state_y
    ADD  HL, BC
    LD   A, (HL)
    LD   HL, door_state_y
    ADD  HL, DE
    LD   (HL), A
    LD   HL, door_state_val
    ADD  HL, BC
    LD   A, (HL)
    LD   HL, door_state_val
    ADD  HL, DE
    LD   (HL), A
    RET

; ovl_actions_find_trap_at — At (B=y, C=x): CF=1 -> E=idx, A=trap_type. Preserves B, C.
ovl_actions_find_trap_at:
    LD   A, (trap_count)
    OR   A
    RET  Z
    LD   D, A
    LD   E, 0
.lp:
    PUSH DE
    LD   D, 0
    LD   HL, trap_x
    ADD  HL, DE
    LD   A, (HL)
    CP   C
    JR   NZ, .nx
    LD   HL, trap_y
    ADD  HL, DE
    LD   A, (HL)
    CP   B
    JR   NZ, .nx
    LD   HL, trap_type
    ADD  HL, DE
    LD   A, (HL)
    POP  DE
    SCF
    RET
.nx:
    POP  DE
    INC  E
    LD   A, E
    CP   D
    JR   C, .lp
    OR   A
    RET

; ovl_actions_remove_trap — Remove trap entry A via swap-with-last. Preserves B, C.
ovl_actions_remove_trap:
    PUSH BC
    LD   E, A
    LD   A, (trap_count)
    OR   A
    JR   Z, .ret
    DEC  A
    LD   (trap_count), A
    CP   E
    JR   Z, .ret
    LD   B, 0
    LD   C, A
    LD   D, 0
    LD   HL, trap_x
    ADD  HL, BC
    LD   A, (HL)
    LD   HL, trap_x
    ADD  HL, DE
    LD   (HL), A
    LD   HL, trap_y
    ADD  HL, BC
    LD   A, (HL)
    LD   HL, trap_y
    ADD  HL, DE
    LD   (HL), A
    LD   HL, trap_type
    ADD  HL, BC
    LD   A, (HL)
    LD   HL, trap_type
    ADD  HL, DE
    LD   (HL), A
.ret:
    POP  BC
    RET

; ovl_actions_disarm_skill — Compute signed disarm skill (-128..+127) in A
; Matches 6502 player_disarm_get_effective_chance (core/6502/disarm_helpers.s).
ovl_actions_disarm_skill:
    LD   A, (player_data + PL_DEX_CUR)
    CALL .dex_adj
    PUSH AF                     ; save signed dex_adj (-8..+8)
    LD   C, A
    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .c_ok
    XOR  A
.c_ok:
    LD   E, A
    LD   D, 0
    LD   HL, ovl_actions_class_disarm
    ADD  HL, DE
    LD   A, C
    ADD  A, (HL)
    LD   C, A
    LD   A, (player_data + PL_RACE)
    CP   RACE_COUNT
    JR   C, .r_ok
    XOR  A
.r_ok:
    LD   E, A
    LD   HL, ovl_actions_race_disarm
    ADD  HL, DE
    LD   A, C
    ADD  A, (HL)
    ADD  A, 2
    LD   C, A                   ; C = df_disarm_base (+9..+70)

    ; total = clamp_s8(dex_adj * base)
    POP  AF                     ; A = signed dex_adj
    OR   A
    JR   Z, .mul_done
    PUSH AF
    BIT  7, A
    JR   Z, .mul_pos
    NEG
.mul_pos:
    LD   D, 0
    LD   E, C
    CALL mul_de_a               ; HL = |dex_adj| * base
    POP  AF
    BIT  7, A
    JR   NZ, .mul_neg
    LD   A, H
    OR   A
    JR   NZ, .mul_sat_pos
    LD   A, L
    CP   128
    JR   C, .mul_done
.mul_sat_pos:
    LD   A, 127
    JR   .mul_done
.mul_neg:
    LD   A, H
    OR   A
    JR   NZ, .mul_sat_neg
    LD   A, L
    CP   129
    JR   NC, .mul_sat_neg
    XOR  A
    SUB  L
    JR   .mul_done
.mul_sat_neg:
    LD   A, 0x80
.mul_done:
    LD   E, A                   ; E = signed total (-128..+127)

    PUSH DE
    LD   A, (player_data + PL_INT_CUR)
    CALL .int_adj
    POP  DE
    CALL .add_signed

    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .c2
    XOR  A
.c2:
    LD   C, A
    LD   B, 0
    LD   HL, ovl_actions_class_lvl_disarm
    ADD  HL, BC
    LD   B, (HL)
    LD   A, (player_data + PL_LEVEL)
    PUSH DE
    LD   D, 0
    LD   E, A
    LD   A, B
    CALL mul_de_a
    LD   C, 3
    CALL div_hl_c
    POP  DE
    LD   A, H
    OR   A
    JR   NZ, .lvl_sat
    LD   A, L
    CP   128
    JR   C, .lvl_add
.lvl_sat:
    LD   A, 127
.lvl_add:
    CALL .add_signed

    LD   A, (zp_eff_confuse)
    OR   A
    JR   Z, .nc
    CALL .div10_signed
.nc:
    LD   A, (zp_eff_blind)
    OR   A
    JR   NZ, .d10
    LD   A, (player_data + PL_LIGHT_RAD)
    OR   A
    JR   NZ, .ret
    PUSH DE
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    CALL map_get_tile
    POP  DE
    JR   C, .d10
    BIT  3, A
    JR   NZ, .ret
.d10:
    CALL .div10_signed
.ret:
    LD   A, E
    RET

.add_signed:
    LD   B, A
    ADD  A, E
    JP   PE, .as_ovf
    LD   E, A
    RET
.as_ovf:
    BIT  7, B
    LD   E, 127
    RET  Z
    LD   E, 0x80
    RET

.div10_signed:
    BIT  7, E
    JR   Z, .d10_pos
    XOR  A
    SUB  E
    LD   L, A
    LD   H, 0
    LD   C, 10
    CALL div_hl_c
    XOR  A
    SUB  L
    LD   E, A
    RET
.d10_pos:
    LD   L, E
    LD   H, 0
    LD   C, 10
    CALL div_hl_c
    LD   E, L
    RET

.dex_adj:
    CP   3
    JR   NC, .d3
    LD   A, 0xF8
    RET
.d3:
    CP   19
    JR   NC, .d19
    SUB  3
    LD   E, A
    LD   D, 0
    LD   HL, ovl_actions_dex_disarm_tbl
    ADD  HL, DE
    LD   A, (HL)
    RET
.d19:
    CP   59
    LD   A, 4
    RET  C
    LD   A, (player_data + PL_DEX_CUR)
    CP   94
    LD   A, 5
    RET  C
    LD   A, (player_data + PL_DEX_CUR)
    CP   117
    LD   A, 6
    RET  C
    LD   A, 8
    RET

.int_adj:
    CP   6
    JR   NC, .i6
    SUB  6
    RET
.i6:
    CP   8
    LD   A, 0
    RET  C
    LD   A, (player_data + PL_INT_CUR)
    CP   15
    LD   A, 1
    RET  C
    LD   A, (player_data + PL_INT_CUR)
    CP   18
    LD   A, 2
    RET  C
    LD   A, (player_data + PL_INT_CUR)
    CP   19
    LD   A, 3
    RET  C
    LD   A, (player_data + PL_INT_CUR)
    CP   69
    LD   A, 4
    RET  C
    LD   A, 5
    RET

; ovl_actions_calc_search_chance — Compute clamped search % (1..99) in A
ovl_actions_calc_search_chance:
    LD   A, (player_data + PL_RACE)
    CP   RACE_COUNT
    JR   C, .r_ok
    XOR  A
.r_ok:
    LD   E, A
    LD   D, 0
    LD   HL, ovl_actions_race_search
    ADD  HL, DE
    LD   C, (HL)
    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .c_ok
    XOR  A
.c_ok:
    LD   E, A
    LD   HL, ovl_actions_class_search
    ADD  HL, DE
    LD   A, C
    ADD  A, (HL)
    BIT  7, A
    JR   Z, .pos
    LD   A, 1
.pos:
    LD   L, A
    LD   H, 0
    LD   A, (zp_eff_confuse)
    OR   A
    JR   Z, .chk_dim
    LD   C, 10
    CALL div_hl_c
.chk_dim:
    LD   A, (zp_eff_blind)
    OR   A
    JR   NZ, .div10_b
    LD   A, (player_data + PL_LIGHT_RAD)
    OR   A
    JR   NZ, .ret_s
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    CALL map_get_tile
    JR   C, .div10_b
    BIT  3, A                   ; FLAG_LIT on player tile
    JR   NZ, .ret_s
.div10_b:
    LD   C, 10
    CALL div_hl_c
.ret_s:
    LD   A, L
    RET

; ovl_actions_stage_hidden_drop — Push 1 object drop onto md_queue & print found msg
ovl_actions_stage_hidden_drop:
    LD   HL, md_queue_count
    LD   A, (HL)
    CP   MD_QUEUE_MAX
    JR   NC, .shd_msg
    LD   E, A
    LD   D, 0
    INC  (HL)
    LD   HL, md_queue_x
    ADD  HL, DE
    LD   A, (abi_player_x)
    LD   (HL), A
    LD   HL, md_queue_y
    ADD  HL, DE
    LD   A, (abi_player_y)
    LD   (HL), A
    LD   HL, md_queue_flags
    ADD  HL, DE
    LD   (HL), 0x11
.shd_msg:
    LD   A, HSTR_TUN_FOUND
    JP   msg_print_huff

; ovl_actions_apply_trap_dmg — HL = dmg16, A = death_src -> CF=1 if died
ovl_actions_apply_trap_dmg:
    PUSH HL
    CALL turn_apply_one_damage  ; CF=1 if dead
    POP  HL
    PUSH AF                     ; Save CF=dead across message print
    LD   A, L
    PUSH AF
    LD   A, HSTR_DF_DAMAGE_PRE
    LD   DE, temp_str_buf
    CALL huff_decode_string     ; HL = temp_str_buf
.at_end:
    LD   A, (HL)
    OR   A
    JR   Z, .at_num
    INC  HL
    JR   .at_end
.at_num:
    POP  AF
    EX   DE, HL
    CALL fmt_u8_dec             ; advances DE to NUL
    PUSH DE
    LD   A, HSTR_DF_DAMAGE_POST
    LD   DE, line_buf
    CALL huff_decode_string
    POP  DE
    CALL _oa_cpystr
    XOR  A
    LD   (DE), A
    LD   HL, temp_str_buf
    CALL msg_print_str
    POP  AF                     ; Recover CF=dead
    RET

; ovl_actions_spawn_vein_gold — Drop gold at (df_target_x, df_target_y) in fi_*
; Output: CF = 1 placed (increments zp_item_count & abi_item_count), CF = 0 array full
ovl_actions_spawn_vein_gold:
    LD   B, 0
    LD   C, 0
.lp:
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .slot
    INC  C
    LD   A, C
    CP   MAX_FLOOR_ITEMS
    JR   C, .lp
    OR   A                      ; CF = 0: full
    RET
.slot:
    LD   A, ITEM_SLOT_GOLD_LARGE + 1
    CALL rng_range
    LD   (HL), A                ; fi_item_id = rng(2) (0..1)
    LD   HL, fi_x
    ADD  HL, BC
    LD   A, (df_target_x)
    LD   (HL), A
    LD   HL, fi_y
    ADD  HL, BC
    LD   A, (df_target_y)
    LD   (HL), A
    LD   HL, fi_qty
    ADD  HL, BC
    PUSH HL
    LD   A, (abi_player_dlvl)
    LD   D, A
    ADD  A, A
    ADD  A, D
    ADD  A, 5                   ; (dlvl * 3 + 5) & 0xFF
    CALL rng_range
    ADD  A, A
    INC  A                      ; rng(base) * 2 + 1
    POP  HL
    LD   (HL), A
    LD   HL, fi_p1
    ADD  HL, BC
    LD   (HL), 0
    LD   HL, fi_to_hit
    ADD  HL, BC
    LD   (HL), 0
    LD   HL, fi_to_dam
    ADD  HL, BC
    LD   (HL), 0
    LD   HL, fi_to_ac
    ADD  HL, BC
    LD   (HL), 0
    LD   HL, fi_meta
    ADD  HL, BC
    LD   (HL), 0
    LD   HL, fi_meta_hi
    ADD  HL, BC
    LD   (HL), 0
    LD   HL, zp_item_count
    INC  (HL)
    LD   A, (HL)
    LD   (abi_item_count), A
    SCF
    RET

; ovl_actions_roll_dice — Roll BdC -> HL
ovl_actions_roll_dice:
    LD   HL, 0
.lp:
    LD   A, C
    CALL rng_range
    INC  A
    ADD  A, L
    LD   L, A
    JR   NC, .nc
    INC  H
.nc:
    DJNZ .lp
    RET

; ovl_actions_add_timer — (HL) = min(255, (HL) + B + rng_range(C))
ovl_actions_add_timer:
    LD   A, C
    CALL rng_range
    ADD  A, B
    ADD  A, (HL)
    JR   NC, .ok
    LD   A, 255
.ok:
    LD   (HL), A
    RET

; ovl_actions_add_xp_a — Award A XP via OVL_MODAL (handles PL_MAX_XP + level-up)
ovl_actions_add_xp_a:
    LD   L, A
    LD   H, 0
    JP   tramp_modal_award_xp

; ovl_actions_set_hstr_death — Input: A=hstr, E=death_src, HL=dmg (preserved)
ovl_actions_set_hstr_death:
    PUSH HL
    LD   (df_death_hstr), A
    LD   A, E
    LD   (df_death_source), A
    LD   A, (df_death_hstr)
    LD   DE, temp_str_buf
    CALL huff_decode_string
    LD   HL, temp_str_buf
    LD   DE, death_cause_buf
    LD   BC, 31
    LDIR
    XOR  A
    LD   (DE), A
    LD   A, (df_death_source)
    POP  HL
    RET

; ovl_actions_set_str_death — Input: DE=asciiz, A=death_src, HL=dmg (preserved)
ovl_actions_set_str_death:
    PUSH HL
    LD   (df_death_source), A
    XOR  A
    LD   (df_death_hstr), A
    EX   DE, HL
    LD   DE, death_cause_buf
    LD   B, 31
.cp:
    LD   A, (HL)
    LD   (DE), A
    OR   A
    JR   Z, .done
    INC  HL
    INC  DE
    DJNZ .cp
    XOR  A
    LD   (DE), A
.done:
    LD   A, (df_death_source)
    POP  HL
    RET

; _oa_print_in_way — A=slot, HL=monster ptr -> "The <name> is in your way!"
_oa_print_in_way:
    LD   (cmb_slot), A
    LD   BC, MX_TYPE
    ADD  HL, BC
    LD   A, (HL)
    LD   (cmb_type), A
    CALL _oa_append_mon_name
    LD   HL, temp_str_buf
    RES  5, (HL)
    LD   HL, .s_in_way
    CALL _oa_cpystr
    XOR  A
    LD   (DE), A
    JP   _oa_print_buf
.s_in_way: DB " is in your way!", 0

; ovl_actions_bash_monster — VMS shield bash against monster at (df_target_x,y).
; Input: A = slot (0..31), HL = monster_table + slot*12
; Output: CF = 1 (turn consumed)
ovl_actions_bash_monster:
    LD   (cmb_slot), A
    LD   DE, MX_TYPE
    ADD  HL, DE
    LD   A, (HL)
    LD   (cmb_type), A
    LD   DE, MX_FLAGS - MX_TYPE
    ADD  HL, DE
    SET  2, (HL)                    ; MF_PROVOKED
    LD   A, (cmb_slot)
    CALL monster_wake               ; MF_AWAKE=1, MX_SLEEP_CUR=0

    ; Compute base bash to-hit: min(255, STR/6 + 25 + level * class_bth)
    LD   A, (player_data + PL_STR_CUR)
    LD   L, A
    LD   H, 0
    LD   C, 6
    CALL div_hl_c
    LD   A, L
    ADD  A, 25
    LD   E, A
    LD   A, (player_data + PL_CLASS)
    LD   C, A
    ADD  A, A
    ADD  A, A
    ADD  A, C
    LD   C, A
    LD   B, 0
    LD   HL, class_level_adj
    ADD  HL, BC
    LD   L, (HL)
    LD   H, 0
    LD   A, (player_data + PL_LEVEL)
    PUSH DE
    CALL mul_hl_a
    POP  DE
    LD   A, L
    LD   (cmb_any_hit), A           ; save level * class_bth (<= 160) for crit
    LD   D, 0
    ADD  HL, DE
    LD   A, H
    OR   A
    LD   A, L
    JR   Z, .th_ok
    LD   A, 0xFF
.th_ok:
    LD   (cmb_total_tohit), A

    ; Blows: DEX < 19 -> 1, < 118 -> 2, 118 -> 3
    LD   A, (player_data + PL_DEX_CUR)
    LD   B, 1
    CP   19
    JR   C, .blows_ok
    INC  B
    CP   118
    JR   C, .blows_ok
    INC  B
.blows_ok:
    LD   C, 0                       ; C = hit_alive flag

.blow_loop:
    PUSH BC
    ; d20 attack roll: 1 always misses, 20 always hits
    LD   A, 20
    CALL rng_range
    INC  A
    CP   1
    JR   Z, .miss
    CP   20
    JR   Z, .hit
    LD   A, (cmb_total_tohit)
    CP   2
    JR   C, .miss
    CALL rng_range                  ; [0..tohit-1]
    LD   E, A
    LD   A, (cmb_type)
    LD   C, A
    LD   B, 0
    LD   HL, cr_ac
    ADD  HL, BC
    LD   A, E
    CP   (HL)
    JR   NC, .hit

.miss:
    LD   HL, .s_miss
    CALL _oa_print_mon_act
    JR   .next_blow

.hit:
    ; Roll shield damage dice (0 if no shield equipped)
    LD   D, 0
    LD   A, (inv_item_id + EQUIP_SHIELD)
    CP   EMPTY_SLOT
    JR   Z, .have_dice
    LD   B, A
    LD   A, (inv_ego + EQUIP_SHIELD)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, B
    CALL icat_select_id
    JR   NC, .sh_dmg
    LD   D, 0
    JR   .have_dice
.sh_dmg:
    CALL icat_get_dmg               ; D = dice, E = sides
    LD   B, D
    LD   C, E
    CALL roll_dice_bc               ; A = clamped sum
    LD   D, A
.have_dice:
    ; Critical blow using weight = PL_STR_CUR
    CALL _oa_bash_crit              ; updates D
    LD   A, D
    ADD  A, 3                       ; BASH_TODAM
    JR   NC, .dmg_ok
    LD   A, 0xFF
.dmg_ok:
    LD   D, A
    LD   A, (cmb_slot)
    CALL monster_get_ptr
    LD   BC, MX_HP_LO
    ADD  HL, BC
    LD   A, (HL)
    SUB  D
    LD   E, A
    INC  HL
    LD   A, (HL)
    SBC  A, 0
    JR   C, .killed
    LD   B, A
    OR   E
    JR   Z, .killed

    ; Hit and survived: store updated HP (HL is at MX_HP_HI)
    LD   (HL), B
    DEC  HL
    LD   (HL), E

    LD   HL, .s_hit
    CALL _oa_print_mon_act
    POP  BC
    LD   C, 1
    JR   .next_blow_dec

.killed:
    LD   HL, .s_kill
    CALL _oa_print_mon_act
    LD   A, (cmb_slot)
    CALL tramp_modal_kill_monster
    POP  BC
    JR   .done_offbal

.next_blow:
    POP  BC
.next_blow_dec:
    DEC  B
    JP   NZ, .blow_loop

.after_blows:
    LD   A, C
    OR   A
    JR   Z, .done_offbal
    LD   A, 2
    CALL rng_range
    ADD  A, 2
    LD   B, A
    LD   A, (cmb_slot)
    CALL monster_get_ptr
    LD   DE, MX_STUN
    ADD  HL, DE
    LD   (HL), B
    CALL _oa_append_mon_name
    LD   HL, temp_str_buf
    RES  5, (HL)
    LD   A, HSTR_BASH_STUNNED
    CALL huff_decode_string
    CALL _oa_print_buf
.done_offbal:
    ; VMS monster bash off-balance: randint(140) > DEX -> 1..3 turns paralysis
    LD   A, 140
    CALL rng_range
    LD   HL, player_data + PL_DEX_CUR
    CP   (HL)
    JR   C, .balanced
    LD   A, 3
    CALL rng_range
    INC  A
    LD   (zp_eff_paralyze), A
    LD   A, HSTR_BASH_OFFBAL
    CALL msg_print_huff
.balanced:
    SCF
    RET

.s_miss: DB "miss ", 0
.s_hit:  DB "hit ", 0
.s_kill: DB "have slain ", 0

; _oa_bash_crit — Apply critical blow multiplier for weight = PL_STR_CUR to D.
_oa_bash_crit:
    PUSH DE
    LD   A, (cmb_any_hit)
    LD   L, A
    LD   H, 0
    LD   A, (player_data + PL_STR_CUR)
    LD   E, A
    LD   D, 0
    ADD  HL, DE

    ; Compute melee_total_tohit_bonus in C (PL_TOHIT + unarmed/heavy penalties)
    LD   A, (player_data + PL_TOHIT)
    LD   C, A
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   EMPTY_SLOT
    JR   Z, .th_unarmed
    LD   A, (wield_missile_type)
    OR   A
    JR   NZ, .th_ready
    LD   DE, (wield_weight_lo)
    LD   A, D
    OR   E
    JR   Z, .th_unarmed
    PUSH HL
    LD   A, (player_data + PL_STR_CUR)
    LD   L, A
    LD   H, 0
    ADD  HL, HL
    ADD  HL, HL
    ADD  HL, HL
    ADD  HL, HL
    LD   B, 0
    PUSH DE
    LD   E, A
    LD   D, 0
    OR   A
    SBC  HL, DE                 ; HL = PL_STR_CUR * 15
    POP  DE
    OR   A
    SBC  HL, DE                 ; CF = 1 if STR*15 < wield_weight
    JR   NC, .th_wt_ok
    LD   A, H
    CP   0xFF
    JR   NZ, .th_cap
    BIT  7, L
    LD   A, L
    JR   NZ, .th_add
.th_cap:
    LD   A, 0x80
.th_add:
    ADD  A, C
    LD   C, A
.th_wt_ok:
    POP  HL
    JR   .th_ready
.th_unarmed:
    LD   A, C
    SUB  3
    LD   C, A
.th_ready:
    LD   A, C
    PUSH AF
    BIT  7, A
    JR   Z, .pos_th
    NEG
.pos_th:
    LD   E, A
    LD   D, 0
    LD   A, 5
    PUSH HL
    CALL mul_de_a
    POP  DE
    POP  AF
    BIT  7, A
    JR   NZ, .neg_sub
    ADD  HL, DE
    JR   .chk_roll
.neg_sub:
    EX   DE, HL
    OR   A
    SBC  HL, DE
    JR   NC, .chk_roll
    LD   HL, 0
.chk_roll:
    PUSH HL
    LD   BC, 5000
    LD   DE, 0x1FFF
    CALL _oa_rng16
    EX   DE, HL
    POP  HL
    OR   A
    SBC  HL, DE
    POP  DE
    RET  Z
    RET  C
    PUSH DE
    LD   BC, 650
    LD   DE, 0x03FF
    CALL _oa_rng16
    LD   A, (player_data + PL_STR_CUR)
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    POP  DE
    LD   B, D
    LD   C, 5
    LD   A, 2
    LD   DE, 400
    OR   A
    SBC  HL, DE
    JR   C, .apply_mult
    INC  A
    LD   C, 10
    LD   DE, 300
    OR   A
    SBC  HL, DE
    JR   C, .apply_mult
    INC  A
    LD   C, 15
    LD   DE, 200
    OR   A
    SBC  HL, DE
    JR   C, .apply_mult
    INC  A
    LD   C, 20
.apply_mult:
    ; HL = orig_dmg * A + C, clamp 255
    LD   E, B
    LD   D, 0
    CALL mul_de_a
    LD   B, 0
    ADD  HL, BC
    LD   A, H
    OR   A
    LD   D, L
    RET  Z
    LD   D, 0xFF
    RET

; _oa_rng16 — Sample HL in [0..BC-1] using bitmask DE. Clobbers AF,HL.
_oa_rng16:
    CALL rng_next_u16
    LD   A, H
    AND  D
    LD   H, A
    LD   A, L
    AND  E
    LD   L, A
    OR   A
    PUSH HL
    SBC  HL, BC
    POP  HL
    JR   NC, _oa_rng16
    RET

; _oa_print_mon_act — Print "You <HL>the <name>." (or "something" if invisible).
_oa_print_mon_act:
    PUSH HL
    LD   HL, _oa_s_you
    LD   DE, temp_str_buf
    CALL _oa_cpystr
    POP  HL
    CALL _oa_cpystr
    CALL _oa_append_mon_name_at
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
_oa_print_buf:
    LD   HL, temp_str_buf
    JP   msg_print_str
_oa_s_you: DB "You ", 0

_oa_cpystr:
    LD   A, (HL)
    OR   A
    RET  Z
    LD   (DE), A
    INC  HL
    INC  DE
    JR   _oa_cpystr

; _oa_append_mon_name — writes "the <name>" / "something" at temp_str_buf, returns DE at end.
_oa_append_mon_name:
    LD   DE, temp_str_buf
_oa_append_mon_name_at:
    LD   A, (cmb_slot)
    CALL monster_get_ptr
    LD   BC, MX_FLAGS
    ADD  HL, BC
    BIT  3, (HL)                    ; MF_VISIBLE
    JR   NZ, .vis
    LD   HL, .s_something
    JR   _oa_cpystr
.vis:
    LD   HL, .s_the
    CALL _oa_cpystr
    LD   A, (cmb_type)
    CALL monster_get_name_ptr
    JR   _oa_cpystr
.s_the: DB "the ", 0
.s_something: DB "something", 0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end
    SAVEBIN "ovl_actions.ovl", ovl_start, ovl_end - ovl_start
