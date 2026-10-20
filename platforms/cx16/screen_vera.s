// screen_vera.s — Commander X16 VERA 80x24 text screen backend (in 80x30 mode).
//
// VERA text RAM is at VRAM $1B000 with 256-byte row stride:
//   even offset = screen code, odd offset = color attribute (bg<<4 | fg).
// All 12 hal_screen_* exports plus screen_flash_at and numeric_format.s.

#import "palette_consts.s"
#import "hal/layout.s"

.const SCREEN_COLS = hal_layout_screen_cols
.const SCREEN_ROWS = hal_layout_screen_rows
.const VIEWPORT_X  = hal_layout_viewport_x
.const VIEWPORT_Y  = hal_layout_viewport_y
.const VIEWPORT_W  = hal_layout_viewport_w
.const VIEWPORT_H  = hal_layout_viewport_h
.const MSG_ROW     = hal_layout_msg_row
.const STATUS_ROW  = hal_layout_status_row
.const INPUT_ROW   = hal_layout_input_row
.const hal_screen_full_clear_uses_bulk = false
.const hal_screen_full_clear_uses_blanked_bulk = true
#define HAL_SCREEN_FULL_CLEAR_USES_BLANKED_BULK
.const hal_screen_box_vertical_char = $21
.const hal_screen_help_line_uses_api = true
.const hal_screen_help_line_uses_color_map = false
.const hal_screen_spell_bolt_flash_sets_color = false
#define HAL_SCREEN_HELP_LINE_USES_API

.assert "HAL layout screen cols", SCREEN_COLS, hal_layout_screen_cols
.assert "HAL layout screen rows", SCREEN_ROWS, hal_layout_screen_rows
.assert "HAL layout viewport x", VIEWPORT_X, hal_layout_viewport_x
.assert "HAL layout viewport y", VIEWPORT_Y, hal_layout_viewport_y
.assert "HAL layout viewport width", VIEWPORT_W, hal_layout_viewport_w
.assert "HAL layout viewport height", VIEWPORT_H, hal_layout_viewport_h
.assert "HAL layout message row", MSG_ROW, hal_layout_msg_row
.assert "HAL layout status row", STATUS_ROW, hal_layout_status_row
.assert "HAL layout input row", INPUT_ROW, hal_layout_input_row

.const VERA_ADDR_L = $9f20
.const VERA_ADDR_M = $9f21
.const VERA_ADDR_H = $9f22
.const VERA_DATA0  = $9f23
.const VERA_CTRL   = $9f25
.const X16_SCREEN_MODE = $ff5f
.const X16_SCREEN_SET_CHARSET = $ff62

.const VERA_TEXT_BASE_LO   = $00
.const VERA_TEXT_BASE_MID  = $b0
.const VERA_TEXT_BASE_HIGH = $01
.const VERA_TEXT_ROW_STRIDE = 256
.const X16_MODE_80X30 = 1
.const X16_CHARSET_PET_UPPER_LOWER = 3
.const VERA_INC_0 = $00
.const VERA_INC_1 = $10
.const VERA_BG_BLACK = $00
.const SC_SPACE = $20
.const SC_REVERSE_SPACE = $a0

.label zp_screen_mid = zp_vol_6

.label hal_screen_init = screen_init
.label hal_screen_clear = screen_clear
.label hal_screen_clear_row = screen_clear_row
.label hal_screen_put_char = screen_put_char
.label hal_screen_put_string = screen_put_string
.label hal_screen_put_char_at = screen_put_char_at
.label hal_screen_set_cursor = screen_set_cursor
.label hal_screen_set_color = screen_set_color
.label hal_screen_blank = screen_noop
.label hal_screen_unblank = screen_noop
.label hal_screen_begin_bulk = screen_noop
.label hal_screen_end_bulk = screen_noop

screen_noop:
    rts

screen_init:
    stz VERA_CTRL
    lda #X16_MODE_80X30
    clc
    jsr X16_SCREEN_MODE
    lda #X16_CHARSET_PET_UPPER_LOWER
    jsr X16_SCREEN_SET_CHARSET
    // Clear all 30 physical VERA text rows on init so rows 24-29 have no KERNAL banner residue.
    stz zp_cursor_row
!init_row:
    lda zp_cursor_row
    jsr screen_clear_row
    inc zp_cursor_row
    lda zp_cursor_row
    cmp #30
    bcc !init_row-
    stz zp_cursor_row
    rts

screen_set_color:
    and #$0f
    sta zp_text_color
    rts

screen_clear:
    stz sc_row_tmp
