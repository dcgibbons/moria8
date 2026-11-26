; ovl_item_mgt.asm — Moria8 CP/M Item Management, Consumable Foods, Refuel,
; Ranged Fire, Throw, Enchantment & Filtered Inventory Selector Overlay.
; (OVL_ITEM_MGT = 19, DAT slot 24)
;
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0:  JP ovl_item_mgt_pickup       ('g' / ',') -> CF=1 turn, CF=0 cancel
;   +3:  JP ovl_item_mgt_wear         ('w')       -> CF=1 turn, CF=0 cancel
;   +6:  JP ovl_item_mgt_takeoff      ('t')       -> CF=1 turn, CF=0 cancel
;   +9:  JP ovl_item_mgt_drop         ('d')       -> CF=1 turn, CF=0 cancel
;   +12: JP ovl_item_mgt_eat          ('E')       -> CF=1 turn, CF=0 cancel
;   +15: JP ovl_item_mgt_refuel       ('R')       -> CF=1 turn, CF=0 cancel
;   +18: JP ovl_item_mgt_fire         ('F')       -> CF=1 turn, CF=0 cancel
;   +21: JP ovl_item_mgt_throw        ('T')       -> CF=1 turn, CF=0 cancel
;   +24: JP ovl_item_mgt_roll_enchant ()          -> mutates fi_add_*
;   +27: JP ovl_item_mgt_select_inv   (A=filter, HL=prompt|0, B=hstr_id)
;                                                 -> CF=1, A=slot, C=id; CF=0 cancel
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
    JP   ovl_item_mgt_pickup        ; +0
    JP   ovl_item_mgt_wear          ; +3
    JP   ovl_item_mgt_takeoff       ; +6
    JP   ovl_item_mgt_drop          ; +9
    JP   ovl_item_mgt_eat           ; +12
    JP   ovl_item_mgt_refuel        ; +15
    JP   ovl_item_mgt_fire          ; +18
    JP   ovl_item_mgt_throw         ; +21
    JP   ovl_item_mgt_roll_enchant  ; +24
    JP   ovl_item_mgt_select_inv    ; +27

; ============================================================================
; Public Entry Wrappers (preserve IX and IY across every vector)
; ============================================================================

ovl_item_mgt_pickup:
    PUSH IX
    PUSH IY
    CALL _im_pickup
    JR   _im_ret_ixiy

ovl_item_mgt_wear:
    PUSH IX
    PUSH IY
    CALL _im_wear
    JR   _im_ret_ixiy

ovl_item_mgt_takeoff:
    PUSH IX
    PUSH IY
    CALL _im_takeoff
    JR   _im_ret_ixiy

ovl_item_mgt_drop:
    PUSH IX
    PUSH IY
    CALL _im_drop
    JR   _im_ret_ixiy

ovl_item_mgt_eat:
    PUSH IX
    PUSH IY
    CALL _im_eat
    JR   _im_ret_ixiy

ovl_item_mgt_refuel:
    PUSH IX
    PUSH IY
    CALL _im_refuel
    JR   _im_ret_ixiy

ovl_item_mgt_fire:
    PUSH IX
    PUSH IY
    CALL _im_fire
    JR   _im_ret_ixiy

ovl_item_mgt_throw:
    PUSH IX
    PUSH IY
    CALL _im_throw
    JR   _im_ret_ixiy

ovl_item_mgt_roll_enchant:
    PUSH IX
    PUSH IY
    CALL _im_roll_enchant
    JR   _im_ret_ixiy

ovl_item_mgt_select_inv:
    PUSH IX
    PUSH IY
    CALL _im_select_inv_ext
_im_ret_ixiy:
    POP  IY
    POP  IX
    RET

; ============================================================================
; +27: _im_select_inv — Filtered Pack/Equipment Picker with '?' Modal List
; Input:  A = PIW_FILTER_* or ICAT_*, HL = prompt str (or 0), B = hstr_id
;         External callers passing HL in [0x5600..0x69FF] have HL resolved
;         from filter (because cross-overlay HL is overwritten on load).
; Output: CF = 1, A = selected slot, C = item_id; CF = 0 cancel / none
; ============================================================================
IM_FILTER_WEARABLE     EQU 0xF7

_im_select_inv_ext:
    LD   D, A
    LD   A, H
    OR   L
    JR   Z, .ext_hstr
    LD   A, H
    CP   0x56
    JR   C, .ext_ok
    CP   0x6A
    JR   NC, .ext_ok
    ; Caller's prompt was in overlay window -> map filter to prompt string
    LD   A, D
    CP   PIW_FILTER_RECHARGE
    LD   HL, _im_s_recharge
    JR   Z, .ext_ok
.ext_hstr:
    LD   HL, 0
.ext_ok:
    LD   A, D

_im_select_inv:
    LD   (piw_filter), A
    PUSH HL
    PUSH BC

    ; Build piw_visible_slots[0..piw_visible_count-1]
    XOR  A
    LD   (piw_visible_count), A
    LD   A, (piw_filter)
    CP   PIW_FILTER_EQUIP
    JR   NZ, .chk_pack
    LD   B, EQUIP_WEAPON
    LD   C, VISIBLE_EQUIP_END
    JR   .scan_lp
.chk_pack:
    LD   B, 0
    LD   C, MAX_INV_SLOTS
.scan_lp:
    LD   A, B
    CP   C
    JR   NC, .scan_done
    LD   E, B
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .scan_next
    PUSH BC
    PUSH DE
    CALL _im_slot_matches_filter
    POP  DE
    POP  BC
    JR   NC, .scan_next
    LD   A, (piw_visible_count)
    LD   L, A
    LD   H, 0
    LD   DE, piw_visible_slots
    ADD  HL, DE
    LD   (HL), B
    LD   HL, piw_visible_count
    INC  (HL)
.scan_next:
    INC  B
    JR   .scan_lp

.scan_done:
    POP  BC
    POP  HL
    LD   A, (piw_visible_count)
    OR   A
    JR   NZ, .have_items

    ; Nothing matches filter
    LD   A, (piw_filter)
    CP   ICAT_FOOD
    LD   B, HSTR_PIW_NO_FOOD
    JR   Z, .none_hstr_b
    CP   PIW_FILTER_AMMO
    LD   B, HSTR_RF_NO_AMMO
    JR   Z, .none_hstr_b
    CP   PIW_FILTER_FUEL
    LD   B, HSTR_PIR_NO_OIL
    JR   Z, .none_hstr_b
    LD   B, HSTR_PIW_NOTHING
.none_hstr_b:
    LD   A, B
    CALL msg_print_huff
    OR   A
    RET

.have_items:
    ; Format prompt into line_buf cleanly; patch "(a-v)" in-place if present
    LD   A, H
    OR   L
    JR   NZ, .cp_prompt
    LD   A, B
    OR   A
    JR   NZ, .dec_prompt
    LD   HL, _im_s_which
    JR   .cp_prompt
.dec_prompt:
    LD   DE, line_buf
    CALL huff_decode_string
    JR   .chk_trim_q
.cp_prompt:
    LD   DE, line_buf
    CALL _im_cpystr
.chk_trim_q:
    LD   HL, line_buf
.patch_lp:
    LD   A, (HL)
    OR   A
    JR   Z, .append_rng
    CP   '-'
    JR   NZ, .patch_next
    INC  HL
    LD   A, (HL)
    OR   A
    JR   Z, .prompt_ready
    LD   A, (piw_visible_count)
    DEC  A
    ADD  A, 'a'
    LD   (HL), A
    JR   .prompt_ready
.patch_next:
    INC  HL
    JR   .patch_lp
.append_rng:
    ; Prompt lacked "(a-v)" (e.g., book/recharge string) -> append " (a-X)"
    EX   DE, HL                     ; DE -> NUL at end of line_buf
    LD   HL, _im_s_range_pre        ; " (a-"
    CALL _im_cpystr                 ; returns DE at NUL after '-'
    LD   A, (piw_visible_count)
    DEC  A
    ADD  A, 'a'
    LD   (DE), A
    INC  DE
    LD   A, ')'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
.prompt_ready:
    CALL msg_clear
    LD   B, 0
    LD   C, 0
    LD   E, COL_PROMPT
    LD   HL, line_buf
    CALL screen_put_str
    CALL screen_flush

.wait_key:
    CALL input_get_key
    CP   '?'
    JR   Z, .show_list
    CP   KEY_ESC
    JR   Z, .cancel
    CP   KEY_SPACE
    JR   Z, .cancel
    CP   0x03                       ; Ctrl-C
    JR   Z, .cancel
    CALL _im_pick_letter_a
    JR   NC, .cancel
    ; Clear prompt row cleanly and return CF=1, A=slot, C=item_id
    PUSH AF
    PUSH BC
    CALL _im_clear_prompt_row
    POP  BC
    POP  AF
    SCF
    RET

.cancel:
    CALL _im_clear_prompt_row
    LD   A, (piw_filter)
    CP   PIW_FILTER_IDENTIFY
    LD   A, HSTR_PIW_NEVERMIND
    JR   NZ, .cancel_msg
    LD   A, HSTR_PIQ_NOTHING
.cancel_msg:
    CALL msg_print_huff
    OR   A
    RET

.show_list:
    CALL tramp_ui_select_display
    PUSH AF
    CALL _im_redraw_play_screen
    POP  AF
    CP   KEY_ESC
    JP   Z, .cancel
    CP   KEY_SPACE
    JP   Z, .cancel
    CP   0x03
    JP   Z, .cancel
    CALL _im_pick_letter_a
    JR   C, .list_picked
    JP   .cancel
.list_picked:
    SCF
    RET

; _im_pick_letter_a — Convert key A ('a'..'a'+count-1 or A..Z) -> CF=1, A=slot, C=item_id.
_im_pick_letter_a:
    CP   'A'
    JR   C, .not_uc
    CP   'Z' + 1
    JR   NC, .not_uc
    OR   0x20
.not_uc:
    SUB  'a'
    RET  C
    LD   HL, piw_visible_count
    CP   (HL)
    JR   NC, .no
    LD   E, A
    LD   D, 0
    LD   HL, piw_visible_slots
    ADD  HL, DE
    LD   E, (HL)                    ; E = slot
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   C, (HL)                    ; C = item_id
    LD   A, E                       ; A = slot
    LD   (piw_slot), A
    SCF
    RET
.no:
    OR   A
    RET

