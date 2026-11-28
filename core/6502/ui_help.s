#importonce
// ui_help.s — Help screen rendering code
//
// Displays all available key bindings on a full screen with
// PETSCII box-drawing borders and color-coded text.
//
// String data lives alongside the overlay in packed format:
//   [type_byte] [string_data...] [$00] repeated for 23 lines.
// The banked code walks this data sequentially.
//
// Layout (SCREEN_COLS columns, SCREEN_ROWS rows):
//   Row 0:     Top border with "COMMAND REFERENCE" title
//   Rows 1..SCREEN_ROWS-2: Content area with left/right borders
//   Last row:  Bottom border with page-aware footer
//
// Colors: borders GREY, title/footer WHITE, headers CYAN,
//         keys WHITE, descriptions LGREY

// ============================================================
// Constants
// ============================================================
.const HELP_LINE_COUNT = SCREEN_ROWS - 2
.const HELP_FRAME_LEFT_COL = 0
.const HELP_FRAME_RIGHT_COL = SCREEN_COLS - 1
.const HELP_FRAME_HSEG_COUNT = SCREEN_COLS - 2
#if HAL_PLATFORM_LEGAL_VIEWER
.const HELP_TITLE_COL = (SCREEN_COLS - 29) / 2
#else
.const HELP_TITLE_COL = (SCREEN_COLS - 17) / 2
#endif
#if HAL_INPUT_HELP_FOOTER_USES_ESC_STOP
.const HELP_FOOTER_LEN = 28
.const HELP_FOOTER_MORE_LEN = 33
#else
.const HELP_FOOTER_LEN = 29
.const HELP_FOOTER_MORE_LEN = 34
#endif
.const HELP_FOOTER_COL = (SCREEN_COLS - HELP_FOOTER_LEN) / 2
.const HELP_FOOTER_MORE_COL = (SCREEN_COLS - HELP_FOOTER_MORE_LEN) / 2
.const HELP_PAGE_ENTRY_SIZE = 2

// Inline control codes for help_draw_line
.const CT = $fc     // Tab-to-column (next byte = target column)
.const CH = $fd     // Color: Header (COL_CYAN)
.const CK = $fe     // Color: Key (COL_WHITE)
.const CD = $ff     // Color: Description (COL_LGREY)

// Line type codes (packed inline in help_lines data)
.const HTYPE_CONTENT = 0
.const HTYPE_HEADER  = 1
.const HTYPE_BLANK   = 2
.const HTYPE_END     = 3

// ASCII box-drawing screen codes (lowercase/uppercase mode)
.const BOX_TL = $2b  // +
.const BOX_TR = $2b  // +
.const BOX_BL = $2b  // +
.const BOX_BR = $2b  // +
.const BOX_H  = $2d  // -
.const BOX_V  = hal_screen_box_vertical_char

// ============================================================
// Subroutines
// ============================================================

.const MSG_HIST_TITLE_COL = (SCREEN_COLS - 15) / 2
.const MSG_HIST_MAX_PRINT = SCREEN_COLS - 2

// ui_help_display — Show help screen with borders and colors
// Preserves: nothing
ui_help_display:
#if HELP_UI_DISPATCH_MSG_HIST
    lda zp_input_cmd
    cmp #CMD_MSG_HISTORY
    bne !help_normal+
    jmp ui_msg_history_draw
!help_normal:
#endif
    jsr help_select_page
    jsr help_draw_frame

    // Title text "Command Reference" centered on row 0, footer on bottom row.
    ldx #HELP_TITLE_COL
    lda #<uh_title_str
    ldy #>uh_title_str
    jsr help_put_white_row0

    ldx help_page_idx
    inx
    cpx help_page_count
    bcc !footer_more+
    ldx #HELP_FOOTER_COL
    lda #<uh_press_key_str
    ldy #>uh_press_key_str
    bne !footer_draw+
!footer_more:
    ldx #HELP_FOOTER_MORE_COL
    lda #<uh_next_key_str
    ldy #>uh_next_key_str
!footer_draw:
    jsr help_put_white_bot

    // 5. Draw content lines for the selected page.
    lda zp_ptr1
    sta zp_ptr0
    lda zp_ptr1_hi
    sta zp_ptr0_hi
    lda #1
    sta help_line_idx           // content-row counter

!content_loop:
    lda help_line_idx
    cmp #(SCREEN_ROWS - 1)
    bcs !content_done+

    // Read type byte and advance ptr past it
    ldy #0
    lda (zp_ptr0),y
    tax                         // X = line type
    inc zp_ptr0
    bne !+
    inc zp_ptr0_hi
