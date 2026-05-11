// test_disk_swap.s — Resident FEAT-DISK unit tests
//
// Tests:
//  1. disk_reset_session_state resets session defaults
//  2. disk_prompt no-op in mode 0
//  3. disk_prompt in mode 1 shows prompt, waits, and inits drive
//  4. disk_prompt restores normal C64 banking after prompt/input recovery
//  5. disk_kernal wrapper preserves caller bank + interrupt state while FEAT
//     KERNAL calls are handled by per-vector wrappers
//  6. hal_storage_probe_media present path
//  7. hal_storage_probe_media OPEN-fail path
//  8. disk_marker_present accepts valid marker bytes
//  9. disk_marker_present rejects invalid marker bytes
// 10. disk_require_save_media fails when setup is incomplete
// 11. disk_require_save_media succeeds for configured marker media
// 12. FEAT KERNAL wrappers keep caller-safe ZP intact while using KERNAL-volatiles
// 13. disk_prompt_save consumes the fresh C64 one-drive setup state once
// 14. disk_prompt clears the full modal immediately after key dismiss

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"

.encoding "screencode_mixed"

#import "../../common/zeropage.s"

.const SCREEN_COLS = 40
.const STATUS_ROW = 21
.const COL_WHITE = $01
.const hal_storage_cmd_channel = 15
.const hal_storage_marker_file_num = 6
.const hal_storage_marker_sec_read = 2
.const hal_storage_marker_sec_write = 2
.const hal_storage_program_file_num = 7

.const KERNAL_SETNAM = kernal_setnam
.const KERNAL_SETLFS = kernal_setlfs
.const KERNAL_OPEN   = kernal_open
.const KERNAL_CLOSE  = kernal_close
.const KERNAL_CLRCHN = kernal_clrchn
.const KERNAL_READST = kernal_readst
.const KERNAL_CHKIN  = kernal_chkin
.const KERNAL_CHKOUT = kernal_chkout
.const KERNAL_CHRIN  = kernal_chrin
.const KERNAL_CHROUT = kernal_chrout

screen_put_string_calls: .byte 0
screen_clear_calls:      .byte 0
ui_clear_calls:          .byte 0
post_key_pre_init_clear_calls: .byte 0
screen_clear_row_calls:  .byte 0
input_get_key_calls:     .byte 0
save_prompt_count:       .byte 0
press_prompt_count:      .byte 0
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
kernal_chkin_calls:      .byte 0
kernal_chkin_fail:       .byte 0
kernal_chkout_calls:     .byte 0
kernal_chkout_fail:      .byte 0
kernal_chrin_calls:      .byte 0
kernal_chrin_mode:       .byte 0
kernal_chrout_calls:     .byte 0
kernal_last_written:     .byte 0
kernal_clobber_zp:       .byte 0
input_idx:               .byte 0
input_len:               .byte 0
input_stream:            .fill 8, 0

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

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
.label disk_marker_read_fname = hal_storage_marker_read_name
.label disk_marker_read_fname_len = hal_storage_marker_read_name_len
.label DISK_MARKER_MAGIC_LEN = hal_storage_marker_magic_len

c64_disk_marker_present:
    .const TEST_DISK_MARKER_FILE_NUM = 6
    .const TEST_DISK_MARKER_SEC_RD = 9
    .const TEST_DISK_MARKER_MAGIC_LEN = 6
    lda #1
    sta disk_status
    lda #hal_storage_marker_read_name_len
    ldx #<hal_storage_marker_read_name
    ldy #>hal_storage_marker_read_name
    jsr kernal_setnam
    lda #TEST_DISK_MARKER_FILE_NUM
    ldx save_device
    ldy #TEST_DISK_MARKER_SEC_RD
    jsr kernal_setlfs
    jsr kernal_open
    bcs !done+
    ldx #TEST_DISK_MARKER_FILE_NUM
    jsr kernal_chkin
    bcs !close+
    ldx #0
!read:
    jsr kernal_chrin
    cmp hal_storage_marker_magic,x
    bne !close+
    inx
    cpx #TEST_DISK_MARKER_MAGIC_LEN
    bcc !read-
    lda #0
    sta disk_status
!close:
    jsr kernal_clrchn
    lda #TEST_DISK_MARKER_FILE_NUM
    jsr kernal_close
