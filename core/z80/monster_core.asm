; monster_core.asm — M4 Resident Monster Table, Catalog, Recall, Visibility & Helpers
;
; Pure 0xNN hex syntax (sjasmplus v1.24.0). IX and IY preserved across all public routines.
; Coordinate register convention: B = y, C = x.

    IFNDEF MONSTER_IDX_CONSTS_INCLUDED
    DEFINE MONSTER_IDX_CONSTS_ONLY 1
    INCLUDE "monster_idx_z80.inc"
    ENDIF

    EXPORT monster_get_ptr
    EXPORT monster_find_at
    EXPORT monster_remove
    EXPORT monster_wake
    EXPORT monster_apply_sleep
    EXPORT monster_aggravate_all
    EXPORT monster_spawn_one
    EXPORT monster_spawn_awake
    EXPORT monster_get_name_ptr
    EXPORT monster_is_balrog_slot
    EXPORT monster_death_stage

    EXPORT catalog_read_record
    EXPORT catalog_init_town_creatures
    EXPORT catalog_reset_slots
    EXPORT catalog_fetch_id_to_slot
    EXPORT catalog_slot_for_id
    EXPORT catalog_refetch_slots
    EXPORT pick_creature_type
    EXPORT pick_summon_creature_type
    EXPORT pick_any_creature_type
    EXPORT pick_undead_creature_type

    EXPORT recall_inc_kills_slot
    EXPORT recall_inc_deaths_slot
    EXPORT recall_mark_atk_slot
    EXPORT recall_mark_spell_slot

    EXPORT monster_update_visibility_all
    EXPORT monster_update_visibility_one
    EXPORT detect_evil_clear_reveal

    EXPORT floor_item_add
    EXPORT floor_item_find_at
    EXPORT floor_item_remove
    EXPORT find_adjacent_empty_tile
    EXPORT find_random_floor
    EXPORT player_search_mode_off
    EXPORT player_wis_save_adj
    EXPORT player_saving_throw
    EXPORT element_resist_divisor
    EXPORT roll_dice_bc
    EXPORT tile_is_walkable_a
    EXPORT player_get_stealth
    EXPORT player_get_infra_range
    EXPORT player_search_get_fos

    EXPORT race_properties
    EXPORT class_properties
    EXPORT class_level_adj
    EXPORT equip_slot_for_cat

    ASSERT MX_X == 0 && MX_Y == 1 && MX_TYPE == 2, "MX head"
    ASSERT MX_HP_LO == 3 && MX_HP_HI == 4 && MX_FLAGS == 5, "MX hp/flags"
    ASSERT MX_SPEED_CNT == 6 && MX_SLEEP_CUR == 7 && MX_STUN == 8, "MX sleep/stun"
    ASSERT MX_CONFUSE == 9 && MX_RESERVED_0 == 10 && MX_RESERVED_1 == 11, "MX reserved"
    ASSERT MF_AWAKE == 0x01 && TILE_FLOOR == 0x00 && MD_QUEUE_MAX == 4, "defs"
    ASSERT abi_player_y == (abi_player_x + 1), "abi_player_x/y"
    ASSERT ms_spawn_y == (ms_spawn_x + 1) && mfa_y == (mfa_x + 1), "spawn/mfa pairs"
    ASSERT (fi_x - fi_item_id) == MAX_FLOOR_ITEMS, "fi_x stride"
    ASSERT (fi_y - fi_x) == MAX_FLOOR_ITEMS && (fi_qty - fi_y) == MAX_FLOOR_ITEMS, "fi_y/qty stride"
    ASSERT (fi_p1 - fi_qty) == MAX_FLOOR_ITEMS && (fi_meta - fi_p1) == MAX_FLOOR_ITEMS, "fi_p1/meta stride"
    ASSERT (fi_to_hit - fi_meta) == MAX_FLOOR_ITEMS && (fi_to_dam - fi_to_hit) == MAX_FLOOR_ITEMS, "fi_hit/dam stride"
    ASSERT (fi_to_ac - fi_to_dam) == MAX_FLOOR_ITEMS && (fi_meta_hi - fi_to_ac) == MAX_FLOOR_ITEMS, "fi_ac/ego stride"

CAT_LEVELS EQU (CATALOG_MAX_MONS_LEVEL + 1)

; ============================================================================
; Monster Table Primitives
; ============================================================================

; monster_get_ptr — A=slot (0..31) -> CF=0 HL=monster_table+A*12, CF=1 >=32.
; Preserves BC, DE, IX, IY.
monster_get_ptr:
    CP   MAX_MONSTERS
    JR   C, .ok
    SCF
    RET
.ok:
    PUSH DE
    LD   L, A
    LD   H, 0
    LD   E, A
    LD   D, H
    ADD  HL, HL
    ADD  HL, DE
    ADD  HL, HL
    ADD  HL, HL
    LD   DE, monster_table
    ADD  HL, DE
    POP  DE
    OR   A
    RET

; monster_find_at — B=y, C=x -> CF=1 A=slot HL=ptr, CF=0 none.
; Preserves BC, DE, IX, IY.
monster_find_at:
    PUSH DE
    LD   HL, monster_table
    LD   E, 0
.lp:
    PUSH HL
    LD   A, (HL)
    CP   C
    JR   NZ, .next
    INC  HL
    LD   A, (HL)
    CP   B
    JR   NZ, .next
    INC  HL
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .next
    POP  HL
    LD   A, E
    POP  DE
    SCF
    RET
.next:
    POP  HL
    LD   A, MONSTER_ENTRY_SIZE
    CALL _mc_add_a_hl_raw
    INC  E
    LD   A, E
    CP   MAX_MONSTERS
    JR   C, .lp
    POP  DE
    OR   A
    RET

; monster_remove — A=slot -> save mfa_x/y, clear FLAG_OCCUPIED, zero slot & MX_TYPE=0xFF, dec counts.
; Preserves BC, DE, IX, IY.
monster_remove:
    CALL monster_get_ptr
    RET  C
    PUSH BC
    PUSH DE
    PUSH HL
    LD   C, (HL)
    INC  HL
    LD   B, (HL)
    LD   (mfa_x), BC
    CALL _mc_tile_clr_occ
.clr_slot:
    POP  HL
    PUSH HL
    XOR  A
    LD   B, MONSTER_ENTRY_SIZE
