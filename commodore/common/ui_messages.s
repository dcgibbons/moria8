// ui_messages.s — Message line management
//
// Top of screen (rows 0-1) displays game messages.
// Two-line message area reduces -MORE- frequency:
// messages fill row 0 then row 1, -MORE- only when
// a 3rd message arrives while both rows are occupied.
// Message history buffer holds last 8 messages.
//
// Messages are screen-code strings, null-terminated.

// Message flags (zp_msg_flags)
.const MSG_PENDING   = $01  // Row 0 has an unread message
.const MSG_FULL      = $02  // Row 1 also has an unread message (both rows occupied)

// History buffer (8 messages x 40 chars max each)
.const MSG_HIST_COUNT = 8
.const MSG_HIST_LEN   = 40
msg_history:
    .fill MSG_HIST_COUNT * MSG_HIST_LEN, 0
msg_hist_idx:
    .byte 0                 // Current write index (0–7, wraps)
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
    ldx #0
    lda #$20                // Space (screen code)
!clr:
    sta msg_history,x
    inx
    bne !clr-
    // Clear remaining (320 - 256 = 64 bytes)
    ldx #0
!clr2:
    sta msg_history + 256,x
    inx
    cpx #64
    bne !clr2-
    rts

// msg_print — Display a message on the message area (rows 0-1)
// Input: zp_ptr0/zp_ptr0_hi = pointer to null-terminated screen code string
// State machine:
//   flags = $00: Both rows empty → print on row 0
//   flags = $01: Row 0 used → print on row 1
//   flags = $03: Both rows full → show -MORE-, clear, print on row 0
// Preserves: nothing
msg_print:
    // Cache source pointer in static RAM so C128 IRQ activity cannot
    // clobber low-ZP pointer bytes before/during message handling.
    lda zp_ptr0
    sta msg_src_lo
    lda zp_ptr0_hi
    sta msg_src_hi

    lda zp_msg_flags
    cmp #MSG_PENDING | MSG_FULL
    beq !show_more+

    and #MSG_PENDING
    bne !use_row1+

    // --- State 0: both rows empty → print on row 0 ---
    lda #MSG_ROW
    jsr screen_clear_row
    lda #MSG_ROW + 1
    jsr screen_clear_row

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
    jsr screen_put_string
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
    jsr screen_clear_row

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
    jsr screen_put_string
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
    // Save incoming message pointer (msg_show_more clobbers zp_ptr0)
    lda msg_src_lo
    pha
    lda msg_src_hi
    pha

    jsr msg_show_more
    jsr input_get_key

    // Restore message pointer
    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0

    // Clear state and restart — will take state 0 path
    lda #0
    sta zp_msg_flags
    jmp msg_print

// msg_clear — Clear the message area and reset flags
// Called at the start of each player turn.
// Preserves: X, Y
msg_clear:
    lda zp_msg_flags
    beq !done+

    lda #MSG_ROW
    jsr screen_clear_row
    lda #MSG_ROW + 1
    jsr screen_clear_row

    lda #0
    sta zp_msg_flags
!done:
    rts

// msg_show_more — Display " -MORE-" at end of row 1 message
// Preserves: nothing
msg_show_more:
    lda msg_row1_col
    cmp #34                 // Room for " -MORE-" (7 chars)?
    bcc !fits+
    lda #33                 // Clamp so it fits in 40 cols
!fits:
    sta zp_cursor_col
    lda #MSG_ROW + 1
    sta zp_cursor_row

    lda zp_text_color
    pha
    lda #COL_WHITE
    sta zp_text_color

    lda #<more_str
    sta zp_ptr0
    lda #>more_str
    sta zp_ptr0_hi
    jsr screen_put_string

    pla
    sta zp_text_color
    rts

// msg_save_history — Save current message to history ring buffer
// Input: zp_ptr0 = original message pointer (still set from msg_print)
// Preserves: nothing
msg_save_history:
    // C128: keep history copy atomic so low-ZP pointer bytes used by
    // (zp_ptr0)/(zp_ptr1) cannot be clobbered mid-copy by IRQ paths.
    lda zp_machine_type
    cmp #MACHINE_C128
    bne !msh_no_lock+
    php
    sei
!msh_no_lock:
    // Calculate destination: $msg_history + (msg_hist_idx * 40)
    // using 16-bit math because msg_history is 320 bytes long
    lda msg_hist_idx
    asl
    asl
    asl
    sta zp_temp0     // x8 (lo)
    clc
    lda #0
    adc #0
    sta zp_temp1     // x8 (hi)

    lda zp_temp0
    asl
    rol zp_temp1     // x16
    asl
    rol zp_temp1     // x32

    clc
    adc zp_temp0
    sta zp_ptr1      // lo: x32 + x8 = x40
    lda zp_temp1
    adc #0
    sta zp_ptr1_hi

    clc
    lda zp_ptr1
    adc #<msg_history
    sta zp_ptr1
    lda zp_ptr1_hi
    adc #>msg_history
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

    lda zp_machine_type
    cmp #MACHINE_C128
    bne !msh_no_unlock+
    plp
!msh_no_unlock:
    rts

// ============================================================
// String data
// ============================================================
more_str:
    .text " -more-" ; .byte 0
