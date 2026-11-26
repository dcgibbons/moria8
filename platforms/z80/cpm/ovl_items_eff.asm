; ovl_items_eff.asm — Moria8 CP/M Scroll/Wand/Staff Effects, Level Spawn,
; Identify, Teleport & Summon Overlay.
; (OVL_ITEMS_EFF = 15, DAT slot 20)
;
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0:  JP ovl_items_eff_scroll      (eff_arg0=id, eff_arg1=page)
;   +3:  JP ovl_items_eff_wand        (eff_arg0=slot, eff_arg1=id, eff_arg2=dir)
;   +6:  JP ovl_items_eff_staff       (eff_arg0=slot, eff_arg1=id)
;   +9:  JP ovl_items_eff_spawn_level ()
;   +12: JP ovl_items_eff_identify    () -> CF=1 identified, CF=0 cancel
;   +15: JP ovl_items_eff_teleport    (A=range: 10 phase door, 0 full random)
;   +18: JP ovl_items_eff_summon_many (A=count, B=0 summon / 1 undead)
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
    JP   ovl_items_eff_scroll       ; +0
    JP   ovl_items_eff_wand         ; +3
    JP   ovl_items_eff_staff        ; +6
    JP   ovl_items_eff_spawn_level  ; +9
    JP   ovl_items_eff_identify     ; +12
    JP   ovl_items_eff_teleport     ; +15
    JP   ovl_items_eff_summon_many  ; +18

; ============================================================================
; Public Entry Wrappers (preserve IX and IY)
; ============================================================================

ovl_items_eff_scroll:
    PUSH IX
    PUSH IY
    CALL _ie_scroll
    JR   _ie_ret_ixiy

ovl_items_eff_wand:
    PUSH IX
    PUSH IY
    CALL _ie_wand
    JR   _ie_ret_ixiy

ovl_items_eff_staff:
    PUSH IX
    PUSH IY
    CALL _ie_staff
    JR   _ie_ret_ixiy

ovl_items_eff_spawn_level:
    PUSH IX
    PUSH IY
    CALL _ie_spawn_level
    JR   _ie_ret_ixiy

ovl_items_eff_identify:
    PUSH IX
    PUSH IY
    CALL _ie_identify
    JR   _ie_ret_ixiy

ovl_items_eff_teleport:
    PUSH IX
    PUSH IY
    CALL _ie_teleport
    JR   _ie_ret_ixiy

ovl_items_eff_summon_many:
    PUSH IX
    PUSH IY
    CALL _ie_summon_many
_ie_ret_ixiy:
    POP  IY
    POP  IX
    RET

; ============================================================================
; +0: _ie_scroll — All 42 VMS Scrolls (Slots 95..136)
; ============================================================================
_ie_scroll:
    LD   A, (eff_arg1)
    AND  ITEM_PAGE_BIT
    RET  NZ
    LD   A, (eff_arg0)
    SUB  ITEM_SLOT_SCROLL_OF_ENCHANT_WEAPON_TO_HIT
    RET  C
    CP   42
    RET  NC
    LD   HL, _ie_scroll_tbl
    JP   _ie_dispatch_hl_a

_ie_scroll_tbl:
    DW _s_ench_wpn_hit              ; 95  ENCHANT_WEAPON_TO_HIT
    DW _s_ench_wpn_dam              ; 96  ENCHANT_WEAPON_TO_DAM
    DW _s_ench_armor                ; 97  ENCHANT_ARMOR
    DW _ie_identify                 ; 98  IDENTIFY
    DW _s_remove_curse              ; 99  REMOVE_CURSE
    DW _s_light                     ; 100 LIGHT
    DW _s_summon                    ; 101 SUMMON_MONSTER
    DW _s_phase_door                ; 102 PHASE_DOOR
    DW _s_teleport                  ; 103 TELEPORTATION
    DW _s_tele_level                ; 104 TELEPORT_LEVEL
    DW _s_mon_conf                  ; 105 MONSTER_CONFUSION
    DW _s_magic_map                 ; 106 MAGIC_MAPPING
    DW _s_sleep_adj                 ; 107 SLEEP_MONSTER
    DW _s_glyph                     ; 108 RUNE_OF_PROTECTION
    DW _s_det_treas                 ; 109 TREASURE_DETECTION
    DW _s_det_objs                  ; 110 OBJECT_DETECTION
    DW _s_det_traps                 ; 111 TRAP_DETECTION_L5
    DW _s_det_traps                 ; 112 TRAP_DETECTION_L12
    DW _s_det_doors                 ; 113 DOOR_STAIR_LOCATION_L5
    DW _s_det_doors                 ; 114 DOOR_STAIR_LOCATION_L15
    DW _s_mass_geno                 ; 115 MASS_GENOCIDE
    DW _s_det_invis                 ; 116 DETECT_INVISIBLE
    DW _s_aggravate                 ; 117 AGGRAVATE
    DW _s_trap_create               ; 118 TRAP_CREATION
    DW _s_dest_traps                ; 119 TRAP_DOOR_DESTRUCTION
    DW _s_door_create               ; 120 DOOR_CREATION
    DW _s_recharging                ; 121 RECHARGING
    DW _s_genocide                  ; 122 GENOCIDE
    DW _s_darkness                  ; 123 DARKNESS
    DW _s_prot_evil                 ; 124 PROTECT_FROM_EVIL
    DW _s_create_food               ; 125 CREATE_FOOD
    DW _s_dispel_undead             ; 126 DISPEL_UNDEAD
    DW _s_star_ench_wpn             ; 127 *ENCHANT WEAPON*
    DW _s_curse_wpn                 ; 128 CURSE_WEAPON
    DW _s_star_ench_arm             ; 129 *ENCHANT ARMOR*
    DW _s_curse_arm                 ; 130 CURSE_ARMOR
    DW _s_summon_und                ; 131 SUMMON_UNDEAD
    DW _s_blessing                  ; 132 BLESSING
    DW _s_holy_chant                ; 133 HOLY_CHANT
    DW _s_holy_prayer               ; 134 HOLY_PRAYER
    DW _s_word_recall               ; 135 WORD_OF_RECALL
    DW _s_destruction               ; 136 *DESTRUCTION*

; --- Scroll Handlers ---
_s_ench_wpn_hit:
    LD   HL, inv_to_hit + EQUIP_WEAPON
    JR   _s_ench_wpn_1
_s_ench_wpn_dam:
    LD   HL, inv_to_dam + EQUIP_WEAPON
_s_ench_wpn_1:
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   EMPTY_SLOT
    JR   Z, _s_no_gear
    LD   A, (HL)
    CALL _ie_vms_ench_ok
    JR   NC, _s_wpn_glow
    INC  (HL)
    JR   _s_wpn_glow
_s_star_ench_wpn:
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   EMPTY_SLOT
    JR   Z, _s_no_gear
    LD   HL, inv_flags + EQUIP_WEAPON
    RES  0, (HL)                    ; lift IF_CURSED
    LD   A, 2
    CALL rng_range
    INC  A
    LD   B, A                       ; 1..2 attempts
.sew_lp:
    PUSH BC
    LD   HL, inv_to_hit + EQUIP_WEAPON
    LD   A, (HL)
    CALL _ie_vms_ench_ok
    JR   NC, .sew_d
    INC  (HL)
.sew_d:
    LD   HL, inv_to_dam + EQUIP_WEAPON
    LD   A, (HL)
    CALL _ie_vms_ench_ok
    JR   NC, .sew_nx
    INC  (HL)
.sew_nx:
    POP  BC
    DJNZ .sew_lp
_s_wpn_glow:
    LD   HL, inv_flags + EQUIP_WEAPON
    RES  0, (HL)                    ; lift IF_CURSED
    CALL tramp_modal_recalc_equipment
    LD   A, HSTR_PIQ_WPN_GLOW
    JP   msg_print_huff
_s_no_gear:
    LD   A, HSTR_PIQ_VIBRATION
    JP   msg_print_huff
_s_ench_fail:
    LD   A, HSTR_PIQ_ENCH_FAIL
    JP   msg_print_huff

_s_ench_armor:
    CALL _ie_pick_cursed_or_rand_armour
    JR   NC, _s_no_gear
    LD   E, A
    LD   D, 0
    LD   HL, inv_to_ac
    ADD  HL, DE
    LD   A, (HL)
    CALL _ie_vms_arm_ench_ok        ; VMS 1000-roll table
    JR   NC, _s_ench_fail
    INC  (HL)
    JR   _s_arm_glow
_s_star_ench_arm:
    CALL _ie_pick_cursed_or_rand_armour
    JR   NC, _s_no_gear
    LD   E, A
    LD   D, 0
    LD   HL, inv_flags
    ADD  HL, DE
    RES  0, (HL)
    LD   A, 2
    CALL rng_range
    INC  A
    LD   B, A                       ; 1..2 attempts
    LD   HL, inv_to_ac
    ADD  HL, DE
.sea_lp:
    PUSH BC
    PUSH HL
    LD   A, (HL)
    CALL _ie_vms_ench_ok
    POP  HL
    JR   NC, .sea_nx
    INC  (HL)
.sea_nx:
    POP  BC
    DJNZ .sea_lp
_s_arm_glow:
    LD   HL, inv_flags
    ADD  HL, DE
    RES  0, (HL)
    CALL tramp_modal_recalc_equipment
    LD   A, HSTR_PIQ_ARM_GLOW
    JP   msg_print_huff

_s_remove_curse:
    LD   B, EQUIP_WEAPON
    LD   HL, inv_flags + EQUIP_WEAPON
.rc_lp:
    RES  0, (HL)
    INC  HL
    INC  B
    LD   A, B
    CP   VISIBLE_EQUIP_END
    JR   C, .rc_lp
    CALL tramp_modal_recalc_equipment
    LD   A, HSTR_PIQ_CLEANSED
    JP   msg_print_huff

_s_curse_wpn:
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   EMPTY_SLOT
    JR   Z, _s_no_gear
    LD   E, EQUIP_WEAPON
    LD   D, 0
    CALL _ie_curse_slot_de
    LD   A, 5
    CALL rng_range
    INC  A
    NEG
    LD   (inv_to_hit + EQUIP_WEAPON), A
    LD   A, 5
    CALL rng_range
    INC  A
    NEG
    LD   (inv_to_dam + EQUIP_WEAPON), A
    CALL tramp_modal_recalc_equipment
    LD   A, HSTR_PIQ_HUMMING
    JP   msg_print_huff