; _im_slot_matches_filter — Check if inv slot E (item_id A) matches piw_filter -> CF=1.
_im_slot_matches_filter:
    LD   D, 0
    PUSH DE
    LD   HL, inv_ego
    ADD  HL, DE
    LD   B, (HL)
    LD   A, B
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   D, (HL)                    ; D = item_id
    POP  HL                         ; L = slot

    LD   A, (piw_filter)
    CP   PIW_FILTER_ALL
    JP   Z, .yes
    CP   PIW_FILTER_EQUIP
    JP   Z, .yes
    CP   IM_FILTER_WEARABLE
    JR   NZ, .not_wear
    LD   A, (item_cur_page)
    OR   A
    JR   NZ, .w_chk
    LD   A, D
    CP   ITEM_SLOT_FLASK_OF_OIL
    JP   Z, .no
.w_chk:
    LD   A, D
    CALL item_get_category_a
    LD   E, A
    LD   D, 0
    LD   HL, equip_slot_for_cat
    ADD  HL, DE
    LD   A, (HL)
    CP   0xFF
    JP   Z, .no
    SCF
    RET
.not_wear:
    CP   PIW_FILTER_IDENTIFY
    JP   Z, .yes
.not_id:
    CP   PIW_FILTER_MAGE_BOOK
    JR   NZ, .not_mbook
    LD   A, (item_cur_page)
    OR   A
    JR   NZ, .no
    LD   A, D
    SUB  ITEM_SLOT_SPELLBOOK_BEGINNERS_MAGICK
    CP   4
    RET                             ; CF=1 iff < 4
.not_mbook:
    CP   PIW_FILTER_PRAYER_BOOK
    JR   NZ, .not_pbook
    LD   A, (item_cur_page)
    OR   A
    JR   NZ, .no
    LD   A, D
    SUB  ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_BEGINNERS_HANDBOOK
    CP   4
    RET
.not_pbook:
    CP   PIW_FILTER_FUEL
    JR   NZ, .not_fuel
    LD   A, (item_cur_page)
    OR   A
    JR   NZ, .no
    LD   A, D
    CP   ITEM_SLOT_WOODEN_TORCH
    JR   Z, .yes
    CP   ITEM_SLOT_FLASK_OF_OIL
    JR   Z, .yes
    OR   A
    RET
.not_fuel:
    CP   PIW_FILTER_RECHARGE
    JR   NZ, .not_rech
    LD   A, D
    CALL item_get_category_a
    CP   ICAT_WAND
    JR   Z, .yes
    CP   ICAT_STAFF
    JR   Z, .yes
    OR   A
    RET
.not_rech:
    CP   PIW_FILTER_AMMO
    JR   NZ, .exact_cat
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   EMPTY_SLOT
    JR   Z, .no
    LD   B, A
    LD   A, (inv_ego + EQUIP_WEAPON)
    AND  ITEM_PAGE_BIT
    JR   NZ, .no                    ; all launchers on Page 0
    LD   A, B
    CALL _im_launcher_msl           ; -> CF=1, A=req missile (1..3)
    RET  NC
    LD   C, A
    LD   A, D
    CALL icat_select_id
    JR   C, .no
    CALL icat_get_level_missile     ; B = missile byte
    BIT  7, B
    JR   Z, .no
    LD   A, B
    AND  0x7F
    CP   C
    JR   Z, .yes
    OR   A
    RET
.exact_cat:
    LD   B, A                       ; B = target ICAT_*
    LD   A, D
    CALL item_get_category_a
    CP   B
    JR   Z, .yes
.no:
    OR   A
    RET
.yes:
    SCF
    RET

; ============================================================================
; +0: _im_pickup — Pick up gold or item under player
; ============================================================================
_im_pickup:
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    CALL floor_item_find_at         ; CF=1, A=floor_slot
    JR   C, .found
    LD   A, HSTR_IPU_NOTHING
    CALL msg_print_huff
    OR   A
    RET
.found:
    PUSH AF                         ; save floor slot
    CALL _im_fi_to_fi_add
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (fi_add_id)
    CALL item_get_category_a
    CP   ICAT_GOLD
    JR   NZ, .non_gold

    ; Gold: 16-bit value = fi_qty + (fi_p1 << 8)
    LD   HL, (fi_add_qty)           ; L=qty (lo), H=qty_hi? (fi_add_qty_hi is +1!)
    LD   A, (fi_add_p1)
    LD   H, A
    LD   E, 0
    PUSH HL
    CALL player_add_gold_24
    CALL status_mark_dirty
    POP  HL                         ; HL = gold amount
    POP  AF                         ; floor slot
    PUSH HL
    CALL floor_item_remove
    LD   A, HSTR_IPU_FOUND
    LD   DE, temp_str_buf
    CALL huff_decode_string         ; "You found ~"
    CALL _im_trim_tilde
    POP  HL
    CALL fmt_u16_dec                ; DE -> after digits
    LD   A, HSTR_IPU_GOLD           ; " gold pieces."
    CALL huff_decode_string
    LD   HL, temp_str_buf
    CALL msg_print_str
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

.non_gold:
    CALL inv_add_carried            ; CF=1, A=inv_slot; CF=0, A=HSTR_UIS_*
    JR   C, .picked
    POP  BC                         ; discard floor slot
    CALL msg_print_huff
    OR   A
    RET
.picked:
    POP  AF                         ; A = floor_slot
    CALL floor_item_remove
    LD   A, HSTR_IPU_PICKED         ; print picked-up fi_add_* qty/attrs before merge
    CALL _im_print_prefixed_a
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; ============================================================================
; +3: _im_wear — Wield weapon / wear armor / light / ring / amulet / cloak
; ============================================================================
_im_wear:
    LD   A, IM_FILTER_WEARABLE
    LD   B, HSTR_PIW_WEAR_PROMPT
    LD   HL, 0
    CALL _im_select_inv
    RET  NC

    LD   E, A                       ; E = pack slot
    LD   D, 0
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, C
    CALL item_get_category_a        ; A = ICAT_*
    LD   C, A                       ; C = category
    LD   L, A
    LD   H, 0
    LD   DE, equip_slot_for_cat
    ADD  HL, DE
    LD   A, (HL)                    ; A = dest equip slot or 0xFF
    CP   0xFF
    RET  Z

.slot_found:
    ; Ring: EQUIP_RING when free, else ALWAYS EQUIP_RING2 (6502 parity)
    CP   EQUIP_RING
    JR   NZ, .chk_cursed
    LD   HL, inv_item_id + EQUIP_RING
    LD   B, (HL)
    INC  B
    JR   Z, .chk_cursed             ; EQUIP_RING is EMPTY_SLOT (0xFF)
    LD   A, EQUIP_RING2

.chk_cursed:
    LD   B, A                       ; B = target equip slot
    LD   E, B
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .no_old_curse
    LD   HL, inv_flags
    ADD  HL, DE
    BIT  0, (HL)                    ; IF_CURSED
    JR   Z, .no_old_curse
    LD   A, HSTR_PIW_CURSED
    CALL msg_print_huff
    OR   A
    RET

.no_old_curse:
    LD   A, (piw_slot)
    LD   D, A                       ; D = pack slot
    ; Stack: B = target equip slot, C = category, D = pack slot
    LD   E, B
    PUSH BC                         ; [B=equip_slot, C=cat]
    PUSH DE                         ; [D=pack_slot]
    LD   A, D
    CALL _im_inv_to_fi_add          ; fi_add_* = item to wear
    ; Split 1 unit out of pack when qty >= 2 (matches 6502 player_item_commands.s:90)
    LD   A, (fi_add_qty)
    CP   2
    JR   C, .chk_old_swap
    ; Split 1 torch out of pack: move old EQUIP_LIGHT FIRST so pack+floor full aborts cleanly (6502 player_item_commands.s:90)
    LD   A, 1
    LD   (fi_add_qty), A
    LD   E, B
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .torch_consume
    CALL _im_move_old_equip_b       ; preserves B, fi_add_*; CF=1 ok, CF=0 both pack+floor full
    JR   C, .torch_consume
    POP  DE
    POP  BC
    LD   A, HSTR_UIS_PACK_FULL
    CALL msg_print_huff
    OR   A
    RET
.torch_consume:
    LD   A, (piw_slot)
    CALL inv_consume_one
    POP  DE
    POP  BC
    JR   .place_new

.chk_old_swap:
    ; Single-item swap: swap in-place if equip slot occupied (6502 player_item_commands.s:69-88)
    POP  DE                         ; D = pack_slot
    POP  BC                         ; B = equip_slot, C = cat
    LD   E, B
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   NZ, .swap_inplace
    PUSH BC
    LD   A, (piw_slot)
    CALL inv_remove_item
    POP  BC
    JR   .place_new
.swap_inplace:
    PUSH BC                         ; save B = equip_slot, C = cat
    ; HL = &inv_item_id[equip_slot]
    LD   A, (piw_slot)
    LD   E, A
    LD   D, 0
    EX   DE, HL                     ; DE = &inv_item_id[equip_slot]
    LD   BC, inv_item_id
    ADD  HL, BC                     ; HL = &inv_item_id[pack_slot]
    LD   BC, TOTAL_INV_SLOTS
    LD   A, 8
.swap8_lp:
    PUSH AF
    LD   A, (DE)
    LD   (HL), A
    ADD  HL, BC
    EX   DE, HL
    ADD  HL, BC
    EX   DE, HL
    POP  AF
    DEC  A
    JR   NZ, .swap8_lp
    POP  BC                         ; B = equip_slot, C = cat

.place_new:
    ; Store fi_add_* into inv_*[B=equip_slot]
    PUSH BC
    LD   A, B
    CALL _im_fi_add_to_slot
    POP  BC
    ; Check light radius if EQUIP_LIGHT
    LD   A, B
    CP   EQUIP_LIGHT
    JR   NZ, .recalc_wear
    CALL _im_sync_light_from_slot
.recalc_wear:
    PUSH BC
    CALL tramp_modal_recalc_equipment
    CALL status_mark_dirty
    CALL los_update_visibility
    LD   HL, zp_dirty_count
    INC  (HL)
    POP  BC
    LD   A, B
    CP   EQUIP_WEAPON
    LD   A, HSTR_PIW_WIELD
    JR   Z, .pmsg
    LD   A, HSTR_PIW_WEARING
.pmsg:
    CALL _im_print_prefixed_a
    SCF
    RET

; ============================================================================
; +6: _im_takeoff — Remove worn/wielded item, explicitly zero light if EQUIP_LIGHT
; ============================================================================
_im_takeoff:
    LD   A, PIW_FILTER_EQUIP
    LD   B, HSTR_PIW_TAKEOFF_PROMPT
    LD   HL, 0
    CALL _im_select_inv
    RET  NC

    LD   E, A
    LD   D, 0
    LD   HL, inv_flags
    ADD  HL, DE
    BIT  0, (HL)                    ; IF_CURSED
    JR   Z, .not_cursed
    LD   A, HSTR_PIW_CURSED
    CALL msg_print_huff
    OR   A
    RET