.z_lp:
    LD   (HL), A
    INC  HL
    DJNZ .z_lp
    POP  HL
    INC  HL
    INC  HL
    LD   (HL), EMPTY_SLOT
    LD   HL, zp_mon_count
    LD   A, (HL)
    OR   A
    JR   Z, .sync
    DEC  (HL)
.sync:
    LD   A, (HL)
    LD   (abi_mon_count), A
    POP  DE
    POP  BC
    RET

; monster_wake (A=slot) & monster_apply_sleep (A=slot, B=dur).
; Preserves BC, DE, IX, IY.
monster_wake:
    CALL monster_get_ptr
    RET  C
    PUSH DE
    LD   DE, MX_FLAGS
    ADD  HL, DE
    SET  0, (HL)
    INC  HL
    INC  HL
    LD   (HL), 0
    POP  DE
    RET

monster_apply_sleep:
    CALL monster_get_ptr
    RET  C
    PUSH DE
    LD   DE, MX_FLAGS
    ADD  HL, DE
    RES  0, (HL)
    INC  HL
    INC  HL
    LD   (HL), B
    POP  DE
    RET

; monster_aggravate_all — Wake all live monsters (caller prints message).
; Preserves IX, IY.
monster_aggravate_all:
    LD   B, 0
    LD   HL, monster_table + MX_TYPE
    LD   DE, MONSTER_ENTRY_SIZE
.lp:
    LD   A, (HL)
    CP   EMPTY_SLOT
    LD   A, B
    CALL NZ, monster_wake
    ADD  HL, DE
    INC  B
    LD   A, B
    CP   MAX_MONSTERS
    JR   C, .lp
    RET

; monster_is_balrog_slot — Z=1 iff A<32 && cat_slot_id[A]==CATALOG_BALROG_ID.
; Preserves BC, DE, HL, IX, IY.
monster_is_balrog_slot:
    CP   MAX_DUNGEON_CREATURES
    JR   C, .chk
    OR   A
    RET
.chk:
    PUSH HL
    LD   HL, cat_slot_id_lo
    CALL _mc_add_a_hl
    CP   LOW CATALOG_BALROG_ID
    JR   NZ, .done
    PUSH DE
    LD   DE, cat_slot_id_hi - cat_slot_id_lo
    ADD  HL, DE
    POP  DE
    LD   A, (HL)
    CP   HIGH CATALOG_BALROG_ID
.done:
    POP  HL
    RET

; monster_death_stage — Queue cr_treasure[A] + mfa_x/y into md_queue_*.
; Preserves BC, DE, HL, IX, IY.
monster_death_stage:
    CP   MAX_CREATURES
    RET  NC
    PUSH BC
    PUSH DE
    PUSH HL
    LD   HL, cr_treasure
    CALL _mc_add_a_hl
    OR   A
    JR   Z, .done
    LD   B, A
    LD   HL, md_queue_count
    LD   A, (HL)
    CP   MD_QUEUE_MAX
    JR   NC, .done
    INC  (HL)
    LD   E, A
    LD   D, 0
    LD   HL, md_queue_flags
    ADD  HL, DE
    LD   (HL), B
    LD   HL, md_queue_x
    ADD  HL, DE
    LD   A, (mfa_x)
    LD   (HL), A
    LD   HL, md_queue_y
    ADD  HL, DE
    LD   A, (mfa_y)
    LD   (HL), A
.done:
    POP  HL
    POP  DE
    POP  BC
    RET

; monster_spawn_awake — A=cr_type, B=y, C=x -> CF=1 A=slot.
; Preserves zp_mon_idx, IX, IY.
monster_spawn_awake:
    CALL monster_spawn_one
    RET  NC
    CALL monster_wake
    SCF
    RET

; monster_spawn_one — A=cr_type (0..39), B=y, C=x -> CF=1 A=slot.
; Preserves zp_mon_idx, IX, IY.
monster_spawn_one:
    CP   MAX_CREATURES
    JR   NC, .fail
    LD   (_mc_sp_type), A
    LD   (ms_spawn_x), BC
    CALL map_get_tile
    JR   C, .fail
    BIT  0, A
    JR   NZ, .fail
    CALL _mc_is_player_bc
    JR   Z, .fail
.find_slot:
    LD   HL, monster_table + MX_TYPE
    LD   DE, MONSTER_ENTRY_SIZE
    LD   B, 0
.slot_lp:
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .got_slot
    ADD  HL, DE
    INC  B
    LD   A, B
    CP   MAX_MONSTERS
    JR   C, .slot_lp
.fail:
    OR   A
    RET
.got_slot:
    LD   A, B
    LD   (_mc_sp_slot), A
    DEC  HL
    DEC  HL                     ; HL = slot base (MX_X)
    PUSH HL

    LD   A, (_mc_sp_type)
    LD   HL, cr_speed
    CALL _mc_add_a_hl_raw
    LD   D, (HL)                ; D = cr_speed (CR_MAX_HP = bit 7 = 0x80)
    LD   BC, MAX_CREATURES * 3
    ADD  HL, BC                 ; cr_hd_num (+3*40 from cr_speed)
    LD   B, (HL)
    PUSH DE
    LD   DE, MAX_CREATURES
    ADD  HL, DE                 ; cr_hd_sides
    LD   C, (HL)
    ADD  HL, DE
    ADD  HL, DE                 ; cr_sleep
    LD   A, (HL)
    POP  DE
    PUSH AF                     ; save sleep
    BIT  7, D
    JR   Z, .roll_hp
    LD   E, B
    LD   D, 0
    LD   A, C
    CALL mul_de_a
    JR   .hp_chk
.roll_hp:
    CALL roll_dice_bc
.hp_chk:
    LD   A, H
    OR   L
    JR   NZ, .hp_ok
    INC  HL
.hp_ok:
    EX   DE, HL                 ; DE = HP
    POP  AF                     ; A = sleep
    OR   A
    JR   Z, .slp_done
    LD   C, A
    CALL rng_range
    INC  A
    JR   Z, .slp_sat
    SRL  C
    SRL  C
    ADD  A, C
    JR   NC, .slp_done
.slp_sat:
    LD   A, 0xFF
