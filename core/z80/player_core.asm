; player_core.asm — Player struct sync, stats/combat/weight calculations,
; inventory & identification management, store category filter, and 24-bit gold.
;
; Resident core module included once by platforms/z80/cpm/main.asm.
; Uses pure 0xNN hex syntax for sjasmplus v1.24.0 (DEVICE NOSLOT64K).
; All public entry points preserve IX and IY.

    IFNDEF CORE_Z80_PLAYER_CORE_ASM
    DEFINE CORE_Z80_PLAYER_CORE_ASM 1

    EXPORT player_init
    EXPORT player_sync_to_abi
    EXPORT player_sync_from_abi
    EXPORT player_weight_limit
    EXPORT player_calc_hp
    EXPORT player_sync_eq_stat_mod
    EXPORT player_clamp_stat_a
    EXPORT player_drain_stat_a
    EXPORT player_restore_stat_a
    EXPORT player_calc_combat
    EXPORT player_str_tohit_adj
    EXPORT player_str_damage_adj
    EXPORT player_dex_tohit_adj
    EXPORT player_dex_ac_adj
    EXPORT player_con_hp_adj
    EXPORT inv_init
    EXPORT inv_add_item
    EXPORT inv_add_carried
    EXPORT inv_remove_item
    EXPORT inv_consume_one
    EXPORT inv_calc_weight
    EXPORT inv_compact
    EXPORT id_is_known
    EXPORT id_mark_known
    EXPORT id_refresh_fixed_known
    EXPORT id_init_flavours
    EXPORT store_check_category
    EXPORT si_match_inv
    EXPORT si_find_match
    EXPORT si_copy_from_inv
    EXPORT si_compact_store
    EXPORT player_add_gold_24
    EXPORT player_sub_gold_24
    EXPORT player_cmp_gold_24

; ============================================================
; player_init — Zero player_data, background, zp_state, combat state, & inventory.
; Output: initialized clean character/world state
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ============================================================
player_init:
    LD   HL, player_data
    LD   DE, player_data + 1
    LD   BC, PL_STRUCT_SIZE - 1
    LD   (HL), 0
    LDIR

    ; Spell order slots default to 99 (empty)
    LD   HL, player_data + PL_SPELL_ORDER
    LD   DE, player_data + PL_SPELL_ORDER + 1
    LD   BC, 31
    LD   (HL), 99
    LDIR

    LD   HL, player_background
    LD   DE, player_background + 1
    LD   BC, PL_BG_SIZE - 1
    LD   (HL), 0
    LDIR

    LD   HL, zp_state
    LD   DE, zp_state + 1
    LD   BC, ZP_STATE_SIZE - 1
    LD   (HL), 0
    LDIR
    LD   A, 0xFF
    LD   (zp_run_dir), A

    XOR  A
    LD   (eff_fear_timer), A
    LD   (wizard_wall_walk_active), A
    LD   (level_force_regen), A
    LD   (pcc_eq_tohit), A
    LD   (pcc_eq_todam), A
    LD   (pcc_eq_ac), A
    LD   (pcc_ac_accum), A

    LD   HL, player_pflags
    LD   DE, player_pflags + 1
    LD   BC, 11
    LD   (HL), A
    LDIR

    CALL inv_init
    JR   player_sync_to_abi

; ============================================================
; player_sync_to_abi — Mirror player_data & zp_state fields into z80_state.
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
player_sync_to_abi:
    LD   HL, (zp_turn)
    LD   (abi_turn), HL
    LD   A, (zp_game_flags)
    LD   (abi_game_flags), A

    LD   A, (player_data + PL_MAP_X)
    LD   (abi_player_x), A
    LD   A, (player_data + PL_MAP_Y)
    LD   (abi_player_y), A
    LD   A, (player_data + PL_DLEVEL)
    LD   (abi_player_dlvl), A
    LD   A, (player_data + PL_LEVEL)
    LD   (abi_player_lvl), A

    LD   HL, (player_data + PL_HP_LO)
    LD   (abi_player_hp), HL
    LD   HL, (player_data + PL_MHP_LO)
    LD   (abi_player_mhp), HL
    LD   A, (player_data + PL_MANA)
    LD   (abi_player_mp), A
    LD   A, (player_data + PL_MAX_MANA)
    LD   (abi_player_mmp), A

    LD   A, (player_data + PL_HUNGER)
    LD   (zp_hunger_state), A
    LD   (abi_hunger_state), A
    LD   A, (player_data + PL_LIGHT_RAD)
    LD   (zp_light_radius), A
    LD   (abi_light_rad), A

    LD   A, (zp_mon_count)
    LD   (abi_mon_count), A
    LD   A, (zp_item_count)
    LD   (abi_item_count), A
    LD   A, (zp_death_source)
    LD   (abi_death_source), A
    RET

; ============================================================
; player_sync_from_abi — Copy mutable z80_state fields back into player_data & zp_state.
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
player_sync_from_abi:
    LD   HL, (abi_turn)
    LD   (zp_turn), HL
    LD   A, (abi_game_flags)
    LD   (zp_game_flags), A

    LD   A, (abi_player_x)
    LD   (player_data + PL_MAP_X), A
    LD   A, (abi_player_y)
    LD   (player_data + PL_MAP_Y), A
    LD   A, (abi_player_dlvl)
    LD   (player_data + PL_DLEVEL), A
    LD   A, (abi_player_lvl)
    LD   (player_data + PL_LEVEL), A

    LD   HL, (abi_player_hp)
    LD   (player_data + PL_HP_LO), HL
    LD   HL, (abi_player_mhp)
    LD   (player_data + PL_MHP_LO), HL
    LD   A, (abi_player_mp)
    LD   (player_data + PL_MANA), A
    LD   A, (abi_player_mmp)
    LD   (player_data + PL_MAX_MANA), A

    LD   A, (abi_hunger_state)
    LD   (zp_hunger_state), A
    LD   (player_data + PL_HUNGER), A
    LD   A, (abi_light_rad)
    LD   (zp_light_radius), A
    LD   (player_data + PL_LIGHT_RAD), A

    LD   A, (abi_mon_count)
    LD   (zp_mon_count), A
    LD   A, (abi_item_count)
    LD   (zp_item_count), A
    LD   A, (abi_death_source)
    LD   (zp_death_source), A
    RET

; ============================================================
; Stat Adjustment Helpers (matching core/6502/player.s thresholds)
; All preserve BC, DE, HL, IX, IY. Input: A = stat (3..118), Output: A = signed byte.
; ============================================================
player_str_tohit_adj:
    CALL _player_stat_lut
    DB   (-3 & 0xFF), 4, 5, 7, 18, 94, 109, 117, 0xFF

player_str_damage_adj:
    CALL _player_stat_lut
    DB   (-2 & 0xFF), 4, 5, 16, 17, 18, 94, 109, 117, 0xFF

player_dex_tohit_adj:
    CALL _player_stat_lut
    DB   (-3 & 0xFF), 4, 6, 8, 16, 17, 18, 69, 118, 0xFF

