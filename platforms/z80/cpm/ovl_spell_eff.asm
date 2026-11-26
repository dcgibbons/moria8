; ovl_spell_eff.asm — Moria8 CP/M Spell, Prayer & Shared Area/Bolt/Ball/Poly Effects Overlay
; (OVL_SPELL_EFF = 16, DAT slot 21)
;
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0:  JP ovl_spell_eff_execute (uses pm_spell_type, pm_spell_idx)
;   +3:  JP ovl_spell_eff_bolt    (eff_arg0=dice, eff_arg1=sides, eff_arg2=elem, eff_arg3=range, proj_dir)
;   +6:  JP ovl_spell_eff_ball    (eff_arg0=dmg, eff_arg1=elem, ball_harm, proj_dir)
;   +9:  JP ovl_spell_eff_poly    (A=0 directional poly, A=1 mass poly)
;   +12: JP ovl_spell_eff_area    (A=sub_op 0..25 shared with OVL_ITEMS_EFF)
;
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax, DEVICE NOSLOT64K).
; All public entry vectors preserve IX and IY.
; Never keep live state in overlay-local RAM across any tramp_* call!

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "item_ids_z80.inc"
    DEFINE HUFF_CONSTS_ONLY 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_CONSTS_ONLY
    DEFINE MONSTER_IDX_CONSTS_ONLY 1
    INCLUDE "monster_idx_z80.inc"
    UNDEFINE MONSTER_IDX_CONSTS_ONLY
    INCLUDE "main_exp.inc"

    ORG  OVL_WINDOW_BASE        ; 0x5600

ovl_start:
    JP   ovl_spell_eff_execute
    JP   ovl_spell_eff_bolt
    JP   ovl_spell_eff_ball
    JP   ovl_spell_eff_poly
    JP   ovl_spell_eff_area

; ============================================================================
; +0: ovl_spell_eff_execute — Execute cast spell/prayer (pm_spell_type, pm_spell_idx)
; Output: CF = 1 if executed, CF = 0 if cancelled at direction/item/genocide prompt
; ============================================================================
ovl_spell_eff_execute:
    PUSH IX
    PUSH IY
    LD   A, 0xFF
    LD   (proj_dir), A

    LD   A, (pm_spell_type)
    CP   SPELL_PRIEST
    LD   HL, ovl_spell_eff_mage_tbl
    JR   NZ, .chk_idx
    LD   HL, ovl_spell_eff_priest_tbl
.chk_idx:
    LD   A, (pm_spell_idx)
    CP   31
    JR   NC, .ret_ok
    CALL ovl_spell_eff_tbl_dispatch
    POP  IY
    POP  IX
    RET
.ret_ok:
    SCF
    POP  IY
    POP  IX
    RET

ovl_spell_eff_tbl_dispatch:
    ADD  A, A
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    EX   DE, HL
    JP   (HL)

; ============================================================================
; +3: ovl_spell_eff_bolt — Directional elemental/physical bolt (fixed range 20)
; Input: eff_arg0=dice, eff_arg1=sides, eff_arg2=elem, eff_arg3=bonus, proj_dir
; Output: CF = 1 executed, CF = 0 direction cancelled
; ============================================================================
ovl_spell_eff_bolt:
    PUSH IX
    PUSH IY
    CALL ovl_spell_eff_bolt_core
    POP  IY
    POP  IX
    RET

ovl_spell_eff_bolt_core:
    CALL ovl_spell_eff_ensure_dir
    RET  NC

    LD   A, (eff_arg0)
    LD   B, A
    LD   A, (eff_arg1)
    LD   C, A
    CALL roll_dice_bc           ; HL = rolled damage
    LD   A, (eff_arg3)          ; flat damage bonus (0 or 1)
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    LD   D, 19                  ; 6502 eff_bolt: max 19 steps (proj_steps=20, dec:bne)
    PUSH HL

    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A

.trace:
    CALL ovl_spell_eff_step_bc
    PUSH DE
    CALL map_get_tile
    POP  DE
    JR   C, .miss

    PUSH AF
    CALL tile_is_walkable_a
    JR   NC, .miss_pop
    POP  AF
    BIT  0, A
    JR   NZ, .hit_check
    DEC  D
    JR   NZ, .trace
    JR   .miss

.miss_pop:
    POP  AF
.miss:
    ; 6502 eff_bolt: silent when hitting wall/empty range
    POP  HL
    SCF
    RET

.hit_check:
    CALL monster_find_at
    JR   NC, .miss
    POP  DE
    LD   B, A
    LD   A, (eff_arg2)
    CALL ovl_spell_eff_apply_bolt_dmg
    SCF
    RET

; ============================================================================
; +6: ovl_spell_eff_ball — Directional 3x3 AoE ball spell (range 20, full 3x3 dmg)
; Input: eff_arg0=base_dmg, eff_arg1=elem, ball_harm, proj_dir
; Output: CF = 1 executed, CF = 0 cancelled
; ============================================================================
ovl_spell_eff_ball:
    PUSH IX
    PUSH IY
    CALL ovl_spell_eff_ball_core
    POP  IY
    POP  IX
    RET

ovl_spell_eff_ball_core:
    CALL ovl_spell_eff_ensure_dir
    JR   C, .dir_ok
    XOR  A
    LD   (ball_harm), A
    RET

.dir_ok:
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    LD   D, 19                  ; 6502 eff_ball: max 19 steps (explodes at prev=18 if no hit)

.trace:
    LD   H, B
    LD   L, C
    CALL ovl_spell_eff_step_bc
    PUSH HL
    PUSH DE
    CALL map_get_tile
    POP  DE
    POP  HL
    JR   C, .use_prev
    PUSH AF
    CALL tile_is_walkable_a
    JR   NC, .use_prev_pop
    POP  AF
    BIT  0, A
    JR   NZ, .explode
    DEC  D
    JR   NZ, .trace
    JR   .use_prev

.use_prev_pop:
    POP  AF
.use_prev:
    LD   B, H
    LD   C, L

.explode:
    LD   A, C
    LD   (proj_x), A
    LD   A, B
    LD   (proj_y), A

    LD   E, -1
.dy_lp:
    LD   D, -1
.dx_lp:
    LD   A, (proj_y)
    ADD  A, E
    CP   MAP_ROWS
    JR   NC, .cell_nxt
    LD   B, A
    LD   A, (proj_x)
    ADD  A, D
    CP   MAP_COLS
    JR   NC, .cell_nxt
    LD   C, A

    PUSH DE
    CALL map_get_tile
    JR   C, .no_mon
    BIT  0, A
    JR   Z, .no_mon
    CALL monster_find_at
    JR   NC, .no_mon

    LD   B, A
    LD   A, (eff_arg0)
    LD   E, A
    LD   D, 0
    LD   A, (eff_arg1)
    CALL ovl_spell_eff_apply_ball_dmg

.no_mon:
    POP  DE
.cell_nxt:
    INC  D
    LD   A, D
    CP   2
    JR   NZ, .dx_lp
    INC  E
    LD   A, E
    CP   2
    JR   NZ, .dy_lp

    XOR  A
    LD   (ball_harm), A
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; ============================================================================
; +9: ovl_spell_eff_poly — MON-042 Polymorph (A=0 directional, A=1 mass <=20)
; ============================================================================
ovl_spell_eff_poly:
    PUSH IX
    PUSH IY
    CALL ovl_spell_eff_poly_core
    POP  IY
    POP  IX
    RET

ovl_spell_eff_poly_dir_core:
    XOR  A
ovl_spell_eff_poly_core:
    OR   A
    JR   NZ, .mass_poly

    CALL ovl_spell_eff_ensure_dir
    RET  NC
    CALL ovl_spell_eff_trace_mon
    JR   NC, .p_done
    CALL ovl_spell_eff_try_poly_slot
.p_done:
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

.mass_poly:
    LD   C, 0
.snap:
    LD   A, C
    CALL monster_get_ptr
    LD   A, 0
    JR   C, .sn_st
    INC  HL
    INC  HL
    LD   A, (HL)
    CP   EMPTY_SLOT
    LD   A, 0
    JR   Z, .sn_st
    LD   A, 1
.sn_st:
    LD   E, C
    LD   D, 0
    LD   HL, bss_scratch
    ADD  HL, DE
    LD   (HL), A
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .snap

    LD   C, 0
.m_lp:
    LD   E, C
    LD   D, 0
    LD   HL, bss_scratch
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    JR   Z, .m_nxt

    LD   A, C
    CALL ovl_spell_eff_get_live_mon
    JR   C, .m_nxt
    CALL ovl_spell_eff_dist_to_player
    CP   MONS_MAX_SIGHT
    JR   NC, .m_nxt

    PUSH HL
    INC  HL
    INC  HL
    LD   E, (HL)
    LD   D, 0
    LD   HL, cr_level
    ADD  HL, DE
    LD   A, (HL)
    POP  HL
    CP   MONS_LEVEL_MAX + 1
    JR   NC, .m_nxt

    LD   A, C
    PUSH BC
    CALL ovl_spell_eff_do_poly_slot
    POP  BC
.m_nxt:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .m_lp

    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; ============================================================================
; +12: ovl_spell_eff_area — Shared area/utility sub-effects (A = sub_op 0..25)
; ============================================================================
ovl_spell_eff_area:
    PUSH IX
    PUSH IY
    CP   26
    JR   NC, .bad_op
    LD   HL, ovl_spell_eff_area_tbl
    CALL ovl_spell_eff_tbl_dispatch
    POP  IY
    POP  IX
    RET
.bad_op:
    OR   A
    POP  IY
    POP  IX
    RET