!done:
    lda disk_status
    beq !ok+
    sec
    rts
!ok:
    clc
    rts

#import "../../common/runtime_ui_strings.s"
#import "../../common/disk_swap.s"

tc_results: .fill 14, $ff

zp_save_ptr0:       .byte 0
zp_save_ptr0_hi:    .byte 0
zp_save_cursor_row: .byte 0
zp_save_text_color: .byte 0

save_zp:
    lda zp_ptr0
    sta zp_save_ptr0
    lda zp_ptr0_hi
    sta zp_save_ptr0_hi
    lda zp_cursor_row
    sta zp_save_cursor_row
    lda zp_text_color
    sta zp_save_text_color
    rts

restore_zp:
    lda zp_save_ptr0
    sta zp_ptr0
    lda zp_save_ptr0_hi
    sta zp_ptr0_hi
    lda zp_save_cursor_row
    sta zp_cursor_row
    lda zp_save_text_color
    sta zp_text_color
    rts

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
    bne !done+
    lda zp_ptr0_hi
    cmp #>press_key_str
    bne !done+
    inc press_prompt_count
!done:
    rts

screen_put_char:
    rts

msg_init:
    rts

ui_clear_full_screen_safe:
    inc ui_clear_calls
    lda input_get_key_calls
    cmp #1
    bne !done+
    lda kernal_open_calls
    bne !done+
    inc post_key_pre_init_clear_calls
!done:
    rts

screen_clear:
    inc screen_clear_calls
    rts

screen_clear_row:
    inc screen_clear_row_calls
    rts

screen_put_decimal_rj2:
    rts

kernal_maybe_clobber_zp:
    lda kernal_clobber_zp
    beq !done+
    lda #$aa
    sta zp_vol_2
    lda #$bb
    sta zp_vol_3
    lda #$cc
    sta zp_vol_4
    lda #$dd
    sta zp_vol_5
!done:
    rts

kernal_setnam:
    jsr kernal_maybe_clobber_zp
    inc kernal_setnam_calls
    sta kernal_setnam_len
    rts

kernal_setlfs:
    jsr kernal_maybe_clobber_zp
    inc kernal_setlfs_calls
    sta kernal_setlfs_la
    stx kernal_setlfs_dev
    sty kernal_setlfs_sec
    rts

kernal_open:
    jsr kernal_maybe_clobber_zp
    inc kernal_open_calls
    lda kernal_open_fail
    beq !ok+
    sec
    rts
!ok:
    clc
    rts

kernal_close:
    jsr kernal_maybe_clobber_zp
    inc kernal_close_calls
    rts

kernal_clrchn:
    jsr kernal_maybe_clobber_zp
    inc kernal_clrchn_calls
    rts

kernal_readst:
    jsr kernal_maybe_clobber_zp
    inc kernal_readst_calls
    lda kernal_readst_value
    rts

kernal_chkin:
    jsr kernal_maybe_clobber_zp
    inc kernal_chkin_calls
    lda kernal_chkin_fail
    beq !ok+
    sec
    rts
!ok:
    clc
    rts

kernal_chkout:
    jsr kernal_maybe_clobber_zp
    inc kernal_chkout_calls
    lda kernal_chkout_fail
    beq !ok+
    sec
    rts
!ok:
    clc
    rts

kernal_chrin:
    jsr kernal_maybe_clobber_zp
    inc kernal_chrin_calls
    ldx kernal_chrin_calls
    dex
    lda kernal_chrin_mode
    beq !valid+
    lda #$58                    // 'X'
    rts
!valid:
    lda disk_marker_magic,x
    rts

kernal_chrout:
    jsr kernal_maybe_clobber_zp
    inc kernal_chrout_calls
    sta kernal_last_written
    rts

.label c64_disk_setnam = kernal_setnam
.label c64_disk_setlfs = kernal_setlfs
.label c64_disk_open   = kernal_open
.label c64_disk_close  = kernal_close
.label c64_disk_clrchn = kernal_clrchn
.label c64_disk_readst = kernal_readst
.label c64_disk_chkin  = kernal_chkin
.label c64_disk_chkout = kernal_chkout
.label c64_disk_chrin  = kernal_chrin
.label c64_disk_chrout = kernal_chrout