player_dex_ac_adj:
    CALL _player_stat_lut
    DB   (-4 & 0xFF), 4, 5, 6, 7, 15, 18, 59, 94, 117, 0xFF

player_con_hp_adj:
    CALL _player_stat_lut
    DB   (-4 & 0xFF), 4, 5, 6, 7, 17, 18, 94, 117, 0xFF

; _player_stat_lut — Walk inline [base_adj, thresh0, ..., 0xFF] following CALL.
; Input:  A = stat (3..118). Output: A = signed adjustment.
; Preserves: BC, DE, HL, IX, IY (returns directly to caller of player_*_adj).
_player_stat_lut:
    EX   (SP), HL
    PUSH BC
    LD   C, A
    LD   B, (HL)
.lp:
    INC  HL
    LD   A, (HL)
    CP   0xFF
    JR   Z, .hit
    LD   A, C
    CP   (HL)
    JR   C, .hit
    INC  B
    JR   .lp
.hit:
    LD   A, B
    POP  BC
    POP  HL
    RET

; ============================================================
; player_weight_limit — Compute carrying capacity in 0.1 lb units.
; Formula: min(PLAYER_WEIGHT_CAP=3000, PL_STR_CUR * 130 + PL_WEIGHT)
; Output: HL = weight limit (0..3000)
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
player_weight_limit:
    LD   A, (player_data + PL_STR_CUR)
    LD   H, 0
    LD   L, A
    LD   A, 130
    CALL mul_hl_a               ; HL = PL_STR_CUR * 130 (<= 15,340)
    LD   A, (player_data + PL_WEIGHT)
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    LD   DE, PLAYER_WEIGHT_CAP + 1
    PUSH HL
    OR   A
    SBC  HL, DE
    POP  HL
    RET  C
    LD   HL, PLAYER_WEIGHT_CAP
    RET

; ============================================================
; player_calc_hp — Recompute PL_MHP from Race/Class HD, Level, & CON.
; Clamps current HP down to MHP only if HP > MHP.
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
player_calc_hp:
    LD   A, (player_data + PL_RACE)
    CP   RACE_COUNT
    JR   C, .race_ok
    XOR  A
.race_ok:
    LD   E, A
    LD   D, 0
    LD   HL, .race_hd_tbl
    ADD  HL, DE
    LD   C, (HL)                ; C = race HD

    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .cls_ok
    XOR  A
.cls_ok:
    LD   E, A
    LD   HL, .class_hd_tbl
    ADD  HL, DE
    LD   A, (HL)
    ADD  A, C
    LD   C, A                   ; C = combined hit_die

    LD   A, (player_data + PL_CON_CUR)
    CALL player_con_hp_adj      ; A = signed CON adj
    LD   B, A                   ; B = con_adj
    LD   A, C
    SRL  A                      ; hit_die / 2
    ADD  A, B                   ; signed result
    BIT  7, A
    JR   NZ, .min1
    OR   A
    JR   NZ, .hp_lvl_ok
.min1:
    LD   A, 1
.hp_lvl_ok:
    LD   E, A                   ; E = hp_per_lvl
    LD   D, 0
    LD   A, (player_data + PL_LEVEL)
    OR   A
    JR   Z, .lvl1
    DEC  A
.lvl1:
    CALL mul_de_a               ; HL = (level - 1) * hp_per_lvl
    LD   E, C
    LD   D, 0
    ADD  HL, DE                 ; HL = max HP
    LD   (player_data + PL_MHP_LO), HL
    LD   (abi_player_mhp), HL

    ; Clamp HP <= MHP
    EX   DE, HL                 ; DE = MHP
    LD   HL, (player_data + PL_HP_LO)
    OR   A
    SBC  HL, DE
    JR   C, .sync_ret
    LD   (player_data + PL_HP_LO), DE
    LD   (abi_player_hp), DE
.sync_ret:
    RET

.race_hd_tbl:
    DB   10, 9, 8, 6, 7, 9, 10, 12
.class_hd_tbl:
    DB   9, 0, 2, 6, 4, 6

; ============================================================
; player_clamp_stat_a — Clamp raw stat byte A to [3..118] & return residual.
; Input:  A = raw stat value (0xC0..0xFF treated as negative underflow)
; Output: A = clamped stat [3..118], E = signed residual (raw - clamped)
; Preserves: BC, HL, IX, IY (clobbers AF, D, E)
; ============================================================
player_clamp_stat_a:
    LD   D, A
    CP   0xC0
    JR   NC, .c_min
    CP   3
    JR   NC, .c_chkmax
.c_min:
    LD   A, 3
    JR   .c_done
.c_chkmax:
    CP   119
    JR   C, .c_done
    LD   A, 118
.c_done:
    LD   E, A
    LD   A, D
    SUB  E
    LD   D, E
    LD   E, A
    LD   A, D
    RET

; ============================================================
; player_sync_eq_stat_mod — Recompute signed equipment deltas player_eq_stat_mod[0..5].
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
player_sync_eq_stat_mod:
    LD   HL, player_eq_stat_mod
    LD   B, STAT_COUNT
    XOR  A
.z_mod:
    LD   (HL), A
    INC  HL
    DJNZ .z_mod

    LD   C, EQUIP_WEAPON
.eq_loop:
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .eq_next
    LD   HL, inv_p1
    ADD  HL, BC
    LD   A, (HL)                ; A = inv_p1[C]
    OR   A
    JR   Z, .eq_next
    LD   D, A                   ; D = p1 mod
    CALL _equip_stat_mask_c     ; A = 6-bit mask (preserves BC, DE)
    OR   A
    JR   Z, .eq_next
    LD   E, A
    LD   HL, player_eq_stat_mod
    PUSH BC
    LD   B, STAT_COUNT
.bit_loop:
    RRC  E
    JR   NC, .bit_skip
    LD   A, (HL)
    ADD  A, D
    LD   (HL), A
.bit_skip:
    INC  HL
    DJNZ .bit_loop
    POP  BC
.eq_next:
    INC  C
    LD   A, C
    CP   EQUIP_END
    JR   C, .eq_loop
    RET

; _player_healthy_c — Compute healthy (PL_*_BASE[C] + player_eq_stat_mod[C]).
; Output: A = clamped healthy stat, E = healthy signed residual. Preserves BC, IX, IY.
_player_healthy_c:
    LD   E, C
    LD   D, 0
    LD   HL, player_data + PL_STR_BASE
    ADD  HL, DE
    LD   A, (HL)
    LD   HL, player_eq_stat_mod
    ADD  HL, DE
    ADD  A, (HL)
    JR   player_clamp_stat_a

; ============================================================
; player_drain_stat_a — Drain PL_*_CUR[A] (0..5) by one Umoria step without
; touching PL_*_BASE. Updates combat/HP/ABI/status when lowered.
; Input:  A = stat index (0..5)
; Output: CF = 1 if drained, CF = 0 if unchanged (< 4)
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
player_drain_stat_a:
    LD   C, A
    LD   B, 0
    LD   HL, player_data + PL_STR_CUR
    ADD  HL, BC
    LD   A, (HL)
    CP   4
    JR   NC, .can
    OR   A
    RET
