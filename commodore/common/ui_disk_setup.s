#importonce
// ui_disk_setup.s — Guided Save Disk setup UI
//
// This overlay is display/input only. The FEAT-DISK coordinator and all disk
// transactions live outside the overlay and re-enter it fresh for each prompt.

#import "input_ui_helpers.s"

.encoding "screencode_mixed"

.macro UDSPrint(row, col, label) {
    lda #row
    sta zp_cursor_row
    lda #col
    sta zp_cursor_col
    lda #<label
    sta zp_ptr0
    lda #>label
    sta zp_ptr0_hi
    jsr hal_screen_put_string
}

uds_digits: .byte 0, 0
uds_count:  .byte 0
uds_device: .byte 0

.const UDS_TITLE_COL = (SCREEN_COLS - 10) / 2
.const UDS_LINE_COL  = (SCREEN_COLS - 24) / 2
.const UDS_NOTE_COL  = (SCREEN_COLS - 28) / 2
.const UDS_PROMPT_COL = (SCREEN_COLS - 19) / 2
.const UDS_DEVICE_PROMPT_COL = (SCREEN_COLS - 19) / 2
.const UDS_DEVICE_DIGIT_COL = UDS_DEVICE_PROMPT_COL + 19
.const UDS_IND_COL = (SCREEN_COLS - 10) / 2

ui_disk_setup_dispatch:
    lda #COL_WHITE
    sta zp_text_color
    lda disk_ui_action
    beq !dispatch_menu+
    cmp #DISK_UI_ACT_CONFIRM_DRIVE9
    beq !dispatch_confirm_drive9+
    cmp #DISK_UI_ACT_INSERT_DISK
    beq !dispatch_insert_disk+
    cmp #DISK_UI_ACT_INIT_PROMPT
    beq !dispatch_init_prompt+
    cmp #DISK_UI_ACT_SHOW_NO_DRIVE9
    beq !dispatch_no_drive9+
    cmp #DISK_UI_ACT_SHOW_NO_DEVICE
    beq !dispatch_no_device+
    cmp #DISK_UI_ACT_SHOW_PROGRAM
    beq !dispatch_program_disk+
    cmp #DISK_UI_ACT_SHOW_INIT_FAIL
    beq !dispatch_init_fail+
    cmp #DISK_UI_ACT_ENTER_DEVICE
#if C128
    beq !dispatch_enter_device+
#endif
    lda #DISK_UI_RES_CANCEL
    sta disk_ui_result
    rts

!dispatch_menu:
    jsr uds_menu_only
    jmp !dispatch_done+
!dispatch_confirm_drive9:
    jsr uds_confirm_drive9
    jmp !dispatch_done+
!dispatch_insert_disk:
    jsr uds_show_insert_prompt
    jmp !dispatch_done+
!dispatch_init_prompt:
    jsr uds_show_init_prompt
    jmp !dispatch_done+
!dispatch_no_drive9:
    jsr uds_show_no_drive9
    jmp !dispatch_done+
!dispatch_no_device:
    jsr uds_show_no_device
    jmp !dispatch_done+
!dispatch_program_disk:
    jsr uds_show_program_disk
    jmp !dispatch_done+
!dispatch_init_fail:
    jsr uds_show_init_fail
    jmp !dispatch_done+
#if C128
!dispatch_enter_device:
    jsr uds_enter_device
    jmp !dispatch_done+
#endif
!dispatch_done:
    rts

uds_menu_only:
    jsr ui_clear_full_screen_safe
    :UDSPrint(0, UDS_TITLE_COL, uds_title_str)
    :UDSPrint(2, UDS_LINE_COL, uds_menu_head_str)
    :UDSPrint(4, UDS_LINE_COL, uds_one_drive_str)
    :UDSPrint(5, UDS_LINE_COL, uds_two_drive_str)
#if C128
    :UDSPrint(6, UDS_LINE_COL, uds_other_drive_str)
    :UDSPrint(7, UDS_LINE_COL, uds_back_str)
    :UDSPrint(9, UDS_NOTE_COL, uds_note_str)
#else
    :UDSPrint(6, UDS_LINE_COL, uds_back_str)
    :UDSPrint(8, UDS_NOTE_COL, uds_note_str)
#endif
    lda disk_setup_done
    beq !menu_key+
    jsr uds_draw_current_indicator
!menu_key:
    jsr input_get_key
    cmp #$31                    // '1'
    bne !menu_not_one+
    lda #DISK_UI_RES_ONE_DRIVE
    sta disk_ui_result
    rts
