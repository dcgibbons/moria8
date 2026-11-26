; ovl_items.asm — Moria8 CP/M Consumable Dispatch Overlay (Quaff, Read, Aim, Use).
; (OVL_ITEMS = 7, DAT slot 6)
;
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0: JP ovl_items_quaff          ('q') -> CF=1 turn, CF=0 cancel
;   +3: JP ovl_items_read           ('r') -> CF=1 turn, CF=0 cancel
;   +6: JP ovl_items_aim            ('a') -> CF=1 turn, CF=0 cancel
;   +9: JP ovl_items_use            ('u'/'z') -> CF=1 turn, CF=0 cancel
;
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax, DEVICE NOSLOT64K).
; All public entry vectors preserve IX and IY.
; No live state is kept in overlay-local RAM across any tramp_* call.

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "item_ids_z80.inc"
    DEFINE HUFF_CONSTS_ONLY 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_CONSTS_ONLY
    INCLUDE "main_exp.inc"

    ORG  OVL_WINDOW_BASE        ; 0x5600

ovl_start:
    JP   ovl_items_quaff            ; +0
    JP   ovl_items_read             ; +3
    JP   ovl_items_aim              ; +6
    JP   ovl_items_use              ; +9
    JP   ovl_items_pseudo_id        ; +12
    JP   ovl_items_eat_ext          ; +15
    JP   ovl_items_world_cold       ; +18

ovl_items_world_cold:
    PUSH IX
    PUSH IY
    CALL _it_world_cold
    JR   _it_ret_ixiy

ovl_items_pseudo_id:
    PUSH IX
    PUSH IY
    CALL _it_pseudo_id
    JP   _it_ret_ixiy

ovl_items_eat_ext:
    PUSH IX
    PUSH IY
    CALL _it_eat_ext
    JR   _it_ret_ixiy

; ============================================================================
; Public Entry Wrappers (preserve IX and IY)
; ============================================================================

ovl_items_quaff:
    PUSH IX
    PUSH IY
    CALL _it_quaff
    JR   _it_ret_ixiy

ovl_items_read:
    PUSH IX
    PUSH IY
    CALL _it_read
    JR   _it_ret_ixiy

ovl_items_aim:
    PUSH IX
    PUSH IY
    CALL _it_aim
    JR   _it_ret_ixiy

ovl_items_use:
    PUSH IX
    PUSH IY
    CALL _it_use
_it_ret_ixiy:
    POP  IY
    POP  IX
    RET

; ============================================================================
; +0: _it_quaff — Select & quaff potion, mark known, apply all 45 VMS potions
; ============================================================================
_it_quaff:
    LD   A, ICAT_POTION
    LD   B, HSTR_PIQ_QUAFF_PROMPT
    LD   HL, 0
    CALL tramp_item_mgt_select_inv  ; CF=1, A=slot, C=item_id
    RET  NC

    LD   E, A
    LD   D, 0
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A

    PUSH BC                         ; C = item_id
    PUSH DE                         ; E = slot
    LD   A, E
    CALL inv_consume_one
    POP  DE
    POP  BC

    LD   A, (item_cur_page)
    OR   A
    JR   NZ, .unknown_eff
    LD   A, C
    SUB  ITEM_SLOT_POTION_OF_GAIN_STRENGTH
    JR   C, .unknown_eff
    CP   45
    JR   NC, .unknown_eff

    ; Save item_id C across handler, dispatch via table -> returns CF=1 if identifiable
    PUSH BC
    LD   E, A
    LD   D, 0
    LD   HL, _it_pot_tbl
    ADD  HL, DE
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    EX   DE, HL
    CALL _it_call_hl                ; CF=1 -> mark id_known
    POP  BC
    JR   NC, .quaff_done
    XOR  A
    LD   (item_cur_page), A
    LD   A, C
    CALL id_mark_known
.quaff_done:
    CALL status_mark_dirty
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

.unknown_eff:
    LD   A, HSTR_PIQ_NOTHING
    CALL msg_print_huff
    JR   .quaff_done

; ============================================================================
; +3: _it_read — Check sight, select scroll, mark known, consume & execute
; ============================================================================
_it_read:
    LD   A, (zp_eff_blind)
    OR   A
    JR   Z, .can_see
    LD   A, HSTR_PIQ_CANT_READ
    CALL msg_print_huff
    OR   A
    RET
.can_see:
    LD   A, ICAT_SCROLL
    LD   B, HSTR_PIQ_READ_PROMPT
    LD   HL, 0
    CALL tramp_item_mgt_select_inv
    RET  NC

    LD   E, A                       ; E = slot
    LD   D, 0
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   (eff_arg1), A
    LD   A, C
    LD   (eff_arg0), A

    PUSH DE
    CALL id_mark_known
    POP  DE
    LD   A, E
    CALL inv_consume_one
    CALL status_mark_dirty
    CALL tramp_items_eff_scroll
    SCF
    RET

; ============================================================================
; +6: _it_aim — Select wand, check charges FIRST, prompt dir, consume & execute
; ============================================================================
_it_aim:
    LD   A, ICAT_WAND
    LD   B, HSTR_PIW_AIM_PROMPT
    LD   HL, 0
    CALL tramp_item_mgt_select_inv
    RET  NC

    LD   (eff_arg0), A              ; slot
    LD   E, A
    LD   D, 0
    LD   HL, inv_p1
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    JR   NZ, .chk_dir
    LD   A, HSTR_PIW_NO_CHARGES
    CALL msg_print_huff
    OR   A                          ; 6502 parity: empty wand = free turn (CF=0)
    RET
.chk_dir:
    LD   A, C
    LD   (eff_arg1), A              ; item_id
    ; 6502 parity: spend charge, mark known, dirty status BEFORE direction prompt
    LD   HL, inv_p1
    ADD  HL, DE
    DEC  (HL)
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (eff_arg1)
    PUSH DE
    CALL id_mark_known
    CALL status_mark_dirty
    POP  DE
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    JR   NZ, .need_dir
    LD   A, (eff_arg1)
    CP   ITEM_SLOT_WAND_OF_LIGHT
    JR   Z, .skip_dir
.need_dir:
    CALL tramp_modal_direction_prompt
    JR   C, .dir_ok
    SCF
    RET
.dir_ok:
    LD   A, (df_dir_idx)
    LD   (eff_arg2), A
    LD   (proj_dir), A
.skip_dir:
    CALL tramp_items_eff_wand
    SCF
    RET

