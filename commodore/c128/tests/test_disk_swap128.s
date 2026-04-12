// test_disk_swap128.s — Focused FEAT-DISK prompt policy tests for C128
//
// Tests:
//  1. disk_reset_session_state resets defaults
//  2. disk_prompt_game is a no-op in C128 one-drive mode
//  3. disk_prompt_save still prompts and re-inits the save drive in one-drive mode
//  4. disk_prompt_game remains a no-op when disk_mode is unset

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

.encoding "screencode_mixed"

#import "../../common/zeropage.s"

.const SCREEN_COLS = 80
.const STATUS_ROW = 23
.const COL_WHITE = $01
.const CMD_CHANNEL = 15

.const KERNAL_SETNAM = w_setnam
.const KERNAL_SETLFS = w_setlfs
.const KERNAL_OPEN   = w_open
.const KERNAL_CLOSE  = w_close
.const KERNAL_CLRCHN = w_clrchn
.const KERNAL_READST = w_readst
.const KERNAL_CHKIN  = w_chkin
.const KERNAL_CHKOUT = w_chkout
.const KERNAL_CHRIN  = w_chrin
.const KERNAL_CHROUT = w_chrout

.macro EnterKernal() {
}

.macro ExitKernal() {
}

screen_put_string_calls: .byte 0
screen_clear_row_calls:  .byte 0
input_modal_calls:       .byte 0
save_prompt_count:       .byte 0
game_prompt_count:       .byte 0
press_prompt_count:      .byte 0
w_setnam_calls:          .byte 0
w_setlfs_calls:          .byte 0
w_setlfs_dev_seen:       .byte 0
w_open_calls:            .byte 0
w_close_calls:           .byte 0
w_clrchn_calls:          .byte 0

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

#import "../../common/runtime_ui_strings.s"
#import "../../common/disk_swap.s"

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass

reset_harness_state:
    lda #0
    ldx #state_end - state_start - 1
!clr:
    sta state_start,x
    dex
    bpl !clr-
    rts
.label state_start = screen_put_string_calls
.label state_end = w_clrchn_calls + 1

input_get_modal_dismiss_key:
    inc input_modal_calls
    lda #$20
    rts

screen_put_string:
    inc screen_put_string_calls
    lda zp_ptr0
    cmp #<ds_save_str
    bne !check_game+
    lda zp_ptr0_hi
    cmp #>ds_save_str
    bne !check_game+
    inc save_prompt_count
    rts
!check_game:
    lda zp_ptr0
    cmp #<ds_game_str
    bne !check_press+
    lda zp_ptr0_hi
    cmp #>ds_game_str
    bne !check_press+
    inc game_prompt_count
    rts
!check_press:
    lda zp_ptr0
    cmp #<press_key_str
    bne !done+
    lda zp_ptr0_hi
    cmp #>press_key_str
    bne !done+
    inc press_prompt_count
!done:
    rts

screen_put_char:
    rts

screen_clear_row:
    inc screen_clear_row_calls
    rts

screen_put_decimal_rj2:
    rts

w_setnam:
    inc w_setnam_calls
    rts

w_setlfs:
    inc w_setlfs_calls
    stx w_setlfs_dev_seen
    rts

w_open:
    inc w_open_calls
    clc
    rts

w_close:
    inc w_close_calls
    rts

w_clrchn:
    inc w_clrchn_calls
    rts

w_readst:
    lda #0
    rts

w_chkin:
    clc
    rts

w_chkout:
    clc
    rts

w_chrin:
    lda #0
    rts

w_chrout:
    rts

test_start:
    sei
    cld
    ldx #$ff
    txs

    // Test 1: disk_reset_session_state resets defaults
    jsr reset_harness_state
    lda #2
    sta disk_mode
    lda #9
    sta save_device
    lda #1
    sta disk_setup_done
    jsr disk_reset_session_state
    lda disk_mode
    beq *+5
    jmp test_fail
    lda save_device
    cmp #8
    beq *+5
    jmp test_fail
    lda disk_setup_done
    beq *+5
    jmp test_fail
    lda disk_ui_result
    cmp #1
    beq *+5
    jmp test_fail

    // Test 2: C128 one-drive game return skips prompt and drive init.
    jsr reset_harness_state
    lda #1
    sta disk_mode
    jsr disk_prompt_game
    lda game_prompt_count
    beq *+5
    jmp test_fail
    lda press_prompt_count
    beq *+5
    jmp test_fail
    lda input_modal_calls
    beq *+5
    jmp test_fail
    lda w_open_calls
    beq *+5
    jmp test_fail
    lda screen_clear_row_calls
    beq *+5
    jmp test_fail

    // Test 3: C128 one-drive save prompt still shows UI and re-inits the save drive.
    jsr reset_harness_state
    lda #1
    sta disk_mode
    lda #9
    sta save_device
    jsr disk_prompt_save
    lda save_prompt_count
    cmp #1
    beq *+5
    jmp test_fail
    lda press_prompt_count
    cmp #1
    beq *+5
    jmp test_fail
    lda input_modal_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda w_open_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda w_setlfs_dev_seen
    cmp #9
    beq *+5
    jmp test_fail
    lda screen_clear_row_calls
    cmp #2
    beq *+5
    jmp test_fail

    // Test 4: unset mode still leaves disk_prompt_game as a no-op.
    jsr reset_harness_state
    lda #0
    sta disk_mode
    jsr disk_prompt_game
    lda screen_put_string_calls
    beq *+5
    jmp test_fail
    lda input_modal_calls
    beq *+5
    jmp test_fail
    lda w_open_calls
    beq *+5
    jmp test_fail

    jmp test_pass
