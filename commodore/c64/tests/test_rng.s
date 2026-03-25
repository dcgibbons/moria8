// test_rng.s — Runtime tests for rng.s
//
// Tests:
// 1. RNG seed produces non-zero state
// 2. rng_next returns different values on consecutive calls
// 3. rng_range returns values in [0, N-1] for 100 iterations
// 4. LFSR doesn't degenerate to all-zeros
// 5. rng_range(1) always returns 0
// 6. rng_range(255) returns values in [0, 254]
// 7. rng_range_word(100) returns [0, 99]
// 8. rng_range_word(500) returns [0, 499]
// 9. rng_range_word(1) always returns 0
// 10. rng_next matches eight reference one-bit steps
//
// Results at $0400: $01 = pass per test, $02 = overall

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"

#import "../../common/zeropage.s"
#import "../memory.s"
#import "../../common/rng.s"
#import "../../common/math.s"

seed_test_state_a:
    lda #$12
    sta zp_rng_0
    sta ref_rng_0
    lda #$34
    sta zp_rng_1
    sta ref_rng_1
    lda #$56
    sta zp_rng_2
    sta ref_rng_2
    lda #$78
    sta zp_rng_3
    sta ref_rng_3
    rts

ref_rng_step_bit:
    lsr ref_rng_3
    ror ref_rng_2
    ror ref_rng_1
    ror ref_rng_0
    bcc !done+
    lda ref_rng_3
    eor #LFSR_POLY
    sta ref_rng_3
!done:
    lda ref_rng_0
    rts

ref_rng_0: .byte 0
ref_rng_1: .byte 0
ref_rng_2: .byte 0
ref_rng_3: .byte 0

test_start:
    // Init results
    ldx #15
    lda #$ff
!clr:
    sta $0400,x
    dex
    bpl !clr-
    lda #$01
    sta $02                 // Overall pass

    // ==========================================
    // Test 1: Seed produces non-zero state
    // ==========================================
    jsr rng_seed
    lda zp_rng_0
    ora zp_rng_1
    ora zp_rng_2
    ora zp_rng_3
    bne !t1_pass+
    lda #$00
    sta $0400
    sta $02
    jmp !t1_done+
!t1_pass:
    lda #$01
    sta $0400
!t1_done:

    // ==========================================
    // Test 2: Two consecutive calls return different values
    // ==========================================
    jsr rng_next
    sta zp_temp0            // Save first value
    jsr rng_next
    cmp zp_temp0            // Compare with second
    bne !t2_pass+
    // Same value — could happen with very low probability
    // but indicates a problem if LFSR is stuck
    lda #$00
    sta $0401
    sta $02
    jmp !t2_done+
!t2_pass:
    lda #$01
    sta $0401
!t2_done:

    // ==========================================
    // Test 3: rng_range(10) returns 0–9 for 100 iterations
    // Track min and max seen.
    // ==========================================
    lda #$ff
    sta zp_temp0            // min seen = 255
    lda #$00
    sta zp_temp1            // max seen = 0
    ldx #100
!t3_loop:
    txa
    pha                     // Save counter
    lda #10
    jsr rng_range
    // A = result, should be 0–9
    cmp #10
    bcs !t3_fail+           // >= 10 is fail
    // Update min
    cmp zp_temp0
    bcs !t3_no_min+
    sta zp_temp0
!t3_no_min:
    // Update max
    cmp zp_temp1
    bcc !t3_no_max+
    beq !t3_no_max+
    sta zp_temp1
!t3_no_max:
    pla
    tax
    dex
    bne !t3_loop-
    // All 100 values were in range
    lda #$01
    sta $0402
    jmp !t3_done+
!t3_fail:
    pla                     // Clean stack
    lda #$00
    sta $0402
    sta $02
!t3_done:

    // Store min/max for inspection
    lda zp_temp0
    sta $0410               // Min value seen
    lda zp_temp1
    sta $0411               // Max value seen

    // ==========================================
    // Test 4: After 256 iterations, state is not all-zero
    // ==========================================
    lda #0
    sta zp_temp4            // 256 iterations (wraps)
!t4_loop:
    jsr rng_next
    inc zp_temp4
    bne !t4_loop-
    // Check state
    lda zp_rng_0
    ora zp_rng_1
    ora zp_rng_2
    ora zp_rng_3
    bne !t4_pass+
    lda #$00
    sta $0403
    sta $02
    jmp !t4_done+
