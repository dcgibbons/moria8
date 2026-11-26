; ovl_legal.asm — Moria8 CP/M Legal & System Info Overlay (OVL_LEGAL, DAT slot 13).
;
; Matches Moria8 ui_legal.s menu and pagination, streaming DAT_ID_LICENSE
; and DAT_ID_SRCOFFR from MORIA8.DAT plus CP/M Z80 System Info (3 / V).
;
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax, DEVICE NOSLOT64K).

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "version_z80.inc"
    INCLUDE "main_exp.inc"

    ORG  OVL_WINDOW_BASE        ; 0x5600

ovl_start:
    JP   ovl_legal_enter
    JP   ovl_legal_sysinfo_direct

LEGAL_PAGE_ROWS         EQU 20  ; rows 2..21
LEGAL_FIRST_ROW         EQU 2
LEGAL_FIRST_COL         EQU 1
LEGAL_MAX_COL           EQU 79  ; cols 1..79 (matching ui_legal.s)

ovl_legal_sysinfo_direct:
    LD   A, 1
    LD   (legal_entry_mode), A
    JP   ovl_legal_sysinfo

; ---------------------------------------------------------------------------
; ovl_legal_enter — Legal & Source main menu.
; ---------------------------------------------------------------------------
ovl_legal_enter:
    XOR  A
    LD   (legal_entry_mode), A
ovl_legal_menu:
    CALL screen_hard_clear

    LD   B, 1
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_legal_heading
    CALL screen_put_str

    LD   B, 3
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_legal_copyright
    CALL screen_put_str

    LD   B, 5
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_legal_rights
    CALL screen_put_str

    LD   B, 6
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_legal_warranty
    CALL screen_put_str

    LD   B, 8
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_legal_choices
    CALL screen_put_str

    CALL screen_flush
    LD   B, 8
    LD   C, 37
    CALL screen_set_cursor

ovl_legal_menu_wait:
    CALL input_get_key
    CP   KEY_ESC
    RET  Z

    CP   'a'
    JR   C, .chk_menu
    CP   'z' + 1
    JR   NC, .chk_menu
    AND  0xDF

.chk_menu:
    CP   'Q'
    RET  Z
    CP   '1'
    JR   Z, .open_license
    CP   '2'
    JR   Z, .open_source
    CP   '3'
    JR   Z, .open_sysinfo
    CP   'V'
    JR   Z, .open_sysinfo
    JR   ovl_legal_menu_wait

.open_license:
    LD   A, DAT_ID_LICENSE
    JR   ovl_legal_open_doc

.open_source:
    LD   A, DAT_ID_SRCOFFR
    JR   ovl_legal_open_doc

.open_sysinfo:
    JP   ovl_legal_sysinfo

; ---------------------------------------------------------------------------
; ovl_legal_open_doc — Stream and paginate DAT_ID_LICENSE or DAT_ID_SRCOFFR.
; Input: A = DAT slot ID
; ---------------------------------------------------------------------------
ovl_legal_open_doc:
    LD   (ovl_legal_doc_slot), A
    CALL dat_get_cold_byte_len  ; HL = byte_len
    JR   C, ovl_legal_doc_err
    LD   A, H
    OR   L
    JR   Z, ovl_legal_doc_err
    LD   (ovl_legal_doc_len), HL
    LD   HL, 0
    LD   (ovl_legal_top_line), HL

ovl_legal_doc_redraw:
    CALL ovl_legal_render_page
    JR   NC, ovl_legal_doc_wait

ovl_legal_doc_err:
    CALL screen_hard_clear
    LD   B, 2
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_legal_err_str
    CALL screen_put_str
    CALL screen_flush
    CALL input_wait_any_key
    JP   ovl_legal_menu

ovl_legal_doc_wait:
    CALL input_get_key
    CP   KEY_ESC
    JP   Z, ovl_legal_menu

    CP   'a'
    JR   C, .chk_doc_key
    CP   'z' + 1
    JR   NC, .chk_doc_key
    AND  0xDF

.chk_doc_key:
    CP   'Q'
    JP   Z, ovl_legal_menu
    CP   'R'
    JR   Z, .doc_restart
    CP   KEY_SPACE
    JR   Z, .doc_pgdn
    CP   KEY_CR
    JR   Z, .doc_pgdn
    JR   ovl_legal_doc_wait

