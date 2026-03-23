// test_disk_swap.s — Isolated unit tests for disk_swap.s
//
// Tests:
//  1. disk_prompt no-op in mode 0
//  2. disk_prompt no-op in mode 2
//  3. disk_prompt in mode 1 shows prompt, waits, and inits drive
//  4. disk_init_drive uses current save_device
//  5. probe_device present path
//  6. probe_device OPEN-fail path
//  7. probe_device READST-error path
//  8. disk_enter_device accepts one-digit device
//  9. disk_enter_device accepts two-digit device
// 10. disk_enter_device invalid entry re-prompts
// 11. disk_enter_device absent device returns carry set and shows error

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"

.encoding "screencode_mixed"

#import "../../common/zeropage.s"

.const SCREEN_COLS = 40
.const COL_WHITE = $01
.const COL_CYAN  = $03
.const COL_LRED  = $0a
.const CMD_CHANNEL = 15

.const KERNAL_SETNAM = kernal_setnam
.const KERNAL_SETLFS = kernal_setlfs
.const KERNAL_OPEN   = kernal_open
.const KERNAL_CLOSE  = kernal_close
.const KERNAL_CLRCHN = kernal_clrchn
.const KERNAL_READST = kernal_readst

screen_put_string_calls: .byte 0
screen_put_char_calls:   .byte 0
screen_clear_row_calls:  .byte 0
screen_put_decimal_calls:.byte 0
input_get_key_calls:     .byte 0
save_prompt_count:       .byte 0
press_prompt_count:      .byte 0
nodev_prompt_count:      .byte 0
drive_ind_count:         .byte 0
last_decimal_value:      .byte 0
last_char_value:         .byte 0
kernal_setnam_calls:     .byte 0
kernal_setnam_len:       .byte 0
kernal_setlfs_calls:     .byte 0
kernal_setlfs_la:        .byte 0
kernal_setlfs_dev:       .byte 0
kernal_setlfs_sec:       .byte 0
kernal_open_calls:       .byte 0
kernal_open_fail:        .byte 0
kernal_close_calls:      .byte 0
kernal_clrchn_calls:     .byte 0
kernal_readst_calls:     .byte 0
kernal_readst_value:     .byte 0
input_idx:               .byte 0
input_len:               .byte 0
input_stream:            .fill 8, 0

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

#import "../../common/runtime_ui_strings.s"
#import "../../common/disk_swap.s"

tc_results: .fill 11, $ff

reset_harness_state:
    lda #0
    ldx #state_end - state_start - 1
!clr:
    sta state_start,x
    dex
    bpl !clr-
    rts
.label state_start = screen_put_string_calls
.label state_end = input_stream + 8

input_get_key:
    inc input_get_key_calls
    ldx input_idx
    cpx input_len
    bcc !have_key+
    lda #0
    rts
!have_key:
    lda input_stream,x
    inc input_idx
    rts

screen_put_string:
    inc screen_put_string_calls
    lda zp_ptr0
    cmp #<ds_save_str
    bne !check_press+
    lda zp_ptr0_hi
    cmp #>ds_save_str
    bne !check_press+
    inc save_prompt_count
    rts
!check_press:
    lda zp_ptr0
    cmp #<press_key_str
    bne !check_nodev+
    lda zp_ptr0_hi
    cmp #>press_key_str
    bne !check_nodev+
    inc press_prompt_count
    rts
!check_nodev:
    lda zp_ptr0
    cmp #<de_nodev_str
    bne !check_drive+
    lda zp_ptr0_hi
    cmp #>de_nodev_str
    bne !check_drive+
    inc nodev_prompt_count
    rts
!check_drive:
    lda zp_ptr0
    cmp #<de_ind_pfx
    bne !done+
    lda zp_ptr0_hi
    cmp #>de_ind_pfx
    bne !done+
    inc drive_ind_count
!done:
    rts

screen_put_char:
    inc screen_put_char_calls
    sta last_char_value
    rts

screen_clear_row:
    inc screen_clear_row_calls
    rts

screen_put_decimal_rj2:
    inc screen_put_decimal_calls
    sta last_decimal_value
    rts

