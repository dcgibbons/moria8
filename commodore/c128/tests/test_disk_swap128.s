// test_disk_swap128.s — Focused FEAT-DISK prompt policy tests for C128
//
// Tests:
//  1. disk_reset_session_state resets defaults
//  2. disk_prompt_game is a no-op in C128 one-drive mode
//  3. disk_prompt_save still prompts and re-inits the save drive before setup completes
//  4. disk_prompt_save becomes a silent drive re-init after one-drive setup completes
//  5. disk_prompt_game remains a no-op when disk_mode is unset
//  6. initialized Disk Setup commit reports carry clear/success
//  7. marker initialization does not trust X across KERNAL byte I/O
//  8. save-media failure classifier separates wrong media from drive errors

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

.encoding "screencode_mixed"

#import "../../common/zeropage.s"

.const SCREEN_COLS = 80
.const STATUS_ROW = 23
.const COL_WHITE = $01
.const hal_storage_cmd_channel = 15
.const hal_storage_marker_file_num = 13
.const hal_storage_marker_sec_read = 2
.const hal_storage_marker_sec_write = 2
.const hal_storage_program_file_num = 7
.const CMD_CHANNEL = hal_storage_cmd_channel
.const DISK_MARKER_FILE_NUM = hal_storage_marker_file_num
.const C128_MEDIA_UNKNOWN = 0
.const C128_MEDIA_PROGRAM = 1
.const C128_MEDIA_SAVE    = 2

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
w_setlfs_lfn_seen:       .byte 0
w_setlfs_dev_seen:       .byte 0
w_open_calls:            .byte 0
w_close_calls:           .byte 0
w_clrchn_calls:          .byte 0
marker_write_count:      .byte 0
marker_read_count:       .byte 0
command_read_count:      .byte 0
marker_readst_override:  .byte 0
marker_bad_byte:         .byte 0
command_open_fail:       .byte 0
w_chkin_lfn_seen:        .byte 0
c128_media_state:        .byte C128_MEDIA_UNKNOWN
marker_write_buf:        .fill 6, 0

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

cmd_status_bytes:
    .byte $30, $31, $30, $30, $30, $30

hal_storage_init_command:
    .byte $49, $30
hal_storage_marker_magic:
    .byte $4d, $38, $53, $41, $56, $45
.label hal_storage_marker_magic_len = * - hal_storage_marker_magic
hal_storage_marker_read_name:
    .byte $30, $3a
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44
    .byte $2c, $53, $2c, $52
.label hal_storage_marker_read_name_len = * - hal_storage_marker_read_name
hal_storage_marker_write_name:
    .byte $40, $30, $3a
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44
    .byte $2c, $53, $2c, $57
.label hal_storage_marker_write_name_len = * - hal_storage_marker_write_name
hal_storage_marker_scratch_name:
    .byte $53, $30, $3a
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44
.label hal_storage_marker_scratch_name_len = * - hal_storage_marker_scratch_name
.label disk_marker_magic = hal_storage_marker_magic
.label DISK_MARKER_MAGIC_LEN = hal_storage_marker_magic_len
.label hal_storage_read_command_status = test_storage_read_command_status

#import "../../common/runtime_ui_strings.s"
#import "../../common/disk_swap.s"
#import "../../common/disk_setup_banked.s"

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
.label state_end = marker_write_buf + DISK_MARKER_MAGIC_LEN

input_get_modal_dismiss_key:
    inc input_modal_calls
    lda #$20
    rts

input_prepare_modal_dismiss_key:
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
    sta w_setlfs_lfn_seen
    stx w_setlfs_dev_seen
    rts

w_open:
    inc w_open_calls
    lda w_setlfs_lfn_seen
    cmp #CMD_CHANNEL
    bne !check_marker+
    lda command_open_fail
    beq !ok+
    sec
    rts
!check_marker:
    clc
!ok:
    rts

w_close:
    inc w_close_calls
    rts

w_clrchn:
    inc w_clrchn_calls
    rts

w_readst:
    lda w_chkin_lfn_seen
    cmp #DISK_MARKER_FILE_NUM
    bne !ok+
    lda marker_readst_override
    beq !marker_default+
    rts
!marker_default:
    lda marker_read_count
    cmp #DISK_MARKER_MAGIC_LEN
    bne !ok+
    lda #$40
    rts
!ok:
    lda #0
    rts

w_chkin:
    stx w_chkin_lfn_seen
    clc
    rts

w_chkout:
    clc
    rts

w_chrin:
    lda w_chkin_lfn_seen
    cmp #CMD_CHANNEL
    bne !marker+
    ldx command_read_count
    inc command_read_count
    lda cmd_status_bytes,x
    clc
    rts
!marker:
    ldx marker_read_count
    lda disk_marker_magic,x
    ldx marker_bad_byte
    beq !marker_ok+
    eor #$ff
!marker_ok:
    inc marker_read_count
    ldx #$a5
    clc
    rts

w_chrout:
    ldx marker_write_count
    sta marker_write_buf,x
    inc marker_write_count
    ldx #$5a
    clc
    rts

