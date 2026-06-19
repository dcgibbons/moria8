#importonce
// bootart128.s — C128 VDC boot art (511 custom tiles across 512 charset slots)
//
// Hardware Standard (16K VDC):
// - Index Map:     $0000 - $07CF
// - Attribute Map: $0800 - $0FCF
// - Charset RAM:   $2000 - $3FFF (16 bytes per character slot)

#import "../../../build/c128/bootart128.inc"

.pc = $2800 "Bootart128"

    jmp bootart_show
    jmp bootart_restore

.const VDC_ADDR_REG         = $d600
.const VDC_DATA_REG         = $d601
.const VDC_SCREEN_VDC_BASE  = $0000
.const VDC_ATTR_VDC_BASE    = $0800
.const VDC_CHARSET_VDC_BASE = $2000
.const KERNAL_JDLCHR        = $ff62
.const VDC_ATTR_MODE        = %01000000

.label zp_ptr0 = $06
.label zp_ptr0_hi = $07
.label vdc_page_count = $08
.label vdc_reg25_work = $09

bootart_show:
    jsr save_vdc_state
    jsr set_vdc_bg_black

    // 1. Point the VDC character generator at the full 512-slot charset in
    // VDC RAM while preserving the active 80-column timing geometry.
    ldx #28
    lda #$20
    jsr vdc_write_reg

    // R12/13: Display Base ($0000)
    ldx #12
    lda #$00
    jsr vdc_write_reg
    ldx #13
    lda #$00
    jsr vdc_write_reg

    // R20/21: Attribute Base ($0800)
    ldx #20
    lda #$08
    jsr vdc_write_reg
    ldx #21
    lda #$00
    jsr vdc_write_reg
    
    // 2. Clear Screen Index Map (at $0000)
    lda #$00
    ldy #$00
    jsr vdc_set_update_addr
    ldx #8
    lda #0
    jsr fill_vdc_block 
    
    // 3. Upload the generated charset to VDC $2000.
    // The asset always provides 512 charset slots * 16 bytes = 8192 bytes = 32 pages.
    lda #<bootart_charset_data
    sta zp_ptr0
    lda #>bootart_charset_data
    sta zp_ptr0_hi
    lda #>VDC_CHARSET_VDC_BASE
    ldy #<VDC_CHARSET_VDC_BASE
    jsr vdc_set_update_addr
    lda #32
    jsr upload_pages

    // 4. Upload Screen Index Map ($0000)
    lda #<bootart_screen_data
    sta zp_ptr0
    lda #>bootart_screen_data
    sta zp_ptr0_hi
    lda #>VDC_SCREEN_VDC_BASE
    ldy #<VDC_SCREEN_VDC_BASE
    jsr vdc_set_update_addr
    lda #8 // 2000 bytes
    jsr upload_pages

    // 5. Upload Attribute Map ($0800)
    lda #<bootart_attr_data
    sta zp_ptr0
    lda #>bootart_attr_data
    sta zp_ptr0_hi
    lda #>VDC_ATTR_VDC_BASE
    ldy #<VDC_ATTR_VDC_BASE
    jsr vdc_set_update_addr
    lda #8 // 2000 bytes
    jsr upload_pages

    // 6. Keep the existing mode geometry and only force per-character
    // attributes on. Writing a fixed reg25 value here breaks the live
    // 80-column framing.
    ldx #25
    jsr vdc_read_reg
    ora #VDC_ATTR_MODE
    sta vdc_reg25_work
    lda vdc_reg25_work
    jsr vdc_write_reg
    rts

bootart_restore:
    jsr restore_vdc_state
    // Reset to Standard ROM Font and Clear Screen
    lda #$00
    ldy #$00
    jsr vdc_set_update_addr
    ldx #8
    lda #$20
    jsr fill_vdc_block
    lda #$08
    ldy #$00
    jsr vdc_set_update_addr
    ldx #8
    lda #$00
    jsr fill_vdc_block
    jsr KERNAL_JDLCHR
    rts

save_vdc_state:
    ldx #12
    jsr vdc_read_reg
    sta vdc_orig_r12
    ldx #13
    jsr vdc_read_reg
    sta vdc_orig_r13
    ldx #20
    jsr vdc_read_reg
    sta vdc_orig_r20
    ldx #21
    jsr vdc_read_reg
    sta vdc_orig_r21
    ldx #25
    jsr vdc_read_reg
    sta vdc_orig_r25
    ldx #28
    jsr vdc_read_reg
    sta vdc_orig_r28
    rts

restore_vdc_state:
    ldx #12
    lda vdc_orig_r12
    jsr vdc_write_reg
    ldx #13
    lda vdc_orig_r13
    jsr vdc_write_reg
    ldx #20
    lda vdc_orig_r20
    jsr vdc_write_reg
    ldx #21
    lda vdc_orig_r21
    jsr vdc_write_reg
    ldx #25
    lda vdc_orig_r25
    jsr vdc_write_reg
    ldx #28
    lda vdc_orig_r28
    jsr vdc_write_reg
    rts

set_vdc_bg_black:
    ldx #26
    jsr vdc_read_reg
    and #$0f
    ora #$00
    ldx #26
    jsr vdc_write_reg
    rts

upload_pages:
    sta vdc_page_count
    ldx #31
    jsr vdc_select_reg
!loop:
    ldy #0
!inner:
    lda (zp_ptr0),y
    :vdc_wait_inlined()
    sta VDC_DATA_REG
    iny
    bne !inner-
    inc zp_ptr0_hi
    dec vdc_page_count
    bne !loop-
    rts

fill_vdc_block:
    stx vdc_page_count
    ldx #31
    jsr vdc_select_reg
!loop:
    ldy #0
!inner:
    :vdc_wait_inlined()
    sta VDC_DATA_REG
    iny
    bne !inner-
    dec vdc_page_count
    bne !loop-
    rts

.macro vdc_wait_inlined() {
!wait:
    bit VDC_ADDR_REG
    bpl !wait-
}

vdc_select_reg:
    :vdc_wait_inlined()
    stx VDC_ADDR_REG
    :vdc_wait_inlined()
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

.align 16
vdc_orig_r12:  .byte 0
vdc_orig_r13:  .byte 0
vdc_orig_r20:  .byte 0
vdc_orig_r21:  .byte 0
vdc_orig_r25:  .byte 0
vdc_orig_r28:  .byte 0

.align 16
bootart_charset_data:
    .import binary "../../../build/c128/bootart128_charset.bin"
bootart_screen_data:
    .import binary "../../../build/c128/bootart128_screen.bin"
bootart_attr_data:
    .import binary "../../../build/c128/bootart128_attr.bin"

.assert "bootart stays below $7000", * <= $7000, true
