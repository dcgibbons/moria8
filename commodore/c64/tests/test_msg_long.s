// test_msg_long.s — Long message row-placement regression

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    lda tc_result
    sta $0400
    brk

.pc = $0830 "Main"

.encoding "screencode_mixed"

#import "../../common/zeropage.s"
#import "../memory.s"
#import "../screen.s"
#import "../../common/color.s"

test_key_calls: .byte 0
tc_result:      .byte $ff

input_get_key:
.label hal_input_get_key = input_get_key
.label hal_input_get_text_char = input_get_key
    inc test_key_calls
    lda #$20
    rts

#import "../../common/ui_messages.s"

test_start:
    lda #COL_LGREY
    sta zp_text_color
    jsr screen_clear
    jsr msg_init

    lda #<short_msg
    sta zp_ptr0
    lda #>short_msg
    sta zp_ptr0_hi
    jsr msg_print

    lda #<long_msg
    sta zp_ptr0
    lda #>long_msg
    sta zp_ptr0_hi
    jsr msg_print

    jsr msg_show_more

    lda test_key_calls
    bne !fail+
    lda zp_msg_flags
    cmp #MSG_PENDING | MSG_FULL
    bne !fail+
    lda $0400 + 34
    cmp #'-'
    bne !fail+
    lda $0400 + 40
    cmp #'T'
    bne !fail+
    lda $0400 + 40 + 38
    cmp #'.'
    bne !fail+

    lda #$01
    sta tc_result
    jmp test_finish
!fail:
    lda #$00
    sta tc_result
    jmp test_finish

short_msg:
    .text "The spell fails."
    .byte 0

long_msg:
    .text "The ancient multi-hued dragon shudders."
    .byte 0