hal_storage_probe_media:
    stx disk_temp
    jsr disk_kernal_enter
    lda #0
    ldx #0
    ldy #0
    jsr c64_disk_setnam
    lda #hal_storage_cmd_channel
    ldx disk_temp
    ldy #hal_storage_cmd_channel
    jsr c64_disk_setlfs
    jsr c64_disk_open
    bcs !absent+
    lda #hal_storage_cmd_channel
    jsr c64_disk_close
    jsr c64_disk_clrchn
    jsr disk_kernal_exit
    clc
    rts
!absent:
    jsr c64_disk_clrchn
    jsr disk_kernal_exit
    sec
    rts

hal_storage_init_selected_drive:
    jsr disk_kernal_enter
    lda #2
    ldx #<hal_storage_init_command
    ldy #>hal_storage_init_command
    jsr c64_disk_setnam
    lda #hal_storage_cmd_channel
    ldx disk_prompt_device
    ldy #hal_storage_cmd_channel
    jsr c64_disk_setlfs
    jsr c64_disk_open
    bcs !done+
    lda #hal_storage_cmd_channel
    jsr c64_disk_close
!done:
    jsr c64_disk_clrchn
    jsr disk_kernal_exit
    rts

test_start:
    sei
    cld
    ldx #$ff
    txs

    ldx #13
    lda #$ff
!init_results:
    sta tc_results,x
    dex
    bpl !init_results-

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
    bne !t1_fail+
    lda save_device
    cmp #8
    bne !t1_fail+
    lda disk_setup_done
    bne !t1_fail+
    lda disk_ui_result
    cmp #1
    bne !t1_fail+
    lda #1
    bne !t1_store+
!t1_fail:
    lda #0
!t1_store:
    sta tc_results + 0

    // Test 2: disk_prompt no-op in mode 0
    jsr reset_harness_state
    lda #0
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

    // Test 3: disk_prompt mode 1 shows prompt, waits, and inits drive
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
    lda ui_clear_calls
    cmp #2
    bne !t3_fail+
    lda post_key_pre_init_clear_calls
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
    lda kernal_setlfs_dev
    cmp #9
    bne !t3_fail+
    lda screen_clear_row_calls
    cmp #0
    bne !t3_fail+
    lda #1
    bne !t3_store+
!t3_fail:
    lda #0
!t3_store:
    sta tc_results + 2

    // Test 4: disk_prompt restores normal C64 banking after prompt/input recovery
    jsr reset_harness_state
    lda #1
    sta disk_mode
    lda #1
    sta input_len
    lda #$20
    sta input_stream
    lda #BANK_NO_KERNAL
    sta $01
    jsr disk_prompt_game
    lda $01
    cmp #BANK_NO_BASIC
    bne !t4_fail+
    lda ui_clear_calls
    cmp #2
    bne !t4_fail+
    lda #1
    bne !t4_store+
!t4_fail:
    lda #0
!t4_store:
    sta tc_results + 3

    // Test 5: disk_kernal wrapper now preserves caller bank + interrupt state.
    jsr reset_harness_state
    sei
    lda #BANK_NO_KERNAL
    sta $01
    jsr disk_kernal_enter
    lda $01
    cmp #BANK_NO_KERNAL
    bne !t5_fail+
    php
    pla
    and #%00000100
    beq !t5_fail+
    jsr disk_kernal_exit
    lda $01
    cmp #BANK_NO_KERNAL
    bne !t5_fail+
    php
    pla
    and #%00000100
    beq !t5_fail+
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr disk_kernal_enter
    lda $01
    cmp #BANK_NO_ROMS
    bne !t5_fail+
    php
    pla
    and #%00000100
    beq !t5_fail+
    jsr disk_kernal_exit
    lda $01
    cmp #BANK_NO_ROMS
    bne !t5_fail+
    php
    pla
    and #%00000100
    beq !t5_fail+
    lda #1
    bne !t5_store+
!t5_fail:
    lda #0
!t5_store:
    sta tc_results + 4

    // Test 6: hal_storage_probe_media present path
    jsr reset_harness_state
    ldx #9
    jsr hal_storage_probe_media
    bcs !t6_fail+
    lda kernal_readst_calls
    bne !t6_fail+
    lda kernal_setlfs_dev
    cmp #9
    bne !t6_fail+
    lda #1
    bne !t6_store+
