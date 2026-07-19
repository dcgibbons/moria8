// Exact C128 LOOK trampoline success/failure cleanup contract.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

.const C128_HELP_OVERLAY_ID = 5
.assert "C128 LOOK test uses the help overlay id", C128_HELP_OVERLAY_ID, 5

test_loader_fail:  .byte 0
test_loader_calls: .byte 0
test_look_calls:   .byte 0
test_enter_calls:  .byte 0
test_exit_calls:   .byte 0
test_guard_calls:  .byte 0
test_stack:        .byte 0

tramp_ui_enter:
    inc test_enter_calls
    sei
    lda #$3e
    sta $ff00
    lda #$34
    sta $01
    rts

c128_restore_runtime_guards:
    inc test_guard_calls
    rts

tramp_ui_exit:
    inc test_exit_calls
    lda #$36
    sta $01
    lda #$3e
    sta $ff00
    jsr c128_restore_runtime_guards
    cli
    rts

overlay_load:
    cmp #C128_HELP_OVERLAY_ID
    beq !id_ok+
    jmp test_fail
!id_ok:
    inc test_loader_calls
    lda #0
    sta $ff00
    lda #$34
    sta $01
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

#import "../look_trampoline.s"

test_reset:
    lda #0
    sta test_loader_calls
    sta test_look_calls
    sta test_enter_calls
    sta test_exit_calls
    sta test_guard_calls
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
    lda test_enter_calls
    cmp #1
    bne test_fail
    lda test_exit_calls
    cmp #1
    bne test_fail
    lda test_guard_calls
    cmp #1
    bne test_fail
    lda $ff00
    cmp #$3e
    bne test_fail
    lda $01
    and #$07
    cmp #$06
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
    lda #$2f
    sta $00
    lda #$36
    sta $01
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