_s_curse_arm:
    CALL _ie_pick_worn_armour
    JP   NC, _s_no_gear
    LD   E, A
    LD   D, 0
    CALL _ie_curse_slot_de
    LD   A, 5
    CALL rng_range
    INC  A
    NEG
    LD   HL, inv_to_ac
    ADD  HL, DE
    LD   (HL), A
    CALL tramp_modal_recalc_equipment
    LD   A, HSTR_PIQ_HUMMING
    JP   msg_print_huff

_s_light:        LD A, 22 : JP tramp_spell_eff_area
_s_magic_map:    JP _ie_magic_map
_s_sleep_adj:    JP _ie_sleep_adj
_s_glyph:        LD A, 24 : JP tramp_spell_eff_area
_s_det_treas:    LD A, 18 : JP tramp_spell_eff_area
_s_det_objs:     JP _ie_det_objs
_s_det_traps:    JP _ie_det_traps
_s_det_doors:    JP _ie_det_doors
_s_mass_geno:    LD A, 15 : JP tramp_spell_eff_area
_s_dest_traps:   JP _ie_dest_traps
_s_genocide:     LD A, 14 : JP tramp_spell_eff_area
_s_destruction:  LD A, 12 : JP tramp_spell_eff_area
_s_dispel_undead:
    LD   A, 60
    LD   (eff_arg0), A
    LD   A, 2
    JP   tramp_spell_eff_area

_s_summon:
    LD   A, 3
    CALL rng_range
    INC  A
    LD   B, 0
    CALL _ie_summon_many
    LD   A, HSTR_PIQ_AIR_CRACKLE
    JP   msg_print_huff
_s_summon_und:
    LD   A, 3
    CALL rng_range
    INC  A
    LD   B, 1
    CALL _ie_summon_many
    LD   A, HSTR_PIQ_AIR_CRACKLE
    JP   msg_print_huff

_s_phase_door:
    LD   A, 10
    JR   _s_tp_msg
_s_teleport:
    XOR  A
_s_tp_msg:
    CALL _ie_teleport
    LD   A, HSTR_PIQ_TELEPORT
    CALL msg_print_huff
    SCF
    RET

_s_tele_level:
    LD   A, 2
    CALL rng_range                  ; 0 or 1
    ADD  A, A                       ; 0 or 2
    LD   B, A
    LD   A, (abi_player_dlvl)
    LD   C, A                       ; C = old_dlvl
    ADD  A, B                       ; old_dlvl + 0 or +2
    DEC  A                          ; old_dlvl - 1 or +1
    JR   Z, .tl_floor               ; 0 (from dlvl 1) -> 1
    BIT  7, A
    JR   Z, .tl_chk_max             ; positive (1..127)
.tl_floor:
    LD   A, 1                       ; 0 or 0xFF (from Town dlvl 0) -> 1
.tl_chk_max:
    CP   100
    JR   C, .tl_dir
    LD   A, 99
.tl_dir:
    LD   B, 1                       ; 1 = ascended (or clamped 1->1 / 99->99)
    CP   C
    JR   C, .tl_store               ; shallower
    JR   Z, .tl_same                ; clamped same level (1->1 or 99->99)
    LD   B, 0                       ; 0 = descended
    LD   HL, player_data + PL_MAX_DLVL
    CP   (HL)
    JR   C, .tl_store
    LD   (HL), A
.tl_store:
    LD   (abi_player_dlvl), A
    LD   (player_data + PL_DLEVEL), A
.tl_dir_ret:
    LD   A, B
    LD   (level_entry_dir), A
    RET                             ; game_loop detects dlvl change & calls _gl_handle_dlvl_change ONCE
.tl_same:
    LD   A, 1
    LD   (level_force_regen), A
    JR   .tl_dir_ret

_s_mon_conf:
    LD   A, 1
    LD   (zp_confuse_melee), A
    LD   A, HSTR_PIQ_HANDS_GLOW
    JP   msg_print_huff

_s_det_invis:
    LD   HL, zp_eff_see_inv
    LD   A, 24
    LD   B, 25
    CALL _ie_add_timer
    CALL monster_update_visibility_all
    LD   A, HSTR_PIQ_EYES_TINGLE
    JP   msg_print_huff

_s_aggravate:
    CALL monster_aggravate_all
    LD   A, HSTR_PIQ_HUMMING
    JP   msg_print_huff

_s_trap_create:
    ; Scan 8 neighbors + player center, add hidden traps to trap_x/y/type table
    LD   D, 0                       ; dir index 0..8 (8 = center)
.tc_lp:
    LD   A, (trap_count)
    CP   MAX_TRAPS
    JR   NC, .tc_done
    LD   A, D
    CP   9
    JR   NC, .tc_done
    PUSH DE
    CALL _ie_neighbor_bc_d
    JR   C, .tc_next
    CALL map_get_tile
    JR   C, .tc_next
    AND  TILE_TYPE_MASK | FLAG_OCCUPIED | FLAG_HAS_ITEM
    JR   NZ, .tc_next
    CALL _ie_trap_at_bc
    JR   C, .tc_next
    LD   A, TRAP_TYPE_COUNT
    CALL rng_range
    PUSH AF
    LD   A, (trap_count)
    LD   L, A
    LD   H, 0
    PUSH HL
    LD   DE, trap_x
    ADD  HL, DE
    LD   (HL), C
    POP  HL
    PUSH HL
    LD   DE, trap_y
    ADD  HL, DE
    LD   (HL), B
    POP  HL
    LD   DE, trap_type
    ADD  HL, DE
    POP  AF
    LD   (HL), A
    LD   HL, trap_count
    INC  (HL)
.tc_next:
    POP  DE
    INC  D
    JR   .tc_lp
.tc_done:
    LD   A, HSTR_PIQ_AIR_CRACKLE
    JP   msg_print_huff

_s_door_create:
    LD   D, 0                       ; 0..7 adjacent only
.dc_lp:
    LD   A, D
    CP   8
    JR   NC, .dc_done
    PUSH DE
    CALL _ie_neighbor_bc_d
    JR   C, .dc_nx
    CALL map_get_tile
    JR   C, .dc_nx
    AND  TILE_TYPE_MASK | FLAG_OCCUPIED
    JR   NZ, .dc_nx
    PUSH BC
    CALL floor_item_find_at
    POP  BC
    JR   C, .dc_nx
    CALL _ie_trap_at_bc
    JR   C, .dc_nx
    CALL map_get_tile
    OR   TILE_DOOR_CLOSED | FLAG_VISITED
    CALL map_set_tile
.dc_nx:
    POP  DE
    INC  D
    JR   .dc_lp
.dc_done:
    CALL los_update_visibility
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

_s_recharging:
    LD   A, PIW_FILTER_RECHARGE
    LD   B, 0
    LD   HL, 0x5600
    CALL tramp_item_mgt_select_inv
    RET  NC
    LD   E, A
    LD   D, 0                       ; DE = slot
    LD   HL, inv_p1
    ADD  HL, DE
    LD   C, (HL)                    ; C = cur charges
    ; threshold = (50 >> 3) + 2 = 8
    LD   A, C
    CP   8
    JR   C, .add_chg
.chk_blow:
    PUSH DE
    LD   A, 4
    CALL rng_range
    POP  DE
    OR   A
    JR   NZ, .add_chg
    LD   A, E
    CALL inv_remove_item
    CALL status_mark_dirty
    LD   HL, _ie_s_blow
    JP   msg_print_str
.add_chg:
    ; p1 += 2 + rng_range(50/8 + 1 = 7)
    LD   A, 7
    CALL rng_range
    ADD  A, 2
    LD   HL, inv_p1
    ADD  HL, DE
    ADD  A, (HL)
    JR   NC, .c_ok
    LD   A, 0xFF
.c_ok:
    LD   (HL), A
    CALL _ie_stage_inv_de
    XOR  A
    LD   (itemdesc_flags), A
    LD   HL, _ie_s_the_cap
    LD   DE, line_buf
    CALL _ie_strcpy
    CALL item_format_staged
    LD   HL, _ie_s_glow_br
    CALL _ie_strcpy
    LD   HL, line_buf
    JP   msg_print_str

_s_darkness:
    ; Clear room light if in a room, otherwise 3x3 (-1..+1) around player; keep FLAG_VISITED
    LD   A, (room_count)
    OR   A
    JR   Z, .dk_corr
    LD   B, A
    LD   E, 0
.dk_rm:
    LD   D, 0
    LD   HL, room_x
    ADD  HL, DE
    LD   A, (HL)
    DEC  A
    LD   C, A                       ; min_x = rx - 1
    LD   HL, abi_player_x
    CP   (HL)
    JR   Z, .dk_x0
    JR   NC, .dk_rnext
.dk_x0:
    LD   HL, room_w
    ADD  HL, DE
    LD   A, C
    INC  A
    ADD  A, (HL)                    ; max_x = rx + rw
    LD   HL, abi_player_x
    CP   (HL)
    JR   C, .dk_rnext
    LD   H, A                       ; H = max_x
    LD   HL, room_y
    ADD  HL, DE
    LD   A, (HL)
    DEC  A                          ; min_y = ry - 1
    LD   L, A
    LD   A, (abi_player_y)
    CP   L
    JR   C, .dk_rnext
    PUSH HL
    LD   HL, room_h
    ADD  HL, DE
    LD   A, (HL)
    POP  HL
    ADD  A, L
    INC  A                          ; max_y = ry + rh
    LD   HL, abi_player_y
    CP   (HL)
    JR   C, .dk_rnext
    ; In room E! Clear room_lit[E] and unlight room bounds
    LD   HL, room_lit
    ADD  HL, DE
    LD   (HL), 0
    LD   HL, room_x
    ADD  HL, DE
    LD   C, (HL)
    DEC  C
    LD   HL, room_w
    ADD  HL, DE
    LD   A, C
    INC  A
    ADD  A, (HL)
    LD   L, A                       ; L = max_x
    PUSH HL
    LD   HL, room_y
    ADD  HL, DE
    LD   B, (HL)
    DEC  B                          ; B = min_y
    LD   HL, room_h
    ADD  HL, DE
    LD   A, B
    INC  A
    ADD  A, (HL)
    LD   H, A                       ; H = max_y
    POP  DE                         ; E = max_x
    LD   D, C                       ; D = min_x
    JR   .dk_box
.dk_rnext:
    INC  E
    DJNZ .dk_rm
