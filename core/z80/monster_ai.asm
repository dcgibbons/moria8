; monster_ai.asm — M4 Resident Monster AI Engine (MON-003..041)
;
; Pure 0xNN hex syntax (sjasmplus v1.24.0). IX and IY preserved across public entries.

    EXPORT monster_ai_tick
    EXPORT monster_try_step

MAX_CAST_RANGE      EQU 8
MSF2_SPELL_MASK     EQU (MSF2_BLINK | MSF2_TELE_SELF | MSF2_SUMMON_UNDEAD | MSF2_SLOW | MSF2_DRAIN_MANA)

    ASSERT (TILE_DOOR_CLOSED ^ 0xF0) == TILE_DOOR_OPEN, "door xor"
    ASSERT zp_mon_y == (zp_mon_x + 1), "zp_mon_x/y"

; ============================================================================
; monster_ai_tick — Execute one full AI pass across slots 0..31.
; Preserves IX, IY.
; ============================================================================
monster_ai_tick:
    PUSH IX
    XOR  A
    LD   (zp_mon_idx), A
    LD   (_mai_scene_dirty), A
    LD   (mat_action_dirty), A
    LD   (mat_force_new_dirty), A
    CALL player_get_stealth
    LD   (_mai_stealth), A

    LD   B, 0
    LD   HL, inv_ego + EQUIP_RING
    CALL _mai_ring_chk
    LD   HL, inv_ego + EQUIP_RING2
    CALL _mai_ring_chk
    LD   A, (inv_item_id + EQUIP_FEET)
    CP   FI_EMPTY
    JR   Z, .chk_spd
    LD   A, (inv_ego + EQUIP_FEET)
    AND  EGO_ID_MASK
    CP   EGO_SPEED
    JR   NZ, .chk_slow_b
    INC  B
    JR   .chk_spd
.chk_slow_b:
    CP   EGO_SLOWNESS
    JR   NZ, .chk_spd
    DEC  B
.chk_spd:
    LD   A, (zp_eff_speed)
    OR   A
    JR   Z, .fast_done
    BIT  7, A
    JR   NZ, .pl_slow
    INC  B
    INC  B
.pl_slow:
    DEC  B
.fast_done:
    LD   A, B
    LD   (mat_fast), A

    LD   HL, (abi_turn)
    LD   A, L
    AND  1
    LD   (mat_turn_mod + 3), A
    LD   A, L
    AND  3
    LD   (mat_turn_mod + 1), A
    LD   A, L
    ADD  A, H
    ADC  A, 0
    LD   C, A
    LD   B, 5
    CALL _mai_mod_b
    LD   (mat_turn_mod), A
    LD   A, C
    LD   B, 3
    CALL _mai_mod_b
    LD   (mat_turn_mod + 2), A

    LD   IX, monster_table
.slot_lp:
    LD   A, (zp_mon_idx)
    CP   MAX_MONSTERS
    JP   NC, .done
    LD   A, (IX + MX_TYPE)
    CP   EMPTY_SLOT
    JP   Z, .next_slot

    LD   (zp_mon_type), A
    LD   E, (IX + MX_X)
    LD   D, (IX + MX_Y)
    LD   (zp_mon_x), DE
    LD   A, (IX + MX_FLAGS)
    LD   (zp_mon_flags), A
    LD   B, (IX + MX_SPEED_CNT)

    LD   HL, cr_speed
    CALL _mai_cr_a
    AND  CR_SPEED_MASK
    LD   C, A
    LD   A, B
    OR   A
    JR   Z, .spd_ready
    BIT  7, A
    JR   NZ, .mon_slow
    LD   A, C
    CP   2
    JR   NC, .spd_ready
    INC  C
    JR   .spd_ready
.mon_slow:
    LD   A, C
    OR   A
    JR   Z, .spd_ready
    DEC  C
