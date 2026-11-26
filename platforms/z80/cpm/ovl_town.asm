; ============================================================================
; ovl_town.asm — Town Stores UI, Pricing, Haggling & Restock Overlay
;                (OVL_TOWN = 2, DAT slot 1)
; ============================================================================
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0: JP ovl_town_store_enter  (A = store_id 0..6)
;   +3: JP ovl_town_restock_all  (A = 0 init all 0..111, A != 0 periodic restock)
; ============================================================================

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "item_ids_z80.inc"
    DEFINE ITEM_HOT_TABLES_CONSTS_ONLY 1
    INCLUDE "item_hot_tables_z80.inc"
    UNDEFINE ITEM_HOT_TABLES_CONSTS_ONLY
    DEFINE HUFF_CONSTS_ONLY 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_CONSTS_ONLY
    INCLUDE "main_exp.inc"

OVL_TOWN_HG_MIN_CONC    EQU 5
OVL_TOWN_HG_MAX_CONC    EQU 15
OVL_TOWN_SRO_CHOICES    EQU 5
OVL_TOWN_SRO_P1_START   EQU (ovl_town_temple_p1_start - ovl_town_choices)
OVL_TOWN_SRO_P1_END     EQU (ovl_town_temple_p1_end - ovl_town_choices)
OVL_TOWN_GEN_CNT        EQU (ovl_town_temple_choice - ovl_town_general_choice)
OVL_TOWN_TMP_CNT        EQU (ovl_town_alchemy_choice - ovl_town_temple_choice)
OVL_TOWN_ALC_CNT        EQU (ovl_town_choices_end - ovl_town_alchemy_choice)
OVL_TOWN_TORCH_CHARGES  EQU 134

    ORG  OVL_WINDOW_BASE

ovl_start:
    JP   ovl_town_store_enter   ; +0: OVL_WINDOW_BASE + 0
    JP   ovl_town_restock_all   ; +3: OVL_WINDOW_BASE + 3

; ============================================================================
; Transient Scalar Scratch (zero DS 128 buffers; compact fixed scalars)
; ============================================================================
ovl_town_store_idx:     DB 0
ovl_town_abs_slot:      DB 0
ovl_town_inv_slot:      DB 0
ovl_town_item_id:       DB 0
ovl_town_item_p1:       DB 0
ovl_town_item_hit:      DB 0
ovl_town_item_dam:      DB 0
ovl_town_item_ac:       DB 0
ovl_town_item_ego:      DB 0
ovl_town_item_flags:    DB 0
ovl_town_insults:       DB 0
ovl_town_status_ptr:    DW 0
ovl_town_status_attr:   DB COL_LGREEN

; 24-bit prices and haggle state (lo, mid, hi)
ovl_town_price:         DB 0, 0, 0
ovl_town_base24:        DB 0, 0, 0
ovl_town_hg_ask:        DB 0, 0, 0
ovl_town_hg_min:        DB 0, 0, 0
ovl_town_hg_last:       DB 0, 0, 0
ovl_town_hg_input:      DB 0, 0, 0
ovl_town_hg_num:        DB 0, 0, 0
ovl_town_hg_den:        DB 0, 0, 0
ovl_town_hg_pct:        DB 0
ovl_town_hg_round:      DB 0
ovl_town_hg_digits:     DB 0

; Restock scratch
ovl_town_srr_base:      DB 0
ovl_town_srr_first_emp: DB 0
ovl_town_srr_count:     DB 0
ovl_town_srr_retry:     DB 0
ovl_town_srr_one:       DB 0
ovl_town_srr_tmp0:      DB 0
ovl_town_srr_tmp1:      DB 0
ovl_town_srr_key:       DB 0, 0, 0, 0, 0, 0, 0 ; id, p1, hit, dam, meta, meta_hi, qty

; ============================================================================
; Vector +0: ovl_town_store_enter — Store UI Loop (A = store_id 0..6)
; Preserves: IX, IY
; ============================================================================
ovl_town_store_enter:
    CP   STORE_HOME
    RET  NC
    PUSH IX
    PUSH IY
    LD   (ovl_town_store_idx), A
    XOR  A
    LD   (ovl_town_insults), A
    LD   L, A
    LD   H, A
    LD   (ovl_town_status_ptr), HL

.loop:
    CALL ovl_town_draw_screen
    LD   HL, 0
    LD   (ovl_town_status_ptr), HL
    CALL screen_flush
    LD   B, STORE_MENU_ROW
    LD   C, 19
    CALL screen_set_cursor
.wait_key:
    CALL input_get_key
    CALL ovl_town_to_upper

    CP   'Q'
    JR   Z, .exit
    CP   KEY_SPACE
    JR   Z, .exit
    CP   KEY_ESC
    JR   Z, .exit

    CP   'B'
    JR   Z, .do_buy

    CP   'S'
    JR   Z, .do_sell

    JR   .wait_key

.do_buy:
    CALL ovl_town_buy
    JR   .loop

.do_sell:
    CALL ovl_town_sell
    JR   .loop

.exit:
    CALL screen_hard_clear
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    POP  IY
    POP  IX
    RET

; ============================================================================
; ovl_town_draw_screen — Render Store owner, store name, 16 slots, row 19
; ============================================================================
ovl_town_draw_screen:
    CALL screen_clear

    ; Row 0: Store name (COL_WHITE, col 1)
    LD   A, (ovl_town_store_idx)
    LD   HL, ovl_town_store_ptrs
    CALL ovl_town_tbl_ptr
    LD   B, 0
    LD   C, 1
    LD   E, COL_WHITE
    CALL screen_put_str

    ; Row 1: Owner name (COL_LGREY, col 2)
    LD   A, (ovl_town_store_idx)
    LD   HL, ovl_town_owner_ptrs
    CALL ovl_town_tbl_ptr
    LD   B, 1
    LD   C, 2
    LD   E, COL_LGREY
    CALL screen_put_str

    ; Row 2 separator
    LD   B, 2
    CALL ovl_town_draw_sep

    ; Rows 3..18: store inventory items (A)..P) at col 1; empty slots greyed
    CALL ovl_town_store_base_a  ; A = store_idx * 16
    LD   E, A                   ; E = abs slot
    LD   C, 0                   ; C = slot index 0..15
.item_loop:
    PUSH BC
    PUSH DE
    LD   A, 3
    ADD  A, C
    LD   B, A                   ; B = row 3..18

    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   NZ, .item_occ

    ; Empty slot: "A)" at col 1 in COL_DGREY
    LD   D, COL_DGREY
    XOR  A                      ; omit trailing space
    CALL ovl_town_put_slot_hdr_sp
    POP  DE
    JR   .item_next

.item_occ:
    ; "A) " at col 1 in COL_WHITE
    LD   D, COL_WHITE
    CALL ovl_town_put_slot_hdr

    ; Format description cleanly clipped before col 67 (62 chars max at col 4)
    POP  DE                     ; E = abs slot
    PUSH DE
    PUSH BC
    LD   A, E
    LD   DE, line_buf
    CALL item_format_store_slot ; HL = line_buf
    XOR  A
    LD   (line_buf + 62), A
    POP  BC
    PUSH BC
    LD   C, 4
    LD   E, COL_LGREY
    LD   HL, line_buf
    CALL screen_put_str
    POP  BC

    ; Leading space at col 67 + "<price> GP    " at col 68 in COL_YELLOW
    PUSH BC
    LD   C, 67
    LD   A, ' '
    LD   E, COL_YELLOW
    CALL screen_put_char
    POP  BC
    POP  DE
    PUSH DE
    PUSH BC
    LD   A, E
    CALL ovl_town_load_price_fields
    CALL ovl_town_calc_buy_price
    LD   HL, ovl_town_price
    CALL ovl_town_fmt_price_gp  ; temp_str_buf = "<price> GP    "
    POP  BC
    LD   C, 68
    LD   E, COL_YELLOW
    LD   HL, temp_str_buf
    CALL screen_put_str
    POP  DE

.item_next:
    POP  BC
    INC  E
    INC  C
    LD   A, C
    CP   STORE_MAX_ITEMS
    JR   C, .item_loop

    ; Row 19: "B)uy  S)ell  Q)uit" at col 1 COL_WHITE + "Gold: <gold>" at col 21 COL_YELLOW
    LD   B, STORE_MENU_ROW
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_town_str_menu
    CALL screen_put_str

    LD   B, STORE_MENU_ROW
    LD   C, 21
    LD   E, COL_YELLOW
    LD   HL, ovl_town_str_gold
    CALL screen_put_str

    LD   A, (player_data + PL_GOLD_0)
    LD   L, A
    LD   A, (player_data + PL_GOLD_1)
    LD   H, A
    LD   A, (player_data + PL_GOLD_2)
    LD   E, A
    LD   BC, temp_str_buf
    CALL status_fmt_u24
    LD   B, STORE_MENU_ROW
    LD   C, 27
    LD   E, COL_YELLOW
    CALL screen_put_str

    ; Pending row 22 status (e.g. "Bought!" / "Sold!")
    LD   HL, (ovl_town_status_ptr)
    LD   A, H
    OR   L
    RET  Z
    LD   B, 22
    LD   C, 1
    LD   A, (ovl_town_status_attr)
    LD   E, A
    JP   screen_put_str

; ============================================================================
; ovl_town_buy — Purchase flow
; ============================================================================
ovl_town_buy:
    CALL ovl_town_clear_msgs
    LD   B, 20
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_town_str_buy_which
    CALL screen_put_str
    CALL screen_flush
    LD   B, 20
    LD   C, 23
    CALL screen_set_cursor

.buy_wait:
    CALL input_get_key
    CALL ovl_town_is_cancel
    RET  Z
    CALL ovl_town_to_lower
    SUB  'a'
    RET  C
    CP   STORE_MAX_ITEMS
    RET  NC

    LD   C, A
    CALL ovl_town_store_base_a
    ADD  A, C
    LD   E, A
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    RET  Z
.buy_got:
    LD   A, E
    LD   (ovl_town_abs_slot), A

    ; Compute price
    LD   A, (ovl_town_abs_slot)
    CALL ovl_town_load_price_fields
    CALL ovl_town_calc_buy_price

    ; BM or price <= 10 GP skips haggling
    LD   A, (ovl_town_store_idx)
    CP   STORE_BM
    JR   Z, .yn_confirm
    LD   HL, ovl_town_price
    CALL ovl_town_is_price_gt10
    JR   C, .do_haggle_chk