; ============================================================================
; +9: _it_use — Select staff, check charges, consume & execute (empty = free turn)
; ============================================================================
_it_use:
    LD   A, ICAT_STAFF
    LD   B, HSTR_PIW_USE_PROMPT
    LD   HL, 0
    CALL tramp_item_mgt_select_inv
    RET  NC

    LD   (eff_arg0), A              ; slot
    LD   A, C
    LD   (eff_arg1), A              ; item_id

    LD   A, (eff_arg0)
    LD   E, A
    LD   D, 0
    LD   HL, inv_p1
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    JR   NZ, .have_chg
    LD   A, HSTR_PIW_STAFF_EMPTY
    CALL msg_print_huff
    OR   A                          ; 6502 parity: empty staff = free turn (CF=0)
    RET
.have_chg:
    DEC  (HL)
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (eff_arg1)
    CALL id_mark_known
    CALL status_mark_dirty
    CALL tramp_items_eff_staff
    SCF
    RET

; ============================================================================
; All 45 Potion Handlers (Slots 50..94) -> CF=1 if identifiable
; ============================================================================

_it_pot_tbl:
    DW _p_gain_str                  ; 50 GAIN_STRENGTH
    DW _p_lose_str                  ; 51 WEAKNESS
    DW _p_rest_str                  ; 52 RESTORE_STRENGTH
    DW _p_gain_int                  ; 53 GAIN_INTELLIGENCE
    DW _p_lose_int                  ; 54 LOSE_INTELLIGENCE
    DW _p_rest_int                  ; 55 RESTORE_INTELLIGENCE
    DW _p_gain_wis                  ; 56 GAIN_WISDOM
    DW _p_lose_wis                  ; 57 LOSE_WISDOM
    DW _p_rest_wis                  ; 58 RESTORE_WISDOM
    DW _p_gain_chr                  ; 59 CHARISMA
    DW _p_lose_chr                  ; 60 UGLINESS
    DW _p_rest_chr                  ; 61 RESTORE_CHARISMA
    DW _p_cure_light                ; 62 CURE_LIGHT_WOUNDS
    DW _p_cure_serious              ; 63 CURE_SERIOUS_WOUNDS
    DW _p_cure_crit                 ; 64 CURE_CRITICAL_WOUNDS
    DW _p_healing                   ; 65 HEALING
    DW _p_gain_con                  ; 66 GAIN_CONSTITUTION
    DW _p_gain_xp                   ; 67 GAIN_EXPERIENCE
    DW _p_sleep                     ; 68 SLEEP
    DW _p_blind                     ; 69 BLINDNESS
    DW _p_confuse                   ; 70 CONFUSION
    DW _p_poison                    ; 71 POISON
    DW _p_speed                     ; 72 SPEED
    DW _p_slow                      ; 73 SLOWNESS
    DW _p_slime_juice               ; 74 SLIME_MOLD_JUICE
    DW _p_apple_juice               ; 75 APPLE_JUICE
    DW _p_water                     ; 76 WATER
    DW _p_gain_dex                  ; 77 GAIN_DEXTERITY
    DW _p_rest_dex                  ; 78 RESTORE_DEXTERITY
    DW _p_rest_con                  ; 79 RESTORE_CONSTITUTION
    DW _p_learning                  ; 80 LEARNING
    DW _p_lose_mem                  ; 81 LOSE_MEMORIES
    DW _p_salt_water                ; 82 SALT_WATER
    DW _p_invuln                    ; 83 INVULNERABILITY
    DW _p_heroism                   ; 84 HEROISM
    DW _p_super_hero                ; 85 SUPER_HEROISM
    DW _p_boldness                  ; 86 BOLDNESS
    DW _p_rest_life                 ; 87 RESTORE_LIFE_LEVELS
    DW _p_res_heat                  ; 88 RESIST_HEAT
    DW _p_res_cold                  ; 89 RESIST_COLD
    DW _p_det_invis                 ; 90 DETECT_INVISIBLE
    DW _p_slow_poison               ; 91 SLOW_POISON
    DW _p_neut_poison               ; 92 NEUTRALIZE_POISON
    DW _p_rest_mana                 ; 93 RESTORE_MANA
    DW _p_infra                     ; 94 INFRAVISION

_p_gain_str: LD C, 0 : JR _p_gain_stat
_p_gain_int: LD C, 1 : JR _p_gain_stat
_p_gain_wis: LD C, 2 : JR _p_gain_stat
_p_gain_dex: LD C, 3 : JR _p_gain_stat
_p_gain_con: LD C, 4 : JR _p_gain_stat
_p_gain_chr: LD C, 5
_p_gain_stat:
    ; Step on BASE: <18 -> +1; <88 -> rng(25)+1; <108 -> rng(10)+1; >=108 -> +1 (cap 118)
    LD   B, 0
    LD   HL, player_data + PL_STR_BASE
    ADD  HL, BC
    LD   E, (HL)                    ; E = old_base
    LD   A, E
    CP   18
    LD   A, 1
    JR   C, .add
    LD   A, E
    CP   88
    LD   A, 25
    JR   C, .roll
    LD   A, E
    CP   108
    LD   A, 10
    JR   C, .roll
    LD   A, 1
    JR   .add
.roll:
    CALL rng_range
    INC  A
.add:
    ADD  A, E
    CP   119
    JR   C, .cap_ok
    LD   A, 118
.cap_ok:
    LD   (HL), A
    SUB  E                          ; step = new_base - old_base
    LD   E, A
    LD   HL, player_data + PL_STR_CUR
    ADD  HL, BC
    LD   L, (HL)
    LD   H, 0
    LD   D, 0
    ADD  HL, DE                     ; HL = cur + step
    PUSH HL
    LD   HL, player_stat_res
    ADD  HL, BC
    LD   A, (HL)
    POP  HL
    LD   E, A
    ADD  A, A
    SBC  A, A
    LD   D, A
    ADD  HL, DE                     ; HL = cur + res + step (signed 16-bit)
    BIT  7, H
    JR   NZ, .gs_under
    LD   A, H
    OR   A
    JR   NZ, .gs_over
    LD   A, L
    CP   3
    JR   C, .gs_under
    CP   119
    JR   NC, .gs_over
    LD   D, L
    LD   E, 0
    JR   .gs_store
.gs_under:
    LD   DE, -3
    ADD  HL, DE
    INC  H
    JR   NZ, .gs_m128
    LD   A, L
    CP   0x80
    JR   NC, .gs_uok
.gs_m128:
    LD   A, 0x80
.gs_uok:
    LD   E, A
    LD   D, 3
    JR   .gs_store
.gs_over:
    LD   DE, -118
    ADD  HL, DE
    LD   A, H
    OR   A
    JR   NZ, .gs_p127
    LD   A, L
    CP   128
    JR   C, .gs_ook
