// test_rng.s — Runtime tests for rng.s
//
// Tests:
// 1. RNG seed produces non-zero state
// 2. rng_next returns different values on consecutive calls
// 3. rng_range returns values in [0, N-1] for 100 iterations
// 4. LFSR doesn't degenerate to all-zeros
//
// Results at $0400: $01 = pass per test, $02 = overall

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"

#import "../zeropage.s"
#import "../memory.s"
#import "../rng.s"
#import "../math.s"

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
    ldx #0                  // 256 iterations (wraps)
!t4_loop:
    jsr rng_next
    inx
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

    brk
