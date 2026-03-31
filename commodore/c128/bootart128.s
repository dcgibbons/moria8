#importonce
// bootart128.s — Generated C128 boot-art helper
//
// Loads into Bank 0 RAM at $2800. Entry points:
//   $2800: show    — save the overwritten alternate-charset slice and render poster
//   $2803: restore — restore the saved alternate-charset bytes

#import "../out/c128/bootart128.inc"

.pc = $2800 "Bootart128"

    jmp bootart_show
    jmp bootart_restore

.const VDC_ADDR_REG         = $d600
.const VDC_DATA_REG         = $d601
.const VDC_SCREEN_BASE      = $0000
.const VDC_ATTRIB_BASE      = $0800
.const VDC_ALT_CHARSET_BASE = $3000
.const VDC_COLS             = 80
.const VDC_ROWS             = 25
.const CUSTOM_CODE_FIRST    = 0
.const SC_SPACE             = $20
.const ATTR_BLACK_PLAIN     = $00
.const VDC_CLEAR_PAGES      = 8

.label zp_temp0 = $02
.label zp_temp1 = $03
.label zp_ptr0 = $06
.label zp_ptr0_hi = $07

bootart_show:
    jsr set_vdc_bg_black
    jsr save_original_alt_glyphs
    jsr upload_custom_alt_glyphs
    jsr render_generated_poster
    rts

bootart_restore:
    jsr clear_bootart_screen
    jsr restore_original_alt_glyphs
    rts

set_vdc_bg_black:
    ldx #26
    jsr vdc_read_reg
    and #$0f
    sta zp_temp0
    lda #$00
    ora zp_temp0
    ldx #26
    jsr vdc_write_reg
    rts

save_original_alt_glyphs:
    lda #<saved_alt_glyphs
    sta zp_ptr0
    lda #>saved_alt_glyphs
    sta zp_ptr0_hi
    lda #>custom_charset_vdc_base
    ldy #<custom_charset_vdc_base
    jsr vdc_set_update_addr

!loop:
    lda zp_ptr0_hi
    cmp #>saved_alt_glyphs_end
    bne !copy+
    lda zp_ptr0
    cmp #<saved_alt_glyphs_end
    beq !done+
!copy:
    jsr vdc_read_data
    ldy #0
    sta (zp_ptr0),y
    inc zp_ptr0
    bne !loop-
    inc zp_ptr0_hi
    jmp !loop-
!done:
    rts

upload_custom_alt_glyphs:
    lda #<bootart_charset_data
    sta zp_ptr0
    lda #>bootart_charset_data
    sta zp_ptr0_hi
    lda #>custom_charset_vdc_base
    ldy #<custom_charset_vdc_base
    jsr vdc_set_update_addr

!loop:
    lda zp_ptr0_hi
    cmp #>bootart_charset_data_end
    bne !copy+
    lda zp_ptr0
    cmp #<bootart_charset_data_end
    beq !done+
!copy:
    ldy #0
    lda (zp_ptr0),y
    jsr vdc_write_data
    inc zp_ptr0
    bne !loop-
    inc zp_ptr0_hi
    jmp !loop-
!done:
    rts

restore_original_alt_glyphs:
    lda #<saved_alt_glyphs
    sta zp_ptr0
    lda #>saved_alt_glyphs
    sta zp_ptr0_hi
    lda #>custom_charset_vdc_base
    ldy #<custom_charset_vdc_base
    jsr vdc_set_update_addr

!loop:
    lda zp_ptr0_hi
    cmp #>saved_alt_glyphs_end
    bne !copy+
    lda zp_ptr0
    cmp #<saved_alt_glyphs_end
    beq !done+
!copy:
    ldy #0
    lda (zp_ptr0),y
    jsr vdc_write_data
    inc zp_ptr0
    bne !loop-
    inc zp_ptr0_hi
    jmp !loop-
!done:
    rts

render_generated_poster:
    lda #<bootart_screen_data
    sta zp_ptr0
    lda #>bootart_screen_data
    sta zp_ptr0_hi
    lda #>VDC_SCREEN_BASE
    ldy #<VDC_SCREEN_BASE
    jsr vdc_set_update_addr
