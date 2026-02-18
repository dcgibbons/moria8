// title_screen.s — Title screen loader and renderer
//
// Loads title art from disk ("TITLE" file) into MAP_BASE ($C000),
// renders to screen RAM, then returns. $C000 is naturally recycled
// when dungeon_generate is called.
//
// Fallback: if KERNAL LOAD fails (no disk, file not found),
// displays a simple text title (original behavior).

// ============================================================
// title_load_and_draw — Load and render the title screen
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_cursor_row/col, zp_text_color
// ============================================================
title_load_and_draw:
    // SETNAM: filename "TITLE" (5 chars)
    lda #5
    ldx #<title_filename
    ldy #>title_filename
    jsr KERNAL_SETNAM

    // SETLFS: logical file 2, device 8, secondary 1 (use header address)
    lda #2
    ldx #8
    ldy #1
    jsr KERNAL_SETLFS

    // LOAD: 0 = load to address from file header
    lda #0
    ldx #<MAP_BASE
    ldy #>MAP_BASE
    jsr $FFD5               // KERNAL LOAD
    bcs !title_fallback+    // Carry set = error

    // Restore VIC-II bank 0 after serial I/O
    lda $dd00
    ora #%00000011
    sta $dd00

    // Clear screen after KERNAL LOAD (removes "SEARCHING..." messages)
    jsr screen_clear

    // Render the loaded art data
    jsr title_render_data
    rts

!title_fallback:
    // Simple text title (no disk art available)
    jsr screen_clear        // Clear KERNAL residue from failed load too
    lda #0
    sta zp_cursor_col
    lda #10
    sta zp_cursor_row
    lda #COL_WHITE
    sta zp_text_color
    lda #<title_str
    sta zp_ptr0
    lda #>title_str
    sta zp_ptr0_hi
    lda #15                 // Center: (40-10)/2
    sta zp_cursor_col
    jsr screen_put_string
    rts

// ============================================================
// title_render_data — Render segment stream from MAP_BASE
// Format: [row, col, color, screen_codes..., $00] ... $FF
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_cursor_row/col, zp_text_color
// ============================================================
title_render_data:
    lda #<MAP_BASE
    sta zp_ptr1
    lda #>MAP_BASE
    sta zp_ptr1_hi

!trd_loop:
    // Read first byte: row or $FF (end marker)
    ldy #0
    lda (zp_ptr1),y
    cmp #$ff
    beq !trd_done+
    sta zp_cursor_row

    // Read col
    iny
    lda (zp_ptr1),y
    sta zp_cursor_col

    // Read color
    iny
    lda (zp_ptr1),y
    sta zp_text_color

    // Advance ptr1 by 3 to point at string data
    clc
    lda zp_ptr1
    adc #3
    sta zp_ptr1
    lda zp_ptr1_hi
    adc #0
    sta zp_ptr1_hi

    // Copy string pointer to ptr0 for screen_put_string
    lda zp_ptr1
    sta zp_ptr0
    lda zp_ptr1_hi
    sta zp_ptr0_hi

    // Render this segment
    jsr screen_put_string

    // Scan forward in ptr1 to find null terminator
    ldy #0
!trd_scan:
    lda (zp_ptr1),y
    beq !trd_found+
    iny
    bne !trd_scan-         // Safety: max 255 chars per segment

!trd_found:
    // Advance ptr1 past the null byte
    iny                     // Y = length + 1
    tya
    clc
    adc zp_ptr1
    sta zp_ptr1
    lda zp_ptr1_hi
    adc #0
    sta zp_ptr1_hi

    jmp !trd_loop-

!trd_done:
    rts

// Filename for KERNAL LOAD (PETSCII, NOT null-terminated — KERNAL uses length)
// Must use explicit PETSCII bytes — .text produces screen codes under screencode_upper
title_filename:
    .byte $54, $49, $54, $4c, $45   // "TITLE" in PETSCII
