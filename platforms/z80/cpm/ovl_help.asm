; ovl_help.asm — Moria8 CP/M Help Reference & Wizard Mode Overlay
; (OVL_HELP = 5, DAT slot 4)
;
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0: JP ovl_help_screen
;   +3: JP ovl_help_wizard
;
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax, DEVICE NOSLOT64K).
; All public entry vectors preserve IX and IY.

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "item_ids_z80.inc"
    DEFINE MONSTER_IDX_CONSTS_ONLY 1
    INCLUDE "monster_idx_z80.inc"
    UNDEFINE MONSTER_IDX_CONSTS_ONLY
    DEFINE HUFF_CONSTS_ONLY 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_CONSTS_ONLY
    INCLUDE "main_exp.inc"

    ORG  OVL_WINDOW_BASE        ; 0x5600

ovl_start:
    JP   ovl_help_screen
    JP   ovl_help_wizard

; Inline markup tokens for compact 2-column 80x24 Help pages
HELP_TOK_END        EQU 0x00
HELP_TOK_TAB2       EQU 0x01    ; move cursor to col 44 (HELP80_COL2)
HELP_TOK_CYAN       EQU 0x02    ; header color (COL_CYAN)
HELP_TOK_KEY        EQU 0x03    ; key color (COL_WHITE)
HELP_TOK_DESC       EQU 0x04    ; description color (COL_LGREY)
HELP_TOK_NL         EQU 0x05    ; next screen row, col 2

; ============================================================================
; +0: ovl_help_screen — 2-page 80-col ui_help_data_80.s parity + [L:License]
; ============================================================================
ovl_help_screen:
    PUSH IX
    PUSH IY

    XOR  A
    LD   (ovl_help_page), A

.redraw:
    CALL screen_hard_clear
    CALL ovl_help_draw_frame

    ; Title row 0 centered ("Command Reference [L:License]", 29 chars -> col 25)
    LD   B, 0
    LD   C, 25
    LD   E, COL_WHITE
    LD   HL, ovl_help_hdr_title
    CALL screen_put_str

    LD   A, (ovl_help_page)
    OR   A
    LD   HL, ovl_help_page1_data
    JR   Z, .have_page
    LD   HL, ovl_help_page2_data
.have_page:
    CALL ovl_help_render_stream

    ; Row 23 footer centered in COL_WHITE
    LD   A, (ovl_help_page)
    OR   A
    LD   HL, ovl_help_ftr_more
    LD   C, 26
    JR   Z, .put_ftr
    LD   HL, ovl_help_ftr_done
    LD   C, 28
.put_ftr:
    LD   B, SCREEN_ROWS - 1
    LD   E, COL_WHITE
    CALL screen_put_str

    CALL screen_flush
    LD   B, SCREEN_ROWS - 1
    LD   C, 76
    CALL screen_set_cursor

.wait_key:
    CALL input_get_key
    CP   KEY_ESC
    JR   Z, .exit
    CP   'q'
    JR   Z, .exit
    CP   'Q'
    JR   Z, .exit

    CP   'l'
    JR   Z, .open_legal
    CP   'L'
    JR   Z, .open_legal

    CP   KEY_SPACE
    JR   Z, .advance_page
    CP   KEY_CR
    JR   Z, .advance_page
    CP   KEY_PGDN
    JR   Z, .flip_page
    CP   KEY_PGUP
    JR   Z, .flip_page
    JR   .wait_key

.advance_page:
    LD   A, (ovl_help_page)
    OR   A
    JR   NZ, .exit
.flip_page:
    LD   A, (ovl_help_page)
    XOR  1
    LD   (ovl_help_page), A
    JR   .redraw

.open_legal:
    LD   A, (ovl_help_page)
    PUSH AF
    CALL tramp_legal_viewer
    POP  AF
    LD   (ovl_help_page), A
    CALL screen_hard_clear
    JP   .redraw

.exit:
    CALL screen_hard_clear
    CALL status_mark_dirty
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    POP  IY
    POP  IX
    RET

; Draw 80x24 border box using '+' / '-' / '|' in COL_GREY
ovl_help_draw_frame:
    LD   B, 0
    CALL .hborder
    LD   B, SCREEN_ROWS - 1
    CALL .hborder
    LD   B, 1
.vloop:
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
    JR   C, .vloop
    RET

.hborder:
    LD   C, 0
.hloop:
    LD   A, C
    OR   A
    JR   Z, .corner
    CP   SCREEN_COLS - 1
    JR   Z, .corner
    LD   A, '-'
    JR   .put_hb
.corner:
    LD   A, '+'
.put_hb:
    PUSH BC
    LD   E, COL_GREY
    CALL screen_put_char
    POP  BC
    INC  C
    LD   A, C
    CP   SCREEN_COLS
    JR   C, .hloop
    RET

; Render compact Help stream HL starting at row 1, col 2
ovl_help_render_stream:
    LD   B, 1                   ; row
    LD   C, 2                   ; col
    LD   E, COL_LGREY           ; current color