.can:
    CP   118
    JR   NZ, .dec_cur
    PUSH HL
    LD   HL, player_stat_res
    ADD  HL, BC
    LD   A, (HL)
    BIT  7, A
    JR   NZ, .reload
    OR   A
    JR   Z, .reload
    DEC  (HL)
    POP  HL
    JR   .sync
.reload:
    POP  HL
    LD   A, 118
.dec_cur:
    CP   109
    JR   NC, .sub1
    CP   88
    JR   NC, .hi88
    CP   19
    JR   C, .sub1
    LD   D, A
    LD   A, 15
    CALL rng_range
    ADD  A, 6
    JR   .sub_chk
.hi88:
    LD   D, A
    LD   A, 6
    CALL rng_range
    ADD  A, 3
.sub_chk:
    LD   E, A
    LD   A, D
    SUB  E
    JR   C, .clamp18
    CP   19
    JR   NC, .wr
.clamp18:
    LD   A, 18
    JR   .wr
.sub1:
    DEC  A
.wr:
    LD   (HL), A
    LD   HL, player_stat_res
    ADD  HL, BC
    LD   (HL), 0
.sync:
    LD   A, C
    CP   STAT_CON
    CALL Z, player_calc_hp
    CALL player_calc_combat
    CALL status_mark_dirty
    SCF
    RET

; ============================================================
; player_restore_stat_a — Restore PL_*_CUR[A] (0..5, or 0xFF = all) to
; healthy max (PL_*_BASE + player_eq_stat_mod) without wiping other drains.
; Output: CF = 1 if any stat raised, CF = 0 if none needed restore.
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
player_restore_stat_a:
    LD   B, A                   ; B = target (0..5 or 0xFF)
    LD   C, 0                   ; C = loop stat index 0..5
    LD   D, 0                   ; D = restored_any (0 or 1)
.lp:
    LD   A, B
    CP   0xFF
    JR   Z, .chk_one
    CP   C
    JR   NZ, .nx
.chk_one:
    PUSH DE                     ; save D = restored_any
    CALL _player_healthy_c      ; A = healthy_cur, E = healthy_res (B, C preserved)
    LD   D, A                   ; D = healthy_cur, E = healthy_res
    PUSH BC                     ; save target B and idx C
    LD   B, 0
    LD   HL, player_data + PL_STR_CUR
    ADD  HL, BC
    LD   A, (HL)
    CP   D
    JR   C, .do_wr
    JR   NZ, .skip_wr
    LD   HL, player_stat_res
    ADD  HL, BC
    LD   A, (HL)
    XOR  0x80
    LD   B, A
    LD   A, E
    XOR  0x80
    CP   B
    JR   C, .skip_wr
    JR   Z, .skip_wr
    LD   B, 0
    LD   HL, player_data + PL_STR_CUR
    ADD  HL, BC
.do_wr:
    LD   (HL), D
    LD   B, 0
    LD   HL, player_stat_res
    ADD  HL, BC
    LD   (HL), E
    POP  BC
    POP  DE
    SET  0, D
    LD   A, C
    CP   STAT_CON
    JR   NZ, .nx
    SET  1, D
    JR   .nx
.skip_wr:
    POP  BC
    POP  DE
.nx:
    INC  C
    LD   A, C
    CP   STAT_COUNT
    JR   C, .lp
    LD   A, D
    OR   A
    RET  Z
    BIT  1, A
    CALL NZ, player_calc_hp
    CALL player_calc_combat
    CALL status_mark_dirty
    SCF
    RET


; _equip_stat_mask_c — Slot C -> A = 6-bit stat mask. Preserves BC, DE.
_equip_stat_mask_c:
    PUSH DE
    LD   D, 0
    LD   E, C
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    LD   E, A
    AND  EGO_ID_MASK
    JR   Z, .chk_item
    LD   HL, .ego_ids
    LD   D, .ego_ids_end - .ego_ids
.ego_lp:
    CP   (HL)
    JR   Z, .ego_hit
    INC  HL
    DEC  D
    JR   NZ, .ego_lp
.chk_item:
    BIT  6, E                   ; ITEM_PAGE_BIT
    JR   Z, .none
    LD   E, C
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    LD   HL, .p1_ids
    LD   D, .p1_ids_end - .p1_ids
.p1_lp:
    CP   (HL)
    JR   Z, .p1_hit
    INC  HL
    DEC  D
    JR   NZ, .p1_lp
.none:
    XOR  A
    POP  DE
    RET
.ego_hit:
    LD   DE, .ego_ids_end - .ego_ids
    ADD  HL, DE
    LD   A, (HL)
    POP  DE
    RET
.p1_hit:
    LD   DE, .p1_ids_end - .p1_ids
    ADD  HL, DE
    LD   A, (HL)
    POP  DE
    RET

.ego_ids:
    DB   EGO_HOLY_AVENGER, EGO_MAGI, EGO_CLUMSINESS, EGO_WEAKNESS
    DB   EGO_INTELLIGENCE, EGO_WISDOM, EGO_MIGHT, EGO_LORDLINESS
    DB   EGO_BEAUTY, EGO_STUPIDITY, EGO_DULLNESS, EGO_UGLINESS
.ego_ids_end:
.ego_masks:
    DB   0x01, 0x02, 0x08, 0x01, 0x02, 0x04, 0x19, 0x24, 0x20, 0x02, 0x04, 0x20
.p1_ids:
    DB   ITEM_SLOT_RING_OF_STRENGTH, ITEM_SLOT_AMULET_OF_WISDOM, ITEM_SLOT_AMULET_OF_THE_MAGI
    DB   ITEM_SLOT_AMULET_OF_CHARISMA, ITEM_SLOT_AMULET_OF_DOOM
    DB   ITEM_SLOT_RING_OF_WEAKNESS, ITEM_SLOT_RING_OF_STUPIDITY, ITEM_SLOT_RING_OF_GAIN_INTELLIGENCE
    DB   ITEM_SLOT_RING_OF_GAIN_DEXTERITY, ITEM_SLOT_RING_OF_GAIN_CONSTITUTION, ITEM_SLOT_RING_OF_WOE
.p1_ids_end:
.p1_masks:
    DB   0x01, 0x04, 0x02, 0x20, 0x3F, 0x01, 0x02, 0x02, 0x08, 0x10, 0x24

