// ui_messages.s — Message line management
//
// Top of screen (row 0) displays game messages.
// Supports -more- prompt when a new message arrives before
// the player has had a turn to read the previous one.
// Message history buffer holds last 8 messages.
//
// Messages are screen-code strings, null-terminated.

// Message flags (zp_msg_flags)
.const MSG_PENDING   = $01  // A message is waiting to be read
.const MSG_MORE      = $02  // -more- prompt is active

// History buffer (8 messages x 40 chars max each)
.const MSG_HIST_COUNT = 8
.const MSG_HIST_LEN   = 40
msg_history:
    .fill MSG_HIST_COUNT * MSG_HIST_LEN, 0
msg_hist_idx:
    .byte 0                 // Current write index (0–7, wraps)

// ============================================================
// Subroutines
// ============================================================

// msg_init — Clear message system
msg_init:
    lda #0
    sta zp_msg_flags
    sta msg_hist_idx
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

// msg_print — Display a message on the message line (row 0)
// Input: zp_ptr0/zp_ptr0_hi = pointer to null-terminated screen code string
// If a message is already pending, show -more- and wait for keypress first.
// Preserves: nothing
msg_print:
    // Check if previous message is pending
    lda zp_msg_flags
    and #MSG_PENDING
    beq !no_more+

    // Save incoming message pointer (msg_show_more clobbers zp_ptr0)
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha

    // Show "-MORE-" prompt and wait
    jsr msg_show_more
    jsr input_get_key       // Wait for any keypress

    // Restore message pointer
    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    // Fall through to display new message

!no_more:
    // Clear message row
    lda #MSG_ROW
    jsr screen_clear_row

    // Set cursor to row 0, col 0
    lda #MSG_ROW
    sta zp_cursor_row
    lda #0
    sta zp_cursor_col

    // Save current color, set message color
    lda zp_text_color
    pha
    lda #COL_MSG_TEXT
    sta zp_text_color

    // Print the string
    jsr screen_put_string

    // Restore color
    pla
    sta zp_text_color

    // Mark message as pending
    lda zp_msg_flags
    ora #MSG_PENDING
    sta zp_msg_flags

    // Save to history
    jsr msg_save_history

    rts

// msg_clear — Clear the message line and reset pending flag
// Called at the start of each player turn.
// Preserves: X, Y
msg_clear:
    lda zp_msg_flags
    and #MSG_PENDING
    beq !done+              // Nothing to clear

    lda #MSG_ROW
    jsr screen_clear_row

    lda #0
    sta zp_msg_flags
!done:
    rts

// msg_show_more — Display "-MORE-" at end of current message
// Preserves: nothing
msg_show_more:
    lda zp_cursor_col
    cmp #34                 // Room for " -MORE-" (7 chars)?
    bcc !fits+
    lda #33                 // Truncate position
!fits:
    sta zp_cursor_col
    lda #MSG_ROW
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
    // Calculate destination: msg_history + (msg_hist_idx * 40)
    lda msg_hist_idx
    // Multiply by 40: x32 + x8
    asl             // x2
    asl             // x4
    asl             // x8
    sta zp_temp0
    asl             // x16
    asl             // x32
    clc
    adc zp_temp0    // x32 + x8 = x40
    tax             // X = offset into history buffer

    // Copy up to 39 chars from source to history
    ldy #0
!copy:
    lda (zp_ptr0),y
    beq !pad+               // Null terminator
    sta msg_history,x
    inx
    iny
    cpy #MSG_HIST_LEN - 1
    bcc !copy-
!pad:
    // Null-terminate and pad with spaces
    lda #0
    sta msg_history,x

    // Advance history index (wrap at 8)
    lda msg_hist_idx
    clc
    adc #1
    and #MSG_HIST_COUNT - 1 // Wrap (8 = power of 2)
    sta msg_hist_idx
    rts

// ============================================================
// String data
// ============================================================
more_str:
    .text " -MORE-" ; .byte 0