.loop:
    LD   A, (HL)
    INC  HL
    OR   A
    RET  Z                      ; HELP_TOK_END
    CP   HELP_TOK_TAB2
    JR   NZ, .chk_cyan
    LD   C, 44
    JR   .loop
.chk_cyan:
    CP   HELP_TOK_CYAN
    JR   NZ, .chk_key
    LD   E, COL_CYAN
    JR   .loop
.chk_key:
    CP   HELP_TOK_KEY
    JR   NZ, .chk_desc
    LD   E, COL_WHITE
    JR   .loop
.chk_desc:
    CP   HELP_TOK_DESC
    JR   NZ, .chk_nl
    LD   E, COL_LGREY
    JR   .loop
.chk_nl:
    CP   HELP_TOK_NL
    JR   NZ, .emit_ch
    INC  B
    LD   A, B
    CP   SCREEN_ROWS - 1
    RET  NC
    LD   C, 2
    JR   .loop
.emit_ch:
    LD   D, A
    LD   A, C
    CP   SCREEN_COLS - 1
    JR   NC, .loop
    LD   A, D
    PUSH HL
    PUSH BC
    PUSH DE
    CALL screen_put_char
    POP  DE
    POP  BC
    POP  HL
    INC  C
    JR   .loop

; ============================================================================
; +3: ovl_help_wizard — ^W Wizard Mode enable + 6502 ui_wizard.s 9-cmd menu
; ============================================================================
ovl_help_wizard:
    PUSH IX
    PUSH IY

    LD   A, (zp_game_flags)
    LD   HL, abi_game_flags
    OR   (HL)
    BIT  1, A                   ; GAME_FLAG_WIZARD
    JR   NZ, .wiz_menu

    LD   HL, ovl_help_wiz_confirm
    CALL msg_print_str
    LD   B, MSG_ROW0
    LD   C, 13
    CALL screen_set_cursor
    CALL screen_flush

    CALL input_get_key
    CP   'y'
    JR   Z, .enable_wiz
    CP   'Y'
    JR   Z, .enable_wiz

    XOR  A                      ; CF = 0 (leave "WIZARD? (Y/N)" intact, matching 6502)
    POP  IY
    POP  IX
    RET

.enable_wiz:
    ; Match 6502 ui_wizard.s: enable flag, print "WIZARD ON", and return to game loop
    LD   A, (zp_game_flags)
    OR   GAME_FLAG_WIZARD
    LD   (zp_game_flags), A
    LD   A, (abi_game_flags)
    OR   GAME_FLAG_WIZARD
    LD   (abi_game_flags), A
    LD   HL, ovl_help_wiz_enabled
    CALL msg_print_str
    CALL screen_flush
    XOR  A                      ; CF = 0 (first-time enable does not force screen rebuild)
    POP  IY
    POP  IX
    RET

.wiz_menu:
    CALL screen_hard_clear

    LD   B, 0
    LD   C, 37
    LD   E, COL_WHITE
    LD   HL, ovl_help_wiz_title
    CALL screen_put_str

    LD   HL, ovl_help_wiz_rows
    LD   B, 2
.mrow_lp:
    PUSH BC
    PUSH HL
    LD   C, 30
    LD   E, COL_LGREY
    CALL screen_put_str
    POP  HL
.mrow_skp:
    LD   A, (HL)
    INC  HL
    OR   A
    JR   NZ, .mrow_skp
    POP  BC
    INC  B
    LD   A, B
    CP   11
    JR   C, .mrow_lp

    LD   B, 18
    LD   C, 34
    LD   E, COL_WHITE
    LD   HL, ovl_help_wiz_footer
    CALL screen_put_str
    CALL screen_flush

.wiz_key:
    CALL input_get_key
    CP   KEY_ESC
    JR   Z, .wiz_cancel
    CP   'a'
    JR   C, .wiz_chk
    CP   'z' + 1
    JR   NC, .wiz_chk
    AND  0xDF
.wiz_chk:
    CP   'Q'
    JR   Z, .wiz_cancel
    CP   'L'
    JR   Z, .do_goto
    CP   'A'
    JR   Z, .do_reveal
    CP   'H'
    JR   Z, .do_heal
    CP   'I'
    JR   Z, .do_identify
    CP   'X'
    JR   Z, .do_gain_level
    CP   'G'
    JR   Z, .do_item
    CP   'S'
    JR   Z, .do_summon
    CP   'T'
    JR   Z, .do_teleport
    CP   'W'
    JP   Z, .do_wall_walk
    ; Unrecognized key exits menu (6502 ui_wizard.s:38-62)

.wiz_cancel:
    XOR  A
    JR   .wiz_exit_hl_z

.wiz_exit_ok:
    LD   HL, ovl_help_wiz_ok_str
    JR   .wiz_exit_msg

