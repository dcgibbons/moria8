; ============================================================================
; ovl_modal.asm — Equipment Recalc, Run Init, Digging, Weapon Swap & Direction
;                 (OVL_MODAL = 9, DAT slot 8)
; ============================================================================
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0 : JP ovl_modal_recalc_equipment  () -> updates pflags/wield/stats/combat
;   +3 : JP ovl_modal_run_init          (A = dir 0..7) -> CF=1 valid, CF=0 blocked
;   +6 : JP ovl_modal_calc_dig          () -> A = digging power (0..255)
;   +9 : JP ovl_modal_exchange_weapon   () -> CF=1 swapped, CF=0 refused/empty
;   +12: JP ovl_modal_direction_prompt  () -> CF=1 A=D=dir + df_target_x/y, CF=0 cancel
; ============================================================================
; ABI / Contract Invariants:
;   - Preserves IX, IY on every public entry vector.
;   - Zero cross-overlay direct calls (only resident core/* symbols via main_exp.inc).
;   - Pure 0xNN hex syntax (sjasmplus v1.24.0, DEVICE NOSLOT64K).
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
    JP   ovl_modal_recalc_equipment ; +0
    JP   ovl_modal_run_init         ; +3
    JP   ovl_modal_calc_dig         ; +6
    JP   ovl_modal_exchange_weapon  ; +9
    JP   ovl_modal_direction_prompt ; +12
    JP   ovl_modal_player_attack    ; +15 (VEC_5)
    JP   ovl_modal_kill_monster     ; +18 (VEC_6)
    JP   ovl_modal_populate_town    ; +21 (VEC_7)
    JP   ovl_modal_populate_dungeon ; +24 (VEC_8)
    JP   ovl_modal_place_wanderer   ; +27 (VEC_9)
    JP   ovl_modal_award_xp         ; +30 (VEC_10)
    JP   ovl_modal_run_area_affect  ; +33 (VEC_11)

; ============================================================================
; Overlay-local transient scratch (cleared/reloaded on overlay swap)
; ============================================================================
ovl_modal_old_curse:    DB 0
ovl_modal_f0:           DB 0
ovl_modal_f1:           DB 0
ovl_modal_f2:           DB 0
ovl_modal_f3:           DB 0
ovl_modal_cat_p1:       DB 0
ovl_modal_dig_acc:      DB 0
ovl_modal_run_dir_tmp:  DB 0
ovl_modal_run_cyc:      DB 0
ovl_modal_run_px:       DB 0
ovl_modal_run_py:       DB 0
_om_r_tx:               DB 0
_om_r_ty:               DB 0
_om_r_t0x:              DB 0
_om_r_t0y:              DB 0
_om_r_scan:             DB 0
_om_r_end:              DB 0
_om_r_dira:             DB 0
_om_r_dirb:             DB 0
_om_r_check:            DB 0
_om_r_found:            DB 0
_om_r_bits:             DB 0

; UMoria cycle[] and chome[] translated to Moria8 directions (0..7),
; mirroring core/6502/player_run.s (home +- 2 is always within 0..11).
ovl_modal_run_cycle:
    DB   7, 3, 5, 0, 4, 2, 6, 1, 7, 3, 5, 0
ovl_modal_run_home:
    DB   3, 7, 5, 9, 4, 2, 6, 8

; Sustain lookup table matching player_pflags_cold.s / ITEM.CAT p1 encoding:
; 0 -> SUST_ALL, 1..6 -> STR, INT, WIS, CON, DEX, CHR
ovl_modal_sust_by_p1:
    DB   SUST_ALL, SUST_STR, SUST_INT, SUST_WIS, SUST_CON, SUST_DEX, SUST_CHR

; Sustain lookup table for Page 1 rings 78..83:
; RING_OF_SUSTAIN_{STRENGTH,INTELLIGENCE,WISDOM,CONSTITUTION,DEXTERITY,CHARISMA}
ovl_modal_sust_ring_tbl:
    DB   SUST_STR, SUST_INT, SUST_WIS, SUST_CON, SUST_DEX, SUST_CHR

; Direction key table: (key_byte, dir_0_to_7), terminated by 0x00
ovl_modal_dir_key_tbl:
    DB   'k', 0, 'K', 0, '8', 0, KEY_UP,    0
    DB   'j', 1, 'J', 1, '2', 1, KEY_DOWN,  1
    DB   'h', 2, 'H', 2, '4', 2, KEY_LEFT,  2
    DB   'l', 3, 'L', 3, '6', 3, KEY_RIGHT, 3
    DB   'y', 4, 'Y', 4, '7', 4
    DB   'u', 5, 'U', 5, '9', 5
    DB   'b', 6, 'B', 6, '1', 6
    DB   'n', 7, 'N', 7, '3', 7
    DB   0

; ============================================================================
; +0: ovl_modal_recalc_equipment
; Scan active equipment slots EQUIP_WEAPON..EQUIP_LAST (22..32), recompute:
;   player_pflags, player_pflags2, player_curse_flags, player_sust_mask,
;   wield_weight_lo/hi, wield_dmg_packed, wield_missile_type, wield_flags_0..3,
;   pcc_eq_tohit/todam/ac, player_eq_stat_mod[6], player_stat_res[6].
; Calls: player_sync_eq_stat_mod, player_step_equip_stat_c, player_calc_hp,
;        player_calc_combat, inv_calc_weight, player_sync_to_abi.
; Triggers INC zp_disturb on ITR3_BLIND | ITR3_TIMID 0->1 onset (TRN-014).
; Preserves: IX, IY
; ============================================================================
ovl_modal_recalc_equipment:
    LD   A, (player_curse_flags)
    LD   (ovl_modal_old_curse), A

    ; Zero player_pflags .. wield_flags_3 (12 contiguous bytes)
    LD   HL, player_pflags
    LD   DE, player_pflags + 1
    LD   BC, 11
    LD   (HL), 0
    LDIR

    ; Compute wield_* cached weapon stats from EQUIP_WEAPON (22)
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   FI_EMPTY
    JP   Z, .scan_slots
    LD   B, A
    LD   A, (inv_ego + EQUIP_WEAPON)
    LD   C, A                   ; C = full ego byte
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, B
    CALL icat_select_id
    JP   C, .scan_slots

    CALL icat_get_weight        ; HL = unit weight (0.1 lb)
    JR   C, .wield_dmg
    LD   A, C
    AND  EGO_ID_MASK
    CP   EGO_GREAT_MASS
    JR   NZ, .wield_wt_ok
    ADD  HL, HL
.wield_wt_ok:
    LD   (wield_weight_lo), HL

.wield_dmg:
    CALL icat_get_dmg           ; D = dice, E = sides
    JR   C, .wield_msl
    LD   A, D
    AND  0x0F
    RLCA
    RLCA
    RLCA
    RLCA
    LD   D, A
    LD   A, E
    AND  0x0F
    OR   D
    LD   (wield_dmg_packed), A

.wield_msl:
    LD   A, B
    CALL item_get_category_a
    LD   D, A                   ; D = category
    CP   ICAT_WEAPON
    JR   NZ, .wield_not_wep
    CALL icat_get_level_missile ; B = missile_type
    LD   A, B
    LD   (wield_missile_type), A
.wield_not_wep:
    PUSH DE                     ; preserve D = category
    CALL icat_get_effects
    POP  DE
    JR   C, .scan_slots
    LD   HL, icat_flags_0
    LD   DE, wield_flags_0
    PUSH DE
    LD   BC, 4
    LDIR
    POP  DE                     ; D = category? oops DE clobbered - reload below
    LD   A, (inv_item_id + EQUIP_WEAPON)
    LD   B, A
    LD   A, (inv_ego + EQUIP_WEAPON)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, B
    CALL item_get_category_a
    CP   ICAT_DIGGING
    JR   Z, .scan_slots
    LD   A, (inv_ego + EQUIP_WEAPON)
    AND  EGO_ID_MASK
    JR   Z, .scan_slots
    CALL icat_get_ego
    JR   C, .scan_slots
    LD   HL, icat_flags_0
    LD   DE, wield_flags_0
    LD   B, 4
.wield_ego_or:
    LD   A, (DE)
    OR   (HL)
    LD   (DE), A
    INC  HL
    INC  DE
    DJNZ .wield_ego_or

.scan_slots:
    LD   C, EQUIP_WEAPON        ; 22..32 (EQUIP_LAST; EQUIP_SECONDARY 33 is stowed)
.slot_loop:
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JP   Z, .slot_next

    LD   D, A                   ; D = slot_lo
    LD   HL, inv_ego
    ADD  HL, BC
    LD   A, (HL)
    LD   E, A                   ; E = raw ego byte
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, D
    CALL icat_select_id
    JP   C, .slot_next

    PUSH DE                     ; preserve D=slot_lo, E=raw_ego
    CALL icat_get_effects
    POP  DE
    JP   C, .slot_next

    ; Save base item flags 0..3 and catalog p1_lo
    LD   A, (icat_p1_lo)
    LD   (ovl_modal_cat_p1), A
    PUSH DE
    LD   HL, icat_flags_0
    LD   DE, ovl_modal_f0
    PUSH BC
    LD   BC, 4
    LDIR
    POP  BC
    POP  DE

    ; Merge ego flags if non-zero (skip ICAT_DIGGING prefix IDs 1..4; strip ITR1_SPEED on EGO_SLOWNESS)
    LD   A, E
    AND  EGO_ID_MASK
    JR   Z, .fold_flags
    LD   A, D
    CALL item_get_category_a
    CP   ICAT_DIGGING
    JR   Z, .fold_flags
    LD   A, E
    AND  EGO_ID_MASK
    PUSH DE
    CALL icat_get_ego
    POP  DE
    JR   C, .fold_flags
    LD   A, E
    AND  EGO_ID_MASK
    CP   EGO_SLOWNESS
    JR   NZ, .ego_flags_ok
    LD   HL, icat_flags_1
    RES  4, (HL)                ; Strip ITR1_SPEED from cursed Boots of Slowness
.ego_flags_ok:
    LD   HL, icat_flags_0
    LD   A, (ovl_modal_f0)
    OR   (HL)
    LD   (ovl_modal_f0), A
    INC  HL
    LD   A, (ovl_modal_f1)
    OR   (HL)
    LD   (ovl_modal_f1), A
    INC  HL
    LD   A, (ovl_modal_f2)
    OR   (HL)
    LD   (ovl_modal_f2), A
    INC  HL
    LD   A, (ovl_modal_f3)
    OR   (HL)
    LD   (ovl_modal_f3), A

.fold_flags:
    ; Byte 0 -> player_pflags2 (SEARCH, SLOW_DIGEST)
    LD   A, (ovl_modal_f0)
    LD   H, A
    LD   A, (player_pflags2)
    BIT  6, H                   ; ITR0_SEARCH
    JR   Z, .no_srh
    OR   PFLAG2_SEARCH
.no_srh:
    BIT  7, H                   ; ITR0_SLOW_DIGEST
    JR   Z, .no_sd
    OR   PFLAG2_SLOW_DIGEST
.no_sd:
    ; Byte 1 -> player_pflags2 (STEALTH, AGGRAVATE, TELEPORT, REGEN) + PFLAG_SPEED
    LD   L, A                   ; L = building player_pflags2
    LD   A, (ovl_modal_f1)
    BIT  0, A                   ; ITR1_STEALTH
    JR   Z, .no_stl
    SET  2, L                   ; PFLAG2_STEALTH (0x04)
.no_stl:
    BIT  1, A                   ; ITR1_AGGRAVATE
    JR   Z, .no_agg
    SET  3, L                   ; PFLAG2_AGGRAVATE (0x08)
.no_agg:
    BIT  2, A                   ; ITR1_TELEPORT
    JR   Z, .no_tel
    SET  4, L                   ; PFLAG2_TELEPORT (0x10)
.no_tel:
    BIT  3, A                   ; ITR1_REGEN
    JR   Z, .no_reg
    SET  1, L                   ; PFLAG2_REGEN (0x02)
.no_reg:
    BIT  4, A                   ; ITR1_SPEED
    JR   Z, .no_spd
    PUSH HL
    LD   HL, player_pflags
    SET  2, (HL)                ; PFLAG_SPEED (0x04)
    POP  HL
.no_spd:
    LD   A, L
    LD   (player_pflags2), A

    ; Byte 2 -> player_pflags + player_sust_mask
    LD   A, (ovl_modal_f2)
    LD   L, A
    LD   A, (player_pflags)
    BIT  3, L                   ; ITR2_RES_FIRE
    JR   Z, .no_rf
    OR   PFLAG_RESIST_FIRE
.no_rf:
    BIT  4, L                   ; ITR2_RES_ACID
    JR   Z, .no_ra
    OR   PFLAG_RESIST_ACID
.no_ra:
    BIT  5, L                   ; ITR2_RES_COLD
    JR   Z, .no_rc
    OR   PFLAG_RESIST_COLD
.no_rc:
    BIT  7, L                   ; ITR2_FREE_ACT
    JR   Z, .no_fa
    OR   PFLAG_FREE_ACT
.no_fa:
    LD   (player_pflags), A
    BIT  6, L                   ; ITR2_SUST_STAT
    CALL NZ, .add_sustain

    ; Byte 3 -> player_pflags, player_pflags2, player_curse_flags
    LD   A, (ovl_modal_f3)
    LD   L, A
    LD   A, (player_pflags)
    BIT  0, L                   ; ITR3_SEE_INVIS
    JR   Z, .no_si
    OR   PFLAG_SEE_INVIS
.no_si:
    BIT  1, L                   ; ITR3_RES_LIGHT
    JR   Z, .no_rl
    OR   PFLAG_RESIST_LIGHT
.no_rl:
    BIT  2, L                   ; ITR3_FFALL
    JR   Z, .no_ff
    OR   PFLAG_FFALL
.no_ff:
    LD   (player_pflags), A

    BIT  6, L                   ; ITR3_INFRA
    JR   Z, .no_inf
    LD   A, (player_pflags2)
    OR   PFLAG2_INFRA
    LD   (player_pflags2), A
.no_inf:
    LD   A, L
    AND  (ITR3_BLIND | ITR3_TIMID)
    JR   Z, .slot_next
    LD   HL, player_curse_flags
    OR   (HL)
    LD   (HL), A

.slot_next:
    INC  C
    LD   A, C
    CP   EQUIP_END
    JP   C, .slot_loop

    ; Sync passive equipment bits into PL_FLAGS (preserving timed zp_eff_see_inv)
    LD   HL, player_data + PL_FLAGS
    RES  1, (HL)                ; PLF_SEE_INV
    RES  3, (HL)                ; PLF_SLOW_DIG
    LD   A, (player_pflags)
    AND  PFLAG_SEE_INVIS
    JR   NZ, .set_see_inv
    LD   A, (zp_eff_see_inv)
    OR   A
    JR   Z, .chk_slowdig_plf
.set_see_inv:
    SET  1, (HL)                ; PLF_SEE_INV (0x02)
.chk_slowdig_plf:
    LD   A, (player_pflags2)
    AND  PFLAG2_SLOW_DIGEST
    JR   Z, .chk_curse_disturb
    SET  3, (HL)                ; PLF_SLOW_DIG (0x08)

.chk_curse_disturb:
    ; TRN-014: disturb on 0->1 onset of cursed blindness or timidity
    LD   A, (ovl_modal_old_curse)
    CPL
    LD   B, A
    LD   A, (player_curse_flags)
    AND  B
    AND  (ITR3_BLIND | ITR3_TIMID)
    JR   Z, .run_calcs
    LD   HL, zp_disturb
    INC  (HL)

.run_calcs:
    ; Preserve drained stats across equipment changes via differential player_eq_stat_mod
    LD   A, (player_data + PL_CON_CUR)
    PUSH AF
    LD   HL, player_eq_stat_mod
    LD   DE, bss_scratch
    LD   BC, STAT_COUNT
    LDIR
    CALL player_sync_eq_stat_mod
    LD   BC, 0
.eqd_lp:
    LD   HL, bss_scratch
    ADD  HL, BC
    LD   D, (HL)                ; D = old eq_stat_mod[C]
    LD   HL, player_eq_stat_mod
    ADD  HL, BC
    LD   A, (HL)                ; A = new eq_stat_mod[C]
    SUB  D                      ; A = signed delta (new - old)
    JR   Z, .eqd_nx
    JP   PO, .eqd_step
    ; Signed delta overflowed (-128..+127): undo old_mod cleanly then apply new_mod
    LD   A, D
    CP   0x80
    JR   NZ, .eqd_neg_ok
    LD   A, 64
    CALL player_step_equip_stat_c
    LD   A, 64
    CALL player_step_equip_stat_c
    JR   .eqd_apply_new
.eqd_neg_ok:
    NEG
    CALL player_step_equip_stat_c
.eqd_apply_new:
    LD   HL, player_eq_stat_mod
    ADD  HL, BC
    LD   A, (HL)
.eqd_step:
    CALL player_step_equip_stat_c
.eqd_nx:
    INC  C
    LD   A, C
    CP   STAT_COUNT
    JR   C, .eqd_lp
    POP  AF
    LD   HL, player_data + PL_CON_CUR
    CP   (HL)
    CALL NZ, player_calc_hp
    CALL player_calc_combat
    CALL inv_calc_weight
    CALL player_sync_to_abi
    LD   A, (inv_item_id + EQUIP_LIGHT)
    CP   FI_EMPTY
    JR   Z, .zero_light
    LD   A, (inv_p1 + EQUIP_LIGHT)
    OR   A
    RET  NZ
.zero_light:
    XOR  A
    LD   (player_data + PL_LIGHT_RAD), A
    LD   (zp_light_radius), A
    LD   (abi_light_rad), A
    RET

; .add_sustain — Resolve ITR2_SUST_STAT bitmask for slot C (D=slot_lo, E=raw_ego)
; Preserves BC
.add_sustain:
    BIT  6, E                   ; ITEM_PAGE_BIT?
    JR   Z, .sust_not_ring
    LD   A, D
    SUB  ITEM_SLOT_RING_OF_SUSTAIN_STRENGTH
    CP   6
    JR   NC, .sust_not_ring
    LD   E, A
    LD   D, 0
    LD   HL, ovl_modal_sust_ring_tbl
    ADD  HL, DE
    LD   A, (HL)
    JR   .sust_apply
.sust_not_ring:
    LD   A, E
    AND  EGO_ID_MASK
    CP   EGO_HOLY_AVENGER
    LD   A, SUST_STR
    JR   Z, .sust_apply
    LD   A, (ovl_modal_cat_p1)
    CP   7
    JR   NC, .sust_all
    LD   E, A
    LD   D, 0
    LD   HL, ovl_modal_sust_by_p1
    ADD  HL, DE
    LD   A, (HL)
    JR   .sust_apply
.sust_all:
    LD   A, SUST_ALL
.sust_apply:
    LD   HL, player_sust_mask
    OR   (HL)
    LD   (HL), A
    RET

; ============================================================================
; +3: ovl_modal_run_init — UMoria CJS running initialization (player_run.s)
; Input:  A = dir (0..7)
; Output: CF = 1 if initial running step is valid (populates zp_run_dir,
;         run_flags, run_prev_dir, run_count = 0)
;         CF = 0 if dir invalid or immediately blocked (zp_run_dir = 0xFF)
; Preserves: IX, IY
; ============================================================================
ovl_modal_run_init:
    PUSH IX
    PUSH IY
    CP   8
    JP   NC, .blocked
    LD   (ovl_modal_run_dir_tmp), A

    ; Compute first step (tx, ty) matching 6502 run_init (step 1 runs through _gl_try_move)
    CALL ovl_modal_dir_delta    ; B = py + dy, C = px + dx
    LD   L, C
    LD   H, B
    LD   (_om_r_t0x), HL

    XOR  A
    LD   (run_count), A
    LD   (run_flags), A
    LD   (_om_r_bits), A

    LD   A, (ovl_modal_run_dir_tmp)
    LD   (zp_run_dir), A
    LD   (run_prev_dir), A
    LD   E, A
    LD   D, 0
    LD   HL, ovl_modal_run_home
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_modal_run_cyc), A ; home index in ovl_modal_run_cycle

    ; Deterministic blind initialization keeps only RUNF_OPEN
    LD   A, (zp_eff_blind)
    OR   A
    JR   Z, .init_sides
    LD   A, RUNF_OPEN
    LD   (run_flags), A
.ok:
    SCF
.ret_ixiy:
    POP  IY
    POP  IX
    RET

.init_sides:
    ; Left flank: home + 1, short bit 1, RUNF_BREAK_LEFT
    LD   A, (ovl_modal_run_cyc)
    INC  A
    CALL _om_run_cyc_lookup
    LD   B, 1
    LD   C, RUNF_BREAK_LEFT
    CALL _om_run_init_side

    ; Right flank: home - 1, short bit 4, RUNF_BREAK_RIGHT
    LD   A, (ovl_modal_run_cyc)
    DEC  A
    CALL _om_run_cyc_lookup
    LD   B, 4
    LD   C, RUNF_BREAK_RIGHT
    CALL _om_run_init_side

    LD   A, (run_flags)
    AND  (RUNF_BREAK_LEFT | RUNF_BREAK_RIGHT)
    CP   (RUNF_BREAK_LEFT | RUNF_BREAK_RIGHT)
    JR   Z, .enclosed
    LD   HL, run_flags
    SET  0, (HL)                ; RUNF_OPEN
    JR   .ok

.enclosed:
    LD   A, (ovl_modal_run_dir_tmp)
    CP   4
    JR   C, .straight
    LD   A, (_om_r_bits)
    AND  10                     ; deep bits (2=left, 8=right)
    CP   2
    JR   Z, .prev_right
    CP   8
    JR   Z, .prev_left
    JR   .ok

.straight:
    CALL _om_run_base_target
    LD   A, (ovl_modal_run_dir_tmp)
    CALL _om_run_wall           ; wall two squares ahead?
    JR   NC, .ok
    LD   A, (_om_r_bits)
    AND  5                      ; short bits (1=left, 4=right)
    CP   1
    JR   Z, .prev_far_right
    CP   4
    JR   Z, .prev_far_left
    JR   .ok

.prev_far_right:
    LD   A, (ovl_modal_run_cyc)
    SUB  2
    JR   .store_prev
.prev_far_left:
    LD   A, (ovl_modal_run_cyc)
    ADD  A, 2
    JR   .store_prev
.prev_right:
    LD   A, (ovl_modal_run_cyc)
    DEC  A
    JR   .store_prev
.prev_left:
    LD   A, (ovl_modal_run_cyc)
    INC  A
.store_prev:
    CALL _om_run_cyc_lookup
    LD   (run_prev_dir), A
    JP   .ok

.blocked:
    LD   A, 0xFF
    LD   (zp_run_dir), A
    OR   A
    JP   .ret_ixiy

; _om_run_init_side — A = side dir, B = short bit, C = RUNF_BREAK_* mask
_om_run_init_side:
    PUSH BC
    PUSH AF
    CALL _om_run_base_player
    POP  AF
    PUSH AF
    CALL _om_run_wall
    POP  DE                     ; D = side dir
    POP  BC
    JR   C, .found
    PUSH BC
    PUSH DE
    CALL _om_run_base_target
    POP  DE
    LD   A, D
    CALL _om_run_wall
    POP  BC
    RET  NC
    SLA  B                      ; deep wall records next higher bit
.found:
    LD   HL, _om_r_bits
    LD   A, (HL)
    OR   B
    LD   (HL), A
    LD   HL, run_flags
    LD   A, (HL)
    OR   C
    LD   (HL), A
    RET

; ============================================================================
; +33: ovl_modal_run_area_affect — UMoria CJS newly-adjacent check (player_run.s)
; Output: CF = 1 -> stop running, CF = 0 -> continue running
; Preserves: IX, IY
; ============================================================================
ovl_modal_run_area_affect:
    PUSH IX
    PUSH IY
    LD   A, (zp_eff_blind)
    OR   A
    JR   Z, .ra_setup
    OR   A                      ; blind: keep running
.ra_ret:
    POP  IY
    POP  IX
    RET

.ra_setup:
    LD   A, (run_prev_dir)
    AND  7
    LD   E, A
    LD   D, 0
    LD   HL, ovl_modal_run_home
    ADD  HL, DE
    LD   B, (HL)                ; home index
    LD   A, B
    LD   (ovl_modal_run_cyc), A
    LD   (_om_r_scan), A
    LD   (_om_r_end), A
    LD   A, E
    CP   4
    JR   C, .ra_cardinal
    LD   HL, _om_r_scan
    DEC  (HL)
    LD   HL, _om_r_end
    INC  (HL)
.ra_cardinal:
    LD   HL, _om_r_scan
    DEC  (HL)
    LD   HL, _om_r_end
    INC  (HL)
    LD   A, 0xFF
    LD   (_om_r_dira), A
    LD   (_om_r_dirb), A
    CALL _om_run_base_player

.ra_scan:
    LD   A, (_om_r_scan)
    CALL _om_run_cyc_lookup
    LD   (ovl_modal_run_dir_tmp), A
    CALL _om_run_classify
    JP   C, .ra_stop            ; visible item, door, stair, trap, monster -> stop
    LD   E, A                   ; E = 0 closed, 1 open

    LD   A, (run_flags)
    AND  RUNF_OPEN
    JR   Z, .ra_corridor

    ; Open room/edge running: track left/right flank wall transitions
    LD   HL, ovl_modal_run_cyc
    LD   A, (_om_r_scan)
    CP   (HL)
    JR   Z, .ra_next            ; skip center dir
    LD   C, RUNF_BREAK_RIGHT
    JR   C, .ra_side_mask
    LD   C, RUNF_BREAK_LEFT
.ra_side_mask:
    LD   A, C
    LD   B, A                   ; B = side mask
    LD   A, E
    OR   A
    JR   Z, .ra_side_closed
    LD   A, (run_flags)
    AND  B
    JP   NZ, .ra_stop           ; previously broken side opened again -> stop
    JR   .ra_next
.ra_side_closed:
    LD   A, B
    XOR  (RUNF_BREAK_LEFT | RUNF_BREAK_RIGHT)
    LD   HL, run_flags
    AND  (HL)
    JP   NZ, .ra_stop           ; opposite side already closed earlier -> stop
    LD   A, (HL)
    OR   B
    LD   (HL), A
    JR   .ra_next

.ra_corridor:
    LD   A, E
    OR   A
    JR   Z, .ra_next            ; closed -> keep scanning
    LD   A, (_om_r_dira)
    BIT  7, A
    JR   Z, .ra_second
    LD   A, (ovl_modal_run_dir_tmp)
    LD   (_om_r_dira), A
    JR   .ra_next
.ra_second:
    LD   A, (_om_r_dirb)
    BIT  7, A
    JP   Z, .ra_stop            ; 3rd open direction -> junction, stop
    LD   A, (_om_r_scan)
    DEC  A
    CALL _om_run_cyc_lookup
    LD   HL, _om_r_dira
    CP   (HL)
    JP   NZ, .ra_stop           ; non-adjacent open directions -> stop
    LD   A, (ovl_modal_run_dir_tmp)
    CP   4
    JR   C, .ra_new_straight
    LD   (_om_r_dirb), A
    LD   A, (_om_r_scan)
    SUB  2
    CALL _om_run_cyc_lookup
    LD   (_om_r_check), A
    JR   .ra_next
.ra_new_straight:
    LD   B, (HL)                ; old dir_a -> dir_b (diagonal)
    LD   (_om_r_dira), A
    LD   A, B
    LD   (_om_r_dirb), A
    LD   A, (_om_r_scan)
    INC  A
    CALL _om_run_cyc_lookup
    LD   (_om_r_check), A

.ra_next:
    LD   HL, _om_r_scan
    INC  (HL)
    LD   A, (_om_r_end)
    CP   (HL)
    JP   NC, .ra_scan

    ; Scan finished: evaluate corridor directions / corners
    LD   A, (run_flags)
    AND  RUNF_OPEN
    JR   NZ, .ra_cont
    LD   A, (_om_r_dirb)
    BIT  7, A
    JR   Z, .ra_corner
    LD   A, (_om_r_dira)
    BIT  7, A
    JR   NZ, .ra_cont           ; 0 open dirs -> next step will hit dead-end
    LD   (zp_run_dir), A
    LD   (run_prev_dir), A
.ra_cont:
    OR   A                      ; CF=0 continue
    JP   .ra_ret

.ra_corner:
    ; Step base to player + dir_a
    LD   A, (_om_r_dira)
    CALL ovl_modal_dir_delta    ; B = py+dy, C = px+dx
    LD   L, C
    LD   H, B
    LD   (_om_r_tx), HL
    LD   A, (_om_r_dira)
    CALL _om_run_wall
    JR   NC, .ra_potential
    LD   A, (_om_r_check)
    CALL _om_run_wall
    JR   NC, .ra_potential
    ; Known corner: cut diagonally along dir_b
    LD   A, (_om_r_dirb)
    LD   (zp_run_dir), A
    LD   (run_prev_dir), A
    JR   .ra_cont

.ra_potential:
    LD   A, (_om_r_dira)
    CALL _om_run_nothing
    JR   NC, .ra_stop
    LD   A, (_om_r_dirb)
    CALL _om_run_nothing
    JR   NC, .ra_stop
    LD   A, (_om_r_dira)
    LD   (zp_run_dir), A
    LD   A, (_om_r_dirb)
    LD   (run_prev_dir), A
    JR   .ra_cont

.ra_stop:
    SCF
    JP   .ra_ret

; ----------------------------------------------------------------------------
; CJS Run Helpers
; ----------------------------------------------------------------------------
_om_run_cyc_lookup:
    LD   E, A
    LD   D, 0
    LD   HL, ovl_modal_run_cycle
    ADD  HL, DE
    LD   A, (HL)
    RET

_om_run_base_player:
    LD   HL, (abi_player_x)
    LD   (_om_r_tx), HL
    RET

_om_run_base_target:
    LD   HL, (_om_r_t0x)
    LD   (_om_r_tx), HL
    RET

; _om_run_get_tile — Input: A = dir 0..7 from (_om_r_tx, _om_r_ty).
; Updates ovl_modal_run_px/py and _om_r_found. Output: A = tile byte.
_om_run_get_tile:
    LD   E, A
    LD   D, 0
    LD   HL, dir_dx
    ADD  HL, DE
    LD   A, (_om_r_tx)
    ADD  A, (HL)
    LD   (ovl_modal_run_px), A
    LD   C, A
    CP   MAP_COLS
    JR   NC, .oob
    LD   HL, dir_dy
    ADD  HL, DE
    LD   A, (_om_r_ty)
    ADD  A, (HL)
    LD   (ovl_modal_run_py), A
    LD   B, A
    CP   MAP_ROWS
    JR   NC, .oob
    CALL map_get_tile
    JR   C, .oob
    LD   (_om_r_found), A
    RET
.oob:
    LD   A, TILE_WALL_H | FLAG_VISITED
    LD   (_om_r_found), A
    RET

; _om_run_tile_displayed — CF=1 iff (_om_r_found at run_px/py) is currently displayed
_om_run_tile_displayed:
    LD   A, (zp_eff_blind)
    OR   A
    JR   NZ, .no
    LD   A, (abi_player_dlvl)
    OR   A
    JR   Z, .yes
    LD   A, (_om_r_found)
    BIT  2, A                   ; FLAG_VISITED
    JR   NZ, .yes
    ; Not visited yet: check light radius + LOS from player
    LD   A, (inv_item_id + EQUIP_LIGHT)
    INC  A
    JR   Z, .rad_ok
    LD   A, (inv_p1 + EQUIP_LIGHT)
    OR   A
    JR   Z, .no
.rad_ok:
    LD   A, (abi_light_rad)
    LD   B, A                   ; B = effective light radius
    LD   HL, (abi_player_x)     ; L=px, H=py
    LD   A, (ovl_modal_run_px)
    SUB  L
    JR   NC, .dx_p
    NEG
.dx_p:
    LD   C, A
    LD   A, (ovl_modal_run_py)
    SUB  H
    JR   NC, .dy_p
    NEG
.dy_p:
    CP   C
    JR   NC, .got_d
    LD   A, C
.got_d:
    CP   B
    JR   Z, .in_rad
    JR   NC, .no
.in_rad:
    CP   2
    JR   C, .yes                ; dist <= 1 from player is always LOS-clear
    LD   E, L
    LD   D, H
    LD   HL, (ovl_modal_run_px) ; L=tx, H=ty
    LD   C, L
    LD   B, H
    JP   los_check
.yes:
    SCF
    RET
.no:
    OR   A
    RET

; _om_run_terrain_class — CF=1 & A=0 (wall), CF=0 & A=1 (open), CF=0 & A=0xFF (object)
_om_run_terrain_class:
    LD   A, (_om_r_found)
    AND  TILE_TYPE_MASK
    JR   Z, .open
    CP   TILE_DOOR_OPEN
    JR   C, .wall
    CP   TILE_MAGMA
    JR   C, .obj
    CP   TILE_TRAP
    JR   Z, .obj
.wall:
    XOR  A
    SCF
    RET
.obj:
    LD   A, 0xFF
    OR   A
    RET
.open:
    LD   A, 1
    OR   A
    RET

; _om_run_mon_visible — Input: B=py, C=px -> Z=0 (NZ) if visible live monster at (px,py)
_om_run_mon_visible:
    CALL monster_find_at
    JR   NC, .none
    PUSH AF
    CALL monster_update_visibility_one
    POP  AF
    CALL monster_get_ptr
    LD   DE, MX_FLAGS
    ADD  HL, DE
    LD   A, (HL)
    AND  MF_VISIBLE
    RET
.none:
    XOR  A
    RET

; _om_run_wall — CF=1 if square in dir A from (_om_r_tx/y) is displayed as wall
_om_run_wall:
    CALL _om_run_get_tile
    CALL _om_run_tile_displayed
    RET  NC
    JP   _om_run_terrain_class

; _om_run_nothing — CF=1 if square in dir A from (_om_r_tx/y) displays as blank
_om_run_nothing:
    CALL _om_run_get_tile
    CALL _om_run_tile_displayed
    CCF
    RET  NC                     ; displayed -> CF=0
    LD   A, (_om_r_found)
    BIT  0, A                   ; FLAG_OCCUPIED
    JR   Z, .blank
    LD   BC, (ovl_modal_run_px)
    CALL _om_run_mon_visible
    JR   NZ, .not_blank
.blank:
    SCF
    RET
.not_blank:
    OR   A
    RET

; _om_run_classify — CF=1 if stop target; else CF=0, A=0 (closed wall) or 1 (open)
_om_run_classify:
    CALL _om_run_get_tile
    CALL _om_run_tile_displayed
    JR   NC, .open_unseen
    LD   A, (abi_player_dlvl)
    OR   A
    JR   NZ, .not_store
    LD   BC, (ovl_modal_run_px)
    CALL store_door_lookup
    RET  C
.not_store:
    LD   A, (_om_r_found)
    BIT  1, A                   ; FLAG_HAS_ITEM
    JR   NZ, .stop
    BIT  0, A                   ; FLAG_OCCUPIED
    JR   Z, .feat
    LD   BC, (ovl_modal_run_px)
    CALL _om_run_mon_visible
    JR   NZ, .stop
.feat:
    CALL _om_run_terrain_class
    BIT  7, A
    JR   NZ, .stop
    OR   A
    RET                         ; 0 or 1 with CF=0
.stop:
    SCF
    RET
.open_unseen:
    LD   A, 1
    OR   A
    RET

; ovl_modal_dir_delta — Compute B = abi_player_y + dir_dy[A], C = abi_player_x + dir_dx[A]
ovl_modal_dir_delta:
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

; ovl_modal_step_passable — CF=1 if tile (B=y, C=x) is in-bounds [1..MAX-2], unoccupied, & walkable
ovl_modal_step_passable:
    LD   A, C
    DEC  A
    CP   MAP_COLS - 2
    JR   NC, .oob_clear
    LD   A, B
    DEC  A
    CP   MAP_ROWS - 2
    JR   NC, .oob_clear
    CALL map_get_tile
    JR   C, .oob_clear
    BIT  0, A                   ; FLAG_OCCUPIED
    JR   NZ, .oob_clear
    JP   tile_is_walkable_a
.oob_clear:
    OR   A
    RET

; ============================================================================
; +6: ovl_modal_calc_dig
; Compute digging power in A (0..255) matching 6502 core/calc_dig_cold.s:
;   Bare hands (FI_EMPTY) -> 0
;   ICAT_DIGGING tool     -> min(255, (STR>>2) + dig_base_table[0..5] + ego*12)
;   Other weapon          -> min(255, (STR>>2) + max(0, PL_TODMG >> 1))
; Preserves: IX, IY
; ============================================================================
ovl_modal_calc_dig:
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   FI_EMPTY
    JR   NZ, .has_weapon
    XOR  A
    RET

.has_weapon:
    LD   B, A                   ; B = weapon slot_lo
    LD   A, (inv_ego + EQUIP_WEAPON)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, B
    CALL item_get_category_a
    LD   D, A                   ; D = category

    LD   A, (player_data + PL_STR_CUR)
    SRL  A
    SRL  A
    LD   C, A                   ; C = STR >> 2

    LD   A, D
    CP   ICAT_DIGGING
    JR   Z, .is_digger

    ; Regular weapon: (STR >> 2) + max(0, PL_TODMG >> 1)
    LD   A, (player_data + PL_TODMG)
    BIT  7, A
    JR   Z, .pos_todmg
    LD   A, C
    RET
.pos_todmg:
    SRL  A
    ADD  A, C
    RET  NC
    LD   A, 255
    RET

.is_digger:
    LD   A, (item_cur_page)
    OR   A
    JR   Z, .page0_dig
    LD   A, C
    RET
.page0_dig:
    LD   A, B                   ; weapon slot_lo
    SUB  ITEM_SLOT_PICK
    JR   C, .ret_c
    CP   6
    JR   NC, .ret_c
    LD   B, A                   ; B = 0..5 index
    LD   E, A
    LD   D, 0
    LD   HL, .dig_base_tbl
    ADD  HL, DE
    LD   A, C
    ADD  A, (HL)
    JR   C, .sat_255
    LD   C, A
    LD   A, B
    CP   2                      ; Only base Pick (0) and Shovel (1) add ego*12
    JR   NC, .ret_c
    LD   A, (inv_ego + EQUIP_WEAPON)
    AND  EGO_ID_MASK
    JR   Z, .ret_c
    ADD  A, A                   ; *2
    ADD  A, A                   ; *4
    LD   D, A
    ADD  A, A                   ; *8
    ADD  A, D                   ; *12
    JR   C, .sat_255
    ADD  A, C
    RET  NC
.sat_255:
    LD   A, 255
    RET
.ret_c:
    LD   A, C
    RET

.dig_base_tbl:
    DB   20, 6, 32, 44, 18, 30

; ============================================================================
; +9: ovl_modal_exchange_weapon
; Swap EQUIP_WEAPON (22) <-> EQUIP_SECONDARY (33).
; Checks IF_CURSED on EQUIP_WEAPON if occupied. Calls ovl_modal_recalc_equipment.
; Output: CF = 1 swapped, CF = 0 refused or both empty.
; Preserves: IX, IY
; ============================================================================
ovl_modal_exchange_weapon:
    ; Corrupt-save guard: EQUIP_SECONDARY must map to EQUIP_WEAPON or be empty (6502 item_exchange.s)
    LD   A, (inv_item_id + EQUIP_SECONDARY)
    CP   FI_EMPTY
    JR   Z, .sec_ok
    LD   B, A
    LD   A, (inv_ego + EQUIP_SECONDARY)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, B
    CALL item_get_category_a
    LD   E, A
    LD   D, 0
    LD   HL, equip_slot_for_cat
    ADD  HL, DE
    LD   A, (HL)
    CP   EQUIP_WEAPON
    JR   NZ, .no_wep
.sec_ok:
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   FI_EMPTY
    JR   NZ, .chk_cursed
    LD   A, (inv_item_id + EQUIP_SECONDARY)
    CP   FI_EMPTY
    JR   NZ, .do_swap
.no_wep:
    LD   HL, _om_str_no_wep
    CALL msg_print_str
    OR   A                      ; Both empty / invalid secondary -> CF = 0
    RET

.chk_cursed:
    LD   A, (inv_flags + EQUIP_WEAPON)
    AND  IF_CURSED
    JR   Z, .do_swap
    LD   A, HSTR_PIW_CURSED
    CALL msg_print_huff
    OR   A                      ; Cursed weapon cannot be sheathed -> CF = 0
    RET

.do_swap:
    ; Swap 8 contiguous arrays (inv_item_id..inv_ego), each TOTAL_INV_SLOTS wide
    LD   HL, inv_item_id + EQUIP_WEAPON
    LD   DE, inv_item_id + EQUIP_SECONDARY
    LD   B, 8
.swap_lp:
    LD   C, (HL)
    LD   A, (DE)
    LD   (HL), A
    LD   A, C
    LD   (DE), A
    PUSH BC
    LD   BC, TOTAL_INV_SLOTS
    ADD  HL, BC
    EX   DE, HL
    ADD  HL, BC
    EX   DE, HL
    POP  BC
    DJNZ .swap_lp

    CALL ovl_modal_recalc_equipment
    LD   A, EQUIP_WEAPON
    LD   HL, _om_str_primary
    CALL .report_slot
    LD   A, EQUIP_SECONDARY
    LD   HL, _om_str_secondary
    CALL .report_slot
    SCF
    RET

.report_slot:
    PUSH AF
    LD   E, A
    LD   D, 0
    PUSH HL
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    POP  HL
    CP   FI_EMPTY
    JR   NZ, .do_rep
    POP  AF
    RET
.do_rep:
    LD   DE, line_buf
    CALL _om_append_str
    POP  AF
    LD   C, A
    LD   B, 0
    LD   HL, inv_flags
    ADD  HL, BC
    LD   C, (HL)
    PUSH HL
    PUSH BC
    RES  3, (HL)                    ; mask IF_SENSED (6502 item_append_desc never prints " (magik)")
    CALL item_format_inv_slot
    POP  BC
    POP  HL
    LD   (HL), C
    LD   HL, line_buf
    JP   msg_print_str

; ============================================================================
; +12: ovl_modal_direction_prompt
; Displays "Direction?" on MSG_ROW0, waits for direction key:
;   hjkl/yubn, HJKL/YUBN, KEY_UP..KEY_RIGHT, 12346789.
; Output: CF = 1 -> A = D = dir (0..7), stores df_dir_idx, df_target_x/y
;         CF = 0 -> cancelled / invalid key
; Preserves: IX, IY
; ============================================================================
ovl_modal_direction_prompt:
    CALL msg_clear
    LD   A, HSTR_DF_DIRECTION
    CALL msg_print_huff
    CALL screen_flush
    CALL input_get_key
    LD   C, A                   ; C = pressed key
    CALL msg_clear

    LD   HL, ovl_modal_dir_key_tbl
.key_lp:
    LD   A, (HL)
    OR   A
    JR   Z, .cancelled
    INC  HL
    LD   D, (HL)                ; D = dir
    INC  HL
    CP   C
    JR   NZ, .key_lp

    LD   A, D
    LD   (df_dir_idx), A
    CALL ovl_modal_dir_delta    ; B = target_y, C = target_x
    LD   A, C
    LD   (df_target_x), A
    LD   A, B
    LD   (df_target_y), A
    LD   A, (df_dir_idx)
    LD   D, A
    SCF
    RET

.cancelled:
    OR   A
    RET

    IFNDEF CATALOG_COUNT
    DEFINE MONSTER_IDX_CONSTS_ONLY 1
    INCLUDE "monster_idx_z80.inc"
    UNDEFINE MONSTER_IDX_CONSTS_ONLY
    ENDIF

; ============================================================================
; +15: ovl_modal_player_attack — Player melee round against (B=y, C=x)
; Output: CF = 1 if turn consumed (monster at target), CF = 0 if none
; Preserves: IX, IY
; ============================================================================
ovl_modal_player_attack:
    PUSH IX
    PUSH IY

    LD   A, C
    LD   (cmb_target_x), A
    LD   A, B
    LD   (cmb_target_y), A

    CALL player_search_mode_off
    CALL monster_find_at        ; B=y, C=x -> CF=1, A=slot, HL=ptr
    JR   C, .has_mon
    POP  IY
    POP  IX
    OR   A                      ; CF = 0
    RET

.has_mon:
    LD   (cmb_slot), A
    PUSH HL
    POP  IX                     ; IX = monster_table[slot]
    LD   A, (IX + MX_TYPE)
    LD   (cmb_type), A

    ; Visibility & wake/provoke on melee target
    LD   A, (IX + MX_FLAGS)
    BIT  3, A                   ; MF_VISIBLE
    LD   B, 0
    JR   Z, .not_lit
    INC  B
.not_lit:
    LD   C, A
    LD   A, B
    LD   (cmb_target_lit), A
    LD   A, C
    OR   (MF_AWAKE | MF_PROVOKED)
    LD   (IX + MX_FLAGS), A
    LD   (IX + MX_SLEEP_CUR), 0

    ; --- Compute melee_tohit_bonus = PL_TOHIT (+ penalties for unarmed/too-heavy, skip launchers) ---
    LD   A, (player_data + PL_TOHIT)
    LD   B, A                   ; B = signed bonus
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   FI_EMPTY
    JR   Z, .pen_unarmed
    LD   A, (wield_missile_type)
    OR   A
    JR   NZ, .bonus_done        ; launchers/ammo in melee skip weight check
    LD   HL, (wield_weight_lo)
    LD   A, H
    OR   L
    JR   Z, .pen_unarmed
    CALL _om_str15_minus_wt     ; DE = STR*15 - wt (CF=1 if negative)
    JR   NC, .bonus_done
    LD   A, D
    CP   0xFF
    JR   NZ, .cap_heavy
    BIT  7, E
    LD   A, E
    JR   NZ, .add_heavy
.cap_heavy:
    LD   A, 0x80                ; clamp -128
.add_heavy:
    ADD  A, B
    LD   B, A
    JR   .bonus_done
.pen_unarmed:
    LD   A, B
    SUB  3
    LD   B, A
.bonus_done:
    LD   A, B
    LD   (_om_melee_bonus), A

    ; --- Compute total BTH (6502 combat_calc_tohit_common: byte-saturating stages) ---
    LD   A, (player_data + PL_CLASS)
    LD   E, A
    LD   D, 0
    LD   A, CLASS_PROP_SIZE
    CALL mul_de_a
    LD   DE, class_properties + 3
    ADD  HL, DE
    LD   C, (HL)                ; C = class BTH (u8)

    LD   A, (player_data + PL_RACE)
    LD   E, A
    LD   D, 0
    LD   A, RACE_PROP_SIZE
    CALL mul_de_a
    LD   DE, race_properties + 7
    ADD  HL, DE
    LD   A, (HL)                ; A = signed race BTH
    LD   L, C
    LD   H, 0
    CALL _om_add_s8_hl
    CALL _om_clamp_hl_u8
    LD   C, A

    ; +5 bless, +12 heroism (byte-saturating)
    LD   A, (zp_eff_bless)
    OR   A
    JR   Z, .no_bless
    LD   A, C
    ADD  A, 5
    JR   NC, .bl_ok
    LD   A, 255
.bl_ok:
    LD   C, A
.no_bless:
    LD   A, (zp_eff_hero)
    OR   A
    JR   Z, .no_hero
    LD   A, C
    ADD  A, 12
    JR   NC, .hr_ok
    LD   A, 255
.hr_ok:
    LD   C, A
.no_hero:

    ; Unlit halves BTH and uses mult=1 instead of 3 (6502 combat.s:384-395)
    LD   A, (cmb_target_lit)
    OR   A
    LD   B, 3
    JR   NZ, .lit_mult_ok
    SRL  C
    LD   B, 1
.lit_mult_ok:
    ; + signed(_om_melee_bonus) * mult
    LD   A, (_om_melee_bonus)
    BIT  7, A
    JR   Z, .pos_b
    NEG
    LD   E, A
    LD   D, 0
    LD   A, B
    CALL mul_de_a
    EX   DE, HL                 ; DE = |bonus| * mult
    LD   L, C
    LD   H, 0
    OR   A
    SBC  HL, DE
    JR   .b_done
.pos_b:
    LD   E, A
    LD   D, 0
    LD   A, B
    CALL mul_de_a
    LD   E, C
    LD   D, 0
    ADD  HL, DE
.b_done:
    CALL _om_clamp_hl_u8
    LD   C, A

    ; + (PL_LEVEL * class_level_adj[class*5 + 0]) >> (!lit ? 1 : 0)
    PUSH BC
    CALL _om_calc_lvl_bth_u8    ; A = level_bth (<= 255)
    POP  BC
    LD   B, A
    LD   A, (cmb_target_lit)
    OR   A
    LD   A, B
    JR   NZ, .lvl_lit_ok
    SRL  A
.lvl_lit_ok:
    ADD  A, C
    JR   NC, .bth_store
    LD   A, 255
.bth_store:
    LD   (cmb_total_tohit), A

    ; --- Compute blow count (1..4; unarmed=2, launcher=1) ---
    CALL _om_calc_blows
    LD   (cmb_blow_count), A

    XOR  A
    LD   (cmb_any_hit), A
    LD   (cmb_hit_count), A
    LD   (cmb_dead), A
    LD   A, (cmb_blow_count)
    LD   B, A

.blow_lp:
    PUSH BC
    ; Roll d20 (0..19 -> 1..20): 1=miss, 20=hit, else (tohit>=2 && rng(tohit)>=cr_ac)
    LD   A, 20
    CALL rng_range
    OR   A
    JP   Z, .next_blow          ; natural 1: always miss
    CP   19
    JR   Z, .hit                ; natural 20: always hit
    LD   A, (cmb_total_tohit)
    CP   2
    JP   C, .next_blow          ; tohit < 2: miss
    CALL rng_range              ; [0, tohit-1]
    LD   D, A
    LD   A, (cmb_type)
    LD   C, A
    LD   B, 0
    LD   HL, cr_ac
    ADD  HL, BC
    LD   A, D
    CP   (HL)                   ; roll >= cr_ac -> hit
    JP   C, .next_blow

.hit:
    LD   A, 1
    LD   (cmb_any_hit), A
    LD   HL, cmb_hit_count
    INC  (HL)

    ; Confuse-on-hit from Monster Confusion scroll (6502 combat.s:132-157: silent, on hit only)
    LD   A, (zp_confuse_melee)
    OR   A
    JR   Z, .no_conf_hit
    XOR  A
    LD   (zp_confuse_melee), A
    LD   A, (cmb_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_cdefense
    ADD  HL, DE
    LD   A, (HL)
    AND  CD_NO_SLEEP
    JR   NZ, .no_conf_hit
    LD   A, (IX + MX_CONFUSE)
    OR   A
    JR   NZ, .conf_stack
    LD   A, 16
    CALL rng_range
    ADD  A, 2                   ; 2..17
    JR   .conf_store
.conf_stack:
    ADD  A, 3
    JR   NC, .conf_store
    LD   A, 255
.conf_store:
    LD   (IX + MX_CONFUSE), A
.no_conf_hit:

    ; Roll weapon dice (unarmed or launcher in melee -> 1d2 per 6502 combat.s:636-642)
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   FI_EMPTY
    JR   Z, .unarmed_1d2
    LD   A, (wield_missile_type)
    OR   A
    JR   Z, .armed_dmg
    CP   4
    JR   C, .unarmed_1d2
.armed_dmg:
    LD   A, (wield_dmg_packed)
    LD   D, A
    RRCA
    RRCA
    RRCA
    RRCA
    AND  0x0F
    LD   B, A                   ; dice
    LD   A, D
    AND  0x0F
    LD   C, A                   ; sides
    OR   A
    JR   Z, .unarmed_1d2
    LD   A, B
    OR   A
    JR   Z, .unarmed_1d2
    CALL roll_dice_bc           ; A = min(sum, 255)
    LD   L, A
    LD   H, 0
    JR   .after_base_dmg
.unarmed_1d2:
    LD   B, 1
    LD   C, 2
    CALL roll_dice_bc
    LD   L, A
    LD   H, 0

.after_base_dmg:
    ; Apply ego weapon slays (armed melee weapon only; launchers skipped)
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   FI_EMPTY
    JR   Z, .after_ego
    LD   A, (wield_missile_type)
    OR   A
    JR   Z, .do_ego
    CP   4
    JR   C, .after_ego
.do_ego:
    CALL _om_apply_ego_slays

.after_ego:
    ; Critical hit check
    CALL _om_apply_critical

    ; + signed PL_TODMG, clamp to [0, 255]
    LD   A, (player_data + PL_TODMG)
    CALL _om_add_s8_hl
    CALL _om_clamp_hl_u8
    LD   L, A
    LD   H, 0
.dmg_ok:
    ; Subtract HL from monster HP (IX + MX_HP_LO/HI)
    LD   E, (IX + MX_HP_LO)
    LD   D, (IX + MX_HP_HI)
    EX   DE, HL                 ; HL = hp, DE = dmg
    OR   A
    SBC  HL, DE
    JR   C, .mon_died
    LD   A, H
    OR   L
    JR   Z, .mon_died
    LD   (IX + MX_HP_LO), L
    LD   (IX + MX_HP_HI), H
    JR   .next_blow

.mon_died:
    LD   (IX + MX_HP_LO), 0
    LD   (IX + MX_HP_HI), 0
    LD   A, 1
    LD   (cmb_dead), A
    POP  BC
    JR   .blows_done

.next_blow:
    POP  BC
    DEC  B
    JP   NZ, .blow_lp

.blows_done:
    LD   A, (cmb_type)
    CALL monster_get_name_ptr
    LD   DE, line_buf
    LD   A, (cmb_dead)
    OR   A
    JR   NZ, .msg_slain
    LD   A, (cmb_any_hit)
    OR   A
    JR   NZ, .msg_hit
    LD   BC, _om_str_miss_pre
    CALL _om_fmt_prefix
    JR   .msg_dot
.msg_hit:
    LD   BC, _om_str_hit_pre
    CALL _om_fmt_prefix
    LD   A, (cmb_blow_count)
    CP   2
    JR   C, .msg_dot
    LD   A, ' '
    LD   (DE), A
    INC  DE
    LD   A, '('
    LD   (DE), A
    INC  DE
    LD   A, (cmb_hit_count)
    CALL fmt_u8_dec
    LD   A, '/'
    LD   (DE), A
    INC  DE
    LD   A, (cmb_blow_count)
    CALL fmt_u8_dec
    LD   A, ')'
    LD   (DE), A
    INC  DE
    JR   .msg_dot
.msg_slain:
    LD   BC, _om_str_slay_pre
    CALL _om_fmt_prefix
.msg_dot:
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   HL, line_buf
    CALL msg_print_str

    LD   A, (cmb_dead)
    OR   A
    JR   Z, .atk_done
    LD   A, (cmb_slot)
    CALL ovl_modal_kill_monster

.atk_done:
    POP  IY
    POP  IX
    SCF
    RET

; ============================================================================
; +18: ovl_modal_kill_monster — Remove dead monster slot A, stage drops, award XP
; Input:  A = monster slot (0..31)
; Preserves: IX, IY
; ============================================================================
ovl_modal_kill_monster:
    PUSH IX
    PUSH IY

    LD   (cmb_slot), A
    CALL monster_get_ptr
    JR   NC, .valid
    POP  IY
    POP  IX
    RET
.valid:
    LD   BC, MX_TYPE
    ADD  HL, BC
    LD   A, (HL)
    LD   (cmb_type), A

    CALL recall_inc_kills_slot
    LD   A, (cmb_slot)
    CALL monster_remove
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   A, (cmb_type)
    CALL monster_death_stage

    ; VMS XP: (cr_xp * cr_level) / pl_lvl + fractional carry in PL_XP_FRAC
    LD   A, (cmb_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_level
    ADD  HL, DE
    LD   A, (HL)                ; A = cr_level
    OR   A
    JR   Z, .chk_balrog

    PUSH AF                     ; save cr_level
    LD   HL, cr_xp_lo
    ADD  HL, DE
    LD   C, (HL)
    LD   HL, cr_xp_hi
    ADD  HL, DE
    LD   B, (HL)                ; BC = cr_xp (16-bit)
    POP  AF
    ; 16x8 unsigned BC * A -> E:HL (24-bit)
    CALL _om_mul_bc_a           ; E:HL = cr_xp * cr_level

    ; Divide 24-bit E:HL by pl_lvl -> quotient E:HL, remainder C
    LD   A, (player_data + PL_LEVEL)
    OR   A
    JR   NZ, .pl_ok
    INC  A
.pl_ok:
    LD   B, A                   ; B = pl_lvl (1..40)
    CALL _om_div_24_b           ; E:HL = xp_int, C = rem (< B)

    ; Fractional XP: add (rem * 65536) / pl_lvl to 16-bit PL_XP_FRAC_LO/HI
    PUSH DE
    PUSH HL
    LD   A, C
    OR   A
    JR   Z, .no_frac
    CALL _om_frac16_c_div_b     ; HL = (C * 65536) / B
    LD   DE, (player_data + PL_XP_FRAC_LO)
    ADD  HL, DE
    LD   (player_data + PL_XP_FRAC_LO), HL
    JR   NC, .no_frac
    POP  HL
    POP  DE
    LD   BC, 1
    ADD  HL, BC
    JR   NC, .add_xp
    INC  E
    JR   .add_xp
.no_frac:
    POP  HL
    POP  DE
.add_xp:
    LD   A, E
    OR   H
    OR   L
    CALL NZ, _om_add_xp_24

.chk_balrog:
    LD   A, (cmb_type)
    CALL monster_is_balrog_slot
    JR   NZ, .kill_done
    LD   A, (zp_game_flags)
    BIT  2, A
    JR   NZ, .kill_done
    OR   GAME_FLAG_WINNER
    LD   (zp_game_flags), A
    LD   (abi_game_flags), A
    LD   HL, _om_str_victory
    CALL msg_print_str
    CALL sound_bell

.kill_done:
    POP  IY
    POP  IX
    RET

; ============================================================================
; +30: ovl_modal_award_xp — Add 16-bit HL XP to PL_XP, update PL_MAX_XP, levelup
; Preserves: IX, IY
; ============================================================================
ovl_modal_award_xp:
    PUSH IX
    PUSH IY
    LD   A, H
    OR   L
    PUSH AF                     ; Z=1 iff called with HL==0 (XP drain / recalc)
    LD   E, 0
    CALL _om_add_xp_24
    POP  AF
    CALL Z, _om_check_leveldown
    POP  IY
    POP  IX
    RET

; ============================================================================
; +21: ovl_modal_populate_town — Spawn 4-7 random townspeople (types 32..39)
; Preserves: IX, IY
; ============================================================================
ovl_modal_populate_town:
    PUSH IX
    PUSH IY
    LD   HL, monster_table
    LD   DE, monster_table + 1
    LD   BC, (MAX_MONSTERS * MONSTER_ENTRY_SIZE) - 1
    LD   (HL), EMPTY_SLOT
    LDIR
    XOR  A
    LD   (zp_mon_count), A
    LD   (abi_mon_count), A
    CALL catalog_init_town_creatures
    LD   A, 4
    CALL rng_range
    ADD  A, 4                   ; 4..7 townspeople (core/6502/monster.s:1170)
    LD   D, A
.town_lp:
    LD   A, D
    OR   A
    JR   Z, .town_done
    LD   E, 64                  ; retry budget per townie
.town_try:
    PUSH DE
    LD   A, 64
    CALL rng_range
    INC  A
    LD   C, A                   ; x in 1..64
    LD   A, 20
    CALL rng_range
    INC  A
    LD   B, A                   ; y in 1..20

    ; Dist > 2 from (TOWN_START_X, TOWN_START_Y)
    LD   A, C
    SUB  TOWN_START_X
    JR   NC, .tdx
    NEG
.tdx:
    LD   H, A
    LD   A, B
    SUB  TOWN_START_Y
    JR   NC, .tdy
    NEG
.tdy:
    CP   H
    JR   NC, .tmax
    LD   A, H
.tmax:
    CP   3
    JR   C, .town_retry

    CALL store_door_lookup      ; must NOT be a store door
    JR   C, .town_retry

    CALL map_get_tile
    JR   C, .town_retry
    AND  (TILE_TYPE_MASK | FLAG_OCCUPIED)
    JR   NZ, .town_retry

    LD   A, TOWN_CREATURE_COUNT
    CALL rng_range              ; preserves BC
    ADD  A, TOWN_CREATURE_BASE
    CALL monster_spawn_one      ; A=cr_type, B=y, C=x -> CF=1, A=slot
    JR   NC, .town_retry

    POP  DE
    JR   .town_next

.town_retry:
    POP  DE
    DEC  E
    JR   NZ, .town_try

.town_next:
    DEC  D
    JR   .town_lp

.town_done:
    POP  IY
    POP  IX
    OR   A
    RET

; ============================================================================
; +24: ovl_modal_populate_dungeon — Populate dungeon floor monsters, rooms & win boss
; Preserves: IX, IY
; ============================================================================
ovl_modal_populate_dungeon:
    PUSH IX
    PUSH IY
    CALL catalog_reset_slots

    ; Base count = randint(8) + 14 + clamp(dlvl/3, 2, 10), capped <= 26
    LD   A, (abi_player_dlvl)
    LD   L, A
    LD   E, 0                   ; L / 3
.div3:
    LD   A, L
    CP   3
    JR   C, .div3_done
    SUB  3
    LD   L, A
    INC  E
    JR   .div3
.div3_done:
    LD   A, E
    CP   2
    JR   NC, .c_lo
    LD   A, 2
.c_lo:
    CP   11
    JR   C, .c_hi
    LD   A, 10
.c_hi:
    ADD  A, 14
    LD   B, A
    LD   A, 8
    CALL rng_range
    INC  A
    ADD  A, B
    LD   (_om_pop_rem), A

.pop_lp:
    LD   A, (zp_mon_count)
    CP   MAX_MONSTERS - CAT_GEN_RESERVE
    JR   NC, .chk_win_mon
    LD   A, (_om_pop_rem)
    OR   A
    JR   Z, .chk_win_mon
    DEC  A
    LD   (_om_pop_rem), A

    XOR  A                      ; unlimited map range
    CALL find_random_floor      ; CF=1, B=y, C=x
    JR   NC, .pop_lp
    LD   A, B
    LD   (_om_ry), A
    LD   A, C
    LD   (_om_rx), A
    PUSH BC
    CALL pick_creature_type     ; A = cr_type (clobbers BC)
    POP  BC
    LD   (_om_sr_type), A
    CALL monster_spawn_one      ; A=cr_type, B=y, C=x -> CF=1, A=slot
    JR   NC, .pop_lp

    ; Check CF_GROUP pack mates (1..3 adjacent)
    LD   A, (_om_sr_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_mflags
    ADD  HL, DE
    LD   A, (HL)
    AND  CF_GROUP
    JR   Z, .pop_lp
    LD   A, 3
    CALL rng_range
    INC  A
    LD   (_om_grp_rem), A
.grp_lp:
    LD   A, (_om_grp_rem)
    OR   A
    JR   Z, .pop_lp
    DEC  A
    LD   (_om_grp_rem), A
    LD   A, (_om_ry)
    LD   B, A
    LD   A, (_om_rx)
    LD   C, A
    CALL find_adjacent_empty_tile ; B=y, C=x -> CF=1, B=ny, C=nx
    JR   NC, .pop_lp
    LD   A, (_om_sr_type)
    CALL monster_spawn_one
    JR   NC, .pop_lp
    JR   .grp_lp

.chk_win_mon:
    LD   A, (abi_player_dlvl)
    CP   CAT_WIN_LEVEL
    JR   C, .special_rooms
    LD   A, (zp_game_flags)
    AND  GAME_FLAG_WINNER
    JR   NZ, .special_rooms

    LD   A, 2
    CALL rng_range
    OR   A
    LD   DE, CATALOG_BALROG_ID
    JR   NZ, .win_id_ok
    LD   DE, CATALOG_IGGY_ID
.win_id_ok:
    CALL catalog_slot_for_id    ; A = cr_type (0..31)
    LD   (_om_sr_type), A
    LD   D, 32
.win_try:
    PUSH DE
    XOR  A
    CALL find_random_floor      ; CF=1, B=y, C=x
    POP  DE
    JR   NC, .win_next
    CALL _om_cheb_player
    CP   MONS_MAX_SIGHT + 1
    JR   NC, .win_spawn
.win_next:
    DEC  D
    JR   NZ, .win_try
    JR   .special_rooms         ; core/6502/monster_catalog.s: abort if all 32 tries fail
.win_spawn:
    LD   A, (_om_sr_type)
    CALL monster_spawn_awake

.special_rooms:
    LD   A, (room_count)
    OR   A
    JR   Z, .pop_done
    LD   B, A
    LD   C, 0                   ; room index
.sr_lp:
    PUSH BC
    LD   B, 0
    LD   HL, room_type
    ADD  HL, BC
    LD   A, (HL)
    OR   A
    JR   Z, .sr_next
    CP   RT_PIT
    JR   Z, .do_pit
    CP   RT_NEST
    JR   Z, .do_nest
    JR   .sr_next

.do_pit:
    CALL pick_creature_type
    LD   (_om_sr_type), A
    LD   A, 5
    CALL rng_range
    ADD  A, 4                   ; 4..8
    LD   B, A
    LD   A, 1
    CALL _om_fill_room_mons
    JR   .sr_next

.do_nest:
    LD   A, (abi_player_dlvl)
    PUSH AF
    SUB  2
    JR   C, .n_dl1
    OR   A
    JR   NZ, .n_dl_ok
.n_dl1:
    LD   A, 1
.n_dl_ok:
    LD   (abi_player_dlvl), A
    LD   A, 4
    CALL rng_range
    ADD  A, 3                   ; 3..6
    LD   B, A
    XOR  A
    CALL _om_fill_room_mons
    POP  AF
    LD   (abi_player_dlvl), A

.sr_next:
    POP  BC
    INC  C
    DJNZ .sr_lp

.pop_done:
    POP  IY
    POP  IX
    OR   A
    RET

; ============================================================================
; +27: ovl_modal_place_wanderer — MON-039 ambient wanderer (>20 dist, count<26)
; Preserves: IX, IY
; ============================================================================
ovl_modal_place_wanderer:
    PUSH IX
    PUSH IY

    LD   A, (zp_mon_count)
    CP   MAX_MONSTERS - CAT_GEN_RESERVE
    JR   NC, .no_spawn

    LD   D, 32
.w_try:
    PUSH DE
    XOR  A
    CALL find_random_floor      ; CF=1, B=y, C=x
    POP  DE
    JR   NC, .w_next
    CALL _om_cheb_player
    CP   MONS_MAX_SIGHT + 1
    JR   C, .w_next

    PUSH BC
    CALL pick_creature_type     ; handles dlvl==0 town vs dungeon (clobbers BC)
    POP  BC
    CALL monster_spawn_awake
    JR   NC, .no_spawn
    LD   HL, zp_dirty_count
    INC  (HL)
    POP  IY
    POP  IX
    SCF
    RET

.w_next:
    DEC  D
    JR   NZ, .w_try

.no_spawn:
    POP  IY
    POP  IX
    OR   A
    RET

; ============================================================================
; Private Helpers for M4 Combat, XP & Population
; ============================================================================

; _om_cheb_player — Chebyshev distance between (B=y, C=x) and player -> A.
; Preserves: BC, DE
_om_cheb_player:
    LD   A, (abi_player_x)
    SUB  C
    JR   NC, .dx
    NEG
.dx:
    LD   H, A
    LD   A, (abi_player_y)
    SUB  B
    JR   NC, .dy
    NEG
.dy:
    CP   H
    RET  NC
    LD   A, H
    RET

; _om_fill_room_mons — Spawn up to B monsters inside room C.
; Input: C = room_idx, B = count, A = 1 (fixed _om_sr_type) or 0 (pick each)
; Preserves: top-of-stack room loop BC (caller pushed it)
_om_fill_room_mons:
    LD   (_om_sr_fixed), A
    LD   (_om_sr_cnt), BC       ; C=room_idx, B=count -> save B/C
    LD   A, C
    LD   E, A
    LD   D, 0
    LD   HL, room_x
    ADD  HL, DE
    LD   A, (HL)
    LD   (_om_rx), A
    LD   HL, room_y
    ADD  HL, DE
    LD   A, (HL)
    LD   (_om_ry), A
    LD   HL, room_w
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    RET  Z
    LD   (_om_rw), A
    LD   HL, room_h
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    RET  Z
    LD   (_om_rh), A

.lp:
    LD   A, (zp_mon_count)
    CP   MAX_MONSTERS - CAT_GEN_RESERVE
    RET  NC
    LD   A, (_om_sr_cnt + 1)
    OR   A
    RET  Z
    DEC  A
    LD   (_om_sr_cnt + 1), A

    LD   A, (_om_rw)
    CALL rng_range
    LD   HL, _om_rx
    ADD  A, (HL)
    LD   C, A                   ; x in rx .. rx+rw-1
    LD   A, (_om_rh)
    CALL rng_range
    LD   HL, _om_ry
    ADD  A, (HL)
    LD   B, A                   ; y in ry .. ry+rh-1

    LD   A, (abi_player_x)
    CP   C
    JR   NZ, .chk_tile
    LD   A, (abi_player_y)
    CP   B
    JR   Z, .lp
.chk_tile:
    CALL map_get_tile
    JR   C, .lp
    AND  (TILE_TYPE_MASK | FLAG_OCCUPIED)
    JR   NZ, .lp

    LD   A, (_om_sr_fixed)
    OR   A
    JR   NZ, .use_fixed
    PUSH BC
    CALL pick_creature_type     ; clobbers BC
    POP  BC
    JR   .spawn
.use_fixed:
    LD   A, (_om_sr_type)
.spawn:
    CALL monster_spawn_one
    JR   .lp

; _om_add_s8_hl — Add signed 8-bit A to 16-bit HL.
_om_add_s8_hl:
    LD   E, A
    RLCA
    SBC  A, A
    LD   D, A
    ADD  HL, DE
    RET

; _om_str15_minus_wt — Compute DE = (PL_STR_CUR * 15) - wield_weight.
; Output: CF = 1 if heavy (DE < 0), CF = 0 if >= 0. Clobbers AF, DE.
_om_str15_minus_wt:
    PUSH HL
    LD   A, (player_data + PL_STR_CUR)
    LD   L, A
    LD   H, 0
    ADD  HL, HL
    ADD  HL, HL
    ADD  HL, HL
    ADD  HL, HL                 ; * 16
    LD   E, A
    LD   D, 0
    OR   A
    SBC  HL, DE                 ; * 15
    LD   DE, (wield_weight_lo)
    OR   A
    SBC  HL, DE                 ; CF=1 if heavy
    EX   DE, HL
    POP  HL
    RET

; _om_calc_blows — Compute melee blows (1..4; 6502 combat.s + 7x6 tables.s).
_om_calc_blows:
    ; DEX bracket (0..5): <10, <19, <68, <108, <118, >=118
    LD   A, (player_data + PL_DEX_CUR)
    LD   C, 0
    CP   10
    JR   C, .col_ok
    INC  C
    CP   19
    JR   C, .col_ok
    INC  C
    CP   68
    JR   C, .col_ok
    INC  C
    CP   108
    JR   C, .col_ok
    INC  C
    CP   118
    JR   C, .col_ok
    INC  C
.col_ok:
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   FI_EMPTY
    JR   Z, .unarmed
    LD   A, (wield_missile_type)
    OR   A
    JR   NZ, .one
    LD   DE, (wield_weight_lo)
    LD   A, D
    OR   E
    JR   Z, .unarmed
    CALL _om_str15_minus_wt
    JR   C, .one

    ; ratio = (PL_STR_CUR * 10) / wield_weight_lo (weight >= 512 -> 0)
    LD   A, (wield_weight_hi)
    CP   2
    JR   NC, .row_zero
    LD   DE, (wield_weight_lo)
    LD   A, (player_data + PL_STR_CUR)
    LD   L, A
    LD   H, 0
    LD   A, 10
    PUSH BC
    PUSH DE
    CALL mul_hl_a
    POP  DE
    POP  BC
    XOR  A
.div_wt:
    OR   A
    SBC  HL, DE
    JR   C, .ratio_ok
    INC  A
    CP   9
    JR   C, .div_wt
.ratio_ok:
    ; Bracket 0..6: <2, <3, <4, <5, <7, <9, >=9
    LD   B, 0
    CP   2
    JR   C, .row_ok
    INC  B
    CP   3
    JR   C, .row_ok
    INC  B
    CP   4
    JR   C, .row_ok
    INC  B
    CP   5
    JR   C, .row_ok
    INC  B
    CP   7
    JR   C, .row_ok
    INC  B
    CP   9
    JR   C, .row_ok
    INC  B                      ; row 0..6
    JR   .row_ok
.row_zero:
    LD   B, 0
.row_ok:
    ; idx = B * 6 + C
    LD   A, B
    ADD  A, A
    ADD  A, B
    ADD  A, A
    ADD  A, C
    LD   E, A
    LD   D, 0
    LD   HL, _om_blows_tbl
    ADD  HL, DE
    LD   A, (HL)
    RET
.unarmed:
    LD   A, 2
    RET
.one:
    LD   A, 1
    RET

; _om_apply_ego_slays — Multiply/enhance damage HL using weapon ego & wield_flags.
_om_apply_ego_slays:
    LD   A, (cmb_type)
    LD   E, A
    LD   D, 0
    PUSH HL
    LD   HL, cr_mflags
    ADD  HL, DE
    LD   B, (HL)                ; B = cr_mflags
    LD   HL, cr_cdefense
    ADD  HL, DE
    LD   C, (HL)                ; C = cr_cdefense
    POP  HL

    LD   A, (inv_ego + EQUIP_WEAPON)
    AND  EGO_ID_MASK
    CP   EGO_SLAY_DRAGON
    JP   Z, .slay_drg
    CP   EGO_SLAY_UNDEAD
    JP   Z, .slay_und
    CP   EGO_SLAY_EVIL
    JP   Z, .slay_evl
    CP   EGO_SLAY_ANIMAL
    JP   Z, .slay_anm
    CP   EGO_HOLY_AVENGER
    JP   Z, .slay_ha
    CP   EGO_FLAME_TONGUE
    JP   Z, .ego_flame
    CP   EGO_FROST_BRAND
    JP   Z, .ego_frost
    CP   EGO_AMMO_FIRE
    JP   Z, .ego_flame
    CP   EGO_AMMO_SLAY_EVIL
    JP   Z, .slay_ammo_evl
    CP   EGO_DRAGON_SLAYING
    JP   Z, .slay_ammo_drg
    CP   EGO_AMMO_SLAY_ANIMAL
    JP   Z, .slay_anm

    ; Non-ego flag checks (unique/wield_flags fallback)
    LD   A, (wield_flags_1)
    AND  ITR1_SLAY_DRAGON
    JP   NZ, .slay_drg
    LD   A, (wield_flags_2)
    AND  ITR2_SLAY_UNDEAD
    JP   NZ, .slay_und
    LD   A, (wield_flags_1)
    AND  ITR1_SLAY_EVIL
    JP   NZ, .slay_evl
    LD   A, (wield_flags_1)
    AND  ITR1_SLAY_ANIMAL
    JP   NZ, .slay_anm
    LD   A, (wield_flags_2)
    AND  ITR2_FLAME_TONGUE
    JP   NZ, .ego_flame
    LD   A, (wield_flags_2)
    AND  ITR2_FROST_BRAND
    JP   NZ, .ego_frost
    RET

.slay_drg:
    BIT  4, B                   ; CF_DRAGON
    RET  Z
    ADD  HL, HL
    ADD  HL, HL
    JR   _om_clamp_dmg_255
.slay_ammo_drg:
    BIT  4, B                   ; CF_DRAGON -> x5
    RET  Z
    LD   D, H
    LD   E, L
    ADD  HL, HL
    ADD  HL, HL
    ADD  HL, DE
    JR   _om_clamp_dmg_255
.slay_ammo_evl:
    BIT  2, B                   ; CF_EVIL -> x3
    RET  Z
    JR   .mul3
.slay_und:
    BIT  1, B                   ; CF_UNDEAD
    RET  Z
.mul3:
    LD   D, H
    LD   E, L
    ADD  HL, HL
    ADD  HL, DE
    JR   _om_clamp_dmg_255
.slay_evl:
    BIT  2, B                   ; CF_EVIL
    RET  Z
    ADD  HL, HL
    JR   _om_clamp_dmg_255
.slay_anm:
    BIT  3, B                   ; CF_ANIMAL
    RET  Z
    ADD  HL, HL
    JR   _om_clamp_dmg_255
.slay_ha:
    BIT  1, B                   ; CF_UNDEAD -> x3
    JR   NZ, .mul3
    BIT  2, B                   ; CF_EVIL -> x2 (6502 ego_items.s:415-425)
    RET  Z
    ADD  HL, HL
    JR   _om_clamp_dmg_255
.ego_flame:
    BIT  1, C                   ; CD_FIRE (vulnerable to fire)
    JR   Z, .elem_2d4
    JR   .elem_15x_2d4
.ego_frost:
    BIT  0, C                   ; CD_FROST (vulnerable to frost)
    JR   Z, .elem_2d4
.elem_15x_2d4:
    LD   D, H
    LD   E, L
    SRL  D
    RR   E
    ADD  HL, DE                 ; 1.5x when vulnerable
    CALL _om_clamp_dmg_255
.elem_2d4:
    PUSH HL
    LD   B, 2
    LD   C, 4
    CALL roll_dice_bc           ; HL = +2d4 unconditional
    POP  DE
    ADD  HL, DE
_om_clamp_dmg_255:
    LD   A, H
    OR   A
    RET  Z
    LD   HL, 255
    RET

; _om_apply_critical — Roll VMS melee critical on HL damage (6502 combat.s:689-780).
_om_apply_critical:
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   FI_EMPTY
    RET  Z
    LD   A, (wield_missile_type)
    OR   A
    JR   Z, .cr_arm
    CP   4
    RET  C                      ; launcher: no melee crits
.cr_arm:
    PUSH HL                     ; save dmg
    ; chance = wield_weight + class_bth_per_lvl*PL_LEVEL + 5*signed(_om_melee_bonus)
    CALL _om_calc_lvl_bth_u8
    LD   E, A
    LD   D, 0
    LD   HL, (wield_weight_lo)
    ADD  HL, DE
    PUSH HL
    LD   A, (_om_melee_bonus)
    BIT  7, A
    JR   NZ, .cr_neg
    LD   E, A
    LD   D, 0
    LD   A, 5
    CALL mul_de_a
    POP  DE
    ADD  HL, DE
    JR   .no_w_wt
.cr_neg:
    NEG
    LD   E, A
    LD   D, 0
    LD   A, 5
    CALL mul_de_a
    EX   DE, HL
    POP  HL
    OR   A
    SBC  HL, DE
    JR   NC, .no_w_wt
    POP  HL                     ; chance <= 0 -> no crit
    RET
.no_w_wt:
    PUSH HL                     ; chance
    CALL _om_rng_u16_5000       ; HL = 0..4999
    POP  DE                     ; DE = chance
    OR   A
    SBC  HL, DE
    POP  HL                     ; HL = dmg
    RET  NC                     ; no crit if roll >= chance

    PUSH HL
    CALL _om_rng_u16_650        ; HL = 0..649
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   FI_EMPTY
    JR   Z, .no_cw
    LD   DE, (wield_weight_lo)
    ADD  HL, DE
.no_cw:
    EX   DE, HL                 ; DE = crit severity k
    POP  HL                     ; HL = dmg
    LD   A, D
    CP   (400 >> 8)
    JR   C, .c2
    JR   NZ, .chk700
    LD   A, E
    CP   (400 & 0xFF)
    JR   C, .c2
.chk700:
    LD   A, D
    CP   (700 >> 8)
    JR   C, .c3
    JR   NZ, .chk900
    LD   A, E
    CP   (700 & 0xFF)
    JR   C, .c3
.chk900:
    LD   A, D
    CP   (900 >> 8)
    JR   C, .c4
    JR   NZ, .c5
    LD   A, E
    CP   (900 & 0xFF)
    JR   C, .c4
.c5:
    LD   D, H
    LD   E, L
    ADD  HL, HL
    ADD  HL, HL
    ADD  HL, DE
    LD   DE, 20
    ADD  HL, DE
    JP   _om_clamp_dmg_255
.c4:
    ADD  HL, HL
    ADD  HL, HL
    LD   DE, 15
    ADD  HL, DE
    JP   _om_clamp_dmg_255
.c3:
    LD   D, H
    LD   E, L
    ADD  HL, HL
    ADD  HL, DE
    LD   DE, 10
    ADD  HL, DE
    JP   _om_clamp_dmg_255
.c2:
    ADD  HL, HL
    LD   DE, 5
    ADD  HL, DE
    JP   _om_clamp_dmg_255

_om_rng_u16_5000:
    LD   BC, 30000
    LD   DE, 5000
    JR   _om_rng_u16_mod

_om_rng_u16_650:
    LD   BC, 32500
    LD   DE, 650

_om_rng_u16_mod:
.rej:
    CALL rng_next_u16
    RES  7, H                   ; 0..32767
    PUSH HL
    OR   A
    SBC  HL, BC                 ; >= multiple*N -> reject for uniform distribution
    POP  HL
    JR   NC, .rej
.lp:
    OR   A
    SBC  HL, DE
    JR   NC, .lp
    ADD  HL, DE
    RET

; _om_fmt_prefix — Copy prefix string BC then monster name HL into DE.
_om_fmt_prefix:
    PUSH HL
    LD   H, B
    LD   L, C
    CALL _om_append_str
    POP  HL
_om_append_str:
    LD   A, (HL)
    OR   A
    RET  Z
    LD   (DE), A
    INC  HL
    INC  DE
    JR   _om_append_str

; _om_mul_bc_a — 16x8 unsigned BC * A -> 24-bit E:HL
_om_mul_bc_a:
    LD   HL, 0
    LD   E, 0
    LD   D, A
    LD   A, 8
.lp:
    ADD  HL, HL
    RL   E
    SLA  D
    JR   NC, .nx
    ADD  HL, BC
    JR   NC, .nx
    INC  E
.nx:
    DEC  A
    JR   NZ, .lp
    RET

; _om_div_24_b — Divide 24-bit E:HL by B (1..255) -> quotient E:HL, rem C
_om_div_24_b:
    LD   D, 24
    XOR  A                      ; A = rem
.lp:
    ADD  HL, HL
    RL   E
    RLA
    JR   C, .sub
    CP   B
    JR   C, .nx
.sub:
    SUB  B
    INC  L
.nx:
    DEC  D
    JR   NZ, .lp
    LD   C, A
    RET

; _om_frac16_c_div_b — Compute HL = (C * 65536) / B where C < B
_om_frac16_c_div_b:
    LD   HL, 0
    LD   A, C
    LD   D, 16
.lp:
    ADD  HL, HL
    ADD  A, A
    JR   C, .sub
    CP   B
    JR   C, .nx
.sub:
    SUB  B
    INC  L
.nx:
    DEC  D
    JR   NZ, .lp
    RET

; _om_add_xp_24 — Add 24-bit E:HL to PL_XP_0..2, update PL_MAX_XP, check levelups.
_om_add_xp_24:
    LD   A, (player_data + PL_XP_0)
    ADD  A, L
    LD   (player_data + PL_XP_0), A
    LD   A, (player_data + PL_XP_1)
    ADC  A, H
    LD   (player_data + PL_XP_1), A
    LD   A, (player_data + PL_XP_2)
    ADC  A, E
    JR   NC, .xp_ok
    LD   A, 0xFF
    LD   (player_data + PL_XP_0), A
    LD   (player_data + PL_XP_1), A
.xp_ok:
    LD   (player_data + PL_XP_2), A

.lvl_chk:
    LD   A, (player_data + PL_LEVEL)
    CP   40
    JR   NC, _om_sync_exit
    CALL _om_cmp_xp_thresh      ; CF=1 if PL_XP < _om_tmp24
    JR   C, _om_sync_exit

.do_lvlup:
    ; Save threshold(old_level) before incrementing level, heal to FULL HP, halve excess XP (6502 combat.s)
    LD   HL, player_data + PL_LEVEL
    INC  (HL)
    CALL player_calc_hp
    LD   HL, (player_data + PL_MHP_LO)
    LD   (player_data + PL_HP_LO), HL
    CALL player_calc_combat
    LD   A, 1
    LD   (levelup_magic_pending), A

    ; Halve excess XP above _om_tmp24: excess = (PL_XP - _om_tmp24) >> 1 (with 16-bit frac), PL_XP = thresh + excess
    LD   DE, (_om_tmp24)
    LD   A, (player_data + PL_XP_2)
    LD   B, A
    LD   HL, (player_data + PL_XP_0)
    OR   A
    SBC  HL, DE
    LD   A, (_om_tmp24 + 2)
    LD   C, A
    LD   A, B
    SBC  A, C                   ; A:HL = excess24
    SRL  A
    RR   H
    RR   L
    LD   B, A
    LD   A, (player_data + PL_XP_FRAC_HI)
    RRA
    LD   (player_data + PL_XP_FRAC_HI), A
    LD   A, (player_data + PL_XP_FRAC_LO)
    RRA
    LD   (player_data + PL_XP_FRAC_LO), A
    ADD  HL, DE
    LD   A, B
    ADC  A, C
    LD   (player_data + PL_XP_0), HL
    LD   (player_data + PL_XP_2), A

    LD   A, HSTR_CMB_LVLUP
    LD   DE, line_buf
    CALL huff_decode_string
.lvl_tilde:
    LD   A, (DE)
    OR   A
    JR   Z, .lvl_num
    CP   '~'
    JR   Z, .lvl_num
    INC  DE
    JR   .lvl_tilde
.lvl_num:
    LD   A, (player_data + PL_LEVEL)
    CALL fmt_u8_dec
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   HL, line_buf
    CALL msg_print_str
    CALL sound_bell
    JP   .lvl_chk

_om_sync_exit:
    ; Sync PL_MAX_XP = max(PL_MAX_XP, PL_XP) after any excess halving (combat.s:1128)
    LD   A, (player_data + PL_XP_2)
    LD   HL, player_data + PL_MAX_XP_2
    CP   (HL)
    JR   C, .max_ok
    JR   NZ, .upd_max2
    LD   A, (player_data + PL_XP_1)
    DEC  HL
    CP   (HL)
    JR   C, .max_ok
    JR   NZ, .upd_max2
    LD   A, (player_data + PL_XP_0)
    DEC  HL
    CP   (HL)
    JR   C, .max_ok
.upd_max2:
    LD   HL, player_data + PL_XP_0
    LD   DE, player_data + PL_MAX_XP_0
    LD   BC, 3
    LDIR
.max_ok:
    CALL player_sync_to_abi
    JP   status_mark_dirty

; _om_check_leveldown — Drop player level(s) when XP was drained below thresh(PL_LEVEL - 1) (combat.s:1133-1160)
_om_check_leveldown:
    LD   B, 0                   ; B = dropped flag
.ld_lp:
    LD   HL, player_data + PL_LEVEL
    LD   A, (HL)
    CP   2
    JR   C, .ld_done
    DEC  (HL)
    PUSH BC
    CALL _om_cmp_xp_thresh      ; CF=1 if PL_XP < thresh(PL_LEVEL - 1)
    POP  BC
    JR   C, .ld_drop
    LD   HL, player_data + PL_LEVEL
    INC  (HL)
    JR   .ld_done
.ld_drop:
    LD   B, 1
    JR   .ld_lp
.ld_done:
    LD   A, B
    OR   A
    RET  Z
    CALL player_calc_hp
    CALL player_calc_combat
    LD   A, 1
    LD   (levelup_magic_pending), A
    JR   _om_sync_exit

; _om_cmp_xp_thresh — Return CF=1 if 24-bit PL_XP < thresh(PL_LEVEL).
_om_cmp_xp_thresh:
    CALL _om_calc_xp_thresh
    LD   A, (player_data + PL_XP_2)
    LD   HL, _om_tmp24 + 2
    CP   (HL)
    RET  NZ
    LD   A, (player_data + PL_XP_1)
    DEC  HL
    CP   (HL)
    RET  NZ
    LD   A, (player_data + PL_XP_0)
    DEC  HL
    CP   (HL)
    RET

; _om_calc_xp_thresh — 24-bit threshold for current PL_LEVEL -> _om_tmp24
_om_calc_xp_thresh:
    LD   A, (player_data + PL_EXPFACT)
    OR   A
    JR   NZ, .ef_ok
    LD   A, 100
.ef_ok:
    PUSH AF                     ; save expfact
    LD   A, (player_data + PL_LEVEL)
    CP   29
    JR   NC, .late
    DEC  A
    ADD  A, A
    LD   E, A
    LD   D, 0
    LD   HL, _om_xp_early
    ADD  HL, DE
    LD   C, (HL)
    INC  HL
    LD   B, (HL)
    POP  AF
    CALL _om_mul_bc_a           ; E:HL = base16 * expfact
    LD   B, 100
    CALL _om_div_24_b           ; E:HL = / 100
    JR   .store
.late:
    SUB  29
    ADD  A, A
    LD   E, A
    LD   D, 0
    LD   HL, _om_xp_late
    ADD  HL, DE
    LD   C, (HL)
    INC  HL
    LD   B, (HL)
    POP  AF
    CALL _om_mul_bc_a
.store:
    LD   (_om_tmp24), HL
    LD   A, E
    LD   (_om_tmp24 + 2), A
    RET

_om_clamp_hl_u8:
    BIT  7, H
    JR   Z, .pos
    XOR  A
    RET
.pos:
    LD   A, H
    OR   A
    LD   A, L
    RET  Z
    LD   A, 255
    RET

_om_calc_lvl_bth_u8:
    LD   A, (player_data + PL_CLASS)
    LD   E, A
    ADD  A, A
    ADD  A, A
    ADD  A, E
    LD   E, A
    LD   D, 0
    LD   HL, class_level_adj + 0
    ADD  HL, DE
    LD   E, (HL)
    LD   A, (player_data + PL_LEVEL)
    CALL mul_de_a
    LD   A, L
    RET

; M4 Modal Combat / Population Tables & Scratch
_om_tmp24:         DB 0, 0, 0
_om_melee_bonus:   DB 0
_om_pop_rem:       DB 0
_om_grp_rem:       DB 0
_om_sr_fixed:      DB 0
_om_sr_type:       DB 0
_om_sr_cnt:        DW 0
_om_rx:            DB 0
_om_ry:            DB 0
_om_rw:            DB 0
_om_rh:            DB 0

_om_blows_tbl:
    DB 1, 1, 1, 1, 1, 1
    DB 1, 1, 1, 1, 2, 2
    DB 1, 1, 1, 2, 2, 3
    DB 1, 1, 2, 2, 3, 3
    DB 1, 2, 2, 3, 3, 4
    DB 1, 2, 2, 3, 4, 4
    DB 2, 2, 3, 3, 4, 4

_om_xp_early:
    DW 10, 25, 45, 70, 100, 140, 200, 280, 380, 500
    DW 650, 850, 1100, 1400, 1800, 2300, 2900, 3600, 4400, 5400
    DW 6800, 8400, 10200, 12500, 17500, 25000, 35000, 50000
_om_xp_late:
    DW 750, 1000, 1500, 2000, 3000, 4000, 5000, 7500, 15000, 25000, 50000

_om_str_no_wep:       DB "No weapons to exchange.", 0
_om_str_primary:      DB "Primary: ", 0
_om_str_secondary:    DB "Secondary: ", 0
_om_str_hit_pre:      DB "You hit the ", 0
_om_str_miss_pre:     DB "You miss the ", 0
_om_str_slay_pre:     DB "You have slain the ", 0
_om_str_victory:      DB "You have won! Shift+Q to claim victory.", 0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end
    SAVEBIN "ovl_modal.ovl", ovl_start, ovl_end - ovl_start
