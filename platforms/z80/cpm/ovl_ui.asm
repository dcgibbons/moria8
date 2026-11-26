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

UCHAR_TITLE_COL     EQU 33
UCHAR_WIZARD_COL    EQU 71
UCHAR_FOOTER_COL    EQU 33
UCHAR_COL_L         EQU 22
UCHAR_COL_NAME      EQU 28
UCHAR_COL_MID       EQU 39
UCHAR_COL_R         EQU 43
UCHAR_STAT_COL0     EQU 22
UCHAR_STAT_COL1     EQU 35
UCHAR_STAT_COL2     EQU 48
UINV_TITLE_COL      EQU 35
UINV_FOOTER_COL     EQU 33
UEQ_TITLE_COL       EQU 35
UEQ_FOOTER_COL      EQU 33

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

    ; Row 2: Name
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

    ; Row 3: Race / Class
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
    LD   C, UCHAR_COL_R
    LD   HL, ovl_ui_str_lbl_class
    CALL ovl_ui_put_lgrey_cstr
    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .cls_ok
    XOR  A
.cls_ok:
    LD   HL, ovl_ui_class_names
    CALL ovl_ui_nth_str
    LD   B, 3
    LD   C, UCHAR_COL_R + 7
    CALL ovl_ui_put_cstr_w

    ; Row 4: Level / AC
    LD   B, 4
    LD   C, UCHAR_COL_L
    LD   HL, ovl_ui_str_lbl_level
    CALL ovl_ui_put_lgrey_cstr
    LD   A, (player_data + PL_LEVEL)
    LD   DE, line_buf
    CALL fmt_u8_dec
    LD   B, 4
    LD   C, UCHAR_COL_L + 7
    CALL ovl_ui_put_linebuf_w

    LD   B, 4
    LD   C, UCHAR_COL_R
    LD   HL, ovl_ui_str_lbl_ac
    CALL ovl_ui_put_lgrey_cstr
    LD   A, (player_data + PL_AC)
    LD   DE, line_buf
    CALL fmt_u8_dec
    LD   B, 4
    LD   C, UCHAR_COL_R + 3
    CALL ovl_ui_put_linebuf_w

    ; Rows 6-7: 6 Stats (Row 6: STR, INT, WIS; Row 7: DEX, CON, CHR)
    LD   B, 0
.stat_loop:
    LD   A, B
    CP   3
    JR   C, .st_row6
    SUB  3
    LD   D, 7
    JR   .st_col
.st_row6:
    LD   D, 6
.st_col:
    LD   C, UCHAR_STAT_COL0
    OR   A
    JR   Z, .st_have_pos
    LD   C, UCHAR_STAT_COL1
    DEC  A
    JR   Z, .st_have_pos
    LD   C, UCHAR_STAT_COL2
.st_have_pos:
    PUSH BC                     ; save stat index B
    LD   E, B
    LD   A, B
    LD   B, D                   ; B = screen row
    PUSH BC
    PUSH DE
    LD   HL, ovl_ui_stat_names
    CALL ovl_ui_nth_str         ; HL = "STR:", etc.
    CALL ovl_ui_put_lgrey_cstr
    POP  DE
    POP  BC                     ; B = row, C = start col
    LD   A, C
    ADD  A, 4
    LD   C, A
    LD   D, 0
    LD   HL, player_data + PL_STR_CUR
    ADD  HL, DE
    LD   E, COL_WHITE
    CALL ovl_ui_put_stat_at
    POP  BC
    INC  B
    LD   A, B
    CP   STAT_COUNT
    JR   C, .stat_loop

    ; Row 9: HP / Mana
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
    LD   C, UCHAR_COL_L + 3
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
    LD   C, UCHAR_COL_MID + 6
    CALL ovl_ui_put_linebuf_w

    ; Row 10: Gold / EXP
    LD   B, 10
    LD   C, UCHAR_COL_L
    LD   HL, ovl_ui_str_lbl_gold
    CALL ovl_ui_put_lgrey_cstr
    LD   B, 10
    LD   C, UCHAR_COL_L + 6
    LD   E, COL_YELLOW
    LD   HL, player_data + PL_GOLD_0
    CALL ovl_ui_put_u24_at

    LD   B, 10
    LD   C, UCHAR_COL_MID
    LD   HL, ovl_ui_str_lbl_exp
    CALL ovl_ui_put_lgrey_cstr
    LD   B, 10
    LD   C, UCHAR_COL_MID + 4
    LD   E, COL_WHITE
    LD   HL, player_data + PL_XP_0
    CALL ovl_ui_put_u24_at

    ; Row 11: Spells (spellcasters only)
    LD   A, (player_data + PL_SPELL_TYPE)
    OR   A
    JR   Z, .no_spells
    LD   B, 11
    LD   C, UCHAR_COL_L
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
    LD   B, 11
    LD   C, UCHAR_COL_L + 8
    CALL ovl_ui_put_linebuf_w
.no_spells:

    ; Row 12: Sex / SC
    LD   B, 12
    LD   C, UCHAR_COL_L
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
    LD   C, UCHAR_COL_L + 5
    CALL ovl_ui_put_linebuf_w

    ; Advance col cleanly right after "Male" (4) or "Female" (6)
    LD   A, (player_data + PL_FLAGS)
    AND  PLF_MALE
    LD   C, UCHAR_COL_L + 5 + 4
    JR   NZ, .sc_col_ok
    LD   C, UCHAR_COL_L + 5 + 6
.sc_col_ok:
    PUSH BC
    LD   B, 12
    LD   HL, ovl_ui_str_lbl_sc
    CALL ovl_ui_put_lgrey_cstr
    POP  BC
    LD   A, C
    ADD  A, 6                   ; len("  SC: ")
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
    LD   C, UCHAR_COL_L
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

    ; Row 18: "Press any key"
    LD   B, 18
    LD   C, UCHAR_FOOTER_COL
    LD   HL, ovl_ui_str_press_key
    CALL ovl_ui_put_lgrey_cstr
    LD   B, 18
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
    LD   (line_buf + 74), A
    POP  BC
    PUSH BC
    LD   E, COL_LGREY
    LD   C, 4
    LD   HL, line_buf
    CALL screen_put_str
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
    LD   (line_buf + 66), A
    POP  BC
    PUSH BC
    LD   C, 12
    CALL ovl_ui_put_linebuf_w
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
    JR   NZ, .sel_inv

    ; Equipment view with all 12 labeled slots and "(none)" for empties
    LD   B, 0
    LD   C, UEQ_TITLE_COL
    LD   E, COL_WHITE
    LD   HL, ovl_ui_str_eq_hdr
    CALL ovl_ui_put_cstr
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
    LD   (line_buf + 66), A
    POP  BC
    PUSH BC
    LD   C, 12
    CALL ovl_ui_put_linebuf_w
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
    LD   DE, line_buf
    CALL item_format_inv_slot
    XOR  A
    LD   (line_buf + 74), A
    POP  BC
    PUSH BC
    LD   A, C
    LD   HL, ovl_ui_base_row
    ADD  A, (HL)
    LD   B, A
    LD   C, 4
    LD   E, COL_LGREY
    LD   HL, line_buf
    CALL screen_put_str
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

ovl_ui_put_lgrey_cstr:
    LD   E, COL_LGREY
    JR   ovl_ui_put_cstr

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