.gs_p127:
    LD   A, 127
.gs_ook:
    LD   E, A
    LD   D, 118
.gs_store:
    PUSH DE
    LD   HL, player_data + PL_STR_CUR
    ADD  HL, BC
    LD   (HL), D
    LD   HL, player_stat_res
    ADD  HL, BC
    POP  DE
    LD   (HL), E
    LD   A, C
    CP   STAT_CON
    JR   NZ, .not_con
    PUSH BC
    CALL player_calc_hp
    LD   HL, 0xFFFF
    CALL eff_heal
    POP  BC
.not_con:
    PUSH BC
    CALL _it_recalc_all
    POP  BC
    LD   E, C
    LD   D, 0
    LD   HL, _it_gain_hstr
    ADD  HL, DE
    LD   A, (HL)
    PUSH BC
    CALL msg_print_huff
    POP  BC
    LD   A, C
    CP   STAT_INT
    JR   Z, .recalc_spl
    CP   STAT_WIS
    JR   NZ, .done
.recalc_spl:
    CALL tramp_spell_recalc_levelup
.done:
    SCF
    RET

_p_lose_str: LD C, 0 : JR _p_lose_stat
_p_lose_int: LD C, 1 : JR _p_lose_stat
_p_lose_wis: LD C, 2 : JR _p_lose_stat
_p_lose_chr: LD C, 5
_p_lose_stat:
    LD   A, 1
    LD   B, C
    INC  B
    JR   .sb_end
.sb_lp:
    RLCA
.sb_end:
    DJNZ .sb_lp
    LD   HL, player_sust_mask
    AND  (HL)
    JR   Z, .drain
.nothing:
    LD   A, HSTR_PIQ_NOTHING
    CALL msg_print_huff
    SCF
    RET
.drain:
    LD   A, C
    CALL player_drain_stat_a
    JR   NC, .nothing
    CALL _it_recalc_all
    LD   HL, _it_s_weak
    CALL msg_print_str
    SCF
    RET

_p_rest_str: LD C, STAT_STR : JR _p_rest_stat
_p_rest_int: LD C, STAT_INT : JR _p_rest_stat
_p_rest_wis: LD C, STAT_WIS : JR _p_rest_stat
_p_rest_dex: LD C, STAT_DEX : JR _p_rest_stat
_p_rest_con: LD C, STAT_CON : JR _p_rest_stat
_p_rest_chr: LD C, STAT_CHR
_p_rest_stat:
    LD   A, C
    PUSH BC
    CALL player_restore_stat_a
    POP  BC
    LD   A, C
    CP   STAT_CON
    CALL Z, player_calc_hp
    CALL _it_recalc_all
    LD   A, HSTR_PIQ_RESTORED
    CALL msg_print_huff
    SCF
    RET

_p_cure_light:
    LD   BC, 0x0207
    LD   E, 2                       ; EFF_CURE_BLIND
    JR   _p_heal_cure
_p_cure_serious:
    LD   BC, 0x0407
    LD   E, 6                       ; EFF_CURE_BLIND | EFF_CURE_CONFUSE
    JR   _p_heal_cure
_p_cure_crit:
    LD   BC, 0x0607
    LD   E, 7                       ; EFF_CURE_ALL
_p_heal_cure:
    PUSH DE
    CALL roll_dice_bc
    POP  DE
    LD   B, A
    CALL _p_is_injured              ; CF=1 iff HP < MHP (identifiable)
    PUSH AF
    PUSH DE
    LD   A, B
    CALL _it_heal_and_report_a
    POP  DE
    LD   A, E
    CALL _it_cure_timers
    POP  AF                         ; CF=1 iff HP < MHP
    RET

_p_healing:
    CALL _p_is_injured              ; CF=1 iff HP < MHP
    PUSH AF
    LD   A, 250
    CALL _it_heal_and_report_a
    LD   B, 3
.hl3:
    PUSH BC
    LD   HL, 250
    CALL eff_heal
    POP  BC
    DJNZ .hl3
    LD   A, 7                       ; EFF_CURE_ALL
    CALL _it_cure_timers
    POP  AF
    RET

_p_is_injured:
    LD   HL, (player_data + PL_HP_LO)
    LD   DE, (player_data + PL_MHP_LO)
    OR   A
    SBC  HL, DE
    RET

_p_gain_xp:
    LD   HL, (player_data + PL_XP_0)
    LD   A, (player_data + PL_XP_2)
    LD   C, A                       ; C:HL = 24-bit PL_XP
    SRL  A
    RR   H
    RR   L                          ; A:HL = xp >> 1
    LD   DE, 10
    ADD  HL, DE
    ADC  A, 0                       ; A:HL = (xp >> 1) + 10
    LD   DE, (player_data + PL_XP_0)
    ADD  HL, DE
    ADC  A, C                       ; A:HL = xp + (xp >> 1) + 10
    JR   NC, .xp_ok
    LD   HL, 0xFFFF
    LD   A, 0xFF
.xp_ok:
    LD   (player_data + PL_XP_0), HL
    LD   (player_data + PL_XP_2), A
    LD   HL, _it_s_gain_xp
    CALL msg_print_str
    LD   HL, 0
    CALL tramp_modal_award_xp
    SCF
    RET

_p_sleep:
    LD   A, (player_pflags)
    AND  PFLAG_FREE_ACT
    JR   Z, .do_slp
    LD   A, HSTR_PIQ_NOTHING
    CALL msg_print_huff
    SCF
    RET
.do_slp:
    LD   HL, zp_eff_paralyze
    LD   A, 4
    LD   B, 4
    CALL _it_add_timer
    LD   HL, _it_s_sleep
    CALL msg_print_str
    SCF
    RET

_p_blind:
    LD   HL, zp_eff_blind
    LD   A, 100
    LD   B, 100
    CALL _it_add_timer
    LD   A, HSTR_PIQ_CANT_SEE
    CALL msg_print_huff
    SCF
    RET

_p_confuse:
    LD   HL, zp_eff_confuse
    LD   A, 15
    LD   B, 10
    CALL _it_add_timer
    LD   A, HSTR_PIQ_DIZZY
    CALL msg_print_huff
    SCF
    RET

_p_poison:
    LD   A, 6
    CALL rng_range
    ADD  A, 3
    CALL _it_pois_dmg_a
    LD   HL, zp_eff_poison
    LD   A, 10
    LD   B, 5
    CALL _it_add_timer
    LD   A, HSTR_PIQ_TERRIBLE
    CALL msg_print_huff
    SCF
    RET