.spd_ready:
    LD   A, (mat_fast)
    LD   B, A
    LD   A, C
    SUB  B
    JR   Z, .cadence_slow
    BIT  7, A
    JR   NZ, .cadence_slow
    CP   3
    JR   C, .moves_ok
    LD   A, 2
    JR   .moves_ok
.cadence_slow:
    ADD  A, 3
    BIT  7, A
    JR   Z, .midx_ok
    XOR  A
.midx_ok:
    LD   HL, mat_turn_mod
    CALL _mc_add_a_hl
    OR   A
    JR   NZ, .next_slot
    LD   A, 1
.moves_ok:
    LD   (_mai_moves), A
    CALL _mai_act_if_alive
    JR   C, .done
    LD   A, (_mai_moves)
    DEC  A
    JR   Z, .next_slot
    CALL _mai_act_if_alive
    JR   C, .done

.next_slot:
    LD   DE, MONSTER_ENTRY_SIZE
    ADD  IX, DE
    LD   HL, zp_mon_idx
    INC  (HL)
    JP   .slot_lp

.done:
    LD   A, (_mai_scene_dirty)
    OR   A
    JR   Z, .ret_ix
    LD   HL, zp_dirty_count
    INC  (HL)
.ret_ix:
    POP  IX
    RET

_mai_mod_b:
    CP   B
    RET  C
    SUB  B
    JR   _mai_mod_b

_mai_ring_chk:
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    RET  Z
    LD   DE, inv_item_id - inv_ego
    ADD  HL, DE
    LD   A, (HL)
    CP   ITEM_SLOT_RING_OF_SPEED
    RET  NZ
    INC  B
    RET

_mai_act_if_alive:
    LD   A, (IX + MX_TYPE)
    CP   EMPTY_SLOT
    CALL NZ, _mai_process_one
    LD   A, (abi_game_flags)
    RRA
    RET

; _mai_process_one — IX points to current monster slot.
_mai_process_one:
    XOR  A
    LD   (mat_action_dirty), A
    LD   (mat_force_new_dirty), A

    LD   A, (zp_mon_flags)
    AND  MF_AWAKE
    JR   NZ, .chk_awake_aware
    CALL _mai_wake_check
    LD   A, (zp_mon_flags)
    AND  MF_AWAKE
    RET  Z
    JR   .awake
.chk_awake_aware:
    LD   A, (zp_mon_flags)
    AND  MF_VISIBLE
    JR   NZ, .awake
    CALL _mai_in_aaf_range
    RET  C

.awake:
    LD   A, (IX + MX_STUN)
    OR   A
    JR   Z, .not_stunned
    DEC  (IX + MX_STUN)
    JR   .writeback
.not_stunned:
    LD   A, (IX + MX_CONFUSE)
    OR   A
    JR   Z, .not_confused
    DEC  (IX + MX_CONFUSE)
    JR   .confused_move

.not_confused:
    CALL _mai_can_cast
    JR   NC, .no_cast
    CALL tramp_mon_ext_cast
    LD   A, 0x03
    JR   .set_act_wb
.no_cast:
    LD   A, (zp_mon_type)
    CP   TOWN_CREATURE_BASE
    JR   C, .not_town
    LD   A, (zp_mon_flags)
    AND  MF_PROVOKED
    JR   NZ, .not_town
    CALL _mai_move_random
    JR   NC, .writeback
    LD   A, 0x81
    JR   .set_act_wb

.not_town:
    LD   HL, cr_speed
    CALL _mai_cr_a
    AND  CM_RANDOM_MOVE
    JR   Z, .no_rand
    LD   C, A
    LD   B, 3
    LD   HL, _mai_rand_tbl
.rand_lp:
    LD   A, (HL)
    INC  HL
    AND  C
    LD   A, (HL)
    INC  HL
    JR   Z, .rand_next
    LD   D, A
    LD   A, 100
    CALL rng_range
    CP   D
    JR   C, .confused_move
