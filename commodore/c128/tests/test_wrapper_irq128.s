#importonce
// test_wrapper_irq128.s — verify representative C128 KERNAL wrappers
// preserve the caller IRQ state and restore MMU/runtime invariants.

#import "../../common/zeropage.s"
#import "test_helpers128.s"
#import "../memory128.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

c128_restore_runtime_state:
    rts

dbg_stage:   .byte 0
dbg_ibit:    .byte 0
dbg_depth:   .byte 0
dbg_ff00:    .byte 0
dbg_d506:    .byte 0
dbg_port00:  .byte 0
dbg_port01:  .byte 0

w_readst_test:
    pha
    txa
    pha
    tya
    pha
    :EnterKernal()
    pla
    tay
    pla
    tax
    pla
    jsr $ffb7
    php
    pha
    :ExitKernal()
    pla
    plp
    rts

w_setlfs_test:
    pha
    txa
    pha
    tya
    pha
    :EnterKernal()
    pla
    tay
    pla
    tax
    pla
    jsr $ffba
    php
    pha
    :ExitKernal()
    pla
    plp
    rts

test_start:
    sei
    cld
    ldx #$ff
    txs

    // Capture the live KERNAL IRQ tail vector before entering all-RAM mode.
    lda $0314
    sta kernal_irq_vec_lo
    lda $0315
    sta kernal_irq_vec_hi

    lda #$0d
    sta $d506
    lda #MMU_ALL_RAM
    sta $ff00
    lda #CPU_PORT_DDR_DEFAULT
    sta $00
    lda #BANK_NO_BASIC
    sta $01

    jsr test_readst_cli
    jsr test_readst_sei
    jsr test_setlfs_cli
    jsr test_setlfs_sei

    jmp test_pass

test_readst_cli:
    lda #$11
    sta dbg_stage
    lda #0
    sta KERNAL_NESTING_DEPTH
    cli
    jsr w_readst_test
    php
    sei
    pla
    and #$04
    sta dbg_ibit
    beq !ok+
    jmp test_fail
!ok:
    jsr assert_runtime_restored
    rts

test_readst_sei:
    lda #$12
    sta dbg_stage
    lda #0
    sta KERNAL_NESTING_DEPTH
    sei
    jsr w_readst_test
    php
    sei
    pla
    and #$04
    sta dbg_ibit
    bne !ok+
    jmp test_fail
!ok:
    jsr assert_runtime_restored
    rts

test_setlfs_cli:
    lda #$21
    sta dbg_stage
    lda #0
    sta KERNAL_NESTING_DEPTH
    lda #8
    ldx #1
    ldy #0
    cli
    jsr w_setlfs_test
    php
    sei
    pla
    and #$04
    sta dbg_ibit
    beq !ok+
    jmp test_fail
!ok:
    jsr assert_runtime_restored
    rts

test_setlfs_sei:
    lda #$22
    sta dbg_stage
    lda #0
    sta KERNAL_NESTING_DEPTH
    lda #8
    ldx #1
    ldy #0
    sei
    jsr w_setlfs_test
    php
    sei
    pla
    and #$04
    sta dbg_ibit
    bne !ok+
    jmp test_fail
!ok:
    jsr assert_runtime_restored
    rts

assert_runtime_restored:
    lda KERNAL_NESTING_DEPTH
    sta dbg_depth
    beq !depth_ok+
    jmp test_fail
!depth_ok:
    lda $ff00
    sta dbg_ff00
    cmp #MMU_ALL_RAM
    beq !ff00_ok+
    jmp test_fail
!ff00_ok:
    lda $d506
    sta dbg_d506
    cmp #$0d
    beq !d506_ok+
    jmp test_fail
!d506_ok:
    lda $00
    sta dbg_port00
    cmp #CPU_PORT_DDR_DEFAULT
    beq !port00_ok+
    jmp test_fail
!port00_ok:
    lda $01
    sta dbg_port01
    cmp #BANK_NO_BASIC
    beq !port01_ok+
    jmp test_fail
!port01_ok:
    rts

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