!menu_not_one:
    cmp #$32                    // '2'
    bne !menu_not_two+
    lda #DISK_UI_RES_TWO_DRIVE
    sta disk_ui_result
    rts
!menu_not_two:
#if C128
    cmp #$4f                    // 'O'
    bne !menu_not_other+
    lda #DISK_UI_RES_OTHER_DRIVE
    sta disk_ui_result
    rts
!menu_not_other:
#endif
    cmp #$51                    // 'Q'
    bne !menu_key-
    lda #DISK_UI_RES_CANCEL
    sta disk_ui_result
    rts

uds_confirm_drive9:
    jsr ui_clear_full_screen_safe
    :UDSPrint(0, UDS_TITLE_COL, uds_title_str)
    :UDSPrint(3, UDS_LINE_COL, uds_drive9_hint_str)
    :UDSPrint(5, UDS_LINE_COL, uds_use_drive9_str)
!cfm_key:
    jsr input_get_modal_dismiss_key
    cmp #$59                    // 'Y'
    beq !cfm_yes+
    cmp #$4e                    // 'N'
    bne !cfm_key-
    lda #DISK_UI_RES_NO
    sta disk_ui_result
    jsr uds_clear_after_modal
    rts
!cfm_yes:
    lda #DISK_UI_RES_YES
    sta disk_ui_result
    jsr uds_clear_after_modal
    rts

uds_show_insert_prompt:
    jsr ui_clear_full_screen_safe
    :UDSPrint(0, UDS_TITLE_COL, uds_title_str)
    lda disk_mode
    cmp #1
    bne !prep_drive_msg+
    :UDSPrint(3, UDS_LINE_COL, uds_insert_one_drive_str)
    :UDSPrint(4, UDS_LINE_COL, uds_insert_drive8_str)
    jmp !prep_wait+
!prep_drive_msg:
    :UDSPrint(3, UDS_LINE_COL, uds_insert_other_drive_str)
    lda #4
    sta zp_cursor_row
    lda #UDS_IND_COL
    sta zp_cursor_col
    lda #<uds_drive_prefix_str
    sta zp_ptr0
    lda #>uds_drive_prefix_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda save_device
    jsr screen_put_decimal_rj2
    lda #$2e                    // '.'
    jsr hal_screen_put_char
!prep_wait:
    :UDSPrint(6, UDS_PROMPT_COL, press_key_str)
    jsr input_get_modal_dismiss_key
    lda #DISK_UI_RES_OK
    sta disk_ui_result
    jsr uds_clear_after_modal
    rts

uds_show_init_prompt:
    jsr ui_clear_full_screen_safe
    :UDSPrint(0, UDS_TITLE_COL, uds_title_str)
    :UDSPrint(3, UDS_LINE_COL, uds_no_marker_str)
    :UDSPrint(5, UDS_LINE_COL, uds_init_prompt_str)
!prep_init_key:
    jsr input_get_modal_dismiss_key
    cmp #$59                    // 'Y'
    beq !prep_init_yes+
    cmp #$4e                    // 'N'
    bne !prep_init_key-
    lda #DISK_UI_RES_NO
    sta disk_ui_result
    jsr uds_clear_after_modal
    rts
!prep_init_yes:
    lda #DISK_UI_RES_YES
    sta disk_ui_result
    jsr uds_clear_after_modal
    rts

uds_enter_device:
    jsr ui_clear_full_screen_safe
    :UDSPrint(0, UDS_TITLE_COL, uds_title_str)
    :UDSPrint(3, UDS_DEVICE_PROMPT_COL, uds_device_prompt_str)
    lda #0
    sta uds_count
!de_key:
    jsr input_get_modal_dismiss_key
    cmp #$51                    // 'Q'
    bne !de_not_q+
    jmp !de_cancel+
!de_not_q:
    cmp #$14                    // DEL
    bne !de_not_del+
    lda uds_count
    beq !de_key-
    dec uds_count
    lda uds_count
    clc
    adc #UDS_DEVICE_DIGIT_COL
    sta zp_cursor_col
    lda #3
    sta zp_cursor_row
    lda #$20
    jsr hal_screen_put_char
    jmp !de_key-
!de_not_del:
    cmp #$0d                    // RETURN
    bne !de_not_ret+
    lda uds_count
    beq !de_key-
    jmp !de_commit+
!de_not_ret:
    cmp #$30
    bcc !de_key-
    cmp #$3a
    bcs !de_key-
    ldx uds_count
    cpx #2
    bcs !de_key-
    sta uds_digits,x
    pha
    txa
    clc
    adc #UDS_DEVICE_DIGIT_COL
    sta zp_cursor_col
    lda #3
    sta zp_cursor_row
    pla
    jsr hal_screen_put_char
    inc uds_count
    jmp !de_key-