; ============================================================
; player_calc_combat — Recompute tohit, todam, AC, blows, weight limit, & sync ABI.
; Output: HL = carrying weight limit (0.1 lb)
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
player_calc_combat:
    ; Accumulate equipment combat bonuses from weapon + rings + gloves/cloak
    XOR  A
    LD   (pcc_eq_tohit), A
    LD   (pcc_eq_todam), A
    LD   (pcc_eq_ac), A

    ; Weapon slot (tohit/todam always added; Defender/Holy Avenger add inv_to_ac)
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   FI_EMPTY
    JR   Z, .chk_rings
    LD   A, (inv_to_hit + EQUIP_WEAPON)
    LD   (pcc_eq_tohit), A
    LD   A, (inv_to_dam + EQUIP_WEAPON)
    LD   (pcc_eq_todam), A
    LD   A, (inv_ego + EQUIP_WEAPON)
    AND  EGO_ID_MASK
    LD   B, 5
    CP   EGO_DEFENDER
    JR   Z, .wpn_ac
    LD   B, 3
    CP   EGO_HOLY_AVENGER
    JR   NZ, .chk_rings
.wpn_ac:
    LD   A, B
    LD   (pcc_eq_ac), A
.chk_rings:
    LD   C, EQUIP_RING
    CALL _pcc_add_combat_ring
    LD   C, EQUIP_RING2
    CALL _pcc_add_combat_ring

    LD   A, (inv_item_id + EQUIP_HANDS)
    CP   FI_EMPTY
    JR   Z, .chk_cloak
    LD   A, (inv_ego + EQUIP_HANDS)
    AND  EGO_ID_MASK
    CP   EGO_SLAYING
    LD   C, EQUIP_HANDS
    CALL Z, _pcc_add_slot_hit_dam
.chk_cloak:
    LD   A, (inv_item_id + EQUIP_CLOAK)
    CP   FI_EMPTY
    JR   Z, .calc_totals
    LD   A, (inv_ego + EQUIP_CLOAK)
    AND  EGO_ID_MASK
    CP   EGO_ENVELOPING
    LD   C, EQUIP_CLOAK
    CALL Z, _pcc_add_slot_hit_dam

.calc_totals:
    LD   A, (player_data + PL_STR_CUR)
    CALL player_str_tohit_adj
    LD   C, A
    LD   A, (player_data + PL_DEX_CUR)
    CALL player_dex_tohit_adj
    ADD  A, C
    LD   HL, pcc_eq_tohit
    ADD  A, (HL)
    LD   (player_data + PL_TOHIT), A

    LD   A, (player_data + PL_STR_CUR)
    CALL player_str_damage_adj
    LD   HL, pcc_eq_todam
    ADD  A, (HL)
    LD   (player_data + PL_TODMG), A

    ; AC = DEX_AC + sum_{EQUIP_BODY..EQUIP_CLOAK}(base_ac + inv_to_ac)
    LD   A, (player_data + PL_DEX_CUR)
    CALL player_dex_ac_adj
    LD   (pcc_ac_accum), A

    LD   C, EQUIP_BODY
.ac_loop:
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .ac_next
    LD   D, A
    LD   HL, inv_ego
    ADD  HL, BC
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, D
    CALL item_get_base_ac_a
    CALL _pcc_ac_add
    LD   HL, inv_to_ac
    ADD  HL, BC
    LD   A, (HL)
    CALL _pcc_ac_add
.ac_next:
    INC  C
    LD   A, C
    CP   EQUIP_END
    JR   C, .ac_loop

    LD   A, (pcc_ac_accum)
    BIT  7, A
    JR   Z, .ac_pos
    XOR  A
    JR   .ac_store
.ac_pos:
    CP   61
    JR   C, .ac_store
    LD   A, 60
.ac_store:
    LD   HL, pcc_eq_ac
    ADD  A, (HL)
    LD   (player_data + PL_AC), A

    LD   A, 1
    LD   (player_data + PL_BLOWS), A
    CALL player_sync_to_abi
    JP   player_weight_limit

; Ring combat bonus check for EQUIP_RING / EQUIP_RING2
_pcc_add_combat_ring:
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    RET  Z
    LD   HL, inv_ego
    ADD  HL, BC
    BIT  6, (HL)                ; Page 1 check
    RET  Z
    CP   ITEM_SLOT_RING_OF_SLAYING
    JR   Z, _pcc_add_slot_hit_dam
    CP   ITEM_SLOT_RING_OF_INCREASE_DAMAGE
    JR   Z, _pcc_add_slot_hit_dam
    CP   ITEM_SLOT_RING_OF_INCREASE_TO_HIT
    RET  NZ
_pcc_add_slot_hit_dam:
    LD   B, 0
    LD   HL, inv_to_hit
    ADD  HL, BC
    LD   A, (pcc_eq_tohit)
    ADD  A, (HL)
    LD   (pcc_eq_tohit), A
    LD   HL, inv_to_dam
    ADD  HL, BC
    LD   A, (pcc_eq_todam)
    ADD  A, (HL)
    LD   (pcc_eq_todam), A
    RET

; Signed saturating addition: pcc_ac_accum += A (clamped [-128, +127]). Preserves BC.
_pcc_ac_add:
    LD   HL, pcc_ac_accum
    ADD  A, (HL)
    JP   PE, .ovf
    LD   (HL), A
    RET
.ovf:
    ; Signed overflow: CF == 1 means previous signs both negative -> -128 (0x80)
    LD   A, 0x7F
    ADC  A, 0
    LD   (HL), A
    RET

; ============================================================
; Inventory Management (0..21 Carried, 22..33 Equipped)
; ============================================================

; inv_init — Clear all 34 inventory/equipment slots and weight.
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
inv_init:
    LD   HL, inv_item_id
    LD   DE, inv_item_id + 1
    LD   BC, TOTAL_INV_SLOTS - 1
    LD   (HL), FI_EMPTY
    LDIR
    LD   HL, inv_qty
    LD   DE, inv_qty + 1
    LD   BC, (TOTAL_INV_SLOTS * 7) - 1
    LD   (HL), 0
    LDIR
    XOR  A
    LD   (inven_weight_lo), A
    LD   (inven_weight_hi), A
    ASSERT player_eq_stat_mod == (player_stat_res + STAT_COUNT)
    LD   HL, player_stat_res
    LD   B, STAT_COUNT * 2
.zr:
    LD   (HL), A
    INC  HL
    DJNZ .zr
    RET

; Helper: _inv_slot_weight(A = id, B = qty, C = ego_byte) -> HL = 16-bit weight,
; CF = 1 if >= 65536 (or catalog error). Preserves IX, IY.
_inv_slot_weight:
    PUSH BC
    LD   D, A                   ; D = slot_lo
    LD   A, C
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, D
    CALL icat_select_id
    JR   C, .err
    CALL icat_get_weight        ; HL = unit weight (0.1 lb)
    JR   C, .err
    POP  BC                     ; B = qty, C = ego
    PUSH BC
    LD   A, C
    AND  EGO_ID_MASK
    CP   EGO_GREAT_MASS
    JR   NZ, .no_double
    ADD  HL, HL
    JR   C, .err
.no_double:
    ; 16x8 unsigned multiply HL * B with overflow carry check
    EX   DE, HL                 ; DE = unit_wt
    LD   HL, 0
    LD   A, B
    OR   A
    JR   Z, .ok                 ; qty 0 -> wt 0
    LD   B, 8
.mloop:
    ADD  HL, HL
    JR   C, .err
    RLCA
    JR   NC, .mskip
    ADD  HL, DE
    JR   C, .err