.rand_next:
    DJNZ .rand_lp

.no_rand:
    CALL _mai_move_toward
    JR   NC, .writeback
    LD   A, 0x83
    JR   .set_act_wb

.confused_move:
    CALL _mai_move_random
    JR   NC, .writeback
    LD   A, 0x83
.set_act_wb:
    LD   (mat_action_dirty), A

.writeback:
    LD   DE, (zp_mon_x)
    LD   (IX + MX_X), E
    LD   (IX + MX_Y), D
    LD   A, (zp_mon_flags)
    LD   (IX + MX_FLAGS), A

    LD   A, (mat_action_dirty)
    BIT  7, A
    CALL NZ, _mai_mark_move_dirty

    LD   HL, cr_mflags
    CALL _mai_cr_a
    AND  CF_BREEDER
    JR   Z, .finish
    LD   A, (zp_mon_count)
    CP   MAX_MONSTERS - 4
    JR   NC, .finish
    LD   A, (auto_rest_active)
    OR   A
    JR   Z, .breed_cnt
    LD   A, MON_MULT_ADJ
    CALL rng_range
    OR   A
    JR   NZ, .finish
.breed_cnt:
    CALL _mai_count_neighbours
    CP   4
    JR   NC, .finish
    OR   A
    JR   Z, .finish
    DEC  A
    LD   HL, _mai_breed_odds
    CALL _mc_add_a_hl
    CALL rng_range
    OR   A
    JR   NZ, .finish
    LD   BC, (zp_mon_x)
    CALL find_adjacent_empty_tile
    JR   NC, .finish
    LD   A, (zp_mon_type)
    CALL monster_spawn_awake
    JR   NC, .finish
    LD   A, 0x03
    LD   (mat_action_dirty), A
    LD   BC, (ms_spawn_x)
    CALL _mai_mark_tile_dirty

.finish:
    LD   A, (mat_action_dirty)
    AND  0x02
    RET  Z
    LD   A, (zp_mon_flags)
    AND  MF_VISIBLE
    RET  Z
    LD   HL, zp_disturb
    INC  (HL)
    RET

; ============================================================================
; Wake, Awareness & Cast Check
; ============================================================================

_mai_dist_to_player:
    LD   DE, (zp_mon_x)
    LD   HL, (abi_player_x)
    JP   _mc_cheb_dist_hl_de

; Returns CF=1 if dist > (cr_aaf & 0x7F); sets C = dist.
_mai_in_aaf_range:
    CALL _mai_dist_to_player
    LD   C, A
    LD   HL, cr_aaf
    CALL _mai_cr_a
    AND  0x7F
    CP   C
    RET

_mai_wake_check:
    CALL _mai_in_aaf_range
    JR   NC, .in_aware
    LD   A, (zp_mon_flags)
    AND  MF_VISIBLE
    RET  Z
.in_aware:
    LD   A, (player_pflags2)
    AND  PFLAG2_AGGRAVATE
    JR   NZ, .wake_now

    LD   A, (IX + MX_SLEEP_CUR)
    OR   A
    JR   Z, .wake_now

    LD   A, (auto_rest_active)
    OR   A
    RET  NZ

    LD   A, 10
    CALL rng_range
    LD   HL, _mai_stealth
    CP   (HL)
    RET  C
    LD   A, C
    CP   6
    JR   C, .step_ok
    LD   A, 6
.step_ok:
    LD   HL, _mai_wake_step
    CALL _mc_add_a_hl
    LD   B, A
    LD   A, (IX + MX_SLEEP_CUR)
    SUB  B
    JR   NC, .st_slp
    XOR  A
.st_slp:
    LD   (IX + MX_SLEEP_CUR), A
    RET  NZ

.wake_now:
    LD   A, (zp_mon_flags)
    OR   MF_AWAKE
    LD   (zp_mon_flags), A
    LD   HL, cr_mflags
    CALL _mai_cr_a
    BIT  5, A
    RET  Z
    LD   B, 0
    LD   HL, monster_table