!de_commit:
    lda uds_count
    cmp #1
    beq !de_one_digit+
    lda uds_digits
    sec
    sbc #$30
    asl
    sta uds_device
    asl
    asl
    clc
    adc uds_device
    sta uds_device
    lda uds_digits+1
    sec
    sbc #$30
    clc
    adc uds_device
    sta uds_device
    jmp !de_validate+
!de_one_digit:
    lda uds_digits
    sec
    sbc #$30
    sta uds_device

!de_validate:
    lda uds_device
    cmp #8
    bcc !de_bad+
    cmp #31
    bcs !de_bad+
    lda #DISK_UI_RES_OK
    sta disk_ui_result
    sta disk_ui_value
    clc
    rts
!de_bad:
    jsr uds_show_no_device
    lda #DISK_UI_RES_CANCEL
    sta disk_ui_result
    sec
    rts

!de_cancel:
    lda #DISK_UI_RES_CANCEL
    sta disk_ui_result
    sec
    rts

uds_show_no_drive9:
    jsr ui_clear_full_screen_safe
    :UDSPrint(0, UDS_TITLE_COL, uds_title_str)
    :UDSPrint(3, UDS_LINE_COL, uds_no_drive9_str)
    :UDSPrint(5, UDS_PROMPT_COL, press_key_str)
    jsr input_get_modal_dismiss_key
    lda #DISK_UI_RES_CANCEL
    sta disk_ui_result
    jsr uds_clear_after_modal
    rts

uds_show_no_device:
    jsr ui_clear_full_screen_safe
    :UDSPrint(0, UDS_TITLE_COL, uds_title_str)
    :UDSPrint(3, UDS_LINE_COL, uds_no_device_str)
    :UDSPrint(5, UDS_PROMPT_COL, press_key_str)
    jsr input_get_modal_dismiss_key
    lda #DISK_UI_RES_CANCEL
    sta disk_ui_result
    jsr uds_clear_after_modal
    rts

uds_show_program_disk:
    jsr ui_clear_full_screen_safe
    :UDSPrint(0, UDS_TITLE_COL, uds_title_str)
    :UDSPrint(3, UDS_LINE_COL, uds_program_disk_str)
    :UDSPrint(5, UDS_PROMPT_COL, press_key_str)
    jsr input_get_modal_dismiss_key
    lda #DISK_UI_RES_CANCEL
    sta disk_ui_result
    jsr uds_clear_after_modal
    rts

uds_show_init_fail:
    jsr ui_clear_full_screen_safe
    :UDSPrint(0, UDS_TITLE_COL, uds_title_str)
    :UDSPrint(3, UDS_LINE_COL, uds_init_fail_str)
    jsr uds_show_init_detail
    :UDSPrint(6, UDS_PROMPT_COL, press_key_str)
    jsr input_get_modal_dismiss_key
    lda #DISK_UI_RES_CANCEL
    sta disk_ui_result
    jsr uds_clear_after_modal
    rts

uds_clear_after_modal:
    jsr ui_clear_full_screen_safe
    jmp msg_init

uds_show_init_detail:
    jsr hal_storage_setup_status
    cmp #HAL_STORAGE_STATUS_WRITE_PROTECTED
    bne !check_full+
    :UDSPrint(4, UDS_LINE_COL, uds_dos_write_protect_str)
    rts
!check_full:
    cmp #HAL_STORAGE_STATUS_DISK_FULL
    bne !check_ready+
    :UDSPrint(4, UDS_LINE_COL, uds_dos_full_str)
    rts
!check_ready:
    cmp #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    bne !fallback+
    :UDSPrint(4, UDS_LINE_COL, uds_dos_not_ready_str)
    rts
!fallback:
#if C128
    lda disk_diag_cmd_status0
    cmp #$ff
    beq !generic+
    cmp #$30
    bne !show_c128_status_error+
    lda disk_diag_cmd_status1
    cmp #$30
    bne !show_c128_status_error+
    jmp !generic+
!show_c128_status_error:
    jmp uds_show_c128_status_error
!generic:
#endif
#if PLUS4
    lda disk_error_dos0
    beq !check_phase+
    jmp uds_show_plus4_disk_error
!check_phase:
    lda disk_error_phase
    ora disk_error_readst
    beq !generic+
    jmp uds_show_plus4_status_error
!generic:
#endif
    :UDSPrint(4, UDS_LINE_COL, uds_dos_generic_str)
    rts

