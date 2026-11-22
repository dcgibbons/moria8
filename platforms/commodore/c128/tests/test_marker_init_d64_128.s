// test_marker_init_d64_128.s — C128 real-D64 marker-init smoke payload.
//
// This is intentionally not a product title/UI smoke. It exercises the real
// C128 storage marker-init path against an attached drive-9 disk image; the
// host test verifies the persistent D64 side effect.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

.encoding "screencode_mixed"

#define STORAGE_STATUS_HELPER

#import "../../../../core/zeropage.s"
#import "../../common/compat/io_kernal_consts.s"
#import "../hal/memory_bank_consts.s"
#import "../hal/storage_policy.s"

.const SCREEN_COLS = 80
.const STATUS_ROW = 23
.const COL_WHITE = $01
.const C128_MEDIA_UNKNOWN = 0
.const C128_MEDIA_PROGRAM = 1
.const C128_MEDIA_SAVE    = 2

.macro EnterKernal() {
}

.macro ExitKernal() {
}

// C128 storage-drive helpers call the product's safe wrappers. During real-D64
// setup (mock_active == 0), delegate directly to KERNAL; afterwards (mock_active == $80),
// feed scripted byte-0 / byte-1 READST timeouts into disk_marker_present.
mock_active:     .byte 0
mock_lfn:        .byte 0
mock_pos:        .byte 0
mock_last_st:    .byte 0
mock_chrin_vals: .fill 32, 0
mock_readst_vals:.fill 32, 0

w_readst:
    bit mock_active
    bmi !mock+
    jmp KERNAL_READST
!mock:
    lda mock_last_st
    rts

w_setlfs:
    bit mock_active
    bmi !mock+
    jmp KERNAL_SETLFS
!mock:
    sta mock_lfn
    rts

w_setnam:
    bit mock_active
    bmi !mock+
    jmp KERNAL_SETNAM
!mock:
    rts

w_open:
    bit mock_active
    bmi !mock+
    jmp KERNAL_OPEN
!mock:
    lda #0
    sta mock_last_st
    clc
    rts

w_close:
    bit mock_active
    bmi !mock+
    jmp KERNAL_CLOSE
!mock:
    clc
    rts

w_chkin:
    bit mock_active
    bmi !mock+
    jmp KERNAL_CHKIN
!mock:
    clc
    rts

w_chkout:
    jmp KERNAL_CHKOUT

w_clrchn:
    bit mock_active
    bmi !mock+
    jmp KERNAL_CLRCHN
!mock:
    rts

w_chrin:
    bit mock_active
    bmi !mock+
    jmp KERNAL_CHRIN
!mock:
    ldx mock_pos
    lda mock_readst_vals,x
    sta mock_last_st
    lda mock_chrin_vals,x
    inc mock_pos
    clc
    rts

w_chrout:
    jmp KERNAL_CHROUT

screen_put_string:
.label hal_screen_put_string = screen_put_string
screen_clear_row:
.label hal_screen_clear_row = screen_clear_row
ui_clear_full_screen_safe:
msg_init:
input_prepare_modal_dismiss_key:
.label hal_input_modal_prepare = input_prepare_modal_dismiss_key
input_get_modal_dismiss_key:
c128_require_program_media:
tramp_disk_setup_ui_action:
save_game:
load_game:
save_stream_status:
load_stream_status:
    rts

save_file_exists:
    clc
    rts

c128_media_state: .byte C128_MEDIA_UNKNOWN

ds_save_str:
    .text "SAVE DISK" ; .byte 0
ds_game_str:
    .text "PROGRAM DISK" ; .byte 0
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