!t6_fail:
    lda #0
!t6_store:
    sta tc_results + 5

    // Test 7: hal_storage_probe_media OPEN-fail path
    jsr reset_harness_state
    lda #5
    sta kernal_open_fail
    ldx #9
    jsr hal_storage_probe_media
    bcc !t7_fail+
    lda kernal_close_calls
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

    // Test 8: disk_marker_present accepts valid marker bytes
    jsr reset_harness_state
    lda #9
    sta save_device
    jsr disk_marker_present
    bcs !t8_fail+
    lda kernal_chkin_calls
    cmp #1
    bne !t8_fail+
    lda kernal_chrin_calls
    cmp #DISK_MARKER_MAGIC_LEN
    bne !t8_fail+
    lda #1
    bne !t8_store+
!t8_fail:
    lda #0
!t8_store:
    sta tc_results + 7

    // Test 9: disk_marker_present rejects invalid marker bytes
    jsr reset_harness_state
    lda #1
    sta kernal_chrin_mode
    lda #9
    sta save_device
    jsr disk_marker_present
    bcc !t9_fail+
    lda kernal_chrin_calls
    cmp #1
    bne !t9_fail+
    lda #1
    bne !t9_store+
!t9_fail:
    lda #0
!t9_store:
    sta tc_results + 8

    // Test 10: disk_require_save_media fails when setup is incomplete
    jsr reset_harness_state
    jsr disk_require_save_media
    bcc !t10_fail+
    lda kernal_open_calls
    bne !t10_fail+
    lda #1
    bne !t10_store+
!t10_fail:
    lda #0
!t10_store:
    sta tc_results + 9

    // Test 11: disk_require_save_media succeeds for configured marker media
    jsr reset_harness_state
    lda #1
    sta disk_setup_done
    lda #2
    sta disk_mode
    lda #9
    sta save_device
    jsr disk_require_save_media
    bcs !t11_fail+
    lda kernal_chrin_calls
    cmp #DISK_MARKER_MAGIC_LEN
    bne !t11_fail+
    lda #1
    bne !t11_store+
!t11_fail:
    lda #0
!t11_store:
    sta tc_results + 10

    // Test 12: FEAT KERNAL wrappers preserve caller-safe ZP state
    jsr reset_harness_state
    lda #1
    sta kernal_clobber_zp
    lda #$12
    sta zp_ptr0
    lda #$34
    sta zp_ptr0_hi
    lda #$05
    sta zp_cursor_row
    lda #$07
    sta zp_text_color
    ldx #9
    jsr hal_storage_probe_media
    bcs !t12_fail+
    lda zp_ptr0
    cmp #$12
    bne !t12_fail+
    lda zp_ptr0_hi
    cmp #$34
    bne !t12_fail+
    lda zp_cursor_row
    cmp #$05
    bne !t12_fail+
    lda zp_text_color
    cmp #$07
    bne !t12_fail+
    lda #1
    bne !t12_store+
!t12_fail:
    lda #0
!t12_store:
    sta tc_results + 11

    // Test 13: fresh one-drive setup state suppresses one redundant prompt.
    jsr reset_harness_state
    lda #1
    sta disk_mode
    lda #2
    sta disk_setup_done
    jsr disk_prompt_save
    lda screen_put_string_calls
    bne !t13_fail+
    lda input_get_key_calls
    bne !t13_fail+
    lda kernal_open_calls
    bne !t13_fail+
    lda ui_clear_calls
    bne !t13_fail+
    lda disk_setup_done
    cmp #1
    bne !t13_fail+
    lda #1
    bne !t13_store+
!t13_fail:
    lda #0
!t13_store:
    sta tc_results + 12

    // Test 14: prompted C64 disk swap clears the full modal after the key
    // and before drive initialization opens the command channel.
    jsr reset_harness_state
    lda #1
    sta disk_mode
    lda #1
    sta input_len
    lda #$20
    sta input_stream
    jsr disk_prompt_game
    lda post_key_pre_init_clear_calls
    cmp #1
    bne !t14_fail+
    lda screen_clear_row_calls
    bne !t14_fail+
    lda #1
    bne !t14_store+
!t14_fail:
    lda #0
!t14_store:
    sta tc_results + 13

test_finish:
    ldx #13
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk
