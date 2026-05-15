#importonce
// ui_messages.s — Message line management
//
// Top of screen (rows 0-1) displays game messages.
// Two-line message area reduces -MORE- frequency:
// messages fill row 0 then row 1, -MORE- only when
// a 3rd message arrives while both rows are occupied.
// Message history buffer holds last 8 messages.
//
// Messages are screen-code strings, null-terminated.

#import "platform_services_api.s"

// Message flags (zp_msg_flags)
.const MSG_PENDING   = $01  // Row 0 has an unread message
.const MSG_FULL      = $02  // Row 1 also has an unread message (both rows occupied)

// History buffer (8 messages x screen width chars max each)
.const MSG_HIST_COUNT = 8
.const MSG_HIST_LEN   = SCREEN_COLS
.const MSG_HIST_BYTES = MSG_HIST_COUNT * MSG_HIST_LEN
.const MSG_MORE_LEN = 7
.const MSG_MORE_MAX_COL = SCREEN_COLS - MSG_MORE_LEN
.const MSG_MORE_OVERFLOW_CMP = MSG_MORE_MAX_COL + 1
msg_history:
    .fill MSG_HIST_COUNT * MSG_HIST_LEN, 0
msg_hist_idx:
    .byte 0                 // Current write index (0–7, wraps)
msg_hist_ptr_lo:
    .byte <msg_history      // Current write pointer (lo)
msg_hist_ptr_hi:
    .byte >msg_history      // Current write pointer (hi)
msg_row1_col:
    .byte 0                 // Cursor column after printing on row 1
msg_src_lo:
    .byte 0                 // Stable copy of source string pointer (lo)
msg_src_hi:
    .byte 0                 // Stable copy of source string pointer (hi)

// ============================================================
// Subroutines
// ============================================================

// msg_init — Clear message system
msg_init:
    lda #0
    sta zp_msg_flags
    sta msg_hist_idx
    sta msg_row1_col
    lda #<msg_history
    sta msg_hist_ptr_lo
    lda #>msg_history
    sta msg_hist_ptr_hi
    lda #$20                // Space (screen code)
    sta zp_temp2
    lda #<msg_history
    sta zp_ptr1
    lda #>msg_history
    sta zp_ptr1_hi
    lda #<MSG_HIST_BYTES
    sta zp_temp0
    lda #>MSG_HIST_BYTES
    sta zp_temp1
!clr:
    lda zp_temp0
    ora zp_temp1
    beq !done+
    ldy #0
    lda zp_temp2
    sta (zp_ptr1),y
    inc zp_ptr1
    bne !dec+
    inc zp_ptr1_hi
!dec:
    sec
    lda zp_temp0
    sbc #1
    sta zp_temp0
    lda zp_temp1
    sbc #0
    sta zp_temp1
    jmp !clr-
!done:
    rts

// msg_print — Display a message on the message area (rows 0-1)
// Input: zp_ptr0/zp_ptr0_hi = pointer to null-terminated screen code string
// State machine:
//   flags = $00: Both rows empty → print on row 0
//   flags = $01: Row 0 used → print on row 1
//   flags = $03: Both rows full → show -MORE-, clear, print on row 0
// Preserves: nothing
msg_print:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$20
    jsr c128_town_dump_log
#endif
    // Cache source pointer in static RAM so IRQ activity cannot clobber
    // low-ZP pointer bytes before/during message handling.
    lda zp_ptr0
    sta msg_src_lo
    lda zp_ptr0_hi
    sta msg_src_hi

// msg_print_cached — Display message using msg_src_lo/msg_src_hi as source.
// Used by C128 Huffman path to avoid a decode->print ZP pointer race.
msg_print_cached:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$21
    jsr c128_town_dump_log
#endif
#if C128
    // Message rendering is hit constantly during live gameplay; reassert
    // the RAM-side vectors/stubs here so leaked KERNAL state can't persist
    // into the screen write path between overlay transitions.
    jsr hal_platform_vector_reassert
