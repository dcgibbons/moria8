#importonce
// Legal viewer. Owner: uncached LegalOverlay in the ordinary overlay window
// (X16: temporary Bank 23). Lifetime: one title/Help modal. Resident entry
// restores the caller's bank; Help reloads its owner after this window is used.
// State, input cache and core-ZP snapshot never borrow game data.

.const LEGAL_LFN = 8
.label legal_input_cache = LEGAL_BASE + $700
.assert "Legal workspace fits overlay window", legal_input_cache + $100 <= LEGAL_LIMIT, true

legal_viewer:
    // Entry and exit share the same live-sound/redraw preservation policy.
    jsr legal_restore_zp
    lda #0
    sta legal_opened
legal_menu:
    jsr legal_stream_close
    jsr hal_screen_clear
    lda #COL_WHITE
    sta zp_text_color
    lda #1
    sta zp_cursor_col
    lda #1
    sta zp_cursor_row
    lda #<legal_heading
    ldy #>legal_heading
    jsr screen_put_string_ay
    lda #3
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<legal_copyright
    ldy #>legal_copyright
    jsr screen_put_string_ay
    lda #5
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<legal_rights
    ldy #>legal_rights
    jsr screen_put_string_ay
    lda #6
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<legal_warranty
    ldy #>legal_warranty
    jsr screen_put_string_ay
    lda #8
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<legal_choices
    ldy #>legal_choices
    jsr screen_put_string_ay
legal_menu_wait:
    jsr legal_key
    cmp #$31
    bne !source+
    lda #0
    beq !select+
!source:
    cmp #$32
    bne !exit+
    lda #1
!select:
    sta legal_document
    jmp legal_document_start
!exit:
    cmp #$51
    beq legal_return
    jsr input_is_modal_escape_key
    bne legal_menu_wait
legal_return:
    jsr legal_stream_close
    jmp legal_restore_zp

legal_restore_zp:
    :LegalRestore()
    rts

legal_document_start:
    lda #0
    sta legal_previous_cr
    sta legal_pending_valid
    jsr legal_stream_close
    jsr legal_stream_open
    bcc !opened+
    jmp legal_read_error
!opened:
legal_page_begin:
    jsr hal_screen_clear
    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<legal_heading
    ldy #>legal_heading
    jsr screen_put_string_ay
    lda #2
    sta legal_row
    lda #1
    sta legal_column
!render:
    lda legal_pending_valid
    beq !read_stream+
    lda #0
    sta legal_pending_valid
    lda legal_pending
    jmp !read+
!read_stream:
    jsr legal_read_character
    bcc !read+
    lda legal_eof
    cmp #$40
    beq !end+
    jmp legal_read_error
!end:
    lda #1
    sta legal_page_is_end
    lda #<legal_end_footer
    ldy #>legal_end_footer
    jmp legal_page_footer
!read:
    sta legal_pending
    cmp #$0d
    bne !print+
    lda legal_row
    cmp #SCREEN_ROWS - 2
    bcs !page_full+
    inc legal_row
    lda #1
    sta legal_column
    jmp !render-
!page_full:
    lda #1
    sta legal_pending_valid
    lda #0
    sta legal_page_is_end
    lda #<legal_more_footer
    ldy #>legal_more_footer
    jmp legal_page_footer
!print:
    pha
    lda legal_column
    cmp #SCREEN_COLS
    bcc !column_ready+
    inc legal_row
    lda #1
    sta legal_column
!column_ready:
    pla
    ldx legal_row
    cpx #SCREEN_ROWS - 2
    bcs !page_full-
    // Shared screen codes use lowercase 1..26 and uppercase $41..$5A.
    cmp #$61
    bcc !punctuation+
    cmp #$7b
    bcs !punctuation+
    sec
    sbc #$60
    jmp !draw+
!punctuation:
    cmp #$40
    bne !bracket+
    lda #0
    beq !draw+
!bracket:
    cmp #$5b
    bcc !draw+
    cmp #$60
    bcs !draw+
    and #$3f
!draw:
    pha
    lda legal_row
    sta zp_cursor_row
    lda legal_column
    sta zp_cursor_col
    pla
    jsr hal_screen_put_char
    inc legal_column
    jmp !render-

legal_read_error:
    jsr legal_stream_close
    jsr hal_screen_clear
    lda #COL_WHITE
    sta zp_text_color
    lda #2
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<legal_error_text
    ldy #>legal_error_text
    jsr screen_put_string_ay
    jsr legal_key
    jmp legal_menu

legal_page_footer:
    pha
    lda #SCREEN_ROWS - 1
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    pla
    jsr screen_put_string_ay
legal_page_wait:
    jsr legal_key
    cmp #$51
    beq !menu+
    jsr input_is_modal_escape_key
    beq !menu+
    cmp #$52
    bne !next+
    jmp legal_document_start
!next:
    cmp #$20
    beq !advance+
    cmp #$0d
    bne legal_page_wait
!advance:
    lda legal_page_is_end
    bne !menu+
    jmp legal_page_begin
!menu:
    jmp legal_menu

// Normalize EOL once, before caching a pending character across pages.
// A CRLF pair is one newline, including when it crosses a stream chunk.
legal_read_character:
!next:
    jsr legal_stream_read
    bcs !done+
    tax
    lda legal_previous_cr
    sta legal_was_cr
    lda #0
    sta legal_previous_cr
    txa
    cmp #$0a
    bne !cr+
    ldx legal_was_cr
    bne !next-
    beq !newline+
!cr:
    cmp #$0d
    bne !atari+
    inc legal_previous_cr
    bne !newline+
!atari:
    cmp #$9b
    beq !newline+
    cmp #$20
    bcc !next-
    clc
    rts
!newline:
    lda #$0d
    clc
!done:
    rts

legal_key:
    jsr legal_stream_pause
    jsr input_prepare_modal_dismiss_key
    jmp hal_input_get_key

legal_previous_cr: .byte 0
legal_was_cr: .byte 0
legal_pending: .byte 0
legal_pending_valid: .byte 0
legal_page_is_end: .byte 0
legal_document: .byte 0
legal_opened: .byte 0
legal_selected: .byte 0
legal_eof: .byte 0
legal_row: .byte 0
legal_column: .byte 0
.encoding "screencode_mixed"
legal_heading: .text "License & Source"; .byte 0
legal_copyright: .text "Copyright (C) 2026 Chad Gibbons"; .byte 0
legal_rights: .text "You may modify and redistribute."; .byte 0
legal_warranty: .text "GPLv3 or later. No warranty."; .byte 0
legal_choices: .text "1 License  2 Source Offer  Q Back"; .byte 0
legal_more_footer: .text "Space: next  R: restart  Q: back"; .byte 0
legal_end_footer: .text "End. R: restart  Q: back"; .byte 0
legal_error_text: .text "Document read failed. Press any key."; .byte 0