.wiz_exit_fail:
    LD   HL, ovl_help_wiz_fail_str

.wiz_exit_msg:
    PUSH HL
    CALL screen_hard_clear
    CALL status_mark_dirty
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    POP  HL
    ; Hand message back in line_buf so game_loop prints it AFTER _gl_vis_fresh
    LD   A, H
    OR   L
    JR   NZ, .wiz_chk_linebuf
    LD   (line_buf), A
    JR   .wiz_ret_redraw
.wiz_chk_linebuf:
    LD   DE, line_buf
    PUSH HL
    OR   A
    SBC  HL, DE
    POP  HL
    JR   Z, .wiz_ret_redraw     ; HL already points to line_buf (gain level)
    LD   B, 79
.wiz_cp_lp:
    LD   A, (HL)
    OR   A
    JR   Z, .wiz_cp_end
    LD   (DE), A
    INC  HL
    INC  DE
    DJNZ .wiz_cp_lp
.wiz_cp_end:
    XOR  A
    LD   (DE), A
.wiz_ret_redraw:
    SCF
    POP  IY
    POP  IX
    RET

.wiz_exit_hl_z:
    LD   HL, 0
    JR   .wiz_exit_msg

.do_goto:
    CALL ovl_help_wiz_goto
    JR   NC, .wiz_cancel
    JR   .wiz_exit_hl_z

.do_reveal:
    CALL ovl_help_wiz_reveal
    JR   .wiz_exit_ok

.do_heal:
    CALL ovl_help_wiz_heal
    JR   .wiz_exit_ok

.do_identify:
    CALL ovl_help_wiz_identify
    JR   .wiz_exit_ok

.do_gain_level:
    CALL ovl_help_wiz_gain_level
    LD   HL, line_buf
    JR   C, .wiz_exit_msg
    LD   HL, ovl_help_wiz_max_str
    JR   .wiz_exit_msg

.do_item:
    CALL ovl_help_wiz_item
    INC  B
    DEC  B                      ; Z=1 iff cancelled (B==0), preserves CF
    JR   Z, .wiz_cancel
    JR   C, .wiz_exit_ok
    JR   .wiz_exit_fail

.do_summon:
    CALL ovl_help_wiz_spawn_mon
    JR   C, .wiz_exit_ok
    JR   .wiz_exit_fail

.do_teleport:
    XOR  A
    CALL tramp_items_eff_teleport
    CALL monster_update_visibility_all
    CALL viewport_center_on_player
    LD   A, 1
    LD   (turn_scene_dirty), A
    JP   .wiz_exit_ok

.do_wall_walk:
    LD   HL, wizard_wall_walk_active
    LD   A, (HL)
    XOR  1
    LD   (HL), A
    OR   A
    LD   HL, ovl_help_wiz_wall_on
    JP   NZ, .wiz_exit_msg
    LD   HL, ovl_help_wiz_wall_off
    JP   .wiz_exit_msg

; --- [L] Jump dungeon level 0..99 ---
; Output: CF=1 if dlvl updated, CF=0 if cancelled
ovl_help_wiz_goto:
    LD   HL, ovl_help_wiz_goto_prompt
    LD   B, 3                       ; allow 3 typed digits before range-checking <= 99 (6502)
    LD   DE, 99
    CALL ovl_help_wiz_prompt_num    ; CF=1 -> HL = value
    RET  NC
    LD   A, L
    LD   B, A
    LD   A, (abi_player_dlvl)
    CP   B
    LD   A, 0                       ; descending (cur < target)
    JR   C, .dir_ok
    INC  A                          ; ascending (cur >= target)
.dir_ok:
    LD   (level_entry_dir), A
    LD   A, B
    LD   (abi_player_dlvl), A
    LD   (player_data + PL_DLEVEL), A
    LD   HL, player_data + PL_MAX_DLVL
    CP   (HL)
    JR   C, .max_ok
    LD   (HL), A
.max_ok:
    LD   A, 1
    LD   (level_force_regen), A
    SCF
    RET

; --- [G] Generate item by catalog ID 0..360 ---
; Output: B=0 cancelled, B=1 attempted (CF=1 ok, CF=0 fail)
ovl_help_wiz_item:
    LD   HL, ovl_help_wiz_item_prompt
    LD   B, 3
    LD   DE, ITEM_TYPE_COUNT - 1
    CALL ovl_help_wiz_prompt_num    ; CF=1 -> HL = 0..360
    JR   C, .have_id
    LD   B, 0
    OR   A
    RET
.have_id:
    ; Convert HL (0..360) -> (item_cur_page), fi_add_id
    LD   DE, ITEM_PAGE_SIZE
    OR   A
    SBC  HL, DE
    JR   NC, .page1
    ADD  HL, DE
    XOR  A
    LD   (item_cur_page), A
    LD   A, L
    JR   .id_set
.page1:
    LD   A, ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, L
