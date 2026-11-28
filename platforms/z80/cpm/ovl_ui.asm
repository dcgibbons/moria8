; ovl_ui.asm — Moria8 CP/M Character Sheet, Inventory, Equipment, Look & Symbol Identify
; (OVL_UI = 6, DAT slot 5)
;
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0:  JP ovl_ui_character
;   +3:  JP ovl_ui_inventory
;   +6:  JP ovl_ui_equipment
;   +9:  JP ovl_ui_look
;   +12: JP ovl_ui_identify_sym
;   +15: JP ovl_ui_select_display
;   +18: JP ovl_ui_msg_history
;
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax, DEVICE NOSLOT64K).
; All public entry vectors preserve IX and IY.

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "item_ids_z80.inc"
    DEFINE HUFF_CONSTS_ONLY 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_CONSTS_ONLY
    INCLUDE "main_exp.inc"

    ASSERT (trap_y - trap_x) == 16 && (trap_type - trap_x) == 32, "trap layout mismatch"
    ASSERT (door_state_y - door_state_x) == 16 && (door_state_val - door_state_x) == 32, "door_state layout mismatch"

    ORG  OVL_WINDOW_BASE        ; 0x5600

ovl_start:
    JP   ovl_ui_character
    JP   ovl_ui_inventory
    JP   ovl_ui_equipment
    JP   ovl_ui_look
    JP   ovl_ui_identify_sym
    JP   ovl_ui_select_display
    JP   ovl_ui_msg_history

UCHAR_TITLE_COL     EQU 33
UCHAR_WIZARD_COL    EQU 71
UCHAR_FOOTER_COL    EQU 33
UCHAR_COL_L         EQU 2
UCHAR_COL_NAME      EQU 11
UCHAR_COL_MID       EQU 29
UCHAR_COL_MID_VAL   EQU 38
UCHAR_COL_R         EQU 53
UINV_TITLE_COL      EQU 35
UINV_FOOTER_COL     EQU 33
UEQ_TITLE_COL       EQU 35
UEQ_FOOTER_COL      EQU 33
MSG_HIST_TITLE_COL  EQU 32

; ============================================================================
; +0: ovl_ui_character — Character Info Sheet (80-col 6502 layout parity)
; ============================================================================
ovl_ui_character:
    PUSH IX
    PUSH IY

    CALL screen_hard_clear

    ; Row 0: "Character Info" (+ optional "WIZARD" badge)
    LD   B, 0
    LD   C, UCHAR_TITLE_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_char_title
    CALL screen_put_str

    LD   A, (abi_game_flags)
    LD   HL, zp_game_flags
    OR   (HL)
    BIT  1, A                   ; GAME_FLAG_WIZARD
    JR   Z, .hdr_done
    LD   B, 0
    LD   C, UCHAR_WIZARD_COL
    LD   E, COL_YELLOW
    LD   HL, ovl_ui_str_wizard
    CALL ovl_ui_put_cstr
.hdr_done:

    ; Row 2: Name / Age
    LD   B, 2
    LD   C, UCHAR_COL_L
    LD   HL, ovl_ui_str_lbl_name
    CALL ovl_ui_put_lgrey_cstr
    LD   HL, player_data + PL_NAME
    LD   DE, line_buf
    LD   B, PL_NAME_MAX
    CALL ovl_ui_copy_bounded
    LD   B, 2
    LD   C, UCHAR_COL_NAME
    CALL ovl_ui_put_linebuf_w

    LD   B, 2
    LD   C, UCHAR_COL_MID
    LD   HL, ovl_ui_str_lbl_age
    CALL ovl_ui_put_lgrey_s
    LD   A, (player_data + PL_AGE)
    LD   DE, line_buf
    CALL fmt_u8_dec
    LD   B, 2
    LD   C, UCHAR_COL_MID_VAL
    CALL ovl_ui_put_linebuf_w

    ; Row 3: Race / Height
    LD   B, 3
    LD   C, UCHAR_COL_L
    LD   HL, ovl_ui_str_lbl_race
    CALL ovl_ui_put_lgrey_cstr
    LD   A, (player_data + PL_RACE)
    CP   RACE_COUNT
    JR   C, .race_ok
    XOR  A
.race_ok:
    LD   HL, ovl_ui_race_names
    CALL ovl_ui_nth_str
    LD   B, 3
    LD   C, UCHAR_COL_NAME
    CALL ovl_ui_put_cstr_w

    LD   B, 3
    LD   C, UCHAR_COL_MID
    LD   HL, ovl_ui_str_lbl_ht
    CALL ovl_ui_put_lgrey_s
    LD   A, (player_data + PL_HEIGHT)
    LD   DE, line_buf
    CALL fmt_u8_dec
    LD   A, '"'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   B, 3
    LD   C, UCHAR_COL_MID_VAL
    CALL ovl_ui_put_linebuf_w

    ; Row 4: Class / Weight
    LD   B, 4
    LD   C, UCHAR_COL_L
    LD   HL, ovl_ui_str_lbl_class
    CALL ovl_ui_put_lgrey_cstr
    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .cls_ok
    XOR  A
.cls_ok:
    LD   HL, ovl_ui_class_names
    CALL ovl_ui_nth_str
    LD   B, 4
    LD   C, UCHAR_COL_NAME
    CALL ovl_ui_put_cstr_w

    LD   B, 4
    LD   C, UCHAR_COL_MID
    LD   HL, ovl_ui_str_lbl_wt
    CALL ovl_ui_put_lgrey_s
    LD   A, (player_data + PL_WEIGHT)
    LD   DE, line_buf
    CALL fmt_u8_dec
    LD   HL, ovl_ui_str_lb
    CALL ovl_ui_append_str
    LD   B, 4
    LD   C, UCHAR_COL_MID_VAL
    CALL ovl_ui_put_linebuf_w

    ; Row 5: Title / Depth
    LD   B, 5
    LD   C, UCHAR_COL_L
    LD   HL, ovl_ui_str_lbl_title
    CALL ovl_ui_put_lgrey_s
    LD   A, (player_data + PL_LEVEL)
    OR   A
    JR   Z, .title_l0
    DEC  A
.title_l0:
    LD   B, 0
.title_d5:
    CP   5
    JR   C, .title_emit
    SUB  5
    INC  B
    LD   C, A
    LD   A, B
    CP   7
    LD   A, C
    JR   C, .title_d5
.title_emit:
    LD   A, B
    LD   HL, ovl_ui_rank_names
    CALL ovl_ui_nth_str
    LD   B, 5
    LD   C, UCHAR_COL_NAME
    LD   E, COL_WHITE
    CALL screen_put_str

    LD   B, 5
    LD   C, UCHAR_COL_MID
    LD   HL, ovl_ui_str_lbl_depth
    CALL ovl_ui_put_lgrey_s
    LD   A, (player_data + PL_DLEVEL)
    OR   A
    JR   NZ, .depth_deep
    LD   HL, ovl_ui_str_town
    LD   B, 5
    LD   C, UCHAR_COL_MID_VAL
    LD   E, COL_WHITE
    CALL screen_put_str
    JR   .row5_done
.depth_deep:
    LD   L, A
    LD   H, 0
    LD   A, 50
    CALL mul_hl_a
    LD   DE, line_buf
    CALL fmt_u16_dec
    LD   A, 0x27
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   B, 5
    LD   C, UCHAR_COL_MID_VAL
    CALL ovl_ui_put_linebuf_w
.row5_done:

    ; Row 6: Hunger / Blows
    LD   B, 6
    LD   C, UCHAR_COL_L
    LD   HL, ovl_ui_str_lbl_hunger
    CALL ovl_ui_put_lgrey_s
    LD   A, (player_data + PL_HUNGER)
    CP   4
    JR   C, .hung_ok
    XOR  A
.hung_ok:
    LD   HL, ovl_ui_hunger_names
    CALL ovl_ui_nth_str
    LD   B, 6
    LD   C, UCHAR_COL_NAME
    LD   E, COL_WHITE
    CALL screen_put_str

    LD   B, 6
    LD   C, UCHAR_COL_MID
    LD   HL, ovl_ui_str_lbl_blows
    CALL ovl_ui_put_lgrey_s
    LD   A, (player_data + PL_BLOWS)
    LD   DE, line_buf
    CALL fmt_u8_dec
    LD   HL, ovl_ui_str_rnd
    CALL ovl_ui_append_str
    LD   B, 6
    LD   C, UCHAR_COL_MID_VAL
    CALL ovl_ui_put_linebuf_w

    ; Row 7: Level / AC
    LD   B, 7
    LD   C, UCHAR_COL_L
    LD   HL, ovl_ui_str_lbl_level
    CALL ovl_ui_put_lgrey_cstr
    LD   A, (player_data + PL_LEVEL)
    LD   DE, line_buf
    CALL fmt_u8_dec
    LD   B, 7
    LD   C, UCHAR_COL_NAME
    CALL ovl_ui_put_linebuf_w

    LD   B, 7
    LD   C, UCHAR_COL_MID
    LD   HL, ovl_ui_str_lbl_ac
    CALL ovl_ui_put_lgrey_cstr
    LD   A, (player_data + PL_AC)
    LD   DE, line_buf
    CALL fmt_u8_dec
    LD   B, 7
    LD   C, UCHAR_COL_MID_VAL
    CALL ovl_ui_put_linebuf_w

    ; Rows 2..7 Right col (col 53): 6 Stats "CUR (BASE)"
    LD   B, 0
