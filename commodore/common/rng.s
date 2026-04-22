#importonce
// rng.s — 32-bit Galois LFSR random number generator
//
// Polynomial: $ED (taps at bits 7,6,5,3,2,0 — period 2^32-1)
// Seeded from CIA #1 Timer A ($DC04/$DC05) which free-runs.
//
// Galois LFSR is used instead of Fibonacci because it only
// needs a single XOR per feedback bit (faster on 6502).
//
// State stored in zp_rng_0..zp_rng_3 (4 bytes, ZP for speed).

// CIA Timer A registers (free-running, read for entropy)
.const CIA1_TIMER_A_LO = $dc04
.const CIA1_TIMER_A_HI = $dc05
.const CIA2_TIMER_A_LO = $dd04
.const CIA2_TIMER_A_HI = $dd05

// Galois LFSR feedback polynomial
.const LFSR_POLY = $ed

// ============================================================
// Subroutines
// ============================================================

// rng_seed — Initialize RNG state from CIA timers
// Should be called once at startup, ideally after user input
// (for additional entropy from timing).
// Preserves: nothing
rng_seed:
    // Read CIA timers and mix with input jitter and prior state
    lda CIA1_TIMER_A_LO
    eor zp_entropy
    eor zp_rng_0
    sta zp_rng_0
    lda CIA1_TIMER_A_HI
    eor zp_entropy
    eor zp_rng_1
    sta zp_rng_1
    lda CIA2_TIMER_A_LO
    eor zp_entropy
    eor zp_rng_2
    sta zp_rng_2
    lda CIA2_TIMER_A_HI
    eor zp_entropy
    eor zp_rng_3
    sta zp_rng_3

    // Ensure state is not all-zeros (LFSR has absorbing zero state)
    lda zp_rng_0
    ora zp_rng_1
    ora zp_rng_2
    ora zp_rng_3
    bne !ok+
    // All zeros — set to a non-zero seed
    lda #$a5
    sta zp_rng_0
!ok:
    rts

// rng_next — Advance LFSR eight steps, return random byte in A
// Output: A = pseudo-random byte (zp_rng_0 after one full byte step)
// Preserves: Y
// Clobbers: X
// Cycles: ~145
rng_next:
    ldx #8
    // Galois LFSR shift right, XOR polynomial on carry.
    // Public byte consumers use eight bit-steps per returned byte to
    // avoid adjacent-call byte-shift correlation.
!step_loop:
    lsr zp_rng_3
    ror zp_rng_2
    ror zp_rng_1
    ror zp_rng_0
    bcc !no_xor+
    // Feedback: XOR high byte with polynomial
    lda zp_rng_3
    eor #LFSR_POLY
    sta zp_rng_3
!no_xor:
    dex
    bne !step_loop-
    lda zp_rng_0
    rts

// rng_byte — Alias for rng_next (returns random byte in A)
.label rng_byte = rng_next

// rng_range — Return random number in range [0, N-1]
// Input:  A = N (upper bound, exclusive). Must be 1–255.
// Output: A = random number in [0, N-1]
// Method: Rejection sampling to avoid modulo bias.
//         Calculate smallest power-of-2 mask >= N, generate
//         masked random bytes, reject if >= N.
// Preserves: Y
// Clobbers: X
rng_range:
    sta zp_temp4            // Save N
    // Calculate mask: smallest (2^k - 1) >= N-1
    tax
    beq !rng_done+          // N=0 → return 0 (A already 0)
    dex                     // N-1
    txa
    // Spread bits right to fill mask
    ora_shift_right:
    sta zp_temp3            // temp = working mask
    lsr
    ora zp_temp3
    sta zp_temp3
    lsr
    lsr
    ora zp_temp3
    sta zp_temp3
    lsr
    lsr
    lsr
    lsr
    ora zp_temp3
    sta zp_temp3            // zp_temp3 = mask with all bits set from MSB of (N-1) down

!retry:
    jsr rng_next
    and zp_temp3            // Mask to range
    cmp zp_temp4            // >= N?
    bcs !retry-             // Yes, reject and retry
!rng_done:
    ora #0                  // Return N/Z for A while preserving carry
    rts

// rng_range_word — Return random 16-bit number in range [0, N-1]
// Input:  zp_temp0 = N lo, zp_temp1 = N hi
// Output: zp_temp2 = result lo, zp_temp3 = result hi
// Preserves: nothing
// Method: 16-bit rejection sampling (same principle as rng_range)
rng_range_word:
    // Compute mask = spread bits of (N-1) to fill all lower bits
    lda zp_temp0
    sec
    sbc #1
    sta zp_temp2
    lda zp_temp1
    sbc #0
    sta zp_temp3           // mask = N-1

    // Spread bits right: shifts of 1, 2, 4, 8
    ldx #1
    jsr rrw_spread
    ldx #2
    jsr rrw_spread
    ldx #4
    jsr rrw_spread
    ldx #8
    jsr rrw_spread

!rrw_retry:
    // Generate 16-bit masked random
    jsr rng_next
    and zp_temp2
    sta rrw_tmp
    jsr rng_next
    and zp_temp3
    tay

    // 16-bit compare: result >= N? If so, reject
    cpy zp_temp1
    bcc !rrw_ok+            // hi < N_hi → accept
    bne !rrw_retry-         // hi > N_hi → reject
    lda rrw_tmp
    cmp zp_temp0            // hi equal, compare lo
    bcs !rrw_retry-         // lo >= N_lo → reject
!rrw_ok:
    lda rrw_tmp
    sta zp_temp2
    tya
    sta zp_temp3
    rts

// rrw_spread — OR mask with itself shifted right by X positions
// Input: X = shift count, rrw_mask_lo/hi
// Output: rrw_mask_lo/hi updated
rrw_spread:
    lda zp_temp2
    sta rrw_tmp
    lda zp_temp3
!rrw_sloop:
    lsr                     // Shift hi
    ror rrw_tmp             // Shift lo (carry from hi)
    dex
    bne !rrw_sloop-
    // OR shifted copy into mask
    ora zp_temp3
    sta zp_temp3
    lda rrw_tmp
    ora zp_temp2
    sta zp_temp2
    rts

rrw_tmp:     .byte 0