.id_set:
    LD   (fi_add_id), A
    CALL item_get_category_a
    CP   ICAT_GOLD
    JR   NZ, .non_gold
    ; Page-0 gold piece (id=0 small 25, else 100) placed on floor
    LD   A, (fi_add_id)
    OR   A
    LD   A, 25
    JR   Z, .g_qty
    LD   A, 100
.g_qty:
    LD   (fi_add_qty), A
    XOR  A
    LD   HL, fi_add_qty_hi
    LD   B, 6
.gz_lp:
    LD   (HL), A
    INC  HL
    DJNZ .gz_lp
    LD   (fi_add_ego), A
    JR   .try_floor
.non_gold:
    CALL tramp_item_mgt_roll_enchant
    LD   A, (fi_add_ego)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, (fi_add_id)
    CALL icat_select_id
    JR   C, .try_inv
    CALL icat_get_level_missile
    BIT  7, B
    JR   Z, .try_inv
    LD   A, 6
    CALL rng_range
    ADD  A, 5
    LD   (fi_add_qty), A
.try_inv:
    CALL inv_add_item
    JR   NC, .try_floor
    LD   B, 1
    SCF
    RET
.try_floor:
    LD   A, (abi_player_x)
    LD   (fi_add_x), A
    LD   A, (abi_player_y)
    LD   (fi_add_y), A
    CALL floor_item_add
    LD   B, 1
    RET

; Prompt for non-negative decimal integer at row 5 col 28.
; Input: HL = prompt string, B = max_digits (2 or 3), DE = max_value (0..999).
; Output: CF=1 HL=parsed value, CF=0 cancelled.
ovl_help_wiz_prompt_num:
    LD   (ovl_help_wiz_maxval), DE
    LD   A, B
    LD   (ovl_help_wiz_maxdig), A
    PUSH HL
    CALL screen_hard_clear
    POP  HL
    ; Measure prompt length for cursor column
    PUSH HL
    LD   C, 0
.plen:
    LD   A, (HL)
    OR   A
    JR   Z, .plen_ok
    INC  HL
    INC  C
    JR   .plen
.plen_ok:
    LD   A, 28
    ADD  A, C
    LD   (ovl_help_wiz_incol), A
    POP  HL
    LD   B, 5
    LD   C, 28
    LD   E, COL_WHITE
    CALL screen_put_str
    CALL screen_flush
    XOR  A
    LD   (ovl_help_wiz_digits), A
.n_loop:
    LD   A, (ovl_help_wiz_incol)
    LD   HL, ovl_help_wiz_digits
    ADD  A, (HL)
    LD   C, A
    LD   B, 5
    CALL screen_set_cursor
    CALL input_get_key
    CP   KEY_ESC
    JP   Z, .n_cancel
    CP   ' '
    JP   Z, .n_cancel
    CP   'q'
    JP   Z, .n_cancel
    CP   'Q'
    JP   Z, .n_cancel
    CP   KEY_BS
    JR   Z, .n_bs
    CP   KEY_DEL
    JR   Z, .n_bs
    CP   KEY_CR
    JR   Z, .n_enter
    CP   '0'
    JR   C, .n_loop
    CP   '9' + 1
    JR   NC, .n_loop
    LD   C, A
    LD   A, (ovl_help_wiz_digits)
    LD   HL, ovl_help_wiz_maxdig
    CP   (HL)
    JR   NC, .n_loop
    LD   E, A
    LD   D, 0
    LD   HL, ovl_help_wiz_numbuf
    ADD  HL, DE
    LD   (HL), C
    LD   A, (ovl_help_wiz_incol)
    ADD  A, E
    LD   E, C
    LD   C, A
    LD   B, 5
    LD   A, E
    LD   E, COL_WHITE
    CALL screen_put_char
    CALL screen_flush
    LD   HL, ovl_help_wiz_digits
    INC  (HL)
    JR   .n_loop
.n_bs:
    LD   A, (ovl_help_wiz_digits)
    OR   A
    JR   Z, .n_loop
    DEC  A
    LD   (ovl_help_wiz_digits), A
    LD   HL, ovl_help_wiz_incol
    ADD  A, (HL)
    LD   C, A
    LD   B, 5
    LD   A, ' '
    LD   E, COL_WHITE
    CALL screen_put_char
    CALL screen_flush
    JR   .n_loop
.n_enter:
    LD   A, (ovl_help_wiz_digits)
    OR   A
    JP   Z, .n_loop
    ; Parse digits -> HL = value
    LD   B, A
    LD   DE, ovl_help_wiz_numbuf
    LD   HL, 0
.p_lp:
    PUSH DE
    LD   D, H
    LD   E, L
    ADD  HL, HL                 ; *2
    ADD  HL, HL                 ; *4
    ADD  HL, DE                 ; *5
    ADD  HL, HL                 ; *10
    POP  DE
    LD   A, (DE)
    INC  DE
    SUB  '0'
    ADD  A, L
    LD   L, A
    JR   NC, .p_nc
    INC  H
