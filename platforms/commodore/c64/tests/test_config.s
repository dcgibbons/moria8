// test_config.s — C64 machine-detection contract smoke test

#import "../../../../core/zeropage.s"
#import "../config.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(bootstrap)

.pc = $080E "Test Code"

bootstrap:
    jmp test_start

test_finish:
    lda test_result
    sta $0400
    brk

.pc = $3000 "Main"

test_result: .byte 0

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #$ff
    sta zp_machine_type
    sta zp_column_mode

    jsr detect_machine

    lda zp_machine_type
    cmp #MACHINE_C64
    bne test_fail

    lda zp_column_mode
    cmp #COLUMNS_40
    bne test_fail

    lda #$01
    sta test_result
    jmp test_finish

test_fail:
    lda #$00
    sta test_result
    jmp test_finish