_p_speed:
    LD   A, 25
    CALL rng_range
    ADD  A, 16
    LD   E, A
    LD   D, 0
    LD   A, (zp_eff_speed)
    LD   L, A
    ADD  A, A
    SBC  A, A
    LD   H, A
    ADD  HL, DE
    LD   DE, 127
    OR   A
    PUSH HL
    SBC  HL, DE
    POP  HL
    JR   C, .spd_ok
    LD   L, 127
.spd_ok:
    LD   A, L
    LD   (zp_eff_speed), A
    LD   A, HSTR_PIQ_SPEED
    CALL msg_print_huff
    SCF
    RET

_p_slow:
    LD   A, 25
    CALL rng_range
    ADD  A, 16
    LD   E, A
    LD   D, 0
    LD   A, (zp_eff_speed)
    LD   L, A
    ADD  A, A
    SBC  A, A
    LD   H, A
    OR   A
    SBC  HL, DE
    LD   A, H
    CP   0xFF
    JR   NZ, .chk_neg
    LD   A, L
    CP   0x81
    JR   NC, .slw_ok
.chk_neg:
    BIT  7, H
    JR   Z, .slw_ok
    LD   L, 0x81                    ; -127 clamp
.slw_ok:
    LD   A, L
    LD   (zp_eff_speed), A
    LD   A, HSTR_EFF_HASTE_END
    CALL msg_print_huff
    SCF
    RET

_p_slime_juice:
    LD   DE, 400
    CALL _it_add_food
    LD   A, HSTR_PIW_YUCK
    CALL msg_print_huff
    SCF
    RET

_p_apple_juice:
    LD   DE, 250
    JR   _p_drink_refresh
_p_water:
    LD   DE, 200
_p_drink_refresh:
    CALL _it_add_food
    LD   HL, _it_s_drink
    CALL msg_print_str
    SCF
    RET

_p_learning:
    LD   A, (player_data + PL_SPELL_TYPE)
    OR   A
    JR   Z, .no_sp
    LD   HL, player_data + PL_NEW_SPELLS
    INC  (HL)
.no_sp:
    LD   HL, _it_s_learn
    CALL msg_print_str
    SCF
    RET

_p_lose_mem:
    LD   A, (player_data + PL_XP_2)
    LD   E, A
    LD   HL, (player_data + PL_XP_0)
    SRL  E
    RR   H
    RR   L
    SRL  E
    RR   H
    RR   L
    LD   BC, (player_data + PL_XP_0)
    EX   DE, HL
    PUSH HL
    LD   H, B
    LD   L, C
    OR   A
    SBC  HL, DE
    LD   (player_data + PL_XP_0), HL
    POP  BC
    LD   A, (player_data + PL_XP_2)
    SBC  A, C
    JR   NC, .xp_ok
    XOR  A
    LD   (player_data + PL_XP_0), A
    LD   (player_data + PL_XP_1), A
    LD   (player_data + PL_XP_FRAC_LO), A
    LD   (player_data + PL_XP_FRAC_HI), A
.xp_ok:
    LD   (player_data + PL_XP_2), A
    LD   HL, 0
    CALL tramp_modal_award_xp
    LD   HL, _it_s_memories
    CALL msg_print_str
    SCF
    RET

_p_salt_water:
    LD   HL, (player_data + PL_FOOD_LO)
    LD   DE, 101
    OR   A
    SBC  HL, DE
    JR   C, .sw_food_ok
    LD   HL, 100
    LD   (player_data + PL_FOOD_LO), HL
    CALL player_update_hunger_state
.sw_food_ok:
    XOR  A
    LD   (zp_eff_poison), A
    LD   A, (zp_eff_paralyze)
    ADD  A, 4
    JR   NC, .sw_par
    LD   A, 0xFF
.sw_par:
    LD   (zp_eff_paralyze), A
    LD   HL, _it_s_salt
    CALL msg_print_str
    SCF
    RET

_p_invuln:
    LD   HL, eff_invuln_timer
    LD   A, 10
    LD   B, 11
    CALL _it_add_timer
    CALL status_mark_dirty
    LD   HL, _it_s_invuln
    CALL msg_print_str
    SCF
    RET

_p_heroism:
    LD   D, 0
    JR   _p_hero_common
_p_super_hero:
    LD   D, 30
_p_hero_common:
    XOR  A
    LD   (eff_fear_timer), A
    LD   A, (zp_eff_hero)
    OR   A
    JR   NZ, .sh_heal
    PUSH DE
    LD   HL, (player_data + PL_MHP_LO)
    LD   DE, 10
    ADD  HL, DE
    LD   (player_data + PL_MHP_LO), HL
    LD   (abi_player_mhp), HL
    LD   HL, 10
    CALL eff_heal
    POP  DE
.sh_heal:
    LD   A, D
    OR   A
    CALL NZ, _it_heal_and_report_a
    LD   HL, zp_eff_hero
    LD   A, 25
    LD   B, 25
    CALL _it_add_timer
    CALL _it_recalc_all
    LD   A, HSTR_PIQ_HEROIC
    CALL msg_print_huff
    SCF
    RET

_p_boldness:
    XOR  A
    LD   (eff_fear_timer), A
    LD   HL, _it_s_bold
    CALL msg_print_str
    SCF
    RET

_p_rest_life:
    LD   HL, _it_s_rest_lvl
    CALL msg_print_str
.rl_loop:
    LD   HL, player_data + PL_XP_0
    LD   B, (HL)
    INC  HL
    LD   C, (HL)
    INC  HL
    LD   A, (player_data + PL_MAX_XP_2)
    CP   (HL)
    JR   C, .rl_done
    JR   NZ, .rl_copy
    LD   A, (player_data + PL_MAX_XP_1)
    CP   C
    JR   C, .rl_done
    JR   NZ, .rl_copy
    LD   A, (player_data + PL_MAX_XP_0)
    CP   B
    JR   C, .rl_done
    JR   Z, .rl_done
.rl_copy:
    LD   HL, player_data + PL_MAX_XP_0
    LD   DE, player_data + PL_XP_0
    LD   BC, 3
    LDIR
    LD   HL, 0
    CALL tramp_modal_award_xp
    JR   .rl_loop
.rl_done:
    SCF
    RET

_p_res_heat:
    LD   HL, zp_eff_resist
    JR   _p_res_10
_p_res_cold:
    LD   HL, eff_resist_cold_timer
_p_res_10:
    LD   A, 10
    LD   B, 11
    CALL _it_add_timer
    SCF
    RET

