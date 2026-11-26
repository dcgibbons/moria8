; rng.asm — 32-bit Xorshift32 PRNG and Z80 hardware/poll entropy mixer.
;
; State lives strictly in abi_rng_seed (4 bytes LE at Z80_STATE_BASE + 0x08)
; so test harnesses can inspect and deterministically seed PRNG runs.
; Included once by resident main.asm.

    IFNDEF CORE_Z80_RNG_ASM
    DEFINE CORE_Z80_RNG_ASM 1

; ============================================================
; rng_init_boot — Seed abi_rng_seed at startup from Z80 R, BDOS vector, & poll
;
; Input:  none (reads LD A, R, CPM_BDOS_VEC, and abi_entropy_poll)
; Output: non-zero 32-bit state stored in abi_rng_seed
; Clobbers: AF, HL (preserves BC, DE, IX, IY)
; ============================================================
    EXPORT rng_init_boot
rng_init_boot:
    LD   HL, (CPM_BDOS_VEC)
    LD   A, R
    XOR  L
    XOR  0x6D
    LD   (abi_rng_seed + 0), A
    LD   A, R
    RLCA
    XOR  H
    XOR  0x2B
    LD   (abi_rng_seed + 1), A
    LD   A, R
    RRCA
    XOR  L
    XOR  0x79
    LD   (abi_rng_seed + 2), A
    LD   A, R
    XOR  H
    XOR  0xF5
    LD   (abi_rng_seed + 3), A
    CALL rng_mix_entropy
    RET

; ============================================================
; rng_mix_entropy — Mix Z80 R refresh register & abi_entropy_poll into RNG state
;
; Guarantees non-zero state and runs one Xorshift32 diffusion step.
; Preserves: AF, BC, DE, HL, IX, IY
; ============================================================
    EXPORT rng_mix_entropy
rng_mix_entropy:
    PUSH AF
    PUSH HL
    LD   A, R
    LD   HL, abi_entropy_poll
    XOR  (HL)
    LD   HL, abi_rng_seed
    XOR  (HL)
    LD   (HL), A

    LD   A, R
    RLCA
    LD   HL, abi_entropy_poll + 1
    XOR  (HL)
    LD   HL, abi_rng_seed + 1
    XOR  (HL)
    LD   (HL), A

    LD   A, R
    RRCA
    LD   HL, abi_entropy_poll + 2
    XOR  (HL)
    LD   HL, abi_rng_seed + 2
    XOR  (HL)
    LD   (HL), A

    LD   A, R
    RLCA
    RLCA
    LD   HL, abi_entropy_poll + 3
    XOR  (HL)
    LD   HL, abi_rng_seed + 3
    XOR  (HL)
    LD   (HL), A

    CALL rng_next_u16
    POP  HL
    POP  AF
    RET

; ============================================================
; rng_next_u16 — Advance Xorshift32 (13, 17, 5) and return 16-bit value in HL
;
; Output: HL = pseudo-random 16-bit word
; Clobbers: AF (preserves BC, DE, IX, IY)
; ============================================================
    EXPORT rng_next_u16
rng_next_u16:
    PUSH BC
    PUSH DE
    PUSH IX
    LD   IX, abi_rng_seed

    ; Guard against absorbing all-zero state
    LD   A, (IX + 0)
    OR   (IX + 1)
    OR   (IX + 2)
    OR   (IX + 3)
    JR   NZ, .nonzero
    LD   (IX + 0), 0x19
    LD   (IX + 1), 0x3C
    LD   (IX + 2), 0x5A
    LD   (IX + 3), 0xA5
.nonzero:

    ; Step 1: x ^= x << 13  (3 right shifts of s2:s1:s0:0 -> bytes 3:2:1)
    LD   A, (IX + 2)
    LD   B, (IX + 1)
    LD   C, (IX + 0)
    LD   D, 0
    LD   E, 3
.sh13:
    SRL  A
    RR   B
    RR   C
    RR   D
    DEC  E
    JR   NZ, .sh13
    LD   A, D
    XOR  (IX + 1)
    LD   (IX + 1), A
    LD   A, C
    XOR  (IX + 2)
    LD   (IX + 2), A
    LD   A, B
    XOR  (IX + 3)
    LD   (IX + 3), A

    ; Step 2: x ^= x >> 17  (1 right shift of s3:s2 -> bytes 1:0)
    LD   A, (IX + 3)
    SRL  A
    LD   B, A
    LD   A, (IX + 2)
    RRA
    XOR  (IX + 0)
    LD   (IX + 0), A
    LD   A, B
    XOR  (IX + 1)
    LD   (IX + 1), A

    ; Step 3: x ^= x << 5   (3 right shifts of s3:s2:s1:s0:0 -> bytes 3:2:1:0)
    LD   A, (IX + 3)
    LD   B, (IX + 2)
    LD   C, (IX + 1)
    LD   D, (IX + 0)
    LD   E, 0
    LD   L, 3
.sh5:
    SRL  A
    RR   B
    RR   C
    RR   D
    RR   E
    DEC  L
    JR   NZ, .sh5
    LD   A, E
    XOR  (IX + 0)
    LD   (IX + 0), A
    LD   A, D
    XOR  (IX + 1)
    LD   (IX + 1), A
    LD   A, C
    XOR  (IX + 2)
    LD   (IX + 2), A
    LD   A, B
    XOR  (IX + 3)
    LD   (IX + 3), A

    LD   L, (IX + 2)
    LD   H, (IX + 3)
    POP  IX
    POP  DE
    POP  BC
    RET

; ============================================================
; rng_next_u8 — Advance PRNG and return 8-bit pseudo-random value in A
;
; Output: A = pseudo-random byte (0..255)
; Preserves: BC, DE, HL, IX, IY
; ============================================================
    EXPORT rng_next_u8
rng_next_u8:
    PUSH HL
    CALL rng_next_u16
    LD   A, H
    POP  HL
    RET

; ============================================================
; rng_range — Return uniform pseudo-random integer in [0, A-1]
;
; Input:  A = N (exclusive upper bound, 1..255; N=0 returns A=0)
; Output: A = uniform value in [0, N-1]
; Preserves: BC, DE, HL, IX, IY
; ============================================================
    EXPORT rng_range
rng_range:
    OR   A
    RET  Z
    CP   1
    JR   NZ, .not_one
    XOR  A
    RET
.not_one:
    PUSH BC
    LD   C, A           ; C = N
    DEC  A              ; A = N - 1
    LD   B, A
    SRL  A
    OR   B
    LD   B, A
    SRL  A
    SRL  A
    OR   B
    LD   B, A
    SRL  A
    SRL  A
    SRL  A
    SRL  A
    OR   B
    LD   B, A           ; B = smallest (2^k - 1) >= N - 1
.retry:
    CALL rng_next_u8
    AND  B
    CP   C
    JR   NC, .retry
    POP  BC
    RET

    ENDIF