.doc_restart:
    LD   HL, 0
    LD   (ovl_legal_top_line), HL
    JP   ovl_legal_doc_redraw

.doc_pgdn:
    LD   A, (ovl_legal_at_eof)
    OR   A
    JP   NZ, ovl_legal_menu     ; at EOF: Space/CR returns to menu (ui_legal.s)
    LD   HL, (ovl_legal_top_line)
    LD   DE, LEGAL_PAGE_ROWS
    ADD  HL, DE
    LD   (ovl_legal_top_line), HL
    JP   ovl_legal_doc_redraw

; ---------------------------------------------------------------------------
; ovl_legal_render_page — Stream from byte 0, skip ovl_legal_top_line lines,
; render up to 20 rows (rows 2..21), detect EOF, draw footer on row 23.
; Output: CF = 1 on read error, CF = 0 on success
; ---------------------------------------------------------------------------
ovl_legal_render_page:
    CALL screen_clear

    LD   B, 0
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_legal_heading
    CALL screen_put_str

    ; Reset stream state
    LD   HL, (ovl_legal_doc_len)
    LD   (ovl_legal_bytes_rem), HL
    LD   HL, 0
    LD   (ovl_legal_cur_rec), HL
    LD   (ovl_legal_cur_line), HL
    LD   A, CPM_RECORD_SIZE
    LD   (ovl_legal_rec_pos), A
    XOR  A
    LD   (ovl_legal_prev_cr), A
    LD   (ovl_legal_io_err), A
    INC  A                      ; at_eof = 1 until a line past page appears
    LD   (ovl_legal_at_eof), A
    LD   A, LEGAL_FIRST_COL
    LD   (ovl_legal_col), A

.stream_loop:
    CALL ovl_legal_next_doc_char
    JR   C, .stream_done        ; CF=1 on EOF or I/O error

    CP   KEY_CR
    JR   NZ, .printable_ch

    ; Newline advances cur_line and resets col = 1
    LD   HL, (ovl_legal_cur_line)
    INC  HL
    LD   (ovl_legal_cur_line), HL
    LD   A, LEGAL_FIRST_COL
    LD   (ovl_legal_col), A
    JR   .stream_loop

.printable_ch:
    LD   (ovl_legal_ch_tmp), A
    LD   A, (ovl_legal_col)
    CP   LEGAL_MAX_COL + 1
    JR   C, .col_ok
    ; Wrap line at col 78
    LD   HL, (ovl_legal_cur_line)
    INC  HL
    LD   (ovl_legal_cur_line), HL
    LD   A, LEGAL_FIRST_COL
    LD   (ovl_legal_col), A

.col_ok:
    ; Compare cur_line against [top_line, top_line + 20)
    LD   HL, (ovl_legal_cur_line)
    LD   DE, (ovl_legal_top_line)
    OR   A
    SBC  HL, DE                 ; HL = cur_line - top_line
    JR   C, .skip_char          ; cur_line < top_line

    LD   A, H
    OR   A
    JR   NZ, .past_page         ; offset >= 256 -> past page
    LD   A, L
    CP   LEGAL_PAGE_ROWS
    JR   NC, .past_page         ; offset >= 20 -> more pages exist!

    ; Visible cell: row = 2 + offset, col = ovl_legal_col
    ADD  A, LEGAL_FIRST_ROW
    LD   B, A
    LD   A, (ovl_legal_col)
    LD   C, A
    INC  A
    LD   (ovl_legal_col), A
    LD   A, (ovl_legal_ch_tmp)
    LD   E, COL_WHITE
    CALL screen_put_char
    JR   .stream_loop

.skip_char:
    LD   A, (ovl_legal_col)
    INC  A
    LD   (ovl_legal_col), A
    JR   .stream_loop

.past_page:
    XOR  A
    LD   (ovl_legal_at_eof), A  ; more content exists after this page

.stream_done:
    LD   A, (ovl_legal_io_err)
    OR   A
    JR   Z, .draw_footer
    SCF
    RET