.yn_confirm:
    LD   HL, ovl_town_str_price_hdr
    LD   DE, ovl_town_str_gp_buy
    LD   B, 21
    LD   A, 1
    CALL ovl_town_yn_prompt
    RET  NZ
    JR   .execute

.do_haggle_chk:
    CALL ovl_town_check_kicked
    JP   NZ, ovl_town_show_kicked
    CALL ovl_town_haggle_buy
    RET  NC

.execute:
    ; Check player gold >= ovl_town_price
    LD   HL, (ovl_town_price)
    LD   A, (ovl_town_price + 2)
    LD   E, A
    CALL player_cmp_gold_24
    JR   C, .can_afford

    LD   HL, ovl_town_str_no_afford
    LD   A, COL_RED
    JP   ovl_town_show_err_wait

.can_afford:
    ; Stage store slot (qty = 1) into fi_add_*
    LD   A, (ovl_town_abs_slot)
    LD   E, A
    LD   D, 0
    LD   BC, STORE_TOTAL_SLOTS
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_id), A
    LD   A, 1
    LD   (fi_add_qty), A
    ADD  HL, BC                 ; skip si_qty
    ADD  HL, BC                 ; si_p1
    LD   A, (HL)
    LD   (fi_add_p1), A
    ADD  HL, BC                 ; si_to_hit
    LD   A, (HL)
    LD   (fi_add_to_hit), A
    ADD  HL, BC                 ; si_to_dam
    LD   A, (HL)
    LD   (fi_add_to_dam), A
    ADD  HL, BC                 ; si_to_ac
    LD   A, (HL)
    LD   (fi_add_to_ac), A
    ADD  HL, BC                 ; si_meta
    LD   A, (HL)
    AND  ITEM_META_FLAGS_MASK
    LD   (fi_add_flags), A
    ADD  HL, BC                 ; si_meta_hi
    LD   A, (HL)
    LD   (fi_add_ego), A

    CALL inv_add_carried
    JR   C, .has_room

    ; A = HSTR_UIS_TOO_HEAVY or HSTR_UIS_PACK_FULL
    LD   DE, temp_str_buf
    CALL huff_decode_string
    LD   A, COL_RED
    JP   ovl_town_show_err_wait

.has_room:
    ; Reward good transaction by easing insult count
    LD   HL, ovl_town_insults
    LD   A, (HL)
    OR   A
    JR   Z, .no_ins_dec
    DEC  (HL)
.no_ins_dec:

    ; Subtract gold
    LD   HL, (ovl_town_price)
    LD   A, (ovl_town_price + 2)
    LD   E, A
    CALL player_sub_gold_24

    ; Decrement si_qty (preserve empty hole like 6502 ui_store.s)
    LD   A, (ovl_town_abs_slot)
    LD   E, A
    LD   D, 0
    LD   HL, si_qty
    ADD  HL, DE
    DEC  (HL)
    JR   NZ, .done_buy
    LD   HL, si_item_id
    ADD  HL, DE
    LD   (HL), FI_EMPTY

.done_buy:
    LD   HL, ovl_town_str_bought
    LD   (ovl_town_status_ptr), HL
    LD   A, COL_LGREEN
    LD   (ovl_town_status_attr), A
    RET

; ============================================================================
; ovl_town_sell — List carried pack A)..V) and sell 1 item to store
; ============================================================================
ovl_town_sell:
    CALL screen_clear
    LD   B, 0
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_town_str_sell_title
    CALL screen_put_str
    LD   B, 1
    CALL ovl_town_draw_sep

    ; Compact occupied pack slots 0..21 starting at row 2 col 1
    LD   A, 2
    LD   (ovl_town_srr_tmp0), A ; display row
    LD   C, 0
.inv_loop:
    LD   E, C
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .inv_next

    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CALL item_get_category_a
    PUSH BC
    LD   B, A
    LD   A, (ovl_town_store_idx)
    LD   D, A
    LD   A, B
    LD   B, D
    CALL ovl_town_check_cat
    POP  BC
    LD   A, COL_DGREY
    JR   NC, .col_set
    LD   A, COL_LGREY
.col_set:
    LD   D, A                   ; D = row color
    LD   A, (ovl_town_srr_tmp0)
    LD   B, A                   ; B = compact display row
    INC  A
    LD   (ovl_town_srr_tmp0), A
    CALL ovl_town_put_slot_hdr

    PUSH BC
    PUSH DE
    LD   A, C
    LD   DE, line_buf
    CALL item_format_inv_slot
    XOR  A
    LD   (line_buf + 75), A
    POP  DE
    POP  BC
    PUSH BC
    LD   E, D
    LD   C, 4
    LD   HL, line_buf
    CALL screen_put_str
    POP  BC

.inv_next:
    INC  C
    LD   A, C
    CP   MAX_INV_SLOTS
    JR   C, .inv_loop

    LD   B, 23
    CALL screen_clear_row
    LD   B, 23
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_town_str_sell_which
    CALL screen_put_str
    CALL screen_flush
    LD   B, 23
    LD   C, 24
    CALL screen_set_cursor

.sell_wait:
    CALL input_get_key
    CALL ovl_town_is_cancel
    RET  Z
    CALL ovl_town_to_lower
    SUB  'a'
    RET  C
    CP   MAX_INV_SLOTS
    RET  NC

    LD   E, A
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    RET  Z
.sell_got:
    LD   (ovl_town_item_id), A
    LD   A, E
    LD   (ovl_town_inv_slot), A

    ; Load inventory item attributes for category & pricing checks
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_town_item_ego), A
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A

    LD   A, (ovl_town_item_id)
    CALL item_get_category_a
    LD   HL, ovl_town_store_idx
    LD   B, (HL)
    CALL ovl_town_check_cat
    JR   C, .cat_ok

    LD   HL, ovl_town_str_no_buy
    LD   A, COL_RED
    JP   ovl_town_show_err_wait

.cat_ok:
    LD   A, (ovl_town_inv_slot)
    LD   E, A
    LD   D, 0
    LD   HL, inv_flags
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_town_item_flags), A
    AND  IF_CURSED
    JR   Z, .not_cursed

    LD   HL, ovl_town_str_cursed
    LD   A, COL_RED
    JP   ovl_town_show_err_wait

.not_cursed:
    LD   HL, inv_p1
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_town_item_p1), A
    LD   HL, inv_to_hit
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_town_item_hit), A
    LD   HL, inv_to_dam
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_town_item_dam), A
    LD   HL, inv_to_ac
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_town_item_ac), A

    CALL ovl_town_calc_sell_price
    LD   HL, ovl_town_price
    CALL ovl_town_is_zero_24
    JR   NZ, .has_val

    LD   HL, ovl_town_str_worthless
    LD   A, COL_RED
    JP   ovl_town_show_err_wait

.has_val:
    LD   A, (ovl_town_store_idx)
    CP   STORE_BM
    JR   Z, .sell_yn
    LD   HL, ovl_town_price
    CALL ovl_town_is_price_gt10
    JR   C, .sell_haggle_chk

.sell_yn:
    LD   HL, ovl_town_str_offer_hdr
    LD   DE, ovl_town_str_gp_sell
    LD   B, 22
    XOR  A                      ; do not clear rows 20..23
    CALL ovl_town_yn_prompt
    RET  NZ
    JR   .sell_exec

.sell_haggle_chk:
    CALL ovl_town_check_kicked
    JP   NZ, ovl_town_show_kicked
    CALL ovl_town_haggle_sell
    RET  NC

.sell_exec:
    CALL ovl_town_find_empty_slot
    JR   C, .sell_write_slot

    LD   HL, ovl_town_str_store_full
    LD   A, COL_RED
    JP   ovl_town_show_err_wait

.sell_write_slot:
    ; A = empty abs slot
    LD   B, A
    LD   A, (ovl_town_inv_slot)
    LD   D, 1
    CALL si_copy_from_inv

.sell_commit:
    LD   HL, ovl_town_insults
    LD   A, (HL)
    OR   A
    JR   Z, .s_no_dec
    DEC  (HL)
.s_no_dec:

    LD   A, (ovl_town_inv_slot)
    CALL inv_consume_one

    LD   HL, (ovl_town_price)
    LD   A, (ovl_town_price + 2)
    LD   E, A
    CALL player_add_gold_24

    CALL ovl_town_clear_msgs
    LD   B, 23
    LD   C, 1
    LD   E, COL_LGREEN
    LD   HL, ovl_town_str_sold
    CALL screen_put_str
    CALL screen_flush
    JP   input_get_key

; ============================================================================
; Pricing Engine (faithful to core/6502/store.s, overflow-safe 24-bit)
; Uses: ovl_town_item_id, _ego, _p1, _hit, _dam, _ac
; Output: ovl_town_price (3 bytes LE)
; ============================================================================
ovl_town_load_price_fields:
    LD   E, A
    LD   D, 0
    LD   BC, STORE_TOTAL_SLOTS
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_town_item_id), A
    ADD  HL, BC                 ; skip qty
    ADD  HL, BC                 ; p1
    LD   A, (HL)
    LD   (ovl_town_item_p1), A
    ADD  HL, BC                 ; hit
    LD   A, (HL)
    LD   (ovl_town_item_hit), A
    ADD  HL, BC                 ; dam
    LD   A, (HL)
    LD   (ovl_town_item_dam), A
    ADD  HL, BC                 ; ac
    LD   A, (HL)
    LD   (ovl_town_item_ac), A
    ADD  HL, BC                 ; meta
    LD   A, (HL)
    LD   (ovl_town_item_flags), A
    ADD  HL, BC                 ; meta_hi
    LD   A, (HL)
    LD   (ovl_town_item_ego), A
    RET

ovl_town_load_base_tool:
    LD   A, (ovl_town_item_ego)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (ovl_town_item_id)
    CALL icat_select_id
    CALL icat_get_cost          ; HL = base cost (16-bit)
    LD   A, (ovl_town_item_ego)
    AND  EGO_ID_MASK
    JR   Z, .base_zero_e
    LD   B, A
    LD   A, (ovl_town_item_id)
    CALL item_get_category_a
    CP   ICAT_DIGGING
    JR   NZ, .base_zero_e
    LD   A, B
    CP   2
    LD   A, 5
    JR   NZ, .mul_tool
    LD   A, 15
