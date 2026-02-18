// test_math.s — Runtime tests for math.s routines
//
// Runs in VICE headless. Results at $0400 (screen RAM):
//   $01 = pass, $00 = fail for each test
// Overall result at $02 (ZP): $01 = all pass, $00 = any fail

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"

#import "../zeropage.s"
#import "../memory.s"
#import "../rng.s"
#import "../math.s"

// Test result pointer
.var test_idx = 0

.macro WriteResult(pass) {
    .if (pass) {
        lda #$01
    } else {
        lda #$00
    }
    sta $0400 + test_idx
    .eval test_idx = test_idx + 1
}

test_start:
    // Initialize result area to $ff (untested)
    ldx #31
    lda #$ff
!clr:
    sta $0400,x
    dex
    bpl !clr-

    // Track overall pass/fail
    lda #$01
    sta $02

    // ==========================================
    // Test 1: 7 * 6 = 42
    // ==========================================
    lda #7
    ldx #6
    jsr math_multiply
    // Result: zp_math_a = lo, zp_math_b = hi
    lda zp_math_a
    cmp #42
    bne !t1_fail+
    lda zp_math_b
    cmp #0
    bne !t1_fail+
    lda #$01
    sta $0400
    jmp !t1_done+
!t1_fail:
    lda #$00
    sta $0400
    sta $02
!t1_done:

    // ==========================================
    // Test 2: 255 * 255 = 65025 ($FE01)
    // ==========================================
    lda #255
    ldx #255
    jsr math_multiply
    lda zp_math_a
    cmp #$01            // lo byte of 65025
    bne !t2_fail+
    lda zp_math_b
    cmp #$fe            // hi byte of 65025
    bne !t2_fail+
    lda #$01
    sta $0401
    jmp !t2_done+
!t2_fail:
    lda #$00
    sta $0401
    sta $02
!t2_done:

    // ==========================================
    // Test 3: 0 * 100 = 0
    // ==========================================
    lda #0
    ldx #100
    jsr math_multiply
    lda zp_math_a
    cmp #0
    bne !t3_fail+
    lda zp_math_b
    cmp #0
    bne !t3_fail+
    lda #$01
    sta $0402
    jmp !t3_done+
!t3_fail:
    lda #$00
    sta $0402
    sta $02
!t3_done:

    // ==========================================
    // Test 4: 1 * 1 = 1
    // ==========================================
    lda #1
    ldx #1
    jsr math_multiply
    lda zp_math_a
    cmp #1
    bne !t4_fail+
    lda zp_math_b
    cmp #0
    bne !t4_fail+
    lda #$01
    sta $0403
    jmp !t4_done+
!t4_fail:
    lda #$00
    sta $0403
    sta $02
!t4_done:

    // ==========================================
    // Test 5: 100 / 10 = 10 remainder 0
    // ==========================================
    lda #100
    sta zp_math_a
    lda #0
    sta zp_math_b
    ldx #10
    jsr math_div_16x8
    // Quotient in zp_math_a/b, remainder in A
    pha                     // Save remainder
    lda zp_math_a
    cmp #10
    bne !t5_fail+
    lda zp_math_b
    cmp #0
    bne !t5_fail+
    pla
    cmp #0                  // Remainder should be 0
    bne !t5_fail+
    lda #$01
    sta $0404
    jmp !t5_done+
!t5_fail:
    pla                     // Clean stack if we jumped here before pla
    lda #$00
    sta $0404
    sta $02
!t5_done:

    // ==========================================
    // Test 6: 255 / 7 = 36 remainder 3
    // ==========================================
    lda #255
    sta zp_math_a
    lda #0
    sta zp_math_b
    ldx #7
    jsr math_div_16x8
    pha
    lda zp_math_a
    cmp #36
    bne !t6_fail+
    pla
    cmp #3
    bne !t6_fail2+
    lda #$01
    sta $0405
    jmp !t6_done+
!t6_fail:
    pla
!t6_fail2:
    lda #$00
    sta $0405
    sta $02
!t6_done:

    // ==========================================
    // Test 7: 1000 / 3 = 333 remainder 1
    // 1000 = $03E8
    // ==========================================
    lda #$e8
    sta zp_math_a
    lda #$03
    sta zp_math_b
    ldx #3
    jsr math_div_16x8
    pha
    lda zp_math_a
    cmp #<333               // 333 = $014D, lo = $4D
    bne !t7_fail+
    lda zp_math_b
    cmp #>333               // hi = $01
    bne !t7_fail+
    pla
    cmp #1
    bne !t7_fail2+
    lda #$01
    sta $0406
    jmp !t7_done+
!t7_fail:
    pla
!t7_fail2:
    lda #$00
    sta $0406
    sta $02