.slp_done:
    LD   B, A
    POP  HL
    LD   A, (ms_spawn_x)
    LD   (HL), A                ; MX_X
    INC  HL
    LD   A, (ms_spawn_y)
    LD   (HL), A                ; MX_Y
    INC  HL
    LD   A, (_mc_sp_type)
    LD   (HL), A                ; MX_TYPE
    INC  HL
    LD   (HL), E                ; MX_HP_LO
    INC  HL
    LD   (HL), D                ; MX_HP_HI
    INC  HL
    XOR  A
    LD   (HL), A                ; MX_FLAGS
    INC  HL
    LD   (HL), A                ; MX_SPEED_CNT
    INC  HL
    LD   (HL), B                ; MX_SLEEP_CUR
    INC  HL
    LD   (HL), A                ; MX_STUN
    INC  HL
    LD   (HL), A                ; MX_CONFUSE
    INC  HL
    LD   (HL), A                ; MX_RESERVED_0
    INC  HL
    LD   (HL), A                ; MX_RESERVED_1

    LD   BC, (ms_spawn_x)
    LD   A, FLAG_OCCUPIED
    CALL _mc_tile_or_a

    LD   HL, zp_mon_count
    INC  (HL)
    LD   A, (HL)
    LD   (abi_mon_count), A
    LD   A, (_mc_sp_slot)
    SCF
    RET

; monster_get_name_ptr — A=cr_type (0..39) -> HL=name ptr.
; Preserves BC, DE, IX, IY.
monster_get_name_ptr:
    CP   MAX_CREATURES
    JR   NC, .unknown
    CALL _mc_pool_hl
    LD   A, (HL)
    OR   A
    RET  NZ
.unknown:
    LD   HL, _mc_str_unknown
    RET

; ============================================================================
; Monster Catalog & Pickers
; ============================================================================

; catalog_read_record — DE=cat_id (0..278) -> CF=0 HL=cpm_dma_buf+(E&1)*57, CF=1 err.
; Preserves DE, IX, IY.
catalog_read_record:
    LD   HL, CATALOG_COUNT - 1
    OR   A
    SBC  HL, DE
    JR   C, .oob
    PUSH DE
    LD   A, E
    AND  1
    PUSH AF
    SRL  D
    RR   E
    LD   A, DAT_ID_MONSTER_CAT
    LD   HL, cpm_dma_buf
    CALL dat_read_slot_record
    JR   C, .io_err
    POP  AF
    LD   HL, cpm_dma_buf
    JR   Z, .done
    LD   DE, CATALOG_RECORD_SIZE
    ADD  HL, DE
.done:
    POP  DE
    OR   A
    RET
.io_err:
    POP  AF
    POP  DE
.oob:
    SCF
    RET

; catalog_init_town_creatures — Load IDs 0..7 into cr_*[32..39] + town_name_pool.
; Preserves IX, IY.
catalog_init_town_creatures:
    LD   DE, 0
.lp:
    CALL catalog_read_record
    RET  C
    PUSH DE
    PUSH HL
    LD   A, E
    ADD  A, TOWN_CREATURE_BASE
    PUSH AF
    CALL _cat_copy_rec_to_cr_row
    POP  AF
    POP  HL
    CALL _cat_copy_name_to_pool
    POP  DE
    INC  DE
    LD   A, E
    CP   CATALOG_TOWN_COUNT
    JR   C, .lp
    RET

; catalog_reset_slots — Empty all 32 slots & zero active_dungeon_count. Preserves IX, IY.
catalog_reset_slots:
    LD   HL, cat_slot_id_hi
    LD   B, CAT_SLOTS
    LD   A, 0xFF
.lp:
    LD   (HL), A
    INC  HL
    DJNZ .lp
    XOR  A
    LD   (active_dungeon_count), A
    RET

; catalog_fetch_id_to_slot — DE=cat_id, A=slot (0..31) -> load record + name.
; Output: CF=0 ok, CF=1 err. Preserves IX, IY.
catalog_fetch_id_to_slot:
    CP   CAT_SLOTS
    JR   C, .slot_ok
    SCF
    RET
.slot_ok:
    PUSH AF
    CALL catalog_read_record
    JR   NC, .rec_ok
    POP  AF
    SCF
    RET
.rec_ok:
    POP  AF
    LD   C, A                   ; C = slot
    PUSH HL                     ; record ptr

    LD   HL, cat_slot_id_lo
    CALL _mc_add_a_hl_raw
    LD   (HL), E
    PUSH DE
    LD   DE, CAT_SLOTS
    ADD  HL, DE
    POP  DE
    LD   (HL), D
    ASSERT cat_slot_id_hi == (cat_slot_id_lo + CAT_SLOTS), "cat_slot_id layout"

    LD   A, C
    INC  A
    LD   HL, active_dungeon_count
    CP   (HL)
    JR   C, .cnt_ok
    LD   (HL), A
.cnt_ok:
    POP  HL
    PUSH HL
    LD   A, C
    PUSH BC
    CALL _cat_copy_rec_to_cr_row
    POP  BC
    POP  HL

    LD   A, C
    CALL _cat_copy_name_to_pool
    OR   A
    RET

; _cat_copy_name_to_pool — Copy name from catalog record HL into pool slot A (0..39).
_cat_copy_name_to_pool:
    LD   DE, CATALOG_RECORD_NAME
    ADD  HL, DE
    PUSH HL
    CALL _mc_pool_hl
    EX   DE, HL
    POP  HL
    LD   BC, CATALOG_RECORD_NAME_SIZE
    LDIR
    RET

_cat_copy_rec_to_cr_row:
    INC  HL
    INC  HL                     ; HL = rec + 2
    EX   DE, HL                 ; DE = rec + 2
    LD   HL, cr_display
    CALL _mc_add_a_hl_raw       ; HL = &cr_display[row]
    PUSH HL
    LD   B, CATALOG_TOTAL_FIELDS
.lp:
    LD   A, (DE)
    LD   (HL), A
    INC  DE
    PUSH DE
    LD   DE, MAX_CREATURES
    ADD  HL, DE
    POP  DE
    DJNZ .lp
    ; Rotate atk0_type/dice/sides (fields 12..14) into cr_atk0_dice/sides/type
    POP  HL
    LD   DE, MAX_CREATURES * 12
    ADD  HL, DE
    LD   B, (HL)                ; type
    LD   DE, MAX_CREATURES
    PUSH HL
    ADD  HL, DE
    LD   C, (HL)                ; dice
    ADD  HL, DE
    LD   A, (HL)                ; sides
    LD   (HL), B                ; cr_atk0_type = type
    POP  HL
    LD   (HL), C                ; cr_atk0_dice = dice
    ADD  HL, DE
    LD   (HL), A                ; cr_atk0_sides = sides
    RET
    ASSERT cr_atk0_dice == (cr_display + MAX_CREATURES * 12) && cr_atk0_sides == (cr_atk0_dice + MAX_CREATURES) && cr_atk0_type == (cr_atk0_sides + MAX_CREATURES), "atk0 rotate layout"

