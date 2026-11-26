; numeric_format.asm — Unsigned ASCII decimal and hex formatting helpers.
;
; Included once by resident main.asm.

    IFNDEF CORE_Z80_NUMERIC_FORMAT_ASM
    DEFINE CORE_Z80_NUMERIC_FORMAT_ASM 1

; ============================================================
; fmt_u8_dec — Format unsigned 8-bit A as NUL-terminated ASCII decimal
;
; Input:  A  = unsigned value (0..255)
;         DE = destination buffer (>= 4 bytes)
; Output: NUL-terminated decimal string written at caller's DE
;         DE = points to trailing NUL byte (ready for chaining)
;         B  = digit count written (1..3, excluding NUL)
; Clobbers: AF, HL, C (preserves IX, IY)
; ============================================================
    EXPORT fmt_u8_dec
fmt_u8_dec:
    LD   L, A
    LD   H, 0
    ; fall through to fmt_u16_dec

; ============================================================
; fmt_u16_dec — Format unsigned 16-bit HL as NUL-terminated ASCII decimal
;
; Input:  HL = unsigned value (0..65535)
;         DE = destination buffer (>= 6 bytes)
; Output: NUL-terminated decimal string written at caller's DE
;         DE = points to trailing NUL byte (ready for chaining)
;         B  = digit count written (1..5, excluding NUL)
; Clobbers: AF, HL, C (preserves IX, IY)
; ============================================================
    EXPORT fmt_u16_dec
fmt_u16_dec:
    PUSH IX
    LD   IX, .pow10_tbl
    LD   B, 0           ; B = digits emitted so far
    LD   C, 4           ; 4 decade powers: 10000, 1000, 100, 10
.pow_loop:
    PUSH BC             ; save B=digit_count, C=remaining_decades
    LD   C, (IX + 0)
    LD   B, (IX + 1)
    INC  IX
    INC  IX
    LD   A, '0' - 1
.sub_loop:
    INC  A
    OR   A              ; clear carry
    SBC  HL, BC
    JR   NC, .sub_loop
    ADD  HL, BC         ; restore overshoot
    POP  BC             ; restore B=digit_count, C=remaining_decades
    CP   '0'
    JR   NZ, .emit
    INC  B
    DEC  B              ; suppress leading zeroes while B == 0
    JR   Z, .next_pow
.emit:
    LD   (DE), A
    INC  DE
    INC  B
.next_pow:
    DEC  C
    JR   NZ, .pow_loop
    ; Final ones digit (0..9 remaining in L)
    LD   A, L
    ADD  A, '0'
    LD   (DE), A
    INC  DE
    INC  B
    XOR  A
    LD   (DE), A        ; NUL terminator (DE stays pointing at NUL)
    POP  IX
    RET

.pow10_tbl:
    DW 10000, 1000, 100, 10

; ============================================================
; fmt_u16_hex — Format 16-bit HL as 4 uppercase hex digits + NUL
;
; Input:  HL = 16-bit value, DE = destination buffer (>= 5 bytes)
; Output: DE = points to trailing NUL byte
; Clobbers: AF (preserves BC, HL, IX, IY)
; ============================================================
    EXPORT fmt_u16_hex
fmt_u16_hex:
    LD   A, H
    CALL fmt_u8_hex
    LD   A, L
    ; fall through to fmt_u8_hex

; ============================================================
; fmt_u8_hex — Format 8-bit A as 2 uppercase hex digits + NUL
;
; Input:  A  = 8-bit value, DE = destination buffer (>= 3 bytes)
; Output: DE = points to trailing NUL byte
; Clobbers: AF (preserves BC, HL, IX, IY)
; ============================================================
    EXPORT fmt_u8_hex
fmt_u8_hex:
    PUSH AF
    RRCA
    RRCA
    RRCA
    RRCA
    CALL .nibble
    POP  AF
    CALL .nibble
    XOR  A
    LD   (DE), A
    RET
.nibble:
    AND  0x0F
    ADD  A, '0'
    CP   '9' + 1
    JR   C, .store
    ADD  A, 'A' - ('9' + 1)
.store:
    LD   (DE), A
    INC  DE
    RET

    ENDIF