test_storage_read_command_status:
    lda #$ff
    sta disk_diag_cmd_status0
    sta disk_diag_cmd_status1
    lda #0
    ldx #0
    ldy #0
    jsr w_setnam
    lda #hal_storage_cmd_channel
    ldx save_device
    ldy #hal_storage_cmd_channel
    jsr w_setlfs
    jsr w_open
    bcs !done+
    ldx #hal_storage_cmd_channel
    jsr w_chkin
    bcs !close+
    jsr w_chrin
    sta disk_diag_cmd_status0
    jsr w_readst
    sta disk_diag_readst
    jsr w_chrin
    sta disk_diag_cmd_status1
    jsr w_readst
    sta disk_diag_readst
!close:
    jsr w_clrchn
    lda #hal_storage_cmd_channel
    jsr w_close
!done:
    rts

tramp_disk_setup_ui_action:
    lda #DISK_UI_RES_OK
    sta disk_ui_result
    clc
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

    // Test 3: before setup completes, C128 one-drive save prompt still shows
    // UI and re-inits the save drive.
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

    // Test 4: after one-drive setup completes, disk_prompt_save skips UI but
    // still re-inits the current save drive.
    jsr reset_harness_state
    lda #1
    sta disk_mode
    sta disk_setup_done
    lda #9
    sta save_device
    jsr disk_prompt_save
    lda screen_put_string_calls
    beq *+5
    jmp test_fail
    lda input_modal_calls
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

    // Test 5: unset mode still leaves disk_prompt_game as a no-op.
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

    // Test 6: initialized Disk Setup commit reports success. This path is
    // reached after the marker has been written and verified.
    jsr reset_harness_state
    lda #0
    sta disk_setup_done
    lda #DISK_UI_RES_CANCEL
    sta disk_ui_result
    sec
    jsr disk_setup_commit_initialized
    bcc *+5
    jmp test_fail
    lda disk_setup_done
    cmp #1
    beq *+5
    jmp test_fail
    lda disk_ui_result
    cmp #DISK_UI_RES_OK
    beq *+5
    jmp test_fail

    // Test 7: marker init writes and verifies the marker even when KERNAL
    // byte I/O clobbers X.
    jsr reset_harness_state
    lda #9
    sta save_device
    sec
    jsr disk_marker_init
    bcc *+5
    jmp test_fail
    lda marker_write_count
    cmp #DISK_MARKER_MAGIC_LEN
    beq *+5
    jmp test_fail
    lda marker_read_count
    cmp #DISK_MARKER_MAGIC_LEN
    beq *+5
    jmp test_fail
    ldx #0
!check_marker_write:
    lda marker_write_buf,x
    cmp disk_marker_magic,x
    beq *+5
    jmp test_fail
    inx
    cpx #DISK_MARKER_MAGIC_LEN
    bcc !check_marker_write-
    lda disk_status
    beq *+5
    jmp test_fail
    lda disk_diag_scratch_status0
    cmp #$30
    beq *+5
    jmp test_fail
    lda disk_diag_scratch_status1
    cmp #$31
    beq *+5
    jmp test_fail
    lda disk_diag_write_status0
    cmp #$30
    beq *+5
    jmp test_fail
    lda disk_diag_write_status1
    cmp #$30
    beq *+5
    jmp test_fail

    // Test 8: C128 save-media failures must report detached/unready media as
    // disk errors, not as "Wrong Save Disk."; readable media with a mismatched
    // or missing marker remains wrong-save-disk.
    jsr reset_harness_state
    lda #$81                    // Marker OPEN failed: drive/device I/O.
    sta disk_status
    lda #0
    sta disk_diag_readst
    jsr disk_save_media_error_is_io
    bcs *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$83                    // Marker contents mismatch on readable media.
    sta disk_status
    lda #0
    sta disk_diag_readst
    jsr disk_save_media_error_is_io
    bcc *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$84                    // Ambiguous READST failure is I/O by default.
    sta disk_status
    lda #$42
    sta disk_diag_readst
    jsr disk_save_media_error_is_io
    bcs *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$84                    // DOS 62 proves readable media, missing marker.
    sta disk_status
    lda #$42
    sta disk_diag_readst
    lda #$36
    sta cmd_status_bytes
    lda #$32
    sta cmd_status_bytes + 1
    jsr disk_save_media_error_is_io
    bcc *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$84                    // Non-missing read status is I/O.
    sta disk_status
    lda #$02
    sta disk_diag_readst
    jsr disk_save_media_error_is_io
    bcs *+5
    jmp test_fail

    jsr reset_harness_state
    lda #1
    sta disk_setup_done
    lda #2
    sta disk_mode
    lda #$42
    sta marker_readst_override
    lda #1
    sta command_open_fail
    jsr disk_require_save_media
    bcs *+5
    jmp test_fail
    jsr disk_save_media_error_is_io
    bcs *+5
    jmp test_fail

    jsr reset_harness_state
    lda #1
    sta disk_setup_done
    lda #2
    sta disk_mode
    lda #$42
    sta marker_readst_override
    lda #$36
    sta cmd_status_bytes
    lda #$32
    sta cmd_status_bytes + 1
    jsr disk_require_save_media
    bcs *+5
    jmp test_fail
    jsr disk_save_media_error_is_io
    bcc *+5
    jmp test_fail

    jsr reset_harness_state
    lda #1
    sta disk_setup_done
    lda #2
    sta disk_mode
    sta marker_bad_byte
    jsr disk_require_save_media
    bcs *+5
    jmp test_fail
    jsr disk_save_media_error_is_io
    bcc *+5
    jmp test_fail

    jmp test_pass
