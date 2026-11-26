; turn.asm — Resident Z80 Turn Engine, Regeneration, Poison/Effects, Hunger & Light (M3)
;
; Implements docs/TURN_RENDER_CONTRACT.md (TRN-009, TRN-010, TRN-011, TRN-014, TRN-015).
; Exports: turn_post_action, eff_heal, turn_apply_one_damage
; Preserves IX and IY across every public entry point.

    EXPORT turn_post_action
    EXPORT eff_heal
    EXPORT turn_apply_one_damage
    EXPORT player_update_hunger_state

poison_damage_tbl:
    DB   4, 3, 3, 2, 1, 0x82, 0x82, 0x82, 0x83

_turn_hng_thresh:
    DW   150, 50, 10

_str_bless_end:
    DB   "T", 0x07, "prayer has expired.", 0

eff_heal:
    PUSH DE
    EX   DE, HL
    LD   HL, (player_data + PL_HP_LO)
    ADD  HL, DE
    JR   NC, .nw
    LD   HL, 0xFFFF
.nw:
    LD   DE, (player_data + PL_MHP_LO)
    PUSH HL
    OR   A
    SBC  HL, DE
    POP  HL
    JR   C, .st
    EX   DE, HL
    XOR  A
    LD   (regen_frac_lo), A
    LD   (zp_regen_frac), A
.st:
    POP  DE
_turn_store_hp:
    LD   (player_data + PL_HP_LO), HL
    LD   (abi_player_hp), HL
    JP   status_mark_dirty

turn_apply_one_damage:
    OR   A
    JR   Z, .ks
    LD   (zp_death_source), A
    LD   (abi_death_source), A
    LD   (df_death_source), A
.ks:
    CALL _turn_inc_disturb
    EX   DE, HL
    LD   HL, (player_data + PL_HP_LO)
    OR   A
    SBC  HL, DE
    JR   C, .dead
    LD   A, H
    OR   L
    JR   Z, .dead
    CALL _turn_store_hp
    OR   A
    RET
.dead:
    LD   HL, zp_game_flags
    SET  0, (HL)
    LD   HL, abi_game_flags
    SET  0, (HL)
    LD   HL, 0
    CALL _turn_store_hp
    SCF
    RET

turn_post_action:
    XOR  A
    LD   (turn_scene_dirty), A

    LD   A, (abi_game_flags)
    RRA
    JR   C, .step_f

    CALL _turn_tick_regen
    CALL _turn_tick_effects
    LD   HL, abi_game_flags
    BIT  0, (HL)
    JR   NZ, .step_f
    CALL _turn_tick_mana

    ; Pseudo-ID cadence: every 16 turns if not confused, 1 / (10 + 750/(5+lvl))
    LD   A, (abi_turn)
    AND  0x0F
    CP   0x0F
    JR   NZ, .no_pid
    LD   A, (zp_eff_confuse)
    OR   A
    JR   NZ, .no_pid
    LD   A, (player_data + PL_LEVEL)
    ADD  A, 5
    LD   C, A
    LD   HL, 750
    CALL div_hl_c
    LD   A, L
    ADD  A, 10
    CALL rng_range
    OR   A
    CALL Z, tramp_items_pseudo_id
.no_pid:

    ; MON-039: 1-in-160 chance to spawn an ambient wanderer beyond sight
    LD   A, CAT_MALLOC_CHANCE
    CALL rng_range
    OR   A
    CALL Z, tramp_modal_place_wanderer

    ; Monster AI tick when monsters are present
    LD   A, (abi_mon_count)
    OR   A
    CALL NZ, monster_ai_tick

.step_f:
    LD   HL, (abi_turn)
    INC  HL
    LD   (abi_turn), HL
    LD   (zp_turn_lo), HL

    LD   A, (abi_game_flags)
    RRA
    JR   C, .fold_dirty

    LD   A, (player_pflags2)
    AND  PFLAG2_TELEPORT
    JR   Z, .fold_dirty
    LD   A, 100
    CALL rng_range
    OR   A
    JR   NZ, .fold_dirty
    XOR  A
    CALL tramp_items_eff_teleport
    LD   A, 1
    LD   (turn_scene_dirty), A

.fold_dirty:
    LD   A, (zp_dirty_count)
    LD   HL, turn_scene_dirty
    OR   (HL)
    LD   (HL), A
    XOR  A
    LD   (zp_dirty_count), A

    CALL status_mark_dirty
    CALL player_sync_to_abi

    LD   A, (abi_game_flags)
    RRA
    RET

_turn_tick_regen:
    ; B flags: bit0=resting, bit1=regen
    LD   B, 0
    LD   A, (auto_rest_active)
    OR   A
    JR   Z, .nr
    SET  0, B