_p_det_invis:
    LD   HL, zp_eff_see_inv
    LD   A, 12
    LD   B, 13
    CALL _it_add_timer
    CALL monster_update_visibility_all
    LD   A, HSTR_PIQ_EYES_TINGLE
    CALL msg_print_huff
    SCF
    RET

_p_slow_poison:
    LD   HL, zp_eff_poison
    LD   A, (HL)
    OR   A
    JR   Z, .sp_done
    SRL  A
    OR   1
    LD   (HL), A
    LD   A, HSTR_EFF_POISON_END
    CALL msg_print_huff
.sp_done:
    SCF
    RET

_p_neut_poison:
    XOR  A
    LD   (zp_eff_poison), A
    LD   A, HSTR_EFF_POISON_END
    CALL msg_print_huff
    SCF
    RET

_p_rest_mana:
    LD   A, (player_data + PL_MAX_MANA)
    LD   (player_data + PL_MANA), A
    LD   (abi_player_mp), A
    LD   A, HSTR_PIQ_MIND_CLEAR
    CALL msg_print_huff
    SCF
    RET

_p_infra:
    LD   HL, zp_eff_infra
    LD   A, 50
    LD   B, 50
    CALL _it_add_timer
    CALL los_update_visibility
    LD   A, HSTR_PIQ_EYES_TINGLE
    CALL msg_print_huff
    SCF
    RET

; ============================================================================
; Internal Helpers
; ============================================================================

_it_call_hl:
    JP   (HL)

_it_recalc_all:
    CALL player_calc_combat
    JP   status_mark_dirty

_it_pseudo_id:
    LD   B, 0
.pack_lp:
    LD   E, B
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .pack_nx
    CALL _it_pid_eligible
    JR   NC, .pack_nx
    LD   A, 50
    CALL rng_range
    OR   A
    JR   Z, .sense_slot
.pack_nx:
    INC  B
    LD   A, B
    CP   MAX_INV_SLOTS
    JR   C, .pack_lp

    LD   B, EQUIP_WEAPON
.eq_lp:
    LD   E, B
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .eq_nx
    CALL _it_pid_eligible
    JR   NC, .eq_nx
    LD   A, 10
    CALL rng_range
    OR   A
    JR   Z, .sense_slot
.eq_nx:
    INC  B
    LD   A, B
    CP   EQUIP_END
    JR   C, .eq_lp
    RET

.sense_slot:
    LD   E, B
    LD   D, 0
    LD   HL, inv_flags
    ADD  HL, DE
    SET  3, (HL)                    ; IF_SENSED
    LD   A, HSTR_PID_CARRY
    JP   msg_print_huff

_it_pid_eligible:
    ; Slot in DE, preserves B, DE -> CF=1 if unsensed positive magic gear
    LD   HL, inv_flags
    ADD  HL, DE
    LD   A, (HL)
    AND  IF_IDENTIFIED | IF_SENSED | IF_CURSED
    JR   NZ, .pid_no
    LD   HL, inv_ego
    ADD  HL, DE
    LD   C, (HL)                    ; C = ego byte
    BIT  6, C                       ; ITEM_PAGE_BIT
    JR   NZ, .pid_ego
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   ITEM_SLOT_WOODEN_TORCH
    JR   Z, .pid_no
    CP   ITEM_SLOT_BRASS_LANTERN
    JR   Z, .pid_no
.pid_ego:
    LD   A, C
    AND  EGO_ID_MASK
    JR   NZ, .pid_yes
    LD   HL, inv_to_hit
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    JR   NZ, .pid_pos
    LD   HL, inv_to_dam
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    JR   NZ, .pid_pos
    LD   HL, inv_to_ac
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    JR   NZ, .pid_pos
    LD   HL, inv_p1
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    JR   Z, .pid_no
.pid_pos:
    BIT  7, A
    JR   NZ, .pid_no
.pid_yes:
    SCF
    RET
.pid_no:
    OR   A
    RET

_it_add_timer:
    ; (HL) += rng_range(A) + B, capped at 255
    CALL rng_range
    ADD  A, B
    JR   C, .sat
    ADD  A, (HL)
    JR   NC, .ok
.sat:
    LD   A, 0xFF
.ok:
    LD   (HL), A
    RET

_it_add_food:
    LD   HL, (player_data + PL_FOOD_LO)
    ADD  HL, DE
    LD   DE, 4000
    OR   A
    PUSH HL
    SBC  HL, DE
    POP  HL
    JR   C, .ok
    LD   HL, 4000
.ok:
    LD   (player_data + PL_FOOD_LO), HL
    JP   player_update_hunger_state

_it_gain_hstr:
    DB HSTR_PIQ_GAIN_STR, HSTR_PIQ_GAIN_INT, HSTR_PIQ_GAIN_WIS
    DB HSTR_PIQ_GAIN_DEX, HSTR_PIQ_GAIN_CON, HSTR_PIQ_GAIN_CHR

_it_s_sleep:    DB "You fall asleep.", 0
_it_s_drink:    DB "You feel refreshed.", 0
_it_s_learn:    DB "You feel more knowledgeable.", 0
_it_s_salt:     DB "The potion makes you vomit!", 0
_it_s_invuln:   DB "You feel invulnerable.", 0
_it_s_bold:     DB "You feel bold.", 0
_it_s_memories: DB "You feel memories fading.", 0
_it_s_rest_lvl: DB "You feel your life returning.", 0
_it_s_gain_xp:  DB "You feel more experienced.", 0

; Extended food handler (Page 0 slot_lo in A: mushrooms 20..40, Waybread 43..44)
_it_eat_ext:
    CP   ITEM_SLOT_PIECE_OF_ELVISH_WAYBREAD_L6
    JR   Z, .eff_waybread
    CP   ITEM_SLOT_PIECE_OF_ELVISH_WAYBREAD_L20
    JR   Z, .eff_waybread
    SUB  ITEM_SLOT_MUSHROOM_OF_POISON
    RET  C
    CP   21
    RET  NC
    LD   E, A
    LD   D, 0
    LD   HL, _it_mushroom_tbl
    ADD  HL, DE
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    EX   DE, HL
    JP   (HL)

.eff_waybread:
    LD   BC, 0x0408
    CALL roll_dice_bc
    CALL _it_heal_and_report_a
    LD   A, 1
    JP   _it_cure_timers