.grp_lp:
    LD   A, (zp_mon_idx)
    CP   B
    JR   Z, .grp_next
    PUSH HL
    LD   E, (HL)                ; MX_X
    INC  HL
    LD   D, (HL)                ; MX_Y
    INC  HL
    LD   A, (HL)                ; MX_TYPE
    LD   C, A
    LD   A, (zp_mon_type)
    CP   C
    JR   NZ, .grp_pop
    INC  HL
    INC  HL
    INC  HL
    BIT  0, (HL)
    JR   NZ, .grp_pop
    LD   HL, (zp_mon_x)
    PUSH BC
    CALL _mc_cheb_dist_hl_de
    POP  BC
    CP   6
    LD   A, B
    CALL C, monster_wake
.grp_pop:
    POP  HL
.grp_next:
    LD   DE, MONSTER_ENTRY_SIZE
    ADD  HL, DE
    INC  B
    LD   A, B
    CP   MAX_MONSTERS
    JR   C, .grp_lp
    RET

_mai_can_cast:
    LD   HL, cr_spell_chance
    CALL _mai_cr_a
    LD   B, A
    AND  MS_FREQ_MASK
    JR   Z, .no
    LD   C, A
    LD   HL, cr_spell_flags2
    CALL _mai_cr_a
    AND  MSF2_SPELL_MASK
    LD   HL, cr_spell_flags
    CALL _mc_cr_or_a
    JR   NZ, .has_spl
    BIT  7, B
    JR   Z, .no
.has_spl:
    CALL _mai_dist_to_player
    CP   MAX_CAST_RANGE + 1
    JR   NC, .no
    CP   2
    JR   C, .los_ok
    PUSH BC
    LD   BC, (zp_mon_x)
    LD   DE, (abi_player_x)
    CALL los_check
    POP  BC
    JR   NC, .no
.los_ok:
    LD   A, C
    CALL rng_range
    OR   A
    JR   NZ, .no
    SCF
    RET
.no:
    OR   A
    RET

; ============================================================================
; Unified Toward / Away / Random Movement
; ============================================================================

; _mai_move_toward — Step toward player (diagonal first, randomized H/V fallback).
; Output: CF=1 moved/attacked. Keeps E = sign_dx, D = sign_dy across trials.
_mai_move_toward:
    LD   BC, (zp_mon_x)
    LD   A, (abi_player_x)
    CALL _mai_sgn_c
    LD   E, A
    LD   A, (abi_player_y)
    LD   C, B
    CALL _mai_sgn_c
    LD   D, A
    OR   E
    RET  Z
    CALL _mai_try_delta
    RET  C
    CALL rng_next_u8
    AND  1
    JR   NZ, .v_first
.h_first:
    CALL _mai_try_h
    RET  C
    JP   _mai_try_v
.v_first:
    CALL _mai_try_v
    RET  C
    JP   _mai_try_h

_mai_sgn_c:
    CP   C
    JR   Z, .z
    JR   NC, .p
    LD   A, 0xFF
    RET
.p:
    LD   A, 1
    RET
.z:
    XOR  A
    RET

_mai_try_h:
    LD   A, E
    OR   A
    RET  Z
    PUSH DE
    LD   D, 0
    CALL _mai_try_delta
    POP  DE
    RET

_mai_try_v:
    LD   A, D
    OR   A
    RET  Z
    PUSH DE
    LD   E, 0
    CALL _mai_try_delta
    POP  DE
    RET

_mai_try_delta:
    LD   BC, (zp_mon_x)
    LD   A, C
    ADD  A, E
    LD   C, A
    LD   A, B
    ADD  A, D
    LD   B, A
    JP   monster_try_step