.draw_footer:
    LD   A, (ovl_legal_at_eof)
    OR   A
    JR   Z, .more_footer
    LD   HL, ovl_legal_end_footer
    JR   .put_footer
.more_footer:
    LD   HL, ovl_legal_more_footer
.put_footer:
    LD   B, SCREEN_ROWS - 1     ; row 23
    LD   C, 1
    LD   E, COL_WHITE
    CALL screen_put_str

    CALL screen_flush
    LD   B, SCREEN_ROWS - 1
    LD   C, 35
    CALL screen_set_cursor
    OR   A                      ; CF = 0
    RET

; Read normalized char from streamed doc (folds CRLF/LF/CR -> KEY_CR).
; Returns A = char (KEY_CR or 0x20..0x7E), CF = 0; CF = 1 on EOF or error.
ovl_legal_next_doc_char:
.next_raw:
    CALL ovl_legal_next_raw_byte
    RET  C                      ; EOF or I/O error (io_err already set if I/O)

    LD   B, A                   ; B = raw byte
    LD   A, (ovl_legal_prev_cr)
    LD   C, A                   ; C = was_cr
    XOR  A
    LD   (ovl_legal_prev_cr), A

    LD   A, B
    CP   KEY_LF
    JR   NZ, .chk_cr
    LD   A, C
    OR   A
    JR   NZ, .next_raw          ; swallow LF immediately after CR
    LD   A, KEY_CR
    OR   A                      ; CF = 0
    RET

.chk_cr:
    CP   KEY_CR
    JR   NZ, .chk_printable
    LD   A, 1
    LD   (ovl_legal_prev_cr), A
    LD   A, KEY_CR
    OR   A
    RET

.chk_printable:
    CP   0x20
    JR   C, .next_raw           ; skip non-EOL control bytes
    CP   0x7F
    JR   NC, .next_raw          ; skip >= 0x7F
    OR   A                      ; CF = 0
    RET

; Read 1 raw byte from MORIA8.DAT doc slot -> A, CF=0; CF=1 on EOF/error.
ovl_legal_next_raw_byte:
    LD   HL, (ovl_legal_bytes_rem)
    LD   A, H
    OR   L
    JR   NZ, .has_bytes
    SCF
    RET
.has_bytes:
    DEC  HL
    LD   (ovl_legal_bytes_rem), HL

    LD   A, (ovl_legal_rec_pos)
    CP   CPM_RECORD_SIZE
    JR   C, .rec_ready

    LD   A, (ovl_legal_doc_slot)
    LD   DE, (ovl_legal_cur_rec)
    LD   HL, cpm_dma_buf
    CALL dat_read_slot_record
    JR   NC, .read_ok
    LD   A, 1
    LD   (ovl_legal_io_err), A
    SCF
    RET
.read_ok:
    LD   HL, (ovl_legal_cur_rec)
    INC  HL
    LD   (ovl_legal_cur_rec), HL
    XOR  A
    LD   (ovl_legal_rec_pos), A

.rec_ready:
    LD   E, A
    INC  A
    LD   (ovl_legal_rec_pos), A
    LD   D, 0
    LD   HL, cpm_dma_buf
    ADD  HL, DE
    LD   A, (HL)
    OR   A                      ; CF = 0
    RET

; ---------------------------------------------------------------------------
; ovl_legal_sysinfo — Moria 8 System Info (6502 ui_legal_sysinfo.s + CP/M hardware).
; ---------------------------------------------------------------------------
ovl_legal_sysinfo:
    CALL screen_hard_clear

    LD   B, 0
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, ovl_legal_sys_heading
    CALL screen_put_str

    ; Row 2: Version
    LD   B, 2
    LD   HL, ovl_legal_lbl_ver
    CALL ovl_legal_begin_row
    LD   HL, ovl_legal_sys_ver
    CALL screen_put_str

    ; Row 3: Format ("Save V2 ($02)  279m/361i")
    LD   B, 3
    LD   HL, ovl_legal_lbl_fmt
    CALL ovl_legal_begin_row
    LD   HL, ovl_legal_sys_fmt
    CALL screen_put_str

    ; Row 4: Display ("80x24  Map: 198x66 (<mode>)")
    LD   B, 4
    LD   HL, ovl_legal_lbl_disp
    CALL ovl_legal_begin_row
    LD   HL, ovl_legal_sys_disp
    CALL _ols_put_adv
    LD   A, (abi_term_mode)
    OR   A
    LD   HL, ovl_legal_mode_adm3a
    JR   Z, .put_disp_mode
    LD   A, (abi_monochrome)
    OR   A
    LD   HL, ovl_legal_mode_mono
    JR   NZ, .put_disp_mode
    LD   HL, ovl_legal_mode_color
