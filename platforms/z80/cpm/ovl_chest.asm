; ============================================================================
; ovl_chest.asm — Chest Open, Lockpick, Disarm, Traps & Loot Overlay
;                 (OVL_CHEST = 10, DAT slot 9)
; ============================================================================
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0: JP ovl_chest_open         (df_target_x/y -> CF=1 turn consumed, CF=0 none)
;   +3: JP ovl_chest_disarm       (df_target_x/y -> CF=1 turn consumed, CF=0 none)
;   +6 : JP ovl_chest_search         (df_search_chance -> updates df_found & zp_disturb)
;   +9 : JP ovl_chest_fulfill_loot   () -> places staged loot / clears chest_pending_summons
;   +12: JP ovl_chest_pick_item_type () -> 13-tier picker -> A=slot_lo, item_cur_page, fi_add_id/ego
; ============================================================================
; ABI / Contract Invariants:
;   - Preserves IX, IY on every public entry vector.
;   - Cross-overlay calls only through tramp_* (tramp_modal_recalc_equipment,
;     tramp_item_mgt_roll_enchant).
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
    JP   ovl_chest_open           ; +0
    JP   ovl_chest_disarm         ; +3
    JP   ovl_chest_search         ; +6
    JP   ovl_chest_fulfill_loot   ; +9
    JP   ovl_chest_pick_item_type ; +12

; ============================================================================
; Overlay-local constants & lookup tables (read-only inside overlay)
; ============================================================================
; Indexed by fi_item_id - ITEM_SLOT_SMALL_WOODEN_CHEST (0..6):
;   0=small wood, 1=large wood, 2=small iron, 3=large iron,
;   4=small steel, 5=large steel, 6=ruined chest
ovl_chest_loot_flags_tbl:
    DB   0x0F, 0x15, 0x0F, 0x1F, 0x0F, 0x23, 0x00

; Shared race/class disarm tables (mirrors 6502 core/6502/tables.s)
ovl_chest_race_disarm:
    DB   0, 2, 5, 15, 10, 2, 0xFD, 0xFB     ; +0,2,5,15,10,2,-3,-5
ovl_chest_class_disarm:
    DB   25, 30, 25, 45, 30, 20
ovl_chest_class_lvl_disarm:
    DB   2, 3, 3, 4, 3, 2
ovl_chest_dex_disarm_tbl:
    DB   0xF8, 0xFA, 0xFC, 0xFE, 0xFF       ; 3..7: -8,-6,-4,-2,-1
    DB   0, 0, 0, 0, 0                      ; 8..12: 0
    DB   1, 1, 1, 2, 2, 4                   ; 13..18: +1,+1,+1,+2,+2,+4

; Transient scratch (NOT relied on across tramp_modal_recalc_equipment)
ovl_chest_slot:         DB 0
ovl_chest_x:            DB 0
ovl_chest_y:            DB 0
ovl_chest_lflags:       DB 0
ovl_chest_cand_id_lo:   DB 0
ovl_chest_cand_id_hi:   DB 0
ovl_chest_tmp_cat:      DB 0
ovl_chest_tmp_msl:      DB 0
ovl_chest_tmp_p1:       DB 0
ovl_chest_tmp_hit:      DB 0
ovl_chest_tmp_dam:      DB 0
ovl_chest_tmp_ac:       DB 0
ovl_chest_tmp_flg:      DB 0
ovl_chest_tmp_ego:      DB 0

    INCLUDE "pick_item_tables_z80.inc"
    ASSERT pit_sorted_lo >= OVL_WINDOW_BASE
    ASSERT (pit_bit_masks + 8) <= (OVL_WINDOW_BASE + OVL_WINDOW_SIZE)
ovl_chest_tmp_qty:      DB 0

; ============================================================================
; +0: ovl_chest_open
; Input:  (df_target_x, df_target_y)
; Output: CF = 1 turn consumed, CF = 0 no chest / cancelled
; Preserves: IX, IY
; ============================================================================
ovl_chest_open:
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL ovl_chest_find_at
    JR   C, .found
    OR   A
    RET

.found:
    ; A = slot (0..MAX_FLOOR_ITEMS-1)
    LD   (ovl_chest_slot), A
    LD   C, A
    LD   B, 0
    LD   HL, fi_p1
    ADD  HL, BC
    LD   A, (HL)
    AND  CHEST_P1_OPENED
    JP   NZ, .already_open

    ; Step 1: Handle CHEST_P1_LOCKED
    LD   A, (HL)
    AND  CHEST_P1_LOCKED
    JR   Z, .open_unlocked

    LD   A, (zp_eff_confuse)
    OR   A
    JR   Z, .try_pick
    LD   A, HSTR_CHEST_PICK_CONFUSED
    CALL msg_print_huff
    SCF
    RET

.try_pick:
    ; threshold = clamp(skill - 2 * fi_to_hit[slot] - 1, 0, 100)
    CALL ovl_chest_disarm_skill ; A = signed skill (-128..+127)
    BIT  7, A
    JR   NZ, .pick_fail         ; negative - 2*lvl - 1 <= -1
    LD   E, A
    LD   D, 0
    EX   DE, HL                 ; HL = skill (0..127)
    LD   A, (ovl_chest_slot)
    LD   C, A
    LD   B, 0
    LD   DE, fi_to_hit
    EX   DE, HL                 ; DE = skill, HL = fi_to_hit
    ADD  HL, BC
    LD   L, (HL)
    LD   H, 0
    ADD  HL, HL                 ; HL = 2 * lock_level
    INC  HL                     ; HL = 2 * lock_level + 1
    EX   DE, HL                 ; HL = skill, DE = 2*lvl + 1
    OR   A
    SBC  HL, DE                 ; HL = skill - 2*lvl - 1
    JR   C, .pick_fail
    LD   A, H
    OR   A
    JR   NZ, .pick_cap100
    LD   A, L
    OR   A
    JR   Z, .pick_fail
    CP   101
    JR   C, .pick_roll