.mul_tool:
    CALL ovl_town_mul16x8       ; HL = low 16 bits of base * mult (6502 store.s)
.base_zero_e:
    LD   E, 0                   ; 16-bit base cost matching 6502 store.s
.store_base:
    LD   (ovl_town_base24), HL
    LD   A, E
    LD   (ovl_town_base24 + 2), A
    RET

ovl_town_calc_buy_price:
    CALL ovl_town_load_base_tool
    LD   A, (ovl_town_store_idx)
    CP   STORE_BM
    JR   Z, .bm_buy
    LD   C, 0                   ; buy table
    CALL ovl_town_apply_chr_pct
    JR   .min1_p1
.bm_buy:
    ; base * 3 truncated to 16 bits (matching 6502 store.s calc_bm_buy_price)
    LD   A, 3
    CALL ovl_town_mul24x8
    XOR  A
    LD   (ovl_town_price + 2), A
.min1_p1:
    LD   HL, ovl_town_price
    CALL ovl_town_is_zero_24
    JR   NZ, ovl_town_add_p1_bonus
    LD   A, 1
    LD   (ovl_town_price), A
    JR   ovl_town_add_p1_bonus

ovl_town_calc_buy_min_price:
    CALL ovl_town_load_base_tool
    LD   HL, ovl_town_base24
    LD   DE, ovl_town_price
    LD   BC, 3
    LDIR
    JR   ovl_town_add_p1_bonus

ovl_town_calc_sell_price:
    CALL ovl_town_load_base_tool
    LD   A, (ovl_town_store_idx)
    CP   STORE_BM
    JR   Z, .bm_sell
    LD   C, 1                   ; sell table
    CALL ovl_town_apply_chr_pct
    JR   ovl_town_add_p1_bonus
.bm_sell:
    LD   HL, (ovl_town_base24)
    LD   A, (ovl_town_base24 + 2)
    LD   E, A
    LD   C, 10
    CALL ovl_town_div24x8
    LD   (ovl_town_price), HL
    LD   A, E
    LD   (ovl_town_price + 2), A
    ; Fall through to p1 bonus

ovl_town_add_p1_bonus:
    LD   A, (ovl_town_item_id)
    CALL item_get_category_a
    CP   ICAT_CLOAK
    JR   Z, .equip
    CP   ICAT_WEAPON
    JR   C, .chk_ring
    CP   ICAT_BOOTS + 1
    JR   C, .equip
.chk_ring:
    CP   ICAT_RING
    JR   Z, .ring
    CP   ICAT_AMULET
    JR   Z, .ring
    CP   ICAT_WAND
    RET  C
    CP   ICAT_STAFF + 1
    RET  NC
    ; Charges: +10 GP per charge (unsigned p1)
    LD   A, (ovl_town_item_p1)
    OR   A
    RET  Z
    LD   C, 10
    JR   .add_a_mul_c

.ring:
    LD   A, (ovl_town_item_p1)
    CALL .add_signed_100
.equip:
    LD   A, (ovl_town_item_hit)
    CALL .add_signed_100
    LD   A, (ovl_town_item_dam)
    CALL .add_signed_100
    LD   A, (ovl_town_item_ac)

.add_signed_100:
    OR   A
    RET  Z
    BIT  7, A
    RET  NZ
    LD   C, 100
.add_a_mul_c:
    LD   L, A
    LD   H, 0
    LD   A, C
    CALL mul_hl_a               ; HL = val * (10 or 100) <= 12,700
    LD   A, (ovl_town_price)
    ADD  A, L
    LD   (ovl_town_price), A
    LD   A, (ovl_town_price + 1)
    ADC  A, H
    LD   (ovl_town_price + 1), A
    RET  NC
    LD   HL, ovl_town_price + 2
    INC  (HL)
    RET

; C = 0 (buy), 1 (sell); reads ovl_town_base24 -> writes ovl_town_price
ovl_town_apply_chr_pct:
    LD   A, (player_data + PL_CHR_CUR)
    CP   3
    JR   NC, .ge3
    XOR  A
    JR   .idx_ok
.ge3:
    CP   18
    JR   C, .sub3
    LD   A, 15
    JR   .idx_ok
.sub3:
    SUB  3
.idx_ok:
    LD   E, A
    LD   D, 0
    LD   HL, ovl_town_chr_buy_adj
    LD   A, C
    OR   A
    JR   Z, .get_pct
    LD   HL, ovl_town_chr_sell_adj
.get_pct:
    ADD  HL, DE
    LD   A, (HL)                ; pct
    CALL ovl_town_mul24x8       ; ovl_town_price = base24 * pct (up to 32-bit, capped)
    LD   HL, (ovl_town_price)
    LD   A, (ovl_town_price + 2)
    LD   E, A
    LD   C, 100
    CALL ovl_town_div24x8
    LD   (ovl_town_price), HL
    LD   A, E
    LD   (ovl_town_price + 2), A
    RET

; ============================================================================
; Haggling Engine (buy + sell, faithful to core/6502/ui_store.s)
; ============================================================================
ovl_town_haggle_buy:
    LD   HL, ovl_town_price
    LD   DE, ovl_town_hg_ask
    CALL ovl_town_copy24
    CALL ovl_town_calc_buy_min_price
    LD   HL, ovl_town_price
    LD   DE, ovl_town_hg_min
    CALL ovl_town_copy24
    ; last = max(1, min / 2)
    LD   HL, ovl_town_hg_min
    LD   DE, ovl_town_hg_last
    CALL ovl_town_copy24
    LD   HL, ovl_town_hg_last
    CALL ovl_town_shr24
    LD   HL, ovl_town_hg_last
    CALL ovl_town_is_zero_24
    JR   NZ, .hb_go
    INC  (HL)
.hb_go:
    XOR  A
    LD   (ovl_town_hg_round), A

.hb_loop:
    LD   A, (ovl_town_hg_round)
    OR   A
    JR   NZ, .hb_final
    LD   HL, ovl_town_str_asks
    LD   DE, ovl_town_str_your_offer
    CALL ovl_town_hg_show_prompt
    JR   .hb_read
.hb_final:
    LD   HL, ovl_town_str_final
    LD   DE, ovl_town_str_your_offer
    CALL ovl_town_hg_show_prompt

.hb_read:
    CALL ovl_town_read_number
    RET  NC                     ; cancelled

    ; input < last -> insult
    LD   HL, ovl_town_hg_input
    LD   DE, ovl_town_hg_last
    CALL ovl_town_cmp24
    JP   C, .hb_insult

    ; input >= ask: if == ask accept, if > ask retry
    LD   HL, ovl_town_hg_input
    LD   DE, ovl_town_hg_ask
    CALL ovl_town_cmp24
    JR   C, .hb_counter
    JP   Z, .hb_accept_in
    CALL ovl_town_hg_retry
    JP   .hb_loop

.hb_counter:
    ; num = input - last, den = ask - last
    LD   HL, ovl_town_hg_input
    LD   DE, ovl_town_hg_last
    LD   BC, ovl_town_hg_num
    CALL ovl_town_sub24
    LD   HL, ovl_town_hg_ask
    LD   DE, ovl_town_hg_last
    LD   BC, ovl_town_hg_den
    CALL ovl_town_sub24
    CALL ovl_town_concession_pct
    JP   NC, .hb_insult

    ; step = ((ask - input) * pct) / 100 + 1
    LD   HL, ovl_town_hg_ask
    LD   DE, ovl_town_hg_input
    LD   BC, ovl_town_hg_num
    CALL ovl_town_sub24
    CALL ovl_town_pct_step      ; ovl_town_hg_num = step

    ; ask -= step (guard underflow below min)
    LD   HL, ovl_town_hg_ask
    LD   DE, ovl_town_hg_num
    CALL ovl_town_cmp24
    JR   C, .hb_clamp
    LD   HL, ovl_town_hg_ask
    LD   DE, ovl_town_hg_num
    LD   BC, ovl_town_hg_ask
    CALL ovl_town_sub24

    LD   HL, ovl_town_hg_ask
    LD   DE, ovl_town_hg_min
    CALL ovl_town_cmp24
    JR   NC, .hb_post
.hb_clamp:
    LD   HL, ovl_town_hg_min
    LD   DE, ovl_town_hg_ask
    CALL ovl_town_copy24
    LD   HL, ovl_town_hg_round
    INC  (HL)
    LD   A, (HL)
    CP   4
    JR   C, .hb_next_round
    JR   .hb_kick_inc

.hb_post:
    ; If store ask dropped <= player input, accept player input
    LD   HL, ovl_town_hg_input
    LD   DE, ovl_town_hg_ask
    CALL ovl_town_cmp24
    JR   NC, .hb_accept_in

.hb_next_round:
    LD   HL, ovl_town_hg_input
    LD   DE, ovl_town_hg_last
    CALL ovl_town_copy24
    CALL ovl_town_hg_show_counter
    JP   .hb_loop

.hb_accept_in:
    LD   HL, ovl_town_hg_input
    LD   DE, ovl_town_price
    CALL ovl_town_copy24
    CALL ovl_town_show_agreed
    SCF
    RET

.hb_kick_inc:
    CALL ovl_town_inc_insults
    JR   C, .hb_kick
    OR   A
    RET

.hb_insult:
    CALL ovl_town_inc_insults
    JR   C, .hb_kick
    CALL ovl_town_show_insult
    JP   .hb_loop

.hb_kick:
    JP   ovl_town_do_kick

ovl_town_haggle_sell:
    LD   HL, ovl_town_price
    LD   DE, ovl_town_hg_min    ; max store will pay
    CALL ovl_town_copy24
    ; start ask = max(1, max / 2)
    LD   HL, ovl_town_hg_min
    LD   DE, ovl_town_hg_ask
    CALL ovl_town_copy24
    LD   HL, ovl_town_hg_ask
    CALL ovl_town_shr24
    LD   HL, ovl_town_hg_ask
    CALL ovl_town_is_zero_24
    JR   NZ, .hs_last
    INC  (HL)
.hs_last:
    ; last = min(0xFFFFFF, max * 2)
    LD   HL, ovl_town_hg_min
    LD   DE, ovl_town_hg_last
    CALL ovl_town_copy24
    LD   HL, ovl_town_hg_last
    CALL ovl_town_shl24
    XOR  A
    LD   (ovl_town_hg_round), A