; ============================================================================
; Sub-Op Dispatch Tables
; ============================================================================
ovl_spell_eff_area_tbl:
    DW ovl_spell_eff_sub_map         ; 0  magic_mapping
    DW ovl_spell_eff_sub_dispel_evil ; 1  dispel_evil (eff_arg0=dmg, MF_VISIBLE)
    DW ovl_spell_eff_sub_dispel_und  ; 2  dispel_undead (eff_arg0=dmg, MF_VISIBLE)
    DW ovl_spell_eff_sub_turn_und    ; 3  turn_undead
    DW ovl_spell_eff_sub_sleep_dir   ; 4  sleep_dir
    DW ovl_spell_eff_sub_sleep_adj   ; 5  sleep_adj
    DW ovl_spell_eff_sub_sleep_all   ; 6  sleep_all
    DW ovl_spell_eff_sub_confuse_dir ; 7  confuse_dir
    DW ovl_spell_eff_sub_slow_dir    ; 8  slow_dir
    DW ovl_spell_eff_sub_confuse_dir ; 9  blind_dir
    DW ovl_spell_eff_sub_tele_other  ; 10 teleport_other
    DW ovl_spell_eff_sub_dest_traps  ; 11 destroy_traps_doors
    DW ovl_spell_eff_sub_dest_area   ; 12 destroy_area
    DW ovl_spell_eff_sub_earthquake  ; 13 earthquake
    DW ovl_spell_eff_sub_genocide    ; 14 genocide
    DW ovl_spell_eff_sub_mass_geno   ; 15 mass_genocide
    DW ovl_spell_eff_sub_det_evil    ; 16 detect_evil_panel
    DW ovl_spell_eff_sub_det_mons    ; 17 detect_monsters
    DW ovl_spell_eff_sub_det_treas   ; 18 detect_treasures
    DW ovl_spell_eff_sub_det_objs    ; 19 detect_objects
    DW ovl_spell_eff_sub_det_traps   ; 20 detect_traps
    DW ovl_spell_eff_sub_det_doors   ; 21 detect_doors_stairs
    DW ovl_spell_eff_sub_light_room  ; 22 light_room (2d8 vs CD_LIGHT)
    DW ovl_spell_eff_sub_wall_mud    ; 23 wall_to_mud (100 vs CD_STONE)
    DW ovl_spell_eff_sub_glyph       ; 24 glyph_of_warding
    DW ovl_spell_eff_sub_holy_word   ; 25 holy_word

ovl_spell_eff_mage_tbl:
    DW ovl_spell_eff_m0, ovl_spell_eff_sub_det_mons, ovl_spell_eff_m2, ovl_spell_eff_sub_light_room
    DW ovl_spell_eff_m4, ovl_spell_eff_m5, ovl_spell_eff_m6, ovl_spell_eff_sub_confuse_dir
    DW ovl_spell_eff_m8, ovl_spell_eff_sub_dest_traps, ovl_spell_eff_sub_sleep_dir, ovl_spell_eff_cure_poison
    DW ovl_spell_eff_m12, ovl_spell_eff_m13, ovl_spell_eff_m14, ovl_spell_eff_sub_wall_mud
    DW ovl_spell_eff_create_food, ovl_spell_eff_m17, ovl_spell_eff_sub_sleep_adj, ovl_spell_eff_poly_dir_core
    DW tramp_items_eff_identify, ovl_spell_eff_sub_sleep_all, ovl_spell_eff_m22, ovl_spell_eff_sub_slow_dir
    DW ovl_spell_eff_m24, ovl_spell_eff_m25, ovl_spell_eff_sub_tele_other, ovl_spell_eff_m27
    DW ovl_spell_eff_m28, ovl_spell_eff_sub_dest_area, ovl_spell_eff_sub_genocide

ovl_spell_eff_priest_tbl:
    DW ovl_spell_eff_sub_det_evil, ovl_spell_eff_p1, ovl_spell_eff_p2, ovl_spell_eff_remove_fear
    DW ovl_spell_eff_sub_light_room, ovl_spell_eff_sub_det_traps, ovl_spell_eff_sub_det_doors, ovl_spell_eff_p7
    DW ovl_spell_eff_sub_confuse_dir, ovl_spell_eff_p9, ovl_spell_eff_m4, ovl_spell_eff_p11
    DW ovl_spell_eff_sub_sleep_adj, ovl_spell_eff_create_food, ovl_spell_eff_p14, ovl_spell_eff_p15
    DW ovl_spell_eff_cure_poison, ovl_spell_eff_p17, ovl_spell_eff_p18, ovl_spell_eff_p19
    DW ovl_spell_eff_p20, ovl_spell_eff_sub_earthquake, ovl_spell_eff_sub_map, ovl_spell_eff_p23
    DW ovl_spell_eff_sub_turn_und, ovl_spell_eff_p25, ovl_spell_eff_p26, ovl_spell_eff_p27
    DW ovl_spell_eff_p28, ovl_spell_eff_sub_glyph, ovl_spell_eff_sub_holy_word

; --- Mage Spell Handlers ---
ovl_spell_eff_m0:  LD BC, (2 << 8) | 6  : LD D, ELEM_NONE      : JR ovl_spell_eff_cast_bolt
ovl_spell_eff_m8:  LD BC, (3 << 8) | 8  : LD D, ELEM_LIGHTNING : JR ovl_spell_eff_cast_bolt
ovl_spell_eff_m14: LD BC, (4 << 8) | 8  : LD D, ELEM_FROST     : JR ovl_spell_eff_cast_bolt
ovl_spell_eff_m22: LD BC, (6 << 8) | 8  : LD D, ELEM_FIRE
ovl_spell_eff_cast_bolt:
    LD   A, B
    LD   (eff_arg0), A
    LD   A, C
    LD   (eff_arg1), A
    LD   A, D
    LD   (eff_arg2), A
    LD   A, 1
    LD   (eff_arg3), A          ; +1 bonus on mage bolts (6502 med_s0/8/14/22)
    JP   ovl_spell_eff_bolt_core

ovl_spell_eff_m6:  LD D, 9  : LD E, ELEM_POISON : JR ovl_spell_eff_cast_ball
ovl_spell_eff_m24: LD D, 33 : LD E, ELEM_FROST  : JR ovl_spell_eff_cast_ball
ovl_spell_eff_m28: LD D, 49 : LD E, ELEM_FIRE
ovl_spell_eff_cast_ball:
    XOR  A
    LD   (ball_harm), A
    LD   A, D
    LD   (eff_arg0), A
    LD   A, E
    LD   (eff_arg1), A
    JP   ovl_spell_eff_ball_core

ovl_spell_eff_m2:  LD A, 10 : JP tramp_items_eff_teleport
ovl_spell_eff_m4:  LD B, 4 : LD C, 4 : JP ovl_spell_eff_heal_dice
ovl_spell_eff_m5:
    CALL ovl_spell_eff_find_secret_doors
    JP   ovl_spell_eff_sub_det_traps
ovl_spell_eff_m12: XOR A : JP tramp_items_eff_teleport
ovl_spell_eff_m13: XOR A : JP ovl_spell_eff_remove_curse
ovl_spell_eff_m17: LD A, 20 : JP ovl_spell_eff_recharge
ovl_spell_eff_m25: LD A, 50 : JP ovl_spell_eff_recharge
ovl_spell_eff_m27:
    LD   A, 20
    CALL rng_range
    INC  A
    LD   HL, abi_player_lvl
    ADD  A, (HL)                ; A = rng(20) + 1 + pl_lvl (capped <= 127)
    JP   P, .h_add
    LD   A, 127
.h_add:
    LD   HL, zp_eff_speed
    ADD  A, (HL)                ; signed add: cancels negative slow, saturates at +127 on overflow (6502 bvc)
    JP   PO, .h_st
    LD   A, 127
.h_st:
    LD   (HL), A
    LD   A, HSTR_PIQ_SPEED
    CALL msg_print_huff
    SCF
    RET

; --- Priest Prayer Handlers ---
ovl_spell_eff_p1:  LD B, 3 : LD C, 3 : JP ovl_spell_eff_heal_dice
ovl_spell_eff_p2:  LD A, 12 : CALL rng_range : ADD A, 12 : JP ovl_spell_eff_add_bless
ovl_spell_eff_p7:
    LD   HL, zp_eff_poison
    LD   A, (HL)
    OR   A
    JR   Z, .p7_ok
    SRL  A
    OR   1
    LD   (HL), A
    LD   A, HSTR_EFF_POISON_END
    CALL msg_print_huff
.p7_ok:
    SCF
    RET
ovl_spell_eff_p9:
    XOR  A                      ; 6502 P9 Portal = eff_teleport_self (unlimited & silent)
    JP   tramp_items_eff_teleport
ovl_spell_eff_p11: LD A, 24 : CALL rng_range : ADD A, 24 : JP ovl_spell_eff_add_bless
ovl_spell_eff_p14: LD A, 1 : JP ovl_spell_eff_remove_curse
ovl_spell_eff_p15:
    LD   A, 10
    CALL rng_range
    ADD  A, 11
    LD   HL, zp_eff_resist
    CALL ovl_spell_eff_add_sat
    LD   A, 10
    CALL rng_range
    ADD  A, 11
    LD   HL, eff_resist_cold_timer
    CALL ovl_spell_eff_add_sat
    LD   HL, ovl_spell_eff_s_resist
    CALL msg_print_str
    SCF
    RET
ovl_spell_eff_p17:
    LD   B, 3
    LD   C, 6
    CALL roll_dice_bc
    LD   A, (abi_player_lvl)
    ADD  A, L
    JR   NC, .orb_c
    LD   A, 255
.orb_c:
    LD   (eff_arg0), A
    LD   A, ELEM_HOLY
    LD   (eff_arg1), A
    LD   A, CF_EVIL
    LD   (ball_harm), A
    JP   ovl_spell_eff_ball_core
ovl_spell_eff_p18: LD B, 8  : LD C, 4 : JR ovl_spell_eff_heal_dice
ovl_spell_eff_p23: LD B, 16 : LD C, 4
ovl_spell_eff_heal_dice:
    CALL roll_dice_bc
    JR   ovl_spell_eff_heal_report
ovl_spell_eff_p27:
    LD   HL, 200
ovl_spell_eff_heal_report:
    ; 6502 pmx_heal_and_report: silent if PL_HP >= PL_MHP; else heal + tiered msg
    PUSH HL                     ; save heal amount
    LD   DE, (player_data + PL_HP_LO)
    LD   HL, (player_data + PL_MHP_LO)
    OR   A
    SBC  HL, DE                 ; MHP - HP
    POP  HL
    JR   C, .h_full
    JR   Z, .h_full
    PUSH HL
    CALL eff_heal
    CALL player_sync_to_abi
    CALL status_mark_dirty
    POP  HL                     ; HL = heal amount
    LD   A, H
    OR   A
    LD   A, HSTR_PIQ_VERY_GOOD
    JR   NZ, .h_msg
    LD   A, L
    CP   5
    LD   A, HSTR_PIQ_LITTLE_BETTER
    JR   C, .h_msg
    LD   A, L
    CP   15
    LD   A, HSTR_EFF_POISON_END
    JR   C, .h_msg
    LD   A, L
    CP   35
    LD   A, HSTR_PIQ_MUCH_BETTER
    JR   C, .h_msg
    LD   A, HSTR_PIQ_VERY_GOOD
.h_msg:
    CALL msg_print_huff
.h_full:
    SCF
    RET

