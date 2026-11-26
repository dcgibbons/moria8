; screen_ansi.asm — 80x24 dual-shadow ANSI/VT100 diff renderer.
;
; Requires main.asm to INCLUDE "memory.inc", "defs.inc", "state.inc",
; "bdos_io.asm", and "huffman.asm" (sgr_lut).
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax).
;
; Contracts enforced:
;   - cpm_char_shadow (0x8E00, 1920 B) + cpm_color_shadow (0x9580, 1920 B)
;   - screen_hard_clear emits ESC[0m BEFORE ESC[2J + ESC[H
;   - screen_flush skips clean cells via BIT 7, (HL) : JR Z
;   - sgr_lut[color] only emitted when abi_monochrome == 0; bold/reverse preserved
;   - writing col 79 invalidates screen_cursor_valid = 0 for VT100 xenl wrap

    EXPORT screen_init
    EXPORT screen_hard_clear
    EXPORT screen_clear
    EXPORT screen_clear_row
    EXPORT screen_put_char
    EXPORT screen_put_str
    EXPORT screen_flush
    EXPORT screen_set_cursor

SCREEN_DEFAULT_ATTR EQU COL_LGREY   ; 0x0F logical light grey (matches ANSI SGR 0 fg 37)

; ---------------------------------------------------------------------------
; screen_init — Clear shadow buffers cleanly and invalidate cursor/SGR cache.
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ---------------------------------------------------------------------------
screen_init:
    CALL _screen_fill_shadows_clean
    XOR  A
    LD   (screen_cursor_valid), A
    LD   A, 0xFF
    LD   (screen_emit_sgr), A
    RET

; ---------------------------------------------------------------------------
; screen_hard_clear — Reset terminal SGR (ESC[0m), clear screen (ESC[2J+ESC[H),
; reset shadows to clean spaces with dirty=0, and reset emit cursor (0,0).
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ---------------------------------------------------------------------------
screen_hard_clear:
    LD   A, (abi_term_mode)
    OR   A
    JR   Z, .hc_adm3a
    LD   HL, .str_hard_clear    ; ESC[0m MUST precede ESC[2J
    CALL bdos_puts_asciiz
    JR   .hc_shadows
.hc_adm3a:
    LD   A, 0x1A                ; ADM-3A clear screen + home cursor
    CALL bdos_rawio_putc
.hc_shadows:
    CALL _screen_fill_shadows_clean
    XOR  A
    LD   (screen_emit_row), A
    LD   (screen_emit_col), A
    LD   B, A                   ; B = 0 (clean mono SGR state)
    INC  A
    LD   (screen_cursor_valid), A
    LD   A, (abi_monochrome)
    OR   A
    LD   A, B                   ; mono -> 0x00 (bold=0, rev=0)
    JR   NZ, .hc_sgr_set
    LD   A, SCREEN_DEFAULT_ATTR ; color -> COL_LGREY (37, bold=0, rev=0)
.hc_sgr_set:
    LD   (screen_emit_sgr), A
    RET

.str_hard_clear:
    DB   KEY_ESC, "[0m", KEY_ESC, "[2J", KEY_ESC, "[H", 0

; Internal: fill cpm_char_shadow with ' ' and cpm_color_shadow with clean default attr.
_screen_fill_shadows_clean:
    LD   HL, CPM_CHAR_SHADOW_BASE
    LD   DE, CPM_CHAR_SHADOW_BASE + 1
    LD   BC, CPM_CHAR_SHADOW_SIZE - 1
    LD   (HL), ' '
    LDIR
    LD   HL, CPM_COLOR_SHADOW_BASE
    LD   DE, CPM_COLOR_SHADOW_BASE + 1
    LD   BC, CPM_COLOR_SHADOW_SIZE - 1
    LD   (HL), SCREEN_DEFAULT_ATTR
    LDIR
    RET

; ---------------------------------------------------------------------------
; screen_clear — Set every cell to (' ', SCREEN_DEFAULT_ATTR), marking changed
; cells with CPM_ATTR_DIRTY.
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ---------------------------------------------------------------------------
screen_clear:
    LD   HL, CPM_CHAR_SHADOW_BASE
    LD   DE, CPM_COLOR_SHADOW_BASE
    LD   BC, SCREEN_CELLS
.clr_loop:
    LD   A, (HL)
    CP   ' '
    JR   NZ, .clr_mark
    LD   A, (DE)
    AND  0x7F
    CP   SCREEN_DEFAULT_ATTR
    JR   Z, .clr_next
.clr_mark:
    LD   (HL), ' '
    LD   A, SCREEN_DEFAULT_ATTR | CPM_ATTR_DIRTY
    LD   (DE), A
.clr_next:
    INC  HL
    INC  DE
    DEC  BC
    LD   A, B
    OR   C
    JR   NZ, .clr_loop
    RET

; ---------------------------------------------------------------------------
; screen_clear_row — Clear row B (0..23), marking changed cells CPM_ATTR_DIRTY.
; Input:  B = row (0..23)
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ---------------------------------------------------------------------------
screen_clear_row:
    LD   A, B
    CP   SCREEN_ROWS
    RET  NC
    CALL _screen_calc_row_offset ; HL = row * 80
    LD   DE, CPM_CHAR_SHADOW_BASE
    ADD  HL, DE                 ; HL = &cpm_char_shadow[row * 80]
    PUSH HL
    LD   DE, CPM_CHAR_SHADOW_SIZE
    ADD  HL, DE
    EX   DE, HL                 ; DE = &cpm_color_shadow[row * 80]
    POP  HL                     ; HL = &cpm_char_shadow[row * 80]
    LD   B, SCREEN_COLS
.crow_loop:
    LD   A, (HL)
    CP   ' '
    JR   NZ, .crow_mark
    LD   A, (DE)
    AND  0x7F
    CP   SCREEN_DEFAULT_ATTR
    JR   Z, .crow_next
.crow_mark:
    LD   (HL), ' '
    LD   A, SCREEN_DEFAULT_ATTR | CPM_ATTR_DIRTY
    LD   (DE), A
.crow_next:
    INC  HL
    INC  DE
    DJNZ .crow_loop
    RET

; ---------------------------------------------------------------------------
; screen_put_char — Write one cell if (char, attr & 0x7F) changed; sets dirty bit.
; Input:  B = row (0..23), C = col (0..79), A = ASCII char, E = attr (0..0x7F)
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ---------------------------------------------------------------------------
screen_put_char:
    PUSH AF
    LD   A, B
    CP   SCREEN_ROWS
    JR   NC, .put_oob
    LD   A, C
    CP   SCREEN_COLS
    JR   NC, .put_oob
    LD   A, B
    CALL _screen_calc_row_offset ; HL = row * 80 (preserves BC, DE)
    LD   B, 0
    ADD  HL, BC                 ; HL = row * 80 + col
    LD   BC, CPM_CHAR_SHADOW_BASE
    ADD  HL, BC                 ; HL = &cpm_char_shadow[idx]
    LD   A, E
    AND  0x7F
    LD   C, A                   ; C = attr & 0x7F
    POP  AF
    LD   B, A                   ; B = char
    LD   DE, CPM_CHAR_SHADOW_SIZE
    LD   A, (HL)
    CP   B
    JR   NZ, .put_changed
    ADD  HL, DE                 ; HL = &cpm_color_shadow[idx]
    LD   A, (HL)
    AND  0x7F
    CP   C
    RET  Z                      ; identical char and attr -> no-op
    LD   A, C
    OR   CPM_ATTR_DIRTY
    LD   (HL), A
    RET
.put_changed:
    LD   (HL), B
    ADD  HL, DE
    LD   A, C
    OR   CPM_ATTR_DIRTY
    LD   (HL), A
    RET
.put_oob:
    POP  AF
    RET

; ---------------------------------------------------------------------------
; screen_put_str — Write NUL-terminated string starting at (B, C), clipped at col 79.
; Input:  B = row (0..23), C = col (0..79), E = attr (0..0x7F), HL = NUL string
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ---------------------------------------------------------------------------
screen_put_str:
    LD   A, B
    CP   SCREEN_ROWS
    RET  NC
    LD   A, C
    CP   SCREEN_COLS
    RET  NC
    PUSH IY
    PUSH HL                     ; save string pointer
    LD   A, B
    CALL _screen_calc_row_offset ; HL = row * 80
    LD   B, 0
    ADD  HL, BC                 ; HL = row * 80 + col
    LD   A, SCREEN_COLS
    SUB  C
    LD   B, A                   ; B = remaining cols (1..80)
    LD   A, E
    AND  0x7F
    LD   C, A                   ; C = attr & 0x7F
    LD   DE, CPM_CHAR_SHADOW_BASE
    ADD  HL, DE                 ; HL = &cpm_char_shadow[idx]
    LD   E, L
    LD   D, H                   ; DE = &cpm_char_shadow[idx]
    PUSH BC
    LD   BC, CPM_CHAR_SHADOW_SIZE
    ADD  HL, BC                 ; HL = &cpm_color_shadow[idx]
    POP  BC
    PUSH HL
    POP  IY                     ; IY = &cpm_color_shadow[idx]
    POP  HL                     ; HL = string pointer
.pstr_loop:
    LD   A, (HL)
    OR   A
    JR   Z, .pstr_done
    EX   DE, HL                 ; HL = char_shadow, DE = str
    CP   (HL)
    JR   NZ, .pstr_diff
    LD   A, (IY + 0)
    AND  0x7F
    CP   C
    JR   Z, .pstr_next
    LD   A, C
    OR   CPM_ATTR_DIRTY
    LD   (IY + 0), A
    JR   .pstr_next
.pstr_diff:
    LD   (HL), A
    LD   A, C
    OR   CPM_ATTR_DIRTY
    LD   (IY + 0), A
.pstr_next:
    EX   DE, HL                 ; HL = str, DE = char_shadow
    INC  HL
    INC  DE
    INC  IY
    DJNZ .pstr_loop
.pstr_done:
    POP  IY
    RET

; ---------------------------------------------------------------------------
; screen_flush — Differential ANSI flush of all dirty shadow cells (0..1919).
; Hot clean-cell scan uses BIT 7, (HL) : JR NZ branch-out (38 T-states/clean cell),
; computes cpm_char_shadow via -0x0780 only on dirty hits, tracks cursor & SGR,
; and invalidates cursor tracking after col 79 (VT100 deferred wrap xenl).
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ---------------------------------------------------------------------------
screen_flush:
    LD   HL, CPM_COLOR_SHADOW_BASE
    LD   D, 0                   ; D = row (0..23)
.fl_row_loop:
    LD   B, SCREEN_COLS         ; B = 80..1 (col = 80 - B)
.fl_col_loop:
    BIT  7, (HL)                ; 12 T
    JR   NZ, .fl_dirty          ;  7 T fall-through on clean cell
.fl_clean:
    INC  HL                     ;  6 T
    DJNZ .fl_col_loop           ; 13 T
    INC  D
    LD   A, D
    CP   SCREEN_ROWS
    JR   NZ, .fl_row_loop
    RET

.fl_dirty:
    ; Dirty cell at (D = row, col = 80 - B); HL = &cpm_color_shadow[idx]
    LD   C, (HL)                ; C = raw color byte (bit 7 = 1)
    RES  7, (HL)                ; clear dirty bit
    PUSH HL                     ; [color_ptr]
    PUSH DE                     ; [color_ptr, row]
    PUSH BC                     ; [color_ptr, row, B=djnz_cnt / C=raw]
    LD   A, SCREEN_COLS
    SUB  B
    LD   E, A                   ; D = row, E = col
    LD   A, C
    AND  0x7F
    PUSH AF                     ; save attr & 0x7F
    LD   BC, -CPM_CHAR_SHADOW_SIZE  ; -0x0780 offset to cpm_char_shadow
    ADD  HL, BC                 ; HL = &cpm_char_shadow[idx]
    LD   B, (HL)                ; B = char byte
    POP  AF
    LD   C, A                   ; C = attr & 0x7F

    ; Clamp char to printable ASCII [0x20..0x7E] so 0xFF/control never leaks
    LD   A, B
    CP   0x20
    JR   C, .fl_bad_ch
    CP   0x7F
    JR   C, .fl_ch_ok
.fl_bad_ch:
    LD   B, ' '
.fl_ch_ok:

    ; Check if cursor is already tracked at (D, E)
    LD   A, (screen_cursor_valid)
    OR   A
    JR   Z, .fl_need_cup
    LD   A, (screen_emit_row)
    CP   D
    JR   NZ, .fl_need_cup
    LD   A, (screen_emit_col)
    CP   E
    JR   Z, .fl_cur_ok
.fl_need_cup:
    PUSH BC
    LD   B, D
    LD   C, E
    CALL _screen_emit_cup       ; emits ESC[row+1;col+1H (preserves DE)
    POP  BC
.fl_cur_ok:

    ; ADM-3A emits no SGR/attribute escapes
    LD   A, (abi_term_mode)
    OR   A
    JR   Z, .fl_sgr_ok

    ; Compute effective attribute & check against screen_emit_sgr
    LD   A, (abi_monochrome)
    OR   A
    JR   Z, .fl_color_attr
    LD   A, C
    AND  CPM_ATTR_BOLD | CPM_ATTR_REVERSE
    JR   .fl_chk_sgr
.fl_color_attr:
    LD   A, C
    AND  CPM_ATTR_COLOR_MASK | CPM_ATTR_BOLD | CPM_ATTR_REVERSE
.fl_chk_sgr:
    LD   HL, screen_emit_sgr
    CP   (HL)
    JR   Z, .fl_sgr_ok
    LD   H, (HL)                ; H = previous SGR state
    LD   (screen_emit_sgr), A
    CALL _screen_emit_sgr       ; A = new_attr, H = prev_sgr (preserves BC, DE)
.fl_sgr_ok:

    ; Emit printable cell byte
    LD   A, B
    CALL bdos_rawio_putc

    ; Update cursor tracker; invalidate after col 79 (VT100 xenl deferred wrap)
    LD   A, E
    CP   SCREEN_COLS - 1
    JR   Z, .fl_col79
    INC  A
    LD   (screen_emit_col), A
    LD   A, D
    LD   (screen_emit_row), A
    LD   A, 1
    LD   (screen_cursor_valid), A
    JR   .fl_next_cell
.fl_col79:
    XOR  A
    LD   (screen_cursor_valid), A
.fl_next_cell:
    POP  BC
    POP  DE
    POP  HL
    JP   .fl_clean

; ---------------------------------------------------------------------------
; screen_set_cursor — Position physical ANSI cursor for prompt placement.
; Input:  B = row (0..23), C = col (0..79)
; Preserves: IX, IY (clobbers AF, HL)
; ---------------------------------------------------------------------------
screen_set_cursor:
    LD   A, B
    CP   SCREEN_ROWS
    RET  NC
    LD   A, C
    CP   SCREEN_COLS
    RET  NC
    CALL _screen_emit_cup
    LD   A, B
    LD   (screen_emit_row), A
    LD   A, C
    LD   (screen_emit_col), A
    LD   A, 1
    LD   (screen_cursor_valid), A
    RET

; ---------------------------------------------------------------------------
; Internal Helpers
; ---------------------------------------------------------------------------

; Input: A = row (0..23). Output: HL = row * 80 = row*16 + row*64.
; Preserves: BC, DE, IX, IY
_screen_calc_row_offset:
    PUSH DE
    LD   L, A
    LD   H, 0
    ADD  HL, HL                 ; *2
    ADD  HL, HL                 ; *4
    ADD  HL, HL                 ; *8
    ADD  HL, HL                 ; *16
    LD   E, L
    LD   D, H                   ; DE = row * 16
    ADD  HL, HL                 ; *32
    ADD  HL, HL                 ; *64
    ADD  HL, DE                 ; HL = row * 80
    POP  DE
    RET

_screen_emit_csi:
    LD   A, KEY_ESC
    CALL bdos_rawio_putc
    LD   A, '['
    JP   bdos_rawio_putc

; Emit ESC[row+1;col+1H for B = row (0..23), C = col (0..79).
; Preserves: BC, DE, HL, IX, IY (clobbers AF)
_screen_emit_cup:
    LD   A, (abi_term_mode)
    OR   A
    JR   NZ, .cup_ansi
    LD   A, KEY_ESC
    CALL bdos_rawio_putc
    LD   A, '='
    CALL bdos_rawio_putc
    LD   A, B
    ADD  A, 0x20
    CALL bdos_rawio_putc
    LD   A, C
    ADD  A, 0x20
    JP   bdos_rawio_putc
.cup_ansi:
    CALL _screen_emit_csi
    LD   A, B
    INC  A
    CALL _screen_emit_dec_u8
    LD   A, ';'
    CALL bdos_rawio_putc
    LD   A, C
    INC  A
    CALL _screen_emit_dec_u8
    LD   A, 'H'
    JP   bdos_rawio_putc

; Emit ANSI SGR for A = new_eff_attr, H = old_eff_sgr (0xFF if unknown).
; Preserves: BC, DE, IX, IY (clobbers AF, HL)
_screen_emit_sgr:
    PUSH BC
    LD   L, A                   ; L = new_eff_attr
    CALL _screen_emit_csi
    LD   A, (abi_monochrome)
    OR   A
    JR   Z, .sgr_color

    ; Monochrome mode: never emit 30..37 / 90..97; preserve bold (1) & reverse (7)
    LD   A, L
    OR   A
    JR   NZ, .sgr_mono_nonzero
    LD   A, '0'
    CALL bdos_rawio_putc
    JR   .sgr_end
.sgr_mono_nonzero:
    CP   CPM_ATTR_REVERSE
    JR   NZ, .sgr_mono_full
    LD   A, H                   ; old_sgr == 0 -> compact ESC[7m
    OR   A
    JR   NZ, .sgr_mono_full
    LD   A, '7'
    CALL bdos_rawio_putc
    JR   .sgr_end
.sgr_mono_full:
    LD   A, '0'
    CALL bdos_rawio_putc
    JR   .sgr_mods

.sgr_color:
    ; If old != 0xFF and neither old nor new has bold/reverse, emit ESC[<fg>m directly
    LD   A, H
    CP   0xFF
    JR   Z, .sgr_reset_prefix
    OR   L
    AND  CPM_ATTR_BOLD | CPM_ATTR_REVERSE
    JR   Z, .sgr_emit_fg
.sgr_reset_prefix:
    LD   A, '0'
    CALL bdos_rawio_putc
    LD   A, ';'
    CALL bdos_rawio_putc
.sgr_emit_fg:
    LD   A, L
    AND  CPM_ATTR_COLOR_MASK
    PUSH HL
    LD   H, 0
    LD   L, A
    LD   BC, sgr_lut
    ADD  HL, BC
    LD   A, (HL)                ; 1-byte numeric SGR fg code (30..37 / 90..97)
    POP  HL
    CALL _screen_emit_dec_u8
.sgr_mods:
    BIT  5, L                   ; CPM_ATTR_BOLD
    JR   Z, .sgr_chk_rev
    LD   A, ';'
    CALL bdos_rawio_putc
    LD   A, '1'
    CALL bdos_rawio_putc
.sgr_chk_rev:
    BIT  6, L                   ; CPM_ATTR_REVERSE
    JR   Z, .sgr_end
    LD   A, ';'
    CALL bdos_rawio_putc
    LD   A, '7'
    CALL bdos_rawio_putc
.sgr_end:
    LD   A, 'm'
    CALL bdos_rawio_putc
    POP  BC
    RET

; Emit unsigned byte A (0..99) as 1 or 2 ASCII digits via bdos_rawio_putc.
; Preserves: BC, DE, HL, IX, IY (clobbers AF)
_screen_emit_dec_u8:
    PUSH BC
    LD   C, '0'
.dec_tens:
    CP   10
    JR   C, .dec_ones
    SUB  10
    INC  C
    JR   .dec_tens
.dec_ones:
    PUSH AF
    LD   A, C
    CP   '0'
    JR   Z, .dec_skip_tens
    CALL bdos_rawio_putc
.dec_skip_tens:
    POP  AF
    ADD  A, '0'
    CALL bdos_rawio_putc
    POP  BC
    RET
