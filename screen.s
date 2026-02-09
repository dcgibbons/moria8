// screen.s — Screen output routines (40-column VIC-II)
//
// All output uses direct screen memory writes at $0400+ (screen codes,
// NOT PETSCII). Color is written to color RAM at $D800+ in parallel.
//
// Vector table allows the 80-column VDC backend to be swapped in for
// C128 support (Phase 10) without changing any callers.
//
// Screen layout (40-col):
//   Row  0:      Message line
//   Rows 1–20:   Game viewport (38x20, columns 1–38)
//   Rows 21–22:  Status bar (2 lines)
//   Row  23:     Input prompt line
//   Cols 0, 39:  Border columns (unused/clear)

// ============================================================
// Constants
// ============================================================
.const SCREEN_COLS = 40
.const SCREEN_ROWS = 25
.const VIEWPORT_X  = 1      // Viewport starts at column 1
.const VIEWPORT_Y  = 1      // Viewport starts at row 1
.const VIEWPORT_W  = 38     // Viewport width
.const VIEWPORT_H  = 20     // Viewport height
.const MSG_ROW     = 0      // Message line row
.const STATUS_ROW  = 21     // Status bar first row
.const INPUT_ROW   = 23     // Input prompt row

// Colors
.const COL_BLACK    = $00
.const COL_WHITE    = $01
.const COL_RED      = $02
.const COL_CYAN     = $03
.const COL_PURPLE   = $04
.const COL_GREEN    = $05
.const COL_BLUE     = $06
.const COL_YELLOW   = $07
.const COL_ORANGE   = $08
.const COL_BROWN    = $09
.const COL_LRED     = $0a
.const COL_DGREY    = $0b
.const COL_GREY     = $0c
.const COL_LGREEN   = $0d
.const COL_LBLUE    = $0e
.const COL_LGREY    = $0f

// Screen code for space (clear)
.const SC_SPACE     = $20

// ============================================================
// Vector table — callers use these indirect JSRs
// Replaced by VDC backend for 80-column mode (Phase 10)
// ============================================================
screen_vectors:
    jmp screen_clear        // +0: clear entire screen
    jmp screen_put_char     // +3: put char at cursor
    jmp screen_put_string   // +6: put string at (row,col)
    jmp screen_set_color    // +9: set current text color
    jmp screen_clear_row    // +12: clear a single row

// ============================================================
// Row address lookup table (lo/hi bytes for each row)
// screen_row_lo[n] / screen_row_hi[n] = $0400 + n*40
// ============================================================
screen_row_lo:
    .fill SCREEN_ROWS, <(SCREEN_RAM + i * SCREEN_COLS)
screen_row_hi:
    .fill SCREEN_ROWS, >(SCREEN_RAM + i * SCREEN_COLS)
color_row_lo:
    .fill SCREEN_ROWS, <(COLOR_RAM + i * SCREEN_COLS)
color_row_hi:
    .fill SCREEN_ROWS, >(COLOR_RAM + i * SCREEN_COLS)

// ============================================================
// Subroutines
// ============================================================

// screen_clear — Clear entire screen (spaces) and color RAM (current color)
// Preserves: nothing
screen_clear:
    lda #SC_SPACE
    ldx #0
!loop:
    sta SCREEN_RAM,x
    sta SCREEN_RAM + $100,x
    sta SCREEN_RAM + $200,x
    sta SCREEN_RAM + $2e8,x    // Last partial page
    inx
    bne !loop-
    // Fill remaining 232 bytes of last page
    ldx #$e8
!last:
    lda #SC_SPACE
    sta SCREEN_RAM + $300,x
    inx
    bne !last-

    // Clear color RAM to current text color
    lda zp_text_color
    ldx #0
!col:
    sta COLOR_RAM,x
    sta COLOR_RAM + $100,x
    sta COLOR_RAM + $200,x
    sta COLOR_RAM + $2e8,x
    inx
    bne !col-
    ldx #$e8
!col_last:
    lda zp_text_color
    sta COLOR_RAM + $300,x
    inx
    bne !col_last-
    rts