.dk_corr:
    LD   A, (abi_player_x)
    DEC  A
    JR   NZ, .dx0
    INC  A
.dx0:
    LD   D, A
    LD   A, (abi_player_x)
    INC  A
    CP   MAP_COLS - 1
    JR   C, .dx1
    LD   A, MAP_COLS - 2
.dx1:
    LD   E, A
    LD   A, (abi_player_y)
    DEC  A
    JR   NZ, .dy0
    INC  A
.dy0:
    LD   B, A
    LD   A, (abi_player_y)
    INC  A
    CP   MAP_ROWS - 1
    JR   C, .dy1
    LD   A, MAP_ROWS - 2
.dy1:
    LD   H, A
.dk_box:
    ; Loop B = min_y..H, C = D..E clearing FLAG_LIT
    LD   C, D
.dk_col:
    PUSH BC
    PUSH DE
    PUSH HL
    CALL map_get_tile
    JR   C, .dsk
    AND  (~FLAG_LIT) & 0xFF
    CALL map_set_tile
.dsk:
    POP  HL
    POP  DE
    POP  BC
    LD   A, C
    CP   E
    JR   Z, .dk_row_done
    INC  C
    JR   .dk_col
.dk_row_done:
    LD   A, B
    CP   H
    JR   Z, .dk_done
    INC  B
    JR   .dk_box
.dk_done:
    CALL _ie_mark_vis_dirty
    LD   A, (zp_eff_blind)
    OR   A
    RET  NZ
    LD   A, 5
    CALL rng_range
    ADD  A, 2
    LD   (zp_eff_blind), A
    LD   A, HSTR_PIQ_CANT_SEE
    JP   msg_print_huff

_s_prot_evil:
    LD   A, (player_data + PL_LEVEL)
    LD   B, A
    ADD  A, A
    ADD  A, B                       ; 3 * level
    LD   B, A
    INC  B                          ; + 1 (sec; adc)
    LD   HL, zp_eff_protect
    LD   A, 25
    CALL _ie_add_timer
    LD   A, HSTR_PIQ_PROTECTED
    JP   msg_print_huff

_s_create_food:
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    PUSH BC
    CALL floor_item_find_at
    CALL C, floor_item_remove
    POP  BC
    XOR  A
    LD   HL, fi_add_p1
    LD   D, 6
.zfood:
    LD   (HL), A
    INC  HL
    DEC  D
    JR   NZ, .zfood
    LD   A, ITEM_SLOT_RATION_OF_FOOD
    LD   (fi_add_id), A
    LD   A, 1
    LD   (fi_add_qty), A
    LD   A, C
    LD   (fi_add_x), A
    LD   A, B
    LD   (fi_add_y), A
    CALL floor_item_add
    RET  NC
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   A, HSTR_PMU_CREATE_FOOD
    JP   msg_print_huff

_s_blessing:
    LD   A, 6  : LD B, 7  : JR _s_add_bless
_s_holy_chant:
    LD   A, 12 : LD B, 13
_s_add_bless:
    LD   HL, zp_eff_bless
    CALL _ie_add_timer
    CALL tramp_modal_recalc_equipment
    LD   A, HSTR_PIQ_HEROIC
    JP   msg_print_huff
_s_holy_prayer:
    LD   HL, zp_eff_bless
    LD   A, 24
    LD   B, 25
    CALL _ie_add_timer
    XOR  A
    LD   (eff_fear_timer), A
    LD   BC, 0x0404
    CALL roll_dice_bc
    CALL eff_heal
    LD   A, 7                       ; EFF_CURE_ALL
    CALL _ie_cure_timers
    CALL tramp_modal_recalc_equipment
    LD   A, HSTR_PIQ_VERY_GOOD
    JP   msg_print_huff

_s_word_recall:
    LD   A, 15
    CALL rng_range
    ADD  A, 15
    LD   (zp_eff_word_recall), A
    LD   A, HSTR_PIQ_AIR_CRACKLE
    JP   msg_print_huff

; ============================================================================
; +3: _ie_wand — All 24 VMS Wands (Slots 137..160)
; ============================================================================
_ie_wand:
    LD   A, (eff_arg1)
    SUB  ITEM_SLOT_WAND_OF_LIGHT
    RET  C
    CP   24
    RET  NC
    ; Note proj_dir already set from eff_arg2 (or 0xFF if caller omitted dir)
_ie_wand_idx:
    LD   HL, _ie_wand_tbl
    JP   _ie_dispatch_hl_a

_ie_wand_tbl:
    DW _w_light                     ; 137 LIGHT
    DW _w_lightning                 ; 138 LIGHTNING
    DW _w_frost                     ; 139 FROST
    DW _w_fire_bolts                ; 140 FIRE_BOLTS (MON-031 6d8)
    DW _w_stone_mud                 ; 141 STONE_TO_MUD
    DW _w_poly                      ; 142 POLYMORPH
    DW _w_heal_mon                  ; 143 HEAL_MONSTER
    DW _w_haste_mon                 ; 144 HASTE_MONSTER
    DW _w_slow_mon                  ; 145 SLOW_MONSTER
    DW _w_confuse_mon               ; 146 CONFUSE_MONSTER
    DW _w_sleep_mon                 ; 147 SLEEP_MONSTER
    DW _w_drain_life                ; 148 DRAIN_LIFE (50 living-only)
    DW _w_dest_traps                ; 149 TRAP_DOOR_DESTRUCTION
    DW _w_magic_msl                 ; 150 MAGIC_MISSILE
    DW _w_wall_build                ; 151 WALL_BUILDING
    DW _w_clone_mon                 ; 152 CLONE_MONSTER (awake)
    DW _w_tele_away                 ; 153 TELEPORT_AWAY
    DW _w_disarm                    ; 154 DISARMING
    DW _w_lit_ball                  ; 155 LIGHTNING_BALLS
    DW _w_cold_ball                 ; 156 COLD_BALLS
    DW _w_fire_ball                 ; 157 FIRE_BALLS
    DW _w_stink_cloud               ; 158 STINKING_CLOUD
    DW _w_acid_ball                 ; 159 ACID_BALLS
    DW _w_wonder                    ; 160 WONDER

_w_magic_msl:   LD BC, (2 << 8) | 6  : LD D, ELEM_NONE      : JR _ie_bolt
_w_lightning:
    LD   BC, (3 << 8) | 8
    LD   D, ELEM_LIGHTNING
    CALL _ie_bolt
    LD   A, HSTR_PIW_WAND_BOLT
    JP   msg_print_huff
_w_frost:
    LD   BC, (4 << 8) | 8
    LD   D, ELEM_FROST
    CALL _ie_bolt
    LD   A, HSTR_PIW_WAND_FROST
    JP   msg_print_huff
_w_fire_bolts:  LD BC, (6 << 8) | 8  : LD D, ELEM_FIRE      : JR _ie_bolt
_ie_bolt:
    LD   A, B
    LD   (eff_arg0), A
    LD   A, C
    LD   (eff_arg1), A
    LD   A, D
    LD   (eff_arg2), A
    XOR  A
    LD   (eff_arg3), A              ; bonus = 0 for wands (range is fixed 20 in bolt_core)
    JP   tramp_spell_eff_bolt

_w_stink_cloud:
    CALL _ie_trace_mon
    JR   NC, .sc_miss
    CALL monster_get_ptr
    LD   DE, MX_CONFUSE
    ADD  HL, DE
    LD   (HL), 10
    LD   A, HSTR_PIW_WAND_CLOUD
    JP   msg_print_huff
.sc_miss:
    LD   A, HSTR_PIW_WAND_MISS
    JP   msg_print_huff

_w_lit_ball:    LD A, 24 : LD E, ELEM_LIGHTNING : JR _ie_ball
_w_cold_ball:   LD A, 33 : LD E, ELEM_FROST     : JR _ie_ball
_w_fire_ball:   LD A, 49 : LD E, ELEM_FIRE      : JR _ie_ball
_w_acid_ball:   LD A, 40 : LD E, ELEM_ACID
_ie_ball:
    LD   (eff_arg0), A
    LD   A, E
    LD   (eff_arg1), A
    XOR  A
    LD   (ball_harm), A
    JP   tramp_spell_eff_ball

_w_stone_mud:   LD A, 23 : JP tramp_spell_eff_area
_w_poly:        XOR A    : JP tramp_spell_eff_poly
_w_slow_mon:    LD A, 8  : JP tramp_spell_eff_area
_w_sleep_mon:
    CALL _ie_trace_mon
    RET  NC
    LD   C, A                       ; C = monster slot
    CALL monster_get_ptr
    LD   DE, MX_TYPE
    ADD  HL, DE
    LD   E, (HL)
    LD   D, 0
    LD   HL, cr_cdefense
    ADD  HL, DE
    BIT  6, (HL)                    ; CD_NO_SLEEP
    RET  NZ
    LD   A, 20
    CALL rng_range
    ADD  A, 10
    LD   B, A
    LD   A, C
    CALL monster_apply_sleep
    LD   HL, zp_dirty_count
    INC  (HL)
    RET
_w_dest_traps:  JP _ie_wand_dest_traps
_w_tele_away:   LD A, 10 : JP tramp_spell_eff_area

_w_confuse_mon:
    CALL _ie_trace_mon
    RET  NC
    CALL monster_get_ptr
    PUSH HL
    LD   DE, MX_TYPE
    ADD  HL, DE
    LD   C, (HL)
    LD   B, 0
    LD   HL, cr_cdefense
    ADD  HL, BC
    BIT  6, (HL)                    ; CD_NO_SLEEP
    POP  HL
    JR   Z, .do_cm
    LD   A, HSTR_PIQ_NOTHING
    JP   msg_print_huff
.do_cm:
    PUSH HL
    LD   DE, MX_FLAGS
    ADD  HL, DE
    SET  1, (HL)                    ; MF_CONFUSED
    POP  HL
    LD   DE, MX_CONFUSE
    ADD  HL, DE
    LD   A, 10
    CALL rng_range
    ADD  A, 10
    LD   (HL), A
    LD   A, HSTR_PIW_WAND_CLOUD
    JP   msg_print_huff

_w_light:
    LD   A, 22
    JP   tramp_spell_eff_area

_w_heal_mon:
    CALL _ie_trace_mon
    RET  NC
    CALL monster_get_ptr
    LD   DE, MX_HP_LO
    ADD  HL, DE
    LD   B, 4
    LD   C, 6
    PUSH HL
    CALL roll_dice_bc               ; HL = 4d6
    EX   DE, HL
    POP  HL
    LD   A, (HL)
    ADD  A, E
    LD   (HL), A
    INC  HL
    LD   A, (HL)
    ADC  A, D
    BIT  7, A
    JR   Z, .hm_ok
    LD   A, 0x7F
