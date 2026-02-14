// test_mapfill.s — Runtime test: verify map memory at $C000 can be filled and read back
//
// Tests that fill_map_rock-style absolute indexed writes to $C000-$CEFF
// work correctly in VICE. Results at $0400 (screen RAM):
//   $01 = pass, $00 = fail
// Test 0: Fill $C000-$CEFF with $0C, verify first byte
// Test 1: Verify byte at $C500
// Test 2: Verify byte at $CA00
// Test 3: Verify byte at $CEB0
// Test 4: Fill with $10, verify first byte changed
// Test 5: Fill with $D0 (quartz value), verify it reads back as $D0
// Test 6: Fill with $0C again, verify no $D0 remains at $C500

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"

.const MAP_BASE = $c000
.const MAP_END  = $ceff

test_start:
    // ======== Test 0: Fill with $0C, check $C000 ========
    lda #$0c
    ldx #0
!fill0:
    sta MAP_BASE,x
    sta MAP_BASE + $100,x
    sta MAP_BASE + $200,x
    sta MAP_BASE + $300,x
    sta MAP_BASE + $400,x
    sta MAP_BASE + $500,x
    sta MAP_BASE + $600,x
    sta MAP_BASE + $700,x
    sta MAP_BASE + $800,x
    sta MAP_BASE + $900,x
    sta MAP_BASE + $a00,x
    sta MAP_BASE + $b00,x
    sta MAP_BASE + $c00,x
    sta MAP_BASE + $d00,x
    sta MAP_BASE + $e00,x
    inx
    bne !fill0-

    // Verify $C000 = $0C
    lda $c000
    cmp #$0c
    bne !t0_fail+
    lda #$01
    sta $0400
    jmp !t1+
!t0_fail:
    lda #$00
    sta $0400

    // ======== Test 1: Check $C500 ========
!t1:
    lda $c500
    cmp #$0c
    bne !t1_fail+
    lda #$01
    sta $0401
    jmp !t2+
!t1_fail:
    lda #$00
    sta $0401

    // ======== Test 2: Check $CA00 ========
!t2:
    lda $ca00
    cmp #$0c
    bne !t2_fail+
    lda #$01
    sta $0402
    jmp !t3+
!t2_fail:
    lda #$00
    sta $0402

    // ======== Test 3: Check $CEB0 (last row start) ========
!t3:
    lda $ceb0
    cmp #$0c
    bne !t3_fail+
    lda #$01
    sta $0403
    jmp !t4+
!t3_fail:
    lda #$00
    sta $0403

    // ======== Test 4: Fill with $10, verify $C000 changed ========
!t4:
    lda #$10
    ldx #0
!fill1:
    sta MAP_BASE,x
    sta MAP_BASE + $100,x
    sta MAP_BASE + $200,x
    sta MAP_BASE + $300,x
    sta MAP_BASE + $400,x
    sta MAP_BASE + $500,x
    sta MAP_BASE + $600,x
    sta MAP_BASE + $700,x
    sta MAP_BASE + $800,x
    sta MAP_BASE + $900,x
    sta MAP_BASE + $a00,x
    sta MAP_BASE + $b00,x
    sta MAP_BASE + $c00,x
    sta MAP_BASE + $d00,x
    sta MAP_BASE + $e00,x
    inx
    bne !fill1-

    lda $c000
    cmp #$10
    bne !t4_fail+
    lda #$01
    sta $0404
    jmp !t5+
!t4_fail:
    lda #$00
    sta $0404

    // ======== Test 5: Fill with $D0 (quartz), verify readback ========
!t5:
    lda #$d0
    ldx #0
!fill2:
    sta MAP_BASE,x
    sta MAP_BASE + $100,x
    sta MAP_BASE + $200,x
    sta MAP_BASE + $300,x
    sta MAP_BASE + $400,x
    sta MAP_BASE + $500,x
    sta MAP_BASE + $600,x
    sta MAP_BASE + $700,x
    sta MAP_BASE + $800,x
    sta MAP_BASE + $900,x
    sta MAP_BASE + $a00,x
    sta MAP_BASE + $b00,x
    sta MAP_BASE + $c00,x
    sta MAP_BASE + $d00,x
    sta MAP_BASE + $e00,x
    inx
    bne !fill2-

    lda $c500
    cmp #$d0
    bne !t5_fail+
    lda #$01
    sta $0405
    jmp !t6+
!t5_fail:
    lda #$00
    sta $0405

    // ======== Test 6: Fill with $0C again, verify $D0 gone ========
!t6:
    lda #$0c
    ldx #0
!fill3:
    sta MAP_BASE,x
    sta MAP_BASE + $100,x
    sta MAP_BASE + $200,x
    sta MAP_BASE + $300,x
    sta MAP_BASE + $400,x
    sta MAP_BASE + $500,x
    sta MAP_BASE + $600,x
    sta MAP_BASE + $700,x
    sta MAP_BASE + $800,x
    sta MAP_BASE + $900,x
    sta MAP_BASE + $a00,x
    sta MAP_BASE + $b00,x
    sta MAP_BASE + $c00,x
    sta MAP_BASE + $d00,x
    sta MAP_BASE + $e00,x
    inx
    bne !fill3-

    lda $c500
    cmp #$0c
    bne !t6_fail+
    lda #$01
    sta $0406
    jmp !done+
!t6_fail:
    lda #$00
    sta $0406

!done:
    brk