ovl_spell_eff_p19:
    LD   A, 24
    CALL rng_range
    ADD  A, 25
    LD   HL, zp_eff_see_inv
    LD   C, (HL)                ; old see_inv
    CALL ovl_spell_eff_add_sat
    LD   A, (zp_eff_invis)
    OR   C
    JR   NZ, .p19_done          ; onset-only message (6502 pmx_set_see_invisible_msg)
    LD   A, HSTR_PIQ_EYES_TINGLE
    CALL msg_print_huff
.p19_done:
    SCF
    RET
ovl_spell_eff_p20:
    LD   A, 25
    CALL rng_range
    INC  A
    LD   B, A
    CALL ovl_spell_eff_3x_lvl
    ADD  A, B
    JR   NC, .pe_ok
    LD   A, 255
.pe_ok:
    LD   HL, zp_eff_protect
    LD   C, (HL)                ; old protect
    CALL ovl_spell_eff_add_sat
    LD   A, C
    OR   A
    JR   NZ, .p20_done          ; onset-only message (6502 pmx_add_protect_msg)
    LD   A, HSTR_PIQ_PROTECTED
    CALL msg_print_huff
.p20_done:
    SCF
    RET
ovl_spell_eff_p25: LD A, 48 : CALL rng_range : ADD A, 48 : JP ovl_spell_eff_add_bless
ovl_spell_eff_p26:
    CALL ovl_spell_eff_3x_lvl
    LD   (eff_arg0), A
    CALL ovl_spell_eff_sub_dispel_und
    JR   ovl_spell_eff_dispel_chk_none
ovl_spell_eff_p28:
    CALL ovl_spell_eff_3x_lvl
    LD   (eff_arg0), A
    CALL ovl_spell_eff_sub_dispel_evil
ovl_spell_eff_dispel_chk_none:
    LD   A, (bss_scratch + 7)
    OR   A
    JR   NZ, .dc_done
    LD   A, HSTR_PIQ_NOTHING
    CALL msg_print_huff
.dc_done:
    SCF
    RET

; ============================================================================
; Area Sub-Op Implementations (0..25)
; ============================================================================

; 0: Sense Surroundings / Magic Mapping (6502 player_magic_map.s: random margins, silent)
ovl_spell_eff_sub_map:
    ; bss_scratch + 0 = x0, +1 = x1, +2 = y0, +3 = y1, +4 = max_c, +5 = max_r
    LD   A, (abi_player_dlvl)
    OR   A
    LD   D, TOWN_MAP_COLS
    LD   E, TOWN_MAP_ROWS
    JR   Z, .dims_ok
    LD   D, MAP_COLS
    LD   E, MAP_ROWS
.dims_ok:
    LD   A, D
    DEC  A
    LD   (bss_scratch + 4), A   ; max_col
    LD   A, E
    DEC  A
    LD   (bss_scratch + 5), A   ; max_row

    LD   A, 20
    CALL rng_range
    LD   B, A
    LD   A, (abi_view_x)
    SUB  B
    JR   NC, .x0_ok
    XOR  A
.x0_ok:
    LD   (bss_scratch + 0), A

    LD   A, 20
    CALL rng_range
    LD   B, A
    LD   A, (abi_view_x)
    ADD  A, VIEW_COLS - 1
    JR   C, .x1_clamp
    ADD  A, B
    JR   C, .x1_clamp
    LD   HL, bss_scratch + 4
    CP   (HL)
    JR   C, .x1_ok
.x1_clamp:
    LD   A, (bss_scratch + 4)
.x1_ok:
    LD   (bss_scratch + 1), A

    LD   A, 10
    CALL rng_range
    LD   B, A
    LD   A, (abi_view_y)
    SUB  B
    JR   NC, .y0_ok
    XOR  A
.y0_ok:
    LD   (bss_scratch + 2), A

    LD   A, 10
    CALL rng_range
    LD   B, A
    LD   A, (abi_view_y)
    ADD  A, VIEW_ROWS - 1
    JR   C, .y1_clamp
    ADD  A, B
    JR   C, .y1_clamp
    LD   HL, bss_scratch + 5
    CP   (HL)
    JR   C, .y1_ok
.y1_clamp:
    LD   A, (bss_scratch + 5)
.y1_ok:
    LD   (bss_scratch + 3), A

    LD   A, (bss_scratch + 2)
    LD   B, A                   ; B = y
.ylp:
    LD   A, (bss_scratch + 0)
    LD   C, A                   ; C = x
.xlp:
    CALL map_get_tile
    JR   C, .nxt
    LD   E, A
    AND  TILE_TYPE_MASK
    OR   A                      ; only TILE_FLOOR triggers 3x3 reveal
    JR   NZ, .nxt
    LD   A, E
    OR   FLAG_VISITED
    CALL map_set_tile

    ; Reveal 8 adjacent non-floor, non-secret walls/doors/features
    LD   D, 7
.adj_lp:
    PUSH BC
    PUSH DE
    LD   E, D
    LD   D, 0
    LD   HL, dir_dx
    ADD  HL, DE
    LD   A, C
    ADD  A, (HL)
    LD   C, A
    LD   HL, dir_dy
    ADD  HL, DE
    LD   A, B
    ADD  A, (HL)
    LD   B, A
    CALL map_get_tile
    JR   C, .adj_pop
    LD   E, A
    AND  TILE_TYPE_MASK
    OR   A                      ; skip floor
    JR   Z, .adj_pop
    CP   TILE_SECRET            ; skip secret door
    JR   Z, .adj_pop
    LD   A, E
    OR   FLAG_VISITED
    CALL map_set_tile
.adj_pop:
    POP  DE
    POP  BC
    DEC  D
    JP   P, .adj_lp

.nxt:
    LD   HL, bss_scratch + 1
    LD   A, C
    CP   (HL)
    JR   Z, .xdone
    INC  C
    JR   .xlp
.xdone:
    LD   HL, bss_scratch + 3
    LD   A, B
    CP   (HL)
    JR   Z, .done
    INC  B
    JR   .ylp
.done:
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; 1 / 2: Dispel Evil (CF_EVIL) / Dispel Undead (CF_UNDEAD), MF_VISIBLE only (MON-001)
ovl_spell_eff_sub_dispel_evil:
    LD   A, CF_EVIL
    JR   ovl_spell_eff_dispel_flagged
ovl_spell_eff_sub_dispel_und:
    LD   A, CF_UNDEAD

ovl_spell_eff_dispel_flagged:
    ; Returns bss_scratch + 7 = targets hit count (for P26/P28 HSTR_PIQ_NOTHING)
    LD   (eff_arg1), A
    XOR  A
    LD   (bss_scratch + 7), A
    LD   A, (eff_arg0)
    OR   A
    JR   NZ, .nz
    SCF
    RET
.nz:
    LD   C, 0                   ; C = slot 0..31
.lp:
    LD   A, C
    CALL monster_get_ptr
    JR   C, .nxt
    PUSH HL
    INC  HL
    INC  HL
    LD   B, (HL)                ; B = MX_TYPE
    LD   A, B
    CP   EMPTY_SLOT
    JR   Z, .pop_nxt
    INC  HL
    INC  HL
    INC  HL                     ; MX_FLAGS
    LD   A, (HL)
    AND  MF_VISIBLE
    JR   Z, .pop_nxt            ; MON-001: MF_VISIBLE only!

    LD   E, B
    LD   D, 0
    LD   HL, cr_mflags
    ADD  HL, DE
    LD   A, (eff_arg1)
    AND  (HL)
    JR   Z, .pop_nxt

    LD   HL, bss_scratch + 7
    INC  (HL)
    LD   A, (eff_arg0)
    CALL rng_range
    INC  A                      ; A = 1..dmg
    LD   E, A
    LD   D, 0
    POP  HL                     ; mon_ptr
    PUSH BC
    CALL ovl_spell_eff_sub_mon_hp_no_wake ; CF=1 killed, CF=0 survived
    POP  BC                     ; B = cr_type, C = slot
    LD   A, B                   ; A = cr_type
    JR   C, .killed
    PUSH BC
    LD   DE, ovl_spell_eff_s_shud
    CALL ovl_spell_eff_print_mon_msg
    POP  BC
    JR   .nxt
.killed:
    PUSH BC
    LD   A, B
    LD   DE, ovl_spell_eff_s_diss
    CALL ovl_spell_eff_print_mon_msg
    POP  BC
    PUSH BC
    LD   A, C
    CALL tramp_modal_kill_monster
    POP  BC
    JR   .nxt

.pop_nxt:
    POP  HL
.nxt:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .lp

    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; 3: Turn Undead (clvl+1 > cr_level else 1/5, clears sleep without monster_wake)
ovl_spell_eff_sub_turn_und:
    CALL ovl_spell_eff_sub_turn_und_core
    OR   A
    JR   NZ, .tu_done
    LD   A, HSTR_PIQ_NOTHING
    CALL msg_print_huff
.tu_done:
    SCF
    RET

ovl_spell_eff_sub_turn_und_core:
    XOR  A
    LD   (bss_scratch + 7), A
    LD   C, 0
.lp:
    LD   A, C
    CALL monster_get_ptr
    JR   C, .nxt
    PUSH HL
    INC  HL
    INC  HL
    LD   B, (HL)                ; B = cr_type
    LD   A, B
    CP   EMPTY_SLOT
    JR   Z, .pop_nxt
    INC  HL
    INC  HL
    INC  HL
    BIT  3, (HL)                ; MF_VISIBLE?
    JR   Z, .pop_nxt

    LD   E, B
    LD   D, 0
    LD   HL, cr_mflags
    ADD  HL, DE
    BIT  1, (HL)                ; CF_UNDEAD
    JR   Z, .pop_nxt

    LD   HL, bss_scratch + 7
    INC  (HL)
    ; 6502 eff_turn_undead_core: player_lvl >= cr_level else 1/5
    LD   HL, cr_level
    ADD  HL, DE
    LD   A, (abi_player_lvl)
    CP   (HL)
    JR   NC, .turn_it
    LD   A, 5
    CALL rng_range
    OR   A
    JR   Z, .turn_it

    POP  HL
    PUSH BC
    LD   A, B
    CALL ovl_spell_eff_print_unaffected
    POP  BC
    JR   .nxt

.turn_it:
    POP  HL
    PUSH BC
    PUSH HL
    LD   DE, MX_SLEEP_CUR
    ADD  HL, DE
    LD   (HL), 0                ; clear sleep without wake/disturb
    POP  HL
    LD   DE, MX_CONFUSE
    ADD  HL, DE
    LD   A, (abi_player_lvl)
    LD   (HL), A
    LD   A, B
    LD   DE, ovl_spell_eff_s_runs
    CALL ovl_spell_eff_print_mon_msg
    POP  BC
    JR   .nxt