.not_cursed:
    PUSH DE                         ; E = equip slot
    LD   A, E
    CALL _im_inv_to_fi_add
    CALL inv_add_item               ; copy to pack first
    POP  DE
    JR   C, .added
    LD   A, HSTR_UIS_PACK_FULL
    CALL msg_print_huff
    OR   A
    RET
.added:
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   (HL), EMPTY_SLOT
    LD   BC, TOTAL_INV_SLOTS
    LD   A, 7
.clr_off:
    ADD  HL, BC
    LD   (HL), 0
    DEC  A
    JR   NZ, .clr_off
    LD   A, E
    CP   EQUIP_LIGHT
    JR   NZ, .recalc_off
    ; Explicitly clear all light radius state when taking off EQUIP_LIGHT
    XOR  A
    LD   (player_data + PL_LIGHT_RAD), A
    LD   (zp_light_radius), A
    LD   (abi_light_rad), A
.recalc_off:
    CALL tramp_modal_recalc_equipment
    CALL status_mark_dirty
    CALL los_update_visibility
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   A, HSTR_PIW_TAKEOFF        ; "You take off the ~"
    CALL _im_print_the_item
    SCF
    RET

; ============================================================================
; +9: _im_drop — Drop 1 unit of pack item onto floor at player position
; ============================================================================
_im_drop:
    LD   A, PIW_FILTER_ALL
    LD   B, HSTR_IDR_PROMPT
    LD   HL, 0
    CALL _im_select_inv
    RET  NC

    LD   B, A                       ; B = pack slot
    PUSH BC
    CALL _im_inv_to_fi_add
    LD   A, (abi_player_x)
    LD   (fi_add_x), A
    LD   A, (abi_player_y)
    LD   (fi_add_y), A
    CALL floor_item_add
    POP  BC
    JR   C, .dropped
    LD   A, HSTR_IDR_FLOOR_FULL
    CALL msg_print_huff
    OR   A
    RET
.dropped:
    LD   A, B
    CALL inv_remove_item
    CALL status_mark_dirty
    LD   HL, zp_dirty_count
    INC  (HL)
    LD   A, HSTR_IDR_DROP
    CALL _im_print_prefixed_a
    SCF
    RET

; ============================================================================
; +12: _im_eat — Consume food / mushroom / mold / waybread & apply effects
; ============================================================================
_im_eat:
    ; Scan pack 0..MAX_INV_SLOTS-1 for first ICAT_FOOD (6502 parity: no prompt)
    LD   B, 0
.eat_scan:
    LD   E, B
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .eat_next
    LD   C, A                       ; C = item_id
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, C
    CALL item_get_category_a
    CP   ICAT_FOOD
    JR   Z, .eat_found
.eat_next:
    INC  B
    LD   A, B
    CP   MAX_INV_SLOTS
    JR   C, .eat_scan
    LD   A, HSTR_PIW_NO_FOOD
    CALL msg_print_huff
    OR   A
    RET

.eat_found:
    ; B = slot, C = item_id
    LD   A, (item_cur_page)
    OR   A
    JR   Z, .page0_food
    LD   DE, 500
    JR   .apply_eat
.page0_food:
    LD   A, C
    CP   ITEM_SLOT_RATION_OF_FOOD
    LD   DE, 1500
    JR   Z, .apply_eat
    CP   ITEM_SLOT_PIECE_OF_ELVISH_WAYBREAD_L6
    JR   Z, .waybread
    CP   ITEM_SLOT_PIECE_OF_ELVISH_WAYBREAD_L20
    JR   Z, .waybread
    LD   DE, 500
    JR   .apply_eat
.waybread:
    LD   DE, 4000

.apply_eat:
    PUSH BC                         ; [B=slot, C=item_id]
    PUSH DE                         ; [food value]
    LD   A, B
    CALL _im_inv_to_fi_add
    LD   A, 1
    LD   (fi_add_qty), A
    POP  DE
    POP  BC
    PUSH BC
    PUSH DE
    LD   A, B
    CALL inv_consume_one
    POP  DE

    ; Update PL_FOOD_LO/HI capped at 4000, then player_update_hunger_state
    LD   HL, (player_data + PL_FOOD_LO)
    ADD  HL, DE
    LD   DE, 4000
    OR   A
    PUSH HL
    SBC  HL, DE
    POP  HL
    JR   C, .food_ok
    LD   HL, 4000
.food_ok:
    LD   (player_data + PL_FOOD_LO), HL
    CALL player_update_hunger_state
    CALL status_mark_dirty

    ; Print "You eat the <name>. Delicious!" (or ". Yuck!" for Slime Mold on Page 0)
    LD   A, HSTR_PIW_EAT
    LD   DE, temp_str_buf
    CALL huff_decode_string
    CALL _im_trim_tilde
    XOR  A
    CALL _im_stage_itemdesc
    CALL item_format_staged
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    JR   NZ, .eat_delic
    LD   A, (fi_add_id)
    CP   ITEM_SLOT_FOOD_SLIME_MOLD
    LD   A, HSTR_PIW_YUCK
    JR   Z, .eat_suf
.eat_delic:
    LD   A, HSTR_PIW_DELICIOUS
.eat_suf:
    CALL huff_decode_string
    LD   HL, temp_str_buf
    CALL msg_print_str

    POP  BC                         ; B = slot, C = item_id
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    JR   NZ, .done_ok
    LD   A, C
    CALL tramp_items_eat_ext        ; applies mushroom 20..40 or waybread 43..44
.done_ok:
    SCF
    RET

; ============================================================================
; +15: _im_refuel — Refuel worn Brass Lantern with Flask of Oil (max 250)
; ============================================================================
_im_refuel:
    LD   A, (inv_item_id + EQUIP_LIGHT)
    CP   ITEM_SLOT_BRASS_LANTERN
    JR   Z, .is_lamp
    LD   A, HSTR_PIR_NOT_LAMP
    CALL msg_print_huff
    OR   A
    RET
.is_lamp:
    LD   A, (inv_ego + EQUIP_LIGHT)
    AND  ITEM_PAGE_BIT
    JR   Z, .lamp_ok
    LD   A, HSTR_PIR_NOT_LAMP
    CALL msg_print_huff
    OR   A
    RET
.lamp_ok:
    LD   B, 0
.oil_lp:
    LD   E, B
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   ITEM_SLOT_FLASK_OF_OIL
    JR   NZ, .oil_next
    LD   HL, inv_ego
    ADD  HL, DE
    BIT  6, (HL)
    JR   Z, .got_oil
.oil_next:
    INC  B
    LD   A, B
    CP   MAX_INV_SLOTS
    JR   C, .oil_lp
    LD   A, HSTR_PIR_NO_OIL
    CALL msg_print_huff
    OR   A
    RET
.got_oil:
    LD   E, B
    LD   D, 0
    LD   HL, inv_p1
    ADD  HL, DE
    LD   C, (HL)                    ; C = oil fuel before consume_one!
    PUSH BC
    LD   A, B
    CALL inv_consume_one
    POP  BC
    LD   A, (inv_p1 + EQUIP_LIGHT)
    ADD  A, C
    JR   C, .overflow
    CP   LANTERN_MAX_CHARGES + 1
    JR   C, .set_fuel
.overflow:
    LD   A, LANTERN_MAX_CHARGES
    LD   (inv_p1 + EQUIP_LIGHT), A
    LD   A, HSTR_PIR_OVERFLOW
    CALL msg_print_huff
    LD   A, HSTR_PIR_FULL
    JR   .ref_msg
.set_fuel:
    LD   (inv_p1 + EQUIP_LIGHT), A
    LD   A, HSTR_PIR_REFUELED
.ref_msg:
    CALL msg_print_huff
    LD   A, EQUIP_LIGHT
    CALL _im_sync_light_from_slot
    CALL los_update_visibility
    CALL status_mark_dirty
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

; ============================================================================
; +18: _im_fire — MON-018 Launcher Fire ('F')
; ============================================================================
_im_fire:
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   EMPTY_SLOT
    JR   Z, .no_wpn
    LD   B, A
    LD   A, (inv_ego + EQUIP_WEAPON)
    AND  ITEM_PAGE_BIT
    JR   NZ, .no_wpn
    LD   A, B
    CALL _im_launcher_msl           ; -> CF=1, A=msl(1..3), B=idx(0..5)
    JR   C, .have_launcher
.no_wpn:
    LD   A, HSTR_RF_NO_WEAPON
    CALL msg_print_huff
    OR   A
    RET

.have_launcher:
    LD   E, B                       ; E = launcher idx 0..5
    OR   0x80                       ; match ammo bit (0x81..0x83)
    LD   C, A                       ; C = required missile byte
    LD   D, 0                       ; D = pack slot 0..MAX_INV_SLOTS-1
.ammo_lp:
    LD   L, D
    LD   H, 0
    PUSH DE
    LD   DE, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    POP  DE
    CP   EMPTY_SLOT
    JR   Z, .ammo_next
    LD   L, D
    LD   H, 0
    PUSH DE
    LD   DE, inv_ego
    ADD  HL, DE
    LD   B, (HL)                    ; B = inv_ego[D]
    POP  DE
    LD   L, A                       ; L = item_id
    LD   A, B
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, L                       ; A = item_id
    CALL icat_select_id             ; preserves BC, DE, IX, IY
    JR   C, .ammo_next
    CALL icat_get_level_missile     ; B = missile_type (preserves C, DE, HL, IX, IY)
    LD   A, B
    CP   C
    JR   Z, .have_ammo
.ammo_next:
    INC  D
    LD   A, D
    CP   MAX_INV_SLOTS
    JR   C, .ammo_lp
    LD   A, HSTR_RF_NO_AMMO
    CALL msg_print_huff
    OR   A
    RET

.have_ammo:
    PUSH DE                         ; [D=ammo_slot, E=launcher_idx]
    CALL tramp_modal_direction_prompt
    JR   C, .have_dir
    POP  DE
    RET
.have_dir:
    POP  DE                         ; D=ammo_slot, E=launcher_idx
    ; Save ammo metadata into fi_add_* for ray / landing, then consume 1 ammo
    PUSH DE
    LD   A, D
    CALL _im_inv_to_fi_add
    LD   A, 1
    LD   (fi_add_qty), A
    POP  DE
    PUSH DE
    LD   A, D
    CALL inv_consume_one
    POP  DE

    ; Compute range into B, trace ray (max 20/25/30/35)
    LD   L, E
    LD   H, 0
    LD   BC, _im_l_range
    ADD  HL, BC
    LD   B, (HL)                    ; B = range
    LD   C, E                       ; C = launcher idx
    CALL _im_trace_missile          ; CF=1 hit mon (A=mon_slot, D=dist), CF=0 stopped (last_x/y in proj_x/y)
    JR   C, .hit_mon

    ; Missed / stopped by wall -> 9/10 drops at (proj_x, proj_y)
    CALL _im_drop_missile_9_10
    LD   A, HSTR_RF_FLIES
    CALL _im_print_fired_act
    SCF
    RET

