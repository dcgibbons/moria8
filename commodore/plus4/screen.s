// screen.s — Screen output routines (40-column TED)
//
// All output uses direct screen memory writes at $0C00+ (screen codes,
// NOT PETSCII). TED attribute bytes are written at $0800+ in parallel.
//
// Vector table allows the 80-column VDC backend to be swapped in for
// C128 support (Phase 10) without changing any callers.
//
// Screen layout (40-col):
//   Rows 0–1:    Message area (2 lines)
//   Rows 2–20:   Game viewport (38x19, columns 1–38)
//   Rows 21–23:  Status bar (3 lines, umoria-style)
//   Row  24:     Input prompt line / spare
//   Cols 0, 39:  Border columns (unused/clear)

#import "../common/vic_palette_consts.s"

// ============================================================
// Constants
// ============================================================
.const SCREEN_COLS = 40
.const SCREEN_ROWS = 25
.const VIEWPORT_X  = 1      // Viewport starts at column 1
.const VIEWPORT_Y  = 2      // Viewport starts at row 2 (below 2-line message area)
.const VIEWPORT_W  = 38     // Viewport width
.const VIEWPORT_H  = 19     // Viewport height
.const MSG_ROW     = 0      // Message line row
.const STATUS_ROW  = 21     // Status bar first row
.const INPUT_ROW   = 24     // Input prompt row (row 23 now used by status bar)

// Screen code for space (clear)
.const SC_SPACE     = $20

.const TED_CR1      = $ff06

// Map existing VIC-style color constants to TED attribute bytes.
// TED attribute bytes use bits 0-3 for chroma and bits 4-6 for luminance.
// The first eight chroma values match VIC-II reasonably well; VIC's grey
// family does not, so greys are represented as lower-luminance white.
plus4_color_attr:
    .byte $00  // black
    .byte $71  // white
    .byte $72  // red
    .byte $73  // cyan
    .byte $74  // purple
    .byte $75  // green
    .byte $76  // blue
    .byte $77  // yellow
    .byte $48  // orange
    .byte $29  // brown
    .byte $62  // light red
    .byte $21  // dark grey
    .byte $41  // grey
    .byte $65  // light green
    .byte $66  // light blue
    .byte $61  // light grey

plus4_color_from_zp:
    txa
    pha
    tya
    pha
    lda zp_text_color
    and #$0f
    tax
    lda plus4_color_attr,x
    sta plus4_color_result
    pla
    tay
    pla
    tax
    lda plus4_color_result
    rts

plus4_color_result: .byte 0

plus4_display_resync:
    lda #TED_SCREEN_DEFAULT
    sta TED_SCREEN_ADDR
    lda TED_CHARPTR
    and #$03
    ora #TED_CHARSET_LOWER_UPPER
    sta TED_CHARPTR
    rts

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
// Screen RAM = 1000 bytes = 3 full pages (768) + 232 bytes ($E8)
// Preserves: nothing
screen_clear:
    // Fill screen RAM with spaces
    lda #SC_SPACE
    ldx #0
!loop:
    sta SCREEN_RAM,x
    sta SCREEN_RAM + $100,x
    sta SCREEN_RAM + $200,x
    inx
    bne !loop-
    // Remaining 232 bytes ($0700-$07E7)
    ldx #232 - 1
!last:
    sta SCREEN_RAM + $300,x
    dex
    bpl !last-

    // Fill TED attribute RAM to current text color
    jsr plus4_color_from_zp
    ldx #0
!col:
    sta COLOR_RAM,x
    sta COLOR_RAM + $100,x
    sta COLOR_RAM + $200,x
    inx
    bne !col-
    ldx #232 - 1
!col_last:
    sta COLOR_RAM + $300,x
    dex
    bpl !col_last-
    // Full clear wipes status rows; force next status_draw to repaint.
    lda zp_ui_dirty
    ora #%10000001          // bit7=force status redraw, bit0=status dirty
    sta zp_ui_dirty
    rts

// screen_blank — Hide display during long operations (TED DEN bit)
// Preserves: nothing
screen_blank:
    lda TED_CR1
    and #%11101111              // Clear bit 4 — DEN off
    sta TED_CR1
    rts

// screen_unblank — Show display after long operations (TED DEN bit)
// Preserves: nothing
screen_unblank:
    lda TED_CR1
    ora #%00010000              // Set bit 4 — DEN on
    sta TED_CR1
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
    jsr plus4_color_from_zp
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
    jsr plus4_color_from_zp
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

    jsr plus4_color_from_zp
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
    jsr plus4_color_from_zp
    sta (zp_color_lo),y
    // Restore cursor
    pla
    sta zp_cursor_col
    pla
    sta zp_cursor_row
    rts

#import "../common/numeric_format.s"

// screen_flash_at — Briefly flash a '*' in white at a screen position, then restore
// Used by bolt animation in spell_effects.s.
// Input:  X = screen row (absolute, 0–24)
//         Y = screen column (absolute, 0–79)
// Clobbers: A, X, Y, zp_ptr0
screen_flash_at:
    stx sfa_save_row
    lda screen_row_lo,x
    sta zp_ptr0
    lda screen_row_hi,x
    sta zp_ptr0_hi
    sty sfa_save_col

    // Save current character
    lda (zp_ptr0),y
    sta sfa_save_char

    // Draw '*' (screen code $2A)
    lda #$2a
    sta (zp_ptr0),y

    // Switch to TED attribute RAM ($0C00 screen -> $0800 attrs), save color, write white
    lda zp_ptr0_hi
    pha                             // Save screen hi byte
    sec
    sbc #$04
    sta zp_ptr0_hi
    lda (zp_ptr0),y
    pha                             // Save original color
    lda plus4_color_attr + COL_WHITE
    sta (zp_ptr0),y

    // Delay (~20ms at 1MHz)
    ldx #$10
!sfa_delay_o:
    ldy #$00
!sfa_delay_i:
    dey
    bne !sfa_delay_i-
    dex
    bne !sfa_delay_o-
    ldy sfa_save_col

    // Restore color
    pla
    sta (zp_ptr0),y

    // Restore screen pointer and character
    pla
    sta zp_ptr0_hi
    lda sfa_save_char
    sta (zp_ptr0),y
    rts

sfa_save_row:   .byte 0
sfa_save_col:   .byte 0
sfa_save_char:  .byte 0

// ============================================================
// Compile-time validation
// ============================================================
.assert "Row table size", screen_row_hi - screen_row_lo, SCREEN_ROWS
.assert "Color table size", color_row_hi - color_row_lo, SCREEN_ROWS