; catalog_slot_for_id — DE=cat_id -> A=slot (0..31). Preserves IX, IY.
catalog_slot_for_id:
    LD   (cat_id_lo), DE
    ASSERT cat_id_hi == (cat_id_lo + 1), "cat_id pair"

    LD   C, 0
.fl_lp:
    LD   A, C
    LD   HL, cat_slot_id_lo
    CALL _mc_add_a_hl
    CP   E
    JR   NZ, .fl_next
    LD   A, C
    LD   HL, cat_slot_id_hi
    CALL _mc_add_a_hl
    CP   D
    JR   Z, .found_c
.fl_next:
    INC  C
    LD   A, C
    CP   CAT_SLOTS
    JR   C, .fl_lp

    PUSH DE
    LD   C, 0
    LD   HL, cat_slot_id_hi
.ff_lp:
    BIT  7, (HL)
    JR   NZ, .got_free
    LD   A, C
    CALL _cat_slot_in_use
    JR   NC, .got_free
    INC  HL
    INC  C
    LD   A, C
    CP   CAT_SLOTS
    JR   C, .ff_lp
    POP  DE
    LD   C, 0
    JR   .found_c
.got_free:
    POP  DE
    LD   A, C
    LD   (cat_slot), A
    PUSH BC
    CALL catalog_fetch_id_to_slot
    POP  BC
    LD   A, C
    RET
.found_c:
    LD   A, C
    LD   (cat_slot), A
    RET

_cat_slot_in_use:
    PUSH HL
    PUSH BC
    LD   C, A
    LD   B, MAX_MONSTERS
.lp:
    LD   A, B
    DEC  A
    CALL monster_get_ptr
    INC  HL
    INC  HL
    LD   A, (HL)
    CP   C
    JR   Z, .used
    DJNZ .lp
    POP  BC
    POP  HL
    OR   A
    RET
.used:
    POP  BC
    POP  HL
    SCF
    RET

; catalog_refetch_slots — Reload active slots where cat_slot_id_hi != 0xFF. Preserves IX, IY.
catalog_refetch_slots:
    XOR  A
    LD   (active_dungeon_count), A
    LD   C, 0
    LD   HL, cat_slot_id_hi
.lp:
    LD   A, (HL)
    BIT  7, A
    JR   NZ, .next
    LD   D, A
    PUSH HL
    LD   DE, cat_slot_id_lo - cat_slot_id_hi
    ADD  HL, DE
    LD   E, (HL)
    LD   D, A
    LD   A, C
    PUSH BC
    CALL catalog_fetch_id_to_slot
    POP  BC
    POP  HL
.next:
    INC  HL
    INC  C
    LD   A, C
    CP   CAT_SLOTS
    JR   C, .lp
    RET

; Creature pickers. Preserve IX, IY.
pick_any_creature_type:
    LD   A, 0xFF
    LD   (cat_level_adj), A
    JR   _pick_dungeon

pick_summon_creature_type:
    LD   A, CAT_SUMMON_ADJ
    JR   _pct_set_adj

pick_creature_type:
    XOR  A
_pct_set_adj:
    LD   (cat_level_adj), A
    LD   A, (abi_player_dlvl)
    OR   A
    JR   NZ, _pick_dungeon
    LD   A, TOWN_CREATURE_COUNT
    CALL rng_range
    ADD  A, TOWN_CREATURE_BASE
    RET

_pick_dungeon:
    LD   A, (cat_level_adj)
    LD   C, A
    LD   A, (abi_player_dlvl)
    ADD  A, C
    JR   C, .deep
    CP   CAT_LEVELS
    JR   C, .in_range
.deep:
    LD   A, CATALOG_MAX_MONS_LEVEL
    LD   (_mc_cat_level), A
    JR   .normal
.in_range:
    LD   (_mc_cat_level), A
    LD   A, (cat_level_adj)
    OR   A
    JR   NZ, .normal
    LD   A, CAT_MON_NASTY
    CALL rng_range
    OR   A
    JR   NZ, .normal

    LD   C, 0
    LD   B, 4
.nor_lp:
    LD   A, 7
    CALL rng_range
    ADD  A, C
    LD   C, A
    DJNZ .nor_lp
    LD   A, C
    SUB  12
    JR   NC, .abs_ok
    NEG
.abs_ok:
    INC  A
    LD   C, A
    LD   A, (_mc_cat_level)
    ADD  A, C
    JR   C, .ood_cap
    CP   CAT_LEVELS
    JR   C, .ood_t_ok
.ood_cap:
    LD   A, CATALOG_MAX_MONS_LEVEL
.ood_t_ok:
    LD   B, A
    LD   HL, cat_level_raw
    CALL _mc_add_a_hl
    LD   C, A
    OR   A
    JR   Z, .normal
    LD   A, B
    CP   2
    JR   C, .ood_t1
    DEC  A
    CALL _cat_sum_levels
    JR   .ood_pick
.ood_t1:
    LD   HL, CATALOG_TOWN_COUNT
.ood_pick:
    LD   A, C
    CALL rng_range
    LD   E, A
    LD   D, 0
.to_slot:
    ADD  HL, DE
    EX   DE, HL
    JP   catalog_slot_for_id

.normal:
    LD   A, (_mc_cat_level)
    CALL _cat_sum_levels
    LD   A, H
    OR   L
    JR   NZ, .cnt_nz
    LD   DE, CATALOG_TOWN_COUNT
    JP   catalog_slot_for_id
.cnt_nz:
    CALL _mc_rng_range_16
    LD   DE, CATALOG_TOWN_COUNT
    JR   .to_slot

_cat_sum_levels:
    LD   HL, 0
    OR   A
    RET  Z
    PUSH BC
    LD   B, A
    LD   DE, cat_level_raw + 1
.lp:
    LD   A, (DE)
    ADD  A, L
    LD   L, A
    JR   NC, .nc
    INC  H
.nc:
    INC  DE
    DJNZ .lp
    POP  BC
    RET

pick_undead_creature_type:
    LD   A, 35
    CALL rng_range
    LD   C, A
.find_byte:
    LD   A, C
    LD   HL, cat_undead
    CALL _mc_add_a_hl
    OR   A
    JR   NZ, .got_byte
    INC  C
    LD   A, C
    CP   35
    JR   C, .find_byte
    LD   C, 0
    JR   .find_byte
