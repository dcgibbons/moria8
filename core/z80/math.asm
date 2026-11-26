; math.asm — Core unsigned 16-bit Z80 multiply and divide helpers.
;
; Included once by resident main.asm.

    IFNDEF CORE_Z80_MATH_ASM
    DEFINE CORE_Z80_MATH_ASM 1

; ============================================================
; mul_hl_a — Unsigned 16x8 -> 16-bit multiply (HL = HL * A)
;
; Input:  HL = 16-bit multiplicand (pass H = 0 for L * A)
;         A  = 8-bit multiplier
; Output: HL = low 16 bits of product
; Clobbers: AF, B, DE (preserves C, IX, IY)
; ============================================================
    EXPORT mul_hl_a
mul_hl_a:
    EX   DE, HL
    ; fall through to mul_de_a

; ============================================================
; mul_de_a — Unsigned 16x8 -> 16-bit multiply (HL = DE * A)
;
; Input:  DE = 16-bit multiplicand
;         A  = 8-bit multiplier
; Output: HL = low 16 bits of product
; Clobbers: AF, B (preserves C, DE, IX, IY)
; ============================================================
    EXPORT mul_de_a
mul_de_a:
    LD   HL, 0
    OR   A
    RET  Z
    LD   B, 8
.loop:
    ADD  HL, HL
    RLCA
    JR   NC, .no_add
    ADD  HL, DE
.no_add:
    DJNZ .loop
    RET

; ============================================================
; mul_de_bc — Unsigned 16x8 -> 16-bit multiply (HL = DE * C)
;
; Input:  DE = 16-bit multiplicand
;         C  = 8-bit multiplier
; Output: HL = low 16 bits of product
; Clobbers: AF, B (preserves C, DE, IX, IY)
; ============================================================
    EXPORT mul_de_bc
mul_de_bc:
    LD   A, C
    JR   mul_de_a

; ============================================================
; div_hl_c — Unsigned 16 / 8 -> 16-bit quotient, 8-bit remainder
;
; Input:  HL = 16-bit unsigned dividend
;         C  = 8-bit unsigned divisor
; Output: HL = 16-bit quotient, A = 8-bit remainder, CF = 0
;         On C == 0: HL = 0xFFFF, A = 0, CF = 1
; Clobbers: AF, B (preserves C, DE, IX, IY)
; ============================================================
    EXPORT div_hl_c
div_hl_c:
    LD   A, C
    OR   A
    JR   NZ, .nonzero
    LD   HL, 0xFFFF
    SCF
    RET
.nonzero:
    XOR  A              ; A = 0 remainder, CF = 0
    LD   B, 16
.loop:
    ADD  HL, HL         ; shift dividend MSB into CF
    RLA                 ; shift CF into remainder LSB (bit 8 -> CF if C >= 128)
    JR   C, .sub        ; rem >= 256 > C, guaranteed >= C
    CP   C
    JR   C, .next
.sub:
    SUB  C
    INC  L              ; set quotient bit 0
.next:
    DJNZ .loop
    OR   A              ; CF = 0
    RET

    ENDIF