_mai_move_random:
    LD   A, 8
    CALL rng_range
    LD   E, A
    LD   HL, dir_dx
    CALL _mc_add_a_hl
    LD   D, A
    LD   A, E
    LD   HL, dir_dy
    CALL _mc_add_a_hl
    LD   E, D
    LD   D, A
    JR   _mai_try_delta

; ============================================================================
; monster_try_step — Execute/validate move or attack to (B=y, C=x).
; Output: CF=1 if moved or attacked, CF=0 if blocked. Preserves IX, IY.
; ============================================================================
monster_try_step:
    LD   (_mai_tgt_x), BC

    CALL _mc_is_player_bc
    JR   NZ, .not_player

    CALL _mai_check_glyph_at
    JR   C, .blocked

    LD   A, (zp_mon_type)
    CP   TOWN_CREATURE_BASE
    JR   C, .do_atk
    LD   A, (zp_mon_flags)
    AND  MF_PROVOKED
    JR   Z, .blocked
.do_atk:
    CALL tramp_mon_ext_attack
    LD   BC, (zp_mon_x)
    LD   (_mai_old_x), BC
    SCF
    RET

.blocked:
    OR   A
    RET

.not_player:
    LD   A, C
    DEC  A
    CP   MAP_COLS - 2
    JR   NC, .blocked
    LD   A, B
    DEC  A
    CP   MAP_ROWS - 2
    JR   NC, .blocked

    CALL map_get_tile
    JR   C, .blocked
    LD   (_mai_tgt_tile), A

    CALL tile_is_walkable_a
    JR   C, .walk_ok
    LD   A, (abi_player_dlvl)
    OR   A
    JP   Z, .door_block
    LD   HL, cr_spell_flags2
    CALL _mai_cr_a
    AND  CM2_PHASE
    JP   Z, .door_block

.walk_ok:
    LD   HL, cr_mflags
    CALL _mai_cr_a
    AND  CF_ATTACK_ONLY
    JR   NZ, .blocked

    LD   A, EMPTY_SLOT
    LD   (_mai_eat_slot), A
    LD   A, (_mai_tgt_tile)
    AND  FLAG_OCCUPIED
    JR   Z, .unoccupied

    LD   HL, cr_spell_flags2
    CALL _mai_cr_a
    AND  CM2_EATS_OTHER
    JR   Z, .blocked
    CALL monster_find_at
    JP   NC, .unoccupied
    LD   D, A
    LD   A, (zp_mon_idx)
    CP   D
    JR   Z, .blocked
    LD   A, D
    LD   (_mai_eat_slot), A
    INC  HL
    INC  HL
    LD   A, (HL)
    PUSH AF
    CALL monster_is_balrog_slot
    JR   NZ, .not_balrog
    POP  AF
    JP   .blocked
.not_balrog:
    POP  AF
    CALL _mai_cmp_xp_mover_ge_a
    LD   BC, (_mai_tgt_x)
    JR   C, .blocked

.unoccupied:
    CALL _mai_check_glyph_at
    JR   C, .blocked
    JR   Z, .no_glyph
    LD   A, 0x03
    LD   (mat_action_dirty), A
    LD   HL, mat_force_new_dirty
    INC  (HL)
.no_glyph:
    LD   A, (_mai_eat_slot)
    CP   EMPTY_SLOT
    JR   Z, .no_eat
    PUSH AF
    CALL monster_get_ptr
    LD   DE, MX_FLAGS
    ADD  HL, DE
    LD   A, (HL)
    AND  (MF_VISIBLE | MF_DETECTED)
    LD   HL, mat_force_new_dirty
    OR   (HL)
    LD   (HL), A
    POP  AF
    CALL monster_remove