!:

    cpx #HTYPE_END
    beq !content_done+
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

// help_draw_frame — Clear screen and draw box borders on rows 0..SCREEN_ROWS-1
help_draw_frame:
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all

    lda #COL_GREY
    sta zp_text_color
    lda #1
    sta zp_temp0                // row counter
!border_loop:
    lda #BOX_V                  // |
    ldx #0                      // col 0
    ldy zp_temp0                // row
    jsr hal_screen_put_char_at
    lda #BOX_V
    ldx #HELP_FRAME_RIGHT_COL
    ldy zp_temp0
    jsr hal_screen_put_char_at
    inc zp_temp0
    lda zp_temp0
    cmp #(SCREEN_ROWS - 1)
    bcc !border_loop-

    lda #0
    jsr help_draw_hborder
    lda #(SCREEN_ROWS - 1)
    jmp help_draw_hborder

help_put_white_row0:
    pha
    lda #0
    beq !pw_go+
help_put_white_bot:
    pha
    lda #(SCREEN_ROWS - 1)
!pw_go:
    sta zp_cursor_row
    stx zp_cursor_col
    lda #COL_WHITE
    sta zp_text_color
    pla
    jmp screen_put_string_ay

// ui_msg_history_draw — Render the 8-slot message history ring buffer (Ctrl+P)
ui_msg_history_draw:
    jsr help_draw_frame

    ldx #MSG_HIST_TITLE_COL
    lda #<uh_msg_hist_title
    ldy #>uh_msg_hist_title
    jsr help_put_white_row0

    ldx #HELP_FOOTER_COL
    lda #<uh_press_key_str
    ldy #>uh_press_key_str
    jsr help_put_white_bot

    // Walk 8 ring slots oldest -> newest starting at msg_hist_idx
    lda msg_hist_ptr_lo
    sta zp_ptr0
    lda msg_hist_ptr_hi
    sta zp_ptr0_hi
    lda msg_hist_idx
    sta zp_temp0                // current slot index (0..7)
    lda #2
    sta zp_temp1                // current output row (2..9)
    lda #MSG_HIST_COUNT
    sta zp_temp2                // remaining slots to check
!hist_slot_loop:
    ldy #0
#if MSG_HISTORY_IN_AUX
    jsr mmu_safe_map_read_ptr0
#else
    lda (zp_ptr0),y
#endif
    beq !hist_next_slot+
    cmp #$20                    // Space sentinel = unused slot from msg_init
    beq !hist_next_slot+

    lda zp_temp1
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #COL_LGREY
    sta zp_text_color
    lda #0
    sta zp_temp3                // character column index
!hist_char_loop:
    ldy zp_temp3
    cpy #MSG_HIST_MAX_PRINT
    bcs !hist_line_done+
#if MSG_HISTORY_IN_AUX
    jsr mmu_safe_map_read_ptr0
#else
    lda (zp_ptr0),y
#endif
    beq !hist_line_done+
    jsr hal_screen_put_char
    inc zp_temp3
    bne !hist_char_loop-
!hist_line_done:
    inc zp_temp1

!hist_next_slot:
    inc zp_temp0
    lda zp_temp0
    and #MSG_HIST_COUNT - 1
    sta zp_temp0
    bne !hist_adv_ptr+
    lda #<msg_history
    sta zp_ptr0
    lda #>msg_history
    sta zp_ptr0_hi
    jmp !hist_next_iter+
!hist_adv_ptr:
    lda zp_ptr0
    clc
    adc #<MSG_HIST_LEN
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #>MSG_HIST_LEN
    sta zp_ptr0_hi
!hist_next_iter:
    dec zp_temp2
    bne !hist_slot_loop-

    lda zp_temp1
    cmp #2
    bne !hist_done+
    lda #COL_GREY
    sta zp_text_color
    lda #2
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col
    lda #<uh_msg_hist_none
    ldy #>uh_msg_hist_none
    jsr screen_put_string_ay
!hist_done:
    rts

// help_select_page — resolve current page pointer and clamp page index
help_select_page:
    lda help_pages_src_lo
    sta zp_ptr0
    lda help_pages_src_hi
    sta zp_ptr0_hi

    ldy #0
    lda (zp_ptr0),y
    sta help_page_count

    lda help_page_idx
    cmp help_page_count
    bcc !page_ok+
    lda #0
    sta help_page_idx
