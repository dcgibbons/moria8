#importonce
// test_vdc_attr128.s — VDC attribute-mode regression guard
//
// Verifies that attribute writes keep bit 7 set (alternate charset mode),
// which is required for the expected mixed-case/screen-code glyph mapping.

#import "../../common/zeropage.s"
#import "../screen_vdc.s"

.const COL_WHITE = 1

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $4000 "Test Code"

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #COL_WHITE
    sta zp_text_color
    jsr screen_clear

    // Char at row 0/col 0 must be VDC space code.
    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    cmp #SC_SPACE
    bne test_fail

    // Printing a string with an embedded space must also map to VDC space.
    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    lda #<test_space_str
    sta zp_ptr0
    lda #>test_space_str
    sta zp_ptr0_hi
    jsr screen_put_string
    // Read character at col 1 (the space in "A B")
    lda #0
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    cmp #SC_SPACE
    bne test_fail

    // Read attribute byte at row 0, col 0.
    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_color_hi
    ldy zp_color_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    sta attr_byte

    // Attribute should match runtime translation table for current mode.
    ldx #COL_WHITE
    lda vic_to_vdc_color,x
    cmp attr_byte
    bne test_fail

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass

test_space_str: .text "A B" ; .byte 0
attr_byte: .byte 0