test_start:
    lda #$05
    sta $d506
    lda #$0e
    sta $ff00
    lda #$2f
    sta $00
    lda #$36
    sta $01
    cli
    lda #9
    sta save_device
    sta disk_prompt_device
    lda #2
    sta disk_mode

    jsr disk_init_drive
    bcs test_fail
    jsr disk_marker_init
    bcs test_fail
    jsr disk_marker_present
    bcs test_fail
    jsr disk_setup_commit_initialized
    bcs test_fail

    // Phase 2: exercise disk_marker_present byte-0 and byte-1 ST=$02 retries
    // and exhaustion using the real compiled inline marker reader.
    jsr patch_kernal_mocks
    lda #$80
    sta mock_active

    // Case 1: byte-0 ST=$02 ('X', ST=$02) -> retry -> "00" + "M8SAVE"
    ldx #0
    jsr load_mock_byte0_retry
    jsr disk_marker_present
    bcs test_fail
    lda disk_status
    bne test_fail
    lda dmp_tries
    cmp #2
    bne test_fail

    // Case 2: byte-1 ST=$02 ('6', ST=0, '2', ST=$02) -> retry -> "00" + "M8SAVE"
    jsr load_mock_byte1_retry
    jsr disk_marker_present
    bcs test_fail
    lda disk_status
    bne test_fail
    lda dmp_tries
    cmp #2
    bne test_fail

    // Case 3: byte-1 ST=$02 exhaustion (3x '6', ST=0, '2', ST=$02) -> C=1, $81, dos1=$ff
    jsr load_mock_byte1_exhaust
    jsr disk_marker_present
    bcc test_fail
    lda disk_status
    cmp #$81
    bne test_fail
    lda disk_diag_cmd_status1
    cmp #$ff
    bne test_fail

test_pass:
    jmp test_pass

test_fail:
    jmp test_fail

.macro PatchKernalVec(kaddr, handler) {
    lda #$4c
    sta kaddr
    lda #<handler
    sta kaddr + 1
    lda #>handler
    sta kaddr + 2
}

patch_kernal_mocks:
    sei
    lda #$3e
    sta $ff00
    :PatchKernalVec(KERNAL_READST, w_readst)
    :PatchKernalVec(KERNAL_SETLFS, w_setlfs)
    :PatchKernalVec(KERNAL_SETNAM, w_setnam)
    :PatchKernalVec(KERNAL_OPEN, w_open)
    :PatchKernalVec(KERNAL_CLOSE, w_close)
    :PatchKernalVec(KERNAL_CHKIN, w_chkin)
    :PatchKernalVec(KERNAL_CLRCHN, w_clrchn)
    :PatchKernalVec(KERNAL_CHRIN, w_chrin)
    rts

load_mock_byte0_retry:
    lda #0
    sta mock_pos
    sta mock_last_st
    // Try 1: 'X' (ST=$02); Try 2: '0','0' (ST=0) + "M8SAVE" (last byte ST=$40)
    lda #$58 ; sta mock_chrin_vals+0
    lda #$02 ; sta mock_readst_vals+0
    jmp load_mock_valid_tail

load_mock_byte1_retry:
    lda #0
    sta mock_pos
    sta mock_last_st
    // Try 1: '6' (ST=0), '2' (ST=$02); Try 2: '0','0' + "M8SAVE"
    lda #$36 ; sta mock_chrin_vals+0
    lda #$00 ; sta mock_readst_vals+0
    lda #$32 ; sta mock_chrin_vals+1
    lda #$02 ; sta mock_readst_vals+1
    ldx #2
    bne load_mock_valid_at_x

load_mock_valid_tail:
    ldx #1
load_mock_valid_at_x:
    lda #$30 ; sta mock_chrin_vals,x ; sta mock_chrin_vals+1,x
    lda #$00 ; sta mock_readst_vals,x ; sta mock_readst_vals+1,x
    ldy #0
!mcopy:
    lda hal_storage_marker_magic,y
    sta mock_chrin_vals+2,x
    lda #0
    cpy #hal_storage_marker_magic_len - 1
    bne !not_last+
    lda #$40
!not_last:
    sta mock_readst_vals+2,x
    inx
    iny
    cpy #hal_storage_marker_magic_len
    bcc !mcopy-
    rts

load_mock_byte1_exhaust:
    lda #0
    sta mock_pos
    sta mock_last_st
    ldx #0
!eloop:
    lda #$36 ; sta mock_chrin_vals,x
    lda #$00 ; sta mock_readst_vals,x
    lda #$32 ; sta mock_chrin_vals+1,x
    lda #$02 ; sta mock_readst_vals+1,x
    inx
    inx
    cpx #6
    bcc !eloop-
    rts

#import "../../common/disk_swap.s"
#import "../hal/storage.s"
#import "../../common/disk_setup_banked.s"