.hit_mon:
    ; A = mon_slot, D = dist, C = launcher idx
    PUSH BC
    PUSH DE
    LD   (cmb_slot), A
    CALL monster_get_ptr
    LD   DE, MX_TYPE
    ADD  HL, DE
    LD   A, (HL)
    LD   (cmb_type), A
    POP  DE                         ; D = dist
    POP  BC                         ; C = launcher idx

    ; Bow To-Hit: BOW base + race + level*bow_lev + dex_adj + wpn_hit + ammo_hit - dist
    PUSH BC
    PUSH DE
    CALL _im_calc_bow_tohit         ; A = clamped u8 tohit (w/ dist in D)
    LD   E, A
    LD   A, (cmb_type)
    LD   L, A
    LD   H, 0
    LD   BC, cr_ac
    ADD  HL, BC
    LD   B, (HL)                    ; B = cr_ac
    LD   A, E                       ; A = tohit
    CALL _im_roll_d20_and_hit       ; CF=1 hit
    POP  DE
    POP  BC                         ; C = launcher idx
    JR   C, .shot_hit

    ; Miss monster -> drop 9/10 at last open tile (proj_x, proj_y)
    CALL _im_drop_missile_9_10
    LD   A, HSTR_RF_MISSES
    CALL _im_print_fired_vs_mon
    SCF
    RET

.shot_hit:
    ; Compute damage = max(0, dice + ammo_todam + launcher_todam) * mult
    PUSH BC
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (fi_add_id)
    CALL icat_select_id
    CALL icat_get_dmg               ; D=dice, E=sides
    LD   B, D
    LD   C, E
    CALL roll_dice_bc               ; L = sum, A = clamped
    LD   L, A
    LD   H, 0
    LD   A, (fi_add_to_dam)
    CALL _im_add_signed_hl
    LD   A, (inv_to_dam + EQUIP_WEAPON)
    CALL _im_add_signed_hl
    BIT  7, H
    JR   Z, .pos_base
    LD   HL, 0
.pos_base:
    POP  BC                         ; C = launcher idx
    LD   E, C
    LD   D, 0
    PUSH HL
    LD   HL, _im_l_mult
    ADD  HL, DE
    LD   A, (HL)                    ; A = mult
    POP  HL
    CALL mul_hl_a                   ; HL = base * mult
    LD   A, H
    OR   A
    LD   D, L
    JR   Z, .cap_base
    LD   D, 0xFF
.cap_base:
    ; Ammo ego multiplier vs creature flags/cdefense
    CALL _im_apply_ammo_ego         ; updates D
    ; Critical blow by ammo weight (6502 combat_critical_blow_weight parity)
    PUSH DE                         ; save D = dmg
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (fi_add_id)
    CALL icat_select_id
    CALL icat_get_weight            ; HL = weight
    LD   A, H
    OR   A
    LD   A, L
    JR   Z, .w_ok
    LD   A, 0xFF
.w_ok:
    POP  DE                         ; D = dmg
    CALL _im_crit_weight            ; D = final dmg

    ; Apply damage to monster (cmb_slot)
    CALL _im_damage_monster         ; CF=1 killed
    JR   NC, .shot_alive
    CALL _im_kill_cmb_mon
    SCF
    RET
.shot_alive:
    LD   A, (cmb_slot)
    CALL monster_wake
    LD   A, HSTR_RF_HITS
    CALL _im_print_fired_vs_mon
    SCF
    RET

; ============================================================================
; +21: _im_throw — Throw carried item ('T'), potion shatter + monster effect
; ============================================================================
_im_throw:
    LD   A, PIW_FILTER_ALL
    LD   B, HSTR_TW_PROMPT
    LD   HL, 0
    CALL _im_select_inv
    RET  NC

    LD   (piw_slot), A
    CALL _im_inv_to_fi_add
    LD   A, 1
    LD   (fi_add_qty), A
    CALL tramp_modal_direction_prompt
    RET  NC

    ; Consume 1 item from pack
    LD   A, (piw_slot)
    CALL inv_consume_one

    ; Throw range = min(10, max(1, (STR_CUR + 20) * 10 / wt))
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (fi_add_id)
    CALL icat_select_id
    CALL icat_get_weight            ; HL = weight
    LD   A, H
    OR   A
    LD   C, L
    JR   Z, .wt_u8
    LD   C, 0xFF
.wt_u8:
    LD   A, C
    OR   A
    JR   NZ, .div_rng
    LD   B, 10
    JR   .do_trace
.div_rng:
    LD   A, (player_data + PL_STR_CUR)
    LD   L, A
    LD   H, 0
    LD   DE, 20
    ADD  HL, DE
    LD   A, 10
    CALL mul_hl_a                   ; HL = (STR + 20) * 10
    CALL div_hl_c
    LD   A, H
    OR   A
    JR   NZ, .rng10
    LD   A, L
    OR   A
    JR   NZ, .chk10
    LD   A, 1
.chk10:
    CP   11
    JR   C, .rng_ok
.rng10:
    LD   A, 10
.rng_ok:
    LD   B, A

.do_trace:
    CALL _im_trace_missile          ; CF=1 hit mon (A=slot, D=dist), CF=0 missed
    JR   C, .th_mon

    ; Miss / wall / range -> potion prints shatters!, else flies away + 9/10 drop
    CALL _im_is_fi_potion
    LD   A, HSTR_TW_SHATTERS
    JR   C, .miss_dark_msg
    LD   A, HSTR_RF_FLIES
    CALL _im_print_ammo_act
    CALL _im_drop_missile_9_10
    SCF
    RET
.miss_dark_msg:
    CALL _im_print_ammo_act
    SCF
    RET

.th_mon:
    PUSH DE                         ; D = dist
    LD   (cmb_slot), A
    CALL monster_get_ptr
    LD   DE, MX_TYPE
    ADD  HL, DE
    LD   A, (HL)
    LD   (cmb_type), A
    POP  DE                         ; D = dist

    ; Throw tohit = min(255, combat_calc_tohit_common(BOW) * 3) / 4 - dist (6502 throw.s:338)
    PUSH DE
    LD   A, (fi_add_to_hit)
    CALL _im_calc_bow_tohit_base    ; A = u8 combat_calc_tohit_common(BOW)
    LD   L, A
    LD   H, 0
    LD   D, H
    LD   E, L
    ADD  HL, HL                     ; *2
    ADD  HL, DE                     ; *3
    LD   A, H
    OR   A
    LD   A, L
    JR   Z, .th_u8_cap
    LD   A, 255
.th_u8_cap:
    SRL  A
    SRL  A                          ; /4 -> *3/4 (max 63)
    POP  DE
    SUB  D                          ; - dist
    JR   NC, .th_u8
    XOR  A
.th_u8:
    LD   E, A
    LD   A, (cmb_type)
    LD   C, A
    LD   B, 0
    LD   HL, cr_ac
    ADD  HL, BC
    LD   B, (HL)
    LD   A, E
    CALL _im_roll_d20_and_hit
    JR   C, .th_hit

    ; Miss monster -> print "The <item> misses the <name>.", 9/10 drop if not potion
    LD   A, HSTR_RF_MISSES
    CALL _im_print_ammo_vs_mon
    CALL _im_is_fi_potion
    CALL NC, _im_drop_missile_9_10
    SCF
    RET

.th_hit:
    ; Damage = max(0, (dice==0 ? 1 : roll(dice)) + str_dmg_adj) + item_todam (min 0)
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (fi_add_id)
    CALL icat_select_id
    CALL icat_get_dmg               ; D=dice, E=sides
    LD   A, D
    OR   A
    JR   NZ, .roll_th_d
    LD   L, 1
    LD   H, 0
    JR   .add_str_td
.roll_th_d:
    LD   B, D
    LD   C, E
    CALL roll_dice_bc
.add_str_td:
    PUSH HL
    LD   A, (player_data + PL_STR_CUR)
    CALL player_str_damage_adj      ; A = signed str dmg adj
    POP  HL
    CALL _im_add_signed_hl
    BIT  7, H
    JR   Z, .th_s_pos
    LD   HL, 0
.th_s_pos:
    LD   A, (fi_add_to_dam)
    CALL _im_add_signed_hl
    BIT  7, H
    JR   Z, .th_d_pos
    LD   HL, 0
.th_d_pos:
    LD   A, H
    OR   A
    LD   D, L
    JR   Z, .th_crit
    LD   D, 0xFF
.th_crit:
    PUSH DE
    LD   A, (fi_add_id)
    CALL icat_get_weight
    LD   A, H
    OR   A
    LD   A, L
    JR   Z, .wt2
    LD   A, 0xFF
.wt2:
    POP  DE
    CALL _im_crit_weight            ; D = dmg
    CALL _im_damage_monster         ; CF=1 killed
    JR   C, .th_killed
    LD   A, (cmb_slot)
    CALL monster_wake
    LD   A, HSTR_RF_HITS
    CALL _im_print_ammo_vs_mon
    SCF
    RET
.th_killed:
    CALL _im_kill_cmb_mon
    SCF
    RET

; ============================================================================
; +24: _im_roll_enchant — Depth-scaled enchanting + all 55 ego types + chests
; Input: fi_add_id, item_cur_page set; Mutates fi_add_* metadata
; ============================================================================
_im_roll_enchant:
    LD   A, (item_cur_page)
    AND  ITEM_PAGE_BIT
    LD   (fi_add_ego), A
    LD   (item_cur_page), A
    LD   A, 1
    LD   (fi_add_qty), A
    XOR  A
    LD   HL, fi_add_qty_hi
    LD   B, 6                       ; qty_hi, p1, to_hit, to_dam, to_ac, flags
.zlp:
    LD   (HL), A
    INC  HL
    DJNZ .zlp

    LD   A, (fi_add_id)
    CALL icat_select_id
    RET  C
    CALL icat_get_effects           ; icat_flags_0..3, icat_p1_lo, icat_toac
    LD   A, (icat_flags_3)
    AND  ITR3_CURSED
    JR   Z, .no_base_c
    LD   A, IF_CURSED
    LD   (fi_add_flags), A
