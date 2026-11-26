; ovl_title.asm — Moria8 CP/M Title Screen Overlay (OVL_TITLE, DAT slot 12).
;
; Streams DAT_ID_TITLE_ART, decodes Huffman greeting via huff_decode_string,
; displays version, menu, color/mono status badge, handles A (nested OVL_LEGAL),
; M (runtime monochrome toggle), N/L/D (M2 stub), and Q/ESC (clean exit).
;
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax, DEVICE NOSLOT64K).

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "main_exp.inc"

    ORG  OVL_WINDOW_BASE        ; 0x5600

ovl_start:
    JP   ovl_title_enter

; ---------------------------------------------------------------------------
; ovl_title_enter — Draw Title screen and run Title command loop.
; Returns cleanly to resident main.asm via overlay_trampoline with:
;   A = 0 (Quit/ESC), 1 (New Game), 2 (Load Game); CF = 0.
; ---------------------------------------------------------------------------
ovl_title_enter:
    CALL ovl_title_draw_screen

ovl_title_loop:
    CALL input_get_key
    CP   KEY_ESC
    JR   Z, .do_quit

    ; Uppercase ASCII 'a'..'z' without altering 0x80+ navigation codes
    CP   'a'
    JR   C, .chk_cmd
    CP   'z' + 1
    JR   NC, .chk_cmd
    AND  0xDF

.chk_cmd:
    CP   'Q'
    JR   Z, .do_quit
    CP   'A'
    JR   Z, .do_legal
    CP   'M'
    JR   Z, .do_mono_toggle
    CP   'N'
    JR   Z, .do_new_game
    CP   'L'
    JR   Z, .do_load_game
    CP   'D'
    JR   Z, .do_disk_setup
    JR   ovl_title_loop

.do_quit:
    XOR  A
    RET

.do_legal:
    XOR  A
    LD   (legal_entry_mode), A
    CALL tramp_legal_viewer
    JR   C, .legal_err
    JR   .toggle_redraw

.legal_err:
    LD   B, INPUT_ROW
    CALL screen_clear_row
    LD   B, INPUT_ROW
    LD   C, (SCREEN_COLS - (ovl_title_legal_err_end - ovl_title_legal_err_msg)) / 2
    LD   E, COL_RED
    LD   HL, ovl_title_legal_err_msg
    CALL screen_put_str
    CALL screen_flush
    LD   B, INPUT_ROW
    LD   C, 54
    CALL screen_set_cursor
    JR   ovl_title_loop

.do_mono_toggle:
    LD   A, (abi_term_mode)
    OR   A
    JR   Z, .toggle_to_color
    LD   A, (abi_monochrome)
    OR   A
    JR   Z, .toggle_to_mono
    XOR  A
    LD   (abi_term_mode), A
    LD   A, 1
    LD   (abi_monochrome), A
    JR   .toggle_redraw
.toggle_to_color:
    LD   A, 1
    LD   (abi_term_mode), A
    XOR  A
    LD   (abi_monochrome), A
    JR   .toggle_redraw
.toggle_to_mono:
    LD   A, 1
    LD   (abi_monochrome), A
.toggle_redraw:
    CALL screen_hard_clear
    JP   ovl_title_enter

.do_new_game:
    CALL sound_bell
    LD   A, 1
    OR   A
    RET

.do_load_game:
    CALL sound_bell
    LD   A, 2
    OR   A
    RET

.do_disk_setup:
    CALL tramp_disk_setup
    JR   .toggle_redraw

; ---------------------------------------------------------------------------
; ovl_title_draw_screen — Render title art, Huffman greeting, menu, & status.
; ---------------------------------------------------------------------------
ovl_title_draw_screen:
    CALL screen_clear

    ; Stream DAT_ID_TITLE_ART segments into shadow buffers
    CALL ovl_title_draw_art

    ; Menu row 18 inside frame: "N)ew  L)oad  D)isk Setup  A)bout" (matching 6502 ports)
    LD   B, 18
    LD   C, (SCREEN_COLS - (ovl_title_menu_end - ovl_title_menu_str)) / 2
    LD   E, COL_WHITE
    LD   HL, ovl_title_menu_str
    CALL screen_put_str

    ; Row 21: "[Save: X:]" centered when save drive was configured via Disk Setup
    LD   A, (disk_setup_done)
    OR   A
    JR   Z, .skip_save_drv
    LD   B, 21
    LD   C, 35
    LD   E, COL_CYAN
    LD   HL, ovl_title_save_ind_pfx
    CALL screen_put_str
    LD   A, (abi_save_drive)
    ADD  A, 'A'
    LD   B, 21
    LD   C, 42
    LD   E, COL_CYAN
    CALL screen_put_char
    LD   B, 21
    LD   C, 43
    LD   E, COL_CYAN
    LD   HL, ovl_title_save_ind_sfx
    CALL screen_put_str
.skip_save_drv:

    ; Row 23: concise centered system info matching 6502 title_sysinfo
    LD   B, 23
    LD   C, 24
    LD   E, COL_DGREY
    LD   HL, ovl_title_sysinfo_pfx
    CALL screen_put_str

    LD   A, (abi_program_drive)
    ADD  A, 'A'
    LD   B, 23
    LD   C, 44
    LD   E, COL_DGREY
    CALL screen_put_char

    LD   B, 23
    LD   C, 45
    LD   E, COL_DGREY
    LD   HL, ovl_title_drv_sep
    CALL screen_put_str

    LD   A, (abi_term_mode)
    OR   A
    JR   NZ, .draw_ansi_badge
    LD   HL, ovl_title_badge_adm3a
    JR   .draw_badge
