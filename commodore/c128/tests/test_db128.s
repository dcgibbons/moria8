// test_db128.s — C128 banked database helper smoke tests for Phase 10.2.1

#import "../../common/zeropage.s"
#import "../memory128.s"
#import "../config128.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

.const DB_TEST_ADDR0 = $5000
.const DB_TEST_ADDR1 = $5001
.const DB_TEST_ADDR2 = $5002

c128_restore_runtime_state:
    rts

test_start:
    sei
    cld
    ldx #$ff
    txs

    // Seed different values in Bank 0 / Bank 1 at DB_TEST_ADDR0
    jsr mmu_select_bank0
    lda #$a1
    sta DB_TEST_ADDR0
    jsr mmu_select_bank1
    lda #$5c
    sta DB_TEST_ADDR0
    jsr mmu_select_bank0

    // Read via ptr0 helper; should return Bank 1 value and restore Bank 0.
    lda #<DB_TEST_ADDR0
    sta zp_ptr0
    lda #>DB_TEST_ADDR0
    sta zp_ptr0_hi
    ldy #0
    jsr mmu_safe_db_read_ptr0
    cmp #$5c
    beq !ok0+
    jmp test_fail
!ok0:
    lda DB_TEST_ADDR0
    cmp #$a1
    beq !ok1+
    jmp test_fail
!ok1:

    // Repeat on ptr1 helper at a second address.
    jsr mmu_select_bank0
    lda #$12
    sta DB_TEST_ADDR1
    jsr mmu_select_bank1
    lda #$e7
    sta DB_TEST_ADDR1
    jsr mmu_select_bank0

    lda #<DB_TEST_ADDR1
    sta zp_ptr1
    lda #>DB_TEST_ADDR1
    sta zp_ptr1_hi
    ldy #0
    jsr mmu_safe_db_read_ptr1
    cmp #$e7
    beq !ok2+
    jmp test_fail
!ok2:
    lda DB_TEST_ADDR1
    cmp #$12
    beq !ok3+
    jmp test_fail
!ok3:

    // Write via ptr0 helper must affect Bank 1 only.
    jsr mmu_select_bank0
    lda #$11
    sta DB_TEST_ADDR2
    jsr mmu_select_bank1
    lda #$22
    sta DB_TEST_ADDR2
    jsr mmu_select_bank0

    lda #<DB_TEST_ADDR2
    sta zp_ptr0
    lda #>DB_TEST_ADDR2
    sta zp_ptr0_hi
    ldy #0
    lda #$77
    jsr mmu_safe_db_write_ptr0

    jsr mmu_select_bank1
    lda DB_TEST_ADDR2
    cmp #$77
    beq !ok4+
    jmp test_fail
!ok4:
    jsr mmu_select_bank0
    lda DB_TEST_ADDR2
    cmp #$11
    beq !ok5+
    jmp test_fail
!ok5:

    // IRQ state should be preserved across helper calls.
    cli
    lda #<DB_TEST_ADDR0
    sta zp_ptr0
    lda #>DB_TEST_ADDR0
    sta zp_ptr0_hi
    ldy #0
    jsr mmu_safe_db_read_ptr0
    php
    pla
    and #$04
    beq !ok6+                 // I flag should remain clear
    jmp test_fail
!ok6:

    sei
    jsr mmu_safe_db_read_ptr0
    php
    pla
    and #$04
    bne !ok7+                 // I flag should remain set
    jmp test_fail
!ok7:

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