.no_base_c:
    LD   A, (icat_p1_lo)
    LD   (fi_add_p1), A

    LD   A, (fi_add_id)
    CALL item_get_category_a        ; A = ICAT_*
    LD   B, A                       ; B = category

    ; 1. Digging tools (ICAT_DIGGING = 0): keep icat_p1_lo, roll Orcish(1)/Dwarven(2) ego
    OR   A
    JR   NZ, .not_dig
    LD   A, (abi_player_dlvl)
    CP   10
    RET  C
    LD   A, 100
    CALL rng_range
    CP   10
    JR   NC, .dig25
    LD   A, (abi_player_dlvl)
    CP   20
    LD   A, 1
    JR   C, .dig_set
    INC  A
    JR   .dig_set
.dig25:
    CP   35
    RET  NC
    LD   A, 1
.dig_set:
    JP   _im_set_ego_a

.not_dig:
    ; 2. Lights (ICAT_LIGHT = 8)
    CP   ICAT_LIGHT
    JR   NZ, .not_light
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    RET  NZ
    LD   A, (fi_add_id)
    CP   ITEM_SLOT_WOODEN_TORCH
    JR   NZ, .chk_lantern
    LD   A, 67
    CALL rng_range
    ADD  A, 67
    LD   (fi_add_p1), A
    RET
.chk_lantern:
    CP   ITEM_SLOT_BRASS_LANTERN
    JR   Z, .roll_lantern
    CP   ITEM_SLOT_FLASK_OF_OIL
    RET  NZ
    LD   A, LANTERN_MAX_CHARGES
    LD   (fi_add_p1), A
    RET
.roll_lantern:
    LD   A, 125
    CALL rng_range
    ADD  A, 125
    LD   (fi_add_p1), A
    RET

.not_light:

.chk_wand:
    LD   A, B
    CP   ICAT_WAND
    JR   NZ, .chk_staff
    LD   A, (fi_add_id)
    CP   ITEM_SLOT_WAND_OF_LIGHT
    JR   NZ, .wand_std
    LD   A, 6
    CALL rng_range
    ADD  A, 10
    LD   (fi_add_p1), A
    RET
.wand_std:
    LD   A, 4
    CALL rng_range
    ADD  A, 5
    LD   (fi_add_p1), A
    RET

.chk_staff:
    CP   ICAT_STAFF
    JR   NZ, .chk_chest
    LD   A, (fi_add_id)
    CP   ITEM_SLOT_STAFF_OF_LIGHT
    JR   NZ, .st_tele
    LD   A, 6
    CALL rng_range
    ADD  A, 10
    LD   (fi_add_p1), A
    RET
.st_tele:
    CP   ITEM_SLOT_STAFF_OF_TELEPORTATION
    JR   NZ, .st_std
    LD   A, 3
    CALL rng_range
    ADD  A, 3
    LD   (fi_add_p1), A
    RET
.st_std:
    LD   A, 6
    CALL rng_range
    ADD  A, 3
    LD   (fi_add_p1), A
    RET

.chk_chest:
    CP   ICAT_CHEST
    JR   NZ, .chk_magic_equip
    LD   A, (fi_add_id)
    SUB  ITEM_SLOT_SMALL_WOODEN_CHEST
    CP   7
    RET  NC
    LD   E, A
    LD   D, 0
    LD   HL, _im_chest_lvl
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_to_hit), A         ; source level for locked chest loot
.chest_trap:
    LD   A, (abi_player_dlvl)
    OR   A
    JR   NZ, .ct_nz
    INC  A
.ct_nz:
    CALL rng_range
    CP   14
    JR   C, .cband
    LD   A, 13
.cband:
    LD   E, A
    LD   D, 0
    LD   HL, _im_chest_traps
    ADD  HL, DE
    LD   A, (HL)
    OR   CHEST_P1_LOCKED
    LD   (fi_add_p1), A
    RET

.chk_magic_equip:
    ; Only Rings, Amulets, Weapons, Armor/Shield/Helm/Gloves/Boots/Cloak keep/roll magic
    LD   A, B
    CP   ICAT_WEAPON
    JR   Z, .do_equip
    CP   ICAT_RING
    JR   Z, .do_equip
    CP   ICAT_AMULET
    JR   Z, .do_equip
    CP   ICAT_CLOAK
    JR   Z, .do_equip
    CP   ICAT_ARMOR
    JR   C, .non_equip
    CP   ICAT_BOOTS + 1
    JR   C, .do_equip
.non_equip:
    XOR  A
    LD   (fi_add_p1), A
    RET

.do_equip:
    ; Roll magic_chance = min(15 + dlvl, 70)
    LD   A, (abi_player_dlvl)
    ADD  A, 15
    CP   71
    JR   C, .mc_ok
    LD   A, 70
.mc_ok:
    LD   C, A                       ; C = magic_chance (15..70)
    LD   A, 100
    CALL rng_range
    CP   C
    JR   NC, .unenchanted

    ; Enchanted! Roll 4 independent bonuses into temp_str_buf[0..3] (hit, dam, ac, p1)
    LD   HL, temp_str_buf
    LD   E, 4
.r4_lp:
    LD   A, (abi_player_dlvl)
    SRL  A
    SRL  A
    INC  A
    CALL rng_range
    INC  A
    LD   (HL), A
    INC  HL
    DEC  E
    JR   NZ, .r4_lp

    ; Curse if ITR3_CURSED (already in fi_add_flags) OR 1-in-13 roll
    LD   A, (fi_add_flags)
    AND  IF_CURSED
    JR   NZ, .apply_curse
    LD   A, 13
    CALL rng_range
    OR   A
    JR   NZ, .not_c13
.apply_curse:
    LD   HL, fi_add_flags
    SET  0, (HL)                    ; IF_CURSED
    LD   HL, temp_str_buf
    LD   E, 4
.neg4_lp:
    LD   A, (HL)
    NEG
    LD   (HL), A
    INC  HL
    DEC  E
    JR   NZ, .neg4_lp

.not_c13:
    ; Reset fi_add_p1 so non-bonus items don't inherit catalog p1
    XOR  A
    LD   (fi_add_p1), A
    ; Branch by category B (temp_str_buf+0=hit, +1=dam, +2=ac, +3=p1)
    LD   A, B
    CP   ICAT_WEAPON
    JP   Z, _im_re_weapon
    CP   ICAT_RING
    JP   Z, _im_re_ring
    CP   ICAT_AMULET
    JP   Z, _im_re_amulet
    JP   _im_re_armour              ; Armor/Shield/Helm/Gloves/Boots/Cloak

.unenchanted:
    LD   A, (fi_add_flags)
    AND  IF_CURSED
    JR   NZ, .unench_c
    XOR  A
    LD   (fi_add_p1), A             ; unenchanted uncursed gets p1 = 0
    JR   .unench_ego
.unench_c:
    ; Intrinsically cursed keeps icat_p1_lo; Ring of Woe also gets -3 AC
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    JR   Z, .unench_ego
    LD   A, (fi_add_id)
    CP   ITEM_SLOT_RING_OF_WOE
    JR   NZ, .unench_ego
    LD   A, -3 & 0xFF
    LD   (fi_add_to_ac), A
.unench_ego:
    LD   A, B
    CP   ICAT_WEAPON
    RET  NZ
    JR   _im_roll_weapon_ego

_im_re_weapon:
    LD   A, (temp_str_buf + 0)
    LD   (fi_add_to_hit), A
    LD   A, (temp_str_buf + 1)
    LD   (fi_add_to_dam), A
_im_roll_weapon_ego:
    ; Ego check: launchers never get ego; cursed ammo skips ego; melee & uncursed ammo roll min(2*dlvl, 40)%
    CALL icat_get_level_missile     ; B = missile byte
    LD   A, B
    OR   A
    JR   Z, .roll_w_ego             ; 0 = melee
    BIT  7, A
    RET  Z                          ; 1..3 = launcher -> EGO_NONE
    LD   A, (fi_add_flags)
    AND  IF_CURSED
    RET  NZ                         ; cursed ammo -> EGO_NONE
.roll_w_ego:
    ; Ego weapon chance = min(2*dlvl, 40)%
    LD   A, (abi_player_dlvl)
    ADD  A, A
    CP   41
    JR   C, .we_ok
    LD   A, 40
.we_ok:
    LD   C, A
    LD   A, 100
    CALL rng_range
    CP   C
    RET  NC
    BIT  7, B
    JR   Z, .melee_ego
    ; Ammo ego: FIRE (43), SLAY_EVIL (44), DRAGON_SLAYING (45), SLAY_ANIMAL (55)
    LD   A, 4
    CALL rng_range
    LD   HL, _im_ammo_egos
    JP   _im_pick_table_a
.melee_ego:
    ; Ego 1..8 (SLAY_ANIMAL..SLAY_DRAGON); Holy Avenger gets 1..4 STR p1; Defender/HA +5/+3 AC lives in player_calc_combat
    LD   A, 8
    CALL rng_range
    INC  A                          ; 1..8
    PUSH AF
    CALL _im_set_ego_a
    POP  AF
    CP   EGO_HOLY_AVENGER
    RET  NZ
    LD   A, 4
    CALL rng_range
    INC  A
    LD   (fi_add_p1), A
    RET

_im_re_armour:
    ; B = category, C = magic_chance, temp_str_buf+2 = bonus_ac
    LD   A, (temp_str_buf + 2)
    LD   (fi_add_to_ac), A
    OR   A
    RET  Z
    ; Ego chance = trunc(magic_chance / 6)%
    LD   L, C
    LD   H, 0
    LD   C, 6
    PUSH BC
    CALL div_hl_c
    POP  BC
    LD   C, L
    LD   A, 100
    CALL rng_range
    CP   C
    RET  NC
    LD   A, (fi_add_to_ac)
    BIT  7, A
    JP   NZ, _im_re_cursed_armour
    ; Good armour ego by category B
    LD   A, B
    CP   ICAT_CLOAK
    JR   NZ, .not_cloak
    LD   A, 2
    CALL rng_range
    OR   A
    JR   NZ, .clk_stealth
    LD   A, 3
    CALL rng_range
    INC  A
    LD   HL, fi_add_to_ac
    ADD  A, (HL)
    LD   (HL), A
    LD   A, EGO_PROTECTION
    JP   _im_set_ego_a
.clk_stealth:
    LD   A, 3
    CALL rng_range
    INC  A
    LD   (fi_add_p1), A
    LD   A, EGO_STEALTH
    JP   _im_set_ego_a
.not_cloak:
    CP   ICAT_GLOVES
    JR   NZ, .not_gloves
    LD   A, 2
    CALL rng_range
    OR   A
    LD   A, EGO_FREE_ACTION
    JP   Z, _im_set_ego_a
    LD   A, 3
    CALL rng_range
    INC  A
    LD   (fi_add_to_hit), A
    LD   A, 3
    CALL rng_range
    INC  A
    LD   (fi_add_to_dam), A
    LD   A, EGO_SLAYING
    JP   _im_set_ego_a
