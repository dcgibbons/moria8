// screen_vera.s - minimal Commander X16 VERA text backend

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

.const VERA_ADDR_L = $9f20
.const VERA_ADDR_M = $9f21
.const VERA_ADDR_H = $9f22
.const VERA_DATA0  = $9f23
.const VERA_CTRL   = $9f25
.const X16_SCREEN_MODE = $ff5f

.const VERA_TEXT_BASE_LO = $00
.const VERA_TEXT_BASE_MID = $b0
.const VERA_TEXT_BASE_HIGH = $01
.const VERA_TEXT_ROW_STRIDE = 256
.const X16_MODE_80X30 = 1
.const VERA_INC_1 = $10
.const SC_SPACE = $20

.label zp_cursor_row = $22
.label zp_cursor_col = $23
.label zp_text_color = $24
.label zp_ptr0 = $25
.label zp_ptr0_hi = $26
.label zp_screen_lo = $27
.label zp_screen_mid = $28
.label zp_screen_hi = $29
.label zp_tmp0 = $2a
.label zp_tmp1 = $2b
.label zp_ptr1 = $2c
.label zp_ptr1_hi = $2d
.label zp_kernal_status = $90

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
    lda #0
    sta VERA_CTRL
    lda #X16_MODE_80X30
    clc
    jsr X16_SCREEN_MODE     // Force 80x30 instead of inheriting NVRAM/default mode.
    rts

screen_set_color:
    sta zp_text_color
    rts

screen_clear:
    lda #0
    sta zp_cursor_row
!row:
    lda zp_cursor_row
    jsr screen_clear_row
    inc zp_cursor_row
    lda zp_cursor_row
    cmp #SCREEN_ROWS
    bcc !row-
    rts

// screen_clear_row — Clear a single VERA text row to spaces
// Input: A = row number
screen_clear_row:
    sta zp_tmp0
    lda #0
    sta zp_tmp1
    lda zp_tmp0
    jsr screen_row_addr
    jsr vera_set_addr_inc1
    ldx #SCREEN_COLS
!loop:
    lda #SC_SPACE
    sta VERA_DATA0
    lda zp_text_color
    sta VERA_DATA0
    dex
    bne !loop-
    rts

// screen_put_char_at — Write one char at specific (row, col) without moving cursor
// Input:  A = screen code
//         X = column
//         Y = row
//         zp_text_color = color
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
    sta VERA_DATA0
    lda zp_text_color
    sta VERA_DATA0
    pla
    sta zp_cursor_col
    pla
    sta zp_cursor_row
    rts
spca_char: .byte 0

screen_put_char:
    pha
    jsr screen_set_cursor
    jsr vera_set_addr_inc1
    pla
    sta VERA_DATA0
    lda zp_text_color
    sta VERA_DATA0
    inc zp_cursor_col
    rts

screen_put_string:
    jsr screen_set_cursor
    jsr vera_set_addr_inc1
    ldy #0
    ldx zp_cursor_col
!loop:
    lda (zp_ptr0),y
    beq !done+
    sta VERA_DATA0
    lda zp_text_color
    sta VERA_DATA0
    iny
    inx
    cpx #SCREEN_COLS
    bne !loop-
!done:
    tya
    clc
    adc zp_cursor_col
    sta zp_cursor_col
    rts

screen_set_cursor:
    lda zp_cursor_row
    jsr screen_row_addr
    lda zp_cursor_col
    asl
    clc
    adc zp_screen_lo
    sta zp_screen_lo
    bcc !done+
    inc zp_screen_mid
    bne !done+
    inc zp_screen_hi
!done:
    rts

// Input: A = row. Output: zp_screen_hi:mid:lo = VERA text row address.
screen_row_addr:
    sta zp_tmp0
    lda #VERA_TEXT_BASE_LO
    sta zp_screen_lo
    lda #VERA_TEXT_BASE_MID
    sta zp_screen_mid
    lda #VERA_TEXT_BASE_HIGH
    sta zp_screen_hi

    lda zp_tmp0
    beq !done+
!add:
    clc
    lda zp_screen_lo
    adc #<VERA_TEXT_ROW_STRIDE
    sta zp_screen_lo
    lda zp_screen_mid
    adc #>VERA_TEXT_ROW_STRIDE
    sta zp_screen_mid
    bcc !next+
    inc zp_screen_hi
!next:
    dec zp_tmp0
    bne !add-
!done:
    rts

vera_set_addr_inc1:
    lda zp_screen_lo
    sta VERA_ADDR_L
    lda zp_screen_mid
    sta VERA_ADDR_M
    lda zp_screen_hi
    ora #VERA_INC_1
    sta VERA_ADDR_H
    rts
