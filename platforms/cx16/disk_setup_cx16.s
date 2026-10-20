#importonce
// disk_setup_cx16.s — Commander X16 Disk Setup UI (OVL.STORAGE).
//
// On Commander X16, Device 8 (SD card / HostFS) is ready for saves by default
// at boot (disk_setup_done = 1, save_device = 8). The Disk Setup screen ('D'
// on the title menu) lets the player switch save_device between Device 8 and
// Device 9 or confirm the active save device.

.const CX16DS_TITLE_COL = (SCREEN_COLS - 10) / 2
.const CX16DS_LINE_COL  = (SCREEN_COLS - 28) / 2

.macro Cx16DSPrint(row, col, label) {
    ldx #row
    ldy #col
    lda #<label
    sta zp_ptr0
    lda #>label
    jsr cx16ds_print_loaded
}

cx16ds_print_loaded:
    sta zp_ptr0_hi
    stx zp_cursor_row
    sty zp_cursor_col
    jmp hal_screen_put_string

cx16_disk_setup_run:
    lda save_device
    bne !menu+
    lda #8
    sta save_device
!menu:
    jsr ui_clear_full_screen_safe
    lda #COL_WHITE
    sta zp_text_color
    :Cx16DSPrint(0, CX16DS_TITLE_COL, cx16ds_title_str)
    :Cx16DSPrint(2, CX16DS_LINE_COL, cx16ds_prog_str)
    lda program_device
    jsr screen_put_decimal
    :Cx16DSPrint(3, CX16DS_LINE_COL, cx16ds_save_str)
    lda save_device
    jsr screen_put_decimal
    :Cx16DSPrint(5, CX16DS_LINE_COL, cx16ds_dev8_str)
    :Cx16DSPrint(6, CX16DS_LINE_COL, cx16ds_dev9_str)
    :Cx16DSPrint(7, CX16DS_LINE_COL, cx16ds_dev10_str)
    :Cx16DSPrint(8, CX16DS_LINE_COL, cx16ds_dev11_str)
    :Cx16DSPrint(9, CX16DS_LINE_COL, cx16ds_done_str)
    :Cx16DSPrint(10, CX16DS_LINE_COL, cx16ds_back_str)
!key:
    jsr hal_input_get_key
    cmp #$31                // '1' -> Device 8
    bne !not1+
    lda #8
    sta save_device
    jmp !menu-
!not1:
    cmp #$32                // '2' -> Device 9
    bne !not2+
    lda #9
    sta save_device
    jmp !menu-
!not2:
    cmp #$33                // '3' -> Device 10
    bne !not3+
    lda #10
    sta save_device
    jmp !menu-
!not3:
    cmp #$34                // '4' -> Device 11
    bne !not4+
    lda #11
    sta save_device
    jmp !menu-
!not4:
    cmp #$35                // '5' -> Done
    bne !not5+
    jmp cx16_disk_prepare_selected
!not5:
    cmp #$51                // 'Q' -> Back
    bne !key-
    sec
    rts

cx16_disk_prepare_selected:
    lda save_device
    bne !ok+
    lda #8
    sta save_device
!ok:
    lda #hal_storage_disk_setup_done_value
    sta disk_setup_done
    clc
    rts

cx16ds_title_str:
    .text "Disk Setup" ; .byte 0
cx16ds_prog_str:
    .text "Program Device: #" ; .byte 0
cx16ds_save_str:
    .text "Save Device:    #" ; .byte 0
cx16ds_dev8_str:
    .text "1) Use Device 8 (SD/HostFS)" ; .byte 0
cx16ds_dev9_str:
    .text "2) Use Device 9" ; .byte 0
cx16ds_dev10_str:
    .text "3) Use Device 10" ; .byte 0
cx16ds_dev11_str:
    .text "4) Use Device 11" ; .byte 0
cx16ds_done_str:
    .text "5) Done" ; .byte 0
cx16ds_back_str:
    .text "Q) Back" ; .byte 0