.pick_cap100:
    LD   A, 100
.pick_roll:
    LD   D, A
    LD   A, 100
    CALL rng_range
    CP   D
    JR   C, .pick_ok
.pick_fail:
    LD   A, HSTR_CHEST_PICK_FAIL
    CALL msg_print_huff
    SCF
    RET

.pick_ok:
    LD   A, (ovl_chest_slot)
    LD   C, A
    LD   B, 0
    LD   HL, fi_p1
    ADD  HL, BC
    RES  0, (HL)                ; Clear CHEST_P1_LOCKED
    LD   HL, fi_to_hit
    ADD  HL, BC
    LD   A, (HL)
    OR   A
    JR   Z, .no_pick_xp
    PUSH BC                     ; tramp_modal_award_xp reloads OVL_CHEST -> restore slot!
    CALL ovl_chest_add_xp_a     ; Award source_level XP (6502 chest.s)
    POP  BC
    LD   A, C
    LD   (ovl_chest_slot), A
.no_pick_xp:
    LD   A, HSTR_CHEST_PICKED
    CALL msg_print_huff
    ; Unlocking opens the chest on this turn if untrapped; UMoria opens after pick
    ; Check armed traps, fire if armed, then mark opened + spawn loot
.open_unlocked:
    LD   A, (ovl_chest_slot)
    LD   C, A
    LD   B, 0
    LD   HL, fi_p1
    ADD  HL, BC
    LD   A, (HL)
    AND  CHEST_P1_TRAP_MASK
    JR   Z, .mark_and_loot

    ; Preserve slot C on stack across _trigger_traps (tramp_modal_recalc_equipment swaps OVL_CHEST)
    PUSH BC
    CALL ovl_chest_trigger_traps ; CF = 1 iff chest exploded & destroyed
    POP  BC
    JR   NC, .restore_slot
    SCF                         ; Turn consumed (chest destroyed)
    RET

.restore_slot:
    LD   A, C
    LD   (ovl_chest_slot), A
.mark_and_loot:
    ; Mark chest opened, clear armed trap bits, generate loot using live dlvl
    LD   A, (ovl_chest_slot)
    LD   C, A
    LD   B, 0
    LD   HL, fi_p1
    ADD  HL, BC
    LD   A, (HL)
    AND  (0xFF ^ CHEST_P1_TRAP_MASK)
    OR   CHEST_P1_OPENED
    LD   (HL), A
    LD   HL, fi_meta_hi
    ADD  HL, BC
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (HL), A

    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    SUB  ITEM_SLOT_SMALL_WOODEN_CHEST
    CP   7
    JR   C, .idx_ok
    XOR  A
.idx_ok:
    LD   E, A
    LD   D, 0
    LD   HL, ovl_chest_loot_flags_tbl
    ADD  HL, DE
    LD   A, (HL)
    LD   (chest_loot_flags), A

    LD   HL, fi_x
    ADD  HL, BC
    LD   A, (HL)
    LD   (chest_loot_x), A
    LD   HL, fi_y
    ADD  HL, BC
    LD   A, (HL)
    LD   (chest_loot_y), A
    LD   A, 1
    LD   (chest_loot_pending), A
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

.already_open:
    SCF
    RET

; ============================================================================
; +3: ovl_chest_disarm
; Input:  (df_target_x, df_target_y)
; Output: CF = 1 turn consumed, CF = 0 no chest / cancelled
; Preserves: IX, IY
; ============================================================================
ovl_chest_disarm:
    LD   A, (df_target_y)
    LD   B, A
    LD   A, (df_target_x)
    LD   C, A
    CALL ovl_chest_find_at
    JR   C, .found
    OR   A
    RET

.found:
    LD   (ovl_chest_slot), A
    LD   C, A
    LD   B, 0
    LD   HL, fi_p1
    ADD  HL, BC
    LD   A, (HL)
    AND  CHEST_P1_TRAP_MASK
    JR   NZ, .armed
    LD   A, HSTR_CHEST_DISARM_NOT_TRAPPED
    CALL msg_print_huff
    OR   A
    RET

.armed:
    LD   A, (HL)
    BIT  6, A                   ; CHEST_P1_TRAP_FOUND
    JR   NZ, .try_disarm
    LD   A, HSTR_CHEST_DISARM_UNFOUND
    CALL msg_print_huff
    OR   A
    RET

.try_disarm:
    CALL ovl_chest_disarm_skill ; A = signed total (-128..+127)
    LD   E, A                   ; E = signed total
    BIT  7, A
    JR   NZ, .thresh_zero
    LD   D, 0
    EX   DE, HL                 ; HL = total (0..127)
    LD   A, (ovl_chest_slot)
    LD   C, A
    LD   B, 0
    LD   DE, fi_to_hit
    EX   DE, HL                 ; DE = total, HL = fi_to_hit
    ADD  HL, BC
    LD   L, (HL)
    LD   H, 0
    INC  HL                     ; HL = source_lvl + 1
    PUSH DE                     ; preserve E = signed total
    EX   DE, HL                 ; HL = total, DE = source_lvl + 1
    OR   A
    SBC  HL, DE                 ; HL = skill - source_lvl - 1
    POP  DE
    JR   C, .thresh_zero
    LD   A, H
    OR   A
    JR   NZ, .thresh_100
    LD   A, L
    CP   101
    JR   C, .roll_disarm
