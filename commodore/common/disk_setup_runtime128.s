#importonce
// disk_setup_runtime128.s — C128 FEAT-DISK coordinator and title/save entry
// points loaded into the dedicated disk-I/O runtime below ROM-shadowed regions
// so title-time disk setup is callable regardless of the current C128 banking state.

#if C128
tramp_disk_setup_ui_action:
    lda #C128_HELP_OVERLAY_ID
    jsr overlay_load
    bcs !tdsua_fail+
    jsr ui_disk_setup_dispatch
    rts
!tdsua_fail:
    lda #1
    sta disk_ui_result
    sec
    rts

tramp_disk_setup:
    lda #1
    sta disk_ui_result
    lda #0
    sta disk_ui_value
    jsr tramp_ui_enter
    jsr disk_setup_run
!tds_done:
    jsr tramp_ui_exit
    lda disk_ui_result
    beq !tds_ok+
    sec
    rts
!tds_ok:
    clc
    rts

title_require_disk_setup:
    lda disk_setup_done
    bne !trds_ready+
    jsr tramp_disk_setup
    bcs !trds_done+
    clc
    rts
!trds_done:
    rts
!trds_ready:
    clc
    rts

title_draw_save_disk_indicator:
    lda #STATUS_ROW
    jsr hal_screen_clear_row
    lda #STATUS_ROW + 1
    jsr hal_screen_clear_row
    lda #COL_CYAN
    sta zp_text_color
    lda #STATUS_ROW
    sta zp_cursor_row
    lda #SAVE_DISK_IND_COL
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

    #import "disk_setup_banked.s"
#endif
