; ============================================================================
; platforms/z80/cpm/ovl_mon_ext.asm — Monster Melee, Spells, Breaths & Acid Overlay
;
; Overlay ID: OVL_MON_EXT = 18 (DAT slot 23), loaded at OVL_WINDOW_BASE (0x5600)
; Jump table:
;   +0 : JP ovl_mon_ext_attack
;   +3 : JP ovl_mon_ext_cast
;   +6 : JP ovl_mon_ext_acid_armour
;
; Contracts:
;   - Pure 0xNN hex syntax only (sjasmplus v1.24.0).
;   - Preserves IX and IY across every public entry point.
;   - Cross-overlay calls only via tramp_* (keeps live state on stack or BSS).
;   - References: core/6502/monster_attack.s, monster_attack_effects.s,
;     monster_acid.s, monster_magic.s; MON-012/015/019/023/025/027/028/032/036/037/038/040/041.
; ============================================================================

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "item_ids_z80.inc"
    DEFINE HUFF_CONSTS_ONLY 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_CONSTS_ONLY
    INCLUDE "main_exp.inc"

    ORG  OVL_WINDOW_BASE

ovl_start:
    JP   ovl_mon_ext_attack         ; +0
    JP   ovl_mon_ext_cast           ; +3
    JP   ovl_mon_ext_acid_armour    ; +6