.thresh_100:
    LD   A, 100
    JR   .roll_disarm
.thresh_zero:
    XOR  A
.roll_disarm:
    PUSH DE                     ; E = signed total
    LD   D, A
    LD   A, 100
    CALL rng_range
    CP   D
    POP  DE
    JR   C, .disarm_ok

    ; Failed: if signed total >= 6 && rng_range(total) >= 5 -> minor fail
    BIT  7, E
    JR   NZ, .bad_fail
    LD   A, E
    CP   6
    JR   C, .bad_fail
    CALL rng_range
    CP   5
    JR   C, .bad_fail
    LD   A, HSTR_CHEST_DISARM_FAIL
    CALL msg_print_huff
    SCF
    RET

.bad_fail:
    LD   A, HSTR_CHEST_DISARM_SET_OFF
    CALL msg_print_huff
    LD   A, (ovl_chest_slot)
    LD   C, A
    LD   B, 0
    LD   HL, fi_p1
    ADD  HL, BC
    LD   A, (HL)
    AND  CHEST_P1_TRAP_MASK
    PUSH AF                     ; Keep surviving armed bits (6502 chest.s:644)
    CALL ovl_chest_trigger_traps
    POP  DE                     ; D = saved armed bits
    JR   C, .bf_ret             ; Chest exploded & destroyed
    LD   A, (ovl_chest_slot)
    LD   C, A
    LD   B, 0
    LD   HL, fi_p1
    ADD  HL, BC
    LD   A, (HL)
    OR   D
    LD   (HL), A
.bf_ret:
    SCF
    RET

.disarm_ok:
    LD   A, (ovl_chest_slot)
    LD   C, A
    LD   B, 0
    LD   HL, fi_p1
    ADD  HL, BC
    LD   A, (HL)
    AND  (0xFF ^ CHEST_P1_TRAP_MASK)
    OR   CHEST_P1_TRAP_FOUND
    LD   (HL), A

    ; Grant XP = fi_to_hit[slot] (source_level, 6502 chest.s:625)
    LD   HL, fi_to_hit
    ADD  HL, BC
    LD   A, (HL)
    OR   A
    CALL NZ, ovl_chest_add_xp_a

    LD   A, HSTR_CHEST_DISARMED
    CALL msg_print_huff
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; ============================================================================
; +6: ovl_chest_search
; Scan 8 adjacent tiles around (abi_player_x, abi_player_y) for trapped chests.
; ============================================================================
ovl_chest_search:
    LD   B, 0
    LD   C, 0
.loop:
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .next
    LD   HL, fi_meta_hi
    ADD  HL, BC
    BIT  6, (HL)                ; Chests live on Page 0 only
    JR   NZ, .next
    SUB  ITEM_SLOT_SMALL_WOODEN_CHEST
    CP   7
    JR   NC, .next

    ; Check 8 adjacent tiles (exclude center tile == (player_x, player_y))
    LD   HL, fi_x
    ADD  HL, BC
    LD   A, (abi_player_x)
    SUB  (HL)
    LD   E, A
    ADD  A, 1
    CP   3
    JR   NC, .next

    LD   HL, fi_y
    ADD  HL, BC
    LD   A, (abi_player_y)
    SUB  (HL)
    LD   D, A
    ADD  A, 1
    CP   3
    JR   NC, .next
    LD   A, D
    OR   E
    JR   Z, .next               ; dx == 0 && dy == 0 -> center tile skipped

    ; Must have armed trap; already-found sets df_found=1 quietly (6502 chest_search.s)
    LD   HL, fi_p1
    ADD  HL, BC
    LD   A, (HL)
    AND  CHEST_P1_TRAP_MASK
    JR   Z, .next
    BIT  6, (HL)                ; CHEST_P1_TRAP_FOUND
    JR   Z, .unfound
    LD   A, 1
    LD   (df_found), A
    JR   .next

.unfound:
    LD   A, (df_search_chance)
    OR   A
    JR   Z, .next
    LD   D, A
    LD   A, 100
    CALL rng_range
    CP   D
    JR   NC, .next

    ; Trap discovered!
    SET  6, (HL)                ; Set CHEST_P1_TRAP_FOUND
    LD   A, 1
    LD   (df_found), A
    LD   HL, zp_disturb
    INC  (HL)
    LD   HL, zp_dirty_count
    INC  (HL)
    PUSH BC
    LD   A, HSTR_CHEST_FOUND_TRAP
    CALL msg_print_huff
    POP  BC

.next:
    INC  C
    LD   A, C
    CP   MAX_FLOOR_ITEMS
    JR   C, .loop
    RET

; ============================================================================
; +9: ovl_chest_fulfill_loot
; Fulfill chest_pending_summons (3 awake summons around chest_summon_x/y) AND
; drain md_queue[0..md_queue_count-1] via ovl_chest_generate_loot (MON-014).
; Preserves: IX, IY
; ============================================================================
ovl_chest_fulfill_loot:
    PUSH IX
    PUSH IY

