#importonce
// test_vdc_attr128.s — VDC attribute-mode regression guard
//
// Verifies that attribute writes keep bit 7 set (alternate charset mode),
// which is required for the expected mixed-case/screen-code glyph mapping.

#import "../../../../core/zeropage.s"
#import "../screen_vdc.s"

.const COL_WHITE = 1
.const COL_GREY = 12
.const COL_LGREY = 15

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
    beq !+
    jmp test_fail
!:

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
    beq !+
    jmp test_fail
!:

    // Lowercase PETSCII in the string path must translate to VDC Set 1.
    lda #0
    sta zp_cursor_row
    lda #4
    sta zp_cursor_col
    lda #<test_lower_str
    sta zp_ptr0
    lda #>test_lower_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #0
    sta zp_cursor_row
    lda #5
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    cmp #$02                // PETSCII 'b' -> VDC Set 1 lowercase 'b'
    beq !+
    jmp test_fail
!:

    // Embedded direct VDC bytes used by packed UI data must still pass through.
    lda #0
    sta zp_cursor_row
    lda #8
    sta zp_cursor_col
    lda #<test_direct_vdc_str
    sta zp_ptr0
    lda #>test_direct_vdc_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #0
    sta zp_cursor_row
    lda #8
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    cmp #$03
    beq !+
    jmp test_fail
!:

    // Shared decimal formatting must also write the expected VDC digit codes.
    lda #0
    sta zp_cursor_row
    lda #10
    sta zp_cursor_col
    lda #$15
    sta zp_temp0
    lda #$27
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #0
    sta zp_cursor_row
    lda #10
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    cmp #$31
    bne test_fail
    jsr vdc_read_reg
    cmp #$30
    bne test_fail
    jsr vdc_read_reg
    cmp #$30
    bne test_fail
    jsr vdc_read_reg
    cmp #$30
    bne test_fail
    jsr vdc_read_reg
    cmp #$35
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
    beq !+
    jmp test_fail
!:

    // Grey and light grey must not collapse on C128 VDC.
    ldx #COL_GREY
    lda vic_to_vdc_color,x
    cmp #VDC_DGREY
    beq !+
    jmp test_fail
!:
    sta grey_attr

    ldx #COL_LGREY
    lda vic_to_vdc_color,x
    cmp #VDC_LGREY
    beq !+
    jmp test_fail
!:
    cmp grey_attr
    bne !+
    jmp test_fail
!:

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass

test_space_str: .text "A B" ; .byte 0
test_lower_str: .text "Ab" ; .byte 0
test_direct_vdc_str: .byte $03, 0
attr_byte: .byte 0
grey_attr: .byte 0