.pop_nxt:
    POP  HL
.nxt:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .lp
    LD   A, (bss_scratch + 7)
    SCF
    RET

; 4/5/6: Sleep I (dir, silent) / Sleep II (adj, summary) / Sleep III (all MF_VISIBLE, summary)
ovl_spell_eff_sub_sleep_dir:
    CALL ovl_spell_eff_ensure_dir
    RET  NC
    CALL ovl_spell_eff_trace_mon
    JR   NC, .done
    CALL ovl_spell_eff_try_sleep
.done:
    SCF
    RET

ovl_spell_eff_sub_sleep_adj:
    XOR  A
    LD   (bss_scratch + 0), A   ; seen
    LD   (bss_scratch + 1), A   ; hits
    LD   C, 0
.lp:
    LD   A, C
    CALL ovl_spell_eff_get_live_mon
    JR   C, .nxt
    CALL ovl_spell_eff_dist_to_player
    CP   2
    JR   NC, .nxt
    LD   HL, bss_scratch + 0
    INC  (HL)
    LD   A, C
    PUSH BC
    CALL ovl_spell_eff_try_sleep
    POP  BC
    JR   NC, .nxt
    LD   HL, bss_scratch + 1
    INC  (HL)
.nxt:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .lp
    LD   A, (bss_scratch + 1)
    OR   A
    LD   HL, ovl_spell_eff_s_slp_ok
    JR   NZ, .msg
    LD   A, (bss_scratch + 0)
    OR   A
    LD   HL, ovl_spell_eff_s_slp_no
    JR   NZ, .msg
    LD   A, HSTR_PIQ_NOTHING
    CALL msg_print_huff
    SCF
    RET
.msg:
    CALL msg_print_str
    SCF
    RET

ovl_spell_eff_sub_sleep_all:
    XOR  A
    LD   (bss_scratch + 1), A   ; hits
    LD   C, 0
.lp:
    LD   A, C
    CALL ovl_spell_eff_get_live_mon
    JR   C, .nxt
    LD   DE, MX_FLAGS
    ADD  HL, DE
    BIT  3, (HL)                ; MF_VISIBLE
    JR   Z, .nxt
    LD   A, C
    PUSH BC
    CALL ovl_spell_eff_try_sleep
    POP  BC
    JR   NC, .nxt
    LD   HL, bss_scratch + 1
    INC  (HL)
.nxt:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .lp
    LD   A, (bss_scratch + 1)
    OR   A
    JR   NZ, .hit
    LD   A, HSTR_PIQ_NOTHING
    CALL msg_print_huff
    SCF
    RET
.hit:
    LD   HL, ovl_spell_eff_s_slp_ok
    CALL msg_print_str
    SCF
    RET

; 7/9: Confuse / Blind Creature directional (range 20, CD_NO_SLEEP only, no wake/MF_CONFUSED)
ovl_spell_eff_sub_confuse_dir:
    CALL ovl_spell_eff_ensure_dir
    JR   NC, .imm
    CALL ovl_spell_eff_trace_mon ; CF=1, A=slot, HL=ptr
    JR   NC, .imm
    CALL ovl_spell_eff_get_cr_cdef ; B=cr_type, D=cdefense
    BIT  6, D                   ; CD_NO_SLEEP?
    JR   NZ, .imm
    LD   DE, MX_CONFUSE
    ADD  HL, DE
    LD   (HL), 10
    LD   A, HSTR_PIW_WAND_CLOUD
    CALL msg_print_huff
    SCF
    RET
.imm:
    LD   A, HSTR_PIQ_NOTHING
    CALL msg_print_huff
    SCF
    RET

; 8: Slow Monster directional (range 20, clears MX_SLEEP_CUR=0 without wake, "It slows.")
ovl_spell_eff_sub_slow_dir:
    CALL ovl_spell_eff_ensure_dir
    RET  NC
    CALL ovl_spell_eff_trace_mon
    JR   NC, .done
    PUSH HL
    LD   DE, MX_SLEEP_CUR
    ADD  HL, DE
    LD   (HL), 0
    POP  HL
    LD   DE, MX_SPEED_CNT
    ADD  HL, DE
    LD   (HL), 0xFF             ; -1 slow speed
    LD   HL, ovl_spell_eff_s_slow
    CALL msg_print_str
.done:
    SCF
    RET

; 10: Teleport Other directional (range 20, clears MX_SLEEP_CUR=0 without wake, silent)
ovl_spell_eff_sub_tele_other:
    CALL ovl_spell_eff_ensure_dir
    RET  NC
    CALL ovl_spell_eff_trace_mon ; A=slot, HL=ptr
    JR   NC, .done
    PUSH HL
    XOR  A                      ; range = 0 (anywhere on floor)
    CALL find_random_floor      ; CF=1, B=new_y, C=new_x
    JR   NC, .fail_pop
    CALL map_get_tile
    JR   C, .fail_pop
    BIT  0, A
    JR   NZ, .fail_pop
    OR   FLAG_OCCUPIED
    CALL map_set_tile           ; mark new tile occupied
    LD   D, B
    LD   E, C                   ; DE = new_y, new_x
    POP  HL                     ; HL = mon_ptr
    ; Clear old FLAG_OCCUPIED
    PUSH DE
    LD   C, (HL)                ; old_x
    INC  HL
    LD   B, (HL)                ; old_y
    CALL map_get_tile
    RES  0, A
    CALL map_set_tile
    POP  DE
    DEC  HL
    LD   (HL), E                ; MX_X
    INC  HL
    LD   (HL), D                ; MX_Y
    LD   DE, MX_SLEEP_CUR - MX_Y
    ADD  HL, DE
    LD   (HL), 0                ; clear sleep without monster_wake
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET
.fail_pop:
    POP  HL
.done:
    SCF
    RET

; 11: Destroy Traps & Doors (8 adjacent tiles only, clears door_state, silent)
ovl_spell_eff_sub_dest_traps:
    LD   E, 7
.dir_lp:
    LD   D, 0
    LD   HL, dir_dy
    ADD  HL, DE
    LD   A, (abi_player_y)
    ADD  A, (HL)
    LD   B, A
    LD   HL, dir_dx
    ADD  HL, DE
    LD   A, (abi_player_x)
    ADD  A, (HL)
    LD   C, A
    PUSH DE
    CALL map_get_tile
    JR   C, .dir_nxt
    LD   H, A
    AND  TILE_TYPE_MASK
    CP   TILE_TRAP
    JR   NZ, .chk_door
    LD   A, H
    AND  TILE_FLAG_MASK             ; TILE_FLOOR (0) keeping flags
    CALL map_set_tile
    CALL ovl_spell_eff_remove_trap_at
    JR   .dir_nxt
.chk_door:
    CP   TILE_DOOR_CLOSED
    JR   Z, .open_d
    CP   TILE_SECRET
    JR   NZ, .dir_nxt
.open_d:
    LD   A, H
    AND  TILE_FLAG_MASK
    OR   TILE_DOOR_OPEN | FLAG_VISITED
    CALL map_set_tile
    CALL ovl_spell_eff_clear_door_state_at
.dir_nxt:
    POP  DE
    DEC  E
    JP   P, .dir_lp

    ; Second pass: remove any adjacent trap entries (incl. hidden traps)
    LD   E, 0
.tr_lp:
    LD   A, (trap_count)
    CP   E
    JR   C, .tr_done
    JR   Z, .tr_done
    LD   D, 0
    LD   HL, trap_y
    ADD  HL, DE
    LD   B, (HL)
    LD   HL, trap_x
    ADD  HL, DE
    LD   C, (HL)
    PUSH DE
    LD   D, B
    LD   E, C
    CALL ovl_spell_eff_dist_de_player
    POP  DE
    OR   A
    JR   Z, .tr_nxt             ; keep any trap on player's own tile (6502 eff_doors_traps_cold.s)
    CP   2
    JR   NC, .tr_nxt
    PUSH DE
    CALL ovl_spell_eff_remove_trap_at ; (B=y, C=x) swap-removes E, decrements trap_count
    POP  DE
    JR   .tr_lp
.tr_nxt:
    INC  E
    JR   .tr_lp
.tr_done:
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; 12: Word of Destruction (cold-spilled to OVL_ITEMS via tramp_items_world_cold)
ovl_spell_eff_sub_dest_area:
    XOR  A
    JP   tramp_items_world_cold

; 13: Earthquake (cold-spilled to OVL_ITEMS via tramp_items_world_cold)
ovl_spell_eff_sub_earthquake:
    LD   A, 1
    JP   tramp_items_world_cold

; 14: Genocide (prompt HSTR_PM_TITLE_PRAY "Type?", allow A-Z / a-z only, 0 strain HP, silent)
ovl_spell_eff_sub_genocide:
    LD   A, HSTR_PM_TITLE_PRAY
    CALL msg_print_huff
    CALL input_get_key
    CP   'A'
    JR   C, .done
    CP   'Z' + 1
    JR   C, .sym_ok
    CP   'a'
    JR   C, .done
    CP   'z' + 1
    JR   NC, .done
.sym_ok:

    LD   B, A                   ; target display char
    LD   C, 0
.lp:
    LD   A, C
    CALL monster_get_ptr
    JR   C, .nxt
    PUSH HL
    INC  HL
    INC  HL
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .pop_nxt
    LD   E, A
    CALL monster_is_balrog_slot
    JR   Z, .pop_nxt
    LD   D, 0
    LD   HL, cr_display
    ADD  HL, DE
    LD   A, (HL)
    CP   B
    POP  HL
    JR   NZ, .nxt
    LD   A, C
    PUSH BC
    CALL monster_remove
    POP  BC
    JR   .nxt
.pop_nxt:
    POP  HL
.nxt:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .lp
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
.done:
    SCF
    RET

; 15: Mass Genocide (remove non-Balrog within LOS, 0 strain HP, HSTR bright flash msg)
ovl_spell_eff_sub_mass_geno:
    LD   C, 0
.lp:
    LD   A, C
    CALL monster_get_ptr
    JR   C, .nxt
    PUSH HL
    INC  HL
    INC  HL
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .pop_nxt
    CALL monster_is_balrog_slot
    JR   Z, .pop_nxt
    POP  HL
    LD   E, (HL)                ; mx
    INC  HL
    LD   D, (HL)                ; my
    PUSH BC
    PUSH DE
    CALL ovl_spell_eff_dist_de_player
    POP  DE
    POP  BC
    CP   21
    JR   NC, .nxt
    PUSH BC
    LD   BC, (abi_player_x)     ; B=py, C=px
    CALL los_check
    POP  BC
    JR   NC, .nxt
    LD   A, C
    PUSH BC
    CALL monster_remove
    POP  BC
    JR   .nxt