.put_disp_mode:
    CALL screen_put_str

    ; Row 6: Platform ("CP/M 2.2 Z80  TPA $XXXX")
    LD   B, 6
    LD   HL, ovl_legal_lbl_plat
    CALL ovl_legal_begin_row
    LD   HL, ovl_legal_sys_plat
    CALL _ols_put_adv
    PUSH BC
    LD   DE, line_buf
    LD   A, '$'
    LD   (DE), A
    INC  DE
    LD   HL, (CPM_BDOS_VEC)
    CALL fmt_u16_hex
    POP  BC
    LD   E, COL_WHITE
    LD   HL, line_buf
    CALL screen_put_str

    ; Row 7: Drives ("Program X:  Save Y:")
    LD   B, 7
    LD   HL, ovl_legal_lbl_drv
    CALL ovl_legal_begin_row
    LD   HL, ovl_legal_drv_prog
    CALL _ols_put_adv
    LD   A, (abi_program_drive)
    ADD  A, 'A'
    PUSH BC
    LD   E, COL_WHITE
    CALL screen_put_char
    POP  BC
    INC  C
    LD   HL, ovl_legal_drv_save
    CALL _ols_put_adv
    LD   A, (abi_save_drive)
    ADD  A, 'A'
    PUSH BC
    LD   E, COL_WHITE
    CALL screen_put_char
    POP  BC
    INC  C
    LD   A, ':'
    LD   E, COL_WHITE
    CALL screen_put_char

    ; Row 8: Assets ("MORIA8.DAT vN (M TOC slots)")
    LD   B, 8
    LD   HL, ovl_legal_lbl_dat
    CALL ovl_legal_begin_row
    LD   DE, line_buf
    LD   HL, ovl_legal_dat_pre
    CALL _ols_copy_cstr
    LD   A, (dat_toc_cache + 1)
    CALL fmt_u8_dec
    LD   HL, ovl_legal_dat_mid
    CALL _ols_copy_cstr
    LD   A, (dat_toc_cache + 2)
    CALL fmt_u8_dec
    LD   HL, ovl_legal_dat_post
    CALL _ols_copy_cstr
    XOR  A
    LD   (DE), A
    LD   B, 8
    LD   C, 11
    LD   E, COL_WHITE
    LD   HL, line_buf
    CALL screen_put_str

    ; Active run telemetry (only when character loaded/created)
    LD   A, (player_data + PL_LEVEL)
    OR   A
    JP   Z, .sys_footer

    ; Row 10: Session ("Turn N  Town" / "Turn N  Dlvl X/Y")
    LD   B, 10
    LD   HL, ovl_legal_lbl_sess
    CALL ovl_legal_begin_row
    LD   DE, line_buf
    LD   HL, ovl_legal_turn_pre
    CALL _ols_copy_cstr
    LD   HL, (abi_turn)
    CALL fmt_u16_dec
    LD   A, (abi_player_dlvl)
    OR   A
    JR   NZ, .in_dng
    LD   HL, ovl_legal_town_str
    CALL _ols_copy_cstr
    JR   .put_sess
.in_dng:
    PUSH AF
    LD   HL, ovl_legal_dlvl_pre
    CALL _ols_copy_cstr
    POP  AF
    CALL fmt_u8_dec
    LD   A, '/'
    LD   (DE), A
    INC  DE
    LD   A, (player_data + PL_MAX_DLVL)
    CALL fmt_u8_dec