!screen_loop:
    lda zp_ptr0_hi
    cmp #>bootart_screen_data_end
    bne !screen_copy+
    lda zp_ptr0
    cmp #<bootart_screen_data_end
    beq !screen_done+
!screen_copy:
    ldy #0
    lda (zp_ptr0),y
    jsr vdc_write_data
    inc zp_ptr0
    bne !screen_loop-
    inc zp_ptr0_hi
    jmp !screen_loop-
!screen_done:

    lda #<bootart_attr_data
    sta zp_ptr0
    lda #>bootart_attr_data
    sta zp_ptr0_hi
    lda #>VDC_ATTRIB_BASE
    ldy #<VDC_ATTRIB_BASE
    jsr vdc_set_update_addr
!attr_loop:
    lda zp_ptr0_hi
    cmp #>bootart_attr_data_end
    bne !attr_copy+
    lda zp_ptr0
    cmp #<bootart_attr_data_end
    beq !attr_done+
!attr_copy:
    ldy #0
    lda (zp_ptr0),y
    jsr vdc_write_data
    inc zp_ptr0
    bne !attr_loop-
    inc zp_ptr0_hi
    jmp !attr_loop-
!attr_done:
    rts

clear_bootart_screen:
    lda #>VDC_SCREEN_BASE
    ldy #<VDC_SCREEN_BASE
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg
    lda #VDC_CLEAR_PAGES
    sta zp_temp0
    ldy #0
    lda #SC_SPACE
!screen_fill:
    jsr vdc_wait
    sta VDC_DATA_REG
    dey
    bne !screen_fill-
    dec zp_temp0
    bne !screen_fill-

    lda #>VDC_ATTRIB_BASE
    ldy #<VDC_ATTRIB_BASE
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg
    lda #VDC_CLEAR_PAGES
    sta zp_temp0
    ldy #0
    lda #ATTR_BLACK_PLAIN
!attr_fill:
    jsr vdc_wait
    sta VDC_DATA_REG
    dey
    bne !attr_fill-
    dec zp_temp0
    bne !attr_fill-
    rts

vdc_wait:
    bit VDC_ADDR_REG
    bpl vdc_wait
    rts

vdc_select_reg:
    jsr vdc_wait
    stx VDC_ADDR_REG
    jsr vdc_wait
    rts

vdc_write_reg:
    jsr vdc_select_reg
    sta VDC_DATA_REG
    rts

vdc_read_reg:
    jsr vdc_select_reg
    lda VDC_DATA_REG
    rts

vdc_set_update_addr:
    pha
    ldx #18
    pla
    jsr vdc_write_reg
    tya
    ldx #19
    jsr vdc_write_reg
    rts

vdc_write_data:
    ldx #31
    jsr vdc_write_reg
    rts

vdc_read_data:
    ldx #31
    jsr vdc_read_reg
    rts

.align 16
bootart_charset_data:
    .import binary "../out/c128/bootart128_charset.bin"

.assert "bootart charset bytes match generated metadata", * - bootart_charset_data == BOOTART_CHARSET_BYTES, true
.label bootart_charset_data_end = *

bootart_screen_data:
    .import binary "../out/c128/bootart128_screen.bin"

.assert "bootart screen map is 2000 bytes", * - bootart_screen_data == 2000, true
.label bootart_screen_data_end = *

bootart_attr_data:
    .import binary "../out/c128/bootart128_attr.bin"

.assert "bootart attr map is 2000 bytes", * - bootart_attr_data == 2000, true
.label bootart_attr_data_end = *

.label custom_charset_vdc_base = VDC_ALT_CHARSET_BASE + (CUSTOM_CODE_FIRST * 16)
.align 16
.label saved_alt_glyphs = *
.label saved_alt_glyphs_end = saved_alt_glyphs + BOOTART_CHARSET_BYTES
.assert "bootart workspace stays below $7000", saved_alt_glyphs_end <= $7000, true