.p_nc:
    DJNZ .p_lp
    ; Check HL <= ovl_help_wiz_maxval
    PUSH HL
    LD   DE, (ovl_help_wiz_maxval)
    EX   DE, HL
    OR   A
    SBC  HL, DE
    POP  HL
    JR   C, .n_bad
    SCF
    RET
.n_bad:
    LD   HL, ovl_help_wiz_bad_str
    CALL msg_print_str
    CALL sound_bell
    LD   A, (ovl_help_wiz_digits)
    OR   A
    JR   Z, .nb_rst
    LD   B, A
    LD   A, (ovl_help_wiz_incol)
    LD   C, A
.nb_clr:
    PUSH BC
    LD   B, 5
    LD   A, ' '
    LD   E, COL_WHITE
    CALL screen_put_char
    POP  BC
    INC  C
    DJNZ .nb_clr
.nb_rst:
    XOR  A
    LD   (ovl_help_wiz_digits), A
    CALL screen_flush
    JP   .n_loop
.n_cancel:
    OR   A
    RET

; --- [A] Reveal floorplan + hidden doors (core/6502/wizard.s::wizard_reveal_level) ---
ovl_help_wiz_reveal:
    LD   B, 0
.ry_loop:
    LD   C, 0
.rx_loop:
    CALL map_get_tile
    LD   D, A
    AND  TILE_TYPE_MASK
    CP   TILE_FLOOR
    JR   Z, .mark
    CP   TILE_DOOR_OPEN
    JR   NC, .chk_secret
    BIT  3, D                   ; FLAG_LIT
    JR   Z, .rx_next
.mark:
    LD   A, D
    OR   FLAG_VISITED
    CALL map_set_tile
    JR   .rx_next
.chk_secret:
    CP   TILE_SECRET
    JR   NZ, .mark
    LD   A, D
    AND  ~TILE_TYPE_MASK & 0xFF
    OR   TILE_DOOR_CLOSED | FLAG_VISITED
    CALL map_set_tile
.rx_next:
    INC  C
    LD   A, C
    CP   MAP_COLS
    JR   C, .rx_loop
    INC  B
    LD   A, B
    CP   MAP_ROWS
    JR   C, .ry_loop
    LD   A, 1
    LD   (turn_scene_dirty), A
    RET

; --- [H] Heal full, restore MP, clear status timers ---
ovl_help_wiz_heal:
    LD   HL, (player_data + PL_MHP_LO)
    LD   (player_data + PL_HP_LO), HL
    LD   A, (player_data + PL_MAX_MANA)
    LD   (player_data + PL_MANA), A
    XOR  A
    LD   (zp_eff_poison), A
    LD   (zp_eff_blind), A
    LD   (zp_eff_confuse), A
    LD   (zp_eff_paralyze), A
    LD   (zp_eff_speed), A
    LD   (zp_eff_word_recall), A
    LD   (eff_fear_timer), A
    CALL player_sync_to_abi
    JP   status_mark_dirty

; --- [I] Identify all inventory & equipment items + mark known catalog ---
ovl_help_wiz_identify:
    LD   C, 0
.id_lp:
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .id_nx
    PUSH AF                     ; save item_id
    LD   HL, inv_flags
    ADD  HL, BC
    LD   A, (HL)
    AND  ~IF_SENSED & 0xFF
    OR   IF_IDENTIFIED
    LD   (HL), A
    LD   HL, inv_ego
    ADD  HL, BC
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    POP  AF
    CALL id_mark_known
.id_nx:
    INC  C
    LD   A, C
    CP   TOTAL_INV_SLOTS
    JR   C, .id_lp
    RET

; --- [X] Gain 1 level up to 40 (matching ui_wizard_cmd_gain_level) ---
; Output: CF=1 gained level, CF=0 already max (>= 40)
ovl_help_wiz_gain_level:
    LD   A, (player_data + PL_LEVEL)
    CP   40
    JR   C, .gl_ok
    OR   A
    RET
.gl_ok:
    OR   A
    JR   NZ, .gl_nz
    LD   A, 1
    LD   (player_data + PL_LEVEL), A
.gl_nz:
    CALL ovl_help_calc_xp_thresh ; ovl_help_tmp24 = next level threshold
    ; Ensure PL_XP >= ovl_help_tmp24
    LD   A, (player_data + PL_XP_2)
    LD   HL, ovl_help_tmp24 + 2
    CP   (HL)
    JR   C, .set_xp
    JR   NZ, .do_lvl
    LD   A, (player_data + PL_XP_1)
    DEC  HL
    CP   (HL)
    JR   C, .set_xp
    JR   NZ, .do_lvl
    LD   A, (player_data + PL_XP_0)
    DEC  HL
    CP   (HL)
    JR   NC, .do_lvl