.put_sess:
    XOR  A
    LD   (DE), A
    LD   B, 10
    LD   C, 11
    LD   E, COL_WHITE
    LD   HL, line_buf
    CALL screen_put_str

    ; Row 11: Active ("M mon, I items")
    LD   B, 11
    LD   HL, ovl_legal_lbl_act
    CALL ovl_legal_begin_row
    LD   DE, line_buf
    LD   A, (abi_mon_count)
    CALL fmt_u8_dec
    LD   HL, ovl_legal_mon_str
    CALL _ols_copy_cstr
    LD   A, (abi_item_count)
    CALL fmt_u8_dec
    LD   HL, ovl_legal_items_str
    CALL _ols_copy_cstr
    XOR  A
    LD   (DE), A
    LD   B, 11
    LD   C, 11
    LD   E, COL_WHITE
    LD   HL, line_buf
    CALL screen_put_str

    ; Row 12: Mode
    LD   B, 12
    LD   HL, ovl_legal_lbl_mode
    CALL ovl_legal_begin_row
    LD   HL, zp_game_flags
    LD   A, (abi_game_flags)
    OR   (HL)
    LD   D, A
    BIT  2, D                   ; GAME_FLAG_WINNER
    JR   Z, .chk_wiz
    LD   HL, ovl_legal_mode_win
    CALL _ols_put_adv
    BIT  1, D                   ; GAME_FLAG_WIZARD
    JR   Z, .rng_row
    LD   HL, ovl_legal_mode_pwiz
    CALL screen_put_str
    JR   .rng_row
.chk_wiz:
    BIT  1, D
    LD   HL, ovl_legal_mode_wiz
    JR   NZ, .put_mode
    LD   HL, ovl_legal_mode_norm
.put_mode:
    CALL screen_put_str

.rng_row:
    ; Row 13: RNG ("$XXXXXXXX")
    LD   B, 13
    LD   HL, ovl_legal_lbl_rng
    CALL ovl_legal_begin_row
    LD   DE, line_buf
    LD   A, '$'
    LD   (DE), A
    INC  DE
    LD   A, (abi_rng_seed + 0)
    CALL fmt_u8_hex
    LD   A, (abi_rng_seed + 1)
    CALL fmt_u8_hex
    LD   A, (abi_rng_seed + 2)
    CALL fmt_u8_hex
    LD   A, (abi_rng_seed + 3)
    CALL fmt_u8_hex
    LD   B, 13
    LD   C, 11
    LD   E, COL_WHITE
    LD   HL, line_buf
    CALL screen_put_str

.sys_footer:
    LD   B, SCREEN_ROWS - 1
    LD   C, 1
    LD   E, COL_LGREY
    LD   A, (legal_entry_mode)
    OR   A
    LD   HL, ovl_legal_sys_foot_menu
    JR   Z, .draw_foot
    LD   HL, ovl_legal_sys_foot_dir
.draw_foot:
    CALL screen_put_str
    CALL screen_flush
    LD   B, SCREEN_ROWS - 1
    LD   C, 31
    CALL screen_set_cursor

.sys_wait:
    CALL input_get_key
    CP   KEY_ESC
    JR   Z, .leave
    CP   KEY_SPACE
    JR   Z, .leave
    CP   KEY_CR
    JR   Z, .leave
    CP   'a'
    JR   C, .sys_chk
    CP   'z' + 1
    JR   NC, .sys_chk
    AND  0xDF
.sys_chk:
    CP   'L'
    JR   Z, .go_menu
    CP   'Q'
    JR   NZ, .sys_wait
.leave:
    LD   A, (legal_entry_mode)
    OR   A
    RET  NZ
    JP   ovl_legal_menu
.go_menu:
    JP   ovl_legal_menu

; Begin SysInfo row B with label HL in COL_CYAN at col 1; returns B=row, C=11, E=COL_WHITE.
ovl_legal_begin_row:
    PUSH BC
    LD   C, 1
    LD   E, COL_CYAN
    CALL screen_put_str
    POP  BC
    LD   C, 11
    LD   E, COL_WHITE
    RET

; Put HL at (B, C) in COL_WHITE, preserving B and advancing C past string.
_ols_put_adv:
    PUSH BC
    PUSH HL
    LD   E, COL_WHITE
    CALL screen_put_str
    POP  HL
    POP  BC
.lp:
    LD   A, (HL)
    OR   A
    RET  Z
    INC  HL
    INC  C
    JR   .lp