.mskip:
    DJNZ .mloop
.ok:
    POP  BC
    OR   A
    RET
.err:
    POP  BC
    LD   HL, 0xFFFF
    SCF
    RET

; inv_calc_weight — Recompute 16-bit inven_weight_lo/hi across all 34 slots.
; Output: HL = total weight (0.1 lb, saturated at 0xFFFF)
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
inv_calc_weight:
    LD   HL, 0
    LD   (inven_weight_lo), HL
    LD   C, 0
.loop:
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .next
    LD   D, A
    LD   HL, inv_qty
    ADD  HL, BC
    LD   A, (HL)
    OR   A
    JR   Z, .next
    LD   E, A                   ; E = qty
    LD   HL, inv_ego
    ADD  HL, BC                 ; B is still 0!
    LD   A, (HL)
    PUSH BC
    LD   B, E                   ; B = qty
    LD   C, A                   ; C = ego
    LD   A, D                   ; A = item_id
    CALL _inv_slot_weight       ; HL = slot weight, CF = overflow
    JR   C, .sat
    EX   DE, HL
    LD   HL, (inven_weight_lo)
    ADD  HL, DE
    JR   C, .sat
    LD   (inven_weight_lo), HL
    POP  BC
.next:
    INC  C
    LD   A, C
    CP   TOTAL_INV_SLOTS
    JR   C, .loop
    LD   HL, (inven_weight_lo)
    RET
.sat:
    POP  BC
    LD   HL, 0xFFFF
    LD   (inven_weight_lo), HL
    RET

; inv_compact — Compact carried pack slots 0..MAX_INV_SLOTS-1 preserving order.
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
inv_compact:
    LD   D, 0                   ; D = write index
    LD   E, 0                   ; E = read index
.scan:
    LD   B, 0
    LD   C, E
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .skip
    LD   A, D
    CP   E
    JR   Z, .adv
    ; Copy all 8 SoA bytes from slot E (C) to slot D
    PUSH DE
    LD   B, 8
    LD   HL, inv_item_id
    LD   A, E
    LD   E, D
    LD   D, A                   ; D=src, E=dst
.cp8:
    PUSH HL
    LD   A, L
    ADD  A, D
    LD   L, A
    JR   NC, .nc1
    INC  H
.nc1:
    LD   A, (HL)
    POP  HL
    PUSH HL
    PUSH AF
    LD   A, L
    ADD  A, E
    LD   L, A
    JR   NC, .nc2
    INC  H
.nc2:
    POP  AF
    LD   (HL), A
    POP  HL
    PUSH DE
    LD   DE, TOTAL_INV_SLOTS
    ADD  HL, DE
    POP  DE
    DJNZ .cp8
    POP  DE
.adv:
    INC  D
.skip:
    INC  E
    LD   A, E
    CP   MAX_INV_SLOTS
    JR   C, .scan

    ; Clear remaining trailing slots [D..MAX_INV_SLOTS-1]
.clr:
    LD   A, D
    CP   MAX_INV_SLOTS
    RET  NC
    LD   C, A
    CALL _inv_clear_slot_c
    INC  D
    JR   .clr

; Clear all 8 arrays at slot C. Preserves BC, DE.
_inv_clear_slot_c:
    PUSH BC
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   (HL), FI_EMPTY
    LD   B, 7
    XOR  A
.lp:
    PUSH DE
    LD   DE, TOTAL_INV_SLOTS
    ADD  HL, DE
    POP  DE
    LD   (HL), A
    DJNZ .lp
    POP  BC
    RET

; _inv_write_fi_add_to_c — Copy fi_add_* metadata into inventory slot C. Preserves BC.
_inv_write_fi_add_to_c:
    PUSH BC
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   DE, TOTAL_INV_SLOTS
    LD   A, (fi_add_id)
    LD   (HL), A
    ADD  HL, DE
    LD   A, (fi_add_qty)
    LD   (HL), A
    ADD  HL, DE
    LD   A, (fi_add_p1)
    LD   (HL), A
    ADD  HL, DE
    LD   A, (fi_add_to_hit)
    LD   (HL), A
    ADD  HL, DE
    LD   A, (fi_add_to_dam)
    LD   (HL), A
    ADD  HL, DE
    LD   A, (fi_add_to_ac)
    LD   (HL), A
    ADD  HL, DE
    LD   A, (fi_add_flags)
    AND  ITEM_META_FLAGS_MASK
    LD   (HL), A
    ADD  HL, DE
    LD   A, (fi_add_ego)
    LD   (HL), A
    POP  BC
    RET

; inv_add_item — Add fi_add_* item into carried pack (0..21), stacking when eligible.
; Input:  fi_add_id, fi_add_qty, fi_add_p1, fi_add_to_hit/dam/ac, fi_add_flags, fi_add_ego
; Output: CF = 1 & A = slot (0..21) on success; CF = 0 if pack full
; Preserves: IX, IY (clobbers BC, DE, HL)
inv_add_item:
    LD   A, (fi_add_qty)
    OR   A
    JR   Z, .full               ; reject qty=0
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (fi_add_id)
    CP   FI_EMPTY
    JR   Z, .full
    CALL item_stacks_a
    JR   NC, .find_empty

    ; Check carried slots 0..21 for stackable match
    LD   C, 0
.match:
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (fi_add_id)
    CP   (HL)
    JR   NZ, .m_next
    LD   DE, TOTAL_INV_SLOTS
    ADD  HL, DE                 ; inv_qty
    LD   A, (fi_add_qty)
    ADD  A, (HL)
    JR   C, .m_next             ; qty overflow (> 255)
    LD   D, A                   ; D = summed qty
    PUSH DE
    LD   DE, TOTAL_INV_SLOTS
    ADD  HL, DE                 ; inv_p1
    LD   A, (fi_add_p1)
    CP   (HL)
    JR   NZ, .m_pop_next
    ADD  HL, DE                 ; inv_to_hit
    LD   A, (fi_add_to_hit)
    CP   (HL)
    JR   NZ, .m_pop_next
    ADD  HL, DE                 ; inv_to_dam
    LD   A, (fi_add_to_dam)
    CP   (HL)
    JR   NZ, .m_pop_next
    ADD  HL, DE                 ; inv_to_ac
    ADD  HL, DE                 ; inv_flags
    ADD  HL, DE                 ; inv_ego
    LD   A, (fi_add_ego)
    CP   (HL)
    JR   NZ, .m_pop_next
    POP  DE
    LD   B, 0
    LD   HL, inv_qty
    ADD  HL, BC
    LD   (HL), D
    JR   .added
.m_pop_next:
    POP  DE
.m_next:
    INC  C
    LD   A, C
    CP   MAX_INV_SLOTS
    JR   C, .match

.find_empty:
    LD   C, 0
.escan:
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .put_empty
    INC  C
    LD   A, C
    CP   MAX_INV_SLOTS
    JR   C, .escan
.full:
    XOR  A
    OR   A                      ; CF = 0
    RET