.no_eat:
    LD   A, (_mai_tgt_tile)
    AND  FLAG_HAS_ITEM
    JR   Z, .no_pickup
    LD   HL, cr_spell_flags2
    CALL _mai_cr_a
    AND  CM2_PICKS_UP
    JR   Z, .no_pickup
    LD   BC, (_mai_tgt_x)
    CALL floor_item_find_at
    JR   NC, .no_pickup
    LD   C, A
    LD   HL, fi_meta_hi
    CALL _mc_add_a_hl
    AND  ITEM_PAGE_BIT
    JR   NZ, .eat_item
    LD   A, C
    LD   HL, fi_item_id
    CALL _mc_add_a_hl
    CP   ITEM_SLOT_GOLD_MITHRIL + 1
    JR   C, .no_pickup
.eat_item:
    LD   A, C
    CALL floor_item_remove
    LD   HL, mat_force_new_dirty
    INC  (HL)

.no_pickup:
    LD   BC, (zp_mon_x)
    LD   (_mai_old_x), BC
    CALL _mc_tile_clr_occ
    LD   BC, (_mai_tgt_x)
    LD   (zp_mon_x), BC
    LD   A, FLAG_OCCUPIED
    CALL _mc_tile_or_a
    SCF
    RET

.door_block:
    LD   A, (_mai_tgt_tile)
    AND  TILE_TYPE_MASK
    CP   TILE_SECRET
    JR   Z, .secret
    CP   TILE_DOOR_CLOSED
    JR   NZ, .blocked_nc
    LD   A, (_mai_tgt_tile)
    AND  FLAG_OCCUPIED
    JR   NZ, .blocked_nc

    LD   BC, (_mai_tgt_x)
    CALL _mai_door_find
    LD   E, A
    AND  0x7F
    LD   (_mai_door_abs), A

    LD   HL, cr_aaf
    CALL _mai_cr_a
    BIT  7, A
    JR   Z, .bash

    LD   A, E
    OR   A
    JR   NZ, .opener_roll
    CALL _mai_write_open
    OR   A
    RET
.opener_roll:
    LD   B, 50
    LD   C, 10
    JR   .do_door_roll
.bash:
    LD   B, 80
    LD   C, 20
    LD   E, 0x80                ; bash always bursts on pass
.do_door_roll:
    LD   A, (_mai_door_abs)
    LD   D, A
    ADD  A, B
    LD   B, A                   ; A_term = abs + (50|80)
    LD   A, D
    ADD  A, C                   ; B_term = abs + (10|20)
    LD   D, B
    PUSH DE                     ; save E bit 7
    LD   E, A
    CALL _mai_mts_state_roll
    POP  DE
    JR   NC, .blocked_nc
    BIT  7, E
    JR   NZ, .burst_open
    XOR  A
    CALL _mai_door_set_target
.blocked_nc:
    OR   A
    RET

.burst_open:
    CALL _mai_write_open
    LD   A, 2
    CALL rng_range
    OR   A
    JR   NZ, .unbroken
    LD   A, (_mai_door_abs)
    OR   A
    JR   NZ, .brk_set
    LD   A, (door_state_count)
    CP   MAX_DOOR_STATES
    JR   NC, .unbroken
.brk_set:
    LD   A, 1
    JR   .set_st
.unbroken:
    XOR  A
.set_st:
    CALL _mai_door_set_target
    LD   A, HSTR_MAT_DOOR_BURST
    CALL msg_print_huff
    LD   HL, zp_disturb
    INC  (HL)
    OR   A
    RET

.secret:
    LD   HL, cr_aaf
    CALL _mai_cr_a
    BIT  7, A
    JP   NZ, .walk_ok
    OR   A
    RET

; ============================================================================
; AI Sub-Helpers
; ============================================================================

_mai_cr_a:
    LD   A, (zp_mon_type)
    JP   _mc_add_a_hl

_mc_cr_or_a:
    LD   D, A
    LD   A, (zp_mon_type)
    CALL _mc_add_a_hl
    OR   D
    RET

_mai_write_open:
    LD   A, (_mai_tgt_tile)
    XOR  0xF0
    LD   BC, (_mai_tgt_x)
    CALL map_set_tile
    LD   A, 0x03
    LD   (mat_action_dirty), A
    JP   _mai_mark_tile_dirty