.stat_loop:
    PUSH BC                     ; B = stat index 0..5
    LD   A, B
    ADD  A, 2
    LD   D, A                   ; D = row 2..7
    LD   A, B
    LD   B, D
    LD   C, UCHAR_COL_R
    PUSH DE
    LD   HL, ovl_ui_stat_names
    CALL ovl_ui_nth_str
    CALL ovl_ui_put_lgrey_cstr
    POP  DE                     ; D = row
    POP  BC                     ; B = stat index
    PUSH BC
    LD   E, B
    LD   C, UCHAR_COL_R + 5
    LD   B, D
    LD   D, 0
    LD   HL, player_data + PL_STR_CUR
    ADD  HL, DE
    LD   A, (HL)
    PUSH HL
    PUSH BC
    PUSH DE
    LD   DE, line_buf
    CALL status_put_stat_val_full
    POP  DE
    POP  BC
    POP  HL
    LD   E, COL_WHITE
    PUSH BC
    PUSH DE
    PUSH HL
    CALL ovl_ui_put_linebuf
    POP  HL
    POP  DE
    POP  BC                     ; B = row, C = start col (58)
    ; Check cur != base
    LD   A, (HL)
    LD   DE, -STAT_COUNT
    ADD  HL, DE
    CP   (HL)
    JR   Z, .stat_next
    LD   DE, line_buf
    EX   DE, HL                 ; HL = line_buf, DE = &base_stat
.st_len:
    LD   A, (HL)
    OR   A
    JR   Z, .st_len_done
    INC  HL
    INC  C
    JR   .st_len
.st_len_done:
    PUSH BC                     ; B = row, C = col right after cur stat
    LD   A, (DE)                ; base stat
    LD   HL, line_buf
    LD   (HL), ' '
    INC  HL
    LD   (HL), '('
    INC  HL
    EX   DE, HL
    CALL status_put_stat_val_full
    LD   HL, line_buf
    XOR  A
.st_end:
    CP   (HL)
    JR   Z, .st_close
    INC  HL
    JR   .st_end
.st_close:
    LD   (HL), ')'
    INC  HL
    LD   (HL), 0
    POP  BC                     ; B = row, C = col right after cur
    LD   E, COL_LGREY
    CALL ovl_ui_put_linebuf
.stat_next:
    POP  BC
    INC  B
    LD   A, B
    CP   STAT_COUNT
    JR   C, .stat_loop

    ; Row 9: HP / Mana / Hit/Dam
    LD   B, 9
    LD   C, UCHAR_COL_L
    LD   HL, ovl_ui_str_lbl_hp
    CALL ovl_ui_put_lgrey_cstr
    LD   DE, line_buf
    LD   HL, (player_data + PL_HP_LO)
    CALL fmt_u16_dec
    LD   A, '/'
    LD   (DE), A
    INC  DE
    LD   HL, (player_data + PL_MHP_LO)
    CALL fmt_u16_dec
    LD   B, 9
    LD   C, UCHAR_COL_NAME
    CALL ovl_ui_put_linebuf_w

    LD   B, 9
    LD   C, UCHAR_COL_MID
    LD   HL, ovl_ui_str_lbl_mana
    CALL ovl_ui_put_lgrey_cstr
    LD   DE, line_buf
    LD   A, (player_data + PL_MANA)
    CALL fmt_u8_dec
    LD   A, '/'
    LD   (DE), A
    INC  DE
    LD   A, (player_data + PL_MAX_MANA)
    CALL fmt_u8_dec
    LD   B, 9
    LD   C, UCHAR_COL_MID_VAL
    CALL ovl_ui_put_linebuf_w

    LD   B, 9
    LD   C, UCHAR_COL_R
    LD   HL, ovl_ui_str_lbl_hitdam
    CALL ovl_ui_put_lgrey_s
    LD   DE, line_buf
    LD   A, (player_data + PL_TOHIT)
    CALL ovl_ui_fmt_signed8
    LD   A, '/'
    LD   (DE), A
    INC  DE
    LD   A, (player_data + PL_TODMG)
    CALL ovl_ui_fmt_signed8
    LD   B, 9
    LD   C, UCHAR_COL_R + 9
    CALL ovl_ui_put_linebuf_w

    ; Row 10: Gold / EXP / Spells
    LD   B, 10
    LD   C, UCHAR_COL_L
    LD   HL, ovl_ui_str_lbl_gold
    CALL ovl_ui_put_lgrey_cstr
    LD   B, 10
    LD   C, UCHAR_COL_NAME
    LD   E, COL_YELLOW
    LD   HL, player_data + PL_GOLD_0
    CALL ovl_ui_put_u24_at

    LD   B, 10
    LD   C, UCHAR_COL_MID
    LD   HL, ovl_ui_str_lbl_exp
    CALL ovl_ui_put_lgrey_cstr
    LD   B, 10
    LD   C, UCHAR_COL_MID_VAL
    LD   E, COL_WHITE
    LD   HL, player_data + PL_XP_0
    CALL ovl_ui_put_u24_at

    ; Row 10 col 53: Spells (spellcasters only)
    LD   A, (player_data + PL_SPELL_TYPE)
    OR   A
    JR   Z, .no_spells
    LD   B, 10
    LD   C, UCHAR_COL_R
    LD   HL, ovl_ui_str_lbl_spells
    CALL ovl_ui_put_lgrey_cstr

    ; Popcount PL_SPELLS_LEARNT_0..3 -> C
    LD   HL, player_data + PL_SPELLS_LEARNT_0
    LD   BC, 0x0400             ; B = 4 bytes, C = 0 set bits
.csk_byte:
    LD   A, (HL)
    INC  HL
    LD   D, 8
.csk_bit:
    RRA
    JR   NC, .csk_nxt
    INC  C
.csk_nxt:
    DEC  D
    JR   NZ, .csk_bit
    DJNZ .csk_byte

    LD   DE, line_buf
    LD   A, C
    CALL fmt_u8_dec
    LD   A, '/'
    LD   (DE), A
    INC  DE
    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .sp_cls_ok
    XOR  A
.sp_cls_ok:
    LD   C, A
    LD   B, 0
    LD   HL, ovl_ui_class_spell_total
    ADD  HL, BC
    LD   A, (HL)
    CALL fmt_u8_dec
    LD   B, 10
    LD   C, UCHAR_COL_R + 8
    CALL ovl_ui_put_linebuf_w
.no_spells:

    ; Row 12: Sex / SC (col 22, matching existing CP/M layout cleanly between row 10 & row 18)
    LD   B, 12
    LD   C, 22
    LD   HL, ovl_ui_str_lbl_sex
    CALL ovl_ui_put_lgrey_cstr
    LD   A, (player_data + PL_FLAGS)
    AND  PLF_MALE
    LD   HL, ovl_ui_str_male
    JR   NZ, .put_sex
    LD   HL, ovl_ui_str_female
.put_sex:
    LD   DE, line_buf
    CALL ovl_ui_append_str
    LD   B, 12
    LD   C, 22 + 5
    CALL ovl_ui_put_linebuf_w

    LD   A, (player_data + PL_FLAGS)
    AND  PLF_MALE
    LD   C, 22 + 5 + 4
    JR   NZ, .sc_col_ok
    LD   C, 22 + 5 + 6
.sc_col_ok:
    PUSH BC
    LD   B, 12
    LD   HL, ovl_ui_str_lbl_sc
    CALL ovl_ui_put_lgrey_cstr
    POP  BC
    LD   A, C
    ADD  A, 6
    LD   C, A
    PUSH BC
    LD   A, (player_data + PL_SOCIAL_CLASS)
    LD   DE, line_buf
    CALL fmt_u8_dec
    POP  BC
    LD   B, 12
    CALL ovl_ui_put_linebuf_w

    ; Rows 13..16: 4x40 Background lines
    LD   C, 0
    LD   HL, player_background
.bg_loop:
    PUSH BC
    PUSH HL
    LD   DE, line_buf
    LD   B, 40
    CALL ovl_ui_copy_bounded
    LD   A, C
    ADD  A, 13
    LD   B, A
    LD   C, 22
    LD   E, COL_LGREY
    CALL ovl_ui_put_linebuf
    POP  HL
    LD   DE, 40
    ADD  HL, DE
    POP  BC
    INC  C
    LD   A, C
    CP   4
    JR   C, .bg_loop

    ; Rows 18..20: 7 Derived Skills + Next XP
    CALL ovl_ui_draw_skills

    ; Row 22: "Press any key"
    LD   B, 22
    LD   C, UCHAR_FOOTER_COL
    LD   HL, ovl_ui_str_press_key
    CALL ovl_ui_put_lgrey_cstr
    LD   B, 22
    LD   C, UCHAR_FOOTER_COL + 13
    JP   ovl_ui_wait_exit

; ============================================================================
; +3: ovl_ui_inventory — Carried Pack View (6502 80-col ui_inventory.s parity)
; ============================================================================
ovl_ui_inventory:
    PUSH IX
    PUSH IY

    CALL screen_hard_clear
    ; Count occupied slots: 22-item full pack omits dashes so 'v)' fits above row 23 footer
    LD   HL, inv_item_id
    LD   B, MAX_INV_SLOTS
    LD   D, 0
.cnt_lp:
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .cnt_nx
    INC  D
.cnt_nx:
    INC  HL
    DJNZ .cnt_lp
    LD   A, D
    CP   MAX_INV_SLOTS
    LD   A, 2
    JR   C, .not_full
    DEC  A
    JR   .set_base
.not_full:
    LD   B, 1
    LD   C, UINV_TITLE_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_dash9
    CALL screen_put_str
    LD   A, 2
.set_base:
    LD   (ovl_ui_base_row), A
    LD   B, 0
    LD   C, UINV_TITLE_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_inv_hdr
    CALL ovl_ui_put_cstr
    CALL ovl_ui_draw_burden

    XOR  A
    LD   (ovl_ui_tmp0), A       ; visible ordinal (0..21)
    LD   C, 0                   ; inv slot 0..21
.inv_loop:
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .inv_next

    LD   A, (ovl_ui_tmp0)
    INC  A
    LD   (ovl_ui_tmp0), A
    DEC  A
    LD   D, A                   ; visible ordinal
    LD   HL, ovl_ui_base_row
    ADD  A, (HL)
    LD   B, A                   ; row = base_row + visible

    PUSH BC
    LD   A, D
    ADD  A, 'a'
    CALL ovl_ui_put_slot_prefix
    POP  BC

    PUSH BC
    LD   A, C
    LD   DE, line_buf
    CALL item_format_inv_slot
    XOR  A
    LD   (line_buf + 63), A
    POP  BC
    PUSH BC
    LD   E, COL_LGREY
    LD   C, 4
    LD   HL, line_buf
    CALL screen_put_str
    POP  BC
    PUSH BC
    LD   A, B
    LD   B, C                   ; slot 0..21
    LD   C, A                   ; screen row
    CALL ovl_ui_put_slot_col69
    POP  BC