.hm_ok:
    LD   (HL), A
    RET

_w_haste_mon:
    CALL _ie_trace_mon
    RET  NC
_ie_haste_slot_a:
    CALL monster_get_ptr
    LD   DE, MX_SPEED_CNT
    ADD  HL, DE
    LD   A, (HL)
    CP   2
    RET  Z                          ; cap at +2 (signed)
    INC  (HL)
    RET

_w_drain_life:
    CALL _ie_trace_mon
    RET  NC
    LD   E, A
    CALL monster_get_ptr
    LD   BC, MX_TYPE
    ADD  HL, BC
    LD   C, (HL)
    LD   B, 0
    LD   HL, cr_mflags
    ADD  HL, BC
    BIT  1, (HL)                    ; CF_UNDEAD -> immune!
    RET  NZ
    LD   D, 50
    LD   A, E
    JP   _ie_dmg_mon_a_d

_w_wall_build:
    ; Beam along proj_dir building TILE_WALL_H | FLAG_VISITED, skipping items, stopping at monster/wall
    LD   A, (abi_player_x)
    LD   (proj_x), A
    LD   A, (abi_player_y)
    LD   (proj_y), A
    LD   B, 20
.wb_lp:
    PUSH BC
    CALL _ie_step_ray
    JR   C, .wb_pop
    LD   A, (proj_y)
    LD   B, A
    LD   A, (proj_x)
    LD   C, A
    CALL map_get_tile
    JR   C, .wb_pop
    CALL tile_is_walkable_a
    JR   NC, .wb_pop
    PUSH BC
    CALL monster_find_at
    POP  BC
    JR   C, .wb_pop
    PUSH BC
    CALL floor_item_find_at
    POP  BC
    JR   C, .wb_next                ; skip squares holding items
    CALL _ie_remove_trap_bc
    CALL map_get_tile
    AND  TILE_FLAG_MASK
    OR   TILE_WALL_H | FLAG_VISITED
    CALL map_set_tile
.wb_next:
    POP  BC
    DJNZ .wb_lp
    JR   .wb_done
.wb_pop:
    POP  BC
.wb_done:
    CALL los_update_visibility
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

_w_clone_mon:
    CALL _ie_trace_mon
    RET  NC
    CALL monster_get_ptr
    LD   DE, MX_TYPE
    ADD  HL, DE
    LD   A, (HL)
    LD   C, A
    LD   B, 0
    PUSH HL
    LD   HL, cr_level
    ADD  HL, BC
    LD   A, (HL)
    POP  HL
    CP   100                        ; win creatures never clone
    RET  NC
    LD   A, C
    PUSH AF                         ; save cr_type
    DEC  HL                         ; MX_Y
    LD   B, (HL)
    DEC  HL                         ; MX_X
    LD   C, (HL)
    CALL find_adjacent_empty_tile
    JR   NC, .no_sp
    POP  AF
    CALL monster_spawn_awake        ; MON-041 clone awake
    LD   HL, zp_dirty_count
    INC  (HL)
    RET
.no_sp:
    POP  AF
    RET

_w_disarm:
    ; Scan ray clearing TILE_TRAP & chest locks/traps along path
    LD   B, 20
    LD   A, (abi_player_x)
    LD   (proj_x), A
    LD   A, (abi_player_y)
    LD   (proj_y), A
.dl_lp:
    PUSH BC
    CALL _ie_step_ray
    JR   C, .dl_pop_ret
    CALL map_get_tile
    JR   C, .dl_pop_ret
    LD   D, A
    CALL tile_is_walkable_a
    JR   NC, .dl_pop_ret
    PUSH DE
    CALL _ie_remove_trap_bc
    POP  DE
    LD   A, D
    AND  TILE_TYPE_MASK
    CP   TILE_TRAP
    JR   NZ, .chk_chest
    LD   A, D
    AND  TILE_FLAG_MASK
    OR   FLAG_VISITED
    CALL map_set_tile
.chk_chest:
    CALL floor_item_find_at
    JR   NC, .dl_next
    LD   E, A
    LD   D, 0
    LD   HL, fi_meta_hi
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    JR   NZ, .dl_next               ; all chests live on page 0
    LD   (item_cur_page), A         ; A = 0
    LD   HL, fi_item_id
    ADD  HL, DE
    LD   A, (HL)
    CALL item_get_category_a
    CP   ICAT_CHEST
    JR   NZ, .dl_next
    CALL _ie_chest_disarm_slot_de
.dl_next:
    POP  BC
    DJNZ .dl_lp
    JR   .dl_vis
.dl_pop_ret:
    POP  BC
.dl_vis:
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

; Remove trap entry matching (B=y, C=x) from trap_x/trap_y/trap_type. Preserves B, C.
_ie_remove_trap_bc:
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

_w_wonder:
    LD   A, 13
    CALL rng_range
    CP   10
    JR   NC, .bolt
    LD   E, A
    LD   D, 0
    LD   HL, _ie_wonder_slots
    ADD  HL, DE
    LD   A, (HL)
    SUB  ITEM_SLOT_WAND_OF_LIGHT
    JP   _ie_wand_idx
.bolt:
    SUB  10
    LD   E, A
    LD   D, 0
    LD   HL, _ie_wonder_dice
    ADD  HL, DE
    LD   B, (HL)
    LD   C, 8
    LD   HL, _ie_wonder_elems
    ADD  HL, DE
    LD   D, (HL)
    JP   _ie_bolt

_ie_wonder_slots:
    DB ITEM_SLOT_WAND_OF_HEAL_MONSTER, ITEM_SLOT_WAND_OF_HASTE_MONSTER
    DB ITEM_SLOT_WAND_OF_CLONE_MONSTER, ITEM_SLOT_WAND_OF_MAGIC_MISSILE
    DB ITEM_SLOT_WAND_OF_CONFUSE_MONSTER, ITEM_SLOT_WAND_OF_SLEEP_MONSTER
    DB ITEM_SLOT_WAND_OF_TRAP_DOOR_DESTRUCTION, ITEM_SLOT_WAND_OF_POLYMORPH
    DB ITEM_SLOT_WAND_OF_DISARMING, ITEM_SLOT_WAND_OF_WALL_BUILDING
_ie_wonder_dice:
    DB 3, 4, 6
_ie_wonder_elems:
    DB ELEM_LIGHTNING, ELEM_FROST, ELEM_FIRE

; ============================================================================
; +6: _ie_staff — All 25 VMS Staves (Slots 161..185)
; ============================================================================
_ie_staff:
    LD   A, (eff_arg1)
    SUB  ITEM_SLOT_STAFF_OF_LIGHT
    RET  C
    CP   25
    RET  NC
    LD   HL, _ie_staff_tbl
    JP   _ie_dispatch_hl_a

_ie_staff_tbl:
    DW _s_light                     ; 161 LIGHT
    DW _s_det_doors                 ; 162 DOOR_STAIR_LOCATION
    DW _s_det_traps                 ; 163 TRAP_LOCATION
    DW _s_det_treas                 ; 164 TREASURE_LOCATION
    DW _st_det_objs                 ; 165 OBJECT_LOCATION
    DW _s_teleport                  ; 166 TELEPORTATION
    DW _st_quake                    ; 167 EARTHQUAKES
    DW _st_summon                   ; 168 SUMMONING_L10
    DW _st_summon                   ; 169 SUMMONING_L50
    DW _s_destruction               ; 170 DESTRUCTION
    DW _st_starlite                 ; 171 STARLITE
    DW _st_haste_mon                ; 172 HASTE_MONSTERS
    DW _st_slow_mon                 ; 173 SLOW_MONSTERS
    DW _st_sleep_all                ; 174 SLEEP_MONSTERS
    DW _st_cure_light               ; 175 CURE_LIGHT_WOUNDS
    DW _s_det_invis                 ; 176 DETECT_INVISIBLE
    DW _st_speed                    ; 177 SPEED
    DW _st_slowness                 ; 178 SLOWNESS
    DW _st_mass_poly                ; 179 MASS_POLYMORPH
    DW _s_remove_curse              ; 180 REMOVE_CURSE
    DW _st_det_evil                 ; 181 DETECT_EVIL
    DW _st_curing                   ; 182 CURING
    DW _st_dispel_evil              ; 183 DISPEL_EVIL
    DW _s_darkness                  ; 184 DARKNESS_L50
    DW _s_darkness                  ; 185 DARKNESS_L5

_st_quake:      LD A, 13 : JP tramp_spell_eff_area
_st_sleep_all:  JP _ie_sleep_all
_st_det_evil:   JP _ie_st_det_evil
_st_det_objs:   LD A, 19 : JP tramp_spell_eff_area
_st_mass_poly:  LD A, 1  : JP tramp_spell_eff_poly
_st_dispel_evil:
    LD   A, (abi_player_lvl)
    LD   B, A
    ADD  A, B
    JR   NC, .de2
    LD   A, 255
    JR   .de3
.de2:
    ADD  A, B
    JR   NC, .de3
    LD   A, 255
.de3:
    LD   (eff_arg0), A
    LD   A, 1
    CALL tramp_spell_eff_area
    LD   A, (bss_scratch + 7)
    OR   A
    RET  NZ
    LD   A, HSTR_PIQ_NOTHING
    JP   msg_print_huff

_st_summon:
    LD   A, 4
    CALL rng_range
    INC  A
    LD   B, 0
    CALL _ie_summon_many            ; 1d4 awake MON-040/041
    LD   A, HSTR_PIQ_AIR_CRACKLE
    JP   msg_print_huff

_st_starlite:
    LD   A, 22
    JP   tramp_spell_eff_area

_st_haste_mon:
    LD   B, 0
.lp:
    LD   A, B
    CALL monster_get_ptr
    LD   DE, MX_TYPE
    ADD  HL, DE
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .nx
    LD   DE, MX_FLAGS - MX_TYPE
    ADD  HL, DE
    BIT  3, (HL)                    ; MF_VISIBLE only
    JR   Z, .nx
    LD   A, B
    CALL _ie_haste_slot_a
.nx:
    INC  B
    LD   A, B
    CP   MAX_MONSTERS
    JR   C, .lp
    RET

_st_slow_mon:
    LD   B, 0