_mai_mts_state_roll:
    LD   A, (zp_mon_idx)
    CALL monster_get_ptr
    INC  HL
    INC  HL
    INC  HL
    LD   C, (HL)
    INC  HL
    LD   A, (HL)
    OR   A
    JR   NZ, .cap254
    LD   A, C
    CP   255
    JR   NZ, .hp_ready
.cap254:
    LD   A, 254
.hp_ready:
    CP   E
    JR   C, .fail
    JR   Z, .fail
    LD   B, A
    SUB  E
    PUSH BC
    PUSH DE
    LD   E, A
    LD   D, 0
    LD   A, 40
    CALL mul_de_a
    DEC  HL
    POP  DE
    POP  BC
    PUSH HL
    LD   A, B
    INC  A
    LD   E, A
    LD   A, D
    LD   D, 0
    CALL mul_de_a
    CALL _mc_rng_range_16
    POP  DE
    OR   A
    SBC  HL, DE
    RET
.fail:
    OR   A
    RET

_mai_door_find:
    LD   A, (door_state_count)
    OR   A
    RET  Z
    LD   D, A
    LD   E, 0
.lp:
    LD   A, E
    LD   HL, door_state_x
    CALL _mc_add_a_hl
    CP   C
    JR   NZ, .next
    LD   A, E
    LD   HL, door_state_y
    CALL _mc_add_a_hl
    CP   B
    JR   NZ, .next
    LD   A, E
    LD   HL, door_state_val
    CALL _mc_add_a_hl
    SCF
    RET
.next:
    INC  E
    LD   A, E
    CP   D
    JR   C, .lp
    XOR  A
    RET

_mai_door_set_target:
    PUSH AF
    LD   BC, (_mai_tgt_x)
    CALL _mai_door_find
    JR   NC, .not_found
    POP  AF
    OR   A
    JR   Z, .remove
    LD   HL, door_state_val
    LD   D, 0
    ADD  HL, DE
    LD   (HL), A
    RET
.remove:
    LD   HL, door_state_count
    DEC  (HL)
    LD   A, (HL)
    CP   E
    RET  Z
    LD   C, A
    LD   HL, door_state_x
    LD   B, 3
.sw_lp:
    PUSH BC
    PUSH HL
    LD   A, C
    CALL _mc_add_a_hl
    LD   B, A
    POP  HL
    PUSH HL
    LD   A, E
    CALL _mc_add_a_hl_raw
    LD   (HL), B
    POP  HL
    LD   BC, MAX_DOOR_STATES
    ADD  HL, BC
    POP  BC
    DJNZ .sw_lp
    RET
.not_found:
    POP  AF
    OR   A
    RET  Z
    PUSH AF
    LD   HL, door_state_count
    LD   E, (HL)
    LD   A, E
    CP   MAX_DOOR_STATES
    JR   NC, .nf_full
    INC  (HL)
    LD   A, E
    LD   HL, door_state_x
    CALL _mc_add_a_hl_raw
    LD   (HL), C
    LD   DE, MAX_DOOR_STATES
    ADD  HL, DE
    LD   (HL), B
    ADD  HL, DE
    POP  AF
    LD   (HL), A
    RET
.nf_full:
    POP  AF
    RET

; _mai_check_glyph_at — Test & break glyph at (B=y, C=x).
; Output: CF=1 holds (blocked); CF=0 & Z=1 no glyph; CF=0 & NZ broke glyph.
_mai_check_glyph_at:
    CALL _mai_glyph_find_at
    JR   C, .found
    XOR  A                      ; CF=0, Z=1
    RET
.found:
    PUSH AF
    CALL _mai_should_break_glyph
    JR   C, .holds
    POP  AF
    LD   HL, glyph_active
    CALL _mc_add_a_hl_raw
    LD   (HL), 0
    OR   1                      ; CF=0, NZ
    RET