.inv_next:
    INC  C
    LD   A, C
    CP   MAX_INV_SLOTS
    JR   C, .inv_loop

    LD   A, (ovl_ui_tmp0)
    OR   A
    JR   NZ, .inv_wait
    LD   B, 2
    LD   C, 1
    LD   HL, ovl_ui_str_nothing
    CALL ovl_ui_put_lgrey_cstr

.inv_wait:
    LD   B, SCREEN_ROWS - 1
    LD   C, UINV_FOOTER_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_press_key
    CALL screen_put_str
    LD   B, SCREEN_ROWS - 1
    LD   C, UINV_FOOTER_COL + 13
    JP   ovl_ui_wait_exit

; ============================================================================
; +6: ovl_ui_equipment — Equipped Slots View (6502 80-col ui_equipment.s parity)
; ============================================================================
ovl_ui_equipment:
    PUSH IX
    PUSH IY

    CALL screen_hard_clear
    LD   B, 0
    LD   C, UEQ_TITLE_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_eq_hdr
    CALL ovl_ui_put_cstr
    CALL ovl_ui_draw_burden
    LD   B, 1
    LD   C, UEQ_TITLE_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_dash9
    CALL screen_put_str

    XOR  A
    LD   (ovl_ui_tmp0), A       ; visible ordinal for non-empty rows
    LD   C, 0                   ; equip offset 0..11
.eq_loop:
    LD   A, C
    ADD  A, 2
    LD   B, A                   ; screen row 2..13

    LD   A, C
    ADD  A, EQUIP_WEAPON
    LD   E, A
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    PUSH AF                     ; remember Z (empty vs filled)
    JR   Z, .eq_lbl_only

    PUSH BC
    PUSH DE
    LD   HL, ovl_ui_tmp0
    LD   A, (HL)
    INC  (HL)
    ADD  A, 'a'
    CALL ovl_ui_put_slot_prefix
    POP  DE
    POP  BC

.eq_lbl_only:
    PUSH BC
    PUSH DE
    LD   A, C
    LD   HL, ovl_ui_eq_labels
    CALL ovl_ui_nth_str
    LD   C, 4
    CALL ovl_ui_put_lgrey_cstr
    POP  DE
    POP  BC
    POP  AF
    JR   NZ, .eq_has_item

    PUSH BC
    LD   C, 12
    LD   E, COL_DGREY
    LD   HL, ovl_ui_str_eq_none
    CALL ovl_ui_put_cstr
    POP  BC
    JR   .eq_next

.eq_has_item:
    PUSH BC
    LD   A, E                   ; EQUIP_WEAPON + offset
    LD   DE, line_buf
    CALL item_format_inv_slot
    XOR  A
    LD   (line_buf + 55), A
    POP  BC
    PUSH BC
    LD   C, 12
    CALL ovl_ui_put_linebuf_w
    POP  BC
    PUSH BC
    LD   A, B                   ; screen row
    LD   B, C
    LD   C, A                   ; C = screen row
    LD   A, B
    ADD  A, EQUIP_WEAPON
    LD   B, A                   ; B = slot index
    CALL ovl_ui_put_slot_col69
    POP  BC

.eq_next:
    INC  C
    LD   A, C
    CP   MAX_EQUIP_SLOTS
    JR   C, .eq_loop

    LD   B, SCREEN_ROWS - 1
    LD   C, UEQ_FOOTER_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_press_key
    CALL screen_put_str
    LD   B, SCREEN_ROWS - 1
    LD   C, UEQ_FOOTER_COL + 13
    JP   ovl_ui_wait_exit

; ============================================================================
; +9: ovl_ui_look — 'x' Look along a prompted direction (matches core/6502/do_look)
; Prompts "Which direction? ", scans along that ray skipping empty visible
; floor tiles, and prints the first visible/detected monster, floor item,
; glyph, visible terrain (with clear LOS), or "You see nothing special.".
; Free action: consumes 0 turns and leaves MSG_ROW0 intact on return.
; ============================================================================
ovl_ui_look:
    PUSH IX
    PUSH IY

    CALL msg_clear
    CALL tramp_modal_direction_prompt
    JP   NC, .exit

    ; dir (0..7) in A -> fetch signed step deltas from resident dir_dx/dir_dy
    LD   E, A
    LD   D, 0
    LD   HL, dir_dx
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_ui_look_dx), A
    LD   HL, dir_dy
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_ui_look_dy), A

.scan:
    LD   A, (df_target_x)
    CP   MAP_COLS
    JP   NC, .nothing
    LD   C, A
    LD   A, (df_target_y)
    CP   MAP_ROWS
    JP   NC, .nothing
    LD   B, A                   ; B = y, C = x

    CALL map_get_tile
    LD   (ovl_ui_tmp0), A

    ; 1. Monster perception runs before terrain visibility (TRN-001 / MON-001)
    BIT  0, A                   ; FLAG_OCCUPIED
    JR   Z, .no_monster
    CALL ovl_ui_find_vis_monster
    JR   NC, .no_monster
    CALL ovl_ui_flash_target
    CALL ovl_ui_fmt_monster_see
    LD   HL, line_buf
    CALL msg_print_str
    JP   .exit

.no_monster:
    ; 2. Must be currently visible (revealed FLAG_LIT or within light radius)
    CALL ovl_ui_look_is_visible
    JR   C, .visible
    LD   A, (ovl_ui_tmp0)
    AND  TILE_TYPE_MASK
    JR   Z, .step               ; empty floor outside light -> keep scanning
    JP   .nothing

.visible:
    ; 3. Visibility predicate can light rooms; look still requires clear LOS
    PUSH BC
    LD   D, B
    LD   E, C                   ; (E, D) = target (x, y)
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    CALL los_check              ; CF=1 clear, CF=0 blocked
    POP  BC
    JP   NC, .nothing

    ; 4. Non-floor terrain (authoritative over floor items)
    LD   A, (ovl_ui_tmp0)
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_OPEN
    JR   NZ, .chk_closed
    LD   A, HSTR_DL_OPEN_DOOR
    JR   .flash_print_huff
.chk_closed:
    CP   TILE_DOOR_CLOSED
    JR   NZ, .chk_sdn
    LD   A, HSTR_DL_CLOSED_DOOR
    JR   .flash_print_huff
.chk_sdn:
    CP   TILE_STAIRS_DN
    JR   NZ, .chk_sup
    LD   A, HSTR_DL_STAIRS_DN
    JR   .flash_print_huff
.chk_sup:
    CP   TILE_STAIRS_UP
    JR   NZ, .chk_trap
    LD   A, HSTR_DL_STAIRS_UP
    JR   .flash_print_huff
.chk_trap:
    CP   TILE_TRAP
    JR   NZ, .chk_rubble
    LD   A, HSTR_DL_TRAP
    JR   .flash_print_huff
.chk_rubble:
    CP   TILE_RUBBLE
    JR   NZ, .chk_floor
    LD   A, HSTR_DL_RUBBLE
    JR   .flash_print_huff
.chk_floor:
    CP   TILE_FLOOR
    JR   Z, .on_floor
    LD   A, HSTR_DL_WALL
    JR   .flash_print_huff

.on_floor:
    ; 5. Floor item (with chest state suffix matching 6502 chest_look_suffix_id)
    CALL ovl_ui_find_floor_item
    JR   NC, .chk_glyph
    CALL ovl_ui_flash_target
    CALL ovl_ui_fmt_floor_item_see
    LD   HL, line_buf
    CALL msg_print_str
    JR   .exit

.chk_glyph:
    CALL ovl_ui_check_glyph
    JR   NC, .step
    LD   A, HSTR_PMU_GLYPH_OK
    JR   .flash_print_huff

.step:
    LD   A, (ovl_ui_look_dx)
    LD   HL, df_target_x
    ADD  A, (HL)
    LD   (HL), A
    LD   A, (ovl_ui_look_dy)
    LD   HL, df_target_y
    ADD  A, (HL)
    LD   (HL), A
    JP   .scan

.flash_print_huff:
    PUSH AF
    CALL ovl_ui_flash_target
    POP  AF
    JR   .print_huff
.nothing:
    LD   A, HSTR_DL_NOTHING
.print_huff:
    CALL msg_print_huff
.exit:
    POP  IY
    POP  IX
    RET

; Flash (df_target_x, df_target_y) in reverse video if inside viewport.
; Preserves: AF, BC, DE, HL, IX, IY.
ovl_ui_flash_target:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    LD   A, (df_target_y)
    LD   HL, abi_view_y
    SUB  (HL)
    CP   VIEWPORT_H
    JR   NC, .lft_done
    ADD  A, VIEWPORT_Y
    LD   B, A                   ; B = screen row
    LD   A, (df_target_x)
    LD   HL, abi_view_x
    SUB  (HL)
    CP   VIEWPORT_W
    JR   NC, .lft_done
    ADD  A, VIEWPORT_X
    LD   C, A                   ; C = screen col

    ; Shadow offset = row * 80 + col
    LD   L, B
    LD   H, 0
    ADD  HL, HL                 ; *2
    ADD  HL, HL                 ; *4
    ADD  HL, HL                 ; *8
    ADD  HL, HL                 ; *16
    LD   E, L
    LD   D, H
    ADD  HL, HL                 ; *32
    ADD  HL, HL                 ; *64
    ADD  HL, DE                 ; *80
    LD   E, C
    LD   D, 0
    ADD  HL, DE                 ; row * 80 + col

    PUSH BC                     ; save (row, col)
    LD   DE, CPM_CHAR_SHADOW_BASE
    PUSH HL
    ADD  HL, DE
    LD   D, (HL)                ; D = saved char
    POP  HL
    LD   BC, CPM_COLOR_SHADOW_BASE
    ADD  HL, BC
    LD   A, (HL)
    AND  0x7F                   ; A = saved attr
    LD   E, A
    POP  BC                     ; B = row, C = col
    PUSH BC
    PUSH DE                     ; D = saved char, E = saved attr

    LD   A, E
    XOR  CPM_ATTR_REVERSE
    LD   E, A
    LD   A, '*'
    CALL screen_put_char
    CALL screen_flush

    ; Bounded delay loop (~16 * 1024 iterations)
    LD   B, 16