!t7_done:

    // ==========================================
    // Test 8: min(5, 10) = 5
    // ==========================================
    lda #5
    ldx #10
    jsr math_min
    cmp #5
    bne !t8_fail+
    lda #$01
    sta $0407
    jmp !t8_done+
!t8_fail:
    lda #$00
    sta $0407
    sta $02
!t8_done:

    // ==========================================
    // Test 9: max(5, 10) = 10
    // ==========================================
    lda #5
    ldx #10
    jsr math_max
    cmp #10
    bne !t9_fail+
    lda #$01
    sta $0408
    jmp !t9_done+
!t9_fail:
    lda #$00
    sta $0408
    sta $02
!t9_done:

    // ==========================================
    // Test 10: clamp(3, 5, 10) = 5 (below min)
    // ==========================================
    lda #3
    ldx #5
    ldy #10
    jsr math_clamp
    cmp #5
    bne !t10_fail+
    lda #$01
    sta $0409
    jmp !t10_done+
!t10_fail:
    lda #$00
    sta $0409
    sta $02
!t10_done:

    // ==========================================
    // Test 11: clamp(15, 5, 10) = 10 (above max)
    // ==========================================
    lda #15
    ldx #5
    ldy #10
    jsr math_clamp
    cmp #10
    bne !t11_fail+
    lda #$01
    sta $040a
    jmp !t11_done+
!t11_fail:
    lda #$00
    sta $040a
    sta $02
!t11_done:

    // ==========================================
    // Test 12: clamp(7, 5, 10) = 7 (in range)
    // ==========================================
    lda #7
    ldx #5
    ldy #10
    jsr math_clamp
    cmp #7
    bne !t12_fail+
    lda #$01
    sta $040b
    jmp !t12_done+
!t12_fail:
    lda #$00
    sta $040b
    sta $02
!t12_done:

    // ==========================================
    // Tests 13-16: math_dice
    // Seed RNG for reproducibility
    // ==========================================
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    // ==========================================
    // Test 13: math_dice 1d6+0 — basic dice roll
    // 20 iterations, each result in [1, 6]
    // ==========================================
    ldx #20
!t13_loop:
    txa
    pha
    lda #1
    ldx #6
    ldy #0
    jsr math_dice
    lda zp_math_b
    bne !t13_fail+
    lda zp_math_a
    cmp #1
    bcc !t13_fail+
    cmp #7
    bcs !t13_fail+
    pla
    tax
    dex
    bne !t13_loop-
    lda #$01
    sta $040c
    jmp !t13_done+
!t13_fail:
    pla
    lda #$00
    sta $040c
    sta $02
!t13_done:

    // ==========================================
    // Test 14: math_dice 1d6+10 — positive bonus
    // 20 iterations, each result in [11, 16]
    // ==========================================
    ldx #20
!t14_loop:
    txa
    pha
    lda #1
    ldx #6
    ldy #10
    jsr math_dice
    lda zp_math_b
    bne !t14_fail+
    lda zp_math_a
    cmp #11
    bcc !t14_fail+
    cmp #17
    bcs !t14_fail+
    pla
    tax
    dex
    bne !t14_loop-
    lda #$01
    sta $040d
    jmp !t14_done+
!t14_fail:
    pla
    lda #$00
    sta $040d
    sta $02
!t14_done:

    // ==========================================
    // Test 15: math_dice 1d6-1 — negative bonus (Y=$FF)
    // 20 iterations, each result in [0, 5]
    // ==========================================
    ldx #20
!t15_loop:
    txa
    pha
    lda #1
    ldx #6
    ldy #$ff
    jsr math_dice
    lda zp_math_b
    bne !t15_fail+
    lda zp_math_a
    cmp #6
    bcs !t15_fail+
    pla
    tax
    dex
    bne !t15_loop-
    lda #$01
    sta $040e
    jmp !t15_done+
!t15_fail:
    pla
    lda #$00
    sta $040e
    sta $02
!t15_done:

    // ==========================================
    // Test 16: math_dice 10d8+0 — multi-dice accumulation
    // 20 iterations, each result in [10, 80]
    // ==========================================
    ldx #20
!t16_loop:
    txa
    pha
    lda #10
    ldx #8
    ldy #0
    jsr math_dice
    lda zp_math_b
    bne !t16_fail+
    lda zp_math_a
    cmp #10
    bcc !t16_fail+
    cmp #81
    bcs !t16_fail+
    pla
    tax
    dex
    bne !t16_loop-
    lda #$01
    sta $040f
    jmp !t16_done+
!t16_fail:
    pla
    lda #$00
    sta $040f
    sta $02
!t16_done:

    // Done — break into monitor
    brk
