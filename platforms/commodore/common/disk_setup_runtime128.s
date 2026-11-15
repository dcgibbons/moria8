#importonce
// disk_setup_runtime128.s — C128 FEAT-DISK coordinator and title/save entry
// points in Bank 0 Default resident RAM (< $AF00, safely clear of $AF00-$CFFF
// persist/play overlays and ROM-shadowed regions during KERNAL calls).

tramp_disk_setup_ui_action:
    jmp ui_disk_setup_dispatch

tramp_disk_setup:
    jsr c128_modal_require_persist
    lda #0
    sta disk_ui_value
    jsr tramp_ui_enter
    jsr disk_setup_run
    php
    jsr tramp_ui_exit
    plp
    rts

tramp_disk_prepare_selected:
    jsr c128_modal_require_persist
    jsr tramp_ui_enter
    jsr disk_setup_prepare_selected
    php
    jsr tramp_ui_exit
    plp
    rts

title_require_disk_setup:
    lda disk_setup_done
    bne !trds_ready+
    jmp tramp_disk_setup
!trds_ready:
    clc
    rts

.segment Default
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

.segment Default
    #import "disk_setup_banked.s"