!t4_pass:
    lda #$01
    sta $0403
!t4_done:

    // ==========================================
    // Test 5: rng_range(1) always returns 0
    // N=1 means the only possible value is 0.
    // ==========================================
    ldx #100
!t5_loop:
    txa
    pha
    lda #1
    jsr rng_range
    cmp #0
    bne !t5_fail+
    pla
    tax
    dex
    bne !t5_loop-
    lda #$01
    sta $0404
    jmp !t5_done+
!t5_fail:
    pla
    lda #$00
    sta $0404
    sta $02
!t5_done:

    // ==========================================
    // Test 6: rng_range(255) returns values in [0, 254]
    // Result must never equal 255.
    // ==========================================
    ldx #100
!t6_loop:
    txa
    pha
    lda #255
    jsr rng_range
    cmp #255
    beq !t6_fail+
    pla
    tax
    dex
    bne !t6_loop-
    lda #$01
    sta $0405
    jmp !t6_done+
!t6_fail:
    pla
    lda #$00
    sta $0405
    sta $02
!t6_done:

    // ==========================================
    // Test 7: rng_range_word(100) returns [0, 99]
    // Result hi must be 0, result lo < 100.
    // ==========================================
    ldx #50
!t7_loop:
    txa
    pha
    lda #100
    sta zp_temp0
    lda #0
    sta zp_temp1                // N = 100
    jsr rng_range_word
    // zp_temp3 (hi) must be 0
    lda zp_temp3
    bne !t7_fail+
    // zp_temp2 (lo) must be < 100
    lda zp_temp2
    cmp #100
    bcs !t7_fail+
    pla
    tax
    dex
    bne !t7_loop-
    lda #$01
    sta $0406
    jmp !t7_done+
!t7_fail:
    pla
    lda #$00
    sta $0406
    sta $02
!t7_done:

    // ==========================================
    // Test 8: rng_range_word(500) returns [0, 499]
    // N=500 ($01F4), 16-bit compare: result < 500
    // ==========================================
    ldx #50
!t8_loop:
    txa
    pha
    lda #<500
    sta zp_temp0
    lda #>500
    sta zp_temp1                // N = 500
    jsr rng_range_word
    // 16-bit compare: zp_temp3:zp_temp2 < $01F4?
    lda zp_temp3
    cmp #>500
    bcc !t8_ok+                 // hi < 1 → accept
    bne !t8_fail+               // hi > 1 → fail
    lda zp_temp2
    cmp #<500                   // hi equal, compare lo
    bcs !t8_fail+               // lo >= $F4 → fail
!t8_ok:
    pla
    tax
    dex
    bne !t8_loop-
    lda #$01
    sta $0407
    jmp !t8_done+
!t8_fail:
    pla
    lda #$00
    sta $0407
    sta $02
!t8_done:

    // ==========================================
    // Test 9: rng_range_word(1) always returns 0
    // ==========================================
    ldx #50
!t9_loop:
    txa
    pha
    lda #1
    sta zp_temp0
    lda #0
    sta zp_temp1                // N = 1
    jsr rng_range_word
    lda zp_temp2
    ora zp_temp3
    bne !t9_fail+
    pla
    tax
    dex
    bne !t9_loop-
    lda #$01
    sta $0408
    jmp !t9_done+
!t9_fail:
    pla
    lda #$00
    sta $0408
    sta $02
!t9_done:

    // ==========================================
    // Test 10: rng_next must match eight reference one-bit steps
    // ==========================================
    jsr seed_test_state_a
    jsr rng_next
    sta zp_temp0
    ldx #8
!t10_ref_loop:
    jsr ref_rng_step_bit
    dex
    bne !t10_ref_loop-
    lda zp_rng_0
    cmp ref_rng_0
    bne !t10_fail+
    lda zp_rng_1
    cmp ref_rng_1
    bne !t10_fail+
    lda zp_rng_2
    cmp ref_rng_2
    bne !t10_fail+
    lda zp_rng_3
    cmp ref_rng_3
    bne !t10_fail+
    lda zp_temp0
    cmp ref_rng_0
    bne !t10_fail+
    lda #$01
    sta $0409
    jmp !t10_done+
!t10_fail:
    lda #$00
    sta $0409
    sta $02
!t10_done:

    brk
