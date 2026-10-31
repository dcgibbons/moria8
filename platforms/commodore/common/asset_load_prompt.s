#importonce
// asset_load_ask_for_disk — "Insert program disk", the file's name and
// "Press any key" on a cleared screen, then a key. Everything it uses is
// resident: the load that failed may be the one holding any other prompt.
.const ALR_PROMPT_ROW = 10
asset_load_ask_for_disk:
    lda #COL_WHITE
    sta zp_text_color
    jsr ui_clear_full_screen_safe   // not msg_init: the message history stays
    lda #ALR_PROMPT_ROW
    sta zp_cursor_row
    lda #(hal_layout_screen_cols - 19) / 2     // "Insert program disk"
    sta zp_cursor_col
    lda #<ds_game_str
    ldy #>ds_game_str
    jsr screen_put_string_ay
    inc zp_cursor_row
    lda #(hal_layout_screen_cols - 19) / 2   // the name below it: PETSCII capitals,
    sta zp_cursor_col                       // digits and '.' are the same glyphs
    lda alr_name_lo
    sta alq_char + 1
    lda alr_name_hi
    sta alq_char + 2
    // The index is alr_left: asset_load_retry gave up when it reached 0.
!alq_name:
    ldx alr_left                    // in memory: screen_put_char may clobber X
alq_char:
    lda $ffff,x                     // the name: patched above
    jsr screen_put_char
    inc alr_left
    lda alr_left
    cmp alr_len
    bcc !alq_name-
    inc zp_cursor_row
    lda #(hal_layout_screen_cols - 13) / 2     // "Press any key"
    sta zp_cursor_col
    lda #<press_key_str
    ldy #>press_key_str
    jsr screen_put_string_ay
    jmp input_get_modal_dismiss_key