.sum_lp:
    LD   HL, chest_pending_summons
    LD   A, (HL)
    OR   A
    JR   Z, .chk_chest_loot
    DEC  (HL)

    LD   A, 8
    CALL rng_range
    LD   E, A
    LD   D, 0
    LD   HL, dir_dx
    ADD  HL, DE
    LD   A, (chest_summon_x)
    ADD  A, (HL)
    LD   C, A
    LD   HL, dir_dy
    ADD  HL, DE
    LD   A, (chest_summon_y)
    ADD  A, (HL)
    LD   B, A

    ; Never spawn on player's tile
    LD   A, (abi_player_x)
    CP   C
    JR   NZ, .sum_chk_tile
    LD   A, (abi_player_y)
    CP   B
    JR   Z, .sum_lp
.sum_chk_tile:
    CALL map_get_tile
    JR   C, .sum_lp
    AND  TILE_TYPE_MASK
    JR   Z, .sum_chk_occ
    CP   TILE_DOOR_OPEN
    JR   NZ, .sum_lp
.sum_chk_occ:
    CALL monster_find_at
    JR   C, .sum_lp
    PUSH BC
    CALL pick_summon_creature_type
    POP  BC
    CALL monster_spawn_awake
    LD   HL, zp_dirty_count
    INC  (HL)
    JR   .sum_lp

.chk_chest_loot:
    LD   HL, chest_loot_pending
    LD   A, (HL)
    OR   A
    JR   Z, .md_lp
    LD   (HL), 0
    LD   A, (chest_loot_y)
    LD   B, A
    LD   A, (chest_loot_x)
    LD   C, A
    CALL ovl_chest_find_at
    JR   NC, .md_lp
    LD   A, C
    LD   (ovl_chest_x), A
    LD   A, B
    LD   (ovl_chest_y), A
    LD   A, (chest_loot_flags)
    LD   (ovl_chest_lflags), A
    CALL ovl_chest_generate_loot

.md_lp:
    LD   HL, md_queue_count
    LD   A, (HL)
    OR   A
    JR   Z, .fulfill_done
    DEC  (HL)
    LD   E, (HL)
    LD   D, 0
    LD   HL, md_queue_x
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_chest_x), A
    LD   HL, md_queue_y
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_chest_y), A
    LD   HL, md_queue_flags
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_chest_lflags), A
    CALL ovl_chest_generate_loot
    JR   .md_lp

.fulfill_done:
    POP  IY
    POP  IX
    RET

; ============================================================================
; Internal Helpers
; ============================================================================

; ovl_chest_find_at — Find chest at (B=y, C=x).
; Output: CF=1 & A=slot (0..41), CF=0 if none. Preserves B, C, IX, IY.
ovl_chest_find_at:
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

; ovl_chest_disarm_skill — Compute signed disarm skill (-128..+127) in A.
; Matches 6502 chest_disarm_skill (core/6502/chest.s):
;   base  = dex_adj + class_disarm + race_disarm + 2
;   total = clamp_s8(dex_adj * base) + int_adj + (class_lvl * PL_LEVEL) / 3
ovl_chest_disarm_skill:
    ; dex_adj (-8..+8)
    LD   A, (player_data + PL_DEX_CUR)
    CALL .dex_adj
    PUSH AF                     ; save signed dex_adj
    LD   C, A                   ; C = base accum

    ; + class_disarm (20..45)
    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .cls_ok
    XOR  A
.cls_ok:
    LD   E, A
    LD   D, 0
    LD   HL, ovl_chest_class_disarm
    ADD  HL, DE
    LD   A, C
    ADD  A, (HL)
    LD   C, A

    ; + race_disarm (-5..+15) + 2
    LD   A, (player_data + PL_RACE)
    CP   RACE_COUNT
    JR   C, .rc_ok
    XOR  A
.rc_ok:
    LD   E, A
    LD   HL, ovl_chest_race_disarm
    ADD  HL, DE
    LD   A, C
    ADD  A, (HL)
    ADD  A, 2
    LD   C, A                   ; C = df_disarm_base (+9..+70)

    ; total = clamp_s8(dex_adj * base)
    POP  AF                     ; A = signed dex_adj (-8..+8)
    OR   A
    JR   Z, .mul_done           ; 0 * base = 0
    PUSH AF                     ; save sign of dex_adj
    BIT  7, A
    JR   Z, .mul_pos
    NEG                         ; A = |dex_adj| (1..8)
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

    ; + int_adj (signed saturating)
    PUSH DE
    LD   A, (player_data + PL_INT_CUR)
    CALL .int_adj
    POP  DE
    CALL .add_signed

    ; + (class_lvl_dis * PL_LEVEL) / 3
    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .cl2
    XOR  A
.cl2:
    LD   C, A
    LD   B, 0
    LD   HL, ovl_chest_class_lvl_disarm
    ADD  HL, BC
    LD   B, (HL)
    LD   A, (player_data + PL_LEVEL)
    PUSH DE
    LD   D, 0
    LD   E, A
    LD   A, B
    CALL mul_de_a               ; HL = class_lvl * level
    LD   C, 3
    CALL div_hl_c               ; HL /= 3 (0..53)
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
    CALL .add_signed            ; E = signed total (-128..+127)

    LD   A, (zp_eff_confuse)
    OR   A
    JR   Z, .no_conf
    CALL .div10_signed