.pop_nxt:
    POP  HL
.nxt:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .lp
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   HL, ovl_spell_eff_s_blow
    CALL msg_print_str
    SCF
    RET

; 16: Detect Evil (immediate current-panel reveal -> eff_detect_evil_mode=1)
ovl_spell_eff_sub_det_evil:
    LD   C, 0
    LD   D, 0
.lp:
    LD   A, C
    CALL monster_get_ptr
    JR   C, .nxt
    LD   B, (HL)                ; x
    INC  HL
    LD   E, (HL)                ; y
    INC  HL
    LD   A, (HL)                ; cr_type
    CP   EMPTY_SLOT
    JR   Z, .nxt

    PUSH HL
    PUSH DE
    LD   E, A
    LD   D, 0
    LD   HL, cr_mflags
    ADD  HL, DE
    BIT  2, (HL)                ; CF_EVIL
    POP  DE
    POP  HL
    JR   Z, .nxt

    PUSH HL
    LD   HL, abi_view_x
    LD   A, B
    SUB  (HL)
    CP   VIEW_COLS
    JR   NC, .oob
    LD   HL, abi_view_y
    LD   A, E
    SUB  (HL)
    CP   VIEW_ROWS
.oob:
    POP  HL
    JR   NC, .nxt

    INC  HL
    INC  HL
    INC  HL
    SET  4, (HL)                ; MF_DETECTED
    LD   D, 1
.nxt:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .lp

    LD   A, D
    OR   A
    JR   Z, .none
    LD   (eff_detect_evil_mode), A
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   HL, ovl_spell_eff_s_det_evil
    CALL msg_print_str
    SCF
    RET
.none:
    LD   HL, ovl_spell_eff_s_no_evil
    CALL msg_print_str
    SCF
    RET

; 17: Detect Monsters (eff_detect_timer = 20, clear eff_detect_evil_mode, scan active incl. CD_INVISIBLE, HSTR_PIQ_SENSE / none)
ovl_spell_eff_sub_det_mons:
    XOR  A
    LD   (eff_detect_evil_mode), A
    LD   A, 20
    LD   (eff_detect_timer), A
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   C, 0
.lp:
    LD   A, C
    CALL monster_get_ptr
    JR   C, .nxt
    INC  HL
    INC  HL
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   NZ, .found
.nxt:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .lp
    LD   HL, ovl_spell_eff_s_no_mon
    CALL msg_print_str
    SCF
    RET
.found:
    LD   A, HSTR_PIQ_SENSE
    CALL msg_print_huff
    SCF
    RET

; 18: Detect Treasures & 19: Detect Objects
ovl_spell_eff_sub_det_treas:
    LD   A, 1
    JR   ovl_spell_eff_det_items
ovl_spell_eff_sub_det_objs:
    XOR  A

ovl_spell_eff_det_items:
    LD   (bss_scratch + 0), A   ; 1 = gold only, 0 = all items
    LD   C, 0
.lp:
    LD   B, 0
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .nxt

    LD   A, (bss_scratch + 0)
    OR   A
    JR   Z, .mark
    LD   HL, fi_meta_hi
    ADD  HL, BC
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    PUSH BC
    CALL item_get_category_a
    POP  BC
    CP   ICAT_GOLD
    JR   NZ, .nxt
.mark:
    PUSH BC
    LD   B, 0
    LD   HL, fi_x
    ADD  HL, BC
    LD   E, (HL)
    LD   HL, fi_y
    ADD  HL, BC
    LD   B, (HL)
    LD   C, E
    CALL map_get_tile
    JR   C, .pop_nxt
    OR   FLAG_VISITED | FLAG_LIT
    CALL map_set_tile
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
.pop_nxt:
    POP  BC
.nxt:
    INC  C
    LD   A, C
    CP   MAX_FLOOR_ITEMS
    JR   C, .lp

    LD   HL, ovl_spell_eff_s_det_tr
    LD   A, (bss_scratch + 0)
    OR   A
    JR   NZ, .msg_tr
    LD   HL, ovl_spell_eff_s_det_ob
.msg_tr:
    CALL msg_print_str
    SCF
    RET

; 20: Detect Traps (silent, armed chests only!)
ovl_spell_eff_sub_det_traps:
    LD   A, (trap_count)
    OR   A
    JR   Z, .chk_chests
    LD   C, 0
.tlp:
    PUSH BC
    LD   B, 0
    LD   HL, trap_x
    ADD  HL, BC
    LD   E, (HL)
    LD   HL, trap_y
    ADD  HL, BC
    LD   B, (HL)
    LD   C, E
    CALL map_get_tile
    JR   C, .tp_pop
    AND  FLAG_LIT | FLAG_HAS_ITEM | FLAG_OCCUPIED
    OR   TILE_TRAP | FLAG_VISITED
    CALL map_set_tile
.tp_pop:
    POP  BC
    INC  C
    LD   A, (trap_count)
    CP   C
    JR   NZ, .tlp

.chk_chests:
    LD   C, 0
.clp:
    LD   B, 0
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .c_nxt
    LD   HL, fi_meta_hi
    ADD  HL, BC
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    PUSH BC
    CALL item_get_category_a
    POP  BC
    CP   ICAT_CHEST
    JR   NZ, .c_nxt
    LD   B, 0
    LD   HL, fi_p1
    ADD  HL, BC
    LD   A, (HL)
    BIT  7, A                   ; CHEST_P1_OPENED? Skip opened
    JR   NZ, .c_nxt
    AND  CHEST_P1_TRAP_MASK
    JR   Z, .c_nxt              ; Skip untrapped
    SET  6, (HL)                ; CHEST_P1_TRAP_FOUND on armed chest only
.c_nxt:
    INC  C
    LD   A, C
    CP   MAX_FLOOR_ITEMS
    JR   C, .clp

    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; 21: Detect Doors & Stairs (silent on 6502 P6 / M5)
ovl_spell_eff_find_secret_doors:
    XOR  A
    JR   ovl_spell_eff_doors_common
ovl_spell_eff_sub_det_doors:
    LD   A, 1
ovl_spell_eff_doors_common:
    LD   (bss_scratch + 0), A
    LD   B, 1
.ylp:
    LD   C, 1
.xlp:
    CALL map_get_tile
    JR   C, .nxt
    LD   E, A
    AND  TILE_TYPE_MASK
    CP   TILE_SECRET
    JR   NZ, .chk_ds
    LD   A, E
    AND  TILE_FLAG_MASK
    OR   TILE_DOOR_CLOSED | FLAG_VISITED
    CALL map_set_tile
    JR   .nxt
.chk_ds:
    LD   H, A
    LD   A, (bss_scratch + 0)
    OR   A
    JR   Z, .nxt
    LD   A, H
    CP   TILE_STAIRS_UP
    JR   Z, .mark
    CP   TILE_STAIRS_DN
    JR   NZ, .nxt
.mark:
    LD   A, E
    OR   FLAG_VISITED
    CALL map_set_tile
.nxt:
    INC  C
    LD   A, C
    CP   MAP_COLS - 1
    JR   C, .xlp
    INC  B
    LD   A, B
    CP   MAP_ROWS - 1
    JR   C, .ylp

    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; 22: Light Room (6502 eff_light_room: scan room_x/y/w/h, light room or corridor vis_room_revealed only, silent 2d8 vs CD_LIGHT)
ovl_spell_eff_sub_light_room:
    LD   A, (room_count)
    OR   A
    JR   Z, .corridor_3x3
    LD   B, A
    LD   C, 0
.r_lp:
    LD   E, C
    LD   D, 0
    LD   HL, room_x
    ADD  HL, DE
    LD   A, (HL)
    DEC  A
    LD   (bss_scratch + 2), A   ; x0 = rx - 1
    LD   HL, room_w
    ADD  HL, DE
    LD   L, (HL)
    ADD  A, L
    INC  A
    LD   (bss_scratch + 3), A   ; x1 = rx + rw
    LD   A, (abi_player_x)
    LD   HL, bss_scratch + 2
    CP   (HL)
    JR   C, .r_nx
    INC  HL
    CP   (HL)
    JR   Z, .x_ok
    JR   NC, .r_nx
.x_ok:
    LD   HL, room_y
    ADD  HL, DE
    LD   A, (HL)
    DEC  A
    LD   (bss_scratch + 0), A   ; y0 = ry - 1
    LD   HL, room_h
    ADD  HL, DE
    LD   L, (HL)
    ADD  A, L
    INC  A
    LD   (bss_scratch + 1), A   ; y1 = ry + rh
    LD   A, (abi_player_y)
    LD   HL, bss_scratch + 0
    CP   (HL)
    JR   C, .r_nx
    INC  HL
    CP   (HL)
    JR   Z, .in_room
    JR   C, .in_room
.r_nx:
    INC  C
    DJNZ .r_lp

.corridor_3x3:
    ; Corridor: do NOT set permanent FLAG_LIT on corridor tiles; 3x3 bounds for CD_LIGHT dmg only
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   A, (abi_player_y)
    DEC  A
    LD   (bss_scratch + 0), A
    ADD  A, 2
    LD   (bss_scratch + 1), A
    LD   A, (abi_player_x)
    DEC  A
    LD   (bss_scratch + 2), A
    ADD  A, 2
    LD   (bss_scratch + 3), A
    JR   .hit_cd_light

.in_room:
    LD   HL, room_lit
    ADD  HL, DE
    LD   (HL), 1
    LD   A, (bss_scratch + 0)
    LD   B, A
.ly:
    LD   A, (bss_scratch + 2)
    LD   C, A
.lx:
    CALL map_get_tile
    JR   C, .lnx
    OR   FLAG_LIT | FLAG_VISITED
    CALL map_set_tile
.lnx:
    LD   HL, bss_scratch + 3
    LD   A, C
    CP   (HL)
    JR   Z, .ly_nx
    INC  C
    JR   .lx
.ly_nx:
    LD   HL, bss_scratch + 1
    LD   A, B
    CP   (HL)
    JR   Z, .hit_cd_light
    INC  B
    JR   .ly

.hit_cd_light:
    ; Damage CD_LIGHT (0x10) monsters inside box for 2d8 (silent survive, slay on kill)
    LD   C, 0