.not_gloves:
    CP   ICAT_BOOTS
    JR   NZ, .not_boots
    LD   A, 3
    CALL rng_range
    ADD  A, EGO_SLOW_DESCENT
    PUSH AF
    CP   EGO_SPEED
    JR   NZ, .b_chk_st
    LD   A, 1
    LD   (fi_add_p1), A
    JR   .b_set
.b_chk_st:
    CP   EGO_STEALTH
    JR   NZ, .b_set
    LD   A, 3
    CALL rng_range
    INC  A
    LD   (fi_add_p1), A
.b_set:
    POP  AF
    JP   _im_set_ego_a
.not_boots:
    CP   ICAT_HELM
    JR   NZ, .body_or_shield
    ; Crowns (SILVER_CROWN..JEWEL_ENCRUSTED_CROWN on Page 0)
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    JR   NZ, .plain_helm
    LD   A, (fi_add_id)
    CP   ITEM_SLOT_SILVER_CROWN
    JR   C, .plain_helm
    CP   ITEM_SLOT_JEWEL_ENCRUSTED_CROWN + 1
    JR   NC, .plain_helm
    LD   A, 6
    CALL rng_range
    LD   HL, _im_crown_egos
    CALL _im_pick_table_a
    CP   EGO_REGENERATION
    RET  Z
    LD   A, 3
    CALL rng_range
    INC  A
    LD   (fi_add_p1), A
    RET
.plain_helm:
    LD   A, 3
    CALL rng_range
    PUSH AF                         ; 0=INT, 1=WIS, 2=INFRA_VISION
    ADD  A, EGO_INTELLIGENCE
    CALL _im_set_ego_a
    POP  AF
    CP   2
    LD   A, 2
    JR   C, .h_p1
    LD   A, 4
.h_p1:
    CALL rng_range
    INC  A
    LD   (fi_add_p1), A
    RET

.body_or_shield:
    LD   A, 9
    CALL rng_range
    LD   HL, _im_armour_egos
    CALL _im_pick_table_a
    CP   EGO_RESIST
    RET  NZ
    LD   HL, fi_add_to_ac
    LD   A, (HL)
    ADD  A, 5
    LD   (HL), A
    RET

_im_re_cursed_armour:
    LD   A, B
    CP   ICAT_HELM
    JR   Z, .rc_helm
    CP   ICAT_GLOVES
    JR   Z, .rc_gloves
    CP   ICAT_BOOTS
    JR   Z, .rc_boots
    CP   ICAT_CLOAK
    RET  NZ                         ; armor/shield cursed = EGO_NONE
    LD   A, 3
    CALL rng_range
    ADD  A, EGO_IRRITATION
    CP   EGO_VULNERABILITY
    JR   NZ, .rc_chk_env
    LD   HL, fi_add_to_ac
    LD   A, (HL)
    SUB  10
    LD   (HL), A
    LD   A, EGO_VULNERABILITY
    JR   .rc_mark
.rc_chk_env:
    CP   EGO_ENVELOPING
    JR   NZ, .rc_mark
    LD   HL, fi_add_to_hit
    LD   A, (HL)
    SUB  3
    LD   (HL), A
    LD   HL, fi_add_to_dam
    LD   A, (HL)
    SUB  3
    LD   (HL), A
    LD   A, EGO_ENVELOPING
    JR   .rc_mark
.rc_boots:
    LD   A, 3
    CALL rng_range
    ADD  A, EGO_SLOWNESS
    CP   EGO_SLOWNESS
    JR   NZ, .rc_mark
    LD   A, 0xFF
    LD   (fi_add_p1), A
    LD   A, EGO_SLOWNESS
    JR   .rc_mark
.rc_helm:
    LD   A, 6
    CALL rng_range
    ADD  A, EGO_STUPIDITY
    CP   EGO_BLINDNESS
    JR   C, .rc_neg_p1
    CP   EGO_UGLINESS
    JR   NZ, .rc_mark
    JR   .rc_neg_p1
.rc_gloves:
    LD   A, 2
    CALL rng_range
    ADD  A, EGO_CLUMSINESS
.rc_neg_p1:
    PUSH AF
    LD   A, 4
    CALL rng_range
    CPL                             ; -(rng(4)+1)
    LD   (fi_add_p1), A
    POP  AF
.rc_mark:
    LD   HL, fi_add_flags
    SET  0, (HL)
    JR   _im_set_ego_a

_im_pick_table_a:
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    LD   A, (HL)
_im_set_ego_a:
    LD   C, A
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    OR   C
    LD   (fi_add_ego), A
    LD   A, C
    RET

_im_re_ring:
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    RET  Z
    LD   A, (fi_add_id)
    CP   ITEM_SLOT_RING_OF_PROTECTION
    JR   Z, .r_ac
    CP   ITEM_SLOT_RING_OF_LORDLY_PROTECTION_FIRE
    JR   C, .not_lordly
    CP   ITEM_SLOT_RING_OF_LORDLY_PROTECTION_COLD + 1
    JR   NC, .not_lordly
.r_ac:
    LD   A, (temp_str_buf + 2)
    LD   (fi_add_to_ac), A
    RET
.not_lordly:
    CP   ITEM_SLOT_RING_OF_SLAYING
    JR   NZ, .not_r_slay
    LD   A, (temp_str_buf + 0)
    LD   (fi_add_to_hit), A
    LD   A, (temp_str_buf + 1)
    LD   (fi_add_to_dam), A
    RET
.not_r_slay:
    CP   ITEM_SLOT_RING_OF_SPEED
    JR   NZ, .not_r_spd
    LD   A, (fi_add_flags)
    AND  IF_CURSED
    LD   A, 1
    JR   Z, .rsp_ok
    LD   A, 0xFF
.rsp_ok:
    LD   (fi_add_p1), A
    RET
.not_r_spd:
    CP   ITEM_SLOT_RING_OF_INCREASE_DAMAGE
    JR   NZ, .not_r_dam
    LD   A, (temp_str_buf + 1)
    LD   (fi_add_to_dam), A
    RET
.not_r_dam:
    CP   ITEM_SLOT_RING_OF_INCREASE_TO_HIT
    JR   NZ, .not_r_hit
    LD   A, (temp_str_buf + 0)
    LD   (fi_add_to_hit), A
    RET
.not_r_hit:
    CP   ITEM_SLOT_RING_OF_WOE
    JR   NZ, .not_r_woe
    LD   A, (temp_str_buf + 2)
    LD   (fi_add_to_ac), A
    LD   A, (temp_str_buf + 3)
    LD   (fi_add_p1), A
    RET
.not_r_woe:
    LD   A, (icat_flags_2)
    AND  ITR2_SUST_STAT
    RET  NZ                         ; Sustain rings keep p1 = 0
_im_re_amulet:
    LD   A, (icat_flags_0)
    AND  ITR0_STR | ITR0_DEX | ITR0_CON | ITR0_INT | ITR0_WIS | ITR0_CHR | ITR0_SEARCH
    RET  Z
    LD   A, (temp_str_buf + 3)
    LD   (fi_add_p1), A
    RET

; ============================================================================
; Shared Helpers
; ============================================================================

_im_call_hl:
    JP   (HL)

_im_cpystr:
    LD   A, (HL)
    LD   (DE), A
    OR   A
    RET  Z
    INC  HL
    INC  DE
    JR   _im_cpystr

_im_trim_tilde:
    LD   HL, temp_str_buf
.find0:
    LD   A, (HL)
    OR   A
    JR   Z, .bk
    INC  HL
    JR   .find0
.bk:
    LD   D, H
    LD   E, L
    LD   BC, temp_str_buf
    OR   A
    SBC  HL, BC
    RET  Z
    DEC  DE
    LD   A, (DE)
    CP   '~'
    RET  Z
    INC  DE
    RET

_im_clear_prompt_row:
    CALL msg_clear
    JP   screen_flush

_im_redraw_play_screen:
    CALL screen_clear
    CALL viewport_center_on_player
    CALL viewport_render
    CALL status_mark_dirty
    CALL status_draw
    JP   screen_flush

; Copy inv[A] -> fi_add_* + item_cur_page
_im_inv_to_fi_add:
    LD   E, A
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_id), A
    LD   HL, inv_qty
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_qty), A
    XOR  A
    LD   (fi_add_qty_hi), A
    LD   HL, inv_p1
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_p1), A
    LD   HL, inv_to_hit
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_to_hit), A
    LD   HL, inv_to_dam
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_to_dam), A
    LD   HL, inv_to_ac
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_to_ac), A
    LD   HL, inv_flags
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_flags), A
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_ego), A
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    RET

; Copy floor[A] -> fi_add_*
_im_fi_to_fi_add:
    LD   E, A
    LD   D, 0
    LD   HL, fi_item_id
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_id), A
    LD   HL, fi_qty
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_qty), A
    LD   HL, fi_p1
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_p1), A
    LD   (fi_add_qty_hi), A
    LD   HL, fi_to_hit
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_to_hit), A
    LD   HL, fi_to_dam
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_to_dam), A
    LD   HL, fi_to_ac
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_to_ac), A
    LD   HL, fi_meta
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_flags), A
    LD   HL, fi_meta_hi
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_ego), A
    RET

; Store fi_add_* -> inv[A]
_im_fi_add_to_slot:
    LD   E, A
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (fi_add_id)
    LD   (HL), A
    LD   HL, inv_qty
    ADD  HL, DE
    LD   A, (fi_add_qty)
    LD   (HL), A
    LD   HL, inv_p1
    ADD  HL, DE
    LD   A, (fi_add_p1)
    LD   (HL), A
    LD   HL, inv_to_hit
    ADD  HL, DE
    LD   A, (fi_add_to_hit)
    LD   (HL), A
    LD   HL, inv_to_dam
    ADD  HL, DE
    LD   A, (fi_add_to_dam)
    LD   (HL), A
    LD   HL, inv_to_ac
    ADD  HL, DE
    LD   A, (fi_add_to_ac)
    LD   (HL), A
    LD   HL, inv_flags
    ADD  HL, DE
    LD   A, (fi_add_flags)
    LD   (HL), A
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (fi_add_ego)
    LD   (HL), A
    RET

; Print "<HSTR ending in 'a ~'> <formatted fi_add item>." (6502 item.s::item_append_desc parity)
_im_print_prefixed_a:
    LD   DE, temp_str_buf
    CALL huff_decode_string
    CALL _im_trim_tilde
_im_finish_item_msg:
    XOR  A                          ; qty=0 -> keep caller prefix article ("a "/"the ")
    CALL _im_stage_itemdesc
    LD   A, (itemdesc_flags)
    AND  IF_IDENTIFIED
    CALL _im_format_no_unid_light
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   HL, temp_str_buf
    JP   msg_print_str