.set_xp:
    LD   HL, ovl_help_tmp24
    LD   DE, player_data + PL_XP_0
    LD   BC, 3
    LDIR
    XOR  A
    LD   (player_data + PL_XP_FRAC_LO), A
    LD   (player_data + PL_XP_FRAC_HI), A
    ; Update PL_MAX_XP if PL_XP > PL_MAX_XP
    LD   A, (player_data + PL_XP_2)
    LD   HL, player_data + PL_MAX_XP_2
    CP   (HL)
    JR   C, .do_lvl
    JR   NZ, .upd_max
    LD   A, (player_data + PL_XP_1)
    DEC  HL
    CP   (HL)
    JR   C, .do_lvl
    JR   NZ, .upd_max
    LD   A, (player_data + PL_XP_0)
    DEC  HL
    CP   (HL)
    JR   C, .do_lvl
.upd_max:
    LD   HL, player_data + PL_XP_0
    LD   DE, player_data + PL_MAX_XP_0
    LD   BC, 3
    LDIR
.do_lvl:
    LD   HL, player_data + PL_LEVEL
    INC  (HL)
    CALL player_calc_hp
    LD   HL, (player_data + PL_MHP_LO)
    LD   (player_data + PL_HP_LO), HL
    CALL player_calc_combat
    CALL player_sync_to_abi
    CALL tramp_spell_recalc_levelup
    CALL status_mark_dirty
    CALL sound_bell
    LD   A, HSTR_CMB_LVLUP
    LD   DE, line_buf
    CALL huff_decode_string
.lvl_tilde:
    LD   A, (DE)
    OR   A
    JR   Z, .lvl_num
    CP   '~'
    JR   Z, .lvl_num
    INC  DE
    JR   .lvl_tilde
.lvl_num:
    LD   A, (player_data + PL_LEVEL)
    CALL fmt_u8_dec
    LD   A, '.'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    SCF
    RET

; Compute 24-bit threshold = base * PL_EXPFACT (/ 100 if level < 29) -> ovl_help_tmp24
ovl_help_calc_xp_thresh:
    LD   A, (player_data + PL_EXPFACT)
    OR   A
    JR   NZ, .ef_ok
    LD   A, 100
.ef_ok:
    LD   (ovl_help_wiz_digits), A
    LD   A, (player_data + PL_LEVEL)
    CP   29
    JR   NC, .late
    DEC  A
    ADD  A, A
    LD   E, A
    LD   D, 0
    LD   HL, ovl_help_xp_early
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    CALL ovl_help_mul_de_ef
    LD   B, 24
    XOR  A
.d24:
    ADD  HL, HL
    RL   C
    RLA
    JR   C, .d_sub
    CP   100
    JR   C, .d_next
.d_sub:
    SUB  100
    INC  L
.d_next:
    DJNZ .d24
    LD   (ovl_help_tmp24), HL
    LD   A, C
    LD   (ovl_help_tmp24 + 2), A
    RET
.late:
    SUB  29
    ADD  A, A
    LD   E, A
    LD   D, 0
    LD   HL, ovl_help_xp_late
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    CALL ovl_help_mul_de_ef
    LD   (ovl_help_tmp24), HL
    LD   A, C
    LD   (ovl_help_tmp24 + 2), A
    RET

ovl_help_mul_de_ef:
    LD   HL, 0
    LD   C, 0
    LD   A, (ovl_help_wiz_digits)
    OR   A
    RET  Z
    LD   B, 8
.lp:
    ADD  HL, HL
    RL   C
    RLCA
    JR   NC, .skip
    ADD  HL, DE
    JR   NC, .skip
    INC  C
.skip:
    DJNZ .lp
    RET

; --- [S] Summon creature adjacent to player (CF=1 ok, CF=0 fail) ---
ovl_help_wiz_spawn_mon:
    LD   A, (abi_player_y)
    LD   B, A
    LD   A, (abi_player_x)
    LD   C, A
    CALL find_adjacent_empty_tile
    RET  NC
    PUSH BC
    LD   A, (abi_player_dlvl)
    CP   100
    JR   C, .pick_norm
    LD   DE, CATALOG_BALROG_ID
    CALL catalog_slot_for_id
    JR   .have_mon
.pick_norm:
    CALL pick_creature_type
.have_mon:
    POP  BC
    CALL monster_spawn_one
    RET  NC
    CALL monster_update_visibility_all
    LD   A, 1
    LD   (turn_scene_dirty), A
    SCF
    RET

; ============================================================================
; Local Overlay Data & Packed 80-col Help Pages (ui_help_data_80.s 1:1)
; ============================================================================
ovl_help_page:         DB 0
ovl_help_wiz_digits:   DB 0
ovl_help_wiz_maxdig:   DB 0
ovl_help_wiz_incol:    DB 0
ovl_help_wiz_maxval:   DW 0
ovl_help_wiz_numbuf:   DB 0, 0, 0
ovl_help_tmp24:        DB 0, 0, 0