.nr:
    CALL _turn_is_regen_active
    JR   Z, .chk_hp
    SET  1, B

.chk_hp:
    PUSH BC                     ; save B flags cleanly across DE/HL checks
    LD   HL, (player_data + PL_HP_LO)
    LD   DE, (player_data + PL_MHP_LO)
    OR   A
    SBC  HL, DE
    JR   C, .try_hp
    XOR  A
    LD   (regen_frac_lo), A
    LD   (zp_regen_frac), A
    JR   .pop_hp_ret
.try_hp:
    LD   A, (zp_eff_poison)
    OR   A
    JR   NZ, .pop_hp_ret

    ; When starving (food == 0), rate = 0 and only REGEN_HPBASE accumulates.
    LD   HL, (player_data + PL_FOOD_LO)
    LD   A, H
    OR   L
    JR   NZ, .calc_rate
    LD   E, 0                   ; E:HL = 0:0000
    JR   .add_base
.calc_rate:
    POP  BC                     ; B = flags, DE STILL holds MHP!
    PUSH BC
    LD   A, (player_data + PL_HUNGER)
    LD   L, REGEN_NORMAL
    CP   HUNGER_WEAK
    JR   C, .rk
    LD   L, REGEN_WEAK
    JR   Z, .rk
    LD   L, REGEN_FAINT
.rk:
    LD   H, 0
    BIT  0, B
    JR   Z, .nrd
    ADD  HL, HL
.nrd:
    BIT  1, B
    JR   Z, .nrg
    ADD  HL, HL
.nrg:
    ; 24-bit E:HL = DE (MHP) * HL (rate) using IX (preserves IX)
    PUSH IX
    LD   B, H
    LD   C, L
    LD   IX, 0
    LD   HL, 0x0010             ; H = acc bits 16..23, L = loop count 16
.m24:
    ADD  IX, IX
    RL   H
    SLA  C
    RL   B
    JR   NC, .ms
    ADD  IX, DE
    JR   NC, .ms
    INC  H
.ms:
    DEC  L
    JR   NZ, .m24
    LD   E, H
    PUSH IX
    POP  HL
    POP  IX

.add_base:
    LD   BC, REGEN_HPBASE
    ADD  HL, BC
    JR   NC, .nb
    INC  E
.nb:
    LD   A, (regen_frac_lo)
    ADD  A, L
    LD   (regen_frac_lo), A
    LD   A, (zp_regen_frac)
    ADC  A, H
    LD   (zp_regen_frac), A
    LD   A, E
    ADC  A, 0
    JR   Z, .pop_hp_ret
    LD   L, A
    LD   H, 0
    CALL eff_heal

.pop_hp_ret:
    POP  BC
    RET

_turn_tick_mana:
    LD   A, (player_data + PL_SPELL_TYPE)
    OR   A
    RET  Z
    LD   HL, player_data + PL_MANA
    LD   A, (player_data + PL_MAX_MANA)
    CP   (HL)
    RET  Z
    RET  C

    CALL _turn_is_regen_active
    JR   NZ, .inc_mp
    LD   A, (abi_turn)
    RRA
    RET  C
.inc_mp:
    INC  (HL)
    LD   A, (HL)
    LD   (abi_player_mp), A
    RET

_turn_tick_effects:
    ; Walk HL sequentially across zp_eff_poison (0x6E8D) .. zp_eff_word_recall (0x6E9B)
    ; 1. zp_eff_poison: decrement first; damage only if remaining > 0 (TRN-010)
    LD   HL, zp_eff_poison
    LD   A, (HL)
    OR   A
    JR   Z, .blind
    DEC  (HL)
    JR   NZ, .p_dmg
    PUSH HL
    LD   A, HSTR_EFF_POISON_END
    CALL msg_print_huff
    POP  HL
    JR   .blind
.p_dmg:
    PUSH HL
    LD   A, (player_data + PL_CON_CUR)
    CALL player_con_hp_adj
    ADD  A, 4
    LD   HL, poison_damage_tbl
    CALL _los_idx_hl_a
    BIT  7, A
    JR   Z, .ap
    AND  0x7F
    LD   C, A
    LD   HL, (abi_turn)
    CALL div_hl_c
    OR   A
    JR   NZ, .dp                ; OR A cleared CF=0
    LD   A, 1
.ap:
    LD   L, A
    LD   H, 0
    LD   A, DEATH_POISON
    CALL turn_apply_one_damage
.dp:
    POP  HL

.blind:
    INC  HL                     ; zp_eff_blind
    LD   A, (player_curse_flags)
    AND  ITR3_BLIND
    JR   Z, .blind_norm
    LD   A, (HL)
    OR   A
    JR   NZ, .blind_cursed_dec
    INC  (HL)
    LD   A, 1
    LD   (vis_room_revealed), A
    CALL _turn_inc_disturb
    PUSH HL
    LD   HL, zp_dirty_count
    INC  (HL)
    POP  HL
    JR   .conf
.blind_cursed_dec:
    CP   2
    JR   C, .conf
.blind_norm:
    LD   A, HSTR_EFF_BLIND_END
    CALL _turn_dec_hstr
    JR   NC, .conf
    LD   A, 1
    LD   (vis_room_revealed), A
    PUSH HL
    LD   HL, zp_dirty_count
    INC  (HL)
    POP  HL
.conf:
    INC  HL                     ; zp_eff_confuse
    LD   A, HSTR_EFF_CONFUSE_END
    CALL _turn_dec_hstr

    INC  HL                     ; zp_eff_paralyze
    LD   A, HSTR_EFF_PARALYZE_END
    CALL _turn_dec_hstr

    ; Tick Fear before Haste/Slow and Heroism so ITR3_TIMID checks pre-expiry hero (6502 turn.s)
    PUSH HL
    LD   HL, eff_fear_timer
    LD   A, (player_curse_flags)
    AND  ITR3_TIMID
    JR   Z, .fear_norm
    LD   A, (zp_eff_hero)
    OR   A
    JR   NZ, .fear_norm
    LD   A, (HL)
    OR   A
    JR   NZ, .fear_cursed_dec
    INC  (HL)
    CALL _turn_inc_disturb
    JR   .fear_done
.fear_cursed_dec:
    CP   2
    JR   C, .fear_done
.fear_norm:
    LD   A, HSTR_EFF_FEAR_END
    CALL _turn_dec_hstr
.fear_done:
    POP  HL

.spd:
    INC  HL                     ; zp_eff_speed (signed)
    LD   A, (HL)
    OR   A
    JR   Z, .blk
    BIT  7, A
    JR   NZ, .slw
    LD   A, HSTR_EFF_HASTE_END
    CALL _turn_dec_hstr
    JR   .blk
.slw:
    INC  (HL)
    JR   NZ, .blk
    PUSH HL
    LD   A, HSTR_EFF_SLOW_END
    CALL msg_print_huff
    POP  HL

.blk:
    ; HL+1 is zp_eff_protect..zp_eff_see_inv (9 bytes), with +4=bless, +5=hero
    INC  HL
    LD   B, 9
    LD   C, 0
.blp:
    LD   A, (HL)
    OR   A
    JR   Z, .bnx
    DEC  (HL)
    JR   NZ, .bnx
    LD   A, C
    CP   4                      ; zp_eff_bless expiry
    JR   NZ, .chk_hr
    PUSH HL
    PUSH BC
    LD   HL, _str_bless_end
    CALL _gl_msg_tok
    JR   .exp_pop
.chk_hr:
    CP   5                      ; zp_eff_hero expiry (-10 MHP, clamp HP)
    JR   NZ, .bnx
    PUSH HL
    PUSH BC
    LD   HL, (player_data + PL_MHP_LO)
    LD   DE, 10
    OR   A
    SBC  HL, DE
    JR   NC, .hr_ok
    LD   HL, 1
.hr_ok:
    LD   (player_data + PL_MHP_LO), HL
    LD   (abi_player_mhp), HL
    LD   HL, 0
    CALL eff_heal
    CALL _turn_inc_disturb
.exp_pop:
    POP  BC
    POP  HL
.bnx:
    INC  HL
    INC  C
    DJNZ .blp

    ; HL is now at zp_eff_word_recall
    LD   A, (HL)
    OR   A
    JR   Z, .invuln
    DEC  (HL)
    CALL Z, _turn_trigger_word_recall

.invuln:

    ; Invulnerability timer (TRN-014 disturb on expiry)
    LD   HL, eff_invuln_timer
    LD   A, (HL)
    OR   A
    JR   Z, .no_invuln
    DEC  (HL)
    CALL Z, _turn_inc_disturb
.no_invuln:

    ; Detect Monsters timer (no disturb on expiry per TRN-014)
    LD   HL, eff_detect_timer
    LD   A, (HL)
    OR   A
    JR   Z, .no_detect
    DEC  (HL)
    JR   NZ, .no_detect
    LD   A, 1
    LD   (muv_clear_detected), A
    LD   (vis_room_revealed), A
    CALL monster_update_visibility_all
    LD   HL, zp_dirty_count
    INC  (HL)
.no_detect:

    CALL _turn_tick_hunger
    RET  C
    JP   _turn_tick_light

