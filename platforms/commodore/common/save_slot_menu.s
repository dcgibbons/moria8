// save_slot_menu.s — transient save-slot selector UI

save_slot_scan_idx: .byte 0
save_slot_default_idx: .byte 0
save_slot_name_idx: .byte 0
save_slot_name_buf: .fill SAVE_SLOT_NAME_LEN, 0

.const SAVE_SLOT_READ_DIGIT_OFF = hal_storage_save_read_name_len - 4
.const SAVE_SLOT_WRITE_DIGIT_OFF = hal_storage_save_write_name_len - 4
.const SAVE_SLOT_READ_SUFFIX_OFF = SAVE_SLOT_READ_DIGIT_OFF + 1
.const SAVE_SLOT_WRITE_SUFFIX_OFF = SAVE_SLOT_WRITE_DIGIT_OFF + 1

.assert "Save read slot digit replaces suffix comma", SAVE_SLOT_READ_DIGIT_OFF, 10
.assert "Save write slot digit replaces suffix comma", SAVE_SLOT_WRITE_DIGIT_OFF, 11
.assert "Save probe filename tracks write filename without overwrite marker", hal_storage_save_probe_name_len, hal_storage_save_write_name_len - 1

#if C128
save_select_slot_prompt:
#else
save_select_slot_prompt_impl:
#endif
    jsr hal_screen_clear
    lda #COL_WHITE
    sta zp_text_color
    lda #SAVE_SLOT_TITLE_ROW
    sta zp_cursor_row
    lda #SAVE_SLOT_TITLE_COL
    sta zp_cursor_col
    lda #<save_slots_title_str
    ldy #>save_slots_title_str
    jsr save_slot_put_str

    lda save_slot_index
    sta save_slot_default_idx
    lda #0
    sta save_slot_scan_idx
!slot_loop:
    lda save_slot_scan_idx
    clc
    adc #SAVE_SLOT_FIRST_ROW
    sta zp_cursor_row
    lda #SAVE_SLOT_LINE_COL
    sta zp_cursor_col
    lda save_slot_scan_idx
    clc
    adc #$31
    jsr hal_screen_put_char
    lda #$29
    jsr hal_screen_put_char
    lda #$20
    jsr hal_screen_put_char
    lda save_slot_scan_idx
    cmp save_slot_default_idx
    bne !not_loaded+
    lda #$2a
    bne !put_marker+
!not_loaded:
    lda #$20
!put_marker:
    jsr hal_screen_put_char
    lda save_slot_scan_idx
    sta save_slot_index
    jsr save_slot_apply_name
    jsr save_slot_read_name
    bcc !empty+
    lda save_slot_name_buf
    beq !empty+
    jsr save_slot_put_name
    jmp !next+
!empty:
    lda #<save_slot_empty_str
    ldy #>save_slot_empty_str
    jsr save_slot_put_str
!next:
    inc save_slot_scan_idx
    lda save_slot_scan_idx
    cmp #SAVE_SLOT_COUNT
    bcc !slot_loop-

    lda #SAVE_SLOT_SELECT_ROW
    sta zp_cursor_row
    lda #SAVE_SLOT_PROMPT_COL
    sta zp_cursor_col
    lda #<save_slot_prompt_str
    ldy #>save_slot_prompt_str
    jsr save_slot_put_str
!key_loop:
    jsr hal_input_get_key
    cmp #$31
    bcc !key_loop-
    cmp #$35
    bcs !key_loop-
    sec
    sbc #$31
    sta save_slot_index
    jsr save_slot_apply_name
    jsr hal_screen_clear
    sec
    rts

save_slot_apply_name:
    lda save_slot_index
    beq !slot_one+
    clc
    adc #$31                // index 1 => "2"
    sta hal_storage_save_read_name + SAVE_SLOT_READ_DIGIT_OFF
    sta hal_storage_save_write_name + SAVE_SLOT_WRITE_DIGIT_OFF
    lda #$2c                // ","
    sta hal_storage_save_read_name + SAVE_SLOT_READ_SUFFIX_OFF
    sta hal_storage_save_read_name + SAVE_SLOT_READ_SUFFIX_OFF + 2
    sta hal_storage_save_write_name + SAVE_SLOT_WRITE_SUFFIX_OFF
    sta hal_storage_save_write_name + SAVE_SLOT_WRITE_SUFFIX_OFF + 2
    lda #$53                // "S"
    sta hal_storage_save_read_name + SAVE_SLOT_READ_SUFFIX_OFF + 1
    sta hal_storage_save_write_name + SAVE_SLOT_WRITE_SUFFIX_OFF + 1
    lda #$52                // "R"
    sta hal_storage_save_read_name + SAVE_SLOT_READ_SUFFIX_OFF + 3
    lda #$57                // "W"
    sta hal_storage_save_write_name + SAVE_SLOT_WRITE_SUFFIX_OFF + 3
    lda #hal_storage_save_read_name_len + 1
    sta load_open_read_len + 1
    sta save_file_exists_read_len + 1
    sta save_slot_read_name_len + 1
    lda #hal_storage_save_write_name_len + 1
#if HAL_STORAGE_SAVE_CONFIRM_OVERWRITE_PROBE
    sta save_confirm_write_len + 1
#else
    sta save_open_write_len + 1
#endif
    lda #hal_storage_save_probe_name_len + 1