kernal_setnam:
    inc kernal_setnam_calls
    sta kernal_setnam_len
    rts

kernal_setlfs:
    inc kernal_setlfs_calls
    sta kernal_setlfs_la
    stx kernal_setlfs_dev
    sty kernal_setlfs_sec
    rts

kernal_open:
    inc kernal_open_calls
    lda kernal_open_fail
    beq !ok+
    sec
    rts
!ok:
    clc
    rts

kernal_close:
    inc kernal_close_calls
    rts

kernal_clrchn:
    inc kernal_clrchn_calls
    rts

kernal_readst:
    inc kernal_readst_calls
    lda kernal_readst_value
    rts

test_start:
    sei
    cld
    ldx #$ff
    txs

    ldx #10
    lda #$ff
!init_results:
    sta tc_results,x
    dex
    bpl !init_results-

    // Test 1: disk_prompt no-op in mode 0
    jsr reset_harness_state
    lda #0
    sta disk_mode
    jsr disk_prompt_save
    lda screen_put_string_calls
    bne !t1_fail+
    lda input_get_key_calls
    bne !t1_fail+
    lda kernal_open_calls
    bne !t1_fail+
    lda #1
    bne !t1_store+
!t1_fail:
    lda #0
!t1_store:
    sta tc_results + 0

    // Test 2: disk_prompt no-op in mode 2
    jsr reset_harness_state
    lda #2
    sta disk_mode
    jsr disk_prompt_save
    lda screen_put_string_calls
    bne !t2_fail+
    lda input_get_key_calls
    bne !t2_fail+
    lda kernal_open_calls
    bne !t2_fail+
    lda #1
    bne !t2_store+
!t2_fail:
    lda #0
!t2_store:
    sta tc_results + 1

    // Test 3: disk_prompt mode 1 shows prompt, waits for key, then inits drive
    jsr reset_harness_state
    lda #1
    sta disk_mode
    lda #9
    sta save_device
    lda #1
    sta input_len
    lda #$20
    sta input_stream
    jsr disk_prompt_save
    lda save_prompt_count
    cmp #1
    bne !t3_fail+
    lda press_prompt_count
    cmp #1
    bne !t3_fail+
    lda input_get_key_calls
    cmp #1
    bne !t3_fail+
    lda kernal_open_calls
    cmp #1
    bne !t3_fail+
    lda kernal_close_calls
    cmp #1
    bne !t3_fail+
    lda kernal_clrchn_calls
    cmp #1
    bne !t3_fail+
    lda screen_clear_row_calls
    cmp #2
    bne !t3_fail+
    lda kernal_setlfs_dev
    cmp #9
    bne !t3_fail+
    lda #1
    bne !t3_store+
!t3_fail:
    lda #0
!t3_store:
    sta tc_results + 2

    // Test 4: disk_init_drive uses current save_device
    jsr reset_harness_state
    lda #9
    sta save_device
    jsr disk_init_drive
    lda kernal_setnam_len
    cmp #2
    bne !t4_fail+
    lda kernal_setlfs_la
    cmp #CMD_CHANNEL
    bne !t4_fail+
    lda kernal_setlfs_dev
    cmp #9
    bne !t4_fail+
    lda kernal_setlfs_sec
    cmp #CMD_CHANNEL
    bne !t4_fail+
    lda kernal_open_calls
    cmp #1
    bne !t4_fail+
    lda kernal_close_calls
    cmp #1
    bne !t4_fail+
    lda kernal_clrchn_calls
    cmp #1
    bne !t4_fail+
    lda #1
    bne !t4_store+
!t4_fail:
    lda #0
!t4_store:
    sta tc_results + 3

    // Test 5: probe_device present path
    jsr reset_harness_state
    ldx #9
    jsr probe_device
    bcs !t5_fail+
    lda kernal_setlfs_dev
    cmp #9
    bne !t5_fail+
    lda kernal_readst_calls
    cmp #1
    bne !t5_fail+
    lda kernal_close_calls
    cmp #1
    bne !t5_fail+
    lda kernal_clrchn_calls
    cmp #1
    bne !t5_fail+
    lda #1
    bne !t5_store+