.hs_loop:
    LD   A, (ovl_town_hg_round)
    OR   A
    JR   NZ, .hs_final
    LD   HL, ovl_town_str_offers
    LD   DE, ovl_town_str_your_price
    CALL ovl_town_hg_show_prompt
    JR   .hs_read
.hs_final:
    LD   HL, ovl_town_str_final
    LD   DE, ovl_town_str_your_price
    CALL ovl_town_hg_show_prompt

.hs_read:
    CALL ovl_town_read_number
    RET  NC

    ; input > last -> insult
    LD   HL, ovl_town_hg_last
    LD   DE, ovl_town_hg_input
    CALL ovl_town_cmp24
    JP   C, .hs_insult

    ; input <= ask: if == accept, if < retry
    LD   HL, ovl_town_hg_ask
    LD   DE, ovl_town_hg_input
    CALL ovl_town_cmp24
    JR   C, .hs_counter
    JR   Z, .hs_accept_in
    CALL ovl_town_hg_retry
    JP   .hs_loop

.hs_counter:
    ; num = last - input, den = last - ask
    LD   HL, ovl_town_hg_last
    LD   DE, ovl_town_hg_input
    LD   BC, ovl_town_hg_num
    CALL ovl_town_sub24
    LD   HL, ovl_town_hg_last
    LD   DE, ovl_town_hg_ask
    LD   BC, ovl_town_hg_den
    CALL ovl_town_sub24
    CALL ovl_town_concession_pct
    JP   NC, .hs_insult

    ; step = ((input - ask) * pct) / 100 + 1
    LD   HL, ovl_town_hg_input
    LD   DE, ovl_town_hg_ask
    LD   BC, ovl_town_hg_num
    CALL ovl_town_sub24
    CALL ovl_town_pct_step

    ; ask += step
    LD   HL, ovl_town_hg_ask
    LD   DE, ovl_town_hg_num
    LD   BC, ovl_town_hg_ask
    CALL ovl_town_add24

    ; Clamp at max (min)
    LD   HL, ovl_town_hg_min
    LD   DE, ovl_town_hg_ask
    CALL ovl_town_cmp24
    JR   NC, .hs_post
    LD   HL, ovl_town_hg_min
    LD   DE, ovl_town_hg_ask
    CALL ovl_town_copy24
    LD   HL, ovl_town_hg_round
    INC  (HL)
    LD   A, (HL)
    CP   4
    JR   C, .hs_next
    JR   .hs_kick_inc

.hs_post:
    ; If ask >= input, accept input
    LD   HL, ovl_town_hg_ask
    LD   DE, ovl_town_hg_input
    CALL ovl_town_cmp24
    JR   NC, .hs_accept_in

.hs_next:
    LD   HL, ovl_town_hg_input
    LD   DE, ovl_town_hg_last
    CALL ovl_town_copy24
    CALL ovl_town_hg_show_counter
    JP   .hs_loop

.hs_accept_in:
    LD   HL, ovl_town_hg_input
    LD   DE, ovl_town_price
    CALL ovl_town_copy24
    CALL ovl_town_show_agreed
    SCF
    RET

.hs_kick_inc:
    CALL ovl_town_inc_insults
    JR   C, .hs_kick
    OR   A
    RET

.hs_insult:
    CALL ovl_town_inc_insults
    JR   C, .hs_kick
    CALL ovl_town_show_insult
    JP   .hs_loop

.hs_kick:
    JP   ovl_town_do_kick

ovl_town_show_agreed:
    CALL ovl_town_clear_msgs
    LD   B, 22
    LD   C, 1
    LD   E, COL_LGREEN
    LD   HL, ovl_town_str_agreed
    JP   screen_put_str

; Compute ovl_town_hg_pct from (ovl_town_hg_num * 100) / ovl_town_hg_den
; Output: CF = 1 OK (ovl_town_hg_pct clamped), CF = 0 below HG_MIN_CONCESSION
ovl_town_concession_pct:
    ; Shift both num and den right together until den fits in 8 bits
.scale:
    LD   A, (ovl_town_hg_den + 1)
    LD   B, A
    LD   A, (ovl_town_hg_den + 2)
    OR   B
    JR   Z, .scaled
    LD   HL, ovl_town_hg_den
    CALL ovl_town_shr24
    LD   HL, ovl_town_hg_num
    CALL ovl_town_shr24
    JR   .scale
.scaled:
    LD   A, (ovl_town_hg_den)
    OR   A
    JR   Z, .hi_pct
.nonz:
    ; If num_hi != 0 or num_mid != 0, pct >= 100 -> saturate 255 then damp (192)
    LD   A, (ovl_town_hg_num + 2)
    LD   B, A
    LD   A, (ovl_town_hg_num + 1)
    OR   B
    JR   NZ, .hi_pct
    LD   HL, (ovl_town_hg_num)  ; H = 0, L = num_lo
    LD   A, 100
    CALL ovl_town_mul16x8       ; E:HL = num_lo * 100 (<= 25500)
    LD   A, (ovl_town_hg_den)
    LD   C, A
    CALL ovl_town_div24x8       ; E:HL = pct
    LD   A, H
    OR   E
    JR   NZ, .hi_pct
    LD   A, L
    CP   OVL_TOWN_HG_MIN_CONC
    RET  C                      ; CF = 0: insult
    CP   OVL_TOWN_HG_MAX_CONC + 1
    JR   C, .store_pct
    JR   .damp_pct
.hi_pct:
    LD   A, 0xFF                ; 6502 $FF -> damped to 255 - 63 = 192
.damp_pct:
    LD   B, A
    SRL  A
    SRL  A
    LD   C, A
    LD   A, B
    SUB  C
    CP   OVL_TOWN_HG_MAX_CONC
    JR   NC, .store_pct
    LD   A, OVL_TOWN_HG_MAX_CONC
.store_pct:
    LD   (ovl_town_hg_pct), A
    SCF
    RET

; ovl_town_pct_step — ovl_town_hg_num = ((ovl_town_hg_num * pct) / 100) + 1
ovl_town_pct_step:
    LD   HL, (ovl_town_hg_num)
    LD   A, (ovl_town_hg_num + 2)
    LD   B, A
    LD   A, (ovl_town_hg_pct)
    CALL ovl_town_mul24x8_in    ; E:HL = gap * pct
    LD   C, 100
    CALL ovl_town_div24x8       ; E:HL = quotient
    INC  HL
    LD   A, H
    OR   L
    JR   NZ, .no_c_hi
    INC  E                      ; carry 0xFFFF -> 0x10000
.no_c_hi:
    LD   (ovl_town_hg_num), HL
    LD   A, E
    LD   (ovl_town_hg_num + 2), A
    RET

; Prompt HL ("Asks "/"Offers "/"Final offer: ") + ask + " gp.", row 21 DE prompt
ovl_town_hg_show_prompt:
    PUSH DE
    PUSH HL
    CALL ovl_town_clear_msgs
    POP  HL
    PUSH HL
    LD   B, 20
    LD   C, 1
    LD   E, COL_WHITE
    CALL screen_put_str
    POP  HL
    CALL ovl_town_strlen        ; A = prefix length
    INC  A
    PUSH AF                     ; save ask start col
    LD   HL, ovl_town_hg_ask
    CALL ovl_town_fmt_price_buf ; HL = temp_str_buf, B = len
    LD   H, B
    POP  AF
    PUSH AF
    PUSH HL                     ; H = price digit len
    LD   C, A
    LD   B, 20
    LD   E, COL_YELLOW
    LD   HL, temp_str_buf
    CALL screen_put_str
    POP  HL                     ; H = price len
    POP  AF                     ; A = start col
    ADD  A, H
    LD   C, A
    LD   B, 20
    LD   E, COL_WHITE
    LD   HL, ovl_town_str_gp_dot
    CALL screen_put_str
    POP  HL                     ; HL = row 21 prompt
    LD   B, 21
    LD   C, 1
    LD   E, COL_WHITE
    JP   screen_put_str

ovl_town_put_slot_hdr:
    LD   A, 1
ovl_town_put_slot_hdr_sp:
    PUSH AF
    PUSH BC
    PUSH DE
    LD   A, 'a'
    ADD  A, C
    LD   C, 1
    LD   E, D
    CALL screen_put_char
    POP  DE
    POP  BC
    PUSH BC
    PUSH DE
    LD   C, 2
    LD   A, ')'
    LD   E, D
    CALL screen_put_char
    POP  DE
    POP  BC
    POP  AF
    OR   A
    RET  Z
    PUSH BC
    PUSH DE
    LD   C, 3
    LD   A, ' '
    LD   E, D
    CALL screen_put_char
    POP  DE
    POP  BC
    RET

; Shared Y/N price confirm: B = row (21 or 22), A = clear_msgs (1/0), HL = header, DE = suffix
; Returns Z = 1 if 'Y' / 'y' pressed (any other key returns Z = 0)
ovl_town_yn_prompt:
    LD   (ovl_town_srr_tmp1), A
    PUSH BC
    PUSH DE
    PUSH HL
    OR   A
    JR   Z, .yn_clr_one
    CALL ovl_town_clear_msgs
    JR   .yn_clr_done
.yn_clr_one:
    CALL screen_clear_row
.yn_clr_done:
    POP  HL
    POP  DE
    POP  BC
    PUSH BC
    PUSH DE
    LD   C, 1
    LD   E, COL_WHITE
    CALL screen_put_str
    LD   HL, ovl_town_price
    CALL ovl_town_fmt_price_buf ; HL = temp_str_buf, B = len
    LD   D, B                   ; D = digit len
    POP  HL                     ; HL = suffix
    POP  BC                     ; B = row
    PUSH BC
    PUSH DE
    PUSH HL
    LD   C, 8
    LD   E, COL_YELLOW
    LD   HL, temp_str_buf
    CALL screen_put_str
    POP  HL                     ; HL = suffix
    POP  DE                     ; D = digit len
    POP  BC                     ; B = row
    LD   A, 8
    ADD  A, D
    LD   C, A
    LD   E, COL_WHITE
    CALL screen_put_str
    CALL screen_flush
    CALL input_get_key
    CALL ovl_town_to_upper
    CP   'Y'
    RET