.lp:
    LD   A, B
    CALL monster_get_ptr
    LD   DE, MX_TYPE
    ADD  HL, DE
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .nx
    LD   DE, MX_FLAGS - MX_TYPE
    ADD  HL, DE
    BIT  3, (HL)                    ; MF_VISIBLE only
    JR   Z, .nx
    LD   DE, MX_SPEED_CNT - MX_FLAGS
    ADD  HL, DE
    LD   A, (HL)
    CP   -2 & 0xFF
    JR   Z, .nx                     ; cap at -2 (signed)
    DEC  (HL)
.nx:
    INC  B
    LD   A, B
    CP   MAX_MONSTERS
    JR   C, .lp
    RET

_st_cure_light:
    LD   BC, 0x0108
    CALL roll_dice_bc
    INC  A                          ; 1d8 + 1
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
    JR   C, .cl_msg
    CP   15
    LD   B, HSTR_EFF_POISON_END
    JR   C, .cl_msg
    CP   35
    LD   B, HSTR_PIQ_MUCH_BETTER
    JR   C, .cl_msg
    LD   B, HSTR_PIQ_VERY_GOOD
.cl_msg:
    LD   A, B
    JP   msg_print_huff

_st_speed:
    LD   A, 30
    CALL rng_range
    ADD  A, 16
    LD   E, A
    LD   A, (zp_eff_speed)
    ADD  A, E
    JP   PO, .ok
    LD   A, 127
.ok:
    LD   (zp_eff_speed), A
    LD   A, HSTR_PIQ_SPEED
    JP   msg_print_huff

_st_slowness:
    LD   A, 16
    CALL rng_range
    ADD  A, 15
    LD   E, A
    LD   D, 0
    LD   A, (zp_eff_speed)
    LD   L, A
    ADD  A, A
    SBC  A, A
    LD   H, A
    OR   A
    SBC  HL, DE
    BIT  7, H
    JR   Z, .sl_ok
    LD   A, H
    CP   0xFF
    JR   NZ, .sl_min
    LD   A, L
    CP   0x80
    JR   NC, .sl_ok
.sl_min:
    LD   L, 0x80                    ; clamp -128
.sl_ok:
    LD   A, L
    LD   (zp_eff_speed), A
    LD   A, HSTR_PIQ_DIZZY
    JP   msg_print_huff

_st_curing:
    LD   A, 7
    CALL _ie_cure_timers
    LD   A, HSTR_PIQ_MIND_CLEAR
    JP   msg_print_huff

; ============================================================================
; +9: _ie_spawn_level — Populate Dungeon Floor Gold, Items & Chests
; ============================================================================
_ie_spawn_level:
    LD   A, (abi_player_dlvl)
    OR   A
    RET  Z                          ; town spawns no dungeon loot

    ; 1. Gold piles: min(16, 2 + rng(3) + dlvl / 2)
    LD   B, A                       ; B = dlvl
    LD   A, 3
    CALL rng_range
    ADD  A, 2
    SRL  B
    ADD  A, B
    CP   17
    JR   C, .gcnt_ok
    LD   A, 16
.gcnt_ok:
    LD   B, A
.gold_lp:
    PUSH BC
    XOR  A
    LD   HL, fi_add_p1
    LD   D, 6
.zg:
    LD   (HL), A
    INC  HL
    DEC  D
    JR   NZ, .zg
    ; Gold ID = rng(2) -> 0..1 (matching 6502 item_spawn_cold.s)
    LD   A, ITEM_SLOT_GOLD_LARGE + 1
    CALL rng_range
    LD   (fi_add_id), A
    ; Value = rng_u16(dlvl * 10) + 5
    LD   A, (abi_player_dlvl)
    LD   E, A
    LD   D, 0
    LD   A, 10
    CALL mul_de_a                   ; HL = dlvl * 10 (<= 990)
    CALL _ie_rng_u16
    LD   DE, 5
    ADD  HL, DE
    LD   A, L
    LD   (fi_add_qty), A
    LD   A, H
    LD   (fi_add_qty_hi), A
    XOR  A
    CALL find_random_floor
    JR   NC, .gnext
    LD   A, C
    LD   (fi_add_x), A
    LD   A, B
    LD   (fi_add_y), A
    CALL floor_item_add
.gnext:
    POP  BC
    DJNZ .gold_lp

    ; 2. Objects & chests: min(8, 1 + rng(2) + dlvl / 3)
    LD   A, (abi_player_dlvl)
    LD   L, A
    LD   H, 0
    LD   C, 3
    CALL div_hl_c                   ; L = dlvl / 3
    LD   A, 2
    CALL rng_range
    INC  A
    ADD  A, L
    CP   9
    JR   C, .ocnt_ok
    LD   A, 8
.ocnt_ok:
    LD   B, A
.obj_lp:
    PUSH BC
    CALL _ie_pick_dungeon_item
    CALL tramp_item_mgt_roll_enchant
    ; Ammo stack = 7d6 (7..42, matching 6502 item_spawn_cold.s)
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (fi_add_id)
    CALL icat_select_id
    JR   C, .place_obj
    CALL icat_get_level_missile
    BIT  7, B
    JR   Z, .place_obj
    LD   B, 7
    LD   C, 6
    CALL roll_dice_bc
    LD   A, L
    LD   (fi_add_qty), A
.place_obj:
    XOR  A
    CALL find_random_floor
    JR   NC, .onext
    LD   A, C
    LD   (fi_add_x), A
    LD   A, B
    LD   (fi_add_y), A
    CALL floor_item_add
.onext:
    POP  BC
    DJNZ .obj_lp

    ; 3. Phase 3: Treasure Room / Vault / Nest Gold (dlvl >= 3)
    LD   A, (abi_player_dlvl)
    CP   3
    JR   C, .spawn_done

    LD   A, RT_VAULT
    CALL _ie_find_special_room
    JR   NC, .chk_nest
    ; Vault: room E, dlvl + 8, 4..8 items
    LD   D, E                       ; D = room idx
    LD   A, (abi_player_dlvl)
    ADD  A, 8
    LD   E, A                       ; E = boosted dlvl
    LD   A, 5
    CALL rng_range
    ADD  A, 4
    LD   B, A
    JR   .treasure_lp

.chk_nest:
    CALL _ie_spawn_nest_gold
    LD   A, (room_count)
    OR   A
    JR   Z, .spawn_done
    CALL rng_range
    LD   D, A                       ; D = random room idx
    LD   A, (abi_player_dlvl)
    ADD  A, 5
    LD   E, A                       ; E = dlvl + 5
    LD   A, 3
    CALL rng_range
    ADD  A, 2
    LD   B, A

.treasure_lp:
    ; B = count, D = room_idx, E = treasure_dlvl
    PUSH BC
    PUSH DE
    LD   A, D
    CALL _ie_random_floor_in_room   ; CF=1 if TILE_FLOOR: B=y, C=x
    JR   NC, .t_next
    LD   A, C
    LD   (fi_add_x), A
    LD   A, B
    LD   (fi_add_y), A
    POP  DE
    PUSH DE
    LD   A, (abi_player_dlvl)
    PUSH AF
    LD   A, E
    LD   (abi_player_dlvl), A
    CALL _ie_pick_dungeon_item
    CALL tramp_item_mgt_roll_enchant
    POP  AF
    LD   (abi_player_dlvl), A
    LD   A, 1
    LD   (fi_add_qty), A
    CALL floor_item_add
.t_next:
    POP  DE
    POP  BC
    DJNZ .treasure_lp

.spawn_done:
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

; _ie_rng_u16 — Uniform [0, HL-1] from HL (returns 0 if HL <= 1). Clobbers: AF, BC, DE
_ie_rng_u16:
    LD   A, H
    OR   L
    RET  Z
    EX   DE, HL                     ; DE = N
.rej:
    CALL rng_next_u16
    LD   A, H
    AND  0x03                       ; 10-bit mask (< 1024; covers max 990)
    LD   H, A
    OR   A
    SBC  HL, DE
    JR   NC, .rej
    ADD  HL, DE
    RET

; _ie_find_special_room — A = RT_*. Output: CF=1, E = room_idx; CF=0 none
_ie_find_special_room:
    LD   B, A
    LD   A, (room_count)
    OR   A
    RET  Z
    LD   C, A
    LD   E, 0
    LD   HL, room_type
.lp:
    LD   A, (HL)
    CP   B
    JR   Z, .hit
    INC  HL
    INC  E
    DEC  C
    JR   NZ, .lp
    OR   A
    RET
.hit:
    SCF
    RET

; _ie_random_floor_in_room — A = room_idx. Output: CF=1 if TILE_FLOOR: B=y, C=x
_ie_random_floor_in_room:
    LD   E, A
    LD   D, 0
    PUSH DE
    LD   HL, room_w
    ADD  HL, DE
    LD   A, (HL)
    CALL rng_range
    POP  DE
    PUSH DE
    LD   HL, room_x
    ADD  HL, DE
    ADD  A, (HL)
    LD   C, A                       ; C = x
    POP  DE
    PUSH DE
    PUSH BC
    LD   HL, room_h
    ADD  HL, DE
    LD   A, (HL)
    CALL rng_range
    POP  BC
    POP  DE
    LD   HL, room_y
    ADD  HL, DE
    ADD  A, (HL)
    LD   B, A                       ; B = y
    PUSH BC
    CALL map_get_tile
    POP  BC
    AND  TILE_TYPE_MASK
    CP   TILE_FLOOR
    JR   Z, .ok
    OR   A
    RET
.ok:
    SCF
    RET

; _ie_spawn_nest_gold — Spawn 2..4 gold piles in RT_NEST (ID=0, qty=rng(min(255,dlvl*10))+5)
_ie_spawn_nest_gold:
    LD   A, RT_NEST
    CALL _ie_find_special_room
    RET  NC
    LD   D, E                       ; D = nest room idx
    LD   A, 3
    CALL rng_range
    ADD  A, 2
    LD   B, A
.lp:
    PUSH BC
    PUSH DE
    XOR  A
    LD   HL, fi_add_p1
    LD   C, 6
.z:
    LD   (HL), A
    INC  HL
    DEC  C
    JR   NZ, .z
    POP  DE
    PUSH DE
    LD   A, D
    CALL _ie_random_floor_in_room   ; even if non-floor? Wait: 6502 places on random_floor_in_room
    JR   NC, .next
    LD   A, C
    LD   (fi_add_x), A
    LD   A, B
    LD   (fi_add_y), A
    XOR  A
    LD   (fi_add_id), A             ; ITEM_SLOT_GOLD_SMALL
    LD   A, (abi_player_dlvl)
    LD   E, A
    LD   D, 0
    LD   A, 10
    CALL mul_de_a                   ; HL = dlvl * 10
    LD   A, H
    OR   A
    LD   A, L
    JR   Z, .cap_ok
    LD   A, 255