; ============================================================================
; +0: ovl_mon_ext_attack — Monster melee round using (zp_mon_idx, zp_mon_type)
; Preserves: IX, IY
; ============================================================================
ovl_mon_ext_attack:
    PUSH IX
    PUSH IY
    CALL player_search_mode_off

    ; Early exit on ATK_NONE in slot 0 (before disturbing / recall)
    LD   A, (zp_mon_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_atk0_type
    ADD  HL, DE
    LD   A, (HL)
    AND  ATK_TYPE_MASK
    OR   A
    JR   Z, .exit_ret

    ; MON-038: monster melee disturbs resting/running/searching player
    LD   HL, zp_disturb
    INC  (HL)

    ; MON-019: Protection from Evil repels evil monsters with level <= player level
    LD   A, (zp_eff_protect)
    OR   A
    JR   Z, .do_slots
    LD   A, (zp_mon_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_mflags
    ADD  HL, DE
    LD   A, (HL)
    AND  CF_EVIL
    JR   Z, .do_slots
    LD   HL, cr_level
    ADD  HL, DE
    LD   A, (player_data + PL_LEVEL)
    CP   (HL)
    JR   C, .do_slots
    LD   B, HSTR_MAT_REPELLED
    CALL _me_print_mon_hstr
.exit_ret:
    POP  IY
    POP  IX
    RET

.do_slots:
    XOR  A
    LD   (me_any_hit), A
    LD   (me_hit_verb), A
.slot_lp:
    CP   4
    JR   NC, .round_done
    PUSH AF                     ; save atk slot index (0..3)

    ; Fetch raw_type, dice, raw_sides for slot A and zp_mon_type
    CALL _me_load_atk_slot      ; B = adtype, C = adesc, D = dice, E = sides
    LD   A, B
    OR   A
    JR   Z, .slot_stop
    CP   ATK_BLANK
    JR   Z, .slot_next
    CP   25
    JR   NC, .slot_next
    CP   ATK_AGGRAVATE          ; VMS: aggravate bypasses hit roll & ends round
    JR   Z, .do_aggravate

    ; Compute hit check: clamp(signed_bth + 3*cr_level, 0, 255)
    PUSH BC
    PUSH DE
    CALL _me_check_hit          ; CF = 1 hit, CF = 0 miss
    POP  DE
    POP  BC
    JR   NC, .slot_next         ; round summary prints "misses you." if all miss

    ; Connecting blow: track any_hit and winning round-summary verb
    LD   HL, me_any_hit
    INC  (HL)
    LD   A, C
    OR   A
    JR   Z, .verb_ok
    CP   ADESC_BITES
    JR   NC, .set_verb
    LD   A, (me_hit_verb)
    OR   A
    JR   NZ, .verb_ok
.set_verb:
    LD   A, C
    LD   (me_hit_verb), A
.verb_ok:
    ; Roll base damage (D = dice, E = sides) -> HL
    PUSH BC
    LD   B, D
    LD   C, E
    CALL roll_dice_bc           ; HL = sum
    POP  BC                     ; B = adtype

    ; Dispatch attack type B (1..24)
    CALL _me_dispatch_attack    ; CF = 1 if player died (stop round)
    JR   NC, .slot_next
.slot_abort:
    POP  AF
    JR   .exit_ret

.slot_next:
    POP  AF
    INC  A
    JR   .slot_lp

.do_aggravate:
    POP  AF
    CALL monster_aggravate_all
    LD   A, HSTR_MAT_SHRIEK
    CALL msg_print_huff
    JR   .exit_ret

.slot_stop:
    POP  AF
.round_done:
    LD   A, (zp_mon_type)
    CALL recall_mark_atk_slot

    LD   A, (me_any_hit)
    OR   A
    JR   Z, .sum_miss
    LD   A, (me_hit_verb)
    CP   ADESC_BITES
    JR   C, .sum_hits
    CALL _me_print_verb_msg
    JR   .exit_ret
.sum_hits:
    LD   B, HSTR_MAT_HITS
    CALL _me_print_mon_hstr
    JP   .exit_ret
.sum_miss:
    LD   B, HSTR_MAT_MISS
    CALL _me_print_mon_hstr
    JP   .exit_ret

; ============================================================================
; +3: ovl_mon_ext_cast — Monster spellcasting (uniform pick + execution)
; Preserves: IX, IY
; ============================================================================
ovl_mon_ext_cast:
    PUSH IX
    PUSH IY

    ; Build choice table in line_buf[0..19] (max 20 entries; safe scratch before printing)
    LD   A, (zp_mon_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_spell_flags
    ADD  HL, DE
    LD   B, (HL)
    LD   HL, cr_spell_chance
    ADD  HL, DE
    LD   C, (HL)                ; C = chance/breath/hold
    LD   HL, cr_spell_flags2
    ADD  HL, DE
    LD   A, (HL)
    AND  0x1F
    LD   D, A                   ; D = spell_flags2 & 0x1F

    LD   HL, line_buf
    LD   E, 0                   ; count

    ; 1. cr_spell_flags bits 0..7 (tokens 1..8; Multi-Hued breath expands to 5 choices!)
    LD   A, 1
.sf1_lp:
    BIT  0, B
    JR   Z, .sf1_nx
    CP   2                      ; bit 1 = MSF_BREATH
    JR   NZ, .sf1_add
    PUSH AF
    LD   A, C
    RRCA
    RRCA
    RRCA
    RRCA
    AND  0x07
    CP   MS_BREATH_ALL
    JR   NZ, .one_br
    ; Multi-Hued: push 5 breath choices (tokens 0x81..0x85)
    LD   A, 0x81
.mh_lp:
    LD   (HL), A
    INC  HL
    INC  E
    INC  A
    CP   0x86
    JR   C, .mh_lp
    POP  AF
    JR   .sf1_nx
.one_br:
    OR   A
    JR   Z, .pop_br
    OR   0x80                   ; token 0x81..0x85
    LD   (HL), A
    INC  HL
    INC  E
.pop_br:
    POP  AF
    JR   .sf1_nx
.sf1_add:
    LD   (HL), A                ; token 1..8
    INC  HL
    INC  E
.sf1_nx:
    SRL  B
    INC  A
    CP   9
    JR   C, .sf1_lp

    ; 2. MS_HOLD (bit 7 of cr_spell_chance) -> token 9
    BIT  7, C
    JR   Z, .sf2_go
    LD   (HL), 9
    INC  HL
    INC  E

.sf2_go:
    ; 3. cr_spell_flags2 bits 0..4 -> tokens 10..14
    LD   A, 10
.sf2_lp:
    BIT  0, D
    JR   Z, .sf2_nx
    LD   (HL), A
    INC  HL
    INC  E
.sf2_nx:
    SRL  D
    INC  A
    CP   15
    JR   C, .sf2_lp

    LD   A, E
    OR   A
    JR   Z, .cast_done          ; no spells enabled

    CALL rng_range              ; 0..count-1
    LD   E, A
    LD   D, 0
    LD   HL, line_buf
    ADD  HL, DE
    LD   A, (HL)                ; picked spell token

    ; Mark recall spell seen (per-MSF_* bit 1<<X for tokens 1..8, MSF_BREATH for 0x81..0x85, 0x01 for 9..14)
    PUSH AF
    LD   B, MSF_BREATH
    BIT  7, A
    JR   NZ, .mk_spl
    CP   9
    LD   B, 0x01
    JR   NC, .mk_spl
    LD   C, A
    LD   A, 0x80
.mk_sh:
    RLCA
    DEC  C
    JR   NZ, .mk_sh
    LD   B, A
.mk_spl:
    LD   A, (zp_mon_type)
    CALL recall_mark_spell_slot
    POP  AF

    CALL _me_exec_spell

.cast_done:
    POP  IY
    POP  IX
    RET

; ============================================================================
; +6: ovl_mon_ext_acid_armour — VMS minus_ac on worn armour (pure CF return)
; Preserves: HL, IX, IY
; Output:    CF = 1 if a worn armour piece took it (resisted or damaged), CF = 0 else
; ============================================================================
ovl_mon_ext_acid_armour:
    PUSH IX
    PUSH IY
    PUSH HL                     ; preserve caller HL (acid dam / rolled dmg)

    ; Collect worn armour slots among EQUIP_BODY..EQUIP_FEET, EQUIP_CLOAK
    LD   HL, _me_armour_slots
    LD   B, 6
    LD   C, 0                   ; count
.arm_scan:
    LD   A, (HL)
    INC  HL
    PUSH HL
    PUSH BC
    LD   E, A
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    POP  BC
    POP  HL
    CP   FI_EMPTY
    JR   Z, .arm_next
    DEC  HL
    LD   A, (HL)
    INC  HL
    PUSH HL
    LD   L, C
    LD   H, 0
    LD   DE, line_buf
    ADD  HL, DE
    LD   (HL), A
    POP  HL
    INC  C
.arm_next:
    DJNZ .arm_scan

    LD   A, C
    OR   A
    JR   Z, .acid_none          ; nothing worn -> CF=0

    CALL rng_range
    LD   E, A
    LD   D, 0
    LD   HL, line_buf
    ADD  HL, DE
    LD   C, (HL)                ; C = chosen equipped slot
    LD   B, 0

    ; VMS minus_ac: EGO_RESIST, EGO_RESIST_ACID, or EGO_MAGI takes acid unharmed
    LD   HL, inv_ego
    ADD  HL, BC
    LD   A, (HL)
    AND  EGO_ID_MASK
    CP   EGO_RESIST
    JR   Z, .arm_resist
    CP   EGO_RESIST_ACID
    JR   Z, .arm_resist
    CP   EGO_MAGI
    JR   NZ, .dmg_piece
.arm_resist:
    LD   A, C
    CALL _me_fmt_your_item
    LD   A, HSTR_MAT_RESISTS
    CALL _me_huff_append
    LD   HL, line_buf
    CALL msg_print_str
    SCF
    JR   .acid_ret

.dmg_piece:
    ; Check worn-out guard FIRST: base_ac + signed inv_to_ac[C] > 0?
    PUSH BC
    CALL _me_get_base_ac        ; A = base_ac
    POP  BC
    LD   HL, inv_to_ac
    ADD  HL, BC
    LD   E, (HL)                ; signed int8 to_ac
    LD   D, A                   ; unsigned base_ac
    LD   A, E
    RLCA
    SBC  A, A
    LD   L, E
    LD   H, A
    LD   E, D
    LD   D, 0
    ADD  HL, DE
    BIT  7, H
    JR   NZ, .acid_none
    LD   A, H
    OR   L
    JR   Z, .acid_none          ; already worn out (<= 0): no dmg, CF=0

    ; Damage worn piece, print "Your <item> is damaged!", recalc, return CF=1
    PUSH BC
    LD   A, C
    CALL _me_fmt_your_item
    LD   A, HSTR_MAT_DAMAGED
    CALL _me_huff_append
    LD   HL, line_buf
    CALL msg_print_str
    POP  BC

    LD   HL, inv_to_ac
    ADD  HL, BC
    DEC  (HL)
    CALL tramp_modal_recalc_equipment
    SCF
    JR   .acid_ret

.acid_none:
    OR   A
.acid_ret:
    POP  HL                     ; pops do not affect flags (CF preserved)
    POP  IY
    POP  IX
    RET

; ============================================================================
; Private Helpers — Attack Decoding, Hit/Dmg Math, Special Effects
; ============================================================================

; _me_load_atk_slot — Read slot A (0..3) of zp_mon_type.
; Output: B = adtype (0..24/99), C = adesc (0..19), D = dice, E = sides (0..15)
_me_load_atk_slot:
    LD   E, A
    ADD  A, E
    ADD  A, E
    ADD  A, E
    ADD  A, E
    ADD  A, E                   ; * 6
    LD   E, A
    LD   D, 0
    LD   HL, _me_atk_tbls
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    INC  HL
    PUSH HL                     ; ptr to dice_tbl ptr
    EX   DE, HL                 ; HL = type_tbl
    CALL _me_idx_mon
    LD   B, A                   ; B = raw_type
    POP  HL
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    INC  HL
    PUSH HL                     ; ptr to sides_tbl ptr
    EX   DE, HL                 ; HL = dice_tbl
    CALL _me_idx_mon
    LD   D, A                   ; D = dice
    POP  HL
    LD   E, (HL)
    INC  HL
    LD   H, (HL)
    LD   L, E
    CALL _me_idx_mon
    LD   E, A                   ; E = raw_sides

    ; Unpack adtype = B & 0x7F, adesc = ((B>>7)&1) | ((E>>3)&0x1E), sides = E & 0x0F
    LD   A, E
    RRCA
    RRCA
    RRCA
    AND  0x1E
    BIT  7, B
    JR   Z, .adesc_ok
    OR   0x01
.adesc_ok:
    LD   C, A                   ; C = adesc (0..19)
    LD   A, B
    AND  ATK_TYPE_MASK
    LD   B, A                   ; B = adtype
    LD   A, E
    AND  ATK_SIDES_MASK
    LD   E, A                   ; E = sides
    RET

_me_idx_mon:
    PUSH BC
    PUSH DE
    LD   A, (zp_mon_type)
    LD   C, A
    LD   B, 0
    ADD  HL, BC
    LD   A, (HL)
    POP  DE
    POP  BC
    RET

; _me_eff_ac — Return unsigned effective player AC (PL_AC + bless 2, sat 255).
; Clobbers: AF, C
_me_eff_ac:
    LD   A, (player_data + PL_AC)
    LD   C, A
    LD   A, (zp_eff_bless)
    OR   A
    LD   A, C
    RET  Z
    ADD  A, 2
    RET  NC
    LD   A, 255
    RET

; _me_check_hit — VMS monster hit check: clamp(atk_bth[B] + 3*cr_level, 0, 255).
; Input:  B = adtype
; Output: CF = 1 hit, CF = 0 miss
_me_check_hit:
    LD   A, B
    CP   ATK_STEAL_GOLD
    JR   Z, .steal_def
    CP   ATK_STEAL_ITEM
    JR   Z, .steal_def
    CALL _me_eff_ac
    JR   .def_ok
.steal_def:
    LD   A, (player_data + PL_LEVEL)
.def_ok:
    PUSH AF                     ; save defense byte across BTH math
    LD   E, B
    LD   D, 0
    LD   HL, _me_atk_bth
    ADD  HL, DE
    LD   A, (HL)
    LD   L, A
    RLCA
    SBC  A, A
    LD   H, A                   ; HL = signed int16 bth

    LD   A, (zp_mon_type)
    LD   E, A
    PUSH HL
    LD   HL, cr_level
    ADD  HL, DE
    LD   L, (HL)
    LD   H, 0
    LD   B, H
    LD   C, L
    ADD  HL, HL
    ADD  HL, BC                 ; 3 * cr_level
    POP  DE
    ADD  HL, DE
    BIT  7, H
    JR   Z, .pos
    LD   B, 0
    JR   .roll
.pos:
    LD   A, H
    OR   A
    JR   Z, .u8
    LD   B, 255
    JR   .roll
.u8:
    LD   B, L
.roll:
    POP  DE                     ; D = defense byte (rng_range preserves DE)
    LD   A, 20
    CALL rng_range
    OR   A
    JR   Z, .miss               ; natural 1 always misses
    CP   19
    JR   Z, .hit                ; natural 20 always hits
    LD   A, B
    CP   2
    JR   C, .miss               ; core/6502: tohit < 2 always misses
    CALL rng_range              ; 0..bth-1
    CP   D                      ; r >= def <=> (r+1) > def (unsigned)
    JR   NC, .hit
.miss:
    OR   A
    RET
.hit:
    SCF
    RET

; _me_print_verb_msg — Print attack verb msg for ADESC A (0..19)
_me_print_verb_msg:
    CP   ADESC_INSULTS + 1
    JR   C, .v_range_ok
    LD   A, ADESC_BITES
.v_range_ok:
    CP   ADESC_BITES
    JR   NC, .lookup
    LD   B, HSTR_MAT_HITS
    JP   _me_print_mon_hstr
.lookup:
    SUB  ADESC_BITES
    PUSH AF
    LD   A, (zp_mon_type)
    CALL monster_get_name_ptr
    LD   DE, line_buf
    CALL _me_fmt_the_name
    POP  AF
    PUSH DE
    ADD  A, A
    LD   E, A
    LD   D, 0
    LD   HL, _me_verb_ptrs
    ADD  HL, DE
    LD   A, (HL)
    INC  HL
    LD   H, (HL)
    LD   L, A
    POP  DE
    LD   A, ' '
    LD   (DE), A
    INC  DE
    CALL _me_append_str
    XOR  A
    LD   (DE), A
    LD   HL, line_buf
    JP   msg_print_str

; _me_dispatch_attack — Execute attack type B (1..24) with damage HL.
; Output: CF = 1 if player died or thief blinked away (stop round)
_me_dispatch_attack:
    LD   A, B
    CP   ATK_NORMAL
    JR   Z, .do_norm
    CP   ATK_LOSE_STR
    JP   Z, .lose_str
    CP   ATK_CONFUSE
    JP   Z, .atk_confuse
    CP   ATK_FEAR
    JP   Z, .atk_fear
    CP   ATK_FIRE
    JP   Z, .atk_fire
    CP   ATK_ACID
    JP   Z, .atk_acid
    CP   ATK_COLD
    JP   Z, .atk_cold
    CP   ATK_LIGHT
    JP   Z, .atk_light
    CP   ATK_CORRODE
    JP   Z, .atk_corrode
    CP   ATK_BLIND
    JP   Z, .atk_blind
    CP   ATK_PARALYZE
    JP   Z, .atk_paralyze
    CP   ATK_STEAL_GOLD
    JP   Z, .steal_gold
    CP   ATK_STEAL_ITEM
    JP   Z, .steal_item
    CP   ATK_POISON
    JP   Z, .atk_poison
    CP   ATK_LOSE_DEX
    JP   Z, .lose_dex
    CP   ATK_LOSE_CON
    JP   Z, .lose_con
    CP   ATK_LOSE_INT
    JP   Z, .lose_int
    CP   ATK_LOSE_WIS
    JP   Z, .lose_wis
    CP   ATK_LOSE_EXP
    JP   Z, .lose_exp
    CP   ATK_AGGRAVATE
    JP   Z, .aggravate
    CP   ATK_DISENCHANT
    JP   Z, .disenchant
    CP   ATK_EAT_FOOD
    JP   Z, .eat_food
    CP   ATK_EAT_LIGHT
    JP   Z, .eat_light
    CP   ATK_EAT_CHARGES
    JP   Z, .eat_charges
    OR   A
    RET

.do_norm:
    CALL _me_reduce_by_ac
    JP   _me_apply_damage

.atk_confuse:
    CALL _me_apply_damage
    RET  C
    LD   A, 2
    CALL rng_range
    OR   A
    RET  NZ                     ; 50% chance (CF=0 from OR A)
    LD   A, (zp_eff_confuse)
    OR   A
    JR   NZ, .conf_stack
    CALL _me_rng_cr_lvl
    ADD  A, 4
    LD   (zp_eff_confuse), A
    LD   B, HSTR_MAT_CONFUSE
    CALL _me_print_mon_hstr
    OR   A
    RET
.conf_stack:
    LD   A, 3
    LD   HL, zp_eff_confuse
    CALL _me_add_sat_u8
    OR   A
    RET

.atk_fear:
    CALL _me_apply_damage
    RET  C
    LD   A, (zp_eff_hero)
    OR   A
    RET  NZ
    LD   A, (player_data + PL_WIS_CUR)
    CALL player_wis_save_adj
    CALL player_saving_throw    ; CF=0 saved, CF=1 fail
    JR   C, .fear_fail
    OR   A
    RET
.fear_fail:
    LD   A, (eff_fear_timer)
    OR   A
    JR   NZ, .fear_stack
    CALL _me_rng_cr_lvl
    ADD  A, 4
    LD   (eff_fear_timer), A
    LD   B, HSTR_MAT_FEAR
    CALL _me_print_mon_hstr
    OR   A
    RET
.fear_stack:
    LD   A, 3
    LD   HL, eff_fear_timer
    CALL _me_add_sat_u8
    OR   A
    RET

.atk_fire:
    PUSH HL
    LD   B, HSTR_MAT_FIRE
    CALL _me_print_mon_hstr
    POP  HL
    LD   B, MS_BREATH_FIRE
    JR   .elem_dmg
.atk_cold:
    PUSH HL
    LD   B, HSTR_MAT_COLD
    CALL _me_print_mon_hstr
    POP  HL
    LD   B, MS_BREATH_FROST
    JR   .elem_dmg
.atk_light:
    PUSH HL
    LD   B, HSTR_MAT_LIGHT
    CALL _me_print_mon_hstr
    POP  HL
    LD   B, MS_BREATH_LIGHTNING
.elem_dmg:
    LD   A, 1
    CALL element_resist_divisor
    LD   B, A
    CALL _me_div_hl_b
    JP   _me_apply_damage

.atk_acid:
    PUSH HL
    LD   B, HSTR_MAT_ACID
    CALL _me_print_mon_hstr
    POP  HL
    CALL ovl_mon_ext_acid_armour
    LD   B, 1
    JR   NC, .acid_res
    INC  B
.acid_res:
    LD   A, (player_pflags)
    AND  PFLAG_RESIST_ACID
    JR   Z, .acid_div
    INC  B
    INC  B
.acid_div:
    CALL _me_div_hl_b
    JP   _me_apply_damage

.atk_corrode:
    PUSH HL
    LD   A, HSTR_DF_POISON_GAS
    CALL msg_print_huff
    POP  HL
    CALL ovl_mon_ext_acid_armour
    JR   C, .corr_dmg
    LD   A, 8
    CALL rng_range
    INC  A
    LD   E, A
    LD   D, 0
    ADD  HL, DE
.corr_dmg:
    JP   _me_apply_damage

.atk_blind:
    CALL _me_reduce_by_ac
    CALL _me_apply_damage
    RET  C
    LD   A, (zp_eff_blind)
    OR   A
    JR   NZ, .bl_stack
    CALL _me_rng_cr_lvl
    ADD  A, 11
    LD   (zp_eff_blind), A
    LD   B, HSTR_MM_BLIND
    CALL _me_print_mon_hstr
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    OR   A
    RET
.bl_stack:
    LD   A, 5
    LD   HL, zp_eff_blind
    CALL _me_add_sat_u8
    OR   A
    RET

.atk_paralyze:
    CALL _me_apply_damage
    RET  C
    LD   A, (zp_eff_paralyze)
    OR   A
    RET  NZ                     ; non-stacking (CF=0 from OR A)
    LD   A, (player_data + PL_CON_CUR)
    CALL player_con_hp_adj
    CALL player_saving_throw    ; CF=0 saved, CF=1 fail
    JR   C, .para_fail
    OR   A
    RET
.para_fail:
    LD   A, (player_pflags)
    AND  PFLAG_FREE_ACT
    JR   Z, .para_hit
    LD   A, HSTR_CHEST_UNAFFECTED
    CALL msg_print_huff
    OR   A
    RET
.para_hit:
    CALL _me_rng_cr_lvl
    ADD  A, 4
    LD   (zp_eff_paralyze), A
    LD   B, HSTR_MAT_PARALYZE
    CALL _me_print_mon_hstr
    OR   A
    RET

.atk_poison:
    CALL _me_apply_damage
    RET  C
    LD   A, (zp_eff_poison)
    PUSH AF                     ; save previous poisoned state
    CALL _me_rng_cr_lvl
    ADD  A, 6
    LD   HL, zp_eff_poison
    CALL _me_add_sat_u8
    POP  AF
    OR   A
    RET  NZ                     ; already poisoned -> silent extension
    LD   B, HSTR_MAT_POISON
    CALL _me_print_mon_hstr
    OR   A
    RET

.lose_str:
    LD   C, 0                   ; stat 0 = STR
    JR   .lose_stat
.lose_int:
    LD   C, 1                   ; stat 1 = INT
    JR   .lose_stat
.lose_wis:
    LD   C, 2                   ; stat 2 = WIS
    JR   .lose_stat
.lose_dex:
    LD   C, 3                   ; stat 3 = DEX
    JR   .lose_stat
.lose_con:
    LD   C, 4                   ; stat 4 = CON
.lose_stat:
    PUSH BC
    CALL _me_reduce_by_ac
    CALL _me_apply_damage
    POP  BC
    RET  C
    ; Check sustain mask FIRST (C = 0:STR, 1:INT, 2:WIS, 3:DEX, 4:CON)
    LD   A, C
    INC  A
    LD   B, A
    LD   A, 0x80
.s_lp:
    RLCA
    DJNZ .s_lp
    LD   HL, player_sust_mask
    AND  (HL)
    JR   Z, .unsust
    LD   A, HSTR_CHEST_UNAFFECTED
    CALL msg_print_huff
    OR   A
    RET
.unsust:
    ; VMS ATK_LOSE_STR has a 50% drain chance when unsustained
    LD   A, C
    OR   A
    JR   NZ, .do_drain_stat
    LD   A, 2
    CALL rng_range
    OR   A
    JR   Z, .do_drain_stat
    RET                         ; CF=0 (OR A already cleared CF)
.do_drain_stat:
    PUSH BC
    LD   A, C
    CALL player_drain_stat_a
    POP  BC
.stat_msg:
    LD   A, C
    ADD  A, A
    LD   E, A
    LD   D, 0
    LD   HL, _me_drain_msgs
    ADD  HL, DE
    LD   A, (HL)
    INC  HL
    LD   H, (HL)
    LD   L, A
    CALL msg_print_str
    OR   A
    RET

.lose_exp:
    ; VMS formula: 2 * (PL_XP / 100) + rolled_dmg (0 HP damage)
    PUSH HL                     ; save rolled dmg
    LD   HL, (player_data + PL_XP_0)
    LD   A, (player_data + PL_XP_2)
    LD   E, A
    LD   B, 100
    CALL _me_div_24_b           ; E:HL = PL_XP / 100
    ADD  HL, HL
    RL   E                      ; E:HL = 2 * (PL_XP / 100)
    POP  BC                     ; BC = rolled dmg
    ADD  HL, BC
    JR   NC, .le_no_c
    INC  E
.le_no_c:
    LD   A, (player_data + PL_XP_0)
    SUB  L
    LD   (player_data + PL_XP_0), A
    LD   A, (player_data + PL_XP_1)
    SBC  A, H
    LD   (player_data + PL_XP_1), A
    LD   A, (player_data + PL_XP_2)
    SBC  A, E
    JR   NC, .xp_d_ok
    XOR  A
    LD   (player_data + PL_XP_0), A
    LD   (player_data + PL_XP_1), A
    LD   (player_data + PL_XP_FRAC_LO), A
    LD   (player_data + PL_XP_FRAC_HI), A
.xp_d_ok:
    LD   (player_data + PL_XP_2), A
    LD   HL, _me_str_drain_exp
    CALL msg_print_str
    LD   HL, 0
    CALL tramp_modal_award_xp
    OR   A
    RET

.aggravate:
    CALL monster_aggravate_all
    OR   A
    RET

.steal_gold:
    CALL _me_thief_dodged
    JR   NC, .st_g_hit
    LD   HL, _me_str_protect_gold
    CALL msg_print_str
    JR   .st_blink
.st_g_hit:
    LD   A, (player_data + PL_GOLD_0)
    LD   L, A
    LD   A, (player_data + PL_GOLD_1)
    LD   H, A
    LD   A, (player_data + PL_GOLD_2)
    LD   E, A
    OR   H
    OR   L
    JR   NZ, .steal_gold_nz
    LD   A, 25
    CALL rng_range
    CALL status_mark_dirty
    JR   .st_g_msg
.steal_gold_nz:
    ; amt = min(gold, gold / 10 + randint(25))
    LD   B, 10
    CALL _me_div_24_b           ; E:HL = gold / 10
    LD   A, 25
    CALL rng_range
    INC  A
    LD   C, A
    LD   B, 0
    ADD  HL, BC
    JR   NC, .g_c_ok
    INC  E
.g_c_ok:
    CALL player_cmp_gold_24
    JR   C, .g_sub_go           ; CF=1 => PL_GOLD >= E:HL
    LD   HL, (player_data + PL_GOLD_0)
    LD   A, (player_data + PL_GOLD_2)
    LD   E, A
.g_sub_go:
    CALL player_sub_gold_24
    CALL status_mark_dirty
    CALL status_draw
.st_g_msg:
    LD   HL, _me_str_purse_light
    CALL msg_print_str
.st_blink:
    LD   A, 2
    CALL rng_range
    DEC  A                      ; 50%: randint(2) == 1 -> rng_range == 1
    JR   Z, .do_thief_blink
    OR   A
    RET
.do_thief_blink:
    LD   HL, _me_str_puff_smoke
    CALL msg_print_str
    LD   D, MONS_MAX_SIGHT
    CALL _me_blink_dist_d
    OR   A                      ; does not abort remaining melee slots
    RET

.steal_item:
    CALL _me_thief_dodged
    JR   NC, .st_i_hit
    LD   HL, _me_str_grab_pack
    CALL msg_print_str
    JR   .st_blink
.st_i_hit:
    ; Collect non-empty pack slots 0..MAX_INV_SLOTS-1 into line_buf
    LD   HL, inv_item_id
    LD   B, MAX_INV_SLOTS
    LD   C, 0                   ; slot index
    LD   D, 0                   ; count
.si_lp:
    LD   A, (HL)
    INC  HL
    CP   FI_EMPTY
    JR   Z, .si_nx
    PUSH HL
    LD   E, D
    LD   D, 0
    LD   HL, line_buf
    ADD  HL, DE
    LD   (HL), C
    LD   D, E
    INC  D
    POP  HL
.si_nx:
    INC  C
    DJNZ .si_lp
    LD   A, D
    OR   A
    JR   Z, .st_blink           ; MON-036: empty pack omits steal + message

    CALL rng_range
    LD   E, A
    LD   D, 0
    LD   HL, line_buf
    ADD  HL, DE
    LD   C, (HL)                ; C = stolen pack slot
    CALL _me_is_bundle_slot_c   ; CF = 1 for ICAT_SPIKE or Arrow..Iron Shot
    LD   A, C
    JR   NC, .si_one
    CALL inv_remove_item
    JR   .si_msg
.si_one:
    CALL inv_consume_one
.si_msg:
    LD   HL, _me_str_pack_light
    CALL msg_print_str
    JR   .st_blink

.disenchant:
    ; VMS creature.inc: 0 HP damage, pick in 7 worn slots, drop positive hit/dam/ac by 1..2
    LD   A, 7
    CALL rng_range              ; 0..6
    CP   6
    JR   C, .dis_slot
    LD   A, EQUIP_CLOAK - EQUIP_WEAPON
.dis_slot:
    ADD  A, EQUIP_WEAPON
    LD   C, A
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .dis_done
    XOR  A
    LD   (_me_dis_chg), A
    LD   HL, inv_to_hit
    CALL .dis_dec_field
    LD   HL, inv_to_dam
    CALL .dis_dec_field
    LD   HL, inv_to_ac
    CALL .dis_dec_field
    LD   A, (_me_dis_chg)
    OR   A
    JR   Z, .dis_done
    LD   A, HSTR_PIQ_AIR_CRACKLE
    CALL msg_print_huff
    CALL tramp_modal_recalc_equipment
.dis_done:
    OR   A
    RET

.dis_dec_field:
    ADD  HL, BC
    LD   A, (HL)
    OR   A
    RET  Z
    BIT  7, A
    RET  NZ
    LD   D, A
    LD   A, 2
    PUSH HL
    CALL rng_range
    POP  HL
    INC  A                      ; 1..2
    LD   E, A
    LD   A, D
    SUB  E
    JR   NC, .ddf_st
    XOR  A
.ddf_st:
    LD   (HL), A
    LD   A, 1
    LD   (_me_dis_chg), A
    RET

.eat_food:
    LD   D, 1
    CALL _me_pick_pack_slot     ; CF=1, C=random ICAT_FOOD slot
    JR   NC, .ef_done
    LD   A, C
    CALL inv_consume_one        ; silent in core/6502 (mae_eat_food)
.ef_done:
    OR   A
    RET

.eat_light:
    LD   A, (inv_item_id + EQUIP_LIGHT)
    CP   FI_EMPTY
    JR   Z, .el_done
    LD   A, (inv_p1 + EQUIP_LIGHT)
    OR   A
    JR   Z, .el_done
    LD   B, A
    LD   A, 9
    CALL rng_range
    ADD  A, 8                   ; 8..16 charges
    LD   C, A
    LD   A, B
    SUB  C
    JR   C, .el_flr
    JR   NZ, .el_st
.el_flr:
    LD   A, 1
.el_st:
    LD   (inv_p1 + EQUIP_LIGHT), A
    LD   A, HSTR_TTL_DIM
    CALL msg_print_huff
.el_done:
    OR   A
    RET

.eat_charges:
    LD   D, 2
    CALL _me_pick_pack_slot     ; CF=1, C=random charged wand/staff slot
    JR   NC, .ec_done
    LD   B, 0
    LD   HL, inv_p1
    ADD  HL, BC
    LD   E, (HL)                ; E = drained charges
    LD   (HL), 0
    LD   D, 0
    LD   A, (zp_mon_type)
    LD   HL, cr_level
    CALL _me_idx_mon            ; A = cr_level
    CALL mul_de_a               ; HL = cr_level * charges
    PUSH HL
    LD   A, (zp_mon_idx)
    CALL monster_get_ptr
    POP  DE
    JR   C, .ec_msg
    LD   BC, MX_HP_LO
    ADD  HL, BC
    LD   C, (HL)
    INC  HL
    LD   B, (HL)
    EX   DE, HL
    ADD  HL, BC
    BIT  7, H
    JR   Z, .ec_hp_ok
    LD   HL, 0x7FFF
.ec_hp_ok:
    EX   DE, HL                 ; DE = new HP, HL = &MX_HP_HI
    LD   (HL), D
    DEC  HL
    LD   (HL), E
.ec_msg:
    LD   A, HSTR_PIQ_VIBRATION
    CALL msg_print_huff
.ec_done:
    OR   A
    RET

; _me_pick_pack_slot — Uniform random pack slot (D=1: ICAT_FOOD; D=2: charged wand/staff).
; Output: CF=1, C=slot on match; CF=0 if none.
_me_pick_pack_slot:
    LD   E, 0                   ; count
    LD   C, 0                   ; slot
.pps_lp:
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .pps_nx
    PUSH DE
    PUSH BC
    CALL _me_set_page_slot_c
    CALL item_get_category_a
    POP  BC
    POP  DE
    BIT  1, D
    JR   NZ, .pps_m2
    CP   ICAT_FOOD
    JR   NZ, .pps_nx
    JR   .pps_add
.pps_m2:
    CP   ICAT_WAND
    JR   Z, .pps_chg
    CP   ICAT_STAFF
    JR   NZ, .pps_nx
.pps_chg:
    LD   B, 0
    LD   HL, inv_p1
    ADD  HL, BC
    LD   A, (HL)
    OR   A
    JR   Z, .pps_nx
.pps_add:
    LD   B, 0
    LD   HL, line_buf
    PUSH DE
    LD   D, 0
    ADD  HL, DE
    POP  DE
    LD   (HL), C
    INC  E
.pps_nx:
    INC  C
    LD   A, C
    CP   MAX_INV_SLOTS
    JR   C, .pps_lp
    LD   A, E
    OR   A
    RET  Z                      ; CF=0
    CALL rng_range
    LD   E, A
    LD   D, 0
    LD   HL, line_buf
    ADD  HL, DE
    LD   C, (HL)
    SCF
    RET

; ============================================================================
; Private Helpers — Monster Spells & Movement
; ============================================================================

; _me_exec_spell — Execute picked spell token A.
_me_exec_spell:
    BIT  7, A
    JR   NZ, .breath
    CP   1
    JP   Z, .wound_light
    CP   2
    JP   Z, .do_breath_bad      ; should not happen; breath uses 0x80+elem
    CP   3
    JP   Z, .summon_mon
    CP   4
    JP   Z, .tele_to
    CP   5
    JP   Z, .blind
    CP   6
    JP   Z, .confuse
    CP   7
    JP   Z, .wound_serious
    CP   8
    JP   Z, .fear
    CP   9
    JP   Z, .hold
    CP   10
    JP   Z, .blink
    CP   11
    JP   Z, .tele_self
    CP   12
    JP   Z, .summon_undead
    CP   13
    JP   Z, .slow
    CP   14
    JP   Z, .drain_mana
.do_breath_bad:
    RET

.breath:
    AND  0x07                   ; 1..5
    LD   C, A                   ; C = MS_BREATH_1..5
    PUSH BC
    ADD  A, HSTR_MM_BREATH_LIGHTNING - 1
    LD   B, A
    CALL _me_print_mon_hstr
    POP  BC

    ; Fetch caster's 16-bit HP uncapped (monster_table[zp_mon_idx])
    PUSH BC
    LD   A, (zp_mon_idx)
    CALL monster_get_ptr
    POP  BC
    RET  C
    LD   DE, MX_HP_LO
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    EX   DE, HL                 ; HL = monster HP (16-bit)

    LD   A, C
    CP   MS_BREATH_ACID
    JR   NZ, .br_not_acid
    CALL ovl_mon_ext_acid_armour
    LD   A, 1
    JR   NC, .ba_res
    INC  A
.ba_res:
    LD   C, A
    LD   A, (player_pflags)
    AND  PFLAG_RESIST_ACID
    JR   Z, .ba_x3
    INC  C
    INC  C
.ba_x3:
    LD   A, C
    ADD  A, A
    ADD  A, C                   ; 3 * (1 + armour + 2*resist) = 3, 6, 9, or 12
    LD   B, A
    CALL _me_div_hl_b
    JP   _me_apply_damage

.br_not_acid:
    ; One combined integer divide: HP / (base_div * resist_mult)
    LD   A, C
    CP   MS_BREATH_LIGHTNING    ; 1 -> base_div 4, else 3
    LD   A, 3
    JR   NZ, .br_div_ok
    INC  A
.br_div_ok:
    PUSH HL
    LD   B, C
    CALL element_resist_divisor
    POP  HL
    LD   B, A
    CALL _me_div_hl_b           ; HL = final breath damage

    LD   A, C
    CP   MS_BREATH_GAS
    JP   NZ, _me_apply_damage

    ; Gas: poison += 12 + randint(max(1, dam)) saturated at 255 (silent timer)
    PUSH HL
    LD   A, H
    OR   L
    JR   NZ, .bg_nz
    LD   HL, 1
.bg_nz:
    CALL _me_rng16_hl           ; HL = rng_range(max(1, dam)) in 0..dam-1
    LD   DE, 13
    ADD  HL, DE
    LD   A, H
    OR   A
    JR   NZ, .bg_max
    LD   A, L
    LD   HL, zp_eff_poison
    CALL _me_add_sat_u8
    JR   .bg_dmg
.bg_max:
    LD   A, 0xFF
    LD   (zp_eff_poison), A
.bg_dmg:
    POP  HL
    JP   _me_apply_damage

.wound_light:
    LD   B, HSTR_MM_CAST
    CALL _me_print_mon_hstr
    CALL _me_spell_save
    JR   NC, .resisted
    LD   B, 3
    LD   C, 8
    CALL roll_dice_bc
    JP   _me_apply_damage

.wound_serious:
    LD   B, HSTR_MM_CAST
    CALL _me_print_mon_hstr
    CALL _me_spell_save
    JR   NC, .resisted
    LD   B, 8
    LD   C, 8
    CALL roll_dice_bc
    JP   _me_apply_damage

.cast_resisted:
    LD   B, HSTR_MM_CAST
    CALL _me_print_mon_hstr
.resisted:
    LD   A, HSTR_MM_RESIST
    JP   msg_print_huff

.unaffected_cast:
    LD   B, HSTR_MM_CAST
    CALL _me_print_mon_hstr
    LD   A, HSTR_CHEST_UNAFFECTED
    JP   msg_print_huff

.blind:
    CALL _me_spell_save
    JR   NC, .cast_resisted
    LD   B, HSTR_MM_BLIND
    CALL _me_print_mon_hstr
    LD   HL, zp_eff_blind
    LD   A, (HL)
    OR   A
    JR   NZ, .s_bl_st
    LD   A, 3
    CALL rng_range
    ADD  A, 13                  ; 12 + randint(3) = 13..15
    LD   (HL), A
    JR   .s_bl_drt
.s_bl_st:
    LD   A, 6
    CALL _me_add_sat_u8
.s_bl_drt:
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    RET

.confuse:
    CALL _me_spell_save
    JR   NC, .cast_resisted
    LD   B, HSTR_MM_CONFUSE
    CALL _me_print_mon_hstr
    LD   HL, zp_eff_confuse
.eff_3_5_2:
    LD   A, (HL)
    OR   A
    JR   NZ, .eff_step2
    LD   A, 5
    CALL rng_range
    ADD  A, 4                   ; 3 + randint(5) = 4..8
    LD   (HL), A
    RET
.eff_step2:
    LD   A, 2
    JP   _me_add_sat_u8

.fear:
    LD   A, (zp_eff_hero)
    OR   A
    JR   NZ, .cast_resisted
    CALL _me_spell_save
    JR   NC, .cast_resisted
    LD   B, HSTR_MAT_FEAR
    CALL _me_print_mon_hstr
    LD   HL, eff_fear_timer
    JR   .eff_3_5_2

.hold:
    LD   A, (player_pflags)
    AND  PFLAG_FREE_ACT
    JR   NZ, .unaffected_cast
    CALL _me_spell_save
    JR   NC, .cast_resisted
    LD   B, HSTR_MAT_PARALYZE
    CALL _me_print_mon_hstr
    LD   HL, zp_eff_paralyze
    LD   A, (HL)
    OR   A
    JR   NZ, .eff_step2
    LD   A, 5
    CALL rng_range
    ADD  A, 5                   ; 4 + randint(5) = 5..9
    LD   (HL), A
    RET

.tele_to:
    LD   B, HSTR_MM_CAST
    CALL _me_print_mon_hstr
    LD   A, (zp_mon_y)
    LD   B, A
    LD   A, (zp_mon_x)
    LD   C, A
    CALL find_adjacent_empty_tile ; CF=1, B=ny, C=nx
    RET  NC
    LD   A, C
    LD   (abi_player_x), A
    LD   (player_data + PL_MAP_X), A
    LD   A, B
    LD   (abi_player_y), A
    LD   (player_data + PL_MAP_Y), A
    CALL player_search_mode_off
    LD   HL, zp_disturb
    INC  (HL)
    CALL los_update_visibility
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    RET

.summon_mon:
    LD   B, HSTR_MM_SUMMON
    CALL _me_print_mon_hstr
    LD   A, (zp_mon_count)
    CP   MAX_MONSTERS
    RET  NC
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    CALL find_adjacent_empty_tile ; MON-041: beside player
    RET  NC
    PUSH BC
    CALL pick_summon_creature_type ; MON-040 (clobbers BC)
    POP  BC
    CALL monster_spawn_awake
    RET  NC
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

.summon_undead:
    LD   B, HSTR_MM_SUMMON
    CALL _me_print_mon_hstr
    LD   A, (zp_mon_count)
    CP   MAX_MONSTERS
    RET  NC
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    CALL find_adjacent_empty_tile
    RET  NC
    PUSH BC
    CALL pick_undead_creature_type ; MON-041 (clobbers BC)
    POP  BC
    CALL monster_spawn_awake
    RET  NC
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

.blink:
    LD   D, 10
    JP   _me_blink_dist_d

.tele_self:
    LD   D, 60
    JP   _me_blink_dist_d

.slow:
    LD   A, (player_pflags)
    AND  PFLAG_FREE_ACT
    JP   NZ, .unaffected_cast
    LD   B, HSTR_MM_CAST
    CALL _me_print_mon_hstr
    CALL _me_spell_save
    JP   NC, .resisted
    LD   A, (zp_eff_speed)
    BIT  7, A
    JR   NZ, .slow_ext
    LD   A, 5
    CALL rng_range
    ADD  A, 4                   ; randint(5) + 3 = 4..8
    JR   .slow_sub
.slow_ext:
    LD   A, 2
.slow_sub:
    LD   C, A
    LD   A, (zp_eff_speed)
    SUB  C
    JP   PE, .slow_clamp
    JR   .slw_st
.slow_clamp:
    LD   A, 0x80                ; clamp at -128
.slw_st:
    LD   (zp_eff_speed), A
    LD   A, HSTR_EFF_HASTE_END
    JP   msg_print_huff

.drain_mana:
    LD   A, (player_data + PL_MANA)
    OR   A
    RET  Z
    LD   D, A                   ; current mana
    LD   A, (zp_mon_type)
    LD   HL, cr_level
    CALL _me_idx_mon            ; A = cr_level
    OR   A
    JR   Z, .dm_r0
    CALL rng_range              ; 0..lev-1
.dm_r0:
    SRL  A
    ADC  A, 1                   ; floor((r + 1)/2) + 1
    CP   D
    JR   C, .dm_ok
    LD   A, D
.dm_ok:
    LD   B, A                   ; B = drained
    LD   A, D
    SUB  B
    LD   (player_data + PL_MANA), A
    LD   (abi_player_mp), A
    ; Heal caster 6 * r1, clamped to 0x7FFF
    LD   L, B
    LD   H, 0
    ADD  HL, HL
    LD   D, H
    LD   E, L
    ADD  HL, HL
    ADD  HL, DE                 ; 6 * B
    PUSH HL
    LD   A, (zp_mon_idx)
    CALL monster_get_ptr
    POP  DE
    JR   C, .dm_msg
    LD   BC, MX_HP_LO
    ADD  HL, BC
    LD   C, (HL)
    INC  HL
    LD   B, (HL)
    EX   DE, HL
    ADD  HL, BC
    BIT  7, H
    JR   Z, .dm_hp_ok
    LD   HL, 0x7FFF
.dm_hp_ok:
    EX   DE, HL
    LD   (HL), D
    DEC  HL
    LD   (HL), E
.dm_msg:
    LD   A, (zp_mon_type)
    CALL monster_get_name_ptr
    LD   DE, line_buf
    CALL _me_fmt_the_name
    LD   HL, _me_str_drains_mana
    CALL _me_append_str
    XOR  A
    LD   (DE), A
    LD   HL, line_buf
    CALL msg_print_str
    JP   status_mark_dirty

_me_rng16_hl:
    ; Return uniform HL in [0 .. input_HL - 1] (input >= 1).
    LD   D, H
    LD   E, L
    DEC  HL
    LD   A, 16
.mk_lp:
    BIT  7, H
    JR   NZ, .mk_fill
    ADD  HL, HL
    DEC  A
    JR   NZ, .mk_lp
    LD   HL, 0
    RET
.mk_fill:
    LD   HL, 0
.f_lp:
    SCF
    RL   L
    RL   H
    DEC  A
    JR   NZ, .f_lp
    LD   B, H
    LD   C, L                   ; BC = mask
.samp:
    CALL rng_next_u16           ; preserves BC, DE
    LD   A, H
    AND  B
    LD   H, A
    LD   A, L
    AND  C
    LD   L, A
    PUSH HL
    OR   A
    SBC  HL, DE
    POP  HL
    JR   NC, .samp
    RET

_me_spell_save:
    LD   A, (player_data + PL_WIS_CUR)
    CALL player_wis_save_adj
    LD   HL, abi_player_lvl
    ADD  A, (HL)
    JP   player_saving_throw

; ============================================================================
; Common Shared Utilities
; ============================================================================

; _me_move_caster_to_bc — Relocate monster zp_mon_idx from (zp_mon_y,x) to (B,C),
;                         clearing MF_VISIBLE and updating zp_mon_x/y/flags & map.
_me_move_caster_to_bc:
    PUSH BC
    ; Clear FLAG_OCCUPIED at old tile
    LD   A, (zp_mon_y)
    LD   B, A
    LD   A, (zp_mon_x)
    LD   C, A
    CALL map_get_tile
    JR   C, .set_new
    AND  ~FLAG_OCCUPIED
    CALL map_set_tile
.set_new:
    POP  BC                     ; B=ny, C=nx
    PUSH BC
    CALL map_get_tile
    JR   C, .pop_fail
    OR   FLAG_OCCUPIED
    CALL map_set_tile
    POP  BC
    LD   A, C
    LD   (zp_mon_x), A
    LD   A, B
    LD   (zp_mon_y), A
    LD   A, (zp_mon_flags)
    BIT  3, A                   ; MON-038: disturb if caster was visible before blink/tele
    JR   Z, .clr_vis
    LD   HL, zp_disturb
    INC  (HL)
.clr_vis:
    AND  ~MF_VISIBLE
    LD   (zp_mon_flags), A

    LD   A, (zp_mon_idx)
    CALL monster_get_ptr
    JR   C, .dirty
    LD   (HL), C                ; MX_X
    INC  HL
    LD   (HL), B                ; MX_Y
    LD   DE, MX_FLAGS - MX_Y
    ADD  HL, DE
    LD   A, (zp_mon_flags)
    LD   (HL), A
.dirty:
    LD   HL, zp_dirty_count
    INC  (HL)
    RET
.pop_fail:
    POP  BC
    RET

; _me_blink_dist_d — Blink monster within +-D (widening +5 per 10 failed tries)
_me_blink_dist_d:
    LD   E, 0                   ; ctr = 0
.lp:
    PUSH DE
    LD   A, D
    ADD  A, A
    INC  A                      ; 2*dis + 1
    CALL rng_range
    SUB  D
    LD   HL, zp_mon_x
    JR   C, .neg_x
    ADD  A, (HL)
    JR   C, .fail
    JR   .x_ok
.neg_x:
    NEG
    LD   B, A
    LD   A, (HL)
    SUB  B
    JR   C, .fail
.x_ok:
    LD   C, A
    OR   A
    JR   Z, .fail
    CP   MAP_COLS - 1
    JR   NC, .fail

    LD   A, D
    ADD  A, A
    INC  A
    CALL rng_range
    SUB  D
    LD   HL, zp_mon_y
    JR   C, .neg_y
    ADD  A, (HL)
    JR   C, .fail
    JR   .y_ok
.neg_y:
    NEG
    LD   B, A
    LD   A, (HL)
    SUB  B
    JR   C, .fail
.y_ok:
    LD   B, A
    OR   A
    JR   Z, .fail
    CP   MAP_ROWS - 1
    JR   NC, .fail

    LD   A, (abi_player_x)
    CP   C
    JR   NZ, .chk_t
    LD   A, (abi_player_y)
    CP   B
    JR   Z, .fail
.chk_t:
    CALL map_get_tile
    JR   C, .fail
    AND  (TILE_TYPE_MASK | FLAG_OCCUPIED)
    JR   NZ, .fail
    POP  DE
    JP   _me_move_caster_to_bc
.fail:
    POP  DE
    INC  E
    LD   A, E
    CP   10
    JR   C, .lp
    LD   E, 0
    LD   A, D
    ADD  A, 5
    CP   100
    JR   NC, .fallback
    LD   D, A
    JR   .lp
.fallback:
    LD   HL, (abi_player_x)
    PUSH HL
    LD   HL, (zp_mon_x)
    LD   (abi_player_x), HL
    LD   A, MONS_MAX_SIGHT
    CALL find_random_floor
    POP  HL
    LD   (abi_player_x), HL
    RET  NC
    LD   A, C
    CP   L
    JR   NZ, .fb_go
    LD   A, B
    CP   H
    RET  Z                      ; never blink onto player square
.fb_go:
    JP   _me_move_caster_to_bc

_me_thief_dodged:
    LD   A, (zp_eff_paralyze)
    OR   A
    JR   NZ, .fail
    LD   A, 124
    CALL rng_range              ; 0..123
    INC  A                      ; randint(124) in 1..124
    LD   HL, player_data + PL_DEX_CUR
    CP   (HL)                   ; CF=1 iff randint(124) < PL_DEX_CUR
    RET
.fail:
    OR   A
    RET

_me_reduce_by_ac:
    ; VMS: dam -= (dam * eff_ac) / 200
    CALL _me_eff_ac
    OR   A
    RET  Z
    PUSH HL                     ; save dam
    LD   B, H
    LD   C, L
    CALL _me_mul_bc_a           ; E:HL = dam * eff_ac
    LD   B, 200
    CALL _me_div_24_b           ; E:HL = red
    EX   DE, HL                 ; DE = red
    POP  HL
    OR   A
    SBC  HL, DE
    RET  NC
    LD   HL, 0
    RET

; _me_apply_damage — Apply HL HP damage to player, record fatal monster cause & recall death.
; Output: CF = 1 if player died
_me_apply_damage:
    LD   A, (eff_invuln_timer)
    OR   A
    RET  NZ                     ; CF=0 (cleared by OR A): invulnerable to monster melee/spells
    LD   A, H
    OR   L
    RET  Z                      ; 0 dmg -> CF=0
    LD   A, (zp_mon_type)
    INC  A                      ; 1..40 (< DEATH_CUSTOM_FIRST)
    CALL turn_apply_one_damage
    RET  NC

    ; Fatal blow: record monster name into death_cause_buf & increment recall deaths
    LD   A, (zp_mon_type)
    CALL recall_inc_deaths_slot
    LD   A, (zp_mon_type)
    CALL monster_get_name_ptr
    LD   DE, death_cause_buf
    LD   B, 31
.cp:
    LD   A, (HL)
    OR   A
    JR   Z, .cp_end
    LD   (DE), A
    INC  HL
    INC  DE
    DJNZ .cp
.cp_end:
    XOR  A
    LD   (DE), A
    SCF
    RET

_me_print_mon_hstr:
    PUSH BC
    LD   A, (zp_mon_type)
    CALL monster_get_name_ptr
    LD   DE, line_buf
    CALL _me_fmt_the_name
    POP  AF                     ; B -> A
    CALL _me_huff_append
    LD   HL, line_buf
    JP   msg_print_str

_me_huff_append:
    CALL huff_decode_string     ; preserves DE, B = length
    LD   A, B
    ADD  A, E
    LD   E, A
    RET  NC
    INC  D
    RET

_me_fmt_the_name:
    PUSH HL
    LD   HL, _me_str_the
    CALL _me_append_str
    POP  HL
_me_append_str:
    LD   A, (HL)
    OR   A
    RET  Z
    LD   (DE), A
    INC  HL
    INC  DE
    JR   _me_append_str

_me_rng_cr_lvl:
    LD   A, (zp_mon_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_level
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    RET  Z
    JP   rng_range

_me_add_sat_u8:
    ADD  A, (HL)
    JR   NC, .ok
    LD   A, 0xFF
.ok:
    LD   (HL), A
    RET

_me_div_hl_b:
    ; HL = HL / B (B >= 1)
    LD   A, B
    CP   2
    RET  C
    LD   E, 0
    CALL _me_div_24_b
    RET

_me_mul_bc_a:
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

_me_div_24_b:
    LD   D, 24
    XOR  A
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
    RET

_me_set_page_slot_c:
    LD   B, 0
    LD   HL, inv_ego
    ADD  HL, BC
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    RET

_me_is_bundle_slot_c:
    PUSH BC
    CALL _me_set_page_slot_c
    CALL item_get_category_a
    POP  BC
    CP   ICAT_SPIKE
    JR   Z, .yes
    LD   A, (item_cur_page)
    AND  ITEM_PAGE_BIT
    JR   NZ, .no
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   ITEM_SLOT_ARROW
    JR   C, .no
    CP   ITEM_SLOT_IRON_SHOT + 1
    JR   C, .yes
.no:
    OR   A
    RET
.yes:
    SCF
    RET

_me_get_base_ac:
    CALL _me_set_page_slot_c
    JP   item_get_base_ac_a

_me_fmt_your_item:
    PUSH AF
    LD   DE, line_buf
    LD   A, HSTR_MAT_YOUR
    CALL huff_decode_string
.find_tilde:
    LD   A, (DE)
    OR   A
    JR   Z, .at_pos
    CP   '~'
    JR   Z, .at_pos
    INC  DE
    JR   .find_tilde
.at_pos:
    POP  AF
    JP   item_format_inv_slot

; ============================================================================
; Local Data & Tables
; ============================================================================
_me_armour_slots:
    DB   EQUIP_BODY, EQUIP_SHIELD, EQUIP_HEAD, EQUIP_HANDS, EQUIP_FEET, EQUIP_CLOAK

_me_atk_tbls:
    DW   cr_atk0_type, cr_atk0_dice, cr_atk0_sides
    DW   cr_atk1_type, cr_atk1_dice, cr_atk1_sides
    DW   cr_atk2_type, cr_atk2_dice, cr_atk2_sides
    DW   cr_atk3_type, cr_atk3_dice, cr_atk3_sides

_me_atk_bth:
    ; Signed base BTH for ATK_0..ATK_24 (core/6502/monster_attack.s:15-40)
    DB   0
    DB   60, 0xFD, 10, 10, 10, 0, 10, 10, 0, 2
    DB   2, 5, 2, 5, 0, 0, 2, 0, 5, 0
    DB   20, 5, 5, 15

_me_verb_ptrs:
    DW   _me_v2, _me_v3, _me_v4, _me_v5, _me_v6, _me_v7, _me_v8, _me_v9
    DW   _me_v10, _me_v11, _me_v12, _me_v13, _me_v14, _me_v15, _me_v16, _me_v17, _me_v18, _me_v19

_me_v2:  DB "bites you.", 0
_me_v3:  DB "claws you.", 0
_me_v4:  DB "stings you.", 0
_me_v5:  DB "touches you.", 0
_me_v6:  DB "kicks you.", 0
_me_v7:  DB "gazes at you.", 0
_me_v8:  DB "breathes on you.", 0
_me_v9:  DB "spits on you.", 0
_me_v10: DB "makes a horrible wail.", 0
_me_v11: DB "embraces you.", 0
_me_v12: DB "crawls on you.", 0
_me_v13: DB "releases a cloud of spores.", 0
_me_v14: DB "begs you for money.", 0
_me_v15: DB "slimes you.", 0
_me_v16: DB "crushes you.", 0
_me_v17: DB "tramples you.", 0
_me_v18: DB "drools on you.", 0
_me_v19: DB "insults you.", 0

_me_drain_msgs:
    DW   _me_str_drain_str, _me_str_drain_int, _me_str_drain_wis, _me_str_drain_dex, _me_str_drain_con

_me_str_the:          DB "The ", 0
_me_str_drains_mana:  DB " drains mana!", 0
_me_str_drain_str:    DB "You feel weaker.", 0
_me_str_drain_dex:    DB "You feel more clumsy.", 0
_me_str_drain_con:    DB "Your health is damaged!", 0
_me_str_drain_int:    DB "You feel your memories fading...", 0
_me_str_drain_wis:    DB "Your wisdom is drained.", 0
_me_str_drain_exp:    DB "You feel your life draining away!", 0
_me_str_protect_gold: DB "You quickly protect your money pouch!", 0
_me_str_purse_light:  DB "Your purse feels lighter.", 0
_me_str_grab_pack:    DB "You grab hold of your backpack!", 0
_me_str_pack_light:   DB "Your backpack feels lighter.", 0
_me_str_puff_smoke:   DB "There is a puff of smoke!", 0

_me_dis_chg:          DB 0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_mon_ext.ovl", ovl_start, ovl_end - ovl_start