_im_format_no_unid_light:
    LD   (itemdesc_flags), A        ; mask off IF_SENSED (6502 item_append_desc never prints "(magik)")
    OR   A
    JP   NZ, item_format_staged
    LD   A, (itemdesc_ego)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (itemdesc_item_id)
    CALL item_get_category_a
    CP   ICAT_LIGHT                 ; 6502 item_append_desc gates (N turns) on IF_IDENTIFIED
    JP   NZ, item_format_staged
    PUSH DE
    CALL item_format_staged         ; populates item_name_decode_buf with base light name
    POP  DE
    LD   HL, item_name_decode_buf
    JP   _im_cpystr

_im_print_the_item:
    LD   DE, temp_str_buf
    CALL huff_decode_string
    CALL _im_trim_tilde
    JR   _im_finish_item_msg

_im_stage_itemdesc:
    LD   (itemdesc_qty), A
    LD   A, (fi_add_id)
    LD   (itemdesc_item_id), A
    LD   A, (fi_add_p1)
    LD   (itemdesc_p1), A
    LD   A, (fi_add_to_hit)
    LD   (itemdesc_to_hit), A
    LD   A, (fi_add_to_dam)
    LD   (itemdesc_to_dam), A
    LD   A, (fi_add_to_ac)
    LD   (itemdesc_to_ac), A
    LD   A, (fi_add_flags)
    LD   (itemdesc_flags), A
    LD   A, (fi_add_ego)
    LD   (itemdesc_ego), A
    RET

_im_sync_light_from_slot:
    LD   E, A
    LD   D, 0
    LD   HL, inv_p1
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    JR   Z, .set_r
    LD   A, 1
.set_r:
    LD   (player_data + PL_LIGHT_RAD), A
    LD   (zp_light_radius), A
    LD   (abi_light_rad), A
    RET

; Launcher helper: Page 0 slot A -> CF=1, A=req_msl(1..3), B=idx(0..5); preserves DE
_im_launcher_msl:
    SUB  ITEM_SLOT_SHORT_BOW
    CP   6
    RET  NC
    LD   B, A
    PUSH DE
    LD   E, A
    LD   D, 0
    LD   HL, _im_l_msl
    ADD  HL, DE
    LD   A, (HL)
    POP  DE
    SCF
    RET

; Trace ray from player along (df_dir_idx) for up to B steps.
; Output: CF=1 hit mon (A=mon_slot, D=dist), CF=0 hit wall/range (last open proj_x/y)
_im_trace_missile:
    LD   A, (abi_player_x)
    LD   (proj_x), A
    LD   A, (abi_player_y)
    LD   (proj_y), A
    LD   A, (df_dir_idx)
    LD   E, A
    LD   D, 0
    LD   HL, dir_dx
    ADD  HL, DE
    LD   L, (HL)
    LD   H, 0
    PUSH HL
    LD   HL, dir_dy
    ADD  HL, DE
    LD   H, (HL)                    ; H = dy
    POP  DE
    LD   L, E                       ; L = dx
    ; H = dy, L = dx, B = max_range, D = dist
    LD   D, 0
.tr_lp:
    INC  D
    PUSH BC
    PUSH DE
    LD   A, (proj_x)
    ADD  A, L
    LD   C, A                       ; C = nx
    LD   A, (proj_y)
    ADD  A, H
    LD   B, A                       ; B = ny
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
    JR   Z, .tr_next
    CALL monster_find_at
    JR   NC, .tr_next
    POP  DE                         ; D = dist
    POP  BC                         ; C = preserved launcher idx
    SCF
    RET
.wall_pop:
    POP  AF
.wall:
    POP  DE
    POP  BC
    OR   A
    RET
.tr_next:
    POP  DE
    POP  BC
    DJNZ .tr_lp
    OR   A
    RET

_im_drop_missile_9_10:
    LD   A, 10
    CALL rng_range
    OR   A
    RET  Z                          ; 1/10 breaks
    LD   A, (proj_x)
    LD   (fi_add_x), A
    LD   A, (proj_y)
    LD   (fi_add_y), A
    LD   A, 1
    LD   (fi_add_qty), A
    CALL floor_item_add
    RET  NC
    LD   HL, zp_dirty_count
    INC  (HL)
    SCF
    RET

_im_is_fi_potion:
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    JR   NZ, .no
    LD   A, (fi_add_id)
    CALL item_get_category_a
    CP   ICAT_POTION
    JR   Z, .yes
.no:
    OR   A
    RET
.yes:
    SCF
    RET

_im_print_fired_act:
    PUSH AF
    XOR  A
    JR   _im_ammo_act_go
_im_print_ammo_act:
    PUSH AF
    LD   A, (fi_add_flags)
    AND  IF_IDENTIFIED
_im_ammo_act_go:
    PUSH AF
    LD   HL, _im_s_The
    LD   DE, temp_str_buf
    CALL _im_cpystr
    XOR  A
    CALL _im_stage_itemdesc
    POP  AF
    CALL _im_format_no_unid_light   ; "The <name>" (without "(N turns)" if unidentified light)
    POP  AF
    CALL huff_decode_string
    LD   HL, temp_str_buf
    JP   msg_print_str

_im_print_fired_vs_mon:
    PUSH AF
    XOR  A
    JR   _im_ammo_vs_go
_im_print_ammo_vs_mon:
    PUSH AF
    LD   A, (fi_add_flags)
    AND  IF_IDENTIFIED
_im_ammo_vs_go:
    PUSH AF
    LD   HL, _im_s_The
    LD   DE, temp_str_buf
    CALL _im_cpystr
    XOR  A
    CALL _im_stage_itemdesc
    POP  AF
    CALL _im_format_no_unid_light
    POP  AF
    CALL huff_decode_string         ; e.g. " misses" / " hits" (B = len)
    LD   L, B
    LD   H, 0
    ADD  HL, DE
    EX   DE, HL                     ; DE -> NUL after verb
    LD   HL, .s_the
    CALL _im_cpystr
    LD   A, (cmb_type)
    CALL monster_get_name_ptr
    CALL _im_cpystr
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   HL, temp_str_buf
    JP   msg_print_str
.s_the: DB " the ", 0

_im_add_signed_hl:
    LD   E, A
    ADD  A, A
    SBC  A, A
    LD   D, A
    ADD  HL, DE
    RET

_im_calc_bow_tohit:
    PUSH DE
    LD   A, (fi_add_to_hit)
    LD   HL, inv_to_hit + EQUIP_WEAPON
    ADD  A, (HL)
    CALL _im_calc_bow_tohit_base
    POP  DE
    SUB  D                          ; - dist
    RET  NC
    XOR  A
    RET

; _im_calc_bow_tohit_base — 6502 combat_calc_tohit_common(BTH_BOW=4, adj=1)
; Input: A = signed extra to-hit (ammo/item [+ launcher]); adds PL_TOHIT internally
; Output: A = u8 to-hit (0..255)
_im_calc_bow_tohit_base:
    LD   HL, player_data + PL_TOHIT
    ADD  A, (HL)
    PUSH AF                         ; save signed total_tohit
    LD   A, (player_data + PL_CLASS)
    LD   E, A
    LD   D, 0
    LD   A, CLASS_PROP_SIZE
    CALL mul_de_a
    LD   DE, class_properties + 4   ; BTH_BOW
    ADD  HL, DE
    LD   B, (HL)                    ; B = class bow
    LD   A, (player_data + PL_RACE)
    LD   E, A
    LD   D, 0
    LD   A, RACE_PROP_SIZE
    PUSH BC
    CALL mul_de_a
    POP  BC
    LD   DE, race_properties + 8    ; race BOW (signed)
    ADD  HL, DE
    LD   A, (HL)
    ADD  A, B
    BIT  7, (HL)
    JR   NZ, .race_neg
    JR   NC, .race_ok
    LD   A, 255
    JR   .race_ok
.race_neg:
    JR   C, .race_ok
    XOR  A
.race_ok:
    LD   B, A
    LD   A, (zp_eff_bless)
    OR   A
    JR   Z, .no_bl
    LD   A, B
    ADD  A, 5
    JR   NC, .bl_ok
    LD   A, 255
.bl_ok:
    LD   B, A
.no_bl:
    LD   A, (zp_eff_hero)
    OR   A
    JR   Z, .no_hr
    LD   A, B
    ADD  A, 12
    JR   NC, .hr_ok
    LD   A, 255
.hr_ok:
    LD   B, A
.no_hr:
    POP  AF                         ; signed total_tohit
    BIT  7, A
    JR   NZ, .neg_th
    LD   E, A
    LD   D, 0
    LD   A, 3
    PUSH BC
    CALL mul_de_a                   ; HL = 3 * total_tohit
    POP  BC
    LD   A, H
    OR   A
    JR   NZ, .sat255
    LD   A, B
    ADD  A, L
    JR   NC, .th_ok
.sat255:
    LD   A, 255
    JR   .th_ok
.neg_th:
    NEG
    LD   E, A
    LD   D, 0
    LD   A, 3
    PUSH BC
    CALL mul_de_a
    POP  BC
    LD   A, H
    OR   A
    JR   NZ, .sat0
    LD   A, B
    SUB  L
    JR   NC, .th_ok
.sat0:
    XOR  A
.th_ok:
    LD   B, A
    LD   A, (player_data + PL_CLASS)
    LD   E, A
    ADD  A, A
    ADD  A, A
    ADD  A, E
    LD   E, A
    LD   D, 0
    LD   HL, class_level_adj + 1
    ADD  HL, DE
    LD   E, (HL)
    LD   D, 0
    LD   A, (player_data + PL_LEVEL)
    PUSH BC
    CALL mul_de_a                   ; HL = level * bow_adj
    POP  BC
    LD   A, H
    OR   A
    JR   NZ, .ret255
    LD   A, B
    ADD  A, L
    RET  NC
.ret255:
    LD   A, 255
    RET

_im_roll_d20_and_hit:
    PUSH BC
    PUSH AF
    LD   A, 20
    CALL rng_range
    INC  A
    CP   1
    JR   Z, .miss
    CP   20
    JR   Z, .hit
    POP  AF
    POP  BC
    CP   2
    JR   C, .miss_np
    CALL rng_range
    CP   B
    CCF
    RET
.miss:
    POP  AF
    POP  BC
.miss_np:
    OR   A
    RET
.hit:
    POP  AF
    POP  BC
    SCF
    RET