.no_conf:
    LD   A, (zp_eff_blind)
    OR   A
    JR   NZ, .div10_lit
    LD   A, (player_data + PL_LIGHT_RAD)
    OR   A
    JR   NZ, .done
    ; Check if player tile has FLAG_LIT (6502 chest.s -> player_search_has_no_light)
    PUSH DE
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    CALL map_get_tile
    POP  DE
    JR   C, .div10_lit
    BIT  3, A                   ; FLAG_LIT
    JR   NZ, .done
.div10_lit:
    CALL .div10_signed
.done:
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
    JR   NC, .dx3
    LD   A, 0xF8
    RET
.dx3:
    CP   19
    JR   NC, .dx19
    SUB  3
    LD   E, A
    LD   D, 0
    LD   HL, ovl_chest_dex_disarm_tbl
    ADD  HL, DE
    LD   A, (HL)
    RET
.dx19:
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
    JR   NC, .in6
    SUB  6
    RET
.in6:
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

; ovl_chest_trigger_traps — Execute all armed chest trap bits for slot C (VMS order).
; Output: CF = 1 iff chest exploded & destroyed; CF = 0 otherwise.
ovl_chest_trigger_traps:
    LD   B, 0
    LD   HL, fi_x
    ADD  HL, BC
    LD   A, (HL)
    LD   (chest_summon_x), A
    LD   HL, fi_y
    ADD  HL, BC
    LD   A, (HL)
    LD   (chest_summon_y), A
    LD   HL, fi_p1
    ADD  HL, BC
    LD   A, (HL)
    OR   CHEST_P1_TRAP_FOUND
    LD   (HL), A
    AND  CHEST_P1_TRAP_MASK
    LD   D, A                   ; D = trap_bits, C = slot

    ; 1. CHEST_P1_TRAP_STR (0x02): STR drain + 1d4 HP damage (DEATH_CHEST_NEEDLE)
    BIT  1, D
    JR   Z, .chk_poison
    PUSH BC
    PUSH DE
    LD   A, HSTR_CHEST_NEEDLE
    CALL msg_print_huff
    LD   A, (player_sust_mask)
    AND  SUST_STR
    JR   NZ, .str_done
    LD   A, STAT_STR
    CALL player_drain_stat_a
    JR   NC, .str_done
    LD   A, HSTR_CHEST_WEAKENED
    CALL msg_print_huff
.str_done:
    LD   A, HSTR_CHEST_DEATH_NEEDLE
    LD   L, DEATH_CHEST_NEEDLE
    CALL ovl_chest_prep_death
    LD   A, 4
    CALL rng_range
    INC  A
    LD   L, A
    LD   H, 0
    LD   A, DEATH_CHEST_NEEDLE
    CALL ovl_chest_apply_trap_dmg
    POP  DE
    POP  BC

.chk_poison:
    ; 2. CHEST_P1_TRAP_POISON (0x04): 1d6 HP + poison timer
    BIT  2, D
    JR   Z, .chk_para
    PUSH BC
    PUSH DE
    LD   A, HSTR_CHEST_NEEDLE
    CALL msg_print_huff
    LD   A, HSTR_CHEST_DEATH_NEEDLE
    LD   L, DEATH_CHEST_NEEDLE
    CALL ovl_chest_prep_death
    LD   A, 6
    CALL rng_range
    INC  A
    LD   L, A
    LD   H, 0
    LD   A, DEATH_CHEST_NEEDLE
    CALL ovl_chest_apply_trap_dmg
    LD   A, 20
    CALL rng_range
    ADD  A, 10
    LD   HL, zp_eff_poison
    ADD  A, (HL)
    JR   NC, .psn_ok
    LD   A, 255
.psn_ok:
    LD   (HL), A
    POP  DE
    POP  BC

.chk_para:
    ; 3. CHEST_P1_TRAP_PARA (0x08): overwrite zp_eff_paralyze = 10..29
    BIT  3, D
    JR   Z, .chk_expl
    PUSH BC
    PUSH DE
    LD   A, HSTR_CHEST_GAS
    CALL msg_print_huff
    LD   A, (player_pflags)
    AND  PFLAG_FREE_ACT
    JR   Z, .para_hit
    LD   A, HSTR_CHEST_UNAFFECTED
    CALL msg_print_huff
    JR   .para_done
.para_hit:
    LD   A, HSTR_CHEST_CHOKE
    CALL msg_print_huff
    LD   A, 20
    CALL rng_range
    ADD  A, 10
    LD   (zp_eff_paralyze), A
.para_done:
    POP  DE
    POP  BC

.chk_expl:
    ; 4. CHEST_P1_TRAP_EXPL (0x10): remove chest first, then 5d8 damage
    BIT  4, D
    JR   Z, .chk_summon
    PUSH BC
    PUSH DE
    LD   A, HSTR_CHEST_EXPLOSION
    CALL msg_print_huff
    POP  DE
    POP  BC
    PUSH BC
    PUSH DE
    LD   B, 0
    LD   HL, fi_x
    ADD  HL, BC
    LD   E, (HL)                ; E = chest x
    LD   HL, fi_y
    ADD  HL, BC
    LD   D, (HL)                ; D = chest y
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   (HL), FI_EMPTY
    LD   HL, zp_item_count
    LD   A, (HL)
    OR   A
    JR   Z, .cnt_zero
    DEC  (HL)
    LD   A, (HL)
    LD   (abi_item_count), A
.cnt_zero:
    CALL ovl_chest_refresh_has_item
    LD   HL, zp_dirty_count
    INC  (HL)

    LD   A, HSTR_CHEST_DEATH_EXPLODING
    LD   L, DEATH_CHEST_EXPLOSION
    CALL ovl_chest_prep_death
    LD   B, 5
    LD   C, 8
    CALL roll_dice_bc
    LD   A, DEATH_CHEST_EXPLOSION
    CALL ovl_chest_apply_trap_dmg
    POP  DE
    POP  BC