.draw_ansi_badge:
    LD   A, (abi_monochrome)
    OR   A
    JR   NZ, .draw_mono_badge
    LD   HL, ovl_title_badge_color
    JR   .draw_badge
.draw_mono_badge:
    LD   HL, ovl_title_badge_mono
.draw_badge:
    LD   B, 23
    LD   C, 48
    LD   E, COL_DGREY | CPM_ATTR_REVERSE
    CALL screen_put_str

    CALL screen_flush
    LD   B, INPUT_ROW
    LD   C, 40
    JP   screen_set_cursor

; ---------------------------------------------------------------------------
; ovl_title_draw_art — Stream DAT_ID_TITLE_ART into shadow screen.
; Record format: [row, col, color, len, ascii[len]..., 0xFF terminator].
; ---------------------------------------------------------------------------
ovl_title_draw_art:
    LD   A, DAT_ID_TITLE_ART
    CALL dat_get_cold_byte_len  ; HL = byte_len
    JR   C, .art_err
    LD   A, H
    OR   L
    JR   Z, .art_err

    LD   (ovl_title_bytes_rem), HL
    LD   HL, 0
    LD   (ovl_title_cur_rec), HL
    LD   A, CPM_RECORD_SIZE
    LD   (ovl_title_rec_pos), A ; force record 0 load on first read

.art_seg_loop:
    CALL ovl_title_next_art_byte
    RET  C                      ; EOF
    CP   0xFF
    RET  Z                      ; explicit 0xFF end marker
    LD   (ovl_title_seg_row), A

    CALL ovl_title_next_art_byte
    RET  C
    LD   (ovl_title_seg_col), A

    CALL ovl_title_next_art_byte
    RET  C
    LD   (ovl_title_seg_colr), A

    CALL ovl_title_next_art_byte
    RET  C
    OR   A
    JR   Z, .art_seg_loop
    LD   (ovl_title_seg_len), A

.art_char_loop:
    CALL ovl_title_next_art_byte
    RET  C
    LD   D, A
    LD   A, (ovl_title_seg_row)
    LD   B, A
    LD   A, (ovl_title_seg_col)
    LD   C, A
    INC  A
    LD   (ovl_title_seg_col), A
    LD   A, (ovl_title_seg_colr)
    LD   E, A
    LD   A, D
    CALL screen_put_char
    LD   A, (ovl_title_seg_len)
    DEC  A
    LD   (ovl_title_seg_len), A
    JR   NZ, .art_char_loop
    JR   .art_seg_loop

.art_err:
    LD   B, 12
    LD   C, 25
    LD   E, COL_RED
    LD   HL, ovl_title_art_err_str
    JP   screen_put_str

; Read next byte from streamed DAT_ID_TITLE_ART -> A, CF=0; CF=1 on EOF/error
ovl_title_next_art_byte:
    LD   HL, (ovl_title_bytes_rem)
    LD   A, H
    OR   L
    JR   NZ, .has_bytes
    SCF
    RET
.has_bytes:
    DEC  HL
    LD   (ovl_title_bytes_rem), HL

    LD   A, (ovl_title_rec_pos)
    CP   CPM_RECORD_SIZE
    JR   C, .buf_ready

    LD   A, DAT_ID_TITLE_ART
    LD   DE, (ovl_title_cur_rec)
    LD   HL, cpm_dma_buf
    CALL dat_read_slot_record
    RET  C
    LD   HL, (ovl_title_cur_rec)
    INC  HL
    LD   (ovl_title_cur_rec), HL
    XOR  A
    LD   (ovl_title_rec_pos), A

.buf_ready:
    LD   E, A
    INC  A
    LD   (ovl_title_rec_pos), A
    LD   D, 0
    LD   HL, cpm_dma_buf
    ADD  HL, DE
    LD   A, (HL)
    OR   A                      ; CF = 0, preserves A
    RET

; ---------------------------------------------------------------------------
; Overlay RO Strings & Local Scratch (inside 0x5600..0x69FF window)
; ---------------------------------------------------------------------------
ovl_title_menu_str:
    DB   "N)ew  L)oad  D)isk Setup  A)bout"
ovl_title_menu_end:
    DB   0

ovl_title_legal_err_msg:
    DB   "Unable to load Legal Viewer."
ovl_title_legal_err_end:
    DB   0

ovl_title_sysinfo_pfx:
    DB   "CP/M 2.2 Z80  Drive ", 0

ovl_title_drv_sep:
    DB   ":  ", 0

ovl_title_save_ind_pfx:
    DB   "[Save: ", 0

ovl_title_save_ind_sfx:
    DB   ":]", 0

ovl_title_badge_adm3a:
    DB   "[ADM-3A]", 0
ovl_title_badge_color:
    DB   "[Color] ", 0
ovl_title_badge_mono:
    DB   "[Mono]  ", 0

ovl_title_art_err_str:
    DB   "Failed to stream title art.", 0

ovl_title_bytes_rem:
    DW   0
ovl_title_cur_rec:
    DW   0
ovl_title_rec_pos:
    DB   0
ovl_title_seg_row:
    DB   0
ovl_title_seg_col:
    DB   0
ovl_title_seg_colr:
    DB   0
ovl_title_seg_len:
    DB   0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_title.ovl", ovl_start, ovl_end - ovl_start
