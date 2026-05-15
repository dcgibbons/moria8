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

#import "../../common/zeropage.s"
#import "../../common/io_kernal_consts.s"
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

// C128 storage-drive helpers call the product's safe wrappers. In this minimal
// KERNAL-visible test payload, direct jump-table calls are sufficient.
w_readst:
    jmp KERNAL_READST
w_setlfs:
    jmp KERNAL_SETLFS
w_setnam:
    jmp KERNAL_SETNAM
w_open:
    jmp KERNAL_OPEN
w_close:
    jmp KERNAL_CLOSE
w_chkin:
    jmp KERNAL_CHKIN
w_chkout:
    jmp KERNAL_CHKOUT
w_clrchn:
    jmp KERNAL_CLRCHN
w_chrin:
    jmp KERNAL_CHRIN
w_chrout:
    jmp KERNAL_CHROUT

screen_put_string:
.label hal_screen_put_string = screen_put_string
screen_clear_row:
.label hal_screen_clear_row = screen_clear_row
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

test_pass:
    jmp test_pass

test_fail:
    jmp test_fail

#import "../../common/disk_swap.s"
#import "../hal/storage.s"
#import "../../common/disk_setup_banked.s"