.chk_summon:
    ; 5. CHEST_P1_TRAP_SUMMON (0x20): defer 3 summons (runs even after explosion)
    BIT  5, D
    JR   Z, .traps_fin
    LD   A, 3
    LD   (chest_pending_summons), A

.traps_fin:
    BIT  4, D
    JR   Z, .clear_armed
    SCF
    RET

.clear_armed:
    LD   B, 0
    LD   HL, fi_p1
    ADD  HL, BC
    LD   A, (HL)
    AND  (0xFF ^ CHEST_P1_TRAP_MASK)
    LD   (HL), A
    OR   A
    RET

ovl_chest_apply_trap_dmg:
    PUSH HL
    CALL turn_apply_one_damage
    POP  HL
    LD   A, L
    PUSH AF
    LD   A, HSTR_DF_DAMAGE_PRE
    LD   DE, temp_str_buf
    CALL huff_decode_string     ; HL = temp_str_buf
.at_end1:
    LD   A, (HL)
    OR   A
    JR   Z, .at_num
    INC  HL
    JR   .at_end1
.at_num:
    POP  AF
    EX   DE, HL
    CALL fmt_u8_dec             ; DE at NUL
    PUSH DE
    LD   A, HSTR_DF_DAMAGE_POST
    LD   DE, line_buf
    CALL huff_decode_string
    POP  DE
.at_cp2:
    LD   A, (HL)
    LD   (DE), A
    INC  HL
    INC  DE
    OR   A
    JR   NZ, .at_cp2
    LD   HL, temp_str_buf
    JP   msg_print_str

; ovl_chest_prep_death — Store df_death_source = L, df_death_hstr = A, decode into death_cause_buf
ovl_chest_prep_death:
    LD   (df_death_hstr), A
    LD   A, L
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
    RET

; ovl_chest_refresh_has_item — Clear FLAG_HAS_ITEM at (D=y, E=x) iff no fi_* remains
ovl_chest_refresh_has_item:
    LD   B, 0
    LD   C, 0
.lp:
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .nx
    LD   HL, fi_x
    ADD  HL, BC
    LD   A, (HL)
    CP   E
    JR   NZ, .nx
    LD   HL, fi_y
    ADD  HL, BC
    LD   A, (HL)
    CP   D
    RET  Z                      ; Still another floor item there
.nx:
    INC  C
    LD   A, C
    CP   MAX_FLOOR_ITEMS
    JR   C, .lp

    LD   B, D
    LD   C, E
    CALL map_get_tile
    RET  C
    RES  1, A                   ; Clear FLAG_HAS_ITEM
    JP   map_set_tile

; ovl_chest_add_xp_a — Award A XP via OVL_MODAL
ovl_chest_add_xp_a:
    LD   L, A
    LD   H, 0
    JP   tramp_modal_award_xp

; ============================================================================
; ovl_chest_generate_loot — Scatter gold + items per ovl_chest_lflags/src_lvl
; Decodes all 7 VMS/MON-014 drop bits (bits 0-1 type, 2..6 drop counts).
; Live loop state stays strictly on CPU stack across tramp_item_mgt_roll_enchant.
; ============================================================================
ovl_chest_generate_loot:
    LD   A, (ovl_chest_lflags)
    AND  0x03
    RET  Z
    LD   C, A                   ; C = drop type mask (1=obj, 2=gold, 3=mixed)
    LD   A, (ovl_chest_lflags)
    LD   D, A                   ; D = flags
    LD   B, 0                   ; B = total drop count

    ; Bit 2 (0x04): 60% one drop
    BIT  2, D
    JR   Z, .no60
    PUSH BC
    PUSH DE
    LD   A, 100
    CALL rng_range
    POP  DE
    POP  BC
    CP   60
    JR   NC, .no60
    INC  B
.no60:
    ; Bit 3 (0x08): 90% one drop
    BIT  3, D
    JR   Z, .no90
    PUSH BC
    PUSH DE
    LD   A, 100
    CALL rng_range
    POP  DE
    POP  BC
    CP   90
    JR   NC, .no90
    INC  B
.no90:
    ; Bit 4 (0x10): randint(2) drops (1..2)
    BIT  4, D
    JR   Z, .no1d2
    PUSH BC
    PUSH DE
    LD   A, 2
    CALL rng_range
    POP  DE
    POP  BC
    INC  A
    ADD  A, B
    LD   B, A
.no1d2:
    ; Bit 5 (0x20): 2d2 drops
    BIT  5, D
    JR   Z, .no2d2
    PUSH BC
    PUSH DE
    LD   A, 2
    CALL rng_range
    LD   E, A
    LD   A, 2
    CALL rng_range
    ADD  A, E
    ADD  A, 2
    POP  DE
    POP  BC
    ADD  A, B
    LD   B, A
.no2d2:
    ; Bit 6 (0x40): 4d3 drops
    BIT  6, D
    JR   Z, .chk_cnt
    LD   E, 4
.lp4d3:
    PUSH BC
    PUSH DE
    LD   A, 3
    CALL rng_range
    POP  DE
    POP  BC
    INC  A
    ADD  A, B
    LD   B, A
    DEC  E
    JR   NZ, .lp4d3