.got_byte:
    LD   B, 0
.bit_lp:
    RRA
    JR   C, .got_bit
    INC  B
    JR   .bit_lp
.got_bit:
    LD   L, C
    LD   H, 0
    ADD  HL, HL
    ADD  HL, HL
    ADD  HL, HL
    LD   E, B
    LD   D, 0
    ADD  HL, DE
    EX   DE, HL
    CALL catalog_slot_for_id
    SCF
    RET

; ============================================================================
; Recall Writers
; ============================================================================

_recall_ptr_for_slot:
    CP   MAX_CREATURES
    JR   NC, .bad
    PUSH DE
    CP   TOWN_CREATURE_BASE
    JR   C, .dungeon
    SUB  TOWN_CREATURE_BASE
    LD   L, A
    LD   H, 0
    JR   .have_id
.dungeon:
    LD   E, A
    LD   HL, cat_slot_id_hi
    CALL _mc_add_a_hl
    BIT  7, A
    JR   NZ, .bad_pop
    PUSH AF
    LD   A, E
    LD   HL, cat_slot_id_lo
    CALL _mc_add_a_hl
    LD   L, A
    POP  AF
    LD   H, A
.have_id:
    LD   DE, CATALOG_COUNT
    OR   A
    SBC  HL, DE
    JR   NC, .bad_pop
    ADD  HL, DE
    ADD  HL, HL
    ADD  HL, HL
    LD   DE, recall_data
    ADD  HL, DE
    POP  DE
    SCF
    RET
.bad_pop:
    POP  DE
.bad:
    OR   A
    RET

recall_inc_kills_slot:
    PUSH HL
    CALL _recall_ptr_for_slot
.inc_at_hl:
    JR   NC, .done
    LD   A, (HL)
    CP   0xFF
    JR   Z, .done
    INC  (HL)
.done:
    POP  HL
    RET

recall_inc_deaths_slot:
    PUSH HL
    CALL _recall_ptr_for_slot
    INC  HL                     ; harmless if NC -> skipped by JR NC
    JR   recall_inc_kills_slot.inc_at_hl

recall_mark_atk_slot:
    PUSH HL
    CALL _recall_ptr_for_slot
    INC  HL                     ; INC HL preserves CF -> JR NC inside .inc_at_hl skips invalid slots
    INC  HL
    JR   recall_inc_kills_slot.inc_at_hl

recall_mark_spell_slot:
    PUSH HL
    CALL _recall_ptr_for_slot
    JR   NC, .done
    INC  HL
    INC  HL
    INC  HL
    LD   A, (HL)
    OR   B
    LD   (HL), A
.done:
    POP  HL
    RET

; ============================================================================
; Monster Visibility & Detection Lifecycle
; ============================================================================

monster_update_visibility_all:
    XOR  A
    LD   (muv_changed), A
    LD   B, MAX_MONSTERS - 1
.lp:
    PUSH BC
    LD   A, B
    CALL _muv_update_one
    POP  BC
    LD   A, B
    OR   A
    JR   Z, .done
    DEC  B
    JR   .lp
.done:
    XOR  A
    LD   (muv_clear_detected), A
    LD   A, (muv_changed)
    RET

monster_update_visibility_one:
_muv_update_one:
    CALL monster_get_ptr
    PUSH HL                     ; save slot base ptr
    INC  HL
    INC  HL
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   NZ, .active
    POP  HL
    OR   A
    RET
.active:
    LD   (_muv_type), A
    POP  HL
    LD   E, (HL)                ; MX_X
    INC  HL
    LD   D, (HL)                ; MX_Y
    INC  HL
    INC  HL
    INC  HL
    INC  HL                     ; MX_FLAGS (1+1+1+1+1 = 5)
    PUSH HL                     ; save &MX_FLAGS
    LD   A, (HL)                ; MX_FLAGS
    LD   (_muv_old_flags), A
    AND  (~MF_VISIBLE) & 0xFF
    LD   C, A

    ASSERT MF_VISIBLE == 0x08 && MF_DETECTED == 0x10, "MF vis/det bits"
    LD   A, (muv_clear_detected)
    OR   A
    JR   Z, .no_clr
    RES  4, C
.no_clr:
    LD   A, (eff_detect_timer)
    OR   A
    JR   Z, .no_det
    SET  4, C
.no_det:
    LD   A, (zp_eff_blind)
    OR   A
    JP   NZ, .store

    LD   A, (abi_player_dlvl)
    OR   A
    JR   Z, .apply_vis

    LD   HL, (abi_player_x)
    CALL _mc_cheb_dist_hl_de
    LD   (_muv_dist), A
    OR   A
    JR   Z, .apply_vis
    CP   MONS_MAX_SIGHT + 1
    JR   NC, .store

    PUSH BC
    LD   B, D
    LD   C, E
    CALL map_get_tile
    POP  BC
    JR   C, .store
    AND  (FLAG_LIT | FLAG_VISITED)
    CP   (FLAG_LIT | FLAG_VISITED)
    JR   Z, .chk_los

    LD   A, (_muv_dist)
    LD   B, A
    LD   A, (zp_light_radius)
    CP   B
    JR   NC, .chk_los

    LD   A, (_muv_type)
    LD   HL, cr_mflags
    CALL _mc_add_a_hl
    BIT  7, A
    JR   Z, .store
    CALL player_get_infra_range
    LD   HL, _muv_dist
    CP   (HL)
    JR   C, .store

.chk_los:
    LD   A, (_muv_dist)
    CP   1
    JR   Z, .apply_vis
    PUSH BC
    LD   BC, (abi_player_x)
    CALL los_check
    POP  BC
    JR   NC, .store

.apply_vis:
    LD   A, (_muv_type)
    LD   HL, cr_cdefense
    CALL _mc_add_a_hl
    BIT  7, A
    JR   Z, .can_see
    LD   A, (player_pflags)
    AND  PFLAG_SEE_INVIS
    LD   HL, zp_eff_see_inv
    OR   (HL)
    LD   HL, zp_eff_invis
    OR   (HL)
    JR   Z, .store

.can_see:
    LD   A, (_muv_old_flags)
    AND  MF_VISIBLE
    JR   NZ, .set_vis
    LD   HL, zp_disturb
    INC  (HL)
    CALL player_search_mode_off
.set_vis:
    SET  3, C

.store:
    POP  HL                     ; &MX_FLAGS
    LD   (HL), C
    LD   A, (_muv_old_flags)
    XOR  C
    AND  (MF_VISIBLE | MF_DETECTED)
    RET  Z
    LD   A, 1
    LD   (muv_changed), A
    RET

detect_evil_clear_reveal:
    LD   HL, eff_detect_evil_mode
    LD   A, (HL)
    OR   A
    RET  Z
    DEC  (HL)
    LD   A, 1
    LD   (muv_clear_detected), A
    LD   (vis_room_revealed), A
    JP   monster_update_visibility_all

; ============================================================================
; Shared Floor Item, Map Search & Combat/Math Helpers
; ============================================================================

; floor_item_add — Compact loop copy from fi_add_* into first empty fi_* slot.
; Output: CF=1 A=slot (0..41), CF=0 full. Preserves BC, DE, IX, IY.
floor_item_add:
    PUSH DE
    PUSH BC
    LD   E, 0
    LD   HL, fi_item_id
.scan:
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .found
    INC  HL
    INC  E
    LD   A, E
    CP   MAX_FLOOR_ITEMS
    JR   C, .scan
    POP  BC
    POP  DE
    OR   A
    RET
.found:
    PUSH DE
    LD   D, 0
    LD   BC, MAX_FLOOR_ITEMS
    LD   A, (fi_add_id)
    LD   (HL), A
    ADD  HL, BC
    LD   A, (fi_add_x)
    LD   (HL), A
    ADD  HL, BC
    LD   A, (fi_add_y)
    LD   (HL), A
    ADD  HL, BC
    LD   A, (fi_add_qty)
    LD   (HL), A
    ADD  HL, BC
    ; fi_p1 (gold uses qty_hi when Page-0 id <= ITEM_SLOT_GOLD_MITHRIL)
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    JR   NZ, .ng_p1
    LD   A, (fi_add_id)
    CP   ITEM_SLOT_GOLD_MITHRIL + 1
    JR   NC, .ng_p1
    LD   A, (fi_add_qty_hi)
    JR   .wr_p1
.ng_p1:
    LD   A, (fi_add_p1)
.wr_p1:
    LD   (HL), A
    ADD  HL, BC
    LD   A, (fi_add_flags)
    AND  ITEM_META_FLAGS_MASK
    LD   (HL), A
    ADD  HL, BC
    LD   A, (fi_add_to_hit)
    LD   (HL), A
    ADD  HL, BC
    LD   A, (fi_add_to_dam)
    LD   (HL), A
    ADD  HL, BC
    LD   A, (fi_add_to_ac)
    LD   (HL), A
    ADD  HL, BC
    LD   A, (fi_add_ego)
    LD   (HL), A
    XOR  A
    LD   (fi_add_qty_hi), A
    LD   BC, (fi_add_x)
    LD   A, FLAG_HAS_ITEM
    CALL _mc_tile_or_a
    LD   HL, zp_item_count
    INC  (HL)
    LD   A, (HL)
    LD   (abi_item_count), A
    POP  DE
    LD   A, E
    POP  BC
    POP  DE
    SCF
    RET

; floor_item_find_at — B=y, C=x -> CF=1 A=slot (0..41), CF=0 none.
; Preserves BC, DE, HL, IX, IY.
floor_item_find_at:
    PUSH HL
    PUSH DE
    LD   E, 0
.lp:
    LD   D, 0
    LD   HL, fi_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .next
    PUSH DE
    LD   DE, MAX_FLOOR_ITEMS
    ADD  HL, DE                 ; fi_x
    LD   A, (HL)
    CP   C
    JR   NZ, .no_m
    ADD  HL, DE                 ; fi_y
    LD   A, (HL)
    CP   B
    JR   NZ, .no_m
    POP  DE                     ; E = matching slot
    LD   A, E
    POP  DE
    POP  HL
    SCF
    RET
.no_m:
    POP  DE
.next:
    INC  E
    LD   A, E
    CP   MAX_FLOOR_ITEMS
    JR   C, .lp
    POP  DE
    POP  HL
    OR   A
    RET

; floor_item_remove — A=slot -> clear item & FLAG_HAS_ITEM iff last at tile.
; Preserves BC, DE, HL, IX, IY.
floor_item_remove:
    CP   MAX_FLOOR_ITEMS
    RET  NC
    PUSH BC
    PUSH DE
    PUSH HL
    LD   E, A
    LD   D, 0
    LD   HL, fi_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .done
    LD   (HL), FI_EMPTY
    LD   HL, fi_x
    ADD  HL, DE
    LD   C, (HL)
    LD   HL, fi_y
    ADD  HL, DE
    LD   B, (HL)
    LD   HL, zp_item_count
    LD   A, (HL)
    OR   A
    JR   Z, .chk_last
    DEC  (HL)
.chk_last:
    LD   A, (HL)
    LD   (abi_item_count), A
    CALL floor_item_find_at
    JR   C, .done
    LD   A, (~FLAG_HAS_ITEM) & 0xFF
    CALL _mc_tile_and_a
.done:
    POP  HL
    POP  DE
    POP  BC
    RET

; find_adjacent_empty_tile — B=cy, C=cx -> CF=1 B=y C=x (and ms_spawn_x/y). Preserves IX, IY.
find_adjacent_empty_tile:
    LD   D, B
    LD   E, C
    LD   A, 8
    CALL rng_range
    LD   B, 8
    LD   C, A
.lp:
    PUSH BC
    LD   A, C
    LD   HL, dir_dy
    CALL _mc_add_a_hl
    ADD  A, D
    LD   B, A
    LD   A, C
    LD   HL, dir_dx
    CALL _mc_add_a_hl
    ADD  A, E
    LD   C, A
    CALL _mc_is_empty_floor_bc
    JR   NC, .next
    POP  HL
    LD   (ms_spawn_x), BC
    SCF
    RET
.next:
    POP  BC
    INC  C
    LD   A, C
    AND  0x07
    LD   C, A
    DJNZ .lp
    OR   A
    RET

; find_random_floor — A=0 unlimited or max dist -> CF=1 B=y C=x (and df_target_x/y).
; Preserves IX, IY.
find_random_floor:
    LD   (_mc_frf_limit), A
    LD   HL, 2048
.lp:
    PUSH HL
    LD   A, MAP_COLS - 2
    CALL rng_range
    INC  A
    LD   C, A
    LD   A, MAP_ROWS - 2
    CALL rng_range
    INC  A
    LD   B, A
    LD   A, (_mc_frf_limit)
    OR   A
    JR   Z, .chk_tile
.pull_lp:
    LD   DE, (abi_player_x)     ; E=px, D=py
    LD   A, C
    CALL _mc_abs_diff_e
    LD   L, A
    LD   A, B
    CALL _mc_abs_diff_d
    CP   L
    JR   NC, .ord
    LD   H, L
    LD   L, A
    JR   .got_dist
.ord:
    LD   H, A                   ; H=max, L=min
.got_dist:
    SRL  L
    LD   A, H
    ADD  A, L
    OR   A
    JR   Z, .next
    DEC  A
    LD   HL, _mc_frf_limit
    CP   (HL)
    JR   C, .chk_tile
    LD   A, C
    CALL _mc_half_toward
    LD   C, A
    LD   E, D
    LD   A, B
    CALL _mc_half_toward
    LD   B, A
    JR   .pull_lp
.chk_tile:
    CALL _mc_is_empty_floor_bc
    JR   NC, .next
    POP  HL
    LD   A, C
    LD   (df_target_x), A
    LD   A, B
    LD   (df_target_y), A
    SCF
    RET
.next:
    POP  HL
    DEC  HL
    LD   A, H
    OR   L
    JR   NZ, .lp
    OR   A
    RET

_mc_half_toward:
    PUSH HL
    PUSH DE
    LD   H, 0
    LD   L, E
    CP   E
    JR   C, .ni                 ; add +1 when t >= p (NC), matching 6502 dungeon_features.s:163
    INC  HL
.ni:
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    SRL  H
    RR   L
    LD   A, L
    POP  DE
    POP  HL
    RET

player_search_mode_off:
    PUSH HL
    LD   HL, player_data + PL_FLAGS
    BIT  4, (HL)
    JR   Z, .done
    RES  4, (HL)
    CALL status_mark_dirty
.done:
    POP  HL
    RET

player_wis_save_adj:
    PUSH HL
    PUSH BC
    LD   HL, _mc_wis_floor
    LD   B, 0
.lp:
    CP   (HL)
    JR   C, .done
    INC  HL
    INC  B
    JR   .lp
.done:
    LD   A, B
    POP  BC
    POP  HL
    RET
_mc_wis_floor: DB 8, 15, 18, 68, 88, 108, 118, 0xFF

player_saving_throw:
    LD   E, A
    LD   A, 9
    CALL _mc_race_prop
    LD   B, A
    LD   A, 6
    CALL _mc_class_prop
    LD   L, A
    LD   H, 0
    LD   A, B
    CALL _mc_add_signed_hl
    LD   A, E
    CALL _mc_add_signed_hl
    BIT  7, H
    JR   Z, .pos
    XOR  A
    JR   .roll
.pos:
    LD   A, H
    OR   A
    LD   A, L
    JR   Z, .roll
    LD   A, 100
.roll:
    LD   B, A
    LD   A, 100
    CALL rng_range
    CP   B
    CCF
    RET

element_resist_divisor:
    PUSH DE
    PUSH HL
    LD   D, A
    LD   A, B
    DEC  A
    CP   5
    JR   NC, .done
    LD   HL, _mc_resist_flag
    CALL _mc_add_a_hl
    LD   E, A
    LD   A, (player_pflags)
    AND  E
    CALL NZ, _mc_triple_d
    LD   A, B
    LD   HL, eff_resist_cold_timer
    CP   MS_BREATH_FROST
    JR   Z, .chk_nz
    CP   MS_BREATH_FIRE
    JR   NZ, .done
    LD   HL, zp_eff_resist
.chk_nz:
    LD   A, (HL)
    OR   A
    CALL NZ, _mc_triple_d
.done:
    LD   A, D
    POP  HL
    POP  DE
    RET
_mc_triple_d:
    LD   A, D
    ADD  A, D
    ADD  A, D
    LD   D, A
    RET
_mc_resist_flag: DB PFLAG_RESIST_LIGHT, 0, 0, PFLAG_RESIST_COLD, PFLAG_RESIST_FIRE

roll_dice_bc:
    LD   HL, 0
    LD   A, B
    OR   A
    RET  Z
    LD   A, C
    OR   A
    RET  Z
    PUSH BC
    PUSH DE
    LD   D, 0
.lp:
    LD   A, C
    CALL rng_range
    INC  A
    LD   E, A
    ADD  HL, DE
    DJNZ .lp
    LD   A, H
    OR   A
    LD   A, L
    JR   Z, .done
    LD   A, 0xFF
.done:
    POP  DE
    POP  BC
    RET

tile_is_walkable_a:
    AND  TILE_TYPE_MASK
    JR   Z, .yes
    CP   TILE_DOOR_OPEN
    JR   Z, .yes
    CP   TILE_STAIRS_DN
    JR   Z, .yes
    CP   TILE_STAIRS_UP
    JR   Z, .yes
    CP   TILE_RUBBLE
    JR   Z, .yes
    CP   TILE_TRAP
    JR   Z, .yes
    OR   A
    RET
.yes:
    SCF
    RET

player_search_get_fos:
    PUSH BC
    PUSH HL
    LD   A, 9
    CALL _mc_class_prop
    LD   B, A
    LD   A, 6
    CALL _mc_race_prop
    ADD  A, B
    LD   HL, player_pflags2
    BIT  5, (HL)                ; PFLAG2_SEARCH (0x20)
    JR   Z, .done
    CP   3
    JR   C, .min1
    SUB  2
    JR   .done
.min1:
    LD   A, 1
.done:
    POP  HL
    POP  BC
    RET

player_get_stealth:
    PUSH BC
    PUSH HL
    LD   A, 7
    CALL _mc_class_prop
    LD   B, A
    LD   A, 5
    CALL _mc_race_prop
    ADD  A, B
    BIT  7, A
    JR   Z, .pos
    XOR  A
.pos:
    LD   HL, player_pflags2
    BIT  2, (HL)
    JR   Z, .done
    ADD  A, 3
    CP   10
    JR   C, .done
    LD   A, 9
.done:
    POP  HL
    POP  BC
    RET

player_get_infra_range:
    PUSH BC
    PUSH HL
    LD   A, 1
    CALL _mc_race_prop
    LD   B, A
    LD   A, (zp_eff_infra)
    OR   A
    LD   A, B
    JR   Z, .eq
    INC  A
.eq:
    LD   HL, player_pflags2
    BIT  6, (HL)
    JR   Z, .done
    ADD  A, 2
.done:
    POP  HL
    POP  BC
    RET

