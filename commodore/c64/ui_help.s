// ui_help.s — Help screen rendering code (banked at $F000)
//
// Displays all available key bindings on a full screen with
// PETSCII box-drawing borders and color-coded text.
//
// String data lives in main RAM (ui_help_data.s) in packed format:
//   [type_byte] [string_data...] [$00] repeated for 23 lines.
// The banked code walks this data sequentially.
//
// Layout (40 columns, 25 rows):
//   Row 0:     Top border with "COMMAND REFERENCE" title
//   Rows 1-23: Content area with left/right borders
//   Row 24:    Bottom border with "PRESS ANY KEY" footer
//
// Colors: borders GREY, title/footer WHITE, headers CYAN,
//         keys WHITE, descriptions LGREY

// Import string data (lives in main RAM; #import has include guards
// so this is a no-op when main.s has already imported it)
#import "ui_help_data.s"

// ============================================================
// Constants
// ============================================================
.const HELP_LINE_COUNT = 23

// Inline control codes for help_draw_line
.const CT = $fc     // Tab-to-column (next byte = target column)
.const CH = $fd     // Color: Header (COL_CYAN)
.const CK = $fe     // Color: Key (COL_WHITE)
.const CD = $ff     // Color: Description (COL_LGREY)

// Line type codes (packed inline in help_lines data)
.const HTYPE_CONTENT = 0
.const HTYPE_HEADER  = 1
.const HTYPE_BLANK   = 2

// ASCII box-drawing screen codes (lowercase/uppercase mode)
.const BOX_TL = $2b  // +
.const BOX_TR = $2b  // +
.const BOX_BL = $2b  // +
.const BOX_BR = $2b  // +
.const BOX_H  = $2d  // -
.const BOX_V  = $21  // !

// ============================================================
// Subroutines
// ============================================================

// ui_help_display — Show help screen with borders and colors
// Preserves: nothing
ui_help_display:
    // 1. Clear screen (black background)
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all

    // 2. Draw left/right borders (rows 1-23)
    lda #COL_GREY
    sta zp_text_color
    lda #1
    sta zp_temp0                // row counter
!border_loop:
    lda #BOX_V                  // │
    ldx #0                      // col 0
    ldy zp_temp0                // row
    jsr screen_put_char_at
    lda #BOX_V
    ldx #39                     // col 39
    ldy zp_temp0
    jsr screen_put_char_at
    inc zp_temp0
    lda zp_temp0
    cmp #24
    bcc !border_loop-

    // 3. Draw top border (row 0): +---...---+
    lda #0
    jsr help_draw_hborder

    // Title text "Command Reference" at (0,10) in WHITE
    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    lda #10
    sta zp_cursor_col
    lda #<help_title_str
    sta zp_ptr0
    lda #>help_title_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // 4. Draw bottom border (row 24): +---...---+
    lda #24
    jsr help_draw_hborder

    // Footer text "Press any key" at (24,10) in WHITE
    lda #COL_WHITE
    sta zp_text_color
    lda #24
    sta zp_cursor_row
    lda #10
    sta zp_cursor_col
    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // 5. Draw content lines — sequential walk through packed help_lines
    lda #<help_lines
    sta zp_ptr0
    lda #>help_lines
    sta zp_ptr0_hi
    lda #1
    sta help_line_idx           // row counter (rows 1-23)

!content_loop:
    lda help_line_idx
    cmp #24
    bcs !content_done+

    // Read type byte and advance ptr past it
    ldy #0
    lda (zp_ptr0),y
    tax                         // X = line type
    inc zp_ptr0
    bne !+
    inc zp_ptr0_hi
!:

    cpx #HTYPE_BLANK
    beq !skip_blank+

    // Set initial color: LGREY for content, CYAN for header
    lda #COL_LGREY
    cpx #HTYPE_HEADER
    bne !+
    lda #COL_CYAN
!:  sta zp_text_color

    lda help_line_idx
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col
    jsr help_draw_line          // draws line AND advances zp_ptr0
    jmp !next_line+

!skip_blank:
    // Blank line data is just a null byte — skip past it
    inc zp_ptr0
    bne !next_line+
    inc zp_ptr0_hi

!next_line:
    inc help_line_idx
    jmp !content_loop-

!content_done:
    rts

// help_draw_line — Draw a string with inline color toggle markers
// Input: zp_ptr0/hi = string with CH/CK/CD markers, $00 terminated
//        zp_cursor_row, zp_cursor_col = starting position
//        zp_text_color = initial color (set by caller)
// On exit: zp_ptr0/hi advanced past the string + null terminator
// Preserves: nothing
help_draw_line:
    jsr screen_set_cursor
    ldy #0
    sty zp_temp0                // string offset
!hdl_loop:
    ldy zp_temp0
    lda (zp_ptr0),y
    beq !hdl_done+
    cmp #CD
    beq !hdl_desc+
    cmp #CK
    beq !hdl_key+
    cmp #CH
    beq !hdl_hdr+
    cmp #CT
    beq !hdl_tab+
    // Regular character — write to screen and color RAM
    ldy #0
    sta (zp_screen_lo),y
    lda zp_text_color
    sta (zp_color_lo),y
    inc zp_screen_lo
    bne !+
    inc zp_screen_hi
!:  inc zp_color_lo
    bne !+
    inc zp_color_hi
!:  inc zp_temp0
    jmp !hdl_loop-
!hdl_desc:
    lda #COL_LGREY
    sta zp_text_color
    inc zp_temp0
    jmp !hdl_loop-
!hdl_key:
    lda #COL_WHITE
    sta zp_text_color
    inc zp_temp0
    jmp !hdl_loop-
!hdl_hdr:
    lda #COL_CYAN
    sta zp_text_color
    inc zp_temp0
    jmp !hdl_loop-
!hdl_tab:
    // Tab-to-column: next byte is target column
    inc zp_temp0                // skip past $fc
    ldy zp_temp0
    lda (zp_ptr0),y             // read target column
    sta zp_cursor_col
    jsr screen_set_cursor       // recompute screen/color pointers
    inc zp_temp0                // skip past column byte
    jmp !hdl_loop-
!hdl_done:
    // Advance zp_ptr0 past string + null terminator
    // zp_temp0 = index of null byte; need to add (zp_temp0 + 1) to zp_ptr0
    lda zp_temp0
    sec                         // +1 for null terminator
    adc zp_ptr0                 // A = ptr0_lo + temp0 + 1
    sta zp_ptr0
    bcc !+
    inc zp_ptr0_hi
!:  rts

// help_draw_hborder — Draw a horizontal border: +---...---+
// Input: A = row number
// Draws 40-char border: + then 38 dashes then +
help_draw_hborder:
    sta zp_cursor_row
    lda #COL_GREY
    sta zp_text_color
    lda #0
    sta zp_cursor_col
    lda #BOX_TL                     // + (corner)
    jsr screen_put_char
    ldx #38
!hb_dash:
    lda #BOX_H                      // - (horizontal)
    jsr screen_put_char
    dex
    bne !hb_dash-
    lda #BOX_TR                     // + (corner)
    jmp screen_put_char             // tail call
