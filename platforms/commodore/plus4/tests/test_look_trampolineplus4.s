// Exact Plus/4 LOOK trampoline success/failure cleanup contract.

.pc = $1001 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $1030 "Test Code"

.const OVL_MODAL_MISC = 9
.assert "Plus/4 LOOK test uses the modal-misc overlay id", OVL_MODAL_MISC, 9

test_loader_fail:    .byte 0
test_loader_calls:   .byte 0
test_look_calls:     .byte 0
test_epilogue_calls: .byte 0
test_bank_ram:       .byte 0
test_stack:          .byte 0

overlay_load_no_kernal:
    cmp #OVL_MODAL_MISC
    beq !id_ok+
    jmp test_fail
!id_ok:
    inc test_loader_calls
    lda #0
    sta test_bank_ram
    cli
    lda test_loader_fail
    beq !ok+
    sec
    rts
!ok:
    clc
    rts

do_look:
    inc test_look_calls
    rts

plus4_platform_runtime_resync:
    inc test_epilogue_calls
    lda #1
    sta test_bank_ram
    cli
    rts

tramp_sr_epilogue:
    jmp plus4_platform_runtime_resync

#import "../look_trampoline.s"

test_reset:
    lda #0
    sta test_loader_calls
    sta test_look_calls
    sta test_epilogue_calls
    sta test_bank_ram
    rts

test_assert_cleanup:
    tsx
    inx
    inx
    cpx test_stack
    bne test_fail
    lda test_loader_calls
    cmp #1
    bne test_fail
    lda test_epilogue_calls
    cmp #1
    bne test_fail
    lda test_bank_ram
    cmp #1
    bne test_fail
    php
    pla
    and #$04
    bne test_fail
    rts

test_start:
    sei
    ldx #$ff
    txs
    jsr test_reset
    lda #0
    sta test_loader_fail
    tsx
    stx test_stack
    jsr tramp_do_look
    jsr test_assert_cleanup
    lda test_look_calls
    cmp #1
    bne test_fail

    jsr test_reset
    lda #1
    sta test_loader_fail
    tsx
    stx test_stack
    jsr tramp_do_look
    jsr test_assert_cleanup
    lda test_look_calls
    bne test_fail
    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
