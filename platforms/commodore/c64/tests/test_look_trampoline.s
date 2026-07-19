// Exact C64 LOOK trampoline success/failure cleanup contract.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0830 "Test Code"

.const OVL_MODAL_MISC = 9
.const BANK_NO_BASIC = $36
.const BANK_NO_ROMS = $34
.assert "C64 LOOK test uses the modal-misc overlay id", OVL_MODAL_MISC, 9

test_loader_fail:    .byte 0
test_loader_calls:   .byte 0
test_look_calls:     .byte 0
test_epilogue_calls: .byte 0
test_stack:          .byte 0

overlay_load_no_kernal:
    cmp #OVL_MODAL_MISC
    beq !id_ok+
    jmp test_fail
!id_ok:
    inc test_loader_calls
    lda #BANK_NO_ROMS
    sta $01
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

platform_runtime_resync_c64:
    lda #BANK_NO_BASIC
    sta $01
    cli
    rts

tramp_sr_epilogue:
    php
    inc test_epilogue_calls
    jsr platform_runtime_resync_c64
    plp
    rts

#import "../look_trampoline.s"

test_reset:
    lda #0
    sta test_loader_calls
    sta test_look_calls
    sta test_epilogue_calls
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
    lda $01
    cmp #BANK_NO_BASIC
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
    cli
    tsx
    stx test_stack
    jsr tramp_do_look
    jsr test_assert_cleanup
    lda test_look_calls
    cmp #1
    bne test_fail
    lda #1
    sta $0400

    jsr test_reset
    lda #1
    sta test_loader_fail
    cli
    tsx
    stx test_stack
    jsr tramp_do_look
    jsr test_assert_cleanup
    lda test_look_calls
    bne test_fail
    lda #1
    sta $0401
    jmp test_finish

test_fail:
    lda #0
    sta $0400
    sta $0401

test_finish:
    brk
