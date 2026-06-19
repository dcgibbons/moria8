// bootsect128.s — Native C128 boot sector for the mixed-platform dual-entry disk
//
// Boot protocol:
// - sector is patched into Track 1 / Sector 0
// - native C128 KERNAL loads it to $0B00 and executes the code there
// - code executes BASIC command: BOOT"BOOT128",U<current device>

.pc = $0b00 "BootSector"
    .text "CBM"
    .word $0000              // no chained sectors from Track 1 / Sector 1
    .byte $00                // bank
    .byte $00                // block count

    .text "MORIA8 C128"
    .byte 0

    .byte 0                  // no implicit filename; custom code runs instead

boot_code:
    lda $ba                     // KERNAL current device from the boot sector
    cmp #8
    bcc !default_device+
    cmp #31
    bcc !store_device+
!default_device:
    lda #8
!store_device:
    sta boot_device

    ldx #0
!copy_prefix:
    lda boot_cmd_prefix,x
    beq !append_device+
    sta boot_cmd,x
    inx
    bne !copy_prefix-

!append_device:
    lda boot_device
    cmp #10
    bcc !one_digit+
    cmp #20
    bcc !ten+
    cmp #30
    bcc !twenty+
    lda #$33                    // "3"
    sta boot_cmd,x
    inx
    lda boot_device
    sec
    sbc #30
    jmp !ones+
!twenty:
    lda #$32                    // "2"
    sta boot_cmd,x
    inx
    lda boot_device
    sec
    sbc #20
    jmp !ones+
!ten:
    lda #$31                    // "1"
    sta boot_cmd,x
    inx
    lda boot_device
    sec
    sbc #10
    jmp !ones+
!one_digit:
    lda boot_device
!ones:
    clc
    adc #$30
    sta boot_cmd,x
    inx
    lda #0
    sta boot_cmd,x

    ldx #<boot_cmd - 1
    ldy #>boot_cmd
    jmp $afa5                // BASIC execute-a-line

boot_cmd_prefix:
    .text "BOOT"
    .byte $22
    .text "BOOT128"
    .byte $22
    .text ",U"
    .byte 0
boot_device:
    .byte 8
boot_cmd:
    .fill 18, 0

.assert "boot sector fits in 256 bytes", * <= $0c00, true
