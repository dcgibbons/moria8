; messages.asm — Top 2-row message bar (rows 0..1), "--more--" overflow wait,
; and 8 x 80 message history ring buffer.
;
; Resident core module included once by platforms/z80/cpm/main.asm.
; Uses pure 0xNN hex syntax for sjasmplus v1.24.0 (DEVICE NOSLOT64K).
; All public entry points preserve IX and IY.

    IFNDEF CORE_Z80_MESSAGES_ASM
    DEFINE CORE_Z80_MESSAGES_ASM 1

    EXPORT msg_init
    EXPORT msg_print_str
    EXPORT msg_print_huff
    EXPORT msg_clear
    EXPORT msg_show_more

MSG_MORE_STR_LEN    EQU 7       ; " -more-"
MSG_MORE_MAX_COL    EQU (SCREEN_COLS - MSG_MORE_STR_LEN)

; ============================================================
; msg_init — Clear message flags, rows 0..1, and 8x80 history buffer.
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
msg_init:
    XOR  A
    LD   (zp_msg_flags), A
    LD   (msg_hist_idx), A
    LD   (msg_hist_count_used), A
    LD   (msg_row1_col), A
    LD   HL, msg_history
    LD   DE, msg_history + 1
    LD   BC, MSG_HIST_BYTES - 1
    LD   (HL), ' '
    LDIR
    LD   B, MSG_ROW0
    CALL screen_clear_row
    LD   B, MSG_ROW1
    JP   screen_clear_row

; ============================================================
; msg_clear — Clear rows 0..1 when unread messages are pending.
; Preserves: BC, DE, HL, IX, IY (clobbers AF)
; ============================================================
msg_clear:
    LD   A, (zp_msg_flags)
    OR   A
    RET  Z
    PUSH BC
    PUSH DE
    PUSH HL
    LD   B, MSG_ROW0
    CALL screen_clear_row
    LD   B, MSG_ROW1
    CALL screen_clear_row
    XOR  A
    LD   (zp_msg_flags), A
    LD   (msg_row1_col), A
    POP  HL
    POP  DE
    POP  BC
    RET

; ============================================================
; msg_print_huff — Decode Huffman string A into temp_str_buf and print it.
; Input:  A = HSTR_* string index
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
msg_print_huff:
    LD   DE, temp_str_buf
    CALL huff_decode_string     ; HL = temp_str_buf, CF = 1 on error
    RET  C
    ; fall through to msg_print_str

; ============================================================
; msg_print_str — Display NUL-terminated ASCII message HL on rows 0..1.
; Handles "--more--" pause when both rows already hold unread messages,
; and saves message to the 8x80 ring buffer.
; Input:  HL = NUL-terminated ASCII string
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
msg_print_str:
    PUSH HL                     ; [src_str]
    LD   A, (zp_msg_flags)
    CP   MSG_PENDING | MSG_FULL
    JR   NZ, .no_more

    ; Both rows occupied: append " -more-" (moving to row 0 if row 1 is tight), flush, await key
    CALL msg_show_more
    CALL input_get_key
    XOR  A
    LD   (zp_msg_flags), A
    LD   (msg_row1_col), A

.no_more:
    LD   A, (zp_msg_flags)
    AND  MSG_PENDING
    JR   NZ, .use_row1

    ; Print on row 0, clearing row 1
    LD   B, MSG_ROW0
    CALL screen_clear_row
    LD   B, MSG_ROW1
    CALL screen_clear_row
    POP  HL
    PUSH HL
    LD   B, MSG_ROW0
    LD   C, 0
    LD   E, COL_MSG_TEXT
    CALL screen_put_str
    LD   A, MSG_PENDING
    LD   (zp_msg_flags), A
    JR   .save_hist

.use_row1:
    LD   B, MSG_ROW1
    CALL screen_clear_row
    POP  HL
    PUSH HL
    CALL _msg_str_len           ; A = min(len, 79)
    LD   (msg_row1_col), A
    LD   B, MSG_ROW1
    LD   C, 0
    LD   E, COL_MSG_TEXT
    CALL screen_put_str
    LD   A, MSG_PENDING | MSG_FULL
    LD   (zp_msg_flags), A

.save_hist:
    POP  HL
    ; Record HL into msg_history[msg_hist_idx]
    LD   A, (msg_hist_idx)
    LD   E, A
    INC  A
    AND  MSG_HIST_COUNT - 1
    LD   (msg_hist_idx), A
    LD   A, (msg_hist_count_used)
    CP   MSG_HIST_COUNT
    JR   NC, .cnt_full
    INC  A
    LD   (msg_hist_count_used), A
.cnt_full:
    CALL _msg_slot_ptr_de       ; E = slot 0..7 -> DE = &msg_history[E * 80]
    LD   B, MSG_HIST_LEN - 1
.copy_h:
    LD   A, (HL)
    OR   A
    JR   Z, .pad_h
    LD   (DE), A
    INC  HL
    INC  DE
    DJNZ .copy_h
.pad_h:
    XOR  A
    LD   (DE), A
    RET

; Clamped length 0..79 of NUL-terminated HL -> A. Preserves HL.
_msg_str_len:
    PUSH HL
    LD   B, 0
.lp:
    LD   A, (HL)
    OR   A
    JR   Z, .done
    INC  HL
    INC  B
    LD   A, B
    CP   SCREEN_COLS - 1
    JR   C, .lp
.done:
    LD   A, B
    POP  HL
    RET

; Slot E (0..7) -> DE = msg_history + E * 80. Preserves HL.
_msg_slot_ptr_de:
    PUSH HL
    LD   L, E
    LD   H, 0
    ADD  HL, HL                 ; * 2
    ADD  HL, HL                 ; * 4
    ADD  HL, HL                 ; * 8
    ADD  HL, HL                 ; * 16
    LD   D, H
    LD   E, L                   ; * 16
    ADD  HL, HL                 ; * 32
    ADD  HL, HL                 ; * 64
    ADD  HL, DE                 ; * 80
    LD   DE, msg_history
    ADD  HL, DE
    EX   DE, HL
    POP  HL
    RET

msg_show_more:
    LD   B, MSG_ROW1
    LD   A, (msg_row1_col)
    CP   MSG_MORE_MAX_COL + 1
    JR   C, .col_ok
    LD   A, MSG_MORE_MAX_COL
    LD   B, MSG_ROW0
.col_ok:
    LD   C, A
    LD   E, COL_WHITE
    LD   HL, _msg_more_str
    CALL screen_put_str
    JP   screen_flush

_msg_more_str: DB " -more-", 0

    ENDIF