_it_mushroom_tbl:
    DW _it_m_poison1                ; 20 Mushroom of Poison (1d8 + pois)
    DW _it_m_blind                  ; 21 Mushroom of Blindness
    DW _it_m_fear                   ; 22 Mushroom of Paranoia
    DW _it_m_confuse                ; 23 Mushroom of Confusion
    DW _it_m_halluc                 ; 24 Mushroom of Hallucination
    DW _it_m_cure_poison            ; 25 Mushroom of Cure Poison
    DW _it_m_cure_blind             ; 26 Mushroom of Cure Blindness
    DW _it_m_cure_fear              ; 27 Mushroom of Cure Paranoia
    DW _it_m_cure_conf              ; 28 Mushroom of Cure Confusion
    DW _it_m_weak                   ; 29 Mushroom of Weakness
    DW _it_m_unhealth               ; 30 Mushroom of Unhealth
    DW _it_m_rest_con               ; 31 Mushroom of Restore Constitution
    DW _it_m_first_aid              ; 32 Mushroom of First Aid (1d4 + cure blind)
    DW _it_m_cure_light             ; 33 Mushroom of Minor Cures (2d8 + cure all)
    DW _it_m_cure_serious           ; 34 Mushroom of Light Cures (1d8 + cure blind)
    DW _it_m_rest_all               ; 35 Mushroom of Restoring
    DW _it_m_poison2                ; 36 Hairy Mold of Poison (2d8 + pois)
    DW _it_m_halluc                 ; 37 Hairy Mold of Hallucinations
    DW _it_m_cure_poison            ; 38 Hairy Mold of Cure Poison
    DW _it_m_mold_unhealth          ; 39 Hairy Mold of Unhealth (CON + 10d10 dmg)
    DW _it_m_mold_cure              ; 40 Hairy Mold of Cure Serious Wounds (3d8 + blind|conf)

_it_m_poison1:
    LD   B, 1
    JR   _it_m_pois_n
_it_m_poison2:
    LD   B, 2
_it_m_pois_n:
    LD   C, 8
    CALL roll_dice_bc
    CALL _it_pois_dmg_a
    LD   HL, zp_eff_poison
    LD   A, 10
    LD   B, 10
    CALL _it_add_timer
    LD   A, HSTR_PIQ_TERRIBLE
    JP   msg_print_huff
_it_m_blind:
    LD   HL, zp_eff_blind
    LD   A, 100
    LD   B, 100
    CALL _it_add_timer
    LD   A, HSTR_PIQ_CANT_SEE
    JP   msg_print_huff
_it_m_fear:
    LD   HL, eff_fear_timer
    LD   A, 10
    LD   B, 11
    CALL _it_add_timer
    LD   HL, _it_s_afraid
    JP   msg_print_str
_it_m_confuse:
    LD   HL, zp_eff_confuse
    LD   A, 15
    LD   B, 10
    CALL _it_add_timer
    LD   A, HSTR_PIQ_DIZZY
    JP   msg_print_huff
_it_m_halluc:
    LD   HL, zp_eff_confuse
    LD   A, 15
    LD   B, 15
    CALL _it_add_timer
    LD   HL, _it_s_halluc
    JP   msg_print_str
_it_m_cure_poison:
    LD   A, 1
    JR   _it_cure_timers
_it_m_cure_blind:
    LD   A, 2
    JR   _it_cure_timers
_it_m_cure_conf:
    LD   A, 4
_it_cure_timers:
    LD   HL, zp_eff_poison
    LD   B, 3
.lp:
    RRCA
    JR   NC, .nx
    LD   C, A
    LD   A, (HL)
    CP   2
    JR   C, .nx_a
    LD   (HL), 1
.nx_a:
    LD   A, C
.nx:
    INC  HL
    DJNZ .lp
    RET
_it_m_cure_fear:
    LD   A, (eff_fear_timer)
    OR   A
    RET  Z
    XOR  A
    LD   (eff_fear_timer), A
    LD   A, HSTR_EFF_FEAR_END
    JP   msg_print_huff
_it_m_mold_unhealth:
    CALL _it_m_unhealth
    LD   BC, 0x0A0A
    CALL roll_dice_bc
    JP   _it_pois_dmg_a
_it_m_weak:
    LD   A, (player_sust_mask)
    AND  SUST_STR
    JR   NZ, _it_m_sust
    LD   A, STAT_STR
    JR   _it_m_drain_a
_it_m_unhealth:
    LD   A, (player_sust_mask)
    AND  SUST_CON
    JR   NZ, _it_m_sust
    LD   A, STAT_CON
_it_m_drain_a:
    PUSH AF
    CALL player_drain_stat_a
    JR   C, .drained
    POP  AF
    JR   _it_m_sust
.drained:
    POP  AF
    CALL tramp_modal_recalc_equipment
    LD   HL, _it_s_weak
    JP   msg_print_str
_it_m_sust:
    LD   A, HSTR_PIQ_NOTHING
    JP   msg_print_huff
_it_m_rest_con:
    LD   A, STAT_CON
    JR   _it_m_rest_a
_it_m_rest_all:
    LD   A, 0xFF
_it_m_rest_a:
    CALL player_restore_stat_a
    CALL tramp_modal_recalc_equipment
    LD   A, HSTR_PIQ_RESTORED
    JP   msg_print_huff
_it_m_first_aid:
    LD   BC, 0x0104
    CALL roll_dice_bc
    CALL _it_heal_and_report_a
    LD   A, 2
    JP   _it_cure_timers
_it_m_cure_light:
    LD   BC, 0x0208
    CALL roll_dice_bc
    CALL _it_heal_and_report_a
    LD   A, 7
    JP   _it_cure_timers
_it_m_cure_serious:
    LD   BC, 0x0108
    CALL roll_dice_bc
    CALL _it_heal_and_report_a
    LD   A, 2
    JP   _it_cure_timers
_it_m_mold_cure:
    LD   BC, 0x0308
    CALL roll_dice_bc
    CALL _it_heal_and_report_a
    LD   A, 6
    JP   _it_cure_timers

_it_heal_and_report_a:
    LD   B, A
    LD   HL, (player_data + PL_HP_LO)
    LD   DE, (player_data + PL_MHP_LO)
    OR   A
    SBC  HL, DE
    RET  NC
    LD   L, B
    LD   H, 0
    PUSH BC
    CALL eff_heal
    POP  AF
    CP   5
    LD   B, HSTR_PIQ_LITTLE_BETTER
    JR   C, .msg
    CP   15
    LD   B, HSTR_EFF_POISON_END
    JR   C, .msg
    CP   35
    LD   B, HSTR_PIQ_MUCH_BETTER
    JR   C, .msg
    LD   B, HSTR_PIQ_VERY_GOOD
.msg:
    LD   A, B
    JP   msg_print_huff

_it_pois_dmg_a:
    LD   L, A
    LD   H, 0
    LD   A, DEATH_POISON
    JP   turn_apply_one_damage