.put_empty:
    CALL _inv_write_fi_add_to_c
.added:
    PUSH BC
    CALL inv_calc_weight
    POP  BC
    LD   A, C
    SCF                         ; CF = 1, A = slot
    RET

; inv_add_carried — Weight-checked inv_add_item matching VMS inven_check_weight.
; Input:  fi_add_* staged
; Output: CF = 1 & A = slot on success;
;         CF = 0 & A = HSTR_UIS_TOO_HEAVY or HSTR_UIS_PACK_FULL on refusal
; Preserves: IX, IY (clobbers BC, DE, HL)
inv_add_carried:
    LD   A, (fi_add_id)
    LD   HL, fi_add_qty
    LD   B, (HL)
    LD   HL, fi_add_ego
    LD   C, (HL)
    CALL _inv_slot_weight       ; HL = added weight, CF = overflow
    JR   C, .too_heavy
    LD   DE, (inven_weight_lo)
    ADD  HL, DE
    JR   C, .too_heavy          ; 16-bit candidate sum overflow
    PUSH HL                     ; [cand_wt]
    CALL player_weight_limit    ; HL = weight_limit
    POP  DE                     ; DE = cand_wt
    OR   A
    SBC  HL, DE                 ; limit - cand_wt; borrow => too heavy
    JR   C, .too_heavy
    CALL inv_add_item
    RET  C
    LD   A, HSTR_UIS_PACK_FULL
    OR   A                      ; CF = 0
    RET
.too_heavy:
    LD   A, HSTR_UIS_TOO_HEAVY
    OR   A                      ; CF = 0
    RET

; inv_remove_item — Remove slot A (0..33), compacting carried pack if A < 22.
; Input:  A = slot index
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
inv_remove_item:
    CP   TOTAL_INV_SLOTS
    RET  NC
    LD   C, A
    CALL _inv_clear_slot_c
    LD   A, C
    CP   MAX_INV_SLOTS
    CALL C, inv_compact
    JP   inv_calc_weight

; inv_consume_one — Decrement qty in slot A or remove slot if qty <= 1.
; Input:  A = slot index
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
inv_consume_one:
    CP   TOTAL_INV_SLOTS
    RET  NC
    LD   C, A
    LD   B, 0
    LD   HL, inv_qty
    ADD  HL, BC
    LD   A, (HL)
    CP   2
    LD   A, C
    JR   C, inv_remove_item
    DEC  (HL)
    JP   inv_calc_weight

; ============================================================
; Item Identification & Flavour Shuffling
; ============================================================

; _id_locate — Compute byte ptr (HL -> id_known_bits[byte]) & mask (C) for
; paged item (item_cur_page, A). Preserves B, D, E, IX, IY.
_id_locate:
    PUSH DE
    CALL item_paged_to_logical  ; HL = 0..360
    LD   A, L
    AND  0x07
    LD   E, A
    LD   D, 0
    SRL  H
    RR   L
    SRL  H
    RR   L
    SRL  H
    RR   L                      ; HL = logical_id >> 3 (0..45)
    PUSH HL
    LD   HL, .bit_masks
    ADD  HL, DE
    LD   C, (HL)                ; C = 1 << (id & 7)
    POP  HL
    LD   DE, id_known_bits
    ADD  HL, DE
    POP  DE
    RET
.bit_masks:
    DB   0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

; id_is_known — Test whether paged item (item_cur_page, A) is known.
; Input:  A = slot_lo (0..254), (item_cur_page)
; Output: A != 0, Z = 0, CF = 1 if KNOWN; A = 0, Z = 1, CF = 0 if UNKNOWN.
; Preserves: BC, DE, HL, IX, IY
id_is_known:
    PUSH BC
    PUSH HL
    CALL _id_locate
    LD   A, (HL)
    AND  C
    POP  HL
    POP  BC
    RET  Z                      ; Z=1, CF=0
    SCF                         ; Z=0, CF=1 (SCF keeps Z unchanged!)
    RET

; id_mark_known — Mark paged item (item_cur_page, A) as identified.
; Input:  A = slot_lo (0..254), (item_cur_page)
; Preserves: BC, DE, HL, IX, IY
id_mark_known:
    PUSH BC
    PUSH HL
    CALL _id_locate
    LD   A, (HL)
    OR   C
    LD   (HL), A
    POP  HL
    POP  BC
    RET

; id_refresh_fixed_known — Mark all fixed-description & fixed-flavour items known.
; Preserves: item_cur_page, IX, IY (clobbers AF, BC, DE, HL)
id_refresh_fixed_known:
    LD   A, (item_cur_page)
    PUSH AF
    XOR  A
    LD   (item_cur_page), A
    LD   B, ITEM_PAGE_SIZE
    CALL .scan_page
    LD   A, ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   B, ITEM_TYPE_COUNT - ITEM_PAGE_SIZE
    CALL .scan_page
    POP  AF
    LD   (item_cur_page), A
    RET

.scan_page:
    LD   C, 0                   ; C = slot_lo (0..B-1)
.sp_loop:
    LD   A, C
    CALL item_get_category_a
    CP   ICAT_POTION
    JR   C, .mark
    CP   ICAT_AMULET
    JR   NC, .mark
    CP   ICAT_BOOK
    JR   Z, .mark
    LD   A, C
    CALL item_get_unknown_idx_a
    CP   0xFF
    JR   NZ, .sp_next
.mark:
    LD   A, C
    CALL id_mark_known
.sp_next:
    INC  C
    DJNZ .sp_loop
    RET

; id_init_flavours — Reset id_known_bits, refresh fixed known items, and
; Fisher-Yates shuffle all 5 randomized appearance tables (174 entries).
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
id_init_flavours:
    LD   HL, id_known_bits
    LD   DE, id_known_bits + 1
    LD   BC, ID_KNOWN_BYTES - 1
    LD   (HL), 0
    LDIR
    CALL id_refresh_fixed_known

    ; Shuffle 5 contiguous flavour tables via (potion_shuffle, count)
    LD   HL, potion_shuffle
    LD   DE, .cls_counts
    LD   B, 5
.cls_loop:
    PUSH BC
    LD   A, (DE)                ; A = count
    INC  DE
    PUSH DE
    PUSH HL
    ; Initialize 0..count-1
    LD   C, A                   ; C = count
    LD   B, A
    XOR  A
.init_seq:
    LD   (HL), A
    INC  HL
    INC  A
    DJNZ .init_seq

    ; Fisher-Yates from i = count-1 down to 1
    POP  HL                     ; HL = base of class shuffle table
    DEC  C                      ; C = i