ovl_town_hg_show_counter:
    CALL ovl_town_clear_msgs
    LD   B, 20
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_town_str_counter
    CALL screen_put_str
    LD   HL, ovl_town_hg_ask
    CALL ovl_town_fmt_price_buf ; HL = temp_str_buf, B = len
    PUSH BC
    LD   B, 20
    LD   C, 11
    LD   E, COL_YELLOW
    CALL screen_put_str
    POP  BC                     ; B = price digit len
    LD   A, 11
    ADD  A, B
    LD   C, A
    LD   B, 20
    LD   E, COL_WHITE
    LD   HL, ovl_town_str_gp_q
    CALL screen_put_str
    CALL screen_flush
    JP   input_get_key

ovl_town_hg_retry:
    CALL ovl_town_clear_msgs
    LD   B, 23
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_town_str_retry
    CALL screen_put_str
    CALL screen_flush
    JP   input_get_key

ovl_town_show_insult:
    CALL ovl_town_clear_msgs
    LD   A, HSTR_INSULT_COUNT
    CALL rng_range
    LD   DE, temp_str_buf
    CALL huff_decode_string
    LD   B, 23
    LD   C, 1
    LD   E, COL_RED
    CALL screen_put_str
    CALL screen_flush
    JP   input_get_key

ovl_town_inc_insults:
    LD   HL, ovl_town_insults
    INC  (HL)
    LD   A, (HL)
    CP   3
    JR   NC, .kicked
    OR   A
    RET
.kicked:
    SCF
    RET

ovl_town_check_kicked:
    LD   A, (ovl_town_store_idx)
    LD   E, A
    LD   D, 0
    LD   HL, hg_kicked
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    RET

ovl_town_do_kick:
    LD   A, (ovl_town_store_idx)
    LD   E, A
    LD   D, 0
    LD   HL, hg_kicked
    ADD  HL, DE
    LD   (HL), 1
    CALL ovl_town_show_kicked
    OR   A                      ; CF = 0
    RET

ovl_town_show_kicked:
    LD   HL, ovl_town_str_kicked
    LD   A, COL_RED

ovl_town_show_err_wait:
    PUSH AF
    PUSH HL
    CALL ovl_town_clear_msgs
    POP  HL
    POP  AF
    LD   E, A
    LD   B, 22
    LD   C, 1
    CALL screen_put_str
    CALL screen_flush
    JP   input_get_key

; Read up to 5 digits (0..65535) on row 22 col 1 -> ovl_town_hg_input, CF=1 OK / CF=0 cancel
ovl_town_read_number:
    XOR  A
    LD   (ovl_town_hg_digits), A
.loop:
    CALL screen_flush
    LD   A, (ovl_town_hg_digits)
    INC  A
    LD   C, A
    LD   B, 22
    CALL screen_set_cursor
    CALL input_get_key

    CP   KEY_CR
    JR   Z, .accept
    CALL ovl_town_is_cancel
    JP   Z, .cancel

    CP   KEY_BS
    JR   Z, .bs
    CP   KEY_DEL
    JR   Z, .bs

    CP   '0'
    JR   C, .loop
    CP   '9' + 1
    JR   NC, .loop

    LD   C, A
    LD   A, (ovl_town_hg_digits)
    CP   5
    JR   NC, .loop
    LD   E, A
    LD   D, 0
    LD   HL, line_buf
    ADD  HL, DE
    LD   (HL), C
    INC  A
    LD   (ovl_town_hg_digits), A
    ; Verify candidate <= 65535 before echoing digit (6502 ui_store.s)
    CALL .parse_buf
    LD   A, (ovl_town_hg_input + 2)
    OR   A
    JR   Z, .digit_ok
    LD   HL, ovl_town_hg_digits
    DEC  (HL)
    JR   .loop
.digit_ok:
    LD   A, (ovl_town_hg_digits)
    LD   E, A
    LD   A, C
    LD   B, 22
    LD   C, E
    LD   E, COL_YELLOW
    CALL screen_put_char
    JR   .loop

.bs:
    LD   A, (ovl_town_hg_digits)
    OR   A
    JR   Z, .loop
    DEC  A
    LD   (ovl_town_hg_digits), A
    LD   C, A
    INC  C
    LD   B, 22
    LD   A, ' '
    LD   E, COL_WHITE
    CALL screen_put_char
    JR   .loop

.accept:
    LD   A, (ovl_town_hg_digits)
    OR   A
    JR   Z, .loop
    CALL .parse_buf
    SCF
    RET

.parse_buf:
    LD   A, (ovl_town_hg_digits)
    LD   B, A
    XOR  A
    LD   HL, ovl_town_hg_input
    LD   (HL), A
    INC  HL
    LD   (HL), A
    INC  HL
    LD   (HL), A
    LD   DE, line_buf
.parse:
    PUSH BC
    PUSH DE
    LD   HL, ovl_town_hg_input
    LD   A, 10
    CALL ovl_town_mul24x8_ptr
    POP  DE
    LD   A, (DE)
    SUB  '0'
    LD   HL, ovl_town_hg_input
    ADD  A, (HL)
    LD   (HL), A
    INC  HL
    LD   A, (HL)
    ADC  A, 0
    LD   (HL), A
    INC  HL
    LD   A, (HL)
    ADC  A, 0
    LD   (HL), A
    INC  DE
    POP  BC
    DJNZ .parse
    RET

.cancel:
    OR   A
    RET

; ============================================================================
; Vector +3: ovl_town_restock_all — Init (A=0) or Periodic Restock (A!=0)
; Preserves: IX, IY
; ============================================================================
ovl_town_restock_all:
    PUSH IX
    PUSH IY
    OR   A
    PUSH AF

    ; Clear hg_kicked[0..STORE_COUNT-1]
    LD   HL, hg_kicked
    LD   DE, hg_kicked + 1
    LD   BC, STORE_COUNT - 1
    LD   (HL), 0
    LDIR

    POP  AF
    JR   NZ, .restock_stores

    ; A == 0: clear all STORE_TOTAL_SLOTS (0..127 including Home, matching 6502 store_init_all)
    LD   HL, si_item_id
    LD   DE, si_item_id + 1
    LD   BC, STORE_TOTAL_SLOTS - 1
    LD   (HL), FI_EMPTY
    LDIR

.restock_stores:
    XOR  A
.st_loop:
    LD   (ovl_town_store_idx), A
    CALL ovl_town_restock_one
    LD   A, (ovl_town_store_idx)
    INC  A
    CP   STORE_HOME             ; 0..6 only
    JR   C, .st_loop

    POP  IY
    POP  IX
    RET

ovl_town_restock_one:
    ; Pre-restock stack compaction: merge identical stackable slots before counting
    CALL ovl_town_store_base_a
    LD   C, STORE_MAX_ITEMS
.cmp_lp:
    LD   E, A
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .cmp_next
    LD   A, E
    PUSH DE
    PUSH BC
    CALL ovl_town_sro_merge_slot
    POP  BC
    POP  DE
.cmp_next:
    LD   A, E
    INC  A
    DEC  C
    JR   NZ, .cmp_lp

    CALL ovl_town_sro_count     ; A = count, (ovl_town_srr_first_emp)
    CP   STORE_MIN_KEEP
    JR   C, .stock_up

    ; Count >= 14: turnover
    CALL ovl_town_sro_turn_around
    CALL ovl_town_sro_sell_one
    CALL ovl_town_sro_turn_around
    JR   ovl_town_sro_stock

.stock_up:
    ; Stock (STORE_MIN_KEEP + 2 - count) items (16 on empty new store)
    LD   B, A
    LD   A, STORE_MIN_KEEP + 2
    SUB  B

ovl_town_sro_stock:
    OR   A
    RET  Z
    LD   (ovl_town_srr_retry), A
.sst_loop:
    CALL ovl_town_sro_count
    LD   A, (ovl_town_srr_first_emp)
    CP   FI_EMPTY
    RET  Z                      ; store full

    LD   (ovl_town_abs_slot), A
    CALL ovl_town_pick_item     ; A = slot_lo, (item_cur_page) set
    LD   B, A
    CALL id_mark_known          ; VMS store_carry marks store items known

    LD   A, (ovl_town_abs_slot)
    LD   E, A
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   (HL), B

    LD   A, B
    CALL ovl_town_sro_stock_qty ; A = stock qty (preserves B)
    LD   HL, si_qty
    ADD  HL, DE
    LD   (HL), A

    LD   A, B
    CALL item_get_category_a    ; A = category
    CALL ovl_town_sro_set_p1

    LD   A, (ovl_town_abs_slot)
    CALL ovl_town_sro_merge_slot

    LD   HL, ovl_town_srr_retry
    DEC  (HL)
    JR   NZ, .sst_loop
    RET

; Sell 1 unit from A random occupied slots (uniform over occupied slots by rejection)
ovl_town_sro_sell_one:
    OR   A
    RET  Z
    LD   (ovl_town_srr_retry), A
.loop:
    CALL ovl_town_sro_count
    OR   A
    RET  Z
.pick_occ:
    LD   A, STORE_MAX_ITEMS
    CALL rng_range
    LD   B, A
    LD   A, (ovl_town_srr_base)
    ADD  A, B
    LD   E, A
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .pick_occ
    LD   HL, si_qty
    ADD  HL, DE
    DEC  (HL)
    JR   NZ, .next
    LD   HL, si_item_id
    ADD  HL, DE
    LD   (HL), FI_EMPTY
.next:
    LD   HL, ovl_town_srr_retry
    DEC  (HL)
    JR   NZ, .loop
    RET

ovl_town_sro_turn_around:
    LD   A, STORE_TURN_AROUND
    CALL rng_range
    ADD  A, 2
    RET

ovl_town_sro_count:
    CALL ovl_town_store_base_a
    LD   (ovl_town_srr_base), A
    LD   E, A
    LD   D, 0
    LD   A, FI_EMPTY
    LD   (ovl_town_srr_first_emp), A
    XOR  A
    LD   (ovl_town_srr_count), A
    LD   B, STORE_MAX_ITEMS
.lp:
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   NZ, .occ
    LD   A, (ovl_town_srr_first_emp)
    CP   FI_EMPTY
    JR   NZ, .nxt
    LD   A, E
    LD   (ovl_town_srr_first_emp), A
    JR   .nxt
.occ:
    LD   HL, ovl_town_srr_count
    INC  (HL)
.nxt:
    INC  E
    DJNZ .lp
    LD   A, (ovl_town_srr_count)
    RET

; Pick suitable item for ovl_town_store_idx -> A = slot_lo, (item_cur_page) set
ovl_town_pick_item:
    LD   A, (ovl_town_store_idx)
    CP   OVL_TOWN_SRO_CHOICES
    JR   NC, .by_cat
    LD   E, A
    LD   D, 0
    LD   HL, ovl_town_choice_cnt
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    JR   Z, .by_cat

    CALL rng_range              ; 0..25
    LD   HL, ovl_town_choice_base
    ADD  HL, DE
    ADD  A, (HL)
    LD   E, A                   ; index in ovl_town_choices
    CP   OVL_TOWN_SRO_P1_START
    JR   C, .p0
    CP   OVL_TOWN_SRO_P1_END
    JR   NC, .p0
    LD   A, ITEM_PAGE_BIT
    JR   .set_pg
.p0:
    XOR  A
.set_pg:
    LD   (item_cur_page), A
    LD   HL, ovl_town_choices
    ADD  HL, DE
    LD   A, (HL)
    RET

.by_cat:
    LD   B, STORE_PICK_RETRIES
.cat_loop:
    PUSH BC
.rng_id:
    CALL rng_next_u8
    AND  0x01
    LD   H, A
    CALL rng_next_u8
    LD   L, A                   ; HL in 0..511
    LD   DE, ITEM_TYPE_COUNT - (ITEM_SLOT_GOLD_MITHRIL + 1)
    OR   A
    SBC  HL, DE
    JR   NC, .rng_id            ; reject >= 341
    ADD  HL, DE
    LD   DE, ITEM_SLOT_GOLD_MITHRIL + 1
    ADD  HL, DE                 ; HL in 20..360
    CALL item_logical_to_paged  ; A = slot_lo, (item_cur_page) set
    LD   D, A
    CALL item_get_category_a
    LD   C, A
    LD   A, (ovl_town_store_idx)
    LD   B, A
    LD   A, C
    PUSH DE
    CALL ovl_town_check_cat
    POP  DE
    JR   NC, .cat_reject

    POP  BC
    LD   A, D
    RET

.cat_reject:
    POP  BC
    DJNZ .cat_loop

    LD   A, (ovl_town_store_idx)
    LD   E, A
    LD   D, 0
    LD   HL, ovl_town_fallback_pg
    ADD  HL, DE
    LD   A, (HL)
    LD   (item_cur_page), A
    LD   HL, ovl_town_fallback
    ADD  HL, DE
    LD   A, (HL)
    RET

; Input: A = slot_lo, (item_cur_page). Output: A = qty. Preserves: BC, DE
ovl_town_sro_stock_qty:
    PUSH BC
    PUSH DE
    LD   C, A
    LD   A, (item_cur_page)
    OR   A
    JR   NZ, .one
    LD   HL, ovl_town_stack_id
    LD   B, ovl_town_stack_qty - ovl_town_stack_id
.lp:
    LD   A, (HL)
    CP   C
    JR   Z, .found
    INC  HL
    DJNZ .lp
.one:
    LD   A, 1
    POP  DE
    POP  BC
    RET
.found:
    LD   DE, ovl_town_stack_qty - ovl_town_stack_id
    ADD  HL, DE
    LD   A, (HL)
    POP  DE
    POP  BC
    RET

; Set p1, to_hit, to_dam, to_ac, si_meta=IF_IDENTIFIED, si_meta_hi=item_cur_page
; Input: A = category, (ovl_town_abs_slot)
ovl_town_sro_set_p1:
    LD   C, A                   ; C = category
    LD   B, 0                   ; default bonus p1=0
    CP   ICAT_CLOAK
    JR   Z, .enchant
    CP   ICAT_WEAPON
    JR   C, .not_eq
    CP   ICAT_BOOTS + 1
    JR   C, .enchant
.not_eq:
    CP   ICAT_RING
    JR   Z, .ring
    CP   ICAT_AMULET
    JR   Z, .ring
    CP   ICAT_LIGHT
    JR   Z, .light
    CP   ICAT_WAND
    JR   C, .store_p1
    CP   ICAT_STAFF + 1
    JR   NC, .store_p1
    ; Wand/staff charges: 3..8
    LD   A, 6
    CALL rng_range
    ADD  A, 3
    LD   B, A
    JR   .store_p1

.light:
    LD   B, LANTERN_MAX_CHARGES
    LD   A, (item_cur_page)
    OR   A
    JR   NZ, .store_p1
    LD   A, (ovl_town_abs_slot)
    LD   E, A
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   ITEM_SLOT_WOODEN_TORCH
    JR   NZ, .store_p1
    LD   B, OVL_TOWN_TORCH_CHARGES

.store_p1:
    LD   A, B
.store_p1_val:
    LD   B, A
    LD   A, (ovl_town_abs_slot)
    LD   E, A
    LD   D, 0
    LD   HL, si_p1
    ADD  HL, DE
    LD   (HL), B
    PUSH DE
    LD   DE, STORE_TOTAL_SLOTS
    XOR  A
    ADD  HL, DE                 ; si_to_hit
    LD   (HL), A
    ADD  HL, DE                 ; si_to_dam
    LD   (HL), A
    ADD  HL, DE                 ; si_to_ac
    LD   (HL), A
    ADD  HL, DE                 ; si_meta
    LD   (HL), IF_IDENTIFIED
    ADD  HL, DE                 ; si_meta_hi
    LD   A, (item_cur_page)
    AND  ITEM_PAGE_BIT
    LD   (HL), A
    POP  DE
    RET

.enchant:
    XOR  A
    CALL .store_p1_val          ; zeros p1/hit/dam/ac & sets meta
    LD   A, 3
    CALL rng_range              ; bonus 0..2
    LD   B, A
    LD   A, (ovl_town_abs_slot)
    LD   E, A
    LD   D, 0
    LD   A, C
    CP   ICAT_WEAPON
    JR   Z, .slaying
.ac_only:
    LD   HL, si_to_ac
    ADD  HL, DE
    LD   (HL), B
    RET
.slaying:
    LD   HL, si_to_hit
    ADD  HL, DE
    LD   (HL), B
    LD   HL, si_to_dam
    ADD  HL, DE
    LD   (HL), B
    RET

.ring:
    XOR  A
    CALL .store_p1_val
    LD   A, (item_cur_page)
    OR   A
    RET  Z
    LD   A, 3
    CALL rng_range
    LD   B, A
    LD   A, (ovl_town_abs_slot)
    LD   E, A
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   ITEM_SLOT_RING_OF_PROTECTION
    JR   Z, .ac_only
    CP   ITEM_SLOT_RING_OF_SLAYING
    JR   Z, .slaying
    CP   ITEM_SLOT_RING_OF_INCREASE_DAMAGE
    JR   Z, .dam_only
    CP   ITEM_SLOT_RING_OF_INCREASE_TO_HIT
    JR   Z, .hit_only
    CP   ITEM_SLOT_AMULET_OF_THE_MAGI
    JR   Z, .p1_only
    CP   ITEM_SLOT_RING_OF_STRENGTH
    JR   C, .chk_am
    CP   ITEM_SLOT_RING_OF_SEARCHING + 1
    JR   C, .p1_only
.chk_am:
    CP   ITEM_SLOT_AMULET_OF_WISDOM
    RET  C
    CP   ITEM_SLOT_AMULET_OF_CHARISMA + 1
    RET  NC
.p1_only:
    LD   HL, si_p1
    ADD  HL, DE
    LD   (HL), B
    RET
.hit_only:
    LD   HL, si_to_hit
    ADD  HL, DE
    LD   (HL), B
    RET
.dam_only:
    LD   HL, si_to_dam
    ADD  HL, DE
    LD   (HL), B
    RET

; Merge store slot A into an earlier matching slot in the same store
ovl_town_sro_merge_slot:
    LD   (ovl_town_srr_tmp0), A ; src slot
    LD   E, A
    LD   D, 0
    LD   HL, si_meta_hi
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    CALL item_stacks_a
    RET  NC

    CALL ovl_town_store_base_a
    LD   E, A                   ; E = scan slot
    LD   C, STORE_MAX_ITEMS
.scan:
    LD   A, (ovl_town_srr_tmp0)
    CP   E
    JR   Z, .next
    LD   B, E                   ; A = src slot, B = scan slot
    CALL ovl_town_match_store_pair
    JR   NC, .next

    ; Add src qty into scan slot E (cap at STORE_STACK_MAX=24), empty src
    LD   A, (ovl_town_srr_tmp0)
    LD   L, A
    LD   H, 0
    LD   BC, si_qty
    ADD  HL, BC
    LD   A, (HL)                ; src qty
    LD   D, 0
    LD   HL, si_qty
    ADD  HL, DE
    ADD  A, (HL)
    CP   STORE_STACK_MAX + 1
    JR   C, .qty_ok
    LD   A, STORE_STACK_MAX
.qty_ok:
    LD   (HL), A
    LD   A, (ovl_town_srr_tmp0)
    LD   E, A
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   (HL), FI_EMPTY
    RET
.next:
    INC  E
    DEC  C
    JR   NZ, .scan
    RET

; ============================================================================
; Shared Store Slot Helpers
; ============================================================================

ovl_town_store_base_a:
    LD   A, (ovl_town_store_idx)
    ADD  A, A
    ADD  A, A
    ADD  A, A
    ADD  A, A                   ; store_idx * 16
    RET

ovl_town_find_empty_slot:
    CALL ovl_town_store_base_a
    LD   E, A
    LD   B, STORE_MAX_ITEMS
.lp:
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .yes
    INC  E
    DJNZ .lp
    OR   A
    RET
.yes:
    LD   A, E
    SCF
    RET

ovl_town_check_cat:
    CP   ICAT_GOLD
    JR   Z, .no
    CP   ICAT_CHEST
    JR   Z, .no
    CP   ICAT_JUNK
    JR   Z, .no
    JP   store_check_category
.no:
    OR   A
    RET

