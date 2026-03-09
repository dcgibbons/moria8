// test_memory128.s — C128 MMU smoke tests for C4.2

#import "../../common/zeropage.s"
#import "../memory128.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

test_start:
    sei
    cld
    ldx #$ff
    txs

    // Test 1: mmu_select_bank1/0 isolation at $4000
    // (Note: $4000 is RAM in both banks)
    
    jsr mmu_select_bank0
    lda #$a5
    sta $4000

    jsr mmu_select_bank1
    lda #$5a
    sta $4000
    lda $4000
    cmp #$5a
    bne test_fail

    jsr mmu_select_bank0
    lda $4000
    cmp #$a5
    bne test_fail

    // Test 2: mmu_select_bank1 preserves caller IRQ state
    
    // Case A: Call from CLI state
    cli
    jsr mmu_select_bank1
    // (IRQ should be disabled INSIDE, but restored OUTSIDE)
    php
    pla
    and #$04
    bne test_fail   // Fail if I=1 (disabled) outside

    jsr mmu_select_bank0 // Balanced restore
    php
    pla
    and #$04
    bne test_fail   // Still should be enabled

    // Case B: Call from SEI state
    sei
    jsr mmu_select_bank1
    php
    pla
    and #$04
    beq test_fail   // Fail if I=0 (enabled) outside

    jsr mmu_select_bank0
    php
    pla
    and #$04
    beq test_fail   // Still should be disabled

    // Test 3: mmu_copy_map_row isolation and boundary checks
    
    // Setup dummy data in Bank 1 at $4000
    jsr mmu_select_bank1
    ldx #0
!setup_src:
    txa
    sta $4000,x
    inx
    cpx #38
    bne !setup_src-
    jsr mmu_select_bank0

    // Setup sentinels at $03FF and $0400+38 ($0426)
    lda #$ff
    sta $03ff
    sta $0426
    
    // Clear destination $0400-$0425
    lda #0
    ldx #0
!clr_dest:
    sta $0400,x
    inx
    cpx #38
    bne !clr_dest-

    // Call the copy routine
    lda #<$4000
    sta zp_ptr0
    lda #>$4000
    sta zp_ptr0_hi
    jsr mmu_copy_map_row

    // Verify boundaries to prove no clobbering
    lda $03ff
    cmp #$ff
    bne test_fail
    lda $0426
    cmp #$ff
    bne test_fail

    // Verify copied content
    ldx #0
!chk_dest:
    txa
    cmp $0400,x
    bne test_fail
    inx
    cpx #38
    bne !chk_dest-

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