_it_s_afraid:   DB "You tremble with fear.", 0
_it_s_halluc:   DB "Everything looks strange!", 0
_it_s_weak:     DB "You feel weaker.", 0
_it_s_blast:    DB "There is a searing blast of light!", 0
_it_s_quake:    DB "The earth trembles.", 0
_it_da_walls:   DB TILE_WALL_H, TILE_MAGMA, TILE_QUARTZ

; +18: _it_world_cold — Cold Word of Destruction (A=0) / Earthquake (A=1) spilled from OVL_SPELL_EFF
_it_world_cold:
    OR   A
    JP   NZ, _it_earthquake

; Word of Destruction (6502 player_destroy_area.s)
_it_dest_area:
    LD   A, (abi_player_dlvl)
    OR   A
    JP   Z, .msg_blind

    ; Delete all monsters (including Balrog!) with oct_dist < 16
    LD   C, 0
.mlp:
    LD   A, C
    CALL monster_get_ptr
    JR   C, .mnxt
    PUSH HL
    INC  HL
    INC  HL
    LD   A, (HL)
    CP   EMPTY_SLOT
    POP  HL
    JR   Z, .mnxt
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    CALL _it_oct_dist_de_player
    CP   16
    JR   NC, .mnxt
    LD   A, C
    CALL monster_remove
.mnxt:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .mlp

    ; Delete floor items with oct_dist < 16
    LD   C, 0
.flp:
    LD   B, 0
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .fnxt
    LD   HL, fi_y
    ADD  HL, BC
    LD   D, (HL)
    LD   HL, fi_x
    ADD  HL, BC
    LD   E, (HL)
    CALL _it_oct_dist_de_player
    CP   16
    JR   NC, .fnxt
    PUSH BC
    LD   A, C
    CALL floor_item_remove
    POP  BC
.fnxt:
    INC  C
    LD   A, C
    CP   MAX_FLOOR_ITEMS
    JR   C, .flp

    ; Delete glyphs with oct_dist < 16
    LD   C, 0
.glp:
    LD   B, 0
    LD   HL, glyph_active
    ADD  HL, BC
    LD   A, (HL)
    OR   A
    JR   Z, .gnxt
    LD   HL, glyph_y
    ADD  HL, BC
    LD   D, (HL)
    LD   HL, glyph_x
    ADD  HL, BC
    LD   E, (HL)
    CALL _it_oct_dist_de_player
    CP   16
    JR   NC, .gnxt
    LD   HL, glyph_active
    ADD  HL, BC
    LD   (HL), 0
.gnxt:
    INC  C
    LD   A, C
    CP   MAX_GLYPHS
    JR   C, .glp

    ; Delete traps downward with oct_dist < 16 (including player square)
    LD   A, (trap_count)
    OR   A
    JR   Z, .traps_done
    LD   C, A
.trlp:
    DEC  C
    LD   B, 0
    LD   HL, trap_y
    ADD  HL, BC
    LD   D, (HL)
    LD   HL, trap_x
    ADD  HL, BC
    LD   E, (HL)
    CALL _it_oct_dist_de_player
    CP   16
    JR   NC, .tr_nx
    PUSH BC
    LD   B, D
    LD   C, E
    CALL _it_remove_trap_at
    POP  BC
.tr_nx:
    LD   A, C
    OR   A
    JR   NZ, .trlp
.traps_done:

    ; Sweep [-15..+15] x [-15..+15]
    LD   E, -15
.ylp:
    LD   D, -15
.xlp:
    LD   A, (abi_player_y)
    ADD  A, E
    CP   MAP_ROWS
    JR   NC, .tnxt
    LD   B, A
    LD   A, (abi_player_x)
    ADD  A, D
    CP   MAP_COLS
    JR   NC, .tnxt
    LD   C, A

    PUSH DE
    LD   A, E
    OR   D
    JR   NZ, .not_plr
    XOR  A                      ; force player tile to TILE_FLOOR (typ = 0)
    JR   .write_t
.not_plr:
    LD   A, C
    OR   A
    JR   Z, .tpop
    CP   MAP_COLS - 1
    JR   NC, .tpop
    LD   A, B
    OR   A
    JR   Z, .tpop
    CP   MAP_ROWS - 1
    JR   NC, .tpop

    LD   D, B
    LD   E, C
    CALL _it_oct_dist_de_player
    CP   16
    JR   NC, .tpop
    CP   13
    LD   A, 6
    JR   C, .roll_t
    LD   A, 9
.roll_t:
    CALL rng_range
    INC  A                      ; 1..6 or 1..9
    CP   4
    JR   NC, .wall_t
    XOR  A                      ; 1..3 -> TILE_FLOOR
    JR   .write_t
.wall_t:
    SUB  4
    CP   3
    JR   C, .wk
    SUB  3
.wk:
    LD   E, A
    LD   D, 0
    LD   HL, _it_da_walls
    ADD  HL, DE
    LD   A, (HL)
.write_t:
    LD   D, A
    CALL map_get_tile
    JR   C, .tpop
    LD   E, A
    AND  FLAG_VISITED
    OR   D
    CP   E
    JR   Z, .tpop
    CALL map_set_tile
    CALL _it_clear_door_state_at
.tpop:
    POP  DE
.tnxt:
    INC  D
    LD   A, D
    CP   16
    JR   NZ, .xlp
    INC  E
    LD   A, E
    CP   16
    JR   NZ, .ylp

    ; Darken intersecting room_lit[] entries & reset room cache
    LD   A, (abi_player_x)
    SUB  15
    JR   NC, .bx0
    XOR  A
.bx0:
    LD   (bss_scratch + 0), A
    LD   A, (abi_player_x)
    ADD  A, 15
    CP   MAP_COLS - 1
    JR   C, .bx1
    LD   A, MAP_COLS - 1
.bx1:
    LD   (bss_scratch + 1), A
    LD   A, (abi_player_y)
    SUB  15
    JR   NC, .by0
    XOR  A
.by0:
    LD   (bss_scratch + 2), A
    LD   A, (abi_player_y)
    ADD  A, 15
    CP   MAP_ROWS - 1
    JR   C, .by1
    LD   A, MAP_ROWS - 1
.by1:
    LD   (bss_scratch + 3), A

    LD   A, (room_count)
    OR   A
    JR   Z, .dk_done
    LD   B, A
    LD   C, 0