; Copy NUL-terminated HL to DE without writing trailing NUL (leaves DE at end).
_ols_copy_cstr:
    LD   A, (HL)
    OR   A
    RET  Z
    LD   (DE), A
    INC  HL
    INC  DE
    JR   _ols_copy_cstr

; ---------------------------------------------------------------------------
; Overlay RO Strings & Local Scratch (inside 0x5600..0x69FF window)
; ---------------------------------------------------------------------------
ovl_legal_heading:
    DB   "License & Source", 0
ovl_legal_copyright:
    DB   "Copyright (C) 2026 Chad Gibbons", 0
ovl_legal_rights:
    DB   "You may modify and redistribute.", 0
ovl_legal_warranty:
    DB   "GPLv3 or later. No warranty.", 0
ovl_legal_choices:
    DB   "1 License  2 Source  3 Info  Q Back", 0
ovl_legal_more_footer:
    DB   "Space: next  R: restart  Q: back", 0
ovl_legal_end_footer:
    DB   "End. R: restart  Q: back", 0
ovl_legal_err_str:
    DB   "Document read failed. Press any key.", 0

ovl_legal_sys_heading:
    DB   "Moria 8 - System Info", 0
ovl_legal_lbl_ver:
    DB   "Version:", 0
ovl_legal_lbl_fmt:
    DB   "Format:", 0
ovl_legal_lbl_disp:
    DB   "Display:", 0
ovl_legal_lbl_plat:
    DB   "Platform:", 0
ovl_legal_lbl_drv:
    DB   "Drives:", 0
ovl_legal_lbl_dat:
    DB   "Assets:", 0
ovl_legal_lbl_sess:
    DB   "Session:", 0
ovl_legal_lbl_act:
    DB   "Active:", 0
ovl_legal_lbl_mode:
    DB   "Mode:", 0
ovl_legal_lbl_rng:
    DB   "RNG:", 0

ovl_legal_sys_ver:
    EmitTitleVersion
    DB   0
ovl_legal_sys_fmt:
    DB   "Save V2 ($22)  279m/361i", 0
ovl_legal_sys_disp:
    DB   "80x24  Map: 198x66 ", 0
ovl_legal_mode_adm3a:
    DB   "(ADM-3A)", 0
ovl_legal_mode_color:
    DB   "(ANSI Color)", 0
ovl_legal_mode_mono:
    DB   "(ANSI Mono)", 0
ovl_legal_sys_plat:
    DB   "CP/M 2.2 Z80  TPA ", 0
ovl_legal_drv_prog:
    DB   "Program ", 0
ovl_legal_drv_save:
    DB   ":  Save ", 0
ovl_legal_dat_pre:
    DB   "MORIA8.DAT v", 0
ovl_legal_dat_mid:
    DB   " (", 0
ovl_legal_dat_post:
    DB   " TOC slots)", 0
ovl_legal_turn_pre:
    DB   "Turn ", 0
ovl_legal_town_str:
    DB   "  Town", 0
ovl_legal_dlvl_pre:
    DB   "  Dlvl ", 0
ovl_legal_mon_str:
    DB   " mon, ", 0
ovl_legal_items_str:
    DB   " items", 0
ovl_legal_mode_norm:
    DB   "Normal", 0
ovl_legal_mode_wiz:
    DB   "Wizard", 0
ovl_legal_mode_win:
    DB   "Winner", 0
ovl_legal_mode_pwiz:
    DB   " + Wiz", 0
ovl_legal_sys_foot_menu:
    DB   "L: License menu  Q/Space: back", 0
ovl_legal_sys_foot_dir:
    DB   "L: License  Q/Esc/Space: back", 0

ovl_legal_doc_slot:
    DB   0
ovl_legal_doc_len:
    DW   0
ovl_legal_top_line:
    DW   0
ovl_legal_bytes_rem:
    DW   0
ovl_legal_cur_rec:
    DW   0
ovl_legal_cur_line:
    DW   0
ovl_legal_rec_pos:
    DB   0
ovl_legal_prev_cr:
    DB   0
ovl_legal_at_eof:
    DB   0
ovl_legal_io_err:
    DB   0
ovl_legal_col:
    DB   0
ovl_legal_ch_tmp:
    DB   0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_legal.ovl", ovl_start, ovl_end - ovl_start