ovl_help_hdr_title:    DB "Command Reference [L:License]", 0
ovl_help_ftr_more:     DB "SPACE/RETURN next Q/ESC quit", 0
ovl_help_ftr_done:     DB "SPACE/RETURN/Q/ESC done", 0

ovl_help_page1_data:
    DB HELP_TOK_CYAN, "Movement", HELP_TOK_TAB2, "Actions", HELP_TOK_NL
    DB HELP_TOK_KEY, "H", HELP_TOK_DESC, " Left", HELP_TOK_TAB2, HELP_TOK_KEY, "O", HELP_TOK_DESC, " Open Door", HELP_TOK_NL
    DB HELP_TOK_KEY, "L", HELP_TOK_DESC, " Right", HELP_TOK_TAB2, HELP_TOK_KEY, "C", HELP_TOK_DESC, " Close Door", HELP_TOK_NL
    DB HELP_TOK_KEY, "K", HELP_TOK_DESC, " Up", HELP_TOK_TAB2, HELP_TOK_KEY, "S", HELP_TOK_DESC, " Search", HELP_TOK_NL
    DB HELP_TOK_KEY, "J", HELP_TOK_DESC, " Down", HELP_TOK_TAB2, HELP_TOK_KEY, "5", HELP_TOK_DESC, " Rest  ", HELP_TOK_KEY, "CTRL+R", HELP_TOK_DESC, " Rest*", HELP_TOK_NL
    DB HELP_TOK_KEY, "Y", HELP_TOK_DESC, " NW", HELP_TOK_TAB2, HELP_TOK_KEY, "<", HELP_TOK_DESC, " Go Up", HELP_TOK_NL
    DB HELP_TOK_KEY, "U", HELP_TOK_DESC, " NE", HELP_TOK_TAB2, HELP_TOK_KEY, ">", HELP_TOK_DESC, " Go Down", HELP_TOK_NL
    DB HELP_TOK_KEY, "B", HELP_TOK_DESC, " SW", HELP_TOK_TAB2, HELP_TOK_KEY, "/", HELP_TOK_DESC, " Identify", HELP_TOK_NL
    DB HELP_TOK_KEY, "N", HELP_TOK_DESC, " SE", HELP_TOK_TAB2, HELP_TOK_KEY, "X", HELP_TOK_DESC, " Look", HELP_TOK_NL
    DB HELP_TOK_DESC, "Cursors also move", HELP_TOK_TAB2, HELP_TOK_KEY, "SHIFT+DIR/.", HELP_TOK_DESC, " Run", HELP_TOK_NL
    DB HELP_TOK_TAB2, HELP_TOK_KEY, "CTRL+D", HELP_TOK_DESC, " Jam", HELP_TOK_NL
    DB HELP_TOK_CYAN, "Items", HELP_TOK_TAB2, "Combat", HELP_TOK_NL
    DB HELP_TOK_KEY, "G", HELP_TOK_DESC, " Get Item", HELP_TOK_TAB2, HELP_TOK_DESC, "Walk into monster", HELP_TOK_NL
    DB HELP_TOK_KEY, "D", HELP_TOK_DESC, " Drop Item", HELP_TOK_TAB2, HELP_TOK_KEY, "SHIFT+F", HELP_TOK_DESC, " Fire", HELP_TOK_NL
    DB HELP_TOK_KEY, "I", HELP_TOK_DESC, " Inventory", HELP_TOK_TAB2, HELP_TOK_KEY, "SHIFT+T", HELP_TOK_DESC, " Throw", HELP_TOK_NL
    DB HELP_TOK_KEY, "E", HELP_TOK_DESC, " Equipment", HELP_TOK_TAB2, HELP_TOK_KEY, "SHIFT+D", HELP_TOK_DESC, " Disarm", HELP_TOK_NL
    DB HELP_TOK_KEY, "W", HELP_TOK_DESC, " Wear/Wield", HELP_TOK_TAB2, HELP_TOK_KEY, "CTRL+B", HELP_TOK_DESC, " Bash", HELP_TOK_NL
    DB HELP_TOK_KEY, "T", HELP_TOK_DESC, " Take Off", HELP_TOK_TAB2, HELP_TOK_KEY, "+", HELP_TOK_DESC, " Tunnel", HELP_TOK_NL
    DB HELP_TOK_KEY, "Q", HELP_TOK_DESC, " Quaff Potion", HELP_TOK_TAB2, HELP_TOK_KEY, "SHIFT+X", HELP_TOK_DESC, " Exchange Weapons", HELP_TOK_NL
    DB HELP_TOK_KEY, "R", HELP_TOK_DESC, " Read Scroll", HELP_TOK_NL
    DB HELP_TOK_KEY, "A", HELP_TOK_DESC, " Aim Wand", HELP_TOK_NL
    DB HELP_TOK_KEY, "Z", HELP_TOK_DESC, " Use Staff", HELP_TOK_END