.fy_loop:
    LD   A, C
    INC  A                      ; N = i + 1
    PUSH HL
    PUSH BC
    CALL rng_range              ; A = rand in [0..i]
    POP  BC
    POP  HL
    ; Swap table[i] <-> table[A]
    LD   E, C
    LD   D, 0
    PUSH HL
    ADD  HL, DE
    LD   B, (HL)                ; B = table[i]
    EX   DE, HL                 ; DE = &table[i]
    POP  HL
    PUSH HL
    PUSH BC
    LD   C, A
    LD   B, 0
    ADD  HL, BC                 ; HL = &table[j]
    LD   A, (HL)                ; A = table[j]
    LD   (DE), A                ; table[i] = old table[j]
    POP  BC
    LD   (HL), B                ; table[j] = old table[i]
    POP  HL
    DEC  C
    JR   NZ, .fy_loop

    ; Advance HL past this class table
    LD   B, 0
    POP  DE                     ; DE -> next count? Wait, need current count!
    DEC  DE
    LD   A, (DE)
    INC  DE
    LD   C, A
    ADD  HL, BC
    POP  BC
    DJNZ .cls_loop
    RET

.cls_counts:
    DB   FLAVOUR_POTION_COUNT, FLAVOUR_SCROLL_COUNT, FLAVOUR_RING_COUNT
    DB   FLAVOUR_WAND_COUNT, FLAVOUR_STAFF_COUNT

; ============================================================
; store_check_category — Check whether store accepts/carries ICAT category.
; Input:  A = ICAT_* (0..20), B = store_id (0..7)
; Output: CF = 1 if accepted/sold here, CF = 0 if rejected
; Preserves: IX, IY (clobbers AF, DE, HL)
; ============================================================
store_check_category:
    PUSH BC
    LD   E, B
    LD   D, 0
    LD   C, A
    LD   A, B
    CP   STORE_COUNT
    JR   NC, .no
    LD   A, C
    CP   8
    JR   NC, .hi_cat
    LD   HL, .bit_masks
    LD   C, A
    LD   B, 0
    ADD  HL, BC
    LD   C, (HL)                ; C = bit mask
    LD   HL, .store_mask_lo
    ADD  HL, DE
    LD   A, (HL)
    AND  C
    JR   NZ, .yes
    JR   .no
.hi_cat:
    CP   ICAT_SPIKE
    JR   Z, .chk_spike
    CP   ICAT_CLOAK
    JR   Z, .chk_cloak
    CP   ICAT_AMULET
    JR   Z, .chk_amulet
    JR   NC, .no                ; CHEST(17), JUNK(20) buy nowhere
    SUB  8                      ; 0..7 for ICAT 8..15
    LD   HL, .bit_masks
    LD   C, A
    LD   B, 0
    ADD  HL, BC
    LD   C, (HL)
    LD   HL, .store_mask_hi
    ADD  HL, DE
    LD   A, (HL)
    AND  C
    JR   NZ, .yes
.no:
    POP  BC
    OR   A
    RET
.chk_spike:
    LD   A, E                   ; spikes only at General Store (0) or Home? Wait: store 0 (E==0)
    OR   A
    JR   Z, .yes
    JR   .no
.chk_cloak:
    LD   HL, .store_mask_x
    ADD  HL, DE
    BIT  3, (HL)
    JR   NZ, .yes
    JR   .no
.chk_amulet:
    LD   HL, .store_mask_x
    ADD  HL, DE
    BIT  0, (HL)
    JR   NZ, .yes
    JR   .no
.yes:
    POP  BC
    SCF
    RET

.bit_masks:
    DB   0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80
.store_mask_lo:
    DB   0x01, 0xF8, 0x04, 0x00, 0x00, 0x00, 0xFF, 0xFF
.store_mask_hi:
    DB   0x03, 0x00, 0x00, 0x0C, 0x04, 0xF0, 0xFF, 0xFF
.store_mask_x:
    DB   0x08, 0x08, 0x00, 0x00, 0x00, 0x01, 0xFF, 0xFF

; ============================================================
; Shared Store/Home Inventory <-> si_* Helpers
; ============================================================

; Internal: advance HL by TOTAL_INV_SLOTS and DE by STORE_TOTAL_SLOTS.
_si_adv_both_soa:
    LD   BC, TOTAL_INV_SLOTS
    ADD  HL, BC
    EX   DE, HL
    LD   BC, STORE_TOTAL_SLOTS
    ADD  HL, BC
    EX   DE, HL
    RET

; si_match_inv — Check whether store/home slot B matches inventory slot A for merge.
; Input:  A = inv slot (0..TOTAL_INV_SLOTS-1), B = abs store slot (0..STORE_TOTAL_SLOTS-1)
; Output: CF = 1 if non-empty si[B] and item_id/p1/to_hit/to_dam/to_ac/(flags&0x0F)/ego match
; Preserves: BC, DE, IX, IY (clobbers AF, HL)
si_match_inv:
    CP   TOTAL_INV_SLOTS
    JR   NC, .no_fast
    LD   L, A
    LD   A, B
    CP   STORE_TOTAL_SLOTS
    JR   NC, .no_fast
    PUSH BC
    PUSH DE
    LD   C, L                   ; C = inv_slot
    LD   E, B
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE                 ; HL = &si_item_id[B]
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .no
    LD   B, 0
    EX   DE, HL                 ; DE = &si_item_id[B]
    LD   HL, inv_item_id
    ADD  HL, BC                 ; HL = &inv_item_id[A]
    CP   (HL)
    JR   NZ, .no
    CALL _si_adv_both_soa       ; skip qty -> next step lands on p1
    LD   B, 4
.cmp4:
    PUSH BC
    CALL _si_adv_both_soa       ; p1, to_hit, to_dam, to_ac
    LD   A, (DE)
    CP   (HL)
    POP  BC
    JR   NZ, .no
    DJNZ .cmp4
    CALL _si_adv_both_soa       ; si_meta / inv_flags
    LD   A, (DE)
    AND  ITEM_META_FLAGS_MASK
    LD   B, A
    LD   A, (HL)
    AND  ITEM_META_FLAGS_MASK
    CP   B
    JR   NZ, .no
    CALL _si_adv_both_soa       ; si_meta_hi / inv_ego
    LD   A, (DE)
    CP   (HL)
    JR   NZ, .no
    POP  DE
    POP  BC
    SCF
    RET
.no:
    POP  DE
    POP  BC
.no_fast:
    OR   A
    RET

; si_find_match — Find first slot in store B (0..7) matching inv[C] with si_qty < 24.
; Input:  B = store_id (0..STORE_COUNT-1), C = inv slot (0..TOTAL_INV_SLOTS-1)
; Output: CF = 1, A = abs_si_slot (0..127) if mergeable slot found; else CF = 0, A = 0
; Preserves: BC, DE, IX, IY (clobbers AF, HL)
si_find_match:
    LD   A, B
    CP   STORE_COUNT
    JR   NC, .none
    LD   A, C
    CP   TOTAL_INV_SLOTS
    JR   NC, .none
    PUSH BC
    PUSH DE
    LD   A, B
    ADD  A, A
    ADD  A, A
    ADD  A, A
    ADD  A, A                   ; A = store_id * 16
    LD   B, A                   ; B = current abs_si_slot
    LD   D, STORE_MAX_ITEMS     ; D = remaining slots