.holds:
    POP  AF
    SCF
    RET

; _mai_cmp_xp_mover_ge_a — CF=0 iff cr_xp[zp_mon_type] >= cr_xp[A].
_mai_cmp_xp_mover_ge_a:
    CALL _mai_xp_hl
    PUSH HL
    LD   A, (zp_mon_type)
    CALL _mai_xp_hl
    POP  DE
    OR   A
    SBC  HL, DE
    RET

_mai_xp_hl:
    LD   HL, cr_xp_lo
    CALL _mc_add_a_hl_raw
    LD   E, (HL)
    LD   BC, MAX_CREATURES
    ADD  HL, BC
    LD   D, (HL)
    EX   DE, HL
    RET

_mai_glyph_find_at:
    LD   E, 0
.lp:
    LD   A, E
    LD   HL, glyph_active
    CALL _mc_add_a_hl
    OR   A
    JR   Z, .next
    LD   A, E
    LD   HL, glyph_x
    CALL _mc_add_a_hl
    CP   C
    JR   NZ, .next
    LD   A, E
    LD   HL, glyph_y
    CALL _mc_add_a_hl
    CP   B
    JR   NZ, .next
    LD   A, E
    SCF
    RET
.next:
    INC  E
    LD   A, E
    CP   MAX_GLYPHS
    JR   C, .lp
    OR   A
    RET

_mai_glyph_remove:
    LD   HL, glyph_active
    CALL _mc_add_a_hl_raw
    LD   (HL), 0
    RET

_mai_should_break_glyph:
    LD   HL, 3000
    CALL _mc_rng_range_16
    INC  HL
    LD   A, H
    OR   A
    JR   NZ, .holds
    LD   C, L
    LD   HL, cr_level
    CALL _mai_cr_a
    LD   B, A
    LD   A, C
    CP   B
    CCF
    RET
.holds:
    SCF
    RET

_mai_count_neighbours:
    LD   BC, (zp_mon_x)
    DEC  B
    DEC  C
    LD   L, 0
    LD   D, 3
.r: LD   E, 3
.c: CALL map_get_tile
    JR   C, .nx
    AND  FLAG_OCCUPIED
    JR   Z, .nx
    INC  L
.nx:
    INC  C
    DEC  E
    JR   NZ, .c
    DEC  C
    DEC  C
    DEC  C
    INC  B
    DEC  D
    JR   NZ, .r
    LD   A, L
    RET

_mai_mark_move_dirty:
    LD   A, (mat_force_new_dirty)
    PUSH AF
    XOR  A
    LD   (mat_force_new_dirty), A
    LD   BC, (_mai_old_x)
    CALL _mai_mark_tile_dirty
    POP  AF
    LD   (mat_force_new_dirty), A
    LD   BC, (zp_mon_x)

_mai_mark_tile_dirty:
    LD   A, (abi_view_x)
    LD   D, A
    LD   A, C
    SUB  D
    JR   C, .done
    CP   VIEWPORT_W
    JR   NC, .done
    LD   A, (abi_view_y)
    LD   D, A
    LD   A, B
    SUB  D
    JR   C, .done
    CP   VIEWPORT_H
    JR   NC, .done
    LD   A, (zp_mon_flags)
    AND  (MF_VISIBLE | MF_DETECTED)
    LD   HL, mat_force_new_dirty
    OR   (HL)
    JR   Z, .done
    LD   HL, _mai_scene_dirty
    INC  (HL)
.done:
    XOR  A
    LD   (mat_force_new_dirty), A
    RET

_mai_wake_step:   DB 8, 8, 4, 3, 2, 2, 1
_mai_breed_odds:  DB MON_MULT_ADJ, 2 * MON_MULT_ADJ, 3 * MON_MULT_ADJ
_mai_rand_tbl:    DB 0x20, 74, 0x10, 39, 0x08, 19