#endif

    lda zp_msg_flags
    cmp #MSG_PENDING | MSG_FULL
    beq !show_more+

    and #MSG_PENDING
    bne !use_row1+

    // --- State 0: both rows empty → print on row 0 ---
    lda #MSG_ROW
    jsr hal_screen_clear_row
    lda #MSG_ROW + 1
    jsr hal_screen_clear_row

    lda #MSG_ROW
    sta zp_cursor_row
    lda #0
    sta zp_cursor_col

    lda zp_text_color
    pha
    lda #COL_MSG_TEXT
    sta zp_text_color
    lda msg_src_lo
    sta zp_ptr0
    lda msg_src_hi
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    pla
    sta zp_text_color

    lda #MSG_PENDING
    sta zp_msg_flags

    lda msg_src_lo
    sta zp_ptr0
    lda msg_src_hi
    sta zp_ptr0_hi
    jmp msg_save_history

!use_row1:
    // --- State 1: row 0 used → print on row 1 ---
    lda #MSG_ROW + 1
    jsr hal_screen_clear_row

    lda #MSG_ROW + 1
    sta zp_cursor_row
    lda #0
    sta zp_cursor_col

    lda zp_text_color
    pha
    lda #COL_MSG_TEXT
    sta zp_text_color
    lda msg_src_lo
    sta zp_ptr0
    lda msg_src_hi
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    pla
    sta zp_text_color

    lda zp_cursor_col
    sta msg_row1_col

    lda #MSG_PENDING | MSG_FULL
    sta zp_msg_flags

    lda msg_src_lo
    sta zp_ptr0
    lda msg_src_hi
    sta zp_ptr0_hi
    jmp msg_save_history

!show_more:
    // --- State 2: both rows full, 3rd message arriving ---
    jsr msg_show_more
    jsr hal_input_get_key

    // Clear state and restart from the cached source pointer.
    lda #0
    sta zp_msg_flags
    jmp msg_print_cached

// msg_clear — Clear the message area and reset flags
// Called at the start of each player turn.
// Preserves: X, Y
msg_clear:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$22
    jsr c128_town_dump_log
#endif
    lda zp_msg_flags
    beq !done+

    lda #MSG_ROW
    jsr hal_screen_clear_row
    lda #MSG_ROW + 1
    jsr hal_screen_clear_row

    lda #0
    sta zp_msg_flags
    sta msg_row1_col
!done:
    rts

// msg_show_more — Display " -MORE-" at end of row 1 message
// Preserves: nothing
msg_show_more:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$23
    jsr c128_town_dump_log
#endif
    lda msg_row1_col
    cmp #MSG_MORE_OVERFLOW_CMP
    bcc !fits+
    lda #MSG_MORE_MAX_COL
!fits:
    sta zp_cursor_col
    lda #MSG_ROW + 1
    bcc !set_row+
    lda #MSG_ROW
!set_row:
    sta zp_cursor_row

    lda zp_text_color
    pha
    lda #COL_WHITE
    sta zp_text_color

    lda #<more_str
    sta zp_ptr0
    lda #>more_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    pla
    sta zp_text_color
    rts

// msg_save_history — Save current message to history ring buffer
// Input: zp_ptr0 = original message pointer (still set from msg_print)
// Preserves: nothing
msg_save_history:
    // Keep history copy atomic so low-ZP pointer bytes used by
    // (zp_ptr0)/(zp_ptr1) cannot be clobbered mid-copy by IRQ paths.
    php
    sei
    lda msg_hist_ptr_lo
    sta zp_ptr1
    lda msg_hist_ptr_hi
    sta zp_ptr1_hi

    // Copy up to 39 chars from source to history
    ldy #0
!copy:
    lda (zp_ptr0),y
    beq !pad+               // Null terminator
    sta (zp_ptr1),y
    iny
    cpy #MSG_HIST_LEN - 1
    bcc !copy-
!pad:
    // Null-terminate
    lda #0
    sta (zp_ptr1),y

    // Advance history index (wrap at 8)
    lda msg_hist_idx
    clc
    adc #1
    and #MSG_HIST_COUNT - 1 // Wrap (8 = power of 2)
    sta msg_hist_idx
    beq !wrap_ptr+

    lda msg_hist_ptr_lo
    clc
    adc #<MSG_HIST_LEN
    sta msg_hist_ptr_lo
    lda msg_hist_ptr_hi
    adc #>MSG_HIST_LEN
    sta msg_hist_ptr_hi
    bne !done_ptr+

!wrap_ptr:
    lda #<msg_history
    sta msg_hist_ptr_lo
    lda #>msg_history
    sta msg_hist_ptr_hi
!done_ptr:
    plp
    rts

// ============================================================
// String data
// ============================================================
more_str:
    .text " -more-" ; .byte 0
