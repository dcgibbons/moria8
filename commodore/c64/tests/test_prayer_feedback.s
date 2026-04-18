// test_prayer_feedback.s — Focused runtime tests for prayer feedback helpers
//
// Covers the shared helper behavior behind priest book B without importing
// the full spell execution overlay into the large effects suite.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    ldx #7
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0830 "Main"

#import "../../common/zeropage.s"
#import "../memory.s"
#import "../../common/input_contract.s"

.const HSTR_PIQ_SPEED = 0
.const HSTR_PIQ_PROTECTED = 1
.const HSTR_PIQ_EYES_TINGLE = 2
.const HSTR_PIQ_FEEL_BETTER = 3
.const HSTR_PIQ_MUCH_BETTER = 4
.const HSTR_PIQ_NOTHING = 5
.const MX_SLEEP_CUR = 7

tc_results: .fill 8, $ff

test_msg_calls:    .byte 0
test_last_msg_lo:  .byte 0
test_last_msg_hi:  .byte 0
test_huff_calls:   .byte 0
test_last_huff:    .byte 0
test_mon_present:  .byte 0
test_mon_x:        .byte 0
test_mon_y:        .byte 0
test_mon_data:     .fill 12, 0

huff_print_msg:
    stx test_last_huff
    inc test_huff_calls
    rts

msg_print:
    inc test_msg_calls
    lda zp_ptr0
    sta test_last_msg_lo
    lda zp_ptr0_hi
    sta test_last_msg_hi
    rts

monster_find_at:
    cmp test_mon_x
    bne !mf_miss+
    cpy test_mon_y
    bne !mf_miss+
    lda test_mon_present
    beq !mf_miss+
    ldx #0
    sec
    rts
!mf_miss:
    clc
    rts

monster_get_ptr:
    lda #<test_mon_data
    sta zp_ptr0
    lda #>test_mon_data
    sta zp_ptr0_hi
    rts

monster_apply_sleep:
    pha
    jsr monster_get_ptr
    ldy #MX_SLEEP_CUR
    pla
    sta (zp_ptr0),y
    rts

eff_heal:
    rts

#import "../../common/player_magic_feedback.s"

test_start:
    lda #10
    sta zp_player_x
    sta zp_player_y

    // Test 1: Bless onset shows a message and sets the timer.
    lda #0
    sta test_msg_calls
    sta zp_eff_bless
    lda #24
    jsr pmx_add_bless_msg
    lda zp_eff_bless
    cmp #24
    bne !t1_fail+
    lda test_msg_calls
    cmp #1
    bne !t1_fail+
    lda test_last_msg_lo
    cmp #<pmx_msg_bless_on
    bne !t1_fail+
    lda test_last_msg_hi
    cmp #>pmx_msg_bless_on
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: Bless refresh stays silent.
!t2:
    lda #0
    sta test_msg_calls
    lda #5
    sta zp_eff_bless
    lda #24
    jsr pmx_add_bless_msg
    lda zp_eff_bless
    cmp #29
    bne !t2_fail+
    lda test_msg_calls
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: Sanctuary with no adjacent monsters shows feedback.
!t3:
    lda #0
    sta test_msg_calls
    sta test_huff_calls
    sta test_mon_present
    sta test_mon_data + MX_SLEEP_CUR
    jsr pmx_sleep_adjacent_msg
    lda test_huff_calls
    cmp #1
    bne !t3_fail+
    lda test_last_huff
    cmp #HSTR_PIQ_NOTHING
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // Test 4: Sanctuary sleeps an adjacent monster and reports it.
!t4:
    lda #0
    sta test_msg_calls
    lda #1
    sta test_mon_present
    lda #11
    sta test_mon_x
    lda #10
    sta test_mon_y
    lda #0
    sta test_mon_data + MX_SLEEP_CUR
    jsr pmx_sleep_adjacent_msg
    lda test_mon_data + MX_SLEEP_CUR
    cmp #20
    bne !t4_fail+
    lda test_msg_calls
    cmp #1
    bne !t4_fail+
    lda test_last_msg_lo
    cmp #<pmx_msg_sleep_success
    bne !t4_fail+
    lda test_last_msg_hi
    cmp #>pmx_msg_sleep_success
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // Test 5: Mass sleep with no visible targets shows feedback.
!t5:
    lda #0
    sta test_msg_calls
    sta test_huff_calls
    lda #0
    jsr pmx_report_sleep_result
    lda test_huff_calls
    cmp #1
    bne !t5_fail+
    lda test_last_huff
    cmp #HSTR_PIQ_NOTHING
    bne !t5_fail+
    lda #$01
    sta tc_results + 4
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 4

    // Test 6: Mass sleep with one visible target reports it.
!t6:
    lda #0
    sta test_msg_calls
    sta test_huff_calls
    lda #1
    jsr pmx_report_sleep_result
    lda test_msg_calls
    cmp #1
    bne !t6_fail+
    lda test_last_msg_lo
    cmp #<pmx_msg_sleep_success
    bne !t6_fail+
    lda test_last_msg_hi
    cmp #>pmx_msg_sleep_success
    bne !t6_fail+
    lda #$01
    sta tc_results + 5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 5

    // Test 7: Resist onset shows a message and sets the resist flags.
!t7:
    lda #0
    sta test_msg_calls
    sta zp_eff_resist
    jsr pmx_set_resist_heat_cold_msg
    lda zp_eff_resist
    cmp #$03
    bne !t7_fail+
    lda test_msg_calls
    cmp #1
    bne !t7_fail+
    lda test_last_msg_lo
    cmp #<pmx_msg_resist_on
    bne !t7_fail+
    lda test_last_msg_hi
    cmp #>pmx_msg_resist_on
    bne !t7_fail+
    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // Test 8: Resist refresh stays silent.
!t8:
    lda #0
    sta test_msg_calls
    lda #1
    sta zp_eff_resist
    jsr pmx_set_resist_heat_cold_msg
    lda zp_eff_resist
    cmp #$03
    bne !t8_fail+
    lda test_msg_calls
    bne !t8_fail+
    lda #$01
    sta tc_results + 7
    jmp test_finish
!t8_fail:
    lda #$00
    sta tc_results + 7
    jmp test_finish