.lft_wait_o:
    LD   DE, 0x0400
.lft_wait_i:
    DEC  DE
    LD   A, D
    OR   E
    JR   NZ, .lft_wait_i
    DJNZ .lft_wait_o

    POP  DE                     ; D = saved char, E = saved attr
    POP  BC                     ; B = row, C = col
    LD   A, D
    CALL screen_put_char
    CALL screen_flush
.lft_done:
    POP  HL
    POP  DE
    POP  BC
    POP  AF
    RET

; Check if (B=y, C=x) with tile byte (ovl_ui_tmp0) is visible (6502 los_is_visible):
;   (FLAG_LIT | FLAG_VISITED) set, OR Chebyshev distance <= effective light radius.
; Preserves: BC, IX, IY. Output: CF = 1 visible, CF = 0 not visible.
ovl_ui_look_is_visible:
    LD   A, (ovl_ui_tmp0)
    AND  FLAG_LIT | FLAG_VISITED
    CP   FLAG_LIT | FLAG_VISITED
    JR   Z, .yes
    LD   A, (abi_player_x)
    SUB  C
    JR   NC, .dx_ok
    NEG
.dx_ok:
    LD   H, A
    LD   A, (abi_player_y)
    SUB  B
    JR   NC, .dy_ok
    NEG
.dy_ok:
    CP   H
    JR   NC, .have_max
    LD   A, H
.have_max:
    LD   H, A                   ; H = max(|dx|, |dy|)
    LD   A, (inv_item_id + EQUIP_LIGHT)
    INC  A
    JR   Z, .rad_ok
    LD   A, (inv_p1 + EQUIP_LIGHT)
    OR   A
    JR   Z, .cmp_rad            ; burnt out light -> radius 0
.rad_ok:
    LD   A, (abi_light_rad)
.cmp_rad:
    CP   H                      ; rad >= dist -> CF=0 -> CCF yields CF=1
    CCF
    RET
.yes:
    SCF
    RET

; Format floor item slot A into line_buf as "You see <item>[ (<chest state>)]."
ovl_ui_fmt_floor_item_see:
    LD   C, A                   ; preserve slot index in C
    PUSH BC
    LD   DE, line_buf
    LD   HL, ovl_ui_str_you_see
    CALL ovl_ui_append_str      ; DE -> end of "You see "
    POP  BC
    PUSH BC
    PUSH DE
    LD   A, C
    LD   DE, temp_str_buf
    CALL item_format_floor_slot ; temp_str_buf = formatted item
    POP  DE
    LD   HL, temp_str_buf
    ; Always emit "You see a <name>." without qty/gold prefix or vowel "an" (6502 player_move.s:456)
    LD   A, (HL)
    SUB  '0'
    CP   10
    JR   NC, .fmt_fi_a
.fmt_fi_skip_num:
    INC  HL
    LD   A, (HL)
    SUB  '0'
    CP   10
    JR   C, .fmt_fi_skip_num
    LD   A, (HL)
    CP   ' '
    JR   NZ, .fmt_fi_a
    INC  HL
.fmt_fi_a:
    LD   A, 'a'
    LD   (DE), A
    INC  DE
    LD   A, ' '
    LD   (DE), A
    INC  DE
.fmt_fi_append:
    CALL ovl_ui_append_str      ; append item text, DE -> NUL
    POP  BC                     ; C = slot, B = 0
    LD   B, 0
    LD   HL, fi_meta_hi
    ADD  HL, BC
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    CALL item_get_category_a
    CP   ICAT_CHEST
    JR   NZ, .done_item
    LD   HL, fi_p1
    ADD  HL, BC
    LD   A, (HL)
    CALL ovl_ui_chest_suffix_id
    OR   A
    JR   Z, .done_item
    PUSH DE
    LD   DE, temp_str_buf
    CALL huff_decode_string
    POP  DE
    JR   C, .done_item
    LD   HL, temp_str_buf
    CALL ovl_ui_append_str
.done_item:
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    RET

; Map chest fi_p1 byte A -> chest look suffix HSTR_CHEST_SFX_* (0 = none),
; matching core/6502/player_move.s::chest_look_suffix_id.
ovl_ui_chest_suffix_id:
    BIT  7, A                   ; CHEST_P1_OPENED
    JR   Z, .not_open
    LD   A, HSTR_CHEST_SFX_EMPTY
    RET
.not_open:
    LD   B, A
    AND  CHEST_P1_TRAP_MASK
    JR   Z, .chk_locked
    BIT  6, B                   ; CHEST_P1_TRAP_FOUND
    JR   Z, .chk_locked
    LD   A, HSTR_CHEST_SFX_TRAPPED
    RET
.chk_locked:
    BIT  0, B                   ; CHEST_P1_LOCKED
    JR   Z, .chk_disarmed
    LD   A, HSTR_CHEST_SFX_LOCKED
    RET
.chk_disarmed:
    BIT  6, B                   ; CHEST_P1_TRAP_FOUND
    JR   Z, .none
    LD   A, HSTR_CHEST_SFX_DISARMED
    RET
.none:
    XOR  A
    RET

; Scan monster_table for (df_target_x, df_target_y) with MF_VISIBLE|MF_DETECTED.
ovl_ui_find_vis_monster:
    PUSH BC
    LD   HL, monster_table
    LD   B, MAX_MONSTERS
.lp:
    LD   A, (df_target_x)
    CP   (HL)
    JR   NZ, .nxt
    INC  HL
    LD   A, (df_target_y)
    CP   (HL)
    DEC  HL
    JR   NZ, .nxt
    PUSH HL
    INC  HL                     ; +1 MX_Y
    INC  HL                     ; +2 MX_TYPE
    LD   C, (HL)
    INC  HL                     ; +3 MX_HP_LO
    INC  HL                     ; +4 MX_HP_HI
    INC  HL                     ; +5 MX_FLAGS
    LD   A, (HL)
    POP  HL
    AND  0x18                   ; MF_VISIBLE | MF_DETECTED
    JR   Z, .nxt
    LD   A, C
    CP   MAX_CREATURES
    JR   NC, .nxt
    POP  BC
    SCF
    RET
.nxt:
    LD   DE, MONSTER_ENTRY_SIZE
    ADD  HL, DE
    DJNZ .lp
    POP  BC
    OR   A
    RET

; Format "You see a <name>." for creature type A (0..39) into line_buf,
; matching core/6502/player_move.s::dl_print_you_see (HSTR_DL_YOU_SEE).
ovl_ui_fmt_monster_see:
    LD   C, A
    PUSH BC
    LD   A, HSTR_DL_YOU_SEE
    LD   DE, line_buf
    CALL huff_decode_string
    EX   DE, HL                 ; HL = line_buf
    LD   C, B
    LD   B, 0
    ADD  HL, BC
    EX   DE, HL                 ; DE -> NUL after "You see a "
    POP  BC
    LD   A, C
    CP   MAX_DUNGEON_CREATURES
    JR   NC, .town_cre
    LD   L, A
    LD   H, 0
    LD   A, TIER_NAME_SIZE
    PUSH DE
    CALL mul_hl_a
    POP  DE
    LD   BC, tier_name_pool
    ADD  HL, BC
    LD   A, (HL)
    CP   0x20
    JR   C, .fallback_mon
    CP   0x7F
    JR   NC, .fallback_mon
.emit_name:
    CALL ovl_ui_append_str
    JR   .done_mon
.town_cre:
    SUB  TOWN_CREATURE_BASE
    CP   TOWN_CREATURE_COUNT
    JR   NC, .fallback_mon
    LD   HL, ovl_ui_town_cre_names
    CALL ovl_ui_nth_str
    JR   .emit_name
.fallback_mon:
    LD   HL, ovl_ui_str_a_mon
    CALL ovl_ui_append_str
.done_mon:
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    RET

ovl_ui_find_floor_item:
    PUSH BC
    PUSH DE
    LD   C, 0
.lp:
    LD   B, 0
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .nxt
    LD   DE, MAX_FLOOR_ITEMS
    ADD  HL, DE                 ; fi_x
    LD   A, (df_target_x)
    CP   (HL)
    JR   NZ, .nxt
    ADD  HL, DE                 ; fi_y
    LD   A, (df_target_y)
    CP   (HL)
    JR   NZ, .nxt
    LD   A, C
    POP  DE
    POP  BC
    SCF
    RET
.nxt:
    INC  C
    LD   A, C
    CP   MAX_FLOOR_ITEMS
    JR   C, .lp
    POP  DE
    POP  BC
    OR   A
    RET

ovl_ui_check_glyph:
    PUSH BC
    LD   C, 0
.lp:
    LD   B, 0
    LD   HL, glyph_active
    ADD  HL, BC
    LD   A, (HL)
    OR   A
    JR   Z, .nxt
    LD   HL, glyph_x
    ADD  HL, BC
    LD   A, (df_target_x)
    CP   (HL)
    JR   NZ, .nxt
    LD   HL, glyph_y
    ADD  HL, BC
    LD   A, (df_target_y)
    CP   (HL)
    JR   NZ, .nxt
    POP  BC
    SCF
    RET
.nxt:
    INC  C
    LD   A, C
    CP   MAX_GLYPHS
    JR   C, .lp
    POP  BC
    OR   A
    RET

; ============================================================================
; +12: ovl_ui_identify_sym — '/' Recall which? prompt (cmd_recall_view parity)
; Output: CF = 1 iff full-screen Recall view was drawn (caller must redraw)
; ============================================================================
ovl_ui_identify_sym:
    PUSH IX
    PUSH IY

    CALL msg_clear
    LD   B, MSG_ROW0
    LD   C, 0
    LD   HL, ovl_ui_str_rcl_prompt
    CALL ovl_ui_put_cstr_w
    CALL screen_flush
    LD   B, MSG_ROW0
    LD   C, 14
    CALL screen_set_cursor

    CALL input_get_key
    ; Accept ASCII letters 'A'..'Z' and 'a'..'z' only (core/6502/recall_key_to_screen_code)
    CP   'A'
    JR   C, .not_shown
    CP   'Z' + 1
    JR   C, .do_recall
    CP   'a'
    JR   C, .not_shown
    CP   'z' + 1
    JR   NC, .not_shown
.do_recall:
    CALL tramp_death_recall     ; A = letter -> CF=1 displayed, CF=0 none
    JR   NC, .not_shown
    CALL screen_hard_clear
    CALL status_mark_dirty
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    SCF
    POP  IY
    POP  IX
    RET
.not_shown:
    LD   B, MSG_ROW0
    CALL screen_clear_row
    CALL msg_clear
    CALL screen_flush
    OR   A
    POP  IY
    POP  IX
    RET

; ============================================================================
; +15: ovl_ui_select_display — Prompt-time '?' pack/equipment selector
; Reads piw_filter, piw_visible_count, piw_visible_slots; returns key in A.
; Matches core/6502/ui_inventory.s::ui_inv_select_display & ui_equipment.s.
; ============================================================================
ovl_ui_select_display:
    PUSH IX
    PUSH IY

    CALL screen_hard_clear
    LD   A, (piw_filter)
    CP   PIW_FILTER_EQUIP
    JP   NZ, .sel_inv

    ; Equipment view with all 12 labeled slots and "(none)" for empties
    LD   B, 0
    LD   C, UEQ_TITLE_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_eq_hdr
    CALL ovl_ui_put_cstr
    CALL ovl_ui_draw_burden
    LD   B, 1
    LD   C, UEQ_TITLE_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_dash9
    CALL screen_put_str

    XOR  A
    LD   (ovl_ui_tmp0), A
    LD   C, 0
.seq_lp:
    LD   A, C
    ADD  A, 2
    LD   B, A
    ADD  A, EQUIP_WEAPON - 2
    LD   E, A
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    CP   FI_EMPTY
    PUSH AF
    JR   Z, .seq_lbl
    PUSH BC
    PUSH DE
    LD   HL, ovl_ui_tmp0
    LD   A, (HL)
    INC  (HL)
    ADD  A, 'a'
    CALL ovl_ui_put_slot_prefix
    POP  DE
    POP  BC
.seq_lbl:
    PUSH BC
    PUSH DE
    LD   A, C
    LD   HL, ovl_ui_eq_labels
    CALL ovl_ui_nth_str
    LD   C, 4
    CALL ovl_ui_put_lgrey_cstr
    POP  DE
    POP  BC
    POP  AF
    JR   NZ, .seq_item
    PUSH BC
    LD   C, 12
    LD   E, COL_DGREY
    LD   HL, ovl_ui_str_eq_none
    CALL ovl_ui_put_cstr
    POP  BC
    JR   .seq_nx
.seq_item:
    PUSH BC
    LD   A, E
    LD   DE, line_buf
    CALL item_format_inv_slot
    XOR  A
    LD   (line_buf + 55), A
    POP  BC
    PUSH BC
    LD   C, 12
    CALL ovl_ui_put_linebuf_w
    POP  BC
    PUSH BC
    LD   A, B                   ; screen row
    LD   B, C
    LD   C, A                   ; C = screen row
    LD   A, B
    ADD  A, EQUIP_WEAPON
    LD   B, A                   ; B = slot index
    CALL ovl_ui_put_slot_col69
    POP  BC
.seq_nx:
    INC  C
    LD   A, C
    CP   MAX_EQUIP_SLOTS
    JR   C, .seq_lp
    JP   .sel_ftr_default

.sel_inv:
    LD   B, 0
    LD   C, UINV_TITLE_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_inv_hdr
    CALL ovl_ui_put_cstr
    CALL ovl_ui_draw_burden
    LD   A, (piw_visible_count)
    OR   A
    JR   NZ, .sinv_nonempty
    LD   B, 1
    LD   C, UINV_TITLE_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_dash9
    CALL screen_put_str
    LD   B, 2
    LD   C, 1
    LD   HL, ovl_ui_str_nothing
    CALL ovl_ui_put_lgrey_cstr
    JP   .sel_ftr
.sinv_nonempty:
    CP   MAX_INV_SLOTS
    LD   B, 2
    JR   C, .sinv_dash
    DEC  B                      ; 22 items: start at row 1 (rows 1..22) so v) fits above row 23 footer
    JR   .sinv_go
.sinv_dash:
    PUSH BC
    LD   B, 1
    LD   C, UINV_TITLE_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_dash9
    CALL screen_put_str
    POP  BC
.sinv_go:
    LD   A, B
    LD   (ovl_ui_base_row), A
    LD   A, (piw_visible_count)
    LD   B, A
    LD   C, 0
.sinv_lp:
    LD   A, C
    CP   B
    JR   NC, .sel_ftr
    LD   HL, ovl_ui_base_row
    ADD  A, (HL)
    CP   SCREEN_ROWS - 1
    JR   NC, .sel_ftr
    PUSH BC
    LD   B, A                   ; row = base_row + idx
    LD   A, C
    ADD  A, 'a'
    CALL ovl_ui_put_slot_prefix
    POP  BC
    PUSH BC
    LD   E, C
    LD   D, 0
    LD   HL, piw_visible_slots
    ADD  HL, DE
    LD   A, (HL)
    PUSH AF                     ; save slot id
    LD   DE, line_buf
    CALL item_format_inv_slot
    XOR  A
    LD   (line_buf + 63), A
    POP  DE                     ; D = slot id
    POP  BC
    PUSH BC
    PUSH DE
    LD   A, C
    LD   HL, ovl_ui_base_row
    ADD  A, (HL)
    LD   B, A
    LD   C, 4
    LD   E, COL_LGREY
    LD   HL, line_buf
    CALL screen_put_str
    POP  DE                     ; D = slot id
    POP  BC
    PUSH BC
    LD   A, C
    LD   HL, ovl_ui_base_row
    ADD  A, (HL)
    LD   C, A                   ; C = screen row
    LD   B, D                   ; B = slot id
    CALL ovl_ui_put_slot_col69
    POP  BC
    INC  C
    JR   .sinv_lp

.sel_ftr:
    LD   A, (piw_filter)
    CP   PIW_FILTER_IDENTIFY
    JR   NZ, .sel_ftr_default
    LD   A, HSTR_PIQ_IDENTIFY_PROMPT
    LD   DE, temp_str_buf
    CALL huff_decode_string
    LD   HL, temp_str_buf
.sid_lp:
    LD   A, (HL)
    OR   A
    JR   Z, .sid_put
    CP   '-'
    JR   NZ, .sid_nx
    INC  HL
    LD   A, (piw_visible_count)
    OR   A
    JR   Z, .sid_a
    DEC  A
.sid_a:
    ADD  A, 'a'
    LD   (HL), A
    JR   .sid_put
.sid_nx:
    INC  HL
    JR   .sid_lp
.sid_put:
    LD   B, SCREEN_ROWS - 1
    LD   C, 27
    LD   E, COL_WHITE
    LD   HL, temp_str_buf
    JR   .sel_wait

.sel_ftr_default:
    LD   B, SCREEN_ROWS - 1
    LD   C, 34
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_select_item
.sel_wait:
    CALL screen_put_str
    CALL screen_flush
    CALL input_get_key
    POP  IY
    POP  IX
    RET

; ============================================================================
; +18: ovl_ui_msg_history — Ctrl+P 8-slot message history viewer
; ============================================================================
ovl_ui_msg_history:
    PUSH IX
    PUSH IY

    CALL screen_hard_clear
    ; Draw '+'/'-'/'|' 80x24 border box in COL_GREY
    LD   B, 0
    CALL .mh_hborder
    LD   B, SCREEN_ROWS - 1
    CALL .mh_hborder
    LD   B, 1
.mh_vloop:
    PUSH BC
    LD   C, 0
    LD   A, '|'
    LD   E, COL_GREY
    CALL screen_put_char
    POP  BC
    PUSH BC
    LD   C, SCREEN_COLS - 1
    LD   A, '|'
    LD   E, COL_GREY
    CALL screen_put_char
    POP  BC
    INC  B
    LD   A, B
    CP   SCREEN_ROWS - 1
    JR   C, .mh_vloop

    LD   B, 0
    LD   C, MSG_HIST_TITLE_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_msg_hist
    CALL screen_put_str

    LD   B, SCREEN_ROWS - 1
    LD   C, UCHAR_FOOTER_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_press_key
    CALL screen_put_str

    ; Walk 8 ring slots oldest -> newest starting from msg_hist_idx
    LD   A, (msg_hist_idx)
    AND  MSG_HIST_COUNT - 1
    LD   C, A                   ; C = slot index (0..7)
    LD   B, 2                   ; B = output row (2..)
    LD   D, MSG_HIST_COUNT      ; D = remaining slots
.mh_slot_loop:
    PUSH BC
    PUSH DE
    LD   L, C
    LD   H, 0
    LD   A, MSG_HIST_LEN
    CALL mul_hl_a               ; HL = slot * 80
    LD   DE, msg_history
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    JR   Z, .mh_skip
    CP   ' '
    JR   Z, .mh_skip
    LD   DE, line_buf
    LD   B, SCREEN_COLS - 2
    CALL ovl_ui_copy_bounded
    POP  DE
    POP  BC
    PUSH BC
    PUSH DE
    LD   C, 1
    LD   E, COL_LGREY
    CALL ovl_ui_put_linebuf
    POP  DE
    POP  BC
    INC  B
    JR   .mh_next
.mh_skip:
    POP  DE
    POP  BC
.mh_next:
    INC  C
    LD   A, C
    AND  MSG_HIST_COUNT - 1
    LD   C, A
    DEC  D
    JR   NZ, .mh_slot_loop

    LD   A, B
    CP   2
    JR   NZ, .mh_wait
    LD   B, 2
    LD   C, 2
    LD   E, COL_GREY
    LD   HL, ovl_ui_str_no_msgs
    CALL screen_put_str