!t5_fail:
    lda #0
!t5_store:
    sta tc_results + 4

    // Test 6: probe_device OPEN-fail path
    jsr reset_harness_state
    lda #1
    sta kernal_open_fail
    ldx #9
    jsr probe_device
    bcc !t6_fail+
    lda kernal_close_calls
    bne !t6_fail+
    lda kernal_clrchn_calls
    cmp #1
    bne !t6_fail+
    lda #1
    bne !t6_store+
!t6_fail:
    lda #0
!t6_store:
    sta tc_results + 5

    // Test 7: probe_device READST-error path
    jsr reset_harness_state
    lda #$80
    sta kernal_readst_value
    ldx #9
    jsr probe_device
    bcc !t7_fail+
    lda kernal_readst_calls
    cmp #1
    bne !t7_fail+
    lda kernal_close_calls
    cmp #1
    bne !t7_fail+
    lda kernal_clrchn_calls
    cmp #1
    bne !t7_fail+
    lda #1
    bne !t7_store+
!t7_fail:
    lda #0
!t7_store:
    sta tc_results + 6

    // Test 8: disk_enter_device accepts one-digit device
    jsr reset_harness_state
    lda #2
    sta input_len
    lda #$38
    sta input_stream
    lda #$0d
    sta input_stream + 1
    jsr disk_enter_device
    bcs !t8_fail+
    lda disk_mode
    cmp #2
    bne !t8_fail+
    lda save_device
    cmp #8
    bne !t8_fail+
    lda drive_ind_count
    cmp #1
    bne !t8_fail+
    lda screen_put_decimal_calls
    cmp #1
    bne !t8_fail+
    lda last_decimal_value
    cmp #8
    bne !t8_fail+
    lda #1
    bne !t8_store+
!t8_fail:
    lda #0
!t8_store:
    sta tc_results + 7

    // Test 9: disk_enter_device accepts two-digit device
    jsr reset_harness_state
    lda #3
    sta input_len
    lda #$33
    sta input_stream
    lda #$30
    sta input_stream + 1
    lda #$0d
    sta input_stream + 2
    jsr disk_enter_device
    bcs !t9_fail+
    lda save_device
    cmp #30
    bne !t9_fail+
    lda last_decimal_value
    cmp #30
    bne !t9_fail+
    lda #1
    bne !t9_store+
!t9_fail:
    lda #0
!t9_store:
    sta tc_results + 8

    // Test 10: invalid entry re-prompts before succeeding
    jsr reset_harness_state
    lda #4
    sta input_len
    lda #$37
    sta input_stream
    lda #$0d
    sta input_stream + 1
    lda #$38
    sta input_stream + 2
    lda #$0d
    sta input_stream + 3
    jsr disk_enter_device
    bcs !t10_fail+
    lda save_device
    cmp #8
    bne !t10_fail+
    lda drive_ind_count
    cmp #1
    bne !t10_fail+
    lda screen_put_string_calls
    cmp #3                      // prompt twice + drive indicator
    bne !t10_fail+
    lda #1
    bne !t10_store+
!t10_fail:
    lda #0
!t10_store:
    sta tc_results + 9

    // Test 11: absent device shows error and returns carry set
    jsr reset_harness_state
    lda #1
    sta kernal_open_fail
    lda #3
    sta input_len
    lda #$38
    sta input_stream
    lda #$0d
    sta input_stream + 1
    lda #$20
    sta input_stream + 2
    lda #0
    sta disk_mode
    lda #9
    sta save_device
    jsr disk_enter_device
    bcc !t11_fail+
    lda nodev_prompt_count
    cmp #1
    bne !t11_fail+
    lda input_get_key_calls
    cmp #3
    bne !t11_fail+
    lda disk_mode
    bne !t11_fail+
    lda save_device
    cmp #9
    bne !t11_fail+
    lda #1
    bne !t11_store+
!t11_fail:
    lda #0
!t11_store:
    sta tc_results + 10

test_finish:
    ldx #10
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk
