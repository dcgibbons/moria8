; ============================================================================
; ovl_home.asm — Player Home storage overlay (OVL_HOME = 11, DAT slot 10)
; ============================================================================
; Entry vector at OVL_WINDOW_BASE (0x5600):
;   +0: JP ovl_home_enter  (STORE_HOME = 7, si_* slots 112..127)
; ============================================================================

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    DEFINE ITEM_HOT_TABLES_CONSTS_ONLY 1
    INCLUDE "item_hot_tables_z80.inc"
    UNDEFINE ITEM_HOT_TABLES_CONSTS_ONLY
    DEFINE HUFF_CONSTS_ONLY 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_CONSTS_ONLY
    INCLUDE "main_exp.inc"

OVL_HOME_BASE_SLOT  EQU (STORE_HOME * STORE_MAX_ITEMS)

    ORG  OVL_WINDOW_BASE

ovl_start:
    JP   ovl_home_enter         ; +0: OVL_WINDOW_BASE + 0

; ============================================================================
; Transient Overlay Working State (zero DS 128 buffers; 8 scalar bytes only)
; ============================================================================
ovl_home_msg_ptr:   DW 0
ovl_home_msg_attr:  DB COL_WHITE
ovl_home_slot:      DB 0
ovl_home_disp_row:  DB 0

; ============================================================================
; ovl_home_enter — Main Player Home loop (Deposit / Retrieve / Exit)
; Preserves: IX, IY
; ============================================================================
ovl_home_enter:
    PUSH IX
    PUSH IY
    CALL ovl_home_clear_msg

.loop:
    CALL ovl_home_draw
    CALL ovl_home_clear_msg
    CALL screen_flush
    LD   B, STORE_MENU_ROW
    LD   C, 19
    CALL screen_set_cursor
.wait_key:
    CALL input_get_key
    CALL ovl_home_to_upper

    CP   'Q'
    JR   Z, .exit
    CP   KEY_SPACE
    JR   Z, .exit
    CP   KEY_ESC
    JR   Z, .exit

    CP   'D'
    JR   Z, .do_dep

    CP   'R'
    JR   Z, .do_ret

    JR   .wait_key

.do_dep:
    CALL ovl_home_deposit
    JR   .loop

.do_ret:
    CALL ovl_home_retrieve
    JR   .loop

.exit:
    CALL screen_hard_clear
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    POP  IY
    POP  IX
    RET

; ============================================================================
; ovl_home_clear_msg — Clear pending row-20 feedback
; ============================================================================
ovl_home_clear_msg:
    XOR  A
    LD   L, A
    LD   H, A
    LD   (ovl_home_msg_ptr), HL
    RET

; ============================================================================
; ovl_home_draw — Render Home header, 16 slots A)..P), menu, gold, status
; ============================================================================
ovl_home_draw:
    CALL screen_clear

    ; Row 0 col 1: "Home" (COL_WHITE) + col 55: "Burden: X/Y lb"
    LD   B, 0
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_home_str_title
    CALL screen_put_str
    CALL ovl_home_draw_burden

    ; Row 2: separator dashes across cols 0..79
    LD   B, 2
    LD   C, 0
.sep_loop:
    PUSH BC
    LD   A, '-'
    LD   E, COL_DGREY
    CALL screen_put_char
    POP  BC
    INC  C
    LD   A, C
    CP   SCREEN_COLS
    JR   C, .sep_loop

    ; Render all 16 Home slots A)..P) at col 1 -> rows 3..18
    LD   C, 0                   ; C = slot index (0..15)
.slot_loop:
    LD   A, 3
    ADD  A, C
    LD   B, A                   ; B = screen row (3..18)
    LD   A, C
    ADD  A, OVL_HOME_BASE_SLOT
    LD   E, A
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   NZ, .slot_occ

    ; Empty slot: "A)" at col 1 in COL_DGREY
    LD   D, COL_DGREY
    XOR  A
    CALL ovl_home_put_hdr_sp
    JR   .slot_next

