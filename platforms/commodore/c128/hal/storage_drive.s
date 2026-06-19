#importonce
// C128 platform-owned drive probing and media-change init helpers.

// Check whether an IEC device responds.
// Input: X = device number (8-30)
// Output: carry clear = present, carry set = absent/unusable
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