// screen_set_cursor — Set screen and color pointers for (row, col)
// Input:  zp_cursor_row, zp_cursor_col
// Output: zp_screen_lo/hi, zp_color_lo/hi point to that cell
// Preserves: Y
screen_set_cursor:
    ldx zp_cursor_row
    lda screen_row_lo,x
    clc
    adc zp_cursor_col
    sta zp_screen_lo
    lda screen_row_hi,x
    adc #0
    sta zp_screen_hi

    lda color_row_lo,x
    clc
    adc zp_cursor_col
    sta zp_color_lo
    lda color_row_hi,x
    adc #0
    sta zp_color_hi
    rts

// screen_put_char — Write one screen code at current cursor position
// Input:  A = screen code
//         zp_cursor_row, zp_cursor_col = position
//         zp_text_color = color
// Output: cursor advances right by 1
// Preserves: X
screen_put_char:
    pha                     // Save char
    txa
    pha                     // Save X
    jsr screen_set_cursor   // Clobbers X (ldx zp_cursor_row)
    pla
    tax                     // Restore X
    pla                     // Restore char
    ldy #0
    sta (zp_screen_lo),y
    lda zp_text_color
    sta (zp_color_lo),y
    inc zp_cursor_col
    rts

// screen_put_string — Write a null-terminated string of screen codes
// Input:  zp_ptr0/zp_ptr0_hi = pointer to string (screen codes, $00 terminated)
//         zp_cursor_row = row
//         zp_cursor_col = starting column
//         zp_text_color = color
// Preserves: nothing
screen_put_string:
    jsr screen_set_cursor
    ldy #0
!loop:
    lda (zp_ptr0),y
    beq !done+              // Null terminator
    sta (zp_screen_lo),y
    lda zp_text_color
    sta (zp_color_lo),y
    iny
    cpy #SCREEN_COLS        // Safety: don't overflow row
    bcc !loop-
!done:
    tya
    clc
    adc zp_cursor_col
    sta zp_cursor_col       // Advance cursor past string
    rts

// screen_set_color — Set current text color
// Input: A = color value (0–15)
// Preserves: X, Y
screen_set_color:
    sta zp_text_color
    rts

// screen_clear_row — Clear a single row to spaces
// Input: A = row number (0–24)
// Preserves: nothing
screen_clear_row:
    tax
    lda screen_row_lo,x
    sta zp_screen_lo
    lda screen_row_hi,x
    sta zp_screen_hi
    lda color_row_lo,x
    sta zp_color_lo
    lda color_row_hi,x
    sta zp_color_hi

    lda #SC_SPACE
    ldy #SCREEN_COLS - 1
!loop:
    sta (zp_screen_lo),y
    dey
    bpl !loop-

    lda zp_text_color
    ldy #SCREEN_COLS - 1
!col:
    sta (zp_color_lo),y
    dey
    bpl !col-
    rts

// screen_put_char_at — Write one char at specific (row, col) without moving cursor
// Input:  A = screen code
//         X = column
//         Y = row
//         zp_text_color = color
// Preserves: cursor position
screen_put_char_at:
    // Save char and cursor
    sta zp_temp4
    lda zp_cursor_row
    pha
    lda zp_cursor_col
    pha
    // Set position and write
    sty zp_cursor_row
    stx zp_cursor_col
    jsr screen_set_cursor
    lda zp_temp4
    ldy #0
    sta (zp_screen_lo),y
    lda zp_text_color
    sta (zp_color_lo),y
    // Restore cursor
    pla
    sta zp_cursor_col
    pla
    sta zp_cursor_row
    rts

// screen_put_hex — Write a byte as 2-digit hex at cursor
// Input:  A = byte to display
//         zp_cursor_row, zp_cursor_col = position
// Preserves: nothing
screen_put_hex:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr !hex_digit+
    jsr screen_put_char
    pla
    and #$0f
    jsr !hex_digit+
    jmp screen_put_char
!hex_digit:
    // Convert nibble (0–15) to screen code for hex digit
    cmp #$0a
    bcc !digit+
    // A–F: screen codes $01–$06
    sbc #$09
    rts
!digit:
    // 0–9: screen codes $30–$39
    ora #$30
    rts