; Match store slot A with store slot B:
; Check non-empty, item_id, p1, to_hit, to_dam, to_ac, (meta & 0x0F), meta_hi
; Output: CF = 1 if match, CF = 0 else. Preserves BC, DE.
ovl_town_match_store_pair:
    PUSH BC
    PUSH DE
    LD   E, A                   ; E = slot A
    LD   D, B                   ; D = slot B
    LD   C, D
    LD   B, 0
    LD   HL, si_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .no

    LD   HL, si_item_id
    CALL .cmp_arr
    JR   NZ, .no
    LD   HL, si_p1
    CALL .cmp_arr
    JR   NZ, .no
    LD   HL, si_to_hit
    CALL .cmp_arr
    JR   NZ, .no
    LD   HL, si_to_dam
    CALL .cmp_arr
    JR   NZ, .no
    LD   HL, si_to_ac
    CALL .cmp_arr
    JR   NZ, .no
    LD   HL, si_meta_hi
    CALL .cmp_arr
    JR   NZ, .no

    ; Compare meta & ITEM_META_FLAGS_MASK
    LD   B, 0
    LD   C, D
    LD   HL, si_meta
    ADD  HL, BC
    LD   A, (HL)
    AND  ITEM_META_FLAGS_MASK
    LD   C, E
    LD   HL, si_meta
    ADD  HL, BC
    LD   B, A
    LD   A, (HL)
    AND  ITEM_META_FLAGS_MASK
    CP   B
    JR   NZ, .no

    POP  DE
    POP  BC
    SCF
    RET
.no:
    POP  DE
    POP  BC
    OR   A
    RET
.cmp_arr:
    ; Compare arr[D] vs arr[E], preserve DE. Z=1 if equal.
    PUSH DE
    LD   B, 0
    LD   C, D
    PUSH HL
    ADD  HL, BC
    LD   A, (HL)
    POP  HL
    LD   C, E
    ADD  HL, BC
    CP   (HL)
    POP  DE
    RET

; ============================================================================
; 24-bit Math, Price Formatting & Screen Helpers
; ============================================================================

; HL * A -> E:HL (24-bit)
ovl_town_mul16x8:
    LD   B, 8
    LD   C, A
    EX   DE, HL                 ; DE = multiplicand
    LD   HL, 0
    LD   A, H                   ; A = hi byte of 24-bit accumulator
.lp:
    ADD  HL, HL
    RLA
    SLA  C
    JR   NC, .nc
    ADD  HL, DE
    ADC  A, 0
.nc:
    DJNZ .lp
    LD   E, A
    RET

; (B:HL) * A -> E:HL (24-bit, saturating to 0xFFFFFF)
ovl_town_mul24x8_in:
    LD   C, A                   ; B = hi8, C = multiplier
    PUSH BC
    CALL ovl_town_mul16x8       ; E:HL = lo16 * A (clobbers BC)
    POP  BC                     ; restore B = hi8, C = multiplier
    LD   A, B
    OR   A
    RET  Z
    ; Add (hi8 * C) << 16 into E (preserve E across mul_hl_a!)
    PUSH HL
    PUSH DE
    LD   L, A
    LD   H, 0
    LD   A, C
    CALL mul_hl_a               ; HL = hi8 * C (clobbers DE!)
    POP  DE
    LD   A, H
    OR   A
    JR   NZ, .sat
    LD   A, E
    ADD  A, L
    JR   C, .sat
    LD   E, A
    POP  HL
    RET
.sat:
    POP  HL
    LD   HL, 0xFFFF
    LD   E, 0xFF
    RET

; ovl_town_base24 * A -> ovl_town_price
ovl_town_mul24x8:
    LD   C, A
    LD   HL, (ovl_town_base24)
    LD   A, (ovl_town_base24 + 2)
    LD   B, A
    LD   A, C
    CALL ovl_town_mul24x8_in
    LD   (ovl_town_price), HL
    LD   A, E
    LD   (ovl_town_price + 2), A
    RET

; (HL[3]) * A -> HL[3]
ovl_town_mul24x8_ptr:
    PUSH HL
    LD   C, A
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    INC  HL
    LD   B, (HL)
    EX   DE, HL                 ; B:HL
    LD   A, C
    CALL ovl_town_mul24x8_in    ; E:HL
    LD   A, E
    EX   DE, HL                 ; DE = lo16, A = hi8
    POP  HL                     ; HL = ptr
    LD   (HL), E
    INC  HL
    LD   (HL), D
    INC  HL
    LD   (HL), A
    RET

; E:HL / C -> E:HL quotient, A remainder
ovl_town_div24x8:
    XOR  A
    LD   B, 24
.lp:
    ADD  HL, HL
    RL   E
    RLA
    JR   C, .sub
    CP   C
    JR   C, .nosub
.sub:
    SUB  C
    INC  L
.nosub:
    DJNZ .lp
    RET

; 24-bit ptr ops: HL, DE, BC
ovl_town_copy24:
    LD   BC, 3
    LDIR
    RET

ovl_town_is_zero_24:
    LD   A, (HL)
    INC  HL
    OR   (HL)
    INC  HL
    OR   (HL)
    DEC  HL
    DEC  HL
    RET

; Return CF=1 if *HL > 10
ovl_town_is_price_gt10:
    INC  HL
    LD   A, (HL)
    INC  HL
    OR   (HL)
    DEC  HL
    DEC  HL
    SCF
    RET  NZ
    LD   A, (HL)
    CP   11
    CCF
    RET

; Compare *HL vs *DE (24-bit unsigned): Z=1 eq, CF=1 if *HL < *DE
ovl_town_cmp24:
    INC  HL
    INC  HL
    INC  DE
    INC  DE
    LD   A, (DE)
    LD   B, (HL)
    DEC  HL
    DEC  DE
    CP   B
    JR   C, .gt
    JR   NZ, .lt
    LD   A, (DE)
    LD   B, (HL)
    DEC  HL
    DEC  DE
    CP   B
    JR   C, .gt
    JR   NZ, .lt
    LD   A, (DE)
    CP   (HL)
    RET  Z
    CCF
    RET
.lt:
    SCF
    RET
.gt:
    OR   B
    RET

ovl_town_add24:
    PUSH BC
    LD   A, (DE)
    ADD  A, (HL)
    LD   (BC), A
    INC  HL
    INC  DE
    INC  BC
    LD   A, (DE)
    ADC  A, (HL)
    LD   (BC), A
    INC  HL
    INC  DE
    INC  BC
    LD   A, (DE)
    ADC  A, (HL)
    LD   (BC), A
    POP  BC
    RET  NC
    LD   A, 0xFF
    LD   (BC), A
    INC  BC
    LD   (BC), A
    INC  BC
    LD   (BC), A
    RET

ovl_town_sub24:
    LD   A, (HL)
    EX   DE, HL
    SUB  (HL)
    EX   DE, HL
    LD   (BC), A
    INC  HL
    INC  DE
    INC  BC
    LD   A, (HL)
    EX   DE, HL
    SBC  A, (HL)
    EX   DE, HL
    LD   (BC), A
    INC  HL
    INC  DE
    INC  BC
    LD   A, (HL)
    EX   DE, HL
    SBC  A, (HL)
    EX   DE, HL
    LD   (BC), A
    RET

ovl_town_shr24:
    INC  HL
    INC  HL
    SRL  (HL)
    DEC  HL
    RR   (HL)
    DEC  HL
    RR   (HL)
    RET

ovl_town_shl24:
    SLA  (HL)
    INC  HL
    RL   (HL)
    INC  HL
    RL   (HL)
    RET  NC
    LD   A, 0xFF
    LD   (HL), A
    DEC  HL
    LD   (HL), A
    DEC  HL
    LD   (HL), A
    RET

ovl_town_fmt_price_buf:
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    INC  HL
    LD   A, (HL)
    EX   DE, HL                 ; HL = lo16
    LD   E, A                   ; E = hi8
    LD   BC, temp_str_buf
    JP   status_fmt_u24         ; HL = temp_str_buf, B = len

ovl_town_fmt_price_gp:
    CALL ovl_town_fmt_price_buf ; HL = temp_str_buf, B = len
    LD   E, B
    LD   D, 0
    ADD  HL, DE
    LD   (HL), ' '
    INC  HL
    LD   (HL), 'G'
    INC  HL
    LD   (HL), 'P'
    INC  HL
    LD   (HL), ' '
    INC  HL
    LD   (HL), ' '
    INC  HL
    LD   (HL), ' '
    INC  HL
    LD   (HL), ' '
    INC  HL
    LD   (HL), 0
    LD   HL, temp_str_buf
    RET

ovl_town_strlen:
    LD   B, 0
.lp:
    LD   A, (HL)
    OR   A
    LD   A, B
    RET  Z
    INC  HL
    INC  B
    JR   .lp

ovl_town_tbl_ptr:
    ADD  A, A
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    LD   A, (HL)
    INC  HL
    LD   H, (HL)
    LD   L, A
    RET

ovl_town_draw_sep:
    LD   C, 0
.lp:
    PUSH BC
    LD   A, '-'
    LD   E, COL_DGREY
    CALL screen_put_char
    POP  BC
    INC  C
    LD   A, C
    CP   SCREEN_COLS
    JR   C, .lp
    RET

ovl_town_clear_msgs:
    LD   B, 20
.lp:
    PUSH BC
    CALL screen_clear_row
    POP  BC
    INC  B
    LD   A, B
    CP   24
    JR   C, .lp
    RET

ovl_town_is_cancel:
    CP   'q'
    RET  Z
    CP   'Q'
    RET  Z
    CP   KEY_ESC
    RET  Z
    CP   KEY_SPACE
    RET

ovl_town_to_upper:
    CP   'a'
    RET  C
    CP   'z' + 1
    RET  NC
    SUB  0x20
    RET

ovl_town_to_lower:
    CP   'A'
    RET  C
    CP   'Z' + 1
    RET  NC
    ADD  A, 0x20
    RET

; ============================================================================
; Tables & Data (matching core/6502/{store,tables,store_restock_overlay}.s)
; ============================================================================

ovl_town_chr_buy_adj:
    DB   130, 125, 122, 120, 118, 116, 114, 112
    DB   110, 108, 106, 104, 103, 102, 101, 100

ovl_town_chr_sell_adj:
    DB   25, 27, 29, 31, 33, 35, 37, 39
    DB   41, 43, 44, 45, 46, 47, 48, 50

