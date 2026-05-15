// test_disk_swap128.s — Focused FEAT-DISK prompt policy tests for C128
//
// Tests:
//  1. disk_reset_session_state resets defaults
//  2. disk_prompt_game is a no-op in C128 one-drive mode
//  3. disk_prompt_save still prompts and re-inits the save drive before setup completes
//  4. disk_prompt_save becomes a silent drive re-init after one-drive setup completes
//  5. failed C128 save-drive re-init clears current-save media ownership
//  6. disk_prompt_game remains a no-op when disk_mode is unset
//  7. initialized Disk Setup commit reports carry clear/success
//  8. marker initialization does not trust X across KERNAL byte I/O
//  9. save-media failure classifier separates wrong media from drive errors
// 10. Disk Setup init status capture maps normalized DOS statuses
// 11. Disk Setup status classifier returns normalized HAL statuses
// 12. Storage HAL command-status classifier maps captured DOS statuses
// 13. Storage HAL diagnostic labels expose platform diagnostic bytes

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

.encoding "screencode_mixed"

#define STORAGE_STATUS_HELPER

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

.label hal_storage_setnam = w_setnam
.label hal_storage_setlfs = w_setlfs
.label hal_storage_open = w_open
.label hal_storage_close = w_close
.label hal_storage_chkin = w_chkin
.label hal_storage_chkout = w_chkout
.label hal_storage_chrin = w_chrin
.label hal_storage_chrout = w_chrout
.label hal_storage_clrchn = w_clrchn
.label hal_storage_readst = w_readst

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
marker_missing_until_write:.byte 0
command_open_fail:       .byte 0
w_chkin_lfn_seen:        .byte 0
c128_media_state:        .byte C128_MEDIA_UNKNOWN
marker_write_buf:        .fill 6, 0
ui_action_count:         .byte 0
ui_action_log:           .fill 8, 0
ui_menu_result:          .byte 3      // DISK_UI_RES_TWO_DRIVE
ui_confirm_result:       .byte 5      // DISK_UI_RES_YES
ui_init_result:          .byte 5      // DISK_UI_RES_YES

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
.label hal_storage_command_status = disk_command_status
.label hal_storage_diag_code = disk_status
.label hal_storage_diag_phase = disk_diag_phase
.label hal_storage_diag_readst = disk_diag_readst
.label hal_storage_diag_device = disk_diag_device
.label hal_storage_diag_dos0 = disk_diag_cmd_status0
.label hal_storage_diag_dos1 = disk_diag_cmd_status1

hal_storage_probe_media:
    stx disk_temp
    lda #0
    ldx #0
    ldy #0
    jsr w_setnam
    lda #hal_storage_cmd_channel
    ldx disk_temp
    ldy #hal_storage_cmd_channel
    jsr w_setlfs
    jsr w_open
    bcs !absent+
    lda #hal_storage_cmd_channel
    jsr w_close
    jsr w_clrchn
    clc
    rts
!absent:
    jsr w_clrchn
    sec
    rts

hal_storage_init_selected_drive:
    lda #2
    ldx #<hal_storage_init_command
    ldy #>hal_storage_init_command
    jsr w_setnam
    lda #hal_storage_cmd_channel
    ldx disk_prompt_device
    ldy #hal_storage_cmd_channel
    jsr w_setlfs
    jsr w_open
    bcs !done+
    lda #hal_storage_cmd_channel
    jsr w_close
!done:
    jsr w_clrchn
    rts

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
.label state_end = ui_init_result + 1

input_get_modal_dismiss_key:
    inc input_modal_calls
    lda #$20
    rts

input_prepare_modal_dismiss_key:
.label hal_input_modal_prepare = input_prepare_modal_dismiss_key
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

.label hal_screen_put_string = screen_put_string
.label hal_screen_put_char = screen_put_char
.label hal_screen_clear_row = screen_clear_row

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
    ldx marker_missing_until_write
    beq !check_bad+
    ldx marker_write_count
    bne !check_bad+
    eor #$ff
    jmp !marker_ok+
!check_bad:
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
    ldx ui_action_count
    cpx #8
    bcs !skip_log+
    lda disk_ui_action
    sta ui_action_log,x
!skip_log:
    inc ui_action_count

    lda disk_ui_action
    cmp #DISK_UI_ACT_MENU
    bne !not_menu+
    lda ui_menu_result
    sta disk_ui_result
    clc
    rts
!not_menu:
    cmp #DISK_UI_ACT_CONFIRM_DRIVE9
    bne !not_confirm+
    lda ui_confirm_result
    sta disk_ui_result
    clc
    rts
!not_confirm:
    cmp #DISK_UI_ACT_INIT_PROMPT
    bne !not_init+
    lda ui_init_result
    sta disk_ui_result
    clc
    rts
!not_init:
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

    // Test 5: a failed C128 save-drive re-init does not keep claiming that
    // save media is current.
    jsr reset_harness_state
    lda #1
    sta disk_mode
    lda #1
    sta disk_setup_done
    lda #9
    sta save_device
    lda #C128_MEDIA_SAVE
    sta c128_media_state
    lda #1
    sta command_open_fail
    clc
    jsr disk_prompt_save
    bcs *+5
    jmp test_fail
    lda c128_media_state
    cmp #C128_MEDIA_UNKNOWN
    beq *+5
    jmp test_fail

    // Test 6: unset mode still leaves disk_prompt_game as a no-op.
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

    // Test 7: initialized Disk Setup commit reports success. This path is
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

    // Test 8: marker init writes and verifies the marker even when KERNAL
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

    // Test 8b: scratching a missing marker on a fresh save disk can report
    // DOS 62,FILE NOT FOUND. That is nonfatal for the scratch phase; creation
    // and verification must still proceed.
    jsr reset_harness_state
    lda #9
    sta save_device
    lda #1
    sta marker_missing_until_write
    lda #$36                    // 62 after scratch
    sta cmd_status_bytes
    lda #$32
    sta cmd_status_bytes + 1
    lda #$30                    // 00 after write/close
    sta cmd_status_bytes + 2
    sta cmd_status_bytes + 3
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
    lda disk_status
    beq *+5
    jmp test_fail
    lda disk_diag_scratch_status0
    cmp #$36
    beq *+5
    jmp test_fail
    lda disk_diag_scratch_status1
    cmp #$32
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
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$83                    // Marker contents mismatch on readable media.
    sta disk_status
    lda #0
    sta disk_diag_readst
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_WRONG_MEDIA
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$84                    // Ambiguous READST failure is I/O by default.
    sta disk_status
    lda #$42
    sta disk_diag_readst
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq *+5
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
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_WRONG_MEDIA
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$84                    // Non-missing read status is I/O.
    sta disk_status
    lda #$02
    sta disk_diag_readst
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq *+5
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
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq *+5
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
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_WRONG_MEDIA
    beq *+5
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
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_WRONG_MEDIA
    beq *+5
    jmp test_fail

    // Test 9: Disk Setup init status capture should use the shared DOS
    // normalizer for the friendly setup-status codes it preserves.
    jsr reset_harness_state
    lda #$32                    // 26, WRITE PROTECT ON
    sta disk_diag_cmd_status0
    lda #$36
    sta disk_diag_cmd_status1
    lda #0
    sta disk_status
    jsr disk_error_capture_c128
    lda disk_status
    cmp #26
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$37                    // 72, DISK FULL
    sta disk_diag_cmd_status0
    lda #$32
    sta disk_diag_cmd_status1
    lda #0
    sta disk_status
    jsr disk_error_capture_c128
    lda disk_status
    cmp #72
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$37                    // 74, DRIVE NOT READY
    sta disk_diag_cmd_status0
    lda #$34
    sta disk_diag_cmd_status1
    lda #0
    sta disk_status
    jsr disk_error_capture_c128
    lda disk_status
    cmp #74
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$33                    // 31 remains unmapped for setup capture.
    sta disk_diag_cmd_status0
    lda #$31
    sta disk_diag_cmd_status1
    lda #$99
    sta disk_status
    jsr disk_error_capture_c128
    lda disk_status
    cmp #$99
    beq *+5
    jmp test_fail

    // Test 10: Disk Setup status classification should return semantic HAL
    // statuses from the same DOS-status source used by setup diagnostics.
    jsr reset_harness_state
    lda #$32
    sta disk_diag_cmd_status0
    lda #$36
    sta disk_diag_cmd_status1
    jsr disk_setup_status
    cmp #HAL_STORAGE_STATUS_WRITE_PROTECTED
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$37
    sta disk_diag_cmd_status0
    lda #$32
    sta disk_diag_cmd_status1
    jsr disk_setup_status
    cmp #HAL_STORAGE_STATUS_DISK_FULL
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$37
    sta disk_diag_cmd_status0
    lda #$34
    sta disk_diag_cmd_status1
    jsr disk_setup_status
    cmp #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$33
    sta disk_diag_cmd_status0
    lda #$31
    sta disk_diag_cmd_status1
    lda #26
    sta disk_status
    jsr disk_setup_status
    cmp #HAL_STORAGE_STATUS_WRITE_PROTECTED
    beq *+5
    jmp test_fail

    // Test 11: Storage HAL command-status classification is the canonical
    // path for raw command-channel DOS digits after capture.
    jsr reset_harness_state
    lda #$30
    sta disk_diag_cmd_status0
    lda #$30
    sta disk_diag_cmd_status1
    jsr hal_storage_command_status
    cmp #HAL_STORAGE_STATUS_OK
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$32
    sta disk_diag_cmd_status0
    lda #$36
    sta disk_diag_cmd_status1
    jsr hal_storage_command_status
    cmp #HAL_STORAGE_STATUS_WRITE_PROTECTED
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$36
    sta disk_diag_cmd_status0
    lda #$32
    sta disk_diag_cmd_status1
    jsr hal_storage_command_status
    cmp #HAL_STORAGE_STATUS_NOT_FOUND
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$37
    sta disk_diag_cmd_status0
    lda #$32
    sta disk_diag_cmd_status1
    jsr hal_storage_command_status
    cmp #HAL_STORAGE_STATUS_DISK_FULL
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$37
    sta disk_diag_cmd_status0
    lda #$34
    sta disk_diag_cmd_status1
    jsr hal_storage_command_status
    cmp #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    beq *+5
    jmp test_fail

    jsr reset_harness_state
    lda #$33
    sta disk_diag_cmd_status0
    lda #$31
    sta disk_diag_cmd_status1
    jsr hal_storage_command_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq *+5
    jmp test_fail

    // Test 12: Storage HAL diagnostic labels expose the current raw C128
    // storage diagnostic bytes without common code knowing their native names.
    jsr reset_harness_state
    lda #$a5
    sta disk_status
    lda #$91
    sta disk_diag_phase
    lda #$40
    sta disk_diag_readst
    lda #9
    sta disk_diag_device
    lda #$37
    sta disk_diag_cmd_status0
    lda #$34
    sta disk_diag_cmd_status1
    lda hal_storage_diag_code
    cmp #$a5
    beq *+5
    jmp test_fail
    lda hal_storage_diag_phase
    cmp #$91
    beq *+5
    jmp test_fail
    lda hal_storage_diag_readst
    cmp #$40
    beq *+5
    jmp test_fail
    lda hal_storage_diag_device
    cmp #9
    beq *+5
    jmp test_fail
    lda hal_storage_diag_dos0
    cmp #$37
    beq *+5
    jmp test_fail
    lda hal_storage_diag_dos1
    cmp #$34
    beq *+5
    jmp test_fail

    // Test 13: Disk Setup's initial drive-9 confirmation path initializes a
    // missing marker and commits drive 9 as the save device.
    jsr reset_harness_state
    lda #1
    sta marker_missing_until_write
    lda #DISK_UI_RES_YES
    sta ui_confirm_result
    sta ui_init_result
    sec
    jsr disk_setup_run
    bcc *+5
    jmp test_fail
    lda disk_setup_done
    cmp #1
    beq *+5
    jmp test_fail
    lda disk_mode
    cmp #2
    beq *+5
    jmp test_fail
    lda save_device
    cmp #9
    beq *+5
    jmp test_fail
    lda marker_write_count
    cmp #DISK_MARKER_MAGIC_LEN
    beq *+5
    jmp test_fail
    lda disk_status
    beq *+5
    jmp test_fail
    lda ui_action_count
    cmp #3
    beq *+5
    jmp test_fail
    lda ui_action_log
    cmp #DISK_UI_ACT_CONFIRM_DRIVE9
    beq *+5
    jmp test_fail
    lda ui_action_log + 1
    cmp #DISK_UI_ACT_INSERT_DISK
    beq *+5
    jmp test_fail
    lda ui_action_log + 2
    cmp #DISK_UI_ACT_INIT_PROMPT
    beq *+5
    jmp test_fail

    // Test 14: if the initial drive-9 prompt is declined, the menu path can
    // still choose the separate save drive and initialize the marker.
    jsr reset_harness_state
    lda #1
    sta marker_missing_until_write
    lda #DISK_UI_RES_NO
    sta ui_confirm_result
    lda #DISK_UI_RES_TWO_DRIVE
    sta ui_menu_result
    lda #DISK_UI_RES_YES
    sta ui_init_result
    sec
    jsr disk_setup_run
    bcc *+5
    jmp test_fail
    lda disk_setup_done
    cmp #1
    beq *+5
    jmp test_fail
    lda disk_mode
    cmp #2
    beq *+5
    jmp test_fail
    lda save_device
    cmp #9
    beq *+5
    jmp test_fail
    lda marker_write_count
    cmp #DISK_MARKER_MAGIC_LEN
    beq *+5
    jmp test_fail
    lda disk_status
    beq *+5
    jmp test_fail
    lda ui_action_count
    cmp #4
    beq *+5
    jmp test_fail
    lda ui_action_log
    cmp #DISK_UI_ACT_CONFIRM_DRIVE9
    beq *+5
    jmp test_fail
    lda ui_action_log + 1
    cmp #DISK_UI_ACT_MENU
    beq *+5
    jmp test_fail
    lda ui_action_log + 2
    cmp #DISK_UI_ACT_INSERT_DISK
    beq *+5
    jmp test_fail
    lda ui_action_log + 3
    cmp #DISK_UI_ACT_INIT_PROMPT
    beq *+5
    jmp test_fail

    jmp test_pass