.chk_cnt:
    LD   A, B
    OR   A
    RET  Z

    ; Stage stack-invariant context across tramp_item_mgt_roll_enchant:
    ; L = typ_mask, D = chest_y, E = chest_x, B = remaining drops
    LD   L, C
    LD   A, (ovl_chest_y)
    LD   D, A
    LD   A, (ovl_chest_x)
    LD   E, A

.drop_loop:
    PUSH BC
    PUSH DE
    PUSH HL
    CALL ovl_chest_spawn_one
    POP  HL
    POP  DE
    POP  BC
    DJNZ .drop_loop
    RET

; ovl_chest_spawn_one — Place 1 drop near (D=cy, E=cx) with L=typ_mask.
; Safe across tramp_item_mgt_roll_enchant reload (no overlay-local state retained).
ovl_chest_spawn_one:
    ; Pick free cell (B=ty, C=tx) in 5x5 box (10 tries), fallback center if item-free
    PUSH HL
    PUSH DE
    CALL ovl_chest_pick_drop_cell_5x5
    POP  DE
    POP  HL
    RET  NC                     ; No free floor slot

    ; Resolve this drop type (L=3 -> 50/50 1=object / 2=gold)
    LD   A, L
    CP   3
    JR   NZ, .typ_ok
    PUSH BC
    PUSH HL
    LD   A, 100
    CALL rng_range
    POP  HL
    POP  BC
    CP   50
    LD   A, 1
    JR   C, .typ_ok
    LD   A, 2
.typ_ok:
    CP   2
    JR   Z, .do_gold

    ; --- Object drop (always uses live abi_player_dlvl, matching 6502 chest_loot.s) ---
    PUSH BC                     ; [ty, tx]
    CALL ovl_chest_pick_item_type ; sets fi_add_id, item_cur_page, fi_add_ego=page
    CALL tramp_item_mgt_roll_enchant
    POP  BC                     ; B = ty, C = tx
    LD   A, C
    LD   (fi_add_x), A
    LD   A, B
    LD   (fi_add_y), A

    LD   A, 1
    LD   (fi_add_qty), A
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (fi_add_id)
    CALL icat_select_id
    JR   C, .add_floor
    CALL icat_get_level_missile
    BIT  7, B                   ; Ammo drop stack = 5 + rng(6) (6502 chest_loot.s:433)
    JR   Z, .add_floor
    LD   A, 6
    CALL rng_range
    ADD  A, 5
    LD   (fi_add_qty), A
.add_floor:
    CALL floor_item_add
    RET  NC
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

.do_gold:
    ; Stage plain gold (id 0 or 1, 16-bit qty = rng_range_u16(max(1,dlvl)*10) + 5)
    PUSH BC                     ; [ty, tx]
    XOR  A
    LD   HL, fi_add_p1
    LD   B, 6                   ; p1, to_hit, to_dam, to_ac, flags, ego
.zmeta:
    LD   (HL), A
    INC  HL
    DJNZ .zmeta
    LD   A, ITEM_SLOT_GOLD_LARGE + 1
    CALL rng_range
    LD   (fi_add_id), A
    LD   A, (abi_player_dlvl)
    OR   A
    JR   NZ, .dl_nz
    INC  A
.dl_nz:
    LD   E, A
    LD   D, 0
    LD   A, 10
    CALL mul_de_a               ; HL = limit (10..990)
    CALL ovl_chest_rng_range_u16 ; HL = 0..limit-1
    LD   DE, 5
    ADD  HL, DE
    LD   A, L
    LD   (fi_add_qty), A
    LD   A, H
    LD   (fi_add_qty_hi), A     ; High byte of floor gold amount
    POP  BC
    LD   A, C
    LD   (fi_add_x), A
    LD   A, B
    LD   (fi_add_y), A
    JR   .add_floor

; +12: ovl_chest_pick_item_type — Exact 6502 13-tier picker (pick_item_type_cold.s)
; Output: A = paged_slot_lo, item_cur_page = 0|ITEM_PAGE_BIT, fi_add_id/fi_add_ego staged.
ovl_chest_pick_item_type:
    LD   A, (abi_player_dlvl)
    ADD  A, 3
    JR   NC, .el_nc
    LD   A, 255
.el_nc:
    SRL  A
    SRL  A
    CP   PIT_MAX_LEVEL + 1
    JR   C, .el_ok
    LD   A, PIT_MAX_LEVEL
.el_ok:
    LD   E, A                   ; E = eff_level (0..12)
    OR   A
    JR   Z, .no_great
    PUSH DE
    LD   A, 12
    CALL rng_range
    POP  DE
    OR   A
    JR   NZ, .no_great
    PUSH DE
    LD   A, PIT_MAX_LEVEL
    CALL rng_range
    INC  A                      ; d = 1..12
    LD   C, A
    POP  DE
    LD   A, E
    ADD  A, A
    ADD  A, A
    LD   B, A
    ADD  A, A
    ADD  A, B                   ; eff * 12 (<= 144)
    LD   L, A
    LD   H, 0
    CALL div_hl_c
    LD   A, L
    INC  A
    CP   PIT_MAX_LEVEL + 1
    JR   C, .gr_ok
    LD   A, PIT_MAX_LEVEL
.gr_ok:
    LD   E, A
.no_great:
    LD   D, 0
    LD   HL, pit_level_bounds_lo
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_chest_cand_id_lo), A
    LD   HL, pit_level_bounds_hi
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_chest_cand_id_hi), A

    LD   A, 2
    CALL rng_range
    OR   A
    JR   NZ, .best_of_3

    LD   HL, (ovl_chest_cand_id_lo)
    CALL ovl_chest_rng_range_u16
    JR   .decode_idx

.best_of_3:
    LD   HL, (ovl_chest_cand_id_lo)
    CALL ovl_chest_rng_range_u16
    LD   B, 2
.bo3_lp:
    PUSH BC
    PUSH HL                     ; save best
    LD   HL, (ovl_chest_cand_id_lo)
    CALL ovl_chest_rng_range_u16 ; HL = candidate
    POP  DE                     ; DE = best
    PUSH HL
    OR   A
    SBC  HL, DE                 ; cand - best
    POP  HL
    JR   NC, .bo3_keep_cand
    EX   DE, HL                 ; keep DE (best)
.bo3_keep_cand:
    POP  BC
    DJNZ .bo3_lp

    ; Find tier E (0..12) where best (HL) < pit_level_bounds[E]
    LD   E, 0
.find_tier:
    PUSH HL
    LD   D, 0
    LD   HL, pit_level_bounds_lo
    ADD  HL, DE
    LD   C, (HL)
    LD   HL, pit_level_bounds_hi
    ADD  HL, DE
    LD   B, (HL)                ; BC = bounds[E]
    POP  HL
    PUSH HL
    OR   A
    SBC  HL, BC                 ; best - bounds[E]
    POP  HL
    JR   C, .found_tier
    INC  E
    LD   A, E
    CP   PIT_MAX_LEVEL
    JR   C, .find_tier

.found_tier:
    LD   A, E
    OR   A
    JR   NZ, .tier_nz
    LD   A, (pit_level_bounds_lo)
    CALL rng_range
    LD   L, A
    LD   H, 0
    JR   .decode_idx

.tier_nz:
    LD   D, 0
    LD   HL, pit_level_bounds_lo - 1
    ADD  HL, DE
    LD   C, (HL)                ; prev_lo
    LD   HL, pit_level_bounds_lo
    ADD  HL, DE
    LD   A, (HL)
    SUB  C                      ; span = lo[E] - lo[E-1] (1..54)
    PUSH DE
    CALL rng_range
    POP  DE
    LD   C, A                   ; r in 0..span-1
    LD   D, 0
    LD   HL, pit_level_bounds_lo - 1
    ADD  HL, DE
    LD   A, (HL)
    LD   HL, pit_level_bounds_hi - 1
    ADD  HL, DE
    LD   H, (HL)
    LD   L, A                   ; HL = bounds[E-1]
    LD   B, 0
    ADD  HL, BC                 ; HL = bounds[E-1] + r

.decode_idx:
    PUSH HL                     ; [idx]
    LD   A, L
    AND  0x07
    LD   E, A
    LD   D, 0
    LD   HL, pit_bit_masks
    ADD  HL, DE
    LD   C, (HL)                ; C = bit mask
    POP  HL
    PUSH HL
    SRL  H
    RR   L
    SRL  L
    SRL  L                      ; HL = idx >> 3
    LD   DE, pit_sorted_hi_bits
    ADD  HL, DE
    LD   A, (HL)
    AND  C
    JR   Z, .pg0
    LD   A, ITEM_PAGE_BIT
.pg0:
    LD   (item_cur_page), A
    LD   (fi_add_ego), A
    POP  HL                     ; idx
    LD   DE, pit_sorted_lo
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_id), A
    RET

; Uniform 16-bit RNG in [0..HL-1] (0 < HL <= 1023). Clobbers AF, BC, DE, HL.
ovl_chest_rng_range_u16:
    LD   D, H
    LD   E, L
.ru_try:
    PUSH DE
    CALL rng_next_u16
    POP  DE
    LD   A, H
    AND  0x03
    LD   H, A
    OR   A
    SBC  HL, DE
    JR   C, .ru_ok
    JR   .ru_try
.ru_ok:
    ADD  HL, DE
    RET

; Find walkable, monster-free, item-free cell in 5x5 around (D=cy, E=cx)
; Output: CF=1, B=ty, C=tx; CF=0 if none
ovl_chest_pick_drop_cell_5x5:
    LD   B, 10
.p5_lp:
    PUSH BC
    PUSH DE
    LD   A, 5
    CALL rng_range
    SUB  2
    POP  DE
    PUSH DE
    ADD  A, E
    LD   C, A
    PUSH BC
    LD   A, 5
    CALL rng_range
    SUB  2
    POP  BC
    POP  DE
    PUSH DE
    ADD  A, D
    LD   B, A
    CALL .is_cell_free
    POP  DE
    POP  HL                     ; saved loop BC
    RET  C                      ; B=ty, C=tx
    LD   B, H
    DJNZ .p5_lp
.p5_no:
    OR   A
    RET

.is_cell_free:
    LD   A, C
    OR   A
    RET  Z
    CP   MAP_COLS - 1
    JR   NC, .p5_no
    LD   A, B
    OR   A
    RET  Z
    CP   MAP_ROWS - 1
    JR   NC, .p5_no
    CALL map_get_tile
    JR   C, .p5_no
    AND  TILE_TYPE_MASK
    JR   Z, .icf_walk
    CP   TILE_DOOR_OPEN
    JR   NZ, .p5_no
.icf_walk:
    CALL monster_find_at
    JR   C, .p5_no
    CALL floor_item_find_at
    CCF
    RET

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end
    SAVEBIN "ovl_chest.ovl", ovl_start, ovl_end - ovl_start