.mlp:
    LD   A, C
    CALL monster_get_ptr
    JR   C, .mnx
    LD   B, (HL)                ; mx
    INC  HL
    LD   D, (HL)                ; my
    INC  HL
    LD   A, (HL)                ; cr_type
    CP   EMPTY_SLOT
    JR   Z, .mnx

    LD   HL, bss_scratch + 0
    LD   A, D
    CP   (HL)
    JR   C, .mnx
    INC  HL
    CP   (HL)
    JR   Z, .yin
    JR   NC, .mnx
.yin:
    INC  HL
    LD   A, B
    CP   (HL)
    JR   C, .mnx
    INC  HL
    CP   (HL)
    JR   Z, .xin
    JR   NC, .mnx
.xin:
    LD   A, C
    CALL monster_get_ptr
    INC  HL
    INC  HL
    LD   E, (HL)
    LD   D, 0
    LD   HL, cr_cdefense
    ADD  HL, DE
    BIT  4, (HL)                ; CD_LIGHT (0x10)
    JR   Z, .mnx

    PUSH BC
    LD   B, 2
    LD   C, 8
    CALL roll_dice_bc           ; HL = 2d8
    EX   DE, HL
    POP  BC
    PUSH BC
    LD   B, C                   ; slot
    XOR  A                      ; raw light damage
    CALL ovl_spell_eff_apply_silent_surv_dmg
    POP  BC

.mnx:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .mlp

    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   A, HSTR_PIQ_LIGHT
    CALL msg_print_huff
    SCF
    RET

; 23: Wall to Mud (6502 eff_wall_to_mud: adjacent wall/vein/secret + FLAG_LIT + silent rock, else 20-tile ray CD_STONE)
ovl_spell_eff_sub_wall_mud:
    CALL ovl_spell_eff_ensure_dir
    RET  NC

    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    CALL ovl_spell_eff_step_bc
    ; Check interior bounds (edges immutable)
    LD   A, C
    OR   A
    JR   Z, .trace_ray
    CP   MAP_COLS - 1
    JR   NC, .trace_ray
    LD   A, B
    OR   A
    JR   Z, .trace_ray
    CP   MAP_ROWS - 1
    JR   NC, .trace_ray

    CALL map_get_tile
    JR   C, .trace_ray
    LD   E, A
    AND  TILE_TYPE_MASK
    CP   TILE_WALL_H
    JR   C, .trace_ray
    CP   TILE_DOOR_OPEN
    JR   C, .adj_dig
    CP   TILE_MAGMA
    JR   Z, .adj_dig
    CP   TILE_QUARTZ
    JR   Z, .adj_dig
    CP   TILE_SECRET
    JR   NZ, .trace_ray

.adj_dig:
    BIT  1, E                   ; FLAG_HAS_ITEM on any dug wall/vein/secret tile?
    JR   NZ, .vein_gold
.set_floor:
    LD   A, E
    AND  FLAG_OCCUPIED | FLAG_HAS_ITEM
    OR   TILE_FLOOR | FLAG_VISITED | FLAG_LIT
    CALL map_set_tile
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    ; Check stone monster at dug tile
    CALL monster_find_at
    JR   NC, .adj_done
.hit_stone:
    PUSH AF
    CALL monster_get_ptr
    INC  HL
    INC  HL
    LD   E, (HL)
    LD   D, 0
    LD   HL, cr_cdefense
    ADD  HL, DE
    BIT  5, (HL)                ; CD_STONE
    POP  BC                     ; B = slot
    JR   Z, .adj_done
    LD   DE, 100
    XOR  A
    CALL ovl_spell_eff_apply_bolt_dmg
.adj_done:
    SCF
    RET

.trace_ray:
    CALL ovl_spell_eff_trace_mon ; 20-tile ray -> CF=1, A=slot
    JR   NC, .adj_done
    JR   .hit_stone

.vein_gold:
    ASSERT (fi_add_ego - fi_add_x) == 10
    PUSH BC
    PUSH DE
    LD   HL, fi_add_x
    LD   (HL), C
    INC  HL                     ; fi_add_y
    LD   (HL), B
    INC  HL                     ; fi_add_id
    PUSH HL
    LD   A, 2
    CALL rng_range              ; 50/50 GOLD_SMALL (0) / GOLD_LARGE (1)
    POP  HL
    LD   (HL), A
    INC  HL                     ; fi_add_qty
    PUSH HL
    LD   A, (abi_player_dlvl)
    LD   B, A
    ADD  A, A
    JR   C, .vg_cap
    ADD  A, B
    JR   C, .vg_cap
    ADD  A, 5
    JR   NC, .vg_rng
.vg_cap:
    LD   A, 255
.vg_rng:
    CALL rng_range
    ADD  A, A
    INC  A
    POP  HL
    LD   (HL), A                ; low byte of rng(5 + dlvl*3)*2 + 1
    INC  HL                     ; fi_add_p1 (gold qty high byte)
    LD   A, 0
    ADC  A, 0
    LD   (HL), A
    LD   B, 6
    XOR  A
.z_gold:
    INC  HL
    LD   (HL), A
    DJNZ .z_gold
    CALL floor_item_add
    POP  DE
    POP  BC
    JR   C, .gold_ok
    RES  1, E                   ; clear ghost FLAG_HAS_ITEM when fi_* full
    JP   .set_floor
.gold_ok:
    PUSH BC
    PUSH DE
    LD   A, HSTR_TUN_FOUND
    CALL msg_print_huff
    POP  DE
    POP  BC
    JP   .set_floor

; 24: Glyph of Warding (6502 eff_glyph_of_warding: floor_item_find_at block, silent on table full)
ovl_spell_eff_sub_glyph:
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    CALL ovl_spell_eff_find_fi_at
    JR   NC, .chk_table
    LD   A, HSTR_PMU_GLYPH_BLOCK
    CALL msg_print_huff
    SCF
    RET
.chk_table:
    LD   D, 0xFF
    LD   E, 0
.lp:
    LD   H, 0
    LD   L, E
    PUSH DE
    LD   DE, glyph_active
    ADD  HL, DE
    POP  DE
    LD   A, (HL)
    OR   A
    JR   NZ, .chk_dup
    LD   A, D
    CP   0xFF
    JR   NZ, .nxt
    LD   D, E
    JR   .nxt
.chk_dup:
    LD   H, 0
    LD   L, E
    PUSH DE
    LD   DE, glyph_x
    ADD  HL, DE
    LD   A, (HL)
    CP   C
    JR   NZ, .pop_n
    LD   L, E
    LD   H, 0
    LD   DE, glyph_y
    ADD  HL, DE
    LD   A, (HL)
    CP   B
    POP  DE
    JR   Z, .ok_ret
    JR   .nxt
.pop_n:
    POP  DE
.nxt:
    INC  E
    LD   A, E
    CP   MAX_GLYPHS
    JR   C, .lp

    LD   A, D
    CP   0xFF
    JR   Z, .full_ret

    LD   E, A
    LD   D, 0
    LD   HL, glyph_active
    ADD  HL, DE
    LD   (HL), 1
    LD   HL, glyph_x
    ADD  HL, DE
    LD   (HL), C
    LD   HL, glyph_y
    ADD  HL, DE
    LD   (HL), B
.ok_ret:
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   A, HSTR_PMU_GLYPH_OK
    CALL msg_print_huff
.full_ret:
    SCF
    RET

; 25: Holy Word (6502 eff_holy_word: fear + poison + restore stats + full HP + HSTR_PIQ_VERY_GOOD + invuln=3 + dispel evil + turn undead core)
ovl_spell_eff_sub_holy_word:
    CALL ovl_spell_eff_remove_fear
    XOR  A
    LD   (zp_eff_poison), A     ; silent cure poison matching 6502 eff_cure_poison

    LD   A, 0xFF
    CALL player_restore_stat_a
    CALL player_calc_combat

    LD   HL, (player_data + PL_MHP_LO)
    LD   (player_data + PL_HP_LO), HL
    CALL player_sync_to_abi
    CALL status_mark_dirty
    LD   A, HSTR_PIQ_VERY_GOOD
    CALL msg_print_huff

    LD   A, 3                   ; direct set invuln = 3 (6502 eff_holy_word)
    LD   (eff_invuln_timer), A

    LD   A, (abi_player_lvl)
    ADD  A, A
    JR   NC, .d2
    LD   A, 255
.d2:
    ADD  A, A
    JR   NC, .d4
    LD   A, 255
.d4:
    LD   (eff_arg0), A
    CALL ovl_spell_eff_sub_dispel_evil
    JP   ovl_spell_eff_sub_turn_und_core

; ============================================================================
; Shared Effect Helpers
; ============================================================================

; Ensure proj_dir is 0..7; if 0xFF, prompt via tramp_modal_direction_prompt
; Output: CF=1 ready (proj_dir 0..7), CF=0 cancelled
ovl_spell_eff_ensure_dir:
    LD   A, (proj_dir)
    CP   8
    JR   C, .ok
    CALL tramp_modal_direction_prompt ; CF=1, A=dir 0..7
    RET  NC
    LD   (proj_dir), A
.ok:
    SCF
    RET

; Advance (B=y, C=x) one step in (proj_dir)
ovl_spell_eff_step_bc:
    PUSH HL
    PUSH DE
    LD   A, (proj_dir)
    AND  0x07
    LD   E, A
    LD   D, 0
    LD   HL, dir_dx
    ADD  HL, DE
    LD   A, C
    ADD  A, (HL)
    LD   C, A
    LD   HL, dir_dy
    ADD  HL, DE
    LD   A, B
    ADD  A, (HL)
    LD   B, A
    POP  DE
    POP  HL
    RET

; Trace ray from player in (proj_dir) up to range 20 to first monster
; Output: CF=1 -> A=slot, HL=mon_ptr; CF=0 -> no monster hit
ovl_spell_eff_trace_mon:
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    LD   D, 20
.lp:
    CALL ovl_spell_eff_step_bc
    PUSH DE
    CALL map_get_tile
    POP  DE
    JR   C, .miss
    PUSH AF
    CALL tile_is_walkable_a
    JR   NC, .miss_pop
    POP  AF
    BIT  0, A
    JR   NZ, .hit
    DEC  D
    JR   NZ, .lp
    JR   .miss
.miss_pop:
    POP  AF
.miss:
    OR   A
    RET
.hit:
    JP   monster_find_at

