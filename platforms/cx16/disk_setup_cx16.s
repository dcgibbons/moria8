#importonce
// disk_setup_cx16.s — Commander X16 Disk Setup UI (OVL.STORAGE).
//
// Uses the same menu layout and "Save drive (8-11): " picker flow as the
// Commodore ports (core/ui_disk_setup.s):
//   Row 0: "Disk Setup"
//   Row 2: "Program:  8" (COL_CYAN)
//   Row 3: "Save:     8" (COL_CYAN)
//   Row 5: "1) Same as program"
//   Row 6: "2) Pick save drive" -> "Save drive (8-11): "
//   Row 7: "3) Done"
//   Row 8: "Q) Back"

.const CX16DS_TITLE_COL         = (SCREEN_COLS - 10) / 2
.const CX16DS_LINE_COL          = (SCREEN_COLS - 24) / 2
.const CX16DS_PROMPT_COL        = (SCREEN_COLS - 19) / 2
.const CX16DS_DEVICE_PROMPT_COL = (SCREEN_COLS - 19) / 2
.const CX16DS_DEVICE_DIGIT_COL  = CX16DS_DEVICE_PROMPT_COL + 19

cx16ds_digits: .byte 0, 0
cx16ds_count:  .byte 0
cx16ds_device: .byte 0

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

cx16ds_draw_drive_summary:
    lda #COL_CYAN
    sta zp_text_color
    :Cx16DSPrint(2, CX16DS_LINE_COL, cx16ds_prog_str)
    lda program_device
    jsr screen_put_decimal_rj2
    :Cx16DSPrint(3, CX16DS_LINE_COL, cx16ds_save_str)
    lda save_device
    jsr screen_put_decimal_rj2
    lda #$20
    jsr hal_screen_put_char
    lda #COL_WHITE
    sta zp_text_color
    rts

cx16_disk_setup_run:
    lda save_device
    bne !menu+
    lda program_device
    sta save_device
!menu:
    jsr ui_clear_full_screen_safe
    lda #COL_WHITE
    sta zp_text_color
    :Cx16DSPrint(0, CX16DS_TITLE_COL, cx16ds_title_str)
    jsr cx16ds_draw_drive_summary
    :Cx16DSPrint(5, CX16DS_LINE_COL, cx16ds_one_drive_str)
    :Cx16DSPrint(6, CX16DS_LINE_COL, cx16ds_two_drive_str)
    :Cx16DSPrint(7, CX16DS_LINE_COL, cx16ds_done_str)
    :Cx16DSPrint(8, CX16DS_LINE_COL, cx16ds_back_str)
!key:
    jsr hal_input_get_key
    cmp #$31                // '1' -> Same as program
    bne !not1+
    lda program_device
    sta save_device
    lda #1
    sta disk_mode
    jmp !menu-
!not1:
    cmp #$32                // '2' -> Pick save drive
    bne !not2+
    jsr cx16ds_enter_device
    bcs !menu-
    lda cx16ds_device
    sta save_device
    lda #2
    sta disk_mode
    jmp !menu-
!not2:
    cmp #$33                // '3' -> Done
    bne !not3+
    jmp cx16_disk_prepare_selected
!not3:
    cmp #$51                // 'Q' -> Back
    bne !key-
    sec
    rts

cx16ds_enter_device:
    jsr ui_clear_full_screen_safe
    lda #COL_WHITE
    sta zp_text_color
    :Cx16DSPrint(0, CX16DS_TITLE_COL, cx16ds_title_str)
    :Cx16DSPrint(3, CX16DS_DEVICE_PROMPT_COL, cx16ds_device_prompt_str)
    stz cx16ds_count
!de_key:
    jsr input_get_modal_dismiss_key
    cmp #$51                // 'Q'
    bne !de_not_q+
    sec
    rts
!de_not_q:
    cmp #$14                // DEL
    bne !de_not_del+
    lda cx16ds_count
    beq !de_key-
    dec cx16ds_count
    lda cx16ds_count
    clc
    adc #CX16DS_DEVICE_DIGIT_COL
    sta zp_cursor_col
    lda #3
    sta zp_cursor_row
    lda #$20
    jsr hal_screen_put_char
    bra !de_key-
!de_not_del:
    cmp #$0d                // RETURN
    bne !de_not_ret+
    lda cx16ds_count
    beq !de_key-
    bra !de_commit+
!de_not_ret:
    cmp #$30
    bcc !de_key-
    cmp #$3a
    bcs !de_key-
    ldx cx16ds_count
    cpx #2
    bcs !de_key-
    sta cx16ds_digits,x
    pha
    txa
    clc
    adc #CX16DS_DEVICE_DIGIT_COL
    sta zp_cursor_col
    lda #3
    sta zp_cursor_row
    pla
    jsr hal_screen_put_char
    inc cx16ds_count
    bra !de_key-

!de_commit:
    lda cx16ds_count
    cmp #1
    beq !de_one_digit+
    lda cx16ds_digits
    sec
    sbc #$30
    asl
    sta cx16ds_device
    asl
    asl
    clc
    adc cx16ds_device
    sta cx16ds_device
    lda cx16ds_digits + 1
    sec
    sbc #$30
    clc
    adc cx16ds_device
    sta cx16ds_device
    bra !de_validate+
!de_one_digit:
    lda cx16ds_digits
    sec
    sbc #$30
    sta cx16ds_device

!de_validate:
    lda cx16ds_device
    cmp #8
    bcc !de_bad+
    cmp #12
    bcs !de_bad+
    clc
    rts
!de_bad:
    jsr ui_clear_full_screen_safe
    :Cx16DSPrint(0, CX16DS_TITLE_COL, cx16ds_title_str)
    :Cx16DSPrint(3, CX16DS_LINE_COL, cx16ds_no_device_str)
    :Cx16DSPrint(5, CX16DS_PROMPT_COL, press_key_str)
    jsr input_get_modal_dismiss_key
!de_cancel:
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

cx16ds_title_str:         .text "Disk Setup" ; .byte 0
cx16ds_prog_str:          .text "Program: " ; .byte 0
cx16ds_save_str:          .text "Save:    " ; .byte 0
cx16ds_one_drive_str:     .text "1) Same as program" ; .byte 0
cx16ds_two_drive_str:     .text "2) Pick save drive" ; .byte 0
cx16ds_done_str:          .text "3) Done" ; .byte 0
cx16ds_back_str:          .text "Q) Back" ; .byte 0
cx16ds_device_prompt_str: .text "Save drive (8-11): " ; .byte 0
cx16ds_no_device_str:     .text "Drive not found." ; .byte 0
