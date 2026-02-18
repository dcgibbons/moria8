// ui_help.s — Help screen rendering code (banked at $F000)
//
// Displays all available key bindings on a full screen with
// PETSCII box-drawing borders and color-coded text.
//
// String data lives in main RAM (ui_help_data.s) to avoid
// overflowing the $F000-$FFFA banked code region.
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

// Inline color toggle codes for help_draw_line
.const CH = $fd     // Color: Header (COL_CYAN)
.const CK = $fe     // Color: Key (COL_WHITE)
.const CD = $ff     // Color: Description (COL_LGREY)

// Line type codes
.const HTYPE_CONTENT = 0
.const HTYPE_HEADER  = 1
.const HTYPE_BLANK   = 2

// PETSCII box-drawing screen codes
.const BOX_TL = $70  // ┌
.const BOX_TR = $6e  // ┐
.const BOX_BL = $6d  // └
.const BOX_BR = $7d  // ┘
.const BOX_H  = $40  // ─
.const BOX_V  = $5d  // │

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

    // 3. Draw top border (row 0, full width)
    lda #COL_GREY
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    lda #<help_border_top
    sta zp_ptr0
    lda #>help_border_top
    sta zp_ptr0_hi
    jsr screen_put_string

    // Overdraw title in WHITE
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

    // 4. Draw bottom border (row 24, full width)
    lda #COL_GREY
    sta zp_text_color
    lda #24
    sta zp_cursor_row
    lda #0
    sta zp_cursor_col
    lda #<help_border_bot
    sta zp_ptr0
    lda #>help_border_bot
    sta zp_ptr0_hi
    jsr screen_put_string

    // Overdraw footer in WHITE
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

    // 5. Draw content lines (rows 1-23, indices 0-22)
    lda #0
    sta help_line_idx

!content_loop:
    ldx help_line_idx
    cpx #HELP_LINE_COUNT
    bcs !content_done+

    // Check line type
    lda help_line_type,x
    cmp #HTYPE_BLANK
    beq !next_line+
    cmp #HTYPE_HEADER
    beq !draw_header+

    // HTYPE_CONTENT: draw with color toggles
    lda help_line_ptrs_lo,x
    sta zp_ptr0
    lda help_line_ptrs_hi,x
    sta zp_ptr0_hi
    txa
    clc
    adc #1                      // row = index + 1
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col
    jsr help_draw_line
    jmp !next_line+

!draw_header:
    lda #COL_CYAN
    sta zp_text_color
    lda help_line_ptrs_lo,x
    sta zp_ptr0
    lda help_line_ptrs_hi,x
    sta zp_ptr0_hi
    txa
    clc
    adc #1
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col
    jsr screen_put_string
    jmp !next_line+

!next_line:
    inc help_line_idx
    jmp !content_loop-

!content_done:
    rts

// help_draw_line — Draw a string with inline color toggle markers
// Input: zp_ptr0/hi = string with CH/CK/CD markers, $00 terminated
//        zp_cursor_row, zp_cursor_col = starting position
// Starts in CD (description / COL_LGREY) color
// Preserves: nothing
help_draw_line:
    lda #COL_LGREY
    sta zp_text_color
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
!hdl_done:
    rts