.cap_ok:
    CALL rng_range
    ADD  A, 5
    JR   NC, .qty_ok
    LD   A, 255
.qty_ok:
    LD   (fi_add_qty), A
    XOR  A
    LD   (fi_add_qty_hi), A
    CALL floor_item_add
.next:
    POP  DE
    POP  BC
    DJNZ .lp
    RET

; ============================================================================
; +12: _ie_identify — Interactive Identify -> IF_IDENTIFIED & id_mark_known
; ============================================================================
_ie_identify:
    LD   A, PIW_FILTER_IDENTIFY
    LD   B, HSTR_PIQ_IDENTIFY_PROMPT
    LD   HL, 0
    CALL tramp_item_mgt_select_inv  ; CF=1, A=slot, C=item_id
    RET  NC

    LD   E, A
    LD   D, 0                       ; DE = slot
    LD   HL, inv_flags
    ADD  HL, DE
    LD   A, (HL)
    AND  (~IF_SENSED) & 0xFF
    OR   IF_IDENTIFIED
    LD   (HL), A

    PUSH DE
    CALL _ie_stage_inv_de
    LD   A, (itemdesc_item_id)
    CALL id_mark_known
    POP  DE

    LD   A, HSTR_PIQ_THISIS         ; "This is a ~"
    LD   DE, temp_str_buf
    CALL huff_decode_string
    LD   HL, temp_str_buf
.f0:
    LD   A, (HL)
    OR   A
    JR   Z, .at0
    INC  HL
    JR   .f0
.at0:
    EX   DE, HL
    DEC  DE
    LD   A, (DE)
    CP   '~'
    JR   Z, .fmt
    INC  DE
.fmt:
    LD   A, 1
    LD   (itemdesc_qty), A          ; 6502 item_append_name omits stack count on Identify
    CALL item_format_staged
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   HL, temp_str_buf
    CALL msg_print_str
    CALL tramp_modal_recalc_equipment
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; ============================================================================
; +15: _ie_teleport — Silent player teleport via find_random_floor (pull-toward)
; Input: A = range limit (10 = phase door, 0 = full map)
; ============================================================================
_ie_teleport:
    CALL find_random_floor          ; CF=1, B=y, C=x (6502 pull-toward within limit)
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
    CALL monster_update_visibility_all
    CALL status_mark_dirty
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; ============================================================================
; +18: _ie_summon_many — Spawn up to A awake summon/undead monsters (MON-040/041)
; Input: A = count, B = 0 summon / 1 undead
; ============================================================================
_ie_summon_many:
    OR   A
    RET  Z
    LD   C, A                       ; C = remaining, B = is_undead
.lp:
    PUSH BC
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    CALL find_adjacent_empty_tile   ; CF=1, B=ty, C=tx
    JR   NC, .stop
    POP  DE                         ; D = is_undead, E = remaining
    PUSH DE
    PUSH BC                         ; [ty, tx]
    LD   A, D
    OR   A
    JR   Z, .norm
    CALL pick_undead_creature_type
    JR   .sp
.norm:
    CALL pick_summon_creature_type
.sp:
    POP  BC                         ; B=ty, C=tx
    CALL monster_spawn_awake
    POP  BC
    DEC  C
    JR   NZ, .lp
    LD   HL, zp_dirty_count
    INC  (HL)
    RET
.stop:
    POP  BC
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

; ============================================================================
; Internal Helpers
; ============================================================================

_ie_dispatch_hl_a:
    ADD  A, A
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    EX   DE, HL
    JP   (HL)

_ie_vms_ench_ok:
    ; VMS enchant probability: <0 always, 0..9 rng(10)>=A, 10..14 rng(20)==0, >=15 fail
    BIT  7, A
    JR   NZ, .yes
    CP   15
    JR   NC, .no
    CP   10
    JR   C, .lt10
    LD   A, 20
    CALL rng_range
    OR   A
    JR   Z, .yes
    JR   .no
.lt10:
    LD   B, A
    LD   A, 10
    CALL rng_range
    CP   B
    JR   C, .no
.yes:
    SCF
    RET
.no:
    OR   A
    RET

; VMS 1000-roll table for Scroll of Enchant Armor (+1..+9, +10+)
; Preserves DE (armor slot) across threshold lookup and roll loop.
_ie_vms_arm_ench_ok:
    BIT  7, A
    JR   NZ, .yes
    OR   A
    JR   Z, .yes
    PUSH DE
    CP   10
    JR   C, .idx_ok
    LD   A, 10
.idx_ok:
    DEC  A
    ADD  A, A
    LD   E, A
    LD   D, 0
    PUSH HL
    LD   HL, _ie_ea_chance
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)                    ; DE = threshold
    POP  HL
.rng1000:
    PUSH HL
    PUSH DE
    CALL rng_next_u16
    LD   A, H
    AND  0x03
    LD   H, A
    LD   DE, 1000
    OR   A
    SBC  HL, DE
    POP  DE
    JR   NC, .retry1000
    PUSH DE
    LD   DE, 1000
    ADD  HL, DE                     ; restore roll 0..999
    POP  DE                         ; DE = threshold, HL = roll 0..999
    OR   A
    SBC  HL, DE                     ; CF=1 if roll < threshold (fail), CF=0 if roll >= threshold (succeed)
    POP  HL
    POP  DE
    CCF
    RET
.yes:
    SCF
    RET
.retry1000:
    POP  HL
    JR   .rng1000

_ie_stage_inv_de:
    XOR  A
    LD   (itemdesc_qty), A
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_item_id), A
    LD   HL, inv_p1
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_p1), A
    LD   HL, inv_to_hit
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_to_hit), A
    LD   HL, inv_to_dam
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_to_dam), A
    LD   HL, inv_to_ac
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_to_ac), A
    LD   HL, inv_flags
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_flags), A
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_ego), A
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    RET

_ie_s_the_cap:     DB "The ", 0
_ie_s_glow_br:     DB " glows briefly.", 0

_ie_ea_chance:
    DW 40, 100, 200, 400, 600, 700, 800, 900, 950, 995

_ie_cure_timers:
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

; _ie_pick_cursed_or_rand_armour — First cursed worn armor slot if any, else random
_ie_pick_cursed_or_rand_armour:
    LD   B, 6
    LD   HL, _ie_arm_slots
.cs_lp:
    LD   E, (HL)
    LD   D, 0
    PUSH HL
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .cs_nx
    LD   HL, inv_flags
    ADD  HL, DE
    BIT  0, (HL)                    ; IF_CURSED
    JR   Z, .cs_nx
    POP  HL
    LD   A, E
    SCF
    RET
.cs_nx:
    POP  HL
    INC  HL
    DJNZ .cs_lp

_ie_pick_worn_armour:
    ; Collect worn slots among EQUIP_BODY..FEET, CLOAK and pick uniformly (rng_range(N))
    LD   B, 6
    LD   C, 0                       ; N = occupied count
    LD   HL, _ie_arm_slots
.scan:
    LD   E, (HL)
    LD   D, 0
    PUSH HL
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    POP  HL
    CP   EMPTY_SLOT
    JR   Z, .scan_nx
    PUSH HL
    PUSH DE
    LD   E, C
    LD   D, 0
    LD   HL, bss_scratch
    ADD  HL, DE
    POP  DE
    LD   (HL), E
    POP  HL
    INC  C
.scan_nx:
    INC  HL
    DJNZ .scan
    LD   A, C
    OR   A
    RET  Z                          ; CF = 0: no armor worn
    CALL rng_range                  ; A = 0..N-1
    LD   E, A
    LD   D, 0
    LD   HL, bss_scratch
    ADD  HL, DE
    LD   A, (HL)
    SCF
    RET
_ie_arm_slots:
    DB EQUIP_BODY, EQUIP_SHIELD, EQUIP_HEAD, EQUIP_HANDS, EQUIP_FEET, EQUIP_CLOAK

_ie_curse_slot_de:
    LD   HL, inv_flags
    ADD  HL, DE
    SET  0, (HL)
    LD   A, E
    CP   EQUIP_WEAPON
    JR   NZ, .clr
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    PUSH DE
    CALL item_get_category_a
    POP  DE
    CP   ICAT_DIGGING
    RET  Z
.clr:
    LD   HL, inv_p1
    ADD  HL, DE
    LD   (HL), 0
    LD   HL, inv_to_hit
    ADD  HL, DE
    LD   (HL), 0
    LD   HL, inv_to_dam
    ADD  HL, DE
    LD   (HL), 0
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (HL), A
    RET

; _ie_neighbor_bc_d — Neighbor D (0..7) or center (8) -> B=y, C=x, CF=1 if OOB
_ie_neighbor_bc_d:
    LD   A, D
    CP   8
    JR   NZ, .dir
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    OR   A
    RET
.dir:
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
    LD   A, C
    OR   A
    JR   Z, .oob
    CP   MAP_COLS - 1
    JR   NC, .oob
    LD   A, B
    OR   A
    JR   Z, .oob
    CP   MAP_ROWS - 1
    JR   NC, .oob
    OR   A
    RET
.oob:
    SCF
    RET

; _ie_trap_at_bc — CF=1 iff trap_x/y already contains (C=x, B=y); preserves B, C
_ie_trap_at_bc:
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
    JR   NZ, .nx
    LD   HL, trap_y
    ADD  HL, DE
    LD   A, (HL)
    CP   B
    JR   NZ, .nx
    SCF
    RET
.nx:
    INC  E
    LD   A, (trap_count)
    CP   E
    JR   NZ, .lp
    OR   A
    RET

_ie_add_timer:
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

_ie_step_ray:
    ; Step (proj_x, proj_y) one cell along (proj_dir) -> CF=1 if out of bounds
    LD   A, (proj_dir)
    AND  0x07
    LD   E, A
    LD   D, 0
    LD   HL, dir_dx
    ADD  HL, DE
    LD   A, (proj_x)
    ADD  A, (HL)
    LD   C, A
    LD   HL, dir_dy
    ADD  HL, DE
    LD   A, (proj_y)
    ADD  A, (HL)
    LD   B, A
    LD   A, C
    CP   MAP_COLS
    JR   NC, .oob
    LD   A, B
    CP   MAP_ROWS
    JR   NC, .oob
    LD   A, C
    LD   (proj_x), A
    LD   A, B
    LD   (proj_y), A
    OR   A
    RET