_turn_is_regen_active:
    LD   A, (player_pflags2)
    LD   D, A
    AND  PFLAG2_REGEN
    RET  NZ
    LD   A, (zp_eff_regen)
    OR   A
    RET

_turn_dec_hstr:
    LD   B, A
    LD   A, (HL)
    OR   A
    RET  Z
    DEC  (HL)
    RET  NZ
    LD   A, B
    PUSH HL
    CALL msg_print_huff
    POP  HL
    SCF
    RET

_turn_trigger_word_recall:
    LD   A, (abi_player_dlvl)
    OR   A
    JR   NZ, .tt
    LD   A, (player_data + PL_MAX_DLVL)
    OR   A
    RET  Z                      ; Never been to dungeon -> fizzle
    PUSH AF
    LD   HL, (abi_player_x)
    LD   C, L
    LD   B, H
    CALL _mc_tile_clr_occ
    POP  AF
    LD   (abi_player_dlvl), A
    LD   (player_data + PL_DLEVEL), A
    XOR  A
    CALL _gl_enter_dungeon
    JR   .dn
.tt:
    LD   HL, (abi_player_x)
    LD   C, L
    LD   B, H
    CALL _mc_tile_clr_occ
    CALL _gl_enter_town
.dn:
    CALL los_update_visibility
    CALL monster_update_visibility_all
    CALL game_loop_redraw_fresh
    CALL msg_clear
    LD   A, HSTR_RECALL_ARRIVE
    CALL msg_print_huff
_turn_disturb_dirty:
    CALL _turn_inc_disturb
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

_turn_tick_hunger:
    LD   HL, (player_data + PL_FOOD_LO)
    LD   A, H
    OR   L
    JR   Z, .starve_chk         ; Already 0 at entry -> starve after state update
    LD   A, (player_pflags2)
    BIT  0, A                   ; PFLAG2_SLOW_DIGEST
    JR   Z, .sub1
    LD   A, (abi_turn)
    RRA
    JR   C, .skip_starve        ; Odd turn with slow digest -> no dec, no starve
.sub1:
    DEC  HL
    LD   (player_data + PL_FOOD_LO), HL
.skip_starve:
    LD   A, 1                   ; suppress starvation damage on decrement / 1->0 turn
    JR   .do_hs
.starve_chk:
    XOR  A                      ; food was already 0 -> take starvation damage
.do_hs:
    PUSH AF
    CALL player_update_hunger_state
    LD   A, B
    CP   C
    JR   NC, .chk_starve
    CALL _turn_inc_disturb
    CALL sound_bell
.chk_starve:
    POP  AF
    OR   A
    RET  NZ
    LD   HL, 1
    LD   A, DEATH_STARVE
    JP   turn_apply_one_damage

player_update_hunger_state:
    LD   DE, (player_data + PL_FOOD_LO)
    LD   HL, _turn_hng_thresh
    LD   BC, 0x0300             ; B = 3, C = state (0..3)
.hlp:
    LD   A, E
    SUB  (HL)
    INC  HL
    LD   A, D
    SBC  A, (HL)
    INC  HL
    JR   NC, .gh
    INC  C
    DJNZ .hlp
.gh:
    LD   A, (player_data + PL_HUNGER)
    LD   B, A
    LD   A, C
    LD   (player_data + PL_HUNGER), A
    LD   (zp_hunger_state), A
    LD   (abi_hunger_state), A
    RET

_turn_tick_light:
    LD   A, (inv_item_id + EQUIP_LIGHT)
    INC  A
    RET  Z
    LD   HL, inv_p1 + EQUIP_LIGHT
    LD   A, (HL)
    OR   A
    JR   NZ, .tf
.cr:
    XOR  A
    LD   (player_data + PL_LIGHT_RAD), A
    LD   (zp_light_radius), A
    LD   (abi_light_rad), A
    RET
.tf:
    LD   A, (light_tick_counter)
    INC  A
    CP   30
    JR   C, .sv
    XOR  A
    LD   (light_tick_counter), A
    DEC  (HL)
    LD   A, (HL)
    CP   2
    JR   NZ, .co
    LD   A, HSTR_TTL_DIM
    JP   msg_print_huff
.co:
    OR   A
    RET  NZ
    LD   A, HSTR_TTL_OUT
    CALL msg_print_huff
    CALL .cr
    LD   HL, zp_dirty_count
    INC  (HL)
    RET
.sv:
    LD   (light_tick_counter), A
    RET

_turn_inc_disturb:
    LD   A, (zp_disturb)
    INC  A
    RET  Z
    LD   (zp_disturb), A
    RET
