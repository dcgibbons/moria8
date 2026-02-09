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
    // Read CIA timers for 4 bytes of entropy
    lda CIA1_TIMER_A_LO
    sta zp_rng_0
    lda CIA1_TIMER_A_HI
    sta zp_rng_1
    lda CIA2_TIMER_A_LO
    sta zp_rng_2
    lda CIA2_TIMER_A_HI
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

// rng_next — Advance LFSR one step, return random byte in A
// Output: A = pseudo-random byte (zp_rng_0)
// Preserves: X, Y
// Cycles: ~35
rng_next:
    // Galois LFSR shift right, XOR polynomial on carry
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
    rts

// rng_range_word — Return random 16-bit number in range [0, N-1]
// Input:  zp_temp0 = N lo, zp_temp1 = N hi
// Output: zp_temp2 = result lo, zp_temp3 = result hi
// Preserves: nothing
// NOTE: Not implemented yet — needed for gold amounts etc. in Phase 6+.