.oob:
    SCF
    RET

_ie_trace_mon:
    ; Trace ray up to 20 tiles along proj_dir. CF=1 hit monster A (proj_x/y saved at last open)
    LD   A, (abi_player_x)
    LD   (proj_x), A
    LD   A, (abi_player_y)
    LD   (proj_y), A
    LD   B, 20
.lp:
    PUSH BC
    LD   A, (proj_dir)
    AND  0x07
    LD   E, A
    LD   D, 0
    LD   HL, dir_dx
    ADD  HL, DE
    LD   A, (proj_x)
    ADD  A, (HL)
    LD   C, A
    LD   HL, dir_dy
    ADD  HL, DE
    LD   A, (proj_y)
    ADD  A, (HL)
    LD   B, A
    CALL map_get_tile
    JR   C, .wall
    PUSH AF
    CALL tile_is_walkable_a
    JR   NC, .wall_pop
    LD   A, C
    LD   (proj_x), A
    LD   A, B
    LD   (proj_y), A
    POP  AF
    AND  FLAG_OCCUPIED
    JR   Z, .nx
    CALL monster_find_at
    JR   NC, .nx
    POP  BC
    SCF
    RET
.wall_pop:
    POP  AF
.wall:
    POP  BC
    OR   A
    RET
.nx:
    POP  BC
    DJNZ .lp
    OR   A
    RET

_ie_dmg_mon_a_d:
    PUSH AF
    CALL monster_get_ptr
    PUSH HL
    INC  HL
    INC  HL
    LD   C, (HL)                    ; C = cr_type
    POP  HL
    PUSH BC                         ; C = cr_type
    LD   BC, MX_HP_LO
    ADD  HL, BC
    LD   A, (HL)
    SUB  D
    LD   E, A
    INC  HL
    LD   A, (HL)
    SBC  A, 0
    JR   C, .dead
    LD   B, A
    OR   E
    JR   Z, .dead
    DEC  HL
    LD   (HL), E
    INC  HL
    LD   (HL), B
    POP  BC                         ; C = cr_type
    POP  AF                         ; A = slot
    PUSH BC
    CALL monster_wake
    LD   A, HSTR_EB_SPELL_HITS
    LD   DE, line_buf
    CALL huff_decode_string
    LD   HL, line_buf
.fnul:
    LD   A, (HL)
    OR   A
    JR   Z, .app_the
    INC  HL
    JR   .fnul
.app_the:
    EX   DE, HL                     ; DE -> NUL after prefix
    LD   HL, _ie_s_the_lc
    CALL _ie_strcpy
    POP  BC
    LD   A, C
    JR   _ie_mon_msg_end
.dead:
    POP  BC                         ; C = cr_type
    POP  AF                         ; A = slot
    PUSH AF
    LD   DE, line_buf
    LD   HL, _ie_s_slay_p
    CALL _ie_strcpy
    LD   A, C
    CALL monster_get_name_ptr
    CALL _ie_strcpy
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   HL, line_buf
    CALL msg_print_str
    POP  AF                         ; A = slot
    JP   tramp_modal_kill_monster
_ie_mon_msg_end:
    CALL monster_get_name_ptr
    CALL _ie_strcpy
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   HL, line_buf
    JP   msg_print_str

_ie_strcpy:
    LD   A, (HL)
    LD   (DE), A
    OR   A
    RET  Z
    INC  HL
    INC  DE
    JR   _ie_strcpy

_ie_pick_dungeon_item:
    JP   tramp_chest_pick_item

_ie_s_blow:        DB "There is a bright flash of light.", 0
_ie_s_the_lc:      DB " the ", 0
_ie_s_slay_p:      DB "You have slain the ", 0
_ie_s_magic_map:   DB "You feel your map grow clearer.", 0
_ie_s_treasure:    DB "You sense treasure nearby.", 0
_ie_s_doors_stairs: DB "You sense doors and stairs.", 0

; ============================================================================
; Extended 6502-Parity Item Effect Helpers (Scrolls / Wands / Staves)
; ============================================================================

_ie_mark_vis_dirty:
    LD   A, 1
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

; Unlock+disarm floor chest slot DE (leaves fi_meta_hi ego unchanged like 6502 eff_item_p1.s:576)
_ie_chest_disarm_slot_de:
    LD   HL, fi_p1
    ADD  HL, DE
    LD   A, (HL)
    AND  (0xFF ^ (CHEST_P1_TRAP_MASK | CHEST_P1_LOCKED))
    LD   (HL), A
    RET

; Return C = map_cols, B = map_rows (town if dlvl == 0, dungeon otherwise)
_ie_map_dims:
    LD   A, (abi_player_dlvl)
    OR   A
    LD   C, TOWN_MAP_COLS
    LD   B, TOWN_MAP_ROWS
    RET  Z
    LD   C, MAP_COLS
    LD   B, MAP_ROWS
    RET

; Scroll of Magic Mapping: eff_reveal_floorplan + eff_find_doors + "You feel your map grow clearer."
_ie_magic_map:
    CALL _ie_map_dims               ; C=cols, B=rows
    LD   A, C
    LD   (bss_scratch + 0), A
    DEC  A
    LD   (bss_scratch + 2), A       ; cols - 1
    LD   A, B
    LD   (bss_scratch + 1), A
    DEC  A
    LD   (bss_scratch + 3), A       ; rows - 1
    LD   B, 0
.mm_y:
    LD   C, 0
.mm_x:
    CALL map_get_tile
    JR   C, .mm_nx
    LD   E, A
    AND  TILE_TYPE_MASK
    CP   TILE_SECRET
    JR   Z, .mm_sec
    CP   TILE_FLOOR
    JR   Z, .mm_vis
    CP   TILE_DOOR_OPEN
    JR   NC, .mm_vis
    BIT  3, E                       ; FLAG_LIT
    JR   Z, .mm_nx
.mm_vis:
    LD   A, E
    OR   FLAG_VISITED
    CALL map_set_tile
    JR   .mm_nx
.mm_sec:
    LD   A, B
    OR   A
    JR   Z, .mm_nx
    LD   HL, bss_scratch + 3
    CP   (HL)
    JR   NC, .mm_nx
    LD   A, C
    OR   A
    JR   Z, .mm_nx
    DEC  HL
    CP   (HL)
    JR   NC, .mm_nx
    LD   A, E
    AND  TILE_FLAG_MASK
    OR   TILE_DOOR_CLOSED | FLAG_VISITED
    CALL map_set_tile
.mm_nx:
    INC  C
    LD   A, (bss_scratch + 0)
    CP   C
    JR   NZ, .mm_x
    INC  B
    LD   A, (bss_scratch + 1)
    CP   B
    JR   NZ, .mm_y
    CALL _ie_mark_vis_dirty
    LD   HL, _ie_s_magic_map
    JP   msg_print_str

; Scroll of Object Detection: mark all floor items VISITED|LIT + "You sense treasure nearby."
_ie_det_objs:
    LD   E, 0
.do_lp:
    LD   D, 0
    LD   HL, fi_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .do_nx
    PUSH DE
    LD   HL, fi_y
    ADD  HL, DE
    LD   B, (HL)
    LD   HL, fi_x
    ADD  HL, DE
    LD   C, (HL)
    CALL map_get_tile
    JR   C, .do_pop
    OR   FLAG_VISITED | FLAG_LIT
    CALL map_set_tile
.do_pop:
    POP  DE
.do_nx:
    INC  E
    LD   A, E
    CP   MAX_FLOOR_ITEMS
    JR   C, .do_lp
    CALL _ie_mark_vis_dirty
    LD   HL, _ie_s_treasure
    JP   msg_print_str

; Scroll/Staff of Trap Detection/Location: mark floor traps LIT+VISITED, mark chest traps, report found/nothing
_ie_det_traps:
    XOR  A
    LD   (bss_scratch + 0), A       ; found count
    LD   A, (trap_count)
    OR   A
    JR   Z, .dt_chests
    LD   E, 0
.dt_tlp:
    LD   D, 0
    PUSH DE
    LD   HL, trap_y
    ADD  HL, DE
    LD   B, (HL)
    LD   HL, trap_x
    ADD  HL, DE
    LD   C, (HL)
    CALL map_get_tile
    JR   C, .dt_tpop
    AND  TILE_FLAG_MASK
    OR   TILE_TRAP | FLAG_VISITED | FLAG_LIT
    CALL map_set_tile
    LD   HL, bss_scratch + 0
    INC  (HL)
.dt_tpop:
    POP  DE
    INC  E
    LD   A, (trap_count)
    CP   E
    JR   NZ, .dt_tlp
.dt_chests:
    LD   E, 0
.dt_clp:
    LD   D, 0
    LD   HL, fi_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .dt_cnx
    LD   HL, fi_meta_hi
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   HL, fi_item_id
    ADD  HL, DE
    LD   A, (HL)
    PUSH DE
    CALL item_get_category_a
    POP  DE
    CP   ICAT_CHEST
    JR   NZ, .dt_cnx
    LD   HL, fi_p1
    ADD  HL, DE
    LD   A, (HL)
    BIT  7, A                       ; skip opened
    JR   NZ, .dt_cnx
    AND  CHEST_P1_TRAP_MASK
    JR   Z, .dt_cnx
    SET  6, (HL)                    ; CHEST_P1_TRAP_FOUND
.dt_cnx:
    INC  E
    LD   A, E
    CP   MAX_FLOOR_ITEMS
    JR   C, .dt_clp
    CALL _ie_mark_vis_dirty
    LD   A, (bss_scratch + 0)
    OR   A
    LD   A, HSTR_DF_FOUND_TRAP
    JR   NZ, .dt_msg
    LD   A, HSTR_DF_FOUND_NOTHING
.dt_msg:
    JP   msg_print_huff

; Scroll/Staff of Door/Stair Location: secret->door+visited, doors->visited, stairs->visited+lit + msg
_ie_det_doors:
    CALL _ie_map_dims               ; C=cols, B=rows
    DEC  C
    LD   A, C
    LD   (bss_scratch + 0), A       ; cols - 1
    DEC  B
    LD   A, B
    LD   (bss_scratch + 1), A       ; rows - 1
    LD   B, 1