.loop:
    LD   A, C                   ; A = inv_slot
    CALL si_match_inv           ; preserves BC, DE
    JR   NC, .next
    LD   E, B
    PUSH DE
    LD   D, 0
    LD   HL, si_qty
    ADD  HL, DE
    POP  DE
    LD   A, (HL)
    CP   STORE_STACK_MAX
    JR   C, .hit
.next:
    INC  B
    DEC  D
    JR   NZ, .loop
    POP  DE
    POP  BC
.none:
    XOR  A                      ; CF = 0, A = 0
    RET
.hit:
    LD   A, B                   ; A = matched abs_si_slot
    POP  DE
    POP  BC
    SCF
    RET

; si_copy_from_inv — Copy inv[A] into store/home slot B with quantity D.
; Input:  A = inv slot (0..TOTAL_INV_SLOTS-1), B = abs_si_slot (0..STORE_TOTAL_SLOTS-1), D = qty
; Preserves: BC, DE, IX, IY (clobbers AF, HL)
si_copy_from_inv:
    CP   TOTAL_INV_SLOTS
    RET  NC
    PUSH AF
    LD   A, B
    CP   STORE_TOTAL_SLOTS
    JR   C, .ok
    POP  AF
    RET
.ok:
    POP  AF
    PUSH BC
    PUSH DE
    PUSH DE                     ; save qty (D)
    LD   C, A
    LD   E, B
    LD   B, 0
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, BC                 ; HL = &inv_item_id[A]
    LD   A, (HL)
    EX   DE, HL
    LD   BC, si_item_id
    ADD  HL, BC                 ; HL = &si_item_id[B]
    LD   (HL), A                ; si_item_id[B] = inv_item_id[A]
    EX   DE, HL                 ; DE = &si_item_id[B], HL = &inv_item_id[A]
    CALL _si_adv_both_soa       ; DE = &si_qty[B], HL = &inv_qty[A]
    POP  BC                     ; B = qty
    LD   A, B
    LD   (DE), A                ; si_qty[B] = qty
    LD   B, 4
.cp4:
    PUSH BC
    CALL _si_adv_both_soa       ; p1, to_hit, to_dam, to_ac
    LD   A, (HL)
    LD   (DE), A
    POP  BC
    DJNZ .cp4
    CALL _si_adv_both_soa       ; si_meta / inv_flags
    LD   A, (HL)
    AND  ITEM_META_FLAGS_MASK
    LD   (DE), A
    CALL _si_adv_both_soa       ; si_meta_hi / inv_ego
    LD   A, (HL)
    LD   (DE), A
    POP  DE
    POP  BC
    RET

; si_compact_store — Compact 16 slots of store B (0..7) toward base, clearing tail slots.
; Input:  B = store_id (0..STORE_COUNT-1)
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
si_compact_store:
    LD   A, B
    CP   STORE_COUNT
    RET  NC
    ADD  A, A
    ADD  A, A
    ADD  A, A
    ADD  A, A                   ; A = base abs slot
    LD   D, A                   ; D = write abs cursor
    LD   E, A                   ; E = read abs cursor
    ADD  A, STORE_MAX_ITEMS
    LD   C, A                   ; C = end abs slot
.scan:
    LD   B, 0
    LD   HL, si_item_id
    PUSH BC
    LD   C, E
    ADD  HL, BC
    POP  BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .skip
    LD   A, D
    CP   E
    CALL NZ, _si_copy_slot_e_to_d
    INC  D
.skip:
    INC  E
    LD   A, E
    CP   C
    JR   NZ, .scan
.clr:
    LD   A, D
    CP   C
    RET  Z
    PUSH DE
    LD   E, D
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   (HL), FI_EMPTY
    LD   DE, STORE_TOTAL_SLOTS
    LD   B, 7
    XOR  A
.clr_fields:
    ADD  HL, DE
    LD   (HL), A
    DJNZ .clr_fields
    POP  DE
    INC  D
    JR   .clr

; Internal: copy all 8 SoA bytes from slot E to slot D. Preserves BC, DE.
_si_copy_slot_e_to_d:
    PUSH BC
    PUSH DE
    LD   HL, si_item_id
    LD   B, 8
.lp:
    PUSH BC
    PUSH HL
    LD   C, E
    LD   B, 0
    ADD  HL, BC
    LD   A, (HL)
    POP  HL
    PUSH HL
    LD   C, D
    ADD  HL, BC
    LD   (HL), A
    POP  HL
    LD   BC, STORE_TOTAL_SLOTS
    ADD  HL, BC
    POP  BC
    DJNZ .lp
    POP  DE
    POP  BC
    RET

; ============================================================
; 24-Bit Gold Arithmetic Helpers
; ============================================================

; player_add_gold_24 — Add 24-bit unsigned (E:HL) to PL_GOLD_0..2, saturating at 0xFFFFFF.
; Input:  HL = low 16 bits, E = high 8 bits
; Preserves: BC, DE, IX, IY (clobbers AF, HL)
player_add_gold_24:
    PUSH DE
    EX   DE, HL
    LD   A, (player_data + PL_GOLD_0)
    ADD  A, E
    LD   (player_data + PL_GOLD_0), A
    LD   A, (player_data + PL_GOLD_1)
    ADC  A, D
    LD   (player_data + PL_GOLD_1), A
    LD   A, (player_data + PL_GOLD_2)
    ADC  A, L
    LD   (player_data + PL_GOLD_2), A
    POP  DE
    RET  NC
    LD   A, 0xFF
    LD   (player_data + PL_GOLD_0), A
    LD   (player_data + PL_GOLD_1), A
    LD   (player_data + PL_GOLD_2), A
    RET

; player_cmp_gold_24 — Compare PL_GOLD >= (E:HL).
; Input:  HL = low 16 bits, E = high 8 bits
; Output: CF = 1 if PL_GOLD >= (E:HL); CF = 0 if insufficient
; Preserves: BC, DE, HL, IX, IY (clobbers AF)
player_cmp_gold_24:
    LD   A, (player_data + PL_GOLD_0)
    SUB  L
    LD   A, (player_data + PL_GOLD_1)
    SBC  A, H
    LD   A, (player_data + PL_GOLD_2)
    SBC  A, E
    CCF                         ; CF = 1 if no borrow (gold >= amt)
    RET

; player_sub_gold_24 — Subtract (E:HL) from PL_GOLD if sufficient.
; Input:  HL = low 16 bits, E = high 8 bits
; Output: CF = 1 if subtracted; CF = 0 if insufficient (PL_GOLD unchanged)
; Preserves: BC, DE, HL, IX, IY (clobbers AF)
player_sub_gold_24:
    CALL player_cmp_gold_24
    RET  NC
    LD   A, (player_data + PL_GOLD_0)
    SUB  L
    LD   (player_data + PL_GOLD_0), A
    LD   A, (player_data + PL_GOLD_1)
    SBC  A, H
    LD   (player_data + PL_GOLD_1), A
    LD   A, (player_data + PL_GOLD_2)
    SBC  A, E
    LD   (player_data + PL_GOLD_2), A
    SCF
    RET

    ENDIF
