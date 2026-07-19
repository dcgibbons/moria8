// test_run_visibility_bank.s — production C64 runner visibility bank trampoline

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $0810 "Test Code"

.const BANK_NO_KERNAL = $35

test_called: .byte 0
test_bank_ok: .byte 0
test_saved_p: .byte 0

#import "../run_visibility_trampoline.s"

test_bootstrap:
    jmp test_start

test_start:
    lda #$36
    sta $01
    cli
    jsr run_monster_update_visibility_one
    php
    pla
    sta test_saved_p
    sei

    lda test_called
    cmp #1
    bne test_fail
    lda test_bank_ok
    cmp #1
    bne test_fail
    lda $01
    cmp #$36
    bne test_fail
    lda test_saved_p
    and #$04
    bne test_fail

test_pass:
    lda #1
    bne test_done

test_fail:
    lda #0

test_done:
    sta $0400
    brk

.pc = $F000 "Banked visibility implementation"
monster_update_visibility_one:
    inc test_called
    lda $01
    cmp #BANK_NO_KERNAL
    bne !done+
    inc test_bank_ok
!done:
    rts

.assert "Visibility bank test trampoline stays below BASIC ROM", test_done < $a000, true