; Apply elemental/harm scaled damage DE to monster slot B with elem A
; Bolts (H=3): survive wakes (no MF_PROVOKED) + hit msg
; Light Room (H=2): survive wakes silently
; Balls (H=0): no wake on survive, silent
ovl_spell_eff_apply_bolt_dmg:
    LD   H, 3                   ; bit 0 = hit_msg, bit 1 = wake_on_survive
    JR   _ose_apply_dmg_common
ovl_spell_eff_apply_silent_surv_dmg:
    LD   H, 2                   ; silent survive, wakes (Light Room)
    JR   _ose_apply_dmg_common
ovl_spell_eff_apply_ball_dmg:
    LD   H, 0                   ; silent survive, no monster_wake (Balls)
_ose_apply_dmg_common:
    ; B = slot, A = elem, DE = base_dmg, H = hit_msg_flag
    PUSH HL                     ; [hit_msg_flag]
    PUSH BC
    PUSH AF
    PUSH DE
    LD   A, B
    CALL monster_get_ptr        ; HL = mon_ptr (preserves B)
    POP  DE
    JR   C, .bad_slot
    POP  AF
    POP  BC                     ; B = slot, A = elem, DE = base_dmg, HL = mon_ptr

    PUSH HL                     ; [mon_ptr, hit_msg_flag]
    INC  HL
    INC  HL
    LD   C, (HL)                ; C = cr_type
    PUSH BC                     ; [slot/type, mon_ptr, hit_msg_flag]
    CALL ovl_spell_eff_scale_dmg ; DE = scaled_dmg
    POP  BC                     ; B = slot, C = cr_type
    POP  HL                     ; HL = mon_ptr

    PUSH BC                     ; [slot/type, hit_msg_flag]
    CALL ovl_spell_eff_sub_mon_hp_no_wake ; CF=1 killed, CF=0 alive
    POP  BC                     ; B = slot, C = cr_type
    POP  HL                     ; H = hit_msg_flag
    JR   C, .killed

    ; Survived: wake without MF_PROVOKED only when bit 1 of H is set
    BIT  1, H
    JR   Z, .chk_hit_msg
    PUSH BC
    PUSH HL
    LD   A, B
    CALL monster_wake
    POP  HL
    POP  BC
.chk_hit_msg:
    BIT  0, H
    RET  Z

    ; Bolt hit message: "Your spell hits the <name>."
    PUSH BC
    LD   A, HSTR_EB_SPELL_HITS
    LD   DE, line_buf
    CALL huff_decode_string
    LD   HL, line_buf
.fnul_h:
    LD   A, (HL)
    OR   A
    JR   Z, .app_h
    INC  HL
    JR   .fnul_h
.app_h:
    EX   DE, HL
    LD   HL, ovl_spell_eff_s_the_lc
    CALL ovl_spell_eff_strcpy
    POP  BC
    LD   A, C
    CALL monster_get_name_ptr
    CALL ovl_spell_eff_strcpy
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   HL, line_buf
    JP   msg_print_str

.killed:
    PUSH BC
    LD   DE, line_buf
    LD   HL, ovl_spell_eff_s_slay_p
    CALL ovl_spell_eff_strcpy
    LD   A, C
    CALL monster_get_name_ptr
    CALL ovl_spell_eff_strcpy
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   HL, line_buf
    CALL msg_print_str
    POP  BC
    LD   A, B
    JP   tramp_modal_kill_monster

.bad_slot:
    POP  AF
    POP  BC
    POP  HL
    RET

; Subtract DE from MX_HP_LO/HI of mon_ptr HL without waking or printing. Output CF=1 if <=0 (killed), CF=0 if alive.
ovl_spell_eff_sub_mon_hp_no_wake:
    INC  HL
    INC  HL
    INC  HL                     ; MX_HP_LO
    LD   A, (HL)
    SUB  E
    LD   (HL), A
    INC  HL
    LD   A, (HL)
    SBC  A, D
    LD   (HL), A
    JR   C, .killed
    OR   A
    JR   NZ, .alive
    DEC  HL
    LD   A, (HL)
    OR   A
    JR   Z, .killed
.alive:
    OR   A
    RET
.killed:
    SCF
    RET

; Scale DE by elem A (ELEM_*) and ball_harm vs monster cr_type C
; Returns DE = scaled damage (u16)
ovl_spell_eff_scale_dmg:
    OR   A
    JR   Z, .chk_harm           ; ELEM_NONE
    LD   B, A                   ; B = elem
    PUSH DE
    LD   E, C
    LD   D, 0
    LD   HL, cr_cdefense
    ADD  HL, DE
    LD   A, (HL)                ; A = cr_cdefense
    POP  DE

    ; Double damage for CD_* weakness (including CD_LIGHT for ELEM_LIGHTNING)
    LD   H, 0
    LD   A, B
    CP   ELEM_FROST
    JR   NZ, .c_fire
    LD   H, CD_FROST
    LD   B, MS_BREATH_FROST
    JR   .do_elem
.c_fire:
    CP   ELEM_FIRE
    JR   NZ, .c_psn
    LD   H, CD_FIRE
    LD   B, MS_BREATH_FIRE
    JR   .do_elem
.c_psn:
    CP   ELEM_POISON
    JR   NZ, .c_acd
    LD   H, CD_POISON
    LD   B, MS_BREATH_GAS
    JR   .do_elem
.c_acd:
    CP   ELEM_LIGHTNING
    JR   Z, .c_lit
    CP   ELEM_ACID
    JR   NZ, .chk_harm
    LD   H, CD_ACID
    LD   B, MS_BREATH_ACID
    JR   .do_elem
.c_lit:
    LD   H, CD_LIGHT            ; M8 Lightning Bolt 2x vs CD_LIGHT!
    LD   B, MS_BREATH_LIGHTNING

.do_elem:
    PUSH DE
    LD   E, C
    LD   D, 0
    PUSH HL
    LD   HL, cr_cdefense
    ADD  HL, DE
    LD   A, (HL)
    POP  HL
    POP  DE
    AND  H
    JR   Z, .chk_breath_res
    SLA  E
    RL   D
    JR   .chk_harm

.chk_breath_res:
    ; Must check MSF_BREATH bit in cr_spell_flags[C] before cr_spell_chance[6:4] (6502 eff_scale_elem_damage)
    PUSH DE
    LD   E, C
    LD   D, 0
    LD   HL, cr_spell_flags
    ADD  HL, DE
    BIT  1, (HL)                ; MSF_BREATH (0x02)
    JR   Z, .no_res
    LD   HL, cr_spell_chance
    ADD  HL, DE
    LD   A, (HL)
    POP  DE
    RRCA
    RRCA
    RRCA
    RRCA
    AND  0x07
    CP   B
    JR   Z, .div4
    CP   MS_BREATH_ALL
    JR   NZ, .chk_harm
.div4:
    SRL  D
    RR   E
    SRL  D
    RR   E
    JR   .chk_harm
.no_res:
    POP  DE

.chk_harm:
    LD   A, (ball_harm)
    OR   A
    RET  Z
    PUSH DE
    LD   E, C
    LD   D, 0
    LD   HL, cr_mflags
    ADD  HL, DE
    AND  (HL)
    POP  DE
    RET  Z
    SLA  E
    RL   D
    RET

; Try to sleep monster slot A (CD_NO_SLEEP immune, else rng_range(40)+1 >= cr_level). Silent, CF=1 slept.
ovl_spell_eff_try_sleep:
    CALL ovl_spell_eff_get_live_mon
    JR   C, .fail
    CALL ovl_spell_eff_get_cr_cdef ; B=cr_type, D=cdefense, E=cr_level
    BIT  6, D                   ; CD_NO_SLEEP
    JR   NZ, .fail
    PUSH AF
    PUSH DE
    LD   A, 40
    CALL rng_range
    INC  A                      ; 1..40 >= cr_level (6502 pmx_try_sleep_monster)
    POP  DE
    CP   E
    JR   C, .imm_pop
    POP  AF
    LD   B, 255
    CALL monster_apply_sleep
    SCF
    RET
.imm_pop:
    POP  AF
.fail:
    OR   A
    RET

; Try polymorph on slot A (Balrog/level>40/rng<level resist)
ovl_spell_eff_try_poly_slot:
    CALL ovl_spell_eff_get_live_mon
    RET  C
    CALL ovl_spell_eff_get_cr_cdef ; B=cr_type, E=cr_level
    PUSH AF
    LD   A, B
    CALL monster_is_balrog_slot
    JR   Z, .res_pop
    LD   A, E
    CP   MONS_LEVEL_MAX + 1
    JR   NC, .res_pop
    PUSH DE
    LD   A, 40
    CALL rng_range
    POP  DE
    CP   E
    JR   C, .res_pop
    POP  AF
    JR   ovl_spell_eff_do_poly_slot
.res_pop:
    POP  AF
    LD   A, B
    JP   ovl_spell_eff_print_unaffected

ovl_spell_eff_do_poly_slot:
    ; A = slot, HL = mon_ptr
    LD   C, (HL)                ; MX_X
    INC  HL
    LD   B, (HL)                ; MX_Y
    PUSH BC                     ; save y, x across monster_remove
    CALL monster_remove
    CALL pick_any_creature_type ; A = new cr_type
    POP  BC                     ; B = y, C = x
    JP   monster_spawn_awake

; Return CF=0, HL=mon_ptr if slot A is valid & occupied (!EMPTY_SLOT); preserves A, BC, DE
ovl_spell_eff_get_live_mon:
    CALL monster_get_ptr
    RET  C
    PUSH BC
    LD   B, A                   ; save slot
    PUSH HL
    INC  HL
    INC  HL
    LD   A, (HL)                ; MX_TYPE
    POP  HL
    CP   EMPTY_SLOT
    LD   A, B                   ; restore slot
    POP  BC
    JR   Z, .empty
    OR   A                      ; CF = 0
    RET
.empty:
    SCF
    RET

; Read cr_type -> B, cr_cdefense -> D, cr_level -> E for mon_ptr HL (preserves A, HL)
ovl_spell_eff_get_cr_cdef:
    PUSH AF
    PUSH HL
    INC  HL
    INC  HL
    LD   B, (HL)                ; cr_type
    LD   E, B
    LD   D, 0
    LD   HL, cr_level
    ADD  HL, DE
    LD   C, (HL)                ; level
    LD   HL, cr_cdefense
    ADD  HL, DE
    LD   D, (HL)                ; cdefense
    LD   E, C                   ; level
    POP  HL
    POP  AF
    RET

; Chebyshev distance from mon_ptr HL to (abi_player_x/y) -> A (preserves C, HL)
ovl_spell_eff_dist_to_player:
    PUSH DE
    LD   E, (HL)                ; mx
    INC  HL
    LD   D, (HL)                ; my
    DEC  HL
    CALL ovl_spell_eff_dist_de_player
    POP  DE
    RET

