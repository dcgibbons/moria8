#importonce
// C128 platform-owned drive probing and media-change init helpers.

// Check whether an IEC device responds.
// Input: X = device number (8-30)
// Output: carry clear = present, carry set = absent/unusable
hal_storage_probe_media:
    stx disk_temp
    jsr w_clrchn
    lda #0
    tax
    tay
    jsr w_setnam
    lda #hal_storage_cmd_channel
    ldx disk_temp
    ldy #hal_storage_cmd_channel
    jsr w_setlfs
    jsr w_open
    bcs !absent+
    ldx #hal_storage_cmd_channel
    jsr w_chkin
    bcc !read_st+
    lda #1
    bne !have_res+
!read_st:
    jsr w_readst
!have_res:
    pha
    jsr w_clrchn
    lda #hal_storage_cmd_channel
    jsr w_close
    pla
    cmp #1
    rts
!absent:
    sec
    rts

// Best-effort drive init for the selected prompt device.
// Output: carry clear = drive reported OK, carry set = init/status failure.
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
    bcs !fail_open+
    lda #hal_storage_cmd_channel
    jsr w_close
    jsr w_clrchn
    jsr c128_storage_read_command_status
    jsr disk_command_status
    cmp #HAL_STORAGE_STATUS_OK
    beq !ok+
    jsr disk_error_capture_c128
    sec
    rts
!fail_open:
    lda #74
    sta disk_status
    jsr w_clrchn
    sec
    rts
!ok:
    lda #0
    sta disk_status
    clc
    rts