.dk_lp:
    LD   E, C
    LD   D, 0
    LD   HL, room_x
    ADD  HL, DE
    LD   A, (bss_scratch + 1)
    CP   (HL)
    JR   C, .dk_nx
    LD   A, (HL)
    LD   HL, room_w
    ADD  HL, DE
    ADD  A, (HL)
    DEC  A
    LD   HL, bss_scratch + 0
    CP   (HL)
    JR   C, .dk_nx
    LD   HL, room_y
    ADD  HL, DE
    LD   A, (bss_scratch + 3)
    CP   (HL)
    JR   C, .dk_nx
    LD   A, (HL)
    LD   HL, room_h
    ADD  HL, DE
    ADD  A, (HL)
    DEC  A
    LD   HL, bss_scratch + 2
    CP   (HL)
    JR   C, .dk_nx
    LD   HL, room_lit
    ADD  HL, DE
    LD   (HL), 0
.dk_nx:
    INC  C
    DJNZ .dk_lp
.dk_done:
    LD   A, 0xFF
    LD   (vis_cached_room_idx), A
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   (turn_scene_dirty), A
    LD   HL, zp_dirty_count
    INC  (HL)

.msg_blind:
    LD   HL, _it_s_blast
    CALL msg_print_str
    LD   A, 10
    CALL rng_range
    ADD  A, 11
    LD   HL, zp_eff_blind
    ADD  A, (HL)
    JR   NC, .bl_ok
    LD   A, 255
.bl_ok:
    LD   (HL), A
    SCF
    RET

; Earthquake (6502 player_magic_earthquake.s)
_it_earthquake:
    LD   HL, _it_s_quake
    CALL msg_print_str
    XOR  A
    LD   (bss_scratch + 0), A   ; eq_changed

    LD   E, -8
.ylp:
    LD   D, -8
.xlp:
    LD   A, E
    OR   D
    JP   Z, .nxt
    LD   A, (abi_player_y)
    ADD  A, E
    CP   MAP_ROWS
    JP   NC, .nxt
    LD   B, A
    LD   A, (abi_player_x)
    ADD  A, D
    CP   MAP_COLS
    JP   NC, .nxt
    LD   C, A

    PUSH DE
    LD   A, 8
    CALL rng_range
    OR   A
    JP   NZ, .pop_nxt

.rfi_lp:
    CALL _it_find_fi_at
    JR   NC, .rfi_done
    PUSH BC
    CALL floor_item_remove
    POP  BC
    LD   A, 1
    LD   (bss_scratch + 0), A
    JR   .rfi_lp
.rfi_done:

    XOR  A
    LD   (bss_scratch + 1), A   ; eq_mon_alive
    CALL monster_find_at
    JR   NC, .after_mon
    LD   D, A                   ; D = slot
    PUSH DE
    CALL monster_get_ptr        ; HL = mon_ptr
    POP  DE
    PUSH HL
    INC  HL
    INC  HL
    LD   A, (HL)                ; cr_type
    LD   E, A
    PUSH DE                     ; [D=slot, E=cr_type]
    LD   D, 0
    LD   HL, cr_mflags
    ADD  HL, DE
    BIT  0, (HL)                ; CF_ATTACK_ONLY
    JR   Z, .roll4d8
    LD   DE, 3000
    JR   .eq_dmg
.roll4d8:
    PUSH BC
    LD   B, 4
    LD   C, 8
    CALL roll_dice_bc
    EX   DE, HL
    POP  BC
.eq_dmg:
    POP  AF                     ; A = slot (from D)
    POP  HL                     ; HL = mon_ptr
    PUSH BC
    LD   B, A                   ; B = slot
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
    JR   C, .eq_kill
    OR   A
    JR   NZ, .eq_surv
    DEC  HL
    LD   A, (HL)
    OR   A
    JR   Z, .eq_kill
.eq_surv:
    LD   A, 1
    LD   (bss_scratch + 1), A
    JR   .eq_mdone
.eq_kill:
    LD   A, B
    CALL tramp_modal_kill_monster
.eq_mdone:
    POP  BC
    LD   A, 1
    LD   (bss_scratch + 0), A

.after_mon:
    LD   A, C
    OR   A
    JR   Z, .pop_nxt
    CP   MAP_COLS - 1
    JR   NC, .pop_nxt
    LD   A, B
    OR   A
    JR   Z, .pop_nxt
    CP   MAP_ROWS - 1
    JR   NC, .pop_nxt

    CALL map_get_tile
    JR   C, .pop_nxt
    LD   H, A
    AND  TILE_TYPE_MASK
    OR   A
    JR   Z, .floor_to_wall
    CP   TILE_WALL_H
    JR   C, .pop_nxt
    CP   TILE_DOOR_OPEN
    JR   C, .wall_to_floor
    CP   TILE_MAGMA
    JR   Z, .wall_to_floor
    CP   TILE_QUARTZ
    JR   Z, .wall_to_floor
    CP   TILE_SECRET
    JR   NZ, .pop_nxt

.wall_to_floor:
    LD   A, H
    AND  FLAG_VISITED
    LD   L, A
    LD   A, (bss_scratch + 1)
    OR   A
    LD   A, L
    JR   Z, .wf_wr
    OR   FLAG_OCCUPIED
.wf_wr:
    CALL map_set_tile
    LD   A, 1
    LD   (bss_scratch + 0), A
    JR   .pop_nxt

.floor_to_wall:
    LD   A, 10
    CALL rng_range
    CP   6
    LD   L, TILE_QUARTZ
    JR   C, .fw_kind
    CP   9
    LD   L, TILE_MAGMA
    JR   C, .fw_kind
    LD   L, TILE_WALL_H
.fw_kind:
    LD   A, H
    AND  FLAG_VISITED | FLAG_LIT | FLAG_OCCUPIED
    OR   L
    CALL map_set_tile
    LD   A, 1
    LD   (bss_scratch + 0), A

.pop_nxt:
    POP  DE
.nxt:
    INC  D
    LD   A, D
    CP   9
    JP   NZ, .xlp
    INC  E
    LD   A, E
    CP   9
    JP   NZ, .ylp

    LD   A, (bss_scratch + 0)
    OR   A
    JR   Z, .eq_done
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   (turn_scene_dirty), A
    LD   HL, zp_dirty_count
    INC  (HL)
.eq_done:
    SCF
    RET

_it_oct_dist_de_player:
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
    JR   NC, .ay_max
    LD   D, E
    LD   E, A
    LD   A, D
.ay_max:
    SRL  E
    ADD  A, E
    RET

_it_find_fi_at:
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

_it_remove_trap_at:
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

_it_clear_door_state_at:
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

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end
    SAVEBIN "ovl_items.ovl", ovl_start, ovl_end - ovl_start