.mh_wait:
    LD   B, SCREEN_ROWS - 1
    LD   C, UCHAR_FOOTER_COL + 13
    JP   ovl_ui_wait_exit

.mh_hborder:
    LD   C, 0
.mh_hlp:
    LD   A, C
    OR   A
    JR   Z, .mh_crn
    CP   SCREEN_COLS - 1
    JR   Z, .mh_crn
    LD   A, '-'
    JR   .mh_pch
.mh_crn:
    LD   A, '+'
.mh_pch:
    PUSH BC
    LD   E, COL_GREY
    CALL screen_put_char
    POP  BC
    INC  C
    LD   A, C
    CP   SCREEN_COLS
    JR   C, .mh_hlp
    RET

; ============================================================================
; Shared Local Helpers
; ============================================================================
ovl_ui_wait_exit:
    PUSH BC
    CALL screen_flush
    POP  BC
    CALL screen_set_cursor
    CALL input_get_key
    CALL screen_hard_clear
    CALL status_mark_dirty
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    POP  IY
    POP  IX
    RET

ovl_ui_put_lgrey_s:
    LD   E, COL_LGREY
    JP   screen_put_str

ovl_ui_put_lgrey_cstr:
    LD   E, COL_LGREY
    JP   ovl_ui_put_cstr

; Format signed 8-bit A into (DE) as "+N"/"-N" + NUL, advancing DE past digits.
ovl_ui_fmt_signed8:
    BIT  7, A
    JR   Z, .pos
    NEG
    LD   C, A
    LD   A, '-'
    JR   .go
.pos:
    LD   C, A
    LD   A, '+'
.go:
    LD   (DE), A
    INC  DE
    LD   A, C
    JP   fmt_u8_dec

; ============================================================================
; Burden Header & Per-Item Weight Helpers (80-col)
; ============================================================================
ovl_ui_draw_burden:
    LD   B, 0
    LD   C, 55
    LD   HL, ovl_ui_str_burden
    CALL ovl_ui_put_lgrey_s
    LD   HL, (inven_weight_lo)
    LD   DE, line_buf
    CALL ovl_ui_fmt_tenths
    LD   A, '/'
    LD   (DE), A
    INC  DE
    PUSH DE
    CALL player_weight_limit
    POP  DE
    CALL ovl_ui_fmt_tenths
    LD   HL, ovl_ui_str_lb
    CALL ovl_ui_append_str
    LD   B, 0
    LD   C, 63
    JP   ovl_ui_put_linebuf_w

; Input: B = inv/equip slot (0..TOTAL_INV_SLOTS-1), C = screen row
ovl_ui_put_slot_col69:
    PUSH BC                     ; C = row in C
    LD   E, B
    LD   D, 0
    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    LD   HL, inv_qty
    ADD  HL, DE
    LD   B, (HL)
    LD   HL, inv_ego
    ADD  HL, DE
    LD   C, (HL)
    CALL inv_slot_weight        ; HL = tenths of lb
    LD   DE, temp_str_buf
    CALL ovl_ui_fmt_tenths      ; DE at NUL
    LD   A, E
    SUB  LOW temp_str_buf
    PUSH AF                     ; save number width
    LD   HL, ovl_ui_str_lb
    CALL ovl_ui_append_str
    POP  AF                     ; A = number width
    POP  BC                     ; C = screen row
    LD   B, A                   ; B = number width
    LD   A, 74
    SUB  B
    CP   69
    JR   NC, .col_ok
    LD   A, 69
.col_ok:
    LD   B, C                   ; row
    LD   C, A                   ; col
    LD   E, COL_LGREY
    LD   HL, temp_str_buf
    JP   screen_put_str

ovl_ui_fmt_tenths:
    LD   C, 10
    CALL div_hl_c
    PUSH AF
    CALL fmt_u16_dec
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
; Derived Skills & Next XP Drawer (80-col Character Sheet Rows 18..20)
; ============================================================================
ovl_ui_draw_skills:
    ; Fighting (row 18, col 2)
    LD   B, 18
    LD   C, 2
    LD   HL, ovl_ui_str_fight
    CALL ovl_ui_put_lgrey_s
    LD   A, 0
    CALL ovl_ui_calc_bth_skill
    LD   B, 18
    LD   C, 15
    CALL ovl_ui_put_rating

    ; Bows/Throw (row 19, col 2)
    LD   B, 19
    LD   C, 2
    LD   HL, ovl_ui_str_bows
    CALL ovl_ui_put_lgrey_s
    LD   A, 1
    CALL ovl_ui_calc_bth_skill
    LD   B, 19
    LD   C, 15
    CALL ovl_ui_put_rating

    ; Saving Thrw (row 20, col 2)
    LD   B, 20
    LD   C, 2
    LD   HL, ovl_ui_str_save
    CALL ovl_ui_put_lgrey_s
    LD   A, 2
    CALL ovl_ui_calc_prop_skill
    LD   B, 20
    LD   C, 15
    CALL ovl_ui_put_rating

    ; Stealth (row 18, col 29)
    LD   B, 18
    LD   C, 29
    LD   HL, ovl_ui_str_stealth
    CALL ovl_ui_put_lgrey_s
    CALL player_get_stealth     ; 0..9
    ADD  A, A
    ADD  A, A
    ADD  A, A
    ADD  A, A                   ; * 16 (0..144)
    LD   B, 18
    LD   C, 42
    CALL ovl_ui_put_rating

    ; Searching (row 19, col 29): class[8] + race[4]
    LD   B, 19
    LD   C, 29
    LD   HL, ovl_ui_str_search
    CALL ovl_ui_put_lgrey_s
    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .sr_cls_ok
    XOR  A
.sr_cls_ok:
    LD   L, A
    LD   H, 0
    LD   A, CLASS_PROP_SIZE
    CALL mul_hl_a
    LD   DE, class_properties + 8
    ADD  HL, DE
    LD   C, (HL)
    LD   A, (player_data + PL_RACE)
    CP   RACE_COUNT
    JR   C, .sr_rc_ok
    XOR  A
.sr_rc_ok:
    LD   L, A
    LD   H, 0
    LD   A, RACE_PROP_SIZE
    CALL mul_hl_a
    LD   DE, race_properties + 4
    ADD  HL, DE
    LD   A, (HL)
    ADD  A, C
    BIT  7, A
    JR   Z, .sr_put
    XOR  A
.sr_put:
    LD   DE, line_buf
    CALL fmt_u8_dec
    LD   A, '%'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    LD   B, 19
    LD   C, 42
    CALL ovl_ui_put_linebuf_w

    ; Next XP (row 20, col 29 -> value col 38)
    LD   B, 20
    LD   C, 29
    LD   HL, ovl_ui_str_next
    CALL ovl_ui_put_lgrey_s
    LD   A, (player_data + PL_LEVEL)
    OR   A
    JR   Z, .nxt_max
    CP   40
    JR   NC, .nxt_max
    CALL ovl_ui_calc_xp_thresh  ; E:HL = 24-bit threshold
    LD   BC, line_buf
    CALL status_fmt_u24
    LD   B, 20
    LD   C, 38
    LD   E, COL_WHITE
    CALL screen_put_str
    JR   .nxt_done
.nxt_max:
    LD   B, 20
    LD   C, 38
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_max
    CALL screen_put_str
.nxt_done:

    ; Disarming (row 18, col 56)
    LD   B, 18
    LD   C, 56
    LD   HL, ovl_ui_str_disarm
    CALL ovl_ui_put_lgrey_s
    LD   A, 3
    CALL ovl_ui_calc_prop_skill
    LD   C, A                   ; C = prop skill (0..255)
    LD   A, (player_data + PL_DEX_CUR)
    CP   18
    JR   C, .dx_lo
    LD   A, 18
.dx_lo:
    CP   3
    JR   NC, .dx_ok
    LD   A, 3
.dx_ok:
    SUB  3
    LD   E, A
    LD   D, 0
    LD   HL, ovl_ui_dex_disarm_bonus
    ADD  HL, DE
    LD   A, (HL)
    CALL ovl_ui_add_signed_c    ; A = clamped 0..255
    LD   B, 18
    LD   C, 69
    CALL ovl_ui_put_rating

    ; Infravision (row 19, col 56)
    LD   B, 19
    LD   C, 56
    LD   HL, ovl_ui_str_infra
    CALL ovl_ui_put_lgrey_s
    CALL player_get_infra_range
    OR   A
    JR   NZ, .inf_val
    LD   B, 19
    LD   C, 69
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_none
    JP   screen_put_str
.inf_val:
    LD   DE, line_buf
    CALL fmt_u8_dec
    LD   HL, ovl_ui_str_ft
    CALL ovl_ui_append_str
    LD   B, 19
    LD   C, 69
    JP   ovl_ui_put_linebuf_w

; Input: A = skill idx 0 (Fight) or 1 (Bows) -> A (0..255)
ovl_ui_calc_bth_skill:
    CALL ovl_ui_calc_prop_skill
    LD   C, A                   ; C = base (0..255)
    LD   A, (player_data + PL_TOHIT)
    BIT  7, A
    JR   NZ, .neg_th
    LD   L, A
    LD   H, 0
    LD   E, L
    LD   D, H
    ADD  HL, HL
    ADD  HL, DE                 ; 3 * tohit
    LD   E, C
    LD   D, 0
    ADD  HL, DE
    LD   A, H
    OR   A
    LD   A, L
    RET  Z
    LD   A, 255
    RET
.neg_th:
    NEG
    LD   L, A
    LD   H, 0
    LD   E, L
    LD   D, H
    ADD  HL, HL
    ADD  HL, DE                 ; 3 * |tohit|
    EX   DE, HL                 ; DE = subtrahend
    LD   L, C
    LD   H, 0
    OR   A
    SBC  HL, DE
    LD   A, 0
    RET  C
    LD   A, L
    RET

; Input: A = skill idx 0..3 -> A (0..255)
ovl_ui_calc_prop_skill:
    LD   (ovl_ui_tmp0), A
    LD   E, A
    LD   D, 0
    LD   HL, ovl_ui_ucp_cls_off
    ADD  HL, DE
    LD   C, (HL)                ; class_properties offset
    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .cls_ok
    XOR  A