// screen_put_decimal — Write an 8-bit value as decimal at cursor
// Input:  A = value (0–255)
//         zp_cursor_row, zp_cursor_col = position
// Preserves: nothing
screen_put_decimal:
    sta zp_temp4
    lda #0
    sta zp_temp2            // Leading zero suppression flag

    // Hundreds
    ldx #0
    lda zp_temp4
!hundreds:
    cmp #100
    bcc !tens+
    sbc #100
    inx
    bne !hundreds-          // Always branches (X won't wrap to 0 for valid input)
!tens:
    sta zp_temp4
    txa
    beq !skip_h+            // Skip leading zero
    ora #$30                // Screen code for digit
    jsr screen_put_char
    inc zp_temp2            // Mark that we printed a digit
    jmp !do_tens+
!skip_h:
    lda zp_temp2
    bne !print_zero_h+
    jmp !do_tens+
!print_zero_h:
    lda #$30
    jsr screen_put_char
!do_tens:
    ldx #0
    lda zp_temp4
!tens_loop:
    cmp #10
    bcc !ones+
    sbc #10
    inx
    bne !tens_loop-
!ones:
    sta zp_temp4
    txa
    beq !skip_t+
    ora #$30
    jsr screen_put_char
    inc zp_temp2
    jmp !do_ones+
!skip_t:
    lda zp_temp2
    beq !do_ones+
    lda #$30
    jsr screen_put_char
!do_ones:
    lda zp_temp4
    ora #$30
    jmp screen_put_char     // Tail call — always print ones digit

// screen_put_decimal_rj2 — Print 8-bit value right-justified in 2-char field
// If value < 10, prints a leading space first.
// Input:  A = value (0–255)
// Preserves: nothing
screen_put_decimal_rj2:
    cmp #10
    bcs screen_put_decimal      // 2+ digits, print normally
    pha
    lda #$20                    // Leading space
    jsr screen_put_char
    pla
    jmp screen_put_decimal

// screen_put_decimal_lz2 — Print 8-bit value with leading zero in 2-char field
// If value < 10, prints a leading '0' first.
// Input:  A = value (0–99)
// Preserves: nothing
screen_put_decimal_lz2:
    cmp #10
    bcs screen_put_decimal
    pha
    lda #$30                    // Leading zero
    jsr screen_put_char
    pla
    jmp screen_put_decimal

// screen_put_decimal_16 — Write a 16-bit value as decimal at cursor
// Input:  zp_temp0 = lo byte, zp_temp1 = hi byte
//         zp_cursor_row, zp_cursor_col = position
// Preserves: nothing
// Uses:   zp_temp2 (leading zero flag), zp_temp3 (digit counter)
screen_put_decimal_16:
    lda #0
    sta zp_temp2            // Leading zero flag
    ldx #4                  // 5 digits (10000s, 1000s, 100s, 10s, 1s), index 4..0
!digit_loop:
    lda #0
    sta zp_temp3            // Digit counter
!sub_loop:
    lda zp_temp0
    sec
    sbc decimal_powers_lo,x
    tay
    lda zp_temp1
    sbc decimal_powers_hi,x
    bcc !digit_done+        // Underflow — done with this digit
    sta zp_temp1
    sty zp_temp0
    inc zp_temp3
    jmp !sub_loop-
!digit_done:
    lda zp_temp3
    bne !print_digit+
    // Check if leading zero
    lda zp_temp2
    beq !next_digit+        // Still leading zeros, skip
!print_digit:
    lda #1
    sta zp_temp2            // No more leading zeros
    lda zp_temp3
    ora #$30                // Digit → screen code
    jsr screen_put_char     // X preserved by screen_put_char
!next_digit:
    dex
    bne !digit_loop-
    // Always print ones digit
    lda zp_temp0
    ora #$30
    jmp screen_put_char

// Powers of 10 for 16-bit decimal conversion (lo/hi)
decimal_powers_lo:
    .byte <1, <10, <100, <1000, <10000
decimal_powers_hi:
    .byte >1, >10, >100, >1000, >10000

// ============================================================
// Compile-time validation
// ============================================================
.assert "Row table size", screen_row_hi - screen_row_lo, SCREEN_ROWS
.assert "Color table size", color_row_hi - color_row_lo, SCREEN_ROWS