; ============================================================================
; Internal Helpers
; ============================================================================

_mc_is_empty_floor_bc:
    CALL map_get_tile
    JR   C, .no
    AND  (TILE_TYPE_MASK | FLAG_OCCUPIED)
    JR   NZ, .no
    CALL _mc_is_player_bc
    JR   Z, .no
    SCF
    RET
.no:
    OR   A
    RET

_mc_is_player_bc:
    PUSH HL
    LD   HL, (abi_player_x)
    LD   A, C
    CP   L
    JR   NZ, .ret
    LD   A, B
    CP   H
.ret:
    POP  HL
    RET

_mc_pool_hl:
    PUSH DE
    LD   E, A
    LD   D, 0
    LD   A, CATALOG_RECORD_NAME_SIZE
    CALL mul_de_a
    LD   DE, tier_name_pool
    ADD  HL, DE
    POP  DE
    RET

_mc_tile_clr_occ:
    LD   A, (~FLAG_OCCUPIED) & 0xFF
_mc_tile_and_a:
    PUSH DE
    LD   D, A
    CALL map_get_tile
    JR   C, .ret_d
    AND  D
    CALL map_set_tile
.ret_d:
    POP  DE
    RET

_mc_tile_or_a:
    PUSH DE
    LD   D, A
    CALL map_get_tile
    JR   C, .done
    OR   D
    CALL map_set_tile
.done:
    POP  DE
    RET

; _mc_add_a_hl_raw / _mc_add_a_hl — HL += A (A = u8), optional load A = (HL).
; Preserves BC, DE, IX, IY.
_mc_add_a_hl:
    CALL _mc_add_a_hl_raw
    LD   A, (HL)
    RET
_mc_add_a_hl_raw:
    PUSH DE
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    POP  DE
    RET

_mc_cheb_dist_hl_de:
    LD   A, L
    CALL _mc_abs_diff_e
    LD   B, A
    LD   A, H
    CALL _mc_abs_diff_d
    CP   B
    RET  NC
    LD   A, B
    RET

_mc_abs_diff_d:
    SUB  D
    RET  NC
    NEG
    RET

_mc_abs_diff_e:
    SUB  E
    RET  NC
    NEG
    RET

; _mc_race_prop / _mc_class_prop — A=prop offset -> A=table[idx*10+off]. Preserves BC, DE, IX, IY.
_mc_race_prop:
    PUSH BC
    LD   B, A
    LD   A, (player_data + PL_RACE)
    LD   HL, race_properties
    JR   _mc_prop_read
_mc_class_prop:
    PUSH BC
    LD   B, A
    LD   A, (player_data + PL_CLASS)
    LD   HL, class_properties
_mc_prop_read:
    ; offset = idx*10 + B = (idx*5)*2 + B
    PUSH DE
    LD   E, A
    ADD  A, A
    ADD  A, A
    ADD  A, E                   ; idx*5
    ADD  A, A                   ; idx*10
    ADD  A, B
    CALL _mc_add_a_hl
    POP  DE
    POP  BC
    RET

_mc_add_signed_hl:
    PUSH DE
    LD   E, A
    ADD  A, A
    SBC  A, A
    LD   D, A
    ADD  HL, DE
    POP  DE
    RET

; _mc_rng_range_16 — HL=limit (>=1) -> HL in [0..limit-1]. Preserves BC, DE, IX, IY.
_mc_rng_range_16:
    LD   A, H
    OR   A
    JR   NZ, .wide
    LD   A, L
    CALL rng_range
    LD   L, A
    LD   H, 0
    RET
.wide:
    DEC  HL
    LD   A, H
    OR   A
    JR   NZ, .ge257
    CALL rng_next_u8
    LD   L, A
    LD   H, 0
    RET
.ge257:
    INC  HL
    PUSH BC
    PUSH DE
    LD   B, H
    LD   C, L
    DEC  HL
    LD   D, 0xFF
.mk_m:
    SLA  H
    JR   C, .roll
    SRL  D
    JR   .mk_m
.roll:
    CALL rng_next_u16
    LD   A, H
    AND  D
    LD   H, A
    OR   A
    PUSH HL
    SBC  HL, BC
    POP  HL
    JR   NC, .roll
    POP  DE
    POP  BC
    RET

; ============================================================================
; Resident Shared Read-Only Tables & Town Creature Names
; ============================================================================

race_properties:
    DB   10,   0, 100,   0,   0,   0,    0,    0,    0,    0
    DB    9,   2, 110,   2,   6,   1, 0xFF, 0xFF,    5,    3
    DB    8,   3, 120,   5,   8,   1, 0xFE, 0xFB,   15,    6
    DB    6,   4, 110,  15,  12,   4, 0xFB, 0xF6,   20,   18
    DB    7,   4, 125,  10,   6,   3, 0xFD, 0xF8,   12,   12
    DB    9,   5, 120,   2,   7, 0xFF,   0,   15,    0,    9
    DB   10,   3, 110, 0xFD,  0, 0xFF,   3,   12, 0xFB, 0xFD
    DB   12,   3, 120, 0xFB, 0xFF, 0xFE, 5,   20, 0xF6, 0xF8

class_properties:
    DB    9,   0,   0,  70,  55,  25,  18,   1,  14,  38
    DB    0,   1,  30,  34,  20,  30,  36,   2,  16,  20
    DB    2,   2,  20,  48,  35,  25,  30,   2,  16,  32
    DB    6,   1,   0,  60,  66,  45,  30,   5,  32,  16
    DB    4,   1,  40,  56,  72,  30,  30,   3,  24,  24
    DB    6,   2,  35,  68,  40,  20,  24,   1,  12,  38

class_level_adj:
    DB     4,   4,   2,   2,   3
    DB     2,   2,   4,   3,   3
    DB     2,   2,   4,   3,   3
    DB     3,   4,   3,   4,   3
    DB     3,   4,   3,   3,   3
    DB     3,   3,   3,   2,   3

equip_slot_for_cat:
    DB   EQUIP_WEAPON, 0xFF, EQUIP_WEAPON, EQUIP_BODY, EQUIP_SHIELD
    DB   EQUIP_HEAD, EQUIP_HANDS, EQUIP_FEET, EQUIP_LIGHT, 0xFF
    DB   0xFF, 0xFF, EQUIP_RING, 0xFF, 0xFF
    DB   0xFF, EQUIP_AMULET, 0xFF, 0xFF, EQUIP_CLOAK, 0xFF

_mc_str_unknown: DB "?", 0