_im_apply_ammo_ego:
    LD   A, (fi_add_ego)
    AND  EGO_ID_MASK
    OR   A
    RET  Z
    LD   C, A
    LD   A, (cmb_type)
    LD   E, A
    LD   A, C
    CP   EGO_AMMO_FIRE
    JR   NZ, .chk_evil
    PUSH DE
    LD   D, 0
    LD   HL, cr_cdefense
    ADD  HL, DE
    BIT  1, (HL)                    ; CD_FIRE
    POP  DE
    JR   Z, .fire_2d4
    ; 1.5x dmg vs CD_FIRE
    LD   A, D
    SRL  A
    ADD  A, D
    JR   NC, .setd
    LD   A, 0xFF
.setd:
    LD   D, A
.fire_2d4:
    PUSH DE
    LD   BC, 0x0204
    CALL roll_dice_bc               ; L = 2d4
    POP  DE
    LD   A, D
    ADD  A, L
    JR   NC, .f2d4_ok
    LD   A, 0xFF
.f2d4_ok:
    LD   D, A
    RET
.chk_evil:
    PUSH DE
    LD   D, 0
    LD   HL, cr_mflags
    ADD  HL, DE
    LD   B, (HL)
    POP  DE
    CP   EGO_AMMO_SLAY_EVIL
    JR   NZ, .chk_drag
    BIT  2, B                       ; CF_EVIL
    RET  Z
    LD   A, 3
    JR   .muld
.chk_drag:
    CP   EGO_DRAGON_SLAYING
    JR   NZ, .chk_anim
    BIT  4, B                       ; CF_DRAGON
    RET  Z
    LD   A, 5
    JR   .muld
.chk_anim:
    CP   EGO_AMMO_SLAY_ANIMAL
    RET  NZ
    BIT  3, B                       ; CF_ANIMAL
    RET  Z
    LD   A, 2
.muld:
    LD   E, D
    LD   D, 0
    CALL mul_de_a
    LD   A, H
    OR   A
    LD   D, L
    RET  Z
    LD   D, 0xFF
    RET

; Critical blow (6502 combat_critical_blow_weight): A = item weight, D = dmg -> D = final dmg
_im_crit_weight:
    PUSH DE                         ; [D = dmg]
    LD   E, A
    LD   D, 0
    PUSH DE                         ; [DE = weight]
    ; Add PL_LEVEL * class_level_adj[class*5 + 0] (BTH/lvl)
    LD   A, (player_data + PL_CLASS)
    LD   E, A
    ADD  A, A
    ADD  A, A
    ADD  A, E
    LD   E, A
    LD   D, 0
    LD   HL, class_level_adj
    ADD  HL, DE
    LD   E, (HL)
    LD   D, 0
    LD   A, (player_data + PL_LEVEL)
    CALL mul_de_a
    POP  DE                         ; DE = weight
    PUSH DE                         ; keep [weight] below [weight + lvl*bth]
    ADD  HL, DE                     ; HL = weight + lvl * BTH/lvl
    PUSH HL
    ; Compute signed melee total_tohit bonus (PL_TOHIT +/- unarmed/heavy penalty)
    LD   A, (player_data + PL_TOHIT)
    LD   B, A
    LD   A, (inv_item_id + EQUIP_WEAPON)
    CP   EMPTY_SLOT
    JR   Z, .mth_unarm
    LD   A, (wield_missile_type)
    OR   A
    JR   NZ, .mth_ok
    LD   HL, (wield_weight_lo)
    LD   A, H
    OR   L
    JR   Z, .mth_unarm
    PUSH HL                         ; weight
    LD   A, (player_data + PL_STR_CUR)
    LD   E, A
    LD   D, 0
    LD   A, 15
    PUSH BC
    CALL mul_de_a                   ; HL = STR * 15
    POP  BC
    POP  DE                         ; weight
    OR   A
    SBC  HL, DE
    JR   NC, .mth_ok
    ; negative penalty = HL (>= -128)
    LD   A, H
    CP   0xFF
    JR   NZ, .mth_cap
    LD   A, L
    BIT  7, A
    JR   NZ, .mth_add
.mth_cap:
    LD   A, 0x80
.mth_add:
    ADD  A, B
    JR   .mth_set
.mth_unarm:
    LD   A, B
    SUB  3
.mth_set:
    LD   B, A
.mth_ok:
    ; Add signed 5 * B to HL on stack
    LD   A, B
    BIT  7, A
    JR   NZ, .neg_th
    LD   E, A
    LD   D, 0
    LD   A, 5
    CALL mul_de_a
    POP  DE
    ADD  HL, DE
    JR   .got_ch
.neg_th:
    NEG
    LD   E, A
    LD   D, 0
    LD   A, 5
    CALL mul_de_a
    EX   DE, HL
    POP  HL
    OR   A
    SBC  HL, DE
    JR   NC, .got_ch
    LD   HL, 0
.got_ch:
    ; Roll [0..4999]
    PUSH HL
    LD   BC, 5000
    LD   DE, 0x1FFF
    CALL _im_rng16
    EX   DE, HL                     ; DE = rand(5000)
    POP  HL                         ; HL = chance
    OR   A
    SBC  HL, DE
    JR   Z, .no_crit
    JR   C, .no_crit
    ; tier_weight = weight + rng(650)
    LD   BC, 650
    LD   DE, 0x03FF
    CALL _im_rng16                  ; HL = rand(650)
    POP  DE                         ; weight
    ADD  HL, DE
    EX   DE, HL                     ; DE = tier_weight
    POP  BC                         ; B = orig dmg
    ; >=900: 5x+20, >=700: 4x+15, >=400: 3x+10, else 2x+5
    LD   C, 20
    LD   A, 5
    LD   HL, 899
    OR   A
    SBC  HL, DE
    JR   C, .cmul
    LD   C, 15
    LD   A, 4
    LD   HL, 699
    OR   A
    SBC  HL, DE
    JR   C, .cmul
    LD   C, 10
    LD   A, 3
    LD   HL, 399
    OR   A
    SBC  HL, DE
    JR   C, .cmul
    LD   C, 5
    LD   A, 2
.cmul:
    LD   E, B
    LD   D, 0
    CALL mul_de_a
    LD   B, 0
    ADD  HL, BC
    LD   A, H
    OR   A
    LD   D, L
    RET  Z
    LD   D, 0xFF
    RET
.no_crit:
    POP  DE                         ; discard weight
    POP  DE                         ; D = orig dmg
    RET

_im_rng16:
    CALL rng_next_u16
    LD   A, H
    AND  D
    LD   H, A
    LD   A, L
    AND  E
    LD   L, A
    OR   A
    PUSH HL
    SBC  HL, BC
    POP  HL
    JR   NC, _im_rng16
    RET

_im_move_old_equip_b:
    LD   HL, (fi_add_id)
    PUSH HL
    LD   HL, (fi_add_qty_hi)
    PUSH HL
    LD   HL, (fi_add_to_hit)
    PUSH HL
    LD   HL, (fi_add_to_ac)
    PUSH HL
    LD   A, (fi_add_ego)
    PUSH AF
    PUSH BC
    LD   A, B
    CALL _im_inv_to_fi_add
    CALL inv_add_item
    POP  BC
    JR   C, .mv_ok
    PUSH BC
    LD   A, (abi_player_x)
    LD   (fi_add_x), A
    LD   A, (abi_player_y)
    LD   (fi_add_y), A
    CALL floor_item_add
    POP  BC
    JR   C, .mv_ok
    LD   D, 0
    JR   .mv_rest
.mv_ok:
    LD   D, 1
.mv_rest:
    POP  AF
    LD   (fi_add_ego), A
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    POP  HL
    LD   (fi_add_to_ac), HL
    POP  HL
    LD   (fi_add_to_hit), HL
    POP  HL
    LD   (fi_add_qty_hi), HL
    POP  HL
    LD   (fi_add_id), HL
    RR   D                          ; CF = bit 0 of D (1=ok, 0=both full)
    RET

_im_damage_monster:
    LD   A, (cmb_slot)
    CALL monster_get_ptr
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
    OR   A
    RET
.dead:
    SCF
    RET

_im_kill_cmb_mon:
    LD   HL, _im_s_slay_pre
    LD   DE, temp_str_buf
    CALL _im_cpystr
    LD   A, (cmb_type)
    CALL monster_get_name_ptr
    CALL _im_cpystr
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   HL, temp_str_buf
    CALL msg_print_str
    LD   A, (cmb_slot)
    JP   tramp_modal_kill_monster

_im_l_msl:        DB 1, 1, 1, 2, 2, 3
_im_l_range:      DB 25, 30, 35, 25, 35, 20
_im_l_mult:       DB 2, 3, 4, 3, 4, 2

_im_chest_lvl:    DB 7, 15, 25, 35, 45, 50, 0
_im_chest_traps:
    DB CHEST_P1_TRAP_POISON, CHEST_P1_TRAP_POISON
    DB CHEST_P1_TRAP_PARA, CHEST_P1_TRAP_PARA, CHEST_P1_TRAP_PARA
    DB CHEST_P1_TRAP_EXPL, CHEST_P1_TRAP_EXPL
    DB CHEST_P1_TRAP_SUMMON, CHEST_P1_TRAP_SUMMON, CHEST_P1_TRAP_SUMMON
    DB (CHEST_P1_TRAP_STR | CHEST_P1_TRAP_POISON | CHEST_P1_TRAP_PARA)
    DB (CHEST_P1_TRAP_STR | CHEST_P1_TRAP_POISON | CHEST_P1_TRAP_PARA)
    DB (CHEST_P1_TRAP_STR | CHEST_P1_TRAP_POISON | CHEST_P1_TRAP_PARA)
    DB (CHEST_P1_TRAP_SUMMON | CHEST_P1_TRAP_EXPL)

_im_ammo_egos:
    DB EGO_AMMO_FIRE, EGO_AMMO_SLAY_EVIL, EGO_DRAGON_SLAYING, EGO_AMMO_SLAY_ANIMAL
_im_crown_egos:
    DB EGO_MIGHT, EGO_LORDLINESS, EGO_MAGI, EGO_BEAUTY, EGO_SEEING, EGO_REGENERATION
_im_armour_egos:
    DB EGO_RESIST, EGO_RESIST_ACID, EGO_RESIST_FIRE, EGO_RESIST_FIRE
    DB EGO_RESIST_COLD, EGO_RESIST_COLD, EGO_RESIST_LIGHT, EGO_RESIST_LIGHT, EGO_RESIST_LIGHT

_im_s_The:        DB "The ", 0
_im_s_slay_pre:   DB "You have slain the ", 0
_im_s_recharge:   DB "Recharge which item (a-v)?", 0
_im_s_which:      DB "Which item?", 0
_im_s_range_pre:  DB " (a-", 0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end
    SAVEBIN "ovl_item_mgt.ovl", ovl_start, ovl_end - ovl_start