; Chebyshev distance from (D=y, E=x) to player -> A (preserves C, HL)
ovl_spell_eff_dist_de_player:
    LD   A, (abi_player_x)
    SUB  E
    JR   NC, .dxp
    NEG
.dxp:
    LD   E, A
    LD   A, (abi_player_y)
    SUB  D
    JR   NC, .dyp
    NEG
.dyp:
    CP   E
    RET  NC
    LD   A, E
    RET

; Clear door_state entry at (B=y, C=x) if present (preserves B, C)
ovl_spell_eff_clear_door_state_at:
    LD   A, (door_state_count)
    OR   A
    RET  Z
    LD   E, 0
.lp:
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
    JR   Z, .del
.nx:
    INC  E
    LD   A, (door_state_count)
    CP   E
    JR   NZ, .lp
    RET
.del:
    LD   HL, door_state_count
    DEC  (HL)
    LD   A, (HL)
    CP   E
    RET  Z
    PUSH BC
    LD   C, A
    LD   B, 0
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
    POP  BC
    RET

; Find first floor item at (B=y, C=x) -> CF=1 A=slot, CF=0 none (preserves B, C)
ovl_spell_eff_find_fi_at:
    LD   E, 0
.lp:
    LD   D, 0
    LD   HL, fi_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .nx
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

; Remove trap entry matching (B=y, C=x) from trap_x/trap_y (preserves B, C)
ovl_spell_eff_remove_trap_at:
    LD   A, (trap_count)
    OR   A
    RET  Z
    LD   E, 0
.lp:
    LD   D, 0
    LD   HL, trap_x
    ADD  HL, DE
    LD   A, (HL)
    CP   C
    JR   NZ, .nxt
    LD   HL, trap_y
    ADD  HL, DE
    LD   A, (HL)
    CP   B
    JR   Z, .del
.nxt:
    INC  E
    LD   A, (trap_count)
    CP   E
    JR   NZ, .lp
    RET
.del:
    LD   HL, trap_count
    DEC  (HL)
    LD   A, (HL)
    CP   E
    RET  Z
    PUSH BC
    LD   C, A
    LD   B, 0
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
    POP  BC
    RET

ovl_spell_eff_cure_poison:
    LD   HL, zp_eff_poison
    LD   A, (HL)
    OR   A
    JR   Z, .done               ; 6502: silent when not poisoned
    LD   (HL), 0
    LD   A, HSTR_EFF_POISON_END
    CALL msg_print_huff
.done:
    SCF
    RET

ovl_spell_eff_remove_fear:
    LD   HL, eff_fear_timer
    LD   A, (HL)
    OR   A
    JR   Z, .done               ; 6502: silent when not afraid
    LD   (HL), 0
    LD   A, HSTR_EFF_FEAR_END
    CALL msg_print_huff
.done:
    SCF
    RET

ovl_spell_eff_add_bless:
    LD   HL, zp_eff_bless
    LD   C, (HL)
    CALL ovl_spell_eff_add_sat
    LD   A, C
    OR   A
    JR   NZ, .done              ; onset-only (6502 pmx_add_bless_msg)
    LD   HL, ovl_spell_eff_s_bless
    CALL msg_print_str
.done:
    SCF
    RET

ovl_spell_eff_add_sat:
    ADD  A, (HL)
    JR   NC, .ok
    LD   A, 255
.ok:
    LD   (HL), A
    RET

ovl_spell_eff_3x_lvl:
    LD   A, (abi_player_lvl)
    LD   B, A
    ADD  A, B
    JR   NC, .a2
    LD   A, 255
    RET
.a2:
    ADD  A, B
    RET  NC
    LD   A, 255
    RET

ovl_spell_eff_remove_curse:
    ; A = 0: worn equip 22..33 (M13); A = 1: all 0..33 (P14)
    OR   A
    LD   C, EQUIP_WEAPON
    LD   B, TOTAL_INV_SLOTS
    JR   Z, .lp
    LD   C, 0
.lp:
    LD   E, C
    LD   D, 0
    LD   HL, inv_flags
    ADD  HL, DE
    RES  0, (HL)                ; clear IF_CURSED
    INC  C
    LD   A, C
    CP   B
    JR   C, .lp
    LD   A, HSTR_PIQ_CLEANSED
    CALL msg_print_huff
    SCF
    RET

ovl_spell_eff_create_food:
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    CALL ovl_spell_eff_find_fi_at
    CALL C, floor_item_remove   ; overwrite floor item under player (6502 pmu_create_food)
    LD   A, (abi_player_x)
    LD   (fi_add_x), A
    LD   A, (abi_player_y)
    LD   (fi_add_y), A
    LD   A, ITEM_SLOT_RATION_OF_FOOD
    LD   (fi_add_id), A
    LD   A, ITEM_PAGE_RATION_OF_FOOD
    LD   (item_cur_page), A
    LD   A, 1
    LD   (fi_add_qty), A
    XOR  A
    LD   (fi_add_qty_hi), A
    LD   (fi_add_p1), A
    LD   (fi_add_to_hit), A
    LD   (fi_add_to_dam), A
    LD   (fi_add_to_ac), A
    LD   (fi_add_flags), A
    LD   (fi_add_ego), A
    CALL floor_item_add
    JR   C, .ok
    LD   A, HSTR_PMU_GLYPH_BLOCK ; "There is already an object under you."
    CALL msg_print_huff
    SCF
    RET
.ok:
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   A, HSTR_PMU_CREATE_FOOD
    CALL msg_print_huff
    SCF
    RET

ovl_spell_eff_recharge:
    ; A = power (20 or 50)
    PUSH AF
    LD   A, PIW_FILTER_RECHARGE
    LD   HL, 0x5600             ; trigger overlay-prompt lookup in ovl_item_mgt ("Recharge which item (a-X)?")
    LD   B, 0
    CALL tramp_item_mgt_select_inv
    JR   C, .got_item
    POP  AF
    OR   A
    RET
.got_item:
    POP  BC                     ; B = power
    LD   E, A
    LD   D, 0                   ; DE = slot
    LD   HL, inv_p1
    ADD  HL, DE
    LD   C, (HL)                ; C = cur charges

    LD   A, B
    SRL  A
    SRL  A
    SRL  A
    LD   L, A                   ; L = power >> 3
    ADD  A, 2
    CP   C
    JR   Z, .chk_blow
    JR   NC, .add_chg
.chk_blow:
    PUSH DE
    PUSH HL
    LD   A, 4
    CALL rng_range
    POP  HL
    POP  DE
    OR   A
    JR   NZ, .add_chg
    LD   A, E
    CALL inv_remove_item
    CALL status_mark_dirty
    LD   HL, ovl_spell_eff_s_blow
    CALL msg_print_str
    SCF
    RET
.add_chg:
    LD   A, L
    INC  A
    PUSH DE
    CALL rng_range
    POP  DE
    ADD  A, 2
    LD   HL, inv_p1
    ADD  HL, DE
    ADD  A, (HL)
    JR   NC, .st_c
    LD   A, 255
.st_c:
    LD   (HL), A
    ; Print "The <item> glows briefly."
    PUSH DE
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_item_id), A
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_ego), A
    XOR  A
    LD   (itemdesc_qty), A
    LD   (itemdesc_flags), A
    LD   DE, line_buf
    LD   HL, ovl_spell_eff_s_the
    CALL ovl_spell_eff_strcpy
    CALL item_format_staged     ; appends item name without qty prefix, advances DE? Check or find NUL!
    POP  DE
    ; Walk line_buf to NUL and append " glows briefly."
    LD   HL, line_buf
.fnul:
    LD   A, (HL)
    OR   A
    JR   Z, .app_g
    INC  HL
    JR   .fnul
.app_g:
    EX   DE, HL
    LD   HL, ovl_spell_eff_s_glow
    CALL ovl_spell_eff_strcpy
    LD   HL, line_buf
    CALL msg_print_str
    SCF
    RET

; Print "The <monster name><suffix_DE>"
ovl_spell_eff_print_unaffected:
    LD   DE, ovl_spell_eff_s_unaff
ovl_spell_eff_print_mon_msg:
    PUSH DE
    CALL monster_get_name_ptr   ; HL = ASCII name
    LD   DE, temp_str_buf
    PUSH HL
    LD   HL, ovl_spell_eff_s_the
    CALL ovl_spell_eff_strcpy
    POP  HL
    CALL ovl_spell_eff_strcpy
    POP  HL
    CALL ovl_spell_eff_strcpy
    XOR  A
    LD   (DE), A
    LD   HL, temp_str_buf
    JP   msg_print_str

ovl_spell_eff_strcpy:
    LD   A, (HL)
    OR   A
    JR   Z, .done
    LD   (DE), A
    INC  HL
    INC  DE
    JR   ovl_spell_eff_strcpy
.done:
    LD   (DE), A
    RET

; ============================================================================
; Strings
; ============================================================================
ovl_spell_eff_s_the:     DB "The ", 0
ovl_spell_eff_s_the_lc:  DB " the ", 0
ovl_spell_eff_s_slay_p:  DB "You have slain the ", 0
ovl_spell_eff_s_unaff:   DB " is unaffected.", 0
ovl_spell_eff_s_shud:    DB " shudders.", 0
ovl_spell_eff_s_diss:    DB " dissolves!", 0
ovl_spell_eff_s_runs:    DB " runs frantically!", 0
ovl_spell_eff_s_slow:    DB "It slows.", 0
ovl_spell_eff_s_slp_ok:  DB "A monster falls asleep.", 0
ovl_spell_eff_s_slp_no:  DB "A monster is unaffected.", 0
ovl_spell_eff_s_bless:   DB "You feel righteous!", 0
ovl_spell_eff_s_resist:  DB "You feel resistant to heat and cold.", 0
ovl_spell_eff_s_det_evil: DB "You sense the presence of evil!", 0
ovl_spell_eff_s_no_evil:  DB "You sense no evil nearby.", 0
ovl_spell_eff_s_no_mon:   DB "You sense no creatures nearby.", 0
ovl_spell_eff_s_det_tr:   DB "You sense treasure nearby.", 0
ovl_spell_eff_s_det_ob:   DB "You sense objects nearby.", 0
ovl_spell_eff_s_blow:    DB "There is a bright flash of light.", 0
ovl_spell_eff_s_glow:    DB " glows briefly.", 0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_spell_eff.ovl", ovl_start, ovl_end - ovl_start