.dd_y:
    LD   A, (bss_scratch + 1)
    CP   B
    JR   Z, .dd_done
    JR   C, .dd_done
    LD   C, 1
.dd_x:
    LD   A, (bss_scratch + 0)
    CP   C
    JR   Z, .dd_ynx
    JR   C, .dd_ynx
    CALL map_get_tile
    JR   C, .dd_xnx
    LD   E, A
    AND  TILE_TYPE_MASK
    CP   TILE_SECRET
    JR   NZ, .dd_chk
    LD   A, E
    AND  TILE_FLAG_MASK
    OR   TILE_DOOR_CLOSED | FLAG_VISITED
    JR   .dd_set
.dd_chk:
    CP   TILE_STAIRS_UP
    JR   Z, .dd_lit
    CP   TILE_STAIRS_DN
    JR   NZ, .dd_xnx
.dd_lit:
    LD   A, E
    OR   FLAG_VISITED | FLAG_LIT
.dd_set:
    CALL map_set_tile
.dd_xnx:
    INC  C
    JR   .dd_x
.dd_ynx:
    INC  B
    JR   .dd_y
.dd_done:
    CALL _ie_mark_vis_dirty
    LD   HL, _ie_s_doors_stairs
    JP   msg_print_str

; Scroll Sleep Monster / Staff Sleep Monsters: CD_NO_SLEEP only, 10..29 turns, silent
_ie_sleep_adj:
    LD   A, 1
    JR   _ie_sleep_common
_ie_sleep_all:
    XOR  A
_ie_sleep_common:
    LD   (bss_scratch + 0), A
    LD   C, 0
.sl_lp:
    LD   A, C
    CALL monster_get_ptr
    JR   C, .sl_done
    PUSH HL
    INC  HL
    INC  HL
    LD   E, (HL)                    ; E = MX_TYPE
    POP  HL
    LD   A, E
    CP   EMPTY_SLOT
    JR   Z, .sl_nx
    LD   A, (bss_scratch + 0)
    OR   A
    JR   Z, .sl_vis
    ; Adjacent Chebyshev dist <= 1 (E saved in bss_scratch + 1 across coords)
    LD   A, E
    LD   (bss_scratch + 1), A
    LD   E, (HL)                    ; mx
    INC  HL
    LD   D, (HL)                    ; my
    LD   A, (abi_player_x)
    SUB  E
    JR   NC, .axp
    NEG
.axp:
    CP   2
    JR   NC, .sl_nx
    LD   A, (abi_player_y)
    SUB  D
    JR   NC, .ayp
    NEG
.ayp:
    CP   2
    JR   NC, .sl_nx
    LD   A, (bss_scratch + 1)
    LD   E, A
    JR   .sl_apply
.sl_vis:
    LD   A, E
    LD   E, MX_FLAGS
    LD   D, 0
    ADD  HL, DE
    BIT  3, (HL)                    ; MF_VISIBLE
    JR   Z, .sl_nx
    LD   E, A
.sl_apply:
    LD   D, 0
    LD   HL, cr_cdefense
    ADD  HL, DE
    BIT  6, (HL)                    ; CD_NO_SLEEP
    JR   NZ, .sl_nx
    LD   A, 20
    CALL rng_range                  ; preserves BC
    ADD  A, 10
    PUSH BC
    LD   B, A
    LD   A, C
    CALL monster_apply_sleep
    POP  BC
.sl_nx:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .sl_lp
.sl_done:
    LD   HL, zp_dirty_count
    INC  (HL)
    RET

; Staff of Detect Evil: scan all MAX_MONSTERS (map-wide) for CF_EVIL
_ie_st_det_evil:
    XOR  A
    LD   (bss_scratch + 0), A
    LD   C, 0
.sde_lp:
    LD   A, C
    CALL monster_get_ptr
    JR   C, .sde_done
    PUSH HL
    INC  HL
    INC  HL
    LD   E, (HL)
    POP  HL
    LD   A, E
    CP   EMPTY_SLOT
    JR   Z, .sde_nx
    LD   D, 0
    PUSH HL
    LD   HL, cr_mflags
    ADD  HL, DE
    BIT  2, (HL)                    ; CF_EVIL
    POP  HL
    JR   Z, .sde_nx
    LD   DE, MX_FLAGS
    ADD  HL, DE
    SET  4, (HL)                    ; MF_DETECTED
    LD   A, 1
    LD   (bss_scratch + 0), A
.sde_nx:
    INC  C
    LD   A, C
    CP   MAX_MONSTERS
    JR   C, .sde_lp
.sde_done:
    LD   A, (bss_scratch + 0)
    OR   A
    JR   Z, .sde_none
    LD   (eff_detect_evil_mode), A
    LD   (vis_room_revealed), A
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   A, HSTR_PIQ_SENSE
    JP   msg_print_huff
.sde_none:
    LD   A, HSTR_PIQ_NOTHING
    JP   msg_print_huff

; Scroll/Wand Trap/Door Destruction: 5x5 -> TILE_FLOOR, disarm traps/doors/chests
_ie_dest_traps:
    CALL _ie_map_dims               ; C=cols, B=rows
    DEC  C
    DEC  C
    LD   E, C                       ; E = max_x (cols - 2)
    DEC  B
    DEC  B
    LD   D, B                       ; D = max_y (rows - 2)
    LD   A, (abi_player_y)
    CP   3
    JR   NC, .y0_sub
    LD   A, 1
    JR   .y0_ok
.y0_sub:
    SUB  2
.y0_ok:
    LD   (bss_scratch + 2), A       ; y0
    LD   A, (abi_player_y)
    ADD  A, 2
    CP   D
    JR   C, .y1_ok
    LD   A, D
.y1_ok:
    LD   (bss_scratch + 3), A       ; y1
    LD   A, (abi_player_x)
    CP   3
    JR   NC, .x0_sub
    LD   A, 1
    JR   .x0_ok
.x0_sub:
    SUB  2
.x0_ok:
    LD   (bss_scratch + 0), A       ; x0
    LD   A, (abi_player_x)
    ADD  A, 2
    CP   E
    JR   C, .x1_ok
    LD   A, E
.x1_ok:
    LD   (bss_scratch + 1), A       ; x1

    LD   A, (bss_scratch + 2)
    LD   B, A
.d5_y:
    LD   A, (bss_scratch + 0)
    LD   C, A
.d5_x:
    CALL _ie_dest_tile_bc
    LD   HL, bss_scratch + 1
    LD   A, C
    CP   (HL)
    JR   NC, .d5_ynx
    INC  C
    JR   .d5_x
.d5_ynx:
    LD   HL, bss_scratch + 3
    LD   A, B
    CP   (HL)
    JR   NC, .d5_done
    INC  B
    JR   .d5_y
.d5_done:
    JP   _ie_mark_vis_dirty

; Wand of Trap/Door Destruction: 20-tile beam along proj_dir, breaking doors & continuing
_ie_wand_dest_traps:
    LD   A, (abi_player_x)
    LD   (proj_x), A
    LD   A, (abi_player_y)
    LD   (proj_y), A
    LD   B, 20
.wd_lp:
    PUSH BC
    CALL _ie_step_ray
    JR   C, .wd_pop
    CALL map_get_tile
    JR   C, .wd_pop
    LD   E, A
    CALL tile_is_walkable_a
    JR   C, .wd_clr
    LD   A, E
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_CLOSED
    JR   Z, .wd_clr
    CP   TILE_SECRET
    JR   NZ, .wd_pop
.wd_clr:
    CALL _ie_dest_tile_bc
    POP  BC
    DJNZ .wd_lp
    JP   _ie_mark_vis_dirty
.wd_pop:
    POP  BC
    JP   _ie_mark_vis_dirty

; Clear traps, chests (if FLAG_HAS_ITEM), and closed/secret doors at (B=y, C=x). Preserves B, C.
_ie_dest_tile_bc:
    CALL _ie_remove_trap_bc         ; preserves B, C (and copies trap_type)
    CALL map_get_tile
    RET  C
    LD   E, A
    BIT  1, E                       ; FLAG_HAS_ITEM?
    JR   Z, .dtb_tile
    PUSH DE
    CALL _ie_disarm_chest_at
    POP  DE
.dtb_tile:
    LD   A, E
    AND  TILE_TYPE_MASK
    CP   TILE_TRAP
    JR   Z, .dtb_flr
    CP   TILE_DOOR_CLOSED
    JR   Z, .dtb_door
    CP   TILE_SECRET
    RET  NZ
.dtb_door:
    CALL _ie_clear_door_state_at    ; preserves B, C
.dtb_flr:
    LD   A, E
    AND  TILE_FLAG_MASK
    OR   FLAG_VISITED
    JP   map_set_tile

; Remove door_state at (B=y, C=x) (preserves B, C)
_ie_clear_door_state_at:
    LD   A, (door_state_count)
    OR   A
    RET  Z
    LD   E, 0
.cds_lp:
    LD   D, 0
    LD   HL, door_state_x
    ADD  HL, DE
    LD   A, (HL)
    CP   C
    JR   NZ, .cds_nx
    LD   HL, door_state_y
    ADD  HL, DE
    LD   A, (HL)
    CP   B
    JR   Z, .cds_del
.cds_nx:
    INC  E
    LD   A, (door_state_count)
    CP   E
    JR   NZ, .cds_lp
    RET
.cds_del:
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

; Disarm floor chest at (B=y, C=x) (preserves B, C)
_ie_disarm_chest_at:
    LD   E, 0
.dca_lp:
    LD   D, 0
    LD   HL, fi_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .dca_nx
    LD   HL, fi_x
    ADD  HL, DE
    LD   A, (HL)
    CP   C
    JR   NZ, .dca_nx
    LD   HL, fi_y
    ADD  HL, DE
    LD   A, (HL)
    CP   B
    JR   NZ, .dca_nx
    LD   HL, fi_meta_hi
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   HL, fi_item_id
    ADD  HL, DE
    LD   A, (HL)
    PUSH BC
    PUSH DE
    CALL item_get_category_a
    POP  DE
    POP  BC
    CP   ICAT_CHEST
    JR   NZ, .dca_nx
    PUSH BC
    CALL _ie_chest_disarm_slot_de
    POP  BC
    RET
.dca_nx:
    INC  E
    LD   A, E
    CP   MAX_FLOOR_ITEMS
    JR   C, .dca_lp
    RET

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end
    SAVEBIN "ovl_items_eff.ovl", ovl_start, ovl_end - ovl_start