#if HAL_STORAGE_SAVE_CONFIRM_OVERWRITE_PROBE
    sta save_confirm_probe_len + 1
#endif
    rts
!slot_one:
    lda #$2c                // ","
    sta hal_storage_save_read_name + SAVE_SLOT_READ_DIGIT_OFF
    sta hal_storage_save_read_name + SAVE_SLOT_READ_DIGIT_OFF + 2
    sta hal_storage_save_write_name + SAVE_SLOT_WRITE_DIGIT_OFF
    sta hal_storage_save_write_name + SAVE_SLOT_WRITE_DIGIT_OFF + 2
    lda #$53                // "S"
    sta hal_storage_save_read_name + SAVE_SLOT_READ_DIGIT_OFF + 1
    sta hal_storage_save_write_name + SAVE_SLOT_WRITE_DIGIT_OFF + 1
    lda #$52                // "R"
    sta hal_storage_save_read_name + SAVE_SLOT_READ_DIGIT_OFF + 3
    lda #$57                // "W"
    sta hal_storage_save_write_name + SAVE_SLOT_WRITE_DIGIT_OFF + 3
    lda #hal_storage_save_read_name_len
    sta load_open_read_len + 1
    sta save_file_exists_read_len + 1
    sta save_slot_read_name_len + 1
    lda #hal_storage_save_write_name_len
#if HAL_STORAGE_SAVE_CONFIRM_OVERWRITE_PROBE
    sta save_confirm_write_len + 1
#else
    sta save_open_write_len + 1
#endif
    lda #hal_storage_save_probe_name_len
#if HAL_STORAGE_SAVE_CONFIRM_OVERWRITE_PROBE
    sta save_confirm_probe_len + 1
#endif
    rts

save_slot_read_name:
save_slot_read_name_len:
    lda #hal_storage_save_read_name_len
    ldx #<hal_storage_save_read_name
    ldy #>hal_storage_save_read_name
    jsr SAVE_SETNAM
    lda #hal_storage_check_file_num
    ldx save_device
    ldy #hal_storage_check_sec_read
    jsr SAVE_SETLFS
    jsr SAVE_OPEN
    bcc !open_ok+
    clc
    bcc !cleanup+
!open_ok:
    ldx #hal_storage_check_file_num
    jsr SAVE_CHKIN
    bcc !read_magic+
    clc
    bcc !cleanup+
!read_magic:
    lda #0
    sta save_slot_name_idx
!magic_loop:
    jsr SAVE_CHRIN
    ldx save_slot_name_idx
    cmp save_magic,x
    beq !magic_ok+
    clc
    bcc !cleanup+
!magic_ok:
    inc save_slot_name_idx
    lda save_slot_name_idx
    cmp #SAVE_MAGIC_SIZE - 1
    bcc !magic_loop-
    jsr SAVE_CHRIN
    jsr save_version_supported
    bcs !version_ok+
    clc
    bcc !cleanup+
!version_ok:
    jsr SAVE_READST
#if HAL_STORAGE_MASK_CHRIN_WRITE_TIMEOUT_STATUS
    and #$fe
#endif
    beq !read_name+
    clc
    bcc !cleanup+
!read_name:
    lda #0
    sta save_slot_name_idx
!name_loop:
    jsr SAVE_CHRIN
    ldx save_slot_name_idx
    sta save_slot_name_buf,x
    inc save_slot_name_idx
    lda save_slot_name_idx
    cmp #SAVE_SLOT_NAME_LEN
    bcc !name_loop-
    jsr SAVE_READST
#if HAL_STORAGE_MASK_CHRIN_WRITE_TIMEOUT_STATUS
    and #$fe
#endif
    beq !name_ok+
    clc
    bcc !cleanup+
!name_ok:
    sec
!cleanup:
    php
    lda #hal_storage_check_file_num
    jsr SAVE_CLOSE
    jsr save_restore_channels
    jsr hal_storage_read_command_status
#if HAL_STORAGE_RESTORE_VIC_BANK_AFTER_SAVE_PROBE
    lda hal_memory_vic_bank_select
    ora #hal_memory_vic_bank0_mask
    sta hal_memory_vic_bank_select
#endif
    plp
    rts

save_slot_put_name:
    ldx #0
!name_loop:
    lda save_slot_name_buf,x
    beq !done+
    jsr hal_screen_put_char
    inx
    cpx #SAVE_SLOT_NAME_LEN
    bcc !name_loop-
!done:
    rts

save_slot_put_str:
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #0
    sta save_slot_name_idx
!str_loop:
    ldy save_slot_name_idx
    lda (zp_ptr0),y
    beq !done+
    jsr hal_screen_put_char
    inc save_slot_name_idx
    bne !str_loop-
!done:
    rts

#if C128
save_slots_title_str:
    .text "Save Slots:"
    .byte 0
save_slot_empty_str:
    .text "Empty"
    .byte 0
save_slot_prompt_str:
    .text "Select Slot 1-4"
    .byte 0
#else
save_slots_title_str:
    .byte $53,$01,$16,$05,$20,$53,$0c,$0f,$14,$13,$3a,0
save_slot_empty_str:
    .byte $45,$0d,$10,$14,$19,0
save_slot_prompt_str:
    .byte $53,$05,$0c,$05,$03,$14,$20,$53,$0c,$0f,$14,$20,$31,$2d,$34,0
#endif