ovl_town_choices:
ovl_town_general_choice:
    DB   ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_RATION_OF_FOOD
    DB   ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_RATION_OF_FOOD
    DB   ITEM_SLOT_HARD_BISCUIT, ITEM_SLOT_HARD_BISCUIT, ITEM_SLOT_HARD_BISCUIT
    DB   ITEM_SLOT_STRIP_OF_BEEF_JERKY, ITEM_SLOT_STRIP_OF_BEEF_JERKY
    DB   ITEM_SLOT_PINT_OF_FINE_ALE, ITEM_SLOT_PINT_OF_FINE_WINE
    DB   ITEM_SLOT_FLASK_OF_OIL, ITEM_SLOT_FLASK_OF_OIL
    DB   ITEM_SLOT_WOODEN_TORCH, ITEM_SLOT_WOODEN_TORCH, ITEM_SLOT_WOODEN_TORCH, ITEM_SLOT_BRASS_LANTERN
    DB   ITEM_SLOT_IRON_SPIKE, ITEM_SLOT_IRON_SPIKE, ITEM_SLOT_SHOVEL, ITEM_SLOT_PICK, ITEM_SLOT_CLOAK
ovl_town_temple_choice:
    DB   ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_BEGINNERS_HANDBOOK
    DB   ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_WORDS_OF_WISDOM
    DB   ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_CHANTS_AND_BLESSINGS
    DB   ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_EXORCISM
    DB   ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_WORDS_OF_WISDOM
    DB   ITEM_SLOT_SCROLL_OF_REMOVE_CURSE, ITEM_SLOT_SCROLL_OF_REMOVE_CURSE
    DB   ITEM_SLOT_SCROLL_OF_BLESSING
    DB   ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS, ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS, ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    DB   ITEM_SLOT_POTION_OF_CURE_SERIOUS_WOUNDS, ITEM_SLOT_POTION_OF_CURE_SERIOUS_WOUNDS, ITEM_SLOT_POTION_OF_CURE_SERIOUS_WOUNDS
    DB   ITEM_SLOT_POTION_OF_CURE_CRITICAL_WOUNDS, ITEM_SLOT_POTION_OF_CURE_CRITICAL_WOUNDS
    DB   ITEM_SLOT_POTION_OF_HEROISM, ITEM_SLOT_POTION_OF_BOLDNESS
    DB   ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL, ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL
    DB   ITEM_SLOT_POTION_OF_RESTORE_WISDOM, ITEM_SLOT_POTION_OF_RESTORE_LIFE_LEVELS
    DB   ITEM_SLOT_POTION_OF_NEUTRALIZE_POISON
ovl_town_temple_p1_start:
    DB   ITEM_SLOT_MORNINGSTAR, ITEM_SLOT_MACE, ITEM_SLOT_WAR_HAMMER
ovl_town_temple_p1_end:
ovl_town_alchemy_choice:
    DB   ITEM_SLOT_SCROLL_OF_ENCHANT_WEAPON_TO_HIT
    DB   ITEM_SLOT_SCROLL_OF_ENCHANT_WEAPON_TO_DAM
    DB   ITEM_SLOT_SCROLL_OF_ENCHANT_ARMOR
    DB   ITEM_SLOT_SCROLL_OF_IDENTIFY, ITEM_SLOT_SCROLL_OF_IDENTIFY, ITEM_SLOT_SCROLL_OF_LIGHT, ITEM_SLOT_SCROLL_OF_LIGHT
    DB   ITEM_SLOT_SCROLL_OF_PHASE_DOOR, ITEM_SLOT_SCROLL_OF_PHASE_DOOR
    DB   ITEM_SLOT_SCROLL_OF_MAGIC_MAPPING, ITEM_SLOT_SCROLL_OF_MAGIC_MAPPING
    DB   ITEM_SLOT_SCROLL_OF_TREASURE_DETECTION, ITEM_SLOT_SCROLL_OF_TREASURE_DETECTION
    DB   ITEM_SLOT_SCROLL_OF_OBJECT_DETECTION, ITEM_SLOT_SCROLL_OF_OBJECT_DETECTION
    DB   ITEM_SLOT_SCROLL_OF_DETECT_INVISIBLE, ITEM_SLOT_SCROLL_OF_RECHARGING
    DB   ITEM_SLOT_POTION_OF_RESTORE_STRENGTH
    DB   ITEM_SLOT_POTION_OF_RESTORE_INTELLIGENCE
    DB   ITEM_SLOT_POTION_OF_RESTORE_DEXTERITY
    DB   ITEM_SLOT_POTION_OF_RESTORE_CONSTITUTION
    DB   ITEM_SLOT_POTION_OF_RESTORE_CHARISMA
    DB   ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL, ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL, ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL
    DB   ITEM_SLOT_POTION_OF_SLOW_POISON
ovl_town_choices_end:

ovl_town_choice_cnt:
    DB   OVL_TOWN_GEN_CNT, 0, 0, OVL_TOWN_TMP_CNT, OVL_TOWN_ALC_CNT
ovl_town_choice_base:
    DB   ovl_town_general_choice - ovl_town_choices, 0, 0
    DB   ovl_town_temple_choice - ovl_town_choices
    DB   ovl_town_alchemy_choice - ovl_town_choices

ovl_town_fallback:
    DB   ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_LEATHER_ARMOR, ITEM_SLOT_DAGGER
    DB   ITEM_SLOT_SCROLL_OF_LIGHT, ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    DB   ITEM_SLOT_RING_OF_PROTECTION, ITEM_SLOT_DAGGER
ovl_town_fallback_pg:
    DB   ITEM_PAGE_RATION_OF_FOOD, ITEM_PAGE_LEATHER_ARMOR, ITEM_PAGE_DAGGER
    DB   ITEM_PAGE_SCROLL_OF_LIGHT, ITEM_PAGE_POTION_OF_CURE_LIGHT_WOUNDS
    DB   ITEM_PAGE_RING_OF_PROTECTION, ITEM_PAGE_DAGGER

ovl_town_stack_id:
    DB   ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_HARD_BISCUIT, ITEM_SLOT_STRIP_OF_BEEF_JERKY
    DB   ITEM_SLOT_WOODEN_TORCH, ITEM_SLOT_FLASK_OF_OIL
    DB   ITEM_SLOT_PINT_OF_FINE_ALE, ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL, ITEM_SLOT_SCROLL_OF_LIGHT
    DB   ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS, ITEM_SLOT_SCROLL_OF_IDENTIFY, ITEM_SLOT_POTION_OF_HEROISM
    DB   ITEM_SLOT_SCROLL_OF_MAGIC_MAPPING, ITEM_SLOT_SCROLL_OF_OBJECT_DETECTION, ITEM_SLOT_SCROLL_OF_PHASE_DOOR
    DB   ITEM_SLOT_POTION_OF_BOLDNESS, ITEM_SLOT_POTION_OF_SLOW_POISON
    DB   ITEM_SLOT_SCROLL_OF_TREASURE_DETECTION, ITEM_SLOT_SCROLL_OF_BLESSING, ITEM_SLOT_SCROLL_OF_DETECT_INVISIBLE
    DB   ITEM_SLOT_ARROW, ITEM_SLOT_BOLT, ITEM_SLOT_ROCK, ITEM_SLOT_IRON_SHOT
ovl_town_stack_qty:
    DB   5, 5, 5, 5, 5
    DB   3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2
    DB   24, 24, 24, 24

ovl_town_store_ptrs:
    DW   ovl_town_sn_0, ovl_town_sn_1, ovl_town_sn_2, ovl_town_sn_3
    DW   ovl_town_sn_4, ovl_town_sn_5, ovl_town_sn_6
ovl_town_owner_ptrs:
    DW   ovl_town_so_0, ovl_town_so_1, ovl_town_so_2, ovl_town_so_3
    DW   ovl_town_so_4, ovl_town_so_5, ovl_town_so_6

ovl_town_sn_0: DB "General Store", 0
ovl_town_sn_1: DB "Armory", 0
ovl_town_sn_2: DB "Weaponsmith", 0
ovl_town_sn_3: DB "Temple", 0
ovl_town_sn_4: DB "Alchemy Shop", 0
ovl_town_sn_5: DB "Magic Shop", 0
ovl_town_sn_6: DB "Black Market", 0

ovl_town_so_0: DB "BILBO THE FRIENDLY", 0
ovl_town_so_1: DB "GORN THE ARMORER", 0
ovl_town_so_2: DB "BRYN THE FORGEMASTER", 0
ovl_town_so_3: DB "GARATH THE HEALER", 0
ovl_town_so_4: DB "ELARA THE ALCHEMIST", 0
ovl_town_so_5: DB "ZOLAN THE ENCHANTER", 0
ovl_town_so_6: DB "THE FENCE", 0

ovl_town_str_menu:       DB "B)uy  S)ell  Q)uit", 0
ovl_town_str_gold:       DB "Gold: ", 0
ovl_town_str_buy_which:  DB "Buy which item? (a-p)", 0
ovl_town_str_price_hdr:  DB "Price: ", 0
ovl_town_str_gp_buy:     DB " gp. Buy? (Y/N)", 0
ovl_town_str_bought:     DB "Bought!", 0
ovl_town_str_no_afford:  DB "You cannot afford that.", 0
ovl_town_str_sell_title: DB "Sell Items", 0
ovl_town_str_sell_which: DB "Sell which item? (a-v)", 0
ovl_town_str_offer_hdr:  DB "Offer: ", 0
ovl_town_str_gp_sell:    DB " gp. Sell? (Y/N)", 0
ovl_town_str_sold:       DB "Sold!", 0
ovl_town_str_no_buy:     DB "We don't buy that.", 0
ovl_town_str_worthless:  DB "That is worthless.", 0
ovl_town_str_store_full: DB "The store is full.", 0
ovl_town_str_cursed:     DB "That item is cursed.", 0
ovl_town_str_asks:       DB "Asks ", 0
ovl_town_str_offers:     DB "Offers ", 0
ovl_town_str_counter:    DB "How about ", 0
ovl_town_str_final:      DB "Final offer: ", 0
ovl_town_str_gp_dot:     DB " gp.", 0
ovl_town_str_gp_q:       DB " gp?", 0
ovl_town_str_your_offer: DB "Your offer? (Q=cancel)", 0
ovl_town_str_your_price: DB "Your price? (Q=cancel)", 0
ovl_town_str_retry:      DB "WHAT WAS THAT?", 0
ovl_town_str_kicked:     DB "Get out of my store!", 0
ovl_town_str_agreed:     DB "Agreed!", 0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_town.ovl", ovl_start, ovl_end - ovl_start