!page_ok:
    lda help_page_idx
    asl
    clc
    adc #1
    clc
    adc zp_ptr0
    sta zp_ptr0
    bcc !+
    inc zp_ptr0_hi
!:
    ldy #0
    lda (zp_ptr0),y
    sta zp_ptr1
    iny
    lda (zp_ptr0),y
    sta zp_ptr1_hi
    rts

// help_draw_line — Draw a string with inline color toggle markers
// Input: zp_ptr0/hi = string with CH/CK/CD markers, $00 terminated
//        zp_cursor_row, zp_cursor_col = starting position
//        zp_text_color = initial color (set by caller)
// On exit: zp_ptr0/hi advanced past the string + null terminator
// Preserves: nothing
help_draw_line:
    jsr hal_screen_set_cursor
    ldy #0
    sty zp_temp0                // string offset
!hdl_loop:
    ldy zp_temp0
    lda (zp_ptr0),y
    beq !hdl_done+
    cmp #CT
    beq !hdl_tab+
    jsr help_emit_byte
    inc zp_temp0
    jmp !hdl_loop-

help_emit_byte:
    cmp #$80
    bcc !hdl_char+
#if HELP_DATA_BPE
.if (SCREEN_COLS >= 80) {
    cmp #$fb
} else {
    cmp #$f9
}
    bcs !hdl_ctrl+
    sec
    sbc #$80
    tax
    lda help_dict_r,x
    pha
    lda help_dict_l,x
    jsr help_emit_byte
    pla
    jmp help_emit_byte
!hdl_ctrl:
    cmp #CH
    bcs !hdl_color+
.if (SCREEN_COLS >= 80) {
    lda #44                     // HELP80_COL2
} else {
    ldx #20
    cmp #$fb
    beq !tab_ok+
    ldx #15
    cmp #$fa
    beq !tab_ok+
    ldx #27
!tab_ok:
    txa
}
    sta zp_cursor_col
    jmp hal_screen_set_cursor
!hdl_color:
#endif
    ldx #COL_CYAN
    cmp #CH
    beq !hdl_set_col+
    ldx #COL_WHITE
    cmp #CK
    beq !hdl_set_col+
    ldx #COL_LGREY
!hdl_set_col:
    stx zp_text_color
    rts
!hdl_char:
#if HAL_SCREEN_HELP_LINE_USES_API
    jsr hal_screen_put_char
    rts
#else
    ldy #0
    sta (zp_screen_lo),y
#if HAL_SCREEN_HELP_LINE_USES_COLOR_MAP
    lda zp_text_color
    and #$0f
    tax
    lda hal_screen_color_attr,x
#else
    lda zp_text_color
#endif
    sta (zp_color_lo),y
    inc zp_screen_lo
    bne !+
    inc zp_screen_hi
!:  inc zp_color_lo
    bne !+
    inc zp_color_hi
!:  rts
#endif
!hdl_tab:
    // Tab-to-column: next byte is target column
    inc zp_temp0                // skip past $fc
    ldy zp_temp0
    lda (zp_ptr0),y             // read target column
    sta zp_cursor_col
    jsr hal_screen_set_cursor   // recompute screen/color pointers
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
// Draws screen-width border: + then (SCREEN_COLS-2) dashes then +
help_draw_hborder:
    sta zp_cursor_row
    lda #COL_GREY
    sta zp_text_color
    lda #0
    sta zp_cursor_col
    lda #BOX_TL                     // + (corner)
    jsr hal_screen_put_char
    ldx #HELP_FRAME_HSEG_COUNT
!hb_dash:
    lda #BOX_H                      // - (horizontal)
    jsr hal_screen_put_char
    dex
    bne !hb_dash-
    lda #BOX_TR                     // + (corner)
    jmp hal_screen_put_char             // tail call

// Local footer strings remain in the overlay.
#if HAL_INPUT_HELP_FOOTER_USES_ESC_STOP
uh_press_key_str: .text "SPACE/RETURN/Q/ESC/STOP done" ; .byte 0
uh_next_key_str: .text "SPACE/RETURN next Q/ESC/STOP quit" ; .byte 0
#else
uh_press_key_str: .text "SPACE/RETURN/Q/RUN/STOP done" ; .byte 0
uh_next_key_str: .text "SPACE/RETURN next Q/RUN/STOP quit" ; .byte 0
#endif

uh_msg_hist_title: .text "Message History" ; .byte 0
uh_msg_hist_none:  .text "(no messages yet)" ; .byte 0

.label ui_help_show_paged = ui_help_display