!row:
    lda sc_row_tmp
    jsr screen_clear_row
    inc sc_row_tmp
    lda sc_row_tmp
    cmp #SCREEN_ROWS
    bcc !row-
    lda zp_ui_dirty
    ora #%10000001
    sta zp_ui_dirty
    rts
sc_row_tmp: .byte 0

// screen_clear_row — Clear row A (0..29) to spaces
// Input: A = row number. Clobbers: A, X
screen_clear_row:
    jsr screen_row_addr
    jsr vera_set_addr_inc1
    lda zp_text_color
    and #$0f
    tax
    lda #SC_SPACE
    ldy #SCREEN_COLS
!loop:
    sta VERA_DATA0
    stx VERA_DATA0
    dey
    bne !loop-
    rts

// screen_put_char_at — Write screen code A at (X = col, Y = row), preserving cursor
screen_put_char_at:
    sta spca_char
    lda zp_cursor_row
    pha
    lda zp_cursor_col
    pha
    sty zp_cursor_row
    stx zp_cursor_col
    jsr screen_set_cursor
    jsr vera_set_addr_inc1
    lda spca_char
    jsr vera_put_char_with_attr
    pla
    sta zp_cursor_col
    pla
    sta zp_cursor_row
    rts
spca_char: .byte 0

// screen_put_char — Write screen code A at cursor, advance right.
// Preserves: X (required by numeric_format_emit_screen and core callers).
screen_put_char:
    phx
    pha
    jsr screen_set_cursor
    jsr vera_set_addr_inc1
    pla
    jsr vera_put_char_with_attr
    inc zp_cursor_col
    plx
    rts

// screen_put_string — Write null-terminated screen codes at (zp_ptr0)
screen_put_string:
    jsr screen_set_cursor
    jsr vera_set_addr_inc1
    ldy #0
    ldx zp_cursor_col
!loop:
    lda (zp_ptr0),y
    beq !done+
    jsr vera_put_char_with_attr
    iny
    inx
    cpx #SCREEN_COLS
    bne !loop-
!done:
    stx zp_cursor_col
    rts

vera_put_char_with_attr:
    sta VERA_DATA0
    lda zp_text_color
    and #$0f
    sta VERA_DATA0
    rts

screen_set_cursor:
    lda zp_cursor_row
    jsr screen_row_addr
    lda zp_cursor_col
    asl
    sta zp_screen_lo
    rts

// Input: A = row. Output: zp_screen_hi:mid:lo = VERA text row base ($1B000 + row*$100).
screen_row_addr:
    clc
    adc #VERA_TEXT_BASE_MID
    sta zp_screen_mid
    stz zp_screen_lo
    lda #VERA_TEXT_BASE_HIGH
    sta zp_screen_hi
    rts

vera_set_addr_inc1:
    stz VERA_CTRL
    lda zp_screen_lo
    sta VERA_ADDR_L
    lda zp_screen_mid
    sta VERA_ADDR_M
    lda zp_screen_hi
    ora #VERA_INC_1
    sta VERA_ADDR_H
    rts

#import "../../core/numeric_format.s"

// screen_flash_at — Briefly flash '*' at (X = row, Y = column), then restore
// Used by bolt animation in spell_effects.s.
// Clobbers: A, X, Y
screen_flash_at:
    stx sfa_row
    sty sfa_col
    stz VERA_CTRL
    tya
    asl
    sta VERA_ADDR_L
    txa
    clc
    adc #VERA_TEXT_BASE_MID
    sta VERA_ADDR_M
    lda #(VERA_TEXT_BASE_HIGH | VERA_INC_1)
    sta VERA_ADDR_H
    lda VERA_DATA0
    sta sfa_char
    lda VERA_DATA0
    sta sfa_attr

    lda sfa_col
    asl
    sta VERA_ADDR_L
    lda #$2a                // '*'
    sta VERA_DATA0
    lda zp_text_color
    and #$0f
    sta VERA_DATA0

    ldx #$20
!d_o:
    ldy #$00
!d_i:
    dey
    bne !d_i-
    dex
    bne !d_o-

    stz VERA_CTRL
    lda sfa_col
    asl
    sta VERA_ADDR_L
    lda sfa_row
    clc
    adc #VERA_TEXT_BASE_MID
    sta VERA_ADDR_M
    lda #(VERA_TEXT_BASE_HIGH | VERA_INC_1)
    sta VERA_ADDR_H
    lda sfa_char
    sta VERA_DATA0
    lda sfa_attr
    sta VERA_DATA0
    rts

sfa_row:  .byte 0
sfa_col:  .byte 0
sfa_char: .byte 0
sfa_attr: .byte 0