ovl_help_page2_data:
    DB HELP_TOK_CYAN, "Magic", HELP_TOK_TAB2, "Other", HELP_TOK_NL
    DB HELP_TOK_KEY, "M", HELP_TOK_DESC, " Cast Spell", HELP_TOK_TAB2, HELP_TOK_KEY, "SHIFT+C", HELP_TOK_DESC, " Character", HELP_TOK_NL
    DB HELP_TOK_KEY, "P", HELP_TOK_DESC, " Pray", HELP_TOK_TAB2, HELP_TOK_KEY, "?", HELP_TOK_DESC, " Help", HELP_TOK_NL
    DB HELP_TOK_KEY, "F", HELP_TOK_DESC, " Study Book", HELP_TOK_TAB2, HELP_TOK_KEY, "SHIFT+S", HELP_TOK_DESC, " Save", HELP_TOK_NL
    DB HELP_TOK_KEY, "SHIFT+E", HELP_TOK_DESC, " Eat", HELP_TOK_TAB2, HELP_TOK_KEY, "SHIFT+Q", HELP_TOK_DESC, " Quit", HELP_TOK_NL
    DB HELP_TOK_KEY, "SHIFT+R", HELP_TOK_DESC, " Refuel", HELP_TOK_TAB2, HELP_TOK_KEY, "CTRL+W", HELP_TOK_DESC, " Wizard", HELP_TOK_NL
    DB HELP_TOK_NL
    DB HELP_TOK_CYAN, "Keypad", HELP_TOK_TAB2, "Letters", HELP_TOK_NL
    DB HELP_TOK_DESC, "    7   8   9", HELP_TOK_TAB2, "    Y   K   U", HELP_TOK_NL
    DB HELP_TOK_DESC, "    4   5   6", HELP_TOK_TAB2, "    H       L", HELP_TOK_NL
    DB HELP_TOK_DESC, "    1   2   3", HELP_TOK_TAB2, "    B   J   N", HELP_TOK_NL
    DB HELP_TOK_NL
    DB HELP_TOK_DESC, "    5 = Rest", HELP_TOK_NL
    DB HELP_TOK_DESC, "   7=NW    9=NE", HELP_TOK_TAB2, "   Y=NW    U=NE", HELP_TOK_NL
    DB HELP_TOK_DESC, "   1=SW    3=SE", HELP_TOK_TAB2, "   B=SW    N=SE", HELP_TOK_NL
    DB HELP_TOK_NL
    DB HELP_TOK_CYAN, "Prompts", HELP_TOK_TAB2, "Notes", HELP_TOK_NL
    DB HELP_TOK_DESC, "ESC/Q Cancel", HELP_TOK_TAB2, "SPACE/RETURN advance", HELP_TOK_NL
    DB HELP_TOK_DESC, "SPACE Continue", HELP_TOK_TAB2, HELP_TOK_KEY, "L", HELP_TOK_DESC, " License / Source", HELP_TOK_NL
    DB HELP_TOK_DESC, "RETURN Accept", HELP_TOK_TAB2, "Inventory letters act directly", HELP_TOK_NL
    DB HELP_TOK_DESC, "/ Identify then symbol", HELP_TOK_TAB2, "S searches, # toggles Search mode", HELP_TOK_NL
    DB HELP_TOK_TAB2, "* Rest until healed", HELP_TOK_END

ovl_help_wiz_confirm:     DB "WIZARD? (Y/N)", 0
ovl_help_wiz_enabled:     DB "WIZARD ON", 0
ovl_help_wiz_title:       DB "WIZARD", 0
ovl_help_wiz_rows:
    DB "L) Jump", 0
    DB "A) Reveal", 0
    DB "H) Heal", 0
    DB "I) Identify", 0
    DB "X) Gain lvl", 0
    DB "G) Item by id", 0
    DB "S) Summon", 0
    DB "T) Teleport", 0
    DB "W) Wall walk", 0
ovl_help_wiz_footer:      DB "Q to cancel", 0
ovl_help_wiz_goto_prompt: DB "DLVL 0-99: ", 0
ovl_help_wiz_item_prompt: DB "ITEM 0-360: ", 0
ovl_help_wiz_ok_str:      DB "OK", 0
ovl_help_wiz_bad_str:     DB "BAD", 0
ovl_help_wiz_fail_str:    DB "FAIL", 0
ovl_help_wiz_max_str:     DB "MAX", 0
ovl_help_wiz_wall_on:     DB "WALL ON", 0
ovl_help_wiz_wall_off:    DB "WALL OFF", 0

ovl_help_xp_early:
    DW 10, 25, 45, 70, 100, 140, 200, 280, 380, 500
    DW 650, 850, 1100, 1400, 1800, 2300, 2900, 3600, 4400, 5400
    DW 6800, 8400, 10200, 12500, 17500, 25000, 35000, 50000
ovl_help_xp_late:
    DW 750, 1000, 1500, 2000, 3000, 4000, 5000, 7500, 15000, 25000, 50000

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_help.ovl", ovl_start, ovl_end - ovl_start
