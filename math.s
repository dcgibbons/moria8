// math.s — Arithmetic routines
//
// 8x8→16 unsigned multiply
// 16/8→16 unsigned divide (quotient + remainder)
// Dice roll: NdS+B (N dice of S sides plus bonus)

// ============================================================
// Subroutines
// ============================================================

// math_multiply — Unsigned 8x8 → 16-bit multiply
// Input:  A = multiplicand, X = multiplier
// Output: zp_math_a = result lo, zp_math_b = result hi
//         A = result lo on exit
// Preserves: Y
// Method: Shift-and-add (multiplier in X shifted right, result
//         accumulated in A:zp_math_a shifted right)
math_multiply:
    sta zp_math_tmp0        // Multiplicand
    lda #0
    sta zp_math_a           // Result = 0
    // Result hi is in A (accumulator), result lo in zp_math_a
    // Multiplier in X
    stx zp_math_tmp1
    ldx #8
!loop:
    lsr zp_math_tmp1        // Shift multiplier right, bit into carry
    bcc !skip+
    clc
    adc zp_math_tmp0        // Add multiplicand to hi byte of result
!skip:
    ror                     // Shift 16-bit result right (hi byte)
    ror zp_math_a           // (lo byte)
    dex
    bne !loop-
    sta zp_math_b           // Store hi byte
    lda zp_math_a           // Return lo byte in A
    rts

// math_div_16x8 — Unsigned 16/8 → 16-bit quotient, 8-bit remainder
// Input:  zp_math_a = dividend lo, zp_math_b = dividend hi
//         X = divisor
// Output: zp_math_a = quotient lo, zp_math_b = quotient hi
//         A = remainder
// Preserves: Y
math_div_16x8:
    stx zp_math_tmp0        // Divisor
    lda #0
    sta zp_math_tmp1        // Remainder
    ldx #16                 // 16 bits
!loop:
    asl zp_math_a           // Shift dividend left
    rol zp_math_b
    rol zp_math_tmp1        // Shift into remainder
    lda zp_math_tmp1
    sec
    sbc zp_math_tmp0        // Try subtract divisor
    bcc !no_sub+
    sta zp_math_tmp1        // Subtraction succeeded
    inc zp_math_a           // Set quotient bit
!no_sub:
    dex
    bne !loop-
    lda zp_math_tmp1        // Return remainder in A
    rts

// math_dice — Roll NdS+B (N dice of S sides plus bonus)
// Input:  A = N (number of dice, 1–255)
//         X = S (sides per die, 2–255)
//         Y = B (bonus, signed, -128 to +127)
// Output: zp_math_a = result lo
//         zp_math_b = result hi
//         (16-bit result to handle large rolls like 10d8+20)
// Preserves: nothing
math_dice:
    sta zp_math_tmp0        // N = dice count
    stx zp_math_tmp1        // S = sides
    // Store bonus for later
    sty zp_temp4
    // Initialize result to 0
    lda #0
    sta zp_math_a
    sta zp_math_b

!roll:
    lda zp_math_tmp1        // S = sides
    jsr rng_range           // A = random [0, S-1]
    clc
    adc #1                  // [1, S]
    // Add to 16-bit result
    clc
    adc zp_math_a
    sta zp_math_a
    lda zp_math_b
    adc #0
    sta zp_math_b
    dec zp_math_tmp0        // --N
    bne !roll-

    // Add signed bonus
    lda zp_temp4            // Bonus
    bpl !pos_bonus+
    // Negative bonus
    clc
    adc zp_math_a
    sta zp_math_a
    lda zp_math_b
    adc #$ff                // Sign-extend negative
    sta zp_math_b
    jmp !done+
!pos_bonus:
    clc
    adc zp_math_a
    sta zp_math_a
    lda zp_math_b
    adc #0
    sta zp_math_b
!done:
    rts

// math_min — Return min(A, X)
// Output: A = min value
math_min:
    stx zp_temp4
    cmp zp_temp4
    bcc !done+
    lda zp_temp4
!done:
    rts

// math_max — Return max(A, X)
// Output: A = max value
math_max:
    stx zp_temp4
    cmp zp_temp4
    bcs !done+
    lda zp_temp4
!done:
    rts

// math_clamp — Clamp A to range [X, Y]
// Input:  A = value, X = min, Y = max
// Output: A = clamped value
math_clamp:
    stx zp_temp3
    sty zp_temp4
    cmp zp_temp3
    bcs !check_max+
    lda zp_temp3            // A < min, return min
    rts
!check_max:
    cmp zp_temp4
    bcc !done+
    beq !done+
    lda zp_temp4            // A > max, return max
!done:
    rts
