; input_csi.asm — CP/M 2.2 BDOS 6 (E=0xFF) input HAL with CSI/SS3 disambiguation.
;
; Requires main.asm to INCLUDE "memory.inc", "defs.inc", "state.inc",
; "bdos_io.asm", and "rng.asm" beforehand.
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax).
;
; Contracts enforced:
;   - Uses ONLY bdos_rawio_poll (BDOS 6 E=0xFF; never E=0xFE/0xFD)
;   - Consumes 1-byte lookahead abi_esc_pending before polling BDOS
;   - Blocking input_get_key increments 32-bit abi_entropy_poll on empty polls
;     and calls rng_mix_entropy when a byte arrives
;   - ESC (0x1B) polls up to ESC_CSI_POLL_ITERS (255) times to disambiguate
;     bare ESC, CSI (ESC [ ...), SS3 (ESC O ...), and rapid ESC + <key>

    EXPORT input_poll_key
    EXPORT input_get_key
    EXPORT input_wait_any_key

CSI_MAX_SEQ_BYTES EQU 32

; ---------------------------------------------------------------------------
; input_poll_key — Non-blocking normalized key poll.
; Output: A = normalized key code (or ASCII), or A = 0 if none (Z=1)
; Preserves: BC, DE, HL, IX, IY (clobbers AF)
; ---------------------------------------------------------------------------
input_poll_key:
    PUSH BC
    PUSH DE
    PUSH HL
    LD   A, (abi_esc_pending)
    OR   A
    JR   Z, .poll_raw
    LD   B, A
    XOR  A
    LD   (abi_esc_pending), A
    LD   A, B
    CP   KEY_ESC
    JR   NZ, .poll_done
    CALL _input_disambiguate_esc
    JR   .poll_done
.poll_raw:
    CALL bdos_rawio_poll
    OR   A
    JR   Z, .poll_done
    CALL _input_mix_entropy_keep_a
    CP   KEY_ESC
    JR   NZ, .poll_done
    CALL _input_disambiguate_esc ; returns A=key/KEY_ESC, or A=0 if unknown CSI ignored
.poll_done:
    POP  HL
    POP  DE
    POP  BC
    OR   A
    RET

; ---------------------------------------------------------------------------
; input_get_key — Blocking normalized key read with entropy polling.
; Output: A = normalized key code (nonzero)
; Preserves: BC, DE, HL, IX, IY (clobbers AF)
; ---------------------------------------------------------------------------
input_get_key:
    PUSH BC
    PUSH DE
    PUSH HL
.get_top:
    LD   A, (abi_esc_pending)
    OR   A
    JR   Z, .get_poll_loop
    LD   B, A
    XOR  A
    LD   (abi_esc_pending), A
    LD   A, B
    CP   KEY_ESC
    JR   NZ, .get_done
    CALL _input_disambiguate_esc
    OR   A
    JR   Z, .get_top
    JR   .get_done

.get_poll_loop:
    CALL bdos_rawio_poll
    OR   A
    JR   NZ, .get_got_byte
    ; Increment 32-bit little-endian abi_entropy_poll on each empty poll
    LD   HL, abi_entropy_poll
    INC  (HL)
    JR   NZ, .get_poll_loop
    INC  HL
    INC  (HL)
    JR   NZ, .get_poll_loop
    INC  HL
    INC  (HL)
    JR   NZ, .get_poll_loop
    INC  HL
    INC  (HL)
    JR   .get_poll_loop

.get_got_byte:
    CALL _input_mix_entropy_keep_a
    CP   KEY_ESC
    JR   NZ, .get_done
    CALL _input_disambiguate_esc
    OR   A
    JR   Z, .get_top            ; unrecognized CSI/SS3 discarded -> continue waiting
.get_done:
    POP  HL
    POP  DE
    POP  BC
    RET

; ---------------------------------------------------------------------------
; input_wait_any_key — Wait until any normalized keypress arrives.
; Output: A = normalized key code
; Preserves: BC, DE, HL, IX, IY (clobbers AF)
; ---------------------------------------------------------------------------
input_wait_any_key:
    JP   input_get_key

; ---------------------------------------------------------------------------
; Internal Helpers
; ---------------------------------------------------------------------------

; Call rng_mix_entropy while preserving A, BC, DE, HL, IX, IY.
_input_mix_entropy_keep_a:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    CALL rng_mix_entropy
    POP  HL
    POP  DE
    POP  BC
    POP  AF
    RET

; Bounded poll up to ESC_CSI_POLL_ITERS (255) times via bdos_rawio_poll.
; Output: A = byte (CF = 0) if received, or A = 0 (CF = 1) on timeout.
_input_poll_csi_byte:
    LD   B, ESC_CSI_POLL_ITERS
.csi_wait_b:
    PUSH BC
    CALL bdos_rawio_poll
    POP  BC
    OR   A
    RET  NZ                     ; CF = 0, A = byte
    DJNZ .csi_wait_b
    SCF                         ; CF = 1 timeout
    RET

; Disambiguate after initial KEY_ESC (0x1B) was received.
; Output: A = KEY_ESC / KEY_* normalized key, or A = 0 if unrecognized sequence ignored.
_input_disambiguate_esc:
    CALL _input_poll_csi_byte
    JR   NC, .esc_got_next
    LD   A, KEY_ESC             ; timeout -> bare ESC
    RET
.esc_got_next:
    CP   '['
    JR   Z, .parse_csi
    CP   'O'
    JR   Z, .parse_ss3
    LD   (abi_esc_pending), A   ; push back rapid byte following ESC
    LD   A, KEY_ESC
    RET

; VT100 SS3 application mode: ESC O <A/B/C/D/H/F>
.parse_ss3:
    CALL _input_poll_csi_byte
    JR   NC, .ss3_got
    XOR  A
    RET
.ss3_got:
    JR   .map_cursor_letter

; ANSI CSI: ESC [ <numeric params> <final byte 0x40..0x7E>
; D = param0 (0..254), E = flags (bit 0: has_digit, bit 1: seen_semi, bit 2: bad_param)
; C = remaining byte budget (CSI_MAX_SEQ_BYTES)
.parse_csi:
    LD   DE, 0
    LD   C, CSI_MAX_SEQ_BYTES
.csi_loop:
    PUSH BC
    PUSH DE
    CALL _input_poll_csi_byte
    POP  DE
    POP  BC
    JR   NC, .csi_byte_ok
    XOR  A                      ; timeout inside CSI -> discard cleanly
    RET
.csi_byte_ok:
    CP   KEY_ESC
    JR   Z, _input_disambiguate_esc ; aborted CSI followed by new ESC
    CP   0x40
    JR   C, .csi_param
    CP   0x7F
    JR   C, .csi_final          ; final byte in 0x40..0x7E
.csi_param:
    CP   ';'
    JR   NZ, .csi_chk_digit
    SET  1, E                   ; seen_semi = 1; ignore subsequent modifier params
    JR   .csi_next
.csi_chk_digit:
    CP   '0'
    JR   C, .csi_bad_param
    CP   '9' + 1
    JR   NC, .csi_bad_param
    BIT  1, E                   ; modifier param after ';' -> ignore
    JR   NZ, .csi_next
    BIT  2, E                   ; already bad/overflowed -> ignore
    JR   NZ, .csi_next
    SET  0, E                   ; has_digit = 1
    SUB  '0'
    LD   B, A                   ; B = digit 0..9
    LD   A, D
    CP   25                     ; > 249 would overflow 8-bit param0
    JR   NC, .csi_bad_param
    ADD  A, A                   ; *2
    ADD  A, A                   ; *4
    ADD  A, D                   ; *5
    ADD  A, A                   ; *10
    ADD  A, B
    JR   C, .csi_bad_param
    LD   D, A
    JR   .csi_next
.csi_bad_param:
    SET  2, E
.csi_next:
    DEC  C
    JR   NZ, .csi_loop
    XOR  A                      ; runaway sequence -> discard cleanly
    RET

.csi_final:
    BIT  2, E                   ; reject private ('?') or overflowed params
    JR   Z, .csi_final_ok
    XOR  A
    RET
.csi_final_ok:
    CP   '~'
    JR   Z, .csi_tilde
    ; Fall through to A/B/C/D/H/F mapping

.map_cursor_letter:
    CP   'A'
    JR   NZ, .chk_b
    LD   A, KEY_UP
    RET
.chk_b:
    CP   'B'
    JR   NZ, .chk_c
    LD   A, KEY_DOWN
    RET
.chk_c:
    CP   'C'
    JR   NZ, .chk_d
    LD   A, KEY_RIGHT
    RET
.chk_d:
    CP   'D'
    JR   NZ, .chk_h
    LD   A, KEY_LEFT
    RET
.chk_h:
    CP   'H'
    JR   NZ, .chk_f
    LD   A, KEY_HOME
    RET
.chk_f:
    CP   'F'
    JR   NZ, .unknown_seq
    LD   A, KEY_END
    RET

.csi_tilde:
    BIT  0, E                   ; require at least one numeric digit before '~'
    JR   Z, .unknown_seq
    LD   A, D
    CP   1
    JR   Z, .ret_home
    CP   7
    JR   Z, .ret_home
    CP   4
    JR   Z, .ret_end
    CP   8
    JR   Z, .ret_end
    CP   5
    JR   Z, .ret_pgup
    CP   6
    JR   Z, .ret_pgdn
    CP   3
    JR   Z, .ret_del
.unknown_seq:
    XOR  A                      ; unrecognized CSI/SS3 -> discard cleanly
    RET
.ret_home:
    LD   A, KEY_HOME
    RET
.ret_end:
    LD   A, KEY_END
    RET
.ret_pgup:
    LD   A, KEY_PGUP
    RET
.ret_pgdn:
    LD   A, KEY_PGDN
    RET
.ret_del:
    LD   A, KEY_DEL
    RET