#if C128
uds_show_c128_status_error:
    lda #4
    sta zp_cursor_row
    lda #UDS_LINE_COL
    sta zp_cursor_col
    lda #<uds_disk_code_str
    sta zp_ptr0
    lda #>uds_disk_code_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda disk_diag_cmd_status0
    jsr hal_screen_put_char
    lda disk_diag_cmd_status1
    jsr hal_screen_put_char
    lda #<uds_phase_str
    sta zp_ptr0
    lda #>uds_phase_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda disk_diag_phase
    jsr screen_put_hex
    lda #$2e
    jsr hal_screen_put_char
    rts
#endif

#if PLUS4
uds_show_plus4_disk_error:
    lda #4
    sta zp_cursor_row
    lda #UDS_LINE_COL
    sta zp_cursor_col
    lda #<uds_disk_error_str
    sta zp_ptr0
    lda #>uds_disk_error_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda disk_error_dos0
    jsr hal_screen_put_char
    lda disk_error_dos1
    jsr hal_screen_put_char
    lda #<uds_on_drive_str
    sta zp_ptr0
    lda #>uds_on_drive_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda disk_error_device
    jsr screen_put_decimal_rj2
    lda #$2e
    jsr hal_screen_put_char
    rts

uds_show_plus4_status_error:
    lda #4
    sta zp_cursor_row
    lda #UDS_LINE_COL
    sta zp_cursor_col
    lda #<uds_disk_status_str
    sta zp_ptr0
    lda #>uds_disk_status_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda disk_error_readst
    jsr screen_put_hex
    lda #<uds_phase_str
    sta zp_ptr0
    lda #>uds_phase_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda disk_error_phase
    jsr screen_put_hex
    lda #$2e
    jsr hal_screen_put_char
    rts
#endif

uds_draw_current_indicator:
    lda #COL_CYAN
    sta zp_text_color
    lda #11
    sta zp_cursor_row
    lda #UDS_IND_COL
    sta zp_cursor_col
    lda #<ds_ind_pfx
    sta zp_ptr0
    lda #>ds_ind_pfx
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda save_device
    jsr screen_put_decimal_rj2
    lda #$1d
    jsr hal_screen_put_char
    lda #COL_WHITE
    sta zp_text_color
    rts

uds_title_str:             .text "Disk Setup" ; .byte 0
uds_menu_head_str:         .text "Choose your Save Disk" ; .byte 0
uds_one_drive_str:         .text "1) One drive" ; .byte 0
uds_two_drive_str:         .text "2) Two drives (9)" ; .byte 0
uds_other_drive_str:       .text "O) Other drive" ; .byte 0
uds_back_str:              .text "Q) Back" ; .byte 0
uds_note_str:              .text "Load, save, and scores use Save Disk." ; .byte 0
uds_drive9_hint_str:       .text "Drive 9 is ready for saves." ; .byte 0
uds_use_drive9_str:        .text "Use drive 9? (Y/N)" ; .byte 0
uds_no_drive9_str:         .text "Drive 9 did not respond." ; .byte 0
uds_insert_one_drive_str:  .text "Insert a separate Save Disk" ; .byte 0
uds_insert_drive8_str:     .text "in drive 8." ; .byte 0
uds_insert_other_drive_str:.text "Insert a Save Disk in" ; .byte 0
uds_drive_prefix_str:      .text "drive " ; .byte 0
uds_no_marker_str:         .text "No Save Disk marker found." ; .byte 0
uds_init_prompt_str:       .text "Initialize this disk? (Y/N)" ; .byte 0
uds_init_fail_str:         .text "Could not initialize disk." ; .byte 0
uds_dos_write_protect_str: .text "Disk is write-protected." ; .byte 0
uds_dos_full_str:          .text "Disk is full." ; .byte 0
uds_dos_not_ready_str:     .text "Drive is not ready." ; .byte 0
uds_dos_generic_str:       .text "Check the disk and try again." ; .byte 0
#if PLUS4
uds_disk_error_str:        .text "Disk error " ; .byte 0
uds_on_drive_str:          .text " on drive " ; .byte 0
#endif
#if C128
uds_disk_code_str:         .text "Disk code " ; .byte 0
#endif
#if PLUS4
uds_disk_status_str:       .text "Disk code $" ; .byte 0
#endif
#if C128
uds_phase_str:             .text " phase $" ; .byte 0
#endif
#if PLUS4
uds_phase_str:             .text " phase $" ; .byte 0
#endif
uds_device_prompt_str:     .text "Save drive (8-30): " ; .byte 0
uds_no_device_str:         .text "Drive not found." ; .byte 0
uds_program_disk_str:      .text "Program disk cannot hold saves." ; .byte 0