.cls_ok:
    LD   L, A
    LD   H, 0
    LD   A, CLASS_PROP_SIZE
    CALL mul_hl_a
    LD   B, 0
    ADD  HL, BC
    LD   DE, class_properties
    ADD  HL, DE
    LD   C, (HL)                ; C = class base

    LD   A, (ovl_ui_tmp0)
    LD   E, A
    LD   D, 0
    LD   HL, ovl_ui_ucp_lvl_off
    ADD  HL, DE
    LD   E, (HL)
    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .cls2_ok
    XOR  A
.cls2_ok:
    LD   L, A
    LD   H, 0
    LD   A, 5                   ; CLASS_LVL_SIZE
    PUSH DE
    CALL mul_hl_a
    POP  DE
    ADD  HL, DE
    LD   DE, class_level_adj
    ADD  HL, DE
    LD   L, (HL)
    LD   H, 0
    LD   A, (player_data + PL_LEVEL)
    PUSH BC
    CALL mul_hl_a               ; HL = lvl * adj
    POP  BC
    LD   A, H
    OR   A
    JR   NZ, .cap255
    LD   A, C
    ADD  A, L
    JR   NC, .have_lvl
.cap255:
    LD   A, 255
.have_lvl:
    LD   C, A                   ; C = clamped subtotal

    LD   A, (ovl_ui_tmp0)
    LD   E, A
    LD   D, 0
    LD   HL, ovl_ui_ucp_race_off
    ADD  HL, DE
    LD   E, (HL)
    LD   A, (player_data + PL_RACE)
    CP   RACE_COUNT
    JR   C, .rc_ok
    XOR  A
.rc_ok:
    LD   L, A
    LD   H, 0
    LD   A, RACE_PROP_SIZE
    PUSH DE
    CALL mul_hl_a
    POP  DE
    ADD  HL, DE
    LD   DE, race_properties
    ADD  HL, DE
    LD   A, (HL)                ; signed race mod
ovl_ui_add_signed_c:
    BIT  7, A
    JR   NZ, .neg
    ADD  A, C
    RET  NC
    LD   A, 255
    RET
.neg:
    NEG
    LD   E, A
    LD   A, C
    SUB  E
    RET  NC
    XOR  A
    RET

; Input: A = skill score (0..255), B = row, C = col -> prints rating in COL_WHITE
ovl_ui_put_rating:
    LD   E, 0
.lp:
    CP   18
    JR   C, .emit
    SUB  18
    INC  E
    LD   D, A
    LD   A, E
    CP   7
    LD   A, D
    JR   C, .lp
.emit:
    LD   A, E
    LD   HL, ovl_ui_rating_names
    CALL ovl_ui_nth_str
    LD   E, COL_WHITE
    JP   screen_put_str

; Compute 24-bit XP threshold in E:HL (1 <= level <= 39)
ovl_ui_calc_xp_thresh:
    LD   A, (player_data + PL_EXPFACT)
    OR   A
    JR   NZ, .ef_ok
    LD   A, 100
.ef_ok:
    LD   (ovl_ui_tmp0), A
    LD   A, (player_data + PL_LEVEL)
    CP   29
    JR   NC, .late
    DEC  A
    ADD  A, A
    LD   E, A
    LD   D, 0
    LD   HL, ovl_ui_xp_early
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    CALL .mul_de_ef
    LD   B, 24
    XOR  A
.d24:
    ADD  HL, HL
    RL   C
    RLA
    JR   C, .d_sub
    CP   100
    JR   C, .d_nx
.d_sub:
    SUB  100
    INC  L
.d_nx:
    DJNZ .d24
    LD   E, C
    RET
.late:
    SUB  29
    ADD  A, A
    LD   E, A
    LD   D, 0
    LD   HL, ovl_ui_xp_late
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    CALL .mul_de_ef
    LD   E, C
    RET
.mul_de_ef:
    LD   HL, 0
    LD   C, 0
    LD   A, (ovl_ui_tmp0)
    OR   A
    RET  Z
    LD   B, 8
.mlp:
    ADD  HL, HL
    RL   C
    RLCA
    JR   NC, .mskp
    ADD  HL, DE
    JR   NC, .mskp
    INC  C
.mskp:
    DJNZ .mlp
    RET

ovl_ui_put_cstr_w:
    LD   E, COL_WHITE
ovl_ui_put_cstr:
    PUSH BC
    PUSH DE
    LD   DE, temp_str_buf
    CALL ovl_ui_append_str
    POP  DE
    POP  BC
    LD   HL, temp_str_buf
    JP   screen_put_str

ovl_ui_put_stat_at:
    PUSH BC
    PUSH DE
    LD   A, (HL)
    LD   DE, line_buf
    CALL status_put_stat_val_full
    POP  DE
    POP  BC
    JR   ovl_ui_put_linebuf

ovl_ui_put_linebuf_w:
    LD   E, COL_WHITE
ovl_ui_put_linebuf:
    LD   HL, line_buf
    JP   screen_put_str

ovl_ui_put_u24_at:
    PUSH BC
    PUSH DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    INC  HL
    LD   A, (HL)
    EX   DE, HL
    LD   E, A
    LD   BC, line_buf
    CALL status_fmt_u24
    POP  DE
    POP  BC
    JR   ovl_ui_put_linebuf

ovl_ui_put_slot_prefix:
    LD   C, 1
    LD   E, COL_LGREY
    PUSH BC
    CALL screen_put_char
    POP  BC
    LD   C, 2
    LD   A, ')'
    LD   E, COL_LGREY
    PUSH BC
    CALL screen_put_char
    POP  BC
    LD   C, 3
    LD   A, ' '
    LD   E, COL_LGREY
    JP   screen_put_char

ovl_ui_copy_bounded:
.lp:
    LD   A, (HL)
    OR   A
    JR   Z, .done
    LD   (DE), A
    INC  HL
    INC  DE
    DJNZ .lp
.done:
    XOR  A
    LD   (DE), A
    RET

; Expand compressed NUL-terminated string HL to DE, leaving HL past NUL and DE at NUL.
; Preserves BC.
ovl_ui_append_str:
    LD   A, (HL)
    INC  HL
    OR   A
    JR   Z, .done
    CALL ovl_ui_emit_byte
    JR   ovl_ui_append_str
.done:
    XOR  A
    LD   (DE), A
    RET

ovl_ui_emit_byte:
    BIT  7, A
    JR   NZ, .bpe
    LD   (DE), A
    INC  DE
    RET
.bpe:
    PUSH HL
    SUB  0x80
    ADD  A, A
    LD   L, A
    LD   H, 0
    PUSH BC
    LD   BC, ovl_ui_bpe_table
    ADD  HL, BC
    POP  BC
    LD   A, (HL)
    INC  HL
    LD   H, (HL)
    CALL ovl_ui_emit_byte
    LD   A, H
    POP  HL
    JR   ovl_ui_emit_byte

ovl_ui_nth_str:
    OR   A
    RET  Z
    PUSH BC
    LD   B, A
.scan:
    LD   A, (HL)
    INC  HL
    OR   A
    JR   NZ, .scan
    DJNZ .scan
    POP  BC
    RET

; ============================================================================
; Local Overlay Variables (scalars only — no DS 128+)
; ============================================================================
ovl_ui_tmp0:             DB 0
ovl_ui_base_row:         DB 0
ovl_ui_look_dx:          DB 0
ovl_ui_look_dy:          DB 0

; ============================================================================
; Read-Only Tables & Compressed Strings
; ============================================================================

ovl_ui_bpe_table:
    DB   0x65, 0x72
    DB   0x6F, 0x72
    DB   0x6F, 0x6E
    DB   0x69, 0x6E
    DB   0x61, 0x72
    DB   0x61, 0x6E
    DB   0x74, 0x72
    DB   0x74, 0x20
    DB   0x61, 0x70
    DB   0x65, 0x6E
    DB   0x6C, 0x65
    DB   0x20, 0x73
    DB   0x61, 0x6C
    DB   0x65, 0x20
    DB   0x83, 0x67
    DB   0x86, 0x88
    DB   0x75, 0x72
    DB   0x72, 0x6F
    DB   0x61, 0x73
    DB   0x64, 0x20
    DB   0x61, 0x67
    DB   0x81, 0x20
    DB   0x61, 0x63
    DB   0x65, 0x6C
    DB   0x69, 0x85
    DB   0x41, 0x20
    DB   0x61, 0x74
    DB   0x6C, 0x6F
    DB   0x61, 0x20
    DB   0x69, 0x74
    DB   0x6F, 0x6C
    DB   0x75, 0x6E
    DB   0x65, 0x73
    DB   0x6F, 0x75
    DB   0x64, 0x6F
    DB   0x63, 0x68
    DB   0x69, 0x73
    DB   0x47, 0x98
    DB   0xA5, 0x87
    DB   0x69, 0x82
    DB   0x8E, 0x20
    DB   0x65, 0x93
    DB   0x79, 0x20
    DB   0x2D, 0x2D
    DB   0x6F, 0x70
    DB   0xA2, 0x81
    DB   0x6F, 0x6F
    DB   0x20, 0x8F
    DB   0x74, 0x80
    DB   0x61, 0x6D
    DB   0x69, 0x67
    DB   0x89, 0x74
    DB   0x63, 0x6B
    DB   0x8B, 0x74
    DB   0x2C, 0x20
    DB   0x41, 0x6E
    DB   0x49, 0x6E
    DB   0xB2, 0x68
    DB   0x65, 0x6D
    DB   0x20, 0x28
    DB   0x73, 0x20
    DB   0x89, 0x20
    DB   0x69, 0x72
    DB   0x6C, 0x6C
    DB   0x65, 0x65
    DB   0x9E, 0x64
    DB   0x20, 0x20
    DB   0x6F, 0x6D
    DB   0x74, 0x68
    DB   0x59, 0xA1
    DB   0x82, 0x20
    DB   0xAC, 0xBD
    DB   0xB5, 0x61
    DB   0x75, 0x73
    DB   0x75, 0x6D
    DB   0x72, 0x69
    DB   0x69, 0x63
    DB   0x64, 0x80
    DB   0x96, 0x65
    DB   0xB9, 0x74
    DB   0x67, 0x80
    DB   0x65, 0x70
    DB   0x96, 0x6B
    DB   0xB8, 0x76
    DB   0x71, 0x75
    DB   0x9F, 0x65
    DB   0xA9, 0xAD
    DB   0xC8, 0xBE
    DB   0xD7, 0x63
    DB   0xD8, 0x92
    DB   0x75, 0x62
    DB   0x8C, 0x6C
    DB   0x68, 0x69
    DB   0xA0, 0x74
    DB   0x48, 0x8C
    DB   0xDE, 0x66
    DB   0x52, 0x6F
    DB   0x41, 0x72
    DB   0x6F, 0x90
    DB   0xAE, 0x6B
    DB   0x70, 0x6F
    DB   0x67, 0x92
    DB   0xE5, 0xAF
    DB   0x74, 0x65
    DB   0x72, 0x61
    DB   0x97, 0x6C
    DB   0x69, 0x64
    DB   0xB7, 0x20
    DB   0x84, 0x6D
    DB   0x43, 0x68
    DB   0xB0, 0x20
    DB   0x53, 0x65
    DB   0x57, 0x65
    DB   0x42, 0x90
    DB   0x53, 0x74
    DB   0x57, 0x49
    DB   0x54, 0x6F
    DB   0x77, 0x6E
    DB   0x6B, 0x65
    DB   0x74, 0x6F
    DB   0x63, 0x82
    DB   0x75, 0x65
    DB   0xAB, 0xAB
    DB   0xC5, 0x8B
    DB   0xFB, 0x65
    DB   0xFC, 0x8D
    DB   0x65, 0x64
    DB   0x72, 0xD5

ovl_ui_str_char_title: DB "Character Info", 0
ovl_ui_str_lbl_name:   DB "Name: ", 0
ovl_ui_str_lbl_race:   DB "Race: ", 0
ovl_ui_str_lbl_class:  DB "Class: ", 0
ovl_ui_str_lbl_level:  DB "Level: ", 0
ovl_ui_str_lbl_ac:     DB "AC:", 0
ovl_ui_str_lbl_hp:     DB "HP:", 0
ovl_ui_str_lbl_mana:   DB "Mana: ", 0
ovl_ui_str_lbl_gold:   DB "Gold: ", 0
ovl_ui_str_lbl_exp:    DB "EXP:", 0
ovl_ui_str_lbl_spells: DB "Spells: ", 0
ovl_ui_str_lbl_sex:    DB "Sex: ", 0
ovl_ui_str_lbl_sc:     DB "  SC: ", 0
ovl_ui_str_lbl_age:    DB "Age: ", 0
ovl_ui_str_lbl_ht:     DB "Height: ", 0
ovl_ui_str_lbl_wt:     DB "Weight: ", 0
ovl_ui_str_lbl_title:  DB "Title: ", 0
ovl_ui_str_lbl_depth:  DB "Depth: ", 0
ovl_ui_str_lbl_hunger: DB "Hunger: ", 0
ovl_ui_str_lbl_blows:  DB "Blows: ", 0
ovl_ui_str_lbl_hitdam: DB "Hit/Dam: ", 0
ovl_ui_str_burden:     DB "Burden: ", 0
ovl_ui_str_lb:         DB " lb", 0
ovl_ui_str_town:       DB "Town", 0
ovl_ui_str_rnd:        DB "/rnd", 0
ovl_ui_str_fight:      DB "Fighting   : ", 0
ovl_ui_str_bows:       DB "Bows/Throw : ", 0
ovl_ui_str_save:       DB "Saving Thrw: ", 0
ovl_ui_str_stealth:    DB "Stealth    : ", 0
ovl_ui_str_search:     DB "Searching  : ", 0
ovl_ui_str_disarm:     DB "Disarming  : ", 0
ovl_ui_str_infra:      DB "Infravision: ", 0
ovl_ui_str_next:       DB "Next: ", 0
ovl_ui_str_max:        DB "Max", 0
ovl_ui_str_none:       DB "None", 0
ovl_ui_str_ft:         DB "0 ft", 0
ovl_ui_str_msg_hist:   DB "Message History", 0
ovl_ui_str_no_msgs:    DB "(No messages)", 0

ovl_ui_hunger_names:
    DB   "Full", 0, "Hungry", 0, "Weak", 0, "Faint", 0
ovl_ui_rank_names:
    DB   "Novice", 0, "Initiate", 0, "Apprentice", 0, "Journeyman", 0
    DB   "Veteran", 0, "Hero", 0, "Master", 0, "Grand Master", 0
ovl_ui_rating_names:
    DB   "Bad", 0, "Poor", 0, "Fair", 0, "Good", 0
    DB   "Very Good", 0, "Superb", 0, "Heroic", 0, "Legendary", 0
ovl_ui_ucp_cls_off:  DB 3, 4, 6, 5
ovl_ui_ucp_race_off: DB 7, 8, 9, 3
ovl_ui_ucp_lvl_off:  DB 0, 1, 4, 3
ovl_ui_dex_disarm_bonus:
    DB   -8, -6, -4, -2, -1, 0, 0, 0
    DB   0, 0, 1, 1, 1, 2, 2, 4
ovl_ui_xp_early:
    DW   10, 25, 45, 70, 100, 140, 200, 280, 380, 500
    DW   650, 850, 1100, 1400, 1800, 2300, 2900, 3600, 4400, 5400
    DW   6800, 8400, 10200, 12500, 17500, 25000, 35000, 50000
ovl_ui_xp_late:
    DW   750, 1000, 1500, 2000, 3000, 4000, 5000, 7500, 15000, 25000, 50000
ovl_ui_stat_names:
    DB   "STR:", 0, "INT:", 0, "WIS:", 0
    DB   "DEX:", 0, "CON:", 0, "CHR:", 0
ovl_ui_class_spell_total:
    DB   0, 31, 31, 12, 30, 31

ovl_ui_str_wizard: DB   0xF3, "ZARD", 0 ; "WIZARD"
ovl_ui_str_male: DB   "Ma", 0x8A, 0 ; "Male"
ovl_ui_str_female: DB   "F", 0xBA, "a", 0x8A, 0 ; "Female"
ovl_ui_str_press_key: DB "Press any key", 0
ovl_ui_str_select_item: DB "Select item", 0
ovl_ui_str_inv_hdr: DB   0xD3, 0xB3, 0x81, "y", 0 ; "Inventory"
ovl_ui_str_nothing: DB "Nothing.", 0
ovl_ui_str_eq_hdr: DB   "E", 0xD4, "ipm", 0xB3, 0 ; "Equipment"
ovl_ui_str_dash9: DB   0xFA, 0xFA, "-", 0 ; "---------"
ovl_ui_str_eq_none: DB   "(n", 0x82, "e)", 0 ; "(none)"
ovl_ui_str_you_see: DB   0xFD, 0 ; "You see "
ovl_ui_str_a_mon: DB   "cre", 0x9A, 0x90, "e", 0 ; "creature"
ovl_ui_str_rcl_prompt: DB "Recall which? ", 0

ovl_ui_race_names:
    DB   "H", 0xCA, 0x85, 0 ; "Human"
    DB   0xDF, "-Elf", 0 ; "Half-Elf"
    DB   "Elf", 0 ; "Elf"
    DB   0xDF, "l", 0x8E, 0 ; "Halfling"
    DB   "Gn", 0xC3, "e", 0 ; "Gnome"
    DB   "Dw", 0x84, "f", 0 ; "Dwarf"
    DB   0xDF, "-Orc", 0 ; "Half-Orc"
    DB   0xDF, "-T", 0x91, 0xBF, 0 ; "Half-Troll"

ovl_ui_class_names:
    DB   "W", 0x84, 0xCB, 0x81, 0 ; "Warrior"
    DB   "M", 0x94, "e", 0 ; "Mage"
    DB   "P", 0xCB, 0xDD, 0 ; "Priest"
    DB   0xE0, "g", 0xF9, 0 ; "Rogue"
    DB   "R", 0x85, 0xD0, 0 ; "Ranger"
    DB   "P", 0x8C, "ad", 0x83, 0 ; "Paladin"

ovl_ui_eq_labels:
    DB   "Weapon: ", 0
    DB   "Body:   ", 0
    DB   "Shield: ", 0
    DB   "Head:   ", 0
    DB   "Hands:  ", 0
    DB   "Feet:   ", 0
    DB   "Light:  ", 0
    DB   "Ring:   ", 0
    DB   "Amulet: ", 0
    DB   "Ring:   ", 0
    DB   "Cloak:  ", 0
    DB   "Second: ", 0

ovl_ui_town_cre_names:
    DB   "Fil", 0xC4, 0xAA, "S", 0x86, 0xC0, 0x87, "Ur", 0xA3, 0x83, 0 ; "Filthy Street Urchin"
    DB   "Bl", 0xDA, "b", 0x80, 0xA8, "Idiot", 0 ; "Blubbering Idiot"
    DB   "P", 0x9D, "iful-L", 0xE3, 0xA8, "Begg", 0x84, 0 ; "Pitiful-Looking Beggar"
    DB   "M", 0x85, "gy-L", 0xE3, 0xA8, "L", 0xD1, 0x80, 0 ; "Mangy-Looking Leper"
    DB   "S", 0xD4, 0x83, "t-Ey", 0xA9, 0xE0, "g", 0xF9, 0 ; "Squint-Eyed Rogue"
    DB   "S", 0x8E, 0x8E, 0xB6, "H", 0x88, "p", 0xAA, "Dr", 0x9F, "k", 0 ; "Singing, Happy Drunk"
    DB   "Me", 0x85, "-L", 0xE3, 0xA8, "M", 0x80, "c", 0x89, 0x84, "y", 0 ; "Mean-Looking Mercenary"
    DB   "B", 0x9A, "t", 0x8A, "-Sc", 0x84, "r", 0xA9, "Ve", 0xB0, 0x85, 0 ; "Battle-Scarred Veteran"

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_ui.ovl", ovl_start, ovl_end - ovl_start