.slot_occ:
    LD   D, COL_WHITE
    LD   A, 1
    CALL ovl_home_put_hdr_sp

    ; Format description cleanly clipped to cols 4..66 + right-aligned weight col 69
    PUSH BC
    LD   A, C
    ADD  A, OVL_HOME_BASE_SLOT
    LD   DE, line_buf
    CALL item_format_store_slot ; HL = line_buf
    XOR  A
    LD   (line_buf + 63), A
    POP  BC
    PUSH BC
    LD   C, 4
    LD   E, COL_LGREY
    LD   HL, line_buf
    CALL screen_put_str
    POP  BC

    ; Store-slot weight at col 69 on row B (C = 0..15)
    PUSH BC
    LD   A, C
    ADD  A, OVL_HOME_BASE_SLOT
    LD   E, A
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   D, (HL)                ; D = item_id
    LD   A, B                   ; A = screen row
    LD   BC, STORE_TOTAL_SLOTS
    ADD  HL, BC                 ; si_qty
    LD   E, (HL)                ; E = qty
    ADD  HL, BC                 ; si_p1
    ADD  HL, BC                 ; si_to_hit
    ADD  HL, BC                 ; si_to_dam
    ADD  HL, BC                 ; si_to_ac
    ADD  HL, BC                 ; si_meta
    ADD  HL, BC                 ; si_meta_hi
    LD   C, (HL)                ; C = ego/page byte
    LD   B, E                   ; B = qty
    PUSH AF                     ; save screen row
    LD   A, D
    CALL inv_slot_weight        ; HL = tenths of lb
    POP  BC                     ; B = screen row
    CALL ovl_home_put_col69
    POP  BC

.slot_next:
    INC  C
    LD   A, C
    CP   STORE_MAX_ITEMS
    JR   C, .slot_loop

.draw_menu:
    ; Row 19: "D)ep R)et Q)uit   " at col 1 COL_WHITE + "Gold: " & value COL_YELLOW
    LD   B, STORE_MENU_ROW
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_home_str_menu
    CALL screen_put_str

    LD   B, STORE_MENU_ROW
    LD   C, 21
    LD   E, COL_YELLOW
    LD   HL, ovl_home_str_gold
    CALL screen_put_str

    LD   A, (player_data + PL_GOLD_0)
    LD   L, A
    LD   A, (player_data + PL_GOLD_1)
    LD   H, A
    LD   A, (player_data + PL_GOLD_2)
    LD   E, A
    LD   BC, temp_str_buf
    CALL status_fmt_u24         ; HL = temp_str_buf
    LD   B, STORE_MENU_ROW
    LD   C, 27
    LD   E, COL_YELLOW
    CALL screen_put_str

    ; Row 22: pending feedback
    LD   HL, (ovl_home_msg_ptr)
    LD   A, H
    OR   L
    RET  Z
    LD   B, 22
    LD   C, 1
    LD   A, (ovl_home_msg_attr)
    LD   E, A
    JP   screen_put_str

ovl_home_put_hdr_sp:
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

; ============================================================================
; ovl_home_deposit — List pack A)..V) and move whole stack into empty Home slot
; ============================================================================
ovl_home_deposit:
    CALL screen_clear
    LD   B, 0
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_home_str_dep_title
    CALL screen_put_str
    CALL ovl_home_draw_burden

    LD   A, 1
    LD   (ovl_home_disp_row), A
    LD   C, 0                   ; C = pack slot 0..21
.dep_list:
    LD   E, C
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .dep_list_next

    LD   A, (ovl_home_disp_row)
    LD   B, A                   ; B = compact screen row (1..22)
    INC  A
    LD   (ovl_home_disp_row), A
    LD   D, COL_LGREY
    LD   A, 1
    CALL ovl_home_put_hdr_sp

    PUSH BC
    LD   A, C
    LD   DE, line_buf
    CALL item_format_inv_slot
    XOR  A
    LD   (line_buf + 63), A
    POP  BC
    PUSH BC
    LD   C, 4
    LD   E, COL_LGREY
    LD   HL, line_buf
    CALL screen_put_str
    POP  BC

    PUSH BC
    LD   D, 0
    LD   E, C                   ; slot 0..21
    LD   A, B                   ; screen row
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   D, (HL)
    LD   HL, inv_qty
    LD   B, 0
    ADD  HL, DE
    LD   B, (HL)
    LD   HL, inv_ego
    ADD  HL, DE
    LD   C, (HL)
    PUSH AF                     ; save screen row
    LD   A, D
    CALL inv_slot_weight
    POP  BC                     ; B = screen row
    CALL ovl_home_put_col69
    POP  BC

.dep_list_next:
    INC  C
    LD   A, C
    CP   MAX_INV_SLOTS
    JR   C, .dep_list

    LD   B, 23
    CALL screen_clear_row
    LD   B, 23
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_home_str_which_dep
    CALL screen_put_str
    CALL screen_flush
    LD   B, 23
    LD   C, 17
    CALL screen_set_cursor

    CALL input_get_key
    CALL ovl_home_is_cancel
    RET  Z

    CALL ovl_home_to_lower
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

.dep_exec:
    LD   A, E
    LD   (ovl_home_slot), A

    ; Find first empty Home slot (no stack merging, no split)
    LD   C, 0
.empty_loop:
    LD   A, C
    ADD  A, OVL_HOME_BASE_SLOT
    LD   E, A
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .put_slot
    INC  C
    LD   A, C
    CP   STORE_MAX_ITEMS
    JR   C, .empty_loop

    ; Home full -> row 22 error + wait for key
    LD   B, 22
    CALL screen_clear_row
    LD   B, 22
    LD   C, 1
    LD   E, COL_RED
    LD   HL, ovl_home_str_full
    CALL screen_put_str
    CALL screen_flush
    JP   input_get_key

.put_slot:
    LD   A, (ovl_home_slot)
    LD   C, A
    LD   B, 0
    LD   HL, inv_qty
    ADD  HL, BC
    LD   D, (HL)                ; whole inventory stack qty
    LD   B, E                   ; B = abs Home slot
    CALL si_copy_from_inv
    LD   A, (ovl_home_slot)
    CALL inv_remove_item
    LD   HL, ovl_home_str_deposited
    LD   A, COL_LGREEN

ovl_home_set_msg_hl:
    LD   (ovl_home_msg_ptr), HL
    LD   (ovl_home_msg_attr), A
    RET

; ============================================================================
; ovl_home_retrieve — Prompt "Which? (a-p)" and move Home slot to pack
; ============================================================================
ovl_home_retrieve:
    LD   B, 20
.clr_bot:
    PUSH BC
    CALL screen_clear_row
    POP  BC
    INC  B
    LD   A, B
    CP   24
    JR   C, .clr_bot
    LD   B, 20
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_home_str_which_ret
    CALL screen_put_str
    CALL screen_flush
    LD   B, 20
    LD   C, 14
    CALL screen_set_cursor

    CALL input_get_key
    CALL ovl_home_is_cancel
    RET  Z

    CALL ovl_home_to_lower
    SUB  'a'
    RET  C
    CP   STORE_MAX_ITEMS
    RET  NC

    LD   C, A                   ; C = sub-slot 0..15
    ADD  A, OVL_HOME_BASE_SLOT
    LD   E, A
    LD   D, 0
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    RET  Z

.ret_exec:
    LD   A, C
    LD   (ovl_home_slot), A

    ; Stage si_*[abs = E] into fi_add_*
    LD   D, 0
    LD   BC, STORE_TOTAL_SLOTS
    LD   HL, si_item_id
    ADD  HL, DE
    LD   A, (HL)
    LD   (fi_add_id), A
    ADD  HL, BC                 ; si_qty
    LD   A, (HL)
    LD   (fi_add_qty), A
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
    JR   C, .ret_ok

    ; CF=0: A = HSTR_UIS_TOO_HEAVY or HSTR_UIS_PACK_FULL -> row 22 error + wait
    CP   HSTR_UIS_TOO_HEAVY
    JR   Z, .ret_heavy
    LD   HL, ovl_home_str_inv_full
    JR   .ret_err
.ret_heavy:
    LD   DE, temp_str_buf
    CALL huff_decode_string     ; HL = temp_str_buf
.ret_err:
    PUSH HL
    LD   B, 22
    CALL screen_clear_row
    POP  HL
    LD   B, 22
    LD   C, 1
    LD   E, COL_RED
    CALL screen_put_str
    CALL screen_flush
    JP   input_get_key

.ret_ok:
    ; Clear all 8 fields of Home slot (no compaction, matching 6502 ui_home.s)
    LD   A, (ovl_home_slot)
    ADD  A, OVL_HOME_BASE_SLOT
    LD   E, A
    LD   D, 0
    LD   BC, STORE_TOTAL_SLOTS
    LD   HL, si_item_id
    ADD  HL, DE
    LD   (HL), FI_EMPTY
    LD   A, 7
.clr_fields:
    ADD  HL, BC
    LD   (HL), 0
    DEC  A
    JR   NZ, .clr_fields

    LD   HL, ovl_home_str_withdrawn
    LD   A, COL_LGREEN
    JP   ovl_home_set_msg_hl

; ============================================================================
; Key helpers
; ============================================================================
ovl_home_is_cancel:
    CP   'q'
    RET  Z
    CP   'Q'
    RET  Z
    CP   KEY_ESC
    RET  Z
    CP   KEY_SPACE
    RET

ovl_home_to_upper:
    CP   'a'
    RET  C
    CP   'z' + 1
    RET  NC
    SUB  0x20
    RET

ovl_home_to_lower:
    CP   'A'
    RET  C
    CP   'Z' + 1
    RET  NC
    ADD  A, 0x20
    RET

; ============================================================================
; Burden Header & Per-Item Weight Helpers (80-col)
; ============================================================================
ovl_home_draw_burden:
    LD   B, 0
    LD   C, 55
    LD   E, COL_LGREY
    LD   HL, ovl_home_str_burden
    CALL screen_put_str

    LD   HL, (inven_weight_lo)
    LD   DE, line_buf
    CALL ovl_home_fmt_tenths
    LD   A, '/'
    LD   (DE), A
    INC  DE
    PUSH DE
    CALL player_weight_limit    ; HL = weight limit (0..3000)
    POP  DE
    CALL ovl_home_fmt_tenths
    LD   HL, ovl_home_str_lb
    LD   BC, 4
    LDIR
    LD   B, 0
    LD   C, 63
    LD   E, COL_WHITE
    LD   HL, line_buf
    JP   screen_put_str

; Input: B = row, HL = weight in tenths of lb
ovl_home_put_col69:
    PUSH BC
    LD   DE, temp_str_buf
    CALL ovl_home_fmt_tenths    ; DE at NUL
    LD   A, E
    SUB  LOW temp_str_buf
    LD   C, A                   ; length of "N.N" (3..6)
    LD   HL, ovl_home_str_lb
    PUSH BC
    LD   BC, 4
    LDIR                        ; append " lb\0"
    POP  BC
    POP  DE                     ; D = row
    LD   A, 74
    SUB  C
    CP   69
    JR   C, .col_clamp
    JR   .col_ok
.col_clamp:
    LD   A, 69
.col_ok:
    LD   B, D
    LD   C, A
    LD   E, COL_LGREY
    LD   HL, temp_str_buf
    JP   screen_put_str

; Format HL (tenths of lb) into DE as "N.N" + NUL, leaving DE at NUL.
ovl_home_fmt_tenths:
    LD   C, 10
    CALL div_hl_c               ; HL = integer part, A = tenths digit 0..9
    PUSH AF
    CALL fmt_u16_dec            ; writes decimal integer at DE, advances DE to NUL
    POP  AF
    EX   DE, HL
    LD   (HL), '.'
    INC  HL
    ADD  A, '0'
    LD   (HL), A
    INC  HL
    LD   (HL), 0
    EX   DE, HL
    RET

; ============================================================================
; Strings
; ============================================================================
ovl_home_str_title:     DB "Home", 0
ovl_home_str_burden:    DB "Burden: ", 0
ovl_home_str_lb:        DB " lb", 0
ovl_home_str_menu:      DB "D)ep R)et Q)uit   ", 0
ovl_home_str_gold:      DB "Gold: ", 0
ovl_home_str_dep_title: DB "Deposit", 0
ovl_home_str_which_dep: DB "Which item? (Q)", 0
ovl_home_str_which_ret: DB "Which? (a-p)", 0
ovl_home_str_full:      DB "Home full!", 0
ovl_home_str_inv_full:  DB "Pack full!", 0
ovl_home_str_deposited: DB "Deposited!", 0
ovl_home_str_withdrawn: DB "Retrieved!", 0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_home.ovl", ovl_start, ovl_end - ovl_start
